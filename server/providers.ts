import { buildInstructions, buildTurnDetection, speedForLevel } from "../src/shared/prompt.ts";
import type { SessionSettings } from "../src/shared/types.ts";
import type { AppConfig } from "./config.ts";

export type MintedToken = {
  provider: "openai" | "gemini";
  token: string;
  model: string;
  expiresAt: string | null;
};

export function sanitizeUpstream(text: string, secrets: string[]): string {
  let cleaned = text;
  for (const secret of secrets) {
    if (secret) cleaned = cleaned.split(secret).join("[redacted]");
  }
  return cleaned.replace(/\s+/g, " ").trim().slice(0, 300);
}

export function buildOpenAIClientSecretBody(settings: SessionSettings, config: AppConfig): Record<string, unknown> {
  return {
    session: {
      type: "realtime",
      model: config.openaiRealtimeModel,
      instructions: buildInstructions(settings),
      audio: {
        input: {
          noise_reduction: { type: "near_field" },
          transcription: {
            model: config.openaiTranscribeModel,
            prompt:
              "The speaker is a Japanese learner of English. They may hesitate, say um or uh, and sometimes switch into Japanese. Transcribe both languages.",
          },
          turn_detection: buildTurnDetection(settings),
        },
        output: {
          voice: config.openaiVoice,
          speed: speedForLevel(settings.level),
        },
      },
    },
  };
}

export function buildGeminiTokenBody(settings: SessionSettings, config: AppConfig, now = Date.now()): Record<string, unknown> {
  const model = config.geminiLiveModel.startsWith("models/") ? config.geminiLiveModel : `models/${config.geminiLiveModel}`;
  return {
    uses: 1,
    expireTime: new Date(now + 30 * 60 * 1000).toISOString(),
    newSessionExpireTime: new Date(now + 60 * 1000).toISOString(),
    liveConnectConstraints: {
      model,
      config: {
        sessionResumption: {},
        responseModalities: ["AUDIO"],
        systemInstruction: { parts: [{ text: buildInstructions(settings) }] },
        realtimeInputConfig: {
          automaticActivityDetection: {
            silenceDurationMs: settings.silenceDurationMs,
            startOfSpeechSensitivity: "START_SENSITIVITY_LOW",
            endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
          },
        },
      },
    },
  };
}

export async function mintOpenAIToken(settings: SessionSettings, config: AppConfig, fetchImpl: typeof fetch): Promise<MintedToken> {
  const response = await fetchImpl("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.openaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildOpenAIClientSecretBody(settings, config)),
  });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(sanitizeUpstream(raw, [config.openaiApiKey]) || `OpenAI token request failed (${response.status})`);
  }
  const parsed = JSON.parse(raw) as { value?: unknown; expires_at?: unknown };
  if (typeof parsed.value !== "string" || !parsed.value) {
    throw new Error("OpenAI の一時トークンを読めませんでした。");
  }
  return {
    provider: "openai",
    token: parsed.value,
    model: config.openaiRealtimeModel,
    expiresAt: typeof parsed.expires_at === "string" ? parsed.expires_at : null,
  };
}

export async function mintGeminiToken(settings: SessionSettings, config: AppConfig, fetchImpl: typeof fetch): Promise<MintedToken> {
  const response = await fetchImpl("https://generativelanguage.googleapis.com/v1beta/auth_tokens", {
    method: "POST",
    headers: {
      "x-goog-api-key": config.geminiApiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildGeminiTokenBody(settings, config)),
  });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(sanitizeUpstream(raw, [config.geminiApiKey]) || `Gemini token request failed (${response.status})`);
  }
  const parsed = JSON.parse(raw) as { name?: unknown; expireTime?: unknown };
  if (typeof parsed.name !== "string" || !parsed.name) {
    throw new Error("Gemini の一時トークンを読めませんでした。");
  }
  return {
    provider: "gemini",
    token: parsed.name,
    model: config.geminiLiveModel,
    expiresAt: typeof parsed.expireTime === "string" ? parsed.expireTime : null,
  };
}
