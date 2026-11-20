// Loading a public video for the watch and embed pages, and the link-preview metadata for it.
import "server-only";

import type { Metadata } from "next";
import { cookies } from "next/headers";
import { cache } from "react";
import { getSessionUser } from "@/app/app/_lib/session";
import type { PublicVideo } from "@/lib/contract";
import { formatTime } from "@/lib/client/format";
import { SITE_URL } from "@/lib/client/links";
import { getPublicVideo } from "@/lib/server/queries";

export type WatchError = "password" | "expired" | "removed" | "not_found";
export type WatchResult = PublicVideo | { error: WatchError };

const SLUG = /^[A-Za-z0-9]{4,32}$/;

/** One load per request, shared by generateMetadata and the page. */
export const loadPublicVideo = cache(async (slug: string): Promise<WatchResult> => {
  if (!SLUG.test(slug)) return { error: "not_found" };
  const store = await cookies();
  const unlockCookie = store.get(`sr_unlock_${slug}`)?.value ?? null;
  const viewer = await getSessionUser();
  const result = await getPublicVideo(slug, { unlockCookie, viewerUserId: viewer?.id ?? null });
  return result as WatchResult;
});

const ERROR_TITLES: Record<WatchError, string> = {
  password: "Password-protected video",
  expired: "This link has expired",
  removed: "This video isn’t shared any more",
  not_found: "Video not found",
};

const noindex: Metadata["robots"] = { index: false, follow: false, googleBot: { index: false, follow: false } };

function kindWord(v: PublicVideo): string {
  if (v.kind === "audio") return "voice recording";
  if (v.kind === "screen") return "screen recording";
  return "video";
}

/** Poster size: the app makes posters 1280 on the long side. */
function posterSize(v: PublicVideo): { width: number; height: number } {
  if (!v.width || !v.height) return { width: 1280, height: 720 };
  return v.width >= v.height
    ? { width: 1280, height: Math.round((1280 * v.height) / v.width) }
    : { width: Math.round((1280 * v.width) / v.height), height: 1280 };
}

export function watchMetadata(slug: string, v: WatchResult): Metadata {
  const path = `/v/${slug}`;
  if ("error" in v) {
    const title = ERROR_TITLES[v.error];
    const image = { url: "/v/preview/locked", width: 1200, height: 630, alt: "A Snapreel video" };
    return {
      title,
      description:
        v.error === "password" ? "Enter the password to watch this video on Snapreel." : "Snapreel: record your screen, camera or voice.",
      robots: noindex,
      openGraph: { type: "website", url: path, title, siteName: "Snapreel", images: [image] },
      twitter: { card: "summary_large_image", title, images: [image.url] },
    };
  }

  const description = v.ownerName
    ? `${v.ownerName} shared a ${formatTime(v.durationS)} ${kindWord(v)}.`
    : `A ${formatTime(v.durationS)} ${kindWord(v)} on Snapreel.`;
  const size = posterSize(v);
  const image = v.posterUrl
    ? { url: v.posterUrl, ...size, alt: v.title }
    : { url: "/v/preview/generic", width: 1200, height: 630, alt: v.title };
  const embed = `${SITE_URL}${path}/embed`;
  const oembed = `${SITE_URL}/api/oembed?url=${encodeURIComponent(`${SITE_URL}${path}`)}&format=json`;

  return {
    // Pro links carry no Snapreel branding, the tab title included.
    title: v.showBadge ? v.title : { absolute: v.title },
    description,
    robots: noindex,
    alternates: {
      canonical: path,
      types: { "application/json+oembed": [{ url: oembed, title: v.title }] },
    },
    openGraph: {
      type: "video.other",
      url: path,
      title: v.title,
      description,
      siteName: "Snapreel",
      images: [image],
      videos: [{ url: embed, secureUrl: embed, type: "text/html", width: size.width, height: size.height }],
    },
    twitter: {
      card: "player",
      title: v.title,
      description,
      images: [image.url],
      players: [{ playerUrl: embed, streamUrl: v.videoUrl ?? embed, width: size.width, height: size.height }],
    },
    other: { "video:duration": String(Math.round(v.durationS)) },
  };
}
