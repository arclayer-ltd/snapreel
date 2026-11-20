/* The site's one iPhone: an iPhone 16 Pro drawn in CSS (.mk-iphone in marketing.css) with a real Snapreel
   screenshot on its glass. Light pages show the app's Light screenshot and Dark pages the Dark one, swapped
   with prefers-color-scheme. Screens come from scripts/web-screens.py. */
import type { CSSProperties } from "react";
import { SCREEN_SIZE, SCREEN_WIDTHS, screens, type ScreenSlug } from "./screens-manifest";

function srcSet(slug: ScreenSlug, mode: "light" | "dark", ext: "avif" | "webp") {
  return SCREEN_WIDTHS.map((w) => `/marketing/screens/${slug}-${mode}-${w}.${ext} ${w}w`).join(", ");
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
 */
export function IPhone({
  screen,
  sizes,
  priority = false,
  ground = false,
  alt,
  className = "",
  style,
}: {
  screen: ScreenSlug;
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
      <span className="mk-iphone-key mk-iphone-key--action" aria-hidden="true" />
      <span className="mk-iphone-key mk-iphone-key--up" aria-hidden="true" />
      <span className="mk-iphone-key mk-iphone-key--down" aria-hidden="true" />
      <span className="mk-iphone-key mk-iphone-key--side" aria-hidden="true" />
      <span className="mk-iphone-key mk-iphone-key--camera" aria-hidden="true" />
      <div className="mk-iphone-body">
        <div className="mk-iphone-screen">
          <picture>
            <source media="(prefers-color-scheme: dark)" type="image/avif" sizes={sizes} srcSet={srcSet(screen, "dark", "avif")} />
            <source media="(prefers-color-scheme: dark)" type="image/webp" sizes={sizes} srcSet={srcSet(screen, "dark", "webp")} />
            <source type="image/avif" sizes={sizes} srcSet={srcSet(screen, "light", "avif")} />
            <img
              src={`/marketing/screens/${screen}-light-${SCREEN_WIDTHS[0]}.webp`}
              srcSet={srcSet(screen, "light", "webp")}
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
          <span className="mk-iphone-island" aria-hidden="true" />
          <span className="mk-iphone-glass" aria-hidden="true" />
        </div>
      </div>
    </div>
  );
}
