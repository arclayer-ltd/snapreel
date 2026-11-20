import "server-only";
import { HttpError, assertSameOrigin } from "./http";
import { getSessionUser, type SessionUser } from "./session";
import { db } from "./supabase";

export type AuthUser = SessionUser;

// Owner endpoints: the app sends `Authorization: Bearer <access_token>`; the web dashboard uses its cookie session.
// Either way the token is checked with Supabase Auth (auth.getUser), so a signed-out or deleted user fails.
export async function optionalUser(req: Request): Promise<AuthUser | null> {
  const header = req.headers.get("authorization");
  if (header && /^bearer\s+/i.test(header)) {
    const token = header.replace(/^bearer\s+/i, "").trim();
    if (!token) throw new HttpError(401, "unauthorized", "Sign in first.");
    const { data, error } = await db().auth.getUser(token);
    if (error || !data.user) throw new HttpError(401, "unauthorized", "Your session has ended. Sign in again.");
    return { id: data.user.id, email: data.user.email ?? null };
  }
  return getSessionUser();
}

export async function requireUser(req: Request): Promise<AuthUser> {
  const user = await optionalUser(req);
  if (!user) throw new HttpError(401, "unauthorized", "Sign in first.");
  if (req.method !== "GET" && req.method !== "HEAD" && !req.headers.get("authorization")) assertSameOrigin(req);
  return user;
}

// For public endpoints: who is watching, when they are signed in on the web. Never throws.
export async function viewerUser(): Promise<AuthUser | null> {
  try {
    return await getSessionUser();
  } catch {
    return null;
  }
}
