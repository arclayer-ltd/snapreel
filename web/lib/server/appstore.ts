import "server-only";
import { PRODUCT_MONTHLY, PRODUCT_YEARLY } from "@/lib/contract";
import { env } from "./env";
import { HttpError } from "./http";
import {
  JwsError,
  verifyAppleJws,
  type JwsRenewalInfo,
  type JwsTransaction,
  type NotificationPayload,
  type VerifyOptions,
} from "./jws";
import {
  isEntitled,
  isNewPurchase,
  maskEmail,
  notificationOwner,
  resolveOwner,
  shouldApply,
  statusFor,
  type StoredSubscription,
  type StoreEnvironment,
} from "./subscription-rules";
import { db } from "./supabase";

export { statusFor };

const PRODUCTS = new Set<string>([PRODUCT_MONTHLY, PRODUCT_YEARLY]);
const COLUMNS = "user_id, product_id, original_transaction_id, status, expires_at, environment";

// Routes never pass `opts`: every request is checked against Apple's pinned root. The self-test calls these functions
// directly with a throwaway root.
export function verifyJwsOr400<T>(jws: unknown, what: string, opts?: VerifyOptions): T {
  if (typeof jws !== "string") throw new HttpError(400, "bad_request", `${what} must be a JWS string.`);
  try {
    return verifyAppleJws<T>(jws, opts);
  } catch (error) {
    if (error instanceof JwsError) throw new HttpError(400, "invalid_signature", `${what} failed Apple's signature check: ${error.message}.`);
    throw error;
  }
}

const storeEnvironment = (e: string | undefined): StoreEnvironment => (e === "Production" ? "Production" : "Sandbox");

export function checkTransaction(tx: JwsTransaction): void {
  if (tx.bundleId !== env.bundleId) throw new HttpError(400, "wrong_app", "That purchase belongs to a different app.");
  if (!PRODUCTS.has(tx.productId)) throw new HttpError(400, "unknown_product", "That product isn't Snapreel Pro.");
}

