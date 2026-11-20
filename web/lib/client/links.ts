// Addresses used across the watch page and dashboard.

export const SITE_URL = "https://snapreel.video";
export const MANAGE_SUBSCRIPTIONS_URL = "https://apps.apple.com/account/subscriptions";

export function watchUrl(slug: string): string {
  return `${SITE_URL}/v/${slug}`;
}

/** Only same-site paths, so ?next= can't send people elsewhere. */
export function safeNext(next: string | null | undefined, fallback = "/app"): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  return next;
}

/** Supabase signed URLs take ?download= to be saved under a name instead of played. */
export function downloadUrl(videoUrl: string, title: string): string {
  const name = `${title.replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim() || "Snapreel video"}.mp4`;
  if (!videoUrl.includes("/storage/v1/object/sign/")) return videoUrl;
  const u = new URL(videoUrl);
  u.searchParams.set("download", name);
  return u.toString();
}

export function downloadName(title: string): string {
  return `${title.replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim() || "Snapreel video"}.mp4`;
}
