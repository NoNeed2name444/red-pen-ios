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

BACK_L, OUT_S0, OUT_L = 58.0, 28.0, 80.0         # the lengths over which body passes into ramus (tongue side, cheek side)
BACK_Q0, BACK_TOP = 0.45, 0.25      # (task C; T-arch-lower: 0.45 to 0.10, below) below this fraction of the body's height the tongue-side face is given up over BACK_L / 2: carried on
# (T-arch-lower: at the margin's height it was carried 55 mm back, nearly to the hind border: from below and from inside a
# shelf ran under the angle. With the body now as wide as the ramus behind the molars there is less to bridge: 43 mm.)
# over most of BACK_L down to the lower border, the body's face stood on the angle's inner side as a long smooth swelling
# (seen from below and behind), where Fig. 177 draws a flat plate with the medial pterygoid's oblique ridges
def _clothoid(n=4001):
    """The hind border's edge law: (distance from the edge as a fraction of the zone, half-thickness as a fraction of the
    face's, the zone's breadth per mm of half-thickness). The edge's quarter turn is a clothoid for its first 45 degrees,
    its curvature growing evenly from nothing, and a round for the rest (a curvature that runs on without a jump)."""
    L = np.arange(n) * (0.5 * np.pi + 0.25 * np.pi) / (n - 1)      # arc length for curvature 1 at the round: clothoid pi / 2, round pi / 4
    k = np.minimum(L / (0.5 * np.pi), 1.0)
    th = np.concatenate([[0], np.cumsum(0.5 * (k[1:] + k[:-1]) * np.diff(L))])
    x = np.concatenate([[0], np.cumsum(0.5 * (np.cos(th[1:]) + np.cos(th[:-1])) * np.diff(L))])
    y = np.concatenate([[0], np.cumsum(0.5 * (np.sin(th[1:]) + np.sin(th[:-1])) * np.diff(L))])
    r = 1.0 - x / x[-1]; g = 1.0 - y / y[-1]
    return r[::-1], g[::-1], x[-1] / y[-1]


CLOTHOID = _clothoid()          # (task C)
HIND_SPREAD = 1.0               # (repair 1) the edge's turn drawn out this many times longer (1.6 tried: a sharper tip, the strip no softer)
HIND_TIP = (0.50, -59.5, 6.0)  # (task C) the edge's tip carried this far (mm, peak, at y, over) behind the face's own border
HIND_THIN, HIND_THIN_L = 0.15, 8.0   # (T-jaw-finish) the hind border's thinning toward its edge (fraction, over mm; 0.45 over 11 before)
# where the old marks (0.3 to 0.5 mm swellings on both faces next to the edge, now gone) had held the side outline out
# (repair 2: OUT_L 64 to 80. The cheek-side blend's end, where its bend stops at once, lay at s 92, 10 mm in front of the hind
# border: on the ramus a ruled line from under the neck to mid-height. It now ends behind the border.)
LEAN = 0.060                                   # the ramus plane's lean outward per mm of height (98 to 100 mm across the angles)
ES4 = sdf.unit((-0.31, 0.0, 0.95))             # the ramus plane's run seen from above: its front a little nearer the midline
O4 = np.array([52.2, -12.0, 10.5])            # a point of the ramus plane (at the neck)
HEAD = {"centre": (51.5, -5.9, 9.5), "half": (9.0, 4.3, 3.9), "turn": -15.0}     # in the skull's socket, 1.5 to 2 mm clear of it all round
MEDIAL_SHAVE = 1.0      # (T-jaw-shape) mm off the upper face of the head's inner half (build): the socket's roof was 0.1 to 0.4 mm from it
SEPTUM_HALF = 0.36      # (T-jaw-shape) half the bony septum between the two central incisors' sockets (sockets)


# The ramus and the lower border redrawn from Gray's own plate of the jaw (Fig. 176), laid on this jaw by its tooth row and
# its condyle (a likeness fitted to the incisors' edge, the third molar and the condyle's top: they agree to 1.5 mm). Against
# the plate the outline above (traced from the skull's side view, Fig. 188) had the ramus 6 to 9 mm too far forward, leaning
# forward as it went down, its coronoid 4 to 5 mm too high, its notch 4 mm too deep and its lowest point too near the
# coronoid; and the lower border 5 mm too low under the chin and 5 to 7 mm too high toward the angle (the jaw's angle 117
# degrees between the borders' tangents where the plate's is about 105). In the plate the hind border runs almost straight
# down from the neck, a little hollow under the neck and full above the angle; the front border of the coronoid is convex,
# stands over the third molar's hind end and draws back below into the hollow behind that tooth before it turns forward as
# the oblique line; the notch's deepest point lies nearer the condyle than the coronoid.
# The skull holds the upper part of the hind border: behind the neck the tympanic plate and the root of the styloid come
# within 5 mm of z = -4 at the height of the neck, so the border stays where it was down to 6 mm under the head.
# (repair 2: the coronoid narrower, by 1 to 1.5 mm off its front border high up; the notch 2 mm shallower and its deepest
# point a little further forward; the neck broad, its front edge running down and forward into the notch as in Fig. 176
# instead of standing as a peg; the hind border one long S, a little hollow under the neck and full above the angle.)
# (task B) The side profile redrawn from Fig. 176 laid on this jaw by the two things that are fixed, the tooth row (its
# occlusal line and its length from the incisors' edge to the third molar's back) and the condyle's top. So anchored, the
# plate's own condyle stands 6.6 mm from this one's (4 behind, 5 below): its ramus is hung halfway between where the plate
# puts it and where the plate's ramus would hang from this condyle. Read from the plate in that frame (and the five head
# CTs agree): the hind border leans back to the joint (about 104 degrees to the occlusal plane), concave under the neck and
# full above the angle; the angle lies 7 to 9 mm in front of the condyle's centre and 24 to 27 below the occlusal plane,
# rounded; the ramus narrowest (33 mm) low down; its front border 33 to 36 mm in front of the condyle at 8 mm above the
# teeth, convex below the coronoid and drawing back into a hollow behind the third molar; the coronoid 2 to 3 mm lower,
# the notch shallow and wide but deeper than it was (15 to 17 mm under the line from condyle to coronoid), its deepest
# point a little nearer the condyle; the neck broad, its front edge running down and forward into the notch. The lower
# border rises gently to the angle from under the first molar, with a faint hollow in front of the angle (antegonial).
# The previous outline (task A) is kept as FRONT_A / HIND_A: everything drawn on it is carried to this one (regrid).
FRONT_A = [(37.3, -56.6), (36.4, -53.5), (36.5, -49.5), (37.2, -45.0), (38.3, -40.0), (39.7, -34.8), (41.0, -29.6), (42.0, -24.6),
           (42.4, -19.6), (41.9, -14.8), (40.8, -10.8), (39.6, -7.8), (38.6, -6.3), (37.6, -6.9), (36.6, -8.9), (34.9, -11.9),
           (32.3, -14.3), (28.8, -15.9), (25.0, -16.3), (21.8, -15.6), (19.0, -13.6), (16.6, -10.6), (14.6, -7.4), (12.6, -4.6)]
HIND_A = [(5.5, -6.0), (5.0, -9.2), (4.6, -13.8), (3.6, -19.0), (2.4, -24.5), (1.4, -30.5), (0.8, -37.0), (0.6, -44.0), (0.8, -51.0),
          (1.3, -57.5), (2.2, -63.5), (3.5, -69.0), (5.8, -73.8), (10.0, -77.3)]
BORDER_Y_A = [-88.8, -89.4, -89.7, -88.5, -86.3, -83.7, -81.0, -80.8, -83.4, -81.6, -79.0]
# (repair 1) The side profile traced from the plate's engraved line itself (the hand trace snapped to the ink, stair steps
# eased out), not drawn by eye: in that frame the hind border is a long S (full under the neck, a shallow hollow at mid
# height, full and a little turned out at the angle); the coronoid a broad triangle, its front edge convex and its hind
# edge hollow, running into a notch deepest nearer the condyle; the front border stands over the third molar's hind end
# and meets the margin behind that tooth. Near the joint the plate is carried by its condyle's offset from this one
# (4.8 mm forward, 5.6 up), fading over 12 to 34 mm along the line from the condyle's top, so the head and neck stay.
# (T-jaw-shape) The side outline laid on Fig. 176 again, now registered on the three points a side view of the jaw alone fixes
# (condyle top, gonion, pogonion; 4.7 px/mm of the 600 px plate) and traced from the plate's ink with its lettering taken out
# (the words "Mandibular Notch" had been read as bone: the notch came out 6 mm too deep and narrow). Against that plate the
# coronoid stood 5.7 mm too far back and 3 mm too low, a finger 6 mm broad 5 mm under its tip where the plate draws a
# triangle 7.4 mm broad; the notch's deepest point 1.7 mm too low and 2.5 mm too far back, its floor a narrow U where the plate
# draws a wide shallow sigmoid; the hind border's middle 2 to 3 mm too far back (the plate hollows it) and its lower end and
# the angle's lower border 1 to 4 mm too low: an angle of 101 degrees by the tangents, a square corner. Now the front border
# runs forward and up into a broad coronoid whose tip stands 5.6 mm under the condyle's top; its hind edge falls evenly into
# a wide notch whose floor is lowest a third of the way from the condyle; the hind border is hollow at mid height and the
# angle opens (to 104 to 108 degrees) and rounds. The joint head, its neck's upper part and the tooth row stay.
FRONT = [(42.4, -53.4), (41.4, -50.6), (41.4, -46.8), (41.8, -42.6), (42.6, -38.6), (43.8, -34.6), (45.4, -30.6), (46.9, -26.6),
         (47.3, -22.4), (46.9, -18.2), (46.4, -14.0), (45.9, -10.4), (43.4, -7.2), (41.0, -8.0), (39.2, -10.8), (37.0, -14.0),
         (34.2, -17.2), (31.6, -19.8), (27.4, -22.6), (23.2, -21.8), (20.6, -20.0), (18.4, -17.8), (15.8, -12.6), (12.6, -4.6)]
HIND = [(5.5, -6.0), (5.0, -9.2), (4.6, -13.8), (5.4, -18.6), (7.6, -24.3), (9.6, -30.3), (11.2, -36.1), (11.6, -41.9), (11.2, -47.9),
        (9.9, -53.7), (9.8, -59.4), (10.4, -65.2), (11.5, -71.0), (14.8, -74.1)]
BORDER_Y = [-86.2, -86.2, -85.8, -84.7, -82.2, -79.3, -76.9, -76.6, -75.6, -75.0, -73.4]      # the lower border's height at M2.B's points (the plate's)
REGRID_PAIRS = (list(zip(FRONT_A, FRONT)) + list(zip(HIND_A, HIND))
                + [((z, a), (z, b)) for z, a, b in ((16.5, -81.6, -75.0), (22.0, -83.4, -75.6), (31.0, -80.8, -76.6), (42.0, -81.0, -76.9),
                                                     (54.0, -83.7, -79.3), (64.5, -86.3, -82.2))]
                + [((p[0], p[1]), (p[0], p[1])) for p in ((9.5, -5.9), (11.5, -5.0), (11.0, -1.5), (55.0, -60.0), (58.0, -72.0), (74.0, -80.0))])
_REGRID = {}


def regrid(z, y):
    """A point drawn on task A's outline (side view z, y) carried to this outline."""
    if "f" not in _REGRID:
        from scipy.interpolate import RBFInterpolator
        A = np.array([a for a, b in REGRID_PAIRS], float); B = np.array([b for a, b in REGRID_PAIRS], float)
        _REGRID["f"] = RBFInterpolator(A, B - A, kernel="thin_plate_spline", smoothing=0.5)
    P = np.column_stack([np.atleast_1d(np.asarray(z, float)), np.atleast_1d(np.asarray(y, float))])
    Q = P + _REGRID["f"](P)
    return (float(Q[0, 0]), float(Q[0, 1])) if np.ndim(z) == 0 else (Q[:, 0], Q[:, 1])