// Reads throw instead of quietly answering "nothing there": a database hiccup must end in a 500, which the app and
// Apple both retry, never in a purchase that is dropped or handed to the wrong account.
async function subscriptionByTransaction(originalTransactionId: string): Promise<StoredSubscription | null> {
  const { data, error } = await db()
    .from("subscriptions")
    .select(COLUMNS)
    .eq("original_transaction_id", originalTransactionId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function subscriptionOf(userId: string): Promise<StoredSubscription | null> {
  const { data, error } = await db().from("subscriptions").select(COLUMNS).eq("user_id", userId).maybeSingle();
  if (error) throw error;
  return data;
}

async function accountOf(userId: string): Promise<{ email: string | null } | null> {
  if (!/^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(userId)) return null;
  const { data, error } = await db().auth.admin.getUserById(userId);
  if (data?.user) return { email: data.user.email ?? null };
  if (!error || error.status === 404 || error.code === "user_not_found") return null; // deleted since
  throw error;
}

// Writes the subscription to `row.user_id`. `recorded` is the row that has this subscription now, if any; when it's
// another account's, that row changes hands in one statement, so a failure half-way can't lose the subscription.
// Callers have already decided that a row of the new owner's own may go.
async function storeSubscription(row: StoredSubscription, recorded: StoredSubscription | null): Promise<void> {
  if (!recorded || recorded.user_id === row.user_id) {
    const { error } = await db().from("subscriptions").upsert(row, { onConflict: "user_id" });
    if (error) throw error;
    return;
  }
  const own = await db().from("subscriptions").delete().eq("user_id", row.user_id);
  if (own.error) throw own.error;
  const moved = await db().from("subscriptions").update(row).eq("original_transaction_id", row.original_transaction_id);
  if (moved.error) throw moved.error;
}

async function otherAccount(ownerId: string, canMove: boolean): Promise<HttpError> {
  const hint = maskEmail((await accountOf(ownerId))?.email);
  return new HttpError(
    403,
    "other_account",
    hint
      ? `This Apple Account's Snapreel Pro is on another Snapreel account (${hint}).`
      : "This Apple Account's Snapreel Pro is on another Snapreel account.",
    { hint, canMove },
  );
}

// POST /api/purchases/verify: the app's StoreKit 2 Transaction.jwsRepresentation.
// `move` takes a running subscription over from another Snapreel account: the app asks the person first, and only the
// Apple Account that pays for it can present its signed transaction.
export async function verifyPurchase(
  userId: string,
  signedTransaction: unknown,
  options: { move?: boolean; jws?: VerifyOptions } = {},
): Promise<void> {
  const tx = verifyJwsOr400<JwsTransaction>(signedTransaction, "signedTransaction", options.jws);
  checkTransaction(tx);
  const token = tx.appAccountToken?.toLowerCase() ?? null;
  const { status, expiresAt } = statusFor(tx);
  const running = isEntitled({ status, expires_at: expiresAt }) && !tx.isUpgraded;

  const recorded = await subscriptionByTransaction(tx.originalTransactionId);
  const asksForToken = !recorded && !!token && token !== userId.toLowerCase();
  const owner = resolveOwner({
    userId,
    recordedUserId: recorded?.user_id ?? null,
    token,
    tokenAccountExists: asksForToken ? !!(await accountOf(token)) : true,
    newPurchase: isNewPurchase(tx, recorded),
  });
  if (owner.kind === "other" && !(options.move && running)) throw await otherAccount(owner.ownerId, running);

  const mine = recorded?.user_id === userId ? recorded : await subscriptionOf(userId);
  const incoming = {
    originalTransactionId: tx.originalTransactionId,
    status,
    expiresAt,
    environment: storeEnvironment(tx.environment),
    isUpgraded: tx.isUpgraded,
  };
  if (owner.kind === "other") {
    // A move the person asked for.
    if (!shouldApply(recorded, incoming)) throw await otherAccount(owner.ownerId, false); // refunded or replaced since
    if (mine && isEntitled(mine)) {
      throw new HttpError(409, "already_pro", "This Snapreel account already has Pro from another subscription.");
    }
  } else if (!shouldApply(mine, incoming)) {
    return;
  }
  const row: StoredSubscription = {
    user_id: userId,
    product_id: tx.productId,
    original_transaction_id: tx.originalTransactionId,
    status,
    expires_at: expiresAt,
    environment: incoming.environment,
  };
  await storeSubscription(row, recorded);
}

// POST /api/appstore/notifications: App Store Server Notifications V2.
export async function handleNotification(
  signedPayload: unknown,
  options: { jws?: VerifyOptions } = {},
): Promise<{ handled: boolean; type: string }> {
  const payload = verifyJwsOr400<NotificationPayload>(signedPayload, "signedPayload", options.jws);
  const type = payload.notificationType + (payload.subtype ? `/${payload.subtype}` : "");
  const data = payload.data;
  if (!data) return { handled: false, type }; // summary notifications carry no transaction
  if (data.bundleId && data.bundleId !== env.bundleId) throw new HttpError(400, "wrong_app", "Notification for another app.");
  if (payload.notificationType === "TEST" || !data.signedTransactionInfo) return { handled: false, type };

  const tx = verifyJwsOr400<JwsTransaction>(data.signedTransactionInfo, "signedTransactionInfo", options.jws);
  checkTransaction(tx);
  const renewal = data.signedRenewalInfo
    ? verifyJwsOr400<JwsRenewalInfo>(data.signedRenewalInfo, "signedRenewalInfo", options.jws)
    : null;

  const recorded = await subscriptionByTransaction(tx.originalTransactionId);
  const token = tx.appAccountToken?.toLowerCase() ?? null;
  const newPurchase = isNewPurchase(tx, recorded);
  const userId = notificationOwner({
    recordedUserId: recorded?.user_id ?? null,
    token,
    tokenAccountExists: (!recorded || newPurchase) && !!token && !!(await accountOf(token)),
    newPurchase,
  });
  // Nobody's yet: the app sends the transaction itself when its owner signs in.
  if (!userId) return { handled: false, type };

  const { status, expiresAt } = statusFor(tx, { notificationType: payload.notificationType, subtype: payload.subtype, renewal });
  const environment = storeEnvironment(data.environment ?? tx.environment);
  const existing = recorded?.user_id === userId ? recorded : await subscriptionOf(userId);
  const apply = shouldApply(existing, {
    originalTransactionId: tx.originalTransactionId,
    status,
    expiresAt,
    environment,
    isUpgraded: tx.isUpgraded,
    notificationType: payload.notificationType,
  });
  if (!apply) return { handled: false, type };
  const row: StoredSubscription = {
    user_id: userId,
    product_id: tx.productId,
    original_transaction_id: tx.originalTransactionId,
    status,
    expires_at: expiresAt,
    environment,
  };
  await storeSubscription(row, recorded);
  return { handled: true, type };
}
