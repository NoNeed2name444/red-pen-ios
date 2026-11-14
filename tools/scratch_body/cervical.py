"""cervical.py: the seven neck vertebrae from one parametric vertebra (no imported 3D).

Each vertebra is built in its own frame (x left, y up along its body, z forward; origin at the centre
of the body), the left half computed and mirrored, then set on the column: a chain of bodies and
discs hung from the tip of the dens, each body tilted by its level's number (the neck's lordosis).
The joints are shared: one plane per facet joint, the bone above kept behind it and the bone below
in front of it with a gap between, so neighbours cannot overlap. Sizes: landmarks.CERVICAL.
"""
import os
import time
import numpy as np
import sdf, view, landmarks as L

EX = np.array([1.0, 0.0, 0.0])
GAP = 0.8                                   # half the joint space at a facet joint, mm
DENS = 15.5                                 # the dens above the axis's shoulders
ATLANTOAXIAL = (np.array([17.5, -42.3, -7.5]), sdf.unit((0.342, 0.940, 0.0)))     # the joint's plane, head frame
CONDYLE = ((17.5, -23.2, -14.0), (5.8, 5.6, 12.0), 27.0)                         # the skull's condyle (skull.py)
SPINE = {  # spinous process: length, drop of the tip, bifid
    "C2": (15.0, 5.0, True), "C3": (9.5, 3.4, True), "C4": (10.5, 4.2, True), "C5": (12.0, 5.4, True),
    "C6": (16.5, 9.0, True), "C7": (29.0, 15.5, False)}        # the drop keeps each pointing back and a little down in the body


class Super:
    """A block with a rounded outline seen from above (power n) and nearly flat ends with rounded rims (power m)."""
    def __init__(self, c, half, n=2.6, m=6.0, waist=0.0):
        self.c = np.asarray(c, float); self.half = np.asarray(half, float); self.n = n; self.m = m; self.waist = waist
        self.bounds = (self.c - self.half, self.c + self.half)

    def __call__(self, X, Y, Z):
        a, c, b = self.half
        r = (np.abs((X - self.c[0]) / a) ** self.n + np.abs((Z - self.c[2]) / b) ** self.n) ** (1.0 / self.n)
        t = (Y - self.c[1]) / c
        r = r / (1.0 - self.waist * np.clip(1.0 - t * t, 0.0, 1.0))          # drawn in a little at mid height
        k = (r ** self.m + np.abs(t) ** self.m) ** (1.0 / self.m)
        return ((k - 1.0) * self.half.min()).astype(np.float32)


class Half:
    """All space on the far side of a plane from its normal (inside where (X - p).n < 0), used within `box`."""
    def __init__(self, p, n, box):
        self.p = np.asarray(p, float); self.nrm = sdf.unit(n)
        self.bounds = (np.asarray(box[0], float), np.asarray(box[1], float))

    def __call__(self, X, Y, Z):
        n, p = self.nrm, self.p
        return ((X - p[0]) * n[0] + (Y - p[1]) * n[1] + (Z - p[2]) * n[2]).astype(np.float32)


def sym(P):
    """Points from the midline outward made into a line that crosses the midline squarely."""
    P = np.asarray(P, float)
    return np.concatenate([P[:0:-1] * np.array([-1.0, 1, 1]), P])


def frame(tilt):
    """A vertebra's axes in the head frame (columns: left, up, forward) for a forward tilt in degrees."""
    t = np.radians(tilt)
    return np.stack([EX, np.array([0, np.cos(t), np.sin(t)]), np.array([0, -np.sin(t), np.cos(t)])], axis=1)


