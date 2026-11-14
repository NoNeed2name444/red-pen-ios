"""mandible.py: the lower jaw built from landmarks (no imported 3D).

Head frame, millimetres (see landmarks.py). The left half is computed and mirrored, so the bone is
symmetric by construction. The body is one solid swept along the dental arch between two drawn
lines, the alveolar crest above and the lower border beneath; the ramus is a drawn outline in its
own slanted plane, thickened along its borders; the condyle sits in the mandibular fossa with the
mouth closed. No teeth: the sockets are frames in the manifest (skull.sockets).
"""
import os
import time
import numpy as np
from scipy.interpolate import CubicSpline
import sdf, view, landmarks as L

# matched stations from the midline back: T = middle of the alveolar crest, B = the lower border under it
T = [(0, -60.0, 89.8), (6.5, -60.0, 88.3), (13.5, -60.3, 84.5), (18.6, -58.0, 78.6), (21.8, -56.5, 72.0),
     (24.6, -54.2, 62.5), (26.8, -52.2, 52.0), (29.2, -50.7, 42.0), (32.0, -49.6, 34.0),
     (37.0, -46.5, 27.5), (41.0, -41.0, 23.0)]                 # the last two climb the ramus (temporal crest)
B = [(0, -91.8, 85.5), (8.5, -91.6, 84.3), (17.0, -90.5, 80.0), (24.0, -88.4, 73.0), (29.0, -85.4, 65.0),
     (34.0, -80.6, 54.0), (38.5, -75.6, 42.0), (41.3, -70.6, 30.0), (42.6, -66.0, 21.0),
     (43.4, -64.4, 15.5), (43.8, -62.0, 12.5)]
HALF = [5.6, 5.6, 5.5, 5.4, 5.6, 6.6, 7.0, 6.8, 5.6, 3.9, 3.0]           # half thickness, cheek to tongue, at mid height
TAPER = [0.36, 0.36, 0.33, 0.25, 0.20, 0.12, 0.08, 0.05, 0.0, 0.0, 0.0]  # thinner at the crest, thicker at the base
POWER = 3.0                                                     # squareness of the body's section

# The body's cross-section, traced at seven stations (u = 0 at the midline, counted in stations of T and B).
# Each is 14 points (out, up) in mm for a half height of 15 (the up values are scaled to the real height
# between crest and lower border): from the crest down the cheek side, round the lower border, up the
# tongue side. They carry the shape a student looks for: the thick rounded lower border, the thinner
# tooth-bearing part, the chin, the oblique line on the cheek side behind (the swelling at point 2), the
# mylohyoid line as a low ridge on the tongue side with the hollow for the gland under it (points 12, 10).
SECTION_U = [0.0, 2.0, 4.0, 6.0, 7.4, 9.1, 10.0]
SECTIONS = [
    [(-0.3, 15.0), (2.9, 14.0), (2.9, 7.0), (3.3, 0.5), (5.5, -5.5), (7.9, -10.8), (6.8, -14.6), (1.5, -16.3),
     (-4.5, -15.2), (-7.4, -11.5), (-7.6, -6.0), (-6.2, 0.5), (-4.8, 7.5), (-3.7, 14.0)],                    # symphysis
    [(0.0, 15.0), (3.5, 14.0), (4.3, 7.5), (4.6, 1.0), (5.5, -5.0), (6.7, -10.4), (5.6, -14.0), (0.8, -15.2),
     (-4.0, -14.2), (-6.2, -10.5), (-6.4, -5.5), (-5.6, 0.5), (-4.6, 7.5), (-3.9, 14.0)],                    # canine
    [(0.0, 15.0), (3.9, 14.0), (4.9, 8.0), (5.4, 1.5), (5.9, -4.5), (5.8, -9.5), (4.6, -13.6), (0.5, -15.0),
     (-3.8, -13.8), (-5.6, -9.8), (-5.0, -4.5), (-5.9, 1.5), (-5.2, 7.5), (-4.2, 14.0)],                     # second premolar
    [(0.0, 15.0), (5.5, 14.0), (7.6, 9.0), (7.4, 3.0), (6.6, -3.5), (5.6, -9.0), (4.2, -13.5), (0.3, -15.0),
     (-3.6, -13.6), (-4.8, -9.5), (-4.3, -4.0), (-5.3, 2.0), (-6.5, 7.0), (-5.7, 14.0)],                     # first and second molar
    [(0.0, 15.0), (5.3, 14.0), (8.0, 10.5), (7.2, 4.0), (6.2, -3.0), (5.2, -9.0), (3.8, -13.5), (0.2, -15.0),
     (-3.2, -13.6), (-4.2, -9.5), (-4.0, -3.5), (-5.0, 3.0), (-6.4, 9.0), (-5.5, 14.0)],                     # third molar
    [(0.0, 15.0), (2.6, 13.5), (3.6, 8.5), (3.7, 3.0), (3.7, -3.0), (3.8, -8.5), (3.2, -13.0), (0.4, -15.0),
     (-2.8, -13.2), (-3.4, -9.0), (-3.0, -3.5), (-3.0, 3.0), (-3.2, 8.5), (-2.6, 13.5)],                     # lower ramus
    [(0.0, 15.0), (2.0, 13.5), (2.7, 8.5), (2.8, 3.0), (2.8, -3.0), (2.9, -8.5), (2.5, -13.0), (0.3, -15.0),
     (-2.2, -13.2), (-2.6, -9.0), (-2.4, -3.5), (-2.4, 3.0), (-2.5, 8.5), (-2.0, 13.5)],                     # higher in the ramus
]


