/**
 * @vitest-environment node
 */
import { readFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { afterEach, describe, expect, test } from "vitest";
import { createApp } from "../server/app.ts";
import { loadConfig } from "../server/config.ts";
import {
  CLOCK_SKEW_SECONDS,
  clearFirebaseCertCache,
  FirebaseIdTokenVerifier,
  identityFromClaims,
  maxAgeSeconds,
} from "../src/shared/firebaseToken.ts";

const servers: Server[] = [];
const PROJECT = "mouthy-stg";

afterEach(async () => {
  clearFirebaseCertCache();
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve, reject) => {
          server.close((error) => (error ? reject(error) : resolve()));
        }),
    ),
  );
});

describe("firebase id token", () => {
  test("accepts a token for this project and rejects the wrong issuer", () => {
    const now = 1_700_000_000;
    const claims = {
      iss: `https://securetoken.google.com/${PROJECT}`,
      aud: PROJECT,
      exp: now + 60,
      iat: now,
      user_id: "user-1",
      email: "a@b.c",
    };
    expect(identityFromClaims(claims, PROJECT, now)).toEqual({ uid: "user-1", email: "a@b.c" });
    expect(identityFromClaims({ ...claims, iss: "https://securetoken.google.com/other" }, PROJECT, now)).toBeNull();
    expect(identityFromClaims({ ...claims, exp: now - CLOCK_SKEW_SECONDS - 1 }, PROJECT, now)).toBeNull();
  });

  test("reuses cached certs until max-age and hides token text in errors", async () => {
    expect(maxAgeSeconds({ "cache-control": "max-age=120" })).toBe(120);
    expect(maxAgeSeconds(undefined)).toBe(300);
    let calls = 0;
    const now = [1_000_000];
    const fetchImpl = (async () => {
      calls += 1;
      return new Response(JSON.stringify({ kid: "not-a-cert" }), {
        status: 200,
        headers: { "cache-control": "public, max-age=60" },
      });
    }) as typeof fetch;
    const verifier = new FirebaseIdTokenVerifier({ fetchImpl, clock: () => now[0] });
    await verifier.verify("aa.bb.cc", PROJECT);
    await verifier.verify("aa.bb.cc", PROJECT);
    expect(calls).toBe(1);
    now[0] += 61_000;
    await verifier.verify("aa.bb.cc", PROJECT);
    expect(calls).toBe(2);

    const leaking = new FirebaseIdTokenVerifier({
      verify: () => {
        throw new Error("Can't parse segment: b'payload-secret'");
      },
    });
    const warnings: string[] = [];
    const original = console.warn;
    console.warn = (message?: unknown) => {
      warnings.push(String(message));
    };
    try {
      expect(await leaking.verify("aa.bb.cc", PROJECT)).toBeNull();
    } finally {
      console.warn = original;
    }
    expect(warnings.join("\n")).toContain("malformed token");
    expect(warnings.join("\n")).not.toContain("payload-secret");
  });
});

describe("paid routes", () => {
  test("production without a Firebase project does not mint an OpenAI token", async () => {
    const base = await start(createApp({ config: loadConfig({ NODE_ENV: "production", OPENAI_API_KEY: "sk-test" }) }));
    const response = await fetch(`${base}/api/realtime/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    expect(response.status).toBe(503);
    expect((await fetch(`${base}/api/health`)).status).toBe(200);
  });

  test("production requires a Firebase ID token and ignores the old client token", async () => {
    const verifyFirebaseToken = async (token: string) => (token === "good" ? { uid: "user-1", email: "a@b.c" } : null);
    const base = await start(createApp({
      config: loadConfig({
        NODE_ENV: "production",
        GOOGLE_CLOUD_PROJECT: PROJECT,
        MOUTHY_CLIENT_TOKEN: "old-client",
        OPENAI_API_KEY: "",
      }),
      verifyFirebaseToken,
    }));
    const denied = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Mouthy-Client": "old-client" },
      body: "{}",
    });
    expect(denied.status).toBe(401);
    const me = await fetch(`${base}/api/me`, { headers: { Authorization: "Bearer good" } });
    expect(me.status).toBe(200);
    expect(await me.json()).toEqual({ uid: "user-1", email: "a@b.c" });
    const allowed = await fetch(`${base}/api/feedback/review`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer good" },
      body: JSON.stringify({ mode: "mock", turns: [], checkpointsDone: 0, checkpointsTotal: 1 }),
    });
    expect(allowed.status).toBe(200);
  });
});

describe("ios sign-in gate", () => {
  test("waits for /api/me and uses Firebase Auth, not a custom session", () => {
    const model = readFileSync("ios/Mouthy/App/AppModel+Auth.swift", "utf8");
    const auth = readFileSync("ios/Mouthy/App/AccountAuth.swift", "utf8");
    const client = readFileSync("ios/Mouthy/App/APIClient.swift", "utf8");
    const me = model.indexOf("api().me()");
    const signedIn = model.indexOf("isSignedIn = true");
    expect(me).toBeGreaterThan(-1);
    expect(signedIn).toBeGreaterThan(me);
    expect(auth).toContain("OAuthProvider.appleCredential");
    expect(auth).toContain("GoogleAuthProvider.credential");
    expect(auth).toContain("FirebaseApp.configure()");
    expect(auth).toContain("getIDToken(forcingRefresh: forcingRefresh)");
    expect(auth).not.toContain("MOUTHY_SESSION");
    expect(client).toContain("forceRefresh: true");
  });
});

async function start(app: ReturnType<typeof createApp>): Promise<string> {
  const server = app.listen(0, "127.0.0.1");
  servers.push(server);
  await new Promise<void>((resolve) => server.once("listening", () => resolve()));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}
