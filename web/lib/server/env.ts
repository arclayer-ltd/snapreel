import "server-only";

// Server configuration. Values live in Vercel env (docs/pro/BACKEND.md lists every name); none are in git.

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

export const SITE_URL = (process.env.SITE_URL || "https://snapreel.video").replace(/\/+$/, "");
export const TEAM_ID = "N3DBKUVJS5";
export const SUPPORT_EMAIL = "support@snapreel.video";
export const EMAIL_FROM = "Snapreel <hello@snapreel.video>";

export const env = {
  get supabaseUrl() {
    return required("NEXT_PUBLIC_SUPABASE_URL");
  },
  get publishableKey() {
    return required("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  },
  get secretKey() {
    return required("SUPABASE_SECRET_KEY");
  },
  get viewerCookieSecret() {
    return required("VIEWER_COOKIE_SECRET");
  },
  get bundleId() {
    return process.env.APPLE_BUNDLE_ID || "co.arclayer.snapreel";
  },
  get appAppleId() {
    return Number(process.env.APPLE_APP_ID || "6836019517");
  },
  get resendApiKey() {
    return process.env.RESEND_API_KEY || "";
  },
  get authHookSecret() {
    return process.env.SUPABASE_AUTH_HOOK_SECRET || "";
  },
  get cronSecret() {
    return process.env.CRON_SECRET || "";
  },
};
