import { describe, expect, test, vi } from "vitest";
import { buildFeedback } from "../src/shared/feedback.ts";
import { mergePhrases } from "../src/shared/memory.ts";
import { mockTutorReply } from "../src/shared/mockTutor.ts";
import { PatienceController } from "../src/shared/patience.ts";
import { buildInstructions, buildTurnDetection, speedForLevel } from "../src/shared/prompt.ts";
import { defaultSettings, parseSessionSettings } from "../src/shared/scenarios.ts";
import { detectStuck } from "../src/shared/stuck.ts";
import { containsBannedJudgement, questionCount } from "../src/shared/textRules.ts";
import type { LevelId, ScenarioId } from "../src/shared/types.ts";
import { confirmedLearnerTexts, partitionTurns } from "../src/shared/captions.ts";
import { initialProtoState, markNextResponseAsHint, reduceRealtimeEvent, UNRECOGNIZED_LEARNER, type RealtimeEffect } from "../src/voice/events.ts";

const scenarios: ScenarioId[] = ["interview", "daily", "business", "travel", "warmup"];
const levels: LevelId[] = ["beginner", "intermediate", "advanced"];
const samples = [
  null,
  "I worked in sales for three years and liked talking to customers.",
  "um",
  "um um uh",
  "I go to the office yesterday",
  "he go to school",
  "I am agree with the plan",
  "It was more better than before",
  "えーと、営業をしていました",
];

describe("mock tutor", () => {
  test("asks exactly one question and does not judge", () => {
    for (const scenarioId of scenarios) {
      for (const level of levels) {
        for (const userText of samples) {
          for (const hint of [false, true]) {
            const reply = mockTutorReply({
              scenarioId,
              level,
              userText,
              turnIndex: userText ? 1 : 0,
              hint,
              reusePhrases: [],
            });
            expect(questionCount(reply.text), reply.text).toBe(1);
            expect(containsBannedJudgement(reply.text), reply.text).toBe(false);
            expect(reply.text.length).toBeLessThan(280);
          }
        }
      }
    }
  });

  test("opens the interview and reuses a stuck phrase next time", () => {
    const first = mockTutorReply({
      scenarioId: "interview",
      level: "intermediate",
      userText: null,
      turnIndex: 0,
      hint: false,
      reusePhrases: [],
    });
    expect(first.text).toContain("Could you tell me a little about yourself?");
    const next = mockTutorReply({
      scenarioId: "interview",
      level: "intermediate",
      userText: null,
      turnIndex: 0,
      hint: false,
      reusePhrases: ["えーと、営業です"],
    });
    expect(next.text).toContain("えーと、営業です");
    expect(next.text).toContain("Could you try using it once today?");
  });

  test("recasts without calling it a mistake", () => {
    const reply = mockTutorReply({
      scenarioId: "daily",
      level: "beginner",
      userText: "I go to the park yesterday",
      turnIndex: 2,
      hint: false,
      reusePhrases: [],
    });
    expect(reply.text).toContain("you went yesterday");
    expect(reply.isHint).toBe(false);
  });
});

describe("stuck expressions and feedback", () => {
  test("records hesitation, Japanese, long pauses, and hints", () => {
    expect(detectStuck({ text: "I worked in sales.", pauseMs: 500, hintShown: false })).toBeNull();
    const hesitating = detectStuck({ text: "um um uh", pauseMs: 1000, hintShown: false });
    expect(hesitating?.reasons).toContain("hesitation");
    const japanese = detectStuck({ text: "えーと、営業です", pauseMs: 8000, hintShown: true });
    expect(japanese?.reasons).toEqual(expect.arrayContaining(["japanese", "hesitation", "long_pause", "hint_needed"]));
  });

  test("keeps feedback to one or two notes and skips a score", () => {
    const stuck = detectStuck({ text: "えーと、営業です", pauseMs: 8000, hintShown: true });
    const items = buildFeedback(["I go to the office yesterday", "えーと、営業です"], stuck ? [{ ...stuck, id: "1" }] : []);
    expect(items.length).toBeGreaterThan(0);
    expect(items.length).toBeLessThanOrEqual(2);
    for (const item of items) {
      expect(item.detailJa).not.toMatch(/点数|score|減点/i);
    }
    expect(items.some((item) => item.category === "grammar")).toBe(true);
    const empty = buildFeedback(["I worked in sales for three years."], []);
    expect(empty).toHaveLength(1);
    expect(empty[0]?.titleJa).toContain("増やしません");
  });

  test("merges phrases with the newest first", () => {
    expect(mergePhrases(["older"], [" newer ", "older"])).toEqual(["newer", "older"]);
  });
});

