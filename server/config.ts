import type { PublicConfig } from "../src/shared/types.ts";

export type AppConfig = {
  voiceProvider: "openai" | "gemini";
  openaiApiKey: string;
  geminiApiKey: string;
  openaiRealtimeModel: string;
  openaiTranscribeModel: string;
  openaiVoice: string;
  geminiLiveModel: string;
  port: number;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const provider = env.VOICE_PROVIDER === "gemini" ? "gemini" : "openai";
  return {
    voiceProvider: provider,
    openaiApiKey: (env.OPENAI_API_KEY ?? "").trim(),
    geminiApiKey: (env.GEMINI_API_KEY ?? "").trim(),
    openaiRealtimeModel: (env.OPENAI_REALTIME_MODEL ?? "").trim() || "gpt-realtime-2.1",
    openaiTranscribeModel: (env.OPENAI_TRANSCRIBE_MODEL ?? "").trim() || "gpt-4o-mini-transcribe",
    openaiVoice: (env.OPENAI_VOICE ?? "").trim() || "marin",
    geminiLiveModel: (env.GEMINI_LIVE_MODEL ?? "").trim() || "gemini-3.8-live",
    port: Number(env.PORT) > 0 ? Number(env.PORT) : 8787,
  };
}

export function toPublicConfig(config: AppConfig): PublicConfig {
  const browserVoiceImplemented = config.voiceProvider === "openai";
  const voiceReady = browserVoiceImplemented && config.openaiApiKey.length > 0;
  let message: string | null = null;
  if (!browserVoiceImplemented) {
    message =
      "このデモのブラウザ音声は OpenAI Realtime です。Gemini は一時トークンを発行する補助アダプタだけで、ブラウザの音声セッションにはつながりません。VOICE_PROVIDER=openai にしてください。";
  } else if (!voiceReady) {
    message =
      "音声会話を始めるには、サーバーの環境変数 OPENAI_API_KEY が必要です。.env に設定してからサーバーを再起動してください。キーがなくても「テキストで試す」で、ロール選択から会話、振り返りまで確認できます。";
  }
  return {
    provider: config.voiceProvider,
    model: config.voiceProvider === "gemini" ? config.geminiLiveModel : config.openaiRealtimeModel,
    transcribeModel: config.voiceProvider === "openai" ? config.openaiTranscribeModel : null,
    voice: config.voiceProvider === "openai" ? config.openaiVoice : null,
    voiceReady,
    browserVoiceImplemented,
    message,
  };
}
