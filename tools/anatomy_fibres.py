#!/usr/bin/env python3
"""The atlas's muscles' fibres: for every point of each skeletal muscle,
where it lies across the fibres and how far it is tendon, for the app's
muscle shader (AtlasShaders.muscle), which draws the fibres as soft streaks
along the lines they truly run by.

    tools/anatomy_fibres.py <atlas folder>     rewrites its muscular parts and anatomy.json

For each skeletal muscle (tissue muscle, in a part of the muscular system):

1. Finer: split into four triangles a side (each edge at its middle) until
   its edges are under FINE (4.5 mm, or a nineteenth of the muscle's size
   where that is less: the square root of its surface) at the median, then
   smoothed without shrinking (Taubin's steps), so a coarse mesh loses its
   facets, and brought back down (quadric decimation) to as many triangles
   as edges of about EVEN (4.3 mm, or a twentieth of its size) at the
   median need. A muscle and its mirror (the same name ending _L and _R)
   are split alike, as often as the coarser of them needs, and brought down
   to the same count, so the two sides look alike.
2. Its line of pull: a length along the muscle, u, held at 0 where it
   meets the bones it arises from and 1 where it meets those it inserts on
   (RULES: its surface within CONTACT, 4 mm, of them, or WIDER, 7 mm, if
   that finds too few; a bone of its own side or of the midline; the
   origin's contact kept to what lies far along the muscle from the
   insertion where a rule says `far`), or, with no rule or no contact, at
   the 3% of its surface at either tip of its long axis (ORIGIN_TOWARD
   says which tip it arises from, where that matters); each end made one
   patch (its pieces joined by the shortest ways over the surface); spread
   between as a harmonic function (cotangent weights, as they are).
3. Where each point lies round the muscle: u's harmonic conjugate, an
   angle that is the same all along each line u climbs by and turns once
   round the muscle between its two ends (`turning`). It is found on the
   triangles, where it is told outright: across an edge it changes by u's
   flow through that edge, which sums to nothing round a vertex and to u's
   whole flow round an end, so the angle counted as 2 pi a whole flow has
   no seam; each vertex then takes the mean of its triangles' values. A
   muscle whose fibres run from origin to insertion (most: straight, or
   fanning from a broad origin to a narrow tendon, which u's lines do of
   themselves) has its fibres along those lines. A pennate one
   (ARCHITECTURE) has them slanting off its line of pull by its angle of
   pennation, from the tendon they arise on (`fibre_angle`).
4. Tendon where the muscle is narrow near an end: its slice across u (one
   of 20) under 45% as wide as its widest, fully under 25%, within the last
   quarter at either end; at its insertion only, for a muscle with a rule
   (the glutei and iliopsoas arise fleshy and end in tendon); where it is
   thin instead, for the eye's muscles and the gluteus maximus
   (`thin_share`); and along the tendon a pennate muscle's fibres leave.
5. Each vertex then carries two numbers, a point: its angle about the
   origin the angle of step 3 (so the same all along a fibre), its distance
   from the origin 2 less its tendon's share. A point on a circle has no
   seam, so no vertex is split and the shader's lines run on round the
   muscle unbroken; where the fibres run together at an end the points of
   a triangle lie all round the circle, the point between them falls
   toward the middle, and that reads as tendon too, which an end is.

The part's .atlas is rewritten with the finer meshes, and beside it
<body>-<part>.fibres (read by Shared/Sciences/AnatomyAtlas.swift):

    "SAF2"                       magic
    u32 count                    structures, in the manifest's order
    count times:
      u32 vertices               its vertex count, or 0 for none (not a skeletal muscle)
      2 f32 x vertices           each vertex's point: x, y

and the part's entry in anatomy.json gains "fibres": {"file", "bytes",
"sha256"}, its bytes, sha256, triangles and bounds updated. Called by
tools/anatomy_atlas.py once the atlas is written; also runs on a built
atlas folder on its own (a part already laid, one listing its "fibres",
is left as it is). Needs numpy, scipy and fast_simplification.
"""
import hashlib, json, os, re, struct, sys

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spl
from scipy.spatial import cKDTree

CONTACT, WIDER, FINE = 0.004, 0.007, 0.0045
EVEN = 0.0043   # a split muscle brought down to edges about this long at the median, under FINE

