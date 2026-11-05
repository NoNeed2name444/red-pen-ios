"""Each tube in the atlas closed at its cut ends, and the pelvis's structures kept out of one another.

The organ sets (the HRA's 3D reference organs, CC BY 4.0) draw a vessel or a gut as a tube cut open where
it meets the next one: a vein where it drains into the next, the rectum where it meets the sigmoid colon, a
branch's mouth where it leaves its trunk. Seen alone, or with its neighbour hidden, such a tube shows its
hollow inside (the app draws a solid structure from both sides). So each hole in a tube is closed here by a
cap, as a whole structure is closed: where the hole is a cut across the tube (flat, the tube on one side of
it), a low dome rising a third of the hole's radius, so the tube ends rounded, as a vessel tied off or a gut
drawn on its own is drawn in an atlas; where it is not (a branch's mouth, cut out of a curved wall), a sheet
across it, smoothed with its rim held. Where two tubes join, each one's cap lies inside the other, out of
sight while both are shown. A small hole (under 4 mm across its radius) is closed by a fan from its rim to
the cap's top; a larger one has a ring of half as many points between, a large one (12 mm) two: the
caps cost little of the atlas's triangle budget.

Then, in the pelvis, nothing passes into anything else (the owner: "elements shouldn't phase through each
other. each should be compact"): first the sacrum, another man's scanned bone on this body's hip bones, drawn
out of them at its joints (see ease_sacrum()); then the soft structures out of the bones and one another (see
apart()).
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
DOME = 1 / 3          # a cut end's dome rises a third of its radius
FLAT = 0.15           # a cut end is flat: its rim within this share of its radius of a plane (root mean square)
ONE_SIDED = 0.9       # and nine in ten of the tube's points near it (within 2.5 radii) on one side of it
FAN, ONE_RING = 0.004, 0.012   # a hole's radius under which its cap is a fan; under which it has one ring


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


def cap(v, loop, start):
    """A cap over one hole: its new points (numbered from `start`) and its triangles over the mesh's point
    ids, and whether it is a dome (a cut end) or a sheet."""
    q = v[loop]
    m = len(loop)
    c = q.mean(0)
    _, _, vt = np.linalg.svd(q - c)
    n = vt[2]
    r = float(np.linalg.norm(q - c, axis=1).mean())
    flat = math.sqrt(float((((q - c) @ n) ** 2).mean())) / max(r, 1e-12)
    near = v[np.linalg.norm(v - c, axis=1) < 2.5 * r]
    side = (near - c) @ n
    if side.mean() > 0:
        n, side = -n, -side                 # the tube on the cap's inner side
    sure = np.abs(side) > 0.15 * r
    one = float((side[sure] < 0).mean()) if sure.any() else 0.0
    dome = flat < FLAT and one >= ONE_SIDED
    H = DOME * r if dome else 0.0
    levels = 0 if r < FAN else (1 if r < ONE_RING else 2)
    pts, tris = [], []
    _, t = around(q, np.zeros(1))
    outer, t_outer = list(loop), t
    nxt = start
    for lev in range(1, levels + 1):
        k = max(3, int(math.ceil(m / 2 ** lev)))
        s = np.arange(k + 1) / k
        P, _ = around(q, s[:k])
        th = lev / (levels + 1) * math.pi / 2
        ring = c + (P - c) * (math.cos(th) if dome else 1 - lev / (levels + 1)) + n * H * math.sin(th)
        ids = list(range(nxt, nxt + k))
        nxt += k
        pts.append(ring)
        tris += zip_rings(outer, t_outer, ids, s)
        outer, t_outer = ids, s
    top = nxt
    pts.append((c + n * H)[None])
    kk = len(outer)
    tris += [(outer[(j + 1) % kk], outer[j], top) for j in range(kk)]
    P = np.concatenate(pts)
    T = np.array(tris, np.int64)
    if not dome and levels:
        # a sheet: its inner points each moved to its neighbours' mean, the rim held
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
            X[free] = np.array([X[l].mean(0) for l in lists])
        P = X[free]
    return P, T, dome, r


def close_tubes(v, f):
    """The mesh with each of its holes capped; the new points after the old, the new triangles after the old.
    Returns (v, f, how many domes, how many sheets)."""
    v = np.asarray(v, np.float64)
    f = np.asarray(f, np.int64)
    # holes are found on the mesh with points at one place made one; the caps meet the mesh at its own points
    key = np.round(v * 1e6).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    wf = inverse[f]
    wf = wf[(wf[:, 0] != wf[:, 1]) & (wf[:, 1] != wf[:, 2]) & (wf[:, 2] != wf[:, 0])]
    wv = v[first]
    loops = cycles(wf)
    if not loops:
        return v, f, 0, 0, []
    newp, newf, domes, sheets, where = [], [], 0, 0, []
    start = len(v)
    for loop in loops:
        P, T, dome, r = cap(wv, loop, start)
        T = np.where(T < len(wv), first[np.minimum(T, len(wv) - 1)], T)   # the rim's points: the mesh's own
        newp.append(P)
        newf.append(T)
        where.append((wv[loop].mean(0), r))
        start += len(P)
        domes += dome
        sheets += not dome
    return np.concatenate([v] + newp), np.concatenate([f] + newf), domes, sheets, where


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
    """Each tube of the body's TUBES parts (and TUBE_NODES' structures) closed at its holes, its part
    rewritten. `ends`, a dict, gets each closed structure's caps, {node: [(centre, radius), ...]}. Returns an
    account."""
    said = []
    for part in body["parts"]:
        pid = part["id"]
        if pid not in TUBES and pid not in TUBE_NODES:
            continue
        meshes = read_part(os.path.join(folder, part["file"]))
        added, domes, sheets = 0, 0, 0
        for i, (st, (v, f)) in enumerate(zip(part["structures"], meshes)):
            if pid in TUBE_NODES and TUBE_NODES[pid] not in st["node"]:
                continue
            nv, nf, d, s, where = close_tubes(v, f)
            if d + s:
                added += len(nf) - len(f)
                domes += d
                sheets += s
                meshes[i] = (nv, nf)
                if ends is not None:
                    ends[st["node"]] = where
        if domes + sheets:
            rewrite(folder, part, meshes)
            said.append(f"{pid} {domes} ends domed, {sheets} mouths sheeted (+{added} triangles)")
    return "; ".join(said) or "no tube open"


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
    """Closes the tubes, draws the sacrum out of the hip bones and parts the pelvis's structures in `folder`'s
    atlas (anatomy.json and its part files); does nothing if done already. Returns what it did."""
    import json
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if body.get("apart"):
            continue
        ends = {}
        said.append(f"{body['id']}: closed {close(folder, body, ends)}")
        said.append(f"{body['id']}: {ease_sacrum(folder, body)}")
        said.append(f"{body['id']}: apart {apart(folder, body, ends)}")
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
