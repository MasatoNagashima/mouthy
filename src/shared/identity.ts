import { createHash, createPublicKey, createVerify, webcrypto } from "node:crypto";

export type ProviderIdentity = {
  sub: string;
  name: string | null;
  email: string | null;
};

export type IdentityJwk = webcrypto.JsonWebKey & { kid?: string };

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function decodeSegment(segment: string): unknown {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function audienceMatches(aud: unknown, expected: string): boolean {
  if (!expected) return false;
  if (typeof aud === "string") return aud === expected;
  return Array.isArray(aud) && aud.includes(expected);
}

export function verifyIdentityToken(input: {
  token: string;
  keys: IdentityJwk[];
  audience: string;
  issuers: string[];
  nonce?: string | null;
  now?: number;
}): ProviderIdentity | null {
  const parts = input.token.split(".");
  if (parts.length !== 3) return null;
  const [headerSeg, payloadSeg, signatureSeg] = parts;
  const header = decodeSegment(headerSeg);
  const payload = decodeSegment(payloadSeg);
  if (!header || typeof header !== "object" || !payload || typeof payload !== "object") return null;
  const head = header as { alg?: unknown; kid?: unknown };
  if (head.alg !== "RS256" || typeof head.kid !== "string") return null;
  const jwk = input.keys.find((key) => key.kid === head.kid);
  if (!jwk) return null;
  let verified = false;
  try {
    const key = createPublicKey({ key: jwk, format: "jwk" });
    verified = createVerify("RSA-SHA256").update(`${headerSeg}.${payloadSeg}`).verify(key, Buffer.from(signatureSeg, "base64url"));
  } catch {
    return null;
  }
  if (!verified) return null;
  const claims = payload as { iss?: unknown; aud?: unknown; exp?: unknown; sub?: unknown; nonce?: unknown; email?: unknown; name?: unknown };
  const now = input.now ?? Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== "number" || claims.exp <= now) return null;
  if (typeof claims.iss !== "string" || !input.issuers.includes(claims.iss)) return null;
  if (!audienceMatches(claims.aud, input.audience)) return null;
  if (typeof claims.sub !== "string" || !claims.sub) return null;
  if (input.nonce) {
    if (claims.nonce !== sha256Hex(input.nonce)) return null;
  }
  return {
    sub: claims.sub,
    name: typeof claims.name === "string" && claims.name ? claims.name : null,
    email: typeof claims.email === "string" && claims.email ? claims.email : null,
  };
}
