#!/usr/bin/env python3
"""Muscles of the atlas made from their attachments, not from a scan's labels.

    tools/anatomy_muscle_build.py <atlas folder>            builds them into the folder's muscular parts
    tools/anatomy_muscle_build.py <atlas folder> --marks out.png     the landmarks it found, to look at

Each muscle is written down the way a textbook gives it (Gray's Anatomy, 1918, public domain): the bone and
the place on it where it arises, the place where it inserts, and the course of its fibres between. From that:

1. The landmarks are found on the body's own bones (`marks`): the lower border of the zygomatic arch, the
   angle, ramus and coronoid process of the mandible, the temporal lines, the mastoid process, the transverse
   processes of the cervical vertebrae, the first ribs, the manubrium, the clavicle, the scapula's upper angle.
2. A muscle is a set of guide fibres from its origin to its insertion, each with half its thickness along the
   way (thin where it is tendon, full in its belly). Between neighbouring guides the fibres are filled in, so a
   broad muscle is a sheet of them. A fibre that would pass through bone is laid on the bone instead.
3. The muscle's body is everything within a fibre's half-thickness of that fibre, less the bones, less every
   muscle built before it (the deep ones first) and less whatever else it must clear, with a hair's gap: so it
   lies on what it lies on, attaches where its fibres end, and passes through nothing.
4. Its surface is taken from that body (marching cubes on a 0.6 mm grid), smoothed without shrinking, and
   brought down to the atlas's triangle sizes. tools/anatomy_fibres.py then draws its fibres from its origin
   to its insertion, which are now where the textbook puts them.
"""
import json
import os
import re
import sys

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anatomy_muscles_more as m                                    # noqa: E402
from anatomy_fibres import read_part, write_part, sha256           # noqa: E402

MARK = "built-1"
H = 0.0006            # the grid the bodies are taken on
GAP = 0.0003          # between a muscle and what it lies on
SKIN_IN = 0.0015      # under the skin by at least this
BONE_PARTS = ("skull", "vertebral-column", "shoulders", "ribs", "sternum", "hyoid")


# ---------------------------------------------------------------- curves and sheets

def along(P, n):
    """n points evenly along the polyline P."""
    P = np.asarray(P, float)
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
    t = np.linspace(0, d[-1], n)
    return np.c_[[np.interp(t, d, P[:, k]) for k in range(3)]].T


def curve(ctrl, n=48):
    """A smooth curve through the control points (Catmull-Rom), as n points evenly along it."""
    C = np.asarray(ctrl, float)
    if len(C) == 2:
        return along(C, n)
    Q = np.r_[[2 * C[0] - C[1]], C, [2 * C[-1] - C[-2]]]
    out = []
    for i in range(len(C) - 1):
        p0, p1, p2, p3 = Q[i:i + 4]
        t = np.linspace(0, 1, 24, endpoint=False)[:, None]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return along(np.r_[np.concatenate(out), [C[-1]]], n)


def profile(n, ends, belly, where=0.5, tendon=(0.0, 0.0)):
    """Half a muscle's thickness along a fibre of n points: `ends` (start, end) at its two ends, `belly` at the
    share `where` of its length, eased between; `tendon` (start, end) are the shares of its length that stay
    as thin as their end before the belly swells."""
    t = np.linspace(0, 1, n)
    a = np.clip((t - tendon[0]) / max(where - tendon[0], 1e-6), 0, 1)
    b = np.clip((1 - tendon[1] - t) / max(1 - tendon[1] - where, 1e-6), 0, 1)
    ease = lambda x: np.sin(np.pi / 2 * x) ** 1.2
    up = ends[0] + (belly - ends[0]) * ease(a)
    down = ends[1] + (belly - ends[1]) * ease(b)
    return np.where(t <= where, up, down)


def sheet(guides, apart=0.5):
    """Fibres filled in between neighbouring guides [(points, half-thickness)], so that nowhere is one farther
    than `apart` times its half-thickness from the next."""
    out = []
    for (p0, r0), (p1, r1) in zip(guides[:-1], guides[1:]):
        k = max(1, int(np.ceil((np.linalg.norm(p1 - p0, axis=1) / (apart * np.minimum(r0, r1))).max())))
        for j in range(k):
            w = j / k
            out.append((p0 * (1 - w) + p1 * w, r0 * (1 - w) + r1 * w))
    out.append(guides[-1])
    return out


def laid(fibres, surf, share=0.9, rounds=5, ends=(True, True), foot=0.12):
    """Fibres laid on the bones: where a point is nearer the bone than `share` of its half-thickness, or in
    it, it is moved out along the bone's normal to that distance; toward an end that attaches (over the last
    `foot` of the length) the fibre comes down onto the bone, and the end itself is put on it. The fibres are
    smoothed a little between rounds so they take no kinks."""
    P = np.array([p for p, r in fibres])
    R = np.array([r for p, r in fibres])
    F, n = R.shape
    t = np.linspace(0, 1, n)
    fade = np.clip(np.minimum(t / foot if ends[0] else 1.0, (1 - t) / foot if ends[1] else 1.0), 0, 1)
    want = share * R * fade
    for k in range(rounds):
        ins, d, i = surf.query(P.reshape(-1, 3), reach=0.03)
        sd = np.where(ins, -d, d).reshape(F, n)
        low = np.isfinite(sd) & (sd < want)
        move = np.where(low, want - sd, 0.0)[..., None] * surf.N[i].reshape(F, n, 3)
        P = P + move
        if k < rounds - 1:
            P[:, 1:-1] = 0.5 * P[:, 1:-1] + 0.25 * (P[:, :-2] + P[:, 2:])
    for e, on in ((0, ends[0]), (n - 1, ends[1])):
        if on:
            ins, d, i = surf.query(P[:, e], reach=0.03)
            ok = np.isfinite(d)
            P[ok, e] = surf.P[i[ok]]
    return [(P[j], R[j]) for j in range(F)]


