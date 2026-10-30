#!/usr/bin/env python3
"""Make the 3D anatomy atlas (ios/RedPen/Resources/Anatomy) from the Human
Reference Atlas's male and female reference organ sets, the NIH 3D skull of
the Visible Human Male and four TotalSegmentator CT scans, the same way
every time.

    python3 -I tools/anatomy_atlas.py \\
        --male 3d-vh-m-united.glb --female 3d-vh-f-united.glb \\
        --crosswalk asct-b-3d-models-crosswalk.csv \\
        --skull 3DPX-020591.glb --ct <folder holding s1803/, s1764/, s1880/ and s1767/> \\
        [--out ios/RedPen/Resources/Anatomy]

Every input is CC BY 4.0 (HuBMAP Human Reference Atlas; NIH 3D 3DPX-020591;
TotalSegmentator v3.0.0); where each comes from, its SHA-256 and the credit
it asks for are in Resources/Anatomy/SOURCES.md, and the inputs themselves
are not kept in the repository. Each organ set is one body (the Visible
Human Male, the Visible Human Female), in metres with y up and the origin
near the hips, so every part lands where it belongs in its body. What the
organ sets lack (the skull, ribs, sternum, shoulder girdle, the bones of the
arms, hands and feet, hip and deep back muscles, thyroid, adrenals,
oesophagus, stomach) is added by tools/anatomy_gaps.py, tools/anatomy_limbs.py
and tools/anatomy_feet.py,
fitted into each body and kept clear of what is already there; see their
headers.

Repairs on the way (checked by rendering the result single-sided, as the
app draws it): stray debris left out; each structure simplified piece by
piece, never below a floor, so thin rings and lobules keep their shape;
open edges kept where they are, so pieces that meet (the lung's segments,
the femur and its cartilage) stay sealed; and the patches that close the
femur's lower end, which the organ sets keep apart, put back.

Writes, per part (an organ or a group of structures, e.g. the vertebral
column):

    <body>-<part>.atlas
                   the structures' meshes, simplified to the part's triangle
                   budget, positions quantised to 16 bits over the file's
                   bounds (format below; read by Shared/Sciences/AnatomyAtlas.swift)
    anatomy.json   the manifest: the sources and their licences, and per body
                   its parts, their structures with label, UBERON id, tissue
                   and layer

.atlas, little-endian:

    "SAT1"                       magic
    u32 count                    structures, in the manifest's order
    f32 min x y z, max x y z     bounds of every position in the file, metres
    count times:
      u32 vertices, u32 triangles
      u16 x 3 per vertex         position: min + q / 65535 x (max - min)
      u16 (or u32 when vertices > 65535) x 3 per triangle, counter-clockwise
      zero padding to a multiple of 4 bytes

Normals are not stored: the app makes smooth ones from the triangles.

Needs numpy and fast-simplification 0.2 (MIT; PyPI), and for the added
parts scipy, scikit-image and nibabel (BSD and MIT; PyPI). The inputs are
downloaded files: run this with python3 -I from outside the folder they are
in.
"""
import argparse
import csv
import hashlib
import json
import os
import re
import struct
import sys

import numpy as np
import fast_simplification

CROSSWALK_SHA256 = "54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06"

# The two bodies, each one organ set: the Visible Human Male and Female,
# each in its own frame (metres, x to the body's left, y up, z forward).
BODIES = {
    "male": {
        "name": "Male",
        "prefix": "VH_M_",
        "sha256": "fae3ac193835e9e24cd13a0d0f11e6788183b290b0691b9b83ec81d907d94581",
        "frame": "The Visible Human Male: metres, x to the body's left, y up, z forward, origin near the hips",
        "source": {
            "id": "hra-united-male-v1.10",
            "title": "3D Reference Organ Set for Male, v1.10",
            "creators": "Kristen Browne and Heidi Schlehlein (HuBMAP Human Reference Atlas)",
            "doi": "https://doi.org/10.48539/HBM833.WZWN.425",
            "url": "https://cdn.humanatlas.io/digital-objects/ref-organ/united-male/v1.10/assets/3d-vh-m-united.glb",
            "licence": "CC BY 4.0",
            "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
            "basis": "The Visible Human Male, U.S. National Library of Medicine",
        },
    },
    "female": {
        "name": "Female",
        "prefix": "VH_F_",
        "sha256": "95f0c3d2f918582608692ca1139e8bdb18c147a16470e9ee9af8b276bd77c422",
        "frame": "The Visible Human Female: metres, x to the body's left, y up, z forward, origin near the hips",
        "source": {
            "id": "hra-united-female-v1.10",
            "title": "3D Reference Organ Set for Female, v1.10",
            "creators": "Kristen Browne and Heidi Schlehlein (HuBMAP Human Reference Atlas)",
            "doi": "https://doi.org/10.48539/HBM637.DWBM.744",
            "url": "https://cdn.humanatlas.io/digital-objects/ref-organ/united-female/v1.10/assets/3d-vh-f-united.glb",
            "licence": "CC BY 4.0",
            "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
            "basis": "The Visible Human Female, U.S. National Library of Medicine",
        },
    },
}
CROSSWALK = {
    "id": "hra-crosswalk-v1.10",
    "title": "ASCT+B Tables to 3D Reference Object Library Mapping, v1.10",
    "creators": "Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy Börner",
    "doi": "https://doi.org/10.48539/HBM626.BRWN.943",
    "url": "https://cdn.humanatlas.io/digital-objects/ref-organ/asct-b-3d-models-crosswalk/v1.10/assets/asct-b-3d-models-crosswalk.csv",
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
}

