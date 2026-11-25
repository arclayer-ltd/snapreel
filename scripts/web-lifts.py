#!/usr/bin/env python3
"""The one picture the "Your phone. Your files." glass pieces need (web/components/marketing/glass-pieces.tsx): the
thumbnail of the library row "Feedback on the onboarding copy", cut from the app's screenshot.

    python scripts/web-lifts.py      # writes web/public/marketing/lifts/thumb-feedback.webp
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web/public/marketing/lifts"
ROW = (14, 470, 361, 579)  # pt: a rough box around the row in lib.videos
THUMB = (12, 12, 132, 79.5)  # pt, inside the row's card


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img = np.asarray(Image.open(ROOT / "art/web/screens/light/lib.videos.png").convert("RGB"))
    x0, y0, x1, y1 = (v * 3 for v in ROW)
    box = img[y0:y1, x0:x1]
    away = np.abs(box.astype(int) - box[1, 1].astype(int)).max(-1) > 5
    ys, xs = np.where(away)
    l, t = int(xs.min()), int(ys.min())
    a, b, c, d = (round(v * 3) for v in THUMB)
    thumb = Image.fromarray(box[t + b : t + d, l + a : l + c])
    thumb.save(OUT / "thumb-feedback.webp", quality=82, method=6)
    print(thumb.size)


if __name__ == "__main__":
    main()
