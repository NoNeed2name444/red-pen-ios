#!/usr/bin/env python3
"""The skull, vertebrae, sacrum and coccyx from scans of real bone, in place
of the atlas's own. Run by tools/anatomy_atlas.py once the atlas is written
and before tools/anatomy_fibres.py lays the muscles' bundles (the gluteus
maximus and the iliopsoas arise on these bones), or on a built atlas on its
own:

    python3 -I tools/anatomy_bones.py --vhskull vhm_skull_0-nih3d.glb \\
        --ka25 <folder holding KA 25's OBJ files> [--atlas DIR] [--cache DIR]

Why: the organ sets' vertebrae are simplified to 280 to 800 triangles each,
from a CT 1 mm apart, so they are blocks with rounded corners and stubs for
processes; and each body's skull meshed from its head CT
(tools/anatomy_skull.py) has the right size and shape for its body but is
lumpy where the CT's bone is thin, and its two sides differ. Two scans of
real bone take their place, each fitted onto the bone it replaces, so
nothing else in the body moves:

- NIH 3D 3DPX-012260, the Visible Human Male's skull (the same man as the
  male body), segmented from his CT and finished whole by NLM for 3D
  printing: cranium and mandible, the teeth in their sockets (CC BY 4.0);
- KA 25, a whole spine from one dry skeleton (Department of Anthropology,
  Lomonosov Moscow State University): every vertebra, the sacrum and the
  coccyx scanned at 0.15 mm with an Artec Space Spider (CC BY 4.0). Its
  column has thirteen thoracic vertebrae.

The skull, for each body:
1. The scan's two largest pieces are the cranium and the mandible (eight
   triangles of debris left out), simplified gently (as the atlas
   simplifies everything) to 90,000 and 16,000 triangles.
2. Each placed on the body's own skull, the cranium on its bones but the
   mandible and the mandible on the mandible, by the similarity (one scale,
   a turn and a move) that best lays it there: trimmed two-sided ICP from
   24 starts, the scan's principal axes laid on the skull's every way round.
3. The woman's is the man's scan, so placed on her skull, then bent onto it
   by a field smooth through space (Gaussian, 20 mm down to 8 mm, each
   round taking 70% of what is left; then the whole bend smoothed at 6
   mm), so it takes her skull's size and shape and keeps its own detail and
   teeth; smooth through space rather than along the surface, so the thin
   plates lying close together (the sinuses' walls) move together.
4. Turned about its middle so its plane of symmetry (the plane the surface
   is most nearly a mirror image about) is the body's.
5. Its teeth found, in the man: within 9 mm (across) of the organ set's
   tooth row, and no further from the jaw's biting surface (a smooth fit to
   the tips of its teeth) than a crown and the little root a dry skull
   shows for that place in the arch (incisors 11.5 mm, canines 12,
   premolars 10 to 9, molars 8.5); a bare ridge where a tooth is missing
   lies short of the biting surface and is left as bone. The woman's are
   the man's.
6. Its two sides evened out: each point pulled toward the mirror image of
   its match on the other side (their normals agreeing, within 5 mm), the
   pulls smoothed through space (6 mm), half taken, three rounds; the
   teeth pull nothing, each tooth keeping its own shape, but ride along.
7. Split into the atlas's bones, in the man: seeds where one of the CT
   skull's bones is clearly the nearest (within 1.2 mm, and 1.5 mm nearer
   than the next), the right side's seeds the mirror image of the left's,
   grown over the surface with crossing an inward fold made costly, so the
   bones part along the scan's own sutures and folds; the teeth as found;
   specks folded into the piece around them. The woman's is the man's
   split, carried over triangle for triangle.
8. The organ sets' tooth rows, in the mouth, give way to the scan's teeth,
   which join the skull's part under the same names.

The spine, for each body:
1. Each file of KA 25 (its MD5 as figshare lists it) brought down to
   60,000 triangles, then simplified gently to 12,000 for fitting and to a
   triangle per 2.5 mm² of its placed surface for the atlas (as the
   skull's), never under 1,000.
2. Each vertebra and the sacrum placed on the organ set's own by a
   similarity found as the skull's; the man's seventh to twelfth thoracic
   vertebrae are KA 25's eighth to thirteenth (its seventh left out), and
   the woman's six lumbar vertebrae are KA 25's five, its third used twice.
   The two pieces of the coccyx (its first segment, and the second to
   fourth fused) were scanned in the sacrum's frame, so the sacrum's
   similarity places them too, on its tip. The intervertebral discs are
   the organ sets'.

On an atlas already done (its manifest lists both sources) it does nothing;
the same inputs give the same bytes. Needs numpy, scipy and
fast-simplification 0.2. The inputs are downloaded files: run this with
python3 -I from outside their folders. --cache keeps each KA 25 file's
60,000-triangle first pass (with its MD5), so a rebuild need not read the
2 GB of OBJ files again.
"""
import argparse
import hashlib
import itertools
import json
import os
import sys

import numpy as np
import fast_simplification
from scipy.ndimage import gaussian_filter, map_coordinates
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components, dijkstra
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anatomy_fibres import read_part, write_part, sha256  # noqa: E402