# The parts, in the order the app lists them: (id, name, system, the organ
# set's group nodes in each body, triangle budget). A group written "*_x"
# is "VH_M_x" in the male body and "VH_F_x" in the female; a body without
# the part leaves it out. A budget is spread over the part's structures by
# their size, never below a floor that keeps a small one recognisable.
BOTH = ("male", "female")
PARTS = [
    ("skin", "Skin", "integumentary", BOTH, ["*_skin"], 24000),
    ("breasts", "Breasts", "reproductive", ("female",), ["*_mammary_gland"], 12000),
    ("brain", "Brain", "nervous", BOTH, ["Allen_brain"], 42000),
    ("spinal-cord", "Spinal cord", "nervous", BOTH, ["*_spinal_cord"], 4000),
    ("optic-nerves", "Optic nerves", "nervous", BOTH, ["*_nerves_of_eye"], 1200),
    ("eyes", "Eyes", "special senses", BOTH, ["*_eyes"], 9000),
    ("heart", "Heart", "cardiovascular", BOTH, ["*_heart"], 16000),
    ("vessels", "Blood vessels", "cardiovascular", BOTH, ["*_blood_vasculature"], 46000),
    ("larynx", "Larynx", "respiratory", BOTH, ["*_larynx"], 3000),
    ("airways", "Trachea and bronchi", "respiratory", BOTH, ["*_tracheobronchial_tree"], 12000),
    ("lungs", "Lungs", "respiratory", BOTH, ["*_lungs"], 20000),
    ("mouth", "Mouth", "digestive", BOTH, ["*_mouth"], 14000),
    ("liver", "Liver", "digestive", BOTH, ["*_liver"], 12000),
    ("gallbladder", "Gallbladder", "digestive", BOTH, ["*_gallbladder_"], 1000),
    ("biliary-tree", "Bile and pancreatic ducts", "digestive", BOTH, ["*_biliary_tree"], 2000),
    ("pancreas", "Pancreas", "digestive", BOTH, ["*_pancreas"], 3000),
    ("small-intestine", "Small intestine", "digestive", BOTH, ["*_small_intestine"], 6000),
    ("colon", "Large intestine", "digestive", BOTH, ["*_colon"], 8000),
    ("omentum", "Greater omentum", "digestive", BOTH, ["*_visceral_adipose"], 5000),
    ("tonsils", "Palatine tonsils", "lymphatic", BOTH, ["*_palatine_tonsil"], 800),
    ("spleen", "Spleen", "lymphatic", BOTH, ["*_spleen"], 3000),
    ("thymus", "Thymus", "lymphatic", BOTH, ["*_thymus"], 1200),
    ("kidneys", "Kidneys and ureters", "urinary", BOTH, ["*_upper_urinary_tract"], 14000),
    ("bladder", "Urinary bladder", "urinary", BOTH, ["*_urinary_bladder"], 2000),
    ("urethra", "Urethra", "urinary", ("male",), ["*_urethra"], 600),
    ("genital-ducts", "Vas deferens and seminal vesicles", "reproductive", ("male",), ["*_male_genital_duct"], 2000),
    ("prostate", "Prostate", "reproductive", ("male",), ["*_prostate_gland"], 4000),
    ("ovaries", "Ovaries", "reproductive", ("female",), ["*_ovary"], 600),
    ("uterine-tubes", "Uterine tubes", "reproductive", ("female",), ["*_fallopian_tube"], 2000),
    ("uterus", "Uterus", "reproductive", ("female",), ["*_uterus"], 4000),
    ("vagina", "Vagina", "reproductive", ("female",), ["*_vagina"], 1000),
    ("uterine-ligaments", "Ligaments of the uterus and ovaries", "reproductive", ("female",),
     ["*_ligaments_of_uterus_and_ovaries"], 4000),
    ("sternum", "Sternum", "skeletal", ("female",), ["*_manubrium", "*_sternum"], 1500),
    ("vertebral-column", "Vertebral column", "skeletal", BOTH, ["*_vertebral_column"], 32000),
    ("pelvis", "Pelvis", "skeletal", BOTH, ["*_pelvis"], 10000),
    ("legs", "Thigh, knee and leg", "skeletal", BOTH, ["*_lower_limb"], 16000),
    ("hyoid", "Hyoid", "skeletal", ("male",), ["*_hyoid"], 500),
    ("eye-muscles", "Muscles of the eye", "muscular", BOTH, ["*_muscles_of_eye"], 3000),
    ("larynx-muscles", "Muscles of the larynx", "muscular", ("male",), ["*_muscles_of_larynx"], 2500),
    ("knee-muscles", "Quadriceps at the knee", "muscular", BOTH, ["*_muscles_of_knee"], 3000),
]

