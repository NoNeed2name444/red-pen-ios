#!/usr/bin/env python3
"""More of the atlas's skeletal muscles, made for both bodies. Batch 1: the head and neck.

    remake(folder, quiet=False)     adds them to <folder>'s atlas (anatomy.json and its part files)
    anatomy_muscles_more.py <atlas folder>

Run before the fibres (tools/anatomy_fibres.py lays their bundles, by its RULES). Each muscle made carries
"made": MARK in the manifest, so a second run leaves it as it is and makes only what is missing (the woman's
thyrohyoid, for one, waits for her hyoid). Adds to each body:

    jaw-muscles    Muscles of mastication: masseter, temporalis, lateral and medial pterygoid
    neck-muscles   Muscles of the neck: digastric, sternocleidomastoid, the anterior, middle and posterior
                   scalenes, levator scapulae, sternothyroid, thyrohyoid, longus colli with longus capitis

each on both sides.

Source: TotalSegmentator's head_muscles and headneck_muscles tasks (TotalSegmentator 2.18.0, Wasserthal et al.;
the code and these tasks' weights Apache-2.0, https://github.com/wasserth/TotalSegmentator), run on the CT scans
s1803 (a man of 40) and s1764 (a woman of 32) of the TotalSegmentator dataset v3 (CC BY 4.0; Zenodo, doi
10.5281/zenodo.22688904), the scans tools/anatomy_gaps.py fits each body's ribs, shoulders and hip muscles from.
The masks are pinned by SHA-256 (MASKS_SHA256). Where each muscle arises and inserts: Gray, Anatomy of the Human
Body, 20th ed. (1918), as GRAYS quotes it.

How, for each body:

1. A warp from the scan to the body, a thin-plate spline (anatomy_gaps.register) fitted on what both have in the
   head and neck: the skull with the mandible, C1 to T4, the clavicles, scapulae and first three ribs, the
   sternum, the trachea, the thyroid gland and the top of the oesophagus.
2. Each muscle's mask meshed (anatomy_gaps.ct_mesh), carried by the warp and brought down to a working mesh
   (edges about WORK at the median).
3. Its attachments seated, as Gray's gives them (MUSCLES: the bones each arises from and inserts on): where its
   surface faces one of those bones within REACH and touched the scan's bone there (within TOUCH), it is drawn
   to GAP off the bone, the pull spread smoothly over the muscle (a Gaussian of SIGMA).
4. Out of every bone and cartilage (its surface sampled every half millimetre); then out of what was placed
   before it, deep to superficial (ORDER), of the atlas's own muscles (the deep back muscles, the larynx's), of
   the glands, the airways, the oesophagus and the vessels, and inside the skin; out of the bone again last,
   so the bone wins.
5. Brought down to its triangles as tools/anatomy_fibres.py would leave it: edges about EVEN (4.3 mm) at the
   median under BIG (50 cm2); above, CAP (625) or one each PER_TRIANGLE (15 mm2), whichever is more; out of
   the bone once more.
"""
import hashlib, json, os, re, sys, time

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
S = "/tmp/claude-0/-home-user/da8cf5cf-b385-5646-a716-c25fc72fb88a/scratchpad"
CT = os.environ.get("MORE_CT", os.path.join(S, "ts", "subj"))           # the dataset's own masks, per scan
SEG = os.environ.get("MORE_SEG", os.path.join(S, "tsrun", "out"))      # TotalSegmentator's muscle masks: <scan>_<task>
SUBJECT = {"male": "s1803", "female": "s1764"}
MARK = "ct-muscles-1"

WORK = 0.0018             # the working mesh's median edge
REACH, TOUCH, GAP = 0.006, 0.0025, 0.0005
SIGMA, STEP = 0.005, 0.003
MARGIN = 0.0004           # off what is not bone
SHALLOW = 0.0008          # inside a surface: within 60 degrees of its inward normal, or nearer it than this
FAR_IN = 0.002            # farther in than this, only if no sample about as near faces the point (see query())
SKIN_IN = 0.0015          # under the skin by at least this
EVEN, BIG, PER_TRIANGLE, MOST = 0.0043, 50e-4, 15e-6, 8000
CAP = int(np.ceil(BIG / (np.sqrt(3) / 4 * EVEN ** 2)))   # 625: BIG's triangles at EVEN, the least a BIG one keeps
FLOOR = 400               # triangles: the smallest muscles keep their shape

PARTS = {"jaw-muscles": "Muscles of mastication", "neck-muscles": "Muscles of the neck"}
# (task, mask, node, label, UBERON, part, group, origin's bones, insertion's bones): bones as regular expressions on
# node names without their source's prefix, a bone of the muscle's own side or of the midline
MUSCLES = [
    ("head_muscles", "masseter", "masseter", "masseter", "0001597", "jaw-muscles", "Muscles of mastication",
     r"^(zygomatic_bone|maxilla|temporal_bone)_", r"^mandible$"),
    ("head_muscles", "temporalis", "temporalis", "temporalis", "0001598", "jaw-muscles", "Muscles of mastication",
     r"^(temporal_bone_|parietal_bone_|frontal_bone$|sphenoid_bone$)", r"^mandible$"),
    ("head_muscles", "lateral_pterygoid", "lateral_pterygoid", "lateral pterygoid", "0006719", "jaw-muscles",
     "Muscles of mastication", r"^sphenoid_bone$", r"^mandible$"),
    ("head_muscles", "medial_pterygoid", "medial_pterygoid", "medial pterygoid", "0006718", "jaw-muscles",
     "Muscles of mastication", r"^(sphenoid_bone$|palatine_bone_|maxilla_)", r"^mandible$"),
    ("head_muscles", "digastric", "digastric", "digastric", "0001562", "neck-muscles", "Suprahyoid muscles",
     r"^temporal_bone_", r"^mandible$"),
    ("headneck_muscles", "sternocleidomastoid", "sternocleidomastoid", "sternocleidomastoid", "0001128",
     "neck-muscles", "Lateral cervical muscles", r"^(sternum|manubrium|clavicle_)", r"^(temporal_bone_|occipital_bone$)"),
    ("headneck_muscles", "anterior_scalene", "scalenus_anterior", "scalenus anterior", "0008622", "neck-muscles",
     "Lateral vertebral muscles", r"^cervical_vertebra_[3-6]$", r"^rib_1_"),
    ("headneck_muscles", "middle_scalene", "scalenus_medius", "scalenus medius", "0001122", "neck-muscles",
     "Lateral vertebral muscles", r"^cervical_vertebra_[1-7]$", r"^rib_1_"),
    ("headneck_muscles", "posterior_scalene", "scalenus_posterior", "scalenus posterior", "0001123", "neck-muscles",
     "Lateral vertebral muscles", r"^cervical_vertebra_[4-7]$", r"^rib_2_"),
    ("headneck_muscles", "levator_scapulae", "levator_scapulae", "levator scapulae", "0005461", "neck-muscles",
     "Muscles connecting the upper limb to the vertebral column", r"^cervical_vertebra_[1-4]$", r"^scapula_"),
    ("headneck_muscles", "sterno_thyroid", "sternothyroid", "sternothyroid", "0001109", "neck-muscles",
     "Infrahyoid muscles", r"^(sternum|manubrium|rib_1_)", r"^thyroid_cartilage$"),
    ("headneck_muscles", "thyrohyoid", "thyrohyoid", "thyrohyoid", "0001110", "neck-muscles", "Infrahyoid muscles",
     r"^thyroid_cartilage$", r"^hyoid$"),
    (None, "sternohyoid", "sternohyoid", "sternohyoid", "0001107", "neck-muscles", "Infrahyoid muscles",
     r"^(sternum|manubrium|clavicle_)", r"^hyoid(_bone)?$"),
    (None, "omohyoid", "omohyoid", "omohyoid", "0001108", "neck-muscles", "Infrahyoid muscles",
     r"^scapula_", r"^hyoid(_bone)?$"),
    (None, "geniohyoid", "geniohyoid", "geniohyoid", "0001565", "neck-muscles", "Suprahyoid muscles",
     r"^mandible$", r"^hyoid(_bone)?$"),
    (None, "mylohyoid", "mylohyoid", "mylohyoid", "0001564", "neck-muscles", "Suprahyoid muscles",
     r"^mandible$", r"^hyoid(_bone)?$"),
    (None, "stylohyoid", "stylohyoid", "stylohyoid", "0008712", "neck-muscles", "Suprahyoid muscles",
     r"^temporal_bone_", r"^hyoid(_bone)?$"),
    ("headneck_muscles", "prevertebral", "longus_colli_and_capitis", "longus colli and longus capitis", "0017647",
     "neck-muscles", "Anterior vertebral muscles", r"^(thoracic_vertebra_[1-3]|cervical_vertebra_[3-7])$",
     r"^(occipital_bone|cervical_vertebra_[1-4])$"),
]
# deep to superficial: each muscle keeps out of those before it
ORDER = ["prevertebral", "middle_scalene", "posterior_scalene", "anterior_scalene", "levator_scapulae",
         "lateral_pterygoid", "medial_pterygoid", "temporalis", "masseter", "geniohyoid", "mylohyoid", "digastric",
         "stylohyoid", "thyrohyoid", "sterno_thyroid", "sternohyoid", "omohyoid", "sternocleidomastoid"]
# Gray's Anatomy (1918), its words: (section, arises, inserted)
GRAYS = {
    "masseter": ("IV.4c, The Muscles of Mastication",
                 "the superficial portion from the zygomatic process of the maxilla and the anterior two-thirds of the "
                 "inferior border of the zygomatic arch; the deep portion from the posterior third of the lower border and "
                 "the whole of the medial surface of the zygomatic arch",
                 "the angle and lower half of the lateral surface of the ramus of the mandible; the deep portion into the "
                 "upper half of the ramus and the lateral surface of the coronoid process"),
    "temporalis": ("IV.4c, The Muscles of Mastication",
                   "the whole of the temporal fossa (except the part formed by the zygomatic bone) and the deep surface "
                   "of the temporal fascia",
                   "the medial surface, apex and anterior border of the coronoid process and the anterior border of "
                   "the ramus of the mandible nearly as far forward as the last molar tooth"),
    "lateral_pterygoid": ("IV.4c, The Muscles of Mastication",
                          "by two heads: an upper from the lower part of the lateral surface of the great wing of the "
                          "sphenoid and the infratemporal crest; a lower from the lateral surface of the lateral "
                          "pterygoid plate",
                          "a depression in front of the neck of the condyle of the mandible, and the front margin of "
                          "the articular disk of the temporomandibular joint"),
    "medial_pterygoid": ("IV.4c, The Muscles of Mastication",
                         "the medial surface of the lateral pterygoid plate and the grooved surface of the pyramidal "
                         "process of the palatine bone; a second slip from the lateral surfaces of the pyramidal "
                         "process of the palatine and the tuberosity of the maxilla",
                         "the lower and back part of the medial surface of the ramus and angle of the mandible, as high "
                         "as the mandibular foramen"),
    "digastric": ("IV.5b, The Suprahyoid Muscles",
                  "the posterior belly from the mastoid notch of the temporal bone; the anterior belly from a "
                  "depression on the inner side of the lower border of the mandible, close to the symphysis",
                  "the two bellies end in an intermediate tendon, held to the body and greater cornu of the hyoid "
                  "bone by a fibrous loop"),
    "sternocleidomastoid": ("IV.5a, The Lateral Cervical Muscles",
                            "the sternal head from the upper part of the anterior surface of the manubrium sterni; the "
                            "clavicular head from the superior border and anterior surface of the medial third of the "
                            "clavicle",
                            "the lateral surface of the mastoid process, from its apex to its superior border, and the "
                            "lateral half of the superior nuchal line of the occipital bone"),
    "anterior_scalene": ("IV.5e, The Lateral Vertebral Muscles",
                         "the anterior tubercles of the transverse processes of the third, fourth, fifth and sixth "
                         "cervical vertebrae",
                         "the scalene tubercle on the inner border of the first rib, and the ridge on its upper surface "
                         "in front of the subclavian groove"),
    "middle_scalene": ("IV.5e, The Lateral Vertebral Muscles",
                       "the posterior tubercles of the transverse processes of the lower six cervical vertebrae",
                       "the upper surface of the first rib, between the tubercle and the subclavian groove"),
    "posterior_scalene": ("IV.5e, The Lateral Vertebral Muscles",
                          "the posterior tubercles of the transverse processes of the lower two or three cervical "
                          "vertebrae",
                          "the outer surface of the second rib, behind the attachment of the serratus anterior"),
    "levator_scapulae": ("IV.7a, Muscles Connecting the Upper Extremity to the Vertebral Column",
                         "the transverse processes of the atlas and axis and the posterior tubercles of the transverse "
                         "processes of the third and fourth cervical vertebrae",
                         "the vertebral border of the scapula, between the medial angle and the root of the spine"),
    "sternohyoid": ("IV.5c, The Infrahyoid Muscles",
                    "the posterior surface of the medial end of the clavicle, the posterior sternoclavicular "
                    "ligament, and the upper and posterior part of the manubrium sterni",
                    "the lower border of the body of the hyoid bone"),
    "omohyoid": ("IV.5c, The Infrahyoid Muscles",
                 "the inferior belly from the upper border of the scapula, beside the scapular notch",
                 "the superior belly into the lower border of the body of the hyoid bone, lateral to the sternohyoid; "
                 "the two bellies are joined by a tendon behind the sternocleidomastoid, held down by a band of fascia"),
    "geniohyoid": ("IV.5b, The Suprahyoid Muscles",
                   "the inferior mental spine on the back of the symphysis of the mandible",
                   "the anterior surface of the body of the hyoid bone"),
    "mylohyoid": ("IV.5b, The Suprahyoid Muscles",
                  "the whole length of the mylohyoid line of the mandible, from the symphysis to the last molar tooth",
                  "the hinder fibres into the body of the hyoid bone; the middle and fore fibres into a median "
                  "raphe that runs from the symphysis to the hyoid bone"),
    "stylohyoid": ("IV.5b, The Suprahyoid Muscles",
                   "the back and lateral surface of the styloid process, near its base",
                   "the body of the hyoid bone, at its junction with the greater cornu"),
    "sterno_thyroid": ("IV.5c, The Infrahyoid Muscles",
                       "the posterior surface of the manubrium sterni, below the origin of the sternohyoid, and the "
                       "edge of the cartilage of the first rib",
                       "the oblique line on the lamina of the thyroid cartilage"),
    "thyrohyoid": ("IV.5c, The Infrahyoid Muscles",
                   "the oblique line on the lamina of the thyroid cartilage",
                   "the lower border of the greater cornu of the hyoid bone"),
    "prevertebral": ("IV.5d, The Anterior Vertebral Muscles",
                     "the longus colli from the bodies of the upper three thoracic and lower three cervical vertebrae "
                     "and the anterior tubercles of the third to fifth cervical transverse processes; the longus "
                     "capitis by four slips from the anterior tubercles of the third to sixth",
                     "the longus colli into the anterior tubercle of the atlas, the bodies of the second to fourth "
                     "cervical vertebrae and the anterior tubercles of the fifth and sixth transverse processes; the "
                     "longus capitis into the inferior surface of the basilar part of the occipital bone"),
}
# SHA-256 of the lines "<task>/<file> <its SHA-256>\n" for the muscle masks used, in name order, per scan; and of
# the dataset masks the warp pairs on (anatomy_gaps.digest)
MASKS_SHA256 = {"s1803": "9947b58a0b1dfb5bb3b35cb06f5fdbe9c15390a8702495d757ddd8cf5e1da758",
                "s1764": "e27fd62bcb1775636cdcd0dbf33c036013155fbab33570b5192bcd42b0f748f2"}
