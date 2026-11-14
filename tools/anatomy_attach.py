#!/usr/bin/env python3
"""Each muscle's origin and insertion put where the textbooks put them: on the right bone, at the right landmark,
touching it (docs/sciences/muscle-attachments.json says where, tools/anatomy_attach_audit.py checks).

    python3 tools/anatomy_attach.py ATLAS_FOLDER [--only REGEX]   moves the ends of the muscles of both bodies of
                                                                 that atlas; their bundles are laid after
                                                                 (tools/anatomy_fibres.py); remake() is the step

The muscles came from CT segmentations (TotalSegmentator's) and the Visible Human organ sets, warped into each body,
then given room (tools/anatomy_gaps.py, which leaves them about 3 mm off the bones): an end can stop short of its
bone (the iliopsoas's tendon on the front of the femur, 2 to 4 cm from the lesser trochanter), sit on the wrong part
of it (the gluteus minimus's above the trochanter's anterior border), or run into it (the gluteus medius's, a
centimetre into the greater trochanter). Each muscle's mesh is moved here, never remade, by smooth move fields, so
its surface stays as it was (no new crease, no fold, nothing jagged):

1. Each end (a tendon or a narrow end, the row's kind "end") brought onto its landmark (landmarks() of the audit:
   the lesser trochanter, the greater trochanter's lateral or anterior face, the anterior inferior iliac spine, the
   side of T12...), or, with none, onto the nearest part of its bone: the end moves as one, its deepest point
   OFFSET off the bone, and the move fades along the muscle (a quintic step, smooth to the second derivative at both
   ends of the fade) over FALLOFF times its length, at least FADE_MIN and at most FADE_MAX of the muscle's length.
   Where that would carry the muscle through a bone (the iliopsoas's tendon, which must pass below the femur's
   neck to reach the lesser trochanter on its back), the end's last part is routed instead: the shortest way
   from where the fade starts to the landmark that keeps the muscle's own thickness clear of the bones (on a 2 mm
   grid), drawn taut and smooth, and the muscle's cross-sections carried along it, each turned as the way turns.
2. Each broad fleshy attachment (kind "area": the glutei on the ilium, the psoas along the lumbar column, the deep
   back muscles along the spine) brought down onto its bone: its deep face (the points facing the expected bones
   within reach, less those with another muscle between) pulled to OFFSET off them, the pull spread smoothly over
   SIGMA_AREA so the muscle moves with its face, a few rounds, each round's moves scaled alike (no crease where the
   largest are held back).
3. The end seated: its deep face, within SEAT_REACH of its bone, pulled or pushed to OFFSET off it, spread over
   SIGMA_SEAT, so a tendon lies on its bone the way it attaches, over an area.
4. Out of every bone and cartilage: each point inside one, or nearer than CLEAR to a bone it does not attach to,
   moved out by the nearest way, spread over SIGMA_OUT.
5. Nothing passes through anything new: for each structure near the muscle (organ, vessel, nerve, other muscle),
   the points of the moved muscle inside it, and its points inside the muscle, against the muscle before it moved;
   where there are more than before, the muscle gives way (its points pushed out of it, spread as in 4), and if it
   still holds more than before the muscle's move is undone and said so.

Every move field is smooth, the same for both sides (the same parameters on each side's own bones), and every
triangle keeps its facing (where one would turn over, the move is smoothed round it). The muscle's triangles stay as
they were (only its points move), so its fibres are laid as before (this step runs before tools/anatomy_fibres.py).
An end's landmark target is the patch's point nearest halfway between the patch's middle and the end (it lands on
the landmark by the shorter way), its normal the mean of the patch's normals near it. The deeper muscles are moved
first and those over them after (a row's "layer"): the gluteus maximus, made from its attachments by
tools/anatomy_gluteus.py, comes last, its deep face brought onto the sacrum and the iliac crest with its shape kept
and kept 5 mm off the midline ("midline"). The eye's muscles are made to the textbook's measures by
tools/anatomy_eyes.py: their rows name it under "moved_by", and they are left alone here.
"""
import argparse
import json
import os
import re
import sys
import time

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import anatomy_attach_audit as audit  # noqa: E402
from anatomy_fibres import read_part, write_part, sha256, normals  # noqa: E402

VERSION = 1
OFFSET = 0.0005        # an attachment's deep face this far off its bone (the periosteum and the tendon's own sheath)
CLEAR = 0.001          # and no nearer than this to a bone it does not attach to
FALLOFF = 4.0          # an end moved t: the move fades along the muscle over FALLOFF * t ...
FADE_MIN = 0.025       # ... at least this long (metres) ...
FADE_MAX = 0.6         # ... and at most this share of the muscle's length
LANDMARK_TOL = 0.003   # an end within this of its landmark is left where it is (seated only)
SEAT_REACH = 0.008     # an end's deep face: its points within this of its bone
SIGMA_SEAT = 0.004     # the seat's moves spread this far
SIGMA_AREA = 0.010     # a fleshy attachment's pull spreads this far (the muscle moves with its face)
SIGMA_OUT = 0.004      # a push out of a bone spreads this far
STEP = 0.002           # no round moves a point more than this (rounds of pull and push)
ROUTE_GRID = 0.002     # the routing grid's cell
ROUTE_SHARE = 1.5      # a routed end: its last ROUTE_SHARE times the move's length is carried along the new way ...
ROUTE_MIN = 0.05       # ... at least this long
NORMAL_REACH = 0.008   # a landmark's normal: the mean of its patch's normals this near the target
SIDE_DEPTH = 0.025     # a point this far or less behind a patch it must stay in front of is brought back ("keep_side")
SIDE_REACH = 0.07      # ... and with it the muscle over that spot of the patch, this far above it at most
TURNS = 5              # out of the bones, the bones out of it, no triangle turned: in turn, at most this often
FACE_ROUNDS = 12       # a fleshy attachment's rounds of pull, at most (it stops when the face is on)


# MARK: small pieces

def smoothstep(x):
    """0 below 0, 1 above 1, between them the quintic 10x^3 - 15x^4 + 6x^5 (flat to the second derivative)."""
    x = np.clip(x, 0.0, 1.0)
    return x * x * x * (10 - 15 * x + 6 * x * x)


def welded(v, f):
    """The mesh with its points at one place made one (to a micrometre), and each original point's welded index."""
    key = np.round(np.asarray(v, float) * 1e6).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    fw = inv[np.asarray(f, np.int64)]
    fw = fw[(fw[:, 0] != fw[:, 1]) & (fw[:, 1] != fw[:, 2]) & (fw[:, 2] != fw[:, 0])]
    return np.asarray(v, float)[first], fw, inv


