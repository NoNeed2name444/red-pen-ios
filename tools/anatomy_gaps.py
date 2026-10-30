"""The parts the organ sets lack, made for both bodies of the 3D anatomy atlas,
and the repairs that letting them in needs. Called by tools/anatomy_atlas.py
(its --skull and --ct inputs); not run on its own.

What it adds, to each body:

    skull          the cranial and facial bones, paired ones split at the
                   midline (the teeth are the mouth's)
    sternum        the male body's (the female organ set has its own)
    ribs           24 ribs and the costal cartilages
    shoulders      clavicles and scapulae
    arms           the humeri, and the radius, ulna, carpus, metacarpals
                   and phalanges of each forearm and hand
                   (tools/anatomy_limbs.py)
    legs           (the organ sets' part, which ends at the ankle) the
                   tarsals, metatarsals, phalanges and the great toe's
                   sesamoids of each foot (tools/anatomy_feet.py)
    pelvis         (the female organ set's, whose hip bones are its ilia
                   alone) the whole hip bones, in place of the ilia
    hip-muscles    gluteus maximus, medius and minimus, iliopsoas
    back-muscles   the deep back muscles (erector spinae with the
                   transversospinal group)
    thyroid, adrenals      in a new system, endocrine
    oesophagus, stomach

Sources, both CC BY 4.0, pinned below and credited in Resources/Anatomy/
SOURCES.md:

- The skull: NIH 3D 3DPX-020591, "Skull and Eyes - Visible Human Male"
  (kbrowne, NLM 3D: Anatomy), segmented from the Visible Human Male's CT:
  the same man as the male body. It is placed on that body by a similarity
  fit of its eyes and upper teeth to the body's own.
- The rest: CT scans of the TotalSegmentator dataset, v3 (Wasserthal et
  al. 2023; Zenodo, doi 10.5281/zenodo.22688904): s1803, a man of 40, for the
  male body and s1764, a woman of 32, for the female, the pair whose
  skeletons matched the bodies best among those judged; for the man's
  forearms and hands s1880, a man of 37, as s1803's hands lie outside its
  field of view; and for the man's feet s1767, a man of 56, as neither of
  those reaches the toes. The forearm, hand and foot bones are found in the
  CT itself (the dataset segments none below the humerus or the femur): see
  tools/anatomy_limbs.py and tools/anatomy_feet.py. Each mask is meshed
  and carried into its body by a smooth warp fitted on what the scan and the
  body both have (vertebrae, sacrum, hip bones, the femurs' tops and the
  centres of their heads, kidneys, liver, spleen, lungs, trachea, heart,
  brain, aorta, pancreas), then, for the hip muscles, by a closer warp of
  the pelvis.

Repairs, each checked by rendering the bodies:

- The skull is kept under the skin: where it would come within 2.5 mm of
  it, seen from the brain, it is moved in, smoothly, by at most 5 mm.
- The female skull is the male's, carried onto her head by a warp fitted on
  the head's skin, the upper three neck vertebrae, the eyes and the teeth,
  then kept under her skin the same way.
- The brain both organ sets use (the Allen atlas's) is larger than either
  skull holds; it is scaled down about a point midway between the foot of
  the medulla and the optic chiasm, so the brainstem and the optic nerves
  stay where they meet it, by the least that puts it inside the skull's
  inner table nearly everywhere over the vault; the vault is then eased out
  where it still touches.
- Each humerus is placed along the skin's arm, its head in the shoulder, and
  turned so its epicondyles lie across the arm, medial toward the body: the
  scans' arms lie otherwise.
- The rib cage is widened, smoothly around the chest's axis, until the
  lungs, heart, liver, spleen, kidneys and colon sit inside it, but never
  past the skin; the shoulder girdle rides with it. Each shoulder is then
  turned down about the sternoclavicular joint until the clavicle and
  scapula lie under the skin, the humerus following.
- Each forearm and hand is set on its humerus at the elbow (the scan's own
  humerus fitted to the body's carries it there), straightened toward the
  skin's wrist, turned so the knuckles lie across as the skin's do, and
  each finger laid along the skin's, joint by joint; forearm, hand and
  fingers are sized to the skin within 15% (fingers 10%). One side is the
  scanned one, the other its mirror image.
- The female organ set's hip bone is the ilium alone, stopping above the
  hip joint. Her scan's whole hip bones take its place: each fitted to her
  ilium (the scan's cut at the same height above its femoral head) and to
  the centre of her femoral head by a similarity, which keeps the scan's
  pelvis whole where a warp fitted on the ilium alone tips the pubis back;
  then the two pubic bodies are brought together at the midline, the rami
  eased smoothly, nothing 7 cm away moving.
- Whatever else came from a scan is pushed out of the organs and bones it
  cuts into (the stomach out of the colon, muscles off the bone), smoothly
  and a few millimetres at a time.

Needs numpy, scipy (BSD), scikit-image (BSD), nibabel (MIT) and pyamg (MIT). The inputs
are downloaded files: anatomy_atlas.py is run with python3 -I from outside
their folders.
"""
import hashlib
import json
import os
import re

import numpy as np
from scipy import ndimage
from scipy.interpolate import RBFInterpolator
from scipy.spatial import cKDTree

SKULL_SOURCE = {
    "id": "nih3d-3dpx-020591",
    "title": "Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591)",
    "creators": "kbrowne (NLM 3D: Anatomy)",
    "doi": None,
    "url": "https://3d.nih.gov/entries/3DPX-020591",
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
    "basis": "The Visible Human Male, U.S. National Library of Medicine",
    "sha256": "031179f6942df5ca89e675e6eb75859a2e9751c6046bcadde083708974345a43",
}
CT_SOURCE = {
    "id": "totalsegmentator-v3",
    "title": "Dataset with segmentations of 117 important anatomical structures in 1939 CT images, v3.0.0 "
             "(TotalSegmentator; scans s1803, s1764, s1880 and s1767)",
    "creators": "Jakob Wasserthal et al. (Wasserthal et al., Radiology: Artificial Intelligence 2023, "
                "https://doi.org/10.1148/ryai.230024)",
    "doi": "https://doi.org/10.5281/zenodo.22688904",
    "url": "https://zenodo.org/records/22688904",
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
}
SUBJECT = {"male": "s1803", "female": "s1764"}
# SHA-256 of the lines "<file> <its SHA-256>\n" for the masks used, in name order, per scan.
CT_SHA256 = {"s1803": "a80b8b04288fbbf036d9097c0bd4f5af7824cbd184342d5897e02bda9b5a4337",
             "s1764": "783bff12299de037206dfb432144580dadc485d2645b34137c9716f5a773a98d",
             "s1880": "718e1a59035e1dabfca91f01874c33d023e559cdea4e9676a20a8c26c8e55f3c",
             "s1767": "62fa7c94217e7d4cd33905e6914e872141b06bf7a5a6f52fa35e6ff3294fc35f"}
# What the run found, for the manifest's account of its changes.
RESULTS = {}

# NIfTI world (RAS+, millimetres) to the atlas frame (x to the body's left, y up, z forward, metres).
TO_ATLAS = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float) / 1000

SIDES = (("left", "L"), ("right", "R"))
ORDINAL = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
           "eleventh", "twelfth"]
RIB_UBERON = ["0004601", "0004602", "0004603", "0004604", "0004605", "0004606", "0004607", "0010757",
              "0004608", "0004609", "0004610", "0004611"]


def u(n):
    return "UBERON:" + n


