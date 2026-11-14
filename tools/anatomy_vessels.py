"""Each vessel one clean tube.

The organ sets' vessels (the HRA's 3D reference organs, CC BY 4.0, segmented from the Visible Human) come to
the atlas cut down to a few hundred triangles each, and many read as anything but a vessel (the owner, 6 Nov:
"it's impossible for a student to identify any vessel anywhere in the models"): the man's internal iliac
veins knobbed with the stumps of tributaries the segmentation cut off, his sigmoid vein's branches webbed
together, the woman's left common iliac vein flared into a sheet where it meets the vena cava, her aortic arch
crumpled, and a dozen of her great vessels drawn twice, an inner wall (the lumen) inside the outer one.

So each vessel is drawn anew from its own centre line: the structure is filled (its holes capped for the
while), the fill thinned to a skeleton (Lee, Kashyap and Chu 1994, as scikit-image does it), each point of
the skeleton keeping how far it lies from the vessel's wall (its radius). The skeleton is then cleaned as an
anatomist would trace the vessel: a spur no longer than the trunk it leaves is wide (a knob, a fin, the stump
of a cut tributary that has no cut end of its own) is pruned, a thin spur whose wall lies far wider than it
is thick (a sheet) too, unless it runs on for over ten times that width (a thin branch, whose thickness the
fill cannot measure), and of any ring in it the thinnest link is cut (a web between two branches closes a
ring), so that what is left is a tree; a part of it the fill broke off (a neck thinner than the fill's
voxels) is joined on again, a crumb under 3 mm dropped. Along each branch the line is smoothed and the radius
taken as its running median, no wider where the branch meets the others than along it (a fork no blob). The
vessel is then the surface round the balls along that tree (marching cubes, Lorensen and Cline 1987), its
creases at the forks eased, brought down to no more triangles than it had (fast quadric simplification).
Where so few triangles cannot hold a thin branch (bringing the surface down pinches it off), the thin are
drawn wider, a share of a triangle's edge at least, and what is still pinched off is left out: each vessel
comes out as many pieces as it was drawn, as a rule one. The wall is one wall: an inner wall drawn as a piece
of its own inside the outer one goes, and a hole in the side of the vessel (the mouth of a branch that is
drawn as its own structure, a tear) is closed by the wall running on.

A cut end stays open where it was: where a branch of the skeleton runs out at one of the structure's holes,
about as wide as the hole (a thin spur by a wide hole is no end), the tube is drawn on past the hole and cut
off flat there, in the hole's own plane if its rim is flat and lies across the branch, else straight across
the branch. The triangles across the plane are cut along it and the cap beyond taken off, so the end is one
flat loop, which tools/anatomy_apart.py takes for a cut and makes hollow.

A stretch that came flattened (a vein pressed against a bone) is drawn round, as wide as its wall lies from
its centre line as a rule and no wider than OVAL times its least half-width; the tube's points are then
drawn back to within SWELL of a radius of the vessel as it came, so it does not swell into its neighbours.

Most vessels keep their own surface. First the sound ones: a vessel that came in one piece and whose
skeleton has nothing to prune (no knob, stump, web or ring) is a clean tube already; only what needs mending
is drawn anew. Then one too fine for the fill to hold (the eye's, the heart's
smallest, under FINE), its inner wall left out. And one drawn with its lumen, the inner wall joined to the
outer at its ends (the man's pulmonary vessels, venae cavae and brachiocephalic veins): it reads as a hollow
tube as it is, and a fill of it holds its wall alone, not its lumen. A third is kept whole: a great vessel
(4 mm wide or more) part of whose wall is drawn as a flap, a branch of its skeleton under a third as wide as
the cut end it runs out at (the man's aortic arch), which a tube round its centre line would make a thread.
And a fourth: a vessel in one piece a third of whose surface (AWAY; nearly half, if a web was pruned from
it) lies further than a third of its radius from the tube drawn anew. It is no plain tube (a short wide trunk, a bent arch, a vein
pressed flat), the tube would not be the vessel, and nothing was wrong with it that a tube mends.

Names: the female inferior mesenteric vein, which read "superior mesenteric artery", is set right (Gray's
Anatomy, 1918, §6d: "The Inferior Mesenteric Vein"); the portal vein is named as a student looks for it
("The Portal Vein (vena portæ)", ibid.), and the man's, which came as two meshes overlapping over a third of
their length, is one structure, one tube from both.
"""
import math
import os
import sys
from collections import defaultdict

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anatomy_fibres import read_part, sha256, write_part  # noqa: E402

PART = "vessels"
TISSUES = ("artery", "vein")
FINE = 0.0006         # a vessel narrower than this (its typical radius, metres) keeps its own surface
CELL = 4.0            # voxels across a vessel's typical radius
CELL_MIN = 0.00012    # never finer than this (metres)
VOXELS = 24e6         # nor more voxels than this for one vessel
SPUR = 1.3            # a spur no longer than this many times the radius where it leaves is a knob
STUB = 1.0            # and one standing out of its trunk's wall less than this many of its own radii a stump
WEB = 2.0             # and a thin one whose wall lies, as a rule, this many times further than its nearest a sheet,
WEB_LONG = 10.0       # if no more than this many times as long as that (longer: a thin branch, kept)
SPAN = 2.0            # each branch's radius the running median over this many of its radii (along it)
FORK = 1.08           # no wider where it meets the others than this many times its own
EASE = 0.8            # the field eased over this many voxels (the forks' creases)
PAST = 1.5            # a cut end drawn on this many radii past its plane before it is cut there
NEAR = 1.6            # a hole is a branch's end if the branch runs out within this many of its radii
FLATTENED = 0.3       # a branch under this share of the width of the cut end it runs out at, in a vessel
GREAT = 0.004         # this wide (metres, its widest branch): the vessel keeps its own surface
OVAL = 1.6            # a flattened stretch is drawn round, as wide as its wall lies from its centre line as a
                      # rule, and no wider than this many times its least half-width
SWELL = 0.1           # the tube no further outside the vessel as it came than this share of its radius
AWAY = (0.35, 0.33, 0.45)  # a vessel this share of its radius from the tube drawn anew over this share of
                      # its surface (the last if a web was taken off it): no plain tube, it keeps its own
