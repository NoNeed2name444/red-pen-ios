"""fit_plates.py <bone> <fig> [h] [--nod] [--free=100011]: the pose of one plate found by what the plates must agree on: the solid that
lies inside all the outlines at once should fill each plate's own outline. A plate held at a wrong angle, size or place
cuts the solid short in the other plates' views, and its own outline is then left unfilled too; the pose is moved
(turn, roll, scale, shift; the nod too with --nod) until the solid fills the outlines best, all plates counted alike.
Starts from sb/platefit_<bone>.json and writes the pose found back there (then run trace_plates.py again)."""
import os, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, foot, platematch as pm
from PIL import Image
from scipy.optimize import minimize
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
name, fig = args[0], args[1]; h = float(args[2]) if len(args) > 2 else 0.8; sub = 2
keep = S + "/sb/platefit_%s.json" % name; poses = json.load(open(keep))
views = [v for v in pm.PLATES[name] if v["fig"] != "Gray265"]          # the plate from below only rules the lower plan
masks = {}
for v in views:
    m = pm.silhouette(np.array(Image.open(S + "/refs_foot/%s.png" % v["fig"]).convert("L")), erase=v.get("erase", ()))
    masks[v["fig"]] = (m[sub // 2::sub, sub // 2::sub], m.shape)
x0 = np.array(poses[fig], float); free = np.array([1 if "--nod" in sys.argv else 0, 1, 1, 1, 1, 1], bool); n = [0]
for a in sys.argv:                                   # --free=100011: which of nod, turn, roll, scale, shift right, shift down may move
    if a.startswith("--free="):
        free = np.array([c == "1" for c in a[7:]], bool)


def cost(q, show=False):
    p = x0.copy(); p[free] = q; cur = dict(poses); cur[fig] = list(p)
    F = getattr(foot, name)(h, log=lambda *a: None, upto="hull", poses=cur); out = []
    for v in views:
        small, (H, W) = masks[v["fig"]]; c = cur[v["fig"]]
        depth, _ = pm.cast(F, pm.basis(v, c[:3]), v["s"] * c[3], v["u0"] + c[4], v["v0"] + c[5], (W, H), sub, normals=False)
        out.append(pm.iou(~np.isnan(depth), small))
    n[0] += 1
    if show or n[0] % 25 == 0:
        print("  %3d: %s  filled %s" % (n[0], " ".join("%.2f" % a for a in p), " ".join("%.3f" % a for a in out)), flush=True)
    return 1.0 - float(np.mean(out))


t0 = time.time(); print("start", cost(x0[free], True))
step = np.array([4.0, 4.0, 3.0, 0.03, 5.0, 5.0])[free]; q0 = x0[free]
best = minimize(cost, q0, method="Nelder-Mead", options=dict(initial_simplex=np.vstack([q0] + [q0 + step[i] * np.eye(len(q0))[i] for i in range(len(q0))]), xatol=0.05, fatol=1e-4, maxfev=260))
best = minimize(cost, best.x, method="Nelder-Mead", options=dict(initial_simplex=np.vstack([best.x] + [best.x - 0.3 * step[i] * np.eye(len(q0))[i] for i in range(len(q0))]), xatol=0.03, fatol=5e-5, maxfev=160))
p = x0.copy(); p[free] = best.x; print("end", cost(best.x, True), "in %.0f s" % (time.time() - t0))
poses[fig] = [round(float(a), 3) for a in p]; json.dump(poses, open(keep, "w"), indent=1)