# Structures left out: patches that lie on another structure's surface
# (landmarks, impressions) and bone inside bone, which the eye never sees.
# One of these that closes a hole in a structure drawn instead (its edge is
# that structure's edge) is not left out: it is drawn too, folded into the
# structure FOLDED names, or as itself (the female liver's bare area, the
# spleen's diaphragmatic surface).
SKIP = re.compile(
    r"_spongy_bone_|enthesis|perichondular|distal_most_point|condyle_of|epicondylar|intercondylar_fossa"
    r"|patellar_surface|trochlear_groove|impression_of_liver|bare_area_of_liver|diaphragmatic_surface|porta_hepatis")

# Patches folded into the bone they belong to, by part: (patch pattern, the
# bone's node without its side). The femur's lower end is drawn as the shaft,
# the articular cartilage and these, which fill the holes between them.
FOLDED = {
    "legs": (r"condyle|patellar_surface|trochlear_groove|intercondylar_fossa|epicondylar|perichondular|cruciate_enthesis",
             "femur"),
}

# Structures drawn only when their part is opened, by part: they sit inside
# another that is drawn by default (the liver's segments inside its capsule,
# the eye's inner layers, the kidney inside its capsule, the heart's valves
# inside its chambers).
INNER = {
    "liver": r"segment1?$|caudate_lobe|quadrate_lobe|ligament_of_liver|falciform|ligamentum_venosum|hepataduodenal",
    "eyes": r"humor|lens_|retina|fovea|macula|optic_disc|ciliary|trabecular|schlemms|ora_serrata|choroid|corneo_scleral",
    "kidneys": r"calyx|renal_pelvis|renal_column|cortex_of_kidney|renal_papilla|renal_pyramid",
    "heart": r"papillary_muscle|_valve$|interventricular_septum",
    "vertebral-column": r"nucleus_pulposus",
    "prostate": r"zone_of_prostate|zone__of_prostate|fibromuscular_stroma|prostatic_utricle|seminal_colliculus|prostate_duct",
    "small-intestine": r"papilla_of_santorini|sphincter_of|duodenal_ampulla",
    "breasts": r"mammary_lobes|lactiferous|suspensory_ligaments",
}

