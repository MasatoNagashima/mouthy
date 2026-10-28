import { countFillerHits, countSpokenWords, removeFillers } from "./fillers.ts";
import { containsJapanese, questionCount } from "./textRules.ts";
import type { ChatTurn } from "./types.ts";

export type QaLevel = "answers" | "partial" | "off_topic" | "no_answer";

export type QaPair = {
  index: number;
  question: string;
  answer: string;
};

export type JudgedPair = {
  index: number;
  level: QaLevel;
  note: string;
};

export type JudgeSource = "llm" | "heuristic";

export type JudgeResult = {
  source: JudgeSource;
  model: string | null;
  pairs: JudgedPair[];
  learnerAskedOrExpanded: boolean;
  notice: string | null;
};

export const QA_LEVEL_LABEL: Record<QaLevel, string> = {
  answers: "答えている",
  partial: "一部だけ答えている",
  off_topic: "話題がずれている",
  no_answer: "答えていない",
};

const LEVELS = new Set<QaLevel>(["answers", "partial", "off_topic", "no_answer"]);

/** 質問と、そのあとに確定した学習者の返事を、出た順に1組ずつ取る。途中の字幕は使わない。 */
export function extractQaPairs(turns: ChatTurn[]): QaPair[] {
  const pairs: QaPair[] = [];
  let question: string | null = null;
  for (const turn of turns) {
    if (turn.role === "ai" && turn.finality !== "failed" && turn.text.trim()) {
      question = turn.text.trim();
      continue;
    }
    if (turn.role !== "learner" || turn.finality !== "final" || !turn.text.trim() || !question) continue;
    pairs.push({ index: pairs.length, question, answer: turn.text.trim() });
  }
  return pairs;
}

export function hasReplyContent(text: string, fillers: readonly string[]): boolean {
  if (countSpokenWords(text, fillers) > 0) return true;
  const rest = removeFillers(text, fillers).replace(/\s+/g, "");
  return containsJapanese(rest) || /[A-Za-z0-9]/.test(rest);
}

/**
 * キーがないときの簡易判定。話題のずれは見ない。
 * 文法や発音では下げない。短い、または英語の語がほとんど無いときだけ「一部」「答えていない」にする。
 */
export function judgeHeuristic(pairs: QaPair[], fillers: readonly string[]): JudgeResult {
  const judged = pairs.map((pair) => {
    const words = countSpokenWords(pair.answer, fillers);
    const content = hasReplyContent(pair.answer, fillers);
    const fillerHits = countFillerHits(pair.answer, fillers);
    let level: QaLevel = "no_answer";
    if (!content || (words === 0 && fillerHits > 0 && !containsJapanese(removeFillers(pair.answer, fillers)))) {
      level = "no_answer";
    } else if (words >= 3) {
      level = "answers";
    } else {
      level = "partial";
    }
    return {
      index: pair.index,
      level,
      note: "簡易判定です。文法や発音では下げていません。話題がずれたかは見ていません。",
    };
  });
  return {
    source: "heuristic",
    model: null,
    pairs: judged,
    learnerAskedOrExpanded: pairs.some((pair) => questionCount(pair.answer) > 0 || countSpokenWords(pair.answer, fillers) >= 12),
    notice: "APIキーがないため、モデルには聞いていません。このQ&A判定は簡易判定です。",
  };
}

export function answerCounts(levels: QaLevel[]): { answers: number; total: number } {
  return { answers: levels.filter((level) => level === "answers").length, total: levels.length };
}

/** 「答えている」または「一部だけ答えている」が途切れずに続いた最長。ずれ・無回答で切れる。 */
export function longestHelpfulStreak(levels: QaLevel[]): number {
  let best = 0;
  let run = 0;
  for (const level of levels) {
    if (level === "answers" || level === "partial") {
      run += 1;
      best = Math.max(best, run);
    } else {
      run = 0;
    }
  }
  return best;
}