ENDS = (0.15, 3.0)    # and is between these many times as wide as the hole there
CRUMB = 0.02          # a piece of the drawn surface with less than this share of its triangles is dropped
THIN = 1.5            # no ball narrower than this many voxels of the field (the eased surface would break)
WIDER = (0.3, 0.45, 0.6)   # a branch too thin for its triangles drawn this share of their edge wide, at least
SMALL = 0.003         # and one under this across (metres), bar the largest, when all is done
JOIN = 2.0            # parts of the tree the fill broke apart joined if no further apart than this many radii
SEEN = 0.05           # a triangle seen from fewer than this share of the directions about its normal is hidden
HALF = 0.5            # and one seen from fewer than this, joined to hidden ones, too (an inner wall's ends)
WALLED = 0.1          # an inner wall when at least this share of the triangles are hidden
# Labels set right: the female inferior mesenteric vein was labelled the superior mesenteric artery (Gray's
# Anatomy, 1918, §6d: "The Inferior Mesenteric Vein"), the male superior mesenteric vein had no UBERON term,
# and the portal vein is named as a student looks for it ("The Portal Vein (vena portæ)", ibid.).
LABELS = {"VH_F_inferior_mesenteric_vein": ("inferior mesenteric vein", "UBERON:0001215"),
          "VH_M_superior_mesenteric_vein": ("superior mesenteric vein", "UBERON:0001138"),
          "VH_M_hepatic_portal_vein": ("portal vein", "UBERON:0001639"),
          "VH_F_hepatic_portal_vein": ("portal vein", "UBERON:0001639")}
# One vessel drawn twice: the man's portal vein comes as two meshes that overlap over a third of their
# length (the organ sets' "portal vein" and "hepatic portal vein"); the first is drawn into the second, one
# tube from both, and its own entry goes.
SAME = {"VH_M_portal_vein": "VH_M_hepatic_portal_vein"}


# MARK: the mesh as it comes

def weld(v, f):
    """The mesh with points at one place made one (to a micrometre), triangles with no area and points no
    triangle uses left out."""
    v = np.asarray(v, np.float64)
    f = np.asarray(f, np.int64)
    key = np.round(v * 1e6).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    v, f = v[first], inv.reshape(-1)[f]
    f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
    f = f[area(v, f) > 1e-13]
    used = np.unique(f)
    at = np.full(len(v), -1, np.int64)
    at[used] = np.arange(len(used))
    return v[used], at[f]


def area(v, f):
    return 0.5 * np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1)


def pieces(n, f):
    """Each triangle's piece (triangles joined through shared points)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]]])
    _, lab = connected_components(coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n)), directed=False)
    return lab[f[:, 0]]


def loops(f):
    """The mesh's holes, each a cycle of its points in the order the triangles run along the rim (as
    tools/anatomy_apart.py finds them); a rim that touches itself is split into simple cycles."""
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    _, inv, cnt = np.unique(np.sort(E, 1), axis=0, return_inverse=True, return_counts=True)
    out = defaultdict(list)
    for a, b in E[cnt[inv.reshape(-1)] == 1]:
        out[int(a)].append(int(b))
    found = []
    while out:
        path = [next(iter(out))]
        where = {path[0]: 0}
        while path:
            x = path[-1]
            if x not in out:
                break
            b = out[x].pop()
            if not out[x]:
                del out[x]
            if b in where:
                k = where[b]
                if len(path) - k >= 3:
                    found.append(np.array(path[k:], np.int64))
                for y in path[k + 1:]:
                    where.pop(y, None)
                path = path[:k + 1]
                if b not in out:
                    break
            else:
                where[b] = len(path)
                path.append(b)
    return found


def hole(v, loop):
    """A hole's middle, the normal of its plane turned away from the vessel, its mean radius, and whether it is
    a cut across the tube as tools/anatomy_apart.py tells one (its rim within 0.15 of its radius of a plane,
    nine in ten of the tube's points near it on one side)."""
    q = v[loop]
    c = q.mean(0)
    n = np.linalg.svd(q - c)[2][2]
    r = float(np.linalg.norm(q - c, axis=1).mean())
    flat = math.sqrt(float((((q - c) @ n) ** 2).mean())) / max(r, 1e-12)
    side = (v[np.linalg.norm(v - c, axis=1) < 2.5 * r] - c) @ n
    if side.mean() > 0:
        n, side = -n, -side
    sure = np.abs(side) > 0.15 * r
    one = float((side[sure] < 0).mean()) if sure.any() else 0.0
    return {"loop": loop, "c": c, "n": n, "r": r, "flat": flat < 0.15, "cut": flat < 0.15 and one >= 0.9}


def capped(v, f, holes):
    """The mesh with each hole closed by a fan to its middle (only to fill it)."""
    P, F = [v], [f]
    k = len(v)
    for h in holes:
        L = h["loop"]
        F.append(np.stack([np.roll(L, -1), L, np.full(len(L), k)], 1))
        P.append(h["c"][None])
        k += 1
    return np.concatenate(P), np.concatenate(F)


def inner_walls(v, f):
    """The triangles of the pieces that lie inside another piece of the same structure (a lumen drawn as an
    inner wall): over half of their points inside it, counted with its holes capped."""
    from anatomy_gaps import winding_number
    lab = pieces(len(v), f)
    ids = np.unique(lab)
    if len(ids) < 2:
        return np.zeros(len(f), bool)
    size = {i: area(v, f[lab == i]).sum() for i in ids}
    drop = np.zeros(len(f), bool)
    for i in ids:
        pts = np.unique(f[lab == i])
        for j in ids:
            if j == i or size[j] <= size[i]:
                continue
            fj = f[lab == j]
            cv, cf = capped(v, fj, [hole(v, L) for L in loops(fj)])
            if (np.abs(winding_number(v[pts], cv, cf)) > 0.5).mean() > 0.5:
                drop |= lab == i
                break
    return drop


def faces_out(v, f):
    """The triangles each piece of them wound to face out (its winding number just behind them near 1)."""
    from anatomy_gaps import wound_out
    lab = pieces(len(v), f)
    f = f.copy()
    for i in np.unique(lab):
        m = lab == i
        if not wound_out(v, f[m]):
            f[m] = f[m][:, ::-1]
    return f


def sight(v, f, h, cone=0.9, rays=400):
    """Each triangle's share of the directions within its cone (cos > `cone` to its outward normal) along
    which it can be seen from outside: a ray from it, marched every half voxel over its surface's voxels
    (side h), that leaves them all behind. An inner wall's triangles face the lumen and see only the wall
    across it."""
    P = samples(v, f, 0.5 * h)
    lo = P.min(0) - 2 * h
    occ = np.zeros(np.floor((P.max(0) - lo) / h).astype(int) + 3, bool)
    occ[tuple(np.floor((P - lo) / h).astype(int).T)] = True
    N = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-18)
    c = v[f].mean(1)
    k = np.arange(rays) + 0.5
    z = 1 - 2 * k / rays
    t = np.pi * (1 + 5 ** 0.5) * k
    D = np.stack([np.sqrt(1 - z * z) * np.cos(t), np.sqrt(1 - z * z) * np.sin(t), z], 1)
    seen = np.zeros(len(f))
    tried = np.zeros(len(f))
    steps = np.arange(0, np.linalg.norm(occ.shape) * h, 0.5 * h)
    for d in D:
        cos = N @ d
        use = np.where(cos > cone)[0]
        if not len(use):
            continue
        start = c[use] + np.outer(1.5 * h / cos[use], d)
        free = np.ones(len(use), bool)
        for s in range(0, len(steps), 64):
            q = start[:, None, :] + steps[None, s:s + 64, None] * d
            idx = np.floor((q - lo) / h).astype(int)
            inside = ((idx >= 0) & (idx < occ.shape)).all(2)
            hit = np.zeros(inside.shape, bool)
            hit[inside] = occ[tuple(idx[inside].T)]
            free &= ~hit.any(1)
            if not inside.any():
                break
        seen[use] += free
        tried[use] += 1
    return np.where(tried > 0, seen / np.maximum(tried, 1), 1.0)


