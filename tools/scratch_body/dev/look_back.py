"""look_back.py <built name | field name> [--field]: the choanae, pterygoid plates and the palate's hind edge, the skull behind them cut away."""
import os
import sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view, sdf
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
if "--field" in sys.argv:
    D = np.load(S + "/sb/%s_D.npy" % name).astype(np.float32); I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb"))
    lo, h = I["lo"], I["h"]
    a = [max(int((q - lo[k]) / h), 0) for k, q in enumerate((-48, -52, 22))]; b = [int((q - lo[k]) / h) for k, q in enumerate((48, 12, 75))]
    D = D[a[0]:b[0], a[1]:b[1], a[2]:b[2]].copy(); lo = lo + h * np.array(a)
    for ax in range(3):                                   # close the block's cut faces
        sl = [slice(None)] * 3
        for e in (0, -1):
            sl[ax] = e; D[tuple(sl)] = np.maximum(D[tuple(sl)], 0.5 * h)
    v, f = sdf.mesh(D, lo, h)
else:
    z = np.load(S + "/sb/%s.npz" % name); v, f = z["v"], z["f"]
    cz = v[f].mean(1); keep = (cz[:, 2] > 24) & (cz[:, 2] < 76) & (np.abs(cz[:, 0]) < 48) & (cz[:, 1] < 12) & (cz[:, 1] > -52); f = f[keep]
m = [(v, f, view.BONE)]; size = 700; c = np.array([0.0, -24.0, 40.0])
P = lambda e, cc=c, sp=78.0: view.picture(m, e, size, frame=(cc, sp), hollow=0.45)
rows = [[(P((0, 0, -1)), "from behind"), (P((0, -0.55, -0.83)), "from behind and below"), (P((0, -1, 0), np.array([12.0, 0.0, 42.0]), 44.0), "from below: left hind corner of the palate")],
        [(P((1, 0, 0), np.array([0.0, -22.0, 40.0]), 60.0), "from the left side (cheek arch and jaw away)"), (P((0.72, -0.12, -0.68)), "from behind and the left"),
         (P((0.62, -0.45, -0.64)), "from behind, below and the left")]]
out = S + "/look/%s_back" % name
view.sheet(rows, out + ".png", "%s: choanae and pterygoid plates (the skull behind them cut away)" % name)
im = Image.open(out + ".png"); im.thumbnail((1700, 1700)); im.convert("RGB").save(out + ".jpg", quality=86); print(out + ".jpg")
