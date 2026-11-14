"""make.py: build the from-scratch bones and their check pictures.

  python3 make.py <out folder> skull|mandible|cervical|hyoid|all [--h 0.5] [--draft]

Writes bones/<id>.npz (v in metres in the body frame, f), checks/<name>.png and manifest.json.
--draft: a coarse grid and no files but the check picture (for looking while shaping).
"""
import json, os, sys, time
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sdf, view, landmarks as L   # noqa: E402


def clock():
    return time.strftime("%H:%M:%S")


def views(meshes, names, size=620, frame=None):
    return [(view.picture(meshes, view.VIEWS[n], size, frame), n) for n in names]


def plate(out, name, size):
    p = os.path.join(out, "refs", name)
    if not os.path.exists(p):
        return None
    im = Image.open(p).convert("RGB")
    k = size / max(im.size)
    return im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)


def snap_landmarks(v_mm, f, marks):
    """Each planned landmark moved to the nearest point of the finished surface, so the manifest gives
    landmarks that lie on the bone as built (midline ones stay on x = 0; centres are left alone)."""
    import check_mesh
    from scipy.spatial import cKDTree
    P = check_mesh.surface_points(np.asarray(v_mm, float), np.asarray(f, int), 0.3)
    tree = cKDTree(P); mid = P[np.abs(P[:, 0]) < 0.4]
    tmid = cKDTree(mid[:, 1:]) if len(mid) else None
    built, moved = {}, {}
    for name, p in marks.items():
        if not (isinstance(p, (list, tuple)) and len(p) == 3) or "centre" in name:
            built[name] = list(p) if isinstance(p, tuple) else p
            continue
        p = np.array(p, float)
        if p[0] == 0 and tmid is not None:
            k = tmid.query(p[1:])[1]; q = np.array([0.0, mid[k, 1], mid[k, 2]])
        else:
            q = P[tree.query(p)[1]]
        built[name] = np.round(q, 1).tolist(); moved[name] = round(float(np.linalg.norm(q - p)), 1)
    return built, moved


def save_bone(out, bid, v_mm, f, info):
    v = L.body(v_mm)
    info = dict(info)
    if "landmarks_mm_head_frame" in info:
        planned = {k: (list(p) if isinstance(p, tuple) else p) for k, p in info["landmarks_mm_head_frame"].items()}
        info["landmarks_planned_mm_head_frame"] = planned
        info["landmarks_mm_head_frame"], info["landmark_moved_mm"] = snap_landmarks(v_mm, f, planned)
    np.savez_compressed(os.path.join(out, "bones", bid + ".npz"), v=v.astype(np.float32), f=f.astype(np.int32))
    mp = os.path.join(out, "manifest.json")
    man = json.load(open(mp)) if os.path.exists(mp) else {"frame": "metres; x = body's left, y up (soles 0), z forward; midline x = 0",
                                                           "stature_m": L.STATURE, "head_origin_m": L.HEAD.tolist(), "bones": {}}
    info = dict(info); info.update({"id": bid, "file": "bones/%s.npz" % bid, "triangles": int(len(f)),
                                    "bounds_m": [np.round(v.min(0), 4).tolist(), np.round(v.max(0), 4).tolist()]})
    man["bones"][bid] = info
    json.dump(man, open(mp, "w"), indent=1)


PART_COLOURS = [(226, 214, 190), (150, 178, 214), (214, 160, 150), (160, 204, 160), (220, 196, 120), (186, 160, 208)]


