#!/usr/bin/env python3
"""What the depth fade did to each body and to the background, from the 70-*
pose-matched stills of GraphPreviewUITests.testDepthBeforeAfter.

    tools/depth_crops.py <dir>        analyse every on/off pair under <dir>
    tools/depth_crops.py --self-test  check the arithmetic on synthetic pictures

Needs python3-numpy and python3-pil (apt-get install -y python3-numpy python3-pil).

Where the files come from. The "Design preview" workflow exports a test run's
attachments with `xcresulttool export attachments` and names each after its
attachment (name_shots.py, .github/workflows/design-preview.yml, "Save the
pictures", lines 256-287): a name is cut at its first "_" (the exporter's
human-readable names look like <name>_<n>_<UUID>.<ext>), 3D map tests get
"graph-" in front, a name already taken gets "-2", "-3" ... before its
extension, and each file goes to shots/iphone/ or shots/ipad/ on the shots
branch. So the stills are graph-70-<theme>-<tier>-<view>-<on|off>.png and the
frames are graph-75-body-frames.txt (a text attachment exports as .txt; .json
is read too). This script takes any directory (it looks below it too, one
device's folder at a time), tolerates the "graph-" prefix, a "-N" suffix (the
file without one wins) and a raw "_<n>_<UUID>" tail, and reads the frames file
in the same folder as the stills.

The frames file (75-body-frames), all in points:
  {"stills": {"70-space-high-whole-on": {"size": [w, h], "meter": [x, y, w, h],
    "line": "<meter text>", "bodies": [[x, y, 44, 44], ...]}, ...}}
scale = the picture's pixel width / size[0].

Per pair it prints
  <pair>: far <r1> <r2> <r3> near <r1> <r2> <r3> patch Δ <value> (<n> patches)
- A body's brightness is the mean grey (mean of R, G, B; 0-255) of its 44-point
  square minus the median grey of the ring 64-80 points from its centre
  (Euclidean distance) in the OFF still: the same background reference for on
  and off. Ratio = on brightness / off brightness for the same body (the on
  still's body nearest the off one's centre, within 22 points).
- far = the 3 bodies of the off still with the least midY (listed top first),
  near = the 3 with the greatest midY (listed bottom first). "n/a" for a body
  with no match in the on still, a square that meets the meter's frame (its
  text differs between on and off), or an off brightness of 0.5 or less (not
  brighter than its surroundings: no ratio).
- Background patches: 32-pixel squares on a 32-pixel grid where the off
  still's grey standard deviation (population) is under 2 grey levels, that
  keep 40 points from every body square (of either still) and stay outside the
  meter's frame. Patch Δ = the mean over them of (on mean - off mean), in grey
  levels. A pair with fewer than 5 gets a FAIL line.
Exit 0 if every pair was read, 1 if not (a missing still or entry, too few
patches), 2 on a usage error.
"""
import argparse
import contextlib
import io
import json
import math
import os
import re
import shutil
import sys
import tempfile

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("depth_crops.py needs python3-numpy and python3-pil (apt-get install -y python3-numpy python3-pil)")

BODY = 44.0          # a body's square, points
RING = (64.0, 80.0)  # the background reference's ring round a body, points
PATCH = 32           # a background patch, pixels
FLAT = 2.0           # a flat patch: grey standard deviation under this (2/255 of the range)
KEEP = 40.0          # a patch keeps this far from every body square, points
MATCH = 22.0         # on and off bodies are the same within this, points
NEED = 5             # background patches a pair needs
MIN_OFF = 0.5        # an off brightness at or under this gives no ratio

STILL = re.compile(r"^(?:graph-)?(?P<pair>70-.+?)-(?P<mode>on|off)(?:-(?P<n>\d+))?(?:_[^/]*)?\.png$")
FRAMES = re.compile(r"^(?:graph-)?75-body-frames(?:-(?P<n>\d+))?(?:_[^/]*)?\.(?:txt|json)$")


# ---- reading the pictures

def grey(path):
    """The picture as a float array of grey levels (mean of R, G, B), rows down."""
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.float64).mean(axis=2)


def centres(record):
    return [(b[0] + b[2] / 2.0, b[1] + b[3] / 2.0) for b in record.get("bodies", [])]