def spread(q, src, D, sigma, cell=0.002):
    """The moves D asked at the points src carried to the points q: pooled per cell, each point within 3 sigma of
    one taking their Gaussian-weighted mean, in full at the sources and fading as a Gaussian of its distance from
    the nearest of them (as tools/anatomy_gaps.py's spread_moves, by area)."""
    out = np.zeros_like(q)
    if not len(src):
        return out
    _, c = np.unique(np.floor(src / cell).astype(np.int64), axis=0, return_inverse=True)
    c = c.reshape(-1)
    wt = np.bincount(c)
    sp = np.stack([np.bincount(c, weights=src[:, k]) for k in range(3)], 1) / wt[:, None]
    sd = np.stack([np.bincount(c, weights=D[:, k]) for k in range(3)], 1) / wt[:, None]
    r, _ = cKDTree(sp).query(q, distance_upper_bound=3 * sigma)
    near = np.flatnonzero(np.isfinite(r))
    ss = (sp * sp).sum(1)
    chunk = max(1, int(4e6 // max(len(sp), 1)))
    for i in range(0, len(near), chunk):
        idx = near[i:i + chunk]
        qq = q[idx]
        d2 = np.maximum((qq * qq).sum(1)[:, None] + ss[None] - 2 * qq @ sp.T, 0.0)
        g = np.exp(-d2 / (2 * sigma ** 2)) * wt
        out[idx] = (g @ sd) / np.maximum(g.sum(1), 1e-300)[:, None] * np.exp(-r[idx] ** 2 / (2 * sigma ** 2))[:, None]
    return out


def unfold(p0, p, f, rounds=300, rings=2):
    """The move p - p0 smoothed (each point toward its neighbours' mean move) on the triangles that turn over and a
    few rings round them, until none does, the rings widened while the count stops falling (a fold wider than the
    rings smooths out over a wider patch); returns the points and how many still turn."""
    import scipy.sparse as sp
    e = np.unique(np.sort(np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1), axis=0)
    adj = sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(p), len(p)))
    adj = (adj + adj.T).tocsr()
    deg = np.maximum(np.asarray(adj.sum(1)).ravel(), 1)
    D = p - p0
    n0 = np.cross(p0[f[:, 1]] - p0[f[:, 0]], p0[f[:, 2]] - p0[f[:, 0]])
    best, still = None, 0
    for _ in range(rounds):
        q = p0 + D
        n1 = np.cross(q[f[:, 1]] - q[f[:, 0]], q[f[:, 2]] - q[f[:, 0]])
        bad = np.einsum("ij,ij->i", n0, n1) < 0.2 * np.linalg.norm(n0, axis=1) * np.linalg.norm(n1, axis=1)
        if not bad.any():
            break
        if best is None or bad.sum() < best:
            best, still = int(bad.sum()), 0
        else:
            still += 1
            if still >= 25 and rings < 12:
                rings, still = rings + 2, 0
        sel = np.zeros(len(p), bool)
        sel[f[bad].ravel()] = True
        for _ in range(rings):
            sel |= (adj @ sel.astype(float)) > 0
        mean = (adj @ D) / deg[:, None]
        D[sel] = 0.5 * D[sel] + 0.5 * mean[sel]
    q = p0 + D
    return q, flipped(p0, q, f)


def flipped(v0, v1, f):
    """How many triangles face more than 90 degrees from where they faced."""
    n0 = np.cross(v0[f[:, 1]] - v0[f[:, 0]], v0[f[:, 2]] - v0[f[:, 0]])
    n1 = np.cross(v1[f[:, 1]] - v1[f[:, 0]], v1[f[:, 2]] - v1[f[:, 0]])
    return int((np.einsum("ij,ij->i", n0, n1) < 0).sum())


class Shape(audit.Muscle):
    """A muscle's mesh as it now stands, its points in the order given (audit.Muscle welds them, which would
    reorder points once they move), with its normals and its length coordinate."""

    def __init__(self, name, v, f, u=None):
        self.name, self.v, self.f, self.u = name, v, f, u
        self.vn, _ = normals(v, f)


# MARK: the bones round a muscle

class Bones:
    """The solids a muscle is moved against: distances to them, the nearest point and its outward normal, and
    which points lie inside one."""

    def __init__(self, solids):
        self.solids = list(solids)

    def nearest(self, q, reach, among=None):
        """Per point: the distance to the nearest of the solids (all, or `among`) within reach (inf beyond), the
        nearest sample, its normal, and the solid's index."""
        d = np.full(len(q), np.inf)
        p = np.zeros((len(q), 3))
        n = np.zeros((len(q), 3))
        k = np.full(len(q), -1)
        for i, s in enumerate(self.solids):
            if among is not None and s.name not in among:
                continue
            near = s.near(q, reach)
            if not near.any():
                continue
            idx = np.flatnonzero(near)
            dd, j = s.tree().query(q[idx], distance_upper_bound=reach)
            ok = np.isfinite(dd)
            better = ok & (dd < d[idx])
            sel = idx[better]
            d[sel], p[sel], n[sel], k[sel] = dd[better], s.p[j[better]], s.n[j[better]], i
        return d, p, n, k

    def inside(self, q, least=0.0002, sign_only=False):
        """Per point: how deep it lies inside a solid (0 outside), the nearest sample of that solid and its normal;
        inside behind the nearest sample (against its outward normal), confirmed by the winding number unless
        sign_only (a routing grid's cells, where a rare wrong cell does not matter)."""
        dep = np.zeros(len(q))
        p = np.zeros((len(q), 3))
        n = np.zeros((len(q), 3))
        for s in self.solids:
            box = s.near(q, 0.0)
            if not box.any():
                continue
            idx = np.flatnonzero(box)
            dd, j = s.tree().query(q[idx])
            behind = np.einsum("ij,ij->i", q[idx] - s.p[j], s.n[j]) < 0
            cand = behind & (dd > least)
            if not cand.any():
                continue
            ci = idx[cand]
            ins = np.ones(len(ci), bool) if sign_only else audit.winding(q[ci], s.v, s.f) > 0.5
            ci, dd2, jj = ci[ins], dd[cand][ins], j[cand][ins]
            deeper = dd2 > dep[ci]
            ci, dd2, jj = ci[deeper], dd2[deeper], jj[deeper]
            dep[ci], p[ci], n[ci] = dd2, s.p[jj], s.n[jj]
        return dep, p, n


# MARK: the muscle's length

