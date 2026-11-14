"""The skeleton's bones made right, one group at a time, on a built atlas (the 206-bone work: docs/sciences/bones-206.md
lists every bone, tools/anatomy_bone_audit.py measures them).

    python3 tools/anatomy_bone_fix.py <atlas folder>

remake(folder) is the build's step: it runs after the ribs (tools/anatomy_ribs.py) and before the muscles that
attach to the bones, and does nothing to a group it has made already.

The hand (the man's, both sides). The atlas had each carpus as one lump and every metacarpal and phalanx cut flat
at its joints, from a 1.5 mm scan of another man. Here all 27 bones of the hand come from the Visible Human Male's
own CT (NLM, the slices of his left hand, 0.94 mm across and 1 mm apart): the CT is resampled to 0.5 mm, each bone
seeded from points inside it (HAND_ANCHORS, read off the scan once by hand) and grown to the joint spaces round it
by a watershed on a sheet filter, which finds the thin dark layer of cartilage between two bones; each bone is then
made solid (its marrow filled), meshed smooth and simplified to its budget. The right hand is the left mirrored.

The bones are set into the body as an articulated hand, so that each keeps its own shape and the hand the atlas's
pose and size, inside its skin: the carpus, with the metacarpals' bases, is one similarity fitted to the atlas's
metacarpal bases, wrist and carpus; then, joint by joint out to the fingertips, each bone is turned about the joint
it shares with the bone before it until its far joint (or tip) lies on the atlas's, and stretched along its length
to reach it (across, it takes its finger's mean stretch). Last, the carpus is moved out of the radius and ulna if
it reaches into them.

Sources (the build's): BONEFIX_VHCT, a folder holding the Visible Human CT's slices as anatomy_skull.py reads them
(male/cvm<n>f.png and .txt); BONEFIX_CACHE, where the meshed scan is kept (default ~/.cache/anatomy_bone_fix).
"""
import hashlib
import json
import os
import re
import sys
import time

import numpy as np
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

VHCT = os.environ.get("BONEFIX_VHCT", "/tmp/claude-0/-home-user/da8cf5cf-b385-5646-a716-c25fc72fb88a/scratchpad/vhct")
CACHE = os.environ.get("BONEFIX_CACHE", os.path.expanduser("~/.cache/anatomy_bone_fix"))


def log(*a):
    print(*a, flush=True)


# MARK: the hand from the Visible Human Male's CT

