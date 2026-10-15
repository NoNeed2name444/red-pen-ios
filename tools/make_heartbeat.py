#!/usr/bin/env python3
"""Make the launch heartbeat (one lub-dub), and measure where its two sounds start.

The opening plays one heartbeat as the chest piece beats and the ECG is drawn
(LaunchSplash). No recording was used: the sound is made here, from nothing
but arithmetic, so the app owns it outright (design/sound/LICENSES.md).

    python3 tools/make_heartbeat.py                 # write the sound into the asset catalogue
    python3 tools/make_heartbeat.py --m4a out.m4a   # and an AAC copy to listen to (needs ffmpeg)
    python3 tools/make_heartbeat.py --measure FILE  # only measure a .caf or .wav

How it is made, as a heart sounds through a stethoscope's bell:
- S1 ("lub"): the mitral then the tricuspid valve closing 22 ms apart, each a
  damped low body (about 30-65 Hz) with content at 100-150 Hz, 0.13 s long;
- S2 ("dub"): the aortic then the pulmonary valve 28 ms apart, shorter
  (0.09 s) and higher (about 70-210 Hz), 0.36 s after S1, the master ECG's
  S1 to S2 (ios/RedPen/Shared/Brand/EcgTrace.swift: S1 just after R, S2 on
  T's end, at 60 a minute);
- both with a fast rise and an exponential fall, and a little band-limited
  noise for the tissue's texture;
- then coloured as the chest and the tubing colour it: a band from 20 to
  about 240 Hz with a soft rise near 90 Hz, and a gentle saturation;
- and, because a phone's speaker plays almost nothing under 200 Hz, a
  "speaker layer" on each valve: the valve's knock as damped partials at
  about 170-480 Hz (the lub's lower and longer, the dub's higher and
  snappier), with a 3 ms click of band-limited noise (300-1500 Hz) on its
  front edge. The thump stays underneath for headphones; the knock is what
  a phone speaker gives back. Writing (or --measure FILE --audit) prints
  what a 200 Hz high-pass leaves of each sound.

The file is a mono 16-bit linear PCM .caf (Core Audio Format), so the app
starts it with no decoding delay, and the launchopening suite can read it.

--measure prints where S1 and S2 start (the RMS over 5 ms first passing a
tenth of the loudest), which HeartbeatSound.s1 / .s2 in
ios/RedPen/Shared/LaunchOpening.swift must say; the suite measures the file
the same way and checks.
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np

RATE = 44100
LEAD = 0.030          # silence before S1
SYSTOLE = 0.360       # S1 onset to S2 onset: EcgTrace's S1 to S2
LENGTH = 0.56
KNOCK = 1.6          # the knock's peak against the thump's
OUT = Path("ios/RedPen/Assets.xcassets/Heartbeat.dataset")


def burst(t: np.ndarray, start: float, length: float, parts, attack: float, decay: float,
          rng: np.random.Generator, noise: float) -> np.ndarray:
    u = t - start
    on = (u >= 0) & (u < length)
    env = np.zeros_like(t)
    uu = u[on]
    env[on] = (1 - np.exp(-uu / attack)) * np.exp(-uu / decay)
    # a cosine taper over the last fifth, so nothing ends in a click
    tail = np.clip((length - uu) / (0.2 * length), 0, 1)
    env[on] *= 0.5 - 0.5 * np.cos(np.pi * tail)
    sig = np.zeros_like(t)
    for f, amp, glide in parts:
        # each valve's ring falls a little in pitch as it dies
        phase = 2 * np.pi * (f * u + 0.5 * glide * u * u) + rng.uniform(0, 2 * np.pi)
        sig += amp * np.sin(phase)
    grain = band(rng.standard_normal(len(t)), 25, 180)
    grain /= np.abs(grain).max() or 1
    return (sig + noise * grain) * env


def band(x: np.ndarray, low: float, high: float, bump: float = 0) -> np.ndarray:
    """Second-order-ish band (20 Hz up, `high` down) by FFT, with an optional rise near 90 Hz."""
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    gain = 1 / np.sqrt(1 + (low / np.maximum(f, 1e-6)) ** 4) / np.sqrt(1 + (f / high) ** 4)
    if bump:
        gain *= 1 + bump * np.exp(-((f - 90) / 35) ** 2)
    return np.fft.irfft(np.fft.rfft(x) * gain, len(x))


def knock(t: np.ndarray, start: float, parts, decay: float, rng: np.random.Generator,
          click: float) -> np.ndarray:
    """A valve's knock where a phone speaker can play it: damped partials
    (each falling a little in pitch) and a short click on the front edge."""
    u = t - start
    on = u >= 0
    env = np.zeros_like(t)
    env[on] = (1 - np.exp(-u[on] / 0.0015)) * np.exp(-u[on] / decay)
    sig = np.zeros_like(t)
    for f, amp in parts:
        sig += amp * np.sin(2 * np.pi * (f * u - 0.5 * 0.6 * f * u * u) + rng.uniform(0, 2 * np.pi))
    tick = band(rng.standard_normal(len(t)), 300, 1500)
    tick /= np.abs(tick).max() or 1
    tick_env = np.zeros_like(t)
    tick_env[on] = np.exp(-u[on] / 0.0012) * (u[on] < 0.012)
    return sig * env + click * tick * tick_env


def heartbeat(seed: int = 7) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = np.arange(int(LENGTH * RATE)) / RATE
    s1, s2 = LEAD, LEAD + SYSTOLE
    lub = [(34, 1.0, -40), (52, 0.75, -60), (108, 0.42, -80), (142, 0.28, -90)]
    dub = [(72, 0.8, -60), (118, 0.62, -90), (166, 0.45, -110), (208, 0.2, -120)]
    x = (burst(t, s1, 0.13, lub, 0.004, 0.034, rng, 0.35)
         + 0.8 * burst(t, s1 + 0.022, 0.11, lub, 0.004, 0.030, rng, 0.3)
         + 0.85 * burst(t, s2, 0.09, dub, 0.0025, 0.020, rng, 0.25)
         + 0.55 * burst(t, s2 + 0.028, 0.07, dub, 0.0025, 0.018, rng, 0.2))
    x = band(x, 20, 240, bump=0.6)
    x /= np.abs(x).max()
    # a soft saturation: harmonics up to a few hundred hertz, the thump a
    # small speaker can reproduce
    x = np.tanh(2.6 * x) / np.tanh(2.6)
    # the knock, for small speakers (S1's mitral and tricuspid parts, S2's
    # aortic and pulmonary), mixed in under the thump's peak
    lub_k = [(172, 1.0), (258, 0.7), (344, 0.45), (470, 0.2)]
    dub_k = [(236, 1.0), (330, 0.75), (452, 0.5), (590, 0.2)]
    k = (knock(t, s1, lub_k, 0.042, rng, 0.9)
         + 0.7 * knock(t, s1 + 0.022, lub_k, 0.034, rng, 0.6)
         + 0.9 * knock(t, s2, dub_k, 0.020, rng, 1.0)
         + 0.55 * knock(t, s2 + 0.028, dub_k, 0.016, rng, 0.6))
    k = band(k, 140, 1800)
    x = x + KNOCK * k / np.abs(k).max()
    # nothing before S1 but silence (the filter rings a hair either side)
    x[: int((s1 - 0.004) * RATE)] = 0
    fade = int(0.02 * RATE)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.abs(x).max() * 10 ** (-1 / 20)


def write_caf(path: Path, x: np.ndarray) -> None:
    """Mono 16-bit big-endian linear PCM in a Core Audio Format file."""
    # rounded to the nearest count, but never past -1 dBFS of 32767: the
    # loudest sample is rounded down, not up
    cap = np.floor(32767 * 10 ** (-1 / 20))
    pcm = np.clip(np.round(np.clip(x, -1, 1) * 32767), -cap, cap).astype(">i2").tobytes()
    desc = struct.pack(">dIIIIII", float(RATE), int.from_bytes(b"lpcm", "big"), 0, 2, 1, 1, 16)
    data = struct.pack(">I", 0) + pcm
    path.write_bytes(b"caff" + struct.pack(">HH", 1, 0)
                     + b"desc" + struct.pack(">q", len(desc)) + desc
                     + b"data" + struct.pack(">q", len(data)) + data)


def read(path: Path) -> tuple[np.ndarray, int]:
    raw = path.read_bytes()
    if raw[:4] == b"caff":
        i, rate, samples = 8, RATE, None
        while i < len(raw):
            kind, size = raw[i:i + 4], struct.unpack(">q", raw[i + 4:i + 12])[0]
            body = raw[i + 12:i + 12 + size]
            if kind == b"desc":
                rate = int(struct.unpack(">d", body[:8])[0])
            if kind == b"data":
                samples = np.frombuffer(body[4:], dtype=">i2").astype(np.float64) / 32768
            i += 12 + size
        return samples, rate
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768, w.getframerate()


def onsets(x: np.ndarray, rate: int) -> tuple[float, float]:
    """S1's and S2's onsets: where the 5 ms RMS first passes a tenth of its
    peak, for the first sound and for the next one after 60 ms of quiet."""
    win = int(0.005 * rate)
    rms = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="full")[: len(x)])
    level = 0.1 * rms.max()
    loud = rms > level
    first = int(np.argmax(loud))
    quiet, i = 0, first
    while i < len(x):
        quiet = quiet + 1 if not loud[i] else 0
        if quiet > 0.06 * rate:
            break
        i += 1
    second = i + int(np.argmax(loud[i:]))
    # the RMS window trails the sound by its length; the sound starts where
    # the window's newest sample is
    return first / rate, second / rate


def audit(x: np.ndarray, rate: int) -> str:
    """What a phone speaker keeps: the levels after a 4th-order 200 Hz
    high-pass, and how the energy splits around the speaker's band."""
    f = np.fft.rfftfreq(len(x), 1 / rate)
    spec = np.fft.rfft(x)
    y = np.fft.irfft(spec / np.sqrt(1 + (200 / np.maximum(f, 1e-6)) ** 8), len(x))
    power = np.abs(spec) ** 2
    share = lambda a, b: power[(f >= a) & (f < b)].sum() / power.sum()
    db = lambda v: 20 * np.log10(max(float(v), 1e-9))
    s1, s2 = onsets(x, rate)
    win = int(0.05 * rate)
    peak = lambda at: np.abs(y[int(at * rate):int(at * rate) + win]).max()
    return (f"peak {db(np.abs(x).max()):.1f} dBFS; after a 200 Hz high-pass: lub {db(peak(s1)):.1f}, "
            f"dub {db(peak(s2)):.1f} dBFS peak; energy under 150 Hz {share(0, 150):.0%}, "
            f"150-600 Hz {share(150, 600):.0%}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=str(OUT))
    parser.add_argument("--m4a", help="also write an AAC copy here, to listen to")
    parser.add_argument("--wav", help="also write a WAV copy here")
    parser.add_argument("--measure", help="only measure this .caf or .wav")
    parser.add_argument("--audit", action="store_true", help="with --measure: what a phone speaker keeps")
    args = parser.parse_args()
    if args.measure:
        x, rate = read(Path(args.measure))
        s1, s2 = onsets(x, rate)
        print(f"S1 {s1:.4f} s, S2 {s2:.4f} s, length {len(x) / rate:.4f} s")
        if args.audit:
            print(audit(x, rate))
        return 0
    x = heartbeat()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    write_caf(out / "heartbeat.caf", x)
    (out / "Contents.json").write_text(
        '{\n  "data" : [\n    {\n      "filename" : "heartbeat.caf",\n'
        '      "idiom" : "universal",\n      "universal-type-identifier" : "com.apple.coreaudio-format"\n'
        '    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    s1, s2 = onsets(*read(out / "heartbeat.caf"))
    print(f"{out}/heartbeat.caf: S1 {s1:.4f} s, S2 {s2:.4f} s, length {len(x) / RATE:.4f} s")
    print(audit(*read(out / "heartbeat.caf")))
    if args.wav or args.m4a:
        wav = Path(args.wav or str(Path(args.m4a).with_suffix(".wav")))
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
            w.writeframes(np.round(x * 32767).astype("<i2").tobytes())
        if args.m4a:
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac",
                            "-b:a", "160k", "-movflags", "+faststart", args.m4a], check=True)
            print(args.m4a)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
