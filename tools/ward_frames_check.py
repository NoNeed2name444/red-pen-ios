#!/usr/bin/env python3
"""Checks a recording of the app switching light and dark for a fade.

Every frame's content contrast (the spread of brightness in the middle of
the screen, where the cards and their words are, and in the status bar,
where the clock is) must stay at or above the lower of the two end states.
A cross-fade, or a mix of the light and dark palettes, passes through grey
on grey: words and cards wash out, and the spread falls well below both
ends. A clean switch changes in one step.

An end state is a mode at rest: the last frame of each stretch in that
mode (the recorder keeps a frame only when the screen changes, so a slow
fade leaves many frames and the last one is the settled look).

    python3 tools/ward_frames_check.py <recording.mp4> [--report out.txt]

Needs ffmpeg and Pillow. Exit 0 clean, 1 a frame faded, 2 nothing to check.
"""
import glob
import subprocess
import sys
import tempfile

from PIL import Image, ImageStat

# below this share of the lower end's contrast, a frame has faded
FADED = 0.8
# a frame this dark (mean brightness of the middle, 0-255) is the dark state
DARK = 120


# where contrast is measured, as shares of the width and height
REGIONS = {
    "content": (0.1, 0.38, 0.9, 0.62),
    "status bar": (0.08, 0.015, 0.3, 0.05),
}


def frames(video):
    tmp = tempfile.mkdtemp()
    # every frame the recorder kept, small: the spread does not need detail
    subprocess.run(["ffmpeg", "-loglevel", "error", "-i", video, "-vsync", "0",
                    "-vf", "scale=300:-1", f"{tmp}/f%05d.png"], check=True,
                   # a recording kept only on change repeats timestamps,
                   # which the image writer reports and handles
                   stderr=subprocess.DEVNULL)
    for path in sorted(glob.glob(f"{tmp}/f*.png")):
        g = Image.open(path).convert("L")
        w, h = g.size
        row = {}
        for name, (x0, y0, x1, y1) in REGIONS.items():
            stat = ImageStat.Stat(g.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1))))
            row[name] = (stat.mean[0], stat.stddev[0])
        yield row


def ends(rows, name):
    """The typical spread of each mode at rest, (light, dark)."""
    settled = {True: [], False: []}
    for i, row in enumerate(rows):
        dark = row["content"][0] < DARK
        last = i + 1 == len(rows) or (rows[i + 1]["content"][0] < DARK) != dark
        if last:
            settled[dark].append(row[name][1])
    light, dark = sorted(settled[False]), sorted(settled[True])
    return light[len(light) // 2], dark[len(dark) // 2]


def main():
    args = sys.argv[1:]
    report = None
    if "--report" in args:
        i = args.index("--report")
        report = args[i + 1]
        del args[i:i + 2]
    rows = list(frames(args[0]))
    modes = {row["content"][0] < DARK for row in rows}
    lines = []
    if len(modes) < 2:
        lines.append(f"only one mode in {len(rows)} frames: nothing to check")
        code = 2
    else:
        faded = 0
        for name in REGIONS:
            light, dark = ends(rows, name)
            floor = FADED * min(light, dark)
            lines.append(f"{len(rows)} frames; {name} contrast light {light:.1f}, dark {dark:.1f}; "
                         f"a frame under {floor:.1f} has faded")
            for i, row in enumerate(rows):
                m, s = row[name]
                if s < floor:
                    faded += 1
                    lines.append(f"FADED frame {i} ({name}): contrast {s:.1f}, brightness {m:.0f}")
        lines.append("clean: every frame keeps its contrast" if not faded else f"{faded} faded frames")
        code = 1 if faded else 0
    text = "\n".join(lines)
    print(text)
    if report:
        with open(report, "w") as f:
            f.write(text + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