# The parts made from the scans: (id, name, system, the parts it goes before
# (the first one the body has), the warp, its structures as (mask, node,
# label, tissue, triangle budget, UBERON id)). A male-only row is marked.
def _ct_parts():
    ribs = []
    for i in range(1, 13):
        for side, s in SIDES:
            ribs.append((f"rib_{side}_{i}", f"TS_rib_{i}_{s}", f"{side} {ORDINAL[i - 1]} rib", "bone", 500,
                         u(RIB_UBERON[i - 1])))
    ribs.append(("costal_cartilages", "TS_costal_cartilages", "costal cartilages", "cartilage", 4000, u("0002236")))
    pair = lambda mask, node, label, tissue, budget, uberon: [
        (f"{mask}_{side}", f"TS_{node}_{s}", f"{side} {label}", tissue, budget, uberon) for side, s in SIDES]
    return [
        ("oesophagus", "Oesophagus", "digestive", ["liver"], "global",
         [("esophagus", "TS_oesophagus", "oesophagus", "gut", 2000, u("0001043"))]),
        ("stomach", "Stomach", "digestive", ["liver"], "global",
         [("stomach", "TS_stomach", "stomach", "gut", 4000, u("0000945"))]),
        ("thyroid", "Thyroid gland", "endocrine", ["kidneys"], "global",
         [("thyroid_gland", "TS_thyroid_gland", "thyroid gland", "gland", 1500, u("0002046"))]),
        ("adrenals", "Adrenal glands", "endocrine", ["kidneys"], "global",
         pair("adrenal_gland", "adrenal_gland", "adrenal gland", "gland", 800, u("0002369"))),
        ("sternum", "Sternum", "skeletal", ["vertebral-column"], "global",
         [("sternum", "TS_sternum", "sternum", "bone", 1500, u("0000975"))]),
        ("ribs", "Ribs and costal cartilages", "skeletal", ["vertebral-column"], "global", ribs),
        ("shoulders", "Shoulder girdle", "skeletal", ["vertebral-column"], "global",
         pair("clavicula", "clavicle", "clavicle", "bone", 700, u("0001105"))
         + pair("scapula", "scapula", "scapula", "bone", 1800, u("0006849"))),
        ("arms", "Arm bones", "skeletal", ["vertebral-column"], "arm",
         pair("humerus", "humerus", "humerus", "bone", 1600, u("0000976"))),
        ("hip-muscles", "Hip muscles", "muscular", [], "pelvis",
         pair("gluteus_maximus", "gluteus_maximus", "gluteus maximus", "muscle", 2500, u("0001370"))
         + pair("gluteus_medius", "gluteus_medius", "gluteus medius", "muscle", 1800, u("0001371"))
         + pair("gluteus_minimus", "gluteus_minimus", "gluteus minimus", "muscle", 1200, u("0008521"))
         + pair("iliopsoas", "iliopsoas", "iliopsoas", "muscle", 2000, u("0001999"))),
        ("back-muscles", "Deep back muscles", "muscular", [], "global",
         pair("autochthon", "deep_back_muscles", "deep back muscles (erector spinae and transversospinales)",
              "muscle", 3500, u("0002462"))),
    ]


CT_PARTS = _ct_parts()

# The skull's bones in the NIH 3D file: (its name there, node, label, paired, UBERON id).
SKULL_BONES = [
    ("Frontal bone", "frontal_bone", "frontal bone", False, "0000209"),
    ("Pareital bone", "parietal_bone", "parietal bone", True, "0000210"),
    ("Occipital bone", "occipital_bone", "occipital bone", False, "0001676"),
    ("Temporal bone", "temporal_bone", "temporal bone", True, "0001678"),
    ("Sphenoid bone", "sphenoid_bone", "sphenoid bone", False, "0001677"),
    ("Ethmoid bone", "ethmoid_bone", "ethmoid bone", False, "0001679"),
    ("Nasal bone", "nasal_bone", "nasal bone", True, "0001681"),
    ("Lacrimal bone", "lacrimal_bone", "lacrimal bone", True, "0001680"),
    ("Zygomatic bone", "zygomatic_bone", "zygomatic bone", True, "0001683"),
    ("Maxilla", "maxilla", "maxilla", True, "0002397"),
    ("Palatine bone", "palatine_bone", "palatine bone", True, "0001682"),
    ("Vomer", "vomer", "vomer", False, "0002396"),
    ("Mandible", "mandible", "mandible", False, "0001684"),
]

# The scan's masks the warp is fitted on, and the body's structures they meet:
# (name, masks, the body's structures (a pattern on the node without its
# body's prefix, or a part id), weight, kind).
LEVELS = [("C", "cervical", 7), ("T", "thoracic", 12)]


def log(*a):
    print(*a, flush=True)


# MARK: inputs

def digest(folder, names):
    lines = "".join(f"{n} {_sha(os.path.join(folder, n))}\n" for n in sorted(names))
    return hashlib.sha256(lines.encode()).hexdigest()


def _sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def masks_used(sex):
    names = {f"vertebrae_{l}{i}" for l, _, n in LEVELS for i in range(1, n + 1)} | {f"vertebrae_L{i}" for i in range(1, 6)}
    names |= {"sacrum", "hip_left", "hip_right", "femur_left", "femur_right", "kidney_left", "kidney_right", "liver",
              "spleen", "trachea", "heart", "brain", "aorta", "pancreas", "lung_upper_lobe_left", "lung_lower_lobe_left",
              "lung_upper_lobe_right", "lung_middle_lobe_right", "lung_lower_lobe_right"}
    names |= {"skull"} if sex == "male" else set()
    for pid, *_, rows in CT_PARTS:
        if pid == "sternum" and sex == "female":
            continue
        names |= {r[0] for r in rows}
    names |= {"sternum"} if sex == "female" else set()  # her sternum pairs with the organ set's
    return sorted(n + ".nii.gz" for n in names)


# MARK: meshes from the scans

def load_mask(path):
    import nibabel
    im = nibabel.load(path)
    return np.asarray(im.dataobj) > 0, im.affine


def keep_pieces(a, share):
    lab, k = ndimage.label(a)
    if k <= 1:
        return a
    size = np.bincount(lab.ravel()); size[0] = 0
    return np.isin(lab, np.flatnonzero(size >= share * size.max()))


def ct_mesh(a, affine, sigma=0.8, share=0.05):
    """A mask's surface in the atlas frame, counter-clockwise seen from
    outside: the pieces worth keeping, smoothed, cut at half."""
    from skimage.measure import marching_cubes
    if not a.any():
        return None
    a = keep_pieces(a, share)
    idx = np.argwhere(a); lo = np.maximum(idx.min(0) - 3, 0); hi = idx.max(0) + 4
    sub = np.pad(a[lo[0]:hi[0], lo[1]:hi[1], lo[2]:hi[2]].astype(np.float32), 2)
    v, f, _, _ = marching_cubes(ndimage.gaussian_filter(sub, sigma), 0.5)
    w = (v - 2 + lo) @ affine[:3, :3].T + affine[:3, 3]
    p = w @ TO_ATLAS.T
    f = f.astype(np.int64)
    if signed_volume(p, f) < 0:
        f = f[:, [0, 2, 1]]
    return p, f


def signed_volume(p, f):
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    return np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6


def sample(p, n, seed=0):
    if len(p) <= n:
        return p
    return p[np.random.default_rng(seed).choice(len(p), n, replace=False)]


def centroid(p, f):
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    w = np.linalg.norm(np.cross(b - a, c - a), axis=1)
    return ((a + b + c) / 3 * w[:, None]).sum(0) / w.sum()


def shell(points, h=0.003):
    """The outside of an organ drawn as many parts: voxels, closed, filled, their boundary."""
    lo = points.min(0) - 3 * h; ijk = np.floor((points - lo) / h).astype(int)
    occ = np.zeros(ijk.max(0) + 4, bool); occ[tuple(ijk.T)] = True
    occ = ndimage.binary_fill_holes(ndimage.binary_closing(occ, iterations=2))
    return (np.argwhere(occ & ~ndimage.binary_erosion(occ)) + 0.5) * h + lo


# MARK: warps

class Warp:
    """A thin-plate spline (or, before one is fitted, an affine map) from the scan to the body."""
    def __init__(self, affine=None, rbf=None):
        self.affine, self.rbf = affine, rbf

    def __call__(self, x):
        if self.rbf is not None:
            return np.concatenate([self.rbf(x[i:i + 20000]) for i in range(0, len(x), 20000)]) if len(x) else x
        return x @ self.affine[:3] + self.affine[3]


class Then:
    def __init__(self, a, b):
        self.a, self.b = a, b

    def __call__(self, x):
        return self.b(self.a(x))