PAIRED_SHA256 = {}
SIDES = (("left", "L"), ("right", "R"))
PREFIX = re.compile(r"^(VH_[MF]_|TS_|NLM_)")


def log(*a):
    print(*a, flush=True)


def short(node):
    return PREFIX.sub("", node)


def side_of(node):
    m = re.search(r"_([LR])$", node)
    return m.group(1) if m else None


def _sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def mask_digest(scan):
    names = sorted(f"{task}/{mask}_{side}.nii.gz" for task, mask, *_ in MUSCLES if task for side, _ in SIDES)
    lines = "".join(f"{n} {_sha(os.path.join(SEG, f'{scan}_{n}'))}\n" for n in names)
    return hashlib.sha256(lines.encode()).hexdigest()


# MARK: meshes

def area(v, f):
    return float(np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1).sum() / 2)


def vertex_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    out = np.zeros_like(v)
    for k in range(3):
        np.add.at(out, f[:, k], n)
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def simplify(v, f, target):
    """Brought down to about `target` triangles (quadric decimation, gentle first), one surface still."""
    import fast_simplification
    for agg in (3, 5, 7):
        if len(f) <= target * 1.1:
            break
        q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32),
                                            target_reduction=1 - target / len(f), agg=agg)
        if len(g) == 0 or len(g) >= len(f):
            continue
        used = np.unique(g)
        remap = np.full(len(q), -1, np.int64)
        remap[used] = np.arange(len(used))
        v, f = q[used].astype(np.float64), remap[g].astype(np.int64)
    return v, f


def samples(v, f, h):
    """Points over the surface, about h apart (a regular grid on each triangle), with its outward normal there."""
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    n = np.cross(b - a, c - a)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-15)
    L = np.maximum(np.maximum(np.linalg.norm(b - a, axis=1), np.linalg.norm(c - a, axis=1)), np.linalg.norm(c - b, axis=1))
    k = np.clip(np.ceil(L / h).astype(int), 1, 64)
    P, N = [], []
    for kk in np.unique(k):
        sel = np.flatnonzero(k == kk)
        i, j = np.meshgrid(np.arange(kk + 1), np.arange(kk + 1))
        m = i + j <= kk
        s, t = (i[m] / kk)[None, :, None], (j[m] / kk)[None, :, None]
        P.append((a[sel, None] * (1 - s - t) + b[sel, None] * s + c[sel, None] * t).reshape(-1, 3))
        N.append(np.repeat(n[sel], m.sum(), axis=0))
    return np.concatenate(P), np.concatenate(N)


def signed_volume(v, f):
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6)


def wound_in(v, f):
    """Whether a mesh's triangles face in: its volume about its own middle negative (about the atlas's origin, an
    open one's volume is anything: the skull's bones, open at their sutures, came out negative for half of them),
    or, too thin to tell (under 0.5 cm3: the palatine bones), its winding number just behind and before them."""
    vol = signed_volume(v - v.mean(0), f)
    if abs(vol) >= 0.5e-6:
        return vol < 0
    from anatomy_gaps import wound_out
    return not wound_out(v, f)


def outward_samples(v, f, h):
    """samples(), their normals turned out if the mesh is wound inward."""
    p, n = samples(v, f, h)
    return (p, -n) if wound_in(v, f) else (p, n)


class Surface:
    """Meshes as dense samples with their outward normals (or such samples, (P, N) pairs, cropped to a box
    lo..hi): which points lie inside, and the way out."""
    def __init__(self, meshes=(), h=0.0006, pieces=(), box=None):
        P, N = [], []
        for v, f in meshes:
            if len(f):
                p, n = outward_samples(v, f, h)
                P.append(p); N.append(n)
        for p, n in pieces:
            P.append(p); N.append(n)
        self.P = np.concatenate(P) if P else np.zeros((0, 3))
        self.N = np.concatenate(N) if N else np.zeros((0, 3))
        if box is not None and len(self.P):
            keep = np.all((self.P >= box[0]) & (self.P <= box[1]), axis=1)
            self.P, self.N = self.P[keep], self.N[keep]
        self.tree = cKDTree(self.P) if len(self.P) else None

    def query(self, X, reach=0.02):
        """(inside, distance, nearest sample) for the points X: inside where the nearest sample, within reach,
        has the point within 60 degrees of its inward normal, or faces away from it nearer than SHALLOW. (Facing
        away alone is not enough: beyond the tip of a thin process or a ridge, a point's nearest sample can face
        away from it while it is outside; such points, up to 15 mm off a vertebra, dragged the sternocleidomastoid
        onto the spine.)"""
        if self.tree is None:
            return np.zeros(len(X), bool), np.full(len(X), np.inf), np.zeros(len(X), int)
        d, i = self.tree.query(X, distance_upper_bound=reach, workers=2)
        ok = np.isfinite(d)
        i = np.where(ok, i, 0)
        dot = np.einsum("ij,ij->i", X - self.P[i], self.N[i])
        inside = ok & ((dot < -0.5 * d) | ((dot < 0) & (d < SHALLOW)))
        far = np.flatnonzero(inside & (d > FAR_IN))
        if len(far):        # well off it, a point is outside if any sample about as near faces it: an edge's
            dk, ik = self.tree.query(X[far], k=min(32, len(self.P)), distance_upper_bound=reach, workers=2)
            near = np.isfinite(dk) & (dk <= dk[:, :1] * 1.2 + 0.0003)      # samples lie on both its faces, and
            ik = np.where(near, ik, 0)                                      # the nearest may be the far one's
            dotk = np.einsum("ikj,ikj->ik", X[far][:, None, :] - self.P[ik], self.N[ik])
            inside[far[(near & (dotk > 0.3 * dk)).any(1)]] = False
        return inside, d, i


def spread(v, hit, D, sigma, cap):
    """Moves D asked for at the vertices `hit`, smoothed through space by a Gaussian of sigma and read back at
    every vertex: their weighted mean wherever half the weight reaches that reaches a vertex in their midst,
    fading beyond; no vertex moving more than cap. Through space and not along the surface, so the two faces of
    a thin muscle move together and it keeps its thickness (moved face by face, the temporalis was pressed
    through itself and the neck's straps crumpled), and on a grid, so a large muscle costs no more than a small."""
    from scipy import ndimage
    if not hit.any():
        return v
    step = sigma / 2
    lo = v.min(0) - 3 * sigma
    n = np.ceil((v.max(0) + 3 * sigma - lo) / step).astype(int) + 2
    acc = np.zeros((*n, 4))
    c = (v - lo) / step
    at = np.rint(c[hit]).astype(int)
    np.add.at(acc, (at[:, 0], at[:, 1], at[:, 2]), np.concatenate([D, np.ones((len(D), 1))], 1))
    got = np.stack([ndimage.map_coordinates(ndimage.gaussian_filter(acc[..., k], 2.0, mode="constant", truncate=3.0),
                                            c.T, order=1) for k in range(4)], 1)
    mv = got[:, :3] / np.maximum(got[:, 3], 0.5 * np.median(got[hit, 3]))[:, None]
    size = np.linalg.norm(mv, axis=1, keepdims=True)
    return v + mv * np.minimum(1, cap / np.maximum(size, 1e-12))


def nudge(v, hit, D, sigma, cap):
    """Moves D asked for at the vertices `hit`, spread to the vertices within 3 sigma of them only (each their
    weighted mean once their weight passes one vertex's): for the last fractions of a millimetre, where one face
    of a muscle has to give and the other must not follow it into what lies beyond."""
    import scipy.sparse as sp
    src = v[hit]
    if not len(src):
        return v
    pairs = cKDTree(v).sparse_distance_matrix(cKDTree(src), 3 * sigma, output_type="ndarray")
    g = sp.csr_matrix((np.exp(-pairs["v"] ** 2 / (2 * sigma ** 2)), (pairs["i"], pairs["j"])), shape=(len(v), len(src)))
    mv = (g @ D) / np.maximum(np.asarray(g.sum(1)).ravel(), 1)[:, None]
    size = np.linalg.norm(mv, axis=1, keepdims=True)
    return v + mv * np.minimum(1, cap / np.maximum(size, 1e-12))


LOCAL, CELL = 0.02, 0.003   # the scan's bone within LOCAL of a muscle seats it; one control point each CELL


def carried_bone(scan_bone, w, p):
    """The scan's bone surface within LOCAL of the muscle p (the scan's frame), carried into the body by the
    warp w: its points and their normals there."""
    d, _ = cKDTree(p).query(scan_bone.P, distance_upper_bound=LOCAL)
    near = np.isfinite(d)
    q, n = scan_bone.P[near], scan_bone.N[near]
    if not len(q):
        return q, n
    _, some = np.unique(np.floor(q / (CELL / 2)).astype(int), axis=0, return_index=True)   # as many as can matter
    q, n = q[some], n[some]
    x = w(q)
    m = w(q + n * 0.001) - x
    return x, m / np.maximum(np.linalg.norm(m, axis=1, keepdims=True), 1e-12)


def closer(x, n, bone, rounds=((1e-3, 0.015), (3e-4, 0.010), (1e-4, 0.007), (3e-5, 0.005), (1e-5, 0.004)),
           control=1500):
    """A warp near the identity that lays the carried scan bone (points x, normals n) on the body's own bone
    around one muscle, so the muscle rides with its bones instead of being pushed out of them afterwards (the
    body's warp has a control point each 8 mm and leaves the two bones millimetres apart between them). Each
    point is paired with the nearest of the body's samples that faces as it does (a thin plate's two faces are
    not confused) and drawn to that sample's tangent plane; a thin-plate spline through one point per CELL,
    each round (smoothing, reach) stiffer and farther-reaching than the next (the woman's skull, a stand-in for
    her own, lay up to a centimetre off her scan's about the temples). Returns the warp and the mean gap left,
    or (None, None) with too little bone near."""
    from scipy.interpolate import RBFInterpolator
    from anatomy_gaps import Warp, sample
    if bone.tree is None or len(x) < 30:
        return None, None
    warp, gap = None, None
    for lam, reach in rounds:
        y = warp(x) if warp is not None else x
        d, i = bone.tree.query(y, k=12, distance_upper_bound=reach, workers=2)
        ok = np.isfinite(d)
        i = np.where(ok, i, 0)
        agree = ok & (np.einsum("ij,ikj->ik", n, bone.N[i]) > 0.4)
        has = agree.any(1)
        j = i[np.arange(len(y)), np.argmax(agree, 1)]
        off = np.einsum("ij,ij->i", y - bone.P[j], bone.N[j])
        S, T = x[has], (y - off[:, None] * bone.N[j])[has]
        if len(S) < 30:
            break
        _, cell = np.unique(np.floor(S / CELL).astype(int), axis=0, return_index=True)
        if len(cell) > control:
            cell = sample(cell, control, 3)
        warp = Warp(rbf=RBFInterpolator(S[cell], T[cell], kernel="thin_plate_spline", smoothing=lam, degree=1))
        gap = float(np.abs(off[has]).mean())
    return warp, gap


