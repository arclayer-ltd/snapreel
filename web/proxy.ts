import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Next 16's proxy (formerly middleware). Keeps the web sign-in fresh: when the Supabase access token in the
// cookies has expired, this refreshes it and writes the new cookies, so Server Components (which can't set
// cookies) see a valid session. It only runs on the dashboard, the sign-in page and watch pages.
export async function proxy(request: NextRequest) {
  if (!request.cookies.getAll().some((c) => c.name.startsWith("sb-"))) return NextResponse.next();
  let response = NextResponse.next({ request });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (list) => {
          for (const { name, value } of list) request.cookies.set(name, value);
          response = NextResponse.next({ request });
          for (const { name, value, options } of list) response.cookies.set(name, value, options);
        },
      },
    },
  );
  // getClaims verifies the JWT and refreshes an expired session through the cookie adapter above.
  await supabase.auth.getClaims();
  return response;
}

export const config = {
  matcher: ["/app/:path*", "/login", "/v/:path*"],
};
