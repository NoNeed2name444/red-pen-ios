"""The parts the organ sets lack, made for both bodies of the 3D anatomy atlas,
and the repairs that letting them in needs. Called by tools/anatomy_atlas.py
(its --skull, --ct and --vhct inputs); not run on its own.

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

Sources, pinned below and credited in Resources/Anatomy/SOURCES.md:

- The skull: each body's own head, from the Visible Human Project's CT
  (U.S. National Library of Medicine; the organ sets were made from the same
  man and woman), meshed by tools/anatomy_skull.py, its bones named, and its
  thinnest plates drawn, after NIH 3D 3DPX-020591, "Skull and Eyes - Visible
  Human Male" (kbrowne, NLM 3D: Anatomy; CC BY 4.0), a model segmented from
  the man's CT at far less detail. The model is placed on the man by a
  similarity fit of its eyes and upper teeth to the body's own and carried
  onto the woman's head by a warp; each CT skull is laid on it.
- The rest: CT scans of the TotalSegmentator dataset, v3 (Wasserthal et
  al. 2023; Zenodo, doi 10.5281/zenodo.22688904; CC BY 4.0): s1803, a man of 40, for the
  male body and s1764, a woman of 32, for the female, the pair whose
  skeletons matched the bodies best among those judged; for the man's
  forearms and hands s1880, a man of 37, as s1803's hands lie outside its
  field of view; for the man's elbows s1831, a man of 33, as s1880's
  olecranon lies outside its; and for the man's feet s1767, a man of 56, as
  none of those reaches the toes. The forearm, hand and foot bones are found in the
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
- The skull model is carried onto the woman's head by a warp fitted on the
  head's skin, the upper three neck vertebrae, the eyes and the teeth; her
  own CT skull, laid on it, is kept under her skin the same way.
- The brain both organ sets use (the Allen atlas's) is larger than either
  skull holds; it is scaled down about a point midway between the foot of
  the medulla and the optic chiasm, so the brainstem and the optic nerves
  stay where they meet it, by the least that puts it inside the skull's
  inner table nearly everywhere over the vault; the vault is then eased out
  where it still touches.
- Each side's clavicle and scapula are carried as one rigid piece, not by
  the warp: nothing it is fitted on lies beside the rib cage at shoulder
  height, so there it extrapolates, and stretched or squashed the shoulder
  bones by up to 45% along an axis, differently on each side. Each side
  takes the similarity that best matches the warp over it, both sides one
  scale; then the two are made mirror images of each other about the upper
  thoracic spine's midline (the scans' own sides are, within about 2 mm).
- Each humerus is placed along the skin's arm, its head on the glenoid as
  the scan's sits on its own, and turned so its epicondyles lie across the
  arm, medial toward the body: the scans' arms lie otherwise.
- The rib cage is widened, smoothly around the chest's axis, until the
  lungs, heart, liver, spleen, kidneys and colon sit inside it, but never
  past the skin; each shoulder girdle moves with it, still rigid, its
  sternoclavicular joint carried as the sternum is. Each girdle is then
  settled on the trunk (the scans' shoulders are raised): turned about that
  joint and moved a little, its joint kept as near the sternum as the
  scan's, until it lies under the skin (the clavicle and the acromion just
  under it), clear of the ribs, in the resting posture (the clavicle near
  level, the shoulder blade's medial border near upright), the two sides as
  near mirror images as the trunk allows; the humeri follow.
- Each arm is one chain, its elbow from one scan (tools/anatomy_elbows.py):
  that scan's humerus takes the place of the one placed above, its head's
  centre on that one's, its shaft stretched so the elbow splits the arm as
  the scans' does; the forearm's shaft is stretched to reach the skin's
  wrist, which the arm meets by turning at the shoulder about the humerus's
  long axis and bending at the elbow about its flexion axis (at most 5
  degrees past straight); the forearm is turned so the knuckles lie across
  as the skin's do, and each finger laid along the skin's, joint by joint;
  forearm, hand and fingers are sized to the skin within 15% (fingers 10%).
  One side is the scanned one, the other its mirror image.
- The female organ set's hip bone is the ilium alone, stopping above the
  hip joint. Her scan's whole hip bones take its place: each fitted to her
  ilium (the scan's cut at the same height above its femoral head) and to
  the centre of her femoral head by a similarity, which keeps the scan's
  pelvis whole where a warp fitted on the ilium alone tips the pubis back;
  then the two pubic bodies are brought together at the midline, the rami
  eased smoothly, nothing 7 cm away moving.
- Whatever else came from a scan is pushed out of the organs and bones it
  cuts into (the stomach out of the colon, muscles off the bone), smoothly
  and a few millimetres at a time; the muscles at the scan's own resolution,
  before they are simplified, so a bony point that would come through between
  a simplified muscle's corners (the ischial tuberosity through the gluteus
  maximus) is caught too.

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
from scipy.sparse import coo_matrix, csr_matrix, diags, identity, vstack
from scipy.sparse.linalg import spsolve
from scipy.sparse.csgraph import connected_components
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
             "(TotalSegmentator; scans s1803, s1764, s1880, s1831 and s1767)",
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
             "s1767": "62fa7c94217e7d4cd33905e6914e872141b06bf7a5a6f52fa35e6ff3294fc35f",
             "s1831": "f051382551efada9cc013fc4e6d6fd92779f7d760e9d34d9b5a9a9333b5b165a"}
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


HUMERUS_BUDGET = 1600   # triangles, for each humerus (the elbow's scan's, in the end: tools/anatomy_limbs.py)


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
         pair("humerus", "humerus", "humerus", "bone", HUMERUS_BUDGET, u("0000976"))),
        ("hip-muscles", "Hip muscles", "muscular", [], "pelvis",
         pair("gluteus_maximus", "gluteus_maximus", "gluteus maximus", "muscle", 6000, u("0001370"))
         + pair("gluteus_medius", "gluteus_medius", "gluteus medius", "muscle", 4000, u("0001371"))
         + pair("gluteus_minimus", "gluteus_minimus", "gluteus minimus", "muscle", 2500, u("0008521"))
         + pair("iliopsoas", "iliopsoas", "iliopsoas", "muscle", 4500, u("0001999"))),
        ("back-muscles", "Deep back muscles", "muscular", [], "global",
         pair("autochthon", "deep_back_muscles", "deep back muscles (erector spinae and transversospinales)",
              "muscle", 8000, u("0002462"))),
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


def icp(src, dst, s, R, t, scale, rounds=40):
    """The similarity (s, R, t) laying the points src on the points dst,
    refined from a start by nearest points matched both ways (the nearest
    90% of each way's), so the scale cannot shrink onto part of dst; with
    scale False the scale stays s. Returns it and how far apart the two
    then lie (metres, the mean of both ways)."""
    bt = cKDTree(dst)
    for _ in range(rounds):
        cur = src @ (s * R).T + t
        d1, i1 = bt.query(cur); d2, i2 = cKDTree(cur).query(dst)
        k1, k2 = d1 <= np.percentile(d1, 90), d2 <= np.percentile(d2, 90)
        A, B = np.vstack([src[k1], src[i2[k2]]]), np.vstack([dst[i1[k1]], dst[k2]])
        s1, R, t = umeyama(A, B)
        if scale:
            s = s1
        else:
            t = B.mean(0) - s * R @ A.mean(0)
    cur = src @ (s * R).T + t
    return (s, R, t), float(bt.query(cur)[0].mean() + cKDTree(cur).query(dst)[0].mean()) / 2


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
    cs = np.cos(np.radians(degrees)); out = np.zeros(len(p))
    for i in range(0, len(p), 4000):   # a few thousand points at a time: the weights are points x directions
        K = np.clip((up[i:i + 4000] @ U.T - cs) / (1 - cs), 0, 1); ws = K.sum(1)
        out[i:i + 4000] = np.where(ws > 0, (K * field[None]).sum(1) / np.maximum(ws, 1e-9), 0)
    return up, out


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


def socket(folder, side, frame):
    """Where the body's humeral head goes: the scan's own shoulder joint,
    carried by the similarity that put the scan's scapula in the body
    (girdles(), then widen_cage() and settle_girdles()). In the scan the
    head (the sphere on the humerus's top 12%, as place_humerus finds it)
    sits on its glenoid, 0 to 1.6 mm off it. folder: the body's scan; side:
    "left" or "right"; frame: (scale, rotation, shift), the scan to the
    body. Returns the head's centre and radius, and the glenoid's normal
    (toward the head), in the body."""
    hum, _ = ct_surface(folder, f"humerus_{side}"); scp, _ = ct_surface(folder, f"scapula_{side}")
    c0, ax = _long_axis(hum); t = (hum - c0) @ ax; tree = cKDTree(scp)
    if tree.query(hum[t > np.percentile(t, 94)].mean(0))[0] > tree.query(hum[t < np.percentile(t, 6)].mean(0))[0]:
        t = -t      # the head is the end nearer the scapula
    C, r = _sphere(hum[t > np.percentile(t, 88)])
    gap = np.linalg.norm(scp - C, axis=1) - r; G = scp[gap < gap.min() + 0.006].mean(0)
    k, R, sh = frame
    return k * R @ C + sh, k * r, R @ ((C - G) / np.linalg.norm(C - G))


def seat_humeri(body, folder, shoulders, arms):
    """Each humerus moved so its head's centre is where socket() carries the
    scan's, and re-placed along the skin's arm from there. shoulders, arms:
    their parts, the humeri changed in place. Returns {side: (the glenoid's
    normal, the head's radius)}, for anatomy_limbs to seat its own head."""
    sp, sf = body.mesh("skin"); sockets = {}
    for side, s in SIDES:
        sign = 1 if side == "left" else -1
        hi = next(i for i, st in enumerate(arms["structures"]) if st["node"] == f"TS_humerus_{s}")
        C, r, n = socket(folder, side, shoulders["frames"][side])
        hp, hf = arms["meshes"][hi][:2]; c, ax = _long_axis(hp)
        if ax[1] < 0:
            ax = -ax
        head, _ = _sphere(hp[(hp - c) @ ax > np.percentile((hp - c) @ ax, 88)])
        e, _ = _epicondyles(hp, ax)
        medial = e if e[0] * sign < 0 else -e
        arms["meshes"][hi] = (place_humerus(hp - head + C, sp, sf, sign, medial), hf)
        sockets[side] = (n, r)
        log(f"    {side} humeral head moved {np.linalg.norm(C - head) * 1000:.0f} mm onto its glenoid")
    return sockets


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


def push_out(p, solids, margin=0.0015, sigma=0.010, rounds=10, step=0.003, f=None, alike=False):
    """Move a mesh's points out of the solids: each round, the points inside
    pulled toward the way out, the pull spread smoothly over the mesh, no
    point moving more than `step`. The points inside are pooled per 2 mm
    cell, and the spread reaches 3 sigma.

    Given its triangles `f` (a mesh at the scan's own resolution, its
    points a millimetre apart), each point takes the pulls near it averaged
    by the surface they stand for, in full at the points inside and fading
    as a Gaussian of its distance from the nearest of them: however finely
    the mesh is cut, the move is the same, and it reaches only about sigma
    past what was inside. (Without `f`, a simplified mesh's points, some
    millimetres apart, each pull alike, summed, and a point takes their
    mean once their weight passes one point's.) The round that leaves the
    fewest points inside is kept: a pull can drag a muscle into the next
    bone (the gluteus minimus, between the ilium and the femur). `alike`:
    each round's pulls scaled alike rather than each held to `step`
    (spread_moves)."""
    best = (np.inf, p)
    for done in range(rounds + 1):
        D = np.zeros_like(p); hit = np.zeros(len(p), bool)
        for S in solids:
            m = S.inside(p)
            if m.any():
                D[m] += S.way_out(p[m], margin); hit |= m
        if hit.sum() < best[0]:
            best = (hit.sum(), p)
        if not hit.any() or done == rounds:
            break
        a = vertex_area(p, f)[hit] if f is not None else np.ones(hit.sum())
        p = spread_moves(p, p[hit], D[hit], a, sigma, step, f is not None, alike)
    return best[1]


def spread_moves(p, at, D, a, sigma, step, by_area, alike=False):
    """Move the points p by the moves D asked for at the points `at` (each
    standing for a share `a` of the surface), pooled per 2 mm cell and
    spread smoothly as push_out describes: each point within 3 sigma takes
    their Gaussian-weighted mean, by area (fading from the nearest of them)
    or, without, their sum capped at their mean; no point moves more than
    `step`, each held to it on its own or, `alike`, all scaled alike so the
    farthest moves `step`. Scaled alike the moves stay as smooth as the
    field; held one by one, every point past `step` moves just that, so the
    surface bends along the line where the holding starts, a crease each
    round (the man's rectum, eased off the coccyx 1 mm a round)."""
    _, cell = np.unique(np.floor(at / 0.002).astype(np.int64), axis=0, return_inverse=True)
    cell = cell.reshape(-1); wt = np.bincount(cell, weights=a)
    src = np.stack([np.bincount(cell, weights=a * at[:, k]) for k in range(3)], 1) / wt[:, None]
    d = np.stack([np.bincount(cell, weights=a * D[:, k]) for k in range(3)], 1) / wt[:, None]
    r, _ = cKDTree(src).query(p, distance_upper_bound=3 * sigma); near = np.flatnonzero(np.isfinite(r))
    out = np.zeros((len(near), 3)); ws = np.zeros(len(near))
    for i in range(0, len(near), 1000):
        g = np.exp(-((p[near[i:i + 1000], None] - src[None]) ** 2).sum(-1) / (2 * sigma ** 2)) * wt
        out[i:i + 1000] = g @ d; ws[i:i + 1000] = g.sum(1)
    if by_area:
        mv = out / ws[:, None] * np.exp(-r[near] ** 2 / (2 * sigma ** 2))[:, None]
    else:
        mv = out / np.maximum(ws, 1)[:, None]
    n = np.linalg.norm(mv, axis=1, keepdims=True)
    p = p.copy()
    if alike:
        p[near] += mv * min(1.0, step / max(float(n.max()) if len(n) else 0.0, 1e-9))
    else:
        p[near] += mv * np.minimum(1, step / np.maximum(n, 1e-9))
    return p


def give_way(p, f, bones, margin=0.0015, sigma=0.015, rounds=20, step=0.001, h=0.002, label=None, trace=None,
             finest=None):
    """Move a soft structure's surface (p, f) off the bones that run into
    it, the soft part giving way. Each round, the points of the bones'
    surfaces (sampled about h apart) inside it are found: its winding
    number, its holes capped, over a half (a point beyond a thin tube's cut
    end, near its rim, is not inside, as it would seem by the rim's
    normal). Where they are, the mesh is first cut finer: an organ set's
    mesh is coarse (the man's rectum has triangles four centimetres across,
    one of them through the coccyx's tip), and a triangle can only give way
    as far as its corners move, so within 2 sigma of them every edge longer
    than `finest` (a third of sigma unless given) is split (refine(), each
    new point where the surface the corners' normals describe passes; cut
    flat, a coarse mesh shaded smooth shows its facets' edges). Each run of
    them (points within 4 mm, inside the same structure) then pushes that
    structure one way, from the bones near the run to the soft surface near
    it (within 2 sigma of its middle), each point as far as the structure
    reaches behind it that way, and `margin`: a wall the coccyx's tip has
    pierced slides off it, where each point's own normal (the tip's sides
    and its end) would pull it apart. The pushes spread over the mesh as
    push_out spreads its pull (by area, sigma), each round's scaled alike
    so the farthest moves `step` (spread_moves). Several meshes joined into p, f are told apart by
    `label` (one per triangle); each must be wound out (wound_out). The
    round that leaves the fewest of the bones' points inside is kept;
    `trace`, a list, gets each round's count. Returns the points,
    triangles and labels (new points after p's)."""
    p = np.asarray(p, np.float64); f = np.asarray(f, np.int64)
    label = np.zeros(len(f), np.int64) if label is None else np.asarray(label, np.int64)
    BP = []
    for v, g in bones:
        v, g = np.asarray(v, np.float64), np.asarray(g, np.int64)
        B, T, _ = face_samples(v, g, h)
        BP.append(np.einsum("sk,skc->sc", B, v[g[T]]))
    BP = np.concatenate(BP); bone = cKDTree(BP); reach = 2 * sigma
    finest = sigma / 3 if finest is None else finest
    normal = vertex_normals(p, f)
    best = (np.inf, p, f, label)
    for done in range(rounds + 1):
        B, T, _ = face_samples(p, f, h); t = np.einsum("sk,skc->sc", B, p[f[T]])
        d, _ = cKDTree(t).query(BP, distance_upper_bound=0.010)
        near = np.isfinite(d); inside = np.zeros(len(BP), bool); owner = np.full(len(BP), -1)
        for k in np.unique(label):
            fk = f[label == k]; q = p[np.unique(fk)]; lo, hi = q.min(0), q.max(0)
            c = np.flatnonzero(near & (BP >= lo).all(1) & (BP <= hi).all(1) & ~inside)
            if len(c):
                w = winding_number(BP[c], *capped(p, fk)) > 0.5
                inside[c[w]] = True; owner[c[w]] = k
        if trace is not None:
            trace.append(int(inside.sum()))
        if inside.sum() < best[0]:
            best = (inside.sum(), p, f, label)
        if not inside.any() or done == rounds:
            break
        i = np.flatnonzero(inside)
        for _ in range(8):
            close = np.unique(T[np.isfinite(cKDTree(BP[i]).query(t, distance_upper_bound=reach)[0])])
            p, f, label, normal, cut = refine(p, f, label, close, finest, normal)
            if not cut:
                break
            B, T, _ = face_samples(p, f, h); t = np.einsum("sk,skc->sc", B, p[f[T]])
        D = np.zeros((len(i), 3))
        for k in np.unique(owner[i]):
            mine = i[owner[i] == k]; at = np.flatnonzero(owner[i] == k)
            own = np.flatnonzero(label[T] == k)
            soft = cKDTree(t[own])
            pairs = cKDTree(BP[mine]).query_pairs(0.004, output_type="ndarray")
            _, run = connected_components(coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])),
                                                     shape=(len(mine), len(mine))), directed=False)
            pc, fc = capped(p, f[label == k])
            for r in np.unique(run):
                j = np.flatnonzero(run == r); mid = BP[mine[j]].mean(0)
                there, hard = soft.query_ball_point(mid, reach), bone.query_ball_point(mid, reach)
                way = (t[own[there]].mean(0) if there else mid) - (BP[hard].mean(0) if hard else mid)
                way /= max(np.linalg.norm(way), 1e-12)
                back = behind(BP[mine[j]], -way, pc, fc, 0.025)
                D[at[j]] = way * (np.where(np.isfinite(back), back, d[mine[j]]) + margin)[:, None]
        p = spread_moves(p, BP[i], D, np.full(len(i), h * h), sigma, step, True, alike=True)
    return best[1], best[2], best[3]


