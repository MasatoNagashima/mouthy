import express, { type Express, type NextFunction, type Request, type Response } from "express";
import path from "node:path";
import { parseFillerList } from "../src/shared/fillers.ts";
import { extractQaPairs, type QaPair } from "../src/shared/qa.ts";
import { assembleReview } from "../src/shared/review.ts";
import { parseSessionSettings, SettingsError } from "../src/shared/scenarios.ts";
import type { ChatTurn } from "../src/shared/types.ts";
import { computeWpm, type SpeechSpan } from "../src/shared/wpm.ts";
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
  app.use(express.json({ limit: "256kb" }));
  const requireClient = clientGate(config.clientToken);

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.get("/api/config", (_req, res) => {
    res.json(toPublicConfig(config));
  });

  app.post("/api/realtime/session", requireClient, async (req: Request, res: Response) => {
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

  app.post("/api/feedback/judge", requireClient, async (req, res) => {
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

  app.post("/api/feedback/review", requireClient, async (req, res) => {
    const body = parseReviewBody(req.body);
    if (!body) {
      res.status(400).json({ error: "bad_review", message: "振り返りの入力が不正です。" });
      return;
    }
    const fillers = config.fillers.length > 0 ? config.fillers : parseFillerList(null);
    const pairs = extractQaPairs(body.turns);
    const judge = await judgePairs({
      pairs,
      fillers,
      apiKey: config.openaiApiKey,
      model: config.openaiJudgeModel,
      fetchImpl,
    });
    const wpm = computeWpm({ mode: body.mode, turns: body.turns, spans: body.spans, fillers });
    const learnerTexts = body.turns
      .filter((turn) => turn.role === "learner" && turn.finality === "final" && turn.text.trim())
      .map((turn) => turn.text);
    res.json(
      assembleReview({
        judge,
        wpm,
        checkpointsDone: body.checkpointsDone,
        checkpointsTotal: body.checkpointsTotal,
        learnerTexts,
        fillers,
        previousTotal: body.previousTotal,
        reactionMedianMs: body.reactionMedianMs,
      }),
    );
  });

  app.post("/api/providers/gemini/token", requireClient, async (req, res) => {
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

function clientGate(expected: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!expected) {
      next();
      return;
    }
    const header = req.header("x-mouthy-client") ?? "";
    if (header !== expected) {
      res.status(401).json({ error: "unauthorized", message: "クライアントトークンが違います。" });
      return;
    }
    next();
  };
}

function parseReviewBody(body: unknown): {
  mode: "mock" | "voice";
  turns: ChatTurn[];
  spans: SpeechSpan[];
  checkpointsDone: number;
  checkpointsTotal: number;
  previousTotal: number | null;
  reactionMedianMs: number | null;
} | null {
  if (!body || typeof body !== "object") return null;
  const record = body as Record<string, unknown>;
  if (!Array.isArray(record.turns) || record.turns.length > 80) return null;
  const turns: ChatTurn[] = [];
  for (const item of record.turns) {
    if (!item || typeof item !== "object") return null;
    const turn = item as Record<string, unknown>;
    if (turn.role !== "ai" && turn.role !== "learner") return null;
    if (turn.finality !== "partial" && turn.finality !== "final" && turn.finality !== "failed") return null;
    if (typeof turn.id !== "string" || typeof turn.text !== "string") return null;
    turns.push({
      id: turn.id.slice(0, 80),
      role: turn.role,
      text: turn.text.slice(0, 4000),
      isHint: Boolean(turn.isHint),
      finality: turn.finality,
    });
  }
  const spans: SpeechSpan[] = [];
  if (record.spans != null) {
    if (!Array.isArray(record.spans) || record.spans.length > 80) return null;
    for (const item of record.spans) {
      if (!item || typeof item !== "object") return null;
      const span = item as Record<string, unknown>;
      if (typeof span.itemId !== "string") return null;
      spans.push({
        itemId: span.itemId.slice(0, 80),
        startMs: finiteOrNull(span.startMs),
        endMs: finiteOrNull(span.endMs),
      });
    }
  }
  const mode = record.mode === "voice" ? "voice" : "mock";
  return {
    mode,
    turns,
    spans,
    checkpointsDone: nonNegativeInt(record.checkpointsDone),
    checkpointsTotal: nonNegativeInt(record.checkpointsTotal),
    previousTotal: finiteOrNull(record.previousTotal),
    reactionMedianMs: finiteOrNull(record.reactionMedianMs),
  };
}

function finiteOrNull(value: unknown): number | null {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function nonNegativeInt(value: unknown): number {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) return 0;
  return Math.min(40, Math.floor(number));
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