VHSKULL_SOURCE = {
    "id": "nih3d-3dpx-012260",
    "title": "Visible Human Male Skull (NIH 3D, 3DPX-012260)",
    "creators": "kbrowne (NLM 3D: Anatomy)",
    "doi": None,
    "url": "https://3d.nih.gov/entries/3DPX-012260",
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
    "basis": "The Visible Human Male, U.S. National Library of Medicine",
    "sha256": "5520142d71db2fda58c6f7fb2ceefcac9f97a47aaaede40064d5741e2e363d9a",
}
# The OBJ files used, with the MD5 figshare lists for each (T7.obj, which no
# body needs, and the textures are not read).
KA25_MD5 = {
    "C1.obj": "5fc4cc2c46c67000a43e8bc8af649d3a", "C2.obj": "4d8017508fd417356dd35e7f35762f70",
    "C3.obj": "0dfdc471dd0b39389daa9cf42feaba7c", "C4.obj": "23ceb2b419e5a3c7ce5b05780280b3be",
    "C5.obj": "6828bfe6cbd72eb6bf45b627b72dc0b6", "C6.obj": "1469a875f2fa5b2c7baeed879930a25e",
    "C7.obj": "b7eb4d417ed849ce347b8022d25a8a73",
    "T1.obj": "37f292c8fc62a8c73a80f6582dbe6e15", "T2.obj": "b3c5a346f4ef1c8320fc2fdce499e845",
    "T3.obj": "da2f1214307a2eef53a6dbbbf6fcd5f4", "T4.obj": "f6dfa13bd2c2c0beb0ce2c208669db85",
    "T5.obj": "66787df5fb23ec535207b7e9e7a62e6f", "T6.obj": "74e82a0173e29bcef210ef50f1e16ac5",
    "T8.obj": "e2580435447cc144f03d8ab767a5aade", "T9.obj": "5584b818f96b28dcedad6bebdc4cfd4a",
    "T10.obj": "14ea816ed47021be9ff16363b885ca3e", "T11.obj": "4eaf7479189fe7e6d0e2ed5df1abce37",
    "T12.obj": "ed5df9e460e6e574981085010b757530", "T13.obj": "5d1dc869060e6f2e281cddb71f48bc7e",
    "L1.obj": "8fb1f751801b80f38857e9769e106e99", "L2.obj": "a4e98f9e94c4140155f55281becb8951",
    "L3.obj": "c9869733bcbda129c8ab32fccc50b312", "L4.obj": "221fb7042459e1162360c43236e2a145",
    "L5.obj": "589d7b8c5690268bdd87559e79100a24",
    "Sacrum.obj": "c93cffd328bb1c52995e69ac70660405",
    "Coccyx1.obj": "e8b6d5862d2293cf41fa3dfb597f1c79", "Coccyx2-4.obj": "3740be22cc6b625961102d4dca0f92e8",
}
KA25_SOURCE = {
    "id": "figshare-ka25-vertebrae",
    "title": "3D model of the entire set of vertebrae of human vertebral column (KA 25), version 2",
    "creators": "Natalya Prilepskaya, Ruslan Belyaev and Alexander Kuznetsov (Department of Anthropology, "
                "Lomonosov Moscow State University)",
    "doi": "https://doi.org/10.6084/m9.figshare.11879133.v2",
    "url": "https://figshare.com/articles/media/3D_model_of_the_entire_set_of_vertebrae_of_human_vertebral_column_KA_25_/11879133",
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
    # the SHA-256 of the lines "<file> <its MD5>\n" for the files used, in name order
    "sha256": hashlib.sha256("".join(f"{k} {KA25_MD5[k]}\n" for k in sorted(KA25_MD5)).encode()).hexdigest(),
}

# The manifest's account of what this step changed.
CHANGES = (
    " Then the skull, vertebrae, sacrum and coccyx replaced by scans of real bone: the skull by NIH 3D's "
    "of the Visible Human Male's skull (3DPX-012260), simplified gently, placed on each body's own skull by "
    "a similarity, bent onto the woman's by a field smooth through space, turned to the body's plane of "
    "symmetry and its sides evened out by a smooth field, and split into the CT skull's bones along the "
    "scan's own sutures and folds, its teeth, found by their height above the biting surface, in place of "
    "the organ sets' tooth rows; each vertebra, the sacrum and the coccyx by the same bone of one dry "
    "skeleton scanned at 0.15 mm (KA 25, figshare), simplified to a triangle per 2.5 mm² and placed on the "
    "organ set's by a similarity, the coccyx by the sacrum's (the man's seventh to twelfth thoracic "
    "vertebrae are the scan's eighth to thirteenth; the woman's six lumbar vertebrae are its five, its "
    "third used twice)."
)

CRANIUM, MANDIBLE = 90_000, 16_000   # the skull's triangles
SKULL_FIT = 20_000                   # its triangles for fitting
KA_FIRST, KA_FIT = 60_000, 12_000    # KA 25's first pass and its triangles for fitting
SPINE_MM2, BONE_FLOOR = 2.5, 1000    # a triangle per 2.5 mm² of the placed bone's surface, never under 1,000
KINDS = ("cervical", "thoracic", "lumbar")


def log(*a):
    print(*a, flush=True)


# MARK: placing one surface on another: a similarity, by ICP from every way round

def sample(v, f, n, seed=11):
    """n points spread evenly over the surface (by area), with their triangles' normals."""
    rng = np.random.default_rng(seed)
    a = v[f[:, 1]] - v[f[:, 0]]; b = v[f[:, 2]] - v[f[:, 0]]
    area = 0.5 * np.linalg.norm(np.cross(a, b), axis=1)
    t = rng.choice(len(f), n, p=area / area.sum())
    r1, r2 = rng.random(n), rng.random(n)
    s = np.sqrt(r1)
    w0, w1, w2 = 1 - s, s * (1 - r2), s * r2
    p = v[f[t, 0]] * w0[:, None] + v[f[t, 1]] * w1[:, None] + v[f[t, 2]] * w2[:, None]
    nrm = np.cross(a[t], b[t]); nrm /= np.maximum(np.linalg.norm(nrm, axis=1), 1e-12)[:, None]
    return p, nrm


def umeyama(src, dst):
    """The similarity (s, R, t) taking src onto dst by least squares."""
    ms, md = src.mean(0), dst.mean(0)
    xs, xd = src - ms, dst - md
    U, S, Vt = np.linalg.svd(xd.T @ xs / len(src))
    D = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt
    s = (S * np.diag(D)).sum() / (xs ** 2).sum() * len(src)
    return s, R, md - s * R @ ms


