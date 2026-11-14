"""The whole body, nothing passing into anything (work in progress)."""
import json
import math
import os
import re
import sys

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

EPS = 0.1234567          # the columns' centres off the grid's, so no corner of the mesh lies on one


def welded(p, f):
    """The mesh with its points at one place made one (as they are written: the muscles' bundles split a point
    where its triangles disagree), and its triangles that then lose a corner dropped."""
    p = np.asarray(p, np.float64)
    f = np.asarray(f, np.int64)
    _, first, inv = np.unique(np.round(p * 1e7).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    g = inv.reshape(-1)[f]
    g = g[(g[:, 0] != g[:, 1]) & (g[:, 1] != g[:, 2]) & (g[:, 2] != g[:, 0])]
    return p[first], g


def capped(p, f):
    """The mesh, welded, with each hole closed by a fan from its rim's middle (tools/anatomy_gaps.py capped)."""
    from anatomy_gaps import capped as cap
    return cap(*welded(p, f))


class Winding:
    """A closed mesh's inside, exactly but for a grain: its winding number read along columns `s` apart running
    along each axis, the signed count of the surface's crossings below a point on the column through it (each a
    triangle's face, its sign its normal's that way: for a mesh wound out, one going in is +1). A point is inside
    when two of the three axes find it so (|winding| over a half): the mesh's holes are capped first (a fan from
    each rim's middle), so a tube cut open at its ends reads as a solid, and where a cap is not flat, or a mesh
    is not quite closed, the three axes outvote the one that passes through the gap. A point is read on the
    column nearest it, so the answer is exact for a point up to 0.71 s from it: wrong only within that of the
    surface. Several pieces that overlap count as one (winding 2)."""

    def __init__(self, v, f, s=0.0005, cap=True):
        v = np.asarray(v, np.float64)
        f = np.asarray(f, np.int64)
        if cap:
            v, f = capped(v, f)
        self.s = s
        self.lo = v.min(0) - 2 * s
        self.hi = v.max(0) + 2 * s
        self.n = np.ceil((self.hi - self.lo) / s).astype(np.int64) + 2
        self.axes = [self._columns(v, f, ax) for ax in range(3)]

    def _columns(self, v, f, ax):
        u, w = (ax + 1) % 3, (ax + 2) % 3
        s, lo = self.s, self.lo
        g = (v[:, [u, w]] - lo[[u, w]]) / s - (0.5 + EPS)        # column (i, j) at grid point (i, j)
        A, B, C = g[f[:, 0]], g[f[:, 1]], g[f[:, 2]]
        d = (B[:, 0] - A[:, 0]) * (C[:, 1] - A[:, 1]) - (B[:, 1] - A[:, 1]) * (C[:, 0] - A[:, 0])
        mn = np.ceil(np.minimum(np.minimum(A, B), C)).astype(np.int64)
        mx = np.floor(np.maximum(np.maximum(A, B), C)).astype(np.int64)
        nu, nw = mx[:, 0] - mn[:, 0] + 1, mx[:, 1] - mn[:, 1] + 1
        ok = np.flatnonzero((nu > 0) & (nw > 0) & (np.abs(d) > 1e-12))
        cnt = nu[ok] * nw[ok]
        cols, ts, sg = [], [], []
        start = 0
        while start < len(ok):
            # chunks of about 4 million candidates
            cum = np.cumsum(cnt[start:])
            stop = start + max(1, int(np.searchsorted(cum, 4_000_000)))
            tri = ok[start:stop]
            c = cnt[start:stop]
            T = np.repeat(np.arange(len(tri)), c)
            k = np.arange(int(c.sum())) - np.repeat(np.cumsum(c) - c, c)
            t = tri[T]
            iu = mn[t, 0] + k // nw[t]
            iw = mn[t, 1] + k % nw[t]
            a, b, cc = A[t], B[t], C[t]
            pu, pw = iu - a[:, 0], iw - a[:, 1]
            dd = d[t]
            l1 = (pu * (cc[:, 1] - a[:, 1]) - pw * (cc[:, 0] - a[:, 0])) / dd
            l2 = ((b[:, 0] - a[:, 0]) * pw - (b[:, 1] - a[:, 1]) * pu) / dd
            inside = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
            t, l1, l2, iu, iw = t[inside], l1[inside], l2[inside], iu[inside], iw[inside]
            va, vb, vc = v[f[t, 0], ax], v[f[t, 1], ax], v[f[t, 2], ax]
            ts.append(va + l1 * (vb - va) + l2 * (vc - va))
            cols.append(iu * self.n[w] + iw)
            sg.append(np.sign(d[t]).astype(np.int8))
            start = stop
        col = np.concatenate(cols) if cols else np.zeros(0, np.int64)
        t = np.concatenate(ts) if ts else np.zeros(0)
        sgn = np.concatenate(sg) if sg else np.zeros(0, np.int8)
        span = self.hi[ax] - self.lo[ax]
        key = col + 0.25 + 0.5 * (t - self.lo[ax]) / span
        order = np.argsort(key, kind="stable")
        key, sgn = key[order], sgn[order]
        cs = np.concatenate([[0], np.cumsum(sgn, dtype=np.int64)])
        return key, cs

    def winding(self, q):
        """The winding number along each axis at the points q, (n, 3); 0 outside the box."""
        q = np.asarray(q, np.float64)
        out = np.zeros((len(q), 3), np.int64)
        box = ((q > self.lo) & (q < self.hi)).all(1)
        if not box.any():
            return out
        qb = q[box]
        for ax, (key, cs) in enumerate(self.axes):
            u, w = (ax + 1) % 3, (ax + 2) % 3
            g = np.rint((qb[:, [u, w]] - self.lo[[u, w]]) / self.s - (0.5 + EPS)).astype(np.int64)
            col = g[:, 0] * self.n[w] + g[:, 1]
            span = self.hi[ax] - self.lo[ax]
            at = np.searchsorted(key, col + 0.25 + 0.5 * (qb[:, ax] - self.lo[ax]) / span)
            first = np.searchsorted(key, col.astype(np.float64))
            out[box, ax] = cs[first] - cs[at]          # wound out: crossing in is +1, so below a point inside, +1
        return out

    def inside(self, q):
        """Whether each point lies inside: two of the three axes' winding numbers over a half."""
        w = self.winding(q)
        return (np.abs(w) >= 1).sum(1) >= 2


# MARK: the body's structures, and the solids they make

class Item:
    """One structure: its part, its place in the part's file, its manifest entry and its mesh."""
    def __init__(self, pid, k, st, v, f):
        self.pid, self.k, self.st = pid, k, st
        self.node, self.tissue, self.inner = st["node"], st.get("tissue"), bool(st.get("inner"))
        self.v, self.f = np.asarray(v, np.float64), np.asarray(f, np.int64)
        self.lo, self.hi = self.v.min(0), self.v.max(0)
        self.group = None

    def short(self):
        return re.sub(r"^(VH_[MF]_|NLM_|TS_|Allen_)", "", self.node)


def load_body(folder, body):
    """Every structure of a body, as Items, part by part."""
    from anatomy_fibres import read_part
    items = []
    for part in body["parts"]:
        meshes = read_part(os.path.join(folder, part["file"]))
        for k, (st, (v, f)) in enumerate(zip(part["structures"], meshes)):
            items.append(Item(part["id"], k, st, v, f))
    return items


def _find(parent, a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a


def tile_groups(items, least=3):
    """The structures that tile one surface, as groups of item indices: within a part, two structures whose open
    edges meet (at least `least` edges at the same points: the lung's segments, the skull's bones, a vessel and
    the branch welded to it) are one solid, read together; every other structure is a group of its own."""
    parent = list(range(len(items)))
    by_part = {}
    for i, it in enumerate(items):
        by_part.setdefault(it.pid, []).append(i)
    for pid, idx in by_part.items():
        if len(idx) < 2:
            continue
        allv = np.concatenate([items[i].v for i in idx])
        _, inv = np.unique(np.round(allv * 1e7).astype(np.int64), axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        off = np.cumsum([0] + [len(items[i].v) for i in idx])
        keys, owner = [], []
        for j, i in enumerate(idx):
            g = inv[items[i].f + off[j]]
            g = g[(g[:, 0] != g[:, 1]) & (g[:, 1] != g[:, 2]) & (g[:, 2] != g[:, 0])]
            E = np.sort(np.concatenate([g[:, [0, 1]], g[:, [1, 2]], g[:, [2, 0]]]), 1)
            e, c = np.unique(E, axis=0, return_counts=True)
            r = e[c == 1]
            keys.append(r[:, 0] * (len(allv) + 1) + r[:, 1])
            owner.append(np.full(len(r), i))
        keys, owner = np.concatenate(keys), np.concatenate(owner)
        order = np.argsort(keys, kind="stable")
        keys, owner = keys[order], owner[order]
        same = np.flatnonzero((keys[1:] == keys[:-1]) & (owner[1:] != owner[:-1]))
        count = {}
        for s in same:
            a, b = sorted((int(owner[s]), int(owner[s + 1])))
            count[(a, b)] = count.get((a, b), 0) + 1
        for (a, b), n in count.items():
            if n >= least:
                ra, rb = _find(parent, a), _find(parent, b)
                if ra != rb:
                    parent[rb] = ra
    groups = {}
    for i in range(len(items)):
        groups.setdefault(_find(parent, i), []).append(i)
    out = sorted(groups.values(), key=lambda g: g[0])
    for gi, g in enumerate(out):
        for i in g:
            items[i].group = gi
    return out


def spacing(v, f):
    """The grain to read a solid on: a quarter of its thickness (twice its volume over its area), 0.25 to 0.75 mm."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1).sum() / 2
    vol = abs(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6
    t = 2 * vol / max(area, 1e-12)
    return float(np.clip(t / 4, 0.00025, 0.00075))


def edge_counts(f):
    E = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    _, c = np.unique(E, axis=0, return_counts=True)
    return len(c), int((c == 1).sum()), int((c > 2).sum())


def joined(items, members):
    """The members' meshes as one, welded."""
    vs = [items[i].v for i in members]
    cut = np.cumsum([0] + [len(v) for v in vs])
    return welded(np.concatenate(vs), np.concatenate([items[i].f + cut[k] for k, i in enumerate(members)]))


def sheet(it):
    """Whether a structure is a sheet, with no inside to keep out of: open, and its holes' caps a large share of
    its surface (four tenths or more: a cup, a lining, a ligament; a tube's caps, its ends, are a small one)."""
    if it.tissue in TUBE_TISSUES:
        return False
    v, f = welded(it.v, it.f)
    n, open_, _ = edge_counts(f)
    if not open_:
        return False
    cv, cf = capped(v, f)
    area = lambda p, t: np.linalg.norm(np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]]), axis=1).sum() / 2
    return area(cv, cf[len(f):]) >= 0.4 * area(v, f)


