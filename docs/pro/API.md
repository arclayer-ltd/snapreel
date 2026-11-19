# Snapreel Pro: shared contract

The one source of truth for the backend, the iPhone app, the watch page and dashboard, and the website.
If a session needs to change something here, it edits this file in the same commit and says so in its report.

Product rules (owner decisions, 20 November 2026):
- Local features stay free forever. Only hosted share links are paid.
- **Free:** 25 active links, each video up to 300 s, 720p on the web.
- **Pro:** unlimited links, up to 7,200 s, 1080p, insights detail, password, expiry, downloads on/off, call-to-action, branding, no badge.
- **Prices:** `co.arclayer.snapreel.pro.monthly` $5.99, `co.arclayer.snapreel.pro.yearly` $39.99 with a 1-week free trial. Subscription group "Snapreel Pro".
- **No AI features.** No server-side transcription, summaries or translation.
- Email goes through Resend from `snapreel.video`.

## Hosts

| What | Where |
|---|---|
| Website, watch pages, dashboard, API | `https://snapreel.video` (Vercel project `snapreel-push`, team `dev-34969213`). Next.js app in `web/` |
| Supabase | Project "Snapreel" (SourceBD org, us-east-1). The URL and publishable key go in the table below once created. Both are public values |
| Storage uploads (TUS) | `https://<ref>.storage.supabase.co/storage/v1/upload/resumable` |
| Lock Screen relay (unchanged; builds 31+ call it) | `POST /api/live-activity`, `GET /api/health` |

| Key | Value |
|---|---|
| `SUPABASE_URL` | _filled in by the backend session_ |
| `SUPABASE_PUBLISHABLE_KEY` | _filled in by the backend session_ |

