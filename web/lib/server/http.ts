import "server-only";
import { unstable_rethrow } from "next/navigation";
import type { ApiError } from "@/lib/contract";

// Errors are JSON {error, message} (docs/pro/API.md). 402 carries {reason} for plan limits.
export class HttpError extends Error {
  constructor(
    public status: number,
    public code: string,
    message?: string,
    public extra: Record<string, unknown> = {},
  ) {
    super(message ?? code);
  }
}

export const NO_STORE = { "Cache-Control": "no-store" } as const;

export function json(data: unknown, status = 200, headers?: HeadersInit): Response {
  const h = new Headers(headers);
  if (!h.has("Cache-Control")) h.set("Cache-Control", "no-store");
  return Response.json(data, { status, headers: h });
}

export function noContent(headers?: HeadersInit): Response {
  const h = new Headers(headers);
  h.set("Cache-Control", "no-store");
  return new Response(null, { status: 204, headers: h });
}

export function limitError(reason: NonNullable<ApiError["reason"]>, message: string): HttpError {
  return new HttpError(402, "limit", message, { reason });
}

export const notFound = (what = "video") => new HttpError(404, "not_found", `That ${what} doesn't exist.`);
export const badRequest = (message: string) => new HttpError(400, "bad_request", message);

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    const body: Record<string, unknown> = { error: error.code, message: error.message, ...error.extra };
    return json(body, error.status);
  }
  console.error("[api] unhandled", error);
  return json({ error: "server_error", message: "Something went wrong on our side. Try again." }, 500);
}

// Runs a route body and turns thrown HttpErrors (and anything else) into the contract's error JSON.
export async function run(fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (error) {
    unstable_rethrow(error); // let Next's own signals (prerender bail-out, redirects) through
    return errorResponse(error);
  }
}

export async function readJson<T extends object = Record<string, unknown>>(req: Request, maxBytes = 64_000): Promise<T> {
  const text = await req.text();
  if (text.length > maxBytes) throw new HttpError(413, "too_large", "The request body is too large.");
  if (!text.trim()) return {} as T;
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw badRequest("The body must be JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw badRequest("The body must be a JSON object.");
  return value as T;
}

// Small validators. They throw 400 with a message a person can act on.
export const is = {
  uuid: (v: unknown): v is string =>
    typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v),
  str: (v: unknown): v is string => typeof v === "string",
  num: (v: unknown): v is number => typeof v === "number" && Number.isFinite(v),
  bool: (v: unknown): v is boolean => typeof v === "boolean",
  slug: (v: unknown): v is string => typeof v === "string" && /^[0-9A-Za-z]{10}$/.test(v),
};

export function requireUuid(v: unknown, field = "id"): string {
  if (!is.uuid(v)) throw badRequest(`${field} must be a UUID.`);
  return v.toLowerCase();
}

export function clientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return req.headers.get("x-real-ip") || "0.0.0.0";
}

// Mutations authenticated by cookie (the web dashboard) must come from our own pages.
export function assertSameOrigin(req: Request): void {
  const origin = req.headers.get("origin");
  if (!origin) return;
  const host = req.headers.get("x-forwarded-host") || req.headers.get("host");
  try {
    if (new URL(origin).host === host) return;
  } catch {
    // fall through
  }
  throw new HttpError(403, "forbidden_origin", "This request must come from snapreel.video.");
}
