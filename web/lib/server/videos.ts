import "server-only";
import { LIMITS, type CreateVideoRequest, type CreateVideoResponse, type Transcript, type UpdateVideoRequest } from "@/lib/contract";
import type { TablesUpdate } from "./database.types";
import { HttpError, badRequest, is, limitError, notFound } from "./http";
import { activeLinkCount, getPlan, limitsFor } from "./plan";
import { ownerVideoRow } from "./queries";
import { watchUrl, type VideoRow } from "./shape";
import { listFolder, removePrefix, videoPaths } from "./storage";
import { BUCKET, db } from "./supabase";
import { hashPassword, newSlug } from "./tokens";
import { oneLine } from "./viewer";

const KINDS = new Set(["screen", "camera", "audio"]);
const MAX_TRANSCRIPT_BYTES = 400_000;

export function parseTranscript(value: unknown): Transcript | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "object" || Array.isArray(value)) throw badRequest("transcript must be {locale, segments}.");
  const t = value as Record<string, unknown>;
  if (typeof t.locale !== "string" || !Array.isArray(t.segments)) throw badRequest("transcript must be {locale, segments}.");
  const segments = t.segments.map((s) => {
    const seg = s as Record<string, unknown>;
    if (!is.num(seg.start) || !is.num(seg.duration) || typeof seg.text !== "string") {
      throw badRequest("Each transcript segment needs start, duration and text.");
    }
    return { start: seg.start, duration: seg.duration, text: seg.text.slice(0, 2000) };
  });
  const transcript = { locale: t.locale.slice(0, 35), segments };
  if (JSON.stringify(transcript).length > MAX_TRANSCRIPT_BYTES) throw new HttpError(413, "too_large", "The transcript is too long.");
  return transcript;
}

function parseCreate(body: Record<string, unknown>): CreateVideoRequest {
  if (!is.uuid(body.localId)) throw badRequest("localId must be the phone's video UUID.");
  if (typeof body.kind !== "string" || !KINDS.has(body.kind)) throw badRequest("kind must be screen, camera or audio.");
  if (!is.num(body.durationS) || body.durationS < 0) throw badRequest("durationS must be a number of seconds.");
  for (const k of ["width", "height", "sizeBytes"] as const) {
    if (!is.num(body[k]) || (body[k] as number) < 0 || !Number.isInteger(body[k])) throw badRequest(`${k} must be a whole number.`);
  }
  if ((body.sizeBytes as number) > LIMITS.maxFileBytes) throw new HttpError(413, "too_large", "Videos can be up to 2 GB.");
  return {
    localId: body.localId.toLowerCase(),
    title: oneLine(body.title, 200),
    kind: body.kind as CreateVideoRequest["kind"],
    durationS: body.durationS,
    width: body.width as number,
    height: body.height as number,
    sizeBytes: body.sizeBytes as number,
    transcript: parseTranscript(body.transcript),
  };
}

function createResponse(v: VideoRow, tier: "free" | "pro"): CreateVideoResponse {
  const p = videoPaths(v.owner_id, v.id);
  const limits = limitsFor(tier);
  return {
    id: v.id,
    slug: v.slug,
    url: watchUrl(v.slug),
    status: v.status,
    upload: { bucket: BUCKET, videoPath: p.video, posterPath: p.poster, previewPath: p.preview },
    limits: { maxDurationS: limits.maxDurationS, maxLongSide: limits.maxLongSide },
  };
}

// POST /api/videos. Returns [status, body]: 200 with the existing link if this phone video is already shared.
export async function createVideo(userId: string, raw: Record<string, unknown>): Promise<[number, CreateVideoResponse]> {
  const input = parseCreate(raw);
  const plan = await getPlan(userId);
  const supabase = db();
  const { data: existing } = await supabase
    .from("videos")
    .select("*")
    .eq("owner_id", userId)
    .eq("local_id", input.localId)
    .is("deleted_at", null)
    .maybeSingle();
  if (existing) return [200, createResponse(existing, plan.tier)];

  const limits = limitsFor(plan.tier);
  if (input.durationS > limits.maxDurationS + 0.5) {
    throw limitError(
      "duration",
      plan.isPro ? "Shared videos can be up to 2 hours." : "Free links are for videos up to 5 minutes. Get Snapreel Pro for up to 2 hours.",
    );
  }
  if (limits.linkLimit !== null && (await activeLinkCount(userId)) >= limits.linkLimit) {
    throw limitError("links", `Free includes ${limits.linkLimit} active links. Stop sharing one, or get Snapreel Pro for unlimited links.`);
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    const { data, error } = await supabase
      .from("videos")
      .insert({
        owner_id: userId,
        slug: newSlug(),
        local_id: input.localId,
        title: input.title,
        kind: input.kind,
        duration_s: input.durationS,
        width: input.width,
        height: input.height,
        size_bytes: input.sizeBytes,
        transcript: input.transcript as never,
      })
      .select("*")
      .single();
    if (!error) return [201, createResponse(data, plan.tier)];
    if (error.code !== "23505") throw error;
    // A unique clash: either the slug (retry) or a concurrent create for the same localId (return that one).
    const { data: raced } = await supabase
      .from("videos")
      .select("*")
      .eq("owner_id", userId)
      .eq("local_id", input.localId)
      .is("deleted_at", null)
      .maybeSingle();
    if (raced) return [200, createResponse(raced, plan.tier)];
  }
  throw new Error("Couldn't make a unique link");
}