def relax(v, f, rounds=3):
    """Small wrinkles smoothed away without shrinking (Taubin's two steps)."""
    from anatomy_fibres import taubin
    return taubin(v, f, rounds=rounds)


def unpoke(v, f, surf, gap, rounds=10, h=0.0007, sigma=0.003, cap=0.002, local=False):
    """Out of what `surf` holds, between the vertices too: the muscle's surface sampled every h, each sample
    inside drawn to gap off it by its nearest vertex, the move spread through the muscle (local: to that face's
    near vertices only). Returns the mesh and how many samples were still inside."""
    left, before = 0, None
    for rnd in range(rounds):
        X, _ = samples(v, f, h)
        inside, d, i = surf.query(X)
        left = int(inside.sum())
        if not left or (before is not None and rnd >= 3 and left > 0.9 * before):
            break       # out, or no longer getting out: what is left is held there by something else
        before = left
        _, j = cKDTree(v).query(X[inside])
        D = surf.P[i[inside]] + surf.N[i[inside]] * gap - X[inside]
        o = np.argsort(np.linalg.norm(D, axis=1))   # each vertex takes its samples' largest move (written last)
        M = np.zeros_like(v); M[j[o]] = D[o]
        hit = np.zeros(len(v), bool); hit[j] = True
        v = (nudge if local else spread)(v, hit, M[hit], sigma, cap)
    else:
        X, _ = samples(v, f, h)
        left = int(surf.query(X)[0].sum())
    return v, left


def dent(v, f, pieces, gap=MARGIN, rounds=10, h=0.0008):
    """The muscle hollowed about what lies inside it. unpoke() draws the muscle's own surface out of its
    neighbours; a neighbour's end lying wholly inside it (the digastric's, in the sternocleidomastoid the scan
    wraps round the whole mastoid tip) leaves none of its surface inside anything, so nothing moved. Here each
    of the neighbours' samples inside the muscle draws the muscle's nearest surface in past it. pieces: the
    neighbours' (points, normals). Returns the mesh and how many of their samples were still inside."""
    lo, hi = v.min(0) - 0.002, v.max(0) + 0.002
    X = [p[np.all((p >= lo) & (p <= hi), axis=1)] for p, n in pieces]
    X = np.concatenate(X) if X else np.zeros((0, 3))
    left = 0
    for rnd in range(rounds):
        if not len(X):
            break
        surf = Surface(meshes=[(v, f)], h=h)
        inside, d, i = surf.query(X, 0.02)
        left = int(inside.sum())
        if not left:
            break
        i = i[inside]
        _, j = cKDTree(v).query(surf.P[i])
        D = X[inside] - surf.P[i] - surf.N[i] * gap
        o = np.argsort(np.linalg.norm(D, axis=1))
        M = np.zeros_like(v); M[j[o]] = D[o]
        hit = np.zeros(len(v), bool); hit[j] = True
        v = nudge(v, hit, M[hit], 0.003, 0.002)
    return v, left


def inside_share(v, f, surf, h=0.0007):
    X, _ = samples(v, f, h)
    return float(surf.query(X)[0].mean()) if len(X) else 0.0


# MARK: the warp

JAW = r"^(mandible|set_of_lower_jaw_teeth)$"       # the body's mandible, with its teeth


def pairs(nodes, sex, scan, jaw=None):
    """(name, scan points, body points, weight, kind) for the head and neck; scan: mask name -> surface points.
    jaw: which of the scan's skull points are its mandible's, to pair it on its own (else the skull is one)."""
    from anatomy_gaps import sample
    def body(pattern=None, part=None, unless=None):
        hit = [v for n, (pid, st, v, f) in nodes.items()
               if ((part and pid == part) or (pattern and re.search(pattern, short(n))))
               and not (unless and re.search(unless, short(n)))]
        return np.concatenate(hit) if hit else None
    out = []
    def add(name, masks, target, w=1.0, n=400, top=None, keep=None):
        have = [scan[m] for m in (masks if isinstance(masks, list) else [masks]) if scan.get(m) is not None]
        if not have or target is None:
            return
        c = np.concatenate(have)
        if keep is not None:
            c = c[keep]
        if top is not None:
            c = c[c[:, 1] > c[:, 1].max() - top]
            target = target[target[:, 1] > target[:, 1].max() - top]
        out.append((name, sample(c, n), sample(target, 4 * n, 1), w, "surface"))
    if jaw is None:
        add("skull", "skull", body(part="skull"), n=1500)
    else:
        add("cranium", "skull", body(part="skull", unless=JAW), n=1500, keep=~jaw)
        add("mandible", "skull", body(JAW), n=800, keep=jaw)
    for i in range(1, 8):
        add(f"C{i}", f"vertebrae_C{i}", body(f"^cervical_vertebra_{i}$"), n=250)
    for i in range(1, 5):
        add(f"T{i}", f"vertebrae_T{i}", body(f"^thoracic_vertebra_{i}$"), n=250)
    for side, s in SIDES:
        add(f"clavicle {side}", f"clavicula_{side}", body(f"^clavicle_{s}$"), n=300)
        add(f"scapula {side}", f"scapula_{side}", body(f"^scapula_{s}$"), n=400)
        for r in (1, 2, 3):
            add(f"rib {r} {side}", f"rib_{side}_{r}", body(f"^rib_{r}_{s}$"), n=250)
    add("sternum", "sternum", body("^sternum$" if sex == "male" else "^(sternum|manubrium)$"), n=300)
    add("trachea", "trachea", body("^trachea$"), w=0.5)
    add("thyroid", "thyroid_gland", body("^thyroid_gland$"), w=0.5, n=250)
    add("oesophagus", "esophagus", body("^oesophagus$"), w=0.3, n=250, top=0.12)
    return out


def kabsch(a, b):
    """The rotation and shift taking the points a onto b, best by least squares."""
    ca, cb = a.mean(0), b.mean(0)
    U, _, Vt = np.linalg.svd((a - ca).T @ (b - cb))
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    R = Vt.T @ np.diag([1, 1, d]) @ U.T
    return R, cb - R @ ca


def find_jaw(nodes, skull_scan, w0, quiet):
    """Which of the scan's skull points are its mandible's (the dataset segments the skull as one): the body's
    own mandible with its teeth, fitted rigidly (ICP) to the scan's skull as a first warp w0 carries it, claims
    the points nearer it than the rest of the body's skull, within 5 mm."""
    from anatomy_gaps import sample
    jaw = np.concatenate([v for n, (pid, st, v, f) in nodes.items() if re.search(JAW, short(n))])
    rest = np.concatenate([v for n, (pid, st, v, f) in nodes.items() if pid == "skull" and not re.search(JAW, short(n))])
    x = w0(skull_scan)
    lo, hi = jaw.min(0) - 0.03, jaw.max(0) + 0.03
    near = np.all((x > lo) & (x < hi), axis=1)
    tree = cKDTree(x[near])
    T = sample(jaw, 4000, 5)
    R, t = np.eye(3), np.zeros(3)
    for k in range(40):
        y = T @ R.T + t
        d, i = tree.query(y, distance_upper_bound=0.012 if k < 10 else 0.006)
        ok = np.isfinite(d)
        dR, dt = kabsch(y[ok], x[near][i[ok]])
        R, t = dR @ R, dR @ t + dt
    moved = jaw @ R.T + t
    dm, _ = cKDTree(moved).query(x)
    dc, _ = cKDTree(rest).query(x)
    label = (dm < dc) & (dm < 0.005)
    angle = np.degrees(np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1)))
    if not quiet:
        res = np.median(cKDTree(x[near]).query(T @ R.T + t)[0]) * 1000
        log(f"    the scan's mandible: {label.sum()} of {len(x)} skull points, the body's turned {angle:.1f} deg and "
            f"moved {np.linalg.norm(moved.mean(0) - jaw.mean(0)) * 1000:.1f} mm onto it (median gap {res:.1f} mm)")
    return label


def paired_masks():
    names = ["skull"] + [f"vertebrae_C{i}" for i in range(1, 8)] + [f"vertebrae_T{i}" for i in range(1, 5)]
    for side, _ in SIDES:
        names += [f"clavicula_{side}", f"scapula_{side}"] + [f"rib_{side}_{r}" for r in (1, 2, 3)]
    return sorted(n + ".nii.gz" for n in names + ["sternum", "trachea", "thyroid_gland", "esophagus"])


def scan_surfaces(scan_dir):
    """The scan's paired masks meshed once: mask name -> (points, triangles) in the atlas frame (the scan's)."""
    from anatomy_gaps import load_mask, ct_mesh
    cache = os.environ.get("MORE_CACHE")   # development only: kept between runs
    kept = cache and os.path.join(cache, f"scan_{os.path.basename(scan_dir)}.pkl")
    if kept and os.path.exists(kept):
        import pickle
        return pickle.load(open(kept, "rb"))
    out = {}
    for name in paired_masks():
        a, A = load_mask(os.path.join(scan_dir, name))
        out[name.split(".")[0]] = ct_mesh(a, A, sigma=1.0, share=0.2)
    if kept:
        import pickle
        os.makedirs(cache, exist_ok=True)
        pickle.dump(out, open(kept, "wb"))
    return out


def warp_for(nodes, sex, meshes, quiet):
    """The scan-to-body warp of the head and neck: a first one with the skull as one, to find the scan's mandible
    by; then one with the mandible paired on its own, so the jaw's muscles follow it however open it is; then a
    closer one."""
    from anatomy_gaps import register, Then
    cache = os.environ.get("MORE_CACHE")   # development only: the warp kept between runs
    if cache and os.path.exists(os.path.join(cache, f"warp_{sex}.pkl")):
        import pickle
        return pickle.load(open(os.path.join(cache, f"warp_{sex}.pkl"), "rb"))
    pts = {n: (m[0] if m is not None else None) for n, m in meshes.items()}
    found = pairs(nodes, sex, pts)
    if not quiet:
        log(f"  {sex}: the head and neck's first warp, on {len(found)} pairs")
    w0 = register(found, rounds=(3e-2, 1e-2, 3e-3), quiet=quiet)
    jaw = find_jaw(nodes, pts["skull"], w0, quiet)
    found = pairs(nodes, sex, pts, jaw)
    if not quiet:
        log(f"  {sex}: the warp, the mandible on its own, on {len(found)} pairs")
    w = register(found, quiet=quiet)
    near = [(n, w(c), v, wt, k) for n, c, v, wt, k in found]
    w2 = register(near, rounds=(1e-3, 3e-4, 1e-4, 3e-5), control=3000, quiet=quiet)
    if cache:
        import pickle
        os.makedirs(cache, exist_ok=True)
        pickle.dump(Then(w, w2), open(os.path.join(cache, f"warp_{sex}.pkl"), "wb"))
    return Then(w, w2)


# MARK: one muscle

def scan_mesh(scan, task, mask, side):
    from anatomy_gaps import load_mask, ct_mesh
    a, A = load_mask(os.path.join(SEG, f"{scan}_{task}", f"{mask}_{side}.nii.gz"))
    return ct_mesh(a, A, sigma=0.8, share=0.05)


def target_count(v, f):
    """The triangles tools/anatomy_fibres.py would leave it: edges about EVEN at the median under BIG; above,
    CAP or one each PER_TRIANGLE of its surface, whichever is more (at most MOST), so the count rises with the
    area throughout."""
    A = area(v, f)
    if A >= BIG:
        return int(min(MOST, max(CAP, np.ceil(A / PER_TRIANGLE))))
    return max(FLOOR, int(np.ceil(A / (np.sqrt(3) / 4 * EVEN ** 2))))


def fit(v, f, touched, origin, insertion, bone, others, skin, h=0.0007):
    """Seat the attachments, then keep out of the bone, of `others` and inside the skin (module doc, 3 to 4). h:
    how finely the muscle's surface is sampled where it is kept out of things."""
    for rnd in range(3):            # the attachments drawn onto their bones
        n = vertex_normals(v, f)
        best = np.full(len(v), np.inf); D = np.zeros_like(v)
        for surf, need in (origin, insertion):
            if surf.tree is None:     # its bone has no surface near this muscle: nothing to draw it onto
                continue
            inside, d, i = surf.query(v, REACH)
            to = surf.P[i] - v
            facing = np.einsum("ij,ij->i", n, to) > 0.3 * np.maximum(d, 1e-9)
            pick = np.isfinite(d) & (facing | inside) & (touched | ~need) & (d < best)
            best[pick] = d[pick]
            D[pick] = surf.P[i[pick]] + surf.N[i[pick]] * GAP - v[pick]
        hit = np.isfinite(best)
        if not hit.any():
            break
        v = spread(v, hit, D[hit], SIGMA, STEP)
    return settle(v, f, bone, others, skin, h)


