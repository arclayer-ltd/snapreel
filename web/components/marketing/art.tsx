/* Plain <picture>, not next/image: these are pre-sized AVIF/WebP pairs made by
   scripts/web-compose.py and swapped for Light and Dark with prefers-color-scheme. */
import { art, type ArtSlot } from "./art-manifest";

type Files = { avif1x: string; avif2x: string; webp1x: string; webp2x: string };
type Entry = {
  alt: string;
  width: number;
  height: number;
  width2x: number;
  light?: Files;
  dark?: Files;
  image?: Files;
};

function srcSet(f: Files, ext: "avif" | "webp", w1: number, w2: number) {
  return ext === "avif" ? `${f.avif1x} ${w1}w, ${f.avif2x} ${w2}w` : `${f.webp1x} ${w1}w, ${f.webp2x} ${w2}w`;
}

/**
 * One piece of website art. Slots with a phone screen have a Light and a Dark composite (the app's
 * real Light or Dark screenshot inside the phone) and follow prefers-color-scheme.
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
  const entry = art[slot] as unknown as Entry;
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
