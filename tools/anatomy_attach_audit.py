#!/usr/bin/env python3
"""Each muscle of a built atlas checked against the attachment table (docs/sciences/muscle-attachments.json), both
bodies, worst first.

    python3 tools/anatomy_attach_audit.py ATLAS_FOLDER [--table PATH] [--out report.md] [--json audit.json]
                                          [--before audit.json] [--body male|female] [--only REGEX]

For every structure that is muscle (each one in a muscular part, and muscle tissue elsewhere: the ciliary muscles,
the heart's papillary muscles, the bladder neck's smooth muscle), its row in the table (by the row's match on its
node name), then for each of the row's ends:

1. The end on the mesh (the row's find). cap: the share of the muscle's points farthest along a direction (x
   lateral for a muscle of one side, so a pair is found alike); far: the end of the muscle's longest way along its
   surface lying farther along a direction (for the eye's muscles, which bend); face: the muscle's deep face (its
   points within reach of the expected bones and facing them) between two shares of its length, the length being
   a harmonic function on the surface, 0 at its origin's end and 1 at its insertion's.
2. Its contact with the expected bones (the row's bone keys, resolved per body and side against the atlas): for an
   end, the distance within which a tenth of its points lie (a tendon's tip touches where some of it does); for an
   area, the median of its deep face's distances. The same for every other bone and cartilage of the body: the
   nearest, and how near.
3. How deep it lies inside any bone: each point's generalized winding number against each bone near it (inside
   over a half; the bones are not all closed, Jacobson et al. 2013 holds for those), the depth its distance to that
   bone's surface; the third deepest point's (so one or two stray points do not decide it).
4. A verdict: INSIDE BONE (deeper than 2 mm), else OK (the expected bones within 2 mm), else FLOATING (they are
   nearest, farther than 2 mm) or WRONG BONE (another bone or cartilage is nearer); UNKNOWN for a muscle with no
   row; NOT ON BONE for a row whose ends are soft (smooth and cardiac muscle: listed, not checked).
   Where the row names a landmark the tools can find (landmarks()), how far the end's contact lies from it.

Each muscle's verdict is its worst end's (WRONG BONE, INSIDE BONE, FLOATING, OK); the report ranks them worst
first, then by how far the worst end is from right. Whole-muscle checks beside it: the share of its points more
than 1 mm inside a bone. The JSON keeps every number; --before compares with an earlier run's JSON.
"""
import argparse
import json
import os
import re
import sys
import time
from collections import defaultdict

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from anatomy_fibres import read_part, weld, normals, cotan_weights  # noqa: E402

TABLE = os.path.normpath(os.path.join(HERE, "..", "docs", "sciences", "muscle-attachments.json"))
NEAR = 0.002          # on the bone: within 2 mm
DEEP = 0.002          # inside the bone: deeper than 2 mm
SAMPLE = 0.0008       # bones sampled about this far apart for nearest distances
ORDER = ["WRONG BONE", "INSIDE BONE", "FLOATING", "OK", "UNKNOWN", "NOT ON BONE", "NOT IN ATLAS"]
SEVERITY = {"WRONG BONE": 3, "INSIDE BONE": 2, "FLOATING": 1, "OK": 0}
# parts whose structures are attachments (bone, cartilage, ligament, tendon) or soft structures muscles attach to
ATTACH_TISSUE = ("bone", "cartilage", "ligament", "tooth")
NOT_OTHER = re.compile(r"nucleus_pulposus")      # inside a disc: never an end's nearest


# MARK: geometry

def surface_samples(v, f, h=SAMPLE, seed=0):
    """Points over the surface about h apart, each with its triangle's normal (the mesh wound outward)."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    cr = np.cross(b - a, c - a)
    area = np.linalg.norm(cr, axis=1) / 2
    n = cr / np.maximum(2 * area, 1e-18)[:, None]
    k = np.maximum(1, np.ceil(area / (h * h))).astype(int)
    rng = np.random.default_rng(seed)
    tri = np.repeat(np.arange(len(f)), k)
    r1, r2 = rng.random(len(tri)), rng.random(len(tri))
    s = np.sqrt(r1)
    p = a[tri] * (1 - s)[:, None] + b[tri] * (s * (1 - r2))[:, None] + c[tri] * (s * r2)[:, None]
    vn, _ = normals(v, f)
    return np.vstack([v, p]), np.vstack([vn, n[tri]])


def winding(q, v, f, chunk=128):
    """The mesh's generalized winding number at the points q (near 1 inside an outward-wound mesh, 0 outside)."""
    w = np.zeros(len(q))
    if not len(q):
        return w
    for s in range(0, len(q), chunk):
        qq = q[s:s + chunk]
        for i in range(0, len(f), 4000):
            a, b, c = (v[f[i:i + 4000, j]][None] - qq[:, None] for j in range(3))
            la, lb, lc = (np.linalg.norm(x, axis=2) for x in (a, b, c))
            det = np.einsum("qfk,qfk->qf", a, np.cross(b, c))
            den = (la * lb * lc + np.einsum("qfk,qfk->qf", a, b) * lc + np.einsum("qfk,qfk->qf", b, c) * la
                   + np.einsum("qfk,qfk->qf", c, a) * lb)
            w[s:s + chunk] += np.arctan2(det, den).sum(1) / (2 * np.pi)
    return w


