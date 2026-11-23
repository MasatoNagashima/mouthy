import type { QaLevel } from "./qa.ts";

/** 会話後スコアの式。変えたら版を上げ、過去の点数は再計算しない。 */
export const SCORE_FORMULA_VERSION = "2026-11-23";

export const SCORE_WEIGHTS = {
  communication: 0.5,
  fluency: 0.35,
  accuracy: 0.15,
} as const;

const TARGET_WPM = 110;
const REACTION_BEST_MS = 2_000;
const REACTION_WORST_MS = 10_000;
const TARGET_WORDS_PER_TURN = 12;

export type ScoreAxisName = "communication" | "fluency" | "accuracy";

export type ScoreInput = {
  qaLevels: QaLevel[];
  checkpointsDone: number;
  checkpointsTotal: number;
  learnerAskedOrExpanded: boolean;
  speakingWpm: number | null;
  reactionMedianMs: number | null;
  averageWordsPerTurn: number | null;
  wordCount: number;
  majorErrors: number;
  minorErrors: number;
};

export type ScoreAxis = {
  axis: ScoreAxisName;
  value: number;
  weight: number;
};

export type ScoreResult = {
  formulaVersion: string;
  total: number;
  communication: number;
  fluency: number;
  accuracy: number;
  axes: ScoreAxis[];
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function roundScore(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return clamp(Math.round(value), 0, 100);
}

function establishment(levels: QaLevel[]): number {
  if (levels.length === 0) return 0;
  const sum = levels.reduce((total, level) => {
    if (level === "answers") return total + 1;
    if (level === "partial") return total + 0.5;
    return total;
  }, 0);
  return sum / levels.length;
}

/** 2秒以下で100、10秒で0。そのあいだは直線。 */
export function reactionPoints(medianMs: number | null): number {
  if (medianMs == null || !Number.isFinite(medianMs)) return 0;
  if (medianMs <= REACTION_BEST_MS) return 100;
  if (medianMs >= REACTION_WORST_MS) return 0;
  return (100 * (REACTION_WORST_MS - medianMs)) / (REACTION_WORST_MS - REACTION_BEST_MS);
}

export function speedPoints(speakingWpm: number | null): number {
  if (speakingWpm == null || !Number.isFinite(speakingWpm) || speakingWpm <= 0) return 0;
  return Math.min(100, (speakingWpm / TARGET_WPM) * 100);
}

export function lengthPoints(averageWordsPerTurn: number | null): number {
  if (averageWordsPerTurn == null || !Number.isFinite(averageWordsPerTurn) || averageWordsPerTurn <= 0) return 0;
  return Math.min(100, (averageWordsPerTurn / TARGET_WORDS_PER_TURN) * 100);
}

/**
 * 意思疎通 50%、流暢さ 35%、正確さ 15%。
 * 各軸を整数にしてから、同じ重みで総合点を四捨五入する。
 */
export function computeScore(input: ScoreInput): ScoreResult {
  const goalRate =
    input.checkpointsTotal > 0 ? clamp(input.checkpointsDone, 0, input.checkpointsTotal) / input.checkpointsTotal : 0;
  const initiative = input.learnerAskedOrExpanded ? 1 : 0;
  const communicationRaw = 100 * (0.5 * establishment(input.qaLevels) + 0.35 * goalRate + 0.15 * initiative);
  const fluencyRaw =
    0.6 * speedPoints(input.speakingWpm) +
    0.2 * reactionPoints(input.reactionMedianMs) +
    0.2 * lengthPoints(input.averageWordsPerTurn);
  const words = Math.max(0, input.wordCount);
  const accuracyRaw =
    words === 0
      ? 0
      : Math.max(
          0,
          100 - 15 * ((Math.max(0, input.majorErrors) / words) * 100) - 3 * ((Math.max(0, input.minorErrors) / words) * 100),
        );

  const communication = roundScore(communicationRaw);
  const fluency = roundScore(fluencyRaw);
  const accuracy = roundScore(accuracyRaw);
  const total = roundScore(
    SCORE_WEIGHTS.communication * communication + SCORE_WEIGHTS.fluency * fluency + SCORE_WEIGHTS.accuracy * accuracy,
  );
  return {
    formulaVersion: SCORE_FORMULA_VERSION,
    total,
    communication,
    fluency,
    accuracy,
    axes: [
      { axis: "communication", value: communication, weight: SCORE_WEIGHTS.communication },
      { axis: "fluency", value: fluency, weight: SCORE_WEIGHTS.fluency },
      { axis: "accuracy", value: accuracy, weight: SCORE_WEIGHTS.accuracy },
    ],
  };
}
