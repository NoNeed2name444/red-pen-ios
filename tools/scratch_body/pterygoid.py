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
    (31.6, -22.0), (32.6, -23.5), (32.9, -26.2), (33.0, -28.4), (33.1, -29.6), (33.3, -32.0), (33.0, -33.0), (33.6, -34.0),   # a small point half-way down; the lower corner turned back a little (Fig. 189), not a rod
    (35.0, -35.0), (36.8, -36.8), (38.9, -37.6), (41.0, -38.6), (43.0, -38.8),                    # lower border: falling forward into the tuberosity, rising back to the corner
    (44.2, -34.0), (44.2, -20.0), (44.2, -5.0)]                                                                  # (its front, from z 41, is sunk in the wall that joins the plates)
MEDIAL = [
    (27.0, -5.0), (27.9, -8.8), (28.6, -10.4), (29.9, -12.6), (31.3, -15.6), (32.4, -18.8), (33.1, -22.2),       # hind border: from the tubercle at its root
    (33.9, -25.6), (35.1, -28.9), (36.5, -31.8), (37.6, -34.4), (38.2, -36.6), (38.3, -38.3),                    # down and forward, a slow S, to the hook
    (39.5, -38.3)]
# its lower border from the hook up to the palate's hind corner, as it now stands (not moved back with the rest below)
MEDIAL_FOOT = [(37.0, -37.2), (37.4, -35.6), (37.9, -33.6), (38.6, -31.4), (39.6, -29.6), (41.5, -28.9),
               (46.3, -28.7), (50.5, -28.2), (50.5, -5.0)]        # (in front of the palate's hind edge it ends inside the palate's plate, a millimetre above the mouth's roof: it showed there as a bump)                                                   # carried forward above the palate as the palatine's upright plate (the nose's side wall)

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
# The process's lower part stands further back than first drawn: the palate's hind border was moved back to Fig. 996's place
# (palate.HIND: spine 12.6 mm behind the third molars' crown line), and Fig. 187 has the plates' lower ends and the pyramidal process
# level with the posterior nasal spine (the hamulus a little behind it). Everything below y -22 is carried back, up to BACK mm
# from y -34 down; the root and the fissure stay.
BACK = 3.0


def back(z, y):
    return z - BACK * smoothstep((-22.0 - y) / 12.0)


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


LATERAL = [(back(z, y), y) for z, y in LATERAL]
MEDIAL = [(back(z, y), y) for z, y in MEDIAL] + MEDIAL_FOOT
LATERAL_X = [(back(z, y), y, x) for z, y, x in LATERAL_X]
MEDIAL_X = [(back(z, y), y, x) for z, y, x in MEDIAL_X]
HAMULUS = [(x, y, back(z, y)) for x, y, z in HAMULUS]
# the palatine's pyramidal process. Fig. 187 (from below), Fig. 169 (the palatine from behind) and Figs. 189/190 (the process from
# behind): it fills the notch between the two plates' lower ends as a wedge, broad below and narrowing upward between them; its hind
# face is grooved, the groove running on up as the floor of the hollow between the plates; its lower end rounded, falling outward
# and forward to the tuberosity; its hind face level with the spine (Fig. 996: 11.9 to 13 mm behind the third molars 15 to 23 mm out).
# Built as Wedge below. PYRAMID is the tube that covers it, kept for bones.py (which part of the bone is the palatine's).
PYRAMID = ([(18.6, -33.4, 43.2), (20.0, -35.0, 39.0), (20.6, -35.6, 36.4)], [2.9, 2.6, 2.1], [4.6, 5.4, 5.4])


def pyramid():
    return Tube(np.array(PYRAMID[0], float), [(0, PYRAMID[1][0]), (0.5, PYRAMID[1][1]), (1, PYRAMID[1][2])], [(0, PYRAMID[2][0]), (0.5, PYRAMID[2][1]), (1, PYRAMID[2][2])])


