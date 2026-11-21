/* The illustrated scenes. Plain <picture>, not next/image: these are pre-sized AVIF/WebP files made by
   scripts/web-compose.py and swapped for Light and Dark with prefers-color-scheme. The iPhones that stand in
   them are drawn by iphone.tsx. */
import type { CSSProperties, ReactNode } from "react";
import { art, type ArtSlot } from "./art-manifest";
import { motion } from "./motion-manifest";
import { SceneMotion } from "./scene-motion";

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
 * .mk-scene CSS in marketing.css. Scenes with motion data (scripts/web-motion.py) get a canvas
 * over the environment that brings its nature to life (scene-motion.tsx).
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
        {slot in motion ? <SceneMotion slot={slot as keyof typeof motion} /> : null}
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
