#!/usr/bin/env python3
"""The atlas's muscles' fibres: bundles laid along the way each muscle's
fibres run, for the app's muscle shader (AtlasShaders.muscle), which draws
them as rounded cords with dark seams between them.

    tools/anatomy_fibres.py <atlas folder>     rewrites its muscular parts and anatomy.json

For each skeletal muscle (tissue muscle, in a part of the muscular system):

1. Finer: split into four triangles a side (each edge at its middle) until
   its edges are under FINE (4.5 mm) at the median, then smoothed without
   shrinking (Taubin's steps), so a coarse mesh loses its facets.
2. Its fibres: a length along the muscle, u, held at 0 where it meets the
   bones it arises from and 1 where it meets those it inserts on (RULES:
   its surface within CONTACT, 4 mm, of them, or WIDER, 7 mm, if that finds
   too few; a bone of its own side or of the midline; the origin's contact
   kept to what lies far along the muscle from the insertion where a rule
   says `far`), or, with no rule or no contact, at the 3% of its surface at
   either tip of its long axis; spread between as a harmonic function
   (cotangent weights). The fibres run along u's gradient on the surface.
3. Tendon where the muscle is narrow near an end: its slice across u (one
   of 20) under 45% as wide as its widest, fully under 25%, within the last
   quarter at either end.
4. Its bundles: stripes along the fibres a bundle wide (a thirtieth of its
   length along its fibres, 1.5 to 6 mm), as Knoeppel, Crane, Pinkall and
   Schroeder lay them (Stripe Patterns on Surfaces, 2015): a unit complex
   number at each vertex whose phase turns by 2 pi a bundle across the
   fibres, found as the smallest eigenvector of the energy that asks each
   edge to turn it by as much as the fibres across it say (inverse
   iteration). Where the bundles cannot run on (where the muscle narrows
   and they must merge), the pattern forks, as a muscle's fascicles do.
5. Per triangle the phase unwound at its corners, and the triangles joined
   where their corners agree (a whole bundle or a reversed count apart is
   agreement); a vertex whose triangles disagree is split. Each vertex
   then carries where it lies across the bundles (one bundle a unit, the
   seams at whole numbers) and its tendon's share; the few triangles
   holding a fork carry -1 there, which the shader leaves plain. Before
   that, the triangles holding a fork are split in four, twice, the new
   corners' phases read along their edges (a neighbour split in two where
   it shares one of their edges), so the fork sits in a triangle a
   sixteenth the size and its plain patch is too small to see.

The part's .atlas is rewritten with the finer, split meshes, and beside it
<body>-<part>.fibres (read by Shared/Sciences/AnatomyAtlas.swift):

    "SAF1"                       magic
    u32 count                    structures, in the manifest's order
    count times:
      u32 vertices               its vertex count, or 0 for none (not a skeletal muscle)
      f32 bundle                 the bundles' width, metres
      f32 x vertices             where each vertex lies across the bundles
      f32 x vertices             its tendon's share (0 to 1), or -1 where it forks

and the part's entry in anatomy.json gains "fibres": {"file", "bytes",
"sha256"}, its bytes, sha256, triangles and bounds updated. Called by
tools/anatomy_atlas.py once the atlas is written; also runs on a built
atlas folder on its own (a part already laid, one listing its "fibres",
is left as it is). Needs numpy and scipy.
"""
import collections, hashlib, json, os, re, struct, sys

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spl
from scipy.spatial import cKDTree

CONTACT, WIDER, FINE = 0.004, 0.007, 0.0045

# (muscle, origin's bones, insertion's bones, options): regular expressions on structure names
RULES = [
    (r"gluteus_maximus", r"ilium|hip_bone|_hip_|sacrum|coccyx", r"femur", {}),
    (r"gluteus_medius", r"ilium|hip_bone|_hip_", r"femur", {}),
    (r"gluteus_minimus", r"ilium|hip_bone|_hip_", r"femur", {}),
    (r"iliopsoas", r"lumbar_vertebra|ilium|hip_bone|_hip_", r"femur", {"far": 0.4}),
]
# muscle that is not skeletal: the heart's, the eye's ciliary, the bladder's smooth muscle
NOT_SKELETAL = re.compile(r"papillary|ciliary|smooth_muscle|gyrus")


# MARK: reading and writing parts

