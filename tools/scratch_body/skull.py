"""skull.py: the cranium (skull without the mandible) made from landmarks alone.

The braincase is a star-shaped surface about a centre: its radius in every direction is
interpolated through craniometric landmarks, so length, breadth and height are what the table
says. The face is built on it from simple solids (maxilla, zygomatic bones and arches, nasal
bones, pterygoid plates, palate, mastoid and styloid processes, condyles) with smooth joins, and
the hollows are cut (orbits, nasal cavity, cranial cavity, foramen magnum, ear holes, joint
sockets). The left half is computed and mirrored, so the skull is symmetric by construction.
Head frame, millimetres: see landmarks.py.
"""
import numpy as np
from scipy import ndimage

import sdf
from sdf import Ellipsoid, Box, Tube, Field, spline, rot, unit
import landmarks as L

C = np.array([0.0, 45.0, -2.0])          # the centre the braincase is drawn about

MIDLINE = [(0, 27, 91), (0, 34, 94.5), (0, 46, 92.6), (0, 68, 87.0), (0, 88, 71.5), (0, 103, 45.5), (0, 111, 14),
           (0, 115, -12), (0, 112, -38), (0, 101, -62), (0, 78, -82), (0, 52, -89), (0, 25, -87), (0, 2, -78),
           (0, -14, -62), (0, -26, -40), (0, -24, -22), (0, -22, -5), (0, -17, 8), (0, -8, 28), (0, 2, 48),
           (0, 14, 70)]
SIDE = [
    (48, 47, 71), (54, 62, 52),                                       # least frontal breadth, temporal line
    (42.0, 10, 47), (50.5, 30, 43), (56.5, 48, 40),                   # temporal fossa: greater wing, pterion
    (56, 10, 24), (62.5, 30, 18), (61, 8, 0), (66.5, 30, -8),         # squama above the ear
    (56, 5, -50), (64, 28, -42),                                      # asterion, mastoid angle
    (30, 6, -77),                                                     # occipital beside the protuberance
    (45, -12, -52), (50, -16, -28), (32, -27, -34),                   # nuchal plane, behind the mastoid, beside the foramen
    (40, -14, -2), (26, -20, -2), (22, -10, 24), (40, -5, 30), (44, -3, 12), (20, -1, 48),   # the base
    (16, 38.5, 92), (30, 41, 88.5), (43, 40, 81.5),                   # the frontal just above the orbit's upper margin
    (40.5, 22, 55), (50, 46, 60),                                     # temporal fossa behind the orbit
    (71, 62, -27), (67.5, 62, -2), (63, 62, 16), (59.5, 66, 30),      # euryon; the vault narrows forward from the parietal eminence (ovoid from above)
]


def egg(P):
    """The braincase's ground shape: an egg, blunt in front, broadest and fullest behind the ears (< 0 inside)."""
    x, y, z = np.abs(P[:, 0]), P[:, 1] - 50.0, P[:, 2] + 12.0
    c = np.where(z > 0, 102.0, 78.0)
    sy = np.where(y > 0, 65.0, 60.0)
    return (x / 71.0) ** 2.12 + np.abs(y / sy) ** 2.12 + np.abs(z / c) ** 2.3 - 1.0      # rounder across (crown), fuller along


FACE_C = np.array([0.0, -10.0, 64.0])    # the centre the face's outer surface is drawn about
FACE_MID = [(0, 27, 90.5), (0, 18, 96.5), (0, 10, 101), (0, 5, 104), (0, -5, 101), (0, -15, 97.5), (0, -25, 95.5),
            (0, -31, 93.5), (0, -38, 95.5), (0, -43, 96.5), (0, -45.3, 92.5), (0, -44.5, 80), (0, -42, 65), (0, -40, 52),
            (0, -30, 45.5), (0, -15, 44), (0, 5, 44), (0, 22, 50), (0, 26, 70)]
