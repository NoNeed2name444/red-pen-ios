#!/usr/bin/env python3
"""Make the owner's film of the opening: the simulator's silent recording with
the heartbeat laid in where the app plays it, and a strip of frames.

    python3 tools/launch_film.py RAW.mp4 light|dark OUT.mp4 [--strip OUT.png]
        [--handoff OUT.png] [--frames DIR]

--strip is the whole opening every 0.1 s; --handoff the hand-off to home
every 0.05 s (0.60 s to 1.80 s from the ECG's start), in rows; --frames
keeps those hand-off frames at full size, to look for seams and jumps.

The simulator records no sound. The app starts the ECG's baseline at the
opening's zero and plays the heartbeat LaunchOpening.audioAt later (S1 on the
R peak), so the sound goes in at the first frame where the ECG shows, plus
that offset. The film is H.264, yuv420p, AAC, faststart: what an iPhone plays.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_heartbeat  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
# the ECG's colours, as LaunchArt.trace has them: WardPalette's .ecg
_trace = re.search(r"\.ecg:\s*\(0x([0-9A-Fa-f]{6}),\s*0x([0-9A-Fa-f]{6})\)",
                   (ROOT / "ios/RedPen/Shared/Ward/WardPalette.swift").read_text())
TRACE = {mode: tuple(int(_trace.group(g)[i:i + 2], 16) for i in (0, 2, 4)) for mode, g in (("light", 1), ("dark", 2))}
FPS = 60


def constants() -> tuple[float, float]:
    """(audioAt, R) from LaunchOpening.swift: R is 0.33, S1 the file's onset."""
    src = (ROOT / "ios/RedPen/Shared/LaunchOpening.swift").read_text()
    s1 = float(re.search(r"static let s1: Double = ([0-9.]+)", src).group(1))
    r = float(re.search(r"\n\s*return 0\.(\d+)\n", src).group(0).split("return")[1])
    return r - s1, r


def frames(raw: Path, tmp: Path) -> list[Path]:
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(raw), "-vf", f"fps={FPS}",
                    str(tmp / "f%05d.png")], check=True)
    return sorted(tmp.glob("f*.png"))


def ecg_start(paths: list[Path], mode: str) -> int:
    """The first frame where the trace's colour newly appears in the band
    just under the mark, where the ECG's baseline runs (and nothing else has
    that colour: it must be new since a few frames before)."""
    want = np.array(TRACE[mode])

    def hits(p: Path) -> np.ndarray:
        a = np.asarray(Image.open(p).convert("RGB"), dtype=int)
        h, w = a.shape[:2]
        band = a[int(h * 0.655):int(h * 0.71), int(w * 0.25):int(w * 0.75)]
        return np.abs(band - want).max(axis=2) < 16

    seen = [hits(p) for p in paths]
    for i in range(6, len(paths)):
        if (seen[i] & ~seen[i - 6]).sum() >= 8:
            return i
    raise SystemExit("no ECG found in the recording")


def sheet(paths: list[Path], picks: list[int], start: int, out: str, per_row: int, tw: int = 180) -> None:
    """Frames `picks` side by side, `per_row` to a row, each labelled with
    its seconds from the opening's zero (the ECG's first frame)."""
    picks = [p for p in picks if 0 <= p < len(paths)]
    thumbs = [Image.open(paths[p]).convert("RGB") for p in picks]
    th = int(thumbs[0].height * tw / thumbs[0].width)
    rows = -(-len(thumbs) // per_row)
    img = Image.new("RGB", (tw * min(per_row, len(thumbs)), (th + 18) * rows), "black")
    draw = ImageDraw.Draw(img)
    for i, (t, p) in enumerate(zip(thumbs, picks)):
        x, y = (i % per_row) * tw, (i // per_row) * (th + 18)
        img.paste(t.resize((tw, th), Image.LANCZOS), (x, y + 18))
        draw.text((x + 6, y + 3), f"{(p - start) / FPS:+.2f} s", fill="white")
    img.save(out)
    print(out, [f"{(p - start) / FPS:+.2f}" for p in picks])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw"); ap.add_argument("mode", choices=["light", "dark"]); ap.add_argument("out")
    ap.add_argument("--strip")
    ap.add_argument("--handoff")
    ap.add_argument("--frames")
    args = ap.parse_args()
    audio_at, _ = constants()
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        paths = frames(Path(args.raw), tmp)
        start = ecg_start(paths, args.mode)
        zero = start / FPS
        x, rate = make_heartbeat.read(ROOT / "ios/RedPen/Assets.xcassets/Heartbeat.dataset/heartbeat.caf")
        wav = tmp / "beat.wav"
        import wave
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
            w.writeframes(np.round(x * 32767).astype("<i2").tobytes())
        delay_ms = int(round((zero + audio_at) * 1000))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(tmp / "f%05d.png"),
                        "-i", str(wav), "-filter_complex",
                        f"[1:a]adelay={delay_ms}|{delay_ms},apad[a]", "-map", "0:v", "-map", "[a]", "-shortest",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                        "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", args.out], check=True)
        print(f"{args.out}: ECG from frame {start} ({zero:.3f} s), heartbeat at {zero + audio_at:.3f} s")
        if args.strip:
            # from just before the ECG to past the hand-off, every 0.1 s
            picks = [start - 6] + [start + round(k * FPS * 0.1) for k in range(0, 17)]
            sheet(paths, picks, start, args.strip, per_row=len(picks))
        if args.handoff or args.frames:
            picks = [start + round(k * FPS * 0.05) for k in range(12, 37)]
            if args.handoff:
                sheet(paths, picks, start, args.handoff, per_row=10, tw=200)
            if args.frames:
                out = Path(args.frames)
                out.mkdir(parents=True, exist_ok=True)
                for p in picks:
                    if 0 <= p < len(paths):
                        Image.open(paths[p]).save(out / f"t{(p - start) / FPS:+.2f}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
