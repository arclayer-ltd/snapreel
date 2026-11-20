import "server-only";
import { HttpError } from "./http";
import { videoBySlug } from "./queries";
import { signUrls, videoPaths } from "./storage";

// Stable URLs for link previews (og:image, og:video, oEmbed thumbnails, the email preview): they redirect to a
// fresh signed URL. Only links anyone can open get one; password-protected, expired or removed links show a
// generic preview instead, so nothing leaks.
export async function previewRedirect(slug: string, file: "poster" | "preview"): Promise<Response> {
  const video = await videoBySlug(slug);
  const open =
    video &&
    !video.deleted_at &&
    video.access === "link" &&
    !(video.expires_at && Date.parse(video.expires_at) <= Date.now()) &&
    (file === "poster" || video.status === "ready");
  if (!video || !open) throw new HttpError(404, "not_found", "No preview for that link.");
  const path = videoPaths(video.owner_id, video.id)[file];
  const url = (await signUrls([path])).get(path);
  if (!url) throw new HttpError(404, "not_found", "No preview for that link.");
  return new Response(null, {
    status: 302,
    headers: { Location: url, "Cache-Control": "public, max-age=600, s-maxage=600" },
  });
}
