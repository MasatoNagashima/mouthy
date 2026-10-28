import type { LevelId, ScenarioId, SessionSettings } from "./types.ts";

export type Scenario = {
  id: ScenarioId;
  labelJa: string;
  descriptionJa: string;
  roleEn: string;
  goalEn: string;
};

export const SCENARIOS: Scenario[] = [
  {
    id: "interview",
    labelJa: "面接官",
    descriptionJa: "自己紹介と志望動機を短く話す",
    roleEn: "a friendly but professional job interviewer conducting an English interview for a Japanese learner",
    goalEn: "Help the learner give a short self-introduction and one reason they want the role.",
  },
  {
    id: "daily",
    labelJa: "日常会話",
    descriptionJa: "友人として、週末の話を広げる",
    roleEn: "a warm friend having an everyday English conversation with a Japanese learner",
    goalEn: "Help the learner talk about a recent day in more than a few sentences.",
  },
  {
    id: "business",
    labelJa: "出張・会議",
    descriptionJa: "海外の同僚として進捗を聞く",
    roleEn: "a colleague at an overseas office talking with a Japanese learner about work",
    goalEn: "Help the learner explain a status update and make one request.",
  },
  {
    id: "travel",
    labelJa: "旅行",
    descriptionJa: "ホテルやお店で注文や依頼を伝える",
    roleEn: "a hotel or restaurant staff member helping a Japanese learner who is traveling",
    goalEn: "Help the learner make a reservation, an order, or a simple request.",
  },
  {
    id: "warmup",
    labelJa: "雑談",
    descriptionJa: "聞き役として、話し始めのハードルを下げる",
    roleEn: "a calm listener helping a Japanese learner warm up in English",
    goalEn: "Help the learner start talking with one small, easy story.",
  },
];

export const LEVELS: Array<{ id: LevelId; labelJa: string; descriptionJa: string }> = [
  { id: "beginner", labelJa: "初級", descriptionJa: "短い文。よく使う語。" },
  { id: "intermediate", labelJa: "中級", descriptionJa: "間を待つ。日常の語彙。" },
  { id: "advanced", labelJa: "上級", descriptionJa: "自然な仕事の英語。ターンは短く。" },
];

export const DEFAULT_HINT_DELAY_MS = 12_000;
export const MIN_HINT_DELAY_MS = 5_000;
export const MAX_HINT_DELAY_MS = 30_000;
export const DEFAULT_SILENCE_DURATION_MS = 1_200;
export const MIN_SILENCE_DURATION_MS = 800;
export const MAX_SILENCE_DURATION_MS = 2_000;
export const LONG_PAUSE_MS = 6_000;
export const DEFAULT_MAX_HINTS = 3;
export const WAIT_REASSURANCE_MS = 2_000;
export const LISTEN_BACKCHANNEL_MS = 1_200;

const SCENARIO_IDS = new Set(SCENARIOS.map((scenario) => scenario.id));

export function scenarioById(id: ScenarioId): Scenario {
  const found = SCENARIOS.find((scenario) => scenario.id === id);
  if (!found) throw new Error(`unknown scenario: ${id}`);
  return found;
}

export function defaultSettings(phrases: string[] = []): SessionSettings {
  const scenario = SCENARIOS[0];
  return {
    scenarioId: scenario.id,
    level: "intermediate",
    goal: scenario.goalEn,
    extraInstructions: "",
    reusePhrases: phrases.slice(0, 8),
    hintDelayMs: DEFAULT_HINT_DELAY_MS,
    maxHints: DEFAULT_MAX_HINTS,
    vadMode: "semantic_vad",
    eagerness: "low",
    silenceDurationMs: DEFAULT_SILENCE_DURATION_MS,
  };
}

export class SettingsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SettingsError";
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function parseSessionSettings(input: unknown): SessionSettings {
  if (!input || typeof input !== "object") {
    throw new SettingsError("セッション設定が不正です。");
  }
  const body = input as Record<string, unknown>;
  const scenarioId = body.scenarioId;
  if (typeof scenarioId !== "string" || !SCENARIO_IDS.has(scenarioId as ScenarioId)) {
    throw new SettingsError("ロールを選んでください。");
  }
  const level = body.level;
  if (level !== "beginner" && level !== "intermediate" && level !== "advanced") {
    throw new SettingsError("レベルが不正です。");
  }
  const vadMode = body.vadMode === "server_vad" ? "server_vad" : "semantic_vad";
  const eagerness = body.eagerness;
  const safeEagerness =
    eagerness === "medium" || eagerness === "high" || eagerness === "auto" || eagerness === "low"
      ? eagerness
      : "low";
  const goal = typeof body.goal === "string" ? body.goal.trim().slice(0, 200) : "";
  const extra = typeof body.extraInstructions === "string" ? body.extraInstructions.trim().slice(0, 500) : "";
  const reuse = Array.isArray(body.reusePhrases)
    ? body.reusePhrases.filter((phrase): phrase is string => typeof phrase === "string").map((phrase) => phrase.trim().slice(0, 80)).filter(Boolean).slice(0, 8)
    : [];
  const hintDelay = Number(body.hintDelayMs);
  const maxHints = Number(body.maxHints);
  const silence = Number(body.silenceDurationMs);
  const scenario = scenarioById(scenarioId as ScenarioId);
  return {
    scenarioId: scenarioId as ScenarioId,
    level,
    goal: goal || scenario.goalEn,
    extraInstructions: extra,
    reusePhrases: reuse,
    hintDelayMs: clamp(Number.isFinite(hintDelay) ? hintDelay : DEFAULT_HINT_DELAY_MS, MIN_HINT_DELAY_MS, MAX_HINT_DELAY_MS),
    maxHints: clamp(Number.isFinite(maxHints) ? maxHints : DEFAULT_MAX_HINTS, 1, 5),
    vadMode,
    eagerness: safeEagerness,
    silenceDurationMs: clamp(
      Number.isFinite(silence) ? silence : DEFAULT_SILENCE_DURATION_MS,
      MIN_SILENCE_DURATION_MS,
      MAX_SILENCE_DURATION_MS,
    ),
  };
}
