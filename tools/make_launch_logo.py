#!/usr/bin/env python3
"""Cut the launch mark from its flat ground, for the launch screen and the opening.

The owner's stethoscope art comes as a picture on a flat ground, exactly the
home screen's base (#E0E5EC by day, #2A2E35 by night), with a soft shadow
under the mark. The launch screen draws its image on that same base colour
(LaunchBackground), and the animated opening (LaunchSplash) scales the mark
and opens a hole through it, so the image has to be the mark alone on a
clear ground that lands back on exactly the original pixels:

    python3 tools/make_launch_logo.py                   # into the asset catalogue
    python3 tools/make_launch_logo.py --preview /tmp/x  # and a check sheet

How the ground comes out (per pixel P, ground G, both known exactly):
- the least alpha that can explain P over G (the colour-to-alpha rule:
  for each channel, how far P is from G towards white or black), so the
  soft shadow becomes a soft, see-through dark and an edge's half-pixels
  stay half;
- raised to fully solid wherever P is clearly not ground (the mark itself),
  so a white tube on a pale ground is not left half see-through;
- the colour then solved from P = a.F + (1 - a).G, so laid back on G the
  image gives P again, to the rounding of a byte: no halo and no jump when
  the launch screen hands over to the opening.

The owner's pair (14 Oct): the white tube by day (02-white-flat.png) and the
slate tube by night (06-slate-flat-dark.png), written as LaunchLogo's light
and dark images, cropped the same way so the mark sits at the same place in
both modes. It measures where the chest piece is in each (as fractions of the image)
and writes that into LaunchArt.chest in ios/RedPen/Shared/LaunchOpening.swift.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GROUND = {False: (0xE0, 0xE5, 0xEC), True: (0x2A, 0x2E, 0x35)}
SIDE_PT = 200          # LaunchArt.side
SOLID = 10             # a channel this far from the ground (and not shadow) is the mark
SHADE = 0.025          # a shadow darkens every channel by this nearly the same share
HOLE = 41              # enclosed pockets narrower than this (pixels) are the mark
CLOSE = 9              # gaps inside the mark narrower than this (pixels) are closed
NOISE = 2              # this close to the ground is the ground

# The art: swapping it is replacing these two files in design/launch-logo
# and running this script, which measures the chest piece itself and writes
# it into LaunchOpening.swift.
VERSIONS = {
    "launch": {"set": "LaunchLogo", "day": "02-white-flat.png", "night": "06-slate-flat-dark.png"},
}


def cut(path: Path, dark: bool) -> np.ndarray:
    """RGBA float array, 0-255, the ground keyed out."""
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    g = np.array(GROUND[dark], dtype=np.float64)
    border = np.concatenate([img[:8].reshape(-1, 3), img[-8:].reshape(-1, 3),
                             img[:, :8].reshape(-1, 3), img[:, -8:].reshape(-1, 3)])
    off = np.abs(np.median(border, axis=0) - g).max()
    if off > 3:
        raise SystemExit(f"{path}: the ground is {np.median(border, axis=0)}, not {g} (off by {off:.0f})")
    d = img - g
    up = np.where(d > 0, d / np.maximum(255 - g, 1), 0)
    down = np.where(d < 0, -d / np.maximum(g, 1), 0)
    alpha = np.maximum(up, down).max(axis=2)
    alpha[np.abs(d).max(axis=2) <= NOISE] = 0
    # the mark itself: clearly not ground and not shadow (a shadow is the
    # ground darkened evenly in every channel), with the narrow gaps inside
    # it closed (a loop's open middle is far wider and stays clear), without
    # specks, and softened by half a pixel so it meets the keyed edge smoothly
    ratio = img / np.maximum(g, 1)
    shadow = (d.max(axis=2) < 0) & (np.abs(ratio - ratio.mean(axis=2, keepdims=True)).max(axis=2) < SHADE)
    solid = ((np.abs(d).max(axis=2) > SOLID) & ~shadow).astype(np.uint8) * 255
    solid_img = Image.fromarray(solid)
    solid_img = solid_img.filter(ImageFilter.MaxFilter(CLOSE)).filter(ImageFilter.MinFilter(CLOSE))
    solid_img = solid_img.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    solid_img = fill_holes(solid_img, HOLE)
    solid_img = solid_img.filter(ImageFilter.GaussianBlur(0.6))
    alpha = np.maximum(alpha, np.asarray(solid_img, dtype=np.float64) / 255)
    alpha = np.clip(alpha, 0, 1)
    a = alpha[..., None]
    with np.errstate(divide="ignore", invalid="ignore"):
        fg = np.where(a > 0, (img - (1 - a) * g) / a, 0)
    fg = np.clip(fg, 0, 255)
    return np.dstack([fg, alpha * 255])


def fill_holes(solid: Image.Image, wide: int) -> Image.Image:
    """Make solid every pocket of not-solid the mark encloses that is narrow
    (no disc `wide` pixels across fits in it): a highlight on the metal, a pale
    patch on a white tube. The big open middles (inside the loop, between the
    ear tubes) stay clear."""
    m = Image.eval(solid, lambda v: 0 if v > 127 else 255)   # 255 = not solid
    w, h = m.size
    for x in range(0, w, 8):                                   # the open ground
        for y in (0, h - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 100)
    for y in range(0, h, 8):
        for x in (0, w - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 100)
    a = np.asarray(m)
    pockets = Image.fromarray(np.where(a == 255, 255, 0).astype(np.uint8))
    # the wide pockets: what is left after shrinking every pocket, grown back
    # to its whole pocket by filling from what survived
    core = np.asarray(pockets.filter(ImageFilter.MinFilter(wide | 1)))
    keep = pockets.copy()
    while True:
        ys, xs = np.nonzero((core == 255) & (np.asarray(keep) == 255))
        if len(ys) == 0:
            break
        ImageDraw.floodfill(keep, (int(xs[0]), int(ys[0])), 100)
    open_ground = (a == 100) | (np.asarray(keep) == 100)
    return Image.fromarray(np.where(open_ground, 0, 255).astype(np.uint8))


def chest_piece(img: Image.Image) -> tuple[float, float, float]:
    """The chest piece's disc in a cut image, as fractions of its side
    (x, y, r): the widest solid run in the image's upper right is the disc's
    diameter (the stem and tube below are far narrower); its middle is the
    centre, and the disc's top plus half that width checks it."""
    a = np.asarray(img)[..., 3] / 255
    n = a.shape[0]
    x0 = int(0.55 * n)
    solid = a[: n // 2, x0:] > 0.9
    widths, mids = np.zeros(solid.shape[0]), np.zeros(solid.shape[0])
    for y in range(solid.shape[0]):
        xs = np.nonzero(solid[y])[0]
        if len(xs):
            run = max(np.split(xs, np.nonzero(np.diff(xs) > 1)[0] + 1), key=len)
            widths[y], mids[y] = len(run), (run[0] + run[-1]) / 2
    best = widths.max()
    rows = np.nonzero(widths >= 0.99 * best)[0]
    cx = mids[rows].mean() + x0
    cy = rows.mean()
    r = best / 2
    top = np.nonzero(a[: n // 2, int(round(cx))] > 0.9)[0].min()
    if abs((top + r) - cy) > 0.03 * n:
        raise SystemExit(f"the chest piece measures oddly: centre {cy:.0f} but top + radius {top + r:.0f}")
    return cx / n, cy / n, r / n


def bbox(rgba: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(rgba[..., 3] > 6)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def square(box, size, pad=0.05) -> tuple[int, int, int]:
    """A square around box (left, top, side), padded, inside the picture where it can be."""
    x0, y0, x1, y1 = box
    side = int(max(x1 - x0, y1 - y0) * (1 + 2 * pad))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    left = int(round(cx - side / 2)); top = int(round(cy - side / 2))
    return left, top, side


def crop(rgba: np.ndarray, left: int, top: int, side: int) -> Image.Image:
    """The square, with clear ground wherever it runs past the picture."""
    h, w = rgba.shape[:2]
    out = np.zeros((side, side, 4), dtype=np.float64)
    sx0, sy0 = max(left, 0), max(top, 0)
    sx1, sy1 = min(left + side, w), min(top + side, h)
    out[sy0 - top:sy1 - top, sx0 - left:sx1 - left] = rgba[sy0:sy1, sx0:sx1]
    # premultiplied while resizing, so the clear ground does not darken edges
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def resized(img: Image.Image, px: int) -> Image.Image:
    pre = np.asarray(img, dtype=np.float64)
    a = pre[..., 3:4] / 255
    pm = Image.fromarray(np.round(np.dstack([pre[..., :3] * a, pre[..., 3]])).astype(np.uint8), "RGBA")
    small = np.asarray(pm.resize((px, px), Image.LANCZOS), dtype=np.float64)
    sa = small[..., 3:4] / 255
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = np.where(sa > 0, small[..., :3] / sa, 0)
    return Image.fromarray(np.round(np.clip(np.dstack([rgb, small[..., 3]]), 0, 255)).astype(np.uint8), "RGBA")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--src", default="design/launch-logo", help="the owner's flat art")
    parser.add_argument("--out", default="ios/RedPen/Assets.xcassets", help="the asset catalogue")
    parser.add_argument("--preview", help="also write a check sheet here")
    parser.add_argument("--swift", default="ios/RedPen/Shared/LaunchOpening.swift",
                        help="where LaunchArt.chest is written")
    args = parser.parse_args()
    src, out = Path(args.src), Path(args.out)
    swift = Path(args.swift).read_text() if Path(args.swift).exists() else ""
    sheet = []
    crops = {}
    chests = {}
    status = 0
    for name, v in VERSIONS.items():
        cuts = {dark: cut(src / v[("night" if dark else "day")], dark) for dark in (False, True)}
        h, w = cuts[False].shape[:2]
        # each mode cropped to its own mark: the two drawings are not the same
        # size on their canvases, and this way the mark fills the image alike
        squares = {dark: square(bbox(c), (w, h)) for dark, c in cuts.items()}
        crops[name] = squares
        folder = out / f"{v['set']}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        for old in folder.glob("*.png"):
            old.unlink()
        images = []
        for dark, rgba in cuts.items():
            left, top, side = squares[dark]
            big = crop(rgba, left, top, side)
            stem = "launch-logo-dark" if dark else "launch-logo"
            for n in (1, 2, 3):
                img = resized(big, SIDE_PT * n)
                img.save(folder / f"{stem}@{n}x.png", optimize=True)
                entry = {"idiom": "universal", "scale": f"{n}x", "filename": f"{stem}@{n}x.png"}
                if dark:
                    entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
                images.append(entry)
            # laid back on its ground, the cut is the source again
            src_img = Image.open(src / v["night" if dark else "day"]).convert("RGB")
            back = Image.alpha_composite(Image.new("RGBA", big.size, GROUND[dark] + (255,)), big)
            ref = Image.new("RGB", big.size, GROUND[dark])
            ref.paste(src_img.crop((max(left, 0), max(top, 0), min(left + side, w), min(top + side, h))),
                      (max(-left, 0), max(-top, 0)))
            diff = np.abs(np.asarray(back.convert("RGB"), dtype=int) - np.asarray(ref, dtype=int)).max()
            print(f"{name} {'night' if dark else 'day'}: crop {side}px at ({left},{top}); "
                  f"back on its ground differs by at most {diff}/255")
            if diff > 2:
                status = 1
            sheet.append((name, dark, big))
            chests[dark] = chest_piece(big)
        (folder / "Contents.json").write_text(json.dumps(
            {"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")
        # the chest pieces into LaunchArt.chest(dark:)
        tup = {d: "({:.4f}, {:.4f}, {:.4f})".format(*chests[d]) for d in (False, True)}
        line = f"dark ? {tup[True]} : {tup[False]}"
        print(f"{name} chest piece: {line}")
        if swift:
            new = re.sub(r"dark \? \([0-9., ]+\) : \([0-9., ]+\)", line, swift, count=1)
            if new != swift:
                Path(args.swift).write_text(new)
                print(f"  written into {args.swift}")
        print(f"{folder}/ launch-logo(-dark)@1x, @2x, @3x")

    if args.preview:
        p = Path(args.preview)
        p.mkdir(parents=True, exist_ok=True)
        tile = 400
        board = Image.new("RGB", (tile * len(sheet), tile * 2))
        for i, (name, dark, big) in enumerate(sheet):
            for row, ground in enumerate((GROUND[dark], (255, 0, 255))):
                bg = Image.new("RGBA", (tile, tile), ground + (255,))
                bg.alpha_composite(resized(big, tile))
                if row == 1:
                    # the measured chest piece, to check it lies on the disc
                    x, y, r = (v * tile for v in chests[dark])
                    ImageDraw.Draw(bg).ellipse((x - r, y - r, x + r, y + r), outline=(0, 255, 0, 255))
                board.paste(bg.convert("RGB"), (tile * i, tile * row))
        board.save(p / "launch-logo-sheet.png")
        print(p / "launch-logo-sheet.png")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