# Tissue, by name first and then by system; the app colours by tissue.
TISSUE_BY_NAME = [
    ("tooth", r"teeth|tooth"),
    ("fat", r"_fat_|adipose|omentum|epiploic"),
    ("skin", r"nipple|areola"),
    ("vein", r"vein|vena_cava|venous|sinus"),
    ("artery", r"arter|aorta|aortic_arch|truncus|trunk"),
    ("nerve", r"nerve|spinal_cord|dura_mater"),
    ("ligament", r"ligament|tendon|mesosalpinx|mesovarium"),
    ("cartilage", r"cartilage|meniscus|disk|nucleus_pulposus|epiglott|carina"),
    ("muscle", r"muscle|rectus|oblique|vocalis|arytenoid$|cricothyroid|cricoarytenoid|thyroarytenoid|thyroepiglottideus"),
    ("fluid", r"humor"),
    ("duct", r"duct|lactiferous|ampulla|papilla_of|sphincter|calyx|renal_pelvis|ureter|urethra|vas_deferens"),
    ("gland", r"gland|thymus|tonsil|ovary|mammary_lobes"),
    ("organ", r"uterus|uterine|uterovesical|cervix|cervical_os|vagina|fallopian|cornua|ostium"),
]
TISSUE_BY_SYSTEM = {
    "integumentary": "skin", "nervous": "brain", "special senses": "eye", "cardiovascular": "heart",
    "respiratory": "airway", "digestive": "organ", "lymphatic": "lymph", "urinary": "organ",
    "reproductive": "gland", "skeletal": "bone", "muscular": "muscle",
}
SYSTEM_TISSUE = {"lungs": "lung", "small-intestine": "gut", "colon": "gut", "mouth": "organ", "vessels": "artery"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
    length, kind = struct.unpack("<I4s", data[12:20])
    assert kind == b"JSON"
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    blength, bkind = struct.unpack("<I4s", data[offset:offset + 8])
    assert bkind == b"BIN\x00"
    return gltf, data[offset + 8:offset + 8 + blength]


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r @ np.diag(node.get("scale", [1, 1, 1]))
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


COMPONENT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC3": 3}


def accessor(gltf, binary, index):
    a = gltf["accessors"][index]
    view = gltf["bufferViews"][a["bufferView"]]
    dtype = COMPONENT[a["componentType"]]
    width = WIDTH[a["type"]]
    item = np.dtype(dtype).itemsize * width
    stride = view.get("byteStride", item)
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    raw = np.frombuffer(binary, dtype=np.uint8, count=stride * (a["count"] - 1) + item, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], item), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(dtype).reshape(a["count"], width)


def mesh_of(gltf, binary, node, world):
    """A node's triangles in the body frame: positions welded, so the
    simplifier sees one surface rather than one per glTF seam."""
    positions, faces, base = [], [], 0
    for prim in gltf["meshes"][node["mesh"]]["primitives"]:
        assert prim.get("mode", 4) == 4, "only triangle lists"
        p = accessor(gltf, binary, prim["attributes"]["POSITION"]).astype(np.float64)
        f = (accessor(gltf, binary, prim["indices"]).reshape(-1, 3) if "indices" in prim
             else np.arange(len(p)).reshape(-1, 3))
        p = np.c_[p, np.ones(len(p))] @ world.T
        positions.append(p[:, :3]); faces.append(f.astype(np.int64) + base); base += len(p)
    p = np.concatenate(positions); f = np.concatenate(faces)
    key = np.round(p / 1e-6).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    p = p[first]; f = inverse.reshape(-1)[f]
    f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 0] != f[:, 2])]
    return p, f


# A piece under this share of its structure's surface is debris; a piece
# kept is never simplified below PIECE_FLOOR triangles.
DEBRIS = 1e-3
PIECE_FLOOR = 24


def pieces(count, f):
    """Each triangle's connected piece (triangles sharing a vertex), numbered
    from 0: labels spread to the lowest vertex number until nothing changes."""
    label = np.arange(count)
    while True:
        low = label[f].min(axis=1)
        new = label.copy()
        for k in range(3):
            np.minimum.at(new, f[:, k], low)
        new = new[new]
        if np.array_equal(new, label):
            break
        label = new
    _, piece = np.unique(label[f[:, 0]], return_inverse=True)
    return piece.reshape(-1)


def area(p, f):
    return np.linalg.norm(np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]]), axis=1) / 2


def simplify_piece(p, f, target):
    # Many small pieces (the lens's zonule fibres) stop one pass short of
    # its target, so a few passes, each from where the last one stopped.
    for _ in range(4):
        if len(f) <= target * 1.15:
            break
        q, g = fast_simplification.simplify(p.astype(np.float32), f.astype(np.int32),
                                            target_reduction=1 - target / len(f), agg=9,
                                            preserve_border=True)
        if len(g) == 0 or len(g) >= len(f):
            break
        used = np.unique(g)
        remap = np.full(len(q), -1, dtype=np.int64); remap[used] = np.arange(len(used))
        p, f = q[used].astype(np.float64), remap[g]
    return p, f


def simplify(p, f, target):
    """A structure brought down to about `target` triangles piece by piece,
    each piece's share by its surface, and never under PIECE_FLOOR, so a
    ring of cartilage or a lobule of the breast keeps its shape rather than
    shattering; debris left out first."""
    piece = pieces(len(p), f)
    a = np.bincount(piece, weights=area(p, f))
    keep = a >= DEBRIS * a.sum()
    shares = np.where(keep, target * a / a[keep].sum(), 0)
    out_p, out_f, base = [], [], 0
    for k in np.flatnonzero(keep):
        g = f[piece == k]
        used = np.unique(g)
        remap = np.full(len(p), -1, dtype=np.int64); remap[used] = np.arange(len(used))
        q, g = simplify_piece(p[used], remap[g], max(PIECE_FLOOR, int(shares[k])))
        out_p.append(q); out_f.append(g + base); base += len(q)
    return np.concatenate(out_p), np.concatenate(out_f)


