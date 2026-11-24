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
| `video-prompts.md` | The prompts of the scenes' video loops (see Video loops). |
| `video-loops.json` | Each loop's length, its regions' cut points, energy dips and cloud drift. Written by `scripts/web-scene-video.py`. |
| `scene-nature.json` | What may move in each scene (see Video loops). |
| `held/` | The people and objects of each scene, which never move: 1-bit masks at the pictures' outlines, half size, the same for Light and Dusk. |
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

## Video loops

Only nature moves (the owner's rule, 23 Nov 2026): wind in the trees, flowers and grass, drifting clouds, birds,
butterflies, water, fireflies and leaf shadows. The people, what they wear and hold, animals on the ground, bicycles,
the kite, the plane, the balloon, lamps, string lights, benches and buildings are the still picture in every frame.
Each scene picture in `gen2/`, Light and Dusk, was animated by an image-to-video model starting from the picture
(MiniMax H3 on Higgsfield, 2K; 8 s with the picture as first and last frame, or 10 s from the first frame only for
the three clips redone in round 8b; the choice, job IDs and credits are in `credits.md`, the prompts in
`video-prompts.md`). The people move in those clips; `scripts/web-scene-video.py` shows only their nature. The camera
is locked off, so the art stays where the page's phones and cards expect it.
This replaced a hand-written Three.js sway layer (round 4 to 7), which the owner found looked like trees under
water.

`scripts/web-scene-video.py <folder of raw clips>` makes the files in `web/public/marketing/video/` and
`web/components/marketing/video-manifest.ts`:

- each clip back in its picture's exact shape (the 3:2 hero went to the model stretched to 16:9 and is squeezed
  back), its colours matched to the still frame by frame, so the fade from picture to video can't be seen;
- the still everywhere but in the nature (round 9). `scene-nature.json` says where a scene's clip may show at all
  (polygons around crowns, beds, bushes, water, birds, shadows; tree lines in front of buildings count only where
  they are plant-coloured), and within that only what moves shows, with soft edges. `held/<scene>.png` (the people and
  objects, at the still's outlines; the same for Light and Dusk) is laid over everything from the still. So leaves
  and flowers move right up to and behind a character who doesn't. Outside the nature a file is the still, resampled
  straight from the picture. A new scene, or a character in a new place, needs both files updated;
- a loop without a calm. The model eases into and out of its keyframes, and a tree lulls at each end of its sway.
  Every separate piece of nature gets its own loop, all of one length (at least 4.5 s): cut where the two ends match
  best in picture and in motion, and turned round so the pieces' lulls don't fall together. The ends are joined over
  0.5 s by a morph, not a crossfade: the optical flow between the two frames, both ways (OpenCV DIS), slides each pose
  towards the other before they are blended. Birds fade over. Loop points, lengths and energy dips are in
  `video-loops.json`;
- no jump at the wrap. Each file starts at one of its own quietest steps (of the quietest fiftieth, the one whose
  picture is nearest the still), so the decoder's jump back to the first frame lands where the picture barely moves;
- clouds that drift instead of shimmering. Inside each cloud box (`CLOUDS` in the script) the video's sky and
  clouds are replaced by a clean sky plate (the still with its clouds painted out over a fitted sky gradient)
  and the still's own clouds, drifting 8 px (on a 1440 px page) over each loop: copy A moves 0 to +D and fades
  out while copy B moves -D to 0 and fades in, so the end equals the start. A cloud is carried on sideways under
  the tree it meets and mirrored past the picture's edge, so no copy shows a cut. Whatever the video shows as
  leaf, trunk or bird stays on top, so swaying branches still pass over the clouds. Lamp heads, the rooftop
  lantern, the string lights, the footer's kite and the characters right under a cloud (a cream sleeve, or skin at
  dusk, has a cloud's colour) are protected boxes;
- the same cuts as the pictures (`screens.json`): wide (1920 px), the phone crop (720 px; the inner-page banner,
  which has none, whole at 960 px) and every spot cut from the same picture (480 px);
- H.264 MP4, no AV1 (at these sizes AV1's big blocks recoded bits of the people next to moving leaves). Each file is one keyframe and then predicted frames: at these bitrates a keyframe is sharper
  than the frames before it, and the usual keyframe every 4 s showed as a pulse, also at the loop seam. For
  the same reason the keyframe and the last frame have to be coded alike, or the picture jumps at the wrap. H.264 is
  two-pass (the raw frames tagged BT.709, or ffmpeg shifts the colours): the first encode's keyframe is decoded, every
  never-moving pixel is set to exactly that, and the last 24 frames, which get more bits, carry the keyframe's own
  coding error, fading in; the second encode uses the same first-pass statistics, so it makes the same keyframe.
  `video-limits.json` holds a size ceiling per file (round 8b's sizes, and up to 1.6 times that for the inner-page banner and three spots, where fewer bits made held edges shimmer).

On the page (`web/components/marketing/scene-video.tsx`, `.mk-scene-video` in `marketing.css`) a scene gets a
muted, looping, inline `<video>` exactly over its `<picture>`, under the phone, the cards and the text. The
picture is the poster and the fallback and stays the first paint and the LCP: the video starts loading only after
the page has loaded and gone idle, only for a scene near the viewport, and fades in once it plays. It plays only
while on screen in a visible tab, follows Light/Dark and the phone crop (fading out, swapping the file and fading
back in), and with `prefers-reduced-motion: reduce` or Save-Data there is no video at all. The hero's front
flower bed, the cut-out drawn in front of the phone, is redrawn every frame from the same video on a small canvas
masked by the cut-out, so the tulips in front of the phone move with the rest of the bed.

The raw clips (8 to 12 MB each) are not in the repo; download them again from the job IDs in `credits.md`.

## Running it

Run from the repo root (Pillow with AVIF, numpy and OpenCV):

```
python scripts/web-compose.py                       # every scene (several minutes)
python scripts/web-compose.py scene-hero --preview  # some slots, with previews in review/compose/
python scripts/web-screens.py --preview             # the phone screens, the logo and the favicons
python scripts/web-scene-video.py <raw clips>        # the video loops (about half an hour)
python scripts/web-scene-video.py <raw clips> scene-footer   # or some
```

Outputs go to `web/public/marketing/art/` and `web/components/marketing/art-manifest.ts`. Run
`web-scene-video.py` again whenever a scene's phone crop, its foreground box or a spot changes; new source art
needs new loops.

## Other scripts

- `node scripts/web-review.mjs http://localhost:3000` captures every page at 390 and 1440 px in Light and
  Dark over the DevTools protocol (headless Edge or Chrome) and reports horizontal overflow and images that
  failed to load. `--shot <url> <out.png> <w> <h>` captures a single viewport (used for the OG image). In
  Git Bash, prefix it with `MSYS_NO_PATHCONV=1` when you pass page paths such as `/`.
- `node scripts/web-sync-content.mjs` snapshots `Snapreel/Features/Help/help-articles.json` and
  `docs/legal/*.md` into `web/components/marketing/content-snapshot.ts`. The site reads the live files at
  build time when the whole repo is present and falls back to this snapshot for a deploy made from `web/`.
