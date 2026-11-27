"use client";

// The app's six quick reactions plus a picker. A reaction is pinned to the moment being watched, shows beside the
// buttons as it happens (other viewers' too, as playback passes them; never over the picture) and appears on the
// scrubber straight away.
import { useEffect, useId, useRef, useState } from "react";
import type { Reaction } from "@/lib/contract";
import { errorMessage, publicApi } from "@/lib/client/api";
import { formatTime } from "@/lib/client/format";
import { EMOJI_GROUPS, QUICK_EMOJI, QUICK_EMOJI_NAMES } from "../emoji";
import { SmilePlusIcon } from "../icons";
import "../player.css";
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
  const [live, setLive] = useState<{ id: string; emoji: string }[]>([]);
  const [popped, setPopped] = useState<{ emoji: string; key: string } | null>(null);
  const pickerId = useId();
  const wrapRef = useRef<HTMLDivElement>(null);

  // One row, newest on the right, as many as fit: a phone has room for two beside the buttons.
  useEffect(
    () =>
      store.onBurst((emoji) => {
        const room = window.innerWidth < 640 ? 2 : 5;
        setLive((all) => [...all.slice(1 - room), { id: tempId(), emoji }]);
      }),
    [store],
  );

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
    const picker = wrapRef.current?.querySelector<HTMLElement>("[data-picker]");
    picker?.querySelector<HTMLButtonElement>("button")?.focus({ preventScroll: true });
    picker?.scrollIntoView({ block: "nearest" });
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
    setPopped({ emoji, key: id });
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
    <div ref={wrapRef} className="relative flex items-center gap-1">
      <div role="group" aria-label={`React at ${formatTime(second)}`} className="flex min-w-0 flex-1 items-center sm:flex-none">
        {QUICK_EMOJI.map((e) => (
          <button
            key={e}
            type="button"
            onClick={() => react(e)}
            aria-label={`React with ${QUICK_EMOJI_NAMES[e]}`}
            title={QUICK_EMOJI_NAMES[e]}
            className="flex h-11 min-w-0 max-w-11 flex-1 items-center justify-center rounded-full text-[22px] leading-none transition-transform duration-100 hover:bg-fill active:scale-90 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-sr-red motion-reduce:transition-none sm:w-11"
          >
            <span key={popped?.emoji === e ? popped.key : e} className={popped?.emoji === e ? "sr-pop" : undefined}>
              {e}
            </span>
          </button>
        ))}
        <button
          type="button"
          data-picker-toggle
          onClick={() => setOpen((o) => !o)}
          aria-expanded={open}
          aria-controls={pickerId}
          aria-label="More reactions"
          className="flex h-11 min-w-0 max-w-11 flex-1 items-center justify-center rounded-full text-text-2 sm:w-11 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-sr-red"
        >
          <SmilePlusIcon size={21} />
        </button>
      </div>
      <span className="hidden text-[13px] tabular-nums text-text-3 sm:inline" aria-hidden="true">
        at {formatTime(second)}
      </span>
      <div className="flex h-11 w-[58px] shrink-0 items-center justify-end gap-0.5 overflow-hidden pr-1.5 max-[359px]:hidden sm:ml-auto sm:w-40" aria-hidden="true">
        {/* On a phone the moment shows here while nothing is happening. */}
        {live.length === 0 && (
          <span className="truncate text-[13px] tabular-nums text-text-3 sm:hidden">at {formatTime(second)}</span>
        )}
        {live.map((l) => (
          <span
            key={l.id}
            className="sr-live flex w-6 shrink-0 justify-center text-[20px] leading-none"
            onAnimationEnd={() => setLive((all) => all.filter((x) => x.id !== l.id))}
          >
            {l.emoji}
          </span>
        ))}
      </div>
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
          className="absolute left-1.5 top-full z-30 mt-1 max-h-[min(24rem,60svh)] w-[min(22rem,calc(100vw-2rem))] scroll-mb-4 overflow-y-auto overscroll-contain rounded-2xl border border-line bg-surface p-3 shadow-[0_18px_50px_rgb(0_0_0/0.22)]"
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