def turns():
    """Every way to lay one set of axes on another (the 24 signed permutations, no mirror images), and
    between them every turn about one axis in 30 degree steps: 168 starts. Where two of a bone's axes are
    nearly as long as each other (the skull's width and height) they are found only loosely, and the 24
    alone can all start more than 30 degrees from the right place."""
    group = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            M = np.zeros((3, 3))
            for i, (p, sg) in enumerate(zip(perm, signs)):
                M[i, p] = sg
            if np.linalg.det(M) > 0:
                group.append(M)
    out, seen = [], set()
    for D in group:
        for k in range(3):
            i, j = [x for x in range(3) if x != k]
            for deg in (0, 30, 60):
                a = np.radians(deg)
                T = np.eye(3); T[i, i] = T[j, j] = np.cos(a); T[i, j], T[j, i] = -np.sin(a), np.sin(a)
                M = D @ T
                key = tuple(np.round(M, 6).ravel())
                if key not in seen:
                    seen.add(key); out.append(M)
    return out


def icp(P, PN, T, TN, tree, s, R, t, rounds=40, trim=0.9):
    """Similarity ICP, both ways (each surface's points to the other's nearest), the worst tenth left out."""
    for _ in range(rounds):
        Q = (s * (R @ P.T)).T + t
        d1, i1 = tree.query(Q)
        d2, i2 = cKDTree(Q).query(T)
        k1, k2 = d1 <= np.quantile(d1, trim), d2 <= np.quantile(d2, trim)
        s, R, t = umeyama(np.vstack([P[k1], P[i2[k2]]]), np.vstack([T[i1[k1]], T[k2]]))
    Q = (s * (R @ P.T)).T + t
    d1, i1 = tree.query(Q); d2, _ = cKDTree(Q).query(T)
    agree = float(np.mean(((R @ PN.T).T * TN[i1]).sum(1)))
    return s, R, t, 0.5 * (d1.mean() + d2.mean()), agree


def angle(R1, R2):
    return float(np.degrees(np.arccos(np.clip((np.trace(R1.T @ R2) - 1) / 2, -1, 1))))


def similarity(v, f, tv, tf, n=2500, coarse=800, keep=6):
    """The places found, best first: (mean distance, normals' agreement, s, R, t), taking v onto tv. Every
    start (turns()) is tried with a short ICP on a few points, and the best few places, each 10 degrees
    from the others, are then refined on all of them."""
    P, PN = sample(v, f, n)
    T, TN = sample(tv, tf, n)
    tree, few = cKDTree(T), cKDTree(T[:coarse])
    cT, cP = T.mean(0), P.mean(0)
    s0 = np.sqrt(((T - cT) ** 2).sum(1).mean() / ((P - cP) ** 2).sum(1).mean())
    eT = np.linalg.eigh(np.cov((T - cT).T))[1]
    eP = np.linalg.eigh(np.cov((P - cP).T))[1]
    if np.linalg.det(eT) < 0:
        eT[:, 0] *= -1
    if np.linalg.det(eP) < 0:
        eP[:, 0] *= -1
    tried = []
    for D in turns():
        R0 = eT @ D @ eP.T
        s, R, t, score, _ = icp(P[:coarse], PN[:coarse], T[:coarse], TN[:coarse], few, s0, R0, cT - s0 * R0 @ cP, rounds=12)
        tried.append((score, s, R, t))
    tried.sort(key=lambda r: r[0])
    chosen = []
    for r in tried:
        if all(angle(r[2], c[2]) > 10 for c in chosen):
            chosen.append(r)
            if len(chosen) == keep:
                break
    found = []
    for _, s, R, t in chosen:
        s, R, t, score, agree = icp(P, PN, T, TN, tree, s, R, t)
        found.append((score, agree, s, R, t))
    found.sort(key=lambda r: r[0])
    return found


def placed(v, fit):
    s, R, t = fit
    return (s * (R @ v.T)).T + t


def report(name, found):
    """The fit's error, and a warning where another start found a different place nearly as good."""
    best = found[0]
    rival = next((r for r in found[1:] if angle(best[3], r[3]) > 20), None)
    note = ""
    if rival is not None and rival[0] - best[0] < 0.0003:
        note = f" (another placement, {rival[0] * 1000:.2f} mm, is nearly as good: check it)"
    assert best[0] < 0.006, f"{name}: the best fit is {best[0] * 1000:.1f} mm off"
    return f"{name}: {best[0] * 1000:.2f} mm, scale {best[2]:.3f}{note}"


# MARK: fields smooth through space (not along a surface, so sheets lying close together move together)

class Grid:
    def __init__(self, points, spacing, pad):
        self.lo = points.min(0) - pad
        self.h = spacing
        self.shape = tuple(np.ceil((points.max(0) + pad - self.lo) / spacing).astype(int) + 1)

    def splat(self, p, values):
        """Per-point values (n, k) spread into the grid, trilinearly."""
        g = (p - self.lo) / self.h
        i0 = np.floor(g).astype(int); t = g - i0
        out = np.zeros(self.shape + (values.shape[1],))
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (t[:, 0] if dx else 1 - t[:, 0]) * (t[:, 1] if dy else 1 - t[:, 1]) * (t[:, 2] if dz else 1 - t[:, 2])
                    idx = tuple(np.clip(i0[:, k] + d, 0, self.shape[k] - 1) for k, d in enumerate((dx, dy, dz)))
                    np.add.at(out, idx, values * w[:, None])
        return out

    def sample(self, field, p):
        c = ((p - self.lo) / self.h).T
        return np.stack([map_coordinates(field[..., k], c, order=1, mode="nearest") for k in range(field.shape[-1])], 1)


