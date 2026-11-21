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

The CI simulator is a notch-era iPhone (375 x 812 pt), where content and sheets start right under a 44 pt
status bar; inside the 16 Pro frame the Dynamic Island would sit on them. `scripts/web_island.py` moves every
screen's content (and every flow video's) 12 pt down, as on a real Dynamic Island iPhone, keeping the status
bar where it is. `web-screens.py` and `web-flows.py` both apply it.

Pieces of the app lifted out beside a phone (the "Your phone. Your files." panel) are cut from the same
screenshots by `scripts/web-lifts.py` into `web/public/marketing/lifts/` with `lifts-manifest.ts`, so they are
exactly the app's, in Light and Dark. The Copy link scene's lifted comments show the commenter's initial,
as the app does (a viewer comments with a name only).

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

The simulator has no camera, so in camera mode the app shows a still photo
(`Snapreel/Debug/fixture-camera-portrait.jpg`) and the preview never moves. `web-flows.py` makes the camera
flow live: `flows/camera-live.mp4` is a 6 s talking clip of the same woman made from that photo (Higgsfield
Grok Video 1.5, 480p, 15 credits), and each frame's overlay (timer, buttons, the countdown's dim and 3-2-1) is
recovered against the still and laid over the clip, which plays forward and back so it never jumps.

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

The nature in the home hero, the Copy link scene, the rooftop (pricing page and "Three ways to record"), the
footer and the inner-page banner moves like a park on a breezy day: clouds sail across the sky, birds fly,
trees sway and their leaves flutter, flowers bob, the kite sways and its tail ripples, the pond ripples,
the balloon wanders, butterflies flutter between flowers, and at dusk the lamps, the lantern, the bike's
headlight and the string lights glow and flicker (with a few fireflies and twinkling stars). The pictures
above stay the source. `web/components/marketing/scene-motion.tsx` lays a Three.js canvas exactly over a
scene's picture, under the phone, the cards and the text; `scene-motion-engine.ts` is the 2.5D stage (an
orthographic camera and textured planes, no 3D model).

- The base is the picture the page already shows (`img.currentSrc`). Where something that moves was painted
  in, a clean plate shows instead and the element is drawn again as a sprite cut from the same art, at the
  same place, so the canvas's first frame equals the picture and its fade-in can't be seen. Everything
  starts at rest and eases in.
- Trees and flowers are **pieces**, each with its own pivot, pace and phase. A tree's crown, with its
  branches, turns as one rigid piece about a point low on its trunk (so its top moves most and the foot of
  the trunk hardly at all); the tree line is split into clumps that each sway about their own foot, smaller
  and quicker the smaller they are; every flower is a stem that bends from the soil, so its head bobs,
  a little out of step with its neighbours. The engine works out each piece's angle every frame: it leans
  with a gust that travels left to right (reaching one tree after the other) and rocks at its own pace. The
  shader draws the picture turned back by its piece's angle; where two pieces touch they blend. Nothing
  waves or ripples inside a crown. On top, leaves flutter: a small, quick shake in leaf-clump-sized patches,
  only in a band along the crowns' edges, stronger in a gust.
- A piece's hold on a pixel falls to zero towards anything that must not move, over more than the
  distance that pixel can move (2.5 times it next to a character or an authored object, 1.2 times next to
  a lamp post or a bench), so nothing still is ever reached. Only the pale skyline far behind the tree
  line gives way by a few pixels where a tree's edge sways across it.
- The home hero's round flower bed is the scene's foreground cut-out, drawn in front of the phone. It gets
  a second, transparent canvas over it (made by `scene-motion.tsx` inside `.mk-scene-fg`), drawn by the same
  engine with the same pieces in the same frame, so the tulips in front of the phone sway and the layer
  under the phone always agrees with them. It takes the cut-out picture's place in one go once its first
  frame, equal to the picture, is drawn.
- Clouds and birds are in a sky layer that tree crowns hide. Every cloud sails with the wind, left to
  right, the bigger ones faster, and comes in again from the left once it is out of sight. So each cloud
  sprite is made whole: where a tree hid part of it, it is carried on in rounded lobes; where the
  picture's edge cut it, it is closed with its own mirror image. Travelling clouds keep to the scene's
  `cloudBand`, clear of everything that is not sky or tree. The two painted birds glide off; after that,
  flocks of two to five, drawn in code with flapping wing frames, cross every 20 to 60 seconds along the
  scene's lanes, which keep clear of the headline.
- The pond is covered whole: ripples wobble its reflections sideways, the surface shimmers and glints run
  along the ripples in short dashes.
- The kite's body is a cut-out; its two ribbons are drawn in code along the painted centre lines and
  ripple as a travelling wave. The balloon is a cut-out that wanders slowly around where it was painted.
  Lamps and the string lights' bulbs only exist in the Dusk data; a bulb sways with the branch it hangs in.
- Motion is layered sines with periods that don't divide into each other plus random events, seeded per
  load, so nothing visibly repeats for minutes.

`art/web/motion.json` holds the authored regions per scene, in fractions of the source picture: single
trees (`poly` around the crown, `pivot` low on the trunk, `sway` in source pixels at the crown's far end),
stretches of tree line (a `poly` with no pivot; `split` sets how fine the clumps are), flower beds (boxes;
`soil` or `stem` says where the stems start), boxes around characters and objects that must not move,
boxes around the painted clouds, birds, kite, balloon and butterflies, the pond, lamp points, boxes around
string lights and bird lanes. `scripts/web-motion.py` turns them into, in `web/public/marketing/motion/`:

- `{scene}-seg.webp` (one for both themes): which piece a pixel belongs to, its neighbouring piece, how
  much of the neighbour it takes, and the leaf flutter. The pieces themselves (pivot, angle, stem, pace)
  are in the manifest. Flower heads are found by colour, and a head counts whole when any part of it is
  near leaves (a big tulip's middle is far from its leaves; counted only along its rim it stayed still).
  Leaves with no flower get a piece per `cell`.
- `{scene}-{theme}-mask.webp`: R how much of its piece's sway a pixel takes, G water, B the sky layer
  (hidden, open or cut out).
- `{scene}-{theme}-plate.webp`: the clean plate (a smooth sky fitted around each cut-out, as the kite
  eraser does, or inpainted grass).
- `{scene}-{theme}-atlas.webp`: the cut-outs.

That is about 250 KB per scene and theme, none of it in the first paint, plus
`web/components/marketing/motion-manifest.ts`. The script also writes review pictures to `review/motion/`:
`{scene}-masks.jpg` (every piece in its own colour with a dot at its pivot, flutter whitened, water blue,
cut-outs magenta, still things outlined yellow), `{scene}-{theme}-plate.jpg` (the art with everything cut
out) and the atlases. After changing a region, look at those: no colour may touch a character, a face, a
phone or a building edge, and every tree and flower should have one. The script prints the largest weight
on still pixels (must be 0) and how far the rest frame is from the picture. Given the same art and
`motion.json` it writes the same files.

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
