"""Builds blind comparison folders for one round.

Usage: python -I scripts/compare_prep.py <screenshots-dir> <round-number> [--only id1,id2]

For every screen pair (Snapreel debug id <-> Loom reference) it writes
  refs/compare/round-<n>/screens/<pair>/image-1.png, image-2.png   (random order, same size)
and for every flow with a Snapreel counterpart
  refs/compare/round-<n>/flows/<flow>/strip-1.png, strip-2.png     (random order, same size)
plus refs/compare/round-<n>/key.json (which image is which; never shown to judges).
Steps a flow marks None (server-only on the reference side) are dropped from both strips.
"""
import json
import os
import random
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 750, 1624  # 375x812 pt at 2x

# Snapreel debug id -> reference id (Mobbin prefix or appstore-0N). One judge per pair.
PAIRS = {
    "start.splash": "f475b086",
    "start.welcome": "0ce2a2f6",
    "start.intro.1": "0ce2a2f6", "start.intro.2": "38ff4bf6", "start.intro.3": "8b5b84cc",
    "start.use": "3812ca86", "start.use.selected": "9520b8b2",
    "start.tour.intro": "19689a04", "start.tour.1": "8cf23f32", "start.tour.3": "55a17d4d",
    "start.tour.4": "6ad134c1", "start.tour.permission": "83ffab4c",
    "home.filled": "appstore-01", "home.empty": "79dd23c0",
    "home.history": "4836687a", "home.history.empty": "69fec831",
    "rec.shell": "appstore-02", "rec.camera": "appstore-02",
    "rec.primer": "c0ee6731",
    "rec.screen.tutorial.1": "8a4bd556", "rec.screen.tutorial.2": "9873040f", "rec.screen.tutorial.3": "9e42071f",
    "rec.broadcast": "fe567cf9", "rec.broadcast.unavailable": "1245d328",
    "rec.screen.recording": "8f0f7c0f",
    "rec.review": "9bed6b10", "rec.title": "18dfff18", "rec.share": "96967148",
    "lib.videos": "appstore-06", "lib.folders": "8815cad9", "lib.actions": "5c3f6863",
    "video.player": "333244de", "video.details": "appstore-04", "video.pip": "307833f4",
    "video.speed": "5bdf10e6", "video.notes": "08b623c3", "video.transcript.none": "1cf35f2e",
    "video.note.compose": "e835b4d8", "video.note.edit": "20d71ce8", "video.reaction": "b670b4bf",
    "video.actions": "5c3f6863", "video.photos.permission": "7abeda8d", "video.stats": "4ebeb7dc",
    "notif.feed": "appstore-05",
    "search.idle": "2ba59348", "search.typing": "dc34fe74", "search.results": "d9ee7199",
    "settings.root": "74aeb655", "settings.notifications": "be1d5c1e",
    "settings.storage": "3792bec9", "settings.storage.confirm": "0adb4039",
    "help.home": "f9c3e1f6", "help.article": "5b3089b4",
    "legal.menu": "35a24f63", "legal.terms": "d2910d61", "legal.privacy": "dc86d237", "legal.ack": "939b73c4",
}


def ref_path(ref):
    if ref.startswith("appstore-"):
        return os.path.join(ROOT, "refs", "appstore", ref + ".png")
    folder = os.path.join(ROOT, "refs", "mobbin", "screens")
    for name in os.listdir(folder):
        if name.startswith(ref):
            return os.path.join(folder, name)
    raise FileNotFoundError(ref)


def load(path):
    im = Image.open(path).convert("RGB")
    # App Store marketing shots have a headline above a device frame; keep them whole but
    # letterbox to the phone aspect so both images share a size.
    if abs(im.width / im.height - W / H) > 0.03:
        canvas = Image.new("RGB", (W, H), (255, 255, 255))
        scale = min(W / im.width, H / im.height)
        resized = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
        canvas.paste(resized, ((W - resized.width) // 2, (H - resized.height) // 2))
        return canvas
    return im.resize((W, H), Image.LANCZOS)


def strip(paths, height=812):
    frames = [load(p).resize((int(W * height / H), height), Image.LANCZOS) for p in paths]
    gap = 16
    out = Image.new("RGB", (sum(f.width for f in frames) + gap * (len(frames) - 1), height), (40, 40, 40))
    x = 0
    for f in frames:
        out.paste(f, (x, 0))
        x += f.width + gap
    return out


def main():
    shots, round_no = sys.argv[1], sys.argv[2]
    only = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
    base = os.path.join(ROOT, "refs", "compare", f"round-{round_no}")
    key = {"screens": {}, "flows": {}, "missing": []}
    rng = random.Random(f"snapreel-{round_no}")
    for sid, ref in PAIRS.items():
        if only and sid not in only:
            continue
        mine = os.path.join(shots, sid + ".png")
        if not os.path.exists(mine):
            key["missing"].append(sid)
            continue
        folder = os.path.join(base, "screens", sid.replace(".", "_"))
        os.makedirs(folder, exist_ok=True)
        order = [("snapreel", mine), ("reference", ref_path(ref))]
        rng.shuffle(order)
        for i, (who, path) in enumerate(order, 1):
            load(path).save(os.path.join(folder, f"image-{i}.png"))
        key["screens"][sid] = {"reference": ref, "image-1": order[0][0], "image-2": order[1][0]}

    index = json.load(open(os.path.join(ROOT, "refs", "index.json"), encoding="utf-8"))
    flows = json.load(open(os.path.join(ROOT, "refs", "mobbin", "flows.json"), encoding="utf-8"))
    by_slug = {}
    for i, flow in enumerate(flows, 1):
        slug = f"{i:02d}-" + flow["name"].lower().replace("&", "and").replace(",", "").replace(" ", "-")
        by_slug[slug] = flow
    for slug, data in index["flows"].items():
        if only:
            continue
        flow = next((f for s, f in by_slug.items() if s.startswith(slug[:3])), None)
        if not flow:
            key["missing"].append("flow " + slug)
            continue
        ref_steps = [s for s in sorted(flow["screens"], key=lambda s: s["position"])]
        mine_steps = data["snapreel"]
        pairs = [(r, m) for r, m in zip(ref_steps, mine_steps) if m is not None]
        mine_paths = [os.path.join(shots, m + ".png") for _, m in pairs]
        if not all(os.path.exists(p) for p in mine_paths):
            key["missing"].append("flow " + slug + ": " + ",".join(m for _, m in pairs if not os.path.exists(os.path.join(shots, m + ".png"))))
            continue
        ref_paths = [os.path.join(ROOT, "refs", "mobbin", "screens", r["screen_id"] + ".png") for r, _ in pairs]
        folder = os.path.join(base, "flows", slug)
        os.makedirs(folder, exist_ok=True)
        order = [("snapreel", mine_paths), ("reference", ref_paths)]
        rng.shuffle(order)
        for i, (who, paths) in enumerate(order, 1):
            strip(paths).save(os.path.join(folder, f"strip-{i}.png"))
        key["flows"][slug] = {"steps": len(pairs), "strip-1": order[0][0], "strip-2": order[1][0],
                              "droppedReferenceSteps": len(ref_steps) - len(pairs)}
    os.makedirs(base, exist_ok=True)
    json.dump(key, open(os.path.join(base, "key.json"), "w", encoding="utf-8"), indent=1)
    print(len(key["screens"]), "screen pairs,", len(key["flows"]), "flows; missing:", key["missing"])


if __name__ == "__main__":
    main()