def read_part(path):
    """A part's meshes (positions in metres, triangles) from its .atlas file."""
    b = open(path, "rb").read()
    if b[:4] != b"SAT1":
        raise ValueError(f"{path}: not an atlas part")
    at = 4
    n, = struct.unpack_from("<I", b, at); at += 4
    lo = np.array(struct.unpack_from("<3f", b, at), np.float64)
    hi = np.array(struct.unpack_from("<3f", b, at + 12), np.float64); at += 24
    scale = (hi - lo) / 65535
    out = []
    for _ in range(n):
        v, t = struct.unpack_from("<II", b, at); at += 8
        q = np.frombuffer(b, "<u2", v * 3, at).reshape(-1, 3); at += v * 6
        wide = v > 65535
        f = np.frombuffer(b, "<u4" if wide else "<u2", t * 3, at).reshape(-1, 3).astype(np.int64)
        at += t * 3 * (4 if wide else 2)
        at += (4 - at % 4) % 4
        out.append((lo + q.astype(np.float64) * scale, f))
    return out


def write_part(path, meshes):
    """As tools/anatomy_atlas.py writes a part; returns its bounds."""
    allp = np.concatenate([p for p, _ in meshes])
    lo, hi = allp.min(0), allp.max(0)
    span = np.where(hi - lo > 0, hi - lo, 1)
    out = bytearray(b"SAT1")
    out += struct.pack("<I", len(meshes)) + struct.pack("<6f", *lo, *hi)
    for p, f in meshes:
        q = np.clip(np.round((p - lo) / span * 65535), 0, 65535).astype("<u2")
        out += struct.pack("<II", len(p), len(f))
        out += q.tobytes()
        out += np.asarray(f).astype("<u2" if len(p) <= 65535 else "<u4").tobytes()
        out += b"\0" * (-len(out) % 4)
    open(path, "wb").write(out)
    return lo, hi


def write_fibres(path, entries):
    out = bytearray(b"SAF1") + struct.pack("<I", len(entries))
    for e in entries:
        if e is None:
            out += struct.pack("<If", 0, 0.0)
            continue
        across, tendon, bundle = e
        out += struct.pack("<If", len(across), bundle)
        out += np.asarray(across, "<f4").tobytes() + np.asarray(tendon, "<f4").tobytes()
    open(path, "wb").write(out)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# MARK: meshes

def weld(v, f):
    """The mesh with points at one place made one (to a micrometre)."""
    key = np.round(v * 1e6).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    f = inverse.reshape(-1)[f]
    f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
    return v[first], f


def edges_of(f):
    e = np.sort(np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    return np.unique(e, axis=0)


def neighbours(n, f):
    e = edges_of(f)
    a = sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    return (a + a.T).tocsr()


def taubin(v, f, rounds=6, lam=0.5, mu=-0.53):
    adj = neighbours(len(v), f)
    deg = np.asarray(adj.sum(1)).ravel()
    deg[deg == 0] = 1
    for _ in range(rounds):
        for k in (lam, mu):
            v = v + k * (adj @ v / deg[:, None] - v)
    return v


def subdivide(v, f):
    """Each triangle into four, each edge split at its middle."""
    e = np.sort(np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    uniq, inverse = np.unique(e, axis=0, return_inverse=True)
    mid = len(v) + inverse.reshape(-1)
    m = len(f)
    a, b, c = mid[:m], mid[m:2 * m], mid[2 * m:]
    v2 = np.vstack([v, (v[uniq[:, 0]] + v[uniq[:, 1]]) / 2])
    f2 = np.vstack([np.c_[f[:, 0], a, c], np.c_[a, f[:, 1], b], np.c_[c, b, f[:, 2]], np.c_[a, b, c]])
    return v2, f2


def normals(v, f):
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    length = np.linalg.norm(n, axis=1)
    return n / np.where(length > 0, length, 1)[:, None], fn


def cotan_weights(v, f):
    """Each edge's cotangent weight (half the cotangents of the angles opposite it), kept positive."""
    rows, cols, vals = [], [], []
    for k in range(3):
        i, j, o = f[:, k], f[:, (k + 1) % 3], f[:, (k + 2) % 3]
        a, b = v[i] - v[o], v[j] - v[o]
        cot = (a * b).sum(1) / np.maximum(np.linalg.norm(np.cross(a, b), axis=1), 1e-18)
        rows += [i, j]; cols += [j, i]; vals += [cot / 2, cot / 2]
    w = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(len(v), len(v))).tocsr()
    w.data = np.maximum(w.data, 1e-3 * np.abs(w.data).mean())
    return w


def vertex_area(v, f):
    a = np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1) / 6
    m = np.zeros(len(v))
    for k in range(3):
        np.add.at(m, f[:, k], a)
    return np.maximum(m, 1e-12)


