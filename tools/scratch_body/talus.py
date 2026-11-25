"""talus.py: the right talus, built as foot.py builds the calcaneus, from nothing but Gray's plates (Anatomy of the
Human Body, 1918, public domain: Fig. 270 the left talus from above, 271 from below, 272 its medial surface, 273 its
lateral surface) and his text (pp. 266 to 268). No scan and no other model is used.

Its own frame, millimetres, the right bone: x medial, y up, z forward; z from the hindmost point of the posterior
process (the lateral tubercle), y from the lowest point of the lateral plate, x from the middle of the trochlea. Gray
gives no measure: the bone is set 60 mm long in the lateral plate (in Fig. 291 it is about three quarters as long as
the calcaneus, which foot.py sets at 79 mm), and that fixes every other size by the plates' own proportions.
"""
import os
import numpy as np
from scipy import ndimage as ndi
import sdf
import platematch as pm
import foot
from foot import _ss, _bump, _near, _cut, _tube, _one_piece, _pixels, _read, _round_meet, _marks_map, lay, emboss, grain
from sdf import Ellipsoid, Field, rot

# Gray 1918, the left talus, written as mirror views of the right-hand model (platematch's way). pose: nod, turn, roll
# (degrees), scale factor, shift right and down (pixels).
TALUS = [
    dict(fig="Gray270", cap="from above", right=(1, 0, 0), up=(0, 0, 1), eye=(0, 1, 0), s=0.208, u0=222, v0=354,
         pose=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0), free=(0, 0, 0, 0, 0, 0)),
    dict(fig="Gray273", cap="lateral surface", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=0.2007, u0=308, v0=219,
         pose=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0), free=(0, 0, 0, 0, 0, 0)),
    dict(fig="Gray272", cap="medial surface", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=0.240, u0=139, v0=202,
         pose=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0), free=(0, 1, 1, 1, 1, 1)),
    dict(fig="Gray271", cap="from below", right=(-1, 0, 0), up=(0, 0, 1), eye=(0, -1, 0), s=0.197, u0=137, v0=362,
         pose=(0.0, 0.0, 0.0, 1.0, 0.0, 0.0), free=(0, 1, 1, 1, 1, 1)),
]
pm.PLATES.setdefault("talus", TALUS)          # for the dev tools (trace_plates.py, fit_plates.py, zoom_plates.py)


def talus(h=0.4, log=print, relief=1.0, upto="all", poses=None, ink=foot.INK):
    """upto="hull" stops at the bare solid inside the four plates' outlines (what the plates' poses are fitted on,
    dev/fit_plates.py); `poses` tries other poses than the traces were made at ({fig: pose})."""
    F = Field((-30.0, -6.0, -5.0), (30.0, 44.0, 66.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    tr = foot.traces("talus"); V = {v["fig"]: v for v in TALUS}
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}

    def outline(fig):
        px = V[fig]["s"] * P[fig][3]; d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
        return _read(ndi.gaussian_filter(d, 1.0 / px), *_pixels(V[fig], P[fig], X, Y, Z))

    # 1. inside the plates' outlines: the two plans (above, below) and the two sides
    plan = sdf.smax(outline("Gray270"), outline("Gray271"), 1.5)
    side = sdf.smax(outline("Gray273"), outline("Gray272"), 1.5)
    R = ndi.gaussian_filter1d(np.interp(F.ax[2], [0.0, 6.0, 14.0, 34.0, 42.0, 50.0, 60.0], [3.0, 4.0, 5.0, 5.0, 5.0, 7.0, 8.0]), 3.0 / h)[None, None, :]
    D = _round_meet(plan, side, R); del plan, side
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32)
    return _one_piece(F)