HIP_BONE = r"ilium|ischium|pubis|hip_bone|_hip_"
# (muscle, origin's bones, insertion's bones, options): regular expressions on structure names
RULES = [
    # (tools/anatomy_gluteus.py makes it: its tendon the sheet it thins to at its insertion, so found as the eye
    # muscles' are, where it is thin)
    (r"gluteus_maximus", r"ilium|hip_bone|_hip_|sacrum|coccyx", r"femur", {"tendon": "thin"}),
    (r"gluteus_medius", r"ilium|hip_bone|_hip_", r"femur", {}),
    (r"gluteus_minimus", r"ilium|hip_bone|_hip_", r"femur", {}),
    (r"iliopsoas", r"lumbar_vertebra|ilium|hip_bone|_hip_", r"femur", {"far": 0.4}),
    # tools/anatomy_muscles_body.py's (its MUSCLES says where each arises and inserts)
    (r"vastus_", r"femur", r"patella", {}),
    (r"adductor_|pectineus|obturator_|gemelli|piriformis", HIP_BONE + r"|sacrum", r"femur", {}),
    (r"semimembranosus|semitendinosus|gracilis|sartorius|tensor_fasciae", HIP_BONE, r"tibia", {}),
    (r"biceps_femoris_long", HIP_BONE, r"fibula", {}),
    (r"biceps_femoris_short", r"femur", r"fibula", {}),
    (r"gastrocnemius|plantaris", r"femur", r"calcaneus", {}),
    (r"soleus", r"tibia|fibula", r"calcaneus", {}),
    (r"popliteus", r"femur", r"tibia", {}),
    (r"tibialis_|flexor_digitorum_longus|flexor_hallucis|peroneus|extensor_digitorum", r"tibia|fibula",
     r"cuneiform|navicular|metatarsal|phalanx", {}),
    (r"trapezius", r"occipital|cervical_vertebra|thoracic_vertebra", r"clavicle|scapula", {}),
    (r"rhomboid", r"cervical_vertebra|thoracic_vertebra", r"scapula", {}),
    (r"latissimus", r"thoracic_vertebra|lumbar_vertebra|sacrum|rib_|" + HIP_BONE, r"humerus", {}),
    (r"deltoid", r"clavicle|scapula", r"humerus", {}),
    (r"supraspinatus|infraspinatus|subscapularis", r"scapula", r"humerus", {}),
    (r"splenius_capitis", r"cervical_vertebra_7|thoracic_vertebra", r"temporal|occipital", {}),
    (r"semispinalis_capitis", r"thoracic_vertebra|cervical_vertebra_[4-7]", r"occipital", {}),
    (r"semispinalis_cervicis", r"thoracic_vertebra", r"cervical_vertebra_[2-5]", {}),
    (r"quadratus_lumborum", HIP_BONE, r"rib_12|lumbar_vertebra", {}),
]
# muscle that is not skeletal: the heart's, the eye's ciliary, the bladder's smooth muscle
NOT_SKELETAL = re.compile(r"papillary|ciliary|smooth_muscle|gyrus")
# the eye's muscles (tools/anatomy_eyes.py): their tendons flat (the recti's, curving on the eyeball) or long and
# round (the superior oblique's, which bends at the trochlea), so their ends are the far ends of their longest way
# along them and their tendon where they are thin, not narrow
THIN_TENDONS = re.compile(r"extraocular")

# Which end a muscle arises from, where its ends are the tips of its long axis (those say which two, not which is
# which): the direction its origin lies in from its insertion, in the body's frame.
ORIGIN_TOWARD = [
    (r"rectus_femoris|quadriceps", (0.0, 1.0, 0.0)),      # the anterior inferior iliac spine, above; the patella below
    (r"deep_back_muscles", (0.0, -1.0, 0.0)),             # the sacrum and iliac crest (the erector spinae's common origin)
    # tools/anatomy_muscles_body.py's: "medial" is toward the midline, whichever side the muscle is on
    (r"trapezius|rhomboid|latissimus|supraspinatus|infraspinatus|subscapularis|obturator_|gemelli|piriformis", "medial"),
    (r"splenius|semispinalis|quadratus_lumborum", (0.0, -1.0, 0.0)),
    (r"deltoid|tensor_fasciae|pectineus|vastus_|adductor_|biceps_femoris|semimembranosus|semitendinosus|gracilis"
     r"|sartorius|tibialis_|flexor_digitorum_longus|flexor_hallucis|popliteus|peroneus|extensor_digitorum|soleus"
     r"|plantaris|gastrocnemius", (0.0, 1.0, 0.0)),
]
# How a muscle's fibres lie where they do not simply run from its origin to its insertion (muscle, how, the angle
# they make with its line of pull in degrees, the face they leave from as a direction in the body's frame: x its
# left, y up, z forward). A bipennate muscle's fibres leave a tendon on that face to either side, going down the
# muscle and round it; a unipennate one's all slant one way round it (the right muscle's the mirror of the left's).
#   rectus femoris: bipennate, its superficial fibres from the anterior aponeurosis (Gray 1918, p. 470); 14 degrees
#   (Ward, Eng, Smallwood and Lieber 2009, Clin Orthop Relat Res 467:1074, table 1: 13.9)
ARCHITECTURE = [
    (r"rectus_femoris", "bipennate", 14.0, (0.0, 0.0, 1.0)),
]


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
    out = bytearray(b"SAF2") + struct.pack("<I", len(entries))
    for e in entries:
        if e is None:
            out += struct.pack("<I", 0)
            continue
        out += struct.pack("<I", len(e)) + np.asarray(e, "<f4").tobytes()
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