def behind(q, way, p, f, most):
    """How far from each point q along `way` the closed mesh p, f is first
    met (within `most`; inf beyond): from a point inside it, how far it
    reaches that way."""
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    lo, hi = q.min(0) - 1e-9 + np.minimum(way * most, 0), q.max(0) + 1e-9 + np.maximum(way * most, 0)
    keep = ((np.maximum(np.maximum(a, b), c) >= lo).all(1) & (np.minimum(np.minimum(a, b), c) <= hi).all(1))
    a, b, c = a[keep], b[keep], c[keep]
    out = np.full(len(q), np.inf)
    if not len(a):
        return out
    e1, e2 = b - a, c - a; pv = np.cross(way, e2); det = (e1 * pv).sum(1)
    ok = np.abs(det) > 1e-15; inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    for s in range(0, len(q), 256):
        T = q[s:s + 256, None] - a[None]; qv = np.cross(T, e1[None])
        uu = (T * pv[None]).sum(-1) * inv; vv = (qv * way).sum(-1) * inv; tt = (qv * e2[None]).sum(-1) * inv
        hit = ok & (uu >= 0) & (vv >= 0) & (uu + vv <= 1) & (tt > 1e-9) & (tt <= most)
        out[s:s + 256] = np.where(hit, tt, np.inf).min(1)
    return out