WARP_PAIRS = [((4.9, -9.2), (4.9, -9.2)), ((5.5, -6.0), (5.5, -6.0)), ((9.5, -5.9), (9.5, -5.9)), ((11.5, -5.0), (11.5, -5.0)), ((11.0, -1.5), (11.0, -1.5)),
              ((6.5, -15.7), (4.4, -15.2)), ((8.4, -21.4), (3.9, -21.2)), ((9.6, -26.2), (3.5, -26.2)), ((11.6, -31.2), (3.1, -31.2)),
              ((12.2, -37.4), (2.8, -37.6)), ((11.6, -45.0), (2.5, -45.0)), ((11.1, -51.5), (2.4, -51.5)), ((11.0, -57.5), (2.6, -57.8)),
              ((12.6, -63.0), (3.2, -64.0)), ((16.4, -67.6), (5.6, -73.0)), ((21.9, -71.0), (11.5, -77.8)), ((36.4, -77.1), (33.0, -81.0)),
              ((48.5, -58.0), (37.3, -56.6)), ((44.8, -47.3), (37.0, -46.5)), ((46.1, -35.4), (39.6, -35.0)), ((47.2, -26.5), (41.7, -26.4)),
              ((47.9, -18.3), (42.8, -18.0)), ((46.9, -12.0), (42.5, -11.5)), ((43.1, -3.8), (40.3, -7.6)), ((40.7, -2.0), (38.8, -6.3)),
              ((37.4, -6.0), (36.0, -8.9)), ((35.7, -10.3), (33.9, -12.1)), ((32.9, -15.1), (31.0, -15.2)), ((30.0, -19.9), (27.6, -17.0)),
              ((25.8, -21.4), (23.6, -17.9)), ((21.7, -19.7), (20.2, -17.4)), ((17.9, -15.9), (17.0, -15.2)), ((15.1, -11.4), (14.6, -11.9)),
              ((12.9, -7.1), (12.8, -8.0)), ((55.0, -60.0), (55.0, -60.0)), ((58.0, -72.0), (58.0, -72.5)), ((50.0, -66.0), (48.0, -66.5)),
              ((28.0, -45.0), (21.5, -44.0)), ((25.0, -30.0), (19.0, -28.5)), ((30.0, -60.0), (22.0, -60.5)), ((20.0, -55.0), (11.5, -56.0))]
_WARP = {}


def warp(z, y):
    """A point drawn in the old outline's frame (side view) moved with the outline to the new one."""
    if "f" not in _WARP:
        from scipy.interpolate import RBFInterpolator
        A = np.array([a for a, b in WARP_PAIRS], float); B = np.array([b for a, b in WARP_PAIRS], float)
        _WARP["f"] = RBFInterpolator(A, B - A, kernel="thin_plate_spline", smoothing=0.5)
    P = np.column_stack([np.atleast_1d(np.asarray(z, float)), np.atleast_1d(np.asarray(y, float))])
    Q = P + _WARP["f"](P)
    Q = np.column_stack(regrid(Q[:, 0], Q[:, 1]))
    return (float(Q[0, 0]), float(Q[0, 1])) if np.ndim(z) == 0 else (Q[:, 0], Q[:, 1])


def use():
    """mandible2's traced lines, with the ramus plane leaned so that the neck stands under the head's outer half."""
    M2.use()
    ET = np.array([LEAN, 1.0, 0.0])
    MB.ES = ES4
    MB.O, MB.ET = O4, sdf.unit(ET - (ET @ MB.ES) * MB.ES)


def sheet4():
    """mandible3's sheet line, eased behind the angle (repair 2). Its spline bends by steps at each traced point and runs on
    straight behind the last; 6 mm out from it, on the ramus, those steps showed as a ruled line down the cheek side at
    z 15 from the neck to the angle. Behind z 34 the line is smoothed over 2.75 mm (more moved the joint head's lower edge) (in front it is as it was)."""
    B = np.array(M2.B, float)[:, [0, 2]]
    e = sdf.unit(B[-1] - B[-3])
    P = np.concatenate([B[:0:-1] * np.array([-1.0, 1.0]), B, B[-1] + np.outer([7.0, 14.0, 22.0, 30.0], e)])
    Q = sdf.spline(P, 0.25)
    Qs = np.column_stack([ndimage.gaussian_filter1d(Q[:, 0], 11.0, mode="nearest"), ndimage.gaussian_filter1d(Q[:, 1], 11.0, mode="nearest")])
    w = smoothstep((34.0 - Q[:, 1]) / 10.0) * (Q[:, 0] > 0)
    Q = Q * (1 - w[:, None]) + Qs * w[:, None]
    k0 = int(np.argmin(np.abs(Q[:, 0]) + 1e3 * (np.abs(Q[:, 1] - B[0, 1]) > 3)))
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))])
    keep = (d > d[k0] - 16.0) & (d < d[-1] - 8.0)
    return Sheet(Q[keep], d[k0] - d[keep][0])


def smoothstep(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def easeout2(t):
    """0 to 1, flat at both ends, and with no bend left at its far end (a smoothstep's bend stops there at once)."""
    t = np.clip(t, 0, 1)
    return t * t * (6 - 8 * t + 3 * t * t)


def evenstep(t):
    """0 to 1 with the least greatest bend for its length: two parabolas (a smoothstep bends half as much again at its
    quarter points, which in a plan view of the jaw read as an elbow)."""
    t = np.clip(t, 0, 1)
    return np.where(t < 0.5, 2 * t * t, 1 - 2 * (1 - t) ** 2)


def ramus3(z, y, out=0.0):
    use()
    return np.array([MB.on_ramus(a, b, out) for a, b in zip(np.atleast_1d(z), np.atleast_1d(y))])


def stroke(M, pts, r, h, wob=0.3, seed=0, mirror=False):
    """A line drawn on the map (s, y) the way a muscle's mark is: it wanders sideways by up to `wob` mm (two slow waves of
    their own phase), and its width r and height h change along it (given at its points, eased between). 1 * h on it."""
    from scipy.spatial import cKDTree
    pts = np.asarray(pts, float); r = np.broadcast_to(np.asarray(r, float), (len(pts),)); h = np.broadcast_to(np.asarray(h, float), (len(pts),))
    P = sdf.spline(pts, 0.25) if len(pts) > 2 else np.vstack([pts[0] + (pts[1] - pts[0]) * t for t in np.linspace(0, 1, max(int(np.linalg.norm(pts[1] - pts[0]) / 0.25), 2))])
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]); Lt = max(d[-1], 1e-6)
    dk = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]); dk = dk / max(dk[-1], 1e-6) * Lt
    ph = np.random.default_rng(seed).uniform(0, 2 * np.pi, 2)
    tg = np.gradient(P, axis=0); tg /= np.maximum(np.linalg.norm(tg, axis=1, keepdims=True), 1e-9); nrm = np.column_stack([-tg[:, 1], tg[:, 0]])
    P = P + nrm * (wob * (0.6 * np.sin(2 * np.pi * d / 9.0 + ph[0]) + 0.4 * np.sin(2 * np.pi * d / 4.3 + ph[1])) * np.sin(np.pi * d / Lt))[:, None]
    rr, hh = np.interp(d, dk, r), np.interp(d, dk, h)
    U = np.abs(M.U) if mirror else M.U
    dist, j = cKDTree(P).query(np.column_stack([U.ravel(), M.V.ravel()]), distance_upper_bound=4.0 * float(r.max()))
    ok = np.isfinite(dist); out = np.zeros(U.size)
    out[ok] = hh[j[ok]] * np.exp(-(dist[ok] / rr[j[ok]]) ** 2)
    return out.reshape(U.shape)


def near_abs(M, pts, r):
    """near_line on both halves of the map at once (s read as its distance from the midline)."""
    pts = np.asarray(pts, float); d = np.full(M.U.shape, 1e9); U = np.abs(M.U)
    for a, b in zip(pts[:-1], pts[1:]):
        e = b - a; L2 = max(float(e @ e), 1e-9)
        t = np.clip(((U - a[0]) * e[0] + (M.V - a[1]) * e[1]) / L2, 0, 1)
        d = np.minimum(d, np.hypot(U - a[0] - t * e[0], M.V - a[1] - t * e[1]))
    return np.exp(-(d / r) ** 2)


RIM_FRONT = 0.65
SOCKET_GAP = 0.28    # (T-lower-sockets) the space round a lower root (mm; the upper arch's is 0.30), now cut square below the lip
RIM_THIN, RIM_SOFT = 0.2, 0.4   # (T-lower-sockets) the most the margin's smoothing may take off a face; the last cut's softness at the lip
SOCKET_WEAR, SOCKET_WEAR_FACE = 0.02, 0.12   # (T-lower-sockets) the most the grain may wear a socket's wall, and the bone's outer faces near the teeth (whole)
LIFT_W, LIFT_S = 41, 12.0         # (Repair 2) the cheek face's lift over the roots: one long low swelling along the row
WALL_MOLAR = 0.35                # (Repairs 1-2) the cheek wall's extra thickness over the first and second molars' roots (1.3 elsewhere); there the wall at the margin is 0.6 mm, 0.8 elsewhere

def crest_line(S):
    """The alveolar margin's height over s (|s|, mm along the sheet): scalloped as a jaw's is. Over the middle of each socket the
    margin dips (to the crest of the tooth's own frame), between two teeth it rises into the septum's top, most between the
    front teeth (whose necks curve up most toward each other), least between the molars. A few tenths of a millimetre of
    unevenness besides, so that no two arches of the scallop are alike."""
    fr = [f for f in teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False) if f["side"] == "L"]
    sc = np.array([float(S.sn(f["position_mm"][0], f["position_mm"][2])[0]) for f in fr])
    yc = np.array([float(f["position_mm"][1]) for f in fr])
    rise = [0.45, 0.45, 0.35, 0.2, 0.24, 0.22, 0.2, 0.16]   # (Repair 2: the front septa rise to points, the rim rounded more below)                # at the midline, then between tooth k and k + 1 (more and the narrow
                                                                     # septa between the front teeth stood up as a row of spikes)
    wob = np.random.default_rng(1918).uniform(-0.1, 0.1, 2 * len(fr) + 2)
    ss, yy = [0.0], [yc[0] + rise[0] + wob[0]]
    nb = [0.5 * (yc[max(k - 1, 0)] + yc[min(k + 1, len(fr) - 1)]) for k in range(len(fr))]
    up = [float(np.clip(0.5 * (nb[k] - yc[k]), 0.0, 1.0)) for k in range(len(fr))]   # (the canine's crest lies 2 mm under its neighbours':
    for k in range(len(fr)):                                                      # the margin over it is raised half way, still under its neck)
        ss.append(sc[k] + wob[2 * k + 1] * 0.8); yy.append(up[k] + yc[k] - 0.05 + 0.5 * wob[2 * k + 1])   # (about level: Gray's crest is a gentle wave, not a row of notches)
        if k + 1 < len(fr):
            m = 0.5 * (sc[k] + sc[k + 1]) + 0.6 * wob[2 * k + 2]
            ss.append(m); yy.append(max(yc[k], yc[k + 1]) + rise[k + 1] + wob[2 * k + 2])
    ss += [sc[-1] + 5.0, sc[-1] + 8.0, sc[-1] + 10.6, sc[-1] + 14.0, sc[-1] + 20.0]; yy += [-57.0, -56.6, -55.6, -54.3, -52.5]   # behind the last molar the
    # retromolar triangle rises gently into the ramus's front border (a level shelf there ended in a square corner)
    from scipy.interpolate import PchipInterpolator
    f = PchipInterpolator(np.array(ss), np.array(yy), extrapolate=True)
    return lambda s: f(np.clip(np.abs(s), 0.0, ss[-1]))


