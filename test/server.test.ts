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
