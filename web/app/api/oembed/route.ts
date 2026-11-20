import { escapeHtml } from "@/lib/server/email";
import { SITE_URL } from "@/lib/server/env";
import { HttpError, json, run } from "@/lib/server/http";
import { videoBySlug } from "@/lib/server/queries";

// GET /api/oembed?url=https://snapreel.video/v/{slug}&format=json[&maxwidth&maxheight]
// Password-protected links answer 401 and expired or removed ones 404, as the oEmbed spec asks.
export async function GET(req: Request) {
  return run(async () => {
    const params = new URL(req.url).searchParams;
    const format = params.get("format") || "json";
    if (format !== "json") throw new HttpError(501, "not_implemented", "Only format=json is supported.");
    let slug: string | null = null;
    try {
      const target = new URL(params.get("url") || "");
      const match = target.pathname.match(/^\/v\/([0-9A-Za-z]{10})\/?$/);
      if (/(^|\.)snapreel\.video$/.test(target.hostname) && match) slug = match[1];
    } catch {
      // fall through
    }
    if (!slug) throw new HttpError(404, "not_found", "That isn't a Snapreel video link.");
    const video = await videoBySlug(slug);
    if (!video || video.deleted_at || (video.expires_at && Date.parse(video.expires_at) <= Date.now())) {
      throw new HttpError(404, "not_found", "That link doesn't exist.");
    }
    if (video.access === "password") throw new HttpError(401, "password", "This video needs a password.");

    const ratio = video.width > 0 && video.height > 0 ? video.width / video.height : 16 / 9;
    const maxW = Number(params.get("maxwidth")) || 1280;
    const maxH = Number(params.get("maxheight")) || 1280;
    let width = Math.min(maxW, video.width || 1280, 1280);
    let height = Math.round(width / ratio);
    if (height > maxH) {
      height = maxH;
      width = Math.round(height * ratio);
    }
    const title = video.title || "Snapreel video";
    const src = `${SITE_URL}/v/${slug}?embed=1`;
    return json(
      {
        type: "video",
        version: "1.0",
        title,
        provider_name: "Snapreel",
        provider_url: SITE_URL,
        html: `<iframe src="${escapeHtml(src)}" width="${width}" height="${height}" title="${escapeHtml(title)}" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>`,
        width,
        height,
        thumbnail_url: `${SITE_URL}/api/public/v/${slug}/poster.jpg`,
        thumbnail_width: video.width || 1280,
        thumbnail_height: video.height || 720,
        duration: Math.round(Number(video.duration_s)),
      },
      200,
      { "Cache-Control": "public, max-age=300, s-maxage=300" },
    );
  });
}