def smooth_field(p, d, w, sigma, spacing=0.003, floor=0.3):
    """The weighted mean of the moves d (n, 3) at the points p, smoothed by a Gaussian of sigma (metres)
    through space and read back at p; where little weight reaches it fades rather than following a few."""
    g = Grid(p, spacing, 3 * sigma)
    acc = g.splat(p, np.concatenate([d * w[:, None], w[:, None]], 1))
    for k in range(4):
        acc[..., k] = gaussian_filter(acc[..., k], sigma / spacing, mode="constant", truncate=3.0)
    num, den = g.sample(acc[..., :3], p), g.sample(acc[..., 3:], p)[:, 0]
    ref = np.median(den[w > 0]) if (w > 0).any() else 1.0
    return num / np.maximum(den, floor * ref)[:, None]


def vertex_normals(v, f):
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]


def neighbours(f, n):
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    A = coo_matrix((np.ones(2 * len(e)), (np.concatenate([e[:, 0], e[:, 1]]), np.concatenate([e[:, 1], e[:, 0]]))),
                   shape=(n, n)).tocsr()
    A.data[:] = 1.0
    return A


def warp(v, f, tv, tf, sigmas_mm=(40, 30, 22, 16), reach_mm=(10, 8, 6, 5), rounds=4, share=0.7):
    """The surface (v, f) bent onto the target (tv, tf) by a field smooth through space, coarse to fine and
    never finer than its last scale, so the target's shape is taken and the surface's own detail kept.
    Pulls both ways (each point to the target's nearest with a facing normal, and each target point back to
    the surface's nearest), so a thin or missing stretch of either still pulls."""
    v = v.copy(); v0 = v.copy()
    tp = np.vstack([tv, tv[tf].mean(1)])
    fn = np.cross(tv[tf[:, 1]] - tv[tf[:, 0]], tv[tf[:, 2]] - tv[tf[:, 0]])
    tn = np.vstack([vertex_normals(tv, tf), fn / np.maximum(np.linalg.norm(fn, axis=1), 1e-15)[:, None]])
    tree = cKDTree(tp)
    for sig, reach in zip(sigmas_mm, reach_mm):
        for _ in range(rounds):
            vn = vertex_normals(v, f)
            d1, j1 = tree.query(v, k=4)
            d1 = np.where((tn[j1] * vn[:, None, :]).sum(2) > 0.3, d1, np.inf)
            b = d1.argmin(1)
            dd, jj = d1[np.arange(len(v)), b], j1[np.arange(len(v)), b]
            w1 = (dd < reach * 1e-3).astype(float)
            pull = (tp[jj] - v) * w1[:, None]
            d2, j2 = cKDTree(v).query(tp)
            ok = ((tn * vn[j2]).sum(1) > 0.3) & (d2 < reach * 1e-3)
            acc = np.zeros_like(v); cnt = np.zeros(len(v))
            np.add.at(acc, j2[ok], tp[ok] - v[j2[ok]]); np.add.at(cnt, j2[ok], 1.0)
            back = acc / np.maximum(cnt, 1)[:, None]
            wsum = w1 + (cnt > 0)
            d = (pull + back * (cnt > 0)[:, None]) / np.maximum(wsum, 1)[:, None]
            v = v + share * smooth_field(v, d, (wsum > 0).astype(float), sig * 1e-3 / 2.0)
        dd, _ = tree.query(v)
        log(f"      {sig} mm: {dd.mean() * 1000:.2f} mm from her skull on average")
    # the whole bend smoothed once more at 6 mm, so no dent or flipped sliver is left in it
    return v0 + smooth_field(v0, v - v0, np.ones(len(v)), 0.006)


# MARK: symmetry

def best_plane(v, rounds=30, sample_n=20000, seed=5):
    """The plane (n, d: n.x = d) the surface is most nearly a mirror image about, from x = its median."""
    rng = np.random.default_rng(seed)
    p = v[rng.choice(len(v), min(sample_n, len(v)), replace=False)]
    tree = cKDTree(v)
    n = np.array([1.0, 0, 0]); d = float(np.median(p @ n))
    for _ in range(rounds):
        dist, j = tree.query(p - 2 * ((p @ n) - d)[:, None] * n)
        keep = dist < np.quantile(dist, 0.8)
        a, b = p[keep], v[j[keep]]          # b is a's mirror image
        nn = np.linalg.svd(a - b, full_matrices=False)[2][0]
        nn = nn if nn @ n > 0 else -nn
        mid = 0.5 * (a + b); c = mid.mean(0)
        cand = np.linalg.svd(mid - c, full_matrices=False)[2][2]
        n = (cand if cand @ nn > 0 else -cand) / np.linalg.norm(cand)
        d = float(c @ n)
    dist, _ = tree.query(p - 2 * ((p @ n) - d)[:, None] * n)
    return n, d, float(np.mean(dist))


def asymmetry(v, x0):
    """The mean distance from each point's mirror image (about x = x0) to the nearest point."""
    q = v.copy(); q[:, 0] = 2 * x0 - q[:, 0]
    return float(cKDTree(v).query(q)[0].mean())


def symmetrize(v, f, x0, hold, rounds=3, reach=0.005, share=0.5, sigma=0.006):
    """The surface bent toward its own mirror image about x = x0: each point pulled toward the mirror image of
    its match (normals agreeing, within reach), the pulls smoothed through space, so only the broad
    differences between the sides go and the surface's own detail stays. Points in `hold` pull nothing."""
    v = v.copy(); n = len(v)
    for _ in range(rounds):
        vn = vertex_normals(v, f)
        q = v.copy(); q[:, 0] = 2 * x0 - q[:, 0]
        qn = vn.copy(); qn[:, 0] = -qn[:, 0]
        dist, j = cKDTree(v).query(q, k=8)
        dist = np.where((vn[j] * qn[:, None, :]).sum(2) > 0.5, dist, np.inf)
        best = np.argmin(dist, 1)
        bd, bj = dist[np.arange(n), best], j[np.arange(n), best]
        target = v[bj].copy(); target[:, 0] = 2 * x0 - target[:, 0]
        w = (bd < reach).astype(float); w[hold] = 0.0
        v = v + share * smooth_field(v, (target - v) * w[:, None], w, sigma)
    return v


