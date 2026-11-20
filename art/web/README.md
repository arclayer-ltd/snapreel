# Website art (snapreel.video)

The marketing site's look is the owner's "Aurea" style reference rebuilt in Snapreel red: one saturated
field (wine vignette, red mid-tones, coral light pools, a faint grid and light beams), white four-point
sparkles, motion strokes and loops, and the five Snapreel characters redrawn semi-3D and cel-shaded.

| Folder or file | What it is |
|---|---|
| `gen/` | The six Higgsfield images (transparent backgrounds). Phones and the laptop have flat #00FF00 screens. Lossless WebP where there's a screen, high-quality WebP otherwise. |
| `credits.md` | Every generation, its job ID and credits (16.5 of the 60 allowed). |
| `refs-crops/` | The character crops from `art/characters/lineup.png` that were uploaded as references. |
| `screens.json` | Slot → screenshot id. Drives `scripts/web-compose.py`. |
| `screens/` | Screens that aren't CI screenshots: the watch-page stand-in for the laptop (`watch-page.html`, rendered to `light/` and `dark/web.watch.png`). |
| `og.html` | Source of `web/app/(marketing)/opengraph-image.jpg`. |
| `review/` | Full-page review screenshots of every page at 390 and 1440 px, Light and Dark (`{page}-{width}-{scheme}.jpg`), and `compose/` previews of each composite on red. |

## The hard rule

An app screenshot only ever appears inside an iPhone, lit to look like the app is running on it.
`scripts/web-compose.py` does that:

- **Kind `art`** (a character holding a phone or laptop): finds the green screen quad (outer-envelope edge
  fit, so fingers over the screen can't pull an edge in), warps the screenshot in with rounded corners, adds
  the Dynamic Island, a thin black glass edge, an inner edge shadow, a glass sheen and a warm-red bounce,
  matches the art's edge softness and grain, keeps fingers and loops in front with a chroma-key unmix, and
  drops wine shadows of the hand and device onto the field.
- **Kind `iphone`** (no hands): renders an iPhone 16 Pro in 3D at the slot's pose (titanium frame with a
  machined edge gradient, side buttons, glass rim highlight) and casts a soft long shadow.
- Every slot with a screen is made with the Light and the Dark screenshot; the page swaps them with
  `<picture>` and `prefers-color-scheme`.

Outputs go to `web/public/marketing/art/` (AVIF and WebP, 1x and 2x) and
`web/components/marketing/art-manifest.ts` (sizes and paths). Run from the repo root:

```
python scripts/web-compose.py                    # every slot (about 10 minutes)
python scripts/web-compose.py hero pro --preview # some slots, with previews in review/compose/
python scripts/web-compose.py --light-dir <ci>/screenshots --dark-dir <ci>/dark/screenshots
```

## When the Pro screens exist

These slots use today's best screen as a stand-in. When CI photographs the Pro screens, change `screen` to
the `swapTo` id in `screens.json` and re-run the script for those slots (the ids below are the planned
ones; use whatever ids the app's debug screens end up with):

| Slot | Today | Swap to |
|---|---|---|
| `hero` | `video.player` | `share.link.ready` |
| `run-link` | `rec.review` | `share.link.ready` |
| `insights` | `video.details` | `insights.overview` |
| `comments` | `notif.feed` | `comments.thread` |
| `pro` | `home.filled` | `pro.paywall` |
| `support` | `settings.root` | `account.root` |
| `watch-laptop` | `web.watch` (stand-in page) | a 1440x900 capture of the real watch page, saved as `screens/{light,dark}/web.watch.png` |

## Other scripts

- `node scripts/web-review.mjs http://localhost:3000` captures every page at 390 and 1440 px in Light and
  Dark over the DevTools protocol (headless Edge or Chrome) and reports horizontal overflow and images
  that failed to load. `--shot <url> <out.png> <w> <h>` captures a single viewport (used for the OG image).
- `node scripts/web-sync-content.mjs` snapshots `Snapreel/Features/Help/help-articles.json` and
  `docs/legal/*.md` into `web/components/marketing/content-snapshot.ts`. The site reads the live files at
  build time when the whole repo is present and falls back to this snapshot for a deploy made from `web/`.
