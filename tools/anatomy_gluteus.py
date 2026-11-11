#!/usr/bin/env python3
"""The gluteus maximus made anew from its attachments. The one segmented from the CT (TotalSegmentator's) and warped
into the body is an oval pad over the buttock that stops short of the femur, the woman's with a loop and a hole at
its lower end; the muscle is a thick rhomboid running down and out from the back of the pelvis to the iliotibial
tract and the femur. This one is built to that shape on each body's own bones.

  python3 tools/anatomy_gluteus.py ATLAS_FOLDER   remakes both sides in both bodies of that atlas; their bundles are
                                                laid after (tools/anatomy_fibres.py); tools/anatomy_atlas.py calls
                                                remake()

1. Its corners on the bones (Gray's Anatomy, 1918, and Gerrish's Text-book of Anatomy, 1902, fig. 349, which draws
   its outline and its attachments on the bones; both public domain): above, the iliac crest where the posterior
   gluteal line meets it, 5 cm in front of the posterior superior iliac spine; below and inside, the side of the
   coccyx a centimetre above its tip; outside, over the side of the greater trochanter, where its upper fibres
   pass into the iliotibial tract; below and outside, the lower end of the gluteal tuberosity, 30 per cent of the
   femur's length below the trochanter's top. Its origin runs from the crest down behind the posterior gluteal
   line, over the spine, along the back of the sacrum's lower part (its fourth piece, a little inside the lateral
   border) to the coccyx; its upper border straight to the trochanter, bowed a little up; its lower border, which
   covers the ischial tuberosity standing (it passes a little below and behind it), down and out across the back
   of the thigh to the femur.
2. Laid on what lies under it: everything, seen from a vertical axis between the femoral head and the midline, as
   far out as it reaches (the hip bone, the sacrum and coccyx, the femur, the gluteus medius and minimus, the deep
   back muscles, and the sacrotuberous ligament, which the atlas lacks and is laid here from its attachments), the
   gaps between bridged as the muscles not drawn (piriformis, the small rotators, the hamstrings' heads) would fill
   them, smoothed; its deep face on its origin (its first tenth brought back down onto what it arises from: the
   bone, the erector spinae's aponeurosis, the ligament), its insertion on the femur, 5 mm off the other bones
   (the bursae over the ischial tuberosity and the trochanter), 1 mm off the other muscles, and stretched over
   their small bumps rather than into them.
3. Thick: 42 mm at most in the man and 36 in the woman (each scaled by the femur's length), through the middle of
   its belly, thinner toward its origin and its upper border, its borders rounded, a thin sheet where it joins the
   iliotibial tract, a thicker one at the gluteal tuberosity: so the muscle's volume comes to what MRI measures in
   living adults (Belzunce et al., BMJ Open Sport Exerc Med 2023;9:e001672, 87 recreational cyclists aged 30 to
   65: median 770 cm3 in the men, 621 in the women; about 10 cm3 a kilogram of body mass in both). Never nearer
   the skin than 6 mm (the fat under it), where a ray from inside first leaves the body (in the natal cleft, its
   wall), and the two muscles at least 5 mm each side of the midline, apart over the coccyx. Its superficial face
   is smooth as a muscle's is: no crease (no bend over 10 degrees from cell to cell) and no groove (no hollow
   curved tighter than a 5 cm radius), so the hollows of what lies under it are filled, not carried up through it.

Its fibres run as the grid's first way, from origin to insertion, and its bundles, and its tendon where it thins
to its insertion, are laid by tools/anatomy_fibres.py. The node names stay (TS_gluteus_maximus_R and _L), so
everything that refers to it still finds it. The shapes are checked against the reference index's images
(docs/sciences/anatomy-references.json): looked at, never traced or shipped.
"""
import json
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

NU, NV = 56, 48            # the grid: along the fibres (origin to insertion) and across them (upper to lower border)
STEP_T, STEP_Y = 1.0, 0.002  # the map's cells: degrees about its vertical axis, metres up
FAT = 0.006                # at least this much under the skin
MIDLINE = 0.005            # and this far from the midline, each side
MARGIN_IN = 0.001          # its lower inner corner this far in from the coccyx's lateral margin
CREASE = 10.0              # degrees: its superficial face, away from its borders, bends less than this cell to cell
HOLLOW = 0.05              # and is hollow nowhere tighter than this radius (a muscle fills a hollow under it)
THICK = {"male": 0.042, "female": 0.036}


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def sphere_fit(p):
    M = np.c_[2 * p, np.ones(len(p))]
    x = np.linalg.lstsq(M, (p * p).sum(1), rcond=None)[0]
    return x[:3], float(np.sqrt(x[3] + x[:3] @ x[:3]))