# MARK: splitting a surface into named pieces along its own folds

def edge_faces(f):
    """Each edge two triangles share, and the two."""
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    t = np.tile(np.arange(len(f)), 3)
    key = e[:, 0].astype(np.int64) * (f.max() + 1) + e[:, 1]
    o = np.argsort(key, kind="stable"); ks = key[o]
    same = np.nonzero(ks[1:] == ks[:-1])[0]
    return e[o[same]], t[o[same]], t[o[same + 1]]


def crease_costs(v, f, K=30.0):
    """The surface as a graph whose edges cost their length times 1 + K x how sharply they fold inward."""
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1), 1e-15)[:, None]
    cen = v[f].mean(1)
    E, t1, t2 = edge_faces(f)
    bend = 1.0 - np.clip((fn[t1] * fn[t2]).sum(1), -1, 1)
    fold = np.where(((cen[t2] - cen[t1]) * fn[t1]).sum(1) > 0, bend, 0.1 * bend)
    w = np.linalg.norm(v[E[:, 0]] - v[E[:, 1]], axis=1) * (1.0 + K * fold) + 1e-9
    return coo_matrix((np.concatenate([w, w]), (np.concatenate([E[:, 0], E[:, 1]]), np.concatenate([E[:, 1], E[:, 0]]))),
                      shape=(len(v), len(v))).tocsr()


def distances(v, sources, names):
    """Each point's distance to each source piece (its vertices, edges' midpoints and centres)."""
    D = np.empty((len(v), len(names)))
    for i, name in enumerate(names):
        sv, sf = sources[name]
        pts = np.vstack([sv, sv[sf].mean(1)] + [0.5 * (sv[sf[:, a]] + sv[sf[:, b]]) for a, b in ((0, 1), (1, 2), (2, 0))])
        D[:, i] = cKDTree(pts).query(v)[0]
    return D


def clean_specks(f, L, nlab, min_tris=40, frac=0.02, rounds=4):
    """Each piece's small islands folded into the piece around them."""
    _, t1, t2 = edge_faces(f)
    for _ in range(rounds):
        changed = 0
        for lab in range(nlab):
            sel = L == lab
            if not sel.any():
                continue
            m = sel[t1] & sel[t2]
            idx = np.nonzero(sel)[0]
            remap = -np.ones(len(f), np.int64); remap[idx] = np.arange(len(idx))
            nc, comp = connected_components(coo_matrix((np.ones(m.sum()), (remap[t1[m]], remap[t2[m]])),
                                                       shape=(len(idx), len(idx))), directed=False)
            if nc <= 1:
                continue
            size = np.bincount(comp)
            small = size < max(min_tris, frac * size.max())
            small[np.argmax(size)] = False
            for c in np.nonzero(small)[0]:
                tris = idx[comp == c]
                inside = np.zeros(len(f), bool); inside[tris] = True
                border = np.concatenate([L[t2[inside[t1] & ~inside[t2]]], L[t1[inside[t2] & ~inside[t1]]]])
                border = border[border != lab]
                if len(border):
                    L[tris] = np.bincount(border).argmax(); changed += 1
        if not changed:
            break
    return L


def split(v, f, sources, x0, sure_mm=1.2, margin_mm=1.5, K=30.0):
    """Each triangle's piece (an index into the sources' names): seeds where one source is clearly the
    nearest, the right side's (x < x0) the mirror image of the left's with left and right swapped, so the
    split is symmetric wherever the surface is; grown along the surface, crossing folds costly."""
    names = list(sources)
    swap = np.array([names.index(n[:-2] + ("_R" if n.endswith("_L") else "_L")) if n.endswith(("_L", "_R")) else i
                     for i, n in enumerate(names)])
    D = distances(v, sources, names)
    o = np.sort(D, 1)
    best = D.argmin(1)
    seed = np.where((o[:, 0] < sure_mm * 1e-3) & (o[:, 1] - o[:, 0] > margin_mm * 1e-3), best, -1)
    left = v[:, 0] >= x0
    mirrored = v[~left].copy(); mirrored[:, 0] = 2 * x0 - mirrored[:, 0]
    dist, j = cKDTree(v[left]).query(mirrored)
    ls = seed[left][j]
    seed[~left] = np.where((ls >= 0) & (dist < 0.003), swap[np.maximum(ls, 0)], -1)
    G = crease_costs(v, f, K)
    cost = np.full((len(v), len(names)), np.inf)
    for i in range(len(names)):
        s = np.nonzero(seed == i)[0]
        if len(s):
            cost[:, i] = dijkstra(G, directed=False, indices=s, min_only=True)
    lab = np.where(np.isfinite(cost.min(1)), cost.argmin(1), best)
    a, b, c = lab[f[:, 0]], lab[f[:, 1]], lab[f[:, 2]]
    return names, clean_specks(f, np.where(b == c, b, a), len(names)), float((seed >= 0).mean())


