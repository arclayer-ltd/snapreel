"""Video loops for the site's illustrated scenes (web/components/marketing/scene-video.tsx).

Each scene picture in art/web/gen2/ (Light and Dusk) was animated by an image-to-video model (Seedance 2.5,
480p, 5 s; prompts and job IDs in art/web/credits.md and video-prompts.md). This script turns those raw clips into
the files the page plays:

- resampled to the picture's exact shape (the hero is 3:2 and went to the model stretched to 16:9, so it is
  squeezed back here) and matched to the still's colours;
- at the picture's own sharpness: the fine detail of every frame is the still's, slid along the optical flow between
  the frame and the still (detail);
- only nature moves: the people and objects of art/web/held/ (and the `hold` boxes of art/web/scene-nature.json) are the
  still in every frame, what strays out of their outlines in the clip is replaced by the still's background, and
  where the clip doesn't move at all the file is the still too;
- looped: a clip starts and ends on the same picture, and its last CLOSE_XF frames run into the first;
- clouds that drift instead of shimmering: inside each cloud box of CLOUDS the video's sky and clouds are
  replaced by a clean sky plate (the still with its clouds painted out) and the still's own clouds, drifting
  over one loop with a seamless crossfade (copy A moves 0 to +D and fades out, copy B moves -D to 0 and fades
  in). Clouds are carried on sideways under the trees they meet and mirrored past the picture's edge, so a
  drifted copy never shows a cut. Every pixel the video shows as tree, trunk or bird stays the
  video's, so swaying branches still pass over the clouds;
- cut like the pictures (art/web/screens.json): the wide frame, the phone crop (`mobile`; a scene without one
  is shown whole on phones, at phone size) and every spot cut from the same picture;
- encoded as H.264 MP4, muted, one keyframe per file (at these
  bitrates a keyframe comes out sharper than the frames before it, which showed as a pulse with the usual GOP);
- listed in web/components/marketing/video-manifest.ts, with the foreground cut-out's box (the hero's front
  flower bed, which the page redraws from the video in front of the phone), and the loops' lengths and
  drift in art/web/video-loops.json.

$WEB_SCENE_VIDEO_THEMES (light, dark or light,dark) limits a run to one theme.

usage:
    python scripts/web-scene-video.py <folder with the raw clips>             # everything (about 40 min)
    python scripts/web-scene-video.py <folder> scene-hero spot-record         # some slots
    python scripts/web-scene-video.py --render-only <folder> [slots]          # only the masters
    python scripts/web-scene-video.py --encode-only [slots]                   # re-encode the kept masters

The lossless masters (FFV1, about 5 GB) are kept for --encode-only in $WEB_SCENE_VIDEO_TMP, or the system
temp folder's web-scene-video/. The raw clips are named after the picture they animate (hero-light.mp4,
pro-dark.mp4, ...). They are not in the repo (8 to 12 MB each); download them again from the job IDs in
art/web/credits.md.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SCREENS = json.loads((ROOT / "art/web/screens.json").read_text(encoding="utf8"))
NATURE = json.loads((ROOT / "art/web/scene-nature.json").read_text(encoding="utf8"))
OUT = ROOT / "web/public/marketing/video"
MANIFEST = ROOT / "web/components/marketing/video-manifest.ts"
LOOPS = ROOT / "art/web/video-loops.json"
URL = "/marketing/video"

FPS = 24
MATTE_PAD = 8  # black rows between the picture and the foreground's matte
CLOSE_XF = 8  # frames over which the end of the clip runs into its start
WIDTH = {"wide": 1920, "mobile": 720, "phone-full": 960, "spot": 480}
GOP = FPS * 10  # longer than any clip: one keyframe, no pulse
# The wrap from the last frame back to the keyframe shows as a pop wherever the two are coded differently: see
# close_loop.
# Phone crops whose round 8b size leaves little room: the slowest useful preset.
TIGHT = {"scene-pricing-mobile-light", "scene-pricing-mobile-dark", "scene-page-mobile-dark"}
CLOSE = 24  # the last frames carry the keyframe's own coding error, more and more
# H.264: bits for those frames (from, to, counted from the end; share), gentle to strong
RAMPS = ([(24, 17, 1.0), (16, 11, 1.15), (10, 6, 1.4), (5, 3, 2.0), (2, 1, 3.5)],
         [(24, 17, 1.1), (16, 11, 1.4), (10, 6, 1.9), (5, 3, 2.8), (2, 1, 4.5)],
         [(24, 17, 1.2), (16, 11, 1.6), (10, 6, 2.4), (5, 3, 4), (2, 1, 8)],
         [(24, 17, 1.3), (16, 11, 1.9), (10, 6, 3.2), (5, 3, 7), (2, 1, 16)],
         [(24, 17, 1.4), (16, 11, 2.2), (10, 6, 4.5), (5, 3, 11), (2, 1, 30)],
         [(24, 17, 1.5), (16, 11, 2.6), (10, 6, 6), (5, 3, 18), (2, 1, 50)])
TMP = Path(os.environ.get("WEB_SCENE_VIDEO_TMP") or Path(tempfile.gettempdir()) / "web-scene-video")

# Cloud drift over one loop, as a share of the picture's width: 5 px on a 1440 px wide page. Two copies
# this far apart are blended halfway through the loop; much more and the halfway frame shows a ghost edge.
DRIFT = 5 / 1440
# Per scene picture: the horizon (sky above it), boxes around the painted clouds (fractions of the picture;
# the same in Light and Dusk), and `protect`: boxes that always stay the video's own, never part of a cloud
# (lamp heads, the rooftop lantern, string lights, characters right under a cloud: a cream sleeve or skin at dusk
# has the colour of a cloud). `still`: indexes of cloud boxes that must not drift. `fixed`: per theme, boxes
# shown as the still itself (something the generator moved away for good).
CLOUDS = {
    "hero": {"horizon": 0.6, "boxes": [[0, 0.135, 0.19, 0.295], [0.135, 0.3, 0.23, 0.335], [0.86, 0.1, 1, 0.25], [0.8, 0.275, 0.91, 0.345]],
             "protect": [[0.14, 0.32, 0.185, 0.4], [0.8, 0.375, 0.845, 0.455], [0.85, 0.355, 0.94, 0.5]]},
    "features": {"horizon": 0.62, "boxes": [[0, 0.14, 0.165, 0.29], [0.1, 0.312, 0.18, 0.362], [0.83, 0.165, 1, 0.34]]},
    "pro": {"horizon": 0.55, "boxes": [[0.03, 0.13, 0.19, 0.27], [0.82, 0.112, 1, 0.27], [0.79, 0.28, 0.88, 0.37]],
            "protect": [[0.005, 0.23, 0.05, 0.31], [0.08, 0, 0.27, 0.1], [0.855, 0, 1, 0.115], [0.66, 0.3, 0.79, 0.5],
                        [0.8, 0.375, 0.88, 0.5]]},
    "footer": {"horizon": 0.8, "boxes": [[0, 0.07, 0.14, 0.32], [0.87, 0.09, 1, 0.31]], "protect_red": [[0.03, 0, 0.13, 0.17]],
               "fixed": {"dark": [[0.045, 0, 0.22, 0.165]]}},
    "page": {"horizon": 0.82, "boxes": [[0, 0.19, 0.165, 0.4], [0.1, 0.415, 0.18, 0.47], [0.875, 0.14, 1, 0.345], [0.81, 0.375, 0.925, 0.455]],
             "protect": [[0.15, 0.52, 0.195, 0.6], [0.83, 0.47, 0.94, 0.7]]},
}


def polygons(polys, shape):
    """The polygons (fractions of the picture; a box is [x0, y0, x1, y1]) as a 0/1 mask."""
    h, w = shape
    m = np.zeros((h, w), np.uint8)
    for pl in polys:
        if not isinstance(pl[0], list):
            x0, y0, x1, y1 = pl
            pl = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
        cv2.fillPoly(m, [np.round(np.array(pl, np.float32) * [w, h]).astype(np.int32)], 1)
    return m


def held_mask(scene: str, shape, theme: str):
    """Everything that must look like the still in every frame, whatever the clip does there: the people, what they wear
    and hold, animals, and the objects (art/web/held/, drawn at the still's outlines), plus the scene's own `hold`
    polygons, minus its `free` ones (flowers caught in the outlines)."""
    cfg = NATURE[scene]
    h, w = shape
    m = cv2.resize(cv2.imread(str(ROOT / f"art/web/held/{scene}.png"), cv2.IMREAD_GRAYSCALE), (w, h), interpolation=cv2.INTER_LINEAR) > 127
    m[polygons(cfg.get("free", []), shape) > 0] = False
    m[polygons(cfg.get("hold", []) + cfg.get(f"hold_{theme}", []), shape) > 0] = True
    return m


def probe(path: Path):
    w, h = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout.strip().split(",")[:2]
    return int(w), int(h)


def frames_of(path: Path):
    """The clip's frames, one at a time, as uint8 RGB."""
    w, h = probe(path)
    p = subprocess.Popen(["ffmpeg", "-v", "quiet", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    size = w * h * 3
    try:
        while True:
            buf = p.stdout.read(size)
            if len(buf) < size:
                break
            yield np.frombuffer(buf, np.uint8).reshape(h, w, 3)
    finally:
        p.stdout.close()
        p.wait()


# ----------------------------------------------------------------------------------------------- loops

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------------------------- clouds

def foreground(img, theme):
    """0..1: how surely a pixel is something in front of the sky (leaf, trunk, bird, kite, balloon, lamp),
    not sky or cloud. img: float RGB 0..255."""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    if theme == "light":
        # clouds are white with cream and lilac shading; leaves are clearly green or yellow
        return np.maximum.reduce([smoothstep(25, 45, g - b), smoothstep(50, 80, r - b), smoothstep(115, 75, lum)])
    # dusk: sky navy to purple to pink, clouds pink, lilac and orange; leaves teal-green with yellow tips; the
    # kite and red clothes are a purer red than any cloud rim
    return np.maximum.reduce([smoothstep(-14, -2, g - np.maximum(r, b)), smoothstep(45, 75, g - b) * smoothstep(60, 100, r),
                              smoothstep(110, 150, r - np.maximum(g, b)), smoothstep(30, 12, lum)])


def luma(img):
    return 0.299 * img[..., 0] + 0.587 * img[..., 1] + 0.114 * img[..., 2]


def fit_sky(img, mask):
    """Smooth sky colour, a cubic in x and y fitted to the pixels in mask (outliers dropped)."""
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    sel = np.random.default_rng(0).choice(len(ys), size=min(len(ys), 60000), replace=False)
    ys, xs = ys[sel], xs[sel]

    def basis(X, Y):
        return np.stack([np.ones_like(X), X, Y, X * X, X * Y, Y * Y, X ** 3, X * X * Y, X * Y * Y, Y ** 3, Y ** 4], axis=-1)

    A = basis(xs / w, ys / h)
    gy, gx = np.mgrid[0:h, 0:w]
    B = basis(gx / w, gy / h)
    out = np.empty((h, w, 3), np.float32)
    for c in range(3):
        v = img[ys, xs, c]
        keep = np.ones(len(v), bool)
        for _ in range(3):
            coef, *_ = np.linalg.lstsq(A[keep], v[keep], rcond=None)
            res = np.abs(A @ coef - v)
            keep = res < max(4.0, 2.5 * np.median(res))
        out[..., c] = B @ coef
    return out


class Clouds:
    """The still's clouds over a clean sky, drifting over one loop, laid into the video's frames."""

    def __init__(self, still, scene, theme):
        cfg = CLOUDS[scene]
        h, w = still.shape[:2]
        self.theme = theme
        self.d = DRIFT * w
        grey = cv2.cvtColor(still.astype(np.uint8), cv2.COLOR_RGB2GRAY).astype(np.float32)
        mu = cv2.blur(grey, (5, 5))
        sd = np.sqrt(np.maximum(cv2.blur(grey * grey, (5, 5)) - mu * mu, 0))
        fg = foreground(still, theme)
        sky = (sd < 3.0) & (fg < 0.1)
        sky[int(cfg["horizon"] * h):] = False
        boxmask = np.zeros((h, w), bool)
        for bx in cfg["boxes"]:
            boxmask[max(0, int(bx[1] * h) - 20):int(bx[3] * h) + 20, max(0, int(bx[0] * w) - 20):int(bx[2] * w) + 20] = True
        fit = fit_sky(still, sky & ~boxmask)
        prot = np.zeros((h, w), np.uint8)
        for bx in cfg.get("protect", ()):
            prot[int(bx[1] * h):int(bx[3] * h), int(bx[0] * w):int(bx[2] * w)] = 1
        # protect_red: inside these boxes only the strongly red things (the kite and its ribbons), grown a little,
        # so a cloud next to them is not cut along the box's edge
        red = np.zeros((h, w), np.uint8)
        for bx in cfg.get("protect_red", ()):
            y0, y1, x0, x1 = int(bx[1] * h), int(bx[3] * h), int(bx[0] * w), int(bx[2] * w)
            c = still[y0:y1, x0:x1]
            # saturated red only: a sunset cloud is pink (r well above g and b, but half as saturated)
            sat = (c.max(axis=-1) - c.min(axis=-1)) / np.maximum(c.max(axis=-1), 1)
            red[y0:y1, x0:x1] = ((c[..., 0] - np.maximum(c[..., 1], c[..., 2]) > 45) & (sat > 0.7)).astype(np.uint8)
        near_red = cv2.dilate(red, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21)))
        drawn = bool(cfg.get("fixed", {}).get(theme))  # the kite is drawn from the still, on top of everything (below)
        prot |= near_red
        res = np.linalg.norm(still - fit, axis=-1)
        self.zones = []
        margin = int(round(self.d)) + 48
        reach = int(round(self.d)) + 40
        for k, bx in enumerate(cfg["boxes"]):
            x0, y0 = max(0, int(bx[0] * w) - margin), max(0, int(bx[1] * h) - margin)
            x1, y1 = min(w, int(bx[2] * w) + margin), min(h, int(bx[3] * h) + margin)
            # what is in front of the sky, grown over its soft edges: none of it may stay in the clean sky or in the
            # cloud layer, or a faint copy of a leaf shows where the leaf has swayed away
            S, R = still[y0:y1, x0:x1], res[y0:y1, x0:x1]
            front = fg[y0:y1, x0:x1].astype(np.float32)
            if theme == "dark":  # the reddest bits of a sunset cloud are no foreground
                front = front * ~((S[..., 1] - S[..., 2] < 45) & (S[..., 0] > S[..., 1] + 15) & (S[..., 2] > 85))
            F = cv2.GaussianBlur(cv2.dilate(front, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))), (0, 0), 1)
            P = prot[y0:y1, x0:x1].astype(bool)
            # the cloud: away from the sky colour, not foreground, not darker than the sky (a bird is), in pieces
            # that reach into the box itself
            brighter = luma(S) > luma(fit[y0:y1, x0:x1]) - 6
            # nor the yellow or green rim a blurred leaf leaves on the sky
            rim = S[..., 2] < (0.65 * S[..., 1] if theme == "dark" else S[..., 1] - 30)
            rim = cv2.dilate(rim.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
            cloud = cv2.morphologyEx(((R > 9) & (F < 0.5) & brighter & ~rim).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) * (~P)
            n, lab, stats, _ = cv2.connectedComponentsWithStats(cloud, 8)
            inner = np.zeros_like(cloud)
            inner[max(0, int(bx[1] * h) - y0):int(bx[3] * h) - y0, max(0, int(bx[0] * w) - x0):int(bx[2] * w) - x0] = 1
            keep = np.zeros(n, bool)
            for c in range(1, n):
                keep[c] = stats[c, cv2.CC_STAT_AREA] > 150 and bool(inner[lab == c].any())
            largest = max((stats[c, cv2.CC_STAT_AREA] for c in range(1, n) if keep[c]), default=0)
            keep &= stats[:, cv2.CC_STAT_AREA] > 0.04 * largest  # bits of sky between leaves
            cmask = keep[lab]
            grown = cv2.dilate(cmask.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
            alpha = (smoothstep(4, 16, R) * grown * (1 - smoothstep(0.4, 0.8, F)) * ~rim).astype(np.float32)
            # clean plate: the fitted sky plus the sky's own small variations, smoothly carried into the holes
            fitz = fit[y0:y1, x0:x1]
            hole = grown | cv2.dilate(((F > 0.06) | rim).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))).astype(bool)
            skym = (~hole).astype(np.float32)
            resid = np.clip(S - fitz, -14, 14) * skym[..., None]
            near = np.zeros_like(S)  # wider and wider neighbourhoods, each taking over where the narrower one sees no sky
            for sigma in (200, 70, 18):
                den = cv2.GaussianBlur(skym, (0, 0), sigma)[..., None]
                local = cv2.GaussianBlur(resid, (0, 0), sigma) / np.maximum(den, 1e-3)
                near += (local - near) * smoothstep(0.02, 0.25, den)
            plate = np.where(hole[..., None], fitz + near, S)
            # the cloud carried on sideways under the foreground it meets (behind a crown or a trunk), row by
            # row, so a drifted copy or a branch swaying aside never shows a cut edge
            under = ((F > 0.3) | rim) & ~near_red[y0:y1, x0:x1].astype(bool)
            col, al = S.copy(), alpha.copy()
            filled = np.zeros_like(under)
            for _ in range(reach):
                for sgn in (1, -1):
                    src_a, src_c = np.roll(al, sgn, axis=1), np.roll(col, sgn, axis=1)
                    src_ok = np.roll(~under | filled, sgn, axis=1)
                    src_ok[:, 0 if sgn == 1 else -1] = False
                    take = under & ~filled & src_ok & (src_a > 0.15)
                    al[take], col[take] = src_a[take], src_c[take]
                    filled |= take
            own = cv2.dilate(((alpha > 0.02) & ~under).astype(np.float32), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
            carried = np.where(under, al * filled, alpha)
            alpha = np.where(under, cv2.GaussianBlur(carried, (0, 0), 4), alpha)  # (row by row leaves streaks)
            # its colour there is the cloud's own, smoothed from what shows of it (copying edge pixels along the rows left
            # streaks, and painting in from all sides brought in the leaves' yellow)
            seen = (alpha * ~under)[..., None]
            fill = np.zeros_like(S)
            for sigma in (60, 10):
                den = cv2.GaussianBlur(seen, (0, 0), sigma)[..., None]
                fill += (cv2.GaussianBlur(S * seen, (0, 0), sigma) / np.maximum(den, 1e-4) - fill) * smoothstep(0.002, 0.05, den)
            col = np.where(under[..., None], fill, S)
            # replaced only around the clouds (room for the drift and the generator's wobbly outline), so gaps
            # between leaves elsewhere keep the video's own sky
            rep = cv2.dilate(cmask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * (int(self.d) + 22) + 1,) * 2))
            keep_video = P & ~near_red[y0:y1, x0:x1].astype(bool) if drawn else P
            rep[cv2.dilate(keep_video.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool)] = 0
            zw = np.clip(cv2.GaussianBlur(rep.astype(np.float32), (0, 0), 6) * 1.6, 0, 1)
            self.zones.append({"box": (x0, y0, x1, y1), "plate": plate.astype(np.float32), "layer": col.astype(np.float32),
                               "alpha": alpha.astype(np.float32), "zw": zw, "own": own, "still": k in cfg.get("still", ()), "cmask": cmask})
        # fixed: areas shown as the still itself, where the generator moved something away for good (the Dusk
        # footer's kite flies off to the right, so it would jump back at the loop point), clear of the clouds
        self.fixed = None
        boxes = cfg.get("fixed", {}).get(theme, [])
        if boxes:
            m = np.zeros((h, w), np.float32)
            for bx in boxes:
                m[int(bx[1] * h):int(bx[3] * h), int(bx[0] * w):int(bx[2] * w)] = 1
            for z in self.zones:  # never over a cloud (with room for its drift)
                zx0, zy0, zx1, zy1 = z["box"]
                near = cv2.dilate(z["cmask"].astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * (int(self.d) + 8) + 1,) * 2))
                m[zy0:zy1, zx0:zx1] *= 1 - near
            m = cv2.GaussianBlur(m, (0, 0), 5)
            # the kite itself also where its tail meets a cloud
            m = np.maximum(m, cv2.GaussianBlur(cv2.dilate(red, np.ones((9, 9), np.uint8)).astype(np.float32), (0, 0), 1.5))
            ys, xs = np.nonzero(m > 0.002)
            fx0, fy0, fx1, fy1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
            self.fixed = (fx0, fy0, fx1, fy1, m[fy0:fy1, fx0:fx1, None], still[fy0:fy1, fx0:fx1].astype(np.float32))

    def _shift(self, z, dx):
        m = np.float32([[1, 0, dx], [0, 1, 0]])
        size = (z["box"][2] - z["box"][0], z["box"][3] - z["box"][1])
        col = cv2.warpAffine(z["layer"], m, size, flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
        a = cv2.warpAffine(z["alpha"], m, size, flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
        return col, np.clip(a, 0, 1)[..., None]

    def sky(self, z, u):
        """The zone's sky and clouds at loop phase u (0..1); u = 0 and u = 1 are the still."""
        if z["still"]:
            a = z["alpha"][..., None]
            return z["plate"] * (1 - a) + z["layer"] * a
        wb = smoothstep(0.15, 0.85, u)
        ca, aa = self._shift(z, u * self.d)
        cb, ab = self._shift(z, -(1 - u) * self.d)
        return (z["plate"] * (1 - aa) + ca * aa) * (1 - wb) + (z["plate"] * (1 - ab) + cb * ab) * wb

    def apply(self, frame, u):
        for z in self.zones:
            x0, y0, x1, y1 = z["box"]
            v = frame[y0:y1, x0:x1]
            # foreground by colour, or anything clearly darker than the clean sky there (birds, outlines)
            below = luma(z["plate"]) - luma(v)
            # (a cloud's own shaded edge is neither: there the darkness has to be plain)
            dark = smoothstep(18, 40, below)
            # or redder than it without being brighter (a branch in the last light)
            redder = (v[..., 0] - v[..., 2]) - (z["plate"][..., 0] - z["plate"][..., 2])
            extra = np.maximum(smoothstep(14, 30, below), smoothstep(22, 40, redder) * smoothstep(-14, -2, below))
            fgv = np.maximum.reduce([foreground(v, self.theme), dark, extra * (1 - z["own"])])
            # without pinholes, and with its soft edge (two pixels of the clip's own sky round it)
            fgv = cv2.morphologyEx(fgv.astype(np.float32), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
            fgv = np.maximum(fgv, cv2.GaussianBlur(cv2.dilate(fgv, np.ones((5, 5), np.uint8)), (0, 0), 1.2))
            k = (z["zw"] * (1 - np.clip(fgv, 0, 1)))[..., None]
            frame[y0:y1, x0:x1] = v * (1 - k) + self.sky(z, u) * k
        if self.fixed is not None:
            x0, y0, x1, y1, m, pic = self.fixed
            frame[y0:y1, x0:x1] = frame[y0:y1, x0:x1] * (1 - m) + pic * m


# ----------------------------------------------------------------------------------------------- files

class Sink:
    """One output: a crop of the frame, resized, written losslessly (FFV1) to a master in TMP. A scene with a foreground
    cut-out (the hero's front flower bed, which the page draws again in front of the phone) also carries the cut-out's
    shape in every frame: its alpha, slid along with the picture, as a grey strip MATTE_PAD rows under the picture."""

    def __init__(self, name: str, kind: str, box, shape, fg=None):
        th0, tw0 = shape
        self.frac = box
        if box:
            x0, y0, x1, y1 = round(box[0] * tw0), round(box[1] * th0), round(box[2] * tw0), round(box[3] * th0)
            tw0, th0 = x1 - x0, y1 - y0
        width = WIDTH[kind]
        self.size = (width - width % 2, (lambda v: v - v % 2)(round(th0 * width / tw0)))
        self.name, self.kind = name, kind
        self.alpha, self.row, coded = None, 0, self.size[1]
        if fg is not None:
            alpha, top = fg
            if box:
                top = (top - box[1]) / (box[3] - box[1])
            self.alpha, self.row = alpha, (lambda v: v - v % 2)(round(top * self.size[1]))
            coded = self.size[1] + MATTE_PAD + self.size[1] - self.row
        self.coded = coded
        TMP.mkdir(parents=True, exist_ok=True)
        self.proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{self.size[0]}x{self.coded}",
             "-r", str(FPS), "-i", "-", "-c:v", "ffv1", "-pix_fmt", "gbrp", str(TMP / f"{name}.mkv")],
            stdin=subprocess.PIPE,
        )

    def cut(self, pic):
        """This file's part of a picture of any size, at the file's size."""
        h, w = pic.shape[:2]
        if self.frac:
            x0, y0, x1, y1 = self.frac
            pic = pic[round(y0 * h):round(y1 * h), round(x0 * w):round(x1 * w)]
        return cv2.resize(pic, self.size, interpolation=cv2.INTER_AREA).astype(np.float32)

    def keep(self, still, ref, change):
        """Where nothing ever changes, the file is the still resampled straight from the picture, not by way of the
        clip's size."""
        soft = cv2.dilate(self.cut(change), np.ones((3, 3), np.uint8))
        self.fix = (self.cut(still) - self.cut(ref)) * (1 - smoothstep(0, 0.25, soft))[..., None]

    def write(self, frame, grid):
        pic = np.clip(self.cut(frame) + self.fix + 0.5, 0, 255).astype(np.uint8)
        if self.alpha is not None:
            a = self.cut(cv2.remap(self.alpha, grid[0], grid[1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE))
            strip = np.zeros((self.coded - self.size[1], self.size[0], 3), np.uint8)
            strip[MATTE_PAD:] = np.clip(a[self.row:] + 0.5, 0, 255).astype(np.uint8)[..., None]
            pic = np.vstack([pic, strip])
        self.proc.stdin.write(pic.tobytes())

    def close(self):
        self.proc.stdin.close()
        if self.proc.wait():
            raise SystemExit(f"master failed for {self.name}")
        (TMP / f"{self.name}.json").write_text(json.dumps({"kind": self.kind, "w": self.size[0], "h": self.coded, "pic": self.size[1], "row": self.row if self.alpha is not None else None}))


TO_YUV = "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p"


def master_yuv(name: str, w: int, h: int, start: int = 0):
    """The master's frames as flat yuv420p arrays (BT.709, TV range), one at a time, from frame `start` on and round."""
    size = w * h * 3 // 2
    for skip, count in ((start, None), (0, start)):
        if count == 0:
            continue
        cmd = ["ffmpeg", "-v", "error", "-i", str(TMP / f"{name}.mkv"), "-vf", TO_YUV]
        p = subprocess.Popen(cmd + ["-f", "rawvideo", "-pix_fmt", "yuv420p", "-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        try:
            n = 0
            while True:
                buf = p.stdout.read(size)
                if len(buf) < size:
                    break
                n += 1
                if n <= skip:
                    continue
                if count is not None and n > count:
                    break
                yield np.frombuffer(buf, np.uint8)
        finally:
            p.stdout.close()
            p.terminate()
            p.wait()


def still_grey(name: str, w: int, h: int):
    """The still picture behind a file (the page fades from it), in grey, cropped like the file, a quarter of its size."""
    slot, theme = name.rsplit("-", 1)
    box = None
    for kind in ("-wide", "-mobile"):
        if slot.endswith(kind):
            slot = slot[: -len(kind)]
            cfg = SCREENS["slots"][slot]
            box = cfg.get("mobile") if kind == "-mobile" else None
            break
    else:
        cfg = SCREENS["slots"][slot]
        box = cfg["wide"]
    pic = cv2.imread(str(ROOT / cfg[theme]), cv2.IMREAD_GRAYSCALE)
    if box:
        ph, pw = pic.shape
        pic = pic[round(box[1] * ph):round(box[3] * ph), round(box[0] * pw):round(box[2] * pw)]
    return cv2.resize(pic, (max(1, w // 4), max(1, h // 4)), interpolation=cv2.INTER_AREA).astype(np.float32)


def quiet_start(name: str, w: int, h: int, n: int):
    """The frame after a quiet step of the master, so that the file's own wrap (last frame back to the first) lands where
    the picture barely moves. Of the quiet steps (the quietest tenth) the
    one whose picture is nearest the still, so the page's fade from picture to video stays soft."""
    still = still_grey(name, w, h)
    prev = first = None
    steps = np.empty(n)
    dist = np.empty(n)
    for t, fr in enumerate(master_yuv(name, w, json.loads((TMP / f"{name}.json").read_text())["h"])):
        y = cv2.resize(fr[:w * h].reshape(h, w), (max(1, w // 4), max(1, h // 4)), interpolation=cv2.INTER_AREA).astype(np.float32)
        dist[t] = np.abs(y - y.mean() - still + still.mean()).mean()
        if prev is None:
            first = y
        else:
            steps[t] = np.abs(y - prev).mean()
        prev = y
    steps[0] = np.abs(first - prev).mean()  # steps[t] = |f[t] - f[t-1]|, round the loop
    quiet = np.percentile(steps, 10)
    return int(np.argmin(np.where(steps <= quiet, dist, np.inf)))


def never_moving(name: str, w: int, h: int, start: int = 0):
    """(frame count, mask over a yuv420p frame of the pixels whose luma stays within one level all through the
    master, eroded a little)."""
    lo = hi = None
    n = 0
    for fr in master_yuv(name, w, h, start):
        y = fr[:w * h]
        lo = y.copy() if lo is None else np.minimum(lo, y)
        hi = y.copy() if hi is None else np.maximum(hi, y)
        n += 1
    still = (hi.astype(np.int16) - lo <= 1).reshape(h, w).astype(np.uint8)
    still_y = cv2.erode(still, np.ones((3, 3), np.uint8))
    still_c = cv2.resize(still_y.astype(np.float32), (w // 2, h // 2), interpolation=cv2.INTER_AREA) > 0.99
    return n, np.concatenate([still_y.ravel() > 0, still_c.ravel(), still_c.ravel()])


def pipe_encode(frames, w: int, h: int, codec_args, path: Path):
    """Encode yuv420p frames (an iterable of flat uint8 arrays)."""
    args = ["-an", "-g", str(GOP), "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
            "-movflags", "+faststart"] + codec_args
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "yuv420p", "-s", f"{w}x{h}", "-r", str(FPS),
                          # say what the raw frames are: untagged, ffmpeg takes them for BT.601 and converts the colours
                          "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                          "-i", "-"] + args + [str(path)], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    for fr in frames:
        p.stdin.write(fr.tobytes())
    p.stdin.close()
    if p.wait():
        raise SystemExit(f"encode failed for {path.name}")


def planes(f, w: int, h: int):
    a = w * h
    return f[:a].reshape(h, w), f[a:a * 5 // 4].reshape(h // 2, w // 2), f[a * 5 // 4:].reshape(h // 2, w // 2)


def decode_yuv(path: Path, w: int, h: int):
    d = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
                       capture_output=True, check=True).stdout
    return np.frombuffer(d, np.uint8).reshape(-1, w * h * 3 // 2)


def seam(dec, w: int, h: int):
    """(step from the last frame to the first, 90th percentile of the other steps), mean luma difference."""
    y = dec[:, :w * h]
    steps = [np.abs(y[t + 1].astype(np.int16) - y[t]).mean() for t in range(len(y) - 1)]
    return float(np.abs(y[0].astype(np.int16) - y[-1]).mean()), float(np.percentile(steps, 90))


def close_loop(src, d0, w: int, h: int, mask):
    """The frames to encode instead of `src`, given the decoded keyframe D0 of a first encode. Frame 0 stays as it is,
    so the next encode makes the same keyframe again; pixels that never move are D0's from frame 1 on; and the last
    CLOSE frames carry D0's coding error, slid along the optical flow and fading in, so the last frame already looks
    like the keyframe when the file wraps."""
    err = [a.astype(np.float32) - b for a, b in zip(planes(d0, w, h), planes(src[0], w, h))]
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    n = len(src)
    out = src.copy()
    for t in range(n - CLOSE, n):
        flow = dis.calc(planes(src[t], w, h)[0].copy(), planes(src[0], w, h)[0].copy(), None)
        half = cv2.resize(flow, (w // 2, h // 2)) / 2
        slid = []
        for e, fl in zip(err, (flow, half, half)):
            gy, gx = np.mgrid[0:e.shape[0], 0:e.shape[1]].astype(np.float32)
            slid.append(cv2.remap(e, gx + fl[..., 0], gy + fl[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT).ravel())
        k = smoothstep(0, 1, (CLOSE + 1 - (n - t)) / CLOSE)
        out[t] = np.clip(src[t] + k * np.concatenate(slid) + 0.5, 0, 255).astype(np.uint8)
    for t in range(1, n):
        out[t][mask] = d0[mask]
    return out


def encode_h264(src, w: int, h: int, mask, path: Path, limit: float, tight: bool, ramp, mbtree: bool):
    """Two-pass H.264 of the closed loop, as big as `limit` allows. The trial encode (for the keyframe) and the real one
    use the same first-pass statistics, so their keyframes are the same even with mbtree on."""
    n = len(src)
    log = str(TMP / f"{path.stem}.2pass")
    params = "scenecut=0" + ("" if mbtree else ":mbtree=0") + ":zones=" + "/".join(f"{n - a},{n - b},b={v}" for a, b, v in ramp)
    rate = limit * 8 * FPS / n
    for _ in range(4):
        args = ["-c:v", "libx264", "-preset", "veryslow" if tight else "slow", "-profile:v", "high", "-b:v", str(int(rate)),
                "-passlogfile", log, "-x264-params", params]
        pipe_encode(src, w, h, args + ["-pass", "1"], path)
        pipe_encode(src, w, h, args + ["-pass", "2"], path)
        d0 = decode_yuv(path, w, h)[0].copy()
        pipe_encode(close_loop(src, d0, w, h, mask), w, h, args + ["-pass", "2"], path)
        size = path.stat().st_size
        if 0.93 * limit <= size <= limit:
            break
        rate *= 0.975 * limit / size
    for f in TMP.glob(f"{path.stem}.2pass*"):
        f.unlink()
    return (*seam(decode_yuv(path, w, h), w, h), size)


def encode(name: str):
    """H.264 from a master. art/web/video-limits.json holds a size ceiling per file (bytes). The gentlest ramp whose wrap is no
    bigger than its 90th percentile step, else the smallest wrap. No AV1: at these sizes its big blocks recode bits of
    the people next to moving leaves (round 9), and nothing but nature may move."""
    meta = json.loads((TMP / f"{name}.json").read_text())
    kind, w, h = meta["kind"], meta["w"], meta["h"]
    OUT.mkdir(parents=True, exist_ok=True)
    limits = json.loads((ROOT / "art/web/video-limits.json").read_text())
    n = sum(1 for _ in master_yuv(name, w, h))
    start = meta["start"] = quiet_start(name, w, meta["pic"], n)
    (TMP / f"{name}.json").write_text(json.dumps(meta))
    src = np.stack(list(master_yuv(name, w, h, start)))
    _, mask = never_moving(name, w, h, start)
    h264_file = OUT / f"{name}.mp4"
    best = None
    for r, mbtree in ((0, True), (1, True), (2, True), (1, False), (2, False), (3, True), (3, False), (4, True), (4, False), (5, True)):
        wrap, p90, size = encode_h264(src, w, h, mask, h264_file, limits[h264_file.name], name in TIGHT, RAMPS[r], mbtree)
        if size <= limits[h264_file.name] and (best is None or wrap / p90 < best[0]):
            best = (wrap / p90, f"ramp {r}{'' if mbtree else ' no mbtree'}", h264_file.read_bytes())
        if best and best[0] <= 0.97:
            break
    h264_file.write_bytes(best[2])
    entry = {"w": w, "h": meta["pic"], "h264": f"{URL}/{h264_file.name}"}
    if meta["row"] is not None:
        entry["matte"] = {"coded": h, "row": meta["row"], "strip": meta["pic"] + MATTE_PAD}
    print(f"    {name}: {w}x{h} starts {start}; h264 {best[1]} {len(best[2]) / 1e6:.3f} MB wrap {best[0]:.2f} x p90", flush=True)
    return entry


def moving(far):
    """Where the clip moves, given how far each pixel gets from the first frame (about 854 px wide): whole plants, and
    small things that move a lot (birds, butterflies, fireflies), but no specks of shimmer."""
    m = cv2.morphologyEx((far > 8).astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(cv2.dilate(m, np.ones((5, 5), np.uint8)))
    top = np.zeros(n, np.float32)
    np.maximum.at(top, lab.ravel(), far.ravel())
    ok = (stats[:, cv2.CC_STAT_AREA] > 350) | ((top > 20) & (stats[:, cv2.CC_STAT_AREA] > 60))
    ok[0] = False
    return (ok[lab] & (m > 0)).astype(np.uint8)


SHIFTS = [(r * x, r * y) for r in (6, 12, 20) for x, y in ((1, 0), (-1, 0), (0, 1), (0, -1), (.7, .7), (-.7, .7), (.7, -.7), (-.7, -.7))]


def sharpen_flow(flow, f, soft, last):
    """The flow with edges where the picture has them. DIS smooths it across the outline of a petal, so the paving beside it is
    dragged along and the petal's tip lags behind. Here every pixel takes whichever flow nearby (or none at all) makes
    the still look most like the frame. last: the sharp flow of the frame before, preferred, so the choice doesn't flicker."""
    h, w = flow.shape[:2]
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
    f = f.astype(np.float32)

    def cost(fl):
        d = np.abs(cv2.remap(soft, gx + fl[..., 0], gy + fl[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT) - f)
        return cv2.GaussianBlur(np.minimum(d.sum(axis=2), 150), (0, 0), 2.3)

    best, out = cost(flow), flow.copy()
    others = [(cv2.warpAffine(flow, np.float32([[1, 0, x], [0, 1, y]]), (w, h), borderMode=cv2.BORDER_REPLICATE), 8) for x, y in SHIFTS]
    for fl, dear in [(np.zeros_like(flow), 5)] + ([] if last is None else [(last, 1)]) + others:
        c = cost(fl) + dear
        m = c < best
        best[m] = c[m]
        out[m] = fl[m]
    for _ in range(2):
        out = np.dstack([cv2.medianBlur(out[..., 0], 5), cv2.medianBlur(out[..., 1], 5)])
    return out, cv2.GaussianBlur(out, (0, 0), 0.7)


def detail(f, ref, refs, soft, dis, grid, guess):
    """A frame of the clip at the picture's full size, with the picture's own line work: the still, slid along the
    optical flow between the frame and the still, gives the fine detail; the clip gives everything broader (and all of
    it where the two disagree: leaves that turned over, a bird's wing). soft: the still as soft as the clip. guess: the
    frame before's small flows. Returns the frame, the flow and the small flows."""
    h, w = ref.shape[:2]
    up = cv2.resize(f, (w, h), interpolation=cv2.INTER_LANCZOS4).astype(np.float32)
    sw, sh = refs.shape[1], refs.shape[0]
    fs = cv2.resize(f, (sw, sh), interpolation=cv2.INTER_CUBIC)
    small = dis.calc(cv2.cvtColor(fs, cv2.COLOR_RGB2GRAY), refs, None if guess is None else guess[0].copy())
    last, sharp = sharpen_flow(small, fs, soft, None if guess is None else guess[1])
    flow = cv2.resize(sharp, (w, h), interpolation=cv2.INTER_LINEAR) * (w / sw)
    slid = cv2.remap(ref, grid[0] + flow[..., 0], grid[1] + flow[..., 1], cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
    s = 1.4 * h / f.shape[0]
    ls, lu = cv2.GaussianBlur(slid, (0, 0), s), cv2.GaussianBlur(up, (0, 0), s)
    err = cv2.GaussianBlur(np.abs(ls - lu).max(axis=2), (0, 0), 2)
    # and how alike the two look, stroke for stroke: where the flow got lost (lavender swaying past its own spikes) the
    # slid line work is a scramble that only matches on average
    m = cv2.GaussianBlur(slid, (0, 0), 0.8 * s).mean(axis=2), cv2.GaussianBlur(up, (0, 0), 0.4 * s).mean(axis=2)
    m = [x - cv2.GaussianBlur(x, (0, 0), 5 * s) for x in m]
    va, vb, vab = [cv2.GaussianBlur(x, (0, 0), 1.8 * s) for x in (m[0] * m[0], m[1] * m[1], m[0] * m[1])]
    like = (vab + 25) / (np.sqrt(va * vb) + 25)
    k = (1 - smoothstep(12, 46, err)) * smoothstep(0.68, 0.9, like)
    k = cv2.morphologyEx(k, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))  # no stray islands of it
    k = cv2.GaussianBlur(k, (0, 0), 1.5)[..., None]
    up += (up - cv2.GaussianBlur(up, (0, 0), 0.8 * s)) * 0.6  # a little crisper where the clip is on its own
    return np.clip(up + (lu - up + slid - ls) * k, 0, 255), flow, (small, last)


def render(src_img: Path, raw: Path, scene: str, theme: str, make_sinks):
    """The whole clip over the still, at the still's sharpness, with the held things on top."""
    still = cv2.cvtColor(cv2.imread(str(src_img), cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    sh, sw = still.shape[:2]
    w, h = probe(raw)
    tw = WIDTH["wide"]
    th = round(tw * sh / sw)
    unit = th / 1440
    ref = cv2.resize(still, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)
    cw, ch = w, round(w * sh / sw)  # the clip in the picture's shape (the hero went to the model stretched to 16:9)
    refc = cv2.resize(still, (cw, ch), interpolation=cv2.INTER_AREA).astype(np.float32)
    refs = cv2.cvtColor(cv2.resize(refc, (1280, round(1280 * sh / sw)), interpolation=cv2.INTER_AREA).astype(np.uint8), cv2.COLOR_RGB2GRAY)
    quarter = (cw // 4, ch // 4)
    refq = cv2.resize(refc, quarter, interpolation=cv2.INTER_AREA)
    TMP.mkdir(parents=True, exist_ok=True)
    frames, gain = [], None
    far = np.zeros((ch, cw), np.float32)
    for f in frames_of(raw):
        g = cv2.resize(f, (cw, ch), interpolation=cv2.INTER_CUBIC).astype(np.float32)
        if gain is None:
            gain = refc.reshape(-1, 3).mean(0) / np.maximum(g.reshape(-1, 3).mean(0), 1)
        g *= gain
        # the generator's colours wander a little: where a frame is near the still nothing moved, so the difference
        # there, smoothed, is the local colour error
        off = refq - cv2.resize(g, quarter, interpolation=cv2.INTER_AREA)
        calm = (np.abs(off).max(axis=2) < 12).astype(np.float32)
        num = cv2.GaussianBlur(off * calm[..., None], (0, 0), 8)
        den = cv2.GaussianBlur(calm, (0, 0), 8)[..., None]
        g += cv2.resize(num / (den + 0.05), (cw, ch), interpolation=cv2.INTER_LINEAR)
        g = np.clip(g + 0.5, 0, 255).astype(np.uint8)
        frames.append(g)
    # the first and the last frame are the same picture
    L = len(frames) - 1
    base = cv2.GaussianBlur(frames[0].astype(np.float32), (0, 0), 1)
    for g in frames[2::2]:
        d = np.abs(cv2.GaussianBlur(g.astype(np.float32), (0, 0), 1) - base).max(axis=2)
        far = np.maximum(far, cv2.GaussianBlur(d, (0, 0), 1.2))
    # where the clip moves; elsewhere it is the still too, so nothing rigid ever shimmers. Wide and soft, so no part
    # of the nature is cut off: the edge always lies where there is hardly a difference.
    size = 2 * round(cw / 110) + 1
    moved = moving(far)
    moved = cv2.dilate(moved, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size)))
    show = cv2.GaussianBlur(cv2.resize(moved.astype(np.float32), (tw, th), interpolation=cv2.INTER_LINEAR), (0, 0), 7 * unit)
    held_px = held_mask(scene, (th, tw), theme).astype(np.uint8)
    reach = cv2.distanceTransform(1 - held_px, cv2.DIST_L2, 5) / unit
    held = np.clip((3.5 - reach) / 2, 0, 1).astype(np.float32)
    free = show * (1 - held)
    clouds = Clouds(ref, scene, theme)
    change = free.copy()
    for z in clouds.zones:
        x0, y0, x1, y1 = z["box"]
        change[y0:y1, x0:x1] = np.maximum(change[y0:y1, x0:x1], z["zw"] * (1 - held[y0:y1, x0:x1]))
    print(f"  {raw.name}: {w}x{h} -> {tw}x{th}; loop of {L} frames ({L / FPS:.2f} s); moving {float((free > 0.5).mean()):.0%} "
          f"of the picture; drift {clouds.d:.1f} px; gain {np.round(gain, 3).tolist()}", flush=True)
    sinks = make_sinks((th, tw), theme)
    for s in sinks:
        s.keep(still, ref, change)
    soft = cv2.resize(refc, (refs.shape[1], refs.shape[0]), interpolation=cv2.INTER_CUBIC)
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    gy, gx = np.mgrid[0:th, 0:tw].astype(np.float32)
    grid = (gx, gy)
    body = cv2.GaussianBlur(cv2.dilate(held_px.astype(np.float32), np.ones((5, 5), np.uint8)), (0, 0), 1)
    f0, _, _ = detail(frames[0], ref, refs, soft, dis, grid, None)
    f1, _, _ = detail(frames[L], ref, refs, soft, dis, grid, None)
    small = None
    for t in range(L):
        f, flow, small = detail(frames[t], ref, refs, soft, dis, grid, small)
        left = L - t
        if left < CLOSE_XF:  # the last frames run into the first one
            f = f + (f0 - f1) * smoothstep(0, 1, (CLOSE_XF - left) / CLOSE_XF)
        # what belongs to a person or an object in the picture but has moved out of its outline in the clip (hair, a
        # skirt, a bag): the picture's own background stands there instead
        strayed = cv2.remap(body, gx + flow[..., 0], gy + flow[..., 1], cv2.INTER_LINEAR) > 0.4
        strayed = cv2.dilate(strayed.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11)))
        strayed = cv2.GaussianBlur(strayed.astype(np.float32), (0, 0), 2.5)
        g = ref + (f - ref) * (show * (1 - strayed))[..., None]
        clouds.apply(g, t / L)
        g += (ref - g) * held[..., None]
        np.clip(g, 0, 255, out=g)
        for s in sinks:
            s.write(g, (gx + flow[..., 0] * show, gy + flow[..., 1] * show))
    for s in sinks:
        s.close()
    return {"length": L, "seconds": round(L / FPS, 2), "drift_px": round(clouds.d, 1), "moving": round(float((free > 0.5).mean()), 3)}


encode_only = sys.argv[1] == "--encode-only"
render_only = sys.argv[1] == "--render-only"  # masters only, for --encode-only later
raw_dir = None if encode_only else Path(sys.argv[2] if render_only else sys.argv[1])
only = set(sys.argv[3:] if render_only else sys.argv[2:])
slots = SCREENS["slots"]



def foreground_alpha(slot, cfg, shape, theme):
    """(the foreground cut-out's alpha over the whole picture, 0..255; the top of its box), or None."""
    if "foreground" not in cfg:
        return None
    a = cv2.imread(str(ROOT / f"web/public/marketing/art/{slot}-fg-wide-{theme}-1920.webp"), cv2.IMREAD_UNCHANGED)[..., 3]
    return cv2.resize(a, (shape[1], shape[0]), interpolation=cv2.INTER_AREA).astype(np.float32), cfg["foreground"][1]


def read_manifest():
    if not MANIFEST.exists():
        return {}
    text = MANIFEST.read_text(encoding="utf8")
    return json.loads(text[text.index("= ") + 2: text.rindex(" as const")])


manifest, touched = {}, {}
loops = json.loads(LOOPS.read_text(encoding="utf8")) if LOOPS.exists() else {}

for slot, cfg in slots.items():
    if cfg.get("kind") != "scene" or "wide" in cfg:
        continue
    spots = {s: c for s, c in slots.items() if c.get("kind") == "scene" and "wide" in c and c["light"] == cfg["light"]}
    wanted = [s for s in [slot, *spots] if not only or s in only]
    if not wanted:
        continue
    print(slot, flush=True)
    for theme in os.environ.get("WEB_SCENE_VIDEO_THEMES", "light,dark").split(","):
        src = ROOT / cfg[theme]
        scene = src.stem.rsplit("-", 1)[0]
        names = {}
        if slot in wanted:
            names[f"{slot}-wide-{theme}"] = ("wide", None)
            names[f"{slot}-mobile-{theme}"] = ("mobile", cfg["mobile"]) if "mobile" in cfg else ("phone-full", None)
        for spot, scfg in spots.items():
            if spot in wanted:
                names[f"{spot}-{theme}"] = ("spot", scfg["wide"])
        if not encode_only:
            touched[src.stem] = render(src, raw_dir / f"{src.stem}.mp4", scene, theme,
                                     lambda shape, theme: [Sink(n, k, b, shape, foreground_alpha(slot, cfg, shape, theme) if k in ("wide", "mobile") else None)
                                                           for n, (k, b) in names.items()])
        if render_only:
            continue
        done = {n: encode(n) for n in names}
        if slot in wanted:
            e = manifest.setdefault(slot, {})
            e.setdefault("wide", {})[theme] = done[f"{slot}-wide-{theme}"]
            e.setdefault("mobile", {})[theme] = done[f"{slot}-mobile-{theme}"]
            if "foreground" in cfg:
                fx0, fy0, fx1, fy1 = cfg["foreground"]
                fg = {"wide": [fx0, fy0, fx1, fy1]}
                if "mobile" in cfg:
                    mx0, my0, mx1, my1 = cfg["mobile"]
                    fg["mobile"] = [max(0.0, (fx0 - mx0) / (mx1 - mx0)), max(0.0, (fy0 - my0) / (my1 - my0)),
                                    min(1.0, (fx1 - mx0) / (mx1 - mx0)), min(1.0, (fy1 - my0) / (my1 - my0))]
                e["fg"] = {key: [round(v, 4) for v in b] for key, b in fg.items()}
        for spot in spots:
            if spot in wanted:
                manifest.setdefault(spot, {}).setdefault("wide", {})[theme] = done[f"{spot}-{theme}"]

files = sorted(OUT.glob("*.mp4"))
print(f"total {sum(p.stat().st_size for p in files) / 1e6:.2f} MB in {len(files)} files")
# several runs (for different slots) may go on at once: only what this one made is replaced
if not render_only:
    MANIFEST.write_text(
        "// Written by scripts/web-scene-video.py. Don't edit by hand.\n"
        "// Per slot: the wide and phone loops in Light and Dark (H.264) and the\n"
        "// foreground cut-out's box in fractions of the picture.\n"
        f"export const sceneVideos = {json.dumps({**read_manifest(), **manifest}, indent=2, sort_keys=True)} as const;\n",
        encoding="utf8", newline="\n",
    )
if touched:
    loops = json.loads(LOOPS.read_text(encoding="utf8")) if LOOPS.exists() else {}
    LOOPS.write_text(json.dumps({**loops, **touched}, indent=1, sort_keys=True) + "\n", encoding="utf8", newline="\n")
