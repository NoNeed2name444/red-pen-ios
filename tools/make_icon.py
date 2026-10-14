#!/usr/bin/env python3
"""Make Stethoscore's app icon from the owner's chosen art.

The icon is a picture, not a drawing: the owner's stethoscope (14 Oct), drawn
with depth, the white tube on the pale Ward base by day and the slate tube on
the dark base by night, plus a grey-on-black version for the tinted home
screen. Those three pictures are kept in design/icon/source/ (icon-light.png,
icon-dark.png, icon-tinted.png); this script turns them into what the app
needs and changes nothing in them but their size:

    python3 tools/make_icon.py                 # into the app
    python3 tools/make_icon.py --preview DIR   # and the three looks, rounded, to check

- ios/RedPen/Assets.xcassets/AppIcon.appiconset: the light picture, a dark
  appearance (luminosity dark) and a tinted one (luminosity tinted), each a
  full opaque 1024 square (the system cuts the corners).
- ios/AppResources/AppIcon.icon (the iOS 26 layered icon, which Xcode 26
  uses): one layer, the picture, swapped per appearance with
  image-name-specializations, over a flat fill of the matching Ward base
  (fill-specializations for dark). The art carries its own depth, highlights
  and shadows, so Liquid Glass's specular and shadow are off and the layer
  is not glass.
- design/icon/preview.png: light, dark and tinted side by side, rounded.

The launch screen's mark is cut separately, from the flat pair, by
tools/make_launch_logo.py; the same pictures in layers (design/icon/layers, for
IconLayersView) by tools/icon_layers.py.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

S = 1024
SOURCE = Path("design/icon/source")
LOOKS = ("light", "dark", "tinted")
# the Ward base, light and dark (WardPalette .background)
FILL = {"light": (0xE0, 0xE5, 0xEC), "dark": (0x2A, 0x2E, 0x35)}
STALE_SET = ("icon-1024-light.png",)
STALE_BUNDLE = ("0-background.png", "1-metal.png", "2-tubing.png", "3-earpieces.png",
                "4-chest-piece.png", "5-a-plus.png")


def srgb(rgb: tuple[int, int, int]) -> str:
    return "srgb:" + ",".join(f"{c / 255:.5f}" for c in rgb) + ",1.00000"


def square(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGB")
    w, h = img.size
    side = min(w, h)
    img = img.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    return img.resize((S, S), Image.LANCZOS)


def rounded(img: Image.Image, radius: float = 0.2237) -> Image.Image:
    """Only for looking at: the squircle the system applies, faked."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                                           radius=int(img.size[0] * radius), fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


def icon_json() -> dict:
    return {
        "fill": {"solid": srgb(FILL["light"])},
        "fill-specializations": [
            {"value": {"solid": srgb(FILL["light"])}},
            {"appearance": "dark", "value": {"solid": srgb(FILL["dark"])}},
        ],
        "groups": [
            {
                "layers": [
                    {
                        "glass": False,
                        "image-name": "icon-light.png",
                        "image-name-specializations": [
                            {"value": "icon-light.png"},
                            {"appearance": "dark", "value": "icon-dark.png"},
                            {"appearance": "tinted", "value": "icon-tinted.png"},
                        ],
                        "name": "stethoscope",
                    }
                ],
                "name": "Stethoscope",
                "shadow": {"kind": "none", "opacity": 0},
                "specular": False,
                "translucency": {"enabled": False, "value": 0},
            }
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }


def remove(folder: Path, names: tuple[str, ...]) -> None:
    for name in names:
        stale = folder / name
        if stale.exists():
            stale.unlink()
            print(f"removed {stale}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", default=str(SOURCE), help="icon-light/-dark/-tinted.png")
    parser.add_argument("--set", default="ios/RedPen/Assets.xcassets/AppIcon.appiconset")
    parser.add_argument("--bundle", default="ios/AppResources/AppIcon.icon")
    parser.add_argument("--design", default="design/icon", help="where preview.png goes")
    parser.add_argument("--preview", help="also write app-icon-<look>.png here")
    args = parser.parse_args()

    pics = {look: square(Path(args.source) / f"icon-{look}.png") for look in LOOKS}

    folder = Path(args.set)
    folder.mkdir(parents=True, exist_ok=True)
    names = {"light": "icon-1024.png", "dark": "icon-1024-dark.png", "tinted": "icon-1024-tinted.png"}
    images = []
    for look in LOOKS:
        pics[look].save(folder / names[look], optimize=True)
        entry = {"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": names[look]}
        if look != "light":
            entry["appearances"] = [{"appearance": "luminosity", "value": look}]
        images.append(entry)
    remove(folder, STALE_SET)
    (folder / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    bundle = Path(args.bundle)
    (bundle / "Assets").mkdir(parents=True, exist_ok=True)
    for look in LOOKS:
        pics[look].save(bundle / "Assets" / f"icon-{look}.png", optimize=True)
    remove(bundle / "Assets", STALE_BUNDLE)
    (bundle / "icon.json").write_text(json.dumps(icon_json(), indent=2) + "\n")

    sheet = Image.new("RGBA", (S * 3 + 80, S + 40), (128, 128, 128, 255))
    for i, look in enumerate(LOOKS):
        sheet.alpha_composite(rounded(pics[look]), (20 + i * (S + 20), 20))
    Path(args.design).mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS).save(
        Path(args.design) / "preview.png", optimize=True)
    if args.preview:
        out = Path(args.preview)
        out.mkdir(parents=True, exist_ok=True)
        for look in LOOKS:
            rounded(pics[look]).resize((512, 512), Image.LANCZOS).save(out / f"app-icon-{look}.png")

    print(f"{folder}/ {', '.join(names.values())}")
    print(f"{bundle}/ icon.json, Assets/icon-light, -dark, -tinted")
    print(f"{args.design}/preview.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