def tooth_mask(v, f, row, upper, reach_mm=9.0, look_mm=3.0, smooth=4):
    """Which points are tooth: within reach of the organ set's tooth row (across), and no further from the
    jaw's biting surface than a crown and a dry skull's little root for that place in the arch."""
    mm = 1e-3
    near = ((cKDTree(row[:, [0, 2]]).query(v[:, [0, 2]])[0] < reach_mm * mm)
            & (v[:, 1] > row[:, 1].min() - 25 * mm) & (v[:, 1] < row[:, 1].max() + 25 * mm))
    idx = np.nonzero(near)[0]
    up = np.array([0.0, 1.0 if upper else -1.0, 0.0])      # from the biting edge toward the bone
    for _ in range(2):
        a = np.cross(up, [0, 0, 1.0]); a /= np.linalg.norm(a)
        b = np.cross(a, up)
        P, H = v[idx] @ np.stack([a, b]).T, v[idx] @ up
        edge = np.array([H[n].min() for n in cKDTree(P).query_ball_point(P, look_mm * mm)])
        tips = idx[H - edge < 0.5 * mm]
        # the biting plane through the tips, those well off it (a ramus rising past the teeth) left out
        for _ in range(3):
            c = np.median(v[tips], 0)
            nn = np.linalg.svd(v[tips] - c, full_matrices=False)[2][2]
            nn = nn if nn @ up > 0 else -nn
            off = (v[tips] - c) @ nn
            tips = tips[np.abs(off) < max(3 * mm, 2.5 * np.median(np.abs(off)))]
        up = nn / np.linalg.norm(nn)
        plane = c
    # the biting surface: a quadratic fit to the tips over the arch, so the curve of the bite is followed;
    # a bare ridge where a tooth is missing sits well short of it
    a = np.cross(up, [0, 0, 1.0]); a /= np.linalg.norm(a); b = np.cross(a, up)
    P, H = v[idx] @ np.stack([a, b]).T, v[idx] @ up

    def basis(Q):
        return np.stack([np.ones(len(Q)), Q[:, 0], Q[:, 1], Q[:, 0] ** 2, Q[:, 0] * Q[:, 1], Q[:, 1] ** 2], 1)
    edge = np.array([H[n].min() for n in cKDTree(P).query_ball_point(P, look_mm * mm)])
    tip = H - edge < 0.5 * mm
    keep = tip.copy()
    for _ in range(5):
        coef = np.linalg.lstsq(basis(P[keep]), H[keep], rcond=None)[0]
        keep = tip & (np.abs(H - basis(P) @ coef) < 3 * mm)
    short = edge - basis(P) @ coef > 4.0 * mm
    h = np.full(len(v), np.inf); h[idx] = np.where(short, np.inf, H - edge)
    h[(v - plane) @ up < -3.5 * mm] = np.inf      # past the biting plane by more than a cusp: a process, not a tooth
    fwd = b if b @ np.array([0, 0, 1.0]) > 0 else -b
    depth = (v[tips] @ fwd).max() - v @ fwd        # how far behind the arch's front
    crown = np.interp(depth, np.array([0, 6, 10, 14, 20, 26, 80]) * mm,
                      np.array([11.5, 11.0, 12.0, 10.0, 9.0, 8.5, 8.5] if upper else [10.5, 10.5, 12.0, 10.0, 9.0, 8.5, 8.5]) * mm)
    s = np.where(np.isfinite(h), h - crown, 1.0)
    A = neighbours(f, len(v)); deg = np.asarray(A.sum(1)).ravel()
    for _ in range(smooth):
        s = np.where(np.isfinite(h), 0.5 * s + 0.5 * (A @ s) / np.maximum(deg, 1), s)
    return s < 0


# MARK: the skull

def load_vhskull(path, atlas):
    """The scan's cranium and mandible (its two largest pieces), in its own frame and units."""
    got = sha256(path)
    assert got == VHSKULL_SOURCE["sha256"], f"{path}: SHA-256 {got}, expected {VHSKULL_SOURCE['sha256']}"
    gltf, binary = atlas.load_glb(path)
    vs, fs, base = [], [], 0

    def walk(i, parent):
        nonlocal base
        node = gltf["nodes"][i]
        world = parent @ atlas.node_matrix(node)
        if "mesh" in node:
            p, f = atlas.mesh_of(gltf, binary, node, world)
            vs.append(p); fs.append(f + base); base += len(p)
        for c in node.get("children", []):
            walk(c, world)
    for r in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    v, f = np.concatenate(vs), np.concatenate(fs)
    piece = atlas.pieces(len(v), f)
    order = np.argsort(-np.bincount(piece), kind="stable")
    out = []
    for k in order[:2]:
        g = f[piece == k]
        used = np.unique(g)
        remap = np.full(len(v), -1, np.int64); remap[used] = np.arange(len(used))
        out.append((v[used], remap[g]))
    log(f"  the skull scan: cranium {len(out[0][1])} triangles, mandible {len(out[1][1])}, "
        f"{len(f) - len(out[0][1]) - len(out[1][1])} of debris left out")
    return out


def joined(meshes):
    vs, fs, off = [], [], 0
    for v, f in meshes:
        vs.append(v); fs.append(f + off); off += len(v)
    return np.vstack(vs).astype(np.float64), np.vstack(fs)


