"""base.py: the underside of the skull as a relief over the view from below.

The braincase alone (skull2.Star) is closed underneath by a smooth bowl. A real skull's underside is
a landscape: the body of the sphenoid high in the middle, the basilar part of the occipital sloping
down and back from it to the front of the foramen magnum, the petrous parts running in toward it
from the ear, the hollow for the jugular bulb, the socket for the jaw, the flat field of the greater
wing. Here that landscape is one height map over (x, z): the height y of the bone's under surface.

Where the heights come from:
  midline   the sagittal section, Gray 1918 Fig. 194 (page 193 of the Internet Archive scan), put to
            the side view's scale (greatest length 183.5 mm) and set on the face as the side view has it:
            under the sphenoid's body -9, front of the foramen magnum (basion) -23 (at z 4.2, where Fig. 187 has it), its back
            (opisthion) -27 at z -34.5, lowest point of the condyle -28.5, hamulus -39.
  across    where things lie in (x, z): the view from below, Fig. 187 (page 179).
  the rest  the usual levels relative to those: the socket's roof about on the Frankfurt plane, the
            tubercle in front of it 8 mm lower, the greater wing 10 mm below the plane.
"""
import numpy as np
from scipy import ndimage
import relief, sdf

# the part of the underside the relief covers: left half, from the middle of the front edge round to the middle of the back
REGION = [(0, 43.5), (12.5, 43.5), (16, 42), (30, 41), (38, 39.5), (41.5, 36), (42, 27), (45, 23.5), (55, 22.5), (59.5, 19),
          (60.5, 10), (60.5, 0), (59.5, -10), (58, -22), (53, -31), (44, -37), (30, -41), (15, -43), (0, -43.5)]

# (x, z, y): the height of the under surface at points of the left half
HEIGHTS = [
    # body of the sphenoid, then the basilar part of the occipital sloping down and back to the basion
    (0, 43, -8.5), (0, 36, -9.0), (0, 28, -9.0), (0, 22, -9.8), (0, 17, -11.8), (0, 13, -14.5), (0, 9.5, -19.0), (0, 6.5, -21.6), (0, 4.2, -23.0),
    (7, 43, -8.7), (7, 36, -9.0), (7, 28, -9.2), (7, 22, -10.2), (7, 17, -12.2), (7, 13, -14.8), (7, 9, -18.3), (6, 6.2, -21.4), (8.5, 2.5, -22.6),
    # the valley between the basilar part and the petrous part, where the plate has their cleft, ending in front at
    # the ragged hole (foramen lacerum); the basilar part widens backward toward the condyles
    (15.3, 15, -11.0), (14.2, 12, -12.8), (16.5, 8.5, -15.6), (20, 4.5, -18.0), (12, 9, -17.6), (13, 5, -20.2),
    # round the foramen magnum
    (15.5, -16, -25.0), (11.5, -29, -26.5), (0, -34.5, -27.0), (0, -16, -25.0), (13.5, -4, -23.6),
    # beside it: the ground the condyle stands on, the jugular process, the hollow behind the condyle
    (18.5, -9, -24.0), (28, -9, -22.0), (26, -18, -23.5), (20, -23.5, -23.5), (34, -14, -21.5),
    (20, -31, -27.3), (33, -29, -26.0), (44, -28, -20.5),
    # the ground the jugular hollow and the carotid canal's mouth are cut in (foramina.py), the under side of the petrous part
    (30, -1, -18.6), (24.5, 2, -19.5), (37.5, 1.5, -17.5), (31, -6.5, -19.5), (30, 11, -17.0), (23, 12, -15.5), (18, 15.5, -13.0), (36, 9, -17.5),
    (25, 7, -17.5),
    # the sheath of the styloid process and the plate in front of the ear hole
    (43, -3, -15.5), (43, -7, -17.5), (40, 3, -14.5), (47, 0, -12.5),
    # the mastoid's ground, the notch on its inner side, the ridge the occipital meets it by
    (51, -13, -19.5), (56, -12, -13.0), (45, -16, -18.5), (40, -17, -22.5), (50, -24, -16.5), (56, -3, -7.5),
    # the socket for the jaw: its roof a little above the Frankfurt plane, the plate in front of the ear hole behind it
    (50.5, 9.5, 1.4), (50.5, 6.5, 0.8), (50.5, 12.3, 0.8), (45, 8.5, 0.0), (56.5, 9.5, 0.3), (41.5, 8.5, -2.2), (60, 9.5, -0.8),
    (50, 3, -2.5), (44.5, 3.5, -2.5), (56.5, 4.5, -2.0), (38, 9.5, -9.5),
    # in front the roof runs down in one slope (no step) to the crest of the tubercle the jaw's head rides on to when the mouth opens
    (50.5, 15, -1.3), (50.5, 17.6, -5.0), (44.5, 14.6, -2.2), (44.5, 17.2, -5.6), (56.5, 14.8, -1.0), (56.5, 17.4, -4.6),
    (44, 20.5, -7.8), (51, 20.5, -8.3), (57.5, 20, -7.2), (48, 26, -5.2), (39, 16, -11.5),
    # the greater wing: the oval hole, the spinous hole and the spine, the crest it turns up at
    (26.5, 24, -11.5), (32.5, 17, -13.5), (35.5, 14.5, -15.0), (33, 26, -9.5), (38, 22, -9.0), (40, 30, -6.5), (30, 33, -9.0),
    (36, 36, -7.5), (24, 36, -9.5), (20, 30, -10.5), (16, 24, -10.5), (14, 36, -9.5), (13, 42, -9.0), (22, 41, -9.0), (32, 40, -8.0),
    (20, 20, -12.0),
]