FACE_SIDE = [
    (5.5, 20, 92.5), (7, 9, 96.5), (6.5, 5, 100.5),                   # side of the nasal bone
    (11.5, 22, 86), (12.5, 10, 87.5), (13.5, 0, 88.5),                # frontal process of the maxilla: inner rim of the orbit
    (13.8, -8, 90.5), (13.2, -18, 92.3), (10.5, -24.5, 93.8),         # rim of the piriform opening
    (20, -1.5, 86.5), (30, -1, 84.5), (40, 0.5, 80),                  # lower rim of the orbit
    (47.5, -1, 75.5), (51.5, -8, 71), (56.5, -5, 62),                   # zygomatic: rim, cheek prominence, outer face
    (55.5, -12.5, 61), (48, -19.5, 67), (39, -21.5, 72),                # its lower border
    (51, -6, 55), (44, -10, 50),                                      # behind the zygomatic
    (27, -8, 85), (25, -21, 84.3), (33, -19, 78.5),                   # infraorbital surface, canine fossa
    (17, -29, 91.3), (16.8, -40, 92.3), (9, -41, 95.6), (8.5, -33, 94),      # canine eminence, incisor crest
    (23.5, -40.5, 80.5), (26.8, -39.5, 73), (30.6, -38.5, 64), (32.3, -37.5, 55), (31.5, -35, 46.5),   # cheek side of the crest
    (29.5, -28, 66), (35.5, -22, 66.5), (32.5, -25, 53),              # cheek wall, buttress under the zygomatic
    (29, -30, 43.5), (30, -14, 47), (22, -18, 44.5),                  # tuberosity and the back of the maxilla
    (15, -44.3, 78), (22, -42.5, 66), (27, -40.3, 52), (12, -44.5, 88),      # under the crest
    (13, 4, 46), (10.5, 24, 60), (9, 27, 82),                         # top and back (joined to the braincase)
    (25, 6, 60), (38, 4, 62),                                         # under the orbit (the orbit's cut makes the floor)
]


# sutures of the vault, left side and midline (control points; each is put on the surface before use)
SUTURES = {
    "sagittal": [(0, 111, 14), (0, 115, -12), (0, 112, -38), (0, 101, -62), (0, 78, -82)],
    "coronal, left": [(0, 111, 14), (24, 105, 18), (43, 90, 25), (54, 70, 32), (56, 50, 37), (54, 34, 40)],
    "lambdoid, left": [(0, 78, -82), (20, 63, -81), (37, 43, -74), (49, 23, -63), (56, 5, -50)],
    "squamosal, left": [(54, 34, 40), (58, 41, 27), (63, 46, 8), (65, 44, -12), (63, 33, -31), (58, 15, -44), (56, 5, -50)],
    "sphenofrontal, left": [(54, 34, 40), (51, 32, 50), (47, 29, 59)],
    "sphenosquamosal, left": [(54, 34, 40), (56, 23, 35), (55, 12, 32)],
    "occipitomastoid, left": [(56, 5, -50), (52, -7, -43), (46, -17, -34), (40, -23, -25)],
}


class Vault:
    """A star-shaped surface: its radius for every direction from the centre C, drawn smoothly through
    landmark points (a table every degree). Used for the braincase and for the face's outer surface."""
    def __init__(self, s=0.40, ridge=2e-4, C=C, mid=MIDLINE, side=SIDE, base=None):
        C = np.asarray(C, float); self.C = C
        self.base = base            # (centre, half axes) of an ellipsoid the surface falls back to between landmarks
        pts = np.array(list(mid) + list(side) + [(-x, y, z) for x, y, z in side], float)
        rel = pts - C
        r = np.linalg.norm(rel, axis=1); u = rel / r[:, None]
        if base is not None:            # away from every landmark the surface is held to the ground shape
            k = np.arange(260) + 0.5
            ph = np.arccos(1 - 2 * k / 260); th = np.pi * (1 + 5 ** 0.5) * k
            a = np.stack([np.cos(th) * np.sin(ph), np.cos(ph), np.sin(th) * np.sin(ph)], axis=1)
            a[:, 0] = np.abs(a[:, 0])
            far = np.sqrt(((a[:, None, :] - u[None, :, :]) ** 2).sum(-1)).min(1) > 0.42
            a = a[far]; a = np.concatenate([a, a * np.array([-1, 1, 1])])
            u = np.concatenate([u, a]); r = np.concatenate([r, self.fallback(a)])
        K = np.exp(-((u[:, None, :] - u[None, :, :]) ** 2).sum(-1) / (2 * s * s))
        r0 = self.fallback(u)
        self.mean = (r - r0).mean()
        self.w = np.linalg.solve(K + ridge * np.eye(len(u)), r - r0 - self.mean)
        self.u, self.s = u, s
        self.residual = float(np.abs(K @ self.w + self.mean + r0 - r).max())
        th = np.radians(np.arange(0, 181)); ph = np.radians(np.arange(-180, 181))
        T, P = np.meshgrid(th, ph, indexing="ij")
        d = np.stack([np.sin(T) * np.sin(P), np.cos(T), np.sin(T) * np.cos(P)], axis=-1)
        self.table = self.radius_exact(d.reshape(-1, 3)).reshape(T.shape).astype(np.float32)

    def fallback(self, d):
        if self.base is None:
            return np.zeros(len(d))
        lo, hi = np.zeros(len(d)), np.full(len(d), 200.0)       # where the ray from C leaves the ground shape
        for _ in range(40):
            mid = (lo + hi) / 2
            ins = self.base(self.C + d * mid[:, None]) < 0
            lo, hi = np.where(ins, mid, lo), np.where(ins, hi, mid)
        return (lo + hi) / 2

    def radius_exact(self, d):
        K = np.exp(-((d[:, None, :] - self.u[None, :, :]) ** 2).sum(-1) / (2 * self.s ** 2))
        return K @ self.w + self.mean + self.fallback(d)

    def radius(self, dx, dy, dz, r):
        th = np.degrees(np.arccos(np.clip(dy / np.maximum(r, 1e-6), -1, 1)))
        ph = np.degrees(np.arctan2(dx, dz)) + 180.0
        return ndimage.map_coordinates(self.table, [th, ph], order=1, mode="nearest")

    def field(self, X, Y, Z):
        C = self.C
        dx, dy, dz = X - C[0], Y - C[1], Z - C[2]
        dx, dy, dz = np.broadcast_arrays(dx, dy, dz)
        r = np.sqrt(dx * dx + dy * dy + dz * dz)
        return (r - self.radius(dx, dy, dz, r)).astype(np.float32), (dy / np.maximum(r, 1e-6)).astype(np.float32)

    def on(self, p, depth=0.0):
        """The point of the surface on the ray from C through p, sunk `depth` mm into the bone."""
        p = np.atleast_2d(np.asarray(p, float)); d = p - self.C
        u = d / np.linalg.norm(d, axis=1, keepdims=True)
        return self.C + u * (self.radius_exact(u) - depth)[:, None]


