#!/usr/bin/env python3
"""Checks a recording of the app switching light and dark for a fade.

The rule (the owner, 15 Oct 2026, 6:25 PM Cairo: "loosen the no fade rule a
bit"):
- Still banned: anything that looks washed out at rest (faded buttons, text
  or cards), and a visible fade lasting longer than 0.2 s used as a
  transition.
- Allowed, besides the buttons' rim and the Neurons depth fade (4f): iOS's
  own brief transitions (the status bar, sheet and alert dimming, the
  keyboard, menus), any change that settles within 0.2 s, and crossfades
  under Reduce Motion.

So each frame's content contrast (the spread of brightness in the middle of
the screen, where the cards and their words are) is measured against the
lower of the two end states. A cross-fade, or a mix of the light and dark
palettes, passes through grey on grey: words and cards wash out, and the
spread falls below both ends. A frame under FADED of the lower end has
faded. Faded frames in a row make a stretch, and a stretch fails only when
it stays on screen longer than BRIEF (0.2 s): from its first frame's time to
the next frame's (the first one back above the floor), or to the end of the
recording when it never comes back, which is washed out at rest. A shorter
stretch is reported as a brief dip, allowed.

The status bar (where the clock is) is measured and reported the same way
but never fails: its words changing style is iOS's own transition.

An end state is a mode at rest: the highest spread among that mode's frames
that stay on screen for REST (0.5 s) or more. The recorder keeps a frame
only when the screen changes, so a settled look is one long frame and a
fade is many short ones; the last frame of a run in one mode is no end
state, it can be caught half way through a crossfade. A frame's time is
ffprobe's best_effort_timestamp_time, matched one to one to the frames
ffmpeg writes with -vsync 0.

    python3 tools/ward_frames_check.py <recording.mp4> [--report out.txt]

Needs ffmpeg, ffprobe and Pillow. Exit 0 clean (brief dips allowed), 1 the
content faded for longer than 0.2 s, 2 nothing to check: one mode only, or
frames and times that do not match.
"""
import glob
import shutil
import subprocess
import sys
import tempfile

# below this share of the lower end's contrast, a frame has faded
FADED = 0.8
# a faded stretch on screen longer than this, in seconds, fails
BRIEF = 0.2
# a frame on screen this long, in seconds, is at rest, not part of a fade
REST = 0.5
# a frame this dark (mean brightness of the middle, 0-255) is the dark state
DARK = 120

# where contrast is measured, as shares of the width and height, and
# whether a fade there fails the check
REGIONS = {
    "content": (0.1, 0.38, 0.9, 0.62),
    "status bar": (0.08, 0.015, 0.3, 0.05),
}
GATED = {"content": True, "status bar": False}


def measure(video):
    """Each frame's (mean brightness, spread) per region, in the order
    ffmpeg writes them."""
    from PIL import Image, ImageStat

    tmp = tempfile.mkdtemp()
    try:
        # every frame the recorder kept, small: the spread does not need detail
        subprocess.run(["ffmpeg", "-loglevel", "error", "-i", video, "-vsync", "0",
                        "-vf", "scale=300:-1", f"{tmp}/f%05d.png"], check=True,
                       # a recording kept only on change repeats timestamps,
                       # which the image writer reports and handles
                       stderr=subprocess.DEVNULL)
        rows = []
        for path in sorted(glob.glob(f"{tmp}/f*.png")):
            g = Image.open(path).convert("L")
            w, h = g.size
            row = {}
            for name, (x0, y0, x1, y1) in REGIONS.items():
                stat = ImageStat.Stat(g.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1))))
                row[name] = (stat.mean[0], stat.stddev[0])
            rows.append(row)
        return rows
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def parse_times(text):
    """ffprobe's csv of best_effort_timestamp_time, one frame a line; a frame
    with side data ends its line with a comma. None for a frame with no time."""
    times = []
    for line in text.splitlines():
        field = line.split(",")[0].strip()
        if not field:
            continue
        try:
            times.append(float(field))
        except ValueError:
            times.append(None)
    return times