def underside(D, F):
    """The height of the lowest bone above each (x, z) of a field's grid (nan where there is none)."""
    neg = D < 0
    j = np.argmax(neg, axis=1); has = neg.any(axis=1)
    j0 = np.clip(j - 1, 0, None)
    a = np.take_along_axis(D, j0[:, None, :], 1)[:, 0, :]; b = np.take_along_axis(D, j[:, None, :], 1)[:, 0, :]
    ys = np.asarray(F.ax[1], float)
    y = ys[j0] + (ys[j] - ys[j0]) * np.clip(a / np.maximum(a - b, 1e-6), 0, 1)
    y[~has] = np.nan
    return y


class Below:
    """Everything under the relief, inside its region (to be cut away)."""
    def __init__(self, M, Yb, reg):
        self.M, self.Yb, self.reg = M, Yb, reg
        self.c = (M.smooth(Yb), M.smooth(reg))
        self.bounds = (np.array([0.0, -60.0, M.V.min()]), np.array([M.U.max(), float(np.nanmax(Yb)) + 2, M.V.max()]))

    def __call__(self, X, Y, Z):
        u, v, w = np.broadcast_arrays(X, Z, Y)
        return np.maximum(w - self.M.smooth_sample(self.c[0], u, v), self.M.smooth_sample(self.c[1], u, v) * 0.9).astype(np.float32)


