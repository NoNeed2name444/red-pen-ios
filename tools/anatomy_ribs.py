#!/usr/bin/env python3
"""Each rib seated on the scanned spine. The ribs come from a CT (TotalSegmentator's masks, tools/anatomy_gaps.py
rib_cage), carried into the body by the warp that fits the scan to it, each rib rigidly; the vertebrae are then
replaced by scans of real bone (tools/anatomy_bones.py), each fitted onto the organ set's. The masks stop at the
transverse processes: each scanned rib ends in a cut face at the tip of its process, its neck and head missing, so
seen from behind every rib stopped in the air beside the spine, 2 to 18 mm off the vertebrae; and here and there a
rib ran a millimetre or two into a process, or stood up to 20 mm above or below its own.

  python3 tools/anatomy_ribs.py ATLAS_FOLDER   seats the ribs of both bodies of that atlas; tools/anatomy_atlas.py
                                             calls remake() after the scanned bones are in

Where each rib meets the spine (Gray's Anatomy, 1918, the costovertebral articulations; public domain): the heads
of the second to ninth ribs on two vertebrae, their crests at the disc between (the rib's own vertebra and the one
above); the first, tenth, eleventh and twelfth each on its own vertebra alone, the first and tenth near its upper
border (a quarter of the way down from the disc above to the disc below), the eleventh and twelfth a little lower
(a third). The neck runs back and out from the head in front of the transverse process, its tubercle on the
process's tip (the costotransverse joint; the eleventh and twelfth have none). Each rib, its back end moved with a
weight that is whole at the end and fades along the rib to nothing at half its reach (its sides and front stay where
the cage has them, against the lungs):

1. eased out of any bone it runs into, the shortest way its points ask for together (at most 8 mm);
2. raised or lowered, where it passes the tip of its own transverse process, to the tip's level (the first to the
   tenth; at most 25 mm), and eased out again of what it slid along;
3. its neck and head drawn out of its end to the joint: the last 30 mm of the rib stretched (its cut face carried
   whole, the stretched part cut finer) straight toward the column's axis at the joint's level, a little ahead or
   behind, until the head lies 1.5 mm off a vertebral body or disc; of the ways in, the one that lands nearest the
   axis within 4 mm of the joint's level (the discs tilt with the spine's curves, so the level is taken where the
   head lands), and of those within 2 mm of it, the hindmost, its neck nearest the process.

Every move is swept a millimetre at a time on points over the rib's surface: none may pass deeper into a bone than
half a millimetre (the bones' 1 mm grid's grain: a neck lies against its process), or than it already was. What the
ribs then run into gives way: the lungs, joined (their segments tile them), moved back into the chest's cavity as
the cage now bounds it by one smooth field, carrying the airways and vessels about them; each other soft part about
the cage moved out of the ribs the same way (tools/anatomy_gaps.py push_out).
"""
import json
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

GAP = 0.0015                 # the heads this far off the bones (the joints' cartilage)
NECK = 0.03                  # the neck and head grown out of this much of each rib's end
TILT = 0.5                   # a rib's back end raised or lowered onto its process, the move gone by this share of
                             # its reach (its sides and front stay where the cage has them, against the lungs)
SLIDE = np.arange(-0.012, 0.0161, 0.002)   # how far ahead (or behind) of its own way in a head may come in
SINGLE = {1: 0.25, 10: 0.25, 11: 0.33, 12: 0.33}   # the ribs on one vertebra: how far down it, disc to disc
TUBERCLE = range(1, 11)      # the ribs whose tubercles meet a transverse process (not the eleventh and twelfth)
STEP = 0.001                 # every move swept this finely, so nothing passes into a bone on the way
SLIP = 0.0004                # and a point already at that, this much deeper as it slides along the bone
CLEAR = 0.0005               # a rib's back end moved this far out of the bones it runs into, before its neck is drawn
OUT = 0.008                  # out, and that move at most this
GRAZE = 0.0005               # how far into a bone a moving rib may come (the bones' grid's grain: a neck on its process)
ORDINALS = ("first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
            "eleventh", "twelfth")
