"""sdf.py: shapes made from nothing but numbers.

Every bone of the from-scratch body is a signed-distance field: smooth unions and cuts of simple
solids placed on landmarks, sampled on a grid and meshed with marching cubes. Nothing is imported:
no mesh, no scan, no label. Units here are millimetres (the bones are written in metres).
Frame: x = the body's left, y up, z forward.
"""
import numpy as np
from scipy import ndimage, sparse
from skimage import measure

BIG = 1.0e3


def smin(a, b, k):
    """Smooth union: the smaller of two distances, rounded over k mm where they meet."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def rot(axis, deg):
    """Rotation matrix about an axis by degrees (right-handed)."""
    a = unit(axis); t = np.radians(deg); c, s = np.cos(t), np.sin(t)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + s * K + (1 - c) * (K @ K)


def spline(P, step=2.0, closed=False):
    """A smooth line through the points P (centripetal Catmull-Rom), resampled about every `step` mm."""
    P = np.asarray(P, float)
    if len(P) < 3:
        n = max(int(np.linalg.norm(P[-1] - P[0]) / step), 1)
        return np.linspace(P[0], P[-1], n + 1)
    Q = np.concatenate([P[-1:], P, P[:2]]) if closed else np.concatenate([2 * P[:1] - P[1:2], P, 2 * P[-1:] - P[-2:-1]])
    out = []
    for i in range(1, len(Q) - 2):
        p0, p1, p2, p3 = Q[i - 1], Q[i], Q[i + 1], Q[i + 2]
        n = max(int(np.linalg.norm(p2 - p1) / step), 1)
        t = np.linspace(0, 1, n, endpoint=False)[:, None]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[:1] if closed else P[-1:])
    return np.concatenate(out)


def along(P, values):
    """Values given at the ends (or at fractions of the length) spread along the line P.
    values: a number, (start, end), or [(fraction, value), ...]."""
    P = np.asarray(P, float)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    u = d / max(d[-1], 1e-9)
    if np.isscalar(values):
        return np.full(len(P), float(values))
    values = list(values)
    if np.isscalar(values[0]):
        return np.interp(u, np.linspace(0, 1, len(values)), values)
    f, v = zip(*values)
    return np.interp(u, f, v)


class Ellipsoid:
    def __init__(self, c, r, R=None):
        self.c = np.asarray(c, float); self.r = np.asarray(r, float)
        self.R = np.eye(3) if R is None else np.asarray(R, float)       # columns: the solid's own axes
        e = np.abs(self.R) @ self.r
        self.bounds = (self.c - e, self.c + e)

    def __call__(self, X, Y, Z):
        dx, dy, dz = X - self.c[0], Y - self.c[1], Z - self.c[2]
        R, r = self.R, self.r
        q = [R[0, j] * dx + R[1, j] * dy + R[2, j] * dz for j in range(3)]
        k0 = np.sqrt((q[0] / r[0]) ** 2 + (q[1] / r[1]) ** 2 + (q[2] / r[2]) ** 2)
        k1 = np.sqrt((q[0] / r[0] ** 2) ** 2 + (q[1] / r[1] ** 2) ** 2 + (q[2] / r[2] ** 2) ** 2)
        return np.where(k1 > 1e-9, k0 * (k0 - 1.0) / np.maximum(k1, 1e-9), -r.min()).astype(np.float32)


class Box:
    """A box with rounded edges: half sizes `half`, edge rounding `round`."""
    def __init__(self, c, half, round=1.0, R=None):
        self.c = np.asarray(c, float); self.half = np.asarray(half, float); self.round = round
        self.R = np.eye(3) if R is None else np.asarray(R, float)
        e = np.abs(self.R) @ self.half
        self.bounds = (self.c - e, self.c + e)

    def __call__(self, X, Y, Z):
        dx, dy, dz = X - self.c[0], Y - self.c[1], Z - self.c[2]
        R = self.R
        q = [np.abs(R[0, j] * dx + R[1, j] * dy + R[2, j] * dz) - (self.half[j] - self.round) for j in range(3)]
        out = np.sqrt(np.maximum(q[0], 0) ** 2 + np.maximum(q[1], 0) ** 2 + np.maximum(q[2], 0) ** 2)
        ins = np.minimum(np.maximum(q[0], np.maximum(q[1], q[2])), 0)
        return (out + ins - self.round).astype(np.float32)


class Tube:
    """A solid swept along a line: at each point an oval `a` (along `up`) by `b` (across), power `n`
    (2 = oval, more = squarer). `taper` thins the section toward +up (0 = none). Round ends."""
    def __init__(self, P, a, b=None, up=(0, 1, 0), n=2.0, taper=0.0, true=False):
        # true: for a squared-off section (n > 2), measure the distance as it is in every direction. Without it the distance is
        # counted in the section's small half-width, so beyond the long side of a flat tube it reads several times too small and a
        # rounded join (Field.add with k) swells the bone far above and below the tube, up to the edge of the block it is worked in.
        self.true = true
        self.P = np.asarray(P, float)
        m = len(self.P)
        self.a = along(self.P, a); self.b = self.a.copy() if b is None else along(self.P, b)
        up = np.asarray(up, float)
        self.up = np.tile(up, (m, 1)) if up.ndim == 1 else up
        self.n = n; self.taper = along(self.P, taper)
        r = np.maximum(self.a, self.b).max()
        self.bounds = (self.P.min(0) - r, self.P.max(0) + r)

    def segment(self, i, X, Y, Z):
        p0, p1 = self.P[i], self.P[i + 1]
        e = p1 - p0; L = np.linalg.norm(e); e = e / max(L, 1e-9)
        u = self.up[i] + self.up[i + 1]; u = u - (u @ e) * e
        if np.linalg.norm(u) < 1e-6:
            u = np.cross(e, [1.0, 0, 0])
        u = u / np.linalg.norm(u); w = np.cross(e, u)
        dx, dy, dz = X - p0[0], Y - p0[1], Z - p0[2]
        s = dx * e[0] + dy * e[1] + dz * e[2]
        t = np.clip(s / max(L, 1e-9), 0, 1)
        qe = s - t * L
        qu = dx * u[0] + dy * u[1] + dz * u[2]
        qw = dx * w[0] + dy * w[1] + dz * w[2]
        a = self.a[i] + (self.a[i + 1] - self.a[i]) * t
        b = self.b[i] + (self.b[i + 1] - self.b[i]) * t
        tp = self.taper[i] + (self.taper[i + 1] - self.taper[i]) * t
        if np.any(self.taper != 0):
            b = b * (1.0 - tp * np.clip(qu / a, -1, 1))
        c = np.minimum(a, b)
        n = self.n
        if n == 2.0:
            k0 = np.sqrt((qu / a) ** 2 + (qw / b) ** 2 + (qe / c) ** 2)
            k1 = np.sqrt((qu / a ** 2) ** 2 + (qw / b ** 2) ** 2 + (qe / c ** 2) ** 2)
            return np.where(k1 > 1e-9, k0 * (k0 - 1.0) / np.maximum(k1, 1e-9), -c)
        k0 = (np.abs(qu / a) ** n + np.abs(qw / b) ** n + np.abs(qe / c) ** n) ** (1.0 / n)
        if self.true:
            with np.errstate(divide="ignore", invalid="ignore"):
                g = k0 ** (1.0 - n) * np.sqrt((np.abs(qu / a) ** (n - 1.0) / a) ** 2 + (np.abs(qw / b) ** (n - 1.0) / b) ** 2 + (np.abs(qe / c) ** (n - 1.0) / c) ** 2)
            g = np.nan_to_num(g, nan=0.0, posinf=0.0)
            return np.where(g > 1e-6, (k0 - 1.0) / np.maximum(g, 1e-6), -c)
        return (k0 - 1.0) * c


class Field:
    """A block of space sampled every h mm. D < 0 inside the solid."""
    def __init__(self, lo, hi, h):
        self.h = float(h)
        self.lo = np.asarray(lo, float)
        self.n = np.ceil((np.asarray(hi, float) - self.lo) / h).astype(int) + 1
        self.ax = [(self.lo[k] + h * np.arange(self.n[k])).astype(np.float32) for k in range(3)]
        self.D = np.full(self.n, BIG, np.float32)

    def window(self, lo, hi):
        sl = []
        for k in range(3):
            a = max(int(np.floor((lo[k] - self.lo[k]) / self.h)), 0)
            b = min(int(np.ceil((hi[k] - self.lo[k]) / self.h)) + 1, int(self.n[k]))
            if b <= a:
                return None
            sl.append(slice(a, b))
        return tuple(sl)

    def coords(self, sl):
        return np.ix_(self.ax[0][sl[0]], self.ax[1][sl[1]], self.ax[2][sl[2]])

    def dist(self, prim, margin):
        """The solid's distance on the part of the grid it can matter in: (window, distances)."""
        lo, hi = prim.bounds
        sl = self.window(np.asarray(lo) - margin, np.asarray(hi) + margin)
        if sl is None:
            return None, None
        if isinstance(prim, Tube):
            d = np.full([s.stop - s.start for s in sl], BIG, np.float32)
            base = [s.start for s in sl]
            for i in range(len(prim.P) - 1):
                r = max(prim.a[i], prim.a[i + 1], prim.b[i], prim.b[i + 1])
                p0, p1 = prim.P[i], prim.P[i + 1]
                s2 = self.window(np.minimum(p0, p1) - r - margin, np.maximum(p0, p1) + r + margin)
                if s2 is None:
                    continue
                X, Y, Z = self.coords(s2)
                loc = tuple(slice(s2[k].start - base[k], s2[k].stop - base[k]) for k in range(3))
                d[loc] = np.minimum(d[loc], prim.segment(i, X, Y, Z).astype(np.float32))
            return sl, d
        X, Y, Z = self.coords(sl)
        return sl, prim(X, Y, Z)

    def add(self, prim, k=0.0, keep=12.0):
        sl, d = self.dist(prim, max(k, keep) + 2.0)
        if sl is not None:
            self.D[sl] = smin(self.D[sl], d, k)
        return self

    def cut(self, prim, k=0.0):
        sl, d = self.dist(prim, k + 2.0)
        if sl is not None:
            self.D[sl] = smax(self.D[sl], -d, k)
        return self

    def ease(self, centre, radius, sigma=0.6):
        """Round what is too sharp for the grid to hold (a lip thinner than a cell meshes as a row of teeth): the field smoothed
        over `sigma` mm inside a ball, in full out to 0.6 of its radius and fading to nothing at its edge."""
        from scipy import ndimage
        c = np.asarray(centre, float); m = radius + 3 * sigma
        sl = self.window(c - m, c + m)
        if sl is None:
            return self
        A = self.D[sl].astype(np.float32)
        G = ndimage.gaussian_filter(np.clip(A, -20, 20), sigma / self.h, mode="nearest")
        X, Y, Z = self.coords(sl)
        w = np.clip((radius - np.sqrt((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2)) / (0.4 * radius), 0, 1); w = w * w * (3 - 2 * w)
        self.D[sl] = np.where(np.abs(A) < 15, A * (1 - w) + G * w, A)
        return self

    def keep_inside(self, prim, k=0.0):
        """Keep only what lies inside the solid (intersection), in the solid's own neighbourhood."""
        sl, d = self.dist(prim, k + 2.0)
        if sl is not None:
            self.D[sl] = smax(self.D[sl], d, k)
        return self


def ease_midline(F, width=2.5, sigma=0.8):
    """A half computed for x >= 0 can meet its mirror at a slight angle: a crease down the midline. Smooth the
    field across the midline (strongest on it, fading out by `width` mm) so that the two halves meet level."""
    from scipy import ndimage
    n = min(int(np.ceil((width + 3 * sigma) / F.h)) + 1, int(F.n[0]))
    A = F.D[:n]
    G = ndimage.gaussian_filter1d(np.clip(A, -20, 20), sigma / F.h, axis=0, mode="mirror")
    w = np.clip(1 - F.ax[0][:n] / width, 0, 1); w = (w * w * (3 - 2 * w))[:, None, None]
    F.D[:n] = np.where(np.abs(A) < 15, A * (1 - w) + G * w, A)
    return F


def mirror_field(D):
    """A field computed for x >= 0 (first sample at x = 0) made whole: the right half is the left's mirror."""
    return np.concatenate([D[:0:-1], D], axis=0)


def mesh(D, lo, h, level=0.0):
    v, f, _, _ = measure.marching_cubes(D, level, spacing=(h, h, h))
    return v + np.asarray(lo, float), f.astype(np.int64)


def components(v, f):
    """Connected pieces of a mesh, largest first: [(vertices, faces)]."""
    n = len(v)
    A = sparse.coo_matrix((np.ones(len(f) * 3), (np.concatenate([f[:, 0], f[:, 1], f[:, 2]]),
                                                 np.concatenate([f[:, 1], f[:, 2], f[:, 0]]))), shape=(n, n))
    k, lab = sparse.csgraph.connected_components(A, directed=False)
    out = []
    for c in np.argsort(-np.bincount(lab)):
        keep = lab[f[:, 0]] == c
        ff = f[keep]; used = np.unique(ff)
        if len(ff) == 0:
            continue
        re = -np.ones(n, np.int64); re[used] = np.arange(len(used))
        out.append((v[used], re[ff]))
    return out


def taubin(v, f, rounds=8, lam=0.5, mu=-0.53):
    """Smoothing that does not shrink (Taubin): takes the grid's stair-steps off."""
    n = len(v)
    i = np.concatenate([f[:, 0], f[:, 1], f[:, 2], f[:, 1], f[:, 2], f[:, 0]])
    j = np.concatenate([f[:, 1], f[:, 2], f[:, 0], f[:, 0], f[:, 1], f[:, 2]])
    A = sparse.coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(1)).ravel(); deg[deg == 0] = 1
    W = sparse.diags(1.0 / deg) @ A
    v = v.copy()
    for _ in range(rounds):
        v += lam * (W @ v - v)
        v += mu * (W @ v - v)
    return v


