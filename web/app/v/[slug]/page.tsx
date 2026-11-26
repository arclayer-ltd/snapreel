import type { Metadata } from "next";
import { Suspense } from "react";
import { preconnect } from "react-dom";
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
  // The poster and video come from Supabase storage: open that connection while the page itself is still arriving.
  if (process.env.NEXT_PUBLIC_SUPABASE_URL) preconnect(process.env.NEXT_PUBLIC_SUPABASE_URL);
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
  return <WatchView slug={slug} initial={result} viewerIsOwner={result.viewerIsOwner} />;
}

function WatchSkeleton() {
  return (
    <div className="sr-safe-x flex min-h-svh flex-col" aria-busy="true">
      <WatchHeader logoUrl={null} ownerName={null} showBadge={false} />
      <div className="mx-auto w-full max-w-[1400px] lg:grid lg:grid-cols-[minmax(0,1fr)_380px] lg:gap-6 lg:px-6">
        <div>
          <div className="flex h-[max(24rem,calc(100svh-9.5rem))] w-full items-center justify-center bg-[#07080c] sm:mx-4 sm:aspect-video sm:h-auto sm:max-h-[calc(100svh-11rem)] sm:w-auto sm:rounded-2xl lg:mx-0">
            <span className="block h-9 w-9 animate-spin rounded-full border-[3px] border-white/20 border-t-white/80 motion-reduce:animate-none" aria-hidden="true" />
          </div>
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