def skull(body, parts, scan, atlas, template=None):
    """The body's new skull pieces {node: (v, f)}, and (for the man) its split, for the woman's."""
    pre = "VH_M_" if body["id"] == "male" else "VH_F_"
    upper, lower = pre + "set_of_upper_jaw_teeth", pre + "set_of_lower_jaw_teeth"
    bones = dict(zip([s["node"] for s in parts["skull"]["structures"]], parts["skull"]["meshes"]))
    mouth = dict(zip([s["node"] for s in parts["mouth"]["structures"]], parts["mouth"]["meshes"]))
    target = {"cranium": joined([m for n, m in bones.items() if n != "NLM_mandible"]),
              "mandible": joined([bones["NLM_mandible"]])}
    jaws = {}
    for (name, budget), (v, f) in zip((("cranium", CRANIUM), ("mandible", MANDIBLE)), scan):
        coarse = atlas.simplify_piece(v, f, SKULL_FIT)
        found = similarity(*coarse, *target[name], n=4000)
        log("    " + report(name, found))
        fine = atlas.simplify_piece(v, f, budget)
        jaws[name] = (placed(fine[0], found[0][2:]), fine[1])
    (cv, cf), (mv, mf) = jaws["cranium"], jaws["mandible"]
    if template is not None:
        assert len(template["cranium"][1]) == len(cf) and len(template["mandible"][1]) == len(mf), \
            "the man's skull was simplified differently"
        log("    the man's skull bent onto hers: cranium")
        cv = warp(cv, cf, *target["cranium"])
        log("    mandible")
        mv = warp(mv, mf, *target["mandible"])
    # turned about its middle so its plane of symmetry is the body's (x = x0)
    n, d, err = best_plane(cv)
    c = cv.mean(0)
    axis = np.cross(n, [1.0, 0, 0]); s = np.linalg.norm(axis)
    Q = np.eye(3)
    if s > 1e-9:
        k = axis / s
        Kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
        Q = np.eye(3) + s * Kx + (1 - n[0]) * Kx @ Kx
    x0 = float((c + Q @ (c - ((c @ n) - d) * n - c))[0])
    cv, mv = (Q @ (cv - c).T).T + c, (Q @ (mv - c).T).T + c
    log(f"    turned {np.degrees(np.arccos(min(1.0, n[0]))):.2f} degrees to the body's plane, x = {x0 * 1000:.1f} mm")
    # the teeth: found in the man, the man's in the woman
    if template is None:
        masks = {"cranium": tooth_mask(cv, cf, mouth[upper][0], upper=True),
                 "mandible": tooth_mask(mv, mf, mouth[lower][0], upper=False)}
    else:
        masks = {}
        for name, (v, f) in (("cranium", (cv, cf)), ("mandible", (mv, mf))):
            names, L = template[name + " split"]
            mask = np.zeros(len(v), bool)
            mask[np.unique(f[L == next(i for i, x in enumerate(names) if "teeth" in x)])] = True
            masks[name] = mask
    for name in ("cranium", "mandible"):
        v, f = (cv, cf) if name == "cranium" else (mv, mf)
        before = asymmetry(v, x0)
        v2 = symmetrize(v, f, x0, masks[name])
        log(f"    {name}'s sides: {before * 1000:.2f} mm apart on average, then {asymmetry(v2, x0) * 1000:.2f} "
            f"(moved at most {np.linalg.norm(v2 - v, axis=1).max() * 1000:.1f} mm)")
        if name == "cranium":
            cv = v2
        else:
            mv = v2
    pieces, made = {}, {"cranium": (cv, cf), "mandible": (mv, mf)}
    for name, v, f in (("cranium", cv, cf), ("mandible", mv, mf)):
        teeth = upper if name == "cranium" else lower
        if template is None:
            sources = {k: m for k, m in bones.items() if (k == "NLM_mandible") == (name == "mandible")}
            sources[teeth] = mouth[teeth]
            names, L, seeded = split(v, f, sources, x0)
            ti = names.index(teeth)
            m = masks[name]
            L = np.where(L == ti, -1, L)
            L[m[f].sum(1) >= 2] = ti
            # what the organ set's row called tooth but the height test does not: the bone around it
            _, t1, t2 = edge_faces(f)
            for _ in range(50):
                hole = L == -1
                if not hole.any():
                    break
                m1 = hole[t1] & ~hole[t2] & (L[t2] != ti); m2 = hole[t2] & ~hole[t1] & (L[t1] != ti)
                L[t1[m1]] = L[t2[m1]]; L[t2[m2]] = L[t1[m2]]
            L[L == -1] = ti
            L = clean_specks(f, L, len(names))
            made[name + " split"] = (names, L)
            log(f"    {name} split along its folds: {seeded:.0%} of its points seeded, {int((L == ti).sum())} triangles of teeth")
        else:
            names, L = template[name + " split"]
            names = [x.replace("VH_M_", pre) for x in names]
        for i, nm in enumerate(names):
            g = f[L == i]
            assert len(g), f"{body['id']}: the {nm} came out empty"
            used, inv = np.unique(g, return_inverse=True)
            pieces[nm] = (v[used], inv.reshape(-1, 3))
    return pieces, made


# MARK: the spine

def read_obj(path):
    vs, fs = [], []
    with open(path, "rb") as fh:
        for line in fh:
            if line.startswith(b"v "):
                p = line.split()
                vs.append((float(p[1]), float(p[2]), float(p[3])))
            elif line.startswith(b"f "):
                idx = [int(x.split(b"/")[0]) for x in line.split()[1:]]
                for k in range(1, len(idx) - 1):
                    fs.append((idx[0], idx[k], idx[k + 1]))
    v = np.array(vs, np.float64)
    f = np.array(fs, np.int64)
    return v, np.where(f < 0, f + len(v), f - 1)


def ka_bone(folder, name, cache=None):
    """One of KA 25's bones after its first pass: 60,000 triangles, in millimetres, its own frame."""
    md5 = KA25_MD5[name + ".obj"]
    kept = os.path.join(cache, name + ".npz") if cache else None
    if kept and os.path.exists(kept):
        z = np.load(kept)
        if str(z["md5"]) == md5:
            return z["v"], z["f"]
    path = os.path.join(folder, name + ".obj")
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    assert h.hexdigest() == md5, f"{path}: MD5 {h.hexdigest()}, expected {md5}"
    v, f = read_obj(path)
    q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - KA_FIRST / len(f))
    v, f = np.asarray(q, np.float64), np.asarray(g, np.int64)
    if kept:
        os.makedirs(cache, exist_ok=True)
        np.savez_compressed(kept, v=v, f=f, md5=np.array(md5))
    return v, f


def ka_name(node, lumbar):
    """The KA 25 bone for an organ set's vertebra (pre + kind + _vertebra_ + n)."""
    kind, n = node.split("_vertebra_")[0].rsplit("_", 1)[1], int(node.rsplit("_", 1)[1])
    if kind == "cervical":
        return f"C{n}"
    if kind == "thoracic":
        return f"T{n}" if n <= 6 else f"T{n + 1}"     # the scan's column has thirteen: its seventh left out
    return f"L{n}" if lumbar == 5 else ["L1", "L2", "L3", "L3", "L4", "L5"][n - 1]


