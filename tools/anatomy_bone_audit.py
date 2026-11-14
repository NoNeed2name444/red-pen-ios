#!/usr/bin/env python3
"""Every bone of a built atlas measured, one by one, both bodies, worst first.

    python3 tools/anatomy_bone_audit.py ATLAS_FOLDER [--out report.md] [--json audit.json] [--body male|female]
                                        [--only REGEX]

What it measures, per bone (a structure whose tissue is bone; the skull's pieces, cut from one scanned shell, are
also measured welded together as one solid, the cranium and the mandible):

- Closed and manifold: open edges (on one triangle), non-manifold edges (on three or more), pieces (connected
  parts), degenerate triangles. The skull's pieces are open where they were cut from the one shell; their open
  edges are left out of the score, and the shell as a whole is checked instead.
- Self-intersections: pairs of triangles that share no corner and cross (an edge of one through the other), and
  the share of triangles caught in one.
- Jaggedness: the share of edges between two triangles more than 60 degrees apart (a crease no bone has at this
  scale), the 99th percentile of those angles, spikes (corners whose triangles' angles there add up to under 220
  degrees, or that stand off the middle of their ring of neighbours by more than 0.6 of their edges' length), and
  the surface's high-frequency noise: how far ten rounds of Taubin smoothing move it (RMS), against its median
  edge.
- Left and right: each bone of a pair against the mirror image of its partner, mirrored about the body's plane
  of symmetry (fitted through the middles of the bones on the midline: vertebrae, sacrum, coccyx, sternum, the
  skull's midline bones): the Hausdorff and mean distance as they lie (placement), then after the mirrored partner
  is laid on it rigidly (shape), and the ratio of their surfaces. A midline bone against its own mirror image.
- Long bones' straightness: the centreline of the shaft (the middles of cross-sections square to its long axis,
  15 to 85% of its length) or, for a curved bone (a rib, the clavicle), of the whole bone (the middles of bands of
  equal distance over the surface from one end); its bow (the furthest the centreline strays from the chord, and
  which way), and its waviness: how far it strays from a smooth curve (a parabola for a shaft, a quartic for a
  curved bone), which no real bone does by more than about a millimetre.
- Pieces outside the skin (share of the bone's surface outside the skin's solid, and how far) and inside other
  bones (share of its surface more than 0.5 mm deep in another bone's solid, the worst such bone and how deep).
- Joints: for each articulation the atlas should show (Gray's Anatomy, 1918, the articulations; public domain),
  the closest approach of the two bones' surfaces and how deep either runs into the other, against the gap a
  joint of that kind leaves between dry bones (its cartilage and disc), flagged when wider or overlapping.

Each bone gets a score, the sum of its flags each capped, so the report lists the worst first; missing standard
bones are listed by docs/sciences/bones-206.md (tools/anatomy_bone_fix.py adds what it can).

Reads: sys.path has tools/; anatomy_fibres.read_part gives a part's meshes (metres; x the body's left, y up,
z forward).
"""
import argparse
import json
import math
import os
import re
import sys
import time

import numpy as np
import scipy.sparse as sp
from scipy.sparse.csgraph import connected_components, dijkstra
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from anatomy_fibres import read_part  # noqa: E402

SKELETAL = ("skull", "sternum", "ribs", "shoulders", "arms", "vertebral-column", "pelvis", "legs", "hyoid")
SHARP = 60.0            # degrees between two triangles' normals: a crease
SPIKE_ANGLE = 220.0     # degrees: a corner whose triangles' angles add up to less is a spike
SPIKE_LIFT = 0.6        # or one standing off its ring's middle by this share of its edges
DEEP = 0.0005           # m: a point counted inside another bone only past this depth (the grids' grain)

# Long bones measured along their shaft; curved ones along the whole bone. Each with the bow a sound bone of the
# kind shows, as a share of the shaft's chord (Egol et al. 2004, the femur's anterior bow, radius of curvature
# about 1.2 m; Schemitsch and Richards 1992, the radius's lateral bow, about 6% of its length; the rest nearly
# straight); a bow beyond it, or any waviness, is what reads as "bent".
SHAFT = [  # (pattern, kind, most bow as a share of the chord)
    (r"femur", "femur", 0.05),
    (r"tibia", "tibia", 0.025),
    (r"fibula", "fibula", 0.03),
    (r"humerus", "humerus", 0.025),
    (r"radius", "radius", 0.07),
    (r"ulna", "ulna", 0.035),
    (r"metacarpal", "metacarpal", 0.05),
    (r"metatarsal", "metatarsal", 0.05),
    (r"proximal_phalanx|middle_phalanx", "phalanx", 0.06),
]
CURVED = [(r"rib_\d+", "rib"), (r"clavicle", "clavicle")]
WAVY = 0.0015           # m: a centreline straying further than this from its smooth curve is wavy
AXIAL = ("skull", "sternum", "ribs", "shoulders", "pelvis", "vertebral-column", "hyoid")   # where a pair's placement
# should mirror (the limbs are posed each its own way)

