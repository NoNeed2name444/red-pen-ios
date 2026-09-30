#!/usr/bin/env python3
"""Make Stethoscore's app icon set from the master render.

The icon is a picture, not a drawing: the render the owner chose, a glossy
blue stethoscope with an A+ on its diaphragm on a sky-to-royal-blue tile,
kept at design/icon/source.png. This script turns that one file into what the
app needs and changes nothing about the picture itself:

    python3 tools/make_icon.py                 # into the asset catalogue
    python3 tools/make_icon.py --out /tmp/x    # somewhere else, to look first

- It finds the tile (the blue rounded square) in the render and crops to it,
  dropping the page margin and the drop shadow around it.
- It paints the tile's own gradient into the rounded corners, because an iOS
  icon asset has to be a full opaque square: the system cuts the corners
  itself, so nothing painted there is ever seen.
- It ships that one square for every appearance. There is no separate dark or
  tinted file: iOS shows the same picture in dark mode and makes its own
  tinted version, so the icon is the render and nothing else.
- It writes the launch logo: the icon, the wordmark and the tagline on
  Midnight navy, flat, with no shadow.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
SOURCE = Path("design/icon/source.png")

# Midnight navy: the launch background (LaunchBackground.colorset).
NAVY = (10, 22, 40)
# The wordmark: "Stetho" in Clean Sheet white, "score" in the tile's sky blue
# so it reads on navy, the tagline in a quiet blue-grey.
INK = (243, 246, 249)
SKY = (95, 176, 250)
TAGLINE = (159, 176, 198)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/Library/Fonts/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]

# Files earlier versions of this script wrote and this one does not: removed
# on the way past, so a stale appearance never ships by accident.
STALE_ICON = ("icon-1024-dark.png", "icon-1024-tinted.png")
STALE_DESIGN = ("background.png", "background-dark.png", "foreground.png", "foreground-tinted.png",
                "clear-light.png", "clear-dark.png", "preview-dark.png")


# --- reading the render -----------------------------------------------------

def find_tile(arr: np.ndarray) -> tuple[int, int, int, int]:
    """The bounding box of the blue tile: the page around it is white and the
    shadow under it is grey, so blue-dominant pixels are the tile (and the
    stethoscope, which lies inside it anyway)."""
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    blue = (b > r + 40) & (b > g + 15)
    ys, xs = np.where(blue)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def square(box: tuple[int, int, int, int], limit: tuple[int, int]) -> tuple[int, int, int, int]:
    """Grow the shorter side of the box so the crop is square, centred on the
    tile; whatever falls outside the tile is filled with the gradient later."""
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    nx0 = int(round(cx - side / 2))
    ny0 = int(round(cy - side / 2))
    nx0 = max(0, min(nx0, limit[0] - side))
    ny0 = max(0, min(ny0, limit[1] - side))
    return nx0, ny0, nx0 + side, ny0 + side


def outside_mask(arr: np.ndarray) -> np.ndarray:
    """The page and shadow left in the crop: low-saturation pixels that connect
    to a corner. The flood fill is what keeps the white ear tips and the
    diaphragm face, which are pale too but sit inside the tile."""
    hi = arr.max(axis=2)
    lo = arr.min(axis=2)
    pale = (hi - lo < 30) & (hi > 190)
    # .copy(): fromarray shares the array's memory and is read-only, and
    # floodfill on a read-only image drops its writes without a word
    img = Image.fromarray(np.where(pale, 255, 0).astype(np.uint8), "L").copy()
    h, w = pale.shape
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if img.getpixel(seed) == 255:
            ImageDraw.floodfill(img, seed, 128)
    outside = np.asarray(img) == 128
    # take the anti-aliased rim of the old corner with it
    grown = Image.fromarray(np.where(outside, 255, 0).astype(np.uint8), "L")
    grown = grown.filter(ImageFilter.MaxFilter(9))
    return np.asarray(grown) > 0


def fit_gradient(arr: np.ndarray, outside: np.ndarray) -> np.ndarray:
    """The tile's colour as a smooth function of position, fitted to the pixels
    that are plainly tile: blue-dominant, bright in blue (the tubing is dark
    navy and drops out), and not the page. A quadratic in x and y follows the
    diagonal wash of the render; a second pass drops whatever did not fit,
    such as the shadows the stethoscope casts on the tile."""
    h, w, _ = arr.shape
    yy, xx = np.mgrid[0:h, 0:w]
    x = xx / (w - 1)
    y = yy / (h - 1)
    basis = np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], axis=-1)

    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    tile = (b > r + 40) & (b > g + 15) & (b > 205) & ~outside
    fitted = np.zeros_like(arr)
    for _ in range(2):
        idx = np.flatnonzero(tile.ravel())[::7]
        a = basis.reshape(-1, 6)[idx]
        for c in range(3):
            coef, *_ = np.linalg.lstsq(a, arr[..., c].ravel()[idx], rcond=None)
            fitted[..., c] = basis.reshape(-1, 6).dot(coef).reshape(h, w)
        residual = np.sqrt(((arr - fitted) ** 2).sum(axis=2))
        tile = tile & (residual < 12)
    return np.clip(fitted, 0, 255)


def master(source: Path) -> Image.Image:
    """The render as the one square iOS wants: the tile, cropped out of the
    page, its corners filled with its own gradient, at 1024 x 1024."""
    page = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
    box = square(find_tile(page), (page.shape[1], page.shape[0]))
    crop = page[box[1]:box[3], box[0]:box[2]]
    outside = outside_mask(crop)
    filled = crop.copy()
    filled[outside] = fit_gradient(crop, outside)[outside]
    img = Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8), "RGB")
    img = img.resize((S, S), Image.LANCZOS)
    x0, y0, x1, y1 = box
    print(f"tile {x1 - x0}x{y1 - y0} at ({x0},{y0}) in {source}")
    return img


def rounded(img: Image.Image, radius: float = 0.225) -> Image.Image:
    """Only for looking at: the squircle the system applies, faked."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                                           radius=int(img.size[0] * radius), fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


