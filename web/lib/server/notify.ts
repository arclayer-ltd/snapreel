import "server-only";
import type { PushPayload } from "@/lib/contract";
import { APNS_HOSTS, apnsConfigured, apnsReason, sendToApns } from "./apns";
import { commentEmail, heldCommentEmail, reactionEmail, sendEmail, viewEmail } from "./email";
import { SITE_URL, env } from "./env";
import { dashboardUrl, formatTimestamp, type VideoRow } from "./shape";
import { signUrls, videoPaths } from "./storage";
import { db } from "./supabase";
import { unsubscribeSig } from "./tokens";

// Alerts to the video's owner: an APNs alert to each of their devices plus an email (unless they turned email
// alerts off). Each event is claimed once in notification_log (dedupe_key is unique), so retries and races
// never send twice. Called from after() so viewers never wait on it.

type Kind = PushPayload["type"];

async function claim(userId: string, kind: Kind, videoId: string, dedupeKey: string): Promise<boolean> {
  const { error } = await db().from("notification_log").insert({ user_id: userId, kind, video_id: videoId, dedupe_key: dedupeKey });
  if (!error) return true;
  if (error.code === "23505") return false; // already sent
  throw error;
}

async function pushToOwner(userId: string, title: string, body: string, sr: PushPayload): Promise<void> {
  if (!apnsConfigured()) return;
  const { data: devices } = await db().from("devices").select("token, environment").eq("user_id", userId);
  for (const d of devices ?? []) {
    try {
      const result = await sendToApns(
        d.token,
        { aps: { alert: { title, body }, sound: "default", "thread-id": sr.videoId }, sr },
        { pushType: "alert", topic: env.bundleId },
        APNS_HOSTS[d.environment],
      );
      const reason = apnsReason(result);
      if (result.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic") {
        await db().from("devices").delete().eq("token", d.token);
      } else if (result.status !== 200) {
        console.warn("[notify] apns", result.status, reason);
      }
    } catch (error) {
      console.warn("[notify] apns error", (error as Error).message);
    }
  }
}

async function ownerEmail(userId: string): Promise<string | null> {
  const { data: profile } = await db().from("profiles").select("email_alerts").eq("id", userId).maybeSingle();
  if (profile && profile.email_alerts === false) return null;
  const { data } = await db().auth.admin.getUserById(userId);
  const email = data?.user?.email;
  // Apple's private relay addresses accept mail too, so they get alerts like any other address.
  return email || null;
}

const unsubscribeUrl = (userId: string) => `${SITE_URL}/api/email/unsubscribe?u=${userId}&s=${unsubscribeSig(userId)}`;

function listUnsubscribe(userId: string): Record<string, string> {
  return {
    "List-Unsubscribe": `<${unsubscribeUrl(userId)}>`,
    "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
}

export async function notifyView(video: VideoRow, view: { id: string; viewerName: string | null; percent: number; sessionId: string }) {
  if (!(await claim(video.owner_id, "view", video.id, `view:${video.id}:${view.sessionId}`))) return;
  const who = view.viewerName || "Someone";
  const title = video.title || "your video";
  await pushToOwner(video.owner_id, `${who} watched “${title}”`, `Watched ${view.percent}%`, {
    type: "view",
    videoId: video.id,
    localId: video.local_id,
  });
  const to = await ownerEmail(video.owner_id);
  if (!to) return;
  const poster = (await signUrls([videoPaths(video.owner_id, video.id).poster], 7 * 24 * 3600)).values().next().value ?? null;
  const mail = viewEmail({
    viewerName: view.viewerName,
    title: video.title,
    percent: view.percent,
    dashboardUrl: dashboardUrl(video.id),
    posterUrl: poster,
    unsubscribeUrl: unsubscribeUrl(video.owner_id),
  });
  await sendEmail({
    to,
    ...mail,
    headers: listUnsubscribe(video.owner_id),
    idempotencyKey: `view-${video.id}-${view.sessionId}`,
    tags: [{ name: "kind", value: "view" }],
  });
}

// A held comment (word filter) alerts the owner without its name or text, so nothing objectionable lands on a Lock
// Screen or in an inbox; the owner reads it in the app or the dashboard.
export async function notifyComment(
  video: VideoRow,
  comment: { id: string; authorName: string; body: string; atS: number | null; held?: boolean },
) {
  if (!(await claim(video.owner_id, "comment", video.id, `comment:${comment.id}`))) return;
  const title = video.title || "your video";
  const sr: PushPayload = { type: "comment", videoId: video.id, localId: video.local_id, commentId: comment.id };
  if (comment.held) {
    await pushToOwner(video.owner_id, `A comment on “${title}” is waiting for you`, "Viewers can't see it until you approve it.", sr);
  } else {
    await pushToOwner(video.owner_id, `${comment.authorName} commented on “${title}”`, comment.body.slice(0, 180), sr);
  }
  const to = await ownerEmail(video.owner_id);
  if (!to) return;
  const mail = comment.held
    ? heldCommentEmail({ title: video.title, dashboardUrl: dashboardUrl(video.id), unsubscribeUrl: unsubscribeUrl(video.owner_id) })
    : commentEmail({
        authorName: comment.authorName,
        body: comment.body,
        title: video.title,
        atLabel: comment.atS === null ? null : formatTimestamp(comment.atS),
        dashboardUrl: dashboardUrl(video.id),
        unsubscribeUrl: unsubscribeUrl(video.owner_id),
      });
  await sendEmail({
    to,
    ...mail,
    headers: listUnsubscribe(video.owner_id),
    idempotencyKey: `comment-${comment.id}`,
    tags: [{ name: "kind", value: "comment" }],
  });
}

// Reactions are batched: at most one alert per video every 10 minutes, summarising what came in.
export async function notifyReaction(video: VideoRow) {
  const window = Math.floor(Date.now() / 600_000);
  if (!(await claim(video.owner_id, "reaction", video.id, `reaction:${video.id}:${window}`))) return;
  const since = new Date(Date.now() - 600_000).toISOString();
  const { data: recent } = await db()
    .from("reactions")
    .select("emoji")
    .eq("video_id", video.id)
    .gte("created_at", since)
    .limit(50);
  const list = recent ?? [];
  const count = Math.max(list.length, 1);
  const emojis = [...new Set(list.map((r) => r.emoji))].slice(0, 5).join("") || "👍";
  const title = video.title || "your video";
  await pushToOwner(video.owner_id, `New reactions on “${title}”`, `${emojis} ${count === 1 ? "1 reaction" : `${count} reactions`}`, {
    type: "reaction",
    videoId: video.id,
    localId: video.local_id,
  });
  const to = await ownerEmail(video.owner_id);
  if (!to) return;
  const mail = reactionEmail({
    count,
    emojis,
    title: video.title,
    dashboardUrl: dashboardUrl(video.id),
    unsubscribeUrl: unsubscribeUrl(video.owner_id),
  });
  await sendEmail({
    to,
    ...mail,
    headers: listUnsubscribe(video.owner_id),
    idempotencyKey: `reaction-${video.id}-${window}`,
    tags: [{ name: "kind", value: "reaction" }],
  });
}
