"""Video loops for the site's illustrated scenes (web/components/marketing/scene-video.tsx).

Each scene picture in art/web/gen2/ (Light and Dusk) was animated by an image-to-video model (MiniMax H3,
2K; prompts and job IDs in art/web/credits.md and video-prompts.md). This script turns those raw clips into
the files the page plays:

- resampled to the picture's exact shape (the hero is 3:2 and went to the model stretched to 16:9, so it is
  squeezed back here) and matched to the still's colours;
- only nature moves: the clip shows only inside the scene's nature (art/web/scene-nature.json) and where it moves;
  everything else, and the people and objects of art/web/held/ on top of it all, is the still in every frame;
- looped without a calm: each separate piece of nature has its own loop, all of one length (at least LOOP_MIN), cut
  where the ends match best in picture and in motion, joined by an XF-frame optical-flow morph, and turned round so
  that the pieces' lulls don't fall together (find_loops);
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
  flower bed, which the page redraws from the video in front of the phone), and the loop points, energy dips
  and drift in art/web/video-loops.json.

$WEB_SCENE_VIDEO_THEMES (light, dark or light,dark) limits a run to one theme; with $WEB_SCENE_VIDEO_SAME_LOOPS set the
loops recorded in video-loops.json are cut again instead of searched for (while the nature polygons keep their order).

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
LOOP_MIN = round(4.5 * FPS)  # shortest loop
XF = 12  # crossfade at the loop point (0.5 s)
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


def held_mask(scene: str, shape):
    """Everything that must look like the still in every frame, whatever the clip does there: the people, what they wear
    and hold, animals, and the objects (art/web/held/, drawn at the still's outlines), plus the scene's own `hold`
    polygons, minus its `free` ones (flowers caught in the outlines)."""
    cfg = NATURE[scene]
    h, w = shape
    m = cv2.resize(cv2.imread(str(ROOT / f"art/web/held/{scene}.png"), cv2.IMREAD_GRAYSCALE), (w, h), interpolation=cv2.INTER_LINEAR) > 127
    m[polygons(cfg.get("free", []), shape) > 0] = False
    m[polygons(cfg.get("hold", []), shape) > 0] = True
    return m


def nature_zone(scene: str, theme: str, shape):
    """Where the clip may show at all: the scene's nature polygons, without the held things."""
    cfg = NATURE[scene]
    z = polygons(cfg["nature"] + cfg.get(f"nature_{theme}", []), shape) > 0
    if "leafy" in cfg:
        # tree lines in front of buildings: only what is plant-coloured in the Light picture (the Dusk one has the same
        # outlines), so no building is ever in the zone
        h, w = shape
        pic = cv2.resize(cv2.imread(str(ROOT / f"art/web/gen2/{scene}-light.webp")), (w, h), interpolation=cv2.INTER_AREA).astype(np.float32)
        b, g, r = pic[..., 0], pic[..., 1], pic[..., 2]
        leaf = ((g - b > 22) & ((g - r > -5) | (g - b > 60))).astype(np.uint8)
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * round(w / 480) + 1,) * 2)
        leaf = cv2.morphologyEx(cv2.morphologyEx(leaf, cv2.MORPH_CLOSE, k), cv2.MORPH_OPEN, k) * polygons(cfg["leafy"], shape)
        n, lab, stats, _ = cv2.connectedComponentsWithStats(leaf)
        small = stats[:, cv2.CC_STAT_AREA] < 0.002 * w * h  # roof gardens, reflections
        leaf[small[lab]] = 0
        big = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * round(w / 160) + 1,) * 2)
        leaf = cv2.morphologyEx(leaf, cv2.MORPH_OPEN, big) | (leaf & (cv2.dilate(cv2.morphologyEx(leaf, cv2.MORPH_OPEN, big), k) > 0))
        z |= (polygons(cfg["leafy"], shape) > 0) & (leaf > 0)
    z[polygons(cfg.get(f"hold_{theme}", []), shape) > 0] = False
    return z & ~held_mask(scene, shape)


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


