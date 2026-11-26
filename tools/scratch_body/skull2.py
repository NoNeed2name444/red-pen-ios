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
import teeth, base, occiput, foramina, palate, surface, nose, temporal, pterygoid, sinus, inner
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
ARCH = [(0.0, 93.9), (5.6, 94.0), (11.2, 93.6), (17.3, 90.5), (20.9, 87.1), (25.0, 81.8), (28.7, 74.7), (31.1, 65.8),
        (31.9, 56.7), (32.1, 48.7), (32.3, 44.7)]   # the upper teeth's outer faces at the gum, seen from below: (x, z): UPPER_LINE and half each tooth's thickness


# the line the upper teeth stand on, from the upper arch seen from below (Gray 1918, Fig. 996; Fig. 160 is the same drawing):
# a broad U, round in front (the six front teeth on a circle of about 23 mm), the molar rows nearly parallel (8 degrees off
# the midline each side). The old line, from an outline traced at the gum, stood 27 mm between the canines and 42 between the
# first molars, its front pointed (a 15 mm circle) and its rows splayed 13 degrees: the owner (25 November) drew the sockets
# out on a wider, rounder U. The points are placed so that the teeth, packed in contact by their own shapes (teeth.packed),
# stand on the plate's socket centres: within 0.9 mm, the lateral incisor within 1.2 (the built front teeth in contact span
# 1.7 mm less from the midline to the third molar than the plate's centres, which were scaled by the table's widths).
# The bone's margin at each tooth is the front view's lower edge.
# 25 November, the rows refitted together (T-rows-refit): this line and mandible2.LOWER_LINE were fitted at once, through the
# real packing, so that the CROWN centres (not the sockets) lie on the crown targets read from Fig. 996 / 997 (each within
# 1.4 mm, mean under 0.9), with the bite closed: overjet 2.6, overbite 3.1, every upper outer face beyond the lower one, the
# upper first molar's mesiobuccal cusp within 1.0 mm of the lower first molar's buccal groove. The upper incisors gave up
# 1.3 mm of their place forward and the lower ones about 1.2 of theirs back, to share the bite. The drawn points of the
# upper jaw (ARCH, the process's FACE_POINTS and lower edge, the tuberosity, the palate's front) were carried with the row.
UPPER_LINE = [(0, 90.8), (11.6, 90.7), (15.7, 86.9), (19.5, 82.5), (22.7, 77.3), (25.0, 71.4), (25.9, 64.9), (26.6, 58.0),
              (27.1, 51.1), (27.4, 44.2)]
UPPER_T = dict(L.UPPER, **{"crest y": [-44.7, -43.9, -43.0, -42.4, -42.0, -41.6, -41.2, -41.0]})


def tooth_ridge(line, table, upper, rise=8.0, beyond=2.0):
    """The tooth-bearing process as a ridge swept along the teeth's line, wide enough to wall every socket."""
    A = arch(line, 1.0)
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(A, axis=0), axis=1))])
    w = np.array(table["width"]); mid = np.cumsum(w) - w / 2
    keep = d <= w.sum() + beyond               # (a tube's end is round: it reaches its own half-width past its last point)
    cy = np.interp(d, mid, table["crest y"])
    sgn = 1.0 if upper else -1.0
    # On the wider arch the premolars' and molars' roots, splayed toward the cheek, stand 2 to 3 mm further out than the face's
    # relief: the ridge is laid 1.5 mm out from the teeth's line behind the canine (run in over the canine, none in front), so
    # the bone over them is what it was. (Moving the face's own points out with them bent its relief, a smooth surface through
    # all of its points, as far as the cheek bone's lower edge.) Its points are now taken every millimetre: out in the open its
    # joints every 3 mm stood on the jaw's side as a row of even ribs.
    t = np.gradient(A, axis=0); t /= np.linalg.norm(t, axis=1, keepdims=True)
    n = np.column_stack([-t[:, 1], t[:, 0]]); n *= np.where(n[:, :1] < 0, -1.0, 1.0)
    out = np.interp(d, [0.0, 14.0, 26.0, 1e3], [0.0, 0.0, 1.5, 1.5]) if upper else 0.0 * d
    Q = A + out[:, None] * n
    P = np.column_stack([Q[keep, 0], cy[keep] + sgn * rise, Q[keep, 1]])
    half = [(0, 3.9), (0.2, 4.2), (0.35, 5.0), (0.55, 6.0), (0.75, 7.5), (1, 7.3)]     # (the molars' part 0.2 to 0.3 mm fuller)
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
    (32.6, -26.5), (32.5, -32.0), (33.0, -39.0), (31.0, -40.5), (25.8, -41.6), (19.9, -42.6), (11.2, -44.2), (0, -45.1),
]   # (its lower edge, the tooth-bearing process, follows the wider arch: each point moved out with the tooth above it)
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
    (53.6, 26.8, 67.9), (51.9, 30.2, 70.7), (50.9, 34.0, 72.9), (49.9, 38.2, 74.3), (48.8, 42.5, 74.9), (48.0, 46.5, 74.6), (47.2, 49.4, 74.0),
    # the tooth-bearing process: the swellings over the roots and the hollows between. Over the canine and the first premolar each
    # point keeps its place against the tooth it lies over on the wider arch (UPPER_LINE); further back the ridge carries the
    # wider arch (tooth_ridge) and these stay as they were
    (4.5, -38, 94.8), (9.5, -38, 94.4), (14.9, -38, 93.7), (19.6, -36, 91.5), (19.1, -41, 90.3), (24.1, -38, 85.5),
    (26.2, -38, 75.6), (28.2, -37, 66.2), (30.4, -36, 56.7), (4.5, -43, 95.0), (9.5, -43, 94.2),
    (21.3, -30, 88.4), (26.7, -30, 78.8), (31.0, -30, 66.9),
]


def front_z(F, x, ys, z0=110.0, z1=70.0):
    """The front surface's depth z at (x, y) for each y in ys: the first bone met coming back from z0 (z1 where none is)."""
    from scipy.ndimage import map_coordinates
    ys = np.asarray(ys, float); zs = np.arange(z0, z1, -0.1)
    I = [np.full((len(ys), len(zs)), (x - F.lo[0]) / F.h), np.repeat(((ys - F.lo[1]) / F.h)[:, None], len(zs), 1),
         np.repeat(((zs - F.lo[2]) / F.h)[None, :], len(ys), 0)]
    d = map_coordinates(F.D, I, order=1, mode="nearest")
    hit = (d < 0).any(1); k = np.maximum(np.argmax(d < 0, axis=1), 1); j = np.arange(len(ys))
    a, b = d[j, k - 1], d[j, k]
    return np.where(hit, zs[k - 1] - 0.1 * np.clip(a / np.maximum(a - b, 1e-6), 0, 1), z1)


