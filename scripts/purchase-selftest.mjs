#!/usr/bin/env node
// Self-test for Snapreel Pro's server side of a purchase (web/lib/server/subscription-rules.ts and appstore.ts).
//
//   node scripts/purchase-selftest.mjs            # the rules only: no network, no secrets
//   node scripts/purchase-selftest.mjs --db       # also verify and notifications against the real database
//
// Purchases can't be made here, so --db signs transactions with a throwaway certificate chain and calls the same
// functions the routes call, handing them that chain's root (the routes themselves only ever trust Apple's). It makes
// throwaway users at Resend's test inbox, writes only their own rows, and deletes the users (and so the rows) at the
// end, even when a check fails. Needs ENV_FILE (a `vercel env pull`), web/node_modules (or NODE_MODULES) and openssl.
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import { createRequire, registerHooks } from "node:module";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.join(here, "../web");
const modules = process.env.NODE_MODULES || path.join(web, "node_modules");
const withDb = process.argv.includes("--db");

// What Next's bundler does for us: the "@/" alias, extensionless imports, "server-only" as an empty module, and (for
// --db) TypeScript that Node can't just strip.
const ts = withDb ? createRequire(path.join(modules, "../package.json"))("typescript") : null;
registerHooks({
  load(url, ctx, next) {
    if (!ts || !url.startsWith("file:") || !url.endsWith(".ts")) return next(url, ctx);
    const { outputText } = ts.transpileModule(fs.readFileSync(fileURLToPath(url), "utf8"), {
      compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
    });
    return { format: "module", source: outputText, shortCircuit: true };
  },
  resolve(spec, ctx, next) {
    if (spec === "server-only") return { url: "data:text/javascript,", shortCircuit: true };
    if (spec === "next/navigation") return { url: "data:text/javascript,export const unstable_rethrow=()=>{}", shortCircuit: true };
    const file = spec.startsWith("@/")
      ? path.join(web, spec.slice(2))
      : spec.startsWith(".") && ctx.parentURL?.startsWith("file:")
        ? path.resolve(path.dirname(fileURLToPath(ctx.parentURL)), spec)
        : null;
    if (file && fs.existsSync(`${file}.ts`)) return next(pathToFileURL(`${file}.ts`).href, ctx);
    if (!file && !spec.startsWith("node:") && ctx.parentURL?.includes("/web/lib/")) {
      return next(spec, { ...ctx, parentURL: pathToFileURL(path.join(modules, "../package.json")).href });
    }
    return next(spec, ctx);
  },
});
const load = (p) => import(pathToFileURL(path.join(web, p)).href);
const rules = await load("lib/server/subscription-rules.ts");

let passed = 0;
let failed = 0;
function same(actual, expected, name) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    passed++;
    console.log(`PASS  ${name}`);
  } else {
    failed++;
    console.log(`FAIL  ${name}: got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`);
  }
}

// ------------------------------------------------------------------------------------------------ the rules

const DAY = 86_400_000;
const now = Date.now();
const iso = (days) => new Date(now + days * DAY).toISOString();
const row = (over = {}) => ({
  user_id: "a",
  product_id: "co.arclayer.snapreel.pro.yearly",
  original_transaction_id: "100",
  status: "active",
  expires_at: iso(10),
  environment: "Production",
  ...over,
});
const inc = (over = {}) => ({ originalTransactionId: "100", status: "active", expiresAt: iso(10), environment: "Production", ...over });
const applies = (existing, incoming, want, name) => same(rules.shouldApply(existing, incoming, now), want, `rule: ${name}`);

