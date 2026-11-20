"use client";

import Link from "next/link";
import { useId, useMemo, useState } from "react";

type Item = { id: string; title: string; summary: string; category: string };

/** Filters the help articles as you type, showing matches under the box (inside the red panel, which
 *  grows to fit). The full list is server-rendered below it. */
export function HelpSearch({ items }: { items: Item[] }) {
  const [q, setQ] = useState("");
  const id = useId();
  const results = useMemo(() => {
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return items
      .filter((it) => {
        const hay = `${it.title} ${it.summary} ${it.category}`.toLowerCase();
        return words.every((w) => hay.includes(w));
      })
      .slice(0, 8);
  }, [q, items]);

  return (
    <div className="relative">
      <label htmlFor={id} className="sr-only">
        Search help
      </label>
      <div className="flex h-14 items-center gap-3 rounded-full bg-white px-5 text-sr-ink shadow-[0_8px_30px_rgb(94_11_22/0.25)]">
        <svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        </svg>
        <input
          id={id}
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search help, like “screen recording”"
          className="h-full w-full bg-transparent text-base text-sr-ink outline-none placeholder:text-[#5b5e6b]"
          autoComplete="off"
        />
      </div>
      {q.trim() ? (
        <div className="mt-2 overflow-hidden rounded-3xl bg-surface text-text shadow-2xl ring-1 ring-line" role="region" aria-label="Search results" aria-live="polite">
          {results.length ? (
            <ul>
              {results.map((r) => (
                <li key={r.id} className="border-b border-line last:border-0">
                  <Link href={`/help/${r.id}`} className="block px-5 py-3.5 hover:bg-fill">
                    <span className="block font-semibold">{r.title}</span>
                    <span className="block text-sm text-text-2">{r.summary}</span>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p className="px-5 py-4 text-text-2">
              Nothing matches. Try another word, or write to{" "}
              <a className="text-red-text underline" href="mailto:support@snapreel.video">
                support@snapreel.video
              </a>
              .
            </p>
          )}
        </div>
      ) : null}
    </div>
  );
}
