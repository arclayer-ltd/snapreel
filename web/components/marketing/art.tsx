/* Plain <picture>, not next/image: these are pre-sized AVIF/WebP files made by
   scripts/web-compose.py and swapped for Light and Dark with prefers-color-scheme. */
import type { CSSProperties, ReactNode } from "react";
import { art, type ArtSlot } from "./art-manifest";

type Files = { avif1x: string; avif2x: string; webp1x: string; webp2x: string };
type PhoneEntry = {
  alt: string;
  width: number;
  height: number;
  width2x: number;
  light?: Files;
  dark?: Files;
  image?: Files;
};

type Set = { avif: [number, string][]; webp: [number, string][] };
type Crop = { width: number; height: number; light: Set; dark?: Set };
type SceneEntry = {
  kind: "scene";
  alt: string;
  top: { light: string; dark?: string };
  bottom: { light: string; dark?: string };
  wide: Crop;
  mobile?: Crop;
  fg?: { wide: Crop; mobile?: Crop };
};

function srcSet(f: Files, ext: "avif" | "webp", w1: number, w2: number) {
  return ext === "avif" ? `${f.avif1x} ${w1}w, ${f.avif2x} ${w2}w` : `${f.webp1x} ${w1}w, ${f.webp2x} ${w2}w`;
}

/**
 * One phone (or other cut-out) from the art manifest. Slots with a screen have a Light and a
 * Dark composite (the app's real Light or Dark screenshot inside the phone) and follow
 * prefers-color-scheme.
 *
 * `sizes` is the rendered width (as in <img sizes>), so phones fetch the small file and retina
 * desktops the large one.
 */
export function Art({
  slot,
  sizes,
  className = "",
  priority = false,
  alt,
}: {
  slot: ArtSlot;
  sizes: string;
  className?: string;
  priority?: boolean;
  alt?: string;
}) {
  const entry = art[slot] as unknown as PhoneEntry;
  const light = entry.light ?? entry.image;
  if (!light) return null;
  const dark = entry.dark;
  const w1 = entry.width;
  const w2 = entry.width2x;
  return (
    <picture>
      {dark ? <source media="(prefers-color-scheme: dark)" type="image/avif" sizes={sizes} srcSet={srcSet(dark, "avif", w1, w2)} /> : null}
      {dark ? <source media="(prefers-color-scheme: dark)" type="image/webp" sizes={sizes} srcSet={srcSet(dark, "webp", w1, w2)} /> : null}
      <source type="image/avif" sizes={sizes} srcSet={srcSet(light, "avif", w1, w2)} />
      <source type="image/webp" sizes={sizes} srcSet={srcSet(light, "webp", w1, w2)} />
      <img
        src={light.webp1x}
        srcSet={srcSet(light, "webp", w1, w2)}
        sizes={sizes}
        width={entry.width}
        height={entry.height}
        alt={alt ?? entry.alt}
        className={`mk-art ${className}`}
        loading={priority ? "eager" : "lazy"}
        fetchPriority={priority ? "high" : "auto"}
        decoding="async"
        draggable={false}
      />
    </picture>
  );
}

function set(s: Set, ext: "avif" | "webp") {
  return s[ext].map(([w, src]) => `${src} ${w}w`).join(", ");
}

/** Below this width the page shows the phone crop of a scene (matches the CSS breakpoint). */
const NARROW = "(max-width: 1023px)";

function ScenePicture({
  crops,
  alt,
  sizes,
  mobileSizes = "100vw",
  priority,
}: {
  crops: { wide: Crop; mobile?: Crop };
  alt: string;
  sizes: string;
  mobileSizes?: string;
  priority: boolean;
}) {
  const { wide, mobile } = crops;
  const fallback = wide.light.webp[0];
  return (
    <picture>
      {mobile?.dark ? (
        <>
          <source media={`(prefers-color-scheme: dark) and ${NARROW}`} type="image/avif" sizes={mobileSizes} srcSet={set(mobile.dark, "avif")} />
          <source media={`(prefers-color-scheme: dark) and ${NARROW}`} type="image/webp" sizes={mobileSizes} srcSet={set(mobile.dark, "webp")} />
        </>
      ) : null}
      {mobile ? (
        <>
          <source media={NARROW} type="image/avif" sizes={mobileSizes} srcSet={set(mobile.light, "avif")} />
          <source media={NARROW} type="image/webp" sizes={mobileSizes} srcSet={set(mobile.light, "webp")} />
        </>
      ) : null}
      {wide.dark ? (
        <>
          <source media="(prefers-color-scheme: dark)" type="image/avif" sizes={sizes} srcSet={set(wide.dark, "avif")} />
          <source media="(prefers-color-scheme: dark)" type="image/webp" sizes={sizes} srcSet={set(wide.dark, "webp")} />
        </>
      ) : null}
      <source type="image/avif" sizes={sizes} srcSet={set(wide.light, "avif")} />
      <img
        src={fallback[1]}
        srcSet={set(wide.light, "webp")}
        sizes={sizes}
        width={wide.width}
        height={wide.height}
        alt={alt}
        loading={priority ? "eager" : "lazy"}
        fetchPriority={priority ? "high" : "auto"}
        decoding="async"
        draggable={false}
      />
    </picture>
  );
}

export type SceneSlot = { [K in ArtSlot]: (typeof art)[K] extends { kind: "scene" } ? K : never }[ArtSlot];

function sceneEntry(slot: SceneSlot) {
  return art[slot] as unknown as SceneEntry;
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
 * .mk-scene CSS in marketing.css.
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
      <div className="mk-scene-art">
        <ScenePicture crops={{ wide: e.wide, mobile: e.mobile }} alt={alt ?? e.alt} sizes={sizes} priority={priority} />
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
        <ScenePicture crops={{ wide: e.wide }} alt="" sizes={sizes} priority={false} />
      </div>
    </div>
  );
}
