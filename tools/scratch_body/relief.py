"""relief.py: flat maps over a view, the way a plate is drawn, and solids made from them.

A Map is a grid over two head-frame axes (millimetres). On it live: a surface drawn smoothly through
points and lines whose third coordinate is known (thin_plate), the inside of a traced outline (region,
with its signed distance), and anything painted on top (ridges, hollows). A Slab is the solid between
two such surfaces inside such an outline; a Prism is an outline pushed straight through.
"""
import numpy as np
from scipy import ndimage, sparse
from scipy.sparse.linalg import spsolve
from skimage.draw import polygon as fill_polygon


class Map:
    def __init__(self, u0, u1, v0, v1, cell=1.0):
        self.u0, self.v0, self.cell = float(u0), float(v0), float(cell)
        self.nu, self.nv = int(round((u1 - u0) / cell)) + 1, int(round((v1 - v0) / cell)) + 1
        self.U, self.V = np.meshgrid(u0 + cell * np.arange(self.nu), v0 + cell * np.arange(self.nv), indexing="ij")

    def ij(self, u, v):
        return (np.asarray(u, float) - self.u0) / self.cell, (np.asarray(v, float) - self.v0) / self.cell

    def sample(self, A, u, v, order=1):
        i, j = self.ij(u, v)
        return ndimage.map_coordinates(A, [i, j], order=order, mode="nearest")

    def smooth(self, A):
        """A surface made ready for smooth_sample: read off between the grid's points it has no creases along the grid."""
        return ndimage.spline_filter(np.asarray(A, np.float64), order=3, mode="nearest")

    def smooth_sample(self, Cf, u, v):
        i, j = self.ij(u, v)
        return ndimage.map_coordinates(Cf, [i, j], order=3, mode="nearest", prefilter=False)

    def outside(self, u, v):
        """How far (mm) a point lies beyond the map's edge (negative inside): nothing drawn on a map reaches past it."""
        return np.maximum(np.maximum(self.u0 - u, u - self.U[-1, 0]), np.maximum(self.v0 - v, v - self.V[0, -1]))

    def thin_plate(self, pts, weight=30.0, tension=0.0):
        """The smoothest surface (least bending) through the points (u, v, value): value on the whole grid."""
        pts = np.asarray(pts, float)
        nu, nv = self.nu, self.nv; n = nu * nv
        idx = np.arange(n).reshape(nu, nv)
        rows, cols, vals = [], [], []

        def pair(a, b):                       # (value at b) - (value at a), once for each neighbour pair
            a, b = a.ravel(), b.ravel()
            rows.extend([a, a]); cols.extend([a, b]); vals.extend([-np.ones(len(a)), np.ones(len(a))])
        pair(idx[:-1, :], idx[1:, :]); pair(idx[1:, :], idx[:-1, :]); pair(idx[:, :-1], idx[:, 1:]); pair(idx[:, 1:], idx[:, :-1])
        Lp = sparse.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsr()
        i, j = self.ij(pts[:, 0], pts[:, 1])
        i = np.clip(i, 0, nu - 1.001); j = np.clip(j, 0, nv - 1.001)
        i0, j0 = np.floor(i).astype(int), np.floor(j).astype(int); fi, fj = i - i0, j - j0
        r = np.arange(len(pts))
        S = sparse.coo_matrix((np.concatenate([(1 - fi) * (1 - fj), fi * (1 - fj), (1 - fi) * fj, fi * fj]),
                               (np.concatenate([r, r, r, r]),
                                np.concatenate([idx[i0, j0], idx[i0 + 1, j0], idx[i0, j0 + 1], idx[i0 + 1, j0 + 1]]))), shape=(len(pts), n)).tocsr()
        w = weight * (np.ones(len(pts)) if pts.shape[1] < 4 else pts[:, 3])
        W = sparse.diags(w)
        A = Lp.T @ Lp + S.T @ W @ S + tension * (-Lp)
        z = spsolve(A.tocsc(), S.T @ (w * pts[:, 2]))
        return z.reshape(nu, nv)

    def region(self, poly, fine=4):
        """Signed distance (mm, < 0 inside) to a closed outline [(u, v)], on the grid."""
        poly = np.asarray(poly, float)
        c = self.cell / fine
        nu, nv = (self.nu - 1) * fine + 1, (self.nv - 1) * fine + 1
        m = np.zeros((nu, nv), bool)
        rr, cc = fill_polygon((poly[:, 0] - self.u0) / c, (poly[:, 1] - self.v0) / c, m.shape)
        m[rr, cc] = True
        d = (ndimage.distance_transform_edt(~m) - ndimage.distance_transform_edt(m)) * c
        d = ndimage.gaussian_filter(d, 0.6 * fine)
        return d[::fine, ::fine]

    def slope(self, A):
        gu, gv = np.gradient(A, self.cell)
        return np.sqrt(1.0 + gu * gu + gv * gv)


def round_meet(a, b, r):
    """Two solids' distances met (intersection) with the edge between them rounded to radius r."""
    return np.minimum(np.maximum(a + r, b + r), 0.0) + np.hypot(np.maximum(a + r, 0.0), np.maximum(b + r, 0.0)) - r


