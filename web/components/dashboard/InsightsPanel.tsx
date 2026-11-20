"use client";

// Views, viewers, how far people watched, where they stopped, where they are. Free sees the counts.
import type { ReactNode } from "react";
import type { Insights, VideoDetail, Viewer } from "@/lib/contract";
import { countryFlag, countryName, formatCount } from "@/lib/client/format";
import { DesktopIcon, EyeIcon, LockIcon, PhoneIcon, TabletIcon, UsersIcon } from "@/components/player/icons";
import { usePlaybackStore } from "@/components/player/playback";
import { Avatar, RelativeTime } from "@/components/player/ui";
import { DropoffChart } from "./DropoffChart";
import { Card, ProBadge } from "./kit";

export function InsightsPanel({ video, insights, pro }: { video: VideoDetail; insights: Insights | null; pro: boolean }) {
  const store = usePlaybackStore();
  const views = insights?.views ?? video.views;
  const unique = insights?.uniqueViewers ?? video.uniqueViewers;
  const locked = !pro || insights?.dropoff == null;

  return (
    <Card title="Insights" id="insights" description={views === 0 ? "Nobody has watched yet. Views count after 5 seconds." : undefined}>
      <dl className="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
        <Stat label="Views" value={formatCount(views)} icon={<EyeIcon size={16} />} />
        <Stat label="Unique viewers" value={formatCount(unique)} icon={<UsersIcon size={16} />} />
        <Stat label="Average watched" value={insights?.avgPercent != null ? `${Math.round(insights.avgPercent)}%` : null} />
        <Stat
          label="Watched to the end"
          value={insights?.completionRate != null ? `${Math.round(insights.completionRate * 100)}%` : null}
        />
      </dl>

      {locked ? (
        views > 0 || !pro ? <UpgradePanel /> : null
      ) : (
        <div className="mt-6 space-y-8">
          {insights!.dropoff && insights!.dropoff.some((n) => n > 0) && (
            <div>
              <h3 className="mb-2 text-[15px] font-semibold">Where people stop watching</h3>
              <DropoffChart dropoff={insights!.dropoff} durationS={video.durationS} onSeek={(t) => store.seek(t, false)} />
            </div>
          )}
          <div className="grid gap-8 md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
            {insights!.countries && insights!.countries.length > 0 && <Countries countries={insights!.countries} />}
            {insights!.viewers && insights!.viewers.length > 0 && <Viewers viewers={insights!.viewers} />}
          </div>
        </div>
      )}
    </Card>
  );
}

function Stat({ label, value, icon }: { label: string; value: string | null; icon?: ReactNode }) {
  return (
    <div className="rounded-2xl bg-fill/70 px-3.5 py-3">
      <dt className="flex items-center gap-1.5 text-[13px] text-text-2">
        {icon}
        {label}
      </dt>
      <dd className="mt-1 text-2xl font-semibold tabular-nums tracking-tight">
        {value ?? (
          <span className="inline-flex items-center gap-1.5 text-base font-medium text-text-3">
            <LockIcon size={15} /> Pro
          </span>
        )}
      </dd>
    </div>
  );
}

function Countries({ countries }: { countries: { code: string; count: number }[] }) {
  const top = [...countries].sort((a, b) => b.count - a.count).slice(0, 6);
  const max = Math.max(1, ...top.map((c) => c.count));
  return (
    <div>
      <h3 className="mb-3 text-[15px] font-semibold">Countries</h3>
      <ul className="space-y-2.5">
        {top.map((c) => (
          <li key={c.code} className="text-sm">
            <div className="flex items-center justify-between gap-2">
              <span className="flex min-w-0 items-center gap-2">
                <span aria-hidden="true">{countryFlag(c.code)}</span>
                <span className="truncate">{countryName(c.code)}</span>
              </span>
              <span className="tabular-nums text-text-2">{formatCount(c.count)}</span>
            </div>
            <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-fill" aria-hidden="true">
              <div className="h-full rounded-full bg-sr-red" style={{ width: `${(c.count / max) * 100}%` }} />
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

function DeviceIcon({ device }: { device: Viewer["device"] }) {
  if (!device) return null;
  const Icon = device === "phone" ? PhoneIcon : device === "tablet" ? TabletIcon : DesktopIcon;
  return (
    <>
      <Icon size={15} className="inline-block align-[-3px]" />
      <span className="sr-only">{device === "desktop" ? "on a computer" : `on a ${device}`}</span>
    </>
  );
}

function Viewers({ viewers }: { viewers: Viewer[] }) {
  const sorted = [...viewers].sort((a, b) => b.lastSeenAt.localeCompare(a.lastSeenAt));
  return (
    <div>
      <h3 className="mb-3 text-[15px] font-semibold">Who watched</h3>
      <ul className="divide-y divide-line">
        {sorted.slice(0, 12).map((v, i) => (
          <li key={`${v.firstSeenAt}-${i}`} className="flex items-center gap-3 py-2.5">
            <Avatar name={v.anonymous ? null : v.name} size={30} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{v.anonymous || !v.name ? "Anonymous" : v.name}</p>
              <p className="flex items-center gap-1.5 text-xs text-text-2">
                <span aria-hidden="true">{countryFlag(v.country)}</span>
                <span className="sr-only">{countryName(v.country)}</span>
                <span className="text-text-3">
                  <DeviceIcon device={v.device} />
                </span>
                <RelativeTime iso={v.lastSeenAt} />
              </p>
            </div>
            <div className="w-20 shrink-0 text-right">
              <p className="text-sm font-semibold tabular-nums">{Math.round(v.percent)}%</p>
              <div className="mt-1 h-1 overflow-hidden rounded-full bg-fill" aria-hidden="true">
                <div className="h-full rounded-full bg-sr-red" style={{ width: `${Math.min(100, v.percent)}%` }} />
              </div>
            </div>
          </li>
        ))}
      </ul>
      {viewers.length > 12 && <p className="mt-2 text-xs text-text-3">And {viewers.length - 12} more.</p>}
    </div>
  );
}

function UpgradePanel() {
  return (
    <div className="relative mt-5 overflow-hidden rounded-2xl border border-line">
      <svg viewBox="0 0 600 160" className="h-36 w-full opacity-60 blur-[3px]" aria-hidden="true" preserveAspectRatio="none">
        <path d="M0,20 C80,24 120,40 200,52 C280,64 320,58 380,86 C440,110 520,118 600,128 L600,160 L0,160 Z" fill="var(--sr-red)" opacity="0.18" />
        <path d="M0,20 C80,24 120,40 200,52 C280,64 320,58 380,86 C440,110 520,118 600,128" fill="none" stroke="var(--sr-red)" strokeWidth="3" />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center bg-surface/70 p-4 text-center backdrop-blur-[1px]">
        <ProBadge />
        <p className="mt-2 max-w-sm text-[15px] font-semibold">See who watched, how far they got and where they stopped</p>
        <p className="mt-1 max-w-sm text-sm text-text-2">Upgrade in the Snapreel app on your iPhone: Settings, then Snapreel Pro.</p>
      </div>
    </div>
  );
}
