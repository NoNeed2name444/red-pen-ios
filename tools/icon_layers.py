#!/usr/bin/env python3
"""Stethoscore's app icon, in layers, for IconLayersView.

The app icon is the owner's stethoscope with depth (design/icon/source/
icon-light.png and icon-dark.png, made into AppIcon.icon by
tools/make_icon.py). actool compiles the icon away, so a screen that wants to
show the icon, or move its parts apart, reads these instead:

    0-background.png        the light base, flat, full bleed
    1-stethoscope.png       the stethoscope with its shadow, the base keyed out
    0-background-dark.png   the same, from the dark picture
    1-stethoscope-dark.png

Every layer is a 1024 x 1024 PNG with alpha, in the icon's own frame, and
the stethoscope over its background recomposes the icon within MAX_ERR. The
cut is make_launch_logo's (colour-to-alpha against the base, the solid
parts kept whole), keyed against the base as measured on the picture's
border, so swapping the icon art and rerunning this keeps the view in step.

    python3 tools/icon_layers.py               write design/icon/layers
    python3 tools/icon_layers.py --check       exit 1 if they are out of date

The layer names and order are IconLayerSpec.swift's; the "iconlayers" Swift
suite checks the files against it. Needs numpy and Pillow.
"""
from __future__ import annotations

import argparse
import io
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_icon  # noqa: E402
import make_launch_logo  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/icon/source"
LAYERS_DIR = ROOT / "design/icon/layers"
N = make_icon.S
MAX_ERR = 2          # /255, the most any pixel may move in the recomposed icon


def ground(img: np.ndarray) -> tuple[int, int, int]:
    border = np.concatenate([img[:8].reshape(-1, 3), img[-8:].reshape(-1, 3),
                             img[:, :8].reshape(-1, 3), img[:, -8:].reshape(-1, 3)])
    return tuple(int(v) for v in np.round(np.median(border, axis=0)))


def layers(look: str) -> dict[str, bytes]:
    pic = make_icon.square(SOURCE / f"icon-{look}.png")
    rgb = np.asarray(pic, dtype=np.float64)
    base = ground(rgb)
    dark = look == "dark"
    make_launch_logo.GROUND[dark] = base
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "icon.png"
        pic.save(path)
        cut = make_launch_logo.cut(path, dark)
    a = cut[..., 3:] / 255
    back = np.round(cut[..., :3] * a + np.array(base) * (1 - a))
    err = np.abs(back - rgb).max()
    if err > MAX_ERR:
        raise SystemExit(f"icon-{look}: the layers recompose the icon only to within {err:.0f}/255")
    suffix = "" if look == "light" else "-dark"
    out = {}
    bg = Image.new("RGBA", (N, N), base + (255,))
    fg = Image.fromarray(np.round(np.clip(cut, 0, 255)).astype(np.uint8), "RGBA")
    for name, img in ((f"0-background{suffix}.png", bg), (f"1-stethoscope{suffix}.png", fg)):
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        out[name] = buf.getvalue()
    print(f"icon-{look}: base {base}, recomposed within {err:.0f}/255")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files: dict[str, bytes] = {}
    for look in ("light", "dark"):
        files.update(layers(look))
    if args.check:
        stale = [n for n, b in files.items() if not (LAYERS_DIR / n).exists()
                 or not np.array_equal(np.asarray(Image.open(LAYERS_DIR / n)),
                                       np.asarray(Image.open(io.BytesIO(b))))]
        extra = sorted(p.name for p in LAYERS_DIR.glob("*.png") if p.name not in files)
        if stale or extra:
            print("out of date:", stale, "extra:", extra)
            return 1
        return 0
    LAYERS_DIR.mkdir(parents=True, exist_ok=True)
    for p in LAYERS_DIR.glob("*.png"):
        if p.name not in files:
            p.unlink()
            print(f"removed {p.relative_to(ROOT)}")
    for name, data in files.items():
        (LAYERS_DIR / name).write_bytes(data)
    print(f"{LAYERS_DIR.relative_to(ROOT)}: {', '.join(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