def register(pairs, rounds=(3e-2, 1e-2, 3e-3, 1e-3, 3e-4, 1e-4), control=2500, quiet=False):
    """A smooth warp taking each pair's scan points onto its body points.
    pairs: (name, scan points, body points, weight, kind); kind 'centre'
    pairs one point with one point, any other the closest points both ways.
    Each round fits a thin-plate spline, less smoothed than the last."""
    cs = np.array([c.mean(0) for _, c, v, w, k in pairs]); vs = np.array([v.mean(0) for _, c, v, w, k in pairs])
    A, *_ = np.linalg.lstsq(np.hstack([cs, np.ones((len(cs), 1))]), vs, rcond=None)
    warp = Warp(affine=A)
    trees = [cKDTree(v) for _, c, v, w, k in pairs]
    for lam in rounds:
        S, T, W = [], [], []
        for (name, c, v, wt, kind), tree in zip(pairs, trees):
            if kind == "centre":
                S.append(c); T.append(v); W.append(np.full(len(c), wt)); continue
            x = warp(c)
            _, j = tree.query(x); S.append(c); T.append(v[j]); W.append(np.full(len(c), wt / len(c) * 400))
            _, i = cKDTree(x).query(v); keep = sample(np.arange(len(v)), len(c), 2)
            S.append(c[i[keep]]); T.append(v[keep]); W.append(np.full(len(keep), wt / len(c) * 400))
        S, T, W = np.concatenate(S), np.concatenate(T), np.concatenate(W)
        # one control point per 8 mm cell, so near duplicates do not fight
        _, first = np.unique(np.floor(S / 0.008).astype(int), axis=0, return_index=True)
        if len(first) > control:
            first = sample(first, control, 3)
        warp = Warp(rbf=RBFInterpolator(S[first], T[first], kernel="thin_plate_spline",
                                        smoothing=lam / W[first], degree=1))
        if not quiet:
            gaps = {n: np.mean(t.query(warp(c))[0]) * 1000 for (n, c, v, w, k), t in zip(pairs, trees) if k != "centre"}
            log(f"    smoothing {lam:g}: mean gap {np.mean(list(gaps.values())):.1f} mm, worst "
                + ", ".join(f"{n} {g:.1f}" for n, g in sorted(gaps.items(), key=lambda x: -x[1])[:3]))
    return warp


# MARK: rays

def fib(n):
    """n directions spread evenly over the sphere."""
    i = np.arange(n) + 0.5; phi = np.arccos(1 - 2 * i / n); th = np.pi * (1 + 5 ** 0.5) * i
    return np.stack([np.cos(th) * np.sin(phi), np.cos(phi), np.sin(th) * np.sin(phi)], 1)


def _ray_t(origin, dirs, v, f, chunk=64):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    e1, e2 = b - a, c - a; T = origin - a; q = np.cross(T, e1)
    for i in range(0, len(dirs), chunk):
        d = dirs[i:i + chunk][:, None, :]
        p = np.cross(d, e2[None]); det = (p * e1[None]).sum(-1)
        ok = np.abs(det) > 1e-12; inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        uu = (T[None] * p).sum(-1) * inv; w = (d * q[None]).sum(-1) * inv; t = (e2[None] * q[None]).sum(-1) * inv
        yield ok & (uu >= 0) & (w >= 0) & (uu + w <= 1) & (t > 0), t


def first_hits(origin, dirs, v, f):
    """How far along each ray from origin it first meets the mesh, inf if never (Moller-Trumbore)."""
    return np.concatenate([np.where(hit, t, np.inf).min(1) for hit, t in _ray_t(origin, dirs, v, f)])


def last_hits(origin, dirs, v, f):
    """How far along each ray from origin it last meets the mesh, inf if never."""
    out = [np.where(hit.any(1), np.where(hit, t, -np.inf).max(1), np.inf) for hit, t in _ray_t(origin, dirs, v, f)]
    return np.concatenate(out)


# MARK: the bodies, as anatomy_atlas.py collected them

class Body:
    """One body's structures by node: (part id, mesh positions, triangles)."""
    def __init__(self, sex, parts):
        self.sex, self.parts = sex, parts
        self.prefix = "VH_M_" if sex == "male" else "VH_F_"
        self.nodes = {}
        for part in parts:
            for s, (p, f) in zip(part["structures"], part["meshes"]):
                self.nodes[s["node"]] = (part["id"], p, f)

    def pts(self, pattern=None, part=None):
        hits = [p for n, (pid, p, f) in self.nodes.items()
                if (part and pid == part) or (pattern and re.search(pattern, n[len(self.prefix):] if n.startswith(self.prefix) else n))]
        return np.concatenate(hits) if hits else None

    def mesh(self, short):
        _, p, f = self.nodes[self.prefix + short]
        return p, f

    def part(self, pid):
        return next((p for p in self.parts if p["id"] == pid), None)


# MARK: the skull

def load_skull(path, atlas):
    """The NIH 3D file's meshes by name, in its own frame."""
    gltf, binary = atlas.load_glb(path)
    nodes = gltf["nodes"]; out = {}
    def walk(i, parent):
        world = parent @ atlas.node_matrix(nodes[i])
        if "mesh" in nodes[i]:
            out[nodes[i].get("name", str(i))] = atlas.mesh_of(gltf, binary, nodes[i], world)
        for c in nodes[i].get("children", []):
            walk(c, world)
    for r in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    return out


def umeyama(src, dst, w=None):
    """The similarity (scale, rotation, shift) taking src onto dst best, weighted."""
    w = np.ones(len(src)) if w is None else w; w = w / w.sum()
    ms, md = (src * w[:, None]).sum(0), (dst * w[:, None]).sum(0); a, b = src - ms, dst - md
    U, S, Vt = np.linalg.svd((b * w[:, None]).T @ a); D = np.eye(3)
    if np.linalg.det(U @ Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt; s = (S * np.diag(D)).sum() / (w * (a ** 2).sum(1)).sum()
    return s, R, md - s * R @ ms


def fit_skull(skull, body, atlas):
    """The similarity placing the skull's eyes and upper teeth on the body's:
    first the eyes' centres (the file's axes turned to the atlas's), then
    closest points both ways on the eyes and the upper teeth."""
    R = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], float)
    v, f = skull["Eyes_Surface"]; piece = atlas.pieces(len(v), f)
    eyes = sorted([v[np.unique(f[piece == k])].mean(0) @ R.T for k in range(piece.max() + 1)], key=lambda c: c[0])
    assert len(eyes) == 2, f"the skull's eyes: {len(eyes)} pieces"
    vr, vl = centroid(*body.mesh("sclera_R")), centroid(*body.mesh("sclera_L"))
    s = np.linalg.norm(vl - vr) / np.linalg.norm(eyes[1] - eyes[0]); t = (vl + vr) / 2 - s * (eyes[0] + eyes[1]) / 2
    pairs = [(skull["Eyes_Surface"][0], np.concatenate([body.mesh("sclera_R")[0], body.mesh("sclera_L")[0]])),
             (skull["Upper teeth"][0], body.mesh("set_of_upper_jaw_teeth")[0])]
    trees = [cKDTree(d) for _, d in pairs]
    for _ in range(30):
        S, D, W = [], [], []
        for (src, dst), tree in zip(pairs, trees):
            x = s * src @ R.T + t
            _, j = tree.query(x); S.append(src); D.append(dst[j]); W.append(np.full(len(src), 1 / len(src)))
            _, i = cKDTree(x).query(dst); S.append(src[i]); D.append(dst); W.append(np.full(len(dst), 1 / len(dst)))
        s, R, t = umeyama(np.concatenate(S), np.concatenate(D), np.concatenate(W))
    lower = s * skull["Lower teeth"][0] @ R.T + t
    log(f"  skull: scale {s:.6f}; lower teeth {np.linalg.norm(lower.mean(0) - body.mesh('set_of_lower_jaw_teeth')[0].mean(0)) * 1000:.1f} mm from the body's")
    return {name: (s * v @ R.T + t, f) for name, (v, f) in skull.items() if not name.startswith("Eyes") and "teeth" not in name}


def joined(d):
    P, F, o = [], [], 0
    for v, f in d.values():
        P.append(v); F.append(f + o); o += len(v)
    return np.concatenate(P), np.concatenate(F)


def split_back(d, p):
    out, o = {}, 0
    for k, (v, f) in d.items():
        out[k] = (p[o:o + len(v)], f); o += len(v)
    return out


