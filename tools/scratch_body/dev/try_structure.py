"""try_structure.py <kept field> [--jaw <kept jaw field>] [--out tag] [--title words] [--auto] [axis:level:a0,a1,b0,b1:caption ...]: what the
bones are made of inside (structure.py), drawn as flat sections at a quarter of a millimetre: compact bone pale, cancellous bone
as its own lattice with the marrow spaces dark red, a long bone's marrow canal yellow, the mastoid's air cells blue. The kept
field is the skull's (dev/save_field.py), with the lower jaw's beside it, or one bone's in its own frame (tools/anatomy_inside.py).
axis 0: a cut at x = level (z across, y up); 2: a cut at z = level (x across, y up); 1: a cut at y = level (x across, z up).
--auto (a bone in its own frame, its length along z): two cuts lengthwise through its middle and five across."""
import os, sys, pickle, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, structure, view
from scipy import ndimage
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
arg = sys.argv[1:]
name = arg[0]
jaw = arg[arg.index("--jaw") + 1] if "--jaw" in arg else None
tag = arg[arg.index("--out") + 1] if "--out" in arg else name
TITLE = arg[arg.index("--title") + 1] if "--title" in arg else "What the bones are made of: flat sections"
cuts = [a for a in arg[1:] if a.count(":") >= 2 and arg[arg.index(a) - 1] != "--title"]
AUTO = "--auto" in arg
INK = {"air": (22, 24, 28), "compact": (238, 229, 205), "bar": (224, 184, 122), "space": (128, 44, 34), "wall": (214, 224, 230), "cell": (58, 112, 168),
       "canal": (64, 168, 120), "marrow": (226, 196, 84)}
PX = 4                                                             # picture points to the millimetre (the sections are worked at 0.25 mm)


def kept(n):
    I = pickle.load(open(S + "/sb/%s_info.pkl" % n, "rb"))
    return (np.load(S + "/sb/%s_D.npy" % n, mmap_mode="r"), np.asarray(I["lo"], float), float(I["h"])), I


def section(D, lo, h, zones, axis, level, win, follow=None):
    """(B, kind) on the picture's own grid (rows downward), with a mask of where this field has anything to say.
    `follow` (a lengthwise cut of a bone in its own frame, axis 0 or 1): the cut's level at each height z, as (z, level):
    the saw keeps to a bent bone's middle line, so its hollow is not lost where the bone bends out of a flat cut."""
    (a0, a1, b0, b1) = win
    ua, va = {0: (2, 1), 2: (0, 1), 1: (0, 2)}[axis]               # the axes that run across and up the picture
    if follow is not None and (a1 - a0 if ua == 2 else b1 - b0) > 48.0:   # in lengths of 40 mm, each with little to work through
        z0, z1 = (a0, a1) if ua == 2 else (b0, b1); cut = list(np.arange(z0, z1 - 8.0, 40.0)) + [z1]; got = []
        for k in range(len(cut) - 1):
            w = (cut[k], cut[k + 1], b0, b1) if ua == 2 else (a0, a1, cut[k], cut[k + 1])
            b, kk = section(D, lo, h, zones, axis, level, w, follow)
            last = k == len(cut) - 2                                # (neighbouring lengths share their meeting line)
            got.append((b, kk) if last else ((b[:, :-1], kk[:, :-1]) if ua == 2 else (b[1:], kk[1:])))
        if ua == 2:
            return np.concatenate([g[0] for g in got], axis=1), np.concatenate([g[1] for g in got], axis=1)
        return np.concatenate([g[0] for g in got[::-1]], axis=0), np.concatenate([g[1] for g in got[::-1]], axis=0)
    levels = None
    if follow is not None:
        z0, z1 = (a0, a1) if ua == 2 else (b0, b1)
        levels = np.interp(np.linspace(z0 - 6.0, z1 + 6.0, 64), follow[0], follow[1])
    blo = np.zeros(3); bhi = np.zeros(3)
    blo[axis], bhi[axis] = (level - 8.0, level + 8.0) if levels is None else (levels.min() - 8.0, levels.max() + 8.0)
    blo[ua], bhi[ua] = a0 - 6.0, a1 + 6.0; blo[va], bhi[va] = b0 - 6.0, b1 + 6.0
    i0 = [max(int(np.floor((blo[k] - lo[k]) / h)), 0) for k in range(3)]; i1 = [min(int(np.ceil((bhi[k] - lo[k]) / h)) + 1, D.shape[k]) for k in range(3)]
    nu, nv = int(round((a1 - a0) * PX)) + 1, int(round((b1 - b0) * PX)) + 1
    B2 = np.full((nv, nu), 4.0, np.float32); K2 = np.zeros((nv, nu), np.uint8)
    if min(i1[k] - i0[k] for k in range(3)) < 4:
        return B2, K2
    A = structure.double(np.asarray(D[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]).astype(np.float32)); h2 = h / 2; l2 = lo + np.array(i0) * h
    if levels is None:
        j = int(round((level - l2[axis]) / h2))
        if j < 2 or j > A.shape[axis] - 3:
            return B2, K2
        slab = [slice(None)] * 3; slab[axis] = slice(j - 1, j + 2)
        B, kind = structure.inside(A, l2, h2, zones, slab=slab)
        take = [slice(None)] * 3; take[axis] = j; Bs = B[tuple(take)]; take[axis] = 1; Ks = kind[tuple(take)]
        if ua > va:                                                # the array's first remaining axis must be the one that runs across
            Bs, Ks = Bs.T, Ks.T
    else:                                                          # the saw's level changes with the height: one line of the block for each
        nz = A.shape[2]; kz = np.arange(nz)
        jz = np.clip(np.round((np.interp(l2[2] + h2 * kz, follow[0], follow[1]) - l2[axis]) / h2).astype(int), 2, A.shape[axis] - 3)
        j0 = int(jz.min()) - 1; slab = [slice(None)] * 3; slab[axis] = slice(j0, int(jz.max()) + 2)
        B, kind = structure.inside(A, l2, h2, zones, slab=slab)
        if axis == 0:
            Bs, Ks = B[jz, :, kz], kind[jz - j0, :, kz]            # (z first, as the picture has it: across)
        else:
            Bs, Ks = B[:, jz, kz], kind[:, jz - j0, kz]
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
    im[K == structure.CANAL] = INK["canal"]; im[K == structure.MARROW] = INK["marrow"]
    return im