# the ridges over the upper front teeth's roots (juga): (x of the socket, how far it stands out, how high it runs, half-width, facing)
# and how far it leans toward the midline at its top (the roots converge a little upward; the canine's toward the opening's corner)
JUGA = [(4.8, 0.55, -36.0, 1.9, (0.0, 0.0, 1.0), 0.4), (11.4, 0.4, -36.5, 1.7, (0.25, 0.0, 0.97), 0.6), (15.6, 1.2, -30.8, 2.2, (0.35, 0.0, 0.94), 1.6),
        (20.4, 0.5, -35.5, 2.0, (0.6, 0.0, 0.8), 0.5)]
INCISIVE_FOSSA = (8.4, -34.2)


def juga(F, log=print):
    """The front of the tooth-bearing process below the nasal opening (Gray 1918, p. 158; Figs. 157, 190): "a series of
    eminences corresponding to the positions of the roots of the teeth. Just above those of the incisor teeth is a depression,
    the incisive fossa". Each ridge runs up from the bone's margin over its socket (UPPER_LINE: 4.8, 11.7, 15.5 and 20.2 mm
    out) and dies away upward; the canine's, over the longest root, stands out most and runs highest, toward the opening's
    lower outer corner. The fossa is a shallow hollow above the incisors' ridges, between the midline and the canine's.
    Laid on the surface as it stands after the tooth-bearing ridge: each a low swelling rounded into the face, not a rib."""
    made = []
    for x0, rise, top, w, n, lean in JUGA:
        ys = np.arange(-43.6, top + 0.01, 1.0)              # (from just above the margin: lower, its round end hung over the sockets as a thin lip)
        ys = ys[front_z(F, x0, ys) > 75.0]                  # (and only where there is bone: the margin stands higher behind the canine)
        if len(ys) < 3:                                     # (a block of the head, build's box, without the face there)
            continue
        ys = ys[ys >= ys[0] + 0.6] if ys[0] > -43.0 else ys
        n = np.asarray(n, float)
        t = (ys - ys[0]) / (ys[-1] - ys[0])
        xs = x0 - lean * t ** 1.5
        zf = np.array([front_z(F, xx, [yy])[0] for xx, yy in zip(xs, ys)])
        r = rise * np.clip(1.0 - t, 0.0, 1.0) ** 0.8                   # full at the margin, gone at the top
        a = 1.2 + 0.2 * w
        P = np.column_stack([xs, ys, zf]) - (a - r)[:, None] * n[None, :]
        F.add(Tube(P, [(0, a), (1, a)], [(0, w), (0.7, 0.85 * w), (1, 0.6 * w)], up=tuple(n)), 1.5)
        made.append("%.0f mm out %.1f proud up to y %.0f" % (x0, rise, top))
    xf, yf = INCISIVE_FOSSA
    zf = float(front_z(F, xf, [yf])[0])
    if zf > 70.0:
        F.cut(Ellipsoid((xf, yf, zf + 1.0), (3.0, 2.3, 1.8)), 1.2)
    log("juga: " + "; ".join(made) + "; incisive fossa at x %.1f y %.1f, about 0.7 mm deep" % (xf, yf))


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
        ys = float(plates.subnasal(y))
        # Below the nasal spine the side view's line stood 4 to 5 mm in front of the bone a few millimetres to either side (the
        # front points over the central incisors and the arch the teeth stand on): the midline came out as a raised strip 4 mm
        # wide with a hollow each side, which Figs. 157 and 190 do not have. There the midline is only a little forward of the
        # bone over the central incisors' roots, as the arch's curve gives it; the side view's line is kept from the spine up.
        t = np.clip((-32.0 - ys) / 3.5, 0.0, 1.0); t = t * t * (3 - 2 * t)
        z = z + (float(np.interp(ys, [-46.0, -43.0, -40.0, -37.0, -35.0, -33.5, -32.0], [95.9, 95.9, 95.8, 95.8, 96.2, 97.2, 97.9])) - z) * t
        pts.append((0.0, ys, z, 1.0))
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
PILLAR_HIND = [(55.2, 6.5), (55.9, 10.0), (57.1, 13.6), (58.8, 17.0), (61.1, 20.3), (63.9, 23.6), (66.9, 26.8), (69.7, 30.2)]     # the pillar's hind border below the crest: (z, y)
ZYG_SIDE = [   # the cheek bone with the arch behind it, seen from the side, traced on Fig. 188: (z, y), closed
    # (its top: the hind border does not run straight up to a level top 30 mm above the Frankfurt plane, as first drawn. From
    # the frontozygomatic suture's hind end, page (750, 1745), it leans forward and up as the frontal bone's temporal crest,
    # page (730, 1700) and (675, 1655): the pillar beside the orbit narrows upward into the forehead's side)
    # The hind border is one sweep, in Gray's words "curved like an italic letter f ... continuous above with the commencement
    # of the temporal line, and below with the upper border of the zygomatic arch" (1918, p. 166). The plate draws it so on a
    # skull tipped back by 12 degrees; traced point by point and levelled on the Frankfurt plane, the stretch through the
    # frontozygomatic suture came out at 27 degrees from the level between two corners: a step backward in the pillar (the
    # owner, 14 November: "fix those curves that i don't think should exist"). The same sweep is now drawn without corners,
    # nowhere flatter than 47 degrees and at most 2.7 mm from the plate's line (PILLAR_HIND, the arch upward).
    (72.9, 27.6), (71.9, 30.3)] + PILLAR_HIND[::-1] + [(54.6, 3.7), (52.0, 0.6), (49.0, -0.8)]