def arch(ctrl, step=1.0):
    """A dental arch's left half seen from above, as a smooth line of (x, z) from the midline back."""
    P = np.array([(-ctrl[1][0], ctrl[1][1])] + list(ctrl), float)
    Q = spline(np.column_stack([P[:, 0], np.zeros(len(P)), P[:, 1]]), step)
    Q = Q[Q[:, 0] >= -1e-9]
    Q[0, 0] = 0.0
    return Q[:, [0, 2]]


def sockets(ctrl, table, upper, start=0.0, mids=None):
    """16 socket frames of one arch: where each tooth stands on the alveolar crest.
    position (mm, head frame), outward (toward lip or cheek), axis (from root tip to crown tip), width.
    `mids`: each tooth's place along the arch (mm from the midline) when given (teeth.packed), else from the widths."""
    A = arch(ctrl, 0.25)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(A, axis=0), axis=1))])
    out, at = [], start                 # `start`: where the first tooth's inner side lies along the arch (mm from the midline)
    for k, name in enumerate(L.TEETH):
        w = table["width"][k]; mid = at + w / 2; at += w
        if mids is not None and k < len(mids):
            mid = float(mids[k])
        x, z = np.interp(mid, d, A[:, 0]), np.interp(mid, d, A[:, 1])
        x2, z2 = np.interp(mid + 0.5, d, A[:, 0]), np.interp(mid + 0.5, d, A[:, 1])
        x1, z1 = np.interp(mid - 0.5, d, A[:, 0]), np.interp(mid - 0.5, d, A[:, 1])
        t = unit([x2 - x1, 0, z2 - z1])                     # along the arch, toward the back
        o = unit([-t[2], 0, t[0]]) * (1 if (-t[2]) * x + t[0] * z > 0 else -1)
        o = o if o[0] >= 0 else -o
        if k < 2 and o[2] < 0:
            o = -o
        tilt = np.radians(table["labial tilt deg"][k])
        ax = unit(np.array([0, -1.0 if upper else 1.0, 0]) * np.cos(tilt) + o * np.sin(tilt))
        for side, sx in (("L", 1), ("R", -1)):
            m = np.array([sx, 1, 1])
            out.append({"tooth": ("upper " if upper else "lower ") + name, "side": side,
                        "position_mm": np.round(np.array([x, table["crest y"][k], z]) * m, 2).tolist(),
                        "outward": np.round(o * m, 4).tolist(), "axis": np.round(ax * m, 4).tolist(),
                        "along_arch": np.round(t * m, 4).tolist(),
                        "width_mm": w, "crown_mm": table["crown"][k], "root_mm": table["root"][k]})
    return out


# half the cheek-to-tongue size of each socket's mouth (mm), midline tooth to third molar: kept inside the bone as built
SOCKET_HALF = {True: [2.3, 2.1, 2.7, 2.9, 2.9, 3.7, 3.7, 3.4], False: [1.8, 1.8, 2.5, 2.8, 2.9, 3.7, 3.7, 3.5]}


def cut_sockets(F, frames, upper):
    """Empty tooth sockets (alveoli) cut into a jaw's left half at the socket frames: one tapering pit a tooth
    (a simplification: the molars' pits are not divided for their several roots)."""
    for s in frames:
        if s["side"] != "L":
            continue
        k = L.TEETH.index(s["tooth"].split(" ", 1)[1])
        p, ax, al = np.array(s["position_mm"]), np.array(s["axis"]), np.array(s["along_arch"])
        a0 = s["width_mm"] / 2 - 0.8
        b0 = SOCKET_HALF[upper][k]
        depth = min(0.8 * s["root_mm"], 10.5)
        P = np.array([p + 1.0 * ax, p - 0.35 * depth * ax, p - depth * ax])
        F.cut(Tube(P, [(0, a0), (0.35, 0.85 * a0), (1, 0.4 * a0)], [(0, b0), (0.35, 0.85 * b0), (1, 0.4 * b0)], up=al, n=2.4), 0.5)


