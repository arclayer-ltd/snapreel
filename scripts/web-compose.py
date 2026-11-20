#!/usr/bin/env python3
"""Composite real Snapreel screenshots into the website's iPhones, and export its scenes.

Driven by art/web/screens.json (slots, lighting presets, screenshot ids). Run from the repo root:

    python scripts/web-compose.py                 # every slot
    python scripts/web-compose.py phone-hero scene-hero
    python scripts/web-compose.py --light-dir D:/ci/screenshots --dark-dir D:/ci/dark/screenshots
    python scripts/web-compose.py --preview       # also writes JPEG previews to art/web/review/compose/

Kinds of slot:

- "scene": an illustrated environment (Light and Dusk). Exported as AVIF (WebP fallback) at the
  page's widths, with an optional centre crop for phones ("mobile"), an optional foreground
  cut-out that sits in front of the phone ("foreground", e.g. the hero's flower bed) and the sky
  colour along the top edge, which the page uses above the picture. A "wide" box makes a crop
  (the guide-card spots).
- "iphone": renders an iPhone 16 Pro (titanium frame with an edge gradient, side buttons, glass
  rim highlight) in 3D at the slot's pose, puts the lit screenshot on its glass and casts a
  shadow, all in the colours of the slot's lighting preset for that mode ("day", "dusk",
  "golden", "studio", "studio-dark"; see LIGHTS and screens.json "lights").
- "art": a character illustration (transparent PNG) holding a device whose screen is flat
  #00FF00 (round 1's red-field site). The green quad is found, the screenshot warped in with
  rounded corners, Dynamic Island, glass edge, reflection and bounce, matched to the art's
  softness and grain.
- Every slot with a screen is made twice, with the Light and the Dark screenshot (falling back
  to Light when there's no Dark one), so the page can swap them with prefers-color-scheme.

Writes web/components/marketing/art-manifest.ts with sizes and paths for the page.

Needs Pillow (with AVIF), numpy and OpenCV.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "art/web/screens.json"

WINE = (94, 11, 22)
GLOW = (254, 98, 98)
RNG = np.random.default_rng(7)

# Lighting for an iPhone placed in an illustrated scene. "red" is the old red-field look. A slot
# picks one per mode with "lighting": {"light": "day", "dark": "dusk"} (or one name for both);
# screens.json can add or override presets under "lights".
#   sky / ground: colours bounced onto the frame from above and below (and onto the glass)
#   key:          the main light's direction (x right, y up, z towards the viewer) and colour
#   bounce:       how much of the ground colour tints the screen, and from which side
#   shadow:       the cast shadow's colour
LIGHTS: dict[str, dict] = {
    "red": dict(sky=GLOW, ground=GLOW, key=([-0.55, 0.65, 0.52], (255, 255, 255)), sky_amt=0.0,
                ground_amt=0.22, bounce=0.08, bounce_side="right", tint=GLOW, shadow=WINE),
}


def lighting(name: str | None, overrides: dict) -> dict:
    base = dict(LIGHTS["red"])
    if name:
        spec = overrides.get(name) or LIGHTS.get(name)
        if spec is None:
            raise SystemExit(f"unknown lighting preset {name}")
        base.update({k: (tuple(v) if isinstance(v, list) and k not in ("key",) else v) for k, v in spec.items()})
    key = base["key"]
    if isinstance(key, dict):
        base["key"] = (key["dir"], tuple(key.get("color", (255, 255, 255))))
    return base


# ----------------------------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------------------------

def rounded_mask(size: tuple[int, int], radius: float, inset: float = 0, ss: int = 4) -> Image.Image:
    """Anti-aliased rounded-rectangle mask (L) of `size`, inset by `inset` px on every side."""
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [inset * ss, inset * ss, (w - inset) * ss - 1, (h - inset) * ss - 1],
        radius=max(0, radius) * ss,
        fill=255,
    )
    return big.resize((w, h), Image.LANCZOS)


def to_np(img: Image.Image) -> np.ndarray:
    return np.asarray(img).astype(np.float32) / 255.0


def from_np(arr: np.ndarray, mode: str = "RGBA") -> Image.Image:
    return Image.fromarray(np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8), mode)


def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    """Porter-Duff src-over for float RGBA arrays (not premultiplied)."""
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 1e-6, (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6), 0)
    return np.concatenate([rgb, oa], axis=-1)


def blur_alpha(alpha: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0:
        return alpha
    k = int(sigma * 3) * 2 + 1
    return cv2.GaussianBlur(alpha, (k, k), sigma)


def shadow_layer(alpha: np.ndarray, dx: float, dy: float, sigma: float, strength: float,
                 length: float = 0.0, steps: int = 12, color=WINE) -> np.ndarray:
    """Soft wine shadow from a silhouette: offset, optionally smeared along (dx, dy) for a long
    shadow, then blurred. Returns float RGBA."""
    h, w = alpha.shape
    acc = np.zeros_like(alpha)
    if length > 0:
        for i in range(steps):
            t = i / (steps - 1)
            m = np.float32([[1, 0, dx * (1 + t * length)], [0, 1, dy * (1 + t * length)]])
            shifted = cv2.warpAffine(alpha, m, (w, h), flags=cv2.INTER_LINEAR, borderValue=0)
            acc = np.maximum(acc, shifted * (1 - 0.85 * t))
    else:
        m = np.float32([[1, 0, dx], [0, 1, dy]])
        acc = cv2.warpAffine(alpha, m, (w, h), flags=cv2.INTER_LINEAR, borderValue=0)
    acc = blur_alpha(acc, sigma) * strength
    out = np.zeros((h, w, 4), np.float32)
    out[..., 0], out[..., 1], out[..., 2] = (c / 255 for c in color)
    out[..., 3] = acc
    return out


# ----------------------------------------------------------------------------------------------
# The lit screen (built in screenshot space, so every effect follows the perspective warp)
# ----------------------------------------------------------------------------------------------

def lit_screen(shot: Image.Image, size: tuple[int, int], *, island: bool, radius_frac: float,
               edge_frac: float, bounce: float, bounce_side: str, exposure: float,
               tint=GLOW, sky=None, sky_amt: float = 0.0) -> Image.Image:
    """Return an RGBA image of `size`: black glass with the screenshot inset by a thin edge,
    rounded corners, Dynamic Island, inner edge shadow, glass reflection and an ambient bounce
    in the scene's colour (`tint`), plus an optional faint reflection of the sky (`sky`)."""
    w, h = size
    edge = max(1.0, w * edge_frac)
    sw, sh = int(round(w - 2 * edge)), int(round(h - 2 * edge))
    content = shot.convert("RGB").resize((sw, sh), Image.LANCZOS)
    c = to_np(content)

    # Exposure and an ambient bounce from the surroundings, stronger on one side.
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    u = xx / max(1, sw - 1)
    v = yy / max(1, sh - 1)
    side = {"right": u, "left": 1 - u, "bottom": v, "none": np.zeros_like(u)}[bounce_side]
    glow = np.array(tint, np.float32) / 255
    amount = (bounce * (0.45 + 0.9 * side))[..., None]
    c = c * exposure
    c = c * (1 - amount) + (c * glow * 1.15 + glow * 0.18) * amount  # tinted multiply-ish bounce

    # The sky reflected in the glass: strongest at the top, fading by the middle (screen blend).
    if sky is not None and sky_amt > 0:
        s = np.array(sky, np.float32) / 255
        refl = (np.clip(1 - v / 0.55, 0, 1) ** 1.4 * sky_amt)[..., None]
        c = 1 - (1 - c) * (1 - s * refl)

    # Inner screen-edge shadow (the glass edge throws a soft shade onto the pixels).
    d = np.minimum(np.minimum(xx, sw - 1 - xx), np.minimum(yy, sh - 1 - yy))
    band = max(2.0, sw * 0.03)
    shade = np.clip(d / band, 0, 1) ** 0.7
    c = c * (0.72 + 0.28 * shade)[..., None]

    # Glass reflection: a soft diagonal sheen from the top-left plus a faint cool rim on the left.
    diag = (u * 0.55 + v * 0.45)
    sheen = np.clip(1 - diag / 0.62, 0, 1) ** 1.6 * 0.10
    streak = np.exp(-((diag - 0.30) / 0.035) ** 2) * 0.035
    cool = np.clip(1 - u / 0.08, 0, 1) ** 2 * 0.05
    c = c + (sheen + streak)[..., None] * (1 - c) + cool[..., None] * np.array([0.75, 0.85, 1.0])

    content = from_np(np.clip(c, 0, 1), "RGB")

    # Dynamic Island, drawn on the content so it warps with it.
    if island:
        dr = ImageDraw.Draw(content, "RGBA")
        iw, ih = sw * 0.318, sh * 0.0435
        top = sh * 0.0128
        x0 = (sw - iw) / 2
        ss = 4
        isl = Image.new("L", (int(sw * ss), int(sh * 0.08 * ss)), 0)
        ImageDraw.Draw(isl).rounded_rectangle([x0 * ss, top * ss, (x0 + iw) * ss, (top + ih) * ss],
                                              radius=ih / 2 * ss, fill=255)
        isl = isl.resize((sw, int(sh * 0.08)), Image.LANCZOS)
        black = Image.new("RGB", isl.size, (6, 6, 8))
        content.paste(black, (0, 0), isl)
        # the front camera, barely visible
        cx, cy, r = x0 + iw * 0.80, top + ih / 2, ih * 0.22
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(18, 20, 30, 255))
        dr.ellipse([cx - r * 0.45, cy - r * 0.65, cx + r * 0.05, cy - r * 0.15], fill=(60, 70, 110, 120))

    out = Image.new("RGBA", (w, h), (4, 4, 6, 0))
    glass = rounded_mask((w, h), radius=w * radius_frac)
    out.paste(Image.new("RGBA", (w, h), (4, 4, 6, 255)), (0, 0), glass)
    inner = rounded_mask((sw, sh), radius=max(0, w * radius_frac - edge))
    out.paste(content.convert("RGBA"), (int(round(edge)), int(round(edge))), inner)
    return out


