"use client";

// The app's six quick reactions plus a picker. A reaction is pinned to the moment being watched,
// floats up over the picture, and appears on the scrubber straight away.
import { useEffect, useId, useRef, useState } from "react";
import type { Reaction } from "@/lib/contract";
import { errorMessage, publicApi } from "@/lib/client/api";
import { formatTime } from "@/lib/client/format";
import { EMOJI_GROUPS, QUICK_EMOJI, QUICK_EMOJI_NAMES } from "../emoji";
import { SmilePlusIcon } from "../icons";
import { usePlaybackSecond, usePlaybackStore } from "../playback";
import { readViewerName } from "./viewerName";

let tempCounter = 0;
/** A local id for a reaction until the server answers with the real one. */
function tempId(): string {
  tempCounter += 1;
  return `temp-${tempCounter}`;
}

export function ReactionBar({
  slug,
  onAdd,
  onSettle,
}: {
  slug: string;
  onAdd: (r: Reaction) => void;
  onSettle: (tempId: string, real: Reaction | null) => void;
}) {
  const store = usePlaybackStore();
  const second = usePlaybackSecond();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pickerId = useId();
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (!wrapRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        wrapRef.current?.querySelector<HTMLButtonElement>("[data-picker-toggle]")?.focus();
      }
    };
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    wrapRef.current?.querySelector<HTMLButtonElement>(`[data-picker] button`)?.focus();
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  useEffect(() => {
    if (!error) return;
    const id = window.setTimeout(() => setError(null), 4000);
    return () => window.clearTimeout(id);
  }, [error]);

  async function react(emoji: string) {
    setOpen(false);
    const atS = Math.round(store.getSnapshot().time * 10) / 10;
    const name = readViewerName() || null;
    const id = tempId();
    store.burst(emoji);
    onAdd({ id, emoji, atS, authorName: name, createdAt: new Date().toISOString() });
    try {
      const real = await publicApi.react(slug, { emoji, atS, name });
      onSettle(id, real);
    } catch (err) {
      onSettle(id, null);
      setError(errorMessage(err, "That reaction didn't go through. Try again."));
    }
  }

  return (
    <div ref={wrapRef} className="relative flex items-center gap-2">
      <div role="group" aria-label={`React at ${formatTime(second)}`} className="flex items-center">
        {QUICK_EMOJI.map((e) => (
          <button
            key={e}
            type="button"
            onClick={() => react(e)}
            aria-label={`React with ${QUICK_EMOJI_NAMES[e]}`}
            title={QUICK_EMOJI_NAMES[e]}
            className="flex h-10 w-10 items-center justify-center rounded-full text-[22px] leading-none transition-transform duration-100 hover:bg-fill active:scale-90 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-sr-red motion-reduce:transition-none"
          >
            {e}
          </button>
        ))}
        <button
          type="button"
          data-picker-toggle
          onClick={() => setOpen((o) => !o)}
          aria-expanded={open}
          aria-controls={pickerId}
          aria-label="More reactions"
          className="flex h-10 w-10 items-center justify-center rounded-full text-text-2 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-sr-red"
        >
          <SmilePlusIcon size={21} />
        </button>
      </div>
      <span className="hidden text-[13px] tabular-nums text-text-3 sm:inline" aria-hidden="true">
        at {formatTime(second)}
      </span>
      {error && (
        <p role="alert" className="absolute left-0 top-full z-20 mt-1 rounded-lg bg-surface px-3 py-2 text-sm text-red-text shadow-lg ring-1 ring-line">
          {error}
        </p>
      )}
      {open && (
        <div
          id={pickerId}
          data-picker
          role="dialog"
          aria-label="Pick a reaction"
          className="absolute left-0 top-full z-30 mt-2 w-[min(22rem,calc(100vw-2rem))] rounded-2xl border border-line bg-surface p-3 shadow-[0_18px_50px_rgb(0_0_0/0.22)]"
        >
          {EMOJI_GROUPS.map((g) => (
            <div key={g.name} className="mb-2 last:mb-0">
              <p className="mb-1 px-1 text-xs font-medium text-text-2">{g.name}</p>
              <div className="grid grid-cols-8 gap-0.5">
                {g.items.map(([emoji, name]) => (
                  <button
                    key={emoji}
                    type="button"
                    onClick={() => react(emoji)}
                    aria-label={name}
                    title={name}
                    className="flex aspect-square items-center justify-center rounded-lg text-[22px] leading-none hover:bg-fill focus-visible:outline-2 focus-visible:outline-sr-red"
                  >
                    {emoji}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