def split_cranium(out, F, V, h):
    """Cut the finished cranium along its sutures and save each piece (bones/cranium_parts/...); a coloured sheet."""
    import skull
    G = sdf.Field(F.lo, F.lo + (F.n - 1) * h, h); G.n = np.array(F.D.shape); G.ax = F.ax; G.D = F.D.copy()
    for sh in skull.split_sheets(V):
        G.cut(sh, 0.0)
    D = sdf.mirror_field(G.D)
    lo = np.array([-F.ax[0][-1], F.lo[1], F.lo[2]])
    v, f = sdf.mesh(D, lo, h)
    parts = [p for p in sdf.components(v, f) if len(p[1]) >= 2000]
    print(clock(), "split: pieces", [len(p[1]) for p in parts], flush=True)
    from scipy.spatial import cKDTree
    trees = [cKDTree(p[0][::7]) for p in parts]
    named, used = {}, set()
    for name, seed in skull.PART_SEEDS.items():
        for side, sx in (("L", 1), ("R", -1)):
            if seed[0] == 0 and side == "R":
                continue
            q = np.array([seed[0] * sx, seed[1], seed[2]], float)
            k = int(np.argmin([t.query(q)[0] for t in trees]))
            bid = name.split(",")[0].split(" ")[0] + ("" if seed[0] == 0 else "_" + side) if "not yet" not in name else "rest_of_cranium"
            named[bid] = (name if seed[0] == 0 else name + (", left" if side == "L" else ", right"), k)
            used.add(k)
    os.makedirs(os.path.join(out, "bones", "cranium_parts"), exist_ok=True)
    info, meshes = {}, []
    area = lambda vv, ff: float(np.linalg.norm(np.cross(vv[ff[:, 1]] - vv[ff[:, 0]], vv[ff[:, 2]] - vv[ff[:, 0]]), axis=1).sum() / 2)
    for i, (bid, (name, k)) in enumerate(named.items()):
        pv, pf = parts[k]
        pv = sdf.taubin(pv, pf, 8)
        target = int(max(3000, area(pv, pf) / 2.6))
        best = None
        for t in [int(target * m) for m in (1, 1.04, 0.96, 1.09, 0.91, 1.15, 0.87, 1.22, 0.8, 1.3, 1.02, 0.98, 1.45, 1.6, 2.0, 2.5)]:
            sv, sf = sdf.simplify(pv, pf, t)
            best = best or (sv, sf)
            if sdf.closed(sv, sf):
                best = (sv, sf); break
        sv, sf = best
        np.savez_compressed(os.path.join(out, "bones", "cranium_parts", bid + ".npz"), v=L.body(sv).astype(np.float32), f=sf.astype(np.int32))
        rep = sdf.report(sv, sf)
        info[bid] = {"id": bid, "name": name, "file": "bones/cranium_parts/%s.npz" % bid, "triangles": int(len(sf)), "closed": rep["closed"],
                     "pieces": rep["pieces"], "bounds_m": [np.round(L.body(sv).min(0), 4).tolist(), np.round(L.body(sv).max(0), 4).tolist()]}
        kinds = list(dict.fromkeys(b.split("_")[0] for b in named))
        meshes.append((sv, sf, PART_COLOURS[kinds.index(bid.split("_")[0]) % len(PART_COLOURS)]))
        print("  part", bid, info[bid]["triangles"], "closed" if rep["closed"] else "NOT closed", "pieces", rep["pieces"], flush=True)
    rows = [views(meshes, ["front", "left side", "back"], 620), views(meshes, ["top", "below", "three-quarter"], 620)]
    view.sheet(rows, os.path.join(out, "checks", "skull_parts.png"), "Cranium cut along its sutures: %d pieces of %d found (gap %.1f mm)" % (len(used), len(parts), skull.GAP))
    man = json.load(open(os.path.join(out, "manifest.json")))
    man["cranium_parts"] = {"note": "the one-piece cranium (bones/cranium.npz) cut along the sutures of the braincase; a partial split: "
                                    "frontal, sphenoid, ethmoid and the facial bones are still one piece; gap %.1f mm at each suture" % skull.GAP,
                            "pieces_found": len(parts), "parts": info}
    json.dump(man, open(os.path.join(out, "manifest.json"), "w"), indent=1)


