import type { CSSProperties } from "react";

/** The reference's white marks, redrawn as small SVGs: four-point sparkles, hand-drawn motion
 *  strokes and loose loops. All are decorative (aria-hidden) and positioned by the caller. */

type Pos = {
  top?: string;
  left?: string;
  right?: string;
  bottom?: string;
};

export function Sparkle({
  size = 28,
  twinkle = true,
  delay = 0,
  className = "",
  style,
  ...pos
}: Pos & { size?: number; twinkle?: boolean; delay?: number; className?: string; style?: CSSProperties }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      className={`mk-sparkle ${twinkle ? "mk-sparkle--twinkle" : ""} ${className}`}
      style={{ ...pos, ...({ "--mk-delay": `${delay}s` } as CSSProperties), ...style }}
    >
      <path
        fill="currentColor"
        d="M12 0c.7 6.4 4.9 10.9 12 12-7.1 1.1-11.3 5.6-12 12-.7-6.4-4.9-10.9-12-12C7.1 10.9 11.3 6.4 12 0Z"
      />
    </svg>
  );
}

/** Two or three short strokes that say "this is moving", as next to the reference's heads. */
export function MotionStrokes({
  size = 56,
  rotate = 0,
  count = 3,
  className = "",
  ...pos
}: Pos & { size?: number; rotate?: number; count?: 2 | 3; className?: string }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 56 56"
      width={size}
      height={size}
      className={`mk-strokes ${className}`}
      style={{ ...pos, transform: `rotate(${rotate}deg)` }}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
    >
      <path d="M8 30c1.6-6.8 3.9-12.6 7.2-17.4" strokeWidth="3.2" />
      <path d="M22 26.5c3.9-7.6 8.6-13.4 14.6-17.5" strokeWidth="2.6" />
      {count === 3 ? <path d="M33 33.5c5.4-3.4 10.6-5.3 15.8-5.9" strokeWidth="2.2" /> : null}
    </svg>
  );
}

/** A loose hand-drawn loop, like the ones wrapped around arms and phones in the reference. */
export function Loop({
  width = 160,
  rotate = -8,
  className = "",
  opacity = 0.9,
  ...pos
}: Pos & { width?: number; rotate?: number; className?: string; opacity?: number }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 160 64"
      width={width}
      height={(width * 64) / 160}
      className={`mk-loop ${className}`}
      style={{ ...pos, transform: `rotate(${rotate}deg)`, opacity }}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
    >
      <path
        d="M24 40c-14-6-14-20 10-27C64 4 118 6 140 18c18 10 10 26-22 33-34 7-76 5-96-4-9-4-9-10-1-14"
        strokeWidth="2.6"
      />
    </svg>
  );
}

/** The record-button mark from the app icon. */
export function LogoMark({ size = 28, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 32 32" width={size} height={size} className={className}>
      <circle cx="16" cy="16" r="13" fill="none" stroke="var(--sr-red)" strokeWidth="3.4" />
      <circle cx="16" cy="16" r="6.4" fill="var(--sr-red)" />
    </svg>
  );
}

export function ArrowRight({ size = 20 }: { size?: number }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12h15M13 6l6 6-6 6" />
    </svg>
  );
}

export function Check({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} className={className} fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="m5 12.5 4.5 4.5L19 7.5" />
    </svg>
  );
}