def hidden_walls(v, f, h):
    """The triangles of an inner wall joined to the outer one (a lumen drawn inside the vessel, the two
    walls meeting at its ends): those seen from almost no direction (SEEN), and those seen from few (HALF)
    that join them."""
    f = faces_out(v, f)
    vis = sight(v, f, h)
    out = vis < SEEN
    if not out.any():
        return out, f
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    tri = np.tile(np.arange(len(f)), 3)
    key = np.sort(E, 1)
    o = np.lexsort(key.T[::-1])
    same = (key[o][1:] == key[o][:-1]).all(1)
    a, b = tri[o][:-1][same], tri[o][1:][same]
    weak = vis < HALF
    while True:
        grow = np.zeros(len(f), bool)
        grow[b[out[a] & weak[b]]] = True
        grow[a[out[b] & weak[a]]] = True
        grow &= ~out
        if not grow.any():
            return out, f
        out |= grow


# MARK: the fill and its skeleton

def samples(v, f, h):
    """Points over the triangles, no further apart than h."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    L = np.maximum.reduce([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - a, axis=1),
                           np.linalg.norm(c - b, axis=1)])
    n = np.clip(np.ceil(L / h).astype(int), 1, 2000)
    out = [a, b, c]
    for k in np.unique(n):
        if k == 1:
            continue
        sel = n == k
        i, j = np.meshgrid(np.arange(k + 1), np.arange(k + 1))
        m = i + j <= k
        s, t = i[m] / k, j[m] / k
        out.append((a[sel, None] * (1 - s - t)[None, :, None] + b[sel, None] * s[None, :, None]
                    + c[sel, None] * t[None, :, None]).reshape(-1, 3))
    return np.concatenate(out)


def fill(v, f, h, pad):
    """What the closed mesh holds, as voxels of side h: its surface's voxels, thickened by one, filled,
    and thinned by one again. Returns the grid and the corner of its first voxel."""
    P = samples(v, f, 0.5 * h)
    lo = P.min(0) - pad * h
    idx = np.floor((P - lo) / h).astype(np.int64)
    g = np.zeros(idx.max(0) + pad + 1, bool)
    g[tuple(idx.T)] = True
    cube = np.ones((3, 3, 3), bool)
    g = ndimage.binary_dilation(g, cube)
    g = ndimage.binary_fill_holes(g)
    return ndimage.binary_erosion(g, cube), lo


OFFS = np.array([(i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1) if (i, j, k) != (0, 0, 0)])


class Skeleton:
    """A skeleton's voxels as a graph: nodes (its ends, and its forks, each fork's touching voxels one
    node) and the branches between them (the voxels in order, the nodes' own at either end)."""

    def __init__(self, sk):
        self.pts = np.argwhere(sk)
        n = len(self.pts)
        keys = np.ravel_multi_index(self.pts.T, sk.shape)
        stride = np.array([sk.shape[1] * sk.shape[2], sk.shape[2], 1])
        nb = np.full((n, 26), -1, np.int64)
        for k, o in enumerate(OFFS):
            q = keys + int(o @ stride)
            j = np.minimum(np.searchsorted(keys, q), n - 1)
            nb[:, k] = np.where(keys[j] == q, j, -1)
        self.nb = [row[row >= 0] for row in nb]
        deg = (nb >= 0).sum(1)
        node = np.full(n, -1, np.int64)
        J = np.where(deg >= 3)[0]
        if len(J):
            from scipy.sparse import coo_matrix
            from scipy.sparse.csgraph import connected_components
            inJ = np.zeros(n, bool)
            inJ[J] = True
            a = np.repeat(np.arange(n), 26)[(nb >= 0).ravel()]
            b = nb[nb >= 0]
            keep = inJ[a] & inJ[b]
            _, lab = connected_components(coo_matrix((np.ones(keep.sum()), (a[keep], b[keep])), shape=(n, n)),
                                          directed=False)
            _, node[J] = np.unique(lab[J], return_inverse=True)
        k = node.max() + 1
        for e in np.where(deg <= 1)[0]:
            node[e] = k
            k += 1
        seen = np.zeros(n, bool)
        self.branches = []
        for a in np.where(node >= 0)[0]:
            for b in self.nb[a]:
                if node[b] >= 0:
                    if node[b] != node[a] and a < b:
                        self.branches.append([a, b])
                    continue
                if seen[b]:
                    continue
                self.branches.append(self.trace(a, b, node, seen))
        for s in np.where((node < 0) & ~seen)[0]:      # a ring with no fork: one of its voxels a node
            if seen[s]:
                continue
            node[s] = k
            k += 1
            nxt = [x for x in self.nb[s] if node[x] < 0 and not seen[x]]
            if nxt:
                self.branches.append(self.trace(s, nxt[0], node, seen))
        self.node = node
        self.branches = [p for p in self.branches if not (node[p[0]] == node[p[-1]] and len(p) <= 3)]

    def trace(self, a, b, node, seen):
        path, prev, cur = [a, b], a, b
        seen[b] = True
        while True:
            nxt = [x for x in self.nb[cur] if x != prev and x != path[-2]]
            if not nxt:
                return path
            x = next((y for y in nxt if node[y] >= 0), nxt[0])
            path.append(x)
            if node[x] >= 0 or seen[x]:
                return path
            seen[x] = True
            prev, cur = cur, x


# MARK: the skeleton cleaned to a tree

def tree(sk, rad, wide, holes, h):
    """The skeleton's branches as a tree: the spurs pruned (see SPUR, STUB and WEB), each ring's thinnest
    link cut, a node met by two branches only made one branch. rad: each skeleton voxel's radius, how far
    it lies from the wall (voxels); wide: how far the wall it is nearest lies from it, as a rule (voxels),
    much more than rad in a sheet. Returns the branches (lists of voxel ids, end to end), each node's id
    per voxel, and how many of each kind it pruned."""
    node = sk.node
    br = [list(p) for p in sk.branches]
    X = sk.pts.astype(np.float64)
    near_hole = np.zeros(len(X), bool)
    for hl in holes:
        c = hl["cv"]
        near_hole |= np.linalg.norm(X - c, axis=1) < NEAR * hl["r"] / h + 2

    def length(p):
        return float(np.linalg.norm(np.diff(X[p], axis=0), axis=1).sum())

    def body(p):
        return float(np.median(rad[p]))

    def node_r(k, at):
        return max(rad[x] for x in at[k])

    pruned = dict(knobs=0, stumps=0, sheets=0, rings=0)
    while True:
        at = defaultdict(set)
        for p in br:
            at[node[p[0]]].add(p[0])
            at[node[p[-1]]].add(p[-1])
        deg = defaultdict(int)
        for p in br:
            deg[node[p[0]]] += 1
            deg[node[p[-1]]] += 1
        # the spurs: a branch with a free end no further from the fork it leaves than SPUR of the fork's
        # radius, its end at no hole (the shortest first, one at each fork a round)
        spurs = []
        for i, p in enumerate(br):
            for e, o in ((p[0], p[-1]), (p[-1], p[0])):
                if deg[node[e]] == 1 and deg[node[o]] >= 3:
                    L, trunk = length(p), node_r(node[o], at)
                    sheet = WEB * max(body(p), 0.5) < np.median(wide[p]) >= L / WEB_LONG and body(p) < 0.5 * trunk
                    why = ("stumps" if near_hole[e] else "knobs") if L - trunk <= STUB * body(p) else \
                        None if near_hole[e] else "knobs" if L <= SPUR * trunk else "sheets" if sheet else None
                    if why:
                        spurs.append((L, i, node[o], why))
                    break
        # a piece of a lone branch shorter than it is wide, its ends at no hole: debris
        for i, p in enumerate(br):
            if deg[node[p[0]]] == 1 and deg[node[p[-1]]] == 1 and not near_hole[[p[0], p[-1]]].any() \
                    and length(p) <= 2 * body(p):
                spurs.append((length(p), i, -1, "knobs"))
        gone, forks = set(), set()
        for _, i, o, why in sorted(spurs):
            if o in forks:
                continue
            gone.add(i)
            pruned[why] += 1
            if o >= 0:
                forks.add(o)
        # the rings: a maximum spanning forest by each branch's radius, the rest cut
        parent = {}

        def find(x):
            while parent.setdefault(x, x) != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        for i in sorted(range(len(br)), key=lambda i: -body(br[i])):
            if i in gone:
                continue
            a, b = find(node[br[i][0]]), find(node[br[i][-1]])
            if a == b:
                gone.add(i)
                pruned["rings"] += 1
            else:
                parent[a] = b
        if not gone:
            break
        br = [p for i, p in enumerate(br) if i not in gone]
        br = joined(br, node)
    return joined(br, node), node, pruned


def joined(br, node):
    """Branches through a node that only two meet made one."""
    while True:
        ends = defaultdict(list)
        for i, p in enumerate(br):
            ends[node[p[0]]].append(i)
            ends[node[p[-1]]].append(i)
        k = next((k for k, v in ends.items() if len(v) == 2 and v[0] != v[1]), None)
        if k is None:
            return br
        i, j = ends[k]
        a, b = br[i], br[j]
        if node[a[0]] == k:
            a = a[::-1]
        if node[b[-1]] == k:
            b = b[::-1]
        br = [p for m, p in enumerate(br) if m not in (i, j)] + [a + b[1:] if a[-1] == b[0] else a + b]


# MARK: the tube drawn anew

def smooth_line(X, sigma):
    """A polyline smoothed (Gaussian, sigma in samples), its ends held."""
    if len(X) < 3 or sigma <= 0:
        return X
    t = np.linspace(0, 1, len(X))[:, None]
    line = X[0] * (1 - t) + X[-1] * t
    return line + ndimage.gaussian_filter1d(X - line, sigma, axis=0, mode="constant")


def resample(X, R, ds):
    """Points every ds along a polyline, with its radii between."""
    s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(X, axis=0), axis=1))]
    if s[-1] <= 0:
        return X[:1], R[:1]
    t = np.linspace(0, s[-1], max(2, int(math.ceil(s[-1] / ds)) + 1))
    return np.stack([np.interp(t, s, X[:, k]) for k in range(3)], 1), np.interp(t, s, R)


