#!/usr/bin/env python3
"""The skeletal muscles of the trunk and lower limb, made for both atlas bodies from a muscle-by-muscle labelling
of the bodies' scans. Batch 2 of the full muscular system (batch 1, the head and neck: anatomy_muscles_more.py).

    remake(folder, quiet=False)     adds them to <folder>'s atlas (anatomy.json and its part files)
    anatomy_muscles_body.py <atlas folder>

Run before the fibres (tools/anatomy_fibres.py lays them). Each muscle made carries "made": MARK in the manifest,
so a second run makes only what is missing.

Source: the MuscleMap Toolbox's contrast-agnostic whole-body muscle segmentation model, version 1.4 (Wesselink,
Elliott, Kim, McKay and Weber; the weights and the code MIT; Zenodo, doi 10.5281/zenodo.21929873;
https://github.com/MuscleMap/MuscleMap), run slice by slice as the
toolbox's own mm_segment.py runs it (tools/anatomy_musclemap.py) on the CT scans s1803 (a man of 40) and s1764
(a woman of 32) of the TotalSegmentator dataset v3 (CC BY 4.0; Zenodo, doi 10.5281/zenodo.22688904): the scans
tools/anatomy_gaps.py fits each body's ribs, shoulders and hip muscles from. The label volumes are pinned by
SHA-256 (LABELS_SHA256). Where each muscle arises and inserts follows Gray, Anatomy of the Human Body, 20th ed.
(1918), in this file's own words (MUSCLES).

How, for each body:

1. Warps from the scan to the body, thin-plate splines (anatomy_gaps.register) fitted region by region on the
   bones both have: the trunk on the skull, every vertebra, the sacrum, the hip bones, the ribs, the sternum, the
   clavicles, scapulae and humeri and the tops of the femora; each lower limb on its hip bone, femur, patella,
   tibia and fibula (the last three are MuscleMap's own labels: the dataset names no bone below the femur).
2. Each muscle's label meshed (anatomy_gaps.ct_mesh), carried by its region's warp and brought down to a
   working mesh.
3. Its attachments seated on the bones Gray's gives (anatomy_muscles_more.fit): where it faces one of those
   bones closely and touched the scan's bone there, it is drawn onto the bone, the pull spread smoothly.
4. Out of every bone; out of what was placed before it, deep to superficial (ORDER), of the atlas's own
   muscles and of the vessels; inside the skin; out of the bone again last, so the bone wins.
5. Brought down to its triangles as the fibres step would leave it.

Left out here, because the atlas has them already from the dataset's own masks or the body's own model: the
glutei, the iliopsoas (MuscleMap's iliacus and psoas major), the deep back muscles (its erector spinae and
thoracolumbar multifidus) and the rectus femoris; and, made by batch 1, the sternocleidomastoid, levator scapulae
and longus colli.
"""
import hashlib, json, os, re, sys, time

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
S = "/tmp/claude-0/-home-user/da8cf5cf-b385-5646-a716-c25fc72fb88a/scratchpad"
CT = os.environ.get("MORE_CT", os.path.join(S, "ts", "subj"))            # the dataset's own masks, per scan
LABELS = os.environ.get("BODY_LABELS", os.path.join(S, "mm", "out"))     # MuscleMap's labels: <scan>.nii.gz
SUBJECT = {"male": "s1803", "female": "s1764"}
MARK = "ct-muscles-2"
LABELS_SHA256 = {"s1803": "8f767b4f33b5a188e5bb4752232b65ce89f5eae97785b063eca0dce7bbf5d59e",
                 "s1764": "db0ab935ee48cd6bf1d7e895a9eff605e81c82b2b605eb5208f0afd345a6c37a"}

PARTS = {"hip-muscles": "Muscles of the hip", "thigh-muscles": "Muscles of the thigh",
         "leg-muscles": "Muscles of the leg", "shoulder-muscles": "Muscles of the shoulder",
         "back-muscles": "Muscles of the back"}
