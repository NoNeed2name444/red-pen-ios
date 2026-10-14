#!/usr/bin/env python3
"""Put the voice sample together: the same lines (lines.json) in the natural
cloud voice and in the phone's own voice, each as an MP4 to listen to.

    voice_sample.py cloud lines.json out/      # read by the live Worker (/tts)
    voice_sample.py film out/ still.png        # out/*.tsv -> out/*.mp4

The cloud voice paces itself: only the quiet after a line is the app's
(VoiceTone.after), as in VoiceSpeaker. The phone's lines carry their quiet
before and after (phone.tsv, written by main.swift on a Mac).

The Worker key is WORKER_KEY (the owner key, built from AI_API_KEY by the
workflow); it is never printed.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

WORKER = os.environ.get("WORKER", "https://redpen-auth.vv7sh4rnnw.workers.dev")

# VoiceTone.after, for the cloud voice
AFTER = {"asking": 0.35, "listing": 0.25, "alert": 0.1}


def cloud(lines_path: Path, out: Path) -> int:
    key = os.environ.get("WORKER_KEY", "")
    if not key:
        print("no WORKER_KEY: the cloud voice is left out")
        return 0
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for index, line in enumerate(json.loads(lines_path.read_text())):
        request = urllib.request.Request(
            f"{WORKER}/tts", method="POST",
            data=json.dumps({"text": line["text"], "voice": line["role"]}).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                model = response.headers.get("x-voice-model", "?")
                kind = response.headers.get("content-type", "")
        except Exception as error:  # noqa: BLE001 - reported, then the line is skipped
            print(f"line {index}: {getattr(error, 'code', '')} {str(error)[:120]}")
            continue
        if "audio" not in kind or len(body) < 256:
            print(f"line {index}: not audio ({kind}, {len(body)} bytes)")
            continue
        name = f"cloud-{index:02d}.mp3"
        (out / name).write_bytes(body)
        rows.append(f"{name}\t0\t{AFTER.get(line['tone'], 0.2)}")
        print(f"{name}: {line['role']} {line['tone']} ({model})")
    if rows:
        (out / "cloud.tsv").write_text("\n".join(rows) + "\n")
    return 0


def run(*args: str) -> None:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def silence(path: Path, seconds: float) -> None:
    run("-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", f"{max(seconds, 0.01):.2f}",
        "-c:a", "pcm_s16le", str(path))


def film(out: Path, still: Path) -> int:
    for manifest in sorted(out.glob("*.tsv")):
        part = manifest.stem
        work = out / f"{part}-work"
        work.mkdir(exist_ok=True)
        pieces = []
        for n, row in enumerate(manifest.read_text().splitlines()):
            name, before, after = row.split("\t")
            if float(before) > 0:
                silence(work / f"{n:02d}a.wav", float(before))
                pieces.append(work / f"{n:02d}a.wav")
            run("-i", str(out / name), "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", str(work / f"{n:02d}b.wav"))
            pieces.append(work / f"{n:02d}b.wav")
            silence(work / f"{n:02d}c.wav", float(after))
            pieces.append(work / f"{n:02d}c.wav")
        listing = work / "list.txt"
        listing.write_text("".join(f"file '{p.resolve()}'\n" for p in pieces))
        audio = work / "all.wav"
        run("-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(audio))
        movie = out / f"voice-{part}.mp4"
        run("-loop", "1", "-i", str(still), "-i", str(audio), "-c:v", "libx264", "-tune", "stillimage",
            "-pix_fmt", "yuv420p", "-r", "2", "-c:a", "aac", "-b:a", "160k", "-shortest", str(movie))
        print(movie)
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "cloud":
        raise SystemExit(cloud(Path(sys.argv[2]), Path(sys.argv[3])))
    if command == "film":
        raise SystemExit(film(Path(sys.argv[2]), Path(sys.argv[3])))
    print(__doc__)
    raise SystemExit(2)
