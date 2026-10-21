#!/usr/bin/env python3
"""Stethoscore's app icon, cut into layers for iOS 26 (Icon Composer).

The icon is the chosen render, design/icon/source.png. iOS 26 lights and moves
an icon layer by layer (Liquid Glass), so this cuts that render - nothing is
redrawn - into one 1024 x 1024 PNG with alpha per element, all in the same
frame (the render's tile stretched to the canvas; iOS applies the mask):

    0 background   the tile's sky-to-royal-blue gradient, full bleed
    1 metal        the silver tubes and the stem
    2 tubing       the blue tube
    3 earpieces    the white tips
    4 chest-piece  the silver disc and its bevel
    5 a-plus       the dark-blue letters inside the disc

Each element is found by colour and region; its soft shadow and anti-aliased
edge go with it as a feathered alpha, matted against the layers below so the
stack recomposes the render; and where it hides a lower element that lower
layer is filled in a little, so moving a layer shows no hole.

    python3 tools/icon_layers.py                 write design/icon/layers and
                                                 ios/AppResources/AppIcon.icon
    python3 tools/icon_layers.py --check         exit 1 if either is out of date
                                                 or the stack drifts from the render
    python3 tools/icon_layers.py --report DIR    also save DIR/side-by-side.png:
                                                 source | composite | each layer on grey

The layer order, names and groups are IconLayerSpec.swift's; the "iconlayers"
Swift suite checks the files against it. Needs numpy and Pillow.
"""
from __future__ import annotations

import io, json, sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/icon/source.png"
LAYERS_DIR = ROOT / "design/icon/layers"
BUNDLE = ROOT / "ios/AppResources/AppIcon.icon"
N = 1024
TILE_BOX = (154, 140, 1100, 1110)  # the tile in source.png (946 x 970 px)
MAX_MAE = 3.0                       # /255, inside the tile

# Back to front: (name, Icon Composer group). iOS moves a group as one piece.
LAYERS = [("background", "Background"), ("metal", "Tubing"), ("tubing", "Tubing"),
          ("earpieces", "Earpieces"), ("chest-piece", "Chest piece"), ("a-plus", "Chest piece")]
FILL = {"linear-gradient": ["srgb:0.35686,0.74118,0.97647,1.00000", "srgb:0.09412,0.28627,0.83137,1.00000"],
        "orientation": {"start": {"x": 0.32, "y": 0}, "stop": {"x": 0.68, "y": 1}}}

# Where the render puts things, in canvas pixels (measured on the cut).
DISC = (790.5, 466.0, 136.0, 132.5)   # chest piece: centre, radii (incl. its edge)
FACE = (790.5, 466.0, 100.0, 97.0)    # the light face the letters sit on
LEFT_EAR = (276, 95, 362, 172)        # box; the seam with the metal is x = 276
RIGHT_EAR = (405, 108, 500, 195)      # box; the seam runs (490, 140) -> (484, 172)
HALO = 128                            # how far a shadow belongs to its element
FILL_GAP = {1: 8, 2: 8, 4: 24}        # how far a hidden element continues under the next

def asset_name(i, name):
    return f"{i}-{name}.png"

# ---- pixel helpers -------------------------------------------------------------
def shift(a, dy, dx, fill=0):
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out

def dilate(m, r):
    for i in range(r):  # alternate 4- and 8-neighbours: an octagon, near a disc
        o = m.copy()
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)] + ([(-1, -1), (-1, 1), (1, -1), (1, 1)] if i % 2 else []):
            o |= shift(m, dy, dx, False)
        m = o
    return m

def erode(m, r):
    return ~dilate(~m, r)

