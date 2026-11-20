import type { MetadataRoute } from "next";
import { getHelp } from "@/components/marketing/content";

const BASE = "https://snapreel.video";

// Marketing pages only. Watch pages (/v/…) and the dashboard (/app) are private by design.
export default function sitemap(): MetadataRoute.Sitemap {
  const pages: MetadataRoute.Sitemap = [
    { url: `${BASE}/`, changeFrequency: "weekly", priority: 1 },
    { url: `${BASE}/pricing`, changeFrequency: "monthly", priority: 0.8 },
    { url: `${BASE}/help`, changeFrequency: "weekly", priority: 0.7 },
    { url: `${BASE}/support`, changeFrequency: "monthly", priority: 0.5 },
    { url: `${BASE}/privacy`, changeFrequency: "monthly", priority: 0.3 },
    { url: `${BASE}/terms`, changeFrequency: "monthly", priority: 0.3 },
  ];
  const articles = getHelp().articles.map((a) => ({
    url: `${BASE}/help/${a.id}`,
    changeFrequency: "monthly" as const,
    priority: 0.5,
  }));
  return [...pages, ...articles];
}
