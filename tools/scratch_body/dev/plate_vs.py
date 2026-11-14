"""plate_vs.py <name>: the model's base from below beside the same piece of Gray's Fig. 187 (page 179), frame for frame."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view, plates
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
Z = np.load(S + "/sb/%s.npz" % name)
meshes = [(Z["v"], Z["f"], view.BONE)]
page = Image.open(S + "/gray1918/pages/p-0179.jpg").convert("RGB")
MID, SX = plates.BASE_MID, plates.BASE_SX
(y0, z0), (y1, z1) = plates.BASE_Z
SZ = (y1 - y0) / (z0 - z1)                       # page pixels per mm along z
N = 900
def plate(c, span):
    xa, xb = MID + SX * (c[0] - span / 2), MID + SX * (c[0] + span / 2)
    ya, yb = y0 + (z0 - (c[2] + span / 2)) * SZ, y0 + (z0 - (c[2] - span / 2)) * SZ
    return page.crop((int(round(xa)), int(round(ya)), int(round(xb)), int(round(yb)))).resize((N, N), Image.LANCZOS)
rows = []
for label, c, span in (("one half of the base", (-28, 0, -4), 78), ("the openings, close", (-27, 0, 7), 48)):
    m = view.picture(meshes, (0, -1, 0), N, frame=(np.array(c, float), float(span)))
    rows.append([(plate(c, span), "Gray 1918, Fig. 187 (public domain): " + label), (m, "the model from below, same frame: " + label)])
out = S + "/look/%s_plate_vs.png" % name
view.sheet(rows, out, "%s: the base from below, plate beside model" % name)
im = Image.open(out); im.thumbnail((1700, 1700)); im.convert("RGB").save(out[:-4] + ".jpg", quality=88)
print(out[:-4] + ".jpg")
