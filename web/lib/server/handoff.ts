import "server-only";
import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from "node:crypto";
import { env } from "./env";

// The app's "Open the web dashboard" link (POST /api/auth/handoff -> GET /login/handoff?t=…).
//
// The link carries a Supabase magic-link token sealed with AES-256-GCM under a key derived from the server's secret
// key, plus who it is for and when it stops working. So the token itself never appears in a URL, the link works
// only through /login/handoff and only until it expires, and Supabase accepts the token once (verifyOtp uses it up).

export const HANDOFF_TTL_S = 120;

interface Sealed {
  h: string; // hashed_token from auth.admin.generateLink
  u: string; // user id it was made for
  e: number; // expiry, unix seconds
}

function key(): Buffer {
  return Buffer.from(hkdfSync("sha256", env.secretKey, "snapreel", "web-handoff-link-v1", 32));
}

export function sealHandoff(hashedToken: string, userId: string, now = Date.now()): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key(), iv);
  const body: Sealed = { h: hashedToken, u: userId, e: Math.floor(now / 1000) + HANDOFF_TTL_S };
  const sealed = Buffer.concat([cipher.update(JSON.stringify(body), "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), sealed]).toString("base64url");
}

/** The token and user from a link, or null when it was changed, made with another key, or has expired. */
export function openHandoff(value: string | null, now = Date.now()): { hashedToken: string; userId: string } | null {
  if (!value || value.length > 2048) return null;
  try {
    const raw = Buffer.from(value, "base64url");
    if (raw.length < 12 + 16 + 1) return null;
    const decipher = createDecipheriv("aes-256-gcm", key(), raw.subarray(0, 12));
    decipher.setAuthTag(raw.subarray(12, 28));
    const text = Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString("utf8");
    const body = JSON.parse(text) as Partial<Sealed>;
    if (typeof body.h !== "string" || typeof body.u !== "string" || typeof body.e !== "number") return null;
    if (body.e * 1000 < now) return null;
    return { hashedToken: body.h, userId: body.u };
  } catch {
    return null;
  }
}
