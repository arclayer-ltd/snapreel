"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ScreenIcon, UsersIcon } from "@/components/player/icons";

const LINKS = [
  { href: "/app", label: "Videos", Icon: ScreenIcon, match: (p: string) => p === "/app" || p.startsWith("/app/v/") },
  { href: "/app/account", label: "Account", Icon: UsersIcon, match: (p: string) => p.startsWith("/app/account") },
];

/** Reads the URL, so it sits inside <Suspense> (Cache Components). */
export function DashboardNav() {
  return <DashboardNavLinks pathname={usePathname() ?? ""} />;
}

/** The same links with nothing marked current: the prerendered fallback. */
export function DashboardNavLinks({ pathname }: { pathname: string }) {
  return (
    <nav aria-label="Dashboard" className="flex items-center gap-1">
      {LINKS.map((l) => {
        const active = l.match(pathname);
        return (
          <Link
            key={l.href}
            href={l.href}
            aria-current={active ? "page" : undefined}
            className={`inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
              active ? "bg-fill text-text" : "text-text-2 hover:text-text"
            }`}
          >
            {l.label === "Account" && <UsersIcon size={16} className="hidden sm:block" />}
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}

/** The phone's bottom bar. */
export function DashboardTabs() {
  return <DashboardTabBar pathname={usePathname() ?? ""} />;
}

export function DashboardTabBar({ pathname }: { pathname: string }) {
  return (
    <nav
      aria-label="Dashboard"
      className="fixed inset-x-0 bottom-0 z-40 flex border-t border-line bg-canvas/95 px-[env(safe-area-inset-left)] pb-[env(safe-area-inset-bottom)] backdrop-blur-md sm:hidden"
    >
      {LINKS.map(({ href, label, Icon, match }) => {
        const active = match(pathname);
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={`flex h-14 flex-1 flex-col items-center justify-center gap-0.5 text-xs font-semibold focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-sr-red ${
              active ? "text-red-text" : "text-text-2"
            }`}
          >
            <Icon size={22} />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
