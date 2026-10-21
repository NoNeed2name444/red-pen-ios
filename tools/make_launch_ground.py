#!/usr/bin/env python3
"""Draw home's ground as a picture, for the launch screen's first frame.

Home stands on its section's ground (WardGround in the app): the Ward base
with the section's wash (WardSection.wash: the base mixed toward the
section's fill in linear light) and the ECG paper's grid over it, in the
section's ink at the mode's strengths, a fine line every 6 points and a bold
one every fifth, counted from the window's top left (WardPaper,
WardPaperInk.drawPaper). The system launch screen
(AppResources/LaunchScreen.storyboard) can only show pictures, so this draws
that ground, line for line, for the section home opens on
(WardSection.opening), as the LaunchPaper image set: the launch screen pins
it to the screen's top left at its own size, and from its first Swift frame
the opening (LaunchSplash) draws the same ground live, so from the first
frame to home at rest the ground is one and never changes:

    python3 tools/make_launch_ground.py                # into the asset catalogue
    python3 tools/make_launch_ground.py --preview DIR  # and a corner of each, enlarged
    python3 tools/make_launch_ground.py --table        # every section's ground, as JSON

Every number is read from the Swift sources, so the two cannot drift apart:
the base from WardPalette.swift, each section's fill and ink and the wash's
strength from WardLook.swift, the paper's cell, line and ink strengths from
WardRelief.swift. The colours are mixed as WardPalette.mix mixes them. Each
picture carries the ground it was drawn with in a text chunk ("WardGround"),
which WardLookTests reads back and checks against home's. The iPhone's
picture is drawn at 2x and 3x and the iPad's at 2x, so no line is scaled.
Lines are laid as the app lays them: the down lines first, each its fine ink
and then, on every fifth, the bold over it, then the across lines the same
way, each a solid point-wide band over what is under it.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

SET = Path("ios/RedPen/Assets.xcassets/LaunchPaper.imageset")
PALETTE = Path("ios/RedPen/Shared/Ward/WardPalette.swift")
LOOK = Path("ios/RedPen/Shared/Ward/WardLook.swift")
RELIEF = Path("ios/RedPen/Shared/Ward/WardRelief.swift")

# The picture's size in points, larger than any screen of its kind in
# portrait, so it always reaches past the far edges.
SIZES = {"iphone": ((480, 1040), (2, 3)), "ipad": ((1400, 1400), (2,))}


def _hexes(text: str) -> tuple[int, int]:
    a, b = re.findall(r"0x([0-9A-Fa-f]{6})", text)[:2]
    return int(a, 16), int(b, 16)


def sources() -> dict:
    palette, look, relief = PALETTE.read_text(), LOOK.read_text(), RELIEF.read_text()
    bg = re.search(r"\.background:\s*\((0x[0-9A-Fa-f]{6}),\s*(0x[0-9A-Fa-f]{6})\)", palette)
    if not bg:
        raise SystemExit(f"the base (.background) not found in {PALETTE}")
    sections = {}
    for m in re.finditer(r"\.(\w+): WardSectionColours\(hue: [0-9.]+, ink: (\([^)]*\)), "
                         r"accent: \([^)]*\), fill: (\([^)]*\))\)", look):
        sections[m.group(1)] = {"ink": _hexes(m.group(2)), "fill": _hexes(m.group(3))}
    if not sections:
        raise SystemExit(f"WardSection.table not found in {LOOK}")
    wash = re.search(r"func wash\(dark: Bool\) -> UInt32 \{[^}]*?let t = dark \? ([0-9.]+) : ([0-9.]+)", look, re.S)
    opening = re.search(r"static let opening: WardSection = \.(\w+)", look)
    if not wash or not opening:
        raise SystemExit(f"the wash's strength or WardSection.opening not found in {LOOK}")

    def num(name: str) -> float:
        m = re.search(rf"static let {name} = ([0-9.]+)", relief)
        if not m:
            raise SystemExit(f"WardPaper.{name} not found in {RELIEF}")
        return float(m.group(1))
    ink = re.search(r"fine: highContrast \? 0 : \(dark \? ([0-9.]+) : ([0-9.]+)\),\s*"
                    r"bold: highContrast \? 0 : \(dark \? ([0-9.]+) : ([0-9.]+)\)", relief)
    if not ink:
        raise SystemExit(f"WardPaper.ink's strengths not found in {RELIEF}")
    return {
        "base": {False: int(bg.group(1), 16), True: int(bg.group(2), 16)},
        "sections": sections,
        "wash": {True: float(wash.group(1)), False: float(wash.group(2))},
        "opening": opening.group(1),
        "cell": num("cell"), "line": num("line"), "every": int(num("boldEvery")),
        "fine": {True: float(ink.group(1)), False: float(ink.group(2))},
        "bold": {True: float(ink.group(3)), False: float(ink.group(4))},
    }


def mix(a: int, b: int, t: float) -> int:
    """WardPalette.mix: part way from a to b in linear light."""
    t = min(1.0, max(0.0, t))

    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def gamma(c: float) -> float:
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

    out = 0
    for shift in (16, 8, 0):
        x, y = ((a >> shift) & 0xFF) / 255, ((b >> shift) & 0xFF) / 255
        v = gamma(linear(x) + (linear(y) - linear(x)) * t)
        # Swift's rounded(): half away from zero
        out |= int(math.floor(min(1.0, max(0.0, v)) * 255 + 0.5)) << shift
    return out


def ground(src: dict, section: str, dark: bool) -> dict:
    """WardGround.home(section, dark:) at the standard contrast."""
    colours = src["sections"][section]
    base = mix(src["base"][dark], colours["fill"][1 if dark else 0], src["wash"][dark])
    return {"base": base, "ink": colours["ink"][1 if dark else 0],
            "fine": src["fine"][dark], "bold": src["bold"][dark]}


def label(g: dict) -> str:
    return f"base=#{g['base']:06X} ink=#{g['ink']:06X} fine={g['fine']:g} bold={g['bold']:g}"


def draw(size_pt: tuple[int, int], scale: int, g: dict, src: dict):
    import numpy as np
    from PIL import Image
    w, h = size_pt[0] * scale, size_pt[1] * scale
    out = np.empty((h, w, 3), dtype=np.float64)
    out[:] = [(g["base"] >> s) & 0xFF for s in (16, 8, 0)]
    ink = np.array([(g["ink"] >> s) & 0xFF for s in (16, 8, 0)], dtype=np.float64)
    lw = int(round(src["line"] * scale))

    def lay(region, alpha: float) -> None:
        region[:] = region * (1 - alpha) + ink * alpha
    for axis in ("down", "across"):
        length = size_pt[0] if axis == "down" else size_pt[1]
        k = 0
        while k * src["cell"] < length:
            at = int(round(k * src["cell"] * scale))
            strip = out[:, at:at + lw] if axis == "down" else out[at:at + lw, :]
            if g["fine"] > 0:
                lay(strip, g["fine"])
            if k % src["every"] == 0 and g["bold"] > 0:
                lay(strip, g["bold"])
            k += 1
    return Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--preview", type=Path)
    ap.add_argument("--table", action="store_true", help="print every section's ground as JSON and stop")
    args = ap.parse_args()
    src = sources()
    if args.table:
        print(json.dumps({
            "opening": src["opening"],
            "sections": {s: {("dark" if d else "light"): {**ground(src, s, d),
                                                          "base": f"{ground(src, s, d)['base']:06X}",
                                                          "ink": f"{ground(src, s, d)['ink']:06X}"}
                             for d in (False, True)} for s in src["sections"]},
        }, indent=1, sort_keys=True))
        return
    from PIL import Image, PngImagePlugin
    SET.mkdir(parents=True, exist_ok=True)
    for old in SET.glob("*.png"):
        old.unlink()
    images = []
    for idiom, (size, scales) in SIZES.items():
        for dark in (False, True):
            g = ground(src, src["opening"], dark)
            for s in scales:
                name = f"paper-{idiom}{'-dark' if dark else ''}@{s}x.png"
                info = PngImagePlugin.PngInfo()
                info.add_text("WardGround", f"{src['opening']} {'dark' if dark else 'light'} {label(g)}")
                draw(size, s, g, src).save(SET / name, optimize=True, pnginfo=info)
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
        with Image.open(f) as im:
            print(f"{f}: {im.width}x{im.height} px, {f.stat().st_size // 1024} KB, {im.text.get('WardGround')}")


if __name__ == "__main__":
    main()