describe("prompt and turn taking", () => {
  test("locks the interviewer rules and a patient semantic VAD", () => {
    const settings = parseSessionSettings({
      ...defaultSettings(["budget"]),
      scenarioId: "interview",
      level: "beginner",
      vadMode: "semantic_vad",
      eagerness: "low",
    });
    const instructions = buildInstructions(settings);
    expect(instructions).toContain("job interviewer");
    expect(instructions).toContain("exactly one follow-up question");
    expect(instructions).toContain("Wait patiently");
    expect(instructions).toContain("switch to Japanese");
    expect(instructions).toContain("budget");
    expect(instructions).not.toMatch(/sk-/);
    const turn = buildTurnDetection(settings);
    expect(turn).toEqual({
      type: "semantic_vad",
      eagerness: "low",
      create_response: true,
      interrupt_response: true,
    });
    expect(speedForLevel("beginner")).toBe(0.9);
  });

  test("uses silence duration only for server VAD", () => {
    const settings = parseSessionSettings({ ...defaultSettings(), vadMode: "server_vad", silenceDurationMs: 1200 });
    expect(buildTurnDetection(settings)).toMatchObject({ type: "server_vad", silence_duration_ms: 1200 });
    expect(parseSessionSettings({ ...defaultSettings(), silenceDurationMs: 50 }).silenceDurationMs).toBe(800);
    expect(parseSessionSettings({ ...defaultSettings(), hintDelayMs: 1000 }).hintDelayMs).toBe(5000);
  });
});

describe("patience", () => {
  test("shows a visual backchannel while waiting, then one hint, and not during speech", () => {
    vi.useFakeTimers();
    const hints: number[] = [];
    const views: Array<{ status: string; backchannel: string | null }> = [];
    const controller = new PatienceController({
      hintDelayMs: 5000,
      maxHints: 2,
      waitReassuranceMs: 2000,
      listenBackchannelMs: 1000,
      onChange: (view) => views.push(view),
      onHint: () => hints.push(views.length),
    });
    controller.aiStarted();
    controller.aiFinished();
    expect(views.at(-1)).toMatchObject({ status: "waiting", backchannel: null });
    vi.advanceTimersByTime(2000);
    expect(views.at(-1)?.backchannel).toBe("Mm-hmm.");
    expect(hints).toHaveLength(0);
    vi.advanceTimersByTime(3000);
    expect(hints).toHaveLength(1);
    controller.aiStarted();
    controller.aiFinished();
    vi.advanceTimersByTime(10_000);
    expect(hints).toHaveLength(1);

    controller.userSpeechStarted();
    vi.advanceTimersByTime(1000);
    expect(views.at(-1)).toMatchObject({ status: "listening" });
    vi.advanceTimersByTime(10_000);
    expect(hints).toHaveLength(1);
    controller.userSpeechStopped();
    controller.aiStarted();
    controller.aiFinished();
    vi.advanceTimersByTime(5000);
    expect(hints).toHaveLength(2);
    controller.aiStarted();
    controller.aiFinished();
    controller.userSpeechStarted();
    controller.userSpeechStopped();
    controller.aiStarted();
    controller.aiFinished();
    vi.advanceTimersByTime(10_000);
    expect(hints).toHaveLength(2);
    controller.dispose();
    vi.useRealTimers();
  });
});

