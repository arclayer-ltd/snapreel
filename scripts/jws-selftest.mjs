#!/usr/bin/env node
// Self-test for web/lib/server/jws.ts (StoreKit 2 / App Store Server Notifications JWS verification).
// Builds a throwaway root -> intermediate -> leaf chain with OpenSSL (with Apple's marker OIDs), signs JWS with
// the leaf key, and checks the verifier accepts good ones and rejects tampering, a foreign root, missing OIDs and
// the real Apple root being swapped out. Needs Node 23+ (runs the .ts file directly) and openssl on PATH.
//   node scripts/jws-selftest.mjs
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const jws = await import(pathToFileURL(path.join(here, "../web/lib/server/jws.ts")).href);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "jws-selftest-"));
const ssl = (...args) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
const write = (name, text) => fs.writeFileSync(path.join(dir, name), text);

function chain(prefix, { oids = true } = {}) {
  ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}root.key`);
  ssl("req", "-x509", "-new", "-key", `${prefix}root.key`, "-subj", `/CN=${prefix}Test Root`, "-days", "3650", "-sha384",
    "-addext", "basicConstraints=critical,CA:true", "-addext", "keyUsage=critical,keyCertSign,cRLSign", "-out", `${prefix}root.pem`);
  write(`${prefix}inter.ext`, `basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n${oids ? "1.2.840.113635.100.6.2.1=ASN1:NULL\n" : ""}`);
  ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}inter.key`);
  ssl("req", "-new", "-key", `${prefix}inter.key`, "-subj", `/CN=${prefix}Test Intermediate`, "-out", `${prefix}inter.csr`);
  ssl("x509", "-req", "-in", `${prefix}inter.csr`, "-CA", `${prefix}root.pem`, "-CAkey", `${prefix}root.key`, "-CAcreateserial",
    "-days", "3650", "-sha384", "-extfile", `${prefix}inter.ext`, "-out", `${prefix}inter.pem`);
  write(`${prefix}leaf.ext`, `basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\n${oids ? "1.2.840.113635.100.6.11.1=ASN1:NULL\n" : ""}`);
  ssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${prefix}leaf.key`);
  ssl("req", "-new", "-key", `${prefix}leaf.key`, "-subj", `/CN=${prefix}Test Leaf`, "-out", `${prefix}leaf.csr`);
  ssl("x509", "-req", "-in", `${prefix}leaf.csr`, "-CA", `${prefix}inter.pem`, "-CAkey", `${prefix}inter.key`, "-CAcreateserial",
    "-days", "3650", "-sha256", "-extfile", `${prefix}leaf.ext`, "-out", `${prefix}leaf.pem`);
  const der = (f) => new crypto.X509Certificate(fs.readFileSync(path.join(dir, f))).raw.toString("base64");
  return {
    x5c: [der(`${prefix}leaf.pem`), der(`${prefix}inter.pem`), der(`${prefix}root.pem`)],
    leafKey: crypto.createPrivateKey(fs.readFileSync(path.join(dir, `${prefix}leaf.key`))),
    rootPem: fs.readFileSync(path.join(dir, `${prefix}root.pem`), "utf8"),
  };
}

function sign(payload, { x5c, leafKey }, alg = "ES256") {
  const b64 = (v) => Buffer.from(JSON.stringify(v)).toString("base64url");
  const head = `${b64({ alg, x5c })}.${b64(payload)}`;
  const sig = crypto.sign("sha256", Buffer.from(head), { key: leafKey, dsaEncoding: "ieee-p1363" });
  return `${head}.${sig.toString("base64url")}`;
}

let failures = 0;
function check(name, fn, expectError) {
  try {
    const out = fn();
    if (expectError) throw new Error(`accepted (${JSON.stringify(out).slice(0, 60)})`);
    console.log(`PASS  ${name}`);
  } catch (e) {
    if (expectError && e instanceof jws.JwsError && (!expectError.test || expectError.test(e.message))) console.log(`PASS  ${name} (rejected: ${e.message})`);
    else {
      failures++;
      console.log(`FAIL  ${name}: ${e.message}`);
    }
  }
}

const good = chain("a-");
const other = chain("b-");
const plain = chain("c-", { oids: false });
const tx = {
  transactionId: "2000000000000001",
  originalTransactionId: "2000000000000001",
  bundleId: "co.arclayer.snapreel",
  productId: "co.arclayer.snapreel.pro.yearly",
  appAccountToken: "0a0a0a0a-0000-4000-8000-00000000000a",
  expiresDate: Date.now() + 7 * 86400e3,
  environment: "Sandbox",
};
const opts = { rootPem: good.rootPem };
const token = sign(tx, good);

check("good chain verifies and returns the payload", () => {
  const out = jws.verifyAppleJws(token, opts);
  if (out.productId !== tx.productId || out.appAccountToken !== tx.appAccountToken) throw new Error("payload mismatch");
  return out;
});
check("the pinned Apple root rejects a self-made chain", () => jws.verifyAppleJws(token), /Apple Root CA/);
check("tampered payload", () => {
  const [h, , s] = token.split(".");
  const p = Buffer.from(JSON.stringify({ ...tx, productId: "free.lunch" })).toString("base64url");
  return jws.verifyAppleJws(`${h}.${p}.${s}`, opts);
}, /signature/);
check("leaf from another chain", () => {
  const mixed = { ...good, x5c: [other.x5c[0], good.x5c[1], good.x5c[2]] };
  return jws.verifyAppleJws(sign(tx, { ...mixed, leafKey: other.leafKey }), opts);
}, /leaf not signed/);
check("intermediate from another root", () => {
  const mixed = { ...good, x5c: [other.x5c[0], other.x5c[1], good.x5c[2]] };
  return jws.verifyAppleJws(sign(tx, { ...mixed, leafKey: other.leafKey }), opts);
}, /intermediate not signed/);
check("chain without Apple's marker OIDs", () => jws.verifyAppleJws(sign(tx, plain), { rootPem: plain.rootPem }), /App Store signing|WWDR/);
check("alg other than ES256", () => jws.verifyAppleJws(sign(tx, good, "HS256"), opts), /ES256/);
check("only two certificates", () => jws.verifyAppleJws(sign(tx, { ...good, x5c: good.x5c.slice(0, 2) }), opts), /three/);
check("certificate not yet valid", () => jws.verifyAppleJws(token, { ...opts, now: new Date("2000-01-01") }), /validity/);
check("garbage", () => jws.verifyAppleJws("not.a.jws", opts), /./);
check("pinned root fingerprint matches Apple's published SHA-256", () => {
  const fp = new crypto.X509Certificate(jws.APPLE_ROOT_CA_G3_PEM).fingerprint256;
  if (fp !== jws.APPLE_ROOT_CA_G3_SHA256) throw new Error(fp);
  const cer = new crypto.X509Certificate(fs.readFileSync(path.join(here, "../web/lib/server/certs/AppleRootCA-G3.cer")));
  if (cer.fingerprint256 !== fp) throw new Error("certs/AppleRootCA-G3.cer differs from the pinned PEM");
  return fp;
});

fs.rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} FAILED` : "\nall JWS checks passed");
process.exit(failures ? 1 : 0);
