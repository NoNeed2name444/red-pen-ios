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
CUBOID = [
    dict(fig="Gray274", cap="antero-medial view", right=(-1, 0, 0), up=(0, 1, 0), eye=(0, 0, 1), s=0.156, u0=228, v0=124,
         pose=(0.0, 30.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
    dict(fig="Gray275", cap="postero-lateral view", right=(1, 0, 0), up=(0, 1, 0), eye=(0, 0, -1), s=0.156, u0=167, v0=83,
         pose=(20.0, 35.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
]
NAVICULAR = [
    dict(fig="Gray276", cap="antero-lateral view", right=(-1, 0, 0), up=(0, 1, 0), eye=(0, 0, 1), s=0.18, u0=176, v0=137,
         pose=(0.0, -20.0, 0.0, 1.0, 0.0, 0.0), free=(1, 1, 1, 1, 1, 1)),
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


# Fig. 268 (the right foot from above), the cuboid's dorsal surface, read under a grid at 0.208 mm a pixel from its
# hind lateral corner at pixel (190, 388): x toward the big toe's side, z toward the toes.
CUB_PLAN = [(0.0, 0.0), (5.0, -1.2), (11.5, -0.8), (16.5, 0.2), (21.0, 2.3),               # behind, against the calcaneus
            (21.4, 5.0), (19.0, 8.6), (15.4, 12.2), (11.6, 15.6), (8.4, 19.0), (6.2, 24.0), (5.0, 30.2),      # medial, against the navicular's end and the third cuneiform
            (2.2, 28.6), (-1.8, 25.6), (-4.8, 22.6), (-6.2, 19.2),                         # in front, the fourth and fifth metatarsals
            (-3.4, 16.0), (-2.0, 11.0), (-1.6, 5.0)]                                       # lateral, to the notch of the peroneal sulcus
# The plan low down, which Fig. 268 cannot show. Behind, the infero-medial angle "projects backward as a process which
# underlies and supports the anterior end of the calcaneus": Fig. 275 draws its tip 5.6 mm (31 pixels) beyond the hind
# medial corner, Fig. 274 has it the lowest, hindmost point. The medial surface is "broad" and has no dent below (the
# dent of the dorsal plan is where the third cuneiform lies over it). In front and laterally Fig. 275's outline stands
# 3 mm beyond the dorsal plan's corner: the base under the fifth metatarsal, in front of the sulcus.
CUB_SOLE = [(0.0, 0.0), (5.0, -1.5), (12.0, -2.6), (18.0, -4.4), (23.0, -5.2), (25.6, -3.4),
            (25.4, 0.5), (23.0, 6.0), (20.0, 11.0), (16.2, 16.0), (12.4, 20.4), (9.2, 25.0), (7.0, 31.0),
            (3.0, 29.6), (-2.0, 26.6), (-6.0, 24.0), (-8.4, 21.6),
            (-8.0, 18.6), (-4.6, 15.2), (-2.6, 11.0), (-2.0, 5.0)]


def cuboid(h=0.3, log=print, relief=1.0, upto="all", poses=None, ink=INK):
    """upto="body": the plan of Fig. 268 carried through the bone's height, nothing more; "hull": what of it lies
    inside the outlines of Fig. 274 and 275 (what the poses are fitted on); `poses` tries other poses."""
    F = Field((-12.0, -9.0, -11.0), (30.0, 31.0, 37.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    V = {v["fig"]: v for v in CUBOID}
    tr = traces("cuboid") if upto != "body" or poses is None else None
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"] if tr is not None else V[f]["pose"]), float) for f in V}
    plan = _plan(CUB_PLAN, X, Z) + 0.0 * Y
    plan = plan + (_plan(CUB_SOLE, X, Z) - plan) * _ss((15.0 - Y) / 10.0)
    body = np.maximum(plan, np.maximum(Y - 27.0, -6.0 - Y))
    if upto == "body":
        F.D = np.clip(body, -12.0, 12.0).astype(np.float32); return F

    def outline(fig):
        px = V[fig]["s"] * P[fig][3]; d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
        return _read(ndi.gaussian_filter(d, 0.6 / px), *_pixels(V[fig], P[fig], X, Y, Z))

    D = _round_meet(_round_meet(outline("Gray274"), outline("Gray275"), 2.0), body, 2.5)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32)
    if upto == "hull":
        return F
    return _one_piece(F)
