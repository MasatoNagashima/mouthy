import { countSpokenWords } from "./fillers.ts";
import { buildNarrative, type JudgeResult, type QaLevel } from "./qa.ts";
import { computeScore, type ScoreResult } from "./score.ts";
import type { WpmResult } from "./wpm.ts";

export type ReviewCorrection = {
  tag: string;
  original: string;
  better: string;
  reasonJa: string;
};

export type ReviewPayload = {
  formulaVersion: string;
  score: ScoreResult;
  delta: number | null;
  strength: string;
  nextSteps: string[];
  corrections: ReviewCorrection[];
  speakingWpm: number | null;
  overallWpm: number | null;
  wordCount: number;
  judgeSource: JudgeResult["source"];
  judgeNotice: string | null;
};

function tidy(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

/** キーが無いときでも振り返りに出せる、意味が変わる誤りだけ。最大2件。 */
export function heuristicCorrections(learnerTexts: string[]): ReviewCorrection[] {
  const found: ReviewCorrection[] = [];
  for (const raw of learnerTexts) {
    const text = tidy(raw);
    if (!text || found.length >= 2) continue;
    if (/\blast year\b/i.test(text) && /\b(join|go|start|am|is)\b/i.test(text)) {
      found.push({
        tag: "時制",
        original: text,
        better: text
          .replace(/\bjoin\b/i, "joined")
          .replace(/\bgo\b/i, "went")
          .replace(/\bstart\b/i, "started")
          .replace(/\bam\b/i, "was")
          .replace(/\bis\b/i, "was"),
        reasonJa: "去年のことなので過去形にします。今も続けているなら、現在完了も使えます。",
      });
      continue;
    }
    if (/\bshy person\b/i.test(text)) {
      found.push({
        tag: "直訳",
        original: text,
        better: "One thing I'm working on is speaking up in groups.",
        reasonJa: "shy person は否定的に響きやすいので、改善中の行動として言うと伝わりやすいです。",
      });
    }
  }
  return found.slice(0, 2);
}

export function averageWordsPerTurn(texts: string[], fillers: readonly string[]): number | null {
  const counts = texts.map((text) => countSpokenWords(text, fillers)).filter((count) => count > 0);
  if (counts.length === 0) return null;
  return counts.reduce((sum, count) => sum + count, 0) / counts.length;
}

export function assembleReview(input: {
  judge: JudgeResult;
  wpm: WpmResult;
  checkpointsDone: number;
  checkpointsTotal: number;
  learnerTexts: string[];
  fillers: readonly string[];
  previousTotal: number | null;
  reactionMedianMs: number | null;
  majorErrors?: number;
  minorErrors?: number;
}): ReviewPayload {
  const levels: QaLevel[] = input.judge.pairs.map((pair) => pair.level);
  const corrections = heuristicCorrections(input.learnerTexts);
  const major = input.majorErrors ?? corrections.length;
  const minor = input.minorErrors ?? 0;
  const score = computeScore({
    qaLevels: levels,
    checkpointsDone: input.checkpointsDone,
    checkpointsTotal: input.checkpointsTotal,
    learnerAskedOrExpanded: input.judge.learnerAskedOrExpanded,
    speakingWpm: input.wpm.speakingWpm,
    reactionMedianMs: input.reactionMedianMs,
    averageWordsPerTurn: averageWordsPerTurn(input.learnerTexts, input.fillers),
    wordCount: input.wpm.wordCount,
    majorErrors: major,
    minorErrors: minor,
  });
  const narrative = buildNarrative({ levels, learnerAskedOrExpanded: input.judge.learnerAskedOrExpanded });
  const quoted = input.learnerTexts.map(tidy).find((text) => countSpokenWords(text, input.fillers) >= 4);
  const strength = quoted ? `「${quoted}」と、自分の言葉で答えられていました。` : narrative.strength;
  const previous = input.previousTotal;
  const delta = previous == null || !Number.isFinite(previous) ? null : score.total - Math.round(previous);
  return {
    formulaVersion: score.formulaVersion,
    score,
    delta,
    strength,
    nextSteps: narrative.improvements,
    corrections,
    speakingWpm: input.wpm.speakingWpm,
    overallWpm: input.wpm.overallWpm,
    wordCount: input.wpm.wordCount,
    judgeSource: input.judge.source,
    judgeNotice: input.judge.notice,
  };
}