class Wedge:
    """The pyramidal process: the bone between the inner plate (xi) and the outer (xo) below y -29. Its hind face z(y, s), s = 0 at
    the inner plate and 1 at the outer: grooved (the middle forward), the groove fading out toward the rounded lower end; the face
    slopes back as it goes down, and a little back as it goes out. Its lower border falls outward and, toward the front, to the
    tuberosity."""
    def __init__(self, M, xm, xl):
        self.M, self.cm, self.cl = M, M.smooth(xm), M.smooth(xl)
        self.bounds = (np.array([12.0, -42.0, 32.0]), np.array([30.0, -27.0, 45.0]))

    def __call__(self, X, Y, Z):
        x, y, z = np.broadcast_arrays(np.abs(X), Y, Z)
        a = self.M.smooth_sample(self.cm, z, y) + 0.6; b = self.M.smooth_sample(self.cl, z, y) - 0.2
        s = np.clip((x - a) / np.maximum(b - a, 1.0), 0.0, 1.0)
        low = -35.8 - 2.8 * s ** 1.3 - 0.5 * np.sin(np.pi * s) - 1.2 * s * smoothstep((z - 38.0) / 4.0)   # the lower end: rounded, falling outward and forward to the tuberosity
        up = smoothstep((y - low) / 3.0)                                                 # 0 at the lower end, 1 from 3 mm above it
        ze = 33.8 + 0.75 * np.clip(y - low, 0.0, 6.0) + 0.4 * smoothstep((s - 0.55) / 0.45)   # the hind face: back as it goes down
        ze = ze + 1.6 * 4.0 * s * (1.0 - s) * up                                          # its groove, from the rounded end up
        ze = ze + 1.6 * (2.0 * s - 1.0) ** 2 * (1.0 - up)                                 # and the end itself rounded from below, not squared
        r = 0.9                                                                          # (edges rounded: a soft maximum, not a box)
        soft = lambda *v: r * np.log(sum(np.exp(np.clip(w / r, -30, 30)) for w in v))
        d = soft(a - x, x - b, ze - z, z - 44.0, low - y, y + 29.0)
        return (0.8 * d).astype(np.float32)


SCAPHOID = ((15.3, -9.6, 29.6), (1.5, 3.0, 2.3))      # the small boat-shaped hollow at the inner plate's root, between the two lips of its hind border


class Web:
    """The bone that joins the two plates in front: the front wall of the hollow between them (below, where the plates
    part, the palatine's pyramidal process fills the cleft). Its hind face is the hollow's floor."""
    def __init__(self, M, xm, xl):
        self.M, self.cm, self.cl = M, M.smooth(xm), M.smooth(xl)
        self.bounds = (np.array([11.0, -39.0, 38.5 - BACK]), np.array([25.0, -4.0, 45.5]))

    def __call__(self, X, Y, Z):
        x, y, z = np.broadcast_arrays(np.abs(X), Y, Z)
        a = self.M.smooth_sample(self.cm, z, y); b = self.M.smooth_sample(self.cl, z, y)
        zw = back(40.6 + 0.9 * smoothstep((-14.0 - y) / 20.0), y)
        d = np.maximum(np.maximum(a - x, x - b), np.maximum(zw - z, z - back(44.6, y)))
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
            # its lower front, where it meets the pyramidal process and the tuberosity, thickens into them (Fig. 189): not a free edge
            th = th + 1.4 * smoothstep((-30.0 - M.V) / 5.0) * smoothstep((M.U - 32.5) / 4.0)
        else:                                                                                 # the inner plate's hind border is thick at its root, where it parts in two
            th = th + 1.9 * smoothstep((M.V + 15.5) / 6.5) * smoothstep((33.5 - M.U) / 4.0)
        F.add(Slab(M, (2, 1, 0), xm + th / 2, xm - th / 2, reg, round=min(0.5, 0.3 * sheet)), 0.9, keep=4)
        out.append(xm)
    xi, xo = out[1], out[0]
    F.add(Web(M, xi, xo), 1.6, keep=4)
    # the palatine bone's pyramidal process: the rounded wedge that fills the cleft between the two plates' lower ends, behind the
    # palate's hind corner and inside the upper jaw's tuberosity (p. 168: "received into the angular interval between the lower
    # extremities of the pterygoid plates"); its hind face is the lowest part of the hollow between the plates
    F.add(Wedge(M, xi, xo), 2.0, keep=4)
    F.add(Tube(spline(np.array(HAMULUS, float), 0.5), [(0, 1.35), (0.5, 1.15), (1, 0.9)]), 0.9, keep=3)       # (at 1 mm and less it read as a wire from below)
    F.cut(sdf.Ellipsoid(*SCAPHOID), 0.8)
    # the cleft between the upper jaw's back and the outer plate's front border (pterygomaxillary fissure, Fig. 189): open above,
    # where it runs up into the fissure in the orbit's floor, closing below where jaw, palatine bone and plate meet
    F.cut(Tube(spline(np.array(FISSURE, float), 0.5), 3.2, [(0, 2.5), (0.35, 1.9), (0.7, 1.0), (1, 0.35)], up=(0.83, 0, 0.55)), 1.0)
    a = np.array(LATERAL); b = np.array(MEDIAL)
    log("pterygoid: outer plate %.0f mm front to back behind the wall at its root and %.0f below, turned out from %.0f to %.0f mm; inner plate %.0f mm out, its hook's tip %.0f mm below the Frankfurt plane; each %.1f mm thick"
        % (41.0 - a[:, 0].min(), 41.0 - 33.5, 22.6, 29.2, 13.8, -HAMULUS[-2][1], sheet))
    return dict(M=M, inner=xi, outer=xo)