def build(h=1.0, parts=False, log=print):
    V = Vault(0.40, 1e-3, base=egg)
    log("vault: %d landmarks, worst miss %.2f mm" % (len(V.u), V.residual))
    F = Field([0, -50, -96], [82, 121, 110], h)
    X, Y, Z = F.coords(tuple(slice(0, n) for n in F.n))
    F0 = np.empty(F.n, np.float32); UY = np.empty(F.n, np.float32)
    for i in range(0, F.n[0], 16):
        F0[i:i + 16], UY[i:i + 16] = V.field(X[i:i + 16], Y, Z)
    F.D = F0.copy()
    up = (0, 1, 0)

    # ---- the face's outer surface, drawn through its own landmarks, joined to the braincase -----
    FV = Vault(0.33, 1e-4, FACE_C, FACE_MID, FACE_SIDE)
    log("face: %d landmarks, worst miss %.2f mm, radius %.0f to %.0f" % (len(FV.u), FV.residual, FV.table.min(), FV.table.max()))
    sl = F.window((0, -50, 38), (60, 34, 110))
    Xs, Ys, Zs = F.coords(sl)
    F.D[sl] = sdf.smin(F.D[sl], FV.field(Xs, Ys, Zs)[0], 5.0)
    # ---- frontal: the swelling over the inner half of the orbit's upper margin ---------------------
    brow = spline([(34, 41.5, 85.5), (25, 42, 88), (15, 39.5, 90.5), (6, 36, 91.5), (0, 35, 91.8)], 2)
    F.add(Tube(brow, [(0, 3.0), (0.5, 4.6), (1, 4.6)], [(0, 3.0), (0.5, 4.6), (1, 4.8)], up=(0, 1, 0)), 7)
    # ---- between the orbits (ethmoid region) -----------------------------------------------------
    F.add(Box((0, 13, 66), (11.4, 16, 22), 5), 4)
    # ---- zygomatic: frontal process (outer rim of the orbit), the wall behind it, the arch --------
    rim = spline([(50, -3, 71.5), (52, 9, 70.5), (52, 20, 71), (51, 28, 72.5), (49, 34.5, 75.3), (46, 38.6, 79.6)], 2)
    F.add(Tube(rim, [(0, 7.2), (0.5, 5.4), (0.82, 5.0), (1, 3.0)], [(0, 4.0), (0.5, 3.5), (0.82, 3.3), (1, 2.2)], up=(-0.35, 0, 0.94), n=2.2), 7)   # thinning into the frontal bone above, no knob
    # the body of the zygomatic bone: a broad plate facing forward and outward under the orbit's outer corner
    F.add(Ellipsoid((46.0, -9.0, 70.5), (10.0, 12.0, 4.4), rot((0, 1, 0), 40)), 6)
    F.add(Ellipsoid((54.3, 3.5, 62.0), (3.4, 7.5, 8.0)), 6)       # the rounded corner between its frontal and temporal processes
    wall = spline([(51, 17, 69), (44, 18, 60), (36, 19, 51), (27, 20, 43)], 2)
    F.add(Tube(wall, [(0, 18.0), (1, 10)], 2.6, up=up, n=3), 7)
    za = spline([(54, -6.5, 61), (58.8, -4.4, 54), (63.1, -2.2, 46), (64.5, -0.8, 36), (64.4, -0.2, 27), (63.4, 0.2, 19),
                 (61.8, 1.5, 11), (60.8, 3.2, 3), (60, 4.2, -6), (58.5, 5, -16)], 2)
    F.add(Tube(za, [(0, 9.5), (0.2, 6.4), (0.5, 4.6), (0.75, 4.4), (1, 2.5)], [(0, 3.9), (0.25, 2.3), (0.55, 2.0), (0.75, 2.5), (1, 2.0)], up=up, n=2.3), 3.5)
    # ---- temporal: root of the arch, articular tubercle, tympanic plate, mastoid -----------------
    F.add(Ellipsoid((54, 1.2, 11), (10.5, 4.6, 13)), 5)
    F.add(Ellipsoid((52, -3.6, 22), (11, 4.0, 5.0), rot((0, 1, 0), -12)), 4)
    F.add(Ellipsoid((49, -7.5, 1.5), (11, 8.5, 3.6), rot((0, 1, 0), -18)), 3)
    F.add(Tube(np.array([(48.5, -2, -17.0), (49.5, -14, -14.5), (50.3, -26.5, -11.5)]), [(0, 13.0), (0.5, 9.5), (1, 4.6)],
               [(0, 10.5), (0.5, 7.6), (1, 4.0)], up=(0, 0, 1)), 7)
    # ---- occipital: condyles, protuberance, nuchal lines ------------------------------------------
    F.add(Ellipsoid((17.5, -23.2, -14), (5.8, 5.6, 12), rot((0, 1, 0), 27)), 3.5)
    F.add(Ellipsoid((0, 1.5, -78.5), (8, 6, 4.5)), 5)
    sup = V.on([(0, 2, -79), (16, 4, -80), (32, 4, -72), (45, 0, -58), (52, -5, -42), (55, -9, -28)], 1.9)
    sup[0, 0] = 0
    F.add(Tube(spline(sup, 2), [(0, 2.9), (1, 2.3)]), 2.5)
    inf = V.on([(0, -12, -64), (15, -13, -62), (30, -15, -52), (40, -17, -40)], 1.5)
    inf[0, 0] = 0
    F.add(Tube(spline(inf, 2), 2.0), 2.0)
    crestline = V.on([(0, 0, -79), (0, -10, -68), (0, -18, -54), (0, -24, -44)], 1.0)
    crestline[:, 0] = 0
    F.add(Tube(spline(crestline, 2), 1.9), 2.0)
    # superior temporal line: a low, broad swelling arching over the temporal fossa (kept faint on purpose)
    tl = V.on([(47.5, 41, 73), (50.5, 54, 62), (55, 70, 40), (59, 79, 10), (59.5, 78, -18), (57, 66, -42), (55, 46, -52), (56.5, 26, -46), (59, 12, -30)], 2.6)
    F.add(Tube(spline(tl, 2), 3.0), 3.0)
    # sutures of the vault: shallow grooves where the bones meet (the lines the cranium is later split along)
    build.sutures = {}
    for name, pts in SUTURES.items():
        line = V.on(pts, -0.35)                      # the groove's centre line rides just above the surface
        if all(p[0] == 0 for p in pts): line[:, 0] = 0
        F.cut(Tube(spline(line, 1.5), 1.0), 0.6)
        build.sutures[name] = np.round(V.on(pts, 0.0), 1).tolist()
    # ---- sphenoid: pterygoid process, its two plates ------------------------------------------------
    F.add(Ellipsoid((19, -7, 43.5), (10.5, 6.5, 6.5)), 4)
    F.add(Tube(np.array([(24, -6, 43.0), (25.5, -22, 42.5), (26.4, -37.2, 42.0)]), [(0, 9.0), (0.55, 7.6), (1, 4.0)], 1.7,
               up=(0.5, 0, -0.866), n=2.2), 2)

    # =========================== the hollows ===========================
    # cranial cavity: the wall is thicker on the base than over the vault
    T = 6.0 + 7.0 * np.clip((0.05 - UY) / 0.6, 0, 1) ** 1.0
    o = unit(np.array([27.0, 30, 62]) - C)
    for i in range(0, F.n[0], 16):
        dx, dy, dz = np.broadcast_arrays(X[i:i + 16] - C[0], Y - C[1], Z - C[2])
        r = np.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
        cosang = (dx * o[0] + dy * o[1] + dz * o[2]) / r
        T[i:i + 16] += 24.0 * np.exp(-(np.arccos(np.clip(cosang, -1, 1)) / np.radians(21)) ** 2)
    F.D = np.maximum(F.D, -(F0 + T))
    del T
    # orbit: a four-sided funnel running back and toward the midline
    oz = np.array([98, 87, 78, 70, 62, 54, 46, 39.0])
    med = np.array([12.1, 12.0, 12.0, 12.3, 12.7, 13.2, 14.2, 15.6])
    lat = np.array([54.4, 53.4, 51.6, 47, 40.5, 32.5, 24.5, 19])
    flo = np.array([-0.7, -0.5, 0.2, 1.6, 4.5, 8.5, 13.5, 17.5])
    roo = np.array([35.5, 35.3, 35.3, 35.5, 33.8, 30.5, 26, 22.5])
    zz = np.arange(98, 38.9, -2.0)
    sm = lambda a: np.interp(zz, oz[::-1], ndimage.gaussian_filter1d(np.interp(np.arange(39, 98.5, 1.0), oz[::-1], a[::-1]), 3.0, mode="nearest")[np.clip((oz[::-1] - 39).astype(int), 0, 59)])
    med, lat, flo, roo = sm(med), sm(lat), sm(flo), sm(roo)
    orb = np.column_stack([(med + lat) / 2, (flo + roo) / 2, zz])
    fr = np.linspace(0, 1, len(zz))
    F.cut(Tube(orb, list(zip(fr, (roo - flo) / 2)), list(zip(fr, (lat - med) / 2)), up=(0.105, 0.994, 0), n=2.3), 2.5)   # a rounded four-sided cone, its long axis sloping down and out
    # nasal cavity: a pear-shaped opening (narrow under the nasal bones, wide at the floor), then the chamber
    F.cut(Tube(np.array([(0, -11.0, 112.0), (0, -11.0, 97), (0, -10.5, 88)]), [(0, 14.6), (1, 15.2)], [(0, 10.6), (1, 11.2)], up=up, n=2.2,
               taper=0.5), 1.2)
    F.cut(Tube(np.array([(0, -10.0, 93.0), (0, -7.5, 84), (0, -6.5, 66), (0, -8.5, 43)]), [(0, 15.4), (0.25, 18.5), (0.6, 19.5), (1, 17.5)],
               [(0, 9.4), (0.3, 10.5), (1, 10.5)], up=up, n=2.3, taper=0.42), 2.0)
    A = arch(L.UPPER_ARCH, 1.0)
    zs = np.array([40, 46, 54.5, 63.5, 72, 78.8, 83.0])
    w = np.interp(zs, A[::-1, 1], A[::-1, 0]) - np.array([6.5, 6.5, 6.6, 6.4, 6.2, 6.4, 8.0])
    F.cut(Tube(np.column_stack([np.zeros(len(zs)), np.full(len(zs), -45.5), zs]), 13.5, list(zip(np.linspace(0, 1, len(zs)), np.maximum(w, 3.0))),
               up=up, n=2.3), 2.5)
    # joint socket for the mandible, ear hole, groove behind the mastoid, foramen magnum
    F.cut(Ellipsoid((51, -5.8, 10.5), (11.5, 8.3, 7.6), rot((0, 1, 0), -15)), 3)
    F.cut(Tube(np.array([(70, -5.2, -0.5), (58, -4.6, 0.5), (45, -3.5, 4.0)]), [(0, 5.2), (0.4, 4.4), (1, 3.4)], [(0, 4.6), (0.4, 3.8), (1, 3.0)], up=up), 1.2)
    F.cut(Tube(np.array([(45.5, -27, -24.0), (47, -22, -13), (47.5, -19, -4)]), 3.0), 2)
    F.cut(Tube(np.array([(0, -44, -22.5), (0, -2, -22.5)]), 17.5, 15.0, up=(0, 0, 1), n=2.4), 2.5)
    # small openings: infraorbital and supraorbital, optic canal and the fissure beside it
    F.cut(Tube(np.array([(27.5, -7.5, 92.0), (27, -4.5, 80)]), 1.9), 0.8)
    F.cut(Tube(np.array([(24.5, 35.3, 99.0), (24.5, 36.5, 84)]), 1.9), 0.8)          # supraorbital notch: a nick in the edge of the upper margin
    F.cut(Tube(np.array([(15, 21, 44.0), (9.5, 22.5, 30)]), 2.4), 1.0)
    F.cut(Tube(np.array([(20, 15, 43.0), (25.5, 27, 41), (22, 24, 30)]), 2.0), 1.0)

    for a, b, r in (((26, -22, 3), (27, -8, 5), 3.0),          # carotid canal
                    ((30.5, -26, -9.5), (29, -10, -8), 3.6),   # jugular foramen
                    ((24, -16, 22), (24, -2, 22), 2.3),        # foramen ovale
                    ((31, -14, 16), (31, -2, 16), 1.3),        # foramen spinosum
                    ((12.5, -18, 16), (12.5, -4, 16), 2.8),    # foramen lacerum
                    ((46.5, -22, -7), (46.5, -10, -6), 1.3),   # stylomastoid foramen
                    ((0, -40, 84.5), (0, -27, 82), 2.3),       # incisive fossa
                    ((17.5, -38, 50), (17, -27, 51), 1.7),     # greater palatine foramen
                    ((50.5, -9.5, 78.5), (46, -9, 70), 1.2)):  # zygomaticofacial foramen
        F.cut(Tube(np.array([a, b], float), r), 0.8)

    cut_sockets(F, sockets(L.UPPER_ARCH, L.UPPER, True), True)

    # =========================== thin things added after the cuts ===========================
    F.add(Box((0, -6.5, 64), (1.15, 21.5, 19), 1.0), 1.5, keep=3)                    # septum (its bony front edge lies back from the opening)
    F.add(Tube(np.array([(14.2, -7, 43.5), (13.8, -24, 42.5), (13.5, -39.5, 41.5)]), [(0, 6.0), (1, 4.8)], 1.5, up=(0.1, 0, -1), n=2.6), 2, keep=4)   # medial pterygoid plate
    F.add(Tube(spline([(10.4, -13.5, 88), (11.2, -15, 72), (10.8, -16.5, 54)], 2), 4.2, 2.3, up=(0.35, 1, 0)), 1.5, keep=3)     # inferior concha
    F.add(Tube(spline([(6.4, -0.5, 84), (7.0, -2, 70), (7.0, -3.5, 56)], 2), 3.8, 1.9, up=(0.3, 1, 0)), 1.5, keep=3)             # middle concha
    F.add(Tube(np.array([(0, -26.2, 89.5), (0, -25.5, 94.0), (0, -25.0, 97.8)]), [(0, 3.6), (0.5, 2.1), (1, 0.9)], [(0, 4.6), (0.5, 2.2), (1, 0.9)], up=up), 2.6, keep=3)  # anterior nasal spine
    F.add(Tube(spline([(43, -12.5, -3.0), (39.6, -23.0, 2.2), (35.2, -33.5, 9.0)], 1.0), [(0, 2.7), (0.35, 1.8), (1, 1.0)]), 2.0, keep=3)  # styloid
    F.add(Tube(np.array([(13.5, -37, 41.3), (14.4, -41.2, 40.6), (16.8, -41.8, 41.3)]), 1.3), 0.8, keep=3)                     # hamulus
    # sutures of the face: each a thin ribbon standing in the bone's surface; only the outer 0.6 mm is cut
    for name, (pts, upv, half) in FACE_SUTURES.items():
        groove(F, Tube(spline(np.array(pts, float), 1.5), half, 1.0, up=upv, n=2.0), 1.0)
        build.sutures[name] = [list(map(float, q)) for q in pts]
    groove(F, Ellipsoid((50, 26.5, 70), (9, 1.0, 10)), 1.0, 0.5)                                   # frontozygomatic, round the outer rim of the orbit
    groove(F, Ellipsoid((63.6, -1.0, 40), (7.0, 12.0, 1.0), rot((1, 0, 0), -35)), 1.0, 0.5)         # zygomaticotemporal, round the arch
    build.sutures["frontozygomatic, left (ring at)"] = [50, 26.5, 70]
    build.sutures["zygomaticotemporal, left (ring at)"] = [63.6, -1.0, 40]
    return F, V


