"use client";

// What a viewer who opens the link early sees in place of the player: how far the upload is, a rough time left, and
// a plain message when it looks paused or the viewer is offline. It asks the server again every few seconds (less
// often the longer nothing changes, at once when the page comes back) and hands over the playable video by itself.
import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import type { PublicVideo } from "@/lib/contract";
import { ApiError, publicApi } from "@/lib/client/api";
import { PauseIcon, UploadIcon } from "../icons";
import "../player.css";

/** [unchanged for at least this long, ask this often]. */
const POLL: [number, number][] = [
  [30 * 60_000, 30_000],
  [5 * 60_000, 15_000],
  [60_000, 6_000],
  [0, 3_000],
];
/** The phone sends 6 MB pieces, and one can take half a minute on slow 4G: only call it paused well after that. */
const PAUSED_AFTER_MS = 90_000;
/** A link that was already old when the page opened has probably been stuck for a while. */
const OLD_LINK_MS = 15 * 60_000;
const PAUSED_AFTER_OLD_MS = 40_000;
/** Before the first byte the phone is still preparing the file, which can take minutes for a long recording. */
const NOT_STARTED_AFTER_MS = 4 * 60_000;

type Phase = "starting" | "sending" | "finishing" | "paused" | "not_started";

export function UploadingStage({
  slug,
  video,
  onReady,
  onFailed,
  onGone,
  variant = "page",
}: {
  slug: string;
  video: PublicVideo;
  onReady: (v: PublicVideo) => void;
  onFailed: () => void;
  /** The link stopped working while waiting (expired, removed, or a password was set). */
  onGone?: (error: string) => void;
  variant?: "page" | "embed";
}) {
  const [progress, setProgress] = useState<number | null>(video.uploadProgress);
  const [quietFor, setQuietFor] = useState(0);
  const [offline, setOffline] = useState(false);
  const [checking, setChecking] = useState(false);
  const [minutesLeft, setMinutesLeft] = useState<number | null>(null);
  const checkNow = useRef<() => void>(() => {});

  useEffect(() => {
    let timer = 0;
    let stopped = false;
    let running = false;
    let last = video.uploadProgress;
    const openedAt = Date.now();
    let changedAt = openedAt;
    // The first change seen, for the speed: what came before the page opened says nothing about now.
    let from: { at: number; progress: number } | null = null;

    const poll = async () => {
      window.clearTimeout(timer);
      if (stopped || running) return;
      if (document.visibilityState === "visible") {
        running = true;
        setChecking(true);
        try {
          const next = await publicApi.video(slug);
          if (stopped) return;
          setOffline(false);
          if (next.status === "ready" && next.videoUrl) {
            stopped = true;
            onReady(next);
            return;
          }
          if (next.status === "failed") {
            stopped = true;
            onFailed();
            return;
          }
          const now = Date.now();
          if (next.uploadProgress !== last) {
            last = next.uploadProgress;
            changedAt = now;
            if (last !== null) {
              if (!from || last < from.progress) from = { at: now, progress: last };
              else if (now - from.at > 8_000) {
                const perMs = (last - from.progress) / (now - from.at);
                setMinutesLeft(perMs > 0 ? (1 - last) / perMs / 60_000 : null);
              }
            }
          }
          setProgress(last);
          setQuietFor(now - changedAt);
        } catch (err) {
          if (stopped) return;
          if (err instanceof ApiError && [401, 404, 410].includes(err.status) && onGone) {
            stopped = true;
            onGone(err.code);
            return;
          }
          setOffline(err instanceof ApiError && err.status === 0);
        } finally {
          running = false;
          if (!stopped) setChecking(false);
        }
      }
      const quiet = Date.now() - changedAt;
      timer = window.setTimeout(poll, POLL.find(([after]) => quiet >= after)![1]);
    };

    const onBack = () => {
      if (document.visibilityState === "visible") void poll();
    };
    const onOffline = () => setOffline(true);
    checkNow.current = () => void poll();
    timer = window.setTimeout(poll, 3_000);
    document.addEventListener("visibilitychange", onBack);
    window.addEventListener("online", onBack);
    window.addEventListener("offline", onOffline);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onBack);
      window.removeEventListener("online", onBack);
      window.removeEventListener("offline", onOffline);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- video.uploadProgress is only where counting starts
  }, [slug, onReady, onFailed, onGone]);

  // Worked out after mount only: the server and first client render agree on "not old".
  const [old, setOld] = useState(false);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- depends on the viewer's clock
    setOld(Date.now() - Date.parse(video.createdAt) > OLD_LINK_MS);
  }, [video.createdAt]);

  const pct = progress === null ? null : Math.floor(Math.min(1, Math.max(0, progress)) * 100);
  const pausedAfter = old ? PAUSED_AFTER_OLD_MS : PAUSED_AFTER_MS;
  const phase: Phase =
    pct === null || pct >= 99
      ? quietFor > 5 * PAUSED_AFTER_MS
        ? "paused"
        : "finishing"
      : pct === 0
        ? quietFor > (old ? PAUSED_AFTER_OLD_MS : NOT_STARTED_AFTER_MS)
          ? "not_started"
          : "starting"
        : quietFor > pausedAfter
          ? "paused"
          : "sending";

  const who = video.ownerName ?? "the person who sent it";
  const Who = video.ownerName ?? "The person who sent it";
  const COPY: Record<Phase, [string, string]> = {
    starting: ["Getting ready to upload…", "The phone is preparing this video. It will start playing here by itself."],
    sending: ["Uploading…", "It will start playing here by itself. You can leave this page open."],
    finishing: ["Getting it ready…", "Nearly there. It will start playing here by itself."],
    paused: ["The upload has paused", `It carries on when ${who} opens Snapreel with a connection. This page keeps checking.`],
    not_started: ["The upload hasn’t started", `${Who} needs to open Snapreel for it to begin. This page keeps checking.`],
  };
  const [title, body] = offline
    ? ["You’re offline", "This page checks again as soon as you’re back online."]
    : COPY[phase];
  const stopped = !offline && (phase === "paused" || phase === "not_started");
  const left = phase === "sending" && !offline && minutesLeft !== null ? timeLeft(minutesLeft) : null;

  const retry = useCallback(() => checkNow.current(), []);

  const isAudio = video.kind === "audio" || video.width === 0 || video.height === 0;
  const ratio = isAudio ? 16 / 9 : video.width / video.height;
  const r = 30;
  const circumference = 2 * Math.PI * r;

  return (
    <div
      className={`relative isolate flex items-center justify-center overflow-hidden bg-[#07080c] text-white ${
        variant === "embed"
          ? "h-full w-full"
          : `min-h-72 w-full max-h-[max(24rem,calc(100svh-9.5rem))] max-lg:landscape:max-h-[calc(100svh-4rem)] sm:rounded-2xl lg:max-h-[calc(100svh-11rem)] ${isAudio ? "aspect-[4/3] sm:aspect-video" : ""}`
      }`}
      style={variant === "embed" || isAudio ? undefined : { aspectRatio: String(ratio) }}
    >
      {video.posterUrl && (
        <Image
          src={video.posterUrl}
          alt=""
          fill
          unoptimized
          loading="eager"
          fetchPriority="high"
          sizes="100vw"
          className="scale-110 object-cover opacity-35 blur-md"
          aria-hidden="true"
        />
      )}
      <div className="relative flex flex-col items-center gap-4 px-6 py-6 text-center">
        <div className="relative h-20 w-20" role="progressbar" aria-label="Upload" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct ?? undefined}>
          <svg viewBox="0 0 72 72" className="h-full w-full -rotate-90" aria-hidden="true">
            <circle cx="36" cy="36" r={r} fill="rgb(0 0 0 / 0.45)" stroke="rgb(255 255 255 / 0.18)" strokeWidth="5" />
            {pct !== null && pct > 0 && (
              <circle
                cx="36"
                cy="36"
                r={r}
                fill="none"
                stroke={stopped || offline ? "rgb(255 255 255 / 0.55)" : "var(--accent, #f04850)"}
                strokeWidth="5"
                strokeLinecap="round"
                strokeDasharray={circumference}
                strokeDashoffset={circumference * (1 - pct / 100)}
                className="transition-[stroke-dashoffset] duration-700 motion-reduce:transition-none"
              />
            )}
          </svg>
          <span
            className={`absolute inset-0 flex items-center justify-center ${
              !stopped && !offline && (phase === "starting" || phase === "finishing") ? "sr-pulse" : ""
            }`}
          >
            {stopped || offline ? (
              <PauseIcon size={24} />
            ) : phase === "sending" ? (
              <span className="text-base font-semibold tabular-nums">{pct}%</span>
            ) : (
              <UploadIcon size={26} />
            )}
          </span>
        </div>
        <div>
          <p className="text-lg font-semibold">{title}</p>
          <p className="mt-1 max-w-xs text-pretty text-sm leading-relaxed text-white/80">
            {left && <span className="block font-medium tabular-nums text-white">{left}</span>}
            {stopped && pct ? `${pct}% is here. ` : ""}
            {body}
          </p>
        </div>
        {stopped && (
          <button
            type="button"
            onClick={retry}
            disabled={checking}
            className="h-11 min-w-32 rounded-full bg-white/15 px-5 text-[15px] font-semibold text-white hover:bg-white/25 focus-visible:outline-2 focus-visible:outline-white disabled:opacity-70"
          >
            {checking ? "Checking…" : "Check now"}
          </button>
        )}
      </div>
      {/* Read out when the state changes and every tenth, not on every percent. */}
      <p className="sr-only" role="status">
        {title} {phase === "sending" && !offline && pct !== null && pct >= 10 ? `${Math.floor(pct / 10) * 10}%` : ""}
      </p>
    </div>
  );
}

function timeLeft(minutes: number): string {
  if (minutes < 1) return "Less than a minute left";
  if (minutes < 60) return `About ${Math.ceil(minutes)} min left`;
  if (minutes < 120) return "Over an hour left";
  return "Over 2 hours left";
}
