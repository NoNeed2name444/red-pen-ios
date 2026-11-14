"""temporal.py: the side of the head round the ear: the mastoid process, the ear hole and its lip, the crest over it, the styloid.

Read from Gray's Anatomy, 1918 (public domain):
  Fig. 188  the skull from the side, put into the head frame (plates.side_frame): where each thing lies and how large
            it is. The mastoid's outline, the ear hole's outline, the crest's line and the styloid are traced on it.
  Fig. 137  the temporal bone's outer surface, larger: what each thing is like. The arch's hind root runs back over the
            ear hole and climbs as the supramastoid crest; between the crest and the hole's hind wall lies the small
            hollow of the suprameatal triangle; the tympanic part's free border is a thick rough lip round the front,
            the floor and the lower back of the hole; a small process (post-glenoid) stands between the hole and the
            jaw's socket; the mastoid's outer face is rough where the muscles take hold; the styloid leaves the bone
            through a sheath (the vaginal process).
  pp. 139-141 the text to those ("lateral border free and rough", "about 2.5 cm. in length", "nearly 2 cm. long").

Head frame, millimetres: x to the body's left, y up, z forward. The side view is a map over (z, y).
The shapes are built with the left half (solids, cuts). What is rough or uneven is pressed into the finished head, each
side with its own unevenness (relief): a mirrored roughness is the first thing the eye picks out.
"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import sdf
from sdf import spline, Tube, Ellipsoid, rot
from relief import Map, Slab, Prism

MASTOID_SIDE = [   # the mastoid process seen from the side, closed, running up into the bone: (z, y)
    (-7.2, 1.0), (-8.4, -4.0), (-9.6, -9.0), (-10.8, -14.0), (-11.5, -19.0), (-11.3, -24.0), (-10.7, -27.5),      # its front border, nearly upright
    (-10.9, -30.2), (-12.3, -32.3), (-15.2, -33.3), (-18.4, -32.8),                                              # the blunt tip
    (-21.4, -30.8), (-24.0, -28.0), (-26.8, -25.2), (-30.0, -22.5), (-34.0, -20.0),                              # its hind border, rising to the occipital
    (-37.0, -14.0), (-36.0, -5.0), (-30.0, 2.0), (-18.0, 4.0)]                                                   # inside the bone
CREST = [(14.0, 1.0), (8.0, 1.6), (2.0, 2.3), (-4.0, 3.4), (-10.0, 4.9), (-16.0, 6.8), (-22.0, 9.0), (-28.0, 11.6), (-33.0, 14.6)]
MEATUS = [(-2.5, 0.3), (0.2, -1.0), (1.3, -3.5), (1.2, -6.5), (0.0, -9.0), (-2.0, -10.2), (-4.5, -9.8), (-6.3, -7.8),
          (-7.0, -5.0), (-6.6, -2.2), (-5.0, -0.3)]                    # the ear hole's mouth: taller than wide, leaning, no two sides alike
LIP = [(2.3, -1.3), (3.0, -4.6), (2.5, -8.1), (0.6, -10.9), (-2.2, -12.1), (-5.2, -11.3), (-7.5, -8.7), (-8.3, -5.6)]   # the tympanic part's free border round it
FISSURE = [(-7.7, -3.5), (-8.5, -8.0), (-9.1, -12.5), (-8.7, -17.0)]   # between the tympanic part and the mastoid
ARTERY = [(-9.0, 9.0), (-10.5, 17.0), (-12.5, 26.0), (-13.5, 34.0)]    # the groove of the middle temporal artery, up the squama
LIP_X = 56.6                # how far out the hole's lip stands: well inside the arch's root above it and the mastoid behind it
STYLOID = [(41.8, -13.0, -1.5), (41.4, -20.0, 1.6), (40.0, -28.0, 5.0), (38.2, -35.5, 8.4)]   # down, forward and a little inward, with a slight bow: 24 mm
INSIDE = MASTOID_SIDE[-6:] + MASTOID_SIDE[:1]       # the part of the mastoid's outline that lies in the bone: there the process runs out into the skull's side
# The temporal lines, which Fig. 188 draws and names ("Supr. temporal line", "Infr. temporal line"): one crest climbs from the
# frontal bone's zygomatic process up the side of the forehead and parts in two as it nears the coronal suture; the two lines
# arch back over the parietal bone 6 to 9 mm apart and come down behind, the lower one into the supramastoid crest. Read off
# the plate's page (the bands of its shading and the two labels, which the engraver set along them), then put into the head
# frame: (z, y) on the side view.
# The crest on the frontal bone is the front edge of the plate's dark band (the temporal fossa falling away behind it). It leaves
# the cheek bone's hind border at the frontozygomatic suture, leans forward and up, turns upright beside the orbit's roof and
# curves back above: page (730, 1700), (675, 1655), (660, 1600), (670, 1550), (685, 1500), (700, 1460), (725, 1420), (750, 1390),
# (772, 1340). (First drawn as three points from 16 mm higher up: a ruled bar that began in the middle of the forehead's side.)
FRONTAL_CREST = [(64.7, 25.3), (71.3, 28.7), (74.1, 34.1), (74.1, 39.5), (73.7, 45.0), (73.0, 49.4), (71.3, 54.1), (69.3, 57.8), (68.1, 63.4)]
LINE_UPPER = [(67.1, 72.8), (60.1, 80.7), (51.8, 87.3), (43.3, 92.9), (34.4, 97.2), (24.3, 100.1), (13.7, 101.3), (2.6, 99.8), (-7.7, 97.1),
              (-17.4, 92.1), (-27.6, 84.6), (-36.2, 74.5), (-42.4, 62.9), (-45.5, 50.6), (-45.8, 38.8), (-42.6, 28.4)]
LINE_LOWER = [(66.3, 69.2), (59.0, 75.6), (50.5, 81.1), (41.7, 85.7), (32.8, 89.2), (22.5, 91.6), (11.8, 92.0), (0.8, 91.0), (-8.5, 87.9),
              (-17.2, 82.4), (-25.6, 73.4), (-31.6, 62.8), (-34.5, 51.5), (-34.6, 40.7), (-32.2, 31.6), (-31.6, 23.0)]


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def uneven(M, seed, grain):
    n = ndimage.gaussian_filter(np.random.default_rng(seed).standard_normal(M.U.shape), grain / M.cell)
    return n / (n.std() + 1e-9)


def along(M, pts):
    """Distance from a line on the map (mm), and how far along it (0..1) the nearest point lies."""
    L = spline(np.array(pts, float), 0.25)
    d, i = cKDTree(L).query(np.column_stack([M.U.ravel(), M.V.ravel()]))
    return d.reshape(M.U.shape), (i / max(len(L) - 1, 1)).reshape(M.U.shape)


def outer_wall(F, M, x_out=76.0, x_in=30.0):
    """The outer surface of the side of the head over the side view: the first bone met coming in from the side (x, mm).
    Where a line meets none (below the base) the nearest value stands in; then it is faired."""
    xs = np.arange(x_out, x_in, -0.25)
    P = np.stack(np.broadcast_arrays(xs[:, None, None], M.V[None], M.U[None]), -1)        # (x, y, z)
    d = sdf.sample_field(F.D, F.lo, F.h, P.reshape(-1, 3)).reshape(P.shape[:3])
    ins = d < 0
    xw = xs[ins.argmax(0)]
    bad = ~ins.any(0) | ins[0]
    if bad.all():
        return None
    idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
    return ndimage.gaussian_filter(xw[tuple(idx)], 1.5 / M.cell)


def mastoid(F, log=print):
    """The mastoid process: the traced outline, with an outer face that is full in the middle and falls away to the tip,
    and an inner face along the notch for the digastric."""
    M = Map(-42.0, 0.0, -38.0, 10.0, 0.5)                    # u = z, v = y
    reg = M.region(spline(np.array(MASTOID_SIDE, float), 0.5, closed=True))
    y, z = M.V, M.U
    xo = np.interp(y, [-34, -31, -27, -22, -16, -8, 0, 6], [54.6, 57.4, 60.0, 61.7, 62.4, 62.4, 61.4, 61.0])
    zc = np.interp(y, [-33, -30, -22, -12, 0], [-15.5, -16.4, -17.8, -19.5, -21.0])
    hw = np.interp(y, [-33, -30, -22, -12, 0], [6.5, 8.0, 10.5, 13.0, 15.0])
    xo = xo - 1.2 * np.clip(np.abs(z - zc) / hw, 0.0, 1.5) ** 2                 # rounded from front to back
    xi = np.interp(y, [-34, -30, -24, -18, -10, 10], [46.0, 45.5, 44.5, 42.5, 38.0, 38.0])
    # where its outline lies in the bone the process has no edge: its face runs out into the side of the skull that is there
    xw = outer_wall(F, M)
    d, _ = along(M, INSIDE)
    if xw is not None:
        xo = xw + (xo - xw) * smoothstep(d / 10.0)
    xi = np.minimum(xi, xo - 5.0)
    # a blunt cone, not a slab: toward its free borders (front, tip, hind) the two faces close on each other in a quarter-round,
    # widest low down, so that from below the tip is a dome and not a pad with a flat end
    free, _ = along(M, MASTOID_SIDE[:16])
    R = np.interp(y, [-34.0, -27.0, -16.0, -6.0], [6.0, 5.5, 3.2, 2.2])
    t = np.clip(free / R, 0.0, 1.0)
    dome = 1.0 - (1.0 - np.sqrt(t * (2.0 - t))) * smoothstep(d / 7.0)
    xm = 0.5 * (xo + xi) + 0.8 * (1.0 - dome)                 # (the tip leans a little outward of the middle)
    xo, xi = xm + (xo - xm) * dome, xm - (xm - xi) * np.maximum(dome, 0.12)
    F.add(Slab(M, (2, 1, 0), xo, np.minimum(xi, xo - 0.6), reg, round=1.4), 3.0)
    tip = min(MASTOID_SIDE, key=lambda p: p[1])
    log("mastoid process: tip %.1f mm below the Frankfurt plane, %.1f behind the ear hole's upper edge; %.0f mm from front to back at mid-height; outer face out to x %.1f"
        % (-tip[1], -tip[0], 14.0, float(xo[reg < 0].max())))


def ear_hole(F, log=print):
    """The outer ear hole (external acoustic meatus) as the plate draws it, with what stands round it. Call after the
    jaw's socket is cut: the hole's front wall is the socket's back wall."""
    up = (0, 1, 0)
    # the tympanic part is a gutter of bone under and in front of the canal: its wall all the way in, lying against the mastoid behind
    F.add(Tube(np.array([(LIP_X - 2.2, -5.0, -3.2), (50.0, -4.6, -2.5), (42.0, -4.0, -1.7)]), [(0, 6.6), (1, 5.5)], [(0, 6.2), (1, 4.8)], up=up), 1.8, keep=4)
    # under the hole the tympanic part hangs down as a plate between the jaw's socket and the styloid, to its lower border 18 mm
    # below the Frankfurt plane (the lower arc of the ring the side view shows round the hole)
    F.add(Ellipsoid((48.5, -13.4, -0.6), (8.8, 5.6, 1.7), rot((0, 1, 0), 8)), 1.6, keep=4)
    # its free outer border: a thick lip round the front, the floor and the lower back of the hole; no two stretches of it alike
    out = (-1.0, -0.3, 0.3, 0.1, 0.45, -0.1, -0.5, -1.3)
    P = spline(np.array([(LIP_X + o, yy, zz) for o, (zz, yy) in zip(out, LIP)]), 0.6)
    F.add(Tube(P, [(0, 0.9), (0.12, 1.2), (0.27, 1.35), (0.4, 1.55), (0.55, 1.3), (0.68, 1.5), (0.82, 1.2), (1, 0.9)],
               [(0, 1.1), (0.12, 1.6), (0.27, 1.5), (0.4, 2.0), (0.55, 2.25), (0.68, 1.8), (0.82, 1.95), (1, 1.2)], up=(1, 0, 0)), 1.6, keep=4)
    # the post-glenoid process: a small tongue of the squama between the hole and the jaw's socket
    F.add(Ellipsoid((56.2, -3.0, 3.4), (4.2, 2.5, 1.6)), 1.2, keep=4)
    # the canal itself: the traced mouth carried inward, a little forward and upward, narrowing
    M = Map(-12.0, 6.0, -15.0, 4.0, 0.25)
    lean = (0.07, 0.03); w0 = 72.0
    mouth = np.array(MEATUS, float) - np.array(lean) * (w0 - LIP_X)
    F.cut(Prism(M, (2, 1, 0), M.region(spline(mouth, 0.4, closed=True)), w0, 40.5, taper=1.4, lean=lean), 0.9)
    q = np.array(MEATUS, float)
    log("ear hole: %.1f mm from front to back, %.1f high at its mouth; its lip stands at x %.1f" % (np.ptp(q[:, 0]), np.ptp(q[:, 1]), LIP_X))


