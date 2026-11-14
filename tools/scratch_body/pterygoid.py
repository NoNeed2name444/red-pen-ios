"""pterygoid.py: the pterygoid process of the sphenoid behind the upper jaw: its two plates, the hollow between them, the hook.

Nothing here is a bar. Each plate is a thin sheet of bone with an outline of its own and a face that is not flat.
Read from Gray's Anatomy, 1918 (public domain):
  Fig. 189  the left infratemporal fossa, from the side: the outer (lateral) plate behind the upper jaw, about 8 mm from
            front to back in its lower half and 15 at its root, its free hind border hollowed, its lower hind corner
            turned back; the hook (hamulus) of the inner plate hanging below and in front of it
  Fig. 187  the base from below: the inner plate a line 14 to 15 mm from the middle plane, from the palate's hind edge
            back to z 28; the outer plate turned outward, its lower border 22 mm out in front and 28 behind, its root
            19 to 21 mm out; the ring between them is the inner pterygoid muscle's origin in the hollow (fossa)
  Fig. 147  the sphenoid from behind: the inner plates upright and a little S-shaped, the hooks turned outward, the
            outer plates broad and everted, the fossa a V open behind
  p. 151    "The lateral pterygoid plate is broad, thin, and everted"; the medial "is narrower and longer than the
            lateral; it curves lateralward at its lower extremity into a hook-like process, the pterygoid hamulus";
            the plates are joined in front above, and part below, the cleft filled by the palatine's pyramidal process

Head frame, millimetres: x to the body's left, y up, z forward. Built with the left half (the right is its mirror).
A sheet is not made thinner than the grid can carry (three cells): on a 0.5 mm grid 1.8 mm, though the real one is 1 mm.
"""
import numpy as np
from scipy import ndimage
import sdf
from sdf import spline, Tube
from relief import Map, Slab

# ---- outlines on the side view, (z, y), closed: from the root's hind end down the free hind border, along the lower border, up the front
LATERAL = [
    (26.0, -5.0), (26.5, -8.0), (27.5, -10.6), (28.9, -13.0), (30.3, -15.4), (31.5, -17.8), (32.3, -20.2),       # hind border: hollowed above
    (31.6, -22.0), (32.6, -23.5), (32.9, -26.2), (32.5, -28.4), (32.9, -29.6), (31.8, -32.0), (30.8, -33.9), (31.3, -35.8),   # a small point half-way down, a notch below it; the lower corner turned back
    (33.0, -36.7), (34.9, -36.0), (36.8, -37.0), (38.9, -36.5), (41.0, -37.4), (43.0, -37.1),                    # lower border, not a ruled line
    (44.2, -34.0), (44.2, -20.0), (44.2, -5.0)]                                                                  # (its front, from z 41, is sunk in the wall that joins the plates)
MEDIAL = [
    (27.0, -5.0), (27.9, -8.8), (28.6, -10.4), (29.9, -12.6), (31.3, -15.6), (32.4, -18.8), (33.1, -22.2),       # hind border: from the tubercle at its root
    (33.9, -25.6), (35.1, -28.9), (36.5, -31.8), (37.6, -34.4), (38.2, -36.6), (38.3, -38.3),                    # down and forward, a slow S, to the hook
    (39.5, -38.3), (40.9, -37.0), (42.3, -35.3), (43.6, -33.5), (44.8, -31.8),                                   # lower border: up and forward from the hook to the palate's hind edge
    (45.6, -30.2), (46.3, -28.7), (50.5, -28.2), (50.5, -5.0)]        # (in front of the palate's hind edge it ends inside the palate's plate, a millimetre above the mouth's roof: it showed there as a bump)                                                   # carried forward above the palate as the palatine's upright plate (the nose's side wall)

# ---- where each sheet lies: (z, y, x of its middle) points; a smooth surface is drawn through them.
# The outer plate is turned outward more and more toward its hind border and its lower end ("everted"): seen from behind it
# shows its inner face. The inner plate stands nearly in the front-to-back plane, but not as a ruled line: a slow S from root to hook.
LATERAL_X = [
    (44.0, -7.0, 18.8), (36.0, -7.0, 20.4), (26.5, -7.0, 22.6),
    (44.0, -16.0, 19.5), (38.0, -16.0, 21.2), (30.6, -16.0, 24.6),
    (44.0, -24.0, 20.2), (39.0, -24.0, 22.6), (32.5, -24.0, 26.9),
    (44.0, -31.0, 21.0), (39.5, -31.0, 24.0), (32.2, -31.0, 28.5),
    (44.0, -37.0, 21.8), (40.0, -37.0, 25.2), (31.2, -37.0, 29.7)]
MEDIAL_X = [
    (50.0, -8.0, 13.7), (50.0, -36.0, 13.8), (43.5, -8.0, 13.5), (43.5, -37.0, 14.0), (38.0, -14.0, 13.7), (39.0, -24.0, 13.9),
    (28.5, -8.0, 13.0), (30.5, -14.0, 13.9), (32.6, -20.0, 14.3), (34.5, -27.0, 13.8), (36.8, -32.0, 13.9), (38.2, -37.5, 14.7)]
