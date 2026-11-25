"""talus.py: the right talus, built as foot.py builds the calcaneus, from nothing but Gray's plates (Anatomy of the
Human Body, 1918, public domain: Fig. 270 the left talus from above, 271 from below, 272 its medial surface, 273 its
lateral surface) and his text (pp. 267 to 269). No scan and no other model is used.

Its own frame, millimetres, the right bone: x medial, y up, z forward. Fig. 270 is taken as the straight view from
above (that fixes which way is up); z = 0 is where Fig. 273's origin pixel falls, 1 to 4 mm behind the lateral tubercle,
y = 0 at the level of the head's underside, x = 0 at the middle of the trochlea. Gray gives no measure: the bone is set
about 58 mm long in the lateral plate (in Fig. 291 it is about three quarters as long as the calcaneus, which foot.py
sets at 79 mm), and that fixes every other size by the plates' own proportions.

How the plates are held (dev/fit_plates.py, all four outlines counted alike, sb/platefit_talus.json): Fig. 270 straight
from above; the two side plates each from about 10 degrees above (each shows the trochlea as a band some 4 to 5 mm
deep over the malleolar facet, 22 px of Fig. 273 and 20 px of Fig. 272, which a level side view cannot: 28 mm of
trochlea seen from 10 degrees above give 4.9 mm; left free in the fit, the nod stays at 10), Fig. 273 besides turned
10 degrees, Fig. 272 turned 5 the other way and rolled 9; Fig. 271 from below, turned 9 and rolled 4. So held, the solid
inside all four outlines fills 0.93 to 0.95 of each.

The build:
  1. the solid inside the four outlines, the edges between rounded (foot.calcaneus's way);
  2. forms cut by hand from what the plates draw inside their outlines and from Gray's text: the lateral malleolar
     facet's slope, the trochlea's hollow from side to side, the oval head, the posterior calcaneal surface's hollow,
     the sulcus tali, the groove for the flexor hallucis longus between the two tubercles;
  3. the joint surfaces marked smooth (no grain or plate ink on them);
  4. the plates' fine drawing and the grain of bone (foot.lay, foot.grain).
"""
import os
import numpy as np
from scipy import ndimage as ndi
import sdf
import platematch as pm
import foot
from foot import _ss, _bump, _one_piece, _pixels, _read, _round_meet, lay, emboss
from sdf import Ellipsoid, Field, rot

# Gray 1918, the left talus, written as mirror views of the right-hand model (platematch's way). pose: nod, turn, roll
# (degrees), scale factor, shift right and down (pixels); the poses in use are those kept in traces/talus_plates.npz.
TALUS = [
    dict(fig="Gray270", cap="from above", right=(1, 0, 0), up=(0, 0, 1), eye=(0, 1, 0), s=0.208, u0=222, v0=354,
         pose=(0.0, 0.0, 0.0, 1.003, 16.47, 8.174), free=(0, 0, 0, 1, 0, 1)),
    dict(fig="Gray273", cap="lateral surface", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=0.2007, u0=308, v0=219,
         pose=(10.0, 10.4, 1.5, 1.0, 0.0, 0.0), free=(1, 1, 1, 0, 0, 0)),
    dict(fig="Gray272", cap="medial surface", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=0.240, u0=139, v0=202,
         pose=(10.0, -4.9, 8.9, 1.02, 8.5, 22.9), free=(1, 1, 1, 1, 1, 1)),
    dict(fig="Gray271", cap="from below", right=(-1, 0, 0), up=(0, 0, 1), eye=(0, -1, 0), s=0.197, u0=137, v0=362,
         pose=(-4.7, 9.1, 4.2, 0.97, 9.2, 2.9), free=(1, 1, 1, 1, 1, 1)),
]
pm.PLATES.setdefault("talus", TALUS)          # for the dev tools (trace_plates.py, fit_plates.py, zoom_plates.py)