# The arch's two borders, read off Fig. 188 (porion origin, Frankfurt plane level, g-op 183.5) by the light-to-dark edge
# every millimetre. "The superior border is long, thin, and sharp ...; the inferior, short, thick, and arched" (1918, p. 139).
# The upper one sags gently from 1.6 mm above the Frankfurt plane over the root to 1 mm below it at the cheek bone; drawn
# as a straight run of 22 mm before. Both borders are the plate's own lines, smooth gentle arcs; a slow waver drawn into
# them read as a knobbly bar and is not in the plate. Their unevenness is fine-scale only, each side its own, in whole()
# (arch_relief). The lower one rises from the tubercle to its top 2.3 mm below the plane at z 29-31 and falls in
# one arch to the cheek bone's angle, turning down at z 40-42 where the plate draws a step under the suture (it ran down in
# a straight 10 mm chord from z 37 to the angle).
ARCH_TOP = [(46.4, -1.35), (44.6, -0.95), (42.4, -0.4), (40.1, 0.2), (37.6, 0.7), (35.0, 1.1), (32.2, 1.45), (29.2, 1.65),
            (26.0, 1.7), (22.6, 1.4), (19.0, 1.3), (15.5, 1.6), (12.0, 1.5), (9.2, 1.5), (3.0, 1.6)]
ARCH_LOW = [(3.0, 1.6), (3.1, -0.4), (5.3, -0.4), (9.0, -0.8), (11.8, -2.9), (13.9, -5.7), (16.8, -7.4), (19.5, -7.6),
            (21.4, -7.6), (22.0, -7.2), (22.7, -5.8), (23.5, -4.5), (24.6, -3.95), (25.8, -2.85), (27.3, -2.4), (29.1, -2.12), (31.1, -2.12), (33.1, -2.4), (35.1, -2.95),
            (37.0, -3.5), (38.8, -4.2), (40.0, -4.9), (40.9, -6.0), (41.7, -7.3), (42.8, -8.3), (44.3, -9.2), (46.0, -10.2),
            (47.8, -11.3), (49.2, -12.6)]


