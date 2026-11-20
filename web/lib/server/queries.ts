import "server-only";
import type { Activity, Insights, Me, PublicVideo, VideoDetail, VideoSummary, Viewer } from "@/lib/contract";
import { SITE_URL } from "./env";
import { is } from "./http";
import { activeLinkCount, getPlan, limitsFor } from "./plan";
import {
  EMPTY_STATS,
  asCta,
  asTranscript,
  toComment,
  toDetail,
  toReaction,
  toSummary,
  type VideoRow,
  type VideoStats,
} from "./shape";
import { signUrls, videoPaths } from "./storage";
import { db } from "./supabase";
import { checkUnlock } from "./tokens";

// Server functions for the watch page and the dashboard (Server Components call these during SSR) and for the
// API routes. They use the secret key, so the caller must pass the signed-in user's own ID (from
// getSessionUser() in ./session.ts) where a function takes a userId; every query is scoped to it.

export type PublicVideoError = { error: "password" | "expired" | "removed" | "not_found" };

export interface PublicAccessOptions {
  /** The raw value of the `sr_unlock_{slug}` cookie, if any. */
  unlockCookie?: string | null;
  /** The signed-in web viewer's user ID, if any. The owner never needs the password. */
  viewerUserId?: string | null;
}

export async function videoBySlug(slug: string): Promise<VideoRow | null> {
  if (!is.slug(slug)) return null;
  const { data, error } = await db().from("videos").select("*").eq("slug", slug).maybeSingle();
  if (error) throw error;
  return data;
}

// The access rules for a shared link: removed, expired, password. Shared by the watch page and every public route.
export async function resolvePublicVideo(
  slug: string,
  opts: PublicAccessOptions = {},
): Promise<{ video: VideoRow; isOwner: boolean } | PublicVideoError> {
  const video = await videoBySlug(slug);
  if (!video) return { error: "not_found" };
  if (video.deleted_at) return { error: "removed" };
  if (video.expires_at && Date.parse(video.expires_at) <= Date.now()) return { error: "expired" };
  const isOwner = !!opts.viewerUserId && opts.viewerUserId === video.owner_id;
  if (video.access === "password" && video.password_hash && !isOwner) {
    if (!checkUnlock(opts.unlockCookie, slug, video.password_hash)) return { error: "password" };
  }
  return { video, isOwner };
}

export async function getPublicVideo(slug: string, opts: PublicAccessOptions = {}): Promise<PublicVideo | PublicVideoError> {
  const resolved = await resolvePublicVideo(slug, opts);
  if ("error" in resolved) return resolved;
  return buildPublicVideo(resolved.video);
}

export async function buildPublicVideo(video: VideoRow): Promise<PublicVideo> {
  const paths = videoPaths(video.owner_id, video.id);
  const ready = video.status === "ready";
  const [profileRes, plan] = await Promise.all([
    db().from("profiles").select("display_name, brand_color, brand_logo_path").eq("id", video.owner_id).maybeSingle(),
    getPlan(video.owner_id),
  ]);
  const profile = profileRes.data;
  const logoPath = plan.isPro ? profile?.brand_logo_path ?? null : null;
  const signed = await signUrls([paths.poster, ...(ready ? [paths.video, paths.preview] : []), ...(logoPath ? [logoPath] : [])]);
  const transcript = asTranscript(video.transcript);
  const brandColor = plan.isPro ? profile?.brand_color ?? null : null;
  return {
    title: video.title,
    kind: video.kind,
    ownerName: profile?.display_name ?? null,
    brand: brandColor || logoPath ? { color: brandColor, logoUrl: logoPath ? signed.get(logoPath) ?? null : null } : null,
    durationS: Number(video.duration_s),
    width: video.width,
    height: video.height,
    status: video.status,
    uploadProgress:
      video.status === "uploading" && Number(video.size_bytes) > 0
        ? Math.min(1, Number(video.uploaded_bytes ?? 0) / Number(video.size_bytes))
        : null,
    posterUrl: signed.get(paths.poster) ?? null,
    videoUrl: ready ? signed.get(paths.video) ?? null : null,
    previewUrl: ready ? signed.get(paths.preview) ?? null : null,
    captionsUrl: transcript?.segments.length ? `${SITE_URL}/api/public/v/${video.slug}/captions.vtt` : null,
    transcript,
    allowDownload: plan.isPro && video.allow_download,
    allowComments: video.allow_comments,
    allowReactions: video.allow_reactions,
    cta: plan.isPro ? asCta(video.cta) : null,
    showBadge: !plan.isPro,
    createdAt: video.created_at,
  };
}