def settle(v, f, bone, others, skin, h=0.0007):
    """Out of the bone, out of `others`, under the skin, its small wrinkles smoothed, and out of the bone again."""
    v, left = unpoke(v, f, bone, GAP, h=h)
    if others is not None:
        v, left_o = unpoke(v, f, others, MARGIN, rounds=8, h=h, sigma=0.005)
    if skin is not None:
        v = under_skin(v, f, skin)
    v = relax(v, f)
    v, left = unpoke(v, f, bone, GAP, h=h)
    return v


def mirrored(v, f, bones, bone, side="L"):
    """A muscle of one side as its fellow of the other: the body's own bones of its side within LOCAL of it are
    mirrored with it (left for right), laid rigidly on the bones of the other side (no skeleton is its own mirror
    image: a limb stands a little differently, a skull is a little skew), then seated closely on them as closer()
    seats a scan's. So the two sides are one shape, each on its own bones. bones: {node: (points, normals)} of
    the body; bone: the Surface of those about where the fellow will lie. Returns the fellow's positions and
    triangles (wound the other way round) and the gap left, or None with no bone near."""
    keep = [x for n, x in bones.items() if side_of(n) in (None, side)]
    if not keep:
        return None
    P, N = np.concatenate([x[0] for x in keep]), np.concatenate([x[1] for x in keep])
    d, _ = cKDTree(v).query(P, distance_upper_bound=LOCAL)
    near = np.isfinite(d)
    q, n = P[near], N[near]
    _, some = np.unique(np.floor(q / (CELL / 2)).astype(int), axis=0, return_index=True)
    q, n = q[some], n[some]
    flip = np.array([-1.0, 1.0, 1.0])
    q, n, x = q * flip, n * flip, v * flip
    if bone.tree is None or len(q) < 30:
        return None
    for reach in (0.03, 0.03, 0.02, 0.02, 0.015, 0.015, 0.01, 0.01, 0.008, 0.008):      # rigidly first
        d, i = bone.tree.query(q, k=12, distance_upper_bound=reach, workers=2)
        ok = np.isfinite(d)
        i = np.where(ok, i, 0)
        agree = ok & (np.einsum("ij,ikj->ik", n, bone.N[i]) > 0.4)
        has = agree.any(1)
        if has.sum() < 30:
            break
        j = i[np.arange(len(q)), np.argmax(agree, 1)]
        R, t = kabsch(q[has], bone.P[j][has])
        q, n, x = q @ R.T + t, n @ R.T, x @ R.T + t
    seat, gap = closer(q, n, bone)
    if seat is not None:
        x = seat(x)
    return x, f[:, [0, 2, 1]], gap


def under_skin(v, f, skin, rounds=6):
    """Every vertex at least SKIN_IN under the skin: those nearer it, or outside, drawn in along its normal."""
    for _ in range(rounds):
        inside, d, i = skin.query(v, 0.03)
        ok = np.isfinite(d)
        depth = np.einsum("ij,ij->i", skin.P[i] - v, skin.N[i])   # under the skin along its normal; < 0 outside
        bad = ok & (depth < SKIN_IN)
        if not bad.any():
            break
        D = -skin.N[i[bad]] * (SKIN_IN + 0.0003 - depth[bad])[:, None]
        v = spread(v, bad, D, SIGMA, STEP)
    return v


FAR, FOOT = 0.025, 0.004    # an end within FAR of its bone is drawn out to it; its foot: what lies within FOOT of its tip


def reach_out(v, f, attachment, bone, quiet_name=None):
    """An end that stops short of its bone drawn out to it (the scan's masks hold a muscle's flesh and little of
    its tendon: the sternocleidomastoid's stopped 5 to 10 mm off the mastoid, the clavicle and the sternum). For
    each bone of an attachment that nothing of the muscle touches: if the muscle comes within FAR of it, the
    vertices within FOOT of its nearest one go onto the bone, the pull spread as widely as the gap is long so the
    end tapers as a tendon does. attachment: [(points, normals)] a bone each. Returns the mesh and what it drew:
    [(gap in mm, vertices)]."""
    drew = []
    for piece in attachment:
        surf = Surface(pieces=[piece], box=(v.min(0) - FAR, v.max(0) + FAR))
        if surf.tree is None:
            continue
        d, i = surf.tree.query(v, workers=2)
        gap = float(d.min())
        if gap > FAR:
            continue
        foot = d <= gap + max(FOOT, 0.4 * gap)
        D = surf.P[i[foot]] + surf.N[i[foot]] * GAP - v[foot]
        v = spread(v, foot, D, float(np.clip(gap, 0.004, 0.012)), gap + FOOT + 0.002)
        drew.append((gap * 1000, int(foot.sum())))
    if drew:
        v = relax(v, f, rounds=2)
        v, _ = unpoke(v, f, bone, GAP, rounds=6)
        v, _ = unpoke(v, f, bone, GAP, rounds=8, sigma=0.002, cap=0.001, local=True)
    return v, drew


def reach(folder, quiet=False):
    """reach_out for every muscle this tool made in `folder`'s atlas whose origin or insertion touches none of
    its bones. Returns what it did; the parts it changed lose their fibres (tools/anatomy_fibres.py lays them
    again)."""
    from anatomy_fibres import read_part, write_part, sha256
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    rows = {m[2]: m for m in MUSCLES}
    said = []
    for body in manifest["bodies"]:
        nodes = body_nodes(folder, body)
        bones = {n: outward_samples(v, f, 0.0006) for n, (pid, st, v, f) in nodes.items()
                 if pid in BONE_PARTS and st.get("tissue") in ("bone", "cartilage") and not st.get("inner")}
        for part in body["parts"]:
            if part["id"] not in PARTS:
                continue
            meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
                      for v, f in read_part(os.path.join(folder, part["file"]))]
            changed = False
            for k, st in enumerate(part["structures"]):
                row = rows.get(re.sub(r"^TS_|_[LR]$", "", st["node"]))
                if st.get("made") != MARK or row is None:
                    continue
                s = side_of(st["node"])
                v, f = meshes[k]
                box = (v.min(0) - 0.03, v.max(0) + 0.03)
                bone = Surface(pieces=list(bones.values()), box=box)
                for what, pat in (("origin", row[7]), ("insertion", row[8])):
                    mine = [x for n, x in bones.items() if re.search(pat, short(n)) and side_of(n) in (None, s)]
                    if not mine or contact(v, f, Surface(pieces=mine, box=box)) >= 4:
                        continue
                    v, drew = reach_out(v, f, mine, bone)
                    if drew:
                        changed = True
                        said.append(f"{body['id']} {st['node']}: its {what} drawn out "
                                    + ", ".join(f"{g:.0f} mm ({n} vertices)" for g, n in drew)
                                    + f"; now {contact(v, f, Surface(pieces=mine, box=box)):.0f} mm2 on its bone")
                        if not quiet:
                            log("   " + said[-1])
                if inside_share(v, f, bone) > 0.002:     # what a coarser mesh or a pull left in the bone
                    v, _ = unpoke(v, f, bone, GAP, rounds=12, h=0.0006, sigma=0.002, cap=0.001, local=True)
                    changed = True
                meshes[k] = (v, f)
            if changed:
                lo, hi = write_part(os.path.join(folder, part["file"]), meshes)
                part.pop("fibres", None)
                part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
                part["sha256"] = sha256(os.path.join(folder, part["file"]))
                part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    return f"{len(said)} ends drawn out to their bones" if said else "every end on its bone already"


YIELD = r"^(parotid|submandibular|sublingual)_gland_[LR]$"
FINE_GLAND = 0.004      # a gland's triangles are split until its edges are about this, so it can take a shape


def give_way(folder, quiet=False):
    """The salivary glands out of the bones and the muscles of the jaw and neck. A gland lies on its muscles:
    the parotid on the back of the masseter and round the ramus against the medial pterygoid, the submandibular
    under the mandible. The reference set's glands are coarse (the parotid 70 triangles) and drawn about another
    jaw; on this body they passed 2 to 7 mm into the masseter, the ramus and the medial pterygoid. It is the
    gland that gives way, not the muscle: its triangles are split until it can take a shape, it is smoothed, and
    it is drawn out of what it lay in and kept under the skin. Returns what it did."""
    from anatomy_fibres import read_part, write_part, sha256, subdivide
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    only = os.environ.get("MORE_ONLY")
    said = []
    for body in manifest["bodies"]:
        if only and body["id"] != only:
            continue
        nodes = body_nodes(folder, body)
        solid = {n: outward_samples(v, f, 0.0007) for n, (pid, st, v, f) in nodes.items()
                 if not st.get("inner") and not re.search(YIELD, short(n))
                 and ((pid in BONE_PARTS and st.get("tissue") in ("bone", "cartilage")) or pid in PARTS)}
        skin = [outward_samples(v, f, 0.0015) for n, (pid, st, v, f) in nodes.items() if pid == "skin"]
        for part in body["parts"]:
            if not any(re.search(YIELD, short(st["node"])) for st in part["structures"]):
                continue
            meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64))
                      for v, f in read_part(os.path.join(folder, part["file"]))]
            changed = False
            for k, st in enumerate(part["structures"]):
                if not re.search(YIELD, short(st["node"])) or st.get("inner"):
                    continue
                v, f = meshes[k]
                box = (v.min(0) - 0.02, v.max(0) + 0.02)
                surf = Surface(pieces=list(solid.values()), box=box)
                before = inside_share(v, f, surf)
                if before < 0.003:
                    continue
                for _ in range(4):
                    e = np.linalg.norm(v[f] - v[f[:, [1, 2, 0]]], axis=2)
                    if np.median(e) <= FINE_GLAND:
                        break
                    v, f = subdivide(v, f)
                v = relax(v, f, rounds=4)
                v, _ = unpoke(v, f, surf, MARGIN, rounds=14, h=0.0007, sigma=0.004)
                if skin:
                    v = under_skin(v, f, Surface(pieces=skin, box=(box[0] - 0.02, box[1] + 0.02)))
                v = relax(v, f, rounds=2)
                v, left = unpoke(v, f, surf, MARGIN, rounds=12, h=0.0007, sigma=0.002, cap=0.001, local=True)
                meshes[k] = (v, f)
                st["triangles"] = int(len(f))
                changed = True
                said.append(f"{body['id']} {st['node']}: {len(f)} triangles, in bone and muscle {before:.1%} -> "
                            f"{inside_share(v, f, surf):.2%}")
                if not quiet:
                    log("   " + said[-1])
            if changed:
                lo, hi = write_part(os.path.join(folder, part["file"]), meshes)
                part.pop("fibres", None)
                part["triangles"] = int(sum(len(f) for v, f in meshes))
                part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
                part["sha256"] = sha256(os.path.join(folder, part["file"]))
                part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    return f"{len(said)} glands drawn out of the muscles and bones" if said else "no gland in a muscle or a bone"


def contact(v, f, surf, h=0.0007, within=0.0012):
    """The muscle's surface within `within` of what surf holds, mm2."""
    X, _ = samples(v, f, h)
    _, d, _ = surf.query(X, within)
    return float(np.isfinite(d).mean() * area(v, f) * 1e6)


# MARK: muscles drawn from their attachments

def evenly(P, n):
    """n points evenly apart along the line through P."""
    P = np.asarray(P, float)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    return np.stack([np.interp(np.linspace(0, d[-1], n), d, P[:, k]) for k in range(3)], axis=1)


def tight(x, h):
    """A string drawn tight over heights h at places x along it: their upper hull."""
    hull = [0]
    for i in range(1, len(x)):
        while len(hull) >= 2:
            a, b = hull[-2], hull[-1]
            if (h[b] - h[a]) * (x[i] - x[a]) <= (h[i] - h[a]) * (x[b] - x[a]):
                hull.pop()
            else:
                break
        hull.append(i)
    return np.interp(x, x[hull], h[hull])