class Filled:
    """A volume its structures tile together, their inner walls shared (the lung's segments: a wall's edges meet
    three faces, and each segment alone is open): their surfaces as voxels `h` apart, closed over a voxel's gaps and
    filled. Exact to a voxel."""
    def __init__(self, items, members, h=0.0006):
        from scipy import ndimage
        from anatomy_gaps import face_samples
        P = []
        for i in members:
            it = items[i]
            B, T, _ = face_samples(it.v, it.f, h / 2)
            P.append(np.einsum("sk,skc->sc", B, it.v[it.f[T]]))
        P = np.concatenate(P)
        self.h, self.lo = h, P.min(0) - 3 * h
        idx = np.floor((P - self.lo) / h).astype(np.int64)
        g = np.zeros(idx.max(0) + 4, bool)
        g[tuple(idx.T)] = True
        self.g = ndimage.binary_fill_holes(ndimage.binary_closing(g, iterations=1)) | g

    def inside(self, q):
        idx = np.floor((np.asarray(q) - self.lo) / self.h).astype(np.int64)
        ok = ((idx >= 0) & (idx < self.g.shape)).all(1)
        out = np.zeros(len(q), bool)
        out[ok] = self.g[tuple(idx[ok].T)]
        return out


class Region:
    """A group's solid. Where its structures tile one closed surface (the skull's bones, the spleen's faces, a
    vessel and its welded branches), that surface, its few remaining holes capped (a fan from each rim's middle),
    read by Winding; where they tile a volume, their inner walls shared (the lung's segments), or do not close,
    each structure capped and read on its own, the region being in any of them. A sheet is no solid (sheet()).
    Its surface sampled finely, each sample knowing its structure, for how deep a point lies and in which."""
    def __init__(self, items, members):
        self.members = members
        v, f = joined(items, members)
        n, open_, many = edge_counts(f)
        self.union = len(members) > 1 and open_ <= 0.10 * n and many <= 0.02 * n
        if len(members) > 1 and many > 0.02 * n:
            self.solids = [Filled(items, members)]
        elif self.union:
            self.solids = [Winding(v, f, spacing(*capped(v, f)))]
        else:
            self.solids = []
            for i in members:
                it = items[i]
                if sheet(it):
                    continue
                cv, cf = capped(it.v, it.f)
                self.solids.append(Winding(it.v, it.f, spacing(cv, cf)))
        self.lo, self.hi = v.min(0), v.max(0)
        self.items, self._tree = items, None

    @property
    def tree(self):
        if self._tree is None:
            from anatomy_gaps import face_samples
            pts, who = [], []
            for i in self.members:
                it = self.items[i]
                B, T, _ = face_samples(it.v, it.f, 0.0004)
                pts.append(np.einsum("sk,skc->sc", B, it.v[it.f[T]]))
                who.append(np.full(len(pts[-1]), i))
            self._tree = cKDTree(np.concatenate(pts))
            self.who = np.concatenate(who)
        return self._tree

    def inside(self, q):
        out = np.zeros(len(q), bool)
        for W in self.solids:
            out |= W.inside(q)
        return out

    def depth(self, q):
        """How far each point lies from the group's surface, and the structure whose surface that is."""
        d, j = self.tree.query(q)  # (builds self.who)
        return d, self.who[j]


