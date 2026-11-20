import { requireUser } from "@/lib/server/auth";
import { json, readJson, run } from "@/lib/server/http";
import { getOwnerVideos } from "@/lib/server/queries";
import { createVideo } from "@/lib/server/videos";

// GET /api/videos: the signed-in user's shared videos, newest first.
export async function GET(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    return json(await getOwnerVideos(user.id));
  });
}

// POST /api/videos: makes the link at once (status "uploading"); the app then uploads with TUS.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const [status, body] = await createVideo(user.id, await readJson(req, 600_000));
    return json(body, status);
  });
}