HIP = r"^((ilium|ischium|pubis)_compact_bone|hip)_"
FOOT = r"(cuneiform|navicular|metatarsal|phalanx|calcaneus|talus|cuboid)"
# (MuscleMap's label for the left side (the right's is one more), node, label, part, group, region, the bones it
#  arises from, the bones it inserts on, where it arises, where it inserts): bones as regular expressions on node
#  names without their source's prefix, a bone of the muscle's own side or of the midline
MUSCLES = [
    # the back of the neck and the back
    (1111, "semispinalis_cervicis_and_multifidus", "semispinalis cervicis with the cervical multifidus", "back-muscles",
     "Deep muscles of the back", "trunk", r"^(thoracic_vertebra_[1-6]|cervical_vertebra_[4-7])$", r"^cervical_vertebra_[2-5]$",
     "the transverse processes of the upper five or six thoracic vertebrae; the multifidus from the articular "
     "processes of the lower four cervical", "the spinous processes of the axis to the fifth cervical vertebra"),
    (1121, "semispinalis_capitis", "semispinalis capitis", "back-muscles", "Deep muscles of the back", "trunk",
     r"^(thoracic_vertebra_[1-7]|cervical_vertebra_[4-7])$", r"^occipital_bone$",
     "the transverse processes of the upper six or seven thoracic and the seventh cervical vertebrae, and the "
     "articular processes of the fourth to sixth cervical",
     "the occipital bone between the superior and inferior nuchal lines"),
    (1131, "splenius_capitis", "splenius capitis", "back-muscles", "Deep muscles of the back", "trunk",
     r"^(cervical_vertebra_7|thoracic_vertebra_[1-4])$", r"^(temporal_bone_|occipital_bone$)",
     "the lower half of the ligamentum nuchae and the spinous processes of the seventh cervical and upper three "
     "or four thoracic vertebrae",
     "the mastoid process of the temporal bone and the lateral third of the superior nuchal line"),
    (5131, "quadratus_lumborum", "quadratus lumborum", "back-muscles", "Posterior muscles of the abdomen", "trunk",
     HIP, r"^(rib_12_|lumbar_vertebra_[1-4]$)",
     "the iliolumbar ligament and the adjacent iliac crest",
     "the lower border of the last rib and the transverse processes of the upper four lumbar vertebrae"),
    (4101, "rhomboid", "rhomboid major and minor", "back-muscles",
     "Muscles connecting the upper limb to the vertebral column", "trunk",
     r"^(cervical_vertebra_7|thoracic_vertebra_[1-5])$", r"^scapula_",
     "the lower ligamentum nuchae and the spinous processes of the seventh cervical to fifth thoracic vertebrae",
     "the vertebral border of the scapula, from the root of its spine to its inferior angle"),
    (5141, "latissimus_dorsi", "latissimus dorsi", "back-muscles",
     "Muscles connecting the upper limb to the vertebral column", "trunk",
     r"^(thoracic_vertebra_([7-9]|1[0-2])|lumbar_vertebra_\d|sacrum|ilium_|hip_|rib_(9|10|11|12)_)", r"^humerus_",
     "the spinous processes of the lower six thoracic vertebrae, the lumbodorsal fascia (and by it the lumbar and "
     "sacral spines), the back of the iliac crest and the lower three or four ribs",
     "the floor of the intertubercular groove of the humerus"),
    (1161, "trapezius", "trapezius", "back-muscles", "Muscles connecting the upper limb to the vertebral column",
     "trunk", r"^(occipital_bone|cervical_vertebra_7|thoracic_vertebra_\d+)$", r"^(clavicle_|scapula_)",
     "the external occipital protuberance and medial third of the superior nuchal line, the ligamentum nuchae "
     "and the spinous processes of the seventh cervical and all the thoracic vertebrae",
     "the lateral third of the clavicle, the acromion and the spine of the scapula"),
    # the shoulder
    (2111, "subscapularis", "subscapularis", "shoulder-muscles", "Muscles of the shoulder", "trunk",
     r"^scapula_", r"^humerus_", "the medial two-thirds of the subscapular fossa",
     "the lesser tubercle of the humerus and the front of the capsule of the shoulder joint"),
    (2101, "supraspinatus", "supraspinatus", "shoulder-muscles", "Muscles of the shoulder", "trunk",
     r"^scapula_", r"^humerus_", "the medial two-thirds of the supraspinous fossa",
     "the highest facet of the greater tubercle of the humerus"),
    (2121, "infraspinatus", "infraspinatus", "shoulder-muscles", "Muscles of the shoulder", "trunk",
     r"^scapula_", r"^humerus_", "the medial two-thirds of the infraspinous fossa",
     "the middle facet of the greater tubercle of the humerus"),
    (2141, "deltoid", "deltoid", "shoulder-muscles", "Muscles of the shoulder", "trunk",
     r"^(clavicle_|scapula_)", r"^humerus_",
     "the lateral third of the clavicle, the acromion and the lower lip of the spine of the scapula",
     "the deltoid tuberosity on the middle of the lateral side of the humerus"),
    # the hip
    (6211, "obturator_externus", "obturator externus", "hip-muscles", "Muscles of the gluteal region", "leg",
     HIP, r"^femur_", "the outer surface of the obturator membrane and the pubis and ischium around it",
     "the trochanteric fossa of the femur"),
    (6201, "obturator_internus", "obturator internus", "hip-muscles", "Muscles of the gluteal region", "leg",
     HIP, r"^femur_", "the inner surface of the obturator membrane and the bone around the obturator foramen",
     "the medial surface of the greater trochanter, above the trochanteric fossa"),
    (6221, "gemelli_and_quadratus_femoris", "gemelli and quadratus femoris", "hip-muscles",
     "Muscles of the gluteal region", "leg", HIP, r"^femur_",
     "the ischial spine (superior gemellus) and the ischial tuberosity (inferior gemellus and quadratus femoris)",
     "the medial surface of the greater trochanter with the obturator internus, and the quadrate tubercle and "
     "the line below it"),
    (6181, "piriformis", "piriformis", "hip-muscles", "Muscles of the gluteal region", "leg",
     r"^sacrum$", r"^femur_", "the front of the sacrum between and beside its second to fourth foramina",
     "the upper border of the greater trochanter"),
    (6191, "pectineus", "pectineus", "hip-muscles", "Medial femoral muscles", "leg",
     HIP, r"^femur_", "the pectineal line of the pubis and the surface in front of it",
     "the line from the lesser trochanter to the linea aspera"),
    (6131, "tensor_fasciae_latae", "tensor fasciae latae", "hip-muscles", "Muscles of the gluteal region", "leg",
     HIP, r"^tibia_", "the front of the outer lip of the iliac crest and the anterior superior iliac spine",
     "the iliotibial band, between its two layers a third of the way down the thigh; by it the lateral condyle "
     "of the tibia"),
    # the thigh
    (7111, "vastus_intermedius", "vastus intermedius", "thigh-muscles", "Anterior femoral muscles", "leg",
     r"^femur_", r"^patella_", "the front and lateral surfaces of the upper two-thirds of the femur's shaft",
     "the base of the patella by the quadriceps tendon"),
    (7201, "adductor_magnus", "adductor magnus", "thigh-muscles", "Medial femoral muscles", "leg",
     HIP, r"^femur_", "the inferior ramus of the pubis, the ramus of the ischium and the ischial tuberosity",
     "the linea aspera along its length, the medial supracondylar line and the adductor tubercle"),
    (7221, "adductor_brevis", "adductor brevis", "thigh-muscles", "Medial femoral muscles", "leg",
     HIP, r"^femur_", "the outer surface of the body and inferior ramus of the pubis",
     "the line from the lesser trochanter to the linea aspera, and the linea aspera's upper part"),
    (7211, "adductor_longus", "adductor longus", "thigh-muscles", "Medial femoral muscles", "leg",
     HIP, r"^femur_", "the front of the pubis, in the angle between its crest and symphysis",
     "the middle third of the linea aspera"),
    (7121, "vastus_medialis", "vastus medialis", "thigh-muscles", "Anterior femoral muscles", "leg",
     r"^femur_", r"^patella_", "the lower intertrochanteric line, the medial lip of the linea aspera and the "
     "medial supracondylar line", "the medial border of the patella and the quadriceps tendon"),
    (7101, "vastus_lateralis", "vastus lateralis", "thigh-muscles", "Anterior femoral muscles", "leg",
     r"^femur_", r"^patella_", "the upper intertrochanteric line, the greater trochanter and the lateral lip of "
     "the gluteal tuberosity and linea aspera", "the lateral border of the patella and the quadriceps tendon"),
    (7191, "biceps_femoris_short_head", "biceps femoris, short head", "thigh-muscles", "Posterior femoral muscles",
     "leg", r"^femur_", r"^fibula_", "the lateral lip of the linea aspera and the lateral supracondylar line",
     "the head of the fibula, with the long head"),
    (7161, "semimembranosus", "semimembranosus", "thigh-muscles", "Posterior femoral muscles", "leg",
     HIP, r"^tibia_", "the upper and lateral impression on the ischial tuberosity",
     "the groove on the back of the medial condyle of the tibia"),
    (7171, "semitendinosus", "semitendinosus", "thigh-muscles", "Posterior femoral muscles", "leg",
     HIP, r"^tibia_", "the lower and medial impression on the ischial tuberosity, with the biceps' long head",
     "the upper part of the medial surface of the tibia's shaft, behind the sartorius and below the gracilis"),
    (7181, "biceps_femoris_long_head", "biceps femoris, long head", "thigh-muscles", "Posterior femoral muscles",
     "leg", HIP, r"^fibula_", "the lower and medial impression on the ischial tuberosity, with the semitendinosus",
     "the lateral side of the head of the fibula"),
    (7151, "gracilis", "gracilis", "thigh-muscles", "Medial femoral muscles", "leg",
     HIP, r"^tibia_", "the lower half of the symphysis pubis and the upper half of the pubic arch",
     "the upper part of the medial surface of the tibia, below the condyle"),
    (7141, "sartorius", "sartorius", "thigh-muscles", "Anterior femoral muscles", "leg",
     HIP, r"^tibia_", "the anterior superior iliac spine and the upper half of the notch below it",
     "the upper part of the medial surface of the tibia, in front of the gracilis and semitendinosus"),
    # the leg
    (8111, "tibialis_posterior", "tibialis posterior", "leg-muscles", "Posterior crural muscles, deep", "leg",
     r"^(tibia|fibula)_", FOOT, "the back of the interosseous membrane and the adjoining surfaces of the tibia "
     "and fibula", "the tuberosity of the navicular, with slips to the cuneiforms, the cuboid and the second to "
     "fourth metatarsals"),
    (8201, "flexor_digitorum_longus", "flexor digitorum longus", "leg-muscles", "Posterior crural muscles, deep",
     "leg", r"^tibia_", FOOT, "the back of the tibia's shaft below the popliteal line",
     "the bases of the last phalanges of the second to fifth toes"),
    (8181, "flexor_hallucis_longus", "flexor hallucis longus", "leg-muscles", "Posterior crural muscles, deep",
     "leg", r"^fibula_", FOOT, "the lower two-thirds of the back of the fibula's shaft",
     "the base of the last phalanx of the great toe"),
    (8211, "popliteus", "popliteus", "leg-muscles", "Posterior crural muscles, deep", "leg",
     r"^femur_", r"^tibia_", "the front of the groove on the lateral condyle of the femur",
     "the medial two-thirds of the triangular surface above the popliteal line of the tibia"),
    (8121, "peroneus_longus", "peroneus longus", "leg-muscles", "Lateral crural muscles", "leg",
     r"^(fibula|tibia)_", FOOT, "the head and upper two-thirds of the lateral surface of the fibula",
     "the lateral side of the first metatarsal's base and of the first cuneiform"),
    (8191, "extensor_digitorum_and_hallucis_longus", "extensor digitorum longus and extensor hallucis longus",
     "leg-muscles", "Anterior crural muscles", "leg", r"^(tibia|fibula)_", FOOT,
     "the lateral condyle of the tibia, the front of the fibula's shaft and the interosseous membrane",
     "the second and third phalanges of the four lesser toes; the last phalanx of the great toe"),
    (8101, "tibialis_anterior", "tibialis anterior", "leg-muscles", "Anterior crural muscles", "leg",
     r"^tibia_", FOOT, "the lateral condyle and upper half of the lateral surface of the tibia's shaft, and the "
     "interosseous membrane", "the medial and under surface of the first cuneiform and the base of the first "
     "metatarsal"),
    (8131, "soleus", "soleus", "leg-muscles", "Posterior crural muscles, superficial", "leg",
     r"^(tibia|fibula)_", r"calcaneus", "the back of the head and upper third of the fibula, the popliteal line "
     "and middle third of the medial border of the tibia", "the calcaneus, by the tendo calcaneus"),
    (8221, "plantaris", "plantaris", "leg-muscles", "Posterior crural muscles, superficial", "leg",
     r"^femur_", r"calcaneus", "the lower part of the lateral prolongation of the linea aspera",
     "the back of the calcaneus, medial to the tendo calcaneus"),
    (8141, "gastrocnemius_medial_head", "gastrocnemius, medial head", "leg-muscles",
     "Posterior crural muscles, superficial", "leg", r"^femur_", r"calcaneus",
     "the back of the medial condyle of the femur and the popliteal surface above it",
     "the calcaneus, by the tendo calcaneus"),
    (8151, "gastrocnemius_lateral_head", "gastrocnemius, lateral head", "leg-muscles",
     "Posterior crural muscles, superficial", "leg", r"^femur_", r"calcaneus",
     "the lateral condyle of the femur and the back of the femur above it", "the calcaneus, by the tendo calcaneus"),
]
# UBERON ids, each looked up by the muscle's exact name (EBI Ontology Lookup Service, November 2026); a label that
# joins two muscles has none, and the two heads of the biceps femoris carry the whole muscle's
UBERON = {
    "semispinalis_capitis": "0001409", "splenius_capitis": "0000711", "quadratus_lumborum": "0001220",
    "rhomboid": "0005621", "latissimus_dorsi": "0001112", "trapezius": "0002380", "subscapularis": "0001129",
    "supraspinatus": "0002383", "infraspinatus": "0001477", "deltoid": "0001476", "obturator_externus": "0001368",
    "obturator_internus": "0011048", "piriformis": "0008529", "pectineus": "0001382",
    "tensor_fasciae_latae": "0001376", "vastus_intermedius": "0014847", "adductor_magnus": "0000370",
    "adductor_brevis": "0000368", "adductor_longus": "0000303", "vastus_medialis": "0001380",
    "vastus_lateralis": "0001379", "biceps_femoris_short_head": "0001374", "semimembranosus": "0001381",
    "semitendinosus": "0001375", "biceps_femoris_long_head": "0001374", "gracilis": "0000950",
    "sartorius": "0001373", "tibialis_posterior": "0001667", "flexor_digitorum_longus": "0001666",
    "flexor_hallucis_longus": "0001392", "popliteus": "0001391", "peroneus_longus": "0001387",
    "tibialis_anterior": "0001385", "soleus": "0001389", "plantaris": "0011905",
    "gastrocnemius_medial_head": "0011907", "gastrocnemius_lateral_head": "0011908",
}
ORDER = [m[1] for m in MUSCLES]          # the table runs deep to superficial within each region
BONES = {"patella": 7231, "tibia": 8161, "fibula": 8171}   # MuscleMap's bones (left; the right is one more)
SIDES = (("left", "L", 0), ("right", "R", 1))
BONE_PARTS = ("skull", "vertebral-column", "shoulders", "arms", "ribs", "sternum", "pelvis", "legs", "feet")
SOFT_PARTS = ("vessels", "hip-muscles", "knee-muscles", "back-muscles", "neck-muscles", "jaw-muscles")


