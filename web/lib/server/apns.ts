import "server-only";
import http2 from "node:http2";
import crypto from "node:crypto";

// Apple Push Notification service over HTTP/2 with a token-based (ES256) provider token. Moved here from
// server/push/api/live-activity.js; the Lock Screen relay (app/api/live-activity) and the alert pushes
// (./notify.ts) both use it. Environment: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 (the .p8 text).

export const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

export type ApnsEnvironment = keyof typeof APNS_HOSTS;

let cached: { token: string; at: number } | null = null; // APNs wants a provider token reused for 20 to 60 minutes.

const b64url = (value: string | Buffer) => Buffer.from(value).toString("base64url");

export function apnsConfigured(): boolean {
  return Boolean(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_KEY_P8);
}

export function providerToken(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 30 * 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: now }));
  // The .p8 may be stored with real newlines or with literal "\n" sequences.
  const key = crypto.createPrivateKey(process.env.APNS_KEY_P8!.replace(/\\n/g, "\n"));
  const signature = crypto.sign("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" });
  cached = { token: `${header}.${claims}.${b64url(signature)}`, at: now };
  return cached.token;
}

export interface ApnsHeaders {
  pushType: "alert" | "liveactivity" | "background";
  topic: string;
  priority?: "10" | "5";
  collapseId?: string;
}

export interface ApnsResult {
  status: number;
  apnsId: string;
  body: string;
}

export function sendToApns(
  deviceToken: string,
  payload: unknown,
  headers: ApnsHeaders,
  host: string = APNS_HOSTS.production,
): Promise<ApnsResult> {
  return new Promise((resolve, reject) => {
    const client = http2.connect(host);
    const fail = (error: unknown) => {
      client.close();
      reject(error);
    };
    client.on("error", fail);
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      "apns-push-type": headers.pushType,
      "apns-topic": headers.topic,
      "apns-priority": headers.priority ?? "10",
      ...(headers.collapseId ? { "apns-collapse-id": headers.collapseId } : {}),
      "content-type": "application/json",
    });
    let status = 0;
    let apnsId = "";
    let body = "";
    request.setEncoding("utf8");
    request.on("response", (h) => {
      status = Number(h[":status"]);
      apnsId = String(h["apns-id"] || "");
    });
    request.on("data", (chunk: string) => {
      body += chunk;
    });
    request.on("end", () => {
      client.close();
      resolve({ status, apnsId, body });
    });
    request.on("error", fail);
    request.setTimeout(8000, () => {
      request.close();
      fail(new Error("APNs timed out"));
    });
    request.end(JSON.stringify(payload));
  });
}

export function apnsReason(result: ApnsResult): string | undefined {
  try {
    return result.body ? (JSON.parse(result.body).reason as string | undefined) : undefined;
  } catch {
    return undefined;
  }
}
