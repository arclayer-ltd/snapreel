"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UsersIcon } from "@/components/player/icons";

const LINKS = [
  { href: "/app", label: "Videos", match: (p: string) => p === "/app" || p.startsWith("/app/v/") },
  { href: "/app/account", label: "Account", match: (p: string) => p.startsWith("/app/account") },
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
