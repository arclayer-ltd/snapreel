import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { DashboardNav, DashboardNavLinks } from "@/components/dashboard/DashboardNav";
import { SnapreelWordmark } from "@/components/player/watch/WatchChrome";
import { PREVIEW } from "@/lib/client/preview-data";

export const metadata: Metadata = {
  title: { default: "Your videos", template: "%s · Snapreel" },
  robots: { index: false, follow: false },
};

// The session is read inside each page's <Suspense> boundary, not here, so this frame renders at once.
export default function DashboardLayout({ children }: LayoutProps<"/app">) {
  return (
    <div className="flex min-h-svh flex-col">
      <header className="sticky top-0 z-40 border-b border-line bg-canvas/85 backdrop-blur-md supports-[not(backdrop-filter:blur(0))]:bg-canvas">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-3 px-4 sm:h-16 sm:px-6">
          <Link href="/app" className="rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-sr-red" aria-label="Snapreel dashboard">
            <SnapreelWordmark />
          </Link>
          {PREVIEW && (
            <span className="hidden rounded-full bg-sr-cream px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-sr-ink sm:inline">
              Preview data
            </span>
          )}
          <div className="ml-auto">
            <Suspense fallback={<DashboardNavLinks pathname="" />}>
              <DashboardNav />
            </Suspense>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-20 pt-6 sm:px-6 sm:pt-8">{children}</main>
    </div>
  );
}