def to_skin(fibres, skin, depth):
    """Fibres brought out to lie just under the skin: each point's own half-thickness and `depth` under it,
    fully over the middle of the fibre, not at all at its two ends."""
    P = np.array([p for p, r in fibres])
    R = np.array([r for p, r in fibres])
    F, n = R.shape
    t = np.linspace(0, 1, n)
    w = np.clip(np.minimum(t, 1 - t) / 0.22, 0, 1)
    w = w * w * (3 - 2 * w)
    for k in range(3):
        ins, d, i = skin.query(P.reshape(-1, 3), reach=0.08)
        sd = np.where(ins, -d, d).reshape(F, n)
        move = np.where(np.isfinite(sd), -(R + depth) - sd, 0.0) * w
        P = P + move[..., None] * skin.N[i].reshape(F, n, 3)
        P[:, 1:-1] = 0.5 * P[:, 1:-1] + 0.25 * (P[:, :-2] + P[:, 2:])
    return [(P[j], R[j]) for j in range(F)]


def lanes(fibres):
    """How far across its sheet each fibre lies (metres, summed between neighbours at mid length)."""
    mid = np.array([p[len(p) // 2] for p, r in fibres])
    return np.r_[0, np.cumsum(np.linalg.norm(np.diff(mid, axis=0), axis=1))]


def body_of(fibres, hard, soft=(), skin=None, h=H, gap=GAP, target=None, quiet=True, name="", raw=None):
    """The surface of a muscle's body: all within a fibre's half-thickness of that fibre (or the ready-made
    solid `raw`: the grid's corner, its shape, and a value per grid point, below zero inside), less the bones
    (`hard`, a Surface), less each of `soft` (Surfaces of what was built before, or must be cleared), under the
    skin. Returns (vertices, triangles, notes)."""
    from skimage import measure
    if raw is not None:
        lo, shape, f = raw
        ax = [lo[j] + h * np.arange(shape[j]) for j in range(3)]
        G = np.stack(np.meshgrid(*ax, indexing="ij"), axis=-1).reshape(-1, 3)
    else:
        P, R = [], []
        for p, r in fibres:                          # each fibre as points at most 0.4 mm apart
            seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
            k = np.maximum(1, np.ceil(seg / 0.0004).astype(int))
            for j in range(len(seg)):
                w = (np.arange(k[j]) / k[j])[:, None]
                P.append(p[j] * (1 - w) + p[j + 1] * w)
                R.append(r[j] * (1 - w[:, 0]) + r[j + 1] * w[:, 0])
        P, R = np.concatenate(P), np.concatenate(R)
        lo, hi = (P - R[:, None]).min(0) - 5 * h, (P + R[:, None]).max(0) + 5 * h
        ax = [np.arange(lo[j], hi[j] + h, h) for j in range(3)]
        shape = tuple(len(a) for a in ax)
        G = np.stack(np.meshgrid(*ax, indexing="ij"), axis=-1).reshape(-1, 3)
        tree = cKDTree(P)
        f = np.full(len(G), 0.004)
        d1, _ = tree.query(G, k=1, distance_upper_bound=R.max() + 4 * h, workers=3)
        cand = np.flatnonzero(np.isfinite(d1))
        for part in np.array_split(cand, max(1, len(cand) // 400000)):
            dk, ik = tree.query(G[part], k=10, workers=3)
            f[part] = (dk - R[ik]).min(1)
    f = ndimage.gaussian_filter(np.asarray(f, float).reshape(shape), 0.8).reshape(-1)
    shell = np.flatnonzero(f < 2 * h)
    for surf, clear in [(hard, gap)] + [(s_, gap) for s_ in soft]:
        if surf is None or surf.tree is None:
            continue
        for part in np.array_split(shell, max(1, len(shell) // 300000)):
            ins, d, _ = surf.query(G[part], reach=0.012)
            sd = np.where(ins, -d, np.where(np.isfinite(d), d, 0.012))
            f[part] = np.maximum(f[part], clear - sd)
    if skin is not None:
        for part in np.array_split(shell, max(1, len(shell) // 300000)):
            ins, d, _ = skin.query(G[part], reach=0.03)
            sd = np.where(ins, -d, np.where(np.isfinite(d), d, -0.03))      # far from the skin: deep inside
            f[part] = np.maximum(f[part], sd + SKIN_IN)
    f = f.reshape(shape)
    inside = f < 0                               # nothing thinner than two cells: it would come out as flakes
    thin = inside & ~ndimage.binary_dilation(ndimage.binary_erosion(inside), iterations=1)
    f = np.where(thin, 0.25 * h, f)
    lab, k = ndimage.label(f < 0)
    pieces = 1
    if k > 1:
        sizes = np.bincount(lab.ravel())[1:]
        pieces = int((sizes > 0.02 * sizes.max()).sum())
        f = np.where((lab == np.argmax(sizes) + 1) | (f >= 0), f, h)        # the body: its largest piece
    v, tri, _, _ = measure.marching_cubes(f, 0.0, spacing=(h, h, h))
    v = v + lo
    tri = tri.astype(np.int64)
    if m.signed_volume(v, tri) < 0:
        tri = tri[:, ::-1]
    from anatomy_teeth import taubin
    v = taubin(v, tri, 10)
    if target == "fine":                         # for a picture to look at: triangles about 1 mm across
        a_, b_, c_ = v[tri[:, 0]], v[tri[:, 1]], v[tri[:, 2]]
        target = max(9000, int(0.5 * np.linalg.norm(np.cross(b_ - a_, c_ - a_), axis=1).sum() / 0.45e-6))
    target = target or m.target_count(v, tri)
    v, tri = m.simplify(v, tri, target)
    e = np.sort(np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=1)
    e, uses = np.unique(e, axis=0, return_counts=True)
    chi = len(np.unique(tri)) - len(e) + len(tri)
    notes = {"pieces": pieces, "holes": int(round((2 - chi) / 2)), "odd_edges": int((uses != 2).sum()),
             "volume_cm3": round(abs(m.signed_volume(v, tri)) * 1e6, 2), "triangles": int(len(tri))}
    return np.asarray(v, np.float64), np.asarray(tri, np.int64), notes


# ---------------------------------------------------------------- the body's bones and their landmarks

def bones_of(nodes, rx):
    return [(v, f) for n, (pid, st, v, f) in nodes.items() if st.get("tissue") == "bone" and re.search(rx, m.short(n))]


def bones_in(nodes, box, more=()):
    """The bones' meshes (and `more`) that reach into the box, whole (a part of one would not tell its outside
    from its inside)."""
    return [(v, f) for v, f in bones_of(nodes, ".") + list(more)
            if not ((v.max(0) < box[0]).any() or (v.min(0) > box[1]).any())]


def points_of(nodes, rx):
    got = bones_of(nodes, rx)
    return np.concatenate([v for v, f in got]) if got else np.zeros((0, 3))


def border(P, axis, lo, hi, step, pick, of=1):
    """A border of the points P: in slices `step` wide along `axis` from lo to hi, the point lowest (pick -1)
    or highest (pick +1) along the axis `of`. Empty slices are skipped."""
    out = []
    for a in np.arange(lo, hi, step):
        s = P[(P[:, axis] >= a) & (P[:, axis] < a + step)]
        if len(s):
            out.append(s[np.argmax(pick * s[:, of])])
    return np.array(out)


def outer(P, s, yz, reach=0.003):
    """The outermost point (farthest to side s) of the points P near each (y, z) asked for."""
    tree = cKDTree(P[:, 1:])
    out = []
    for q in np.atleast_2d(yz):
        i = tree.query_ball_point(q, reach)
        if not i:
            i = [tree.query(q)[1]]
        c = P[i]
        out.append(c[np.argmax(s * c[:, 0])])
    return np.array(out)


def reach_map(P, s, zlo, ylo, nz, ny, cell, pick=+1):
    """Seen from the side (cells of z by y): how far to side s the points P reach in each cell (their
    outermost for pick +1, their innermost for -1), as s times x. An empty cell takes its nearest neighbour's."""
    iz = np.round((P[:, 2] - zlo) / cell).astype(int)
    iy = np.round((P[:, 1] - ylo) / cell).astype(int)
    ok = (iz >= 0) & (iz < nz) & (iy >= 0) & (iy < ny)
    M = np.full((nz, ny), -np.inf)
    np.maximum.at(M, (iz[ok], iy[ok]), pick * s * P[ok, 0])
    empty = ~np.isfinite(M)
    if empty.any():
        idx = ndimage.distance_transform_edt(empty, return_distances=False, return_indices=True)
        M = M[tuple(idx)]
    return pick * M


def membrane(inside, fixed):
    """Over the cells `inside`, the sheet stretched as flat as it can be between the values `fixed` holds all
    round them (Laplace's equation): how a fascia spans from one bony edge to another."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.linalg import spsolve
    n = int(inside.sum())
    idx = -np.ones(inside.shape, int)
    idx[inside] = np.arange(n)
    I, J = np.nonzero(inside)
    rows, cols, rhs, diag = [], [], np.zeros(n), np.full(n, 4.0)
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        a, b = I + di, J + dj
        ok = (a >= 0) & (a < inside.shape[0]) & (b >= 0) & (b < inside.shape[1])
        a, b = np.clip(a, 0, inside.shape[0] - 1), np.clip(b, 0, inside.shape[1] - 1)
        nb = ok & inside[a, b]
        rows.append(np.flatnonzero(nb))
        cols.append(idx[a, b][nb])
        out = ok & ~inside[a, b]
        rhs[out] += fixed[a, b][out]
        diag[~ok] -= 1
    r_, c_ = np.concatenate(rows), np.concatenate(cols)
    A = coo_matrix((np.r_[-np.ones(len(r_)), diag], (np.r_[r_, np.arange(n)], np.r_[c_, np.arange(n)])), shape=(n, n))
    got = fixed.astype(float).copy()
    got[inside] = spsolve(A.tocsc(), rhs)
    return got


def ease(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def marks(nodes, s):
    """The landmarks of one side (s = +1 the body's left, -1 its right), as points (metres) and rows of points."""
    L = {}
    sd = "L" if s > 0 else "R"
    man = points_of(nodes, r"^mandible$")
    man = man[s * man[:, 0] > 0.004]
    back = man[man[:, 2] < man[:, 2].min() + 0.020]
    L["condyle"] = c = back[np.argmax(back[:, 1])]
    fr = man[(man[:, 2] > c[2] + 0.014) & (man[:, 2] < c[2] + 0.048) & (s * man[:, 0] > s * c[0] - 0.022)]
    L["coronoid"] = k = fr[np.argmax(fr[:, 1])]
    ram = man[man[:, 2] < k[2] + 0.012]
    L["gonion"] = g = ram[np.argmin(ram[:, 1] + ram[:, 2])]
    up = border(man, 2, c[2] + 0.004, k[2] - 0.003, 0.002, +1)
    L["notch"] = up[np.argmin(up[:, 1])]
    # the ramus: its hind border from the condyle's neck to the angle, its front border from the coronoid down
    hind = border(ram[ram[:, 1] < c[1] - 0.008], 1, g[1], c[1] - 0.008, 0.003, -1, of=2)
    L["ramus_hind"] = hind[::-1]                                           # from above down
    body = man[(man[:, 2] > g[2] + 0.004)]
    L["jaw_lower"] = border(body, 2, g[2] + 0.004, g[2] + 0.060, 0.003, -1)   # the lower border, from the angle on
    front = border(ram[(ram[:, 1] < k[1] - 0.004) & (ram[:, 1] > g[1] + 0.022)], 1, g[1] + 0.022, k[1] - 0.004, 0.003, +1, of=2)
    L["ramus_front"] = front[::-1]                                         # from the coronoid down
    # the zygomatic arch: the bar of bone outside the coronoid process, from the cheek bone back to the joint
    zyg = np.concatenate([points_of(nodes, rf"^zygomatic_bone_{sd}$"), points_of(nodes, rf"^temporal_bone_{sd}$")])
    bar = zyg[(s * zyg[:, 0] > s * k[0] + 0.005) & (zyg[:, 1] < k[1] + 0.024) & (zyg[:, 1] > k[1] - 0.02)
              & (zyg[:, 2] > c[2] + 0.004)]
    low = border(bar, 2, bar[:, 2].min(), bar[:, 2].max(), 0.003, -1)[::-1]                # from the front back
    third = low[:max(3, len(low) // 3)]
    first = int(np.argmax(third[:, 1] <= third[:, 1].min() + 0.004))                     # where the cheek bone's
    L["arch_lower"] = low[first:]                                                         # front edge stops climbing
    L["arch_upper"] = border(bar, 2, bar[:, 2].min(), bar[:, 2].max(), 0.003, +1)[::-1]
    L["arch_bar"] = bar
    # the mastoid process: the temporal bone's lowest point behind the joint
    tb = points_of(nodes, rf"^temporal_bone_{sd}$")
    beh = tb[(tb[:, 2] < c[2] - 0.010) & (s * tb[:, 0] > s * c[0] - 0.020)]
    L["mastoid"] = mt = beh[np.argmin(beh[:, 1])]
    # the sternocleidomastoid's line on the skull: the mastoid's outer face from its tip's front edge up and
    # back, then the outer half of the superior nuchal line on the occipital bone
    cal = np.concatenate([tb, points_of(nodes, r"^occipital_bone$"), points_of(nodes, rf"^parietal_bone_{sd}$")])
    cal = cal[s * cal[:, 0] > 0.015]
    L["mastoid_line"] = outer(cal, s, [[mt[1] + 0.005, mt[2] + 0.004], [mt[1] + 0.012, mt[2] - 0.004],
                                       [mt[1] + 0.017, mt[2] - 0.014], [mt[1] + 0.020, mt[2] - 0.026],
                                       [mt[1] + 0.021, mt[2] - 0.038]])
    # the neck's vertebrae: each transverse process's tip and its front and hind tubercles
    for n in range(1, 8):
        v = points_of(nodes, rf"^cervical_vertebra_{n}$")
        side = v[(s * v[:, 0] > 0.008) & ((v[:, 2] > v[:, 2].max() - 0.020) | (n == 1))]
        tip = side[np.argmax(s * side[:, 0])]
        lat = side[(s * side[:, 0] > s * tip[0] - 0.007) & (np.abs(side[:, 1] - tip[1]) < 0.007)
                   & (np.abs(side[:, 2] - tip[2]) < 0.012)]
        L[f"C{n}"] = (tip, lat[np.argmax(lat[:, 2])], lat[np.argmin(lat[:, 2])])
    # the first two ribs, from the head round to the front end: per slice its top, its inner and outer edge
    for n in (1, 2):
        v = points_of(nodes, rf"^rib_{n}_{sd}$")
        c0 = v.mean(0)
        ang = np.arctan2(v[:, 2] - c0[2], s * (v[:, 0] - c0[0]))
        rows = []
        for a in np.linspace(ang.min(), ang.max(), 26)[:-1]:
            sl = v[(ang >= a) & (ang < a + (ang.max() - ang.min()) / 25)]
            if len(sl) < 3:
                continue
            flat = np.hypot(sl[:, 0] - c0[0], sl[:, 2] - c0[2])
            up = sl[sl[:, 1] > sl[:, 1].max() - 0.003]
            rows.append((up.mean(0), up[np.argmin(np.hypot(up[:, 0] - c0[0], up[:, 2] - c0[2]))], sl[np.argmax(flat)]))
        L[f"rib{n}"] = rows
    # the breast bone's top, in front, beside the notch; the collar bone's inner third, on top
    st = points_of(nodes, r"^sternum$")
    top = st[(np.abs(st[:, 0] - s * 0.011) < 0.006) & (st[:, 1] > st[:, 1].max() - 0.017) & (st[:, 1] < st[:, 1].max() - 0.006)]
    L["manubrium"] = top[np.argmax(top[:, 2])]
    cl = points_of(nodes, rf"^clavicle_{sd}$")
    e0 = cl[np.argmin(s * cl[:, 0])]
    row = []
    for d in (0.016, 0.031, 0.046):
        sl = cl[np.abs(s * (cl[:, 0] - e0[0]) - d) < 0.004]
        row.append(sl[np.argmax(sl[:, 1] + 0.5 * sl[:, 2])])
    L["clavicle_third"] = np.array(row)
    # the shoulder blade's upper angle and its inner border below it, to the root of its spine
    sc = points_of(nodes, rf"^scapula_{sd}$")
    med = sc[s * sc[:, 0] < (s * sc[:, 0]).min() + 0.030]
    ang_ = med[np.argmax(med[:, 1])]
    row = [ang_]
    for d in (0.012, 0.026):
        sl = sc[np.abs(sc[:, 1] - (ang_[1] - d)) < 0.003]
        row.append(sl[np.argmin(s * sl[:, 0])])
    L["scapula_border"] = np.array(row)
    return L


# ---------------------------------------------------------------- the muscles, as the textbook gives them

def part_of(row, a, b, n):
    """n points evenly along the share a..b of a row of points."""
    whole = along(row, 200)
    return along(whole[int(round(a * 199)):int(round(b * 199)) + 1], n)


def temporalis(nodes, L, s):
    """Temporalis (Gray, 1918): arises from the whole of the temporal fossa (all of it but the part the
    cheek bone forms) up to the inferior temporal line, and from the deep face of the fascia over it; its
    fibres converge, the front ones straight down, the hind ones nearly level and forward, to a tendon that
    passes deep to the zygomatic arch and inserts on the coronoid process (its tip, inner face and front
    border) and the front border of the ramus nearly to the last molar.

    So it is built as what fills the fossa: seen from the side, everything inside the temporal line (in front
    it stops at the temporal crest behind the orbit's outer rim, behind and below at the crest over the ear
    hole and the arch's upper border); in depth, from the fossa's bony wall out to the temporal fascia, which
    is stretched from the temporal line to the upper border of the arch (so the muscle is a thin layer on the
    bulge of the parietal bone and a thick one in the hollow over the arch); below the arch it narrows, between
    the arch and the skull, onto the coronoid process."""
    from skimage.draw import polygon
    sd = "L" if s > 0 else "R"
    k, c, notch = L["coronoid"], L["condyle"], L["notch"]
    top = float(L["arch_upper"][:, 1].mean())
    crown = points_of(nodes, rf"^parietal_bone_{sd}$")[:, 1].max()
    fro, occ = points_of(nodes, r"^frontal_bone$"), points_of(nodes, r"^occipital_bone$")
    length = fro[fro[:, 1] > top + 0.03][:, 2].max() - occ[:, 2].min()        # the skull, forehead to occiput
    ear = c[2] - 0.009                                                        # the ear hole, behind the joint
    # on Gray's plate 382 the muscle reaches 0.72 of the way from the arch to the crown and 0.34 of the
    # skull's length behind the ear hole
    rise, z1 = 0.72 * (crown - top), ear - 0.34 * length
    cell = 0.0005
    zlo, ylo = z1 - 0.012, k[1] - 0.034
    nz, ny = int((c[2] + 0.085 - zlo) / cell) + 1, int((top + rise + 0.012 - ylo) / cell) + 1
    Z = zlo + cell * np.arange(nz)[:, None] + np.zeros((1, ny))
    Y = ylo + cell * np.arange(ny)[None, :] + np.zeros((nz, 1))
    # the wall of the fossa: the outward-facing surface of the skull's side, without the arch
    surf = m.Surface(bones_of(nodes, rf"^(parietal_bone_{sd}|frontal_bone|temporal_bone_{sd}|sphenoid_bone|"
                                     rf"occipital_bone|zygomatic_bone_{sd})$"), h=0.0007)
    P = surf.P[(s * surf.N[:, 0] > 0.12) & (s * surf.P[:, 0] > 0.02)]
    P = P[~((s * P[:, 0] > s * k[0] + 0.004) & (P[:, 1] < top + 0.0045) & (P[:, 2] > c[2] + 0.004))]
    W0 = reach_map(P, s, zlo, ylo, nz, ny, cell)
    W = ndimage.gaussian_filter(ndimage.median_filter(W0, 7), 2.0)
    # in front the fossa ends where its wall turns outward again: the back of the cheek bone's frontal process
    # and, above it, the temporal crest of the frontal bone
    j0 = int((c[2] + 0.030 - zlo) / cell)
    far = zlo + cell * nz
    zf = np.full(ny, far)
    for iy in range(ny):
        if top - 0.004 <= ylo + cell * iy <= top + 0.050:
            row = W[j0:, iy]
            up = np.flatnonzero(row > np.minimum.accumulate(row) + 0.0025)
            if len(up):
                zf[iy] = zlo + cell * (j0 + up[0]) - 0.001
    zf = ndimage.median_filter(zf, 15, mode="nearest")
    band = zf[(ylo + cell * np.arange(ny) > top + 0.026) & (ylo + cell * np.arange(ny) < top + 0.040)]
    z0 = (np.median(band[band < far]) if (band < far).any() else c[2] + 0.058) + 0.003
    zc, a = (z0 + z1) / 2, (z0 - z1) / 2
    yup = top + rise * (1 - np.abs(np.clip((Z - zc) / a, -1, 1)) ** 2.4) ** (1 / 2.4)      # the temporal line
    ylow = top + 0.002 + 0.020 * np.clip((ear - Z) / (ear - z1), 0, 1) ** 1.5               # the crest over the ear
    up = (Y >= ylow) & (Y <= yup) & (Z <= zf[None, :]) & (Z >= z1) & (Z <= z0)
    r_ = 0.009 / cell                                  # its corners rounded (9 mm), as the line itself is
    up = ndimage.distance_transform_edt(~(ndimage.distance_transform_edt(up) > r_)) <= r_
    # under the arch: narrowing from the gap inside it down onto the coronoid and the ramus's front border
    rf = part_of(np.r_[[k], L["ramus_front"]], 0.0, 0.45, 20)[-1]
    hk = k + (notch - k) * 0.6
    poly = [(k[2] + 0.012, top + 0.003), (rf[2] + 0.0035, rf[1]), (rf[2] - 0.003, rf[1] - 0.003),
            (hk[2] - 0.001, hk[1] - 0.002), (c[2] + 0.019, top + 0.003)]
    low = np.zeros(Z.shape, bool)
    low[polygon([(q[0] - zlo) / cell for q in poly], [(q[1] - ylo) / cell for q in poly], Z.shape)] = True
    mask = ndimage.gaussian_filter((up | low).astype(float), 2.4) > 0.5
    lab, n_ = ndimage.label(mask)
    if n_ > 1:
        mask = lab == 1 + np.argmax(np.bincount(lab.ravel())[1:])
    outline = (ndimage.distance_transform_edt(~mask) - ndimage.distance_transform_edt(mask)) * cell
    above = mask & (Y >= ylow)
    rim = ndimage.distance_transform_edt(above | (Y < ylow)) * cell           # how far inside the temporal line
    # the fascia's foot: the arch's upper border (just inside its inner face), and behind the arch the bone
    bar = L["arch_bar"]
    xb = np.full(nz, np.nan)
    for i in range(nz):
        sl = bar[np.abs(bar[:, 2] - (zlo + cell * i)) < 0.002]
        if len(sl) > 3:
            xb[i] = (s * sl[:, 0]).min() + 0.0015
    wl = W[np.arange(nz), np.clip(((ylow[:, 0] - ylo) / cell).astype(int), 0, ny - 1)] + 0.003
    xb = ndimage.gaussian_filter1d(np.where(np.isfinite(xb), np.maximum(xb, wl), wl), 6.0)
    ahead = ndimage.maximum_filter1d(W, 20, axis=0, origin=-9)                # the wall's rise just in front
    fixed = np.where(Y < ylow, xb[:, None], np.where(Z > zf[None, :] - 0.001, ahead, W) + 0.0005)
    tent = membrane(above, fixed)
    thick = 0.0045 * np.sqrt(1 - (1 - np.clip(rim / 0.020, 0, 1)) ** 2)        # thin at the line, 4.5 mm within
    # (the skin is not asked: on this body the scalp's skin lies 1 to 5 mm off the skull on the right and 6 to
    # 10 mm on the left, which is the skin's fault; the skin is lifted to clear the muscle afterwards)
    out_up = W + np.maximum(tent - W, thick)
    floor = s * k[0] - 0.012                                                  # no deeper than the crest below
    in_up = np.where(Y < top + 0.006, np.maximum(W, floor), W) - 0.0008
    # below the arch's upper border
    jaw = m.Surface(bones_of(nodes, r"^mandible$"), h=0.0006)
    J = jaw.P[(s * jaw.P[:, 0] > 0.02) & (jaw.P[:, 2] > c[2] + 0.006) & (jaw.P[:, 1] > k[1] - 0.045)]
    Jl = reach_map(J, s, zlo, ylo, nz, ny, cell, +1)
    Jm = reach_map(J, s, zlo, ylo, nz, ny, cell, -1)
    w = ease((np.clip((top - Y) / (top - k[1]), 0, 3) - 0.3) / 0.6)
    wrap = -0.001 + 0.0036 * ease((Y - (k[1] - 0.011)) / 0.004)               # round the tip only, on its outer face
    row_top = min(ny - 1, int((top + 0.002 - ylo) / cell))
    out_low = (1 - w) * xb[:, None] + w * (Jl + wrap)
    in_low = (1 - w) * np.maximum(W[:, row_top], floor)[:, None] + w * (Jm - 0.0035)
    if os.environ.get("MB_DEBUG"):
        q = above & (outline < -0.002)
        print(f"   [temporalis {sd}] top {top*1000:.1f} crown {crown*1000:.1f} length {length*1000:.1f} z0 {z0*1000:.1f} z1 {z1*1000:.1f}"
              f" front limit {np.percentile(zf[zf < far], [0, 50, 100]).round(4) * 1000 if (zf < far).any() else None}"
              f" cells {int(q.sum())} thick mm {np.percentile((out_up - W)[q], [1, 10, 50, 90]).round(4) * 1000}"
              f" xb {np.percentile(xb, [0, 50, 100]).round(4) * 1000}", flush=True)
    Xo = ndimage.gaussian_filter(np.where(Y >= ylow, out_up, out_low), 2.0)
    Xi = ndimage.gaussian_filter(np.where(Y >= ylow, in_up, in_low), 2.0)

    def solid(h):
        xs = np.arange(0.028, 0.092, h)
        ys = np.arange(ylo + 0.004, ylo + cell * (ny - 1) - 0.002, h)
        zs = np.arange(zlo + 0.002, zlo + cell * (nz - 1) - 0.002, h)
        gz, gy = np.meshgrid((zs - zlo) / cell, (ys - ylo) / cell, indexing="ij")
        at = lambda M_: ndimage.map_coordinates(M_, [gz, gy], order=1, mode="nearest").T      # [y, z]
        O, A, B = at(outline), at(Xo), at(Xi)
        f = np.maximum(np.maximum(O[None], xs[:, None, None] - A[None]), B[None] - xs[:, None, None])
        if s < 0:
            f = f[::-1]
            lo = np.array([-xs[-1], ys[0], zs[0]])
        else:
            lo = np.array([xs[0], ys[0], zs[0]])
        return lo, f.shape, f.reshape(-1)

    # the fibres' lanes, for the check picture: they fan out from the coronoid process
    pick = mask & (np.indices(mask.shape).sum(0) % 2 == 0)
    FP = np.c_[s * Xo[pick], Y[pick], Z[pick]]
    FL = np.arctan2(Z[pick] - k[2], Y[pick] - (k[1] - 0.014)) * 0.045
    # what it must lie on: the fossa's wall inside the line
    iz = np.clip(np.round((P[:, 2] - zlo) / cell).astype(int), 0, nz - 1)
    iy = np.clip(np.round((P[:, 1] - ylo) / cell).astype(int), 0, ny - 1)
    on = above[iz, iy] & (outline[iz, iy] < -0.002) & (s * P[:, 0] > W0[iz, iy] - 0.0015)
    box = (np.array([min(s * 0.026, s * 0.094), ylo, zlo]), np.array([max(s * 0.026, s * 0.094), ylo + cell * ny, zlo + cell * nz]))
    return {"name": "temporalis", "solid": solid, "box": box, "stripes": (FP, FL), "covers": P[on], "lifts_skin": True}


def masseter(nodes, L, s):
    """Masseter (Gray, 1918). Superficial part: from the zygomatic process of the maxilla and the front two
    thirds of the lower border of the zygomatic arch, its fibres down and back to the angle and the lower
    half of the outer face of the ramus. Deep part: from the hind third of the lower border and the whole
    inner face of the arch, its fibres straight down to the upper half of the ramus and the coronoid."""
    g, k, c = L["gonion"], L["coronoid"], L["condyle"]
    n = 56
    low = L["arch_lower"]
    # the superficial part's insertion: the lower border from 27 mm in front of the angle, round the angle,
    # and 12 mm up the hind border
    under = L["jaw_lower"][np.linalg.norm(L["jaw_lower"] - g, axis=1) < 0.027][::-1]
    hind = L["ramus_hind"][::-1]
    hind = hind[np.linalg.norm(hind - g, axis=1) < 0.008]
    row = np.r_[under, [g], hind]
    row = row + np.array([0, 0, 0.003]) * np.clip(1 - np.linalg.norm(row - g, axis=1) / 0.012, 0, 1)[:, None]
    sup = []
    for w in np.linspace(0, 1, 7):
        o = part_of(low, 0.0, 0.64, 50)[int(round(w * 49))]
        e = along(row, 50)[int(round(w * 49))]
        e = e + np.array([0, 0.0015, 0]) + np.array([s * 0.001, 0, 0])
        P = curve([o, o + (e - o) * 0.5 + np.array([s * 0.003, 0, 0]), e], n)
        sup.append((P, profile(n, (0.0016, 0.0022), 0.0042, where=0.55)))
    # the deep part: from the hind half of the arch's lower border (its inner side) straight down to the
    # ramus at mid height, from the coronoid's root back to the hind border
    mid_y = (L["notch"][1] + g[1]) / 2 + 0.004
    deep = []
    for w in np.linspace(0, 1, 5):
        o = part_of(low, 0.42, 1.0, 50)[int(round(w * 49))] + np.array([-s * 0.003, 0.001, 0])
        back = L["ramus_hind"][np.argmin(np.abs(L["ramus_hind"][:, 1] - mid_y)), 2] + 0.008
        z = (k[2] - 0.004) + (back - (k[2] - 0.004)) * w
        e = np.array([g[0] + s * 0.002, mid_y, z])
        P = curve([o, e], n)
        deep.append((P, profile(n, (0.0016, 0.0018), 0.0034, where=0.45)))
    return {"name": "masseter", "guides": sup, "more": [deep], "share": 0.9, "ends": (True, True)}


def scalene(name, tubercles, feet, belly, n=56):
    """A scalene: slips from the tubercles it arises on, running together down to its foot on a rib."""
    guides = []
    for j, o in enumerate(tubercles):
        e = feet[int(round(j / max(len(tubercles) - 1, 1) * (len(feet) - 1)))]
        guides.append((curve([o, e], n), profile(n, (0.0016, 0.0018), belly, where=0.55)))
    return {"name": name, "guides": guides, "share": 0.9, "ends": (True, True)}


def scalenus_medius(nodes, L, s):
    """Scalenus medius (Gray, 1918): from the hind tubercles of the transverse processes of the lower six
    cervical vertebrae, down to the upper face of the first rib behind the groove for the subclavian artery."""
    rib = L["rib1"]
    feet = [rib[int(round(w * (len(rib) - 1)))][0] for w in (0.34, 0.40, 0.46)]
    return scalene("scalenus_medius", [L[f"C{n}"][2] for n in range(2, 8)], feet[::-1], 0.0046)


def scalenus_posterior(nodes, L, s):
    """Scalenus posterior (Gray, 1918): from the hind tubercles of the transverse processes of the lower two or
    three cervical vertebrae, to the outer face of the second rib."""
    rib = L["rib2"]
    feet = [rib[int(round(w * (len(rib) - 1)))][2] for w in (0.30, 0.36)]
    return scalene("scalenus_posterior", [L[f"C{n}"][2] + np.array([0, 0, -0.003]) for n in (4, 5, 6)], feet[::-1], 0.0032)


def scalenus_anterior(nodes, L, s):
    """Scalenus anterior (Gray, 1918): from the front tubercles of the transverse processes of the third to
    sixth cervical vertebrae, down and a little out, by a narrow flat tendon to the scalene tubercle on the
    inner border of the first rib and the ridge on its upper face in front of the subclavian groove."""
    rib = L["rib1"]
    feet = [rib[int(round(w * (len(rib) - 1)))][1] for w in (0.60, 0.66)]
    return scalene("scalenus_anterior", [L[f"C{n}"][1] for n in (3, 4, 5, 6)], feet, 0.0040)


def levator_scapulae(nodes, L, s):
    """Levator scapulae (Gray, 1918): by four slips from the transverse processes of the atlas and axis and the
    hind tubercles of those of the third and fourth cervical vertebrae, down, back and out to the vertebral
    border of the scapula from its upper angle to the root of its spine."""
    n = 64
    tops = [L["C1"][0], L["C2"][2], L["C3"][2], L["C4"][2]]
    feet = along(L["scapula_border"], 4)
    guides = [(curve([o, e], n), profile(n, (0.0018, 0.0022), 0.0042, where=0.55)) for o, e in zip(tops, feet)]
    return {"name": "levator_scapulae", "guides": guides, "share": 0.9, "ends": (True, True)}


def sternocleidomastoid(nodes, L, s):
    """Sternocleidomastoid (Gray, 1918). Sternal head: a rounded tendon from the upper front of the manubrium.
    Clavicular head: flat and fleshy from the upper border and front of the inner third of the clavicle. The
    two leave a three-cornered gap above the joint, blend below the middle of the neck (the clavicular head
    passing under the sternal), and run up, out and back to the outer face of the mastoid process, from its
    tip to its upper border, and the outer half of the superior nuchal line. It lies just under the skin."""
    n = 72
    line = along(L["mastoid_line"], 60)
    mb, cl = L["manubrium"], L["clavicle_third"]
    sternal = []
    for w in np.linspace(0, 1, 3):
        o = mb + np.array([s * (w - 0.5) * 0.007, 0, 0])
        e = line[int(round(w * 0.42 * 59))]
        sternal.append((curve([o, o + (e - o) * 0.33, o + (e - o) * 0.66, e], n),
                        profile(n, (0.0024, 0.0020), 0.0052, where=0.5, tendon=(0.10, 0.0))))
    clav = []
    for w in np.linspace(0, 1, 4):
        o = along(cl, 20)[int(round(w * 19))]
        e = line[int(round((0.36 + 0.64 * w) * 59))]
        clav.append((curve([o, o + (e - o) * 0.33, o + (e - o) * 0.66, e], n),
                     profile(n, (0.0020, 0.0018), 0.0044, where=0.5)))
    return {"name": "sternocleidomastoid", "guides": sternal, "more": [clav], "share": 0.9, "ends": (True, True),
            "skin": 0.004}


MUSCLES = [  # deep first: (the function, the part it goes in, its label, UBERON, tissue group)
    (temporalis, "jaw-muscles", "temporalis", "UBERON:0001598"),
    (masseter, "jaw-muscles", "masseter", "UBERON:0001597"),
    (scalenus_medius, "neck-muscles", "scalenus_medius", "UBERON:0008712"),
    (scalenus_posterior, "neck-muscles", "scalenus_posterior", "UBERON:0008713"),
    (scalenus_anterior, "neck-muscles", "scalenus_anterior", "UBERON:0008711"),
    (levator_scapulae, "neck-muscles", "levator_scapulae", "UBERON:0001106"),
    (sternocleidomastoid, "neck-muscles", "sternocleidomastoid", "UBERON:0002377"),
]


def build(nodes, quiet=False, only=None, sides=(1, -1), fine=False):
    """Every muscle of MUSCLES, both sides: {name_L/R: (v, f, notes, part, uberon, fibre points, their lanes)}."""
    sk = [(v, f) for n, (pid, st, v, f) in nodes.items() if pid == "skin"]
    skin = m.Surface(sk, h=0.0012, box=(np.array([-0.25, 0.45, -0.2]), np.array([0.25, 0.95, 0.2]))) if sk else None
    made = {}
    for s in sides:
        sd = "L" if s > 0 else "R"
        L = marks(nodes, s)
        before = []                                  # what was built before, on this side: (v, f)
        for fn, part, label, uberon in MUSCLES:
            if only and not re.search(only, label):
                continue
            spec = fn(nodes, L, s)
            if "solid" in spec:
                box = spec["box"]
                hard = m.Surface(bones_in(nodes, box), h=0.0006, box=box)
                v, f, notes = body_of(None, hard, soft=[m.Surface([b_], h=0.0006) for b_ in before],
                                      skin=None if spec.get("lifts_skin") else skin, name=label,
                                      target="fine" if fine else None, raw=spec["solid"](H))
                mine = m.Surface([(v, f)], h=0.0007)
                if skin is not None:
                    ins, d, _ = skin.query(v, reach=0.08)
                    notes["under_skin_mm"] = [round(float(x) * 1000, 1) for x in np.percentile(np.where(ins, d, -d), [0, 10, 50])]
                if "covers" in spec:
                    ins, d, _ = mine.query(spec["covers"], reach=0.01)
                    notes["covers_pct"] = round(100 * float((ins | (d < 0.0012)).mean()), 1)
                notes["in_bone"] = round(float(m.inside_share(v, f, hard, h=0.0007)) * 100, 2)
                made[f"{label}_{sd}"] = (v, f, notes, part, uberon) + tuple(spec["stripes"])
                before.append((v, f))
                if not quiet:
                    print(f"   {label}_{sd}: {notes}", flush=True)
                continue
            sheets = [spec["guides"]] + spec.get("more", [])
            allp = np.concatenate([p for g in sheets for p, r in g])
            box = (allp.min(0) - 0.025, allp.max(0) + 0.025)
            hard = m.Surface(bones_in(nodes, box), h=0.0006, box=box)
            under = m.Surface(bones_in(nodes, box, before), h=0.0007, box=box) if before else hard
            fibres, lane, base = [], [], 0.0
            for g in sheets:
                fs = sheet(g)
                if spec.get("skin") and skin is not None:
                    fs = to_skin(fs, skin, spec["skin"])
                fs = laid(fs, under, share=spec.get("share", 0.9), ends=spec.get("ends", (True, True)))
                fibres += fs
                la = lanes(fs) + base
                lane += list(la)
                base = la[-1] + 0.004
            v, f, notes = body_of(fibres, hard, soft=[m.Surface([b_], h=0.0006) for b_ in before], skin=skin, name=label,
                                  target="fine" if fine else None)
            if skin is not None:                     # the room the skin leaves over each fibre's middle half
                cp = np.concatenate([p[len(p) // 4:-len(p) // 4] for p, r in fibres])
                cr = np.concatenate([r[len(r) // 4:-len(r) // 4] for p, r in fibres])
                ins, d, _ = skin.query(cp, reach=0.08)
                room = np.where(ins, d, -d) - cr
                notes["skin_room_mm"] = [round(float(x) * 1000, 1) for x in np.percentile(room, [0, 10, 50])]
            notes["in_bone"] = round(float(m.inside_share(v, f, hard, h=0.0007)) * 100, 2)
            step = max(1, len(fibres[0][0]) // 24)
            FP = np.concatenate([p[::step] for p, r in fibres])
            FL = np.concatenate([np.full(len(p[::step]), l_) for (p, r), l_ in zip(fibres, lane)])
            made[f"{label}_{sd}"] = (v, f, notes, part, uberon, FP, FL)
            before.append((v, f))
            if not quiet:
                print(f"   {label}_{sd}: {notes}", flush=True)
    return made


# ---------------------------------------------------------------- pictures to look at

def look(nodes, made, path, eye=(1, 0.05, 0.25), box=((-0.11, 0.66, -0.12), (0.11, 0.92, 0.13)), size=1000, bones="."):
    """The built muscles (red) on the bones, to look at."""
    sys.path.insert(0, os.path.join(m.S, "mm"))
    from quick import render
    lo, hi = np.array(box[0]), np.array(box[1])
    M = []
    for n, (pid, st, v, f) in nodes.items():
        if st.get("tissue") in ("bone", "tooth") and pid in BONE_PARTS and re.search(bones, m.short(n)):
            ok = ((v >= lo) & (v <= hi)).all(1)
            g = f[ok[f].all(1)]
            if len(g):
                M.append((v, g, (232, 228, 214) if st.get("tissue") == "tooth" else (196, 186, 160)))
    for name, (v, f, *rest) in made.items():
        ok = ((v >= lo) & (v <= hi)).all(1)
        g = f[ok[f].all(1)]
        if not len(g):
            continue
        if len(rest) >= 5:                          # striped along its fibres: every other 1.5 mm lane darker
            FP, FL = rest[3], rest[4]
            lane = FL[cKDTree(FP).query(v[g].mean(1))[1]]
            dark = (np.floor(lane / 0.0015) % 2).astype(bool)
            M.append((v, g[~dark], (186, 70, 58)))
            M.append((v, g[dark], (150, 48, 42)))
        else:
            M.append((v, g, (176, 62, 52)))
    render(M, eye, path, size=size)


def views(nodes, made, out):
    """The check pictures: the jaw from the side; the neck from the side, the front and behind."""
    head = ((-0.11, 0.69, -0.12), (0.11, 0.92, 0.13))
    neck = ((-0.19, 0.52, -0.14), (0.19, 0.80, 0.13))
    look(nodes, made, out.replace(".png", "_jaw.png"), box=head, size=900)
    look(nodes, made, out.replace(".png", "_neck.png"), box=neck, eye=(1, 0.05, 0.3), size=900)
    look(nodes, made, out.replace(".png", "_front.png"), box=neck, eye=(0.35, 0.05, 1), size=900)
    look(nodes, made, out.replace(".png", "_back.png"), box=neck, eye=(0.7, 0.1, -0.8), size=900)


def picture(nodes, sides, path, eye=(1, 0.05, 0.25), box=((-0.11, 0.52, -0.13), (0.11, 0.92, 0.14)), size=1100):
    sys.path.insert(0, os.path.join(m.S, "mm"))
    from quick import render
    lo, hi = np.array(box[0]), np.array(box[1])
    M = []
    for n, (pid, st, v, f) in nodes.items():
        if st.get("tissue") == "bone" and pid in BONE_PARTS:
            ok = ((v >= lo) & (v <= hi)).all(1)
            g = f[ok[f].all(1)]
            if len(g):
                M.append((v, g, (196, 186, 160)))
    cols = {"condyle": (230, 60, 60), "coronoid": (60, 200, 60), "gonion": (60, 120, 240), "notch": (240, 200, 40),
            "mastoid": (230, 60, 230)}
    def dot(p, col, r=0.0016):
        t = np.array([[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]], float) * r
        M.append((p + t, np.array([[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]]), col))
    for s in sides:
        L = marks(nodes, s)
        for key, val in L.items():
            if key == "arch_bar":
                continue
            val = np.atleast_2d(val)
            for p in val:
                dot(p + np.array([s * 0.004, 0, 0]), cols.get(key, (40, 220, 220) if "arch" in key else (250, 140, 40)),
                    0.0022 if len(val) == 1 else 0.0012)
    render(M, eye, path, size=size)


def main():
    folder = sys.argv[1]
    manifest = json.load(open(os.path.join(folder, "anatomy.json")))
    body = manifest["bodies"][0]
    nodes = m.body_nodes(folder, body)
    if "--marks" in sys.argv:
        picture(nodes, (1,), sys.argv[sys.argv.index("--marks") + 1])
        for key, val in marks(nodes, 1).items():
            if np.ndim(val) == 1:
                print(key, np.round(val * 1000, 1))
            else:
                print(key, len(val), "points")
        return
    if "--try" in sys.argv:                       # build without writing, and draw: --try out.png [only] [sides]
        i = sys.argv.index("--try")
        out = sys.argv[i + 1]
        only = sys.argv[i + 2] if len(sys.argv) > i + 2 else None
        made = build(nodes, only=only, sides=(1,) if "--left" in sys.argv else (1, -1), fine=True)
        np.save(out.replace(".png", ".npy"), made, allow_pickle=True)
        views(nodes, made, out)
        return


if __name__ == "__main__":
    main()
