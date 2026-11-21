#!/usr/bin/env python3
"""Motion data for the site's illustrated scenes (web/components/marketing/scene-motion.tsx).

The scenes stay the pictures web-compose.py exports. This script makes what the Three.js layer needs to
bring them to life, per scene and per theme (Light and Dusk), from the regions authored in
art/web/motion.json:

  {scene}-{theme}-mask.webp    half-size, lossless. R: wind sway weight (tree crowns, bushes, flowers).
                               G: water. B: 0 where a tree or anything solid hides the sky layer (clouds
                               and birds pass behind it), 128 elsewhere, 255 where a painted element was
                               cut out and the clean plate shows instead.
  {scene}-{theme}-plate.webp   the clean plate: the sky (a smooth model fitted around each cut-out, as
                               web-hero-erase-kite.py does) or inpainted grass behind what was cut out.
                               Grey everywhere else, so it stays small.
  {scene}-{theme}-atlas.webp   the cut-outs with alpha: clouds, the two painted birds, the kite and its
                               tail, the butterflies.

plus web/components/marketing/motion-manifest.ts, and review pictures in art/web/review/motion/:
{scene}-masks.jpg (the masks tinted over the art), {scene}-{theme}-plate.jpg (the art with everything
cut out) and {scene}-{theme}-atlas.jpg.

Structure (what sways, what is solid) is read from the Light picture and used for both themes: the two
are the same drawing, aligned to the pixel. Cut-outs are made per theme.

    python scripts/web-motion.py                 # every scene
    python scripts/web-motion.py scene-footer    # some

Needs Pillow, numpy, OpenCV and scipy.
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra

ROOT = Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "art/web/motion.json").read_text(encoding="utf8"))
SCREENS = json.loads((ROOT / "art/web/screens.json").read_text(encoding="utf8"))
OUT = ROOT / CFG["output"]
REVIEW = ROOT / CFG["review"]

MASK_SCALE = 0.5
PLATE_SCALE = 0.5
CLOUD_SCALE = 0.6  # clouds are soft; everything else is cut at full size
# The shader moves a pixel of weight 1 by at most this many source pixels. The sway weight falls to zero
# towards anything solid over four times this distance, so a character's or a building's edge never moves.
MAX_SHIFT = 14
GATE_MARGIN = 5
GATE_FALLOFF = 4 * MAX_SHIFT


# ----------------------------------------------------------------------------------------- helpers


def load(path):
    return np.asarray(Image.open(ROOT / path).convert("RGB")).astype(np.float32)


def ellipse(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def dilate(mask, r):
    return cv2.dilate(mask.astype(np.uint8), ellipse(r)).astype(bool)


def erode(mask, r):
    return cv2.erode(mask.astype(np.uint8), ellipse(r)).astype(bool)


def opened(mask, r):
    return cv2.morphologyEx(mask.astype(np.uint8), cv2.MORPH_OPEN, ellipse(r)).astype(bool)


def big_parts(mask, min_area):
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= min_area
    return keep[labels]


def px_box(box, w, h, pad=0):
    x0, y0, x1, y1 = box
    return (
        max(0, int(round(x0 * w)) - pad),
        max(0, int(round(y0 * h)) - pad),
        min(w, int(round(x1 * w)) + pad),
        min(h, int(round(y1 * h)) + pad),
    )


def poly_mask(poly, w, h):
    m = np.zeros((h, w), np.uint8)
    cv2.fillPoly(m, [np.round(np.array(poly) * [w, h]).astype(np.int32)], 1)
    return m.astype(bool)


def classify(light):
    """From the Light picture: what is foliage, and what is open sky or cloud ("free")."""
    r, g, b = light[..., 0], light[..., 1], light[..., 2]
    hsv = cv2.cvtColor(light.astype(np.uint8), cv2.COLOR_RGB2HSV)
    hue, sat, val = hsv[..., 0].astype(np.int32) * 2, hsv[..., 1], hsv[..., 2]
    foliage = (hue >= 38) & (hue <= 175) & (sat >= 55) & (val >= 30)
    sky = (b > r + 15) & (b >= g) & (val > 120)
    white = np.minimum(np.minimum(r, g), b) > 205
    return foliage, sky, sky | white


def sky_model(img, cand, region):
    """A smooth sky for `region` (x0, y0, x1, y1): a low-order polynomial fitted to the candidate sky pixels
    there, with outliers (stars, a contrail, cloud wisps) trimmed. Returns (evaluate(box), grain sigma)."""
    x0, y0, x1, y1 = region
    cx, cy, sx, sy = (x0 + x1) / 2, (y0 + y1) / 2, max(1, (x1 - x0) / 2), max(1, (y1 - y0) / 2)

    def feats(x, y):
        x = (x - cx) / sx
        y = (y - cy) / sy
        return np.stack([np.ones_like(x), x, y, x * x, y * y, x * y, y**3], -1)

    ys, xs = np.nonzero(cand[y0:y1, x0:x1])
    if len(xs) < 400:
        return None
    if len(xs) > 60000:
        pick = np.random.default_rng(1).choice(len(xs), 60000, replace=False)
        xs, ys = xs[pick], ys[pick]
    xs = xs + x0
    ys = ys + y0
    A = feats(xs.astype(np.float64), ys.astype(np.float64))
    vals = img[ys, xs].astype(np.float64)
    keep = np.ones(len(xs), bool)
    for _ in range(3):
        coef, *_ = np.linalg.lstsq(A[keep], vals[keep], rcond=None)
        res = np.linalg.norm(vals - A @ coef, axis=1)
        sigma = float(np.sqrt(np.mean(res[keep] ** 2)))
        keep = res < 2.5 * sigma + 1e-6
    coef, *_ = np.linalg.lstsq(A[keep], vals[keep], rcond=None)

    def evaluate(box):
        bx0, by0, bx1, by1 = box
        gy, gx = np.mgrid[by0:by1, bx0:bx1].astype(np.float64)
        return (feats(gx, gy) @ coef).clip(0, 255).astype(np.float32)

    return evaluate, sigma


def fit_sky(img, cand, box, w, h, horizon):
    """The sky around a box: fitted on the box grown by 60% of its size, wider when there is too little sky."""
    x0, y0, x1, y1 = box
    for grow in (0.6, 1.2, 2.5, 6):
        gx, gy = int((x1 - x0) * grow) + 60, int((y1 - y0) * grow) + 60
        region = (max(0, x0 - gx), max(0, y0 - gy), min(w, x1 + gx), min(int(horizon * h), y1 + gy))
        model = sky_model(img, cand, region)
        if model:
            return model
    raise SystemExit(f"no sky found around {box}")


def bleed(rgb, alpha):
    """Fill the colour of transparent pixels from the nearest opaque one, so bilinear sampling and lossy
    compression don't pull a dark fringe in at the sprite's edge."""
    solid = alpha > 0.03
    if not solid.any():
        return rgb
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


# ----------------------------------------------------------------------------------------- structure


def structure(scene, slot, light, w, h):
    """Sway weight, water and the solid/"free" maps, from the Light picture and the authored regions."""
    foliage, sky, free = classify(light)
    horizon = scene["horizon"]
    above = np.zeros((h, w), bool)
    above[: int(horizon * h)] = True

    # Authored things that never move, plus the hero's foreground cut-out (it is a static picture in front
    # of the phone, so the canvas under it must stay still too).
    fixed = np.zeros((h, w), bool)
    for box in scene.get("exclude", []):
        x0, y0, x1, y1 = px_box(box, w, h)
        fixed[y0:y1, x0:x1] = True
    if slot.get("foreground"):
        x0, y0, x1, y1 = px_box(slot["foreground"], w, h)
        fixed[y0:y1, x0:x1] = True

    trees = scene.get("trees", [])
    in_tree = np.zeros((h, w), bool)
    tree_w = np.zeros((h, w), np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for t in trees:
        m = poly_mask(t["poly"], w, h)
        in_tree |= m
        soft = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 14)
        if "anchor" in t:
            ax, ay = t["anchor"][0] * w, t["anchor"][1] * h
            pts = np.array(t["poly"]) * [w, h]
            reach = 0.75 * np.max(np.hypot(pts[:, 0] - ax, pts[:, 1] - ay))
            soft = soft * np.clip(np.hypot(xx - ax, yy - ay) / reach, 0, 1)
        tree_w = np.maximum(tree_w, soft * t.get("amp", 1))

    # Around the trees, whatever is neither foliage nor sky is solid: trunks, characters, lamp posts,
    # buildings. Opening drops the leaves' ink lines and thin twigs.
    near_tree = dilate(in_tree, 40)
    solid = near_tree & ~foliage & ~(free & above)
    solid = big_parts(opened(solid, 5), 260)

    near_leaf = cv2.GaussianBlur(dilate(foliage & near_tree, 9).astype(np.float32), (0, 0), 6)
    weight = tree_w * near_leaf

    beds = np.zeros((h, w), np.float32)
    green = (light[..., 1] > light[..., 0] + 8) & (light[..., 1] > light[..., 2] + 25)
    near_green = cv2.GaussianBlur(dilate(green, 8).astype(np.float32), (0, 0), 5)
    for b in scene.get("beds", []):
        m = np.zeros((h, w), np.float32)
        x0, y0, x1, y1 = px_box(b["box"], w, h)
        m[y0:y1, x0:x1] = 1
        beds = np.maximum(beds, cv2.GaussianBlur(m, (0, 0), 12) * b.get("amp", 0.3))
    weight = np.maximum(weight, beds * near_green)

    # Fall to zero towards anything that must not move.
    still = solid | fixed
    gate = np.clip((cv2.distanceTransform((~still).astype(np.uint8), cv2.DIST_L2, 5) - GATE_MARGIN) / GATE_FALLOFF, 0, 1)
    weight = np.minimum(cv2.GaussianBlur(weight, (0, 0), 3), gate)
    weight[weight < 0.02] = 0

    water = np.zeros((h, w), np.float32)
    if "water" in scene:
        r, g, b = light[..., 0], light[..., 1], light[..., 2]
        blue = (b > r + 20) & (b > g - 5)
        # The pond is told by its colour, so a hand, a phone, reeds or stones in front of it stay out.
        m = opened(poly_mask(scene["water"], w, h) & blue, 3)
        still_w = dilate(m, 12) & ~m
        water = np.clip((cv2.distanceTransform((~still_w).astype(np.uint8), cv2.DIST_L2, 5) - 3) / 24, 0, 1) * m

    return {"near_tree": near_tree, "foliage": foliage, "sky": sky, "free": free, "above": above, "solid": solid, "fixed": fixed, "weight": weight, "water": water}


# ----------------------------------------------------------------------------------------- cut-outs


class Atlas:
    def __init__(self):
        self.items = []

    def add(self, rgb, alpha, scale=1.0):
        """Queue a sprite (float RGB 0..255, alpha 0..1); returns its index."""
        if scale != 1.0:
            size = (max(1, round(rgb.shape[1] * scale)), max(1, round(rgb.shape[0] * scale)))
            rgb = cv2.resize(bleed(rgb, alpha), size, interpolation=cv2.INTER_AREA)
            alpha = cv2.resize(alpha, size, interpolation=cv2.INTER_AREA)
        self.items.append((bleed(rgb, alpha), alpha))
        return len(self.items) - 1

    def pack(self, max_w=1024, pad=8):
        order = sorted(range(len(self.items)), key=lambda i: -self.items[i][1].shape[0])
        rects = [None] * len(self.items)
        x = y = row = 0
        for i in order:
            hh, ww = self.items[i][1].shape
            if x + ww + pad > max_w and x > 0:
                x, y, row = 0, y + row + pad, 0
            rects[i] = [x, y, ww, hh]
            x += ww + pad
            row = max(row, hh)
        width = max((r[0] + r[2] for r in rects), default=1)
        height = max((r[1] + r[3] for r in rects), default=1)
        out = np.zeros((height, width, 4), np.uint8)
        for (rgb, alpha), (rx, ry, rw, rh) in zip(self.items, rects):
            out[ry : ry + rh, rx : rx + rw, :3] = rgb.clip(0, 255).round()
            out[ry : ry + rh, rx : rx + rw, 3] = (alpha * 255).clip(0, 255).round()
        return out, rects


def matte(img, model, sigma, box, soft=35.0):
    """Alpha of whatever stands out from the sky in `box`, and its colour with the sky taken back out."""
    x0, y0, x1, y1 = box
    sky = model(box)
    sub = img[y0:y1, x0:x1]
    dist = np.linalg.norm(sub - sky, axis=-1)
    t0 = max(8.0, 3.5 * sigma)
    alpha = np.clip((dist - t0) / soft, 0, 1)
    # Never less than what the colour needs: with the sky taken back out it must stay within 0..255.
    need = np.max(np.where(sub > sky, (sub - sky) / np.maximum(255 - sky, 1), (sky - sub) / np.maximum(sky, 1)), axis=-1)
    alpha = np.where(alpha > 0, np.maximum(alpha, np.clip(need, 0, 1)), 0)
    return alpha, sky


def unmix(sub, sky, alpha):
    a = alpha[..., None]
    return np.where(a > 0.04, (sub - (1 - a) * sky) / np.maximum(a, 0.04), sub).clip(0, 255)


def trim(alpha, pad=3):
    ys, xs = np.nonzero(alpha > 0.01)
    if len(xs) == 0:
        return None
    return max(0, xs.min() - pad), max(0, ys.min() - pad), min(alpha.shape[1], xs.max() + 1 + pad), min(alpha.shape[0], ys.max() + 1 + pad)


def ribbon_paths(tail, attach, count=2, points=14):
    """Centre lines of the kite's ribbons: from where they join the kite, the paths through the tail's
    pixels (kept to the middle of each ribbon) to its far ends."""
    ys, xs = np.nonzero(tail)
    index = -np.ones(tail.shape, np.int64)
    index[ys, xs] = np.arange(len(xs))
    depth = cv2.distanceTransform(tail.astype(np.uint8), cv2.DIST_L2, 5)
    rows, cols, costs, steps = [], [], [], []
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        y2, x2 = ys + dy, xs + dx
        ok = (y2 < tail.shape[0]) & (x2 >= 0) & (x2 < tail.shape[1])
        ok[ok] &= tail[y2[ok], x2[ok]]
        a, b = index[ys[ok], xs[ok]], index[y2[ok], x2[ok]]
        step = np.hypot(dy, dx)
        mid = (depth[ys[ok], xs[ok]] + depth[y2[ok], x2[ok]]) / 2
        rows += [a, b]
        cols += [b, a]
        costs += [step / (mid**2 + 0.2)] * 2
        steps += [np.full(len(a), step)] * 2
    n = len(xs)
    by_cost = coo_matrix((np.concatenate(costs), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsr()
    by_len = coo_matrix((np.concatenate(steps), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsr()
    start = int(np.argmin(np.hypot(xs - attach[0], ys - attach[1])))
    _, pred = dijkstra(by_cost, indices=start, return_predecessors=True)
    sources = [start]
    out = []
    for _ in range(count):
        far = dijkstra(by_len, indices=sources, min_only=True)
        far[~np.isfinite(far)] = -1
        end = int(np.argmax(far))
        path = [end]
        while path[-1] != start and pred[path[-1]] >= 0:
            path.append(int(pred[path[-1]]))
        path = path[::-1]
        sources = sorted(set(sources) | set(path))
        pts = np.stack([xs[path], ys[path]], 1).astype(np.float64)
        pts = ndimage.uniform_filter1d(pts, 9, axis=0, mode="nearest")
        pts[0] = attach
        seg = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
        at = np.linspace(0, seg[-1], points)
        line = np.stack([np.interp(at, seg, pts[:, 0]), np.interp(at, seg, pts[:, 1])], 1)
        wide = 2 * depth[np.clip(line[:, 1].round().astype(int), 0, tail.shape[0] - 1), np.clip(line[:, 0].round().astype(int), 0, tail.shape[1] - 1)]
        wide = ndimage.uniform_filter1d(np.maximum(wide, 3), 3, mode="nearest")
        out.append((line, wide))
    return out


def cut_theme(scene, st, img, theme, w, h):
    """Everything painted into one theme's picture that moves: mattes, the clean plate, the removal mask."""
    free = erode(st["free"], 1)  # not the blended pixels along a leaf's edge: they stay with the tree
    if theme == "dark":
        # The same drawing, but leaf edges differ by a pixel or two, and a stray leaf must not end up in a
        # cloud: around the trees, also drop what is leaf-coloured at dusk (golden, or dark green).
        r, g, b = img[..., 0], img[..., 1], img[..., 2]
        leafy = (g > b * 1.6 + 10) | ((np.maximum(np.maximum(r, g), b) < 75) & (g >= b - 4))
        # Nor anything dark and warm (a lamp's cap, a branch): the dusk sky and its clouds are never both.
        warm = (r > b + 10) & (np.maximum(np.maximum(r, g), b) < 140)
        free = erode(free, 1) & ~dilate((leafy & st["near_tree"]) | warm, 3)
    hidden = st["above"] & ~free  # what stands in front of the sky layer
    cand = erode(st["sky"], 5) & st["above"]
    atlas = Atlas()
    removal = np.zeros((h, w), bool)
    plate = img.copy()
    plate_on = np.zeros((h, w), bool)
    data = {"clouds": [], "birds": [], "butterflies": []}
    check = img.copy()  # plate + sprites at rest, to compare with the picture

    def paint_out(box, sky, gone):
        x0, y0, x1, y1 = box
        removal[y0:y1, x0:x1] |= gone
        near = dilate(gone, 30)
        plate[y0:y1, x0:x1][near] = sky[near]
        plate_on[y0:y1, x0:x1] |= near
        check[y0:y1, x0:x1][gone] = sky[gone]

    def put_back(box, rgb, alpha):
        x0, y0, x1, y1 = box
        a = alpha[..., None]
        check[y0:y1, x0:x1] = check[y0:y1, x0:x1] * (1 - a) + rgb * a

    # Other elements inside a cloud's box must not end up in the cloud.
    taken = np.zeros((h, w), bool)
    for box in scene.get("birds", []) + ([scene["kite"]["box"]] if "kite" in scene else []):
        x0, y0, x1, y1 = px_box(box, w, h)
        taken[y0:y1, x0:x1] = True

    # -- the kite and its tail
    if "kite" in scene:
        box = px_box(scene["kite"]["box"], w, h)
        x0, y0, x1, y1 = box
        model, sigma = fit_sky(img, cand & ~taken, box, w, h, scene["horizon"])
        alpha, sky = matte(img, model, sigma, box)
        sub = img[y0:y1, x0:x1]
        red = (sub[..., 0] > sub[..., 1] + 45) & (sub[..., 0] > sub[..., 2] + 25)
        alpha = alpha * big_parts(dilate(red, 8) & (alpha > 0.05), 400)
        rgb = unmix(sub, sky, alpha)
        body = dilate(opened(alpha > 0.5, 11), 5)
        tail = (alpha > 0.35) & ~body
        tail = big_parts(tail, 200)
        ring = dilate(body, 4) & tail
        ys, xs = np.nonzero(ring)
        attach = np.array([xs.mean(), ys.mean()])
        ribbons = ribbon_paths(tail | ring, attach)
        body_a = alpha * body
        tail_a = alpha * ~body
        paint_out(box, sky, dilate(alpha > 0.02, 5))
        put_back(box, rgb, alpha)
        solid_tail = tail & (cv2.distanceTransform(tail.astype(np.uint8), cv2.DIST_L2, 3) > 2.5)
        rim = tail & ~solid_tail
        fill = np.median(rgb[solid_tail], axis=0)
        if theme == "light":  # a dark red ink line by day, a lit orange rim at dusk
            edge = [int(v) for v in fill * 0.68]
        else:
            lum_t = rgb[tail] @ np.array([0.299, 0.587, 0.114])
            edge = [int(v) for v in np.median(rgb[tail][lum_t >= np.percentile(lum_t, 85)], axis=0)]
        kite = {
            "attach": [round(float(attach[0] + x0), 1), round(float(attach[1] + y0), 1)],
            "fill": [int(v) for v in fill],
            "edge": edge,
            "ribbons": [
                {"p": [[round(float(px + x0), 1), round(float(py + y0), 1)] for px, py in line], "w": [round(float(v), 1) for v in wide]}
                for line, wide in ribbons
            ],
        }
        for name, a in (("body", body_a), ("tail", tail_a)):
            tx0, ty0, tx1, ty1 = trim(a)
            kite[name] = {"r": [x0 + tx0, y0 + ty0, tx1 - tx0, ty1 - ty0], "i": atlas.add(rgb[ty0:ty1, tx0:tx1], a[ty0:ty1, tx0:tx1])}
        data["kite"] = kite

    # -- the two painted birds
    for bbox in scene.get("birds", []):
        box = px_box(bbox, w, h)
        x0, y0, x1, y1 = box
        model, sigma = fit_sky(img, cand, box, w, h, scene["horizon"])
        alpha, sky = matte(img, model, sigma, box, soft=30.0)
        alpha = alpha * dilate(big_parts(alpha > 0.3, 60), 3)
        rgb = unmix(img[y0:y1, x0:x1], sky, alpha)
        paint_out(box, sky, dilate(alpha > 0.02, 4))
        put_back(box, rgb, alpha)
        n, labels = cv2.connectedComponents(dilate(alpha > 0.3, 2).astype(np.uint8))
        found = []
        for k in range(1, n):
            a = alpha * (labels == k)
            t = trim(a)
            if t is None:
                continue
            tx0, ty0, tx1, ty1 = t
            ys, xs = np.nonzero(a[ty0:ty1, tx0:tx1] > 0.5)
            found.append(
                {
                    "r": [x0 + tx0, y0 + ty0, tx1 - tx0, ty1 - ty0],
                    "i": atlas.add(rgb[ty0:ty1, tx0:tx1], a[ty0:ty1, tx0:tx1]),
                    "ink": [int(v) for v in np.median(rgb[ty0:ty1, tx0:tx1][ys, xs], axis=0)],
                }
            )
        data["birds"] += sorted(found, key=lambda b: b["r"][0])

    # -- clouds
    for cbox in scene.get("clouds", []):
        box = px_box(cbox, w, h)
        x0, y0, x1, y1 = box
        model, sigma = fit_sky(img, cand & ~taken, box, w, h, scene["horizon"])
        alpha, sky = matte(img, model, sigma, box)
        sub = img[y0:y1, x0:x1]
        open_sky = free[y0:y1, x0:x1] & ~dilate(taken[y0:y1, x0:x1], 6) & ~removal[y0:y1, x0:x1]
        alpha = alpha * open_sky
        alpha = alpha * dilate(big_parts(alpha > 0.25, 500), 6)
        if not (alpha > 0.5).any():
            print(f"    no cloud in {cbox}")
            continue
        rgb = unmix(sub, sky, alpha)
        paint_out(box, sky, dilate(alpha > 0.02, 5) & open_sky)
        put_back(box, rgb, alpha)
        # Carry the cloud on a little behind the trees in front of it, so drifting never opens a gap: the
        # nearest cloud colour, thinning out over 60 px. If the drift brings that part into the open, it
        # reads as a soft edge of the same cloud.
        behind = hidden[y0:y1, x0:x1]
        solid = alpha > 0.5
        reach, near = ndimage.distance_transform_edt(~solid, return_indices=True)
        grow = behind & (reach < 60)
        if grow.any():
            # Colour from well inside the cloud, where nothing of the tree's edge is mixed in.
            core = erode(alpha > 0.9, 5)
            if core.any():
                near = ndimage.distance_transform_edt(~core, return_distances=False, return_indices=True)
            carried = cv2.GaussianBlur(rgb[near[0], near[1]], (0, 0), 5)
            alpha = np.where(grow, np.clip(1 - reach / 60, 0, 1) ** 1.5, alpha).astype(np.float32)
            rgb = np.where(grow[..., None], carried, rgb).astype(np.float32)
        tx0, ty0, tx1, ty1 = trim(alpha)
        pin = -1 if x0 + tx0 <= 4 else 1 if x0 + tx1 >= w - 4 else 0  # cut by the picture's edge: only drift towards it
        data["clouds"].append({"r": [x0 + tx0, y0 + ty0, tx1 - tx0, ty1 - ty0], "i": atlas.add(rgb[ty0:ty1, tx0:tx1], alpha[ty0:ty1, tx0:tx1], CLOUD_SCALE), "pin": pin})

    # -- butterflies (on grass: GrabCut finds them, inpainting fills the grass behind)
    for b in scene.get("butterflies", []):
        inner = px_box(b["box"], w, h)
        box = px_box(b["box"], w, h, pad=40)
        x0, y0, x1, y1 = box
        sub = img[y0:y1, x0:x1].astype(np.uint8)
        gc = np.zeros(sub.shape[:2], np.uint8)
        rect = (inner[0] - x0, inner[1] - y0, inner[2] - inner[0], inner[3] - inner[1])
        cv2.grabCut(cv2.cvtColor(sub, cv2.COLOR_RGB2BGR), gc, rect, np.zeros((1, 65)), np.zeros((1, 65)), 8, cv2.GC_INIT_WITH_RECT)
        m = (gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD)
        m = ndimage.binary_fill_holes(big_parts(opened(m, 1), 300))
        alpha = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 0.8)
        gone = dilate(m, 4)
        fill = cv2.inpaint(sub, gone.astype(np.uint8), 7, cv2.INPAINT_TELEA).astype(np.float32)
        paint_out(box, fill, gone)
        put_back(box, sub.astype(np.float32), alpha)
        tx0, ty0, tx1, ty1 = trim(alpha, pad=2)
        bw, bh = inner[2] - inner[0], inner[3] - inner[1]
        data["butterflies"].append(
            {
                "r": [x0 + tx0, y0 + ty0, tx1 - tx0, ty1 - ty0],
                "i": atlas.add(sub[ty0:ty1, tx0:tx1].astype(np.float32), alpha[ty0:ty1, tx0:tx1]),
                "axis": [round(inner[0] + b["axis"][0] * bw, 1), round(inner[1] + b["axis"][1] * bh, 1), b["axis"][2]],
                "perches": [[round(px * w), round(py * h)] for px, py in b.get("perches", [])],
            }
        )

    if theme == "dark":
        lum = img @ np.array([0.299, 0.587, 0.114], np.float32)
        # Lamps: snap each authored point to the middle of the light it marks.
        lamps = []
        for lamp in scene.get("lamps", []):
            cx, cy = lamp["at"][0] * w, lamp["at"][1] * h
            reach = int(0.012 * w)
            x0, y0, x1, y1 = int(cx - reach), int(cy - reach), int(cx + reach), int(cy + reach)
            wgt = (lum[y0:y1, x0:x1] / 255.0) ** 6
            gy, gx = np.mgrid[y0:y1, x0:x1]
            entry = {"at": [round(float((gx * wgt).sum() / wgt.sum()), 1), round(float((gy * wgt).sum() / wgt.sum()), 1)], "r": round(lamp["r"] * w)}
            if "pool" in lamp:
                px, py, rx, ry = lamp["pool"]
                entry["pool"] = [round(px * w), round(py * h), round(rx * w), round(ry * w)]
            lamps.append(entry)
        data["lamps"] = lamps
        # Stars: small bright specks in the open sky.
        bright = (lum - cv2.medianBlur(lum.astype(np.uint8), 31) > 45) & free & ~dilate(removal, 20)
        bright[int(0.24 * h) :] = False  # lower down the specks are windows in the skyline
        n, labels, stats, cents = cv2.connectedComponentsWithStats(bright.astype(np.uint8), connectivity=8)
        stars = []
        for k in range(1, n):
            area, bw, bh = stats[k, cv2.CC_STAT_AREA], stats[k, cv2.CC_STAT_WIDTH], stats[k, cv2.CC_STAT_HEIGHT]
            if not (8 <= area <= 500 and max(bw, bh) <= 2.2 * min(bw, bh) and max(bw, bh) <= 40):
                continue
            # A star stands alone: the plane's lights and the moon's tips have something bright next to them.
            sx, sy = int(cents[k][0]), int(cents[k][1])
            around = bright[max(0, sy - 60) : sy + 60, max(0, sx - 60) : sx + 60] & (labels[max(0, sy - 60) : sy + 60, max(0, sx - 60) : sx + 60] != k)
            if not around.any():
                stars.append((float(lum[labels == k].max()), [round(float(cents[k][0]), 1), round(float(cents[k][1]), 1), int(max(bw, bh))]))
        data["stars"] = [s for _, s in sorted(stars, reverse=True)[:10]]
        data["fireflies"] = [list(px_box(b, w, h)) for b in scene.get("fireflies", [])]

    err = np.abs(check - img)
    data["_fit"] = (float(err.mean()), float(np.percentile(err, 99.9)), float(err.max()))
    return data, atlas, removal, plate, plate_on, hidden


