/* Your phone. Your files: pieces of the app lifted out of the Library phone's screen, redrawn as liquid glass (the
   panel's own dark translucent cards). Text and icons are the app's own words and shapes; the thumbnail is cut from
   the app's screenshot by scripts/web-lifts.py. Each piece is placed in % of the phone's box (x: left edge, y:
   middle, w: width; from: where it slides in from) and sized in cqw, so the composition scales as one. */
import type { CSSProperties, ReactNode } from "react";
import { Icon } from "./marks";

type Piece = { x: number; y: number; w: number; from: number; label: string; className: string; body: ReactNode };

const pieces: Piece[] = [
  {
    x: -52,
    y: 14,
    w: 62,
    from: 40,
    label: "Saved on this iPhone",
    className: "mk-glass--pill mk-glass-saved",
    body: (
      <>
        <Icon name="lock" />
        Saved on this iPhone
      </>
    ),
  },
  {
    x: 46,
    y: 28,
    w: 96,
    from: -40,
    label: "Notes, Transcript and Comments",
    className: "mk-glass--pill mk-glass-tabs",
    body: (
      <>
        <span>Notes</span>
        <span>Transcript</span>
        <span data-on="">Comments</span>
      </>
    ),
  },
  {
    x: -66,
    y: 64,
    w: 122,
    from: 36,
    label: "A recording in the library: Feedback on the onboarding copy, in the Clients folder",
    className: "mk-glass-row",
    body: (
      <>
        {/* eslint-disable-next-line @next/next/no-img-element -- a small pre-sized crop of the app's screen */}
        <img src="/marketing/lifts/thumb-feedback.webp" width={360} height={202} alt="" loading="lazy" decoding="async" draggable={false} />
        <span className="mk-glass-row-text">
          <b>Feedback on the onboarding copy</b>
          <span>Camera · 5h ago</span>
          <span>
            <Icon name="folder" />
            Clients
          </span>
        </span>
        <span className="mk-glass-dots">
          <i />
          <i />
          <i />
        </span>
      </>
    ),
  },
  {
    x: 30,
    y: 86,
    w: 112,
    from: -36,
    label: "Edit title, Save to Photos and Watch later",
    className: "mk-glass-actions",
    body: (
      <>
        <span>
          <Icon name="pencil" />
          Edit title
        </span>
        <span>
          <Icon name="save" />
          Save to Photos
        </span>
        <span>
          <Icon name="clock" />
          Watch later
        </span>
      </>
    ),
  },
];

export function GlassPieces() {
  return pieces.map((p, i) => (
    <div
      key={p.label}
      role="img"
      aria-label={p.label}
      className={`mk-glass ${p.className}`}
      style={{ "--x": p.x, "--y": p.y, "--w": p.w, "--from": p.from, "--d": `${150 + i * 110}ms` } as CSSProperties}
    >
      {p.body}
    </div>
  ));
}
