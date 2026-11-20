import type { Metadata } from "next";
import { MarketingShell } from "@/components/marketing/shell";

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
  return <MarketingShell>{children}</MarketingShell>;
}
