# Higgsfield credits for the website art

> **No longer used (25 Nov 2026).** The scene videos listed below (rounds 8 to 10) were dropped by the owner: the site
> shows the still pictures. Their files, scripts, masks and prompts (`video-prompts.md`, `web-scene-video.py`,
> `scene-nature.json`, `held/`) are in git history, last in 5c533e8. The entries stay as the record of what was spent.

## Round 2: the illustrated-world redesign (2026-11-20)

Budget: at most 80 credits. Balance before the first generation: 2,986.34 (stop at 2,906.34).

Model for every image: `gpt_image_2_6` (GPT Image 2.6). References: `art/characters/lineup.png` and the five crops in
`art/web/refs-crops/` (uploads and `media_confirm` cost nothing). Dusk versions use the Light version as their
first reference so the composition stays put. Raw downloads are in `art/web/gen2/raw/`.

| # | Scene | Quality | Job ID | Credits | Kept |
|---|---|---|---|---|---|
| 1 | Hero, style test | medium 2k 3:2 | 1eabfda5-6d03-4063-879b-95eaf2beea31 | 1.00 | as the layout reference for #2 |
| 2 | Hero, Light (park plaza) | high 4k 3:2 | 1199d6ab-cb08-4d80-80c2-63c5979cff11 | 4.25 | yes |
| 3 | Hero, Dusk | high 4k 3:2 | f944dcb7-35e3-4a91-b4d7-27fe62e20519 | 4.25 | yes |
| 4 | Features, Light (meadow path, dog) | high 4k 16:9 | 6e9a63fa-204e-41d6-9835-12ea38084c91 | 4.25 | yes |
| 5 | Pricing, Light (rooftop terrace) | high 4k 16:9 | e4ef37e0-cf68-4a15-ba51-2918416a2ad2 | 4.25 | yes |
| 6 | Footer, Light (hilltop picnic, all five) | high 4k 21:9 | 2faaa0b2-056d-4bb0-9fa8-a4349d76ea73 | 4.25 | yes |
| 7 | Inner pages, Light (skyline banner) | high 4k 21:9 | aee14ba2-c59b-4f1e-8787-95d39c9728a1 | 4.25 | yes |
| 8 | Features, Dusk | high 4k 16:9 | 03e628b3-588c-4d76-a929-1356f00886bf | 4.25 | yes |
| 9 | Pricing, Dusk | high 4k 16:9 | a582a6ad-9f81-478a-88a5-53c52f11403d | 4.25 | yes |
| 10 | Footer, Dusk | high 4k 21:9 | 4f26b35f-14aa-4f03-a6ba-339d3fe239ad | 4.25 | yes |
| 11 | Inner pages, Dusk | high 4k 21:9 | ec3da122-1113-45fc-9d2b-c1a8c915dee1 | 4.25 | yes |

**Total: 43.50 credits of the 80 allowed** (balance after: 2,942.84). No retries: every scene was kept first time.
The spot illustrations on the guide cards and the 404 page are crops of these scenes, so they cost nothing.

## Round 1: the red-field site (2026-11-20)

Budget: at most 60 credits. Balance before the first generation: 3,002.84.

Model for every image: `gpt_image_2_6` (GPT Image 2.6), quality `high`, resolution `2k`, transparent background,
one character crop from `art/characters/lineup.png` as the reference (crops in `art/web/refs-crops/`).
Uploads and `media_confirm` cost nothing.

| # | Date | Scene | Character | Job ID | Credits | Kept |
|---|---|---|---|---|---|---|
| 1 | 2026-11-20 | Hero: phone handed to the viewer, thumbs-up | c1 hoodie | 0b4418c5-d1f8-4165-9540-b3b6eae00f7f | 2.75 | yes |
| 2 | 2026-11-20 | Jump, open palm at the viewer | c4 varsity | dd1e4f21-ffd1-448e-b772-83f6db31bb45 | 2.75 | yes |
| 3 | 2026-11-20 | Run with a phone | c3 headphones | 2b0ba02a-c593-45aa-8601-5659c36585f9 | 2.75 | yes |
| 4 | 2026-11-20 | Points at a laptop (watch page) | c2 bucket hat | 4368783f-2bcb-4e59-982c-8b5c0d7a304f | 2.75 | yes |
| 5 | 2026-11-20 | Celebrates (Pro) | c5 beanie | eff6c97c-753e-4c0e-ba09-16b0348149e6 | 2.75 | yes |
| 6 | 2026-11-20 | Group shot for the footer, 21:9 | all five | e9af427c-7e59-4a56-b5fb-be6c056ff4fd | 2.75 | yes |

