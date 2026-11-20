import { after } from "next/server";
import { is, json, readJson, run } from "@/lib/server/http";
import { notifyView } from "@/lib/server/notify";
import { publicContext, withCookie } from "@/lib/server/public";
import { rateLimit } from "@/lib/server/ratelimit";
import { db } from "@/lib/server/supabase";
import { countryFrom, deviceFrom, isBot, referrerHost } from "@/lib/server/viewer";

// POST /api/public/v/{slug}/view {event: "start"|"progress"|"end", positionS, watched: [bucketIndex], viewId?, referrer?}
// -> {viewId}. Sent with sendBeacon on pagehide too. A view counts once it has 5 s watched, 75% of the length, or
// reaches the last second (public.record_view). The owner's own views and link-preview bots are never recorded.
export async function POST(req: Request, ctx: RouteContext<"/api/public/v/[slug]/view">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video, isOwner, viewer, sessionId, setCookie } = await publicContext(req, slug);
    const headers = withCookie(setCookie);
    const ua = req.headers.get("user-agent");
    if (isOwner || isBot(ua) || video.status !== "ready") return json({ viewId: null }, 200, headers);
    await rateLimit(req, "view", sessionId);

    const body = await readJson(req, 8_000);
    const event = body.event === "start" || body.event === "end" ? body.event : "progress";
    const position = is.num(body.positionS) ? Math.max(0, body.positionS) : 0;
    const watched = Array.isArray(body.watched)
      ? [...new Set(body.watched.filter((n): n is number => Number.isInteger(n) && n >= 0 && n < 100))]
      : [];

    let viewerName: string | null = null;
    if (viewer) {
      const { data } = await db().from("profiles").select("display_name").eq("id", viewer.id).maybeSingle();
      viewerName = data?.display_name ?? null;
    }
    const { data, error } = await db().rpc("record_view", {
      p_video_id: video.id,
      p_session_id: sessionId,
      p_event: event,
      p_view_id: is.uuid(body.viewId) ? body.viewId : null,
      p_viewer_user_id: viewer?.id ?? null,
      p_viewer_name: viewerName,
      p_country: countryFrom(req),
      p_device: deviceFrom(ua),
      p_referrer_host: referrerHost(body.referrer),
      p_position: position,
      p_watched: watched,
      p_duration: Number(video.duration_s),
    });
    if (error) throw error;
    const row = data?.[0];
    if (row?.first_for_session) {
      // The viewer's name, if they commented before watching enough to count.
      const { data: named } = await db()
        .from("views")
        .select("viewer_name")
        .eq("video_id", video.id)
        .eq("session_id", sessionId)
        .not("viewer_name", "is", null)
        .limit(1);
      const name = viewerName ?? named?.[0]?.viewer_name ?? null;
      after(() =>
        notifyView(video, { id: row.view_id, viewerName: name, percent: row.percent, sessionId }).catch((e) =>
          console.error("[view] notify", e),
        ),
      );
    }
    return json({ viewId: row?.view_id ?? null }, 200, headers);
  });
}
