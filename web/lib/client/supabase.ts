"use client";

// The browser's Supabase client: cookie sessions through @supabase/ssr, so the server sees the same session.
import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PREVIEW, PREVIEW_COOKIE } from "@/lib/client/preview-data";

let client: SupabaseClient | null = null;

/** Null in preview mode (no Supabase env). */
export function supabaseBrowser(): SupabaseClient | null {
  if (PREVIEW) return null;
  client ??= createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  );
  return client;
}

/** The current access token for owner API calls, refreshed if needed. */
export async function accessToken(): Promise<string | null> {
  const sb = supabaseBrowser();
  if (!sb) return null;
  const { data } = await sb.auth.getSession();
  return data.session?.access_token ?? null;
}

/** Signs out everywhere this browser is signed in. */
export async function signOut(): Promise<void> {
  const sb = supabaseBrowser();
  if (sb) {
    await sb.auth.signOut();
    return;
  }
  document.cookie = `${PREVIEW_COOKIE}=; Path=/; Max-Age=0; SameSite=Lax`;
}

/** Preview mode: "signs in" by setting a cookie the server reads. */
export function previewSignIn(tier: "free" | "pro"): void {
  document.cookie = `${PREVIEW_COOKIE}=${tier}; Path=/; Max-Age=${60 * 60 * 24 * 7}; SameSite=Lax`;
}