def chain():
    """Where each vertebra sits and where its facet joints are.
    -> {name: {"c", "R", "up": (point, normal) or None, "low": (point, normal)}} in the head frame."""
    C = L.CERVICAL
    names = ["C2", "C3", "C4", "C5", "C6", "C7"]
    out = {}
    R = frame(C["C2"]["tilt"])
    c = np.array(L.DENS_TIP, float) - R[:, 1] * (DENS + C["C2"]["body"] / 2) - R[:, 2] * 1.75
    prev_joint = None
    for i, nm in enumerate(names):
        p = C[nm]
        u, f = R[:, 1], R[:, 2]
        low = c - u * p["body"] / 2
        if i + 1 < len(names):
            q = C[names[i + 1]]; Rn = frame(q["tilt"])
        else:
            q = {"body": 16.0, "depth": 17.5, "width": 27.0}; Rn = frame(p["tilt"] + 2.5)      # the first thoracic, for the last joint
        um, fm = sdf.unit(u + Rn[:, 1]), sdf.unit(f + Rn[:, 2])
        top_next = low - um * p["disc"]
        m = (low + top_next) / 2
        J = m + EX * ((p["width"] + q["width"]) / 4 + 9.5) - fm * ((p["depth"] + q["depth"]) / 4 + 9.0) + um * 2.0
        n = np.cos(np.radians(45)) * um - np.sin(np.radians(45)) * fm
        out[nm] = {"c": c.copy(), "R": R.copy(), "up": prev_joint, "low": (J, n), "lower end plate": low, "disc below": p["disc"]}
        prev_joint = (J, n)
        c = top_next - Rn[:, 1] * q["body"] / 2
        R = Rn
    return out