def outlines(uu, a, n=240):
    """The body's section outline at each station of the line: (m, n, 2) as (out, up) in mm."""
    from scipy.interpolate import PchipInterpolator
    S = np.array(SECTIONS, float)
    at = PchipInterpolator(SECTION_U, S, axis=0)(np.clip(np.abs(uu), 0, SECTION_U[-1]))        # (m, 14, 2)
    k = np.arange(S.shape[1] + 1)
    closed = np.concatenate([at, at[:, :1]], axis=1)
    out = CubicSpline(k, closed, axis=1, bc_type="periodic")(np.linspace(0, S.shape[1], n, endpoint=False))
    out[:, :, 1] *= (np.asarray(a) / 15.0)[:, None]
    return out

# the ramus: a plane leaning in toward the chin and in toward the angle, and its outline in (z, y)
O = np.array([49.0, -12.0, 10.5])
ES = sdf.unit((-0.20, 0.0, 0.98))
ET = np.array([0.115, 1.0, 0.0]); ET = sdf.unit(ET - (ET @ ES) * ES)
OUTLINE = [(8.2, -5), (8.7, -14), (7.2, -28), (7.6, -42), (9.3, -53), (11.5, -60), (14.5, -63.4), (22, -65.7),
           (34, -71.6), (41, -64), (38.5, -50), (36, -38), (35.5, -26), (37.4, -14), (40.1, -8.0), (39.1, -4.3),
           (36.4, -9.4), (31.2, -14.6), (24.6, -17.2), (19.0, -15.4), (15.6, -10.4), (14.3, -5)]
CONDYLE = {"centre": (50.6, -5.4, 10.5), "half": (9.0, 4.3, 4.1), "turn": -15.0}


def on_ramus(z, y, out=0.0):
    """The point of the ramus plane with this z and y (mm); `out` mm toward the cheek."""
    s = (z - O[2]) / ES[2]
    t = (y - O[1]) / ET[1]
    n = np.cross(ES, ET); n = n if n[0] > 0 else -n
    return O + s * ES + t * ET + out * n


def body_line(step=0.04):
    """The body's stations made smooth and symmetric: (centre, up, half height, half thickness, taper, u)."""
    m = len(T) - 1
    u = np.arange(-m, m + 1)
    def both(P, flip):
        P = np.asarray(P, float)
        Q = P[:0:-1].copy()
        if flip:
            Q[:, 0] *= -1
        return np.concatenate([Q, P])
    cT, cB = CubicSpline(u, both(T, True)), CubicSpline(u, both(B, True))
    ch, ct = CubicSpline(u, both(np.array(HALF)[:, None], False)[:, 0]), CubicSpline(u, both(np.array(TAPER)[:, None], False)[:, 0])
    uu = np.arange(-0.2, m + 0.0001, step)
    t, b = cT(uu), cB(uu)
    return (t + b) / 2, (t - b) / np.linalg.norm(t - b, axis=1)[:, None], np.linalg.norm(t - b, axis=1) / 2, ch(uu), ct(uu), uu


