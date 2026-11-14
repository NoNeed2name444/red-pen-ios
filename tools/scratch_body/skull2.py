"""skull2.py: the cranium built on lines traced from plates (see plates.py for the plates and their scale).

Shape comes from the plates; nothing 3D is imported. The braincase is a star-shaped surface about a
centre, drawn through the traced side profile (Fig. 188), the traced outline of the vault from the
front (Fig. 190) and from below (Fig. 187). The face is a relief over the front view: a surface drawn
through the traced margins of the orbits, the nasal opening and the cheek bones, each given its depth
from the side view. Head frame, millimetres: see landmarks.py.
"""
import numpy as np
from scipy import ndimage, sparse
from scipy.sparse.linalg import spsolve

import sdf, plates, relief
import landmarks as L
import teeth, base, occiput, foramina, palate, surface, nose, temporal, pterygoid
from skull import arch, sockets, cut_sockets, groove
from relief import Map, Slab, Prism, Funnel
from sdf import Ellipsoid, Box, Tube, Field, spline, rot, unit, smin, smax

C = np.array([0.0, 45.0, -2.0])           # the centre the braincase is drawn about


def resample(P, step):
    P = np.asarray(P, float)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    t = np.arange(0, d[-1], step)
    return np.column_stack([np.interp(t, d, P[:, k]) for k in range(P.shape[1])])


class Traces:
    """The traced outlines in head-frame millimetres."""
    def __init__(self):
        T = plates.traces()
        self.F = plates.side_frame(T["side_silhouette_px"])
        self.side = self.F.mm(T["side_silhouette_px"])             # (z, y), closed, the whole skull with the mandible
        self.front = plates.front_mm(T["front_silhouette_px"])     # (x, y), both halves folded onto x >= 0
        self.front_px = T["front_silhouette_px"]
        self.base = plates.base_mm(T["base_silhouette_px"])        # (x, z)
        self.base_px = T["base_silhouette_px"]
        self.mark = {k: self.F.mm(v)[0] for k, v in plates.SIDE.items()}

    def profile(self, a0=-13.0, a1=-128.0, step=4.0):
        """The midline of the vault from the nasion up over the crown and down the back of the head: (z, y)
        every `step` degrees about the braincase centre (angles: 0 forward, 90 up)."""
        q = self.side
        a = np.degrees(np.arctan2(q[:, 1] - C[1], q[:, 0] - C[2]))
        r = np.hypot(q[:, 1] - C[1], q[:, 0] - C[2])
        out = []
        angs = np.concatenate([np.arange(a0, 180, step), np.arange(-180, a1, step)])
        for ang in angs:
            near = np.abs(((a - ang + 180) % 360) - 180) < step / 2
            if near.any():
                k = np.where(near)[0][np.argmax(r[near])]           # the outermost point in that direction
                out.append(q[k])
        return np.array(out)

    def face_profile(self):
        """The front edge of the side view from the brow down to the upper teeth: (z, y), y falling."""
        q = self.side
        k0 = np.argmax(q[:, 0])                                     # the tip of the nasal bones (the farthest forward point)
        # walk both ways from the nasal tip along the closed outline while staying on the front of the skull
        n = len(q); out = []
        for step in (1, -1):
            k, run = k0, []
            while len(run) < n // 3:
                run.append(q[k]); k = (k + step) % n
            out.append(np.array(run))
        up = out[0] if out[0][20, 1] > out[1][20, 1] else out[1]
        down = out[1] if up is out[0] else out[0]
        up = up[up[:, 1] <= 60]; down = down[down[:, 1] >= self.mark["prosthion"][1] - 1.0]
        return up, down

    def vault_side_from_front(self, y0=10.0, y1=110.0, step=5.0):
        """The vault's outline seen from the front (the skull's right half, which no leader line crosses),
        brought to the usual breadth: (x, y)."""
        px = self.front_px
        keep = px[:, 0] < plates.FRONT_MID - 150
        q = self.front[keep]
        q = q[(q[:, 1] >= y0) & (q[:, 1] <= y1)]
        q = q[np.argsort(-q[:, 1])]
        k = plates.BREADTH / (2 * q[:, 0].max())
        return resample(np.column_stack([q[:, 0] * k, q[:, 1]]), step), k

    def vault_side_from_below(self, z0=-80.0, z1=2.0, step=5.0):
        """The vault's outline seen from below, behind the cheek bone's arch, brought to the usual breadth: (x, z)."""
        px = self.base_px
        keep = px[:, 0] < plates.BASE_MID - 300
        q = self.base[keep]
        q = q[(q[:, 1] >= z0) & (q[:, 1] <= z1)]
        # the outermost point for every 2 mm of length (the outline doubles back round muscle markings)
        zs = np.arange(z0, z1, 2.0); out = []
        for z in zs:
            m = np.abs(q[:, 1] - z) < 1.5
            if m.any():
                out.append((q[m, 0].max(), z))
        out = np.array(out)
        k = plates.BREADTH / (2 * out[:, 0].max())
        return resample(np.column_stack([out[:, 0] * k, out[:, 1]]), step), k


class Egg:
    """The ground shape of the braincase: an egg with its own half-lengths forward, back, up and down, and its own
    fullness along each axis, fitted to the traced lines (< 0 inside)."""
    names = ("y0", "z0", "sx", "up", "down", "fore", "back", "px", "py", "pz")
    start = (50.0, -8.0, 71.0, 64.0, 62.0, 106.0, 76.0, 2.2, 2.2, 2.3)

    def __init__(self, p=None):
        self.p = np.array(self.start if p is None else p, float)

    def __call__(self, P):
        y0, z0, sx, up, down, fore, back, px, py, pz = self.p
        x, y, z = np.abs(P[:, 0]), P[:, 1] - y0, P[:, 2] - z0
        return (x / sx) ** px + np.abs(y / np.where(y > 0, up, down)) ** py + np.abs(z / np.where(z > 0, fore, back)) ** pz - 1.0

    def radius(self, C, d):
        """How far from C the egg's surface lies along each unit direction d."""
        lo, hi = np.zeros(len(d)), np.full(len(d), 220.0)
        for _ in range(40):
            mid = (lo + hi) / 2
            ins = self(C + d * mid[:, None]) < 0
            lo, hi = np.where(ins, mid, lo), np.where(ins, hi, mid)
        return (lo + hi) / 2

    def fit(self, C, pts):
        """Fit the egg to points of the vault (those above the ears carry the fit)."""
        from scipy.optimize import least_squares
        pts = np.asarray(pts, float); d = pts - C; r = np.linalg.norm(d, axis=1); d = d / r[:, None]
        lo = (35, -25, 60, 50, 40, 85, 60, 1.8, 1.8, 1.8); hi = (65, 10, 80, 80, 90, 125, 95, 2.5, 2.5, 2.5)

        def miss(p):
            self.p = np.asarray(p, float)
            return self.radius(C, d) - r
        out = least_squares(miss, self.p, bounds=(lo, hi), diff_step=1e-3, max_nfev=60)
        self.p = out.x
        return float(np.sqrt((miss(out.x) ** 2).mean()))


