// Sample data for preview mode: the web app running without Supabase (no NEXT_PUBLIC_SUPABASE_* env).
// The stub in lib/server/queries.ts and the client mock in lib/client/preview.ts both read from here,
// so pages work end to end locally before the backend lands. Media lives in public/dev-fixtures/.
// Nothing here runs once NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY are set.

import type {
  Activity,
  Comment,
  Insights,
  Me,
  PublicVideo,
  Reaction,
  Tier,
  Transcript,
  VideoDetail,
  Viewer,
} from "@/lib/contract";
import { LIMITS } from "@/lib/contract";

export const PREVIEW =
  !process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

/** Cookie the preview sign-in sets: "free" or "pro". */
export const PREVIEW_COOKIE = "sr_preview";
/** Password for the password-protected sample. */
export const PREVIEW_PASSWORD = "snapreel";

export type PreviewError = "password" | "expired" | "removed" | "not_found";

export interface PreviewVideo {
  detail: VideoDetail;
  publicVideo: PublicVideo;
  /** What the public endpoint says instead of the video, if anything. */
  publicError: PreviewError | null;
  activity: Activity;
  insights: Insights;
}

const F = "/dev-fixtures";

const iso = (now: number, minutesAgo: number) => new Date(now - minutesAgo * 60_000).toISOString();

const launchTranscript: Transcript = {
  locale: "en-GB",
  segments: [
    { start: 0, duration: 3.5, text: "Hi team, here's a quick look at the launch plan." },
    { start: 3.5, duration: 4, text: "These are the five people you'll see across the new site." },
    { start: 7.5, duration: 3.5, text: "Each one shows a different way to record with Snapreel." },
    { start: 11, duration: 4, text: "Next, the welcome screen, the first thing new people see." },
    { start: 15, duration: 4, text: "It explains recording, links and privacy in one go." },
    { start: 19, duration: 4, text: "Leave a comment if anything looks off, and I'll fix it today." },
  ],
};

const phoneTranscript: Transcript = {
  locale: "en-GB",
  segments: [
    { start: 0, duration: 4, text: "This is how a link goes from my phone to yours." },
    { start: 4, duration: 5, text: "Tap Copy link, and it's ready straight away." },
    { start: 9, duration: 5, text: "The upload carries on in the background." },
    { start: 14, duration: 4, text: "You can start watching before it has even finished." },
  ],
};

const voiceTranscript: Transcript = {
  locale: "en-GB",
  segments: [
    { start: 0, duration: 5, text: "Quick voice note before Thursday." },
    { start: 5, duration: 6, text: "First we'll go over the numbers from last week." },
    { start: 11, duration: 5, text: "Then the new onboarding, which Priya has been working on." },
    { start: 16, duration: 5, text: "Bring questions, and we'll finish by four." },
  ],
};

function comment(
  now: number,
  id: string,
  authorName: string,
  body: string,
  atS: number | null,
  minutesAgo: number,
  extra: Partial<Comment> = {},
): Comment {
  return { id, authorName, isOwner: false, body, atS, parentId: null, createdAt: iso(now, minutesAgo), ...extra };
}

function reactions(now: number, prefix: string, list: [string, number, string | null, number][]): Reaction[] {
  return list.map(([emoji, atS, authorName, minutesAgo], i) => ({
    id: `${prefix}-r${i}`,
    emoji,
    atS,
    authorName,
    createdAt: iso(now, minutesAgo),
  }));
}

function dropoff(views: number, steepness: number, bump = 0): number[] {
  return Array.from({ length: 100 }, (_, i) => {
    const x = i / 99;
    const base = views * (1 - steepness * Math.pow(x, 1.25)) * (i < 3 ? 1 : 0.96);
    const rewatch = bump * views * Math.exp(-Math.pow((i - 52) / 6, 2));
    return Math.max(0, Math.round(base + rewatch));
  });
}

