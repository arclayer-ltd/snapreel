// GET /api/health: whether the relay has its APNs settings (never shows them). Ported unchanged from
// server/push/api/health.js.
import { connection } from "next/server";
import { apnsConfigured } from "@/lib/server/apns";

export async function GET(): Promise<Response> {
  await connection(); // answer per request, never from a build-time prerender
  return new Response(JSON.stringify({ ok: true, configured: apnsConfigured() }), {
    status: 200,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