class Star:
    """A star-shaped surface about the centre C, kept as a table of its radius for every degree of direction.
    It starts as the fitted egg and is moved in or out, smoothly, wherever it is told it misses (move())."""
    def __init__(self, C, egg):
        self.C = np.asarray(C, float)
        th = np.radians(np.arange(0, 181)); ph = np.radians(np.arange(-180, 181))
        Tt, Pp = np.meshgrid(th, ph, indexing="ij")
        self.dd = np.stack([np.sin(Tt) * np.sin(Pp), np.cos(Tt), np.sin(Tt) * np.cos(Pp)], axis=-1).reshape(-1, 3)
        self.shape = Tt.shape
        self.table = egg.radius(self.C, self.dd).reshape(self.shape).astype(np.float64)

    def radius_dir(self, d):
        d = np.asarray(d, float)
        th = np.degrees(np.arccos(np.clip(d[:, 1], -1, 1))); ph = np.degrees(np.arctan2(d[:, 0], d[:, 2])) + 180.0
        return ndimage.map_coordinates(self.table, [th, ph], order=1, mode="nearest")

    def move(self, u, miss, s=0.30, ridge=0.02):
        """Move the surface by `miss` mm along each unit direction u (both sides alike), spread smoothly round about."""
        u = np.asarray(u, float); miss = np.asarray(miss, float)
        off = np.abs(u[:, 0]) > 0.02
        u = np.concatenate([u, u[off] * np.array([-1, 1, 1])]); miss = np.concatenate([miss, miss[off]])
        K = np.exp(-((u[:, None, :] - u[None, :, :]) ** 2).sum(-1) / (2 * s * s))
        w = np.linalg.solve(K + ridge * np.eye(len(u)), miss)
        add = np.empty(len(self.dd))
        for i in range(0, len(self.dd), 4000):
            add[i:i + 4000] = np.exp(-((self.dd[i:i + 4000, None, :] - u[None, :, :]) ** 2).sum(-1) / (2 * s * s)) @ w
        self.table += add.reshape(self.shape)

    def points(self, step=2):
        r = self.table[::step, ::step]
        d = self.dd.reshape(self.shape + (3,))[::step, ::step]
        return d.reshape(-1, 3), r.reshape(-1)

    def radius(self, dx, dy, dz, r):
        th = np.degrees(np.arccos(np.clip(dy / np.maximum(r, 1e-6), -1, 1)))
        ph = np.degrees(np.arctan2(dx, dz)) + 180.0
        return ndimage.map_coordinates(self.table, [th, ph], order=1, mode="nearest")

    def field(self, X, Y, Z):
        dx, dy, dz = np.broadcast_arrays(X - self.C[0], Y - self.C[1], Z - self.C[2])
        r = np.sqrt(dx * dx + dy * dy + dz * dz)
        return (r - self.radius(dx, dy, dz, r)).astype(np.float32), (dy / np.maximum(r, 1e-6)).astype(np.float32)

    def on(self, p, depth=0.0):
        p = np.atleast_2d(np.asarray(p, float)); d = p - self.C
        u = d / np.linalg.norm(d, axis=1, keepdims=True)
        return self.C + u * (self.radius_dir(u) - depth)[:, None]


UNDER = [(0, -26, -40), (0, -22, -5), (0, -17, 8), (0, -8, 28), (0, 2, 48), (0, 14, 70)]        # the midline under the braincase and through the face
UNDER_SIDE = [(45, -12, -52), (50, -16, -28), (32, -27, -34), (40, -14, -2), (26, -20, -2), (22, -10, 24), (40, -5, 30),
              (44, -3, 12), (20, -1, 48), (30, 6, -72)]


# the braincase seen from above narrows toward the forehead; no plate here shows that outline, so the usual breadths hold it:
# least frontal breadth 96 (frontotemporale), across the pterions 108, behind the orbits 94 to 96
PLAN = [(48, 47, 71), (53, 62, 55), (54, 40, 40), (48, 14, 50), (47, 28, 60)]


VIEWS = {"side": (2, 1), "front": (0, 1), "below": (0, 2)}        # the two head-frame axes each view shows


def outline_radius(q, c2, angs, half):
    """The outermost reach of a traced outline q (2D, mm) about the point c2, per direction: one radius per angle (nan where none)."""
    a = np.degrees(np.arctan2(q[:, 1] - c2[1], q[:, 0] - c2[0])); r = np.hypot(q[:, 0] - c2[0], q[:, 1] - c2[1])
    out = np.full(len(angs), np.nan)
    for i, ang in enumerate(angs):
        m = np.abs(((a - ang + 180) % 360) - 180) < half
        if m.any():
            out[i] = r[m].max()
    return out


def fit_silhouettes(T, E, pins, rounds=8, log=print):
    """The braincase drawn so that its outline in each of the three views is the plate's traced outline.
    Each round: find, for every direction of each view, the point of the surface that makes the outline there,
    and ask the surface to move in or out by what it misses the traced outline; the pins (points under the
    braincase, which no outline shows) hold the rest."""
    fr_k = plates.BREADTH / (2 * T.vault_side_from_front()[0][:, 0].max() / T.vault_side_from_front()[1])
    bl_k = T.vault_side_from_below()[1]
    px = T.front_px; front = T.front[px[:, 0] < plates.FRONT_MID - 150] * np.array([fr_k, 1.0])
    px = T.base_px; base = T.base[px[:, 0] < plates.BASE_MID - 300] * np.array([bl_k, 1.0])
    views = [   # name, traced outline (2D in the view's axes), angles fitted (degrees about the centre's projection)
        ("side", T.side, np.arange(-12, 181, 5).tolist() + np.arange(-180, -127, 5).tolist()),
        ("front", front, np.arange(-28, 91, 5).tolist()),           # x to the right, y up: from above the ear to the crown
        ("below", base, np.arange(-90, 1, 5).tolist()),             # x to the right, z up: from the back round to behind the arch
    ]
    pins = np.asarray(pins, float); pd = pins - C; pr = np.linalg.norm(pd, axis=1); pd = pd / pr[:, None]
    V = Star(C, E)
    for it in range(rounds):
        dd, r = V.points(2); P = C + dd * r[:, None]
        us, miss, worst = [pd], [pr - V.radius_dir(pd)], 0.0
        for name, q, angs in views:
            i, j = VIEWS[name]; c2 = np.array([C[i], C[j]])
            sel = np.ones(len(P), bool) if name == "side" else P[:, 0] >= -1e-6
            a = np.degrees(np.arctan2(P[:, j] - c2[1], P[:, i] - c2[0])); rho = np.hypot(P[:, i] - c2[0], P[:, j] - c2[1])
            want = outline_radius(q, c2, np.array(angs, float), 2.5)
            ok = np.isfinite(want)
            if ok.sum() > 5:      # a traced line carries small blips (lettering touching it): take them off
                w2 = want.copy(); w2[ok] = ndimage.gaussian_filter1d(ndimage.median_filter(want[ok], 3, mode='nearest'), 0.8, mode='nearest'); want = w2
            for ang, w in zip(angs, want):
                m = sel & (np.abs(((a - ang + 180) % 360) - 180) < 2.5)
                if not np.isfinite(w) or not m.any():
                    continue
                k = np.where(m)[0][np.argmax(rho[m])]
                worst = max(worst, abs(rho[k] - w))
                us.append(dd[k:k + 1] * np.array([np.sign(dd[k, 0]) or 1.0, 1, 1])); miss.append(np.array([r[k] * (w / rho[k] - 1.0)]))
        log("  round %d: outlines off by at most %.2f mm" % (it, worst))
        V.move(np.concatenate(us), np.concatenate(miss))
    return V