def crosswalk(path):
    rows = list(csv.reader(open(path, encoding="utf-8")))
    head = next(i for i, r in enumerate(rows) if r and r[0] == "anatomical_structure_of")
    out = {}
    for r in rows[head + 1:]:
        if len(r) > 4 and r[2] and r[2] not in out:
            out[r[2]] = (r[3], r[4] if r[4].startswith("UBERON:") else None)
    return out


# Where the crosswalk's label is wrong for the mesh (checked against the
# node's own name and standard anatomy), the right name, and no UBERON id
# rather than the wrong one's.
CORRECTED = {
    "VH_M_superior_mesenteric_vein": "superior mesenteric vein",
    "VH_M_superior_rectal_vein": "superior rectal vein",
    "VH_M_left_anterior_descending_artery": "anterior interventricular branch of left coronary artery (LAD)",
    "VH_M_right_apical_bronchus": "right apical segmental bronchus",
    "VH_M_right_anterior_basal_bronchus": "right anterior basal segmental bronchus",
    "VH_M_left_posetrior_basal_bronchopulmonary_segment": "left posterior basal bronchopulmonary segment",
    "VH_M_papilla_of_santorini": "minor duodenal papilla",
    "VH_M_pubis_compact_bone_L": "left pubis", "VH_M_pubis_compact_bone_R": "right pubis",
    "VH_M_ilium_compact_bone_L": "left ilium", "VH_M_ilium_compact_bone_R": "right ilium",
    "VH_M_ischium_compact_bone_L": "left ischium", "VH_M_ischium_compact_bone_R": "right ischium",
    "VH_M_dura_mater_left": "dural sheath of left optic nerve",
    "VH_M_dura_mater_right": "dural sheath of right optic nerve",
    # sides swapped in the organ set: each of these lies wholly, or runs to
    # its organ, on the other side of the body from its name
    "VH_M_left_renal_artery": "right renal artery", "VH_M_right_renal_artery": "left renal artery",
    "VH_M_vas_deferens_L": "right vas deferens", "VH_M_vas_deferens_R": "left vas deferens",
    "VH_M_thymus_lobe_L": "right lobe of thymus", "VH_M_thymus_lobe_R": "left lobe of thymus",
    # the female set: sides swapped on these, the same way
    "VH_F_pulmonary_vein_R_inf": "right inferior pulmonary vein",
    "VH_F_pulmonary_vein_L_inf": "left inferior pulmonary vein",
    "VH_F_right_round_ligament_of_uterus": "left round ligament of uterus",
    "VH_F_left_round_ligament_of_uterus": "right round ligament of uterus",
    # the female liver: the segment named superomedial lies where segment II
    # does (the male's posterolateral), and its unnamed twin where IVa does
    "VH_F_left_superomedial_segment": "left posterolateral segment",
    "VH_F_left_superomedial_segment1": "left superomedial segment",
    "VH_F_superior_rectal_vein": "superior rectal vein",
    "VH_F_left_anterior_descending_artery": "anterior interventricular branch of left coronary artery (LAD)",
    "VH_F_dura_mater_left": "dural sheath of left optic nerve",
    "VH_F_dura_mater_right": "dural sheath of right optic nerve",
    "VH_F_right_cardinal_ligament_of_uterus": "right cardinal ligament",
    "VH_F_left_cardinal_ligament_of_uterus": "left cardinal ligament",
    # the female set's "hip bone" is the ilium alone, no pubis or ischium (with
    # her scan, anatomy_gaps.whole_hips puts whole hip bones in its place)
    "VH_F_ilium_compact_bone_R": "right ilium", "VH_F_ilium_compact_bone_L": "left ilium",
    "VH_F_fat_L": "fatty tissue of left breast", "VH_F_fat_R": "fatty tissue of right breast",
    # the Visible Human Female has six lumbar vertebrae
    "VH_F_lumbar_vertebra_6": "sixth lumbar vertebra (a normal variant)",
}
# A corrected label's own UBERON id, where there is one (checked on OLS).
CORRECTED_UBERON = {
    f"VH_{x}_{bone}_compact_bone_{s}": "UBERON:" + n
    for bone, n in (("ilium", "0001273"), ("ischium", "0001274"), ("pubis", "0001275"))
    for x in "MF" for s in "LR"
}
# Parts mirrored left to right about their own middle. The Allen brain
# came into the organ set with its x axis unflipped: every structure named
# left sits on the body's right. Mirrored, each lies where its name says.
MIRRORED = {"brain"}
# Where the crosswalk's label is right but reads oddly; the UBERON id stays.
RENAMED = {
    "vertebral bone 1": "atlas (cervical vertebra 1)", "vertebral bone 2": "axis (cervical vertebra 2)",
    "heart right ventricle": "right ventricle", "heart left ventricle": "left ventricle",
    "left cardiac atrium": "left atrium", "right cardiac atrium": "right atrium",
    "left common carotid artery plus branches": "left common carotid artery",
    "great vein of heart": "great cardiac vein", "fused sacrum": "sacrum", "other urethra": "urethra",
    "trachea cartilage": "tracheal cartilages", "verumontanum": "seminal colliculus (verumontanum)",
    "left articular disk of knee joint": "left menisci", "right articular disk of knee joint": "right menisci",
    "left deferent duct": "left vas deferens", "right deferent duct": "right vas deferens",
    "marginal colic artery": "marginal artery of Drummond",
    "left female areola": "left areola", "right female areola": "right areola",
    "cornua": "cornua of uterus",
}
# Words that keep their capital: people's names and abbreviations.
PROPER = {"Drummond", "Schlemm", "Santorini", "Heschl", "Heschls", "Ammon", "Broca", "Wernicke", "LAD", "HTH"}