class Map:
    """Positions as (degrees about a vertical axis, from straight out to the side toward the back and in; height;
    distance from that axis)."""

    def __init__(self, head, sx, y0, y1, t0=-30.0, t1=185.0):
        self.h, self.sx = head, sx
        self.t0, self.y0 = t0, y0
        self.nt = int(round((t1 - t0) / STEP_T)) + 1
        self.ny = int(round((y1 - y0) / STEP_Y)) + 1

    def polar(self, p):
        d = p - self.h
        out, back = self.sx * d[:, 0], -d[:, 2]
        return np.degrees(np.arctan2(back, out)), p[:, 1], np.hypot(out, back)

    def point(self, t, y, r):
        a = np.radians(t)
        return np.stack([self.h[0] + self.sx * r * np.cos(a), y, self.h[2] - r * np.sin(a)], axis=-1)

    def cells(self, t, y):
        return (np.asarray(t) - self.t0) / STEP_T, (np.asarray(y) - self.y0) / STEP_Y

    def farthest(self, p):
        """Per cell, the farthest of p from the vertical (what a ray from outside meets first); -inf where none."""
        t, y, r = self.polar(p)
        i, j = (np.rint(c).astype(int) for c in self.cells(t, y))
        ok = (i >= 0) & (i < self.nt) & (j >= 0) & (j < self.ny)
        out = np.full((self.nt, self.ny), -np.inf)
        np.maximum.at(out, (i[ok], j[ok]), r[ok])
        return out

    def nearest(self, p):
        """Per cell, the nearest of p to the vertical (where a ray from inside first meets it); inf where none."""
        t, y, r = self.polar(p)
        i, j = (np.rint(c).astype(int) for c in self.cells(t, y))
        ok = (i >= 0) & (i < self.nt) & (j >= 0) & (j < self.ny)
        out = np.full((self.nt, self.ny), np.inf)
        np.minimum.at(out, (i[ok], j[ok]), r[ok])
        return out

    def at(self, field, t, y):
        i, j = self.cells(t, y)
        return ndimage.map_coordinates(field, [i.ravel(), j.ravel()], order=1, mode="nearest").reshape(np.shape(t))


def harmonic(field, known):
    """`field` with the cells not `known` filled smoothly from those that are: each the mean of its neighbours (a
    membrane stretched over the gap, not a step where the nearest values meet)."""
    from scipy.sparse import csr_matrix
    from scipy.sparse.linalg import spsolve
    unknown = ~known
    if not unknown.any() or not known.any():
        return field.copy()
    nt, ny = field.shape
    index = -np.ones(field.shape, int)
    index[unknown] = np.arange(unknown.sum())
    ii, jj = np.nonzero(unknown)
    rows, cols, vals = [], [], []
    rhs = np.zeros(len(ii))
    degree = np.zeros(len(ii))
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ni, nj = ii + di, jj + dj
        inside = (ni >= 0) & (ni < nt) & (nj >= 0) & (nj < ny)
        degree += inside
        n_i, n_j, me = ni[inside], nj[inside], np.nonzero(inside)[0]
        free = unknown[n_i, n_j]
        rows.append(me[free]); cols.append(index[n_i[free], n_j[free]]); vals.append(-np.ones(free.sum()))
        np.add.at(rhs, me[~free], field[n_i[~free], n_j[~free]])
    # held a little to the nearest known value, so a region the known cells never reach is still solvable
    idx = ndimage.distance_transform_edt(unknown, return_distances=False, return_indices=True)
    nearest = field[tuple(idx)][unknown]
    eps = 1e-4
    rows.append(np.arange(len(ii))); cols.append(np.arange(len(ii))); vals.append(degree + eps)
    A = csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(len(ii), len(ii)))
    out = field.copy()
    out[unknown] = spsolve(A, rhs + eps * nearest)
    return out


def bridged(field, cells_t, cells_y):
    """The surface over what is there: its gaps narrower than the reach (in cells: t, y) bridged over the tops on
    either side (a grey closing), wider ones spanned smoothly."""
    have = np.isfinite(field) & (field > 0)
    base = np.where(have, field, 0.0)
    rt, ry = max(int(cells_t), 1), max(int(cells_y), 1)
    gt, gy = np.ogrid[-rt:rt + 1, -ry:ry + 1]
    disc = (gt / rt) ** 2 + (gy / ry) ** 2 <= 1.0
    closed = ndimage.grey_closing(base, footprint=disc)
    return harmonic(closed, closed > 0.01)


def midline(sacrum):
    """The body's midline (x, metres): the middle of the sacrum's width, height by height over its lower half (its
    vertices' mean leans toward the side with more of them)."""
    y0, y1 = sacrum[:, 1].min(), sacrum[:, 1].min() + 0.5 * np.ptp(sacrum[:, 1])
    mids = []
    for y in np.linspace(y0 + 0.005, y1, 8):
        band = sacrum[np.abs(sacrum[:, 1] - y) < 0.003]
        if len(band) >= 3:
            mids.append(0.5 * (band[:, 0].min() + band[:, 0].max()))
    return float(np.median(mids)) if mids else float(sacrum[:, 0].mean())