def styloid(F, log=print):
    """The styloid process in its sheath: slender, a little flattened, never quite straight."""
    P = spline(np.array(STYLOID, float), 0.8)
    F.add(Tube(P, [(0, 3.1), (0.25, 2.4), (0.5, 2.15), (0.8, 1.75), (0.93, 1.3), (1, 0.9)], [(0, 2.7), (0.25, 2.0), (0.5, 1.75), (0.8, 1.4), (0.93, 1.1), (1, 0.8)],
               up=(1, 0, 0)), 2.0, keep=3)
    # the vaginal process: the tympanic part's lower border, split to sheathe the root in front and on the outer side
    F.add(Ellipsoid((43.6, -16.6, 1.3), (4.6, 3.6, 1.4), rot((0, 1, 0), 18)), 1.4, keep=3)
    L = np.linalg.norm(np.diff(P, axis=0), axis=1).sum()
    log("styloid process: %.0f mm long, its tip %.1f mm below the Frankfurt plane" % (L, -STYLOID[-1][1]))


def side_relief(seed, log=print):
    """The small relief of the temporal bone's outer surface as a height map over the side view (mm, + raised)."""
    M = Map(-42.0, 30.0, -37.0, 40.0, 0.25)
    H = np.zeros(M.U.shape)
    slow = uneven(M, seed, 6.0); fine = uneven(M, seed + 1, 1.5)
    d, t = along(M, CREST)                                   # the supramastoid crest: strongest over the ear hole, fading as it climbs
    H += (1.15 - 0.8 * t) * (1.0 + 0.22 * slow) * np.exp(-(d / (1.6 + 0.3 * slow)) ** 2)
    H -= 0.75 * np.exp(-((M.U + 8.7) / 2.3) ** 2 - ((M.V - 0.1) / 1.9) ** 2)        # the suprameatal triangle
    d, t = along(M, FISSURE)
    H -= (0.5 + 0.15 * fine) * np.exp(-(d / 0.55) ** 2)
    d, t = along(M, LIP)                                     # the tympanic part's free border is rough
    H += np.exp(-(d / 2.0) ** 2) * (0.22 * fine + 0.16 * uneven(M, seed + 3, 0.8))
    d, t = along(M, ARTERY)
    H -= 0.32 * (1.0 - 0.55 * t) * np.exp(-(d / (0.9 + 0.2 * slow)) ** 2)
    # the mastoid's outer face: low uneven ridges running up and back from the tip, where the muscles take hold
    reg = M.region(spline(np.array(MASTOID_SIDE, float), 0.5, closed=True))
    on = smoothstep(-(reg + 0.6) / 2.5) * smoothstep((-5.0 - M.V) / 7.0)
    q = 0.86 * M.U + 0.51 * M.V; p = -0.51 * M.U + 0.86 * M.V
    r = np.random.default_rng(seed + 2).uniform(0, 2 * np.pi, 6)
    ridges = (np.sin(2 * np.pi * q / 3.4 + r[0] + 0.8 * np.sin(2 * np.pi * p / 13.0 + r[1]))
              + 0.7 * np.sin(2 * np.pi * q / 5.3 + r[2] + 0.9 * np.sin(2 * np.pi * p / 19.0 + r[3]))
              + 0.5 * np.sin(2 * np.pi * q / 2.3 + r[4] + 0.7 * np.sin(2 * np.pi * p / 9.0 + r[5]))) / 1.6
    H += on * (0.15 + 0.07 * slow) * ridges * np.clip(0.7 + 0.5 * fine, 0.2, 1.4) + on * 0.1 * fine
    return M, ndimage.gaussian_filter(H, 1.0)


