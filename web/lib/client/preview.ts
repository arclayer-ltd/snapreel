"use client";

// Preview mode only: answers the API calls in the browser with the sample data, so every screen can be
// tried without Supabase. Loaded lazily by lib/client/api.ts when NEXT_PUBLIC_SUPABASE_* are missing.
import type {
  Activity,
  Comment,
  Me,
  NewComment,
  NewReaction,
  PublicVideo,
  Reaction,
  Tier,
  UpdateMeRequest,
  UpdateVideoRequest,
  VideoDetail,
} from "@/lib/contract";
import { ApiError } from "@/lib/client/api";
import {
  PREVIEW_COOKIE,
  PREVIEW_PASSWORD,
  insightsForTier,
  previewMe,
  previewVideos,
} from "@/lib/client/preview-data";

const activity = new Map<string, Activity>();
const uploadPolls = new Map<string, number>();
const videoEdits = new Map<string, Partial<VideoDetail>>();
let meEdits: UpdateMeRequest = {};

function tier(): Tier {
  return document.cookie.includes(`${PREVIEW_COOKIE}=pro`) ? "pro" : "free";
}

function wait(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

function bySlug(slug: string) {
  return previewVideos(Date.now()).find((v) => v.detail.slug === slug);
}

function byId(id: string) {
  return previewVideos(Date.now()).find((v) => v.detail.id === id);
}

function activityFor(slug: string): Activity {
  let a = activity.get(slug);
  if (!a) {
    const found = bySlug(slug);
    a = structuredClone(found?.activity ?? { comments: [], reactions: [] });
    activity.set(slug, a);
  }
  return a;
}

function me(): Me {
  const base = previewMe(tier(), previewVideos(Date.now()).length - 1);
  return {
    ...base,
    user: {
      ...base.user,
      ...(meEdits.displayName !== undefined ? { displayName: meEdits.displayName } : {}),
      ...(meEdits.emailAlerts !== undefined ? { emailAlerts: meEdits.emailAlerts } : {}),
      ...(meEdits.brandColor !== undefined ? { brandColor: meEdits.brandColor } : {}),
    },
  };
}

export async function mockRequest<T>(method: string, path: string, body?: unknown): Promise<T> {
  await wait(250 + Math.random() * 250);
  const url = new URL(path, "http://preview.local");
  const parts = url.pathname.split("/").filter(Boolean); // ["api", ...]
  const result = route(method, parts.slice(1), body);
  if (process.env.NODE_ENV !== "production") console.debug("[preview api]", method, path, body ?? "");
  return result as T;
}

function route(method: string, p: string[], body: unknown): unknown {
  // Public
  if (p[0] === "public" && p[1] === "v") {
    const slug = decodeURIComponent(p[2] ?? "");
    const found = bySlug(slug);
    const action = p[3];
    if (!found) throw new ApiError(404, "not_found");
    if (!action && method === "GET") {
      if (found.detail.status !== "uploading") return found.publicVideo;
      const n = (uploadPolls.get(slug) ?? 0) + 1;
      uploadPolls.set(slug, n);
      if (n < 3) return { ...found.publicVideo, uploadProgress: Math.min(0.97, 0.45 + n * 0.22) };
      const ready: PublicVideo = {
        ...found.publicVideo,
        status: "ready",
        uploadProgress: null,
        videoUrl: "/dev-fixtures/landscape.mp4",
        captionsUrl: "/dev-fixtures/landscape.vtt",
      };
      return ready;
    }
    if (action === "unlock") {
      const { password } = body as { password: string };
      if (password !== PREVIEW_PASSWORD) throw new ApiError(403, "wrong_password", "That password isn't right.");
      document.cookie = `sr_unlock_${slug}=1; Path=/; Max-Age=${60 * 60 * 12}; SameSite=Lax`;
      return undefined;
    }
    if (action === "activity") return activityFor(slug);
    if (action === "view") return { viewId: "preview-view" };
    if (action === "report") return undefined;
    if (action === "comments") {
      const c = body as NewComment;
      if (c.website) throw new ApiError(400, "spam");
      const comment: Comment = {
        id: `pc-${Date.now()}`,
        authorName: c.name,
        isOwner: false,
        body: c.body,
        atS: c.atS,
        parentId: c.parentId ?? null,
        createdAt: new Date().toISOString(),
      };
      activityFor(slug).comments.push(comment);
      return comment;
    }
    if (action === "reactions") {
      const r = body as NewReaction;
      const reaction: Reaction = {
        id: `pr-${Date.now()}`,
        emoji: r.emoji,
        atS: r.atS,
        authorName: r.name ?? null,
        createdAt: new Date().toISOString(),
      };
      activityFor(slug).reactions.push(reaction);
      return reaction;
    }
  }

  // Owner
  if (p[0] === "me") {
    if (method === "PATCH") meEdits = { ...meEdits, ...(body as UpdateMeRequest) };
    return me();
  }
  if (p[0] === "videos") {
    const id = p[1] ? decodeURIComponent(p[1]) : null;
    if (!id) return previewVideos(Date.now()).map((v) => v.detail);
    const found = byId(id);
    if (!found) throw new ApiError(404, "not_found");
    if (p[2] === "insights") return insightsForTier(found.insights, tier());
    if (p[2] === "activity") return activityFor(found.detail.slug);
    if (method === "DELETE") return undefined;
    if (method === "PATCH") {
      const patch = body as UpdateVideoRequest;
      const proOnly =
        patch.access === "password" ||
        patch.password !== undefined ||
        (patch.expiresAt !== undefined && patch.expiresAt !== null) ||
        patch.allowDownload === true ||
        (patch.cta !== undefined && patch.cta !== null);
      if (proOnly && tier() !== "pro") throw new ApiError(402, "limit", undefined, "pro_feature");
      const { password, ...rest } = patch;
      const prev = videoEdits.get(id) ?? {};
      const next: Partial<VideoDetail> = {
        ...prev,
        ...(rest as Partial<VideoDetail>),
        ...(password ? { hasPassword: true } : {}),
        ...(patch.access === "link" ? { hasPassword: false } : {}),
      };
      videoEdits.set(id, next);
      return { ...found.detail, ...next };
    }
    return { ...found.detail, ...(videoEdits.get(id) ?? {}) };
  }
  if (p[0] === "comments" && method === "DELETE") return undefined;
  if (p[0] === "blocks") return undefined;
  if (p[0] === "account" && p[1] === "delete") return undefined;

  throw new ApiError(404, "not_found");
}
