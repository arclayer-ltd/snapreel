"use client";

// The on-device transcript: tap a line to play from there; the line being spoken is highlighted and
// kept in view (inside the panel only, never by scrolling the page).
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Transcript } from "@/lib/contract";
import { formatTime, spokenTime } from "@/lib/client/format";
import { CloseIcon, SearchIcon } from "../icons";
import { usePlayback } from "../playback";

function highlight(text: string, query: string): ReactNode {
  if (!query) return text;
  const i = text.toLowerCase().indexOf(query.toLowerCase());
  if (i < 0) return text;
  return (
    <>
      {text.slice(0, i)}
      <mark className="rounded bg-sr-cream px-0.5 text-sr-ink">{text.slice(i, i + query.length)}</mark>
      {text.slice(i + query.length)}
    </>
  );
}

export function TranscriptList({ transcript, onSeek }: { transcript: Transcript; onSeek?: (t: number) => void }) {
  const { time, started } = usePlayback();
  const [query, setQuery] = useState("");
  const listRef = useRef<HTMLOListElement>(null);
  const userScrolledAt = useRef(0);

  const segments = transcript.segments;
  // Highlight once playback has started or the viewer has moved the playhead.
  const active = started || time > 0
    ? segments.findIndex((s, i) => time >= s.start && (time < s.start + s.duration || (i < segments.length - 1 && time < segments[i + 1].start)))
    : -1;

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return segments.map((s, i) => ({ s, i })).filter(({ s }) => !q || s.text.toLowerCase().includes(q));
  }, [segments, query]);

  useEffect(() => {
    const list = listRef.current;
    if (!list || active < 0 || query) return;
    if (list.scrollHeight <= list.clientHeight + 4) return;
    if (Date.now() - userScrolledAt.current < 4000) return;
    const el = list.querySelector<HTMLElement>(`[data-index="${active}"]`);
    if (!el) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const top = el.offsetTop - list.clientHeight / 3;
    list.scrollTo({ top, behavior: reduce ? "auto" : "smooth" });
  }, [active, query]);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="border-b border-line p-3">
        <label className="flex h-10 items-center gap-2 rounded-xl bg-fill px-3 text-text-2 focus-within:ring-2 focus-within:ring-sr-red/30">
          <SearchIcon size={17} />
          <span className="sr-only">Search the transcript</span>
          <input
            type="search"
            enterKeyHint="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search the transcript"
            className="sr-search h-full min-w-0 flex-1 bg-transparent text-base text-text placeholder:text-text-3 focus:outline-none"
          />
          {query && (
            <button
              type="button"
              onClick={() => setQuery("")}
              aria-label="Clear the search"
              className="-mr-2 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-text-2 hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
            >
              <CloseIcon size={16} />
            </button>
          )}
        </label>
      </div>
      <ol
        ref={listRef}
        onWheel={() => (userScrolledAt.current = Date.now())}
        onTouchMove={() => (userScrolledAt.current = Date.now())}
        className="relative max-h-[50svh] min-h-0 flex-1 overflow-y-auto p-2 lg:max-h-none"
      >
        {shown.length === 0 && <li className="p-4 text-sm text-text-2">Nothing in the transcript matches “{query}”.</li>}
        {shown.map(({ s, i }) => {
          const current = i === active;
          return (
            <li key={i} data-index={i}>
              {onSeek ? (
                <button
                  type="button"
                  onClick={() => onSeek(s.start)}
                  aria-current={current ? "true" : undefined}
                  aria-label={`${spokenTime(s.start)}: ${s.text}`}
                  className={`flex w-full gap-3 rounded-xl px-2.5 py-2 text-left transition-colors focus-visible:outline-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
                  current ? "bg-red-soft" : "hover:bg-fill"
                }`}
                >
                <span
                  className={`w-10 shrink-0 pt-px text-[13px] font-semibold tabular-nums ${current ? "text-red-text" : "text-text-3"}`}
                >
                  {formatTime(s.start)}
                </span>
                <span className={`text-[15px] leading-relaxed ${current ? "text-text" : "text-text-2"}`}>
                  {highlight(s.text, query.trim())}
                </span>
                </button>
              ) : (
                <div className="flex w-full gap-3 px-2.5 py-2">
                <span
                  className={`w-10 shrink-0 pt-px text-[13px] font-semibold tabular-nums ${current ? "text-red-text" : "text-text-3"}`}
                >
                  {formatTime(s.start)}
                </span>
                <span className={`text-[15px] leading-relaxed ${current ? "text-text" : "text-text-2"}`}>
                  {highlight(s.text, query.trim())}
                </span>
                </div>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
