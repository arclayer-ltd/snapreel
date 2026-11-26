"use client";

// /v/{slug}/embed: the player alone, filling an iframe (oEmbed and Twitter player cards).
import { useCallback, useState } from "react";
import type { PublicVideo } from "@/lib/contract";
import { publicApi } from "@/lib/client/api";
import { ExternalIcon } from "../icons";
import { PlaybackContext, PlaybackStore } from "../playback";
import { Player } from "../Player";
import { accentVars } from "../ui-classes";
import { UploadingStage } from "./UploadingStage";
import { useViewBeacons } from "./useViewBeacons";

export function EmbedView({ slug, initial }: { slug: string; initial: PublicVideo }) {
  const [video, setVideo] = useState(initial);
  const [autoStart, setAutoStart] = useState(false);
  const [failed, setFailed] = useState(initial.status === "failed");
  const [store] = useState(() => new PlaybackStore(initial.durationS));
  const ready = video.status === "ready" && !!video.videoUrl;
  useViewBeacons(slug, store, ready);

  const onReady = useCallback((next: PublicVideo) => {
    setVideo(next);
    setAutoStart(true);
  }, []);
  const onFailed = useCallback(() => setFailed(true), []);
  const onGone = useCallback(() => location.reload(), []);
  const onRefresh = useCallback(async () => {
    const next = await publicApi.video(slug);
    setVideo((v) => ({ ...v, status: next.status, videoUrl: next.videoUrl }));
    return true;
  }, [slug]);

  if (failed) return <EmbedMessage slug={slug} text="This upload didn’t finish." />;

  return (
    <PlaybackContext value={store}>
      <div className="h-svh w-full bg-[#07080c]" style={accentVars(video.brand?.color)}>
        {ready ? (
          <Player
            variant="embed"
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
            autoStart={autoStart}
            onRefresh={onRefresh}
            topOverlay={
              <a
                href={`/v/${slug}`}
                target="_blank"
                rel="noopener"
                className="inline-flex max-w-full items-center gap-2 rounded-md text-[15px] font-semibold text-white focus-visible:outline-2 focus-visible:outline-white"
              >
                <span className="truncate">{video.title}</span>
                <ExternalIcon size={15} className="shrink-0 opacity-80" />
              </a>
            }
          />
        ) : (
          <UploadingStage slug={slug} video={video} onReady={onReady} onFailed={onFailed} onGone={onGone} variant="embed" />
        )}
      </div>
    </PlaybackContext>
  );
}

export function EmbedMessage({ slug, text }: { slug: string; text: string }) {
  return (
    <div className="flex h-svh w-full flex-col items-center justify-center gap-3 bg-[#07080c] p-6 text-center text-white">
      <p className="text-[15px] font-medium">{text}</p>
      <a
        href={`/v/${slug}`}
        target="_blank"
        rel="noopener"
        className="inline-flex h-11 items-center gap-1.5 rounded-full bg-white px-5 text-sm font-semibold text-[#13141b] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      >
        Open on Snapreel
        <ExternalIcon size={15} />
      </a>
    </div>
  );
}