# MARK: fibres

def surface_points(v, f, h=0.001):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    k = np.maximum(1, np.ceil(area / (h * h))).astype(int)
    rng = np.random.default_rng(0)
    tri = np.repeat(np.arange(len(f)), k)
    r1, r2 = rng.random(len(tri)), rng.random(len(tri))
    s = np.sqrt(r1)
    p = a[tri] * (1 - s)[:, None] + b[tri] * (s * (1 - r2))[:, None] + c[tri] * (s * r2)[:, None]
    return np.vstack([v, p])


def side(name):
    m = re.search(r"_(L|R)$", name)
    return m.group(1) if m else None


def long_axis(v):
    return np.linalg.svd(v - v.mean(0), full_matrices=False)[2][0]


def ends(name, v, bones):
    """The vertices held at u = 0 (origin) and 1 (insertion), by its rule's bones or its long axis's tips."""
    rule = next((r for r in RULES if re.search(r[0], name)), None)
    if rule is not None:
        _, origin, insertion, options = rule
        hits = []
        for pattern in (origin, insertion):
            pts = [p for bone, p in bones.items() if re.search(pattern, bone) and side(bone) in (None, side(name))]
            if not pts:
                hits.append(np.zeros(len(v), bool))
                continue
            d, _ = cKDTree(np.vstack(pts)).query(v, distance_upper_bound=WIDER)
            hit = d < CONTACT
            if hit.sum() < 12:
                hit = d < WIDER
            hits.append(hit)
        o, i = hits
        if o.any() and i.any():
            t = v @ long_axis(v)
            both = o & i
            if both.any():
                ti, to = t[i & ~o].mean() if (i & ~o).any() else t[i].mean(), t[o & ~i].mean() if (o & ~i).any() else t[o].mean()
                nearer = np.abs(t - ti) < np.abs(t - to)
                o, i = o & ~(both & nearer), i & ~(both & ~nearer)
            if "far" in options and i.any():
                o = o & (np.abs(t - t[i].mean()) > options["far"] * np.ptp(t))
        if o.sum() >= 3 and i.sum() >= 3:
            return o, i, "bones"
    t = v @ long_axis(v)
    lo, hi = np.quantile(t, [0.03, 0.97])
    return t <= lo, t >= hi, "tips"


def harmonic(v, f, held0, held1):
    w = cotan_weights(v, f)
    L = sp.diags(np.asarray(w.sum(1)).ravel()) - w
    u = np.full(len(v), 0.5)
    u[held0], u[held1] = 0.0, 1.0
    held = held0 | held1
    free = ~held
    if free.any():
        A = L[free][:, free].tocsc()
        b = -L[free][:, held] @ u[held]
        u[free] = spl.spsolve(A + sp.identity(A.shape[0]) * 1e-12, b)
    return np.clip(u, 0, 1)


def gradient(v, f, u, vn):
    """u's gradient at each vertex, on the surface (area-weighted over its triangles)."""
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    twice = np.linalg.norm(fn, axis=1)
    ok = twice > 1e-18
    n = fn / np.where(ok, twice, 1)[:, None]
    g = (np.cross(n, p2 - p1) * u[f[:, 0], None] + np.cross(n, p0 - p2) * u[f[:, 1], None]
         + np.cross(n, p1 - p0) * u[f[:, 2], None])  # times twice the area: area-weighted when summed
    gv = np.zeros_like(v)
    for k in range(3):
        np.add.at(gv, f[:, k], g * ok[:, None])
    gv -= vn * (gv * vn).sum(1)[:, None]
    return gv