# MARK: what may lie in what

TUBE_TISSUES = ("artery", "vein", "duct", "gut", "airway", "nerve")
VESSEL = ("artery", "vein")
SOLID_ORGAN = ("organ", "gland", "lymph", "heart", "lung")
LOOSE = ("fat",)                     # a sheet that wraps what it holds, never a wall
ANY = None
# An organ's own vessels and ducts, and what joins it, which may lie in it: (the inner structure and its tissues,
# the organ and its tissues, why), regular expressions on their nodes. Gray's Anatomy (1918, public domain): the
# vessels and ducts named for an organ enter it at its hilum or run in its wall; the ducts named run through it.
OWN = [
    (r"hepatic|portal", VESSEL + ("duct",), r"liver|segment|caudate|quadrate|lobe", ("organ",),
     "the liver's own vessels and ducts"),
    (r"vena_cava", VESSEL, r"liver|segment|caudate|lobe", ("organ",),
     "the inferior vena cava in its fossa on the liver, 'occasionally a complete canal' (Gray's, the liver)"),
    (r"cystic", VESSEL + ("duct",), r"gallbladder", ("organ",), "the gallbladder's own duct and vessels"),
    (r"common_bile_duct|pancreatic_duct|hepatopancreatic", ("duct",), r"pancrea", ("organ", "gland"),
     "the bile duct and the pancreatic ducts run through the pancreas's head (Gray's, the pancreas)"),
    (r"pancreaticoduodenal", VESSEL, r"pancrea|duoden", ("organ", "gland", "gut"),
     "the pancreaticoduodenal vessels, between the pancreas's head and the duodenum"),
    (r"common_bile_duct|pancreatic_duct|hepatopancreatic|santorini|ampulla", ("duct",), r"duoden", ("gut", "duct"),
     "the ducts open through the duodenum's wall"),
    (r"splenic", VESSEL, r"spleen|hilum_of_spleen", ("lymph", "organ"), "the spleen's own vessels, at its hilum"),
    (r"renal|ureter|calyx|pelvis", VESSEL + ("duct",), r"kidney|renal|calyx|pelvis_[LR]|hilum_of_kidney|papilla|"
     r"pyramid|cortex", ("organ", "duct"), "the kidney's own vessels and ducts, at its hilum"),
    (r"coronary|cardiac_vein|marginal|descending|diagonal|oblique_vein|coronary_sinus|posterior_vein_of_left|"
     r"circumflex|ventricular_branch|interventricular", VESSEL, r"atrium|ventricle|septum|heart|cardiac",
     ("heart", "muscle"), "the heart's own vessels, in its wall"),
    (r"aort|pulmonary_trunk|pulmonary_vein|vena_cava|pulmonary_artery|coronary_sinus", VESSEL,
     r"atrium|ventricle|septum|valve|heart|cardiac", ("heart", "muscle"), "a great vessel's root in the heart"),
    (r"pulmonary|bronch", VESSEL + ("airway", "cartilage"), r"segm|lung|hilum", ("lung",),
     "the lungs' own vessels and airways"),
    (r"rectal", VESSEL, r"rectum", ("gut",), "the rectum's own vessels"),
    (r"sigmoid", VESSEL, r"sigmoid", ("gut",), "the sigmoid colon's own vessels"),
    (r"colic|marginal_artery", VESSEL, r"colon|caecum|cecum|flexure", ("gut",), "the colon's own vessels"),
    (r"ileocolic", VESSEL, r"ileum|caecum|cecum|ileocecal|colon", ("gut",), "the ileocolic vessels"),
    (r"ophthalmic|opthalmic|retinal|ciliary", VESSEL, r"optic|retina|sclera|choroid|eye|disc", ("eye", "nerve"),
     "the eye's own vessels (the central retinal vessels run in the optic nerve)"),
    (r"uterine", VESSEL, r"uter", ("organ",), "the uterus's own vessels"),
    (r"ovarian", VESSEL, r"ovar", ("gland", "organ"), "the ovary's own vessels"),
    (r"vesic", VESSEL, r"bladder|trigone", ("organ", "muscle"), "the bladder's own vessels"),
    (r"ureter", ("duct",), r"bladder|trigone|ureteral", ("organ", "duct", "muscle"),
     "the ureter ends in the bladder's wall (Gray's: it runs obliquely through it)"),
    (r"prostatic_urethra|ejaculatory|prostate_duct|utricle|colliculus", ("duct", "gland"),
     r"prostat|colliculus|utricle", ("gland", "duct"),
     "runs through the prostate (Gray's: the prostatic urethra, the ejaculatory ducts)"),
    (r"other_urethra|urethra", ("duct",), r"prostat", ("gland",), "the urethra leaves the prostate at its apex"),
    (r"vas_deferens|ejaculatory|seminal", ("duct", "gland"), r"seminal|ejaculatory|vas_deferens", ("duct", "gland"),
     "the genital ducts join"),
    (r"uterine_tube|tube|ostium", ("duct", "organ"), r"uter|fundus|cornu", ("organ",),
     "the uterine tube's intramural part, in the uterus's wall"),
    (r"vagin|cervi", ("organ",), r"uter|cervi|vagin", ("organ",), "the cervix in the vagina's vault"),
    (r"oesophagus", ("gut",), r"stomach", ("gut",), "the oesophagus opens into the stomach"),
    (r"stomach", ("gut",), r"duoden", ("gut",), "the stomach opens into the duodenum"),
    (r"ileum|ileocecal", ("gut",), r"caecum|cecum|ileocecal|colon", ("gut",), "the ileum opens into the caecum"),
    (r"appendix", ("gut",), r"caecum|cecum", ("gut",), "the appendix opens off the caecum"),
    (r"trachea", ("airway", "cartilage"), r"cricoid|larynx", ("cartilage",), "the trachea hangs from the cricoid"),
    (r"lactiferous|areol|nipple", ANY, r"breast|mammary|lactiferous|areol|nipple|lobule", ANY,
     "the breast's own ducts"),
]
# The nerves Gray's Anatomy (1918) says pierce a muscle or run in it: (nerve, muscle). None is drawn yet.
PIERCE = [
    (r"genitofemoral", r"psoas|iliopsoas"),           # "passes obliquely forward and downward through the Psoas major"
    (r"femoral_nerve|obturator_nerve|iliohypogastric|ilioinguinal|lateral_femoral_cutaneous|lumbar_plexus",
     r"psoas|iliopsoas"),                             # the lumbar plexus "situated in the posterior part of the Psoas"
    (r"musculocutaneous", r"coracobrachialis"),       # "pierces the Coracobrachialis"
    (r"greater_occipital", r"semispinalis|trapezius|deep_back"),   # "pierces the Semispinalis capitis and Trapezius"
    (r"accessory", r"sternocleidomastoid"),           # "pierces the deep surface of the Sternocleidomastoideus"
    (r"radial.*deep|posterior_interosseous", r"supinator"),        # "pierces the Supinator"
    (r"perforating_cutaneous", r"gluteus_maximus"),   # "pierces the lower part of the sacrotuberous ligament"
]
ATTACH_DEPTH = 0.002     # a muscle's end this far into a bone it arises from or inserts on is its attachment