TRACE = set()                # ribs ("9R") whose seating seat() describes step by step, for working on it
# the soft parts about the cage that give way to it (the bones and the sternum's joints are left as they are)
SOFT = ("lungs", "airways", "heart", "vessels", "oesophagus", "back-muscles", "liver", "spleen", "stomach",
        "kidneys", "adrenals", "thymus")


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * x * (x * (6 * x - 15) + 10)


def _plane(v):
    """A disc's middle plane: its centre and the normal of its least spread (upward)."""
    c = np.median(v, 0)
    n = np.linalg.svd(v - v.mean(0), full_matrices=False)[2][2]
    return c, (n if n[1] > 0 else -n)


def _level(plane, x, z):
    c, n = plane
    return c[1] - (n[0] * (x - c[0]) + n[2] * (z - c[2])) / n[1]


class Bones:
    """The column's bones as an obstacle, each filled on a 1 mm grid: whether a point is in one, and how near it is
    to the faces a rib's head meets (the vertebral bodies and the discs, given as `joints`: points on them)."""
    def __init__(self, meshes, joints, h=0.001):
        from scipy import ndimage
        from anatomy_gaps import surface_points
        pts = [surface_points(v, f, h) for v, f in meshes]
        self.tree = cKDTree(np.vstack(pts))
        self.joints = cKDTree(np.vstack(joints))
        P = np.vstack(pts)
        self.lo, self.h = P.min(0) - 5 * h, h
        self.g = np.zeros(np.floor((P.max(0) - self.lo) / h).astype(int) + 6, bool)
        for q in pts:                                         # each bone filled on its own: the canal stays open
            idx = np.floor((q - self.lo) / h).astype(int)
            a, b = idx.min(0) - 3, idx.max(0) + 4
            sub = np.zeros(b - a, bool)
            sub[tuple((idx - a).T)] = True
            sub = ndimage.binary_fill_holes(ndimage.binary_closing(sub, iterations=2))
            self.g[a[0]:b[0], a[1]:b[1], a[2]:b[2]] |= sub
        # how far into the bones each cell's middle lies, less outside: the faces halfway between the cells in and
        # the cells out
        self.sd = ((np.where(self.g, ndimage.distance_transform_edt(self.g) - 0.5, 0.0)
                    - np.where(self.g, 0.0, ndimage.distance_transform_edt(~self.g) - 0.5)) * h).astype(np.float32)

    def depth(self, p):
        """How far into the bones each point lies (less than 0 outside), read off the cells' middles linearly."""
        from scipy import ndimage
        return ndimage.map_coordinates(self.sd, ((p - self.lo) / self.h - 0.5).T, order=1, mode="nearest")

    def inside(self, p):
        idx = np.floor((p - self.lo) / self.h).astype(int)
        ok = ((idx >= 0) & (idx < self.g.shape)).all(1)
        out = np.zeros(len(p), bool)
        out[ok] = self.g[tuple(idx[ok].T)]
        return out

    def near(self, p):
        return self.joints.query(p, distance_upper_bound=GAP + 0.0005)[0]

    def way_out(self, p, margin):
        """From each point the move to the nearest place outside the bones, and margin past it."""
        if not hasattr(self, "ind"):
            from scipy import ndimage
            _, self.ind = ndimage.distance_transform_edt(self.g, return_indices=True)
        idx = np.clip(np.floor((p - self.lo) / self.h).astype(int), 0, np.array(self.g.shape) - 1)
        q = self.lo + (np.stack([self.ind[k][tuple(idx.T)] for k in range(3)], 1) + 0.5) * self.h
        d = q - p
        return d + d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) * margin


