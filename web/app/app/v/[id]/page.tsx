import type { Metadata } from "next";
import Link from "next/link";
import { Suspense, cache } from "react";
import { VideoDashboard } from "@/components/dashboard/VideoDashboard";
import { btn } from "@/components/player/ui-classes";
import type { PublicVideo } from "@/lib/contract";
import { getActivity, getInsights, getMe, getOwnerVideo, getPublicVideo } from "@/lib/server/queries";
import { getSessionUser, requireUser } from "../../_lib/session";

const ownerVideo = cache(getOwnerVideo);

export async function generateMetadata({ params }: PageProps<"/app/v/[id]">): Promise<Metadata> {
  const { id } = await params;
  const user = await getSessionUser();
  const video = user ? await ownerVideo(user.id, id) : null;
  return { title: video?.title ?? "Video" };
}

export default function VideoPage({ params }: PageProps<"/app/v/[id]">) {
  return (
    <Suspense fallback={<DetailSkeleton />}>
      <Detail params={params} />
    </Suspense>
  );
}

async function Detail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await requireUser(`/app/v/${id}`);
  const video = await ownerVideo(user.id, id);
  if (!video) return <Missing />;
  const [insights, activity, me, media] = await Promise.all([
    getInsights(user.id, id),
    getActivity(id, "owner"),
    getMe(user.id),
    // The owner's own copy for the preview player: owners skip the password, and their views don't count.
    getPublicVideo(video.slug, { unlockCookie: null, viewerUserId: user.id }),
  ]);
  const playable = media && !("error" in media) ? (media as PublicVideo) : null;
  return <VideoDashboard initial={video} insights={insights} activity={activity} me={me} media={playable} />;
}

function Missing() {
  return (
    <div className="mx-auto max-w-md py-16 text-center">
      <h1 className="text-2xl font-semibold tracking-tight">That video isn&rsquo;t here</h1>
      <p className="mt-3 text-[15px] text-text-2">It may have stopped being shared, or it belongs to a different account.</p>
      <Link href="/app" className={btn("secondary", "md", "mt-6")}>
        Back to your links
      </Link>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div aria-busy="true">
      <div className="h-11 w-24 py-3">
        <div className="h-5 rounded bg-fill motion-safe:animate-pulse" />
      </div>
      <div className="mt-2 h-9 w-2/3 rounded-xl bg-fill motion-safe:animate-pulse" />
      <div className="mt-3 h-4 w-1/2 rounded bg-fill motion-safe:animate-pulse" />
      <div className="mt-4 flex gap-2 sm:hidden">
        <div className="h-11 flex-1 rounded-full bg-fill motion-safe:animate-pulse" />
        <div className="h-11 flex-1 rounded-full bg-fill motion-safe:animate-pulse" />
      </div>
      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_400px]">
        <div className="space-y-6">
          <div className="h-[56svh] rounded-2xl bg-[#07080c] sm:aspect-video sm:h-auto" />
          <div className="h-64 rounded-3xl border border-line bg-surface" />
        </div>
        <div className="h-[32rem] rounded-3xl border border-line bg-surface" />
      </div>
      <p className="sr-only">Loading video…</p>
    </div>
  );
}
