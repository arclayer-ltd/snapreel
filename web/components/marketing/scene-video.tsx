"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";

/**
 * The living version of an illustrated scene: an AI-animated loop of the very same picture (wind in the
 * trees and flowers, birds, lamps at dusk, the characters breathing), made by scripts/web-scene-video.py.
 * A muted, looping, inline <video> laid exactly over the scene's <picture>, under the phone, the cards and
 * the text. The picture stays the first paint, the LCP and the fallback: the video only starts loading
 * after the page has loaded and gone idle, only when the scene is near the viewport, and fades in over
 * the picture once it plays. It plays only while on screen in a visible tab, follows Light/Dark and the
 * phone crop (fading out, swapping the file and fading back in), and never exists with reduced motion
 * or Save-Data.
 *
 * A scene with a foreground cut-out in front of the phone (`.mk-scene-fg`, the hero's front flower bed)
 * gets a canvas over the cut-out's box that redraws that part of the video every frame, masked by the
 * cut-out, so the flowers in front of the phone move with the rest of the bed.
 */

type Clip = { readonly w: number; readonly h: number; readonly h264: string; readonly av1?: string };
type Themed = { readonly light: Clip; readonly dark: Clip };
type Box = readonly number[];
export type SceneVideoData = {
  readonly wide: Themed;
  readonly mobile?: Themed;
  readonly fg?: { readonly wide: Box; readonly mobile?: Box };
};

const REDUCE = "(prefers-reduced-motion: reduce)";
const DARK = "(prefers-color-scheme: dark)";
/** Below this the <picture> shows a scene's phone crop (the same breakpoint as in art.tsx). */
const NARROW = "(max-width: 1023px)";
const AV1 = 'video/mp4; codecs="av01.0.08M.08"';
const FADE_MS = 600;

function watchReduce(notify: () => void) {
  const query = window.matchMedia(REDUCE);
  query.addEventListener("change", notify);
  return () => query.removeEventListener("change", notify);
}

export function SceneVideo({ data, className = "" }: { data: SceneVideoData; className?: string }) {
  // Reduced motion on the server and until hydration, so the markup never holds a video by default.
  const reduce = useSyncExternalStore(
    watchReduce,
    () => window.matchMedia(REDUCE).matches,
    () => true,
  );
  return reduce ? null : <Loop data={data} className={className} />;
}