def surface_point(line, u, q, cheek=True, lift=0.0):
    """A point on the body's surface at station u, at the fraction q of its height (0 lower border, 1 crest),
    on the cheek side or the tongue side; `lift` mm off the surface."""
    M, up, a, b, tp, uu = line
    i = int(np.argmin(np.abs(uu - u)))
    e = sdf.unit(M[min(i + 1, len(M) - 1)] - M[max(i - 1, 0)])
    w = sdf.unit(np.cross(e, up[i]))
    k = 2 * q - 1
    o = outlines(uu[i:i + 1], a[i:i + 1])[0]
    side = o[o[:, 0] > 0] if cheek else o[o[:, 0] < 0]
    j = int(np.argmin(np.abs(side[:, 1] - k * a[i])))
    return M[i] + side[j, 1] * up[i] + (side[j, 0] + (1 if cheek else -1) * lift) * w, w


def build(h=0.5, log=print):
    F = sdf.Field([0, -99, -1], [64, 5, 100], h)
    line = body_line()
    M, up, a, b, tp, uu = line
    F.add(sdf.Sweep(M, up, outlines(uu, a)))
    # ramus plate and its thick borders
    Q = sdf.spline(np.array(OUTLINE, float), 1.5, closed=True)
    st = np.stack([(Q[:, 0] - O[2]) / ES[2], (Q[:, 1] - O[1]) / ET[1]], axis=1)
    F.add(sdf.Plate(st, O, ES, ET, 1.75, 1.7), k=9.0)                 # thin in the middle; the borders and ridges below thicken it
    back = sdf.spline([on_ramus(z, y) for z, y in [(12.3, -13), (10.4, -27), (10.4, -41), (12.2, -52), (14.8, -59.5)]], 2.0)
    F.add(sdf.Tube(back, [(0, 2.6), (0.25, 3.2), (0.6, 3.3), (1, 4.0)], [(0, 3.0), (0.5, 3.3), (1, 3.3)], up=ES), k=7.0)     # thick rounded hind border
    front = [on_ramus(z, y) for z, y in [(37.4, -9.5), (34.9, -20), (34.9, -33), (37.2, -45)]]
    p1, _ = surface_point(line, 6.9, 0.60, True, -2.4)
    p2, _ = surface_point(line, 6.1, 0.42, True, -2.5)
    p3, _ = surface_point(line, 5.2, 0.30, True, -2.5)
    front = sdf.spline(front + [p1, p2, p3], 2.0)                    # the front border runs on as the oblique line
    F.add(sdf.Tube(front, [(0, 1.8), (0.35, 2.6), (0.6, 3.0), (1, 1.6)], [(0, 1.6), (0.35, 2.2), (0.6, 2.0), (1, 0.9)], up=ES), k=6.0)
    # the angle turned a little outward and roughened for the masseter; the pterygoid roughness on its inner face
    F.add(sdf.Ellipsoid(on_ramus(18.5, -57.0, 0.7), (9.0, 7.5, 2.1), np.stack([ES, ET, np.cross(ES, ET)], axis=1)), k=7.0)
    F.add(sdf.Ellipsoid(on_ramus(20.0, -55.0, -1.2), (7.5, 6.5, 1.9), np.stack([ES, ET, np.cross(ES, ET)], axis=1)), k=6.0)
    # inner face: the ridge from the neck down to the lingula, and the temporal crest from the coronoid down to behind the last molar
    F.add(sdf.Tube(sdf.spline([on_ramus(12.5, -11, -0.8), on_ramus(17.5, -21, -1.2), on_ramus(23.5, -30, -1.4)], 2.0), [(0, 3.6), (1, 2.6)], [(0, 2.2), (1, 1.5)], up=ES), k=6.0)
    F.add(sdf.Tube(sdf.spline([on_ramus(37.6, -10, -0.6), on_ramus(35.8, -22, -1.0), on_ramus(35.6, -34, -1.3), on_ramus(36.6, -43, -1.6)], 2.0), [(0, 1.8), (0.5, 2.8), (1, 3.0)], [(0, 1.2), (0.5, 1.7), (1, 2.0)], up=ES), k=6.0)
    # the angle, a little thickened and roughened for the masseter and the medial pterygoid
    # condyle on its neck
    c = CONDYLE
    F.add(sdf.Tube(sdf.spline([on_ramus(10.8, -6.0), on_ramus(11.0, -15.0)], 2.0), [(0, 4.0), (1, 3.6)], [(0, 6.2), (1, 2.6)], up=ES), k=4.5)
    F.add(sdf.Ellipsoid(c["centre"], c["half"], sdf.rot((0, 1, 0), c["turn"])), k=2.5)
    F.cut(sdf.Ellipsoid(on_ramus(16.2, -8.2, -1.6), (3.0, 3.2, 2.2)), k=1.5)          # pterygoid fovea on the front of the neck
    # chin: mental protuberance and tubercle
    # (the mental protuberance and the tubercles beside it are in the traced sections)
    # mylohyoid line on the tongue side, from under the last molar down and forward
    # (the mylohyoid line is part of the traced sections: a low ridge, not a bar)
    # mental spines
    sp, w = surface_point(line, 0.0, 0.33, False, -0.6)
    F.add(sdf.Ellipsoid(sp, (1.6, 2.4, 1.5)), k=1.5)
    # lingula, then the mandibular foramen behind it
    F.add(sdf.Ellipsoid(on_ramus(25.2, -31.5, -2.0), (1.5, 2.6, 2.4)), k=2.0)
    F.cut(sdf.Tube(np.array([on_ramus(20.5, -29.0, -5.0), on_ramus(23.2, -35.0, -1.2)]), 1.6), k=0.8)
    # mental foramen under the second premolar, opening up and back
    mf, w = surface_point(line, 4.05, 0.47, True, 0.0)
    F.cut(sdf.Tube(np.array([mf + 2.5 * w + np.array([0, 1.0, -1.0]), mf - 3.5 * w]), 1.35), k=0.6)
    # shallow digastric fossa under the chin on the tongue side, and the submandibular hollow under the ridge
    dg, w = surface_point(line, 1.3, 0.10, False, 0.0)
    F.cut(sdf.Ellipsoid(dg - 1.5 * w, (6.0, 3.0, 3.2)), k=2.5)
    import skull
    skull.cut_sockets(F, skull.sockets(L.LOWER_ARCH, L.LOWER, False), False)
    return F, {"mental foramen": np.round(mf, 1).tolist(), "line": line}


