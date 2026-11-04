"""The skull's bones from the Visible Human CT: the Visible Human Male's and
Female's own heads, scanned at 1 mm (U.S. National Library of Medicine), in
place of the NIH 3D model's bones (3DPX-020591, made from the same man's
data but drawn coarsely: its frontal bone is 828 triangles, its orbits and
sinuses plates). Called by tools/anatomy_gaps.py; not run on its own.

For each body:

1. The head's slices (HEAD: the top 291 of the scan's normal CT, PNG images
   with their GE headers) put on one grid, 0.5 mm across and 1 mm between
   slices, in Hounsfield units, each slice by its own pixel size and centre
   (the field of view widens below the head), a missing slice filled
   between its neighbours; pixels out of the scanner's range (a few corrupt
   ones) replaced by their neighbours'; in the slices with dental metal,
   bright streaks lying in one slice only flattened to soft tissue.
2. Bone: the CT smoothed (0.4 mm), above 150 HU inside the head (its outline
   2 mm in), kept where it joins dense bone (over 600 HU: thin plates kept,
   specks of soft tissue left out); in the slices with dental metal, what
   stands under 5 mm tall and further than 3 mm from the jaws' dense bone
   left out (a streak lies flat; teeth and jaws run on up and down);
   pinholes under 2 mm across closed.
3. Placed in the body: first by the head's skin (the CT's outer skin, from
   the top down as far as the body's head reaches, laid on the body's head
   skin by closest points both ways, from nine starting turns), then by the
   bone itself, laid on the model's skull already fitted to the body (by its
   eyes and teeth, anatomy_gaps.fit_skull, and for the woman carried onto
   her head by a warp) by closest points both ways, within 15, 10, 6 and
   then 4 mm, the scale free. The model is then brought onto the CT's
   bone: its mandible, the one bone that moves, fitted on its own by a
   rigid move (the woman's jaw sits some millimetres from where the warp
   carries the man's), and the whole bent onto the CT's thick bone (bend),
   so that where it stands in below it meets the CT's bone without a step.
4. The field meshed: the CT's bone wherever it covers the model's surface
   (CT bone along the surface's normal within COVER mm, over KEEP of the
   surface round each point of it), thin or not, as over the vault and the
   base, and wherever it is THICK mm thick or more within COVER mm (so a jaw
   the fit leaves a few millimetres off keeps its own chin), but not within
   COVER mm of the organ set's teeth, where the CT's own dense teeth would
   make their sockets' thin walls count as thick; the model's (a smoothed
   solid, placed by the same fit) where the CT's bone round it is both thin
   and broken into lace or missing - the orbits' floors and inner walls, the
   walls of the sinuses and the nasal cavity, which at 1 mm break up. In the
   face (within FACE_AROUND mm of the model's facial bones, FACE, and over
   FACE_CLEAR mm from its others) the model's bone stands in whole: its
   plates are paper-thin, and the woman's (thinned with age) come out of her
   CT as lace even where they cover the model's. CT bone under THICK mm
   thick further than REACH + 1 mm from the model's (specks, the conchae's
   noise) is left out. Blended over about a millimetre.
5. The surface (marching cubes) smoothed without shrinking (Taubin's steps,
   ten rounds): the grid's steps taken off, the bone's own relief kept.
6. Named: each vertex by the nearest of the model's bones or the organ
   set's teeth (within 10 mm; the rest - the neck's vertebrae, the hyoid -
   left out), smoothed over the surface; the CT's teeth left out (the organ
   set's stay); the whole simplified to BUDGET triangles at once; each
   triangle then named by the nearest bone, smoothed over its neighbours,
   and the borders between two bones straightened.

The bones come out in the body's frame under the model's names, which they
replace; anatomy_gaps.py then keeps them under the skin, sizes the brain to
them and splits the paired ones at the midline.

NLM's terms (Terms and Conditions, July 2019, which replaced its data
licence): no fees or royalties; the data credited "Courtesy of the U.S.
National Library of Medicine"; no endorsement by NLM implied.

Needs numpy, scipy, scikit-image and Pillow.
"""
import hashlib
import os
import re

import numpy as np
from scipy import ndimage, sparse
from scipy.spatial import cKDTree