def balls(sk, br, node, rad, h, lo, holes):
    """The balls the tube is drawn round: along each branch every half voxel, the line smoothed, the radius
    its running median and no wider where it meets the others than FORK of its own; past a cut end drawn on
    PAST of its radius. A hole is a cut end of the tube if a branch runs out at it (within NEAR of the hole's
    radius) about as wide as it is (ENDS: no spur by a wide hole); each such hole is paired with the nearest
    such branch end, and cut in the hole's own plane if its rim is flat and lies across the branch, else
    straight across the branch. Returns the balls' middles and radii (metres), each one's branch, and the cut
    ends drawn (each hole with the normal it is cut across, turned away from its branch, the tube's radius
    there and its branch)."""
    X = lo + (sk.pts + 0.5) * h
    deg = defaultdict(int)
    for p in br:
        deg[node[p[0]]] += 1
        deg[node[p[-1]]] += 1
    where = {}
    for p in br:
        for e in (p[0], p[-1]):
            where.setdefault(node[e], []).append(X[e])
    centre = {k: np.mean(v, 0) for k, v in where.items()}
    lines = []
    for i, p in enumerate(br):
        P = X[p].copy()
        R = rad[p].astype(np.float64) * h
        for e in (0, -1):
            if deg[node[p[e]]] >= 2:
                P[e] = centre[node[p[e]]]
        P, R = resample(P, R, 0.5 * h)
        body = float(np.median(R))
        P = smooth_line(P, max(1.5, 0.5 * body / (0.5 * h)))
        w = max(3, int(round(SPAN * body / (0.5 * h))) | 1)
        if len(R) > w:
            R = ndimage.median_filter(R, size=w, mode="nearest")
        s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
        for e in (0, -1):
            if deg[node[p[e]]] >= 3:
                d = s if e == 0 else s[-1] - s
                inner = R[d > 1.5 * body]
                top = FORK * float(np.median(inner if len(inner) else R))
                R = np.where(d < 2.5 * body, np.minimum(R, top), R)
        R = ndimage.gaussian_filter1d(R, max(1.0, 0.25 * body / (0.5 * h)), mode="nearest")
        m = min(len(R), max(3, int(round(2 * body / (0.5 * h)))))
        lines.append((P, R, m))
    # each cut end paired with the free end of a branch nearest it
    pairs = []
    for i, p in enumerate(br):
        P, R, m = lines[i]
        for e in (0, -1):
            if deg[node[p[e]]] != 1:
                continue
            r_end = float(np.median(R[:m] if e == 0 else R[-m:]))
            for k, hl in enumerate(holes):
                d = float(np.linalg.norm(P[e] - hl["c"]))
                if d < NEAR * hl["r"] + 2 * h and ENDS[0] <= r_end / hl["r"] <= ENDS[1]:
                    pairs.append((d, k, i, e))
    cut, taken = {}, set()
    for d, k, i, e in sorted(pairs):
        if k in taken or (i, e) in cut:
            continue
        cut[(i, e)] = holes[k]
        taken.add(k)
    C, Rs, B, cuts = [], [], [], []
    for i, p in enumerate(br):
        P, R, m = lines[i]
        # an end no narrower than the vessel just behind it: a cut end as wide as the tube there, a closed
        # end rounded, not drawn to a point
        for e in (0, -1):
            if deg[node[p[e]]] == 1:
                seg = slice(0, m) if e == 0 else slice(len(R) - m, len(R))
                end = float(np.median(R[seg])) * (1.0 if (i, e) in cut else 0.7)
                R[seg] = np.maximum(R[seg], end)
        C.append(P)
        Rs.append(R)
        B.append(np.full(len(P), i))
        for e in (0, -1):
            if (i, e) in cut:
                hl = dict(cut[(i, e)])
                back = P[min(m, len(P) - 1)] if e == 0 else P[max(len(P) - 1 - m, 0)]
                out = (hl["c"] - back) / max(np.linalg.norm(hl["c"] - back), 1e-12)
                r_end = float(R[e])
                if not hl["flat"] or abs(out @ hl["n"]) < 0.8 or r_end < 0.5 * hl["r"]:
                    hl["n"] = out           # a ragged, sidelong or far wider hole: cut straight across the branch
                elif out @ hl["n"] < 0:
                    hl["n"] = -hl["n"]
                tip = hl["c"] + hl["n"] * (PAST * r_end + 2 * h)
                Q, S = resample(np.stack([P[e], hl["c"], tip]), np.full(3, r_end), 0.5 * h)
                C.append(Q)
                Rs.append(S)
                B.append(np.full(len(Q), i))
                cuts.append((hl, r_end, i))
    return np.concatenate(C), np.concatenate(Rs), np.concatenate(B), cuts