def refine(p, f, label, tris, longest, normal=None, seam=0.0006):
    """Split the edges longer than `longest` of the triangles `tris`, each
    triangle with a split edge cut by how many it has (one: in two; two: in
    three, by the shorter diagonal; three: in four), so the mesh stays
    whole; each piece keeps its triangle's label and winding. A new point
    lies where the surface its edge's ends' normals describe passes (Phong
    tessellation, Boubekeur and Alexa 2008, shape factor 3/4: the middle
    pulled toward the tangent planes at the ends), its normal their mean;
    without normals, or on a rim (where the mesh is cut open or meets the
    next structure), at the edge's middle. A rim edge is split with the
    rim edge of another structure that meets it (its ends within `seam`),
    so the two stay joined; left whole, a long rim edge would have the
    triangles beside it cut ever thinner. Returns p (the new points after
    it), f, label, the normals (None if not given) and whether anything
    was split."""
    f = np.asarray(f, np.int64)
    E = np.stack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]], 1).reshape(-1, 2)
    key, inv, cnt = np.unique(np.sort(E, 1), axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1, 3)
    want = np.zeros(len(key), bool); want[inv[np.asarray(tris, np.int64)].ravel()] = True
    want &= np.linalg.norm(p[key[:, 0]] - p[key[:, 1]], axis=1) > longest
    rim = np.flatnonzero(cnt == 1)
    if want[rim].any():
        lab = np.zeros(len(key), np.int64); lab[inv.ravel()] = np.repeat(label, 3)
        ends = p[key[rim]]; mids = ends.mean(1); tree = cKDTree(mids)
        for i, j in tree.query_pairs(seam, output_type="ndarray"):
            ei, ej = ends[i], ends[j]
            same = (np.linalg.norm(ei - ej, axis=1).max() <= seam) or (np.linalg.norm(ei - ej[::-1], axis=1).max() <= seam)
            if same and lab[rim[i]] != lab[rim[j]] and (want[rim[i]] or want[rim[j]]):
                want[rim[i]] = want[rim[j]] = True
    if not want.any():
        return p, f, label, normal, False
    new = np.flatnonzero(want); at = np.full(len(key), -1); at[new] = len(p) + np.arange(len(new))
    a, b = key[new, 0], key[new, 1]; mid = (p[a] + p[b]) / 2
    if normal is not None:
        na, nb = normal[a], normal[b]
        tangent = (mid - ((mid - p[a]) * na).sum(1, keepdims=True) * na + mid - ((mid - p[b]) * nb).sum(1, keepdims=True) * nb) / 2
        inner = (cnt[new] > 1)[:, None]
        mid = np.where(inner, mid / 4 + tangent * 3 / 4, mid)
        nm = na + nb; nm /= np.maximum(np.linalg.norm(nm, axis=1, keepdims=True), 1e-12)
        normal = np.concatenate([normal, nm])
    p = np.concatenate([p, mid])
    m = at[inv]; s = (m >= 0).sum(1)
    r = np.where(s == 1, np.argmax(m >= 0, 1), np.where(s == 2, (np.argmin(m >= 0, 1) + 1) % 3, 0))
    o = (np.arange(3)[None] + r[:, None]) % 3; n = np.arange(len(f))[:, None]
    v, m = f[n, o], m[n, o]
    out, lab = [f[s == 0]], [label[s == 0]]
    k = s == 1
    out += [np.stack([v[k, 0], m[k, 0], v[k, 2]], 1), np.stack([m[k, 0], v[k, 1], v[k, 2]], 1)]; lab += [label[k]] * 2
    k = np.flatnonzero(s == 2)
    short = (np.linalg.norm(p[v[k, 0]] - p[m[k, 1]], axis=1) <= np.linalg.norm(p[m[k, 0]] - p[v[k, 2]], axis=1))
    a, b = k[short], k[~short]
    out += [np.stack([m[k, 0], v[k, 1], m[k, 1]], 1),
            np.stack([v[a, 0], m[a, 0], m[a, 1]], 1), np.stack([v[a, 0], m[a, 1], v[a, 2]], 1),
            np.stack([v[b, 0], m[b, 0], v[b, 2]], 1), np.stack([m[b, 0], m[b, 1], v[b, 2]], 1)]
    lab += [label[k], label[a], label[a], label[b], label[b]]
    k = s == 3
    out += [np.stack([v[k, 0], m[k, 0], m[k, 2]], 1), np.stack([m[k, 0], v[k, 1], m[k, 1]], 1),
            np.stack([m[k, 2], m[k, 1], v[k, 2]], 1), np.stack([m[k, 0], m[k, 1], m[k, 2]], 1)]
    lab += [label[k]] * 4
    return p, np.concatenate(out), np.concatenate(lab), normal, True


def fair(p, f, free, normal, cap=1.0):
    """The points `free` of the mesh p, f moved along their normals to where
    the surface through the rest bends least: the least squares of each
    point's offset from the mean of its neighbours (each weighted by its
    closeness, one over the edge's length), over the free points and their
    neighbours, a thin plate's bending (Botsch and Kobbelt 2004, Remeshing
    for multiresolution modeling). Made for the points refine() adds: each
    lies where its own edge's ends' normals put it, so the surfaces on
    either side of an old edge meet at an angle, and a coarse mesh cut finer
    shows its old triangles as creases (the man's rectum); faired, the
    surface through the old points is smooth. A free point on a rim (where
    the mesh is cut open or meets the next structure) stays, so a seam stays
    joined, and none moves more than `cap` times its shortest edge. Returns
    the points."""
    f = np.asarray(f, np.int64); n = len(p)
    E = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    e, cnt = np.unique(E, axis=0, return_counts=True)
    rim = np.zeros(n, bool); rim[e[cnt == 1].ravel()] = True
    free = np.asarray(free, np.int64); free = free[~rim[free]]
    if not len(free):
        return p
    i, j = np.concatenate([e[:, 0], e[:, 1]]), np.concatenate([e[:, 1], e[:, 0]])
    length = np.maximum(np.linalg.norm(p[i] - p[j], axis=1), 1e-9)
    W = csr_matrix((1 / length, (i, j)), shape=(n, n))
    L = (diags(1 / np.maximum(np.asarray(W.sum(1)).ravel(), 1e-12)) @ W - identity(n)).tocsr()
    isfree = np.zeros(n, bool); isfree[free] = True
    rows = L[np.unique(np.concatenate([free, i[isfree[j]]]))]
    A = vstack([rows[:, free] @ diags(normal[free, k]) for k in range(3)]).tocsr()
    b = -(rows @ p).T.ravel()
    M = (A.T @ A).tocsc()
    t = spsolve(M + 1e-6 * M.diagonal().mean() * identity(len(free), format="csc"), A.T @ b)
    short = np.full(n, np.inf); np.minimum.at(short, i, length)
    t = np.clip(t, -cap * short[free], cap * short[free])
    p = p.copy(); p[free] += normal[free] * t[:, None]
    return p