ZYG_SIDE = ZYG_SIDE + ARCH_TOP + ARCH_LOW[1:] + [
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
    pts += [(55.3, 7.0, 58.6, 1.0), (57.1, 13.6, 57.6, 1.0), (61.1, 20.3, 56.3, 1.0), (63.9, 23.6, 55.2, 1.0), (66.9, 26.8, 53.6, 1.0),
            (69.7, 30.2, 51.8, 1.0), (72.9, 27.6, 52.4, 1.0)]
    pts = np.array(pts, float)
    Xo = S.thin_plate(pts, weight=20.0)
    miss = S.sample(Xo, pts[:, 0], pts[:, 1]) - pts[:, 2]
    log("cheek relief through %d points: off by rms %.2f, worst %.2f mm" % (len(pts), np.sqrt((miss ** 2).mean()), np.abs(miss).max()))
    t = np.interp(S.U, [0, 6, 12, 22, 44, 50, 58, 66], [14.0, 12.0, 8.0, 4.4, 4.2, 5.0, 5.5, 9.0])      # (the frontal process is a plate 5 to 6 mm thick, not 8)
    # The bar is thin from side to side and thinnest at its upper border, where the temporal fascia holds: the inner face
    # leans out toward the top, to under half the bar's thickness at the border (it was a rounded box, 4 mm across top and bottom)
    top = np.array(ARCH_TOP, float)[::-1]
    depth = np.interp(S.U, top[:, 0], top[:, 1]) - S.V                       # mm below the upper border
    ss = lambda q: np.clip(q, 0, 1) ** 2 * (3 - 2 * np.clip(q, 0, 1))
    on = ss((S.U - 13.0) / 5.0) * ss((47.0 - S.U) / 4.0)
    t = t * (1.0 - 0.55 * on * (1.0 - ss((depth - 0.4) / 3.4)))
    return Slab(S, (2, 1, 0), Xo, Xo - t, S.region(ZYG_SIDE), round=1.6)


CONDYLE_TOPS = [(51.0, -1.5, 9.0), (54.5, -1.5, 9.5)]     # the jaw's heads (left; the right one's mirror image) as seated by mandible4


class Kept:
    """Solid b, except near the given points, where solid a is kept unchanged (inside r0 mm; blended out to r1), and
    behind z0 and in front of z1 (blended over 3 mm)."""
    def __init__(self, a, b, keep, r0, r1, z0=-1e9, z1=1e9):
        self.a, self.b, self.keep, self.r0, self.r1, self.z0, self.z1 = a, b, np.asarray(keep, float), r0, r1, z0, z1
        self.bounds = (np.minimum(a.bounds[0], b.bounds[0]), np.maximum(a.bounds[1], b.bounds[1]))

    def __call__(self, X, Y, Z):
        d = np.min([np.sqrt((np.abs(X) - p[0]) ** 2 + (Y - p[1]) ** 2 + (Z - p[2]) ** 2) for p in self.keep], axis=0)
        w = np.clip((d - self.r0) / (self.r1 - self.r0), 0, 1) * np.clip((Z - self.z0) / 3.0, 0, 1) * np.clip((self.z1 - Z) / 3.0, 0, 1); w = w * w * (3 - 2 * w)
        return (self.a(X, Y, Z) * (1 - w) + self.b(X, Y, Z) * w).astype(np.float32)


def arch_root(F):
    """The arch's two roots over the joint. The posterior root's top stood 5.5 mm above the Frankfurt plane on its outer
    edge, with the squama, so that from the side the arch had no upper border behind z 20 (the plate draws it at 1.3 to 1.5
    mm, running back over the ear hole as the temporal line). Its outer half is lowered by 2.4 mm and narrowed; round the
    jaw's heads, within 8.4 mm of their tops, the old root is kept as it was (the joint and its clearance do not move)."""
    old = Ellipsoid((54, 1.4, 9), (10.5, 4.4, 12))
    new = Ellipsoid((53.6, -0.5, 9), (10.6, 2.5, 12))
    F.add(Kept(old, new, CONDYLE_TOPS, 8.4, 10.0, z0=1.0, z1=21.0), 5)      # (behind the joint, over the ear hole, it stays as it was; and in front, where it
    # blends with the arch: lowered there it let the arch's outer face out by 0.4 mm at z 20, beyond Fig. 187)
    F.add(Ellipsoid((52, -3.8, 18.5), (11, 3.9, 5.2), rot((0, 1, 0), -12)), 3.5)      # the anterior root and the tubercle


ARCH_SEEDS = ((1, 1717), (-1, 1727))                        # each side's own unevenness
ARCH_FINE = {"face": 0.08, "top": 0.05, "low": 0.10}       # std (mm) of the fine unevenness; its peaks stay near 3 times that


def arch_relief(G, log=print, sign=1.0):
    """Each side's arch its own fine unevenness (whole head, after the mirror): the upper border a few hundredths of a
    millimetre at a scale of 1 to 2 mm; the lower border and the bar's under face, from the tubercle to the cheek bone's
    angle, the masseter's fine irregular serration, 1 to 3 mm apart and under 0.3 mm high (Fig. 187: the origin's serrated
    line). No slow waves: the borders stay the plate's smooth arcs. Nothing within 10 mm of the jaw's heads, and nothing
    in front of z 52 (the cheek's prominence and the orbit's rim)."""
    lo3 = np.array([55.0, -17.0, 0.0]); hi3 = np.array([72.0, 9.0, 54.0])
    low = np.array(ARCH_LOW[8:], float)
    for side, seed in ARCH_SEEDS:
        a, b = lo3.copy(), hi3.copy()
        if side < 0:
            a[0], b[0] = -hi3[0], -lo3[0]
        sl = G.window(a, b)
        if sl is None:
            continue
        X, Y, Z = np.broadcast_arrays(*G.coords(sl))
        D = G.D[sl].astype(np.float32)
        rng = np.random.default_rng(seed)
        def grain(mm):
            n = ndimage.gaussian_filter(rng.standard_normal(D.shape), mm / G.h, mode="nearest")
            return (n / (n.std() + 1e-9)).astype(np.float32)
        ax = np.abs(X)
        ss = lambda q: np.clip(q, 0, 1) ** 2 * (3 - 2 * np.clip(q, 0, 1))
        dc = np.min([np.sqrt((ax - p[0]) ** 2 + (Y - p[1]) ** 2 + (Z - p[2]) ** 2) for p in CONDYLE_TOPS], axis=0)
        m = ss((ax - 57.0) / 2.5) * ss((dc - 10.0) / 2.5) * ss((52.0 - Z) / 5.0) * ss((Z - 2.0) / 4.0) * ss((Y + 15.0) / 2.0) * ss((7.5 - Y) / 2.0)
        h = ARCH_FINE["face"] * (0.7 * grain(2.0) + grain(1.0))                 # the outer face: low and fine, under 0.3 mm
        lb = np.interp(Z, low[:, 0], low[:, 1])                                  # the lower border's height at this z
        top = np.array(ARCH_TOP, float)[::-1]
        near_top = ss((Y - np.interp(Z, top[:, 0], top[:, 1]) + 1.8) / 1.2) * ss((Z - 15.0) / 3.0)
        h = h + near_top * ARCH_FINE["top"] * grain(0.6)
        mas = ss((lb + 2.2 - Y) / 1.6) * ss((Z - 25.0) / 3.0)                    # the masseter's origin: the lower border and the under face
        h = h + mas * ARCH_FINE["low"] * (0.6 + grain(0.5))
        # behind z 26 the outer face of the root and the tubercle is not let out by more than 0.1 mm: seen from below the arch
        # is already as broad there as Fig. 187 draws it, or broader
        gx = side * np.gradient(D, G.h, axis=0)
        h = h + 0.06 * ss((gx - 0.3) / 0.4) * ss((Z - 27.0) / 2.0) * ss((41.0 - Z) / 2.0)   # the bar's outer face at its broadest let out a little
        h = np.where((gx > 0.5) & (Z < 26.0), np.minimum(h, 0.1), h)
        band = 1.0 - ss((np.abs(D) - 1.5) / 1.5)
        G.D[sl] = D - sign * h * m * band
    log("zygomatic arches: each side's own unevenness and the masseter's roughness pressed in")


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


def normals(F, P, smooth=4.0):
    """The bone's outward normal at points P (mm) of the half field F (x mirrored for the right side), smoothed along the line."""
    P = np.asarray(P, float); A = P.copy(); sx = np.where(A[:, 0] < 0, -1.0, 1.0); A[:, 0] = np.abs(A[:, 0])
    e = 0.5 * F.h
    fld = lambda q: sdf.sample_field(F.D, F.lo, F.h, np.column_stack([np.abs(q[:, 0]), q[:, 1:]]))
    g = np.column_stack([fld(A + d) - fld(A - d) for d in np.eye(3) * e])
    g[:, 0] *= sx
    g = ndimage.gaussian_filter1d(g, smooth, axis=0, mode="nearest")
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def onto(F, P, reach=2.5):
    """Each point moved along the bone's normal on to the nearest outer surface of the half field F (either side of the head)."""
    P = np.asarray(P, float); g = normals(F, P)
    t = np.arange(-reach, reach + 1e-9, 0.05)
    S = P[:, None, :] + t[None, :, None] * g[:, None, :]
    S[..., 0] = np.abs(S[..., 0])
    d = sdf.sample_field(F.D, F.lo, F.h, S.reshape(-1, 3)).reshape(len(P), len(t))
    out = P.copy()
    for k in range(len(P)):
        i = np.where((d[k, :-1] < 0) & (d[k, 1:] >= 0))[0]           # inside to outside, going outward
        if len(i):
            j = i[np.argmin(np.abs(t[i]))]
            a, b = d[k, j], d[k, j + 1]
            out[k] = P[k] + (t[j] + (t[j + 1] - t[j]) * a / (a - b)) * g[k]
    return out, g


def arclen(P):
    return np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])


def with_end(P, step):
    """P resampled every `step` mm, its last point kept."""
    Q = resample(P, step)
    if np.linalg.norm(Q[-1] - P[-1]) < 0.3 * step:
        Q = Q[:-1]
    return np.vstack([Q, P[-1:]])


def smooth_line(P, sigma, step=0.5):
    """A line resampled every `step` mm and smoothed over `sigma` mm, its two ends kept where they are."""
    P = with_end(np.asarray(P, float), step)
    s = arclen(P); lin = P[0] + (P[-1] - P[0]) * (s / s[-1])[:, None]
    R = P - lin; n = min(len(R) - 1, int(4 * sigma / step) + 1)
    pad = np.concatenate([-R[n:0:-1], R, -R[-2:-n - 2:-1]])       # odd about each end: the ends stay put and are not pulled in
    R = ndimage.gaussian_filter1d(pad, sigma / step, axis=0, mode="nearest")[n:n + len(P)]
    return lin + R


