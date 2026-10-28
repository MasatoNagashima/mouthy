/**
 * @vitest-environment node
 */
import type { AddressInfo } from "node:net";
import { readFileSync } from "node:fs";
import { afterEach, describe, expect, test } from "vitest";
import type { Server } from "node:http";
import { createApp } from "../server/app.ts";
import { loadConfig } from "../server/config.ts";
import { buildGeminiTokenBody, buildOpenAIClientSecretBody } from "../server/providers.ts";
import { defaultSettings } from "../src/shared/scenarios.ts";

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

describe("token server", () => {
  test("says the key is missing and does not start a voice session", async () => {
    const base = await start(createApp({ config: loadConfig({ PORT: "0" }) }));
    const config = (await (await fetch(`${base}/api/config`)).json()) as { voiceReady: boolean; message: string; model: string };
    expect(config.voiceReady).toBe(false);
    expect(config.model).toBe("gpt-realtime-2.1");
    expect(config.message).toContain("OPENAI_API_KEY");
    expect(config.message).toContain("テキストで試す");
    const denied = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(defaultSettings()),
    });
    expect(denied.status).toBe(503);
    const body = (await denied.json()) as { message: string };
    expect(body.message).toContain("OPENAI_API_KEY");
  });

  test("mints an ephemeral OpenAI token without returning the long-lived key", async () => {
    const secret = "sk-test-secret";
    const captured: { current: { url: string; authorization: string; body: Record<string, unknown> } | null } = { current: null };
    const fetchImpl: typeof fetch = async (input, init) => {
      const headers = init?.headers as Record<string, string> | undefined;
      captured.current = {
        url: String(input),
        authorization: String(headers?.Authorization ?? ""),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      };
      return new Response(JSON.stringify({ value: "ek_demo", expires_at: "2026-10-28T00:00:00Z" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    };
    const config = loadConfig({
      OPENAI_API_KEY: secret,
      OPENAI_REALTIME_MODEL: "gpt-realtime-test",
      OPENAI_VOICE: "cedar",
    });
    const base = await start(createApp({ config, fetchImpl }));
    const ready = (await (await fetch(`${base}/api/config`)).json()) as { voiceReady: boolean; model: string };
    expect(ready.voiceReady).toBe(true);
    expect(ready.model).toBe("gpt-realtime-test");
    const response = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...defaultSettings(["last phrase"]), scenarioId: "interview", level: "beginner" }),
    });
    const payload = (await response.json()) as { token: string; model: string };
    expect(response.status).toBe(200);
    expect(payload).toEqual({ provider: "openai", token: "ek_demo", model: "gpt-realtime-test", expiresAt: "2026-10-28T00:00:00Z" });
    expect(JSON.stringify(payload)).not.toContain(secret);
    expect(captured.current?.url).toBe("https://api.openai.com/v1/realtime/client_secrets");
    expect(captured.current?.authorization).toBe(`Bearer ${secret}`);
    const session = (captured.current?.body.session ?? {}) as {
      model: string;
      instructions: string;
      audio: { input: { turn_detection: Record<string, unknown> }; output: { voice: string; speed: number } };
    };
    expect(session.model).toBe("gpt-realtime-test");
    expect(session.instructions).toContain("exactly one follow-up question");
    expect(session.instructions).toContain("job interviewer");
    expect(session.audio.input.turn_detection).toEqual({
      type: "semantic_vad",
      eagerness: "low",
      create_response: true,
      interrupt_response: true,
    });
    expect(session.audio.output).toEqual({ voice: "cedar", speed: 0.9 });
  });

  test("hides the upstream secret when token minting fails", async () => {
    const secret = "sk-test-secret";
    const fetchImpl: typeof fetch = async () => new Response(`denied ${secret}`, { status: 401 });
    const base = await start(createApp({ config: loadConfig({ OPENAI_API_KEY: secret }), fetchImpl }));
    const response = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(defaultSettings()),
    });
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain(secret);
  });

  test("builds a Gemini ephemeral-token request but does not expose browser voice", async () => {
    const secret = "gemini-test-secret";
    let captured = "";
    const fetchImpl: typeof fetch = async (_input, init) => {
      captured = String(init?.body);
      return new Response(JSON.stringify({ name: "authTokens/demo" }), { status: 200 });
    };
    const config = loadConfig({ VOICE_PROVIDER: "gemini", GEMINI_API_KEY: secret, GEMINI_LIVE_MODEL: "gemini-3.8-live" });
    const base = await start(createApp({ config, fetchImpl }));
    const pub = (await (await fetch(`${base}/api/config`)).json()) as { browserVoiceImplemented: boolean; voiceReady: boolean };
    expect(pub.browserVoiceImplemented).toBe(false);
    expect(pub.voiceReady).toBe(false);
    const blocked = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    expect(blocked.status).toBe(409);
    const minted = await fetch(`${base}/api/providers/gemini/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...defaultSettings(), vadMode: "server_vad", silenceDurationMs: 1200 }),
    });
    expect(minted.status).toBe(200);
    expect(await minted.text()).not.toContain(secret);
    expect(captured).toContain("models/gemini-3.8-live");
    expect(captured).toContain("\"silenceDurationMs\":1200");
    const direct = buildGeminiTokenBody(defaultSettings(), config, Date.parse("2026-10-28T00:00:00Z"));
    expect(JSON.stringify(direct)).toContain("END_SENSITIVITY_LOW");
    expect(JSON.stringify(buildOpenAIClientSecretBody(defaultSettings(), loadConfig({})))).toContain("gpt-realtime-2.1");
  });

  test("judges answers on the server and does not call OpenAI without a key", async () => {
    const fetchImpl: typeof fetch = async () => {
      throw new Error("judge should not call the network without a key");
    };
    const noKey = await start(createApp({ config: loadConfig({}), fetchImpl }));
    const heuristic = await fetch(`${noKey}/api/feedback/judge`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pairs: [{ question: "Where did you go?", answer: "he go to school yesterday" }] }),
    });
    const heuristicBody = (await heuristic.json()) as { source: string; pairs: Array<{ level: string }> };
    expect(heuristic.status).toBe(200);
    expect(heuristicBody.source).toBe("heuristic");
    expect(heuristicBody.pairs[0]?.level).toBe("answers");

    const captured: { current: { url: string; body: { model?: string; messages?: Array<{ content?: string }> } } | null } = {
      current: null,
    };
    const liveFetch: typeof fetch = async (input, init) => {
      captured.current = {
        url: String(input),
        body: JSON.parse(String(init?.body)) as { model?: string; messages?: Array<{ content?: string }> },
      };
      return new Response(
        JSON.stringify({
          choices: [
            {
              message: {
                content: JSON.stringify({
                  pairs: [{ index: 0, level: "partial", note: "一部です。" }],
                  learnerAskedOrExpanded: true,
                }),
              },
            },
          ],
        }),
        { status: 200 },
      );
    };
    const base = await start(
      createApp({
        config: loadConfig({ OPENAI_API_KEY: "sk-test-secret", OPENAI_JUDGE_MODEL: "gpt-5.4-mini" }),
        fetchImpl: liveFetch,
      }),
    );
    const judged = await fetch(`${base}/api/feedback/judge`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pairs: [{ question: "Where?", answer: "school" }] }),
    });
    const body = (await judged.json()) as { source: string; model: string; pairs: Array<{ level: string }>; learnerAskedOrExpanded: boolean };
    expect(body.source).toBe("llm");
    expect(body.model).toBe("gpt-5.4-mini");
    expect(body.pairs[0]?.level).toBe("partial");
    expect(body.learnerAskedOrExpanded).toBe(true);
    expect(captured.current?.url).toBe("https://api.openai.com/v1/chat/completions");
    expect(captured.current?.body.model).toBe("gpt-5.4-mini");
    expect(JSON.stringify(captured.current?.body.messages)).toMatch(/must NOT lower the level/);
    expect(JSON.stringify(captured.current?.body)).not.toContain("sk-test-secret");
  });
});

describe("browser bundle boundary", () => {
  test("the browser voice client never requests a long-lived key", () => {
    const source = readFileSync(new URL("../src/voice/openaiRealtime.ts", import.meta.url), "utf8");
    expect(source).toContain("https://api.openai.com/v1/realtime/calls");
    expect(source).not.toContain("client_secrets");
    expect(source).not.toContain("OPENAI_API_KEY");
    const ui = readFileSync(new URL("../src/App.tsx", import.meta.url), "utf8");
    expect(ui).not.toContain("sk-");
  });
});
