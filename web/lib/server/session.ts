import "server-only";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { env } from "./env";

export interface SessionUser {
  id: string;
  email: string | null;
}

// The signed-in web user from the @supabase/ssr cookie session, checked with Supabase Auth (getUser), or null.
// Works in Server Components (inside <Suspense> with cacheComponents), Route Handlers and Server Functions.
// The dashboard calls this, then passes user.id to the functions in ./queries.ts.
export async function getSessionUser(): Promise<SessionUser | null> {
  const store = await cookies();
  if (!store.getAll().some((c) => c.name.startsWith("sb-"))) return null;
  const supabase = createServerClient(env.supabaseUrl, env.publishableKey, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          for (const { name, value, options } of list) store.set(name, value, options);
        } catch {
          // Server Components can't set cookies; web/proxy.ts refreshes the session instead.
        }
      },
    },
  });
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? null };
}