class Solid:
    """One structure: its welded mesh, samples with normals, a tree, its bounds; distances and depths of points."""

    def __init__(self, name, v, f, tissue=None):
        self.name, self.tissue = name, tissue
        self.v, self.f = weld(np.asarray(v, float), np.asarray(f, np.int64))
        # wound outward (its volume positive), as the winding number and the normals assume
        a, b, c = self.v[self.f[:, 0]], self.v[self.f[:, 1]], self.v[self.f[:, 2]]
        if np.einsum("ij,ij->i", a, np.cross(b, c)).sum() < 0:
            self.f = self.f[:, ::-1]
        self.lo, self.hi = self.v.min(0), self.v.max(0)
        self._tree = None

    def tree(self):
        if self._tree is None:
            self.p, self.n = surface_samples(self.v, self.f)
            self._tree = cKDTree(self.p)
        return self._tree

    def distance(self, q, upper=np.inf):
        d, _ = self.tree().query(q, distance_upper_bound=upper)
        return d

    def near(self, q, reach):
        """Which of q lie within reach of its bounds."""
        return np.all((q > self.lo - reach) & (q < self.hi + reach), axis=1)

    def depth(self, q, least=0.0005):
        """How deep each point lies inside (0 outside, or less than `least` in): the points inside its bounds and
        behind its nearest sample (against that sample's outward normal) more than `least`, confirmed by the
        winding number (the sign alone errs where a bone is thin or open)."""
        out = np.zeros(len(q))
        box = self.near(q, 0.0)
        if box.any():
            idx = np.flatnonzero(box)
            d, j = self.tree().query(q[idx])
            behind = np.einsum("ij,ij->i", q[idx] - self.p[j], self.n[j]) < 0
            idx, d = idx[behind & (d > least)], d[behind & (d > least)]
            if len(idx):
                w = winding(q[idx], self.v, self.f)
                out[idx[w > 0.5]] = d[w > 0.5]
        return out


class Muscle:
    """A muscle's welded mesh, its normals, and its length coordinate between two ends."""

    def __init__(self, name, v, f):
        self.name = name
        self.v, self.f = weld(np.asarray(v, float), np.asarray(f, np.int64))
        self.vn, _ = normals(self.v, self.f)
        self.u = None

    def cap(self, direction, share):
        d = np.asarray(direction, float)
        d = d / max(np.linalg.norm(d), 1e-12)
        t = self.v @ d
        return t >= np.quantile(t, 1 - share)

    def far(self, direction):
        """The end of the longest way along the surface lying farther along `direction` (3% of that way)."""
        from scipy.sparse.csgraph import dijkstra
        import scipy.sparse as sp
        e = np.unique(np.sort(np.vstack([self.f[:, [0, 1]], self.f[:, [1, 2]], self.f[:, [2, 0]]]), axis=1), axis=0)
        g = sp.coo_matrix((np.linalg.norm(self.v[e[:, 0]] - self.v[e[:, 1]], axis=1), (e[:, 0], e[:, 1])),
                          shape=(len(self.v), len(self.v))).tocsr()
        fin = lambda d: np.where(np.isfinite(d), d, -1)
        a = int(np.argmax(fin(dijkstra(g, directed=False, indices=0))))
        da = dijkstra(g, directed=False, indices=a)
        b = int(np.argmax(fin(da)))
        db = dijkstra(g, directed=False, indices=b)
        d = np.asarray(direction, float)
        ends = [da < 0.03 * da[b], db < 0.03 * da[b]]
        score = [self.v[m].mean(0) @ d for m in ends]
        return ends[int(np.argmax(score))]

    def length_between(self, held0, held1):
        """u: 0 on held0, 1 on held1, harmonic between (cotangent weights)."""
        import scipy.sparse as sp
        import scipy.sparse.linalg as spl
        w = cotan_weights(self.v, self.f)
        L = sp.diags(np.asarray(w.sum(1)).ravel()) - w
        u = np.full(len(self.v), 0.5)
        both = held0 & held1
        held0, held1 = held0 & ~both, held1 & ~both
        u[held0], u[held1] = 0.0, 1.0
        held = held0 | held1
        free = ~held
        if free.any() and held0.any() and held1.any():
            A = L[free][:, free].tocsc()
            b = -L[free][:, held] @ u[held]
            u[free] = spl.spsolve(A + sp.identity(A.shape[0]) * 1e-12, b)
        self.u = np.clip(u, 0, 1)
        return self.u


