"""foot.py: the bones of the foot, built from nothing but what is read off Gray's plates (Anatomy of the Human Body,
20th edition, 1918, public domain) and his text. No scan and no other model is used. The owner, 18 Nov: "ignore skull
for now and start from foot upward."

The right foot is built; the left is its mirror. Foot frame, millimetres: x toward the big toe's side (medial),
y up, z forward toward the toes. Each bone is first made in a frame of its own and then set in the foot.

A bone starts as a run of cross-sections set between the edges two of its plates draw (from above, from the side);
what the plates name is then worked into those sections or cut in, each where the plate has it.

The calcaneus (Fig. 264, from above; Fig. 266, the lateral surface; pp. 263 to 266). Its own frame: z from the back
of the tuberosity forward, y up from its lowest point (the lateral process), x from the body's long axis toward the
sustentaculum. Gray gives no measure in millimetres: the bone is set 80 mm long, which makes it 50 high and 47 across
at the sustentaculum by the plates' own proportions. That length is ours."""
import numpy as np
import sdf
from sdf import Plate, Ellipsoid, Tube, Field, rot

# Fig. 264, the left calcaneus from above, read off the plate under a millimetre grid (0.225 mm a pixel at 80 mm long)
# and written for the right bone; the sustentaculum is left off this outline, for it is a shelf and not the whole height
CALC_TOP = [(2.9, 0.4), (-5.4, 1.5), (-11.0, 7.9), (-15.2, 15.4), (-16.1, 19.9), (-14.4, 23.6), (-12.9, 30.4), (-13.7, 37.9),
            (-14.4, 45.4), (-15.0, 52.0), (-14.1, 60.4), (-11.4, 67.9), (-8.4, 73.9), (-4.7, 76.5), (2.9, 77.8), (8.9, 77.3),
            (13.4, 75.8), (16.4, 71.6), (17.6, 66.0), (15.6, 58.1), (14.9, 49.9), (14.1, 40.9), (13.8, 34.9), (15.6, 24.4),
            (17.9, 19.1), (20.5, 15.4), (20.2, 10.9), (17.1, 5.6), (11.1, 1.1)]                                         # (x, z)
# the joint surfaces as the same plate draws them, (x, z): posterior, middle (on the shelf), anterior
CALC_FACETS = [[(-7.7, 57.8), (-0.2, 58.9), (6.6, 58.1), (12.6, 58.5), (16.0, 57.8), (17.5, 55.1), (15.6, 49.9), (13.4, 45.4),
                (10.0, 42.6), (5.1, 44.6), (1.4, 49.1), (-2.4, 52.1), (-6.2, 54.0), (-8.4, 56.3)],
               [(17.1, 65.8), (20.5, 66.4), (25.0, 63.6), (29.0, 60.2), (30.0, 57.4), (27.6, 56.2), (23.0, 58.4), (19.0, 61.0), (16.6, 63.6)],
               [(11.4, 77.0), (14.6, 75.6), (17.2, 71.0), (17.6, 66.6), (15.2, 67.0), (12.6, 70.6), (10.8, 74.4)]]
# Fig. 266, its lateral surface, read the same way (0.238 mm a pixel), (z, y). Its upper edge here is the lateral one: the
# crest behind the posterior facet, the facet's fall, the floor of the sinus tarsi, the top of the anterior process
CALC_SIDE = [(0.0, 18.1), (1.4, 27.6), (3.1, 33.6), (5.5, 39.5), (7.9, 41.4), (11.4, 41.2), (16.2, 40.5), (21.0, 41.9), (25.7, 44.7),
             (29.3, 49.0), (31.4, 51.4), (33.3, 50.5), (37.6, 49.5), (42.4, 48.3), (47.1, 47.6), (50.0, 46.6), (51.8, 42.0),
             (53.0, 37.5), (54.5, 34.6), (57.5, 34.5), (60.5, 36.5), (63.0, 39.5), (66.0, 40.5), (70.9, 40.9), (74.5, 42.4),
             (76.9, 42.6), (78.0, 40.7), (77.6, 37.1), (76.2, 32.4), (76.6, 25.2), (77.4, 18.1), (76.2, 15.2), (70.9, 13.8),
             (63.8, 11.9), (56.6, 10.7), (49.5, 11.0), (42.4, 10.2), (35.2, 8.6), (30.5, 6.7), (26.9, 3.3), (24.5, 1.0),
             (20.9, 0.0), (17.4, 0.7), (13.8, 3.3), (9.0, 5.0), (4.3, 7.4), (1.4, 12.1)]