# The slices of his left hand (it lies on his left hip, palm in), and the box round it in each slice. The scan's
# series changes at slice 1850 (location -863 mm to -170 mm, the body unmoved) and the later slices sit 1 row down
# and 2 columns left of the earlier ones. Rows from HAND_BACK on hold the hip and thigh, left out.
HAND_SLICES = (1730, 1930)
HAND_ROWS, HAND_COLS = (30, 250), (290, 512)
HAND_SEAM = (1850, 1, -2)
HAND_BACK = 150
HAND_PX = 0.9375            # mm across a pixel in these slices (and the slices 1 mm apart)
GRID = 0.5                  # mm, the grid the scan is resampled to
BONE_HU = 220.0             # the bone's edge in the resampled, lightly smoothed scan
SHEET_SIGMA = 1.2           # grid steps, the scale of the joint-space filter
# Points inside each bone, in the 0.5 mm grid's steps (slice, row, column) from the box's first slice, row and column:
# three along each long bone, one in each small one. Read off the scan by hand (the joints found on sections along
# each finger), so that the bones come out the same every build.
HAND_ANCHORS = {
    "radius": [[74, 220, 278], [50, 220, 295], [17, 230, 300]], "ulna": [[98, 240, 307], [85, 254, 313], [66, 275, 319]],
    "scaphoid": [[100, 185, 226], [92, 183, 238], [85, 184, 257]], "lunate": [[103, 198, 279]],
    "triquetrum": [[129, 196, 274]], "pisiform": [[129, 220, 265]], "trapezium": [[98, 170, 196]],
    "trapezoid": [[103, 169, 228]], "capitate": [[124, 168, 243], [119, 175, 239], [113, 183, 250]],
    "hamate": [[153, 191, 250], [152, 192, 262], [127, 192, 261]],
    "mc1": [[121, 133, 134], [103, 160, 142], [94, 151, 172]], "mc2": [[175, 105, 162], [147, 108, 186], [124, 130, 198]],
    "mc3": [[205, 115, 192], [179, 126, 211], [154, 140, 225]], "mc4": [[216, 152, 206], [196, 146, 230], [171, 152, 240]],
    "mc5": [[227, 171, 232], [205, 186, 240], [186, 185, 258]],
    "thumb_p": [[172, 131, 75], [157, 132, 85], [142, 127, 103]], "thumb_d": [[196, 118, 59]],
    "index_p": [[256, 98, 89], [240, 95, 109], [220, 84, 123]], "index_m": [[284, 116, 41], [277, 106, 49], [272, 102, 55]],
    "index_d": [[294, 123, 22]],
    "middle_p": [[285, 107, 118], [256, 100, 130], [239, 104, 141]], "middle_m": [[314, 123, 49], [309, 117, 67], [300, 111, 82]],
    "middle_d": [[326, 135, 27]],
    "ring_p": [[296, 125, 144], [274, 129, 161], [267, 129, 181]], "ring_m": [[331, 140, 88], [331, 141, 108], [314, 132, 111]],
    "ring_d": [[345, 142, 65]],
    "little_p": [[302, 168, 193], [281, 165, 195], [271, 175, 203]], "little_m": [[339, 173, 156], [322, 163, 163], [317, 160, 177]],
    "little_d": [[350, 169, 138]],
}
CARPALS = ["scaphoid", "lunate", "triquetrum", "pisiform", "trapezium", "trapezoid", "capitate", "hamate"]
RAYS = [["mc1", "thumb_p", "thumb_d"], ["mc2", "index_p", "index_m", "index_d"], ["mc3", "middle_p", "middle_m", "middle_d"],
        ["mc4", "ring_p", "ring_m", "ring_d"], ["mc5", "little_p", "little_m", "little_d"]]
ORD = ["first", "second", "third", "fourth", "fifth"]
FINGER = {"thumb": "thumb", "index": "index_finger", "middle": "middle_finger", "ring": "ring_finger", "little": "little_finger"}
KIND = {"p": "proximal", "m": "middle", "d": "distal"}
# UBERON ids of the carpals (the metacarpals and phalanges keep the ids they have)
CARPAL_UBERON = {"scaphoid": "UBERON:0001427", "lunate": "UBERON:0001428", "triquetrum": "UBERON:0002445",
                 "pisiform": "UBERON:0001429", "trapezium": "UBERON:0001430", "trapezoid": "UBERON:0001431",
                 "capitate": "UBERON:0001432", "hamate": "UBERON:0001433"}
# Triangles for each bone (the carpus had 1,500 as one lump; the rest keep about what they had).
BUDGET = {"capitate": 260, "hamate": 250, "scaphoid": 240, "lunate": 220, "trapezium": 230, "trapezoid": 200,
          "triquetrum": 200, "pisiform": 160, "mc1": 400, "mc2": 400, "mc3": 400, "mc4": 400, "mc5": 400,
          "p": 300, "m": 250, "d": 210}
CLEAR = 0.0006              # m: the carpus kept this far from the radius and ulna


def budget_of(name):
    return BUDGET.get(name) or BUDGET[name.split("_")[1]]


def ts_node(name, side):
    """The atlas's node for a metacarpal or phalanx (TotalSegmentator's names)."""
    if name.startswith("mc"):
        return f"TS_{ORD[int(name[2]) - 1]}_metacarpal_{side}"
    finger, kind = name.split("_")
    return f"TS_{KIND[kind]}_phalanx_of_{FINGER[finger]}_{side}"


