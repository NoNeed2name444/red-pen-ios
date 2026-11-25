"""midfoot.py: the right cuboid and the right navicular, built as foot.py builds the heel bone: from nothing but
Gray's plates (Anatomy of the Human Body, 1918, public domain) and his text. No scan and no other model is used.

Each of the two has only two plates of its own, and the two are drawn from nearly opposite sides (the cuboid: Fig. 274
"antero-medial view", Fig. 275 "postero-lateral view"; the navicular: Fig. 276 "antero-lateral view", Fig. 277
"postero-medial view"; all of the LEFT bone, so each is written as a mirror view of the right-hand model). Two such
outlines fix the bone's section across the line of sight and say nothing of its length along it. That comes from the
whole-foot plates of the right foot: Fig. 268 (dorsal) gives each bone's plan, Fig. 269 (plantar) the cuboid's ridge
and groove, Fig. 290 and 291 (medial and lateral) the heights. Those two are read by hand under a pixel grid and
written here as lists of millimetres; their scale is the heel bone's: 79 mm long (foot.py), which is 0.208 mm a
pixel in Fig. 268 and 269.

Frame of each bone (right bone, as it lies in the foot): x medial, y up, z forward, millimetres.
  cuboid: origin at the hind lateral corner of its dorsal surface as Fig. 268 draws it, at the level of the sole side.
  navicular: origin at the middle of the bone.
"""
import os
import numpy as np
from scipy import ndimage as ndi
import sdf
import platematch as pm
import foot
from foot import _ss, _bump, _read, _pixels, _round_meet, _cut, _tube, _one_piece, _marks_map, lay, emboss, grain, INK
from sdf import Ellipsoid, Field, rot

HERE = os.path.dirname(os.path.abspath(__file__))