# Read off the plates under a pixel grid (each plate's own pixels).
# Fig. 270, from above: the trochlea's lateral border (where it turns down into the facet for the lateral malleolus and,
# behind, into the narrow facet for the inferior transverse ligament) and its medial border, as (row, column)
TROCH_LAT_270 = [(165, 142), (180, 140), (205, 140), (255, 144), (280, 153), (305, 170), (318, 185), (328, 200)]
# the whole trochlea as Fig. 270 draws it (column, row): wider in front, its lateral border curved, its hind corners
# rounded, its front border notched where the neck's upper surface runs back into it
TROCH_270 = [(150, 172), (140, 182), (140, 205), (144, 255), (153, 280), (170, 305), (185, 318), (200, 327), (230, 330),
             (260, 326), (280, 318), (292, 305), (298, 280), (298, 220), (296, 172), (285, 160), (270, 168), (258, 177),
             (245, 168), (225, 158), (200, 155), (175, 160)]
# the small pits of the neck's rough upper surface, Fig. 270 (column, row)
NECK_PITS_270 = [(240, 137), (255, 150), (265, 131), (270, 157), (285, 138), (275, 145), (245, 160), (265, 167), (231, 128),
                 (292, 127), (252, 128), (281, 152)]
TROCH_MED_270 = [(160, 296), (220, 298), (280, 297), (305, 290), (330, 284)]
# Fig. 273: the facet for the lateral malleolus is a triangle with its apex down, on the lateral process; its lower
# border, read on the model drawn in the plate's frame, stands (z, y mm): 33 mm up at its front corner (column 125),
# 20.7 at column 150, 16.5 at the apex (column 190), 19 at column 232 and 28.5 at its hind corner (column 270)
FACET_LOW = [(9.7, 28.5), (20.4, 19.0), (28.8, 16.5), (36.3, 20.7), (39.5, 33.0)]
# Fig. 271, from below (columns, rows): the posterior calcaneal surface, the middle one, the anterior one and the
# surface for the plantar calcaneonavicular ligament
POST_FACET_271 = [(97, 300), (106, 262), (150, 215), (200, 205), (245, 215), (256, 258), (250, 300), (222, 330), (182, 352),
                  (150, 356), (116, 340)]
MID_FACET_271 = [(52, 170), (70, 152), (98, 150), (114, 170), (112, 200), (96, 216), (66, 214), (52, 196)]
ANT_FACET_271 = [(66, 92), (100, 80), (134, 92), (136, 132), (112, 142), (76, 138)]
LIG_FACET_271 = [(16, 105), (40, 82), (64, 96), (64, 168), (44, 190), (20, 168)]
# Fig. 272, medial: the pear-shaped facet for the medial malleolus, broad in front, under the trochlea's medial border
MED_FACET_272 = [(181, 89), (189, 75), (209, 59), (239, 53), (269, 61), (287, 77), (290, 95), (281, 111), (269, 113), (253, 105),
                 (241, 97), (219, 95), (195, 97)]
# Fig. 273, lateral: the triangular facet for the lateral malleolus (column, row), apex down on the lateral process
LAT_FACET_273 = [(120, 74), (150, 65), (200, 51), (250, 67), (272, 92), (265, 115), (250, 145), (225, 158), (200, 163),
                 (180, 167), (160, 160), (140, 135), (122, 92)]


def _neck_pits():
    """The neck's small pits: Fig. 270's traced ones and, round them, more scattered thinner toward the head and the
    trochlea, of mixed sizes, none in a row (a fixed seed: the same pits every build)."""
    rng = np.random.default_rng(270); out = []
    pts = [tuple(map(float, q)) for q in NECK_PITS_270]
    while len(pts) < 22:
        c, r = rng.normal(262.0, 20.0), rng.normal(147.0, 11.0)
        if 118 < r < 172 and 222 < c < 302 and min(np.hypot(c - a, r - b) for a, b in pts) > 7.0:
            pts.append((c, r))
    for c, r in pts:
        fade = np.exp(-((c - 262.0) / 30.0) ** 2 - ((r - 147.0) / 18.0) ** 2)
        out.append(((c + rng.normal(0, 1.5), r + rng.normal(0, 1.5)), rng.uniform(0.3, 0.75), (0.12 + 0.2 * rng.random()) * (0.5 + 0.5 * fade)))
    return out


