import { json, run } from "@/lib/server/http";
import { publicContext, withCookie } from "@/lib/server/public";
import { buildPublicVideo } from "@/lib/server/queries";

// GET /api/public/v/{slug}: everything the watch page needs, with signed URLs valid for 2 hours.
// 401 {error: "password"}, 410 {error: "expired" | "removed"}, 404 {error: "not_found"}.
export async function GET(req: Request, ctx: RouteContext<"/api/public/v/[slug]">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video, setCookie } = await publicContext(req, slug);
    return json(await buildPublicVideo(video), 200, withCookie(setCookie));
  });
}
