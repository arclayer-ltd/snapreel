import "server-only";
import { viewerUser, type AuthUser } from "./auth";
import { HttpError } from "./http";
import { resolvePublicVideo, type PublicVideoError } from "./queries";
import type { VideoRow } from "./shape";
import { db } from "./supabase";
import { VIEWER_COOKIE, newViewerSession, readCookie, readViewerSession, unlockCookieName, viewerCookieHeader } from "./tokens";

export interface PublicContext {
  video: VideoRow;
  isOwner: boolean;
  viewer: AuthUser | null;
  sessionId: string;
  /** Set-Cookie for a new `sr_vs` session, or null when the request already had a valid one. */
  setCookie: string | null;
}

const MESSAGES: Record<PublicVideoError["error"], [number, string]> = {
  password: [401, "This video needs a password."],
  expired: [410, "This link has expired."],
  removed: [410, "The owner stopped sharing this video."],
  not_found: [404, "That link doesn't exist."],
};

export function publicError(code: PublicVideoError["error"]): HttpError {
  const [status, message] = MESSAGES[code];
  return new HttpError(status, code, message);
}

// Resolves a public slug with the viewer's cookies (unlock, session) and applies the access rules.
export async function publicContext(req: Request, slug: string): Promise<PublicContext> {
  const viewer = await viewerUser();
  const resolved = await resolvePublicVideo(slug, {
    unlockCookie: readCookie(req, unlockCookieName(slug)),
    viewerUserId: viewer?.id ?? null,
  });
  if ("error" in resolved) throw publicError(resolved.error);
  let sessionId = readViewerSession(readCookie(req, VIEWER_COOKIE));
  let setCookie: string | null = null;
  if (!sessionId) {
    const fresh = newViewerSession();
    sessionId = fresh.id;
    setCookie = viewerCookieHeader(fresh.cookie);
  }
  return { ...resolved, viewer, sessionId, setCookie };
}

export function withCookie(setCookie: string | null): HeadersInit | undefined {
  return setCookie ? { "Set-Cookie": setCookie } : undefined;
}

// Blocked viewers (by session or signed-in user) can't comment or react on any of that owner's videos.
export async function assertNotBlocked(ownerId: string, sessionId: string, userId: string | null): Promise<void> {
  let query = db().from("blocks").select("id").eq("owner_id", ownerId);
  query = userId ? query.or(`session_id.eq.${sessionId},user_id.eq.${userId}`) : query.eq("session_id", sessionId);
  const { data, error } = await query.limit(1);
  if (error) throw error;
  if (data?.length) throw new HttpError(403, "blocked", "The owner of this video has turned off your comments and reactions.");
}