def _mask(shape, polys, ease):
    """Plate-pixel polygons as a filled picture (0 to 1), eased over `ease` pixels."""
    from PIL import Image, ImageDraw
    im = Image.new("L", shape[::-1], 0)
    for poly in polys:
        ImageDraw.Draw(im).polygon([tuple(q) for q in sdf.spline(np.asarray(poly, float), 2.0, closed=True)], fill=255)
    return ndi.gaussian_filter(np.asarray(im, np.float32) / 255.0, ease)


def _line(at, pts, sig=6.0):
    """A traced border, (row, column) points, eased along its rows over `sig` pixels and read at rows `at`."""
    rows = np.arange(-50.0, 500.0)
    col = ndi.gaussian_filter1d(np.interp(rows, [a for a, _ in pts], [b for _, b in pts]), sig, mode="nearest")
    return np.interp(at, rows, col)


def _surface_maps(F, D):
    """The solid's lowest and highest point over each (x, z) column (nan where the column is empty), between cells."""
    ins = D < 0; y = F.ax[1]; h = F.h
    any_ = ins.any(1)
    lo_i = np.argmax(ins, 1); hi_i = D.shape[1] - 1 - np.argmax(ins[:, ::-1, :], 1)
    def edge(i, step):
        j = np.clip(i - step, 0, D.shape[1] - 1)
        a = np.take_along_axis(D, j[:, None, :], 1)[:, 0]; b = np.take_along_axis(D, i[:, None, :], 1)[:, 0]
        return y[j] + step * h * a / np.maximum(a - b, 1e-6)
    lo = np.where(any_, edge(lo_i, 1), np.nan); hi = np.where(any_, edge(hi_i, -1), np.nan)
    return lo.astype(np.float32), hi.astype(np.float32)


def _fill(a, sig):
    """A map with its empty (nan) places filled from the nearest value and eased over sig cells."""
    bad = np.isnan(a)
    if bad.all():
        return np.zeros_like(a)
    idx = ndi.distance_transform_edt(bad, return_distances=False, return_indices=True)
    return ndi.gaussian_filter(a[tuple(idx)], sig).astype(np.float32)


