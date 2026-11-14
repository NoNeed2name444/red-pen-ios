"""mandible3.py: the lower jaw as one bone.

mandible2.py made the jaw from two solids, a body swept along the dental arch and a flat plate for the ramus,
joined afterwards; where they met it read as two parts. Here the jaw's half is ONE sheet of bone. The sheet is
laid along the line the lower border follows seen from above (from the chin back to the angle and on under the
ramus), and unrolled it is the jaw as the side view draws it: one outline (Gray 1918, Fig. 188, the same traced
lines mandible2 uses) from the chin along the lower border to the angle, up the hind border to the neck of the
condyle, across the notch to the coronoid tip, down the front border of the ramus and forward along the
tooth-bearing margin. On that one outline two surfaces are drawn, the cheek-side face and the tongue-side face:

  the body     its section at seven places, the ones mandible.py traced (chin, canine, premolar, molars);
  the ramus    thin in the middle (2.6 to 3.6 mm), 5.5 mm along the hind border, 5 at the angle, 3 to 4 along
               the front border, 2.2 at the notch and the coronoid tip; its angle turned a little outward;
  between      one surface passes into the other: the cheek-side face of the ramus runs forward and down on to
               the body as the oblique line, the tongue-side face steps in to the tooth-bearing margin behind
               the last molar (the shelf the third molar stands on).

So the cheek-side surface is a single continuous surface from chin to condyle. The condyle's head sits on the
sheet's neck in the skull's socket; the teeth's sockets are cut as before (teeth.seat).

Head frame, millimetres; the left half is computed and mirrored.
"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import sdf, relief, landmarks as L
import mandible as MB
import mandible2 as M2
import skull, teeth


def smoothstep(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


class Sheet:
    """A line seen from above (x, z), with distance s along it and n off it (outward = cheek side / forward)."""
    def __init__(self, Q, s0):
        self.Q = np.asarray(Q, float)
        d = np.linalg.norm(np.diff(self.Q, axis=0), axis=1)
        self.s = np.concatenate([[0], np.cumsum(d)]) - s0
        t = np.gradient(self.Q, axis=0); t /= np.linalg.norm(t, axis=1)[:, None]
        self.t = t; self.nrm = np.column_stack([-t[:, 1], t[:, 0]])
        self.tree = cKDTree(self.Q)

    def sn(self, x, z):
        x, z = np.broadcast_arrays(np.asarray(x, float), np.asarray(z, float))
        _, j = self.tree.query(np.column_stack([x.ravel(), z.ravel()]))
        dx, dz = x.ravel() - self.Q[j, 0], z.ravel() - self.Q[j, 1]
        s = self.s[j] + dx * self.t[j, 0] + dz * self.t[j, 1]
        n = dx * self.nrm[j, 0] + dz * self.nrm[j, 1]
        return s.reshape(x.shape), n.reshape(x.shape)

    def at(self, s, y, n=0.0):
        s, y, n = np.broadcast_arrays(np.asarray(s, float), np.asarray(y, float), np.asarray(n, float))
        qx, qz = np.interp(s, self.s, self.Q[:, 0]), np.interp(s, self.s, self.Q[:, 1])
        nx, nz = np.interp(s, self.s, self.nrm[:, 0]), np.interp(s, self.s, self.nrm[:, 1])
        return np.stack([qx + n * nx, y, qz + n * nz], axis=-1)


def smin(a, b, k):
    """The smaller of two distances, the crease between them eased over k mm (the union of two solids, filleted)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


