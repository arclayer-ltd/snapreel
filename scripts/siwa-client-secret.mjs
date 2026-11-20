#!/usr/bin/env node
// Makes the Sign in with Apple client secret (an ES256 JWT) that Supabase's Apple provider needs for web sign-in
// (Services ID co.arclayer.snapreel.web). Apple caps it at 6 months, so this is re-run every ~5 months; see
// docs/pro/BACKEND.md, "Apple client secret".
//
// Reads ~/.appstoreconnect/siwa/siwa.env (KEY_ID, TEAM_ID, KEY_PATH; written by the Apple-setup session) and the
// .p8 it points to. Prints ONLY the JWT on stdout, so pipe it straight to the clipboard and paste it into
// Supabase > Authentication > Sign In / Providers > Apple > "Secret Key (for OAuth)":
//   node scripts/siwa-client-secret.mjs | clip            (Windows)
//   node scripts/siwa-client-secret.mjs | pbcopy          (macOS)
// The expiry date goes to stderr. Options: --client <id> (default co.arclayer.snapreel.web), --days <n> (max 180).
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const dir = path.join(os.homedir(), ".appstoreconnect", "siwa");
const envText = fs.readFileSync(path.join(dir, "siwa.env"), "utf8");
const env = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .map((l) => l.match(/^\s*([A-Z_]+)\s*=\s*"?([^"]*)"?\s*$/))
    .filter(Boolean)
    .map((m) => [m[1], m[2]]),
);
const keyId = env.KEY_ID;
const teamId = env.TEAM_ID || "N3DBKUVJS5";
const keyPath = env.KEY_PATH ? path.resolve(dir, env.KEY_PATH.replace(/^~(?=$|[\\/])/, os.homedir())) : path.join(dir, `AuthKey_${keyId}.p8`);
if (!keyId) throw new Error("KEY_ID missing in siwa.env");

const clientId = opt("client", "co.arclayer.snapreel.web");
const days = Math.min(Number(opt("days", "180")), 180);
const now = Math.floor(Date.now() / 1000);
const exp = now + Math.floor(days * 86400) - 60;
const b64 = (v) => Buffer.from(JSON.stringify(v)).toString("base64url");
const head = `${b64({ alg: "ES256", kid: keyId })}.${b64({ iss: teamId, iat: now, exp, aud: "https://appleid.apple.com", sub: clientId })}`;
const key = crypto.createPrivateKey(fs.readFileSync(keyPath, "utf8"));
const sig = crypto.sign("sha256", Buffer.from(head), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");

process.stdout.write(`${head}.${sig}`);
process.stderr.write(`\nClient secret for ${clientId} (key ${keyId}, team ${teamId}) expires ${new Date(exp * 1000).toISOString().slice(0, 10)}.\n`);
