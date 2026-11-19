// Snapreel's Live Activity relay. The broadcast extension can't end the app's Live Activity
// (ActivityKit only lists the calling app's own activities, and the app is usually suspended
// while the screen records), so when a screen recording stops it posts here and this sends
// Apple's ActivityKit push to end the Lock Screen card.
//
// POST /api/live-activity
//   { "token": "<hex push token from Activity.pushTokenUpdates>",
//     "event": "end" | "update",
//     "contentState": { ...RecordingActivityStatus, JSON-encoded by Swift's JSONEncoder... },
//     "staleDate"?: <unix seconds>, "dismissalDate"?: <unix seconds, end only> }
// -> 200 { apns: 200, apnsId } on success; 400 for a bad request; 502 when APNs refuses.
//
// Environment: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 (the .p8 text). Production APNs only
// (TestFlight and App Store builds). Holds no data: nothing is stored or logged but the result.
import http2 from "node:http2";
import crypto from "node:crypto";

const HOST = "https://api.push.apple.com";
const TOPIC = "co.arclayer.snapreel.push-type.liveactivity";
let cached = null; // { token, at }: APNs wants a provider token reused for 20 to 60 minutes.

const b64url = (value) => Buffer.from(value).toString("base64url");

function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 30 * 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: now }));
  const key = crypto.createPrivateKey(process.env.APNS_KEY_P8.replace(/\n/g, "\n"));
  const signature = crypto.sign("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" });
  cached = { token: `${header}.${claims}.${b64url(signature)}`, at: now };
  return cached.token;
}

function sendToApns(deviceToken, payload) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(HOST);
    const fail = (error) => { client.close(); reject(error); };
    client.on("error", fail);
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      "apns-push-type": "liveactivity",
      "apns-topic": TOPIC,
      "apns-priority": "10",
      "content-type": "application/json",
    });
    let status = 0;
    let apnsId = "";
    let body = "";
    request.setEncoding("utf8");
    request.on("response", (headers) => { status = headers[":status"]; apnsId = headers["apns-id"] || ""; });
    request.on("data", (chunk) => { body += chunk; });
    request.on("end", () => { client.close(); resolve({ status, apnsId, body }); });
    request.on("error", fail);
    request.setTimeout(8000, () => { request.close(); fail(new Error("APNs timed out")); });
    request.end(JSON.stringify(payload));
  });
}

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  if (!process.env.APNS_KEY_ID || !process.env.APNS_TEAM_ID || !process.env.APNS_KEY_P8) {
    return res.status(500).json({ error: "APNs is not configured" });
  }
  const { token, event, contentState, staleDate, dismissalDate } = req.body || {};
  if (typeof token !== "string" || !/^[0-9a-f]{32,400}$/i.test(token)) {
    return res.status(400).json({ error: "token must be the hex push token" });
  }
  if (event !== "end" && event !== "update") return res.status(400).json({ error: "event must be end or update" });
  if (!contentState || typeof contentState !== "object" || Array.isArray(contentState)
      || JSON.stringify(contentState).length > 2000) {
    return res.status(400).json({ error: "contentState must be a small JSON object" });
  }
  const aps = { timestamp: Math.floor(Date.now() / 1000), event, "content-state": contentState };
  if (Number.isFinite(staleDate)) aps["stale-date"] = Math.floor(staleDate);
  if (event === "end" && Number.isFinite(dismissalDate)) aps["dismissal-date"] = Math.floor(dismissalDate);
  try {
    const result = await sendToApns(token.toLowerCase(), { aps });
    let reason;
    try { reason = result.body ? JSON.parse(result.body).reason : undefined; } catch { reason = undefined; }
    return res.status(result.status === 200 ? 200 : 502).json({ apns: result.status, apnsId: result.apnsId, reason });
  } catch (error) {
    return res.status(502).json({ error: String(error?.message || error) });
  }
}
