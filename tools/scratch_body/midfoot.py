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
    dict(fig="Gray277", cap="postero-medial view", right=(1, 0, 0), up=(0, 1, 0), eye=(0, 0, -1), s=0.18, u0=176, v0=137,
         pose=(0.0, -20.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
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


# The navicular. Fig. 276 is its only own plate here (Fig. 277, the postero-medial view, could not be fetched: the
# plate server refused every request), so the bone is held by three outlines: its plan as Fig. 268 draws its dorsal
# surface (0.208 mm a pixel, x = (u - 377) 0.208, z = (v - 440) 0.208), its side as Fig. 290 draws it between the
# talus's head and the first cuneiform (0.49 mm a pixel, the scale of Fig. 291 at which the calcaneus is 79 mm:
# z = (u - 210) 0.49, y = (80 - v) 0.49), and Fig. 276 from in front, whose pose is fitted to the first two.
NAV_PLAN = [((u - 377.0) * 0.208, (v - 440.0) * 0.208) for u, v in [
    (310, 398), (330, 402), (350, 406), (370, 408), (390, 405), (410, 397), (425, 391),        # behind, the talus's head
    (435, 400), (443, 415), (447, 432), (445, 450), (437, 465), (425, 477),                     # medial, the tuberosity
    (410, 486), (390, 491), (365, 488), (340, 479), (318, 470),                                 # in front, the cuneiforms
    (308, 455), (304, 430), (305, 410)]]                                                         # the lateral end
NAV_SIDE = [((u - 210.0) * 0.49, (80.0 - v) * 0.49) for u, v in [
    (204, 44), (202, 60), (200, 77), (195, 85), (190, 90), (187, 101), (188, 110), (193, 116),   # behind, up to down
    (200, 118), (207, 116), (211, 110), (221, 94), (229, 77), (231, 64), (226, 47), (218, 43), (210, 42)]]   # in front
# Fig. 276, in its own pixels: the three facets for the cuneiforms (medial to lateral) and the occasional one for the cuboid
NAV_FACETS = {"Gray276": [
    [(104, 108), (140, 95), (172, 90), (179, 94), (181, 123), (180, 163), (167, 177), (135, 179), (105, 177), (92, 167), (89, 143), (93, 119)],
    [(186, 94), (196, 90), (215, 88), (234, 89), (248, 94), (255, 102), (256, 110), (245, 115), (231, 125), (222, 143), (217, 163), (211, 169),
     (195, 167), (187, 160), (185, 125)],
    [(267, 113), (279, 123), (282, 139), (275, 163), (255, 183), (235, 191), (223, 183), (219, 163), (223, 143), (235, 125), (251, 116)],
    [(222, 205), (230, 196), (248, 188), (254, 191), (242, 204), (228, 213)]]}
NAV_MARKS = {"Gray276": [
    # the rough plantar part between the 1st and 3rd facets, under the 2nd, and the pits the plate draws in it
    ("area", [(160, 182), (185, 172), (212, 172), (222, 190), (215, 212), (190, 218), (165, 205)], -0.5, 1.2),
    ("dot", (163, 196), 0.5, -0.6), ("dot", (176, 205), 0.4, -0.5), ("dot", (199, 190), 0.35, -0.4),
    # the thick rim of the dorsal surface above the facets, a light raised border
    ("line", [(80, 125), (100, 100), (140, 80), (190, 66), (235, 64), (262, 80), (278, 105)], 1.0, 0.35),
    # the two ridges between the three facets, clear and single
    ("line", [(182, 92), (183, 110), (183, 140), (182, 170)], 1.1, 0.8),
    ("line", [(261, 100), (246, 115), (232, 126), (222, 145), (218, 172)], 1.1, 0.8),
    # the facet for the third cuneiform a shallow oval dish of its own
    ("area", [(267, 113), (279, 123), (282, 139), (275, 163), (255, 183), (235, 191), (223, 183), (219, 163), (223, 143), (235, 125), (251, 116)], -0.25, 0.9)]}


def _slab(poly, a, z, across=0, step=0.2):
    """How far a point lies behind a traced outline's back border or in front of its front border (mm, below 0
    between), the borders read along z at each value of the other coordinate (`across` says which of the outline's two
    is that one: 0 for (x, z) outlines, 1 for (z, y)); beyond the outline's ends its end values hold."""
    P = sdf.spline(np.asarray(poly, float), 0.4, closed=True)
    if across == 1:
        P = P[:, ::-1]
    lo, hi = P[:, 0].min(), P[:, 0].max(); grid = np.arange(lo, hi + step, step); zb = np.full(len(grid), np.nan); zf = zb.copy()
    for i, g in enumerate(grid):
        near = np.abs(P[:, 0] - g) < 0.6
        if near.any():
            zb[i] = P[near, 1].min(); zf[i] = P[near, 1].max()
    ok = ~np.isnan(zb); zb = np.interp(grid, grid[ok], zb[ok]); zf = np.interp(grid, grid[ok], zf[ok])
    zb = ndi.gaussian_filter1d(zb, 2.5 / step, mode="nearest"); zf = ndi.gaussian_filter1d(zf, 2.5 / step, mode="nearest")
    b = np.interp(a, grid, zb); f = np.interp(a, grid, zf)
    return np.maximum(b - z, z - f).astype(np.float32)


def navicular(h=0.3, log=print, relief=1.0, upto="all", poses=None, ink=INK):
    """upto="body": inside the plan (Fig. 268) and the side (Fig. 290), what Fig. 276's pose is fitted on; "hull":
    within Fig. 276's outline as well; "forms": with the forms cut by hand."""
    F = Field((-22.0, -24.0, -16.0), (23.0, 24.0, 16.0), h)
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
    D = sdf.smax(_slab(NAV_PLAN, X, Z), _slab(NAV_SIDE, Y, Z, across=1), 2.5)
    fig = "Gray276"; px = V[fig]["s"] * P[fig][3]
    d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
    o6 = _read(ndi.gaussian_filter(d, 1.3 / px), *_pixels(V[fig], P[fig], X, Y, Z))
    if upto != "hull":
        # (no face of it runs straight back from Fig. 276's outline: the dorsal and plantar surfaces are convex from
        # the talus forward to the cuneiforms, and the outline's walls fall in toward both)
        o6 = o6 + 0.028 * (Z - 0.5) ** 2 * (1.0 + 0.15 * np.sin(0.35 * X + 0.25 * Y))
    D = _round_meet(D, o6, 1.3 + 1.4 * _ss((1.0 - Z) / 5.0) + 0.0 * D); del o6      # (a firm rim in front, as Fig. 276 draws it)
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    B = pm.basis(V[fig], P[fig][:3]); ax_ = B[0]                    # the bone's long axis (Fig. 276's left to right: medial to lateral)
    # 2a. behind, the surface for the talus: "oval, concave, broader laterally than medially". The head as Fig. 268
    # draws its front border: some 17 mm in radius from side to side; the socket 4 mm deep, its rim left all round.
    c = np.array([0.0, 0.0, -15.6]) + 2.0 * ax_
    rr = (np.stack(np.broadcast_arrays(X - c[0], Y - c[1], Z - c[2]), -1) @ np.stack([ax_, B[1], [0.0, 0.0, 1.0]], 1)).astype(np.float32)
    a = 17.5 + 1.2 * np.tanh(rr[..., 0] / 8.0)                       # the lateral half the broader
    head = (np.sqrt((rr[..., 0] / a) ** 2 + (rr[..., 1] / 11.5) ** 2 + (rr[..., 2] / 13.0) ** 2) - 1.0) * 11.5; del rr, a
    D = sdf.smax(D, -head, 1.2); del head
    # 2b. the tuberosity, at the medial end, rounded, and reaching down and back past the body (Fig. 268 has it bulge
    # medially behind the first cuneiform, Fig. 290 low at the back of the bone, Fig. 276 as the thick rounded rim of its left end)
    t = np.array([0.0, 0.0, -3.5]) - 15.0 * ax_ - 1.5 * B[1]
    D = sdf.smin(D, Ellipsoid(tuple(t), (4.0, 4.8, 4.6), rot((0, 0, 1), -40.0))(X, Y, Z), 3.5)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D
    if upto == "forms":
        return F
    # 3. the joint surfaces in front ("subdivided by two ridges into three facets") and on the lateral side, smooth;
    # the two ridges between the facets a little raised; the plate's marks
    # (Fig. 276 looks straight at the front: every layer it gives is kept to what faces it squarely, or the dorsal and
    # plantar surfaces, which fall away from the front border at a slant, take its tracings drawn out into streaks)
    _facets(F, [V[fig]], P, tr, {fig: NAV_FACETS[fig][:3]}, proud=-0.45, edge=0.8, face=0.55)        # set a little into the rim, each its own surface
    _facets(F, [V[fig]], P, tr, {fig: NAV_FACETS[fig]}, proud=0.0, face=0.55)
    # (Fig. 276 sets the facets inside a broad rough rim, widest above and at the lower middle: what of the outline the
    # facets leave is raised a little and roughened, with pits strewn over it)
    sh = tr[fig + "_sdf"].shape; inside = (tr[fig + "_sdf"].astype(np.float32) < 0).astype(np.float32)
    fac = ndi.binary_dilation(_mask(NAV_FACETS[fig][:3], sh, 0.5) > 0.5, iterations=2).astype(np.float32)
    rim = ndi.gaussian_filter(np.clip(inside - fac, 0.0, 1.0), 0.5 / px)
    rng = np.random.default_rng(276)
    bumpy = ndi.gaussian_filter(rng.normal(size=sh).astype(np.float32), 0.7 / px); bumpy /= bumpy.std()
    # (eased off over the outline's last half millimetre, where the surface turns away from the plate: raised right
    # to the edge, it stood as a seam down the bone's front border in the side views)
    rmap = rim * (0.8 + 0.3 * bumpy) * _ss((-tr[fig + "_sdf"].astype(np.float32) - 0.3) / 0.5)
    ys, xs_ = np.nonzero(rim > 0.6); pick = rng.choice(len(ys), 28, replace=False)
    rmap += _marks_map(_pits([("dot", (float(xs_[i]), float(ys[i])), float(rng.uniform(0.2, 0.45)), float(rng.uniform(-0.6, -0.3))) for i in pick], px, 277), sh, px)
    _lay(F, [V[fig]], P, {fig: rmap}, face=0.4)
    # (only on what faces the plate: laid on the dorsal and plantar surfaces, which Fig. 276 sees edge-on, the marks
    # of its border were drawn out into streaks and blocks across them)
    _lay(F, [V[fig]], P, {fig: _marks_map(_pits(NAV_MARKS[fig], V[fig]["s"] * P[fig][3]), tr[fig + "_sdf"].shape, V[fig]["s"] * P[fig][3])}, face=0.45)
    if relief:
        _emboss(F, tr, [V[fig]], P, relief, log, face=0.6)
    if ink:
        _lay(F, [V[fig]], P, {fig: tr[fig + "_ink"].astype(np.float32) * (ink / 50.0)}, face=0.55, shared=True, rough=True)
    log("navicular: built from Fig. 276, its plan from Fig. 268 and its side from Fig. 290")
    return _one_piece(F)