applies(null, inc(), true, "a first purchase is stored");
applies(null, inc({ status: "expired", expiresAt: iso(-1) }), true, "an old purchase with nothing on record is stored (as expired)");
applies(row(), inc(), true, "the same transaction again");
applies(row(), inc({ expiresAt: iso(375) }), true, "a renewal");
applies(row(), inc({ status: "expired", expiresAt: iso(-20) }), false, "a missed renewal that arrives late doesn't end the current one");
applies(row({ status: "expired", expires_at: iso(-1) }), inc({ expiresAt: iso(30) }), true, "subscribing again after it ran out");
applies(row(), inc({ status: "expired", expiresAt: iso(10), notificationType: "EXPIRED" }), true, "Apple says this period ended");
applies(row({ expires_at: iso(365) }), inc({ expiresAt: iso(20), isUpgraded: true }), false, "the monthly plan a yearly upgrade replaced");
applies(row({ expires_at: iso(365) }), inc({ expiresAt: iso(20) }), false, "the old monthly transaction, signed before the upgrade");
applies(row({ expires_at: iso(20), product_id: "co.arclayer.snapreel.pro.monthly" }), inc({ expiresAt: iso(365) }), true, "monthly to yearly");
applies(row(), inc({ status: "revoked", expiresAt: iso(10), notificationType: "REFUND" }), true, "a refund of the current period ends Pro");
applies(row({ expires_at: iso(365) }), inc({ status: "revoked", expiresAt: iso(-5), notificationType: "REFUND" }), false, "a refund of an earlier period doesn't");
applies(row({ status: "revoked" }), inc(), false, "a transaction signed before the refund can't undo it");
applies(row({ status: "revoked" }), inc({ notificationType: "REFUND_REVERSED" }), true, "Apple reversing the refund does");
applies(row({ status: "revoked" }), inc({ expiresAt: iso(40) }), true, "buying again after a refund");
applies(row({ expires_at: iso(0.1) }), inc({ status: "in_grace", expiresAt: iso(16), notificationType: "DID_FAIL_TO_RENEW" }), true, "a failed renewal goes into grace");
applies(row({ status: "in_grace", expires_at: iso(10) }), inc({ status: "expired", expiresAt: iso(-6) }), false, "the app sending the lapsed period doesn't end grace");
applies(row({ status: "in_grace", expires_at: iso(0.1) }), inc({ status: "expired", expiresAt: iso(-16), notificationType: "GRACE_PERIOD_EXPIRED" }), true, "grace running out does");
applies(row({ status: "in_grace", expires_at: iso(10) }), inc({ status: "expired", expiresAt: iso(-6), notificationType: "EXPIRED" }), true, "cancelling in grace does");
applies(row({ status: "in_grace", expires_at: iso(10) }), inc({ expiresAt: iso(359) }), true, "paying in grace");
applies(row({ status: "in_grace", expires_at: iso(10) }), inc({ status: "revoked", expiresAt: iso(-6), notificationType: "REFUND" }), true, "a refund in grace");
applies(row(), inc({ environment: "Sandbox", expiresAt: iso(400) }), false, "a sandbox transaction can't replace a paid one");
applies(row(), inc({ originalTransactionId: "200", status: "expired", expiresAt: iso(-3) }), false, "a second Apple Account's lapsed subscription leaves the running one alone");
applies(row(), inc({ originalTransactionId: "200", expiresAt: iso(300) }), true, "a second Apple Account's longer one takes over");
applies(row({ expires_at: iso(300) }), inc({ originalTransactionId: "200", expiresAt: iso(10) }), false, "a second Apple Account's shorter one doesn't");
applies(row({ status: "expired", expires_at: iso(-3) }), inc({ originalTransactionId: "200" }), true, "a new Apple Account after the old one lapsed");
applies(row(), inc({ originalTransactionId: "200", environment: "Sandbox", expiresAt: iso(300) }), false, "sandbox doesn't replace production across accounts");
applies(row({ environment: "Sandbox", expires_at: iso(300) }), inc({ originalTransactionId: "200" }), true, "production replaces sandbox across accounts");

const owner = (p, want, name) => same(rules.resolveOwner({ userId: "me", recordedUserId: null, token: null, tokenAccountExists: true, ...p }), want, `owner: ${name}`);
owner({ token: "me" }, { kind: "mine" }, "bought here");
owner({ token: "ME" }, { kind: "mine" }, "the token's case doesn't matter");
owner({ token: "you" }, { kind: "other", ownerId: "you" }, "bought for another account");
owner({ token: "you", tokenAccountExists: false }, { kind: "mine" }, "that account was deleted");
owner({}, { kind: "mine" }, "bought outside the app");
owner({ recordedUserId: "you" }, { kind: "other", ownerId: "you" }, "bought outside the app, already another account's");
owner({ recordedUserId: "me", token: "you" }, { kind: "mine" }, "moved here earlier");
owner({ recordedUserId: "you", token: "me" }, { kind: "other", ownerId: "you" }, "moved away earlier");
owner({ recordedUserId: "you", token: "me", newPurchase: true }, { kind: "mine" }, "bought again here after it lapsed on another account");
owner({ recordedUserId: "you", token: "x", newPurchase: true }, { kind: "other", ownerId: "you" }, "a third account's purchase isn't mine");
const fresh = (over, existing, want, name) =>
  same(rules.isNewPurchase({ expiresDate: now + 40 * DAY, appAccountToken: "me", transactionReason: "PURCHASE", ...over }, existing, now), want, `new purchase: ${name}`);
