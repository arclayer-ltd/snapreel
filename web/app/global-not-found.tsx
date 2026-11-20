import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
// globals.css must load before the marketing shell's marketing.css: Tailwind's first stylesheet fixes the
// cascade-layer order (theme, base, components, utilities). Loaded after, the base reset beats the marketing padding.
import "./globals.css";
import { NotFoundContent } from "@/components/marketing/not-found-content";
import { MarketingShell } from "@/components/marketing/shell";

// Served for any address that matches no route (e.g. /nope). Next skips the root layout here, so this file
// repeats its fonts, html attributes and theme colours (keep them in step with app/layout.tsx).
const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://snapreel.video"),
  title: "Page not found · Snapreel",
  robots: { index: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f4f6" },
    { media: "(prefers-color-scheme: dark)", color: "#0e0f14" },
  ],
};

export default function GlobalNotFound() {
  return (
    <html lang="en-GB" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <MarketingShell>
          <NotFoundContent />
        </MarketingShell>
      </body>
    </html>
  );
}
