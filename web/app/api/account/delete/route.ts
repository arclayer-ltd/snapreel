import { requireUser } from "@/lib/server/auth";
import { noContent, readJson, run } from "@/lib/server/http";
import { revokeWithAuthorizationCode } from "@/lib/server/siwa";
import { removePrefix } from "@/lib/server/storage";
import { db } from "@/lib/server/supabase";

export const maxDuration = 60;

// POST /api/account/delete [{appleAuthorizationCode?, appleClientId?}] -> 204. Deletes every file and row,
// revokes Sign in with Apple when the app sends a fresh authorization code (and SIWA_* is configured), then
// deletes the auth user. The App Store subscription itself is cancelled by the user in Settings; the app says so.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    const supabase = db();

    await removePrefix(user.id);

    const { data: authUser } = await supabase.auth.admin.getUserById(user.id);
    const usedApple = (authUser?.user?.identities ?? []).some((i) => i.provider === "apple");
    if (usedApple && typeof body.appleAuthorizationCode === "string") {
      const clientId = typeof body.appleClientId === "string" ? body.appleClientId : undefined;
      const revoked = await revokeWithAuthorizationCode(body.appleAuthorizationCode, clientId);
      console.info("[account] apple revoke", revoked ? "ok" : "not done");
    }

    // Videos cascade to their views, comments, reactions, reports and alerts. Then the rest of the user's rows.
    const steps = [
      supabase.from("videos").delete().eq("owner_id", user.id),
      supabase.from("devices").delete().eq("user_id", user.id),
      supabase.from("subscriptions").delete().eq("user_id", user.id),
      supabase.from("blocks").delete().eq("owner_id", user.id),
      supabase.from("notification_log").delete().eq("user_id", user.id),
      supabase.from("profiles").delete().eq("id", user.id),
    ];
    for (const step of steps) {
      const { error } = await step;
      if (error) throw error;
    }
    const { error } = await supabase.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return noContent();
  });
}
