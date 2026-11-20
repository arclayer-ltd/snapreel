"use client";

// The public watch page once a video can be shown: player (or the upload in progress), reactions,
// title and owner, call-to-action, download, and a panel with comments and the transcript.
import { useCallback, useEffect, useId, useRef, useState, type ReactNode } from "react";
import type { Comment, PublicVideo, Reaction } from "@/lib/contract";
import { publicApi } from "@/lib/client/api";
import { formatDate, formatTime, plural } from "@/lib/client/format";
import { downloadName, downloadUrl, watchUrl } from "@/lib/client/links";
import { CommentIcon, DownloadIcon, ExternalIcon, FlagIcon, TranscriptIcon } from "../icons";
import { PlaybackContext, PlaybackStore } from "../playback";
import { Player } from "../Player";
import { Avatar, CopyLinkButton, btn } from "../ui";
import { accentVars } from "../ui-classes";
import { CommentsPanel } from "./CommentsPanel";
import { ReactionBar } from "./ReactionBar";
import { ReportDialog } from "./ReportDialog";
import { StateScreen } from "./StateScreen";
import { TranscriptList } from "./TranscriptList";
import { UploadingStage } from "./UploadingStage";
import { useViewBeacons } from "./useViewBeacons";
import { ViewCountSwitch } from "./ViewCountSwitch";
import { WatchFooter, WatchHeader } from "./WatchChrome";

type Tab = "comments" | "transcript";