def draped(course, off, half, thick, under, over=None, step=0.003, across=8, clear=0.0006, around=0.002, reach=0.03):
    """A flat muscle drawn from its attachments: a sheet along `course` (points from its origin to its insertion),
    each of its fibres pulled tight over what lies under it, as a strap under tension lies. off: the direction it
    lies off what is under it. half(u), thick(u): its half-width and its thickness along it, u from 0 to 1; it
    thins to an edge at its sides and at both ends. With half None, `course` is instead the lines across the
    sheet, from its origin's to its insertion's (a muscle whose ends are not square to its length). under: the Surface it lies on, never nearer than `clear`;
    over: one it lies under where that covers it (the sternum over a muscle arising from its back). Returns
    positions and triangles (a closed surface, outward) and the worst clash of the two in metres (0 with none)."""
    from anatomy_tendons import spline, smoothstep
    m1 = across + 1
    s = np.linspace(-1, 1, m1)
    off = np.asarray(off, float) / np.linalg.norm(off)
    if half is None:        # `course`: the lines across it, its origin's first, its insertion's last; a fibre from
        rows = [evenly(r, m1) for r in course]                    # each place on one to the same place on the next
        n = len(spline([r.mean(0) for r in rows], step))
        B = np.stack([evenly(spline([r[j] for r in rows], step / 3), n) for j in range(m1)], axis=1)
        C = B.mean(1)
    else:
        C = spline(course, step)
        n = len(C)
    x = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    u = x / x[-1]
    if half is not None:
        T = np.gradient(C, axis=0)
        T /= np.linalg.norm(T, axis=1, keepdims=True)
        W = np.cross(off, T)
        W /= np.linalg.norm(W, axis=1, keepdims=True)
        a = np.array([half(k) for k in u])
        B = C[:, None, :] + (a[:, None] * s[None, :])[:, :, None] * W[:, None, :]
    ends = smoothstep(x / 0.008) * smoothstep((x[-1] - x) / 0.008)
    th = np.array([thick(k) for k in u])[:, None] * ((1 - s ** 2) ** 0.35)[None, :] * ends[:, None]

    def heights(surf, lowest):
        """Of what surf holds on the line through each of the sheet's points along `off`: the highest (or lowest)."""
        H = np.full((n, m1), np.nan)
        lo, hi = B.reshape(-1, 3).min(0) - reach, B.reshape(-1, 3).max(0) + reach
        P = surf.P[((surf.P >= lo) & (surf.P <= hi)).all(1)]
        if not len(P):
            return H
        al = P @ off
        Q = P - np.outer(al, off)
        tree = cKDTree(Q)
        for i in range(n):
            for j in range(m1):
                b = B[i, j] - off * (B[i, j] @ off)
                k = tree.query_ball_point(b, around)
                if k:
                    d = al[k] - B[i, j] @ off
                    d = d[(d < reach) & (d > -reach)]
                    if len(d):
                        H[i, j] = d.min() if lowest else d.max()
        return H

    floor = heights(under, False) + th / 2 + clear
    roof = heights(over, True) - th / 2 - clear if over is not None else np.full((n, m1), np.nan)
    h, clash = np.zeros((n, m1)), 0.0
    for j in range(m1):
        f, r = floor[:, j], roof[:, j]
        pinned = np.isfinite(r)
        both = pinned & np.isfinite(f) & (f > r)
        if both.any():
            clash = max(clash, float((f - r)[both].max()))
        v = np.where(np.isfinite(f), f, -1.0)
        v[pinned] = np.where(both, (f + r) / 2, r)[pinned]
        for e in (0, n - 1):
            if v[e] == -1.0:
                v[e] = 0.0
        k = int(np.nonzero(pinned)[0].max()) if pinned.any() else 0
        line = v.copy()
        line[k:] = tight(x[k:], v[k:])
        if k:                                   # under its cover: as high as its cover and the string let it lie
            line[:k + 1] = np.where(pinned[:k + 1], v[:k + 1], np.minimum(tight(x[:k + 1], v[:k + 1]), line[k]))
        h[:, j] = line
    M = B + h[:, :, None] * off
    N = np.cross(np.gradient(M, axis=0), np.gradient(M, axis=1))
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
    if (N @ off).mean() < 0:
        N = -N
    top, bottom = M + N * th[:, :, None] / 2, M - N * th[:, :, None] / 2
    it = lambda i, j: i * m1 + j
    ib = lambda i, j: it(i, j) if i in (0, n - 1) or j in (0, across) else n * m1 + (i - 1) * (across - 1) + (j - 1)
    V = np.vstack([top.reshape(-1, 3), bottom[1:-1, 1:-1].reshape(-1, 3)])
    F = []
    for i in range(n - 1):
        for j in range(across):
            turn = (i == 0 and j == 0) or (i == n - 2 and j == across - 1)   # no triangle wholly on the rim
            for g, flip in ((it, False), (ib, True)):
                p, q, r, t = g(i, j), g(i, j + 1), g(i + 1, j), g(i + 1, j + 1)
                two = [(p, q, t), (p, t, r)] if turn else [(p, q, r), (q, t, r)]
                F += [(k[0], k[2], k[1]) for k in two] if flip else two
    F = np.asarray(F, np.int64)
    volume = np.einsum("ij,ij->i", V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum()
    return V, (F if volume > 0 else F[:, [0, 2, 1]]), clash


def strap_sternothyroid(nodes, made, s, prefix):
    """The sternothyroid, a flat strap (Gray's): from the back of the manubrium, below the sternohyoid's origin,
    up in front of the great vessels, the trachea and the thyroid gland's lobe, to the oblique line of the
    thyroid cartilage, where the thyrohyoid (made before it) begins; the two lie side by side below and part as
    they climb. The scan's mask of it is a ribbon a voxel or two thick with a fan of stray voxels at its foot;
    carried to the body it came out as a bow-tie. Here it is a strap 13 mm wide and 3 mm thick."""
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    sternum = np.concatenate([v for v, f in get(r"^(sternum|manubrium)$")])
    top = sternum[sternum[:, 1] > sternum[:, 1].max() - 0.03]
    cart = Surface(meshes=get(r"^thyroid_cartilage$"), h=0.0006)
    mid = ((top[:, 0].min() + top[:, 0].max()) / 2 + (cart.P[:, 0].min() + cart.P[:, 0].max()) / 2) / 2
    x0 = mid + sg * 0.008                    # no body's sternum is quite under its larynx: about the line between
    behind = lambda y0, y1: top[(np.abs(top[:, 0] - x0) < 0.004) & (top[:, 1] < top[:, 1].max() - y0)
                               & (top[:, 1] > top[:, 1].max() - y1)][:, 2].min() - 0.002
    start = np.array([x0, top[:, 1].max() - 0.018, behind(0.014, 0.022)])
    rim = np.array([x0, top[:, 1].max() - 0.002, behind(0.0, 0.006)])
    th = (made.get(f"{prefix}thyrohyoid_{s}") or nodes[f"{prefix}thyrohyoid_{s}"])[2]
    foot = th[th[:, 1] < th[:, 1].min() + 0.004].mean(0)
    d, i = cart.tree.query(foot - [0, 0.004, 0])
    under = Surface(meshes=get(r"^(trachea|tracheal_cartilage|thyroid_gland.*|cricoid_cartilage|thyroid_cartilage|"
                               r"cricothyroid_[LR]|brachiocephalic_.*|left_common_carotid_artery.*|thymus_.*)$"), h=0.0007)
    over = Surface(meshes=get(r"^(sternum|manubrium)$"), h=0.0007)
    v, f, clash = draped([start, rim, cart.P[i]], [0.0, 0.0, 1.0], lambda u: 0.0065 - 0.001 * u, lambda u: 0.003,
                         under, over)
    return v, f, clash


def strap_scalenus_posterior(nodes, made, s, prefix):
    """The scalenus posterior, the smallest and deepest of the three (Gray's): from the posterior tubercles of
    the transverse processes of the lower two or three cervical vertebrae, down behind the scalenus medius and
    over the outer border of the first rib, to the outer surface of the second rib behind the serratus anterior.
    The scan's mask of it is a few voxels that lie inside the medius. Here it is a slender flat belly, 14 by 5 mm
    at its thickest."""
    from anatomy_tendons import far
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    one = lambda pat: np.concatenate([v for v, f in get(pat)])
    lat = np.array([sg, 0.0, 0.0])
    tips = [far(one(f"^cervical_vertebra_{k}$"), lat - [0, 0, 0.4], 0.003) for k in (5, 6)]
    r2 = one(f"^rib_2_{s}$")
    x = r2 @ lat
    at = tips[1] @ lat + 0.72 * (x.max() - tips[1] @ lat)   # just outside the first rib's outer border,
    back = r2[(np.abs(x - at) < 0.005) & (r2[:, 2] < r2[x.argmax(), 2] - 0.008)]   # behind the rib's widest
    end = far(back, np.array([0.0, 1.0, 0.0]) + 0.7 * lat, 0.002)
    medius = made.get(f"{prefix}scalenus_medius_{s}") or nodes.get(f"{prefix}scalenus_medius_{s}")
    under = Surface(meshes=get(f"^(rib_[12]_{s}|cervical_vertebra_[4-7]|thoracic_vertebra_[12])$")
                    + ([(medius[2], medius[3])] if medius else []), h=0.0007)
    out = lat * 0.8 + np.array([0.0, 0.5, -0.33])       # out of the root of the neck: lateral, up and a little back
    v, f, clash = draped([tips[0] + lat * 0.001, tips[1] + lat * 0.004 - [0, 0.003, 0], end], out,
                         lambda u: 0.0035 + 0.0035 * np.sin(np.pi * min(u * 1.2, 1.0)) ** 0.7 + 0.002 * u,
                         lambda u: 0.002 + 0.0035 * np.sin(np.pi * u), under)
    return v, f, clash


def rope(course, wide, half, thick, step=0.003, ring=12):
    """A muscle with a round or oval section drawn along its course: half(s, length) and thick(s, length), its
    section's two half-axes at the distance s along it; wide: the direction it is wide in at its start, carried
    along without twist. Returns positions and triangles (a closed surface, outward)."""
    from anatomy_tendons import spline, frames
    C = spline(course, step)
    T, W = frames(C, np.asarray(wide, float))
    B = np.cross(T, W)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    a = np.array([half(x, s[-1]) for x in s])
    b = np.array([thick(x, s[-1]) for x in s])
    th = np.linspace(0, 2 * np.pi, ring, endpoint=False)
    V = (C[:, None, :] + a[:, None, None] * np.cos(th)[None, :, None] * W[:, None, :]
         + b[:, None, None] * np.sin(th)[None, :, None] * B[:, None, :]).reshape(-1, 3)
    n = len(C)
    F = []
    for i in range(n - 1):
        for j in range(ring):
            p, q = i * ring + j, i * ring + (j + 1) % ring
            F += [(p, q, p + ring), (q, q + ring, p + ring)]
    c0, c1 = len(V), len(V) + 1
    V = np.vstack([V, C[0] - T[0] * min(a[0], b[0]) * 0.5, C[-1] + T[-1] * min(a[-1], b[-1]) * 0.5])
    for j in range(ring):
        F.append((c0, (j + 1) % ring, j))
        F.append((c1, (n - 1) * ring + j, (n - 1) * ring + (j + 1) % ring))
    F = np.asarray(F, np.int64)
    return V, (F if signed_volume(V, F) > 0 else F[:, [0, 2, 1]])


def mastoid(nodes, s):
    """The mastoid process of one side: its tip, the Surface of its temporal bone, and the direction out of the
    head there. The tip is the lowest of the bone's outer 30 mm behind its middle (the styloid is lower, but
    farther in; the zygomatic process is in front)."""
    lat = np.array([1.0 if s == "L" else -1.0, 0.0, 0.0])
    temporal = Surface(meshes=[(v, f) for n, (pid, st, v, f) in nodes.items() if short(n) == f"temporal_bone_{s}"],
                       h=0.0007)
    t = temporal.P
    out = t[t @ lat > (t @ lat).max() - 0.03]
    back = out[out[:, 2] < np.median(t[:, 2])]
    return back[back[:, 1].argmin()], temporal, lat


def mastoid_side(nodes, s):
    """Where the sternocleidomastoid ends (Gray's): the outer face of the mastoid process, from its tip up. The
    scan's mask of the muscle stops 5 mm short of the tip; drawn out to the nearest of its bone it went under
    the skull, into the notch inside the process where the digastric arises. Returns a point 3 mm off the
    process's outer face, 12 mm above its tip."""
    tip, temporal, lat = mastoid(nodes, s)
    t = temporal.P
    band = t[(np.abs(t[:, 1] - tip[1] - 0.012) < 0.003) & (np.abs(t[:, 2] - tip[2] + 0.003) < 0.006)]
    return band[(band @ lat).argmax()] + lat * 0.003


def drawn_up(v, target, foot=0.006, reach=0.05):
    """A muscle's upper end drawn to `target`: what lies within `foot` of its top moves there whole, the rest
    less and less, none of it `reach` below the top."""
    from anatomy_tendons import smoothstep
    top = v[:, 1].max()
    w = smoothstep((v[:, 1] - (top - reach)) / (reach - foot))
    return v + np.outer(w, target - v[v[:, 1] > top - foot].mean(0))


UPPER_END = {"sternocleidomastoid": mastoid_side}


def strap_digastric(nodes, made, s, prefix):
    """The digastric, two bellies joined by a round tendon (Gray's): the posterior belly from the mastoid notch
    of the temporal bone, down and forward to the tendon, which is held to the hyoid's body and greater horn
    by a loop of fascia; the anterior belly from there forward to the digastric fossa, on the inner side of the
    mandible's lower border beside the symphysis. The scan's mask of it is its anterior belly alone, 35 mm of
    it, and that lay 15 mm up inside the jaw's arch. Here it is the whole muscle: the posterior belly 11 by
    9 mm at its thickest, the tendon 3.6 mm, the anterior belly flatter, 13 by 6.5 mm."""
    sg = 1.0 if s == "L" else -1.0
    one = lambda pat: np.concatenate([v for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))])
    lat = np.array([sg, 0.0, 0.0])
    tip, temporal, _ = mastoid(nodes, s)
    d, i = temporal.tree.query(tip - lat * 0.014 + [0, 0.006, -0.008])     # the notch: inside the process, behind
    origin = temporal.P[i] + temporal.N[i] * 0.0016
    hyoid = one(r"^hyoid(_bone)?$")
    front = hyoid[hyoid[:, 2] > hyoid[:, 2].max() - 0.008]                 # its body
    mid = (front[:, 0].min() + front[:, 0].max()) / 2
    beside = hyoid[np.abs(hyoid[:, 0] - (mid + sg * 0.014)) < 0.003]       # where body and greater horn meet
    there = hyoid[np.abs(hyoid[:, 2] - beside[:, 2].mean()) < 0.003]
    tendon = np.array([sg * ((sg * there[:, 0]).max() + 0.0028), beside[:, 1].mean(), beside[:, 2].mean()])   # on its outer side
    jaw = one(r"^mandible$")
    chin = jaw[jaw[:, 2] > jaw[:, 2].max() - 0.03]
    mid = chin[chin[:, 1] < chin[:, 1].min() + 0.003][:, 0].mean()
    col = chin[np.abs(chin[:, 0] - (mid + sg * 0.009)) < 0.003]
    low = col[col[:, 1] < col[:, 1].min() + 0.005]
    fossa = np.array([mid + sg * 0.009, col[:, 1].min() + 0.0015, low[:, 2].min() - 0.0012])
    unit = lambda x: x / np.linalg.norm(x)
    course = [origin, tendon + unit(origin - tendon) * 0.014, tendon, tendon + unit(fossa - tendon) * 0.012, fossa]
    floor = _named(nodes, made, prefix, ("mylohyoid",), s)
    if floor:                           # its anterior belly lies under the floor of the mouth
        sheet = floor[0][0]
        under = []
        for q in (0.35, 0.55, 0.75):
            p = course[3] + (fossa - course[3]) * q
            near = sheet[np.linalg.norm(sheet[:, [0, 2]] - p[[0, 2]], axis=1) < 0.006]
            if len(near):
                p = np.array([p[0], min(p[1], near[:, 1].min() - 0.0042), p[2]])
            under.append(p)
        course = course[:4] + under + [fossa]
    from anatomy_tendons import spline
    C = spline(course)
    at = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    st = at[np.linalg.norm(C - tendon, axis=1).argmin()]
    bell = lambda x: np.sin(np.pi * min(max(x, 0.0), 1.0)) ** 0.6
    def axis(big_back, big_front, thin=0.0018):
        def r(x, length):
            if x < st - 0.008:
                return thin + (big_back - thin) * bell(x / (st - 0.008))
            if x <= st + 0.008:
                return thin
            return thin + (big_front - thin) * bell((x - st - 0.008) / (length - st - 0.008))
        return r
    v, f = rope(course, lat, axis(0.0055, 0.0065), axis(0.0045, 0.0032))
    return v, f, 0.0