# MARK: the table

def load_table(path=TABLE):
    with open(path) as f:
        return json.load(f)


def side_of(name):
    m = re.search(r"_([LR])$", name)
    return m.group(1) if m else None


def row_for(table, name):
    return next((r for r in table["muscles"] if re.search(r["match"], name)), None)


def expected(table, keys, body, side, names):
    """The atlas structures a list of bone keys names in this body, for a muscle of this side (None: midline)."""
    out = []
    for k in keys:
        pat = table["bone_keys"].get(k, {}).get(body)
        if not pat:
            continue
        sides = [side] if side else ["L", "R"]
        for s in sides:
            rx = re.compile(pat.replace("{S}", s).replace("{side}", "left" if s == "L" else "right"))
            out += [n for n in names if rx.search(n)]
    return sorted(set(out))


def mirrored(direction, side):
    d = np.array(direction, float)
    if side == "R":
        d[0] = -d[0]
    return d


# MARK: landmarks on the bones

def sphere_fit(p):
    M = np.c_[2 * p, np.ones(len(p))]
    x = np.linalg.lstsq(M, (p * p).sum(1), rcond=None)[0]
    return x[:3], float(np.sqrt(max(x[3] + x[:3] @ x[:3], 0.0)))


def seen_from(p, way, cell=0.002):
    """The points a viewer looking along -way sees first: per cell of the plane across `way`, the farthest along it."""
    way = np.asarray(way, float) / np.linalg.norm(way)
    a = np.cross(way, [0.0, 1.0, 0.0] if abs(way[1]) < 0.9 else [1.0, 0.0, 0.0])
    a /= np.linalg.norm(a)
    b = np.cross(way, a)
    key = np.stack([np.floor(p @ a / cell), np.floor(p @ b / cell)], 1).astype(np.int64)
    t = p @ way
    order = np.lexsort((-t, key[:, 1], key[:, 0]))
    k = key[order]
    first = np.r_[True, np.any(k[1:] != k[:-1], axis=1)]
    keep = np.zeros(len(p), bool)
    keep[order[first]] = True
    return keep


