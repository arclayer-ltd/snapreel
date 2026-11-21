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

Every screen is fitted to the site's iPhone 16 Pro frame first (scripts/web_island.py): the CI simulator is a
notch-era iPhone, so content and sheets move 12 pt down to clear the Dynamic Island.

The flow-* stills are frames of the recorded app flows (scripts/web-flows.py writes them into
art/web/screens/); the page plays the flow's video over its still.

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
from PIL import Image

from web_island import fit_image

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
    # Stills of the recorded flows (scripts/web-flows.py), shown before and under their videos.
    "flow-share": {
        "id": "flow.share",
        "alt": "Snapreel on iPhone: a camera recording plays, then Copy link uploads it and the sheet says anyone with the link can watch in a browser",
    },
    "flow-comments": {
        "id": "flow.comments",
        "alt": "A shared recording playing in Snapreel, with viewers' comments and reactions at the moment they mean",
    },
    "flow-camera": {"id": "flow.camera", "alt": "Snapreel counting down, then recording with the front camera"},
    "flow-voice": {"id": "flow.voice", "alt": "Snapreel recording a voice memo, with its live waveform"},
    "flow-screen": {"id": "flow.screen", "alt": "Snapreel's three steps before a screen recording"},
    "library": {"id": "lib.videos", "alt": "The Snapreel library: recordings with titles, folders and tags"},
    "insights": {"id": "insights.pro", "alt": "A shared recording's stats in Snapreel Pro: 128 views, 64 unique viewers and where people stopped"},
    "paywall": {"id": "pro.paywall", "alt": "Snapreel Pro in the app: $39.99 a year with a week free, or $5.99 a month"},
    "account": {"id": "account.page.pro", "alt": "Snapreel's Account page with Snapreel Pro, shared links and Manage subscription"},
    "help": {"id": "help.home", "alt": "Snapreel's help centre in the app"},
}

def find(sid: str, mode: str) -> Path:
    for ext in (".png", ".webp"):
        p = SRC / mode / f"{sid}{ext}"
        if p.exists():
            return p
    raise SystemExit(f"missing screenshot {mode}/{sid} in {SRC}")


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
            bgs[mode] = hexcol(img.getpixel((SCREEN[0] // 2, 6)))
            # Content and sheets start 12 pt lower, below the 16 Pro frame's Dynamic Island (web_island.py).
            img = fit_image(img)
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
