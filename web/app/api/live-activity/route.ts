// Snapreel's Live Activity relay, ported unchanged from server/push/api/live-activity.js (builds 31 and later
// call this exact address). The broadcast extension can't end the app's Live Activity (ActivityKit only lists the
// calling app's own activities, and the app is usually suspended while the screen records), so when a screen
// recording stops it posts here and this sends Apple's ActivityKit push to end the Lock Screen card.
//
// POST /api/live-activity
//   { "token": "<hex push token from Activity.pushTokenUpdates>",
//     "event": "end" | "update",
//     "contentState": { ...RecordingActivityStatus, JSON-encoded by Swift's JSONEncoder... },
//     "staleDate"?: <unix seconds>, "dismissalDate"?: <unix seconds, end only> }
// -> 200 { apns: 200, apnsId } on success; 400 for a bad request; 502 when APNs refuses.
//
// Production APNs only (TestFlight and App Store builds). Holds no data: nothing is stored or logged but the result.
import { apnsConfigured, apnsReason, sendToApns } from "@/lib/server/apns";

export const maxDuration = 10;

const TOPIC = "co.arclayer.snapreel.push-type.liveactivity";

// Same bytes and content type as the old Vercel function's res.status(n).json(body).
function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (!(req.headers.get("content-type") || "").includes("json")) return {};
  try {
    const value = JSON.parse(await req.text());
    return value && typeof value === "object" ? value : {};
  } catch {
    return {};
  }
}

export async function POST(req: Request): Promise<Response> {
  if (!apnsConfigured()) return reply(500, { error: "APNs is not configured" });
  const { token, event, contentState, staleDate, dismissalDate } = await readBody(req);
  if (typeof token !== "string" || !/^[0-9a-f]{32,400}$/i.test(token)) {
    return reply(400, { error: "token must be the hex push token" });
  }
  if (event !== "end" && event !== "update") return reply(400, { error: "event must be end or update" });
  if (
    !contentState ||
    typeof contentState !== "object" ||
    Array.isArray(contentState) ||
    JSON.stringify(contentState).length > 2000
  ) {
    return reply(400, { error: "contentState must be a small JSON object" });
  }
  const aps: Record<string, unknown> = { timestamp: Math.floor(Date.now() / 1000), event, "content-state": contentState };
  if (Number.isFinite(staleDate)) aps["stale-date"] = Math.floor(staleDate as number);
  if (event === "end" && Number.isFinite(dismissalDate)) aps["dismissal-date"] = Math.floor(dismissalDate as number);
  try {
    const result = await sendToApns(token.toLowerCase(), { aps }, { pushType: "liveactivity", topic: TOPIC });
    return reply(result.status === 200 ? 200 : 502, {
      apns: result.status,
      apnsId: result.apnsId,
      reason: apnsReason(result),
    });
  } catch (error) {
    return reply(502, { error: String((error as Error)?.message || error) });
  }
}

const postOnly = async () => reply(405, { error: "POST only" });
export { postOnly as GET, postOnly as PUT, postOnly as PATCH, postOnly as DELETE, postOnly as OPTIONS };