# Articulations, by name patterns ({S} the side, L or R). Each: name, bone A, bone B, the closest approach a
# dry-bone model of that joint shows (min, max, m). The ribs' and vertebrae's are added in joints_of().
FINGERS = ("thumb", "index_finger", "middle_finger", "ring_finger", "little_finger")
TOES = ("great_toe", "second_toe", "third_toe", "fourth_toe", "little_toe")
ORD = ("first", "second", "third", "fourth", "fifth")
JOINTS = [
    ("glenohumeral", r"scapula_{S}$", r"humerus_{S}$", (0.0005, 0.008)),
    ("acromioclavicular", r"clavicle_{S}$", r"scapula_{S}$", (0.0, 0.006)),
    ("sternoclavicular", r"clavicle_{S}$", r"(sternum|manubrium)$", (0.0, 0.010)),
    ("humeroulnar", r"humerus_{S}$", r"ulna_{S}$", (0.0, 0.005)),
    ("humeroradial", r"humerus_{S}$", r"radius_{S}$", (0.0, 0.006)),
    ("radioulnar", r"radius_{S}$", r"ulna_{S}$", (0.0, 0.004)),
    ("radiocarpal", r"radius_{S}$", r"(carpal_bones|scaphoid|lunate)_{S}$", (0.0, 0.005)),
    ("hip", r"(ilium_compact_bone|ischium_compact_bone|pubis_compact_bone|hip)_{S}$", r"femur_{S}$", (0.0005, 0.007)),
    ("knee (tibiofemoral)", r"femur_{S}$", r"tibia_{S}$", (0.001, 0.010)),
    ("knee (patellofemoral)", r"femur_{S}$", r"patella_{S}$", (0.0005, 0.008)),
    ("tibiofibular", r"tibia_{S}$", r"fibula_{S}$", (0.0, 0.005)),
    ("ankle (tibia)", r"tibia_{S}$", r"talus_{S}$", (0.0, 0.005)),
    ("ankle (fibula)", r"fibula_{S}$", r"talus_{S}$", (0.0, 0.005)),
    ("subtalar", r"talus_{S}$", r"calcaneus_{S}$", (0.0, 0.004)),
    ("talonavicular", r"talus_{S}$", r"navicular_{S}$", (0.0, 0.004)),
    ("calcaneocuboid", r"calcaneus_{S}$", r"cuboid_{S}$", (0.0, 0.004)),
    ("cuneonavicular (medial)", r"navicular_{S}$", r"medial_cuneiform_{S}$", (0.0, 0.004)),
    ("cuneonavicular (intermediate)", r"navicular_{S}$", r"intermediate_cuneiform_{S}$", (0.0, 0.004)),
    ("cuneonavicular (lateral)", r"navicular_{S}$", r"lateral_cuneiform_{S}$", (0.0, 0.004)),
    ("tarsometatarsal 1", r"medial_cuneiform_{S}$", r"first_metatarsal_{S}$", (0.0, 0.004)),
    ("tarsometatarsal 2", r"intermediate_cuneiform_{S}$", r"second_metatarsal_{S}$", (0.0, 0.004)),
    ("tarsometatarsal 3", r"lateral_cuneiform_{S}$", r"third_metatarsal_{S}$", (0.0, 0.004)),
    ("tarsometatarsal 4", r"cuboid_{S}$", r"fourth_metatarsal_{S}$", (0.0, 0.004)),
    ("tarsometatarsal 5", r"cuboid_{S}$", r"fifth_metatarsal_{S}$", (0.0, 0.004)),
    ("sacroiliac", r"sacrum$", r"(ilium_compact_bone|hip)_{S}$", (0.0005, 0.005)),
    ("sacrococcygeal", r"sacrum$", r"coccyx$", (0.0, 0.004)),
    ("atlanto-occipital", r"cervical_vertebra_1$", r"occipital_bone$", (0.0005, 0.006)),
    ("temporomandibular", r"mandible$", r"temporal_bone_{S}$", (0.001, 0.008)),
]
for k, ft in enumerate(FINGERS):
    JOINTS.append((f"carpometacarpal {k + 1}", r"(carpal_bones|trapezium|trapezoid|capitate|hamate)_{S}$",
                   rf"{ORD[k]}_metacarpal_{{S}}$", (0.0, 0.004)))
    JOINTS.append((f"metacarpophalangeal {k + 1}", rf"{ORD[k]}_metacarpal_{{S}}$", rf"proximal_phalanx_of_{ft}_{{S}}$",
                   (0.0, 0.004)))
    if ft == "thumb":
        JOINTS.append(("interphalangeal (thumb)", r"proximal_phalanx_of_thumb_{S}$", r"distal_phalanx_of_thumb_{S}$",
                       (0.0, 0.003)))
    else:
        JOINTS.append((f"proximal interphalangeal ({ft.split('_')[0]})", rf"proximal_phalanx_of_{ft}_{{S}}$",
                       rf"middle_phalanx_of_{ft}_{{S}}$", (0.0, 0.003)))
        JOINTS.append((f"distal interphalangeal ({ft.split('_')[0]})", rf"middle_phalanx_of_{ft}_{{S}}$",
                       rf"distal_phalanx_of_{ft}_{{S}}$", (0.0, 0.003)))
for k, toe in enumerate(TOES):
    JOINTS.append((f"metatarsophalangeal {k + 1}", rf"{ORD[k]}_metatarsal_{{S}}$", rf"proximal_phalanx_of_{toe}_{{S}}$",
                   (0.0, 0.004)))
    if toe == "great_toe":
        JOINTS.append(("interphalangeal (great toe)", r"proximal_phalanx_of_great_toe_{S}$",
                       r"distal_phalanx_of_great_toe_{S}$", (0.0, 0.003)))
    else:
        JOINTS.append((f"proximal interphalangeal ({toe.split('_')[0]} toe)", rf"proximal_phalanx_of_{toe}_{{S}}$",
                       rf"middle_phalanx_of_{toe}_{{S}}$", (0.0, 0.003)))
        JOINTS.append((f"distal interphalangeal ({toe.split('_')[0]} toe)", rf"middle_phalanx_of_{toe}_{{S}}$",
                       rf"distal_phalanx_of_{toe}_{{S}}$", (0.0, 0.003)))
# the carpal bones, when the carpus is split into its eight (tools/anatomy_bone_fix.py)
for a, b in (("scaphoid", "lunate"), ("lunate", "triquetrum"), ("triquetrum", "pisiform"), ("scaphoid", "trapezium"),
             ("scaphoid", "trapezoid"), ("scaphoid", "capitate"), ("lunate", "capitate"), ("triquetrum", "hamate"),
             ("trapezium", "trapezoid"), ("trapezoid", "capitate"), ("capitate", "hamate"), ("lunate", "radius")):
    JOINTS.append((f"intercarpal ({a}, {b})", rf"{a}_{{S}}$", rf"{b}_{{S}}$", (0.0, 0.003)))


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# MARK: reading

class Bone:
    __slots__ = ("body", "part", "node", "label", "uberon", "tissue", "v", "f", "index", "group", "cut")

    def __init__(self, body, part, st, v, f, index):
        self.body, self.part, self.node = body, part, st["node"]
        self.label, self.uberon, self.tissue = st.get("label", ""), st.get("uberon"), st.get("tissue")
        self.v, self.f, self.index = np.asarray(v, np.float64), np.asarray(f, np.int64), index
        self.group = None          # the solid it belongs to, for the inside tests (the skull's pieces, a femur and its cartilage)
        self.cut = part == "skull"  # cut from one shell: open edges are expected

    @property
    def side(self):
        m = re.search(r"_([LR])$", self.node)
        return m.group(1) if m else None

    @property
    def short(self):
        return re.sub(r"^(VH_[MF]_|TS_|NLM_)", "", self.node)


def load(folder, only_body=None):
    """{body id: (bones, others)}: the bones of each body, and every other structure by part, for the checks that
    need them (the skin, the knee's cartilage)."""
    manifest = json.load(open(os.path.join(folder, "anatomy.json")))
    out = {}
    for body in manifest["bodies"]:
        if only_body and body["id"] != only_body:
            continue
        bones, others = [], {}
        for part in body["parts"]:
            skeletal = part.get("system") == "skeletal" or part["id"] in SKELETAL
            want = skeletal or part["id"] == "skin"
            if not want:
                continue
            meshes = read_part(os.path.join(folder, part["file"]))
            for i, (st, (v, f)) in enumerate(zip(part["structures"], meshes)):
                if skeletal and st.get("tissue") == "bone":
                    bones.append(Bone(body["id"], part["id"], st, v, f, i))
                else:
                    others.setdefault(part["id"], []).append((st, np.asarray(v, np.float64), np.asarray(f, np.int64)))
        out[body["id"]] = (bones, others)
    return out


# MARK: mesh basics

def face_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    a = np.linalg.norm(n, axis=1)
    return n / np.maximum(a, 1e-30)[:, None], a / 2


def vertex_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    out = np.zeros_like(v)
    for k in range(3):
        np.add.at(out, f[:, k], n)
    return out / np.maximum(np.linalg.norm(out, axis=1), 1e-30)[:, None]


