#!/usr/bin/env python3
"""Export the app screens the website shows inside its iPhone, and the app icon the site uses as its logo.

The iPhone itself is drawn in CSS (web/components/marketing/iphone.tsx, .mk-iphone in marketing.css). This
script only prepares what goes on its glass: real Snapreel screenshots, Light and Dark, as AVIF with a WebP
fallback at two widths. The page swaps Light and Dark with prefers-color-scheme, so a Light page only ever
shows Light screens and a Dark page Dark ones.

Run from the repo root (Pillow with AVIF, numpy):

    python scripts/web-screens.py                 # every screen, the icons and the manifest
    python scripts/web-screens.py --preview       # also writes JPEG previews to art/web/review/screens/

Sources: art/web/screens/{light,dark}/{id}.png (or .webp). Add a screen by copying the CI screenshot
(`gh run download <run> -n snapreel-ci`, files under screenshots/ and dark/screenshots/) into those folders
and adding an entry to SCREENS.

Two screens are composites: the player screens ("player-ready", "player-comments") show the camera
recording from rec.camera.recording instead of the CI fixture's grey diagram video. The player's own
controls, reactions and timeline are lifted off the screenshot with a colour-to-alpha against the
fixture video's flat grey (which is uniform everywhere except the diagram) and laid back over the new
frame; the sheet's dimming is applied to the new frame too, so nothing but the video changes.

Outputs:
    web/public/marketing/screens/{slug}-{light|dark}-{width}.{avif|webp}
    web/components/marketing/screens-manifest.ts
    web/public/marketing/app-icon-{64,128,192}.webp       (nav and footer logo)
    web/app/favicon.ico, web/app/icon.png, web/app/apple-icon.png
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/web/screens"
OUT = ROOT / "web/public/marketing/screens"
MANIFEST = ROOT / "web/components/marketing/screens-manifest.ts"
ICON = ROOT / "Snapreel/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
PREVIEW = ROOT / "art/web/review/screens"

WIDTHS = [400, 800]
SCREEN = (1125, 2436)  # the CI simulator, 375 x 812 pt at 3x

# slug: screenshot id, alt text, optional composite.
SCREENS: dict[str, dict] = {
    "player-ready": {
        "id": "share.link.ready",
        "face": True,
        "alt": "Snapreel on iPhone: a camera recording with viewers' reactions on its timeline, and the Link copied sheet saying anyone with the link can watch in a browser",
    },
    "player-comments": {
        "id": "share.link.comments",
        "face": True,
        "alt": "A shared recording in Snapreel with emoji reactions and viewers' comments at the moment they mean",
    },
    "rec-screen": {"id": "rec.shell.screen", "alt": "Snapreel's recorder set to Screen, with the red record button"},
    "rec-camera": {"id": "rec.camera.recording", "alt": "Snapreel recording with the front camera, 1 minute 23 in"},
    "rec-voice": {"id": "rec.review.audio", "alt": "A voice recording in Snapreel, with its waveform"},
    "library": {"id": "lib.videos", "alt": "The Snapreel library: recordings with titles, folders and tags"},
    "insights": {"id": "insights.pro", "alt": "A shared recording's stats in Snapreel Pro: 128 views, 64 unique viewers and where people stopped"},
    "paywall": {"id": "pro.paywall", "alt": "Snapreel Pro in the app: $39.99 a year with a week free, or $5.99 a month"},
    "account": {"id": "account.page.pro", "alt": "Snapreel's Account page with Snapreel Pro, shared links and Manage subscription"},
    "help": {"id": "help.home", "alt": "Snapreel's help centre in the app"},
}

# --- The player composite ---------------------------------------------------------------------------
# All rows in full-resolution screenshot pixels.
VIDEO_TOP, VIDEO_BOTTOM = 130, 954  # the player's video area (the timeline panel starts at 954)
WIPE = (470, 866)  # rows holding the fixture's diagram, its touch dot and the centre play/skip buttons
BAR_EDGE = (284, 352)  # where the control bar's scrim stops, under its buttons
FIXTURE_GREY = 224.0  # the fixture video's flat background, undimmed
FACE_BOX = (30, 300, 1095, 1094)  # the part of the camera feed in rec.camera.recording to show


def find(sid: str, mode: str) -> Path:
    for ext in (".png", ".webp"):
        p = SRC / mode / f"{sid}{ext}"
        if p.exists():
            return p
    raise SystemExit(f"missing screenshot {mode}/{sid} in {SRC}")


def colour_to_alpha(region: np.ndarray, bg: float) -> tuple[np.ndarray, np.ndarray]:
    """Split pixels drawn over a flat grey `bg` into (colour, alpha), GIMP-style: least alpha that explains them."""
    o = region.astype(np.float64)
    up = (o - bg) / (255.0 - bg)
    down = (bg - o) / bg
    a = np.where(o > bg, up, down).max(axis=-1).clip(0, 1)
    a3 = a[..., None]
    c = (o - bg * (1 - a3)) / np.maximum(a3, 1e-6)
    return c.clip(0, 255), a


def face_frame(mode: str) -> np.ndarray:
    cam = Image.open(find("rec.camera.recording", "light")).convert("RGB")
    crop = cam.crop(FACE_BOX)
    w, h = SCREEN[0], VIDEO_BOTTOM - VIDEO_TOP
    # cover the video area, centred
    scale = max(w / crop.width, h / crop.height)
    big = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    x = (big.width - w) // 2
    y = (big.height - h) // 2
    return np.asarray(big.crop((x, y, x + w, y + h))).astype(np.float64)


def compose_player(img: Image.Image, mode: str) -> Image.Image:
    arr = np.asarray(img.convert("RGB")).astype(np.float64).copy()
    # The flat grey just under the diagram, as shown (a presented sheet dims everything behind it).
    bg = float(arr[760, 20, 0])
    dim = bg / FIXTURE_GREY
    region = arr[VIDEO_TOP:VIDEO_BOTTOM]
    colour, alpha = colour_to_alpha(region, bg)
    lo, hi = WIPE[0] - VIDEO_TOP, WIPE[1] - VIDEO_TOP
    # Inside the wiped band only the player's own scrim survives: take each row's scrim from the
    # screen's left edge (x = 3), which the diagram never reaches, and drop everything else.
    alpha[lo:hi] = alpha[lo:hi, 3:4]
    colour[lo:hi] = colour[lo:hi, 3:4]
    # The control bar's scrim ends in a hard edge, which crossed the face; ease it over 60 rows (below the
    # buttons, so only the scrim changes).
    e0, e1 = BAR_EDGE[0] - VIDEO_TOP, BAR_EDGE[1] - VIDEO_TOP
    top, bottom = alpha[e0].copy(), alpha[e1].copy()
    for r in range(e0, e1):
        t = (r - e0) / (e1 - e0)
        t = t * t * (3 - 2 * t)
        alpha[r] = top * (1 - t) + bottom * t
        colour[r] = 0.0
    frame = face_frame(mode) * dim
    a3 = alpha[..., None]
    arr[VIDEO_TOP:VIDEO_BOTTOM] = frame * (1 - a3) + colour * a3
    return Image.fromarray(arr.clip(0, 255).round().astype(np.uint8))


# --- Export -----------------------------------------------------------------------------------------

def save(img: Image.Image, slug: str, mode: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for w in WIDTHS:
        h = round(img.height * w / img.width)
        small = img.resize((w, h), Image.LANCZOS)
        small.save(OUT / f"{slug}-{mode}-{w}.avif", quality=64, speed=4)
        small.save(OUT / f"{slug}-{mode}-{w}.webp", quality=84, method=6)


def hexcol(rgb) -> str:
    return "#%02x%02x%02x" % tuple(int(v) for v in rgb[:3])


def icons() -> None:
    src = Image.open(ICON).convert("RGB")
    # Logo in the nav and footer: the square icon; the page rounds it with CSS.
    for s in (64, 128, 192):
        src.resize((s, s), Image.LANCZOS).save(ROOT / f"web/public/marketing/app-icon-{s}.webp", quality=92, method=6)
    # Favicon and icon.png: the icon in its iOS shape (a continuous-corner squircle) on transparent.
    def masked(size: int) -> Image.Image:
        k = 4
        n = 5.0  # superellipse exponent close to the iOS icon outline
        big = size * k
        yy, xx = np.mgrid[0:big, 0:big]
        u = np.abs((xx + 0.5) / big * 2 - 1)
        v = np.abs((yy + 0.5) / big * 2 - 1)
        inside = (u**n + v**n) <= 1.0
        m = Image.fromarray((inside * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
        im = src.resize((size, size), Image.LANCZOS).convert("RGBA")
        im.putalpha(m)
        return im
    fav = [masked(s) for s in (16, 32, 48)]
    fav[2].save(ROOT / "web/app/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)], append_images=fav[:2])
    masked(512).save(ROOT / "web/app/icon.png", optimize=True)
    # iOS draws its own mask on a home-screen icon, so apple-icon stays square and opaque.
    src.resize((180, 180), Image.LANCZOS).save(ROOT / "web/app/apple-icon.png", optimize=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("slugs", nargs="*")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--no-icons", action="store_true")
    args = ap.parse_args()

    manifest: dict[str, dict] = {}
    for slug, spec in SCREENS.items():
        bgs = {}
        for mode in ("light", "dark"):
            img = Image.open(find(spec["id"], mode)).convert("RGB")
            if img.size != SCREEN:
                raise SystemExit(f"{spec['id']} ({mode}) is {img.size}, expected {SCREEN}")
            if spec.get("face"):
                img = compose_player(img, mode)
            bgs[mode] = hexcol(img.getpixel((SCREEN[0] // 2, 6)))
            if not args.slugs or slug in args.slugs:
                save(img, slug, mode)
                if args.preview:
                    PREVIEW.mkdir(parents=True, exist_ok=True)
                    img.resize((563, 1218), Image.LANCZOS).save(PREVIEW / f"{slug}-{mode}.jpg", quality=86)
                print(f"{slug} {mode}")
        manifest[slug] = {"alt": spec["alt"], "bg": bgs}

    lines = [
        "/* Generated by scripts/web-screens.py: the app screens shown inside the site's iPhone. Don't edit by hand. */",
        "",
        f"export const SCREEN_WIDTHS = {json.dumps(WIDTHS)} as const;",
        f"export const SCREEN_SIZE = {{ width: {SCREEN[0]}, height: {SCREEN[1]} }} as const;",
        "",
        "export const screens = {",
    ]
    for slug, m in manifest.items():
        lines.append(f"  {json.dumps(slug)}: {{")
        lines.append(f"    alt: {json.dumps(m['alt'])},")
        lines.append(f"    bg: {{ light: {json.dumps(m['bg']['light'])}, dark: {json.dumps(m['bg']['dark'])} }},")
        lines.append("  },")
    lines += ["} as const;", "", "export type ScreenSlug = keyof typeof screens;", ""]
    MANIFEST.write_text("\n".join(lines), encoding="utf-8")

    if not args.no_icons:
        icons()
        print("icons")


if __name__ == "__main__":
    main()
