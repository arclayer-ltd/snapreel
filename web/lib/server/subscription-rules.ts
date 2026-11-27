// What an App Store transaction means for a Snapreel account. Pure functions, no "server-only" import, so
// scripts/purchase-selftest.mjs can run them with plain Node. The database half is in appstore.ts.
//
// Three things make this more than "write what Apple says":
//  1. Apple delivers late and out of order. The app sends every renewal it missed, oldest first or last, and
//     notifications are retried for days, so an old period must never overwrite a newer one.
//  2. A signed transaction never expires. One signed before a refund still verifies, so it must not undo the refund.
//  3. One subscription belongs to one Snapreel account at a time, whoever's signed in when its transaction arrives.
import type { JwsRenewalInfo, JwsTransaction } from "./jws";

export type SubscriptionStatus = "active" | "in_grace" | "expired" | "revoked";
export type StoreEnvironment = "Production" | "Sandbox";

export interface StoredSubscription {
  user_id: string;
  product_id: string;
  original_transaction_id: string;
  status: SubscriptionStatus;
  expires_at: string | null;
  environment: StoreEnvironment;
}

export interface IncomingState {
  originalTransactionId: string;
  status: SubscriptionStatus;
  expiresAt: string | null;
  environment: StoreEnvironment;
  /** Superseded by an upgrade inside the same subscription group. */
  isUpgraded?: boolean;
  /** The App Store Server Notification it came with, when it came with one. */
  notificationType?: string;
}

// Apple's billing grace period is 3, 16 or 28 days.
const GRACE_MAX_MS = 29 * 86_400_000;

const ms = (iso: string | null): number => (iso ? Date.parse(iso) : Number.POSITIVE_INFINITY);

/** The same rule as plan.ts and the SQL helper public.is_pro. */
export function isEntitled(s: { status: SubscriptionStatus; expires_at: string | null }, now = Date.now()): boolean {
  return (s.status === "active" || s.status === "in_grace") && ms(s.expires_at) > now;
}

/** The subscription state a transaction (plus, from a notification, its renewal info and type) stands for. */
export function statusFor(
  tx: Pick<JwsTransaction, "expiresDate" | "revocationDate">,
  opts: { notificationType?: string; subtype?: string; renewal?: JwsRenewalInfo | null; now?: number } = {},
): { status: SubscriptionStatus; expiresAt: string | null } {
  const now = opts.now ?? Date.now();
  const expires = tx.expiresDate ?? null;
  const expiresAt = expires ? new Date(expires).toISOString() : null;
  if (tx.revocationDate || opts.notificationType === "REFUND" || opts.notificationType === "REVOKE") {
    return { status: "revoked", expiresAt };
  }
  const grace = opts.renewal?.gracePeriodExpiresDate;
  if (grace && grace > now && (opts.notificationType === "DID_FAIL_TO_RENEW" || (expires && expires < now))) {
    return { status: "in_grace", expiresAt: new Date(grace).toISOString() };
  }
  if (opts.notificationType === "EXPIRED" || opts.notificationType === "GRACE_PERIOD_EXPIRED") {
    return { status: "expired", expiresAt };
  }
  if (expires && expires <= now) return { status: "expired", expiresAt };
  return { status: "active", expiresAt };
}

/**
 * Whether `incoming` should replace `existing`, the row the account (or the same subscription) has now.
 * False means it is old news, and the row stays as it is.
 */