def simplify(v, f, target):
    import fast_simplification
    if len(f) <= target:
        return v, f
    v2, f2 = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_count=int(target), agg=5)
    return np.asarray(v2, float), np.asarray(f2, np.int64)


def report(v, f):
    """Is the mesh closed and clean? A dict of plain facts."""
    import trimesh
    m = trimesh.Trimesh(v, f, process=False)
    e = np.sort(m.edges, axis=1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    return {"triangles": int(len(f)), "closed": bool(m.is_watertight), "edges_not_shared_by_two": int((cnt != 2).sum()),
            "pieces": int(len(components(v, f))), "volume_cm3": round(float(abs(m.volume)) / 1000.0, 2),
            "bounds_mm": [np.round(v.min(0), 1).tolist(), np.round(v.max(0), 1).tolist()]}


def closed(v, f):
    """Every edge shared by exactly two triangles."""
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    return bool((cnt == 2).all())


def finish(D, lo, h, target, rounds=8, least=200):
    """Field to finished mesh: marching cubes, drop crumbs, smooth, simplify (retried at nearby sizes until the
    result is closed). Returns the fine mesh, the final mesh and the number of pieces the field had;
    finish.dropped lists the crumbs left out as (triangles, centre)."""
    v, f = mesh(D, lo, h)
    allparts = components(v, f)
    parts = [p for p in allparts if len(p[1]) >= least]
    finish.dropped = [(int(len(p[1])), np.round(p[0].mean(0), 1).tolist()) for p in allparts[1:]]
    v, f = parts[0]
    v = taubin(v, f, rounds)
    fine = (v, f)
    best = None
    for t in [int(target * k) for k in (1, 1.03, 0.96, 1.08, 0.9, 1.01, 0.98, 1.05, 0.93, 1.12, 0.87, 1.15)]:
        v2, f2 = simplify(v, f, t)
        if best is None:
            best = (v2, f2)
        if closed(v2, f2):
            best = (v2, f2)
            break
    return fine, best, len(parts)


class Plate:
    """A flat plate with a drawn outline: the outline (s, t) lies in the plane through `origin` spanned by
    the unit vectors es and et; `half` is half the thickness, `round` the rounding of the rim."""
    def __init__(self, outline, origin, es, et, half, round=1.5):
        self.o = np.asarray(origin, float); self.es = unit(es); self.et = unit(et)
        self.en = np.cross(self.es, self.et)
        self.Q = np.asarray(outline, float); self.half = half; self.round = min(round, half)
        c = [self.o + s * self.es + t * self.et for s, t in self.Q]
        c = np.array(c); e = half * np.abs(self.en)
        self.bounds = (c.min(0) - e, c.max(0) + e)

    def outline_distance(self, S, T):
        """Signed distance in the plane to the outline (negative inside)."""
        Q = self.Q; n = len(Q)
        d2 = np.full(S.shape, 1e18); inside = np.zeros(S.shape, bool)
        for i in range(n):
            a, b = Q[i], Q[(i + 1) % n]
            ex, ey = b[0] - a[0], b[1] - a[1]
            wx, wy = S - a[0], T - a[1]
            h = np.clip((wx * ex + wy * ey) / max(ex * ex + ey * ey, 1e-12), 0, 1)
            d2 = np.minimum(d2, (wx - ex * h) ** 2 + (wy - ey * h) ** 2)
            c1 = (a[1] <= T) & (b[1] > T) & (ex * wy - ey * wx > 0)
            c2 = (a[1] > T) & (b[1] <= T) & (ex * wy - ey * wx < 0)
            inside ^= (c1 | c2)
        return np.where(inside, -1.0, 1.0) * np.sqrt(d2)

    def __call__(self, X, Y, Z):
        dx, dy, dz = np.broadcast_arrays(X - self.o[0], Y - self.o[1], Z - self.o[2])
        S = dx * self.es[0] + dy * self.es[1] + dz * self.es[2]
        T = dx * self.et[0] + dy * self.et[1] + dz * self.et[2]
        N = dx * self.en[0] + dy * self.en[1] + dz * self.en[2]
        r = self.round
        a = self.outline_distance(S, T) + r
        b = np.abs(N) - (self.half - r)
        return (np.sqrt(np.maximum(a, 0) ** 2 + np.maximum(b, 0) ** 2) + np.minimum(np.maximum(a, b), 0) - r).astype(np.float32)


def sample_field(D, lo, h, P):
    """The field's value at points P (mm), by linear interpolation; +BIG outside the block."""
    idx = ((np.asarray(P, float) - np.asarray(lo, float)) / h).T
    return ndimage.map_coordinates(D, idx, order=1, mode="constant", cval=BIG)


class Sweep:
    """A solid swept along a line with a traced cross-section that changes along it.

    C: the centre line (m, 3), closely spaced; up: the section's own up direction at each point (m, 3);
    outlines: (m, K, 2) the closed outline of the section at each point as (out, up) in mm, where
    out = tangent x up (so with the line running back along the left side of an arch, +out is the cheek).
    Each outline must be star-shaped about (0, 0). Flat, slightly rounded ends."""
    def __init__(self, C, up, outlines, na=180):
        from scipy.spatial import cKDTree
        C = np.asarray(C, float); up = np.asarray(up, float); O = np.asarray(outlines, float)
        e = np.gradient(C, axis=0); e /= np.linalg.norm(e, axis=1)[:, None]
        u = up - (up * e).sum(1)[:, None] * e; u /= np.linalg.norm(u, axis=1)[:, None]
        w = np.cross(e, u)
        ang = (np.arange(na) + 0.0) * 2 * np.pi / na
        R = np.zeros((len(C), na))
        for i in range(len(C)):
            th = np.arctan2(O[i, :, 1], O[i, :, 0]); r = np.hypot(O[i, :, 0], O[i, :, 1])
            k = np.argsort(th)
            R[i] = np.interp(ang, th[k] % (2 * np.pi), r[k], period=2 * np.pi)
        # twice as many stations, so the nearest one is never more than a fraction of a millimetre off
        t = np.arange(0, len(C) - 0.5, 0.5); i0 = np.floor(t).astype(int); i1 = np.minimum(i0 + 1, len(C) - 1); fr = (t - i0)[:, None]
        mix = lambda A: A[i0] * (1 - fr) + A[i1] * fr
        self.C = mix(C); self.e = mix(e); self.u = mix(u); self.w = mix(w); self.R = mix(R).astype(np.float32)
        for A in (self.e, self.u, self.w):
            A /= np.linalg.norm(A, axis=1)[:, None]
        dR = (np.roll(self.R, -1, axis=1) - np.roll(self.R, 1, axis=1)) / (2 * (2 * np.pi / na))
        self.fac = (self.R / np.sqrt(self.R ** 2 + dR ** 2)).astype(np.float32)
        self.na = na; self.tree = cKDTree(self.C)
        r = float(self.R.max())
        self.bounds = (self.C.min(0) - r, self.C.max(0) + r)

    def __call__(self, X, Y, Z):
        X, Y, Z = np.broadcast_arrays(X, Y, Z)
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1).astype(np.float64)
        out = np.empty(len(P), np.float32)
        last = len(self.C) - 1
        for s in range(0, len(P), 400000):
            p = P[s:s + 400000]
            j = self.tree.query(p, workers=2)[1]
            q = p - self.C[j]
            qe = (q * self.e[j]).sum(1); qu = (q * self.u[j]).sum(1); qw = (q * self.w[j]).sum(1)
            rho = np.hypot(qu, qw)
            a = (np.arctan2(qu, qw) % (2 * np.pi)) * (self.na / (2 * np.pi))
            a0 = np.floor(a).astype(int) % self.na; a1 = (a0 + 1) % self.na; fa = a - np.floor(a)
            r = self.R[j, a0] * (1 - fa) + self.R[j, a1] * fa
            d = (rho - r) * self.fac[j, a0]
            end = ((j == 0) & (qe < 0)) | ((j == last) & (qe > 0))
            d = np.where(end, np.where(d > 0, np.hypot(d, qe), np.maximum(d, np.abs(qe))), d)
            out[s:s + 400000] = d
        return out.reshape(X.shape)