VH_SOURCE = {
    "id": "nlm-visible-human-ct",
    "title": "The Visible Human Project's normal CT of the male and female heads (PNG with headers)",
    "creators": "U.S. National Library of Medicine",
    "url": "https://www.nlm.nih.gov/research/visible/visible_human.html",
    "data": "https://data.lhncbc.nlm.nih.gov/public/Visible-Human/",
    "licence": "NLM Terms and Conditions (no fees or royalties; credit \"Courtesy of the U.S. National Library of Medicine\")",
    "licenceURL": "https://www.nlm.nih.gov/databases/download/terms_and_conditions.html",
}
# Per body: the first and last of the head's slices (1 mm apart, from the
# top of the head down 290 mm), and where the scan's files are on NLM's site.
HEAD = {"male": (1006, 1296), "female": (1001, 1291)}
REMOTE = {"male": ("Male-Images/PNG_format/radiological/normalCT/", "Male-Images/PNG_format/radiological/normalCT/"),
          "female": ("Female-Images/PNG_format/radiological/normalCT/", "Female-Images/PNG_format/radiological/normalCTHeaders/")}
# SHA-256 of the lines "<file> <its SHA-256>\n" for the files used, in name order.
VH_SHA256 = {"male": "b75e1a66a927bce1df5928cb8bbd460fe76428b7ebcdfbebfb52ec55c5f146f6",
             "female": "837ef1c4c12a25a370fd7d83bb040fadcf1e91bd36a19d59d429cab99ecad31c"}
STEP = 0.5        # mm across the grid (slices are 1 mm apart)
ISO = 150.0       # HU: bone's surface
REACH = 5.0       # mm from the model's bone within which it stands in for thin or missing CT bone
COVER = 4.0       # mm along the model's surface normal within which CT bone covers it
KEEP = 0.7        # the share of the model's surface round a point the CT must cover for its own bone to be kept
THICK = 2.0       # mm: CT bone this thick is its own wherever it lies; thinner may be lace
# The face's bones (the model's names), which the model gives whole: within
# FACE_AROUND mm of them and over FACE_CLEAR mm from the model's other bones.
FACE = ("Maxilla", "Zygomatic bone", "Nasal bone", "Lacrimal bone", "Ethmoid bone", "Palatine bone", "Vomer")
FACE_AROUND = 8.0
FACE_CLEAR = 5.0
BUDGET = 80000    # triangles for the whole skull, all its bones


def log(*a):
    print(*a, flush=True)


# MARK: the scan

def _names(sex, n):
    return (f"cvm{n}f.png", f"cvm{n}f.txt") if sex == "male" else (f"cvf{n}f.png", f"c_vf{n}.txt")


def files_used(sex):
    lo, hi = HEAD[sex]
    return [name for n in range(lo, hi + 1) for name in _names(sex, n)]


def urls(sex):
    """(file, its address on NLM's site) for every file used."""
    png, txt = REMOTE[sex]; base = "https://data.lhncbc.nlm.nih.gov/public/Visible-Human/"
    return [(name, base + (png if name.endswith(".png") else txt) + name) for name in files_used(sex)]


