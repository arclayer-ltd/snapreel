import { json, run } from "@/lib/server/http";
import { publicContext, withCookie } from "@/lib/server/public";
import { getActivity } from "@/lib/server/queries";

// GET /api/public/v/{slug}/activity -> {comments, reactions}, after the same access checks as the video.
export async function GET(req: Request, ctx: RouteContext<"/api/public/v/[slug]/activity">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video, setCookie } = await publicContext(req, slug);
    return json(await getActivity(video.id), 200, withCookie(setCookie));
  });
}