def landmarks(solids, table, body, side):
    """The landmarks this body's bones on this side show: name -> (points of the patch, a representative point).
    Only those its bones have; each is described in the table's landmarks."""
    names = list(solids)
    get = lambda key: [solids[n] for n in expected(table, [key], body, side, names)]
    sx = 1.0 if side == "L" else -1.0
    lat = np.array([sx, 0.0, 0.0])
    out = {}
    femur = get("femur")
    head = None
    if femur:
        F = femur[0]
        F.tree()
        fp, fnrm = F.p, F.n
        top = fp[fp[:, 1] > fp[:, 1].max() - 0.06]
        extreme = top[np.argmin(sx * top[:, 0])]
        head, radius = sphere_fit(top[np.linalg.norm(top - extreme, axis=1) < 0.03])
        side_pts = fp[sx * fp[:, 0] > sx * head[0] + 0.03]
        troch = side_pts[np.argmax(side_pts[:, 1])]
        gt = (sx * fp[:, 0] > sx * head[0] + 0.03) & (fp[:, 1] < troch[1] - 0.004) & (fp[:, 1] > troch[1] - 0.028)
        m = gt & (fnrm @ lat > 0.55)
        if m.sum() > 10:
            out["femur.greater_trochanter.lateral"] = (fp[m], fp[m].mean(0))
        m = gt & (fnrm[:, 2] > 0.5)
        if m.sum() > 10:
            out["femur.greater_trochanter.anterior"] = (fp[m], fp[m].mean(0))
        # the shaft's axis from its upper part, then the point farthest back and in from it below the neck
        y1 = fp[:, 1].max()
        cs = []
        for y in np.linspace(y1 - 0.30, y1 - 0.13, 8):
            band = fp[np.abs(fp[:, 1] - y) < 0.002]
            if len(band) > 20:
                cs.append(band.mean(0))
        cs = np.array(cs)
        c0 = cs.mean(0)
        ax = np.linalg.svd(cs - c0)[2][0]
        ax = ax if ax[1] > 0 else -ax
        band = (fp[:, 1] < head[1] - 0.035) & (fp[:, 1] > head[1] - 0.095)
        if band.any():
            q = fp[band]
            foot = c0 + np.outer((q - c0) @ ax, ax)
            way = np.array([-sx, 0.0, -1.0]) / np.sqrt(2)
            tip = q[np.argmax((q - foot) @ way)]
            m = np.linalg.norm(fp - tip, axis=1) < 0.009
            out["femur.lesser_trochanter"] = (fp[m], tip)
        out["femur.head"] = (head[None], head)
    ilium = get("ilium")
    if ilium and head is not None:
        for s in ilium:
            s.tree()
        H = np.vstack([s.p for s in ilium])
        Hn = np.vstack([s.n for s in ilium])
        m = (H[:, 1] > head[1] + 0.012) & (H[:, 1] < head[1] + 0.05) & (np.abs(H[:, 0] - head[0]) < 0.045)
        if m.any():
            q = H[m]
            tip = q[np.argmax(q[:, 2])]
            near = (np.linalg.norm(H - tip, axis=1) < 0.008)
            out["ilium.aiis"] = (H[near], tip)
        r = np.linalg.norm(H - head, axis=1)
        m = (r > 0.020) & (r < 0.034) & (H[:, 1] > head[1] + 0.008) & ((Hn[:, 1] > 0.3) | (Hn @ lat > 0.3))
        if m.sum() > 10:
            out["ilium.supra_acetabular"] = (H[m], H[m].mean(0))
        wing = H[:, 1] > head[1] + 0.012
        m = wing & (Hn @ lat > 0.3) & seen_from(H, lat)
        if m.sum() > 10:
            out["ilium.gluteal_surface"] = (H[m], H[m].mean(0))
        m = (H[:, 1] > head[1] + 0.015) & (Hn @ -lat > 0.3) & (H[:, 2] > head[2] - 0.03)
        if m.sum() > 10:
            out["ilium.iliac_fossa"] = (H[m], H[m].mean(0))
        above = H[:, 1] > head[1]
        if above.any():
            psis = H[above][np.argmin(H[above][:, 2])]
            m = above & (np.linalg.norm(H - psis, axis=1) < 0.04)
            out["ilium.iliac_crest.posterior"] = (H[m], psis)
    pat = get("patella")
    if pat:
        P = pat[0]
        P.tree()
        m = P.p[:, 1] > P.p[:, 1].max() - 0.2 * np.ptp(P.p[:, 1])
        out["patella.base"] = (P.p[m], P.p[m].mean(0))
    t12 = [solids[n] for n in expected(table, ["T12"], body, None, names)]
    if t12:
        T = t12[0]
        T.tree()
        m = (T.p[:, 2] > np.median(T.p[:, 2])) & (T.n @ lat > 0.3)
        if m.sum() > 10:
            # its lower half, where the psoas's highest slip arises (with the T12/L1 disc below it)
            m &= T.p[:, 1] < np.median(T.p[m, 1])
            out["vertebrae.T12_body"] = (T.p[m], T.p[m].mean(0))
    sac = [solids[n] for n in expected(table, ["sacrum"], body, None, names)]
    if sac:
        Sm = sac[0]
        Sm.tree()
        m = seen_from(Sm.p, [0.0, 0.0, -1.0]) & (Sm.n[:, 2] < -0.3)
        if m.sum() > 10:
            out["sacrum.dorsal_surface"] = (Sm.p[m], Sm.p[m].mean(0))
    return out


# MARK: the atlas

def load_body(folder, body):
    """A body's structures: name -> (vertices, triangles, part id, tissue, system), muscles and the rest."""
    out = {}
    for part in body["parts"]:
        meshes = None
        for st, mesh in zip(part["structures"], read_part(os.path.join(folder, part["file"]))):
            out[st["node"]] = (mesh[0], mesh[1], part["id"], st.get("tissue"), part["system"])
    return out


def is_muscle(name, part_system, tissue):
    return part_system == "muscular" or tissue == "muscle"


def attachment_solids(structs):
    """Every structure a muscle may be checked against: bone, cartilage, ligament and tooth, and every soft structure
    a table row names (made lazily: the caller asks for what it needs)."""
    return {n: Solid(n, v, f, tissue) for n, (v, f, pid, tissue, system) in structs.items()
            if tissue in ATTACH_TISSUE or system == "skeletal"}


# MARK: one muscle

