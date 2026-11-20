"use client";

// "Uploading… / processing" in place of the player. Polls every 3 s and hands over the playable video
// as soon as the upload is ready, so it starts by itself.
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import type { PublicVideo } from "@/lib/contract";
import { publicApi } from "@/lib/client/api";
import { UploadIcon } from "../icons";
import styles from "../player.module.css";

const POLL_MS = 3000;

export function UploadingStage({
  slug,
  video,
  onReady,
  onFailed,
  variant = "page",
}: {
  slug: string;
  video: PublicVideo;
  onReady: (v: PublicVideo) => void;
  onFailed: () => void;
  variant?: "page" | "embed";
}) {
  const [progress, setProgress] = useState<number | null>(video.uploadProgress);
  const done = useRef(false);

  useEffect(() => {
    let timer: number | undefined;
    let stopped = false;
    const poll = async () => {
      if (stopped) return;
      if (document.visibilityState === "visible") {
        try {
          const next = await publicApi.video(slug);
          if (stopped || done.current) return;
          if (next.status === "ready" && next.videoUrl) {
            done.current = true;
            onReady(next);
            return;
          }
          if (next.status === "failed") {
            done.current = true;
            onFailed();
            return;
          }
          setProgress(next.uploadProgress);
        } catch {
          // Keep trying: the phone may simply be between pieces.
        }
      }
      timer = window.setTimeout(poll, POLL_MS);
    };
    timer = window.setTimeout(poll, POLL_MS);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
    };
  }, [slug, onReady, onFailed]);

  const pct = progress === null ? null : Math.round(Math.min(1, Math.max(0, progress)) * 100);
  const processing = pct === null || pct >= 99;
  const isAudio = video.kind === "audio" || video.width === 0 || video.height === 0;
  const ratio = isAudio ? 16 / 9 : video.width / video.height;
  const r = 30;
  const circumference = 2 * Math.PI * r;

  return (
    <div
      className={`relative isolate flex items-center justify-center overflow-hidden bg-[#07080c] text-white ${
        variant === "embed" ? "h-full w-full" : "w-full max-h-[72svh] sm:rounded-2xl lg:max-h-[calc(100svh-11rem)]"
      }`}
      style={variant === "embed" ? undefined : { aspectRatio: String(ratio) }}
      role="status"
      aria-live="polite"
    >
      {video.posterUrl && (
        <Image src={video.posterUrl} alt="" fill unoptimized sizes="100vw" className="scale-110 object-cover opacity-35 blur-xl" aria-hidden="true" />
      )}
      <div className="relative flex flex-col items-center gap-4 px-6 text-center">
        <div className="relative h-20 w-20">
          <svg viewBox="0 0 72 72" className="h-full w-full -rotate-90" aria-hidden="true">
            <circle cx="36" cy="36" r={r} fill="rgb(0 0 0 / 0.35)" stroke="rgb(255 255 255 / 0.18)" strokeWidth="5" />
            {pct !== null && (
              <circle
                cx="36"
                cy="36"
                r={r}
                fill="none"
                stroke="var(--accent, #f04850)"
                strokeWidth="5"
                strokeLinecap="round"
                strokeDasharray={circumference}
                strokeDashoffset={circumference * (1 - pct / 100)}
                className="transition-[stroke-dashoffset] duration-700 motion-reduce:transition-none"
              />
            )}
          </svg>
          <span className={`absolute inset-0 flex items-center justify-center ${processing ? styles.pulse : ""}`}>
            {pct !== null && !processing ? (
              <span className="text-base font-semibold tabular-nums">{pct}%</span>
            ) : (
              <UploadIcon size={26} />
            )}
          </span>
        </div>
        <div>
          <p className="text-lg font-semibold">{processing ? "Getting it ready…" : "Uploading…"}</p>
          <p className="mt-1 max-w-xs text-sm text-white/75">
            {processing
              ? "Nearly there. It will start playing here by itself."
              : "This video is still on its way from the phone. It will start playing here by itself."}
          </p>
        </div>
      </div>
    </div>
  );
}