def edge_table(f):
    """Each undirected edge once (sorted pair), how many triangles hold it, and for edges on exactly two, those two."""
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    tri = np.tile(np.arange(len(f)), 3)
    key = e[:, 0] * (int(e.max()) + 1 if len(e) else 1) + e[:, 1]
    order = np.argsort(key, kind="stable")
    key, tri, e = key[order], tri[order], e[order]
    uniq, start, count = np.unique(key, return_index=True, return_counts=True)
    two = count == 2
    pairs = np.stack([tri[start[two]], tri[start[two] + 1]], 1)
    return e[start], count, pairs


def adjacency(n, f):
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    e = np.unique(e, axis=0)
    a = sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    return (a + a.T).tocsr()


def taubin(v, f, rounds=10, lam=0.5, mu=-0.53, hold=None):
    """Taubin's smoothing (lambda then mu, so the surface keeps its size); points in `hold` stay."""
    adj = adjacency(len(v), f)
    deg = np.asarray(adj.sum(1)).ravel()
    deg[deg == 0] = 1
    v = v.copy()
    for _ in range(rounds):
        for k in (lam, mu):
            step = k * (adj @ v / deg[:, None] - v)
            if hold is not None:
                step[hold] = 0
            v = v + step
    return v


def surface_samples(v, f, h, seed=7):
    """Points over the surface about h apart: the corners, and in each triangle as many more as its area holds
    squares of side h, spread at random (seeded, so the same mesh always gives the same points)."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    n = np.floor(area / (h * h) + np.random.default_rng(seed).random(len(f))).astype(int)
    t = np.repeat(np.arange(len(f)), n)
    rng = np.random.default_rng(seed + 1)
    r1, r2 = rng.random(len(t)), rng.random(len(t))
    s1 = np.sqrt(r1)
    w0, w1 = 1 - s1, s1 * (1 - r2)
    w2 = 1 - w0 - w1
    pts = w0[:, None] * a[t] + w1[:, None] * b[t] + w2[:, None] * c[t]
    return np.concatenate([v[np.unique(f)], pts])


def components(n, f):
    if len(f) == 0:
        return 0, np.zeros(n, int)
    rows = np.concatenate([f[:, 0], f[:, 1], f[:, 2]])
    cols = np.concatenate([f[:, 1], f[:, 2], f[:, 0]])
    a = sp.coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(n, n))
    used = np.zeros(n, bool)
    used[f.ravel()] = True
    k, lab = connected_components(a, directed=False)
    return len(np.unique(lab[used])), lab


def weld(v, f, tol=1e-6):
    key = np.round(v / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    f = inv.reshape(-1)[f]
    f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
    return v[first], f


# MARK: closed and manifold

def topology(v, f):
    e, count, _ = edge_table(f)
    _, area = face_normals(v, f)
    pieces, _ = components(len(v), f)
    V = len(np.unique(f))
    chi = V - len(e) + len(f)
    return dict(vertices=int(len(v)), triangles=int(len(f)), open=int((count == 1).sum()),
                nonmanifold=int((count > 2).sum()), pieces=int(pieces), degenerate=int((area < 1e-12).sum()),
                euler=int(chi))


# MARK: self-intersections

def _segments_hit(p0, p1, a, b, c, eps=1e-12):
    """Whether each segment p0->p1 crosses triangle (a, b, c) strictly inside (Moller-Trumbore)."""
    d = p1 - p0
    e1, e2 = b - a, c - a
    pv = np.cross(d, e2)
    det = (e1 * pv).sum(1)
    ok = np.abs(det) > eps
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    tv = p0 - a
    u = (tv * pv).sum(1) * inv
    qv = np.cross(tv, e1)
    w = (d * qv).sum(1) * inv
    t = (e2 * qv).sum(1) * inv
    m = 1e-9
    return ok & (u > m) & (w > m) & (u + w < 1 - m) & (t > m) & (t < 1 - m)


def self_intersections(v, f, cap=400000):
    """Pairs of triangles sharing no corner that cross each other; (number of pairs, triangles caught)."""
    if len(f) < 4:
        return 0, np.zeros(0, int)
    tri = v[f]
    lo, hi = tri.min(1), tri.max(1)
    size = np.percentile((hi - lo).max(1), 95) + 1e-9
    origin = lo.min(0)
    a0 = np.floor((lo - origin) / size).astype(np.int64)
    a1 = np.floor((hi - origin) / size).astype(np.int64)
    span = a1 - a0 + 1
    cnt = span.prod(1)
    keys, owners = [], []
    for m in np.unique(cnt):
        t = np.flatnonzero(cnt == m)
        sx, sy, sz = span[t, 0], span[t, 1], span[t, 2]
        for k in range(int(m)):
            # each triangle's k-th cell within its own box of cells
            ix = k % sx; iy = (k // sx) % sy; iz = k // (sx * sy)
            ok = iz < sz
            tt = t[ok]
            c = a0[tt] + np.stack([ix[ok], iy[ok], iz[ok]], 1)
            keys.append((c[:, 0] * 73856093) ^ (c[:, 1] * 19349663) ^ (c[:, 2] * 83492791))
            owners.append(tt)
    keys = np.concatenate(keys)
    owners = np.concatenate(owners)
    order = np.argsort(keys, kind="stable")
    keys, owners = keys[order], owners[order]
    _, start, count = np.unique(keys, return_index=True, return_counts=True)
    I, J = [], []
    for c in np.unique(count):
        if c < 2:
            continue
        s = start[count == c]
        ii, jj = np.triu_indices(int(c), 1)
        I.append(owners[s[:, None] + ii[None]].ravel())
        J.append(owners[s[:, None] + jj[None]].ravel())
    if not I:
        return 0, np.zeros(0, int)
    I, J = np.concatenate(I), np.concatenate(J)
    a, b = np.minimum(I, J), np.maximum(I, J)
    pair = np.unique(a.astype(np.int64) * len(f) + b)
    a, b = pair // len(f), pair % len(f)
    over = np.all((lo[a] <= hi[b]) & (lo[b] <= hi[a]), 1)
    a, b = a[over], b[over]
    shared = np.zeros(len(a), bool)
    for i in range(3):
        for j in range(3):
            shared |= f[a, i] == f[b, j]
    a, b = a[~shared], b[~shared]
    hit = np.zeros(len(a), bool)
    for s in range(0, len(a), cap):
        A, B = a[s:s + cap], b[s:s + cap]
        h = np.zeros(len(A), bool)
        for (P, Q) in ((A, B), (B, A)):
            for i in range(3):
                h |= _segments_hit(v[f[P, i]], v[f[P, (i + 1) % 3]], v[f[Q, 0]], v[f[Q, 1]], v[f[Q, 2]])
        hit[s:s + cap] = h
    caught = np.unique(np.concatenate([a[hit], b[hit]]))
    return int(hit.sum()), caught


# MARK: jaggedness

def jaggedness(v, f):
    fn, area = face_normals(v, f)
    _, count, pairs = edge_table(f)
    cos = np.clip((fn[pairs[:, 0]] * fn[pairs[:, 1]]).sum(1), -1, 1)
    ang = np.degrees(np.arccos(cos))
    # each corner's angle in each triangle
    angsum = np.zeros(len(v))
    for k in range(3):
        p, q, r = v[f[:, k]], v[f[:, (k + 1) % 3]], v[f[:, (k + 2) % 3]]
        x, y = q - p, r - p
        c = (x * y).sum(1) / np.maximum(np.linalg.norm(x, axis=1) * np.linalg.norm(y, axis=1), 1e-30)
        np.add.at(angsum, f[:, k], np.degrees(np.arccos(np.clip(c, -1, 1))))
    e, cnt, _ = edge_table(f)
    border = np.zeros(len(v), bool)
    border[e[cnt != 2].ravel()] = True
    adj = adjacency(len(v), f)
    deg = np.asarray(adj.sum(1)).ravel()
    used = deg > 0
    ring = adj @ v / np.maximum(deg, 1)[:, None]
    el = np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)
    mean_edge = np.bincount(e.ravel(), weights=np.repeat(el, 2), minlength=len(v)) / np.maximum(
        np.bincount(e.ravel(), minlength=len(v)), 1)
    vn = vertex_normals(v, f)
    lift = ((v - ring) * vn).sum(1) / np.maximum(mean_edge, 1e-12)
    inner = used & ~border
    spikes_out = inner & ((angsum < SPIKE_ANGLE) | (np.abs(lift) > SPIKE_LIFT)) & (lift > 0)
    spikes_in = inner & ((angsum < SPIKE_ANGLE) | (np.abs(lift) > SPIKE_LIFT)) & (lift <= 0)
    sm = taubin(v, f, rounds=10)
    # only the move along the surface's normal: smoothing also slides points along the surface, which is no noise
    off = np.abs(((sm - v) * vn).sum(1))
    noise = float(np.sqrt((off[used] ** 2).mean())) if used.any() else 0.0
    med_edge = float(np.median(el)) if len(el) else 0.0
    return dict(sharp=float((ang > SHARP).mean()) if len(ang) else 0.0,
                sharp90=float((ang > 90).mean()) if len(ang) else 0.0,
                p99_angle=float(np.percentile(ang, 99)) if len(ang) else 0.0,
                spikes=int(spikes_out.sum() + spikes_in.sum()), spikes_out=int(spikes_out.sum()),
                spike_share=float((spikes_out.sum() + spikes_in.sum()) / max(1, inner.sum())),
                noise_mm=noise * 1000, median_edge_mm=med_edge * 1000,
                noise_rel=noise / med_edge if med_edge > 0 else 0.0)


# MARK: solids (inside tests)

class Solids:
    """Solids made when first asked for, the larger ones forgotten first when too many are held."""

    def __init__(self, meshes, keep=40):
        self.meshes, self.cache, self.keep = meshes, {}, keep
        self.box = {k: (v.min(0), v.max(0)) for k, (v, f) in meshes.items()}

    def near(self, lo, hi, pad=0.002):
        return [k for k, (a, b) in self.box.items() if np.all(a - pad <= hi) and np.all(lo <= b + pad)]

    def get(self, key):
        if key not in self.meshes:
            return None
        if key not in self.cache:
            if len(self.cache) >= self.keep:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = Solid(*self.meshes[key])
        return self.cache[key]


class Solid:
    """A closed mesh's inside on a grid (ray parity along each axis, the three voting), and its surface for
    distances."""

    def __init__(self, v, f, h=None, pad=3):
        self.v, self.f = v, f
        ext = v.max(0) - v.min(0) + 0.002
        if h is None:
            h = float(np.clip((ext.prod() / 1.2e7) ** (1 / 3), 0.0003, 0.003))
        self.h = h
        self.deep = max(DEEP, 0.75 * h)
        self.lo = v.min(0) - pad * h
        self.n = np.ceil((v.max(0) + pad * h - self.lo) / h).astype(int) + 1
        votes = np.zeros(tuple(self.n), np.uint8)
        for axis in range(3):
            votes += self._parity(axis)
        self.inside = votes >= 2
        self.surface = cKDTree(surface_samples(v, f, h * 0.7))

    def _parity(self, axis):
        v, f, h, lo, n = self.v, self.f, self.h, self.lo, self.n
        a1, a2 = [k for k in range(3) if k != axis]
        jit = np.array([0.1234, 0.2671, 0.3719])
        tri = v[f]
        P, Q, R = tri[:, 0], tri[:, 1], tri[:, 2]
        tlo = np.floor((tri[:, :, [a1, a2]].min(1) - lo[[a1, a2]]) / h - jit[[a1, a2]]).astype(int)
        thi = np.floor((tri[:, :, [a1, a2]].max(1) - lo[[a1, a2]]) / h - jit[[a1, a2]]).astype(int) + 1
        cnt = (thi - tlo + 1).prod(1)
        acc = np.zeros(tuple(n), np.int32)
        flat = acc.reshape(-1)
        strides = np.array(acc.strides) // acc.itemsize
        for m in np.unique(cnt):
            t = np.flatnonzero(cnt == m)
            w = thi[t, 0] - tlo[t, 0] + 1
            k = np.arange(m)
            T = np.repeat(t, m)
            K = np.tile(k, len(t))
            W = np.repeat(w, m)
            i = tlo[T, 0] + K % W
            j = tlo[T, 1] + K // W
            ok = (j <= thi[T, 1])
            T, i, j = T[ok], i[ok], j[ok]
            x = lo[a1] + (i + jit[a1]) * h
            y = lo[a2] + (j + jit[a2]) * h
            p, q, r = P[T], Q[T], R[T]
            d1 = (q[:, a1] - p[:, a1]) * (y - p[:, a2]) - (q[:, a2] - p[:, a2]) * (x - p[:, a1])
            d2 = (r[:, a1] - q[:, a1]) * (y - q[:, a2]) - (r[:, a2] - q[:, a2]) * (x - q[:, a1])
            d3 = (p[:, a1] - r[:, a1]) * (y - r[:, a2]) - (p[:, a2] - r[:, a2]) * (x - r[:, a1])
            ins = ((d1 > 0) & (d2 > 0) & (d3 > 0)) | ((d1 < 0) & (d2 < 0) & (d3 < 0))
            T, i, j, x, y = T[ins], i[ins], j[ins], x[ins], y[ins]
            if not len(T):
                continue
            p, q, r = P[T], Q[T], R[T]
            nrm = np.cross(q - p, r - p)
            ok = np.abs(nrm[:, axis]) > 1e-18
            T, i, j, x, y, p, nrm = T[ok], i[ok], j[ok], x[ok], y[ok], p[ok], nrm[ok]
            z = p[:, axis] - ((x - p[:, a1]) * nrm[:, a1] + (y - p[:, a2]) * nrm[:, a2]) / nrm[:, axis]
            kz = np.ceil((z - lo[axis]) / h).astype(int)
            kz = np.clip(kz, 0, n[axis] - 1)
            idx = np.zeros((len(T), 3), int)
            idx[:, a1], idx[:, a2], idx[:, axis] = i, j, kz
            good = (i >= 0) & (i < n[a1]) & (j >= 0) & (j < n[a2])
            np.add.at(flat, (idx[good] * strides).sum(1), 1)
        par = np.cumsum(acc, axis=axis) % 2
        return par.astype(np.uint8)

    def contains(self, q):
        k = np.round((q - self.lo) / self.h).astype(int)
        ok = np.all((k >= 0) & (k < self.n), 1)
        out = np.zeros(len(q), bool)
        kk = k[ok]
        out[ok] = self.inside[kk[:, 0], kk[:, 1], kk[:, 2]]
        return out

    def depth(self, q):
        return self.surface.query(q)[0]


def winding_number(q, p, f):
    """The generalized winding number (Jacobson et al. 2013), exact, for the few points where a grid's answer
    is too coarse."""
    w = np.zeros(len(q))
    for s in range(0, len(q), 128):
        qq = q[s:s + 128]
        for i in range(0, len(f), 4000):
            a, b, c = (p[f[i:i + 4000, j]][None] - qq[:, None] for j in range(3))
            la, lb, lc = (np.linalg.norm(x, axis=2) for x in (a, b, c))
            det = np.einsum("qfk,qfk->qf", a, np.cross(b, c))
            den = (la * lb * lc + np.einsum("qfk,qfk->qf", a, b) * lc + np.einsum("qfk,qfk->qf", b, c) * la
                   + np.einsum("qfk,qfk->qf", c, a) * lb)
            w[s:s + 128] += (2 * np.arctan2(det, den)).sum(1) / (4 * np.pi)
    return w


# MARK: the body's plane of symmetry

MIDLINE = re.compile(r"(vertebra|sacrum|coccyx|sternum|manubrium|frontal_bone|occipital_bone|sphenoid_bone|vomer|"
                     r"ethmoid_bone|mandible|hyoid)$")


def midplane(bones):
    """The plane x = a + b y + c z through the middles of the midline bones (least squares): returns a point on
    it and its unit normal (toward the body's left)."""
    C = []
    for b in bones:
        if MIDLINE.search(b.node):
            s = surface_samples(b.v, b.f, 0.002)
            C.append(np.median(s, 0))
    C = np.array(C)
    A = np.c_[np.ones(len(C)), C[:, 1], C[:, 2]]
    coef, *_ = np.linalg.lstsq(A, C[:, 0], rcond=None)
    n = np.array([1.0, -coef[1], -coef[2]])
    n /= np.linalg.norm(n)
    p0 = np.array([coef[0], 0.0, 0.0])
    return p0, n


def mirror(v, plane):
    p0, n = plane
    d = (v - p0) @ n
    return v - 2 * d[:, None] * n[None]


def rigid_icp(src, dst_tree, dst, rounds=30, trim=0.9):
    """src laid on dst rigidly (no scale): returns the moved src."""
    s = src - src.mean(0) + dst.mean(0)
    for _ in range(rounds):
        d, j = dst_tree.query(s)
        keep = d <= np.quantile(d, trim)
        A, B = s[keep], dst[j[keep]]
        ca, cb = A.mean(0), B.mean(0)
        U, S, Vt = np.linalg.svd((A - ca).T @ (B - cb))
        D = np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))])
        R = Vt.T @ D @ U.T
        s = (s - ca) @ R.T + cb
    return s


