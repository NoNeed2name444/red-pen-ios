"""bones_close.py <field name> [set]: close views of the split bones (coloured), to check each suture's place.
set: face (default), base, side"""
import os
import sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, bones, view
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]; which = sys.argv[2] if len(sys.argv) > 2 else "face"
M = pickle.load(open(S + "/sb/%s_bones.pkl" % name, "rb"))
hide = sys.argv[3].split(",") if len(sys.argv) > 3 else []
meshes = [(v, f, bones.COLOUR[n.split(",")[0]]) for n, (v, f) in M.items() if not any(n.startswith(q) for q in hide)]
SETS = {
    "face": [("face, from in front", (0, 0, 1), (0, -5, 80), 135), ("left orbit, from in front and a little outward", (0.3, 0.05, 1), (30, 14, 70), 62),
             ("nose and inner wall of the left orbit", (0.75, 0.1, 0.65), (12, 8, 85), 70), ("left cheek, from the side and front", (0.8, 0.0, 0.6), (40, -5, 70), 110)],
    "side": [("left side", (1, 0, 0), (55, 5, 25), 150), ("left temple and arch", (1, 0.1, 0.25), (55, 10, 35), 100),
             ("from behind and below, left", (0.5, -0.6, -0.6), (40, -10, -10), 130), ("left side, from a little below", (1, -0.45, 0.2), (50, -5, 25), 130)],
    "base": [("base, from below", (0, -1, 0), (0, -20, 20), 150), ("palate and choanae", (0, -1, -0.25), (0, -30, 55), 80),
             ("left half of the base's middle", (0.1, -1, 0), (30, -15, 12), 80), ("from below and in front", (0, -0.8, 0.6), (0, -15, 55), 130)],
    "in": [("cranial floor, from above (vault parts hidden)", (0, 1, 0), (0, 10, 5), 160), ("left orbit, deep", (0.15, 0.0, 1), (28, 14, 60), 50),
           ("nose, from in front", (0, 0, 1), (0, -10, 90), 60), ("right half seen from the left (cut)", (1, 0, 0), (0, 0, 30), 180)],
}
size = 800; rows = [[], []]
for k, (cap, eye, c, span) in enumerate(SETS[which]):
    rows[k // 2].append((view.picture(meshes, eye, size, frame=(np.array(c, float), float(span))), cap))
out = S + "/look/%s_bones_%s" % (name, which)
view.sheet(rows, out + ".png", "bones, close: %s" % which)
im = Image.open(out + ".png"); im.thumbnail((1700, 1700)); im.convert("RGB").save(out + ".jpg", quality=86); print(out + ".jpg")
