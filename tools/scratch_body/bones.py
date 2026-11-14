"""bones.py: the skull cut into its separate bones along the sutures.

The skull is built as one solid (skull2.py). Here it is divided the way the real one is. Each suture is a wall: a thin
surface set where the suture runs. The walls together shut every bone off from its neighbours, and what lies between
them is named by a point placed inside each bone. A wall that fails to shut shows at once (two bones' points in one
piece of bone) and is reported with the way the leak runs. The thin bones inside the nose and the orbit (vomer, the
ethmoid's plate and scroll, the inferior concha, the lacrimal and nasal bones, the palatine bone) are marked off by
their own shapes instead: they are the solids nose.py and palate.py made.

Where each suture runs:
  braincase   the lines traced on Gray's Fig. 188 (plates.SUTURES_SIDE), as they were cut on the surface, carried in
              through the wall toward the middle of the braincase
  face        read off Gray's Fig. 190 (front) and Fig. 188 (side) in the head frame
  base        Gray's Fig. 187: between the openings the plate places
  inside      where no plate shows the suture, its usual course, set on this skull's own masses

Paired bones are told left from right at the end; those that meet on the midline (parietal, maxilla, palatine) part
along the midline suture as it was really cut, with its wander.

Head frame, millimetres: x to the body's left, y up, z forward. Gray's Anatomy, 20th edition, 1918: public domain.
"""
import numpy as np
from scipy import ndimage, sparse
import sdf
from sdf import spline, Ellipsoid
from relief import Map
import pterygoid, nose

C = np.array([0.0, 45.0, -2.0])           # the centre the braincase is drawn about (skull2.C)
BONES = ["frontal", "parietal", "occipital", "temporal", "sphenoid", "ethmoid", "vomer", "maxilla", "zygomatic",
         "nasal bone", "lacrimal", "palatine", "inferior nasal concha"]
ID = {n: i + 1 for i, n in enumerate(BONES)}
PAIRED = ("parietal", "temporal", "maxilla", "zygomatic", "nasal bone", "lacrimal", "palatine", "inferior nasal concha")
MIDLINE = {"parietal": "sagittal", "maxilla": "median palatine", "palatine": "median palatine"}   # which cut suture parts a pair
COLOUR = {"frontal": (232, 196, 120), "parietal": (150, 190, 230), "occipital": (150, 210, 150), "temporal": (236, 150, 140),
          "sphenoid": (190, 150, 220), "ethmoid": (250, 240, 130), "vomer": (120, 220, 210), "maxilla": (240, 222, 196),
          "zygomatic": (240, 170, 100), "nasal bone": (120, 150, 240), "lacrimal": (240, 120, 180), "palatine": (160, 200, 110),
          "inferior nasal concha": (200, 120, 90), "mandible": (168, 176, 190)}

# a point well inside each bone, left side (the right side's are these mirrored); (x, y, z)
SEEDS = {
    "frontal": [(25, 78, 76), (10, 40, 92)],
    "parietal": [(60, 85, -20)],
    "occipital": [(22, 25, -74), (2, -6, 10)],
    "temporal": [(66, 12, -2), (54, -14, -17), (30, 0, 4)],
    "sphenoid": [(3, 6, 30), (48, 18, 40), (21, -16, 37)],
    "zygomatic": [(52, -6, 64)],
    "maxilla": [(24, -16, 84)],
    "ethmoid": [(7, 14, 65)],
}

VOMER = [(76.5, -12.6), (81.0, -16.4), (87.0, -21.0), (93.0, -25.0), (97.6, -27.3), (98.0, -31.5), (84.0, -31.1), (77.0, -30.0), (71.0, -27.6), (60.0, -26.6), (50.0, -26.5), (43.0, -27.1),
         (42.0, -24.4), (40.3, -21.4), (38.4, -17.6), (36.3, -14.2), (33.9, -11.3), (31.8, -9.3), (30.2, -8.0),
         (28.9, -5.0), (45.0, -3.6)]                                                             # (z, y): nose.SEPTUM below the gap's corner, its hollowed hind edge and its wings
PLATE = [(105.5, 9.5), (97.0, 3.2), (89.0, -3.2), (81.5, -9.2), (76.5, -12.6), (45.0, -3.6), (46.0, 16.0), (90.0, 16.0), (101.0, 13.0)]   # the ethmoid's plate above it


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, float)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