def log(*a):
    print(*a, flush=True)


def _sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# MARK: the scan

class Labels:
    """MuscleMap's label volume of a scan: each label's mesh in the atlas frame (the scan's)."""
    def __init__(self, scan):
        import nibabel
        im = nibabel.load(os.path.join(LABELS, scan + ".nii.gz"))
        self.vol, self.affine = np.asarray(im.dataobj), im.affine
        self.boxes = ndimage.find_objects(self.vol)

    def mesh(self, value, sigma=0.8, share=0.05):
        from anatomy_gaps import ct_mesh
        box = self.boxes[value - 1] if value - 1 < len(self.boxes) else None
        if box is None:
            return None
        box = tuple(slice(max(s.start - 4, 0), s.stop + 4) for s in box)
        A = self.affine.copy()
        A[:3, 3] += self.affine[:3, :3] @ np.array([s.start for s in box], float)
        return ct_mesh(self.vol[box] == value, A, sigma=sigma, share=share)


def dataset_bones():
    names = ["skull", "sacrum", "sternum"] + [f"vertebrae_C{i}" for i in range(1, 8)] \
        + [f"vertebrae_T{i}" for i in range(1, 13)] + [f"vertebrae_L{i}" for i in range(1, 6)]
    for side, _, _ in SIDES:
        names += [f"hip_{side}", f"femur_{side}", f"clavicula_{side}", f"scapula_{side}", f"humerus_{side}"]
        names += [f"rib_{side}_{r}" for r in range(1, 13)]
    return names