def braincase(T, log=print):
    prof = T.profile(step=6.0)
    mid = [(0.0, y, z) for z, y in prof]
    fr, kf = T.vault_side_from_front(step=9.0)
    zf = np.interp(fr[:, 1], [10, 30, 60, 100, 113], [4.0, -6.0, -20.0, -10.0, -3.0])
    bl, kb = T.vault_side_from_below(step=9.0)
    yb = np.interp(bl[:, 1], [-80, -60, -20, 2], [40.0, 48.0, 54.0, 40.0])
    side = [(x, y, z) for (x, y), z in zip(fr, zf)] + [(x, y, z) for (x, z), y in zip(bl, yb)]
    upper = np.array(mid + side, float)
    E = Egg(); rms = E.fit(C, upper[upper[:, 1] > 5.0])
    log("egg fitted to %d traced points: rms miss %.2f mm; %s" % (len(upper), rms, " ".join("%s %.1f" % kv for kv in zip(E.names, E.p))))
    V = fit_silhouettes(T, E, list(UNDER) + list(UNDER_SIDE) + list(PLAN), log=log)
    return V


# =================================== the face: a relief over the front view ===================================
ORBIT_BOX = ((11.5, 49.5), (-1.0, 31.3))        # the orbit's opening: breadth as usual, heights from the side view
APERTURE_HALF = 12.4                            # half the nasal opening's breadth (24.8 mm)
ARCH = [(0.0, 98.1), (5.0, 97.4), (9.5, 95.6), (14.0, 92.0), (17.5, 88.0), (21.0, 81.5), (23.8, 74.0), (27.0, 64.5),
        (29.5, 54.5), (30.8, 46.0)]             # the upper teeth's outer faces at the gum, seen from below: (x, z)


# the line the upper teeth stand on: the traced outer faces at the gum brought in by half a tooth's thickness, and run on
# behind the trace for the third molar; the bone's margin at each tooth is the front view's lower edge
UPPER_LINE = [(0, 95.1), (4.5, 94.4), (8.1, 92.7), (11.5, 89.4), (14.2, 85.7), (17.1, 79.7), (19.4, 72.5), (22.0, 63.0),
              (24.3, 53.4), (25.5, 45.4), (26.0, 40.0)]
UPPER_T = dict(L.UPPER, **{"crest y": [-44.7, -43.9, -43.0, -42.4, -42.0, -41.6, -41.2, -41.0]})


def tooth_ridge(line, table, upper, rise=8.0, beyond=2.0):
    """The tooth-bearing process as a ridge swept along the teeth's line, wide enough to wall every socket."""
    A = arch(line, 1.0)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(A, axis=0), axis=1))])
    w = np.array(table["width"]); mid = np.cumsum(w) - w / 2
    keep = d <= w.sum() + beyond               # (a tube's end is round: it reaches its own half-width past its last point)
    cy = np.interp(d, mid, table["crest y"])
    sgn = 1.0 if upper else -1.0
    P = np.column_stack([A[keep, 0], cy[keep] + sgn * rise, A[keep, 1]])[::3]
    half = [(0, 3.9), (0.2, 4.2), (0.35, 5.0), (0.55, 5.8), (0.75, 7.2), (1, 7.0)]
    return Tube(P, rise, half, up=(0, 1, 0), n=2.5), A


def orbit_margin():
    """The orbital margin as a closed 3D line (left side), from the front view's trace with depths from the side view."""
    q = np.array(plates.ORBIT_FRONT, float)
    xy = plates.front_mm(q[:, :2])
    (x0, x1), (y0, y1) = ORBIT_BOX
    x = x0 + (xy[:, 0] - xy[:, 0].min()) * (x1 - x0) / np.ptp(xy[:, 0])
    y = y0 + (xy[:, 1] - xy[:, 1].min()) * (y1 - y0) / np.ptp(xy[:, 1])
    P = np.column_stack([x, y, q[:, 2]])
    return sdf.spline(P, 1.5, closed=True)


def aperture_rim():
    """The rim of the nasal opening, left half, from the nasal bones' tip down to the spine: (x, y, z)."""
    q = np.array(plates.APERTURE_FRONT, float)
    xy = plates.front_mm(q[:, :2])
    x = xy[:, 0] * APERTURE_HALF / xy[:, 0].max()
    y = np.interp(xy[:, 1], [xy[:, 1].min(), xy[:, 1].max()], [plates.NASAL_FLOOR_Y - 1.0, 9.0])
    return sdf.spline(np.column_stack([x, y, q[:, 2]]), 1.5)


