import type { Transcript } from "@/lib/contract";

// WebVTT captions from the phone's on-device transcript ({locale, segments: [{start, duration, text}]}).

function stamp(seconds: number): string {
  const ms = Math.max(0, Math.round(seconds * 1000));
  const h = Math.floor(ms / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  const s = Math.floor((ms % 60_000) / 1000);
  const f = ms % 1000;
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(h)}:${p(m)}:${p(s)}.${p(f, 3)}`;
}

export function transcriptToVtt(transcript: Transcript): string {
  const lines = ["WEBVTT", ""];
  let n = 0;
  for (const seg of transcript.segments) {
    const text = String(seg.text ?? "")
      .replace(/-->/g, "→")
      .replace(/\r?\n\s*\r?\n/g, "\n")
      .trim();
    const start = Number(seg.start);
    const duration = Number(seg.duration);
    if (!text || !Number.isFinite(start) || !Number.isFinite(duration)) continue;
    n += 1;
    lines.push(String(n), `${stamp(start)} --> ${stamp(start + Math.max(duration, 0.2))}`, text, "");
  }
  return lines.join("\n");
}