def scan_surfaces(scan, labels):
    """The scan's bones meshed once: name -> (points, triangles) in the atlas frame (the scan's); the dataset's
    masks, and MuscleMap's patella, tibia and fibula."""
    from anatomy_gaps import load_mask, ct_mesh
    cache = os.environ.get("MORE_CACHE")   # development only: kept between runs
    kept = cache and os.path.join(cache, f"body_scan_{scan}.pkl")
    if kept and os.path.exists(kept):
        import pickle
        return pickle.load(open(kept, "rb"))
    out = {}
    for name in dataset_bones():
        path = os.path.join(CT, scan, name + ".nii.gz")
        if os.path.exists(path):
            a, A = load_mask(path)
            out[name] = ct_mesh(a, A, sigma=1.0, share=0.2)
    for bone, value in BONES.items():
        for side, _, k in SIDES:
            out[f"{bone}_{side}"] = labels.mesh(value + k, sigma=1.0, share=0.2)
    if kept:
        import pickle
        os.makedirs(cache, exist_ok=True)
        pickle.dump(out, open(kept, "wb"))
    return out


# MARK: the warps

def pairs(nodes, sex, scan, region):
    """(name, scan points, body points, weight, kind) on the bones both have, for a region: "trunk", "leg left"
    or "leg right". scan: name -> surface points."""
    from anatomy_gaps import sample
    from anatomy_muscles_more import short
    def body(pattern, top=None, bottom=None):
        hit = [v for n, (pid, st, v, f) in nodes.items() if st.get("tissue") == "bone" and re.search(pattern, short(n))]
        return np.concatenate(hit) if hit else None
    out = []
    def add(name, mask, target, w=1.0, n=300, top=None, low=None):
        c = scan.get(mask)
        if c is None or target is None:
            return
        if top is not None:      # the upper `top` metres of both
            c, target = c[c[:, 1] > c[:, 1].max() - top], target[target[:, 1] > target[:, 1].max() - top]
        if low is not None:      # the lower `low` metres of both
            c, target = c[c[:, 1] < c[:, 1].min() + low], target[target[:, 1] < target[:, 1].min() + low]
        out.append((name, sample(c, n), sample(target, 4 * n, 1), w, "surface"))
    if region == "trunk":
        add("skull", "skull", np.concatenate([v for n, (pid, st, v, f) in nodes.items() if pid == "skull"
                                              and not re.search(r"mandible|teeth|tooth", short(n))]), n=800)
        for i in range(1, 8):
            add(f"C{i}", f"vertebrae_C{i}", body(f"^cervical_vertebra_{i}$"), n=200)
        for i in range(1, 13):
            add(f"T{i}", f"vertebrae_T{i}", body(f"^thoracic_vertebra_{i}$"), n=200)
        lumbar = [x for x in (body(f"^lumbar_vertebra_{i}$") for i in range(1, 7)) if x is not None]
        if len(lumbar) == 5:
            for i in range(1, 6):
                add(f"L{i}", f"vertebrae_L{i}", lumbar[i - 1], n=200)
        add("sacrum", "sacrum", body("^sacrum$"), n=400)
        add("sternum", "sternum", body("^(sternum|manubrium)$"), n=300)
        for side, s, _ in SIDES:
            add(f"hip {side}", f"hip_{side}", body(HIP[:-1] + f"_{s}$"), n=500)
            add(f"femur {side}", f"femur_{side}", body(f"^femur_{s}$"), n=300, top=0.15)
            add(f"clavicle {side}", f"clavicula_{side}", body(f"^clavicle_{s}$"), n=250)
            add(f"scapula {side}", f"scapula_{side}", body(f"^scapula_{s}$"), n=500)
            add(f"humerus {side}", f"humerus_{side}", body(f"^humerus_{s}$"), n=300, top=0.16)
            for r in range(1, 13):
                add(f"rib {r} {side}", f"rib_{side}_{r}", body(f"^rib_{r}_{s}$"), n=150)
    else:
        side = region.split()[1]
        s = "L" if side == "left" else "R"
        add("sacrum", "sacrum", body("^sacrum$"), w=0.5, n=300)
        add("hip", f"hip_{side}", body(HIP[:-1] + f"_{s}$"), n=600)
        add("femur", f"femur_{side}", body(f"^femur_{s}$"), n=900)
        add("patella", f"patella_{side}", body(f"^patella_{s}$"), n=150)
        add("tibia", f"tibia_{side}", body(f"^tibia_{s}$"), n=800)
        add("fibula", f"fibula_{side}", body(f"^fibula_{s}$"), n=500)
    return out