def digest(folder, names):
    def sha(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    return hashlib.sha256("".join(f"{n} {sha(os.path.join(folder, n))}\n" for n in sorted(names)).encode()).hexdigest()


def _header(path):
    s = open(path, "rb").read().decode("latin-1")
    def num(key):
        return float(re.search(re.escape(key) + r"[.\s]*:\s*(-?[\d.e+]+)", s).group(1))
    return dict(loc=num("Image location"), ps=num("Image pixel size - X"),
                cr=num("Center R coord of plane image"), ca=num("Center A coord of plane image"))


def head_grid(sex, folder):
    """The head's CT on one grid (int16 HU): [mm down from the top slice,
    rows from the front back, columns from the patient's right to left],
    0.5 mm across and 1 mm down, the grid spanning the top slice's field of
    view; each slice resampled by its own pixel size and centre."""
    from PIL import Image
    lo, hi = HEAD[sex]; rows = []
    for n in range(lo, hi + 1):
        png, txt = _names(sex, n); rows.append((os.path.join(folder, png), _header(os.path.join(folder, txt))))
    top = rows[0][1]["loc"]; byz = {}
    for p, h in rows:   # one slice per mm: a repeated location keeps its first slice
        byz.setdefault(int(round(top - h["loc"])), (p, h))
    nz = max(byz) + 1; h0 = rows[0][1]; half = 256 * h0["ps"]; n = int(np.ceil(2 * half / STEP))
    A = h0["ca"] + half - STEP * (np.arange(n) + 0.5); R = h0["cr"] + half - STEP * (np.arange(n) + 0.5)
    AA, RR = np.meshgrid(A, R, indexing="ij"); vol = np.empty((nz, n, n), np.int16)
    for k in range(nz):
        if k in byz:
            p, h = byz[k]; a = np.asarray(Image.open(p)).astype(np.float32) - 1024.0
            i = 255.5 - (AA - h["ca"]) / h["ps"]; j = 255.5 - (RR - h["cr"]) / h["ps"]   # pixel (i, j): A = ca + (255.5 - i) ps
            vol[k] = np.round(ndimage.map_coordinates(a, [i, j], order=1, mode="constant", cval=-1024.0)).astype(np.int16)
    gaps = [k for k in range(nz) if k not in byz]
    for k in gaps:
        a, b = max(z for z in byz if z < k), min(z for z in byz if z > k); t = (k - a) / (b - a)
        vol[k] = np.round((1 - t) * vol[a] + t * vol[b]).astype(np.int16)
    log(f"  {sex}: the head's CT, {len(rows)} slices on a {vol.shape} grid; {len(gaps)} missing filled")
    return vol


def clean(hu):
    """Corrupt pixels replaced by their neighbours'; in the slices with dental
    metal (over 2400 HU), bone kept only where the slice above or below also
    has bone within 1 mm across (a streak lies in one slice, bone runs on),
    the rest set to the slice's soft tissue."""
    hu = hu.astype(np.float32); bad = (hu > 3071) | (hu < -1024)
    if bad.any():
        med = ndimage.median_filter(np.where(bad, np.nan, hu), size=(3, 1, 1))
        hu[bad] = np.nan_to_num(med[bad], nan=-1024.0)
    metal = np.flatnonzero((hu > 2400).reshape(len(hu), -1).sum(1) > 30)
    if len(metal):
        lo, hi = max(metal.min() - 4, 1), min(metal.max() + 4, len(hu) - 2)
        near = ndimage.binary_dilation(hu > ISO, structure=np.ones((1, 5, 5), bool))
        for k in range(lo, hi + 1):
            lone = (hu[k] > ISO) & ~(near[k - 1] | near[k + 1]); soft = (hu[k] > -100) & (hu[k] < 100)
            hu[k][lone] = np.median(hu[k][soft]) if soft.any() else 40.0
    log(f"  cleaned: {int(bad.sum())} corrupt pixels; dental metal in {len(metal)} slices")
    return hu


# MARK: bone

def _ball(r_mm, sp):
    r = np.ceil(r_mm / sp).astype(int); g = np.mgrid[-r[0]:r[0] + 1, -r[1]:r[1] + 1, -r[2]:r[2] + 1]
    return ((g[0] * sp[0]) ** 2 + (g[1] * sp[1]) ** 2 + (g[2] * sp[2]) ** 2) <= r_mm ** 2 + 1e-9


def _disk(r_mm):
    r = int(np.ceil(r_mm / STEP)); g = np.mgrid[-r:r + 1, -r:r + 1]
    return ((g[0] * STEP) ** 2 + (g[1] * STEP) ** 2 <= r_mm ** 2 + 1e-9)[None]


SP = np.array([1.0, STEP, STEP])


def bone_of(hu):
    """The CT smoothed, the head's inside, and its bone (step 2)."""
    sm = ndimage.gaussian_filter(hu, sigma=0.4 / SP)
    body = np.stack([ndimage.binary_fill_holes(s) for s in (sm > -300)])
    body = ndimage.binary_erosion(body, structure=_disk(2.0))
    bone = (sm > ISO) & body
    lab, n = ndimage.label(bone); dense = ndimage.maximum(sm, lab, np.arange(1, n + 1)) > 600
    bone = dense[np.maximum(lab - 1, 0)] & (lab > 0); del lab
    metal = np.flatnonzero((sm > 2400).reshape(len(sm), -1).sum(1) > 30)
    if len(metal):
        lo, hi = max(metal.min() - 4, 0), min(metal.max() + 4, len(sm) - 1)
        core = ndimage.binary_dilation(sm[lo:hi + 1] > 1200, structure=_disk(3.0))
        up = np.zeros(bone.shape, np.int16); down = np.zeros(bone.shape, np.int16)
        for k in range(len(bone)):
            up[k] = (up[k - 1] + 1) * bone[k] if k else bone[k]
        for k in range(len(bone) - 1, -1, -1):
            down[k] = (down[k + 1] + 1) * bone[k] if k < len(bone) - 1 else bone[k]
        bone[lo:hi + 1] &= core | ((up + down - 1)[lo:hi + 1] * SP[0] >= 5.0)
    return sm.astype(np.float32), body, bone


def _mesh(field, level):
    """The field's surface (marching cubes; vertices in the grid's mm), and
    each vertex's piece of the field above the level, largest first."""
    from skimage.measure import marching_cubes
    lab, n = ndimage.label(field > level)
    sizes = ndimage.sum_labels(np.ones_like(lab, np.float32), lab, np.arange(1, n + 1))
    order = np.argsort(sizes)[::-1]; rank = np.zeros(n + 1, int); rank[order + 1] = np.arange(1, n + 1)
    v, f, _, _ = marching_cubes(np.pad(field, 1, constant_values=-1024), level, spacing=tuple(SP)); v -= SP
    lr = rank[lab]; near = ndimage.distance_transform_edt(lr == 0, return_distances=False, return_indices=True)
    ix = tuple(np.clip(np.round(v / SP).astype(int), 0, np.array(lab.shape) - 1).T)
    return v, f.astype(np.int64), lr[near[0][ix], near[1][ix], near[2][ix]]


def ct_field(sm, body, bone):
    """The CT's own bone as a field for marching cubes: bone where kept,
    pinholes under 2 mm closed."""
    closed = ndimage.binary_closing(bone, structure=_ball(1.0, SP)) & body
    field = np.where(bone, sm, np.minimum(sm, ISO - 50)); field = np.where(closed & ~bone, ISO + 80, field)
    return field.astype(np.float32)


# MARK: placing it

def axes(p):
    """The grid's mm (down, back, across to the left) to the atlas's axes (m: x to the left, y up, z forward)."""
    return np.stack([p[:, 2], -p[:, 0], -p[:, 1]], 1) / 1000.0


def to_grid(p, s, R, t):
    """The atlas's points (m) back into the grid's mm, through the placement (s, R, t)."""
    a = (p - t) @ R / s * 1000.0
    return np.stack([-a[:, 1], -a[:, 2], a[:, 0]], 1)


def by_skin(hu, head, g):
    """The similarity laying the CT's outer skin on the body's head skin
    (points, m), from nine starting turns."""
    from skimage.measure import marching_cubes
    sm = ndimage.gaussian_filter(hu[:, ::2, ::2], sigma=1.0)     # 1 mm across
    out = np.stack([ndimage.binary_fill_holes(s) for s in (sm > -400)])   # the sinuses, airway and ear canals are not skin
    lab, n = ndimage.label(out); out = lab == (1 + np.argmax(ndimage.sum(out, lab, range(1, n + 1))))
    v, _, _, _ = marching_cubes(np.pad(ndimage.gaussian_filter(out.astype(np.float32), 0.7), 1), 0.5,
                                spacing=(1.0, 2 * STEP, 2 * STEP))
    skin = axes(v - [1.0, 2 * STEP, 2 * STEP]); reach = head[:, 1].max() - head[:, 1].min()
    skin = skin[skin[:, 1] > skin[:, 1].max() - reach]
    a, b = g.sample(skin, 8000, 0), g.sample(head, 8000, 1); best = None
    for yaw in (-8, 0, 8):
        for pitch in (-8, 0, 8):
            R0 = g._axis_angle(np.array([0, 1.0, 0]), np.radians(yaw)) @ g._axis_angle(np.array([1.0, 0, 0]), np.radians(pitch))
            fit = g.icp(a, b, 1.0, R0, b.mean(0) - R0 @ a.mean(0), True, rounds=60)
            if best is None or fit[1] < best[1]:
                best = fit
    (s, R, t), e = best
    log(f"  the CT's skin on the body's head: scale {s:.4f}, mean gap {e * 1000:.1f} mm")
    return s, R, t


def by_bone(v, model, start, g):
    """The similarity laying the CT's bone on the model's skull, closest
    points both ways (what lies within reach of it), from the skin's fit."""
    A = axes(v); s, R, t = start
    dst = np.vstack([g.surface_points(p, f, 0.0015) for p, f in model.values()]); dsub = g.sample(dst, 30000, 1)
    tree = cKDTree(dst)
    for reach in (0.015, 0.010, 0.006, 0.004):
        a = g.sample(A[tree.query(A @ (s * R).T + t)[0] < reach], 30000, 0)
        (s, R, t), e = g.icp(a, dsub[cKDTree(a @ (s * R).T + t).query(dsub)[0] < reach], s, R, t, True, rounds=25)
    turn = np.degrees(np.arccos(np.clip((np.trace(R @ start[1].T) - 1) / 2, -1, 1)))
    log(f"  the CT's bone on the model's skull: scale {s:.4f}, {turn:.1f} degrees from the skin's fit, mean gap {e * 1000:.2f} mm")
    return s, R, t


# MARK: the field

def model_solid(model, shape, placed, g):
    """The model's bones as a solid on the grid."""
    out = np.zeros(shape, bool)
    for p, f in model.values():
        idx = np.round(g.surface_points(to_grid(p, *placed), f, 0.3) / SP).astype(int)
        idx = idx[((idx >= 0) & (idx < shape)).all(1)]
        if not len(idx):
            continue
        one = np.zeros(shape, bool); one[tuple(idx.T)] = True
        lo, hi = np.maximum(idx.min(0) - 3, 0), np.minimum(idx.max(0) + 4, shape)
        sub = one[lo[0]:hi[0], lo[1]:hi[1], lo[2]:hi[2]]
        out[lo[0]:hi[0], lo[1]:hi[1], lo[2]:hi[2]] |= ndimage.binary_fill_holes(
            ndimage.binary_closing(ndimage.binary_dilation(sub), iterations=1))
    return out


def thickness(bone):
    """How thick the bone is at each voxel (mm): twice its deepest point within 1 mm (its medial axis)."""
    din = ndimage.distance_transform_edt(bone, sampling=SP).astype(np.float32)
    return 2 * ndimage.maximum_filter(din, footprint=_ball(1.0, SP))


def _spread(C, D, n, sigma):
    """A smooth move from the moves D at the points C (each standing for n
    points): their Gaussian-weighted average, fading to nothing where none
    lies near."""
    tree = cKDTree(C); floor = float(np.mean(n))
    def move(x):
        out = np.empty_like(x)
        for a in range(0, len(x), 20000):
            d, k = tree.query(x[a:a + 20000], k=min(96, len(C)), distance_upper_bound=3 * sigma)
            ok = np.isfinite(d); k = np.where(ok, k, 0)
            w = np.where(ok, n[k] * np.exp(-0.5 * (np.where(ok, d, 0) / sigma) ** 2), 0)
            out[a:a + 20000] = x[a:a + 20000] + np.einsum("ij,ijk->ik", w, D[k]) / (w.sum(1) + floor)[:, None]
        return out
    return move


def _kabsch(A, B):
    ca, cb = A.mean(0), B.mean(0); U, _, Vt = np.linalg.svd((A - ca).T @ (B - cb))
    R = Vt.T @ np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))]) @ U.T
    return R, cb - R @ ca