def budget(v, f, s):
    """A bone's triangles for the atlas: one per SPINE_MM2 of its placed surface, never under BONE_FLOOR."""
    a = 0.5 * np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1).sum() * s * s
    return max(BONE_FLOOR, int(round(a * 1e6 / SPINE_MM2)))


def spine(body, parts, folder, cache, atlas):
    """The body's new vertebrae, sacrum and coccyx {node: (v, f)}."""
    pre = "VH_M_" if body["id"] == "male" else "VH_F_"
    column = dict(zip([s["node"] for s in parts["vertebral-column"]["structures"]], parts["vertebral-column"]["meshes"]))
    pelvis = dict(zip([s["node"] for s in parts["pelvis"]["structures"]], parts["pelvis"]["meshes"]))
    lumbar = sum(1 for n in column if "_lumbar_vertebra_" in n)
    jobs = [(n, ka_name(n, lumbar), column[n]) for n in column if any(n.startswith(f"{pre}{k}_vertebra_") for k in KINDS)]
    jobs.append((pre + "sacrum", "Sacrum", pelvis[pre + "sacrum"]))
    out, kept = {}, {}
    for node, name, (tv, tf) in jobs:
        if name not in kept:
            kept[name] = ka_bone(folder, name, cache)
        v, f = kept[name]
        v = v * 0.001
        found = similarity(*atlas.simplify(v, f, KA_FIT), tv.astype(np.float64), tf)
        fit = found[0][2:]
        fv, ff = atlas.simplify(v, f, budget(v, f, fit[0]))
        out[node] = (placed(fv, fit), ff)
        log("    " + report(f"{node[len(pre):]} from {name}", found) + f", {len(ff)} triangles")
        if name == "Sacrum":
            # the coccyx's two pieces, scanned in the sacrum's frame, placed by its similarity
            vs, fs, off = [], [], 0
            for piece in ("Coccyx1", "Coccyx2-4"):
                cv, cf = ka_bone(folder, piece, cache)
                cv = cv * 0.001
                cv, cf = atlas.simplify(cv, cf, budget(cv, cf, fit[0]))
                vs.append(placed(cv, fit)); fs.append(cf + off); off += len(cv)
            out[pre + "coccyx"] = (np.vstack(vs), np.vstack(fs))
            log(f"    coccyx on the sacrum's tip, {sum(len(x) for x in fs)} triangles")
    return out


# MARK: the atlas

def rewrite(folder, part, meshes):
    lo, hi = write_part(os.path.join(folder, part["file"]), [(np.asarray(v, np.float32), np.asarray(f, np.int64)) for v, f in meshes])
    for st, (_, f) in zip(part["structures"], meshes):
        st["triangles"] = int(len(f))
    part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
    part["sha256"] = sha256(os.path.join(folder, part["file"]))
    part["triangles"] = int(sum(s["triangles"] for s in part["structures"]))
    part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]


def replace(folder, vhskull, ka25, cache=None, atlas=None):
    """Puts the scanned bones into the atlas in `folder`; does nothing if they are there already."""
    if atlas is None:
        import anatomy_atlas as atlas
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    have = {s["id"] for s in manifest["sources"]}
    if {VHSKULL_SOURCE["id"], KA25_SOURCE["id"]} <= have:
        log("the scanned skull and spine are in already")
        return False
    scan = load_vhskull(vhskull, atlas)
    template = None
    for body in sorted(manifest["bodies"], key=lambda b: b["id"] != "male"):    # the man first: the woman's is his
        log(f"  {body['id']}:")
        parts = {p["id"]: p for p in body["parts"]}
        for pid in ("skull", "mouth", "vertebral-column", "pelvis"):
            parts[pid]["meshes"] = read_part(os.path.join(folder, parts[pid]["file"]))
        new, made = skull(body, parts, scan, atlas, template)
        if template is None:
            template = made
        new.update(spine(body, parts, ka25, cache, atlas))
        # the scan's teeth join the skull, under the names the organ sets' had in the mouth
        skull_part, mouth = parts["skull"], parts["mouth"]
        moving = [st for st in mouth["structures"] if st["node"] in new]
        stay = [(st, m) for st, m in zip(mouth["structures"], mouth["meshes"]) if st["node"] not in new]
        mouth["structures"] = [st for st, _ in stay]
        rewrite(folder, mouth, [m for _, m in stay])
        skull_part["structures"] = skull_part["structures"] + moving
        missing = [st["node"] for st in skull_part["structures"] if st["node"] not in new]
        assert not missing, f"{body['id']}: no new mesh for {missing}"
        rewrite(folder, skull_part, [new[st["node"]] for st in skull_part["structures"]])
        for pid in ("vertebral-column", "pelvis"):
            part = parts[pid]
            rewrite(folder, part, [new.get(st["node"], m) for st, m in zip(part["structures"], part["meshes"])])
        for pid in ("skull", "mouth", "vertebral-column", "pelvis"):
            del parts[pid]["meshes"]
        log(f"  {body['id']}: skull {skull_part['triangles']} triangles in {len(skull_part['structures'])} pieces, "
            f"column {parts['vertebral-column']['triangles']}, pelvis {parts['pelvis']['triangles']}; "
            f"{sum(p['triangles'] for p in body['parts'])} in all")
    manifest["sources"] += [dict(VHSKULL_SOURCE), dict(KA25_SOURCE)]
    manifest["changes"] += CHANGES
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--vhskull", required=True, help="NIH 3D 3DPX-012260's GLB (vhm_skull_0-nih3d.glb)")
    ap.add_argument("--ka25", required=True, help="a folder holding KA 25's OBJ files (C1.obj ... Coccyx2-4.obj)")
    ap.add_argument("--atlas", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "RedPen", "Resources", "Anatomy"))
    ap.add_argument("--cache", help="a folder to keep each KA 25 file's first pass in")
    a = ap.parse_args()
    replace(a.atlas, a.vhskull, a.ka25, a.cache)


if __name__ == "__main__":
    main()