function Loop({ data, className }: { data: SceneVideoData; className: string }) {
  const ref = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = ref.current;
    const host = video?.parentElement;
    if (!video || !host) return;
    const connection = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection;
    if (connection?.saveData) return;

    const dark = window.matchMedia(DARK);
    const narrow = window.matchMedia(NARROW);
    let av1 = video.canPlayType(AV1) === "probably";
    const crop = () => (narrow.matches && data.mobile ? "mobile" : "wide");
    const pick = () => {
      const set = crop() === "mobile" && data.mobile ? data.mobile : data.wide;
      const clip = dark.matches ? set.dark : set.light;
      return av1 && clip.av1 ? clip.av1 : clip.h264;
    };

    // The foreground cut-out's canvas, if the scene has one.
    const fgHost = data.fg ? host.parentElement?.querySelector<HTMLElement>(":scope > .mk-scene-fg") : null;
    const fgImg = fgHost?.querySelector("img") ?? null;
    let canvas: HTMLCanvasElement | null = null;
    let ctx: CanvasRenderingContext2D | null = null;
    if (fgHost && fgImg) {
      canvas = document.createElement("canvas");
      canvas.className = "mk-scene-video mk-scene-video--fg";
      canvas.setAttribute("aria-hidden", "true");
      fgHost.appendChild(canvas);
      ctx = canvas.getContext("2d");
    }
    const fgBox = () => (crop() === "mobile" ? data.fg?.mobile : data.fg?.wide) ?? null;
    const place = () => {
      const box = fgBox();
      if (!canvas || !box) return;
      canvas.style.left = `${box[0] * 100}%`;
      canvas.style.top = `${box[1] * 100}%`;
      canvas.style.width = `${(box[2] - box[0]) * 100}%`;
      canvas.style.height = `${(box[3] - box[1]) * 100}%`;
    };
    place();
    // The cut-out as a plain image of the same file (from the cache): the <img>'s own size is corrected
    // for its srcset density, which drawImage doesn't use, so its pixels can't be addressed reliably.
    let mask: HTMLImageElement | null = null;
    const loadMask = () => {
      const url = fgImg?.currentSrc;
      if (!url || mask?.src === url) return;
      mask = new Image();
      mask.decoding = "async";
      mask.src = url;
    };
    // Each video frame: that part of the video, cut to the cut-out's shape. Returns whether it drew.
    const draw = () => {
      const box = fgBox();
      loadMask();
      if (!canvas || !ctx || !mask || !box || video.readyState < 2 || !mask.complete || !mask.naturalWidth) return false;
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      const cw = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const ch = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (canvas.width !== cw || canvas.height !== ch) {
        canvas.width = cw;
        canvas.height = ch;
      }
      const [x0, y0, x1, y1] = box;
      const vw = video.videoWidth;
      const vh = video.videoHeight;
      const iw = mask.naturalWidth;
      const ih = mask.naturalHeight;
      ctx.globalCompositeOperation = "copy";
      ctx.drawImage(video, x0 * vw, y0 * vh, (x1 - x0) * vw, (y1 - y0) * vh, 0, 0, cw, ch);
      ctx.globalCompositeOperation = "destination-in";
      ctx.drawImage(mask, x0 * iw, y0 * ih, (x1 - x0) * iw, (y1 - y0) * ih, 0, 0, cw, ch);
      return true;
    };
    // Draw, and once the video shows and a frame has been drawn, fade the canvas in; after that the
    // cut-out picture under it goes (a flower that sways aside must not uncover its painted twin).
    let liveTimer = 0;
    const paint = () => {
      if (!draw() || !canvas || !video.hasAttribute("data-on") || canvas.hasAttribute("data-on")) return;
      canvas.setAttribute("data-on", "");
      clearTimeout(liveTimer);
      liveTimer = window.setTimeout(() => fgHost?.setAttribute("data-live", ""), FADE_MS + 50);
    };
    let frameHandle = 0;
    let rafHandle = 0;
    const loop = () => {
      if (!canvas) return;
      paint();
      if (typeof video.requestVideoFrameCallback === "function") frameHandle = video.requestVideoFrameCallback(loop);
      else rafHandle = requestAnimationFrame(loop);
    };
    const stopLoop = () => {
      if (frameHandle && typeof video.cancelVideoFrameCallback === "function") video.cancelVideoFrameCallback(frameHandle);
      cancelAnimationFrame(rafHandle);
      frameHandle = rafHandle = 0;
    };

    let dead = false;
    let near = false;
    let idle = false;
    let onScreen = false;
    let src = ""; // the file the video was given
    let swapping = false;
    let timer = 0;
    let idleHandle = 0;

    const run = () => {
      if (!src || swapping || dead) return;
      if (onScreen && !document.hidden) {
        video.play().catch(() => {});
        if (canvas && !frameHandle && !rafHandle) loop();
      } else {
        video.pause();
        stopLoop();
      }
    };

    const show = () => {
      if (dead || swapping) return;
      video.setAttribute("data-on", "");
      paint();
    };

    const hide = () => {
      clearTimeout(liveTimer);
      fgHost?.removeAttribute("data-live");
      video.removeAttribute("data-on");
      canvas?.removeAttribute("data-on");
    };

    const load = () => {
      if (dead) return;
      src = pick();
      place();
      video.src = src;
      video.load();
      swapping = false;
      run();
    };

    const fail = () => {
      if (dead || !src) return;
      // An AV1 file that won't play: try its H.264 twin.
      if (av1 && src.endsWith(".av1.mp4")) {
        av1 = false;
        hide();
        load();
        return;
      }
      // Otherwise back to the still picture, quietly.
      dead = true;
      hide();
      stopLoop();
      video.removeEventListener("error", fail);
      video.removeAttribute("src");
      video.load();
      canvas?.remove();
      canvas = null;
    };

    // Light to Dark, or the wide picture to the phone crop: fade out, swap the file, fade back in.
    const swap = () => {
      if (!src || dead || swapping || pick() === src) return;
      swapping = true;
      hide();
      video.pause();
      stopLoop();
      clearTimeout(timer);
      timer = window.setTimeout(load, FADE_MS);
    };

    const start = () => {
      if (src || dead || !near || !idle) return;
      load();
    };

    // Wait for the page to load, a moment more (the last pictures still have to paint), then for the main
    // thread to go idle: the picture stays the first paint and the LCP.
    const whenIdle = () => {
      const go = () => {
        idle = true;
        start();
      };
      timer = window.setTimeout(() => {
        if (typeof window.requestIdleCallback === "function") idleHandle = window.requestIdleCallback(go, { timeout: 3000 });
        else go();
      }, 1500);
    };
    if (document.readyState === "complete") whenIdle();
    else window.addEventListener("load", whenIdle, { once: true });

    const nearby = new IntersectionObserver(
      ([entry]) => {
        near = entry.isIntersecting;
        start();
      },
      { rootMargin: "600px 0px" },
    );
    const visible = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
      run();
    });
    nearby.observe(host);
    visible.observe(host);

    video.addEventListener("playing", show);
    video.addEventListener("error", fail);
    document.addEventListener("visibilitychange", run);
    dark.addEventListener("change", swap);
    narrow.addEventListener("change", swap);

    return () => {
      dead = true;
      clearTimeout(timer);
      clearTimeout(liveTimer);
      if (idleHandle) window.cancelIdleCallback(idleHandle);
      window.removeEventListener("load", whenIdle);
      nearby.disconnect();
      visible.disconnect();
      stopLoop();
      video.removeEventListener("playing", show);
      video.removeEventListener("error", fail);
      document.removeEventListener("visibilitychange", run);
      dark.removeEventListener("change", swap);
      narrow.removeEventListener("change", swap);
      fgHost?.removeAttribute("data-live");
      canvas?.remove();
    };
  }, [data]);

  return (
    <video
      ref={ref}
      className={`mk-scene-video ${className}`}
      muted
      autoPlay
      loop
      playsInline
      disablePictureInPicture
      preload="none"
      aria-hidden="true"
      tabIndex={-1}
    />
  );
}