def distances(a, b, ta=None, tb=None):
    """Symmetric surface distances between point sets a and b: (Hausdorff, mean of the two means, 95th pct)."""
    ta = ta or cKDTree(a)
    tb = tb or cKDTree(b)
    dab = tb.query(a)[0]
    dba = ta.query(b)[0]
    return (float(max(dab.max(), dba.max())), float((dab.mean() + dba.mean()) / 2),
            float(max(np.percentile(dab, 95), np.percentile(dba, 95))))


def partner_of(node):
    if node.endswith("_L"):
        return node[:-2] + "_R"
    if node.endswith("_R"):
        return node[:-2] + "_L"
    return None


def symmetry(b, other, plane, samples):
    """b against its partner's mirror image (or its own, on the midline)."""
    A = samples[b.node]
    B = mirror(samples[other.node] if other is not None else samples[b.node], plane)
    ta, tb = cKDTree(A), cKDTree(B)
    place = distances(A, B, ta, tb)
    moved = rigid_icp(B, ta, A)
    shape = distances(A, moved, ta, cKDTree(moved))
    diag = float(np.linalg.norm(A.max(0) - A.min(0)))
    _, aa = face_normals(b.v, b.f)
    if other is not None:
        _, ab = face_normals(other.v, other.f)
        ratio = float(aa.sum() / max(ab.sum(), 1e-12))
    else:
        ratio = 1.0
    return dict(partner=other.node if other is not None else "(itself)", place_hd_mm=place[0] * 1000,
                place_mean_mm=place[1] * 1000, shape_hd_mm=shape[0] * 1000, shape_mean_mm=shape[1] * 1000,
                shape_p95_mm=shape[2] * 1000, area_ratio=ratio, diag_mm=diag * 1000)