def head_skin(body):
    p, f = body.mesh("skin")
    below = centroid(*body.mesh("cervical_vertebra_2"))[1] - 0.03
    return p, f[(p[f][:, :, 1] > below).all(1)]


def spread(U, need, degrees):
    """A need per direction, covering its neighbours within `degrees` and smoothed over them."""
    cs = np.cos(np.radians(degrees)); K = np.clip((U @ U.T - cs) / (1 - cs), 0, 1)
    grown = (K * need[None]).max(1)
    return (K * grown[None]).sum(1) / K.sum(1)


def along(p, centre, U, field, degrees):
    """The field's value at each point's direction from centre, blended over neighbouring directions."""
    r = p - centre; up = r / np.linalg.norm(r, axis=1, keepdims=True)
    cs = np.cos(np.radians(degrees)); K = np.clip((up @ U.T - cs) / (1 - cs), 0, 1); ws = K.sum(1)
    return up, np.where(ws > 0, (K * field[None]).sum(1) / np.maximum(ws, 1e-9), 0)


def tuck(d, centre, skin, margin=0.0025, cap=0.005, ignore=0.008, n=3000, degrees=12):
    """Move the skull in where it comes closer than `margin` to the skin,
    seen from centre, by at most `cap`; a direction short by more than
    `ignore` looks out through a nostril or the lips, and is left alone."""
    p, f = joined(d); U = fib(n); S = last_hits(centre, U, *skin)
    r = p - centre; rp = np.linalg.norm(r, axis=1)
    near = cKDTree(U).query(r / rp[:, None])[1]; reach = np.zeros(len(U)); np.maximum.at(reach, near, rp)
    need = np.where(np.isfinite(S), np.maximum(0, reach + margin - S), 0)
    need = np.where(need > ignore, 0, np.minimum(need, cap))
    up, push = along(p, centre, U, spread(U, need, degrees), degrees)
    log(f"  skull kept under the skin: {np.mean(need > 0):.1%} of directions, at most {need.max() * 1000:.1f} mm")
    return split_back(d, p - up * push[:, None])


def outside_skin(d, centre, skin, n=3000):
    U = fib(n); S = last_hits(centre, U, *skin); tree = cKDTree(U); out = {}
    for k, (v, f) in d.items():
        r = v - centre; rp = np.linalg.norm(r, axis=1); out[k] = float(np.mean(rp > S[tree.query(r / rp[:, None])[1]]))
    return out


def brain_pivot(body):
    medulla = np.concatenate([p for n, (pid, p, f) in body.nodes.items() if n.startswith("Allen") and "medulla" in n.lower()])
    return (medulla[medulla[:, 1].argmin()] + centroid(*body.mesh("optic_chiasm"))) / 2


def past_inner_table(skull_p, skull_f, brain, centre, n=3000, below=-0.1):
    """Per direction over the vault, how far the brain reaches beyond the
    first surface of the skull met from centre (the inner table)."""
    U = fib(n); U = U[U[:, 1] > below]; hit = first_hits(centre, U, skull_p, skull_f)
    q = brain - centre; rq = np.linalg.norm(q, axis=1); near = cKDTree(U).query(q / rq[:, None])[1]
    reach = np.zeros(len(U)); np.maximum.at(reach, near, rq)
    return U, hit, np.where(np.isfinite(hit), reach - hit, -1)


def size_brain(body, skull, scales=(0.94, 0.93, 0.92, 0.91, 0.90)):
    """Scale the brain about its pivot by the largest of `scales` that leaves
    it past the skull's inner table in under 1 % of the vault's directions;
    then ease the vault out where it still is, by at most 4 mm."""
    brain = {n: p for n, (pid, p, f) in body.nodes.items() if pid == "brain" and n.startswith("Allen")}
    allb = sample(np.concatenate(list(brain.values())), 40000, 0); pv = brain_pivot(body); sp, sf = joined(skull)
    for s in scales:
        q = pv + s * (allb - pv); c = q.mean(0)
        _, _, short = past_inner_table(sp, sf, q, c)
        share = float(np.mean(short > 0.0005))
        if share < 0.01:
            break
    log(f"  brain scaled by {s} about {np.round(pv, 3)}: past the inner table in {share:.1%} of the vault's directions")
    U, hit, short = past_inner_table(sp, sf, q, c, n=2000)
    need = np.minimum(0.004, np.maximum(0, short + 0.001))
    up, push = along(sp, c, U, spread(U, need, 25), 25)
    fade = np.clip((up[:, 1] + 0.1) / 0.25, 0, 1)
    skull = split_back(skull, sp + up * (push * fade)[:, None])
    return s, pv, skull


def skull_items(d):
    """The skull's structures: paired bones split at the midline (the vomer's)."""
    x0 = float(np.median(d["Vomer"][0][:, 0])); items = []
    for name, node, label, paired, uberon in SKULL_BONES:
        v, f = d[name]
        if not paired:
            items.append((f"NLM_{node}", label, uberon, v, f)); continue
        left = v[f].mean(1)[:, 0] > x0
        for side, s, keep in (("left", "L", left), ("right", "R", ~left)):
            g = f[keep]; used = np.unique(g); remap = np.full(len(v), -1); remap[used] = np.arange(len(used))
            items.append((f"NLM_{node}_{s}", f"{side} {label}", uberon, v[used], remap[g]))
    return items


# MARK: the arms

def _rot(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b); v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def _axis_angle(k, t):
    k = k / np.linalg.norm(k); K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K


def _sphere(p):
    A = np.hstack([2 * p, np.ones((len(p), 1))]); x, *_ = np.linalg.lstsq(A, (p ** 2).sum(1), rcond=None)
    return x[:3], np.sqrt(x[3] + x[:3] @ x[:3])


def _long_axis(p):
    c = p.mean(0); _, _, vt = np.linalg.svd(p - c, full_matrices=False)
    return c, vt[0]


def _loops(v, f, o, n):
    """The closed curves where a plane through o, normal n, cuts a mesh."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    d = (v - o) @ n; side = d > 0
    t3 = side[f]; fc = f[t3.any(1) & ~t3.all(1)]
    if len(fc) == 0:
        return []
    E = np.stack([fc[:, [0, 1]], fc[:, [1, 2]], fc[:, [2, 0]]], 1)
    e = np.sort(E[side[E[..., 0]] != side[E[..., 1]]].reshape(-1, 2, 2), axis=2)
    keys, inv = np.unique(e.reshape(-1, 2), axis=0, return_inverse=True); inv = inv.reshape(-1, 2)
    k = len(keys); _, lab = connected_components(coo_matrix((np.ones(len(inv)), (inv[:, 0], inv[:, 1])), shape=(k, k)), directed=False)
    a, b = keys[:, 0], keys[:, 1]; t = d[a] / (d[a] - d[b]); pts = v[a] + (v[b] - v[a]) * t[:, None]
    return [pts[lab == i] for i in range(lab.max() + 1)]


def _arm_line(skin, faces, shoulder, side, length):
    """The arm's centre line in the skin, from the shoulder toward the hand:
    through the centres of the skin's cross-sections, refined until it settles."""
    tip = skin[np.argmax(side * skin[:, 0])]; d = (tip - shoulder) / np.linalg.norm(tip - shoulder)
    for _ in range(4):
        cs = []
        for t in np.linspace(0.3, 0.95, 12) * length:
            o = shoulder + t * d
            ls = [q for q in _loops(skin, faces, o, d) if len(q) > 6 and side * q.mean(0)[0] > side * shoulder[0] + 0.01]
            if ls:
                best = min(ls, key=lambda q: np.linalg.norm(q.mean(0) - o))
                if np.linalg.norm(best.mean(0) - o) < 0.12:
                    cs.append(best.mean(0))
        if len(cs) < 3:
            log(f"    arm line: only {len(cs)} cross-sections found; the line to the hand kept")
            break
        r = np.array(cs) - shoulder; _, _, vt = np.linalg.svd(r, full_matrices=False)
        d = vt[0] if vt[0] @ d > 0 else -vt[0]
    return d


def _epicondyles(p, axis):
    t = (p - p.mean(0)) @ axis; low = p[t < np.percentile(t, 8)]
    q = low - low.mean(0); q = q - np.outer(q @ axis, axis); _, _, vt = np.linalg.svd(q, full_matrices=False)
    return vt[0], low.mean(0)