def envelope(spec, s):
    """A suture's tooth depth along it: spec [(mm from start, or from the end if negative), share]; s its arc lengths."""
    L = s[-1]
    x = np.array([L + a if (a < 0 or (a == 0 and k > 0 and spec[k - 1][0] < 0)) else a for k, (a, _) in enumerate(spec)], float)
    y = np.array([v for _, v in spec], float)
    o = np.argsort(x, kind="stable")
    e = np.interp(s, x[o], y[o])
    return e


def denticulate(length, depth, rng, reach, w0, w1, gap=1.6):
    """A toothed suture's run beside its course, in the course's own frame: (u along it, v to the side), mm, from (0, 0) to
    (length, 0). The course is broken into tongues of bone of irregular breadth (w0 to w1 mm, drawn anew for each), each
    reaching out to one side by its own length (up to reach x depth(u)), leaning forward or back by its own amount, squared
    or rounded at its tip, sometimes broader at its tip than at its neck, now and then cleft; the next one the other
    bone's, on the other side, and a quarter of them mere stubs. No two parts of the line come closer than `gap` mm (a tongue that would is shortened
    and straightened). (The old line was a sum of sine waves: a zip, every tooth like the next.)"""
    ws = []
    while sum(ws) < length:
        w = w0 + (w1 - w0) * rng.beta(0.6, 1.5)
        ws.append(w * 1.5 if rng.random() < 0.22 else w)           # now and then a broad one
    ws = np.array(ws) * length / sum(ws)
    a = np.concatenate([[0], np.cumsum(ws)])
    n = len(ws)
    side = rng.choice([-1.0, 1.0]) * (-1.0) ** np.arange(n)          # each tongue the other bone's: the sides take turns
    small = rng.random(n) < 0.25                                     # but a quarter of them are short
    reachk = reach * np.where(small, rng.uniform(0.28, 0.45, n), rng.uniform(0.5, 1.0, n))
    lean = rng.uniform(-0.55, 0.55, n)
    sq = rng.uniform(0.4, 0.9, n)                         # small: square-ended; near 1: rounded
    bulb = rng.uniform(0.1, 0.7, n) * (rng.random(n) < 0.65)
    cleft = rng.uniform(0.25, 0.45, n) * ((rng.random(n) < 0.18) | (ws > 0.55 * (w0 + w1)))    # a broad tongue is lobed at its tip
    shrink = np.ones(n)

    def path():
        U, V, K = [np.zeros(1)], [np.zeros(1)], [np.full(1, -1)]
        for k in range(n):
            m = max(int(ws[k] / 0.08), 12)
            t = np.linspace(0, 1, m + 1)[1:]
            mid = 0.5 * (a[k] + a[k + 1])
            L = reachk[k] * shrink[k] * float(np.interp(mid, s_mid, dep))
            h = np.sin(np.pi * t) ** sq[k]
            h = h * (1 - cleft[k] * shrink[k] * np.exp(-((t - 0.5) / 0.11) ** 2))
            u = a[k] + ws[k] * (t + bulb[k] * shrink[k] * (t - 0.5) * h ** 4) + lean[k] * shrink[k] * L * h ** 2
            U.append(u); V.append(side[k] * L * h); K.append(np.full(len(t), k))
        return np.concatenate(U), np.concatenate(V), np.concatenate(K)

    s_mid, dep = depth
    from scipy.spatial import cKDTree
    for _ in range(12):
        u, v, kk = path()
        Q = np.column_stack([u, v]); s = arclen(Q)
        pairs = cKDTree(Q).query_pairs(gap, output_type="ndarray")
        bad = pairs[np.abs(s[pairs[:, 0]] - s[pairs[:, 1]]) > 2.2 * gap] if len(pairs) else pairs
        if not len(bad):
            break
        for k in np.unique(np.concatenate([kk[bad[:, 0]], kk[bad[:, 1]]])):
            if k >= 0:
                shrink[k] *= 0.8
    return np.column_stack([u, v]), dict(breadth=ws, reach=reachk * shrink, side=side)


def wander(P, F, rng, spec, step=0.25):
    """A suture's line on the bone about its course P (on the surface, mm): toothed after spec (plates.SUTURE_TEETH), or a
    smooth line straying a little to either side if spec is a number. Returns (line on the surface, its outward normals,
    its run beside the course as (u, v))."""
    P = with_end(P, 0.25)
    s = arclen(P); t = np.gradient(P, s, axis=0); t /= np.linalg.norm(t, axis=1, keepdims=True)
    n = normals(F, P)
    b = np.cross(t, n); b /= np.maximum(np.linalg.norm(b, axis=1, keepdims=True), 1e-9)
    if np.isscalar(spec):                                   # a smooth, uneven edge: noise smoothed over 1 to 2 mm, no wave length of its own
        u = np.arange(0, s[-1], step); u = np.append(u, s[-1])
        w = ndimage.gaussian_filter1d(rng.standard_normal(len(u) + 80), 1.3 / step, mode="wrap")[40:-40]
        w += 0.6 * ndimage.gaussian_filter1d(rng.standard_normal(len(u) + 80), 0.8 / step, mode="wrap")[40:-40]
        w = spec * w / w.std() * np.clip(np.minimum(u, u[-1] - u) / 1.5, 0, 1)
        uv = np.column_stack([u, w])
    else:
        reach, w0, w1, prof = spec
        sm = np.linspace(0, s[-1], 400)
        uv, _ = denticulate(s[-1], (sm, envelope(prof, sm)), rng, reach, w0, w1)
        uv = with_end(uv, step)
    u = np.clip(uv[:, 0], 0, s[-1])
    Pu = np.column_stack([np.interp(u, s, P[:, k]) for k in range(3)])
    bu = np.column_stack([np.interp(u, s, b[:, k]) for k in range(3)])
    Q, nq = onto(F, Pu + uv[:, 1:2] * bu)
    return Q, nq, uv


def side_likeness(uvl, uvr):
    """How alike two sides' teeth are, seen in a mirror: the correlation of the left's run beside its course with the right's
    (the right's sideways direction turns over in the mirror)."""
    g = np.linspace(0, min(uvl[-1, 0], uvr[-1, 0]), 2000)
    return float(np.corrcoef(np.interp(g, uvl[:, 0], uvl[:, 1]), -np.interp(g, uvr[:, 0], uvr[:, 1]))[0, 1])


MASTOID = ((54.2, -12.6, -17.0), (7.4, 17.6, 12.4))          # the mastoid process: middle and half-lengths (x, y, z) of the solid it is made from
GROOVE = (0.55, 0.08)        # a suture's groove: the radius of the tube cut along it and how far its axis stands out of the surface (mm)