def nearest(seeds, reach=128):
    """For every pixel, the flat index of the nearest seed pixel and the distance
    to it (jump flooding); -1 / inf where none is within about `reach`."""
    yy, xx = np.mgrid[0:N, 0:N]
    idx = np.where(seeds, yy * N + xx, -1)
    d2 = np.where(seeds, 0.0, np.inf)
    step = 1
    while step * 2 <= reach: step *= 2
    steps = []
    while step >= 1: steps.append(step); step //= 2
    for s in steps + [1]:
        for dy in (-s, 0, s):
            for dx in (-s, 0, s):
                if dy == dx == 0: continue
                c = shift(idx, dy, dx, -1)
                cd = np.where(c >= 0, (yy - c // N) ** 2.0 + (xx - c % N) ** 2.0, np.inf)
                better = cd < d2
                idx[better], d2[better] = c[better], cd[better]
    return idx, np.sqrt(d2)

def gather(img, idx):
    flat = img.reshape(N * N, -1)
    return flat[np.clip(idx, 0, None).ravel()].reshape(N, N, -1)

def ellipse(e, scale=1.0):
    cx, cy, rx, ry = e
    yy, xx = np.mgrid[0:N, 0:N]
    return ((xx - cx) / (rx * scale)) ** 2 + ((yy - cy) / (ry * scale)) ** 2 <= 1

def box(b):
    m = np.zeros((N, N), bool)
    m[b[1]:b[3], b[0]:b[2]] = True
    return m

# ---- the cut -------------------------------------------------------------------
def load():
    im = Image.open(SOURCE).convert("RGB").resize((N, N), Image.LANCZOS, box=TILE_BOX)
    return np.clip(np.asarray(im).astype(float), 0, 255)

def tile_mask(C):
    """The rounded tile: everything not reachable from the canvas edge without crossing blue."""
    blue = (C[..., 2] - C[..., 0]) > 60
    out = np.zeros((N, N), bool)
    out[0, :] = out[-1, :] = out[:, 0] = out[:, -1] = True
    out &= ~blue
    while True:
        nxt = dilate(out, 1) & ~blue
        if (nxt == out).all(): break
        out = nxt
    inside = ~out
    inside[[0, -1], :] = inside[:, [0, -1]] = False  # where the tile touches the crop, the edge is its rim
    return inside

def background(C, inside):
    """The tile's gradient: a smooth fit to its bare pixels, carried out to the
    canvas edge (no rounded corners, no shadow)."""
    yy, xx = np.mgrid[0:N, 0:N] / N
    basis = np.stack([xx ** i * yy ** j for i in range(5) for j in range(5 - i)], -1)
    keep = inside.copy()
    for t in [40, 20, 10, 6, 4, 3, 3]:  # drop the stethoscope and its shadow, refit
        coef = np.linalg.lstsq(basis[keep], C[keep], rcond=None)[0]
        B = np.clip(basis @ coef, 0, 255)
        keep = inside & ((B - C).mean(-1) < t) & ((C - B).mean(-1) < 3 * t)
    idx, _ = nearest(inside, 256)
    return np.where(inside[..., None], B, gather(B, idx))

def labels(C, B, inside):
    """Each element's solid pixels: 1 metal, 2 tubing, 3 earpieces, 4 chest piece, 5 A+."""
    ratio = C / np.maximum(B, 1)
    q = ratio[..., 0] / np.maximum(ratio[..., 2], 0.05)  # red gained against the blue sky
    mx = C.max(-1)
    sat = (mx - C.min(-1)) / np.maximum(mx, 1)
    lum = C.mean(-1)
    inner = erode(inside, 24)            # the stethoscope keeps clear of the tile's rim
    yy, xx = np.mgrid[0:N, 0:N]
    neutral = inner & (q > 1.5)           # silver and white
    navy = inner & (q < 0.5)
    # The tube's highlight is silver-bright but thin: neutral, yet nowhere near
    # a part of the stethoscope that is thick and neutral.
    thin = neutral & ~dilate(erode(neutral, 6), 9) & dilate(navy, 6)
    tube = erode(dilate(navy | thin, 3), 3)
    # Reflections streak the tube a little red or light; close those narrow
    # gaps, but not a gap where bright sky shows between coils.
    tube |= erode(dilate(tube, 5), 5) & inner & (C.mean(-1) < B.mean(-1) + 25)
    disc = ellipse(DISC)
    face = ellipse(FACE)
    ear = neutral & ((box(LEFT_EAR) & (xx >= 276)) |
                     (box(RIGHT_EAR) & (xx < 490 - (yy - 140) * 0.19)))
    lab = np.zeros((N, N), np.uint8)
    metal_zone = (yy < 440) & (xx < 600) | box((715, 560, 805, 665))  # binaurals, stem
    lab[neutral & ~tube & metal_zone] = 1
    lab[tube & ~disc & (yy > 330)] = 2   # the dark shadow under the earpieces is not tube
    lab[ear] = 3
    lab[inner & ((disc & neutral) | ellipse(DISC, 0.97))] = 4
    letters = face & (sat > 0.4) & (lum < 140)
    lab[letters] = 5
    return lab, letters, face

def cut(C, B, inside):
    lab, letters, face = labels(C, B, inside)
    fg = lab > 0
    # Who owns each pixel: its element, or for the edge and shadow around one,
    # the nearest element (out to HALO px).
    near_idx, near_d = nearest(fg, 256)
    owner = np.where(fg, lab, gather(lab[..., None], near_idx)[..., 0])
    diff = np.abs(C - B).max(-1)
    shade = (B - C).mean(-1)  # a shadow darkens the sky; only a strong glint brightens it
    halo = ~fg & inside & (near_d <= HALO) & ((shade > 3) | (diff > 12) | (near_d <= 3))
    owner = np.where(fg | halo, owner, 0)
    # A+ owns its anti-aliased edge on the face, not just its shadow.
    owner[face & dilate(letters, 3) & ~letters & (owner == 4)] = 5
    B = np.round(B)
    comp = B.copy()
    layers = [(B, np.ones((N, N)))]
    for L in range(1, 6):
        solid = (lab == L) & (owner == L)
        lower = (lab > 0) & (lab < L)
        # Solid but at an edge: one pixel in from the sky, two from a lower element.
        edge = solid & (dilate(~fg & inside, 1) | dilate(lower, 2))
        core = solid & ~edge
        if L == 5: core = letters & ~dilate(~letters, 1)
        rgb = np.zeros((N, N, 3)); a = np.zeros((N, N))
        rgb[core], a[core] = C[core], 1.0
        # Fill under the elements above, a little way in from this one's solid part.
        above = dilate(lab > L, 2) & (owner > L)
        if L == 4: above = dilate(letters, 4) & face & (owner == 5)
        cidx, cd = nearest(core, 64)
        gap = above & (cd <= FILL_GAP.get(L, 0)) & ~core & (owner != L)
        if L == 4: gap = above & ~core
        fill = gather(C, cidx)
        if L == 4: fill = inpaint(fill, C, gap, face & ~gap)
        rgb[gap], a[gap] = fill[gap], 1.0
        # The edge and the shadow: matte against what's beneath.
        soft = (owner == L) & ~core & ~gap
        # Away from the edge it is shadow (black over the sky), unless that would
        # take a red cast (a reflection on the element): then the element's colour.
        taper = np.clip((HALO - near_d) / 32, 0, 1)
        def unmix(est):
            alpha = matte(C, comp, est, soft)
            alpha = np.where(fg | (lab == L), alpha, alpha * taper)
            return alpha, np.clip((C - (1 - alpha[..., None]) * comp) / np.maximum(alpha, 1e-6)[..., None], 0, 255)
        alpha, f = unmix(np.where((cd <= 3)[..., None], fill, 0.0))
        cast = (cd <= 16) & (f[..., 0] > f[..., 2]) & (fill[..., 2] > fill[..., 0] + 40)  # blue elements only
        alpha2, f2 = unmix(np.where((cd <= 3)[..., None] | cast[..., None], fill, 0.0))
        alpha, f = np.where(cast, alpha2, alpha), np.where(cast[..., None], f2, f)
        rgb[soft], a[soft] = f[soft], alpha[soft]
        rgb8, a8 = quantize(rgb, a)
        comp = over(comp, rgb8, a8)
        layers.append((rgb8, a8))
    return layers, comp, lab, owner

def matte(C, D, F, mask):
    """The least alpha that explains C as F over D (and no less than the
    projection onto F - D), so un-premultiplying never leaves 0...255."""
    lo = np.where(C < D, (D - C) / np.maximum(D, 1e-6), (C - D) / np.maximum(255 - D, 1e-6)).max(-1)
    v = F - D
    proj = ((C - D) * v).sum(-1) / np.maximum((v * v).sum(-1), 1e-6)
    return np.where(mask, np.clip(np.maximum(lo, proj), 0, 1), 0)

def inpaint(fill, C, hole, known):
    """Smooth the hole from its rim (the face under the letters)."""
    out = fill.copy()
    out[known] = C[known]
    ys, xs = np.nonzero(hole)
    y0, y1, x0, x1 = ys.min() - 2, ys.max() + 3, xs.min() - 2, xs.max() + 3
    sub, h = out[y0:y1, x0:x1].copy(), hole[y0:y1, x0:x1]
    for _ in range(400):
        avg = (shift(sub, 1, 0) + shift(sub, -1, 0) + shift(sub, 0, 1) + shift(sub, 0, -1)) / 4
        sub[h] = avg[h]
    out[y0:y1, x0:x1] = sub
    return out

def quantize(rgb, a):
    a8 = np.round(a * 255) / 255
    rgb8 = np.where((a8 > 0)[..., None], np.clip(np.round(rgb), 0, 255), 0)
    return rgb8, a8

def over(D, rgb, a):
    return a[..., None] * rgb + (1 - a[..., None]) * D

def png(rgb, a):
    arr = np.dstack([rgb, a * 255]).round().astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(arr, "RGBA").save(buf, "PNG", optimize=True)
    return buf.getvalue()

def mae(C, comp, inside):
    region = erode(inside, 4)
    return float(np.abs(C - comp)[region].mean())

# ---- icon.json -----------------------------------------------------------------
def icon_json():
    groups = {}
    for i, (name, group) in enumerate(LAYERS):
        # glass off: the layers are the render itself, lit and shaded already.
        groups.setdefault(group, []).append({"glass": False, "image-name": asset_name(i, name), "name": name})
    out = []
    # Icon Composer lists groups, and the layers in each, front first.
    for g, layers in reversed(list(groups.items())):
        entry = {"layers": list(reversed(layers)), "name": g}
        if g != "Background":
            entry.update({"shadow": {"kind": "neutral", "opacity": 0.5}, "specular": True,
                          "translucency": {"enabled": False, "value": 0.5}})
        out.append(entry)
    # No "color-space-for-untagged-svg-colors": actool in Xcode 26.4-26.6
    # crashes on it ("attempt to insert nil object").
    return json.dumps({"fill": FILL, "groups": out,
                       "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}},
                      indent=2, sort_keys=True) + "\n"

# ---- report --------------------------------------------------------------------
def side_by_side(C, comp, layers, inside, path):
    """source | composite | each layer on grey, 512 px a panel."""
    P = 512
    grey = np.full((N, N, 3), 128.0)
    panels = [np.where(inside[..., None], C, 255), np.where(inside[..., None], comp, 255)]
    panels += [over(grey, rgb, a) for rgb, a in layers]
    sheet = Image.new("RGB", (P * 4, P * 2), "white")
    for i, p in enumerate(panels):
        sheet.paste(Image.fromarray(p.round().astype(np.uint8)).resize((P, P), Image.LANCZOS), ((i % 4) * P, (i // 4) * P))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)

# ---- write ---------------------------------------------------------------------
def build():
    C = load()
    inside = tile_mask(C)
    B = background(C, erode(inside, 4))
    layers, comp, _, _ = cut(C, B, inside)
    return C, inside, layers, comp

def outputs(layers):
    files = {}
    for i, ((name, _), (rgb, a)) in enumerate(zip(LAYERS, layers)):
        data = png(rgb, a)
        files[LAYERS_DIR / asset_name(i, name)] = data
        files[BUNDLE / "Assets" / asset_name(i, name)] = data
    files[BUNDLE / "icon.json"] = icon_json().encode()
    return files

def main():
    args = sys.argv[1:]
    check = "--check" in args
    C, inside, layers, comp = build()
    err = mae(C, comp, inside)
    print(f"composite vs source, inside the tile: MAE {err:.2f}/255 (limit {MAX_MAE})")
    if "--report" in args:
        out = Path(args[args.index("--report") + 1]) / "side-by-side.png"
        side_by_side(C, comp, layers, inside, out)
        print("wrote", out)
    files = outputs(layers)
    stale = [p for p, data in files.items() if not p.exists() or p.read_bytes() != data]
    keep = {p.name for p in files}
    extra = [p for d in (LAYERS_DIR, BUNDLE / "Assets") if d.exists() for p in d.iterdir() if p.name not in keep]
    for p in stale: print(("stale " if check else "wrote ") + str(p.relative_to(ROOT)))
    for p in extra: print(("extra " if check else "removed ") + str(p.relative_to(ROOT)))
    if not check:
        for p in stale:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(files[p])
        for p in extra: p.unlink()
    return 1 if err > MAX_MAE or (check and (stale or extra)) else 0

if __name__ == "__main__":
    sys.exit(main())