def place_humerus(p, skin, faces, side, medial):
    """A humerus (in the body, scaled) moved along the skin's arm, its head
    kept, turned so its epicondyles lie across the arm, `medial` toward the body."""
    c, ax = _long_axis(p)
    if ax[1] < 0:
        ax = -ax
    head, _ = _sphere(p[(p - c) @ ax > np.percentile((p - c) @ ax, 88)])
    d = _arm_line(skin, faces, head, side, np.ptp((p - c) @ ax))
    R1 = _rot(-ax, d); q = (p - head) @ R1.T
    e, _ = _epicondyles(q, d)
    if e @ (R1 @ medial) < 0:
        e = -e
    want = np.cross(d, [0, 0, 1.0]); want -= (want @ d) * d; want /= np.linalg.norm(want)
    if want[0] * side > 0:
        want = -want
    return q @ _axis_angle(d, np.arctan2(np.cross(e, want) @ d, e @ want)).T + head


# MARK: making room

def surface_points(v, f, h):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    L = np.maximum(np.linalg.norm(b - a, axis=1), np.linalg.norm(c - a, axis=1))
    n = np.clip(np.ceil(L / (h * 0.7)).astype(int), 1, 40); out = [a, b, c]
    for k in np.unique(n):
        if k == 1:
            continue
        sel = n == k; i, j = np.meshgrid(np.arange(k + 1), np.arange(k + 1)); m = i + j <= k; s, t = i[m] / k, j[m] / k
        out.append((a[sel, None] * (1 - s - t)[None, :, None] + b[sel, None] * s[None, :, None] + c[sel, None] * t[None, :, None]).reshape(-1, 3))
    return np.concatenate(out)


class Solid:
    """What a part fills, on a 2 mm grid: its surfaces as voxels, closed
    over small gaps and filled, with the way out from every voxel inside."""
    def __init__(self, meshes, h=0.002, close=2):
        P = np.concatenate([surface_points(v, f, h) for v, f in meshes])
        self.lo = P.min(0) - (close + 3) * h; self.h = h
        idx = np.floor((P - self.lo) / h).astype(int); g = np.zeros(idx.max(0) + close + 4, bool); g[tuple(idx.T)] = True
        self.g = ndimage.binary_fill_holes(ndimage.binary_closing(g, iterations=close))
        _, self.ind = ndimage.distance_transform_edt(self.g, return_indices=True)

    def inside(self, p):
        idx = np.floor((p - self.lo) / self.h).astype(int); ok = ((idx >= 0) & (idx < self.g.shape)).all(1)
        out = np.zeros(len(p), bool); out[ok] = self.g[tuple(idx[ok].T)]
        return out

    def way_out(self, p, margin):
        idx = np.floor((p - self.lo) / self.h).astype(int)
        q = self.lo + (np.stack([self.ind[k][tuple(idx.T)] for k in range(3)], 1) + 0.5) * self.h
        d = q - p; return d + d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9) * margin


def push_out(p, solids, margin=0.0015, sigma=0.010, rounds=10, step=0.003):
    """Move a mesh's points out of the solids: each round, the points inside
    pulled toward the way out, the pull spread smoothly over the mesh, no
    point moving more than `step`."""
    for _ in range(rounds):
        D = np.zeros_like(p); hit = np.zeros(len(p), bool)
        for S in solids:
            m = S.inside(p)
            if m.any():
                D[m] += S.way_out(p[m], margin); hit |= m
        if not hit.any():
            break
        src, d = p[hit], D[hit]; out = np.zeros_like(p); ws = np.zeros(len(p))
        for i in range(0, len(p), 2000):
            g = np.exp(-((p[i:i + 2000, None] - src[None]) ** 2).sum(-1) / (2 * sigma ** 2))
            out[i:i + 2000] = g @ d; ws[i:i + 2000] = g.sum(1)
        mv = out / np.maximum(ws, 1)[:, None]; n = np.linalg.norm(mv, axis=1, keepdims=True)
        p = p + mv * np.minimum(1, step / np.maximum(n, 1e-9))
    return p


# What each part from a scan must stay out of.
OBSTACLES = {
    "ribs": ["liver", "lungs", "heart", "spleen", "colon", "kidneys"],
    "sternum": ["heart", "lungs", "liver"],
    "shoulders": ["ribs", "lungs"],
    "oesophagus": ["heart", "airways", "lungs", "larynx"],
    "stomach": ["liver", "pancreas", "colon", "spleen", "small-intestine", "kidneys", "heart", "lungs", "gallbladder", "ribs"],
    "thyroid": ["larynx", "airways"],
    "adrenals": ["liver", "kidneys", "spleen", "pancreas", "stomach"],
    "arms": ["liver", "lungs", "ribs", "colon", "spleen"],
    "hip-muscles": ["pelvis", "vertebral-column", "legs", "colon", "bladder", "kidneys"],
    "back-muscles": ["vertebral-column", "pelvis", "ribs", "kidneys"],
}
# Parts whose structures are each a solid of their own (bones), rather than one together.
EACH = {"pelvis", "vertebral-column", "legs", "ribs"}


def make_room(body, pid, part, cache):
    solids = []
    for o in OBSTACLES[pid]:
        other = body.part(o)
        if other is None:
            continue
        if o not in cache:
            meshes = [m for s, m in zip(other["structures"], other["meshes"])
                      if not re.search("ligament|falciform|venosum|hepataduodenal", s["node"])]
            cache[o] = [Solid([m]) for m in meshes] if o in EACH else [Solid(meshes)]
        solids += cache[o]
    moved = []
    for i, (s, (p, f)) in enumerate(zip(part["structures"], part["meshes"])):
        before = np.mean(np.any([S.inside(p) for S in solids], 0))
        q = push_out(p, solids)
        after = np.mean(np.any([S.inside(q) for S in solids], 0))
        if before > 0.01:
            moved.append(f"{s['node']} {before:.0%}->{after:.0%}")
        part["meshes"][i] = (q, f)
    if moved:
        log(f"    {pid}: out of {', '.join(OBSTACLES[pid])}: " + "; ".join(moved))


# MARK: the chest and shoulders

def chest_axis(body):
    """The chest's vertical axis: through the middle of the lungs' x and z ranges."""
    p = body.pts(part="lungs")
    return np.array([(p[:, 0].min() + p[:, 0].max()) / 2, 0, (p[:, 2].min() + p[:, 2].max()) / 2])


def _cyl(p, ax):
    d = p - ax
    return p[:, 1], np.arctan2(d[:, 0], d[:, 2])


def _outward(p, ax):
    d = p - ax; d[:, 1] = 0
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)


def _exits(p, ax, solids, margin=0.002, reach=0.05, step=0.001):
    """How far each point must go out, level and away from the axis, to leave every solid (0 if it is out)."""
    d = _outward(p, ax); inside = lambda q: np.any([S.inside(q) for S in solids], 0)
    need = np.zeros(len(p)); todo = inside(p)
    for k in np.arange(step, reach + step, step):
        if not todo.any():
            break
        idx = np.flatnonzero(todo); free = ~inside(p[idx] + d[idx] * k)
        need[idx[free]] = k + margin; todo[idx[free]] = False
    return need  # still inside after `reach`: left alone


def _room(p, ax, skin, margin=0.006, reach=0.06, step=0.002):
    """How far each point can go out, level and away from the axis, before it comes within `margin` of the skin's outside."""
    d = _outward(p, ax); room = np.full(len(p), reach); todo = np.ones(len(p), bool)
    for k in np.arange(step, reach + step, step):
        idx = np.flatnonzero(todo)
        if not len(idx):
            break
        out = ~skin.inside(p[idx] + d[idx] * (k + margin))
        room[idx[out]] = k - step; todo[idx[out]] = False
    return np.maximum(room, 0)


