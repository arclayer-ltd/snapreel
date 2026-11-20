"use client";

// View beacons (docs/pro/API.md). A view starts once it has 5 s watched, 75% of the length watched, or
// playback reaches the last second. Then progress every 10 s of playback, "end" when it finishes, and a
// sendBeacon when the page goes away. `watched` lists the 1% buckets seen so far (0 to 99).
import { useEffect } from "react";
import type { ViewEvent } from "@/lib/contract";
import { publicApi, sendViewBeacon } from "@/lib/client/api";
import type { PlaybackStore } from "../playback";

export function useViewBeacons(slug: string, store: PlaybackStore, enabled: boolean) {
  useEffect(() => {
    if (!enabled) return;
    const watched = new Set<number>();
    let watchedS = 0;
    let lastT = store.getSnapshot().time;
    let started = false;
    let ended = false;
    let sentAtWatched = 0;
    let lastBeaconAt = 0;

    const payload = (event: ViewEvent["event"]): ViewEvent => ({
      event,
      positionS: Math.round(lastT * 10) / 10,
      watched: [...watched].sort((a, b) => a - b),
    });

    const send = (event: ViewEvent["event"]) => {
      void publicApi.view(slug, payload(event)).catch(() => {});
    };

    const unsubscribe = store.subscribe(() => {
      const s = store.getSnapshot();
      const d = s.duration;
      const t = s.time;
      const delta = t - lastT;
      if (s.playing && d > 0 && delta > 0 && delta < 1.5) {
        watchedS += delta; // seconds of the video seen, at any speed
        const from = Math.max(0, Math.floor((lastT / d) * 100));
        const to = Math.min(99, Math.floor((t / d) * 100));
        for (let b = from; b <= to; b++) watched.add(b);
      }
      lastT = t;
      const atEnd = d > 0 && t >= d - 1;
      if (!started) {
        if (watchedS >= 5 || (d > 0 && watchedS >= 0.75 * d) || (atEnd && watchedS > 0)) {
          started = true;
          sentAtWatched = watchedS;
          send("start");
        }
        return;
      }
      if (!ended && atEnd && !s.playing) {
        ended = true;
        send("end");
        return;
      }
      if (s.playing) ended = false;
      if (watchedS - sentAtWatched >= 10) {
        sentAtWatched = watchedS;
        send("progress");
      }
    });

    const flush = () => {
      if (!started) return;
      const now = Date.now();
      if (now - lastBeaconAt < 1000) return;
      lastBeaconAt = now;
      sendViewBeacon(slug, payload(ended ? "end" : "progress"));
    };
    const onVisibility = () => {
      if (document.visibilityState === "hidden") flush();
    };
    window.addEventListener("pagehide", flush);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      unsubscribe();
      window.removeEventListener("pagehide", flush);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [slug, store, enabled]);
}
