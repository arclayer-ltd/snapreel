"""Cut a seamless character loop from a generated clip.

Finds no cut points itself: pass the first frame and the frame that matches it one or more
walk cycles later (compare frames with a mean absolute difference; a match is well under the
size of a normal step between neighbours). Plays first..match-1, drops the frames the generator
repeated (difference from the previous kept frame <= 0.6 on a 320 px greyscale copy) so the pace
stays even, and encodes at 24 fps, 960x720, like the other character clips.

The welcome walk (build 25): Seedance 2.5, 720p, 5 s, first frame art/characters/welcome.png;
frame 19 matches frame 99 (two walk cycles), so:
    python scripts/loop_from_cycle.py raw.mp4 19 99 Snapreel/Resources/Characters/char_welcome.mp4
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageStat

raw, first, match, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]

with tempfile.TemporaryDirectory() as work:
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', raw, f'{work}/f_%04d.png'], check=True)

    def frame(i):
        return f'{work}/f_{i + 1:04d}.png'

    def small(i):
        return Image.open(frame(i)).convert('L').resize((320, 240))

    def diff(a, b):
        return ImageStat.Stat(ImageChops.difference(a, b)).mean[0]

    keep = [first]
    last = small(first)
    for i in range(first + 1, match):
        image = small(i)
        if diff(image, last) > 0.6:
            keep.append(i)
            last = image
    seam = diff(small(keep[-1]), small(first))
    print(f'kept {len(keep)} of {match - first} frames; loop point step {seam:.2f}')

    os.makedirs(f'{work}/loop')
    for n, i in enumerate(keep):
        os.replace(frame(i), f'{work}/loop/o_{n + 1:04d}.png')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', '24', '-i', f'{work}/loop/o_%04d.png',
                    '-vf', 'scale=960:720:flags=lanczos', '-c:v', 'libx264', '-profile:v', 'high',
                    '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', '18', '-tune', 'animation', '-an',
                    '-movflags', '+faststart', out], check=True)
print('done')
