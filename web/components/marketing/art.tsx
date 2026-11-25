/* The illustrated scenes. Plain <picture>, not next/image: these are pre-sized WebP files made by
   scripts/web-compose.py and swapped for Light and Dark with prefers-color-scheme. The iPhones that stand in
   them are drawn by iphone.tsx. */
import type { CSSProperties, ReactNode } from "react";
import { art, type ArtSlot } from "./art-manifest";
import { PictureWarm } from "./picture-warm";

type Set = readonly (readonly [number, string])[];
type Crop = { width: number; height: number; light: Set; dark?: Set; blur?: { light: string; dark?: string } };
type SceneEntry = {
  kind: "scene";
  alt: string;
  top: { light: string; dark?: string };
  bottom: { light: string; dark?: string };
  wide: Crop;
  mobile?: Crop;
  fg?: { wide: Crop; mobile?: Crop };
};

function set(s: Set) {
  return s.map(([w, src]) => `${src} ${w}w`).join(", ");
}

/** Below this width the page shows the phone crop of a scene (matches the CSS breakpoint). */
const NARROW = "(max-width: 1023px)";
const WIDE = "(min-width: 1024px)";
const DARK = "(prefers-color-scheme: dark)";
const LIGHT = "(prefers-color-scheme: light)";

type Source = { media: string; sizes: string; srcSet: string };

/** One entry per combination of theme and crop; exactly one matches, so each can also be a preload. */
function sources({ wide, mobile }: { wide: Crop; mobile?: Crop }, sizes: string, mobileSizes: string): Source[] {
  const pick = (c: Crop, sz: string, width?: string): Source[] => [
    { media: [DARK, width].filter(Boolean).join(" and "), sizes: sz, srcSet: set(c.dark ?? c.light) },
    { media: [LIGHT, width].filter(Boolean).join(" and "), sizes: sz, srcSet: set(c.light) },
  ];
  return mobile ? [...pick(mobile, mobileSizes, NARROW), ...pick(wide, sizes, WIDE)] : pick(wide, sizes);
}

function ScenePicture({
  crops,
  alt,
  sizes,
  mobileSizes = "100vw",
  priority,
  preload = false,
}: {
  crops: { wide: Crop; mobile?: Crop };
  alt: string;
  sizes: string;
  mobileSizes?: string;
  priority: boolean;
  preload?: boolean;
}) {
  const { wide } = crops;
  const all = sources(crops, sizes, mobileSizes);
  return (
    <>
      {preload
        ? all.map((s) => (
            <link
              key={s.media}
              rel="preload"
              as="image"
              type="image/webp"
              media={s.media}
              imageSrcSet={s.srcSet}
              imageSizes={s.sizes}
              fetchPriority="high"
            />
          ))
        : null}
      <picture>
        {all.map((s) => (
          <source key={s.media} type="image/webp" media={s.media} sizes={s.sizes} srcSet={s.srcSet} />
        ))}
        <img
          src={wide.light[0][1]}
          width={wide.width}
          height={wide.height}
          alt={alt}
          loading={priority ? "eager" : "lazy"}
          fetchPriority={priority ? "high" : "auto"}
          decoding="async"
          draggable={false}
        />
      </picture>
    </>
  );
}

export type SceneSlot = { [K in ArtSlot]: (typeof art)[K] extends { kind: "scene" } ? K : never }[ArtSlot];

function sceneEntry(slot: SceneSlot) {
  return art[slot] as unknown as SceneEntry;
}

/** The tiny blurred picture that fills a scene's place until the real one has loaded (.mk-scene-art). */
function blurVars(e: SceneEntry): CSSProperties {
  const url = (u?: string) => (u ? `url(${u})` : undefined);
  const m = e.mobile ?? e.wide;
  return {
    "--lq": url(e.wide.blur?.light),
    "--lq-d": url(e.wide.blur?.dark ?? e.wide.blur?.light),
    "--lq-m": url(m.blur?.light),
    "--lq-md": url(m.blur?.dark ?? m.blur?.light),
  } as CSSProperties;
}

/** CSS custom properties a scene section needs: aspect ratios and the sky colours. */
export function sceneVars(slot: SceneSlot, extra: Record<string, string | number> = {}): CSSProperties {
  const e = sceneEntry(slot);
  const vars: Record<string, string | number> = {
    "--ar": +(e.wide.width / e.wide.height).toFixed(4),
    "--sky": e.top.light,
    "--sky-d": e.top.dark ?? e.top.light,
    ...extra,
  };
  if (e.mobile) vars["--mar"] = +(e.mobile.width / e.mobile.height).toFixed(4);
  return vars as CSSProperties;
}

/**
 * The picture layers of a scene: the environment, an optional phone (or anything else) that
 * stands in it, and the scene's foreground cut-out in front of that. Positioned by the
 * .mk-scene CSS in marketing.css. `priority` is for the scene at the top of a page: its picture is preloaded.
 */
export function SceneStage({
  slot,
  sizes = "100vw",
  priority = false,
  alt,
  children,
}: {
  slot: SceneSlot;
  sizes?: string;
  priority?: boolean;
  alt?: string;
  children?: ReactNode;
}) {
  const e = sceneEntry(slot);
  return (
    <div className="mk-scene-stage">
      <div className="mk-scene-art" style={blurVars(e)}>
        <ScenePicture
          crops={{ wide: e.wide, mobile: e.mobile }}
          alt={alt ?? e.alt}
          sizes={sizes}
          priority={priority}
          preload={priority}
        />
      </div>
      {children ? <div className="mk-scene-phone">{children}</div> : null}
      {e.fg ? (
        <div className="mk-scene-fg" aria-hidden="true">
          <ScenePicture crops={e.fg} alt="" sizes={sizes} priority={priority} />
        </div>
      ) : null}
    </div>
  );
}

/** A small illustration cropped from a scene (guide cards). Decorative: the card's title says it all. */
export function Spot({ slot, sizes, className = "" }: { slot: SceneSlot; sizes: string; className?: string }) {
  const e = sceneEntry(slot);
  return (
    <div className={`relative overflow-hidden ${className}`}>
      <div className="absolute inset-0 [&_img]:h-full [&_img]:w-full [&_img]:object-cover">
        <ScenePicture crops={{ wide: e.wide }} alt="" sizes={sizes} mobileSizes={sizes} priority={false} />
      </div>
    </div>
  );
}

/** Fetches the inner pages' banner (help, support, legal) once the page is idle, or as a link to one of them is
    pointed at, so it is already there on the next page. */
export function BannerWarm() {
  const e = sceneEntry("scene-page");
  return <PictureWarm sources={sources({ wide: e.wide, mobile: e.mobile }, "100vw", "100vw")} />;
}