def fit_jaw(model, ct, g, name="Mandible"):
    """The mandible, the one bone of the skull that moves, fitted to the
    CT's bone on its own: a rigid move found by closest points (each of the
    model's surface points and its nearest CT point, kept where the model's
    point nearest that CT point lies back within 2 mm), the reach narrowing
    from 10 to 3 mm. ct: points (m) on the CT's bone surface."""
    v, f = np.asarray(model[name][0], float), np.asarray(model[name][1])
    P = g.sample(g.surface_points(v, f, 0.0015), 6000, 0); lo, hi = P.min(0) - 0.015, P.max(0) + 0.015
    Q = g.sample(ct[((ct > lo) & (ct < hi)).all(1)], 80000, 1); tree = cKDTree(Q); R, t = np.eye(3), np.zeros(3)
    for reach in (0.010, 0.007, 0.005, 0.003):
        for _ in range(12):
            X = P @ R.T + t; d, j = tree.query(X); back = X[cKDTree(X).query(Q[j])[1]]
            ok = (d < reach) & (np.linalg.norm(back - X, axis=1) < 0.002)
            R, t = _kabsch(P[ok], Q[j[ok]])
    c = P.mean(0); X = P @ R.T + t
    log(f"  the model's mandible fitted to the CT's jaw: turned {np.degrees(np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1))):.1f} degrees, "
        f"moved {np.linalg.norm(c @ R.T + t - c) * 1000:.1f} mm; its surface to the CT's bone {np.median(tree.query(P)[0]) * 1000:.1f} mm, "
        f"then {np.median(tree.query(X)[0]) * 1000:.1f} (medians)")
    return dict(model, **{name: (v @ R.T + t, model[name][1])})