# ----------------------------------------------------------------------------------------------
# Green-screen detection on the art
# ----------------------------------------------------------------------------------------------

def green_mask(arr: np.ndarray, lenient: bool = False) -> np.ndarray:
    r, g, b, a = (arr[..., i].astype(np.int32) for i in range(4))
    if lenient:
        m = (g > np.maximum(r, b) + 28) & (g > 70)
    else:
        m = (g > 150) & (g > r * 1.6) & (g > b * 1.6)
    return m & (a > 20)


def fit_quad(arr: np.ndarray, portrait: bool) -> tuple[np.ndarray, np.ndarray]:
    """Find the screen quad (4x2 float, TL TR BR BL in the device's own orientation) and the
    filled screen region mask."""
    gm = green_mask(arr).astype(np.uint8) * 255
    gm = cv2.morphologyEx(gm, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    contours, _ = cv2.findContours(gm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        raise SystemExit("no green screen found")
    cnt = max(contours, key=cv2.contourArea)
    region = np.zeros(gm.shape, np.uint8)
    cv2.drawContours(region, [cnt], -1, 255, thickness=cv2.FILLED)

    hull = cv2.convexHull(cnt)
    peri = cv2.arcLength(hull, True)
    approx = None
    for eps in np.linspace(0.01, 0.12, 60):
        a = cv2.approxPolyDP(hull, eps * peri, True)
        if len(a) == 4:
            approx = a.reshape(4, 2).astype(np.float32)
            break
    if approx is None:
        rect = cv2.minAreaRect(cnt)
        approx = cv2.boxPoints(rect).astype(np.float32)

    # Refine each side to its outer envelope: try angles near the rough side and keep the
    # supporting line that hugs the most contour points. Fingers or loops that cut into the
    # green only make dents, so they can't pull the edge inwards.
    pts = cnt.reshape(-1, 2).astype(np.float32)
    centre = pts.mean(axis=0)
    lines = []
    for i in range(4):
        p0, p1 = approx[i], approx[(i + 1) % 4]
        seg = p1 - p0
        L = float(np.linalg.norm(seg))
        d0 = seg / max(L, 1e-6)
        rel = pts - p0
        t = rel @ d0
        n0 = np.array([-d0[1], d0[0]])
        if (centre - p0) @ n0 > 0:
            n0 = -n0  # outward
        side_pts = pts[(t > 0.12 * L) & (t < 0.88 * L) & (np.abs(rel @ n0) < max(10.0, L * 0.08))]
        if len(side_pts) < 10:
            lines.append((p0, d0))
            continue
        base = math.atan2(d0[1], d0[0])
        best = None
        for da in np.radians(np.linspace(-4, 4, 161)):
            a = base + da
            d = np.array([math.cos(a), math.sin(a)])
            n = np.array([-d[1], d[0]])
            if n @ n0 < 0:
                n = -n
            proj = side_pts @ n
            s = np.percentile(proj, 99.5)
            gap = np.median(s - proj)
            if best is None or gap < best[0]:
                best = (gap, d, n, s)
        _, d, n, s = best
        lines.append((n * s, d))
    corners = []
    for i in range(4):
        (pa, da), (pb, db) = lines[i - 1], lines[i]
        m = np.array([da, -db]).T
        try:
            s = np.linalg.solve(m, pb - pa)
            corners.append(pa + da * s[0])
        except np.linalg.LinAlgError:
            corners.append(approx[i])
    q = np.array(corners, np.float32)

    # Order clockwise from the device's top-left.
    c = q.mean(axis=0)
    ang = np.arctan2(q[:, 1] - c[1], q[:, 0] - c[0])
    q = q[np.argsort(ang)]  # clockwise in image coordinates (y down)
    best, best_score = 0, None
    for s in range(4):
        r = np.roll(q, -s, axis=0)
        top = np.linalg.norm(r[1] - r[0])
        side = np.linalg.norm(r[2] - r[1])
        if portrait != (top < side):
            continue
        score = (r[0][1] + r[1][1]) / 2  # the top edge is the higher one
        if best_score is None or score < best_score:
            best, best_score = s, score
    return np.roll(q, -best, axis=0), region


def edge_blur_sigma(arr: np.ndarray, quad: np.ndarray) -> float:
    """Measure how soft the art is where the green meets the bezel (10-90% rise), as a Gaussian
    sigma in px, so the screenshot can be softened to match."""
    g = arr[..., 1].astype(np.float32) - np.maximum(arr[..., 0], arr[..., 2]).astype(np.float32)
    g = np.clip(g / 255.0, 0, 1)
    c = quad.mean(axis=0)
    widths = []
    for i in range(4):
        p0, p1 = quad[i], quad[(i + 1) % 4]
        for t in np.linspace(0.25, 0.75, 9):
            p = p0 + (p1 - p0) * t
            n = (c - p) / max(np.linalg.norm(c - p), 1e-6)
            samples = []
            for s in np.arange(-10, 14, 0.5):
                x, y = p + n * s
                xi, yi = int(round(x)), int(round(y))
                if 0 <= yi < g.shape[0] and 0 <= xi < g.shape[1]:
                    samples.append(g[yi, xi])
                else:
                    samples.append(0.0)
            prof = np.array(samples)
            hi = prof.max()
            if hi < 0.5:
                continue
            a10 = np.argmax(prof > 0.1 * hi)
            a90 = np.argmax(prof > 0.9 * hi)
            if a90 > a10:
                widths.append((a90 - a10) * 0.5)
    if not widths:
        return 0.6
    w = float(np.median(widths))
    return float(np.clip(w / 2.56, 0.3, 1.6))


def grain_sigma(arr: np.ndarray, region: np.ndarray) -> float:
    """Noise level of the art in flat areas near the device, in 0..1 units."""
    gray = cv2.cvtColor(arr[..., :3], cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    hp = gray - cv2.GaussianBlur(gray, (0, 0), 1.2)
    lap = np.abs(cv2.Laplacian(gray, cv2.CV_32F))
    ring = cv2.dilate(region, np.ones((61, 61), np.uint8)) > 0
    ring &= ~(cv2.dilate(region, np.ones((9, 9), np.uint8)) > 0)
    ring &= arr[..., 3] > 250
    flat = ring & (lap < np.percentile(lap[ring], 40) if ring.any() else ring)
    if flat.sum() < 200:
        return 0.004
    return float(np.clip(hp[flat].std(), 0.002, 0.02))


def add_grain(rgba: np.ndarray, mask: np.ndarray, sigma: float) -> np.ndarray:
    noise = RNG.normal(0, sigma, rgba.shape[:2]).astype(np.float32)[..., None]
    out = rgba.copy()
    out[..., :3] = np.clip(out[..., :3] + noise * mask[..., None], 0, 1)
    return out


# ----------------------------------------------------------------------------------------------
# Kind "art": a character holding a green-screen device
# ----------------------------------------------------------------------------------------------

def compose_art(slot: dict, shot: Image.Image | None) -> Image.Image:
    art = Image.open(ROOT / slot["art"]).convert("RGBA")
    arr8 = np.asarray(art).copy()
    arr = arr8.astype(np.float32) / 255
    h, w = arr.shape[:2]
    out = arr.copy()
    sh = slot.get("shadow", {})
    alpha = arr[..., 3]

    dev = slot.get("device", "iphone")
    if shot is not None:
        portrait = dev != "laptop"
        quad, region = fit_quad(arr8, portrait=portrait)
        sigma = edge_blur_sigma(arr8, quad)
        grain = grain_sigma(arr8, region)

        # Screen texture sized to the quad's rough pixel size (x1.25 for clean sampling).
        top = np.linalg.norm(quad[1] - quad[0])
        side = np.linalg.norm(quad[3] - quad[0])
        tw, th = int(top * 1.25), int(side * 1.25)
        if dev == "laptop":
            tex = lit_screen(shot, (tw, th), island=False, radius_frac=0.012, edge_frac=0.004,
                             bounce=slot.get("bounce", 0.10), bounce_side=slot.get("bounceSide", "right"),
                             exposure=slot.get("exposure", 0.95))
        else:
            tex = lit_screen(shot, (tw, th), island=True, radius_frac=slot.get("radius", 0.13),
                             edge_frac=0.012, bounce=slot.get("bounce", 0.10),
                             bounce_side=slot.get("bounceSide", "right"), exposure=slot.get("exposure", 0.94))

        # Grow the quad a touch so the black glass covers the anti-aliased green fringe.
        c = quad.mean(axis=0)
        grow = 1.0 + 2.0 / max(top, side)
        dst = (quad - c) * grow + c
        src = np.float32([[0, 0], [tw, 0], [tw, th], [0, th]])
        m = cv2.getPerspectiveTransform(src, dst.astype(np.float32))
        t = np.asarray(tex).astype(np.float32) / 255
        warped = cv2.warpPerspective(t, m, (w, h), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
        # premultiplied blur so edges don't fringe
        rgb = warped[..., :3] * warped[..., 3:4]
        k = int(sigma * 3) * 2 + 1
        rgb = cv2.GaussianBlur(rgb, (k, k), sigma)
        a = cv2.GaussianBlur(warped[..., 3], (k, k), sigma)
        warped = np.concatenate([np.where(a[..., None] > 1e-4, rgb / np.maximum(a[..., None], 1e-4), 0), a[..., None]], -1)

        warped = add_grain(warped, warped[..., 3], grain)

        # Layers inside the screen zone, bottom to top:
        #   1. black glass wherever the art showed green (or a transparent hole) — the thin dark
        #      edge between bezel and pixels, and cover for any green the quad misses;
        #   2. the warped screenshot;
        #   3. the art again, chroma-key unmixed: green pixels go fully transparent, the soft
        #      edges of fingers and loops keep their own colour at partial alpha. Opaque blobs
        #      enclosed by the green (a drawn notch) are dropped so only our island shows.
        quad_mask = np.zeros((h, w), np.uint8)
        cv2.fillConvexPoly(quad_mask, dst.astype(np.int32), 255)
        rgb = arr[..., :3]
        greenness = np.clip((rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])) / 0.85, 0, 1)
        greenness = np.where(rgb[..., 1] > 0.18, greenness, 0)
        # A transparent hole inside the green (the model sometimes keys out part of the screen)
        # is screen too; transparency outside the green region, such as past a rounded corner, isn't.
        hole = (arr[..., 3] < 0.5) & (region > 0)
        screenish = ((greenness > 0.04) & (arr[..., 3] > 0.05)) | hole
        zone = cv2.dilate((screenish | (quad_mask > 0)).astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
        screenish &= zone

        glass = np.zeros((h, w, 4), np.float32)
        glass[..., :3] = 0.016
        glass[..., 3] = cv2.GaussianBlur(cv2.dilate(screenish.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(np.float32), (3, 3), 0.8)

        # Occluders: solid, non-green shapes inside the quad that reach in from its edge (fingers,
        # a loop drawn across the phone, the bezel in the rounded corners). Anything else inside
        # the screen (a drawn notch, the light halo round a keyed-out hole) is replaced. The
        # occluders keep a 2 px soft edge, unmixed from the green.
        solid = (quad_mask > 0) & (greenness < 0.15) & (arr[..., 3] > 0.96)
        solid = cv2.morphologyEx(solid.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        band = (quad_mask > 0) & ~(cv2.erode(quad_mask, np.ones((11, 11), np.uint8)) > 0)
        ncomp, labels = cv2.connectedComponents(solid, connectivity=8)
        reach = np.zeros(ncomp, bool)
        reach[np.unique(labels[band & (solid > 0)])] = True
        reach[0] = False
        keep = cv2.dilate(reach[labels].astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        inner = cv2.erode(quad_mask, np.ones((9, 9), np.uint8)) > 0

        a_art = arr[..., 3] * (1 - greenness)
        a_art = np.where(inner & ~keep, 0, a_art)
        safe = np.maximum(a_art, 1e-4)[..., None]
        green_rgb = np.array([0.0, 1.0, 0.0], np.float32)
        unmixed = np.clip((rgb * arr[..., 3:4] - (arr[..., 3:4] - a_art[..., None]) * green_rgb) / safe, 0, 1)
        top_layer = np.concatenate([unmixed, a_art[..., None]], -1)

        under = out.copy()
        under[zone] = 0  # the zone is rebuilt from the layers below
        stack = over(over(glass, warped), top_layer)
        out = np.where(zone[..., None], over(under, stack), out)

        # Hand + device silhouette for a tighter contact shadow on the field.
        dev_mask = cv2.dilate(quad_mask, np.ones((int(max(top, side) * 0.35),) * 2, np.uint8)) > 0
        dev_alpha = np.where(dev_mask, out[..., 3], 0).astype(np.float32)
        ds = sh.get("device", [0.012, 0.016, 0.010, 0.30])
        contact = shadow_layer(dev_alpha, ds[0] * w, ds[1] * h, ds[2] * w, ds[3])
    else:
        contact = None

    body = sh.get("body", [0.018, 0.022, 0.022, 0.26])
    base = shadow_layer(out[..., 3], body[0] * w, body[1] * h, body[2] * w, body[3])
    if contact is not None:
        base = over(base, contact)
    final = over(base, out)
    return from_np(np.clip(final, 0, 1))


# ----------------------------------------------------------------------------------------------
# Kind "iphone": a 3D iPhone 16 Pro without hands
# ----------------------------------------------------------------------------------------------

PHONE = dict(W=71.5, H=149.6, D=8.25, R=10.6, rim=0.75, screen_h=144.6)
FINISHES = {
    # base, highlight, shadow (sRGB)
    "natural": ((178, 172, 162), (236, 232, 224), (92, 86, 80)),
    "black": ((64, 64, 68), (150, 150, 156), (22, 22, 26)),
    "desert": ((190, 164, 140), (240, 220, 200), (104, 84, 70)),
}


def rot_matrix(yaw: float, pitch: float, roll: float) -> np.ndarray:
    y, p, r = (math.radians(a) for a in (yaw, pitch, roll))
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    return rz @ rx @ ry


def rr_outline(w: float, h: float, r: float, n: int = 18) -> np.ndarray:
    """Rounded-rect outline, clockwise in y-up coordinates starting top-left, as (N,2)."""
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (w / 2 - r, -h / 2 + r, -90), (-w / 2 + r, -h / 2 + r, -180),
               (-w / 2 + r, h / 2 - r, -270)]
    for cx, cy, start in corners:
        for i in range(n + 1):
            a = math.radians(start + 90 - 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts)


def phone_front_texture(shot: Image.Image, tex_w: int, finish: str, slot: dict, L: dict) -> Image.Image:
    P = PHONE
    scale = tex_w / P["W"]
    tw, th = tex_w, int(round(P["H"] * scale))
    base, hi, lo = (np.array(c, np.float32) / 255 for c in FINISHES[finish])
    tex = Image.new("RGBA", (tw, th), (0, 0, 0, 0))

    # Titanium rim seen from the front: a gradient lit from the top-left.
    yy, xx = np.mgrid[0:th, 0:tw].astype(np.float32)
    lit = np.clip(0.5 - (xx / tw - 0.5) * 0.6 - (yy / th - 0.5) * 0.5, 0, 1)
    rim = base * (1 - lit[..., None]) * 0.8 + hi * lit[..., None] * 0.9 + lo * 0.12
    rim_img = from_np(np.concatenate([np.clip(rim, 0, 1), np.ones((th, tw, 1), np.float32)], -1))
    outer = rounded_mask((tw, th), P["R"] * scale)
    tex.paste(rim_img, (0, 0), outer)

    # Black front glass inside the rim.
    rim_px = P["rim"] * scale
    glass_mask = rounded_mask((tw, th), (P["R"] - P["rim"]) * scale, inset=rim_px)
    tex.paste(Image.new("RGBA", (tw, th), (7, 7, 9, 255)), (0, 0), glass_mask)

    # The lit screen.
    sh_mm = P["screen_h"]
    sw_mm = sh_mm * shot.width / shot.height
    sw, shp = int(round(sw_mm * scale)), int(round(sh_mm * scale))
    screen = lit_screen(shot, (sw, shp), island=True, radius_frac=0.135, edge_frac=0.0,
                        bounce=slot.get("bounce", L["bounce"]), bounce_side=slot.get("bounceSide", L["bounce_side"]),
                        exposure=slot.get("exposure", L.get("exposure", 0.96)), tint=L["tint"],
                        sky=L["sky"], sky_amt=L.get("glass_sky", 0.0))
    tex.alpha_composite(screen, ((tw - sw) // 2, (th - shp) // 2))

    # Glass rim highlight: a thin bright line just inside the titanium, brighter top-left.
    ring = Image.new("L", (tw, th), 0)
    d = ImageDraw.Draw(ring)
    d.rounded_rectangle([rim_px + 1, rim_px + 1, tw - rim_px - 2, th - rim_px - 2],
                        radius=(P["R"] - P["rim"]) * scale, outline=255, width=max(1, int(scale * 0.35)))
    ring = ring.filter(ImageFilter.GaussianBlur(scale * 0.12))
    ra = to_np(ring) * np.clip(1.05 - (xx / tw) * 0.7 - (yy / th) * 0.45, 0.15, 1)
    hl = np.zeros((th, tw, 4), np.float32)
    hl[..., :3] = 1.0
    hl[..., 3] = ra * 0.55
    t = to_np(tex)
    t = over(t, hl)
    return from_np(t)


def render_iphone(slot: dict, shot: Image.Image, L: dict) -> Image.Image:
    P = PHONE
    pose = slot.get("pose", {})
    yaw, pitch, roll = pose.get("yaw", -16), pose.get("pitch", 8), pose.get("roll", -6)
    finish = slot.get("finish", "natural")
    out_w = slot.get("canvas", [900, 1300])
    SS = 2
    cw, ch = out_w[0] * SS, out_w[1] * SS
    R = rot_matrix(yaw, pitch, roll)
    dist = 520.0
    f = ch * 0.78 * dist / P["H"] / 1.1
    off = np.array(pose.get("offset", [0.0, 0.0]))

    def proj(p3: np.ndarray) -> np.ndarray:
        q = p3 @ R.T
        z = dist - q[:, 2]
        return np.stack([cw / 2 + off[0] * cw + f * q[:, 0] / z, ch / 2 + off[1] * ch - f * q[:, 1] / z], -1)

    base, hi, lo = (np.array(c, np.float32) for c in FINISHES[finish])
    outline = rr_outline(P["W"], P["H"], P["R"], n=24)
    n = len(outline)
    front = np.c_[outline, np.full(n, P["D"] / 2)]
    back = np.c_[outline, np.full(n, -P["D"] / 2)]
    pf, pb = proj(front), proj(back)

    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    light = np.array(L["key"][0], np.float64)
    light /= np.linalg.norm(light)
    key_col = np.array(L["key"][1], np.float32) / 255
    cam = np.array([0, 0, dist])
    sky_col = np.array(L["sky"], np.float32)
    ground_col = np.array(L["ground"], np.float32)

    # Side faces of the frame, split in depth bands for a machined edge gradient.
    bands = [(0.5, 0.40, 1.35), (0.40, 0.18, 1.0), (0.18, -0.30, 0.78), (-0.30, -0.5, 0.58)]
    for i in range(n):
        j = (i + 1) % n
        e = outline[j] - outline[i]
        nrm2 = np.array([e[1], -e[0]])  # outward for clockwise (y-up) outline
        if np.linalg.norm(nrm2) < 1e-6:
            continue
        nrm = np.r_[nrm2 / np.linalg.norm(nrm2), 0] @ R.T
        mid = ((front[i] + front[j]) / 2) @ R.T
        if nrm @ (cam - mid) <= 0:
            continue
        lam = max(0.0, nrm @ light)
        refl = nrm - 2 * (nrm @ np.array([0, 0, -1.0])) * np.array([0, 0, -1.0])
        spec = max(0.0, refl @ light) ** 18
        # Ambient bounce: sky on faces that look up or sideways, ground on faces that look down.
        g_amt = L["ground_amt"] * (0.6 + max(0.0, nrm[0]) * 1.0 + max(0.0, -nrm[1]) * 0.7)
        s_amt = L["sky_amt"] * (0.5 + max(0.0, nrm[1]) * 1.0 + abs(nrm[0]) * 0.4)
        for z0, z1, k in bands:
            col = base * (0.30 + 0.55 * lam) * k * key_col + hi * spec * (1.1 if k > 1.2 else 0.5) * key_col
            col = col * (1 - g_amt) + ground_col * g_amt * 0.85
            col = col * (1 - s_amt) + sky_col * s_amt * 0.85
            col = np.clip(col, 0, 255).astype(int)
            quad = np.array([
                [outline[i][0], outline[i][1], z0 * P["D"]], [outline[j][0], outline[j][1], z0 * P["D"]],
                [outline[j][0], outline[j][1], z1 * P["D"]], [outline[i][0], outline[i][1], z1 * P["D"]],
            ])
            pq = proj(quad)
            draw.polygon([tuple(p) for p in pq], fill=(*col, 255))

    # Side buttons (mm from the top): left = Action, volume up, volume down; right = side button,
    # Camera Control.
    buttons = [(-1, 26.0, 33.0), (-1, 39.0, 51.0), (-1, 54.0, 66.0), (1, 40.0, 57.0), (1, 92.0, 110.0)]
    for sgn, y0, y1 in buttons:
        x = sgn * (P["W"] / 2 + 0.55)
        nrm = np.array([sgn, 0, 0.0]) @ R.T
        mid = np.array([x, P["H"] / 2 - (y0 + y1) / 2, 0]) @ R.T
        if nrm @ (cam - mid) <= 0:
            continue
        lam = max(0.0, nrm @ light)
        col = np.clip(base * (0.5 + 0.55 * lam) * 1.05 * key_col + ground_col * L["ground_amt"] * 0.35, 0, 255).astype(int)
        cam_ctrl = sgn == 1 and y0 > 80
        if cam_ctrl:
            col = np.clip(col * 0.55, 0, 255).astype(int)
        z = 1.25
        quad = np.array([[x, P["H"] / 2 - y0, z], [x, P["H"] / 2 - y1, z], [x, P["H"] / 2 - y1, -z],
                         [x, P["H"] / 2 - y0, -z]])
        draw.polygon([tuple(p) for p in proj(quad)], fill=(*col, 255))

    # Front glass, mapped with a homography from the flat texture.
    tex_w = int(np.linalg.norm(pf[0] - pf[-1]) * 0 + cw * 0.9)
    tex = phone_front_texture(shot, tex_w, finish, slot, L)
    tw, th = tex.size
    corners3 = np.array([[-P["W"] / 2, P["H"] / 2, P["D"] / 2], [P["W"] / 2, P["H"] / 2, P["D"] / 2],
                         [P["W"] / 2, -P["H"] / 2, P["D"] / 2], [-P["W"] / 2, -P["H"] / 2, P["D"] / 2]])
    dst = proj(corners3).astype(np.float32)
    src = np.float32([[0, 0], [tw, 0], [tw, th], [0, th]])
    m = cv2.getPerspectiveTransform(src, dst)
    t = np.asarray(tex).astype(np.float32) / 255
    warped = cv2.warpPerspective(t, m, (cw, ch), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
    body = to_np(canvas)
    body = over(body, warped)

    img = from_np(np.clip(body, 0, 1)).resize((cw // SS, ch // SS), Image.LANCZOS)
    arr = to_np(img)
    a = arr[..., 3]
    s = slot.get("longShadow", [0.035, 0.045, 0.9, 0.022, 0.42])
    W = arr.shape[1]
    shadow = shadow_layer(a, s[0] * W, s[1] * W, s[3] * W, s[4], length=s[2], steps=16, color=L["shadow"])
    contact = shadow_layer(a, 0.008 * W, 0.012 * W, 0.008 * W, L.get("contact", 0.28), color=L["shadow"])
    final = over(over(shadow, contact), arr)
    return from_np(np.clip(final, 0, 1))


# ----------------------------------------------------------------------------------------------
# Kind "scene": a full-bleed illustrated environment (Light and Dusk), sized for the page
# ----------------------------------------------------------------------------------------------

def foreground_matte(img: Image.Image, box: list[float]) -> Image.Image:
    """Cut a foreground object (the hero's round flower bed) out of the scene so it can sit in
    front of the phone. `box` (fractions x0, y0, x1, y1) must have plain paving along its top and
    side edges. Paving is flood-filled in from those edges; the inked outline stops the fill, so
    whatever it can't reach (flowers, leaves and the stone rim) is the object."""
    arr = np.asarray(img.convert("RGB"))
    H, W = arr.shape[:2]
    x0, y0, x1, y1 = int(box[0] * W), int(box[1] * H), int(box[2] * W), int(box[3] * H)
    crop = arr[y0:y1, x0:x1]
    lab = cv2.cvtColor(crop, cv2.COLOR_RGB2LAB).astype(np.float32)
    # Paving colour: the median of the crop's top band and side strips.
    band = np.concatenate([lab[:12].reshape(-1, 3), lab[:, :12].reshape(-1, 3), lab[:, -12:].reshape(-1, 3)])
    ref = np.median(band, axis=0)
    spread = np.percentile(np.linalg.norm(band - ref, axis=1), 90)
    dist = np.linalg.norm(lab - ref, axis=2)
    # Dappled shadows on the paving change lightness, not hue: weigh chroma more than L.
    dchroma = np.linalg.norm(lab[..., 1:] - ref[1:], axis=2)
    paving = ((dchroma < max(9.0, spread * 0.9)) & (np.abs(lab[..., 0] - ref[0]) < 60) & (dist < max(40.0, spread * 2.5)))
    paving = paving.astype(np.uint8)
    h, w = paving.shape
    seeds = np.zeros_like(paving)
    seeds[0, :] = 1
    seeds[:, 0] = 1
    seeds[:, -1] = 1
    n, labels = cv2.connectedComponents(paving, connectivity=4)
    reach = np.unique(labels[(seeds > 0) & (paving > 0)])
    reach = reach[reach > 0]
    background = np.isin(labels, reach)
    obj = (~background).astype(np.uint8)
    # Keep the biggest blob (the bed) and fill its holes.
    n, labels, stats, _ = cv2.connectedComponentsWithStats(obj, connectivity=8)
    if n > 1:
        big = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        obj = (labels == big).astype(np.uint8)
    cnts, _ = cv2.findContours(obj, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    filled = np.zeros_like(obj)
    cv2.drawContours(filled, cnts, -1, 1, thickness=cv2.FILLED)
    alpha = cv2.GaussianBlur(filled.astype(np.float32), (3, 3), 0.7)
    full = np.zeros((H, W), np.float32)
    full[y0:y1, x0:x1] = alpha
    out = np.dstack([arr, (full * 255).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def save_scene(img: Image.Image, base: Path, widths: list[int], q: dict) -> dict:
    base.parent.mkdir(parents=True, exist_ok=True)
    files: dict[str, list] = {"avif": [], "webp": []}
    # WebP is only the fallback for browsers without AVIF (Safari before 16), so it stops at
    # 1920 px wide to keep the repo and the deploy small.
    webp_max = q.get("webpMax", 1920)
    for w in widths:
        w = min(w, img.width)
        h = round(img.height * w / img.width)
        im = img.resize((w, h), Image.LANCZOS) if w != img.width else img
        for ext, kw in (("avif", dict(quality=q.get("avif", 58), speed=4)), ("webp", dict(quality=q.get("webp", 80), method=5))):
            if ext == "webp" and w > webp_max and files["webp"]:
                continue
            path = base.with_name(f"{base.name}-{w}.{ext}")
            im.save(path, **kw)
            files[ext].append([w, "/" + path.relative_to(ROOT / "web/public").as_posix()])
    return files


def hex_of(rgb) -> str:
    return "#%02x%02x%02x" % tuple(int(round(c)) for c in rgb)


def compose_scene(name: str, slot: dict, out_dir: Path, preview: bool) -> dict:
    """Export a scene's Light and Dark images at the page's widths: the full frame for wide
    screens and a centre crop for phones (art direction), plus an optional foreground cut-out
    that sits in front of the phone. Also records the colour along the top and bottom edges so
    the page can blend the sky into the background."""
    entry: dict = {"kind": "scene", "alt": slot.get("alt", "")}
    q = slot.get("quality", {})
    for mode in ("light", "dark"):
        src = slot.get(mode)
        if not src:
            continue
        img = Image.open(ROOT / src).convert("RGB")
        W, H = img.size
        arr = np.asarray(img).astype(np.float32)
        # The sky colour: the middle of the top edge (the corners often have leaves or clouds).
        entry.setdefault("top", {})[mode] = hex_of(arr[: max(2, H // 200), int(W * 0.3):int(W * 0.7)].reshape(-1, 3).mean(axis=0))
        entry.setdefault("bottom", {})[mode] = hex_of(arr[-max(2, H // 200):].reshape(-1, 3).mean(axis=0))
        wide = slot.get("wide", [0, 0, 1, 1])
        crops = {"wide": (wide, slot.get("widths", [1600, 2880]))}
        if slot.get("mobile"):
            crops["mobile"] = (slot["mobile"], slot.get("mobileWidths", [800, 1200]))
        fg_img = foreground_matte(img, slot["foreground"]) if slot.get("foreground") else None
        for crop_name, (c, widths) in crops.items():
            box = (round(c[0] * W), round(c[1] * H), round(c[2] * W), round(c[3] * H))
            im = img.crop(box)
            info = entry.setdefault(crop_name, {"width": im.width, "height": im.height})
            info[mode] = save_scene(im, out_dir / f"{name}-{crop_name}-{mode}", widths, q)
            if fg_img is not None:
                fim = fg_img.crop(box)
                finfo = entry.setdefault("fg", {}).setdefault(crop_name, {"width": fim.width, "height": fim.height})
                finfo[mode] = save_scene(fim, out_dir / f"{name}-fg-{crop_name}-{mode}", widths[:1] + widths[1:], q)
            if preview:
                prev = ROOT / "art/web/review/compose" / f"{name}-{crop_name}-{mode}.jpg"
                prev.parent.mkdir(parents=True, exist_ok=True)
                p_im = im if fg_img is None else Image.alpha_composite(
                    Image.new("RGBA", im.size, (255, 0, 255, 255)), fg_img.crop(box))
                p_im = p_im.convert("RGB")
                p_im.resize((1000, round(p_im.height * 1000 / p_im.width)), Image.LANCZOS).save(prev, quality=82)
        print(f"{name}-{mode}: {W}x{H}")
    return entry


# ----------------------------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------------------------

def trim(img: Image.Image, pad: int = 4) -> Image.Image:
    bbox = img.getchannel("A").point(lambda v: 255 if v > 2 else 0).getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    return img.crop((max(0, l - pad), max(0, t - pad), min(img.width, r + pad), min(img.height, b + pad)))


def save_variants(img: Image.Image, base: Path, width: int) -> dict:
    base.parent.mkdir(parents=True, exist_ok=True)
    files = {}
    h1 = None
    widths = {}
    for mult in (1, 2):
        w = min(width * mult, img.width)
        h = round(img.height * w / img.width)
        im = img.resize((w, h), Image.LANCZOS) if w != img.width else img
        widths[mult] = w
        if mult == 1:
            h1 = h
        for ext, kw in (("avif", dict(quality=62, speed=4)), ("webp", dict(quality=84, method=4))):
            p = base.with_name(f"{base.name}-{mult}x.{ext}")
            im.save(p, **kw)
            files[f"{ext}{mult}x"] = "/" + p.relative_to(ROOT / "web/public").as_posix()
    # The page uses width descriptors (srcset 760w, 1520w) with a sizes hint per slot.
    return {"width": widths[1], "height": h1, "width2x": widths[2], "files": files}


def find_shot(screen_id: str, mode: str, dirs: dict) -> tuple[Image.Image, str]:
    """Local art/web/screens/{dark,light}/ first, then the CI folders. Dark falls back to Light."""
    local = ROOT / "art/web/screens"
    order = []
    if mode == "dark":
        order += [(local / "dark", "dark"), (Path(dirs["dark"]), "dark")]
    order += [(local / "light", "light"), (Path(dirs["light"]), "light")]
    for folder, used in order:
        p = folder / f"{screen_id}.png"
        if p.exists():
            return Image.open(p), used
    raise SystemExit(f"screenshot not found: {screen_id} (looked in {', '.join(str(f) for f, _ in order)})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slots", nargs="*")
    ap.add_argument("--light-dir")
    ap.add_argument("--dark-dir")
    ap.add_argument("--preview", action="store_true", help="also write JPEG previews to art/web/review/compose/")
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    dirs = dict(cfg["screenshots"])
    if args.light_dir:
        dirs["light"] = args.light_dir
    if args.dark_dir:
        dirs["dark"] = args.dark_dir
    out_dir = ROOT / cfg["output"]
    manifest_path = ROOT / cfg["manifest"]
    manifest = {}
    if manifest_path.exists():
        txt = manifest_path.read_text(encoding="utf-8")
        start = txt.find("{")
        end = txt.rfind("}")
        try:
            manifest = json.loads(txt[start:end + 1])
        except json.JSONDecodeError:
            manifest = {}

    # Drop entries for slots that no longer exist.
    manifest = {k: v for k, v in manifest.items() if k in cfg["slots"]}
    wanted = args.slots or list(cfg["slots"].keys())
    presets = cfg.get("lights", {})
    for name in wanted:
        slot = cfg["slots"][name]
        kind = slot["kind"]
        if kind == "scene":
            manifest[name] = compose_scene(name, slot, out_dir, args.preview)
            continue
        entry = {"alt": slot.get("alt", "")}
        screen_id = slot.get("screen")
        modes = ["light", "dark"] if screen_id else [None]
        for mode in modes:
            shot, used = (find_shot(screen_id, mode, dirs) if screen_id else (None, None))
            if kind == "art":
                img = compose_art(slot, shot)
            elif kind == "iphone":
                lit = slot.get("lighting")
                lit = lit.get(mode or "light") if isinstance(lit, dict) else lit
                img = render_iphone(slot, shot, lighting(lit, presets))
            else:
                raise SystemExit(f"unknown kind {kind}")
            if slot.get("trim", kind == "iphone"):
                img = trim(img)
            suffix = f"-{mode}" if mode else ""
            info = save_variants(img, out_dir / f"{name}{suffix}", slot["width"])
            if args.preview:
                prev = ROOT / "art/web/review/compose" / f"{name}{suffix}.jpg"
                prev.parent.mkdir(parents=True, exist_ok=True)
                bg_col = slot.get("previewBg", {}).get(mode or "light") if slot.get("previewBg") else None
                bg = Image.new("RGBA", img.size, tuple(bg_col or (211, 36, 52)) + (255,))
                bg.alpha_composite(img)
                rgb = bg.convert("RGB")
                if rgb.width > 1000:
                    rgb = rgb.resize((1000, round(rgb.height * 1000 / rgb.width)), Image.LANCZOS)
                rgb.save(prev, quality=82)
            entry["width"], entry["height"], entry["width2x"] = info["width"], info["height"], info["width2x"]
            entry[mode or "image"] = info["files"]
            if mode:
                entry[f"{mode}Source"] = f"{screen_id} ({used})"
            print(f"{name}{suffix}: {info['width']}x{info['height']} ({used or 'no screen'})")
        manifest[name] = entry

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(dict(sorted(manifest.items())), indent=2)
    manifest_path.write_text(
        "// Written by scripts/web-compose.py from art/web/screens.json. Don't edit by hand.\n"
        "export const art = " + body + " as const;\n\nexport type ArtSlot = keyof typeof art;\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    sys.exit(main())