def rect_of(cx, cy, half=BODY / 2.0):
    return (cx - half, cy - half, cx + half, cy + half)


def meter_rect(record):
    m = record.get("meter") or [0, 0, 0, 0]
    return (m[0], m[1], m[0] + m[2], m[1] + m[3]) if m[2] > 0 and m[3] > 0 else None


def gap(a, b):
    """Euclidean distance between two (x0, y0, x1, y1) rectangles, 0 if they meet."""
    dx = max(a[0] - b[2], b[0] - a[2], 0.0)
    dy = max(a[1] - b[3], b[1] - a[3], 0.0)
    return math.hypot(dx, dy)


def square_mean(g, cx, cy, s):
    """Mean grey of the 44-point square round (cx, cy) points, clipped to the picture."""
    h, w = g.shape
    x0, x1 = max(int(round((cx - BODY / 2) * s)), 0), min(int(round((cx + BODY / 2) * s)), w)
    y0, y1 = max(int(round((cy - BODY / 2) * s)), 0), min(int(round((cy + BODY / 2) * s)), h)
    if x1 <= x0 or y1 <= y0:
        return None
    return float(g[y0:y1, x0:x1].mean())


def ring_median(g, cx, cy, s):
    """Median grey of the pixels 64-80 points (Euclidean) from (cx, cy) points."""
    h, w = g.shape
    px, py = cx * s, cy * s
    out = RING[1] * s
    x0, x1 = max(int(math.floor(px - out)), 0), min(int(math.ceil(px + out)) + 1, w)
    y0, y1 = max(int(math.floor(py - out)), 0), min(int(math.ceil(py + out)) + 1, h)
    if x1 <= x0 or y1 <= y0:
        return None
    ys, xs = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(xs + 0.5 - px, ys + 0.5 - py)  # pixel centres, in pixels
    values = g[y0:y1, x0:x1][(d >= RING[0] * s) & (d <= RING[1] * s)]
    return float(np.median(values)) if values.size else None


# ---- the numbers

def ratio_for(off_g, on_g, s_off, s_on, off_c, on_cs, strips):
    """on brightness / off brightness of the body at off_c, or None (see the docstring)."""
    near = [(math.hypot(c[0] - off_c[0], c[1] - off_c[1]), c) for c in on_cs]
    if not near:
        return None
    dist, on_c = min(near)
    if dist > MATCH:
        return None
    for strip in strips:
        if strip and (gap(rect_of(*off_c), strip) == 0.0 or gap(rect_of(*on_c), strip) == 0.0):
            return None
    ref = ring_median(off_g, off_c[0], off_c[1], s_off)
    b_off = square_mean(off_g, off_c[0], off_c[1], s_off)
    b_on = square_mean(on_g, on_c[0], on_c[1], s_on)
    if ref is None or b_off is None or b_on is None:
        return None
    off_b, on_b = b_off - ref, b_on - ref
    if off_b <= MIN_OFF:
        return None
    return on_b / off_b


def patch_delta(off_g, on_g, s, body_rects, strip):
    """(mean of on - off over the flat background patches, how many)."""
    h, w = off_g.shape
    deltas = []
    for y in range(0, h - PATCH + 1, PATCH):
        for x in range(0, w - PATCH + 1, PATCH):
            tile = off_g[y:y + PATCH, x:x + PATCH]
            if tile.std() >= FLAT:
                continue
            rect = (x / s, y / s, (x + PATCH) / s, (y + PATCH) / s)
            if strip and gap(rect, strip) == 0.0:
                continue
            if any(gap(rect, b) < KEEP for b in body_rects):
                continue
            deltas.append(float(on_g[y:y + PATCH, x:x + PATCH].mean() - tile.mean()))
    return (sum(deltas) / len(deltas) if deltas else None), len(deltas)