def strap_levator_scapulae(nodes, made, s, prefix):
    """The levator scapulae (Gray's): by four slips from the transverse processes of the atlas and axis and the
    posterior tubercles of those of the third and fourth cervical vertebrae, down and back behind the scalenes
    to the vertebral border of the scapula, between its medial angle and the root of its spine. The scan's mask
    of it, carried to the body, came out a sheet 45 mm broad that held the scalenus posterior inside it and,
    on the side whose shoulder blade sits farther out, stopped 20 mm short of the bone. Here it is a strap from
    the four processes to the upper 32 mm of the border, 28 mm broad and 9 mm thick in its belly, lying outside
    the scalenes and the deep muscles of the neck."""
    from anatomy_tendons import far
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    one = lambda pat: np.concatenate([v for v, f in get(pat)])
    unit = lambda x: x / np.linalg.norm(x)
    lat = np.array([sg, 0.0, 0.0])
    tips = [far(one(f"^cervical_vertebra_{k}$"), lat - [0, 0, 0.4], 0.003) + lat * 0.0005 for k in (1, 2, 3, 4)]
    sc = one(f"^scapula_{s}$")
    angle = far(sc, np.array([0.0, 1.0, 0.0]) - lat, 0.003)
    border, run = [], 0.0
    for dy in np.arange(0.0, 0.06, 0.004):                  # down its vertebral border from the medial angle
        band = sc[np.abs(sc[:, 1] - (angle[1] - dy)) < 0.003]
        p = band[(band @ -lat).argmax()] - lat * 0.0005
        run += np.linalg.norm(p - border[-1]) if border else 0.0
        border.append(p)
        if run >= 0.032:
            break
    top, foot = np.array(tips), np.array(border)
    along = unit(foot.mean(0) - top.mean(0))
    mid = (top.mean(0) + foot.mean(0)) / 2
    wide = (top[-1] + foot[-1]) / 2 - (top[0] + foot[0]) / 2
    wide = unit(wide - along * (wide @ along))              # across the strap, square to its length
    belly = [mid - wide * 0.014, mid + wide * 0.014]
    kept = [made.get(f"{prefix}{k}_{s}") or nodes.get(f"{prefix}{k}_{s}") for k in ("scalenus_medius", "scalenus_posterior")]
    under = Surface(meshes=get(f"^(cervical_vertebra_[1-7]|thoracic_vertebra_[1-3]|rib_[1-3]_{s}|deep_back_muscles_{s})$")
                    + [(k[2], k[3]) for k in kept if k], h=0.0007)
    out = lat + np.array([0.0, 0.15, -0.25])                # it lies on the side of the neck, facing out and a little back
    v, f, clash = draped([top, belly, foot], out, None, lambda u: 0.004 + 0.005 * np.sin(np.pi * min(u * 1.15, 1.0)) ** 0.8,
                         under)
    return v, f, clash


def strap_thyrohyoid(nodes, made, s, prefix):
    """The thyrohyoid, a small four-sided muscle (Gray's): from the oblique line on the outer face of the thyroid
    cartilage's lamina, straight up over the cartilage's upper border to the lower border of the greater horn
    of the hyoid. The scan's mask of it, carried to the body, lay inside the larynx, within the lamina, where
    it held a seventh of the thyroarytenoid. Here it is a sheet 3 mm thick on the lamina's outer face: its
    hinder fibres short, from high on the lamina, its front ones long, from low on it."""
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    cart = Surface(meshes=get(r"^thyroid_cartilage$"), h=0.0006)
    hyoid = Surface(meshes=get(r"^hyoid(_bone)?$"), h=0.0006)
    mid = (cart.P[:, 0].min() + cart.P[:, 0].max()) / 2
    out = np.array([sg * 0.85, 0.0, 0.5]) / np.hypot(0.85, 0.5)        # the way a lamina's outer face looks
    face = cart.P[(cart.N @ out > 0.5) & (sg * (cart.P[:, 0] - mid) > 0.003)]
    z0, z1 = face[:, 2].min(), face[:, 2].max()
    def on_face(z, up):                 # the lamina's outer face at depth z: `up` of the way from its lower border
        band = face[np.abs(face[:, 2] - z) < 0.003]
        y = band[:, 1].min() + up * (np.percentile(band[:, 1], 90) - band[:, 1].min())
        return band[np.abs(band[:, 1] - y).argmin()]
    line = [on_face(z0 + f * (z1 - z0), up) for f, up in ((0.22, 0.78), (0.42, 0.52), (0.62, 0.26))]   # the oblique line
    side = hyoid.P[sg * (hyoid.P[:, 0] - mid) > 0.004]
    def under_horn(z):                  # the lower border of the hyoid's greater horn at depth z
        band = side[np.abs(side[:, 2] - z) < 0.002]
        low = band[band[:, 1] < band[:, 1].min() + 0.0015]
        return np.array([low[:, 0].mean(), band[:, 1].min() + 0.001, z])       # its end laps the border's outer lip
    horn = [under_horn(z) for z in np.linspace(line[0][2] + 0.001, line[-1][2] - 0.002, 4)]
    under = Surface(meshes=get(r"^(thyroid_cartilage|hyoid(_bone)?)$"), h=0.0006)
    v, f, clash = draped([np.array(line) + out * 0.0003, np.array(horn)], out, None, lambda u: 0.0032, under,
                         step=0.002, across=8, around=0.0015)
    return v, f, clash


def _named(nodes, made, prefix, names, s):
    """The meshes of muscles made already (this run's, else the atlas's), by node name without prefix or side."""
    out = []
    for k in names:
        x = made.get(f"{prefix}{k}_{s}") or nodes.get(f"{prefix}{k}_{s}")
        if x:
            out.append((x[2], x[3]))
    return out


def strap_sternohyoid(nodes, made, s, prefix):
    """The sternohyoid, a thin narrow strap (Gray's): from the back of the medial end of the clavicle, the
    posterior sternoclavicular ligament and the upper, hinder part of the manubrium, up and a little medialward
    in front of the sternothyroid and the thyrohyoid, to the lower border of the body of the hyoid; the two a
    good way apart below and nearly touching above. No scan labels it. Here it is a strap 13 mm wide below and
    10 mm above, 3 mm thick."""
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    one = lambda pat: np.concatenate([v for v, f in get(pat)])
    cl = one(f"^clavicle_{s}$")
    inner = (sg * cl[:, 0]).min()                                  # the clavicle's medial end
    end = cl[sg * cl[:, 0] < inner + 0.02]
    x0 = sg * (inner + 0.006)
    bone = np.vstack([one(r"^(sternum|manubrium)$"), end])
    col = bone[np.abs(bone[:, 0] - x0) < 0.005]
    top = col[:, 1].max()
    behind = lambda y0, y1: col[(col[:, 1] < top - y0) & (col[:, 1] > top - y1)][:, 2].min() - 0.002
    start = np.array([x0, top - 0.016, behind(0.012, 0.020)])
    rim = np.array([x0 - sg * 0.002, top - 0.001, behind(0.0, 0.006)])
    hy = one(r"^hyoid(_bone)?$")
    body = hy[hy[:, 2] > hy[:, 2].max() - 0.008]
    mid = (body[:, 0].min() + body[:, 0].max()) / 2
    at = body[np.abs(body[:, 0] - (mid + sg * 0.007)) < 0.003]
    low = at[at[:, 1] < at[:, 1].min() + 0.002]
    to = np.array([mid + sg * 0.007, at[:, 1].min() + 0.0008, low[:, 2].max()])
    under = Surface(meshes=get(r"^(trachea|tracheal_cartilage|thyroid_gland.*|cricoid_cartilage|thyroid_cartilage|"
                               r"cricothyroid_[LR]|brachiocephalic_.*|left_common_carotid_artery.*|thymus_.*|hyoid(_bone)?)$")
                    + _named(nodes, made, prefix, ("sternothyroid", "thyrohyoid"), s), h=0.0007)
    over = Surface(meshes=get(f"^(sternum|manubrium|clavicle_{s})$"), h=0.0007)
    return draped([start, rim, to], [0.0, 0.0, 1.0], lambda u: 0.0065 - 0.0015 * u, lambda u: 0.003, under, over)


