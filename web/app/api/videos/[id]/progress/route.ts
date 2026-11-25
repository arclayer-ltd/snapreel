import { requireUser } from "@/lib/server/auth";
import { noContent, readJson, run } from "@/lib/server/http";
import { saveProgress } from "@/lib/server/videos";

// POST /api/videos/{id}/progress {uploadedBytes, totalBytes?}: the upload's progress for the watch page. 204 for any
// signed-in owner, also when the link has finished or gone meanwhile.
export async function POST(req: Request, ctx: RouteContext<"/api/videos/[id]/progress">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    await saveProgress(user.id, id, await readJson(req));
    return noContent();
  });
}