def vertex_normals(p, f):
    """Each point's normal: its triangles' normals, weighted by their areas."""
    n = np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]])
    out = np.zeros_like(p)
    for k in range(3):
        np.add.at(out, f[:, k], n)
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def capped(p, f):
    """The mesh with each hole closed by a fan from its rim's middle, wound as
    the mesh is: an organ set's vessel is a tube cut open where it meets the
    next, and its winding number at a cut end is a half, not 0 or 1."""
    f = np.asarray(f, np.int64)
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    key = np.sort(E, 1); _, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    rim = E[cnt[inv.reshape(-1)] == 1]
    if not len(rim):
        return p, f
    _, comp = connected_components(coo_matrix((np.ones(len(rim)), (rim[:, 0], rim[:, 1])), shape=(len(p), len(p))), directed=False)
    loops = comp[rim[:, 0]]; ids, at = np.unique(loops, return_inverse=True)
    mid = np.stack([np.bincount(at, weights=np.r_[p[rim[:, 0], k]], minlength=len(ids)) for k in range(3)], 1) / np.bincount(at)[:, None]
    fan = np.stack([rim[:, 1], rim[:, 0], len(p) + at], 1)
    return np.concatenate([p, mid]), np.concatenate([f, fan])


def winding_number(q, p, f):
    """The mesh's generalized winding number at the points q: the solid angle
    its triangles fill seen from each, over 4 pi (Jacobson, Kavan and
    Sorkine-Hornung 2013; each triangle's by van Oosterom and Strackee's
    formula): near 1 inside an outward-wound mesh, 0 outside, and in
    between, smoothly, at an open one's mouth."""
    f = np.asarray(f, np.int64); w = np.zeros(len(q))
    for s in range(0, len(q), 256):
        qq = q[s:s + 256]
        for i in range(0, len(f), 2000):
            a, b, c = (p[f[i:i + 2000, j]][None] - qq[:, None] for j in range(3))
            la, lb, lc = (np.linalg.norm(x, axis=2) for x in (a, b, c))
            det = np.einsum("qfk,qfk->qf", a, np.cross(b, c))
            den = (la * lb * lc + np.einsum("qfk,qfk->qf", a, b) * lc + np.einsum("qfk,qfk->qf", b, c) * la
                   + np.einsum("qfk,qfk->qf", c, a) * lb)
            w[s:s + 256] += (2 * np.arctan2(det, den)).sum(1) / (4 * np.pi)
    return w


def wound_out(p, f, eps=0.0003, most=300):
    """Whether a mesh's triangles are wound to face out: just behind and in
    front of up to `most` of them, its winding number is near 1 and 0 when
    they face out, -1 and 0 when in. Unlike its signed volume, this holds
    for an open, thin, curved tube (an organ set's median sacral vein,
    whose volume about its own middle comes out negative while it faces
    out)."""
    f = np.asarray(f, np.int64)
    k = np.arange(len(f)) if len(f) <= most else np.random.default_rng(0).choice(len(f), most, replace=False)
    N = np.cross(p[f[k, 1]] - p[f[k, 0]], p[f[k, 2]] - p[f[k, 0]])
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    c = p[f[k]].mean(1)
    return winding_number(np.concatenate([c - eps * N, c + eps * N]), p, f).mean() >= 0


def face_samples(p, f, h=0.002):
    """Points over each triangle at most about h apart: their barycentric
    weights (n, 3), the triangle each lies on, and the share of the surface
    each stands for."""
    e = np.linalg.norm(p[f[:, [1, 2, 0]]] - p[f], axis=2).max(1)
    ar = np.linalg.norm(np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]]), axis=1) / 2
    n = np.maximum(1, np.ceil(e / h)).astype(int)
    B, T, A = [], [], []
    for k in np.unique(n):
        i, j = np.meshgrid(np.arange(k + 1), np.arange(k + 1), indexing="ij"); keep = i + j <= k
        b = np.stack([i[keep], j[keep], k - i[keep] - j[keep]], 1) / k
        tri = np.flatnonzero(n == k)
        B.append(np.tile(b, (len(tri), 1))); T.append(np.repeat(tri, len(b))); A.append(np.repeat(ar[tri] / len(b), len(b)))
    return np.concatenate(B), np.concatenate(T), np.concatenate(A)


def face_points(p, f, h=0.002):
    """face_samples' points."""
    B, T, _ = face_samples(p, f, h)
    return np.einsum("sk,skc->sc", B, p[f[T]])


def vertex_area(p, f):
    """Each point's share of the surface: a third of its triangles' areas."""
    ar = np.linalg.norm(np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]]), axis=1) / 6
    return np.bincount(f.ravel(), weights=np.repeat(ar, 3), minlength=len(p))


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
# Parts pushed out at the scan's own resolution and simplified after: a bony point
# (the ischial tuberosity) can come through a simplified muscle between its corners,
# where the push, which moves corners, cannot see it.
FINE = {"hip-muscles", "back-muscles"}


def make_room(body, pid, part, cache, simplify=None):
    """Part `pid`'s structures pushed out of its OBSTACLES. A FINE part's are
    pushed at the scan's resolution (part["fine"]: positions, triangles and
    budget) and then simplified to their budgets."""
    fine = part.pop("fine", None)
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
        if fine is not None:
            p, f, budget = fine[i]
        before = np.mean(np.any([S.inside(p) for S in solids], 0))
        q = push_out(p, solids, f=f if fine is not None else None)
        after = np.mean(np.any([S.inside(q) for S in solids], 0))
        if before > 0.01:
            moved.append(f"{s['node']} {before:.0%}->{after:.0%}")
        part["meshes"][i] = tuple(simplify(q, f, budget)) if fine is not None else (q, f)
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


def mirror_motions(left, right, xm):
    """The rigid motions making two pieces mirror images of each other about
    the plane x = xm, each going half way, in turn and in shift, to the
    other's mirror image. left, right: their points. Returns (rotation,
    shift) for the left and for the right, the left's turn to the right's
    mirror image (radians) and how far apart the two then lie (metres)."""
    from scipy.spatial.transform import Rotation
    S = np.diag([-1.0, 1, 1]); m = np.array([2 * xm, 0, 0])
    a, b = sample(left, 6000, 0), sample(right @ S + m, 6000, 1)
    starts = [np.eye(3)] + [_axis_angle(e, np.radians(d)) for e in np.eye(3) for d in (-20, 20)]
    (_, RD, tD), err = min((icp(a, b, 1.0, R0, b.mean(0) - R0 @ a.mean(0), False) for R0 in starts), key=lambda x: x[1])
    half = Rotation.from_matrix(RD).as_rotvec() / 2; Rh = Rotation.from_rotvec(half).as_matrix()
    th = np.linalg.solve(Rh + np.eye(3), tD)   # x -> Rh x + th, done twice, is x -> RD x + tD
    return (Rh, th), (S @ Rh.T @ S, S @ Rh.T @ (m - th) + m), 2 * float(np.linalg.norm(half)), err


def _geodesic(v, f, src):
    """Each point's distance along the surface from the nearest of `src` (-1 where none reaches)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]); wt = np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)
    G = coo_matrix((wt, (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr(); G = G.maximum(G.T)
    d = dijkstra(G, indices=src, min_only=True); d[~np.isfinite(d)] = -1
    return d


def _far_end(v, f, head):
    """A rib's far end: its 5% of points farthest along its surface from its head (its 3% nearest `head`)."""
    v = np.asarray(v, float); f = np.asarray(f); dh = np.linalg.norm(v - head, axis=1)
    g = _geodesic(v, f, np.flatnonzero(dh <= np.percentile(dh, 3))); ok = g >= 0
    return np.flatnonzero(ok & (g >= np.percentile(g[ok], 95)))


def _spread(x, src, dsp, wt, sigma=0.015):
    """A smooth move at the points x from the moves dsp at the points src
    (weights wt): their Gaussian-weighted sum, over the weights' sum where
    that passes 1, so it is their mean near them and fades out away."""
    out = np.zeros((len(x), 3)); ws = np.zeros(len(x))
    for s in range(0, len(x), 500):
        g = np.exp(-((x[s:s + 500, None] - src[None]) ** 2).sum(-1) / (2 * sigma ** 2)) * wt
        out[s:s + 500] = g @ dsp; ws[s:s + 500] = g.sum(1)
    return out / np.maximum(ws, 1.0)[:, None]


