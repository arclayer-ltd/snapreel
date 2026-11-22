"""Video loops for the site's illustrated scenes (web/components/marketing/scene-video.tsx).

Each scene picture in art/web/gen2/ (Light and Dusk) was animated by an image-to-video model with the
picture as both its first and its last frame (MiniMax H3, 2K, 8 s; prompts and job IDs in
art/web/credits.md). This script turns those raw clips into the files the page plays:

- resampled to the picture's exact shape (the hero is 3:2 and went to the model stretched to 16:9, so
  it is squeezed back here) and matched to the still's average colour, so the video fades in over the
  picture without a shift;
- made seamless: the last LOOP_BLEND frames are blended into the first ones and the clip is shortened
  by as many, so the end runs straight into the start (the generator eases into its last frame, so the
  loop has a short calm before the breeze picks up again);
- cut like the pictures (art/web/screens.json): the wide frame, the phone crop (`mobile`; a scene
  without one is shown whole on phones, at phone size) and every spot cut from the same picture;
- encoded as H.264 MP4 and AV1 MP4 (kept only where clearly smaller), muted;
- listed in web/components/marketing/video-manifest.ts, with the foreground cut-out's box (the hero's
  front flower bed, which the page redraws from the video in front of the phone).

usage:
    python scripts/web-scene-video.py <folder with the raw clips>             # everything (about 30 min)
    python scripts/web-scene-video.py <folder> scene-hero spot-record         # some slots
    python scripts/web-scene-video.py --encode-only [slots]                   # re-encode the kept masters

Every clip is one keyframe followed by predicted frames: at these bitrates a keyframe comes out sharper than
the frames before it, which showed as a pulse every few seconds and at the loop seam with the usual GOP.
The lossless masters (FFV1, about 5 GB) are kept for --encode-only in $WEB_SCENE_VIDEO_TMP, or the system
temp folder's web-scene-video/.

The raw clips are named after the picture they animate (hero-light.mp4, pro-dark.mp4, ...). They are not
in the repo (about 8 MB each); download them again from the job IDs in art/web/credits.md.
"""
import json
import os
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SCREENS = json.loads((ROOT / "art/web/screens.json").read_text(encoding="utf8"))
OUT = ROOT / "web/public/marketing/video"
MANIFEST = ROOT / "web/components/marketing/video-manifest.ts"
URL = "/marketing/video"

FPS = 24
LOOP_BLEND = 14  # frames blended across the seam (spreads out the generator's settle into its last frame)
WIDTH = {"wide": 1920, "mobile": 720, "phone-full": 960, "spot": 480}
# Picked by eye on the hero at 100 %: the generated frames are soft, so these look the same as far
# lower settings; AV1 at these is about a quarter smaller than H.264.
H264_CRF = {"wide": 32, "mobile": 32, "phone-full": 32, "spot": 31}
AV1_CRF = {"wide": 55, "mobile": 52, "phone-full": 52, "spot": 50}
GOP = FPS * 10  # longer than any clip: one keyframe, no pulse
TMP = Path(os.environ.get("WEB_SCENE_VIDEO_TMP") or Path(tempfile.gettempdir()) / "web-scene-video")


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
    subprocess.run(common + ["-c:v", "libx264", "-preset", "slow", "-crf", str(H264_CRF[kind]), "-profile:v", "high",
                             "-x264-params", "scenecut=0", str(h264_file)], check=True)
    subprocess.run(common + ["-c:v", "libsvtav1", "-preset", "6", "-crf", str(AV1_CRF[kind]),
                             "-svtav1-params", "tune=0:scd=0", str(av1_file)], check=True, stderr=subprocess.DEVNULL)
    h264, av1 = h264_file.stat().st_size, av1_file.stat().st_size
    print(f"    {name}: {meta['w']}x{meta['h']}  h264 {h264 / 1e6:.2f} MB  av1 {av1 / 1e6:.2f} MB", flush=True)
    entry = {"w": meta["w"], "h": meta["h"], "h264": f"{URL}/{h264_file.name}"}
    if av1 < h264 * 0.85:
        entry["av1"] = f"{URL}/{av1_file.name}"
    else:
        av1_file.unlink()
    return entry


def render(src_img: Path, raw: Path, make_sinks):
    """Resample, colour-match and loop the raw clip, feeding every frame to the sinks."""
    still = cv2.cvtColor(cv2.imread(str(src_img), cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    sh, sw = still.shape[:2]
    w, h = probe(raw)
    ar = sw / sh
    # The picture's shape at the clip's resolution: squeezed across (the hero) or a hair shorter.
    tw, th = (round(h * ar), h) if w / h > ar else (w, round(w / ar))

    def fit(f):
        return cv2.resize(f, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)

    # Pass 1: the first frame, the frame count and the last frames.
    first, n, tail = None, 0, deque(maxlen=LOOP_BLEND + 1)
    for f in frames_of(raw):
        if first is None:
            first = fit(f)
        tail.append(f)
        n += 1
    tail = [fit(f) for f in tail]
    if np.abs(tail[-1] - first).mean() < 1.0:  # the generator repeated the first frame at the end
        n -= 1
        tail = tail[:-1]
    else:
        tail = tail[1:]
    ref = cv2.resize(still, (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32)
    gain = ref.reshape(-1, 3).mean(0) / np.maximum(first.reshape(-1, 3).mean(0), 1)
    k = LOOP_BLEND
    length = n - k
    print(f"  {raw.name}: {w}x{h} {n} frames -> {tw}x{th} {length} frames, gain {np.round(gain, 3).tolist()}, "
          f"first/last {np.abs(tail[-1] - first).mean():.2f}")

    sinks = make_sinks((th, tw))
    # Pass 2: frame j < k is the tail's frame j blended into frame j; the rest as they are.
    seam = []
    for j, f in enumerate(frames_of(raw)):
        if j >= length:
            break
        g = fit(f)
        if j < k:
            a = (j + 1) / (k + 1)
            g = tail[j] * (1 - a) + g * a
        g = np.clip(g * gain, 0, 255)
        if j in (0, 1, length - 1):
            seam.append(g)
        for s in sinks:
            s.write(g)
    print(f"  seam {np.abs(seam[2] - seam[0]).mean():.2f} vs step {np.abs(seam[1] - seam[0]).mean():.2f}", flush=True)
    for sink in sinks:
        sink.close()


encode_only = sys.argv[1] == "--encode-only"
raw_dir = None if encode_only else Path(sys.argv[1])
only = set(sys.argv[2:])
slots = SCREENS["slots"]

manifest = {}
if MANIFEST.exists() and only:
    text = MANIFEST.read_text(encoding="utf8")
    manifest = json.loads(text[text.index("= ") + 2: text.rindex(" as const")])

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
        names = {}
        if slot in wanted:
            names[f"{slot}-wide-{theme}"] = ("wide", None)
            names[f"{slot}-mobile-{theme}"] = ("mobile", cfg["mobile"]) if "mobile" in cfg else ("phone-full", None)
        for spot, scfg in spots.items():
            if spot in wanted:
                names[f"{spot}-{theme}"] = ("spot", scfg["wide"])
        if not encode_only:
            render(src, raw_dir / f"{src.stem}.mp4", lambda shape: [Sink(n, k, b, shape) for n, (k, b) in names.items()])
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
