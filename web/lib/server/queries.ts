// STUB: replaced by the backend's version at merge.
//
// Same names and shapes as the backend's server functions (docs/pro/API.md). Returns the sample data in
// lib/client/preview-data.ts so the watch page and dashboard build and run before Supabase is wired up.
import "server-only";

import { connection } from "next/server";
import type {
  Activity,
  Insights,
  Me,
  PublicVideo,
  Tier,
  VideoDetail,
  VideoSummary,
} from "@/lib/contract";
import {
  PREVIEW_REMOVED_SLUG,
  insightsForTier,
  previewMe,
  previewVideos,
} from "@/lib/client/preview-data";

export type PublicVideoError = { error: "password" | "expired" | "removed" | "not_found" };

/** The preview user ids are "preview-free" and "preview-pro"; anyone else is treated as Free. */
function tierOf(userId: string): Tier {
  return userId === "preview-pro" ? "pro" : "free";
}

function summary(detail: VideoDetail): VideoSummary {
  return {
    id: detail.id,
    slug: detail.slug,
    url: detail.url,
    localId: detail.localId,
    title: detail.title,
    kind: detail.kind,
    durationS: detail.durationS,
    status: detail.status,
    posterUrl: detail.posterUrl,
    createdAt: detail.createdAt,
    views: detail.views,
    uniqueViewers: detail.uniqueViewers,
    lastViewedAt: detail.lastViewedAt,
    commentCount: detail.commentCount,
  };
}

export async function getPublicVideo(
  slug: string,
  opts: { unlockCookie: string | null; viewerUserId: string | null },
): Promise<PublicVideo | PublicVideoError> {
  await connection(); // the sample data reads the clock, so it is request-time only
  if (slug === PREVIEW_REMOVED_SLUG) return { error: "removed" };
  const found = previewVideos(Date.now()).find((v) => v.detail.slug === slug);
  if (!found) return { error: "not_found" };
  if (found.publicError === "password") {
    const isOwner = opts.viewerUserId?.startsWith("preview-") ?? false;
    if (!opts.unlockCookie && !isOwner) return { error: "password" };
    return found.publicVideo;
  }
  if (found.publicError) return { error: found.publicError };
  return found.publicVideo;
}

export async function getOwnerVideos(userId: string): Promise<VideoSummary[]> {
  await connection(); // the sample data reads the clock, so it is request-time only
  void userId;
  return previewVideos(Date.now()).map((v) => summary(v.detail));
}

export async function getOwnerVideo(userId: string, id: string): Promise<VideoDetail | null> {
  await connection(); // the sample data reads the clock, so it is request-time only
  void userId;
  return previewVideos(Date.now()).find((v) => v.detail.id === id)?.detail ?? null;
}

export async function getInsights(userId: string, id: string): Promise<Insights | null> {
  await connection(); // the sample data reads the clock, so it is request-time only
  const found = previewVideos(Date.now()).find((v) => v.detail.id === id);
  return found ? insightsForTier(found.insights, tierOf(userId)) : null;
}

export async function getActivity(videoId: string): Promise<Activity> {
  await connection(); // the sample data reads the clock, so it is request-time only
  return previewVideos(Date.now()).find((v) => v.detail.id === videoId)?.activity ?? { comments: [], reactions: [] };
}

export async function getMe(userId: string): Promise<Me> {
  await connection(); // the sample data reads the clock, so it is request-time only
  const active = previewVideos(Date.now()).filter((v) => v.detail.status !== "failed").length;
  return previewMe(tierOf(userId), active);
}
