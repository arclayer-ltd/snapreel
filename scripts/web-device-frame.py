#!/usr/bin/env python3
"""Make the site's iPhone frame from a rendered iPhone 16 Pro (art/web/device/iphone-16-pro-render.png).

The render (Higgsfield, GPT Image 2.6, job 5a94f1a2-99bd-4af0-b39b-99c84faafac3) is a front view of an
iPhone 16 Pro in Natural Titanium on a transparent background. Its screen came out half transparent with a
green fringe, so this script keeps only the titanium band, the buttons and the black bezel, cuts an exact,
anti-aliased screen opening (a rounded rectangle measured off the bezel's inner edge), and keeps the
Dynamic Island as a clean black pill. The page puts the app screen under the opening
(web/components/marketing/iphone.tsx) and this frame on top.

    python scripts/web-device-frame.py        # writes web/public/marketing/iphone-frame-{600,1200}.webp

The numbers printed at the end are the CSS geometry (percent of the frame) used by .mk-iphone.
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/web/device/iphone-16-pro-render.png"
OUT = ROOT / "web/public/marketing"

CROP = (130, 30, 2030, 3812)  # the phone with its buttons, in the 2160 x 3840 render
SCREEN = (227, 107, 1931, 3738)  # x0, y0, x1, y1 of the screen opening (bezel's inner edge)
RADIUS = 260  # the opening's corner radius, px
ISLAND = (832, 159, 1326, 308)  # the Dynamic Island's box
SS = 4  # supersampling for the masks


def rounded_rect_mask(size, box, radius, ss=SS):
    w, h = size
    x0, y0, x1, y1 = box
    yy, xx = np.mgrid[0 : h * ss, 0 : w * ss].astype(np.float32)
    xx = (xx + 0.5) / ss
    yy = (yy + 0.5) / ss
    cx = np.clip(xx, x0 + radius, x1 - radius)
    cy = np.clip(yy, y0 + radius, y1 - radius)
    inside = ((xx - cx) ** 2 + (yy - cy) ** 2 <= radius**2) & (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
    m = inside.reshape(h, ss, w, ss).mean(axis=(1, 3))
    return m


def main() -> None:
    im = np.asarray(Image.open(SRC).convert("RGBA")).astype(np.float32)
    H, W, _ = im.shape
    alpha = im[..., 3] / 255.0

    # The phone's silhouette: everything not connected to the image corners through transparent pixels.
    outside = alpha < 0.5
    lab, _ = ndimage.label(outside)
    out = np.isin(lab, [lab[0, 0], lab[0, W - 1], lab[H - 1, 0], lab[H - 1, W - 1]])
    body = ndimage.binary_fill_holes(~out)
    # Keep the render's own soft edge on the outside, solid inside.
    edge = ndimage.binary_dilation(body, iterations=2) & ~ndimage.binary_erosion(body, iterations=2)
    a = np.where(body, 1.0, 0.0)
    a = np.where(edge, alpha, a)

    hole = rounded_rect_mask((W, H), SCREEN, RADIUS)
    x0, y0, x1, y1 = ISLAND
    island = rounded_rect_mask((W, H), ISLAND, (y1 - y0) / 2)
    rgb = im[..., :3].copy()
    # The island: the render's own pixels (black, with the lens), forced dark where the green fringe leaked.
    leak = (rgb[..., 1] > rgb[..., 0] + 30) & (rgb[..., 1] > rgb[..., 2] + 30)
    rgb[leak & (island > 0)] = 0
    a = a * (1 - hole) + island * hole
    # The bezel next to the opening is black; clean any green spill there too.
    near = ndimage.binary_dilation(hole > 0, iterations=40) & (hole < 1)
    spill = near & leak
    rgb[spill] = 4

    frame = np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(frame, "RGBA").crop(CROP)
    for w in (600, 1200):
        h = round(img.height * w / img.width)
        img.resize((w, h), Image.LANCZOS).save(OUT / f"iphone-frame-{w}.webp", quality=90, method=6)
    img.save(ROOT / "art/web/device/iphone-frame.png", optimize=True)

    cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
    sx0, sy0, sx1, sy1 = SCREEN
    print(f"frame {cw}x{ch}  aspect {cw}/{ch}")
    print(f"screen left {100 * (sx0 - CROP[0]) / cw:.3f}%  top {100 * (sy0 - CROP[1]) / ch:.3f}%  "
          f"width {100 * (sx1 - sx0) / cw:.3f}%  height {100 * (sy1 - sy0) / ch:.3f}%")
    print(f"screen radius {100 * RADIUS / (sx1 - sx0):.3f}% / {100 * RADIUS / (sy1 - sy0):.3f}%")
    print(f"island left {100 * (x0 - CROP[0]) / cw:.3f}%  top {100 * (y0 - CROP[1]) / ch:.3f}%  "
          f"width {100 * (x1 - x0) / cw:.3f}%  height {100 * (y1 - y0) / ch:.3f}%")


if __name__ == "__main__":
    main()