def field(C, R, h):
    """The tube as a field on a grid of side h: inside where positive (each ball's radius less its distance,
    the most of them), eased over EASE voxels (the forks' creases). Returns it and its corner."""
    pad = 3
    lo = (C - R[:, None]).min(0) - pad * h
    hi = (C + R[:, None]).max(0) + pad * h
    shape = np.ceil((hi - lo) / h).astype(int) + 1
    F = np.full(shape, -2.0 * h, np.float32)
    for c, r in zip(C, R):
        a = np.maximum(np.floor((c - r - 2 * h - lo) / h).astype(int), 0)
        b = np.minimum(np.ceil((c + r + 2 * h - lo) / h).astype(int) + 1, shape)
        g = [lo[k] + np.arange(a[k], b[k]) * h - c[k] for k in range(3)]
        d = np.sqrt(g[0][:, None, None] ** 2 + g[1][None, :, None] ** 2 + g[2][None, None, :] ** 2)
        sub = F[a[0]:b[0], a[1]:b[1], a[2]:b[2]]
        np.maximum(sub, (r - d).astype(np.float32), out=sub)
    return ndimage.gaussian_filter(F, EASE), lo


def neighbours(T):
    """Pairs of triangles that share an edge."""
    E = np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])
    tri = np.tile(np.arange(len(T)), 3)
    key = np.sort(E, 1)
    o = np.lexsort(key.T[::-1])
    same = (key[o][1:] == key[o][:-1]).all(1)
    return tri[o][:-1][same], tri[o][1:][same]