def measure(v):
    """Sizes of the finished mandible (mm, head frame)."""
    left = v[v[:, 0] > 0]
    ang = left[(left[:, 2] < 20) & (left[:, 1] < -55)]
    gon = ang[np.argmin(ang[:, 1] * 0.6 + ang[:, 2] * 0.8)]              # lowest and hindmost: the angle
    top = v[np.argmax(np.where(v[:, 2] < 20, v[:, 1], -1e9))]
    cor = left[left[:, 2] > 30]; cor = cor[np.argmax(cor[:, 1])]
    mid = v[np.abs(v[:, 0]) < 1.0]
    ram = left[(left[:, 1] > -45) & (left[:, 1] < -30) & (left[:, 2] < 50)]
    breadth = min(np.ptp(ram[np.abs(ram[:, 1] - y) < 0.7][:, 2]) for y in np.arange(-44, -30, 1.0))
    return {
        "bigonial breadth": round(2 * float(ang[:, 0].max()), 1),
        "bicondylar breadth": round(2 * float(left[left[:, 1] > -9][left[left[:, 1] > -9][:, 2] < 20][:, 0].max()), 1),
        "ramus height condylion-gonion": round(float(np.linalg.norm(top[1:] - gon[1:])), 1),
        "minimum ramus breadth": round(float(breadth), 1),
        "symphysis height": round(float(mid[:, 1].max() - mid[:, 1].min()), 1),
        "chin: pogonion z, menton y": [round(float(mid[:, 2].max()), 1), round(float(mid[:, 1].min()), 1)],
        "gonion": np.round(gon, 1).tolist(), "condylion": np.round(top, 1).tolist(), "coronion": np.round(cor, 1).tolist(),
        "mandibular plane to Frankfurt, degrees": round(float(np.degrees(np.arctan2(gon[1] - mid[:, 1].min(), mid[mid[:, 1].argmin(), 2] - gon[2]))), 1),
    }


