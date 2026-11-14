"""look_face.py <built name> [dist]: the lower face from in front, with and without perspective, beside Gray's front view."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]; dist = 600.0
z = np.load(S + "/sb/%s.npz" % name)
meshes = [(z["v"], z["f"], view.BONE)]
TOOTH = (236, 232, 220)
if "--jaw" in sys.argv:                                   # another jaw (try_jaw.py) under this skull's upper teeth
    j = np.load(S + "/sb/%s.npz" % sys.argv[sys.argv.index("--jaw") + 1]); nt = int(z["nt"]); tf = z["tf"]
    meshes += [(j["mv"], j["mf"], view.BONE), (z["tv"][:nt], tf[tf.max(1) < nt], TOOTH), (j["tv"], j["tf"], TOOTH)]
    name = name + "_" + sys.argv[sys.argv.index("--jaw") + 1]
else:
    if "mv" in z.files: meshes.append((z["mv"], z["mf"], view.BONE))
    if "tv" in z.files: meshes.append((z["tv"], z["tf"], TOOTH))
c = np.array([0.0, -35.0, 60.0]); size = 760
# Gray's front view is drawn from about 8 degrees above the Frankfurt plane: seen so, this jaw's outline lies within 1.6 mm (rms)
# of the plate's; seen dead level the same jaw's sides look upright
rows = [[(view.picture(meshes, (0, 0, 1), size, frame=(c, 150.0), dist=dist), "front, dead level, seen from %.0f mm" % dist),
         (view.picture(meshes, (0, 0.139, 0.990), size, frame=(c, 150.0), dist=dist), "front, from 8 degrees above (the plate's own viewpoint)")]]
rows.append([(view.picture(meshes[1:], (0, -1, 0), size, frame=(np.array([0.0, -60.0, 50.0]), 130.0)), "jaw and teeth from below (skull hidden)"),
             (view.picture(meshes, (0.55, 0.05, 0.83), size, frame=(c, 150.0), dist=dist), "three-quarter, seen from %.0f mm" % dist),
             (view.picture(meshes, (0, -0.35, 0.94), size, frame=(c + (0, -15, 0), 150.0), dist=dist), "from in front and a little below")])
ref = Image.open(S + "/gray1918/pages/p-0186.jpg").convert("RGB").crop((974 - 690, 1640, 974 + 690, 3020)).resize((size, size), Image.LANCZOS)
rows[0].append((ref, "Gray 1918, Fig. 190 (public domain)"))
out = S + "/look/%s_face_vs" % name
view.sheet(rows, out + ".png", "%s: lower face from in front" % name)
im = Image.open(out + ".png"); im.thumbnail((1900, 1900)); im.convert("RGB").save(out + ".jpg", quality=86); print(out + ".jpg")
