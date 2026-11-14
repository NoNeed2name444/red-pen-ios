"""check_mesh.py: the mesh checks every from-scratch bone has to pass before it is called done.

  python3 check_mesh.py <out>

For each bone in <out>/manifest.json: closed and manifold (every edge shared by exactly two triangles),
one piece, no self-intersection (an edge of one triangle passing through another triangle), and how
far the mesh is from its own mirror image (mm). For each pair of bones: the least distance between
them and whether any vertex of one lies inside the other. Writes <out>/mesh_checks.json.
Everything in millimetres. Uses numpy and scipy only.
"""
import sys, json, os
import numpy as np
from scipy.spatial import cKDTree


def edges_of(f):
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    return np.unique(e, axis=0, return_counts=True)


def pieces(f, n):
    parent = np.arange(n)
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for a, b in edges_of(f)[0]:
        ra, rb = find(a), find(b)
        if ra != rb: parent[ra] = rb
    return len({find(i) for i in np.unique(f)})


def self_cuts(v, f, chunk=4000):
    """Number of (edge, triangle) pairs where the edge passes through the triangle's inside."""
    e, _ = edges_of(f)
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    cen = (a + b + c) / 3
    rad = np.sqrt(np.maximum.reduce([((a - cen) ** 2).sum(1), ((b - cen) ** 2).sum(1), ((c - cen) ** 2).sum(1)]))
    tree = cKDTree(cen)
    p0, p1 = v[e[:, 0]], v[e[:, 1]]
    mid, half = (p0 + p1) / 2, np.linalg.norm(p1 - p0, axis=1) / 2
    rmax = float(np.percentile(rad, 99.9))
    hits = 0; where = []
    for s in range(0, len(e), chunk):
        near = tree.query_ball_point(mid[s:s + chunk], half[s:s + chunk] + rmax, return_sorted=False)
        n = np.array([len(x) for x in near])
        if n.sum() == 0: continue
        ei = np.repeat(np.arange(s, s + len(near)), n); ti = np.concatenate([np.asarray(x, int) for x in near])
        share = (f[ti] == e[ei, 0][:, None]).any(1) | (f[ti] == e[ei, 1][:, None]).any(1)
        ei, ti = ei[~share], ti[~share]
        d = p1[ei] - p0[ei]; e1 = b[ti] - a[ti]; e2 = c[ti] - a[ti]
        h = np.cross(d, e2); det = (e1 * h).sum(1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        sv = p0[ei] - a[ti]; u = inv * (sv * h).sum(1)
        q = np.cross(sv, e1); w = inv * (d * q).sum(1); t = inv * (e2 * q).sum(1)
        eps = 1e-7
        cut = ok & (u > eps) & (w > eps) & (u + w < 1 - eps) & (t > eps) & (t < 1 - eps)
        hits += int(cut.sum())
        if cut.any() and len(where) < 5:
            where += np.round((p0[ei[cut]] + d[cut] * t[cut][:, None])[:5], 1).tolist()
    return hits, where[:5]


def surface_points(v, f, spacing=0.35, cap=1500000, seed=1):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    n = int(min(cap, area.sum() / spacing ** 2))
    rng = np.random.default_rng(seed)
    k = rng.choice(len(f), n, p=area / area.sum())
    r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
    return np.concatenate([v, a[k] * (1 - r1)[:, None] + b[k] * (r1 * (1 - r2))[:, None] + c[k] * (r1 * r2)[:, None]])


def inside(v, f, P):
    """Whether each point is inside the closed mesh (ray along +x, counting crossings; vectorised by pairs)."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    lo = np.minimum(np.minimum(a, b), c)[:, 1:]; hi = np.maximum(np.maximum(a, b), c)[:, 1:]
    out = np.zeros(len(P), bool)
    for i in range(0, len(P), 400):
        p = P[i:i + 400]
        m = ((p[:, None, 1] >= lo[None, :, 0]) & (p[:, None, 1] <= hi[None, :, 0]) &
             (p[:, None, 2] >= lo[None, :, 1]) & (p[:, None, 2] <= hi[None, :, 1]))
        pi, ti = np.nonzero(m)
        if len(pi) == 0: continue
        o = p[pi]; e1 = b[ti] - a[ti]; e2 = c[ti] - a[ti]
        d = np.array([1.0, 0.0, 0.0]); h = np.cross(np.broadcast_to(d, e2.shape), e2); det = (e1 * h).sum(1)
        ok = np.abs(det) > 1e-12; inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = o - a[ti]; u = inv * (s * h).sum(1); q = np.cross(s, e1); w = inv * q[:, 0]; t = inv * (e2 * q).sum(1)
        hit = ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (t > 0)
        out[i:i + 400] = (np.bincount(pi[hit], minlength=len(p)) % 2) == 1
    return out


def main(out):
    import landmarks as L
    man = json.load(open(os.path.join(out, "manifest.json")))
    M = {}
    for bid, b in man["bones"].items():
        z = np.load(os.path.join(out, "bones", bid + ".npz"))
        M[bid] = ((z["v"].astype(float) - L.HEAD) * 1000.0, z["f"].astype(int))
    res = {"units": "mm, head frame", "bones": {}, "pairs": {}}
    S = {}
    for bid, (v, f) in M.items():
        e, cnt = edges_of(f)
        cuts, where = self_cuts(v, f)
        S[bid] = surface_points(v, f)
        tree = cKDTree(S[bid])
        d = tree.query(v * np.array([-1.0, 1, 1]))[0]
        res["bones"][bid] = {"triangles": int(len(f)), "edges not shared by exactly two triangles": int((cnt != 2).sum()),
                             "pieces": pieces(f, len(v)), "edges passing through a triangle (self-intersection)": cuts,
                             "self-intersection at": where,
                             "mirror image differs by, median / 99th percentile / worst": [round(float(np.median(d)), 2), round(float(np.percentile(d, 99)), 2), round(float(d.max()), 2)],
                             "midline offset of the bounds (should be 0)": round(float(v[:, 0].max() + v[:, 0].min()) / 2, 2)}
        print(bid, res["bones"][bid], flush=True)
    ids = list(M)
    for i, a in enumerate(ids):
        ta = cKDTree(S[a])
        for b in ids[i + 1:]:
            lo = np.maximum(M[a][0].min(0), M[b][0].min(0)) - 12; hi = np.minimum(M[a][0].max(0), M[b][0].max(0)) + 12
            if (lo > hi).any(): continue
            sb = S[b][((S[b] > lo) & (S[b] < hi)).all(1)]
            if len(sb) == 0: continue
            d, k = ta.query(sb)
            j = int(d.argmin())
            if d[j] > 12: continue
            va = M[a][0][((M[a][0] > lo) & (M[a][0] < hi)).all(1)]; vb = M[b][0][((M[b][0] > lo) & (M[b][0] < hi)).all(1)]
            ina = int(inside(M[b][0], M[b][1], va).sum()) if len(va) else 0
            inb = int(inside(M[a][0], M[a][1], vb).sum()) if len(vb) else 0
            res["pairs"][a + " / " + b] = {"least distance": round(float(d[j]), 2), "at": np.round(sb[j], 1).tolist(),
                                           "vertices of the first inside the second": ina, "vertices of the second inside the first": inb}
            print(a, "/", b, res["pairs"][a + " / " + b], flush=True)
    json.dump(res, open(os.path.join(out, "mesh_checks.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