def bend(model, ct, g, reaches=(0.010, 0.006, 0.004, 0.0025), sigma=0.006):
    """The model bent onto the CT's thick bone, so that where it stands in
    for thin bone it meets the CT's without a step. Where a point of the
    model's surface and a point of the CT's thick bone match (the CT's point
    nearest the model's within reach, and the model's surface nearest that
    CT point back within 1.5 mm of where it started), the model is moved by
    the difference; those moves, averaged per 3 mm cell, are spread by a
    Gaussian-weighted average (sigma 6 mm) that fades to nothing away from
    them, so the thin plates the CT does not show ride with the thick bone
    around them. Four rounds, the reach narrowing. ct: points (m) on the
    CT's surface where its bone is 2 mm thick or more."""
    P = np.vstack([g.sample(g.surface_points(np.asarray(v, float), np.asarray(f), 0.0015), 4000, k)
                   for k, (v, f) in enumerate(model.values())])
    tree = cKDTree(ct); move = None; before = np.median(tree.query(P)[0])
    for reach in reaches:
        X = move(P) if move else P; d1, j = tree.query(X); back = X[cKDTree(X).query(ct[j])[1]]
        ok = (d1 < reach) & (np.linalg.norm(back - X, axis=1) < 0.0015)
        src, disp = P[ok], (ct[j] - P)[ok]   # each the whole move from the model's own surface
        _, inv = np.unique(np.floor(src / 0.003).astype(int), axis=0, return_inverse=True); inv = inv.reshape(-1)
        n = np.bincount(inv).astype(float)
        C = np.stack([np.bincount(inv, src[:, k]) for k in range(3)], 1) / n[:, None]
        D = np.stack([np.bincount(inv, disp[:, k]) for k in range(3)], 1) / n[:, None]
        move = _spread(C, D, n, sigma)
    X = move(P); shift = np.linalg.norm(X - P, axis=1)
    log(f"  the model bent onto the CT's thick bone: moved {np.median(shift) * 1000:.1f} mm (90th {np.percentile(shift, 90) * 1000:.1f}); "
        f"its surface to the CT's thick bone {before * 1000:.1f} mm, then {np.median(tree.query(X)[0]) * 1000:.1f} (medians)")
    return {nm: (move(np.asarray(v, float)), f) for nm, (v, f) in model.items()}