fresh({}, row({ status: "expired", expires_at: iso(-3) }), true, "subscribing again after it lapsed");
fresh({}, row(), true, "an upgrade");
fresh({ transactionReason: "RENEWAL" }, row({ status: "expired", expires_at: iso(-3) }), false, "a late renewal isn't one");
fresh({ expiresDate: now + 10 * DAY }, row(), false, "the period already on record isn't one");
fresh({ appAccountToken: undefined }, row(), false, "bought outside the app");
fresh({ transactionReason: undefined }, row({ status: "expired", expires_at: iso(-3) }), true, "no reason given, nothing running");
fresh({ transactionReason: undefined }, row(), false, "no reason given, one running");
fresh({}, null, false, "nothing on record");
const told = (p, want, name) => same(rules.notificationOwner({ recordedUserId: null, token: null, tokenAccountExists: false, ...p }), want, `notification: ${name}`);
told({ token: "YOU", tokenAccountExists: true }, "you", "goes to the account it was bought for");
told({ token: "you", tokenAccountExists: true, recordedUserId: "me" }, "me", "follows a moved subscription");
told({ token: "you", tokenAccountExists: true, recordedUserId: "me", newPurchase: true }, "you", "goes to whoever just bought it");
told({ token: "you" }, null, "a deleted account's is left for the app");
told({}, null, "bought outside the app: nobody's until the app sends it");

const tx = (days, over = {}) => ({ expiresDate: now + days * DAY, ...over });
same(rules.statusFor(tx(5), { now }).status, "active", "status: running");
same(rules.statusFor(tx(-5), { now }).status, "expired", "status: run out");
same(rules.statusFor(tx(5, { revocationDate: now }), { now }).status, "revoked", "status: refunded");
same(rules.statusFor(tx(-1), { now, notificationType: "DID_FAIL_TO_RENEW", renewal: { originalTransactionId: "1", gracePeriodExpiresDate: now + 15 * DAY } }), { status: "in_grace", expiresAt: iso(15) }, "status: in grace until the grace date");
same(rules.statusFor(tx(-1), { now, notificationType: "DID_FAIL_TO_RENEW", renewal: { originalTransactionId: "1" } }).status, "expired", "status: billing retry without grace");
same(rules.maskEmail("rezan@gmail.com"), "r•••n@gmail.com", "hint: masks the address");
same(rules.maskEmail("ab@x.io"), "a•••@x.io", "hint: short addresses");
same(rules.maskEmail("k3j@privaterelay.appleid.com"), "Sign in with Apple (Hide My Email)", "hint: Hide My Email");
same(rules.maskEmail(null), null, "hint: none");

// ------------------------------------------------------------------------------------------------ the database