**Total: 16.50 credits of the 60 allowed.** Every image was kept; no retries were needed.

Cut-outs came straight from the model's transparent background, so `remove_background` and `rembg` were not needed.

## Round 5 (owner's second review, 21 Nov 2026)

| What | Model | Job IDs | Credits | Kept |
|---|---|---|---|---|
| Two made-up commenters' faces, two variants each, for the lifted comments | GPT Image 2.6, 1:1 | 84e4e189, a4929c12, e1354b3a, f7e3774d | 3.00 | no: the owner then chose letter avatars, as in the app |
| Camera mode live preview: 6 s talking clip from `fixture-camera-portrait.jpg` (`flows/camera-live.mp4`) | Grok Video 1.5, 480p, 9:16 | af690827-23a6-4ff0-860a-70b48741f0aa | 15.00 | yes |

**Round 5 total: 18.00 credits.**

## Round 8: AI video loops instead of the code animation (23 Nov 2026)

The owner judged the Three.js sway layer a failure (trees "under water", lamps moving with the trees, boring
clouds) and asked for AI-generated motion, cheaply. Limit: about 250 Higgsfield credits, existing credits only.
Balance before: 2,194.84. kie.ai had 4 credits, so it was not used.

**Model test (hero Light only), each with the picture as both first and last frame:**

| Model | Settings | Job ID | Credits | Verdict |
|---|---|---|---|---|
| Outpaint (to widen the 3:2 hero to 16:9) | 16:9 | 11c998a6-cc14-449c-a82b-fb3d20f7308b | 2 | not used: it repainted the scene; the hero is stretched to 16:9 instead and squeezed back |
| Kling 3.0 Omni Frames (`kling_o3_flf`) | pro 1080p, 8 s | a00ce6fc-5c38-4207-bfc7-77f91d8d7b7e | 10 | rock steady but almost nothing moves (one waving hand) |
| Hailuo 02 (`minimax_hailuo`, variant `minimax`) | 1080p, 6 s | 7bccf6a7-2c68-452e-a927-ace02b84fd48 | 10 | camera shakes by about 3 px, adds butterflies, people move too much |
| **MiniMax H3** (`minimax_h3`) | 2K, 8 s | cd97d372-3d42-4504-b398-8fbb4bf605cb | 16 | **chosen**: 2560 px, under 1 px drift, trees and flowers sway as whole branches and stems, lamps and buildings rigid, people keep their faces; kept as the hero Light loop |

Hailuo 2.3 can't take a last frame. Seedance 2.5 costs 35 credits for 5 s at 720p (80 at 1080p), too dear for ten
clips; Seedance 2.0 fast is 20 for 8 s at 1080p.

**The loops (MiniMax H3, 2K, 8 s, start = end = the scene picture; 16:9, the footer and banner 21:9):**

| Scene | Job ID | Credits |
|---|---|---|
| Hero, Light | cd97d372-3d42-4504-b398-8fbb4bf605cb (the test) | (16) |
| Hero, Dusk | edc145e9-3dfe-403d-aae4-a3249facf9ac | 16 |
| Features (Copy link), Light | 888c50d7-f2c9-4ddf-87ed-314d56ac1ed3 (first try 74f18d62 was wrongly flagged and refunded) | 16 |
| Features, Dusk | c4650cb9-160f-4674-a59f-a0be4cb84b42 | 16 |
| Pricing / rooftop, Light | 3213e46f-d5b6-4733-8c37-5b3c70d80fae | 16 |
| Pricing / rooftop, Dusk | 0142e4f5-d4f7-4e56-915a-6fcec589628e | 16 |
| Footer, Light | 2c2f1264-a971-4804-bd3a-9b1fa872ac1a | 16 |
| Footer, Dusk | 93285610-6fb8-4ec4-927b-7e73298d73f1 | 16 |
| Inner pages, Light | 7a55609e-db26-4127-8370-c7d48b426348 | 16 |
| Inner pages, Dusk | 081dc773-abe4-41d0-af88-5b64cf7f6b1e | 16 |

**Round 8 total: 182 credits** (38 for the tests and the outpaint, 144 for the nine other loops). The spots are
cut from the same loops, so they cost nothing. The prompts are in `video-prompts.md`.

## Round 8b: no calm at the loop point, clouds that drift (23 Nov 2026)