def advance(bones, at, most, step, stop=None):
    """How far along a move (at(k): the moving points at k, k from 0 to most) they go before any goes deeper into
    the bones than GRAZE or than it started (a rib already in a bone may come out of it, never go further in), or
    any of `stop` (a mask of them: the head) not in a bone comes nearer the joints' faces than GAP (or than it
    started, if nearer); swept by step, the last step halved down."""
    q0 = at(0.0)
    deep0 = np.maximum(bones.depth(q0), GRAZE) + SLIP
    if stop is not None:
        d0 = np.where(deep0[stop] > GRAZE + 1e-5, -np.inf, np.minimum(bones.near(q0[stop]), GAP) - 1e-4)
    # (a point's depth read off the grid moves by up to a cell's share as the point crosses it; held to where it
    # started, a point already in a bone may slide along at that depth)

    def ok(k):
        q = at(k)
        return bool((bones.depth(q) <= deep0).all()) and (stop is None or bool((bones.near(q[stop]) >= d0).all()))
    k = 0.0
    while k < most - 1e-12:
        nk = min(k + step, most)
        if not ok(nk):
            lo, hi = k, nk
            for _ in range(6):
                m = (lo + hi) / 2
                lo, hi = (m, hi) if ok(m) else (lo, m)
            if _trace:
                q = at(nk)
                over = bones.depth(q) > deep0
                print(f"    stopped at {lo * 1000:.1f} of {most * 1000:.1f}: {int(over.sum())} too deep (to "
                      f"{bones.depth(q)[over].max(initial=0) * 1000:.1f} mm)" + ("" if stop is None else
                      f", head nearer than allowed {int((bones.near(q[stop]) < d0).sum())}"))
            return lo
        k = nk
    return most


_trace = False


def _samples(v, f, w, least):
    """Points over the triangles whose corners move (w: each corner's share of the move), with their own share."""
    from anatomy_gaps import face_samples
    tri = np.flatnonzero(w[f].max(1) > least)
    B, T, _ = face_samples(v, f[tri], 0.001)
    return np.einsum("sk,skc->sc", B, v[f[tri][T]]), (B * w[f[tri][T]]).sum(1)


def _tip(V, centre, sign):
    """A vertebra's transverse process tip on one side: the middle of its points within 8 mm of its farthest out,
    behind its body."""
    lat = sign * (V[:, 0] - centre[0])
    behind = V[:, 2] < centre[2] - 0.01
    return V[behind & (lat > lat[behind].max() - 0.008)].mean(0)