FACE_EDGE = [   # the outline of the facial skeleton seen from the front, left half, from the midline over the brow and round: (x, y)
    (0, 57), (46.0, 57), (47.5, 52), (49.5, 44), (51.0, 37.6), (52.9, 30), (56.0, 24), (57.4, 19), (57.6, 6.6), (58.0, 1.5),
    (60.5, -3.0), (59.8, -7.6), (55.6, -12.8), (52.4, -17.0), (49.2, -19.5), (45.5, -20.6), (40.7, -21.1), (35.5, -23.0),
    (32.6, -26.5), (31.8, -32.0), (31.8, -39.0), (28.5, -40.5), (22.5, -41.6), (17.5, -42.6), (9.5, -44.2), (0, -45.1),
]
FACE_POINTS = [  # the front surface's depth z where no traced line gives it: (x, y, z)
    # frontal process of the maxilla and the side of the nasal bones
    (6.0, 16, 96.0), (7.0, 10, 100.5), (9.0, 19, 93.5), (10.5, 8, 95.0), (12.0, 2, 93.0),
    # beside the nasal opening and under the orbit
    (16.0, -8, 91.0), (17.0, -20, 90.0), (15.0, -27, 92.5), (19.0, -3, 87.5), (25.0, -5, 84.5),
    # infraorbital foramen, canine fossa
    (30.6, -9.8, 81.5), (26.0, -20, 81.5), (22.0, -15, 85.5), (31.0, -17, 77.0),
    # along the suture between cheek bone and maxilla; the cheek's prominence; its outer and lower edges
    (33.3, -5.6, 77.5), (40.7, -7.6, 75.0), (45.0, -10.3, 73.0), (47.0, -14.4, 71.0),
    (50.0, -6.0, 69.5), (53.0, 2.0, 68.5), (54.5, 12.0, 68.0), (54.0, 20.0, 69.5),
    (57.4, 15.0, 63.5), (57.6, 5.0, 62.5), (59.5, -4.0, 57.0), (55.6, -12.8, 62.0), (49.2, -19.5, 67.0),
    (40.7, -21.1, 70.5), (35.5, -23.0, 70.5),
    # the frontal bone's zygomatic process and the temporal crest above it: x from the outline seen from in front (FACE_EDGE,
    # a millimetre inside it), y and z from the crest traced on the side view (temporal.FRONTAL_CREST). Without them the
    # forehead turned back too soon: at the crest's line it stood 47 mm out where the outline from in front has 52, and the
    # pillar beside the orbit ended in a horn under that narrow place.
    (54.5, 25.3, 65.7), (52.6, 28.7, 72.3), (50.9, 34.1, 75.1), (49.6, 39.5, 75.1), (48.2, 45.0, 74.7), (47.2, 49.4, 74.0),
    # the tooth-bearing process: the swellings over the roots and the hollows between
    (4.5, -38, 97.6), (9.5, -38, 96.0), (13.8, -38, 92.8), (17.5, -36, 91.5), (17.5, -41, 89.5), (21.5, -38, 83.5),
    (24.3, -38, 76.0), (27.6, -37, 66.5), (30.0, -36, 57.0), (4.5, -43, 97.8), (9.5, -43, 95.8),
    (20.0, -30, 87.2), (25.0, -30, 79.2), (29.0, -30, 68.0),
]


def face(T, V, h, log=print):
    """The facial skeleton as one slab over the front view; returns (solid, the front surface map, the Map)."""
    M = Map(0.0, 72.0, -52.0, 58.0, 1.0)
    pts = []
    up, down = T.face_profile()
    up = up[(up[:, 1] > 9.0) & (up[:, 1] < 46)]
    for z, y in up[::3]:
        pts.append((0.0, y, z, 1.0))
    down = down[down[:, 1] < -21.4]
    for z, y in down[::3]:
        pts.append((0.0, float(plates.subnasal(y)), z, 1.0))
    om = orbit_margin()
    for x, y, z in om[::2]:
        pts.append((x, y, z, 1.0))
    ap = aperture_rim()
    for x, y, z in ap[::2]:
        pts.append((x, y, z, 1.0))
    for x, y, z in FACE_POINTS:
        pts.append((x, y, z, 1.0))
    # above the orbits the relief runs into the braincase: take the braincase's own surface there
    fe = np.array(FACE_EDGE[1:6], float)[::-1]                                             # the slab's edge beside the forehead, going up
    for x in np.arange(0, 61, 6.0):
        for y in (48.0, 56.0):
            if x > np.interp(y, fe[:, 1], fe[:, 0]) + 2.0:      # past the edge a line only grazes the braincase's side: that says nothing of the forehead, and pulled the crest 2 mm back
                continue
            zz = np.arange(40, 115, 0.5)
            d = V.field(np.full(len(zz), x), np.full(len(zz), y), zz)[0]
            k = np.where(d < 0)[0]
            if len(k):
                pts.append((x, y, zz[k[-1]], 0.6))
    pts = np.array(pts, float)
    Zf = M.thin_plate(pts, weight=40.0)
    from scipy import ndimage
    wf = np.clip((M.V - 33.0) / 8.0, 0, 1); wf = wf * wf * (3 - 2 * wf)                   # the forehead has no fine relief: the traced points' small disagreements are smoothed out of it
    Zf = Zf * (1 - wf) + ndimage.gaussian_filter(Zf, 3.0, mode="nearest") * wf
    miss = M.sample(Zf, pts[:, 0], pts[:, 1]) - pts[:, 2]
    log("face relief through %d points: off by rms %.2f, worst %.2f mm" % (len(pts), np.sqrt((miss ** 2).mean()), np.abs(miss).max()))
    reg = M.region(FACE_EDGE)
    # how far back the slab goes: a block between the cheek bones, a thick plate over the cheek and the orbit's outer rim
    # between the nasal cavity's walls it runs back to the sphenoid (z = 44); the upper jaw's own back (its tuberosity
    # behind the last molar, then the wall sloping forward up to the fissure under the orbit) is rounded
    ease = lambda t: np.clip(t, 0, 1) ** 2 * (3 - 2 * np.clip(t, 0, 1))
    jaw = np.interp(M.V, [-42, -30, -18, -8, 0, 12], [41.0, 40.5, 43.0, 48.0, 54.0, 58.0]) + 7.0 * ease((M.U - 24.0) / 9.0) ** 2
    mid = 44.0 + (jaw - 44.0) * ease((M.U - 13.0) / 6.0)
    t = np.interp(M.U, [33.0, 40.0, 60.0], [0.0, 1.0, 1.0])
    plate = np.interp(M.V, [-25, -10, 10, 30, 52], [13.0, 12.0, 9.5, 10.0, 16.0])
    # Above the orbit the slab's outer edge is the temporal crest, and the bone falls away into the fossa straight behind it:
    # there the slab is a lip 4 to 5 mm deep, not a plate 10 to 14 mm deep whose flat back stood in the fossa as a second step.
    plate = Zf - plate * (1.0 - 0.65 * ease((reg + 7.0) / 7.0) * ease((M.V - 27.0) / 6.0))
    inner = np.where(M.U < 33.0, mid, mid + (plate - mid) * t)
    inner = np.minimum(inner, Zf - 3.0)
    # toward the top of the forehead the relief sinks under the braincase, so the two meet without a step
    t = np.clip((M.V - 40.0) / 16.0, 0.0, 1.0)
    outer = Zf - 7.0 * t * t * (3 - 2 * t)
    # and likewise along its outer edge, where the forehead turns into the temple. Not from the orbit's roof up, as first done:
    # the outline from in front (FACE_EDGE: x 52.9 at y 30, 51.0 at 37.6, 49.5 at 44) is the frontal bone's zygomatic process
    # running up into the temporal crest, which stands out of the braincase until about 45 mm up. Sunk from 30 mm it left the
    # pillar beside the orbit ending in a horn at its top, 5 mm proud of the forehead's side.
    outer = outer - 5.0 * ease((reg + 5.0) / 5.0) * ease((M.V - 42.0) / 10.0)
    solid = Slab(M, (0, 1, 2), outer, np.minimum(inner, outer - 3.0), reg, round=2.2)
    return solid, Zf, M, om, ap, reg