def analyse_pair(pair, off_path, on_path, off_rec, on_rec):
    """{'far': [3 ratios or None], 'near': [...], 'delta': float or None, 'patches': n, 'failures': [...]}"""
    off_g, on_g = grey(off_path), grey(on_path)
    s_off, s_on = off_g.shape[1] / off_rec["size"][0], on_g.shape[1] / on_rec["size"][0]
    off_c, on_c = centres(off_rec), centres(on_rec)
    strips = [meter_rect(off_rec), meter_rect(on_rec)]
    by_top = sorted(off_c, key=lambda c: (c[1], c[0]))
    by_bottom = sorted(off_c, key=lambda c: (-c[1], c[0]))

    def ratios(picks):
        got = [ratio_for(off_g, on_g, s_off, s_on, c, on_c, strips) for c in picks[:3]]
        return got + [None] * (3 - len(got))

    bodies = [rect_of(*c) for c in off_c + on_c]
    delta, n = patch_delta(off_g, on_g, s_off, bodies, strips[0])
    failures = []
    if n < NEED:
        failures.append(f"{pair}: FAIL only {n} flat background patches, need {NEED}")
    return {"far": ratios(by_top), "near": ratios(by_bottom), "delta": delta, "patches": n, "failures": failures}


def line_for(pair, result):
    def r(v):
        return "n/a" if v is None else f"{v:.2f}"
    d = "n/a" if result["delta"] is None else f"{result['delta']:+.2f}"
    return (f"{pair}: far {' '.join(r(v) for v in result['far'])} near {' '.join(r(v) for v in result['near'])}"
            f" patch Δ {d} ({result['patches']} patches)")


# ---- finding the files

def collect(root):
    """{folder: {'stills': {name: path}, 'frames': path or None}} for each folder holding 70-* stills."""
    found = {}
    for folder, _, files in os.walk(root):
        stills, frames = {}, None
        for name in sorted(files):
            m = STILL.match(name)
            if m:
                key = f"{m.group('pair')}-{m.group('mode')}"
                rank = int(m.group("n") or 0)
                if key not in stills or rank < stills[key][0]:
                    stills[key] = (rank, os.path.join(folder, name))
                continue
            m = FRAMES.match(name)
            if m and (frames is None or int(m.group("n") or 0) < frames[0]):
                frames = (int(m.group("n") or 0), os.path.join(folder, name))
        if stills:
            found[folder] = {"stills": {k: v[1] for k, v in stills.items()}, "frames": frames[1] if frames else None}
    return found


def run(root):
    """Prints a line per pair; returns the exit status."""
    folders = collect(root)
    if not folders:
        print(f"FAIL no 70-*-on.png / 70-*-off.png under {root}")
        return 1
    status = 0
    for folder in sorted(folders):
        info = folders[folder]
        if len(folders) > 1:
            print(f"== {folder}")
        if not info["frames"]:
            print(f"FAIL no 75-body-frames in {folder}")
            status = 1
            continue
        try:
            with open(info["frames"], encoding="utf-8") as f:
                stills = json.load(f)["stills"]
        except (OSError, ValueError, KeyError, TypeError) as e:
            print(f"FAIL cannot read {info['frames']}: {e!r}")
            status = 1
            continue
        pairs = sorted({k.rsplit("-", 1)[0] for k in info["stills"]})
        for pair in pairs:
            on, off = info["stills"].get(pair + "-on"), info["stills"].get(pair + "-off")
            if not (on and off):
                print(f"{pair}: FAIL needs both the on and the off still")
                status = 1
            elif pair + "-on" not in stills or pair + "-off" not in stills:
                print(f"{pair}: FAIL no entry in 75-body-frames for its on and off stills")
                status = 1
            else:
                try:
                    result = analyse_pair(pair, off, on, stills[pair + "-off"], stills[pair + "-on"])
                except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
                    print(f"{pair}: FAIL cannot be read: {e!r}")
                    status = 1
                    continue
                print(line_for(pair, result))
                for failure in result["failures"]:
                    print(failure)
                    status = 1
    return status


# ---- self-test

