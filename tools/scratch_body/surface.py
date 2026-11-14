"""surface.py: the small unevenness of real bone, put on after the two halves are joined.

The skull is built as its left half and mirrored. Anything random built into the half comes out the same on both
sides, and the eye picks that out at once (a blot test, not a bone). So everything that is not anatomy but texture is
added here, on the whole head, where left and right get their own:

  grain     the surface is nowhere quite smooth: it rises and falls a few hundredths of a millimetre over a millimetre
            or two, more where muscles and ligaments take hold and on the palate, least on the joint surfaces
  pits      the small openings for vessels (and on the palate for glands): each its own size, none round
  midline   the sutures that run on the midline wander from side to side as real ones do

Where the bone is rough or pitted is given by zones in the head frame (mm): (name, centre, radii, grain, pits per mm2).
A zone with a negative grain smooths (a joint surface). `detail` (mm) is the finest thing the grid can carry: grain
finer than that would only be noise in the mesh.
"""
import numpy as np
from scipy import ndimage

ZONES = [
    # name, centre (x, y, z), radii, extra grain (mm), pits per mm2
    # (the palate's many small openings are a third of a millimetre across: pits the grid can carry, put as close as the real ones
    # stand, ran together into cracks. The few larger ones are pits here; the fine ones are for the surface's picture, not its shape)
    ("palate, maxilla's part", (0, -34, 72), (17, 9, 20), 0.06, 0.035),
    ("palate, palatine bone", (0, -30, 49), (15, 4, 7), 0.02, 0.012),
    ("alveolar process, upper", (0, -38, 74), (32, 8, 30), 0.03, 0.03),
    ("nuchal plane", (0, -18, -52), (52, 16, 28), 0.06, 0.008),    # (rough, but not pitted all over: at a pit every 20 mm2 it looked like kneaded clay)
    ("mastoid", (56, -12, -17), (10, 20, 14), 0.05, 0.003),      # (its small openings are finer than the grid: as pits they came out as craters)
    ("mastoid", (-56, -12, -17), (10, 20, 14), 0.05, 0.003),
    ("pterygoid plates", (22, -22, 37), (10, 16, 7), 0.04, 0.04),
    ("pterygoid plates", (-22, -22, 37), (10, 16, 7), 0.04, 0.04),
    ("under side of the cheek's arch", (60, -6, 44), (9, 5, 22), 0.05, 0.04),
    ("under side of the cheek's arch", (-60, -6, 44), (9, 5, 22), 0.05, 0.04),
    ("jaw socket", (50, -1, 10), (11, 5, 9), -0.035, -0.02),
    ("jaw socket", (-50, -1, 10), (11, 5, 9), -0.035, -0.02),
    ("occipital condyles", (0, -26, -6), (22, 5, 13), -0.03, -0.02),
]
BASE_GRAIN, BASE_PITS = 0.035, 0.0012        # on the smooth vault a pit the grid can carry is larger than a real one: few of them


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def zone_field(shape, lo, h, col, zones=ZONES, base=0.0):
    """One of the zones' numbers (col 3: grain, col 4: pits) as a field over the whole grid."""
    A = np.full(shape, base, np.float32)
    ax = [lo[k] + h * np.arange(shape[k]) for k in range(3)]
    for z in zones:
        c, r, val = np.array(z[1], float), np.array(z[2], float), z[col]
        sl = tuple(slice(max(int((c[k] - 1.3 * r[k] - lo[k]) / h), 0), min(int((c[k] + 1.3 * r[k] - lo[k]) / h) + 2, shape[k])) for k in range(3))
        if any(s.stop <= s.start for s in sl):
            continue
        X, Y, Z = np.ix_(*(ax[k][sl[k]] for k in range(3)))
        q = np.sqrt(((X - c[0]) / r[0]) ** 2 + ((Y - c[1]) / r[1]) ** 2 + ((Z - c[2]) / r[2]) ** 2)
        A[sl] += (val * smoothstep((1.2 - q) / 0.35)).astype(np.float32)
    return A


def noise(shape, rng, sigma):
    n = ndimage.gaussian_filter(rng.standard_normal(shape, dtype=np.float32), sigma, mode="wrap")
    return n / float(n[::3, ::3, ::3].std())


