"""Re-cut the welcome walk from build 1's clip (welcome_v1.mp4, 136 frames at 30 fps).

The source repeats frames in an uneven 2-3 pattern (about 18 distinct pictures a second), eases
in and out of its keyframe, slows down mid-walk, and snaps to the keyframe on its last frame.
This keeps the second walk (distinct frames 55..121, 0-based), bridges 121 -> 55 with one
optical-flow in-between instead of the snap, and retimes the whole loop to constant speed:
each output frame shows the distinct frame whose cumulative movement matches that moment.
Usage: welcome_recut.py <full frames dir f_NNN.png (1-based)> <seam dir with m_04> <out dir>
"""
import glob
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

full, seam, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)


def load(path):
    return Image.open(path).convert('RGB')


frames = {i: load(f'{full}/f_{i + 1:03d}.png') for i in range(136)}
small = {}


def diff(a, b):
    return ImageStat.Stat(ImageChops.difference(a.convert('L').resize((320, 240)),
                                                b.convert('L').resize((320, 240)))).mean[0]


# Distinct frames of the second walk.
seq = [55]
for i in range(56, 124):
    if diff(frames[i], frames[seq[-1]]) > 0.6:
        seq.append(i)
# One optical-flow in-between halfway from 121 back to 55 replaces the snap.
seq = [i for i in seq if i <= 121]
pictures = [frames[i] for i in seq] + [load(f'{seam}/m_04.png')]
labels = [str(i) for i in seq] + ['bridge']

# Drop pictures where the walk crawls (eases and the mid-walk slowdown) so every step is a
# similar size, then hold each kept picture exactly two frames: an even 15 pictures a second.
kept = [0]
for k in range(1, len(pictures)):
    if k >= len(pictures) - 1 or diff(pictures[k], pictures[kept[-1]]) >= 3.6:
        kept.append(k)
steps = [diff(pictures[kept[i]], pictures[kept[(i + 1) % len(kept)]]) for i in range(len(kept))]
print('kept', len(kept), [labels[k] for k in kept])
print('steps', [round(x, 1) for x in steps])
n = 0
for k in kept:
    for _ in range(2):
        n += 1
        pictures[k].save(f'{out}/o_{n:03d}.png')
print('frames', n, 'seconds', round(n / 30, 2))
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', '30', '-i', f'{out}/o_%03d.png',
                '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-preset', 'slow',
                '-crf', '18', '-tune', 'animation', '-an', '-movflags', '+faststart',
                f'{out}/char_welcome.mp4'], check=True)
print('done')