# ----------------------------------------------------------------------------------------- output


def save_webp(arr, path, **kw):
    Image.fromarray(arr).save(path, **kw)
    return path.stat().st_size


def overlay(light, st, removal, scene, w, h, path):
    out = light.copy()

    def tint(mask, colour, amount):
        a = (mask * amount)[..., None]
        out[:] = out * (1 - a) + np.array(colour, np.float32) * a

    tint(st["weight"], (255, 0, 0), 0.75)
    tint(st["water"], (0, 60, 255), 0.75)
    tint(removal.astype(np.float32), (255, 0, 255), 0.6)
    edge = st["solid"] ^ erode(st["solid"], 2)
    out[edge] = (255, 235, 0)
    edge = st["fixed"] ^ erode(st["fixed"], 3)
    out[edge] = (255, 255, 255)
    small = cv2.resize(out, (1800, round(h * 1800 / w)), interpolation=cv2.INTER_AREA)
    Image.fromarray(small.clip(0, 255).astype(np.uint8)).save(path, quality=84)


def build(name):
    scene = CFG["scenes"][name]
    slot = SCREENS["slots"][name]
    light = load(slot["light"])
    h, w = light.shape[:2]
    st = structure(scene, slot, light, w, h)
    still = st["solid"] | st["fixed"]
    print(f"{name}: {w}x{h}  sway on {100 * (st['weight'] > 0).mean():.1f}% of the picture, max weight on still pixels {st['weight'][still].max() if still.any() else 0:.3f}")
    entry = {
        "size": [w, h],
        "mobile": slot.get("mobile"),
        "maxShift": MAX_SHIFT,
        "lanes": scene.get("lanes", []),
        "lanesMobile": scene.get("lanesMobile", scene.get("lanes", [])),
        "birdExit": scene.get("birdExit", [1, -0.2]),
        "water": "water" in scene,
    }
    msize = (round(w * MASK_SCALE), round(h * MASK_SCALE))
    psize = (round(w * PLATE_SCALE), round(h * PLATE_SCALE))
    for theme in ("light", "dark"):
        img = light if theme == "light" else load(slot["dark"])
        data, atlas, removal, plate, plate_on, hidden = cut_theme(scene, st, img, theme, w, h)
        fit = data.pop("_fit")

        blue = np.full((h, w), 128, np.float32)
        blue[hidden] = 0
        blue[removal] = 255
        mask = np.stack([np.round(st["weight"] * 31) * (255 / 31), st["water"] * 255, blue], -1)
        mask = cv2.resize(mask, msize, interpolation=cv2.INTER_AREA).round().astype(np.uint8)
        mask[..., 0] = (np.round(mask[..., 0] / 255 * 31) * (255 / 31)).astype(np.uint8)  # 32 levels compress far better
        mask[..., 1] = (np.round(mask[..., 1] / 255 * 15) * 17).astype(np.uint8)
        size_m = save_webp(mask, OUT / f"{name}-{theme}-mask.webp", lossless=True, quality=100, method=6)

        flat = np.where(dilate(plate_on, 8)[..., None], plate, 128.0)
        flat = cv2.resize(flat, psize, interpolation=cv2.INTER_AREA).round().astype(np.uint8)
        size_p = save_webp(flat, OUT / f"{name}-{theme}-plate.webp", quality=90, method=6)

        sheet, rects = atlas.pack()
        size_a = save_webp(sheet, OUT / f"{name}-{theme}-atlas.webp", quality=88, alpha_quality=92, method=6, exact=True)

        def place(item):
            item["a"] = rects[item.pop("i")]
            return item

        for key in ("clouds", "birds", "butterflies"):
            data[key] = [place(i) for i in data[key]]
        if "kite" in data:
            place(data["kite"]["body"])
            place(data["kite"]["tail"])
        data.update(mask=f"/marketing/motion/{name}-{theme}-mask.webp", plate=f"/marketing/motion/{name}-{theme}-plate.webp", atlas=f"/marketing/motion/{name}-{theme}-atlas.webp", atlasSize=[sheet.shape[1], sheet.shape[0]])
        entry[theme] = data
        print(
            f"  {theme}: mask {size_m / 1024:.0f} KB, plate {size_p / 1024:.0f} KB, atlas {size_a / 1024:.0f} KB ({sheet.shape[1]}x{sheet.shape[0]}) = {(size_m + size_p + size_a) / 1024:.0f} KB;"
            f" {len(data['clouds'])} clouds, {len(data['birds'])} birds; rest frame vs picture: mean {fit[0]:.3f}, p99.9 {fit[1]:.1f}, max {fit[2]:.0f} (of 255)"
        )

        # Review pictures.
        if theme == "light":
            overlay(light, st, removal, scene, w, h, REVIEW / f"{name}-masks.jpg")
        clean = np.where(removal[..., None], plate, img)
        Image.fromarray(cv2.resize(clean, (1800, round(h * 1800 / w)), interpolation=cv2.INTER_AREA).clip(0, 255).astype(np.uint8)).save(REVIEW / f"{name}-{theme}-plate.jpg", quality=84)
        a = sheet[..., 3:4] / 255.0
        yy, xx = np.mgrid[0 : sheet.shape[0], 0 : sheet.shape[1]]
        board = np.where(((yy // 16 + xx // 16) % 2 == 0)[..., None], 150, 110).astype(np.float32)
        Image.fromarray((sheet[..., :3] * a + board * (1 - a)).astype(np.uint8)).save(REVIEW / f"{name}-{theme}-atlas.jpg", quality=88)
    return entry


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(CFG["scenes"])
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / CFG["manifest"]
    manifest = {}
    if manifest_path.exists():  # a partial run keeps the other scenes' entries
        text = manifest_path.read_text(encoding="utf8")
        manifest = json.loads(text[text.index("{") : text.rindex("}") + 1])
    for name in names:
        manifest[name] = build(name)
    body = json.dumps({k: manifest[k] for k in sorted(manifest)}, separators=(",", ":"), default=lambda v: v.item())
    text = (
        "// Written by scripts/web-motion.py from art/web/motion.json. Don't edit by hand.\n"
        "// Positions are in pixels of the scene's source picture (size), x right and y down.\n"
        f"export const motion = {body} as const;\n"
    )
    manifest_path.write_bytes(text.encode("utf8"))


if __name__ == "__main__":
    main()
