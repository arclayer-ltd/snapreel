#!/usr/bin/env python3
"""Turn the simulator recordings of the app's flows into the looping videos on snapreel.video's iPhones.

The recordings come from the iOS workflow (`gh workflow run ios.yml -f screenshots=false -f flows=flow.`,
then `gh run download <run> -n snapreel-ci`): ci-out/flows/{light,dark}/flow.<name>.mp4, the real app driven
by Debug/DebugFlows.swift on a 375 x 812 pt simulator, recorded from just before the app launches.

    python scripts/web-flows.py <downloaded snapreel-ci folder>

For each flow and mode this writes
    web/public/marketing/flows/<name>-<mode>.mp4   600 px wide H.264, muted, ending in a short crossfade back
                                                   to its first frame so the loop has no jump
    art/web/screens/<mode>/flow.<name>.png         one full-size frame, the still the page shows first, with
                                                   reduced motion, and under the video while it loads
Then run scripts/web-screens.py to export those stills.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

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


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1])
    flows_dir = src / "flows" if (src / "flows").exists() else src / "ci-out/flows"
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (longest, poster, skip) in FLOWS.items():
        for mode in ("light", "dark"):
            rec = flows_dir / mode / f"flow.{name}.mp4"
            if not rec.exists():
                print(f"missing {rec}")
                continue
            start = content_start(rec) + skip
            length = round(min(longest, duration(rec) - start + HOLD), 2)
            end = start + length
            at_poster = poster if poster >= 0 else length - FADE + poster
            # simctl records a frame only when the screen changes: make it 30 fps and hold the last frame.
            cfr = f"fps=30,tpad=stop_mode=clone:stop_duration={length + 2}"
            # The clip, then a crossfade from its end back to its first frame, so `loop` is seamless.
            graph = (
                f"[0:v]{cfr},trim=start={start}:end={end},setpts=PTS-STARTPTS,scale={WIDTH}:-2:flags=lanczos,"
                f"format=yuv420p,split[a][b];"
                f"[b]trim=end_frame=1,loop=loop={int(FADE * 30) + 2}:size=1:start=0,setpts=N/30/TB[first];"
                f"[a][first]xfade=transition=fade:duration={FADE}:offset={length - FADE:.2f},format=yuv420p[v]"
            )
            out = OUT / f"{name}-{mode}.mp4"
            run(["ffmpeg", "-v", "error", "-y", "-i", str(rec), "-filter_complex", graph, "-map", "[v]", "-an",
                 "-c:v", "libx264", "-profile:v", "high", "-crf", "27", "-preset", "slow", "-movflags", "+faststart",
                 str(out)])
            still = STILLS / mode / f"flow.{name}.png"
            at = start + at_poster
            run(["ffmpeg", "-v", "error", "-y", "-i", str(rec), "-vf", f"{cfr},trim=start={at}:end={at + 0.2}",
                 "-frames:v", "1", "-update", "1", str(still)])
            # The simulator records 1124 px wide; the screens pipeline expects the screenshot size.
            Image.open(still).convert("RGB").resize(SCREEN, Image.LANCZOS).save(still)
            print(f"{out.name}  {out.stat().st_size // 1024} KB  start {start:.2f}s  length {length:.2f}s")


if __name__ == "__main__":
    main()
