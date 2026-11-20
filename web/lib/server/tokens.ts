import "server-only";
import crypto from "node:crypto";
import { promisify } from "node:util";
import { env } from "./env";

const scrypt = promisify(crypto.scrypt) as (pw: string, salt: Buffer, len: number, opts: crypto.ScryptOptions) => Promise<Buffer>;

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

// Unbiased base62 string (rejection sampling on random bytes).
export function base62(length: number): string {
  let out = "";
  while (out.length < length) {
    for (const byte of crypto.randomBytes(length * 2)) {
      if (byte < 248) out += BASE62[byte % 62];
      if (out.length === length) break;
    }
  }
  return out;
}

export const newSlug = () => base62(10);

function hmac(data: string): string {
  return crypto.createHmac("sha256", env.viewerCookieSecret).update(data).digest("base64url");
}

function safeEqual(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// Viewer session cookie `sr_vs`: "<22 random base62>.<hmac>". Identifies a browser for unique viewers,
// rate limits and blocks; it holds nothing personal.
export const VIEWER_COOKIE = "sr_vs";
const VIEWER_MAX_AGE = 60 * 60 * 24 * 365;

export function newViewerSession(): { id: string; cookie: string } {
  const id = base62(22);
  return { id, cookie: `${id}.${hmac(`vs:${id}`)}` };
}

export function readViewerSession(value: string | undefined | null): string | null {
  if (!value) return null;
  const [id, sig] = value.split(".");
  if (!id || !sig || !/^[0-9A-Za-z]{22}$/.test(id)) return null;
  return safeEqual(sig, hmac(`vs:${id}`)) ? id : null;
}

// Password unlock cookie `sr_unlock_{slug}`: "<expiry>.<hmac(slug, expiry, password hash)>". Changing the
// password changes the hash, which invalidates every unlock already handed out.
export const UNLOCK_MAX_AGE = 12 * 60 * 60;
export const unlockCookieName = (slug: string) => `sr_unlock_${slug}`;

export function makeUnlock(slug: string, passwordHash: string): string {
  const exp = Math.floor(Date.now() / 1000) + UNLOCK_MAX_AGE;
  return `${exp}.${hmac(`unlock:${slug}:${exp}:${passwordHash}`)}`;
}

export function checkUnlock(value: string | undefined | null, slug: string, passwordHash: string | null): boolean {
  if (!value || !passwordHash) return false;
  const [exp, sig] = value.split(".");
  if (!exp || !sig || !/^\d+$/.test(exp) || Number(exp) < Date.now() / 1000) return false;
  return safeEqual(sig, hmac(`unlock:${slug}:${exp}:${passwordHash}`));
}

// Email alert unsubscribe links: hmac of the user ID, so a link only works for its own account.
export const unsubscribeSig = (userId: string) => hmac(`unsub:${userId}`).slice(0, 32);
export const checkUnsubscribeSig = (userId: string, sig: string) => safeEqual(sig, unsubscribeSig(userId));

// Video passwords: scrypt$N$r$p$salt$hash.
const SCRYPT = { N: 16384, r: 8, p: 1 };

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(password.normalize("NFKC"), salt, 32, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString("base64url")}$${hash.toString("base64url")}`;
}

export async function verifyPassword(password: string, stored: string | null): Promise<boolean> {
  if (!stored) return false;
  const [kind, n, r, p, salt, hash] = stored.split("$");
  if (kind !== "scrypt" || !salt || !hash) return false;
  const expected = Buffer.from(hash, "base64url");
  const actual = await scrypt(password.normalize("NFKC"), Buffer.from(salt, "base64url"), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
  });
  return crypto.timingSafeEqual(actual, expected);
}

// A short, stable, non-reversible tag for an IP address (rate-limit keys never hold raw IPs).
export function ipTag(ip: string): string {
  return hmac(`ip:${ip}`).slice(0, 16);
}

export interface CookieOptions {
  maxAge: number;
  httpOnly?: boolean;
}

export function setCookieHeader(name: string, value: string, { maxAge, httpOnly = true }: CookieOptions): string {
  return [
    `${name}=${value}`,
    "Path=/",
    `Max-Age=${maxAge}`,
    "SameSite=Lax",
    "Secure",
    httpOnly ? "HttpOnly" : "",
  ]
    .filter(Boolean)
    .join("; ");
}

export function viewerCookieHeader(cookie: string): string {
  return setCookieHeader(VIEWER_COOKIE, cookie, { maxAge: VIEWER_MAX_AGE });
}

export function readCookie(req: Request, name: string): string | null {
  const header = req.headers.get("cookie");
  if (!header) return null;
  for (const part of header.split(/;\s*/)) {
    const i = part.indexOf("=");
    if (i > 0 && part.slice(0, i) === name) return decodeURIComponent(part.slice(i + 1));
  }
  return null;
}
