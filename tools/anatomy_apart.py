"""Each tube in the atlas closed at its holes, its cut ends open and hollow, and the pelvis's structures kept out
of one another.

The organ sets (the HRA's 3D reference organs, CC BY 4.0) draw a vessel or a gut as a tube cut open where
it meets the next one: a vein where it drains into the next, the rectum where it meets the sigmoid colon, a
branch's mouth where it leaves its trunk. Seen alone, or with its neighbour hidden, such a tube showed a ragged
hole and the back of its own wall (the app draws a solid structure from both sides). So each hole is closed
here, as a whole structure is closed, but a cut across a tube is left open, as a cut tube is (the owner, 6 Nov:
"they are normally hollow in a human"; a dome over it read as a solid stump). Many of the organ sets' tubes are
drawn with their lumen, an inner wall inside the outer one (the gut, the great vessels, the ducts), so a cut
there shows two rims: they are joined by the ring of the wall between them (the rectum's 3 mm). A tube drawn
without its lumen is given one at a cut end: its wall a ring in from the rim, as thick as its tissue's (an
artery's an eighth of its radius, a vein's a fourteenth, a duct's three tenths, a gut's 3 mm and an airway's
2 mm, none under 0.35 mm, so it shows), its lumen a sleeve along the tube's own axis (an aslant cut's too) to
its cross-section 1.2 radii in, then narrowing to a seal 3 radii in, or as deep as it lies wholly inside the
tube, out of sight. Where a tube runs too short behind its cut to hold a lumen (a stub where three meet), and
over a branch's mouth, cut out of a curved wall, a sheet closes the hole, smoothed with its rim held. The
ring's points are new ones at the rim's own places (the app lights the cut as a sharp edge, the tube's side and
the ring each with its own normal), and each tube stays a closed surface. Where two tubes join, each one's ring
lies in the joint and its lumen inside itself, so nothing shows while both are shown (the domes before lay each
inside the other). A narrow end (under 4 mm across its radius) keeps half as many points round its wall's inner
edge as on its rim, one under 1.5 mm a third and a cone for its lumen: the ends cost little of the atlas's
triangle budget.

Before that, in the pelvis, nothing passes into anything else (the owner: "elements shouldn't phase through
each other"): first the sacrum, another man's scanned bone on this body's hip bones, drawn out of them at its
joints (see ease_sacrum()); then the soft structures out of the bones and one another (see apart()), the tubes
sheeted flat across their holes while that is done (see cap()).
"""
import math
import os
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anatomy_fibres import read_part, sha256, write_part  # noqa: E402

# The parts whose structures are tubes, and from the kidneys' part the ureters
TUBES = ("vessels", "colon", "small-intestine", "urethra", "genital-ducts", "uterine-tubes", "vagina",
         "biliary-tree")
TUBE_NODES = {"kidneys": "ureter"}
CLOSE_ENDS = True     # each tube closed at its holes (close()) once the pelvis is parted, its cut ends open and
                      # hollow (the owner, 6 Nov: "they are normally hollow in a human"), no longer domed
FLAT = 0.15           # a cut end is flat: its rim within this share of its radius of a plane (root mean square)
ONE_SIDED = 0.9       # and nine in ten of the tube's points near it (within 2.5 radii) on one side of it
FAN, ONE_RING = 0.004, 0.012   # a mouth's radius under which its sheet is a fan; under which it has one ring
WALL_SHARE = {"artery": 0.12, "vein": 0.07}    # a cut end's wall: a vessel's this share of its radius,
WALL_MM = {"gut": 0.003, "airway": 0.002}      # a gut's and an airway's this many metres (at most WALL_MOST of
WALL_DUCT, WALL_MOST = 0.3, 0.3                # its radius), any other's (a duct's, an organ's) WALL_DUCT of it;
WALL_MIN = 0.00035                             # none thinner than 0.35 mm, or it would not show
SLEEVE, SEAL = 1.2, 3.0        # the lumen's sleeve runs this many radii in, then narrows to its seal this far in
FINE, COARSE = 0.004, 0.0015   # an end this wide keeps a point round its wall's inner edge for each of its rim's,
                               # a narrower one half as many, one under COARSE a third and a cone for its lumen
PAIR = 0.5            # two rims of a structure are one double wall's: the inner inside the outer, facing alike,
                      # its middle within this share of the outer's radius of the outer's, across and along


def cycles(f):
    """A mesh's holes: each a cycle of its points, in the order its triangles run along the rim (an edge a->b
    of a triangle with no other triangle across it); a rim that touches itself at a point is split there into
    simple cycles, and a rim that cannot be closed (the mesh not a surface there) is left out."""
    f = np.asarray(f, np.int64)
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    _, inv, cnt = np.unique(np.sort(E, 1), axis=0, return_inverse=True, return_counts=True)
    rim = E[cnt[inv.reshape(-1)] == 1]
    out = defaultdict(list)
    for a, b in rim:
        out[int(a)].append(int(b))
    found = []
    while out:
        path = [next(iter(out))]
        where = {path[0]: 0}
        while path:
            x = path[-1]
            if x not in out:
                break                       # a dead end: the rest of the path cannot close
            b = out[x].pop()
            if not out[x]:
                del out[x]
            if b in where:
                k = where[b]
                loop = path[k:]
                if len(loop) >= 3:
                    found.append(np.array(loop, np.int64))
                for y in path[k + 1:]:
                    where.pop(y, None)
                path = path[:k + 1]
                if b not in out:
                    break
            else:
                where[b] = len(path)
                path.append(b)
    return found


def around(q, s):
    """The points at arc-length shares s (0 to 1) along the closed polyline q."""
    seg = np.linalg.norm(np.roll(q, -1, 0) - q, axis=1)
    t = np.r_[0, np.cumsum(seg)] / max(seg.sum(), 1e-12)
    i = np.clip(np.searchsorted(t, s, side="right") - 1, 0, len(q) - 1)
    w = ((s - t[i]) / np.maximum(t[i + 1] - t[i], 1e-12))[:, None]
    return q[i] * (1 - w) + q[(i + 1) % len(q)] * w, t


