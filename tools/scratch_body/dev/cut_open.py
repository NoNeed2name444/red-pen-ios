"""cut_open.py <kept field> [<second field> ...] [--set name] [--out tag] [--inside] [--only 0,2]: the head sawn open, to look at what is inside the bones
(the air sinuses above all). Each kept field (dev/save_field.py, dev/try_sinus.py --save) is cut by a flat saw and drawn from the
sawn side; with two fields the same cuts are drawn one above the other (before, now). --inside: the bone's own make-up is
shown on the sawn face (compact shell, cancellous bone, the mastoid's cells), worked at a quarter of a millimetre."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, view, structure
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
names = [a for a in sys.argv[1:] if not a.startswith("--") and sys.argv[sys.argv.index(a) - 1] not in ("--set", "--out", "--labels", "--only", "--jaw", "--title")]
which = sys.argv[sys.argv.index("--set") + 1] if "--set" in sys.argv else "sinus"
labels = sys.argv[sys.argv.index("--labels") + 1].split(",") if "--labels" in sys.argv else names
INSIDE = "--inside" in sys.argv
TITLE = sys.argv[sys.argv.index("--title") + 1] if "--title" in sys.argv else None
ONLY = [int(i) for i in sys.argv[sys.argv.index("--only") + 1].split(",")] if "--only" in sys.argv else None
# a cut: (caption, the saw's plane as (axis, level, which side is kept: +1 the larger coordinates), eye, centre, span, block)
SETS = {
    "sinus": [("sawn down the middle, a little left of it: the left half from the right", (0, 4.6, 1), (-1, 0.05, 0.12), (4.6, 10, 58), 104, ((0, -42, 6), (60, 62, 110))),
              ("sawn across through the orbits: the hind part from in front", (2, 66.0, -1), (0, 0.05, 1), (0, 0, 66), 100, ((-56, -46, 20), (56, 58, 70))),
              ("sawn level through the orbits: the lower part from above", (1, 13.0, -1), (0, 1, 0.08), (0, 13, 58), 104, ((-56, -30, 6), (56, 16, 110))),
              ("sawn across through the forehead: the hind part from in front", (2, 91.0, -1), (0, 0.05, 1), (0, 22, 91), 80, ((-45, -12, 60), (45, 62, 94)))],
    "sinus2": [("sawn down through the left upper jaw: the outer part from the middle", (0, 22.0, 1), (-1, 0.05, 0.1), (22, -12, 62), 80, ((18, -46, 30), (60, 20, 100))),
               ("sawn across through the sphenoid's body: the hind part from in front", (2, 30.0, -1), (0, 0.1, 1), (0, 4, 30), 80, ((-45, -30, -5), (45, 45, 33))),
               ("sawn across behind the orbits: the hind part from in front", (2, 52.0, -1), (0, 0.05, 1), (0, 0, 52), 100, ((-56, -46, 10), (56, 58, 55))),
               ("sawn level through the upper jaws: the lower part from above", (1, -12.0, -1), (0, 1, 0.08), (0, -12, 62), 104, ((-56, -46, 20), (56, -9, 106)))],
    "inside": [("sawn down the middle, a little left of it: the left half from the right", (0, 4.6, 1), (-1, 0.05, 0.12), (4.6, 14, 3), 232, ((0, -104, -104), (82, 122, 112))),
               ("the same, close: the face and the front of the base", (0, 4.6, 1), (-1, 0.05, 0.12), (4.6, 10, 58), 104, ((0, -42, 6), (60, 62, 110))),
               ("sawn across through the ear holes: the front part from behind", (2, -8.0, 1), (0, 0.05, -1), (0, 12, -8), 216, ((-82, -104, -8), (82, 122, 70))),
               ("sawn across through the orbits and the molars: the hind part from in front", (2, 62.0, -1), (0, 0.05, 1), (0, -20, 62), 168, ((-70, -104, 12), (70, 62, 66))),
               ("sawn level above the ear holes: the lower part from above", (1, 5.0, -1), (0, 1, 0.08), (0, 5, 2), 196, ((-82, -40, -104), (82, 8, 112))),
               ("the lower jaw sawn level through the sockets of its teeth (the teeth taken out): from above", (1, -60.0, -1), (0, 1, 0.08), (0, -60, 42), 124, ((-66, -84, -8), (66, -56, 102)))],
}


def block(D, lo, h, blo, bhi):
    i0 = [max(int(np.floor((blo[k] - lo[k]) / h)), 0) for k in range(3)]; i1 = [min(int(np.ceil((bhi[k] - lo[k]) / h)) + 1, D.shape[k]) for k in range(3)]
    if min(i1[k] - i0[k] for k in range(3)) < 3:
        return None, None
    return np.asarray(D[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]).astype(np.float32), lo + np.array(i0) * h


def saw(A, l2, h, axis, level, keep):
    ax = l2[axis] + h * np.arange(A.shape[axis]); shape = [1, 1, 1]; shape[axis] = -1
    A = np.maximum(A, (keep * (level - ax)).reshape(shape))                 # the saw: nothing is left on the far side of its plane
    if float(A.min()) >= 0:                                                 # (no bone of this field behind the saw here)
        return None
    A = np.pad(A, 1, constant_values=4.0)                                   # (closed at the block's edges)
    v, f = sdf.mesh(A, l2 - h, h)
    return (v, f, view.BONE) if len(f) else None


def pieces(name, zones, cut):
    """The meshes of one kept field behind the saw. With --inside: the 6 mm behind the saw worked at a quarter of a
    millimetre with the bone's make-up in it (structure.py), the rest as it was, a little further back."""
    cap, (axis, level, keep), eye, c, span, (blo, bhi) = cut
    I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); h = float(I["h"]); lo = np.asarray(I["lo"], float)
    D = np.load(S + "/sb/%s_D.npy" % name, mmap_mode="r")
    if zones is None or not INSIDE:
        A, l2 = block(D, lo, h, blo, bhi)
        return [] if A is None else [saw(A, l2, h, axis, level, keep)]
    if zones == "jaw":
        zones = structure.Jaw.of(D, lo, h)
    out = []
    A, l2 = block(D, lo, h, blo, bhi)
    if A is not None:
        out.append(saw(A, l2, h, axis, level + keep * 5.0, keep))            # the rest
    b0, b1 = np.array(blo, float), np.array(bhi, float)
    b0[axis] = level - 10.0; b1[axis] = level + 10.0                         # (room either side, for the depth under the surface)
    A, l2 = block(D, lo, h, b0, b1)
    if A is not None:
        A = structure.double(A); h2 = h / 2
        j = int(round((level - l2[axis]) / h2)); n6 = int(round(6.0 / h2))
        if 2 < j < A.shape[axis] - 3:
            ja, jb = (j - 2, min(j + n6, A.shape[axis])) if keep > 0 else (max(j - n6, 0), j + 3)
            slab = [slice(None)] * 3; slab[axis] = slice(ja, jb)
            A, _ = structure.inside(A, l2, h2, zones, slab=slab)
            A = A[tuple(slab)]; l3 = l2.copy(); l3[axis] += ja * h2
            out.append(saw(A, l3, h2, axis, level, keep))
    return out


