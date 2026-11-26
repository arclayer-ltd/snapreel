// Uploads a file the way the app does: S3 multipart through Supabase Storage, presigned with a person's session token
// (docs/pro/BACKEND.md, "Uploads"). Used by pro-smoke.sh, and by hand to measure.
//
//   SB=https://<ref>.supabase.co ANON=<anon key> TOKEN_FILE=<file with an access token> \
//     node scripts/s3-upload.mjs <file> <object name> [parts at once] [checks]
//
// "checks" also tries what goes wrong on a phone: a piece sent twice, a lost completion, a missing piece, an unknown
// upload, a signature from 40 minutes ago, another person's folder (OTHER_TOKEN_FILE). Prints one line per check and
// exits 1 when one fails. Tokens are read from files and never printed.
import crypto from "node:crypto";
import fs from "node:fs";

const [file, key, atOnce = "3", mode = ""] = process.argv.slice(2);
const { SB, ANON, TOKEN_FILE, OTHER_TOKEN_FILE } = process.env;
if (!file || !key || !SB || !ANON || !TOKEN_FILE) {
  console.error("usage: SB=… ANON=… TOKEN_FILE=… node scripts/s3-upload.mjs <file> <object> [parts at once] [checks]");
  process.exit(2);
}
const token = fs.readFileSync(TOKEN_FILE, "utf8").trim();
const ref = new URL(SB).host.split(".")[0];
const host = `${ref}.storage.supabase.co`;
const PIECE = 5 * 1024 * 1024;

const hmac = (k, s) => crypto.createHmac("sha256", k).update(s).digest();
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
const md5 = (b) => crypto.createHash("md5").update(b).digest("hex");
const enc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());

// AWS Signature Version 4 in the query string, as Snapreel/Services/Cloud/S3Signer.swift does it.
function presign(method, query, { date = new Date(), expires = 86400, as = token } = {}) {
  const path = "/storage/v1/s3/videos/" + key.split("/").map(enc).join("/");
  const stamp = date.toISOString().replace(/[-:]|\.\d{3}/g, "");
  const day = stamp.slice(0, 8);
  const scope = `${day}/us-east-1/s3/aws4_request`;
  const q = {
    ...query,
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${ref}/${scope}`,
    "X-Amz-Date": stamp,
    "X-Amz-Expires": String(expires),
    "X-Amz-Security-Token": as,
    "X-Amz-SignedHeaders": "host",
  };
  const qs = Object.keys(q).sort().map((k) => `${enc(k)}=${enc(q[k])}`).join("&");
  const canonical = [method, path, qs, `host:${host}\n`, "host", "UNSIGNED-PAYLOAD"].join("\n");
  const toSign = ["AWS4-HMAC-SHA256", stamp, scope, sha(canonical)].join("\n");
  const k = hmac(hmac(hmac(hmac("AWS4" + ANON, day), "us-east-1"), "s3"), "aws4_request");
  return `https://${host}${path}?${qs}&X-Amz-Signature=${crypto.createHmac("sha256", k).update(toSign).digest("hex")}`;
}

async function call(method, query, body, options) {
  // Storage reads the list of pieces only as XML, and the new file's type comes from the call that starts it.
  const headers = method === "POST" ? { "content-type": body ? "application/xml" : "video/mp4" } : {};
  const r = await fetch(presign(method, query, options), { method, body, headers });
  return { status: r.status, etag: (r.headers.get("etag") || "").replaceAll('"', ""), text: await r.text() };
}
const create = async (options) => {
  const r = await call("POST", { uploads: "" }, undefined, options);
  return { ...r, id: /<UploadId>(.*?)<\/UploadId>/.exec(r.text)?.[1] };
};
const list = (pieces) => `<CompleteMultipartUpload>${pieces.map((p) => `<Part><PartNumber>${p.n}</PartNumber><ETag>"${p.md5}"</ETag></Part>`).join("")}</CompleteMultipartUpload>`;

let failed = 0;
const check = (ok, what, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${what}${ok ? "" : `: ${detail}`}`);
  if (!ok) failed += 1;
};

const size = fs.statSync(file).size;
const fd = fs.openSync(file, "r");
const pieces = Array.from({ length: Math.ceil(size / PIECE) }, (_, i) => ({ n: i + 1, start: i * PIECE, size: Math.min(PIECE, size - i * PIECE) }));
const read = (p) => {
  const b = Buffer.alloc(p.size);
  fs.readSync(fd, b, 0, p.size, p.start);
  return b;
};

const upload = await create();
if (!upload.id) {
  console.log(`FAIL  create multipart upload: ${upload.status} ${upload.text.slice(0, 200)}`);
  process.exit(1);
}
const began = Date.now();
// Last piece first: the app sends the one with the index last, so order must not matter.
const todo = [...pieces].reverse();
let retries = 0;
await Promise.all(
  Array.from({ length: Number(atOnce) }, async () => {
    for (let p; (p = todo.shift()); ) {
      const bytes = read(p);
      p.md5 = md5(bytes);
      for (let attempt = 0; ; attempt++) {
        try {
          const r = await call("PUT", { partNumber: String(p.n), uploadId: upload.id }, bytes);
          if (r.status === 200 && r.etag === p.md5) break;
          throw new Error(`${r.status} ${r.text.slice(0, 200)}`);
        } catch (error) {
          retries += 1;
          if (attempt >= 8) throw error;
        }
      }
    }
  }),
);
if (mode === "checks") {
  const first = read(pieces[0]);
  let r = await call("PUT", { partNumber: "1", uploadId: upload.id }, first);
  check(r.status === 200 && r.etag === pieces[0].md5, "a piece sent twice is harmless", `${r.status}`);
  r = await call("PUT", { partNumber: "1", uploadId: upload.id }, first, { date: new Date(Date.now() - 40 * 60e3) });
  check(r.status === 200, "a piece signed 40 minutes ago is accepted", `${r.status} ${r.text.slice(0, 160)}`);
  r = await call("PUT", { partNumber: "1", uploadId: "unknown" }, first);
  check(r.status === 404 && r.text.includes("NoSuchUpload"), "an unknown upload is 404 NoSuchUpload", `${r.status}`);
  r = await call("POST", { uploadId: upload.id }, list([{ n: 1, md5: md5("x") }]));
  check(r.status === 400 && r.text.includes("InvalidPart"), "completing with a wrong piece is InvalidPart", `${r.status} ${r.text.slice(0, 160)}`);
  if (OTHER_TOKEN_FILE) {
    const as = fs.readFileSync(OTHER_TOKEN_FILE, "utf8").trim();
    r = await create({ as });
    check(r.status === 403, "another person can't start an upload in this folder", `${r.status}`);
    r = await call("PUT", { partNumber: "1", uploadId: upload.id }, first, { as });
    check(r.status === 403, "another person can't send a piece to this upload", `${r.status}`);
  }
}
let done = await call("POST", { uploadId: upload.id }, list(pieces));
if (done.status !== 200 || done.text.includes("<Error>")) {
  console.log(`FAIL  complete: ${done.status} ${done.text.slice(0, 300)}`);
  process.exit(1);
}
const seconds = (Date.now() - began) / 1000;
if (mode === "checks") {
  done = await call("POST", { uploadId: upload.id }, list(pieces));
  check(done.status === 404, "completing again says the upload is gone (a lost answer)", `${done.status}`);
}
console.log(`S3 multipart: ${pieces.length} pieces, ${(size / 1048576).toFixed(1)} MB in ${seconds.toFixed(1)} s (${(size / 1048576 / seconds).toFixed(2)} MB/s), ${retries} retries`);
process.exit(failed ? 1 : 0);