The owner asked to fix the calm pause at each loop point and the shimmering clouds. Limit: 100 Higgsfield
credits without asking. Seven loops were re-cut from the round 8 clips at no cost. Three clips had no 4.5 s
stretch of steady motion and were made again with MiniMax H3, 2K, 10 s, the scene picture as first frame only
(the loop is now made by a crossfade, so no last frame is needed); prompts in `video-prompts.md`:

| Scene | Why | Job ID | Credits |
|---|---|---|---|
| Pricing / rooftop, Light | motion died down after 4 s | c7003d44-1405-4714-9849-4b0ff153e173 | 20 |
| Footer, Dusk | motion died down after 4 s | d1aabd7c-d1ea-4005-96ff-60bcdb22c7dd | 20 |
| Inner pages, Light | rhythmic lull every 1.5 s | d51f09ec-d14c-4a6f-8659-6fc7d5f5d9f7 | 20 |

**Round 8b total: 60 credits.** The clouds are composited from the stills in `scripts/web-scene-video.py`, so
they cost nothing.

## Round 9: only nature moves (23 Nov 2026)

The owner's rule: "make sure the charecter dosen't animate only the nature". The people and objects are the still
picture in every frame; the nature comes from the round 8 and 8b clips (round 8c, which morphed the moving characters
at the loop point, was never finished). Limit: 200 Higgsfield credits without asking.

**Round 9 total: 0 credits.** Nothing was generated: see Video loops in `README.md`, `scene-nature.json` and `held/`.

## Round 10: Seedance 2.5 (25 Nov 2026)

The owner found round 9's motion unnatural (patches of plants moving beside frozen ones; the tulips in front of the
phone cut with a fixed stencil) and asked for every loop to be made again with Seedance 2.5, at 720p, about 350 credits.

What the model needs (Higgsfield `seedance_2_5`, mode `omni_reference`, the picture as `start_image` and `end_image`, no
audio): `aspect_ratio: auto` keeps the picture exactly (scale 1.000); a forced 16:9, or draft mode, redraws and
reframes it. With `auto`, 720p failed every time (six tries, refunded), so the clips are 480p and
`scripts/web-scene-video.py` puts the picture's own line work back.

| What | Job ID | Credits | Kept |
|---|---|---|---|
| Hero Light test: draft, "everything else frozen" | 66da271a-2f73-487c-aee7-5c7119e216b2 | 18 | no, hardly any wind, reframed |
| Hero Light test: draft, strong wind, first frame only | 46bfc237-57e4-4ebc-945b-d7061a202f63 | 18 | no, redrawn |
| Hero Light test: 480p, 4 s, `auto` | 2b564fd2-7525-481a-82bc-8a4acaa3086b | 12 | no, replaced |
| Hero Light, 720p, 16:9 | 38de67dc-3293-4edb-a3e2-46499425138a | 35 | no, redrawn |
| Hero, Light | 18f4bd8c-1d4d-4c8e-86aa-407cefb1a73c | 15 | yes |
| Hero, Dusk | 4d17483b-2509-48b6-936a-4e9c0a29099d | 15 | yes |
| Features, Light | 2c55b9db-f1d3-4b68-bfcb-393da941a40b | 15 | no, calms down |
| Features, Light | 19605b96-782d-4f7d-b930-32931e5eb2b5 | 15 | yes |
| Features, Dusk | 9e7e6f62-e161-4688-9909-c4be822b3d30 | 15 | no, wind ribbons |
| Features, Dusk | 08814f85-a36e-4d3d-852d-dc20a01c90b3 | 15 | yes |
| Pricing / rooftop, Light | f4ea9d7b-3053-486c-b3fd-059409afdb50 | 15 | yes |
| Pricing / rooftop, Dusk | 7a1601e1-2410-4086-aadf-3f36b484688f | 15 | yes |
| Footer, Light | 32505b81-638b-445b-930f-e3b270c60e42 | 15 | no, wind ribbons |
| Footer, Light | 1d6ca0d2-e7ab-4c22-87c8-429acf402024 | 15 | yes |
| Footer, Dusk | edab2844-f86b-4848-a928-285dc660c28e | 15 | yes |
| Inner pages, Light | c313b5aa-4b10-405d-b041-183aba673059 | 15 | yes |
| Inner pages, Dusk | 88eda631-7938-451d-8a68-534739201e1e | 15 | yes |

**Round 10 total: 278 credits** (48 for the first tests, 230 after the owner's go).