# MARK: straightness

def pca_axis(p):
    c = p.mean(0)
    U, S, Vt = np.linalg.svd(p - c, full_matrices=False)
    return c, Vt[0]


def slice_centres(v, f, c, axis, ts):
    """The middle of the bone's outline in planes square to `axis` at the given positions (m along it from c)."""
    out = []
    d0 = (v - c) @ axis
    for t in ts:
        d = d0 - t
        s = np.sign(d[f])
        cross = (s.min(1) < 0) & (s.max(1) > 0)
        F = f[cross]
        if not len(F):
            out.append(np.full(3, np.nan))
            continue
        P = v[F]
        D = d[F]
        pts = []
        for i, j in ((0, 1), (1, 2), (2, 0)):
            m = np.sign(D[:, i]) != np.sign(D[:, j])
            w = D[:, i] / np.where(m, D[:, i] - D[:, j], 1)
            q = P[:, i] + w[:, None] * (P[:, j] - P[:, i])
            pts.append(np.where(m[:, None], q, np.nan))
        pts = np.stack(pts, 1)   # (n, 3 edges, 3)
        segs = []
        for row in pts:
            r = row[~np.isnan(row[:, 0])]
            if len(r) >= 2:
                segs.append(r[:2])
        if not segs:
            out.append(np.full(3, np.nan))
            continue
        segs = np.array(segs)
        L = np.linalg.norm(segs[:, 1] - segs[:, 0], axis=1)
        mid = segs.mean(1)
        # keep the largest loop near the axis: the outline whose points lie nearest the slice's middle
        out.append((mid * L[:, None]).sum(0) / max(L.sum(), 1e-12))
    return np.array(out)


