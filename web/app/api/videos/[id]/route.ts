import { requireUser } from "@/lib/server/auth";
import { json, noContent, notFound, readJson, run } from "@/lib/server/http";
import { detailFor, getOwnerVideo } from "@/lib/server/queries";
import { requireOwnerVideo, stopSharing, updateVideo } from "@/lib/server/videos";

export async function GET(req: Request, ctx: RouteContext<"/api/videos/[id]">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    const video = await getOwnerVideo(user.id, id);
    if (!video) throw notFound();
    return json(video);
  });
}

// PATCH /api/videos/{id}: settings, upload progress, and {status: "ready"} once all three files are up.
export async function PATCH(req: Request, ctx: RouteContext<"/api/videos/[id]">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    const video = await requireOwnerVideo(user.id, id);
    const updated = await updateVideo(video, await readJson(req, 600_000));
    return json(await detailFor(updated));
  });
}

// DELETE /api/videos/{id}: stops sharing and deletes the files.
export async function DELETE(req: Request, ctx: RouteContext<"/api/videos/[id]">) {
  return run(async () => {
    const user = await requireUser(req);
    const { id } = await ctx.params;
    await stopSharing(await requireOwnerVideo(user.id, id));
    return noContent();
  });
}
