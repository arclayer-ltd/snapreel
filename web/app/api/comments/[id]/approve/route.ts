import { requireUser } from "@/lib/server/auth";
import { is, json, notFound, run } from "@/lib/server/http";
import { toComment } from "@/lib/server/shape";
import { db } from "@/lib/server/supabase";

// POST /api/comments/{id}/approve -> Comment: the video's owner publishes a comment the word filter held.
// Approving a comment that isn't held is a no-op that returns it as it is.
export async function POST(req: Request, ctx: RouteContext<"/api/comments/[id]/approve">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    if (!is.uuid(id)) throw notFound("comment");
    const { data: comment } = await db().from("comments").select("id, video_id").eq("id", id).is("deleted_at", null).maybeSingle();
    if (!comment) throw notFound("comment");
    const { data: video } = await db().from("videos").select("owner_id").eq("id", comment.video_id).maybeSingle();
    if (!video || video.owner_id !== user.id) throw notFound("comment");
    const { data: row, error } = await db().from("comments").update({ held: false }).eq("id", id).select("*").single();
    if (error) throw error;
    return json(toComment(row, video.owner_id));
  });
}