def _ss(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t)


def _bump(z, a, b, c, d):
    """0 before a, 1 from b to c, 0 after d, eased."""
    return _ss((z - a) / (b - a)) * (1.0 - _ss((z - c) / (d - c)))


class Lump:
    """A rounded block: half-sizes r along its own axes (turned by R), power n (2 an ellipsoid, more is squarer)."""
    def __init__(self, c, r, n=2.8, R=None):
        self.c = np.asarray(c, float); self.r = np.asarray(r, float); self.n = n; self.R = np.eye(3) if R is None else R
        m = float(self.r.max()) * 1.5; self.bounds = (self.c - m, self.c + m)

    def __call__(self, X, Y, Z):
        d = [X - self.c[0], Y - self.c[1], Z - self.c[2]]
        q = [sum(self.R[j, i] * d[j] for j in range(3)) / self.r[i] for i in range(3)]
        n = self.n
        k0 = (np.abs(q[0]) ** n + np.abs(q[1]) ** n + np.abs(q[2]) ** n) ** (1.0 / n)
        g = np.sqrt(sum((np.abs(q[i]) ** (n - 1.0) / self.r[i]) ** 2 for i in range(3))) * np.maximum(k0, 1e-6) ** (1.0 - n)
        return np.where(g > 1e-6, (k0 - 1.0) / np.maximum(g, 1e-6), -float(self.r.min())).astype(np.float32)


def _patch(F, poly, soft=0.7):
    """0 to 1 inside an outline drawn on the plan (x, z), its edge eased over `soft` mm: as a block (nx, 1, nz)."""
    from PIL import Image, ImageDraw
    from scipy import ndimage
    P = sdf.spline(np.asarray(poly, float), 0.4, closed=True)
    im = Image.new("L", (int(F.n[0]), int(F.n[2])), 0)
    ImageDraw.Draw(im).polygon([((x - F.lo[0]) / F.h, (z - F.lo[2]) / F.h) for x, z in P], fill=255)
    m = ndimage.gaussian_filter(np.asarray(im, np.float32).T / 255.0, soft / F.h)
    return m[:, None, :]


def _limits(outline, zcol, zt):
    """A drawn outline's two edges at each station z along the bone: (lower, upper), smoothed over a millimetre."""
    from scipy import ndimage
    P = sdf.spline(np.asarray(outline, float), 0.2, closed=True)
    z = P[:, zcol]; v = P[:, 1 - zcol]; z2 = np.roll(z, -1); v2 = np.roll(v, -1)
    lo = np.full(len(zt), np.inf); hi = np.full(len(zt), -np.inf)
    for i, t in enumerate(zt):                      # where the outline crosses this station
        c = (z - t) * (z2 - t) <= 0
        if c.any():
            w = np.where(np.abs(z2[c] - z[c]) > 1e-9, (t - z[c]) / np.where(np.abs(z2[c] - z[c]) > 1e-9, z2[c] - z[c], 1.0), 0.5)
            x = v[c] + w * (v2[c] - v[c]); lo[i] = x.min(); hi[i] = x.max()
    ok = np.isfinite(lo); j = np.flatnonzero(ok)
    lo = np.interp(np.arange(len(zt)), j, lo[j]); hi = np.interp(np.arange(len(zt)), j, hi[j])
    mid = 0.5 * (lo + hi); out = (np.arange(len(zt)) < j[0]) | (np.arange(len(zt)) > j[-1])
    lo[out] = mid[out]; hi[out] = mid[out]
    s = 1.0 / (zt[1] - zt[0])
    return ndimage.gaussian_filter1d(lo, s), ndimage.gaussian_filter1d(hi, s), zt[j[0]], zt[j[-1]]


