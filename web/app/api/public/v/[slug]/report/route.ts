import { after } from "next/server";
import { reportEmail, sendEmail } from "@/lib/server/email";
import { SUPPORT_EMAIL } from "@/lib/server/env";
import { badRequest, noContent, readJson, run } from "@/lib/server/http";
import { publicError } from "@/lib/server/public";
import { videoBySlug } from "@/lib/server/queries";
import { rateLimit } from "@/lib/server/ratelimit";
import { db } from "@/lib/server/supabase";

const REASONS = new Set(["spam", "abuse", "illegal", "copyright", "other"]);

// POST /api/public/v/{slug}/report {reason, details, email?} -> 204. Goes to the abuse queue (public.reports)
// and to support@snapreel.video. Works for password-protected links too (a viewer may report what they were sent).
export async function POST(req: Request, ctx: RouteContext<"/api/public/v/[slug]/report">) {
  return run(async () => {
    const { slug } = await ctx.params;
    const video = await videoBySlug(slug);
    if (!video) throw publicError("not_found");
    if (video.deleted_at) throw publicError("removed");
    await rateLimit(req, "report", null);
    const body = await readJson(req, 8_000);
    const reason = typeof body.reason === "string" && REASONS.has(body.reason) ? body.reason : null;
    if (!reason) throw badRequest("reason must be spam, abuse, illegal, copyright or other.");
    const details = typeof body.details === "string" ? body.details.trim().slice(0, 2000) : "";
    const email = typeof body.email === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email.trim()) ? body.email.trim().slice(0, 320) : null;

    const { error } = await db()
      .from("reports")
      .insert({ video_id: video.id, reason: reason as "spam", details, email });
    if (error) throw error;
    after(() =>
      sendEmail({
        to: SUPPORT_EMAIL,
        ...reportEmail({ slug, videoId: video.id, ownerId: video.owner_id, reason, details, reporterEmail: email }),
        replyTo: email ?? undefined,
        tags: [{ name: "kind", value: "report" }],
      }).catch((e) => console.error("[report] email", e)),
    );
    return noContent();
  });
}
