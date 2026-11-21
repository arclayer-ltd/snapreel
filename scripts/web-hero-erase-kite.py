#!/usr/bin/env python3
"""Paint the red kite out of the home hero's sky (art/web/gen2/hero-{light,dark}.webp), in place.

Since the site review of 20 Nov 2026 the hero's headline sits on one line in the picture's own sky, and the
kite and its ribbons ran through the first word. The kite floats on open sky in both versions, so it is
filled with a smooth model of the surrounding sky (a low-order polynomial fitted to the sky pixels around
it) plus grain matched to the sky's own. The originals are in git history (commit 0532e43).

    python scripts/web-hero-erase-kite.py && python scripts/web-compose.py scene-hero
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BOX = (380, 110, 790, 420)  # x0, y0, x1, y1 around the kite, in the 3504 x 2336 source
SKY = (330, 60, 1000, 470)  # where the sky model is fitted


def feats(x, y):
    x = (x - 665) / 400
    y = (y - 265) / 250
    return np.stack([np.ones_like(x), x, y, x * x, y * y, x * y, y**3], -1)


def erase(path: Path) -> None:
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    x0, y0, x1, y1 = BOX
    sub = im[y0:y1, x0:x1]
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    red = (r > g + 45) & (r > b + 25)
    # The tree's leaves have warm rims at dusk: only the kite's body (right) and ribbons (low) count.
    yy, xx = np.mgrid[y0:y1, x0:x1]
    red &= (xx >= 600) | (yy >= 255)
    red = cv2.morphologyEx(red.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    mask = cv2.dilate(red, np.ones((3, 3), np.uint8), iterations=7)

    X0, Y0, X1, Y1 = SKY
    big = im[Y0:Y1, X0:X1]
    sky = (big[..., 2] > big[..., 0] + 25) & (big[..., 2] > big[..., 1] + 8)
    mbig = np.zeros(sky.shape, np.uint8)
    mbig[y0 - Y0 : y1 - Y0, x0 - X0 : x1 - X0] = mask
    sky &= ~cv2.dilate(mbig, np.ones((15, 15), np.uint8)).astype(bool)
    gy, gx = np.mgrid[Y0:Y1, X0:X1].astype(np.float64)
    A = feats(gx[sky], gy[sky])
    F = feats(gx, gy)
    model = np.zeros_like(big)
    grain = []
    for c in range(3):
        coef, *_ = np.linalg.lstsq(A, big[..., c][sky], rcond=None)
        model[..., c] = F @ coef
        grain.append(np.std(big[..., c][sky] - A @ coef))
    fill = model[y0 - Y0 : y1 - Y0, x0 - X0 : x1 - X0]
    noise = np.random.default_rng(3).normal(0, 1, fill.shape[:2])[..., None] * np.array(grain) * 0.8
    soft = cv2.GaussianBlur(mask.astype(np.float64), (0, 0), 2.0)[..., None]
    im[y0:y1, x0:x1] = sub * (1 - soft) + (fill + noise) * soft
    Image.fromarray(im.clip(0, 255).round().astype(np.uint8)).save(path, quality=96, method=6)
    print(path.name)


if __name__ == "__main__":
    for mode in ("light", "dark"):
        erase(ROOT / f"art/web/gen2/hero-{mode}.webp")