# =================================== walls ===================================
def lengthen(P, ext, step):
    """The line drawn on a little past both ends, so that walls cross where sutures meet."""
    e0, e1 = ext if isinstance(ext, tuple) else (ext, ext)
    a = unit(P[0] - P[min(4, len(P) - 1)]); b = unit(P[-1] - P[max(-5, -len(P))])
    k0 = np.arange(step, e0 + 1e-6, step)[:, None]; k1 = np.arange(step, e1 + 1e-6, step)[:, None]
    return np.vstack([P[0] + k0[::-1] * a, P, P[-1] + k1 * b])


def wavy(L, amp, seed, waves=(7.3, 3.9, 2.3)):
    """A drawn line (N x 2) splined and made to wander a little to either side, its ends kept: no suture is ruler-straight."""
    P = spline(np.asarray(L, float), 0.25)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    t = np.gradient(P, axis=0); n = unit(np.column_stack([-t[:, 1], t[:, 0]]))
    ph = np.random.default_rng(seed).uniform(0, 2 * np.pi, len(waves))
    w = sum(a * np.sin(2 * np.pi * s / Lw + p) for a, Lw, p in zip((1.0, 0.7, 0.45), waves, ph)) / 1.6
    return P + (amp * w * np.clip(np.minimum(s, s[-1] - s) / 1.5, 0, 1))[:, None] * n


def y_frontonasal(ax):
    """The frontal bone's lower border at the root of the nose (front view, Fig. 190): over the nasal bones and the upper jaws'
    frontal processes, a little toothed."""
    ax = np.abs(ax)
    return np.interp(ax, [0, 3.2, 6.6, 10.0, 13.6, 22.0], [23.2, 23.9, 23.5, 22.4, 20.8, 20.5]) \
        + (0.45 * np.sin(2 * np.pi * ax / 3.7 + 0.8) + 0.3 * np.sin(2 * np.pi * ax / 1.9 + 2.1)) * np.clip(ax / 1.2, 0, 1) * np.clip((16.0 - ax) / 3.0, 0, 1)


def x_nasomaxillary(y):
    """The nasal bone's outer border (half-width at height y): narrow above, widest low down, a little uneven."""
    return np.interp(y, [-0.5, 4.5, 9.8, 14.0, 19.0, 23.5], [8.0, 9.0, 9.4, 8.2, 7.3, 6.6]) + 0.35 * np.sin(2 * np.pi * y / 6.1 + 0.9) + 0.2 * np.sin(2 * np.pi * y / 2.7)


def sweep(P, d, t0, t1, step, ext=3.0):
    """A wall: the line P (N x 3) carried along d (one direction, or a function giving one for each point) from t0 to t1 mm."""
    P = lengthen(spline(np.asarray(P, float), step), ext, step)
    Dn = unit(d(P)) if callable(d) else np.broadcast_to(unit(d), P.shape)
    t = np.arange(t0, t1 + 1e-6, step)
    return (P[:, None, :] + t[None, :, None] * Dn[:, None, :]).reshape(-1, 3)


def ribbon(P, step, depth=22.0, out=2.5, ext=3.0):
    """A suture of the braincase: its line on the surface carried in through the wall, toward the braincase's middle."""
    return sweep(P, lambda Q: C - Q, -out, depth, step, ext)


def curtain(L, axes, w0, w1, step, ext=3.0):
    """A wall drawn as a line in one view (head-frame axes iu, iv) and carried straight through from w0 to w1 along the third."""
    iu, iv = axes; iw = 3 - iu - iv
    P = np.zeros((len(L), 3)); P[:, iu] = [p[0] for p in L]; P[:, iv] = [p[1] for p in L]; P[:, iw] = w0
    d = np.zeros(3); d[iw] = 1.0
    return sweep(P, d, 0.0, w1 - w0, step, ext)


def sheet(fn, axes, u, v, step, keep=None):
    """A wall given as a height over two head-frame axes: w = fn(u, v) on the block u[0]..u[1], v[0]..v[1]."""
    iu, iv = axes; iw = 3 - iu - iv
    U, V = np.meshgrid(np.arange(u[0], u[1] + 1e-6, step), np.arange(v[0], v[1] + 1e-6, step), indexing="ij")
    Wv = fn(U, V) * np.ones_like(U)
    if keep is not None:
        m = keep(U, V); U, V, Wv = U[m], V[m], Wv[m]
    P = np.zeros((U.size, 3)); P[:, iu] = U.ravel(); P[:, iv] = V.ravel(); P[:, iw] = Wv.ravel()
    return P


