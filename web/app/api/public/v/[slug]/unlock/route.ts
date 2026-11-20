import { HttpError, noContent, readJson, run } from "@/lib/server/http";
import { publicError } from "@/lib/server/public";
import { videoBySlug } from "@/lib/server/queries";
import { rateLimit } from "@/lib/server/ratelimit";
import { UNLOCK_MAX_AGE, makeUnlock, setCookieHeader, unlockCookieName, verifyPassword } from "@/lib/server/tokens";

// POST /api/public/v/{slug}/unlock {password} -> 204 and the `sr_unlock_{slug}` cookie (12 hours).
export async function POST(req: Request, ctx: RouteContext<"/api/public/v/[slug]/unlock">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const video = await videoBySlug(slug);
    if (!video) throw publicError("not_found");
    if (video.deleted_at) throw publicError("removed");
    if (video.expires_at && Date.parse(video.expires_at) <= Date.now()) throw publicError("expired");
    await rateLimit(req, "unlock", null, `:${slug}`);
    const body = await readJson(req);
    const password = typeof body.password === "string" ? body.password : "";
    if (video.access !== "password" || !video.password_hash) return noContent();
    if (!password || !(await verifyPassword(password, video.password_hash))) {
      throw new HttpError(401, "wrong_password", "That password isn't right.");
    }
    return noContent({
      "Set-Cookie": setCookieHeader(unlockCookieName(slug), makeUnlock(slug, video.password_hash), { maxAge: UNLOCK_MAX_AGE }),
    });
  });
}