def own(a, b):
    """The reason structure a may lie in structure b as its organ's own (OWN, PIERCE), or None."""
    for x, xt, y, yt, why in OWN:
        if re.search(x, a.node, re.I) and re.search(y, b.node, re.I) and (xt is ANY or a.tissue in xt) \
                and (yt is ANY or b.tissue in yt):
            return why
    if a.tissue == "nerve" and b.tissue == "muscle":
        for x, y in PIERCE:
            if re.search(x, a.node, re.I) and re.search(y, b.node, re.I):
                return "the nerve pierces the muscle (Gray's Anatomy, 1918)"
    return None


def rims(it):
    """A structure's open ends: each hole's middle and mean radius."""
    v, f = welded(it.v, it.f)
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    key = np.sort(E, 1)
    _, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    rim = E[cnt[inv.reshape(-1)] == 1]
    if not len(rim):
        return np.zeros((0, 3)), np.zeros(0)
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    _, comp = connected_components(coo_matrix((np.ones(len(rim)), (rim[:, 0], rim[:, 1])), shape=(len(v), len(v))),
                                   directed=False)
    lab = comp[rim[:, 0]]
    out_c, out_r = [], []
    for l in np.unique(lab):
        p = v[np.unique(rim[lab == l])]
        c = p.mean(0)
        out_c.append(c)
        out_r.append(float(np.linalg.norm(p - c, axis=1).mean()))
    return np.array(out_c), np.array(out_r)


def named_legit(a, b):
    """Why structure a may lie in b, by what they are alone (no matter where or how deep), or None."""
    if a.pid == "brain" and b.pid == "brain":
        return "nested brain parts"
    if a.pid == "eyes" and b.pid == "eyes":
        return "the eye's own coats, humours and lids (tools/anatomy_eyes.py)"
    if (a.inner or b.inner) and a.pid == b.pid:
        return "inside its own organ (drawn when the organ is opened)"
    if a.tissue in LOOSE or b.tissue in LOOSE:
        return "fat, which wraps what it holds"
    if a.pid == b.pid == "spinal-cord":
        return "the cord's segments, end to end"
    if a.pid == b.pid == "optic-nerves":
        return "the optic nerve in its dural sheath"
    if a.pid == b.pid == "breasts":
        return "the breast's own lobules, ducts and fat"
    if a.pid == b.pid and a.tissue == "ligament" and b.tissue == "ligament":
        return "ligaments of one organ, side by side"
    if a.pid == b.pid == "vertebral-column" and "nucleus_pulposus" in a.node and \
            a.node.replace("nucleus_pulposus_of_", "") == b.node:
        return "the disc's own nucleus pulposus"
    if a.pid == "airways" and b.pid == "lungs":
        return "the airways in their lung"
    if a.pid == b.pid == "airways":
        return "the bronchial tree's own branches and cartilages"
    why = own(a, b)
    if why:
        return why
    if a.pid == b.pid == "knee-muscles" and a.short()[-2:] == b.short()[-2:]:
        return "a muscle and its own tendon"
    return None