def describe_direction(u, side):
    """A deviation's direction in the body's words."""
    names = []
    x, y, z = u
    lateral = (x > 0) if side == "L" else (x < 0) if side == "R" else None
    comps = sorted([(abs(x), "x"), (abs(y), "y"), (abs(z), "z")], reverse=True)
    for mag, k in comps:
        if mag < 0.35:
            continue
        if k == "x":
            names.append("lateral" if lateral else "medial" if lateral is not None else ("left" if x > 0 else "right"))
        elif k == "y":
            names.append("up" if y > 0 else "down")
        else:
            names.append("forward" if z > 0 else "back")
    return "-".join(names) or "?"


def shaft_straightness(b, most_bow):
    v, f = b.v, b.f
    s = surface_samples(v, f, 0.002)
    c, ax = pca_axis(s)
    t = (s - c) @ ax
    lo, hi = t.min(), t.max()
    L = hi - lo
    ts = lo + L * np.linspace(0.15, 0.85, 15)
    C = slice_centres(v, f, c, ax, ts)
    ok = ~np.isnan(C[:, 0])
    if ok.sum() < 6:
        return None
    C, tt = C[ok], np.linspace(0.15, 0.85, 15)[ok]
    chord = C[-1] - C[0]
    cl = np.linalg.norm(chord)
    u = chord / max(cl, 1e-12)
    dev = (C - C[0]) - np.outer((C - C[0]) @ u, u)
    dist = np.linalg.norm(dev, axis=1)
    k = int(np.argmax(dist))
    bow = float(dist[k])
    way = describe_direction(dev[k] / max(bow, 1e-12), b.side)
    # waviness: off a parabola through the centres
    V = np.vander(tt, 3)
    coef, *_ = np.linalg.lstsq(V, C, rcond=None)
    res = np.linalg.norm(C - V @ coef, axis=1)
    return dict(method="shaft", length_mm=float(L * 1000), chord_mm=float(cl * 1000), bow_mm=bow * 1000,
                bow_share=bow / max(cl, 1e-12), bow_way=way, most_bow=most_bow,
                wave_mm=float(res.max() * 1000))


