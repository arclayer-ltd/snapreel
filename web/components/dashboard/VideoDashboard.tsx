"use client";

// One shared video: preview, insights, comments and reactions, settings, copy, open, stop sharing.
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import type { Activity, Insights, Me, PublicVideo, VideoDetail } from "@/lib/contract";
import { errorMessage, ownerApi } from "@/lib/client/api";
import { formatDate, formatTime, formatUntil, isPast } from "@/lib/client/format";
import { watchUrl } from "@/lib/client/links";
import { AlertIcon, ChevronLeftIcon, ClockIcon, ExternalIcon, LockIcon, TrashIcon, UploadIcon } from "@/components/player/icons";
import { PlaybackContext, PlaybackStore } from "@/components/player/playback";
import { Player } from "@/components/player/Player";
import { CopyLinkButton, Dialog, Spinner, btn } from "@/components/player/ui";
import { ActivityPanel } from "./ActivityPanel";
import { InsightsPanel } from "./InsightsPanel";
import { StatusDot, linkState, statusLabel } from "./kit";
import { SettingsForm } from "./SettingsForm";

type Tab = "insights" | "activity" | "settings";

export function VideoDashboard({
  initial,
  insights,
  activity,
  me,
  media,
}: {
  initial: VideoDetail;
  insights: Insights | null;
  activity: Activity;
  me: Me;
  media: PublicVideo | null;
}) {
  const router = useRouter();
  const [video, setVideo] = useState(initial);
  const [store] = useState(() => new PlaybackStore(initial.durationS));
  const [tab, setTab] = useState<Tab>("insights");
  const [confirmStop, setConfirmStop] = useState(false);
  const [stopping, setStopping] = useState(false);
  const [stopError, setStopError] = useState<string | null>(null);
  const pro = me.plan.tier === "pro";

  // While it's uploading the page asks again by itself, and takes the new state when it arrives.
  const [seen, setSeen] = useState(initial);
  if (seen !== initial) {
    setSeen(initial);
    if (initial.status !== video.status) setVideo(initial);
  }
  const uploading = video.status === "uploading";
  useEffect(() => {
    if (!uploading) return;
    const look = () => {
      if (document.visibilityState === "visible") router.refresh();
    };
    const id = window.setInterval(look, 15_000);
    document.addEventListener("visibilitychange", look);
    return () => {
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", look);
    };
  }, [uploading, router]);
  const url = watchUrl(video.slug);
  const expired = video.expiresAt ? isPast(video.expiresAt) : false;

  async function stopSharing() {
    setStopping(true);
    setStopError(null);
    try {
      await ownerApi.deleteVideo(video.id);
      try {
        sessionStorage.setItem("sr_flash", `“${video.title}” isn’t shared any more. Its link has stopped working.`);
      } catch {}
      router.replace("/app");
      router.refresh();
    } catch (err) {
      setStopping(false);
      setStopError(errorMessage(err, "Sharing didn't stop. Try again."));
    }
  }

  const tabs: { id: Tab; label: string }[] = [
    { id: "insights", label: "Insights" },
    { id: "activity", label: `Comments${activity.comments.length ? ` (${activity.comments.length})` : ""}` },
    { id: "settings", label: "Settings" },
  ];
  const shown = (id: Tab) => (tab === id ? "" : "max-lg:hidden");

  return (
    <PlaybackContext value={store}>
      <Link
        href="/app"
        className="-ml-2 inline-flex h-11 items-center gap-1 rounded-full px-2 text-sm font-semibold text-text-2 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
      >
        <ChevronLeftIcon size={17} />
        All links
      </Link>

      <div className="mt-2 flex flex-wrap items-start justify-between gap-x-6 gap-y-4">
        <div className="min-w-0">
          <h1 className="text-[26px] font-semibold leading-tight tracking-tight text-balance sm:text-[30px]">{video.title}</h1>
          <p className="mt-2 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-sm text-text-2">
            <span className="inline-flex items-center gap-1.5">
              <StatusDot status={linkState(video)} />
              {statusLabel(linkState(video))}
            </span>
            <span aria-hidden="true">·</span>
            <span>Shared {formatDate(video.createdAt)}</span>
            <span aria-hidden="true">·</span>
            <span>{formatTime(video.durationS)}</span>
            {video.access === "password" && (
              <span className="inline-flex items-center gap-1 rounded-full bg-fill px-2 py-0.5 text-xs font-medium text-text">
                <LockIcon size={12} /> Password
              </span>
            )}
            {video.expiresAt && !expired && (
              <span className="inline-flex items-center gap-1 rounded-full bg-fill px-2 py-0.5 text-xs font-medium text-text">
                <ClockIcon size={12} /> Ends {formatUntil(video.expiresAt)}
              </span>
            )}
          </p>
        </div>
        <div className="flex w-full flex-wrap gap-2 sm:w-auto">
          {/* A failed upload has nothing to watch yet: no link to hand out until the phone sends it again. */}
          {video.status !== "failed" && (
            <>
              <CopyLinkButton url={url} variant="primary" size="md" className="max-sm:flex-1" />
              <a href={`/v/${video.slug}`} target="_blank" rel="noopener" className={btn("secondary", "md", "max-sm:flex-1")}>
                Open
                <ExternalIcon size={17} />
              </a>
            </>
          )}
          <button type="button" onClick={() => setConfirmStop(true)} className={btn("quiet", "md", "text-red-text max-sm:w-full")}>
            <TrashIcon size={17} />
            Stop sharing
          </button>
        </div>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_400px] lg:items-start">
        <div className="min-w-0 space-y-6">
          <Preview video={video} media={media} expired={expired} activity={activity} />

          <div role="tablist" aria-label="Sections" className="flex gap-1 rounded-full bg-fill p-1 lg:hidden">
            {tabs.map((t) => (
              <button
                key={t.id}
                type="button"
                role="tab"
                aria-selected={tab === t.id}
                onClick={() => setTab(t.id)}
                className={`h-11 flex-1 rounded-full text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
                  tab === t.id ? "bg-surface text-text shadow-sm" : "text-text-2"
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>

          <div className={shown("insights")}>
            <InsightsPanel
              video={video}
              insights={insights}
              pro={pro}
              activityCount={activity.comments.length + activity.reactions.length}
            />
          </div>
          <div className={shown("activity")}>
            <ActivityPanel
              initial={activity}
              allowComments={video.allowComments}
              videoId={video.id}
              slug={video.slug}
              ownerName={me.user.displayName}
            />
          </div>
        </div>
        <div className={`lg:sticky lg:top-24 ${shown("settings")}`}>
          <SettingsForm
            key={video.id}
            video={video}
            pro={pro}
            onSaved={(next) => {
              setVideo(next);
              router.refresh();
            }}
          />
        </div>
      </div>

      <Dialog open={confirmStop} onClose={() => setConfirmStop(false)} title="Stop sharing this video?">
        <p className="text-[15px] leading-relaxed text-text-2">
          The link stops working straight away, and the copy on Snapreel&rsquo;s servers is deleted with its views, comments
          and reactions. The recording stays on your iPhone, and you can share it again later as a new link.
        </p>
        {stopError && (
          <p role="alert" className="mt-3 text-sm text-red-text">
            {stopError}
          </p>
        )}
        <div className="mt-6 flex justify-end gap-2">
          <button type="button" className={btn("ghost", "md", "max-sm:flex-1")} onClick={() => setConfirmStop(false)}>
            Keep sharing
          </button>
          <button type="button" className={btn("primary", "md", "min-w-[8.5rem] max-sm:flex-1")} onClick={stopSharing} disabled={stopping}>
            {stopping ? <Spinner size={16} /> : "Stop sharing"}
          </button>
        </div>
      </Dialog>
    </PlaybackContext>
  );
}

function Preview({
  video,
  media,
  expired,
  activity,
}: {
  video: VideoDetail;
  media: PublicVideo | null;
  expired: boolean;
  activity: Activity;
}) {
  if (media && media.status === "ready" && media.videoUrl) {
    return (
      <Player
        variant="preview"
        src={media.videoUrl}
        poster={media.posterUrl}
        captionsUrl={media.captionsUrl}
        transcript={media.transcript}
        kind={media.kind}
        title={media.title}
        width={media.width}
        height={media.height}
        durationS={media.durationS}
        reactions={activity.reactions}
      />
    );
  }
  const message =
    video.status === "uploading"
      ? "Still uploading from your iPhone. This page updates by itself."
      : video.status === "failed"
        ? "This upload didn't finish. Open Snapreel on your iPhone to send it again."
        : expired
          ? "This link has expired, so nobody can watch it. Change when it stops working in Settings."
          : "The preview isn't available right now.";
  return (
    <div className="relative flex aspect-video w-full items-center justify-center overflow-hidden rounded-2xl bg-[#07080c] text-white">
      {video.posterUrl && (
        <Image src={video.posterUrl} alt="" fill unoptimized sizes="(min-width: 1024px) 700px, 100vw" className="object-cover opacity-40 blur-md" />
      )}
      <div className="relative flex max-w-sm flex-col items-center gap-3 px-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-white/15">
          {video.status === "uploading" ? (
            <UploadIcon size={22} />
          ) : video.status === "failed" ? (
            <AlertIcon size={22} />
          ) : (
            <ClockIcon size={22} />
          )}
        </span>
        <p className="text-[15px] font-medium">{message}</p>
      </div>
    </div>
  );
}