def model_points(model, placed, step=0.6):
    """Points (the grid's mm) spread over the model's surface, about step mm
    apart, with their triangles' normals."""
    P, N = [], []
    rng = np.random.default_rng(0)
    for v, f in model.values():
        q = to_grid(np.asarray(v, float), *placed); f = np.asarray(f); a, b, c = q[f[:, 0]], q[f[:, 1]], q[f[:, 2]]
        n = np.cross(b - a, c - a); area = np.linalg.norm(n, axis=1) / 2; n = n / np.maximum(2 * area[:, None], 1e-12)
        k = rng.choice(len(f), size=int(area.sum() / step ** 2) + 1, p=area / area.sum())
        u, w = rng.random(len(k)), rng.random(len(k)); flip = u + w > 1; u[flip], w[flip] = 1 - u[flip], 1 - w[flip]
        P.append(a[k] + u[:, None] * (b[k] - a[k]) + w[:, None] * (c[k] - a[k])); N.append(n[k])
    return np.vstack(P), np.vstack(N)


def _within(solid, mm):
    """The voxels within mm of the solid."""
    idx = np.argwhere(solid)
    if not len(idx):
        return np.zeros_like(solid)
    pad = np.ceil(mm / SP).astype(int) + 1
    lo, hi = np.maximum(idx.min(0) - pad, 0), np.minimum(idx.max(0) + pad + 1, solid.shape)
    box = tuple(slice(a, b) for a, b in zip(lo, hi)); out = np.zeros_like(solid)
    out[box] = ndimage.distance_transform_edt(~solid[box], sampling=SP) <= mm
    return out


def face_zone(model, shape, placed, g):
    """Where the model's face stands in whole: within FACE_AROUND mm of its
    facial bones and over FACE_CLEAR mm from its others."""
    face = model_solid({k: v for k, v in model.items() if k in FACE}, shape, placed, g)
    rest = model_solid({k: v for k, v in model.items() if k not in FACE}, shape, placed, g)
    return _within(face, FACE_AROUND) & ~_within(rest, FACE_CLEAR)