HAMULUS = [(14.7, -36.8, 38.5), (14.8, -39.4, 38.7), (15.5, -41.6, 38.6), (16.8, -42.6, 38.2), (17.9, -42.4, 37.7)]
FISSURE = [(26.0, -4.0, 43.6), (25.2, -10.0, 42.5), (24.4, -16.0, 41.8), (24.3, -21.0, 41.9), (24.6, -25.0, 42.3)]
PYRAMID = ((17.6, -34.3, 41.6), (3.9, 3.5, 2.5))       # the palatine's pyramidal process (centre, half-sizes; turned 28 degrees about the upright)
SCAPHOID = ((15.3, -9.6, 29.6), (1.5, 3.0, 2.3))      # the small boat-shaped hollow at the inner plate's root, between the two lips of its hind border


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Web:
    """The bone that joins the two plates in front: the front wall of the hollow between them (below, where the plates
    part, the palatine's pyramidal process fills the cleft). Its hind face is the hollow's floor."""
    def __init__(self, M, xm, xl):
        self.M, self.cm, self.cl = M, M.smooth(xm), M.smooth(xl)
        self.bounds = (np.array([11.0, -39.0, 38.5]), np.array([25.0, -4.0, 45.5]))

    def __call__(self, X, Y, Z):
        x, y, z = np.broadcast_arrays(np.abs(X), Y, Z)
        a = self.M.smooth_sample(self.cm, z, y); b = self.M.smooth_sample(self.cl, z, y)
        zw = 40.6 + 0.9 * smoothstep((-14.0 - y) / 20.0)
        d = np.maximum(np.maximum(a - x, x - b), np.maximum(zw - z, z - 44.6))
        d = np.maximum(d, np.maximum(y + 5.0, -35.0 - y))
        return (0.8 * d).astype(np.float32)


def build(F, log=print):
    """Add the two plates, the wall that joins them in front and the hook to the half-built field."""
    h = F.h
    sheet = max(1.8, 3.0 * h)
    M = Map(22.0, 54.0, -46.0, -2.0, 0.5)                    # u = z, v = y
    out = []
    for name, outline, pts, root in (("outer", LATERAL, LATERAL_X, 1.0), ("inner", MEDIAL, MEDIAL_X, 0.7)):
        reg = M.region(spline(np.array(outline, float), 0.4, closed=True))
        xm = M.thin_plate(np.array(pts, float), weight=30.0)
        rng = np.random.default_rng(147 + len(name) + len(pts))
        n = ndimage.gaussian_filter(rng.standard_normal(xm.shape), 7.0); xm = xm + 0.22 * n / n.std()
        n = ndimage.gaussian_filter(rng.standard_normal(xm.shape), 5.0); n = n / n.std()
        # a plate's free border is an edge, not a bead: thinnest at the border, its full thickness 3 to 4 mm in; stouter toward its root
        th = (sheet - 0.45) + 0.95 * smoothstep(-reg / 3.5) * (1.0 + 0.25 * n) + root * smoothstep((M.V + 15.0) / 9.0)
        if name == "outer":
            th = th + 0.5 * smoothstep((M.U - 40.0) / 3.5)
        else:                                                                                 # the inner plate's hind border is thick at its root, where it parts in two
            th = th + 1.9 * smoothstep((M.V + 15.5) / 6.5) * smoothstep((33.5 - M.U) / 4.0)
        F.add(Slab(M, (2, 1, 0), xm + th / 2, xm - th / 2, reg, round=min(0.5, 0.3 * sheet)), 0.9, keep=4)
        out.append(xm)
    xi, xo = out[1], out[0]
    F.add(Web(M, xi, xo), 1.6, keep=4)
    # the palatine bone's pyramidal process: the rounded wedge that fills the cleft between the two plates' lower ends, behind the
    # palate's hind corner and inside the upper jaw's tuberosity (p. 168: "received into the angular interval between the lower
    # extremities of the pterygoid plates"); its hind face is the lowest part of the hollow between the plates
    F.add(sdf.Ellipsoid(PYRAMID[0], PYRAMID[1], sdf.rot((0, 1, 0), 28.0)), 2.2)
    F.add(Tube(spline(np.array(HAMULUS, float), 0.5), [(0, 1.35), (0.5, 1.15), (1, 0.9)]), 0.9, keep=3)       # (at 1 mm and less it read as a wire from below)
    F.cut(sdf.Ellipsoid(*SCAPHOID), 0.8)
    # the cleft between the upper jaw's back and the outer plate's front border (pterygomaxillary fissure, Fig. 189): open above,
    # where it runs up into the fissure in the orbit's floor, closing below where jaw, palatine bone and plate meet
    F.cut(Tube(spline(np.array(FISSURE, float), 0.5), 3.2, [(0, 2.5), (0.35, 1.9), (0.7, 1.0), (1, 0.35)], up=(0.83, 0, 0.55)), 1.0)
    a = np.array(LATERAL); b = np.array(MEDIAL)
    log("pterygoid: outer plate %.0f mm front to back behind the wall at its root and %.0f below, turned out from %.0f to %.0f mm; inner plate %.0f mm out, its hook's tip %.0f mm below the Frankfurt plane; each %.1f mm thick"
        % (41.0 - a[:, 0].min(), 41.0 - 33.5, 22.6, 29.2, 13.8, -HAMULUS[-2][1], sheet))
    return dict(M=M, inner=xi, outer=xo)
