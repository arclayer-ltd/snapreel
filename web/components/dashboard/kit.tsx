"use client";

// Dashboard building blocks: cards, switches, Pro locks.
import type { ReactNode } from "react";
import { isPast } from "@/lib/client/format";
import { LockIcon, SparkIcon } from "@/components/player/icons";

export function Card({
  title,
  description,
  action,
  children,
  className = "",
  id,
}: {
  title?: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <section id={id} className={`rounded-3xl border border-line bg-surface p-4 sm:p-6 ${className}`} aria-labelledby={id && title ? `${id}-title` : undefined}>
      {(title || action) && (
        <header className="mb-4 flex items-start justify-between gap-3">
          <div>
            {title && (
              <h2 id={id ? `${id}-title` : undefined} className="text-[17px] font-semibold tracking-tight">
                {title}
              </h2>
            )}
            {description && <p className="mt-1 text-sm text-text-2">{description}</p>}
          </div>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

export function ProBadge({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full bg-sr-ink px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-white dark:bg-sr-cream dark:text-sr-ink ${className}`}
    >
      <SparkIcon size={11} />
      Pro
    </span>
  );
}

export function LockedHint({ children }: { children?: ReactNode }) {
  return (
    <p className="flex items-start gap-2 rounded-2xl bg-fill px-3.5 py-3 text-sm leading-relaxed text-text-2">
      <LockIcon size={16} className="mt-0.5 shrink-0" />
      <span>{children ?? "Part of Snapreel Pro. Upgrade in the Snapreel app on your iPhone."}</span>
    </p>
  );
}

export function Switch({
  checked,
  onChange,
  disabled,
  label,
  id,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  label: string;
  id?: string;
}) {
  return (
    <button
      id={id}
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-[30px] w-[50px] shrink-0 items-center rounded-full transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red disabled:cursor-not-allowed disabled:opacity-50 motion-reduce:transition-none ${
        checked ? "bg-sr-red-deep" : "bg-line"
      }`}
    >
      <span
        className={`inline-block h-[26px] w-[26px] rounded-full bg-white shadow-[0_2px_6px_rgb(0_0_0/0.2)] transition-transform duration-150 motion-reduce:transition-none ${
          checked ? "translate-x-[22px]" : "translate-x-[2px]"
        }`}
      />
    </button>
  );
}

export function SwitchRow({
  title,
  description,
  checked,
  onChange,
  disabled,
  pro,
}: {
  title: string;
  description?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  pro?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-3">
      <div className="min-w-0">
        <p className="flex items-center gap-2 font-medium">
          {title}
          {pro && <ProBadge />}
        </p>
        {description && <p className="mt-0.5 text-sm text-text-2">{description}</p>}
      </div>
      <Switch checked={checked} onChange={onChange} disabled={disabled} label={title} />
    </div>
  );
}

export const inputClass =
  "block h-11 w-full rounded-xl border border-line bg-canvas px-3 text-base placeholder:text-text-3 focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25 disabled:cursor-not-allowed disabled:opacity-60";

export type LinkState = "ready" | "uploading" | "failed" | "expired";

/** What the owner needs to know about a link at a glance. */
export function linkState(v: { status: "ready" | "uploading" | "failed"; expiresAt: string | null }): LinkState {
  if (v.status !== "ready") return v.status;
  return v.expiresAt && isPast(v.expiresAt) ? "expired" : "ready";
}

export function StatusDot({ status }: { status: LinkState }) {
  const colour =
    status === "ready" ? "bg-[#1f9d63]" : status === "uploading" ? "bg-[#e0a100]" : status === "expired" ? "bg-text-3" : "bg-sr-red";
  return <span aria-hidden="true" className={`inline-block h-2 w-2 shrink-0 rounded-full ${colour}`} />;
}

export function statusLabel(status: LinkState): string {
  return status === "ready" ? "Live" : status === "uploading" ? "Uploading" : status === "expired" ? "Expired" : "Upload failed";
}