class Ribbon:
    """The solid between two faces drawn on a Sheet's unrolled map (s, y), inside an outline, its rim rounded.
    The tongue side can be two faces at once: `inner`, and `body` = (its own tongue-side face, the distance
    under its top, how far it has sunk away): the solid then reaches whichever lies further toward the tongue,
    and where one passes into the other the hollow between them is filled to a radius of about `meet`/2."""
    def __init__(self, sheet, M, outer, inner, region, radius, body=None):
        self.S, self.M, self.two = sheet, M, body is not None
        A = [outer, inner, 1.0 / M.slope(outer), 1.0 / M.slope(inner), region, radius]
        low = inner
        if body is not None:
            A += [body[0], 1.0 / M.slope(body[0])] + list(body[1:])
            low = np.minimum(inner, body[0])
        self.c = [M.smooth(a) for a in A]
        ins = region < 2.0
        P = np.concatenate([sheet.at(M.U[ins], M.V[ins], outer[ins] + 3), sheet.at(M.U[ins], M.V[ins], low[ins] - 3)])
        lo, hi = P.min(0), P.max(0); lo[0] = max(lo[0], 0.0)
        self.bounds = (lo, hi)

    def __call__(self, X, Y, Z):
        x2, z2 = np.broadcast_arrays(X[:, :1, :], Z[:, :1, :])
        s, n = self.S.sn(x2, z2)
        u, v, w = np.broadcast_arrays(s, Y, n)
        V = [self.M.smooth_sample(c, u, v) for c in self.c]
        o, i, ko, ki, d2, r = V[:6]
        e = self.M.outside(u, v)
        d2 = np.where(e > 0, np.maximum(d2, e), d2)
        tongue = (i - w) * ki
        if self.two:
            b, kb, top, sunk, lip, meet, away = V[6:]
            tongue = smin(tongue + away, relief.round_meet((b - w) * kb, top, np.clip(lip, 0.8, 6.0)) + sunk, np.clip(meet, 0.3, 8.0))
        through = np.maximum((w - o) * ko, tongue)
        r = np.clip(r, 0.6, 6.0)
        return relief.round_meet(through, d2, r).astype(np.float32)


def sheet():
    """The line the sheet is laid along: under the lower border from the chin to the angle, and straight on behind."""
    B = np.array(M2.B, float)[:, [0, 2]]
    e = sdf.unit(B[-1] - B[-3])
    P = np.concatenate([B[:0:-1] * np.array([-1.0, 1.0]), B, B[-1] + np.outer([7.0, 14.0, 22.0], e)])
    Q = sdf.spline(P, 0.25)
    k0 = int(np.argmin(np.abs(Q[:, 0]) + 1e3 * (np.abs(Q[:, 1] - B[0, 1]) > 3)))
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))])
    keep = d > d[k0] - 16.0
    return Sheet(Q[keep], d[k0] - d[keep][0])


def ramus3(z, y, out=0.0):
    M2.use()
    return np.array([MB.on_ramus(a, b, out) for a, b in zip(np.atleast_1d(z), np.atleast_1d(y))])


