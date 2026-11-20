// Sign in with Apple on the web returns here with ?code= (PKCE). Exchanging it sets the session cookies.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer } from "@/app/app/_lib/session";
import { safeNext } from "@/lib/client/links";
import { PREVIEW } from "@/lib/client/preview-data";

export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const next = safeNext(url.searchParams.get("next"));
  const code = url.searchParams.get("code");
  const back = (error: string) =>
    NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(error)}&next=${encodeURIComponent(next)}`, url.origin));

  if (PREVIEW) return NextResponse.redirect(new URL(next, url.origin));
  if (!code) return back(url.searchParams.get("error") ?? "apple");

  const supabase = await supabaseServer();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) return back("apple");
  return NextResponse.redirect(new URL(next, url.origin));
}
