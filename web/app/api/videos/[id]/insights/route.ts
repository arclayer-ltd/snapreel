import { requireUser } from "@/lib/server/auth";
import { json, notFound, run } from "@/lib/server/http";
import { getInsights } from "@/lib/server/queries";

// GET /api/videos/{id}/insights. Free gets views and uniqueViewers; the rest is null.
export async function GET(req: Request, ctx: RouteContext<"/api/videos/[id]/insights">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    const insights = await getInsights(user.id, id);
    if (!insights) throw notFound();
    return json(insights);
  });
}
