import { requireUser } from "@/lib/server/auth";
import { is, noContent, notFound, run } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";

// DELETE /api/comments/{id}: the video's owner hides a comment.
export async function DELETE(req: Request, ctx: RouteContext<"/api/comments/[id]">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    if (!is.uuid(id)) throw notFound("comment");
    const { data: comment } = await db().from("comments").select("id, video_id").eq("id", id).maybeSingle();
    if (!comment) throw notFound("comment");
    const { data: video } = await db().from("videos").select("owner_id").eq("id", comment.video_id).maybeSingle();
    if (!video || video.owner_id !== user.id) throw notFound("comment");
    const { error } = await db().from("comments").update({ deleted_at: new Date().toISOString() }).eq("id", id);
    if (error) throw error;
    return noContent();
  });
}