def near(M, a, b, r):
    """A soft hill (1 on the segment a-b, falling off over r mm) on a map."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    e = b - a; L2 = max(float(e @ e), 1e-9)
    t = np.clip(((np.abs(M.U) - a[0]) * e[0] + (M.V - a[1]) * e[1]) / L2, 0, 1)
    d = np.hypot(np.abs(M.U) - a[0] - t * e[0], M.V - a[1] - t * e[1])
    return np.exp(-(d / r) ** 2)


def build(F, F0, log=print):
    """Give the field F the relief for its underside. F0: the braincase alone (to join on to). Returns what the
    later steps need: the map, the heights, the region and the floor the cranial cavity must stay above."""
    M = relief.Map(-64, 64, -48, 48, 1.0)
    half = sdf.spline(np.column_stack([np.array(REGION, float), np.zeros(len(REGION))]), 1.5)[:, :2]
    poly = np.concatenate([half, half[-2:0:-1] * np.array([-1.0, 1.0])])
    reg = M.region(poly)
    # the braincase's own underside, as a map
    yu = underside(F0, F)
    xs, zs = np.asarray(F.ax[0], float), np.asarray(F.ax[2], float)
    iu = np.clip((np.abs(M.U) - xs[0]) / F.h, 0, len(xs) - 1.001); iv = np.clip((M.V - zs[0]) / F.h, 0, len(zs) - 1.001)
    star = ndimage.map_coordinates(np.nan_to_num(yu, nan=60.0), [iu, iv], order=1, mode="nearest")
    pts = [(x, z, y, 1.0) for x, z, y in HEIGHTS] + [(-x, z, y, 1.0) for x, z, y in HEIGHTS if x > 0]
    # behind, the relief runs out into the braincase's own surface
    ring = (reg > 2.0) & (reg < 7.0) & (M.V < -24) & (star < 20) & (np.abs(M.U) % 3 < 1) & (M.V % 3 < 1)
    pts += [(u, v, s, 0.4) for u, v, s in zip(M.U[ring], M.V[ring], star[ring])]
    Yb = M.thin_plate(np.array(pts, float), weight=30.0)
    H = np.array(HEIGHTS, float)
    off = M.sample(Yb, H[:, 0], H[:, 1]) - H[:, 2]
    log("underside relief through %d points (%d on the rim): off by rms %.2f, worst %.2f mm" % (len(H), int(ring.sum()), np.sqrt((off ** 2).mean()), np.abs(off).max()))
    # how thick the bone is above the relief: thin under the greater wing, thick in the sphenoid's body, the petrous part, round the condyles
    Tf = (4.5 + 11.0 * near(M, (0, 6), (0, 40), 11.0) + 9.0 * near(M, (47, -3), (17, 16), 8.0)
          + 6.0 * near(M, (22, -9), (22, -9), 12.0) + 6.0 * near(M, (50, -14), (50, -14), 10.0))
    gap = np.where(star < 40, star - Yb, 0.0)
    Ts = np.maximum(Tf + 1.5, np.minimum(gap + 2.5, 17.0))
    # Behind, the relief hands over to the braincase's own surface. A solid laid in the bone's surface stands a little
    # proud of it and a cut along that surface takes a little off, and wherever either stopped it showed: first as a
    # seam across the back of the skull, then as a band behind the great opening. So nothing stops there now: over the
    # last 14 mm before the region's hind edge the relief's heights go over into the braincase's, and the finished
    # field itself is mixed with the braincase's, a little more at every step, until only the braincase is left.
    ease = lambda q: np.clip(q, 0.0, 1.0) ** 2 * (3 - 2 * np.clip(q, 0.0, 1.0))
    over = ease((-18.0 - M.V) / 8.0) * ease((reg + 16.0) / 14.0)
    Yb = np.where(star < 40, Yb + (star - Yb) * over, Yb)
    F.cut(Below(M, Yb, reg), 2.0)
    F.add(relief.Slab(M, (0, 2, 1), -Yb, -(Yb + Ts), reg, round=2.5, sign=-1.0), 3.0)
    sl = F.window((0.0, float(F.lo[1]), float(M.V.min())), (float(M.U.max()), float(F.ax[1][-1]), -18.0))
    if sl is not None:                                       # (a block built without the back of the head has none of this)
        X, Y, Z = F.coords(sl)
        u, v = np.broadcast_arrays(X[:, 0, :], Z[:, 0, :])
        w = M.sample(over, u, v)[:, None, :].astype(np.float32)
        F.D[sl] = F.D[sl] * (1.0 - w) + F0[sl] * w
    return dict(M=M, Yb=Yb, reg=reg, floor=Yb + Tf)


# the jaw's socket as it is seen from below (x, z): what is laid over it afterwards (the root of the cheek's arch) is cleared out of it again
SOCKET = [(38.5, 6), (41, 2.4), (47, 1.0), (55, 1.6), (60.5, 4), (62, 10), (61, 17), (57.5, 22), (50, 23.5), (43, 22.5), (38.5, 17), (37, 11)]


def socket_cut(F, B, k=2.0):
    """Clear the jaw's socket: everything under the relief inside the socket's outline. The socket's shape is the
    relief's own (its roof, the slope down to the tubercle), so it has no rim of its own."""
    M = B["M"]
    P = sdf.spline(np.column_stack([np.array(SOCKET, float), np.zeros(len(SOCKET))]), 1.0, closed=True)[:, :2]
    cut = Below(M, B["Yb"], M.region(P))
    cut.bounds = (np.array([34.0, -30.0, -2.0]), np.array([64.0, 6.0, 27.0]))
    F.cut(cut, k)


def floor_cut(F, B):
    """Keep the cranial cavity above the relief's floor: fill again whatever of the cavity lies under it."""
    M = B["M"]
    X, Y, Z = F.coords(tuple(slice(0, n) for n in F.n))
    for i in range(0, F.n[0], 16):
        u, v, w = np.broadcast_arrays(X[i:i + 16], Z, Y)
        fl = M.sample(B["floor"], u, v); rg = M.sample(B["reg"], u, v)
        under = np.maximum(w - fl, rg)                       # < 0: under the floor and inside the region
        above = M.sample(B["Yb"], u, v) + 0.5 - w            # < 0: above the relief itself
        F.D[i:i + 16] = np.minimum(F.D[i:i + 16], np.maximum(under, above))
