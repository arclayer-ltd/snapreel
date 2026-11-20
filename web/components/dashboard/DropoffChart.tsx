"use client";

// Where people stop watching: the share of viewers still watching at each 1% of the video.
import { useId, useMemo, useRef, useState } from "react";
import { formatTime } from "@/lib/client/format";

const W = 600;
const H = 200;
const PAD = { top: 12, right: 8, bottom: 26, left: 36 };

export function DropoffChart({
  dropoff,
  durationS,
  onSeek,
}: {
  dropoff: number[];
  durationS: number;
  onSeek?: (t: number) => void;
}) {
  const gradientId = `dropoff-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const svgRef = useRef<SVGSVGElement>(null);
  const [hover, setHover] = useState<number | null>(null);

  const values = useMemo(() => {
    const top = Math.max(1, ...dropoff);
    return dropoff.map((n) => n / top);
  }, [dropoff]);

  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;
  const x = (i: number) => PAD.left + (i / Math.max(1, values.length - 1)) * innerW;
  const y = (v: number) => PAD.top + (1 - v) * innerH;

  const line = values.map((v, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");
  const area = `${line} L${x(values.length - 1).toFixed(1)},${y(0)} L${x(0)},${y(0)} Z`;

  const halfIndex = values.findIndex((v) => v < 0.5);
  const endShare = Math.round((values[values.length - 1] ?? 0) * 100);
  const summary =
    halfIndex < 0
      ? `Most viewers stayed: ${endShare}% reached the end.`
      : `Half had stopped by ${formatTime((halfIndex / 100) * durationS)}, and ${endShare}% reached the end.`;

  const indexAt = (clientX: number) => {
    const rect = svgRef.current!.getBoundingClientRect();
    const sx = ((clientX - rect.left) / rect.width) * W;
    return Math.max(0, Math.min(values.length - 1, Math.round(((sx - PAD.left) / innerW) * (values.length - 1))));
  };

  return (
    <figure>
      <div className="relative">
        <svg
          ref={svgRef}
          viewBox={`0 0 ${W} ${H}`}
          className="h-auto w-full touch-none select-none"
          role="img"
          aria-label={`Drop-off chart. ${summary}`}
          onPointerMove={(e) => setHover(indexAt(e.clientX))}
          onPointerDown={(e) => setHover(indexAt(e.clientX))}
          onPointerLeave={() => setHover(null)}
          onClick={(e) => onSeek?.((indexAt(e.clientX) / 100) * durationS)}
        >
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="var(--sr-red)" stopOpacity="0.32" />
              <stop offset="1" stopColor="var(--sr-red)" stopOpacity="0.02" />
            </linearGradient>
          </defs>
          {[0, 0.5, 1].map((g) => (
            <g key={g}>
              <line x1={PAD.left} x2={W - PAD.right} y1={y(g)} y2={y(g)} stroke="var(--sr-line)" strokeDasharray={g === 0 ? undefined : "3 4"} />
              <text x={PAD.left - 8} y={y(g) + 4} textAnchor="end" fontSize="11" fill="var(--sr-text-3)">
                {Math.round(g * 100)}%
              </text>
            </g>
          ))}
          <path d={area} fill={`url(#${gradientId})`} />
          <path d={line} fill="none" stroke="var(--sr-red)" strokeWidth="2.25" strokeLinejoin="round" />
          <text x={PAD.left} y={H - 6} fontSize="11" fill="var(--sr-text-3)">
            0:00
          </text>
          <text x={PAD.left + innerW / 2} y={H - 6} textAnchor="middle" fontSize="11" fill="var(--sr-text-3)">
            {formatTime(durationS / 2)}
          </text>
          <text x={W - PAD.right} y={H - 6} textAnchor="end" fontSize="11" fill="var(--sr-text-3)">
            {formatTime(durationS)}
          </text>
          {hover !== null && (
            <g>
              <line x1={x(hover)} x2={x(hover)} y1={PAD.top} y2={y(0)} stroke="var(--sr-text-3)" strokeWidth="1" />
              <circle cx={x(hover)} cy={y(values[hover])} r="4.5" fill="var(--sr-surface)" stroke="var(--sr-red)" strokeWidth="2.25" />
            </g>
          )}
        </svg>
        {hover !== null && (
          <div
            className="pointer-events-none absolute top-0 -translate-x-1/2 whitespace-nowrap rounded-lg bg-sr-ink px-2 py-1 text-xs font-medium text-white shadow-lg dark:bg-white dark:text-sr-ink"
            style={{ left: `${(x(hover) / W) * 100}%` }}
          >
            <span className="tabular-nums">{formatTime((hover / 100) * durationS)}</span> · {Math.round(values[hover] * 100)}% still watching
          </div>
        )}
      </div>
      <figcaption className="mt-2 text-sm text-text-2">{summary}</figcaption>
    </figure>
  );
}
