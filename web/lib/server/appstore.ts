import "server-only";
import { PRODUCT_MONTHLY, PRODUCT_YEARLY } from "@/lib/contract";
import type { Enums } from "./database.types";
import { env } from "./env";
import { HttpError } from "./http";
import { JwsError, verifyAppleJws, type JwsRenewalInfo, type JwsTransaction, type NotificationPayload } from "./jws";
import { db } from "./supabase";

const PRODUCTS = new Set<string>([PRODUCT_MONTHLY, PRODUCT_YEARLY]);

export function verifyJwsOr400<T>(jws: unknown, what: string): T {
  if (typeof jws !== "string") throw new HttpError(400, "bad_request", `${what} must be a JWS string.`);
  try {
    return verifyAppleJws<T>(jws);
  } catch (error) {
    if (error instanceof JwsError) throw new HttpError(400, "invalid_signature", `${what} failed Apple's signature check: ${error.message}.`);
    throw error;
  }
}

const storeEnvironment = (e: string | undefined): Enums<"store_environment"> => (e === "Production" ? "Production" : "Sandbox");

export interface SubscriptionUpdate {
  userId: string;
  productId: string;
  originalTransactionId: string;
  status: Enums<"subscription_status">;
  expiresAt: string | null;
  environment: Enums<"store_environment">;
}

// The subscription state a transaction (plus, from a notification, its renewal info and type) stands for.
export function statusFor(
  tx: JwsTransaction,
  opts: { notificationType?: string; subtype?: string; renewal?: JwsRenewalInfo | null } = {},
): { status: Enums<"subscription_status">; expiresAt: string | null } {
  const expires = tx.expiresDate ?? null;
  if (tx.revocationDate || opts.notificationType === "REFUND" || opts.notificationType === "REVOKE") {
    return { status: "revoked", expiresAt: expires ? new Date(expires).toISOString() : null };
  }
  const grace = opts.renewal?.gracePeriodExpiresDate;
  if (grace && grace > Date.now() && (opts.notificationType === "DID_FAIL_TO_RENEW" || (expires && expires < Date.now()))) {
    return { status: "in_grace", expiresAt: new Date(grace).toISOString() };
  }
  if (opts.notificationType === "EXPIRED" || opts.notificationType === "GRACE_PERIOD_EXPIRED") {
    return { status: "expired", expiresAt: expires ? new Date(expires).toISOString() : null };
  }
  if (expires && expires <= Date.now()) return { status: "expired", expiresAt: new Date(expires).toISOString() };
  return { status: "active", expiresAt: expires ? new Date(expires).toISOString() : null };
}

export function checkTransaction(tx: JwsTransaction): void {
  if (tx.bundleId !== env.bundleId) throw new HttpError(400, "wrong_app", "That purchase belongs to a different app.");
  if (!PRODUCTS.has(tx.productId)) throw new HttpError(400, "unknown_product", "That product isn't Snapreel Pro.");
}

export async function saveSubscription(u: SubscriptionUpdate): Promise<void> {
  const supabase = db();
  // One Apple subscription belongs to one Snapreel account. appAccountToken pins it when the app buys; a row for
  // the same original transaction under another user (from before a token check existed) is moved, not copied.
  const { data: existing } = await supabase
    .from("subscriptions")
    .select("user_id")
    .eq("original_transaction_id", u.originalTransactionId)
    .maybeSingle();
  if (existing && existing.user_id !== u.userId) {
    await supabase.from("subscriptions").delete().eq("original_transaction_id", u.originalTransactionId);
  }
  const { error } = await supabase.from("subscriptions").upsert(
    {
      user_id: u.userId,
      product_id: u.productId,
      original_transaction_id: u.originalTransactionId,
      status: u.status,
      expires_at: u.expiresAt,
      environment: u.environment,
    },
    { onConflict: "user_id" },
  );
  if (error) throw error;
}

// POST /api/purchases/verify: the app's StoreKit 2 Transaction.jwsRepresentation.
export async function verifyPurchase(userId: string, signedTransaction: unknown): Promise<void> {
  const tx = verifyJwsOr400<JwsTransaction>(signedTransaction, "signedTransaction");
  checkTransaction(tx);
  if (!tx.appAccountToken || tx.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    throw new HttpError(
      403,
      "other_account",
      "This purchase was made while signed in to a different Snapreel account. Sign in to that account to use it.",
    );
  }
  const { status, expiresAt } = statusFor(tx);
  await saveSubscription({
    userId,
    productId: tx.productId,
    originalTransactionId: tx.originalTransactionId,
    status,
    expiresAt,
    environment: storeEnvironment(tx.environment),
  });
}

// POST /api/appstore/notifications: App Store Server Notifications V2.
export async function handleNotification(signedPayload: unknown): Promise<{ handled: boolean; type: string }> {
  const payload = verifyJwsOr400<NotificationPayload>(signedPayload, "signedPayload");
  const type = payload.notificationType + (payload.subtype ? `/${payload.subtype}` : "");
  const data = payload.data;
  if (!data) return { handled: false, type }; // summary notifications carry no transaction
  if (data.bundleId && data.bundleId !== env.bundleId) throw new HttpError(400, "wrong_app", "Notification for another app.");
  if (payload.notificationType === "TEST" || !data.signedTransactionInfo) return { handled: false, type };

  const tx = verifyJwsOr400<JwsTransaction>(data.signedTransactionInfo, "signedTransactionInfo");
  checkTransaction(tx);
  const renewal = data.signedRenewalInfo ? verifyJwsOr400<JwsRenewalInfo>(data.signedRenewalInfo, "signedRenewalInfo") : null;

  let userId = tx.appAccountToken?.toLowerCase() ?? null;
  if (userId) {
    const { data: user } = await db().auth.admin.getUserById(userId);
    if (!user?.user) userId = null; // account deleted since
  }
  if (!userId) {
    const { data: row } = await db()
      .from("subscriptions")
      .select("user_id")
      .eq("original_transaction_id", tx.originalTransactionId)
      .maybeSingle();
    userId = row?.user_id ?? null;
  }
  if (!userId) return { handled: false, type };

  const { status, expiresAt } = statusFor(tx, {
    notificationType: payload.notificationType,
    subtype: payload.subtype,
    renewal,
  });
  await saveSubscription({
    userId,
    productId: tx.productId,
    originalTransactionId: tx.originalTransactionId,
    status,
    expiresAt,
    environment: storeEnvironment(data.environment ?? tx.environment),
  });
  return { handled: true, type };
}