# =================================== the cheek bone and its arch: a relief over the side view ===================================
ZYG_SIDE = [   # the cheek bone with the arch behind it, seen from the side, traced on Fig. 188: (z, y), closed
    # (its top: the hind border does not run straight up to a level top 30 mm above the Frankfurt plane, as first drawn. From
    # the frontozygomatic suture's hind end, page (750, 1745), it leans forward and up as the frontal bone's temporal crest,
    # page (730, 1700) and (675, 1655): the pillar beside the orbit narrows upward into the forehead's side)
    (72.9, 27.6), (71.4, 28.8), (68.0, 27.0), (64.7, 25.3), (62.4, 22.6), (59.7, 20.9), (57.5, 17.4), (56.1, 13.7), (55.6, 9.8), (55.4, 5.9), (54.6, 3.7),
    (52.0, 0.6), (49.0, -0.8), (46.4, -0.9), (40.1, 0.4), (34.8, 1.2), (28.4, 1.6), (22.0, 1.9), (15.5, 1.9), (9.2, 1.5),
    (3.0, 1.6), (3.1, -0.4), (5.3, -0.4), (9.0, -0.8), (11.8, -2.9), (13.9, -5.7), (16.8, -7.4), (19.5, -7.5), (22.4, -6.3),
    (25.0, -4.2), (27.5, -2.7), (31.7, -3.2), (35.8, -4.3), (39.3, -5.7), (39.9, -7.1), (44.6, -9.7), (49.2, -12.7),
    (53.9, -15.6), (58.8, -17.6), (63.9, -18.7), (68.3, -18.3), (70.5, -17.2), (71.9, -12.2), (72.5, -6.0), (71.3, 3.9),
    (69.5, 8.2), (68.9, 11.6), (69.2, 16.2), (70.7, 19.9), (72.0, 23.7)]
ARCH_OUT = [(2, 61.5), (10, 62.0), (15, 62.8), (20, 64.0), (25, 65.6), (30, 66.5), (35, 66.4), (40, 65.3), (45, 63.6),
            (50, 62.1), (55, 60.3), (60, 58.3)]      # the arch's outer face seen from below (Fig. 187), at the usual breadth of 133: (z, x)


def cheek(M, Zf, reg, log=print):
    """The cheek bone's outer face and the arch as a slab over the side view: its outline is the traced one,
    its outer face is the arch's line seen from below, running into the face's own relief in front."""
    S = Map(-8.0, 78.0, -26.0, 36.0, 1.0)            # u = z, v = y
    pts = []
    for z, x in ARCH_OUT:
        if z <= 46:
            pts += [(z, 2.0, x - 0.3, 1.0), (z, -1.5, x, 1.0), (z, -6.0, x - 0.5, 1.0)]
    gx, gy = [a.ravel() for a in np.meshgrid(np.arange(44.0, 60.1, 2.0), np.arange(-20.0, 30.1, 3.0))]
    gz = M.sample(Zf, gx, gy)
    ok = (M.sample(reg, gx, gy) < -1.5) & (gz > 50.0) & (gz < 76.0)
    pts += [(z, y, x, 0.6) for x, y, z in zip(gx[ok], gy[ok], gz[ok])]
    # The frontal process: nothing held its outer face between the arch (z 46 and back) and the face's relief, and it bellied
    # out to x 62 at its hind border, 4 mm beyond the face's outline seen from in front (FACE_EDGE: 57.6 at y 6.6, 57.4 at 19,
    # 56.0 at 24, 52.9 at 30) and beyond the arch's own line seen from below. Its hind border is held on that outline.
    # At its top the process runs into the frontal bone's zygomatic process, which the face's slab draws on the same outline.
    pts += [(55.5, 8.0, 58.6, 1.0), (56.1, 13.7, 57.6, 1.0), (59.7, 20.9, 56.4, 1.0), (64.7, 25.3, 55.0, 1.0), (68.0, 27.0, 54.2, 1.0),
            (71.4, 28.8, 53.2, 1.0), (72.9, 27.6, 53.4, 1.0)]
    pts = np.array(pts, float)
    Xo = S.thin_plate(pts, weight=20.0)
    miss = S.sample(Xo, pts[:, 0], pts[:, 1]) - pts[:, 2]
    log("cheek relief through %d points: off by rms %.2f, worst %.2f mm" % (len(pts), np.sqrt((miss ** 2).mean()), np.abs(miss).max()))
    t = np.interp(S.U, [0, 6, 12, 22, 44, 50, 58, 66], [14.0, 12.0, 8.0, 4.4, 4.2, 5.0, 5.5, 9.0])      # (the frontal process is a plate 5 to 6 mm thick, not 8)
    return Slab(S, (2, 1, 0), Xo, Xo - t, S.region(ZYG_SIDE), round=1.6)


# =================================== sutures: lines traced on the side view, laid on the surface ===================================
def drape(F, zy):
    """The outermost point of the bone on each line through (z, y) that runs from side to side: (x, y, z); x = 0 where none."""
    zy = np.asarray(zy, float); xs = np.arange(float(F.ax[0][-1]) - 1.0, -0.01, -0.25)
    out = np.zeros((len(zy), 3))
    for k, (z, y) in enumerate(zy):
        d = sdf.sample_field(F.D, F.lo, F.h, np.column_stack([xs, np.full(len(xs), y), np.full(len(xs), z)]))
        i = np.where(d < 0)[0]
        x = 0.0
        if len(i) and i[0] > 0:
            a, b = d[i[0] - 1], d[i[0]]
            x = xs[i[0] - 1] + (xs[i[0]] - xs[i[0] - 1]) * a / (a - b)
        out[k] = (x, y, z)
    return out


def wander(P, amp, seed, snap=None, wave=plates.TOOTHED, depth=None):
    """A line on the braincase made to wander from side to side as a toothed suture does (mm), its ends kept.
    depth(P): how deep the teeth are at each point of the line (1 = amp). (The waves were once as short as 1.4 mm: on a line
    kept every half millimetre and a half-millimetre grid those came out as a row of pits, not as teeth.)"""
    P = spline(np.asarray(P, float), 0.5)
    if snap is not None:
        P = snap(P)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    t = np.gradient(P, axis=0); t /= np.linalg.norm(t, axis=1, keepdims=True)
    n = P - C; n /= np.linalg.norm(n, axis=1, keepdims=True)
    b = np.cross(t, n); b /= np.maximum(np.linalg.norm(b, axis=1, keepdims=True), 1e-9)
    r = np.random.default_rng(seed).uniform(0, 2 * np.pi, 4)
    if depth is None:
        w = sum(a * np.sin(2 * np.pi * s / q + f) for a, q, f in zip((1.0, 0.7, 0.6, 0.4), wave, r))
    else:
        w = 2.5 * surface.teeth(s, wave, r, np.random.default_rng(seed + 100).uniform(0, 2 * np.pi, 4)) * depth(P)
    fade = np.clip(np.minimum(s, s[-1] - s) / 3.0, 0, 1)
    Q = P + (amp * 0.5 * w * fade)[:, None] * b
    Q[:, 0] = np.maximum(Q[:, 0], 0.0)
    return Q, n