def lines_relief(seed, log=print):
    """The temporal crest and lines as a height map over the side view (mm, + raised). The lower line is the muscle's edge: on
    the frontal bone a crest of nearly 1 mm, gentle toward the forehead and steep toward the fossa, with the bone behind it
    hollowed (the front of the temporal fossa, deepest just behind the crest beside the orbit's roof and shallower upward); on
    the parietal a plain low line with the muscle's bed a shade lower inside it. The upper line, where the fascia holds, is
    fainter and broader. Neither is even along its length."""
    M = Map(-62.0, 86.0, 8.0, 108.0, 0.5)
    slow = uneven(M, seed, 9.0); fine = np.clip(uneven(M, seed + 1, 2.5), -1.5, 1.5)
    H = np.zeros(M.U.shape)
    lower, upper = FRONTAL_CREST + LINE_LOWER, FRONTAL_CREST + LINE_UPPER
    seg = lambda L: np.linalg.norm(np.diff(np.array(L, float), axis=0), axis=1).sum()
    tc = seg(FRONTAL_CREST) / seg(lower)                                   # how much of the lower line is the crest on the frontal bone
    reg = M.region(spline(np.array(lower + [(-32.0, 12.0), (20.0, 12.0), (58.0, 14.0)], float), 0.5, closed=True))      # below zero inside the muscle's field
    d, t = along(M, lower)
    high = 0.3 + 0.6 * (1 - smoothstep((t - 0.8 * tc) / (0.6 * tc)))        # strongest on the crest, 0.3 mm on the parietal
    wide = np.where(reg > 0, 1.9, 1.0) + 0.25 * fine
    H += high * smoothstep(t / 0.025) * (1.0 + 0.3 * slow) * np.exp(-(d / wide) ** 2) * (1 - 0.6 * smoothstep((t - 0.85) / 0.15))
    d, t = along(M, upper)
    H += 0.2 * smoothstep((t - 1.1 * tc) / 0.08) * (1.0 + 0.35 * slow) * np.exp(-(d / 2.2) ** 2) * (1 - 0.7 * smoothstep((t - 0.85) / 0.15))
    H -= 0.16 * smoothstep(-reg / 2.5) * np.exp(-(reg / 12.0) ** 2)         # the step down across the lower line, dying away within 12 mm
    dc, _ = along(M, FRONTAL_CREST + LINE_LOWER[:1])
    deep = 2.3 * smoothstep((M.V - 44.0) / 10.0) * (1 - 0.85 * smoothstep((M.V - 38.0) / 26.0))     # (below that the fossa's front is cut back to the braincase behind the crest: fossa_front)
    H -= deep * smoothstep(dc / 3.5) * np.exp(-(dc / 16.0) ** 2) * smoothstep(-reg / 2.0) * (1.0 + 0.15 * slow)
    return M, ndimage.gaussian_filter(H, 1.0)