def face_depth(D, lo, h, xy):
    """z of the front surface at points (x, y): the first bone met coming from in front (nan where there is none)."""
    xy = np.asarray(xy, float)
    i = np.clip(np.round((xy[:, 0] - lo[0]) / h).astype(int), 0, D.shape[0] - 1)
    j = np.clip(np.round((xy[:, 1] - lo[1]) / h).astype(int), 0, D.shape[1] - 1)
    col = np.asarray(D[i, j, :]) < 0
    k = col.shape[1] - 1 - np.argmax(col[:, ::-1], axis=1)
    return np.where(col.any(1), lo[2] + h * k, np.nan)


BAR = [(50, 16, 67), (44, 17, 59), (36, 18, 51), (27, 19, 43)]       # the orbit's outer wall (skull2.build): the sphenoid's orbital plate behind, the cheek bone in front
SZ = ((45.0, 61.0), (0.857, 0.514))                                   # the suture across it, seen from above: a point (x, z) and the direction square to it (forward and outward)
ACROSS = np.array([-0.5, 0.0, 0.857])                                 # level, across that wall toward the orbit


def frontal_plane(E):
    """The plane under the frontal bone at the orbit's outer corner: it holds the lower edge of the sphenofrontal wall (the line
    from the traced suture's lower end E in toward the braincase's middle) and runs level across the orbit's outer wall.
    Returns (d, u, y(x, z))."""
    d = unit(C - E); n = np.cross(d, ACROSS)
    return d, ACROSS, lambda x, z: E[1] - (n[0] * (x - E[0]) + n[2] * (z - E[2])) / n[1]


def z_pterygomaxillary(x, y):
    """Where the upper jaw's back meets the pterygoid process: further back low down, behind the tuberosity."""
    z = 46.5 + 3.0 * smoothstep((x - 18.0) / 4.0)
    return z + (43.0 - z) * smoothstep((-24.0 - y) / 4.0)