describe("realtime events", () => {
  test("finishes only after playback stops and keeps a single learner transcript", () => {
    let state = markNextResponseAsHint(initialProtoState());
    const effects: RealtimeEffect[] = [];
    const steps = [
      { type: "response.created", response: { id: "resp_1" } },
      { type: "response.output_audio.delta", response_id: "resp_1" },
      { type: "response.output_audio_transcript.delta", response_id: "resp_1", delta: "No rush. " },
      { type: "response.output_audio_transcript.done", response_id: "resp_1", transcript: "No rush. What do you do now?" },
      { type: "response.done", response: { id: "resp_1", status: "completed", output: [] } },
      { type: "output_audio_buffer.stopped" },
      { type: "input_audio_buffer.speech_started" },
      { type: "input_audio_buffer.speech_stopped" },
      { type: "conversation.item.input_audio_transcription.completed", item_id: "item_1", transcript: "I am an engineer." },
      { type: "conversation.item.input_audio_transcription.completed", item_id: "item_1", transcript: "I am an engineer." },
    ];
    for (const event of steps) {
      const next = reduceRealtimeEvent(state, event);
      state = next.state;
      effects.push(...next.effects);
    }
    expect(effects.filter((effect) => effect.type === "ai_finished")).toHaveLength(1);
    expect(effects.some((effect) => effect.type === "arm_playback_fallback")).toBe(true);
    expect(state.turns.find((turn) => turn.role === "ai")).toMatchObject({ isHint: true, text: "No rush. What do you do now?" });
    expect(state.turns.filter((turn) => turn.role === "learner")).toHaveLength(1);
  });

  test("does not arm a hint when the response is cancelled", () => {
    let state = initialProtoState();
    state = reduceRealtimeEvent(state, { type: "response.created", response: { id: "resp_2" } }).state;
    const done = reduceRealtimeEvent(state, { type: "response.done", response: { id: "resp_2", status: "cancelled" } });
    expect(done.effects).toEqual([]);
  });

  test("keeps AI, learner, AI order when the learner transcript arrives last", () => {
    let state = initialProtoState();
    const effects: RealtimeEffect[] = [];
    const steps = [
      { type: "response.output_audio_transcript.done", response_id: "resp_greet", transcript: "Could you tell me about yourself?" },
      { type: "input_audio_buffer.speech_started", item_id: "item_user" },
      { type: "response.created", response: { id: "resp_reply" } },
      { type: "response.output_audio_transcript.delta", response_id: "resp_reply", delta: "What " },
      { type: "response.output_audio_transcript.delta", response_id: "resp_reply", delta: "happened next?" },
      { type: "conversation.item.input_audio_transcription.delta", item_id: "item_user", delta: "I " },
      { type: "conversation.item.input_audio_transcription.delta", item_id: "item_user", delta: "work" },
      { type: "response.output_audio_transcript.done", response_id: "resp_reply", transcript: "What happened next?" },
      { type: "conversation.item.input_audio_transcription.completed", item_id: "item_user", transcript: "I work in sales." },
    ];
    for (const event of steps) {
      const next = reduceRealtimeEvent(state, event);
      state = next.state;
      effects.push(...next.effects);
    }
    expect(state.turns.map((turn) => turn.id)).toEqual(["resp_greet", "item_user", "resp_reply"]);
    expect(state.turns.map((turn) => turn.role)).toEqual(["ai", "learner", "ai"]);
    expect(state.turns[1]).toMatchObject({ text: "I work in sales.", finality: "final" });
    expect(effects.filter((effect) => effect.type === "learner_utterance")).toEqual([
      { type: "learner_utterance", text: "I work in sales.", itemId: "item_user" },
    ]);
    expect(confirmedLearnerTexts(state.turns)).toEqual(["I work in sales."]);
    const shown = partitionTurns(state.turns);
    expect(shown.live).toBeNull();
    expect(shown.history.map((turn) => turn.role)).toEqual(["ai", "learner", "ai"]);
  });

  test("inserts a late learner row before the assistant reply that raced ahead", () => {
    let state = initialProtoState();
    const steps = [
      { type: "response.output_audio_transcript.done", response_id: "resp_greet", transcript: "Hello." },
      { type: "response.output_item.added", response_id: "resp_greet", item: { id: "item_greet", role: "assistant" } },
      { type: "response.output_audio_transcript.delta", response_id: "resp_reply", delta: "What next?" },
      {
        type: "conversation.item.added",
        previous_item_id: "item_greet",
        item: { id: "item_user", role: "user" },
      },
      { type: "input_audio_buffer.committed", item_id: "item_user", previous_item_id: "item_greet" },
    ];
    for (const event of steps) state = reduceRealtimeEvent(state, event).state;
    expect(state.turns.map((turn) => turn.id)).toEqual(["resp_greet", "item_user", "resp_reply"]);
  });

  test("streams partial learner text without treating it as confirmed, and marks failure", () => {
    let state = initialProtoState();
    state = reduceRealtimeEvent(state, { type: "input_audio_buffer.speech_started", item_id: "item_user" }).state;
    const partial = reduceRealtimeEvent(state, {
      type: "conversation.item.input_audio_transcription.delta",
      item_id: "item_user",
      delta: "um",
    });
    expect(partial.effects.some((effect) => effect.type === "learner_utterance")).toBe(false);
    expect(confirmedLearnerTexts(partial.state.turns)).toEqual([]);
    expect(partitionTurns(partial.state.turns).live).toMatchObject({ text: "um", finality: "partial" });

    const failed = reduceRealtimeEvent(partial.state, {
      type: "conversation.item.input_audio_transcription.failed",
      item_id: "item_user",
    });
    expect(failed.state.turns[0]).toMatchObject({ text: "um", finality: "failed" });
    expect(confirmedLearnerTexts(failed.state.turns)).toEqual([]);
    expect(failed.effects.some((effect) => effect.type === "learner_utterance")).toBe(false);

    const empty = reduceRealtimeEvent(initialProtoState(), { type: "input_audio_buffer.speech_started", item_id: "item_empty" }).state;
    const unrecognized = reduceRealtimeEvent(empty, {
      type: "conversation.item.input_audio_transcription.failed",
      item_id: "item_empty",
    });
    expect(unrecognized.state.turns[0]).toMatchObject({ text: UNRECOGNIZED_LEARNER, finality: "failed" });
    expect(partitionTurns(unrecognized.state.turns).history).toHaveLength(1);
    expect(partitionTurns(unrecognized.state.turns).live).toBeNull();
  });
});