def legit(a, b, pts, depth):
    """Why structure a's points `pts` (lying `depth` deep) may lie in b (a reason), or None: a fault."""
    why = named_legit(a, b)
    if why:
        return why
    if a.tissue in TUBE_TISSUES and b.tissue in TUBE_TISSUES + SOLID_ORGAN:
        c, r = rims(a)
        if len(c):
            near = np.min(np.linalg.norm(pts[:, None] - c[None], axis=2) - (1.5 * r + 0.002)[None], axis=1) <= 0
            if near.all():
                return "its cut end opens into the other (a join)"
    if a.tissue == "muscle" and b.tissue in ("bone", "cartilage") and depth.max() <= ATTACH_DEPTH:
        return "a muscle on its bone, within an attachment's depth"
    return None


# MARK: the audit

def unique_points(it):
    """A structure's points, each place once, and the share of its surface each stands for."""
    from anatomy_gaps import vertex_area
    v, f = welded(it.v, it.f)
    return v, vertex_area(v, f) / max(vertex_area(v, f).sum(), 1e-12)


def audit_body(items, groups, quiet=True, skip_named=True):
    """Every structure's points inside every other group's solid: [(a, b, points in, its points, share of its
    surface, deepest, 90th percentile depth, reason or None)], a and b item indices (b the structure of the group
    whose surface lies nearest the points)."""
    import time
    t0 = time.time()
    pts = [unique_points(it) for it in items]
    lo = np.array([it.lo for it in items])
    hi = np.array([it.hi for it in items])
    rows = []
    for gi, g in enumerate(groups):
        if any(items[i].pid == "skin" for i in g):
            continue
        glo, ghi = lo[g].min(0), hi[g].max(0)
        cand = np.flatnonzero((lo <= ghi).all(1) & (hi >= glo).all(1))
        cand = [a for a in cand if items[a].group != gi]
        if skip_named:
            cand = [a for a in cand if not all(named_legit(items[a], items[b]) for b in g)]
        if not cand:
            continue
        C = None
        for a in cand:
            v, w = pts[a]
            inbox = np.flatnonzero(((v >= glo) & (v <= ghi)).all(1))
            if not len(inbox):
                continue
            if C is None:
                C = Region(items, g)
                if not C.solids:
                    break
            ins = inbox[C.inside(v[inbox])]
            if not len(ins):
                continue
            d, who = C.depth(v[ins])
            for b in np.unique(who):
                m = who == b
                rows.append((a, int(b), int(m.sum()), len(v), float(w[ins[m]].sum()), float(d[m].max()),
                             float(np.percentile(d[m], 90)), legit(items[a], items[b], v[ins[m]], d[m])))
        if not quiet and gi % 100 == 0:
            print(f"    group {gi}/{len(groups)} {time.time() - t0:.0f} s", flush=True)
    return rows


def pair_table(items, rows, least_mm=0.4):
    """The rows folded into pairs (a in b and b in a together), faults first, deepest first; a pair counts as a
    fault if either way is one and lies deeper than least_mm (the solids' grain)."""
    pairs = {}
    for r in rows:
        a, b = r[0], r[1]
        key = (min(a, b), max(a, b))
        pairs.setdefault(key, []).append(r)
    out = []
    for key, rs in pairs.items():
        faults = [r for r in rs if r[7] is None and r[5] > least_mm / 1000]
        worst = max(rs, key=lambda r: r[5])
        out.append((bool(faults), max((r[5] for r in faults), default=worst[5]), key, rs))
    out.sort(key=lambda x: (not x[0], -x[1]))
    return out


def write_table(path, sex, items, rows, least_mm=0.4):
    table = pair_table(items, rows, least_mm)
    lines = [f"# {sex}: pairs of structures where one's points lie inside the other's closed solid",
             "# verdict  deepest(mm)  pair: each way 'A in B: points in / A's points (share of A's surface), deepest "
             "and 90th percentile depth in mm, reason if legitimate'"]
    for fault, deep, (i, j), rs in table:
        ways = []
        for r in sorted(rs, key=lambda r: -r[5]):
            a, b = items[r[0]], items[r[1]]
            ways.append(f"{a.pid}/{a.short()} in {b.pid}/{b.short()}: {r[2]}/{r[3]} ({r[4]:.1%}), "
                        f"{r[5] * 1000:.1f} / {r[6] * 1000:.1f} mm" + (f" [{r[7]}]" if r[7] else ""))
        lines.append(f"{'FAULT' if fault else 'ok   '} {deep * 1000:6.1f}  " + " | ".join(ways))
    open(path, "w").write("\n".join(lines) + "\n")
    return table


def audit(folder, out_dir, tag, quiet=False):
    """Writes out_dir/audit_<tag>_<body>.txt for each body; returns {body: pair table}."""
    import time
    manifest = json.load(open(os.path.join(folder, "anatomy.json")))
    tables = {}
    for body in manifest["bodies"]:
        t = time.time()
        items = load_body(folder, body)
        groups = tile_groups(items)
        rows = audit_body(items, groups, quiet=quiet)
        tables[body["id"]] = (items, write_table(os.path.join(out_dir, f"audit_{tag}_{body['id']}.txt"), body["id"],
                                                 items, rows))
        if not quiet:
            n = sum(1 for x in tables[body["id"]][1] if x[0])
            print(f"{body['id']}: {len(items)} structures, {len(groups)} solids, {len(rows)} ways in, {n} faults "
                  f"({time.time() - t:.0f} s)", flush=True)
    return tables


# MARK: who gives way

FIXED_PARTS = ("eyes", "eye-muscles", "optic-nerves")   # the orbit's, tools/anatomy_eyes.py's: neither moved nor moved for
NOT_MINE = ((r"hepatic_portal_vein$", r"(?<!hepatic)_portal_vein$"),)   # one vein drawn twice: the vessels' own work
THIN = ("artery", "vein", "duct", "nerve")
MARGIN = 0.0005          # what gives way stops this far clear
MUSCLE_MARGIN = 0.001    # a muscle further: the fibres step smooths it after (Taubin), by up to about a millimetre
STEP = 0.002             # each round's moves scaled alike so the largest is this
ROUNDS = 40
DENT_SIGMA = 0.004       # a dent spread over at least this (by the surface each point stands for)
DENT_WIDEST = 0.015      # and at most this
SHIFT_SIGMA = 0.008      # a thin structure's shift over this, wider than it, so it moves across whole
SHIFT_MOST = 0.008       # and no point of it further than this
FINE = 0.0025            # where something gives way, its edges cut to this
REACH = 0.045            # how far a point looks along its way for the way out
STRETCH, STRETCH_MM = 3.0, 0.005    # no edge stretched past this many times its length, and this much longer
ALLOW = 20_000           # the triangles a body's structures may gain, cut finer (the atlas's 880,000: the fibres
                         # step makes the muscles about 70,000 more, so the muscles are not cut finer here)
