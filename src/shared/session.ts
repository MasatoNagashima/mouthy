import { createHmac, timingSafeEqual } from "node:crypto";

export type SessionProvider = "apple" | "google";

export type SessionClaims = {
  sub: string;
  provider: SessionProvider;
  name: string | null;
  exp: number;
};

const SESSION_TTL_SEC = 30 * 24 * 60 * 60;

function b64url(value: Buffer | string): string {
  return Buffer.from(value).toString("base64url");
}

function encode(value: unknown): string {
  return b64url(JSON.stringify(value));
}

function decodeJson(segment: string): unknown {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

export function signSession(input: {
  sub: string;
  provider: SessionProvider;
  name?: string | null;
  secret: string;
  now?: number;
}): { token: string; expiresAt: string } {
  const now = input.now ?? Math.floor(Date.now() / 1000);
  const exp = now + SESSION_TTL_SEC;
  const header = encode({ alg: "HS256", typ: "JWT" });
  const payload = encode({
    sub: input.sub,
    provider: input.provider,
    name: input.name ?? null,
    iat: now,
    exp,
  });
  const signature = createHmac("sha256", input.secret).update(`${header}.${payload}`).digest("base64url");
  const expiresAt = new Date(exp * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
  return { token: `${header}.${payload}.${signature}`, expiresAt };
}

export function readSession(token: string, secret: string, now = Math.floor(Date.now() / 1000)): SessionClaims | null {
  const parts = token.split(".");
  if (parts.length !== 3 || !secret) return null;
  const [header, payload, signature] = parts;
  const expected = createHmac("sha256", secret).update(`${header}.${payload}`).digest();
  const actual = Buffer.from(signature, "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return null;
  const body = decodeJson(payload);
  if (!body || typeof body !== "object") return null;
  const record = body as { sub?: unknown; provider?: unknown; name?: unknown; exp?: unknown };
  if (typeof record.sub !== "string" || !record.sub) return null;
  if (record.provider !== "apple" && record.provider !== "google") return null;
  if (typeof record.exp !== "number" || record.exp <= now) return null;
  return {
    sub: record.sub,
    provider: record.provider,
    name: typeof record.name === "string" && record.name ? record.name : null,
    exp: record.exp,
  };
}
