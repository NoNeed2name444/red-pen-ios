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
  1. the solid inside the four outlines, the edges between rounded (foot.calcaneus's way); the body (trochlea, its two
     side walls) rebuilt from coronal sections held inside those outlines (2a);
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
# Fig. 270, from above: the trochlea's own border (column, row), the engraved line inside the silhouette that bounds
# the articular surface (read on the 1918 book's 300 dpi page, PDF page 266, brought into the plate's pixels): wider
# in front than behind, the medial border nearly straight, the lateral one the longer and curved. Outside it, between
# the lateral border and the silhouette, the plate shows the strip "for lateral malleolus" (the facet seen from above:
# the wall leans out below the border) and behind it the narrow one "for inferior transverse ligament"; medially a
# narrower strip "for medial malleolus" toward the front. Its front border is notched where the neck's upper surface
# runs back into it.
TROCH_EDGE_270 = [(150, 172), (140, 182), (139, 205), (141, 232), (145, 250), (152, 263), (161, 276), (168, 288), (175, 299),
                  (187, 312), (200, 322), (215, 329), (230, 331), (260, 326), (280, 318), (292, 305), (297, 280), (297, 220),
                  (296, 172), (285, 160), (270, 168), (258, 177), (245, 168), (225, 158), (200, 155), (175, 160)]
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

# Its place in the foot: foot_frame.py's frame (the navicular's: x medial, y up, z forward, mm), frame point =
# AT_R @ bone point + AT_T. foot_frame.TARGET["talus"], this bone fitted rigidly to its outlines in Fig. 268, 290 and 291
# through that frame's registration (T-foot-seat, 25 Nov; outline gaps 1.17 / 2.99 / 2.24 mm mean). It replaces the
# pose the navicular's round seated it at (turned -5 degrees about y, t (-8.17, -13.21, -59.99): its head in the
# navicular's hollow, the body 15 degrees too far head-down, 5.6 mm too medial, 4.8 mm too far forward; 3.6 / 4.0 /
# 4.3 mm against the three plates). Only the pose: the bone's own field is untouched.
AT_R = ((0.9969, -0.0754, -0.0212), (0.0784, 0.9638, 0.2549), (0.0012, -0.2558, 0.9667))
AT_T = (-8.82, -20.14, -58.76)
# The head's articular surface as an ellipsoid in this bone's frame (the front 9 mm facing forward fitted, 0.4 mm rms):
# centre, axes (columns), semi-axes; midfoot.NAV_HEAD_* is this carried by AT_R, AT_T.
HEAD_C = (3.405, 17.251, 36.003)
HEAD_AX = ((0.8399, 0.5364, -0.0826), (-0.5427, 0.8301, -0.1278), (0.0, 0.1522, 0.9884))
HEAD_R = (21.6, 16.58, 25.0)


def at():
    """(R, t) of the bone in the foot frame, R made exactly orthonormal."""
    u, _, vt = np.linalg.svd(np.asarray(AT_R, float)); return u @ vt, np.asarray(AT_T, float)


