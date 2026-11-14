"""hyoid.py: the hyoid bone from landmarks (no imported 3D).

Head frame, millimetres. A body bowed forward, two greater horns running back and up, two lesser
horns at the joins. Left half computed and mirrored. It hangs free at the level of the third
cervical vertebra, inside the arch of the mandible and in front of the spine.
"""
import os
import time
import numpy as np
import sdf, view, landmarks as L
from cervical import sym


def build(h=0.4):
    by = float(L.HYOID["body"][1])
    F = sdf.Field([0, by - 9, 3], [27, by + 12, 46], h)
    F.add(sdf.Tube(sdf.spline(sym([(0, by, 39.6), (6.0, by, 38.7), (11.5, by + 0.4, 35.6)]), 1.0), [(0, 3.9), (0.5, 5.4), (1, 3.9)], [(0, 2.0), (0.5, 2.4), (1, 2.0)], n=2.4))
    gh = sdf.spline([(10.0, by + 0.3, 36.7), (13.0, by + 1.0, 32.5), (16.5, by + 2.5, 25.0), (20.0, by + 4.5, 15.5), (22.0, by + 6.0, 9.5)], 1.0)
    F.add(sdf.Tube(gh, [(0, 3.9), (0.25, 2.5), (0.6, 1.6), (1, 1.5)], [(0, 2.1), (0.3, 2.7), (0.7, 2.2), (1, 1.8)]), k=3.5)   # flattened from above down, tapering back
    F.add(sdf.Tube(sdf.spline(sym([(0, by + 0.5, 41.4), (6.0, by + 0.5, 40.4), (10.5, by + 0.8, 37.3)]), 1.0), 1.1), k=1.2)          # the cross ridge on the front of the body
    F.add(sdf.Tube(np.array([(0, by + 4.4, 41.2), (0, by - 4.2, 41.2)]), 1.0), k=1.2)                                           # and the low ridge down its middle
    F.add(sdf.Ellipsoid((22.0, by + 6.1, 9.2), (2.2, 2.3, 2.4)), k=1.5)
    F.add(sdf.Tube(np.array([(11.6, by + 3.0, 34.6), (12.8, by + 7.5, 32.0)]), [(0, 1.9), (1, 1.0)]), k=1.5)
    F.cut(sdf.Ellipsoid((0, by, 35.0), (9.0, 4.0, 3.2)), k=1.5)          # the hollow on the back of the body
    return F


def nearest(v, out, bid):
    """Least distance (mm) from these points to a finished bone of the manifest."""
    from scipy.spatial import cKDTree
    p = os.path.join(out, "bones", bid + ".npz")
    if not os.path.exists(p):
        return None
    w = (np.load(p)["v"].astype(float) - L.HEAD) * 1000.0
    return round(float(cKDTree(w).query(v)[0].min()), 1)


def make(out, h=0.4, draft=False):
    import make as mk
    h = min(h, 0.4)
    F = build(h)
    D = sdf.mirror_field(F.D); lo = np.array([-F.ax[0][-1], F.lo[1], F.lo[2]])
    fine, final, pieces = sdf.finish(D, lo, h, 10 ** 9 if draft else 4000, rounds=8, least=60)
    v, f = fine if draft else final
    rep = sdf.report(v, f); rep["pieces_in_field"] = pieces
    sizes = {"width across the greater horns": round(float(np.ptp(fine[0][:, 0])), 1), "length front to back": round(float(np.ptp(fine[0][:, 2])), 1),
             "body height": round(float(np.ptp(fine[0][np.abs(fine[0][:, 0]) < 1][:, 1])), 1),
             "least distance to the mandible": nearest(fine[0], out, "mandible"), "least distance to C3": nearest(fine[0], out, "C3"),
             "body centre, head frame": [0.0, float(L.HYOID["body"][1]), 39.6]}
    print(mk.clock(), "hyoid", rep, sizes, flush=True)
    m = [(v, f, view.BONE)]
    rows = [mk.views(m, ["front", "top", "left side", "three-quarter"], 480)]
    r = mk.plate(out, "Gray186.png", 480)
    if r is not None:
        rows.append([(r, "reference: Gray's Anatomy 1918 (public domain), Gray186.png")])
    view.sheet(rows, os.path.join(out, "checks", "hyoid_draft.png" if draft else "hyoid.png"), "Hyoid built from landmarks (no imported 3D)  h = %.2f mm, %d triangles" % (h, len(f)))
    if not draft:
        mk.save_bone(out, "hyoid", v, f, {"name": "hyoid bone", "side": "midline", "group": "neck",
                                           "how": "body, greater and lesser horns as swept solids on landmarks; left half computed and mirrored; grid %.2f mm" % h,
                                           "landmarks_mm_head_frame": L.HYOID, "measured_mm": sizes, "mesh": rep})
    return v, f