def cotan_weights(v, f, positive=True):
    """Each edge's cotangent weight (half the cotangents of the angles opposite it), kept positive (or, for
    `positive` False, as it is: the surface's own Dirichlet energy, which the fibres' lines are worked in)."""
    rows, cols, vals = [], [], []
    for k in range(3):
        i, j, o = f[:, k], f[:, (k + 1) % 3], f[:, (k + 2) % 3]
        a, b = v[i] - v[o], v[j] - v[o]
        cot = (a * b).sum(1) / np.maximum(np.linalg.norm(np.cross(a, b), axis=1), 1e-18)
        rows += [i, j]; cols += [j, i]; vals += [cot / 2, cot / 2]
    w = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(len(v), len(v))).tocsr()
    if positive:
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


def origin_toward(name):
    """The direction a muscle's origin lies in from its insertion (ORIGIN_TOWARD), or None."""
    way = next((r[1] for r in ORIGIN_TOWARD if re.search(r[0], name)), None)
    if isinstance(way, str):      # "medial": the body's left is +x
        return np.array([1.0 if side(name) == "R" else -1.0, 0.0, 0.0])
    return None if way is None else np.asarray(way, float)


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
        # One end on its bone and the other short of its own (a belly whose tendon is not modelled): that end
        # is the tip farthest the other way, and the end on the bone keeps clear of it.
        toward = origin_toward(name)
        if toward is not None and (o.sum() >= 3 or i.sum() >= 3):
            t = v @ toward
            lo, mid_lo, mid_hi, hi = np.quantile(t, [0.03, 0.2, 0.8, 0.97])
            if o.sum() >= 3 and (o & (t > mid_lo)).sum() >= 3:
                return o & (t > mid_lo), t <= lo, "its origin's bone and its far tip"
            if i.sum() >= 3 and (i & (t < mid_hi)).sum() >= 3:
                return t >= hi, i & (t < mid_hi), "its far tip and its insertion's bone"
    t = v @ long_axis(v)
    lo, hi = np.quantile(t, [0.03, 0.97])
    return t <= lo, t >= hi, "tips"