def landmarks(hip, sacrum, coccyx, femur, sx):
    """The femoral head's centre and the corners of the muscle on the bones (metres)."""
    top = femur[femur[:, 1] > femur[:, 1].max() - 0.06]
    extreme = top[np.argmin(sx * top[:, 0])]
    head, radius = sphere_fit(top[np.linalg.norm(top - extreme, axis=1) < 0.03])
    side = femur[sx * femur[:, 0] > sx * head[0] + 0.03]
    trochanter = side[np.argmax(side[:, 1])]
    length = float(np.ptp(femur[:, 1]))
    k = length / 0.485
    above = hip[hip[:, 1] > head[1]]
    psis = above[np.argmin(above[:, 2])]
    tip = coccyx[np.argmin(coccyx[:, 1])]
    # above: the crest where the posterior gluteal line meets it, 5 cm in front of the spine (Gray), its highest
    # point that far from the spine
    ring = hip[np.abs(np.linalg.norm(hip - psis, axis=1) - 0.05 * k) < 0.002]
    a = ring[np.argmax(ring[:, 1])] if len(ring) else psis + [0, 0.04 * k, 0.02 * k]
    # the back of the sacrum's lower part, a little inside its lateral border (it arises there, from the lateral
    # sacral crest and the aponeurosis over it), at its fourth piece (a fifth of the way up from its apex)
    ys = sacrum[:, 1].min() + 0.2 * np.ptp(sacrum[:, 1])
    mid_x = midline(sacrum)
    band = sacrum[np.abs(sacrum[:, 1] - ys) < 0.003]
    if len(band):
        out = sx * (band[:, 0] - mid_x)
        near = band[np.abs(out - (out.max() - 0.008 * k)) < 0.003]
        s = near[np.argmin(near[:, 2])] if len(near) else band[np.argmax(out)]
    else:
        s = (a + tip) / 2
    # below and inside: the side of the coccyx a centimetre above its tip, on the bone (MARGIN_IN in from its lateral
    # margin at that height, on its back half, where a ray meets the bone rather than grazing its edge): a scanned
    # coccyx's tip leans to one side, so a corner set out from the tip lies off the bone on one side and near the
    # midline on the other
    band = coccyx[np.abs(coccyx[:, 1] - (tip[1] + 0.010)) < 0.003]
    band = band[band[:, 2] <= np.median(band[:, 2])] if len(band) >= 6 else band
    d = (band[np.argmax(sx * band[:, 0])] - np.array([sx * MARGIN_IN, 0.0, 0.0]) if len(band)
         else tip + np.array([sx * 0.006, 0.010, -0.003]))
    # outside: over the trochanter's side, 2 cm below its top
    band = femur[np.abs(femur[:, 1] - (trochanter[1] - 0.02 * k)) < 0.004]
    b = band[np.argmax(sx * band[:, 0])] + np.array([sx * 0.006, 0, 0])
    # below and outside: the gluteal tuberosity's lower end, on the femur's back and outer side
    band = femur[np.abs(femur[:, 1] - (trochanter[1] - 0.30 * length)) < 0.004]
    c0 = band.mean(0)
    way = np.array([sx * np.cos(np.radians(45)), 0, -np.sin(np.radians(45))])
    c = band[np.argmax((band - c0) @ way)] + 0.004 * way
    it = hip[np.argmin(hip[:, 1])]
    # standing, its lower border covers the ischial tuberosity (Gray): it passes a little below and behind it
    t = it + np.array([0.0, -0.012 * k, -0.008 * k])
    return dict(head=head, radius=radius, trochanter=trochanter, length=length, psis=psis, a=a, s=s, d=d, b=b, c=c,
                t=t, tip=tip, tuberosity=it, k=k)