def smooth(e, k):
    """Moving average over k frames, wrapping round (a loop has no ends)."""
    pad = np.concatenate([e[-k:], e, e[:k]])
    return np.convolve(pad, np.ones(k) / k, mode="same")[k:-k]


def regions_of(zone, scene: str, theme: str):
    """The pieces of nature that loop by themselves, as a label picture (1..n, 0 = none): one per nature polygon (an
    earlier one wins where they overlap), the leafy areas and Dusk's extra ones, and the `solo` things (a butterfly,
    birds) on top."""
    cfg = NATURE[scene]
    lab = np.zeros(zone.shape, np.int32)
    k = 0
    rest = cfg.get("leafy", []) + cfg.get(f"nature_{theme}", [])
    for pl in cfg["nature"] + rest:
        k += 1
        lab[(polygons([pl], zone.shape) > 0) & zone & (lab == 0)] = k
    for pl in cfg.get("solo", []):
        k += 1
        lab[(polygons([pl], zone.shape) > 0) & zone] = k
    return lab, k


def dip(e, k):
    s = smooth(e, k)
    return float(1 - s.min() / max(np.median(s), 1e-6))


def find_loops(frames, weight, lab, count):
    """One loop length for the whole picture, and for every region the frame its loop starts at (i) and how far it is
    turned round (phase). frames: n grey frames 480 px wide; weight: how much each pixel shows (0..1). A region's loop
    runs i..i+L; the best are those whose two ends match in picture and in motion and whose motion never dies down (the
    generator eases in and out of its keyframes). The phases are then set so that the regions' lulls, at the ends of
    their sways, don't fall together: the picture as a whole never goes calm. Motion energy = summed absolute
    difference of consecutive frames; a dip = how far its moving average (0.25 s or 0.5 s; the generator's frames come
    in uneven 2-3 frame steps) falls below its median."""
    n = len(frames)
    regs = []
    for q in range(1, count + 1):
        sel = (lab == q) & (weight > 0.3)
        area = int(sel.sum())
        if area < 12:
            regs.append(None)
            continue
        s = frames[:, sel][:, ::max(1, area // 2500)]
        v = np.zeros_like(s)
        v[1:-1] = s[2:] - s[:-2]
        d = np.stack([np.abs(s - s[t]).mean(axis=1) for t in range(n)])
        dv = np.stack([np.abs(v - v[t]).mean(axis=1) for t in range(n)])
        e = np.abs(np.diff(s, axis=0)).mean(axis=1) * area
        regs.append({"d": d, "dv": dv, "e": np.append(e, e[-1]), "area": area, "scale": float(np.median(d[d > 0]))})

    def cost(rg, L):
        """Per start frame i: how badly the two ends match, plus what a lull in the region's own motion costs."""
        out = np.full(n, np.inf)
        for i in range(2, n - L - XF - 1):
            j = i + L
            match = np.mean([rg["d"][i + k, j + k] for k in range(0, XF, 2)])
            motion = rg["dv"][i + XF // 2, j + XF // 2]
            out[i] = (match + 0.5 * motion) / rg["scale"] + 0.8 * max(0.0, dip(rg["e"][i:j], 24) - 0.3)
        return out

    def energy(rg, i, L):
        a = (np.arange(XF) + 1) / (XF + 1)
        e = rg["e"][i:i + L].copy()
        e[:XF] = e[:XF] * a + rg["e"][i + L:i + L + XF] * (1 - a)
        return e

    live = [q for q, rg in enumerate(regs) if rg]
    weights = np.array([regs[q]["area"] ** 0.5 for q in live])
    table = {}
    for L in range(LOOP_MIN, n - XF - 4):
        cs = [cost(regs[q], L) for q in live]
        score = float(np.average([c.min() for c in cs], weights=weights)) - 0.0025 * (L - LOOP_MIN)
        table[L] = (score, cs)

    def obj(total):
        return max(0.0, dip(total, 6) - 0.1) + 1.5 * max(0.0, dip(total, 12) - 0.05) + 4 * max(0.0, dip(total, 12) - 0.15)

    best = None
    rng = np.random.default_rng(1)
    bins = {}
    for L in sorted(table, key=lambda L: table[L][0]):
        if len(bins.setdefault((L - LOOP_MIN) // 8, [])) < 2:
            bins[(L - LOOP_MIN) // 8].append(L)
    for L in sorted(sum(bins.values(), [])):
        score, cs = table[L]
        opts = []
        for c in cs:
            good = np.nonzero(c <= c.min() + 0.06)[0]
            opts.append(sorted(good, key=lambda i: c[i])[:6])
        for trial in range(2):
            pick = [(int(o[0]), int(rng.integers(L)) if trial else 0) for o in opts]
            curves = [np.roll(energy(regs[q], i, L), -ph) for q, (i, ph) in zip(live, pick)]
            total = np.sum(curves, axis=0)
            for _ in range(3):
                for z, q in enumerate(live):
                    rest = total - curves[z]
                    cur = None
                    for i in opts[z]:
                        base = energy(regs[q], int(i), L)
                        extra = 0.5 * (cs[z][i] - cs[z].min()) * weights[z] / weights.sum()
                        for ph in range(0, L, 4):
                            cv = np.roll(base, -ph)
                            o = obj(rest + cv) + extra
                            if cur is None or o < cur - 1e-6:
                                cur, pick[z], curves[z] = o, (int(i), ph), cv
                    total = rest + curves[z]
            final = score + obj(total)
            if best is None or final < best[0]:
                best = (final, L, list(pick), total.copy(), [float(c[i]) for c, (i, _ph) in zip(cs, pick)])
    _, L, pick, total, match = best
    loops = {q + 1: pk for q, pk in zip(live, pick)}
    return {"length": L, "seconds": round(L / FPS, 2), "regions": {str(q): {"i": i, "phase": ph} for q, (i, ph) in loops.items()},
            "match": [round(m, 2) for m in match], "dip_025s": round(dip(total, 6), 3), "dip_05s": round(dip(total, 12), 3),
            "energy": [round(float(x / total.mean()), 3) for x in total]}


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
    """One output: a crop of the frame, resized, written losslessly (FFV1) to a master in TMP."""

    def __init__(self, name: str, kind: str, box, shape):
        th0, tw0 = shape
        self.frac = box
        if box:
            x0, y0, x1, y1 = round(box[0] * tw0), round(box[1] * th0), round(box[2] * tw0), round(box[3] * th0)
            tw0, th0 = x1 - x0, y1 - y0
        width = WIDTH[kind]
        self.size = (width - width % 2, (lambda v: v - v % 2)(round(th0 * width / tw0)))
        self.name, self.kind = name, kind
        self.join = None  # the master frame where the join starts; set by render
        TMP.mkdir(parents=True, exist_ok=True)
        self.proc = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{self.size[0]}x{self.size[1]}",
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

    def write(self, frame):
        self.proc.stdin.write(np.clip(self.cut(frame) + self.fix + 0.5, 0, 255).astype(np.uint8).tobytes())

    def close(self):
        self.proc.stdin.close()
        if self.proc.wait():
            raise SystemExit(f"master failed for {self.name}")
        (TMP / f"{self.name}.json").write_text(json.dumps({"kind": self.kind, "w": self.size[0], "h": self.size[1], "join": self.join}))


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


def quiet_start(name: str, w: int, h: int, join, n: int):
    """The frame after a quiet step of the master, so that the file's own wrap (last frame back to the first) lands where
    the picture barely moves; never inside the join, whose frames are blends. Of the quiet steps (the quietest fiftieth)
    the one whose picture is nearest the still, so the page's fade from picture to video stays soft."""
    still = still_grey(name, w, h)
    prev = first = None
    steps = np.empty(n)
    dist = np.empty(n)
    for t, fr in enumerate(master_yuv(name, w, h)):
        y = cv2.resize(fr[:w * h].reshape(h, w), (max(1, w // 4), max(1, h // 4)), interpolation=cv2.INTER_AREA).astype(np.float32)
        dist[t] = np.abs(y - y.mean() - still + still.mean()).mean()
        if prev is None:
            first = y
        else:
            steps[t] = np.abs(y - prev).mean()
        prev = y
    steps[0] = np.abs(first - prev).mean()  # steps[t] = |f[t] - f[t-1]|, round the loop
    if join is not None:
        for t in range(n):
            if (t - join) % n <= XF + 1:
                steps[t] = np.inf
    quiet = np.percentile(steps[np.isfinite(steps)], 2)
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
    start = meta["start"] = quiet_start(name, w, h, meta["join"], n)
    (TMP / f"{name}.json").write_text(json.dumps(meta))  # the checks that look at the join need to know where it landed
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
    entry = {"w": w, "h": h, "h264": f"{URL}/{h264_file.name}"}
    print(f"    {name}: {w}x{h} starts {start}; h264 {best[1]} {len(best[2]) / 1e6:.3f} MB wrap {best[0]:.2f} x p90", flush=True)
    return entry


def warp_pair(a_img, b_img, a, dis):
    """a_img and b_img (float RGB), each slid along the optical flow between them (DIS, both ways, at half size)
    towards the frame a of the way from a_img to b_img."""
    h, w = a_img.shape[:2]
    small = (w // 2, h // 2)
    ga = cv2.resize(cv2.cvtColor(np.clip(a_img, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY), small, interpolation=cv2.INTER_AREA)
    gb = cv2.resize(cv2.cvtColor(np.clip(b_img, 0, 255).astype(np.uint8), cv2.COLOR_RGB2GRAY), small, interpolation=cv2.INTER_AREA)
    fab = cv2.resize(dis.calc(ga, gb, None), (w, h), interpolation=cv2.INTER_LINEAR) * 2
    fba = cv2.resize(dis.calc(gb, ga, None), (w, h), interpolation=cv2.INTER_LINEAR) * 2
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
    wa = cv2.remap(a_img, gx - a * fab[..., 0], gy - a * fab[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    wb = cv2.remap(b_img, gx - (1 - a) * fba[..., 0], gy - (1 - a) * fba[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    return wa, wb


def join_frames(tails, heads, dis, cut):
    """The XF frames that carry a region's loop end over into its start. tails and heads: its frames right after the
    loop's end and right after its start (uint8 RGB). Every frame is a morph: both poses are slid along the optical flow
    towards a common middle, then blended, so a pose that differs moves across instead of showing twice. `cut` (a soft
    mask, or None): birds, which the flow can't follow, just fade over."""
    frames = []
    for k in range(XF):
        a = (k + 1) / (XF + 1)
        ta, hd = tails[k].astype(np.float32), heads[k].astype(np.float32)
        wa, wb = warp_pair(ta, hd, a, dis)
        d = cv2.GaussianBlur(np.abs(wa - wb).mean(axis=2), (0, 0), 2)
        u = smoothstep(10, 35, d)[..., None]  # a little disagreement: switch within a few frames
        ae = a * (1 - u) + smoothstep(0.3, 0.7, a) * u
        f = wa * (1 - ae) + wb * ae
        if cut is not None:
            f = f * (1 - cut) + (ta * (1 - a) + hd * a) * cut
        frames.append(np.clip(f, 0, 255).astype(np.uint8))
    return frames


def render(src_img: Path, raw: Path, scene: str, theme: str, make_sinks):
    """Resample, colour-match, loop and re-cloud the raw clip, and lay the nature of every frame over the still."""
    still = cv2.cvtColor(cv2.imread(str(src_img), cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    sh, sw = still.shape[:2]
    w, h = probe(raw)
    ar = sw / sh
    # The picture's shape at the clip's resolution: squeezed across (the hero) or a hair shorter.
    tw, th = (round(h * ar), h) if w / h > ar else (w, round(w / ar))
    unit = th / 1440
    ref = cv2.resize(still, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)
    zone = nature_zone(scene, theme, (th, tw))
    lab, count = regions_of(zone, scene, theme)
    quarter = (tw // 4, th // 4)
    refq = cv2.resize(ref, quarter, interpolation=cv2.INTER_AREA)
    # pass 1: every frame, colour-matched to the still. The overall gain comes from the first frame, which is the still;
    # the generator's colours also wander a little: where a frame is within a few levels of the still nothing moved, so
    # the difference there, smoothed, is the local colour error.
    TMP.mkdir(parents=True, exist_ok=True)
    store = TMP / f"{src_img.stem}.frames"
    gw = 480
    gh = round(gw * th / tw)
    grey, far, gain, n = [], None, None, 0
    with open(store, "wb") as fh:
        for f in frames_of(raw):
            g = cv2.resize(f, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)
            if gain is None:
                gain = ref.reshape(-1, 3).mean(0) / np.maximum(g.reshape(-1, 3).mean(0), 1)
                far = np.zeros((th, tw), np.float32)
            g *= gain
            off = refq - cv2.resize(g, quarter, interpolation=cv2.INTER_AREA)
            calm = (np.abs(off).max(axis=2) < 7).astype(np.float32)
            num = cv2.GaussianBlur(off * calm[..., None], (0, 0), 12 * unit)
            den = cv2.GaussianBlur(calm, (0, 0), 12 * unit)[..., None]
            g += cv2.resize(num / (den + 0.05), (tw, th), interpolation=cv2.INTER_LINEAR)
            g = np.clip(g + 0.5, 0, 255).astype(np.uint8)
            fh.write(g.tobytes())
            if n % 2 == 0:
                far = np.maximum(far, cv2.GaussianBlur(np.abs(g.astype(np.float32) - ref).max(axis=2), (0, 0), 1.5 * unit))
            grey.append(cv2.resize(cv2.cvtColor(g, cv2.COLOR_RGB2GRAY), (gw, gh), interpolation=cv2.INTER_AREA))
            n += 1
    frames = np.memmap(store, np.uint8, "r", shape=(n, th, tw, 3))
    # where the nature moves at all; elsewhere in its zone the picture is the still too, so the edge between the two
    # always lies where there is hardly a difference. Eased off towards the zone's edges, and over the last pixels next
    # to a held thing (the clip's own character reaches a little past the still's outline).
    held_px = held_mask(scene, (th, tw)).astype(np.uint8)
    moved = cv2.dilate(far, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * round(4 * unit) + 1,) * 2))
    show = cv2.GaussianBlur(smoothstep(7, 16, moved), (0, 0), 4 * unit)
    away = cv2.distanceTransform(zone.astype(np.uint8), cv2.DIST_L2, 5) / unit
    show *= smoothstep(2, 7, away)
    # the held things, 2 px grown with a 2 px feather
    reach = cv2.distanceTransform(1 - held_px, cv2.DIST_L2, 5) / unit
    held = np.clip((4 - reach) / 2, 0, 1).astype(np.float32)
    clouds = Clouds(ref, scene, theme)
    # what can change at all, for the sinks: the rest is the still, resampled straight from the picture
    change = show.copy()
    for z in clouds.zones:
        x0, y0, x1, y1 = z["box"]
        change[y0:y1, x0:x1] = np.maximum(change[y0:y1, x0:x1], z["zw"])
    change *= 1 - held
    weight = cv2.resize(show * (1 - held), (gw, gh), interpolation=cv2.INTER_AREA)
    labs = cv2.resize(lab.astype(np.int16), (gw, gh), interpolation=cv2.INTER_NEAREST)
    loop = json.loads(LOOPS.read_text(encoding="utf8")).get(src_img.stem) if os.environ.get("WEB_SCENE_VIDEO_SAME_LOOPS") else None
    if not loop or "regions" not in loop:
        loop = find_loops(np.stack(grey).astype(np.float32), weight, labs, count)
    L = loop["length"]
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    birds = polygons(NATURE[scene].get("birds", []), (th, tw)).astype(np.float32)
    parts = []
    # each region's share of a pixel: where two of them touch they blend over a few pixels
    total = np.full((th, tw), 1e-4, np.float32)
    shares = {}
    for q in loop["regions"]:
        shares[q] = cv2.GaussianBlur((lab == int(q)).astype(np.float32), (0, 0), 5 * unit)
        total += shares[q]
    for q, pk in loop["regions"].items():
        share = shares.pop(q) / total
        m = (share > 0.01) & (show > 0.002)
        ys, xs = np.nonzero(m)
        if not len(ys):
            continue
        pad = 24
        y0, y1, x0, x1 = max(0, ys.min() - pad), min(th, ys.max() + pad + 1), max(0, xs.min() - pad), min(tw, xs.max() + pad + 1)
        i, j = pk["i"], pk["i"] + L
        cut = birds[y0:y1, x0:x1]
        cut = cv2.GaussianBlur(cut, (0, 0), 6 * unit)[..., None] if cut.any() else None
        joined = join_frames([np.array(frames[j + k, y0:y1, x0:x1]) for k in range(XF)],
                             [np.array(frames[i + k, y0:y1, x0:x1]) for k in range(XF)], dis, cut)
        a = (show[y0:y1, x0:x1] * share[y0:y1, x0:x1])[..., None]
        parts.append((i, pk["phase"], y0, y1, x0, x1, a, joined))
    print(f"  {raw.name}: {w}x{h} -> {tw}x{th}; loop of {L} frames ({L / FPS:.2f} s) in {len(parts)} regions "
          f"{[(p[0], p[1]) for p in parts]}; match {loop['match']}; dip {loop['dip_025s']:.0%} / {loop['dip_05s']:.0%}; moving "
          f"{float((show * (1 - held) > 0.5).mean()):.0%} of the picture; drift {clouds.d:.1f} px; gain {np.round(gain, 3).tolist()}", flush=True)
    sinks = make_sinks((th, tw))
    for s in sinks:
        s.keep(still, ref, change)
    for t in range(L):
        # the still everywhere but in the nature; the clouds drift over that; the held things on top of it all
        g = ref.copy()
        for i, ph, y0, y1, x0, x1, a, joined in parts:
            k = (t + ph) % L
            patch = joined[k] if k < XF else frames[i + k, y0:y1, x0:x1]
            g[y0:y1, x0:x1] += (patch.astype(np.float32) - ref[y0:y1, x0:x1]) * a
        clouds.apply(g, t / L)
        g += (ref - g) * held[..., None]
        np.clip(g, 0, 255, out=g)
        for s in sinks:
            s.write(g)
    for s in sinks:
        s.close()
    frames._mmap.close()
    store.unlink()
    loop["drift_px"] = round(clouds.d, 1)
    loop["drift_css_px_at_1440"] = round(DRIFT * 1440, 1)
    return loop


encode_only = sys.argv[1] == "--encode-only"
render_only = sys.argv[1] == "--render-only"  # masters only, for --encode-only later
raw_dir = None if encode_only else Path(sys.argv[2] if render_only else sys.argv[1])
only = set(sys.argv[3:] if render_only else sys.argv[2:])
slots = SCREENS["slots"]



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
                                     lambda shape: [Sink(n, k, b, shape) for n, (k, b) in names.items()])
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