def far_ends(v, f):
    """The vertices held at u = 0 and 1 for a muscle that may bend: about the two ends of its longest way along its
    surface (shortest paths swept from a vertex to the farthest, and from that one to the farthest again)."""
    from scipy.sparse.csgraph import dijkstra
    e = edges_of(f)
    g = sp.coo_matrix((np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1), (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr()
    far = lambda d: int(np.argmax(np.where(np.isfinite(d), d, -1)))
    a = far(dijkstra(g, directed=False, indices=0))
    da = dijkstra(g, directed=False, indices=a)
    b = far(da)
    db = dijkstra(g, directed=False, indices=b)
    return da < 0.03 * da[b], db < 0.03 * da[b], "far ends"


def harmonic(v, f, held0, held1, positive=True):
    w = cotan_weights(v, f, positive)
    L = sp.diags(np.asarray(w.sum(1)).ravel()) - w
    u = np.full(len(v), 0.5)
    u[held0], u[held1] = 0.0, 1.0
    held = held0 | held1
    free = ~held
    if free.any():
        A = L[free][:, free].tocsc()
        b = -L[free][:, held] @ u[held]
        u[free] = spl.spsolve(A + sp.identity(A.shape[0]) * 1e-12, b)
    return np.clip(u, 0, 1) if positive else u


def tendon_share(v, u, origin=True):
    """Each vertex's share of tendon: where its slice across u is narrow, near an end (the origin's, u = 0, too
    unless `origin` is False)."""
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
    return smooth(0.45, 0.25, thin) * smooth(0.25, 0.08, np.minimum(u, 1 - u) if origin else 1 - u)


def thin_share(v, f, u):
    """Each vertex's share of tendon by how thin the muscle is there: its thickness at each vertex the distance to the
    nearest point of the opposite face, the median of it across each slice along u against the thickest slice's. A
    flat tendon is as wide as its belly and a sixth as thick, a round one narrower; tendon runs in from either end
    while its slices stay thin."""
    vn, _ = normals(v, f)
    k = min(64, len(v))
    d, i = cKDTree(v).query(v, k=k)
    opposite = np.einsum("ij,ikj->ik", vn, vn[i]) < -0.7
    thick = np.where(opposite, d, np.inf).min(1)
    thick = np.where(np.isfinite(thick), thick, d[:, -1])
    bins = 40
    b = np.minimum(bins - 1, (u * bins).astype(int))
    med = np.array([np.median(thick[b == j]) if (b == j).sum() >= 4 else np.nan for j in range(bins)])
    have = ~np.isnan(med)
    if not have.any():
        return np.zeros(len(v))
    ratio = np.interp(np.arange(bins), np.flatnonzero(have), med[have] / med[have].max())
    thin = np.clip((0.5 - ratio) / 0.15, 0, 1)
    thin = thin * thin * (3 - 2 * thin)
    reach = np.zeros(bins, bool)
    for order in (range(bins), range(bins - 1, -1, -1)):
        for j in order:
            if ratio[j] >= 0.5:
                break
            reach[j] = True
    share = np.where(reach, thin, 0.0)
    x = np.clip(u * bins - 0.5, 0, bins - 1)
    i0 = np.floor(x).astype(int)
    i1 = np.minimum(i0 + 1, bins - 1)
    w = x - i0
    return share[i0] * (1 - w) + share[i1] * w


# MARK: the fibres' own lines

def wrap(a):
    """An angle brought into -pi to pi."""
    return (a + np.pi) % (2 * np.pi) - np.pi


def face_gradient(v, f, u):
    """u's gradient on each triangle, its unit normal and twice its area."""
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    fn = np.cross(p1 - p0, p2 - p0)
    twice = np.maximum(np.linalg.norm(fn, axis=1), 1e-18)
    n = fn / twice[:, None]
    g = (np.cross(n, p2 - p1) * u[f[:, 0], None] + np.cross(n, p0 - p2) * u[f[:, 1], None]
         + np.cross(n, p1 - p0) * u[f[:, 2], None]) / twice[:, None]
    return g, n, twice


def one_patch(v, f, held, other):
    """`held` with its separate patches joined into one by the shortest ways between them over the surface (not
    through `other`): an end held in several places is one line of attachment, and the surface between the two
    ends then a band the fibres' lines run round once."""
    from scipy.sparse.csgraph import connected_components, dijkstra
    n = len(v)
    e = edges_of(f)
    length = np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)
    held = held.copy()
    for _ in range(64):
        inside = held[e[:, 0]] & held[e[:, 1]]
        g = sp.coo_matrix((np.ones(inside.sum()), (e[inside, 0], e[inside, 1])), shape=(n, n))
        count, label = connected_components(g, directed=False)
        patches = np.unique(label[held])
        if len(patches) <= 1:
            break
        first = held & (label == np.bincount(label[held]).argmax())
        rest = held & ~first
        open_ = ~other[e[:, 0]] & ~other[e[:, 1]]
        way = sp.coo_matrix((length[open_], (e[open_, 0], e[open_, 1])), shape=(n, n)).tocsr()
        d, before, source = dijkstra(way, directed=False, indices=np.flatnonzero(first), min_only=True,
                                     return_predecessors=True)
        reach = np.where(rest, d, np.inf)
        k = int(np.argmin(reach))
        if not np.isfinite(reach[k]):
            break
        while k >= 0 and not first[k]:
            held[k] = True
            k = int(before[k])
    return held


def turning(v, f, u, held):
    """Where each vertex lies round the muscle, as a unit complex number whose angle is constant along the lines u
    climbs by (the fibres, from origin to insertion) and turns once round the muscle: u's harmonic conjugate. It
    lives on the triangles: over an edge between two of them it changes by u's flow through that edge (its
    cotangent weight times u's change along it), which sums to nothing round a vertex where u is harmonic, and to
    u's whole flow round an end. So over the triangles with no held corner it is told but for whole flows, and the
    number turned 2 pi a whole flow is told outright. Returns the numbers at the vertices (the mean of their
    triangles'), the flow, and the largest misfit where two ways round met (in turns: 0 on a muscle whose two ends
    are one patch each)."""
    from scipy.sparse.csgraph import breadth_first_order, connected_components
    nv, nf = len(v), len(f)
    w = cotan_weights(v, f, positive=False)
    free_face = ~held[f].any(1)
    # each half edge's triangle, and the triangle over it
    i = np.concatenate([f[:, k] for k in range(3)])
    j = np.concatenate([f[:, (k + 1) % 3] for k in range(3)])
    face = np.tile(np.arange(nf), 3)
    order = np.argsort(i * nv + j, kind="stable")
    keys = (i * nv + j)[order]
    at = np.searchsorted(keys, j * nv + i)
    at = np.minimum(at, len(keys) - 1)
    twin = np.where(keys[at] == j * nv + i, face[order][at], -1)
    ok = (twin >= 0) & free_face[face] & free_face[np.maximum(twin, 0)]
    a, b = face[ok], twin[ok]
    # the angle's change from a to b: u's gradient, turned a quarter turn about the normal, along the way from
    # a's circumcentre to b's
    step = np.asarray(w[i[ok], j[ok]]).ravel() * (u[i[ok]] - u[j[ok]])
    out = held & (u < 0.5)
    e = edges_of(f)
    cross = out[e[:, 0]] != out[e[:, 1]]
    lo = np.where(out[e[cross, 0]], e[cross, 0], e[cross, 1])
    hi = np.where(out[e[cross, 0]], e[cross, 1], e[cross, 0])
    flow = float((np.asarray(w[lo, hi]).ravel() * (u[hi] - u[lo])).sum())
    graph = sp.coo_matrix((np.ones(len(a)), (a, b)), shape=(nf, nf)).tocsr()
    lookup = {}
    for x, y, s_ in zip(a.tolist(), b.tolist(), step.tolist()):
        lookup[(x, y)] = s_
    count, label = connected_components(graph, directed=False)
    angle = np.full(nf, np.nan)
    for c in np.unique(label[free_face]):
        start = int(np.flatnonzero(free_face & (label == c))[0])
        nodes, before = breadth_first_order(graph, start, directed=False, return_predecessors=True)
        angle[start] = 0.0
        for node in nodes[1:]:
            parent = int(before[node])
            way = lookup.get((parent, int(node)))   # (an edge listed one way only, where the mesh is pinched)
            angle[node] = angle[parent] + (way if way is not None else -lookup[(int(node), parent)])
    turn = 2 * np.pi / max(abs(flow), 1e-30)
    miss = np.abs(wrap((angle[b] - angle[a] - step) * turn)) / (2 * np.pi)
    # At the vertices: on each triangle the angle is linear (u's gradient there, turned a quarter turn about the
    # normal), with the value above at the circumcentre; two triangles' agree at the middle of the edge they share.
    # A vertex takes the mean of its triangles' values at it, as unit numbers (so whole turns do not matter).
    g, n, twice = face_gradient(v, f, u)
    r = np.cross(n, g)
    p0 = v[f[:, 0]]
    e1, e2 = v[f[:, 1]] - p0, v[f[:, 2]] - p0
    fn = np.cross(e1, e2)
    centre = p0 + ((e1 * e1).sum(1)[:, None] * np.cross(e2, fn) + (e2 * e2).sum(1)[:, None] * np.cross(fn, e1)) \
        / (2 * np.maximum((fn * fn).sum(1), 1e-36))[:, None]
    base = np.nan_to_num(angle)
    z = np.zeros(nv, complex)
    for k in range(3):
        at_vertex = base + (r * (v[f[:, k]] - centre)).sum(1)
        np.add.at(z, f[:, k], np.where(free_face, twice * np.exp(1j * at_vertex * turn), 0))
    # a vertex with no such triangle (inside an end): its neighbours', spread inward
    adj = neighbours(nv, f)
    known = np.abs(z) > 0
    for _ in range(64):
        if known.all():
            break
        s_ = adj @ np.where(known, z / np.maximum(np.abs(z), 1e-30), 0)
        take = ~known & (np.abs(s_) > 0)
        if not take.any():
            break
        z[take] = s_[take]
        known = known | take
    z = np.where(np.abs(z) > 0, z / np.maximum(np.abs(z), 1e-30), 1.0)
    return z, abs(flow), float(miss.max()) if len(miss) else 0.0


def along_fibres(v, f, u, z):
    """How well the angle's lines follow u's: the area-weighted mean of |cos| between the angle's gradient and
    u's on each triangle (0: its level lines are u's gradient lines), over the triangles where both are told."""
    g, n, twice = face_gradient(v, f, u)
    a = np.angle(z)
    d1, d2 = wrap(a[f[:, 1]] - a[f[:, 0]]), wrap(a[f[:, 2]] - a[f[:, 0]])
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    ga = (np.cross(p2 - p0, n) * d1[:, None] + np.cross(n, p1 - p0) * d2[:, None]) / twice[:, None]
    lg, la = np.linalg.norm(g, axis=1), np.linalg.norm(ga, axis=1)
    ok = (lg > 0.05 * np.median(lg)) & (la > 0)
    c = np.abs((g * ga).sum(1)) / np.maximum(lg * la, 1e-30)
    return float((c * twice)[ok].sum() / max(twice[ok].sum(), 1e-30))


def fibre_angle(name, v, f, u, z, flow):
    """Where each vertex lies across the muscle's fibres, in turns (constant along a fibre), as a unit complex
    number; how its fibres lie; and the tendon they leave, as a share at each vertex (or None). A muscle whose
    fibres run from origin to insertion: z itself. A pennate one (ARCHITECTURE): u and z's angle are a conformal
    pair (the angle times flow / 2 pi changes as fast as u does, at right angles), so a line at the angle `a` to
    u's lines keeps  angle / 2 pi -+ u tan(a) / flow.  Unipennate: that, all round. Bipennate: the angle counted
    from the face the fibres leave, either way, less u tan(a) / flow (lines leaving that face's middle to both
    sides as they go down), brought into nine tenths of a turn, so it never wraps. Where the two sides meet (that
    face's middle line and the one opposite) the count is rounded over an edge and a half's width, as a mesh can
    hold: the fibres there turn into the tendon they leave, which is marked along that face's line, 9 mm to
    either side (two edges and a bit, where those are longer: a narrower band would bead along the triangles), seven
    tenths tendon at the origin and fading to none just over half way down, as an aponeurosis thins into the flesh."""
    rule = next((r for r in ARCHITECTURE if re.search(r[0], name)), None)
    if rule is None or flow <= 0:
        return z, "along", None
    _, how, degrees, toward = rule
    k = np.tan(np.radians(degrees)) / flow
    uc = np.clip(u, 0, 1)
    if how == "unipennate":   # (the angle runs the other way round a mirrored muscle: the right's the left's mirrored)
        return z * np.exp((2j if side(name) == "R" else -2j) * np.pi * uc * k), how, None
    vn, _ = normals(v, f)
    area = vertex_area(v, f)
    facing = (vn @ np.asarray(toward, float) > 0.7) & (uc > 0.25) & (uc < 0.75)
    if not facing.any():
        return z, "along: no face of it looks the way its rule says its fibres leave", None
    middle = (z[facing] * area[facing]).sum()
    s_ = np.abs(np.angle(z * np.conj(middle / max(abs(middle), 1e-30)))) / (2 * np.pi)   # 0 to half a turn
    # a turn's length across the belly, and the rounding's width in turns
    g, _, twice = face_gradient(v, f, uc)
    belly = (uc[f].mean(1) > 0.25) & (uc[f].mean(1) < 0.75)
    span = flow / max(np.median(np.linalg.norm(g, axis=1)[belly]) if belly.any() else 0, 1e-9)   # metres a turn
    e = 1.5 * median_edge(v, f) / span
    soft = 0.5 * (np.sqrt(s_ * s_ + e * e) - np.sqrt((0.5 - s_) ** 2 + e * e)) + 0.25
    reach = max(0.009, 2.2 * median_edge(v, f))
    t = np.clip((reach - s_ * span) / (0.7 * reach), 0, 1)
    return np.exp(2j * np.pi * 0.9 * (soft - uc * k + k) / (0.5 + k)), how, \
        0.7 * np.clip(1 - uc / 0.55, 0, 1) * t * t * (3 - 2 * t)


def median_edge(v, f):
    e = edges_of(f)
    return float(np.median(np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)))