t0 = time.time()
K0, I0 = kept(name)
fields = [(K0, structure.zones_for(I0, *K0))]
if jaw:
    J, I = kept(jaw); fields.append((J, structure.zones_for(I, *J)))
rows = None; FOLLOW = {}
if AUTO:                                                           # a bone in its own frame: where it lies, and the cuts that show it
    D, lo, h = K0
    ext = []
    for k in range(3):
        on = np.nonzero((np.asarray(D) < 0).any(axis=tuple(a for a in range(3) if a != k)))[0]
        ext.append((lo[k] + h * on[0] - 3.0, lo[k] + h * on[-1] + 3.0))
    L = ext[2][1] - ext[2][0] - 6.0
    c = [lo[k] + h * int(np.argmax(ndimage.gaussian_filter1d((np.asarray(D) < 0).sum(axis=tuple(a for a in range(3) if a != k)).astype(float), 2.0))) for k in range(3)]   # each lengthwise cut where it meets most bone (a bent bone's middle may lie outside it)
    win = lambda u, v: "%.1f,%.1f,%.1f,%.1f" % (ext[u][0], ext[u][1], ext[v][0], ext[v][1])
    words = getattr(fields[0][1], "words", "")
    if TITLE.startswith("What the bones"):
        TITLE = "%s: what it is made of (%s)" % (I0.get("label", name), words)
    long = I0["bone"]["class"] == "long"
    R = np.asarray(I0["axes"], float)                              # the bone's own axes in the body (x to its left, y up, z forward)

    def plane(k):                                                  # what a cut square to the bone's k-th axis is called in the body
        n = np.abs(R[k]); j = int(np.argmax(n))
        return ("cut from front to back", "cut level", "cut from side to side")[j] + ("" if n[j] > 0.8 else ", obliquely")
    j = int(np.argmax(np.abs(R[2])))
    end = ("upper" if j == 1 else ("front" if R[2, j] > 0 else "hind") if j == 2 else ("left-hand" if R[2, j] > 0 else "right-hand"))   # the end at the greater values of its length
    cuts = ["0:%.2f:%s:%s, where it meets most bone (its %s end to the right)" % (c[0], win(2, 1), plane(0), end),
            "1:%.2f:%s:%s (its %s end %s)" % (c[1], win(0, 2), plane(1), end, "to the right" if long else "at the top")]
    FOLLOW = {}
    if long:                                                       # a long bone bends: each lengthwise cut keeps to the body's middle line
        bone = np.asarray(D) < 0; nz = bone.sum(axis=(0, 1)).astype(float); zz = lo[2] + h * np.arange(bone.shape[2])
        t = (zz - (ext[2][0] + 3.0)) / L; mid = (t > 0.14) & (t < 0.86) & (nz > 0)
        for k in (0, 1):
            ck = lo[k] + h * (bone.sum(axis=1 - k) * np.arange(bone.shape[k])[:, None]).sum(axis=0) / np.maximum(nz, 1.0)
            ck = np.interp(zz, zz[mid], ck[mid])                   # (held at the body's ends through the extremities)
            FOLLOW[k] = (zz, ndimage.gaussian_filter1d(ck, 10.0 / h, mode="nearest"))
        cuts = ["0:%.2f:%s:%s along its middle line (its %s end to the right)" % (c[0], win(2, 1), plane(0), end),
                "1:%.2f:%s:%s along its middle line (its %s end to the right)" % (c[1], win(0, 2), plane(1), end)]
    shares = (0.06, 0.25, 0.5, 0.75, 0.94) if long else (0.2, 0.5, 0.8)
    for q in shares:
        z = ext[2][1] - 3.0 - q * L
        cuts.append("2:%.2f:%s:%s, %.0f mm from its %s end" % (z, win(0, 1), "cut across" if long else plane(2), q * L, end))
    rows = [[0], list(range(1, len(cuts)))]
