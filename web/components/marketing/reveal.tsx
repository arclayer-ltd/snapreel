"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";

/**
 * A block whose pieces animate in the first time it scrolls into view (CSS does the animating, keyed on
 * `data-anim` and `data-in`). Everything is visible in the server markup and without JavaScript; with reduced
 * motion nothing moves.
 */
export function Reveal({
  children,
  className = "",
  style,
  ariaHidden,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
  ariaHidden?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    el.setAttribute("data-anim", "");
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        // A frame later, so the hidden state has painted and the transition runs.
        requestAnimationFrame(() => el.setAttribute("data-in", ""));
        observer.disconnect();
      },
      { rootMargin: "0px 0px -18% 0px" },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} className={className} style={style} aria-hidden={ariaHidden}>
      {children}
    </div>
  );
}