def _grid_field(y, th, value, yb, tb, reduce, sy=0.025, st=np.radians(25)):
    from scipy.interpolate import RegularGridInterpolator
    F = np.full((len(yb), len(tb)), 0.0 if reduce == "max" else np.inf)
    iy = np.clip(np.searchsorted(yb, y), 0, len(yb) - 1); it = np.clip(np.searchsorted(tb, th), 0, len(tb) - 1)
    (np.maximum if reduce == "max" else np.minimum).at(F, (iy, it), value)
    ky = max(1, int(sy / (yb[1] - yb[0]))); kt = max(1, int(st / (tb[1] - tb[0])))
    if reduce == "max":
        F = ndimage.gaussian_filter(ndimage.maximum_filter(F, size=(2 * ky + 1, 2 * kt + 1), mode=("nearest", "wrap")),
                                    sigma=(ky, kt), mode=("nearest", "wrap"))
    else:
        F = np.where(np.isfinite(F), F, 1.0)
        F = ndimage.minimum_filter(F, size=(2 * ky + 1, 2 * kt + 1), mode=("nearest", "wrap"))
    tb3 = np.concatenate([tb - 2 * np.pi, tb, tb + 2 * np.pi])
    f = RegularGridInterpolator((yb, tb3), np.concatenate([F, F, F], 1), bounds_error=False, fill_value=0)
    return lambda yy, tt: f(np.stack([yy, tt], 1))


def widen_cage(body, cage, riders):
    """Widen the rib cage, smoothly by height and angle about the chest's
    axis, until it clears the organs inside it, never closer than 6 mm to
    the skin; what rides on it (the shoulder girdle) moves with it. cage,
    riders: lists of [positions, triangles] changed in place."""
    organs = [Solid([m for m in body.part(o)["meshes"]]) for o in ("lungs", "liver", "heart", "spleen", "kidneys", "colon")
              if body.part(o) is not None]
    skin = Solid([body.mesh("skin")], h=0.003, close=1)
    ax = chest_axis(body)
    for r in range(4):
        pts = np.concatenate([m[0] for m in cage]); need = _exits(pts, ax, organs)
        log(f"    cage, round {r}: {np.mean(need > 0):.1%} of its points inside organs, the deepest {need.max() * 1000:.0f} mm")
        if not (need > 0).any():
            break
        y, th = _cyl(pts, ax); yb = np.arange(y.min() - 0.02, y.max() + 0.02, 0.005); tb = np.linspace(-np.pi, np.pi, 72, endpoint=False)
        grow = _grid_field(y, th, need, yb, tb, "max"); room = _grid_field(y, th, _room(pts, ax, skin), yb, tb, "min")
        for m in cage + riders:
            yy, tt = _cyl(m[0], ax); m[0] = m[0] + _outward(m[0], ax) * np.minimum(grow(yy, tt), room(yy, tt))[:, None]


def lower_shoulders(body, shoulders, arms):
    """Turn each side's clavicle and scapula down about the sternoclavicular
    joint, by the least that brings them under the skin, and its humerus's
    head with them (the scans' shoulders are raised); then re-place the
    humerus along the arm. shoulders, arms: their parts, changed in place."""
    skin = Solid([body.mesh("skin")], h=0.003, close=1); sp, sf = body.mesh("skin")
    for side, s in SIDES:
        sign = 1 if side == "left" else -1
        ci = next(i for i, st in enumerate(shoulders["structures"]) if st["node"] == f"TS_clavicle_{s}")
        si = next(i for i, st in enumerate(shoulders["structures"]) if st["node"] == f"TS_scapula_{s}")
        hi = next(i for i, st in enumerate(arms["structures"]) if st["node"] == f"TS_humerus_{s}")
        clav, scap = shoulders["meshes"][ci][0], shoulders["meshes"][si][0]
        joint = clav[np.argmin(np.abs(clav[:, 0]))]
        both = np.concatenate([clav, scap])
        for deg in range(0, 41):
            # about +z a positive turn takes +x up, so the left side (x > 0)
            # turns by a negative angle to bring its lateral end down
            R = _axis_angle(np.array([0, 0, 1.0]), -np.radians(deg) * sign)
            out = 1 - skin.inside((both - joint) @ R.T + joint).mean()
            if out < 0.003:
                break
        log(f"    {side} shoulder lowered {deg} degrees; {out:.1%} of it outside the skin")
        if deg == 0:
            continue
        shoulders["meshes"][ci][0] = (clav - joint) @ R.T + joint
        shoulders["meshes"][si][0] = (scap - joint) @ R.T + joint
        hp = arms["meshes"][hi][0]; c, ax = _long_axis(hp)
        if ax[1] < 0:
            ax = -ax
        head, _ = _sphere(hp[(hp - c) @ ax > np.percentile((hp - c) @ ax, 88)])
        moved = (head - joint) @ R.T + joint
        e, _ = _epicondyles(hp, ax)
        medial = e if e[0] * sign < 0 else -e
        arms["meshes"][hi][0] = place_humerus(hp - head + moved, sp, sf, sign, medial)


# MARK: the scans' warps

def pairs(body, sex, folder, hips=None):
    """(name, scan points, body points, weight, kind) for every structure both have. hips: the
    scan's whole hip bones already fitted to a body whose own stop short (whole_hips), paired in
    their place."""
    P = body.prefix; hips = hips or {}
    def ct(names, sigma=1.0):
        ms = []
        for n in names:
            a, A = load_mask(os.path.join(folder, n + ".nii.gz"))
            m = ct_mesh(a, A, sigma=sigma, share=0.2)
            if m is not None:
                ms.append(m[0])
        return np.concatenate(ms) if ms else None
    out = []
    def add(name, masks, target, w=1.0, n=500, kind="surface", top=None):
        c = ct(masks if isinstance(masks, list) else [masks])
        if c is not None and top is not None:   # as much of the scan's as the body's: its top `top` metres
            c = c[c[:, 1] > c[:, 1].max() - top]
        if c is not None and target is not None:
            out.append((name, sample(c, n), sample(target, 4 * n, 1), w, kind))
    for letter, word, count in LEVELS:
        for i in range(1, count + 1):
            add(f"{letter}{i}", f"vertebrae_{letter}{i}", body.pts(f"^{word}_vertebra_{i}$"), n=200)
    lumbar = [body.pts(f"^lumbar_vertebra_{i}$") for i in range(1, 7)]; lumbar = [v for v in lumbar if v is not None]
    for i in range(1, 6):
        if len(lumbar) == 5:
            add(f"L{i}", f"vertebrae_L{i}", lumbar[i - 1], n=200)
        else:  # six lumbar vertebrae in the body, five in the scan: spread along the curve, centres only
            c = ct([f"vertebrae_L{i}"])
            cs = np.array([v.mean(0) for v in lumbar]); t = (i - 1) / 4 * (len(cs) - 1); k = min(int(t), len(cs) - 2); f_ = t - k
            out.append((f"L{i}", c.mean(0, keepdims=True), (cs[k] * (1 - f_) + cs[k + 1] * f_)[None], 4.0, "centre"))
    add("sacrum", "sacrum", body.pts("^sacrum$"))
    mid_b, mid_c = midline(body.pts("^sacrum$")), midline(ct_surface(folder, "sacrum")[0])
    for side, s in SIDES:
        add(f"hip {side}", f"hip_{side}", surface_points(*hips[side], 0.003) if side in hips
            else body.pts(f"^(ilium|ischium|pubis)_compact_bone_{s}$"))
        femur = body.pts(f"^femur_{s}$")
        add(f"femur {side}", f"femur_{side}", femur[femur[:, 1] > femur[:, 1].max() - 0.15], top=0.15)
        out.append((f"head {side}", femoral_head(ct_surface(folder, f"femur_{side}")[0], mid_c)[0][None],
                    femoral_head(femur, mid_b)[0][None], 4.0, "centre"))
        add(f"kidney {side}", f"kidney_{side}", body.pts(f"^kidney_capsule_{s}$"))
    add("liver", "liver", body.pts("^(liver_capsule|capsule_of_the_liver)$"))
    add("spleen", "spleen", shell(body.pts(part="spleen")))
    lungs = {n: p for n, (pid, p, f) in body.nodes.items() if pid == "lungs" and "hilum" not in n}
    for side in ("left", "right"):
        pts = np.concatenate([p for n, p in lungs.items() if re.search(f"{side}_|lingula" if side == "left" else f"{side}_", n)])
        lobes = [f"lung_{l}_lobe_{side}" for l in (("upper", "lower") if side == "left" else ("upper", "middle", "lower"))]
        add(f"lung {side}", lobes, shell(pts), n=800)
    add("trachea", "trachea", body.pts("^trachea$"))
    add("heart", "heart", shell(body.pts(part="heart")), n=600)
    add("brain", "brain", shell(body.pts(part="brain")), n=800)
    add("aorta", "aorta", body.pts("^(ascending_aorta|aortic_arch|descending_aorta_[ab])$"), 0.5)
    add("pancreas", "pancreas", body.pts(part="pancreas"), 0.3)
    if sex == "male":
        add("skull", "skull", np.concatenate([p for n, (pid, p, f) in body.nodes.items() if pid == "skull"]), n=1200)
    else:
        add("sternum", "sternum", body.pts("^(sternum|manubrium)$"))
    return out