def find_end(m, find, side):
    if find is None:
        return None
    if "cap" in find:
        return m.cap(mirrored(find["cap"], side), find.get("share", 0.04))
    if "far" in find:
        return m.far(mirrored(find["far"], side))
    return None


def contact(d, kind):
    """The contact distance of a region whose points lie d from the bone: a tenth of an end's points within it, or
    half of an area's deep face."""
    if not len(d):
        return np.inf
    return float(np.quantile(d, 0.1 if kind == "end" else 0.5))


def deep_face(m, sel, solids, reach, occluders=(), between=()):
    """The points of `sel` facing the solids within reach (the way to the nearest of them within 60 degrees of the
    point's outward normal), less those with another muscle nearer than the bone (a muscle under this one there,
    as the gluteus minimus lies under the medius), and less those nearer one of the bones `between` (the muscle's
    other attachments: where the gluteus maximus lies on the ilium, the sacrum beyond it is not what it is on)."""
    idx = np.flatnonzero(sel)
    if not len(idx) or not solids:
        return idx[:0]
    best_d = np.full(len(idx), np.inf)
    best_p = np.zeros((len(idx), 3))
    for s in solids:
        near = s.near(m.v[idx], reach)
        if not near.any():
            continue
        d, j = s.tree().query(m.v[idx[near]], distance_upper_bound=reach)
        ok = np.isfinite(d)
        k = np.flatnonzero(near)[ok]
        closer = d[ok] < best_d[k]
        best_d[k[closer]] = d[ok][closer]
        best_p[k[closer]] = s.p[j[ok][closer]]
    have = np.isfinite(best_d)
    way = best_p - m.v[idx]
    nrm = np.linalg.norm(way, axis=1)
    facing = (np.einsum("ij,ij->i", way, m.vn[idx]) > 0.5 * nrm) | (nrm < 0.0015)
    keep = have & facing
    for b in between:
        if not keep.any():
            break
        k = np.flatnonzero(keep)
        near = b.near(m.v[idx[k]], reach)
        if near.any():
            d = b.distance(m.v[idx[k[near]]], upper=reach)
            keep[k[near][d + 0.0005 < best_d[k[near]]]] = False
    for o in occluders:
        if not keep.any():
            break
        k = np.flatnonzero(keep)
        near = o.near(m.v[idx[k]], reach)
        if near.any():
            d = o.distance(m.v[idx[k[near]]], upper=reach)
            keep[k[near][d + 0.0005 < best_d[k[near]]]] = False
    return idx[keep]


def measure(m, region, kind, exp_solids, other_solids, all_solids):
    """Distances and depth of a region of the muscle: contact with the expected structures, the nearest other one,
    depth inside any bone."""
    q = m.v[region]
    res = {"points": int(len(region))}
    if not len(region):
        res.update(gap=np.inf, nearest_other=None, other_gap=np.inf, buried=0.0, buried_in=None)
        return res
    d_exp = np.full(len(q), np.inf)
    for s in exp_solids:
        d_exp = np.minimum(d_exp, s.distance(q, upper=0.25))
    res["gap"] = contact(d_exp, kind)
    res["gap_min"] = float(d_exp.min())
    best = (np.inf, None)
    for s in other_solids:
        if not s.near(q, 0.03).any():
            continue
        g = contact(s.distance(q, upper=0.06), kind)
        if g < best[0]:
            best = (g, s.name)
    res["other_gap"], res["nearest_other"] = best
    deepest = (0.0, None)
    for s in all_solids:
        if s.tissue not in ("bone", "cartilage") or not s.near(q, 0.0).any():
            continue
        dep = s.depth(q)
        third = float(np.sort(dep)[-3]) if len(dep) >= 3 else float(dep.max())
        if third > deepest[0]:
            deepest = (third, s.name)
    res["buried"], res["buried_in"] = deepest
    res["contact_points"] = q[d_exp <= max(res["gap"], NEAR) + 0.0015] if np.isfinite(res["gap"]) else q[:0]
    return res


def verdict(res):
    if res["buried"] > DEEP:
        return "INSIDE BONE"
    if res["gap"] <= NEAR:
        return "OK"
    if res["other_gap"] < res["gap"]:
        return "WRONG BONE"
    return "FLOATING"


def error_mm(res, v):
    """How far an end is from right, in mm: its gap past 2 mm, its depth past 2 mm, or for a wrong bone its gap
    to the right one."""
    if v == "INSIDE BONE":
        return 1000 * res["buried"]
    if v in ("FLOATING", "WRONG BONE"):
        return 1000 * (res["gap"] if np.isfinite(res["gap"]) else 250.0)
    return 0.0


