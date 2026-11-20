// The thin frame around the watch page: owner branding or the Snapreel mark at the top, the badge and
// report link at the bottom. No "use client": used by both server and client components.
import Image from "next/image";
import type { ReactNode } from "react";
import { SITE_URL } from "@/lib/client/links";
import { SnapreelMark } from "../icons";

export function SnapreelWordmark({ size = 26 }: { size?: number }) {
  return (
    <span className="inline-flex items-center gap-2 text-[17px] font-semibold tracking-tight text-text">
      <SnapreelMark size={size} />
      Snapreel
    </span>
  );
}

export function WatchHeader({
  logoUrl,
  ownerName,
  showBadge,
  actions,
}: {
  logoUrl: string | null;
  ownerName: string | null;
  showBadge: boolean;
  actions?: ReactNode;
}) {
  return (
    <header className="mx-auto flex h-14 w-full max-w-[1400px] items-center gap-3 px-4 lg:h-16 lg:px-6">
      {logoUrl ? (
        <span className="relative block h-8 w-36 overflow-hidden rounded-md dark:bg-white dark:px-2">
          <Image src={logoUrl} alt={ownerName ?? "Logo"} fill unoptimized sizes="144px" className="object-contain object-left dark:px-1.5" />
        </span>
      ) : showBadge ? (
        <a href={SITE_URL} className="rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-sr-red" aria-label="Snapreel home">
          <SnapreelWordmark />
        </a>
      ) : ownerName ? (
        <span className="text-[15px] font-semibold">{ownerName}</span>
      ) : null}
      {actions && <div className="ml-auto flex items-center gap-1">{actions}</div>}
    </header>
  );
}

export function MadeWithSnapreel() {
  return (
    <a
      href={SITE_URL}
      className="inline-flex items-center gap-2 rounded-full border border-line bg-surface py-1.5 pl-1.5 pr-3.5 text-[13px] font-medium text-text-2 shadow-sm transition-colors hover:text-text focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red motion-reduce:transition-none"
    >
      <SnapreelMark size={22} />
      Made with <span className="font-semibold text-text">Snapreel</span>
    </a>
  );
}

export function WatchFooter({ showBadge, children }: { showBadge: boolean; children?: ReactNode }) {
  return (
    <footer className="mx-auto mt-auto flex w-full max-w-[1400px] flex-wrap items-center justify-center gap-x-5 gap-y-3 px-4 pb-8 pt-10 text-[13px] text-text-2 sm:justify-between lg:px-6">
      {showBadge ? <MadeWithSnapreel /> : <span />}
      <div className="flex items-center gap-4">
        {children}
        <a href={`${SITE_URL}/privacy`} className="rounded hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red">
          Privacy
        </a>
        <a href={`${SITE_URL}/terms`} className="rounded hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red">
          Terms
        </a>
      </div>
    </footer>
  );
}