tiles = []
for c in cuts:
    q = c.split(":"); axis, level = int(q[0]), float(q[1]); win = tuple(float(x) for x in q[2].split(",")); cap = q[3] if len(q) > 3 else c
    B = K = None
    for (D, lo, h), zones in fields:
        b, k = section(D, lo, h, zones, axis, level, win, FOLLOW.get(axis) if AUTO else None)
        if B is None:
            B, K = b, k
        else:
            m = b < B; K = np.where((k != 0) | m, np.where(k != 0, k, K), K); B = np.minimum(B, b)
            K[(b >= 0) & (k != 0)] = k[(b >= 0) & (k != 0)]
    im = paint(B, K)
    if AUTO and axis == 1 and I0["bone"]["class"] == "long":       # (z up the picture: laid along the sheet instead)
        im = np.rot90(im, -1)
    n = {v: int(((K == v) & ((B < 0) | (v != structure.COMPACT))).sum()) for v in (1, 2, 3, 5)}; tot = max(sum(n.values()), 1)
    print("%s: compact %.0f%%, cancellous %.0f%%, marrow canal %.0f%%, air cells %.0f%% of the cut (%.0f s)" % (cap, 100 * n[1] / tot, 100 * n[2] / tot, 100 * n[5] / tot, 100 * n[3] / tot, time.time() - t0))
    tiles.append((Image.fromarray(im), cap))
f = view.font(24); pad = 16
if rows is None:
    cols = 1 if len(tiles) < 3 else 2
    rows = [list(range(k, min(k + cols, len(tiles)))) for k in range(0, len(tiles), cols)]
rows = [[tiles[k] for k in r] for r in rows]
width = lambda t: max(t[0].size[0], int(view.font(24).getlength(t[1])) + 8)
rw = [sum(width(t) + pad for t in r) + pad for r in rows]; rh = [max(t[0].size[1] for t in r) for r in rows]
legend = [("compact", "compact bone"), ("bar", "cancellous (spongy) bone"), ("space", "its marrow spaces (red marrow)"), ("marrow", "marrow canal (yellow marrow)"),
          ("wall", "air cells' partitions"), ("cell", "air cells"), ("canal", "canal for a nerve and vessels")]
used = set()
for im, cap in tiles:
    a = np.asarray(im).reshape(-1, 3)
    for key, word in legend:
        if (a == np.array(INK[key], np.uint8)).all(axis=1).any():
            used.add(key)
legend = [(k, w) for k, w in legend if k in used]
lw = sum(64 + int(f.getlength(w)) for k, w in legend) + 2 * pad
tf = view.font(30)
sheet = Image.new("RGB", (max(max(rw), lw, int(tf.getlength(TITLE)) + 2 * pad), sum(rh) + 44 * len(rows) + 120), INK["air"]); d = ImageDraw.Draw(sheet)
d.text((pad, 10), TITLE, fill=(235, 235, 235), font=tf); y = 56
for r, hh in zip(rows, rh):
    x = pad
    for im, cap in r:
        w = width((im, cap))
        sheet.paste(im, (x + (w - im.size[0]) // 2, y + (hh - im.size[1]) // 2)); d.text((x, y + hh + 6), cap, fill=(210, 210, 210), font=f)
        x += w + pad
    y += hh + 44
x = pad
for key, word in legend:
    d.rectangle([x, y + 6, x + 26, y + 32], fill=INK[key], outline=(120, 120, 120)); d.text((x + 34, y + 4), word, fill=(210, 210, 210), font=f); x += 64 + int(f.getlength(word))
sheet.save(S + "/look/structure_%s.png" % tag)
sheet.thumbnail((2700, 2700)); sheet.save(S + "/look/structure_%s.jpg" % tag, quality=90)
print(S + "/look/structure_%s.jpg" % tag, sheet.size)
