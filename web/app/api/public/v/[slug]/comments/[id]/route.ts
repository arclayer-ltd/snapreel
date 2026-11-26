import { assertSameOrigin, is, noContent, notFound, run } from "@/lib/server/http";
import { publicContext, withCookie } from "@/lib/server/public";
import { rateLimit } from "@/lib/server/ratelimit";
import { db } from "@/lib/server/supabase";

// DELETE /api/public/v/{slug}/comments/{id}: a viewer takes back their own comment (and its replies go with it, as
// when the owner deletes one). "Own" means written in this browser session, or by this signed-in account. 204, or 404
// for anything else, so it says nothing about other people's comments.
export async function DELETE(req: Request, ctx: RouteContext<"/api/public/v/[slug]/comments/[id]">) {
  return run(async () => {
    assertSameOrigin(req);
    const { slug, id } = await ctx.params;
    const { video, viewer, sessionId, setCookie } = await publicContext(req, slug);
    if (!is.uuid(id)) throw notFound("comment");
    await rateLimit(req, "comment", sessionId);
    const { data: comment } = await db()
      .from("comments")
      .select("id, session_id, author_user_id")
      .eq("id", id)
      .eq("video_id", video.id)
      .is("deleted_at", null)
      .maybeSingle();
    const mine = !!comment && (comment.session_id === sessionId || (!!viewer && comment.author_user_id === viewer.id));
    if (!mine) throw notFound("comment");
    const { error } = await db().from("comments").update({ deleted_at: new Date().toISOString() }).eq("id", id);
    if (error) throw error;
    return noContent(withCookie(setCookie));
  });
}
