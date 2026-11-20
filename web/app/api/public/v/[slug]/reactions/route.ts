import { after } from "next/server";
import { HttpError, badRequest, is, json, readJson, run } from "@/lib/server/http";
import { notifyReaction } from "@/lib/server/notify";
import { assertNotBlocked, publicContext, withCookie } from "@/lib/server/public";
import { rateLimit } from "@/lib/server/ratelimit";
import { toReaction } from "@/lib/server/shape";
import { db } from "@/lib/server/supabase";
import { needsReview } from "@/lib/server/moderation";
import { isEmoji, oneLine } from "@/lib/server/viewer";

// POST /api/public/v/{slug}/reactions {emoji, atS, name?} -> 201 Reaction. Alerts are batched (one per video per
// 10 minutes). A typed name that matches the comment word filter is dropped; the reaction stays, anonymous.
export async function POST(req: Request, ctx: RouteContext<"/api/public/v/[slug]/reactions">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video, isOwner, viewer, sessionId, setCookie } = await publicContext(req, slug);
    if (!video.allow_reactions) throw new HttpError(403, "reactions_off", "Reactions are turned off for this video.");
    await rateLimit(req, "reaction", sessionId);
    const body = await readJson(req, 4_000);
    if (!isEmoji(body.emoji)) throw badRequest("emoji must be a single emoji.");
    if (!is.num(body.atS) || body.atS < 0) throw badRequest("atS must be seconds.");
    if (!isOwner) await assertNotBlocked(video.owner_id, sessionId, viewer?.id ?? null);
    const typed = oneLine(body.name, 60);
    const name = typed && !needsReview(typed) ? typed : null;

    const { data: row, error } = await db()
      .from("reactions")
      .insert({
        video_id: video.id,
        session_id: sessionId,
        author_user_id: viewer?.id ?? null,
        author_name: name,
        emoji: body.emoji,
        at_s: Math.min(body.atS, Number(video.duration_s) || body.atS),
      })
      .select("*")
      .single();
    if (error) throw error;
    if (!isOwner) after(() => notifyReaction(video).catch((e) => console.error("[reactions] notify", e)));
    return json(toReaction(row), 201, withCookie(setCookie));
  });
}
