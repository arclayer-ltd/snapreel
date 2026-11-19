# snapreel.video (site and push relay)

The snapreel.video home page (`public/`) and a tiny Vercel function that ends Snapreel's Lock Screen Live Activity when a screen recording
stops while Snapreel is suspended (locking the phone, the red status pill, Control Centre).
Only the app can end its own Live Activity, and iOS suspends Snapreel soon after you leave it,
so the broadcast extension posts here and this sends Apple's ActivityKit push (`event: end`).

- Endpoint: `POST https://snapreel.video/api/live-activity` (see `api/live-activity.js`). The app falls back to
  `https://snapreel-push.vercel.app/api/live-activity`; some mobile carriers can't reach that address.
- Health: `GET /api/health`.
- Vercel project `snapreel-push` on the arclayer team (`dev-34969213`), deployed with the CLI from a copy
  of this folder outside git. Domains: snapreel.video and www.snapreel.video.
- DNS at Hostinger (snapreel.video, registered 2026-11-20): A @ 216.198.79.1 and 76.76.21.21, CNAME www
  cname.vercel-dns.com. Not Vercel's 64.29.17.x: the owner's carrier can't reach those. Mail records
  (MX, SPF, DKIM, DMARC) are Hostinger email's.
- Secrets live only in the Vercel project: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8`
  (Apple Push key "Arclayer Push", Production, team scoped). Never commit them.
- Without network the app falls back to its 30-second background grace and the card's
  15-minute stale date.
