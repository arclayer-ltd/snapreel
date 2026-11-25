import type { ReactNode } from "react";
import { SceneStage, sceneVars } from "./art";

/**
 * The top of an inner page: the skyline panorama under the floating nav bar.
 *
 * - `variant="hero"` (help centre, support): the title, intro and anything passed as children
 *   sit on the sky.
 * - `variant="strip"` (help articles, legal pages): a short strip of the panorama; the page puts
 *   its title in a card that overlaps the strip's bottom edge.
 */
export function PageBanner({
  variant,
  label,
  title,
  titleId,
  intro,
  children,
}: {
  variant: "hero" | "strip";
  label?: string;
  title?: ReactNode;
  titleId?: string;
  intro?: ReactNode;
  children?: ReactNode;
}) {
  if (variant === "strip") {
    return (
      <div className="mk-scene mk-scene--cover mk-scene--top" style={sceneVars("scene-page", { "--h": "clamp(300px, 30vw, 440px)", "--tuck": "0px" })}>
        <div className="mk-scene-content h-[76px] lg:h-0" />
        <SceneStage slot="scene-page" priority sizes="max(100vw, 800px)" />
      </div>
    );
  }
  return (
    <section
      aria-labelledby={titleId}
      className="mk-scene mk-scene--flow mk-scene--top"
      style={sceneVars("scene-page", { "--tuck": "28px", "--tuck-d": "calc(24.9vw - 20px)" })}
    >
      <div className="mk-scene-content mx-auto max-w-3xl px-[var(--mk-gutter)] pt-28 text-center sm:pt-32">
        {label ? <p className="mk-label">{label}</p> : null}
        <h1 id={titleId} className="mk-title mt-4 text-[2.625rem] sm:text-[3.5rem]">
          {title}
        </h1>
        {intro ? <p className="mx-auto mt-4 max-w-xl text-lg leading-relaxed text-[var(--mk-sky-ink-2)]">{intro}</p> : null}
        {children ? <div className="mx-auto mt-7 max-w-xl">{children}</div> : null}
      </div>
      <SceneStage slot="scene-page" priority sizes="100vw" />
    </section>
  );
}