def walls(D, lo, h, ctx, step):
    """Every suture wall of the left half: [(name, points)]. The right half's are these mirrored."""
    S = {k: np.array(v, float) for k, v in ctx["sutures"].items()}
    sag = np.array(ctx["midlines"]["sagittal"], float)
    mid = lambda p: np.array([-2.0, p[1], p[2]])
    W = [("coronal", ribbon(np.vstack([mid(sag[0]), S["coronal"]]), step, depth=40.0)),
         ("lambdoid", ribbon(np.vstack([mid(sag[-1]), S["lambdoid"]]), step))]
    for k in ("squamosal", "parietomastoid", "occipitomastoid", "sphenoparietal", "sphenosquamosal"):
        # (the sphenoparietal wall is drawn on forward past the pterion: deep in the thick wall there it is the sphenoid's roof as far as
        # the front edge of the small wings)
        W.append((k, ribbon(S[k], step, depth=40.0 if k == "sphenoparietal" else 22.0, ext=(12.0, 3.0) if k == "sphenoparietal" else 3.0)))
    W.append(("sphenofrontal", ribbon(S["sphenofrontal"], step, depth=40.0)))        # (the wall is thick behind the orbit)
    # ---- the base, between the openings (x, z), carried up through the base's thickness
    lac, jo, jh, spine = (17.4, 16.8), (23.0, -0.1), (30.5, -1.1), (37.0, 11.0)
    om, ss = S["occipitomastoid"][-1], S["sphenosquamosal"][-1]
    W += [("spheno-occipital", curtain([(-2.0, 19.0), (6.0, 19.0), (13.0, 19.3), lac], (0, 2), -18.0, 24.0, step)),
          ("petro-occipital", curtain([lac, (19.6, 10.5), (21.6, 4.5), jo, (26.5, -0.8), jh], (0, 2), -24.0, 16.0, step)),
          ("occipitomastoid, on the base", curtain([jh, (34.0, -5.0), (37.5, -11.0), (41.0, -19.0), (om[0], om[2])], (0, 2), -32.0, 10.0, step)),
          ("sphenopetrosal", curtain([lac, (24.0, 13.4), (31.0, 11.6), spine], (0, 2), -22.0, 20.0, step)),
          ("sphenosquamosal, on the base", curtain([spine, (38.5, 16.0), (40.0, 21.0), (42.0, 27.0), (44.0, 34.0), (ss[0], ss[2])], (0, 2), -14.0, 26.0, step))]      # (up past where the suture's own wall, slanting in and up from the surface, begins: at 0.5 mm a slit was left between the two)
    # ---- the cheek bone's four sutures
    W.append(("zygomaticotemporal", curtain(wavy([(50.4, 3.8), (48.5, 0.6), (46.8, -2.2), (45.6, -4.6), (43.6, -6.4), (41.6, -9.6), (40.3, -12.0)], 0.7, 11),
                                            (2, 1), 54.0, 76.0, step, ext=0)))
    zm = spline(wavy([(27.2, 5.0), (27.6, 1.6), (28.6, -2.4), (31.0, -4.6), (35.0, -5.8), (39.0, -7.2), (43.0, -9.3), (45.2, -12.0),
                      (45.6, -15.5), (45.2, -19.5), (44.9, -22.5)], 0.6, 12), step)
    zf = face_depth(D, lo, h, zm)
    for i in range(len(zf) - 2, -1, -1):                      # above the orbit's lower rim the line looks into the orbit: keep the rim's depth
        if not np.isfinite(zf[i]) or zf[i] < zf[i + 1] - 4.0:
            zf[i] = zf[i + 1]
    zf = ndimage.uniform_filter1d(np.where(np.isfinite(zf), zf, np.nanmedian(zf)), max(int(3.0 / step), 1), mode="nearest")
    W.append(("zygomaticomaxillary", sweep(np.column_stack([zm, zf]), (0.33, 0.0, -0.94), -3.0, 34.0, step, ext=0)))
    W.append(("sphenozygomatic", curtain([(50.1, 52.4), (45.0, 61.0), (40.4, 68.7)], (0, 2), -0.5, 29.0, step, ext=0)))
    # under the frontal bone at the orbit's outer corner: the frontozygomatic suture across the rim, and on back over the outer wall
    E = S["sphenofrontal"][-1]
    d, u, _ = frontal_plane(E)
    T, Wd = np.meshgrid(np.arange(-18.0, 34.0, step), np.arange(-7.0, 22.0, step), indexing="ij")
    ok = (T <= 14.0) | (Wd <= 7.0)
    P = E + T[ok][:, None] * d + Wd[ok][:, None] * u
    # across the rim (in front of the sphenozygomatic suture) the suture is toothed: the wall there is waved, up and down
    rim = smoothstep(((P[:, 0] - SZ[0][0]) * SZ[1][0] + (P[:, 2] - SZ[0][1]) * SZ[1][1] - 1.0) / 3.0)
    wave = 0.55 * np.sin(2 * np.pi * Wd[ok] / 4.3 + 1.1) + 0.35 * np.sin(2 * np.pi * Wd[ok] / 2.2 + 0.4)
    W.append(("frontozygomatic", P + (rim * wave)[:, None] * unit(np.cross(d, u))))
    # ---- the frontal bone's hind border inside: the front edge of the sphenoid's small wings
    pt = S["sphenofrontal"][0]                                    # pterion: the three walls that meet there share one line, in toward the middle
    W.append(("sphenofrontal, inside", sheet(lambda x, y: 46.0 + 0 * x, (0, 1), (-2.0, 47.0), (21.0, 46.0), step,
                                             keep=lambda x, y: y < pt[1] + 1.0 + 0.13 * np.maximum(pt[0] - x, 0.0))))
    def y_frontal(x, z):
        front = y_frontonasal(x)
        t = smoothstep((z - 84.0) / 6.0)
        return front * t + 22.0 * (1 - t)
    W.append(("frontal's lower border", sheet(y_frontal, (0, 2), (-2.0, 22.0), (44.0, 112.0), step)))
    # ---- the ethmoid's block between the orbits
    W += [("ethmoid | maxilla", sheet(lambda x, z: 5.5 + 0 * x, (0, 2), (2.0, 27.0), (45.0, 85.0), step,
                                      keep=lambda x, z: x < 18.0 + 9.0 * (1 - smoothstep((z - 52.0) / 10.0)))),
          ("ethmoid, front", curtain([(-2.0, 84.0), (18.0, 84.0)], (0, 2), 4.5, 23.5, step, ext=0)),
          ("ethmoid | sphenoid", curtain([(-2.0, 46.0), (24.0, 46.0)], (0, 2), -12.0, 22.5, step, ext=0))]
    W.append(("maxilla | sphenoid", sheet(z_pterygomaxillary, (0, 1), (9.0, 52.0), (-45.0, 6.5), step, keep=lambda x, y: (y < 1.0) | (x < 30.0))))
    return W


# =================================== the thin bones, marked off by their own shapes ===================================
def window(lo, h, shape, a, b):
    sl = tuple(slice(max(int(np.floor((a[k] - lo[k]) / h)), 0), min(int(np.ceil((b[k] - lo[k]) / h)) + 1, shape[k])) for k in range(3))
    return sl, np.ix_(*(lo[k] + h * np.arange(sl[k].start, sl[k].stop) for k in range(3)))


