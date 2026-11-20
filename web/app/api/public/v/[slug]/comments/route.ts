import crypto from "node:crypto";
import { after } from "next/server";
import type { Comment } from "@/lib/contract";
import { HttpError, badRequest, is, json, readJson, run } from "@/lib/server/http";
import { needsReview } from "@/lib/server/moderation";
import { notifyComment } from "@/lib/server/notify";
import { assertNotBlocked, publicContext, withCookie } from "@/lib/server/public";
import { rateLimit } from "@/lib/server/ratelimit";
import { toComment } from "@/lib/server/shape";
import { db } from "@/lib/server/supabase";
import { oneLine } from "@/lib/server/viewer";

// POST /api/public/v/{slug}/comments {name, body, atS, parentId?, website} -> 201 Comment.
// `website` is a honeypot: a bot that fills it gets a normal-looking answer and nothing is stored.
// A viewer's comment whose name or text matches the word list (lib/server/moderation.ts) is stored as held: the answer
// says `held: true`, other viewers never see it, and the owner approves or deletes it. The owner is never held.
export async function POST(req: Request, ctx: RouteContext<"/api/public/v/[slug]/comments">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video, isOwner, viewer, sessionId, setCookie } = await publicContext(req, slug);
    const headers = withCookie(setCookie);
    if (!video.allow_comments) throw new HttpError(403, "comments_off", "Comments are turned off for this video.");
    await rateLimit(req, "comment", sessionId);
    const body = await readJson(req, 8_000);

    const text = typeof body.body === "string" ? body.body.replace(/\r\n/g, "\n").trim() : "";
    if (!text || text.length > 1000) throw badRequest("Comments are 1 to 1,000 characters.");
    let name = oneLine(body.name, 60);
    if (!name && viewer) {
      const { data } = await db().from("profiles").select("display_name").eq("id", viewer.id).maybeSingle();
      name = data?.display_name ?? "";
    }
    if (!name) throw badRequest("Add your name.");
    const atS = body.atS === null || body.atS === undefined ? null : is.num(body.atS) ? Math.max(0, body.atS) : NaN;
    if (Number.isNaN(atS)) throw badRequest("atS must be seconds or null.");

    if (typeof body.website === "string" && body.website.trim()) {
      const fake: Comment = {
        id: crypto.randomUUID(),
        authorName: name,
        isOwner: false,
        body: text,
        atS,
        parentId: null,
        createdAt: new Date().toISOString(),
        held: false,
      };
      return json(fake, 201, headers);
    }
    if (!isOwner) await assertNotBlocked(video.owner_id, sessionId, viewer?.id ?? null);

    let parentId: string | null = null;
    if (body.parentId !== undefined && body.parentId !== null) {
      if (!is.uuid(body.parentId)) throw badRequest("parentId must be a comment ID.");
      const { data: parent } = await db()
        .from("comments")
        .select("id")
        .eq("id", body.parentId)
        .eq("video_id", video.id)
        .eq("held", false)
        .is("deleted_at", null)
        .maybeSingle();
      if (!parent) throw badRequest("You're replying to a comment that isn't there any more.");
      parentId = parent.id;
    }

    const held = !isOwner && needsReview(name, text);
    const { data: row, error } = await db()
      .from("comments")
      .insert({
        video_id: video.id,
        session_id: sessionId,
        author_user_id: viewer?.id ?? null,
        author_name: name,
        body: text,
        at_s: atS,
        parent_id: parentId,
        held,
      })
      .select("*")
      .single();
    if (error) throw error;

    // Name this session's views, so insights show who watched (not with a name the filter caught).
    if (!held) {
      await db().from("views").update({ viewer_name: row.author_name }).eq("video_id", video.id).eq("session_id", sessionId).is("viewer_name", null);
    }

    if (!isOwner) {
      after(() =>
        notifyComment(video, { id: row.id, authorName: row.author_name, body: row.body, atS: row.at_s, held }).catch((e) =>
          console.error("[comments] notify", e),
        ),
      );
    }
    return json(toComment(row, video.owner_id), 201, headers);
  });
}
