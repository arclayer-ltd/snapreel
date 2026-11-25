import { Outfit } from "next/font/google";
import { BannerWarm } from "./art";
import { SiteFooter } from "./site-footer";
import { SiteHeader } from "./site-header";
import "./marketing.css";

// One display face for headlines: a geometric sans, bold, as in the reference. Body text stays in
// Geist from the root layout.
const outfit = Outfit({ subsets: ["latin"], variable: "--font-display", display: "swap" });

/** The marketing site's frame: skip link, floating nav bar, main content and the footer scene. Used by the
 *  (marketing) layout and by app/not-found.tsx, so an unknown address gets the same page as everything else. */
export function MarketingShell({ children }: { children: React.ReactNode }) {
  return (
    <div className={`mk ${outfit.variable} flex min-h-full flex-1 flex-col`}>
      <a
        href="#main"
        className="sr-only z-50 rounded-full bg-sr-ink px-4 py-2 text-white focus:not-sr-only focus:fixed focus:left-4 focus:top-20"
      >
        Skip to content
      </a>
      <SiteHeader />
      <main id="main" className="flex-1">
        {children}
      </main>
      <SiteFooter />
      <BannerWarm />
    </div>
  );
}