def inside(M, reg, u, v):
    return M.sample(reg, *np.broadcast_arrays(u, v)) < 0


def paints(D, lo, h, ctx, log=print):
    """A volume with the thin bones written in (0 elsewhere)."""
    paint = np.zeros(D.shape, np.uint8)
    said = []

    def put(name, a, b, test):
        sl, (X, Y, Z) = window(lo, h, D.shape, a, b)
        m = np.broadcast_to(test(X, Y, Z), paint[sl].shape) & (np.asarray(D[sl]) < 0)
        paint[sl][m] = ID[name]
        said.append("%s %.1f" % (name, m.sum() * h ** 3 / 1000.0))

    P = ctx["palate"]
    # the orbit's outer wall behind the sphenozygomatic suture is the sphenoid's orbital plate, up to the plane under the frontal bone
    bar = sdf.Tube(spline(np.array(BAR, float), 2), [(0, 17.0), (1, 10)], 2.6, up=(0, 1, 0), n=3)
    _, _, yf = frontal_plane(np.array(ctx["sutures"]["sphenofrontal"][-1], float))
    def plate(X, Y, Z):
        ax = np.abs(X)
        d = np.minimum.reduce([bar.segment(i, ax, Y, Z) for i in range(len(bar.P) - 1)])
        return (d < 0.6) & ((ax - SZ[0][0]) * SZ[1][0] + (Z - SZ[0][1]) * SZ[1][1] < 0) & (Y < yf(ax, Z)) & (Z > 46.0)
    put("sphenoid", (-56, -3, 44), (56, 34, 70), plate)
    # the upper jaw's tuberosity (the pyramidal process, put in after it, takes its hind inner corner)
    put("maxilla", (-33, -42, 38), (33, -27, 50), lambda X, Y, Z: Ellipsoid((25.4, -34.6, 44.5), (5.8, 6.1, 4.5))(np.abs(X), Y, Z) < 0)
    put("maxilla", (-33, -38, 39), (33, -10, 52), lambda X, Y, Z: Ellipsoid((26.2, -24.0, 45.6), (5.7, 12.7, 5.0))(np.abs(X), Y, Z) < 0)   # the swelling above it, up the jaw's back
    # the palatine bone's level plate: the hard palate behind the suture across, as far out as the groove by the tooth-bearing process
    hind = [(16.6, 41.2), (15.6, 43.0), (14.5, 44.2), (11.5, 45.0), (8.0, 45.3), (5.0, 44.9), (2.9, 44.2), (1.6, 43.3), (0.7, 42.5), (0.0, 42.2)]
    poly = np.vstack([np.asarray(P["cross"], float), [(16.6, 46.3), (17.2, 43.5)], np.array(hind) - (0, 0.9), [(-0.5, 41.3), (-0.5, 56.1)]])
    Mp = Map(-1.0, 19.0, 39.0, 58.0, 0.25); reg = Mp.region(poly)
    put("palatine", (-19, -39.5, 39), (19, -24.0, 58), lambda X, Y, Z: inside(Mp, reg, np.abs(X), Z) & (Y < P["M"].sample(P["NF"], *np.broadcast_arrays(np.abs(X), Z)) + 0.6))
    put("palatine", (-26, -41, 37), (26, -30, 45), lambda X, Y, Z: Ellipsoid(pterygoid.PYRAMID[0], tuple(r + 0.4 for r in pterygoid.PYRAMID[1]), sdf.rot((0, 1, 0), 28.0))(np.abs(X), Y, Z) < 0)   # pyramidal process (the wedge pterygoid.py adds)
    side = ctx.get("sidewall")
    if side is not None and side[1] is not None:
        Mw, xw = side
        def perp(X, Y, Z):                                     # its upright plate: the hind part of the nose's side wall
            w = Mw.sample(xw, *np.broadcast_arrays(Z, Y))
            return (np.abs(X) > w - 0.6) & (np.abs(X) < w + 2.4) & (Y > -30.0) & (Y < -5.0)
        put("palatine", (-24, -30, 44), (24, -5, 51), perp)       # (behind z 44 the side wall is the sphenoid's inner pterygoid plate)
    # the lacrimal bone: a thin plate of the orbit's inner wall, behind the upper jaw's frontal process
    sl, (X, Y, Z) = window(lo, h, D.shape, (6, 4, 78), (26, 21, 90))
    ins = np.asarray(D[sl]) < 0
    k = ins.shape[0] - 1 - np.argmax(ins[::-1], axis=0)        # the first bone met going inward from the orbit
    xm = np.where(ins.any(0), X.ravel()[k], np.nan)
    Ml = Map(78.0, 90.0, 4.0, 21.0, 0.25)
    # (four-sided, taller than wide, no border straight: the upper jaw's frontal process in front, the ethmoid's plate behind)
    regl = Ml.region(spline(np.array([(79.7, 7.6), (80.3, 5.9), (82.6, 5.3), (85.6, 5.9), (88.1, 6.7), (88.8, 10.0), (88.2, 14.0), (88.9, 17.4), (87.5, 19.3),
                                      (84.0, 19.9), (81.1, 19.2), (79.9, 16.0), (79.3, 12.0)]), 0.5, closed=True))
    ys, zs = Y.ravel(), Z.ravel()
    def lacrimal(X, Y, Z):
        j = np.clip(np.round((Y - ys[0]) / h).astype(int), 0, len(ys) - 1); kk = np.clip(np.round((Z - zs[0]) / h).astype(int), 0, len(zs) - 1)
        w = xm[j[0, :, 0]][:, kk[0, 0, :]][None]
        return (np.abs(X) > w - 2.6) & (np.abs(X) < w + 0.6) & inside(Ml, regl, Z, Y)
    put("lacrimal", (-26, 4, 78), (26, 21, 90), lacrimal)
    # the nasal bones: the bridge of the nose, from the frontal bone down to the opening's upper rim, a thin plate
    sl, (X, Y, Z) = window(lo, h, D.shape, (-12, -2, 86), (12, 25, 112))
    ins = np.asarray(D[sl]) < 0
    k = ins.shape[2] - 1 - np.argmax(ins[:, :, ::-1], axis=2)
    zf = np.where(ins.any(2), Z.ravel()[k], -1e3)[:, :, None]
    put("nasal bone", (-12, -2, 86), (12, 25, 112), lambda X, Y, Z: (np.abs(X) < x_nasomaxillary(Y))
        & (Y < y_frontonasal(X)) & (Y > -1.5) & (Z > np.maximum(zf - 4.5, 89.0)))
    # the scrolls on the nose's side wall: the inferior concha is a bone of its own, the middle one is the ethmoid's
    for name, slab in (ctx.get("conchae") or {}).items():
        def scroll(X, Y, Z, slab=slab):
            w = side[0].sample(side[1], *np.broadcast_arrays(Z, Y))
            return (slab(X, Y, Z) < 0.3) & (np.abs(X) < w + 0.3)
        put("inferior nasal concha" if "inferior" in name else "ethmoid", (-27, -31, 39), (27, 11, 97), scroll)
        if "middle" in name:
            # the middle scroll is the ethmoid's own: the strip of the side wall it hangs from, up to the ethmoid's block, goes with it
            # (without it the scroll hung from the upper jaw's bone and came out as a loose piece of the ethmoid)
            top = np.array(nose.MIDDLE["top"], float); top = top[np.argsort(top[:, 0])]
            def stem(X, Y, Z, top=top):
                w = side[0].sample(side[1], *np.broadcast_arrays(Z, Y))
                return (np.abs(X) > w - 0.4) & (np.abs(X) < w + 2.4) & (Y > np.interp(Z, top[:, 0], top[:, 1]) - 1.0) & (Y < 8.0) & (Z > top[0, 0]) & (Z < top[-1, 0])
            put("ethmoid", (-27, -6, 44), (27, 9, 80), stem)
    # the partition: the vomer below and behind, the ethmoid's plate above and in front
    sep = ctx.get("septum")
    if sep is not None:
        Ms = Map(25.0, 110.0, -34.0, 18.0, 0.5)
        rv, rp = Ms.region(np.array(VOMER)), Ms.region(np.array(PLATE))
        put("ethmoid", (-6, -34, 30), (6, 9, 110), lambda X, Y, Z: (sep(X, Y, Z) < 0.35) & inside(Ms, rp, Z, Y))
        # (it stands on the crest of the nose's floor: the palate under it, down to the mouth, is the upper jaws' and the palatine bones')
        # (its wings under the sphenoid's body are the same sheet spread out: nose.septum)
        put("vomer", (-7, -29.6, 26), (7, 18, 110), lambda X, Y, Z: (sep(X, Y, Z) < 0.35) & inside(Ms, rv, Z, Y)
            & ((Y > P["M"].sample(P["NF"], *np.broadcast_arrays(0 * Z, Z)) - 0.3) | (Z < 42.0)))
    log("bones marked off by their shapes (cm3): " + ", ".join(said))
    return paint