def splits(v, f):
    """How often a (welded) muscle is split in four for its edges to be under FINE at the median, at most 3,
    and how many triangles it needs for them to be about EVEN (a split halves the edges and quarters the
    triangles, so that count is the same however often it is split). A small muscle's edges are shorter: a
    twentieth of its size (the square root of its surface), so the lines its fibres run by are not bent at
    every triangle (the larynx's muscles, a centimetre or two long, had 170 to 300 triangles each)."""
    size = float(np.sqrt(np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1).sum() / 2))
    fine, even = min(FINE, size / 19), min(EVEN, size / 20)
    level, count = 0, int(np.ceil(len(f) * (median_edge(v, f) / even) ** 2))
    while level < 3 and median_edge(v, f) > fine:
        v, f = subdivide(v, f)
        level += 1
    return level, count


def coarsen(v, f, target):
    """A smoothed, split muscle brought down to about `target` triangles, in gentle passes (agg 3 first:
    its triangles are well shaped and shade smoothly), one closed surface still."""
    import fast_simplification
    for agg in (3, 5, 7):
        if len(f) <= target * 1.1:
            break
        q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32),
                                            target_reduction=1 - target / len(f), agg=agg)
        if len(g) == 0 or len(g) >= len(f):
            continue
        used = np.unique(g)
        remap = np.full(len(q), -1, dtype=np.int64)
        remap[used] = np.arange(len(used))
        v, f = q[used].astype(np.float64), remap[g]
    return v, f


