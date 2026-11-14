"""proportions.py: the built bones measured against the target sizes of landmarks.py.

  python3 proportions.py <out folder>     -> prints a table and writes <out>/proportions.json
Everything is read off the finished meshes (bones/*.npz) and the manifest; nothing else is opened.
"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import landmarks as L


def load(out, bid):
    d = np.load(os.path.join(out, "bones", bid + ".npz"))
    return (d["v"].astype(float) - L.HEAD) * 1000.0


def near(v, p):
    return v[np.argmin(np.linalg.norm(v - np.asarray(p, float), axis=1))]


def main(out):
    man = json.load(open(os.path.join(out, "manifest.json")))
    c = np.load(os.path.join(out, "bones", "_cranium_fine.npz"))["v"].astype(float)      # kept in head-frame mm
    m = load(out, "mandible")
    mid = c[np.abs(c[:, 0]) < 0.8]
    glab = mid[(mid[:, 1] > 25) & (mid[:, 1] < 45)]; glab = glab[np.argmax(glab[:, 2])]
    opis = mid[np.argmin(mid[:, 2])]
    breg = near(mid, L.SKULL["bregma"])
    rim = mid[(mid[:, 2] > -14) & (mid[:, 2] < 4) & (mid[:, 1] < -14) & (mid[:, 1] > -30)]
    bas = rim[np.argmin(rim[:, 2])]                           # front edge of the foramen magnum on the midline
    back = mid[(mid[:, 2] < -30) & (mid[:, 2] > -50) & (mid[:, 1] < -14) & (mid[:, 1] > -32)]
    opn = back[np.argmax(back[:, 2])]                         # its back edge
    nas = near(mid, L.SKULL["nasion"])
    alv = mid[(mid[:, 2] > 86) & (mid[:, 1] < -35)]; pro = alv[np.argmin(alv[:, 1])]
    mm = m[np.abs(m[:, 0]) < 0.8]; men = mm[np.argmin(mm[:, 1])]
    mb = man["bones"]["mandible"]["measured_mm"]; cs = man["cervical_column"]; cm = man["bones"]["cranium"]["measured_mm"]
    hy = man["bones"]["hyoid"]["measured_mm"]
    fm = c[(np.abs(c[:, 1] + 24) < 2.5) & (c[:, 2] > -45) & (c[:, 2] < 0) & (np.abs(c[:, 0]) < 22)]
    rows = [
        ("skull length, glabella to opisthocranion", float(np.linalg.norm((glab - opis)[1:])), L.SIZES["skull length glabella-opisthocranion"]),
        ("skull breadth", cm["skull breadth"], L.SIZES["skull breadth euryon-euryon"]),
        ("skull height, basion to bregma", float(np.linalg.norm(bas - breg)), L.SIZES["basion-bregma height"]),
        ("vertex above the Frankfurt plane", cm["vertex above Frankfurt plane"], L.VERTEX_ABOVE_FH),
        ("bizygomatic breadth", cm["bizygomatic breadth"], L.SIZES["bizygomatic breadth"]),
        ("bimastoid breadth near the tips", cm["bimastoid breadth (outer, near tips)"], L.SIZES["bimastoid breadth at the tips"]),
        ("upper facial height, nasion to alveolar margin", float(np.linalg.norm(nas - pro)), L.SIZES["upper facial height nasion-prosthion"]),
        ("total facial height, nasion to menton", float(np.linalg.norm(nas - men)), L.SIZES["total facial height nasion-menton"]),
        ("foramen magnum length", float(bas[2] - opn[2]), L.SIZES["foramen magnum length"]),
        ("bigonial breadth", mb["bigonial breadth"], L.SIZES["bigonial breadth"]),
        ("bicondylar breadth", mb["bicondylar breadth"], L.SIZES["bicondylar breadth"]),
        ("ramus height, condylion to gonion", mb["ramus height condylion-gonion"], L.SIZES["ramus height condylion-gonion"]),
        ("least ramus breadth", mb["minimum ramus breadth"], L.SIZES["minimum ramus breadth"]),
        ("symphysis height", mb["symphysis height"], L.SIZES["symphysis height"]),
        ("cervical column, dens tip to lower end plate of C7", cs["dens tip to the lower end plate of C7 (straight)"], 130.0),
        ("cervical lordosis C2-C7, degrees", cs["lordosis C2-C7 (difference of end plate tilts), degrees"], 17.0),
        ("atlas width", cs["atlas width"], 80.0),
        ("atlas front to back", cs["atlas front to back"], 45.0),
        ("C7 spinous tip above the soles, m", cs["C7 spinous tip above the soles, m"], round(L.LEVELS["seventh cervical spine"], 3)),
        ("hyoid width across the greater horns", hy["width across the greater horns"], 45.0),
    ]
    table = [{"what": w, "built": round(float(b), 1 if b > 3 else 3), "target (typical textbook value)": t} for w, b, t in rows]
    for r in table:
        print("%-52s built %8s   target %8s" % (r["what"], r["built"], r["target (typical textbook value)"]))
    json.dump({"note": "mm unless said; targets are typical textbook values for an adult man, no source cited", "rows": table,
               "points_mm_head_frame": {"glabella": np.round(glab, 1).tolist(), "opisthocranion": np.round(opis, 1).tolist(), "bregma": np.round(breg, 1).tolist(),
                                        "basion": np.round(bas, 1).tolist(), "opisthion": np.round(opn, 1).tolist(), "nasion": np.round(nas, 1).tolist(),
                                        "prosthion (alveolar margin, midline)": np.round(pro, 1).tolist(), "menton": np.round(men, 1).tolist()}},
              open(os.path.join(out, "proportions.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