# =================================== naming what lies between the walls ===================================
def route(mask, a, b, lo, h):
    """The shortest way through a piece of bone from voxel a to voxel b: points (mm) along it."""
    n = int(mask.sum()); idx = -np.ones(mask.shape, np.int64); idx[mask] = np.arange(n)
    I, J = [], []
    for ax in range(3):
        s0 = [slice(None)] * 3; s1 = [slice(None)] * 3; s0[ax] = slice(0, -1); s1[ax] = slice(1, None)
        p, q = idx[tuple(s0)].ravel(), idx[tuple(s1)].ravel(); ok = (p >= 0) & (q >= 0)
        I.append(p[ok]); J.append(q[ok])
    I, J = np.concatenate(I), np.concatenate(J)
    G = sparse.coo_matrix((np.ones(len(I), np.int8), (I, J)), shape=(n, n)).tocsr()
    order, pred = sparse.csgraph.breadth_first_order(G, int(idx[tuple(a)]), directed=False)
    k = int(idx[tuple(b)]); path = [k]
    while pred[k] >= 0:
        k = int(pred[k]); path.append(k)
    pts = np.argwhere(mask)[path] * h + lo
    return pts[::-1]


def label(D, lo, h, ctx, log=print):
    """Every voxel of bone given its bone's number (ID). Returns (labels, problems): problems are leaks and bone left unnamed."""
    lo = np.asarray(lo, float); step = min(0.25, 0.45 * h); shape = np.array(D.shape)
    bone = np.asarray(D) < 0
    wall = np.zeros(D.shape, bool)
    names = []
    for name, P in walls(D, lo, h, ctx, step):
        names.append(name)
        for sgn in (1.0, -1.0):
            ijk = np.round((P * np.array([sgn, 1.0, 1.0]) - lo) / h).astype(int)
            ok = np.all((ijk >= 0) & (ijk < shape), axis=1)
            wall[tuple(ijk[ok].T)] = True
    # A wall is about 3 mm thick whatever the grid (what it takes is given back to the nearer bone at the end, so the
    # boundary still lies on the suture). One cell either side was enough at 1 mm; at 0.5 mm it left slits where two walls
    # meet (the frontal bone ran through one into the sphenoid, the cheek bone into the upper jaw).
    wall = ndimage.binary_dilation(wall, ndimage.generate_binary_structure(3, 1), iterations=max(1, int(round(1.0 / h))))
    paint = paints(D, lo, h, ctx, log)
    free = bone & ~wall & (paint == 0)
    comp, n = ndimage.label(free)
    owner = np.zeros(n + 1, np.uint8); first = {}
    problems = []
    r = int(np.ceil(6.0 / h))
    for name, pts in SEEDS.items():
        for p in pts:
            for sgn in ((1.0, -1.0) if abs(p[0]) > 1e-6 else (1.0,)):
                q = np.array([sgn * p[0], p[1], p[2]], float)
                c0 = np.round((q - lo) / h).astype(int)
                a = np.maximum(c0 - r, 0); b = np.minimum(c0 + r + 1, shape)
                sub = comp[a[0]:b[0], a[1]:b[1], a[2]:b[2]]
                cand = np.argwhere(sub > 0)
                if not len(cand):
                    problems.append("no bone within 6 mm of the point for %s at %s" % (name, q.tolist())); continue
                v = cand[np.argmin(((cand + a - c0) ** 2).sum(1))] + a
                c = int(comp[tuple(v)])
                if owner[c] not in (0, ID[name]):
                    other = BONES[owner[c] - 1]
                    way = route(comp == c, first[c], v, lo, h)
                    problems.append("leak: %s and %s are one piece. The way from %s's point to %s's: %s" % (
                        other, name, other, name, "; ".join("(%.0f, %.0f, %.0f)" % tuple(w) for w in way[::max(int(6.0 / h), 1)])))
                    continue
                if owner[c] == 0:
                    owner[c] = ID[name]; first[c] = v
    lab = owner[comp]
    lab[paint > 0] = paint[paint > 0]
    size = np.bincount(comp.ravel(), minlength=n + 1) * h ** 3
    loose = [c for c in range(1, n + 1) if owner[c] == 0 and size[c] > 40.0]
    if loose:
        cen = ndimage.center_of_mass(free, comp, loose)
        for c, m in sorted(zip(loose, cen), key=lambda t: -size[t[0]])[:12]:
            problems.append("a piece of %.2f cm3 round (%.0f, %.0f, %.0f) has no bone's point in it (given to the nearest bone)" % (
                size[c] / 1000.0, *(np.array(m) * h + lo)))
    idx = ndimage.distance_transform_edt(lab == 0, return_distances=False, return_indices=True)
    todo = bone & (lab == 0)
    lab[todo] = lab[idx[0][todo], idx[1][todo], idx[2][todo]]
    del idx
    lab[~bone] = 0
    log("bones: %d walls, %d pieces of bone between them, %d problems" % (len(names), n, len(problems)))
    for p in problems:
        log("  " + p)
    return lab, problems