REGIONS = {
    "pelvis": r"^(L[345]|sacrum|hip left|hip right|femur left|femur right|head left|head right)$",
}


def warps(body, sex, folder, hips=None):
    found = pairs(body, sex, folder, hips)
    log(f"  {sex}: the warp, on {len(found)} pairs")
    w = register(found)
    out = {"global": w}
    for region, pattern in REGIONS.items():
        local = [(n, w(c), v, wt, k) for n, c, v, wt, k in found if re.search(pattern, n)]
        log(f"  {sex}: the {region}'s closer warp, on {len(local)} pairs")
        out[region] = Then(w, register(local, rounds=(1e-3, 3e-4, 1e-4, 3e-5), control=3000))
    return out


# MARK: the hip bones

def midline(p):
    return float(np.median(p[:, 0]))


def ct_surface(folder, name, sigma=0.8, share=0.05):
    a, A = load_mask(os.path.join(folder, name + ".nii.gz"))
    return ct_mesh(a, A, sigma=sigma, share=share)


def femoral_head(p, mid):
    """The femoral head's centre and radius: a sphere fitted to the top of the femur on its inner
    side, then again to the points lying on it."""
    top = p[p[:, 1] > p[:, 1].max() - 0.07]
    d = np.abs(top[:, 0] - mid)
    c, r = _sphere(top[d < np.percentile(d, 40)])
    for _ in range(5):
        c, r = _sphere(top[np.abs(np.linalg.norm(top - c, axis=1) - r) < 0.003])
    return c, r


def whole_hips(body, folder):
    """The scan's whole hip bones for a body whose own stop above the hip joint (the female organ
    set's "hip bone" is the ilium alone: no pubis or ischium). Each is fitted to the body's ilium
    (the scan's cut at the same height above its femoral head) and femoral head by a similarity,
    which keeps the scan's own pelvis whole (a warp fitted on the ilium alone tips the pubis back);
    then the two pubic bodies are brought together at the midline, the rami eased smoothly, nothing
    7 cm away moving. {side: (positions, triangles)}, or {} for a body whose hip bones are whole."""
    mid_b, mid_c = midline(body.pts("^sacrum$")), midline(ct_surface(folder, "sacrum")[0])
    heads = {side: femoral_head(body.pts(f"^femur_{s}$"), mid_b)[0] for side, s in SIDES}
    if all(body.pts(f"^(ilium|ischium|pubis)_compact_bone_{s}$")[:, 1].min() < heads[side][1] for side, s in SIDES):
        return {}
    out, faces = {}, {}
    for side, s in SIDES:
        bh = heads[side]; ch = femoral_head(ct_surface(folder, f"femur_{side}")[0], mid_c)[0]
        p, f = ct_surface(folder, f"hip_{side}")
        ib = surface_points(*body.mesh(f"ilium_compact_bone_{s}"), 0.002); cp = surface_points(p, f, 0.002)
        h = ib[:, 1].min() - bh[1] + 0.006     # just above where the body's ilium stops
        dst = sample(ib[ib[:, 1] > bh[1] + h], 3000, 1); tree = cKDTree(dst)
        sc, R, t = 1.0, np.eye(3), bh - ch
        for k in range(60):
            if k in (0, 30):                   # the scan cut at the same height, in the scan's own size
                src = sample(cp[cp[:, 1] > ch[1] + h / sc], 3000, 0)
            X = sc * src @ R.T + t
            j = tree.query(X)[1]; i = cKDTree(X).query(dst)[1]
            sc, R, t = umeyama(np.vstack([src, src[i], ch[None]]), np.vstack([dst[j], dst, bh[None]]),
                               np.concatenate([np.ones(len(src) + len(dst)), [0.3 * (len(src) + len(dst))]]))
        X = sc * src @ R.T + t; q = sc * p @ R.T + t
        turned = np.degrees(np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1)))
        log(f"    {side} hip bone: scaled x{sc:.3f}, turned {turned:.1f} degrees; ilium fit {tree.query(X)[0].mean() * 1000:.1f} mm, "
            f"head {np.linalg.norm(sc * R @ ch + t - bh) * 1000:.1f} mm")
        sgn = 1 if side == "left" else -1
        low = q[q[:, 1] < bh[1]]; reach = (low[:, 0] * sgn).min()
        faces[side] = low[low[:, 0] * sgn < reach + 0.006].mean(0)     # the symphyseal face
        out[side] = (q, f)
    mid = 0.5 * (faces["left"] + faces["right"])
    for side, s in SIDES:
        sgn = 1 if side == "left" else -1
        D = np.array([mid_b + sgn * 0.002, mid[1], mid[2]]) - faces[side]
        q, f = out[side]; dist = np.linalg.norm(q - faces[side], axis=1)
        fixed = sample(np.flatnonzero(dist > 0.07), 400, 0); moved = np.flatnonzero(dist < 0.012)
        ease = RBFInterpolator(np.vstack([q[fixed], q[moved]]), np.vstack([np.zeros((len(fixed), 3)), np.tile(D, (len(moved), 1))]),
                               kernel="thin_plate_spline", smoothing=1e-6)
        out[side] = (q + ease(q), f)
        log(f"    {side} pubic body moved {np.linalg.norm(D) * 1000:.0f} mm to meet the other at the midline")
    return out


def put_hips(body, hips, atlas):
    """The body's short hip bones (its ilia) replaced by the whole ones."""
    part = body.part("pelvis")
    for side, s in SIDES:
        i = next(k for k, st in enumerate(part["structures"]) if st["node"] == f"{body.prefix}ilium_compact_bone_{s}")
        part["structures"][i] = {"node": f"TS_hip_{s}", "label": f"{side} hip bone", "uberon": u("0001272"),
                                 "tissue": "bone", "group": "Pelvis", "inner": False}
        part["meshes"][i] = tuple(atlas.simplify(*hips[side], 4000))


# MARK: the parts from the scans

def ct_part(body, sex, folder, warp, pid, name, system, rows):
    structures, meshes = [], []
    if pid == "arms":
        return arms(body, folder, warp, rows)
    for mask, node, label, tissue, budget, uberon in rows:
        a, A = load_mask(os.path.join(folder, mask + ".nii.gz"))
        m = ct_mesh(a, A, sigma=0.8 if tissue in ("bone", "cartilage", "muscle") else 1.0, share=0.05)
        assert m is not None, f"{sex}: the scan's {mask} is empty"
        meshes.append((warp(m[0]), m[1], budget))
        structures.append({"node": node, "label": label, "uberon": uberon, "tissue": tissue, "group": name, "inner": False})
    return structures, meshes


def arms(body, folder, w, rows):
    """The humeri, scaled as the warp scales the shoulders, placed along the skin's arms."""
    skin, faces = body.mesh("skin")
    def jacobian(x):
        return np.stack([(w(x[None] + 0.01 * e)[0] - w(x[None] - 0.01 * e)[0]) / 0.02 for e in np.eye(3)], 1)
    loaded = []
    for mask, *_ in rows:
        a, A = load_mask(os.path.join(folder, mask + ".nii.gz")); loaded.append(ct_mesh(a, A))
    heads = [p[p[:, 1] > np.percentile(p[:, 1], 90)].mean(0) for p, f in loaded]
    scale = float(np.mean([abs(np.linalg.det(jacobian(h))) ** (1 / 3) for h in heads]))
    log(f"    arms: humeri scaled by {scale:.3f}")
    structures, meshes = [], []
    for (mask, node, label, tissue, budget, uberon), (p, f), head in zip(rows, loaded, heads):
        side = 1 if mask.endswith("left") else -1
        c, ax = _long_axis(p); e, low = _epicondyles(p, ax)
        medial = e if abs((low + 0.02 * e)[0]) < abs((low - 0.02 * e)[0]) else -e  # nearer the scan's midline
        tw = w(np.array([low, low + 0.01 * medial])); medial = (tw[1] - tw[0]) / np.linalg.norm(tw[1] - tw[0])
        q = place_humerus((p - head) * scale + w(head[None])[0], skin, faces, side, medial)
        meshes.append((q, f, budget))
        structures.append({"node": node, "label": label, "uberon": uberon, "tissue": tissue, "group": "Arm bones", "inner": False})
    return structures, meshes


