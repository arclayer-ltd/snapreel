import { verifyPurchase } from "@/lib/server/appstore";
import { requireUser } from "@/lib/server/auth";
import { json, readJson, run } from "@/lib/server/http";
import { getPlan } from "@/lib/server/plan";

// POST /api/purchases/verify {signedTransaction, move?}: StoreKit 2's Transaction.jwsRepresentation. The server checks
// the x5c chain up to Apple Root CA - G3, the bundle ID, the product, and whose subscription it is
// (lib/server/subscription-rules.ts). 403 other_account {hint, canMove} when it is on another Snapreel account; with
// move: true, a running one is moved to this account.
export async function POST(req: Request) {
  return run(async () => {
    const user = await requireUser(req);
    const body = await readJson(req);
    await verifyPurchase(user.id, body.signedTransaction, { move: body.move === true });
    const { tier, productId, expiresAt } = await getPlan(user.id);
    return json({ plan: { tier, productId, expiresAt } });
  });
}