def zip_rings(outer, t_outer, inner, s_inner):
    """Triangles between two rings of point ids, each in the rim's order and starting at the same place, wound
    as the cap must be (across from the rim's edge a->b, the cap's triangle runs b->a)."""
    m, k = len(outer), len(inner)
    tris, i, j = [], 0, 0
    while i < m or j < k:
        rim_next = t_outer[i + 1] if i < m else np.inf
        ring_next = s_inner[j + 1] if j < k else np.inf
        if rim_next <= ring_next:
            tris.append((outer[(i + 1) % m], outer[i], inner[j % k]))
            i += 1
        else:
            tris.append((outer[i % m], inner[j % k], inner[(j + 1) % k]))
            j += 1
    return tris


def frame(n):
    """Two unit vectors across n, and n's turn about them (right-handed)."""
    a = np.array([1.0, 0.0, 0.0]) if abs(n[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    e1 = np.cross(n, a)
    e1 /= np.linalg.norm(e1)
    return e1, np.cross(n, e1)


def plane(p, c, e1, e2):
    """Points in the plane across n: their offsets from c along e1 and e2."""
    d = np.atleast_2d(p) - c
    return np.stack([d @ e1, d @ e2], 1)


def turning(xy):
    """Twice the signed area of a closed polygon in the plane (positive anticlockwise)."""
    x, y = xy[:, 0], xy[:, 1]
    return float((x * np.roll(y, -1) - np.roll(x, -1) * y).sum())


def encloses(poly, xy):
    """Whether the closed polygon (in the plane) holds each point (even-odd)."""
    x, y = xy[:, :1], xy[:, 1:]
    x0, y0 = poly[None, :, 0], poly[None, :, 1]
    x1, y1 = np.roll(poly[:, 0], -1)[None], np.roll(poly[:, 1], -1)[None]
    across = (y0 > y) != (y1 > y)
    at = x0 + (y - y0) * (x1 - x0) / np.where(y1 != y0, y1 - y0, 1.0)
    return (across & (x < at)).sum(1) % 2 == 1


def rim(v, loop):
    """A hole's rim: its points' ids, its middle, the normal of its plane turned away from the tube, its mean
    radius, and whether it is a cut across the tube (flat, the tube on one side of it)."""
    q = v[loop]
    c = q.mean(0)
    _, _, vt = np.linalg.svd(q - c)
    n = vt[2]
    r = float(np.linalg.norm(q - c, axis=1).mean())
    flat = math.sqrt(float((((q - c) @ n) ** 2).mean())) / max(r, 1e-12)
    near = v[np.linalg.norm(v - c, axis=1) < 2.5 * r]
    side = (near - c) @ n
    if side.mean() > 0:
        n, side = -n, -side                 # the tube behind the rim
    sure = np.abs(side) > 0.15 * r
    one = float((side[sure] < 0).mean()) if sure.any() else 0.0
    return {"loop": loop, "c": c, "n": n, "r": r, "cut": flat < FLAT and one >= ONE_SIDED}


def pair_up(v, holes):
    """The double walls among a structure's holes: (outer, inner) pairs, the inner rim inside the outer and
    near its plane, each hole in one pair at most, the nearest first."""
    found = []
    for i, a in enumerate(holes):
        e1, e2 = frame(a["n"])
        poly = plane(v[a["loop"]], a["c"], e1, e2)
        for j, b in enumerate(holes):
            if j == i or not 0.3 * a["r"] < b["r"] < a["r"] or abs(float(a["n"] @ b["n"])) < 0.7:
                continue
            d = b["c"] - a["c"]
            along = abs(float(d @ a["n"]))
            across = float(np.linalg.norm(d - (d @ a["n"]) * a["n"]))
            if along > PAIR * a["r"] or across > PAIR * a["r"]:
                continue
            if encloses(poly, plane(v[b["loop"]], a["c"], e1, e2)).mean() < 0.9:
                continue
            found.append((along + across + a["r"] - b["r"], i, j))
    pairs, used = [], set()
    for _, i, j in sorted(found):
        if i not in used and j not in used:
            used |= {i, j}
            pairs.append((i, j))
    return pairs


def sweep(xy, sense, ref):
    """Shares round a rim (in the plane, about its middle) by the angle each point makes there, from the angle
    `ref` on, the rim turning the way `sense` says; None where it does not go once round in steps all one way."""
    ang = np.arctan2(xy[:, 1], xy[:, 0])
    step = np.angle(np.exp(1j * (np.roll(ang, -1) - ang))) * sense
    if (step <= 0).any() or abs(step.sum() - 2 * math.pi) > 0.5:
        return None
    return (np.angle(np.exp(1j * (ang[0] - ref))) * sense + np.r_[0, np.cumsum(step)]) / (2 * math.pi)


def edge_gap(P, poly):
    """How far each point lies inside the closed polygon (in the plane), from its nearest edge; negative outside."""
    a, d = poly, np.roll(poly, -1, 0) - poly
    t = np.clip(((P[:, None] - a[None]) * d[None]).sum(2) / np.maximum((d * d).sum(1), 1e-18)[None], 0, 1)
    gap = np.linalg.norm(P[:, None] - (a[None] + t[..., None] * d[None]), axis=2).min(1)
    return np.where(encloses(poly, P), gap, -gap)


def join_walls(v, a, b, start):
    """A double wall's cut: the ring from its outer rim a to its inner rim b, its points new ones at the rims'
    places (numbered from `start`), the two zipped by the angle about the outer's middle. Where the inner rim
    strays out to the outer (a thin wall drawn unevenly), its points are first drawn in, a quarter of the wall
    inside it. Returns the ring's points and triangles, and the inner rim's points as they now lie."""
    q, p = v[a["loop"]], v[b["loop"]].copy()
    e1, e2 = frame(a["n"])
    xq, xp = plane(q, a["c"], e1, e2), plane(p, a["c"], e1, e2)
    keep = max(0.25 * (a["r"] - b["r"]), 1e-5)
    gap = edge_gap(xp, xq)
    shy = gap < keep
    if shy.any():
        towards = xp[shy] / np.maximum(np.linalg.norm(xp[shy], axis=1, keepdims=True), 1e-12)
        move = np.minimum(keep - gap[shy], 0.5 * np.linalg.norm(xp[shy], axis=1))[:, None] * towards
        p[shy] -= move[:, :1] * e1 + move[:, 1:] * e2
        xp = plane(p, a["c"], e1, e2)
    moved = p.copy()
    order = np.arange(len(p))
    if turning(xq) * turning(xp) < 0:
        order = order[::-1]                 # both rims turning the same way
    sense = 1.0 if turning(xq) > 0 else -1.0
    ref = math.atan2(xq[0, 1], xq[0, 0])
    order = np.roll(order, -int(np.argmin(np.abs(np.angle(np.exp(1j * (np.arctan2(xp[order, 1], xp[order, 0])
                                                                          - ref)))))))
    p, xp = p[order], xp[order]
    t, s = sweep(xq, sense, ref), sweep(xp, sense, ref)
    if t is None or s is None:
        t, s = around(q, np.zeros(1))[1], around(p, np.zeros(1))[1]
    m, k = len(q), len(p)
    T = zip_rings(list(range(start, start + m)), t, list(range(start + m, start + m + k)), s)
    return np.concatenate([q, p]), np.array(T, np.int64), moved


def radii(v, f, o, n, e1, e2, U):
    """In the plane through o across n, along each direction U (k by 2, over e1 and e2): the distance to the
    nearest place the surface f crosses it, or inf where it does not."""
    s = (v - o) @ n
    s = np.where(s == 0, 1e-12, s)
    sf = s[f]
    up = sf > 0
    cut = up.any(1) & ~up.all(1)
    F, sf, up = f[cut], sf[cut], up[cut]
    if not len(F):
        return np.full(len(U), np.inf)
    ends, crossing = [], []
    for a, b in ((0, 1), (1, 2), (2, 0)):
        crossing.append(up[:, a] != up[:, b])
        share = sf[:, a] / np.where(crossing[-1], sf[:, a] - sf[:, b], 1.0)
        ends.append(v[F[:, a]] + (v[F[:, b]] - v[F[:, a]]) * share[:, None])
    two = np.argsort(~np.stack(crossing, 1), axis=1, kind="stable")[:, :2]
    ends, rows = np.stack(ends, 1), np.arange(len(F))
    x0 = plane(ends[rows, two[:, 0]], o, e1, e2)
    d = plane(ends[rows, two[:, 1]], o, e1, e2) - x0
    ux, uy = U[:, :1], U[:, 1:]
    den = ux * d[None, :, 1] - uy * d[None, :, 0]
    den = np.where(np.abs(den) < 1e-18, 1e-18, den)
    lam = (x0[None, :, 0] * d[None, :, 1] - x0[None, :, 1] * d[None, :, 0]) / den
    mu = (x0[None, :, 0] * uy - x0[None, :, 1] * ux) / den
    return np.where((lam > 0) & (mu >= 0) & (mu <= 1), lam, np.inf).min(1)


def crosses(P0, P1, tri):
    """Whether any of the segments P0 -> P1 passes through any of the triangles tri (T by 3 by 3)."""
    if not len(tri):
        return False
    a = tri[:, 0]
    e1, e2 = tri[:, 1] - a, tri[:, 2] - a
    D = np.broadcast_to(P1, P0.shape) - P0
    for i in range(0, len(tri), 4000):
        sl = slice(i, i + 4000)
        pv = np.cross(D[:, None, :], e2[None, sl])
        det = (pv * e1[None, sl]).sum(2)
        inv = 1.0 / np.where(np.abs(det) < 1e-24, 1e-24, det)
        tv = P0[:, None, :] - a[None, sl]
        u = (tv * pv).sum(2) * inv
        qv = np.cross(tv, e1[None, sl])
        w = (D[:, None, :] * qv).sum(2) * inv
        t = (e2[None, sl] * qv).sum(2) * inv
        if ((np.abs(det) >= 1e-24) & (u >= 0) & (w >= 0) & (u + w <= 1) & (t > 1e-6) & (t < 1 - 1e-6)).any():
            return True
    return False


def inward(P, mid, n, w):
    """The points P moved w toward mid, across n (never more than nine tenths of the way)."""
    d = P - mid
    d = d - np.outer(d @ n, n)
    ln = np.linalg.norm(d, axis=1, keepdims=True)
    return P - d / np.maximum(ln, 1e-12) * np.minimum(w, 0.9 * ln)


def wall(tissue, r):
    """A cut end's wall, by the tube's tissue and radius."""
    if tissue in WALL_SHARE:
        w = WALL_SHARE[tissue] * r
    elif tissue in WALL_MM:
        w = min(WALL_MM[tissue], WALL_MOST * r)
    else:
        w = WALL_DUCT * r
    return max(w, min(WALL_MIN, 0.45 * r))


def hollow_end(v, f, h, w, start):
    """A cut end left open (see the header): its wall a ring from the rim in by w, its lumen a sleeve along the
    tube's axis to its cross-section SLEEVE radii in, w inside it, then a cone to the axis SEAL radii in, or as
    deep as the cone lies wholly inside the tube. v, f: the tube's points and the triangles of its surface the
    rim is on; h: the rim (rim()); its points new ones (numbered from `start`). Returns the points and the
    triangles, or None where the tube runs too short behind its rim to hold a lumen."""
    loop, c, n, r = h["loop"], h["c"], h["n"], h["r"]
    q = v[loop]
    m = len(loop)
    e1, e2 = frame(n)
    w = min(w, 0.45 * float(np.linalg.norm(plane(q, c, e1, e2), axis=1).min()))
    if w <= 0:
        return None
    own = v[np.unique(f)] - c
    tv = v[f] - c

    def reach(a):
        """How far the tube runs behind the rim along a, near that line."""
        d = own @ a
        return float(d[np.linalg.norm(own - np.outer(d, a), axis=1) < 1.5 * r].max(initial=0.0))

    def nearby(a, deep):
        """The tube's triangles about the line from c along a, to `deep` past it."""
        d = tv @ a
        lt = np.linalg.norm(tv - d[..., None] * a, axis=2)
        return f[(d.min(1) < deep + r) & (d.max(1) > -0.5 * r) & (lt.min(1) < 3 * r)]

    def middle(o, a, b1, b2, U, near):
        """The middle of the tube's cross-section through o across a, and the distances from it to the tube
        along the directions U (over b1, b2), or (o, None) where the plane there does not go round the tube."""
        out = U[:, :1] * b1 + U[:, 1:] * b2
        for _ in range(2):
            dist = radii(v, near, o, a, b1, b2, U)
            hit = dist < 2.5 * r
            if hit.mean() < 0.75:
                return o, None
            o = o + (dist[hit, None] * out[hit]).mean(0)
        return o, radii(v, near, o, a, b1, b2, U)

    # the tube's axis behind the rim (a cut may run across it aslant): to the middles of its cross-sections one
    # and two radii in
    a = -n
    turn = np.arange(12) * (2 * math.pi / 12)
    U12 = np.stack([np.cos(turn), np.sin(turn)], 1)
    for depth in (r, 2 * r):
        if depth > 0.45 * reach(a):
            break
        b1, b2 = frame(a)
        g, dist = middle(c + a * depth, a, b1, b2, U12, nearby(a, depth + r))
        if dist is None:
            break
        ax = (g - c) / np.linalg.norm(g - c)
        if ax @ -n < 0.5:
            break
        a = ax
    seal = min(SEAL * r, 0.45 * reach(a))
    near = nearby(a, seal)
    tri = v[near]
    b1, b2 = frame(a)
    k = m if r >= FINE else max(6, -(-m // 2)) if r >= COARSE else max(4, -(-m // 3))
    _, t = around(q, np.zeros(1))
    s = t if k == m else np.arange(k + 1) / k
    A = inward(q.copy() if k == m else around(q, s[:k])[0], c, n, w)
    xa = plane(A, c, b1, b2)
    ra = np.linalg.norm(xa, axis=1)
    U = xa / np.maximum(ra, 1e-12)[:, None]
    out = U[:, :1] * b1 + U[:, 1:] * b2
    top = float(((A - c) @ a).max())         # the wall's inner edge reaches this far in (an aslant cut's)
    if seal < top + 0.2 * r:
        return None
    last = list(range(start + m + k, start + m + 2 * k))
    nxt = start + m + 2 * k
    pts = [q, A, A]                           # the rim, the wall's inner edge, and the lumen's own copy of it
    T = zip_rings(list(range(start, start + m)), t, list(range(start + m, start + m + k)), s)
    P, gone, drift = A, top, np.zeros(3)
    if r >= COARSE:
        # the sleeve: on the tube's cross-section, w inside it, never wider than the wall's inner edge
        t1 = top + (seal - top) * SLEEVE / SEAL
        for _ in range(3):
            if t1 < top + 0.15 * r:
                break
            o, dist = middle(c + a * t1, a, b1, b2, U, near)
            if dist is not None:
                rho = np.minimum(dist - w, ra)
                B = o + rho[:, None] * out
                if rho.min() > 0.15 * r and not crosses(A, B, tri):
                    down = list(range(nxt, nxt + k))
                    nxt += k
                    pts.append(B)
                    T += zip_rings(last, s, down, s)
                    last, P, gone, drift = down, B, t1, (o - (c + a * t1)) / t1
                    break
            t1 = top + 0.6 * (t1 - top)
    # the seal: the middle of the tube's cross-section that deep (followed as the tube bends), as deep as the
    # cone to it lies wholly inside the tube
    for t2 in (seal, gone + 0.6 * (seal - gone), gone + 0.35 * (seal - gone), gone + 0.15 * r, gone + 0.08 * r):
        if t2 <= gone:
            continue
        apex = middle(c + a * t2 + drift * t2, a, b1, b2, U, near)[0]
        if not crosses(P, apex[None], tri):
            pts.append(apex[None])
            T += [(last[(j + 1) % k], last[j], nxt) for j in range(k)]
            return np.concatenate(pts), np.array(T, np.int64)
    return None


def sheet(v, loop, start):
    """A sheet over a hole that is not a cut across the tube (a branch's mouth, cut out of a curved wall): its
    new points (numbered from `start`) and its triangles over the mesh's point ids. A small hole (under FAN
    across its radius) a fan from its rim to its middle; a larger one with a ring of half as many points between,
    a large one (ONE_RING) two; its inner points each moved to its neighbours' mean, the rim held."""
    q = v[loop]
    m = len(loop)
    c = q.mean(0)
    r = float(np.linalg.norm(q - c, axis=1).mean())
    levels = 0 if r < FAN else (1 if r < ONE_RING else 2)
    pts, tris = [], []
    _, t = around(q, np.zeros(1))
    outer, t_outer = list(loop), t
    nxt = start
    for lev in range(1, levels + 1):
        k = max(3, int(math.ceil(m / 2 ** lev)))
        s = np.arange(k + 1) / k
        P, _ = around(q, s[:k])
        ids = list(range(nxt, nxt + k))
        nxt += k
        pts.append(c + (P - c) * (1 - lev / (levels + 1)))
        tris += zip_rings(outer, t_outer, ids, s)
        outer, t_outer = ids, s
    top = nxt
    pts.append(c[None])
    kk = len(outer)
    tris += [(outer[(j + 1) % kk], outer[j], top) for j in range(kk)]
    P = np.concatenate(pts)
    T = np.array(tris, np.int64)
    if levels:
        ids = np.unique(T)
        at = {g: i for i, g in enumerate(ids)}
        X = np.array([v[g] if g < start else P[g - start] for g in ids])
        nb = defaultdict(set)
        for a, b, cc in T:
            for x, y in ((a, b), (b, cc), (cc, a)):
                nb[at[x]].add(at[y])
                nb[at[y]].add(at[x])
        free = [at[g] for g in range(start, start + len(P))]
        lists = [np.array(sorted(nb[i])) for i in free]
        for _ in range(20):
            X[free] = np.array([X[lst].mean(0) for lst in lists])
        P = X[free]
    return P, T


def close_tubes(v, f, tissue=None):
    """The mesh with each of its holes closed (see the header): a double wall's two rims joined, a cut end left
    open and hollow, any other hole sheeted; the new points after the old, the new triangles after the old.
    Returns (v, f, how many of each {"joined", "hollow", "sheet"}, [(each hole's middle, its radius)])."""
    from collections import Counter
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    v = np.array(v, np.float64)
    f = np.asarray(f, np.int64)
    # holes are found on the mesh with points at one place made one; a sheet meets the mesh at its own points
    key = np.round(v * 1e6).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    wf = inverse[f]
    wf = wf[(wf[:, 0] != wf[:, 1]) & (wf[:, 1] != wf[:, 2]) & (wf[:, 2] != wf[:, 0])]
    wv = v[first]
    loops = cycles(wf)
    if not loops:
        return v, f, {}, []
    E = np.concatenate([wf[:, [0, 1]], wf[:, [1, 2]]])
    _, piece = connected_components(coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(len(wv),) * 2),
                                    directed=False)
    holes = [rim(wv, loop) for loop in loops]
    newp, newf, said = [], [], Counter()
    start = len(v)

    def add(P, T, kind):
        nonlocal start
        newp.append(P)
        newf.append(T)
        start += len(P)
        said[kind] += 1
    done, drawn = set(), {}
    for i, j in pair_up(wv, holes):
        P, T, moved = join_walls(wv, holes[i], holes[j], start)
        add(P, T, "joined")
        drawn.update(zip(holes[j]["loop"].tolist(), moved))
        done |= {i, j}
    if drawn:                               # an inner rim drawn in: its points, wherever the mesh has them
        ids = np.array(list(drawn))
        wv[ids] = np.array(list(drawn.values()))
        at = np.isin(inverse, ids)
        v[at] = wv[inverse[at]]
    for i, h in enumerate(holes):
        if i in done:
            continue
        made = None
        if h["cut"]:
            made = hollow_end(wv, wf[piece[wf[:, 0]] == piece[h["loop"][0]]], h, wall(tissue, h["r"]), start)
        if made is not None:
            add(*made, "hollow")
            continue
        P, T = sheet(wv, h["loop"], start)
        add(P, np.where(T < len(wv), first[np.minimum(T, len(wv) - 1)], T), "sheet")
    return (np.concatenate([v] + newp), np.concatenate([f] + newf), dict(said),
            [(h["c"], h["r"]) for h in holes])


def rewrite(folder, part, meshes):
    lo, hi = write_part(os.path.join(folder, part["file"]),
                        [(np.asarray(v, np.float32), np.asarray(f, np.int64)) for v, f in meshes])
    for st, (_, f) in zip(part["structures"], meshes):
        st["triangles"] = int(len(f))
    part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
    part["sha256"] = sha256(os.path.join(folder, part["file"]))
    part["triangles"] = int(sum(s["triangles"] for s in part["structures"]))
    part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]


def close(folder, body, ends=None):
    """Each tube of the body's TUBES parts (and TUBE_NODES' structures) closed at its holes, its cut ends open
    and hollow (see the header), its part rewritten. `ends`, a dict, gets each closed structure's holes,
    {node: [(middle, radius), ...]}. Returns an account."""
    said = []
    for part in body["parts"]:
        pid = part["id"]
        if pid not in TUBES and pid not in TUBE_NODES:
            continue
        meshes = read_part(os.path.join(folder, part["file"]))
        added, made = 0, defaultdict(int)
        for i, (st, (v, f)) in enumerate(zip(part["structures"], meshes)):
            if pid in TUBE_NODES and TUBE_NODES[pid] not in st["node"]:
                continue
            nv, nf, how, where = close_tubes(v, f, st.get("tissue"))
            if where:
                added += len(nf) - len(f)
                for kind, n in how.items():
                    made[kind] += n
                meshes[i] = (nv, nf)
                if ends is not None:
                    ends[st["node"]] = where
        if made:
            rewrite(folder, part, meshes)
            said.append(f"{pid} {made['hollow']} cut ends hollow, {made['joined']} double walls joined, "
                        f"{made['sheet']} mouths sheeted (+{added} triangles)")
    return "; ".join(said) or "no tube open"


def cap(folder, body, ends=None):
    """Each tube's holes sheeted over for the parting alone (see remake()): apart() tells what lies inside a
    structure by its closed surface, and a hollow end's lumen is outside it, so the pelvis is parted against
    tubes closed flat across their cuts and the sheets taken off again (uncap()). The sheets' points and
    triangles come after each mesh's own. `ends` gets each tube's holes, as close() gives them. Returns each
    part's meshes' sizes before the sheets, {part id: [(points, triangles), ...]}."""
    sizes = {}
    for part in body["parts"]:
        pid = part["id"]
        if pid not in TUBES and pid not in TUBE_NODES:
            continue
        meshes = read_part(os.path.join(folder, part["file"]))
        sizes[pid] = [(len(v), len(f)) for v, f in meshes]
        changed = False
        for i, (st, (v, f)) in enumerate(zip(part["structures"], meshes)):
            if pid in TUBE_NODES and TUBE_NODES[pid] not in st["node"]:
                continue
            v = np.array(v, np.float64)
            f = np.asarray(f, np.int64)
            key = np.round(v * 1e6).astype(np.int64)
            _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
            wf = inverse.reshape(-1)[f]
            wf = wf[(wf[:, 0] != wf[:, 1]) & (wf[:, 1] != wf[:, 2]) & (wf[:, 2] != wf[:, 0])]
            wv = v[first]
            loops = cycles(wf)
            if not loops:
                continue
            newp, newf, start = [], [], len(v)
            for loop in loops:
                P, T = sheet(wv, loop, start)
                newp.append(P)
                newf.append(np.where(T < len(wv), first[np.minimum(T, len(wv) - 1)], T))
                start += len(P)
            meshes[i] = (np.concatenate([v] + newp), np.concatenate([f] + newf))
            changed = True
            if ends is not None:
                ends[st["node"]] = [(h["c"], h["r"]) for h in (rim(wv, loop) for loop in loops)]
        if changed:
            rewrite(folder, part, meshes)
    return sizes


def uncap(folder, body, sizes):
    """cap()'s sheets taken off again: each mesh cut back to its own points and triangles, where the parting
    has left them."""
    for part in body["parts"]:
        if part["id"] not in sizes:
            continue
        meshes = read_part(os.path.join(folder, part["file"]))
        if any(len(v) != n or len(f) != k for (v, f), (n, k) in zip(meshes, sizes[part["id"]])):
            rewrite(folder, part, [(v[:n], f[:k]) for (v, f), (n, k) in zip(meshes, sizes[part["id"]])])


# MARK: the sacrum off the hip bones

# The sacrum is a scan of another man's (tools/anatomy_bones.py), seated by its joints on this body's hip bones:
# its auricular surfaces come to lie by the ilia's, but where the two bones' shapes differ, parts of its sides
# lie inside the ilia (1 to 4 mm deep, some 70 to 250 of its points a side). Each such point is drawn back into
# the sacrum along its own inward normal, as far as it lies inside and a joint's width more, the move spread
# smoothly over the points about it (each by the surface it stands for, as tools/anatomy_gaps.py push_out spreads
# its pulls), round after round until none lies inside: the sacrum's side takes the ilium's shape there, a
# joint's width off it, and the hip bones stay as they are. (Pushed the shortest way out of the ilium instead,
# the points in a thin plate of it went either way and their pulls cancelled.) Where that would bend the sacrum,
# an edge stretched or shrunk past one and a half times its length, it is left as it was: the man's hip bones are
# his organ set's, thin plates the scan's sacrum crosses over some 250 points a side, and drawing it out of them
# dented it 10 to 20 mm (wanted: his hip bones from his CT, as the woman's are from hers).
SI_GAP = 0.001         # a joint's width
SI_SIGMA = 0.004       # each move spread over this
SI_REACH = 0.008       # a point looked for this far in (one deeper along its normal, which runs along a thin plate
                       # of the ilium rather than through it, is left to its neighbours' moves)
SI_STRETCH = 1.5       # no edge of the sacrum stretched or shrunk past this many times its length


class Inside:
    """A closed mesh's inside, exactly: its winding number (tools/anatomy_gaps.py winding_number) over a half,
    counted for the points in its box. A grid's voxels stand a voxel proud of a thin bone's faces and doubled the
    man's iliac plates."""
    def __init__(self, v, f):
        self.v, self.f = np.asarray(v, np.float64), np.asarray(f, np.int64)
        self.lo, self.hi = self.v.min(0), self.v.max(0)

    def inside(self, q):
        from anatomy_gaps import winding_number
        out = np.zeros(len(q), bool)
        box = ((q >= self.lo) & (q <= self.hi)).all(1)
        if box.any():
            out[box] = np.abs(winding_number(q[box], self.v, self.f)) > 0.5
        return out


def drawn_in(v, f, solids, margin=SI_GAP, sigma=SI_SIGMA, rounds=10, reach=SI_REACH, most=SI_STRETCH):
    """A bone's points (v, its triangles f wound to face out) that lie inside any of the solids, drawn back into
    it along its inward normals as described above, round after round while each round leaves fewer inside and
    no edge stretched or shrunk past `most` times its length (the round before is kept). Returns the new
    points, how many lay inside before and after, and the largest move."""
    from anatomy_gaps import spread_moves, vertex_area
    from anatomy_bones import vertex_normals

    def inside(q):
        return np.logical_or.reduce([S.inside(q) for S in solids])
    p = np.asarray(v, np.float64)
    p0, before = p.copy(), int(inside(p).sum())
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    length = np.linalg.norm(p0[e[:, 0]] - p0[e[:, 1]], axis=1)
    left = before
    for _ in range(rounds):
        ins = inside(p)
        if not ins.any():
            break
        q, n = p[ins], vertex_normals(p, f)[ins]
        depth = np.full(len(q), np.nan)
        for t in np.arange(1, int(round(reach / 0.00025)) + 1) * 0.00025:
            out = np.isnan(depth) & ~inside(q - n * t)
            depth[out] = t
            if not np.isnan(depth).any():
                break
        found = ~np.isnan(depth)
        if not found.any():
            break
        q = spread_moves(p, q[found], -n[found] * (depth[found] + margin)[:, None], vertex_area(p, f)[ins][found],
                         sigma, reach, True)
        ratio = np.linalg.norm(q[e[:, 0]] - q[e[:, 1]], axis=1) / np.maximum(length, 1e-9)
        now = int(inside(q).sum())
        if now >= left or ratio.max() > most or ratio.min() < 1 / most:
            break
        p, left = q, now
    return p, before, left, float(np.linalg.norm(p - p0, axis=1).max())


def ease_sacrum(folder, body):
    """The sacrum drawn out of the hip bones (see above), the pelvis's part rewritten. Returns an account."""
    from anatomy_gaps import wound_out
    pre = "VH_M_" if body["id"] == "male" else "VH_F_"
    part = next((p for p in body["parts"] if p["id"] == "pelvis"), None)
    nodes = [s["node"] for s in part["structures"]] if part else []
    if pre + "sacrum" not in nodes:
        return "no sacrum"
    meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
              for v, f in read_part(os.path.join(folder, part["file"]))]
    i = nodes.index(pre + "sacrum")
    hips = [meshes[k] for k, n in enumerate(nodes) if "_ilium_" in n or "_hip_" in n]
    v, f = meshes[i]
    p, before, after, most = drawn_in(v, f if wound_out(v, f) else f[:, ::-1], [Inside(*h) for h in hips])
    if not before:
        return "the sacrum clear of the hip bones"
    if not most:
        return (f"the sacrum left as it was, {before} of its points in the hip bones: drawn out, it would bend "
                f"past {SI_STRETCH} times an edge's length")
    meshes[i] = (p, f)
    rewrite(folder, part, meshes)
    return (f"the sacrum drawn out of the hip bones: {before} of its points in them, {after} left, moved up to "
            f"{most * 1000:.1f} mm")


# MARK: apart

# In the pelvis, nothing passes into anything else. The organs, the gut and the vessels come from each body's
# own scan (the organ sets are the Visible Human man's and woman's), the hip muscles (bar the gluteus maximus,
# made from its attachments by tools/anatomy_gluteus.py) from other people's CT scans fitted to the body: so
# where a muscle and an organ, a vessel or a duct run into each other, the muscle gives way, a groove in it
# where the other lies (as the psoas carries the iliac vessels on it). The soft structures are pushed out of
# what they run into a rank at a time, each rank's structures as one mesh (as tools/anatomy_bones.py
# together() moves the seat's), so where two of them join (a vein and the one it drains into) both move
# alike and stay joined: the organs and the gut out of the bones and the discs; then the vessels out of
# those and the organs; then the ducts out of all of these; last the muscles out of the organs, the vessels
# and the ducts. A vessel stays in an organ only at its ends, and only if it is that organ's own (named for
# it: the superior rectal vein's branches in the rectum, a uterine artery's in the uterus); a duct stays in
# the organ it drains into at its ends (a ureter in the bladder's wall); a duct, or a vessel in its own organ,
# a quarter or more of which lies in it (the prostatic urethra and the ejaculatory ducts in the prostate, a
# rectal vein's branches in the rectum) runs through it, as in the body, and stays, but a vessel in an organ
# not its own is pushed out however much of it lies there (the woman's median sacral vein, a quarter of it in
# the back of her rectum, lies behind it, on the sacrum). A sheet that wraps what it holds (fat, a ligament) and an inner structure (one shown only when
# its organ is opened) are neither moved nor in the way. No push moves a point further than its rank's
# most, and a structure a push would stretch (an edge to over twice its length, and 2 mm longer) is left as
# it was: a thin vein deep in a gut (the superior mesenteric vein's branches among the ileum's loops) is not
# dragged out of it into a sail.
RANKS = (("organs", {"organ", "gut", "gland", "lymph"}, 0.010, 0.010),
         ("vessels", {"vein", "artery"}, 0.005, 0.005),
         ("ducts", {"duct", "nerve"}, 0.004, 0.005))   # each rank's tissues, how far a push spreads, its most
SOFT = ("vessels", "colon", "small-intestine", "bladder", "kidneys", "urethra", "prostate", "genital-ducts",
        "uterus", "vagina", "ovaries", "uterine-tubes")
HARD = ("vertebral-column", "pelvis", "legs")
HARD_TISSUES = ("bone", "cartilage")
GIVE = ("hip-muscles",)            # the muscles that give way
GIVE_SIGMA, GIVE_MOST = 0.008, 0.015
GIVE_STRETCH, GIVE_STRETCH_MM = 3.0, 0.004   # a groove stretches a muscle more than a push may a vessel
LOOSE = ("fat", "ligament")
OWN = {"rect": "rect", "uter": "uter", "vesic": "bladder", "sigmoid": "sigmoid", "ovari": "ovar",
       "prostat": "prostat", "ileocolic": "ile", "colic": "colon", "caec": "caec", "append": "append"}
THROUGH = 0.25        # a duct or an own vessel a quarter or more of whose points lie in an organ runs through it
MARGIN = 0.001        # pushed this far clear of what it ran into
HOLD = 1.5            # an end held within 1.5 of its radii (and 2 mm)
STRETCH, STRETCH_MM = 2.0, 0.002


def region(body):
    """The pelvis: its part's bounds, 2 cm wider, and 1 cm above the iliac crests (the great vessels' forks)."""
    b = next(p["bounds"] for p in body["parts"] if p["id"] == "pelvis")
    lo, hi = np.array(b[:3]) - 0.02, np.array(b[3:]) + 0.02
    hi[1] -= 0.01
    return lo, hi


def owns(vessel, organ):
    """Whether a vessel is named for the organ (and so may end in it)."""
    v, o = vessel.lower(), organ.lower()
    return any(k in v and w in o for k, w in OWN.items())


def stretched(p0, p, f, times=STRETCH, mm=STRETCH_MM):
    """Whether moving a mesh's points from p0 to p stretches an edge past `times` its length, and `mm` longer."""
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    a = np.linalg.norm(p0[e[:, 0]] - p0[e[:, 1]], axis=1)
    b = np.linalg.norm(p[e[:, 0]] - p[e[:, 1]], axis=1)
    return bool(((b > times * a) & (b - a > mm)).any())


def push_clear(p, f, solids, skip, held, inbox, sigma, most, rounds=15, step=0.002):
    """The points p (a mesh with triangles f) moved out of the solids (tools/anatomy_gaps.py push_out, the
    pull spread over the mesh by area, each round's pulls scaled alike), none further than `most`: a solid's
    `skip` mask marks the points it does not count; the points held do not move, the move fading in from
    them over half of sigma; only the points in the box are pulled. Returns the round's points that leave
    the fewest inside, and how many."""
    from anatomy_gaps import spread_moves, vertex_area
    from scipy.spatial import cKDTree
    keep = np.ones(len(p))
    if held.any():
        keep = 1 - np.exp(-cKDTree(p[held]).query(p)[0] ** 2 / (2 * (sigma / 2) ** 2))
    p0, best = p, (np.inf, p)
    for done in range(rounds + 1):
        D = np.zeros_like(p)
        hit = np.zeros(len(p), bool)
        for S, sk in zip(solids, skip):
            m = S.inside(p) & inbox & ~held & ~sk
            if m.any():
                D[m] += S.way_out(p[m], MARGIN)
                hit |= m
        if hit.sum() < best[0]:
            best = (int(hit.sum()), p)
        if not hit.any() or done == rounds:
            break
        q = spread_moves(p, p[hit], D[hit], vertex_area(p, f)[hit], sigma, step, True, alike=True)
        p = p + (q - p) * keep[:, None]
        d = p - p0
        n = np.linalg.norm(d, axis=1, keepdims=True)
        p = p0 + d * np.minimum(1, most / np.maximum(n, 1e-12))
    return best[1], best[0]


def apart(folder, body, ends):
    """The pelvis's soft structures pushed out of what they run into, a rank at a time (see RANKS), then the
    muscles that give way out of them; each moved structure's part rewritten. `ends`: close()'s caps
    {node: [(centre, radius)]}. Returns an account."""
    from anatomy_gaps import Solid, wound_out
    from scipy.spatial import cKDTree
    lo, hi = region(body)
    parts = {p["id"]: p for p in body["parts"]}
    meshes, hard, soft, give = {}, [], [], []
    for pid in HARD + SOFT + GIVE:
        part = parts.get(pid)
        if part is None:
            continue
        meshes[pid] = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
                       for v, f in read_part(os.path.join(folder, part["file"]))]
        for i, st in enumerate(part["structures"]):
            v = meshes[pid][i][0]
            if not ((v >= lo) & (v <= hi)).all(1).any():
                continue
            t = st.get("tissue")
            if pid in HARD:
                if t in HARD_TISSUES:
                    hard.append((pid, i, st["node"], None))
            elif pid in GIVE:
                if t == "muscle":
                    give.append((pid, i, st["node"], None))
            elif t not in LOOSE and not st.get("inner"):
                rank = next((k for k, r in enumerate(RANKS) if t in r[1]), None)
                if rank is not None:
                    soft.append((pid, i, st["node"], rank))
    solid = {}
    def solid_of(item):
        if item[2] not in solid:
            solid[item[2]] = Solid([meshes[item[0]][item[1]]], h=0.001)
        return solid[item[2]]
    def bounds(item):
        v = meshes[item[0]][item[1]][0]
        return v.min(0), v.max(0)
    said, dirty = [], set()
    # the organs keep off the bones; the vessels and the ducts off the muscles too, by up to their most, the
    # muscles then giving way for the rest
    groups = [(name, [s for s in soft if s[3] == k], hard + (give if k else []) + [s for s in soft if s[3] < k],
               sigma, most) for k, (name, _, sigma, most) in enumerate(RANKS)]
    groups += [("muscles", [g], soft, GIVE_SIGMA, GIVE_MOST) for g in give]
    for name, members, above, sigma, most in groups:
        if not members:
            continue
        rank = members[0][3]
        P, F, cut = [], [], [0]
        for pid, i, node, _ in members:
            v, f = meshes[pid][i]
            P.append(v)
            F.append((f if wound_out(v, f) else f[:, ::-1]) + cut[-1])
            cut.append(cut[-1] + len(v))
        p0, f0 = np.concatenate(P), np.concatenate(F)
        inbox = ((p0 >= lo) & (p0 <= hi)).all(1)
        a0, a1 = p0[inbox].min(0) - 0.003, p0[inbox].max(0) + 0.003
        ways = [b for b in above if (bounds(b)[0] < a1).all() and (bounds(b)[1] > a0).all()]
        if not ways:
            continue
        solids = [solid_of(b) for b in ways]
        skip = [np.zeros(len(p0), bool) for _ in ways]
        held = np.zeros(len(p0), bool)
        for k, (pid, i, node, _) in enumerate(members):
            seg = slice(cut[k], cut[k + 1])
            v = p0[seg]
            for j, (b, S) in enumerate(zip(ways, solids)):
                if b[3] is None or rank is None:
                    continue              # nothing runs through a bone or a disc, or ends in one; a muscle gives way
                ins = S.inside(v)
                if not ins.any():
                    continue
                theirs = rank == 2 or owns(node, b[2])
                if theirs and ins.mean() >= THROUGH:
                    skip[j][seg] = True   # it runs through b, as in the body
                    continue
                if theirs:
                    bv = meshes[b[0]][b[1]][0]
                    for c, r in ends.get(node, ()):
                        if S.inside(c[None])[0] or cKDTree(bv).query(c)[0] < r:
                            held[seg] |= np.linalg.norm(v - c, axis=1) < HOLD * r + 0.002
        inside = np.zeros(len(p0), bool)
        for S, sk in zip(solids, skip):
            inside |= S.inside(p0) & ~sk
        inside &= inbox & ~held
        if not inside.any():
            continue
        q, left = push_clear(p0, f0, solids, skip, held, inbox, sigma, most)
        moved, kept = [], []
        for k, (pid, i, node, _) in enumerate(members):
            seg = slice(cut[k], cut[k + 1])
            d = np.linalg.norm(q[seg] - p0[seg], axis=1).max()
            if d <= 1e-5:
                continue
            if stretched(p0[seg], q[seg], meshes[pid][i][1], *((GIVE_STRETCH, GIVE_STRETCH_MM) if rank is None
                                                               else (STRETCH, STRETCH_MM))):
                kept.append(node)
                continue
            meshes[pid][i] = (q[seg], meshes[pid][i][1])
            solid.pop(node, None)
            dirty.add(pid)
            moved.append(f"{node} {int(inside[seg].sum())} in the way (moved up to {d * 1000:.1f} mm)")
        said.append(f"{name}: {int(inside.sum())}->{left} points in the way; " + ", ".join(moved)
                    + (f"; left as they were, a push would stretch them: {', '.join(kept)}" if kept else ""))
    for pid in sorted(dirty):
        rewrite(folder, parts[pid], meshes[pid])
    return "; ".join(said) or "nothing in the way"


def remake(folder, quiet=False):
    """Draws the sacrum out of the hip bones, parts the pelvis's structures and closes the tubes in `folder`'s
    atlas (anatomy.json and its part files); does nothing if done already. Returns what it did. The pelvis is
    parted against the tubes sheeted flat across every hole, and their ends made hollow after: parted against
    hollow ends, the vessels by a gut's cut end were pushed further than their edges bear and so left where they
    were, in its wall (the man's right external iliac vein in his sigmoid colon, the woman's median sacral vein in
    her rectum)."""
    import json
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if body.get("apart"):
            continue
        ends = {}
        if CLOSE_ENDS:
            sizes = cap(folder, body, ends)       # for the parting alone: see cap()
        said.append(f"{body['id']}: {ease_sacrum(folder, body)}")
        said.append(f"{body['id']}: apart {apart(folder, body, ends)}")
        if CLOSE_ENDS:
            uncap(folder, body, sizes)
            said.append(f"{body['id']}: closed {close(folder, body)}")
        body["apart"] = True
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            print("  " + line)
    return "; ".join(said) or "closed and apart already"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("anatomy_apart.py ATLAS_FOLDER")
    print(remake(sys.argv[1]))