MASTOID = ((54.2, -12.6, -17.0), (7.4, 17.6, 12.4))          # the mastoid process: middle and half-lengths (x, y, z) of the solid it is made from


def sutures(F, T, V, log=print):
    """Cut the braincase's sutures as fine grooves; returns each one's line on the surface (mm), for splitting the bones later."""
    out = {}
    lines = {k: drape(F, spline(np.column_stack([T.F.mm(np.array(v, float)), np.zeros(len(v))]), 2.0)[:, :2]) for k, v in plates.SUTURES_SIDE.items()}
    b, l = T.mark["bregma"], T.mark["lambda"]
    a0, a1 = np.arctan2(b[1] - C[1], b[0] - C[2]), np.arctan2(l[1] - C[1], l[0] - C[2])
    ang = np.linspace(a0, a1 if a1 > a0 else a1 + 2 * np.pi, 40)
    lines["sagittal"] = V.on(np.column_stack([np.zeros(len(ang)), C[1] + 50 * np.sin(ang), C[2] + 50 * np.cos(ang)]))
    # The coronal and lambdoid sutures begin on the midline, at the sagittal's two ends (bregma and lambda). The vault is nearly
    # level from side to side there, so the lines draped from the side view began 12 and 18 mm out and the three never met.
    for name, end in (("coronal", 0), ("lambdoid", -1)):
        P = lines[name]
        lines[name] = np.vstack([lines["sagittal"][end], P[P[:, 0] > 0.0]])
    for seed, (name, P) in enumerate(sorted(lines.items())):
        P = P[(P[:, 0] > 0.0) | (name == "sagittal") | (np.arange(len(P)) == 0)]
        if name == "occipitomastoid":                      # it runs behind and inward of the mastoid process, never on to it
            P = P[(((P - np.array(MASTOID[0])) / (np.array(MASTOID[1]) + 2.5)) ** 2).sum(1) > 1.0]
        stop = None
        if name == "sphenofrontal":                        # its groove ends in the fossa, at the back of the cheek bone's frontal process: draped
            up_ = np.where(np.diff(P[:, 0]) > 2.0)[0]      # from the side its last points climb the process's hind edge, and the groove cut a pit in it.
            up_ = up_[up_ > len(P) // 2]                   # (The line itself is kept whole: the bones are parted along it, out to the process's edge.)
            if len(up_):
                stop = P[up_[0]]
        if len(P) < 3:
            continue
        toothed = name in ("coronal", "lambdoid")
        deep = None
        if name == "coronal":                              # long teeth above, a fine wavering line below (plates.CORONAL_FINE_BELOW)
            y0 = float(T.F.mm(np.array([plates.CORONAL_FINE_BELOW], float))[0][1])
            deep = lambda q: 0.3 + 0.7 * np.clip((q[:, 1] - y0 + 4.0) / 8.0, 0, 1)
        elif name == "lambdoid":
            deep = lambda q: np.ones(len(q))
        Q, n = wander(P, 0.0 if name == "sagittal" else plates.SUTURE_WAVE[name], seed,
                      snap=(lambda q: V.on(q, 0.0)) if toothed else None, depth=deep)
        if name == "sagittal":                             # on the midline: cut after the halves are joined, with a wander of its own (whole())
            build.midline.append((name, Q + 0.15 * n, plates.SAGITTAL["teeth"], 0.65))      # a narrower groove: its teeth stay apart
            out[name] = np.round(Q[::4], 2).tolist()
            continue
        k = len(Q) if stop is None else int(np.argmin(((Q - stop) ** 2).sum(1))) + 1
        lift = np.zeros(len(Q))
        if stop is not None:                               # It ends 3 mm short of the process's hind face and runs out to nothing over its last
            run = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(Q[:k], axis=0), axis=1))])      # 6 mm: carried to the foot of that steep face at
            k = int(np.searchsorted(run, run[-1] - 3.0)) + 1                                             # full depth, its end bit a round pit into it.
            t_ = np.clip((run[:k] - (run[k - 1] - 6.0)) / 6.0, 0, 1)
            lift[:k] = t_ * t_ * (3 - 2 * t_)
        F.cut(Tube((Q + (0.35 + lift)[:, None] * n)[:k], 0.85), 0.5)
        out[name] = np.round(Q[::2 if toothed else 4], 2).tolist()      # (the toothed ones kept every millimetre: the bones part along the teeth)
    log("sutures cut: " + ", ".join(sorted(out)))
    return out


