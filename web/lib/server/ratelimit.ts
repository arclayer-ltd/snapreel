import "server-only";
import { HttpError, clientIp } from "./http";
import { db } from "./supabase";
import { ipTag } from "./tokens";

// Public endpoint limits (docs/pro/API.md): per IP and per viewer session, fixed windows in Postgres
// (public.rate_limit_hit). If the database call itself fails we let the request through rather than block viewers.
export const RATE = {
  comment: { windowS: 60, max: 5 },
  reaction: { windowS: 60, max: 30 },
  view: { windowS: 60, max: 60 },
  report: { windowS: 3600, max: 5 },
  unlock: { windowS: 60, max: 10 },
} as const;

async function hit(key: string, windowS: number, max: number): Promise<boolean> {
  const { data, error } = await db().rpc("rate_limit_hit", { p_key: key, p_window_s: windowS, p_max: max });
  if (error) {
    console.error("[ratelimit]", error.message);
    return true;
  }
  return data !== false;
}

export async function rateLimit(req: Request, kind: keyof typeof RATE, sessionId: string | null, scope = ""): Promise<void> {
  const { windowS, max } = RATE[kind];
  const keys = [`${kind}:ip:${ipTag(clientIp(req))}${scope}`];
  if (sessionId) keys.push(`${kind}:s:${sessionId}${scope}`);
  const results = await Promise.all(keys.map((k) => hit(k, windowS, max)));
  if (results.includes(false)) {
    throw new HttpError(429, "rate_limited", "Too many requests. Wait a minute and try again.");
  }
}
