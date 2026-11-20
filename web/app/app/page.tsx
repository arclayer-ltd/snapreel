import type { Metadata } from "next";
import { Suspense } from "react";
import { VideoLibrary } from "@/components/dashboard/VideoLibrary";
import { getMe, getOwnerVideos } from "@/lib/server/queries";
import { requireUser } from "./_lib/session";

export const metadata: Metadata = { title: "Your links" };

export default function DashboardPage() {
  return (
    <Suspense fallback={<ListSkeleton />}>
      <Videos />
    </Suspense>
  );
}

async function Videos() {
  const user = await requireUser("/app");
  const [videos, me] = await Promise.all([getOwnerVideos(user.id), getMe(user.id)]);
  return <VideoLibrary videos={videos} me={me} />;
}

function ListSkeleton() {
  return (
    <div aria-busy="true">
      <div className="h-9 w-48 rounded-xl bg-fill motion-safe:animate-pulse" />
      <div className="mt-2 h-5 w-64 rounded bg-fill motion-safe:animate-pulse" />
      <div className="mt-8 h-11 rounded-full bg-fill motion-safe:animate-pulse" />
      <div className="mt-4 space-y-px overflow-hidden rounded-3xl border border-line bg-surface">
        {Array.from({ length: 5 }, (_, i) => (
          <div key={i} className="flex items-center gap-4 p-4">
            <div className="aspect-video w-28 rounded-xl bg-fill motion-safe:animate-pulse sm:w-32" />
            <div className="flex-1 space-y-2">
              <div className="h-4 w-2/3 rounded bg-fill motion-safe:animate-pulse" />
              <div className="h-3 w-1/3 rounded bg-fill motion-safe:animate-pulse" />
            </div>
          </div>
        ))}
      </div>
      <p className="sr-only">Loading your videos…</p>
    </div>
  );
}
