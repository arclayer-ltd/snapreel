import { verifyPurchase } from "@/lib/server/appstore";
import { requireUser } from "@/lib/server/auth";
import { json, readJson, run } from "@/lib/server/http";
import { getPlan } from "@/lib/server/plan";

// POST /api/purchases/verify {signedTransaction}: StoreKit 2's Transaction.jwsRepresentation. The server checks
// the x5c chain up to Apple Root CA - G3, the bundle ID, the product, and that appAccountToken is this user's ID.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    await verifyPurchase(user.id, body.signedTransaction);
    const { tier, productId, expiresAt } = await getPlan(user.id);
    return json({ plan: { tier, productId, expiresAt } });
  });
}
