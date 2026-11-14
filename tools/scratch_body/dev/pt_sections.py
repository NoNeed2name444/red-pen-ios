"""pt_sections.py <field name>: level sections through the pterygoid region (bone white), x 0..40 across, z 22..58 up the picture."""
import os
import sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
D = np.load(S + "/sb/%s_D.npy" % name, mmap_mode="r"); I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); lo, h = I["lo"], I["h"]
ix = lambda q, k: int(round((q - lo[k]) / h))
tiles = []
k = 10
for y in (-10, -14, -18, -22, -26, -30, -33, -36, -38, -40):
    A = np.asarray(D[ix(-2, 0):ix(40, 0), ix(y, 1), ix(22, 2):ix(58, 2)]).astype(np.float32)      # (x, z)
    im = Image.fromarray(((A.T[::-1] < 0) * 215 + 25).astype(np.uint8)).resize((A.shape[0] * int(k * h), A.shape[1] * int(k * h)), Image.NEAREST).convert("RGB")
    d = ImageDraw.Draw(im)
    for x in range(0, 40, 10):
        X = (x + 2) * k; d.line([(X, 0), (X, im.size[1])], fill=(0, 120, 255), width=1); d.text((X + 2, 2), "x%d" % x, fill=(0, 160, 255))
    for z in range(30, 58, 10):
        Y = (58 - z) * k; d.line([(0, Y), (im.size[0], Y)], fill=(0, 120, 255), width=1); d.text((2, Y + 2), "z%d" % z, fill=(0, 160, 255))
    d.text((6, im.size[1] - 14), "y %d" % y, fill=(255, 220, 0))
    tiles.append(im)
W = sum(t.size[0] + 4 for t in tiles[:5]); H = tiles[0].size[1] * 2 + 8
out = Image.new("RGB", (W, H), (60, 0, 0))
for i, t in enumerate(tiles):
    out.paste(t, ((i % 5) * (t.size[0] + 4), (i // 5) * (t.size[1] + 4)))
out.save(S + "/look/%s_ptsec.png" % name); print(S + "/look/%s_ptsec.png" % name, out.size)