TRACE = bool(os.environ.get("WHOLE_TRACE"))


def rank(it):
    """Who gives way to whom: the lower stays (see the module's account)."""
    t = it.tissue
    if t in ("bone", "tooth"):
        return 0
    if t in ("cartilage", "ligament"):
        return 1
    if it.pid == "skin":
        return 6
    if it.node.startswith("TS_") and not it.st.get("made"):
        return 5 if t == "muscle" else 4
    if t in THIN:
        return 3
    return 2


def mine(a, b):
    """Whether this step parts structures a and b: not the eye's, not two bones (the bones' own work), not one vein
    drawn twice."""
    if a.pid in FIXED_PARTS or b.pid in FIXED_PARTS:
        return False
    if rank(a) == 0 and rank(b) == 0:
        return False
    for x, y in NOT_MINE:
        if (re.search(x, a.node) and re.search(y, b.node)) or (re.search(x, b.node) and re.search(y, a.node)):
            return False
    return True


def volume(v, f):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    return abs(float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6)


class Group:
    """A group's structures as one welded mesh (their triangles wound out), each structure's points kept as they
    are: a structure moves by the field at its points, so points at one place move alike and a seam stays joined;
    one cut finer is rebuilt from the welded mesh."""
    def __init__(self, items, members):
        from anatomy_gaps import wound_out
        self.items, self.members = items, list(members)
        vs = [items[i].v for i in members]
        cut = np.cumsum([0] + [len(v) for v in vs])
        P = np.concatenate(vs)
        _, first, inv = np.unique(np.round(P * 1e7).astype(np.int64), axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        self.V = P[first]
        self.inv = [inv[cut[k]:cut[k + 1]] for k in range(len(members))]
        F, lab, self.flip = [], [], []
        for k, i in enumerate(members):
            f = inv[items[i].f + cut[k]]
            f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
            flip = not wound_out(items[i].v, items[i].f)
            self.flip.append(flip)
            F.append(f[:, ::-1] if flip else f)
            lab.append(np.full(len(f), k))
        self.F, self.lab = np.concatenate(F), np.concatenate(lab)
        self.n0 = len(self.V)
        self.counts = np.bincount(self.lab, minlength=len(members))

    def meshes(self):
        """Each member's new mesh: its own points moved, or, cut finer, rebuilt from the welded mesh."""
        out = []
        now = np.bincount(self.lab, minlength=len(self.members))
        for k, i in enumerate(self.members):
            if now[k] == self.counts[k]:
                out.append((self.V[self.inv[k]], self.items[i].f))
                continue
            g = self.F[self.lab == k]
            used = np.unique(g)
            at = np.full(len(self.V), -1)
            at[used] = np.arange(len(used))
            g = at[g]
            out.append((self.V[used], g[:, ::-1] if self.flip[k] else g))
        return out


def along(x, way, blocked, reach=REACH, h=0.0005):
    """How far each point x goes along its way (unit vectors) before it is clear (blocked() false): nan if not
    within reach."""
    t = np.full(len(x), np.nan)
    todo = np.arange(len(x))
    for k in range(1, int(round(reach / h)) + 1):
        if not len(todo):
            break
        q = x[todo] + way[todo] * k * h
        free = ~blocked(q)
        t[todo[free]] = k * h
        todo = todo[~free]
    return t


def unit(d):
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-12)


def relax(V, F, free, rounds=3, lam=0.5):
    """The points `free` (a mask) slid along the surface toward their neighbours' middle, each move's part along
    its normal taken off (a tangential Laplacian): the triangles a dent stretched evened out, the surface's shape
    kept. A point on a rim (an open edge) stays."""
    from scipy.sparse import coo_matrix
    from anatomy_gaps import vertex_normals
    E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    key, cnt = np.unique(np.sort(E, 1), axis=0, return_counts=True)
    free = free.copy()
    free[key[cnt == 1].ravel()] = False
    if not free.any():
        return V
    n = len(V)
    A = coo_matrix((np.ones(2 * len(key)), (np.r_[key[:, 0], key[:, 1]], np.r_[key[:, 1], key[:, 0]])),
                   shape=(n, n)).tocsr()
    deg = np.asarray(A.sum(1)).ravel()
    V = V.copy()
    for _ in range(rounds):
        nrm = vertex_normals(V, F)
        d = (A @ V) / np.maximum(deg, 1)[:, None] - V
        d -= (d * nrm).sum(1, keepdims=True) * nrm
        V[free] += lam * d[free]
    return V


def coarse(R, items):
    """A region's surface sampled about 1.5 mm apart (for what draws a structure that gives way)."""
    if not hasattr(R, "coarse"):
        from anatomy_gaps import face_samples
        pts = []
        for i in R.members:
            it = items[i]
            B, T, _ = face_samples(it.v, it.f, 0.0015)
            pts.append(np.einsum("sk,skc->sc", B, it.v[it.f[T]]))
        R.coarse = np.unique(np.round(np.concatenate(pts) * 1e5), axis=0) / 1e5
    return R.coarse


