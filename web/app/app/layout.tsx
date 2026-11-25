import type { Metadata, Viewport } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { DashboardNav, DashboardNavLinks, DashboardTabBar, DashboardTabs } from "@/components/dashboard/DashboardNav";
import { PagePaint, appViewport } from "@/components/player/page-paint";
import { SnapreelWordmark } from "@/components/player/watch/WatchChrome";
import { PREVIEW } from "@/lib/client/preview-data";

export const viewport: Viewport = appViewport;

export const metadata: Metadata = {
  title: { default: "Your videos", template: "%s · Snapreel" },
  robots: { index: false, follow: false },
};

// The session is read inside each page's <Suspense> boundary, not here, so this frame renders at once.
export default function DashboardLayout({ children }: LayoutProps<"/app">) {
  return (
    <div className="sr-safe-x flex min-h-svh flex-col">
      <PagePaint />
      <header className="sticky top-0 z-40 border-b border-line bg-canvas/85 backdrop-blur-md supports-[not(backdrop-filter:blur(0))]:bg-canvas">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-3 px-4 sm:h-16 sm:px-6">
          <Link href="/app" className="flex min-h-11 items-center rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-sr-red" aria-label="Snapreel dashboard">
            <SnapreelWordmark />
          </Link>
          {PREVIEW && (
            <span className="hidden rounded-full bg-sr-cream px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-sr-ink sm:inline">
              Preview data
            </span>
          )}
          <div className="ml-auto max-sm:hidden">
            <Suspense fallback={<DashboardNavLinks pathname="" />}>
              <DashboardNav />
            </Suspense>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-28 pt-4 sm:px-6 sm:pb-20 sm:pt-8">{children}</main>
      {/* On phones the sections are along the bottom, in reach of a thumb. */}
      <Suspense fallback={<DashboardTabBar pathname="" />}>
        <DashboardTabs />
      </Suspense>
    </div>
  );
}
