#!/usr/bin/env python3
"""Make Stethoscore's app icon set from the master render.

The icon is a picture, not a drawing: a glossy blue stethoscope with an A+ on
its diaphragm, on a sky-to-royal-blue tile. The render the owner chose is kept
at design/icon/source.png, and this script turns that one file into everything
the app needs, so a new render is a one-file swap and the whole set comes out
consistent:

    python3 tools/make_icon.py                 # into the asset catalogue
    python3 tools/make_icon.py --out /tmp/x    # somewhere else, to look first

What it does with the render:
- finds the tile (the blue rounded square), crops to it and throws away the
  page margin and the drop shadow around it;
- fits the tile's gradient and paints it into the rounded corners, because an
  iOS icon asset has to be a full opaque square (the system cuts the corners);
- separates the stethoscope from the tile by how far each pixel sits from that
  fitted gradient, which is what gives the Dark, Tinted, Clear and layered
  appearances without a second render;
- writes the launch logo: the icon, the wordmark and the tagline on Midnight
  navy, the same picture LaunchSplash carries into the first SwiftUI frame.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
SOURCE = Path("design/icon/source.png")

# Midnight navy: the launch background (LaunchBackground.colorset) and the
# ground of the Dark appearance.
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


def object_alpha(arr: np.ndarray, fitted: np.ndarray, outside: np.ndarray) -> np.ndarray:
    """How much of each pixel is stethoscope rather than tile, from its
    distance to the fitted gradient. The ramp starts high on purpose: the
    shadows the stethoscope casts are only darker tile, and counting them as
    object is what puts a glowing halo round it on the dark and tinted
    grounds. The tubing, chrome and white sit far beyond the ramp."""
    d = np.sqrt(((arr - fitted) ** 2).sum(axis=2))
    a = np.clip((d - 45.0) / (90.0 - 45.0), 0.0, 1.0)
    a[outside] = 0.0
    img = Image.fromarray((a * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.8))
    return np.asarray(img).astype(np.float32) / 255.0


def unmix(arr: np.ndarray, fitted: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """The object's own colour at its soft edges, with the tile colour that was
    blended into them taken back out; otherwise a pale-blue fringe follows the
    tubing onto the dark and tinted grounds."""
    a = alpha[..., None]
    # only where the pixel is mostly object: dividing by a small alpha turns
    # a highlight a shade lighter than the tile into an orange speck
    mostly = a > 0.35
    safe = np.where(mostly, a, 1.0)
    own = (arr - (1.0 - a) * fitted) / safe
    own = np.where(mostly, own, arr)
    return np.clip(own, 0, 255)


# --- the appearances --------------------------------------------------------

def to_image(rgb: np.ndarray, alpha: np.ndarray | None = None) -> Image.Image:
    rgb8 = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        return Image.fromarray(rgb8, "RGB")
    a8 = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb8, a8]), "RGBA")


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


class Icon:
    def __init__(self, source: Path):
        page = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
        box = square(find_tile(page), (page.shape[1], page.shape[0]))
        crop = page[box[1]:box[3], box[0]:box[2]]
        outside = outside_mask(crop)
        fitted = fit_gradient(crop, outside)
        filled = crop.copy()
        filled[outside] = fitted[outside]
        alpha = object_alpha(crop, fitted, outside)
        own = unmix(filled, fitted, alpha)

        def at(a: np.ndarray, mode: str = "RGB") -> np.ndarray:
            img = to_image(a) if a.shape[-1] == 3 else Image.fromarray((a * 255).astype(np.uint8), "L")
            return np.asarray(img.resize((S, S), Image.LANCZOS)).astype(np.float32)

        self.light = at(filled)
        self.ground = at(fitted)
        self.alpha = at(alpha) / 255.0
        self.own = at(own)
        self.box = box

    # the Dark appearance: the same wash turned down to navy, the stethoscope
    # kept, its blue tubing lifted a little so it still separates from the tile
    def dark(self) -> np.ndarray:
        ground = self.dark_ground()
        # the tile and the shadows on it darken together, by the same ratio,
        # so a shadow stays a shadow instead of turning into a pale rim
        ratio = np.clip(ground / np.maximum(self.ground, 1.0), 0.0, 1.2)
        shaded = np.clip(self.light * ratio, 0, 255)
        own = self.own.copy()
        r, g, b = own[..., 0], own[..., 1], own[..., 2]
        tubing = ((b > r + 40) & (b > g + 15))[..., None]
        own = np.where(tubing, np.clip(own * 1.28, 0, 255), own)
        a = self.alpha[..., None]
        return a * own + (1 - a) * shaded

    def dark_ground(self) -> np.ndarray:
        return self.ground * 0.30 + np.array(NAVY, dtype=np.float32) * 0.55

    # the Tinted appearance: the system supplies the hue, so ship the shape in
    # grey on black, which is what iOS wants under its tint
    def tinted(self) -> np.ndarray:
        grey = np.clip(luminance(self.own) * 1.12, 0, 255)[..., None].repeat(3, axis=2)
        a = self.alpha[..., None]
        return a * grey + (1 - a) * np.zeros_like(grey)

    def foreground(self, mono: bool = False) -> Image.Image:
        rgb = self.own
        if mono:
            rgb = luminance(self.own)[..., None].repeat(3, axis=2)
        return to_image(rgb, self.alpha)

    # the Clear appearance is a stencil the system frosts out of the wallpaper:
    # light shape for a dark wallpaper, dark shape for a light one
    def clear(self, dark: bool) -> Image.Image:
        grey = luminance(self.own)
        if not dark:
            grey = 255 - grey
        return to_image(grey[..., None].repeat(3, axis=2), self.alpha)


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
    """The first frame: icon, wordmark, tagline on Midnight navy. 300 x 240 pt."""
    w, h = 300 * scale, 240 * scale
    out = Image.new("RGBA", (w, h), NAVY + (255,))

    side = 128 * scale
    tile = rounded(icon.resize((side, side), Image.LANCZOS))
    x, y = (w - side) // 2, 10 * scale
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (x, y + 4 * scale), tile.split()[3])
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(8 * scale)))
    out.alpha_composite(tile, (x, y))

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
    text = "LISTEN \u00B7 LEARN \u00B7 SCORE"
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

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", default=str(SOURCE), help="the master render")
    parser.add_argument("--out", default="ios/RedPen/Assets.xcassets/AppIcon.appiconset",
                        help="where the icon itself goes")
    parser.add_argument("--launch", default="ios/RedPen/Assets.xcassets/LaunchLogo.imageset",
                        help="where the launch logo goes")
    parser.add_argument("--layers", default="design/icon",
                        help="the flat layers and the appearances that are not\n"
                             "expressible in an asset catalogue")
    args = parser.parse_args()

    icon = Icon(Path(args.source))
    light = to_image(icon.light)
    dark = to_image(icon.dark())

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    light.save(out / "icon-1024.png")
    dark.save(out / "icon-1024-dark.png")
    to_image(icon.tinted()).save(out / "icon-1024-tinted.png")
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

    launch = Path(args.launch)
    launch.mkdir(parents=True, exist_ok=True)
    big = launch_logo(light, scale=3)
    big.save(launch / "launch-logo@3x.png")
    big.resize((600, 480), Image.LANCZOS).save(launch / "launch-logo@2x.png")
    big.resize((300, 240), Image.LANCZOS).save(launch / "launch-logo@1x.png")
    (launch / "Contents.json").write_text(json.dumps({
        "images": [{"idiom": "universal", "scale": f"{n}x", "filename": f"launch-logo@{n}x.png"}
                   for n in (1, 2, 3)],
        "info": {"version": 1, "author": "xcode"},
    }, indent=2) + "\n")

    layers = Path(args.layers)
    layers.mkdir(parents=True, exist_ok=True)
    to_image(icon.ground).save(layers / "background.png")
    to_image(icon.dark_ground()).save(layers / "background-dark.png")
    icon.foreground().save(layers / "foreground.png")
    icon.foreground(mono=True).save(layers / "foreground-tinted.png")
    icon.clear(dark=False).save(layers / "clear-light.png")
    icon.clear(dark=True).save(layers / "clear-dark.png")
    rounded(light).save(layers / "preview.png")
    rounded(dark).save(layers / "preview-dark.png")

    x0, y0, x1, y1 = icon.box
    print(f"tile {x1 - x0}x{y1 - y0} at ({x0},{y0}) in {args.source}")
    for name in ("icon-1024.png", "icon-1024-dark.png", "icon-1024-tinted.png"):
        print(out / name)
    print(f"{launch}/ launch-logo@1x, @2x, @3x")
    print(f"{layers}/ background, background-dark, foreground, foreground-tinted,")
    print(f"{layers}/ clear-light, clear-dark, preview, preview-dark")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