class Line:
    """A muscle's centre line: the mean of its points in bins of its length coordinate u, smoothed, with each
    point's arc position along it."""

    def __init__(self, v, u, bins=48):
        edges = np.linspace(0, 1, bins + 1)
        k = np.clip(np.digitize(u, edges) - 1, 0, bins - 1)
        mid = (edges[:-1] + edges[1:]) / 2
        have = np.array([(k == i).sum() >= 3 for i in range(bins)])
        c = np.array([v[k == i].mean(0) if have[i] else np.zeros(3) for i in range(bins)])
        c = np.stack([np.interp(mid, mid[have], c[have, j]) for j in range(3)], 1)
        for _ in range(3):
            c[1:-1] = 0.25 * c[:-2] + 0.5 * c[1:-1] + 0.25 * c[2:]
        self.u, self.c = mid, c
        seg = np.linalg.norm(np.diff(c, axis=0), axis=1)
        self.s = np.r_[0.0, np.cumsum(seg)]
        self.length = float(self.s[-1])
        r = np.array([np.median(np.linalg.norm(v[k == i] - c[i], axis=1)) if have[i] else np.nan for i in range(bins)])
        self.r = np.interp(mid, mid[have], r[have])

    def at(self, u):
        return np.stack([np.interp(u, self.u, self.c[:, j]) for j in range(3)], -1)

    def arc(self, u):
        return np.interp(u, self.u, self.s)

    def radius(self, u):
        return np.interp(u, self.u, self.r)

    def tangent(self, u, h=0.02):
        t = self.at(np.clip(u + h, 0, 1)) - self.at(np.clip(u - h, 0, 1))
        return t / np.maximum(np.linalg.norm(t, axis=-1, keepdims=True), 1e-12)


def rotation(a, b):
    """The smallest rotation taking the unit vector a to b (3x3)."""
    v = np.cross(a, b)
    c = float(a @ b)
    if c < -0.999999:
        x = np.cross(a, [1.0, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1.0, 0])
        x /= np.linalg.norm(x)
        return 2 * np.outer(x, x) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx / (1 + c)


# MARK: routing an end round a bone

def route(a, a_dir, e, bones, clear, grid=ROUTE_GRID, pad=0.03, soft=()):
    """The shortest way from a to e keeping `clear` (metres, a function of the share of the way gone, 0 to 1) off the
    bones, leaving a along a_dir: Dijkstra on a grid of cells `grid` across (26 neighbours), each cell's cost its
    length, more near a bone (or a soft structure: soft, a list of solids passed only at a cost), then drawn taut and
    smooth. Returns the way's points (a first, e last) or None if there is none."""
    import scipy.sparse as sp
    from scipy.sparse.csgraph import dijkstra
    lead = a + a_dir * 0.006
    lo = np.minimum(np.minimum(a, e), lead) - pad
    hi = np.maximum(np.maximum(a, e), lead) + pad
    shape = np.ceil((hi - lo) / grid).astype(int) + 1
    if np.prod(shape) > 2_000_000:
        return None
    ii = np.stack(np.meshgrid(*[np.arange(s) for s in shape], indexing="ij"), -1).reshape(-1, 3)
    P = lo + ii * grid
    d, _, _, _ = bones.nearest(P, 0.03)
    dep, _, _ = bones.inside(P, least=0.0, sign_only=True)
    d = np.where(dep > 0, -dep, d)
    total = np.linalg.norm(e - a) + 1e-9
    # how far along the way a cell is, roughly: its share of the straight way's length
    share = np.clip(((P - a) @ (e - a)) / total ** 2, 0, 1)
    need = clear(share)
    free = d >= need * 0.85
    near_e = np.linalg.norm(P - e, axis=1) < 3 * grid
    free |= near_e & (dep <= 0)
    cost = 1.0 + 6.0 * np.clip((need - d) / np.maximum(need, 1e-6), 0, 1)
    for s in soft:
        ds = s.distance(P, upper=0.01)
        cost += 3.0 * np.clip(1 - ds / 0.006, 0, 1)
    index = -np.ones(len(P), np.int64)
    index[free] = np.arange(free.sum())
    grid_idx = index.reshape(tuple(shape))
    rows, cols, vals = [], [], []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if (dx, dy, dz) <= (0, 0, 0):
                    continue
                s0 = tuple(slice(max(0, -o), shape[k] - max(0, o)) for k, o in enumerate((dx, dy, dz)))
                s1 = tuple(slice(max(0, o), shape[k] - max(0, -o)) for k, o in enumerate((dx, dy, dz)))
                g0, g1 = grid_idx[s0].ravel(), grid_idx[s1].ravel()
                ok = (g0 >= 0) & (g1 >= 0)
                g0, g1 = g0[ok], g1[ok]
                length = grid * np.sqrt(dx * dx + dy * dy + dz * dz)
                c0 = cost.reshape(tuple(shape))[s0].ravel()[ok]
                c1 = cost.reshape(tuple(shape))[s1].ravel()[ok]
                rows.append(g0)
                cols.append(g1)
                vals.append(length * (c0 + c1) / 2)
    n = int(free.sum())
    G = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsr()
    Pf = P[free]
    start = int(np.argmin(np.linalg.norm(Pf - lead, axis=1)))
    goal = int(np.argmin(np.linalg.norm(Pf - e, axis=1)))
    dist, pred = dijkstra(G, directed=False, indices=start, return_predecessors=True)
    if not np.isfinite(dist[goal]):
        return None
    path = [goal]
    while path[-1] != start:
        path.append(int(pred[path[-1]]))
    way = np.vstack([a, Pf[path[::-1]], e])
    return taut(way, a, a_dir, e, bones, clear)


def taut(way, a, a_dir, e, bones, clear, n=40, rounds=200):
    """A way resampled to n points and drawn taut and smooth, a and e held, its first step along a_dir, each point
    kept clear of the bones."""
    def resample(w, n):
        s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(w, axis=0), axis=1))]
        t = np.linspace(0, s[-1], n)
        return np.stack([np.interp(t, s, w[:, j]) for j in range(3)], 1)

    w = resample(way, n)
    ghost = a - a_dir * np.linalg.norm(w[1] - w[0])
    share = np.linspace(0, 1, n)
    need = clear(share)
    for it in range(rounds):
        prev = np.vstack([ghost, w[:-1]])
        nxt = np.vstack([w[1:], e])
        w[1:-1] = w[1:-1] + 0.5 * ((prev[1:-1] + nxt[1:-1]) / 2 - w[1:-1])
        d, p, nn, _ = bones.nearest(w, 0.04)
        dep, pin, nin = bones.inside(w, least=0.0)
        ins = dep > 0
        d = np.where(ins, -dep, d)
        p = np.where(ins[:, None], pin, p)
        nn = np.where(ins[:, None], nin, nn)
        short = (d < need) & np.isfinite(d)
        short[0] = short[-1] = False
        w[short] = p[short] + nn[short] * need[short, None]
        if it % 20 == 19:
            w = np.vstack([w[0], resample(w, n)[1:-1], w[-1]])
    return w


