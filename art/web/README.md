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
| `screens.json` | Slots, lighting presets and screenshot ids. Drives `scripts/web-compose.py`. |
| `screens/` | Screens that aren't in a CI run: the Pro screens (`light/`, `dark/`) and the old watch-page stand-in. |
| `og.html` | Source of `web/app/(marketing)/opengraph-image.jpg` and `twitter-image.jpg`. |
| `review/` | Full-page review screenshots of every page at 390 and 1440 px, Light and Dark (`{page}-{width}-{scheme}.jpg`), and `compose/` previews of each phone and scene. |

## The hard rule

An app screenshot only ever appears inside an iPhone, lit to match where it stands. `scripts/web-compose.py`
renders an iPhone 16 Pro in 3D (titanium frame with a machined edge gradient, side buttons, glass rim
highlight, Dynamic Island, glass sheen) at the slot's pose and casts its shadow. Each slot names a lighting
preset per mode:

| Preset | Where | Light |
|---|---|---|
| `day` | phones standing in the Light scenes | sun from the upper left, sky-blue fill on the frame, warm paving bounce, faint sky reflection in the glass, cool slate shadow |
| `dusk` | phones in the Dusk scenes | warm lamp light from the right, indigo fill, orange ground bounce, deep navy shadow |
| `golden` | the pricing rooftop, Light | warm late-afternoon light from the right, warm brown shadow |
| `studio`, `studio-dark` | phones on the pastel tiles | neutral soft light; Dark uses a cooler frame and a black shadow |

A Light scene shows the app's Light screenshot and a Dusk scene the Dark one; the page swaps them with
`<picture>` and `prefers-color-scheme`.

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
`--tuck-d` on wide screens) so the characters start just below the buttons. The inner-page strip banner is
the one "cover" scene: a set height, the picture anchored to the bottom.

## Running it

Run from the repo root (Pillow with AVIF, numpy and OpenCV):

```
python scripts/web-compose.py                       # every slot (about 15 minutes)
python scripts/web-compose.py phone-hero --preview  # some slots, with previews in review/compose/
python scripts/web-compose.py --light-dir <ci>/screenshots --dark-dir <ci>/dark/screenshots
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