def vertebra(name, place, h):
    """One vertebra (C2 to C7) in its own frame: the Field of its left half."""
    p = L.CERVICAL[name]
    hw, hh, hd = p["width"] / 2, p["body"] / 2, p["depth"] / 2
    c, R = place["c"], place["R"]
    loc = lambda P: R.T @ (np.asarray(P, float) - c)
    vec = lambda n: R.T @ np.asarray(n, float)
    length, drop, bifid = SPINE[name]
    Jl, nl = loc(place["low"][0]), vec(place["low"][1])
    axis = name == "C2"
    if axis:
        Pa, na = loc(ATLANTOAXIAL[0]), vec(ATLANTOAXIAL[1])
        top = hh + DENS + 3
    else:
        Ju, nu = loc(place["up"][0]), vec(place["up"][1])
        top = Ju[1] + 9
    lo = np.array([0.0, min(Jl[1] - 9, -hh - drop - 9), -hd - 18 - length - 7])
    hi = np.array([hw + 20.0, top, hd + 9.0])
    box = (lo, hi)
    F = sdf.Field(lo, hi, h)
    F.add(Super((0, 0, 0), (hw, hh, hd), 2.6, 6.0, waist=0.10))
    # lower front lip of the body
    F.add(sdf.Tube(sdf.spline(sym([(0, -hh - 0.2, hd - 1.9), (hw * 0.5, -hh - 0.1, hd - 2.4), (hw - 3.5, -hh + 0.5, hd - 4.6)]), 1.5), 1.7), k=1.5)
    # articular pillar, between this bone's two facet joints
    B = Jl + GAP * nl
    if axis:
        A = B + np.array([0.0, 10.0, 1.0])                 # a short column above its lower facet
    else:
        A = Ju - GAP * nu
    d = sdf.unit(B - A)
    P = sdf.Field(lo, hi, h)
    P.add(sdf.Tube(np.array([A - (0 if axis else 1.0) * d, (A + B) / 2, B + 1.0 * d]), 5.5 if axis else [(0, 5.7), (0.5, 4.9), (1, 5.7)],
                   3.7 if axis else [(0, 3.9), (0.5, 3.1), (1, 3.9)], up=EX, n=2.4 if axis else 2.1))       # a column drawn in at its waist
    P.keep_inside(Half(B, -nl, box), k=3.4)
    if not axis:
        P.keep_inside(Half(A, nu, box), k=3.4)
    F.D = sdf.smin(F.D, P.D, 3.0)
    Pm = (A + B) / 2
    if axis:
        # the dens, and the shoulders that carry the atlas
        F.add(sdf.Tube(np.array([(0, hh - 4.0, 1.75), (0, hh + 5.0, 1.75), (0, hh + DENS - 5.1, 1.75)]),
                       [(0, 5.9), (0.5, 4.7), (1, 5.1)], [(0, 5.9), (0.5, 4.9), (1, 5.1)]), k=3.0)
        Sh = sdf.Field(lo, hi, h)
        Sh.add(sdf.Ellipsoid((15.0, hh - 3.5, -0.8), (8.4, 6.5, 8.4)))
        Sh.keep_inside(Half(Pa - GAP * na, na, box), k=0.6)
        F.D = sdf.smin(F.D, Sh.D, 3.0)
        F.add(sdf.Tube(np.array([(13.5, hh - 6.5, -hd + 2.5), Pm + np.array([-0.5, 1.0, 1.0])]), 4.6, 3.6), k=3.5)     # the thick pedicle and pars
    else:
        # uncinate process along the upper side edge
        F.cut(sdf.Ellipsoid((0, hh + 2.0, 0.0), ((hw - 1.6) / 0.745, 3.0, hd * 1.5)), k=1.2)        # the upper surface hollow from side to side
        F.add(sdf.Tube(sdf.spline([(hw - 1.4, hh + 0.7, -hd + 2.4), (hw - 1.1, hh + 0.8, -1.0), (hw - 1.9, hh - 0.6, hd - 4.5)], 1.5),
                       [(0, 2.9), (0.6, 2.4), (1, 1.0)], 1.5), k=1.5)
        # pedicle
        F.add(sdf.Tube(np.array([(hw - 2.6, 1.0, -hd + 1.6), Pm + np.array([-1.5, 0.0, 1.5])]), 3.6, 3.2), k=3.0)
    # lamina
    F.add(sdf.Tube(sdf.spline(sym([(0, -2.5, -hd - 17.0), (7.5, -1.5, -hd - 15.3), Pm + np.array([-3.5, -1.0, -2.5])]), 1.5),
                   6.0 if axis else 5.3, 2.4 if axis else 1.9, up=(0, 1, 0) if axis else (0, 0.94, 0.34)), k=3.0)      # a thin plate, its upper edge leaning forward
    # spinous process
    base = np.array([0, -2.5, -hd - 16.5]); tip = np.array([0, -2.5 - drop, -hd - 17.0 - length])
    if bifid:
        # a short stem that parts into two diverging tubercles
        stem = base + 0.6 * (tip - base)
        F.add(sdf.Tube(np.array([base, stem]), [(0, 5.2 if axis else 4.4), (1, 3.7 if axis else 3.1)], [(0, 3.0 if axis else 2.6), (1, 2.5 if axis else 2.2)]), k=3.0)
        end = tip + np.array([5.6 if axis else (3.6 if name == "C6" else 4.4), -1.2, 0.0])
        fork = sdf.spline([stem + np.array([0.5, 0.2, 0.6]), (stem + end) / 2 + np.array([0.9, 0.0, 0.5]), end], 1.0)
        F.add(sdf.Tube(fork, [(0, 3.0), (0.6, 2.6), (1, 2.3)], [(0, 2.2), (0.6, 2.0), (1, 2.1)]), k=2.2)
        F.add(sdf.Ellipsoid(end + np.array([0.2, -0.6, -0.3]), (2.5, 3.0, 2.6)), k=1.8)
    else:
        mid = (base + tip) / 2 + np.array([0, 1.1, 0])                       # a long spine, a little hollow along its lower edge
        F.add(sdf.Tube(sdf.spline([base, mid, tip], 1.5), [(0, 5.9), (0.45, 4.3), (0.85, 4.0), (1, 4.4)], [(0, 4.5), (0.45, 3.1), (0.85, 3.0), (1, 3.4)]), k=3.5)
        F.add(sdf.Ellipsoid(tip + np.array([0, -0.6, -0.6]), (4.4, 4.8, 3.6)), k=2.5)
    # transverse process: two roots, two tubercles, the bar between them
    if axis:
        pt = np.array([hw + 9.5, -5.5, -4.5])
        F.add(sdf.Tube(np.array([(hw - 1.5, 0.0, 2.0), (hw + 6.5, -3.0, 1.0), pt]), 2.4, 2.1), k=2.0)
        F.add(sdf.Tube(np.array([Pm + np.array([0.5, 1.0, 4.0]), pt]), 2.4), k=2.0)
        F.add(sdf.Ellipsoid(pt, (2.6, 2.8, 2.8)), k=1.5)
        F.add(sdf.Ellipsoid((hw + 5.0, -3.0, -1.5), (6.5, 2.6, 5.5)), k=2.0)
        F.cut(sdf.Tube(sdf.spline([(hw + 4.6, -12.0, -3.2), (hw + 4.6, -4.5, -3.2), (hw + 7.5, -1.0, -3.4), (hw + 14.0, 0.5, -3.6)], 1.0), 2.6), k=0.6)
        hole = None
    else:
        big = name == "C6"; last = name == "C7"
        at = np.array([hw + (9.0 if not last else 6.5), -2.8, 5.5 if big else (2.5 if last else 4.0)])
        pt = np.array([hw + (16.0 if last else 12.5), -3.2, -8.0 if last else -6.0])
        F.add(sdf.Tube(np.array([(hw - 1.5, 0.8, 1.8), at]), 2.5, 1.9), k=2.0)
        F.add(sdf.Tube(np.array([Pm + np.array([0.5, -1.0, 4.5]), pt]), 2.6 if last else 2.3), k=2.0)
        F.add(sdf.Tube(np.array([at, (at + pt) / 2 + np.array([0.8, -1.2, 0.0]), pt]), 2.0), k=1.5)
        F.add(sdf.Ellipsoid(at, (3.3, 3.5, 3.3) if big else ((1.8, 2.0, 1.8) if last else (2.4, 2.6, 2.4))), k=1.5)
        F.add(sdf.Ellipsoid(pt, (2.8, 3.0, 3.0) if last else (2.4, 2.6, 2.6)), k=1.5)
        F.add(sdf.Ellipsoid((hw + 6.0, -2.0, -1.5), (7.0, 2.3, 6.0)), k=2.0)                  # the plate the foramen pierces
        hole = (hw + 5.3, -2.8, 2.0 if last else 3.0)
        # gutter for the spinal nerve across the top of the process
        F.cut(sdf.Tube(np.array([(hw + 1.5, 3.4, -5.5), (hw + 15.0, 0.9, 0.5)]), 2.2), k=1.5)
    if hole is not None:
        F.cut(sdf.Tube(np.array([(hole[0], -11.0, hole[1]), (hole[0], 11.0, hole[1])]), hole[2]), k=0.6)
    # the vertebral canal, kept open and the back of the body flattened
    if axis:
        F.cut(sdf.Tube(np.array([(0, lo[1] - 5, -hd - 7.3), (0, hi[1] + 5, -hd - 7.3)]), 11.3, 7.5, up=EX, n=2.4), k=1.0)
    else:           # a triangle with rounded corners: wide behind the body, narrowing back to where the laminae meet
        F.cut(sdf.Tube(np.array([(0, lo[1] - 5, -hd - 5.9), (0, hi[1] + 5, -hd - 5.9)]), 11.6, 5.7, up=EX, n=2.5), k=1.0)
        F.cut(sdf.Tube(np.array([(0, lo[1] - 5, -hd - 10.2), (0, hi[1] + 5, -hd - 10.2)]), 7.4, 5.4, up=EX, n=2.0), k=1.5)
    return F