def sweep(v, u, line, ends_at_one, way, u_a):
    """The muscle's points past u_a (toward its end at u=1 if ends_at_one, else toward u=0) carried from the old
    centre line onto the way: each point's cross-section moved to the way's point at the same share of the length
    past u_a, turned as the way's direction turns from the line's, the change brought in smoothly over the first
    quarter."""
    out = v.copy()
    if ends_at_one:
        past = u > u_a
        share = (u[past] - u_a) / max(1 - u_a, 1e-9)
    else:
        past = u < u_a
        share = (u_a - u[past]) / max(u_a, 1e-9)
    s_way = np.r_[0, np.cumsum(np.linalg.norm(np.diff(way, axis=0), axis=1))]
    s_way /= s_way[-1]
    W = np.stack([np.interp(share, s_way, way[:, j]) for j in range(3)], 1)
    # the way's direction at each share, and the line's at each point's own u
    dW = np.gradient(way, s_way, axis=0)
    dW /= np.maximum(np.linalg.norm(dW, axis=1, keepdims=True), 1e-12)
    T_new = np.stack([np.interp(share, s_way, dW[:, j]) for j in range(3)], 1)
    T_new /= np.maximum(np.linalg.norm(T_new, axis=1, keepdims=True), 1e-12)
    up = u[past]
    T_old = line.tangent(up)
    if not ends_at_one:
        T_old = -T_old
    C_old = line.at(up)
    moved = np.empty_like(v[past])
    for i in range(len(up)):
        R = rotation(T_old[i], T_new[i])
        moved[i] = W[i] + R @ (v[past][i] - C_old[i])
    b = smoothstep(share / 0.25)[:, None]
    out[past] = v[past] + b * (moved - v[past])
    return out


# MARK: one muscle

def target_of(marks, keys, bones, exp, c=None):
    """The landmark an end goes to (the first of the row's landmarks found): the patch's point nearest the middle
    between the patch's middle and the end's centre c (so the end lands on the patch, on its near part: no longer
    move than it takes), and the bone's outward normal there, the mean of the patch's normals within NORMAL_REACH
    (one sample's normal at a rim or an endplate's edge can face anywhere)."""
    for key in keys:
        if key in marks and len(marks[key][0]) >= 3:
            P = marks[key][0]
            mid = P.mean(0)
            # a broad patch (a facet): aimed toward the end, up to halfway; a small one (the lesser trochanter, under
            # 2 cm across): its middle
            R = float(np.max(np.linalg.norm(P - mid, axis=1)))
            share = 0.0 if c is None else float(np.clip((R - 0.010) / max(R, 1e-9), 0.0, 0.5))
            aim = mid + share * (np.zeros(3) if c is None else c - mid)
            i = int(np.argmin(np.linalg.norm(P - aim, axis=1)))
            d, _, n, _ = bones.nearest(P, 0.002, among=exp)
            ok = np.isfinite(d)
            if not ok[i]:
                continue
            near = ok & (np.linalg.norm(P - P[i], axis=1) < NORMAL_REACH)
            nT = n[near].mean(0) if near.sum() >= 3 else n[i]
            nT = nT / max(np.linalg.norm(nT), 1e-12)
            return key, P[i], nT, P
    return None, None, None, None


def midline_of(points):
    """The body's midline (x) as the suite finds it: the middle of the sacrum's width height by height over its
    lower half, the median of eight heights (tools/anatomy_gluteus.py's and the suite's midline)."""
    y0 = points[:, 1].min()
    y1 = y0 + 0.5 * (points[:, 1].max() - y0)
    mids = []
    for k in range(8):
        y = y0 + 0.005 + (y1 - y0 - 0.005) * k / 7
        band = points[np.abs(points[:, 1] - y) < 0.003, 0]
        if len(band) >= 3:
            mids.append((band.min() + band.max()) / 2)
    return float(np.median(mids)) if mids else float(points[:, 0].mean())


def side_patches(checked, marks, table, body, side, solids, names):
    """The patches of bone a muscle must stay in front of: for each end of its row marked "keep_side", its first
    landmark's points with the bone's outward normals there."""
    out = []
    for role, e in checked:
        if not e.get("keep_side"):
            continue
        exp = audit.expected(table, e["bones"], body, side, names)
        expb = Bones([solids[n] for n in exp if n in solids])
        for key in e.get("landmarks", []):
            if key in marks and len(marks[key][0]) >= 10 and expb.solids:
                P = marks[key][0]
                d, _, n, _ = expb.nearest(P, 0.002, among=exp)
                ok = np.isfinite(d)
                if ok.sum() >= 10:
                    depth = e["keep_side"] if not isinstance(e["keep_side"], bool) else SIDE_DEPTH
                    out.append((P[ok], n[ok], float(depth)))
                break
    return out


def own_side(p, patches, rounds=12):
    """The muscle's points straight behind a patch of the bone it lies on, by the patch's depth at most (in the bone
    or beyond it: an iliacus through the iliac wing, a gluteus lying in it) brought back in front of the patch, to
    OFFSET off it, by columns: over each spot of the patch the whole thickness of the muscle moves along the patch's
    normal by what its deepest point there needs (so a sheet lying in the bone is shifted out of it whole, neither
    folded nor pressed flat), the need taken at its widest within 4 mm and spread over the patch (SIGMA_AREA, or wider
    for a need so deep that the slope would turn a triangle), fading beyond the patch's edge and 40 to 70 mm above
    it."""
    for P, N, depth in patches:
        tree = cKDTree(P)
        pairs = tree.query_pairs(0.004, output_type="ndarray")
        sigma = None
        for _ in range(rounds):
            d, j = tree.query(p, distance_upper_bound=SIDE_REACH)
            idx = np.flatnonzero(np.isfinite(d))
            if not len(idx):
                break
            v = p[idx] - P[j[idx]]
            h = np.einsum("ij,ij->i", v, N[j[idx]])
            foot = p[idx] - h[:, None] * N[j[idx]]
            off = np.linalg.norm(foot - P[j[idx]], axis=1)
            behind = (h < OFFSET - 0.0002) & (h > -depth) & (off < 0.003)
            if behind.sum() < 3:
                break
            need = np.zeros(len(P))
            np.maximum.at(need, j[idx[behind]], OFFSET - h[behind])
            if len(pairs):
                wide = need.copy()
                np.maximum.at(wide, pairs[:, 0], need[pairs[:, 1]])
                np.maximum.at(wide, pairs[:, 1], need[pairs[:, 0]])
                need = wide
            if need.max() < 0.0002:
                break
            if sigma is None:
                sigma = max(SIGMA_AREA, 1.5 * float(need.max()))
            D = spread(foot, P, N * need[:, None], sigma)
            D *= (1.0 - smoothstep((h - 0.04) / 0.03))[:, None]
            p = p.copy()
            p[idx] += D
    return p


