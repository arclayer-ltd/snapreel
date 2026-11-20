import type { Metadata } from "next";
import { Suspense } from "react";
import { PasswordGate } from "@/components/player/watch/PasswordGate";
import { StateScreen } from "@/components/player/watch/StateScreen";
import { WatchView } from "@/components/player/watch/WatchView";
import { WatchHeader } from "@/components/player/watch/WatchChrome";
import { loadPublicVideo, watchMetadata } from "./watch-data";

export async function generateMetadata({ params }: PageProps<"/v/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  return watchMetadata(slug, await loadPublicVideo(slug));
}

// With Cache Components, params and cookies are request-time data: the page shell renders at once and
// the video streams in behind the boundary.
export default function WatchPage({ params }: PageProps<"/v/[slug]">) {
  return (
    <Suspense fallback={<WatchSkeleton />}>
      <Watch params={params} />
    </Suspense>
  );
}

async function Watch({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const result = await loadPublicVideo(slug);
  if ("error" in result) {
    if (result.error === "password") return <PasswordGate slug={slug} />;
    return <StateScreen state={result.error} />;
  }
  if (result.status === "failed") return <StateScreen state="failed" ownerName={result.ownerName} />;
  return <WatchView slug={slug} initial={result} />;
}

function WatchSkeleton() {
  return (
    <div className="flex min-h-svh flex-col" aria-busy="true">
      <WatchHeader logoUrl={null} ownerName={null} showBadge={false} />
      <div className="mx-auto w-full max-w-[1400px] lg:grid lg:grid-cols-[minmax(0,1fr)_380px] lg:gap-6 lg:px-6">
        <div>
          <div className="aspect-video w-full bg-[#07080c] sm:mx-4 sm:w-auto sm:rounded-2xl lg:mx-0" />
          <div className="space-y-3 px-4 pt-14 lg:px-0">
            <div className="h-7 w-2/3 rounded-lg bg-fill motion-safe:animate-pulse" />
            <div className="h-4 w-1/3 rounded bg-fill motion-safe:animate-pulse" />
          </div>
        </div>
        <div className="mx-4 mt-6 h-64 rounded-2xl border border-line bg-surface lg:mx-0 lg:mt-0 lg:h-[calc(100svh-6rem)]" />
      </div>
      <p className="sr-only">Loading video…</p>
    </div>
  );
}
