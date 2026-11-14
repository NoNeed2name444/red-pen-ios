"""mandible4.py: the lower jaw as one bone, its form read from Gray's two plates of the jaw alone.

mandible3.py made the jaw one sheet of bone laid along the lower border's line, its outline the one Gray's side view
of the skull draws (Fig. 188); that machinery is kept (Sheet, Ribbon). Seen alone from eight sides that jaw was a
board with a knob on a stalk for a joint, a chin with no shape and a lower border as even as a pipe. What is new
here is read from the plates of the jaw alone (Gray 1918, public domain: Fig. 176 outer surface, Fig. 177 inner
surface) and the text beside them (pp. 172 to 174):

  ramus      leans outward going up (98 mm across the angles, 120 across the joint heads): the joint head then
             overhangs its neck toward the tongue, as it does, not toward the cheek
  joint      the neck "flattened from before backward" widens from the hind border up into the head (18 by 8 mm,
             its long axis turned 15 degrees); the hollow for the lateral pterygoid on the front of the neck; the
             tubercle at the head's outer end
  body       thins behind the last molar low down (the hollow for the gland runs back on to the ramus) and keeps
             its thickness only along the tooth-bearing margin (retromolar triangle)
  chin       the mental protuberance with a tubercle either side and the base hollowed between; the incisive
             fossae; the oblique line from the tubercle to the ramus's front border
  openings   the mental foramen midway between the borders, between the two premolars' roots, opening backward
             and upward; the mandibular foramen as an oblique funnel behind the lingula's ridge, the mylohyoid
             groove running down and forward from it
  tongue     the mylohyoid line, faint in front and strong behind; the hollows for the two glands above and below
  side       it; the digastric fossae; the mental spines (a pair above, a ridge below)
  angle      turned outward, ridged outside for the masseter and inside for the medial pterygoid

Head frame, millimetres; the left half is computed and mirrored; the grain and pits, which must not be the same on
both sides, go on afterwards (whole).
"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import sdf, relief, landmarks as L
import mandible as MB
import mandible2 as M2
import skull, teeth, surface
from mandible3 import Sheet, Ribbon, sheet, smin, gauss, near_line

LEAN = 0.124                                   # the ramus plane's lean outward per mm of height
O4 = np.array([52.2, -12.0, 10.5])            # a point of the ramus plane (at the neck)
HEAD = {"centre": (51.5, -5.9, 9.5), "half": (9.0, 4.3, 3.9), "turn": -15.0}     # in the skull's socket, 1.5 to 2 mm clear of it all round


# The ramus's outline as mandible2 traced it from the side view of the skull (Fig. 188), but for the coronoid process: there
# the plate shows only what is below the cheek's arch, and mandible2 ended it flat at the arch's lower border. It runs on up
# behind the arch to a point (Fig. 176: "a thin, triangular eminence", its front border convex, its hind border concave).
OUTLINE = M2.OUTLINE[:21] + [(46.9, -12.0), (45.3, -7.4), (43.1, -3.8), (40.7, -2.0), (39.0, -2.8), (37.4, -6.0), (35.7, -10.3)] + M2.OUTLINE[26:]


def use():
    """mandible2's traced lines, with the ramus plane leaned so that the neck stands under the head's outer half."""
    M2.use()
    ET = np.array([LEAN, 1.0, 0.0])
    MB.O, MB.ET = O4, sdf.unit(ET - (ET @ MB.ES) * MB.ES)


def smoothstep(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def ramus3(z, y, out=0.0):
    use()
    return np.array([MB.on_ramus(a, b, out) for a, b in zip(np.atleast_1d(z), np.atleast_1d(y))])


def near_abs(M, pts, r):
    """near_line on both halves of the map at once (s read as its distance from the midline)."""
    pts = np.asarray(pts, float); d = np.full(M.U.shape, 1e9); U = np.abs(M.U)
    for a, b in zip(pts[:-1], pts[1:]):
        e = b - a; L2 = max(float(e @ e), 1e-9)
        t = np.clip(((U - a[0]) * e[0] + (M.V - a[1]) * e[1]) / L2, 0, 1)
        d = np.minimum(d, np.hypot(U - a[0] - t * e[0], M.V - a[1] - t * e[1]))
    return np.exp(-(d / r) ** 2)


def maps(S, log=print):
    """Everything drawn on the unrolled sheet: the outline, the two faces, the rim's roundness; and the lines
    other steps need (the lower border and the tooth-bearing margin as heights over s)."""
    use()
    M = relief.Map(-16.0, 114.0, -101.0, 4.0, 0.5)
    sy = lambda P: np.column_stack([S.sn(P[:, 0], P[:, 2])[0], P[:, 1]])
    # the outline, unrolled: tooth-bearing margin, front border of the ramus, coronoid, notch, neck, hind border, angle, lower border
    T = np.array(M2.T, float)[:8]; B = np.array(M2.B, float)
    O = np.array(OUTLINE, float)
    ram = sy(ramus3(O[:, 0], O[:, 1]))                              # the traced ramus outline, point for point
    top = sy(T)
    low = sy(B)[:9][::-1]                                           # from under the ramus forward to the chin
    low[:, 1] += 1.2 * np.exp(-((low[:, 0] - low[1, 0]) / 7.0) ** 2)  # the shallow notch in front of the angle (the facial artery's groove)
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
        (16, -65, 5.3), (23, -69.5, 5.2), (34, -74.5, 6.0), (44, -78.5, 7.4),                                   # angle and lower border
        (30, -27, 2.6), (28, -38, 4.4), (28, -50, 4.4), (30, -60, 4.6), (21, -45, 3.8), (36, -40, 3.6), (36, -28, 2.8), (21, -30, 3.0),
        (45, -20, 3.2), (44.5, -30, 3.6), (43.0, -40, 4.2), (43.5, -48, 5.0),                                   # front border
        (41, -10, 2.8), (39.5, -7, 2.3), (26, -23, 2.2), (20, -21, 2.6), (31, -21, 2.2),                        # coronoid, notch
        (9.5, -9, 6.6), (12, -14, 5.6)]                                                                         # neck
    th = M.thin_plate(np.array([(zs(z, y), y, t) for z, y, t in TH]), weight=20.0, tension=0.05)
    th = np.clip(th, 2.0, 8.0)
    g = lambda z, y, r: gauss(M, (zs(z, y), y), (r, r))
    # Seen from in front the jaw's side is no upright ruled line (the owner, 14 November: "it shouldn't be perfectly straight in
    # sides"). An earlier build turned the angle 0.8 mm out and hollowed the ramus 0.8 above it, which together undid the
    # plane's own lean: 20 mm of the side stood exactly upright. Now the side keeps the plane's lean all the way down (in by
    # 1 mm for every 8 of height, 121 mm across the joint heads to 98 across the angles), a little hollow under the neck and
    # a little full over the masseter's ridges, and turns in to the lower border round the angle.
    mid = mid + 1.2 * g(40.0, -8.0, 9.0)                                     # the coronoid tip curves out a little
    mid = mid - 0.35 * g(17.0, -38.0, 10.0) + 1.2 * g(11.0, -24.0, 7.0) + 0.3 * g(17.0, -55.0, 7.0)
    orr, irr = mid + th / 2, mid - th / 2
    # cheek-side roughness for the masseter near the angle (low oblique ridges), the lingula's ridge and the ridge from the neck on the tongue side
    for (z0, y0), (z1, y1), hgt in (((14, -52), (26, -65), 0.42), ((18, -45), (33, -61), 0.34), ((13, -60), (20, -69), 0.4), ((23, -47), (38, -63), 0.26), ((12, -44), (19, -53), 0.22)):
        orr = orr + hgt * near_line(M, [(zs(z0, y0), y0), (zs(0.5 * (z0 + z1) + 0.8, 0.5 * (y0 + y1)), 0.5 * (y0 + y1)), (zs(z1, y1), y1)], 1.9)
    irr = irr - 1.6 * near_line(M, [(zs(10.5, -12), -12), (zs(17, -22), -22), (zs(25, -31), -31)], 3.0)     # neck to lingula
    irr = irr - 1.2 * near_line(M, [(zs(41, -10), -10), (zs(43, -22), -22), (zs(42.5, -34), -34), (zs(41.5, -45), -45)], 2.6)   # temporal crest
    for (z0, y0), (z1, y1), hgt in (((15, -55), (25, -66), 0.55), ((19, -50), (31, -63), 0.5), ((13, -62), (19, -69), 0.45), ((24, -48), (36, -61), 0.35)):
        irr = irr - hgt * near_line(M, [(zs(z0, y0), y0), (zs(z1, y1), y1)], 1.7)                             # the medial pterygoid's ridges at the angle
    irr = irr - 0.8 * near_line(M, [(zs(29.8, -26.5), -26.5), (zs(29.4, -34.0), -34.0)], 1.8)                # the ridge in front of the mandibular foramen (it bears the lingula)
    irr = irr - 0.9 * g(28.5, -41.0, 5.0)                                                                    # bone over the canal where it enters
    irr = irr + 0.55 * near_line(M, [(zs(26.6, -39.0), -39.0), (zs(32.0, -47.5), -47.5), (zs(39.0, -56.5), -56.5), (zs(45.5, -62.5), -62.5)], 1.05)   # mylohyoid groove

    # the cheek-side face: the body's, passing into the ramus's (which reaches forward highest up: the oblique line)
    gs, gy = np.meshgrid(np.arange(74.0, 111.0, 6.0), np.arange(-92.0, 1.0, 6.0), indexing="ij")
    out_pts = np.vstack([out_pts, np.column_stack([gs.ravel(), gy.ravel(), M.sample(orr, gs.ravel(), gy.ravel())])])
    sym = lambda P: np.vstack([P, P * np.array([-1.0, 1.0, 1.0])])
    ob = ndimage.gaussian_filter(M.thin_plate(sym(out_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")     # (1.5 mm: no pimple at a control point)
    ib = ndimage.gaussian_filter(M.thin_plate(sym(in_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")
    s_ = np.abs(M.U)
    H2 = lambda c, r: np.exp(-(((s_ - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2))
    yc_ = float(yb(0.0))
    myl = [(63.0, float(yt(63.0)) - 5.0), (52.0, float(yt(52.0)) - 7.5), (40.0, float(yt(40.0)) - 11.0), (28.0, float(yb(28.0)) + 12.0), (16.0, float(yb(16.0)) + 9.5), (6.0, yc_ + 8.5)]
    ib = ib - 1.1 * near_abs(M, myl, 1.8) * (0.35 + 0.65 * smoothstep((s_ - 12.0) / 22.0))      # mylohyoid line: faint in front, strong behind
    ib = ib + 1.4 * H2((45.0, float(yb(45.0)) + 8.0), (11.0, 4.6))                             # the hollow for the submandibular gland, under its hind part
    ib = ib + 0.5 * H2((19.0, float(yt(19.0)) - 9.0), (8.0, 4.2))                              # the hollow for the sublingual gland, above its front part
    q = np.clip((M.V - yb(M.U)) / np.maximum(yt(M.U) - yb(M.U), 1.0), 0, 1.4)
    s = np.abs(M.U)
    w_out = smoothstep((s - 44.0 - 16.0 * (1 - np.minimum(q, 1.0))) / 16.0)
    outer = ob * (1 - w_out) + orr * w_out
    # the chin and the oblique line (Fig. 176); all of it before the roots' clearance is taken below
    yc = float(yb(0.0))
    G2 = lambda c, r: np.exp(-(((s - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2))
    outer = outer + 1.0 * G2((0.0, yc + 8.5), (7.5, 5.5))                        # mental protuberance
    outer = outer + 0.85 * G2((10.5, yc + 4.8), (4.2, 3.6))                      # mental tubercles
    outer = outer - 0.45 * G2((0.0, yc + 2.6), (4.2, 2.5))                       # the protuberance's base, depressed in the centre
    outer = outer + 0.3 * np.exp(-(s / 1.4) ** 2) * smoothstep((M.V - (yc + 13.0)) / 3.0) * smoothstep((yt(M.U) - 1.0 - M.V) / 3.0)   # the symphysis's faint ridge above it
    outer = outer - 0.7 * G2((7.0, yc + 20.5), (4.0, 3.8))                       # incisive fossa
    s_fr = zs(48.3, -58.0)                                                       # the ramus's front border at the height of the margin
    outer = outer + 0.45 * near_abs(M, [(12.5, yc + 5.5), (26.0, yb(26.0) + 9.5), (40.0, yb(40.0) + 13.5), (52.0, yb(52.0) + 18.0), (s_fr, -58.5)], 2.6)   # oblique line
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
    # How far back the body keeps its thickness depends on the height: low down it thins from under the last molar and is the
    # ramus's own 12 mm behind it (the gland's hollow runs back on to the ramus); at the margin's height it lasts 26 mm
    # (the retromolar triangle and the foot of the temporal crest). The body's own face follows the same law, so that where
    # it is let go (sunk, below) there is no step from the one face to the other.
    qq = np.clip(q, 0.0, 1.0)
    back = 1 - smoothstep((s - (s3 - 4.0 + 8.0 * qq)) / (16.0 + 6.0 * qq))
    more = np.maximum(irr - ib, 0.0)
    ib = ib + smoothstep((s - (s3 - 8.0)) / 4.0) * (irr - more * back - ib)
    swell = more * (1 - smoothstep((M.V - (yt(M.U) - 1.0)) / 16.0)) * back * smoothstep((s - (s3 - 1.0)) / 6.0)
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
    edge += [(zs(z, y), y, r) for z, y, r in ((15.5, -66, 2.6), (11.5, -55, 2.7), (12, -37, 2.7), (8, -20, 2.8), (7, -9, 3.0),
                                              (26, -21, 1.1), (39.5, -6, 1.2), (46, -20, 1.5), (45.5, -40, 1.8), (48, -56, 2.0))]
    edge += [(sv, yt(sv), 2.0) for sv in (0.0, 15.0, 30.0, 45.0)]
    rad = M.thin_plate(np.array(sym(np.array(edge)), float), weight=10.0, tension=0.3)
    log("jaw sheet: body faces through %d and %d traced points, ramus thickness through %d" % (len(out_pts), len(in_pts), len(TH)))
    return dict(M=M, reg=reg, outer=outer, inner=irr, inner_body=ib, top=top, sunk=sunk, lip=lip, meet=meet, away=away, rad=rad, yb=yb, yt=yt, zs=zs)


def build(h=0.5, log=print, seat=True):
    use()
    S = sheet()
    W = maps(S, log)
    M = W["M"]
    F = sdf.Field([0, -103, -4], [68, 5, 101], h)
    F.add(Ribbon(S, M, W["outer"], W["inner"], W["reg"], W["rad"], body=(W["inner_body"], W["top"], W["sunk"], W["lip"], W["meet"], W["away"])))
    on = lambda z, y, out=0.0: MB.on_ramus(z, y, out)

    def face(z, y, cheek=True, lift=0.0, s=None):
        """A point on the jaw's cheek-side (or tongue-side) face, by its place on the side view (z, y) or at (s, y),
        and the direction toward the cheek there."""
        sv = W["zs"](z, y) if s is None else s
        A = W["outer"] if cheek else (W["inner"] if s is None else W["inner_body"])           # tongue side: the ramus's face by (z, y), the body's by (s, y)
        n = float(M.sample(A, np.array([sv], float), np.array([y], float))[0]) + (lift if cheek else -lift)
        return S.at(sv, y, n), sdf.unit(S.at(sv, y, n + 1.0) - S.at(sv, y, n))

    # ---- the condyloid process. The neck is "flattened from before backward": seen from behind it widens from the ramus's
    # thick hind border up into the head, seen from the side it stays narrow. Its sections are ovals set along the head's
    # long axis, which runs toward the midline and a little backward.
    c = HEAD
    R = sdf.rot((0, 1, 0), c["turn"]); axis = R @ np.array([1.0, 0.0, 0.0])
    ctr = np.array(c["centre"], float)
    P = sdf.spline(np.array([on(13.4, -27.0), on(11.9, -20.0), on(10.3, -13.5) + 0.25 * (ctr - on(10.3, -13.5)) * np.array([1, 0, 0]),
                             ctr + np.array([0.5, -3.0, 0.1])]), 0.8)
    F.add(sdf.Tube(P, [(0, 2.6), (0.35, 3.1), (0.7, 4.6), (0.88, 6.6), (1, 8.0)], [(0, 3.1), (0.35, 3.3), (0.7, 3.5), (1, 3.6)], up=axis), k=2.5)
    F.add(sdf.Ellipsoid(ctr, c["half"], R), k=2.2)                                                    # the head: convex from before backward and from side to side
    F.add(sdf.Ellipsoid(ctr + R @ np.array([8.3, -1.9, 0.9]), (1.5, 1.9, 1.7)), k=1.2)               # the tubercle at its outer end (temporomandibular ligament)
    F.cut(sdf.Ellipsoid(ctr + R @ np.array([-1.6, -4.6, 4.6]), (4.2, 2.6, 1.7), R), k=1.4)           # the hollow on the front of the neck (lateral pterygoid)

    # ---- the tongue side of the ramus: the mandibular foramen, an oblique funnel that runs down and forward into the bone
    # behind the ridge that bears the lingula
    p0, w0 = face(23.4, -30.0, False); p1, w1 = face(28.8, -40.5, False)
    F.cut(sdf.Tube(sdf.spline(np.array([p0 - 1.9 * w0, 0.5 * (p0 + p1) - 0.2 * w0 + np.array([0.0, 0.6, -0.6]), p1 + 1.9 * w1]), 0.6), [(0, 2.2), (0.5, 1.7), (1, 1.15)]), k=0.8)
    q0, v0 = face(29.3, -35.4, False); q1, v1 = face(27.7, -32.0, False)
    F.add(sdf.Tube(np.array([q0 + 0.2 * v0, 0.5 * (q0 + q1) - 0.35 * v0, q1 - 0.7 * v1]), [(0, 1.6), (0.6, 1.35), (1, 1.0)]), k=1.2)     # the lingula: a spine pointing up and back over the opening

    # ---- the tongue side of the chin: the mental spines (a pair above, a low ridge below) and the digastric fossae
    yc = float(W["yb"](0.0))
    p, w = face(0, yc + 11.0, False, s=1.5)
    F.add(sdf.Ellipsoid(p + 0.1 * w, (1.1, 1.5, 1.2)), k=1.0)
    p, w = face(0, yc + 7.2, False, s=0.0)
    F.add(sdf.Ellipsoid(p + 0.25 * w, (0.9, 2.1, 1.1)), k=1.0)
    p, w = face(0, yc + 2.6, False, s=10.5)
    F.cut(sdf.Ellipsoid(p - 1.6 * w + np.array([0.0, -1.2, 0.0]), (5.6, 2.6, 2.5)), k=1.6)             # digastric fossa: a shallow oval on the base's hind slope
    sdf.ease_midline(F)
    frames = teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False)
    if seat:
        teeth.seat(F, frames, False, reach=5.0)            # the sheet's faces already clear the roots (maps): bone is added at the margin only
        lab, n = ndimage.label(F.D < 0)                                                              # specks of bone left loose inside a socket (between close roots) go
        if n > 1:
            big = int(np.argmax(ndimage.sum(np.ones_like(lab), lab, np.arange(1, n + 1)))) + 1
            F.D[(lab > 0) & (lab != big)] = 0.5 * h
    # ---- the mental foramen: "midway between the upper and lower borders of the body", between the two premolars' roots
    # and a little toward the second; it opens backward and upward
    fr = [f for f in frames if f["side"] == "L"]
    pa, pb = np.array(fr[3]["position_mm"]), np.array(fr[4]["position_mm"])
    sm = 0.4 * float(S.sn(pa[0], pa[2])[0]) + 0.6 * float(S.sn(pb[0], pb[2])[0])
    ym = 0.5 * (float(W["yt"](sm)) + float(W["yb"](sm)))
    mf, w = face(0, ym, True, s=sm)
    back = sdf.unit(S.at(sm + 2.0, 0.0) - S.at(sm, 0.0)); up1 = np.array([0.0, 1.0, 0.0])
    F.cut(sdf.Tube(np.array([mf + 2.4 * w + 0.9 * up1 + 0.9 * back, mf - 2.0 * w - 0.7 * up1 - 0.7 * back]), [(0, 1.45), (1, 1.1)]), k=0.6)
    log("jaw: mental foramen at %s, %.1f mm below the margin and %.1f above the lower border; joint head %.0f by %.0f mm at %s"
        % (np.round(mf, 1).tolist(), float(W["yt"](sm)) - ym, ym - float(W["yb"](sm)), 2 * c["half"][0], 2 * c["half"][2], list(c["centre"])))
    return F, {"mental foramen": np.round(mf, 1).tolist(), "sockets": frames, "sheet": S, "maps": W}


ZONES = [   # name, centre, radii, extra grain (mm), pits per mm2 (surface.py)
    ("masseter's and medial pterygoid's ridges at the angle", (47, -58, 20), (7, 14, 13), 0.04, -0.01),      # (no pits here: at the grid's size they came out as craters)
    ("masseter's and medial pterygoid's ridges at the angle", (-47, -58, 20), (7, 14, 13), 0.04, -0.01),
    ("chin", (0, -80, 90), (17, 11, 9), 0.02, 0.03),
    ("tooth-bearing margin", (0, -63, 68), (30, 5, 30), 0.03, 0.06),
    ("coronoid process (temporalis)", (47, -14, 40), (5, 10, 7), 0.025, 0.0),
    ("coronoid process (temporalis)", (-47, -14, 40), (5, 10, 7), 0.025, 0.0),
    ("joint head", (51, -4, 9.5), (11, 4.5, 6), -0.03, -0.02),
    ("joint head", (-51, -4, 9.5), (11, 4.5, 6), -0.03, -0.02),
]


def whole(F, info, log=print, rough=True, seed=176):
    """The whole jaw's field from its left half: mirrored, then given its grain and pits (each side its own). Returns (D, lo)."""
    D = sdf.mirror_field(F.D); lo = np.array([-float(F.ax[0][-1]), float(F.lo[1]), float(F.lo[2])])
    if not rough:
        return D, lo
    D0 = D.copy()
    D = surface.roughen(D, lo, F.h, seed=seed, zones=ZONES, log=log)
    G = sdf.Field.__new__(sdf.Field); G.h = F.h; G.lo = lo; G.n = np.array(D.shape)
    G.ax = [(lo[k] + F.h * np.arange(D.shape[k])).astype(np.float32) for k in range(3)]; G.D = D
    for s in info["sockets"]:                                 # round the teeth the bone may not grow, nor wear away by more than a hair
        p = np.array(s["position_mm"], float); a = np.array(s["axis"], float)
        q = [p + 3.0 * a, p - a * (s["root_mm"] + 2.0)]
        sl = G.window(np.minimum(*q) - 7.0, np.maximum(*q) + 7.0)
        if sl is not None:
            G.D[sl] = np.clip(G.D[sl], D0[sl], D0[sl] + 0.12)
    return G.D, lo
