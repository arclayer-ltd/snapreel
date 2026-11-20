import type { MetadataRoute } from "next";

// Search engines get the marketing site only. Watch pages (/v/…) are unlisted links and the
// dashboard is private. Link-preview bots that read robots.txt (X, Facebook, Slack, LinkedIn,
// Discord, Telegram, WhatsApp) may still fetch watch pages, so a pasted link shows its preview;
// the watch pages themselves are noindex.
const previewBots = [
  "Twitterbot",
  "facebookexternalhit",
  "Slackbot-LinkExpanding",
  "LinkedInBot",
  "Discordbot",
  "TelegramBot",
  "WhatsApp",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/", disallow: ["/v/", "/app", "/login", "/api/"] },
      { userAgent: previewBots, allow: ["/v/", "/api/oembed"], disallow: ["/app", "/login"] },
    ],
    sitemap: "https://snapreel.video/sitemap.xml",
    host: "https://snapreel.video",
  };
}