GAP = 0.9          # mm left between two bones of the braincase where a suture is cut right through


def split_sheets(V):
    """The thin sheets that cut the braincase into its bones (left side and midline): along the sutures of
    the vault each sheet runs from outside the bone toward the centre the vault is drawn about; on the
    base two upright sheets carry on, one in front of the temporal bone (sphenosquamosal and
    sphenopetrosal lines, then across the midline between sphenoid and occipital), one behind it
    (from the asterion down the occipitomastoid line, then the petro-occipital line)."""
    sheets = []
    for name in ("sagittal", "coronal, left", "lambdoid, left", "squamosal, left", "sphenosquamosal, left"):
        pts = SUTURES[name]
        line = V.on(pts, 8.0)
        mid = all(p[0] == 0 for p in pts)
        if mid: line[:, 0] = 0
        P = spline(line, 1.5)
        P = np.vstack([P[0] + 1.5 * sdf.unit(P[0] - P[2]), P, P[-1] + 1.5 * sdf.unit(P[-1] - P[-3])])    # a little past both ends
        upv = V.C - P
        if mid: P[:, 0] = 0; upv[:, 0] = 0
        upv /= np.linalg.norm(upv, axis=1)[:, None]
        sheets.append(Tube(P, 15.0, GAP / 2, up=upv, n=4.0))
    front = spline(np.array([(59, -2, 33), (50, -2, 29.5), (40, -2, 21), (34.5, -2, 12.5), (24, -2, 10.5), (15, -2, 13.5), (11.5, -2, 17), (0, -2, 17.5)], float), 1.5)
    sheets.append(Tube(front, 23.0, GAP / 2, up=(0, 1, 0), n=4.0))
    behind = spline(np.array([(58.5, -8, -54), (56, -8, -50), (52, -8, -43), (46, -8, -34), (40, -8, -25), (36, -8, -18), (30.5, -8, -9.5), (22, -8, 0), (15, -8, 9), (11.5, -8, 17), (11.5, -8, 18.5)], float), 1.5)
    sheets.append(Tube(behind, 28.0, GAP / 2, up=(0, 1, 0), n=4.0))
    for q in [(54, 34, 40), (56, 5, -50), (55, 12, 32)]:                                      # where three sutures meet: a round plug through the wall
        sheets.append(Tube(np.array([V.on([q], -7.0)[0], V.on([q], 24.0)[0]]), 1.4))
    sheets.append(Ellipsoid((63.6, -1.0, 40), (6.5, 9.5, GAP / 2), rot((1, 0, 0), -35)))        # zygomaticotemporal, through the arch
    return sheets


