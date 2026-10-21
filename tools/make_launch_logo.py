#!/usr/bin/env python3
"""Cut the launch mark from its flat ground, for the launch screen and the opening.

The art is private: design/launch-logo and the LaunchLogo image set are not
in this repository (.gitignore keeps them out); the mark is added to the
built app as loose PNGs when it is downloaded. Run this on a copy that holds
the art, and never commit its output here.

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
- fully solid inside the mark, so a white tube on a pale ground is not
  left half see-through, with an anti-aliased edge where the mark meets the
  ground or its shadow. Which pixels are the mark is read from colour, not
  brightness: the shadows in this art darken the ground evenly in every
  channel (towards black at the deepest), so they keep the ground's blue
  tint, while the stethoscope's grey and white parts are neutral. The edge
  is the line where a pixel is half one, half the other, found on a
  lightly smoothed map of that and drawn with sub-pixel coverage, so the
  outline is as smooth as the drawing: no squared-off steps, no specks
  of shadow made solid, no notches;
- the colour then solved from P = a.F + (1 - a).G, so laid back on G the
  image gives P again, to the rounding of a byte: no halo and no jump when
  the launch screen hands over to the opening.

The owner's pair: the white tube by day (14 Oct) and the grey tube by night
(15 Oct, in place of the slate one), kept as design/launch-logo/light.png
and dark.png (named by mode, not by colour, so a new tube for either is one
file copied over the old), written as LaunchLogo's light and dark images,
cropped the same way so the mark sits at the same place in both modes. It
measures where the chest piece is in each (as fractions of the image) and
writes that into LaunchArt.chest in ios/RedPen/Shared/LaunchOpening.swift.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

GROUND = {False: (0xE0, 0xE5, 0xEC), True: (0x2A, 0x2E, 0x35)}
SIDE_PT = 200          # LaunchArt.side
NOISE = 2              # this close to the ground is the ground
SURE = 0.15            # this sure (0 to 1) of ground or of mark counts as sure
SMOOTH = 1.0           # the mark/ground map is smoothed over this many pixels (sigma)
BLUER = 0.3            # at least this much more of the ground's tint than the ground has is surely the mark
NEAR = 3               # a mark's own colour is read from this many pixels around (radius)
STANDS = 0.15          # a blue line is the mark where it is this much darker or lighter than the ground beside it
BEYOND = 4             # the ground beyond the mark is read this many pixels out from its edge
LINE = 0.3             # a line along the mark's edge this much darker or lighter than the ground beyond is the mark in full
HOLE = 41              # enclosed pockets narrower than this (pixels) are the mark
SPECK = 0.01           # a piece of the mark smaller than this share of the whole is a speck

# The art: swapping it is copying a new picture over light.png or dark.png in
# design/launch-logo and running this script (or tools/swap_art.sh), which measures the chest piece itself and writes
# it into LaunchOpening.swift.
VERSIONS = {
    "launch": {"set": "LaunchLogo", "day": "light.png", "night": "dark.png"},
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
    least = np.maximum(up, down).max(axis=2)
    least[np.abs(d).max(axis=2) <= NOISE] = 0

    # the mark: where the smoothed map says more mark than ground, with the
    # narrow pockets it encloses (a highlight, a pale patch, the engraving's
    # edge) filled and any stray piece away from the drawing dropped
    smooth = gauss(img, 0.7)
    sure = gauss(markness(smooth, g), SMOOTH)
    # closed over a pixel: where two of the mark's colours meet (the chrome's
    # blue rim and its grey), the blend between them can pass for a shadow's
    # tint, and that seam must not open into a crack
    sure = -widest(-widest(sure, 1.5), 1.5)
    mark, _, _ = solid(sure)
    # the chrome's own rim: a line a pixel or two wide along the metal's
    # edge, mirroring the blue-grey room, so its tint passes for the ground's
    # or a shadow's. A shadow here is soft (a few pixels out from the mark
    # it varies by under 0.08 of the ground's brightness), so a line along
    # the edge that is far darker or lighter than the ground just beyond it
    # is the metal, measured against the mark's own contrast nearby so the
    # edge falls half-way across the line's outer side. Without it the rim
    # is cut in places and kept in others: bumps, slivers and a stepped edge
    bright = smooth.mean(axis=2) / g.mean()
    beyond = erode(~mark, BEYOND)
    weight = gauss(beyond.astype(np.float64), 3.0)
    ground_level = np.where(weight > 1e-3, gauss(bright * beyond, 3.0) / np.maximum(weight, 1e-3), bright)
    off = np.abs(bright - ground_level)
    rim = np.clip(off / np.maximum(widest(off, NEAR), LINE), 0, 1)
    rim[beyond] = 0
    sure = np.maximum(sure, gauss(rim, SMOOTH))
    mark, pocket, speck = solid(sure)
    sure = np.where(pocket, 1.0, np.where(speck, 0.0, sure))

    # how much of each edge pixel the mark covers: its distance to the
    # half-way line, read off the smoothed map's slope
    gy, gx = np.gradient(sure)
    cover = np.clip(0.5 + (sure - 0.5) / np.maximum(np.hypot(gx, gy), 1e-6), 0, 1)
    inside, outside = erode(mark, 1), erode(~mark, 1)
    cover[inside], cover[outside] = 1, 0
    # under an edge pixel lies the ground or its shadow, as see-through as
    # the shadow just beside it
    beside = outside.astype(np.float64)
    weight = gauss(beside, 1.5)
    under = np.where(weight > 1e-3, gauss(least * beside, 1.5) / np.maximum(weight, 1e-3), 0)
    alpha = np.where(inside, 1.0, np.where(outside, least, cover + (1 - cover) * under))
    alpha = np.clip(np.maximum(alpha, least), 0, 1)
    a = alpha[..., None]
    with np.errstate(divide="ignore", invalid="ignore"):
        fg = np.where(a > 0, (img - (1 - a) * g) / a, 0)
    fg = np.clip(fg, 0, 255)
    return np.dstack([fg, alpha * 255])


def solid(sure: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The mark from its map: more mark than ground, with the narrow pockets
    it encloses filled and any stray piece away from the drawing dropped.
    Returns the mark, the pockets and the specks."""
    mark = sure > 0.5
    labels, _ = components(~mark)
    open_ground = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    wide = np.unique(labels[erode(~mark, HOLE // 2)])
    pocket = (labels > 0) & ~np.isin(labels, open_ground) & ~np.isin(labels, wide)
    mark |= pocket
    labels, _ = components(mark)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    speck = mark & (sizes < SPECK * sizes.max())[labels]
    return mark & ~speck, pocket, speck


def markness(img: np.ndarray, g: np.ndarray) -> np.ndarray:
    """How surely each pixel is the mark rather than the ground or a shadow
    on it, 0 to 1, passing 0.5 where the mark covers about half the pixel.

    Only the colour's tint counts (P minus its own grey level), measured
    along the ground's tint: the ground and its shadows have the ground's
    tint in full (an even darkening) or in proportion to their brightness
    (a darkening towards black); the stethoscope's greys and whites have
    none; the blue ring and the engraving have more than the ground; the
    metal's warm tints lie across it."""
    mean = img.mean(axis=2)
    tint = img - mean[..., None]
    gt = g - g.mean()
    n2 = float((gt ** 2).sum())
    along = (tint * gt).sum(axis=2) / n2
    across = np.sqrt(np.maximum((tint ** 2).sum(axis=2) / n2 - along ** 2, 0))
    bright = mean / g.mean()
    lit = np.clip(bright, 1e-3, 1)
    toward_grey = np.clip((lit - along) / lit, 0, None)
    # tinted across the ground's tint (the metal's warmth): the mark, measured
    # against the mark's own colour nearby so the edge falls half-way to it
    warm = across / np.maximum(widest(across, NEAR), 1)
    # bluer than the ground: a shadow here only darkens, so this is the
    # mark too (the chrome's rim, mirroring the blue-grey room, the blue
    # ring, the engraving), but only where it also stands out in brightness
    # from the ground beside it, since the faint bluish light along a rim
    # is barely bluer than the rim itself
    plain = gauss(np.maximum(np.maximum(toward_grey, warm), (along - 1) / BLUER), 1.0) < 0.5
    weight = gauss(plain.astype(np.float64), 3.0)
    beside = np.where(weight > 1e-3, gauss(bright * plain, 3.0) / np.maximum(weight, 1e-3), 1)
    stands = np.clip(np.abs(bright - beside) / STANDS, 0, 1)
    bluer = np.clip((along - 1) / np.maximum(widest(along, NEAR) - 1, BLUER), 0, None) * stands
    sure = np.maximum(np.maximum(toward_grey, bluer), warm)
    return np.clip((sure - 0.5) / (1 - 2 * SURE) + 0.5, 0, 1)


def gauss(a: np.ndarray, sigma: float) -> np.ndarray:
    """A Gaussian blur over the first two axes, the edges repeated."""
    r = max(1, int(np.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = a.astype(np.float64)
    for axis in (0, 1):
        pad = [(0, 0)] * out.ndim
        pad[axis] = (r, r)
        padded = np.pad(out, pad, mode="edge")
        n = out.shape[axis]
        out = sum(w * np.take(padded, np.arange(i, i + n), axis=axis) for i, w in enumerate(k))
    return out


def widest(a: np.ndarray, r: float) -> np.ndarray:
    """The largest value within a disc of radius r pixels around each pixel."""
    h, w = a.shape
    n = int(r)
    padded = np.pad(a, n, mode="edge")
    out = a.copy()
    for dy in range(-n, n + 1):
        for dx in range(-n, n + 1):
            if dx * dx + dy * dy <= r * r:
                np.maximum(out, padded[n + dy:n + dy + h, n + dx:n + dx + w], out=out)
    return out


def erode(mask: np.ndarray, r: int) -> np.ndarray:
    """The mask shrunk by a disc of radius r pixels."""
    h, w = mask.shape
    padded = np.pad(mask, r, mode="constant", constant_values=False)
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out &= padded[r + dy:r + dy + h, r + dx:r + dx + w]
    return out


def components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """The mask's 8-connected pieces: a label per pixel (0 off the mask) and how many."""
    parent = [0]

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    raw = np.zeros(mask.shape, np.int64)
    above: list[tuple[int, int, int]] = []
    for y in range(mask.shape[0]):
        edges = np.diff(np.concatenate(([0], mask[y].astype(np.int8), [0])))
        runs = []
        j = 0
        for s, e in zip(np.nonzero(edges == 1)[0].tolist(), np.nonzero(edges == -1)[0].tolist()):
            label = len(parent)
            parent.append(label)
            while j < len(above) and above[j][1] < s:
                j += 1
            k = j
            while k < len(above) and above[k][0] <= e:
                a, b = find(label), find(above[k][2])
                if a != b:
                    parent[max(a, b)] = min(a, b)
                k += 1
            runs.append((s, e, label))
            raw[y, s:e] = label
        above = runs
    roots = np.array([find(i) for i in range(len(parent))])
    _, compact = np.unique(roots, return_inverse=True)
    return compact[raw], int(compact.max())


def chest_piece(img: np.ndarray) -> tuple[float, float, float]:
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


def crop(rgba: np.ndarray, left: int, top: int, side: int) -> np.ndarray:
    """The square, with clear ground wherever it runs past the picture (still
    floating point: it is rounded once, after resizing)."""
    h, w = rgba.shape[:2]
    out = np.zeros((side, side, 4), dtype=np.float64)
    sx0, sy0 = max(left, 0), max(top, 0)
    sx1, sy1 = min(left + side, w), min(top + side, h)
    out[sy0 - top:sy1 - top, sx0 - left:sx1 - left] = rgba[sy0:sy1, sx0:sx1]
    return out


def resized(rgba: np.ndarray, px: int) -> Image.Image:
    """Down to px square. The colour is filtered premultiplied by alpha, once
    and in floating point, so the clear ground neither darkens the mark's
    edge nor leaves a beaded rim on it (Pillow premultiplies RGBA itself, so
    a picture premultiplied beforehand would be twice over). The filter
    (Hamming) has no negative lobes: a sharper one (Lanczos) rings at the
    crisp edge, and once alpha is clipped back to 0-1 the ring shows as a
    light or dark halo. With this one, every size laid on its ground is the
    art resized the same way, to within 2/255."""
    rgba = np.asarray(rgba, dtype=np.float64)
    a = rgba[..., 3] / 255

    def filtered(channel: np.ndarray) -> np.ndarray:
        img = Image.fromarray(channel.astype(np.float32), "F")
        return np.asarray(img.resize((px, px), Image.HAMMING), dtype=np.float64)

    small = filtered(a)
    alpha = np.round(np.clip(small, 0, 1) * 255)
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = np.dstack([np.where(small > 0, filtered(rgba[..., c] * a) / small, 0) for c in range(3)])
    rgb = np.where(alpha[..., None] > 0, np.clip(rgb, 0, 255), 0)
    return Image.fromarray(np.round(np.dstack([rgb, alpha])).astype(np.uint8), "RGBA")


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
            # the source as cut: the same square of the picture, its ground
            # carried on where the square runs past it
            src_img = Image.open(src / v["night" if dark else "day"]).convert("RGB")
            ref = Image.new("RGB", (side, side), GROUND[dark])
            ref.paste(src_img.crop((max(left, 0), max(top, 0), min(left + side, w), min(top + side, h))),
                      (max(-left, 0), max(-top, 0)))
            sizes = []
            for n in (1, 2, 3):
                img = resized(big, SIDE_PT * n)
                img.save(folder / f"{stem}@{n}x.png", optimize=True)
                entry = {"idiom": "universal", "scale": f"{n}x", "filename": f"{stem}@{n}x.png"}
                if dark:
                    entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
                images.append(entry)
                # each size laid on its ground is the picture made that size
                on = Image.new("RGBA", img.size, GROUND[dark] + (255,))
                on.alpha_composite(img)
                made = ref.resize(img.size, Image.HAMMING)
                sizes.append(np.abs(np.asarray(on.convert("RGB"), dtype=np.float64)
                                    - np.asarray(made, dtype=np.float64)).max())
            # laid back on its ground, the cut is the source again
            a = big[..., 3:] / 255
            back = np.round(big[..., :3] * a + np.array(GROUND[dark]) * (1 - a))
            diff = np.abs(back - np.asarray(ref, dtype=np.float64)).max()
            print(f"{name} {'night' if dark else 'day'}: crop {side}px at ({left},{top}); "
                  f"back on its ground differs by at most {diff:.0f}/255; "
                  f"@1x-@3x on it, from the picture resized, by at most {max(sizes):.0f}/255")
            if diff > 2 or max(sizes) > 2:
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
