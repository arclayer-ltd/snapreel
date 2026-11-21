"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";
import type { MotionSlot, SceneMotion as Engine } from "./scene-motion-engine";

/**
 * The living layer of an illustrated scene: drifting clouds, birds, swaying trees and flowers, the kite,
 * the pond, butterflies and, at dusk, the lamps. A canvas laid exactly over the scene's picture inside
 * `.mk-scene-art`, under the phone, the cards and the text. The picture stays the first paint: the canvas
 * fades in over it once its first frame (identical to the picture) is drawn.
 *
 * Three.js and the scene's data load only after the page has loaded and gone idle, and only when the scene
 * is near the viewport. It draws only while on screen in a visible tab. With reduced motion there is no
 * canvas and nothing is downloaded. If WebGL is missing or anything fails, the picture simply stays.
 */

const REDUCE = "(prefers-reduced-motion: reduce)";
const LITE = "(max-width: 1023px), (pointer: coarse)";
const DARK = "(prefers-color-scheme: dark)";
/** Below this the <picture> shows a scene's phone crop (the same breakpoint as in art.tsx). */
const NARROW = "(max-width: 1023px)";

function watchReduce(notify: () => void) {
  const query = window.matchMedia(REDUCE);
  query.addEventListener("change", notify);
  return () => query.removeEventListener("change", notify);
}

export function SceneMotion({ slot }: { slot: MotionSlot }) {
  // Reduced motion on the server and until hydration, so the markup never holds a canvas by default.
  const reduce = useSyncExternalStore(
    watchReduce,
    () => window.matchMedia(REDUCE).matches,
    () => true,
  );
  return reduce ? null : <MotionCanvas slot={slot} />;
}

function MotionCanvas({ slot }: { slot: MotionSlot }) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    const art = canvas?.parentElement;
    const img = art?.querySelector("img");
    if (!canvas || !art || !img) return;

    let engine: Engine | null = null;
    let dead = false;
    let near = false;
    let idle = false;
    let started = false;
    let onScreen = false;
    let shown = ""; // the theme and crop the canvas was built for
    let swapping = false;
    let idleHandle = 0;
    let timer = 0;

    const dark = window.matchMedia(DARK);
    const lite = window.matchMedia(LITE);
    const narrow = window.matchMedia(NARROW);
    const wanted = () => ({ theme: dark.matches ? ("dark" as const) : ("light" as const), narrow: narrow.matches, lite: lite.matches });
    const key = (o: ReturnType<typeof wanted>) => `${o.theme}/${o.narrow}/${o.lite}`;
    const run = () => engine?.setRunning(onScreen && !document.hidden && !swapping);
    // The picture's box can be a fraction of a device pixel short of whole (its height comes from an
    // aspect ratio). The browser still paints the picture a whole number of pixels tall, but it rounds a
    // canvas of that fractional height down, squeezing it by a pixel against the picture. A whole size
    // keeps the two lined up exactly, so the fade between them can't be seen.
    const snap = () => {
      const box = art.getBoundingClientRect();
      const ratio = window.devicePixelRatio || 1;
      canvas.style.width = `${Math.round(box.width * ratio) / ratio}px`;
      canvas.style.height = `${Math.round(box.height * ratio) / ratio}px`;
    };

    const fail = () => {
      // Back to the still picture, quietly.
      dead = true;
      canvas.removeAttribute("data-on");
      engine?.dispose();
      engine = null;
    };

    const build = async () => {
      if (!engine || dead) return;
      const options = wanted();
      swapping = true;
      run();
      try {
        snap();
        engine.onFirstFrame(() => canvas.setAttribute("data-on", ""));
        await engine.load(options);
        shown = key(options);
      } catch {
        // If the theme or the crop changed while this one was loading, build that one instead.
        if (!dead && key(wanted()) !== key(options)) timer = window.setTimeout(build, 60);
        else if (!dead) fail();
        return;
      }
      swapping = false;
      run();
      // The theme or the crop may have changed again while this one was loading.
      if (!dead && key(wanted()) !== shown) swap();
    };

    // Light to Dark, or the wide picture to the phone crop: fade out, rebuild, fade back in.
    const swap = () => {
      if (!engine || dead || swapping || key(wanted()) === shown) return;
      swapping = true;
      run();
      canvas.removeAttribute("data-on");
      timer = window.setTimeout(build, 320);
    };

    const start = async () => {
      if (started || dead || !near || !idle) return;
      started = true;
      try {
        const { SceneMotion: Motion } = await import("./scene-motion-engine");
        if (dead) return;
        engine = new Motion(canvas, img, slot);
      } catch {
        fail();
        return;
      }
      build();
    };

    // Wait for the page to load, then a moment more (the last pictures to arrive, often the largest, still
    // have to paint), then for the main thread to go idle: the picture stays the first paint and the LCP.
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
      { rootMargin: "400px 0px" },
    );
    const visible = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
      run();
    });
    nearby.observe(canvas);
    visible.observe(canvas);

    const resized = new ResizeObserver(() => {
      snap();
      engine?.resize();
      swap();
    });
    resized.observe(art);
    const lost = (event: Event) => {
      event.preventDefault();
      fail();
    };
    canvas.addEventListener("webglcontextlost", lost);
    document.addEventListener("visibilitychange", run);
    dark.addEventListener("change", swap);
    lite.addEventListener("change", swap);
    narrow.addEventListener("change", swap);
    img.addEventListener("load", swap); // the <picture> switched files

    return () => {
      dead = true;
      clearTimeout(timer);
      if (idleHandle) window.cancelIdleCallback(idleHandle);
      window.removeEventListener("load", whenIdle);
      nearby.disconnect();
      visible.disconnect();
      resized.disconnect();
      canvas.removeEventListener("webglcontextlost", lost);
      document.removeEventListener("visibilitychange", run);
      dark.removeEventListener("change", swap);
      lite.removeEventListener("change", swap);
      narrow.removeEventListener("change", swap);
      img.removeEventListener("load", swap);
      engine?.dispose();
      engine = null;
    };
  }, [slot]);

  return <canvas ref={ref} className="mk-scene-motion" aria-hidden="true" />;
}