export function WatchView({ slug, initial }: { slug: string; initial: PublicVideo }) {
  const [video, setVideo] = useState(initial);
  const [autoStart, setAutoStart] = useState(false);
  const [uploadFailed, setUploadFailed] = useState(initial.status === "failed");
  const [store] = useState(() => new PlaybackStore(initial.durationS));
  const [comments, setComments] = useState<Comment[]>([]);
  const [reactions, setReactions] = useState<Reaction[]>([]);
  const [loadingActivity, setLoadingActivity] = useState(true);
  const [reportOpen, setReportOpen] = useState(false);
  const hasTranscript = (video.transcript?.segments.length ?? 0) > 0;
  const [tab, setTab] = useState<Tab>(video.allowComments || !hasTranscript ? "comments" : "transcript");
  const playerRef = useRef<HTMLDivElement>(null);
  const tabsId = useId();

  const ready = video.status === "ready" && !!video.videoUrl;
  useViewBeacons(slug, store, ready);

  const loadActivity = useCallback(async () => {
    try {
      const a = await publicApi.activity(slug);
      setComments(a.comments);
      setReactions((mine) => [...a.reactions, ...mine.filter((r) => r.id.startsWith("temp-"))]);
    } catch {
      // Comments are a bonus; the video still plays.
    } finally {
      setLoadingActivity(false);
    }
  }, [slug]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- first load of comments and reactions
    void loadActivity();
    const onVisible = () => {
      if (document.visibilityState === "visible") void loadActivity();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [loadActivity]);

  const seek = useCallback(
    (t: number) => {
      store.seek(t, true);
      const el = playerRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      if (rect.bottom < 80 || rect.top > window.innerHeight - 80) {
        const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        el.scrollIntoView({ block: "start", behavior: reduce ? "auto" : "smooth" });
      }
    },
    [store],
  );

  const onReady = useCallback((next: PublicVideo) => {
    setVideo(next);
    setAutoStart(true);
  }, []);
  const onFailed = useCallback(() => setUploadFailed(true), []);

  if (uploadFailed) return <StateScreen state="failed" ownerName={video.ownerName} />;

  const showPanel = video.allowComments || comments.length > 0 || hasTranscript;
  const ctaLink = video.cta ? (
    <a href={video.cta.url} target="_blank" rel="noopener noreferrer nofollow ugc" className={btn("accent", "md")}>
      {video.cta.label}
      <ExternalIcon size={17} />
    </a>
  ) : null;

  return (
    <PlaybackContext value={store}>
      <div className="flex min-h-svh flex-col" style={accentVars(video.brand?.color)}>
        <WatchHeader
          logoUrl={video.brand?.logoUrl ?? null}
          ownerName={video.ownerName}
          showBadge={video.showBadge}
          actions={<CopyLinkButton url={watchUrl(slug)} variant="quiet" />}
        />

        <main className="mx-auto w-full max-w-[1400px] flex-1 lg:grid lg:grid-cols-[minmax(0,1fr)_380px] lg:items-start lg:gap-6 lg:px-6">
          <section className="min-w-0" aria-labelledby="watch-title">
            <div ref={playerRef} className="scroll-mt-2 sm:px-4 lg:px-0">
              {ready ? (
                <Player
                  src={video.videoUrl}
                  poster={video.posterUrl}
                  captionsUrl={video.captionsUrl}
                  transcript={video.transcript}
                  kind={video.kind}
                  title={video.title}
                  artist={video.ownerName}
                  width={video.width}
                  height={video.height}
                  durationS={video.durationS}
                  reactions={video.allowReactions ? reactions : []}
                  autoStart={autoStart}
                  floatReactions={video.allowReactions}
                  endScreen={ctaLink}
                />
              ) : (
                <UploadingStage slug={slug} video={video} onReady={onReady} onFailed={onFailed} />
              )}
            </div>

            <div className="px-4 lg:px-0">
              {ready && video.allowReactions && (
                <div className="-mx-1 mt-2">
                  <ReactionBar
                    slug={slug}
                    onAdd={(r) => setReactions((all) => [...all, r])}
                    onSettle={(tempId, real) =>
                      setReactions((all) => (real ? all.map((r) => (r.id === tempId ? real : r)) : all.filter((r) => r.id !== tempId)))
                    }
                  />
                </div>
              )}

              <h1 id="watch-title" className="mt-3 text-[22px] font-semibold leading-tight tracking-tight text-balance sm:text-[26px]">
                {video.title}
              </h1>
              <div className="mt-2.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-text-2">
                {video.ownerName && (
                  <>
                    <Avatar name={video.ownerName} size={24} />
                    <span className="font-medium text-text">{video.ownerName}</span>
                    <span aria-hidden="true">·</span>
                  </>
                )}
                <time dateTime={video.createdAt}>{formatDate(video.createdAt)}</time>
                <span aria-hidden="true">·</span>
                <span>{formatTime(video.durationS)}</span>
              </div>

              {(video.cta || (ready && video.allowDownload)) && (
                <div className="mt-4 flex flex-wrap items-center gap-2 [&>a:first-child]:max-sm:w-full">
                  {ctaLink}
                  {ready && video.allowDownload && video.videoUrl && (
                    <a
                      href={downloadUrl(video.videoUrl, video.title)}
                      download={downloadName(video.title)}
                      className={btn("secondary", "md")}
                    >
                      <DownloadIcon size={18} />
                      Download
                    </a>
                  )}
                </div>
              )}
            </div>
          </section>

          {showPanel && (
            <aside
              className="mx-4 mt-6 flex flex-col overflow-hidden rounded-2xl border border-line bg-surface lg:sticky lg:top-4 lg:mx-0 lg:mt-0 lg:h-[calc(100svh-6rem)] lg:max-h-[56rem]"
              aria-label="Comments and transcript"
            >
              {hasTranscript ? (
                <div role="tablist" aria-label="Show" className="flex gap-1 border-b border-line p-1.5">
                  <TabButton id={`${tabsId}-c`} panel={`${tabsId}-panel`} selected={tab === "comments"} onSelect={() => setTab("comments")}>
                    <CommentIcon size={17} />
                    Comments
                    {comments.length > 0 && <span className="tabular-nums text-text-3">{comments.length}</span>}
                  </TabButton>
                  <TabButton id={`${tabsId}-t`} panel={`${tabsId}-panel`} selected={tab === "transcript"} onSelect={() => setTab("transcript")}>
                    <TranscriptIcon size={17} />
                    Transcript
                  </TabButton>
                </div>
              ) : (
                <h2 className="flex items-center gap-2 border-b border-line px-4 py-3 text-[15px] font-semibold">
                  <CommentIcon size={17} />
                  {comments.length ? plural(comments.length, "comment") : "Comments"}
                </h2>
              )}
              <div
                id={`${tabsId}-panel`}
                role={hasTranscript ? "tabpanel" : undefined}
                aria-labelledby={hasTranscript ? (tab === "comments" ? `${tabsId}-c` : `${tabsId}-t`) : undefined}
                className="flex min-h-0 flex-1 flex-col"
              >
                {tab === "comments" || !hasTranscript ? (
                  <CommentsPanel
                    slug={slug}
                    comments={comments}
                    loading={loadingActivity}
                    allowComments={video.allowComments && ready}
                    ownerName={video.ownerName}
                    closedMessage={
                      video.allowComments && !ready
                        ? "You can comment once the video has finished uploading."
                        : undefined
                    }
                    onPosted={(c) => setComments((all) => (all.some((x) => x.id === c.id) ? all : [...all, c]))}
                    onSeek={seek}
                  />
                ) : (
                  <TranscriptList transcript={video.transcript!} onSeek={seek} />
                )}
              </div>
            </aside>
          )}
        </main>

        <WatchFooter showBadge={video.showBadge}>
          <button
            type="button"
            onClick={() => setReportOpen(true)}
            className="inline-flex items-center gap-1.5 rounded hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
          >
            <FlagIcon size={14} />
            Report this video
          </button>
          <ViewCountSwitch />
        </WatchFooter>
        <ReportDialog slug={slug} open={reportOpen} onClose={() => setReportOpen(false)} />
      </div>
    </PlaybackContext>
  );
}

function TabButton({
  id,
  panel,
  selected,
  onSelect,
  children,
}: {
  id: string;
  panel: string;
  selected: boolean;
  onSelect: () => void;
  children: ReactNode;
}) {
  return (
    <button
      id={id}
      type="button"
      role="tab"
      aria-selected={selected}
      aria-controls={panel}
      tabIndex={selected ? 0 : -1}
      onClick={onSelect}
      onKeyDown={(e) => {
        if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
          e.preventDefault();
          const sibling = (e.key === "ArrowRight" ? e.currentTarget.nextElementSibling : e.currentTarget.previousElementSibling) as
            | HTMLButtonElement
            | null;
          sibling?.focus();
          sibling?.click();
        }
      }}
      className={`flex h-10 flex-1 items-center justify-center gap-2 rounded-xl text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
        selected ? "bg-fill text-text" : "text-text-2 hover:text-text"
      }`}
    >
      {children}
    </button>
  );
}