class Slab:
    """The solid between an outer surface and an inner one, inside an outline, all drawn on one Map.
    axes = (iu, iv, iw): which head-frame axes are the map's two and the one the surfaces are measured along;
    `sign` = +1 if the outer surface is the larger coordinate. mirror: fold x so that both sides are made."""
    def __init__(self, M, axes, outer, inner, region, round=2.0, sign=1.0, mirror=True):
        self.M, self.axes, self.round, self.sign, self.mirror = M, axes, round, sign, mirror
        self.outer, self.inner, self.reg = outer, inner, region
        self.k = 1.0 / M.slope(outer)
        self.c = [M.smooth(a) for a in (outer, inner, self.k, region)]
        lo = np.zeros(3); hi = np.zeros(3)
        iu, iv, iw = axes
        lo[iu], hi[iu] = M.U.min(), M.U.max(); lo[iv], hi[iv] = M.V.min(), M.V.max()
        ins = region < 2.0
        a, b = sign * outer[ins], sign * inner[ins]
        lo[iw], hi[iw] = min(a.min(), b.min()) - 2, max(a.max(), b.max()) + 2
        if mirror and iu == 0:
            lo[0] = 0.0
        self.bounds = (lo, hi)

    def __call__(self, X, Y, Z):
        P = [np.abs(X) if self.mirror else X, Y, Z]
        iu, iv, iw = self.axes
        u, v, w = np.broadcast_arrays(P[iu], P[iv], P[iw])
        o, i, k, d2 = (self.M.smooth_sample(c, u, v) for c in self.c)
        e = self.M.outside(u, v)
        d2 = np.where(e > 0, np.maximum(d2, e), d2)
        w = self.sign * w
        through = np.maximum((w - o) * k, (i - w) * k)
        return round_meet(through, d2, self.round).astype(np.float32)


class Prism:
    """An outline (signed distance on a Map) pushed through along the third axis between w0 and w1.
    taper: the opening narrows by this many mm from w0 to w1. lean: (du, dv) the outline moves sideways by per mm
    from w0 toward w1 (a canal that does not run square to the view it was traced in)."""
    def __init__(self, M, axes, region, w0, w1, mirror=True, taper=0.0, lean=(0.0, 0.0)):
        self.M, self.axes, self.reg, self.w0, self.w1, self.mirror, self.taper, self.lean = M, axes, region, w0, w1, mirror, taper, lean
        self.c = M.smooth(region)
        lo = np.zeros(3); hi = np.zeros(3); iu, iv, iw = axes
        ins = region < 1.0
        run = abs(w1 - w0)
        lo[iu], hi[iu] = M.U[ins].min() + min(0.0, lean[0] * run), M.U[ins].max() + max(0.0, lean[0] * run)
        lo[iv], hi[iv] = M.V[ins].min() + min(0.0, lean[1] * run), M.V[ins].max() + max(0.0, lean[1] * run)
        lo[iw], hi[iw] = min(w0, w1), max(w0, w1)
        self.bounds = (lo, hi)

    def __call__(self, X, Y, Z):
        P = [np.abs(X) if self.mirror else X, Y, Z]
        iu, iv, iw = self.axes
        u, v, w = np.broadcast_arrays(P[iu], P[iv], P[iw])
        t = np.clip((w - self.w0) / (self.w1 - self.w0), 0, 1)
        run = t * abs(self.w1 - self.w0)
        u, v = u - self.lean[0] * run, v - self.lean[1] * run
        d2 = self.M.smooth_sample(self.c, u, v); e = self.M.outside(u, v)
        d2 = np.where(e > 0, np.maximum(d2, e), d2)
        d2 = d2 + self.taper * t                       # the opening narrows by `taper` mm from w0 to w1
        lo, hi = min(self.w0, self.w1), max(self.w0, self.w1)
        return np.maximum(d2, np.maximum(lo - w, w - hi)).astype(np.float32)


class Funnel:
    """A hollow that runs from a closed margin (3D points) to an apex: at each station along the axis the
    margin's own outline, scaled. Used for the orbit: its opening is the traced margin."""
    def __init__(self, margin, apex, scale=((-0.4, 1.12), (0.0, 1.0), (0.22, 1.05), (0.6, 0.62), (1.0, 0.12))):
        margin = np.asarray(margin, float); apex = np.asarray(apex, float)
        self.M0 = margin.mean(0); ax = apex - self.M0; self.L = np.linalg.norm(ax); self.ax = ax / self.L
        e1 = np.cross([0.0, 1.0, 0.0], self.ax); e1 /= np.linalg.norm(e1); e2 = np.cross(self.ax, e1)
        self.e1, self.e2 = e1, e2
        d = margin - self.M0
        a = np.arctan2(d @ e2, d @ e1); r = np.hypot(d @ e1, d @ e2)
        o = np.argsort(a); a, r = a[o], r[o]
        th = np.radians(np.arange(-180, 181, 2.0))
        R = np.interp(th, np.concatenate([a - 2 * np.pi, a, a + 2 * np.pi]), np.concatenate([r, r, r]))
        R = ndimage.gaussian_filter1d(R, 3.0, mode="wrap")
        self.th, self.R = th, R
        self.scale = np.array(scale, float)
        rr = R.max() * self.scale[:, 1].max() + 3
        pts = np.array([self.M0 + self.ax * self.L * t for t in (self.scale[0, 0], 1.0)])
        self.bounds = (pts.min(0) - rr, pts.max(0) + rr)

    def __call__(self, X, Y, Z):
        dx, dy, dz = X - self.M0[0], Y - self.M0[1], Z - self.M0[2]
        w = dx * self.ax[0] + dy * self.ax[1] + dz * self.ax[2]
        u = dx * self.e1[0] + dy * self.e1[1] + dz * self.e1[2]
        v = dx * self.e2[0] + dy * self.e2[1] + dz * self.e2[2]
        t = w / self.L
        s = np.interp(t, self.scale[:, 0], self.scale[:, 1])
        R = np.interp(np.arctan2(v, u), self.th, self.R)
        d = np.hypot(u, v) - R * s
        return np.maximum(d * 0.9, np.maximum(w - self.L, self.scale[0, 0] * self.L - w)).astype(np.float32)