def strap_omohyoid(nodes, made, s, prefix):
    """The omohyoid, two bellies joined by a tendon (Gray's): the inferior belly, a flat narrow band from the
    upper border of the scapula beside the scapular notch, forward and a little up across the root of the neck
    behind the sternocleidomastoid, where it becomes tendinous and turns; the superior belly from there almost
    straight up, close to the outer border of the sternohyoid, to the lower border of the body of the hyoid,
    lateral to the sternohyoid's insertion. The tendon is held down by a band of fascia, at about the level of
    the cricoid cartilage. No scan labels it. Here each belly is 9 by 4 mm at its thickest and the tendon 3 mm."""
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    one = lambda pat: np.concatenate([v for v, f in get(pat)])
    lat = np.array([sg, 0.0, 0.0])
    sc = one(f"^scapula_{s}$")
    x = sc @ lat
    tops = []                                        # its upper border, from the medial angle outward
    for a in np.arange(x.min() + 0.004, x.min() + 0.07, 0.004):
        band = sc[np.abs(x - a) < 0.003]
        tops.append(band[band[:, 1].argmax()])
    tops = np.array(tops)
    notch = int(tops[2:, 1].argmin()) + 2            # the border's lowest: the notch
    origin = tops[max(notch - 1, 0)] + [0, 0.0006, 0]
    cric = one(r"^cricoid_cartilage$")
    turn = np.array([(cric[:, 0].min() + cric[:, 0].max()) / 2 + sg * 0.031, (cric[:, 1].min() + cric[:, 1].max()) / 2,
                     cric[:, 2].min() - 0.0005])     # on the great vessels, outside the cricoid
    hy = one(r"^hyoid(_bone)?$")
    body = hy[hy[:, 2] > hy[:, 2].max() - 0.008]
    mid = (body[:, 0].min() + body[:, 0].max()) / 2
    at = body[np.abs(body[:, 0] - (mid + sg * 0.015)) < 0.003]
    to = np.array([mid + sg * 0.015, at[:, 1].min() + 0.0005, at[at[:, 1] < at[:, 1].min() + 0.002][:, 2].max()])
    cart = one(r"^thyroid_cartilage$")
    face = cart[(sg * (cart[:, 0] - mid) > 0.006) & (np.abs(cart[:, 1] - (turn[1] + to[1]) / 2) < 0.004)]
    on = face[face[:, 2] > face[:, 2].max() - 0.012]   # the fore part of the lamina's side, half way up
    up = np.array([(on @ lat).max() * sg + sg * 0.006, (turn[1] + to[1]) / 2, on[:, 2].mean() + 0.003])
    sca = np.concatenate([v for v, f in _named(nodes, made, prefix, ("scalenus_medius", "scalenus_anterior"), s)]
                         or [one(f"^rib_1_{s}$")])
    lev = sca[np.abs(sca[:, 1] - (turn[1] - 0.004)) < 0.006]           # the scalenes where it crosses them
    across = np.array([sg * ((lev @ lat).max() + 0.005), turn[1] - 0.004, lev[lev @ lat > (lev @ lat).max() - 0.006][:, 2].mean()])
    course = [origin, across, turn, up, to]
    from anatomy_tendons import spline
    C = spline(course)
    at = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    st = at[np.linalg.norm(C - turn, axis=1).argmin()]
    bell = lambda q: np.sin(np.pi * min(max(q, 0.0), 1.0)) ** 0.5
    def axis(big, thin=0.0015):
        def r(q, length):
            if q < st - 0.008:
                return thin + (big - thin) * bell(q / (st - 0.008))
            if q <= st + 0.008:
                return thin
            return thin + (big - thin) * bell((q - st - 0.008) / (length - st - 0.008))
        return r
    v, f = rope(course, [0.0, 1.0, 0.0], axis(0.0045), axis(0.002))
    return v, f, 0.0


def strap_geniohyoid(nodes, made, s, prefix):
    """The geniohyoid, a narrow muscle above the mylohyoid (Gray's): from the inferior mental spine on the back
    of the symphysis of the mandible, back and a little down, beside its fellow, to the front of the body of the
    hyoid. No scan labels it. Here it is 10 by 7 mm at its thickest."""
    sg = 1.0 if s == "L" else -1.0
    one = lambda pat: np.concatenate([v for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))])
    jaw = one(r"^mandible$")
    chin = jaw[jaw[:, 2] > jaw[:, 2].max() - 0.03]
    mid = chin[chin[:, 1] < chin[:, 1].min() + 0.003][:, 0].mean()
    col = chin[np.abs(chin[:, 0] - mid) < 0.003]
    low = col[:, 1].min()
    at = col[np.abs(col[:, 1] - (low + 0.0125)) < 0.002]           # the spine: a third of the way up the symphysis
    origin = np.array([mid + sg * 0.004, low + 0.0125, at[:, 2].min() - 0.0008])
    hy = one(r"^hyoid(_bone)?$")
    body = hy[hy[:, 2] > hy[:, 2].max() - 0.008]
    hmid = (body[:, 0].min() + body[:, 0].max()) / 2
    front = body[np.abs(body[:, 0] - (hmid + sg * 0.006)) < 0.003]
    to = np.array([hmid + sg * 0.006, front[:, 1].max() - 0.003, front[:, 2].max() + 0.0006])
    bell = lambda q: 0.35 + 0.65 * np.sin(np.pi * min(max(q, 0.0), 1.0)) ** 0.6
    v, f = rope([origin, to], [1.0, 0.0, 0.0], lambda q, n: 0.005 * bell(q / n) - 0.0006, lambda q, n: 0.0035 * bell(q / n))
    return v, f, 0.0


def strap_mylohyoid(nodes, made, s, prefix):
    """The mylohyoid, the flat sheet that with its fellow floors the mouth (Gray's): from the whole of the
    mylohyoid line of the mandible, from the symphysis to the last molar tooth; its hinder fibres medialward and
    a little down to the body of the hyoid, the middle and fore ones to a median raphe that runs from the
    symphysis to the hyoid. It lies below the geniohyoid, and the anterior belly of the digastric (drawn after it)
    below it. No scan labels it. Here it is a sheet 2.5 mm thick."""
    sg = 1.0 if s == "L" else -1.0
    get = lambda pat: [(v, f) for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))]
    jawS = Surface(meshes=get(r"^mandible$"), h=0.0007)
    jaw = jawS.P
    chin = jaw[jaw[:, 2] > jaw[:, 2].max() - 0.03]
    mid = chin[chin[:, 1] < chin[:, 1].min() + 0.003][:, 0].mean()
    lat = np.array([sg, 0.0, 0.0])
    inner = jaw[(jawS.N @ -lat > 0.25) & (sg * (jaw[:, 0] - mid) > 0.003)]     # the body's inner (lingual) face
    col = chin[np.abs(chin[:, 0] - mid) < 0.003]
    z_front = col[np.abs(col[:, 1] - (col[:, 1].min() + 0.008)) < 0.002][:, 2].min()
    line = [np.array([mid + sg * 0.003, col[:, 1].min() + 0.007, z_front - 0.0003])]
    for k, z in enumerate(np.linspace(z_front - 0.004, z_front - 0.034, 9)):   # the mylohyoid line: low in front, high behind
        band = inner[np.abs(inner[:, 2] - z) < 0.002]
        band = band[band[:, 1] < np.percentile(band[:, 1], 70)]           # the body, not the teeth's sockets
        y = band[:, 1].min() + 0.0075 + 0.0016 * k
        at = band[np.abs(band[:, 1] - y) < 0.0015]
        line.append(np.array([sg * (sg * at[:, 0]).min() - sg * 0.0006, y, z]))
    line = np.array(line)
    line[1:-1] = (line[:-2] + 2 * line[1:-1] + line[2:]) / 4              # the line is a smooth ridge
    hy = np.concatenate([v for v, f in get(r"^hyoid(_bone)?$")])
    body = hy[hy[:, 2] > hy[:, 2].max() - 0.008]
    hmid = (body[:, 0].min() + body[:, 0].max()) / 2
    upper = lambda x: body[np.abs(body[:, 0] - x) < 0.003]
    b0, b1 = upper(hmid + sg * 0.001), upper(hmid + sg * 0.007)     # the body's middle: the digastric passes outside it
    raphe = [np.array([mid + sg * 0.0006, col[:, 1].min() + 0.007, z_front - 0.0003]),
             np.array([hmid + sg * 0.0006, b0[:, 1].min() + 0.002, b0[:, 2].max() + 0.0005]),
             np.array([hmid + sg * 0.007, b1[:, 1].min() + 0.002, b1[:, 2].max() + 0.0005])]
    d = np.linalg.norm(raphe[1] - raphe[0])          # the fore two thirds of the fibres to the raphe, the rest to the bone
    ins = np.vstack([raphe[0] + (raphe[1] - raphe[0]) * np.linspace(0, 1, 7)[:, None], raphe[2][None]])
    under = Surface(meshes=_named(nodes, made, prefix, ("geniohyoid",), "L") + _named(nodes, made, prefix, ("geniohyoid",), "R")
                    or get(r"^hyoid(_bone)?$"), h=0.0007)
    return draped([line, ins], [0.0, -1.0, 0.0], None, lambda u: 0.0025, under, step=0.002, around=0.0015)


def strap_stylohyoid(nodes, made, s, prefix):
    """The stylohyoid, a slender muscle in front of and above the digastric's posterior belly (Gray's): from the
    back and outer side of the styloid process near its base, down and forward to the body of the hyoid where
    the greater horn joins it; the digastric's tendon passes through it near its insertion. No scan labels it.
    Here it is a spindle 5 mm thick."""
    sg = 1.0 if s == "L" else -1.0
    one = lambda pat: np.concatenate([v for n, (pid, st, v, f) in nodes.items() if re.search(pat, short(n))])
    lat = np.array([sg, 0.0, 0.0])
    tip, temporal, _ = mastoid(nodes, s)
    t = temporal.P
    inn = t[t @ lat < tip @ lat - 0.008]
    low = inn[inn[:, 1] < inn[:, 1].min() + 0.004].mean(0)        # the styloid's tip: the lowest of the bone inside the mastoid
    d, i = temporal.tree.query(low + [0, 0.008, -0.002] + lat * 0.002)   # its back and outer side, towards the base
    origin = temporal.P[i] + temporal.N[i] * 0.0012
    hy = one(r"^hyoid(_bone)?$")
    body = hy[hy[:, 2] > hy[:, 2].max() - 0.008]
    mid = (body[:, 0].min() + body[:, 0].max()) / 2
    at = hy[np.abs(hy[:, 0] - (mid + sg * 0.017)) < 0.003]
    to = np.array([mid + sg * 0.0185, at[:, 1].max() - 0.002, at[:, 2].max() - 0.002])
    bell = lambda q: 0.4 + 0.6 * np.sin(np.pi * min(max(q, 0.0), 1.0)) ** 0.6
    v, f = rope([origin, to], lat, lambda q, n: 0.0026 * bell(q / n), lambda q, n: 0.0022 * bell(q / n))
    return v, f, 0.0


DRAWN = {"sterno_thyroid": strap_sternothyroid, "posterior_scalene": strap_scalenus_posterior,
         "digastric": strap_digastric, "levator_scapulae": strap_levator_scapulae, "thyrohyoid": strap_thyrohyoid,
         "sternohyoid": strap_sternohyoid, "omohyoid": strap_omohyoid, "geniohyoid": strap_geniohyoid,
         "mylohyoid": strap_mylohyoid, "stylohyoid": strap_stylohyoid}


# MARK: the bodies

def body_nodes(folder, body):
    from anatomy_fibres import read_part
    out = {}
    for part in body["parts"]:
        path = os.path.join(folder, part["file"])
        for st, (v, f) in zip(part["structures"], read_part(path)):
            out[st["node"]] = (part["id"], st, v, f)
    return out


BONE_PARTS = ("skull", "vertebral-column", "shoulders", "ribs", "sternum", "hyoid", "larynx")
SOFT_PARTS = ("thyroid", "oesophagus", "airways", "mouth", "tonsils", "vessels", "larynx-muscles", "back-muscles")


def open_share(f):
    """The share of a mesh's edges on its border: an open sheet (the tongue's surfaces, the palate's) has no
    inside to keep out of."""
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
    _, c = np.unique(e, axis=0, return_counts=True)
    return float(np.mean(c == 1))
NOT_IN_SCAN = re.compile(r"thyroid_cartilage|hyoid")   # attachments the scan's masks lack: no touch asked there


