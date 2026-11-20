import { run } from "@/lib/server/http";
import { previewRedirect } from "@/lib/server/media";

// GET /api/public/v/{slug}/preview.mp4 -> 302 to the signed 3-second silent preview (link previews, email paste).
export async function GET(_req: Request, ctx: RouteContext<"/api/public/v/[slug]/preview.mp4">) {
  return run(async () => previewRedirect((await ctx.params).slug, "preview"));
}
