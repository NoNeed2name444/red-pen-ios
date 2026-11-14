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
    done = 0
    for side, seed in ((1, 1370), (-1, 1380)):
        M, H = side_relief(seed, log)
        done += press(G, M, H, side)
    if done:
        log("side of the head: crest, triangle, fissure, artery's groove and the mastoid's roughness pressed in on %d side(s), %.2f to %.2f mm" % (done, H.min(), H.max()))
