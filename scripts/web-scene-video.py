"""Video loops for the site's illustrated scenes (web/components/marketing/scene-video.tsx).

Each scene picture in art/web/gen2/ (Light and Dusk) was animated by an image-to-video model (MiniMax H3,
2K; prompts and job IDs in art/web/credits.md and video-prompts.md). This script turns those raw clips into
the files the page plays:

- resampled to the picture's exact shape (the hero is 3:2 and went to the model stretched to 16:9, so it is
  squeezed back here) and matched to the still's average colour;
- looped without a calm: the generator eases in and out of its keyframes, so the ends are dropped and the
  loop is cut inside the clip's active part, between the two frames at least LOOP_MIN apart that best match
  in picture and in motion (video-textures style), joined by an XF-frame crossfade. The file then starts at
  the loop frame closest to the still, so the fade from picture to video stays soft;
- clouds that drift instead of shimmering: inside each cloud box of CLOUDS the video's sky and clouds are
  replaced by a clean sky plate (the still with its clouds painted out) and the still's own clouds, drifting
  over one loop with a seamless crossfade (copy A moves 0 to +D and fades out, copy B moves -D to 0 and fades
  in). Clouds are carried on sideways under the trees they meet and mirrored past the picture's edge, so a
  drifted copy never shows a cut. Every pixel the video shows as tree, trunk, bird, kite or balloon stays the
  video's, so swaying branches still pass over the clouds;
- cut like the pictures (art/web/screens.json): the wide frame, the phone crop (`mobile`; a scene without one
  is shown whole on phones, at phone size) and every spot cut from the same picture;
- encoded as H.264 MP4 and AV1 MP4 (kept only where clearly smaller), muted, one keyframe per file (at these
  bitrates a keyframe comes out sharper than the frames before it, which showed as a pulse with the usual GOP);
- listed in web/components/marketing/video-manifest.ts, with the foreground cut-out's box (the hero's front
  flower bed, which the page redraws from the video in front of the phone), and the loop points, energy dips
  and drift in art/web/video-loops.json.

usage:
    python scripts/web-scene-video.py <folder with the raw clips>             # everything (about 40 min)
    python scripts/web-scene-video.py <folder> scene-hero spot-record         # some slots
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
OUT = ROOT / "web/public/marketing/video"
MANIFEST = ROOT / "web/components/marketing/video-manifest.ts"
LOOPS = ROOT / "art/web/video-loops.json"
URL = "/marketing/video"

FPS = 24
LOOP_MIN = round(4.5 * FPS)  # shortest loop
XF = 12  # crossfade at the loop point (0.5 s)
WIDTH = {"wide": 1920, "mobile": 720, "phone-full": 960, "spot": 480}
# Picked by eye on the hero at 100 %: the generated frames are soft, so these look the same as far
# lower settings; AV1 at these is about a quarter smaller than H.264.
H264_CRF = {"wide": 32, "mobile": 32, "phone-full": 32, "spot": 31}
AV1_CRF = {"wide": 55, "mobile": 52, "phone-full": 52, "spot": 50}
# The rooftop Light clip made in round 8b moves more than the one before; these two files are encoded a notch
# lower so they stay within their round 8 size.
CRF_OVERRIDE = {"spot-pro-light": (33, 51), "scene-pricing-mobile-light": (34, 54)}
GOP = FPS * 10  # longer than any clip: one keyframe, no pulse
TMP = Path(os.environ.get("WEB_SCENE_VIDEO_TMP") or Path(tempfile.gettempdir()) / "web-scene-video")

# Cloud drift over one loop, as a share of the picture's width: 8 px on a 1440 px wide page. Two copies
# this far apart are blended halfway through the loop; much more and the halfway frame shows a ghost edge.
DRIFT = 8 / 1440
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
    "footer": {"horizon": 0.8, "boxes": [[0, 0.07, 0.14, 0.32], [0.87, 0.09, 1, 0.31]], "protect": [[0.04, 0, 0.125, 0.16]],
               "fixed": {"dark": [[0.045, 0, 0.22, 0.165]]}},
    "page": {"horizon": 0.82, "boxes": [[0, 0.19, 0.165, 0.4], [0.1, 0.415, 0.18, 0.47], [0.875, 0.14, 1, 0.345], [0.81, 0.375, 0.925, 0.455]],
             "protect": [[0.15, 0.52, 0.195, 0.6], [0.83, 0.47, 0.94, 0.7]]},
}


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

def smooth(e, k):
    """Moving average over k frames, wrapping round (a loop has no ends)."""
    pad = np.concatenate([e[-k:], e, e[:k]])
    return np.convolve(pad, np.ones(k) / k, mode="same")[k:-k]


def find_loop(raw: Path, still_path: Path, horizon: float):
    """Loop points in the clip's active part. Works on grey frames 480 px wide, sky left out (it barely moves,
    and its clouds are replaced anyway). Motion energy = mean absolute difference of consecutive frames;
    a dip = how far its moving average (0.25 s or 0.5 s; the generator's frames come in uneven 2-3 frame
    steps, so single frames say little) falls below its median."""
    sh, sw = cv2.imread(str(still_path)).shape[:2]
    W = 480
    H = round(W * sh / sw)
    H -= H % 2
    data = subprocess.run(["ffmpeg", "-v", "error", "-i", str(raw), "-vf", f"scale={W}:{H}:flags=area", "-f", "rawvideo",
                           "-pix_fmt", "gray", "-"], capture_output=True, check=True).stdout
    f = np.frombuffer(data, np.uint8).reshape(-1, H, W).astype(np.float32)
    s = cv2.resize(cv2.imread(str(still_path), cv2.IMREAD_GRAYSCALE), (W, H), interpolation=cv2.INTER_AREA).astype(np.float32)
    mu = cv2.blur(s, (7, 7))
    flat = np.sqrt(np.maximum(cv2.blur(s * s, (7, 7)) - mu * mu, 0)) < 6
    flat[int(horizon * H):] = False
    m = ~flat
    fm = f[:, m]
    n = len(fm)
    e = np.abs(np.diff(fm, axis=0)).mean(axis=1)
    es = np.convolve(e, np.ones(6) / 6, mode="same")
    mid = np.median(es[n // 5: 4 * n // 5])
    act = np.nonzero(es >= 0.6 * mid)[0]
    a0, a1 = int(act[0]), int(act[-1]) + 1  # without the eased ends
    small = fm[:, ::4]

    def dist(i, j):
        return float(np.abs(small[i] - small[j]).mean())

    cands = []
    for i in range(max(a0, 2), a1):
        for j in range(i + LOOP_MIN, a1 - XF - 1):
            frames = np.mean([dist(i + k, j + k) for k in range(-1, XF + 2, 3)])  # the frames the crossfade mixes
            motion = float(np.abs((small[i + 1] - small[i - 1]) - (small[j + 1] - small[j - 1])).mean())
            cands.append((frames + 0.5 * motion, i, j, frames, motion))
    if not cands:
        raise SystemExit(f"{raw.name}: no active span of {LOOP_MIN + XF} frames; regenerate it")
    cands.sort()

    def build(i, j):
        L = j - i
        out = np.empty((L,) + fm.shape[1:], np.float32)
        for k in range(L):
            a = (k + 1) / (XF + 1) if k < XF else 1.0
            out[k] = fm[j + k] * (1 - a) + fm[i + k] * a if k < XF else fm[i + k]
        return out

    def dips(out):
        le = np.abs(np.diff(np.concatenate([out, out[:1]]), axis=0)).mean(axis=1)  # with the step across the seam
        d6 = 1 - smooth(le, 6).min() / np.median(smooth(le, 6))
        d12 = 1 - smooth(le, 12).min() / np.median(smooth(le, 12))
        return le, d6, d12

    best = None
    for c in cands[:60]:
        out = build(c[1], c[2])
        le, d6, d12 = dips(out)
        score = c[0] + 20 * max(0.0, d12 - 0.25) + 5 * max(0.0, d6 - 0.3)
        if best is None or score < best[0]:
            best = (score, c, out, le, d6, d12)
    _, (_, i, j, frames, motion), out, le, d6, d12 = best
    # start the file at the loop frame nearest the still
    sm = s[m]
    r = int(np.argmin(np.abs(out - (sm - sm.mean() + out.mean(axis=1, keepdims=True))).mean(axis=1)))
    # the old loop (whole clip, its last 14 frames blended into the first), for the record
    k14 = 14
    old = np.stack([fm[n - k14 + k] * (1 - (k + 1) / (k14 + 1)) + fm[k] * (k + 1) / (k14 + 1) if k < k14 else fm[k] for k in range(n - k14)])
    ole, od6, od12 = dips(old)
    return {"frames": n, "active": [a0, a1], "i": i, "j": j, "length": j - i, "seconds": round((j - i) / FPS, 2), "start": r,
            "match": round(frames, 2), "motion_match": round(motion, 2), "dip_025s": round(float(d6), 3), "dip_05s": round(float(d12), 3),
            "old_dip_025s": round(float(od6), 3), "old_dip_05s": round(float(od12), 3),
            "energy": [round(float(x), 3) for x in np.roll(le, -r)], "old_energy": [round(float(x), 3) for x in ole]}


# ---------------------------------------------------------------------------------------------- clouds

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


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
        res = np.linalg.norm(still - fit, axis=-1)
        self.zones = []
        margin = int(round(self.d)) + 48
        reach = int(round(self.d)) + 40
        for k, bx in enumerate(cfg["boxes"]):
            x0, y0 = max(0, int(bx[0] * w) - margin), max(0, int(bx[1] * h) - margin)
            x1, y1 = min(w, int(bx[2] * w) + margin), min(h, int(bx[3] * h) + margin)
            S, F, R = still[y0:y1, x0:x1], fg[y0:y1, x0:x1], res[y0:y1, x0:x1]
            P = prot[y0:y1, x0:x1].astype(bool)
            # the cloud: away from the sky colour, not foreground, not darker than the sky (a bird is), in pieces
            # that reach into the box itself
            brighter = luma(S) > luma(fit[y0:y1, x0:x1]) - 6
            cloud = cv2.morphologyEx(((R > 9) & (F < 0.5) & brighter).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) * (~P)
            n, lab, stats, _ = cv2.connectedComponentsWithStats(cloud, 8)
            inner = np.zeros_like(cloud)
            inner[max(0, int(bx[1] * h) - y0):int(bx[3] * h) - y0, max(0, int(bx[0] * w) - x0):int(bx[2] * w) - x0] = 1
            keep = np.zeros(n, bool)
            for c in range(1, n):
                keep[c] = stats[c, cv2.CC_STAT_AREA] > 150 and bool(inner[lab == c].any())
            cmask = keep[lab]
            grown = cv2.dilate(cmask.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
            alpha = (smoothstep(4, 16, R) * grown * (1 - smoothstep(0.4, 0.8, F))).astype(np.float32)
            # clean plate: the fitted sky plus the sky's own small variations, smoothly carried into the holes
            fitz = fit[y0:y1, x0:x1]
            hole = grown | cv2.dilate((F > 0.15).astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
            skym = (~hole).astype(np.float32)
            resid = np.clip(S - fitz, -14, 14) * skym[..., None]
            num = cv2.GaussianBlur(resid, (0, 0), 18)
            den = cv2.GaussianBlur(skym, (0, 0), 18)[..., None]
            plate = np.where(hole[..., None], fitz + num / np.maximum(den, 1e-3) * (den > 0.02), S)
            # the cloud carried on sideways under the foreground it meets (behind a crown or a trunk), row by
            # row, so a drifted copy or a branch swaying aside never shows a cut edge
            under = F > 0.3
            col, al = S.copy(), alpha.copy()
            filled = np.zeros_like(under)
            for _ in range(reach):
                for sgn in (1, -1):
                    src_a, src_c = np.roll(al, sgn, axis=1), np.roll(col, sgn, axis=1)
                    src_ok = np.roll(~under | filled, sgn, axis=1)
                    src_ok[:, 0 if sgn == 1 else -1] = False
                    take = under & ~filled & src_ok & (src_a > 0.02)
                    al[take], col[take] = src_a[take], src_c[take]
                    filled |= take
            alpha = np.where(under, al * filled, alpha)
            # its colour there painted in smoothly (copying edge pixels along the rows left streaks that showed
            # through gaps between the leaves as the copy drifted)
            col = np.where(filled[..., None], cv2.inpaint(np.clip(S, 0, 255).astype(np.uint8), filled.astype(np.uint8) * 255, 9,
                                                          cv2.INPAINT_TELEA).astype(np.float32), S)
            # replaced only around the clouds (room for the drift and the generator's wobbly outline), so gaps
            # between leaves elsewhere keep the video's own sky
            rep = cv2.dilate(cmask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * (int(self.d) + 22) + 1,) * 2))
            rep[cv2.dilate(P.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool)] = 0
            zw = np.clip(cv2.GaussianBlur(rep.astype(np.float32), (0, 0), 6) * 1.6, 0, 1)
            self.zones.append({"box": (x0, y0, x1, y1), "plate": plate.astype(np.float32), "layer": col.astype(np.float32),
                               "alpha": alpha.astype(np.float32), "zw": zw, "still": k in cfg.get("still", ()), "cmask": cmask})
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
            fgv = np.maximum(foreground(v, self.theme), smoothstep(18, 40, luma(z["plate"]) - luma(v)))
            k = (z["zw"] * (1 - fgv))[..., None]
            frame[y0:y1, x0:x1] = v * (1 - k) + self.sky(z, u) * k
        if self.fixed is not None:
            x0, y0, x1, y1, m, pic = self.fixed
            frame[y0:y1, x0:x1] = frame[y0:y1, x0:x1] * (1 - m) + pic * m


# ----------------------------------------------------------------------------------------------- files

class Sink:
    """One output: a crop of the frame, resized, written losslessly (FFV1) to a master in TMP."""

    def __init__(self, name: str, kind: str, box, shape):
        th0, tw0 = shape
        self.box = None
        if box:
            x0, y0, x1, y1 = round(box[0] * tw0), round(box[1] * th0), round(box[2] * tw0), round(box[3] * th0)
            self.box = (x0, y0, x1, y1)
            tw0, th0 = x1 - x0, y1 - y0
        width = WIDTH[kind]
        self.size = (width - width % 2, (lambda v: v - v % 2)(round(th0 * width / tw0)))
        self.name, self.kind = name, kind
        TMP.mkdir(parents=True, exist_ok=True)
        self.proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{self.size[0]}x{self.size[1]}",
             "-r", str(FPS), "-i", "-", "-c:v", "ffv1", "-pix_fmt", "gbrp", str(TMP / f"{name}.mkv")],
            stdin=subprocess.PIPE,
        )

    def write(self, frame):
        if self.box:
            x0, y0, x1, y1 = self.box
            frame = frame[y0:y1, x0:x1]
        self.proc.stdin.write(cv2.resize(frame, self.size, interpolation=cv2.INTER_AREA).astype(np.uint8).tobytes())

    def close(self):
        self.proc.stdin.close()
        if self.proc.wait():
            raise SystemExit(f"master failed for {self.name}")
        (TMP / f"{self.name}.json").write_text(json.dumps({"kind": self.kind, "w": self.size[0], "h": self.size[1]}))


def encode(name: str):
    """H.264 and AV1 from a master, one after the other (several AV1 encoders at once run out of memory)."""
    meta = json.loads((TMP / f"{name}.json").read_text())
    kind = meta["kind"]
    OUT.mkdir(parents=True, exist_ok=True)
    h264_file, av1_file = OUT / f"{name}.mp4", OUT / f"{name}.av1.mp4"
    common = ["ffmpeg", "-v", "error", "-y", "-i", str(TMP / f"{name}.mkv"), "-an", "-g", str(GOP),
              "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
              "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-movflags", "+faststart"]
    crf_h264, crf_av1 = CRF_OVERRIDE.get(name, (H264_CRF[kind], AV1_CRF[kind]))
    subprocess.run(common + ["-c:v", "libx264", "-preset", "slow", "-crf", str(crf_h264), "-profile:v", "high",
                             "-x264-params", "scenecut=0", str(h264_file)], check=True)
    subprocess.run(common + ["-c:v", "libsvtav1", "-preset", "6", "-crf", str(crf_av1),
                             "-svtav1-params", "tune=0:scd=0", str(av1_file)], check=True, stderr=subprocess.DEVNULL)
    h264, av1 = h264_file.stat().st_size, av1_file.stat().st_size
    print(f"    {name}: {meta['w']}x{meta['h']}  h264 {h264 / 1e6:.2f} MB  av1 {av1 / 1e6:.2f} MB", flush=True)
    entry = {"w": meta["w"], "h": meta["h"], "h264": f"{URL}/{h264_file.name}"}
    if av1 < h264 * 0.85:
        entry["av1"] = f"{URL}/{av1_file.name}"
    else:
        av1_file.unlink()
    return entry


def render(src_img: Path, raw: Path, scene: str, theme: str, make_sinks):
    """Resample, colour-match, loop and re-cloud the raw clip, feeding every frame to the sinks."""
    still = cv2.cvtColor(cv2.imread(str(src_img), cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    sh, sw = still.shape[:2]
    w, h = probe(raw)
    ar = sw / sh
    # The picture's shape at the clip's resolution: squeezed across (the hero) or a hair shorter.
    tw, th = (round(h * ar), h) if w / h > ar else (w, round(w / ar))
    loop = find_loop(raw, src_img, CLOUDS[scene]["horizon"])
    i, L, r = loop["i"], loop["length"], loop["start"]
    j = loop["j"]

    def fit(f):
        return cv2.resize(f, (tw, th), interpolation=cv2.INTER_AREA)

    ref = cv2.resize(still, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)
    clouds = Clouds(ref, scene, theme)
    # pass 1: the colour gain (from the first frame, which is the still) and the frames the crossfade mixes in
    tail = {}
    first = None
    for t, f in enumerate(frames_of(raw)):
        if t == 0:
            first = fit(f).astype(np.float32)
        if j <= t < j + XF:
            tail[t - j] = fit(f)
        if t >= j + XF:
            break
    gain = ref.reshape(-1, 3).mean(0) / np.maximum(first.reshape(-1, 3).mean(0), 1)
    print(f"  {raw.name}: {w}x{h} -> {tw}x{th}; loop {i}..{j} ({L} frames, {L / FPS:.2f} s), starts at {r}; "
          f"dip {loop['dip_025s']:.0%} / {loop['dip_05s']:.0%} (was {loop['old_dip_025s']:.0%} / {loop['old_dip_05s']:.0%}); "
          f"drift {clouds.d:.1f} px; gain {np.round(gain, 3).tolist()}", flush=True)
    sinks = make_sinks((th, tw))
    # pass 2, twice: the file starts at loop frame r, so frames r..L-1 come first, then 0..r-1
    for lo, hi in ((r, L), (0, r)):
        if lo == hi:
            continue
        for t, f in enumerate(frames_of(raw)):
            k = t - i
            if k < lo:
                continue
            if k >= hi:
                break
            g = fit(f).astype(np.float32)
            if k < XF:
                a = (k + 1) / (XF + 1)
                g = tail[k].astype(np.float32) * (1 - a) + g * a
            g *= gain
            clouds.apply(g, ((k - r) % L) / L)
            np.clip(g, 0, 255, out=g)
            for s in sinks:
                s.write(g)
    for s in sinks:
        s.close()
    loop["drift_px"] = round(clouds.d, 1)
    loop["drift_css_px_at_1440"] = round(DRIFT * 1440, 1)
    return loop


encode_only = sys.argv[1] == "--encode-only"
raw_dir = None if encode_only else Path(sys.argv[1])
only = set(sys.argv[2:])
slots = SCREENS["slots"]

manifest = {}
if MANIFEST.exists() and only:
    text = MANIFEST.read_text(encoding="utf8")
    manifest = json.loads(text[text.index("= ") + 2: text.rindex(" as const")])
loops = json.loads(LOOPS.read_text(encoding="utf8")) if LOOPS.exists() else {}

for slot, cfg in slots.items():
    if cfg.get("kind") != "scene" or "wide" in cfg:
        continue
    spots = {s: c for s, c in slots.items() if c.get("kind") == "scene" and "wide" in c and c["light"] == cfg["light"]}
    wanted = [s for s in [slot, *spots] if not only or s in only]
    if not wanted:
        continue
    print(slot, flush=True)
    for theme in ("light", "dark"):
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
            loops[src.stem] = render(src, raw_dir / f"{src.stem}.mp4", scene, theme,
                                     lambda shape: [Sink(n, k, b, shape) for n, (k, b) in names.items()])
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
MANIFEST.write_text(
    "// Written by scripts/web-scene-video.py. Don't edit by hand.\n"
    "// Per slot: the wide and phone loops in Light and Dark (H.264, plus AV1 where it is smaller) and the\n"
    "// foreground cut-out's box in fractions of the picture.\n"
    f"export const sceneVideos = {json.dumps(manifest, indent=2, sort_keys=True)} as const;\n",
    encoding="utf8",
)
if not encode_only:
    LOOPS.write_text(json.dumps(loops, indent=1, sort_keys=True) + "\n", encoding="utf8")