function viewers(now: number, list: [string | null, string | null, Viewer["device"], number, number][]): Viewer[] {
  return list.map(([name, country, device, percent, minutesAgo]) => ({
    name,
    anonymous: name === null,
    country,
    device,
    firstSeenAt: iso(now, minutesAgo + 40),
    lastSeenAt: iso(now, minutesAgo),
    percent,
  }));
}

const lockedInsights = (views: number, uniqueViewers: number): Insights => ({
  views,
  uniqueViewers,
  avgPercent: null,
  completionRate: null,
  dropoff: null,
  countries: null,
  viewers: null,
});

/** Every sample video, newest first. Built per call so relative times stay fresh. */
export function previewVideos(now: number): PreviewVideo[] {
  const base = {
    localId: "",
    access: "link" as const,
    hasPassword: false,
    expiresAt: null,
    allowDownload: false,
    allowComments: true,
    allowReactions: true,
    cta: null,
  };

  const launchComments: Comment[] = [
    comment(now, "c1", "Priya Shah", "Love the lineup. Could the person in the red hoodie lead the hero?", 4.2, 130),
    comment(now, "c2", "Sam Carter", "Yes, swapping that in now.", null, 118, { isOwner: true, parentId: "c1" }),
    comment(now, "c3", "Jordan Lee", "The welcome screen reads really well on my phone.", 12.5, 95),
    comment(now, "c4", "Alex", "Watched it twice. Plays nicely on the train too.", null, 52),
    comment(now, "c5", "Mina Okafor", "Small thing: can the email say “today” instead of “tonight”?", 19, 21),
    comment(now, "c6", "Priya Shah", "Agree with Mina.", null, 14, { parentId: "c5" }),
  ];

  const list: PreviewVideo[] = [
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0001",
        slug: "Lx7kQ2mN9a",
        url: "https://snapreel.video/v/Lx7kQ2mN9a",
        localId: "1d7c0b9e-0000-4000-8000-000000000001",
        title: "Launch plan walkthrough",
        kind: "screen",
        durationS: 23,
        status: "ready",
        posterUrl: `${F}/landscape.jpg`,
        createdAt: iso(now, 60 * 5),
        views: 128,
        uniqueViewers: 54,
        lastViewedAt: iso(now, 6),
        commentCount: launchComments.length,
        allowDownload: true,
        cta: { label: "Book a call", url: "https://example.com/book" },
        width: 1280,
        height: 720,
        sizeBytes: 672_221,
      },
      publicVideo: {
        title: "Launch plan walkthrough",
        kind: "screen",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 23,
        width: 1280,
        height: 720,
        status: "ready",
        uploadProgress: null,
        posterUrl: `${F}/landscape.jpg`,
        videoUrl: `${F}/landscape.mp4`,
        previewUrl: `${F}/landscape.mp4`,
        captionsUrl: `${F}/landscape.vtt`,
        transcript: launchTranscript,
        allowDownload: true,
        allowComments: true,
        allowReactions: true,
        cta: { label: "Book a call", url: "https://example.com/book" },
        showBadge: false,
        createdAt: iso(now, 60 * 5),
      },
      publicError: null,
      activity: {
        comments: launchComments,
        reactions: reactions(now, "v1", [
          ["👍", 1.8, "Jordan Lee", 100],
          ["❤️", 4.4, "Priya Shah", 128],
          ["🔥", 5.1, null, 90],
          ["🔥", 5.6, "Alex", 50],
          ["😂", 8.9, null, 70],
          ["👏", 11.6, "Mina Okafor", 22],
          ["👍", 12.9, null, 40],
          ["😮", 14.7, "Jordan Lee", 94],
          ["❤️", 16.2, null, 33],
          ["❤️", 16.5, "Priya Shah", 12],
          ["👏", 21.8, null, 8],
          ["🎉", 22.4, "Alex", 49],
        ]),
      },
      insights: {
        views: 128,
        uniqueViewers: 54,
        avgPercent: 72,
        completionRate: 0.58,
        dropoff: dropoff(128, 0.46, 0.08),
        countries: [
          { code: "GB", count: 41 },
          { code: "US", count: 38 },
          { code: "DE", count: 13 },
          { code: "IN", count: 11 },
          { code: "CA", count: 8 },
          { code: "NL", count: 7 },
          { code: "FR", count: 5 },
          { code: "AU", count: 5 },
        ],
        viewers: viewers(now, [
          ["Mina Okafor", "GB", "phone", 100, 6],
          [null, "US", "desktop", 64, 18],
          ["Jordan Lee", "US", "desktop", 100, 41],
          [null, "DE", "phone", 22, 55],
          ["Priya Shah", "GB", "desktop", 100, 72],
          [null, "IN", "tablet", 81, 130],
          ["Alex", "CA", "phone", 100, 180],
          [null, "NL", "desktop", 47, 260],
          [null, "GB", "phone", 13, 300],
        ]),
      },
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0002",
        slug: "Pt3vR8wZ1c",
        url: "https://snapreel.video/v/Pt3vR8wZ1c",
        title: "Sending a link from my phone",
        kind: "camera",
        durationS: 18,
        status: "ready",
        posterUrl: `${F}/portrait.jpg`,
        createdAt: iso(now, 60 * 26),
        views: 37,
        uniqueViewers: 21,
        lastViewedAt: iso(now, 60 * 3),
        commentCount: 2,
        width: 720,
        height: 1280,
        sizeBytes: 267_409,
      },
      publicVideo: {
        title: "Sending a link from my phone",
        kind: "camera",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 18,
        width: 720,
        height: 1280,
        status: "ready",
        uploadProgress: null,
        posterUrl: `${F}/portrait.jpg`,
        videoUrl: `${F}/portrait.mp4`,
        previewUrl: `${F}/portrait.mp4`,
        captionsUrl: null,
        transcript: phoneTranscript,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: null,
        showBadge: true,
        createdAt: iso(now, 60 * 26),
      },
      publicError: null,
      activity: {
        comments: [
          comment(now, "p1", "Jordan Lee", "That was quick. Didn't even have to wait.", 9.5, 60 * 20),
          comment(now, "p2", "Robin", "Does this work for longer videos too?", null, 60 * 4),
        ],
        reactions: reactions(now, "v2", [
          ["👍", 4.5, null, 60 * 20],
          ["🔥", 9.2, "Jordan Lee", 60 * 20],
          ["😮", 14.1, null, 60 * 6],
        ]),
      },
      insights: {
        views: 37,
        uniqueViewers: 21,
        avgPercent: 64,
        completionRate: 0.41,
        dropoff: dropoff(37, 0.62),
        countries: [
          { code: "GB", count: 19 },
          { code: "IE", count: 9 },
          { code: "ES", count: 6 },
          { code: "US", count: 3 },
        ],
        viewers: viewers(now, [
          ["Robin", "IE", "phone", 100, 60 * 3],
          [null, "GB", "phone", 35, 60 * 7],
          ["Jordan Lee", "GB", "desktop", 100, 60 * 20],
          [null, "ES", "phone", 52, 60 * 22],
        ]),
      },
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0003",
        slug: "Vn4bA6sD2e",
        url: "https://snapreel.video/v/Vn4bA6sD2e",
        title: "Voice note: Thursday's agenda",
        kind: "audio",
        durationS: 21,
        status: "ready",
        posterUrl: null,
        createdAt: iso(now, 60 * 50),
        views: 9,
        uniqueViewers: 6,
        lastViewedAt: iso(now, 60 * 30),
        commentCount: 1,
        width: 0,
        height: 0,
        sizeBytes: 159_923,
        cta: { label: "Add it to your calendar", url: "https://example.com/thursday" },
      },
      publicVideo: {
        title: "Voice note: Thursday's agenda",
        kind: "audio",
        ownerName: "Sam Carter",
        brand: { color: "#1f6f68", logoUrl: `${F}/brand-logo.svg` },
        durationS: 21,
        width: 0,
        height: 0,
        status: "ready",
        uploadProgress: null,
        posterUrl: null,
        videoUrl: `${F}/audio.m4a`,
        previewUrl: null,
        captionsUrl: null,
        transcript: voiceTranscript,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: { label: "Add it to your calendar", url: "https://example.com/thursday" },
        showBadge: false,
        createdAt: iso(now, 60 * 50),
      },
      publicError: null,
      activity: {
        comments: [comment(now, "a1", "Priya Shah", "I'll bring the onboarding draft.", 13, 60 * 31)],
        reactions: reactions(now, "v3", [["👍", 6, "Priya Shah", 60 * 31]]),
      },
      insights: {
        views: 9,
        uniqueViewers: 6,
        avgPercent: 88,
        completionRate: 0.78,
        dropoff: dropoff(9, 0.25),
        countries: [{ code: "GB", count: 9 }],
        viewers: viewers(now, [["Priya Shah", "GB", "desktop", 100, 60 * 30]]),
      },
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0004",
        slug: "Kq9pW3xY5f",
        url: "https://snapreel.video/v/Kq9pW3xY5f",
        title: "Q4 numbers (private)",
        kind: "screen",
        durationS: 23,
        status: "ready",
        posterUrl: `${F}/second.jpg`,
        createdAt: iso(now, 60 * 72),
        views: 4,
        uniqueViewers: 3,
        lastViewedAt: iso(now, 60 * 49),
        commentCount: 0,
        access: "password",
        hasPassword: true,
        width: 1280,
        height: 720,
        sizeBytes: 672_221,
      },
      publicVideo: {
        title: "Q4 numbers (private)",
        kind: "screen",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 23,
        width: 1280,
        height: 720,
        status: "ready",
        uploadProgress: null,
        posterUrl: `${F}/second.jpg`,
        videoUrl: `${F}/landscape.mp4`,
        previewUrl: null,
        captionsUrl: `${F}/landscape.vtt`,
        transcript: launchTranscript,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: null,
        showBadge: false,
        createdAt: iso(now, 60 * 72),
      },
      publicError: "password",
      activity: { comments: [], reactions: [] },
      insights: {
        views: 4,
        uniqueViewers: 3,
        avgPercent: 91,
        completionRate: 0.75,
        dropoff: dropoff(4, 0.2),
        countries: [{ code: "GB", count: 4 }],
        viewers: viewers(now, [["Jordan Lee", "GB", "desktop", 100, 60 * 49]]),
      },
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0005",
        slug: "Up0lD4gH7j",
        url: "https://snapreel.video/v/Up0lD4gH7j",
        title: "Bug report: checkout button",
        kind: "screen",
        durationS: 23,
        status: "uploading",
        posterUrl: `${F}/landscape.jpg`,
        createdAt: iso(now, 2),
        views: 0,
        uniqueViewers: 0,
        lastViewedAt: null,
        commentCount: 0,
        width: 1280,
        height: 720,
        sizeBytes: 672_221,
      },
      publicVideo: {
        title: "Bug report: checkout button",
        kind: "screen",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 23,
        width: 1280,
        height: 720,
        status: "uploading",
        uploadProgress: 0.45,
        posterUrl: `${F}/landscape.jpg`,
        videoUrl: null,
        previewUrl: null,
        captionsUrl: null,
        transcript: null,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: null,
        showBadge: true,
        createdAt: iso(now, 2),
      },
      publicError: null,
      activity: { comments: [], reactions: [] },
      insights: lockedInsights(0, 0),
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0006",
        slug: "Ex2pQ8rT4k",
        url: "https://snapreel.video/v/Ex2pQ8rT4k",
        title: "Holiday rota draft",
        kind: "camera",
        durationS: 18,
        status: "ready",
        posterUrl: `${F}/portrait.jpg`,
        createdAt: iso(now, 60 * 24 * 12),
        views: 15,
        uniqueViewers: 11,
        lastViewedAt: iso(now, 60 * 24 * 5),
        commentCount: 0,
        expiresAt: iso(now, 60 * 24 * 2),
        width: 720,
        height: 1280,
        sizeBytes: 267_409,
      },
      publicVideo: {
        title: "Holiday rota draft",
        kind: "camera",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 18,
        width: 720,
        height: 1280,
        status: "ready",
        uploadProgress: null,
        posterUrl: `${F}/portrait.jpg`,
        videoUrl: `${F}/portrait.mp4`,
        previewUrl: null,
        captionsUrl: null,
        transcript: null,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: null,
        showBadge: true,
        createdAt: iso(now, 60 * 24 * 12),
      },
      publicError: "expired",
      activity: { comments: [], reactions: [] },
      insights: {
        views: 15,
        uniqueViewers: 11,
        avgPercent: 58,
        completionRate: 0.33,
        dropoff: dropoff(15, 0.7),
        countries: [
          { code: "GB", count: 12 },
          { code: "PT", count: 3 },
        ],
        viewers: viewers(now, [[null, "GB", "phone", 40, 60 * 24 * 5]]),
      },
    },
    {
      detail: {
        ...base,
        id: "8f0a5c1e-6b1d-4c39-9a51-5f7d2f0c0007",
        slug: "Fa1lU5rE3m",
        url: "https://snapreel.video/v/Fa1lU5rE3m",
        title: "Team stand-up, Monday",
        kind: "camera",
        durationS: 94,
        status: "failed",
        posterUrl: null,
        createdAt: iso(now, 60 * 24 * 3),
        views: 0,
        uniqueViewers: 0,
        lastViewedAt: null,
        commentCount: 0,
        width: 1080,
        height: 1920,
        sizeBytes: 31_000_000,
      },
      publicVideo: {
        title: "Team stand-up, Monday",
        kind: "camera",
        ownerName: "Sam Carter",
        brand: null,
        durationS: 94,
        width: 1080,
        height: 1920,
        status: "failed",
        uploadProgress: null,
        posterUrl: null,
        videoUrl: null,
        previewUrl: null,
        captionsUrl: null,
        transcript: null,
        allowDownload: false,
        allowComments: true,
        allowReactions: true,
        cta: null,
        showBadge: true,
        createdAt: iso(now, 60 * 24 * 3),
      },
      publicError: null,
      activity: { comments: [], reactions: [] },
      insights: lockedInsights(0, 0),
    },
  ];
  return list;
}

/** A slug that once existed but was stopped by its owner. */
export const PREVIEW_REMOVED_SLUG = "Rm0vEd7sLg";

export function previewMe(tier: Tier, activeLinks: number): Me {
  const pro = tier === "pro";
  return {
    user: {
      id: pro ? "preview-pro" : "preview-free",
      email: pro ? "sam.pro@example.com" : "sam@example.com",
      displayName: "Sam Carter",
      emailAlerts: true,
      brandColor: pro ? "#1f6f68" : null,
    },
    plan: {
      tier,
      productId: pro ? "co.arclayer.snapreel.pro.yearly" : null,
      expiresAt: pro ? new Date(Date.UTC(2027, 10, 20)).toISOString() : null,
    },
    usage: {
      activeLinks,
      linkLimit: pro ? LIMITS.pro.linkLimit : LIMITS.free.linkLimit,
      maxDurationS: pro ? LIMITS.pro.maxDurationS : LIMITS.free.maxDurationS,
      quality: pro ? "1080p" : "720p",
    },
  };
}

/** Free accounts see counts only, as the real endpoint returns. */
export function insightsForTier(insights: Insights, tier: Tier): Insights {
  return tier === "pro" ? insights : lockedInsights(insights.views, insights.uniqueViewers);
}