def vh_node(name, side, prefix="VH_M_"):
    if name in CARPALS:
        return f"{prefix}{name}_{side}"
    return prefix + ts_node(name, side)[3:]


def vh_label(name, side):
    s = "left" if side == "L" else "right"
    if name in CARPALS:
        return f"{s} {name}"
    if name.startswith("mc"):
        return f"{s} {ORD[int(name[2]) - 1]} metacarpal"
    finger, kind = name.split("_")
    return f"{s} {KIND[kind]} phalanx of {FINGER[finger].replace('_', ' ')}"


def _slice_files(n):
    return os.path.join(VHCT, "male", f"cvm{n}f.png"), os.path.join(VHCT, "male", f"cvm{n}f.txt")


def scan_digest():
    """SHA-256 of the lines "<file> <its SHA-256>" for the slices used, in order (as anatomy_skull.py pins its own)."""
    lines = []
    for n in range(HAND_SLICES[0], HAND_SLICES[1] + 1):
        for p in _slice_files(n):
            lines.append(f"{os.path.basename(p)} {hashlib.sha256(open(p, 'rb').read()).hexdigest()}\n")
    return hashlib.sha256("".join(lines).encode()).hexdigest()


def hand_scan():
    """The hand's box of the scan, HU, (slices, rows, columns), the seam put right and the hip left out."""
    from PIL import Image
    sl = []
    for n in range(HAND_SLICES[0], HAND_SLICES[1] + 1):
        png, txt = _slice_files(n)
        head = open(txt, "rb").read().decode("latin-1")
        ps = float(re.search(r"Image pixel size - X[.\s]*:\s*([\d.]+)", head).group(1))
        if abs(ps - HAND_PX) > 1e-6:
            raise ValueError(f"slice {n}: pixel size {ps}, not {HAND_PX}")
        a = np.asarray(Image.open(png)).astype(np.float32) - 1024.0
        sl.append(a[HAND_ROWS[0]:HAND_ROWS[1], HAND_COLS[0]:HAND_COLS[1]])
    v = np.stack(sl)
    k = HAND_SEAM[0] - HAND_SLICES[0]
    v[k:] = np.roll(np.roll(v[k:], HAND_SEAM[1], 1), HAND_SEAM[2], 2)
    v[:, HAND_BACK:, :] = -1000.0
    return v


def hand_labels(v):
    """Each bone's voxels on the 0.5 mm grid: (labels, names)."""
    from skimage.segmentation import watershed
    u = ndi.zoom(v, (1.0 / GRID, HAND_PX / GRID, HAND_PX / GRID), order=3)
    g = ndi.gaussian_filter(u, 0.5)
    m = g > BONE_HU
    lab, n = ndi.label(m)
    sz = np.bincount(lab.ravel()); sz[0] = 0
    m = ndi.binary_fill_holes(lab == sz.argmax())
    # the joint spaces: thin dark sheets between bright bone (the Hessian's one large positive eigenvalue)
    roi = ndi.binary_dilation(m, iterations=2)
    idx = np.nonzero(roi)
    H = np.empty((len(idx[0]), 3, 3), np.float32)
    for i in range(3):
        for j in range(i, 3):
            o = [0, 0, 0]; o[i] += 1; o[j] += 1
            H[:, i, j] = (ndi.gaussian_filter(u, SHEET_SIGMA, order=o) * SHEET_SIGMA ** 2)[idx]
            H[:, j, i] = H[:, i, j]
    w = np.linalg.eigvalsh(H)
    l3, l2, l1 = w[:, 2], np.abs(w[:, 1]), np.abs(w[:, 0])
    sheet = np.where(l3 > 0, l3 * np.exp(-(np.maximum(l2, l1) / (l3 + 1e-6)) ** 2 / 0.5), 0)
    S = np.zeros(u.shape, np.float32); S[idx] = sheet
    elev = ndi.gaussian_filter(S, 0.7) - 0.02 * np.clip(g, 0, 1500)
    names = list(HAND_ANCHORS)
    mk = np.zeros(u.shape, np.int32)
    for i, nm in enumerate(names, 1):
        for z, r, c in HAND_ANCHORS[nm]:
            mk[max(z - 2, 0):z + 3, max(r - 2, 0):r + 3, max(c - 2, 0):c + 3] = i
    mk[~m] = 0
    return watershed(elev, mk, mask=m).astype(np.int16), names