async function database() {
  const envFile = process.env.ENV_FILE || path.join(web, ".env.local");
  for (const line of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z_]+)=("?)(.*)\2$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[3];
  }
  const appstore = await load("lib/server/appstore.ts");
  const { db } = await load("lib/server/supabase.ts");
  const { getPlan } = await load("lib/server/plan.ts");

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "purchase-selftest-"));
  const ssl = (...args) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, MSYS_NO_PATHCONV: "1" } });
  const write = (n, t) => fs.writeFileSync(path.join(dir, n), t);
  ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key");
  ssl("req", "-x509", "-new", "-key", "root.key", "-subj", "/CN=Test Root", "-days", "2", "-sha384", "-addext", "basicConstraints=critical,CA:true", "-out", "root.pem");
  write("inter.ext", "basicConstraints=critical,CA:true,pathlen:0\n1.2.840.113635.100.6.2.1=ASN1:NULL\n");
  ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "inter.key");
  ssl("req", "-new", "-key", "inter.key", "-subj", "/CN=Test Intermediate", "-out", "inter.csr");
  ssl("x509", "-req", "-in", "inter.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-days", "2", "-sha384", "-extfile", "inter.ext", "-out", "inter.pem");
  write("leaf.ext", "basicConstraints=critical,CA:false\n1.2.840.113635.100.6.11.1=ASN1:NULL\n");
  ssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
  ssl("req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr");
  ssl("x509", "-req", "-in", "leaf.csr", "-CA", "inter.pem", "-CAkey", "inter.key", "-CAcreateserial", "-days", "2", "-sha256", "-extfile", "leaf.ext", "-out", "leaf.pem");
  const der = (f) => new crypto.X509Certificate(fs.readFileSync(path.join(dir, f))).raw.toString("base64");
  const x5c = ["leaf.pem", "inter.pem", "root.pem"].map(der);
  const key = crypto.createPrivateKey(fs.readFileSync(path.join(dir, "leaf.key")));
  const jws = { rootPem: fs.readFileSync(path.join(dir, "root.pem"), "utf8") };
  fs.rmSync(dir, { recursive: true, force: true });
  const sign = (payload) => {
    const b64 = (v) => Buffer.from(JSON.stringify(v)).toString("base64url");
    const head = `${b64({ alg: "ES256", x5c })}.${b64(payload)}`;
    return `${head}.${crypto.sign("sha256", Buffer.from(head), { key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
  };

  const run = crypto.randomBytes(4).toString("hex");
  const users = [];
  const newUser = async (name) => {
    const { data, error } = await db().auth.admin.createUser({ email: `delivered+iap-${name}-${run}@resend.dev`, email_confirm: true });
    if (error) throw error;
    users.push(data.user.id);
    return data.user.id;
  };
  let serial = 0;
  const original = () => `selftest-${run}-${++serial}`;
  const transaction = (otx, days, over = {}) => ({
    transactionId: `${otx}-${Math.random()}`,
    originalTransactionId: otx,
    bundleId: "co.arclayer.snapreel",
    productId: "co.arclayer.snapreel.pro.yearly",
    purchaseDate: Date.now(),
    expiresDate: Date.now() + days * DAY,
    environment: "Sandbox",
    ...over,
  });
  const verify = async (user, t, move = false) => {
    try {
      await appstore.verifyPurchase(user, sign(t), { move, jws });
      return "ok";
    } catch (e) {
      return e.status ? { status: e.status, code: e.code, ...e.extra } : Promise.reject(e);
    }
  };
  const notify = (type, t, renewal, subtype) =>
    appstore.handleNotification(
      sign({
        notificationType: type,
        subtype,
        notificationUUID: crypto.randomUUID(),
        data: { bundleId: "co.arclayer.snapreel", environment: "Sandbox", signedTransactionInfo: sign(t), ...(renewal ? { signedRenewalInfo: sign(renewal) } : {}) },
      }),
      { jws },
    );
  const pro = async (user) => (await getPlan(user)).isPro;

  try {
    const [a, b] = [await newUser("a"), await newUser("b")];
    const o1 = original();
    const mine = { appAccountToken: a };

    // The real routes must not accept this chain: without the test root the same token is refused.
    let refused = "";
    await appstore.verifyPurchase(a, sign(transaction(o1, 7, mine))).catch((e) => (refused = e.code));
    same(refused, "invalid_signature", "db: a self-signed transaction is refused by the pinned root");

    same(await verify(a, transaction(o1, 7, mine)), "ok", "db: a purchase is stored");
    same(await pro(a), true, "db: and Pro is on");
    same(await verify(a, transaction(o1, 7, mine)), "ok", "db: sending it twice is fine");
    same(await verify(b, transaction(o1, 7, mine)), { status: 403, code: "other_account", hint: `d•••${run.slice(-1)}@resend.dev`, canMove: true }, "db: another account is told whose it is");
    same(await pro(b), false, "db: and gets nothing");

    same(await verify(a, transaction(o1, -7, mine)), "ok", "db: a missed renewal arriving late is accepted");
    same(await pro(a), true, "db: without ending the current period");
    same((await notify("DID_RENEW", transaction(o1, 30, mine))).handled, true, "db: a renewal notification is applied");
    same((await notify("DID_RENEW", transaction(o1, 7, mine))).handled, false, "db: an older one arriving after it isn't");
    same((await notify("DID_FAIL_TO_RENEW", transaction(o1, 30.001, mine), { originalTransactionId: o1, gracePeriodExpiresDate: Date.now() + 46 * DAY }, "GRACE_PERIOD")).handled, true, "db: grace is applied");
    same((await notify("GRACE_PERIOD_EXPIRED", transaction(o1, 30.001, mine))).handled, true, "db: grace running out is applied");
    same(await pro(a), false, "db: and Pro is off");
    same((await notify("DID_RENEW", transaction(o1, 60, mine), null, "BILLING_RECOVERY")).handled, true, "db: billing recovered");
    same(await pro(a), true, "db: and Pro is back");

    const paid = transaction(o1, 60, mine);
    same((await notify("REFUND", { ...paid, revocationDate: Date.now() })).handled, true, "db: a refund is applied");
    same(await pro(a), false, "db: and Pro is off");
    same(await verify(a, paid), "ok", "db: the transaction from before the refund is accepted");
    same(await pro(a), false, "db: but doesn't turn Pro back on");
    same((await notify("REFUND_REVERSED", paid)).handled, true, "db: a reversed refund is applied");
    same(await pro(a), true, "db: and Pro is back");

    same(await verify(b, transaction(o1, -2, mine), true), { status: 403, code: "other_account", hint: `d•••${run.slice(-1)}@resend.dev`, canMove: false }, "db: a lapsed transaction can't move a subscription");
    same(await verify(b, paid, true), "ok", "db: the person moves Pro to their other account");
    same([await pro(a), await pro(b)], [false, true], "db: Pro moved, it wasn't copied");
    same((await notify("DID_RENEW", transaction(o1, 90, mine))).handled, true, "db: the next renewal still carries the old account's token");
    same([await pro(a), await pro(b)], [false, true], "db: and stays with the account it was moved to");
    same((await verify(a, transaction(o1, 90, mine))).code, "other_account", "db: the first account is told it moved");
    same(await verify(a, transaction(o1, 90, mine), true), "ok", "db: and can move it back");
    same([await pro(a), await pro(b)], [true, false], "db: back on the first account");

    const o2 = original();
    same(await verify(b, transaction(o2, 30)), "ok", "db: bought outside the app (no token) goes to whoever presents it first");
    same((await verify(a, transaction(o2, 30))).code, "other_account", "db: and only to them");
    same((await verify(a, transaction(o2, 30), true)).code, "already_pro", "db: no second Pro on top of a running one");
    same((await verify(b, transaction(o1, 90, mine), true)).code, "already_pro", "db: in either direction");
    same([await pro(a), await pro(b)], [true, true], "db: nothing was lost trying");

    const c = await newUser("c");
    const o3 = original();
    same(await verify(c, transaction(o3, 30, { appAccountToken: c })), "ok", "db: a third account buys");
    const { error } = await db().auth.admin.deleteUser(c);
    if (error) throw error;
    same((await notify("DID_RENEW", transaction(o3, 60, { appAccountToken: c }))).handled, false, "db: a deleted account's renewal is left alone");
    const d = await newUser("d");
    same(await verify(d, transaction(o3, 60, { appAccountToken: c })), "ok", "db: a new account picks it up after the old one was deleted");
    same(await pro(d), true, "db: and has Pro");

    const o5 = original();
    const [f, g] = [await newUser("f"), await newUser("g")];
    const bought = (user) => ({ appAccountToken: user, transactionReason: "PURCHASE" });
    same(await verify(f, transaction(o5, -1, bought(f))), "ok", "db: a subscription that lapsed under one account");
    same(await verify(g, transaction(o5, 30, bought(g))), "ok", "db: bought again under another (same Apple Account)");
    same([await pro(f), await pro(g)], [false, true], "db: goes to the account that bought it");
    same((await notify("DID_RENEW", transaction(o5, 60, { appAccountToken: g, transactionReason: "RENEWAL" }))).handled, true, "db: and renews there");
    same([await pro(f), await pro(g)], [false, true], "db: still there");
    const o6 = original();
    same(await verify(f, transaction(o6, -1, bought(f))), "ok", "db: the same again");
    const h = await newUser("h");
    same((await notify("SUBSCRIBED", transaction(o6, 30, bought(h)), null, "RESUBSCRIBE")).handled, true, "db: with Apple's notification arriving before the app");
    same(await verify(h, transaction(o6, 30, bought(h))), "ok", "db: then the app");
    same([await pro(f), await pro(h)], [false, true], "db: the buyer has it");

    const o4 = original();
    const e = await newUser("e");
    const monthly = { appAccountToken: e, productId: "co.arclayer.snapreel.pro.monthly" };
    same(await verify(e, transaction(o4, 30, monthly)), "ok", "db: monthly");
    same((await notify("DID_CHANGE_RENEWAL_PREF", transaction(o4, 365, { appAccountToken: e }), null, "UPGRADE")).handled, true, "db: upgraded to yearly");
    same(await verify(e, transaction(o4, 30, { ...monthly, isUpgraded: true })), "ok", "db: the replaced monthly transaction arrives after it");
    same((await getPlan(e)).productId, "co.arclayer.snapreel.pro.yearly", "db: and the plan stays yearly");
    same((await verify(e, transaction(o4, 30, { ...monthly, bundleId: "co.example" }))).code, "wrong_app", "db: another app's transaction");
    same((await verify(e, transaction(o4, 30, { ...monthly, productId: "co.example.gold" }))).code, "unknown_product", "db: another product");
  } finally {
    for (const id of users) await db().auth.admin.deleteUser(id).catch(() => {});
    const { data } = await db().from("subscriptions").select("user_id").like("original_transaction_id", `selftest-${run}-%`);
    same(data?.length ?? -1, 0, "db: nothing left behind");
  }
}

if (withDb) await database();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