def give(G, regions, how, room, items, margin=None):
    """The group G moved off the obstacles' solids (regions) as `how` says: "dent", each point inside one goes in
    along its normal (the inward one) until clear, and each of their surface's samples inside it draws its
    nearest point in past it; "out" (the skin, which holds everything), each point out along its normal and the
    samples outside it draw it out; "shift" (a thin tube), each run of its points inside one (points within
    4 mm) goes one way, the way out nearest the run, until clear. Each round's moves spread over the mesh by the
    surface each point stands for (tools/anatomy_gaps.py spread_moves, a smooth field fading as a Gaussian of
    the distance from them), scaled alike so the largest is STEP; the spread is wider for a deeper dent (0.6 of
    its depth, DENT_SIGMA to DENT_WIDEST), so a structure pushed far gives way over as wide a stretch, not in a
    pit. The round that leaves the fewest inside is kept, and the rounds stop before an edge stretches past
    STRETCH times its length. Where it gives way, it is first cut finer (edges to FINE, each new point faired:
    tools/anatomy_gaps.py refine and fair), as far as `room` triangles allow. Returns (its points inside and the
    samples drawn in before, after, the largest move, triangles added)."""
    from anatomy_gaps import spread_moves, vertex_area, vertex_normals, refine, fair
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    margin = MARGIN if margin is None else margin
    lo, hi = G.V.min(0) - 0.01, G.V.max(0) + 0.01
    regions = [R for R in regions if (R.lo < hi).all() and (R.hi > lo).all()]
    if not regions:
        return (0, 0), (0, 0), 0.0, 0
    S = np.concatenate([coarse(R, items) for R in regions])
    S = S[((S >= lo) & (S <= hi)).all(1)]
    stree = cKDTree(S) if len(S) else None

    def blocked(q):
        out = np.zeros(len(q), bool)
        for R in regions:
            box = ((q >= R.lo) & (q <= R.hi)).all(1)
            if box.any():
                out[box] |= R.inside(q[box])
        return out

    def drawn(V, F):
        """The obstacles' samples on the wrong side of G's surface: inside it, or (the skin) outside it."""
        if how == "shift" or not len(S):
            return np.zeros(len(S), bool)
        ins = Winding(V, F, s=0.001 if how == "out" else 0.0005).inside(S)
        if how == "out":
            return ~ins & np.isfinite(cKDTree(V).query(S, distance_upper_bound=0.03)[0])
        return ins

    def ways(V, ins):
        """Each point inside an obstacle: its way out and how far."""
        x = V[ins]
        if how == "shift":
            pairs = cKDTree(x).query_pairs(0.004, output_type="ndarray")
            _, run = connected_components(coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])),
                                                     shape=(len(x), len(x))), directed=False)
            toward = unit(S[stree.query(x)[1]] - x)
            way = np.zeros_like(x)
            for r in np.unique(run):
                m = run == r
                w = toward[m].mean(0)
                if np.linalg.norm(w) < 0.3:
                    c = x[m].mean(0)
                    w = S[stree.query(c)[1]] - c
                way[m] = w / max(np.linalg.norm(w), 1e-12)
        else:
            way = vertex_normals(V, G.F)[ins] * (1 if how == "out" else -1)
        t = along(x, way, blocked)
        lost = np.isnan(t)
        if lost.any() and stree is not None:      # no way out along it within reach: the nearest
            d = S[stree.query(x[lost])[1]] - x[lost]
            way[lost], t[lost] = unit(d), np.linalg.norm(d, axis=1)
        return x, way, t

    held = np.zeros(len(G.V), bool)
    if how == "shift":                    # a thin tube's cut ends stay where they join the next
        for k, i in enumerate(G.members):
            c, r = rims(G.items[i])
            for cc, rr in zip(c, r):
                held[G.inv[k][np.linalg.norm(G.items[i].v - cc, axis=1) < 1.5 * rr + 0.002]] = True
    # how deep it must give, and so how widely
    ins, dr = blocked(G.V) & ~held, drawn(G.V, G.F)
    first = (int(ins.sum()), int(dr.sum()))
    if not sum(first):
        return first, first, 0.0, 0
    deep = []
    if ins.any():
        deep.append(ways(G.V, ins)[2])
    if dr.any():
        deep.append(cKDTree(G.V).query(S[dr])[0])
    depth = float(np.percentile(np.concatenate(deep), 90))
    sigma = SHIFT_SIGMA if how == "shift" else float(np.clip(0.6 * depth, DENT_SIGMA, DENT_WIDEST))
    # cut finer where it gives way
    added, n0 = 0, len(G.F)
    if how != "shift":
        normal = vertex_normals(G.V, G.F)
        for _ in range(4):
            contact = np.concatenate([G.V[blocked(G.V)], S[drawn(G.V, G.F)]])
            if not len(contact):
                break
            mid = G.V[G.F].mean(1)
            near = np.flatnonzero(np.isfinite(cKDTree(contact).query(mid, distance_upper_bound=2 * sigma)[0]))
            if len(G.F) - n0 + 3 * len(near) > room:
                break
            V, F, lab, normal, cut = refine(G.V, G.F, G.lab, near, FINE, normal)
            if not cut:
                break
            G.V, G.F, G.lab = V, F, lab
        if len(G.V) > G.n0:
            G.V = fair(G.V, G.F, np.arange(G.n0, len(G.V)), vertex_normals(G.V, G.F))
            held = np.concatenate([held, np.zeros(len(G.V) - len(held), bool)])
        added = len(G.F) - n0
    V0 = G.V.copy()
    E = np.concatenate([G.F[:, [0, 1]], G.F[:, [1, 2]], G.F[:, [2, 0]]])
    L0 = np.linalg.norm(V0[E[:, 0]] - V0[E[:, 1]], axis=1)
    keep = np.ones(len(G.V))
    if held.any():
        keep = 1 - np.exp(-cKDTree(G.V[held]).query(G.V)[0] ** 2 / (2 * (sigma / 2) ** 2))
    V, best = G.V, None
    for done in range(ROUNDS + 1):
        ins = blocked(V) & ~held
        dr = drawn(V, G.F)
        count = (int(ins.sum()), int(dr.sum()))
        if TRACE:
            print(f"      round {done}: {count}, sigma {sigma * 1000:.1f} mm, moved {np.linalg.norm(V - V0, axis=1).max() * 1000:.1f} mm", flush=True)
        if best is None or sum(count) < sum(best[0]):
            best = (count, V)
        if not sum(count) or done == ROUNDS:
            break
        area = vertex_area(V, G.F)
        at, D, a = [], [], []
        if ins.any():
            x, way, t = ways(V, ins)
            at.append(x)
            D.append(way * (t + margin)[:, None])
            a.append(area[ins])
        if dr.any():
            b = S[dr]
            j = cKDTree(V).query(b)[1]
            d = b - V[j]
            at.append(V[j])
            D.append(d + unit(d) * margin)
            a.append(np.full(len(b), 0.0015 ** 2))
        q = spread_moves(V, np.concatenate(at), np.concatenate(D), np.concatenate(a), sigma, STEP, True, alike=True)
        q = V + (q - V) * keep[:, None]
        if how == "shift":                 # a tube: no edge stretched past STRETCH times its length, all told
            d = q - V0
            n = np.linalg.norm(d, axis=1, keepdims=True)
            q = V0 + d * np.minimum(1, SHIFT_MOST / np.maximum(n, 1e-12))
            L, was = np.linalg.norm(q[E[:, 0]] - q[E[:, 1]], axis=1), L0
            torn = (L > STRETCH * was) & (L - was > STRETCH_MM)
        else:                              # a dent: none torn in a round, then the triangles evened out
            L, was = np.linalg.norm(q[E[:, 0]] - q[E[:, 1]], axis=1), np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)
            torn = (L > 2 * was) & (L - was > 0.002)
        if torn.any():
            if TRACE:
                print(f"      stopped: {int(torn.sum())} edges would stretch", flush=True)
            break
        if how != "shift":
            q = relax(q, G.F, np.linalg.norm(q - V0, axis=1) > 0.0002)
        V = q
    G.V = best[1]
    return first, best[0], float(np.linalg.norm(G.V - V0, axis=1).max()), added


