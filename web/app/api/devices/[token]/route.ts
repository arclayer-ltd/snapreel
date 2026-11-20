import { requireUser } from "@/lib/server/auth";
import { noContent, run } from "@/lib/server/http";
import { db } from "@/lib/server/supabase";

// DELETE /api/devices/{token}: stops alert pushes to this phone (sign-out).
export async function DELETE(req: Request, ctx: RouteContext<"/api/devices/[token]">) {
  return run(async () => {
    const user = await requireUser(req);
    const { token } = await ctx.params;
    const { error } = await db().from("devices").delete().eq("token", token.toLowerCase()).eq("user_id", user.id);
    if (error) throw error;
    return noContent();
  });
}
