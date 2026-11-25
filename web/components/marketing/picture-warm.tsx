"use client";

import { useEffect } from "react";

type Source = { media: string; sizes: string; srcSet: string };

/** Puts one picture in the browser's cache: when a link to a page that opens with it is pointed at or touched,
    or once the page has loaded and gone quiet on a fast connection. */
export function PictureWarm({ sources }: { sources: Source[] }) {
  useEffect(() => {
    let done = false;
    const warm = () => {
      const s = sources.find((x) => window.matchMedia(x.media).matches);
      if (done || !s) return;
      done = true;
      const img = new Image();
      img.decoding = "async";
      img.sizes = s.sizes;
      img.srcset = s.srcSet;
    };
    const intent = (e: Event) => {
      const a = e.target instanceof Element ? e.target.closest("a") : null;
      if (a && /^\/(help|support|privacy|terms)\b/.test(a.getAttribute("href") ?? "")) warm();
    };
    const events = ["pointerover", "touchstart", "focusin"] as const;
    for (const t of events) document.addEventListener(t, intent, { passive: true });

    const net = (navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string } }).connection;
    let timer = 0;
    const quiet = () => {
      timer = window.setTimeout(warm, 2500);
    };
    if (net && !net.saveData && net.effectiveType === "4g") {
      if (document.readyState === "complete") quiet();
      else window.addEventListener("load", quiet, { once: true });
    }
    return () => {
      for (const t of events) document.removeEventListener(t, intent);
      window.removeEventListener("load", quiet);
      window.clearTimeout(timer);
    };
  }, [sources]);
  return null;
}
