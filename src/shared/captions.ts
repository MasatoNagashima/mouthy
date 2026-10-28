import type { ChatTurn } from "./types.ts";

export function partitionTurns(turns: ChatTurn[]): { history: ChatTurn[]; live: ChatTurn | null } {
  let liveIndex = -1;
  for (let index = turns.length - 1; index >= 0; index -= 1) {
    if (turns[index]?.finality === "partial") {
      liveIndex = index;
      break;
    }
  }
  const history = turns.filter((turn, index) => {
    if (index === liveIndex) return false;
    if (!turn.text.trim() && turn.finality === "partial") return false;
    return true;
  });
  return { history, live: liveIndex >= 0 ? turns[liveIndex] ?? null : null };
}

export function presentCaption(turns: ChatTurn[], draft: string): { history: ChatTurn[]; live: ChatTurn | null } {
  const partitioned = partitionTurns(turns);
  const typed = draft.trim();
  if (!typed) return partitioned;
  const displaced = partitioned.live?.text.trim() ? partitioned.live : null;
  return {
    history: displaced ? [...partitioned.history, displaced] : partitioned.history,
    live: { id: "draft", role: "learner", text: typed, isHint: false, finality: "final" },
  };
}

export function confirmedLearnerTexts(turns: ChatTurn[]): string[] {
  return turns
    .filter((turn) => turn.role === "learner" && turn.finality === "final" && turn.text.trim())
    .map((turn) => turn.text);
}