def calcaneus(h=0.4, log=print):
    """The heel bone, in its own frame. Returns the Field.

    The body is not two outlines pushed through each other (that gives a box). At every station along the bone its
    cross-section is an oval set between the edges the two plates draw there, and the oval is not the same all the way:
    narrower above than below behind the joint, squarer toward the cuboid; its medial wall is hollowed and, higher up,
    carried out into the sustentaculum, so the shelf grows from the wall; its upper edge is lower on the medial side
    beside the posterior facet, and the facet's front edge runs obliquely as Fig. 264 draws it."""
    F = Field((-24.0, -5.0, -6.0), (40.0, 57.0, 88.0), h)
    X, Y, Z = F.coords(tuple(slice(0, int(n)) for n in F.n))
    X = X.astype(np.float32); Y = Y.astype(np.float32); Z = Z.astype(np.float32)
    zt = np.arange(-8.0, 92.0, 0.25)
    XL, XM, z0, z1 = _limits(CALC_TOP, 1, zt)
    YB, YT, _, _ = _limits(CALC_SIDE, 0, zt)
    tab = lambda z, T: np.interp(z.ravel(), zt, T).reshape(z.shape).astype(np.float32)
    # the back of the tuberosity: at its middle a cross swell where the tendo calcaneus is fixed (Fig. 268)
    Zq = Z + 1.1 * np.exp(-((Y - 21.0) / 4.5) ** 2) * np.exp(-((X - 1.0) / 13.0) ** 2) * (1.0 - _ss((Z - 2.0) / 10.0))
    # upper edge of the sections: the side plate's, but only its broad run (the fine upper surface is cut afterwards, so
    # that a step in it does not pull the whole section with it)
    from scipy import ndimage
    YTB = ndimage.gaussian_filter1d(ndimage.maximum_filter1d(YT, 56), 16.0) + 0.5
    YTB = np.where((zt < z0) | (zt > z1), YT, np.minimum(YTB, YT + 14.0 * _bump(zt, 40.0, 50.0, 70.0, 76.0) + 1.0))
    YTB = ndimage.gaussian_filter1d(YTB, 8.0)
    yt = tab(Zq, YTB)
    yb = (tab(Zq, YB) + 2.0 * np.exp(-((X - 0.5) / 3.2) ** 2) * _bump(Zq, 5.0, 13.0, 22.0, 31.0)
          + 1.6 * _ss((-X - 2.0) / 8.0) * _bump(Zq, 1.0, 9.0, 20.0, 31.0) - 1.4 * np.exp(-(X / 7.0) ** 2) * _bump(Zq, 59.0, 64.0, 70.0, 75.0))
    # lateral wall: the trochlear process, a low oblique ridge, and under it the Peroneus longus's shallow groove
    xl = (tab(Zq, XL) - 3.6 * np.exp(-(((Zq - 54.0) / 4.4) ** 2 + ((Y - 21.0 - 0.45 * (Zq - 54.0)) / 2.5) ** 2))
          + 1.6 * np.exp(-(((Zq - 52.0) / 7.0) ** 2 + ((Y - 14.5 - 0.45 * (Zq - 52.0)) / 2.6) ** 2)))
    # medial wall: "deeply concave" below, and above carried out as the sustentaculum tali (flat above, buttressed below)
    xm = (tab(Zq, XM) - 3.5 * _bump(Zq, 26.0, 38.0, 56.0, 68.0) * np.exp(-((Y - 16.0) / 8.0) ** 2)
          + 4.5 * _bump(Zq, 42.0, 52.0, 66.0, 75.0) * np.exp(-((Y - 37.0) / 7.5) ** 2))
    yc = 0.5 * (yb + yt); b = np.maximum(0.5 * (yt - yb), 0.3)
    u = (Y - yc) / b
    taper = 0.12 + 0.30 * _bump(Zq, 4.0, 14.0, 34.0, 44.0)
    a = np.maximum(0.5 * (xm - xl) * (1.0 - taper * 0.5 * (np.clip(u, -1.0, 1.0) + 1.0)), 0.3)
    n = 2.3 + 0.9 * _ss((Zq - 50.0) / 25.0)
    k0 = (np.abs((X - 0.5 * (xm + xl)) / a) ** n + np.abs(u) ** n) ** (1.0 / n)
    del yt, yb, xl, xm, yc, b, u, a
    g = np.gradient(k0, h)
    gm = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2); del g
    D = np.clip((k0 - 1.0) / np.maximum(gm, 0.02), -12.0, 12.0)
    D = sdf.smax(D, np.maximum(z0 - Z, Z - z1) + 0.0 * D, 1.5)
    # the upper surface itself. The side plate gives its height along the bone; from above (Fig. 264) the posterior
    # facet's front edge runs straight across near z 58 and the crest behind it runs obliquely, further back medially
    # than laterally. The plates do not agree to the millimetre on where the crest is, so the side plate's stations are
    # slid: its crest (31.4) to zp(x), its facet's foot (54.5) to 58. Medial to the facet lies the shelf's upper surface
    X2 = X + 0.0 * Z; Z2 = Z + 0.0 * X
    zp = np.clip(46.0 - 0.45 * (X2 - 2.0), 41.0, 52.0)
    zs = np.where(Z2 < 21.0, Z2, np.where(Z2 < zp, 21.0 + (Z2 - 21.0) / (zp - 21.0) * 10.4,
                  np.where(Z2 < 58.0, 31.4 + (Z2 - zp) / (58.0 - zp) * 23.1, 54.5 + (Z2 - 58.0) / 20.0 * 23.5)))
    top = tab(zs, YT)
    # the floor in front of the facet is the sinus tarsi laterally and narrows to the sulcus medially; behind the facet
    # the upper surface is a ridge, rounded from side to side
    top = top + 5.5 * _ss((X2 + 2.0) / 12.0) * _bump(Z2, 53.0, 57.0, 61.0, 66.0)
    top = top - 5.0 * ((X2 - 0.5) / 14.0) ** 2 * (1.0 - _ss((Z2 - 36.0) / 12.0))
    top = top + (44.0 - top) * _ss((X2 - 14.0) / 5.0) * _bump(Z2, 41.0, 47.0, 66.0, 73.0)
    top = ndimage.gaussian_filter(top, (1.2 / h, 0, 1.2 / h))
    gx, gz = np.gradient(top[:, 0, :], h); slope = np.sqrt(1.0 + gx ** 2 + gz ** 2)[:, None, :]
    F.D = sdf.smax(D, (Y - top) / slope, 4.0).astype(np.float32)
    # the sustentaculum itself: a thick shelf with a blunt edge, grown out of the swell the wall already makes for it
    F.add(Lump((20.5, 38.4, 57.5), (9.5, 5.6, 11.5), 2.8, rot((0, 1, 0), 24.0) @ rot((0, 0, 1), -6.0)), 7.0, keep=10)
    # under the shelf, the groove for the tendon of the Flexor hallucis longus (Fig. 268 names it)
    F.cut(Tube(np.array([(21.0, 31.0, 42.0), (25.5, 30.5, 56.0), (26.5, 28.5, 72.0)]), 3.0, 4.4, up=(0, 1, 0)), 3.0)
    # sulcus calcanei: in front of the posterior facet and medial to it, between it and the shelf; wider laterally
    F.cut(Tube(np.array([(18.5, 46.0, 47.0), (18.0, 43.5, 58.5), (8.0, 39.0, 62.0), (-9.0, 38.0, 62.0)]), [(0, 1.5), (0.4, 2.0), (1, 3.6)],
               [(0, 1.6), (0.4, 2.2), (1, 4.0)], up=(0, 1, 0)), 2.5)
    # in front, the saddle for the cuboid: hollow from above down, facing forward and a little outward
    F.cut(Ellipsoid((-1.0, 29.0, 84.5), (16.0, 11.0, 7.0), rot((0, 1, 0), 8.0)), 2.5)
    # the joint surfaces stand a hair proud of the rough bone round them, each with its own edge (Fig. 264): posterior,
    # middle (on the shelf), anterior; they are smooth, so the grain is held off them
    m = np.maximum.reduce([_patch(F, p) for p in CALC_FACETS]) * _ss((Y - 33.0) / 3.0)
    F.D = (F.D - 0.3 * m).astype(np.float32); F.smooth = m.astype(np.float32)
    log("calcaneus: built in its own frame, %.0f mm long" % (z1 - z0))
    return F


def grain(F, seed=264, amp=0.12):
    """A bone's fine unevenness (no surface of it is polished): chance, smoothed over about a millimetre and over four."""
    from scipy import ndimage
    rng = np.random.default_rng(seed); n = F.D.shape
    a = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), 1.0 / F.h); a /= a.std()
    b = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), 3.5 / F.h); b /= b.std()
    F.D += amp * (0.6 * a + 0.8 * b) * (1.0 - 0.85 * getattr(F, 'smooth', 0.0))
    return F