def fibre_way(v, f, u, vn):
    adj = neighbours(len(v), f)
    g = gradient(v, f, u, vn)
    length = np.linalg.norm(g, axis=1)
    known = length > 1e-9 * max(length.max(), 1e-30)
    d = np.where(known[:, None], g / np.where(length > 0, length, 1)[:, None], 0)
    # where u is flat (held against bone): the neighbours' way, spread inward
    for _ in range(64):
        if known.all():
            break
        s = adj @ (d * known[:, None])
        c = np.asarray(adj @ known.astype(float)).ravel()
        take = ~known & (c > 0)
        if not take.any():
            break
        d[take] = s[take]
        known = known | take
    for _ in range(2):
        d = d + adj @ d
        d -= vn * (d * vn).sum(1)[:, None]
        d /= np.maximum(np.linalg.norm(d, axis=1), 1e-12)[:, None]
    return d


def tendon_share(v, u):
    bins = 20
    b = np.minimum(bins - 1, (u * bins).astype(int))
    radius = np.ones(bins)
    for i in range(bins):
        sel = b == i
        if sel.any():
            radius[i] = np.linalg.norm(v[sel] - v[sel].mean(0), axis=1).mean()
    have = np.bincount(b, minlength=bins) > 0
    narrow = np.where(have, radius / max(radius[have].max(), 1e-12), 1.0)
    x = u * bins - 0.5
    i0 = np.clip(np.floor(x).astype(int), 0, bins - 1)
    i1 = np.minimum(i0 + 1, bins - 1)
    w = np.clip(x - i0, 0, 1)
    thin = narrow[i0] * (1 - w) + narrow[i1] * w

    def smooth(e0, e1, x):
        t = np.clip((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    return smooth(0.45, 0.25, thin) * smooth(0.25, 0.08, np.minimum(u, 1 - u))


# MARK: bundles (stripe patterns)

def stripes(v, f, across, width, rounds=40):
    """The unit complex number at each vertex (as angles) whose phase turns 2 pi a `width` along `across`."""
    n = len(v)
    e = edges_of(f)
    i, j = e[:, 0], e[:, 1]
    w = np.asarray(cotan_weights(v, f)[i, j]).ravel()
    s = np.where((across[i] * across[j]).sum(1) >= 0, 1.0, -1.0)
    d = v[j] - v[i]
    nu = 2 * np.pi / width
    omega = nu / 2 * ((across[i] * d).sum(1) + s * (across[j] * d).sum(1))
    c, sn = np.cos(omega), np.sin(omega)
    # energy w |C x_j - R x_i|^2: blocks A_ii += w, A_jj += w, A_ij = -w R^T C, A_ji = its transpose
    # R = [[c, -sn], [sn, c]], C = diag(1, s); R^T C = [[c, s sn], [-sn, s c]]
    rows, cols, vals = [], [], []

    def put(r, cc, val):
        rows.append(r); cols.append(cc); vals.append(val)
    for a in (0, 1):
        put(2 * i + a, 2 * i + a, w); put(2 * j + a, 2 * j + a, w)
    m = [[c, s * sn], [-sn, s * c]]
    for a in (0, 1):
        for b in (0, 1):
            put(2 * i + a, 2 * j + b, -w * m[a][b])
            put(2 * j + b, 2 * i + a, -w * m[a][b])
    A = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(2 * n, 2 * n)).tocsc()
    mass = np.repeat(vertex_area(v, f), 2)
    M = sp.diags(mass)
    shift = 1e-6 * A.diagonal().mean() / mass.mean()
    solve = spl.splu((A + M * shift).tocsc())
    x = np.random.default_rng(3).standard_normal(2 * n)
    for _ in range(rounds):
        x = solve.solve(mass * x)
        x /= np.sqrt((x * x * mass).sum())
    z = x[0::2] + 1j * x[1::2]
    return np.angle(z), s, omega, e


def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi


def corners(v, f, across, phase, width):
    """Each triangle's corners' phases, unwound from its first corner, and whether it holds a fork."""
    nu = 2 * np.pi / width
    out = np.zeros((len(f), 3))
    sign = np.ones((len(f), 3))
    i = f[:, 0]
    out[:, 0] = phase[i]
    for k in (1, 2):
        j = f[:, k]
        s = np.where((across[i] * across[j]).sum(1) >= 0, 1.0, -1.0)
        d = v[j] - v[i]
        om = nu / 2 * ((across[i] * d).sum(1) + s * (across[j] * d).sum(1))
        pj = s * phase[j]
        out[:, k] = out[:, 0] + om + wrap(pj - out[:, 0] - om)
        sign[:, k] = s
    # the third edge, from corner 1 to corner 2, read the same way: a whole turn apart is a fork
    j, k2 = f[:, 1], f[:, 2]
    bj, bk = across[j] * sign[:, 1, None], across[k2] * sign[:, 2, None]
    d = v[k2] - v[j]
    om = nu / 2 * ((bj * d).sum(1) + (bk * d).sum(1))
    expect = out[:, 1] + om + wrap(out[:, 2] - out[:, 1] - om)
    fork = np.abs(expect - out[:, 2]) > np.pi
    return out / (2 * np.pi), fork


def refine(v, f, across, phase, tendon, fork, width):
    """The triangles holding forks split in four, a neighbour in two where it shares one of their
    edges (in four if two), each new corner's phase read along its edge the way the pattern runs: a
    fork then sits in a triangle a quarter the size, its plain patch too small to see."""
    nu = 2 * np.pi / width
    n = len(v)
    pairs = np.stack([np.sort(f[:, [k, (k + 1) % 3]], axis=1) for k in range(3)], axis=1)
    keys = pairs[..., 0].astype(np.int64) * n + pairs[..., 1]
    marked = np.unique(keys[fork])
    while True:
        count = np.isin(keys, marked).sum(1)
        grow = np.setdiff1d(keys[count == 2], marked)
        if not len(grow):
            break
        marked = np.union1d(marked, grow)
    a, b = marked // n, marked % n
    s = np.where((across[a] * across[b]).sum(1) >= 0, 1.0, -1.0)
    d = v[b] - v[a]
    om = nu / 2 * ((across[a] * d).sum(1) + s * (across[b] * d).sum(1))
    mid_phase = wrap(phase[a] + om / 2 + wrap(s * phase[b] - phase[a] - om) / 2)
    mid_across = across[a] + s[:, None] * across[b]
    mid_across /= np.maximum(np.linalg.norm(mid_across, axis=1), 1e-12)[:, None]
    index = {int(k): n + i for i, k in enumerate(marked)}
    faces = []
    for t, (p, q, r) in enumerate(f):
        m = [index.get(int(keys[t, k])) for k in range(3)]
        hit = [x is not None for x in m]
        if all(hit):
            faces += [(p, m[0], m[2]), (m[0], q, m[1]), (m[2], m[1], r), (m[0], m[1], m[2])]
        elif hit[0]:
            faces += [(p, m[0], r), (m[0], q, r)]
        elif hit[1]:
            faces += [(p, q, m[1]), (p, m[1], r)]
        elif hit[2]:
            faces += [(p, q, m[2]), (q, r, m[2])]
        else:
            faces.append((p, q, r))
    return (np.vstack([v, (v[a] + v[b]) / 2]), np.array(faces, np.int64), np.vstack([across, mid_across]),
            np.concatenate([phase, mid_phase]), np.concatenate([tendon, (tendon[a] + tendon[b]) / 2]))


def join(f, coord, fork):
    """Triangles turned or moved by whole bundles to agree with their neighbours, then their corners
    shared where they agree; returns the corner's new vertex and its coordinate."""
    m = len(f)
    coord = coord.copy()
    edge_tris = collections.defaultdict(list)
    for t in range(m):
        for k in range(3):
            a, b = f[t, k], f[t, (k + 1) % 3]
            edge_tris[(min(a, b), max(a, b))].append(t)
    placed = np.zeros(m, bool)
    for start in range(m):
        if placed[start]:
            continue
        placed[start] = True
        queue = collections.deque([start])
        while queue:
            t = queue.popleft()
            if fork[t]:
                continue
            for k in range(3):
                a, b = f[t, k], f[t, (k + 1) % 3]
                for o in edge_tris[(min(a, b), max(a, b))]:
                    if placed[o] or fork[o]:
                        continue
                    ka, kb = list(f[o]).index(a), list(f[o]).index(b)
                    ta, tb = coord[t, k], coord[t, (k + 1) % 3]
                    for sgn in (1.0, -1.0):
                        oa, ob = sgn * coord[o, ka], sgn * coord[o, kb]
                        shift = np.round(ta - oa)
                        if abs(ta - oa - shift) < 1e-4 and abs(tb - ob - shift) < 1e-4:
                            coord[o] = sgn * coord[o] + shift
                            placed[o] = True
                            queue.append(o)
                            break
    key = {}
    vertex = np.zeros((m, 3), np.int64)
    origin = []
    for t in range(m):
        for k in range(3):
            q = (int(f[t, k]), int(np.round(coord[t, k] * 1e4)), bool(fork[t]))
            if q not in key:
                key[q] = len(origin)
                origin.append((f[t, k], coord[t, k], fork[t]))
            vertex[t, k] = key[q]
    return vertex, origin


def lay(name, v, f, bones):
    """A muscle made finer, its fibres and bundles: (positions, triangles, across, tendon, bundle, log)."""
    v, f = weld(v, f)
    level = 0
    while level < 3:
        e = edges_of(f)
        if np.median(np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)) <= FINE:
            break
        v, f = subdivide(v, f)
        level += 1
    if level:
        v = taubin(v, f)
    vn, _ = normals(v, f)
    held0, held1, how = ends(name, v, bones)
    u = harmonic(v, f, held0, held1)
    way = fibre_way(v, f, u, vn)
    across = np.cross(vn, way)
    across /= np.maximum(np.linalg.norm(across, axis=1), 1e-12)[:, None]
    along = v @ (way.mean(0) / max(np.linalg.norm(way.mean(0)), 1e-12))
    bundle = float(np.clip(np.ptp(along) / 30, 0.0015, 0.006))
    phase, *_ = stripes(v, f, across, bundle)
    tendon = tendon_share(v, u)
    coord, fork = corners(v, f, across, phase, bundle)
    forks = int(fork.sum())
    for _ in range(2):
        if fork.any():
            v, f, across, phase, tendon = refine(v, f, across, phase, tendon, fork, bundle)
            coord, fork = corners(v, f, across, phase, bundle)
    vertex, origin = join(f, coord, fork)
    src = np.array([o[0] for o in origin])
    pos = v[src]
    acr = np.array([o[1] for o in origin], np.float32)
    ten = np.where(np.array([o[2] for o in origin]), -1.0, tendon[src]).astype(np.float32)
    log = (f"{name}: {level} split{'s' * (level != 1)}, {len(f)} triangles, {len(pos)} vertices ({len(pos) - len(v)} split "
           f"at seams), fibres from {how}, bundles {bundle * 1000:.1f} mm, {forks} forks ({int(fork.sum())} after "
           f"refining), "
           f"tendon {float((tendon > 0.5).mean()):.0%}")
    return pos, vertex, acr, ten, bundle, log


