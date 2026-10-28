import express, { type Express, type Request, type Response } from "express";
import path from "node:path";
import { parseFillerList } from "../src/shared/fillers.ts";
import type { QaPair } from "../src/shared/qa.ts";
import { parseSessionSettings, SettingsError } from "../src/shared/scenarios.ts";
import { loadConfig, toPublicConfig, type AppConfig } from "./config.ts";
import { judgePairs } from "./judge.ts";
import { mintGeminiToken, mintOpenAIToken, sanitizeUpstream } from "./providers.ts";

export type AppDeps = {
  fetchImpl?: typeof fetch;
  config?: AppConfig;
};

export function createApp(deps: AppDeps = {}): Express {
  const config = deps.config ?? loadConfig();
  const fetchImpl = deps.fetchImpl ?? fetch;
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.get("/api/config", (_req, res) => {
    res.json(toPublicConfig(config));
  });

  app.post("/api/realtime/session", async (req: Request, res: Response) => {
    const pub = toPublicConfig(config);
    if (!pub.browserVoiceImplemented) {
      res.status(409).json({ error: "provider_unavailable", message: pub.message });
      return;
    }
    if (!pub.voiceReady) {
      res.status(503).json({ error: "missing_api_key", message: pub.message });
      return;
    }
    try {
      const settings = parseSessionSettings(req.body);
      const minted = await mintOpenAIToken(settings, config, fetchImpl);
      res.json({
        provider: minted.provider,
        token: minted.token,
        model: minted.model,
        expiresAt: minted.expiresAt,
      });
    } catch (error) {
      if (error instanceof SettingsError) {
        res.status(400).json({ error: "bad_settings", message: error.message });
        return;
      }
      const message = error instanceof Error ? error.message : "一時トークンを発行できませんでした。";
      res.status(502).json({
        error: "token_failed",
        message: `音声セッションを開始できませんでした。${sanitizeUpstream(message, [config.openaiApiKey, config.geminiApiKey])}`,
      });
    }
  });

  app.post("/api/feedback/judge", async (req, res) => {
    const pairs = parseJudgePairs(req.body);
    if (!pairs) {
      res.status(400).json({ error: "bad_pairs", message: "質問と答えの組が不正です。" });
      return;
    }
    const result = await judgePairs({
      pairs,
      fillers: config.fillers.length > 0 ? config.fillers : parseFillerList(null),
      apiKey: config.openaiApiKey,
      model: config.openaiJudgeModel,
      fetchImpl,
    });
    res.json(result);
  });

  app.post("/api/providers/gemini/token", async (req, res) => {
    if (!config.geminiApiKey) {
      res.status(503).json({
        error: "missing_api_key",
        message: "GEMINI_API_KEY が未設定です。この経路はブラウザ音声には使いません。",
      });
      return;
    }
    try {
      const settings = parseSessionSettings(req.body);
      const minted = await mintGeminiToken(settings, config, fetchImpl);
      res.json({
        provider: minted.provider,
        token: minted.token,
        model: minted.model,
        expiresAt: minted.expiresAt,
        browserVoiceImplemented: false,
      });
    } catch (error) {
      if (error instanceof SettingsError) {
        res.status(400).json({ error: "bad_settings", message: error.message });
        return;
      }
      const message = error instanceof Error ? error.message : "一時トークンを発行できませんでした。";
      res.status(502).json({
        error: "token_failed",
        message: sanitizeUpstream(message, [config.geminiApiKey, config.openaiApiKey]),
      });
    }
  });

  app.use("/api", (_req, res) => {
    res.status(404).json({ error: "not_found", message: "APIが見つかりません。" });
  });

  if (process.env.NODE_ENV === "production") {
    const distDir = path.resolve(process.cwd(), "dist");
    app.use(express.static(distDir));
    app.get("*", (req, res, next) => {
      if (req.path.startsWith("/api")) {
        next();
        return;
      }
      res.sendFile(path.join(distDir, "index.html"));
    });
  }

  return app;
}

function parseJudgePairs(body: unknown): QaPair[] | null {
  if (!body || typeof body !== "object") return null;
  const pairs = (body as { pairs?: unknown }).pairs;
  if (!Array.isArray(pairs) || pairs.length > 40) return null;
  const parsed: QaPair[] = [];
  for (const item of pairs) {
    if (!item || typeof item !== "object") return null;
    const record = item as { question?: unknown; answer?: unknown };
    if (typeof record.question !== "string" || typeof record.answer !== "string") return null;
    parsed.push({
      index: parsed.length,
      question: record.question.slice(0, 2000),
      answer: record.answer.slice(0, 2000),
    });
  }
  return parsed;
}