def make_body(folder, body, quiet):
    """The muscles this body lacks, made: {node: (structure, part id, positions, triangles)}, and notes."""
    sex = body["id"]
    scan = SUBJECT[sex]
    nodes = body_nodes(folder, body)
    have = {n for n, (pid, st, v, f) in nodes.items() if st.get("made") == MARK}
    if os.environ.get("MORE_REDO"):     # development only: made again (those of MORE_MUSCLES, or all)
        again = os.environ.get("MORE_MUSCLES")
        again = {m[2] for m in MUSCLES if m[1] in again.split(",")} if again else None
        have = {n for n in have if again is not None and re.sub(r"^TS_|_[LR]$", "", n) not in again}
    prefix = "TS_"
    todo = [m for m in MUSCLES if any(f"{prefix}{m[2]}_{s}" not in have for _, s in SIDES)]
    if not todo:
        return {}, [f"{sex}: made already"]
    t0 = time.time()
    say = (lambda *a: None) if quiet else log
    meshes = scan_surfaces(os.path.join(CT, scan))
    say(f"  {sex}: the scan's masks meshed, {time.time() - t0:.0f} s")
    w = warp_for(nodes, sex, meshes, quiet)
    say(f"  {sex}: the warp, {time.time() - t0:.0f} s")
    lo_y = min(float(v[:, 1].min()) for n, (pid, st, v, f) in nodes.items() if pid == "skull") - 0.25
    near = {n: x for n, x in nodes.items() if x[2][:, 1].max() > lo_y and not x[1].get("inner")}
    bones = {n: outward_samples(v, f, 0.0006) for n, (pid, st, v, f) in near.items()
             if pid in BONE_PARTS and st.get("tissue") in ("bone", "cartilage")}
    soft = [outward_samples(v, f, 0.0008) for n, (pid, st, v, f) in near.items()
            if pid in SOFT_PARTS and st.get("tissue") not in ("bone",) and open_share(f) <= 0.02
            and not re.search(YIELD, short(n))]
    skin = [outward_samples(v, f, 0.0015) for n, (pid, st, v, f) in near.items() if pid == "skin"]
    say(f"  {sex}: {len(bones)} bones and cartilages, {len(soft)} soft structures to keep out of, "
        f"{time.time() - t0:.0f} s")
    # the scan's own bones, for where each muscle touched bone in the scan
    scan_bone = Surface([m for n, m in meshes.items() if m is not None and n not in ("trachea", "thyroid_gland", "esophagus")],
                        h=0.0008)
    made, notes = {}, []
    placed = [outward_samples(*nodes[n][2:4], 0.0008) for n in sorted(have)]     # those kept: all to keep out of
    by_mask = {m[1]: m for m in MUSCLES}
    some = os.environ.get("MORE_MUSCLES")   # development only: some of the muscles
    for mask in ORDER:
        if some and mask not in some.split(",") and not os.environ.get("MORE_REDO"):
            continue
        task, _, node, label, uberon, pid, group, o_pat, i_pat = by_mask[mask]
        for side, s in SIDES:
            t1 = time.time()
            name = f"{prefix}{node}_{s}"
            pick = lambda pat: [x for n, x in bones.items() if re.search(pat, short(n)) and side_of(n) in (None, s)]
            o_b, i_b = pick(o_pat), pick(i_pat)
            if not o_b or not i_b:
                notes.append(f"{sex} {name}: no {'origin' if not o_b else 'insertion'} bone in this body, not made")
                say("   " + notes[-1])
                continue
            if name in have:
                continue
            fellow = made.get(f"{prefix}{node}_L") if s == "R" and mask not in DRAWN else None
            if fellow is not None:          # the right as the left's mirror image, on its own bones
                lv, lf = fellow[2], fellow[3]
                box = (lv.min(0) * [-1, 1, 1] - [0.06, 0.06, 0.06], lv.max(0) * [-1, 1, 1] + [0.06, 0.06, 0.06])
                box = (np.minimum(*box), np.maximum(*box))
                bone = Surface(pieces=list(bones.values()), box=box)
                got = mirrored(lv, lf, bones, bone)
                if got is not None:
                    v, f, gap = got
                    others = Surface(pieces=soft + placed, box=box)
                    sk = Surface(pieces=skin, box=(box[0] - 0.02, box[1] + 0.02)) if skin else None
                    O, I = Surface(pieces=o_b, box=box), Surface(pieces=i_b, box=box)
                    before = (inside_share(v, f, bone), inside_share(v, f, others))
                    v = settle(v, f, bone, others, sk)
                    v, _ = unpoke(v, f, others, MARGIN, rounds=6, h=0.0006)
                    v, held = dent(v, f, placed)
                    v, left = unpoke(v, f, bone, GAP, rounds=6, h=0.0006)
                    v, left = unpoke(v, f, bone, GAP, rounds=12, h=0.0006, sigma=0.002, cap=0.001, local=True)
                    st = dict(fellow[0], node=name, label=f"{side} {label}")
                    made[name] = (st, pid, v, f)
                    placed.append(outward_samples(v, f, 0.0008))
                    notes.append(f"{sex} {name}: {len(f)} triangles, the left's mirror image seated "
                                 f"({'no bone near' if gap is None else f'{gap * 1000:.2f} mm off'}); in bone "
                                 f"{before[0]:.1%} -> {inside_share(v, f, bone):.2%} ({left} samples), origin "
                                 f"contact {contact(v, f, O):.0f} mm2, insertion {contact(v, f, I):.0f} mm2, in "
                                 f"others {before[1]:.1%} -> {inside_share(v, f, others):.2%}")
                    say("   " + notes[-1] + f" [{time.time() - t1:.0f} s]")
                    continue
            if mask in DRAWN:               # drawn from its attachments: the scan's mask of it is no shape
                v, f, clash = DRAWN[mask](nodes, made, s, prefix)
                if clash > 0.0005:
                    notes.append(f"{sex} {name}: {clash * 1000:.1f} mm too little room under its cover")
                    say("   " + notes[-1])
                box = (v.min(0) - 0.03, v.max(0) + 0.03)
                O, I = Surface(pieces=o_b, box=box), Surface(pieces=i_b, box=box)
                bone = Surface(pieces=list(bones.values()), box=box)
                others = Surface(pieces=soft + placed, box=box)
                before = (inside_share(v, f, bone), inside_share(v, f, others))
                if skin:
                    was = v
                    v = under_skin(v, f, Surface(pieces=skin, box=(box[0] - 0.02, box[1] + 0.02)))
                    moved = np.linalg.norm(v - was, axis=1)
                    if moved.max() > 0.0005:
                        notes.append(f"{sex} {name}: drawn in under the skin, {moved.max() * 1000:.1f} mm at most "
                                     f"({int((moved > 0.0005).sum())} vertices)")
                        say("   " + notes[-1])
                v, _ = unpoke(v, f, others, MARGIN, rounds=6, h=0.0006, sigma=0.002, cap=0.001, local=True)
                v, left = unpoke(v, f, bone, GAP, rounds=12, h=0.0006, sigma=0.002, cap=0.001, local=True)
                for mine, surf in ((o_b, O), (i_b, I)):
                    if contact(v, f, surf) < 4:
                        v, _ = reach_out(v, f, mine, bone)
                st = {"node": name, "label": f"{side} {label}", "uberon": f"UBERON:{uberon}", "tissue": "muscle",
                      "group": group, "inner": False, "made": MARK, "basis": "drawn from its attachments"}
                made[name] = (st, pid, v, f)
                placed.append(outward_samples(v, f, 0.0008))
                notes.append(f"{sex} {name}: {len(f)} triangles, {area(v, f) * 1e4:.0f} cm2, drawn from its "
                             f"attachments; in bone {before[0]:.1%} -> {inside_share(v, f, bone):.2%} ({left} "
                             f"samples), origin contact {contact(v, f, O):.0f} mm2, insertion "
                             f"{contact(v, f, I):.0f} mm2, in others {before[1]:.1%} -> "
                             f"{inside_share(v, f, others):.2%}")
                say("   " + notes[-1] + f" [{time.time() - t1:.0f} s]")
                continue
            m = scan_mesh(scan, task, mask, side)
            if m is None:
                notes.append(f"{sex} {name}: empty mask, not made")
                continue
            p, f = m
            p = relax(p, f, rounds=10)      # the scan's slices leave terraces
            p, f = simplify(p, f, max(600, int(area(p, f) / (np.sqrt(3) / 4 * WORK ** 2))))
            touched = np.isfinite(scan_bone.query(p, TOUCH)[1])
            v = w(p)
            box = (v.min(0) - 0.03, v.max(0) + 0.03)
            O, I = Surface(pieces=o_b, box=box), Surface(pieces=i_b, box=box)
            bone = Surface(pieces=list(bones.values()), box=box)
            others = Surface(pieces=soft + placed, box=box)
            sk = Surface(pieces=skin, box=(box[0] - 0.02, box[1] + 0.02)) if skin else None
            was = inside_share(v, f, bone)
            seat, gap = closer(*carried_bone(scan_bone, w, p), bone)
            if seat is not None:
                v = seat(v)
            if mask in UPPER_END:           # an end the scan's mask stops short of: to its own place on its bone
                v = drawn_up(v, UPPER_END[mask](nodes, s))
            before = (inside_share(v, f, bone), contact(v, f, O), contact(v, f, I), inside_share(v, f, others))
            t2 = time.time()
            v = fit(v, f, touched, (O, not NOT_IN_SCAN.search(o_pat)), (I, not NOT_IN_SCAN.search(i_pat)), bone,
                    others, sk)
            t3 = time.time()
            v, f = simplify(v, f, target_count(v, f))
            v, _ = unpoke(v, f, others, MARGIN, rounds=6, h=0.0006)
            v, held = dent(v, f, placed)
            v, left = unpoke(v, f, bone, GAP, rounds=6, h=0.0006)
            v, left = unpoke(v, f, bone, GAP, rounds=12, h=0.0006, sigma=0.002, cap=0.001, local=True)
            for mine, surf in ((o_b, O), (i_b, I)):     # an end short of its bone drawn out to it
                if contact(v, f, surf) < 4:
                    v, _ = reach_out(v, f, mine, bone)
            after = (inside_share(v, f, bone), contact(v, f, O), contact(v, f, I), inside_share(v, f, others))
            st = {"node": name, "label": f"{side} {label}", "uberon": f"UBERON:{uberon}", "tissue": "muscle",
                  "group": group, "inner": False, "made": MARK}
            made[name] = (st, pid, v, f)
            placed.append(outward_samples(v, f, 0.0008))
            notes.append(f"{sex} {name}: {len(f)} triangles, {area(v, f) * 1e4:.0f} cm2; in bone {was:.1%}, seated "
                         f"({'no bone near' if gap is None else f'{gap * 1000:.2f} mm off'}) {before[0]:.1%} -> "
                         f"{after[0]:.2%} ({left} samples), origin contact {before[1]:.0f} -> {after[1]:.0f} mm2, "
                         f"insertion {before[2]:.0f} -> {after[2]:.0f} mm2, in others {before[3]:.1%} -> "
                         f"{after[3]:.2%}")
            say("   " + notes[-1] + f" [{t2 - t1:.0f}+{t3 - t2:.0f}+{time.time() - t3:.0f} s]")
    return made, notes


def remake(folder, quiet=False):
    """Adds the head's and neck's muscles to both bodies in `folder`'s atlas; does nothing for those made
    already. Returns what it did."""
    from anatomy_fibres import write_part, sha256
    from anatomy_gaps import place
    for scan in SUBJECT.values():
        if scan in MASKS_SHA256:
            got = mask_digest(scan)
            assert got == MASKS_SHA256[scan], f"{scan}: the muscle masks are not the ones pinned ({got})"
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    only = os.environ.get("MORE_ONLY")   # development only: one body
    for body in manifest["bodies"]:
        if only and body["id"] != only:
            continue
        made, notes = make_body(folder, body, quiet)
        said += notes
        if not made:
            continue
        sex = body["id"]
        for pid, pname in PARTS.items():
            mine = {n: x for n, x in made.items() if x[1] == pid}
            if not mine:
                continue
            part = next((p for p in body["parts"] if p["id"] == pid), None)
            if part is None:
                part = {"id": pid, "name": pname, "system": "muscular", "file": f"{sex}-{pid}.atlas", "structures": []}
                place(body["parts"], part, ["knee-muscles", "hip-muscles", "back-muscles"])
                meshes = []
            else:
                from anatomy_fibres import read_part
                meshes = list(read_part(os.path.join(folder, part["file"])))
                part.pop("fibres", None)
            order = [m[2] for m in MUSCLES]
            for name, (st, _, v, f) in mine.items():
                k = next((i for i, s in enumerate(part["structures"]) if s["node"] == name), None)
                st = dict(st, triangles=int(len(f)))
                if k is None:
                    part["structures"].append(st); meshes.append((v, f))
                else:
                    part["structures"][k] = st; meshes[k] = (v, f)
            rank = lambda s: (order.index(re.sub(r"^TS_|_[LR]$", "", s["node"])) if re.sub(r"^TS_|_[LR]$", "", s["node"]) in order
                              else len(order), s["node"])
            both = sorted(zip(part["structures"], meshes), key=lambda x: rank(x[0]))
            part["structures"] = [s for s, _ in both]
            meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for _, (v, f) in both]
            lo, hi = write_part(os.path.join(folder, part["file"]), meshes)
            part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
            part["sha256"] = sha256(os.path.join(folder, part["file"]))
            part["triangles"] = int(sum(s["triangles"] for s in part["structures"]))
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
    src = {"id": "totalsegmentator-muscles", "title": "TotalSegmentator 2.18.0, its head_muscles and headneck_muscles "
           "tasks (run on the dataset's scans s1803 and s1764)", "creators": "Jakob Wasserthal et al.",
           "url": "https://github.com/wasserth/TotalSegmentator", "licence": "Apache-2.0",
           "licenceURL": "https://www.apache.org/licenses/LICENSE-2.0", "doi": None,
           "basis": "The masks the two tasks gave for the two scans; sha256 is of the lines \"<scan> <its "
                    "masks' digest>\", the digests those pinned in tools/anatomy_muscles_more.py",
           "sha256": hashlib.sha256("".join(f"{scan} {MASKS_SHA256[scan]}\n" for scan in sorted(MASKS_SHA256))
                                    .encode()).hexdigest()}
    manifest["sources"] = [s for s in manifest.get("sources", []) if s.get("id") != src["id"]] + [src]
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    n = sum(1 for line in said if "triangles" in line)
    ends = reach(folder, quiet)
    glands = give_way(folder, quiet)
    return (f"{n} muscles of the head and neck made" if n else "; ".join(said)) + "; " + ends + "; " + glands


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