def seat(column, ribs, pre):
    """The ribs seated on the column. column: {node: (v, f)} of the vertebral column's part; ribs: [(node, (v, f))]
    of the ribs' part, the costal cartilages among them. Returns the ribs' new meshes in the same order (each rib's
    end cut finer where its neck is drawn out) and an account."""
    from anatomy_gaps import refine, surface_points, vertex_normals
    col = {k: (np.asarray(v, np.float64), np.asarray(f, np.int64)) for k, (v, f) in column.items()}
    disc = {0: col[f"{pre}intervertebral_disk_of_seventh_cervical_vertebra"]}
    for n in range(1, 13):
        disc[n] = col[f"{pre}intervertebral_disk_of_{ORDINALS[n - 1]}_thoracic_vertebra"]
    mid = {n: np.median(v, 0) for n, (v, _) in disc.items()}     # each disc's middle, on the axis
    plane = {n: _plane(v) for n, (v, _) in disc.items()}
    vert = {n: col[f"{pre}thoracic_vertebra_{n}"] for n in range(1, 13)}
    vert[0], vert[13] = col[f"{pre}cervical_vertebra_7"], col[f"{pre}lumbar_vertebra_1"]
    out = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for _, (v, f) in ribs]
    names = [n for n, _ in ribs]

    def body(k):
        """The vertebral body of T(k), the face the heads meet: its points about the axis between its discs, no
        farther out than the discs reach (and the roots of its pedicles)."""
        p = surface_points(*vert[k], 0.001)
        axis = (mid[k - 1] + mid[k]) / 2
        r = max(np.percentile(np.hypot(*(disc[j][0] - mid[j])[:, [0, 2]].T), 90) for j in (k - 1, k)) + 0.002
        return p[np.hypot(p[:, 0] - axis[0], p[:, 2] - axis[2]) < r]
    said = []
    for n in range(1, 13):
        c = mid[n - 1] + SINGLE[n] * (mid[n] - mid[n - 1]) if n in SINGLE else mid[n - 1]

        def level(x, z):
            a = _level(plane[n - 1], x, z)
            return a + SINGLE[n] * (_level(plane[n], x, z) - a) if n in SINGLE else a
        # the bones a rib's end can meet: its own vertebrae and the next above and below, and their discs
        near_v = range(max(0, n - 2), min(13, n + 2) + 1)
        near_d = range(max(0, n - 2), min(12, n + 1) + 1)
        bones = Bones([vert[k] for k in near_v] + [disc[k] for k in near_d],
                      [surface_points(*disc[k], 0.001) for k in near_d] + [body(k) for k in near_v if 1 <= k <= 12])
        for side, sign in (("L", 1.0), ("R", -1.0)):
            i = names.index(f"TS_rib_{n}_{side}")
            v, f = out[i]
            global _trace
            _trace = f"{n}{side}" in TRACE
            across = np.hypot(v[:, 0] - c[0], v[:, 2] - c[2])
            p0 = v[across <= np.percentile(across, 3)].mean(0)            # the scan's rib ends here, cut off
            gap0 = bones.tree.query(v)[0].min()
            reach = np.linalg.norm(v - p0, axis=1)
            lift = 1 - smoothstep(reach / (TILT * reach.max()))          # a move whole at the end, fading along it
            # 1. what of the rib's back end is in a bone or on one (the scan's ribs run into the processes here and
            # there) moved off it the shortest way, the move fading along the rib: room for the neck to pass
            out_of = np.zeros(3)

            def clear(v, p0):
                """The end moved out of what it is in, by the way out its points ask for together: their mean
                way, as far as the one that asks most along it needs; at most OUT in all."""
                moved = np.zeros(3)
                for _ in range(8):
                    S, ws = _samples(v, f, lift, 0.02)
                    deep = (bones.depth(S) > GRAZE) & (ws > 0.25)
                    if not deep.any():
                        break
                    way = bones.way_out(S[deep], CLEAR) / ws[deep, None]
                    mean = way.sum(0)
                    mean /= max(np.linalg.norm(mean), 1e-12)
                    along = way @ mean
                    step_out = mean * along[along > 0].max(initial=0.0005)
                    if np.linalg.norm(moved + step_out) > OUT:
                        break
                    v = v + lift[:, None] * step_out
                    p0 = p0 + step_out
                    moved += step_out
                return v, p0, moved
            v, p0, moved = clear(v, p0)
            out_of += moved
            # 2. the end raised or lowered to the tip of its transverse process (the tubercle's joint), the move
            # fading along the rib so its sides and front stay where the cage has them; swept, so it stops at
            # whatever bone it meets
            dy = 0.0
            if n in TUBERCLE:
                tip = _tip(vert[n][0], (mid[n - 1] + mid[n]) / 2, sign)
                there = np.linalg.norm(v - v[np.argmin(np.linalg.norm(v - tip, axis=1))], axis=1) < 0.012
                want = float(np.clip(tip[1] - v[there, 1].mean(), -0.025, 0.025))
                S, ws = _samples(v, f, lift, 0.02)
                way = np.array([0.0, np.sign(want), 0.0])
                dy = np.sign(want) * advance(bones, lambda k: S + ws[:, None] * (k * way), abs(want), STEP)
                v = v + lift[:, None] * np.array([0.0, dy, 0.0])
                p0 = p0 + np.array([0.0, dy, 0.0])
                # and off whatever it slid along on the way
                v, p0, moved = clear(v, p0)
                out_of += moved
            # 3. the neck and head drawn out of the end to the joint on the vertebral bodies: the end's last NECK
            # stretched, its cut face carried whole, its way swept so it passes into no bone
            u = v[(reach > NECK) & (reach < NECK + 0.01)].mean(0) - p0
            u /= np.linalg.norm(u)                                       # the way the rib runs from its end
            v, f, _, _, _ = refine(v, f, np.zeros(len(f), np.int64), np.flatnonzero(reach[f].min(1) < NECK + 0.01),
                                   0.004, vertex_normals(v, f))
            d = np.linalg.norm(v - p0, axis=1)
            w = np.where(d < NECK + 0.015, 1 - smoothstep(((v - p0) @ u) / NECK), 0.0)
            S, ws = _samples(v, f, w, 0.0)
            head = ws > 0.9

            def land(aim, most):
                """The head moved straight toward aim until it meets the bones (swept): its move."""
                way = aim - p0
                way /= np.linalg.norm(way)
                return advance(bones, lambda k: S + ws[:, None] * (k * way), most, STEP, head) * way

            # aimed at the axis at its joint's level, a little ahead or behind (a head coming in from the side can
            # catch its neck on the process before it reaches the body); then aimed again so it arrives at its
            # joint's level where it first landed (the discs tilt with the curves of the spine). Of the landings
            # within 4 mm of their joint's level, the one nearest the axis, and of those that land within 2 mm of
            # it, the hindmost: the neck nearest the process
            inward = np.array([c[0] - p0[0], 0.0, c[2] - p0[2]])
            inward /= np.linalg.norm(inward)
            ahead = np.array([-inward[2], 0.0, inward[0]])               # across, toward the front
            ahead *= np.sign(ahead[2]) or 1.0
            tries = []
            for b in SLIDE:
                y = level(c[0], c[2])
                for _ in range(2):
                    aim = np.array([c[0], y, c[2]]) + b * ahead
                    T = land(aim, 0.08)
                    q = p0 + T
                    tries.append((np.hypot(*(q - c)[[0, 2]]), abs(q[1] - level(q[0], q[2])), b, T))
                    if _trace:
                        print(f"  {n}{side} b {b * 1000:+.0f}: lands {tries[-1][0] * 1000:.0f} mm from the axis, "
                              f"{tries[-1][1] * 1000:.0f} mm off its level, moved {np.linalg.norm(T) * 1000:.0f} mm")
                    # the head goes a share of the way to its aim before it lands: aimed so it arrives at the level
                    share = max(np.linalg.norm(T) / np.linalg.norm(aim - p0), 0.3)
                    y = p0[1] + (level(q[0], q[2]) - p0[1]) / share
            level_ok = [t for t in tries if t[1] <= 0.004] or tries
            best = min(t[0] for t in level_ok)
            _, _, b, T = min((t for t in level_ok if t[0] <= best + 0.002), key=lambda t: t[2])
            v = v + w[:, None] * T
            out[i] = (v, f)
            said.append(f"{n}{side} head in {np.linalg.norm(T) * 1000:.0f} mm, {dy * 1000:+.0f} mm onto its process"
                        + (f", {np.linalg.norm(out_of) * 1000:.1f} mm out of the bone ({out_of[0] * sign * 1000:+.0f} out, "
                           f"{out_of[1] * 1000:+.0f} up, {out_of[2] * 1000:+.0f} forward)" if out_of.any() else "") + " "
                        f"(gap {gap0 * 1000:.0f}->{bones.tree.query(v)[0].min() * 1000:.1f})")
    return out, "ribs " + ", ".join(said)