def rib_cage(body, folder, w, rows):
    """The ribs and costal cartilages. Warped point by point, a rib takes
    every local stretch and bend of the warp: the reference man's left ribs
    came out up to a fifth longer than his right, and wavy. Each rib is
    instead carried rigidly by the similarity that best matches the warp
    over it, every rib at one scale (the geometric mean of theirs), its head
    (its 3% of points nearest the scan's thoracic vertebrae) where the warp
    puts it; then the two of each pair are turned about their heads to
    mirror images of each other about the thoracic spine's midline, each
    half way to the other's. The costal cartilages take the warp, corrected
    near each rib's far end by the move that takes the warped end onto the
    placed one (spread over 15 mm). Returns the structures, the meshes and
    {heads: each rib's head (None for the cartilages), pairs: (left, right)
    indices, cartilage: the cartilages' index}."""
    loaded = []
    for mask, *_ in rows:
        a, A = load_mask(os.path.join(folder, mask + ".nii.gz")); m = ct_mesh(a, A, sigma=0.8, share=0.05)
        assert m is not None, f"the scan's {mask} is empty"
        loaded.append(m)
    ribs = [i for i, row in enumerate(rows) if row[0].startswith("rib_")]
    ci = next(i for i, row in enumerate(rows) if row[0] == "costal_cartilages")
    level = {i: (rows[i][0].split("_")[1], int(rows[i][0].split("_")[2])) for i in ribs}
    pairs = [(next(i for i in ribs if level[i] == ("left", n)), next(i for i in ribs if level[i] == ("right", n)))
             for n in range(1, 13)]
    vert = cKDTree(np.concatenate([ct_surface(folder, f"vertebrae_T{i}")[0] for i in range(1, 13)]))
    head, ends = {}, {}
    for i in ribs:
        p, f = loaded[i]; dv = vert.query(p)[0]; near = np.flatnonzero(dv <= np.percentile(dv, 3))
        head[i] = p[near].mean(0)
        g = _geodesic(p, f, near); ends[i] = np.flatnonzero(g >= np.percentile(g[g >= 0], 95))
    warped = {i: w(loaded[i][0]) for i in ribs + [ci]}
    sims = {i: umeyama(loaded[i][0], warped[i]) for i in ribs}
    k = float(np.exp(np.mean([np.log(sims[i][0]) for i in ribs])))
    log(f"    ribs: the warp's scale over each, {min(sims[i][0] for i in ribs):.2f} to {max(sims[i][0] for i in ribs):.2f}; "
        f"all at {k:.3f}")
    wh = {i: w(head[i][None])[0] for i in ribs}
    frame = {i: (sims[i][1], wh[i] - k * sims[i][1] @ head[i]) for i in ribs}   # p -> k R p + t
    put = lambda i, p: p @ (k * frame[i][0]).T + frame[i][1]
    xm = midline(body.pts(r"^thoracic_vertebra_([1-9]|1[0-2])$")); turns = []
    for a, b in pairs:
        (Qa, da), (Qb, db), turn, err = mirror_motions(put(a, loaded[a][0]), put(b, loaded[b][0]), xm)
        for i, Q, d in ((a, Qa, da), (b, Qb, db)):
            R, t = frame[i]; R, t = Q @ R, Q @ t + d
            frame[i] = (R, t + wh[i] - (k * R @ head[i] + t))   # the head back where the warp put it
        turns.append(f"{level[a][1]} {np.degrees(turn):.0f}")
    log(f"    ribs: each pair turned to mirror images about x = {xm * 1000:.0f} mm (degrees apart before: {', '.join(turns)})")
    placed = {i: put(i, loaded[i][0]) for i in ribs}
    ez = np.concatenate([loaded[i][0][ends[i]] for i in ribs])
    corr = np.concatenate([placed[i][ends[i]] - warped[i][ends[i]] for i in ribs])
    wz = np.concatenate([np.full(len(ends[i]), 1.0 / len(ends[i])) for i in ribs])
    cartilage = warped[ci] + _spread(loaded[ci][0], ez, corr, wz)
    structures, meshes = [], []
    for i, ((mask, node, label, tissue, budget, uberon), (p, f)) in enumerate(zip(rows, loaded)):
        meshes.append((placed[i] if i in placed else cartilage, f, budget))
        structures.append({"node": node, "label": label, "uberon": uberon, "tissue": tissue, "group": "Ribs and costal cartilages",
                           "inner": False})
    return structures, meshes, {"heads": [wh.get(i) for i in range(len(rows))], "pairs": pairs, "cartilage": ci}


def girdles(body, folder, w, rows):
    """The clavicles and scapulae, each side's two as one rigid piece. The
    warp is fitted on the spine and the organs, so beside the rib cage at
    shoulder height it extrapolates, and would stretch one shoulder blade
    and squash the other. Each side is instead carried by the similarity
    that best matches the warp over it, both sides at one scale (the
    geometric mean of the two similarities'), the turn kept, its
    sternoclavicular joint (the girdle's one joint with the trunk, by the
    sternum, where the warp is held well) where the warp puts it; then the
    two are turned about their joints to mirror images of each other about
    the upper thoracic spine's midline, each half way to the other's mirror
    image (the scans' own left and right are mirror images within about
    2 mm). Returns the structures, the meshes, each side's frame (scale,
    rotation, shift: the scan to the body), and each side's joint in the
    scan with how far it lies from the scan's sternum (metres)."""
    loaded = []
    for mask, *_ in rows:
        a, A = load_mask(os.path.join(folder, mask + ".nii.gz")); m = ct_mesh(a, A, sigma=0.8, share=0.05)
        assert m is not None, f"the scan's {mask} is empty"
        loaded.append(m)
    on = {side: [i for i, row in enumerate(rows) if row[0].endswith("_" + side)] for side, _ in SIDES}
    sims = {}
    for side, idx in on.items():
        p = np.vstack([loaded[i][0] for i in idx]); sims[side] = (p, *umeyama(p, w(p)))
    k = float(np.sqrt(sims["left"][1] * sims["right"][1]))
    # each side's sternoclavicular joint, the girdle's one joint with the trunk: the last 3% of the
    # clavicle's end nearer the other clavicle; the warp carries it well (it lies by the sternum)
    clav = {side: loaded[next(i for i in idx if rows[i][0].startswith("clavicula"))][0] for side, idx in on.items()}
    joint = {}
    for side, other in (("left", "right"), ("right", "left")):
        c, ax = _long_axis(clav[side]); t = (clav[side] - c) @ ax; far = clav[other].mean(0)
        if np.linalg.norm(clav[side][t > 0].mean(0) - far) > np.linalg.norm(clav[side][t < 0].mean(0) - far):
            t = -t
        joint[side] = clav[side][t > np.percentile(t, 97)].mean(0)
    sternum = cKDTree(surface_points(*ct_surface(folder, "sternum"), 0.001))
    joints = {side: (j, float(sternum.query(j)[0])) for side, j in joint.items()}
    wj = {side: w(j[None])[0] for side, j in joint.items()}
    # at a fixed scale the best turn is the same; the joint where the warp puts it
    frames = {side: (k, R, wj[side] - k * R @ joint[side]) for side, (p, s, R, t) in sims.items()}
    xm = midline(body.pts(r"^thoracic_vertebra_[1-7]$"))
    placed = {side: sims[side][0] @ (k * R).T + t for side, (k, R, t) in frames.items()}
    moves = mirror_motions(placed["left"], placed["right"], xm)
    for side, (Q, d) in zip(("left", "right"), moves[:2]):
        k, R, t = frames[side]; R, t = Q @ R, Q @ t + d
        frames[side] = (k, R, t + wj[side] - (k * R @ joint[side] + t))   # the joint back where the warp put it
        log(f"    shoulders: the {side} girdle scaled by {k:.3f} (the warp's {sims[side][1]:.3f}) about its "
            f"sternoclavicular joint, turned {np.degrees(np.arccos(np.clip((np.trace(Q) - 1) / 2, -1, 1))):.1f} degrees about it")
    log(f"    shoulders: the two turned to mirror images about x = {xm * 1000:.0f} mm (the left was "
        f"{np.degrees(moves[2]):.0f} degrees from the right's, its bone within {moves[3] * 1000:.1f} mm of it, matched); "
        f"the joints {np.round(wj['left'] * 1000).astype(int).tolist()} and {np.round(wj['right'] * 1000).astype(int).tolist()} mm")
    structures, meshes = [], []
    for (mask, node, label, tissue, budget, uberon), (p, f) in zip(rows, loaded):
        k, R, t = frames["left" if mask.endswith("_left") else "right"]
        meshes.append((p @ (k * R).T + t, f, budget))
        structures.append({"node": node, "label": label, "uberon": uberon, "tissue": tissue, "group": "Shoulder girdle",
                           "inner": False})
    log(f"    shoulders: in the scan, the sternoclavicular joints lie {joints['left'][1] * 1000:.1f} (left) and "
        f"{joints['right'][1] * 1000:.1f} mm (right) from the sternum")
    return structures, meshes, {"frames": frames, "joints": joints}


