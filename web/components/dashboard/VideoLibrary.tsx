"use client";

// The signed-in list of shared videos: search, sort, and one row per link.
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { Me, VideoSummary } from "@/lib/contract";
import { formatCount, formatTime, plural } from "@/lib/client/format";
import { AlertIcon, ChevronRightIcon, CloseIcon, LockIcon, MicIcon, SearchIcon } from "@/components/player/icons";
import { RelativeTime } from "@/components/player/ui";
import settingUp from "./art/setting-up.webp";
import { ProBadge, StatusDot, linkState, statusLabel } from "./kit";

type Sort = "newest" | "oldest" | "views" | "viewers" | "recent" | "title";

const SORTS: { value: Sort; label: string }[] = [
  { value: "newest", label: "Newest first" },
  { value: "recent", label: "Recently watched" },
  { value: "views", label: "Most views" },
  { value: "viewers", label: "Most viewers" },
  { value: "oldest", label: "Oldest first" },
  { value: "title", label: "Title A to Z" },
];

function sortVideos(list: VideoSummary[], sort: Sort): VideoSummary[] {
  const copy = [...list];
  const t = (iso: string | null) => (iso ? new Date(iso).getTime() : 0);
  switch (sort) {
    case "newest":
      return copy.sort((a, b) => t(b.createdAt) - t(a.createdAt));
    case "oldest":
      return copy.sort((a, b) => t(a.createdAt) - t(b.createdAt));
    case "views":
      return copy.sort((a, b) => b.views - a.views || t(b.createdAt) - t(a.createdAt));
    case "viewers":
      return copy.sort((a, b) => b.uniqueViewers - a.uniqueViewers || t(b.createdAt) - t(a.createdAt));
    case "recent":
      return copy.sort((a, b) => t(b.lastViewedAt) - t(a.lastViewedAt) || t(b.createdAt) - t(a.createdAt));
    case "title":
      return copy.sort((a, b) => a.title.localeCompare(b.title, "en-GB", { sensitivity: "base" }));
  }
}

