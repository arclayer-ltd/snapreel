import { requireUser } from "@/lib/server/auth";
import { badRequest, noContent, readJson, run } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";

// POST /api/devices {token, environment, appVersion}: registers this phone for alert pushes. A token that moves
// to another account (sign-out, sign-in as someone else) follows the new account.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    const token = typeof body.token === "string" ? body.token.toLowerCase() : "";
    if (!/^[0-9a-f]{32,400}$/.test(token)) throw badRequest("token must be the hex APNs device token.");
    const environment = body.environment === "sandbox" ? "sandbox" : body.environment === "production" ? "production" : null;
    if (!environment) throw badRequest("environment must be production or sandbox.");
    const appVersion = typeof body.appVersion === "string" ? body.appVersion.slice(0, 40) : null;
    const { error } = await db()
      .from("devices")
      .upsert(
        { token, user_id: user.id, environment, app_version: appVersion, last_seen_at: new Date().toISOString() },
        { onConflict: "token" },
      );
    if (error) throw error;
    return noContent();
  });
}
