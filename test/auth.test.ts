/**
 * @vitest-environment node
 */
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { afterEach, describe, expect, test } from "vitest";
import { createApp } from "../server/app.ts";
import { loadConfig } from "../server/config.ts";
import { verifyIdentityToken } from "../src/shared/identity.ts";
import { readSession, signSession } from "../src/shared/session.ts";

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

function b64url(value: string): string {
  return Buffer.from(value).toString("base64url");
}

function signedToken(claims: Record<string, unknown>, kid = "test-key") {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const jwk = publicKey.export({ format: "jwk" }) as { kid?: string };
  jwk.kid = kid;
  const header = b64url(JSON.stringify({ alg: "RS256", kid }));
  const payload = b64url(JSON.stringify(claims));
  const signature = createSign("RSA-SHA256").update(`${header}.${payload}`).sign(privateKey).toString("base64url");
  return { token: `${header}.${payload}.${signature}`, jwk };
}

describe("session token", () => {
  test("round-trips and rejects a bad signature or an expired token", () => {
    const minted = signSession({ sub: "apple:abc", provider: "apple", name: "青木", secret: "test-secret", now: 1_000 });
    expect(readSession(minted.token, "test-secret", 1_000)?.name).toBe("青木");
    expect(readSession(minted.token, "other-secret", 1_000)).toBeNull();
    expect(readSession(minted.token, "test-secret", 1_000 + 31 * 24 * 60 * 60)).toBeNull();
  });
});

describe("provider identity token", () => {
  test("accepts an Apple token only for this bundle and the matching nonce", () => {
    const now = 1_700_000_000;
    const nonce = "raw-nonce";
    const nonceHash = createHash("sha256").update(nonce).digest("hex");
    const { token, jwk } = signedToken({
      iss: "https://appleid.apple.com",
      aud: "com.mouthy.stg",
      exp: now + 60,
      sub: "apple-user",
      nonce: nonceHash,
    });
    expect(verifyIdentityToken({
      token,
      keys: [jwk],
      audience: "com.mouthy.stg",
      issuers: ["https://appleid.apple.com"],
      nonce,
      now,
    })?.sub).toBe("apple-user");
    expect(verifyIdentityToken({
      token,
      keys: [jwk],
      audience: "com.mouthy.app",
      issuers: ["https://appleid.apple.com"],
      nonce,
      now,
    })).toBeNull();
  });
});

describe("paid routes", () => {
  test("production without a session secret does not mint an OpenAI token", async () => {
    const base = await start(createApp({ config: loadConfig({ NODE_ENV: "production", OPENAI_API_KEY: "sk-test" }) }));
    const response = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    expect(response.status).toBe(503);
    const health = await fetch(`${base}/api/health`);
    expect(health.status).toBe(200);
  });

  test("a session secret requires a bearer token and ignores the old client token", async () => {
    const secret = "stg-session-secret";
    const base = await start(createApp({
      config: loadConfig({ MOUTHY_SESSION_SECRET: secret, MOUTHY_CLIENT_TOKEN: "old-client", OPENAI_API_KEY: "" }),
    }));
    const denied = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Mouthy-Client": "old-client" },
      body: "{}",
    });
    expect(denied.status).toBe(401);
    const minted = signSession({ sub: "google:user", provider: "google", secret, now: Math.floor(Date.now() / 1000) });
    const allowed = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${minted.token}` },
      body: JSON.stringify({ mode: "mock", turns: [], checkpointsDone: 0, checkpointsTotal: 1 }),
    });
    expect(allowed.status).toBe(200);
  });

  test("apple sign-in issues a session after the provider key verifies", async () => {
    const now = Math.floor(Date.now() / 1000);
    const nonce = "raw-nonce";
    const nonceHash = createHash("sha256").update(nonce).digest("hex");
    const { token, jwk } = signedToken({
      iss: "https://appleid.apple.com",
      aud: "com.mouthy.stg",
      exp: now + 60,
      sub: "apple-user",
      nonce: nonceHash,
      name: "青木",
    });
    const fetchImpl = (async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 })) as typeof fetch;
    const base = await start(createApp({
      config: loadConfig({ MOUTHY_SESSION_SECRET: "session-secret", MOUTHY_APPLE_AUDIENCE: "com.mouthy.stg" }),
      fetchImpl,
    }));
    const response = await fetch(`${base}/api/auth/apple`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: token, nonce, name: "青木" }),
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { token: string; provider: string };
    expect(body.provider).toBe("apple");
    expect(readSession(body.token, "session-secret")?.sub).toBe("apple:apple-user");
  });
});

async function start(app: ReturnType<typeof createApp>): Promise<string> {
  const server = app.listen(0, "127.0.0.1");
  servers.push(server);
  await new Promise<void>((resolve) => server.once("listening", () => resolve()));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}
