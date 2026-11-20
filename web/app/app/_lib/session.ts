// Who is signed in, read from the Supabase cookie session on the server.
// Call it inside a <Suspense> boundary: it reads cookies, which is request-time data.
import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { PREVIEW, PREVIEW_COOKIE } from "@/lib/client/preview-data";

export interface SessionUser {
  id: string;
  email: string | null;
}

/** A Supabase client bound to this request's cookies. Server Components can't write cookies, so the
 *  proxy refreshes the session; writes here are only kept in route handlers. */
export async function supabaseServer() {
  const store = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (list) => {
          try {
            for (const { name, value, options } of list) store.set(name, value, options);
          } catch {
            // Called from a Server Component: the proxy keeps the session fresh instead.
          }
        },
      },
    },
  );
}

export async function getSessionUser(): Promise<SessionUser | null> {
  if (PREVIEW) {
    const tier = (await cookies()).get(PREVIEW_COOKIE)?.value;
    if (tier !== "free" && tier !== "pro") return null;
    return { id: `preview-${tier}`, email: tier === "pro" ? "sam.pro@example.com" : "sam@example.com" };
  }
  try {
    const supabase = await supabaseServer();
    const { data, error } = await supabase.auth.getClaims();
    if (error || !data?.claims?.sub) return null;
    const email = typeof data.claims.email === "string" ? data.claims.email : null;
    return { id: data.claims.sub, email };
  } catch {
    return null;
  }
}

/** The signed-in user, or a redirect to /login that comes back to `next`. */
export async function requireUser(next: string): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(next)}`);
  return user;
}
