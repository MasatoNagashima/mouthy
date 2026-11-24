/**
 * @vitest-environment node
 */
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { afterEach, describe, expect, test } from "vitest";
import { createApp } from "../server/app.ts";
import { loadConfig } from "../server/config.ts";
import { computeScore } from "../src/shared/score.ts";

const servers: Server[] = [];

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve, reject) => {
          server.close((error) => (error ? reject(error) : resolve()));
        }),
    ),
  );
});

async function start(app: ReturnType<typeof createApp>): Promise<string> {
  const server = app.listen(0, "127.0.0.1");
  servers.push(server);
  await new Promise<void>((resolve) => server.once("listening", () => resolve()));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

describe("speaking score", () => {
  test("weights communication most and rounds each axis before the total", () => {
    const score = computeScore({
      qaLevels: ["answers", "answers", "partial"],
      checkpointsDone: 2,
      checkpointsTotal: 4,
      learnerAskedOrExpanded: true,
      speakingWpm: 94,
      reactionMedianMs: 3800,
      averageWordsPerTurn: 11,
      wordCount: 100,
      majorErrors: 1,
      minorErrors: 2,
    });
    expect(score.formulaVersion).toBe("2026-11-23");
    expect(score.communication).toBe(74);
    expect(score.fluency).toBe(85);
    expect(score.accuracy).toBe(79);
    expect(score.total).toBe(79);
  });

  test("does not invent a speed or an accuracy score when nobody spoke", () => {
    const score = computeScore({
      qaLevels: [],
      checkpointsDone: 0,
      checkpointsTotal: 4,
      learnerAskedOrExpanded: false,
      speakingWpm: null,
      reactionMedianMs: null,
      averageWordsPerTurn: null,
      wordCount: 0,
      majorErrors: 0,
      minorErrors: 0,
    });
    expect(score.total).toBe(0);
    expect(score.fluency).toBe(0);
    expect(score.accuracy).toBe(0);
  });
});

describe("review endpoint", () => {
  test("scores a transcript without an API key and hides the long-lived key", async () => {
    const base = await start(createApp({ config: loadConfig({ PORT: "0", OPENAI_API_KEY: "" }) }));
    const response = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: "voice",
        turns: [
          { id: "a1", role: "ai", text: "Why are you interested?", finality: "final", isHint: false },
          { id: "l1", role: "learner", text: "I join the finance club last year.", finality: "final", isHint: false },
        ],
        spans: [{ itemId: "l1", startMs: 0, endMs: 4000 }],
        checkpointsDone: 1,
        checkpointsTotal: 4,
        previousTotal: 60,
        reactionMedianMs: 2000,
      }),
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      score: { total: number; communication: number };
      delta: number;
      corrections: Array<{ tag: string }>;
      judgeSource: string;
    };
    expect(body.judgeSource).toBe("heuristic");
    expect(body.score.communication).toBeGreaterThan(0);
    expect(body.score.total).toBeGreaterThan(0);
    expect(body.delta).toBe(body.score.total - 60);
    expect(body.corrections[0]?.tag).toBe("時制");
    expect(JSON.stringify(body)).not.toContain("sk-");
  });

  test("rejects review calls when a client token is configured and missing", async () => {
    const base = await start(
      createApp({ config: loadConfig({ PORT: "0", MOUTHY_CLIENT_TOKEN: "stg-client" }) }),
    );
    const denied = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    expect(denied.status).toBe(401);
    const allowed = await fetch(`${base}/api/health`);
    expect(allowed.status).toBe(200);
  });
});