PART_SEEDS = {      # a point inside each piece the sheets leave (left side; the right is the mirror image)
    "parietal": (61, 72, -20), "occipital": (0, 30, -84), "temporal": (63, 14, -6),
    "frontal, sphenoid, ethmoid and facial skeleton (not yet split)": (0, 62, 86),
}


def groove(F, prim, half, depth=0.6):
    """Cut a shallow V-shaped groove where the thin solid `prim` (half as thick as `half`) crosses the
    bone's surface: deepest on the solid's middle sheet, nothing at its faces."""
    sl, d = F.dist(prim, 2.0)
    if sl is not None:
        F.D[sl] += depth * np.clip(-d / half, 0.0, 1.0)


FACE_SUTURES = {
    "internasal": ([(0, 27, 92), (0, 18, 96.5), (0, 10, 101), (0, 5, 104)], (0, 0, 1), 4.0),
    "frontonasal and frontomaxillary, left": ([(0, 27, 92), (5, 26.8, 90.5), (9.5, 25.5, 88), (12.5, 22, 85.5)], (0, 0, 1), 4.0),
    "nasomaxillary, left": ([(6.0, 26.5, 90), (7.0, 17, 93), (9.0, 8, 96), (11.0, 2.5, 97.5)], (0.3, 0, 0.95), 4.0),
    "intermaxillary": ([(0, -26, 95), (0, -34, 94), (0, -43, 96.5)], (0, 0, 1), 4.0),
    "median palatine": ([(0, -41, 80), (0, -33.5, 66), (0, -32.5, 52), (0, -31.5, 46)], (0, 1, 0), 5.0),
    "transverse palatine, left": ([(0, -32.5, 56), (8, -33.5, 56), (15, -36.5, 56.5)], (0, 1, 0), 5.0),
    "zygomaticomaxillary, left": ([(32, 0, 85), (35, -8, 82.5), (39.5, -16, 78.5), (43.5, -22.5, 74)], (0.5, 0, 0.87), 5.0),
}


