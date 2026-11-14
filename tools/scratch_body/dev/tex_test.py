"""tex_test.py <built name> [super]: one three-quarter view and one close view of the cheek and upper jaw, to judge the bone's surface."""
import os
import sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]; view.SUPER = int(sys.argv[2]) if len(sys.argv) > 2 else 1
Z = np.load(S + "/sb/%s.npz" % name)
m = [(Z["v"], Z["f"], view.BONE)]
if "tv" in Z: m.append((Z["tv"], Z["tf"], (240, 236, 222)))
t0 = time.time()
a = view.picture(m, (0.62, 0.12, 0.77), 760, frame=(np.array([0.0, -5.0, 60.0]), 190.0), dist=600.0)
b = view.picture(m, (0.55, 0.05, 0.83), 760, frame=(np.array([30.0, -12.0, 80.0]), 70.0))
out = S + "/look/%s_tex%d" % (name, view.SUPER)
view.sheet([[(a, "three-quarter, seen from 600 mm"), (b, "cheek and upper jaw, close")]], out + ".png", "%s: surface (drawn %d times over)" % (name, view.SUPER))
Image.open(out + ".png").convert("RGB").save(out + ".jpg", quality=88); print(out + ".jpg", "%.0f s" % (time.time() - t0))