def gauss(M, c, r):
    return np.exp(-(((M.U - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2))


def near_line(M, pts, r):
    """1 on a polyline drawn on the map (s, y), falling off over r mm."""
    pts = np.asarray(pts, float); d = np.full(M.U.shape, 1e9)
    for a, b in zip(pts[:-1], pts[1:]):
        e = b - a; L2 = max(float(e @ e), 1e-9)
        t = np.clip(((M.U - a[0]) * e[0] + (M.V - a[1]) * e[1]) / L2, 0, 1)
        d = np.minimum(d, np.hypot(M.U - a[0] - t * e[0], M.V - a[1] - t * e[1]))
    return np.exp(-(d / r) ** 2)


def maps(S, log=print):
    """Everything drawn on the unrolled sheet: the outline, the two faces, the rim's roundness; and the lines
    other steps need (the lower border and the tooth-bearing margin as heights over s)."""
    M2.use()
    M = relief.Map(-16.0, 114.0, -97.0, 4.0, 0.5)
    sy = lambda P: np.column_stack([S.sn(P[:, 0], P[:, 2])[0], P[:, 1]])
    # the outline, unrolled: tooth-bearing margin, front border of the ramus, coronoid, notch, neck, hind border, angle, lower border
    T = np.array(M2.T, float)[:8]; B = np.array(M2.B, float)
    O = np.array(M2.OUTLINE, float)
    ram = sy(ramus3(O[:, 0], O[:, 1]))                              # the traced ramus outline, point for point
    top = sy(T)
    low = sy(B)[:9][::-1]                                           # from under the ramus forward to the chin
    k_front = 16                                                    # OUTLINE[16] is the front border at the height of the teeth
    poly = np.concatenate([top[::-1] * np.array([-1.0, 1.0]), top,  # (mirrored across the midline so that no rim falls on it)
                           ram[k_front:], ram[:13], low, low[::-1][1:] * np.array([-1.0, 1.0])])
    poly = poly[np.concatenate([[True], np.linalg.norm(np.diff(poly, axis=0), axis=1) > 0.5])]
    reg = M.region(sdf.spline(poly, 1.0, closed=True))
    yb = lambda s: np.interp(np.abs(s), low[::-1][:, 0], low[::-1][:, 1])          # lower border
    s_t = np.concatenate([top[:, 0], [top[-1, 0] + 6, top[-1, 0] + 12, top[-1, 0] + 19]])
    y_t = np.concatenate([top[:, 1], [-57.6, -57.4, -57.2]])                       # the margin runs on level behind, to behind the last molar
    yt = lambda s: np.interp(np.abs(s), s_t, y_t)

    # the body's two faces, through its traced sections
    line = MB.body_line()
    Mc, up, a, b, tp, uu = line
    out_pts, in_pts = [], []
    for u in np.arange(0.0, 8.01, 0.5):
        i = int(np.argmin(np.abs(uu - u)))
        e = sdf.unit(Mc[min(i + 1, len(Mc) - 1)] - Mc[max(i - 1, 0)])
        w = sdf.unit(np.cross(e, up[i])); w = w if (w[0] > 0 or (u < 0.3 and w[2] > 0)) else -w
        o = MB.outlines(uu[i:i + 1], a[i:i + 1], n=56)[0]
        P = Mc[i] + o[:, 1:2] * up[i] + o[:, 0:1] * w
        s, n = S.sn(P[:, 0], P[:, 2])
        q = (P[:, 1] - yb(s)) / np.maximum(yt(s) - yb(s), 1.0)
        for side, pts, far in ((o[:, 0] > 1.0, out_pts, 6.51), (o[:, 0] < -1.0, in_pts, 8.01)):
            if u > far:
                continue
            ok = side & (q > 0.12) & (q < 0.93)
            pts.extend(np.column_stack([s[ok], P[ok, 1], n[ok]]))
    out_pts, in_pts = np.array(out_pts), np.array(in_pts)
    # behind the traced sections the cheek-side face thins toward the angle: 7 mm of bone behind the third molar, 5.5 at the angle
    for s0, th, mid in ((68.0, 7.4, 0.2), (76.0, 6.2, 0.1), (86.0, 5.4, 0.0)):
        for q in (0.25, 0.5, 0.75):
            out_pts = np.vstack([out_pts, [s0, yb(s0) + q * 16.0, mid + th / 2]])
    # the ramus: its own plane's offset from the sheet's line, its thickness through points, the angle turned outward
    nr = np.cross(MB.ES, MB.ET); nr = nr if nr[0] > 0 else -nr
    C0 = S.at(M.U, M.V, 0.0); N0 = S.at(M.U, M.V, 1.0) - C0
    mid = -((C0 - MB.O) @ nr) / np.maximum(N0 @ nr, 0.3)
    zs = lambda z, y: float(sy(ramus3(z, y))[0, 0])
    TH = [  # (z, y, thickness) on the side view
        (8.5, -12, 6.2), (9.5, -20, 5.7), (11.5, -30, 5.5), (14.5, -40, 5.5), (14.0, -50, 5.6), (13.0, -60, 5.6),     # hind border
        (17, -66, 5.3), (24, -70, 5.2), (34, -73, 6.0), (44, -76, 7.4),                                         # angle and lower border
        (30, -27, 2.6), (28, -38, 4.4), (28, -50, 4.4), (30, -60, 4.6), (21, -45, 3.8), (36, -40, 3.6), (36, -28, 2.8), (21, -30, 3.0),
        (45, -20, 3.2), (44.5, -30, 3.6), (43.0, -40, 4.2), (43.5, -48, 5.0),                                   # front border
        (41, -10, 2.8), (39.5, -7, 2.3), (26, -23, 2.2), (20, -21, 2.6), (31, -21, 2.2),                        # coronoid, notch
        (9.5, -9, 6.6), (12, -14, 5.6)]                                                                         # neck
    th = M.thin_plate(np.array([(zs(z, y), y, t) for z, y, t in TH]), weight=20.0, tension=0.05)
    th = np.clip(th, 2.0, 8.0)
    g = lambda z, y, r: gauss(M, (zs(z, y), y), (r, r))
    mid = mid + 1.8 * g(14.0, -64.0, 11.0) + 1.2 * g(40.0, -8.0, 9.0)        # the angle turned outward; the coronoid tip curves out a little
    orr, irr = mid + th / 2, mid - th / 2
    # cheek-side roughness for the masseter near the angle (low oblique ridges), the lingula's ridge and the ridge from the neck on the tongue side
    for (z0, y0), (z1, y1), hgt in (((14, -52), (26, -64), 0.22), ((18, -46), (32, -60), 0.16), ((13, -60), (20, -68), 0.2), ((22, -48), (36, -62), 0.12)):
        orr = orr + hgt * near_line(M, [(zs(z0, y0), y0), (zs(z1, y1), y1)], 2.4)
    irr = irr - 1.6 * near_line(M, [(zs(10.5, -12), -12), (zs(17, -22), -22), (zs(25, -31), -31)], 3.0)     # neck to lingula
    irr = irr - 1.2 * near_line(M, [(zs(41, -10), -10), (zs(43, -22), -22), (zs(42.5, -34), -34), (zs(41.5, -45), -45)], 2.6)   # temporal crest
    irr = irr - 0.5 * near_line(M, [(zs(15, -54), -54), (zs(25, -64), -64)], 1.6) - 0.5 * near_line(M, [(zs(20, -50), -50), (zs(31, -62), -62)], 1.6)

    # the cheek-side face: the body's, passing into the ramus's (which reaches forward highest up: the oblique line)
    gs, gy = np.meshgrid(np.arange(74.0, 111.0, 6.0), np.arange(-92.0, 1.0, 6.0), indexing="ij")
    out_pts = np.vstack([out_pts, np.column_stack([gs.ravel(), gy.ravel(), M.sample(orr, gs.ravel(), gy.ravel())])])
    sym = lambda P: np.vstack([P, P * np.array([-1.0, 1.0, 1.0])])
    ob = ndimage.gaussian_filter(M.thin_plate(sym(out_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")     # (1.5 mm: no pimple at a control point)
    ib = ndimage.gaussian_filter(M.thin_plate(sym(in_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")
    q = np.clip((M.V - yb(M.U)) / np.maximum(yt(M.U) - yb(M.U), 1.0), 0, 1.4)
    s = np.abs(M.U)
    w_out = smoothstep((s - 44.0 - 16.0 * (1 - np.minimum(q, 1.0))) / 16.0)
    outer = ob * (1 - w_out) + orr * w_out
    # The tongue side. Under the teeth it is the body's own face (its traced sections), and the body's top is the
    # tooth-bearing margin: the shelf the third molar stands on, with the ramus rising from its cheek-side third.
    # Behind that tooth there is no second surface: the ramus's face itself swells toward the tongue to meet the
    # body's (the retromolar triangle, the foot of the temporal crest), and the swelling dies away upward in 16 mm
    # and backward in 30, toward the angle. So from the last molar back the tongue side is a single smooth face.
    fr = [f for f in teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False) if f["side"] == "L"]
    tn = np.array([[float(v) for v in S.sn(f["position_mm"][0], f["position_mm"][2])] for f in fr])
    # Both faces stand clear of every root: each root's own surface (the tooth as it stands in its socket) is laid on
    # the map, and where a face comes nearer than 2.1 mm to it (0.8 at the margin, where the plate of bone is thin)
    # the face is lifted over it, gently: the low swellings over the roots that a jaw has.
    need_out = np.full(M.U.shape, -1e3); need_in = np.full(M.U.shape, 1e3)
    for f in fr:
        k = L.TEETH.index(f["tooth"].split(" ", 1)[1])
        R, p0 = teeth.frame(f)
        v = teeth.AT.tooth("lower", k, h=0.3)[0]
        v = v[v[:, 2] < -teeth.NECK_ABOVE_CREST]
        Pw = v @ R.T + p0
        sv, nv = S.sn(Pw[:, 0], Pw[:, 2])
        wall = 0.8 + 1.3 * smoothstep((-teeth.NECK_ABOVE_CREST - v[:, 2]) / 4.0)
        for sg in (1.0, -1.0):
            i, j = M.ij(sg * sv, Pw[:, 1]); i, j = np.round(i).astype(int), np.round(j).astype(int)
            ok = (i >= 0) & (i < M.nu) & (j >= 0) & (j < M.nv)
            np.maximum.at(need_out, (i[ok], j[ok]), (nv + wall)[ok]); np.minimum.at(need_in, (i[ok], j[ok]), (nv - wall)[ok])
    lift = ndimage.gaussian_filter(ndimage.maximum_filter(np.maximum(need_out - outer, 0.0), 11), 3.0)
    sink = ndimage.gaussian_filter(ndimage.maximum_filter(np.maximum(ib - need_in, 0.0), 11), 3.0)
    log("jaw sheet: to clear the roots the cheek-side face is lifted by up to %.1f mm and the tongue-side by up to %.1f" % (lift.max(), sink.max()))
    outer = outer + 1.1 * lift
    ib = ib - 1.1 * sink
    ib = np.minimum(ib, outer - 1.8)
    irr = np.minimum(irr, outer - 1.8)
    s3 = float(tn[-1, 0]) + 5.0                                                      # the hind end of the third molar
    swell = np.maximum(irr - ib, 0.0) * (1 - smoothstep((M.V - (yt(M.U) - 1.0)) / 16.0)) * (1 - smoothstep((s - (s3 + 9.0)) / 24.0)) * smoothstep((s - (s3 - 1.0)) / 6.0)
    irr = irr - swell
    away = 40.0 * (1 - smoothstep((s - 40.0) / 8.0))                                 # in front of the second molar the ramus's face is nothing
    top = M.V - (yt(M.U) + 3.0 * (1 - smoothstep((s - 44.0) / 5.0)))                 # (in front, the outline itself is the top)
    sunk = 30.0 * smoothstep((s - (s3 + 4.5)) / 4.0)                                 # behind the tooth the body's face is the ramus's: let it go
    lip = np.full(M.U.shape, 1.5)                                                    # the shelf's tongue-side edge
    meet = 0.6 + 4.4 * (1 - smoothstep((s - (s3 - 1.0)) / 5.0))                      # the hollow where the shelf meets the ramus, filled; none where the two faces are one
    d2 = np.abs(np.diff(irr, 2, axis=0))[(reg[1:-1] < 0) & (s[1:-1] > s3 + 6)]
    log("jaw sheet: third molar ends at s %.1f; behind it the tongue-side face bends at most %.2f mm from one half-millimetre row to the next" % (s3, d2.max()))

    # the rim's roundness: the lower border broad, the hind border and angle rounded, the notch and coronoid thin, the tooth-bearing margin 2 mm
    edge = [(0.0, yb(0.0), 4.6), (20.0, yb(20.0), 4.2), (45.0, yb(45.0), 3.8), (70.0, yb(70.0), 3.2)]
    edge += [(zs(z, y), y, r) for z, y, r in ((16, -68, 2.6), (11, -55, 2.7), (12, -37, 2.7), (8, -20, 2.8), (7, -9, 3.0),
                                              (26, -21, 1.1), (39.5, -6, 1.2), (46, -20, 1.5), (45.5, -40, 1.8), (48, -56, 2.0))]
    edge += [(sv, yt(sv), 2.0) for sv in (0.0, 15.0, 30.0, 45.0)]
    rad = M.thin_plate(np.array(sym(np.array(edge)), float), weight=10.0, tension=0.3)
    log("jaw sheet: body faces through %d and %d traced points, ramus thickness through %d" % (len(out_pts), len(in_pts), len(TH)))
    return dict(M=M, reg=reg, outer=outer, inner=irr, inner_body=ib, top=top, sunk=sunk, lip=lip, meet=meet, away=away, rad=rad, yb=yb, yt=yt, zs=zs)


def build(h=0.5, log=print, seat=True):
    M2.use()
    S = sheet()
    W = maps(S, log)
    M = W["M"]
    F = sdf.Field([0, -99, -4], [66, 5, 101], h)
    F.add(Ribbon(S, M, W["outer"], W["inner"], W["reg"], W["rad"], body=(W["inner_body"], W["top"], W["sunk"], W["lip"], W["meet"], W["away"])))

    def face(z, y, cheek=True, lift=0.0, s=None):
        """A point on the jaw's cheek-side (or tongue-side) face, by its place on the side view (z, y) or at (s, y)."""
        sv = W["zs"](z, y) if s is None else s
        A = W["outer"] if cheek else (W["inner"] if s is None else W["inner_body"])           # tongue side: the ramus's face by (z, y), the body's by (s, y)
        n = float(M.sample(A, np.array([sv], float), np.array([y], float))[0]) + (lift if cheek else -lift)
        return S.at(sv, y, n), sdf.unit(S.at(sv, y, n + 1.0) - S.at(sv, y, n))

    c = M2.CONDYLE
    F.add(sdf.Ellipsoid(c["centre"], c["half"], sdf.rot((0, 1, 0), c["turn"])), k=3.0)                # the head, on the sheet's neck
    p, w = face(13.5, -8.6, False)
    F.cut(sdf.Ellipsoid(p - 0.4 * w, (3.0, 3.2, 2.0)), k=1.5)                                          # pterygoid fovea on the front of the neck
    p, w = face(0, W["yb"](0.0) + 9.0, False, s=0.0)
    F.add(sdf.Ellipsoid(p + 0.3 * w, (1.6, 2.4, 1.5)), k=1.5)                                          # mental spines
    p, w = face(28.5, -33.5, False)
    F.add(sdf.Ellipsoid(p - 0.3 * w, (1.3, 2.4, 1.3)), k=1.5)                                          # lingula
    a, _ = face(26.5, -37.0, False); b_, w = face(23.8, -31.0, False)
    F.cut(sdf.Tube(np.array([b_ - 3.0 * w, a - 0.1 * w + np.array([0.0, -2.0, 1.5])]), 1.35), k=0.8)   # mandibular foramen behind it: the canal runs down and forward inside the bone
    p, w = face(0, W["yb"](10.0) + 3.5, False, s=10.0)
    F.cut(sdf.Ellipsoid(p - 0.8 * w, (6.0, 3.0, 3.0)), k=2.5)                                          # digastric fossa
    sdf.ease_midline(F)
    frames = teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False)
    if seat:
        teeth.seat(F, frames, False, reach=5.0)            # the sheet's faces already clear the roots (maps): bone is added at the margin only
        lab, n = ndimage.label(F.D < 0)                                                              # specks of bone left loose inside a socket (between close roots) go
        if n > 1:
            big = int(np.argmax(ndimage.sum(np.ones_like(lab), lab, np.arange(1, n + 1)))) + 1
            F.D[(lab > 0) & (lab != big)] = 0.5 * h
    fr = [f for f in teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False) if f["side"] == "L"]
    pm = np.array(fr[4]["position_mm"]); sm, _ = S.sn(pm[0], pm[2])
    mf, w = face(0, pm[1] - 15.5, True, s=float(sm))                                                 # under the second premolar, just below its root's tip
    back = sdf.unit(S.at(float(sm) + 2.0, 0.0) - S.at(float(sm), 0.0)); up1 = np.array([0.0, 1.0, 0.0])
    F.cut(sdf.Tube(np.array([mf + 2.5 * w + 0.8 * up1 - 0.6 * back, mf - 2.2 * w - 0.8 * up1 + 0.8 * back]), 1.3), k=0.6)   # mental foramen: it opens backward and upward (cut last: clear of that root)
    return F, {"mental foramen": np.round(mf, 1).tolist(), "sockets": frames, "sheet": S, "maps": W}