def clearance(v, h=1.0):
    """How near the mandible comes to the cranium (mm): the least distance, and where. Negative = overlap."""
    import skull
    Fs, _ = skull.build(h, log=lambda *a: None)
    D = sdf.mirror_field(Fs.D)
    lo = np.array([-Fs.ax[0][-1], Fs.lo[1], Fs.lo[2]])
    d = sdf.sample_field(D, lo, h, v)
    i = int(np.argmin(d))
    con = (v[:, 1] > -10) & (v[:, 2] < 18)
    cor = (v[:, 1] > -22) & (v[:, 2] > 28)
    top = con & (v[:, 1] > -1.5)
    return {"least distance to the cranium": round(float(d[i]), 2), "at": np.round(v[i], 1).tolist(),
            "condyle to temporal bone, least": round(float(d[con].min()), 2), "condyle at": np.round(v[con][np.argmin(d[con])], 1).tolist(),
            "condyle top to fossa roof": round(float(d[top].min()), 2),
            "coronoid to cranium, least": round(float(d[cor].min()), 2)}


def make(out, h=0.5, draft=False):
    import make as mk
    t = time.time()
    F, info = build(h)
    D = sdf.mirror_field(F.D)
    lo = np.array([-F.ax[0][-1], F.lo[1], F.lo[2]])
    fine, final, pieces = sdf.finish(D, lo, h, 10 ** 9 if draft else 22000, rounds=6 if draft else 10)
    v, f = fine if draft else final
    rep = sdf.report(v, f); rep["pieces_in_field"] = pieces; rep["crumbs_left_out"] = sdf.finish.dropped
    sizes = measure(fine[0])
    gap = clearance(fine[0])
    print(mk.clock(), "mandible %.0f s" % (time.time() - t), rep, flush=True)
    print("sizes", sizes, flush=True)
    print("clearance", gap, flush=True)
    m = [(v, f, view.BONE)]
    ff = f[v[f].mean(1)[:, 0] > 0.4]
    used = np.unique(ff); re = -np.ones(len(v), np.int64); re[used] = np.arange(len(used))
    half = [(v[used], re[ff], view.BONE)]
    rows = [mk.views(m, ["front", "left side", "three-quarter"], 560),
            [(view.picture(m, view.VIEWS["top"], 560), "top"), (view.picture(m, view.VIEWS["below"], 560), "below"),
             (view.picture(half, (-1, 0, 0), 560), "left half, inner surface")]]
    refs = [(mk.plate(out, n, 560), "reference: Gray's Anatomy 1918 (public domain), " + n) for n in ("Gray176.png", "Gray177.png")]
    refs = [r for r in refs if r[0] is not None]
    if refs:
        rows.append(refs)
    view.sheet(rows, os.path.join(out, "checks", "mandible_draft.png" if draft else "mandible.png"),
               "Mandible built from landmarks (no imported 3D)  h = %.2f mm, %d triangles" % (h, len(f)))
    if not draft:
        marks = dict(L.MANDIBLE)
        marks.update({"gonion": sizes["gonion"], "condylion": sizes["condylion"], "coronion": sizes["coronion"],
                      "mental foramen": info["mental foramen"]})
        mk.save_bone(out, "mandible", v, f, {
            "name": "mandible", "side": "midline", "group": "skull",
            "how": "body: seven traced cross-sections swept along the dental arch between the alveolar crest and the lower border "
                   "(sdf.Sweep); ramus: a thin drawn outline in its own plane, thickened along the hind border, the angle and the "
                   "inner ridges; condyle seated in the mandibular fossa, mouth closed; "
                   "left half computed and mirrored; grid %.2f mm" % h,
            "landmarks_mm_head_frame": marks, "measured_mm": sizes, "clearance_mm": gap, "mesh": rep})
    return v, f
