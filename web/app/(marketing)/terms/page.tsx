import type { Metadata } from "next";
import { LegalPage } from "@/components/marketing/legal-page";

export const metadata: Metadata = {
  title: "Terms of use",
  description: "The terms for using Snapreel.",
  alternates: { canonical: "/terms" },
  openGraph: { url: "/terms" },
};

export default function TermsPage() {
  return <LegalPage doc="terms" fallbackTitle="Terms of use" />;
}
