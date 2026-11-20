import { requireUser } from "@/lib/server/auth";
import { badRequest, is, noContent, notFound, readJson, run } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";

// POST /api/blocks {commentId} or {reactionId}: blocks that viewer (their browser session, and their account when
// they were signed in) from commenting or reacting on any of your videos.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    const isComment = is.uuid(body.commentId);
    if (!isComment && !is.uuid(body.reactionId)) throw badRequest("Send commentId or reactionId.");
    const what = isComment ? "comment" : "reaction";
    const id = String(isComment ? body.commentId : body.reactionId);
    const { data: row } = isComment
      ? await db().from("comments").select("video_id, session_id, author_user_id").eq("id", id).maybeSingle()
      : await db().from("reactions").select("video_id, session_id, author_user_id").eq("id", id).maybeSingle();
    if (!row) throw notFound(what);
    const { data: video } = await db().from("videos").select("owner_id").eq("id", row.video_id).maybeSingle();
    if (!video || video.owner_id !== user.id) throw notFound(what);

    const rows: { owner_id: string; session_id: string | null; user_id: string | null }[] = [
      { owner_id: user.id, session_id: row.session_id, user_id: null },
    ];
    if (row.author_user_id && row.author_user_id !== user.id) {
      rows.push({ owner_id: user.id, session_id: null, user_id: row.author_user_id });
    }
    for (const r of rows) {
      const { error } = await db().from("blocks").insert(r);
      if (error && error.code !== "23505") throw error; // already blocked is fine
    }
    return noContent();
  });
}
