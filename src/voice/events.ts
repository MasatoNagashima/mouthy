import type { ChatTurn } from "../shared/types.ts";

export type RealtimeEffect =
  | { type: "ai_started" }
  | { type: "ai_finished" }
  | { type: "user_speech_started" }
  | { type: "user_speech_stopped" }
  | { type: "learner_utterance"; text: string; itemId: string }
  | { type: "error"; message: string }
  | { type: "notice"; message: string }
  | { type: "arm_playback_fallback" };

export type ProtoState = {
  turns: ChatTurn[];
  hintNext: boolean;
  pendingHint: boolean;
  activeResponseId: string | null;
  audioStarted: boolean;
  settled: boolean;
};

export function initialProtoState(): ProtoState {
  return {
    turns: [],
    hintNext: false,
    pendingHint: false,
    activeResponseId: null,
    audioStarted: false,
    settled: true,
  };
}

export function markNextResponseAsHint(state: ProtoState): ProtoState {
  return { ...state, hintNext: true };
}

export function extractTranscript(response: unknown): string {
  if (!response || typeof response !== "object") return "";
  const output = (response as { output?: unknown }).output;
  if (!Array.isArray(output)) return "";
  const parts: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const record = part as { transcript?: unknown; text?: unknown };
      if (typeof record.transcript === "string" && record.transcript.trim()) parts.push(record.transcript.trim());
      else if (typeof record.text === "string" && record.text.trim()) parts.push(record.text.trim());
    }
  }
  return parts.join(" ").trim();
}

function upsertAi(state: ProtoState, responseId: string, text: string, replace: boolean): ProtoState {
  const existing = state.turns.find((turn) => turn.id === responseId);
  if (!existing) {
    const turn: ChatTurn = {
      id: responseId,
      role: "ai",
      text,
      isHint: state.pendingHint && state.activeResponseId === responseId,
      pending: !replace,
    };
    return { ...state, turns: [...state.turns, turn] };
  }
  return {
    ...state,
    turns: state.turns.map((turn) =>
      turn.id === responseId ? { ...turn, text: replace ? text : `${turn.text}${text}`, pending: replace ? false : turn.pending } : turn,
    ),
  };
}

function placeholder(state: ProtoState): ProtoState {
  if (!state.activeResponseId) return state;
  if (state.turns.some((turn) => turn.id === state.activeResponseId && turn.text.trim())) return state;
  const text = state.audioStarted
    ? "（文字起こしがありません。音声だけが再生されています。）"
    : "（応答の文字を取得できませんでした。）";
  return upsertAi(state, state.activeResponseId, text, true);
}

function asRecord(event: unknown): Record<string, unknown> | null {
  if (!event || typeof event !== "object" || !("type" in event)) return null;
  return event as Record<string, unknown>;
}

export function reduceRealtimeEvent(state: ProtoState, event: unknown): { state: ProtoState; effects: RealtimeEffect[] } {
  const record = asRecord(event);
  if (!record || typeof record.type !== "string") return { state, effects: [] };
  const effects: RealtimeEffect[] = [];

  switch (record.type) {
    case "response.created": {
      const response = record.response as { id?: unknown } | undefined;
      const id = typeof response?.id === "string" ? response.id : "";
      return {
        state: {
          ...state,
          hintNext: false,
          pendingHint: state.hintNext,
          activeResponseId: id || state.activeResponseId,
          audioStarted: false,
          settled: false,
        },
        effects: [{ type: "ai_started" }],
      };
    }
    case "response.output_audio_transcript.delta": {
      const responseId = typeof record.response_id === "string" ? record.response_id : state.activeResponseId;
      const delta = typeof record.delta === "string" ? record.delta : "";
      if (!responseId || !delta) return { state, effects };
      return { state: upsertAi(state, responseId, delta, false), effects };
    }
    case "response.output_audio_transcript.done": {
      const responseId = typeof record.response_id === "string" ? record.response_id : state.activeResponseId;
      const transcript = typeof record.transcript === "string" ? record.transcript : "";
      if (!responseId || !transcript.trim()) return { state, effects };
      return { state: upsertAi(state, responseId, transcript.trim(), true), effects };
    }
    case "response.output_audio.delta":
    case "output_audio_buffer.started":
      return { state: { ...state, audioStarted: true }, effects };
    case "output_audio_buffer.stopped": {
      if (state.settled) return { state, effects };
      effects.push({ type: "ai_finished" });
      return { state: placeholder({ ...state, settled: true }), effects };
    }
    case "response.done": {
      const response = record.response as { id?: unknown; status?: unknown } | undefined;
      const status = typeof response?.status === "string" ? response.status : "";
      const id = typeof response?.id === "string" ? response.id : state.activeResponseId;
      if (status === "cancelled") {
        return { state: { ...state, settled: true, activeResponseId: id }, effects };
      }
      if (status === "failed") {
        effects.push({ type: "error", message: "応答を生成できませんでした。" });
        return { state: { ...state, settled: true }, effects };
      }
      let next = state;
      const finalText = extractTranscript(response);
      if (finalText && id) next = upsertAi(next, id, finalText, true);
      if (state.settled) return { state: next, effects };
      if (!state.audioStarted) {
        effects.push({ type: "ai_finished" });
        return { state: placeholder({ ...next, settled: true }), effects };
      }
      effects.push({ type: "arm_playback_fallback" });
      return { state: next, effects };
    }
    case "input_audio_buffer.speech_started":
      effects.push({ type: "user_speech_started" });
      return { state, effects };
    case "input_audio_buffer.speech_stopped":
      effects.push({ type: "user_speech_stopped" });
      return { state, effects };
    case "conversation.item.input_audio_transcription.completed": {
      const itemId = typeof record.item_id === "string" ? record.item_id : "";
      const transcript = typeof record.transcript === "string" ? record.transcript.trim() : "";
      if (!itemId || !transcript) return { state, effects };
      if (state.turns.some((turn) => turn.id === itemId)) return { state, effects };
      const turn: ChatTurn = { id: itemId, role: "learner", text: transcript, isHint: false, pending: false };
      effects.push({ type: "learner_utterance", text: transcript, itemId });
      return { state: { ...state, turns: [...state.turns, turn] }, effects };
    }
    case "conversation.item.input_audio_transcription.failed":
      effects.push({ type: "notice", message: "一部の文字起こしに失敗しました。会話はそのまま続けます。" });
      return { state, effects };
    case "error": {
      const error = record.error as { message?: unknown } | undefined;
      const message = typeof error?.message === "string" ? error.message.slice(0, 200) : "音声APIでエラーが起きました。";
      effects.push({ type: "error", message });
      return { state, effects };
    }
    default:
      return { state, effects };
  }
}