def behind_patches(p, patches):
    """How many of the points lie more than 1 mm behind a patch they must stay in front of."""
    n = 0
    for P, N, depth in patches:
        d, j = cKDTree(P).query(p, distance_upper_bound=depth)
        idx = np.flatnonzero(np.isfinite(d))
        v = p[idx] - P[j[idx]]
        h = np.einsum("ij,ij->i", v, N[j[idx]])
        off = np.linalg.norm(v - h[:, None] * N[j[idx]], axis=1)
        n += int(((h < -0.001) & (off < 0.003)).sum())
    return n


def off_midline(p, mid, sx, keep, rounds=8):
    """The muscle's points kept `keep` or more from the midline on their own side (sx: +1 left, -1 right): those
    nearer pushed out across it, spread over SIGMA_OUT, a few rounds."""
    for _ in range(rounds):
        gap = sx * (p[:, 0] - mid)
        go = gap < keep
        if not go.any():
            break
        want = np.zeros((int(go.sum()), 3))
        want[:, 0] = sx * (keep + 0.0002 - gap[go])
        D = spread(p, p[go], want, SIGMA_OUT)
        big = np.max(np.linalg.norm(D, axis=1))
        if big < 0.00005:
            break
        p = p + D * min(1.0, STEP / big)
    return p


def plan_ends(m, row, side, body, table, names):
    """The row's ends on this muscle: (role, end, region indices, kind), the primary caps giving u."""
    ends = [("origin", e) for e in row["origin"]] + [("insertion", e) for e in row["insertion"]]
    primary = {}
    for role in ("origin", "insertion"):
        e = next((e for r, e in ends if r == role and e.get("find") and ("cap" in e["find"] or "far" in e["find"])), None)
        primary[role] = audit.find_end(m, e["find"], side) if e else None
    if primary["origin"] is None and primary["insertion"] is not None:
        c = m.v[primary["insertion"]].mean(0) - m.v.mean(0)
        primary["origin"] = m.cap(-c, 0.04)
    if primary["insertion"] is None and primary["origin"] is not None:
        c = m.v[primary["origin"]].mean(0) - m.v.mean(0)
        primary["insertion"] = m.cap(-c, 0.04)
    m.length_between(primary["origin"], primary["insertion"])
    return [(role, e) for role, e in ends if e.get("check", True) and e.get("find")]


