"use client";

// Client calls to the snapreel.video API (docs/pro/API.md). Public calls ride on the viewer's sr_vs cookie;
// owner calls send the Supabase access token as a Bearer token. In preview mode (no Supabase env) every
// call is answered by lib/client/preview.ts instead, so the pages can be tried locally.
import type {
  Activity,
  CallToAction,
  Comment,
  Insights,
  Me,
  NewComment,
  NewReaction,
  NewReport,
  PublicVideo,
  Reaction,
  UpdateMeRequest,
  UpdateVideoRequest,
  VideoDetail,
  VideoSummary,
  ViewEvent,
  ViewOptOut,
} from "@/lib/contract";
import { PREVIEW } from "@/lib/client/preview-data";
import { accessToken } from "@/lib/client/supabase";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message?: string,
    readonly reason?: "links" | "duration" | "pro_feature",
  ) {
    super(message ?? code);
    this.name = "ApiError";
  }

  get isRateLimited(): boolean {
    return this.status === 429;
  }

  get needsPro(): boolean {
    return this.status === 402;
  }
}

type Method = "GET" | "POST" | "PATCH" | "DELETE";

async function request<T>(method: Method, path: string, opts: { body?: unknown; auth?: boolean } = {}): Promise<T> {
  if (PREVIEW) {
    const { mockRequest } = await import("@/lib/client/preview");
    return mockRequest<T>(method, path, opts.body);
  }
  const headers: Record<string, string> = { accept: "application/json" };
  if (opts.body !== undefined) headers["content-type"] = "application/json";
  if (opts.auth) {
    const token = await accessToken();
    if (!token) throw new ApiError(401, "signed_out", "You're signed out. Sign in again to carry on.");
    headers.authorization = `Bearer ${token}`;
  }
  let res: Response;
  try {
    res = await fetch(path, {
      method,
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch {
    throw new ApiError(0, "offline", "Couldn't reach Snapreel. Check your connection and try again.");
  }
  if (res.status === 204) return undefined as T;
  const data = (await res.json().catch(() => null)) as
    | (T & { error?: string; message?: string; reason?: ApiError["reason"] })
    | null;
  if (!res.ok) {
    throw new ApiError(res.status, data?.error ?? "unknown", data?.message, data?.reason);
  }
  return data as T;
}

const pub = (slug: string, rest = "") => `/api/public/v/${encodeURIComponent(slug)}${rest}`;

// Public (viewer) calls

export const publicApi = {
  video: (slug: string) => request<PublicVideo>("GET", pub(slug)),
  unlock: (slug: string, password: string) => request<void>("POST", pub(slug, "/unlock"), { body: { password } }),
  activity: (slug: string) => request<Activity>("GET", pub(slug, "/activity")),
  comment: (slug: string, body: NewComment) => request<Comment>("POST", pub(slug, "/comments"), { body }),
  react: (slug: string, body: NewReaction) => request<Reaction>("POST", pub(slug, "/reactions"), { body }),
  report: (slug: string, body: NewReport) => request<void>("POST", pub(slug, "/report"), { body }),
  view: (slug: string, body: ViewEvent) => request<{ viewId: string }>("POST", pub(slug, "/view"), { body }),
  /** "Don't count my views": sets or clears the sr_nocount cookie for every Snapreel link in this browser. */
  setViewOptOut: (optOut: boolean) => request<ViewOptOut>("POST", "/api/public/view-opt-out", { body: { optOut } }),
};

/** True when this browser turned on "Don't count my views" (cookie sr_nocount=1). */
export function viewsOptedOut(): boolean {
  return typeof document !== "undefined" && /(?:^|;\s*)sr_nocount=1(?:;|$)/.test(document.cookie);
}

/** For pagehide: survives the page closing. Returns false if the browser refused it. */
export function sendViewBeacon(slug: string, body: ViewEvent): boolean {
  if (PREVIEW) {
    void import("@/lib/client/preview").then(({ mockRequest }) => mockRequest("POST", pub(slug, "/view"), body));
    return true;
  }
  const blob = new Blob([JSON.stringify(body)], { type: "application/json" });
  if (typeof navigator !== "undefined" && typeof navigator.sendBeacon === "function") {
    if (navigator.sendBeacon(pub(slug, "/view"), blob)) return true;
  }
  void fetch(pub(slug, "/view"), {
    method: "POST",
    body: blob,
    keepalive: true,
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
  }).catch(() => {});
  return false;
}

// Owner calls

export const ownerApi = {
  me: () => request<Me>("GET", "/api/me", { auth: true }),
  updateMe: (body: UpdateMeRequest) => request<Me>("PATCH", "/api/me", { body, auth: true }),
  videos: () => request<VideoSummary[]>("GET", "/api/videos", { auth: true }),
  video: (id: string) => request<VideoDetail>("GET", `/api/videos/${encodeURIComponent(id)}`, { auth: true }),
  updateVideo: (id: string, body: UpdateVideoRequest) =>
    request<VideoDetail>("PATCH", `/api/videos/${encodeURIComponent(id)}`, { body, auth: true }),
  deleteVideo: (id: string) => request<void>("DELETE", `/api/videos/${encodeURIComponent(id)}`, { auth: true }),
  insights: (id: string) => request<Insights>("GET", `/api/videos/${encodeURIComponent(id)}/insights`, { auth: true }),
  activity: (id: string) => request<Activity>("GET", `/api/videos/${encodeURIComponent(id)}/activity`, { auth: true }),
  deleteComment: (id: string) => request<void>("DELETE", `/api/comments/${encodeURIComponent(id)}`, { auth: true }),
  approveComment: (id: string) => request<Comment>("POST", `/api/comments/${encodeURIComponent(id)}/approve`, { auth: true }),
  block: (target: { commentId: string } | { reactionId: string }) =>
    request<void>("POST", "/api/blocks", { body: target, auth: true }),
  deleteAccount: () => request<void>("POST", "/api/account/delete", { auth: true }),
};

/** A short, human message for any failed call. */
export function errorMessage(err: unknown, fallback = "Something went wrong. Try again."): string {
  if (err instanceof ApiError) {
    if (err.status === 0) return err.message;
    if (err.isRateLimited) return "That's a lot at once. Wait a minute, then try again.";
    if (err.needsPro) return "That needs Snapreel Pro. Upgrade in the Snapreel app on your iPhone.";
    if (err.status === 401 && err.code === "signed_out") return err.message;
    return err.message && err.message !== err.code ? err.message : fallback;
  }
  return fallback;
}

/** True when the URL is a plausible https link for a call-to-action. */
export function isValidCtaUrl(url: string): boolean {
  try {
    const u = new URL(url.trim());
    return u.protocol === "https:" && u.hostname.includes(".");
  } catch {
    return false;
  }
}

export type { CallToAction };