# MARK: the audit

def audit_muscle(name, v, f, row, table, body, solids, others, names, marks_for, occluders=()):
    """One muscle's ends measured: a dict for the JSON."""
    side = side_of(name) if row.get("sided", True) else None
    ends = [("origin", e) for e in row["origin"]] + [("insertion", e) for e in row["insertion"]]
    out = {"body": body, "name": name, "row": row["id"], "side": side, "ends": []}
    checked = [(role, e) for role, e in ends if e.get("check", True) and e.get("find")]
    if not checked:
        out["verdict"], out["error_mm"] = "NOT ON BONE", 0.0
        return out, None
    m = Muscle(name, v, f)
    primary = {}
    for role in ("origin", "insertion"):
        e = next((e for r, e in ends if r == role and e.get("find") and ("cap" in e["find"] or "far" in e["find"])), None)
        primary[role] = find_end(m, e["find"], side) if e else None
    if primary["origin"] is None and primary["insertion"] is not None:
        c = m.v[primary["insertion"]].mean(0) - m.v.mean(0)
        primary["origin"] = m.cap(-c, 0.04)
    if primary["insertion"] is None and primary["origin"] is not None:
        c = m.v[primary["origin"]].mean(0) - m.v.mean(0)
        primary["insertion"] = m.cap(-c, 0.04)
    u = m.length_between(primary["origin"], primary["insertion"])
    marks = marks_for(side)
    row_bones = set()
    for role, e in checked:
        row_bones |= set(expected(table, e["bones"], body, side, names))
    for role, e in checked:
        exp_names = expected(table, e["bones"], body, side, names)
        exp = [solids[n] for n in exp_names if n in solids]
        between = [solids[n] for n in sorted(row_bones - set(exp_names)) if n in solids]
        find = e["find"]
        if "face" in find:
            u0, u1 = find["face"]
            sel = (u >= u0) & (u <= u1)
            region = deep_face(m, sel, exp, find.get("reach", 0.012), [o for o in occluders if o.name != name], between)
            if len(region) < 10 and exp:
                idx = np.flatnonzero(sel)
                d = np.min([s.distance(m.v[idx], upper=0.25) for s in exp], axis=0)
                region = idx[d <= np.quantile(d, 0.05)]
        else:
            region = np.flatnonzero(find_end(m, find, side))
        kind = "area" if "face" in find else "end"
        res = measure(m, region, kind, exp, [s for s in others if s.name not in exp_names], others)
        vd = verdict(res) if exp else "UNKNOWN"
        lm = []
        if res["points"] and len(res.get("contact_points", [])):
            c = res["contact_points"].mean(0)
        elif res["points"]:
            c = m.v[region].mean(0)
        else:
            c = None
        for key in e.get("landmarks", []):
            if key not in marks or c is None:
                continue
            if kind == "area":
                d, _ = cKDTree(marks[key][0]).query(m.v[region])
                lm.append({"landmark": key, "share": round(float((d < 0.006).mean()), 2)})
            else:
                lm.append({"landmark": key, "mm": round(1000 * float(np.min(np.linalg.norm(marks[key][0] - c, axis=1))), 1)})
        out["ends"].append({
            "role": role, "text": e["text"], "kind": kind, "expected": exp_names, "verdict": vd,
            "error_mm": round(error_mm(res, vd), 1), "gap_mm": round(1000 * res["gap"], 1) if np.isfinite(res["gap"]) else None,
            "gap_min_mm": round(1000 * res.get("gap_min", np.inf), 1) if np.isfinite(res.get("gap_min", np.inf)) else None,
            "nearest_other": res["nearest_other"],
            "other_gap_mm": round(1000 * res["other_gap"], 1) if np.isfinite(res["other_gap"]) else None,
            "buried_mm": round(1000 * res["buried"], 1), "buried_in": res["buried_in"], "points": res["points"],
            "landmarks": lm, "where_mm": None if c is None else [round(1000 * float(x), 1) for x in c]})
    worst = max(out["ends"], key=lambda x: (SEVERITY.get(x["verdict"], -1), x["error_mm"]))
    out["verdict"], out["error_mm"] = worst["verdict"], worst["error_mm"]
    # the whole muscle: its share of points more than 1 mm inside a bone or cartilage
    dep = np.zeros(len(m.v))
    for s in others:
        if s.tissue in ("bone", "cartilage") and np.all(s.hi > m.v.min(0)) and np.all(s.lo < m.v.max(0)):
            dep = np.maximum(dep, s.depth(m.v))
    out["in_bone_share"] = round(float((dep > 0.001).mean()), 4)
    out["in_bone_max_mm"] = round(1000 * float(dep.max()), 1)
    # and the other way: a bone's points more than 1 mm inside the muscle (a thin process through it, the muscle's
    # own points all outside the bone)
    me = Solid(name, m.v, m.f)
    tree = me.tree()
    through = 0
    for s in others:
        if s.tissue not in ("bone", "cartilage") or np.any(s.hi < m.v.min(0)) or np.any(s.lo > m.v.max(0)):
            continue
        s.tree()
        box = np.all((s.p > m.v.min(0)) & (s.p < m.v.max(0)), axis=1)
        if not box.any():
            continue
        q = s.p[box]
        dd, _ = tree.query(q, distance_upper_bound=0.015)
        q = q[np.isfinite(dd)]
        if len(q):
            through += int((me.depth(q, least=0.001) > 0).sum())
    out["bone_through"] = through
    return out, m


