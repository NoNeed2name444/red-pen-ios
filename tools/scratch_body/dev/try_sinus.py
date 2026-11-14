"""try_sinus.py <kept field> [--save name] [--cuts axis:levels:a0,a1,b0,b1 ...]: cut the air sinuses (sinus.py) into a whole-head
field kept by save_field.py, without building the skull again, and draw sections: bone light, air dark, what was hollowed blue."""
import os, sys, time, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, sinus
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
name = sys.argv[1]
I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); h = float(I["h"]); lo = np.asarray(I["lo"], float)
D0 = np.load(S + "/sb/%s_D.npy" % name).astype(np.float32)
G = sdf.Field.__new__(sdf.Field); G.h = h; G.lo = lo; G.n = np.array(D0.shape)
G.ax = [(lo[k] + h * np.arange(D0.shape[k])).astype(np.float32) for k in range(3)]; G.D = D0.copy()
t0 = time.time()
sinus.air(G)
print("sinuses cut in %.0f s" % (time.time() - t0))
from scipy import ndimage
x0, x1 = [int(round((t - lo[0]) / h)) for t in (-50.0, 50.0)]; y0, y1 = [int(round((t - lo[1]) / h)) for t in (-40.0, 56.0)]; z0, z1 = [int(round((t - lo[2]) / h)) for t in (8.0, 108.0)]
A = G.D[x0:x1, y0:y1, z0:z1] >= 0                                  # the air in the face's block: is every hollow open to the outside?
lab, n = ndimage.label(A)
sizes = ndimage.sum(A, lab, range(1, n + 1)); big = int(np.argmax(sizes)) + 1
shut = [(int(sizes[i - 1]), ndimage.center_of_mass(A, lab, i)) for i in range(1, n + 1) if i != big and sizes[i - 1] >= 30]
shut = [t for t in shut if lo[1] + (y0 + t[1][1]) * h > -30.0]            # (the teeth's sockets are shut pockets here: the teeth are not in this field)
print("air pockets shut off from the outside (30 cells and more): %d" % len(shut))
for sz, c in sorted(shut, reverse=True)[:12]:
    print("   %.2f cm3 at x %.1f, y %.1f, z %.1f" % (sz * h ** 3 / 1000, lo[0] + (x0 + c[0]) * h, lo[1] + (y0 + c[1]) * h, lo[2] + (z0 + c[2]) * h))
if "--save" in sys.argv:
    out = sys.argv[sys.argv.index("--save") + 1]
    np.save(S + "/sb/%s_D.npy" % out, np.clip(G.D, -12, 12).astype(np.float16)); pickle.dump(I, open(S + "/sb/%s_info.pkl" % out, "wb"))
for spec in [a for a in sys.argv[2:] if a.count(":") == 3]:
    ax, levels, win, tag = spec.split(":"); axis = "xyz".index(ax); win = [float(t) for t in win.split(",")]
    a, b = [j for j in range(3) if j != axis]
    if axis == 0:
        a, b = 2, 1                                     # side-on cuts: z across, y up
    k = 5; tiles = []
    for L in [float(t) for t in levels.split(",")]:
        i = int(round((L - lo[axis]) / h)); A = np.take(D0, i, axis=axis); B = np.take(G.D, i, axis=axis)
        if axis == 0:
            A, B = A.T, B.T
        p0, p1 = max(int((win[0] - lo[a]) / h), 0), int((win[1] - lo[a]) / h); q0, q1 = max(int((win[2] - lo[b]) / h), 0), int((win[3] - lo[b]) / h)
        A = A[p0:p1, q0:q1]; B = B[p0:p1, q0:q1]; la = lo[a] + p0 * h; lb = lo[b] + q0 * h
        img = np.zeros(A.shape + (3,), np.uint8); img[:] = (24, 24, 26); img[B < 0] = (212, 204, 186); img[(A < 0) & (B >= 0)] = (60, 110, 215)
        im = Image.fromarray(img.transpose(1, 0, 2)[::-1]).resize((A.shape[0] * k, A.shape[1] * k), Image.NEAREST)
        d = ImageDraw.Draw(im); d.text((4, 4), "%s = %g  (across %s, up %s)" % (ax, L, "xyz"[a], "xyz"[b]), fill=(255, 220, 0))
        for t in np.arange(np.ceil(la / 10) * 10, la + h * A.shape[0], 10):
            x = (t - la) / h * k; d.line([(x, im.height - 10), (x, im.height)], fill=(255, 220, 0)); d.text((x + 2, im.height - 12), "%d" % t, fill=(255, 220, 0))
        for t in np.arange(np.ceil(lb / 10) * 10, lb + h * A.shape[1], 10):
            y = im.height - (t - lb) / h * k; d.line([(0, y), (10, y)], fill=(255, 220, 0)); d.text((12, y - 6), "%d" % t, fill=(255, 220, 0))
        tiles.append(im)
    W = Image.new("RGB", (sum(t.width for t in tiles) + 6 * len(tiles), max(t.height for t in tiles)), (0, 0, 60)); x = 0
    for t in tiles:
        W.paste(t, (x, 0)); x += t.width + 6
    W.save(S + "/look/sinus_%s.jpg" % tag, quality=88); print(S + "/look/sinus_%s.jpg" % tag, W.size)