def talus(h=0.4, log=print, relief=0.0, upto="all", poses=None, ink=foot.INK):
    """upto="hull" stops at the bare solid inside the four plates' outlines (what the plates' poses are fitted on,
    dev/fit_plates.py); `poses` tries other poses than the traces were made at ({fig: pose})."""
    F = Field((-32.0, -6.0, -4.0), (28.0, 46.0, 66.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    tr = foot.traces("talus"); V = {v["fig"]: v for v in TALUS}
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}
    ease = 1.0 if upto == "hull" else 1.4        # mm: an outline's small wiggles would else run across the bone as flutes

    def outline(fig, e=None):
        px = V[fig]["s"] * P[fig][3]; d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
        return _read(ndi.gaussian_filter(d, (e or ease) / px), *_pixels(V[fig], P[fig], X, Y, Z))

    # 1. inside the plates' outlines: the two plans (above, below) and the two sides
    plan = sdf.smax(outline("Gray270"), outline("Gray271"), 1.5)
    if upto != "hull":
        # behind, the plans' two tubercles eased over 3 mm: blunt prominences run into the body, not knuckles on a waist
        wb = _ss((13.0 - Z) / 5.0)
        plan = plan + (sdf.smax(outline("Gray270", 3.0), outline("Gray271", 3.0), 2.5) - plan) * wb; del wb
    # (at the head Fig. 272's outline stops 1.5 to 2 mm short of where the other three plates agree the head ends: there
    # the three are followed and Fig. 272 is let go, up to 3 mm)
    side = sdf.smax(outline("Gray273"), outline("Gray272") - (0.0 if upto == "hull" else 3.0) * _ss((Z - 46.0) / 4.0), 1.5)
    R = ndi.gaussian_filter1d(np.interp(F.ax[2], [0.0, 6.0, 14.0, 34.0, 42.0, 50.0, 60.0], [3.0, 4.0, 5.0, 5.0, 5.0, 5.5, 5.0]), 3.0 / h)[None, None, :]
    D = _round_meet(plan, side, R); del plan, side
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    # (the eased outlines and the rounding pull the head's front in by 1.5 to 2 mm against Figs. 270, 271 and 273: let
    # it out again there)
    D = D - 1.6 * _ss((Z - 53.0) / 4.0)

    xs = F.ax[0][:, None]; zs = F.ax[2][None, :]
    v270 = V["Gray270"]; p270 = P["Gray270"]; s270 = v270["s"] * p270[3]
    u2, r2 = _pixels(v270, p270, xs, 0.0 * xs, zs)                      # Fig. 270 is a straight view: the plan's pixels
    lo, top = _surface_maps(F, D); lo = _fill(lo, 1.0 / h); top = _fill(top, 1.0 / h)
    los = ndi.gaussian_filter(lo, 3.0 / h)[:, None, :]; tops = ndi.gaussian_filter(top, 3.0 / h)[:, None, :]   # for weights only

    # 2a. the lateral surface. The plans make it upright; Gray: "a large triangular facet, concave from above downward,
    # for articulation with the lateral malleolus". Fig. 270 sees it from above as a band 9 mm wide between the
    # trochlea's lateral border and the bone's outline (the lateral process, its apex), so the facet leans out as it
    # goes down: at the trochlea's border it starts at that border; at its lower border (Fig. 273) it reaches the
    # outline; between, it bows in (concave), x following the height to the power 1.7.
    u_top = _line(r2, TROCH_LAT_270)
    sil = tr["Gray270_sdf"].astype(np.float32) < 0
    rows = np.arange(sil.shape[0]); first = np.where(sil.any(1), np.argmax(sil, 1), 400).astype(float)
    u_out = np.interp(r2, rows, ndi.gaussian_filter1d(ndi.minimum_filter1d(first, 5), 7.0)) - 10.0    # past the outline
    x_edge = (u_top[0] - v270["u0"] - p270[4]) * s270                    # the trochlea's lateral border, x at each z
    xe = np.clip(np.round((x_edge - F.lo[0]) / h), 0, F.n[0] - 1).astype(int)
    y_edge = top[xe, np.arange(F.n[2])]                                  # and its height there
    y_edge = ndi.gaussian_filter1d(y_edge, 1.5 / h)
    y_low = ndi.gaussian_filter1d(np.interp(F.ax[2], [a for a, _ in FACET_LOW], [b for _, b in FACET_LOW]), 1.5 / h)
    t = np.clip((y_edge - Y) / np.maximum(y_edge - y_low, 3.0), 0.0, 1.0)
    wz = _bump(Z, 2.0, 6.0, 37.0, 41.0)      # (behind, the border curves in and the slope with it: the trochlea narrows)
    u_lat = u_out[:, None, :] + (u_top[:, None, :] - u_out[:, None, :]) * (1.0 - t ** 1.7) * wz
    D = sdf.smax(D, (u_lat - u2[:, None, :]) * s270, 3.0); del u_lat
    del t

    # 2b. the trochlea: "slightly concave from side to side": a hollow 1 mm deep down its middle, between the borders
    # Fig. 270 draws (it is broader in front than behind, as the plate's outline already has it)
    u_med = _line(r2, TROCH_MED_270)
    q = np.clip(1.0 - ((u2 - 0.5 * (u_top + u_med)) / (0.5 * (u_med - u_top))) ** 2, 0.0, 1.0)
    wt = _bump(zs, 7.0, 12.0, 36.0, 41.0)
    near_top = _ss((Y - (tops - 9.0)) / 7.0)        # (a displacement eased in over less than about three times its size folds the surface)
    # (the rounded meeting of plans and sides leaves the top domed across: the hollow is set against a height, not cut
    # into the dome) the pulley: across the trochlea two soft shoulders near its borders with a dip of 1.3 mm between,
    # the shoulders' height running along it as the side plates draw it (convex from before backward); past the
    # shoulders the borders roll down into the side walls
    _, topc = _surface_maps(F, D); topc = _fill(topc, 1.0 / h)
    sx = (u2 - 0.5 * (u_top + u_med)) / (0.5 * (u_med - u_top))
    Hc = np.nanmax(np.where(np.abs(sx) < 0.75, topc, np.nan), 0)
    Hc = ndi.gaussian_filter1d(np.where(np.isnan(Hc), np.nanmin(Hc), Hc), 1.5 / h)[None, :]
    target = Hc - 1.4 - 1.3 * np.exp(-(sx / 0.45) ** 2)     # (the shoulders where the side plates had the top)
    wsx = (1.0 - _ss((np.abs(sx) - 0.8) / 0.35)) * wt * _ss((topc - (Hc - 4.0)) / 1.5)
    D = D + ndi.gaussian_filter((topc - target) * wsx, 1.0 / h)[:, None, :] * near_top; del topc, target, wsx
    # in front of its border the upper surface falls away to the neck: the border as Fig. 270 draws it, notched in
    # the middle (the side outlines alone would leave it a straight edge across)
    # behind and medially it ends where its outline in Fig. 270 ends (the side outlines alone would square it off)
    tm = _mask(tr["Gray270_sdf"].shape, [TROCH_270], 0.5) > 0.5
    dtro = (ndi.distance_transform_edt(~tm) - ndi.distance_transform_edt(tm)) * s270
    dtro = _read(ndi.gaussian_filter(dtro, 1.5), u2, r2)                   # mm outside the trochlea's outline, on the plan
    # (on the lateral side only at the two corners: between them the facet's own slope is the border)
    mid = _bump(zs, 10.0, 16.0, 33.0, 38.0)
    away = _ss(dtro / 5.0) * (1.0 - mid * (1.0 - _ss((u2 - u_top - 6.0) / 4.0))) * (1.0 - _ss((zs - 46.0) / 3.0))
    D = D + ((1.4 + 3.0 * _ss((16.0 - zs) / 5.0)) * away)[:, None, :] * near_top     # (in front a gentle fall to the neck)
    trochlea = _ss((0.3 - dtro) / 0.6)[:, None, :] * _ss((Y - (tops - 5.0)) / 3.0)

    # 2c. the head: "large, oval, and convex", looking forward and medialward; the plans' box is rounded to an oval
    # 34 by 27 mm across (Fig. 270's and 273's head), its long axis falling medially (Fig. 272: the medial end lower)
    Rh = rot((0, 1, 0), 22.0) @ rot((0, 0, 1), -18.0); ch = np.array((5.0, 13.0, 45.5))
    E = Ellipsoid(ch, (20.5, 14.5, 20.5), Rh)(X, Y, Z)
    D = D + (sdf.smax(D, E, 4.0) - D) * _ss((Z - 40.0) / 5.0); del E

    # the neck's upper surface: Fig. 270's soft hollow just in front of the trochlea's notch (at column 258, row 158),
    # a dish 1 mm deep, about 6 by 5 mm
    D = D + 1.0 * np.exp(-((X - 4.1) / 3.0) ** 2 - ((Z - 42.6) / 2.5) ** 2) * _ss((Y - (tops - 8.0)) / 6.0)

    # 2d. below. The posterior calcaneal surface is "deeply concave in the direction of its long axis which runs
    # forward and lateralward at an angle of about 45 degrees": its outline as Fig. 271 draws it, its middle lifted
    # 3 mm along that axis (the ends, the lateral tubercle behind and the lateral process in front, stay where the
    # outlines have them)
    v271 = V["Gray271"]; p271 = P["Gray271"]; shape271 = tr["Gray271_sdf"].shape
    def below(polys, at):           # a Fig. 271 tracing, read on the underside (x, z) at height `at`
        m = _mask(shape271, polys, 5.0)
        return _read(m, *_pixels(v271, p271, xs, at, zs))
    mpost = below([POST_FACET_271], lo + 1.0)
    wsum = mpost.sum(); cx = (mpost * xs).sum() / wsum; cz = (mpost * zs).sum() / wsum
    ax_ = np.array([-np.sin(np.radians(50.0)), np.cos(np.radians(50.0))])   # forward and lateral (x medial)
    sd = (xs - cx) * ax_[0] + (zs - cz) * ax_[1]
    half = max(float(np.abs(sd[mpost > 0.5]).max()), 8.0)
    lift = 3.0 * np.clip(1.0 - (sd / half) ** 2, 0.0, 1.0) * _ss((mpost - 0.2) / 0.5)
    lift = ndi.gaussian_filter(lift, 2.5 / h)
    D = D + lift[:, None, :] * _ss((los + 10.0 - Y) / 8.0)      # the underside moved up, its sides with it
    # the sulcus tali: "a deep groove ... runs obliquely forward and lateralward, becoming gradually broader and deeper
    # in front", between the middle and the posterior surfaces (Fig. 271's rough band; Fig. 273 looks into its wide
    # lateral end under the neck, in front of the lateral process)
    path = [(7.5, 22.0), (2.0, 26.0), (-5.0, 30.0), (-12.0, 33.5), (-17.5, 35.8), (-20.0, 36.5)]
    d, t = foot._near(xs, zs, path)
    deep = np.interp(t, [0.0, 0.3, 0.7, 1.0], [2.0, 3.2, 4.4, 4.8]); wide = np.interp(t, [0.0, 0.5, 1.0], [2.4, 3.6, 4.8])
    sul = deep * np.exp(-(d / wide) ** 2) * _ss(t / 0.3) * _ss((xs + 17.0) / 7.0)
    D = D + sul[:, None, :] * _ss((los + deep[:, None, :] + 9.0 - Y) / 8.0); del d, t, sul

    # 2e. the posterior process. All four plates draw its lateral tubercle as the hindmost point of the bone, and the
    # four outlines' common part keeps only the stump of it (they disagree there by a millimetre or so: the tip read off
    # Fig. 270 at (205, 343), Fig. 273 at (305, 132), Fig. 271 at (155, 354) and Fig. 272 at (141, 135) lies, by least
    # squares, at x -6.2, y 20.0, z 2.9, within 1 mm of each plate's ray): "a prominent tubercle" is put back there, a
    # blunt knob broader than it is tall, run into the body
    # (a low ridge across the back, run broadly into the body and down into the posterior calcaneal surface's hind end)
    D = sdf.smin(D, Ellipsoid((-4.5, 18.0, 9.0), (7.5, 3.2, 4.8), rot((0, 0, 1), -20.0) @ rot((1, 0, 0), 20.0))(X, Y, Z), 8.0)
    # and the smaller medial tubercle, below and medial of the groove (Fig. 270 at (280, 322), Fig. 272 at (178, 172))
    D = sdf.smin(D, Ellipsoid((7.6, 13.0, 11.5), (3.0, 1.8, 4.0))(X, Y, Z), 5.0)

    # 2e. behind: "the posterior surface is narrow, and traversed by a groove running obliquely downward and
    # medialward ... for the Flexor hallucis longus"; lateral to it the larger (lateral) tubercle, medial the smaller.
    # Fig. 270 has the groove at column 257 between the lateral tubercle (203) and the medial (280); Fig. 272 sees its
    # upper end at (159, 128)
    ins = D < 0; first_z = np.where(ins.any(2), np.argmax(ins, 2), F.n[2] - 1)
    zb = _fill(np.where(ins.any(2), F.ax[2][first_z], np.nan), 2.5 / h)
    groove = [(1.6, 28.0), (2.6, 23.0), (3.7, 18.0), (4.6, 14.5)]
    xa = F.ax[0][:, None]; ya = F.ax[1][None, :]
    d, t = foot._near(xa, ya, groove)
    g = 2.6 * np.exp(-(d / 2.4) ** 2) * _ss(t / 0.35) * _ss((1.0 - t) / 0.35) * _ss((16.0 - zb) / 3.0)
    D = D + g[:, :, None] * _ss((zb[:, :, None] + 9.0 - Z) / 8.0) * _ss((Y - 9.0) / 4.0); del d, t, g

    D = ndi.gaussian_filter(D, 0.5 / h)          # (the cuts' last voxel-sized kinks would print as speckle)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D
    F = _one_piece(F)

    # 3. the joint surfaces: the trochlea, the two malleolar facets, the head's surface for the navicular, and below the
    # three calcaneal surfaces with the one for the plantar calcaneonavicular ligament, each where its plate draws its
    # border. A joint surface is smooth (eased over a millimetre, no grain or plate ink) and ends at a rim: the rough
    # bone round it stands half a millimetre lower.
    lo2, top2 = _surface_maps(F, F.D); lo2 = _fill(lo2, 1.0 / h)
    under = _ss((lo2[:, None, :] + 4.5 - Y) / 3.0)      # (every gate eased over millimetres: a sharp one prints the grid as dots)
    def below2(polys):
        m = _mask(shape271, polys, 4.0)
        return _read(m, *_pixels(v271, p271, xs, lo2 + 1.0, zs))[:, None, :] * under
    m_under = np.maximum(np.maximum(below2([POST_FACET_271]), below2([MID_FACET_271])), below2([ANT_FACET_271, LIG_FACET_271]))
    v272 = V["Gray272"]; m_med = _read(_mask(tr["Gray272_sdf"].shape, [MED_FACET_272], 4.0), *_pixels(v272, P["Gray272"], X, Y, Z))
    m_med = m_med * _ss((X - 5.0) / 3.0) * _ss((tops - 1.0 - Y) / 2.5)
    v273 = V["Gray273"]; m_lat = _read(_mask(tr["Gray273_sdf"].shape, [LAT_FACET_273], 4.0), *_pixels(v273, P["Gray273"], X, Y, Z))
    m_lat = m_lat * _ss((-7.0 - X) / 3.0) * _ss((tops - 1.0 - Y) / 2.5)
    along = ((X - ch[0]) * Rh[0, 2] + (Y - ch[1]) * Rh[1, 2] + (Z - ch[2]) * Rh[2, 2])
    perp2 = (X - ch[0]) ** 2 + (Y - ch[1]) ** 2 + (Z - ch[2]) ** 2 - along ** 2
    m_nav = _ss((along + 0.02 * perp2 - 10.0) / 1.2); del perp2     # (its border an oval round the head, not a plane's edge)
    M = np.zeros(F.D.shape, np.float32)
    for m in (trochlea, m_med, m_lat, m_nav, m_under):
        M = np.maximum(M, np.broadcast_to(m, F.D.shape))
    del m_under, m_med, m_lat, m_nav, trochlea, along
    M = ndi.gaussian_filter(_ss((M - 0.25) / 0.5).astype(np.float32), 0.7 / h)
    Ds = ndi.gaussian_filter(F.D, 0.8 / h); F.D += (Ds - F.D) * ndi.gaussian_filter(M, 0.6 / h); del Ds
    ring = np.clip(2.5 * ndi.gaussian_filter(M, 0.9 / h), 0.0, 1.0)
    F.D += 0.6 * ring * (1.0 - M); del ring
    # and at the border itself a faint lip, 0.3 mm proud, so each surface reads bounded against the rough bone
    F.D -= 0.3 * np.exp(-((M - 0.45) / 0.2) ** 2)
    F.smooth = M
    # 4. the plates' relief (off by default: the hollows are cut from Gray's text, not chased in the engraving's tone)
    if relief:
        emboss(F, tr, TALUS, P, relief, log)
    if ink:
        # (not where a plate sees the surface edge-on and its ink would be drawn out into streaks: the neck's upper
        # surface in Fig. 270, the posterior surface in all four; the neck's small pits are laid on as marks instead)
        maps = {f: tr[f + "_ink"].astype(np.float32) * (ink / 50.0) for f in V}
        cut = {"Gray270": [[(195, 95), (310, 95), (310, 178), (195, 178)], [(190, 318), (300, 318), (300, 370), (190, 370)]],
               "Gray271": [[(100, 330), (200, 330), (200, 380), (100, 380)]],
               "Gray272": [[(120, 100), (200, 100), (200, 200), (120, 200)]],
               "Gray273": [[(262, 80), (330, 80), (330, 170), (262, 170)]]}
        for f, polys in cut.items():
            maps[f] = maps[f] * (1.0 - _mask(maps[f].shape, polys, 12.0 if f == "Gray270" else 4.0))   # (the neck's fades out)
        lay(F, TALUS, P, maps, shared=True, rough=True)
    pits = [("dot", q, r, -dp) for q, r, dp in _neck_pits()]
    lay(F, TALUS, P, {"Gray270": foot._marks_map(pits, tr["Gray270_sdf"].shape, V["Gray270"]["s"] * P["Gray270"][3])})
    log("talus: built from its four plates")
    return _one_piece(F)
