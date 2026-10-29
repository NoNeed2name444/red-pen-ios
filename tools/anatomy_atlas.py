#!/usr/bin/env python3
"""Make the 3D anatomy atlas (ios/RedPen/Resources/Anatomy) from the Human
Reference Atlas's male reference organ set, the same way every time.

    python3 -I tools/anatomy_atlas.py \\
        --glb 3d-vh-m-united.glb \\
        --crosswalk asct-b-3d-models-crosswalk.csv \\
        [--out ios/RedPen/Resources/Anatomy]

Both inputs are CC BY 4.0 (HuBMAP Human Reference Atlas); where each comes
from, its SHA-256 and the credit it asks for are in Resources/Anatomy/
SOURCES.md, and the inputs themselves are not kept in the repository. The
organ set is one body (the Visible Human Male), in metres with y up and the
origin near the hips, so every part lands where it belongs.

Writes, per part (an organ or a group of structures, e.g. the vertebral
column):

    <part>.atlas   the structures' meshes, simplified to the part's triangle
                   budget, positions quantised to 16 bits over the file's
                   bounds (format below; read by Shared/Sciences/AnatomyAtlas.swift)
    anatomy.json   the manifest: parts, their structures with label, UBERON
                   id, tissue and layer, and the source and its licence

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

Needs numpy and fast-simplification (MIT; PyPI). The inputs are downloaded
files: run this with python3 -I from outside the folder they are in.
"""
import argparse
import csv
import hashlib
import json
import os
import re
import struct

import numpy as np
import fast_simplification

GLB_SHA256 = "fae3ac193835e9e24cd13a0d0f11e6788183b290b0691b9b83ec81d907d94581"
CROSSWALK_SHA256 = "54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06"

