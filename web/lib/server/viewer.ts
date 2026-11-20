import "server-only";
import type { Enums } from "./database.types";

// Facts about an anonymous viewer, from request headers only. Nothing here tracks people across sites.

export function deviceFrom(userAgent: string | null): Enums<"device_kind"> | null {
  if (!userAgent) return null;
  if (/iPad|Tablet|PlayBook|Silk|Android(?!.*Mobile)/i.test(userAgent)) return "tablet";
  if (/Mobi|iPhone|iPod|Android|Windows Phone/i.test(userAgent)) return "phone";
  return "desktop";
}

export function countryFrom(req: Request): string | null {
  const c = (req.headers.get("x-vercel-ip-country") || "").toUpperCase();
  return /^[A-Z]{2}$/.test(c) && c !== "XX" ? c : null;
}

export function referrerHost(value: unknown): string | null {
  if (typeof value !== "string" || !value) return null;
  try {
    const host = new URL(value).hostname.toLowerCase().replace(/^www\./, "");
    if (!host || host.endsWith("snapreel.video")) return null;
    return host.slice(0, 255);
  } catch {
    return null;
  }
}

// Link-preview bots and crawlers fetch watch pages but never count as views.
const BOTS =
  /bot|crawler|spider|crawling|preview|facebookexternalhit|slackbot|twitterbot|whatsapp|telegram|discord|linkedin|embedly|skype|curl|wget|python-requests|headless/i;

export function isBot(userAgent: string | null): boolean {
  return !userAgent || BOTS.test(userAgent);
}

// A light word filter for viewer comments and names (App Review 1.2). Masks, doesn't reject.
const BAD = [
  "fuck", "fucking", "shit", "cunt", "bitch", "bastard", "asshole", "dick", "pussy", "whore", "slut",
  "nigger", "nigga", "faggot", "fag", "retard", "kike", "spic", "chink", "twat", "wanker",
];
const BAD_RE = new RegExp(`\\b(${BAD.join("|")})\\b`, "gi");

export function cleanText(s: string): string {
  return s.replace(BAD_RE, (w) => w[0] + "*".repeat(w.length - 1));
}

export function oneLine(s: unknown, max: number): string {
  return typeof s === "string" ? s.replace(/\s+/g, " ").trim().slice(0, max) : "";
}

// Emoji reactions: one emoji (with modifiers / ZWJ sequences), at most 16 UTF-16 units.
export function isEmoji(s: unknown): s is string {
  return (
    typeof s === "string" &&
    s.length > 0 &&
    s.length <= 16 &&
    /^(\p{Extended_Pictographic}|\p{Regional_Indicator})/u.test(s) &&
    /^[\p{Extended_Pictographic}\p{Emoji_Component}\p{Emoji_Modifier}\p{Regional_Indicator}‍️]+$/u.test(s)
  );
}
