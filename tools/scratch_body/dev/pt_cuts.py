"""pt_cuts.py <field name>: upright sections through the pterygoid region (bone white).
Top row: front-to-back sections (z across, forward to the right; y up) at several x. Bottom row: side-to-side sections (x across, y up) at several z."""
import os
import sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
D = np.load(S + "/sb/%s_D.npy" % name, mmap_mode="r"); I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); lo, h = I["lo"], I["h"]
ix = lambda q, k: int(round((q - lo[k]) / h))
k = 12
def tile(A, a0, a1, label, lab_a):
    # A[(a, y)] with y from -50..0
    im = Image.fromarray(((A.T[::-1] < 0) * 215 + 25).astype(np.uint8)).resize((A.shape[0] * int(k * h), A.shape[1] * int(k * h)), Image.NEAREST).convert("RGB")
    d = ImageDraw.Draw(im)
    for a in range(int(np.ceil(a0 / 5.0) * 5), int(a1), 5):
        X = (a - a0) * k; d.line([(X, 0), (X, im.size[1])], fill=(0, 120, 255), width=1); d.text((X + 2, 2), "%s%d" % (lab_a, a), fill=(0, 160, 255))
    for y in range(-45, 0, 5):
        Y = (0 - y) * k; d.line([(0, Y), (im.size[0], Y)], fill=(0, 120, 255), width=1); d.text((2, Y + 2), "y%d" % y, fill=(0, 160, 255))
    d.text((6, im.size[1] - 14), label, fill=(255, 220, 0))
    return im
rows = []
row = [tile(np.asarray(D[ix(x, 0), ix(-50, 1):ix(0, 1), ix(26, 2):ix(54, 2)]).astype(np.float32).T, 26, 54, "x %.1f" % x, "z") for x in (0.5, 14, 16, 18, 20, 22, 25)]
rows.append(row)
row = [tile(np.asarray(D[ix(0, 0):ix(36, 0), ix(-50, 1):ix(0, 1), ix(z, 2)]).astype(np.float32), 0, 36, "z %.1f" % z, "x") for z in (35, 38, 40, 42, 44, 46)]
rows.append(row)
for tag, r in zip(("sag", "cor"), rows):
    W = sum(t.size[0] + 4 for t in r); H = r[0].size[1]
    out = Image.new("RGB", (W, H), (60, 0, 0)); x = 0
    for t in r:
        out.paste(t, (x, 0)); x += t.size[0] + 4
    out.save(S + "/look/%s_ptcuts_%s.png" % (name, tag)); print(S + "/look/%s_ptcuts_%s.png" % (name, tag), out.size)