SOURCE = {
    "id": "hra-united-male-v1.10",
    "title": "3D Reference Organ Set for Male, v1.10",
    "creators": "Kristen Browne and Heidi Schlehlein (HuBMAP Human Reference Atlas)",
    "doi": "https://doi.org/10.48539/HBM833.WZWN.425",
    "url": "https://cdn.humanatlas.io/digital-objects/ref-organ/united-male/v1.10/assets/3d-vh-m-united.glb",
    "sha256": GLB_SHA256,
    "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/",
    "basis": "The Visible Human Male, U.S. National Library of Medicine",
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
# set's group node, triangle budget). A budget is spread over the part's
# structures by their size, never below a floor that keeps a small one
# recognisable.
PARTS = [
    ("skin", "Skin", "integumentary", "VH_M_skin", 24000),
    ("brain", "Brain", "nervous", "Allen_brain", 42000),
    ("spinal-cord", "Spinal cord", "nervous", "VH_M_spinal_cord", 4000),
    ("optic-nerves", "Optic nerves", "nervous", "VH_M_nerves_of_eye", 1200),
    ("eyes", "Eyes", "special senses", "VH_M_eyes", 9000),
    ("heart", "Heart", "cardiovascular", "VH_M_heart", 16000),
    ("vessels", "Blood vessels", "cardiovascular", "VH_M_blood_vasculature", 46000),
    ("larynx", "Larynx", "respiratory", "VH_M_larynx", 3000),
    ("airways", "Trachea and bronchi", "respiratory", "VH_M_tracheobronchial_tree", 12000),
    ("lungs", "Lungs", "respiratory", "VH_M_lungs", 20000),
    ("mouth", "Mouth", "digestive", "VH_M_mouth", 14000),
    ("liver", "Liver", "digestive", "VH_M_liver", 12000),
    ("gallbladder", "Gallbladder", "digestive", "VH_M_gallbladder_", 1000),
    ("biliary-tree", "Bile and pancreatic ducts", "digestive", "VH_M_biliary_tree", 2000),
    ("pancreas", "Pancreas", "digestive", "VH_M_pancreas", 3000),
    ("small-intestine", "Small intestine", "digestive", "VH_M_small_intestine", 6000),
    ("colon", "Large intestine", "digestive", "VH_M_colon", 8000),
    ("tonsils", "Palatine tonsils", "lymphatic", "VH_M_palatine_tonsil", 800),
    ("spleen", "Spleen", "lymphatic", "VH_M_spleen", 3000),
    ("thymus", "Thymus", "lymphatic", "VH_M_thymus", 1200),
    ("kidneys", "Kidneys and ureters", "urinary", "VH_M_upper_urinary_tract", 14000),
    ("bladder", "Urinary bladder", "urinary", "VH_M_urinary_bladder", 2000),
    ("urethra", "Urethra", "urinary", "VH_M_urethra", 600),
    ("genital-ducts", "Vas deferens and seminal vesicles", "reproductive", "VH_M_male_genital_duct", 2000),
    ("prostate", "Prostate", "reproductive", "VH_M_prostate_gland", 4000),
    ("vertebral-column", "Vertebral column", "skeletal", "VH_M_vertebral_column", 32000),
    ("pelvis", "Pelvis", "skeletal", "VH_M_pelvis", 10000),
    ("legs", "Thigh, knee and leg", "skeletal", "VH_M_lower_limb", 16000),
    ("hyoid", "Hyoid", "skeletal", "VH_M_hyoid", 500),
    ("eye-muscles", "Muscles of the eye", "muscular", "VH_M_muscles_of_eye", 3000),
    ("larynx-muscles", "Muscles of the larynx", "muscular", "VH_M_muscles_of_larynx", 2500),
    ("knee-muscles", "Quadriceps at the knee", "muscular", "VH_M_muscles_of_knee", 3000),
]

# Structures left out: patches that lie on another structure's surface
# (landmarks, impressions) and bone inside bone, which the eye never sees.
SKIP = re.compile(
    r"_spongy_bone_|enthesis|perichondular|distal_most_point|condyle_of|epicondylar|intercondylar_fossa"
    r"|patellar_surface|impression_of_liver|bare_area_of_liver|diaphragmatic_surface$|porta_hepatis")

# Structures drawn only when their part is opened, by part: they sit inside
# another that is drawn by default (the liver's segments inside its capsule,
# the eye's inner layers, the kidney inside its capsule, the heart's valves
# inside its chambers).
INNER = {
    "liver": r"segment$|caudate_lobe|quadrate_lobe|ligament_of_liver|falciform|ligamentum_venosum|hepataduodenal",
    "eyes": r"humor|lens_|retina|fovea|macula|optic_disc|ciliary|trabecular|schlemms|ora_serrata|choroid|corneo_scleral",
    "kidneys": r"calyx|renal_pelvis|renal_column|cortex_of_kidney|renal_papilla|renal_pyramid",
    "heart": r"papillary_muscle|_valve$|interventricular_septum",
    "vertebral-column": r"nucleus_pulposus",
    "prostate": r"zone_of_prostate|zone__of_prostate|fibromuscular_stroma|prostatic_utricle|seminal_colliculus|prostate_duct",
    "small-intestine": r"papilla_of_santorini|sphincter_of|duodenal_ampulla",
}

# Tissue, by name first and then by system; the app colours by tissue.
TISSUE_BY_NAME = [
    ("tooth", r"teeth|tooth"),
    ("vein", r"vein|vena_cava|venous|sinus"),
    ("artery", r"arter|aorta|aortic_arch|truncus|trunk"),
    ("nerve", r"nerve|spinal_cord|dura_mater"),
    ("ligament", r"ligament|tendon"),
    ("cartilage", r"cartilage|meniscus|disk|nucleus_pulposus|epiglott|carina"),
    ("muscle", r"muscle|rectus|oblique|vocalis|arytenoid$|cricothyroid|cricoarytenoid|thyroarytenoid|thyroepiglottideus"),
    ("fluid", r"humor"),
    ("duct", r"duct|ampulla|papilla_of|sphincter|calyx|renal_pelvis|ureter|urethra|vas_deferens"),
    ("gland", r"gland|thymus|tonsil"),
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


def simplify(p, f, target):
    # Many small pieces (the lens's zonule fibres) stop one pass short of
    # its target, so a few passes, each from where the last one stopped.
    for _ in range(4):
        if len(f) <= target * 1.15:
            break
        q, g = fast_simplification.simplify(p.astype(np.float32), f.astype(np.int32),
                                            target_reduction=1 - target / len(f), agg=9)
        if len(g) == 0 or len(g) >= len(f):
            break
        used = np.unique(g)
        remap = np.full(len(q), -1, dtype=np.int64); remap[used] = np.arange(len(used))
        p, f = q[used].astype(np.float64), remap[g]
    return p, f


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
}
# Words that keep their capital: people's names and abbreviations.
PROPER = {"Drummond", "Schlemm", "Santorini", "Heschl", "Heschls", "Ammon", "Broca", "Wernicke", "LAD", "HTH"}


def label(node, crossed):
    if node in CORRECTED:
        return CORRECTED[node]
    text = crossed[0] if crossed and crossed[0] not in ("", "-") else node.replace("VH_M_", "").replace("_", " ")
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


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--glb", required=True)
    ap.add_argument("--crosswalk", required=True)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "RedPen", "Resources", "Anatomy"))
    a = ap.parse_args()
    got = sha256(a.glb)
    assert got == GLB_SHA256, f"{a.glb}: SHA-256 {got}, expected {GLB_SHA256} (a new release? re-pin it in SOURCES.md and here)"
    got = sha256(a.crosswalk)
    assert got == CROSSWALK_SHA256, f"{a.crosswalk}: SHA-256 {got}, expected {CROSSWALK_SHA256}"
    crossed = crosswalk(a.crosswalk)
    gltf, binary = load_glb(a.glb)
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

    os.makedirs(a.out, exist_ok=True)
    manifest_parts, total = [], 0
    for pid, name, system, group, budget in PARTS:
        found = []
        def collect(i, parent_label):
            n = nodes[i]
            here = n.get("name", "")
            if "mesh" in n and not SKIP.search(here):
                found.append((i, here, parent_label))
            for c in n.get("children", []):
                collect(c, label(here, crossed.get(here)) if "mesh" not in n else parent_label)
        collect(by_name[group], name)
        assert found, f"{pid}: no structures under {group}"
        raw = [mesh_of(gltf, binary, nodes[i], world[i]) for i, _, _ in found]
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
                "uberon": crossed_row[1] if crossed_row and node not in CORRECTED else None,
                "tissue": tissue(pid, system, node),
                "group": parent_label,
                "inner": bool(re.search(INNER[pid], node)) if pid in INNER else False,
                "triangles": int(len(f)),
            })
        path = os.path.join(a.out, pid + ".atlas")
        lo, hi = write_part(path, meshes)
        triangles = sum(s["triangles"] for s in structures)
        total += triangles
        manifest_parts.append({
            "id": pid, "name": name, "system": system, "file": pid + ".atlas",
            "bytes": os.path.getsize(path), "sha256": sha256(path), "triangles": triangles,
            "bounds": [round(float(v), 5) for v in (*lo, *hi)],
            "structures": structures,
        })
        print(f"{pid:18} {len(structures):4} structures {triangles:7} triangles {os.path.getsize(path):9} bytes")
    manifest = {
        "format": 1,
        "frame": "The Visible Human Male: metres, x to the body's left, y up, z forward, origin near the hips",
        "sources": [SOURCE, dict(CROSSWALK, sha256=CROSSWALK_SHA256)],
        "changes": "Structures simplified to a triangle budget per part, positions quantised to 16 bits; "
                   "surface patches and inner spongy bone left out; the brain mirrored left to right so each "
                   "side lies where its name says; labels and UBERON ids from the crosswalk, corrected where "
                   "wrong for the mesh (sides swapped on the renal arteries, vas deferens and thymus lobes).",
        "parts": manifest_parts,
    }
    json.dump(manifest, open(os.path.join(a.out, "anatomy.json"), "w"), indent=1, ensure_ascii=False)
    print(f"total {total} triangles in {len(manifest_parts)} parts")


if __name__ == "__main__":
    main()
