import "server-only";
import type { CallToAction, Comment, Reaction, Transcript, VideoDetail, VideoSummary } from "@/lib/contract";
import type { Tables } from "./database.types";
import { SITE_URL } from "./env";

export type VideoRow = Tables<"videos">;
export type CommentRow = Tables<"comments">;
export type ReactionRow = Tables<"reactions">;

export interface VideoStats {
  views: number;
  uniqueViewers: number;
  lastViewedAt: string | null;
  commentCount: number;
}

export const EMPTY_STATS: VideoStats = { views: 0, uniqueViewers: 0, lastViewedAt: null, commentCount: 0 };

export const watchUrl = (slug: string) => `${SITE_URL}/v/${slug}`;
export const dashboardUrl = (videoId: string) => `${SITE_URL}/app/v/${videoId}`;

export function toSummary(v: VideoRow, stats: VideoStats, posterUrl: string | null): VideoSummary {
  return {
    id: v.id,
    slug: v.slug,
    url: watchUrl(v.slug),
    localId: v.local_id,
    title: v.title,
    kind: v.kind,
    durationS: Number(v.duration_s),
    status: v.status,
    posterUrl,
    createdAt: v.created_at,
    views: stats.views,
    uniqueViewers: stats.uniqueViewers,
    lastViewedAt: stats.lastViewedAt,
    commentCount: stats.commentCount,
    access: v.access,
    expiresAt: v.expires_at,
  };
}

export function toDetail(v: VideoRow, stats: VideoStats, posterUrl: string | null): VideoDetail {
  return {
    ...toSummary(v, stats, posterUrl),
    hasPassword: !!v.password_hash,
    allowDownload: v.allow_download,
    allowComments: v.allow_comments,
    allowReactions: v.allow_reactions,
    cta: asCta(v.cta),
    width: v.width,
    height: v.height,
    sizeBytes: Number(v.size_bytes),
  };
}

export function toComment(c: CommentRow, ownerId: string): Comment {
  return {
    id: c.id,
    authorName: c.author_name,
    isOwner: !!c.author_user_id && c.author_user_id === ownerId,
    body: c.body,
    atS: c.at_s === null ? null : Number(c.at_s),
    parentId: c.parent_id,
    createdAt: c.created_at,
  };
}

export function toReaction(r: ReactionRow): Reaction {
  return { id: r.id, emoji: r.emoji, atS: Number(r.at_s), authorName: r.author_name, createdAt: r.created_at };
}

export function asCta(value: unknown): CallToAction | null {
  if (!value || typeof value !== "object") return null;
  const { label, url } = value as Record<string, unknown>;
  return typeof label === "string" && typeof url === "string" ? { label, url } : null;
}

export function asTranscript(value: unknown): Transcript | null {
  if (!value || typeof value !== "object") return null;
  const t = value as Transcript;
  return typeof t.locale === "string" && Array.isArray(t.segments) ? t : null;
}

export function formatTimestamp(s: number): string {
  const total = Math.max(0, Math.floor(s));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const sec = String(total % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}