def label(node, crossed):
    if node in CORRECTED:
        return CORRECTED[node]
    text = crossed[0] if crossed and crossed[0] not in ("", "-") else re.sub(r"^VH_[MF]_", "", node).replace("_", " ")
    # the Allen brain's names: "Allen thalamus L"
    text = re.sub(r"^Allen ", "", text)
    text = re.sub(r" (L|R)$", "", text)
    text = text.replace(" of HTH", " of hypothalamus").replace("Heschls", "Heschl's")
    text = re.sub(r"^mammalian ", "", text).strip()
    text = " ".join(w if w in PROPER or len(w) <= 2 or not (w[:1].isupper() and w[1:].islower()) else w.lower()
                    for w in text.split())
    side = re.search(r"_(L|R)(_[a-z])?$", node)
    if side and not re.search(r"\b(left|right)\b", text):
        text = ("left " if side.group(1) == "L" else "right ") + text
    return RENAMED.get(text, text)


def tissue(part, system, node):
    name = node.lower()
    for kind, pattern in TISSUE_BY_NAME:
        if re.search(pattern, name):
            if kind in ("vein", "artery") and part not in ("vessels", "heart", "eyes"):
                continue
            return kind
    return SYSTEM_TISSUE.get(part, TISSUE_BY_SYSTEM[system])


def write_part(path, meshes):
    allp = np.concatenate([p for p, _ in meshes])
    lo, hi = allp.min(0), allp.max(0)
    span = np.where(hi - lo > 0, hi - lo, 1)
    out = bytearray(b"SAT1")
    out += struct.pack("<I", len(meshes)) + struct.pack("<6f", *lo, *hi)
    for p, f in meshes:
        q = np.clip(np.round((p - lo) / span * 65535), 0, 65535).astype("<u2")
        out += struct.pack("<II", len(p), len(f))
        out += q.tobytes()
        out += f.astype("<u2" if len(p) <= 65535 else "<u4").tobytes()
        out += b"\0" * (-len(out) % 4)
    open(path, "wb").write(out)
    return lo, hi


def edge_points(p, f):
    """The positions on a mesh's open edges (edges only one triangle has),
    rounded to a hundredth of a millimetre."""
    e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    u, c = np.unique(e, axis=0, return_counts=True)
    return set(map(tuple, np.round(p[np.unique(u[c == 1])] / 1e-5).astype(np.int64)))