def attach_muscle(name, v, f, row, table, body, side, solids, names, marks, soft, others_muscles, trace=None,
                  midline=None):
    """One muscle moved: returns its new points (welded order), the welded triangles and the inverse map, and what
    was done. midline: the body's midline (x), for a row that keeps its muscle off it ("midline": metres)."""
    vw, fw, inv = welded(v, f)
    said = []
    allbones = Bones(list(solids.values()))
    m = audit.Muscle(name, vw, fw)
    checked = plan_ends(m, row, side, body, table, names)
    u = m.u
    line = Line(m.v, u)
    p0 = m.v.copy()
    p = m.v.copy()
    # 1. the ends moved onto their landmarks (or bones)
    for role, e in checked:
        if "face" in e["find"]:
            continue
        exp = audit.expected(table, e["bones"], body, side, names)
        expb = Bones([solids[n] for n in exp if n in solids])
        if not expb.solids:
            continue
        region = np.flatnonzero(audit.find_end(m, e["find"], side))
        if not len(region):
            continue
        tip = p[region]
        key, T, nT, patch = target_of(marks, e.get("landmarks", []) if e.get("to", "landmark") == "landmark" else [],
                                      expb, exp, tip.mean(0))
        if key is not None:
            c = tip.mean(0)
            off = np.min(np.linalg.norm(patch - c, axis=1))
            if off <= LANDMARK_TOL:
                continue
            h = float(np.max((c - tip) @ nT))
            t = T + nT * (OFFSET + h) - c
            if os.environ.get("ATTACH_DEBUG"):
                print(f"      {role}: tip {len(region)} points, centre {np.round(1000 * c, 1)}, target {np.round(1000 * T, 1)} normal {np.round(nT, 2)}, reach {1000 * h:.1f} mm, move {np.round(1000 * t, 1)} ({1000 * np.linalg.norm(t):.1f} mm)")
            what = f"{role} to the {key.split('.', 1)[1].replace('_', ' ').replace('.', ' ')} ({1000 * off:.0f} mm off)"
        else:
            d, q, n, _ = expb.nearest(tip, 0.05)
            dep, qi, ni = expb.inside(tip)
            ok = np.isfinite(d)
            if not ok.any():
                continue
            gap = np.quantile(np.where(dep > 0, -dep, d)[ok], 0.1)
            if -audit.DEEP <= gap <= audit.NEAR:
                continue
            # the tip's nearest tenth brought to OFFSET off the bone
            close = np.argsort(np.where(dep > 0, -dep, d))[:max(3, len(tip) // 10)]
            t = np.median(q[close] + n[close] * OFFSET - tip[close], axis=0)
            what = f"{role} onto {audit.short(exp[0])} ({1000 * gap:.1f} mm {'off' if gap > 0 else 'in'})"
        ends_at_one = role == "insertion"
        # the move fades with the distance from the end (straight, not along the surface: a thin sheet's two faces
        # then move alike, and with the fade at least FALLOFF times the move no part is ever turned inside out: the
        # field's gradient stays under 1.875 / FALLOFF); the iliacus is farther from the psoas's top than any fade
        span = min(max(FALLOFF * np.linalg.norm(t), FADE_MIN), FADE_MAX * line.length)
        ell, _ = cKDTree(p[region]).query(p)
        w = smoothstep(1 - ell / span)
        moved = p + w[:, None] * t
        # does the move carry the muscle into a bone? then the end is routed round it
        going = np.flatnonzero(w > 0.02)
        dep0, _, _ = allbones.inside(p[going], least=0.001)
        dep1, _, _ = allbones.inside(moved[going], least=0.001)
        newly = (dep1 > 0.003) & (dep0 <= 0.001)
        if newly.sum() > max(10, 0.02 * len(going)):
            # the last part only is routed: as far from the end as the move is long and half as far again (at least
            # ROUTE_MIN), the rest of the muscle staying where it is
            routed = np.flatnonzero(ell < max(ROUTE_SHARE * np.linalg.norm(t), ROUTE_MIN))
            u_a = float(np.quantile(u[routed], 0.02) if ends_at_one else np.quantile(u[routed], 0.98))
            a = line.at(np.array([u_a]))[0]
            a_dir = line.tangent(np.array([u_a]))[0] * (1 if ends_at_one else -1)
            e_pt = line.at(np.array([1.0 if ends_at_one else 0.0]))[0] + t
            r_a = float(line.radius(np.array([u_a]))[0])
            r_e = max(float(np.max(np.linalg.norm(tip - tip.mean(0), axis=1))) * 0.5, 0.002)
            clear = lambda s: (r_a + (r_e - r_a) * np.clip(s, 0, 1)) * 0.8 + OFFSET
            way = route(a, a_dir, e_pt, allbones, clear, soft=soft)
            if way is not None:
                moved = sweep(p, u, line, ends_at_one, way, u_a)
                what += (f", routed round the bone ({newly.sum()} points would have gone in; a "
                         f"{1000 * np.sum(np.linalg.norm(np.diff(way, axis=0), axis=1)):.0f} mm way)")
            else:
                what += ", no way round the bone found: moved straight"
        p = moved
        said.append(what + f", the move fading over {1000 * span:.0f} mm")
    # 1b. back onto its own side of a thin bone it straddles (the iliacus and the iliac wing)
    patches = side_patches(checked, marks, table, body, side, solids, names)
    if patches:
        was = behind_patches(p, patches)
        p = own_side(p, patches)
        said.append(f"{was} points behind the bone's face it lies on brought back in front of it ({behind_patches(p, patches)} left)")
    if trace:
        trace("ends moved", p0, p, fw)
    # 2. the fleshy attachments brought onto their bones
    occl = [o for o in others_muscles if o.name != name]
    row_bones = set()
    for role, e in checked:
        row_bones |= set(audit.expected(table, e["bones"], body, side, names))
    for role, e in checked:
        if "face" not in e["find"]:
            continue
        exp = audit.expected(table, e["bones"], body, side, names)
        expb = Bones([solids[n] for n in exp if n in solids])
        if not expb.solids:
            continue
        u0, u1 = e["find"]["face"]
        reach = e["find"].get("reach", 0.012)
        between = [solids[n] for n in sorted(row_bones - set(exp)) if n in solids]
        before = None
        for rnd in range(FACE_ROUNDS):
            mm = Shape(name, p, fw, u)
            sel = (u >= u0) & (u <= u1)
            face = audit.deep_face(mm, sel, expb.solids, reach, occl, between)
            if len(face) < 10:
                break
            d, q, n, _ = expb.nearest(p[face], reach + 0.002)
            dep, qi, ni = expb.inside(p[face])
            ins = dep > 0
            q = np.where(ins[:, None], qi, q)
            n = np.where(ins[:, None], ni, n)
            gap = np.where(ins, -dep, d)
            if before is None:
                before = float(np.median(gap))
            elif abs(float(np.median(gap)) - OFFSET) < 0.0004:
                break
            want = (q + n * OFFSET) - p[face]
            far = gap > OFFSET + 0.0003
            near_in = gap < OFFSET - 0.0003
            go = far | near_in
            if go.sum() < 5:
                break
            D = spread(p, p[face[go]], want[go], SIGMA_AREA)
            big = np.max(np.linalg.norm(D, axis=1))
            if big < 0.0002:
                break
            p = p + D * min(1.0, STEP / big)
        if before is not None:
            mm = Shape(name, p, fw, u)
            face = audit.deep_face(mm, (u >= u0) & (u <= u1), expb.solids, reach, occl, between)
            after = float(np.median(expb.nearest(p[face], reach + 0.002)[0])) if len(face) else float("nan")
            said.append(f"{role} face on {audit.short(exp[0])}{'...' if len(exp) > 1 else ''}: {1000 * before:.1f} -> {1000 * after:.1f} mm")
    if trace:
        trace("faces brought on", p0, p, fw)
    # 3. the ends seated on their bones
    for role, e in checked:
        if "face" in e["find"]:
            continue
        exp = audit.expected(table, e["bones"], body, side, names)
        expb = Bones([solids[n] for n in exp if n in solids])
        if not expb.solids:
            continue
        mm = Shape(name, p, fw, u)
        region = np.flatnonzero(audit.find_end(mm, e["find"], side))
        if not len(region):
            continue
        for rnd in range(12):
            d, q, n, _ = expb.nearest(p, SEAT_REACH)
            dep, qi, ni = expb.inside(p)
            ins = dep > 0
            # the end's deep face: the end region's points within reach, and the points near them facing the bone
            ends = np.zeros(len(p), bool)
            ends[region] = True
            near_end = np.isfinite(d) | ins
            cand = np.flatnonzero(near_end & ends)
            if not len(cand):
                break
            q = np.where(ins[:, None], qi, q)[cand]
            n = np.where(ins[:, None], ni, n)[cand]
            gap = np.where(ins, -dep, d)[cand]
            mm = Shape(name, p, fw, u)
            facing = np.einsum("ij,ij->i", q - p[cand], mm.vn[cand]) > 0.3 * np.linalg.norm(q - p[cand], axis=1)
            take = (facing & (gap > OFFSET + 0.0003)) | (gap < OFFSET - 0.0003)
            if os.environ.get("ATTACH_DEBUG"):
                print(f"      seat {role} round {rnd}: region {len(region)} near {len(cand)} facing {int(facing.sum())} take {int(take.sum())} gap median {1000 * np.median(gap):.1f} mm")
            if take.sum() < 3:
                break
            want = q[take] + n[take] * OFFSET - p[cand[take]]
            D = spread(p, p[cand[take]], want, SIGMA_SEAT)
            big = np.max(np.linalg.norm(D, axis=1))
            if big < 0.0002:
                break
            p = p + D * min(1.0, 1.5 * STEP / big)
    if trace:
        trace("ends seated", p0, p, fw)
    # 4. out of every bone and cartilage, and every triangle keeping its facing (where one would turn over, the
    # move smoothed round it), in turn till both hold
    attached = set()
    for role, e in checked:
        attached |= set(audit.expected(table, e["bones"], body, side, names))
    first_turned = None
    keep = row.get("midline")     # the gluteus maximus: the two apart over the coccyx (tools/anatomy_gluteus.py's 5 mm)
    sx = 1.0 if side == "L" else -1.0
    lo, hi = p.min(0) - 0.02, p.max(0) + 0.02
    near_bones = [s for s in allbones.solids if np.all(s.hi > lo) and np.all(s.lo < hi)]
    for turn in range(TURNS):
        # first back in front of the face it lies on (a sheet of muscle in the middle of a thin bone is not got out
        # by the nearest way: its points part to either side), then out of every bone by the nearest way
        if patches:
            p = own_side(p, patches)
        p = out_of_bones(p, allbones, attached, rounds=16)
        # a bone's tip through the muscle is dealt with only once the muscle's own points are out of the bones: while
        # a thin muscle still lies in a bone, the bone's points in it are nearer its outer face, and pushing that
        # face in past them would drive the muscle farther into the bone
        dep, _, _ = allbones.inside(p, least=0.001)
        n_in, n_through = int((dep > 0.001).sum()), 0
        if n_in <= max(3, 0.002 * len(p)):
            p = bones_out(p, fw, near_bones, rounds=8)
            p = out_of_bones(p, allbones, attached, rounds=4)
            n_through = through(p, fw, near_bones)
        if keep and midline is not None:
            p = off_midline(p, midline, sx, keep)
        if trace:
            trace(f"out of the bones ({n_in} in, {n_through} through)", p0, p, fw)
        turned = flipped(p0, p, fw)
        first_turned = turned if first_turned is None else max(first_turned, turned)
        if turned:
            p, left = unfold(p0, p, fw)
            if trace:
                trace("unfolded", p0, p, fw)
        elif n_in <= 3 and n_through <= 3:
            break
    if first_turned:
        said.append(f"{first_turned} triangles would have turned over: the move smoothed round them ({flipped(p0, p, fw)} left)")
    dep, _, _ = allbones.inside(p, least=0.001)
    if (dep > 0.001).any():
        said.append(f"{int((dep > 0.001).sum())} points still over 1 mm inside a bone (deepest {1000 * dep.max():.1f} mm)")
    poking = through(p, fw, near_bones)
    if poking:
        said.append(f"{poking} bone points still over 1 mm inside the muscle")
    moved_mm = 1000 * np.linalg.norm(p - p0, axis=1)
    said.append(f"points moved: median {np.median(moved_mm):.1f} mm, most {moved_mm.max():.1f} mm")
    return p, fw, inv, said


def bone_points_in(p, f, solids, least=0.0005, reach=0.015):
    """The bones' sample points inside the muscle (deeper than `least`), with how deep, and the muscle's surface
    samples nearest them (points, outward normals)."""
    me = audit.Solid("me", p, f)
    tree = me.tree()
    lo, hi = p.min(0), p.max(0)
    pts, deps = [], []
    for s in solids:
        s.tree()
        box = np.all((s.p > lo) & (s.p < hi), axis=1)
        if not box.any():
            continue
        q = s.p[box]
        dd, _ = tree.query(q, distance_upper_bound=reach)
        q = q[np.isfinite(dd)]
        if not len(q):
            continue
        d = me.depth(q, least=least)
        if (d > 0).any():
            pts.append(q[d > 0])
            deps.append(d[d > 0])
    if not pts:
        return np.zeros((0, 3)), np.zeros(0), np.zeros((0, 3)), np.zeros((0, 3))
    q, d = np.vstack(pts), np.concatenate(deps)
    _, j = tree.query(q)
    return q, d, me.p[j], me.n[j]


def bones_out(p, f, solids, rounds=6):
    """A bone through the muscle (a transverse process's tip through the psoas, its vertices all outside the bone)
    put back outside it: the muscle's surface nearest each bone point inside it moved in past that point (along the
    surface's inward normal), spread over SIGMA_OUT, a few rounds."""
    for _ in range(rounds):
        q, d, mp, mn = bone_points_in(p, f, solids)
        if not len(q):
            break
        D = spread(p, mp, -mn * (d + 0.0003)[:, None], SIGMA_OUT)
        big = np.max(np.linalg.norm(D, axis=1))
        if big < 0.0001:
            break
        p = p + D * min(1.0, STEP / big)
    return p


def through(p, f, solids):
    """How many bone points lie more than 1 mm inside the muscle."""
    q, d, _, _ = bone_points_in(p, f, solids, least=0.001)
    return int(len(q))


def out_of_bones(p, bones, attached, rounds=12):
    """The muscle's points moved out of every bone (to OFFSET off it) and off the bones it does not attach to (to
    CLEAR), the nearest way, spread over SIGMA_OUT, a few rounds."""
    for rnd in range(rounds):
        dep, qi, ni = bones.inside(p)
        d, q, n, k = bones.nearest(p, CLEAR)
        close = np.isfinite(d) & (d < CLEAR) & np.array([bones.solids[i].name not in attached if i >= 0 else False for i in k])
        ins = dep > 0.0002
        go = ins | close
        if not go.any():
            break
        want = np.where(ins[:, None], qi + ni * OFFSET, q + n * CLEAR) - p
        D = spread(p, p[go], want[go], SIGMA_OUT)
        big = np.max(np.linalg.norm(D, axis=1))
        if big < 0.0001:
            break
        p = p + D * min(1.0, STEP / big)
    return p


# MARK: nothing through anything

def overlaps(p, f, others, reach=0.0):
    """How many of the muscle's points lie inside each other closed structure near it, and how many of theirs
    inside it: {name: (in it, its in us)}."""
    out = {}
    lo, hi = p.min(0), p.max(0)
    me = audit.Solid("me", p, f)
    for o in others:
        if np.any(o.hi < lo) or np.any(o.lo > hi):
            continue
        a = o.depth(p, least=0.0003)
        o.tree()
        box = np.all((o.p > lo) & (o.p < hi), axis=1)
        b = me.depth(o.p[box], least=0.0003) if box.any() else np.zeros(0)
        na, nb = int((a > 0).sum()), int((b > 0).sum())
        if na or nb:
            out[o.name] = (na, nb)
    return out


# MARK: the atlas

def remake(folder, quiet=False, only=None, table=None):
    """Moves the ends of every muscle the attachment table has a row for (but those whose row names another tool
    under fix) in both bodies of `folder`'s atlas; does nothing to a muscle marked attached already. Returns what
    it did."""
    table = table or audit.load_table(os.environ.get("ATTACH_TABLE", audit.TABLE))
    only = only or os.environ.get("ATTACH_ONLY")      # a build may move only some (a regular expression on names)
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said, changed_n = [], 0
    for body in manifest["bodies"]:
        t0 = time.time()
        structs = audit.load_body(folder, body)
        names = list(structs)
        solids = {}
        for n, (v, f, pid, tissue, system) in structs.items():
            if tissue in audit.ATTACH_TISSUE or system == "skeletal":
                solids[n] = audit.Solid(n, v, f, tissue)
        bone_solids = {n: s for n, s in solids.items() if s.tissue in ("bone", "cartilage", "tooth") or structs[n][4] == "skeletal"}
        bone_solids = {n: s for n, s in bone_solids.items() if not audit.NOT_OTHER.search(n)}
        muscles = {n: audit.Solid(n, v, f, tissue) for n, (v, f, pid, tissue, system) in structs.items()
                   if system == "muscular" and tissue == "muscle"}
        soft = {n: None for n, (v, f, pid, tissue, system) in structs.items()
                if n not in bone_solids and n not in muscles and system != "integumentary"}
        marks_cache = {}
        by_part = {}
        for part in body["parts"]:
            for i, st in enumerate(part["structures"]):
                by_part[st["node"]] = (part, i, st)
        todo, pending = [], set()
        for n, (v, f, pid, tissue, system) in structs.items():
            if not audit.is_muscle(n, system, tissue):
                continue
            row = audit.row_for(table, n)
            if row is None or row.get("moved_by") or row["kind"] in ("smooth", "cardiac"):
                continue
            if by_part[n][2].get("attached") == VERSION:
                continue
            pending.add(n)          # has a row and is still where the scans left it
            if only and not re.search(only, n):
                continue
            todo.append((n, row))
        if not todo:
            continue
        # the deep muscles first, those over them after (the gluteus maximus over the medius), each checked against
        # the others as they then stand
        todo.sort(key=lambda nr: (nr[1].get("layer", 0), nr[0]))
        sac = [n for n in audit.expected(table, ["sacrum"], body["id"], None, names)]
        midline = midline_of(np.asarray(structs[sac[0]][0], float)) if sac else None
        new = {}
        for n, row in todo:
            v, f, pid, tissue, system = structs[n]
            side = audit.side_of(n) if row.get("sided", True) else None
            marks = marks_cache.setdefault(side, audit.landmarks(solids, table, body["id"], side or "L"))
            near_soft = []
            lo, hi = np.asarray(v).min(0) - 0.01, np.asarray(v).max(0) + 0.01
            for sn in soft:
                sv = structs[sn][0]
                if np.all(sv.max(0) > lo) and np.all(sv.min(0) < hi):
                    if soft[sn] is None:
                        soft[sn] = audit.Solid(sn, sv, structs[sn][1], structs[sn][3])
                    near_soft.append(soft[sn])
            others = [muscles[o] for o in muscles if o != n]
            # given way to: the muscles that stand where they will (no row, another tool's, or moved already); one
            # still to be moved gives way to this one when its turn comes
            settled = [muscles[o] for o in muscles if o != n and (o in new or o not in pending)]
            p, fw, inv, what = attach_muscle(n, v, f, row, table, body["id"], side, bone_solids, names, marks,
                                             near_soft, others, None, midline=midline)
            # nothing new through anything: the soft structures and the other muscles near it
            vw0, _, _ = welded(v, f)
            near = [s for s in near_soft + settled if np.all(s.hi > p.min(0)) and np.all(s.lo < p.max(0))]
            was = overlaps(vw0, fw, near)
            now = overlaps(p, fw, near)
            worse = {k: (now[k], was.get(k, (0, 0))) for k in now if sum(now[k]) > sum(was.get(k, (0, 0))) + 2}
            allb = Bones(list(bone_solids.values()))
            on = set()
            for e in row["origin"] + row["insertion"]:
                on |= set(audit.expected(table, e["bones"], body["id"], side, names))
            for turn in range(3):
                if not worse:
                    break
                if os.environ.get("ATTACH_DEBUG"):
                    print(f"      gives way, turn {turn}: {dict((audit.short(k), v) for k, v in worse.items())}; in bone {int((allb.inside(p, least=0.001)[0] > 0.001).sum())}", flush=True)
                # giving way may push it into a bone: out of the bones again, no triangle turned, and counted anew
                p = give_way(p, fw, [s for s in near if s.name in worse], vw0)
                p = out_of_bones(p, allb, on)
                p, _ = unfold(vw0, p, fw)
                now = overlaps(p, fw, near)
                worse = {k: (now[k], was.get(k, (0, 0))) for k in now if sum(now[k]) > sum(was.get(k, (0, 0))) + 2}
            if os.environ.get("ATTACH_DEBUG"):
                print(f"      after giving way: in bone {int((allb.inside(p, least=0.001)[0] > 0.001).sum())}", flush=True)
            if worse:
                what.append("new overlaps left: " + ", ".join(f"{audit.short(k)} {a[0]}+{a[1]} (was {b[0]}+{b[1]})" for k, (a, b) in worse.items()))
            new[n] = p[inv]
            # the moved muscle is what the next one is checked against
            muscles[n] = audit.Solid(n, p, fw, tissue)
            said.append(f"{body['id']} {audit.short(n)}: " + "; ".join(what))
            if not quiet:
                print("  " + said[-1], flush=True)
        # write the parts that changed
        parts = {}
        for n in new:
            part, i, st = by_part[n]
            parts.setdefault(part["id"], part)
        for pid, part in parts.items():
            fp = os.path.join(folder, part["file"])
            meshes = read_part(fp)
            out = []
            for st, (pv, pf) in zip(part["structures"], meshes):
                if st["node"] in new:
                    out.append((new[st["node"]].astype(np.float32), pf))
                    st["attached"] = VERSION
                    changed_n += 1
                else:
                    out.append((pv, pf))
            lo, hi = write_part(fp, out)
            part["bytes"] = os.path.getsize(fp)
            part["sha256"] = sha256(fp)
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
            fibres = part.pop("fibres", None)
            if fibres and os.path.exists(os.path.join(folder, fibres["file"])):
                os.remove(os.path.join(folder, fibres["file"]))
        if not quiet:
            print(f"  {body['id']}: {len(new)} muscles in {time.time() - t0:.0f} s", flush=True)
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    return f"{changed_n} muscles' ends moved onto their attachments" if changed_n else "the muscles' ends on their attachments already"


def give_way(p, f, solids, p_before, rounds=8):
    """The muscle's points pushed out of the structures it newly runs into (the nearest way out, spread over
    SIGMA_OUT), and the structures' points inside it pushed back out of it by moving the muscle's points near them
    away."""
    for _ in range(rounds):
        moves_at, moves = [], []
        bones = Bones(solids)
        dep, q, n = bones.inside(p, least=0.0002)
        ins = dep > 0
        if ins.any():
            moves_at.append(p[ins])
            moves.append(q[ins] + n[ins] * 0.0003 - p[ins])
        me = audit.Solid("me", p, f)
        for s in solids:
            s.tree()
            box = np.all((s.p > p.min(0)) & (s.p < p.max(0)), axis=1)
            if not box.any():
                continue
            pts = s.p[box]
            d = me.depth(pts, least=0.0002)
            hit = d > 0
            if hit.any():
                # the muscle's surface points nearest those, moved past them (along the muscle's inward normal)
                dd, j = me.tree().query(pts[hit])
                mp, mn = me.p[j], me.n[j]
                moves_at.append(mp)
                moves.append(-mn * (d[hit] + 0.0003)[:, None])
        if not moves_at:
            break
        D = spread(p, np.vstack(moves_at), np.vstack(moves), SIGMA_OUT)
        big = np.max(np.linalg.norm(D, axis=1))
        if big < 0.0001:
            break
        p = p + D * min(1.0, STEP / big)
    return p


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folder")
    ap.add_argument("--only", help="a regular expression on node names")
    ap.add_argument("--table")
    a = ap.parse_args()
    table = audit.load_table(a.table) if a.table else None
    print(remake(a.folder, only=a.only, table=table))


if __name__ == "__main__":
    main()
