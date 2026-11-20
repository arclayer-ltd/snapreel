import type { Metadata } from "next";
import { Suspense } from "react";
import { AccountPanel } from "@/components/dashboard/AccountPanel";
import { getMe } from "@/lib/server/queries";
import { requireUser } from "../_lib/session";

export const metadata: Metadata = { title: "Account" };

export default function AccountPage() {
  return (
    <Suspense fallback={<AccountSkeleton />}>
      <Account />
    </Suspense>
  );
}

async function Account() {
  const user = await requireUser("/app/account");
  const me = await getMe(user.id);
  return <AccountPanel initial={me} />;
}

function AccountSkeleton() {
  return (
    <div aria-busy="true" className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center gap-4">
        <div className="h-14 w-14 rounded-full bg-fill motion-safe:animate-pulse" />
        <div className="space-y-2">
          <div className="h-7 w-48 rounded-lg bg-fill motion-safe:animate-pulse" />
          <div className="h-4 w-56 rounded bg-fill motion-safe:animate-pulse" />
        </div>
      </div>
      {Array.from({ length: 3 }, (_, i) => (
        <div key={i} className="h-40 rounded-3xl border border-line bg-surface" />
      ))}
      <p className="sr-only">Loading your account…</p>
    </div>
  );
}
