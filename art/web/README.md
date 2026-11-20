# Website art (snapreel.video)

The marketing site is an illustrated world, after the owner's "Resolve" reference: full-bleed scenes of
one sunny city park (sky, clouds, a stylised skyline, lawns, flowers, a red kite and a red bench) with
Snapreel's five characters living in it, and real iPhones standing in the scenes. Dark mode shows the same
places at dusk. Below the scenes the page is calm: white cards, pastel tiles and small red label pills.
Red is the only accent.

| Folder or file | What it is |
|---|---|
| `gen2/` | The ten Higgsfield scenes (Light and Dusk of hero, features, pricing, footer and the inner-page banner), high-quality WebP. The site's art is made from these. |
| `gen/` | Round 1's six cut-out characters for the old red-field site. Not used by the site any more; kept as source art. |
| `credits.md` | Every generation, its job ID and credits (round 2: 43.50 of the 80 allowed). |
| `refs-crops/` | The character crops from `art/characters/lineup.png` uploaded as references. |
| `screens.json` | The scene slots. Drives `scripts/web-compose.py`. |
| `screens/` | The app screenshots the site's iPhones show, Light and Dark (`light/`, `dark/`), copied from CI runs (the Pro screens from run r31, the rest from build 40, run 44708462842). Drives `scripts/web-screens.py`. |
| `og.html` | Source of `web/app/(marketing)/opengraph-image.jpg` and `twitter-image.jpg`. |
| `review/` | Full-page review screenshots of every page at 390 and 1440 px, Light and Dark (`{page}-{width}-{scheme}.jpg`), and `compose/` previews of each phone and scene. |

## The iPhone

Since the owner's review of 20 Nov 2026 ("make it a real iPhone, upright, prominent"), every phone on the site
is one component, `web/components/marketing/iphone.tsx`: an iPhone 16 Pro drawn in CSS (`.mk-iphone` in
`marketing.css`), front on and upright, with a titanium band (natural in Light, black in Dark), the black
bezel, Dynamic Island, the side keys and a soft, layered shadow, all sized in `cqw` so it scales to any width.
`<PeekPhone>` is the same phone rising out of the bottom of a tile.

An app screenshot only ever appears inside that iPhone, and a Light page only shows Light screenshots, a Dark
page Dark ones. `scripts/web-screens.py` exports them (AVIF and WebP, 400 and 800 px) to
`web/public/marketing/screens/` with `screens-manifest.ts`, and makes the logo and favicons from the app icon.
The two player screens are composites: the fixture's grey diagram video is replaced by the camera recording
from `rec.camera.recording`, with the player's own controls, reactions and timeline lifted off the screenshot
and laid back on top.

The old 3D phone renders (`kind: "iphone"` in `scripts/web-compose.py`) are no longer used.

## Scenes

Kind `scene` exports a scene's Light and Dusk images as AVIF (WebP fallback up to 1920 px) at the page's
widths, plus:

- `mobile`: a centre crop for screens under 1024 px (art direction through `<source media>`), so a phone
  sees the characters next to the iPhone rather than a thin strip;
- `foreground`: a cut-out that sits in front of the phone. The hero's round flower bed is found by
  flood-filling the paving in from the box edges; the inked outline stops the fill, so the flowers and the
  stone rim come out clean in both Light and Dusk;
- the colour along the middle of the top edge, which the page uses as the sky above the picture.

Spots (the guide-card and 404 illustrations) are just scene crops (`wide` box), so they cost no credits.

On the page (`web/components/marketing/art.tsx`, `.mk-scene` in `marketing.css`), a scene section draws
its sky colour, puts the headline on it, and tucks the picture up under the text (`--tuck` on phones,
`--tuck-d` on wide screens) so the characters start just below the buttons. The home hero and the inner-page
strip banner are "cover" scenes on wide screens: a set height, the picture anchored to the bottom with no
fade, so the hero's headline sits in the picture's own sky. The hero's kite, which ran through the one-line
headline, was painted out with `scripts/web-hero-erase-kite.py` (originals in git history).

## Running it

Run from the repo root (Pillow with AVIF, numpy and OpenCV):

```
python scripts/web-compose.py                       # every scene (several minutes)
python scripts/web-compose.py scene-hero --preview  # some slots, with previews in review/compose/
python scripts/web-screens.py --preview             # the phone screens, the logo and the favicons
```

Outputs go to `web/public/marketing/art/` and `web/components/marketing/art-manifest.ts`.

## Other scripts

- `node scripts/web-review.mjs http://localhost:3000` captures every page at 390 and 1440 px in Light and
  Dark over the DevTools protocol (headless Edge or Chrome) and reports horizontal overflow and images that
  failed to load. `--shot <url> <out.png> <w> <h>` captures a single viewport (used for the OG image). In
  Git Bash, prefix it with `MSYS_NO_PATHCONV=1` when you pass page paths such as `/`.
- `node scripts/web-sync-content.mjs` snapshots `Snapreel/Features/Help/help-articles.json` and
  `docs/legal/*.md` into `web/components/marketing/content-snapshot.ts`. The site reads the live files at
  build time when the whole repo is present and falls back to this snapshot for a deploy made from `web/`.
