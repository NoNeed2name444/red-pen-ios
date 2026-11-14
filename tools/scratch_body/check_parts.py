#!/usr/bin/env python3
"""Mesh checks for the pieces the cranium is cut into (bones/cranium_parts): closed, one piece, no
self-intersection, the gap to each neighbour, nothing inside a neighbour.  python3 check_parts.py <out>
Writes <out>/cranium_parts_checks.json."""
import json, os, sys
import numpy as np
from scipy.spatial import cKDTree
import check_mesh as cm
import landmarks as L


def main(out):
    man = json.load(open(os.path.join(out, "manifest.json")))
    M, S, res = {}, {}, {"units": "mm, head frame", "parts": {}, "pairs": {}}
    for bid, b in man["cranium_parts"]["parts"].items():
        z = np.load(os.path.join(out, b["file"]))
        v, f = (z["v"].astype(float) - L.HEAD) * 1000.0, z["f"].astype(int)
        M[bid] = (v, f)
        e, cnt = cm.edges_of(f)
        cuts, where = cm.self_cuts(v, f)
        S[bid] = cm.surface_points(v, f)
        res["parts"][bid] = {"triangles": int(len(f)), "edges not shared by exactly two triangles": int((cnt != 2).sum()),
                             "pieces": cm.pieces(f, len(v)), "edges passing through a triangle (self-intersection)": cuts, "self-intersection at": where}
        print(bid, res["parts"][bid], flush=True)
    ids = list(M)
    for i, a in enumerate(ids):
        ta = cKDTree(S[a])
        for b in ids[i + 1:]:
            d, k = ta.query(S[b])
            j = int(d.argmin())
            if d[j] > 5: continue
            ina = int(cm.inside(M[b][0], M[b][1], M[a][0]).sum()); inb = int(cm.inside(M[a][0], M[a][1], M[b][0]).sum())
            res["pairs"][a + " / " + b] = {"least distance": round(float(d[j]), 2), "at": np.round(S[b][j], 1).tolist(),
                                           "vertices of the first inside the second": ina, "vertices of the second inside the first": inb}
            print(a, "/", b, res["pairs"][a + " / " + b], flush=True)
    json.dump(res, open(os.path.join(out, "cranium_parts_checks.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
