import { LONG_PAUSE_MS } from "./scenarios.ts";
import { clip, containsJapanese, fillerCount, isHesitationHeavy, japaneseSnippet } from "./textRules.ts";
import type { StuckExpression, StuckReason } from "./types.ts";

const REASON_NOTES: Record<StuckReason, string> = {
  hesitation: "言いよどみやフィラーが続いていました",
  japanese: "日本語に切り替わっていました",
  long_pause: "返答まで間が長く、表現を探していました",
  hint_needed: "ヒントのあとで話し始めました",
};

export function detectStuck(input: {
  text: string;
  pauseMs: number;
  hintShown: boolean;
  longPauseMs?: number;
}): Omit<StuckExpression, "id"> | null {
  const text = input.text.replace(/\s+/g, " ").trim();
  if (!text) return null;
  const reasons: StuckReason[] = [];
  if (isHesitationHeavy(text) || fillerCount(text) >= 2) reasons.push("hesitation");
  if (containsJapanese(text)) reasons.push("japanese");
  const longPauseMs = input.longPauseMs ?? LONG_PAUSE_MS;
  const pauseMs = Number.isFinite(input.pauseMs) ? Math.max(0, input.pauseMs) : 0;
  if (pauseMs >= longPauseMs) reasons.push("long_pause");
  if (input.hintShown) reasons.push("hint_needed");
  if (reasons.length === 0) return null;
  return {
    text: clip(text, 160),
    reasons,
    noteJa: reasons.map((reason) => REASON_NOTES[reason]).join("。") + "。",
    pauseMs: pauseMs >= 1000 ? Math.round(pauseMs) : null,
  };
}

export function reasonLabel(reason: StuckReason): string {
  switch (reason) {
    case "hesitation":
      return "言いよどみ";
    case "japanese":
      return "日本語への切り替え";
    case "long_pause":
      return "長い間";
    case "hint_needed":
      return "ヒントが必要だった";
  }
}

export { japaneseSnippet };
