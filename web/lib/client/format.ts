// Formatting shared by the watch page and the dashboard. British English, en-GB dates.

/** 0:05, 12:34, 1:02:03. */
export function formatTime(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(Number.isFinite(totalSeconds) ? totalSeconds : 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const ss = String(sec).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

/** "1 minute 5 seconds", for screen readers. */
export function spokenTime(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const parts: string[] = [];
  if (h) parts.push(`${h} hour${h === 1 ? "" : "s"}`);
  if (m) parts.push(`${m} minute${m === 1 ? "" : "s"}`);
  if (sec || parts.length === 0) parts.push(`${sec} second${sec === 1 ? "" : "s"}`);
  return parts.join(" ");
}

const dateFmt = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" });
const longDateFmt = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric" });

/** 20 Nov 2026. */
export function formatDate(iso: string): string {
  return dateFmt.format(new Date(iso));
}

/** 20 November 2026. */
export function formatLongDate(iso: string): string {
  return longDateFmt.format(new Date(iso));
}

/** "just now", "5 min ago", "3 h ago", "2 days ago", then the date. */
export function formatRelative(iso: string, now: number = Date.now()): string {
  const diff = Math.max(0, now - new Date(iso).getTime()) / 1000;
  if (diff < 45) return "just now";
  if (diff < 3600) return `${Math.max(1, Math.round(diff / 60))} min ago`;
  if (diff < 86_400) return `${Math.round(diff / 3600)} h ago`;
  const days = Math.round(diff / 86_400);
  if (days < 7) return days === 1 ? "yesterday" : `${days} days ago`;
  return formatDate(iso);
}

/** "in 2 days", "in 3 h", for expiry dates. Past dates read as "expired". */
export function formatUntil(iso: string, now: number = Date.now()): string {
  const diff = (new Date(iso).getTime() - now) / 1000;
  if (diff <= 0) return "expired";
  if (diff < 3600) return `in ${Math.max(1, Math.round(diff / 60))} min`;
  if (diff < 86_400) return `in ${Math.round(diff / 3600)} h`;
  const days = Math.round(diff / 86_400);
  return days === 1 ? "tomorrow" : `in ${days} days`;
}

const numberFmt = new Intl.NumberFormat("en-GB");

/** 1,234 or 12.3k past ten thousand. */
export function formatCount(n: number): string {
  if (n >= 10_000) return `${(n / 1000).toFixed(n >= 100_000 ? 0 : 1).replace(/\.0$/, "")}k`;
  return numberFmt.format(n);
}

export function plural(n: number, one: string, many: string = `${one}s`): string {
  return `${formatCount(n)} ${n === 1 ? one : many}`;
}

/** Bytes as "640 KB", "31 MB", "1.2 GB". */
export function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${Math.round(bytes / (1024 * 1024))} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

const regionNames =
  typeof Intl.DisplayNames === "function" ? new Intl.DisplayNames(["en-GB"], { type: "region" }) : null;

/** "GB" to "United Kingdom". */
export function countryName(code: string | null): string {
  if (!code) return "Unknown";
  try {
    return regionNames?.of(code.toUpperCase()) ?? code;
  } catch {
    return code;
  }
}

/** "GB" to the flag emoji. */
export function countryFlag(code: string | null): string {
  if (!code || code.length !== 2) return "🌐";
  return String.fromCodePoint(...[...code.toUpperCase()].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
}

/** Initials for an avatar: "Priya Shah" to "PS". */
export function initials(name: string | null): string {
  if (!name) return "?";
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const letters = parts.length > 1 ? parts[0][0] + parts[parts.length - 1][0] : parts[0]?.slice(0, 2) ?? "?";
  return letters.toUpperCase();
}

/** A stable hue for a name, so the same person keeps the same avatar colour. */
export function nameHue(name: string | null): number {
  let h = 0;
  for (const ch of name ?? "?") h = (h * 31 + ch.charCodeAt(0)) % 360;
  return h;
}

/** True once the moment has gone. */
export function isPast(iso: string): boolean {
  return new Date(iso).getTime() < Date.now();
}
