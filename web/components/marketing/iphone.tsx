/* The site's one iPhone: a rendered iPhone 16 Pro frame (scripts/web-device-frame.py, .mk-iphone in
   marketing.css) over a real Snapreel screen. Light pages show the app's Light screenshot and Dark pages the Dark one, swapped
   with prefers-color-scheme. Screens come from scripts/web-screens.py. */
import type { CSSProperties } from "react";
import { FlowVideo } from "./flow-video";
import { SCREEN_SIZE, SCREEN_WIDTHS, screens, type ScreenSlug } from "./screens-manifest";

function srcSet(slug: ScreenSlug, mode: "light" | "dark") {
  return SCREEN_WIDTHS.map((w) => `/marketing/screens/${slug}-${mode}-${w}.webp ${w}w`).join(", ");
}

/**
 * A phone rising out of the bottom edge of a tile (the tile needs overflow: hidden): the bottom `crop` of
 * the phone's height is cut off. `className` sizes it.
 */
export function PeekPhone({
  crop = 0.12,
  className = "",
  ...phone
}: Omit<Parameters<typeof IPhone>[0], "className"> & { crop?: number; className?: string }) {
  return (
    <div className={`mk-peek ${className}`} style={{ "--crop": crop } as CSSProperties}>
      <IPhone {...phone} />
    </div>
  );
}

/**
 * An upright iPhone showing one app screen. It fills its parent's width; size it with the parent or
 * `className`.
 *
 * - `sizes`: the phone's rendered width, as in <img sizes>, so small phones fetch the small screen.
 * - `priority`: load the screen eagerly and first (the hero's phone).
 * - `ground`: a soft contact shadow under the phone, for phones that stand in an illustrated scene.
 * - `flow`: a recorded app flow (scripts/web-flows.py) that plays over the still `screen` while the phone
 *   is on screen; `screen` should be that flow's own still.
 */
export function IPhone({
  screen,
  sizes,
  priority = false,
  ground = false,
  flow,
  alt,
  className = "",
  style,
}: {
  screen: ScreenSlug;
  flow?: "share" | "comments" | "camera" | "voice" | "screen";
  sizes: string;
  priority?: boolean;
  ground?: boolean;
  alt?: string;
  className?: string;
  style?: CSSProperties;
}) {
  const s = screens[screen];
  const vars = { "--scr-l": s.bg.light, "--scr-d": s.bg.dark, ...style } as CSSProperties;
  return (
    <div className={`mk-iphone ${ground ? "mk-iphone--ground" : ""} ${className}`} style={vars}>
      <span className="mk-iphone-shadow" aria-hidden="true" />
      <div className="mk-iphone-screen">
        <picture>
          <source media="(prefers-color-scheme: dark)" type="image/webp" sizes={sizes} srcSet={srcSet(screen, "dark")} />
          <img
            src={`/marketing/screens/${screen}-light-${SCREEN_WIDTHS[0]}.webp`}
            srcSet={srcSet(screen, "light")}
            sizes={sizes}
            width={SCREEN_SIZE.width}
            height={SCREEN_SIZE.height}
            alt={alt ?? s.alt}
            loading={priority ? "eager" : "lazy"}
            fetchPriority={priority ? "high" : "auto"}
            decoding={priority ? "sync" : "async"}
            draggable={false}
          />
        </picture>
        {flow ? (
          <FlowVideo light={`/marketing/flows/${flow}-light.mp4`} dark={`/marketing/flows/${flow}-dark.mp4`} priority={priority} />
        ) : null}
        <span className="mk-iphone-glass" aria-hidden="true" />
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element -- a pre-sized frame overlay; next/image adds nothing */}
      <img
        className="mk-iphone-frame"
        src="/marketing/iphone-frame-600.webp"
        srcSet="/marketing/iphone-frame-600.webp 600w, /marketing/iphone-frame-1200.webp 1200w"
        sizes={sizes}
        width={1900}
        height={3782}
        alt=""
        aria-hidden="true"
        loading={priority ? "eager" : "lazy"}
        decoding="async"
        draggable={false}
      />
    </div>
  );
}
