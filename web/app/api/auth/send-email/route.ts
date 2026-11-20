import crypto from "node:crypto";
import { codeEmail, sendEmail } from "@/lib/server/email";
import { env } from "@/lib/server/env";

// Supabase Auth "Send Email" hook (HTTPS). Supabase calls this for every auth email (sign-in and sign-up codes,
// email change, reauthentication) instead of using its own templates; we send a branded 6-digit code email
// through Resend. Signed with Standard Webhooks: webhook-id, webhook-timestamp and webhook-signature
// ("v1,<base64 HMAC-SHA256 of id.timestamp.body>") using SUPABASE_AUTH_HOOK_SECRET ("v1,whsec_<base64>").

interface HookPayload {
  user?: { id?: string; email?: string; new_email?: string };
  email_data?: {
    token?: string;
    token_new?: string;
    email_action_type?: string;
  };
}

function hookError(status: number, message: string): Response {
  return Response.json({ error: { http_code: status, message } }, { status });
}

function verify(req: Request, body: string): boolean {
  const secret = env.authHookSecret.replace(/^v1,whsec_/, "").replace(/^whsec_/, "");
  if (!secret) return false;
  const id = req.headers.get("webhook-id");
  const timestamp = req.headers.get("webhook-timestamp");
  const signatures = req.headers.get("webhook-signature");
  if (!id || !timestamp || !signatures) return false;
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 5 * 60) return false;
  const expected = crypto
    .createHmac("sha256", Buffer.from(secret, "base64"))
    .update(`${id}.${timestamp}.${body}`)
    .digest();
  return signatures.split(" ").some((entry) => {
    const [version, sig] = entry.split(",");
    if (version !== "v1" || !sig) return false;
    const given = Buffer.from(sig, "base64");
    return given.length === expected.length && crypto.timingSafeEqual(given, expected);
  });
}

export async function POST(req: Request): Promise<Response> {
  const body = await req.text();
  if (!verify(req, body)) return hookError(401, "Invalid signature");
  let payload: HookPayload;
  try {
    payload = JSON.parse(body);
  } catch {
    return hookError(400, "Invalid JSON");
  }
  const user = payload.user ?? {};
  const data = payload.email_data ?? {};
  const action = data.email_action_type ?? "magiclink";

  const sends: { to: string; code: string; kind: "sign_in" | "email_change" | "reauthentication" }[] = [];
  if (action === "email_change") {
    if (data.token && user.email) sends.push({ to: user.email, code: data.token, kind: "email_change" });
    if (data.token_new && user.new_email) sends.push({ to: user.new_email, code: data.token_new, kind: "email_change" });
  } else if (data.token && user.email) {
    sends.push({ to: user.email, code: data.token, kind: action === "reauthentication" ? "reauthentication" : "sign_in" });
  }
  if (!sends.length) return hookError(400, `Nothing to send for ${action}`);

  for (const s of sends) {
    const result = await sendEmail({
      to: s.to,
      ...codeEmail(s.code, s.kind),
      tags: [{ name: "kind", value: `auth_${action}` }],
    });
    if (!result.ok) return hookError(500, "Couldn't send the email. Try again in a moment.");
  }
  return Response.json({});
}