def roughen(D, lo, h, seed=1918, zones=ZONES, log=print):
    """Give the whole head's field D (mm, < 0 in bone) its grain and pits. Returns the new field."""
    rng = np.random.default_rng(seed)
    lo = np.asarray(lo, float)
    detail = max(2.2 * h, 0.55)
    G = np.maximum(zone_field(D.shape, lo, h, 3, zones, BASE_GRAIN), 0.008)
    N = (0.62 * noise(D.shape, rng, detail / h * 0.5) + 0.48 * noise(D.shape, rng, detail / h) + 0.42 * noise(D.shape, rng, 2.3 * detail / h)
         + 0.3 * noise(D.shape, rng, 5.0 * detail / h))
    near = np.abs(D) < 3.0
    # a thin plate keeps its thickness: the grain is weaker on it (how thin is read off a blurred field)
    thin = smoothstep((ndimage.gaussian_filter(D, 1.0 / h) - 0.15) / 0.2).astype(np.float32)      # 0 on a plate 2.4 mm thick, 1 on one of 1.2 mm
    D = D + np.where(near, G * N * (1.0 - 0.8 * thin), 0.0).astype(np.float32)
    del thin
    del N
    # ---- pits: at points of the surface, each a small hollow of its own size and shape
    Pd = np.maximum(zone_field(D.shape, lo, h, 4, zones, BASE_PITS), 0.0)
    surf = np.argwhere(np.abs(D) < 0.5 * h)
    area = len(surf) * h * h                                   # about one surface cell per h2 of surface
    want = Pd[surf[:, 0], surf[:, 1], surf[:, 2]] * h * h      # the chance that a surface cell carries a pit
    pick = surf[rng.uniform(size=len(surf)) < want]
    K = int(np.ceil(2.4 * 1.0 / h))
    off = np.arange(-K, K + 1) * h
    OX, OY, OZ = np.meshgrid(off, off, off, indexing="ij")
    n = np.array(D.shape)
    made = 0
    for a, b, c in pick:
        if a < K or b < K or c < K or a >= n[0] - K or b >= n[1] - K or c >= n[2] - K:
            continue
        # no pit in a thin plate (it would go through): the bone must be bone 1.5 mm in from the surface
        g = np.array([D[a + 1, b, c] - D[a - 1, b, c], D[a, b + 1, c] - D[a, b - 1, c], D[a, b, c + 1] - D[a, b, c - 1]], float)
        g /= max(np.linalg.norm(g), 1e-6)
        ia, ib, ic = (int(round(q)) for q in (a - g[0] * 1.5 / h, b - g[1] * 1.5 / h, c - g[2] * 1.5 / h))
        if D[ia, ib, ic] > -1.15:
            continue
        r = rng.uniform(0.34, 0.55) if rng.uniform() < 0.9 else rng.uniform(0.55, 0.8)
        r = max(r, 0.8 * h)
        dep = r * rng.uniform(0.5, 1.0)
        # a vessel's opening is seldom round: the vessel enters aslant, and its mouth is drawn out along the surface the way it runs
        v = rng.standard_normal(3); v -= (v @ g) * g; v /= max(np.linalg.norm(v), 1e-6)
        e = min(rng.uniform(1.0, 2.3), 1.05 / r)
        along = OX * v[0] + OY * v[1] + OZ * v[2]
        q = (OX ** 2 + OY ** 2 + OZ ** 2 - along ** 2) + along ** 2 / (e * e)
        D[a - K:a + K + 1, b - K:b + K + 1, c - K:c + K + 1] += (dep * np.exp(-q / (r * r))).astype(np.float32)
        made += 1
    log("surface: grain %.3f to %.3f mm (nothing finer than %.2f mm), %d pits on about %.0f cm2" % (float(G.min()), float(G.max()), detail, made, area / 100.0))
    return D


def teeth(s, wave, ph, ph2):
    """The sideways run of a toothed suture along its length s (mm), about -1.5 to 1.5: teeth of several lengths at once, their
    spacing and their depth both changing from place to place (no two teeth of a real suture are alike, and a plain sum of
    waves reads as a zip)."""
    warp = s + 1.2 * np.sin(2 * np.pi * s / 23.0 + ph2[0]) + 0.8 * np.sin(2 * np.pi * s / 13.7 + ph2[1])
    deep = 0.75 + 0.3 * np.sin(2 * np.pi * s / 19.0 + ph2[2]) + 0.2 * np.sin(2 * np.pi * s / 7.3 + ph2[3])
    return deep * sum(a * np.sin(2 * np.pi * warp / L + p) for a, L, p in zip((1.0, 0.8, 0.7, 0.45), wave, ph)) / 1.9


def wander_line(P, amp, rng, wave=(6.1, 3.4, 9.7, 2.3), drift=0.0, depth=None):
    """A line (N x 3) made to wander sideways (in x) by up to about amp mm, its ends kept: a suture on the midline.
    depth(u): how deep its teeth are at each place along it (u from 0 at its start to 1 at its end; 1 = amp).
    drift: how far the whole line strays from the middle plane besides (mm), over lengths of 4 to 7 cm."""
    P = np.asarray(P, float)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    ph = rng.uniform(0, 2 * np.pi, 4)
    if depth is None:
        w = sum(a * np.sin(2 * np.pi * s / L + p) for a, L, p in zip((1.0, 0.8, 0.7, 0.45), wave, ph)) / 1.9
    else:
        w = teeth(s, wave, ph, rng.uniform(0, 2 * np.pi, 4)) * depth(s / s[-1])
    end = np.minimum(s, s[-1] - s)
    Q = P.copy(); Q[:, 0] += amp * w * np.clip(end / 2.0, 0, 1)
    if drift:
        ph = rng.uniform(0, 2 * np.pi, 2)
        Q[:, 0] += drift * (np.sin(2 * np.pi * s / 71.0 + ph[0]) + 0.6 * np.sin(2 * np.pi * s / 43.0 + ph[1])) / 1.3 * np.clip(end / 14.0, 0, 1)
    return Q