def audit(folder, table, bodies=None, only=None, quiet=False):
    manifest = json.load(open(os.path.join(folder, "anatomy.json")))
    results = []
    for body in manifest["bodies"]:
        if bodies and body["id"] not in bodies:
            continue
        structs = load_body(folder, body)
        names = list(structs)
        solids = {}
        for n, (v, f, pid, tissue, system) in structs.items():
            if tissue in ATTACH_TISSUE or system == "skeletal":
                solids[n] = Solid(n, v, f, tissue)
        # the soft structures rows name (the quadriceps tendon is a ligament already; the rectus femoris, the
        # sclera, the heart's walls...)
        for r in table["muscles"]:
            for e in r["origin"] + r["insertion"]:
                for n in expected(table, e["bones"], body["id"], None, names):
                    if n not in solids:
                        v, f, pid, tissue, system = structs[n]
                        solids[n] = Solid(n, v, f, tissue)
        others = [s for n, s in solids.items() if structs[n][4] != "muscular" and not NOT_OTHER.search(n)
                  and (s.tissue in ("bone", "cartilage", "tooth") or structs[n][4] == "skeletal")]
        occluders = [Solid(n, v, f, tissue) for n, (v, f, pid, tissue, system) in structs.items()
                     if system == "muscular" and tissue == "muscle"]
        cache = {}
        marks_for = lambda side: cache.setdefault(side, landmarks(solids, table, body["id"], side or "L"))
        for n, (v, f, pid, tissue, system) in structs.items():
            if not is_muscle(n, system, tissue):
                continue
            if only and not re.search(only, n):
                continue
            row = row_for(table, n)
            if row is None:
                results.append({"body": body["id"], "name": n, "row": None, "verdict": "UNKNOWN", "error_mm": 0.0, "ends": []})
                continue
            t0 = time.time()
            r, _ = audit_muscle(n, v, f, row, table, body["id"], solids, others, names, marks_for, occluders)
            results.append(r)
            if not quiet:
                print(f"  {body['id']} {n}: {r['verdict']} {r['error_mm']:.1f} mm ({time.time() - t0:.0f} s)", flush=True)
    # rows with no structure in a body (muscles still to be added)
    for body in manifest["bodies"]:
        if bodies and body["id"] not in bodies:
            continue
        have = {r["row"] for r in results if r["body"] == body["id"]}
        for r in table["muscles"]:
            if r["id"] not in have and not only:
                results.append({"body": body["id"], "name": r["name"], "row": r["id"], "verdict": "NOT IN ATLAS",
                                "error_mm": 0.0, "ends": []})
    return results


# MARK: the report

def short(name):
    return re.sub(r"^(VH_[MF]_|TS_|NLM_)", "", name or "")


def end_line(e):
    bits = [f"{e['role']} {e['verdict']}"]
    if e["gap_mm"] is not None:
        bits.append(f"{e['gap_mm']:.1f} mm from {', '.join(short(x) for x in e['expected'][:3])}{'...' if len(e['expected']) > 3 else ''}")
    if e["nearest_other"] and e["other_gap_mm"] is not None and (e["other_gap_mm"] < 10 or e["verdict"] == "WRONG BONE"):
        bits.append(f"nearest other {short(e['nearest_other'])} {e['other_gap_mm']:.1f} mm")
    if e["buried_mm"] > 0.3:
        bits.append(f"{e['buried_mm']:.1f} mm inside {short(e['buried_in'])}")
    for lm in e["landmarks"]:
        what = lm["landmark"].split(".", 1)[1].replace("_", " ")
        bits.append(f"{100 * lm['share']:.0f}% over the {what}" if "share" in lm else f"{lm['mm']:.0f} mm from the {what}")
    return "; ".join(bits)