def widen_cage(body, ribs, riders=(), joints=(), sternum=(), cap=np.radians(15)):
    """Widen the rib cage until it clears the organs inside it, never
    closer than 6 mm to the skin, every rib staying rigid: turned about its
    head (its joint with the spine) toward where a smooth widening by height
    and angle about the chest's axis would take its points (the best turn,
    by Kabsch), the two of a pair alike as mirror images, at most `cap` in
    all; the costal cartilages follow the ribs' far ends and the sternum the
    cartilages beside it. What rides on the cage (each side's shoulder
    girdle) moves with the widening as one rigid piece: turned as the
    widening would turn its points, at best, and shifted so its joint with
    the cage goes where the widening takes that point (turning a girdle
    about its middle would carry its sternoclavicular joint off the
    sternum). ribs: the ribs' part (rib_cage's), its meshes changed in
    place; riders: lists of [positions, triangles], one per piece, changed
    in place; joints: each piece's joint, a list, changed in place;
    sternum: its [positions, triangles], changed in place. Returns each
    piece's motion (rotation, shift)."""
    from scipy.spatial.transform import Rotation
    organs = [Solid([m for m in body.part(o)["meshes"]]) for o in ("lungs", "liver", "heart", "spleen", "kidneys", "colon")
              if body.part(o) is not None]
    skin = Solid([body.mesh("skin")], h=0.003, close=1)
    ax = chest_axis(body); motions = [(np.eye(3), np.zeros(3)) for _ in riders]
    start = [np.concatenate([m[0] for m in piece]).mean(0) for piece in riders]
    meshes, heads, ci = ribs["meshes"], ribs["heads"], ribs["cartilage"]
    idx = [i for i, h in enumerate(heads) if h is not None]
    ends = {i: _far_end(meshes[i][0], meshes[i][1], heads[i]) for i in idx}
    wz = np.concatenate([np.full(len(ends[i]), 1.0 / len(ends[i])) for i in idx])
    total = {i: np.zeros(3) for i in idx}
    flip = np.array([1.0, -1, -1])   # a turn's mirror image about x: its rotation vector (x, y, z) -> (x, -y, -z)
    for r in range(4):
        cage = [meshes[i] for i in idx + [ci]] + list(sternum)
        pts = np.concatenate([m[0] for m in cage]); need = _exits(pts, ax, organs)
        log(f"    cage, round {r}: {np.mean(need > 0):.1%} of its points inside organs, the deepest {need.max() * 1000:.0f} mm")
        if not (need > 0).any():
            break
        y, th = _cyl(pts, ax); yb = np.arange(y.min() - 0.02, y.max() + 0.02, 0.005); tb = np.linspace(-np.pi, np.pi, 72, endpoint=False)
        grow = _grid_field(y, th, need, yb, tb, "max"); room = _grid_field(y, th, _room(pts, ax, skin), yb, tb, "min")
        def moved(p):
            yy, tt = _cyl(p, ax)
            return p + _outward(p, ax) * np.minimum(grow(yy, tt), room(yy, tt))[:, None]
        before = {i: np.array(meshes[i][0]) for i in idx}
        for a, b in ribs["pairs"]:
            rv = []
            for i in (a, b):
                A = meshes[i][0] - heads[i]; B = moved(meshes[i][0]) - heads[i]
                U, _, Vt = np.linalg.svd(B.T @ A); D = np.eye(3); D[2, 2] = np.sign(np.linalg.det(U @ Vt))
                rv.append(Rotation.from_matrix(U @ D @ Vt).as_rotvec())
            v = (rv[0] + rv[1] * flip) / 2
            for i, vi in ((a, v), (b, v * flip)):
                tot = total[i] + vi
                if np.linalg.norm(tot) > cap:
                    tot = tot / np.linalg.norm(tot) * cap
                step = Rotation.from_rotvec(tot).as_matrix() @ Rotation.from_rotvec(total[i]).as_matrix().T; total[i] = tot
                meshes[i][0] = heads[i] + (meshes[i][0] - heads[i]) @ step.T
        src = np.concatenate([before[i][ends[i]] for i in idx])
        dsp = np.concatenate([meshes[i][0][ends[i]] - before[i][ends[i]] for i in idx])
        cb = np.array(meshes[ci][0]); meshes[ci][0] = cb + _spread(cb, src, dsp, wz)
        if len(sternum):   # the sternum goes with the cartilages beside it, rigidly
            near = cKDTree(np.concatenate([m[0] for m in sternum])).query(cb)[0] < 0.015
            if near.any():
                d = (meshes[ci][0][near] - cb[near]).mean(0)
                for m in sternum:
                    m[0] = m[0] + d
        for i, piece in enumerate(riders):
            p = np.concatenate([m[0] for m in piece]); q = moved(p)
            _, Q, _ = umeyama(p, q); to = moved(joints[i][None])[0]; d = to - Q @ joints[i]
            for m in piece:
                m[0] = m[0] @ Q.T + d
            motions[i] = (Q @ motions[i][0], Q @ motions[i][1] + d); joints[i] = to
    log("    ribs turned about their heads (degrees): " + ", ".join(
        f"{n + 1} {np.degrees(np.linalg.norm(total[a])):.1f}" for n, (a, b) in enumerate(ribs["pairs"])))
    for c, (Q, d) in zip(start, motions):
        log(f"    a piece riding on the cage moved {np.round((Q @ c + d - c) * 1000).astype(int).tolist()} mm, "
            f"turned {np.degrees(np.arccos(np.clip((np.trace(Q) - 1) / 2, -1, 1))):.1f} degrees")
    return motions


# The organs that give way to the rib cage (conform_trunk): everything soft
# inside it, moved as one, so organs that touch stay touching.
SOFT_TRUNK = ("lungs", "heart", "vessels", "airways", "liver", "gallbladder", "biliary-tree", "spleen", "colon",
              "small-intestine", "pancreas", "thymus", "omentum", "kidneys")


def conform_trunk(body, cage, margin=0.002, depth=0.03):
    """The organs inside the rib cage give way to it, the bones staying as
    they are (the organ set's thorax and the scan's ribs are two people's:
    the rigid ribs leave the organs reaching up to a centimetre or so into
    the front of the cage). Wherever soft tissue reaches past `margin`
    inside the cage's inner face (the innermost bone within 25 mm up or down
    and 25 degrees round, which bridges the gaps between ribs), everything
    soft from `depth` inside that face outward is squeezed in, level toward
    the chest's axis, to end there: smooth by height and angle, faded out
    where the cage ends (below the costal margin, above the first ribs),
    one move for every soft structure. What lies outside the cage's outer
    face is left alone. cage: the cage's [positions, triangles]."""
    ax = chest_axis(body)
    P = np.concatenate([surface_points(np.asarray(v, float), np.asarray(f), 0.002) for v, f in cage])
    radius = lambda p: np.linalg.norm((p - ax)[:, [0, 2]], axis=1)
    y, th = _cyl(P, ax); r = radius(P)
    yb = np.arange(y.min() - 0.05, y.max() + 0.05, 0.005); tb = np.linspace(-np.pi, np.pi, 72, endpoint=False)
    inner = _grid_field(y, th, r, yb, tb, "min"); outer = _grid_field(y, th, r, yb, tb, "max")
    cover = _grid_field(y, th, np.ones(len(y)), yb, tb, "max")
    parts = [body.part(o) for o in SOFT_TRUNK if body.part(o) is not None]
    for rnd in range(2):
        soft = [(part, k, np.asarray(v, float)) for part in parts for k, (v, f) in enumerate(part["meshes"])]
        Q = np.concatenate([v for _, _, v in soft]); yq, tq = _cyl(Q, ax); rq = radius(Q)
        Ri, Ro, c = inner(yq, tq), outer(yq, tq), np.clip(cover(yq, tq), 0, 1)
        held = (rq < Ro) & (c > 0.01)
        if not held.any():
            break
        Rs = _grid_field(yq[held], tq[held], rq[held], yb, tb, "max")(yq, tq)
        over = Rs - (Ri - margin); a = Ri - margin - depth
        squeeze = held & (over > 0) & (rq > a)
        log(f"    organs past the cage's inner face, round {rnd}: {np.mean(held & (rq > Ri - margin)):.2%} of their points, "
            f"the farthest {max(0.0, float((rq - Ri + margin)[held].max())) * 1000:.0f} mm")
        if not squeeze.any():
            break
        rn = rq.copy()
        rn[squeeze] = a[squeeze] + (rq[squeeze] - a[squeeze]) * depth / (depth + over[squeeze])
        rn = rq + c * (rn - rq)
        move = _outward(Q, ax) * (rn - rq)[:, None]
        at = 0
        for part, k, v in soft:
            n = len(v); f = part["meshes"][k][1]
            part["meshes"][k] = (v + move[at:at + n], f); at += n
        moved = np.linalg.norm(move, axis=1)
        log(f"    organs squeezed in from the cage: {np.mean(moved > 0.001):.1%} of their points by over 1 mm, "
            f"the most {moved.max() * 1000:.0f} mm")