export function VideoLibrary({ videos, me }: { videos: VideoSummary[]; me: Me }) {
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<Sort>("newest");
  const [flash, setFlash] = useState<string | null>(null);
  const router = useRouter();

  // Said once after the page that sent here (Stop sharing) is gone.
  useEffect(() => {
    try {
      const said = sessionStorage.getItem("sr_flash");
      if (!said) return;
      sessionStorage.removeItem("sr_flash");
      // eslint-disable-next-line react-hooks/set-state-in-effect -- sessionStorage is only readable after mount
      setFlash(said);
    } catch {}
  }, []);

  // Anything still uploading: keep the list fresh, so it turns "Live" by itself.
  const uploading = videos.some((v) => v.status === "uploading");
  useEffect(() => {
    if (!uploading) return;
    const look = () => {
      if (document.visibilityState === "visible") router.refresh();
    };
    const id = window.setInterval(look, 30_000);
    document.addEventListener("visibilitychange", look);
    return () => {
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", look);
    };
  }, [uploading, router]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return sortVideos(
      videos.filter((v) => !q || v.title.toLowerCase().includes(q)),
      sort,
    );
  }, [videos, query, sort]);

  const pro = me.plan.tier === "pro";
  const totalViews = videos.reduce((n, v) => n + v.views, 0);

  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
        <div>
          <h1 className="text-[28px] font-semibold tracking-tight sm:text-[32px]">Your links</h1>
          <p className="mt-1 text-[15px] text-text-2">
            {videos.length === 0
              ? "Videos you share from the Snapreel app show up here."
              : `${plural(videos.length, "video")} shared · ${plural(totalViews, "view")} in all`}
          </p>
        </div>
        <UsageMeter me={me} pro={pro} />
      </div>

      {flash && (
        <p role="status" className="mt-4 flex items-center gap-2 rounded-2xl bg-fill px-4 py-3 text-sm">
          <span className="flex-1">{flash}</span>
          <button
            type="button"
            onClick={() => setFlash(null)}
            className="-my-2 min-h-11 rounded px-2 font-semibold text-text-2 hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
          >
            OK
          </button>
        </p>
      )}

      {videos.length === 0 ? (
        <EmptyState />
      ) : (
        <>
          <div className="mt-6 flex flex-col gap-2 sm:flex-row sm:items-center">
            <label className="flex h-11 shrink-0 items-center gap-2 rounded-full border border-line bg-surface px-4 sm:flex-1 text-text-2 focus-within:border-sr-red focus-within:ring-2 focus-within:ring-sr-red/25">
              <SearchIcon size={18} />
              <span className="sr-only">Search your videos</span>
              <input
                type="search"
                enterKeyHint="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search by title"
                className="sr-search h-full min-w-0 flex-1 bg-transparent text-base text-text placeholder:text-text-3 focus:outline-none"
              />
              {query && (
                <button
                  type="button"
                  onClick={() => setQuery("")}
                  aria-label="Clear the search"
                  className="-mr-2 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-text-2 hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
                >
                  <CloseIcon size={16} />
                </button>
              )}
            </label>
            <label className="flex h-11 shrink-0 items-center gap-2 rounded-full border border-line bg-surface pl-4 pr-2 text-sm text-text-2 focus-within:border-sr-red focus-within:ring-2 focus-within:ring-sr-red/25">
              Sort
              <select
                value={sort}
                onChange={(e) => setSort(e.target.value as Sort)}
                className="h-full min-w-0 flex-1 cursor-pointer rounded-full bg-transparent pr-1 text-base font-medium text-text focus:outline-none"
              >
                {SORTS.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
            </label>
          </div>

          <div className="mt-4 overflow-hidden rounded-3xl border border-line bg-surface">
            <div
              className="hidden grid-cols-[minmax(0,1fr)_4.5rem_4.5rem_4.5rem_5.5rem_7.5rem_7rem_1.5rem] items-center gap-5 border-b border-line px-5 py-3 text-xs font-medium uppercase tracking-wide text-text-3 lg:grid"
              aria-hidden="true"
            >
              <span>Video</span>
              <span className="text-right">Length</span>
              <span className="text-right">Views</span>
              <span className="text-right">Viewers</span>
              <span className="text-right">Comments</span>
              <span>Last watched</span>
              <span>Status</span>
              <span />
            </div>
            {shown.length === 0 ? (
              <p className="px-5 py-10 text-center text-[15px] text-text-2">No videos match &ldquo;{query.trim()}&rdquo;.</p>
            ) : (
              <ul className="divide-y divide-line">
                {shown.map((v) => (
                  <li key={v.id}>
                    <VideoRow video={v} />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </>
      )}
    </div>
  );
}

function UsageMeter({ me, pro }: { me: Me; pro: boolean }) {
  if (pro) {
    return (
      <div className="flex items-center gap-2 text-sm text-text-2">
        <ProBadge />
        <span>Unlimited links · {me.usage.quality}</span>
      </div>
    );
  }
  const limit = me.usage.linkLimit ?? 25;
  const used = Math.min(me.usage.activeLinks, limit);
  const near = used >= limit - 3;
  return (
    <div className="w-full max-w-xs sm:w-64">
      <div className="flex items-baseline justify-between text-sm">
        <span className="font-medium">
          {used} of {limit} links
        </span>
        <span className="text-text-3">Free</span>
      </div>
      <div
        className="mt-1.5 h-2 overflow-hidden rounded-full bg-fill"
        role="meter"
        aria-label="Links used"
        aria-valuemin={0}
        aria-valuemax={limit}
        aria-valuenow={used}
      >
        <div className={`h-full rounded-full ${near ? "bg-sr-red-deep" : "bg-text-2"}`} style={{ width: `${(used / limit) * 100}%` }} />
      </div>
      <p className="mt-1.5 text-xs text-text-2">Unlimited links with Pro: upgrade in the Snapreel app.</p>
    </div>
  );
}

function Thumb({ video }: { video: VideoSummary }) {
  return (
    <div className="relative aspect-video w-28 shrink-0 overflow-hidden rounded-xl bg-sr-ink sm:w-32">
      {video.posterUrl ? (
        <>
          <Image src={video.posterUrl} alt="" fill unoptimized sizes="128px" className="scale-110 object-cover opacity-50 blur-md" />
          <Image src={video.posterUrl} alt="" fill unoptimized sizes="128px" className="object-contain" />
        </>
      ) : (
        <div className="flex h-full w-full items-center justify-center text-white/70">
          {video.status === "failed" ? <AlertIcon size={22} /> : <MicIcon size={22} />}
        </div>
      )}
      <span className="absolute bottom-1 right-1 rounded-md bg-black/70 px-1.5 py-px text-[11px] font-semibold tabular-nums text-white">
        {formatTime(video.durationS)}
      </span>
    </div>
  );
}

function VideoRow({ video }: { video: VideoSummary }) {
  const state = linkState(video);
  return (
    <Link
      href={`/app/v/${video.id}`}
      className="group grid grid-cols-[auto_minmax(0,1fr)_1.25rem] items-center gap-3 px-3 py-3 transition-colors hover:bg-fill/60 focus-visible:bg-fill focus-visible:outline-none sm:gap-4 sm:px-5 lg:grid-cols-[minmax(0,1fr)_4.5rem_4.5rem_4.5rem_5.5rem_7.5rem_7rem_1.5rem] lg:gap-5 motion-reduce:transition-none"
    >
      <div className="contents lg:flex lg:min-w-0 lg:items-center lg:gap-4">
        <Thumb video={video} />
        <div className="min-w-0">
          <p className="line-clamp-2 font-semibold leading-snug group-hover:underline group-hover:decoration-line group-hover:underline-offset-4">
            {video.access === "password" && (
              <>
                <LockIcon size={14} className="mr-1.5 inline-block align-[-1px] text-text-2" />
                <span className="sr-only">Password protected: </span>
              </>
            )}
            {video.title}
          </p>
          <p className="mt-1 text-[13px] text-text-2 lg:hidden">
            {plural(video.views, "view")} · {plural(video.uniqueViewers, "viewer")}
            {video.commentCount > 0 && <> · {plural(video.commentCount, "comment")}</>}
          </p>
          <p className="mt-0.5 flex items-center gap-1.5 text-[13px] text-text-3 lg:hidden">
            {state !== "ready" ? (
              <>
                <StatusDot status={state} />
                <span className={state === "failed" ? "text-red-text" : ""}>{statusLabel(state)}</span>
              </>
            ) : video.lastViewedAt ? (
              <>
                Watched <RelativeTime iso={video.lastViewedAt} />
              </>
            ) : (
              "Not watched yet"
            )}
          </p>
          <p className="mt-1 hidden text-[13px] text-text-3 lg:block">
            Shared <RelativeTime iso={video.createdAt} />
          </p>
        </div>
      </div>
      <span className="hidden text-right text-sm tabular-nums text-text-2 lg:block">{formatTime(video.durationS)}</span>
      <span className="hidden text-right text-sm font-medium tabular-nums lg:block">{formatCount(video.views)}</span>
      <span className="hidden text-right text-sm tabular-nums lg:block">{formatCount(video.uniqueViewers)}</span>
      <span className="hidden text-right text-sm tabular-nums lg:block">{formatCount(video.commentCount)}</span>
      <span className="hidden text-sm text-text-2 lg:block">
        {video.lastViewedAt ? <RelativeTime iso={video.lastViewedAt} /> : <span className="text-text-3">Not yet</span>}
      </span>
      <span className={`hidden items-center gap-2 text-sm lg:flex ${state === "failed" ? "text-red-text" : "text-text-2"}`}>
        <StatusDot status={state} />
        {statusLabel(state)}
      </span>
      <ChevronRightIcon size={18} className="justify-self-end text-text-3" />
    </Link>
  );
}

function EmptyState() {
  return (
    <div className="mt-8 grid items-center gap-8 rounded-3xl border border-line bg-surface p-6 sm:p-10 md:grid-cols-[minmax(0,1fr)_260px]">
      <div>
        <h2 className="text-xl font-semibold tracking-tight">No links yet</h2>
        <p className="mt-2 max-w-md text-[15px] leading-relaxed text-text-2">
          Links are made in the Snapreel app on your iPhone. The moment you make one, it shows up here with its views and
          comments.
        </p>
        <ol className="mt-6 space-y-4">
          {[
            ["Record or pick a video", "Screen, camera or voice, in the Snapreel app."],
            ["Tap Copy link", "The link works straight away. The upload carries on in the background."],
            ["Paste it anywhere", "People watch in any browser, with no app and no account."],
          ].map(([title, body], i) => (
            <li key={title} className="flex gap-3">
              <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-red-soft text-sm font-semibold text-red-text">
                {i + 1}
              </span>
              <div>
                <p className="font-medium">{title}</p>
                <p className="text-sm text-text-2">{body}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>
      <div className="mx-auto w-full max-w-[260px] overflow-hidden rounded-[2rem] bg-[#f3eee6]">
        <Image src={settingUp} alt="" sizes="260px" className="h-auto w-full" />
      </div>
    </div>
  );
}
