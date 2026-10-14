#!/usr/bin/env python3
"""Make the owner's film of the opening: the simulator's silent recording with
the heartbeat laid in where the app plays it, and a strip of frames.

    python3 tools/launch_film.py RAW.mp4 light|dark OUT.mp4 [--strip OUT.png]

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
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_heartbeat  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TRACE = {"light": (0x43, 0x56, 0x6F), "dark": (0x65, 0x84, 0xAE)}
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw"); ap.add_argument("mode", choices=["light", "dark"]); ap.add_argument("out")
    ap.add_argument("--strip")
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
            # from just before the ECG to past the reveal, every 0.1 s
            picks = [start - 6] + [start + int(k * FPS * 0.1) for k in range(0, 15)]
            picks = [p for p in picks if 0 <= p < len(paths)]
            thumbs = [Image.open(paths[p]).convert("RGB") for p in picks]
            tw = 180
            th = int(thumbs[0].height * tw / thumbs[0].width)
            strip = Image.new("RGB", (tw * len(thumbs), th), "black")
            for i, t in enumerate(thumbs):
                strip.paste(t.resize((tw, th), Image.LANCZOS), (i * tw, 0))
            strip.save(args.strip)
            print(args.strip, [f"{(p - start) / FPS:+.2f}" for p in picks])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
