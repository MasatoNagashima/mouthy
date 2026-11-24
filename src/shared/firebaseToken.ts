import { createVerify, X509Certificate } from "node:crypto";

export const CLOCK_SKEW_SECONDS = 10;
export const DEFAULT_CERTS_TTL_SECONDS = 300;
export const MAX_CERTS_TTL_SECONDS = 6 * 60 * 60;
export const FIREBASE_CERTS_URL =
  "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";

const MAX_AGE = /max-age=(\d+)/i;

export type FirebaseIdentity = { uid: string; email: string };

type Claims = {
  iss?: unknown;
  aud?: unknown;
  exp?: unknown;
  iat?: unknown;
  sub?: unknown;
  user_id?: unknown;
  uid?: unknown;
  email?: unknown;
};

type CertMap = Record<string, string>;
type CacheEntry = { until: number; certs: CertMap };

const certCache = new Map<string, CacheEntry>();

export function clearFirebaseCertCache(): void {
  certCache.clear();
}

export function maxAgeSeconds(headers: Headers | Record<string, unknown> | undefined): number {
  let value = "";
  if (!headers) return DEFAULT_CERTS_TTL_SECONDS;
  if (typeof Headers !== "undefined" && headers instanceof Headers) {
    value = headers.get("cache-control") ?? "";
  } else {
    for (const [key, item] of Object.entries(headers)) {
      if (key.toLowerCase() === "cache-control") value = String(item);
    }
  }
  const match = MAX_AGE.exec(value);
  if (!match) return DEFAULT_CERTS_TTL_SECONDS;
  return Math.max(0, Math.min(Number(match[1]), MAX_CERTS_TTL_SECONDS));
}

function safeReason(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const lower = message.toLowerCase();
  if (lower.includes("segment") || message.includes("b'") || message.includes('b"')) return "malformed token";
  return message.slice(0, 200);
}

function decodeJson(segment: string): unknown {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function audienceMatches(aud: unknown, project: string): boolean {
  if (typeof aud === "string") return aud === project;
  return Array.isArray(aud) && aud.includes(project);
}

export function identityFromClaims(claims: Claims, project: string, now = Math.floor(Date.now() / 1000)): FirebaseIdentity | null {
  if (claims.iss !== `https://securetoken.google.com/${project}`) {
    console.warn(`Firebase ID token rejected: unexpected issuer ${String(claims.iss)}`);
    return null;
  }
  if (!audienceMatches(claims.aud, project)) {
    console.warn("Firebase ID token rejected: unexpected audience");
    return null;
  }
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW_SECONDS <= now) {
    console.warn("Firebase ID token rejected: expired");
    return null;
  }
  if (typeof claims.iat === "number" && claims.iat > now + CLOCK_SKEW_SECONDS) {
    console.warn("Firebase ID token rejected: token used too early");
    return null;
  }
  const uid = [claims.uid, claims.user_id, claims.sub].find((value) => typeof value === "string" && value) as string | undefined;
  if (!uid) {
    console.warn("Firebase ID token rejected: no uid claim");
    return null;
  }
  return { uid, email: typeof claims.email === "string" ? claims.email : "" };
}

export function claimsIfSignatureValid(token: string, certs: CertMap): Claims | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [headerSeg, payloadSeg, signatureSeg] = parts;
  const header = decodeJson(headerSeg);
  if (!header || typeof header !== "object") return null;
  const head = header as { alg?: unknown; kid?: unknown };
  if (head.alg !== "RS256" || typeof head.kid !== "string") return null;
  const pem = certs[head.kid];
  if (!pem) return null;
  try {
    const key = new X509Certificate(pem).publicKey;
    const ok = createVerify("RSA-SHA256").update(`${headerSeg}.${payloadSeg}`).verify(key, Buffer.from(signatureSeg, "base64url"));
    if (!ok) return null;
  } catch (error) {
    console.warn(`Firebase ID token rejected: ${safeReason(error)}`);
    return null;
  }
  const payload = decodeJson(payloadSeg);
  if (!payload || typeof payload !== "object") return null;
  return payload as Claims;
}

export function verifySignedFirebaseToken(token: string, certs: CertMap, project: string, now = Math.floor(Date.now() / 1000)): FirebaseIdentity | null {
  const claims = claimsIfSignatureValid(token, certs);
  if (!claims) return null;
  return identityFromClaims(claims, project, now);
}

export class FirebaseIdTokenVerifier {
  constructor(
    private readonly deps: {
      fetchImpl?: typeof fetch;
      verify?: (token: string, project: string) => Claims | Promise<Claims>;
      now?: () => number;
      clock?: () => number;
    } = {},
  ) {}

  async verify(token: string, project = projectId()): Promise<FirebaseIdentity | null> {
    if (token.split(".").length !== 3) return null;
    if (!project) {
      console.warn("Firebase ID token rejected: GOOGLE_CLOUD_PROJECT is not set");
      return null;
    }
    const now = this.deps.now?.() ?? Math.floor(Date.now() / 1000);
    try {
      const claims = this.deps.verify ? await this.deps.verify(token, project) : await this.claimsFromCerts(token);
      if (!claims) return null;
      return identityFromClaims(claims, project, now);
    } catch (error) {
      console.warn(`Firebase ID token rejected: ${error instanceof Error ? error.constructor.name : "Error"}: ${safeReason(error)}`);
      return null;
    }
  }

  private async claimsFromCerts(token: string): Promise<Claims | null> {
    const certs = await this.loadCerts();
    if (!certs) return null;
    return claimsIfSignatureValid(token, certs);
  }

  private async loadCerts(): Promise<CertMap | null> {
    const fetchImpl = this.deps.fetchImpl ?? fetch;
    const clock = this.deps.clock ?? (() => Date.now());
    const now = clock();
    const hit = certCache.get(FIREBASE_CERTS_URL);
    if (hit && hit.until > now) return hit.certs;
    const response = await fetchImpl(FIREBASE_CERTS_URL);
    if (!response.ok) return null;
    const body = (await response.json()) as CertMap;
    if (!body || typeof body !== "object") return null;
    certCache.set(FIREBASE_CERTS_URL, { until: now + maxAgeSeconds(response.headers) * 1000, certs: body });
    return body;
  }
}

function projectId(): string {
  return (process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? "").trim();
}