export function buildNarrative(input: { levels: QaLevel[]; learnerAskedOrExpanded: boolean }): {
  strength: string;
  improvements: string[];
} {
  const { answers, total } = answerCounts(input.levels);
  const streak = longestHelpfulStreak(input.levels);
  const strength =
    total === 0
      ? "質問と答えの組は、今回は見つかりませんでした。会話そのものには参加しています。"
      : answers * 2 >= total
        ? "質問に対して、意味が通る答えが半分以上ありました。"
        : input.learnerAskedOrExpanded
          ? "自分から質問するか、答えに一文以上を足していました。"
          : streak >= 2
            ? "質問への答えが、途中で途切れずに続いていました。"
            : "最後まで、相手の質問に向きあっていました。";

  const improvements: string[] = [];
  if (input.levels.some((level) => level === "no_answer" || level === "off_topic")) {
    improvements.push("答えきれていない質問がありました。次は、質問の中の語を一つ使ってから話し始めると、話題が合いやすくなります。");
  }
  if (input.levels.some((level) => level === "partial")) {
    improvements.push("途中までしか答えていない箇所がありました。一言だけ足すと、相手が次の質問をしやすくなります。");
  }
  if (!input.learnerAskedOrExpanded) {
    improvements.push("自分からの質問や、話の広げはまだありません。答えたあとに、一文だけ自分の話を足してみてください。");
  }
  if (improvements.length === 0) {
    improvements.push("次も、答えたあとに一文だけ足すと、会話が続きやすくなります。");
  }
  return { strength, improvements: improvements.slice(0, 2) };
}

export function isQaLevel(value: unknown): value is QaLevel {
  return typeof value === "string" && LEVELS.has(value as QaLevel);
}

export function mergeJudgeResult(pairs: QaPair[], raw: unknown, fillers: readonly string[], model: string): JudgeResult {
  const fallback = judgeHeuristic(pairs, fillers);
  if (!raw || typeof raw !== "object") {
    return { ...fallback, notice: "モデルの応答を読めなかったため、簡易判定に戻しました。" };
  }
  const body = raw as { pairs?: unknown; learnerAskedOrExpanded?: unknown };
  const returned = Array.isArray(body.pairs) ? body.pairs : [];
  const byIndex = new Map<number, JudgedPair>();
  for (const item of returned) {
    if (!item || typeof item !== "object") continue;
    const record = item as { index?: unknown; level?: unknown; note?: unknown };
    if (typeof record.index !== "number" || !isQaLevel(record.level)) continue;
    byIndex.set(record.index, {
      index: record.index,
      level: record.level,
      note: typeof record.note === "string" ? record.note.slice(0, 240) : "",
    });
  }
  const merged = pairs.map((pair) => byIndex.get(pair.index) ?? fallback.pairs.find((item) => item.index === pair.index)!);
  const asked = typeof body.learnerAskedOrExpanded === "boolean" ? body.learnerAskedOrExpanded : fallback.learnerAskedOrExpanded;
  const filled = merged.some((_, index) => !byIndex.has(index));
  return {
    source: "llm",
    model,
    pairs: merged,
    learnerAskedOrExpanded: asked,
    notice: filled ? "一部の組はモデルが返さなかったため、簡易判定で補いました。" : null,
  };
}

export const JUDGE_INSTRUCTIONS = [
  "You judge whether a Japanese learner of English answered an AI's question.",
  "Judge only from the transcript. Do not listen for pronunciation, and do not score fluency or grammar.",
  "Grammar mistakes and pronunciation-like misspellings must NOT lower the level. If the meaning gets through, the level is answers.",
  "Levels:",
  "- answers: the reply addresses the question, even if the English is imperfect.",
  "- partial: the reply touches the question but leaves out most of what was asked.",
  "- off_topic: the reply is about something else.",
  "- no_answer: silence, fillers only, or no attempt to respond.",
  "Also decide learnerAskedOrExpanded for the whole session: true if the learner asked a question or added information beyond a minimal answer.",
  "Write each note in Japanese, one short sentence. Do not mention scores, grades, grammar corrections, pronunciation, or fluency.",
].join("\n");