def atlas(h):
    """The atlas in the head frame (it has no body): the Field of its left half."""
    lo, hi = np.array([0.0, -49.0, -43.0]), np.array([45.0, -23.0, 11.0])
    box = (lo, hi)
    Pa, na = ATLANTOAXIAL
    M = sdf.Field(lo, hi, h)
    M.add(sdf.Ellipsoid((19.6, -35.2, -11.0), (8.7, 9.6, 12.4), sdf.rot((0, 1, 0), 18)))       # a rounded mass, long from front to back, its front end nearer the midline
    cc, cr, turn = CONDYLE
    M.cut(sdf.Ellipsoid(cc, np.array(cr) + 1.8, sdf.rot((0, 1, 0), turn)), k=0.8)       # the cup the condyle sits in
    M.keep_inside(Half(Pa + GAP * na, -na, box), k=0.6)                                 # lower joint surface
    F = sdf.Field(lo, hi, h)
    F.D = M.D.copy()
    F.add(sdf.Tube(sdf.spline(sym([(0, -35.5, 4.0), (7, -35.5, 3.2), (12.5, -35.5, 0.2), (16, -35.5, -4.0)]), 1.5), 4.6, 2.3, n=2.6), k=2.5)
    F.add(sdf.Ellipsoid((0, -36.6, 6.1), (3.5, 3.8, 2.4)), k=1.8)
    F.add(sdf.Tube(sdf.spline(sym([(0, -36.5, -35.0), (8.5, -36.5, -33.2), (15.5, -36.8, -27.5), (19.5, -37.0, -20.5)]), 1.5),
                   [(0, 3.0), (0.25, 3.3), (0.5, 4.5), (0.75, 3.3), (1, 3.0)], [(0, 2.6), (0.5, 3.1), (1, 2.6)]), k=3.0)
    F.add(sdf.Ellipsoid((0, -36.6, -37.5), (3.3, 3.7, 2.5)), k=1.8)
    F.add(sdf.Tube(np.array([(25.0, -37.5, -11.0), (31.0, -37.9, -11.4), (37.0, -38.2, -11.8)]), [(0, 3.1), (0.6, 2.7), (1, 2.6)], [(0, 6.8), (0.6, 5.8), (1, 4.4)]), k=3.0)
    F.add(sdf.Ellipsoid((37.6, -38.5, -12.2), (3.2, 3.7, 4.6)), k=2.0)
    F.add(sdf.Ellipsoid((11.6, -35.5, -8.5), (1.8, 2.6, 2.6)), k=1.5)                   # tubercle for the transverse ligament
    F.cut(sdf.Tube(np.array([(30.2, -47.0, -10.8), (30.2, -29.0, -10.8)]), 3.2), k=0.6)   # transverse foramen
    F.cut(sdf.Tube(sdf.spline([(27.0, -32.4, -21.5), (17.0, -32.3, -24.5), (10.0, -32.6, -22.5)], 1.5), 2.6), k=1.5)   # groove, vertebral artery
    return F