function proOnly(isPro: boolean, what: string) {
  if (!isPro) throw limitError("pro_feature", `${what} is part of Snapreel Pro.`);
}

// PATCH /api/videos/{id}. Plan rules are enforced here; the app's own checks are only for show.
export async function updateVideo(video: VideoRow, raw: Record<string, unknown>): Promise<VideoRow> {
  const body = raw as UpdateVideoRequest & Record<string, unknown>;
  const update: TablesUpdate<"videos"> = {};
  const plan = await getPlan(video.owner_id);

  if ("title" in body) update.title = oneLine(body.title, 200);
  if ("uploadedBytes" in body) {
    if (!is.num(body.uploadedBytes) || body.uploadedBytes < 0) throw badRequest("uploadedBytes must be a number.");
    update.uploaded_bytes = Math.min(Math.floor(body.uploadedBytes), Number(video.size_bytes) || Math.floor(body.uploadedBytes));
  }
  if ("transcript" in body) update.transcript = parseTranscript(body.transcript) as never;
  if ("allowComments" in body) {
    if (!is.bool(body.allowComments)) throw badRequest("allowComments must be true or false.");
    update.allow_comments = body.allowComments;
  }
  if ("allowReactions" in body) {
    if (!is.bool(body.allowReactions)) throw badRequest("allowReactions must be true or false.");
    update.allow_reactions = body.allowReactions;
  }
  if ("allowDownload" in body) {
    if (!is.bool(body.allowDownload)) throw badRequest("allowDownload must be true or false.");
    if (body.allowDownload) proOnly(plan.isPro, "Letting viewers download");
    update.allow_download = body.allowDownload;
  }
  if ("expiresAt" in body) {
    if (body.expiresAt === null) update.expires_at = null;
    else {
      proOnly(plan.isPro, "Link expiry");
      const t = typeof body.expiresAt === "string" ? Date.parse(body.expiresAt) : NaN;
      if (!Number.isFinite(t)) throw badRequest("expiresAt must be an ISO date or null.");
      update.expires_at = new Date(t).toISOString();
    }
  }
  if ("cta" in body) {
    if (body.cta === null) update.cta = null;
    else {
      proOnly(plan.isPro, "A call-to-action button");
      const cta = body.cta as { label?: unknown; url?: unknown };
      const label = oneLine(cta?.label, 40);
      const url = typeof cta?.url === "string" ? cta.url.trim() : "";
      if (!label || !/^https?:\/\/[^\s]+$/i.test(url) || url.length > 500) {
        throw badRequest("cta needs a label (up to 40 characters) and an http(s) URL.");
      }
      update.cta = { label, url };
    }
  }
  if ("password" in body || "access" in body) {
    const access = "access" in body ? body.access : "password" in body && body.password ? "password" : video.access;
    if (access !== "link" && access !== "password") throw badRequest("access must be link or password.");
    if (access === "link") {
      update.access = "link";
      update.password_hash = null;
    } else {
      proOnly(plan.isPro, "Password protection");
      const password = typeof body.password === "string" ? body.password : "";
      if (password) {
        if (password.length < 4 || password.length > 128) throw badRequest("Passwords are 4 to 128 characters.");
        update.password_hash = await hashPassword(password);
      } else if (!video.password_hash) {
        throw badRequest("Set a password to protect this link.");
      }
      update.access = "password";
    }
  }
  if ("status" in body) {
    if (body.status !== "ready" && body.status !== "failed" && body.status !== "uploading") {
      throw badRequest("status must be uploading, ready or failed.");
    }
    if (body.status === "ready") {
      const files = await listFolder(videoPaths(video.owner_id, video.id).base);
      const missing = ["video.mp4", "poster.jpg", "preview.mp4"].filter((f) => !files.has(f));
      if (missing.length) {
        throw new HttpError(409, "upload_incomplete", `Still missing: ${missing.join(", ")}.`, { missing });
      }
      const size = files.get("video.mp4") ?? 0;
      if (size > LIMITS.maxFileBytes) throw new HttpError(413, "too_large", "Videos can be up to 2 GB.");
      update.size_bytes = size || Number(video.size_bytes);
      update.uploaded_bytes = update.size_bytes;
    }
    update.status = body.status;
  }
  if (!Object.keys(update).length) return video;
  const { data, error } = await db().from("videos").update(update).eq("id", video.id).select("*").single();
  if (error) throw error;
  return data;
}

// DELETE /api/videos/{id}: stops sharing at once. Files, views, comments, reactions, reports and alerts go;
// the row stays as a tombstone (slug only) so the link says "removed" (the daily cron purges it after 30 days).
export async function stopSharing(video: VideoRow): Promise<void> {
  await removePrefix(videoPaths(video.owner_id, video.id).base);
  const supabase = db();
  await Promise.all(
    (["views", "comments", "reactions", "reports", "notification_log"] as const).map(async (table) => {
      const { error } = await supabase.from(table).delete().eq("video_id", video.id);
      if (error) throw error;
    }),
  );
  const { error } = await supabase
    .from("videos")
    .update({
      deleted_at: new Date().toISOString(),
      title: "",
      transcript: null,
      cta: null,
      password_hash: null,
      access: "link",
      uploaded_bytes: 0,
    })
    .eq("id", video.id);
  if (error) throw error;
}

export async function requireOwnerVideo(userId: string, id: string): Promise<VideoRow> {
  const video = await ownerVideoRow(userId, id);
  if (!video) throw notFound();
  return video;
}