class Cavity:
    """Everything a lung may not be in, on a 2 mm grid: outside the chest's cavity as the cage bounds it, or in a
    bone; with the way back from every voxel. The cavity: about each level's middle (the middle of the cage's box
    there, smoothed over 20 mm), at each angle, as far out as the nearest of the cage's points (the inner faces of
    the ribs, their cartilages and the sternum), the gaps between ribs bridged level to level, and nothing above or
    below the cage. Moved out of a rib by the nearest way, a lung the rib has cut into goes out behind it; out of
    this, only back in. Where at some angle no point of the cage lies, the vertebrae behind the middle bound it
    (`stops`): straight back from the middle no rib lies at all, so there the cavity ran on behind the spine, and the
    man's right lung lay 13 mm behind the neck of his 4th rib, 22 of the rib's points inside it. They bound only
    there: as a bound at every angle they shut the top of the chest, where the cage is only the first ribs' necks
    about the spine, and pushed both lungs' apices 30-40 mm down out of the thoracic inlet. The way back is level
    (each 2 mm slice on its own), so a lung goes out of a vertebra or a rib to the side or forward, as it lies
    beside the column, and not down: the apex keeps its height above the first rib's neck."""
    def __init__(self, cage, bones, lo, hi, h=0.002, angles=180, stops=()):
        from scipy import ndimage
        from anatomy_gaps import surface_points
        P = np.vstack(cage)
        self.lo, self.h = lo, h
        shape = np.ceil((hi - lo) / h).astype(int) + 1
        ys = lo[1] + (np.arange(shape[1]) + 0.5) * h
        mid = np.full((len(ys), 2), np.nan)
        for j, y in enumerate(ys):
            q = P[np.abs(P[:, 1] - y) < 0.01]
            if len(q) > 50:
                mid[j] = (q[:, [0, 2]].min(0) + q[:, [0, 2]].max(0)) / 2
        ok = np.flatnonzero(np.isfinite(mid[:, 0]))
        k = np.ones(11) / 11
        mid = np.stack([np.convolve(np.pad(np.interp(np.arange(len(ys)), ok, mid[ok, c]), 5, mode="edge"), k, "valid")
                        for c in range(2)], 1)
        def bins(Q):
            j = np.clip(np.floor((Q[:, 1] - lo[1]) / h).astype(int), 0, len(ys) - 1)
            dx, dz = Q[:, 0] - mid[j, 0], Q[:, 2] - mid[j, 1]
            return j, np.floor((np.arctan2(dz, dx) + np.pi) / (2 * np.pi) * angles).astype(int) % angles, \
                np.hypot(dx, dz), dz
        R = np.full((len(ys), angles), np.inf)
        j, a, r, _ = bins(P)
        np.minimum.at(R, (j, a), r)
        if len(stops):
            j, a, r, dz = bins(np.vstack(stops))
            back = dz < 0                              # behind the middle
            column = np.full_like(R, np.inf)
            np.minimum.at(column, (j[back], a[back]), r[back])
            empty = ~np.isfinite(R)
            R[empty] = column[empty]
        R = ndimage.minimum_filter(R, size=(3, 3), mode="wrap")
        for i in range(angles):
            have = np.flatnonzero(np.isfinite(R[:, i]))
            if len(have) > 1:
                R[have[0]:have[-1] + 1, i] = np.interp(np.arange(have[0], have[-1] + 1), have, R[have, i])
        gx = lo[0] + (np.arange(shape[0]) + 0.5) * h
        gz = lo[2] + (np.arange(shape[2]) + 0.5) * h
        g = np.zeros(shape, bool)
        for jj in range(len(ys)):
            DX, DZ = gx[:, None] - mid[jj, 0], gz[None, :] - mid[jj, 1]
            A = np.floor((np.arctan2(DZ, DX) + np.pi) / (2 * np.pi) * angles).astype(int) % angles
            g[:, jj, :] = np.hypot(DX, DZ) > R[jj][A]
        for v, f in bones:
            idx = np.floor((surface_points(v, f, h) - lo) / h).astype(int)
            b = np.zeros(shape, bool)
            b[tuple(idx[((idx >= 0) & (idx < shape)).all(1)].T)] = True
            g |= ndimage.binary_fill_holes(ndimage.binary_closing(b, iterations=2))
        self.g = g
        _, self.ind = ndimage.distance_transform_edt(g, return_indices=True)
        # the level way back: each slice's own nearest free voxel; a slice with none keeps the way in three dimensions
        self.full = g.all((0, 2))
        self.ix = np.broadcast_to(np.arange(g.shape[0])[:, None, None], g.shape).astype(np.int32)
        self.iz = np.broadcast_to(np.arange(g.shape[2])[None, None, :], g.shape).astype(np.int32)
        for jj in np.flatnonzero(g.any((0, 2)) & ~self.full):
            _, (ax, az) = ndimage.distance_transform_edt(g[:, jj, :], return_indices=True)
            self.ix[:, jj, :], self.iz[:, jj, :] = ax, az

    def inside(self, p):
        idx = np.floor((p - self.lo) / self.h).astype(int)
        ok = ((idx >= 0) & (idx < self.g.shape)).all(1)
        out = np.zeros(len(p), bool)
        out[ok] = self.g[tuple(idx[ok].T)]
        return out

    def way_out(self, p, margin):
        idx = np.clip(np.floor((p - self.lo) / self.h).astype(int), 0, np.array(self.g.shape) - 1)
        q = self.lo + (np.stack([self.ind[k][tuple(idx.T)] for k in range(3)], 1) + 0.5) * self.h
        level = ~self.full[idx[:, 1]]
        q[level, 0] = self.lo[0] + (self.ix[tuple(idx[level].T)] + 0.5) * self.h
        q[level, 2] = self.lo[2] + (self.iz[tuple(idx[level].T)] + 0.5) * self.h
        q[level, 1] = p[level, 1]
        d = q - p
        return d + d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) * margin