def measure(F):
    """The skull's own sizes, read off the field (mm)."""
    D = F.D; ax = F.ax
    ins = D < 0
    xs = ax[0][np.where(ins.any(axis=(1, 2)))[0]]
    out = {}
    zany = ins.any(axis=(0, 1)); yany = ins.any(axis=(0, 2))
    # glabella-opisthocranion: extent in z of the braincase above the nose
    above = ins[:, ax[1] > 30, :].any(axis=(0, 1))
    z = ax[2][above]; out["skull length"] = float(z.max() - z.min())
    brain = ins[:, ax[1] > 20, :][:, :, ax[2] < 40].any(axis=(1, 2))
    out["skull breadth"] = float(2 * ax[0][brain].max())
    arch = ins[:, (ax[1] > -12) & (ax[1] < 8), :][:, :, (ax[2] > 15) & (ax[2] < 60)].any(axis=(1, 2))
    out["bizygomatic breadth"] = float(2 * ax[0][arch].max())
    col = ins[:4].any(axis=0)         # the midline plane and just beside it (the sagittal suture is a groove)
    y_top = ax[1][col.any(axis=1)].max()
    out["vertex above Frankfurt plane"] = float(y_top)
    fr = ins[:, (ax[1] > 40) & (ax[1] < 55), :][:, :, (ax[2] > 62) & (ax[2] < 76)].any(axis=(1, 2))
    out["least frontal breadth (near)"] = float(2 * ax[0][fr].max())
    mast = ins[:, (ax[1] < -22), :][:, :, (ax[2] > -22) & (ax[2] < 0)]
    m = mast[ax[0] > 44].any(axis=(1, 2))
    out["bimastoid breadth (outer, near tips)"] = float(2 * ax[0][ax[0] > 44][m].max()) if m.any() else None
    # the orbit's opening, at its narrowest in planes through the inner and outer margins (the outer margin lies behind the inner)
    phi = np.arctan2(15.0, 38.0); e1 = np.array([np.cos(phi), 0, -np.sin(phi)]); nn = np.array([np.sin(phi), 0, np.cos(phi)])
    ss = np.arange(-30, 30.01, 0.25); best = [1e9, 1e9]
    def run(d):
        m = len(ss) // 2
        if d[m] <= 0: return 1e9
        a = b = m
        while a > 0 and d[a - 1] > 0: a -= 1
        while b < len(ss) - 1 and d[b + 1] > 0: b += 1
        return (b - a + 1) * 0.25 if (a > 0 and b < len(ss) - 1) else 1e9
    for o in np.arange(-6, 6.1, 1.0):
        c = np.array([31.5, 17.0, 79.0]) + o * nn
        best[0] = min(best[0], run(sdf.sample_field(F.D, F.lo, F.h, c + ss[:, None] * e1)))
        best[1] = min(best[1], run(sdf.sample_field(F.D, F.lo, F.h, c + ss[:, None] * np.array([0, 1.0, 0]))))
    out["orbit opening breadth"] = float(best[0]) if best[0] < 1e8 else None
    out["orbit opening height"] = float(best[1]) if best[1] < 1e8 else None
    return {k: (round(v, 1) if v is not None else None) for k, v in out.items()}