def sides(lab, lo, h, ctx):
    """Paired bones told left from right. Returns (numbered volume, the parts' names in number order)."""
    out = np.zeros(lab.shape, np.uint8); parts = []
    x = (lo[0] + h * np.arange(lab.shape[0]))[:, None, None]
    Y, Z = np.meshgrid(lo[1] + h * np.arange(lab.shape[1]), lo[2] + h * np.arange(lab.shape[2]), indexing="ij")
    from scipy.spatial import cKDTree
    for name in BONES:
        m = lab == ID[name]
        if not m.any():
            continue
        if name not in PAIRED:
            parts.append(name); out[m] = len(parts); continue
        off = 0.0
        line = ctx["midlines"].get(MIDLINE.get(name, ""))
        if line is not None:
            L = spline(np.asarray(line, float), 0.2)
            d, i = cKDTree(L[:, 1:]).query(np.column_stack([Y.ravel(), Z.ravel()]), distance_upper_bound=20.0)
            off = np.where(np.isfinite(d), L[np.minimum(i, len(L) - 1), 0], 0.0).reshape(Y.shape)[None]
            off = off * smoothstep((16.0 - np.where(np.isfinite(d), d, 99.0).reshape(Y.shape)[None]) / 8.0)
        left = x > off
        parts.append(name + ", left"); out[m & left] = len(parts)
        parts.append(name + ", right"); out[m & ~left] = len(parts)
    return out, parts


