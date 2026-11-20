import { run } from "@/lib/server/http";
import { previewRedirect } from "@/lib/server/media";

// GET /api/public/v/{slug}/poster.jpg -> 302 to a signed poster URL (link previews, oEmbed, email).
export async function GET(_req: Request, ctx: RouteContext<"/api/public/v/[slug]/poster.jpg">) {
  return run(async () => previewRedirect((await ctx.params).slug, "poster"));
}