# =================================== the whole cranium ===================================
def build(h=1.0, log=print, box=None):
    """The skull's left half as a field sampled every h mm. box = (lo, hi): build only that block of the head (for a
    finer grid on one region, e.g. the base at a quarter of a millimetre); x must start at 0."""
    T = Traces()
    V = braincase(T, log)
    build.midline = []
    F = Field(*(box if box is not None else ([0, -52, -96], [82, 121, 112])), h)
    X, Y, Z = F.coords(tuple(slice(0, n) for n in F.n))
    F0 = np.empty(F.n, np.float32); UY = np.empty(F.n, np.float32)
    for i in range(0, F.n[0], 16):
        F0[i:i + 16], UY[i:i + 16] = V.field(X[i:i + 16], Y, Z)
    F.D = F0.copy()
    up = (0, 1, 0)
    solid, Zf, M, om, ap, reg = face(T, V, h, log)
    F.add(solid, 4.0)
    F.add(cheek(M, Zf, reg, log), 2.5)
    # the outer wall of the orbit, running back and inward from the outer rim to the braincase
    wall = spline([(50, 16, 67), (44, 17, 59), (36, 18, 51), (27, 19, 43)], 2)
    F.add(Tube(wall, [(0, 17.0), (1, 10)], 2.6, up=up, n=3, true=True), 6)      # (its distance as it is: counted in its thin half-width it swelled the temple by a millimetre up to a ruled step 14 mm above it)
    temporal.fossa_front(F, F0, ZYG_SIDE[9:3:-1], log)     # the hollow behind the cheek bone's hind border (those six points of its outline) and the frontal bone's crest, as the plate draws it
    # The cheek bone's frontal process is a plate 5 to 6 mm thick with a hollowed back (its temporal surface), not a block.
    # The hollow lies between the plate and the orbit's outer wall and opens backward into the fossa: an oval laid along the
    # wall (which runs back and inward at 37 degrees), so that its inner bank is the wall's own face and runs on into the
    # fossa's floor with no sill between. (A round channel cut straight in read as a slot with a pointed top.)
    d_, n_ = np.array([0.6, 0.0, 0.8]), np.array([0.8, 0.0, -0.6])
    F.cut(Ellipsoid((48.8, 14.5, 58.5), (4.5, 8.0, 2.4), np.stack([d_, np.array([0.0, 1.0, 0.0]), n_], axis=1)), 2.5)
    # ---- temporal bone: the arch's root over the joint, the tubercle in front of it, the plate round the ear hole, the mastoid
    B = base.build(F, F0, log)
    F.add(Ellipsoid((54, 1.4, 9), (10.5, 4.4, 12)), 5)
    F.add(Ellipsoid((52, -3.8, 18.5), (11, 3.9, 5.2), rot((0, 1, 0), -12)), 3.5)
    F.add(Ellipsoid((46.5, -5.4, -1.2), (11.0, 7.4, 5.4), rot((0, 1, 0), -10)), 3)   # the ground the ear hole's canal runs in (its mouth, lip and wall: temporal.ear_hole)
    # the mastoid process: its outline traced on the side view (Fig. 188), full in the middle of its outer face, falling away to
    # the tip 33 mm below the Frankfurt plane; the notch for the digastric is cut on its inner side further down
    temporal.mastoid(F, log)
    # ---- occipital bone: condyles, outer protuberance, nuchal lines, the crest between them
    foramina.condyles(F, B, log)               # on the plate's own outline (the tubercle the pharynx hangs from is pressed in with the base's small relief)
    pro = V.on([(0, 2, -80)], 0.0)[0]; pro[0] = 0
    occiput.build(F, pro, log=log)             # the protuberance, the nuchal lines and the crest: the borders of the muscles' hollows, pressed into the surface
    # ---- sphenoid: the pterygoid process and its outer plate
    F.add(Ellipsoid((19, -10.5, 37.5), (8.5, 5.5, 5.5)), 4)
    # (the two plates, the wall joining them in front and the hook are thin sheets: pterygoid.py, added after the cuts)

    # ---- the tooth-bearing process of the upper jaw, along the teeth's own line
    ridge, A = tooth_ridge(UPPER_LINE, UPPER_T, True, beyond=-3.0)        # its round end stops 4 mm behind the last molar (Fig. 189), clear of the outer pterygoid plate
    F.add(ridge, 3.0)

    # =========================== the hollows ===========================
    # cranial cavity: the wall is thicker on the base than over the vault, and thickest behind the orbit's roof
    Tw = 6.0 + 7.0 * np.clip((0.05 - UY) / 0.6, 0, 1)
    o = unit(np.array([27.0, 30, 62]) - C)
    for i in range(0, F.n[0], 16):
        dx, dy, dz = np.broadcast_arrays(X[i:i + 16] - C[0], Y - C[1], Z - C[2])
        r = np.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
        cosang = (dx * o[0] + dy * o[1] + dz * o[2]) / r
        Tw[i:i + 16] += 24.0 * np.exp(-(np.arccos(np.clip(cosang, -1, 1)) / np.radians(21)) ** 2)
    F.D = np.maximum(F.D, -(F0 + Tw))
    del Tw
    base.floor_cut(F, B)
    # the orbit: a funnel from the traced margin to the optic canal
    orbit = Funnel(om, (13.5, 18.0, 37.0))
    F.cut(orbit, 1.6)
    sl, d = F.dist(orbit, 6.0)                       # the orbit keeps a wall of its own wherever it lies inside the braincase (its roof above all)
    if sl is not None:
        F.D[sl] = np.minimum(F.D[sl], np.maximum(np.maximum(-d - 0.2, d - 2.3), F0[sl] + 1.5))
    # the nasal opening: the traced rim pushed back; then the chamber behind it
    rim = np.concatenate([ap, [(0.0, ap[-1, 1] - 0.5, 0)], [(0.0, ap[0, 1] + 1.0, 0)]])
    F.cut(Prism(M, (0, 1, 2), M.region(rim[:, :2]), 112.0, 78.0, taper=-1.0), 1.8)      # (the rim is rounded as far as the grid needs: a knife edge comes out saw-toothed)
    F.cut(Tube(np.array([(0, -13.6, 92.0), (0, -10.5, 84), (0, -9.5, 66), (0, -14.5, 50), (0, -18.3, 41)]), [(0, 15.4), (0.25, 18.5), (0.6, 19.5), (0.85, 14.0), (1, 9.6)],
               [(0, 10.6), (0.25, 12.4), (0.7, 12.2), (1, 11.0)], up=up, n=2.3, taper=[(0, 0.42), (0.6, 0.42), (1, 0.0)]), 2.0)
    # the choanae (the nose's two hind openings): no frame is built for them. Each is what is left between the inner pterygoid plate
    # (pterygoid.py), the vomer's free hind border (nose.py), the sphenoid's body above and the palate's hind edge below; this clears
    # the way through, an arch about 12 mm wide and 24 high
    arch_ = spline(np.array([(1.1, -34.0, 0), (6.5, -34.0, 0), (12.7, -34.0, 0), (12.8, -28.0, 0), (12.8, -23.0, 0), (12.7, -17.0, 0), (12.0, -13.2, 0),
                             (10.2, -10.8, 0), (7.4, -9.8, 0), (4.8, -10.2, 0), (2.6, -11.8, 0), (1.4, -14.5, 0), (1.0, -19.0, 0), (1.0, -25.0, 0), (1.0, -30.0, 0)], float), 0.4, closed=True)[:, :2]
    Mc = Map(-2.0, 17.0, -37.0, -5.0, 0.25)
    F.cut(Prism(Mc, (0, 1, 2), Mc.region(arch_), 54.0, 29.0), 0.8)
    # the roof of the mouth: one height map read from the plate (palate.py): the vault, its thin free hind edge and spine, the
    # grooves, pits, sutures and openings; the floor of the nose above it
    build.palate = palate.build(F, UPPER_LINE, UPPER_T, log)
    # the tuberosity: the rounded end of the tooth-bearing process behind the last molar; the pyramidal process and the lower ends
    # of the pterygoid plates lean on it
    # (it ends 4 to 5 mm behind the last molar and the jaw's back rises from it nearly upright, as Fig. 189 has it: one rounded
    # swelling from the gum to under the orbit, not a ball hung behind the jaw)
    F.add(Ellipsoid((25.4, -34.6, 44.5), (6.1, 6.4, 4.8)), 3.5)
    F.add(Ellipsoid((26.2, -24.0, 45.6), (6.0, 13.0, 5.3)), 4.5)
    build.midline.append(("median palatine", build.palate["median"], 0.85, max(0.3, 0.7 * h)))
    # joint socket for the mandible, ear hole, groove behind the mastoid, foramen magnum
    base.socket_cut(F, B)                      # the socket's shape is the base relief's own; this clears the arch's root out of it
    temporal.ear_hole(F, log)                  # the ear hole as the plate draws it, with its lip, its wall and the small process in front of it
    # the notch for the digastric on the mastoid's inner side: from behind the stylomastoid foramen backward and outward, where the plate
    # rings the muscle (a slit open below, 4.5 mm wide, its roof at y -18); inward of it the shallow groove for the occipital artery
    F.cut(Tube(spline([(42.6, -23.0, -8.5), (45.0, -23.0, -15.5), (47.4, -23.0, -22.5), (50.6, -22.5, -29.5)], 1.5), 5.0, [(0, 1.7), (0.3, 2.3), (0.8, 2.3), (1, 1.6)], up=up), 1.6)
    F.cut(Tube(spline([(39.4, -23.4, -11.0), (41.4, -23.6, -19.0), (44.8, -23.0, -28.0)], 1.5), 1.3), 1.5)
    # the openings of the base, each with the outline the plate draws for it (foramina.py)
    foramina.press(F, B, foramina.cut(F, B, log), log)
    # small openings
    F.cut(Tube(np.array([(30.6, -9.8, 92.0), (29.5, -5.5, 74)]), 1.9), 0.8)          # infraorbital foramen
    # two more that the front view (Fig. 190) draws: the notch in the orbit's upper rim, 23.7 mm from the middle plane (page
    # 757, 1648), a groove across the rim's edge from the orbit's roof up on to the forehead; and the small hole on the cheek
    # bone's face, 51 mm out and 1 mm below the Frankfurt plane (page 505, 1983), running in toward the orbit
    F.cut(Ellipsoid((23.7, 30.2, 97.0), (2.6, 2.1, 3.6), rot((1, 0, 0), -30)), 1.2)   # supraorbital notch: a shallow rounded bite out of the rim's edge, 5 mm wide and under 2 deep
    F.cut(Tube(np.array([(51.6, -0.8, 72.5), (49.4, 2.0, 66.5)]), 0.85), 0.4)        # zygomaticofacial foramen
    F.cut(Tube(np.array([(15, 21, 44.0), (9.5, 22.5, 30)]), 2.4), 1.0)               # optic canal
    # the two fissures at the back of the orbit: slits, the upper one between the sphenoid's wings, the lower one in the floor
    F.cut(Tube(np.array([(21.3, 20.6, 47.5), (19.5, 20.0, 30.0)]), 5.6, 1.5, up=(0.55, 0.83, 0), taper=0.55), 0.6)
    F.cut(Tube(np.array([(19.5, 9.5, 44.5), (26.5, 6.3, 51.5), (32.5, 3.8, 57.5)]), 4.5, [(0, 1.3), (1, 1.9)], up=(0.35, -0.94, 0)), 0.6)
    sdf.ease_midline(F)                                     # the two halves meet level on the midline (no crease down the face)
    build.sockets = teeth.packed(UPPER_LINE, UPPER_T, True)           # each tooth in contact with the one before, none through another
    teeth.seat(F, build.sockets, True)

    # =========================== thin things added after the cuts ===========================
    # the septum (nose.py) is a bowed sheet: it goes in after the halves are joined (whole), with the other things that differ from side to side
    build.midsolids = [(nose.septum(h, log), 0.8)]
    # the pterygoid process's two plates, the wall that joins them in front, the hook (thin curved sheets, none of them a bar)
    build.pterygoid = pterygoid.build(F, log)
    # the anterior nasal spine: the floor's crest drawn out into a point in front of the opening's lower rim (a thin spike, taller than wide)
    # (a wedge: deep where it leaves the rim, thinning evenly to a point no finer than the grid can carry, so it does not end in a bead)
    # Seen from the side (Fig. 188) it is a three-cornered blade: its upper edge runs on level from the rim, its lower edge slopes up to the point.
    F.add(Tube(spline([(0, -31.6, 93.5), (0, -30.4, 97.0), (0, -29.2, 100.0), (0, -28.3, 102.2)], 0.5), [(0, 3.8), (0.4, 2.7), (0.8, 1.5), (1, 0.85)],
               [(0, 2.0), (0.4, 1.3), (0.8, 0.85), (1, 0.6)], up=up), 2.0, keep=3)
    # the conchae: thin scrolled sheets hung from the side wall that is really there (nose.py, after Gray's Fig. 196)
    nose.conchae(F, log)
    # the styloid process: from just in front of the stylomastoid foramen down, forward and a little inward, in its sheath (temporal.py)
    temporal.styloid(F, log)
    build.sutures = sutures(F, T, V, log)
    build.parts = dict(T=T, V=V, M=M, Zf=Zf, orbit=om, aperture=ap)
    return F, V