def open_end(P, T, hl, rr, past):
    """The tube opened at one of its cut ends (the hole hl, the tube rr wide there and drawn on `past` beyond
    the hole's plane): the triangles near the hole cut along its plane (both halves kept, each new point
    shared by the triangles on either side of its edge), and the cap beyond the plane taken off, the piece of
    the surface past the plane that is bounded by the plane alone (it runs on nowhere else) and lies nearest
    the drawn-on tip. Returns the points, the triangles and whether it opened."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    c, n = hl["c"], hl["n"]
    reach = past + 2.5 * rr
    s = (P - c) @ n
    s = np.where(np.abs(s) < 1e-10, 0.0, s)
    across = (s[T] > 0).any(1) & (s[T] < 0).any(1)
    # the triangles across the plane near the hole, and those that share an edge across it with them (so no
    # edge is cut on one side and not on the other)
    cross = across & (np.linalg.norm(P - c, axis=1)[T] < reach).any(1)
    idx = np.where(across)[0]
    if len(idx) and cross.any():
        a, b = neighbours(T[idx])
        while True:
            grow = np.zeros(len(T), bool)
            grow[idx[b[cross[idx[a]] & ~cross[idx[b]]]]] = True
            grow[idx[a[cross[idx[b]] & ~cross[idx[a]]]]] = True
            if not grow.any():
                break
            cross |= grow
    new, at = [], {}

    def on(a, b):
        key = (min(a, b), max(a, b))
        if key not in at:
            new.append(P[a] + (P[b] - P[a]) * (s[a] / (s[a] - s[b])))
            at[key] = len(P) + len(new) - 1
        return at[key]
    out = []
    for tri in T[cross]:
        st = s[tri]
        if (st == 0).any():                         # one corner on the plane: two triangles
            i = int(np.argmax(st == 0))
            a, b, d = tri[i], tri[(i + 1) % 3], tri[(i + 2) % 3]
            m = on(b, d)
            out += [(a, b, m), (a, m, d)]
        else:                                       # one corner alone on its side: three
            i = int(np.argmax(st > 0 if (st > 0).sum() == 1 else st < 0))
            a, b, d = tri[i], tri[(i + 1) % 3], tri[(i + 2) % 3]
            ab, ad = on(a, b), on(a, d)
            out += [(a, ab, ad), (ab, b, d), (ab, d, ad)]
    if new:
        P = np.concatenate([P, np.array(new)])
        s = np.concatenate([s, np.zeros(len(new))])
    T = np.concatenate([T[~cross], np.array(out, np.int64).reshape(-1, 3)])
    beyond = np.where((s[T] > 0).any(1))[0]
    if not len(beyond):
        return P, T, False
    a, b = neighbours(T[beyond])
    k = len(beyond)
    _, lab = connected_components(coo_matrix((np.ones(len(a)), (a, b)), shape=(k, k)), directed=False)
    tip = c + n * past
    gap = np.linalg.norm(P[T[beyond]].mean(1) - tip, axis=1)
    far = (np.linalg.norm(P[T[beyond]] - c, axis=-1) > reach).any(1)
    best = None
    for j in np.unique(lab):
        m = lab == j
        if far[m].any():
            continue                                # it runs on past the hole: the vessel, not its cap
        g = float(gap[m].min())
        if g < 2.0 * rr + past and (best is None or g < best[0]):
            best = (g, j)
    if best is None:
        return P, T, False
    return P, np.delete(T, beyond[lab == best[1]], axis=0), True


def tidy(P, T, small):
    """The mesh with points no triangle uses left out, and each piece of it under `small` across (bar the
    largest) dropped."""
    lab = pieces(len(P), T)
    ids, cnt = np.unique(lab, return_counts=True)
    if len(ids) > 1:
        keep = np.zeros(len(T), bool)
        for i in ids:
            m = lab == i
            q = P[np.unique(T[m])]
            if i == ids[np.argmax(cnt)] or np.linalg.norm(q.max(0) - q.min(0)) >= small:
                keep |= m
        T = T[keep]
    used = np.unique(T)
    at = np.full(len(P), -1, np.int64)
    at[used] = np.arange(len(used))
    return P[used], at[T]


def one_piece(C, R, B, cuts, br, node, whole, h):
    """The tree's parts joined, when the vessel came as one piece and the fill broke it (a neck thinner than
    the fill's voxels): each part to the nearest by a straight tube as wide as the narrower where they come
    nearest, the nearest first, when they lie no further apart than JOIN of that width (and four voxels); a
    part that is not joined and is under SMALL across dropped, with its cut ends. Returns the balls, their
    branches, the cut ends and how many parts it joined and dropped."""
    from scipy.spatial import cKDTree
    root = {}

    def find(x):
        while root.setdefault(x, x) != x:
            root[x] = root[root[x]]
            x = root[x]
        return x
    for p in br:
        a, b = find(node[p[0]]), find(node[p[-1]])
        if a != b:
            root[a] = b
    part = np.array([find(node[p[0]]) for p in br])[B]
    ids = list(np.unique(part))
    if len(ids) < 2:
        return C, R, B, cuts, 0, 0
    joins = []
    if whole:
        for x, a in enumerate(ids):
            ia = np.where(part == a)[0]
            for b in ids[x + 1:]:
                ib = np.where(part == b)[0]
                d, j = cKDTree(C[ib]).query(C[ia])
                g = d - R[ia] - R[ib[j]]
                k = int(np.argmin(g))
                joins.append((float(g[k]), a, b, ia[k], ib[j[k]]))
    parts = {a: a for a in ids}

    def top(x):
        while parts[x] != x:
            x = parts[x]
        return x
    nb = B.max() + 1
    Cs, Rs, Bs, joined_ = [C], [R], [B], 0
    for g, a, b, i, j in sorted(joins):
        w = min(R[i], R[j])
        if g > max(JOIN * w, 4 * h) or top(a) == top(b):
            continue
        parts[top(a)] = top(b)
        Q, S = resample(np.stack([C[i], C[j]]), np.full(2, w), 0.5 * h)
        Cs.append(Q)
        Rs.append(S)
        Bs.append(np.full(len(Q), nb))
        nb += 1
        joined_ += 1
    C, R, B = np.concatenate(Cs), np.concatenate(Rs), np.concatenate(Bs)
    part = np.concatenate([part] + [np.full(len(x), -1) for x in Bs[1:]])
    groups = defaultdict(list)
    for a in ids:
        groups[top(a)].append(a)
    size = {g: np.isin(part, m).sum() for g, m in groups.items()}
    main = max(size, key=size.get)
    drop = np.zeros(len(C), bool)
    dropped = 0
    for g, m in groups.items():
        if g == main:
            continue
        sel = np.isin(part, m)
        lo, hi = (C[sel] - R[sel, None]).min(0), (C[sel] + R[sel, None]).max(0)
        if np.linalg.norm(hi - lo) < SMALL:
            drop |= sel
            dropped += 1
    if dropped:
        gone = set(np.unique(B[drop]))
        cuts = [x for x in cuts if x[2] not in gone]
        C, R, B = C[~drop], R[~drop], B[~drop]
    return C, R, B, cuts, joined_, dropped


def within(P, T, v, f, cv, cf, m):
    """The tube's points drawn back to within m of the vessel as it came (points v, triangles f; cv, cf: its
    holes capped) where they lie further outside it: a stretch that came flattened is drawn round, and would
    swell into the bone or the gut it lies against. The rims of its open ends stay where they were cut.
    Returns the points and how many moved."""
    from anatomy_gaps import winding_number
    from scipy.spatial import cKDTree
    rim = np.zeros(len(P), bool)
    for L in loops(T):
        rim[np.asarray(L)] = True
    S = samples(v, f, 0.5 * m)
    d, j = cKDTree(S).query(P)
    out = (d > m) & ~rim
    if out.any():
        out[out] = np.abs(winding_number(P[out], cv, cf)) < 0.5
    P = P.copy()
    P[out] = S[j[out]] + (P[out] - S[j[out]]) * (m / d[out])[:, None]
    return P, int(out.sum())


def decimate(p, f, target, border=False):
    """The mesh brought down to no more than `target` triangles (fast quadric simplification), a quarter of
    its triangles kept at each pass, so the last pass does not overshoot far."""
    import fast_simplification
    for _ in range(40):
        if len(f) <= target:
            break
        goal = max(target, len(f) // 4)
        q, g = fast_simplification.simplify(p.astype(np.float32), f.astype(np.int32),
                                            target_reduction=1 - goal / len(f), agg=3 if goal > target else 5,
                                            preserve_border=border)
        if len(g) == 0 or len(g) >= len(f):
            continue
        used = np.unique(g)
        at = np.full(len(q), -1, np.int64)
        at[used] = np.arange(len(used))
        p, f = q[used].astype(np.float64), at[g]
    return p, f


def volume(p, f):
    return float(np.einsum("ij,ij->i", p[f[:, 0]], np.cross(p[f[:, 1]], p[f[:, 2]])).sum() / 6)


def typical_radius(v, f, holes):
    """A tube's radius as its volume and side give it (twice the one over the other), and no wider than
    its narrowest cut."""
    cv, cf = capped(v, f, holes)
    r = 2 * abs(volume(cv, cf)) / max(area(v, f).sum(), 1e-12)
    ends = [hl["r"] for hl in holes if hl["r"] > 0.4 * r]
    return min([r] + ends)


def rebuild(v, f, target):
    """The vessel (points v, triangles f) drawn anew as one clean tube (see the header), in no more than
    `target` triangles, its cut ends open. Returns (points, triangles, account); a vessel too fine to fill
    comes back as it was, its inner walls left out (the account says it was kept)."""
    import time
    from scipy.spatial import cKDTree
    from skimage.measure import marching_cubes
    from skimage.morphology import skeletonize
    t0 = time.time()
    v, f = weld(v, f)
    tris = len(f)
    inner = inner_walls(v, f)
    f = f[~inner]
    single = f
    target = min(target, len(single))   # one wall needs no more triangles than the outer one had
    hv = float(np.clip(np.linalg.norm(v.max(0) - v.min(0)) / 300, 0.0002, 0.001))
    hid, f = hidden_walls(v, f, hv)
    walled = hid.mean() >= WALLED       # it came with its lumen, the two walls joined: a hollow tube as it is
    if hid.mean() < WALLED:
        hid[:] = False                  # a few triangles in a crevice, no inner wall
    f = f[~hid]
    whole = len(np.unique(pieces(len(v), single))) == 1
    holes = [hole(v, L) for L in loops(f)]
    r = typical_radius(v, f, holes)
    if r < FINE or walled:
        P, T = tidy(v, single, 0.0)
        return P, T, dict(kept="walled" if walled else "fine", tris=tris, inner=int(inner.sum()), hidden=0,
                          holes=len(loops(T)), cuts=0,
                          open=len(loops(T)), pieces=len(np.unique(pieces(len(P), T))), seconds=time.time() - t0)
    cv, cf = capped(v, f, holes)
    span = cv.max(0) - cv.min(0) + 8 * r
    h = max(CELL_MIN, r / CELL, float(np.prod(span) / VOXELS) ** (1 / 3))
    g, lo = fill(cv, cf, h, 4)
    sk = Skeleton(skeletonize(g).astype(bool))
    # each skeleton voxel's radius: how far it lies from the vessel's own wall (not from the voxels'), and
    # the median distance of the wall it is the nearest point of the skeleton to (a sheet's far wider)
    S = samples(v, f, 0.5 * h)
    X = lo + (sk.pts + 0.5) * h
    rad = cKDTree(S).query(X)[0] / h
    d, j = cKDTree(X).query(S)
    o = np.argsort(j, kind="stable")
    cut = np.searchsorted(j[o], np.arange(len(X) + 1))
    wide = np.array([np.median(d[o[cut[k]:cut[k + 1]]]) if cut[k + 1] > cut[k] else np.nan
                     for k in range(len(X))]) / h
    wide = np.where(np.isnan(wide), rad, wide)
    for hl in holes:
        hl["cv"] = (hl["c"] - lo) / h - 0.5
    br, node, pruned = tree(sk, rad, wide, holes, h)
    if whole and not any(pruned.values()):
        # in one piece, and its skeleton a tree with nothing to prune: a sound tube already, and a tube drawn
        # anew would be the same vessel with other triangles (and could lose it a cut end)
        P, T = tidy(v, single, 0.0)
        return P, T, dict(kept="sound", tris=tris, inner=int(inner.sum()), hidden=0, holes=len(loops(T)), cuts=0,
                          open=len(loops(T)), pieces=len(np.unique(pieces(len(P), T))), seconds=time.time() - t0)
    C, R, B, cuts = balls(sk, br, node, np.minimum(wide, OVAL * np.maximum(rad, 1.0)), h, lo, holes)
    widest = max(float(np.median(R[B == i])) for i in np.unique(B))
    if widest >= GREAT and any(hl["cut"] and hl["r"] >= 0.5 * widest and rr < FLATTENED * hl["r"]
                               for hl, rr, _ in cuts):
        # a great vessel with a branch far thinner than the cut end it runs out at: its wall is drawn there as
        # a flap, not a tube (the man's aortic arch), and a tube round the flap's centre line would be a thread
        # hanging from the arch; it keeps its own surface
        P, T = tidy(v, single, 0.0)
        return P, T, dict(kept="flat", tris=tris, inner=int(inner.sum()), hidden=0, holes=len(loops(T)), cuts=0,
                          open=len(loops(T)), pieces=len(np.unique(pieces(len(P), T))), seconds=time.time() - t0)
    C, R, B, cuts, joins, dropped = one_piece(C, R, B, cuts, br, node, whole, h)
    # the field on a grid fine enough for the narrowest branch, and the surface round the balls; brought down
    # to the triangles it had, each cut end then opened flat in its plane (its cap taken off), and again from
    # the drawn surface if what is left falls short of them or runs over. Where so few triangles cannot hold a
    # thin branch (bringing the surface down pinches it off), the thin are drawn wider (WIDER of an edge of
    # the triangles the surface gets, step by step) and, at the last, what is pinched off is left out.
    R0, cuts0, edge, best = R, cuts, 0.0, None
    for wider in (0.0,) + WIDER:
        R = np.maximum(R0, wider * edge)
        cuts = [(hl, max(rr, wider * edge), k) for hl, rr, k in cuts0]
        thin = min(float(np.median(R[B == i])) for i in np.unique(B))
        span = (C + R[:, None]).max(0) - (C - R[:, None]).min(0) + 6 * h
        hf = min(h, max(CELL_MIN, thin / 2.5, float(np.prod(span) / VOXELS) ** (1 / 3)))
        R = np.maximum(R, THIN * hf)
        F, lo2 = field(C, R, hf)
        P0, T0 = marching_cubes(F, 0.0, spacing=(hf, hf, hf))[:2]
        P0, T0 = P0.astype(np.float64) + lo2, T0.astype(np.int64)
        lab = pieces(len(P0), T0)
        size = np.bincount(lab)
        T0 = T0[size[lab] >= CRUMB * len(T0)]
        if volume(P0, T0) < 0:
            T0 = T0[:, ::-1]
        P0, T0 = tidy(P0, T0, SMALL)
        made, drawn = len(T0), len(np.unique(pieces(len(P0), T0)))
        held = abs(volume(P0, T0)) / max(float(g.sum()) * h ** 3, 1e-18)
        edge = edge or math.sqrt(4 * area(P0, T0).sum() / target / math.sqrt(3))
        goal, found = target, None
        for _ in range(5):
            P, T = decimate(P0, T0, goal)
            opened = 0
            for hl, rr, k in cuts:
                P, T, ok = open_end(P, T, hl, rr, PAST * rr + 2 * h)
                opened += ok
            P, T = tidy(P, T, SMALL)
            if len(T) <= target and (found is None or (opened, len(T)) > (found[2], len(found[1]))):
                found = (P, T, opened)
            if 0.9 * target <= len(T) <= target and opened == len(cuts):
                break
            goal = max(8, int(goal * target / max(len(T), 1) * (0.98 if len(T) > target else 1.0)))
        if found is None:
            P, T = decimate(P, T, target, border=True)
            found = (*tidy(P, T, SMALL), opened)
        parts = len(np.unique(pieces(len(found[0]), found[1])))
        if best is None or parts < best[3]:
            best = (*found, parts, wider, hf, made, len(cuts), held)
        if parts <= drawn:
            break
    P, T, opened, parts, wider, hf, made, ncuts, held = best
    shed = 0
    if parts > drawn:                       # still pinched off: the largest pieces kept, as many as were drawn
        lab = pieces(len(P), T)
        ids, cnt = np.unique(lab, return_counts=True)
        keep = ids[np.argsort(-cnt)[:drawn]]
        shed = parts - drawn
        P, T = tidy(P, T[np.isin(lab, keep)], 0.0)
    # the tube held within the vessel as it came (not where a broken neck was joined: the join lies outside
    # it); then how far the vessel lies from the tube, against its radius as its volume and side give it
    ra = 2 * abs(volume(cv, cf)) / max(area(v, f).sum(), 1e-12)
    drawn_in = 0
    if not joins:
        P, drawn_in = within(P, T, v, f, cv, cf, SWELL * ra)
    far = float((cKDTree(samples(P, T, 0.15 * ra)).query(samples(v, f, 0.15 * ra))[0] > AWAY[0] * ra).mean())
    if whole and far >= AWAY[2 if pruned["sheets"] or pruned["rings"] else 1]:
        P, T = tidy(v, single, 0.0)
        return P, T, dict(kept="shape", far=round(far, 2), tris=tris, inner=int(inner.sum()), hidden=0,
                          holes=len(loops(T)), cuts=0, open=len(loops(T)),
                          pieces=len(np.unique(pieces(len(P), T))), seconds=time.time() - t0)
    said = dict(h=h, hf=hf, r=r, tris=tris, inner=int(inner.sum()), hidden=int(hid.sum()), holes=len(holes),
                cuts=ncuts, opened=opened, branches=len(br), joins=joins, dropped=dropped, made=made,
                wider=wider, shed=shed, held=round(held, 2), far=round(far, 2), drawn_in=drawn_in,
                open=len(loops(T)), pieces=len(np.unique(pieces(len(P), T))), seconds=time.time() - t0, **pruned)
    return P, T, said


def rewrite(folder, part, meshes):
    """A part's file written anew from its meshes, and its entry in the manifest with it."""
    lo, hi = write_part(os.path.join(folder, part["file"]),
                        [(np.asarray(v, np.float32), np.asarray(f, np.int64)) for v, f in meshes])
    for st, (_, f) in zip(part["structures"], meshes):
        st["triangles"] = int(len(f))
    part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
    part["sha256"] = sha256(os.path.join(folder, part["file"]))
    part["triangles"] = int(sum(s["triangles"] for s in part["structures"]))
    part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]


