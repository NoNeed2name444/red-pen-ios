"""try_structure.py <kept skull field> [--jaw <kept jaw field>] [--out tag] [--title words] [axis:level:a0,a1,b0,b1:caption ...]: what the bones
are made of inside (structure.py), drawn as flat sections at a quarter of a millimetre: compact bone pale, cancellous bone as
its own lattice with the marrow spaces dark red, the mastoid's air cells blue. axis 0: a cut from front to back at x = level
(z across, y up); 2: a cut from side to side at z = level (x across, y up); 1: a level cut at y = level (x across, z up)."""
import os, sys, pickle, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, structure, view
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
arg = sys.argv[1:]
name = arg[0]
jaw = arg[arg.index("--jaw") + 1] if "--jaw" in arg else None
tag = arg[arg.index("--out") + 1] if "--out" in arg else name
TITLE = arg[arg.index("--title") + 1] if "--title" in arg else "What the bones are made of: flat sections"
cuts = [a for a in arg[1:] if a.count(":") >= 2 and arg[arg.index(a) - 1] != "--title"]
INK = {"air": (22, 24, 28), "compact": (238, 229, 205), "bar": (224, 184, 122), "space": (128, 44, 34), "wall": (214, 224, 230), "cell": (58, 112, 168)}
PX = 4                                                             # picture points to the millimetre (the sections are worked at 0.25 mm)


def kept(n):
    I = pickle.load(open(S + "/sb/%s_info.pkl" % n, "rb"))
    return np.load(S + "/sb/%s_D.npy" % n, mmap_mode="r"), np.asarray(I["lo"], float), float(I["h"])


def section(D, lo, h, zones, axis, level, win):
    """(B, kind) on the picture's own grid (rows downward), with a mask of where this field has anything to say."""
    (a0, a1, b0, b1) = win
    ua, va = {0: (2, 1), 2: (0, 1), 1: (0, 2)}[axis]               # the axes that run across and up the picture
    blo = np.zeros(3); bhi = np.zeros(3)
    blo[axis], bhi[axis] = level - 8.0, level + 8.0; blo[ua], bhi[ua] = a0 - 6.0, a1 + 6.0; blo[va], bhi[va] = b0 - 6.0, b1 + 6.0
    i0 = [max(int(np.floor((blo[k] - lo[k]) / h)), 0) for k in range(3)]; i1 = [min(int(np.ceil((bhi[k] - lo[k]) / h)) + 1, D.shape[k]) for k in range(3)]
    nu, nv = int(round((a1 - a0) * PX)) + 1, int(round((b1 - b0) * PX)) + 1
    B2 = np.full((nv, nu), 4.0, np.float32); K2 = np.zeros((nv, nu), np.uint8)
    if min(i1[k] - i0[k] for k in range(3)) < 4:
        return B2, K2
    A = structure.double(np.asarray(D[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]).astype(np.float32)); h2 = h / 2; l2 = lo + np.array(i0) * h
    j = int(round((level - l2[axis]) / h2))
    if j < 2 or j > A.shape[axis] - 3:
        return B2, K2
    slab = [slice(None)] * 3; slab[axis] = slice(j - 1, j + 2)
    B, kind = structure.inside(A, l2, h2, zones, slab=slab)
    take = [slice(None)] * 3; take[axis] = j; Bs = B[tuple(take)]; take[axis] = 1; Ks = kind[tuple(take)]
    if ua > va:                                                    # the array's first remaining axis must be the one that runs across
        Bs, Ks = Bs.T, Ks.T
    iu = np.round((a0 + np.arange(nu) / PX - l2[ua]) / h2).astype(int); iv = np.round((b1 - np.arange(nv) / PX - l2[va]) / h2).astype(int)
    ok = ((iv >= 0) & (iv < Bs.shape[1]))[:, None] & ((iu >= 0) & (iu < Bs.shape[0]))[None, :]
    U, V = np.meshgrid(np.clip(iu, 0, Bs.shape[0] - 1), np.clip(iv, 0, Bs.shape[1] - 1))
    B2[ok] = Bs[U, V][ok]; K2[ok] = Ks[U, V][ok]
    return B2, K2


def paint(B, K):
    im = np.zeros(B.shape + (3,), np.uint8); im[:] = INK["air"]
    bone = B < 0
    im[bone & (K == structure.COMPACT)] = INK["compact"]
    im[bone & (K == structure.SPONGY)] = INK["bar"]; im[~bone & (K == structure.SPONGY)] = INK["space"]
    im[bone & (K == structure.CELLS)] = INK["wall"]; im[~bone & (K == structure.CELLS)] = INK["cell"]
    return im


t0 = time.time()
fields = [(kept(name), structure.Skull())]
if jaw:
    J = kept(jaw); fields.append((J, structure.Jaw.of(*J)))
tiles = []
for c in cuts:
    q = c.split(":"); axis, level = int(q[0]), float(q[1]); win = tuple(float(x) for x in q[2].split(",")); cap = q[3] if len(q) > 3 else c
    B = K = None
    for (D, lo, h), zones in fields:
        b, k = section(D, lo, h, zones, axis, level, win)
        if B is None:
            B, K = b, k
        else:
            m = b < B; K = np.where((k != 0) | m, np.where(k != 0, k, K), K); B = np.minimum(B, b)
            K[(b >= 0) & (k != 0)] = k[(b >= 0) & (k != 0)]
    im = paint(B, K)
    n = {v: int(((K == v) & ((B < 0) | (v != structure.COMPACT))).sum()) for v in (1, 2, 3)}; tot = max(sum(n.values()), 1)
    print("%s: compact %.0f%%, cancellous %.0f%%, air cells %.0f%% of the cut bone (%.0f s)" % (cap, 100 * n[1] / tot, 100 * n[2] / tot, 100 * n[3] / tot, time.time() - t0))
    tiles.append((Image.fromarray(im), cap))
f = view.font(26); pad = 16; cols = 1 if len(tiles) < 3 else 2
rows = [tiles[k:k + cols] for k in range(0, len(tiles), cols)]
cw = max(t[0].size[0] for t in tiles); rh = [max(t[0].size[1] for t in r) for r in rows]
sheet = Image.new("RGB", (cols * (cw + pad) + pad, sum(rh) + 44 * len(rows) + 120), INK["air"]); d = ImageDraw.Draw(sheet)
d.text((pad, 10), TITLE, fill=(235, 235, 235), font=view.font(30)); y = 56
for r, hh in zip(rows, rh):
    for k, (im, cap) in enumerate(r):
        x = pad + k * (cw + pad)
        sheet.paste(im, (x + (cw - im.size[0]) // 2, y + (hh - im.size[1]) // 2)); d.text((x, y + hh + 4), cap, fill=(210, 210, 210), font=f)
    y += hh + 44
x = pad
for key, word in (("compact", "compact bone"), ("bar", "cancellous (spongy) bone"), ("space", "its marrow spaces"), ("wall", "air cells' partitions"), ("cell", "air cells (mastoid)")):
    d.rectangle([x, y + 6, x + 26, y + 32], fill=INK[key], outline=(120, 120, 120)); d.text((x + 34, y + 4), word, fill=(210, 210, 210), font=f); x += 64 + int(d.textlength(word, font=f))
sheet.save(S + "/look/structure_%s.png" % tag)
sheet.thumbnail((2600, 2600)); sheet.save(S + "/look/structure_%s.jpg" % tag, quality=90)
print(S + "/look/structure_%s.jpg" % tag, sheet.size)
