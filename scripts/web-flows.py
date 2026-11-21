#!/usr/bin/env python3
"""Turn the simulator recordings of the app's flows into the looping videos on snapreel.video's iPhones.

The recordings come from the iOS workflow (`gh workflow run ios.yml -f screenshots=false -f flows=flow.`,
then `gh run download <run> -n snapreel-ci`): ci-out/flows/{light,dark}/flow.<name>.mp4, the real app driven
by Debug/DebugFlows.swift on a 375 x 812 pt simulator, recorded from just before the app launches.

    python scripts/web-flows.py <downloaded snapreel-ci folder>                # every flow, Light and Dark
    python scripts/web-flows.py <downloaded snapreel-ci folder> camera dark    # or some

For each flow and mode this writes
    web/public/marketing/flows/<name>-<mode>.mp4   600 px wide H.264, muted, ending in a short crossfade back
                                                   to its first frame so the loop has no jump
    art/web/screens/<mode>/flow.<name>.png         one full-size frame, the still the page shows first, with
                                                   reduced motion, and under the video while it loads
Then run scripts/web-screens.py to export those stills.

Two fixes on the way, so the phones look like a real iPhone 16 Pro:
- Every video is fitted to the site's frame (scripts/web_island.py): content moves 12 pt down to clear the
  Dynamic Island. The stills are fitted later, by web-screens.py.
- Camera mode: the simulator has no camera, so the app's Debug build shows a still photo
  (Snapreel/Debug/fixture-camera-portrait.jpg) and the preview never moves. On a real iPhone it is live video,
  so the camera flow gets a short talking clip of the same person (art/web/flows/camera-live.mp4, made from that
  photo with Higgsfield Grok Video 1.5) under the app's own overlays: each frame's overlay (the timer, the
  buttons, the dim and the 3-2-1 of the countdown) is recovered against the still and laid over the clip.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from web_island import fit_filter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web/public/marketing/flows"
STILLS = ROOT / "art/web/screens"

# name: (longest length, poster, skip). The clip starts `skip` seconds after the app's screen first shows
# (after the launch splash; the player needs a moment before its first video frame) and runs to the
# recording's last change plus HOLD seconds, at most "longest length". The poster (the still the page shows
# first and under the video) is that many seconds into the clip; a negative value counts from its end.
FLOWS: dict[str, tuple[float, float, float]] = {
    "share": (11.0, -0.5, 0.8),
    "comments": (8.0, 3.0, 0.8),
    "camera": (9.0, -0.5, 0.1),
    "voice": (9.0, -0.5, 0.1),
    "screen": (9.0, 0.6, 0.1),
}
HOLD = 1.6
# x264 quality per flow (lower is better and bigger). The live camera clip moves everywhere, so it is coded a
# little harder to stay near the size of the others.
CRF = {"camera": "31"}
WIDTH = 600
FADE = 0.45
SCREEN = (1125, 2436)


def content_start(rec: Path) -> float:
    """Seconds into the recording when the app's screen first shows: the home screen (busy), then the
    launch splash (one flat colour), then the screen (busy again)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(rec), "-vf", "fps=20,scale=60:130,format=gray",
                          "-f", "rawvideo", "-"], check=True, capture_output=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, 130, 60)[:, 12:, :].astype(np.float32)
    busy = frames.std(axis=(1, 2)) > 12
    flat = np.where(~busy)[0]
    if not len(flat):
        return 0.0
    after = np.where(busy[flat[0]:])[0]
    return (flat[0] + after[0]) / 20 if len(after) else 0.0


def duration(rec: Path) -> float:
    return float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                 str(rec)], check=True, capture_output=True, text=True).stdout.strip())


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def size(rec: Path) -> tuple[int, int]:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", str(rec)], check=True, capture_output=True, text=True).stdout
    w, h = out.strip().split(",")[:2]
    return int(w), int(h)


# --- Camera mode: a live preview ---------------------------------------------------------------------

LIVE_CLIP = ROOT / "art/web/flows/camera-live.mp4"
LIVE_STILL = ROOT / "Snapreel/Debug/fixture-camera-portrait.jpg"


