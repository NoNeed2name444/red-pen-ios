#!/usr/bin/env python3
"""Draw CramDown's app icon.

Kept as a script rather than as a binary blob nobody can edit: an icon that can
be regenerated is one that can be adjusted. Change a number here and the whole
set comes out consistent - the composed icon, and the flat layers that an
iOS 26 layered icon is assembled from.

    python3 tools/make_icon.py                 # into the asset catalogue
    python3 tools/make_icon.py --out /tmp/x    # somewhere else, to look first

The design: a flat scarlet tile with one soft white exam paper lit from above.
All of the depth is in the object and none in the background, because a busy
ground competes with the thing it is meant to be showing. The lines on the page
get shorter as they descend and the last is struck in pale blue - the name
doing its work inside the picture rather than beside it.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
GROUND = ((226, 62, 48), (192, 36, 32))       # scarlet, deeper at the foot
GROUND_DARK = ((122, 24, 22), (72, 12, 14))   # the same red, turned down
ACCENT = (140, 200, 240)                      # the one cool mark on the page
RULE = (150, 162, 184)                        # the writing: grey, never black


def ground(stops=GROUND) -> Image.Image:
    top, foot = stops
    img = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(img)
    for y in range(S):
        t = y / S
        draw.line([(0, y), (S, y)],
                  fill=tuple(int(top[k] + (foot[k] - top[k]) * t) for k in range(3)))
    return img.convert("RGBA")


def sheet_mask(back: int) -> Image.Image:
    """One sheet of paper. `back` is how far behind the front one it sits."""
    pad = int(S * 0.030 * back)
    lift = int(S * 0.040 * back)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [int(S * 0.275) + pad, int(S * 0.205) + pad - lift,
         int(S * 0.725) - pad, int(S * 0.815) - lift],
        radius=int(S * 0.075), fill=255)
    return mask


def inflate(mask: Image.Image, shade=(196, 204, 216)) -> Image.Image:
    """Turn a flat silhouette into something that looks blown up like a pillow.

    A blurred copy of the mask is treated as a height map: the middle of the
    shape is tall and reads as white, the edges fall away into a cool grey.
    That height, nudged up and to the left and subtracted from itself, gives
    the highlight along the top edge - which is what makes a soft object look
    lit rather than merely rounded - and the opposite nudge gives the shadow
    that gathers under the bottom edge.
    """
    height = mask.filter(ImageFilter.GaussianBlur(S * 0.052))
    lit = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)),
                          Image.new("RGB", (S, S), shade),
                          height.point(lambda v: min(255, int(v * 1.35))))
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(lit, (0, 0), mask)

    spec = ImageChops.subtract(height, ImageChops.offset(height, int(S * 0.012), int(S * 0.016)))
    spec = spec.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: min(255, int(v * 2.2)))
    body = Image.alpha_composite(body, Image.composite(
        Image.new("RGBA", (S, S), (255, 255, 255, 255)),
        Image.new("RGBA", (S, S), (0, 0, 0, 0)),
        ImageChops.multiply(spec, mask)))

    occ = ImageChops.subtract(ImageChops.offset(height, -int(S * 0.010), -int(S * 0.014)), height)
    occ = occ.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: min(255, int(v * 1.5)))
    return Image.alpha_composite(body, Image.composite(
        Image.new("RGBA", (S, S), (70, 84, 108, 140)),
        Image.new("RGBA", (S, S), (0, 0, 0, 0)),
        ImageChops.multiply(occ, mask)))


def writing(mono: bool = False) -> Image.Image:
    box = (int(S * 0.275), int(S * 0.205), int(S * 0.725), int(S * 0.815))
    x0, y0, x1, y1 = box
    width, middle = x1 - x0, (x0 + x1) // 2
    thickness = int(S * 0.028)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for i, (ratio, top) in enumerate(zip([0.62, 0.50, 0.38], [0.26, 0.42, 0.58])):
        w = int(width * ratio)
        y = int(y0 + (y1 - y0) * top)
        draw.rounded_rectangle([middle - w // 2, y, middle + w // 2, y + thickness],
                               radius=thickness // 2, fill=RULE + (230 - 30 * i,))
    w = int(width * 0.24)
    y = int(y0 + (y1 - y0) * 0.745)
    draw.rounded_rectangle([middle - w // 2, y, middle + w // 2, y + thickness],
                           radius=thickness // 2,
                           fill=((120, 128, 146) if mono else ACCENT) + (255,))
    return layer


def foreground(sheets: int = 2, mono: bool = False, flat: bool = False) -> Image.Image:
    """Everything that sits ON the tile, with its own transparency.

    This is the layer an iOS 26 layered icon wants: no background, and no baked
    tile shadow, because the system draws that itself.
    """
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for back in range(sheets - 1, -1, -1):
        mask = sheet_mask(back)
        front = back == 0
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        shadow.paste((12, 20, 40, 150 if front else 105),
                     (0, int(S * (0.030 if front else 0.018))), mask)
        out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(S * 0.030)))
        body = inflate(mask, shade=(196, 204, 216) if front else (168, 178, 196))
        if not front:
            body = Image.blend(Image.new("RGBA", (S, S), (0, 0, 0, 0)), body, 0.82)
        out = Image.alpha_composite(out, body)
    out = Image.alpha_composite(out, writing(mono=mono))
    if flat:
        # No cast shadow in the layered and Clear appearances: the system draws
        # the shadow itself, and a second one baked into the art is the classic
        # way a layered icon ends up looking dirty.
        out = Image.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 0)), out)
    return out


def composed(stops=GROUND, mono: bool = False) -> Image.Image:
    """The icon as one flat square, for the classic single-image slot."""
    return Image.alpha_composite(ground(stops), foreground(mono=mono)).convert("RGB")


def clear(dark: bool) -> Image.Image:
    """The Clear appearance: no ground of our own, and no colour.

    In this mode iOS makes the icon out of the wallpaper behind it - the art
    is a stencil the system frosts, so anything coloured here comes out wrong.
    What is shipped is the shape in white, with its own internal shading kept
    (that is what stops the paper reading as a flat rectangle) and the writing
    knocked through it: on a light wallpaper the page is drawn dark, on a dark
    one it is drawn light.
    """
    art = foreground(mono=True, flat=True)
    if not dark:
        grey, alpha = art.convert("L"), art.split()[3]
        art = Image.merge("RGBA", (ImageChops.invert(grey),) * 3 + (alpha,))
    return art


def tinted() -> Image.Image:
    """The Tinted appearance: one hue chosen by the user, so ship grey."""
    return Image.alpha_composite(ground(((58, 58, 62), (28, 28, 32))),
                                 foreground(mono=True)).convert("RGB")


def rounded_preview(stops=GROUND) -> Image.Image:
    """Only for looking at: the squircle the system applies, faked."""
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(composed(stops).convert("RGBA"), (0, 0), mask)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default="ios/RedPen/Assets.xcassets/AppIcon.appiconset",
                        help="where the icon itself goes")
    parser.add_argument("--layers", default="design/icon",
                        help="the flat layers and the appearances that are not\n"
                             "expressible in an asset catalogue")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    composed().save(out / "icon-1024.png")
    composed(GROUND_DARK).save(out / "icon-1024-dark.png")
    tinted().save(out / "icon-1024-tinted.png")

    # An asset catalogue can carry three of the appearances. Dark is a real
    # design decision rather than a filter: the same scarlet turned right down,
    # so a home screen at night is not one glowing red square among dark ones.
    # Tinted must be greyscale, because the hue is the user's to choose.
    (out / "Contents.json").write_text(json.dumps({
        "images": [
            {"idiom": "universal", "platform": "ios", "size": "1024x1024",
             "filename": "icon-1024.png"},
            {"idiom": "universal", "platform": "ios", "size": "1024x1024",
             "filename": "icon-1024-dark.png",
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
            {"idiom": "universal", "platform": "ios", "size": "1024x1024",
             "filename": "icon-1024-tinted.png",
             "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
        ],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")

    layers = Path(args.layers)
    layers.mkdir(parents=True, exist_ok=True)
    ground().convert("RGB").save(layers / "background.png")
    ground(GROUND_DARK).convert("RGB").save(layers / "background-dark.png")
    foreground(flat=True).save(layers / "foreground.png")
    foreground(mono=True, flat=True).save(layers / "foreground-tinted.png")
    # Clear has no catalogue slot at all - it belongs to a layered .icon - so
    # it is exported here, ready for whoever assembles one.
    clear(dark=False).save(layers / "clear-light.png")
    clear(dark=True).save(layers / "clear-dark.png")
    rounded_preview().save(layers / "preview.png")
    rounded_preview(GROUND_DARK).save(layers / "preview-dark.png")

    for name in ("icon-1024.png", "icon-1024-dark.png", "icon-1024-tinted.png"):
        print(out / name)
    print(f"{layers}/ background, background-dark, foreground, foreground-tinted,")
    print(f"{layers}/ clear-light, clear-dark, preview, preview-dark")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
