import { assertSameOrigin, badRequest, json, readJson, run } from "@/lib/server/http";
import { noCountCookieHeader } from "@/lib/server/tokens";

// POST /api/public/view-opt-out {optOut: boolean} -> {optOut}. The watch page's "Don't count my views" switch: sets
// (or clears) the sr_nocount cookie for a year, after which this browser's views aren't recorded on any Snapreel
// link. Nothing is stored on the server; the sr_vs cookie stays for blocks and rate limits.
export async function POST(req: Request) {
  return run(async () => {
    assertSameOrigin(req);
    const body = await readJson(req, 1_000);
    if (typeof body.optOut !== "boolean") throw badRequest("optOut must be true or false.");
    return json({ optOut: body.optOut }, 200, { "Set-Cookie": noCountCookieHeader(body.optOut) });
  });
}
