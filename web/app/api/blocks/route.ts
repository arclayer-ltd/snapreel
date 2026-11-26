import { requireUser } from "@/lib/server/auth";
import { badRequest, is, json, noContent, notFound, readJson, run } from "@/lib/server/http";
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

// The blocks that cover a comment or reaction's author: by their browser session, and by their account if they had one.
async function blocksFor(ownerId: string, row: { session_id: string; author_user_id: string | null }) {
  let q = db().from("blocks").select("id").eq("owner_id", ownerId);
  q = row.author_user_id ? q.or(`session_id.eq.${row.session_id},user_id.eq.${row.author_user_id}`) : q.eq("session_id", row.session_id);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []).map((b) => b.id);
}

// GET /api/blocks?videoId=: which of this video's comments and reactions come from someone you blocked, so the
// dashboard can say "Blocked" and offer Unblock. {commentIds, reactionIds}.
export async function GET(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const videoId = new URL(req.url).searchParams.get("videoId");
    if (!is.uuid(videoId)) throw badRequest("Send videoId.");
    const { data: video } = await db().from("videos").select("owner_id").eq("id", videoId).maybeSingle();
    if (!video || video.owner_id !== user.id) throw notFound();
    const [blocks, comments, reactions] = await Promise.all([
      db().from("blocks").select("session_id, user_id").eq("owner_id", user.id).limit(5000),
      db().from("comments").select("id, session_id, author_user_id").eq("video_id", videoId).is("deleted_at", null).limit(1000),
      db().from("reactions").select("id, session_id, author_user_id").eq("video_id", videoId).limit(2000),
    ]);
    for (const r of [blocks, comments, reactions]) if (r.error) throw r.error;
    const sessions = new Set((blocks.data ?? []).map((b) => b.session_id).filter(Boolean));
    const users = new Set((blocks.data ?? []).map((b) => b.user_id).filter(Boolean));
    const blocked = (r: { session_id: string; author_user_id: string | null }) =>
      sessions.has(r.session_id) || (!!r.author_user_id && users.has(r.author_user_id));
    return json({
      commentIds: (comments.data ?? []).filter(blocked).map((c) => c.id),
      reactionIds: (reactions.data ?? []).filter(blocked).map((r) => r.id),
    });
  });
}

// DELETE /api/blocks {commentId} or {reactionId}: unblocks that viewer again. 204, also when they weren't blocked.
export async function DELETE(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    const isComment = is.uuid(body.commentId);
    if (!isComment && !is.uuid(body.reactionId)) throw badRequest("Send commentId or reactionId.");
    const id = String(isComment ? body.commentId : body.reactionId);
    const { data: row } = isComment
      ? await db().from("comments").select("video_id, session_id, author_user_id").eq("id", id).maybeSingle()
      : await db().from("reactions").select("video_id, session_id, author_user_id").eq("id", id).maybeSingle();
    if (!row) throw notFound(isComment ? "comment" : "reaction");
    const { data: video } = await db().from("videos").select("owner_id").eq("id", row.video_id).maybeSingle();
    if (!video || video.owner_id !== user.id) throw notFound(isComment ? "comment" : "reaction");
    const ids = await blocksFor(user.id, row);
    if (ids.length) {
      const { error } = await db().from("blocks").delete().in("id", ids).eq("owner_id", user.id);
      if (error) throw error;
    }
    return noContent();
  });
}
