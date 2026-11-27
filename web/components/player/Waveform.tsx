"use client";

// Audio-only recordings: a speech-like waveform drawn from the title (so it's stable), lit up to the
// playhead and gently moving while it plays. No Web Audio, so it never mutes cross-origin audio.
import { useMemo } from "react";
import "./player.css";

function seeded(seed: string) {
  let h = 2166136261;
  for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  return () => {
    h = Math.imul(h ^ (h >>> 15), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  };
}

export function Waveform({
  seed,
  progress,
  playing,
  bars = 56,
}: {
  seed: string;
  progress: number;
  playing: boolean;
  bars?: number;
}) {
  const heights = useMemo(() => {
    const rand = seeded(seed);
    return Array.from({ length: bars }, (_, i) => {
      const syllable = 0.35 + 0.65 * Math.abs(Math.sin(i * 0.55 + rand() * 1.4));
      const envelope = 0.55 + 0.45 * Math.sin((i / bars) * Math.PI);
      return Math.max(0.12, Math.min(1, syllable * envelope * (0.75 + rand() * 0.35)));
    });
  }, [seed, bars]);

  const lit = Math.round(progress * bars);

  return (
    <div className="flex h-full w-full items-center justify-center gap-[3px] sm:gap-1" aria-hidden="true">
      {heights.map((h, i) => {
        const played = i < lit;
        const near = Math.abs(i - lit) < 10;
        return (
          <span
            key={i}
            className={`sr-wave-bar ${playing && near ? "sr-wave-live" : ""} block w-[3px] rounded-full sm:w-1`}
            style={{
              height: `${h * 100}%`,
              backgroundColor: played ? "var(--accent, #f04850)" : "rgb(255 255 255 / 0.28)",
              animationDelay: `${(i % 7) * -130}ms`,
            }}
          />
        );
      })}
    </div>
  );
}
