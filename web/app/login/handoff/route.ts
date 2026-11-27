// The app's "Open the web dashboard" lands here with ?t= from POST /api/auth/handoff. Verifying the sealed magic-link
// token sets the cookie session (once: Supabase uses the token up), then this goes on to the dashboard.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer } from "@/app/app/_lib/session";
import { safeNext } from "@/lib/client/links";
import { PREVIEW } from "@/lib/client/preview-data";
import { openHandoff } from "@/lib/server/handoff";

const NO_STORE = { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" };

export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const next = safeNext(url.searchParams.get("next"));
  const go = (path: string) => NextResponse.redirect(new URL(path, url.origin), { headers: NO_STORE });
  const expired = () => go(`/login?error=handoff&next=${encodeURIComponent(next)}`);

  if (PREVIEW) return go(next);
  const handoff = openHandoff(url.searchParams.get("t"));
  if (!handoff) return expired();

  const supabase = await supabaseServer();
  const { data, error } = await supabase.auth.verifyOtp({ type: "magiclink", token_hash: handoff.hashedToken });
  if (error || !data.user) return expired();
  if (data.user.id !== handoff.userId) {
    await supabase.auth.signOut({ scope: "local" });
    return expired();
  }
  return go(next);
}