def to_foot(P):
    """This bone's points (..., 3) in the foot frame."""
    R, t = at(); return np.asarray(P, float) @ R.T + t


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
    D = _round_meet(plan, side, R)
    box = _round_meet(plan, side, 1.8); del plan, side    # (the same, its edges rounded less: the sections' cap, 2a)
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

    # 2a. the body, built up from coronal sections rather than taken as the four outlines' common solid (four silhouettes
    # cannot give a pulley or leaning walls: the common solid is a box with a flat top and upright sides). At each z:
    #   the top, a pulley: "convex from before backward, slightly concave from side to side": its two shoulders as high
    #   as the side plates draw the top there, a groove 1.3 mm deep between them, the lateral shoulder a little the
    #   higher and the sharper (rounded over 1.2 mm, the medial over 2.6);
    #   its borders as Fig. 270 draws them: broader in front than behind, the medial border straight, the lateral
    #   curved and, behind, bevelled into the narrow facet for the inferior transverse ligament;
    #   the lateral wall, "a large triangular facet, concave from above downward, for articulation with the lateral
    #   malleolus", leaning out from the trochlea's border (where it starts upright) to the bone's outline at the facet's
    #   lower border (Fig. 273), its apex on the lateral process (x follows the depth below the border as 0.8 t + 0.2 t^2:
    #   it leans out from the border itself, so from above the facet shows as a strip, as in Fig. 270);
    #   the medial wall: the pear-shaped facet for the medial malleolus (Fig. 272) nearly upright under the rounded
    #   medial border, broad in front and tapering behind; below and behind it the rough bone stands 1.6 mm further out.
    # Each section is a set of distances, met with rounded edges (_round_meet), held inside the four outlines with a
    # rounded meeting too, and eased into the rest of the bone in front (the neck) and behind (the posterior process).
    tm = _mask(tr["Gray270_sdf"].shape, [TROCH_EDGE_270], 0.5) > 0.5
    rows = np.arange(tm.shape[0]); has = tm.any(1)
    lat = np.interp(rows, rows[has], np.argmax(tm, 1)[has].astype(float))           # the trochlea's lateral border per row
    u_top = np.interp(r2, rows, ndi.gaussian_filter1d(lat, 2.0)); u_med = _line(r2, TROCH_MED_270)
    sil = tr["Gray270_sdf"].astype(np.float32) < 0
    first = np.where(sil.any(1), np.argmax(sil, 1), 400).astype(float)
    u_out = np.interp(r2, rows, ndi.gaussian_filter1d(ndi.minimum_filter1d(first, 5), 7.0))       # the lateral outline
    tox = lambda u: ((u[0] - v270["u0"] - p270[4]) * s270)[None, None, :]
    xl = tox(u_top); xm = tox(u_med); xo = tox(u_out) - 0.6                 # x of the two borders and of the outline
    xc = 0.5 * (xl + xm); hw = 0.5 * (xm - xl)
    Yb = F.ax[1][None, :, None]; Zb = F.ax[2][None, None, :] + 0.0 * Yb
    sx = (F.ax[0][:, None, None] - xc) / hw                                                      # -1 at the lateral border, +1 the medial
    zz = F.ax[2]
    # the shoulders' heights: each side plate is seen from some 10 degrees above, so the top of its outline is the far
    # border of the trochlea (Fig. 273's the medial border, Fig. 272's the lateral): read off the outlines' sharp common
    # solid just inside each border
    _, btop = _surface_maps(F, box); btop = _fill(btop, 1.0 / h)
    def at(xq, dx):
        i = np.clip(np.round((xq[0, 0] + dx - F.lo[0]) / h), 0, F.n[0] - 1).astype(int)
        return ndi.gaussian_filter1d(btop[i, np.arange(F.n[2])], 1.2 / h)[None, None, :]
    HL = at(xl, 1.5); HM = at(xm, -2.0); Hc = np.maximum(HL, HM); del btop
    wt = _bump(zz, 3.0, 8.0, 40.0, 45.0)[None, None, :]
    sc = np.clip(sx, -1.0, 1.0)
    Ttop = HL + (HM - HL) * 0.5 * (1.0 + sc) + 0.5 - 1.9 * wt * (1.0 - sc ** 2) ** 1.2; del sc
    def unitd(d, *g):          # a height-field's or wall's difference made a distance (divided by its slope)
        return d / np.sqrt(1.0 + sum(gi ** 2 for gi in g))
    gx, gz = np.gradient(Ttop[:, 0, :], h)
    Dtop = unitd(Y - Ttop, gx[:, None, :], gz[:, None, :]); del Ttop, gx, gz
    # the lateral wall
    y_low = ndi.gaussian_filter1d(np.interp(zz, [a for a, _ in FACET_LOW], [b for _, b in FACET_LOW]), 1.5 / h)[None, None, :]
    ye = Hc - 0.6
    t = np.clip((ye - Yb) / np.maximum(ye - y_low, 4.0), 0.0, None)
    # (the turn is strongest behind the apex, under the triangle's hind edge, where the rough bone between the facet and
    # the posterior calcaneal surface faces back and down; under the apex the lateral process keeps its outline)
    wti = (0.55 + 0.9 * _bump(zz, 8.0, 12.0, 22.0, 27.0))[None, None, :] * _bump(zz, 5.0, 10.0, 30.0, 35.0)[None, None, :]
    tl = np.minimum(t, 1.0)
    XL = xl + (xo - xl) * (0.8 * tl + 0.2 * tl ** 2) + (0.7 * wti - 1.0 * (1.0 - wti)) * np.maximum(t - 1.0, 0.0) * (ye - y_low)
    XL = ndi.gaussian_filter1d(XL, 0.9 / h, axis=1)      # (below its lower border the bone turns back in: a rounded ridge)
    wl = _bump(zz, 3.0, 9.0, 39.0, 44.0)[None, None, :]
    XL = XL + (xo - 8.0 - XL) * (1.0 - wl)
    gy, gz = np.gradient(XL.astype(np.float32), h, axis=(1, 2))
    Dlat = unitd(XL - X, gy, gz); del XL, gy, gz, t
    # the medial wall, the facet read off Fig. 272 at the trochlea's medial border
    v272 = V["Gray272"]
    fm = _read(_mask(tr["Gray272_sdf"].shape, [MED_FACET_272], 3.0), *_pixels(v272, P["Gray272"], xm + 0.0 * Yb, Yb, Zb))
    # (the border between the facet and the rough bone below an irregular line, not the tracing's smooth curve)
    wob = ndi.gaussian_filter(np.random.default_rng(272).normal(0.0, 1.0, fm.shape[1:]), 1.3 / h)
    wob = (wob / max(float(np.abs(wob).max()), 1e-6))[None]
    fm = ndi.gaussian_filter(np.clip(1.6 * fm + 0.45 * wob, 0.0, 1.0), 0.6 / h); del wob
    XM = xm - 0.4 + (0.08 + 0.14 * _ss((Zb - 22.0) / 6.0)) * np.maximum(Hc - Yb, 0.0) + (2.9 + 6.0 * _ss((Zb - 36.0) / 5.0)) * (1.0 - fm) * _ss((Hc - 1.5 - Yb) / 2.5)
    wm = _bump(zz, 4.0, 9.0, 41.0, 46.0)[None, None, :]
    XM = XM + 8.0 * (1.0 - wm)
    gy, gz = np.gradient(XM[0].astype(np.float32), h)
    Dmed = unitd(X - XM, gy[None], gz[None]); del XM, gy, gz, fm
    # (behind, the lateral border bevelled into the facet for the inferior transverse ligament and both corners rounded)
    # (the radii vary along the border, as a worn edge does: laterally 1.6 to 2.4 mm, medially 3.2 to 4.0)
    Rl = 2.0 + 0.4 * np.cos((Zb - 14.0) / 5.5) + 3.0 * _ss((18.0 - Zb) / 9.0)
    Rm = 3.6 + 0.4 * np.sin((Zb - 20.0) / 4.5) + 1.8 * _ss((15.0 - Zb) / 7.0)
    Dsec = _round_meet(_round_meet(Dtop, Dlat, Rl), Dmed, Rm * _ss((sx + 0.2) / 0.6) + Rl * (1.0 - _ss((sx + 0.2) / 0.6)))
    del Dtop, Dlat, Dmed
    # held in the outlines: above, the sharp common solid (its rounding would take the shoulders down), lower the rounded
    cap = D + (box - 0.4 - D) * _ss((Y - (tops - 9.0)) / 4.0)
    Dsec = _round_meet(Dsec, cap, 1.5); del cap
    wb = _bump(zz, 4.0, 10.0, 38.0, 45.0)[None, None, :]
    D = (D + (Dsec - D) * wb).astype(np.float32); del Dsec, box, sx
    lo, top = _surface_maps(F, D); lo = _fill(lo, 1.0 / h); top = _fill(top, 1.0 / h)
    tops = ndi.gaussian_filter(top, 3.0 / h)[:, None, :]
    near_top = _ss((Y - (tops - 9.0)) / 7.0)        # (a displacement eased in over less than about three times its size folds the surface)

    # in front of its border the upper surface falls away to the neck: the border as Fig. 270 draws it, notched in
    # the middle (the side outlines alone would leave it a straight edge across)
    # behind and medially it ends where its outline in Fig. 270 ends (the side outlines alone would square it off)
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
    # a dish 2 mm deep, about 9 by 6 mm, eased out all round
    D = D + 2.0 * np.exp(-((X - 3.6) / 4.2) ** 2 - ((Z - 42.4) / 3.0) ** 2) * _ss((Y - (tops - 8.0)) / 6.0)

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
    # (the surface's fall from behind forward, as the two side plates draw its margins (T-subtalar, 25 Nov): the hull
    # left it too level. Under the lateral process, Fig. 273's lower outline stands 1.6 to 3.2 mm below the hull's
    # (columns 180 to 228, z 16 to 26); behind, both side plates draw it higher than the hull: Fig. 273 by 1.2 to 3.4
    # mm (columns 258 to 290), Fig. 272 by 1.0 to 2.2 (columns 146 to 188), z 1 to 10. So the lateral front of the
    # surface comes down 2.4 mm and its hind part goes up 1.8, both eased over 5 mm: the surface then falls forward as
    # the calcaneus's posterior surface rises backward, "deeply concave" still along its long axis.)
    down = 2.4 * _bump(zs, 11.0, 17.0, 25.0, 31.0) * _ss((-6.0 - xs) / 7.0) * _ss((mpost - 0.1) / 0.4)
    D = D - ndi.gaussian_filter(down.astype(np.float32), 2.0 / h)[:, None, :] * _ss((los + 10.0 - Y) / 8.0); del down
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
    D = sdf.smin(D, Ellipsoid((-4.5, 18.5, 9.5), (7.5, 4.6, 5.4), rot((0, 0, 1), -20.0) @ rot((1, 0, 0), 20.0))(X, Y, Z), 11.0)
    # and the smaller medial tubercle, below and medial of the groove (Fig. 270 at (280, 322), Fig. 272 at (178, 172))
    D = sdf.smin(D, Ellipsoid((7.4, 13.6, 11.0), (3.4, 2.8, 4.4))(X, Y, Z), 6.0)

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
    # (and the hind part of the posterior calcaneal surface raised, the tubercles' undersides with it: see 2d)
    up = 1.8 * (1.0 - _ss((zs - 7.0) / 6.0)) * _ss((mpost - 0.1) / 0.4)
    D = D + ndi.gaussian_filter(up.astype(np.float32), 2.0 / h)[:, None, :] * _ss((los + 12.0 - Y) / 8.0); del up

    # the lateral malleolar facet stands as a low triangular table on the lateral surface: round it, under the trochlea's
    # border and above the calcaneal surfaces, the rough bone (in front the neck's side, behind the strip between the
    # facet's hind edge and the posterior calcaneal surface) lies 1 mm lower, eased over 2 to 3 mm (Fig. 273's tracing)
    v273 = V["Gray273"]
    m273 = _read(_mask(tr["Gray273_sdf"].shape, [LAT_FACET_273], 3.0), *_pixels(v273, P["Gray273"], X, Y, Z))
    sink = (1.0 - np.clip(1.5 * m273, 0.0, 1.0)) * _ss((-14.0 - X) / 3.0) * _ss((HL - 2.0 - Y) / 2.5) \
        * _ss((Y - (los + 4.0)) / 2.5) * _bump(Z, 4.0, 8.0, 34.0, 39.0)
    D = D + 1.0 * ndi.gaussian_filter(sink, 0.8 / h); del m273, sink

    D = ndi.gaussian_filter(D, 0.5 / h)          # (the cuts' last voxel-sized kinks would print as speckle)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D
    F = _one_piece(F)

    # 3. the joint surfaces: the trochlea, the two malleolar facets, the head's surface for the navicular, and below the
    # three calcaneal surfaces with the one for the plantar calcaneonavicular ligament, each where its plate draws its
    # border. A joint surface is smooth (eased over a millimetre, no grain or plate ink) and ends at a rim: the rough
    # bone round it stands half a millimetre lower.
    lo2, top2 = _surface_maps(F, F.D); lo2 = _fill(lo2, 2.0 / h)      # (eased: where the column overhangs, its lowest point jumps)
    under = _ss((lo2[:, None, :] + 4.5 - Y) / 3.0)      # (every gate eased over millimetres: a sharp one prints the grid as dots)
    def below2(polys):
        m = _mask(shape271, polys, 4.0)
        return _read(m, *_pixels(v271, p271, xs, lo2 + 1.0, zs))[:, None, :] * under
    m_under = np.maximum(np.maximum(below2([POST_FACET_271]), below2([MID_FACET_271])), below2([ANT_FACET_271, LIG_FACET_271]))
    v272 = V["Gray272"]; m_med = _read(_mask(tr["Gray272_sdf"].shape, [MED_FACET_272], 4.0), *_pixels(v272, P["Gray272"], X, Y, Z))
    m_med = m_med * _ss((X - 5.0) / 3.0) * _ss((HM - 1.0 - Y) / 2.0)     # (below the trochlea's own border, not the column's top)
    v273 = V["Gray273"]; m_lat = _read(_mask(tr["Gray273_sdf"].shape, [LAT_FACET_273], 4.0), *_pixels(v273, P["Gray273"], X, Y, Z))
    m_lat = m_lat * _ss((-7.0 - X) / 3.0) * _ss((HL - 1.0 - Y) / 2.0)
    along = ((X - ch[0]) * Rh[0, 2] + (Y - ch[1]) * Rh[1, 2] + (Z - ch[2]) * Rh[2, 2])
    perp2 = (X - ch[0]) ** 2 + (Y - ch[1]) ** 2 + (Z - ch[2]) ** 2 - along ** 2
    m_nav = _ss((along + 0.035 * perp2 - 0.02 * (X - 2.0) ** 2 + 0.8 * np.sin(0.45 * X + 0.25 * Y) + 0.4 * np.sin(1.1 * X - 0.5 * Y + 1.0) - 10.0) / 1.5); del perp2     # (its border an oval round the head, not a plane's edge)
    M = np.zeros(F.D.shape, np.float32)
    for m in (trochlea, m_med, m_lat, m_nav, m_under):
        M = np.maximum(M, np.broadcast_to(m, F.D.shape))
    del m_under, m_med, m_lat, m_nav, trochlea, along
    M = ndi.gaussian_filter(_ss((M - 0.25) / 0.5).astype(np.float32), 0.7 / h)
    Ds = ndi.gaussian_filter(F.D, 0.8 / h); F.D += (Ds - F.D) * ndi.gaussian_filter(M, 0.6 / h); del Ds
    ring = np.clip(2.5 * ndi.gaussian_filter(M, 0.9 / h), 0.0, 1.0)
    behind = _ss((Z - 7.0) / 6.0)      # (not round the posterior process: there the facet runs out onto the tubercle)
    F.D += 0.6 * ring * (1.0 - M) * behind; del ring
    # and at the border itself a faint lip, 0.3 mm proud, so each surface reads bounded against the rough bone
    F.D -= 0.3 * np.exp(-((M - 0.45) / 0.2) ** 2) * behind; del behind
    F.smooth = M
    # 4. the plates' relief (off by default: the hollows are cut from Gray's text, not chased in the engraving's tone)
    if relief:
        emboss(F, tr, TALUS, P, relief, log)
    if ink:
        # (not where a plate sees the surface edge-on and its ink would be drawn out into streaks: the neck's upper
        # surface in Fig. 270, the posterior surface in all four; the neck's small pits are laid on as marks instead)
        maps = {f: tr[f + "_ink"].astype(np.float32) * (ink / 50.0) for f in V}
        cut = {"Gray270": [[(195, 95), (310, 95), (310, 178), (195, 178)], [(190, 318), (300, 318), (300, 370), (190, 370)]],
               "Gray271": [[(100, 330), (200, 330), (200, 380), (100, 380)], [(72, 288), (142, 288), (142, 348), (72, 348)]],
               "Gray272": [[(120, 100), (200, 100), (200, 200), (120, 200)]],
               "Gray273": [[(262, 80), (330, 80), (330, 170), (262, 170)]]}
        for f, polys in cut.items():
            maps[f] = maps[f] * (1.0 - _mask(maps[f].shape, polys, 12.0 if f == "Gray270" else 4.0))   # (the neck's fades out)
        lay(F, TALUS, P, maps, shared=True, rough=True)
    pits = [("dot", q, r, -dp) for q, r, dp in _neck_pits()]
    lay(F, TALUS, P, {"Gray270": foot._marks_map(pits, tr["Gray270_sdf"].shape, V["Gray270"]["s"] * P["Gray270"][3])})
    # the rough bone under the medial facet, for the deltoid ligament: Fig. 272's scattered pits (cols 190 to 300, rows
    # 100 to 150), mixed sizes, none in a row; not on the facet itself (rough=True)
    rng = np.random.default_rng(2720); dp = []
    while len(dp) < 26:
        c, r = rng.uniform(188.0, 300.0), rng.uniform(104.0, 152.0)
        if all(np.hypot(c - a, r - b) > 6.0 for (a, b), _, _ in dp):
            dp.append(((c, r), rng.uniform(0.3, 0.65), rng.uniform(0.12, 0.3)))
    lay(F, TALUS, P, {"Gray272": foot._marks_map([("dot", q, a, -b) for q, a, b in dp], tr["Gray272_sdf"].shape, V["Gray272"]["s"] * P["Gray272"][3])}, rough=True)
    log("talus: built from its four plates")
    return _one_piece(F)