def geodesic_ends(v, f):
    e = np.unique(np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1), axis=0)
    w = np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)
    g = sp.coo_matrix((w, (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr()
    g = g + g.T
    start = int(np.argmax(np.linalg.norm(v - v.mean(0), axis=1)))
    d0 = dijkstra(g, indices=start, directed=False)
    d0[~np.isfinite(d0)] = -1
    a = int(np.argmax(d0))
    da = dijkstra(g, indices=a, directed=False)
    da[~np.isfinite(da)] = np.nan
    return a, da


def curve_straightness(b):
    v, f = b.v, b.f
    a, da = geodesic_ends(v, f)
    total = np.nanmax(da)
    if not np.isfinite(total) or total <= 0:
        return None
    _, area = face_normals(v, f)
    va = np.zeros(len(v))
    for k in range(3):
        np.add.at(va, f[:, k], area / 3)
    edges = np.linspace(0.05, 0.95, 31)
    C, T = [], []
    for lo_, hi_ in zip(edges[:-1], edges[1:]):
        m = (da >= lo_ * total) & (da < hi_ * total)
        if va[m].sum() <= 0:
            continue
        C.append((v[m] * va[m, None]).sum(0) / va[m].sum())
        T.append((lo_ + hi_) / 2)
    if len(C) < 8:
        return None
    C, T = np.array(C), np.array(T)
    V = np.vander(T, 5)
    coef, *_ = np.linalg.lstsq(V, C, rcond=None)
    res = np.linalg.norm(C - V @ coef, axis=1)
    seg = np.linalg.norm(np.diff(C, axis=0), axis=1).sum()
    chord = np.linalg.norm(C[-1] - C[0])
    return dict(method="curve", length_mm=float(seg * 1000 / 0.9), chord_mm=float(chord * 1000),
                wave_mm=float(res.max() * 1000), bow_mm=None, bow_share=None, bow_way=None, most_bow=None)


def straightness(b):
    for pat, kind, most in SHAFT:
        if re.search(pat, b.node):
            r = shaft_straightness(b, most)
            if r:
                r["kind"] = kind
            return r
    for pat, kind in CURVED:
        if re.search(pat, b.node):
            r = curve_straightness(b)
            if r:
                r["kind"] = kind
            return r
    return None


# MARK: joints

def joints_of(bones):
    """The articulations to check in this body: (name, bone a, bone b, (min, max) m)."""
    by = {b.node: b for b in bones}
    out = []

    def find(pat):
        r = re.compile(pat)
        return [b for b in bones if r.search(b.node)]

    for name, pa, pb, rng in JOINTS:
        for side in ("L", "R"):
            A, B = find(pa.replace("{S}", side)), find(pb.replace("{S}", side))
            if not A or not B:
                continue
            # a joint with several pieces on one side (the male hip bone's three) takes the nearest
            out.append((f"{name} {side}" if "{S}" in pa + pb else name, A, B, rng))
            if "{S}" not in pa + pb:
                break
    # the column: each vertebra on the next (the facets; their bodies stand a disc apart)
    col = [b for b in bones if re.search(r"(cervical|thoracic|lumbar)_vertebra_\d+$", b.node)]
    rank = {"cervical": 0, "thoracic": 1, "lumbar": 2}
    col.sort(key=lambda b: (rank[re.search(r"(cervical|thoracic|lumbar)", b.node).group(1)],
                            int(re.search(r"(\d+)$", b.node).group(1))))
    for x, y in zip(col[:-1], col[1:]):
        out.append((f"{x.short} on {y.short}", [x], [y], (0.0, 0.006)))
    if col:
        sac = [b for b in bones if b.node.endswith("sacrum")]
        if sac:
            out.append((f"{col[-1].short} on the sacrum", [col[-1]], sac, (0.0, 0.006)))
    # each rib's head on its vertebra (the first, tenth to twelfth on their own; the rest on two)
    thor = {int(re.search(r"(\d+)$", b.node).group(1)): b for b in col if "thoracic" in b.node}
    for b in bones:
        m = re.search(r"rib_(\d+)_([LR])$", b.node)
        if m and int(m.group(1)) in thor:
            k = int(m.group(1))
            near = [thor[k]] + ([thor[k - 1]] if 2 <= k <= 9 and k - 1 in thor else [])
            out.append((f"costovertebral {k} {m.group(2)}", [b], near, (0.0, 0.004)))
    return out


def joint_check(A, B, samples, solids):
    """Closest approach between two sets of bones and how deep either runs into the other."""
    best = None
    for a in A:
        for b in B:
            sa, sb = samples[a.node], samples[b.node]
            tb = cKDTree(sb)
            d = tb.query(sa)[0]
            gap = float(d.min())
            pen = 0.0
            for (x, sx, y) in ((a, sa, b), (b, sb, a)):
                sol = solids.get(y.group or y.node)
                if sol is None:
                    continue
                ins = sol.contains(sx)
                if ins.any():
                    dep = sol.depth(sx[ins])
                    if (dep > sol.deep).any():
                        pen = max(pen, float(dep.max()))
            if best is None or gap < best[0] or (gap == best[0] and pen > best[1]):
                best = (gap, pen, a.node, b.node)
    return best


# MARK: the audit

def audit_body(bones, others, quiet=False, only=None):
    t0 = time.time()
    plane = midplane(bones)
    by = {b.node: b for b in bones}
    # the solids: each bone on its own, the skull's pieces (and teeth) as one, each femur with its knee's cartilage
    groups = {}
    skull = [b for b in bones if b.part == "skull"]
    if skull:
        V, F, o = [], [], 0
        for b in skull:
            V.append(b.v); F.append(b.f + o); o += len(b.v)
            b.group = "skull"
        for st, v, f in others.get("skull", []):
            V.append(v); F.append(f + o); o += len(v)
        groups["skull"] = weld(np.vstack(V), np.vstack(F))
    for b in bones:
        m = re.search(r"femur_([LR])$", b.node)
        if m:
            cart = [(v, f) for st, v, f in others.get("legs", []) if re.search(rf"articular_cartilage.*_{m.group(1)}$", st["node"])]
            if cart:
                V, F, o = [b.v], [b.f], len(b.v)
                for v, f in cart:
                    V.append(v); F.append(f + o); o += len(v)
                groups[b.node] = weld(np.vstack(V), np.vstack(F))
                b.group = b.node
    samples = {b.node: surface_samples(b.v, b.f, 0.001) for b in bones}
    meshes = {b.node: (b.v, b.f) for b in bones if b.group is None}
    meshes.update(groups)
    solids = Solids(meshes)
    if not quiet:
        log(f"    solids and samples ready ({time.time() - t0:.0f} s)")
    # the skin
    skin = others.get("skin")
    skin_solid = None
    if skin:
        _, sv, sf = skin[0]
        skin_solid = Solid(sv, sf, h=0.003)
        skin_mesh = (sv, sf)
    rows = {}
    for b in bones:
        if only and not re.search(only, b.node):
            continue
        r = dict(node=b.node, label=b.label, part=b.part, uberon=b.uberon)
        r["topology"] = topology(b.v, b.f)
        if b.group and b.group != "skull" and b.group in groups:
            gt = topology(*groups[b.group])
            if gt["open"] == 0:
                r["closed_with"] = "its cartilage"
        n, caught = self_intersections(b.v, b.f)
        r["self_intersections"] = dict(pairs=n, share=float(len(caught) / max(1, len(b.f))))
        r["jagged"] = jaggedness(b.v, b.f)
        p = partner_of(b.node)
        if p and p in by:
            r["symmetry"] = symmetry(b, by[p], plane, samples)
        elif MIDLINE.search(b.node):
            r["symmetry"] = symmetry(b, None, plane, samples)
        r["straight"] = straightness(b)
        # outside the skin
        s = samples[b.node]
        if skin_solid is not None:
            ins = skin_solid.contains(s)
            d = skin_solid.depth(s)
            unsure = d < 0.006
            if unsure.any():
                w = winding_number(s[unsure], *skin_mesh)
                ins[unsure] = w > 0.5
            out = ~ins
            r["outside_skin"] = dict(share=float(out.mean()), most_mm=float(d[out].max() * 1000) if out.any() else 0.0)
        # inside other bones
        worst, share_all, deepest = None, 0.0, 0.0
        inside_any = np.zeros(len(s), bool)
        blo, bhi = s.min(0), s.max(0)
        for key in solids.near(blo, bhi):
            if key == (b.group or b.node):
                continue
            sol = solids.get(key)
            ins = sol.contains(s)
            if not ins.any():
                continue
            dep = sol.depth(s[ins])
            deep = np.zeros(len(s), bool)
            deep[np.flatnonzero(ins)[dep > sol.deep]] = True
            if deep.any():
                inside_any |= deep
                sh = float(deep.mean())
                if worst is None or sh > worst[1]:
                    worst = (key, sh, float(dep.max() * 1000))
                deepest = max(deepest, float(dep.max() * 1000))
        r["inside_bones"] = dict(share=float(inside_any.mean()), worst=worst[0] if worst else None,
                                 worst_share=worst[1] if worst else 0.0, deepest_mm=deepest)
        rows[b.node] = r
    if not quiet:
        log(f"    per-bone measures ({time.time() - t0:.0f} s)")
    # joints
    jrows = []
    for name, A, B, (lo, hi) in joints_of(bones):
        if only and not any(re.search(only, x.node) for x in A + B):
            continue
        gap, pen, a, b = joint_check(A, B, samples, solids)
        flag = []
        if gap > hi:
            flag.append("gap too big")
        if pen > 0.0005 + 1e-9:
            flag.append("overlap")
        jrows.append(dict(joint=name, a=a, b=b, gap_mm=gap * 1000, pen_mm=pen * 1000, lo_mm=lo * 1000,
                          hi_mm=hi * 1000, flag=", ".join(flag)))
        for x in (a, b):
            if x in rows:
                rows[x].setdefault("joints", []).append(jrows[-1])
    if not quiet:
        log(f"    joints ({time.time() - t0:.0f} s)")
    for r in rows.values():
        r["score"], r["why"] = score(r, by[r["node"]])
    whole = {}
    for g, (v, f) in groups.items():
        whole[g] = topology(v, f)
    return dict(plane=[plane[0].tolist(), plane[1].tolist()], bones=rows, joints=jrows, solids=whole)


def score(r, b):
    """The bone's badness: each flag capped, summed; and the reasons, worst first."""
    why = []
    t = r["topology"]
    closed_with = r.get("closed_with")
    if not b.cut and not closed_with:
        if t["open"]:
            why.append((min(1.0, t["open"] / 50), f"{t['open']} open edges"))
        if t["pieces"] > 1 and "sesamoid" not in b.node:
            why.append((min(1.5, 0.5 * (t["pieces"] - 1)), f"{t['pieces']} pieces"))
    if t["nonmanifold"]:
        why.append((min(0.5, t["nonmanifold"] / 40), f"{t['nonmanifold']} non-manifold edges"))
    si = r["self_intersections"]
    if si["pairs"]:
        why.append((min(2.0, 20 * si["share"]), f"{si['pairs']} self-intersecting pairs ({100 * si['share']:.1f}% of triangles)"))
    j = r["jagged"]
    if j["sharp"] > 0.002:
        why.append((min(2.0, 20 * j["sharp"]), f"{100 * j['sharp']:.1f}% of edges sharper than {SHARP:.0f} deg"))
    if j["spike_share"] > 0.001:
        why.append((min(1.5, 100 * j["spike_share"]), f"{j['spikes']} spikes ({100 * j['spike_share']:.1f}% of points)"))
    if j["noise_rel"] > 0.05:
        why.append((min(1.0, 10 * (j["noise_rel"] - 0.05)), f"surface noise {j['noise_mm']:.2f} mm ({100 * j['noise_rel']:.0f}% of an edge)"))
    s = r.get("symmetry")
    if s:
        tol = max(1.5, 0.03 * s["diag_mm"])
        if s["shape_hd_mm"] > tol:
            why.append((min(2.0, (s["shape_hd_mm"] - tol) / max(tol, 1e-9)),
                        f"shape {s['shape_hd_mm']:.1f} mm from its mirror ({s['partner'].replace('_', ' ')})"))
        if s["partner"] != "(itself)" and s["place_hd_mm"] > 10 and b.part in AXIAL:
            why.append((min(1.0, (s["place_hd_mm"] - 10) / 20), f"placed {s['place_hd_mm']:.0f} mm off its partner's mirror"))
        if s["partner"] != "(itself)" and abs(math.log(max(s["area_ratio"], 1e-6))) > 0.1:
            why.append((min(1.0, 3 * abs(math.log(s["area_ratio"]))), f"surface {s['area_ratio']:.2f} of its partner's"))
    st = r.get("straight")
    if st:
        if st["wave_mm"] > WAVY * 1000:
            why.append((min(2.0, (st["wave_mm"] - WAVY * 1000) / 2), f"wavy: centreline {st['wave_mm']:.1f} mm off a smooth curve"))
        if st.get("bow_share") is not None and st["bow_share"] > st["most_bow"]:
            ex = st["bow_share"] - st["most_bow"]
            why.append((min(2.0, ex * 33), f"bowed {st['bow_mm']:.1f} mm {st['bow_way']} ({100 * st['bow_share']:.1f}% of its chord; at most {100 * st['most_bow']:.1f}%)"))
    o = r.get("outside_skin")
    if o and o["share"] > 0.001:
        why.append((min(2.0, 20 * o["share"]), f"{100 * o['share']:.1f}% outside the skin (by up to {o['most_mm']:.1f} mm)"))
    ib = r["inside_bones"]
    if ib["share"] > 0.002:
        why.append((min(2.0, 20 * ib["share"]) + min(1.0, max(0, ib["deepest_mm"] - 1) / 4),
                    f"{100 * ib['share']:.1f}% inside other bones (most in {str(ib['worst']).replace('_', ' ')}, up to {ib['deepest_mm']:.1f} mm deep)"))
    for jr in r.get("joints", []):
        if "gap too big" in jr["flag"]:
            why.append((min(1.5, (jr["gap_mm"] - jr["hi_mm"]) / max(jr["hi_mm"], 1)), f"{jr['joint']}: gap {jr['gap_mm']:.1f} mm (at most {jr['hi_mm']:.0f})"))
        if "overlap" in jr["flag"]:
            why.append((min(1.5, (jr["pen_mm"] - 0.5) / 2), f"{jr['joint']}: overlap {jr['pen_mm']:.1f} mm"))
    why.sort(key=lambda x: -x[0])
    return float(sum(w for w, _ in why)), [w for _, w in why]


def audit(folder, only_body=None, only=None, quiet=False):
    out = {}
    for body, (bones, others) in load(folder, only_body).items():
        if not quiet:
            log(f"  {body}: {len(bones)} bones")
        out[body] = audit_body(bones, others, quiet, only)
    return out


# MARK: the report

def fmt(x, d=1):
    return "" if x is None else f"{x:.{d}f}"


def report(result, title="Bone audit", top=60):
    L = [f"# {title}", ""]
    L.append("Each bone's score is the sum of its flags, each capped (see tools/anatomy_bone_audit.py); worst first. "
             "Distances in mm. Symmetry: Hausdorff distance to the partner's mirror image (about the body's plane of "
             "symmetry) as placed, then after a rigid fit (shape).")
    L.append("")
    for body, res in result.items():
        rows = sorted(res["bones"].values(), key=lambda r: -r["score"])
        L.append(f"## {body.capitalize()}: {len(rows)} bones, {sum(1 for r in rows if r['score'] > 0)} flagged")
        L.append("")
        tot = sum(r["topology"]["triangles"] for r in rows)
        L.append(f"Triangles in bones: {tot:,}. Plane of symmetry: x = {res['plane'][0][0] * 1000:.1f} mm, "
                 f"normal ({', '.join(f'{c:.3f}' for c in res['plane'][1])}).")
        for g, t in res["solids"].items():
            L.append(f"Solid {g}: {t['triangles']:,} triangles, {t['open']} open edges, {t['nonmanifold']} non-manifold, {t['pieces']} pieces.")
        L.append("")
        L.append("| # | bone | score | why (worst first) |")
        L.append("|---|---|---|---|")
        for i, r in enumerate(rows[:top]):
            if r["score"] <= 0:
                break
            L.append(f"| {i + 1} | {r['node']} | {r['score']:.2f} | {'; '.join(r['why'][:4])} |")
        L.append("")
        L.append(f"### {body.capitalize()}: every bone's numbers")
        L.append("")
        L.append("| bone | tris | open | nm | pieces | self-x % | sharp % | spikes | noise mm | sym place | sym shape | wave mm | bow mm (%) | out skin % | in bone % (deep mm) | score |")
        L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            t, j, s, st = r["topology"], r["jagged"], r.get("symmetry"), r.get("straight")
            o, ib = r.get("outside_skin") or {}, r["inside_bones"]
            bow = f"{st['bow_mm']:.1f} ({100 * st['bow_share']:.1f}) {st['bow_way']}" if st and st.get("bow_mm") is not None else ""
            L.append("| " + " | ".join([
                r["node"], str(t["triangles"]), str(t["open"]), str(t["nonmanifold"]), str(t["pieces"]),
                fmt(100 * r["self_intersections"]["share"]), fmt(100 * j["sharp"]), str(j["spikes"]), fmt(j["noise_mm"], 2),
                fmt(s["place_hd_mm"]) if s else "", fmt(s["shape_hd_mm"]) if s else "",
                fmt(st["wave_mm"]) if st else "", bow,
                fmt(100 * o.get("share", 0)), f"{100 * ib['share']:.1f} ({ib['deepest_mm']:.1f})", f"{r['score']:.2f}"]) + " |")
        L.append("")
        L.append(f"### {body.capitalize()}: joints")
        L.append("")
        L.append("| joint | bones | closest mm | overlap mm | expected mm | flag |")
        L.append("|---|---|---|---|---|---|")
        for jr in sorted(res["joints"], key=lambda x: (x["flag"] == "", -x["pen_mm"], -x["gap_mm"])):
            L.append(f"| {jr['joint']} | {jr['a']}, {jr['b']} | {jr['gap_mm']:.1f} | {jr['pen_mm']:.1f} | "
                     f"{jr['lo_mm']:.1f} to {jr['hi_mm']:.1f} | {jr['flag']} |")
        L.append("")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("atlas")
    ap.add_argument("--out", help="the report (Markdown)")
    ap.add_argument("--json", help="every number, as JSON")
    ap.add_argument("--body", choices=("male", "female"))
    ap.add_argument("--only", help="only the bones whose node names match this")
    ap.add_argument("--title", default="Bone audit")
    a = ap.parse_args()
    t0 = time.time()
    res = audit(a.atlas, a.body, a.only)
    text = report(res, a.title)
    if a.out:
        open(a.out, "w").write(text)
    else:
        print(text)
    if a.json:
        json.dump(res, open(a.json, "w"), indent=1)
    log(f"done in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()
