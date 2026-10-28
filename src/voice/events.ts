import type { ChatTurn } from "../shared/types.ts";

export const UNRECOGNIZED_LEARNER = "（聞き取れませんでした）";

const PENDING_PREFIX = "pending-learner";

export type RealtimeEffect =
  | { type: "ai_started" }
  | { type: "ai_finished" }
  | { type: "user_speech_started" }
  | { type: "user_speech_stopped" }
  | { type: "learner_utterance"; text: string; itemId: string }
  | { type: "error"; message: string }
  | { type: "notice"; message: string }
  | { type: "arm_playback_fallback" };

type TurnMeta = {
  isGreeting: boolean;
  followsLearnerId: string | null;
  itemId: string | null;
};

export type ProtoState = {
  turns: ChatTurn[];
  hintNext: boolean;
  pendingHint: boolean;
  activeResponseId: string | null;
  audioStarted: boolean;
  settled: boolean;
  openLearnerId: string | null;
  meta: Record<string, TurnMeta>;
  responseItemId: Record<string, string>;
  itemPrevious: Record<string, string | null>;
};

export function initialProtoState(): ProtoState {
  return {
    turns: [],
    hintNext: false,
    pendingHint: false,
    activeResponseId: null,
    audioStarted: false,
    settled: true,
    openLearnerId: null,
    meta: {},
    responseItemId: {},
    itemPrevious: {},
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

function textField(record: Record<string, unknown>, key: string): string {
  const value = record[key];
  return typeof value === "string" ? value : "";
}

function readMessage(value: unknown): { id: string; role: string } | null {
  if (!value || typeof value !== "object") return null;
  const item = value as { id?: unknown; role?: unknown };
  if (typeof item.id !== "string" || !item.id) return null;
  return { id: item.id, role: typeof item.role === "string" ? item.role : "" };
}

function isPendingId(id: string): boolean {
  return id.startsWith(PENDING_PREFIX);
}

function turnIndex(turns: ChatTurn[], id: string, meta: Record<string, TurnMeta>): number {
  return turns.findIndex((turn) => turn.id === id || meta[turn.id]?.itemId === id);
}

function moveAfter(state: ProtoState, turnId: string, previousId: string | null): ProtoState {
  if (!previousId) return state;
  const turns = state.turns.slice();
  const from = turnIndex(turns, turnId, state.meta);
  if (from < 0) return state;
  const [turn] = turns.splice(from, 1);
  const previous = turnIndex(turns, previousId, state.meta);
  if (previous < 0) {
    turns.splice(from, 0, turn);
    return state;
  }
  turns.splice(previous + 1, 0, turn);
  return { ...state, turns };
}

function retargetFollows(meta: Record<string, TurnMeta>, from: string, to: string): Record<string, TurnMeta> {
  const next: Record<string, TurnMeta> = {};
  for (const [key, value] of Object.entries(meta)) {
    next[key] = value.followsLearnerId === from ? { ...value, followsLearnerId: to } : value;
  }
  return next;
}

function ensureLearner(state: ProtoState, itemId: string, previousItemId?: string | null): ProtoState {
  if (state.turns.some((turn) => turn.id === itemId)) {
    const opened = { ...state, openLearnerId: itemId };
    return previousItemId ? moveAfter(opened, itemId, previousItemId) : opened;
  }
  const synthetic = state.turns.find((turn) => turn.role === "learner" && isPendingId(turn.id) && turn.finality === "partial");
  if (synthetic && !isPendingId(itemId)) {
    const renamed: ProtoState = {
      ...state,
      openLearnerId: itemId,
      turns: state.turns.map((turn) => (turn.id === synthetic.id ? { ...turn, id: itemId } : turn)),
      meta: retargetFollows(state.meta, synthetic.id, itemId),
    };
    return previousItemId ? moveAfter(renamed, itemId, previousItemId) : renamed;
  }
  const turn: ChatTurn = { id: itemId, role: "learner", text: "", isHint: false, finality: "partial" };
  const raced = state.turns.findIndex((candidate) => {
    if (candidate.role !== "ai") return false;
    const meta = state.meta[candidate.id];
    return Boolean(meta && !meta.isGreeting && meta.followsLearnerId == null);
  });
  const turns = state.turns.slice();
  if (raced >= 0) turns.splice(raced, 0, turn);
  else turns.push(turn);
  const meta = { ...state.meta };
  for (const candidate of turns) {
    if (candidate.role !== "ai") continue;
    const info = meta[candidate.id];
    if (info && !info.isGreeting && info.followsLearnerId == null) {
      meta[candidate.id] = { ...info, followsLearnerId: itemId };
    }
  }
  const placed: ProtoState = { ...state, turns, meta, openLearnerId: itemId };
  return previousItemId ? moveAfter(placed, itemId, previousItemId) : placed;
}

function updateLearner(state: ProtoState, itemId: string, text: string, finality: ChatTurn["finality"]): ProtoState {
  return {
    ...state,
    turns: state.turns.map((turn) => (turn.id === itemId ? { ...turn, text, finality } : turn)),
  };
}

function markFailed(state: ProtoState, itemId: string): ProtoState {
  return {
    ...state,
    turns: state.turns.map((turn) =>
      turn.id === itemId
        ? { ...turn, text: turn.text.trim() || UNRECOGNIZED_LEARNER, finality: "failed" }
        : turn,
    ),
  };
}

function attachItemId(state: ProtoState, responseId: string, itemId: string): ProtoState {
  const meta = state.meta[responseId];
  if (!meta) return state;
  return { ...state, meta: { ...state.meta, [responseId]: { ...meta, itemId } } };
}

function upsertAi(state: ProtoState, responseId: string, text: string, mode: "append" | "replace"): ProtoState {
  const existing = state.turns.find((turn) => turn.id === responseId);
  if (!existing) {
    const isGreeting = !state.turns.some((turn) => turn.role === "ai");
    const turn: ChatTurn = {
      id: responseId,
      role: "ai",
      text,
      isHint: state.pendingHint && state.activeResponseId === responseId,
      finality: mode === "replace" ? "final" : "partial",
    };
    let next: ProtoState = {
      ...state,
      turns: [...state.turns, turn],
      meta: {
        ...state.meta,
        [responseId]: { isGreeting, followsLearnerId: state.openLearnerId, itemId: state.responseItemId[responseId] ?? null },
      },
    };
    const itemId = next.responseItemId[responseId];
    const previous = itemId ? next.itemPrevious[itemId] : null;
    if (previous) next = moveAfter(next, responseId, previous);
    return next;
  }
  if (existing.finality === "final" && mode === "append") return state;
  return {
    ...state,
    turns: state.turns.map((turn) =>
      turn.id === responseId
        ? { ...turn, text: mode === "replace" ? text : `${turn.text}${text}`, finality: mode === "replace" ? "final" : turn.finality }
        : turn,
    ),
  };
}

function placeholder(state: ProtoState): ProtoState {
  if (!state.activeResponseId) return state;
  const current = state.turns.find((turn) => turn.id === state.activeResponseId);
  if (current?.text.trim()) {
    return {
      ...state,
      turns: state.turns.map((turn) => (turn.id === state.activeResponseId ? { ...turn, finality: "final" } : turn)),
    };
  }
  const text = state.audioStarted ? "（文字起こしがありません。音声だけが再生されています。）" : "（応答の文字を取得できませんでした。）";
  return upsertAi(state, state.activeResponseId, text, "replace");
}

function asRecord(event: unknown): Record<string, unknown> | null {
  if (!event || typeof event !== "object" || !("type" in event)) return null;
  return event as Record<string, unknown>;
}

function onOutputItem(state: ProtoState, record: Record<string, unknown>): ProtoState {
  const responseId = textField(record, "response_id");
  const item = readMessage(record.item);
  if (!responseId || !item) return state;
  if (item.role && item.role !== "assistant") return state;
  let next: ProtoState = { ...state, responseItemId: { ...state.responseItemId, [responseId]: item.id } };
  next = attachItemId(next, responseId, item.id);
  const previous = next.itemPrevious[item.id];
  if (previous && next.turns.some((turn) => turn.id === responseId)) next = moveAfter(next, responseId, previous);
  return next;
}

function onConversationItem(state: ProtoState, record: Record<string, unknown>): ProtoState {
  const item = readMessage(record.item);
  if (!item) return state;
  const previous = textField(record, "previous_item_id") || null;
  if (item.role === "user") return ensureLearner(state, item.id, previous);
  if (item.role !== "assistant") return state;
  let next: ProtoState = { ...state, itemPrevious: { ...state.itemPrevious, [item.id]: previous } };
  const responseId = Object.entries(next.responseItemId).find(([, id]) => id === item.id)?.[0] ?? null;
  if (!responseId) return next;
  next = attachItemId(next, responseId, item.id);
  return previous ? moveAfter(next, responseId, previous) : next;
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
    case "response.output_item.added":
      return { state: onOutputItem(state, record), effects };
    case "conversation.item.added":
    case "conversation.item.created":
      return { state: onConversationItem(state, record), effects };
    case "response.output_audio_transcript.delta": {
      const responseId = textField(record, "response_id") || state.activeResponseId || "";
      const delta = textField(record, "delta");
      if (!responseId || !delta) return { state, effects };
      return { state: upsertAi(state, responseId, delta, "append"), effects };
    }
    case "response.output_audio_transcript.done": {
      const responseId = textField(record, "response_id") || state.activeResponseId || "";
      const transcript = textField(record, "transcript").trim();
      if (!responseId || !transcript) return { state, effects };
      return { state: upsertAi(state, responseId, transcript, "replace"), effects };
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
        const turns = state.turns.filter((turn) => turn.id !== id || turn.text.trim());
        return { state: { ...state, turns, settled: true, activeResponseId: id }, effects };
      }
      if (status === "failed") {
        effects.push({ type: "error", message: "応答を生成できませんでした。" });
        return { state: { ...state, settled: true }, effects };
      }
      let next = state;
      const finalText = extractTranscript(response);
      if (finalText && id) next = upsertAi(next, id, finalText, "replace");
      if (state.settled) return { state: next, effects };
      if (!state.audioStarted) {
        effects.push({ type: "ai_finished" });
        return { state: placeholder({ ...next, settled: true }), effects };
      }
      effects.push({ type: "arm_playback_fallback" });
      return { state: next, effects };
    }
    case "input_audio_buffer.speech_started": {
      effects.push({ type: "user_speech_started" });
      const itemId = textField(record, "item_id");
      if (!itemId) {
        if (state.openLearnerId && state.turns.some((turn) => turn.id === state.openLearnerId && turn.finality === "partial")) {
          return { state, effects };
        }
        const count = state.turns.filter((turn) => isPendingId(turn.id)).length;
        return { state: ensureLearner(state, `${PENDING_PREFIX}-${count}`), effects };
      }
      return { state: ensureLearner(state, itemId), effects };
    }
    case "input_audio_buffer.speech_stopped":
      effects.push({ type: "user_speech_stopped" });
      return { state, effects };
    case "input_audio_buffer.committed": {
      const itemId = textField(record, "item_id");
      if (!itemId) return { state, effects };
      const previous = textField(record, "previous_item_id") || null;
      return { state: ensureLearner(state, itemId, previous), effects };
    }
    case "conversation.item.input_audio_transcription.delta": {
      const itemId = textField(record, "item_id");
      const delta = textField(record, "delta");
      if (!itemId || !delta) return { state, effects };
      const next = ensureLearner(state, itemId);
      const current = next.turns.find((turn) => turn.id === itemId);
      if (!current || current.finality === "final" || current.finality === "failed") return { state: next, effects };
      return { state: updateLearner(next, itemId, `${current.text}${delta}`, "partial"), effects };
    }
    case "conversation.item.input_audio_transcription.completed": {
      const itemId = textField(record, "item_id");
      const transcript = textField(record, "transcript").trim();
      if (!itemId) return { state, effects };
      let next = ensureLearner(state, itemId);
      const current = next.turns.find((turn) => turn.id === itemId);
      if (current?.finality === "final") return { state: next, effects };
      if (!transcript) return { state: markFailed(next, itemId), effects };
      next = updateLearner(next, itemId, transcript, "final");
      effects.push({ type: "learner_utterance", text: transcript, itemId });
      return { state: next, effects };
    }
    case "conversation.item.input_audio_transcription.failed": {
      const itemId = textField(record, "item_id");
      effects.push({ type: "notice", message: "一部の文字起こしに失敗しました。会話はそのまま続けます。" });
      if (!itemId) return { state, effects };
      const next = ensureLearner(state, itemId);
      if (next.turns.find((turn) => turn.id === itemId)?.finality === "final") return { state: next, effects };
      return { state: markFailed(next, itemId), effects };
    }
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