def ligament(hip, sacrum, coccyx, L, sx, n=64):
    """Points on the back of the sacrotuberous ligament, which the muscle's lower part lies on and arises from in
    part (Gray, 1918: from the posterior superior iliac spine and the lateral margins of the lower sacrum and the
    upper coccyx, narrowing as it runs down and out, widening again into the inner margin of the ischial
    tuberosity). The atlas has no ligaments here, so without it the muscle would sag into the gap between the
    coccyx and the tuberosity."""
    k, psis, tip, it = L["k"], L["psis"], L["tip"], L["tuberosity"]
    mid = midline(sacrum)
    tail = np.vstack([sacrum, coccyx])
    # its base: the spine, then the sacrum's lateral margin (its back half) down to the coccyx's first piece
    base = [psis]
    for y in np.linspace(psis[1] - 0.025 * k, tip[1] + 0.02 * k, 8):
        band = tail[np.abs(tail[:, 1] - y) < 0.003]
        if len(band) < 3:
            continue
        band = band[band[:, 2] <= np.median(band[:, 2])]
        base.append(band[np.argmax(sx * (band[:, 0] - mid))])
    # its foot: the tuberosity's inner margin, behind
    foot = []
    low = hip[(hip[:, 1] < it[1] + 0.045 * k) & (sx * (hip[:, 0] - it[0]) < 0.02)]
    for y in np.linspace(it[1] + 0.035 * k, it[1] + 0.006 * k, 6):
        band = low[np.abs(low[:, 1] - y) < 0.003]
        if len(band) < 3:
            continue
        foot.append(band[np.argmax(-sx * (band[:, 0] - it[0]) - (band[:, 2] - it[2]))])
    if len(base) < 3 or len(foot) < 2:
        return np.zeros((0, 3))
    along = lambda P: (lambda d: (np.r_[0, np.cumsum(d)] / max(d.sum(), 1e-9)))(np.linalg.norm(np.diff(P, axis=0), axis=1))
    base, foot = np.array(base), np.array(foot)
    a = np.linspace(0, 1, n)
    top = np.stack([np.interp(a, along(base), base[:, i]) for i in range(3)], 1)
    bottom = np.stack([np.interp(a, along(foot), foot[:, i]) for i in range(3)], 1)
    b = np.linspace(0, 1, n)[:, None, None]
    P = (1 - b) * top[None] + b * bottom[None]
    middle = (1 - b) * top[n // 2][None, None] + b * bottom[n // 2][None, None]
    P = middle + (P - middle) * (1 - 0.65 * np.sin(np.pi * b))
    return P.reshape(-1, 3)


def coons(A, B, C, D, upper, lower, origin, insertion, u, v):
    """The patch over (u, v) in [0, 1]^2 from its four borders (each a function of its own parameter, in map
    coordinates) and corners: A (0, 0), B (1, 0), C (1, 1), D (0, 1)."""
    U, V = np.meshgrid(u, v, indexing="ij")
    up, lo = upper(u)[:, None, :], lower(u)[:, None, :]
    og, ins = origin(v)[None, :, :], insertion(v)[None, :, :]
    U3, V3 = U[..., None], V[..., None]
    return ((1 - V3) * up + V3 * lo + (1 - U3) * og + U3 * ins
            - ((1 - U3) * (1 - V3) * A + U3 * (1 - V3) * B + (1 - U3) * V3 * D + U3 * V3 * C))


def bowed(P, Q, bow):
    """A curve from P to Q (map coordinates) bowed sideways by `bow` (a 2-vector) at its middle."""
    return lambda s: P[None] + (Q - P)[None] * s[:, None] + 4 * (s * (1 - s))[:, None] * bow[None]


def through(P, M, Q):
    """A curve from P through M to Q (a quadratic through the three at 0, 1/2 and 1)."""
    c1 = 2 * M - 0.5 * (P + Q)
    return lambda s: ((1 - s) ** 2)[:, None] * P + (2 * s * (1 - s))[:, None] * c1 + (s * s)[:, None] * Q


def spline(points):
    """A smooth curve through the points (map coordinates), at 0 and 1 the first and last, spaced by the distance
    between them."""
    from scipy.interpolate import CubicSpline
    P = np.array(points, float)
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
    curve = CubicSpline(d / d[-1], P, bc_type="natural")
    return lambda s: curve(np.asarray(s, float))


def grid_smooth(r, rounds, fixed=None):
    for _ in range(rounds):
        avg = r.copy()
        avg[1:-1, 1:-1] = 0.25 * (r[2:, 1:-1] + r[:-2, 1:-1] + r[1:-1, 2:] + r[1:-1, :-2])
        avg[0, 1:-1] = (r[0, 2:] + r[0, :-2] + r[1, 1:-1]) / 3
        avg[-1, 1:-1] = (r[-1, 2:] + r[-1, :-2] + r[-2, 1:-1]) / 3
        avg[1:-1, 0] = (r[2:, 0] + r[:-2, 0] + r[1:-1, 1]) / 3
        avg[1:-1, -1] = (r[2:, -1] + r[:-2, -1] + r[1:-1, -2]) / 3
        r = 0.5 * r + 0.5 * avg
    return r


def creased(g, limit):
    """The grid points where the surface `g` (NU x NV x 3) bends more than `limit` degrees from one cell to the
    next."""
    n = np.cross(np.gradient(g, axis=0), np.gradient(g, axis=1))
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)
    cos = np.cos(np.radians(limit))
    bad = np.zeros(g.shape[:2], bool)
    du = np.einsum("ijk,ijk->ij", n[1:], n[:-1]) < cos
    dv = np.einsum("ijk,ijk->ij", n[:, 1:], n[:, :-1]) < cos
    bad[1:] |= du
    bad[:-1] |= du
    bad[:, 1:] |= dv
    bad[:, :-1] |= dv
    return bad


def hollowed(g, normal, radius):
    """The grid points where the surface `g` (NU x NV x 3) is hollow, seen along `normal`, more tightly than
    `radius` (metres) along the grid's rows, its columns or either diagonal."""
    n = np.cross(np.gradient(g, axis=0), np.gradient(g, axis=1))
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)
    n *= np.sign(np.einsum("ijk,ijk->ij", n, normal))[..., None]
    bad = np.zeros(g.shape[:2], bool)
    c = g[1:-1, 1:-1]
    for di, dj in ((1, 0), (0, 1), (1, 1), (1, -1)):
        f = g[1 + di:g.shape[0] - 1 + di, 1 + dj:g.shape[1] - 1 + dj]
        b = g[1 - di:g.shape[0] - 1 - di, 1 - dj:g.shape[1] - 1 - dj]
        step = 0.5 * (np.linalg.norm(f - c, axis=2) + np.linalg.norm(b - c, axis=2))
        bend = np.einsum("ijk,ijk->ij", f + b - 2 * c, n[1:-1, 1:-1]) / np.maximum(step, 1e-9) ** 2
        bad[1:-1, 1:-1] |= bend > 1.0 / radius
    return bad