def sawn(names, cut):
    cap, (axis, level, keep), eye, c, span, (blo, bhi) = cut
    meshes = [m for n, z in names for m in pieces(n, z, cut) if m is not None]
    return view.picture(meshes, eye, 900, frame=(np.array(c, float), float(span)))


JAW = sys.argv[sys.argv.index("--jaw") + 1] if "--jaw" in sys.argv else None
rows = []
for name, lab in zip(names, labels):
    parts = [(name, structure.Skull())] + ([(JAW, "jaw")] if JAW else [])
    rows.append([(sawn(parts, cut), "%s: %s" % (lab, cut[0])) for i, cut in enumerate(SETS[which]) if ONLY is None or i in ONLY])
if len(names) == 1 and len(rows[0]) > 3:
    k = (len(rows[0]) + 1) // 2; rows = [rows[0][:k], rows[0][k:]]
tag = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "%s_%s" % (names[-1], which)
view.sheet(rows, S + "/look/%s.png" % tag, TITLE if TITLE else "sawn open: %s" % ", ".join(labels))
im = Image.open(S + "/look/%s.png" % tag); im.thumbnail((2700, 2700)); im.convert("RGB").save(S + "/look/%s.jpg" % tag, quality=88)
print(S + "/look/%s.jpg" % tag, im.size)