def do_skull(out, h, draft):
    import skull
    t = time.time()
    F, V = skull.build(h)
    print(clock(), "skull field", F.n.tolist(), "%.0f s" % (time.time() - t), flush=True)
    sizes = skull.measure(F)
    print("sizes", sizes, flush=True)
    D = sdf.mirror_field(F.D)
    lo = np.array([-F.ax[0][-1], F.lo[1], F.lo[2]])
    fine, final, pieces = sdf.finish(D, lo, h, 60000 if not draft else 10 ** 9, rounds=6 if draft else 10)
    v, f = fine if draft else final
    rep = sdf.report(v, f); rep["pieces_in_field"] = pieces; rep["crumbs_left_out"] = sdf.finish.dropped
    print(clock(), "skull mesh", rep, flush=True)
    m = [(v, f, view.BONE)]
    rows = [views(m, ["front", "left side", "back"]), views(m, ["top", "below", "three-quarter"])]
    refs = [(plate(out, n, 620), "reference: Gray's Anatomy 1918 (public domain), " + n) for n in ("Gray190.png", "Gray188.png", "Gray187.png")]
    refs = [r for r in refs if r[0] is not None]
    if refs:
        rows.append(refs)
    name = "skull_draft.png" if draft else "skull.png"
    view.sheet(rows, os.path.join(out, "checks", name), "Cranium built from landmarks (no imported 3D)  h = %.2f mm, %d triangles" % (h, len(f)))
    if not draft:
        np.savez_compressed(os.path.join(out, "bones", "_cranium_fine.npz"), v=fine[0].astype(np.float32), f=fine[1].astype(np.int32))
        save_bone(out, "cranium", v, f, {"name": "cranium (skull without the mandible)", "side": "midline", "group": "skull",
                                          "how": "star-shaped braincase through craniometric landmarks; face from solids on landmarks; "
                                                 "hollows cut; left half computed and mirrored; grid %.2f mm" % h,
                                          "landmarks_mm_head_frame": L.SKULL, "measured_mm": sizes, "mesh": rep,
                                          "sutures_mm_head_frame": getattr(skull.build, "sutures", {}),
                                          "to_do": "split into the named bones along the sutures (a partial split is in cranium_parts)"})
        split_cranium(out, F, V, h)
        man = json.load(open(os.path.join(out, "manifest.json")))
        man["dental_arches"] = {"note": "socket frames in the head frame (mm): position = middle of the socket's mouth on the alveolar margin, "
                                        "outward = toward lip or cheek, axis = the tooth's long axis from root to crown, along_arch = toward the back "
                                        "of the arch, width_mm = mesiodistal width; the crown tip is taken as position + axis x crown_mm and the root "
                                        "end as position - axis x root_mm. For the body frame divide by 1000 and add head_origin_m. No teeth are modelled.",
                                "upper": skull.sockets(L.UPPER_ARCH, L.UPPER, True), "lower": skull.sockets(L.LOWER_ARCH, L.LOWER, False)}
        json.dump(man, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    return v, f


def occlusion(arches):
    """How the two rows of sockets meet with the mouth closed: per tooth, the crown tips of the upper and the
    lower tooth (position + long axis x crown height) and how far they overlap in height."""
    out = []
    for up, lw in zip(arches["upper"], arches["lower"]):
        tu = np.array(up["position_mm"]) + np.array(up["axis"]) * up["crown_mm"]
        tl = np.array(lw["position_mm"]) + np.array(lw["axis"]) * lw["crown_mm"]
        out.append({"tooth": up["tooth"].replace("upper ", ""), "side": up["side"], "upper tip": np.round(tu, 1).tolist(), "lower tip": np.round(tl, 1).tolist(),
                    "vertical overlap_mm": round(float(tl[1] - tu[1]), 1), "upper ahead or outside of lower_mm": round(float(np.linalg.norm(tu[[0, 2]]) - np.linalg.norm(tl[[0, 2]])), 1)})
    return out


def do_assembly(out):
    mp = os.path.join(out, "manifest.json")
    man = json.load(open(mp))
    meshes = []
    for bid in man["bones"]:
        d = np.load(os.path.join(out, "bones", bid + ".npz"))
        meshes.append(((d["v"].astype(float) - L.HEAD) * 1000.0, d["f"].astype(np.int64), view.BONE))
    rows = [views(meshes, ["front", "left side", "back"], 700), views(meshes, ["three-quarter", "below", "right side"], 700)]
    close = [(view.picture(meshes, view.VIEWS["left side"], 700, frame=(np.array([50.0, -28.0, 20.0]), 105.0)), "left jaw joint and ramus, close"),
             (view.picture(meshes, view.VIEWS["front"], 700, frame=(np.array([0.0, -55.0, 60.0]), 130.0)), "jaws from the front, close (no teeth: sockets are frames in the manifest)"),
             (view.picture(meshes, (0.75, -0.1, -0.65), 700, frame=(np.array([0.0, -70.0, -15.0]), 170.0)), "neck from behind and the left")]
    rows.append(close)
    refs = [(plate(out, n, 700), "reference: Gray's Anatomy 1918 (public domain), " + n) for n in ("Gray190.png", "Gray188.png")]
    refs = [r for r in refs if r[0] is not None]
    if refs:
        rows.append(refs)
    view.sheet(rows, os.path.join(out, "checks", "head_neck.png"), "Skull, mandible, C1-C7 and hyoid together, all built from landmarks (no imported 3D)")
    if "dental_arches" in man:
        man["dental_arches"]["occlusion"] = occlusion(man["dental_arches"])
        json.dump(man, open(mp, "w"), indent=1)
        left = [o for o in man["dental_arches"]["occlusion"] if o["side"] == "L"]
        print("occlusion (left)", [(o["tooth"], o["vertical overlap_mm"], o["upper ahead or outside of lower_mm"]) for o in left], flush=True)
    tri = sum(b["triangles"] for b in man["bones"].values())
    print(clock(), "assembly", len(man["bones"]), "bones", tri, "triangles", flush=True)


def main():
    out, what = sys.argv[1], sys.argv[2]
    h = float(sys.argv[sys.argv.index("--h") + 1]) if "--h" in sys.argv else 0.5
    draft = "--draft" in sys.argv
    for d in ("bones", "checks"):
        os.makedirs(os.path.join(out, d), exist_ok=True)
    if what in ("skull", "all"):
        do_skull(out, h, draft)
    if what in ("mandible", "all"):
        import mandible
        mandible.make(out, h, draft)
    if what in ("cervical", "all"):
        import cervical
        cervical.make(out, h, draft)
    if what in ("hyoid", "all"):
        import hyoid
        hyoid.make(out, h, draft)
    if what in ("assembly", "all") and not draft:
        do_assembly(out)


if __name__ == "__main__":
    main()