def fossa_front(F, F0, border, log=print):
    """The front of the temporal fossa: the hollow behind the pillar that bounds the orbit on the outside.

    Nothing drew it before: the pillar was a slab over the front view ten millimetres thick with a flat back, and behind it the
    orbit's outer wall stood up as a plate with a level top, so the pillar ended in a knob with a ledge running back to the
    pterion. The plate (Fig. 188) draws the cheek bone's hind border leaning forward and up into the frontal bone's temporal
    crest (FRONTAL_CREST), with the fossa falling away behind it all the way. Here whatever stands behind that line (border: the
    cheek bone's hind border from above the arch upward, (z, y)) is taken down to the braincase's own surface less a hollow
    that is deepest just behind the line.

    The cut has an edge only along that line. Upward, backward and downward it runs out to nothing over 6 to 8 mm (a first
    cut ended on a level top and an upright hind side, and a second faded out below the top of what it was removing: each
    left a ruled step across the temple, where bone has none). Its hollow has run out by 44 mm, where the relief's
    (lines_relief) begins. It never leaves the orbit's outer wall under 2.5 mm thick."""
    S = Map(40.0, 78.0, 4.0, 59.0, 0.5)                                    # u = z, v = y
    lo = np.asarray(F.lo, float); hi = lo + F.h * (np.array(F.n) - 1)
    if lo[1] > 6.0 or hi[1] < 57.0 or lo[2] > 42.0 or hi[2] < 76.0 or hi[0] < 70.0:
        return False
    xs = np.arange(76.0, 20.0, -0.25)
    P = np.stack(np.broadcast_arrays(xs[:, None, None], S.V[None], S.U[None]), -1).reshape(-1, 3)
    shape = (len(xs),) + S.U.shape

    def outer(A):                         # where the bone is first met coming in from the side, and which samples are bone
        d = sdf.sample_field(A, F.lo, F.h, P).reshape(shape)
        ins = d < 0
        i = np.clip(ins.argmax(0), 1, len(xs) - 1)
        d1 = np.take_along_axis(d, i[None], 0)[0]; d0 = np.take_along_axis(d, (i - 1)[None], 0)[0]
        x = xs[i] + 0.25 * np.where(d0 > d1, -d1 / np.maximum(d0 - d1, 1e-6), 0.0)
        return np.where(ins.any(0), x, 30.0), ins, i

    x0, _, _ = outer(F0)
    x0 = ndimage.gaussian_filter(x0, 1.0 / S.cell)
    xc, ins, ic = outer(F.D)
    edge = list(border) + FRONTAL_CREST[:7] + [(70.3, 58.0)]              # the cheek bone's hind border, then the crest
    dc, _ = along(S, edge)
    # The orbit's outer wall ends at 34 mm; the edge of the face's slab (the frontal bone's zygomatic process, then the crest)
    # stands out of the braincase to about 45 mm and has sunk into it by 52 (skull2.face). The cut runs out between 44 and 54,
    # where there is less and less to step over.
    fade = (1 - smoothstep((S.V - 44.0) / 10.0)) * smoothstep((S.U - 43.0) / 7.0) * smoothstep((S.V - 7.0) / 6.0)
    # Below the frontozygomatic suture the cheek bone's hind border is a plate's free edge: the fossa begins straight behind
    # it. Above, the crest is the lip of a slope: the frontal bone's temporal surface falls away over 7 to 8 mm, not off a cliff.
    fade = fade * smoothstep(dc / (2.0 + 6.0 * smoothstep((S.V - 20.0) / 14.0)))
    # Above the orbit's roof nothing stands in the fossa further than that slope reaches: the cut ends 7 to 17 mm behind the crest.
    fade = fade * (1 - smoothstep((S.V - 32.0) / 6.0) * smoothstep((dc - 7.0) / 10.0))
    # The hollow is deepest at the level of the cheek bone's frontal process and runs out upward over 20 mm: ended over 5 (as it
    # first was) it left a level shelf across the fossa at the height of the orbit's roof, 2.3 mm in 4.
    hollow = 2.6 * smoothstep(dc / 3.0) * np.exp(-(dc / 16.0) ** 2) * (1 - smoothstep((S.V - 24.0) / 20.0)) * smoothstep((S.V - 10.0) / 10.0)
    # Above the orbit's roof there is little or nothing to take away far behind the crest. A cut laid exactly on the surface
    # there planes off its grain where that stands a hair above and leaves it where it lies a hair below: a stitched row of
    # pits across the forehead's side. So up there the cut stops 0.6 mm above the braincase's own surface.
    want = x0 - hollow + 0.6 * smoothstep((S.V - 34.0) / 6.0)
    # no deeper than leaves 2.5 mm of bone under the new surface (the orbit lies inside this wall)
    n = 10
    c = np.cumsum(ins, 0, dtype=np.int32); c = np.concatenate([c, np.repeat(c[-1:], n, 0)], 0)
    thick = (c[n:] - np.concatenate([np.zeros((1,) + S.U.shape, np.int32), c[:-n - 1]], 0)) == n + 1      # bone from this sample to 2.5 mm in
    idx = np.arange(len(xs))[:, None, None]
    it = np.clip(np.floor((xs[0] - want) / 0.25).astype(int), 0, len(xs) - 1)
    okay = thick & (idx <= it[None]) & (idx >= ic[None])
    last = len(xs) - 1 - okay[::-1].argmax(0)
    floor = np.where(okay.any(0), np.where(last >= it, want, xs[last]), xc + 1.0)
    inner = (xc + 1.0) - fade * np.maximum(xc + 1.0 - floor, 0.0)
    reg = S.region(spline(np.array(edge + [(41.0, 58.0), (41.0, 5.0)], float), 0.5, closed=True))
    F.cut(Slab(S, (2, 1, 0), np.full(S.U.shape, 84.0), inner, reg, round=1.2, mirror=False), 1.2)
    took = np.where(reg < 0, xc - inner, 0.0)
    log("front of the temporal fossa: taken back to the braincase behind the cheek bone's hind border and the crest (up to %.1f mm of the pillar's back, a hollow of up to %.1f mm), running out to nothing above, behind and below"
        % (took.max(), (hollow * fade)[reg < 0].max()))
    return True


