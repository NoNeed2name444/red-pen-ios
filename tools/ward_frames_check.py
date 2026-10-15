#!/usr/bin/env python3
"""Checks a recording of the app switching light and dark for a fade.

Every frame's content contrast (the spread of brightness in the middle of
the screen, where the cards and their words are) must stay at or above the
lower of the two end states. A cross-fade, or a mix of the light and dark
palettes, passes through grey on grey: words and cards wash out, and the
spread falls well below both ends. A clean switch changes in one step.

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


def frames(video):
    tmp = tempfile.mkdtemp()
    # every frame the recorder kept, small: the spread does not need detail
    subprocess.run(["ffmpeg", "-loglevel", "error", "-i", video, "-vsync", "0",
                    "-vf", "scale=300:-1", f"{tmp}/f%05d.png"], check=True)
    for path in sorted(glob.glob(f"{tmp}/f*.png")):
        g = Image.open(path).convert("L")
        w, h = g.size
        middle = g.crop((int(w * 0.1), int(h * 0.38), int(w * 0.9), int(h * 0.62)))
        stat = ImageStat.Stat(middle)
        yield stat.mean[0], stat.stddev[0]


def main():
    args = sys.argv[1:]
    report = None
    if "--report" in args:
        i = args.index("--report")
        report = args[i + 1]
        del args[i:i + 2]
    rows = list(frames(args[0]))
    light = sorted(s for m, s in rows if m >= DARK)
    dark = sorted(s for m, s in rows if m < DARK)
    lines = []
    if not light or not dark:
        lines.append(f"only one mode in {len(rows)} frames: nothing to check")
        code = 2
    else:
        # the ends: the typical spread of each mode at rest
        ends = (light[len(light) // 2], dark[len(dark) // 2])
        floor = min(ends)
        faded = [(i, m, s) for i, (m, s) in enumerate(rows) if s < FADED * floor]
        lines.append(f"{len(rows)} frames; content contrast light {ends[0]:.1f}, dark {ends[1]:.1f}; "
                     f"a frame under {FADED * floor:.1f} has faded")
        for i, m, s in faded:
            lines.append(f"FADED frame {i}: contrast {s:.1f}, brightness {m:.0f}")
        lines.append("clean: every frame keeps its contrast" if not faded else f"{len(faded)} faded frames")
        code = 1 if faded else 0
    text = "\n".join(lines)
    print(text)
    if report:
        with open(report, "w") as f:
            f.write(text + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