def sutures(F, T, V, log=print):
    """Lay out the braincase's sutures on the surface, each side with teeth of its own, to be cut in the whole head after the
    halves are joined (whole(), through build.midline): left and right are not copies. Returns each one's line on the left
    side (mm), for splitting the bones later; build.suture_lines keeps both sides' lines and courses."""
    out, keep = {}, {}
    # the courses: each line the plate draws, laid on the bone from the side point by point every tenth of a millimetre and
    # smoothed over 2 mm in space. (It was laid every 2 mm and joined to bregma and lambda by straight chords: near the crown,
    # where the vault is level from side to side, one step down the plate is 30 mm across the head, and the coronal ran dead
    # straight over the top and turned down at a corner.)
    lines = {}
    for k, v in plates.SUTURES_SIDE.items():
        zy = spline(np.column_stack([T.F.mm(np.array(v, float)), np.zeros(len(v))]), 0.1)[:, :2]
        lines[k] = drape(F, zy)
    b, l = T.mark["bregma"], T.mark["lambda"]
    a0, a1 = np.arctan2(b[1] - C[1], b[0] - C[2]), np.arctan2(l[1] - C[1], l[0] - C[2])
    ang = np.linspace(a0, a1 if a1 > a0 else a1 + 2 * np.pi, 400)
    lines["sagittal"] = onto(F, V.on(np.column_stack([np.zeros(len(ang)), C[1] + 50 * np.sin(ang), C[2] + 50 * np.cos(ang)])))[0]
    # The coronal and lambdoid sutures begin on the midline, at the sagittal's two ends (bregma and lambda).
    for name, end in (("coronal", 0), ("lambdoid", -1)):
        P = lines[name]
        lines[name] = np.vstack([lines["sagittal"][end], P[P[:, 0] > 0.0]])
    stops = {}
    for name in sorted(lines):
        P = lines[name]
        P = P[(P[:, 0] > 0.0) | (name == "sagittal") | (np.arange(len(P)) == 0)]
        if name == "occipitomastoid":                      # it runs behind and inward of the mastoid process, never on to it
            P = P[(((P - np.array(MASTOID[0])) / (np.array(MASTOID[1]) + 2.5)) ** 2).sum(1) > 1.0]
        if name == "sphenofrontal":                        # its groove ends in the fossa, at the back of the cheek bone's frontal process: draped
            i0 = len(P) // 2 + int(np.argmin(P[len(P) // 2:, 0]))      # from the side its last points climb the process's hind edge (from where the line
            if P[-1, 0] - P[i0, 0] > 2.0:                  # comes nearest the middle plane), and the groove cut a pit in it. (The line itself is
                stops[name] = P[i0 + 1:]                   # kept whole: the bones are parted along it, out to the process's edge.)
                P = P[:i0 + 1]
        if len(P) < 3:
            continue
        lines[name] = onto(F, smooth_line(P, 2.0))[0]
    seeds = {k: 7 + 13 * i for i, k in enumerate(sorted(lines))}
    r, off = GROOVE
    for name in sorted(lines, key=lambda k: k != "sagittal"):          # the sagittal first: whole() gives it its stray from the same draws as before
        P = lines[name]
        if len(P) < 3:
            continue
        spec = plates.SUTURE_TEETH[name]
        if name == "coronal":                              # long teeth above, a fine wavering line below (plates.CORONAL_FINE_BELOW)
            y0 = float(T.F.mm(np.array([plates.CORONAL_FINE_BELOW], float))[0][1])
            s = arclen(P); s0 = float(np.interp(-y0, -P[:, 1], s))
            spec = spec[:3] + (list(spec[3]) + [(s0 - 4.0, 1.0), (s0 + 4.0, 0.55), (-1.5, 0.55), (0, 0.0)],)
        if name == "sagittal":                             # Gray: "deeply serrated in its anterior two-thirds"
            s = arclen(P); h = plates.SAGITTAL["hind"]
            spec = spec[:3] + (list(spec[3]) + [(0.6 * s[-1], 1.0), (0.72 * s[-1], h), (-3.0, h), (0, 0.0)],)
        keep[name] = dict(course=P)
        for side, sx in (("left", 1.0), ("right", -1.0)):
            Pc = P * np.array([sx, 1.0, 1.0])
            for j in range(20):                            # each side its own teeth: on a short line two draws can come out alike by chance,
                rng = np.random.default_rng(seeds[name] + (0 if side == "left" else 1000 + j))      # so the right takes the first draw
                Q, nq, uv = wander(Pc, F, rng, spec)                                                 # that is unlike the left (seen in a mirror)
                if side == "left" or name == "sagittal" or abs(side_likeness(keep[name]["left uv"], uv)) < 0.25:
                    break
            keep[name][side] = Q; keep[name][side + " uv"] = uv
            lift = np.zeros(len(Q)); kq = len(Q)
            if name in stops:                              # It ends 3 mm short of the process's hind face and runs out to nothing over its last
                run = arclen(Q)                                                                               # 6 mm: carried to the foot of that steep face at
                kq = int(np.searchsorted(run, run[-1] - 3.0)) + 1
                t_ = np.clip((run[:kq] - (run[kq - 1] - 6.0)) / 6.0, 0, 1)
                lift[:kq] = t_ * t_ * (3 - 2 * t_)
            cut = (Q + (off + lift)[:, None] * nq)[:kq]
            if name == "sagittal":                         # on the midline: one line for both sides, given its slow stray in whole()
                build.midline.append(("sagittal", cut, 0.0, r))
                break
            build.midline.append(("%s, %s" % (name, side), cut, 0.0, r))
        line = keep[name]["left"][::4]                     # every millimetre: the bones part along the teeth
        if name in stops:                                  # and the sphenofrontal on out to the process's edge
            line = np.vstack([line, stops[name][::10]])
        out[name] = np.round(line, 2).tolist()
    build.suture_lines = keep
    log("sutures laid out, each side with its own teeth, to be cut in the whole head: " + ", ".join(sorted(out)))
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
    temporal.fossa_front(F, F0, PILLAR_HIND, log)          # the hollow behind the pillar's hind border and the frontal bone's crest
    # The cheek bone's frontal process is a three-sided bar: its back, the temporal surface, "directed backward and medialward,
    # is concave" (Gray 1918, p. 164) and runs from the free hind border inward to the orbit's outer wall. It was hollowed by a narrow oval laid along that
    # wall, which undercut the plate by up to 6 mm and showed from behind as a slot with a rim, cut into the pillar. The
    # hollow is now a broad shallow one, 2 mm at its deepest, leaning with the hind border and running out at both ends.
    u1, u2 = np.array([0.0, 0.92, 0.39]), np.array([0.0, -0.39, 0.92])
    F.cut(Ellipsoid((49.9, 14.8, 54.3), (5.1, 12.0, 5.4), np.stack([np.array([1.0, 0.0, 0.0]), u1, u2], axis=1)), 4.0)      # (it stops 2 mm short of the free border: nearer, it frayed the border's edge)
    # ---- temporal bone: the arch's root over the joint, the tubercle in front of it, the plate round the ear hole, the mastoid
    B = base.build(F, F0, log)
    arch_root(F)
    F.add(Ellipsoid((46.5, -5.0, -4.4), (11.0, 7.2, 6.2), rot((0, 1, 0), -8)), 3)    # the ground the ear canal runs in (its mouth and the tympanic part round it: temporal.ear_hole)
    # the mastoid process: its outline traced on the side view (Fig. 188), full in the middle of its outer face, falling away to
    # the tip 33 mm below the Frankfurt plane; the notch for the digastric is cut on its inner side further down
    temporal.mastoid(F, log)
    # ---- occipital bone: condyles, outer protuberance, nuchal lines, the crest between them
    foramina.condyles(F, B, log)               # on the plate's own outline (the tubercle the pharynx hangs from is pressed in with the base's small relief)
    pro = V.on([(0, 2, -80)], 0.0)[0]; pro[0] = 0
    occiput.build(F, pro, log=log)             # the protuberance, the nuchal lines and the crest: the borders of the muscles' hollows, pressed into the surface
    # ---- sphenoid: the pterygoid process. Its two plates, the wall joining them in front (whose hind face, sloping back toward
    # the root, closes the top of the hollow between them), the hook and the vaginal processes are thin sheets: pterygoid.py,
    # added after the cuts. (An ellipsoid stood here, 17 by 11 by 11 mm, from when the process was one lump: it filled the top of
    # that hollow, but also stood inward of the inner plate over the choana as a flat-faced block, down to y -15.6.)

    # ---- the tooth-bearing process of the upper jaw, along the teeth's own line
    ridge, A = tooth_ridge(UPPER_LINE, UPPER_T, True, beyond=-3.0)        # its round end stops 4 mm behind the last molar (Fig. 189), clear of the outer pterygoid plate
    F.add(ridge, 3.0)
    juga(F, log)

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
    sinus.body(F, log)                         # the sphenoid's body under the saddle (sella turcica), dorsum and clivus: the cranial floor ran level there
    # the orbit: a funnel from the traced margin to the optic canal
    orbit = sinus.Orbit(Funnel(om, (13.5, 18.0, 37.0)))       # (less what lies inward of the ethmoid's orbital plate: the funnel alone left 8 mm of bone between the orbits)
    F.cut(orbit, 1.6)
    sl, d = F.dist(orbit, 6.0)                       # the orbit keeps a wall of its own wherever it lies inside the braincase (its roof above all)
    if sl is not None:
        F.D[sl] = np.minimum(F.D[sl], np.maximum(np.maximum(-d - 0.2, d - 2.3), F0[sl] + 1.5))
    # the nasal opening: the traced rim pushed back; then the chamber behind it
    rim = np.concatenate([ap, [(0.0, ap[-1, 1] - 0.5, 0)], [(0.0, ap[0, 1] + 1.0, 0)]])
    F.cut(Prism(M, (0, 1, 2), M.region(rim[:, :2]), 112.0, 78.0, taper=-1.0), 1.8)      # (the rim is rounded as far as the grid needs: a knife edge comes out saw-toothed)
    F.cut(Tube(np.array([(0, -13.6, 92.0), (0, -10.5, 84), (0, -9.5, 66), (0, -14.5, 50), (0, -18.3, 41)]), [(0, 15.4), (0.25, 18.5), (0.6, 19.5), (0.85, 14.0), (1, 9.6)],
               [(0, 10.6), (0.25, 12.4), (0.7, 12.2), (1, 11.0)], up=up, n=2.3, taper=[(0, 0.42), (0.6, 0.42), (1, 0.0)]), 2.0)
    sinus.cleft(F, log)                        # the nose's narrow upper part, up to the plate that roofs it
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
    # (on the wider arch the last molar stands 1 mm further out and 1.2 forward: the swelling's foot goes with it, its upper part half as far)
    F.add(Ellipsoid((27.7, -34.6, 45.0), (6.1, 6.4, 4.8)), 3.5)
    F.add(Ellipsoid((27.5, -24.0, 45.5), (6.0, 13.0, 5.3)), 4.5)
    build.midline.append(("median palatine", build.palate["median"], 0.85, max(0.3, 0.7 * h)))
    build.midline.append(("median palatine, hind", build.palate["median hind"], 0.85, max(0.3, 0.7 * h)))
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
    # infraorbital groove, canal and foramen. Gray (pages 159, 188): "Running forward near the middle of the floor is the
    # infraorbital groove, ending in front in the infraorbital canal"; the canal "opens just below the margin of the orbit".
    # The groove: a shallow gutter with soft edges from the middle of the lower fissure's front edge forward and inward along
    # the orbit's floor, 4 mm wide and under 1 deep behind, narrower and deeper in front, where it sinks under the floor 10 mm
    # behind the rim.
    F.cut(Tube(spline([(34.2, 1.9, 60.6), (33.4, 1.3, 63.0), (32.3, 0.4, 65.8), (31.4, -1.3, 68.4), (30.8, -2.1, 70.3), (30.6, -2.3, 71.0)], 1.0),
               [(0, 0.9), (0.6, 1.1), (1, 1.2)], [(0, 2.1), (0.5, 1.7), (1, 1.4)]), 1.2)
    # The canal: down and forward through the bone. The face there looks outward as well as forward; the canal meets it 25
    # degrees off square, leaning down and inward along it, so the opening is what Fig. 190 draws (page 1254, 2060): some
    # 4 mm across, a lip overhanging it above and outside, its floor running out downward and inward toward the canine fossa.
    # (It was a round hole drilled square to the face. Run straight forward to the face, the canal opened as a slanted slit.)
    # The lip is a wedge of 65 degrees, too sharp for the grid to hold: left as cut it meshed as a row of teeth, so the field
    # is eased there.
    io = spline([(30.9, -1.9, 69.3), (30.6, -3.0, 71.4), (30.25, -4.4, 73.8), (29.85, -5.7, 76.4), (29.52, -7.23, 79.28), (30.6, -9.4, 81.8),
                 (31.41, -11.01, 83.67)], 1.0)
    F.cut(Tube(io, [(0, 1.25), (0.5, 1.25), (0.83, 1.5), (1, 1.55)], [(0, 1.45), (0.5, 1.5), (0.83, 1.9), (1, 2.0)], taper=0.2), 0.7)
    io_n = np.array([0.60, -0.30, 0.75])                                             # the face's outward direction at the opening
    io_run = np.array([(29.94, -10.40, 81.78), (29.07, -11.74, 81.84), (28.14, -13.17, 81.81)])   # on the face, below and inward of the opening
    F.cut(Tube(io_run + np.array([0.35, 0.75, 1.25])[:, None] * io_n, 1.1, [(0, 1.5), (0.5, 2.0), (1, 2.4)], up=io_n), 1.2)   # the floor's run-out: a fan fading over 4 mm
    F.ease((30.8, -8.4, 80.8), 4.5, 0.6)
    # two more that the front view (Fig. 190) draws: the notch in the orbit's upper rim, 23.7 mm from the middle plane (page
    # 757, 1648), a groove across the rim's edge from the orbit's roof up on to the forehead; and the small hole on the cheek
    # bone's face, 51 mm out and 1 mm below the Frankfurt plane (page 505, 1983), running in toward the orbit
    F.cut(Ellipsoid((23.7, 30.2, 97.0), (2.6, 2.1, 3.6), rot((1, 0, 0), -30)), 1.2)   # supraorbital notch: a shallow rounded bite out of the rim's edge, 5 mm wide and under 2 deep
    # zygomaticofacial foramen and its canal. Gray (pages 164, 165): the malar surface is "perforated near its center by a small
    # aperture, the zygomaticofacial foramen", and on the orbital surface "are seen the orifices of two canals, the
    # zygomaticoorbital foramina; one of these canals opens into the temporal fossa, the other on the malar surface of the bone".
    # This is the second: a fine curved canal from the cheek bone's orbital surface, 4 mm inside the rim, outward, down and
    # forward through the bone to the cheek, where it opens 30 degrees off square with a short run-out below it. (It was a
    # straight blind hole, round on the face.) The first, the zygomaticotemporal canal, is cut after it: 5 mm higher on the
    # orbital surface, outward, upward and backward through the 3 mm of bone there into the temporal fossa.
    zf = spline([(44.4, 5.4, 66.6), (45.6, 4.6, 64.8), (47.6, 3.2, 65.0), (49.3, 1.5, 66.9), (50.5, 0.1, 69.2), (51.0, -0.9, 70.7), (51.5, -2.0, 72.0)], 0.8)
    F.cut(Tube(zf, [(0, 0.8), (0.15, 0.75), (0.75, 0.75), (0.9, 0.95), (1, 1.0)], [(0, 0.9), (0.15, 0.8), (0.75, 0.8), (0.9, 1.15), (1, 1.2)]), 0.5)
    zf_n = np.array([0.54, -0.08, 0.83])                                             # the cheek's outward direction at the opening
    zf_run = np.array([(51.2, -1.9, 70.43), (51.5, -3.0, 69.98), (51.8, -4.0, 69.4)])           # on the cheek, below the opening
    F.cut(Tube(zf_run + np.array([0.3, 0.6, 0.95])[:, None] * zf_n, 0.8, [(0, 0.9), (1, 1.4)], up=zf_n), 0.8)
    F.ease((51.0, -0.9, 70.6), 2.4, 0.4)
    F.cut(Tube(spline([(46.1, 8.4, 64.3), (47.2, 9.0, 63.3), (48.5, 9.8, 62.3), (49.6, 10.3, 61.2), (50.6, 10.6, 59.9)], 0.8), 0.7, 0.8), 0.4)   # zygomaticotemporal canal
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
    if build.pterygoid["vaginal"] is not None:
        build.midsolids.append((build.pterygoid["vaginal"], 0.8))       # the vaginal processes: thin leaves under the body, each side its own
    palate.lesser(F, log)                                   # the lesser palatine foramina, on the pyramidal process just added
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
    # the intermaxillary suture on the face, from under the nasal spine down between the central incisors' sockets (Fig. 190): a fine
    # wandering line, not a ridge. (Last in the list, so the lines before it keep the wander they had.)
    ys = np.arange(-33.5, -44.01, -0.5)
    zfront = front_z(F, 0.0, ys)
    if (zfront > 70.0).all():
        build.midline.append(("intermaxillary", np.column_stack([np.zeros(len(ys)), ys, zfront]), 0.45, max(0.3, 0.7 * h)))
    build.parts = dict(T=T, V=V, M=M, Zf=Zf, orbit=om, aperture=ap)
    return F, V