def priority(items, g, vol):
    """A group's place in the order of giving way: (its rank, less its volume); the lower stays."""
    return (min(rank(items[i]) for i in g), -vol)


def legit_pair(a, b):
    return bool(named_legit(a, b) or named_legit(b, a))


def part_body(folder, body, quiet=False, only=None):
    """One body's structures moved off what they pass into, the lower in the order giving way (see the module's
    account); their parts rewritten. Returns an account."""
    import time
    from anatomy_bones import rewrite
    t0 = time.time()
    items = load_body(folder, body)
    groups = tile_groups(items)
    rows = audit_body(items, groups)
    vols = []
    for g in groups:
        v, f = joined(items, g)
        vols.append(volume(*capped(v, f)))
    key = [priority(items, g, vols[k]) for k, g in enumerate(groups)]
    faults = {}
    for r in rows:
        a, b = items[r[0]], items[r[1]]
        if r[7] is not None or r[5] <= 0.0004 or not mine(a, b):
            continue
        ga, gb = a.group, b.group
        mover, stay = (ga, gb) if key[ga] > key[gb] else (gb, ga)
        faults.setdefault(mover, set()).add(stay)
    regions = {}

    def region(g, against):
        members = [b for b in groups[g] if not items[b].inner
                   and not any(legit_pair(items[a], items[b]) for a in groups[against])]
        k = (g, tuple(members))
        if k not in regions:
            regions[k] = Region(items, members) if members else None
        return regions[k]
    total = 0
    said, dirty = [], set()
    for m in sorted(faults, key=lambda g: key[g]):
        if only and not any(re.search(only, items[i].node) for i in groups[m]):
            continue
        lo = np.min([items[i].lo for i in groups[m]], 0) - 0.01
        hi = np.max([items[i].hi for i in groups[m]], 0) + 0.01
        stays = set(faults[m])
        if any(items[i].pid == "skin" for i in groups[m]):
            how = "out"
        elif all(items[i].tissue in THIN for i in groups[m]):
            how = "shift"
        else:
            how = "dent"
        for g, gr in enumerate(groups):          # a tube shifted: whatever stays that it could be moved into
            if how != "shift" or g == m or key[g] >= key[m] or g in stays:
                continue
            glo = np.min([items[i].lo for i in gr], 0)
            ghi = np.max([items[i].hi for i in gr], 0)
            if (glo < hi).all() and (ghi > lo).all() and all(mine(items[a], items[b]) for a in groups[m] for b in gr):
                stays.add(g)
        obstacles = [region(g, m) for g in sorted(stays)]
        obstacles = [R for R in obstacles if R is not None and R.solids]
        if not obstacles:
            continue
        G = Group(items, groups[m])
        room = 0 if any(items[i].tissue == "muscle" for i in groups[m]) else max(0, ALLOW - total)
        muscle = any(items[i].tissue == "muscle" for i in groups[m])
        before, after, most, added = give(G, obstacles, how, room, items, MUSCLE_MARGIN if muscle else MARGIN)
        if most <= 1e-6 and not added:
            continue
        total += added
        for i, (v, f) in zip(groups[m], G.meshes()):
            it = items[i]
            it.v, it.f = np.asarray(v, np.float64), np.asarray(f, np.int64)
            it.lo, it.hi = it.v.min(0), it.v.max(0)
            dirty.add(it.pid)
        for k in [k for k in regions if k[0] == m]:
            del regions[k]
        names = ", ".join(items[i].short() for i in groups[m][:3]) + (f" (+{len(groups[m]) - 3})" if len(groups[m]) > 3 else "")
        line = (f"{names} [{how}] off {len(stays)}: {before[0]}->{after[0]} of its points in them and {before[1]}->"
                f"{after[1]} of their samples in it, moved up to {most * 1000:.1f} mm"
                + (f", {added} triangles added" if added else ""))
        said.append(line)
        if not quiet:
            print(f"    {body['id']}: {line} ({time.time() - t0:.0f} s)", flush=True)
    parts = {p["id"]: p for p in body["parts"]}
    for pid in sorted(dirty):
        meshes = [(it.v, it.f) for it in sorted((it for it in items if it.pid == pid), key=lambda it: it.k)]
        rewrite(folder, parts[pid], meshes)
    return f"{len(said)} groups moved ({time.time() - t0:.0f} s): " + "; ".join(said)


def remake(folder, quiet=False):
    """Moves each body's structures in `folder`'s atlas (anatomy.json and its part files) off what they pass into;
    does nothing for a body done already (its manifest's "whole"). Returns what it did."""
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if body.get("whole"):
            continue
        said.append(f"{body['id']}: {part_body(folder, body, quiet)}")
        body["whole"] = True
        json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    return "; ".join(said) or "whole already"


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--audit":
        audit(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 2:
        print(remake(sys.argv[1]))
    else:
        sys.exit("anatomy_whole.py ATLAS_FOLDER | --audit ATLAS_FOLDER OUT_DIR TAG")
