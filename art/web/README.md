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
| `motion.json` | What moves in each scene (see Motion). Drives `scripts/web-motion.py`. |
| `screens/` | The app screenshots the site's iPhones show, Light and Dark (`light/`, `dark/`), copied from CI runs (the Pro screens from run r31, the rest from build 40, run 44708462842). Drives `scripts/web-screens.py`. |
| `og.html` | Source of `web/app/(marketing)/opengraph-image.jpg` and `twitter-image.jpg`. |
| `review/` | Full-page review screenshots of every page at 390 and 1440 px, Light and Dark (`{page}-{width}-{scheme}.jpg`), and `compose/` previews of each phone and scene. |

## The iPhone

Every phone on the site is one component, `web/components/marketing/iphone.tsx`: a rendered iPhone 16 Pro
frame in Natural Titanium (`device/iphone-16-pro-render.png`, Higgsfield GPT Image 2.6, cut into
`web/public/marketing/iphone-frame-{600,1200}.webp` by `scripts/web-device-frame.py`), upright and front on,
laid over the app's screen, with a soft, layered shadow in the body's shape. `<PeekPhone>` is the same phone
rising out of the bottom of a tile.

An app screen only ever appears inside that iPhone, and a Light page only shows the app in Light, a Dark page
in Dark. `scripts/web-screens.py` exports the stills (AVIF and WebP, 400 and 800 px) to
`web/public/marketing/screens/` with `screens-manifest.ts`, and makes the logo and favicons from the app icon.

## Recorded flows

Where a phone has a `flow`, it plays a recording of the real app over its still: the hero (a camera
recording plays, Copy link, the link uploads, Ready to watch), the Copy link scene (a shared recording with
viewers' comments) and the three recorder tiles (screen steps, camera countdown and timer, voice waveform).

1. `Snapreel/Debug/DebugFlows.swift` scripts each flow (`flow.*` debug screens): the app's own views, driven
   through the same state changes taps and a live recording make. The desk camera fixture plays a real
   talking clip (`Snapreel/Debug/fixture-camera-desk.mp4`, Debug builds only).
2. `gh workflow run ios.yml --ref <branch> -f screenshots=false -f flows=flow.` records them on the simulator,
   Light and Dark (`RECORD=1` in `scripts/ci-screenshots.sh`), into the `snapreel-ci` artifact.
3. `python scripts/web-flows.py <downloaded artifact>` trims each from when its screen appeared, makes it
   600 px H.264 with a crossfade back to its first frame (a seamless loop), and writes a still per mode to
   `art/web/screens/`; then `python scripts/web-screens.py` exports the stills.

On the page (`flow-video.tsx`) a flow plays muted and inline only while it is on screen, fades in over its
still, and never plays with reduced motion.

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

## Motion

The nature in the home hero, the Copy link scene, the footer and the inner-page banner moves: clouds drift,
birds fly, trees and flowers sway in gusts that cross the scene from the left, the kite sways and its tail
ripples, the pond shimmers, butterflies flutter between flowers, and at dusk the lamps, the lantern and the
bike's headlight glow and flicker (with a few fireflies and twinkling stars). The pictures above stay the
source. `web/components/marketing/scene-motion.tsx` lays a Three.js canvas exactly over a scene's picture,
under the phone, the cards and the text; `scene-motion-engine.ts` is the 2.5D stage (an orthographic camera
and textured planes, no 3D model).

- The base is the picture the page already shows (`img.currentSrc`). Where something that moves was painted
  in, a clean plate shows instead and the element is drawn again as a sprite cut from the same art, at the
  same place, so the canvas's first frame equals the picture and its fade-in can't be seen. Everything
  starts at rest and eases in.
- Wind is a displacement shader on the picture, driven by a sway weight mask: crowns move most at their
  tips, flower beds less, and the weight falls to zero towards anything solid (trunks, characters, benches,
  lamps, buildings, the hero's foreground flower bed), so no character or building edge ever moves.
- Clouds and birds are in a sky layer that tree crowns hide. Clouds stay around where they were painted
  (one cut by the picture's edge only leans out towards it). The two painted birds glide off; after that,
  flocks of two to five, drawn in code with flapping wing frames, cross every 20 to 60 seconds along the
  scene's lanes, which keep clear of the headline.
- The kite's body is a cut-out; its two ribbons are drawn in code along the painted centre lines and
  ripple as a travelling wave. Lamps only exist in the Dusk data.
- Motion is layered sines with periods that don't divide into each other plus random events, seeded per
  load, so nothing visibly repeats for minutes.

`art/web/motion.json` holds the authored regions per scene, in fractions of the source picture: tree crowns
(`poly`, with the `anchor` where the trunk holds them), flower beds, boxes around characters and objects
that must not move, boxes around the painted clouds, birds, kite and butterflies, the pond, lamp points and
bird lanes. `scripts/web-motion.py` turns them into `web/public/marketing/motion/{scene}-{theme}-`
`mask.webp` (R sway weight, G water, B sky layer: hidden, open or cut out), `plate.webp` (the clean plate:
a smooth sky fitted around each cut-out, as the kite eraser does, or inpainted grass) and `atlas.webp` (the
cut-outs), about 100 KB per scene and theme, plus `web/components/marketing/motion-manifest.ts`. It also
writes review pictures to `review/motion/`: `{scene}-masks.jpg` (sway red, water blue, cut-outs magenta,
solid things outlined yellow, authored boxes white), `{scene}-{theme}-plate.jpg` (the art with everything
cut out) and the atlases. After changing a region, look at those: nothing red may touch a character, a
face, a phone or a building edge. The script prints the largest sway weight on still pixels (must be 0)
and how far the rest frame is from the picture.

On the page the layer costs nothing up front. Three.js (its own chunk) and the scene's data load only after
the page has loaded and gone idle, and only for a scene near the viewport, so the picture stays the first
paint and the LCP. It draws only while the scene is on screen in a visible tab, at a capped pixel ratio
(phones: fewer things and 30 frames a second), and rebuilds with a short fade when the theme or the crop
changes. With `prefers-reduced-motion: reduce` there is no canvas and nothing is downloaded; without WebGL,
or if anything fails, the picture simply stays.

## Running it

Run from the repo root (Pillow with AVIF, numpy and OpenCV):

```
python scripts/web-compose.py                       # every scene (several minutes)
python scripts/web-compose.py scene-hero --preview  # some slots, with previews in review/compose/
python scripts/web-screens.py --preview             # the phone screens, the logo and the favicons
python scripts/web-motion.py                        # the motion data for every scene (a few minutes)
python scripts/web-motion.py scene-footer           # or some
```

Outputs go to `web/public/marketing/art/` and `web/components/marketing/art-manifest.ts`. Run `web-motion.py`
after `web-compose.py` whenever a scene's source art, its phone crop or its foreground box changes (it also
needs scipy).

## Other scripts

- `node scripts/web-review.mjs http://localhost:3000` captures every page at 390 and 1440 px in Light and
  Dark over the DevTools protocol (headless Edge or Chrome) and reports horizontal overflow and images that
  failed to load. `--shot <url> <out.png> <w> <h>` captures a single viewport (used for the OG image). In
  Git Bash, prefix it with `MSYS_NO_PATHCONV=1` when you pass page paths such as `/`.
- `node scripts/web-sync-content.mjs` snapshots `Snapreel/Features/Help/help-articles.json` and
  `docs/legal/*.md` into `web/components/marketing/content-snapshot.ts`. The site reads the live files at
  build time when the whole repo is present and falls back to this snapshot for a deploy made from `web/`.