def live_camera(rec: Path, out: Path) -> Path:
    """The camera recording with its still preview replaced by the talking clip, as a near-lossless video."""
    w, h = size(rec)
    still = np.asarray(Image.open(LIVE_STILL).convert("RGB"))
    decode = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(rec), "-vf", "fps=30", "-f", "rawvideo",
                               "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    encode = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                               "-r", "30", "-i", "-", "-c:v", "libx264", "-crf", "8", "-preset", "ultrafast",
                               "-pix_fmt", "yuv444p", str(out)], stdin=subprocess.PIPE)
    clip_raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(LIVE_CLIP), "-vf", "fps=30", "-f", "rawvideo",
                               "-pix_fmt", "rgb24", "-"], check=True, capture_output=True).stdout
    cw, ch = size(LIVE_CLIP)
    clip = np.frombuffer(clip_raw, np.uint8).reshape(-1, ch, cw, 3)
    # Forward, then back, so the clip never jumps.
    order = list(range(len(clip))) + list(range(len(clip) - 2, 0, -1))

    rect = warp = warp_clip = corners = placed = None
    live = 0
    seen = 0
    n = w * h * 3
    while True:
        buf = decode.stdout.read(n)
        if len(buf) < n:
            break
        frame = np.frombuffer(buf, np.uint8).reshape(h, w, 3)
        seen += 1
        # Looking for the preview is slow (SIFT), so only every half second until it is found.
        if rect is None and seen % 15 == 0:
            rect, warp, corners = _find_preview(frame, still)
            if rect is not None:
                # The clip has the still's shape, so it goes where the still goes.
                warp_clip = warp.copy()
                warp_clip[:, :2] *= still.shape[1] / cw
                bw, bh = rect[2] - rect[0], rect[3] - rect[1]
                placed = cv2.warpAffine(still, warp, (bw, bh), flags=cv2.INTER_AREA).astype(np.float32)
        if rect is not None:
            new = _relive(frame, rect, placed, warp_clip, corners, clip[order[live % len(order)]])
            if new is not None:
                frame = new
                live += 1
        encode.stdin.write(np.ascontiguousarray(frame).tobytes())
    encode.stdin.close()
    encode.wait()
    decode.wait()
    print(f"  live camera: {live} frames")
    return out