def meshes(D, lo, h, lab2, parts, gap=0.1, rounds=6, log=print):
    """Each bone as a closed mesh of its own: the skull's own surface outside, the suture walls where it meets its neighbours
    (each drawn back by half of `gap`, so that nothing lies inside anything). Returns {name: (v, f)}."""
    lo = np.asarray(lo, float); out = {}
    objs = ndimage.find_objects(lab2, max_label=len(parts))
    for k, name in enumerate(parts, 1):
        if objs[k - 1] is None:
            continue
        sl = tuple(slice(max(s.start - 5, 0), min(s.stop + 5, n)) for s, n in zip(objs[k - 1], lab2.shape))
        L = lab2[sl]; own = L == k; other = (L != 0) & ~own
        E = ndimage.distance_transform_edt(~own)
        if other.any():
            E -= ndimage.distance_transform_edt(~other)
        else:
            E -= 1e3
        E = ndimage.gaussian_filter(E.astype(np.float32), 0.7) * (0.5 * h)
        Db = np.maximum(np.asarray(D[sl], np.float32), E + 0.5 * gap)
        Db = np.pad(Db, 1, constant_values=1.0)
        v, f = sdf.mesh(Db, lo + h * (np.array([s.start for s in sl]) - 1), h)
        pieces = sdf.components(v, f)
        keep = [p for p in pieces if len(p[1]) >= max(40, 0.004 * len(pieces[0][1]))]
        nv = np.cumsum([0] + [len(p[0]) for p in keep[:-1]])
        v = np.concatenate([p[0] for p in keep]); f = np.concatenate([p[1] + o for p, o in zip(keep, nv)])
        v = sdf.taubin(v, f, rounds)
        out[name] = (v, f)
        log("  %-28s %7.2f cm3, %7d faces, %d piece(s)%s" % (name, own.sum() * h ** 3 / 1000.0, len(f), len(keep),
                                                            (", %d crumbs dropped" % (len(pieces) - len(keep))) if len(pieces) > len(keep) else ""))
    return out


def split(D, lo, h, ctx, gap=0.1, log=print):
    """The whole job: (meshes by name, numbered volume, names, problems)."""
    lab, problems = label(D, lo, h, ctx, log)
    lab2, parts = sides(lab, np.asarray(lo, float), h, ctx)
    return meshes(D, lo, h, lab2, parts, gap, log=log), lab2, parts, problems
