import { connection } from "next/server";
import { is } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";
import { checkUnsubscribeSig } from "@/lib/server/tokens";

// Email alert unsubscribe. Every alert carries List-Unsubscribe (with One-Click POST, RFC 8058) and a footer link
// to GET this with ?u={userId}&s={signature}. Either one turns profiles.email_alerts off. Push alerts stay on.

async function unsubscribe(req: Request): Promise<boolean> {
  const params = new URL(req.url).searchParams;
  const userId = params.get("u") || "";
  const sig = params.get("s") || "";
  if (!is.uuid(userId) || !sig || !checkUnsubscribeSig(userId, sig)) return false;
  const { error } = await db().from("profiles").update({ email_alerts: false }).eq("id", userId);
  return !error;
}

function page(ok: boolean): Response {
  const text = ok
    ? "You won't get Snapreel email alerts any more. You can turn them back on in the app under Settings, Account."
    : "That unsubscribe link isn't valid. Turn email alerts off in the app under Settings, Account.";
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Snapreel email alerts</title></head><body style="margin:0;font:17px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#F4F4F6;color:#13141B"><main style="max-width:520px;margin:15vh auto;padding:0 20px"><h1 style="font-size:28px;margin:0 0 12px">${ok ? "Email alerts are off" : "Link not valid"}</h1><p style="margin:0;color:#3D404C">${text}</p></main></body></html>`;
  return new Response(html, {
    status: ok ? 200 : 400,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  });
}

export async function GET(req: Request) {
  await connection();
  return page(await unsubscribe(req));
}

export async function POST(req: Request) {
  const ok = await unsubscribe(req);
  return new Response(null, { status: ok ? 200 : 400 });
}
