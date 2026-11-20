import type { Metadata } from "next";
import { Outfit } from "next/font/google";
import { SiteFooter } from "@/components/marketing/site-footer";
import { SiteHeader } from "@/components/marketing/site-header";
import "@/components/marketing/marketing.css";

// One display face for headlines: a geometric sans close to the reference's Poppins. Body text
// stays in Geist from the root layout.
const outfit = Outfit({ subsets: ["latin"], variable: "--font-display", display: "swap" });

export const metadata: Metadata = {
  title: {
    default: "Snapreel: record your iPhone screen, camera or voice and send a link",
    template: "%s · Snapreel",
  },
  description:
    "Record your iPhone screen, camera or voice. Tap Copy link and anyone can watch in a browser, no app or account needed. Free on your iPhone, forever.",
  applicationName: "Snapreel",
  openGraph: {
    type: "website",
    siteName: "Snapreel",
    locale: "en_GB",
    url: "/",
  },
  twitter: { card: "summary_large_image" },
  alternates: { canonical: "/" },
};

export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={`mk ${outfit.variable} flex min-h-full flex-1 flex-col`}>
      <a
        href="#main"
        className="sr-only z-50 rounded-full bg-sr-ink px-4 py-2 text-white focus:not-sr-only focus:fixed focus:left-4 focus:top-3"
      >
        Skip to content
      </a>
      <SiteHeader />
      <main id="main" className="flex-1">
        {children}
      </main>
      <SiteFooter />
    </div>
  );
}