async function statsFor(ids: string[]): Promise<Map<string, VideoStats>> {
  const out = new Map<string, VideoStats>();
  if (!ids.length) return out;
  const { data, error } = await db().rpc("video_stats", { p_video_ids: ids });
  if (error) throw error;
  for (const s of data ?? []) {
    out.set(s.video_id, {
      views: s.views,
      uniqueViewers: s.unique_viewers,
      lastViewedAt: s.last_viewed_at,
      commentCount: s.comment_count,
    });
  }
  return out;
}

export async function getOwnerVideos(userId: string): Promise<VideoSummary[]> {
  const { data, error } = await db()
    .from("videos")
    .select("*")
    .eq("owner_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(1000);
  if (error) throw error;
  const videos = data ?? [];
  const [stats, posters] = await Promise.all([
    statsFor(videos.map((v) => v.id)),
    signUrls(videos.map((v) => videoPaths(v.owner_id, v.id).poster)),
  ]);
  return videos.map((v) => toSummary(v, stats.get(v.id) ?? EMPTY_STATS, posters.get(videoPaths(v.owner_id, v.id).poster) ?? null));
}

export async function ownerVideoRow(userId: string, id: string): Promise<VideoRow | null> {
  if (!is.uuid(id)) return null;
  const { data, error } = await db()
    .from("videos")
    .select("*")
    .eq("id", id)
    .eq("owner_id", userId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function detailFor(video: VideoRow): Promise<VideoDetail> {
  const poster = videoPaths(video.owner_id, video.id).poster;
  const [stats, signed] = await Promise.all([statsFor([video.id]), signUrls([poster])]);
  return toDetail(video, stats.get(video.id) ?? EMPTY_STATS, signed.get(poster) ?? null);
}

export async function getOwnerVideo(userId: string, id: string): Promise<VideoDetail | null> {
  const video = await ownerVideoRow(userId, id);
  return video ? detailFor(video) : null;
}

const ones = (bits: unknown) => (typeof bits === "string" ? bits.split("").filter((c) => c === "1").length : 0);

// Free gets views and unique viewers; Pro also gets the detail. avgPercent, completionRate and viewers[].percent
// are 0 to 100; dropoff is 100 counts (how many counted views watched each 1% of the video).
export async function getInsights(userId: string, id: string): Promise<Insights | null> {
  const video = await ownerVideoRow(userId, id);
  if (!video) return null;
  const [plan, statsMap] = await Promise.all([getPlan(userId), statsFor([video.id])]);
  const stats = statsMap.get(video.id) ?? EMPTY_STATS;
  const base: Insights = {
    views: stats.views,
    uniqueViewers: stats.uniqueViewers,
    avgPercent: null,
    completionRate: null,
    dropoff: null,
    countries: null,
    viewers: null,
  };
  if (!plan.isPro) return base;

  const { data, error } = await db()
    .from("views")
    .select("session_id, viewer_user_id, viewer_name, country, device, started_at, last_seen_at, buckets, completed")
    .eq("video_id", video.id)
    .eq("counted", true)
    .order("last_seen_at", { ascending: false })
    .limit(5000);
  if (error) throw error;
  const rows = data ?? [];
  const n = rows.length;
  const perBucket = new Array<number>(100).fill(0);
  const countries = new Map<string, number>();
  const sessions = new Map<string, Viewer & { userId: string | null }>();
  let percentSum = 0;
  let completed = 0;
  for (const r of rows) {
    const bits = typeof r.buckets === "string" ? r.buckets : "";
    for (let i = 0; i < 100; i++) if (bits[i] === "1") perBucket[i] += 1;
    const pct = ones(bits);
    percentSum += pct;
    if (r.completed) completed += 1;
    if (r.country) countries.set(r.country, (countries.get(r.country) ?? 0) + 1);
    const s = sessions.get(r.session_id);
    if (!s) {
      sessions.set(r.session_id, {
        name: r.viewer_name,
        anonymous: !r.viewer_name,
        country: r.country,
        device: r.device,
        firstSeenAt: r.started_at,
        lastSeenAt: r.last_seen_at,
        percent: pct,
        userId: r.viewer_user_id,
      });
    } else {
      if (r.started_at < s.firstSeenAt) s.firstSeenAt = r.started_at;
      if (r.last_seen_at > s.lastSeenAt) s.lastSeenAt = r.last_seen_at;
      s.percent = Math.max(s.percent, pct);
      s.name ??= r.viewer_name;
      s.anonymous = !s.name;
      s.userId ??= r.viewer_user_id;
    }
  }
  // Signed-in viewers without a typed name show their profile name.
  const missing = [...sessions.values()].filter((s) => !s.name && s.userId).map((s) => s.userId!);
  if (missing.length) {
    const { data: profiles } = await db().from("profiles").select("id, display_name").in("id", [...new Set(missing)]);
    const names = new Map((profiles ?? []).map((p) => [p.id, p.display_name]));
    for (const s of sessions.values()) {
      if (!s.name && s.userId && names.get(s.userId)) {
        s.name = names.get(s.userId)!;
        s.anonymous = false;
      }
    }
  }
  return {
    ...base,
    avgPercent: n ? Math.round((percentSum / n) * 10) / 10 : 0,
    completionRate: n ? Math.round((completed / n) * 1000) / 10 : 0,
    dropoff: perBucket,
    countries: [...countries.entries()].sort((a, b) => b[1] - a[1]).map(([code, count]) => ({ code, count })),
    viewers: [...sessions.values()]
      .sort((a, b) => (a.lastSeenAt < b.lastSeenAt ? 1 : -1))
      .slice(0, 500)
      .map((s): Viewer => ({
        name: s.name,
        anonymous: s.anonymous,
        country: s.country,
        device: s.device,
        firstSeenAt: s.firstSeenAt,
        lastSeenAt: s.lastSeenAt,
        percent: s.percent,
      })),
  };
}

// Comments (oldest first, deleted ones left out) and reactions on a video. No access check here: the dashboard
// calls it after getOwnerVideo, the watch page after getPublicVideo.
export async function getActivity(videoId: string): Promise<Activity> {
  if (!is.uuid(videoId)) return { comments: [], reactions: [] };
  const [video, comments, reactions] = await Promise.all([
    db().from("videos").select("owner_id").eq("id", videoId).maybeSingle(),
    db()
      .from("comments")
      .select("*")
      .eq("video_id", videoId)
      .is("deleted_at", null)
      .order("created_at", { ascending: true })
      .limit(1000),
    db().from("reactions").select("*").eq("video_id", videoId).order("created_at", { ascending: true }).limit(2000),
  ]);
  if (comments.error) throw comments.error;
  if (reactions.error) throw reactions.error;
  const ownerId = video.data?.owner_id ?? "";
  return {
    comments: (comments.data ?? []).map((c) => toComment(c, ownerId)),
    reactions: (reactions.data ?? []).map(toReaction),
  };
}

export async function getMe(userId: string, email?: string | null): Promise<Me> {
  const [profileRes, plan, activeLinks, userRes] = await Promise.all([
    db().from("profiles").select("display_name, brand_color, email_alerts").eq("id", userId).maybeSingle(),
    getPlan(userId),
    activeLinkCount(userId),
    email === undefined ? db().auth.admin.getUserById(userId) : Promise.resolve(null),
  ]);
  const limits = limitsFor(plan.tier);
  return {
    user: {
      id: userId,
      email: email ?? userRes?.data?.user?.email ?? null,
      displayName: profileRes.data?.display_name ?? null,
      emailAlerts: profileRes.data?.email_alerts ?? true,
      brandColor: profileRes.data?.brand_color ?? null,
    },
    plan: { tier: plan.tier, productId: plan.productId, expiresAt: plan.expiresAt },
    usage: {
      activeLinks,
      linkLimit: limits.linkLimit,
      maxDurationS: limits.maxDurationS,
      quality: limits.quality,
    },
  };
}