def probe(video):
    """Each frame's time, and the recording's end (None when unknown)."""
    def run(entries):
        return subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", entries,
                               "-of", "csv=p=0", video], check=True, capture_output=True, text=True).stdout
    times = parse_times(run("frame=best_effort_timestamp_time"))
    end = parse_times(run("format=duration"))
    return times, end[0] if end else None


def ends(rows, times, end, name):
    """The spread of each mode at rest, (light, dark).

    A frame is at rest when it stays on screen for REST seconds or more: the
    recorder keeps a frame only when the screen changes, so a settled look is
    one long frame, and a fade is many short ones. Each mode's end state is
    the highest spread among its frames at rest, so a frame caught half way
    through a crossfade (grey on grey, the lowest spread of the lot) can
    never set the floor and let the fade pass. A mode with no frame at rest
    takes the highest spread of any of its frames."""
    best = {True: [], False: []}
    rest = {True: [], False: []}
    for i, row in enumerate(rows):
        dark = row["content"][0] < DARK
        best[dark].append(row[name][1])
        until = times[i + 1] if i + 1 < len(rows) else end
        if until is None or until - times[i] >= REST - 1e-9:
            rest[dark].append(row[name][1])
    light, dark = (max(rest[m] or best[m]) for m in (False, True))
    return light, dark


def stretches(rows, times, end, name, floor):
    """Faded frames in a row, each stretch as (first, last, seconds on
    screen or None when unknown, lowest spread, that frame's brightness)."""
    out = []
    i = 0
    while i < len(rows):
        if rows[i][name][1] >= floor:
            i += 1
            continue
        j = i
        while j + 1 < len(rows) and rows[j + 1][name][1] < floor:
            j += 1
        until = times[j + 1] if j + 1 < len(rows) else end
        if until is not None and end is not None:
            until = min(until, max(end, times[j]))
        seconds = None if until is None else max(0.0, until - times[i])
        low = min(range(i, j + 1), key=lambda k: rows[k][name][1])
        out.append((i, j, seconds, rows[low][name][1], rows[low][name][0]))
        i = j + 1
    return out


def judge(rows, times, end):
    """The verdict on a recording: (report lines, exit code)."""
    if len(times) != len(rows) or any(t is None for t in times):
        return [f"{len(rows)} frames but {sum(t is not None for t in times)} frame times: "
                "a fade's length cannot be measured"], 2
    modes = {row["content"][0] < DARK for row in rows}
    if len(modes) < 2:
        return [f"only one mode in {len(rows)} frames: nothing to check"], 2
    lines = []
    failed = 0
    for name in REGIONS:
        light, dark = ends(rows, times, end, name)
        floor = FADED * min(light, dark)
        note = "" if GATED[name] else " (reported, never fails: iOS's own transition)"
        lines.append(f"{len(rows)} frames; {name} contrast light {light:.1f}, dark {dark:.1f}; "
                     f"a frame under {floor:.1f} has faded{note}")
        for first, last, seconds, low, mean in stretches(rows, times, end, name, floor):
            held = "to the end, length unknown" if seconds is None else f"{seconds:.3f} s"
            span = (f"frames {first}-{last} from {times[first]:.3f} s, on screen {held}; "
                    f"lowest contrast {low:.1f}, brightness {mean:.0f}")
            if not GATED[name]:
                lines.append(f"faded {name}, not gated: {span}")
            elif seconds is None or seconds > BRIEF + 1e-9:
                failed += 1
                lines.append(f"FADED {name}, longer than {BRIEF} s: {span}")
            else:
                lines.append(f"brief dip, allowed ({name}): {span}")
    if failed:
        lines.append(f"{failed} faded stretches longer than {BRIEF} s")
    else:
        lines.append(f"clean: the content keeps its contrast, or dips for {BRIEF} s at most")
    return lines, 1 if failed else 0


def main():
    args = sys.argv[1:]
    report = None
    if "--report" in args:
        i = args.index("--report")
        report = args[i + 1]
        del args[i:i + 2]
    rows = measure(args[0])
    times, end = probe(args[0])
    lines, code = judge(rows, times, end)
    text = "\n".join(lines)
    print(text)
    if report:
        with open(report, "w") as f:
            f.write(text + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