export function shouldApply(existing: StoredSubscription | null, incoming: IncomingState, now = Date.now()): boolean {
  if (incoming.isUpgraded) return false; // the upgrade's own transaction says what the plan is now
  if (!existing) return true;
  const oldEnd = ms(existing.expires_at);
  const newEnd = ms(incoming.expiresAt);
  const oldOn = isEntitled(existing, now);
  const newOn = isEntitled({ status: incoming.status, expires_at: incoming.expiresAt }, now);

  if (existing.original_transaction_id !== incoming.originalTransactionId) {
    // A second subscription on the same Snapreel account (another Apple Account, say). Keep whichever lasts.
    if (oldOn && !newOn) return false;
    if (oldOn && newOn) {
      if (existing.environment !== incoming.environment) return incoming.environment === "Production";
      return newEnd > oldEnd;
    }
    return newOn || newEnd >= oldEnd;
  }

  if (existing.environment === "Production" && incoming.environment === "Sandbox") return false;

  if (incoming.status === "revoked") {
    // A refund of the current period ends Pro; a refund of an older one doesn't. In grace, expires_at is the
    // grace date, which is later than the period that was refunded.
    if (existing.status === "in_grace") return newEnd + GRACE_MAX_MS >= oldEnd;
    return newEnd >= oldEnd;
  }
  if (existing.status === "revoked") {
    // Only a newer period (they subscribed again) or Apple reversing the refund turns it back on.
    return newEnd > oldEnd || incoming.notificationType === "REFUND_REVERSED";
  }
  if (incoming.status === "expired" && existing.status === "in_grace") {
    // Grace ran out: the period that expired is older than the grace date on the row.
    const ended = incoming.notificationType === "EXPIRED" || incoming.notificationType === "GRACE_PERIOD_EXPIRED";
    return ended ? newEnd + GRACE_MAX_MS >= oldEnd : newEnd >= oldEnd;
  }
  return newEnd >= oldEnd;
}

/**
 * Whether this transaction is somebody buying (not renewing) a period the row hasn't seen. Subscribing again keeps the
 * Apple Account's original transaction ID, so a subscription that lapsed under one Snapreel account and was bought again
 * under another arrives on the first account's row. A renewal also carries a token, the one from when it was bought,
 * and must not undo a later move.
 */
export function isNewPurchase(
  tx: Pick<JwsTransaction, "expiresDate" | "appAccountToken" | "transactionReason">,
  recorded: StoredSubscription | null,
  now = Date.now(),
): boolean {
  if (!recorded || !tx.appAccountToken || !tx.expiresDate) return false;
  if (tx.expiresDate <= ms(recorded.expires_at)) return false;
  return tx.transactionReason === "PURCHASE" || (!tx.transactionReason && !isEntitled(recorded, now));
}

export type Ownership =
  | { kind: "mine" }
  /** Another Snapreel account has it. */
  | { kind: "other"; ownerId: string };

const sameId = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

/**
 * Who a subscription belongs to when `userId` presents its transaction.
 *  - the account it was just bought for, when this is a new purchase;
 *  - else the account that already has it on record;
 *  - else the account it was bought for (`appAccountToken`), while that account exists;
 *  - else whoever presents it: bought outside the app (offer code, the App Store's own page), or for an account
 *    that has since been deleted. Only the Apple Account that paid can produce the signed transaction.
 */
export function resolveOwner(p: {
  userId: string;
  recordedUserId: string | null;
  token: string | null;
  tokenAccountExists: boolean;
  newPurchase?: boolean;
}): Ownership {
  if (p.newPurchase && p.token && sameId(p.token, p.userId)) return { kind: "mine" };
  if (p.recordedUserId) return sameId(p.recordedUserId, p.userId) ? { kind: "mine" } : { kind: "other", ownerId: p.recordedUserId };
  if (!p.token || sameId(p.token, p.userId) || !p.tokenAccountExists) return { kind: "mine" };
  return { kind: "other", ownerId: p.token.toLowerCase() };
}

/**
 * The account a notification is about: the one that just bought it, the one that has it on record (it may have been
 * moved since it was bought), or the one it was bought for.
 */
export function notificationOwner(p: {
  recordedUserId: string | null;
  token: string | null;
  tokenAccountExists: boolean;
  newPurchase?: boolean;
}): string | null {
  const bought = p.token && p.tokenAccountExists ? p.token.toLowerCase() : null;
  if (p.newPurchase && bought) return bought;
  return p.recordedUserId ?? bought;
}

/** "r•••s@gmail.com", so a person recognises their other account without it being spelled out. */
export function maskEmail(email: string | null | undefined): string | null {
  if (!email) return null;
  const at = email.lastIndexOf("@");
  if (at < 1) return null;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1).toLowerCase();
  if (domain === "privaterelay.appleid.com") return "Sign in with Apple (Hide My Email)";
  const tail = local.length > 3 ? local.slice(-1) : "";
  return `${local[0]}•••${tail}@${domain}`;
}