# --- the launch logo --------------------------------------------------------

def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def launch_logo(icon: Image.Image, scale: int = 3) -> Image.Image:
    """The first frame: icon, wordmark, tagline on Midnight navy. 300 x 240 pt.
    The icon sits flat on the navy, as it does on a home screen: no shadow."""
    w, h = 300 * scale, 240 * scale
    out = Image.new("RGBA", (w, h), NAVY + (255,))

    side = 128 * scale
    tile = rounded(icon.resize((side, side), Image.LANCZOS))
    out.alpha_composite(tile, ((w - side) // 2, 10 * scale))

    draw = ImageDraw.Draw(out)
    size = 52 * scale
    while size > 10:
        f = font(size)
        if draw.textlength("Stethoscore", font=f) <= w - 40 * scale:
            break
        size -= scale
    left = draw.textlength("Stetho", font=f)
    total = draw.textlength("Stethoscore", font=f)
    x0 = (w - total) / 2
    y0 = 152 * scale
    draw.text((x0, y0), "Stetho", font=f, fill=INK)
    draw.text((x0 + left, y0), "score", font=f, fill=SKY)

    # the tagline, tracked by hand: PIL has no letter spacing of its own
    text = "LISTEN · LEARN · SCORE"
    track = 3 * scale
    size = 12 * scale
    while size > 6:
        small = font(size)
        width = sum(draw.textlength(c, font=small) for c in text) + track * (len(text) - 1)
        if width <= w - 40 * scale:
            break
        size -= 1
    x = (w - width) / 2
    for c in text:
        draw.text((x, 214 * scale), c, font=small, fill=TAGLINE)
        x += draw.textlength(c, font=small) + track
    return out


# --- writing ----------------------------------------------------------------

def remove(folder: Path, names: tuple[str, ...]) -> None:
    for name in names:
        stale = folder / name
        if stale.exists():
            stale.unlink()
            print(f"removed {stale}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", default=str(SOURCE), help="the master render")
    parser.add_argument("--out", default="ios/RedPen/Assets.xcassets/AppIcon.appiconset",
                        help="where the icon itself goes")
    parser.add_argument("--launch", default="ios/RedPen/Assets.xcassets/LaunchLogo.imageset",
                        help="where the launch logo goes")
    parser.add_argument("--design", default="design/icon",
                        help="where the preview goes, next to the master render")
    args = parser.parse_args()

    icon = master(Path(args.source))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    icon.save(out / "icon-1024.png")
    remove(out, STALE_ICON)
    # one image for every appearance: the system reuses it in dark mode and
    # derives the tinted one itself
    (out / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024",
                    "filename": "icon-1024.png"}],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")

    launch = Path(args.launch)
    launch.mkdir(parents=True, exist_ok=True)
    big = launch_logo(icon, scale=3)
    big.save(launch / "launch-logo@3x.png")
    big.resize((600, 480), Image.LANCZOS).save(launch / "launch-logo@2x.png")
    big.resize((300, 240), Image.LANCZOS).save(launch / "launch-logo@1x.png")
    (launch / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "scale": f"{n}x", "filename": f"launch-logo@{n}x.png"}
                   for n in (1, 2, 3)],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")

    design = Path(args.design)
    design.mkdir(parents=True, exist_ok=True)
    rounded(icon).save(design / "preview.png")
    remove(design, STALE_DESIGN)

    print(out / "icon-1024.png")
    print(f"{launch}/ launch-logo@1x, @2x, @3x")
    print(f"{design}/ preview.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