def unfold(top, deep, normal, floor, rounds=200):
    """The superficial face with its folds, creases and grooves smoothed out: where it is thick over a hollow its
    offset can turn over on itself, or nearly, and bend sharply, or carry the hollow up into a groove a muscle would
    fill; there, and two rows round, each point is moved toward its neighbours' mean, never nearer the deep face
    than `floor`, until none is turned over and none, four rows or more in from the borders, bends more than CREASE
    or is hollow tighter than HOLLOW. Its border rows are left as they are: there it comes down
    onto the deep face as a rounded edge, steeply, and where the deep face curls under (the lower border by the
    coccyx) the edge's last step may lean over a little, as a rounded edge does."""
    facing = lambda g: np.cross(np.diff(g, axis=0)[:, :-1], np.diff(g, axis=1)[:-1])
    ref = facing(deep)
    top = top.copy()
    nu, nv = top.shape[:2]
    I, J = np.meshgrid(np.arange(nu), np.arange(nv), indexing="ij")
    away = np.minimum(np.minimum(I, nu - 1 - I), np.minimum(J, nv - 1 - J)) >= 4
    inner = np.zeros(top.shape[:2], bool)
    inner[1:-1, 1:-1] = True
    for _ in range(rounds):
        bad = np.einsum("ijk,ijk->ij", facing(top), ref) <= 0
        bad[0], bad[-1], bad[:, 0], bad[:, -1] = False, False, False, False
        mask = (creased(top, CREASE) | hollowed(top, normal, HOLLOW)) & away
        for di in (0, 1):
            for dj in (0, 1):
                mask[di:di + bad.shape[0], dj:dj + bad.shape[1]] |= bad
        if not mask.any():
            break
        mask = ndimage.binary_dilation(mask, iterations=2) & inner
        pad = np.pad(top, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = 0.25 * (pad[2:, 1:-1] + pad[:-2, 1:-1] + pad[1:-1, 2:] + pad[1:-1, :-2])
        top[mask] = 0.5 * top[mask] + 0.5 * avg[mask]
        t = np.einsum("ijk,ijk->ij", top - deep, normal)
        top += normal * np.maximum(floor - t, 0.0)[..., None]
    return top


def sheet(deep, top):
    """A closed mesh from two grids of points (NU x NV x 3): its deep face, its superficial face, and the strips
    between them round its four borders."""
    nu, nv = deep.shape[:2]
    v = np.vstack([deep.reshape(-1, 3), top.reshape(-1, 3)])
    at = lambda i, j, face: face * nu * nv + i * nv + j
    f = []
    for i in range(nu - 1):
        for j in range(nv - 1):
            a, b, c, d = at(i, j, 0), at(i + 1, j, 0), at(i + 1, j + 1, 0), at(i, j + 1, 0)
            f += [(a, c, b), (a, d, c)]
            a, b, c, d = at(i, j, 1), at(i + 1, j, 1), at(i + 1, j + 1, 1), at(i, j + 1, 1)
            f += [(a, b, c), (a, c, d)]
    ring = ([(i, 0) for i in range(nu - 1)] + [(nu - 1, j) for j in range(nv - 1)]
            + [(i, nv - 1) for i in range(nu - 1, 0, -1)] + [(0, j) for j in range(nv - 1, 0, -1)])
    for (i0, j0), (i1, j1) in zip(ring, ring[1:] + ring[:1]):
        a, b = at(i0, j0, 0), at(i1, j1, 0)
        c, d = at(i1, j1, 1), at(i0, j0, 1)
        f += [(a, b, c), (a, c, d)]
    f = np.array(f, np.int64)
    # facing out: the enclosed volume positive
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    if np.einsum("ij,ij->i", a, np.cross(b, c)).sum() < 0:
        f = f[:, ::-1]
    return v, f


def build(sex, sx, hip, sacrum, coccyx, femur, bones_v, bones_f, muscles_v, muscles_f, skin_v, skin_f):
    """One side's gluteus maximus: (vertices, triangles, notes)."""
    from anatomy_fibres import surface_points
    L = landmarks(hip, sacrum, coccyx, femur, sx)
    k = L["k"]
    y0 = L["c"][1] - 0.05 * k
    y1 = max(L["a"][1], L["psis"][1]) + 0.04 * k
    # the map's axis: halfway from the femoral head to the midline and 4 cm in front, so that its rays run
    # straight back through the sacrum and the coccyx, where it arises, and out through the trochanter (from the
    # head's own vertical they cross the sacrum aslant, toward the midline, and meet its far side)
    mid = midline(sacrum)
    axis = L["head"] + np.array([0.5 * (mid - L["head"][0]), 0.0, 0.04 * k])
    mp = Map(axis, sx, y0, y1)
    keep = lambda p: p[(p[:, 1] > y0 - 0.01) & (p[:, 1] < y1 + 0.01) & (sx * (p[:, 0] - L["head"][0]) > -0.15)
                       & (p[:, 2] < L["head"][2] + 0.08)]
    pts = lambda vs, fs: keep(np.vstack([surface_points(v, f, 0.0012) for v, f in zip(vs, fs)])) if vs else np.zeros((0, 3))
    # this side's only (the sacrum's and coccyx's far half, and the other buttock's skin, lie farther along the rays
    # that pass the midline)
    this_side = lambda p: p[sx * (p[:, 0] - mid) > 0.0]
    bone_p, muscle_p = this_side(pts(bones_v, bones_f)), this_side(pts(muscles_v, muscles_f))
    skin_p = this_side(pts(skin_v, skin_f))
    # the sacrotuberous ligament it lies on, as a muscle is (1 mm off it)
    muscle_p = np.vstack([muscle_p, ligament(hip, sacrum, coccyx, L, sx)])
    raw_b, raw_m, raw_s = mp.farthest(bone_p), mp.farthest(muscle_p), mp.nearest(skin_p)
    r_ref = 0.12 * k
    cells = lambda metres, r=r_ref: (np.degrees(metres / r) / STEP_T, metres / STEP_Y)
    # what it must clear: the bones' and muscles' tops, their pits and grooves (the sacral foramina, between the
    # crests) under 3 cm across bridged, as its aponeurotic origin and the fascia bridge them
    disc = lambda ct, cy: (lambda gt, gy: (gt / max(ct, 1)) ** 2 + (gy / max(cy, 1)) ** 2 <= 1.0)(
        *np.ogrid[-int(ct):int(ct) + 1, -int(cy):int(cy) + 1])
    grow = lambda x: ndimage.maximum_filter(np.where(np.isfinite(x), x, -1.0), size=3)
    close = lambda x: ndimage.grey_closing(x, footprint=disc(*cells(0.016 * k, 0.1)))
    rb, rm = close(grow(raw_b)), close(grow(raw_m))
    # (the short rotators, behind the hip joint between the trochanter and the ischium, fill a gap 7 cm across)
    ct, cy = cells(0.040 * k)
    under = bridged(np.maximum(raw_b, raw_m), ct, cy)
    under = ndimage.gaussian_filter(under, cells(0.006 * k))
    # the skin where a ray from inside first leaves the body (in the natal cleft, over the coccyx, its wall, not the
    # buttock beyond), filled and smoothed a little, but never beyond the skin met in a cell or its neighbours
    known = np.isfinite(raw_s)
    skin = ndimage.gaussian_filter(harmonic(np.where(known, raw_s, 0.0), known), (1.0, 1.0))
    skin = np.minimum(skin, ndimage.grey_erosion(np.where(known, raw_s, np.inf), size=3))

    # the outline in map coordinates (arc length at r_ref, height)
    to_map = lambda p: (lambda t, y, r: np.array([np.radians(t) * r_ref, y]))(*mp.polar(p[None]))[:, 0]
    A, B, C, D, S, T, PS = (to_map(L[x]) for x in ("a", "b", "c", "d", "s", "t", "psis"))
    span = lambda P, Q: np.linalg.norm(Q - P)
    up_n = np.array([0.0, 1.0])
    upper = bowed(A, B, 0.12 * span(A, B) * up_n)
    lower = spline([D, T, C])
    origin = spline([A, PS, S, D])
    insertion = bowed(B, C, np.zeros(2))
    u = np.linspace(0, 1, NU)
    v = np.linspace(0, 1, NV)
    P = coons(A, B, C, D, upper, lower, origin, insertion, u, v)
    th, yy = np.degrees(P[..., 0] / r_ref), P[..., 1]

    # the deep face: on what lies under it, never in it
    U, V = np.meshgrid(u, v, indexing="ij")
    gap_b = np.interp(U, [0, 0.12, 0.85, 1], [0.0005, 0.005, 0.005, 0.0008])
    clear = np.maximum(mp.at(rb, th, yy) + gap_b, mp.at(rm, th, yy) + 0.001)
    # over the bumps of what is under it (the tubercles of the sacral crests), not down between them: its deep face
    # an aponeurosis stretched over them
    need = np.maximum(ndimage.gaussian_filter(ndimage.maximum_filter(clear, size=5, mode="nearest"), 1.5,
                                              mode="nearest"), clear)
    # and, where the skin comes close over bone (over the coccyx in the natal cleft), no nearer it than half the fat:
    # the stretching over bumps gives way there first, then the bridging; only the bone itself does not
    hi = mp.at(skin, th, yy) - FAT / 2
    need = np.maximum(np.minimum(need, hi), clear)
    hi = np.maximum(hi, need)
    r_d = np.minimum(np.maximum(mp.at(under, th, yy) + 0.001, need), hi)
    for _ in range(24):
        r_d = np.maximum(np.minimum(grid_smooth(r_d, 3), hi), need)
    # its origin on what it arises from: the smoothing and the stretching over bumps lift the deep face off its
    # attachments wherever something thicker lies beside them (the erector spinae beside the posterior iliac crest
    # held the man's 6 to 13 mm off his ilium), so over the first tenth of its fibres it comes back down to them;
    # only onto what lies close under it (a ray past the coccyx's side meets nothing until the pelvis's far wall)
    drop = r_d - clear
    r_d = r_d - drop * (1 - smooth(0.012 * k, 0.020 * k, drop)) * (1 - smooth(0.0, 0.10, U))
    # thickness: its belly in the middle, its origin fleshy, a sheet into the iliotibial tract, its borders rounded
    # (a smooth curve through these, not straight pieces, whose corners would crease its surface)
    # (and the curve itself rounded where it turns, at its knots, by a gaussian 6 per cent of its length wide: at
    # 44 mm a turn from a gentle to a steep slope over one cell reads as a crease across the belly)
    from scipy.interpolate import PchipInterpolator
    from scipy.ndimage import gaussian_filter1d
    knots, values = [0, 0.08, 0.35, 0.6, 0.8, 0.92, 1], [0.35, 0.75, 1.0, 0.95, 0.55, 0.16, 0.1]
    curve = PchipInterpolator(knots, values)
    uf = np.linspace(-0.4, 1.4, 1801)
    slope0, slope1 = curve.derivative()(0.0), curve.derivative()(1.0)
    line = np.where(uf < 0, values[0] + slope0 * uf, np.where(uf > 1, values[-1] + slope1 * (uf - 1),
                                                              curve(np.clip(uf, 0, 1))))
    along = np.interp(U, uf, gaussian_filter1d(line, 0.06 / (uf[1] - uf[0])))
    along = along + (V > 0.7) * np.interp(U, [0.8, 0.92, 1], [0.0, 0.08, 0.12]) * smooth(0.7, 0.85, V)
    # (the lower border tapers over a wider band than the upper, rounding as the edge of a thick mass does)
    across = np.sqrt(np.clip(1 - np.abs(2 * V - 1) ** np.where(V < 0.5, 6.0, 3.0), 0, 1))
    across = np.maximum(across, 0.12) * np.where(V < 0.5, 0.85 + 0.15 * smooth(0.0, 0.5, V), 1.0)
    t_max = THICK[sex] * k
    made = np.maximum(t_max * along * across, 0.002)
    deep = mp.point(th, yy, r_d)
    # the superficial face: over a smooth version of the deep one, along its normal (not the ray, which near the
    # sacrum runs in toward the midline), so the muscle's mass is smooth and the bumps of what lies under it are
    # taken up in its thickness; never within 2 mm of its deep face, nor nearer the skin than FAT. At its borders
    # the smooth version comes back to the deep face, so they end as rounded edges on it, not cut faces.
    I, J = np.meshgrid(np.arange(NU), np.arange(NV), indexing="ij")
    rim = smooth(0.0, 4.0, np.minimum(np.minimum(I, NU - 1 - I), np.minimum(J, NV - 1 - J)))
    r_smooth = ndimage.gaussian_filter(r_d, (4.0, 4.0), mode="nearest")
    base = mp.point(th, yy, r_d + rim * (r_smooth - r_d))
    # (its normals the smooth surface's, which do not turn where the base comes back to the deep face)
    smooth_face = mp.point(th, yy, r_smooth)
    normal = np.cross(np.gradient(smooth_face, axis=0), np.gradient(smooth_face, axis=1))
    ray = mp.point(th, yy, r_d + 1.0) - deep
    normal *= np.sign(np.einsum("ijk,ijk->ij", normal, ray))[..., None]
    normal /= np.maximum(np.linalg.norm(normal, axis=2), 1e-12)[..., None]
    for _ in range(4):
        normal[1:-1, 1:-1] = (normal[1:-1, 1:-1] + 0.25 * (normal[2:, 1:-1] + normal[:-2, 1:-1] + normal[1:-1, 2:]
                                                         + normal[1:-1, :-2]))
        normal /= np.maximum(np.linalg.norm(normal, axis=2), 1e-12)[..., None]
    floor = np.einsum("ijk,ijk->ij", deep - base, normal) + 0.002
    # (smoothed, but never thicker than it was made, so its rounded borders stay rounded)
    thick = np.maximum(made, floor)
    for _ in range(3):
        thick = np.maximum(np.minimum(grid_smooth(thick, 2), np.maximum(made, floor)), floor)
    # nor nearer the midline than MIDLINE (the two muscles' medial borders come close at the coccyx, never together)
    inward = np.maximum(-sx * normal[..., 0], 0.3)
    squeezed = np.zeros(thick.shape, bool)
    for _ in range(8):
        top = base + thick[..., None] * normal
        ts, ys, rs = mp.polar(top.reshape(-1, 3))
        over = (rs - (mp.at(skin, ts, ys) - FAT)).reshape(thick.shape)
        near = (MIDLINE * k - sx * (top[..., 0] - mid)) / inward
        if over.max() <= 1e-4 and near.max() <= 1e-4:
            break
        squeezed |= over > 1e-4
        thick = np.maximum(thick - np.maximum(np.maximum(over, near), 0.0), floor)
        thick = np.maximum(np.minimum(thick, grid_smooth(thick, 1) + 0.0005), floor)
    squeezed = int(squeezed.sum())
    top = unfold(base + thick[..., None] * normal, deep, normal, floor)
    # (smoothing a hollow out lifts it: held under the skin and off the midline again)
    for _ in range(8):
        ts, ys, rs = mp.polar(top.reshape(-1, 3))
        over = (rs - (mp.at(skin, ts, ys) - FAT)).reshape(thick.shape)
        near = (MIDLINE * k - sx * (top[..., 0] - mid)) / inward
        excess = np.maximum(np.maximum(over, near), 0.0)
        if excess.max() <= 1e-4:
            break
        top -= normal * excess[..., None]
        top += normal * np.maximum(floor - np.einsum("ijk,ijk->ij", top - deep, normal), 0.0)[..., None]
    thick = np.einsum("ijk,ijk->ij", top - deep, normal)
    vtx, tri = sheet(deep, top)
    if os.environ.get("GM_DEBUG"):
        np.savez(os.path.join(os.environ["GM_DEBUG"], f"{sex}_{'R' if sx < 0 else 'L'}.npz"), raw_b=raw_b,
                 raw_m=raw_m, under=under, skin=skin, rb=rb, rm=rm, th=th, yy=yy, r_d=r_d, t0=mp.t0, y0=mp.y0,
                 corners=np.array([to_map(L[x]) for x in ("a", "b", "c", "d", "s", "t", "psis")]) / [r_ref, 1],
                 need=need, clear=clear, hi=hi, made=made, floor=floor, thick=thick, base=base, normal=normal, deep=deep,
                 top=top)
    ts, ys, rs = mp.polar(top.reshape(-1, 3))
    out = int((rs > mp.at(skin, ts, ys) - 0.001).sum())
    notes = (f"head {np.round(L['head'] * 1000).astype(int)} mm, corners: crest {np.round(L['a'] * 1000).astype(int)}, "
             f"sacrum {np.round(L['s'] * 1000).astype(int)}, coccyx {np.round(L['d'] * 1000).astype(int)}, trochanter "
             f"{np.round(L['b'] * 1000).astype(int)}, tuberosity {np.round(L['c'] * 1000).astype(int)}; thickest "
             f"{thick.max() * 1000:.0f} mm, {squeezed} of {thick.size} points thinner for the skin, {out} nearer it than 1 mm")
    return vtx, tri, notes


def remake(folder, quiet=False):
    """Remakes the gluteus maximus, both sides, in `folder`'s atlas (anatomy.json and its part files); does nothing
    if it is made already. Returns what it did."""
    from anatomy_fibres import read_part, write_part, sha256

    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        parts = {p["id"]: p for p in body["parts"]}
        hipm = parts.get("hip-muscles")
        if hipm is None:
            continue
        gm = [st for st in hipm["structures"] if "gluteus_maximus" in st["node"]]
        if not gm or all(st.get("made") == "attachments" for st in gm):
            continue
        load = lambda pid: [(st, m) for st, m in zip(parts[pid]["structures"], read_part(os.path.join(folder, parts[pid]["file"])))] if pid in parts else []
        pelvis, legs, back, skin = load("pelvis"), load("legs"), load("back-muscles"), load("skin")
        own = load("hip-muscles")
        sex = body["id"]
        made = {}
        for st in gm:
            side = "R" if st["node"].endswith("_R") else "L"
            sx = -1.0 if side == "R" else 1.0
            mine = lambda items, words: [(s, m) for s, m in items if s["node"].endswith("_" + side) and any(w in s["node"] for w in words)]
            hip = mine(pelvis, ("ilium", "ischium", "pubis", "hip"))
            sacrum = [m for s, m in pelvis if "sacrum" in s["node"]]
            coccyx = [m for s, m in pelvis if "coccyx" in s["node"]]
            femur = mine(legs, ("femur",))
            if not hip or not sacrum or not coccyx or not femur:
                said.append(f"{sex} {side}: bones missing, left as it was")
                continue
            bones = [m for _, m in hip] + sacrum + coccyx + [m for _, m in femur]
            muscles = [m for _, m in mine(own, ("gluteus_medius", "gluteus_minimus"))] + [m for _, m in mine(back, ("deep_back",))]
            v, f, notes = build(sex, sx, np.vstack([m[0] for _, m in hip]), sacrum[0][0], coccyx[0][0], femur[0][1][0],
                                [m[0] for m in bones], [m[1] for m in bones], [m[0] for m in muscles],
                                [m[1] for m in muscles], [m[0] for _, m in skin], [m[1] for _, m in skin])
            made[st["node"]] = (v.astype(np.float32), f)
            said.append(f"{sex} {side}: {notes}")
        if not made:
            continue
        meshes = [made.get(st["node"], m) for st, m in own]
        lo, hi = write_part(os.path.join(folder, hipm["file"]), [(np.asarray(v, np.float32), np.asarray(f, np.int64)) for v, f in meshes])
        for st, (_, f) in zip(hipm["structures"], meshes):
            st["triangles"] = int(len(f))
            if st["node"] in made:
                st["made"] = "attachments"
        hipm["bytes"] = os.path.getsize(os.path.join(folder, hipm["file"]))
        hipm["sha256"] = sha256(os.path.join(folder, hipm["file"]))
        hipm["triangles"] = int(sum(st["triangles"] for st in hipm["structures"]))
        hipm["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
        # its bundles are laid anew (tools/anatomy_fibres.py)
        fibres = hipm.pop("fibres", None)
        if fibres and os.path.exists(os.path.join(folder, fibres["file"])):
            os.remove(os.path.join(folder, fibres["file"]))
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            print("  " + line)
    made_n = sum(1 for line in said if "left as it was" not in line)
    return f"{made_n} glutei maximi made anew" if said else "the glutei maximi made already"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
    import anatomy_fibres
    print(anatomy_fibres.annotate(sys.argv[1], quiet=True), "muscles laid")