def close_holes(pid, prefix, found, raw, skipped, skipped_raw):
    """The structures to draw, with the left-out patches that close a hole
    in them put back. A patch closes a hole when its edge runs along the
    drawn structures' edges: a FOLDED one touching them at all (the knee's
    patches also meet each other) is folded into its bone, any other with
    half its edge on them is drawn as itself; one lying on a surface shares
    no edge, or a few points by chance, and stays out."""
    drawn = set().union(*[edge_points(p, f) for p, f in raw])
    found, raw = list(found), list(raw)
    fold = FOLDED.get(pid)
    for (i, node, parent_label), (p, f) in zip(skipped, skipped_raw):
        mine = edge_points(p, f)
        share = len(mine & drawn) / max(1, len(mine))
        if fold and re.search(fold[0], node) and share > 0:
            side = "L" if re.search(r"_L$|left", node) else "R"
            host = next(k for k, (_, n, _) in enumerate(found) if n == f"{prefix}{fold[1]}_{side}")
            hp, hf = raw[host]
            raw[host] = (np.concatenate([hp, p]), np.concatenate([hf, f + len(hp)]))
        elif share >= 0.5:
            found.append((i, node, parent_label))
            raw.append((p, f))
    return found, raw


def build_body(sex, glb, crossed):
    """One body's parts from its organ set, each with its structures and
    their simplified meshes, not yet written."""
    body = BODIES[sex]
    got = sha256(glb)
    assert got == body["sha256"], f"{glb}: SHA-256 {got}, expected {body['sha256']} (a new release? re-pin it in SOURCES.md and here)"
    gltf, binary = load_glb(glb)
    nodes = gltf["nodes"]
    by_name = {n.get("name"): i for i, n in enumerate(nodes)}

    # world matrices, from the scene's roots down
    world = {}
    def walk(i, parent):
        world[i] = parent @ node_matrix(nodes[i])
        for c in nodes[i].get("children", []):
            walk(c, world[i])
    for r in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))

    parts = []
    for pid, name, system, bodies, groups, budget in PARTS:
        if sex not in bodies:
            continue
        found, skipped = [], []
        def collect(i, parent_label):
            n = nodes[i]
            here = n.get("name", "")
            if "mesh" in n:
                (skipped if SKIP.search(here) else found).append((i, here, parent_label))
            for c in n.get("children", []):
                collect(c, label(here, crossed.get(here)) if "mesh" not in n else parent_label)
        for group in groups:
            group = group.replace("*_", body["prefix"])
            assert group in by_name, f"{sex} {pid}: no group {group}"
            collect(by_name[group], name)
        assert found, f"{sex} {pid}: no structures under {groups}"
        raw = [mesh_of(gltf, binary, nodes[i], world[i]) for i, _, _ in found]
        found, raw = close_holes(pid, body["prefix"], found, raw, skipped,
                                 [mesh_of(gltf, binary, nodes[i], world[i]) for i, _, _ in skipped])
        if pid in MIRRORED:
            xs = np.concatenate([p[:, 0] for p, _ in raw])
            middle = (xs.min() + xs.max()) / 2
            raw = [(p * [-1, 1, 1] + [2 * middle, 0, 0], f[:, [0, 2, 1]]) for p, f in raw]
        sizes = np.array([len(f) for _, f in raw], dtype=np.float64)
        weights = sizes ** 0.75
        targets = np.minimum(sizes, np.maximum(60, budget * weights / weights.sum())).astype(int)
        meshes, structures = [], []
        for (i, node, parent_label), (p, f), target in zip(found, raw, targets):
            p, f = simplify(p, f, int(target))
            meshes.append((p, f))
            crossed_row = crossed.get(node)
            structures.append({
                "node": node,
                "label": label(node, crossed_row),
                "uberon": crossed_row[1] if crossed_row and node not in CORRECTED else CORRECTED_UBERON.get(node),
                "tissue": tissue(pid, system, node),
                "group": parent_label,
                "inner": bool(re.search(INNER[pid], node)) if pid in INNER else False,
            })
        parts.append({"id": pid, "name": name, "system": system, "structures": structures, "meshes": meshes})
    return parts


def write_body(sex, parts, out):
    """Writes each part's <sex>-<part>.atlas into out; returns the manifest's entry for the body."""
    body, entries, total = BODIES[sex], [], 0
    for part in parts:
        file = f"{sex}-{part['id']}.atlas"
        path = os.path.join(out, file)
        lo, hi = write_part(path, part["meshes"])
        structures = [dict(s, triangles=int(len(f))) for s, (_, f) in zip(part["structures"], part["meshes"])]
        triangles = sum(s["triangles"] for s in structures)
        total += triangles
        entries.append({
            "id": part["id"], "name": part["name"], "system": part["system"], "file": file,
            "bytes": os.path.getsize(path), "sha256": sha256(path), "triangles": triangles,
            "bounds": [round(float(v), 5) for v in (*lo, *hi)],
            "structures": structures,
        })
        print(f"{sex:6} {part['id']:18} {len(structures):4} structures {triangles:7} triangles {os.path.getsize(path):9} bytes")
    print(f"{sex}: {total} triangles in {len(entries)} parts")
    return {"id": sex, "name": body["name"], "frame": body["frame"], "source": body["source"]["id"], "parts": entries}