def maps(S, log=print):
    """Everything drawn on the unrolled sheet: the outline, the two faces, the rim's roundness; and the lines
    other steps need (the lower border and the tooth-bearing margin as heights over s)."""
    use()
    M = relief.Map(-16.0, 114.0, -101.0, 4.0, 0.5)
    sy = lambda P: np.column_stack([S.sn(P[:, 0], P[:, 2])[0], P[:, 1]])
    # the outline, unrolled: tooth-bearing margin, front border of the ramus, coronoid, notch, neck, hind border, angle, lower border
    T = np.array(M2.T, float)[:8]; B = np.array(M2.B, float); B[:, 1] = BORDER_Y
    Fr, Hi = np.array(FRONT, float), np.array(HIND, float)
    front = sy(ramus3(Fr[:, 0], Fr[:, 1])); hind = sy(ramus3(Hi[:, 0], Hi[:, 1]))
    top = sy(T)
    low = sy(B)[:10][::-1]                                          # from under the ramus forward to the chin
    sg = float(sy(ramus3(*regrid(34.0, -79.0)))[0, 0])                       # the facial artery crosses the border in front of the masseter
    low[:, 1] += 0.9 * np.exp(-((low[:, 0] - sg) / 5.0) ** 2)       # (a shallow notch in it: "groove for external maxillary artery")
    # Where the body's upper border meets the ramus there is no notch: "the anterior border is thin above, thicker below, and
    # continuous with the oblique line" (Gray 1918, p. 174); the rim turns up into the front border in a hollow curve.
    yrim = crest_line(S)
    st = np.arange(0.0, 57.01, 0.5)
    rim = np.column_stack([st, yrim(st) + 0.5])                     # (0.5 mm over the crest: the rim's rounding takes it back down)
    # (the front border's foot sweeps forward and down into the margin behind the third molar: a broad hollow, no corner)
    poly = np.concatenate([rim[::-1] * np.array([-1.0, 1.0]), rim, front, hind, low, low[::-1][1:] * np.array([-1.0, 1.0])])   # (mirrored across the midline so that no rim falls on it)
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
    zy = lambda z, y: tuple(sy(ramus3(*warp(z, y)))[0])             # (a point drawn on the old outline, carried to the new: its s and y)
    zs = lambda z, y: zy(z, y)[0]
    TH = [  # (z, y, thickness) on the side view
        (8.5, -12, 6.4), (9.5, -20, 6.2), (11.5, -30, 5.8), (14.5, -40, 5.1), (14.0, -50, 4.6), (13.0, -60, 4.4),     # hind border (repair 1: thinning
        (16, -65, 4.5), (23, -69.5, 4.3),                                                                    # toward the angle: from behind it read as a rod)
        (34, -74.5, 5.0), (44, -78.5, 6.6),                                   # angle and lower border
        (30, -27, 2.6), (28, -38, 4.0), (28, -50, 3.9), (30, -60, 3.8), (21, -45, 3.8), (36, -40, 3.6), (36, -28, 2.8), (21, -30, 3.6),
        (45, -20, 3.2), (44.5, -30, 3.6), (43.0, -40, 4.2), (43.5, -48, 5.0),                                   # front border
        (41, -10, 2.2), (39.5, -7, 1.6), (26, -23, 2.6), (20, -21, 3.4), (31, -21, 2.2),                        # coronoid, notch
        (9.5, -9, 6.6), (12, -14, 6.4), (14.5, -9.5, 5.8), (17.0, -13.0, 4.6), (20.0, -15.5, 3.4), (13.0, -20.0, 6.0)]   # (the neck's front passes into the notch without a groove)                                                                         # neck
    # (task B) the ramus is narrower behind than it was, and the hind border's thickness fell off within a few mm into the
    # thin middle: from behind it read as a rod with a crease along its front. The fall is spread over 8 to 10 mm (points on
    # this outline, 5 to 6 mm in front of the hind border).
    zn = lambda z, y: tuple(sy(ramus3(z, y))[0])
    TH_B = [(12.0, -22.0, 5.2), (15.6, -32.0, 4.6), (17.8, -42.0, 4.6), (17.0, -52.0, 4.5), (16.6, -61.0, 4.2), (18.2, -68.0, 3.9)]   # (T-jaw-shape: carried with the hollowed hind border)
    th = M.thin_plate(np.array([(*zy(z, y), t) for z, y, t in TH] + [(*zn(z, y), t) for z, y, t in TH_B]), weight=20.0, tension=0.05)
    th = np.clip(th, 2.0, 8.0)
    # (repair 1) Toward its edge the hind border thins (to 62 % at the edge, over 9 mm), below the neck: at an even thickness to
    # the edge, rounded, it read from behind as a rod with a crease along its front. Now its section is a low swelling a few
    # mm in from a blunter edge, and lower down it thins toward the angle.
    from scipy.spatial import cKDTree as _KD
    hl = sdf.spline(hind, 0.25)
    dh = _KD(hl).query(np.column_stack([np.abs(M.U).ravel(), M.V.ravel()]))[0].reshape(M.U.shape)
    th = th * (1 - HIND_THIN * (1 - easeout2(dh / HIND_THIN_L)) * smoothstep((-18.0 - M.V) / 10.0))   # (repair 2: 55 % at the edge, over 11 mm;
    # task C: eased so that its bend, too, fades to nothing where the thinning ends)
    # (T-jaw-finish: at 55 % the two faces ran in as straight bevels from 9 mm in to a 1.2 mm round, 2.6 mm thick at 1 mm
    # in: from behind and from behind-outside a flat bright strip from the neck to the angle. Gray, p. 174: the posterior
    # border "thick, smooth, rounded". Now the border keeps most of its thickness and is turned by the clothoid round.)
    # (task C) where the hind border's rounding met the faces, its curvature fell at once from that of a 1.2 to 1.4 mm round
    # to none: from three-quarter behind the border read as a round column beside a flat plate, a line between them. Along
    # the hind border, from under the neck round the angle, the rim is drawn instead by a clothoid (Ribbon4): each face turns
    # in to the edge with its bend growing evenly from nothing, so the curvature runs on from the masseter's face round the
    # border to the inner face.
    hind_w = (1 - smoothstep((dh - 3.0) / 6.0)) * smoothstep((-16.0 - M.V) / 4.0)
    g = lambda z, y, r: gauss(M, zy(z, y), (r, r))
    # Seen from in front the jaw's side is no upright ruled line (the owner, 14 November: "it shouldn't be perfectly straight in
    # sides"). An earlier build turned the angle 0.8 mm out and hollowed the ramus 0.8 above it, which together undid the
    # plane's own lean: 20 mm of the side stood exactly upright. Now the side keeps the plane's lean all the way down (in by
    # 1 mm for every 8 of height, 121 mm across the joint heads to 98 across the angles), a little hollow under the neck and
    # a little full over the masseter's ridges, and turns in to the lower border round the angle.
    mid = mid - 0.5 * g(40.0, -8.0, 9.0)                                     # the coronoid tip held in a little (curved out, it stood out from above as a spur; T-jaw-shape: 1.0 to 0.5, the broader tip 2.6 mm under the skull's infratemporal surface)
    mid = mid - 2.0 * gauss(M, zn(41.0, -22.0), (5.0, 10.0)) + 0.5 * gauss(M, zn(32.0, -20.0), (5.0, 9.0))                   # (repair 1: the coronoid's base held in a little: with the front border
                                                                             # traced back to the plate's, it stood out of the plan view's line as a corner)
    mid = mid - 0.15 * g(17.0, -38.0, 12.0) + 0.6 * g(11.0, -24.0, 9.0) + 0.3 * g(17.0, -55.0, 9.0)   # (task B: gentler; the hind border read as a rod)
    orr, irr = mid + th / 2, mid - th / 2
    # The ramus's markings, drawn on the new outline (side-view z, y): every one a stroke that wanders a little, swells and
    # fades along its length, none a ruled line of even strength.
    zr = lambda z, y: tuple(sy(ramus3(*regrid(z, y)))[0])       # (drawn on task A's outline, carried to this one)
    st = lambda pts, r, h, wob=0.3, seed=0: stroke(M, [zr(z, y) for z, y in pts], r, h, wob, seed)
    gr = lambda z, y, r: gauss(M, zr(z, y), (r, r))
    ev = 1.7 * gr(8.0, -71.0, 13.0) + 0.4 * gr(16.0, -76.0, 10.0)                   # the angle turned outward (Gray: "inverted or everted"), broadly
    orr, irr = orr + ev, irr + ev                                                   # (repair 1: it was added to mid after the faces were taken from it, so did nothing)
    # outside: "flat and marked by oblique ridges to the Masseter", rough at the angle (Fig. 176)
    # (Fig. 176: a few short, faint, broken oblique marks low at the angle only, each fading out at both ends; none in the
    # middle of the ramus, nothing parallel or evenly spaced. A raked row of welts read as artificial.)
    # (task C) The body's cheek-side face is fitted through samples of this face (below); they are taken from the face with
    # task B's marks on it, so that redrawing the marks moves nothing but the marks (the fit spreads any change of a sample
    # over the whole body).
    orr_b = orr.copy()
    for k, (pts, r, h) in enumerate((([(12.5, -61.5), (9.5, -65.8), (6.5, -69.5)], [0.9, 1.2, 0.9], [0.0, 0.35, 0.0]),
                                     ([(5.6, -71.2), (4.2, -73.4)], [0.8, 0.7], [0.18, 0.0]),
                                     ([(19.5, -69.5), (15.8, -73.6), (12.6, -76.2)], [0.9, 1.1, 0.8], [0.0, 0.28, 0.0]),
                                     ([(27.5, -73.0), (25.2, -75.4), (23.4, -77.4)], [0.8, 0.9, 0.7], [0.0, 0.2, 0.0]))):
        orr_b = orr_b + st(pts, r, h, 0.45, 11 + k)
    for k, (pts, r, h) in enumerate((([(22.0, -56.0), (18.5, -62.0), (15.5, -67.0)], [0.8, 1.0, 0.8], [0.0, 0.3, 0.0]),
                                     ([(28.0, -62.0), (25.0, -68.5), (22.5, -72.5)], [0.8, 1.1, 0.8], [0.0, 0.36, 0.05]),
                                     ([(17.0, -50.0), (15.6, -53.0), (14.8, -55.5)], [0.7, 0.8, 0.7], [0.0, 0.2, 0.0]),
                                     ([(33.5, -68.0), (31.8, -71.0), (30.5, -73.5)], [0.8, 0.9, 0.8], [0.0, 0.25, 0.0]))):
        orr_b = orr_b + st(pts, r, h, 0.5, 21 + k)
    rk = np.random.default_rng(1919)
    for _ in range(7):
        z0, y0 = rk.uniform(4.0, 22.0), rk.uniform(-79.0, -67.0)
        orr_b = orr_b + rk.uniform(0.08, 0.18) * gauss(M, zr(z0, y0), (rk.uniform(0.6, 1.0), rk.uniform(0.6, 1.0)))
        rk.uniform(4.0, 22.0), rk.uniform(-79.0, -64.0), rk.uniform(0.08, 0.18), rk.uniform(0.6, 1.0), rk.uniform(0.6, 1.0)
    # (task C) The masseter's marks: up close they read as knobbly bumps (three-point strokes 0.2 to 0.36 mm high, each a short
    # spindle, and seven round dabs besides). Fig. 176 draws short oblique strokes, uneven in length, running down and back
    # on the lower half of the field: so long low ridges 0.10 to 0.18 mm high, each rising and fading along its length at
    # its own place, and no dabs. (The medial pterygoid's on the inside likewise: low, uneven, strongest near the border and
    # fading upward.)
    # (T-jaw-finish, repair 1) Drawn as short strokes of several knots each, rising and falling twice and wandering 0.5 mm,
    # they read as clusters of round lumps 3 to 5 mm across. Fig. 176 and p. 174: the lower hind part of the outer face is
    # marked by oblique ridges for the masseter. Now four ridges, each one long narrow crest running down and back toward
    # the angle (10 to 17 mm long, 1.2 to 1.4 mm wide), rising from nothing and fading to nothing once along its length
    # (no second peak), barely bent, of unequal length, spacing, slant and height; on each a fine unevenness of its crest
    # (12 %, knots 1 mm apart) and the angle's grain (ZONES) for its roughness.
    rq = np.random.default_rng(176)
    for k, (a0, a1, bend, r, h) in enumerate((((16.0, -56.0), (6.5, -70.5), 0.6, 0.65, 0.34),
                                              ((23.5, -61.5), (14.0, -74.5), -0.5, 0.70, 0.40),
                                              ((29.0, -67.5), (22.5, -76.0), 0.4, 0.62, 0.26),
                                              ((33.5, -70.3), (29.8, -75.8), -0.3, 0.60, 0.20))):
        a0, a1 = np.array(a0), np.array(a1); n = max(int(np.linalg.norm(a1 - a0) / 1.0), 6)
        t = np.linspace(0.0, 1.0, n + 1); e = a1 - a0; nn = np.array([-e[1], e[0]]) / np.linalg.norm(e)
        pts = a0 + np.outer(t, e) + np.outer(bend * np.sin(np.pi * t), nn)
        prof = np.sin(np.pi * t) ** 1.4 * (1.0 + 0.12 * rq.uniform(-1, 1, n + 1)) * (0.9 + 0.2 * t)    # (a little fuller toward the angle)
        orr = orr + st([tuple(p) for p in pts], np.full(n + 1, r), h * prof, 0.12, 11 + k)
    # inside: the medial pterygoid's marks at the angle; the ridge from the neck down to the lingula, the temporal crest
    # (T-jaw-finish) laid on after the smoothing (below), so that they show: low (to 0.25 to 0.4 mm), each fading out at both
    # ends and a little weaker somewhere along its length, running up and back from near the lower border at slants of their
    # own, unequally spaced; the shortest at the angle itself
    for k, (pts, r, h) in enumerate((([(15.0, -56.5), (13.0, -60.0), (10.6, -63.8), (8.4, -67.6), (6.6, -70.6)], [0.8, 1.0, 1.1, 1.0, 0.8], [0.0, 0.24, 0.36, 0.28, 0.0]),
                                     ([(22.0, -59.4), (19.6, -62.6), (17.2, -66.4), (15.0, -70.0), (13.8, -72.4)], [0.8, 1.0, 1.1, 1.1, 0.8], [0.0, 0.30, 0.20, 0.38, 0.0]),
                                     ([(27.4, -64.2), (25.2, -67.6), (22.2, -71.0), (20.4, -74.2)], [0.8, 1.1, 1.1, 0.8], [0.0, 0.34, 0.27, 0.0]),
                                     ([(32.4, -69.6), (30.4, -71.8), (28.0, -74.6)], [0.8, 1.0, 0.8], [0.0, 0.22, 0.0]),
                                     ([(11.0, -70.8), (9.4, -73.0), (8.2, -74.8)], [0.8, 1.0, 0.8], [0.0, 0.28, 0.0]))):
        ptg = st(pts, r, h, 0.5, 31 + k) + (ptg if k else 0.0)          # (laid on below, after the face at the angle is smoothed)
    irr = irr - st([(9.2, -15.5), (12.8, -22.5), (17.5, -29.0), (21.8, -34.6)], [2.6, 2.6, 2.2, 1.6], [0.9, 1.0, 0.7, 0.35], 0.3, 41)     # neck to lingula
    irr = irr - st([(37.5, -10.0), (38.2, -21.0), (36.8, -32.0), (35.0, -42.0), (34.0, -50.0)], [2.0, 2.2, 2.4, 2.4, 2.2], [0.7, 1.0, 1.0, 0.8, 0.5], 0.25, 42)   # temporal crest
    irr = irr + 0.8 * gauss(M, zn(16.0, -66.0), (8.0, 7.0))                        # (repair 2) the medial pterygoid's field at the angle a shallow hollow, not a swelling
    irr = irr - 0.7 * gr(24.0, -46.0, 5.0)                                          # bone over the canal where it enters
    irr = irr + st([(23.0, -45.6), (25.6, -49.6), (29.0, -54.0), (33.0, -58.4), (37.0, -62.0)], [1.0, 1.05, 1.0, 0.9, 0.8], [0.5, 0.45, 0.35, 0.2, 0.0], 0.2, 43)   # (repair 1: a fine line from the foramen's lower edge)   # mylohyoid groove (a shallow furrow)

    # the cheek-side face: the body's, passing into the ramus's (which reaches forward highest up: the oblique line)
    gs, gy = np.meshgrid(np.arange(74.0, 111.0, 6.0), np.arange(-92.0, 1.0, 6.0), indexing="ij")
    out_pts = np.vstack([out_pts, np.column_stack([gs.ravel(), gy.ravel(), M.sample(orr_b, gs.ravel(), gy.ravel())])])
    sym = lambda P: np.vstack([P, P * np.array([-1.0, 1.0, 1.0])])
    ob = ndimage.gaussian_filter(M.thin_plate(sym(out_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")     # (1.5 mm: no pimple at a control point)
    ib = ndimage.gaussian_filter(M.thin_plate(sym(in_pts), weight=20.0, tension=0.02), 3.0, mode="nearest")
    # (T-rows-refit) the tongue-side face smoothed up and down behind the canines: seen from below a long sharp line ran along it
    wV = smoothstep((np.abs(M.U) - 14.0) / 10.0)
    ib = ib * (1 - wV) + ndimage.gaussian_filter1d(ib, 6.0, axis=1, mode="nearest") * wV
    s_ = np.abs(M.U)
    H2 = lambda c, r: np.exp(-(((s_ - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2))
    yc_ = float(yb(0.0))
    myl = [(63.0, float(yt(63.0)) - 5.0), (52.0, float(yt(52.0)) - 7.5), (40.0, float(yt(40.0)) - 11.0), (28.0, float(yb(28.0)) + 12.0), (16.0, float(yb(16.0)) + 9.5), (6.0, yc_ + 8.5)]
    # mylohyoid line: strong behind, near the margin under the last molar, fading as it runs down and forward to the symphysis;
    # its course wanders a little and its crest is not of one height (a straight sharp ridge of even strength read as a seam)
    ib = ib - stroke(M, myl, [1.5, 1.7, 1.9, 2.1, 2.3, 2.4], [1.25, 1.15, 0.85, 0.5, 0.22, 0.06], 0.45, 61, mirror=True)
    ib = ib + 1.4 * H2((45.0, float(yb(45.0)) + 8.0), (11.0, 4.6))                             # the hollow for the submandibular gland, under its hind part
    ib = ib + 0.8 * H2((19.0, float(yt(19.0)) - 9.0), (8.5, 4.4))                              # the hollow for the sublingual gland, above its front part
    # The mental spines: drawn on the tongue-side face, not stuck on. The upper pair (genioglossi) two low pointed eminences
    # 3 to 4 mm apart, joined at their roots; the lower pair (geniohyoidei) smaller and run together into a short median
    # ridge; all of them rough, a scatter of small knots of bone over each.
    d2 = lambda c, r: np.sqrt(((s_ - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2)
    # (each under 1.5 mm and run into the bone round it: taller, pointed ones read as pegs on a mound)
    # (two small pointed tubercles above, a little unequal, their sides sloping out into the bone; below them a low rough
    # median ridge with a faint pair; nothing square: each a cone on a broad low skirt, the two sides drawn apart)
    # (T-jaw-finish) The cones, their skirts, the median ridge and sixteen knots clipped to where the cones stood made one
    # flat-topped patch with a squared edge (5 by 6 mm, 0.3 to 0.5 mm proud, its rim a ring of knots): seen from behind a
    # block on the symphysis's hind face. Now (Fig. 177; p. 173: "two pairs of laminated tubercles, the mental spines"):
    # an upper pair (genioglossi) and a lower, smaller pair (geniohyoidei) a little closer together, each a low rounded bump
    # (no cone tip, no skirt, no plateau between them), on a face otherwise smooth; their roughness is the grain's (ZONES).
    dS = lambda c, r: ((s_ - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2       # (both sides at once: a pair across the midline)
    # (T-jaw-shape) Drawn on the map at its 0.5 mm grid, the four bumps came out as two flat squarish pads (seen from behind
    # and below). The spines are now made in the solid (chin_marks, after the halves are joined, each its own); here only
    # the low swelling of the hind face round them.
    sp = 0.14 * np.exp(-dS((0.0, yc_ + 8.8), (3.6, 4.6)))                       # the hind face swells a little round them
    ib = ib - sp
    q = np.clip((M.V - yb(M.U)) / np.maximum(yt(M.U) - yb(M.U), 1.0), 0, 1.4)
    s = np.abs(M.U)
    w_out = evenstep((s - OUT_S0 - 12.0 * (1 - np.minimum(q, 1.0))) / OUT_L)   # (long: the cheek side widens into the ramus with no elbow)
    w_out = w_out + (1 - w_out) * smoothstep((M.V + 28.0) / 14.0)              # (repair 2: the ramus's own face from under the neck up, as before)
    outer = ob * (1 - w_out) + orr * w_out
    # the chin and the oblique line (Fig. 176); all of it before the roots' clearance is taken below
    yc = float(yb(0.0))
    G2 = lambda c, r: np.exp(-(((s - c[0]) / r[0]) ** 2 + ((M.V - c[1]) / r[1]) ** 2))
    # mental protuberance: a triangle, its apex up toward the incisors, its base the lower border between the two tubercles
    hw = 11.0 * np.clip(1.0 - (M.V - (yc + 2.5)) / 14.0, 0.0, 1.0) + 0.5
    tri = ndimage.gaussian_filter(smoothstep((hw - s) / 3.5) * smoothstep((M.V - (yc + 1.0)) / 5.0) * smoothstep((yc + 18.0 - M.V) / 5.0), 2.4)
    outer = outer + 2.4 * tri                       # (T-arch-lower: 1.4 to 2.4, and the fill above 3.6 to 3.0: with the incisors 1.6 mm further forward the chin stood behind Fig. 176)
    outer = outer + 1.0 * G2((9.8, yc + 5.0), (3.0, 2.6)) + 0.3 * G2((11.4, yc + 3.8), (1.8, 1.5))   # mental tubercles (a little lumpy)
    outer = outer - 0.12 * G2((0.0, yc + 2.8), (4.0, 2.8))                        # the protuberance's base, depressed in the centre
    outer = outer + stroke(M, [(0.0, yc + 12.5), (0.3, yc + 17.0), (-0.2, yc + 21.0), (0.1, float(yt(0.0)) - 2.0)], [1.2, 1.3, 1.3, 1.1], [0.2, 0.45, 0.4, 0.15], 0.25, 62)   # the symphysis's faint ridge above it
    # Gray 176: the symphysis stands upright under the incisors, the chin as far forward as the alveolar border, not set back under it
    outer = outer + 3.0 * np.exp(-(s / 13.0) ** 2) * smoothstep((M.V - (yc - 1.0)) / 11.0) * smoothstep((yt(M.U) - 2.0 - M.V) / 7.0)   # (repair 1: from 1 mm under the border, not 4: the chin's underside rounds back)   # (no edge to it: a window starting at the border drew a shelf across the chin)
    outer = outer - 0.5 * G2((6.5, yc + 18.5), (5.0, 4.8))                       # incisive fossa, under the incisors' roots
    # the oblique line: faint in front, as Gray has it, and stronger toward the ramus, whose front border it becomes
    # (it runs on up into the ramus's front border, which now rises behind the third molar)
    outer = outer + stroke(M, [(12.5, yc + 5.0), (26.0, yb(26.0) + 6.5), (40.0, yb(40.0) + 12.0), (52.0, yb(52.0) + 17.0), (60.5, -57.5), (61.6, -54.5), (62.3, -50.5),
                           (62.6, -45.0), (62.4, -40.0)], [2.6, 3.0, 2.8, 2.6, 2.4, 2.2, 2.0, 1.8, 1.6], [0.3, 0.45, 0.7, 0.9, 1.0, 0.9, 0.7, 0.45, 0.0], 0.4, 63, mirror=True)
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
        # (Repair 1) the cheek plate over the first and second molars is thin (Fig. 997: the body slim outside the molars)
        # (blended along the row from the second premolar's middle to the first molar's, and from the second molar's to the third's)
        wm = smoothstep((np.abs(sv) - tn[4, 0]) / (tn[5, 0] - tn[4, 0])) * (1 - smoothstep((np.abs(sv) - tn[6, 0]) / (tn[7, 0] - tn[6, 0])))
        wall_out = 0.8 - 0.2 * wm + (1.3 - (1.3 - WALL_MOLAR) * wm) * smoothstep((-teeth.NECK_ABOVE_CREST - v[:, 2]) / 4.0)
        for sg in (1.0, -1.0):
            i, j = M.ij(sg * sv, Pw[:, 1]); i, j = np.round(i).astype(int), np.round(j).astype(int)
            ok = (i >= 0) & (i < M.nu) & (j >= 0) & (j < M.nv)
            np.maximum.at(need_out, (i[ok], j[ok]), (nv + wall_out)[ok]); np.minimum.at(need_in, (i[ok], j[ok]), (nv - wall)[ok])
    lift = ndimage.gaussian_filter(ndimage.maximum_filter(np.maximum(need_out - outer, 0.0), (LIFT_W, 17)), (LIFT_S, 5.0))   # (broad: a narrow one read as a pimple; Repair 1: longer along the row, no groove between the premolar's and the molar's swellings)   # (broad: a narrow one read as a pimple)
    sink = ndimage.gaussian_filter(ndimage.maximum_filter(np.maximum(ib - need_in, 0.0), 17), 5.0)
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
    # (the owner, 25 November: seen from above or below each half must be one gently curved line from the chin to the
    # angle, no elbow behind the last tooth. The tongue-side face behind the third molar therefore keeps the body's
    # offset from the ramus as it stood at that tooth, and gives it up over BACK_L mm, not 16: the swelling that bridges
    # the two faces is long and low.)
    sA = s3 - 9.0                                                   # (from the third molar's middle back)
    back = 1 - evenstep((s - sA) / (BACK_L * (0.5 + BACK_TOP * smoothstep((qq - BACK_Q0) / (1.0 - BACK_Q0)))))   # (ending well in front of the hind border at every height;
    # repair 2: low down over half the length, so that no long swelling stands on the angle's inner side seen from below)
    iA = int(np.argmin(np.abs(M.U[:, 0] - sA))); iB = int(np.argmin(np.abs(M.U[:, 0] - (sA - 3.0))))
    slope = (ib[iA] - ib[iB]) / max(float(M.U[iA, 0] - M.U[iB, 0]), 0.5)
    cell = float(M.U[1, 0] - M.U[0, 0])
    col = ndimage.gaussian_filter1d(ib[iA] + 0.0, 3.0 / cell); slope = ndimage.gaussian_filter1d(slope, 3.0 / cell)
    run = col[None, :] + slope[None, :] * (s - sA)                     # the body's face carried on as it was going there (its shelf's
    # edge eased: carried back as it stood, the ledge under the shelf ran on into the ramus as a long groove)
    target = smin(run * back + irr * (1 - back), irr, 3.0)          # and handed over to the ramus's face (never thinner than the ramus)
    # (T-rows-refit) behind the third molar the handover is rounded, not a pointed ledge
    wS = smoothstep((s - s3 + 2.0) / 6.0)
    target = np.minimum(target * (1 - wS) + ndimage.gaussian_filter(target, (2.0 / cell, 3.5 / cell), mode="nearest") * wS, irr)
    wA = smoothstep((s - sA + 4.0) / 16.0)                         # (over 16 mm: over 8 it read from below as an elbow)
    ib = ib * (1 - wA) + target * wA
    # (T-rows-refit) the lower part of the tongue-side face smoothed again after the handover (the line seen from below)
    wq = (1 - smoothstep((qq - 0.40) / 0.25)) * smoothstep((s - 14.0) / 10.0)
    ib = ib * (1 - wq) + ndimage.gaussian_filter1d(ndimage.gaussian_filter1d(ib, 8.0, axis=1, mode="nearest"), 4.0, axis=0, mode="nearest") * wq
    # (T-jaw-finish: toward the body's face as smoothed above, not as it was before: the two differed by 0.3 to 0.4 mm low
    # down, and where the body's face is let go behind the third molar that step stood as a vertical line on the inner face)
    swell = (irr - ib) * (1 - smoothstep((M.V - (yt(M.U) - 1.0)) / 16.0)) * smoothstep((s - (s3 - 1.0)) / 6.0) * (s >= sA)
    irr = irr - swell
    # (T-jaw-finish) the medial pterygoid's ridges go on now: drawn on the ramus's face before, they were lost under the low
    # tongue-side face's smoothing (2 by 3.5 mm) and its handover (0.75 mm toward the tongue), which is the face at the angle
    irr = irr - ptg
    away = 40.0 * (1 - smoothstep((s - 40.0) / 8.0))                                 # in front of the second molar the ramus's face is nothing
    top = M.V - (yrim(M.U) + 0.5 + 3.0 * (1 - smoothstep((s - 44.0) / 5.0)))         # (in front, the outline itself is the top)
    sunk = 30.0 * smoothstep((s - (s3 + 4.5)) / 4.0)                                 # behind the tooth the body's face is the ramus's: let it go
    lip = np.full(M.U.shape, 2.6)                                                    # the shelf's tongue-side edge, well rounded (at 1.5 mm it read as a level step)
    meet = 0.6 + 4.4 * (1 - smoothstep((s - (s3 - 1.0)) / 5.0))                      # the hollow where the shelf meets the ramus, filled; none where the two faces are one
    d2 = np.abs(np.diff(irr, 2, axis=0))[(reg[1:-1] < 0) & (s[1:-1] > s3 + 6)]
    log("jaw sheet: third molar ends at s %.1f; behind it the tongue-side face bends at most %.2f mm from one half-millimetre row to the next" % (s3, d2.max()))

    # the rim's roundness: the lower border broad, the hind border and angle rounded, the notch and coronoid thin, the tooth-bearing margin 2 mm
    edge = [(0.0, yb(0.0), 4.6), (20.0, yb(20.0), 4.2), (45.0, yb(45.0), 3.8), (70.0, yb(70.0), 3.2)]
    edge += [(*zy(z, y), r) for z, y, r in ((15.5, -66, 1.2), (11.5, -55, 1.2), (12, -37, 1.4), (8, -20, 2.4), (7, -9, 3.0),   # (repair 1: hind border's round under its half-thickness)
                                              (26, -21, 1.1), (39.5, -6, 0.8), (46, -20, 1.5), (45.5, -40, 1.8), (48, -56, 2.0))]
    edge += [(*zn(z, y), r) for z, y, r in ((14.8, -14.5, 2.6), (16.6, -19.0, 2.0))]   # (repair 2: the neck's front edge well rounded:
    # at 1.5 mm its corner ran down the neck's outer side as a line)
    edge += [(sv, yt(sv), 1.3) for sv in (0.0, 15.0, 30.0, 45.0)]                 # the margin thin and rounded
    rad = M.thin_plate(np.array(sym(np.array(edge)), float), weight=10.0, tension=0.3)
    log("jaw sheet: body faces through %d and %d traced points, ramus thickness through %d" % (len(out_pts), len(in_pts), len(TH)))
    return dict(M=M, hw=hind_w, reg=reg, outer=outer, inner=irr, inner_body=ib, top=top, sunk=sunk, lip=lip, meet=meet, away=away, rad=rad, yb=yb, yt=yt, zs=zs, zy=zy, rim=yrim)


def sockets(F, frames, yrim, S, wall=1.5, gap=SOCKET_GAP):
    """The sockets (teeth.seat's way: each the tooth's own shape `gap` mm larger), with the bone round them brought up to the
    scalloped margin (yrim) and not to a plane square to each tooth: teeth.seat's flat collars, one per tooth, stood above the
    body's top with square notches between them. The collars of bone run down the whole root, thinning toward its tip, and
    join the body's faces over 1.6 mm, so they leave no step where they end; the socket's mouth is eased a little."""
    from sdf import smin, smax
    h = float(F.ax[0][1] - F.ax[0][0])
    fields = []
    for s in [f for f in frames if f["side"] == "L"]:
        i = L.TEETH.index(s["tooth"].split(" ", 1)[1])
        R, p = teeth.frame(s)
        root = teeth.AT.ARCHES["lower"][i][4]; wide = max(teeth.AT.ARCHES["lower"][i][5], teeth.AT.ARCHES["lower"][i][7])
        c = p - R[:, 2] * (root / 2 - 2.0); half = np.abs(R) @ np.array([wide / 2 + 3.5, wide / 2 + 3.5, root / 2 + 6.0])
        sl = F.window(c - half, c + half)
        if sl is None:
            continue
        X, Y, Z = np.broadcast_arrays(*F.coords(sl))
        Q = np.stack([X - p[0], Y - p[1], Z - p[2]], -1) @ R
        f = teeth.AT.field("lower", i, Q[..., 0], Q[..., 1], Q[..., 2]).astype(np.float32)
        lz = Q[..., 2]
        socket = teeth.fair(f, h) - gap * np.clip(-(lz + teeth.NECK_ABOVE_CREST) / 2.0, 0.4, 1.0)
        cap = (Y - yrim(S.sn(X, Z)[0])).astype(np.float32)
        fields.append((sl, socket, lz, root, cap))
    for sl, socket, lz, root, cap in fields:
        depth = -(lz + teeth.NECK_ABOVE_CREST)
        thin = wall * np.clip(0.85 + depth / 6.0, 0.85, 1.0)   # (a lip thinner than this was eaten down 2 mm by the rounding: the crest stood in notches)
        deep = np.clip((depth / root - 0.5) / 0.45, 0.0, 1.0)
        thin = thin * (1.0 - 0.7 * deep * deep * (3 - 2 * deep))
        sleeve = smax(socket - thin, cap, 0.7)
        # (below the margin a sleeve stays inside the body's faces: a root's tip near the face stood out as a pimple)
        wd = np.clip((depth - 4.0) / 3.0, 0.0, 1.0)
        sleeve = np.maximum(sleeve, F.D[sl] - 0.2 - 30.0 * (1.0 - wd))
        F.D[sl] = smin(F.D[sl], sleeve, 1.6)
    pre0 = F.D[fields[0][0]].copy()          # (the bone round the central incisor before any socket is cut: the septum's envelope)
    for sl, socket, lz, root, cap in fields:
        F.D[sl] = smax(F.D[sl], -socket, 0.5)
    # The septum between a molar's two roots: left to what the two roots' sockets spared, it was a low knife-edge 3.5 mm below
    # the roots' fork, and from above the narrow gap over it read as a crack across the socket. Bone is filled into the fork
    # (a blade across the tooth between its roots) and the sockets cut again, so the septum rises to the fork, broad and round.
    for s in [f for f in frames if f["side"] == "L" and "molar" in f["tooth"]]:
        R, p = teeth.frame(s)
        F.add(sdf.Box(p - R[:, 2] * 9.0, (1.6, 4.0, 5.2), 1.2, R), k=0.6)
    # (T-lower-sockets) cut again square: a soft cut where the field already is the socket's wall (the first cut) moves the wall
    # out by a quarter of its softness, and three such cuts had made the space round a lower root 0.45 mm where the upper
    # arch's is 0.30. The septum's crest is then the fork's own roof the space's breadth below it, a round arch under each
    # molar 2 to 4 mm below the margin (Gray, Figs. 997 and 1003; the ease that rounded it here had eaten it down to 6 mm).
    for sl, socket, lz, root, cap in fields:
        F.D[sl] = np.maximum(F.D[sl], -socket)
    # The margin as a whole: the field smoothed in a band about the crest's height (septa and lips left by separate cuts met
    # in square shoulders and read as a dark jagged line), then the sockets cut once more with a soft lip.
    from scipy import ndimage
    lo_ = np.min([[s_.start for s_ in sl] for sl, *_ in fields], 0); hi_ = np.max([[s_.stop for s_ in sl] for sl, *_ in fields], 0)
    win = tuple(slice(int(a), int(b)) for a, b in zip(lo_, hi_))
    A = F.D[win].astype(np.float32)
    G = ndimage.gaussian_filter(np.clip(A, -20, 20), 0.45 / h, mode="nearest")
    # (Repair 2) round the front teeth's rim more: their septa and lips met the sockets in square-edged blocks
    G2 = ndimage.gaussian_filter(np.clip(A, -20, 20), RIM_FRONT / h, mode="nearest")
    X_, Y_, Z_ = np.broadcast_arrays(*F.coords(win)); wf = smoothstep((14.0 - np.abs(S.sn(X_, Z_)[0])) / 4.0)
    G = G * (1 - wf) + G2 * wf
    X, Y, Z = np.broadcast_arrays(*F.coords(win))
    dy = Y - yrim(S.sn(X, Z)[0])
    wb = np.clip((dy + 4.0) / 2.0, 0, 1) * np.clip((3.0 - dy) / 1.5, 0, 1); wb = wb * wb * (3 - 2 * wb)
    # (T-lower-sockets) the smoothing may take at most RIM_THIN off any face (a Gaussian of the field thins a plate by 0.8 of
    # its spread from each side: the 1.0 to 1.3 mm septa between the front teeth were left 0.06 mm at 1 mm under the crest);
    # it still rounds the septa's tops and the sockets' lips and fills the square shoulders
    G = smin(G, A + RIM_THIN, 0.15)
    F.D[win] = np.where(np.abs(A) < 15, A * (1 - wb) + G * wb, A)
    for sl, socket, lz, root, cap in fields:
        # (T-lower-sockets) the last cut soft only at the lip (a rounded mouth); below it square, so the space keeps its breadth
        Xs, Ys, Zs = np.broadcast_arrays(*F.coords(sl))
        k = RIM_SOFT * np.clip((Ys - yrim(S.sn(Xs, Zs)[0]) + 1.5) / 1.0, 0.0, 1.0)
        a_, b_ = -F.D[sl], socket
        hh = np.clip(0.5 + 0.5 * (b_ - a_) / np.maximum(k, 1e-6), 0.0, 1.0)
        F.D[sl] = np.maximum(-(b_ + (a_ - b_) * hh - k * hh * (1.0 - hh)), np.maximum(F.D[sl], -socket)).astype(np.float32)
    # (T-jaw-shape) The two central incisors stand with their crowns in contact at the midline and their roots, which lean
    # toward it as the arch curves, within 0.24 to 0.45 mm of it: their sockets, each the root 0.3 mm larger, met across the
    # midline and left no bone between them for 10 mm (a slot in the median section, a crease inside the chin). The
    # interdental septum is put back: a plate of bone 0.72 mm thick on the midline, inside the bone that stood round the
    # sockets before they were cut, up to the scalloped margin, its edges blended into the sockets' walls. The roots keep
    # their places; where one comes nearer the midline than the septum's half (by 0.12 mm at most) the socket's wall
    # touches it there.
    sl0 = fields[0][0]
    X0 = np.broadcast_arrays(*F.coords(sl0))[0]
    F.D[sl0] = smin(F.D[sl0], smax(np.abs(X0) - SEPTUM_HALF, pre0, 0.3), 0.3).astype(np.float32)
    return F


class Ribbon4(Ribbon):
    """mandible3's Ribbon, its rim drawn along the hind border (weight hw on the map) by a law of continuous curvature: there
    each face turns in to the edge along a clothoid, whose curvature grows evenly from none where it leaves the face, and
    then a round of the face's distance b from the mid-plane (the zone takes about 1.6 b mm of the border's
    breadth). Elsewhere the rim keeps its circular rounding."""
    def __init__(self, sheet, M, outer, inner, region, radius, body, hw):
        super().__init__(sheet, M, outer, inner, region, radius, body)
        self.c.append(M.smooth(hw))

    def __call__(self, X, Y, Z):
        x2, z2 = np.broadcast_arrays(X[:, :1, :], Z[:, :1, :])
        s, n = self.S.sn(x2, z2)
        u, v, w = np.broadcast_arrays(s, Y, n)
        V = [self.M.smooth_sample(c, u, v) for c in self.c]
        o, i, ko, ki, d2, r = V[:6]
        b, kb, top, sunk, lip, meet, away, hw = V[6:]
        e = self.M.outside(u, v)
        d2 = np.where(e > 0, np.maximum(d2, e), d2)
        tongue = smin((i - w) * ki + away, relief.round_meet((b - w) * kb, top, np.clip(lip, 0.8, 6.0)) + sunk, np.clip(meet, 0.3, 8.0))
        through = np.maximum((w - o) * ko, tongue)
        rim = relief.round_meet(through, d2, np.clip(r, 0.6, 6.0))
        hw = np.clip(hw, 0.0, 1.0)
        if not (hw > 1e-3).any():
            return rim.astype(np.float32)
        half = np.maximum(0.5 * (o - i), 0.3)
        de = d2 - HIND_TIP[0] * np.exp(-((v - HIND_TIP[1]) / HIND_TIP[2]) ** 2)   # (the side outline kept where it was)
        g = np.interp(np.clip(-de / (CLOTHOID[2] * HIND_SPREAD * half), 0.0, 1.0), CLOTHOID[0], CLOTHOID[1])
        k = 0.5 * (ko + ki)
        edge = np.maximum(through + half * (1.0 - g) * k, de)
        return (rim * (1 - hw) + edge * hw).astype(np.float32)


# (task C) The condylar process under the joint surface, rebuilt from horizontal sections. Built from an ellipsoid head, a
# tube for the neck, a ball for the lateral tubercle and three tubes for the ridges, it read from the side as a broad
# column with a level top and a small round knob on its front corner, and from in front as a knob with a bump on its outer
# end. Its sections said why: from 5 to 10 mm under the top every section was the same oval (17.5 by 10 mm), and the neck
# under it was as deep from front to back as the head (11 to 12.5 mm), so the head had no underside and the column's
# front and back edges ran straight up into it; the knob was the head's own outer end (an ellipsoid's tip, 1.8 mm round,
# turned 2.3 mm forward by the head's slant) with the tubercle's ball fused under it, standing 4 mm proud of the face in
# front of it and cut off 1.5 mm in a millimetre below it. Now: the joint surface (above y -5) is kept as it was, and
# under it each 1 mm section is an eased oval in the head's own frame (its long axis turned 15 degrees), drawn from Gray
# (Figs. 176, 177 and pp. 173 to 174: the head 18 to 20 mm across and 9 to 10 from front to back, convex both ways, its
# long axis transverse; the neck narrower, flattened from before backward, strengthened by ridges from the fore part and
# sides of the head; the pterygoid fovea on the front of the neck; the tubercle at the head's outer end) with the five
# head CTs for its proportions, and lofted through them by a curve smooth in its second derivative (no section ends in a
# step). Down to 20 mm under the top it meets the ramus's own sections, which are kept.
#   (y, lateral half-length, medial half-length, forward half-depth, backward half-depth, squareness): in the head frame,
#   millimetres from the head's centre line. (repair 1) Each key is solved so that the process's outline meets a drawn
#   silhouette (Figs. 176, 177): from the side the hind edge runs from the back of the head straight down into the hind
#   border, slightly convex, with no notch (its z changes one way only below y -9.5); the front edge has one long shallow
#   hollow (1.4 mm deep at most) from the head's front lip down into the notch; under the head the neck is a little
#   shallower from front to back than the head (10.6 against 10.9 mm). From in front the head's two poles draw in over 6
#   mm (17.2 mm across at y -7, 11.1 at -13.5), the underside easing into the neck with no lip; the neck 13.4 mm across
#   at y -11. (Round 1 drew them in within 3 mm and let the neck run deeper than the head below a 2 mm notch: a dome on
#   a ring groove.) The CT helper's neck10 (jawlib: the process's front-to-back depth 10 mm under its top, in whole mm)
#   reads 11 here, under its 12 to 16: it reaches 12 only with the neck 11.4 mm deep at y -13, deeper than the head, and
#   then the front edge either stands 0.6 mm further forward at y -15 to -17 (outline gap to Fig. 176 there 6.60 mm) or
#   swells again below a second hollow. The plate is followed.
COND_KEYS = [(-8.5, 8.529, 7.809, 4.473, 6.167, 2.0), (-9.5, 8.187, 7.255, 4.521, 5.766, 2.0), (-10.5, 7.56, 6.564, 4.522, 5.651, 2.0),
             (-11.5, 6.927, 5.96, 4.529, 5.664, 2.0), (-12.5, 6.396, 5.44, 4.775, 5.666, 2.0), (-13.5, 6.024, 5.041, 5.298, 5.657, 2.0),
             (-14.5, 5.811, 4.733, 5.96, 5.641, 2.0), (-15.5, 5.705, 4.445, 6.766, 5.623, 2.0), (-16.5, 5.6, 4.18, 7.618, 5.603, 2.0),
             (-17.5, 5.448, 4.032, 8.468, 5.552, 2.0), (-18.5, 5.097, 4.012, 9.426, 5.534, 2.0)]
# (T-jaw-shape) the neck's front edge below y -12 carried forward (its forward half-depths, the fourth column, re-solved): the
# notch's floor now lies 2 mm higher and 2.5 further forward, and the front edge sweeps down and forward into it in one
# hollow curve (Fig. 176) instead of standing upright to y -18 and turning there.
COND_KEEP_TOP, COND_KEEP_LOW = (-4.5, -5.0, -5.5, -6.0, -6.5, -7.0), (-19.5, -20.0, -20.5, -21.0)     # sections taken from the field as it is
COND_HANDOVER = (-16.5, -19.5)      # from here down the drawn sections hand over to the ramus's own (no ring where they meet)
COND_HANDOVER_TOP = (-7.0, -10.5)   # (repair 1) and from here up to the head's own: the head's sections are lens-shaped,
#   the drawn ones ovals, and a change of shape within half a millimetre left a crease across the back of the head
#   the marks on it, as changes of a section's radius (mm) at an angle (deg, 0 = outward along the long axis, 90 = forward),
#   eased over an angle and a height: (amplitude, angle, angular spread, y, height spread)
COND_MARKS = [(0.35, 12.0, 28.0, -7.6, 1.4),       # the lateral tubercle: a low swelling on the outer end, a little forward
              (-1.0, 115.0, 22.0, -10.8, 1.8),     # the pterygoid fovea: a shallow hollow on the front of the neck, under the inner half
              (0.22, 58.0, 16.0, -10.6, 1.6),      # the ridges from the fore part and sides of the head, either side of the fovea,
              (0.22, 158.0, 16.0, -10.6, 1.6)]     # fading down the neck (T-arch-lower: by y -13; reaching on to y -16 they stood as two
                                                   # soft lumps low on the neck's outer face)


def condyle_sections(F, log=print):
    """Replace the condylar process between y -5 and -20.5 by the loft through its sections (COND_KEYS) in the head's frame."""
    from scipy.interpolate import CubicSpline
    from skimage import measure
    c, s = np.cos(np.radians(-HEAD["turn"])), np.sin(np.radians(-HEAD["turn"]))
    cx, cz = HEAD["centre"][0], HEAD["centre"][2]
    ang = np.radians(np.arange(0.0, 360.0, 0.5))
    X0, X1, Z0, Z1 = 36.0, 66.0, -4.0, 22.0
    sl = F.window(np.array([X0, -22.0, Z0]), np.array([X1, -4.0, Z1]))
    X, Y, Z = (np.asarray(a, float) for a in F.coords(sl))
    xs, ys, zs = X[:, 0, 0], Y[0, :, 0], Z[0, 0, :]
    XX, ZZ = np.meshgrid(xs, zs, indexing="ij")
    U = (XX - cx) * c + (ZZ - cz) * s; V = -(XX - cx) * s + (ZZ - cz) * c       # the head frame (u outward, v forward)
    def kept(y):                                   # a section of the field as it is: its radius at each angle
        j = int(round((y - ys[0]) / F.h)); A = np.clip(F.D[sl][:, j, :], -12, 12)
        cc = max(measure.find_contours(A, 0.0), key=len)
        x = xs[0] + F.h * cc[:, 0]; z = zs[0] + F.h * cc[:, 1]
        u = (x - cx) * c + (z - cz) * s; v = -(x - cx) * s + (z - cz) * c
        a = np.mod(np.arctan2(v, u), 2 * np.pi); o = np.argsort(a)
        return np.interp(ang, a[o], np.hypot(u, v)[o], period=2 * np.pi)
    def drawn(lat, med, fw, bk, n):
        ca, sa = np.cos(ang), np.sin(ang)
        A = np.where(ca > 0, lat, med); B = np.where(sa > 0, fw, bk)
        return (np.abs(ca / A) ** n + np.abs(sa / B) ** n) ** (-1.0 / n)
    def handed(y, r):
        f = min(smoothstep((y - COND_HANDOVER[1]) / (COND_HANDOVER[0] - COND_HANDOVER[1])),
                smoothstep((COND_HANDOVER_TOP[0] - y) / (COND_HANDOVER_TOP[0] - COND_HANDOVER_TOP[1])))
        return r if f >= 1 else kept(y) * (1 - f) + r * f
    keys = [(y, kept(y)) for y in COND_KEEP_TOP + COND_KEEP_LOW] + [(k[0], handed(k[0], drawn(*k[1:]))) for k in COND_KEYS]
    keys.sort(key=lambda t: t[0])
    ky = np.array([k[0] for k in keys]); KR = np.array([k[1] for k in keys])
    KR = ndimage.gaussian_filter1d(KR, 4.0, axis=1, mode="wrap")                 # (2 degrees: the quadrants' joins eased)
    loft = CubicSpline(ky, KR, axis=0)
    D = F.D[sl]
    for j, y in enumerate(ys):
        w = smoothstep((-5.0 - y) / 0.75) * smoothstep((y + 20.5) / 1.25)
        if w <= 0:
            continue
        r = loft(y)
        for amp, a0, da, y0, dy in COND_MARKS:
            d = np.angle(np.exp(1j * (ang - np.radians(a0))))
            r = r + amp * np.exp(-(d / np.radians(da)) ** 2) * np.exp(-((y - y0) / dy) ** 2)
        P = np.column_stack([cx + r * np.cos(ang) * c - r * np.sin(ang) * s, cz + r * np.cos(ang) * s + r * np.sin(ang) * c])
        dist = cKDTree(P).query(np.column_stack([XX.ravel(), ZZ.ravel()]))[0].reshape(XX.shape)
        inside = np.hypot(U, V) < np.interp(np.mod(np.arctan2(V, U), 2 * np.pi), ang, r, period=2 * np.pi)
        L = np.where(inside, -dist, dist)
        D[:, j, :] = (np.clip(D[:, j, :], -12, 12) * (1 - w) + L * w).astype(np.float32)
    F.D[sl] = D
    log("jaw: condylar process lofted through %d sections from y %.1f to %.1f" % (len(ky), ky.max(), ky.min()))


def build(h=0.5, log=print, seat=True):
    use()
    S = sheet4()
    W = maps(S, log)
    M = W["M"]
    F = sdf.Field([0, -103, -4], [68, 5, 101], h)
    F.add(Ribbon4(S, M, W["outer"], W["inner"], W["reg"], W["rad"], (W["inner_body"], W["top"], W["sunk"], W["lip"], W["meet"], W["away"]), W["hw"]))
    on = lambda z, y, out=0.0: MB.on_ramus(*warp(z, y), out)

    def face(z, y, cheek=True, lift=0.0, s=None, raw=False):
        """A point on the jaw's cheek-side (or tongue-side) face, by its place on the side view (z, y) or at (s, y),
        and the direction toward the cheek there. (z, y) are on the old outline unless raw (then on the new)."""
        if s is None and raw:
            z, y = regrid(z, y)
            sv = float(S.sn(*MB.on_ramus(z, y)[[0, 2]])[0])
        elif s is None:
            sv, y = W["zy"](z, y)
        else:
            sv = s
        A = W["outer"] if cheek else (W["inner"] if s is None else W["inner_body"])           # tongue side: the ramus's face by (z, y), the body's by (s, y)
        n = float(M.sample(A, np.array([sv], float), np.array([y], float))[0]) + (lift if cheek else -lift)
        return S.at(sv, y, n), sdf.unit(S.at(sv, y, n + 1.0) - S.at(sv, y, n))

    # ---- the condyloid process. The neck is "flattened from before backward": seen from behind it widens from the ramus's
    # thick hind border up into the head, seen from the side it stays narrow. Its sections are ovals set along the head's
    # long axis, which runs toward the midline and a little backward.
    c = HEAD
    R = sdf.rot((0, 1, 0), c["turn"]); axis = R @ np.array([1.0, 0.0, 0.0])
    ctr = np.array(c["centre"], float)
    P = sdf.spline(np.array([on(12.6, -22.5), on(11.6, -18.0), on(10.3, -13.5)       # (from lower down it stood on the ramus as a column)
                             + 0.25 * (ctr - on(10.3, -13.5)) * np.array([1, 0, 0]),
                             ctr + np.array([0.5, -3.0, 0.1])]), 0.8)
    # (side to side the neck is half as wide again as from front to back all the way up: it was a round rod below the head)
    F.add(sdf.Tube(P, [(0, 2.4), (0.35, 3.0), (0.7, 4.7), (0.88, 6.8), (1, 8.0)], [(0, 3.4), (0.35, 3.3), (0.7, 3.3), (1, 3.4)], up=axis), k=5.0)                                     # (k 5: at 3.2 its edge read as a crease down the ramus)
    F.add(sdf.Ellipsoid(ctr, c["half"], R), k=1.6)                                                    # the head: convex from before backward and from side to side
    F.add(sdf.Ellipsoid(ctr + R @ np.array([1.5, 0.35, -0.4]), (6.0, 4.0, 3.5), R), k=1.2)          # (its top a little fuller toward the outer end: oblong, not a lens)
    # (T-jaw-shape) The head's inner half drawn lower: its upper face falls away toward the medial pole, by up to 1 mm on
    # the pole's upper slope (y above -5, u under -4), nothing on the lateral half or the top. The head stood 0.1 to 0.4 mm
    # from the socket's roof there (the roof comes down lowest over the inner half, 2 to 3 mm in from the pole); the
    # condyle's medial pole in an adult is the lower one, its upper surface sloping down and in from the crest.
    sl = F.window(ctr - np.array([14.0, 9.0, 10.0]), ctr + np.array([4.0, 6.0, 10.0]))
    Xh, Yh, Zh = (np.asarray(a, float) for a in F.coords(sl))
    Uh = (Xh - ctr[0]) * np.cos(np.radians(-c["turn"])) + (Zh - ctr[2]) * np.sin(np.radians(-c["turn"]))
    F.D[sl] = (F.D[sl] + MEDIAL_SHAVE * smoothstep((-Uh - 0.3) / 3.5) * smoothstep((Yh + 7.2) / 2.4)).astype(np.float32)
    # (task C) the tubercle's ball, the three ridge tubes and the fovea's cut are gone: under the joint surface the process
    # is drawn by its sections, with those marks on them (COND_MARKS)
    condyle_sections(F, log)

    # ---- the tongue side of the ramus: the mandibular foramen "about its center", oblique: a funnel whose mouth, longer than
    # wide, faces up and back and toward the tongue, and which runs down and forward into the bone. On the front of its mouth
    # the lingula, "a sharp spine": a thin tongue of bone rising from the mouth's front lip, its tip up and back over the
    # opening; behind and below, the notch from which the mylohyoid groove runs down and forward (drawn in maps).
    fz = lambda z, y, l=0.0: face(z, y, False, lift=l, raw=True)
    rng = np.random.default_rng(1771)
    path = [fz(19.6, -37.4, 3.4), fz(20.8, -39.8, 1.8), fz(21.8, -41.9, 0.0), fz(23.1, -44.2, -1.5), fz(25.4, -48.0, -2.1)]   # (its bottom 2 mm under the face: deeper, it came through the ramus's 4.5 mm)   # (repair 1: steeper in, 45 degrees: a long slant drew the mouth out into a slit)
    P = np.array([p for p, w in path]); Wn = np.array([w for p, w in path])
    a = [(0, 2.4), (0.3, 2.2), (0.55, 1.8), (0.8, 1.4), (1, 1.2)]                           # across the face, and along it (b)
    b = [(0, 2.9), (0.3, 2.5), (0.55, 1.9), (0.8, 1.4), (1, 1.2)]
    a = [(t, v * rng.uniform(0.93, 1.07)) for t, v in a]; b = [(t, v * rng.uniform(0.9, 1.1)) for t, v in b]
    # the lingula: a flattened, tapering blade standing 1 to 1.5 mm proud of the face, broad at its root on the front lip
    (l0, n0), (l1, n1), (l2, n2) = fz(25.0, -43.8, -0.6), fz(24.3, -41.6, 0.1), fz(23.5, -39.6, 0.5)   # (repair 1: short, at the mouth's front: a long blade along it read as a hooked line)
    Lp = np.array([l0, l1, l2])
    F.add(sdf.Tube(sdf.spline(Lp, 0.4), [(0, 0.6), (0.6, 0.5), (1, 0.4)], [(0, 2.8), (0.5, 1.8), (0.85, 0.9), (1, 0.4)], up=n1), k=1.0)   # (a thin flat tongue: 1.2 mm thick, 6 wide at its root)
    # (the lingula first and the funnel cut after: its root, left standing inside the mouth, read as a second flap and a crack)
    F.cut(sdf.Tube(sdf.spline(P, 0.5), a, b, up=Wn[2]), k=0.9)                     # (the path's slant through the face draws the mouth out)
    F.ease(P[2], 2.6, 0.5); F.ease(P[3], 2.4, 0.5)                                 # the funnel's throat smooth (no crack line where its walls met)
    canal_in = (P[-1], sdf.unit(P[-1] - P[-2]))                                                # the funnel's bottom and the way it points: the canal goes on from here (structure.py)

    # ---- the tongue side of the chin: the mental spines and the digastric fossae are made after the halves are joined
    # (chin_marks), each side its own (T-jaw-shape: the fossa cut here, 1.8 mm across under a 2.4 mm blend, did not show)
    sdf.ease_midline(F)
    frames = teeth.packed(M2.LOWER_LINE, M2.LOWER_T, False)
    if seat:
        sockets(F, frames, W["rim"], S)
        lab, n = ndimage.label(F.D < 0)                                                              # specks of bone left loose inside a socket (between close roots) go
        if n > 1:
            big = int(np.argmax(ndimage.sum(np.ones_like(lab), lab, np.arange(1, n + 1)))) + 1
            F.D[(lab > 0) & (lab != big)] = 0.5 * h
    # ---- the mental foramen: "midway between the upper and lower borders of the body", between the two premolars' roots
    # and a little toward the second; it opens backward and upward
    fr = [f for f in frames if f["side"] == "L"]
    pa, pb = np.array(fr[3]["position_mm"]), np.array(fr[4]["position_mm"])
    sm = 0.1 * float(S.sn(pa[0], pa[2])[0]) + 0.9 * float(S.sn(pb[0], pb[2])[0])   # (below the second premolar: it lay under the first)
    ym = 0.5 * (float(W["yt"](sm)) + float(W["yb"](sm)))
    mf, w = face(0, ym, True, s=sm)
    back = sdf.unit(S.at(sm + 2.0, 0.0) - S.at(sm, 0.0)); up1 = np.array([0.0, 1.0, 0.0])
    # Gray (page 173): the canal in the body, "on arriving at the incisor teeth, ... turns back to communicate with the mental
    # foramen". So the canal comes up from in front and below and opens backward, upward and outward, 45 degrees off square to
    # the face: an oval under a front and lower lip, its hind and upper edge running out into a shallow groove. (It was a short
    # straight hole, round on the face.) The lip is too sharp for the grid to hold, so the field is eased there (as at the
    # infraorbital foramen).
    e = sdf.unit(0.55 * w + 0.62 * back + 0.52 * up1); deep = sdf.unit(0.4 * w + 0.75 * back + 0.5 * up1)
    P = sdf.spline(np.array([mf - 2.5 * e - 2.6 * deep, mf - 2.5 * e, mf, mf + 2.3 * e]), 0.8)
    F.cut(sdf.Tube(P, [(0, 1.0), (0.7, 1.1), (1, 1.2)], [(0, 1.15), (0.7, 1.45), (1, 1.75)], up=w, taper=0.22), k=0.7)
    run = np.array([face(0, ym + dy, True, lift=l, s=sm + ds)[0] for ds, dy, l in ((0.9, 0.85, 0.3), (2.0, 1.9, 0.65), (3.3, 3.1, 1.1))])
    F.cut(sdf.Tube(run, 1.0, [(0, 1.3), (1, 2.0)], up=w), k=1.0)
    F.ease(mf, 4.0, 0.6)
    log("jaw: mental foramen at %s, %.1f mm below the margin and %.1f above the lower border; joint head %.0f by %.0f mm at %s"
        % (np.round(mf, 1).tolist(), float(W["yt"](sm)) - ym, ym - float(W["yb"](sm)), 2 * c["half"][0], 2 * c["half"][2], list(c["centre"])))
    canal = {"in": [np.round(canal_in[0], 2).tolist(), np.round(canal_in[1], 3).tolist()],                             # (left side; the right is its mirror)
             "out": [np.round(mf - 2.5 * e - 2.6 * deep, 2).tolist(), np.round(deep, 3).tolist()]}                      # the mental foramen's inner end and the way it runs out
    return F, {"mental foramen": np.round(mf, 1).tolist(), "sockets": frames, "sheet": S, "maps": W, "canal": canal}


ZONES = [   # name, centre, radii, extra grain (mm), pits per mm2 (surface.py)
    ("masseter's and medial pterygoid's ridges at the angle", (47, -58, 20), (7, 14, 13), 0.04, -0.01),      # (no pits here: at the grid's size they came out as craters)
    ("masseter's and medial pterygoid's ridges at the angle", (-47, -58, 20), (7, 14, 13), 0.04, -0.01),
    ("chin", (0, -80, 90), (17, 11, 9), 0.02, 0.03),
    ("mental spines", (0, -77, 79.5), (5, 6, 3.5), 0.03, 0.0),                  # (T-jaw-finish) their roughness, each side its own
    ("tooth-bearing margin", (0, -63, 68), (30, 5, 30), 0.03, 0.06),
    ("coronoid process (temporalis)", (47, -14, 40), (5, 10, 7), 0.025, 0.0),
    ("coronoid process (temporalis)", (-47, -14, 40), (5, 10, 7), 0.025, 0.0),
    ("joint head", (51, -4, 9.5), (11, 4.5, 6), -0.03, -0.02),
    ("joint head", (-51, -4, 9.5), (11, 4.5, 6), -0.03, -0.02),
    ("pterygoid fovea", (50.5, -11.5, 13.5), (3.5, 2.5, 2.5), 0.03, 0.0),
    ("pterygoid fovea", (-50.5, -11.5, 13.5), (3.5, 2.5, 2.5), 0.03, 0.0),
]


def _ray(D, lo, h, p, d, step=0.1, far=25.0):
    """The first place the field turns from bone to air going from p (inside the bone) along d, and the surface's
    outward normal there."""
    from scipy.ndimage import map_coordinates
    d = sdf.unit(d); t = np.arange(0.0, far, step); P = np.asarray(p, float) + np.outer(t, d)
    v = map_coordinates(D, ((P - lo) / h).T, order=1, mode="nearest")
    k = int(np.argmax(v > 0)); q = P[k - 1] + (P[k] - P[k - 1]) * (-v[k - 1]) / max(v[k] - v[k - 1], 1e-6)
    e = 0.4; g = np.array([map_coordinates(D, (((q + e * u) - lo) / h)[:, None], order=1)[0] - map_coordinates(D, (((q - e * u) - lo) / h)[:, None], order=1)[0]
                           for u in np.eye(3)])
    return q, sdf.unit(g)


def _box(D, lo, h, c, r):
    i0 = [max(int((c[k] - r - lo[k]) / h), 0) for k in range(3)]; i1 = [min(int((c[k] + r - lo[k]) / h) + 1, D.shape[k]) for k in range(3)]
    sl = tuple(slice(i0[k], i1[k]) for k in range(3))
    X, Y, Z = np.meshgrid(*[lo[k] + h * np.arange(i0[k], i1[k]) for k in range(3)], indexing="ij")
    return sl, np.stack([X, Y, Z], -1)


CHIN_SPINES = [   # (x, height over the lower border, height mm, base half-width across, up and down, lean down, tip round): Fig. 177 and p. 173
    (1.9, 11.4, 1.15, 2.3, 2.8, 0.35, 0.18),        # upper left (genioglossus)
    (-1.5, 10.6, 0.95, 2.1, 2.5, 0.25, 0.20),       # upper right: a little lower and smaller
    (1.0, 7.3, 0.60, 1.6, 1.8, 0.15, 0.20),         # lower left (geniohyoid), nearer the midline
    (-1.1, 6.8, 0.50, 1.5, 1.7, 0.10, 0.22)]        # lower right: fainter
DIGASTRIC = [     # (x, z of its middle on the base, depth mm, half-length along the border, half-breadth): one each side
    (10.4, 82.6, 1.55, 6.6, 3.4),
    (-9.8, 82.0, 1.40, 6.2, 3.6)]


def chin_marks(D, lo, h, info):
    """The tongue side of the chin, on the whole jaw (so the two sides are not alike): the mental spines and the digastric
    fossae. (T-jaw-shape) Drawn on the unrolled sheet the spines came out as two flat squarish pads, and the fossae, a
    1.8 mm ellipsoid cut under a 2.4 mm blend, did not show at all. Gray (p. 173, Fig. 177): "on either side of the
    symphysis, near its lower part, two pairs of laminated tubercles, the mental spines"; "below the mental spines, on
    either side of the middle line, an oval depression for the attachment of the Digastricus". So each spine is a small
    pointed tubercle standing up to 1 mm off the hind face of the symphysis, its flanks hollow-sided and running out into
    the face over 1.1 to 2 mm, its tip leaning a little down; the upper pair larger and further apart than the lower; and
    each fossa a shallow oval hollow (1.1 to 1.25 mm, 10 to 11 mm long) on the base's hind lip either side of the midline,
    facing down and back. Every one has its own size and place."""
    yc = float(info["maps"]["yb"](0.0))
    for x, dy, H, ra, rb, lean, rt in CHIN_SPINES:
        p, n = _ray(D, lo, h, (x, yc + dy, 88.0), (0.0, 0.0, -1.0))
        t = sdf.unit(n + np.array([0.0, -lean, 0.0]))                        # the tip's way: back, a little down
        up = sdf.unit(np.array([0.0, 1.0, 0.0]) - (np.array([0.0, 1.0, 0.0]) @ t) * t); ac = np.cross(up, t)
        sl, P = _box(D, lo, h, p, 4.5)
        Q = P - p; a = Q @ t; r = np.sqrt((Q @ ac / ra) ** 2 + (Q @ up / rb) ** 2)
        r = np.sqrt(r * r + (rt / max(ra, rb)) ** 2) - rt / max(ra, rb)          # (the tip rounded, not a needle)
        g = H * np.clip(1.0 - r, 0.0, 1.0) ** 2.4                                # hollow-sided: a point, its flanks running out over a broad foot
        w = 1.0 - smoothstep((np.abs(a) - 2.0) / 2.0)
        D[sl] = (D[sl] - g * w).astype(D.dtype)
    from scipy.ndimage import map_coordinates
    for x, zc, dep, al, ab in DIGASTRIC:
        sx = np.sign(x); ys = lo[1] + h * np.arange(D.shape[1])
        col = map_coordinates(D, np.vstack([np.full(len(ys), (x - lo[0]) / h), (ys - lo[1]) / h, np.full(len(ys), (zc - lo[2]) / h)]), order=1)
        p, n = _ray(D, lo, h, (x, ys[col < 0].min() + 3.0, zc), (0.0, -1.0, -0.25))   # (from 3 mm inside the base, down: the base's underside)
        e1 = sdf.unit(np.array([1.0, 0.0, -0.32 * sx])); e1 = sdf.unit(e1 - (e1 @ n) * n); e2 = np.cross(n, e1)
        sl, P = _box(D, lo, h, p, 10.0)
        Q = P - p
        g = dep * np.exp(-((Q @ e1 / al) ** 2 + (Q @ e2 / ab) ** 2 + (Q @ n / 3.5) ** 2))
        D[sl] = (D[sl] + g).astype(D.dtype)
    return D


def whole(F, info, log=print, rough=True, seed=176):
    """The whole jaw's field from its left half: mirrored, then given its grain and pits (each side its own). Returns (D, lo)."""
    D = sdf.mirror_field(F.D); lo = np.array([-float(F.ax[0][-1]), float(F.lo[1]), float(F.lo[2])])
    Dm = D.copy() if rough else None          # (T-lower-sockets) the sockets before the chin's marks (whole: kept clear of them)
    D = chin_marks(D, lo, F.h, info)
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
            # (T-lower-sockets) a socket's own wall a hair only (it had worn the space round the roots 0.12 mm wider); the faces
            # outside, the rim and the bone round the sockets keep their grain
            R, pc = teeth.frame(s)
            X, Y, Z = np.broadcast_arrays(*G.coords(sl))
            Q = np.stack([X - pc[0], Y - pc[1], Z - pc[2]], -1) @ R
            tf = teeth.AT.field("lower", L.TEETH.index(s["tooth"].split(" ", 1)[1]), Q[..., 0], Q[..., 1], Q[..., 2])
            wear = SOCKET_WEAR + (SOCKET_WEAR_FACE - SOCKET_WEAR) * smoothstep((tf - 0.5) / 1.0)
            # and no bone grows into a socket's space from the chin's marks either (the upper left mental spine's foot reached
            # the central incisor's apex: 0.03 mm of space left there)
            floor = np.where((tf < 0.4) & (Dm[sl] > 0), np.maximum(D0[sl], Dm[sl]), D0[sl])
            G.D[sl] = np.clip(G.D[sl], floor, floor + wear)
    sl = G.window(np.array([-0.9, -77.0, 81.0]), np.array([0.9, -57.0, 95.0]))    # (T-jaw-shape) the septum between the central incisors' sockets: no wear
    G.D[sl] = D0[sl]
    return G.D, lo