def blend(sm, body, bone, nih, thick, P, N, zone, teeth, reach=REACH):
    """Step 4: the field, the CT's bone where it covers the model's surface
    (P, N: points on it and their normals) or is thick (but not by the
    teeth, teeth: the organ set's on the grid, whose sockets' thin walls
    the CT's own teeth would make count as thick), the model's where round it the CT's
    bone is thin and lace or missing, and the model's whole in the face's
    zone."""
    kept = bone & ~zone
    far = kept & (thick < THICK) & ~ndimage.binary_dilation(nih, structure=_ball(reach + 1.0, SP)); kept &= ~far
    dist, ind = ndimage.distance_transform_edt(~bone, sampling=SP, return_indices=True)
    solid = (thick[ind[0], ind[1], ind[2]] >= THICK) & (dist <= COVER); del dist, ind
    solid &= ~_within(teeth, COVER)
    grow = ndimage.binary_dilation(kept | ((sm > ISO - 50) & body), structure=_ball(0.5, SP))
    covered = np.zeros(len(P), bool)
    for k in np.linspace(-COVER, COVER, int(2 * COVER / 0.5) + 1):
        idx = np.round((P + k * N) / SP).astype(int); ok = ((idx >= 0) & (idx < np.array(bone.shape))).all(1)
        covered[ok] |= grow[tuple(idx[ok].T)]
    del grow
    idx = np.round(P / SP).astype(int); ok = ((idx >= 0) & (idx < np.array(bone.shape))).all(1); idx = idx[ok]
    T = np.zeros(bone.shape, np.float32); C = np.zeros(bone.shape, np.float32)
    np.add.at(T, tuple(idx.T), 1.0); np.add.at(C, tuple(idx.T), covered[ok].astype(np.float32))
    T = ndimage.gaussian_filter(T, sigma=2.0 / SP); C = ndimage.gaussian_filter(C, sigma=2.0 / SP)
    ratio = np.where(T > 1e-3, C / np.maximum(T, 1e-3), 1.0); del C
    stand = ndimage.binary_dilation(nih, structure=_ball(reach, SP)) & ~solid & (T > 1e-3) & (ratio < KEEP); del T, ratio, solid
    ct = ct_field(sm, body, kept)
    mf = (ISO + 1000 * (ndimage.gaussian_filter(nih.astype(np.float32), sigma=0.5 / SP) - 0.5)).astype(np.float32)
    w = ndimage.gaussian_filter(stand.astype(np.float32), sigma=1.0 / SP)
    wz = ndimage.gaussian_filter(zone.astype(np.float32), sigma=1.0 / SP)
    log(f"  the model's surface: {np.mean(~covered):.1%} not covered by the CT's bone within {COVER:.0f} mm; its bone stands in over "
        f"{np.mean(w > 0.5) * 100:.2f}% of the grid, and over {np.mean(wz > 0.5) * 100:.2f}% in the face; "
        f"{int(far.sum())} voxels of thin CT bone far from it left out")
    field = ndimage.gaussian_filter((1 - w) * ct + w * mf, sigma=0.25 / SP); del ct, w
    return (1 - wz) * field + wz * ndimage.gaussian_filter(mf, sigma=0.25 / SP)


def smooth(v, f, rounds=10, lam=0.5, mu=-0.53):
    """Step 5: Taubin smoothing, each step toward the neighbours' mean and
    then back a little, so the surface loses the grid's steps, not size."""
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    A = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr()
    A = ((A + A.T) > 0).astype(np.float64); deg = np.asarray(A.sum(1)).ravel()
    W = sparse.diags(1 / np.maximum(deg, 1)) @ A
    for _ in range(rounds):
        v = v + lam * (W @ v - v); v = v + mu * (W @ v - v)
    return v


# MARK: naming

def _smooth_vertices(lab, f, n, k, rounds=3):
    """A mode filter over the mesh's edges: each vertex takes the name most of it and its neighbours have."""
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    A = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr(); A = ((A + A.T) > 0).astype(np.float32)
    for _ in range(rounds):
        votes = np.zeros((n, k), np.float32)
        for j in range(k):
            x = (lab == j).astype(np.float32); votes[:, j] = A @ x + 1.5 * x
        lab = np.where(lab >= 0, votes.argmax(1), lab)
    return lab