# How a shoulder girdle rests on the trunk (settle_girdles), the usual resting
# posture: the clavicle's shaft and the acromion this deep under the skin
# (metres: both lie just under it); the shoulder blade at least this clear of
# the ribs and every point of the girdle at least this far under the skin;
# the clavicle near level, rising this much from the sternum to the acromion,
# and the shoulder blade's medial border near upright, about parallel to the
# spine, this far from it (degrees).
REST = dict(clavicle=0.006, acromion=0.008, rib=0.003, skin=0.002, rise=10.0, tilt=5.0)
# How far each may stray at the cost of one unit: those, the girdle's turn
# about its joint (degrees) and its joint's distance to the sternum from the
# scan's own.
SPREAD = dict(clavicle=0.004, acromion=0.005, rib=0.0015, skin=0.001, rise=6.0, tilt=6.0, turn=20.0, gap=0.003)


class _Signed:
    """A signed distance (metres, positive inside the solids, at most `cap`
    either way) on a grid over a box, read back between its points by
    trilinear interpolation: the distance to the nearest of the surfaces'
    points, its sign from the solids."""
    def __init__(self, lo, hi, h, points, solids, cap=0.04):
        self.lo, self.h = lo, h
        n = np.ceil((hi - lo) / h).astype(int) + 1
        grid = np.stack(np.meshgrid(*[lo[i] + h * np.arange(n[i]) for i in range(3)], indexing="ij"), -1).reshape(-1, 3)
        near = points[((points > lo - cap) & (points < hi + cap)).all(1)]
        d = np.minimum(cKDTree(near).query(grid, distance_upper_bound=cap, workers=-1)[0], cap) if len(near) else np.full(len(grid), cap)
        inside = np.zeros(len(grid), bool)
        for S in solids:
            inside |= S.inside(grid)
        self.f = np.where(inside, d, -d).reshape(n)

    def __call__(self, p):
        return ndimage.map_coordinates(self.f, ((p - self.lo) / self.h).T, order=1, mode="nearest")


class _Girdle:
    """One side's clavicle and scapula as one rigid piece, turned about its
    sternoclavicular joint J and shifted: its landmarks (the clavicle's
    medial and lateral ends, the acromion, the scapula's inferior and
    superior angles, the joint) and samples of its points."""
    def __init__(self, clav, scap, sign, xm, J, gap):
        self.sign, self.J, self.gap = sign, J, gap
        lat = (clav[:, 0] - xm) * sign; c, ax = _long_axis(clav); t = (clav - c) @ ax
        lo, hi = np.percentile(t, [10, 90]); self.shaft = sample(clav[(t > lo) & (t < hi)], 200, 0)
        slat = (scap[:, 0] - xm) * sign; med = scap[slat < np.percentile(slat, 8)]
        self.marks = np.vstack([clav[np.argmin(lat)], clav[np.argmax(lat)], scap[slat > np.percentile(slat, 99)].mean(0),
                                scap[np.argmin(scap[:, 1])], med[np.argmax(med[:, 1])], J])
        self.scap = sample(scap, 600, 1); self.all = sample(np.vstack([clav, scap]), 800, 2)

    def moved(self, p, R, d):
        return (p - self.J) @ R.T + self.J + d

    def measure(self, skin, ribs, sternum, R, d):
        cm, cl, ac, inf, sup, J = self.moved(self.marks, R, d)
        dep = skin(self.moved(self.all, R, d)); shaft = np.sort(skin(self.moved(self.shaft, R, d)))
        rd = -ribs(self.moved(self.scap, R, d))
        return dict(out=float(np.mean(dep < 0)), skin=float(np.mean(np.maximum(0, REST["skin"] - dep) ** 2)),
                    clavicle=float(shaft[:10].mean()), acromion=float(skin(ac[None])[0]),
                    inrib=float(np.mean(rd < 0)), rib=float(np.mean(np.maximum(0, REST["rib"] - rd) ** 2)),
                    rib5=float(np.percentile(rd, 5)), gap=float(sternum.query(J)[0]),
                    rise=float(np.degrees(np.arctan2(cl[1] - cm[1], abs(cl[0] - cm[0])))),
                    tilt=float(np.degrees(np.arctan2((inf[0] - sup[0]) * self.sign, sup[1] - inf[1]))))

    def cost(self, mm, turn):
        s = SPREAD
        return (400 * mm["skin"] / s["skin"] ** 2 + 400 * mm["rib"] / s["rib"] ** 2
                + ((mm["clavicle"] - REST["clavicle"]) / s["clavicle"]) ** 2 + ((mm["acromion"] - REST["acromion"]) / s["acromion"]) ** 2
                + ((mm["gap"] - self.gap) / s["gap"]) ** 2 + ((mm["rise"] - REST["rise"]) / s["rise"]) ** 2
                + ((mm["tilt"] - REST["tilt"]) / s["tilt"]) ** 2 + (turn / s["turn"]) ** 2)


def settle_girdles(body, shoulders, arms):
    """Each side's shoulder girdle (clavicle and scapula, one rigid piece)
    settled on the trunk, in place of the scan's raised shoulders: its
    sternoclavicular joint kept at the sternum about as the scan's sits (its
    distance to the sternum near the scan's), the piece turned about that
    joint and moved a little until it lies under the skin (the clavicle's
    shaft and the acromion at their usual depth), clear of the ribs, in the
    resting posture (REST). The two sides stay exact mirror images of each
    other about the upper thoracic spine's midline: first turned half way
    each to the other's mirror image (widening the cage moves each on its
    own), then settled together, one move for the left and its mirror image
    for the right, against both sides' costs (the reference woman's left
    shoulder blade, settled one side at a time, came to rest 33 mm higher
    than her right). Nelder-Mead from a few starts; each humerus's head goes
    with its side. shoulders, arms: their parts, changed in place, the
    shoulders' frames with them."""
    from scipy.optimize import minimize
    from scipy.spatial.transform import Rotation
    at = lambda part, node: next(i for i, st in enumerate(part["structures"]) if st["node"] == node)
    xm = midline(body.pts(r"^thoracic_vertebra_[1-7]$"))
    pieces = {side: [shoulders["meshes"][at(shoulders, f"TS_{n}_{s}")][0] for n in ("clavicle", "scapula")] for side, s in SIDES}
    pre = dict(zip(("left", "right"), mirror_motions(np.vstack(pieces["left"]), np.vstack(pieces["right"]), xm)[:2]))
    for side, s in SIDES:   # mirror images first, each half way
        Q, d = pre[side]
        for n in ("clavicle", "scapula"):
            i = at(shoulders, f"TS_{n}_{s}"); shoulders["meshes"][i][0] = shoulders["meshes"][i][0] @ Q.T + d
        k, Rf, t = shoulders["frames"][side]; shoulders["frames"][side] = (k, Q @ Rf, Q @ t + d)
    pieces = {side: [shoulders["meshes"][at(shoulders, f"TS_{n}_{s}")][0] for n in ("clavicle", "scapula")] for side, s in SIDES}
    allp = np.vstack([p for ps in pieces.values() for p in ps]); lo, hi = allp.min(0) - 0.06, allp.max(0) + 0.06
    sp, sf = body.mesh("skin")
    skin = _Signed(lo, hi, 0.003, surface_points(sp, sf, 0.003), [Solid([(sp, sf)], h=0.003, close=1)])
    cage = [(np.asarray(m[0]), m[1]) for m in body.part("ribs")["meshes"]]
    ribs = _Signed(lo, hi, 0.003, np.vstack([surface_points(*m, 0.002) for m in cage]), [Solid([m]) for m in cage])
    sternum = cKDTree(np.vstack([surface_points(np.asarray(m[0]), m[1], 0.001) for m in body.part("sternum")["meshes"]]))
    g = {}
    for side, s in SIDES:
        (Js, gap), (k, R, t) = shoulders["joints"][side], shoulders["frames"][side]
        g[side] = _Girdle(*pieces[side], 1 if side == "left" else -1, xm, k * R @ Js + t, k * gap)
    S = np.diag([-1.0, 1, 1]); m2 = np.array([g["left"].J[0] + g["right"].J[0], 0, 0])
    unpack = lambda v: (Rotation.from_rotvec(np.radians(v[:3])).as_matrix(), v[3:] / 1000)   # degrees, mm
    mirrored = lambda R, d: (S @ R @ S, S @ d)   # the left's move, as its mirror image moves the right

    def total(v):
        R, d = unpack(v)
        return sum(g[side].cost(g[side].measure(skin, ribs, sternum, *M), np.linalg.norm(v[:3]))
                   for side, M in (("left", (R, d)), ("right", mirrored(R, d))))
    starts = [np.zeros(6)] + [np.r_[0, a, b, 0, 0, 0] for a in (-8, 8) for b in (-8, 8)]
    best = None
    for r in range(2):
        for x0 in (starts if best is None else [best.x]):
            res = minimize(total, x0, method="Nelder-Mead", options=dict(
                initial_simplex=np.vstack([x0, x0 + np.diag([3.0] * 6)]), xatol=0.1, fatol=1e-3, maxfev=900))
            if best is None or res.fun < best.fun:
                best = res
    R0, d0 = unpack(best.x)
    moves = {"left": (R0, d0), "right": mirrored(R0, d0)}
    zero = (np.eye(3), np.zeros(3))
    apart = lambda a, b: np.linalg.norm(g["left"].moved(g["left"].marks, *a) - (g["right"].moved(g["right"].marks, *b) @ S + m2), axis=1).mean()
    for side, s in SIDES:
        gd, sign = g[side], (1 if side == "left" else -1); R, d = moves[side]
        for tag, mm in (("as placed", gd.measure(skin, ribs, sternum, *zero)), ("settled", gd.measure(skin, ribs, sternum, R, d))):
            log(f"    {side} girdle {tag}: joint {mm['gap'] * 1000:.1f} mm from the sternum (the scan's {gd.gap * 1000:.1f}); "
                f"{mm['out']:.1%} outside the skin; clavicle {mm['clavicle'] * 1000:.0f} mm and acromion {mm['acromion'] * 1000:.0f} mm deep; "
                f"{mm['inrib']:.1%} of the scapula inside the ribs; clavicle rising {mm['rise']:.0f} degrees, medial border {mm['tilt']:+.0f}")
        log(f"    {side} girdle turned {np.linalg.norm(best.x[:3]):.1f} degrees about its joint, moved {np.linalg.norm(best.x[3:]):.1f} mm")
        for n in ("clavicle", "scapula"):
            i = at(shoulders, f"TS_{n}_{s}"); shoulders["meshes"][i][0] = gd.moved(shoulders["meshes"][i][0], R, d)
        k, Rf, t = shoulders["frames"][side]; shoulders["frames"][side] = (k, R @ Rf, R @ (t - gd.J) + gd.J + d)
        hi_ = at(arms, f"TS_humerus_{s}"); hp = arms["meshes"][hi_][0]; c, ax = _long_axis(hp)
        if ax[1] < 0:
            ax = -ax
        head, _ = _sphere(hp[(hp - c) @ ax > np.percentile((hp - c) @ ax, 88)])
        e, _ = _epicondyles(hp, ax)
        medial = e if e[0] * sign < 0 else -e
        Q, dq = pre[side]; head_now = head @ Q.T + dq   # the humerus's head goes with its girdle, both moves
        arms["meshes"][hi_][0] = place_humerus(hp - head + gd.moved(head_now[None], R, d)[0], sp, sf, sign, medial)
    log(f"    the two girdles' landmarks from mirror images: {apart(zero, zero) * 1000:.0f} mm as placed, "
        f"{apart(moves['left'], moves['right']) * 1000:.0f} mm settled")


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
    if pid == "shoulders":
        return girdles(body, folder, warp, rows)
    if pid == "ribs":
        return rib_cage(body, folder, warp, rows)
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

