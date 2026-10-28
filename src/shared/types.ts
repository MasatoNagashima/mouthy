export type ScenarioId = "interview" | "daily" | "business" | "travel" | "warmup";

export type LevelId = "beginner" | "intermediate" | "advanced";

export type VadMode = "semantic_vad" | "server_vad";

export type Eagerness = "low" | "medium" | "high" | "auto";

export type SessionSettings = {
  scenarioId: ScenarioId;
  level: LevelId;
  goal: string;
  extraInstructions: string;
  reusePhrases: string[];
  hintDelayMs: number;
  maxHints: number;
  vadMode: VadMode;
  eagerness: Eagerness;
  silenceDurationMs: number;
};

export type ChatTurn = {
  id: string;
  role: "ai" | "learner";
  text: string;
  isHint: boolean;
  pending: boolean;
};

export type StuckReason = "hesitation" | "japanese" | "long_pause" | "hint_needed";

export type StuckExpression = {
  id: string;
  text: string;
  reasons: StuckReason[];
  noteJa: string;
  pauseMs: number | null;
};

export type FeedbackCategory = "grammar" | "expression";

export type FeedbackItem = {
  category: FeedbackCategory;
  titleJa: string;
  detailJa: string;
  quote?: string;
};

export type PublicConfig = {
  provider: "openai" | "gemini";
  model: string;
  transcribeModel: string | null;
  voice: string | null;
  voiceReady: boolean;
  browserVoiceImplemented: boolean;
  message: string | null;
};

export type TalkStatus =
  | "connecting"
  | "ai_speaking"
  | "waiting"
  | "listening"
  | "error";
