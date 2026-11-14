"""try_bones.py <field name> [--mesh] [--head <built head>]: split a kept field into its bones; keep the label volume (for fsec.py --lab),
and with --mesh the bones' meshes and check pictures (together, and drawn apart)."""
import os
import sys, time, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, bones, view
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
D = np.load(S + "/sb/%s_D.npy" % name).astype(np.float32); I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb"))
lo, h = I["lo"], I["h"]
t0 = time.time()
lab, problems = bones.label(D, lo, h, I)
lab2, parts = bones.sides(lab, lo, h, I)
np.save(S + "/sb/%s_lab.npy" % name, lab); np.save(S + "/sb/%s_lab2.npy" % name, lab2)
print("named in %.0f s:" % (time.time() - t0), ", ".join("%s %.1f" % (p, (lab2 == k + 1).sum() * h ** 3 / 1000) for k, p in enumerate(parts)))
if "--mesh" not in sys.argv:
    sys.exit(0)
M = bones.meshes(D, lo, h, lab2, parts)
print("meshed in %.0f s" % (time.time() - t0))
if "--head" in sys.argv:                                   # --head <built head>: its lower jaw and every tooth join the parts
    Z = np.load(S + "/sb/%s.npz" % sys.argv[sys.argv.index("--head") + 1])
    M["mandible"] = (Z["mv"], Z["mf"])
    for k, (v, f) in enumerate(sorted(sdf.components(Z["tv"], Z["tf"]), key=lambda p: (-np.sign(p[0][:, 1].mean() + 52.0), p[0][:, 0].mean()))):
        M["tooth %02d" % (k + 1)] = (v, f)
    print("with the jaw and %d teeth: %d parts" % (sum(n.startswith("tooth") for n in M), len(M)))
pickle.dump(M, open(S + "/sb/%s_bones.pkl" % name, "wb"))
col = lambda n: (244, 240, 228) if n.startswith("tooth") else bones.COLOUR[n.split(",")[0]]
size = 620; c3 = np.array([0, 12.0, 8.0])
views = (("left side", (1, 0, 0)), ("front", (0, 0, 1)), ("three-quarter", (0.6, 0.25, 0.75)), ("below", (0, -1, 0)), ("top", (0, 1, 0)), ("back", (0, 0, -1)))
for kind, spread, span in (("together", 0.0, 250.0), ("apart", 0.45, 390.0)):
    meshes = []
    off = {n: spread * (v.mean(0) - c3) * np.array([1.0, 0.8, 0.8]) for n, (v, f) in M.items()}
    if spread and "mandible" in M:
        off["mandible"] = off["mandible"] + np.array([0.0, -34.0, 0.0])         # the mouth opened, so that the teeth can be drawn
    for n, (v, f) in M.items():
        if n.startswith("tooth"):                          # a tooth goes with its jaw, drawn 10 mm out of its socket
            c = v.mean(0); low = c[1] < -52.0
            j = "mandible" if low else "maxilla, left" if c[0] > 0 else "maxilla, right"
            off[n] = off[j] + (np.array([0.0, 10.0 if low else -10.0, 0.0]) if spread else 0.0)
        meshes.append((v + off[n], f, col(n)))
    c4 = c3 + np.array([0.0, -14.0, 0.0]) * (spread > 0)
    rows = [[], []]
    for k, (vn, eye) in enumerate(views):
        rows[k // 3].append((view.picture(meshes, eye, size, frame=(c4, span)), vn))
    view.sheet(rows, S + "/look/%s_bones_%s.png" % (name, kind), "the skull's bones, each a part of its own (%s), h = %.2f mm" % (kind, h))
    im = Image.open(S + "/look/%s_bones_%s.png" % (name, kind)); im.thumbnail((1700, 1700)); im.convert("RGB").save(S + "/look/%s_bones_%s.jpg" % (name, kind), quality=86)
print("drawn in %.0f s" % (time.time() - t0))