Server-only secrets live in Vercel env and never in git:
- `SUPABASE_SECRET_KEY`
- `RESEND_API_KEY`
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8`
- `SIWA_KEY_ID`, `SIWA_KEY_P8`, `SIWA_CLIENT_IDS`
- `APPLE_BUNDLE_ID=co.arclayer.snapreel`, `APPLE_APP_ID` (numeric, 6836019517)
- `VIEWER_COOKIE_SECRET`

## Sign-in (Supabase Auth)

- Methods:
  - **email code**: 6 digits, sent through Resend SMTP;
  - **Sign in with Apple**: native in the app through `id_token`; OAuth on the web through the Services ID.
- **The app** talks to GoTrue directly with URLSession; no SDK is needed:
  - `POST /auth/v1/otp` `{email, create_user: true}`;
  - `POST /auth/v1/verify` `{type: "email", email, token}`;
  - `POST /auth/v1/token?grant_type=id_token` `{provider: "apple", id_token, nonce}`;
  - `POST /auth/v1/token?grant_type=refresh_token`;
  - `POST /auth/v1/logout`.
  - Every call sends the header `apikey: <publishable key>`. Tokens go in the Keychain, shared with no extension.
- **The web** uses `@supabase/ssr` with cookie sessions.
- Every owner call to our API sends `Authorization: Bearer <access_token>`. The server checks it with Supabase (`auth.getUser`).

## Database (Postgres, schema `public`)

`profiles`
- `id` uuid pk → `auth.users`
- `display_name` text
- `brand_color` text null (Pro)
- `brand_logo_path` text null (Pro)
- `created_at`

`subscriptions`
- `user_id` uuid pk
- `product_id`
- `original_transaction_id` unique
- `status`: active | in_grace | expired | revoked
- `expires_at`
- `environment`: Production | Sandbox
- `updated_at`

Only the server writes it.

`videos`
- `id` uuid pk; `owner_id`; `slug` text unique (10 characters, base62); `local_id` uuid (the phone's Video.id)
- `title`; `kind`: screen | camera | audio; `duration_s` numeric; `width` int; `height` int; `size_bytes` bigint
- `status`: uploading | ready | failed; `uploaded_bytes` bigint
- `transcript` jsonb null: `{locale, segments: [{start, duration, text}]}`
- `access`: link | password; `password_hash` null; `expires_at` null
- `allow_download` bool, default false; `allow_comments` bool, default true; `allow_reactions` bool, default true
- `cta` jsonb null: `{label, url}`
- `created_at`, `updated_at`, `deleted_at` null

`views`
- `id`; `video_id`; `session_id` text (cookie); `viewer_user_id` null; `viewer_name` null
- `country` (2 letters); `device`: phone | tablet | desktop; `referrer_host`
- `started_at`, `last_seen_at`; `watched_s`; `max_position_s`
- `buckets` bit(100), the parts of the video watched
- `counted` bool; `completed` bool

`comments`
- `id`; `video_id`; `session_id`; `author_user_id` null; `author_name`
- `body` (1 to 1,000 characters); `at_s` numeric null; `parent_id` null
- `created_at`, `deleted_at`

`reactions`
- `id`, `video_id`, `session_id`, `author_name` null, `emoji`, `at_s`, `created_at`

`blocks`
- `owner_id`, `session_id` null, `user_id` null, `created_at`

A blocked viewer can't comment or react on any of that owner's videos.

`reports`
- `id`, `video_id`, `reason`: spam | abuse | illegal | copyright | other
- `details`, `email` null, `created_at`, `resolved_at` null

`devices`
- `token` pk, `user_id`, `environment`, `app_version`, `created_at`, `last_seen_at`

`notification_log`
- `id`, `user_id`, `kind`, `video_id`, `dedupe_key` unique, `created_at`

**Row-level security** is on for every table.
- Owners may select, update and delete their own `videos`, and the `comments`, `reactions` and `views` on their videos.
- `anon` gets nothing. Public pages read through the server with the secret key.
- Storage bucket `videos` is private. Authenticated users may insert and update only under `videos/{auth.uid()}/…`.

## Storage layout

`videos/{userId}/{videoId}/`:
- `video.mp4`: H.264 and AAC, faststart. Made on the phone at 1280 (Free) or 1920 (Pro) on the long side.
- `poster.jpg`: 1280 on the long side.
- `preview.mp4`: 3 s, silent, 480 px wide, for email and link previews.

Viewers get signed URLs valid for 2 hours, issued after the access checks. Captions (WebVTT) are made by the server from `videos.transcript` at `/api/public/v/{slug}/captions.vtt`.

**Upload** uses TUS 1.0.0 with chunks of exactly 6 MB. Headers:
- `Authorization: Bearer <user token>`
- `apikey`
- `x-upsert: true`
- `Upload-Metadata`: bucketName, objectName, contentType, cacheControl=3600

When all three files are up, the app sends `PATCH /api/videos/{id} {status: "ready"}`. The server checks the objects exist before it accepts.

## API (Next.js route handlers in `web/app/api/`)

Bodies are JSON with camelCase keys. Errors look like `{error: "<code>", message}`. 402 means a plan limit: `{error: "limit", reason: "links" | "duration" | "pro_feature"}`.

### Owner endpoints (Bearer token)

| Method and path | Body | Returns |
|---|---|---|
| `GET /api/me` | | `{user: {id, email, displayName, emailAlerts, brandColor}, plan: {tier: "free"\|"pro", productId, expiresAt}, usage: {activeLinks, linkLimit, maxDurationS, quality}}` |
| `PATCH /api/me` | `{displayName?, brandColor?, emailAlerts?}` | the same as `GET` |
| `POST /api/videos` | `{localId, title, kind, durationS, width, height, sizeBytes, transcript?}` | 201 `{id, slug, url, status, upload: {bucket, videoPath, posterPath, previewPath}, limits: {maxDurationS, maxLongSide}}`. If the `localId` is already shared, returns the existing link with 200 |
| `GET /api/videos` | | `[VideoSummary]` |
| `GET /api/videos/{id}` | | `VideoDetail` |
| `PATCH /api/videos/{id}` | any of `{title, status, uploadedBytes, access, password, expiresAt, allowDownload, allowComments, allowReactions, cta, transcript}` | `VideoDetail` |
| `DELETE /api/videos/{id}` | | 204. Stops sharing, deletes the files, keeps nothing |
| `GET /api/videos/{id}/insights` | | `{views, uniqueViewers, avgPercent, completionRate, dropoff: [100 ints], countries: [{code, count}], viewers: [{name, anonymous, country, device, firstSeenAt, lastSeenAt, percent}]}`. Free gets `views` and `uniqueViewers`; the rest is `null` |
| `GET /api/videos/{id}/activity` | | `{comments: [Comment], reactions: [Reaction]}` |
| `DELETE /api/comments/{id}` | | 204 |
| `POST /api/blocks` | `{commentId}` or `{reactionId}` | 204. Blocks that viewer from all your videos |
| `POST /api/devices` | `{token, environment: "production"\|"sandbox", appVersion}` | 204 |
| `DELETE /api/devices/{token}` | | 204 |
| `POST /api/purchases/verify` | `{signedTransaction}` (StoreKit 2 JWS) | `{plan}`. The server checks the x5c chain to Apple Root CA G3, the bundle ID, and that `appAccountToken` equals the user ID |
| `POST /api/account/delete` | | 204. Deletes everything, including the auth user, and revokes Sign in with Apple |

Shapes:
- `VideoSummary`: `{id, slug, url, localId, title, kind, durationS, status, posterUrl, createdAt, views, uniqueViewers, lastViewedAt, commentCount}`
- `VideoDetail`: VideoSummary plus `{access, hasPassword, expiresAt, allowDownload, allowComments, allowReactions, cta, width, height, sizeBytes}`
- `Comment`: `{id, authorName, isOwner, body, atS, parentId, createdAt}`
- `Reaction`: `{id, emoji, atS, authorName, createdAt}`

### Public endpoints (no account; cookie `sr_vs` = signed random session ID)

| Method and path | Body | Returns |
|---|---|---|
| `GET /api/public/v/{slug}` | | `{title, kind, ownerName, brand: {color, logoUrl} \| null, durationS, width, height, status, uploadProgress, posterUrl, videoUrl, previewUrl, captionsUrl, transcript, allowDownload, allowComments, allowReactions, cta, showBadge, createdAt}`, or 401 `{error: "password"}`, or 410 `{error: "expired" \| "removed"}` |
| `POST /api/public/v/{slug}/unlock` | `{password}` | 204 and sets the `sr_unlock_{slug}` cookie (12 h) |
| `POST /api/public/v/{slug}/view` | `{event: "start"\|"progress"\|"end", positionS, watched: [bucketIndex]}` | `{viewId}`. Sent with `sendBeacon` on pagehide |
| `GET /api/public/v/{slug}/activity` | | `{comments, reactions}` |
| `POST /api/public/v/{slug}/comments` | `{name, body, atS, parentId?, website}`. `website` is a honeypot and must be empty | `Comment` |
| `POST /api/public/v/{slug}/reactions` | `{emoji, atS, name?}` | `Reaction` |
| `POST /api/public/v/{slug}/report` | `{reason, details, email?}` | 204 |
| `GET /api/public/v/{slug}/captions.vtt` | | `text/vtt` |
| `GET /api/oembed?url=…&format=json` | | `{type: "video", version: "1.0", title, provider_name: "Snapreel", provider_url, html, width, height, thumbnail_url, thumbnail_width, thumbnail_height, duration}` |

**A view counts** once it has 5 s watched, or 75% of the length, or reaches the last second. The owner's own views (signed-in owner) never count. Unique viewers are counted by `session_id`.

**Rate limits** per IP and session:
- comments: 5 a minute;
- reactions: 30 a minute;
- views: 60 a minute;
- reports: 5 an hour.

### Apple

- `POST /api/appstore/notifications`: App Store Server Notifications V2 (`signedPayload`). The server checks the chain and updates `subscriptions`. Used for production and sandbox.
- `GET /.well-known/apple-app-site-association`: `applinks` for `/v/*`, plus `webcredentials`. App ID `N3DBKUVJS5.co.arclayer.snapreel`.

### Push to the app (APNs alert, topic `co.arclayer.snapreel`, production)

```json
{"aps": {"alert": {"title": "Sam watched “Launch plan”", "body": "Watched 80%"}, "sound": "default", "thread-id": "<videoId>"},
 "sr": {"type": "view" | "comment" | "reaction" | "upload", "videoId": "<server id>", "localId": "<phone id>", "commentId": "<id>"}}
```

When pushes are sent:
- **view:** the first counted view by each new session;
- **comment:** every comment;
- **reaction:** batched, at most one per video every 10 minutes.

Each one also gets an email from Resend if the user hasn't turned email off. That setting lives in `profiles.email_alerts`, a boolean defaulting to true, which the backend adds.

`uploadProgress` on the public video is `uploaded_bytes / size_bytes` (0 to 1) while `status` is `uploading`, and `null` otherwise. The watch page polls `GET /api/public/v/{slug}` every 3 s while uploading and starts playing when it turns `ready`.

## Watch page routes (`web/app/`)

- `/v/{slug}`: watch page. `noindex`. Link-preview bots get OG and Twitter player tags plus oEmbed discovery.
- `/v/{slug}/embed`: the same player with no page around it, for iframes. The oEmbed `html` and `twitter:player` point here (`<iframe src="https://snapreel.video/v/{slug}/embed" allowfullscreen>`).
- `/v/preview/locked` and `/v/preview/generic`: 1200×630 PNG link-preview images for password videos and videos with no poster.
- `/app`: dashboard. `/app/v/{id}` is a video's insights, comments and settings. `/app/account` is account and plan.
- `/login`: email code and Sign in with Apple. Apple on the web returns to `/login/callback?next=…`, which exchanges the code for the cookie session; add `https://snapreel.video/login/callback` (and `http://localhost:3000/login/callback`) to Supabase Auth redirect URLs.
- `/`, `/pricing`, `/help`, `/help/{slug}`, `/privacy`, `/terms`, `/support`: the marketing site.

## Who owns which files (parallel sessions)

| Session | Owns | Must not edit |
|---|---|---|
| Backend | `supabase/**`, `web/app/api/**`, `web/lib/server/**`, `web/middleware.ts`, `web/app/.well-known/**`, `server/**` (removed once the relay is ported), Vercel env | app code, marketing pages |
| App | `Snapreel/**`, `Shared/**`, `SnapreelBroadcast/**`, `SnapreelLiveActivity/**`, `Snapreel.entitlements`, `Snapreel.xcodeproj/**` | `web/**` |
| Apple setup | App Store Connect, developer.apple.com, GitHub secrets, `.github/workflows/ios.yml` (signing lines only), `docs/pro/APPLE.md` | Swift code |
| Website | `web/app/(marketing)/**`, `web/components/marketing/**`, `web/public/marketing/**`, `art/web/**`, `scripts/web-*` | API, watch page, dashboard |
| Watch page and dashboard | `web/app/v/**`, `web/app/app/**`, `web/app/login/**`, `web/components/player/**`, `web/components/dashboard/**`, `web/lib/client/**` | API internals |

Shared and changed carefully: `web/app/layout.tsx`, `web/app/globals.css` (tokens), `web/lib/contract.ts` (these types), `web/package.json`. Add dependencies, and don't remove other sessions' dependencies.

## Session cookies on the web

The dashboard reads the Supabase session from cookies in Server Components, which can't write cookies. So `web/proxy.ts` (Next 16's name for middleware; backend-owned) refreshes the session on every request to `/app`, `/login` and `/v/*` with `@supabase/ssr`'s `createServerClient` and `auth.getClaims()`, copying refreshed cookies onto the response. Without it, an expired access token sends the owner back to `/login` (which signs them straight back in from the browser), and a server-side refresh could reuse a rotated refresh token.