def world_points(F, c, R):
    X, Y, Z = np.meshgrid(F.ax[0], F.ax[1], F.ax[2], indexing="ij")
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1).astype(float)
    return P @ R.T + c                       # both halves alike: x is the same axis in every frame


def guard(F, c, R, other, gap):
    """Trim this bone wherever it comes within `gap` mm of the other (a finished whole field in its frame)."""
    D2, lo2, h2, c2, R2 = other
    W = world_points(F, c, R)
    d = sdf.sample_field(D2, lo2, h2, (W - c2) @ R2).reshape(F.D.shape)
    F.D = np.maximum(F.D, (gap - d).astype(np.float32))


def whole(F):
    return sdf.mirror_field(F.D), np.array([-F.ax[0][-1], F.lo[1], F.lo[2]])


def make(out, h=0.5, draft=False):
    import make as mk
    import skull
    t0 = time.time()
    Fs, _ = skull.build(1.0, log=lambda *a: None)
    cran = (sdf.mirror_field(Fs.D), np.array([-Fs.ax[0][-1], Fs.lo[1], Fs.lo[2]]), 1.0, np.zeros(3), np.eye(3))
    ch = chain()
    built, meshes, facts = {}, {}, {}
    order = ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]
    prev = None
    for nm in order:
        if nm == "C1":
            F = atlas(h); c, R = np.zeros(3), np.eye(3)
            guard(F, c, R, cran, 1.5)
        else:
            c, R = ch[nm]["c"], ch[nm]["R"]
            F = vertebra(nm, ch[nm], h)
            guard(F, c, R, prev, 1.2)
            if nm == "C2":
                guard(F, c, R, cran, 1.5)
        D, lo = whole(F)
        fine, final, pieces = sdf.finish(D, lo, h, 10 ** 9 if draft else (7000 if nm in ("C1", "C2") else 6000), rounds=6 if draft else 10, least=60)
        v, f = fine if draft else final
        rep = sdf.report(v, f); rep["pieces_in_field"] = pieces; rep["crumbs_left_out"] = sdf.finish.dropped
        vw, fw = v @ R.T + c, f
        dn = sdf.sample_field(prev[0], prev[1], prev[2], (fine[0] @ R.T + c - prev[3]) @ prev[4]) if prev is not None else None
        dc = sdf.sample_field(cran[0], cran[1], cran[2], fine[0] @ R.T + c)
        fw_ = fine[0] @ R.T + c
        front = np.ones(len(fw_), bool) if nm == "C1" else fine[0][:, 2] > -L.CERVICAL[nm]["depth"] / 2 - 1.0
        left = fw_[(fw_[:, 0] > 0) & front]
        marks = {"spinous tip" if nm != "C1" else "posterior tubercle": np.round(fw_[np.argmin(fine[0][:, 2])] * np.array([0, 1, 1]), 1).tolist(),
                 "left transverse process tip": np.round(left[np.argmax(left[:, 0])], 1).tolist()}
        if nm == "C1":
            marks["anterior tubercle"] = np.round(fw_[np.argmax(fw_[:, 2])] * np.array([0, 1, 1]), 1).tolist()
        else:
            marks["body centre"] = np.round(c, 1).tolist()
        if nm == "C2":
            marks["dens tip"] = np.round(fw_[np.argmax(fine[0][:, 1])] * np.array([0, 1, 1]), 1).tolist()
        facts[nm] = {"mesh": rep, "landmarks_mm_head_frame": marks, "least distance to the bone above": None if dn is None else round(float(dn.min()), 2),
                     "least distance to the cranium": round(float(dc.min()), 2) if dc.min() < 900 else None,
                     "centre_mm_head_frame": np.round(c, 1).tolist(), "tilt_deg": 0.0 if nm == "C1" else L.CERVICAL[nm]["tilt"]}
        print(mk.clock(), nm, facts[nm], flush=True)
        prev = (D, lo, h, c, R)
        meshes[nm] = (vw, fw, v, f)
    # sizes of the column
    c7 = ch["C7"]; tipw = None
    v7 = meshes["C7"][0]
    spine_tip = v7[np.argmin(v7[:, 2])]
    v1 = meshes["C1"][0]
    sizes = {
        "dens tip to the lower end plate of C7 (straight)": round(float(np.linalg.norm(np.array(L.DENS_TIP) - c7["lower end plate"])), 1),
        "top of the atlas to the lower end plate of C7, height": round(float(v1[:, 1].max() - c7["lower end plate"][1]), 1),
        "lordosis C2-C7 (difference of end plate tilts), degrees": L.CERVICAL["C7"]["tilt"] - L.CERVICAL["C2"]["tilt"],
        "atlas width": round(float(np.ptp(v1[:, 0])), 1), "atlas front to back": round(float(np.ptp(v1[:, 2])), 1),
        "C7 spinous tip, head frame": np.round(spine_tip, 1).tolist(),
        "C7 spinous tip above the soles, m": round(float(L.body(spine_tip)[1]), 3),
        "C7 lower end plate centre, head frame": np.round(c7["lower end plate"], 1).tolist(),
        "C2 body centre ahead of C7 body centre": round(float(ch["C2"]["c"][2] - ch["C7"]["c"][2]), 1),
    }
    print("sizes", sizes, "%.0f s" % (time.time() - t0), flush=True)
    col = [(meshes[n][0], meshes[n][1], view.BONE) for n in order]
    one = lambda n: [(meshes[n][2], meshes[n][3], view.BONE)]
    rows = [mk.views(col, ["front", "left side", "back", "three-quarter"], 520),
            [(view.picture(one("C4"), view.VIEWS["top"], 520), "C4 from above (front is up)"), (view.picture(one("C4"), view.VIEWS["left side"], 520), "C4, left side"),
             (view.picture(one("C1"), view.VIEWS["top"], 520), "atlas from above"), (view.picture(one("C2"), (0.5, 0.2, 0.8), 520), "axis, from the front and left")],
            [(view.picture(one("C7"), view.VIEWS["top"], 520), "C7 from above"), (view.picture(one("C7"), view.VIEWS["left side"], 520), "C7, left side"),
             (view.picture(one("C2"), view.VIEWS["left side"], 520), "axis, left side"), (view.picture(one("C2"), view.VIEWS["top"], 520), "axis from above")]]
    refs = [(mk.plate(out, n, 520), "reference: Gray's Anatomy 1918 (public domain), " + n) for n in ("Gray84.png", "Gray85.png", "Gray86.png", "../refs_axis/Gray87.png")]
    refs = [(im, cap.replace("../refs_axis/", "")) for im, cap in refs if im is not None]
    if refs:
        rows.append(refs)
    view.sheet(rows, os.path.join(out, "checks", "cervical_draft.png" if draft else "cervical.png"),
               "Cervical vertebrae C1-C7 from one parametric vertebra (no imported 3D)  h = %.2f mm" % h)
    if not draft:
        full = {"C1": "atlas (first cervical vertebra)", "C2": "axis (second cervical vertebra)"}
        for i, nm in enumerate(order):
            info = {"name": full.get(nm, "%s cervical vertebra" % ["third", "fourth", "fifth", "sixth", "seventh"][i - 2] if i >= 2 else nm),
                    "side": "midline", "group": "cervical spine",
                    "how": "one parametric vertebra with this level's numbers; left half computed and mirrored; set on the lordotic chain; "
                           "facet joints shared planes with a gap; grid %.2f mm" % h}
            info.update(facts[nm])
            if nm != "C1":
                info["numbers"] = L.CERVICAL[nm]
                info["facet joint below, left (point, normal), head frame"] = [np.round(ch[nm]["low"][0], 1).tolist(), np.round(ch[nm]["low"][1], 3).tolist()]
            mk.save_bone(out, nm, meshes[nm][0], meshes[nm][1], info)
        import json
        mp = os.path.join(out, "manifest.json")
        man = json.load(open(mp)); man["cervical_column"] = sizes
        json.dump(man, open(mp, "w"), indent=1)
    return meshes
