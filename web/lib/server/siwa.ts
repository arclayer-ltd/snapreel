import "server-only";
import crypto from "node:crypto";
import { TEAM_ID, env } from "./env";

// Sign in with Apple REST calls for account deletion (App Review guideline 5.1.1(v)): exchange the app's fresh
// authorization code for a refresh token, then revoke it. Environment: SIWA_KEY_ID, SIWA_KEY_P8 (the .p8 text),
// SIWA_TEAM_ID (defaults to N3DBKUVJS5), SIWA_CLIENT_IDS (comma-separated; the bundle ID for the app and the
// Services ID co.arclayer.snapreel.web for the website).

export function siwaConfigured(): boolean {
  return Boolean(process.env.SIWA_KEY_ID && process.env.SIWA_KEY_P8);
}

export function allowedClientIds(): string[] {
  const list = (process.env.SIWA_CLIENT_IDS || "").split(",").map((s) => s.trim()).filter(Boolean);
  return list.length ? list : [env.bundleId, "co.arclayer.snapreel.web"];
}

// ES256 client secret. Apple accepts up to 6 months; these are minted per request and live 5 minutes.
// (The Supabase Apple provider needs a long-lived one: scripts/siwa-client-secret.mjs, renewed every 6 months.)
export function clientSecret(clientId: string, lifetimeS = 300): string {
  const now = Math.floor(Date.now() / 1000);
  const b64 = (v: object) => Buffer.from(JSON.stringify(v)).toString("base64url");
  const header = b64({ alg: "ES256", kid: process.env.SIWA_KEY_ID });
  const claims = b64({
    iss: process.env.SIWA_TEAM_ID || TEAM_ID,
    iat: now,
    exp: now + lifetimeS,
    aud: "https://appleid.apple.com",
    sub: clientId,
  });
  const key = crypto.createPrivateKey(process.env.SIWA_KEY_P8!.replace(/\\n/g, "\n"));
  const sig = crypto.sign("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${claims}.${sig.toString("base64url")}`;
}

async function appleForm(path: string, form: Record<string, string>): Promise<{ status: number; body: Record<string, unknown> }> {
  const res = await fetch(`https://appleid.apple.com${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
    signal: AbortSignal.timeout(10_000),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  return { status: res.status, body };
}

// Revokes the user's Apple grant. Returns false (never throws) when it can't: no key configured, a stale code,
// or Apple refusing. Account deletion goes ahead either way.
export async function revokeWithAuthorizationCode(code: string, clientId = env.bundleId): Promise<boolean> {
  if (!siwaConfigured() || !code || !allowedClientIds().includes(clientId)) return false;
  try {
    const secret = clientSecret(clientId);
    const token = await appleForm("/auth/token", {
      client_id: clientId,
      client_secret: secret,
      code,
      grant_type: "authorization_code",
    });
    const refresh = typeof token.body.refresh_token === "string" ? token.body.refresh_token : null;
    const access = typeof token.body.access_token === "string" ? token.body.access_token : null;
    if (!refresh && !access) {
      console.warn("[siwa] code exchange failed", token.status, token.body.error);
      return false;
    }
    const revoke = await appleForm("/auth/revoke", {
      client_id: clientId,
      client_secret: secret,
      token: (refresh ?? access)!,
      token_type_hint: refresh ? "refresh_token" : "access_token",
    });
    if (revoke.status !== 200) console.warn("[siwa] revoke failed", revoke.status, revoke.body.error);
    return revoke.status === 200;
  } catch (error) {
    console.warn("[siwa] revoke error", (error as Error).message);
    return false;
  }
}
