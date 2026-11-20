import crypto from "node:crypto";
import { env } from "@/lib/server/env";
import { json, run, HttpError } from "@/lib/server/http";
import { removePrefix, videoPaths } from "@/lib/server/storage";
import { db } from "@/lib/server/supabase";

export const maxDuration = 60;

const DAY = 24 * 3600 * 1000;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

// GET /api/cron/daily: Vercel Cron (web/vercel.json, 04:17 UTC) with `Authorization: Bearer $CRON_SECRET`.
//  - uploads stuck in "uploading" for 48 hours become "failed" (the watch page says so);
//  - failed uploads after 7 days, and links 30 days past their expiry, lose their files and become tombstones;
//  - tombstones (stopped links) are purged 30 days after they stopped, so the slug then reads "not found";
//  - subscriptions a day past expiry with no word from Apple are marked expired;
//  - rate-limit windows older than a day and alert dedupe rows older than 90 days are cleared.
export async function GET(req: Request) {
  return run(async () => {
    const secret = env.cronSecret;
    const given = req.headers.get("authorization") || "";
    const expected = `Bearer ${secret}`;
    if (!secret || given.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(expected))) {
      throw new HttpError(401, "unauthorized", "Cron only.");
    }
    const supabase = db();
    const report: Record<string, number> = {};

    const stale = await supabase
      .from("videos")
      .update({ status: "failed" })
      .eq("status", "uploading")
      .is("deleted_at", null)
      .lt("updated_at", ago(2 * DAY))
      .select("id");
    if (stale.error) throw stale.error;
    report.staleUploadsFailed = stale.data.length;

    const toTombstone = new Map<string, string>(); // id -> owner
    const failed = await supabase
      .from("videos")
      .select("id, owner_id")
      .eq("status", "failed")
      .is("deleted_at", null)
      .lt("updated_at", ago(7 * DAY))
      .limit(500);
    if (failed.error) throw failed.error;
    for (const v of failed.data) toTombstone.set(v.id, v.owner_id);
    const expired = await supabase
      .from("videos")
      .select("id, owner_id")
      .is("deleted_at", null)
      .lt("expires_at", ago(30 * DAY))
      .limit(500);
    if (expired.error) throw expired.error;
    for (const v of expired.data) toTombstone.set(v.id, v.owner_id);
    let files = 0;
    for (const [id, owner] of toTombstone) {
      files += await removePrefix(videoPaths(owner, id).base);
      await supabase.from("views").delete().eq("video_id", id);
      await supabase.from("comments").delete().eq("video_id", id);
      await supabase.from("reactions").delete().eq("video_id", id);
      const { error } = await supabase
        .from("videos")
        .update({ deleted_at: new Date().toISOString(), title: "", transcript: null, cta: null, password_hash: null })
        .eq("id", id);
      if (error) throw error;
    }
    report.linksRetired = toTombstone.size;
    report.filesRemoved = files;

    const purged = await supabase.from("videos").delete().lt("deleted_at", ago(30 * DAY)).select("id");
    if (purged.error) throw purged.error;
    report.tombstonesPurged = purged.data.length;

    const lapsed = await supabase
      .from("subscriptions")
      .update({ status: "expired" })
      .in("status", ["active", "in_grace"])
      .lt("expires_at", ago(DAY))
      .select("user_id");
    if (lapsed.error) throw lapsed.error;
    report.subscriptionsExpired = lapsed.data.length;

    const logs = await supabase.from("notification_log").delete().lt("created_at", ago(90 * DAY)).select("id");
    if (logs.error) throw logs.error;
    report.alertLogsCleared = logs.data.length;

    const windows = await supabase.rpc("prune_rate_limits", { p_before: ago(DAY) });
    if (windows.error) console.warn("[cron] rate_limits", windows.error.message);
    report.rateLimitWindowsCleared = windows.data ?? 0;

    console.info("[cron] daily", JSON.stringify(report));
    return json({ ok: true, ...report });
  });
}