def remake(folder, quiet=False):
    """Each vessel of `folder`'s atlas drawn anew as one clean tube (see the header), the labels set right
    and a vessel drawn twice made one; the vessels' part rewritten. Does nothing for a body done already.
    Returns what it did."""
    import json
    import time
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if body.get("vessels"):
            continue
        part = next((p for p in body["parts"] if p["id"] == PART), None)
        if part is None:
            continue
        t0 = time.time()
        meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
                  for v, f in read_part(os.path.join(folder, part["file"]))]
        sts = part["structures"]
        named = 0
        for st in sts:
            if st["node"] in LABELS and (st["label"], st.get("uberon")) != LABELS[st["node"]]:
                st["label"], st["uberon"] = LABELS[st["node"]]
                named += 1
        merged = []
        for a, b in SAME.items():
            i = next((k for k, s in enumerate(sts) if s["node"] == a), None)
            j = next((k for k, s in enumerate(sts) if s["node"] == b), None)
            if i is None or j is None:
                continue
            (va, fa), (vb, fb) = meshes[i], meshes[j]
            meshes[j] = (np.concatenate([vb, va]), np.concatenate([fb, fa + len(vb)]))
            del meshes[i], sts[i]
            merged.append(f"{a} into {b}")
        before = sum(len(f) for _, f in meshes)
        tally = defaultdict(int)
        kept = []
        for k, st in enumerate(sts):
            if st.get("tissue") not in TISSUES:
                continue
            v, f = meshes[k]
            P, T, info = rebuild(v, f, len(f))
            meshes[k] = (P, T)
            tally["inner"] += info["inner"] + info["hidden"]
            if info.get("kept"):
                kept.append(info["kept"])
                continue
            tally["redrawn"] += 1
            for key in ("holes", "cuts", "opened", "joins", "dropped", "shed", "knobs", "stumps", "sheets", "rings"):
                tally[key] += int(info.get(key, 0))
            tally["wider"] += info.get("wider", 0) > 0
            if not quiet:
                print(f"    {st['node']}: {info['tris']} -> {len(T)} triangles, {info['opened']} of {info['holes']} "
                      f"holes open cut ends ({info['cuts']} drawn), {info['pieces']} piece(s), "
                      f"{info['seconds']:.1f} s", flush=True)
        rewrite(folder, part, meshes)
        after = sum(len(f) for _, f in meshes)
        body["vessels"] = True
        said.append(f"{body['id']}: {tally['redrawn']} vessels drawn anew ({kept.count('fine')} too fine and "
                    f"{kept.count('walled')} drawn with their lumen and {kept.count('flat') + kept.count('shape')} no plain "
                    f"tube and {kept.count('sound')} sound already kept as drawn), "
                    f"{tally['inner']} triangles of inner walls left out, {tally['knobs']} knobs, "
                    f"{tally['stumps']} stumps and {tally['sheets']} sheets pruned, {tally['rings']} rings cut, "
                    f"{tally['joins']} broken necks joined and {tally['dropped']} crumbs dropped, {tally['wider']} vessels' "
                    f"thin branches drawn wider and {tally['shed']} pinched-off pieces left out, "
                    f"{tally['opened']} cut ends kept open ({tally['cuts']} drawn) of {tally['holes']} holes (the "
                    f"rest mouths and stumps, closed), {named} labels set right"
                    + (f", {'; '.join(merged)}" if merged else "") + f"; {before} -> {after} triangles, "
                    f"{time.time() - t0:.0f} s")
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            print("  " + line)
    return "; ".join(said) or "vessels drawn anew already"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("anatomy_vessels.py ATLAS_FOLDER")
    print(remake(sys.argv[1]))
