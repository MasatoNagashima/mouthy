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

export type TurnFinality = "partial" | "final" | "failed";

export type ChatTurn = {
  id: string;
  role: "ai" | "learner";
  text: string;
  isHint: boolean;
  /** partial は字幕の途中。final だけを振り返りに使う。failed は聞き取れなかった行。 */
  finality: TurnFinality;
};

export type StuckReason = "hesitation" | "japanese" | "long_pause" | "hint_needed";

export type StuckExpression = {
  id: string;
  text: string;
  reasons: StuckReason[];
  noteJa: string;
  pauseMs: number | null;
};

export type PublicConfig = {
  provider: "openai" | "gemini";
  model: string;
  transcribeModel: string | null;
  voice: string | null;
  voiceReady: boolean;
  browserVoiceImplemented: boolean;
  judgeModel: string;
  fillers: string[];
  message: string | null;
};

export type TalkStatus =
  | "connecting"
  | "ai_speaking"
  | "waiting"
  | "listening"
  | "error";