def whole(F, log=print, rough=True):
    """The whole head's field from the built left half: mirrored; then what must not be the same on both sides: the
    midline's sutures, each with a wander of its own, and the bone's grain and pits (surface.py). Returns (D, lo)."""
    D = sdf.mirror_field(F.D); lo = np.array([-float(F.ax[0][-1]), float(F.lo[1]), float(F.lo[2])])
    G = Field.__new__(Field); G.h = F.h; G.lo = lo; G.n = np.array(D.shape)
    G.ax = [(lo[k] + F.h * np.arange(D.shape[k])).astype(np.float32) for k in range(3)]; G.D = D
    for prim, k in getattr(build, "midsolids", []):          # what stands on the midline and is not the same on both sides
        G.add(prim, k, keep=3)
    rng = np.random.default_rng(194)
    whole.midlines = {}                                       # each midline suture as it was really cut (bones.py splits the paired bones along them)
    for name, P, amp, r in getattr(build, "midline", []):
        if len(P) > 2:
            sg = plates.SAGITTAL if name == "sagittal" else None       # deep teeth in its front two-thirds, shallow behind
            Q = surface.wander_line(P, amp, rng, **(dict(wave=sg["wave"], drift=sg["drift"], depth=lambda u: sg["hind"] + (1 - sg["hind"]) *
                                                         (1 - np.clip((u - 0.6) / 0.14, 0, 1))) if sg else {}))
            whole.midlines[name] = Q
            G.cut(Tube(Q, r), 0.4)
    temporal.relief(G, log)                                   # the temporal bone's small relief, each side with its own unevenness
    if rough:
        D0 = G.D.copy()
        G.D = surface.roughen(G.D, lo, F.h, log=log)
        for s in getattr(build, "sockets", []):               # round the teeth the bone may not grow: every tooth keeps its clearance
            p = np.array(s["position_mm"], float); a = np.array(s["axis"], float)
            q = [p + 3.0 * a, p - a * (s["root_mm"] + 2.0)]
            sl = G.window(np.minimum(*q) - 7.0, np.maximum(*q) + 7.0)
            if sl is not None:
                G.D[sl] = np.clip(G.D[sl], D0[sl], D0[sl] + 0.12)   # nor is it worn away there by more than a hair: the walls between sockets are thin
    return G.D, lo
