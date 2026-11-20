import { requireUser } from "@/lib/server/auth";
import { json, run } from "@/lib/server/http";
import { getActivity } from "@/lib/server/queries";
import { requireOwnerVideo } from "@/lib/server/videos";

// GET /api/videos/{id}/activity: {comments, reactions} for the owner.
export async function GET(req: Request, ctx: RouteContext<"/api/videos/[id]/activity">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    const video = await requireOwnerVideo(user.id, id);
    return json(await getActivity(video.id));
  });
}