def carry(x, p, d, a, sigma):
    """The points x moved by the moves d of the surface p (each standing for a share a of it): their Gaussian mean
    by area over 3 sigma, as the airways and vessels inside a lung go with it."""
    from scipy.spatial import cKDTree as Tree
    moving = np.flatnonzero(np.linalg.norm(d, axis=1) > 1e-6)
    out = x.copy()
    if not len(moving):
        return out
    tree = Tree(p)
    for s in range(0, len(x), 2000):
        near = tree.query_ball_point(x[s:s + 2000], 3 * sigma)
        for k, idx in enumerate(near):
            if not idx:
                continue
            idx = np.asarray(idx)
            w = a[idx] * np.exp(-((p[idx] - x[s + k]) ** 2).sum(1) / (2 * sigma ** 2))
            if w.sum() > 0:
                out[s + k] += (w[:, None] * d[idx]).sum(0) / w.sum()
    return out


def give_way(folder, body, parts, after, column):
    """The soft parts the seated ribs run into moved off them. after: the ribs part's meshes; column: the vertebral
    column's {node: (v, f)}. The lungs, joined (their segments tile them), are moved back into the chest's cavity
    (Cavity) by one smooth field (tools/anatomy_gaps.py push_out), carrying the airways and vessels about them
    (carry()); every other part about the cage, its structures there joined, is moved out of the ribs by the
    nearest way, as is what the lungs carried that is left in a rib."""
    from anatomy_fibres import read_part
    from anatomy_gaps import Solid, push_out, vertex_area
    from anatomy_bones import rewrite, SETTLE_SIGMA, SETTLE_ROUNDS
    ribs = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for v, f in after]
    solids = [Solid([m]) for m in ribs]
    cage = np.concatenate([v for v, _ in ribs])
    lo, hi = cage.min(0) - 3 * SETTLE_SIGMA, cage.max(0) + 3 * SETTLE_SIGMA
    in_ribs = lambda q: np.any([s.inside(q) for s in solids], 0)
    loaded, moved, said = {}, set(), []

    def load(pid):
        if pid not in loaded:
            loaded[pid] = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
                           for v, f in read_part(os.path.join(folder, parts[pid]["file"]))]
        return loaded[pid]

    def near(meshes):
        return [i for i, (v, _) in enumerate(meshes) if (v.max(0) > lo).all() and (v.min(0) < hi).all()]

    def joined(meshes, take):
        cut = np.cumsum([0] + [len(meshes[i][0]) for i in take])
        return (np.concatenate([meshes[i][0] for i in take]),
                np.concatenate([meshes[i][1] + cut[k] for k, i in enumerate(take)]), cut)

    if "lungs" in parts:
        lungs = load("lungs")
        take = near(lungs)
        p0, f0, cut = joined(lungs, take)
        walls = ribs + ([(np.asarray(v, np.float64), np.asarray(f, np.int64)) for v, f in load("sternum")]
                        if "sternum" in parts else [])
        spine = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for k, (v, f) in column.items()
                 if "thoracic" in k]
        everything = np.vstack([p0] + [v for v, _ in walls + spine])
        C = Cavity([v for v, _ in walls], walls + spine, everything.min(0) - 0.02, everything.max(0) + 0.02,
                   stops=[v for v, _ in spine])
        was = C.inside(p0).mean()
        q = push_out(p0, [C], margin=0.003, sigma=SETTLE_SIGMA, rounds=4 * SETTLE_ROUNDS, step=0.003, f=f0,
                     alike=True)
        if C.inside(q).any():      # what the smooth field left, moved again over a smaller reach (by the spine)
            q = push_out(q, [C], margin=0.003, sigma=SETTLE_SIGMA / 2, rounds=2 * SETTLE_ROUNDS, step=0.002, f=f0)
        for k, i in enumerate(take):
            lungs[i] = (q[cut[k]:cut[k + 1]], lungs[i][1])
        moved.add("lungs")
        d = q - p0
        line = (f"lungs: {was:.1%} out of the chest's cavity (in or behind a rib, or in the column) -> "
                f"{C.inside(q).mean():.1%}, moved up to {np.linalg.norm(d, axis=1).max() * 1000:.0f} mm")
        a = vertex_area(p0, f0)
        for r in ("airways", "vessels"):                         # what lies in and about them goes with them
            if r not in parts:
                continue
            rm = load(r)
            most = 0.0
            for i in near(rm):
                v, f = rm[i]
                w = carry(v, p0, d, a, SETTLE_SIGMA)
                most = max(most, float(np.linalg.norm(w - v, axis=1).max()))
                rm[i] = (w, f)
            if most > 1e-5:
                moved.add(r)
                line += f", the {r} with them up to {most * 1000:.0f} mm"
        said.append(line)
    for pid in SOFT:
        if pid not in parts or pid == "lungs":
            continue
        meshes = load(pid)
        take = [i for i in near(meshes) if in_ribs(meshes[i][0]).any()]
        if not take:
            continue
        p0, f0, cut = joined(meshes, take)
        was = in_ribs(p0)
        q = push_out(p0, solids, margin=0.002, sigma=SETTLE_SIGMA, rounds=2 * SETTLE_ROUNDS, step=0.004, f=f0,
                     alike=True)
        for k, i in enumerate(take):
            meshes[i] = (q[cut[k]:cut[k + 1]], meshes[i][1])
        moved.add(pid)
        said.append(f"{pid}: {was.mean():.1%} of what was near in the ribs -> {in_ribs(q).mean():.1%} (moved up to "
                    f"{np.linalg.norm(q - p0, axis=1).max() * 1000:.0f} mm)")
    for pid in sorted(moved):
        rewrite(folder, parts[pid], loaded[pid])
    return "; ".join(said) or "nothing in the way"


def remake(folder, quiet=False):
    """Seats the ribs of both bodies in `folder`'s atlas (anatomy.json and its part files); does nothing if they
    are seated already. Returns what it did."""
    from anatomy_fibres import read_part
    from anatomy_bones import rewrite
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if body.get("ribs seated"):
            continue
        parts = {p["id"]: p for p in body["parts"]}
        if "ribs" not in parts or "vertebral-column" not in parts:
            continue
        pre = "VH_M_" if body["id"] == "male" else "VH_F_"
        col = parts["vertebral-column"]
        column = dict(zip([s["node"] for s in col["structures"]], read_part(os.path.join(folder, col["file"]))))
        rp = parts["ribs"]
        before = read_part(os.path.join(folder, rp["file"]))
        after, account = seat(column, list(zip([s["node"] for s in rp["structures"]], before)), pre)
        rewrite(folder, rp, after)
        said.append(f"{body['id']}: {account}; out of the ribs: {give_way(folder, body, parts, after, column)}")
        body["ribs seated"] = True
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            print("  " + line)
    return "; ".join(said) or "the ribs seated already"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