def whole(F, log=print, rough=True, sinuses=True, inside=True):
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
            Q = surface.wander_line(P, amp, np.random.default_rng(196) if name.endswith(", hind") else rng, **(dict(wave=sg["wave"], drift=sg["drift"], depth=lambda u: sg["hind"] + (1 - sg["hind"]) *
                                                         (1 - np.clip((u - 0.6) / 0.14, 0, 1))) if sg else {}))
            whole.midlines[name] = Q
            if name.endswith(", hind"):                          # one suture for bones.py: its hind part (cut with a wander of its own) and its front
                whole.midlines[name[:-6]] = np.concatenate([Q, whole.midlines.get(name[:-6], Q[:0])])
            G.cut(Tube(Q, r), 0.4)
    if inside:
        whole.inner = inner.build(G, log=log)                # the cavity's own surface: ridges, fossae, the sinuses' and the arteries' grooves (inner.py)
    foramina.through(G, log)                                  # the base's canals opened into the cavity, both sides, not alike (foramina.py)
    if sinuses:
        whole.sinuses = sinus.air(G, log)                    # the air sinuses: hollowed in the whole head, the two sides not alike
    temporal.relief(G, log)                                   # the temporal bone's small relief, each side with its own unevenness
    arch_relief(G, log)                                       # and each zygomatic arch's
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
