// Shared API types for snapreel.video. Mirrors docs/pro/API.md; change both together.

export type Tier = "free" | "pro";
export type VideoKind = "screen" | "camera" | "audio";
export type VideoStatus = "uploading" | "ready" | "failed";
export type Access = "link" | "password";

export const PRODUCT_MONTHLY = "co.arclayer.snapreel.pro.monthly";
export const PRODUCT_YEARLY = "co.arclayer.snapreel.pro.yearly";

export const LIMITS = {
  free: { linkLimit: 25, maxDurationS: 300, maxLongSide: 1280, quality: "720p" },
  pro: { linkLimit: null, maxDurationS: 7200, maxLongSide: 1920, quality: "1080p" },
  maxFileBytes: 2 * 1024 * 1024 * 1024,
} as const;

export interface ApiError {
  error: string;
  message?: string;
  reason?: "links" | "duration" | "pro_feature";
}

export interface Plan {
  tier: Tier;
  productId: string | null;
  expiresAt: string | null;
}

export interface Me {
  user: {
    id: string;
    email: string | null;
    displayName: string | null;
    /** profiles.email_alerts: emails for new viewers, comments and reactions. */
    emailAlerts: boolean;
    /** Pro branding on watch pages (profiles.brand_color, "#rrggbb"). */
    brandColor: string | null;
  };
  plan: Plan;
  usage: {
    activeLinks: number;
    linkLimit: number | null;
    maxDurationS: number;
    quality: "720p" | "1080p";
  };
}

export interface TranscriptSegment {
  start: number;
  duration: number;
  text: string;
}

export interface Transcript {
  locale: string;
  segments: TranscriptSegment[];
}

export interface CallToAction {
  label: string;
  url: string;
}

export interface CreateVideoRequest {
  localId: string;
  title: string;
  kind: VideoKind;
  durationS: number;
  width: number;
  height: number;
  sizeBytes: number;
  transcript?: Transcript | null;
}

export interface CreateVideoResponse {
  id: string;
  slug: string;
  url: string;
  status: VideoStatus;
  upload: { bucket: "videos"; videoPath: string; posterPath: string; previewPath: string };
  limits: { maxDurationS: number; maxLongSide: number };
}

export interface VideoSummary {
  id: string;
  slug: string;
  url: string;
  localId: string;
  title: string;
  kind: VideoKind;
  durationS: number;
  status: VideoStatus;
  posterUrl: string | null;
  createdAt: string;
  views: number;
  uniqueViewers: number;
  lastViewedAt: string | null;
  commentCount: number;
}

export interface VideoDetail extends VideoSummary {
  access: Access;
  hasPassword: boolean;
  expiresAt: string | null;
  allowDownload: boolean;
  allowComments: boolean;
  allowReactions: boolean;
  cta: CallToAction | null;
  width: number;
  height: number;
  sizeBytes: number;
}

export interface UpdateMeRequest {
  displayName?: string;
  brandColor?: string | null;
  emailAlerts?: boolean;
}

export interface UpdateVideoRequest {
  title?: string;
  status?: VideoStatus;
  uploadedBytes?: number;
  access?: Access;
  password?: string;
  expiresAt?: string | null;
  allowDownload?: boolean;
  allowComments?: boolean;
  allowReactions?: boolean;
  cta?: CallToAction | null;
  transcript?: Transcript | null;
}

export interface Viewer {
  name: string | null;
  anonymous: boolean;
  country: string | null;
  device: "phone" | "tablet" | "desktop" | null;
  firstSeenAt: string;
  lastSeenAt: string;
  percent: number;
}

export interface Insights {
  views: number;
  uniqueViewers: number;
  avgPercent: number | null;
  completionRate: number | null;
  dropoff: number[] | null;
  countries: { code: string; count: number }[] | null;
  viewers: Viewer[] | null;
}

export interface Comment {
  id: string;
  authorName: string;
  isOwner: boolean;
  body: string;
  atS: number | null;
  parentId: string | null;
  createdAt: string;
}

export interface Reaction {
  id: string;
  emoji: string;
  atS: number;
  authorName: string | null;
  createdAt: string;
}

export interface Activity {
  comments: Comment[];
  reactions: Reaction[];
}

export interface PublicVideo {
  title: string;
  /** "audio" plays with a moving waveform instead of a picture. */
  kind: VideoKind;
  ownerName: string | null;
  brand: { color: string | null; logoUrl: string | null } | null;
  durationS: number;
  width: number;
  height: number;
  status: VideoStatus;
  /** 0 to 1 while status is "uploading" (uploaded_bytes / size_bytes); otherwise null. */
  uploadProgress: number | null;
  posterUrl: string | null;
  videoUrl: string | null;
  previewUrl: string | null;
  captionsUrl: string | null;
  transcript: Transcript | null;
  allowDownload: boolean;
  allowComments: boolean;
  allowReactions: boolean;
  cta: CallToAction | null;
  showBadge: boolean;
  createdAt: string;
}

export interface ViewEvent {
  event: "start" | "progress" | "end";
  positionS: number;
  watched: number[];
}

export interface NewComment {
  name: string;
  body: string;
  atS: number | null;
  parentId?: string | null;
  website?: string;
}

export interface NewReaction {
  emoji: string;
  atS: number;
  name?: string | null;
}

export interface NewReport {
  reason: "spam" | "abuse" | "illegal" | "copyright" | "other";
  details: string;
  email?: string | null;
}

export interface PushPayload {
  type: "view" | "comment" | "reaction" | "upload";
  videoId: string;
  localId: string;
  commentId?: string;
}