# Gray 1918, the left cuboid. Fig. 274 looks at the medial surface (the facet for the third cuneiform nearly square
# to the eye) with the front surface turning away on the right; Fig. 275 looks into the surface for the calcaneus from
# behind, the lateral side and above, the lateral surface with the notch of the peroneal sulcus turning away on the left.
# The angles are worked out from where the plan's corners (Fig. 268) fall in each plate, not left to an outline fit
# (two outlines seen from nearly opposite sides fill equally well at any scale): in Fig. 274 the hind medial corner,
# the edge between the medial and the front surface and the front lateral corner lie at columns 150, 277 and 333,
# which the plan gives when the eye stands 10 degrees medial of straight in front, at 0.161 mm a pixel; in Fig. 275 the
# hind medial corner, the facet's lateral rim and the front lateral corner lie at 240, 140 and 65: 24 degrees lateral
# of straight behind, 0.18 mm a pixel. Both are level views: so held, both plates give the same height (25 and 26 mm),
# the same lateral border (13 and 15 mm tall) and the same drop of the hind medial corner below the top (5 and 6 mm).
CUBOID = [
    dict(fig="Gray274", cap="antero-medial view", right=(-1, 0, 0), up=(0, 1, 0), eye=(0, 0, 1), s=0.156, u0=228, v0=124,
         pose=(0.0, 10.0, 0.0, 1.03, 43.902, 66.342), free=(0, 0, 0, 0, 1, 1)),
    dict(fig="Gray275", cap="postero-lateral view", right=(1, 0, 0), up=(0, 1, 0), eye=(0, 0, -1), s=0.156, u0=167, v0=83,
         pose=(0.0, 24.0, 0.0, 1.15, -23.6, 58.824), free=(0, 0, 0, 0, 1, 1)),
]
NAVICULAR = [
    dict(fig="Gray276", cap="antero-lateral view", right=(-1, 0, 0), up=(0, 1, 0), eye=(0, 0, 1), s=0.14, u0=176, v0=137,
         pose=(10.0, -20.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
    dict(fig="Gray277", cap="postero-medial view", right=(1, 0, 0), up=(0, 1, 0), eye=(0, 0, -1), s=0.08, u0=465, v0=255,
         pose=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
]
PLATES = {"cuboid": CUBOID, "navicular": NAVICULAR}


def traces(name):
    return np.load(os.path.join(HERE, "traces", name + "_plates.npz"))


def _plan(poly, x, z, step=0.2, pad=8.0, ease=0.8):
    """A traced plan (a closed line of (x, z) in mm, eased through its points) as distance from it at each (x, z):
    below 0 inside."""
    from PIL import Image, ImageDraw
    P = sdf.spline(np.asarray(poly, float), 0.5, closed=True); lo = P.min(0) - pad; hi = P.max(0) + pad
    W, H = (np.ceil((hi - lo) / step).astype(int) + 1)
    im = Image.new("L", (int(W), int(H)), 0); ImageDraw.Draw(im).polygon([((a - lo[0]) / step, (b - lo[1]) / step) for a, b in P], fill=255)
    m = np.asarray(im) > 0
    d = ndi.gaussian_filter((ndi.distance_transform_edt(~m) - ndi.distance_transform_edt(m)).astype(np.float32), ease / step) * step
    shape = np.broadcast(x, z).shape
    c = [((np.broadcast_to(z, shape) - lo[1]) / step).ravel(), ((np.broadcast_to(x, shape) - lo[0]) / step).ravel()]
    return ndi.map_coordinates(d, c, order=1, mode="nearest").reshape(shape).astype(np.float32)


def _heights(D, F, ease=0.8):
    """The solid's top and bottom (y, mm) over each point of the plan, eased; where it has none, the nearest's."""
    inside = D < 0; got = inside.any(1); Y = F.ax[1]; n = inside.shape[1]
    top = Y[n - 1 - np.argmax(inside[:, ::-1, :], 1)]; bot = Y[np.argmax(inside, 1)]
    i = ndi.distance_transform_edt(~got, return_distances=False, return_indices=True)
    top = top[i[0], i[1]]; bot = bot[i[0], i[1]]
    return ndi.gaussian_filter(top, ease / F.h).astype(np.float32), ndi.gaussian_filter(bot, ease / F.h).astype(np.float32)


def _lay(F, views, poses, maps, face=0.3, shared=False, rough=False):
    """foot.lay, but only on what faces each plate squarely (n . eye above `face`): a facet traced on a plate is not
    carried on to the faces the plate sees edge-on, where it would print the tracing's outline as straight bands."""
    D = F.D; idx = np.nonzero(np.abs(D) < 3.0)
    g = np.gradient(ndi.gaussian_filter(D, 1.0 / F.h), F.h)
    n = np.stack([c[idx] for c in g], 1); n /= np.maximum(np.linalg.norm(n, axis=1), 1e-9)[:, None]; del g
    P = np.stack([F.ax[k][idx[k]] for k in range(3)], 1).astype(np.float64)
    total = np.zeros(len(P), np.float32); wsum = np.zeros(len(P), np.float32); ease = foot._unhidden(F, idx)
    for v in views:
        m = maps.get(v["fig"])
        if m is None:
            continue
        pose = poses[v["fig"]]; B = pm.basis(v, pose[:3]); px = v["s"] * pose[3]
        depth, _ = pm.cast(F, B, px, v["u0"] + pose[4], v["v0"] + pose[5], m.shape[::-1], normals=False)
        u, r = _pixels(v, pose, P[:, 0], P[:, 1], P[:, 2])
        front = _read(np.where(np.isnan(depth), -1e3, depth), u, r)
        wt = ease(_ss((P @ B[2] - front + 3.0) / 2.0)) * _ss((n @ B[2] - face) / 0.3)
        total += (wt * _read(m, u, r)).astype(np.float32); wsum += wt.astype(np.float32)
    if shared:
        total /= np.maximum(wsum, 1.0)
    if rough and hasattr(F, "smooth"):
        total *= 1.0 - np.clip(F.smooth[idx], 0.0, 1.0)
    D[idx] -= total
    return F


def _emboss(F, tr, views, poses, gain, log, face=0.4):
    """foot.emboss, kept to the faces the plates see squarely: where a plate meets the surface at a slant its shading
    relief comes out as fine combed ripples (the cuboid's sole had them along its medial edge), so the relief is taken
    off again there, in proportion as no plate faces the surface."""
    D0 = F.D.copy(); g = np.gradient(ndi.gaussian_filter(D0, 1.0 / F.h), F.h)
    nrm = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6; w = np.zeros(D0.shape, np.float32)
    for v in views:
        e = pm.basis(v, poses[v["fig"]][:3])[2]
        w = np.maximum(w, _ss(((g[0] * e[0] + g[1] * e[1] + g[2] * e[2]) / nrm - face) / 0.3))
    del g, nrm
    emboss(F, tr, views, poses, gain, log)
    F.D = (D0 + (F.D - D0) * w).astype(np.float32)
    return F


def _pits(items, px, seed=7):
    """The plates' small foramina as marks: no drilled round holes, but short, uneven slits and pits, each its own size,
    bearing and depth."""
    rng = np.random.default_rng(seed); out = []
    for it in items:
        if it[0] != "dot":
            out.append(it); continue
        (u, v), r, hgt = it[1], it[2], it[3]
        a = rng.uniform(0, np.pi); L = r / px * rng.uniform(0.9, 1.6); c = rng.uniform(-0.3, 0.3) * L
        pts = [(u - L * np.cos(a), v - L * np.sin(a)), (u + c * np.sin(a), v - c * np.cos(a)), (u + L * np.cos(a), v + L * np.sin(a))]
        out.append(("line", pts, r * rng.uniform(1.0, 1.4), hgt * rng.uniform(0.45, 0.7)))
    return out


def _rough(poly, n, seed, r=(0.2, 0.55), deep=(-0.75, -0.35), lumps=8, lift=(0.25, 0.5)):
    """A rough patch a plate draws as pitted, uneven bone, as marks: `n` pits strewn over the traced patch at chance
    (each its own size and depth; _pits makes them slits and pits, not drilled holes) and a few low, uneven swellings
    and hollows between them."""
    from PIL import Image, ImageDraw
    rng = np.random.default_rng(seed); poly = np.asarray(poly, float)
    im = Image.new("L", (400, 400), 0); ImageDraw.Draw(im).polygon([tuple(q) for q in poly], fill=255); inside = np.asarray(im) > 0
    lo, hi = poly.min(0), poly.max(0); out = []
    while len(out) < n:
        p = rng.uniform(lo, hi)
        if inside[int(p[1]), int(p[0])]:
            out.append(("dot", (float(p[0]), float(p[1])), float(rng.uniform(*r)), float(rng.uniform(*deep))))
    k = 0
    while k < lumps:
        p = rng.uniform(lo, hi)
        if inside[int(p[1]), int(p[0])]:
            a = rng.uniform(4, 9); t = np.linspace(0, 2 * np.pi, 9)[:-1]; rad = a * rng.uniform(0.6, 1.3, len(t))
            out.append(("area", [(float(p[0] + q * np.cos(w)), float(p[1] + 0.8 * q * np.sin(w))) for q, w in zip(rad, t)],
                        float(rng.choice([-1, 1]) * rng.uniform(*lift)), 1.0)); k += 1
    return out


# Fig. 268 (the right foot from above), the cuboid's dorsal surface, read under a grid at 0.208 mm a pixel from its
# hind lateral corner at pixel (190, 388): x toward the big toe's side, z toward the toes.
CUB_PLAN = [(-1.0, 0.3), (5.0, -1.2), (11.5, -0.8), (16.5, 0.2), (21.0, 2.3),               # behind, against the calcaneus
            (21.4, 5.0), (19.0, 8.6), (15.4, 12.2), (11.6, 15.6), (8.4, 19.0), (6.2, 24.0), (5.0, 30.2),      # medial, against the navicular's end and the third cuneiform
            (2.2, 28.6), (-1.8, 25.6), (-4.8, 22.6), (-6.2, 19.2),                         # in front, the fourth and fifth metatarsals
            (-4.2, 16.0), (-3.0, 11.0), (-2.6, 5.0)]                                       # lateral, to the notch of the peroneal sulcus
# (the lateral border is set 1 mm out from the first reading: so Fig. 268's edge, Fig. 274's right side and Fig. 275's
# left side all agree)
# The plan low down, which Fig. 268 cannot show. Behind, the infero-medial angle "projects backward as a process which
# underlies and supports the anterior end of the calcaneus": Fig. 275 draws its tip 5.6 mm (31 pixels) beyond the hind
# medial corner, Fig. 274 has it the lowest, hindmost point. The medial surface is "broad" and has no dent below (the
# dent of the dorsal plan is where the third cuneiform lies over it). In front and laterally Fig. 275's outline stands
# 3 mm beyond the dorsal plan's corner: the base under the fifth metatarsal, in front of the sulcus.
CUB_SOLE = [(-1.0, 0.2), (5.0, -1.5), (12.0, -2.6), (18.0, -4.4), (23.0, -5.2), (25.6, -3.4),
            (25.4, 0.5), (23.0, 6.0), (20.0, 11.0), (16.2, 16.0), (12.4, 20.4), (9.2, 25.0), (7.0, 31.0),
            (3.0, 29.6), (-2.0, 26.6), (-6.0, 24.0), (-8.4, 21.6),
            (-8.0, 18.6), (-5.4, 15.2), (-3.6, 11.0), (-3.0, 5.0)]



# Marks traced on the cuboid's plates, in each plate's own pixels (as foot.CALC_MARKS). The joint surfaces first: each
# is raised half a millimetre with a clear edge and kept smooth.
CUB_FACETS = {
    "Gray274": [  # for the third cuneiform; behind it the occasional one for the navicular; the small oval low behind; in front the fourth and fifth metatarsals'
        [(160, 80), (165, 105), (172, 125), (180, 140), (192, 146), (200, 140), (207, 120), (217, 105), (232, 95), (243, 82), (245, 68),
         (238, 57), (225, 50), (205, 50), (185, 57), (170, 66)],
        [(146, 100), (152, 92), (157, 96), (161, 110), (166, 128), (170, 150), (169, 166), (164, 170), (159, 158), (152, 140), (146, 120)],
        [(141, 170), (143, 161), (148, 158), (152, 164), (152, 175), (148, 181), (143, 179)],
        [(280, 52), (290, 46), (297, 50), (298, 70), (299, 100), (300, 125), (299, 140), (291, 146), (282, 138), (276, 120), (274, 95), (275, 70)],
        [(304, 62), (312, 68), (322, 85), (330, 105), (331, 124), (324, 133), (311, 139), (305, 137), (304, 110), (303, 80)]],
    "Gray275": [  # for the calcaneus, running down on to the process; the oval on the tuberosity for the peroneal tendon's sesamoid
        [(141, 86), (146, 66), (160, 46), (178, 31), (196, 24), (215, 26), (231, 36), (239, 60), (243, 90), (250, 110), (262, 125), (271, 137),
         (267, 147), (250, 151), (225, 147), (200, 139), (175, 127), (155, 111), (144, 98)],
        [(96, 88), (104, 82), (113, 84), (120, 94), (124, 108), (124, 122), (118, 130), (110, 126), (102, 114), (96, 100)]],
}
CUB_MARKS = {
    "Gray274": [("line", [(246, 66), (236, 90), (222, 106), (210, 122), (205, 138)], 1.5, -0.8),         # the dark cleft along the cuneiform facet's front edge
                # the rough hollow between that facet and the metatarsals' (for the interosseous ligaments), and the oval swelling the plate draws in it
                ("area", [(232, 100), (244, 84), (252, 66), (262, 58), (271, 62), (273, 90), (274, 125), (270, 145), (258, 150), (244, 146), (234, 130), (228, 112)], -1.3, 1.6),
                ("area", [(240, 100), (248, 84), (258, 76), (265, 86), (266, 112), (260, 134), (250, 142), (242, 132), (238, 116)], 0.9, 1.2),
                ("dot", (224, 134), 0.55, -0.8), ("dot", (222, 161), 0.45, -0.6), ("dot", (212, 166), 0.4, -0.5), ("dot", (203, 168), 0.4, -0.5),
                ("dot", (194, 172), 0.35, -0.5), ("dot", (176, 166), 0.3, -0.4), ("dot", (156, 176), 0.35, -0.4),
                ("line", [(170, 160), (164, 168), (160, 176)], 0.9, -0.6)],                               # the notch under the navicular's facet
    "Gray275": [("dot", (124, 69), 1.0, -1.0), ("dot", (128, 45), 0.6, -0.8), ("dot", (137, 53), 0.5, -0.7), ("dot", (107, 33), 0.4, -0.5),
                ("dot", (86, 45), 0.4, -0.5), ("dot", (92, 70), 0.5, -0.6), ("dot", (84, 62), 0.4, -0.5), ("dot", (113, 62), 0.45, -0.5),
                ("dot", (190, 22), 0.5, -0.5),
                # the smooth swelling the plate bounds with a line on the dorsal surface
                ("area", [(100, 40), (108, 29), (124, 25), (137, 31), (139, 44), (130, 53), (114, 55), (102, 50)], 0.6, 1.0),
                # the calcaneal surface's rim, a definite edge all round
                ("line", [(141, 86), (146, 66), (160, 46), (178, 31), (196, 24), (215, 26), (231, 36), (239, 60), (243, 90), (250, 110),
                          (262, 125), (271, 137), (267, 147), (250, 151), (225, 147), (200, 139), (175, 127), (155, 111), (144, 98), (141, 86)], 1.1, 0.55),
                # the tuberosity: its oval facet stands out, with a rim, in front of the sulcus
                ("area", [(96, 88), (104, 82), (113, 84), (120, 94), (124, 108), (124, 122), (118, 130), (110, 126), (102, 114), (96, 100)], 1.9, 0.7),
                ("line", [(94, 85), (104, 79), (115, 81), (123, 93), (127, 108), (127, 124), (118, 133), (107, 129), (99, 115), (93, 100), (94, 85)], 1.0, 0.9),
                # (and a shallow furrow round it, which the plate shades dark: the rim stands up from it)
                ("line", [(89, 83), (103, 74), (118, 76), (128, 91), (132, 108), (132, 127), (120, 139), (104, 134), (94, 117), (88, 100), (89, 83)], 1.3, -0.7),
                ("area", [(126, 100), (136, 97), (143, 106), (148, 119), (141, 131), (130, 131), (127, 116)], -0.8, 1.2)]
               # the rough bone above and lateral to the calcaneal surface: pitted and uneven all over
               + _rough([(74, 28), (100, 15), (150, 15), (192, 21), (172, 33), (154, 50), (143, 72), (140, 92), (128, 96), (118, 82),
                         (100, 80), (84, 98), (72, 84), (71, 52)], 85, 275, r=(0.25, 0.75), deep=(-1.4, -0.6), lumps=18, lift=(0.45, 0.85)),
}


def _mask(polys, shape, soft=1.0):
    """Closed lines traced on a plate (pixels), filled: a picture the size of the plate, 1 inside, eased over `soft` pixels."""
    from PIL import Image, ImageDraw
    im = Image.new("L", (shape[1] * 3, shape[0] * 3), 0)
    for poly in polys:
        ImageDraw.Draw(im).polygon([((u + 0.5) * 3, (v + 0.5) * 3) for u, v in sdf.spline(np.asarray(poly, float), 2.0, closed=True)], fill=255)
    return ndi.gaussian_filter(np.asarray(im.resize((shape[1], shape[0]), Image.BOX), np.float32) / 255.0, soft)


def _shown(F, v, pose, img, deep=2.5):
    """A plate-sized picture's values at the points of the model's surface that plate sees (0 on what it does not):
    for every point of the grid within `deep` mm behind the surface the plate looks at, and facing it."""
    B = pm.basis(v, pose[:3]); px = v["s"] * pose[3]
    depth, _ = pm.cast(F, B, px, v["u0"] + pose[4], v["v0"] + pose[5], img.shape[::-1], normals=False)
    X, Y, Z = F.coords((slice(None),) * 3)
    u, r = _pixels(v, pose, X, Y, Z)
    front = _read(np.where(np.isnan(depth), -1e3, depth), u, r)
    return _read(img, u, r) * _ss((X * B[2][0] + Y * B[2][1] + Z * B[2][2] - front + deep + 1.0) / 1.0)


def _facets(F, views, P, tr, facets, proud=0.5, edge=0.35, face=0.3):
    """The joint surfaces traced on the plates: each raised `proud` mm with a clear edge, and marked smooth (no relief,
    no ink and little grain on them)."""
    sm = np.zeros(F.D.shape, np.float32); maps = {}
    for v in views:
        f = v["fig"]
        if f not in facets:
            continue
        px = v["s"] * P[f][3]; m = _mask(facets[f], tr[f + "_sdf"].shape, edge / px)
        sm = np.maximum(sm, _shown(F, v, P[f], _mask(facets[f], tr[f + "_sdf"].shape, 0.8 / px)))
        maps[f] = proud * _ss((m - 0.2) / 0.6)
    _lay(F, views, P, maps, face=face)
    F.smooth = np.clip(sm, 0.0, 1.0).astype(np.float32)
    return F


HULL_EASE = 0.6   # mm
TOP_GIVE = 0.35   # mm
BEV_OUT = 1.2     # mm: the corner above the calcaneal surface's lateral rim is taken off this far outside the rim's plane


def cuboid(h=0.3, log=print, relief=1.0, upto="all", poses=None, ink=INK):
    """upto="body": the plans carried through the bone's height, nothing more; "hull": what of it lies inside the
    outlines of Fig. 274 and 275 (what the plates' shifts are fitted on); "forms": with the forms cut by hand, before
    any plate's marks. `poses` tries other poses than the traces were made at ({fig: pose})."""
    F = Field((-12.0, -9.0, -11.0), (30.0, 31.0, 37.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    V = {v["fig"]: v for v in CUBOID}
    tr = traces("cuboid")
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}
    plan = _plan(CUB_PLAN, X, Z) + 0.0 * Y
    plan = plan + (_plan(CUB_SOLE, X, Z) - plan) * _ss((15.0 - Y) / 10.0)
    body = np.maximum(plan, np.maximum(Y - 27.0, -6.0 - Y))
    if upto == "body":
        F.D = np.clip(body, -12.0, 12.0).astype(np.float32); return F

    def outline(fig, ease=0.5):
        px = V[fig]["s"] * P[fig][3]; d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
        return _read(ndi.gaussian_filter(d, ease / px), *_pixels(V[fig], P[fig], X, Y, Z))

    # 1. inside the two plates' outlines and the plan. The two plates look along the bone from nearly opposite sides,
    # so their outlines' walls meet at a shallow angle all round: any rounding of that edge pulls both outlines in (a
    # rounded meet cost Fig. 275 a millimetre along its whole left side and top). They are met sharply, and the field
    # is then eased over twice the grid: the edge is resolved (met sharply and left so, it is finer than the grid and
    # reads as a dashed seam down the dorsal surface and a comb on the facets) and the bone's borders are as sharp as
    # Fig. 274 and 275 draw them. The front and back corners above are rounded by the crown below (2c).
    o4, o5 = outline("Gray274"), outline("Gray275")
    # (the two plates do not quite agree on the height: held level at the scales the plan gives, Fig. 275 has the top
    # border 1.2 mm higher than Fig. 274. The difference is split: Fig. 274's outline gives way by TOP_GIVE at the top)
    o4 = o4 - TOP_GIVE * _ss((Y - 17.0) / 5.0)
    D = ndi.gaussian_filter(np.maximum(np.maximum(o4, o5), body), HULL_EASE / F.h).astype(np.float32); del body, plan
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F

    # 2a. the front, "divided by a vertical ridge into two facets: the medial, quadrilateral in form, articulates with
    # the fourth metatarsal; the lateral, larger and more triangular, articulates with the fifth". Fig. 274 has the
    # ridge at column 300, two fifths of the way from the medial edge (277) to the lateral (333): the two facets are
    # two faces that meet along it, the fifth's turned 10 degrees more to the lateral side than the fourth's.
    rx, rz = 0.5, 25.8
    # (the faces stand where Fig. 268's plan has the front border, and the fifth's does not reach down over the base
    # in front of the sulcus, which Fig. 275 draws standing out laterally below the facet: there it gives way)
    for nx, nz, out in ((-0.62, 0.785, 1.4), (-0.78, 0.626, 1.4)):
        e = (X - rx) * nz - (Z - rz) * nx                    # across the face, and up it: each a little convex, no plane
        e = np.maximum(e, -1.0) if nx > -0.7 else np.minimum(e, 1.0)      # (each face's curve ends at the ridge: beyond it the other face rules)
        bow = 0.011 * (e - 4.0 * np.sign(nx + 0.7)) ** 2 + 0.005 * (Y - 12.0) ** 2 + 0.25 * np.sin(0.45 * Y + 0.3 * e + 1.3 * nx)
        base = 3.0 * _ss((14.0 - Y) / 5.0) * _ss((-1.0 - X) / 3.0)
        D = _cut(D, (X - rx) * nx + (Z - rz) * nz - out + bow - base, 1.3)
    # 2b. behind, the surface for the calcaneus is "triangular": Fig. 275 draws its lateral border as a rim running
    # obliquely from 10 mm up at the lateral side to the top 9 mm further medially, and what lies lateral to and above
    # that rim is rough bone turning away forward (the dorsal surface, "directed upward and lateralward", comes down
    # to the rim there). The corner above the rim is taken off to a face that looks backward, upward and lateralward.
    a = np.array([-0.5, 10.2, 0.4]); d = np.array([8.6, 21.0, -1.2]) - a; d /= np.linalg.norm(d)
    n = np.array([-0.55, 0.45, -0.70]); n -= (n @ d) * d; n /= np.linalg.norm(n)
    bev = (X - a[0]) * n[0] + (Y - a[1]) * n[1] + (Z - a[2]) * n[2]
    D = _cut(D, bev - BEV_OUT + 0.6 * np.sin(0.45 * Y + 0.3 * X), 1.6)                    # (no face of a bone is a true plane)
    # (the surface itself is "concavo-convex": Fig. 275 shades it dark just inside the lateral rim, light along its
    # middle and grey toward the medial side: hollow from side to side next the rim, swelling toward the process)
    D = sdf.smax(D, -Ellipsoid((5.0, 12.5, -5.6), (5.5, 9.5, 5.6), rot((0, 0, 1), -32.0))(X, Y, Z), 2.5)
    # 2c. the sole side. "In front a deep groove, the peroneal sulcus, which runs obliquely forward and medialward ...
    # bounded behind by a prominent ridge ... The ridge ends laterally in an eminence, the tuberosity". Fig. 269 has
    # the groove leave the lateral border 19 mm from the back and reach the front medial corner, some 5 mm wide;
    # Fig. 275 looks into its beginning, the notch of the lateral border, in front of the tuberosity; Fig. 274 shows it
    # from in front as the dark hollow under the fifth metatarsal's facet, with the lip in front of it 8 mm above the
    # tuberosity's lowest point. The outlines leave the sole at the level of the ridge: the groove is cut in front of
    # it and the rough surface hollowed behind it, and the ridge is what stands between.
    # (its lateral opening low, under the lip: Fig. 275 draws the lateral border full down to 6 mm above the sole and
    # the notch below that, and Fig. 274 the lip's lowest point 8 mm up at the lateral end)
    D = sdf.smax(D, -_tube(X, Y, Z, [(-13.0, 5.4, 13.4), (-9.0, 4.8, 14.6), (-5.0, 3.9, 16.6), (-0.6, 3.0, 19.4), (3.6, 2.0, 22.6), (7.6, 0.8, 25.8), (10.6, 0.5, 28.4)],
                           [2.2, 2.2, 2.2, 2.4, 2.4, 1.9, 1.4]), 1.4)
    # (the sole side as Fig. 269 and 291 draw it. The two own plates look along the bone and leave the whole sole at
    # the level of its lowest parts, the ridge with the tuberosity and the process under the calcaneus: what lies in
    # front of the ridge and behind it is raised off that level. Fig. 269: the tuberosity and the ridge an oval swelling
    # 10 mm across and 15 long in the lateral half, centred 11 mm from the back; in front of it the tendon of the
    # peroneus longus, 4 mm wide, from the lateral border 15 mm from the back to the front medial corner. Fig. 291 (side
    # view): the front lip under the fifth metatarsal stands 3 mm above the tuberosity's lowest point, the rough
    # surface behind it 4 to 5 mm.)
    g = np.gradient(ndi.gaussian_filter(D, 1.0 / F.h), F.h); ny = g[1] / np.maximum(np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2), 1e-6); del g
    xs = F.ax[0][:, None]; zs = F.ax[2][None, :]
    p0 = np.array([-5.5, 15.0]); p1 = np.array([12.0, 31.0]); dl = (p1 - p0) / np.linalg.norm(p1 - p0)
    t = ((xs - p0[0]) * dl[0] + (zs - p0[1]) * dl[1]) / np.linalg.norm(p1 - p0)
    sg = -(xs - p0[0]) * dl[1] + (zs - p0[1]) * dl[0]                            # mm in front of the groove's line
    wob = 0.5 * np.sin(0.55 * xs + 0.3 * zs + 0.7) * np.cos(0.4 * zs - 0.25 * xs)  # (no surface of it is even)
    behind = (2.6 + wob) * _ss((-sg - 6.0) / 3.5)
    xr = (xs - 3.4) * 0.966 + (zs - 10.8) * 0.259; zr = -(xs - 3.4) * 0.259 + (zs - 10.8) * 0.966
    oval = np.sqrt((xr / 5.6) ** 2 + (zr / 7.6) ** 2)
    behind = behind * _ss((oval - 0.85) / 0.5)                                            # not on the tuberosity
    behind = behind * (1.0 - _ss((xs - 6.0) / 5.0) * _ss((15.0 - zs) / 6.0))            # nor on the process and the broad medial part (Fig. 275's lowest border)
    behind = behind - 0.8 * (1.0 - _ss((oval - 0.55) / 0.45))                             # the tuberosity a swelling
    lip = (1.4 + 0.3 * wob) * _ss((sg - 2.5) / 2.0) * (1.0 - 0.3 * _ss((t - 0.55) / 0.4))
    deep = (4.4 - 2.4 * _ss((t - 0.3) / 0.7)) * np.exp(-(sg / 2.3) ** 2) * _ss((t + 0.1) / 0.15) * (1.0 - _ss((t - 1.0) / 0.12))
    raise_ = ndi.gaussian_filter((behind * (1.0 - _ss((sg + 2.5) / 2.0)) + lip + deep).astype(np.float32), 0.8 / F.h)
    # (moved up along the sole's own normal. The weight turns from 0 to 1 within a millimetre where the sole meets the
    # sides, and a 2.6 mm offset stepping so fast is stamped into the grid as fine teeth along that edge: the offset is
    # eased in all three directions before it is added)
    # (and only low down: where the outlines already leave the sole high, under the lip at the lateral end, Fig. 274's
    # outline has cut the groove's opening, and raising it again would cut into the lip)
    D = D + ndi.gaussian_filter((raise_[:, None, :] * _ss((-ny - 0.25) / 0.45) * _ss((9.0 - Y) / 3.0)).astype(np.float32), 0.9 / F.h)
    # (the dorsal surface is no plane: Fig. 291 draws it convex from behind forward, its lateral front corner some
    # 2 mm and its hind border under 1 mm below the crown; Fig. 274's highest point, the top of the fourth metatarsal's
    # facet, keeps the medial front corner nearly as high as the crown)
    inside = (D < 0).any(1); zi = np.where(inside, zs + 0 * xs, np.nan)
    zmin = np.min(np.where(inside, zs + 0 * xs, 99.0), 1)[:, None]; zmax = np.max(np.where(inside, zs + 0 * xs, -99.0), 1)[:, None]
    zm = 0.5 * (zmin + zmax); hl = np.maximum(0.5 * (zmax - zmin), 4.0); q = np.clip((zs - zm) / hl, -1.2, 1.2)
    drop = (1.9 - (0.5 + 0.5 * _ss((xs - 2.0) / 5.0)) * (q > 0)) * q ** 2 + 0.5 * wob * (1.0 - q ** 2)        # a crown, highest mid-length
    # (and the top border wanders, as the outlines of Fig. 274 and 275 do: low swellings and dips 6 to 10 mm long,
    # up to a millimetre or so, no stretch of it straight)
    wander = (0.15 + 0.8 * np.sin(0.75 * zs + 0.35 * xs + 0.9) + 0.55 * np.sin(1.15 * zs - 0.5 * xs + 2.3) + 0.35 * np.sin(1.9 * zs + 0.8 * xs)) * (1.0 - 0.4 * q ** 2)
    off = ndi.gaussian_filter(drop.astype(np.float32), 1.0 / F.h)[:, None, :] * _ss((ny + 0.15) / 0.6) \
        + ndi.gaussian_filter(wander.astype(np.float32), 1.0 / F.h)[:, None, :] * _ss((ny - 0.35) / 0.4)     # (on the top only, not down the sides)
    D = (D + ndi.gaussian_filter(off.astype(np.float32), 0.9 / F.h)).astype(np.float32); del off, wander
    del ny, raise_, drop
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D, o4, o5
    if upto == "forms":
        return F
    # 3. the joint surfaces and the marks the plates draw
    _facets(F, CUBOID, P, tr, CUB_FACETS)
    # (the ridge between the two metatarsal facets stands a little above both)
    # (laid only where a plate faces the surface: carried on to faces it sees edge-on, a mark is drawn out into
    # streaks and fine ripples, as it was under the sulcus's lip)
    _lay(F, CUBOID, P, {f: _marks_map(_pits(m, V[f]["s"] * P[f][3]), tr[f + "_sdf"].shape, V[f]["s"] * P[f][3]) for f, m in CUB_MARKS.items()}, face=0.1)
    # (the calcaneal surface's lower border, which Fig. 275 sees at a slant, a definite edge as the rest of its rim)
    f = "Gray275"; _lay(F, [V[f]], P, {f: _marks_map([("line", [(144, 98), (155, 111), (175, 127), (200, 139), (225, 147), (250, 151), (267, 147), (271, 137)], 1.2, 0.8)],
                                                  tr[f + "_sdf"].shape, V[f]["s"] * P[f][3])}, face=-0.1)
    # 4. the plates' shading as relief, and their fine drawing
    if relief:
        _emboss(F, tr, CUBOID, P, relief, log)
    if ink:
        _lay(F, CUBOID, P, {f: tr[f + "_ink"].astype(np.float32) * (ink / 50.0) for f in V}, face=0.35, shared=True, rough=True)
    log("cuboid: built from Fig. 274 and 275, its plan from Fig. 268")
    return _one_piece(F)


# The navicular. Its body is held by three outlines (Fig. 277, the postero-medial view, is fitted to it afterwards and
# gives the surface for the talus, its rim and the rough bone round it; its pose is found by the outline alone, which
# leaves the view's nod and turn free along a valley: they are set at 5 degrees from above and 10 medial, nearly
# straight into the talar surface as the plate draws it, and the roll, scale and shift fitted): its plan as Fig. 268 draws its dorsal
# surface (0.208 mm a pixel, x = (u - 377) 0.208, z = (v - 440) 0.208), its side as Fig. 290 draws it between the
# talus's head and the first cuneiform (0.49 mm a pixel, the scale of Fig. 291 at which the calcaneus is 79 mm:
# z = (u - 210) 0.49, y = (80 - v) 0.49), and Fig. 276 from in front, whose pose is fitted to the first two.
NAV_PLAN = [((u - 377.0) * 0.208, (v - 440.0) * 0.208) for u, v in [
    (310, 398), (330, 402), (350, 406), (370, 408), (390, 405), (410, 397), (425, 391),        # behind, the talus's head
    (435, 400), (443, 415), (447, 432), (445, 450), (437, 465), (425, 477),                     # medial, the tuberosity
    (410, 485), (398, 488), (385, 492), (372, 494), (360, 495),                                 # in front: the first cuneiform's, to the notch where
    (352, 487), (340, 480), (320, 475), (305, 472), (292, 469),                                 # its joint with the second meets the border; the second's
    (281, 457), (270, 441),                                                                     # the third's, out to the front lateral corner
    (276, 428), (285, 414), (293, 403), (300, 397)]]                                            # the lateral border, oblique, along the cuboid
# (the lateral border as Fig. 268 draws it: not a short upright end at x -15, as first read, but an oblique line along
# the cuboid's medial border from (298, 396) to the front lateral corner at (270, 441), x -22.3, where the joints with the
# third cuneiform and the cuboid meet; and in front the two cuneiform joints meet the border at u 358 (x -4.0) and 290 (x -18.1))
NAV_SIDE = [((u - 210.0) * 0.49, (80.0 - v) * 0.49) for u, v in [
    (204, 44), (202, 60), (200, 77), (195, 85), (190, 90), (187, 101), (188, 110), (193, 116),   # behind, up to down
    (200, 118), (207, 116), (211, 110), (221, 94), (229, 77), (231, 64), (226, 47), (218, 43), (210, 42)]]   # in front
# Fig. 276, in its own pixels: the three facets for the cuneiforms (medial to lateral) and the occasional one for the cuboid
NAV_FACETS = {"Gray276": [
    [(104, 108), (140, 95), (172, 90), (179, 94), (181, 123), (180, 163), (167, 177), (135, 179), (105, 177), (92, 167), (89, 143), (93, 119)],
    [(186, 86), (200, 81), (220, 80), (240, 82), (253, 88), (259, 97), (258, 106), (245, 115), (231, 125), (222, 143), (217, 163), (211, 169),
     (195, 167), (187, 160), (185, 125)],
    [(267, 113), (279, 123), (282, 139), (275, 163), (255, 183), (235, 191), (223, 183), (219, 163), (223, 143), (235, 125), (251, 116)],
    [(222, 205), (230, 196), (248, 188), (254, 191), (242, 204), (228, 213)]]}
# Fig. 277 (the postero-medial view), in its own pixels (0.07 mm): the border of the surface for the talus, the white
# line just inside the dark rim; and the rough bone it draws dark and pitted round it, each patch with how many pits
# and swellings: the lateral end (left), the tuberosity (lower right) and the band below the surface.
NAV_TALAR = [(332, 72), (318, 105), (312, 150), (310, 200), (312, 250), (318, 300), (330, 345), (345, 375), (365, 395), (400, 401),
             (480, 401), (560, 398), (615, 386), (640, 362), (648, 330), (641, 292), (622, 243), (600, 200), (574, 158), (545, 115),
             (512, 82), (480, 63), (450, 57), (400, 59), (360, 64)]
NAV_ROUGH7 = [
    ([(222, 180), (250, 120), (296, 72), (318, 85), (302, 200), (302, 330), (330, 385), (300, 380), (255, 330), (226, 260)], 45, 10),
    ([(565, 412), (610, 390), (652, 345), (690, 330), (712, 380), (712, 440), (690, 472), (640, 476), (590, 462)], 40, 9),
    ([(345, 410), (480, 412), (600, 404), (560, 440), (470, 452), (400, 455), (345, 432)], 20, 5)]
# The surface for the talus is cut by the talus's own head (talus.py, accepted): an ellipsoid fitted to its articular
# surface (the front 9 mm that faces forward: 0.4 mm rms), its oval standing 33 degrees from horizontal, lateral end up,
# turned 5 degrees about the vertical as Fig. 268 lays the talus, and seated where Fig. 277's border of the surface (the
# ring NAV_TALAR, carried on to this bone in that plate's pose) lies on the head (1.1 mm rms). The hollow is that head
# grown by the joint's gap. (So seated, the talus lies 11 mm lower than Fig. 290's outline of its body puts it, which
# the outline of this bone and its talar ring in Fig. 277 cannot give way to: an open conflict between the plates and
# the talus's head height.)
# T-foot-seat, 25 Nov: the talus moved to its place in foot_frame's assembly (talus.AT_*: 15 degrees head-up, 5.6 mm
# lateral, 4.8 mm back), and the hollow follows it. It is now cut by the talus itself there (NAV_HEAD_FROM, its field
# eased over NAV_HEAD_EASE): the ellipsoid above, carried to the new place, stood 1 to 1.5 mm off the head's flatter
# front in the middle of the face (the hollow's floor 2.5 to 3 mm from the head there). The ellipsoid is kept, refitted
# to the head at its place where it faces this bone inside Fig. 277's border (0.37 mm rms; the old one carried there
# 0.54), for NAV_HEAD_FROM = "ellipsoid"; old values: centre (-1.64, 4.04, -24.42), axes ((0.837, 0.548, 0.004),
# (-0.543, 0.83, -0.128), (-0.073, 0.105, 0.992)), semi-axes (21.6, 16.58, 25.0).
NAV_HEAD_C = (-18.64, 13.484, -23.044)   # mm, this frame
NAV_HEAD_AX = [[-0.3432, 0.44, -0.8298], [-0.0461, 0.8745, 0.4828], [0.9381, 0.204, -0.2799]]   # its axes (columns) in this frame
NAV_HEAD_R = (17.45, 16.48, 32.01)       # mm
NAV_GAP = 1.3                            # mm
NAV_HEAD_FROM = "talus"                  # the hollow is cut by the talus itself at its place in the foot (talus.AT_*)
NAV_HEAD_EASE = 1.2                      # mm: the talus's field eased over this much first (its own small unevenness not printed in the hollow)
# The hind faces of the three cuneiforms as cuneiforms.py poses them (its PLACE, the second and third at Fig. 268's
# joint lines, read 25 Nov), each bone as its own plates build it before it is cut to its neighbours: a smooth surface
# fitted to the face (0.46, 0.42 and 0.61 mm rms), in this frame: w = q0 + q1 a + q2 b + q3 a^2 + q4 ab + q5 b^2 along
# n (toward this bone) at (a, b) along e1, e2 from c, over the face's extent a, b. Refit if those bones move. `give`:
# mm this bone's facet stands into that face. So built, the three overlap Fig. 268's navicular by up to 1.6 mm (the
# third at its lateral corner): held a joint's gap off them, this bone lost that corner (x -18.9 for -22.3) and its plan
# went to 1.1 mm. So the facets keep the plan and the cuneiforms, assembled after this bone, are cut to it (their own
# plates' outlines move by 0.05 mm at most); the gaps are then cuneiforms.GAP's, 0.7 to 1.0 mm median (an open conflict).
NAV_CUNE_FACES = {
    "first": dict(c=(2.39, -0.69, 9.72), n=(0.051, 0.285, -0.957), e1=(0.999, 0.0, 0.053), e2=(0.015, -0.959, -0.285),
                  q=(0.5457, 0.3583, -0.1547, -0.1042, 0.0186, -0.0003), a=(-5.5, 5.1), b=(-9.2, 10.5), give=-3.0),
    "second": dict(c=(-10.76, 7.9, 8.69), n=(0.286, -0.055, -0.957), e1=(0.958, 0.0, 0.287), e2=(-0.016, -0.998, 0.053),
                   q=(0.769, -0.1089, -0.0503, -0.0199, 0.0161, -0.0231), a=(-8.8, 7.2), b=(-7.9, 10.1), give=-2.0),
    "third": dict(c=(-19.79, 3.85, 2.69), n=(0.802, 0.066, -0.593), e1=(0.594, 0.0, 0.804), e2=(0.053, -0.998, -0.039),
                  q=(1.7242, -0.2219, -0.0323, -0.2068, -0.0453, -0.0269), a=(-5.0, 4.4), b=(-8.8, 11.7), give=-3.5)}
NAV_CUNE_GAP = 1.2       # mm: the joint's gap to them (the blend below adds to it)
NAV_FACET_R = (15.0, 1e9)   # mm: each facet at least this gently convex across (along e1) and up and down (e2) (the fitted faces are a little concave: so carried, the third stood as a trough)
NAV_FACET_MORE = 2.0     # mm: the face held so far beyond the extent fitted (the cuneiform's face is rounded off at its edges)
NAV_FACET_FALL = 0.25    # 1/mm: beyond a face's extent its hold lets go as the square of the distance (a window there printed its edge as a straight crease)
NAV_CUNE_BLEND = 0.8     # mm over which the facets meet each other and the rest of the bone: the two ridges low and rounded
NAV_CLEAR = 0.8          # mm: the least gap to them and to the talus's head once the surface's layers are on
NAV_CLEAR_BLEND = 1.5    # mm (taken back over less, the raised rim and ridges were cut off along a straight crease)
NAV_PLAN_EASE = 1.2      # mm
NAV_PLAN_OUT = 0.9       # mm
NAV_PLAN_BACK = (0.5, -5.0, 7.0)   # mm the plan's back border (the joint line with the talus) is taken in, from x to x (eased over
                                   # 2 mm): the head seated 4 mm further forward used to take that off; without it the plan went to 0.74 mm
NAV_SIDE_GIVE = 4.0      # mm
NAV_SIDE_FRONT = 1.5     # mm
NAV_TUB = (10.5, -13.5, -4.0)            # the tuberosity's centre: Fig. 268's medial bulge (x 14.6 at z -1.7), Fig. 290's lowest point behind
TALAR_OUT = 5.0     # mm: how far the head is pushed back well outside the talar surface's border (no hollow there)
TALAR_EASE = 2.0    # mm over which the hollow rises into its rim
TALAR_FREE = 6.0    # mm outside the border within which the hollow is the head's own shape: the head is still in the bone there, at the lateral end most, and a hollow stopped short of it was cut again at the end into a trench along the lateral rim (a dark slit)
TALAR_LIP = 0.45    # mm: the rim at the border
TALAR_RIM = 1.0     # mm: the hollow is gone this far below the dorsal surface's top
TALAR_RIM_EASE = 1.5   # mm below that over which it rises into the rim (4: with the head at its place, 2 mm higher, the
                       # upper half of the hollow was left uncut until the last clearing, and the rough layers' pits stayed in it)
TALAR_FLARE = 0.0   # mm: the hollow's mouth opened by this much 3 mm outside the border (2.5 cut a trench along the lateral
                    # end, where the head at its place runs past the border: a dark slit)
TALAR_CLEAR_REACH = 40.0  # mm outside the border within which the bone is kept clear of the head at the end: all of it (the
                          # head at its place reaches 2 to 4 mm past the border at the lateral end; kept clear only within
                          # 5 mm, the bone there ran 0.6 mm into it and the cut's edge stood as a dark slit)
TALAR_PIT_HOLD = 1.0   # how the layers' pits fade near the head: hw ** this (0 kept them all)
TALAR_GAPFADE = 0.3   # mm beyond the joint's least gap from where the layers fade in
TALAR_CLEAR_BLEND = 1.5   # mm: what the layers raised into the head's gap is taken back over this much (over half a millimetre the lip was cut into a sheer wall, a dark slit along the lateral rim)
TALAR_TUB = [(400, 401), (480, 401), (560, 398), (615, 386), (640, 362), (648, 330), (641, 292)]   # the ring's stretch along the tuberosity, Fig. 277
NAV_FRONT_R = 1.3   # mm: the front border's rounding
NAV_LOW_R = 1.8     # mm more along its lower part
TUB_BLEND = 3.5    # mm
ROUGH3 = 0.2      # mm
NAV_LOW_DAMP = 0.65   # how much lower the rough rim is along the front surface's lower border
NAV_RIM = 0.22      # mm: the rough margin round the facets, thin and low
NAV_OCC = 0.15      # mm: the occasional facet for the cuboid, a low smooth swelling
NAV_FACE = 0.5      # Fig. 276's layers only where the surface faces it so squarely (n . eye): taken on at a slant they ran out into streaks along its line of sight
NAV_WANDER = 0.3    # mm
NAV_SOFT = 0.9      # mm
GROOVE_SINK = 0.6   # mm: the groove's line below the plantar surface
NAV_MARKS = {"Gray276": [
    # the rough plantar part between the 1st and 3rd facets, under the 2nd, and the pits the plate draws in it
    ("area", [(160, 182), (185, 172), (212, 172), (222, 190), (215, 212), (190, 218), (165, 205)], -0.5, 1.2),
    ("dot", (163, 196), 0.5, -0.6), ("dot", (176, 205), 0.4, -0.5), ("dot", (199, 190), 0.35, -0.4),
    # the two ridges between the three facets, low and rounded: each facet's field falls off into them over about a
    # millimetre (a raised line along the dorsal rim, and the third facet set as a dish, stood as a ruled edge and a trough)
    ("line", [(184, 84), (184, 110), (184, 140), (183, 166)], 1.6, 0.22),
    ("line", [(259, 102), (246, 115), (232, 126), (222, 145), (217, 168)], 1.6, 0.22)]}


def _slab(poly, a, z, across=0, step=0.2, ease=2.5, give=None, give_front=0.0):
    """How far a point lies behind a traced outline's back border or in front of its front border (mm, below 0
    between), the borders read along z at each value of the other coordinate (`across` says which of the outline's two
    is that one: 0 for (x, z) outlines, 1 for (z, y)); beyond the outline's ends its end values hold. `ease`: mm over
    which the borders are eased along the other coordinate; `give`: mm the back border is let out at each value of it
    (where the plate's border is a joint line that a neighbour hides, not the bone's edge); `give_front`: mm the front
    border is let out."""
    P = sdf.spline(np.asarray(poly, float), 0.4, closed=True)
    if across == 1:
        P = P[:, ::-1]
    # (each border read off the outline filled on a fine raster, row by row: read from the outline's points that fall
    # within a window, it moved in steps as points came into the window and printed them on the dorsal surface as bands)
    from PIL import Image, ImageDraw
    fine = 0.02; lo, hi = P.min(0), P.max(0); W, H = (np.ceil((hi - lo) / fine).astype(int) + 2)
    im = Image.new("L", (int(H), int(W)), 0); ImageDraw.Draw(im).polygon([((b - lo[1]) / fine, (a_ - lo[0]) / fine) for a_, b in P], fill=255)
    m = np.asarray(im) > 0; zs = lo[1] + np.arange(m.shape[1]) * fine; rows = lo[0] + np.arange(m.shape[0]) * fine; ok = m.any(1)
    zbr = np.where(ok, zs[np.argmax(m, 1)], np.nan); zfr = np.where(ok, zs[m.shape[1] - 1 - np.argmax(m[:, ::-1], 1)], np.nan)
    grid = np.arange(lo[0], hi[0] + step, step)
    zb = np.interp(grid, rows[ok], zbr[ok]); zf = np.interp(grid, rows[ok], zfr[ok])
    zb = ndi.gaussian_filter1d(zb, ease / step, mode="nearest"); zf = ndi.gaussian_filter1d(zf, ease / step, mode="nearest")
    if give is not None:
        zb = zb - give(grid)
    zf = zf + give_front
    b = np.interp(a, grid, zb); f = np.interp(a, grid, zf)
    return np.maximum(b - z, z - f).astype(np.float32)


def navicular(h=0.3, log=print, relief=1.0, upto="all", poses=None, ink=INK):
    """upto="body": inside the plan (Fig. 268) and the side (Fig. 290), what Fig. 276's pose is fitted on; "hull":
    within Fig. 276's outline as well; "forms": with the forms cut by hand."""
    F = Field((-27.0, -24.0, -16.0), (23.0, 24.0, 16.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    V = {v["fig"]: v for v in NAVICULAR if v["fig"] == "Gray276"}
    tr = traces("navicular")
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}
    plan = _plan(NAV_PLAN, X, Z, ease=0.6); side = _plan(NAV_SIDE, Z, Y, ease=0.8)
    D = _round_meet(plan, side, 3.0); del plan, side
    if upto == "body":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    # Fig. 276 rules the bone's section across its line of sight; the plan and the side only say how far it reaches
    # back and forward at each x and at each height (their front and back borders), so the solid fills Fig. 276's
    # outline and lies within the other two where the pose is right.
    # (Fig. 290's back border, above the bone's middle, is the joint line where the talus's head hides the bone: what of
    # the lateral end lies further back there is out of that plate's sight, and Fig. 268's plan and the head rule it.
    # Its front border is the joint with the first cuneiform, which hides what of the bone lies lateral of it and further
    # forward, the notch where the first two cuneiforms meet: let out a little, so Fig. 268's front rules there.
    # The plan's borders are eased over a millimetre only, so its notch where the first two cuneiforms meet stays; and
    # let out by what the meeting of the solids and the easing below take off a convex border, so the plan keeps its line)
    D = sdf.smax(_slab(NAV_PLAN, X, Z, ease=NAV_PLAN_EASE, give=lambda x: -NAV_PLAN_BACK[0] * _ss((x - NAV_PLAN_BACK[1] + 2.0) / 2.0) * _ss((NAV_PLAN_BACK[2] + 2.0 - x) / 2.0)) - NAV_PLAN_OUT, _slab(NAV_SIDE, Y, Z, across=1, give=lambda y: NAV_SIDE_GIVE * _ss((y + 2.0) / 4.0), give_front=NAV_SIDE_FRONT), 2.5)
    fig = "Gray276"; px = V[fig]["s"] * P[fig][3]; B6 = pm.basis(V[fig], P[fig][:3])
    d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
    o6 = _read(ndi.gaussian_filter(d, 1.3 / px), *_pixels(V[fig], P[fig], X, Y, Z))
    if upto != "hull":
        # (no face of it runs straight back from Fig. 276's outline: the dorsal and plantar surfaces are convex from
        # the talus forward to the cuneiforms, and the outline's walls fall in toward both)
        o6 = o6 + 0.028 * (Z - 0.5) ** 2 * (1.0 + 0.15 * np.sin(0.35 * X + 0.25 * Y))
        # (nor is any of them the outline drawn straight back: each small turn of Fig. 276's outline, so carried, ran
        # across the dorsal surface as a straight crease. Away from the bone's widest section they wander a little)
        o6 = o6 + NAV_WANDER * (np.sin(0.55 * Z + 0.4 * X - 0.3 * Y + 0.6) + 0.6 * np.sin(0.9 * Z - 0.5 * X + 0.2 * Y + 2.1)) * _ss((np.abs(Z - 0.5) - 1.0) / 4.0)
    # (the front border rounded, as Fig. 276 draws it; more broadly along its lower part, where the first cuneiform's
    # facet comes down to it: met there at a sharp corner, the facet stood from below as a hard-edged black field)
    up6 = (X * B6[1][0] + Y * B6[1][1] + Z * B6[1][2]).astype(np.float32)
    D = _round_meet(D, o6, NAV_FRONT_R + 1.0 * _ss((1.0 - Z) / 5.0) + NAV_LOW_R * _ss((-up6 - 2.0) / 6.0)); del o6, up6
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    B = pm.basis(V[fig], P[fig][:3]); ax_ = B[0]                    # the bone's long axis (Fig. 276's left to right: medial to lateral)
    f7 = "Gray277"; V7 = [v for v in NAVICULAR if v["fig"] == f7][0]; P7 = np.asarray((poses or {}).get(f7, tr[f7 + "_pose"]), float)
    px7 = V7["s"] * P7[3]; sh7 = tr[f7 + "_sdf"].shape
    # 2a. behind, the surface for the talus: "oval, concave, broader laterally than medially". Fig. 277 looks into
    # it: its border is traced there (NAV_TALAR). The hollow is the talus's head grown by the joint's gap (NAV_HEAD_*),
    # within the border and for TALAR_FREE beyond it, where the head curves away from the bone; further out none. The
    # rim the plate draws round it is laid below (the lip on the border).
    head = _head(X, Y, Z, NAV_GAP)
    fm = _mask([NAV_TALAR], sh7, 0.5) > 0.5
    fsd = ndi.gaussian_filter((ndi.distance_transform_edt(fm) - ndi.distance_transform_edt(~fm)).astype(np.float32), 0.6 / px7) * px7   # mm inside the border
    fin = _read(fsd, *_pixels(V7, P7, X, Y, Z))
    # (its mouth opened a little outside the border, so the hollow rises into its rim as a rounded lip: where the bone
    # wraps round the head's lateral end, cut to the head alone it was a narrow slot, its wall a dark slit)
    # (and it rises into a rim below the dorsal surface's back border, gradually: carried up to that border, the
    # hollow cut through it and was seen from above; held off it over a short way only, the rim stood over the hollow
    # as a hooked flap)
    ins = D < 0; top = np.where(ins.any(1), F.ax[1][F.n[1] - 1 - np.argmax(ins[:, ::-1, :], 1)], -50.0).astype(np.float32); del ins
    top = ndi.gaussian_filter(top, 1.5 / F.h)[:, None, :]
    rim = _ss((Y - top + TALAR_RIM + TALAR_RIM_EASE) / TALAR_RIM_EASE); del top
    head = head - TALAR_FLARE * _ss(-fin / 3.0) + TALAR_OUT * np.maximum(_ss((-fin - TALAR_FREE) / TALAR_EASE), rim); del rim
    D = sdf.smax(D, -head, 1.2); del head
    # 2b. the tuberosity, at the medial end, rounded, and reaching down and back past the body (Fig. 268 has it bulge
    # medially behind the first cuneiform, Fig. 290 low at the back of the bone, Fig. 276 as the thick rounded rim of
    # its left end, Fig. 277 as the low hind end of the bone's right side)
    t = np.asarray(NAV_TUB)
    D = sdf.smin(D, Ellipsoid(tuple(t), (4.0, 4.8, 4.6), rot((0, 0, 1), -30.0))(X, Y, Z), TUB_BLEND)
    # (the plantar surface has a shallow groove lateral to the tuberosity, running from behind forward under the
    # tendon's slip: cut along the bone's lowest surface there)
    g0 = t + np.array([-6.5, 0.0, 0.0])
    i0 = int(round((g0[0] - F.lo[0]) / F.h)); col = D[i0, :, :]; low = np.where((col < 0).any(0), F.ax[1][np.argmax(col < 0, 0)], np.nan)
    path = []
    for zz in (-5.0, -2.5, 0.0, 2.5):
        k = int(round((zz - F.lo[2]) / F.h)); yb = low[k] if np.isfinite(low[k]) else g0[1]
        path.append((g0[0] + 0.12 * zz, yb - GROOVE_SINK + 0.15 * np.sin(zz), zz))
    D = sdf.smax(D, -_tube(X, Y, Z, path, [0.5, 1.4, 1.4, 0.5]), 1.0)
    # (each part above is a solid ruled along one line of sight (the plan's, the side's, Fig. 276's) and where two
    # meet they leave a straight crease, which the dorsal view showed as rectangular steps: the whole is eased over a
    # millimetre)
    D = ndi.gaussian_filter(D, NAV_SOFT / F.h)
    # (and kept a joint's gap off the three cuneiforms as cuneiforms.py poses them: their hind faces stand a little
    # inside Fig. 268's joint lines, the third's lower part further, where its postero-lateral angle runs back)
    D = _clear(D, X, Y, Z, NAV_CUNE_GAP, blend=NAV_CUNE_BLEND)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D
    if upto == "forms":
        return F
    D_forms = F.D.copy()
    # 3. the joint surfaces in front ("subdivided by two ridges into three facets"), smooth; the two ridges between
    # the facets low and rounded; the plate's marks; and the "occasional facet for cuboid" below the third.
    # Every layer Fig. 276 gives is eased out to nothing over the outline's last millimetre or so (q6), whatever way the
    # surface faces there: a layer that ran to the outline and was cut off only where the surface turned from the plate
    # stopped dead along the front border, as a block edge seen from above, a torn black margin from below and a seam
    # from the sides.
    sh = tr[fig + "_sdf"].shape; s6 = tr[fig + "_sdf"].astype(np.float32); q6 = _ss((-s6 - 0.15) / 1.0)
    # (the facets are the joint's own convex fields, not set into the rim: a recess there stood as a square step)
    # (and the occasional facet for the cuboid, below the third: the bone comes within 2 mm of the cuboid there, so it
    # is given, a low smooth field)
    fm = np.clip(_mask(NAV_FACETS[fig][:4], sh, 0.8 / px), 0.0, 1.0)
    smooth = _shown(F, V[fig], P[fig], fm)
    _lay(F, [V[fig]], P, {fig: NAV_OCC * _mask(NAV_FACETS[fig][3:4], sh, 1.2 / px) * q6}, face=NAV_FACE)
    # (Fig. 276 sets the facets inside a broad rough rim, widest above and at the lower middle: what of the outline the
    # facets leave is raised a little and roughened, with pits strewn over it)
    inside = (s6 < 0).astype(np.float32)
    fac = ndi.binary_dilation(_mask(NAV_FACETS[fig][:4], sh, 0.5) > 0.5, iterations=2).astype(np.float32)
    # (its inner edge eased over a millimetre: a sheer step there stood, where the first cuneiform's facet comes down to
    # the plantar border, as a hard-edged black field from below)
    rim = ndi.gaussian_filter(np.clip(inside - fac, 0.0, 1.0), 1.0 / px)
    rng = np.random.default_rng(276)
    bumpy = ndi.gaussian_filter(rng.normal(size=sh).astype(np.float32), 0.7 / px); bumpy /= bumpy.std()
    coarse = ndi.gaussian_filter(rng.normal(size=sh).astype(np.float32), 2.5 / px); coarse /= coarse.std()
    rmap = rim * NAV_RIM * (1.0 + 0.6 * coarse + 0.5 * bumpy)        # (its roughness uneven: here nearly smooth, there knobbed)
    ys, xs_ = np.nonzero((rim > 0.6) & (q6 > 0.7)); pick = rng.choice(len(ys), 28, replace=False)
    rmap += _marks_map(_pits([("dot", (float(xs_[i]), float(ys[i])), float(rng.uniform(0.2, 0.45)), float(rng.uniform(-0.6, -0.3))) for i in pick], px, 277), sh, px)
    rmap += _marks_map(_pits(NAV_MARKS[fig], px), sh, px)
    # (along the lower border, where the front surface comes down to the plantar border at a slant, the rim's roughness
    # is eased out further from the outline, and lower: the front surface is seen from below in profile there, and
    # its rough rim at full height stood as a torn margin along that border)
    low = _ss((np.arange(sh[0], dtype=np.float32)[:, None] - 150.0) / 30.0)
    _lay(F, [V[fig]], P, {fig: rmap * (1.0 - NAV_LOW_DAMP * low) * (q6 * (1.0 - low) + _ss((-s6 - 0.3) / 2.2) * low)}, face=NAV_FACE)
    # 4. behind, Fig. 277: the talar surface's border a raised lip all round, the hollow smooth; the rough bone round it,
    # the tuberosity and the lateral end pitted and uneven as the plate draws them
    sm7 = _shown(F, V7, P7, _mask([NAV_TALAR], sh7, 0.8 / px7))
    s7 = tr[f7 + "_sdf"].astype(np.float32); q7 = _ss((-s7 - 0.15) / 1.0)
    rng = np.random.default_rng(2770)
    # (the lip a continuous rounded rim, broader, higher and rougher along the tuberosity)
    lip = _marks_map([("line", NAV_TALAR + NAV_TALAR[:1], 1.6, TALAR_LIP)], sh7, px7)
    tl = _marks_map([("line", TALAR_TUB, 2.6, 1.0)], sh7, px7); lb = ndi.gaussian_filter(rng.normal(size=sh7).astype(np.float32), 0.5 / px7); lb /= lb.std()
    lip = lip + tl * (0.3 + 0.12 * lb); del tl, lb
    band = np.clip((s7 < 0).astype(np.float32) - ndi.binary_dilation(_mask([NAV_TALAR], sh7, 0.5) > 0.5, iterations=8), 0.0, 1.0)
    bumpy7 = ndi.gaussian_filter(rng.normal(size=sh7).astype(np.float32), 0.7 / px7); bumpy7 /= bumpy7.std()
    rough7 = ndi.gaussian_filter(band, 0.5 / px7) * (0.25 + 0.3 * bumpy7)
    rough7 += _marks_map(_pits(_rough7(NAV_ROUGH7, rng), px7, 2771), sh7, px7)
    _lay(F, [V7], {f7: P7}, {f7: lip * q7}, face=0.5)
    _lay(F, [V7], {f7: P7}, {f7: rough7 * q7}, face=0.7)
    F.smooth = np.clip(np.maximum(smooth, sm7), 0.0, 1.0).astype(np.float32); del sm7, smooth
    # (the bone's rough surfaces, "rough" in Gray's words for the dorsal, the plantar and the lateral surface, and the
    # broad rim round the facets which Fig. 276 draws hatched and pitted: laid in the solid itself, the same from
    # every side, not from one plate's tracing, which carried on to faces the plate sees at a slant runs out into
    # streaks along its line of sight. Low uneven swellings, and small pits of every shape where a finer chance runs high)
    rng = np.random.default_rng(278); sh3 = F.D.shape
    n1 = ndi.gaussian_filter(rng.normal(size=sh3).astype(np.float32), 0.5 / F.h); n1 /= n1.std()
    n2 = ndi.gaussian_filter(rng.normal(size=sh3).astype(np.float32), 1.6 / F.h); n2 /= n2.std()
    n3 = ndi.gaussian_filter(rng.normal(size=sh3).astype(np.float32), 0.3 / F.h); n3 /= n3.std()
    n4 = ndi.gaussian_filter(rng.normal(size=sh3).astype(np.float32), 3.5 / F.h); n4 /= n4.std()
    var = 0.35 + 1.3 * _ss((n4 + 0.6) / 1.6); del n4      # (not evenly bumpy: patches nearly smooth, others coarse)
    F.D += ROUGH3 * var * (0.35 * n1 + 0.5 * n2 + 1.4 * _ss((n3 - 2.3 + 0.5 * (var - 1.0)) / 0.6)) * (1.0 - F.smooth); del n1, n2, n3, var      # (D grows outward: + is a pit)
    if relief:
        # (not on the facets: the plate's stipple and shading there, embossed, stood as stair-stepped contour lines)
        D0 = F.D.copy(); _emboss(F, tr, [V[fig]], P, relief, log, face=0.6)
        F.D = (D0 + (F.D - D0) * _shown(F, V[fig], P[fig], q6 * (1.0 - fm), deep=3.0)).astype(np.float32); del D0
    if ink:
        _lay(F, [V[fig]], P, {fig: tr[fig + "_ink"].astype(np.float32) * (ink / 50.0) * q6 * (1.0 - fm)}, face=0.55, shared=True, rough=True)
    # (nothing the layers raise is let into the talus's head's gap: faded out as the surface comes near the head, so
    # the cut below has nothing left to take there; cut at the end, the lip and rough bone raised there stood as a
    # sheer wall, a dark slit along the lateral rim. Nor what they sink: the hollow reaches past Fig. 277's border
    # where the head stands higher than that plate's ring, and the rough bone's pits laid there stayed in the hollow
    # as marks, deeper than the cut below)
    dl = F.D - D_forms; wr = _ss((fin + TALAR_CLEAR_REACH) / 3.0); hw = _ss((_head(X, Y, Z, 0.0) - NAV_CLEAR - TALAR_GAPFADE) / 1.2) * wr + (1.0 - wr); del wr
    F.D = (D_forms + np.maximum(dl, 0.0) * hw ** TALAR_PIT_HOLD + np.minimum(dl, 0.0) * hw).astype(np.float32); del dl, hw, D_forms
    # (what the layers raised into a joint's gap is taken back: no part of the bone runs into the talus's head or a
    # cuneiform; met over half a millimetre, so no edge is left where it was)
    F.D = _clear(F.D, X, Y, Z, NAV_CLEAR, head=_ss((fin + TALAR_CLEAR_REACH) / 3.0), blend=NAV_CLEAR_BLEND)
    log("navicular: built from Fig. 276 and 277, its plan from Fig. 268 and its side from Fig. 290")
    return _one_piece(F)


_TALUS = {}


def _talus_field():
    """The talus as talus.py builds it (no plate ink, no relief), eased over NAV_HEAD_EASE mm: (field, lo, h)."""
    if "F" not in _TALUS:
        import talus
        T = talus.talus(0.4, log=lambda *a: None, relief=0.0, ink=0.0)
        _TALUS["F"] = (ndi.gaussian_filter(np.asarray(T.D, np.float32), NAV_HEAD_EASE / T.h), np.asarray(T.lo, float), float(T.h))
    return _TALUS["F"]


def _head(X, Y, Z, grow):
    """The talus's head grown by `grow` mm, as a field: below 0 inside. NAV_HEAD_FROM "talus": the talus itself at its
    place in the foot (talus.at()); "ellipsoid": the ellipsoid NAV_HEAD_*."""
    if NAV_HEAD_FROM == "talus":
        import talus
        D, lo, h = _talus_field(); R, t = talus.at()
        sh = np.broadcast(X, Y, Z).shape; out = np.empty(sh, np.float32)
        Xb, Yb, Zb = (np.broadcast_to(a, sh) for a in (X, Y, Z))
        for i in range(0, sh[0], 16):                     # in slabs: the whole grid's coordinates at once are large
            P = np.stack([Xb[i:i + 16] - t[0], Yb[i:i + 16] - t[1], Zb[i:i + 16] - t[2]], -1) @ R      # into the talus's frame
            out[i:i + 16] = ndi.map_coordinates(D, [(P[..., k] - lo[k]) / h for k in range(3)], order=1, mode="constant", cval=12.0)
        return out - grow
    rr = (np.stack(np.broadcast_arrays(X - NAV_HEAD_C[0], Y - NAV_HEAD_C[1], Z - NAV_HEAD_C[2]), -1) @ np.asarray(NAV_HEAD_AX)).astype(np.float32)
    ab = np.asarray(NAV_HEAD_R) + grow
    return (np.sqrt((rr[..., 0] / ab[0]) ** 2 + (rr[..., 1] / ab[1]) ** 2 + (rr[..., 2] / ab[2]) ** 2) - 1.0) * ab.min()


def _clear(D, X, Y, Z, gap, head=None, blend=0.5):
    """D kept `gap` mm off the hind faces of the three cuneiforms (NAV_CUNE_FACES) and, where `head` (a
    weight) is 1, off the talus's head. Each face is made at least gently convex (NAV_FACET_R) and falls back smoothly
    beyond its extent, so the three facets meet each other in two low rounded ridges and the rest of the bone without
    an edge. (The head's ellipsoid is the talus only over its joint surface: the weight keeps it to Fig. 277's
    border of that surface and 3 mm round it; beyond, at the lateral end, it would take off what Fig. 268 draws.)"""
    for f in NAV_CUNE_FACES.values():
        c, n, e1, e2 = (np.asarray(f[k], np.float32) for k in ("c", "n", "e1", "e2"))
        P = np.stack(np.broadcast_arrays(X - c[0], Y - c[1], Z - c[2]), -1).astype(np.float32)
        a, b, w = P @ e1, P @ e2, P @ n; del P
        q = f["q"]
        face = q[0] + q[1] * a + q[2] * b + max(q[3], 0.5 / NAV_FACET_R[0]) * a * a + max(q[5], 0.5 / NAV_FACET_R[1]) * b * b
        m = NAV_FACET_MORE
        oa = np.maximum(np.maximum(f["a"][0] - m - a, a - f["a"][1] - m), 0.0); ob = np.maximum(np.maximum(f["b"][0] - m - b, b - f["b"][1] - m), 0.0)
        face = face - NAV_FACET_FALL * (oa * oa + ob * ob); del oa, ob      # (falling away from this bone: the hold lets go)
        D = sdf.smax(D, (face + gap + f.get("give", 0.0) - w).astype(np.float32), blend)
    if head is not None:
        D = sdf.smax(D, -_head(X, Y, Z, gap) - 6.0 * (1.0 - head), TALAR_CLEAR_BLEND)    # (let go gently: switched off over 1.5 mm it left its edge as a straight slit)
    return D.astype(np.float32)


def _rough7(patches, rng):
    """Rough patches traced on Fig. 277 (whose pixels are fine: 0.07 mm), as _rough's pits and low swellings, with
    the swellings a millimetre or so across."""
    out = []
    for poly, n, lumps in patches:
        from PIL import Image, ImageDraw
        poly = np.asarray(poly, float); lo, hi = poly.min(0), poly.max(0); k = 0; j = 0
        im = Image.new("L", (int(hi[0]) + 2, int(hi[1]) + 2), 0); ImageDraw.Draw(im).polygon([tuple(q) for q in poly], fill=255); ins = np.asarray(im) > 0
        inside = lambda p: ins[int(p[1]), int(p[0])]
        while k < n:
            p = rng.uniform(lo, hi)
            if inside(p):
                out.append(("dot", (float(p[0]), float(p[1])), float(rng.uniform(0.25, 0.55)), float(rng.uniform(-0.5, -0.25)))); k += 1
        while j < lumps:
            p = rng.uniform(lo, hi)
            if inside(p):
                a = rng.uniform(9, 18); t = np.linspace(0, 2 * np.pi, 9)[:-1]; rad = a * rng.uniform(0.6, 1.3, len(t))
                out.append(("area", [(float(p[0] + q * np.cos(w)), float(p[1] + 0.8 * q * np.sin(w))) for q, w in zip(rad, t)],
                            float(rng.choice([-1, 1]) * rng.uniform(0.2, 0.35)), 1.0)); j += 1
    return out
