"use client";

import { useEffect, useRef } from "react";

/**
 * A recorded app flow playing on an iPhone's screen (muted, looping, inline). It sits over the screen's
 * still picture, which shows until the first frame is ready, and plays only while it's on screen. With
 * reduced motion it never plays, so the still stays. Light and Dark recordings are picked with
 * prefers-color-scheme.
 */
export function FlowVideo({ light, dark, priority = false }: { light: string; dark: string; priority?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = ref.current;
    if (!video) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reduce.matches) return;
    const show = () => video.setAttribute("data-playing", "");
    video.addEventListener("playing", show);
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          if (video.preload === "none") video.preload = "auto";
          video.play().catch(() => {});
        } else {
          video.pause();
        }
      },
      { rootMargin: "240px 0px" },
    );
    observer.observe(video);
    return () => {
      observer.disconnect();
      video.removeEventListener("playing", show);
    };
  }, []);

  return (
    <video
      ref={ref}
      className="mk-flow"
      muted
      loop
      playsInline
      disablePictureInPicture
      preload={priority ? "auto" : "none"}
      aria-hidden="true"
      tabIndex={-1}
    >
      <source media="(prefers-color-scheme: dark)" src={dark} type="video/mp4" />
      <source src={light} type="video/mp4" />
    </video>
  );
}