def counts(results, key="verdict"):
    c = defaultdict(int)
    for r in results:
        c[r[key]] += 1
    return c


def report(results, folder, before=None):
    lines = [f"# Muscle attachments: audit of {folder}", "",
             "Each muscle's origin and insertion against docs/sciences/muscle-attachments.json "
             "(tools/anatomy_attach_audit.py). OK: on the right bone within 2 mm; FLOATING: the right bone nearest but "
             "farther; WRONG BONE: another bone nearer; INSIDE BONE: the end more than 2 mm in a bone; UNKNOWN: no row; "
             "NOT ON BONE: smooth or cardiac muscle, listed only. An end's distance is where a tenth of its tip lies (an "
             "end) or the median of its deep face (a broad attachment).", ""]
    present = [r for r in results if r["verdict"] != "NOT IN ATLAS"]
    lines += ["## Counts", "", "| verdict | " + " | ".join(b for b in ("male", "female")) + " | both |", "|---|---|---|---|"]
    for v in ORDER:
        if v == "NOT IN ATLAS":
            continue
        n = [sum(1 for r in present if r["verdict"] == v and r["body"] == b) for b in ("male", "female")]
        if sum(n) or v in SEVERITY or v == "UNKNOWN":
            lines.append(f"| {v} | {n[0]} | {n[1]} | {sum(n)} |")
    lines.append(f"| muscles | {sum(1 for r in present if r['body'] == 'male')} | "
                 f"{sum(1 for r in present if r['body'] == 'female')} | {len(present)} |")
    ends = [e for r in present for e in r["ends"]]
    lines += ["", "Ends: " + ", ".join(f"{v} {sum(1 for e in ends if e['verdict'] == v)}" for v in ORDER[:4]), ""]
    if before:
        old = {(r["body"], r["name"]): r for r in before}
        lines += ["## Before and after", "", "| verdict | before | after |", "|---|---|---|"]
        for v in ORDER[:6]:
            lines.append(f"| {v} | {sum(1 for r in before if r['verdict'] == v)} | {sum(1 for r in present if r['verdict'] == v)} |")
        lines += ["", "| body | muscle | before | after |", "|---|---|---|---|"]
        for r in present:
            o = old.get((r["body"], r["name"]))
            if o and (o["verdict"] != r["verdict"] or abs(o["error_mm"] - r["error_mm"]) > 0.5):
                lines.append(f"| {r['body']} | {short(r['name'])} | {o['verdict']} {o['error_mm']:.1f} mm | "
                             f"{r['verdict']} {r['error_mm']:.1f} mm |")
        lines.append("")
    lines += ["## Ranked, worst first", "", "| # | body | muscle | verdict | worst (mm) | in bone >1 mm | ends |", "|---|---|---|---|---|---|---|"]
    rank = sorted(present, key=lambda r: (-SEVERITY.get(r["verdict"], -1), -r["error_mm"], r["body"], r["name"]))
    for i, r in enumerate(rank, 1):
        ib = f"{100 * r['in_bone_share']:.1f}% (max {r['in_bone_max_mm']:.1f})" if "in_bone_share" in r else ""
        if r.get("bone_through"):
            ib += f"; {r['bone_through']} bone points through it"
        lines.append(f"| {i} | {r['body']} | {short(r['name'])} | {r['verdict']} | {r['error_mm']:.1f} | {ib} | "
                     + "<br>".join(end_line(e) for e in r["ends"]) + " |")
    missing = [r for r in results if r["verdict"] == "NOT IN ATLAS"]
    if missing:
        lines += ["", "## Rows with no structure in a body", "",
                  ", ".join(sorted({f"{r['name']} ({r['body']})" for r in missing}))]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folder")
    ap.add_argument("--table", default=TABLE)
    ap.add_argument("--out")
    ap.add_argument("--json")
    ap.add_argument("--before", help="an earlier run's --json, to compare")
    ap.add_argument("--body", choices=["male", "female"])
    ap.add_argument("--only", help="a regular expression on node names")
    a = ap.parse_args()
    table = load_table(a.table)
    results = audit(a.folder, table, [a.body] if a.body else None, a.only)
    before = json.load(open(a.before)) if a.before else None
    text = report(results, a.folder, before)
    if a.out:
        open(a.out, "w").write(text)
    if a.json:
        json.dump(results, open(a.json, "w"), indent=1)
    c = counts([r for r in results if r["verdict"] != "NOT IN ATLAS"])
    print(", ".join(f"{v} {c[v]}" for v in ORDER if c.get(v)))


if __name__ == "__main__":
    main()
