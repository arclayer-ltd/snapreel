import { requireUser } from "@/lib/server/auth";
import { SITE_URL } from "@/lib/server/env";
import { HANDOFF_TTL_S, sealHandoff } from "@/lib/server/handoff";
import { HttpError, json, run } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";

// POST /api/auth/handoff (Bearer token, the app only): a link that opens the web dashboard signed in as this
// account. Single use, valid for HANDOFF_TTL_S seconds. See lib/server/handoff.ts.
export async function POST(req: Request) {
  return run(async () => {
    if (!/^bearer\s+/i.test(req.headers.get("authorization") ?? "")) {
      throw new HttpError(401, "unauthorized", "Sign in in the app first.");
    }
    const user = await requireUser(req);
    if (!user.email) throw new HttpError(409, "no_email", "This account has no email address to sign in with on the web.");

    // Makes a magic-link token without sending any email.
    const { data, error } = await db().auth.admin.generateLink({ type: "magiclink", email: user.email });
    const hashed = data?.properties?.hashed_token;
    if (error || !hashed || data.user?.id !== user.id) {
      console.error("[handoff] generateLink failed", error?.message ?? "no token");
      throw new HttpError(502, "handoff_failed", "The sign-in link couldn't be made. Sign in on the website instead.");
    }

    // Production links always point at snapreel.video; previews at the preview that was asked.
    const origin = process.env.VERCEL_ENV === "production" ? SITE_URL : new URL(req.url).origin;
    const url = new URL("/login/handoff", origin);
    url.searchParams.set("t", sealHandoff(hashed, user.id));
    return json({ url: url.toString(), expiresInS: HANDOFF_TTL_S });
  });
}