# The manifest's account of the changes made ({scales}: each body's brain scale).
CHANGES = (
    "Structures simplified to a triangle budget per part, piece by piece with their open edges kept, "
    "positions quantised to 16 bits; stray debris, surface patches and inner spongy bone left out, but "
    "the patches that close a hole put back (the femur's lower end, the spleen's diaphragmatic surface, "
    "the female liver's bare area); the brain mirrored left to right so each side lies where its name "
    "says, and scaled ({scales}) about a point between the medulla's foot and the optic chiasm so it fits "
    "inside the skull; labels and UBERON ids from the crosswalk, corrected where wrong for the mesh "
    "(sides swapped on the renal arteries, vas deferens and thymus lobes); the female set's placenta, "
    "which sits outside the body, left out. Added: the Visible Human skull, placed by its eyes and upper "
    "teeth, kept under the skin, and carried onto the female head by a warp fitted on the head's skin, "
    "neck vertebrae, eyes and teeth; ribs, costal cartilages, the male sternum, clavicles, scapulae, "
    "humeri, the hip and deep back muscles, thyroid, adrenals, oesophagus and stomach meshed from two "
    "TotalSegmentator CT scans and carried into each body by a warp fitted on the structures both have; "
    "the female set's hip bones, its ilia alone, replaced by her scan's whole ones, each fitted to her "
    "ilium and femoral head by a similarity, the two pubic bones brought together at the midline; the rib "
    "cage widened smoothly to clear the lungs and liver, the shoulders lowered under the skin, the humeri "
    "laid along the arms, and the rest pushed out of the organs and bones they cut into; the radius, "
    "ulna, carpus, metacarpals and phalanges found by density in the CT of one forearm and hand per body "
    "(a third scan for the man's), each humerus lengthened or shortened so its elbow sits where the "
    "scan's own arm would bend, the forearm set on it at the elbow and posed into the skin's hand, finger "
    "by finger, the other side their mirror image; the tarsals, metatarsals, phalanges and the great "
    "toe's sesamoids found the same way in the CT of one foot per body (a fourth scan for the man's), set "
    "on the body's tibia and fibula at the ankle and fitted into the skin's foot, toe by toe, the other "
    "side their mirror image."
)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--male", required=True, help="3d-vh-m-united.glb")
    ap.add_argument("--female", required=True, help="3d-vh-f-united.glb")
    ap.add_argument("--crosswalk", required=True)
    ap.add_argument("--skull", required=True, help="the NIH 3D 3DPX-020591 GLB (see anatomy_gaps.py)")
    ap.add_argument("--ct", required=True, help="a folder holding the TotalSegmentator scans s1803, s1764, s1880 and s1767, one folder each")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "RedPen", "Resources", "Anatomy"))
    a = ap.parse_args()
    got = sha256(a.crosswalk)
    assert got == CROSSWALK_SHA256, f"{a.crosswalk}: SHA-256 {got}, expected {CROSSWALK_SHA256}"
    crossed = crosswalk(a.crosswalk)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import anatomy_gaps
    bodies = {sex: build_body(sex, getattr(a, sex), crossed) for sex in BOTH}
    anatomy_gaps.extend(bodies, a.skull, a.ct, sys.modules[__name__])
    os.makedirs(a.out, exist_ok=True)
    # the files of the one-body atlas (format 1), and parts no longer made
    for old in os.listdir(a.out):
        if old.endswith(".atlas"):
            os.remove(os.path.join(a.out, old))
    ct = dict(anatomy_gaps.CT_SOURCE, sha256=hashlib.sha256("".join(
        f"{s} {anatomy_gaps.CT_SHA256[s]}\n" for s in sorted(anatomy_gaps.CT_SHA256)).encode()).hexdigest())
    scales = ", ".join(f"{sex} {anatomy_gaps.RESULTS[sex + ' brain scale']}" for sex in BOTH)
    manifest = {
        "format": 2,
        "sources": [dict(BODIES[s]["source"], sha256=BODIES[s]["sha256"]) for s in BOTH]
                   + [dict(CROSSWALK, sha256=CROSSWALK_SHA256), anatomy_gaps.SKULL_SOURCE, ct],
        "changes": CHANGES.format(scales=scales),
        "bodies": [write_body(sex, bodies[sex], a.out) for sex in BOTH],
    }
    json.dump(manifest, open(os.path.join(a.out, "anatomy.json"), "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
