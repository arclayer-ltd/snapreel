import type { Metadata } from "next";
import { Suspense } from "react";
import { EmbedMessage, EmbedView } from "@/components/player/watch/EmbedView";
import { ERROR_TITLES, loadPublicVideo } from "../watch-data";

export async function generateMetadata({ params }: PageProps<"/v/[slug]/embed">): Promise<Metadata> {
  const { slug } = await params;
  const v = await loadPublicVideo(slug);
  return {
    title: "error" in v ? ERROR_TITLES[v.error] : { absolute: v.title },
    robots: { index: false, follow: false },
  };
}

export default function EmbedPage({ params }: PageProps<"/v/[slug]/embed">) {
  return (
    <Suspense fallback={<div className="h-svh w-full bg-[#07080c]" aria-busy="true" />}>
      <Embed params={params} />
    </Suspense>
  );
}

const MESSAGES = {
  password: "This video has a password.",
  expired: "This link has expired.",
  removed: "This video isn’t shared any more.",
  not_found: "We can’t find this video.",
} as const;

async function Embed({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const v = await loadPublicVideo(slug);
  if ("error" in v) return <EmbedMessage slug={slug} text={MESSAGES[v.error]} />;
  return <EmbedView slug={slug} initial={v} />;
}