def extend(bodies, skull_path, ct_dir, vh_dir, atlas):
    """Add the missing parts to both bodies and size their brains. bodies:
    {"male": parts, "female": parts}, each part a dict with id, name,
    system, structures (without triangles) and meshes [(positions,
    triangles)], as anatomy_atlas.py collected them; changed in place.
    vh_dir: the Visible Human CT's head slices, a folder per body (male/,
    female/; tools/anatomy_skull.py)."""
    got = _sha(skull_path)
    assert got == SKULL_SOURCE["sha256"], f"{skull_path}: SHA-256 {got}, expected {SKULL_SOURCE['sha256']}"
    import sys
    import anatomy_limbs, anatomy_feet, anatomy_elbows, anatomy_skull
    for sex in ("male", "female"):
        folder = os.path.join(vh_dir, sex); got = anatomy_skull.digest(folder, anatomy_skull.files_used(sex))
        assert anatomy_skull.VH_SHA256[sex] in (None, got), f"{folder}: files digest {got}, expected {anatomy_skull.VH_SHA256[sex]}"
        anatomy_skull.VH_SHA256[sex] = got
    need = {}
    for sex, subject in SUBJECT.items():
        need.setdefault(subject, set()).update(masks_used(sex))
    for sex in ("male", "female"):   # the forearms and hands: the CT itself, and the bones taken out before them
        need.setdefault(anatomy_limbs.LIMBS[sex]["subject"], set()).update(anatomy_limbs.files_used(sex))
    for sex in ("male", "female"):   # the elbows: the CT, the humerus, and the bones set aside around it
        need.setdefault(anatomy_elbows.ELBOWS[sex]["subject"], set()).update(anatomy_elbows.files_used(sex))
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
    skin_f = head_skin(female); cf = female.pts(part="brain").mean(0)
    def marks(b):
        return [centroid(*b.mesh(n)) for n in ("sclera_L", "sclera_R", "set_of_upper_jaw_teeth", "set_of_lower_jaw_teeth")]
    head = [("skin", sample(skin_m[0][np.unique(skin_m[1])], 3000, 0), sample(skin_f[0][np.unique(skin_f[1])], 12000, 1), 1.0, "surface")]
    head += [(f"C{i}", sample(male.mesh(f"cervical_vertebra_{i}")[0], 200, 0), sample(female.mesh(f"cervical_vertebra_{i}")[0], 800, 1), 1.0, "surface")
             for i in (1, 2, 3)]
    head += [(n, a[None], b[None], 4.0, "centre") for n, a, b in zip(("eye L", "eye R", "upper teeth", "lower teeth"), marks(male), marks(female))]
    log("  her head, from his")
    W = register(head, rounds=(3e-2, 1e-2, 3e-3, 1e-3))
    model = {"male": skull, "female": {k: (W(v), f) for k, (v, f) in skull.items()}}
    for body in (male, female):   # each body's own skull, from its CT, laid on the model
        log(f"  {body.sex}: the skull from the body's own CT")
        model[body.sex] = anatomy_skull.ct_skull(body.sex, os.path.join(vh_dir, body.sex), model[body.sex], body,
                                                 atlas.simplify, sys.modules[__name__])
    skull_m, skull_f = tuck(model["male"], cm, skin_m), tuck(model["female"], cf, skin_f)
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
            structures, meshes, *extra = ct_part(body, sex, folder, ws[region], pid, name, system, rows)
            part = {"id": pid, "name": name, "system": system, "structures": structures,
                    "meshes": [list(atlas.simplify(p, f, b)) for p, f, b in meshes]}
            if pid in FINE:   # kept at the scan's resolution until pushed out (make_room)
                part["fine"] = meshes
            if extra:   # the shoulders': each side's frame and joint; the ribs': their heads and pairs
                part.update(extra[0])
            place(body.parts, part, before); made[pid] = part
            log(f"    {pid}: {len(structures)} structures")
        if hips:
            put_hips(body, hips, atlas)
            log("    pelvis: the whole hip bones in place of the ilia")
        body.__init__(sex, body.parts)
        girdle = made["shoulders"]
        pieces = [[m for st, m in zip(girdle["structures"], girdle["meshes"]) if st["node"].endswith("_" + s)] for _, s in SIDES]
        joints = [girdle["frames"][side][0] * girdle["frames"][side][1] @ girdle["joints"][side][0] + girdle["frames"][side][2]
                  for side, _ in SIDES]
        motions = widen_cage(body, made["ribs"], pieces, joints, made["sternum"]["meshes"] if "sternum" in made else ())
        for (side, _), (Q, d) in zip(SIDES, motions):
            k, R, t = girdle["frames"][side]; girdle["frames"][side] = (k, Q @ R, Q @ t + d)
        settle_girdles(body, girdle, made["arms"])
        conform_trunk(body, made["ribs"]["meshes"] + list(body.part("sternum")["meshes"]))
        for key in ("heads", "pairs", "cartilage"):
            del made["ribs"][key]
        for part in made.values():
            part["meshes"] = [tuple(m) for m in part["meshes"]]
        body.__init__(sex, body.parts)
        cache = {}
        for pid in ("oesophagus", "stomach", "thyroid", "adrenals", "arms", "hip-muscles", "back-muscles"):
            make_room(body, pid, made[pid], cache, atlas.simplify)
            cache.pop(pid, None)
        body.__init__(sex, body.parts)
        log(f"  {sex}: the forearms and hands, from the scan {anatomy_limbs.LIMBS[sex]['subject']}")
        arms = made["arms"]
        sockets = seat_humeri(body, folder, made["shoulders"], arms)
        del made["shoulders"]["frames"], made["shoulders"]["joints"]
        humeri = {side: next(m[0] for st, m in zip(arms["structures"], arms["meshes"]) if st["node"] == f"TS_humerus_{s}")
                  for side, s in SIDES}
        structures, meshes, facts, humerus = anatomy_limbs.limbs(sex, ct_dir, humeri, body.mesh("skin"), sockets)
        for side, s in SIDES:   # each humerus the elbow's scan's, posed with the forearm (its budget the row's)
            hi = next(i for i, st in enumerate(arms["structures"]) if st["node"] == f"TS_humerus_{s}")
            arms["meshes"][hi] = tuple(atlas.simplify(*humerus[side], HUMERUS_BUDGET))
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