def _find_preview(frame: np.ndarray, still: np.ndarray):
    """Where the app draws the still: the preview box and the still's placement in it (SIFT), or Nones."""
    h, w = frame.shape[:2]
    bg = frame[h - 136, 30].astype(int)
    away = np.abs(frame.astype(int) - bg).max(-1) > 30
    rows = np.where(away[:, w // 2])[0]
    rows = rows[(rows > h * 0.05) & (rows < h * 0.8)]
    if len(rows) < h * 0.4:
        return None, None, None
    y0, y1 = int(rows.min()), int(rows.max()) + 1
    cols = np.where(away[(y0 + y1) // 2 + 300])[0]
    if not len(cols):
        return None, None, None
    x0, x1 = int(cols.min()), int(cols.max()) + 1
    box = np.ascontiguousarray(frame[y0:y1, x0:x1])
    sift = cv2.SIFT_create(4000)
    k1, d1 = sift.detectAndCompute(cv2.cvtColor(still, cv2.COLOR_RGB2GRAY), None)
    k2, d2 = sift.detectAndCompute(cv2.cvtColor(box, cv2.COLOR_RGB2GRAY), None)
    if d1 is None or d2 is None:
        return None, None, None
    good = [a for a, b in cv2.BFMatcher().knnMatch(d1, d2, k=2) if a.distance < 0.7 * b.distance]
    if len(good) < 200:
        return None, None, None
    p1 = np.float32([k1[a.queryIdx].pt for a in good])
    p2 = np.float32([k2[a.trainIdx].pt for a in good])
    warp, _ = cv2.estimateAffinePartial2D(p1, p2, method=cv2.RANSAC, ransacReprojThreshold=2)
    # The rounded corners: the screen's background inside the box.
    corners = np.abs(box.astype(int) - bg).max(-1) < 10
    edge = np.zeros_like(corners)
    r = 90
    for sy in (slice(0, r), slice(-r, None)):
        for sx in (slice(0, r), slice(-r, None)):
            edge[sy, sx] = True
    print(f"  preview {x0},{y0} {x1 - x0}x{y1 - y0}, still x{warp[0, 0]:.3f}, {len(good)} matches")
    return (x0, y0, x1, y1), warp, corners & edge


def _relive(frame, rect, s, warp_clip, corners, clip_frame):
    """One frame: recover the app's overlay over the still (s, already placed in the preview box), then lay it
    over the clip. None if the still isn't showing in this frame (the launch, the home screen)."""
    x0, y0, x1, y1 = rect
    bw, bh = x1 - x0, y1 - y0
    c = frame[y0:y1, x0:x1].astype(np.float32)
    probe = (slice(bh * 6 // 10, bh * 9 // 10), slice(bw // 5, bw * 4 // 5))  # the sweater: no overlays there
    ratio = float(np.median(c[probe] / np.maximum(s[probe], 1)))
    if not 0.3 < ratio < 1.3 or float(np.abs(c[probe] - ratio * s[probe]).mean()) > 14:
        return None
    base = ratio * s
    v = ratio * cv2.warpAffine(clip_frame, warp_clip, (bw, bh), flags=cv2.INTER_CUBIC).astype(np.float32)
    d = c - base
    up = np.clip(d / np.maximum(255 - base, 1), 0, 1)
    down = np.clip(-d / np.maximum(base, 1), 0, 1)
    quiet = np.abs(d) < 7  # compression noise, not an overlay
    up[quiet] = 0
    down[quiet] = 0
    out = v + up * (255 - v) - down * v
    out[corners] = c[corners]
    new = frame.copy()
    new[y0:y1, x0:x1] = np.clip(out, 0, 255).astype(np.uint8)
    return new


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1])
    only = sys.argv[2:]  # optional: flow names and/or modes, e.g. `camera dark`
    flows_dir = src / "flows" if (src / "flows").exists() else src / "ci-out/flows"
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (longest, poster, skip) in FLOWS.items():
        for mode in ("light", "dark"):
            names = [a for a in only if a in FLOWS]
            modes = [a for a in only if a in ("light", "dark")]
            if (names and name not in names) or (modes and mode not in modes):
                continue
            rec = flows_dir / mode / f"flow.{name}.mp4"
            if not rec.exists():
                print(f"missing {rec}")
                continue
            if name == "camera" and LIVE_CLIP.exists():
                rec = live_camera(rec, LIVE_CLIP.parent / f".live-{mode}.mp4")
            start = content_start(rec) + skip
            length = round(min(longest, duration(rec) - start + HOLD), 2)
            end = start + length
            at_poster = poster if poster >= 0 else length - FADE + poster
            # simctl records a frame only when the screen changes: make it 30 fps and hold the last frame.
            cfr = f"fps=30,tpad=stop_mode=clone:stop_duration={length + 2}"
            # The clip, then a crossfade from its end back to its first frame, so `loop` is seamless.
            w, h = size(rec)
            graph = (
                f"[0:v]{cfr},trim=start={start}:end={end},setpts=PTS-STARTPTS[t0];"
                + fit_filter(w, h, "t0", "t1")
                + f";[t1]scale={WIDTH}:-2:flags=lanczos,format=yuv420p,split[a][b];"
                f"[b]trim=end_frame=1,loop=loop={int(FADE * 30) + 2}:size=1:start=0,setpts=N/30/TB[first];"
                f"[a][first]xfade=transition=fade:duration={FADE}:offset={length - FADE:.2f},format=yuv420p[v]"
            )
            out = OUT / f"{name}-{mode}.mp4"
            run(["ffmpeg", "-v", "error", "-y", "-i", str(rec), "-filter_complex", graph, "-map", "[v]", "-an",
                 "-c:v", "libx264", "-profile:v", "high", "-crf", CRF.get(name, "27"), "-preset", "slow", "-movflags", "+faststart",
                 str(out)])
            still = STILLS / mode / f"flow.{name}.png"
            at = start + at_poster
            run(["ffmpeg", "-v", "error", "-y", "-i", str(rec), "-vf", f"{cfr},trim=start={at}:end={at + 0.2}",
                 "-frames:v", "1", "-update", "1", str(still)])
            # The simulator records 1124 px wide; the screens pipeline expects the screenshot size.
            Image.open(still).convert("RGB").resize(SCREEN, Image.LANCZOS).save(still)
            print(f"{out.name}  {out.stat().st_size // 1024} KB  start {start:.2f}s  length {length:.2f}s")
            if rec.name.startswith(".live-"):
                rec.unlink()


if __name__ == "__main__":
    main()
