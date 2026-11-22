#!/usr/bin/env python3
"""Motion data for the site's illustrated scenes (web/components/marketing/scene-motion.tsx).

The scenes stay the pictures web-compose.py exports. This script makes what the Three.js layer needs to
bring them to life, per scene and per theme (Light and Dusk), from the regions authored in
art/web/motion.json:

  {scene}-{theme}-mask.webp    half-size, lossless. R: how much of its piece's sway a pixel takes (1 inside
                               a crown or a flower, falling to 0 towards anything that must not move).
                               G: water. B: 0 where a tree or anything solid hides the sky layer (clouds
                               and birds pass behind it), 128 elsewhere, 255 where a painted element was
                               cut out and the clean plate shows instead. Alpha: 255 in front, 128 on the
                               still layers behind what sways, which never move: the skyline and the sky
                               behind the trees, and a rock or wall behind the flowers drawn across it.
  {scene}-seg.webp             half-size, lossless, the same for both themes. Which swaying piece a pixel
                               belongs to: R the piece, G its neighbour (0: none), B's high four bits how
                               much of the neighbour's movement it takes (0..15 = 0..1/2), B's low four
                               bits the leaf flutter (crown edges only). Alpha: 128 on the characters and
                               authored objects with their ink outline, which the page holds still outright
                               (a held pixel shows itself, and nothing is drawn from one), 255 elsewhere.
                               The pieces themselves (a tree, a clump of the tree line, a flower: pivot,
                               angle, stem, pace) go in the manifest.
  {scene}-{theme}-plate.webp   the clean plate: the sky (a smooth model fitted around each cut-out, as
                               web-hero-erase-kite.py does) or inpainted grass behind what was cut out,
                               and the skyline carried on under the leaves in front of it as far as they
                               can sway (what a leaf uncovers), likewise the rock or wall under the flowers
                               drawn across it. Grey everywhere else, so it stays small.
  {scene}-{theme}-atlas.webp   the cut-outs with alpha: clouds (made whole where a tree or the picture's
                               edge cut them), the two painted birds, the kite and its tail, the balloon,
                               the butterflies.

plus web/components/marketing/motion-manifest.ts, and review pictures in art/web/review/motion/:
{scene}-masks.jpg (the masks tinted over the art, with the characters and the skyline hatched),
{scene}-{theme}-plate.jpg (the art with everything cut out and the skyline carried on under the tree
edges) and {scene}-{theme}-atlas.jpg.

Structure (what sways, what is solid) is read from the Light picture and used for both themes: the two
are the same drawing, aligned to the pixel. Cut-outs are made per theme.

Two things never move. Characters and authored objects (the `exclude` boxes): inside a box whatever is
not plant-coloured is the character, except the flower heads of a bed that reaches into the box, which
are small islands of flower colour standing clear of the character; a piece's hold falls to zero towards
the character over more than the distance it can move. And the skyline with the sky behind the trees:
found by colour above the horizon (a roof garden counts as skyline, not as a tree), marked in the mask's
alpha and never warped; a crown's edge sways across it. A rock, a wall or a bench seat with flowers drawn
across it (the `behind` polygons) is such a still layer too, behind those flowers, so they sway in front
of it; the gate then only holds towards the character itself. The skyline behind a character inside its
box is skyline as well (it is joined to the open sky; the character is closed in by its ink outline), so
a crown behind a character sways. The characters and authored objects are also marked in the seg
picture's alpha, and the page never moves such a pixel nor draws from one, whatever the weights say; an
object in front of plants (the `front` polygons: the bench's seat) is held that way alone, with no gate,
so the bed behind it sways right up to its edge.

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
# The sway weight is zero within this many source pixels of anything that must not move, and rises over
# four times the distance the pixel can move, so a character's or a building's edge never moves.
GATE_MARGIN = 3
# How far (source pixels) a tree's edge can sway across the skyline behind it: the clean plate carries the
# skyline on this far under the leaves, for the sliver a leaf uncovers.
BACK_REACH = 32
# Skyline showing for this many source pixels up a column ends the tree line there (a gap between leaves is smaller).
SKY_GAP = 22
# How far (source pixels) the plate carries a rock or a wall on under the flowers drawn across it.
OBJECT_REACH = 20


# ----------------------------------------------------------------------------------------- helpers


def load(path):
    return np.asarray(Image.open(ROOT / path).convert("RGB")).astype(np.float32)


def ellipse(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def dilate(mask, r):
    if r >= 8:  # a wide disc is far quicker as a distance
        return cv2.distanceTransform((~mask.astype(bool)).astype(np.uint8), cv2.DIST_L2, 5) <= r
    return cv2.dilate(mask.astype(np.uint8), ellipse(r)).astype(bool)


def erode(mask, r):
    if r >= 8:
        return cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5) > r
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


def plant_colours(light):
    """Leaf green, lavender, and the colours of flower heads (red, yellow and orange; white; pink)."""
    r, g, b = light[..., 0], light[..., 1], light[..., 2]
    green = (g > r + 8) & (g > b + 25)
    purple = (b > g + 25) & (r > g + 5) & (b > 110)
    red = (r > 165) & (g < 115) & (b < 120)
    yellow = (r > 195) & (g > 135) & (b < 120) & (r > g + 6)  # not sunlit lawn, which is greener than it is red
    white = np.minimum(np.minimum(r, g), b) > 218
    pink = (r > 190) & (b > 120) & (g < r - 45) & (g < b + 30)
    orange = (r > 200) & (g > 90) & (g < 170) & (b < 110)
    return green, purple, red | yellow | orange, white, pink


class Segments:
    """The things that sway, each a piece with its own pivot: a tree, a clump of the tree line, a flower.
    `label` says which piece a pixel belongs to (0: none)."""

    def __init__(self, w, h):
        self.label = np.zeros((h, w), np.uint16)
        self.items = []

    def add(self, region, pivot, sway, reach, freq, bend=0.0, flutter=0.0, blur=8.0, kind="tree", at=None):
        """`sway`: how far (source pixels) the point `reach` away from the pivot moves in a full gust.
        `bend` > 0: a stem of that length that bends from the pivot up, instead of a rigid piece.
        `at`: the window of the picture `region` is given in (default: the whole picture)."""
        if not region.any():
            return
        self.items.append({"pivot": pivot, "amp": sway / max(reach, 1.0), "reach": reach, "freq": freq, "bend": bend, "flutter": flutter, "blur": blur, "kind": kind})
        (self.label if at is None else self.label[at])[region] = len(self.items)


def structure(scene, slot, light, w, h):
    """What sways and how, the water and the solid/"free" maps, from the Light picture and the authored
    regions. The maps for the page are made at half size (hw x hh)."""
    foliage, sky, free = classify(light)
    green, purple, heads, white, pink = plant_colours(light)
    horizon = scene["horizon"]
    above = np.zeros((h, w), bool)
    above[: int(horizon * h)] = True
    hw, hh = round(w * MASK_SCALE), round(h * MASK_SCALE)

    # Authored boxes around characters and objects that never move. Inside a box, whatever is not
    # plant-coloured is first taken as still (so the trees and the grass between two people can move;
    # thin ink lines inside foliage don't count)...
    plantish = foliage | green | purple
    boxes = np.zeros((h, w), bool)
    for box in scene.get("exclude", []):
        x0, y0, x1, y1 = px_box(box, w, h)
        boxes[y0:y1, x0:x1] = True
    # The skyline and the pale sky behind a character are not the character: whatever is pale or
    # sky-coloured above the horizon and joined to the open blue sky higher up, without crossing an ink
    # outline, is skyline. (A cream sleeve or a white shirt is closed in by its outline.) So a tree's
    # crown behind a character is held only by the character itself.
    hsv = cv2.cvtColor(light.astype(np.uint8), cv2.COLOR_RGB2HSV)
    hue, sat, val = hsv[..., 0].astype(np.int32) * 2, hsv[..., 1], hsv[..., 2]
    trunk = (hue >= 8) & (hue <= 40) & (sat >= 70) & (val >= 45) & (val <= 205)
    pale = (val > 150) & (sat < 90)
    airy = (pale | free) & above & ~foliage & ~trunk
    n, lab = cv2.connectedComponents(opened(airy, 3).astype(np.uint8), connectivity=4)
    top = np.zeros((h, w), bool)
    top[: int(0.6 * horizon * h)] = True
    joined = np.bincount(lab[top & sky], minlength=n) >= 400
    joined[0] = False
    open_air = dilate(joined[lab], 3) & airy
    for box in scene.get("whole", []):  # a lamp's pale globe has no ink round it: its box stays whole
        x0, y0, x1, y1 = px_box(box, w, h)
        open_air[y0:y1, x0:x1] = False
    inked = boxes & ~plantish & ~(sky & above) & ~open_air
    fixed = big_parts(opened(inked, 4), 500)
    # ...then the flower heads of a bed that reaches into a box are told from the character: a head is a
    # small island of flower colour that stands clear of everything else that is still (the character's
    # body, a bench, a rock, the paving). Anything joined to the character stays with the character: a
    # sock, a shoe, a red lace, and also a flower drawn right across a leg.
    beds_at = np.zeros((h, w), bool)
    for b in scene.get("beds", []):
        x0, y0, x1, y1 = px_box(b["box"], w, h)
        beds_at[y0:y1, x0:x1] = True
    insect = np.zeros((h, w), bool)  # a butterfly on a flower is cut out, not swayed
    for b in scene.get("butterflies", []):
        x0, y0, x1, y1 = px_box(b["box"], w, h, pad=6)
        insect[y0:y1, x0:x1] = True
    flowery = heads | white | pink
    head_max = scene.get("headMax", 0.0005) * w * w  # the largest head, as a share of the picture's width squared
    n, lab, stats, _ = cv2.connectedComponentsWithStats(fixed.astype(np.uint8), connectivity=8)
    area = stats[:, cv2.CC_STAT_AREA].astype(np.float64)
    share = lambda m: np.bincount(lab[m], minlength=n) / np.maximum(area, 1)
    maybe = (area <= head_max) & (share(flowery & fixed) >= 0.4) & (share(beds_at & fixed) >= 0.6) & (share(insect & fixed) < 0.2)
    maybe[0] = False
    body = fixed & ~maybe[lab]
    touching = np.zeros(n, bool)
    touching[np.unique(lab[dilate(body, 5) & fixed])] = True
    bloom_in_box = (maybe & ~touching)[lab]
    fixed = fixed & ~bloom_in_box
    # Things one can see through (a bicycle's basket, its spokes) are still whole, the green in them too:
    # the authored `held` polygons.
    for poly in scene.get("held", []):
        fixed |= poly_mask(poly, w, h)
    # The character's thin parts (fingers, a strap, a lace, the ink outline) are too thin to be found
    # above; they belong to it as far as they are joined to it.
    near = inked & dilate(fixed, 12) & ~dilate(bloom_in_box, 3)
    n, lab = cv2.connectedComponents(near.astype(np.uint8), connectivity=8)
    joined = np.zeros(n, bool)
    joined[np.unique(lab[fixed])] = True
    joined[0] = False
    fixed = fixed | joined[lab]

    # Still objects with flowers drawn across them (a rock, a wall, the bench's seat: the authored
    # `behind` polygons, which keep clear of the character). There the object is a still layer BEHIND the
    # flowers, like the skyline behind the trees: it never moves, but it does not hold the flowers in
    # front of it still either. Inside a polygon the flower heads (small pieces of flower colour, with
    # their ink outline) and everything green are in front; the rest is the object.
    behind = np.zeros((h, w), bool)
    if scene.get("behind"):
        region = np.zeros((h, w), bool)
        bare = np.zeros((h, w), bool)  # {"poly": ..., "heads": false}: nothing on it is a flower
        for entry in scene["behind"]:
            m = poly_mask(entry["poly"] if isinstance(entry, dict) else entry, w, h)
            region |= m
            if isinstance(entry, dict) and not entry.get("heads", True):
                bare |= m
        n, lab, stats, _ = cv2.connectedComponentsWithStats(opened(flowery & ~plantish, 1).astype(np.uint8), connectivity=8)
        small = (stats[:, cv2.CC_STAT_AREA] >= 20) & (stats[:, cv2.CC_STAT_AREA] <= head_max)
        # A head lies on the object; a piece of the object itself that happens to be small and red (the
        # end of a bench slat between two legs) reaches out of the polygon.
        small &= np.bincount(lab[region], minlength=n) >= 0.6 * stats[:, cv2.CC_STAT_AREA]
        small[0] = False
        in_front = dilate(((small[lab] & ~bare) | plantish) & dilate(region, 6), 4)
        behind = big_parts(region & ~plantish & ~in_front, 200)
        fixed = fixed & ~region
    # Still objects IN FRONT of plants (the bench's seat over the bed behind it: the authored `front`
    # polygons). They belong to what never moves and are held like a character (see `hold` below), but
    # they do not slow the plants behind them down: those sway right up to the object's edge and behind it.
    no_gate = np.zeros((h, w), bool)
    for poly in scene.get("front", []):
        no_gate |= poly_mask(poly, w, h)
    # ...and there only the sky's own blue is open sky: a white sleeve or a lamp's globe hides the clouds.
    free = free & ~(boxes & ~sky) & ~dilate(fixed, 2)

    lum = light @ np.array([0.299, 0.587, 0.114], np.float32)
    rough = cv2.GaussianBlur(np.abs(lum - cv2.GaussianBlur(lum, (0, 0), 4)), (0, 0), 10)
    drawn = cv2.morphologyEx((rough > 9).astype(np.uint8), cv2.MORPH_CLOSE, ellipse(14)).astype(bool)

    segs = Segments(w, h)
    trees = scene.get("trees", [])
    in_tree = np.zeros((h, w), bool)
    for t in trees:
        in_tree |= poly_mask(t["poly"], w, h)
    near_tree = dilate(in_tree, 40)

    # The skyline and the sky above the horizon (pale, or sky-coloured), and what stands on the skyline:
    # going up from the ground, the tree line ends where the skyline shows for more than a leaf gap, so a
    # roof garden on a tower (as green as a tree, but with the tower's wall under it) is not a tree.
    skyline = big_parts(opened((pale | free) & above & ~foliage & ~trunk & ~fixed, 2), 600)
    # ...and it is one with the open sky higher up: a pale blossom tree or pale paving among the trees is not.
    n, lab = cv2.connectedComponents(skyline.astype(np.uint8), connectivity=8)
    open_sky = np.zeros(n, bool)
    open_sky[np.unique(lab[: int(0.6 * horizon * h)])] = True
    open_sky[0] = False
    skyline = open_sky[lab]
    gap = cv2.erode(skyline.astype(np.uint8), np.ones((SKY_GAP, 1), np.uint8), anchor=(0, 0)).astype(bool)  # it and the pixels under it
    gap &= np.maximum.accumulate((foliage & above)[::-1], axis=0)[::-1]  # pale paving under the trees is no skyline
    beyond = np.maximum.accumulate(gap[::-1], axis=0)[::-1]  # at or above such a gap
    for t in trees:
        if "pivot" in t:  # a single crown may hang over open sky
            beyond &= ~poly_mask(t["poly"], w, h)

    # -- the tree line: split into clumps, each swaying about its foot
    for t in trees:
        if "pivot" in t:
            continue
        m = poly_mask(t["poly"], w, h)
        # Trees are drawn with leaves and shading; a lawn or a far hill, though just as green, is flat.
        leaf = opened(foliage & drawn & m & ~fixed & ~beyond, 2)
        if not leaf.any():
            continue
        small = cv2.resize(leaf.astype(np.uint8), (hw, hh), interpolation=cv2.INTER_AREA) > 0
        depth = cv2.GaussianBlur(cv2.distanceTransform(small.astype(np.uint8), cv2.DIST_L2, 5), (0, 0), t.get("grain", 0.004) * hw)
        sep = max(3, int(t.get("split", 0.02) * hw))
        peaks = (depth == ndimage.maximum_filter(depth, size=2 * sep + 1)) & (depth > 2.5) & small
        n, plab = cv2.connectedComponents(peaks.astype(np.uint8))
        n -= 1
        if n <= 0:
            continue
        cents = np.array(ndimage.center_of_mass(peaks, plab, range(1, n + 1)))
        seeds = np.zeros((hh, hw), np.int32)
        seeds[cents[:, 0].round().astype(int), cents[:, 1].round().astype(int)] = np.arange(1, n + 1)
        idx = ndimage.distance_transform_edt(seeds == 0, return_distances=False, return_indices=True)
        own = cv2.resize(seeds[idx[0], idx[1]].astype(np.float32), (w, h), interpolation=cv2.INTER_NEAREST).astype(np.int32)
        region_all = dilate(leaf, 6) & dilate(m, 6)
        found = ndimage.find_objects(own * leaf, max_label=n)
        for k in range(1, n + 1):
            sl = found[k - 1]
            if sl is None:
                continue
            mine = (own[sl] == k) & leaf[sl]
            ys, xs = np.nonzero(mine)
            if len(xs) < 300:
                continue
            ys, xs = ys + sl[0].start, xs + sl[1].start
            top, foot = float(np.percentile(ys, 1)), float(np.percentile(ys, 97))
            tall = max(40.0, foot - top)
            low = ys > foot - 0.25 * tall
            pivot = (float(np.median(xs[low])), foot + 0.12 * tall)
            reach = 1.12 * tall
            sway = t.get("sway", float(np.clip(7.0 + 0.05 * tall, 8.0, 20.0)))
            pad = (slice(max(0, sl[0].start - 12), sl[0].stop + 12), slice(max(0, sl[1].start - 12), sl[1].stop + 12))
            segs.add(region_all[pad] & (own[pad] == k), pivot, sway, reach, float(np.clip(0.52 - tall / 1400, 0.27, 0.48)), flutter=float(np.clip(tall / 420, 0.25, 0.8)), blur=5.0, kind="clump", at=pad)

    # -- single trees: the whole crown, with its branches, turns about a point low on the trunk
    for t in trees:
        if "pivot" not in t:
            continue
        m = poly_mask(t["poly"], w, h)
        pivot = (t["pivot"][0] * w, t["pivot"][1] * h)
        ys, xs = np.nonzero(m & foliage)
        reach = float(np.percentile(np.hypot(xs - pivot[0], ys - pivot[1]), 99)) if len(xs) else 1.0
        segs.add(m, pivot, t.get("sway", 15.0), reach, t.get("freq", 0.2), flutter=t.get("flutter", 1.0), blur=t.get("blur", 9.0))

    # -- flower beds, bushes and reeds: every flower is a stem that bends from the soil
    plant_any = np.zeros((h, w), bool)
    for b in scene.get("beds", []):
        x0, y0, x1, y1 = px_box(b["box"], w, h)
        # Work in the bed's own window (the box and a margin), not the whole picture.
        sub = (slice(max(0, y0 - 40), min(h, y1 + 40)), slice(max(0, x0 - 40), min(w, x1 + 40)))
        oy, ox = sub[0].start, sub[1].start
        inbox = np.zeros((sub[0].stop - oy, sub[1].stop - ox), bool)
        inbox[y0 - oy : y1 - oy, x0 - ox : x1 - ox] = True
        # Flower heads count inside the box; their leaves may reach a little out of it, so a bed never
        # ends in a straight line.
        leafy = green[sub] | purple[sub]
        # A head counts whole when any of it is near leaves: a big tulip's middle is far from its leaves,
        # and a head only counted along its rim stays still. (Big red or yellow shapes are not heads.)
        cand = (heads[sub] | pink[sub] | (white[sub] & dilate(green[sub], 22))) & inbox & ~fixed[sub] & ~insect[sub]
        n, lab, stats, _ = cv2.connectedComponentsWithStats(cand.astype(np.uint8), connectivity=8)
        keep = np.zeros(n, bool)
        keep[np.unique(lab[cand & dilate(leafy, 30)])] = True
        keep[0] = False
        keep &= stats[:, cv2.CC_STAT_AREA] <= 60000
        bloom = keep[lab] | (cand & dilate(leafy, 30))
        plant = big_parts((leafy | bloom) & ~fixed[sub], 40)
        if not plant.any():
            continue
        plant_any[sub] |= plant
        cell = b.get("cell", 0.018) * w
        seeds, tops = [], []  # in the window's own pixels; a flower reaches no higher than its head
        n, lab, stats, cents = cv2.connectedComponentsWithStats(opened(bloom & plant, 2 if b.get("head", 30) >= 60 else 1).astype(np.uint8), connectivity=8)
        # The biggest heads first; a small one right next to a taken one sways with it.
        for k in sorted(range(1, n), key=lambda k: -stats[k, cv2.CC_STAT_AREA]):
            if b.get("head", 30) <= stats[k, cv2.CC_STAT_AREA] <= 60000 and all(np.hypot(cents[k][0] - sx, cents[k][1] - sy) > 0.75 * cell for sx, sy in seeds):
                seeds.append((float(cents[k][0]), float(cents[k][1])))
                tops.append(stats[k, cv2.CC_STAT_TOP] - 12)
        # Leaves with no flower above them ('fill': bushes, reeds, a bed inside a rim): a seed every `cell`.
        if b.get("fill"):
            taken = np.ones(inbox.shape, np.uint8)
            for sx, sy in seeds:
                taken[int(sy), int(sx)] = 0
            far = cv2.distanceTransform(taken, cv2.DIST_L2, 5) if seeds else np.full(inbox.shape, 1e6, np.float32)
            rng = np.random.default_rng(int(x0 * 7 + y0 * 13))
            for gy in np.arange(y0 - oy + cell / 2, y1 - oy, cell):
                for gx in np.arange(x0 - ox + cell / 2, x1 - ox, cell):
                    px, py = int(gx + rng.uniform(-0.3, 0.3) * cell), int(gy + rng.uniform(-0.3, 0.3) * cell)
                    if 0 <= px < inbox.shape[1] and 0 <= py < inbox.shape[0] and inbox[py, px] and plant[py, px] and far[py, px] > 0.7 * cell:
                        seeds.append((float(px), float(py)))
                        tops.append(py - 0.6 * cell)
        if not seeds:
            continue
        mark = np.zeros(inbox.shape, np.int32)
        for k, (sx, sy) in enumerate(seeds):
            mark[int(sy), int(sx)] = k + 1
        # A flower owns the plant pixels nearest to it, counting a step down its stem as less than half a
        # step sideways, and no farther than a cell and a bit: the lawn around a bed stays still.
        near, idx = ndimage.distance_transform_edt(mark == 0, sampling=(0.45, 1.0), return_indices=True)
        own = np.where(near < 1.15 * cell, mark[idx[0], idx[1]], 0)
        # A margin round each plant, so a head leaning out of its own outline is not cut off at it.
        own[~(dilate(plant, 10) & ~fixed[sub])] = 0
        rows = np.arange(inbox.shape[0])[:, None]
        own[rows < np.array([1e9] + tops)[own]] = 0
        for k, (sx, sy) in enumerate(seeds):
            sx, sy = sx + ox, sy + oy
            stem = (b["soil"] * h - sy) if "soil" in b else b.get("stem", 0.035) * h
            stem = float(np.clip(stem, 0.012 * h, 0.1 * h))
            sway = float(np.clip(stem * b.get("sway", 0.075), 2.5, b.get("maxSway", 10.0)))
            freq = float(np.clip(0.72 * (90.0 / stem) ** 0.3, 0.5, 1.0))
            segs.add(own == k + 1, (sx, sy + stem), sway, stem, freq, bend=stem, flutter=0.0, blur=5.0, kind="flower", at=sub)

    # Around the trees, whatever is neither foliage, branch nor sky is solid: lamp posts, benches, walls,
    # anything dark or strongly coloured. Opening drops the leaves' ink lines and thin twigs. The pale
    # skyline far behind the tree line is not: a tree's edge has to be able to move across it.
    solid = near_tree & ~foliage & ~trunk & ~(free & above) & ~plant_any & ~(pale & above)
    solid = big_parts(opened(solid, 5), 260)
    still = solid | fixed

    # What lies behind the trees: the skyline and the sky. It never moves; a crown's edge sways across it
    # (the page draws the moved picture only where it lands on something in front, see `back` below).
    # Pale or sky-coloured, above the horizon, within reach of a tree; specks of light inside a crown are
    # not it, and a roof garden or a dark window with skyline all round it is.
    treeish = np.array([False] + [i["kind"] != "flower" for i in segs.items])[segs.label]
    zone = dilate(treeish, BACK_REACH + 8) & above
    back = big_parts(opened((skyline | beyond) & zone & ~dilate(still, 2) & ~plant_any, 2), 600)
    n, lab, stats, _ = cv2.connectedComponentsWithStats((zone & ~back).astype(np.uint8), connectivity=4)
    island = stats[:, cv2.CC_STAT_AREA] <= 0.0004 * w * w
    island[np.unique(lab[dilate(~zone, 1) & zone])] = False  # joined to the trees or the ground beyond
    island[np.unique(lab[dilate(still, 3) & zone])] = False
    island[0] = False
    back = back | island[lab]
    # ------------------------------------------------------------------ half-size maps for the page
    label = cv2.resize(segs.label, (hw, hh), interpolation=cv2.INTER_NEAREST)
    n = len(segs.items)
    if n > 255:
        count = {k: sum(i["kind"] == k for i in segs.items) for k in ("tree", "clump", "flower")}
        raise SystemExit(f"{n} swaying pieces {count}: more than fit in a byte; raise 'split' or 'cell' in motion.json")
    # Soft membership, so neighbours blend into each other instead of tearing: the two strongest per pixel.
    m1 = np.zeros((hh, hw), np.float32)
    m2 = np.zeros((hh, hw), np.float32)
    i1 = np.zeros((hh, hw), np.uint8)
    i2 = np.zeros((hh, hw), np.uint8)
    reachmax = np.zeros((hh, hw), np.float32)  # how far a pixel can be moved, in source pixels
    hy, hx = np.mgrid[0:hh, 0:hw].astype(np.float32)
    for k, sl in enumerate(ndimage.find_objects(label, max_label=n)):
        if sl is None:
            continue
        item = segs.items[k]
        pad = int(3 * item["blur"] / 2) + 2
        sl = (slice(max(0, sl[0].start - pad), min(hh, sl[0].stop + pad)), slice(max(0, sl[1].start - pad), min(hw, sl[1].stop + pad)))
        mem = cv2.GaussianBlur((label[sl] == k + 1).astype(np.float32), (0, 0), item["blur"] / 2)
        a, b, ia, ib = m1[sl], m2[sl], i1[sl], i2[sl]
        first = mem > a
        second = ~first & (mem > b)
        b[first], ib[first] = a[first], ia[first]
        a[first], ia[first] = mem[first], k + 1
        b[second], ib[second] = mem[second], k + 1
        dx, dy = hx[sl] * 2 - item["pivot"][0], hy[sl] * 2 - item["pivot"][1]
        if item["bend"]:
            moved = item["amp"] * item["bend"] * np.clip(-dy / item["bend"], 0, 1.25) ** 1.3 * 1.25
        else:
            moved = item["amp"] * np.hypot(dx, dy)
        reachmax[sl] = np.maximum(reachmax[sl], np.where(mem > 0.02, moved + 3.0 * item["flutter"], 0))
    i2[m2 < 0.02] = 0
    member = np.clip(m1 + np.where(i2 > 0, m2, 0), 0, 1)
    mix = np.where(i2 > 0, m2 / np.maximum(m1 + m2, 1e-6), 0)

    # Fall to zero towards anything that must not move: over 1.5 times the distance a pixel can move next
    # to a character or an authored object, and over 1.2 times that distance next to what merely stands
    # beside a tree (a lamp post, a bench), so a pixel never moves as far as the still thing is away. (The
    # page also holds the characters outright, see `hold`: this ramp is what makes a crown or a flower
    # ease to rest beside an arm or a leg instead of being cut off at it.)
    half = lambda m: cv2.resize(m.astype(np.uint8), (hw, hh), interpolation=cv2.INTER_AREA) > 0
    still_h = half(still & ~no_gate)
    away = lambda m: cv2.distanceTransform((~half(m)).astype(np.uint8), cv2.DIST_L2, 5) * 2 - GATE_MARGIN
    can = cv2.GaussianBlur(reachmax, (0, 0), 4)
    reach = cv2.dilate(reachmax, ellipse(3)) * np.array([0.0] + [i["kind"] != "flower" for i in segs.items], np.float32)[i1]
    gate = np.clip(np.minimum(away(fixed & ~no_gate) / (1.5 * can + 3), away(solid & ~no_gate) / (1.2 * can + 2)), 0, 1)
    # What the page holds outright: the characters and authored objects, grown over their ink outline.
    # A held pixel always shows itself, and nothing is ever drawn from one.
    hold = half(dilate(fixed, 2))
    weight = np.minimum(member, gate)
    weight[weight < 0.02] = 0

    # Leaf flutter: only in a band along the crowns' outer edges (and the edges of their leaf clumps).
    scale = np.array([0.0] + [i["flutter"] for i in segs.items], np.float32)[i1]
    leaf_h = cv2.resize((foliage & (segs.label > 0)).astype(np.uint8), (hw, hh), interpolation=cv2.INTER_AREA) > 0
    crown = cv2.morphologyEx(leaf_h.astype(np.uint8), cv2.MORPH_CLOSE, ellipse(6))
    inside = cv2.distanceTransform(crown, cv2.DIST_L2, 5)
    flutter = np.clip(1 - (inside - 2) / 20, 0, 1) * scale * (weight > 0)
    flutter = cv2.GaussianBlur(flutter.astype(np.float32), (0, 0), 2)

    water = np.zeros((h, w), np.float32)
    if "water" in scene:
        r, g, b = light[..., 0], light[..., 1], light[..., 2]
        # The pond is told by its colour (blue water, green reflections, lily pads), so a sleeve, a hand,
        # a phone or a stone in front of it stay out.
        pond = poly_mask(scene["water"], w, h)
        wet = ((b > r - 5) | (g > r + 10)) & (val > 60)
        m = ndimage.binary_fill_holes(opened(pond & wet, 3)) & pond
        water = np.clip(cv2.distanceTransform(m.astype(np.uint8), cv2.DIST_L2, 5) / 14, 0, 1)

    kinds = {}
    for item in segs.items:
        kinds[item["kind"]] = kinds.get(item["kind"], 0) + 1
    rows = [[round(i["pivot"][0]), round(i["pivot"][1]), round(i["amp"] * 1e4), round(i["bend"]), round(i["freq"] * 100)] for i in segs.items]
    return {
        "near_tree": near_tree,
        "foliage": foliage,
        "sky": sky,
        "free": free,
        "above": above,
        "solid": solid,
        "fixed": fixed,
        "hold": hold,
        "back": back,
        "behind": behind,
        "can": reach,
        "still_h": still_h,
        "weight": weight,
        "water": water,
        "i1": i1,
        "i2": i2,
        "mix": mix,
        "flutter": flutter,
        "segs": rows,
        "kinds": kinds,
    }


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
        fruit = (r > 185) & (g > 150) & (b < 110) & st["near_tree"]  # lemons catch the last light
        free = erode(free, 1) & ~dilate((leafy & st["near_tree"]) | warm | fruit, 3)
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
    for box in scene.get("birds", []) + scene.get("bulbs", []) + [scene[k]["box"] for k in ("kite", "balloon") if k in scene]:
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

    # -- the hot-air balloon (with its basket)
    if "balloon" in scene:
        box = px_box(scene["balloon"]["box"], w, h)
        x0, y0, x1, y1 = box
        model, sigma = fit_sky(img, cand & ~taken, box, w, h, scene["horizon"])
        alpha, sky = matte(img, model, sigma, box, soft=30.0)
        alpha = alpha * dilate(big_parts(dilate(alpha > 0.3, 6), 400), 3)
        rgb = unmix(img[y0:y1, x0:x1], sky, alpha)
        paint_out(box, sky, dilate(alpha > 0.02, 5))
        put_back(box, rgb, alpha)
        tx0, ty0, tx1, ty1 = trim(alpha)
        data["balloon"] = {"r": [x0 + tx0, y0 + ty0, tx1 - tx0, ty1 - ty0], "i": atlas.add(rgb[ty0:ty1, tx0:tx1], alpha[ty0:ty1, tx0:tx1])}

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
        # Make the cloud whole, so it can drift right across the sky. Behind the trees in front of it, it
        # is carried on in rounded lobes (the cloud's own shape grown into what the tree hides, never
        # below its flat base)...
        reach = int(np.clip(0.45 * (y1 - y0), 50, 140))
        gx0, gy0, gx1, gy1 = max(0, x0 - reach), max(0, y0 - reach), min(w, x1 + reach), min(h, y1 + reach)
        inner = (slice(y0 - gy0, y1 - gy0), slice(x0 - gx0, x1 - gx0))
        wide_a = np.zeros((gy1 - gy0, gx1 - gx0), np.float32)
        wide_c = np.zeros((gy1 - gy0, gx1 - gx0, 3), np.float32)
        wide_a[inner], wide_c[inner] = alpha, rgb
        behind = hidden[gy0:gy1, gx0:gx1]
        solid = wide_a > 0.5
        rows = solid.sum(1)
        base = int(np.nonzero(rows > 0.3 * rows.max())[0].max())
        # What a tree hides is cloud if it lies under the cloud's top (a cloud's base is flat), in a hollow
        # of its outline, or just past its hidden end.
        under = np.maximum.accumulate(solid, axis=0)
        ends = cv2.dilate(solid.astype(np.uint8), np.ones((1, 61), np.uint8)).astype(bool)
        grow = behind & (under | erode(dilate(solid, reach), reach) | ends) & ~solid
        grow[base + 1 :] = False
        if grow.any():
            # Colour from well inside the cloud, where nothing of the tree's edge is mixed in.
            core = erode(wide_a > 0.9, 5)
            near = ndimage.distance_transform_edt(~(core if core.any() else solid), return_distances=False, return_indices=True)
            carried = cv2.GaussianBlur(wide_c[near[0], near[1]], (0, 0), 5)
            shape = cv2.GaussianBlur((solid | grow).astype(np.float32), (0, 0), 9) > 0.5  # round the lobes
            grown = cv2.GaussianBlur((shape & (behind | solid)).astype(np.float32), (0, 0), 1.5)
            fill = behind & (grown > wide_a)
            wide_a = np.where(fill, grown, wide_a).astype(np.float32)
            wide_c = np.where(fill[..., None], carried, wide_c).astype(np.float32)
        tx0, ty0, tx1, ty1 = trim(wide_a)
        rgb, alpha = wide_c[ty0:ty1, tx0:tx1], wide_a[ty0:ty1, tx0:tx1]
        rx, rw = gx0 + tx0, tx1 - tx0
        # ...and where the picture's edge cut it, it is closed with its own mirror image (outside the
        # picture until it drifts in).
        if rx <= 4:
            rgb, alpha = np.concatenate([rgb[:, ::-1], rgb], 1), np.concatenate([alpha[:, ::-1], alpha], 1)
            rx, rw = rx - rw, 2 * rw
        elif rx + rw >= w - 4:
            rgb, alpha = np.concatenate([rgb, rgb[:, ::-1]], 1), np.concatenate([alpha, alpha[:, ::-1]], 1)
            rw = 2 * rw
        data["clouds"].append({"r": [rx, gy0 + ty0, rw, ty1 - ty0], "i": atlas.add(rgb, alpha, CLOUD_SCALE)})

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
        # String lights: every bulb in the authored boxes, with the swaying piece it hangs in.
        bulbs = []
        for bbox in scene.get("bulbs", []):
            x0, y0, x1, y1 = px_box(bbox, w, h)
            sub = img[y0:y1, x0:x1]
            lit = (lum[y0:y1, x0:x1] > 205) & (sub[..., 0] >= sub[..., 2])
            n, labels, stats, cents = cv2.connectedComponentsWithStats(opened(lit, 2).astype(np.uint8), connectivity=8)
            for k in range(1, n):
                if stats[k, cv2.CC_STAT_AREA] < 150:
                    continue
                bx, by = float(cents[k][0] + x0), float(cents[k][1] + y0)
                hy, hx = min(st["i1"].shape[0] - 1, int(by * MASK_SCALE)), min(st["i1"].shape[1] - 1, int(bx * MASK_SCALE))
                bulbs.append([round(bx, 1), round(by, 1), round(float(np.sqrt(stats[k, cv2.CC_STAT_AREA] / np.pi)), 1), int(st["i1"][hy, hx]), round(float(st["weight"][hy, hx]), 2)])
        if bulbs:
            data["bulbs"] = sorted(bulbs)
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

    # -- the skyline and the sky behind the trees, carried on under the leaves in front of them: what a
    # leaf uncovers when it sways aside, so only as far in as the leaves there can move. Buildings are
    # upright, so each pixel takes the nearest clean pixel of the skyline counting a step up or down as a
    # third of a step sideways. (A sliver a few pixels wide: soft is fine, and far smaller to send.)
    back = st["back"]
    carried_on = np.zeros((h, w), bool)
    clean = erode(back, 2) & ~removal  # not the blended pixels along a leaf's edge
    reach = 1.15 * cv2.resize(st["can"], (w, h), interpolation=cv2.INTER_LINEAR) + 8
    reach[reach < 9] = 0  # nothing moves there
    under = (cv2.distanceTransform((~back).astype(np.uint8), cv2.DIST_L2, 5) <= np.minimum(reach, BACK_REACH + 10)) & ~clean & ~removal
    if clean.any() and under.any():
        ys, xs = np.nonzero(under)
        y0, y1, x0, x1 = max(0, ys.min() - 4 * BACK_REACH), min(h, ys.max() + 4 * BACK_REACH), max(0, xs.min() - 2 * BACK_REACH), min(w, xs.max() + 2 * BACK_REACH)
        win = (slice(y0, y1), slice(x0, x1))
        idx = ndimage.distance_transform_edt(~clean[win], sampling=(0.33, 1.0), return_distances=False, return_indices=True)
        carried = cv2.GaussianBlur(plate[win][idx[0], idx[1]], (0, 0), sigmaX=3, sigmaY=0.6)
        # ...and on the skyline's own side a soft rim, which only the blended pixels of an edge ever show.
        rim = dilate(under, 10) & clean
        soft = cv2.GaussianBlur(plate[win], (0, 0), 4)
        plate[win][under[win]] = carried[under[win]]
        plate[win][rim[win]] = soft[rim[win]]
        carried_on = under | rim

    # -- and the rock, wall or bench behind the flowers drawn across it, carried on under them from the
    # object's own nearest pixels: what a flower head uncovers when it sways aside.
    obj = st["behind"]
    if obj.any():
        clean = erode(obj, 2)
        under = dilate(obj, OBJECT_REACH) & ~clean & ~removal
        ys, xs = np.nonzero(under)
        y0, y1, x0, x1 = max(0, ys.min() - 60), min(h, ys.max() + 60), max(0, xs.min() - 60), min(w, xs.max() + 60)
        win = (slice(y0, y1), slice(x0, x1))
        idx = ndimage.distance_transform_edt(~clean[win], return_distances=False, return_indices=True)
        carried = cv2.GaussianBlur(plate[win][idx[0], idx[1]], (0, 0), 2.5)
        plate[win][under[win]] = carried[under[win]]
        carried_on |= under

    err = np.abs(check - img)
    data["_fit"] = (float(err.mean()), float(np.percentile(err, 99.9)), float(err.max()))
    return data, atlas, removal, plate, plate_on, carried_on, hidden


# ----------------------------------------------------------------------------------------- output


def save_webp(arr, path, **kw):
    Image.fromarray(arr).save(path, **kw)
    return path.stat().st_size


def overlay(light, st, removal, scene, w, h, path, width=1800):
    """The review picture: every swaying piece in its own colour (strength = its weight) with its pivot,
    leaf flutter white, water blue, cut-outs magenta; the characters and authored objects (never moved)
    hatched cyan; the still layers behind what sways (the skyline and sky behind the trees, a rock or wall
    behind the flowers drawn across it: never moved either) hatched orange; the other still things (lamp
    posts, benches by a tree) outlined yellow."""
    out = light.copy()
    up = lambda m, how=cv2.INTER_LINEAR: cv2.resize(m, (w, h), interpolation=how)

    def tint(mask, colour, amount):
        a = (mask * amount)[..., None]
        out[:] = out * (1 - a) + np.asarray(colour, np.float32) * a

    rng = np.random.default_rng(3)
    palette = np.concatenate([[[0, 0, 0]], rng.uniform(60, 255, (len(st["segs"]), 3)) * [1, 0.45, 0.8] + [0, 0, 0]]).astype(np.float32)
    piece = palette[up(st["i1"], cv2.INTER_NEAREST)]
    a = (up(st["weight"]) * 0.72)[..., None]
    out[:] = out * (1 - a) + piece * a
    tint(up(st["flutter"]), (255, 255, 255), 0.45)
    tint(st["water"], (0, 60, 255), 0.7)
    tint(removal.astype(np.float32), (255, 0, 255), 0.6)
    still = up(st["still_h"].astype(np.uint8), cv2.INTER_NEAREST) > 0
    out[still ^ erode(still, 2)] = (255, 235, 0)
    yy, xx = np.mgrid[0:h, 0:w]
    for mask, colour, lean in ((st["fixed"], (0, 225, 255), 1), (st["back"] | st["behind"], (255, 140, 0), -1)):
        tint((mask & ((xx + lean * yy) % 14 < 5)).astype(np.float32), colour, 0.55)
        out[mask ^ erode(mask, 2)] = colour
    out = out.clip(0, 255).astype(np.uint8)
    for x, y, amp, bend, freq in st["segs"]:
        cv2.circle(out, (int(x), int(y)), 9 if not bend else 5, (255, 255, 255), -1)
        cv2.circle(out, (int(x), int(y)), 9 if not bend else 5, (0, 0, 0), 2)
    small = out if width >= w else cv2.resize(out, (width, round(h * width / w)), interpolation=cv2.INTER_AREA)
    Image.fromarray(small).save(path, quality=84)


def build(name):
    scene = CFG["scenes"][name]
    slot = SCREENS["slots"][name]
    light = load(slot["light"])
    h, w = light.shape[:2]
    st = structure(scene, slot, light, w, h)
    msize = (round(w * MASK_SCALE), round(h * MASK_SCALE))
    psize = (round(w * PLATE_SCALE), round(h * PLATE_SCALE))
    kinds = ", ".join(f"{v} {k}s" for k, v in sorted(st["kinds"].items()))
    print(
        f"{name}: {w}x{h}  {len(st['segs'])} swaying pieces ({kinds}) on {100 * (st['weight'] > 0).mean():.1f}% of the picture, water on {100 * (st['water'] > 0).mean():.2f}%,"
        f" max weight on still pixels {st['weight'][st['still_h']].max() if st['still_h'].any() else 0:.3f}"
    )
    # Which piece, its neighbour, how much of the neighbour, and the flutter: one lossless picture.
    # Alpha: 128 where the page holds the picture still outright (characters, authored objects), else 255.
    seg = np.stack([st["i1"], st["i2"], (np.round(st["mix"] * 30).astype(np.uint8) << 4) | np.round(st["flutter"].clip(0, 1) * 15).astype(np.uint8), np.where(st["hold"], 128, 255).astype(np.uint8)], -1)
    size_s = save_webp(seg, OUT / f"{name}-seg.webp", lossless=True, quality=100, method=4)
    print(f"  seg {size_s / 1024:.0f} KB")
    entry = {
        "size": [w, h],
        "mobile": slot.get("mobile"),
        "fg": slot.get("foreground"),
        "seg": f"/marketing/motion/{name}-seg.webp",
        "segs": st["segs"],
        "cloudBand": scene.get("cloudBand", [0.03, 0.4]),
        "lanes": scene.get("lanes", []),
        "lanesMobile": scene.get("lanesMobile", scene.get("lanes", [])),
        "birdExit": scene.get("birdExit", [1, -0.2]),
        "water": "water" in scene,
    }
    for theme in ("light", "dark"):
        img = light if theme == "light" else load(slot["dark"])
        data, atlas, removal, plate, plate_on, carried_on, hidden = cut_theme(scene, st, img, theme, w, h)
        fit = data.pop("_fit")

        blue = np.full((h, w), 128, np.float32)
        blue[hidden] = 0
        blue[removal] = 255
        blue = cv2.resize(blue, msize, interpolation=cv2.INTER_AREA).round()
        water = cv2.resize(st["water"], msize, interpolation=cv2.INTER_AREA)
        # 32 and 16 levels compress far better
        # Alpha: 255 in front, 128 the skyline and sky behind the trees (never 0, so no decoder drops the colours).
        behind = cv2.resize((st["back"] | st["behind"]).astype(np.float32), msize, interpolation=cv2.INTER_AREA)
        mask = np.stack([np.round(st["weight"] * 31) * (255 / 31), np.round(water * 15) * 17, blue, 255 - np.round(behind * 4) * (127 / 4)], -1).astype(np.uint8)
        size_m = save_webp(mask, OUT / f"{name}-{theme}-mask.webp", lossless=True, quality=100, method=4)

        # Only the plate's used parts matter; the rest is filled smoothly from them (no hard edge to pay for).
        # Grey wherever the plate is not used, so it stays small. Around a cut-out it keeps a margin of the
        # picture; the carried-on skyline is its own margin.
        flat = np.where((dilate(plate_on, 8) | carried_on)[..., None], plate, 128.0)
        flat = cv2.resize(flat, psize, interpolation=cv2.INTER_AREA).round().astype(np.uint8)
        size_p = save_webp(flat, OUT / f"{name}-{theme}-plate.webp", quality=84, method=6)

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
        if "balloon" in data:
            place(data["balloon"])
        data.update(mask=f"/marketing/motion/{name}-{theme}-mask.webp", plate=f"/marketing/motion/{name}-{theme}-plate.webp", atlas=f"/marketing/motion/{name}-{theme}-atlas.webp", atlasSize=[sheet.shape[1], sheet.shape[0]])
        entry[theme] = data
        print(
            f"  {theme}: mask {size_m / 1024:.0f} KB, plate {size_p / 1024:.0f} KB, atlas {size_a / 1024:.0f} KB ({sheet.shape[1]}x{sheet.shape[0]}) = {(size_m + size_p + size_a) / 1024:.0f} KB;"
            f" {len(data['clouds'])} clouds, {len(data['birds'])} birds{', ' + str(len(data['bulbs'])) + ' bulbs' if 'bulbs' in data else ''}; rest frame vs picture: mean {fit[0]:.3f}, p99.9 {fit[1]:.1f}, max {fit[2]:.0f} (of 255)"
        )

        # Review pictures.
        if theme == "light":
            overlay(light, st, removal, scene, w, h, REVIEW / f"{name}-masks.jpg")
        clean = np.where((removal | carried_on)[..., None], plate, img)
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
