"""Fit the app's screenshots and flow recordings to the site's iPhone 16 Pro frame.

The CI simulator is a 375 x 812 pt notch-era iPhone: its status bar is 44 pt tall and a screen's content (or a
presented sheet) starts at about 42 pt. The site draws its screens inside an iPhone 16 Pro frame, whose Dynamic
Island reaches down to 44 pt, so without this the island sits on the first line of content and on the top edge
of every sheet (the Stats sheet's grabber, the Account and Help sheets). On a real Dynamic Island iPhone the
status bar is taller and content starts about 12 pt lower.

So, in 1125 x 2436 px (3x) terms:
  rows    0-100   status bar (time, signal, battery)     kept where it is (it already centres on the island)
  rows  100-126   empty status-bar background            stretched to 62 rows (a flat colour, or the paywall's
                                                         gentle gradient)
  rows  126-2334  the screen's content or sheet          moved 36 px (12 pt) down
  rows 2334-2370  top of the home-indicator area         dropped
  rows 2370-2436  the rest of the home-indicator area    kept
The screen keeps its size, so nothing else in the pipeline changes. Used by web-screens.py (stills) and
web-flows.py (videos).
"""
from __future__ import annotations

import numpy as np
from PIL import Image

H = 2436
BAR, BAND_END, SHIFT, SAFE = 100, 126, 36, 102  # px at 3x on a 2436 px tall screen


def _rows(h: int) -> tuple[int, int, int, int]:
    k = h / H
    return round(BAR * k), round(BAND_END * k), round(SHIFT * k), round(SAFE * k)


def fit_image(img: Image.Image) -> Image.Image:
    """The remap on a still (any width, 2436 px tall or proportional)."""
    a = np.asarray(img.convert("RGB"))
    h, w = a.shape[:2]
    bar, band_end, shift, safe = _rows(h)
    band = Image.fromarray(a[bar:band_end]).resize((w, band_end - bar + shift), Image.BICUBIC)
    out = np.concatenate([a[:bar], np.asarray(band), a[band_end : h - safe], a[h - safe + shift :]], axis=0)
    assert out.shape == a.shape, (out.shape, a.shape)
    return Image.fromarray(out)


def fit_filter(w: int, h: int, src: str = "in", dst: str = "out") -> str:
    """The same remap as an ffmpeg filtergraph fragment from [src] to [dst] (frames w x h)."""
    bar, band_end, shift, safe = _rows(h)
    content = h - safe - band_end
    tail = safe - shift
    return (
        f"[{src}]split=4[fa][fb][fc][fd];"
        f"[fa]crop={w}:{bar}:0:0[fa1];"
        f"[fb]crop={w}:{band_end - bar}:0:{bar},scale={w}:{band_end - bar + shift}:flags=bicubic[fb1];"
        f"[fc]crop={w}:{content}:0:{band_end}[fc1];"
        f"[fd]crop={w}:{tail}:0:{h - tail}[fd1];"
        f"[fa1][fb1][fc1][fd1]vstack=inputs=4[{dst}]"
    )
