import { HttpError, run } from "@/lib/server/http";
import { publicContext } from "@/lib/server/public";
import { asTranscript } from "@/lib/server/shape";
import { transcriptToVtt } from "@/lib/server/vtt";

// GET /api/public/v/{slug}/captions.vtt: WebVTT made from the phone's on-device transcript.
export async function GET(req: Request, ctx: RouteContext<"/api/public/v/[slug]/captions.vtt">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const { video } = await publicContext(req, slug);
    const transcript = asTranscript(video.transcript);
    if (!transcript?.segments.length) throw new HttpError(404, "no_captions", "This video has no captions.");
    return new Response(transcriptToVtt(transcript), {
      headers: {
        "content-type": "text/vtt; charset=utf-8",
        // Browser-only caching: the link's access can change at any time, so no shared cache keeps a copy.
        "cache-control": "private, max-age=300",
      },
    });
  });
}