def self_test():
    scale, size = 2, (400, 800)  # points; the pictures are twice as big
    bg_off, bg_on = 20, 23
    # (centre in points, off grey, wanted ratio); midY all different
    bodies = [((100, 100), 120, 0.25), ((300, 115), 140, 0.50), ((100, 280), 160, 0.75),
              ((300, 295), 100, 1.0), ((100, 460), 100, 1.0),
              ((300, 475), 160, 0.80), ((100, 640), 180, 0.90), ((300, 655), 200, 1.00)]

    def px(v):
        return int(round(v * scale))

    def fill(a, x0, y0, x1, y1, rgb):
        a[px(y0):px(y1), px(x0):px(x1)] = rgb

    def painted(on):
        a = np.zeros((size[1] * scale, size[0] * scale, 3), dtype=np.uint8)
        a[:] = bg_on if on else bg_off
        fill(a, 8, 40, 392, 56, 120 if on else bg_off)  # the meter: differs only in the on still
        # the noisy last row of patches: std 30 in the off still, bright in the on one
        a[px(768):, :] = 150 if on else 0
        if not on:
            a[px(768):, ::2] = 60
        for (cx, cy), off_grey, ratio in bodies:
            g = off_grey if not on else bg_off + ratio * (off_grey - bg_off)
            g = int(round(g))
            if on:
                fill(a, cx - 52, cy - 52, cx + 52, cy + 52, 60)  # a halo round each body, on only
            fill(a, cx - 22, cy - 22, cx + 22, cy + 22, g)
            if cx == 300 and cy == 115:  # channels apart, same mean: grey is the mean of R, G, B
                fill(a, cx - 22, cy - 22, cx + 22, cy + 22, (g + 30, g, g - 30))
        return a

    def record(on):
        return {"size": list(size), "meter": [8, 40, 384, 16], "line": "on frame 16.70",
                "bodies": [[cx - 22, cy - 22, 44, 44] for (cx, cy), _, _ in bodies]}

    here = "/__w/_temp" if os.path.isdir("/__w/_temp") else None
    work = tempfile.mkdtemp(prefix="depth-crops-", dir=here)
    try:
        shots = os.path.join(work, "iphone")
        os.makedirs(shots)
        # named as the workflow's exporter names them
        Image.fromarray(painted(True), "RGB").save(os.path.join(shots, "graph-70-space-high-whole-on.png"))
        Image.fromarray(painted(False), "RGB").save(os.path.join(shots, "graph-70-space-high-whole-off.png"))
        Image.fromarray(np.zeros((16, 16, 3), dtype=np.uint8), "RGB").save(
            os.path.join(shots, "graph-70-space-high-whole-on-2.png"))  # a later duplicate: ignored
        frames = {"stills": {"70-space-high-whole-on": record(True), "70-space-high-whole-off": record(False)}}
        with open(os.path.join(shots, "graph-75-body-frames.txt"), "w", encoding="utf-8") as f:
            json.dump(frames, f)

        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = run(work)
        text = out.getvalue()
        want = "70-space-high-whole: far 0.25 0.50 0.75 near 1.00 0.90 0.80 patch Δ +3.00 ("
        assert status == 0 and want in text, f"unexpected output (status {status}):\n{text}"
        n = int(text.split("patch Δ +3.00 (")[1].split(" ")[0])
        assert n >= NEED, f"only {n} patches"
        print(text.strip())

        # a pair with nothing flat to measure against is reported, not passed
        noisy = np.random.RandomState(1).randint(0, 256, (size[1] * scale, size[0] * scale, 3)).astype(np.uint8)
        Image.fromarray(noisy, "RGB").save(os.path.join(work, "n-off.png"))
        Image.fromarray(noisy, "RGB").save(os.path.join(work, "n-on.png"))
        result = analyse_pair("70-x", os.path.join(work, "n-off.png"), os.path.join(work, "n-on.png"),
                              record(False), record(True))
        assert result["patches"] == 0 and result["failures"], "no failure line for a pair with no flat patches"
        print(result["failures"][0])
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("SELF-TEST OK")


def main():
    with contextlib.suppress(AttributeError, ValueError):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="Brightness ratios and background change of the depth fade's 70-* stills.")
    ap.add_argument("dir", nargs="?", help="the exported pictures (shots/iphone, or a folder above it)")
    ap.add_argument("--self-test", action="store_true", help="check the arithmetic on synthetic pictures")
    args = ap.parse_args()
    if args.self_test:
        try:
            self_test()
        except AssertionError as e:
            print(f"SELF-TEST FAILED: {e}")
            return 1
        return 0
    if not args.dir:
        ap.error("give the folder of exported pictures, or --self-test")
    return run(args.dir)


if __name__ == "__main__":
    sys.exit(main())