def annotate(folder, quiet=False):
    """Lays the bundles on every skeletal muscle in `folder`'s atlas; returns how many."""
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    done = 0
    for body in manifest["bodies"]:
        bones = {}
        named = re.compile("|".join(f"{o}|{i}" for _, o, i, _ in RULES))
        for part in body["parts"]:
            if part["system"] != "skeletal":
                continue
            for st, (v, f) in zip(part["structures"], read_part(os.path.join(folder, part["file"]))):
                if st.get("tissue") == "bone" and named.search(st["node"]):
                    bones[st["node"]] = surface_points(v, f)
        for part in body["parts"]:
            if part["system"] != "muscular" or "fibres" in part:
                continue
            meshes = read_part(os.path.join(folder, part["file"]))
            out, entries = [], []
            for st, (v, f) in zip(part["structures"], meshes):
                st.pop("fibres", None)
                if st.get("tissue") != "muscle" or NOT_SKELETAL.search(st["node"]):
                    out.append((v, f)); entries.append(None)
                    continue
                pos, tri, acr, ten, bundle, log = lay(st["node"], v, f, bones)
                out.append((pos, tri)); entries.append((acr, ten, bundle))
                st["triangles"] = int(len(tri))
                done += 1
                if not quiet:
                    print(f"  {body['id']} {log}")
            lo, hi = write_part(os.path.join(folder, part["file"]), out)
            fibres = part["file"].rsplit(".", 1)[0] + ".fibres"
            write_fibres(os.path.join(folder, fibres), entries)
            part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
            part["sha256"] = sha256(os.path.join(folder, part["file"]))
            part["triangles"] = int(sum(s["triangles"] for s in part["structures"]))
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
            part["fibres"] = {"file": fibres, "bytes": os.path.getsize(os.path.join(folder, fibres)),
                              "sha256": sha256(os.path.join(folder, fibres))}
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    return done


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(f"{annotate(sys.argv[1])} muscles with their bundles laid")
