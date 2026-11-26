import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  // Only the dashboard's colour code uses it: don't make every page download it before it paints.
  preload: false,
});

export const metadata: Metadata = {
  metadataBase: new URL("https://snapreel.video"),
  title: {
    default: "Snapreel: record your screen, camera or voice",
    template: "%s · Snapreel",
  },
  description:
    "Record your iPhone screen, camera or voice, keep it organised, and share it as a link people can watch in any browser.",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f4f6" },
    { media: "(prefers-color-scheme: dark)", color: "#0e0f14" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en-GB"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
