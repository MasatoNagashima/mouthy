import { useEffect, useRef, useState } from "react";
import { buildFeedback } from "./shared/feedback.ts";
import { mockTutorReply } from "./shared/mockTutor.ts";
import { PatienceController } from "./shared/patience.ts";
import { buildHintInstructions, speedForLevel } from "./shared/prompt.ts";
import { LISTEN_BACKCHANNEL_MS, LONG_PAUSE_MS, WAIT_REASSURANCE_MS } from "./shared/scenarios.ts";
import { speakEnglish, stopSpeaking } from "./shared/speech.ts";
import { detectStuck } from "./shared/stuck.ts";
import type { ChatTurn, FeedbackItem, SessionSettings, StuckExpression, TalkStatus } from "./shared/types.ts";
import { initialProtoState, markNextResponseAsHint, reduceRealtimeEvent, type ProtoState } from "./voice/events.ts";
import { OpenAIRealtimeSession } from "./voice/openaiRealtime.ts";

export type TalkSession = {
  settings: SessionSettings;
  mode: "mock" | "voice";
  speak: boolean;
  nonce: number;
};

type Snapshot = {
  turns: ChatTurn[];
  stuck: StuckExpression[];
  feedback: FeedbackItem[];
};

export function useConversation(session: TalkSession | null) {
  const [turns, setTurns] = useState<ChatTurn[]>([]);
  const [stuck, setStuck] = useState<StuckExpression[]>([]);
  const [status, setStatus] = useState<TalkStatus>("connecting");
  const [backchannel, setBackchannel] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const draftRef = useRef("");
  const controls = useRef({
    send: () => {},
    onDraft: (_value: string) => {},
    end: (): Snapshot => ({ turns: [], stuck: [], feedback: [] }),
  });

  useEffect(() => {
    if (!session) return;
    let cancelled = false;
    const bag = {
      turns: [] as ChatTurn[],
      stuck: [] as StuckExpression[],
      aiTurnCount: 0,
      hintShownSinceLearner: false,
      aiFinishedAt: 0,
      speechStartedAt: 0,
      lastStatus: "connecting" as TalkStatus,
      epoch: 0,
      settings: session.settings,
      mode: session.mode,
      speak: session.speak,
    };
    const proto: { current: ProtoState } = { current: initialProtoState() };
    let patience: PatienceController | null = null;
    let voice: OpenAIRealtimeSession | null = null;
    let fallbackTimer = 0;

    const publishTurns = (next: ChatTurn[]) => {
      bag.turns = next;
      setTurns(next);
    };
    const clearFallback = () => {
      if (fallbackTimer) window.clearTimeout(fallbackTimer);
      fallbackTimer = 0;
    };

    patience = new PatienceController({
      hintDelayMs: session.settings.hintDelayMs,
      maxHints: session.settings.maxHints,
      waitReassuranceMs: WAIT_REASSURANCE_MS,
      listenBackchannelMs: LISTEN_BACKCHANNEL_MS,
      onChange: (view) => {
        if (cancelled) return;
        if (view.status === "waiting" && bag.lastStatus !== "waiting") bag.aiFinishedAt = Date.now();
        bag.lastStatus = view.status;
        setStatus(view.status);
        setBackchannel(view.backchannel);
      },
      onHint: () => {
        if (cancelled) return;
        if (bag.mode === "voice") {
          proto.current = markNextResponseAsHint(proto.current);
          bag.hintShownSinceLearner = true;
          voice?.requestHint(buildHintInstructions(bag.settings));
          return;
        }
        deliver(null, true);
      },
    });

    function deliver(userText: string | null, hint: boolean) {
      const current = patience;
      if (!current || cancelled) return;
      const epoch = ++bag.epoch;
      stopSpeaking();
      current.aiStarted();
      const reply = mockTutorReply({
        scenarioId: bag.settings.scenarioId,
        level: bag.settings.level,
        userText,
        turnIndex: bag.aiTurnCount,
        hint,
        reusePhrases: bag.settings.reusePhrases,
      });
      bag.aiTurnCount += 1;
      if (hint) bag.hintShownSinceLearner = true;
      publishTurns([
        ...bag.turns,
        { id: crypto.randomUUID(), role: "ai", text: reply.text, isHint: hint, pending: false },
      ]);
      const finish = () => {
        if (cancelled || bag.epoch !== epoch) return;
        current.aiFinished();
      };
      if (bag.speak) speakEnglish(reply.text, speedForLevel(bag.settings.level), finish);
      else finish();
    }

    function rememberLearner(text: string, pauseMs: number) {
      const note = detectStuck({
        text,
        pauseMs,
        hintShown: bag.hintShownSinceLearner,
        longPauseMs: LONG_PAUSE_MS,
      });
      bag.hintShownSinceLearner = false;
      if (!note) return;
      bag.stuck = [...bag.stuck, { ...note, id: crypto.randomUUID() }];
      setStuck(bag.stuck);
    }

    controls.current.onDraft = (value: string) => {
      draftRef.current = value;
      setDraft(value);
      if (session.mode !== "mock") return;
      if (value.trim()) patience?.userSpeechStarted();
      else patience?.resumeWaiting();
    };
    controls.current.send = () => {
      const text = draftRef.current.trim();
      if (!text || session.mode !== "mock") return;
      const pauseMs = bag.aiFinishedAt ? Date.now() - bag.aiFinishedAt : 0;
      publishTurns([...bag.turns, { id: crypto.randomUUID(), role: "learner", text, isHint: false, pending: false }]);
      rememberLearner(text, pauseMs);
      draftRef.current = "";
      setDraft("");
      deliver(text, false);
    };
    controls.current.end = () => {
      const learnerTexts = bag.turns.filter((turn) => turn.role === "learner").map((turn) => turn.text);
      return {
        turns: bag.turns.filter((turn) => turn.text.trim()),
        stuck: bag.stuck,
        feedback: buildFeedback(learnerTexts, bag.stuck),
      };
    };

    setTurns([]);
    setStuck([]);
    setError(null);
    setNotice(null);
    setBackchannel(null);
    draftRef.current = "";
    setDraft("");

    if (session.mode === "mock") {
      deliver(null, false);
    } else {
      setStatus("connecting");
      void startVoice();
    }

    async function startVoice() {
      try {
        const response = await fetch("/api/realtime/session", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(bag.settings),
        });
        const body = (await response.json().catch(() => ({}))) as { message?: string; token?: string };
        if (!response.ok || !body.token) {
          throw new Error(body.message || "音声セッションを開始できません。");
        }
        if (cancelled) return;
        voice = new OpenAIRealtimeSession({
          onOpen: () => voice?.requestResponse(),
          onConnectionError: (message) => {
            if (cancelled) return;
            setError(message);
            setStatus("error");
          },
          onEvent: (event) => {
            if (cancelled) return;
            const reduced = reduceRealtimeEvent(proto.current, event);
            proto.current = reduced.state;
            publishTurns(reduced.state.turns);
            for (const effect of reduced.effects) {
              if (effect.type === "ai_started") {
                clearFallback();
                patience?.aiStarted();
              } else if (effect.type === "ai_finished") {
                clearFallback();
                patience?.aiFinished();
              } else if (effect.type === "arm_playback_fallback") {
                clearFallback();
                fallbackTimer = window.setTimeout(() => {
                  if (cancelled || proto.current.settled) return;
                  proto.current = { ...proto.current, settled: true };
                  patience?.aiFinished();
                }, 8000);
              } else if (effect.type === "user_speech_started") {
                bag.speechStartedAt = Date.now();
                patience?.userSpeechStarted();
              } else if (effect.type === "user_speech_stopped") {
                patience?.userSpeechStopped();
              } else if (effect.type === "learner_utterance") {
                const pauseMs =
                  bag.speechStartedAt && bag.aiFinishedAt ? Math.max(0, bag.speechStartedAt - bag.aiFinishedAt) : 0;
                rememberLearner(effect.text, pauseMs);
              } else if (effect.type === "error") {
                setError(effect.message);
              } else if (effect.type === "notice") {
                setNotice(effect.message);
              }
            }
          },
        });
        await voice.connect(body.token);
      } catch (caught) {
        if (cancelled) return;
        setError(caught instanceof Error ? caught.message : "音声を開始できませんでした。");
        setStatus("error");
      }
    }

    return () => {
      cancelled = true;
      bag.epoch += 1;
      clearFallback();
      patience?.dispose();
      voice?.close();
      stopSpeaking();
    };
  }, [session]);

  return {
    turns,
    stuck,
    status,
    backchannel,
    error,
    notice,
    draft,
    setDraft: (value: string) => controls.current.onDraft(value),
    sendDraft: () => controls.current.send(),
    endConversation: () => controls.current.end(),
  };
}
