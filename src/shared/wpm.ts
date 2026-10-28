import { countSpokenWords } from "./fillers.ts";
import type { ChatTurn, TurnFinality } from "./types.ts";

export type SpeechSpan = {
  itemId: string;
  startMs: number | null;
  endMs: number | null;
};

export type WpmResult = {
  available: boolean;
  wordCount: number;
  speakingMs: number | null;
  overallMs: number | null;
  /** 発話区間だけの WPM。考えている間や発話のあいだは分母に入れない。 */
  speakingWpm: number | null;
  /**
   * 最初の speech_started から最後の speech_stopped までを分母にした WPM。
   * そのあいだの沈黙と、相手が話している時間も分母に入る。
   */
  overallWpm: number | null;
};

function rate(words: number, ms: number | null): number | null {
  if (ms == null || ms <= 0) return null;
  return words / (ms / 60_000);
}

export function computeWpm(input: {
  mode: "mock" | "voice";
  turns: ChatTurn[];
  spans: SpeechSpan[];
  fillers: readonly string[];
}): WpmResult {
  const empty: WpmResult = {
    available: false,
    wordCount: 0,
    speakingMs: null,
    overallMs: null,
    speakingWpm: null,
    overallWpm: null,
  };
  if (input.mode !== "voice") return empty;

  const finals = input.turns.filter((turn) => turn.role === "learner" && turn.finality === ("final" satisfies TurnFinality) && turn.text.trim());
  const spansById = new Map(input.spans.map((span) => [span.itemId, span]));
  let words = 0;
  let speakingMs = 0;
  let speakingPieces = 0;
  let firstStart: number | null = null;
  let lastEnd: number | null = null;

  for (const turn of finals) {
    const span = spansById.get(turn.id);
    words += countSpokenWords(turn.text, input.fillers);
    if (!span || span.startMs == null || span.endMs == null || span.endMs <= span.startMs) continue;
    speakingMs += span.endMs - span.startMs;
    speakingPieces += 1;
    firstStart = firstStart == null ? span.startMs : Math.min(firstStart, span.startMs);
    lastEnd = lastEnd == null ? span.endMs : Math.max(lastEnd, span.endMs);
  }

  if (speakingPieces === 0) return { ...empty, wordCount: words };
  const overallMs = firstStart != null && lastEnd != null && lastEnd > firstStart ? lastEnd - firstStart : null;
  return {
    available: true,
    wordCount: words,
    speakingMs,
    overallMs,
    speakingWpm: rate(words, speakingMs),
    overallWpm: rate(words, overallMs),
  };
}

export function formatWpm(value: number | null, available: boolean): string {
  if (!available || value == null || !Number.isFinite(value)) return "算出不可";
  return `1分あたり ${Math.round(value)} 語`;
}