def mirror(name):
    """The same muscle's name on the other side (_L and _R swapped), or None."""
    m = re.search(r"_([LR])$", name)
    return name[:-1] + ("R" if m.group(1) == "L" else "L") if m else None


def pieces(n, f):
    """The mesh's connected pieces: each vertex's piece, and how many there are."""
    from scipy.sparse.csgraph import connected_components
    e = edges_of(f)
    count, label = connected_components(sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)), directed=False)
    return label, count


BROAD = 0.012   # an end is broad where some of it lies this far (over the surface) inside its own patch
FAR = 0.7       # of a broad end, the part kept: what lies in the last three tenths of its way from the other end


def far_rim(v, f, held, other):
    """A broad end brought down to its far rim. Where a muscle lies on its bone over a whole face (the gluteus
    minimus on the ilium), that face is all "its origin's bone", and held as one end it leaves u flat over
    the muscle's top: its lines all left the patch by the edge nearest the insertion, and a third of the
    muscle had none (the woman's right gluteus minimus). The muscle's surface fibres arise at the far edge of
    such an attachment and run the muscle's whole length, so that edge is the end: of a patch some of which lies
    BROAD inside it, the part in the last (1 - FAR) of its range of distances from the other end, over the
    surface. A narrow one (a line of attachment, however long: the latissimus's along the spine) is kept whole."""
    from scipy.sparse.csgraph import dijkstra
    if not held.any() or not other.any() or held.all():
        return held
    n = len(v)
    e = edges_of(f)
    g = sp.coo_matrix((np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr()
    depth = dijkstra(g, directed=False, indices=np.flatnonzero(~held), min_only=True)
    if not (depth[held] > BROAD).any():
        return held
    d = dijkstra(g, directed=False, indices=np.flatnonzero(other), min_only=True)
    ok = held & np.isfinite(d)
    if not ok.any():
        return held
    lo, hi = d[ok].min(), d[ok].max()
    kept = ok & (d >= lo + FAR * (hi - lo))
    return kept if kept.sum() >= 3 else held


def shut_in(v, f, held0, held1):
    """The two ends with each run of free surface that touches one of them only added to it: such a run (an
    island inside a broad attachment, or a lobe past it) has no way to the other end, so u is one number all
    over it and no line could be drawn across it; it is part of that attachment. (A run that touches neither
    cannot be: the piece is connected and has both ends.) Returns the ends and the area's share so moved."""
    from scipy.sparse.csgraph import connected_components
    n = len(v)
    e = edges_of(f)
    free = ~(held0 | held1)
    inside = free[e[:, 0]] & free[e[:, 1]]
    _, label = connected_components(sp.coo_matrix((np.ones(inside.sum()), (e[inside, 0], e[inside, 1])), shape=(n, n)),
                                    directed=False)
    touch0, touch1 = np.zeros(n, bool), np.zeros(n, bool)
    for a_, b_ in ((e[:, 0], e[:, 1]), (e[:, 1], e[:, 0])):
        touch0[label[a_[free[a_] & held0[b_]]]] = True
        touch1[label[a_[free[a_] & held1[b_]]]] = True
    to0, to1 = free & touch0[label] & ~touch1[label], free & touch1[label] & ~touch0[label]
    area = vertex_area(v, f)
    return held0 | to0, held1 | to1, float(area[to0 | to1].sum() / max(area.sum(), 1e-30))


def stalled(v, f, u, held0, held1):
    """The free vertices where u has all but stopped at an end's value (it changes under a tenth as fast as it
    would evenly down the muscle's length, and is within a twentieth of 0 or of 1): surface behind that end, with
    no way to the other but past it (a muscle's top rising above its highest hold on the bone; a lobe cut off by
    the way one_patch joined two patches). Returns the two sets and their share of the area."""
    from scipy.sparse.csgraph import dijkstra
    e = edges_of(f)
    g = sp.coo_matrix((np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1), (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr()
    d = dijkstra(g, directed=False, indices=np.flatnonzero(held1), min_only=True)
    length = float(np.median(d[held0 & np.isfinite(d)])) if (held0 & np.isfinite(d)).any() else 0.0
    if length <= 0:
        return np.zeros(len(v), bool), np.zeros(len(v), bool), 0.0
    grad, _, twice = face_gradient(v, f, u)
    size = np.linalg.norm(grad, axis=1)
    top, under = np.zeros(len(v)), np.zeros(len(v))
    for k in range(3):
        np.add.at(top, f[:, k], size * twice)
        np.add.at(under, f[:, k], twice)
    slow = ~(held0 | held1) & (top / np.maximum(under, 1e-30) < 0.1 / length)
    at0, at1 = slow & (u < 0.05), slow & (u > 0.95)
    area = vertex_area(v, f)
    return at0, at1, float(area[at0 | at1].sum() / max(area.sum(), 1e-30))


def lay_piece(name, v, f, bones):
    """One connected piece's fibres: (the two numbers each vertex carries, a line of the log)."""
    held0, held1, how = far_ends(v, f) if THIN_TENDONS.search(name) else ends(name, v, bones)
    toward = origin_toward(name)
    if how == "tips" and toward is not None and (v[held0].mean(0) - v[held1].mean(0)) @ toward < 0:
        held0, held1 = held1, held0
    moved = 0.0
    for again in range(3):
        if how != "far ends":
            held0, held1 = far_rim(v, f, held0, held1), far_rim(v, f, held1, held0)
        held0 = one_patch(v, f, held0, held1)
        held1 = one_patch(v, f, held1, held0)
        held0, held1, shut = shut_in(v, f, held0, held1)
        u = harmonic(v, f, held0, held1, positive=False)
        # surface behind an end joins it, and the end (now broad) is brought down to its far rim: the lines
        # then start from the muscle's true far edge
        at0, at1, share = stalled(v, f, u, held0, held1)
        moved = max(moved, shut + share)
        if how == "far ends" or share < 0.015 or again == 2:
            break
        held0, held1 = held0 | at0, held1 | at1
    z, flow, miss = turning(v, f, u, held0 | held1)
    off = along_fibres(v, f, u, z)
    c, lie, leaves = fibre_angle(name, v, f, u, z, flow)
    uc = np.clip(u, 0, 1)
    rule = next((r for r in RULES if re.search(r[0], name)), None)
    thin = THIN_TENDONS.search(name) or (rule is not None and rule[3].get("tendon") == "thin")
    tendon = thin_share(v, f, uc) if thin else tendon_share(v, uc, origin=how == "tips" or how.startswith("its far"))
    if leaves is not None:
        tendon = np.maximum(tendon, leaves)
    pair = np.stack([c.real, c.imag], 1) * (2.0 - np.clip(tendon, 0, 1))[:, None]
    log = (f"fibres from {how} ({lie}), {off:.3f} off u's lines, misfit {miss:.4f} turns, u {u.min():.2f} to "
           f"{u.max():.2f}, tendon {float((tendon > 0.5).mean()):.0%}"
           + (f", {moved:.0%} of its surface behind an end" if moved > 0.005 else ""))
    return pair, log


def lay(name, v, f, bones, level=None, count=None):
    """A muscle made finer (split `level` times, or as often as it needs, then brought down to about `count`
    triangles where the split made more) and its fibres: (positions, triangles, the two numbers each vertex
    carries, log). A muscle in several pieces (the cricothyroid's two parts) has each laid by itself, between
    its own ends: across a piece that held neither end, or one only, no line could be drawn."""
    v, f = weld(v, f)
    if level is None:
        level, count = splits(v, f)
    for _ in range(level):
        v, f = subdivide(v, f)
    if level:
        v = taubin(v, f)
        if count is not None and count < len(f) / 1.1:
            v, f = coarsen(v, f, count)
    label, n = pieces(len(v), f)
    pair = np.zeros((len(v), 2))
    pair[:, 0] = 2.0     # (a crumb too small to lay: belly, the angle 0)
    logs = []
    for k in range(n):
        mine = label == k
        fk = f[mine[f[:, 0]]]
        if len(fk) < 8:
            continue
        index = np.cumsum(mine) - 1
        pair[mine], said = lay_piece(name, v[mine], index[fk], bones)
        logs.append(said)
    head = f"{name}: {level} split{'s' * (level != 1)}, {len(f)} triangles, {len(v)} vertices, "
    log = head + (logs[0] if len(logs) == 1 else f"{len(logs)} pieces: " + "; ".join(logs))
    return v, f, pair.astype(np.float32), log


def annotate(folder, quiet=False, again=False):
    """Lays the fibres on every skeletal muscle in `folder`'s atlas that has none yet; returns how many. With
    `again`, on those that have them too: their meshes are kept as they are (they were made fine when their
    fibres were first laid) and only the fibres laid anew."""
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
        skeletal = lambda st: st.get("tissue") == "muscle" and not NOT_SKELETAL.search(st["node"])
        need = {}   # how often each muscle would be split on its own, and to how many triangles brought down;
        # a pair is split as its coarser side needs, and both brought down to the larger count
        for part in body["parts"]:
            if part["system"] == "muscular" and "fibres" not in part:
                for st, (v, f) in zip(part["structures"], read_part(os.path.join(folder, part["file"]))):
                    if skeletal(st):
                        need[st["node"]] = splits(*weld(v, f))
        for part in body["parts"]:
            if part["system"] != "muscular" or ("fibres" in part and not again):
                continue
            if "fibres" in part:
                need.update({st["node"]: (0, 0) for st in part["structures"]})
            meshes = read_part(os.path.join(folder, part["file"]))
            out, entries = [], []
            for st, (v, f) in zip(part["structures"], meshes):
                st.pop("fibres", None)
                if not skeletal(st):
                    out.append((v, f)); entries.append(None)
                    continue
                pair = [need[st["node"]], need.get(mirror(st["node"]), (0, 0))]
                level, count = max(p[0] for p in pair), max(p[1] for p in pair)
                pos, tri, pair, log = lay(st["node"], v, f, bones, level, count)
                out.append((pos, tri)); entries.append(pair)
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
    args = [a for a in sys.argv[1:] if a != "--again"]
    if len(args) != 1:
        sys.exit(__doc__)
    print(f"{annotate(args[0], again='--again' in sys.argv)} muscles with their fibres laid")