def named(p, f, model, teeth, simplify, g, budget=BUDGET):
    """Step 6: {the model's bone name: (vertices, triangles)}, from the CT's
    surface p, f (the atlas's frame)."""
    names = list(model) + ["teeth"] * len(teeth)
    P, L = [], []
    for k, (q, h) in enumerate(list(model.values()) + teeth):
        pts = g.surface_points(np.asarray(q, float), np.asarray(h), 0.0012); P.append(pts); L.append(np.full(len(pts), k))
    tree, L = cKDTree(np.vstack(P)), np.concatenate(L)
    d, i = tree.query(p, workers=-1); name = np.where(d < 0.010, L[i], -1)
    name = _smooth_vertices(name, f, len(p), len(names))
    cut = (name < 0) | (name >= len(model))
    keep = ~cut[f].any(1); g0 = f[keep]; used = np.unique(g0); rm = np.full(len(p), -1); rm[used] = np.arange(len(used))
    p1, f1 = simplify(p[used], rm[g0], budget)
    log(f"  {keep.sum()} of {len(f)} triangles named (the teeth and what lies away from the skull left out), simplified to {len(f1)}")
    nb = len(model); _, j = cKDTree(np.vstack(P[:nb])).query(p1[f1].mean(1), workers=-1); fl = L[:sum(len(x) for x in P[:nb])][j]
    # each triangle's name smoothed over the triangles it shares an edge with
    E = np.sort(np.vstack([f1[:, [0, 1]], f1[:, [1, 2]], f1[:, [2, 0]]]), 1); T = np.tile(np.arange(len(f1)), 3)
    key = E[:, 0] * len(p1) + E[:, 1]; o = np.argsort(key, kind="stable"); ks, ts, es = key[o], T[o], E[o]
    pair = np.flatnonzero(ks[1:] == ks[:-1]); ta, tb = ts[pair], ts[pair + 1]
    A = sparse.coo_matrix((np.ones(2 * len(ta)), (np.r_[ta, tb], np.r_[tb, ta])), shape=(len(f1), len(f1))).tocsr()
    for _ in range(3):
        votes = np.zeros((len(f1), nb), np.float32)
        for k in np.unique(fl):
            x = (fl == k).astype(np.float32); votes[:, k] = A @ x + 1.1 * x
        fl = votes.argmax(1)
    # the borders between two bones straightened: each vertex on one (not where three meet) moved toward
    # the middle of its two neighbours along it, four times
    border = es[pair][fl[ta] != fl[tb]]; nbrs = {}
    for a, b in border:
        nbrs.setdefault(a, set()).add(b); nbrs.setdefault(b, set()).add(a)
    count = np.zeros(len(p1), int)
    for k in np.unique(fl):
        has = np.zeros(len(p1), bool); has[np.unique(f1[fl == k])] = True; count += has
    movable = sorted(v for v, s in nbrs.items() if len(s) == 2 and count[v] == 2)
    if movable:
        idx = np.array(movable); two = np.array([sorted(nbrs[v]) for v in movable])
        for _ in range(4):
            p1[idx] = 0.5 * p1[idx] + 0.25 * (p1[two[:, 0]] + p1[two[:, 1]])
    out = {}
    for k, nm in enumerate(names[:nb]):
        g_ = f1[fl == k]
        if len(g_):
            used = np.unique(g_); rm = np.full(len(p1), -1); rm[used] = np.arange(len(used)); out[nm] = (p1[used], rm[g_])
        else:   # a bone the CT's surface never came nearest to keeps the model's
            out[nm] = model[nm]; log(f"  {nm}: none of the CT's surface, the model's kept")
    log("  bones: " + ", ".join(f"{nm} {len(h)}" for nm, (q, h) in out.items()))
    return out


# MARK: the whole

def ct_skull(sex, folder, model, body, simplify, g):
    """The body's skull from its own CT: {the model's bone name: (vertices,
    triangles)} in the body's frame. model: the model's skull fitted to this
    body, by those names; body: anatomy_gaps.Body (its head skin and teeth);
    simplify: anatomy_atlas.simplify; g: anatomy_gaps."""
    hu = clean(head_grid(sex, folder))
    sm, inside, bone = bone_of(hu)
    skin = g.head_skin(body); head = skin[0][np.unique(skin[1])]
    start = by_skin(hu, head, g); del hu
    v, f, _ = _mesh(ndimage.gaussian_filter(ct_field(sm, inside, bone), sigma=0.25 / SP), ISO)
    placed = by_bone(v, model, start, g); s, R, t = placed
    thick = thickness(bone)
    at = ndimage.map_coordinates(ndimage.maximum_filter(thick, size=3), (v / SP).T, order=0)
    model = fit_jaw(model, axes(v) @ (s * R).T + t, g)
    model = bend(model, g.sample(axes(v[at >= THICK]) @ (s * R).T + t, 60000, 0), g); del v, f, at
    nih = model_solid(model, bone.shape, placed, g)
    zone = face_zone(model, bone.shape, placed, g)
    teeth = [body.mesh("set_of_upper_jaw_teeth"), body.mesh("set_of_lower_jaw_teeth")]
    crowns = model_solid(dict(enumerate(teeth)), bone.shape, placed, g)
    P, N = model_points(model, placed)
    field = blend(sm, inside, bone, nih, thick, P, N, zone, crowns); del sm, inside, bone, nih, thick, zone, crowns
    v, f, _ = _mesh(field, ISO); del field
    v = smooth(v, f)
    p = axes(v) @ (s * R).T + t
    return named(p, f[:, ::-1] if g.signed_volume(p, f) < 0 else f, model, teeth, simplify, g)
