#!/usr/bin/env python3
"""Draw home's ECG paper as a picture, for the launch screen and the opening.

The home screen stands on ECG paper: the Ward base with a grid of fine lines
every 6 points and a bolder one every fifth, counted from the window's top
left corner (WardPaper and WardPaperInk.drawPaper in the app). The system
launch screen (AppResources/LaunchScreen.storyboard) can only show pictures,
so this draws the same paper, line for line, as the LaunchPaper image set; the
launch screen pins it to the screen's top left at its own size, and the
opening (LaunchSplash) lays the same picture the same way, so from the first
frame to home at rest the ground is one paper and never changes:

    python3 tools/make_launch_paper.py                   # into the asset catalogue
    python3 tools/make_launch_paper.py --preview DIR     # and a corner of each, enlarged

The ink, the cell and the line come from ios/RedPen/Shared/Ward/WardRelief.swift
(WardPaper), read from the source so the two cannot drift apart; the base is
the LaunchBackground colour. Lines are laid as the app lays them: the down
lines first, each its fine ink and then, on every fifth, the bold over it,
then the across lines the same way, each a solid point-wide band over what is
under it.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

SET = Path("ios/RedPen/Assets.xcassets/LaunchPaper.imageset")
RELIEF = Path("ios/RedPen/Shared/Ward/WardRelief.swift")
BASE = Path("ios/RedPen/Assets.xcassets/LaunchBackground.colorset/Contents.json")

# The picture's size in points, larger than any screen of its kind in
# either orientation, so it always reaches past the far edges.
SIZES = {"iphone": ((480, 1040), (2, 3)), "ipad": ((1400, 1400), (2,))}


def paper_numbers() -> dict:
    src = RELIEF.read_text()
    def num(name: str) -> float:
        m = re.search(rf"static let {name} = ([0-9.]+)", src)
        if not m:
            raise SystemExit(f"WardPaper.{name} not found in {RELIEF}")
        return float(m.group(1))
    ink = re.search(r"WardPaperInk\(hex: dark \? 0x([0-9A-Fa-f]{6}) : 0x([0-9A-Fa-f]{6}),\s*"
                    r"fine: highContrast \? 0 : \(dark \? ([0-9.]+) : ([0-9.]+)\),\s*"
                    r"bold: highContrast \? 0 : \(dark \? ([0-9.]+) : ([0-9.]+)\)", src)
    if not ink:
        raise SystemExit(f"WardPaper.ink not found in {RELIEF}")
    hexes = {True: ink.group(1), False: ink.group(2)}
    return {
        "cell": num("cell"), "line": num("line"), "every": int(num("boldEvery")),
        "ink": {d: tuple(int(hexes[d][i:i + 2], 16) for i in (0, 2, 4)) for d in (False, True)},
        "fine": {True: float(ink.group(3)), False: float(ink.group(4))},
        "bold": {True: float(ink.group(5)), False: float(ink.group(6))},
    }


def base_colour(dark: bool) -> tuple[int, int, int]:
    doc = json.loads(BASE.read_text())
    for entry in doc["colors"]:
        is_dark = any(a.get("value") == "dark" for a in entry.get("appearances", []))
        if is_dark == dark:
            c = entry["color"]["components"]
            def ch(v: str) -> int:
                return int(v, 16) if v.startswith("0x") else round(float(v) * 255) if "." in v else int(v)
            return ch(c["red"]), ch(c["green"]), ch(c["blue"])
    raise SystemExit(f"no {'dark' if dark else 'light'} LaunchBackground in {BASE}")


def draw(size_pt: tuple[int, int], scale: int, dark: bool, p: dict) -> Image.Image:
    w, h = size_pt[0] * scale, size_pt[1] * scale
    out = np.empty((h, w, 3), dtype=np.float64)
    out[:] = base_colour(dark)
    ink = np.array(p["ink"][dark], dtype=np.float64)
    fine, bold = p["fine"][dark], p["bold"][dark]
    lw = int(round(p["line"] * scale))
    def lay(region: np.ndarray, alpha: float) -> None:
        region[:] = region * (1 - alpha) + ink * alpha
    for axis in ("down", "across"):
        length = size_pt[0] if axis == "down" else size_pt[1]
        k = 0
        while k * p["cell"] < length:
            at = int(round(k * p["cell"] * scale))
            strip = out[:, at:at + lw] if axis == "down" else out[at:at + lw, :]
            if fine > 0:
                lay(strip, fine)
            if k % p["every"] == 0 and bold > 0:
                lay(strip, bold)
            k += 1
    return Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    p = paper_numbers()
    SET.mkdir(parents=True, exist_ok=True)
    for old in SET.glob("*.png"):
        old.unlink()
    images = []
    for idiom, (size, scales) in SIZES.items():
        for dark in (False, True):
            for s in scales:
                name = f"paper-{idiom}{'-dark' if dark else ''}@{s}x.png"
                draw(size, s, dark, p).save(SET / name, optimize=True)
                entry = {"idiom": idiom, "scale": f"{s}x", "filename": name}
                if dark:
                    entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
                images.append(entry)
                if args.preview:
                    args.preview.mkdir(parents=True, exist_ok=True)
                    corner = Image.open(SET / name).crop((0, 0, 60 * s, 60 * s))
                    corner.resize((corner.width * 4 // s, corner.height * 4 // s), Image.NEAREST) \
                        .save(args.preview / name)
    (SET / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
    for f in sorted(SET.glob("*.png")):
        print(f"{f}: {f.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