def warp_for(nodes, sex, meshes, region, quiet):
    """A region's scan-to-body warp: one fitted loosely, then a closer one on what it left."""
    from anatomy_gaps import register, Then
    cache = os.environ.get("MORE_CACHE")   # development only: the warp kept between runs
    kept = cache and os.path.join(cache, f"body_warp_{sex}_{region.replace(' ', '_')}.pkl")
    if kept and os.path.exists(kept):
        import pickle
        return pickle.load(open(kept, "rb"))
    pts = {n: m[0] for n, m in meshes.items() if m is not None}
    found = pairs(nodes, sex, pts, region)
    if not quiet:
        log(f"  {sex}: the {region}'s warp, on {len(found)} pairs")
    w = register(found, rounds=(3e-2, 1e-2, 3e-3, 1e-3), control=3000, quiet=quiet)
    near = [(n, w(c), v, wt, k) for n, c, v, wt, k in found]
    w2 = register(near, rounds=(1e-3, 3e-4, 1e-4, 3e-5), control=3500, quiet=quiet)
    both = Then(w, w2)
    if kept:
        import pickle
        os.makedirs(cache, exist_ok=True)
        pickle.dump(both, open(kept, "wb"))
    return both


# MARK: the bodies

def make_body(folder, body, quiet):
    """The muscles this body lacks, made: {node: (structure, part id, positions, triangles)}, and notes."""
    import anatomy_muscles_more as more
    from anatomy_muscles_more import (Surface, area, carried_bone, closer, contact, fit, inside_share, mirrored,
                                      open_share, outward_samples, reach_out, relax, settle, short, side_of,
                                      simplify, target_count, unpoke, body_nodes)
    sex = body["id"]
    scan = SUBJECT[sex]
    nodes = body_nodes(folder, body)
    have = {n for n, (pid, st, v, f) in nodes.items() if st.get("made") == MARK}
    some = os.environ.get("BODY_MUSCLES")   # development only: some of the muscles, some of the sides
    sides = [x for x in SIDES if x[1] in os.environ.get("BODY_SIDES", "LR")]
    todo = [m for m in MUSCLES if any(f"TS_{m[1]}_{s}" not in have for _, s, _ in sides)
            and (not some or m[1] in some.split(","))]
    if not todo:
        return {}, [f"{sex}: made already"]
    t0 = time.time()
    say = (lambda *a: None) if quiet else log
    labels = Labels(scan)
    meshes = scan_surfaces(scan, labels)
    say(f"  {sex}: the scan's bones meshed, {time.time() - t0:.0f} s")
    regions = sorted({m[5] if m[5] == "trunk" else f"leg {side}" for m in todo for side, _, _ in sides})
    warps = {r: warp_for(nodes, sex, meshes, r, quiet) for r in regions}
    say(f"  {sex}: the warps, {time.time() - t0:.0f} s")
    near = {n: x for n, x in nodes.items() if not x[1].get("inner")}
    bones = {n: outward_samples(v, f, 0.0006) for n, (pid, st, v, f) in near.items()
             if pid in BONE_PARTS and st.get("tissue") in ("bone", "cartilage")}
    soft = [outward_samples(v, f, 0.0008) for n, (pid, st, v, f) in near.items()
            if pid in SOFT_PARTS and st.get("tissue") not in ("bone",) and st.get("made") != MARK
            and open_share(f) <= 0.02]
    skin = [outward_samples(v, f, 0.0015) for n, (pid, st, v, f) in near.items() if pid == "skin"]
    say(f"  {sex}: {len(bones)} bones and cartilages, {len(soft)} soft structures to keep out of, "
        f"{time.time() - t0:.0f} s")
    scan_bone = Surface([m for m in meshes.values() if m is not None], h=0.0008)
    made, notes, placed = {}, [], []
    for value, node, label, pid, group, region, o_pat, i_pat, arises, inserts in MUSCLES:
        for side, s, k in SIDES:
            t1 = time.time()
            name = f"TS_{node}_{s}"
            if name in have:
                placed.append(outward_samples(*nodes[name][2:4], 0.0008))
                continue
            if (some and node not in some.split(",")) or (side, s, k) not in sides:
                continue
            pick = lambda pat: [x for n, x in bones.items() if re.search(pat, short(n)) and side_of(n) in (None, s)]
            o_b, i_b = pick(o_pat), pick(i_pat)
            fellow = made.get(f"TS_{node}_L") if s == "R" else None
            if fellow is not None:          # the right as the left's mirror image, on its own bones
                lv, lf = fellow[2], fellow[3]
                coarse = float(np.clip(np.sqrt(area(lv, lf) / 0.012), 1.0, 2.2))
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
                    v = settle(v, f, bone, others, sk, h=0.0007 * coarse)
                    v, _ = unpoke(v, f, others, more.MARGIN, rounds=6, h=0.0006 * coarse)
                    v, left = unpoke(v, f, bone, more.GAP, rounds=6, h=0.0006 * coarse)
                    v, left = unpoke(v, f, bone, more.GAP, rounds=12, h=0.0006 * coarse, sigma=0.002, cap=0.001, local=True)
                    made[name] = (dict(fellow[0], node=name, label=f"{side} {label}"), pid, v, f)
                    placed.append(outward_samples(v, f, 0.0008))
                    notes.append(f"{sex} {name}: {len(f)} triangles, the left's mirror image seated "
                                 f"({'no bone near' if gap is None else f'{gap * 1000:.2f} mm off'}); in bone "
                                 f"{before[0]:.1%} -> {inside_share(v, f, bone):.2%} ({left} samples), origin "
                                 f"contact {contact(v, f, O):.0f} mm2, insertion {contact(v, f, I):.0f} mm2, in "
                                 f"others {before[1]:.1%} -> {inside_share(v, f, others):.2%}")
                    say("   " + notes[-1] + f" [{time.time() - t1:.0f} s]")
                    continue
            m = labels.mesh(value + k)
            if m is None:
                notes.append(f"{sex} {name}: no such label in the scan, not made")
                say("   " + notes[-1])
                continue
            p, f = m
            # the working mesh: batch 1's edge up to 120 cm2 of surface, then longer as the muscle is larger (to
            # 2.2 times at 580 cm2 and above), and its surface sampled as much more coarsely: the thigh's and the
            # back's muscles are ten times the neck's, and the time went with the square of their vertices
            coarse = float(np.clip(np.sqrt(area(p, f) / 0.012), 1.0, 2.2))
            p = relax(p, f, rounds=10)      # the scan's slices leave terraces
            p, f = simplify(p, f, max(600, int(area(p, f) / (np.sqrt(3) / 4 * (more.WORK * coarse) ** 2))))
            touched = np.isfinite(scan_bone.query(p, more.TOUCH)[1])
            w = warps[region if region == "trunk" else f"leg {side}"]
            v = w(p)
            box = (v.min(0) - 0.03, v.max(0) + 0.03)
            O, I = Surface(pieces=o_b, box=box), Surface(pieces=i_b, box=box)
            bone = Surface(pieces=list(bones.values()), box=box)
            others = Surface(pieces=soft + placed, box=box)
            sk = Surface(pieces=skin, box=(box[0] - 0.02, box[1] + 0.02)) if skin else None
            was = inside_share(v, f, bone)
            seat, gap = closer(*carried_bone(scan_bone, w, p), bone)     # the muscle rides with its own bones
            if seat is not None:
                v = seat(v)
            before = (inside_share(v, f, bone), contact(v, f, O), contact(v, f, I), inside_share(v, f, others))
            t2 = time.time()
            v = fit(v, f, touched, (O, True), (I, True), bone, others, sk, h=0.0007 * coarse)
            t3 = time.time()
            v, f = simplify(v, f, target_count(v, f))
            v, _ = unpoke(v, f, others, more.MARGIN, rounds=6, h=0.0006 * coarse)
            v, left = unpoke(v, f, bone, more.GAP, rounds=6, h=0.0006 * coarse)
            v, left = unpoke(v, f, bone, more.GAP, rounds=12, h=0.0006 * coarse, sigma=0.002, cap=0.001, local=True)
            for mine, surf in ((o_b, O), (i_b, I)):     # an end a little short of its bone drawn out to it
                if mine and contact(v, f, surf) < 4:
                    v, _ = reach_out(v, f, mine, bone)
            after = (inside_share(v, f, bone), contact(v, f, O), contact(v, f, I), inside_share(v, f, others))
            st = {"node": name, "label": f"{side} {label}", "tissue": "muscle", "group": group, "inner": False,
                  "made": MARK}
            if node in UBERON:
                st["uberon"] = "UBERON:" + UBERON[node]
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
    """Adds the trunk's and lower limbs' muscles to both bodies in `folder`'s atlas; does nothing for those made
    already. Returns what it did."""
    from anatomy_fibres import read_part, write_part, sha256
    from anatomy_gaps import place
    for scan in SUBJECT.values():
        if scan in LABELS_SHA256:
            got = _sha(os.path.join(LABELS, scan + ".nii.gz"))
            assert got == LABELS_SHA256[scan], f"{scan}: the labels are not the ones pinned ({got})"
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    only = os.environ.get("MORE_ONLY")   # development only: one body
    order = [m[1] for m in MUSCLES]
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
                place(body["parts"], part, ["back-muscles"])
                meshes = []
            else:
                meshes = list(read_part(os.path.join(folder, part["file"])))
                part.pop("fibres", None)
            for name, (st, _, v, f) in mine.items():
                k = next((i for i, x in enumerate(part["structures"]) if x["node"] == name), None)
                st = dict(st, triangles=int(len(f)))
                if k is None:
                    part["structures"].append(st); meshes.append((v, f))
                else:
                    part["structures"][k] = st; meshes[k] = (v, f)
            def rank(x):       # the part's own muscles first, as they were; then these, in the table's order
                base = re.sub(r"^TS_|_[LR]$", "", x["node"])
                return (1, order.index(base), x["node"]) if x.get("made") == MARK and base in order else (0, 0, "")
            both = sorted(zip(part["structures"], meshes), key=lambda x: rank(x[0]))
            part["structures"] = [x for x, _ in both]
            meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for _, (v, f) in both]
            lo, hi = write_part(os.path.join(folder, part["file"]), meshes)
            part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
            part["sha256"] = sha256(os.path.join(folder, part["file"]))
            part["triangles"] = int(sum(x["triangles"] for x in part["structures"]))
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
    src = {"id": "musclemap", "title": "MuscleMap whole-body muscle segmentation model 1.4 (run on the "
           "TotalSegmentator dataset's scans s1803 and s1764)", "creators": "Evert Onno Wesselink, James Elliott, "
           "Brian Kim, Marnee McKay, Kenneth Arnold Weber", "url": "https://github.com/MuscleMap/MuscleMap", "licence": "MIT",
           "licenceURL": "https://opensource.org/license/mit", "doi": "https://doi.org/10.5281/zenodo.21929873",
           "basis": "The labels the model gave for the two scans; sha256 is of the lines \"<scan> <its labels' "
           "digest>\", the digests those pinned in tools/anatomy_muscles_body.py",
           "sha256": hashlib.sha256("".join(f"{k} {LABELS_SHA256[k]}\n" for k in sorted(LABELS_SHA256)).encode()).hexdigest()}
    if not any(x.get("id") == src["id"] for x in manifest.get("sources", [])):
        manifest.setdefault("sources", []).append(src)
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    n = sum(1 for line in said if "triangles" in line)
    return f"{n} muscles of the trunk and lower limbs made" if n else "; ".join(said)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