def press(G, M, H, side, lo=(44.0, -36.0, -41.0), hi=(70.0, 39.0, 29.0)):
    """Push a relief over the side view into the bone's own outer surface on one side of the finished head (side = +1 left, -1 right)."""
    a, b = np.array(lo, float), np.array(hi, float)
    if side < 0:
        a[0], b[0] = -hi[0], -lo[0]
    sl = G.window(a, b)
    if sl is None:
        return False
    X, Y, Z = np.broadcast_arrays(*G.coords(sl))
    D = G.D[sl].astype(np.float32)
    Ds = ndimage.gaussian_filter(D, 0.6 / G.h)
    g = np.gradient(Ds, G.h)
    n = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6
    t = Ds / (n * n)
    u, v = Z - t * g[2], Y - t * g[1]                         # the surface point beside each point of the field
    h = M.smooth_sample(M.smooth(H), u, v)
    w = (1 - smoothstep((np.abs(D) - 2.0) / 2.0)) * smoothstep((side * g[0] / n - 0.25) / 0.35) * (M.outside(u, v) < -1.0)
    G.D[sl] = D - h * w * np.clip(n, 0.6, 1.8)
    return True


def relief(G, log=print):
    """Both sides' small relief, each with its own unevenness. For the whole head's field."""
    done = lines = 0
    for side, seed in ((1, 1390), (-1, 1400)):
        M, H = lines_relief(seed, log)
        lines += press(G, M, H, side, lo=(15.0, 8.0, -62.0), hi=(76.0, 108.0, 86.0))
    if lines:
        log("temporal lines: the crest on the frontal bone and the two lines over the parietal pressed in on %d side(s), %.2f to %.2f mm" % (lines, H.min(), H.max()))
    for side, seed in ((1, 1370), (-1, 1380)):
        M, H = side_relief(seed, log)
        done += press(G, M, H, side)
    if done:
        log("side of the head: crest, triangle, fissure, artery's groove and the mastoid's roughness pressed in on %d side(s), %.2f to %.2f mm" % (done, H.min(), H.max()))
