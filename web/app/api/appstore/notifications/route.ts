import { handleNotification } from "@/lib/server/appstore";
import { json, readJson, run } from "@/lib/server/http";

// POST /api/appstore/notifications: App Store Server Notifications V2 ({signedPayload}), production and sandbox.
// Answers 200 once the payload verifies (Apple retries anything else); 400 when the signature doesn't.
export async function POST(req: Request) {
  return run(async () => {
    const body = await readJson(req, 200_000);
    const result = await handleNotification(body.signedPayload);
    console.info("[appstore] notification", result.type, result.handled ? "applied" : "ignored");
    return json({ ok: true });
  });
}