def solid(m):
    """A bone as a solid: its marrow, open to the outside where the cortex is thin at 1 mm, filled slice by slice
    along each axis, then the whole closed and filled."""
    m = ndi.binary_fill_holes(m)
    for ax in range(3):
        st = np.zeros((3, 3, 3), bool)
        sl = [slice(None)] * 3; sl[ax] = 1
        st[tuple(sl)] = ndi.generate_binary_structure(2, 1)
        m = m | ndi.binary_fill_holes(m, structure=st)
    ball = np.zeros((5, 5, 5), bool)
    zz, yy, xx = np.mgrid[-2:3, -2:3, -2:3]; ball[zz ** 2 + yy ** 2 + xx ** 2 <= 4] = True
    m = ndi.binary_closing(np.pad(m, 3), structure=ball)[3:-3, 3:-3, 3:-3] | m
    return ndi.binary_fill_holes(m)


def taubin(v, f, rounds=6, lam=0.5, mu=-0.53):
    import scipy.sparse as sp
    e = np.unique(np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1), axis=0)
    A = sp.coo_matrix((np.ones(2 * len(e)), (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(len(v), len(v))).tocsr()
    deg = np.maximum(np.asarray(A.sum(1)).ravel(), 1)
    for _ in range(rounds):
        for k in (lam, mu):
            v = v + k * (A @ v / deg[:, None] - v)
    return v


def signed_volume(v, f):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    return float(np.einsum("ij,ij->i", a - a.mean(0), np.cross(b - a.mean(0), c - a.mean(0))).sum() / 6)


def mesh_bone(m, lo, target=900):
    """A smooth closed surface round one bone's voxels (m, its box starting at grid index lo): the signed
    distance, doubled in resolution and smoothed a little, cut at zero; metres, atlas axes (x to the body's left,
    y up, z forward)."""
    import fast_simplification
    from skimage.measure import marching_cubes
    din = ndi.distance_transform_edt(m, sampling=GRID)
    dout = ndi.distance_transform_edt(~m, sampling=GRID)
    sd = ndi.gaussian_filter(ndi.zoom(dout - din, 2, order=1), 0.9)
    vv, ff, _, _ = marching_cubes(sd, 0.0, spacing=(GRID / 2,) * 3)
    vv = vv + np.asarray(lo) * GRID
    # grid (slice, row, column) to mm: slices 1 mm apart from the first, rows and columns HAND_PX apart in the image
    z = HAND_SLICES[0] + vv[:, 0]
    r = HAND_ROWS[0] * HAND_PX + vv[:, 1]
    c = HAND_COLS[0] * HAND_PX + vv[:, 2]
    P = np.stack([c, -z, -r], 1) / 1000.0
    vs, fs = fast_simplification.simplify(P.astype(np.float32), ff.astype(np.int32),
                                          target_reduction=max(0.0, 1 - target / len(ff)), agg=7)
    vs = taubin(vs.astype(np.float64), fs.astype(np.int64))
    fs = fs.astype(np.int64)
    if signed_volume(vs, fs) < 0:
        fs = fs[:, ::-1].copy()
    return vs, fs


def hand_from_ct(quiet=True):
    """{bone: (vertices m, faces)} of the man's left hand, and the radius's and ulna's joint points with the carpus;
    from the cache when made already."""
    key = hashlib.sha256(json.dumps([HAND_SLICES, HAND_ROWS, HAND_COLS, HAND_SEAM, HAND_BACK, GRID, BONE_HU, SHEET_SIGMA,
                                     HAND_ANCHORS, 2]).encode()).hexdigest()[:16]
    path = os.path.join(CACHE, f"hand-{key}.npz")
    if os.path.exists(path):
        z = np.load(path)
        bones = {k[2:]: (z[k].astype(np.float64), z["f_" + k[2:]].astype(np.int64)) for k in z.files if k.startswith("v_")}
        return bones, {k[2:]: z[k] for k in z.files if k.startswith("p_")}
    t0 = time.time()
    v = hand_scan()
    lab, names = hand_labels(v)
    if not quiet:
        log(f"  hand: scan segmented ({time.time() - t0:.0f} s)")
    bones, points = {}, {}
    for i, nm in enumerate(names, 1):
        b = lab == i
        cl, nc = ndi.label(b)
        if nc > 1:
            sz = np.bincount(cl.ravel()); sz[0] = 0; b = cl == sz.argmax()
        if nm in ("radius", "ulna"):
            continue
        idx = np.argwhere(b); lo = np.maximum(idx.min(0) - 6, 0); hi = idx.max(0) + 7
        sub = solid(b[lo[0]:hi[0], lo[1]:hi[1], lo[2]:hi[2]])
        bones[nm] = mesh_bone(sub, lo, 900)
    # the radius's and ulna's faces to the carpus, for placing it
    def near(name, others, reach):
        a = lab == names.index(name) + 1
        o = np.isin(lab, [names.index(x) + 1 for x in others])
        p = np.argwhere(a & ndi.binary_dilation(o, iterations=reach)).astype(float) * GRID
        return np.stack([HAND_COLS[0] * HAND_PX + p[:, 2], -(HAND_SLICES[0] + p[:, 0]), -(HAND_ROWS[0] * HAND_PX + p[:, 1])], 1).mean(0) / 1000
    points["radius"] = near("radius", ["scaphoid", "lunate"], 2)
    points["ulna"] = near("ulna", ["triquetrum", "lunate"], 12)
    os.makedirs(CACHE, exist_ok=True)
    np.savez_compressed(path, **{"v_" + k: v for k, (v, f) in bones.items()}, **{"f_" + k: f for k, (v, f) in bones.items()},
                        **{"p_" + k: p for k, p in points.items()})
    if not quiet:
        log(f"  hand: {len(bones)} bones meshed ({time.time() - t0:.0f} s)")
    return bones, points


# MARK: setting the hand into a body

def surface_points(v, f, h):
    from anatomy_bone_audit import surface_samples
    return surface_samples(v, f, h)


def joint_centre(A, B, reach=0.0025):
    """The middle of the joint between two bones: the points of each within reach of the other."""
    pa, pb = surface_points(*A, 0.0008), surface_points(*B, 0.0008)
    ta, tb = cKDTree(pa), cKDTree(pb)
    da, db = tb.query(pa)[0], ta.query(pb)[0]
    for r in (reach, 2 * reach, 4 * reach, 8 * reach):
        sel = np.vstack([pa[da < r], pb[db < r]])
        if len(sel) > 20:
            return sel.mean(0)
    return 0.5 * (pa.mean(0) + pb.mean(0))


def end_of(v, toward, share=0.1, far=False):
    """The middle of a long bone's end nearer (far: further from) the point `toward`."""
    c = v.mean(0)
    a = np.linalg.eigh(np.cov((v - c).T))[1][:, -1]
    if ((toward - c) @ a < 0) != far:
        a = -a
    t = (v - c) @ a
    return v[t > t.max() - share * (t.max() - t.min())].mean(0)


def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(a @ b)
    if np.linalg.norm(v) < 1e-12:
        return np.eye(3)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def set_hand(ct, ctp, atlas, side, quiet=True):
    """The CT hand (a left hand; mirrored here for the right) set into the atlas's hand: {bone: (v, f)}, and notes."""
    from anatomy_bones import umeyama
    if side == "R":
        flip = np.array([-1.0, 1.0, 1.0])
        ct = {k: (v * flip, f[:, ::-1].copy()) for k, (v, f) in ct.items()}
        ctp = {k: p * flip for k, p in ctp.items()}
    A = {b: atlas[ts_node(b, side)] for r in RAYS for b in r}
    blob = atlas[f"TS_carpal_bones_{side}"]
    rad, uln = atlas[f"TS_radius_{side}"], atlas[f"TS_ulna_{side}"]
    notes = []
    aJ, cJ = {}, {}
    for r in RAYS:
        for a, b in zip(r[:-1], r[1:]):
            aJ[(a, b)] = joint_centre(A[a], A[b]); cJ[(a, b)] = joint_centre(ct[a], ct[b])
    for r in RAYS:
        aJ[(r[-1], None)] = end_of(A[r[-1]][0], aJ[(r[-2], r[-1])], 0.08, far=True)
        cJ[(r[-1], None)] = end_of(ct[r[-1]][0], cJ[(r[-2], r[-1])], 0.08, far=True)
    carpus_ct = np.vstack([ct[c][0] for c in CARPALS]).mean(0)
    aBase = {r[0]: end_of(A[r[0]][0], blob[0].mean(0)) for r in RAYS}
    cBase = {r[0]: end_of(ct[r[0]][0], carpus_ct) for r in RAYS}
    pb = surface_points(*blob, 0.001)
    rs, us = surface_points(*rad, 0.001), surface_points(*uln, 0.001)
    a_rad = rs[cKDTree(pb).query(rs)[0] < 0.003].mean(0)
    a_uln = us[cKDTree(pb).query(us)[0] < 0.006].mean(0)
    # 1. the carpus: one similarity, on the metacarpals' bases, the wrist and the carpus's middle
    src = [cBase[r[0]] for r in RAYS] + [ctp["radius"], ctp["ulna"], carpus_ct]
    dst = [aBase[r[0]] for r in RAYS] + [a_rad, a_uln, blob[0].mean(0)]
    wts = [2, 2, 2, 2, 2, 3, 1, 1]
    rep = np.repeat(np.arange(len(src)), wts)
    s, R, t = umeyama(np.array(src)[rep], np.array(dst)[rep])
    put = lambda v: (s * (R @ np.asarray(v).T)).T + t
    miss = np.linalg.norm(put(np.array(src)) - np.array(dst), axis=1) * 1000
    notes.append(f"carpus x{s:.3f}, off its marks by {miss.mean():.1f} mm (most {miss.max():.1f})")
    out = {c: (put(ct[c][0]), ct[c][1]) for c in CARPALS}
    # 2. the rays, joint by joint: each bone turned about the joint before it (its base, for the metacarpals) so its
    # far joint lies on the atlas's, stretched along its length to reach it and across by its ray's mean stretch
    for r in RAYS:
        starts = {r[0]: (cBase[r[0]], put(cBase[r[0]][None])[0])}
        stretch = []
        rots = {}
        prevR = R
        plan = []
        for k, b in enumerate(r):
            p_ct, p_new = starts[b]
            q_ct = cJ[(b, r[k + 1])] if k + 1 < len(r) else cJ[(b, None)]
            q_at = aJ[(b, r[k + 1])] if k + 1 < len(r) else aJ[(b, None)]
            d_ct = prevR @ (q_ct - p_ct)
            d_at = q_at - p_new
            Rb = rot_between(d_ct, d_at) @ prevR
            L = np.linalg.norm(d_at) / np.linalg.norm(q_ct - p_ct)
            stretch.append(L)
            plan.append((b, p_ct, p_new, q_ct, Rb, L))
            if k + 1 < len(r):
                starts[r[k + 1]] = (q_ct, q_at)
            prevR = Rb
        across = float(np.mean(stretch))
        for b, p_ct, p_new, q_ct, Rb, L in plan:
            a = (q_ct - p_ct) / np.linalg.norm(q_ct - p_ct)
            Sm = across * np.eye(3) + (L - across) * np.outer(a, a)
            v = (Rb @ (Sm @ (ct[b][0] - p_ct).T)).T + p_new
            out[b] = (v, ct[b][1])
        notes.append(f"{r[0]}-{r[-1]}: stretched " + " ".join(f"{x:.2f}" for x in stretch) + f", across {across:.2f}")
    # 3. the carpus out of the radius and ulna
    from anatomy_bone_audit import Solid
    forearm = [Solid(*rad), Solid(*uln)]
    carp = np.vstack([surface_points(*out[c], 0.0006) for c in CARPALS])
    axis = (put(cBase["mc3"][None])[0] - a_rad); axis /= np.linalg.norm(axis)
    moved = 0.0
    for _ in range(20):
        deep = 0.0
        for sol in forearm:
            ins = sol.contains(carp)
            if ins.any():
                deep = max(deep, float(sol.depth(carp[ins]).max()))
        if deep <= 0:
            break
        step = deep + CLEAR
        out.update({c: (out[c][0] + axis * step, out[c][1]) for c in CARPALS})
        carp = carp + axis * step
        moved += step
    if moved:
        notes.append(f"carpus moved {moved * 1000:.1f} mm out of the radius and ulna")
    return out, notes


def simplify(v, f, target):
    import fast_simplification
    if len(f) <= target:
        return v, f
    vs, fs = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - target / len(f), agg=6)
    vs = taubin(vs.astype(np.float64), fs.astype(np.int64), rounds=2)
    return vs, fs.astype(np.int64)


def remake_hands(folder, manifest, quiet=False):
    """The man's hands, both sides. Returns what it did."""
    from anatomy_fibres import read_part
    from anatomy_bones import rewrite
    body = next((b for b in manifest["bodies"] if b["id"] == "male"), None)
    if body is None:
        return "no male body"
    arms = next((p for p in body["parts"] if p["id"] == "arms"), None)
    if arms is None or not any(st["node"] == "TS_carpal_bones_L" for st in arms["structures"]):
        return "the man's hands made already"
    ct, ctp = hand_from_ct(quiet)
    meshes = read_part(os.path.join(folder, arms["file"]))
    atlas = {st["node"]: (np.asarray(v, np.float64), np.asarray(f, np.int64)) for st, (v, f) in zip(arms["structures"], meshes)}
    for p in body["parts"]:
        if p["id"] == "skin":
            for st, (v, f) in zip(p["structures"], read_part(os.path.join(folder, p["file"]))):
                atlas[st["node"]] = (np.asarray(v, np.float64), np.asarray(f, np.int64))
    said = []
    made = {}
    for side in ("L", "R"):
        new, notes = set_hand(ct, ctp, atlas, side, quiet)
        said += [f"male {side}: {n}" for n in notes]
        made[side] = {b: simplify(v, f, budget_of(b)) for b, (v, f) in new.items()}
    structures, out = [], []
    for st, m in zip(arms["structures"], meshes):
        node = st["node"]
        side = node[-1]
        if node == f"TS_carpal_bones_{side}":
            for c in CARPALS:
                structures.append(dict(node=vh_node(c, side), label=vh_label(c, side), uberon=CARPAL_UBERON[c], tissue="bone",
                                       group=st.get("group", "Arm bones"), inner=False, made="vh-ct-hand"))
                out.append(made[side][c])
            continue
        hit = [b for r in RAYS for b in r if ts_node(b, side) == node]
        if hit and side in made:
            b = hit[0]
            nst = dict(st)
            nst["node"] = vh_node(b, side); nst["made"] = "vh-ct-hand"
            structures.append(nst)
            out.append(made[side][b])
            continue
        structures.append(st)
        out.append(m)
    arms["structures"] = structures
    rewrite(folder, arms, out)
    arms.pop("fibres", None)
    manifest.setdefault("changes", [])
    return said


def remake(folder, quiet=False):
    """Every group this step makes, in `folder`'s atlas. Returns what it did."""
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    r = remake_hands(folder, manifest, quiet)
    said += r if isinstance(r, list) else [r]
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            log("  " + line)
    return "; ".join(said[:1]) + (f" (+{len(said) - 1} more)" if len(said) > 1 else "")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
