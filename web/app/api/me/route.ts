import { requireUser } from "@/lib/server/auth";
import type { TablesUpdate } from "@/lib/server/database.types";
import { badRequest, is, json, limitError, readJson, run } from "@/lib/server/http";
import { getPlan } from "@/lib/server/plan";
import { getMe } from "@/lib/server/queries";
import { db } from "@/lib/server/supabase";

// GET /api/me: the account, plan and usage.
export async function GET(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    return json(await getMe(user.id, user.email));
  });
}

// PATCH /api/me {displayName?, brandColor?, emailAlerts?}. brandColor is Pro only.
export async function PATCH(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    const update: TablesUpdate<"profiles"> = {};
    if ("displayName" in body) {
      if (body.displayName !== null && typeof body.displayName !== "string") throw badRequest("displayName must be text.");
      const name = typeof body.displayName === "string" ? body.displayName.replace(/\s+/g, " ").trim().slice(0, 80) : "";
      update.display_name = name || null;
    }
    if ("brandColor" in body) {
      if (body.brandColor === null) update.brand_color = null;
      else {
        if (typeof body.brandColor !== "string" || !/^#[0-9A-Fa-f]{6}$/.test(body.brandColor)) {
          throw badRequest("brandColor must look like #F04850.");
        }
        if (!(await getPlan(user.id)).isPro) throw limitError("pro_feature", "Your own colour is part of Snapreel Pro.");
        update.brand_color = body.brandColor.toUpperCase();
      }
    }
    if ("emailAlerts" in body) {
      if (!is.bool(body.emailAlerts)) throw badRequest("emailAlerts must be true or false.");
      update.email_alerts = body.emailAlerts;
    }
    if (Object.keys(update).length) {
      const { error } = await db().from("profiles").upsert({ id: user.id, ...update }, { onConflict: "id" });
      if (error) throw error;
    }
    return json(await getMe(user.id, user.email));
  });
}