def place(parts, new, before):
    """Insert a part before the first of `before` the body has, else at the end."""
    ids = [p["id"] for p in parts]
    at = next((ids.index(b) for b in before if b in ids), len(parts))
    parts.insert(at, new)


# MARK: both bodies

def extend(bodies, skull_path, ct_dir, atlas):
    """Add the missing parts to both bodies and size their brains. bodies:
    {"male": parts, "female": parts}, each part a dict with id, name,
    system, structures (without triangles) and meshes [(positions,
    triangles)], as anatomy_atlas.py collected them; changed in place."""
    got = _sha(skull_path)
    assert got == SKULL_SOURCE["sha256"], f"{skull_path}: SHA-256 {got}, expected {SKULL_SOURCE['sha256']}"
    import anatomy_limbs, anatomy_feet
    need = {}
    for sex, subject in SUBJECT.items():
        need.setdefault(subject, set()).update(masks_used(sex))
    for sex in ("male", "female"):   # the forearms and hands: the CT itself, and the bones taken out before them
        need.setdefault(anatomy_limbs.LIMBS[sex]["subject"], set()).update(anatomy_limbs.files_used(sex))
    for sex in ("male", "female"):   # the feet: the CT itself
        need.setdefault(anatomy_feet.FEET[sex]["subject"], set()).update(anatomy_feet.files_used(sex))
    for subject, names in need.items():
        folder = os.path.join(ct_dir, subject); got = digest(folder, names)
        assert CT_SHA256[subject] in (None, got), f"{folder}: files digest {got}, expected {CT_SHA256[subject]}"
        CT_SHA256[subject] = got
    male, female = Body("male", bodies["male"]), Body("female", bodies["female"])

    # the heads
    log("the heads")
    skull = fit_skull(load_skull(skull_path, atlas), male, atlas)
    cm = male.pts(part="brain").mean(0); skin_m = head_skin(male)
    skull_m = tuck(skull, cm, skin_m)
    skin_f = head_skin(female); cf = female.pts(part="brain").mean(0)
    def marks(b):
        return [centroid(*b.mesh(n)) for n in ("sclera_L", "sclera_R", "set_of_upper_jaw_teeth", "set_of_lower_jaw_teeth")]
    head = [("skin", sample(skin_m[0][np.unique(skin_m[1])], 3000, 0), sample(skin_f[0][np.unique(skin_f[1])], 12000, 1), 1.0, "surface")]
    head += [(f"C{i}", sample(male.mesh(f"cervical_vertebra_{i}")[0], 200, 0), sample(female.mesh(f"cervical_vertebra_{i}")[0], 800, 1), 1.0, "surface")
             for i in (1, 2, 3)]
    head += [(n, a[None], b[None], 4.0, "centre") for n, a, b in zip(("eye L", "eye R", "upper teeth", "lower teeth"), marks(male), marks(female))]
    log("  her head, from his")
    W = register(head, rounds=(3e-2, 1e-2, 3e-3, 1e-3))
    skull_f = tuck({k: (W(v), f) for k, (v, f) in skull_m.items()}, cf, skin_f)
    for body, sk, skin, c in ((male, skull_m, skin_m, cm), (female, skull_f, skin_f, cf)):
        s, pv, sk = size_brain(body, sk); RESULTS[body.sex + " brain scale"] = s
        brain = body.part("brain")
        brain["meshes"] = [(pv + s * (p - pv), f) if st["node"].startswith("Allen") else (p, f)
                           for st, (p, f) in zip(brain["structures"], brain["meshes"])]
        out = {k: round(v, 3) for k, v in outside_skin(sk, c, skin).items() if v > 0.002}
        log(f"  {body.sex}: skull outside the skin: {out or 'none'}")
        items = skull_items(sk)
        place(body.parts, {"id": "skull", "name": "Skull", "system": "skeletal",
                           "structures": [{"node": n, "label": l, "uberon": u(ub), "tissue": "bone", "group": "Skull", "inner": False}
                                          for n, l, ub, v, f in items],
                           "meshes": [(v, f) for n, l, ub, v, f in items], "budget": None},
              ["sternum", "vertebral-column"])
        body.__init__(body.sex, body.parts)  # the skull and the sized brain, for the warps

    # the parts from the scans
    for body in (male, female):
        sex = body.sex; folder = os.path.join(ct_dir, SUBJECT[sex])
        log(f"{sex}: the scan {SUBJECT[sex]}")
        hips = whole_hips(body, folder)
        ws = warps(body, sex, folder, hips); ws["arm"] = ws["global"]
        made = {}
        for pid, name, system, before, region, rows in CT_PARTS:
            if pid == "sternum" and body.part("sternum") is not None:
                continue
            structures, meshes = ct_part(body, sex, folder, ws[region], pid, name, system, rows)
            part = {"id": pid, "name": name, "system": system, "structures": structures,
                    "meshes": [list(atlas.simplify(p, f, b)) for p, f, b in meshes]}
            place(body.parts, part, before); made[pid] = part
            log(f"    {pid}: {len(structures)} structures")
        if hips:
            put_hips(body, hips, atlas)
            log("    pelvis: the whole hip bones in place of the ilia")
        body.__init__(sex, body.parts)
        widen_cage(body, made["ribs"]["meshes"] + (made["sternum"]["meshes"] if "sternum" in made else []),
                   made["shoulders"]["meshes"])
        lower_shoulders(body, made["shoulders"], made["arms"])
        for part in made.values():
            part["meshes"] = [tuple(m) for m in part["meshes"]]
        body.__init__(sex, body.parts)
        cache = {}
        for pid in ("oesophagus", "stomach", "thyroid", "adrenals", "arms", "hip-muscles", "back-muscles"):
            make_room(body, pid, made[pid], cache)
            cache.pop(pid, None)
        body.__init__(sex, body.parts)
        log(f"  {sex}: the forearms and hands, from the scan {anatomy_limbs.LIMBS[sex]['subject']}")
        arms = made["arms"]
        humeri = {side: next(m[0] for st, m in zip(arms["structures"], arms["meshes"]) if st["node"] == f"TS_humerus_{s}")
                  for side, s in SIDES}
        structures, meshes, facts, fitted = anatomy_limbs.limbs(sex, ct_dir, humeri, body.mesh("skin"))
        for side, s in SIDES:   # each humerus stretched so its elbow sits where the skin's arm bends
            hi = next(i for i, st in enumerate(arms["structures"]) if st["node"] == f"TS_humerus_{s}")
            m = list(arms["meshes"][hi]); m[0] = fitted[side]; arms["meshes"][hi] = type(arms["meshes"][hi])(m)
        arms["structures"] += structures
        arms["meshes"] += [tuple(atlas.simplify(p, f, b)) for p, f, b in meshes]
        arms["name"] = "Arm and hand bones"; RESULTS[sex + " limbs"] = facts
        body.__init__(sex, body.parts)
        log(f"  {sex}: the feet, from the scan {anatomy_feet.FEET[sex]['subject']}")
        legs = {side: np.vstack([body.mesh(f"tibia_{s}")[0], body.mesh(f"fibula_{s}")[0]]) for side, s in SIDES}
        structures, meshes, facts = anatomy_feet.feet(sex, ct_dir, legs, body.mesh("skin"))
        part = body.part("legs")
        part["structures"] += structures
        part["meshes"] += [tuple(atlas.simplify(p, f, b)) for p, f, b in meshes]
        part["name"] = "Thigh, knee, leg and foot"; RESULTS[sex + " feet"] = facts
        body.__init__(sex, body.parts)
    return {"male": male.parts, "female": female.parts}
