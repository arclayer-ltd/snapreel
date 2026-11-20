import "server-only";
import { LIMITS, type Plan, type Tier } from "@/lib/contract";
import { db } from "./supabase";

export interface PlanState extends Plan {
  isPro: boolean;
}

// Same rule as the SQL helper public.is_pro(uid): active or in Apple's grace period, and not past expiry.
export async function getPlan(userId: string): Promise<PlanState> {
  const { data, error } = await db()
    .from("subscriptions")
    .select("product_id, status, expires_at")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  const isPro =
    !!data &&
    (data.status === "active" || data.status === "in_grace") &&
    (!data.expires_at || new Date(data.expires_at).getTime() > Date.now());
  return {
    tier: isPro ? "pro" : "free",
    productId: isPro ? data!.product_id : null,
    expiresAt: isPro ? data!.expires_at : null,
    isPro,
  };
}

export function limitsFor(tier: Tier) {
  return tier === "pro" ? LIMITS.pro : LIMITS.free;
}

export async function activeLinkCount(userId: string): Promise<number> {
  const { data, error } = await db().rpc("active_link_count", { uid: userId });
  if (error) throw error;
  return data ?? 0;
}

export async function isPro(userId: string): Promise<boolean> {
  return (await getPlan(userId)).isPro;
}
