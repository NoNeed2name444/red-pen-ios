"""temporal.py: the side of the head round the ear: the mastoid process, the ear opening and the tympanic part round it,
the crest over it, the styloid.

Read from Gray's Anatomy, 1918 (public domain):
  Fig. 188  the skull from the side, put into the head frame (plates.side_frame): where each thing lies and how large
            it is. The mastoid's outline, the ear opening's rim and canal, the tympanic part's outline, the crest's line
            and the styloid are traced on it.
  Fig. 137  the temporal bone's outer surface, larger: what each thing is like. The arch's hind root runs back over the
            ear opening and climbs as the supramastoid crest; between the crest and the opening's hind wall lies the
            small hollow of the suprameatal triangle; the opening is a tall arch under the root, the dark canal in its
            upper part, and in front of it and below it the tympanic part's free border, thick and rough, with the
            canal's floor running out behind that border down to the mastoid; a small process (post-glenoid) stands
            between the opening and the jaw's socket; the mastoid's outer face is rough where the muscles take hold;
            the styloid leaves the bone through a sheath (the vaginal process).
  pp. 139-141, 145, 183  the text to those (quoted where the shapes are made).

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
    (-10.8, 1.4), (-12.1, -3.0), (-11.6, -6.4), (-11.1, -9.6), (-11.8, -14.0), (-12.5, -19.0), (-11.3, -23.0), (-10.0, -26.3),   # its front border: the ear opening's hind rim above, then nearly upright
    (-10.4, -29.2), (-12.5, -32.1), (-15.2, -33.3), (-18.4, -32.8),                                              # the blunt tip
    (-21.4, -30.8), (-24.0, -28.0), (-26.8, -25.2), (-30.0, -22.5), (-34.0, -20.0),                              # its hind border, rising to the occipital
    (-37.0, -14.0), (-36.0, -5.0), (-30.0, 2.0), (-18.0, 4.0)]                                                   # inside the bone
CREST = [(14.0, 1.0), (8.0, 1.6), (2.0, 2.3), (-4.0, 3.4), (-10.0, 4.9), (-16.0, 6.8), (-22.0, 9.0), (-28.0, 11.6), (-33.0, 14.6)]
# The ear opening (external acoustic meatus). Gray, p. 183: "Below the posterior root of the zygomatic arch is the elliptical
# orifice of the external acoustic meatus, bounded in front, below, and behind by the tympanic part of the temporal bone";
# p. 145: in section the canal "presents an oval or elliptical shape with the long axis directed downward and slightly
# backward", the tympanic part's "lateral border is free and rough", and "the upper limit of its outer orifice is formed by
# the posterior root of the zygomatic process". So it is no round hole in a ring. Both figures (188, and 137 larger) draw a
# dark oval under the root's smooth overhang, with a rounded hind rim; in front of it and below it the rough end of the
# tympanic plate, a band 3 mm wide that runs down and back to the mastoid's front border 18 mm below the Frankfurt plane,
# and between band and mastoid the canal's floor running out. Read off Fig. 188 (dev/plate_side.py), in the head frame:
LUMEN = [(-5.2, 0.7), (-3.8, 0.0), (-2.9, -1.6), (-2.6, -3.6), (-2.9, -5.6), (-3.8, -7.4), (-5.4, -8.6), (-7.4, -8.7), (-8.9, -7.6),
         (-9.6, -5.7), (-9.7, -3.6), (-9.2, -1.6), (-8.1, 0.0), (-6.6, 0.7)]       # the canal's mouth: 7 mm from front to back, 9.4 high, leaning back below
RIM = [(-2.9, 0.2), (-4.8, 0.9), (-6.8, 1.2), (-9.6, 0.5), (-11.7, -1.4), (-12.3, -3.6), (-11.9, -5.7), (-11.2, -7.6), (-10.9, -9.6),      # the opening's upper and hind rim (the plate's arc)
       (-11.1, -12.0), (-10.4, -14.3), (-8.6, -15.4), (-6.2, -14.4), (-4.2, -12.0), (-2.9, -9.0), (-2.2, -6.0), (-2.0, -3.0), (-2.2, -1.0)]   # closed below it over the tympanic part, which lies lower
TYMPANIC_SIDE = [   # the tympanic part's outer end seen from the side, closed: (z, y)
    (-1.4, 0.2), (0.7, -1.3), (1.5, -4.0), (1.5, -7.0), (1.0, -10.4), (-0.3, -13.5), (-2.3, -16.4), (-4.4, -17.9), (-6.3, -19.1), (-8.2, -18.0), (-10.1, -19.4), (-11.8, -18.7),   # its front edge, down and back to the mastoid (the lower border is not ruled)
    (-13.6, -15.5), (-13.2, -12.0), (-12.8, -9.0), (-13.0, -6.0), (-13.2, -3.6),                                 # under the mastoid's front border (the fissure between them is pressed in)
    (-9.5, -1.5), (-6.0, -0.4), (-3.0, 0.2)]                                                                     # across the canal
BAND = [(0.4, -1.6), (0.8, -4.5), (0.6, -8.0), (-0.3, -11.2), (-1.7, -14.2), (-3.7, -16.5), (-6.5, -17.5), (-9.8, -17.8)]   # the crest of its rough free border
BAND_X = (56.3, 56.9, 56.8, 56.2, 55.3, 54.4, 53.7, 53.4)             # how far out the crest stands: 3 to 4 mm inside the root above it, more below
FISSURE = [(-12.0, -4.0), (-11.3, -8.5), (-11.9, -13.0), (-12.4, -17.5)]   # between the tympanic part and the mastoid
ARTERY = [(-9.0, 9.0), (-10.5, 17.0), (-12.5, 26.0), (-13.5, 34.0)]    # the groove of the middle temporal artery, up the squama
STYLOID = [(41.5, -12.6, -2.9), (41.2, -15.6, -1.9), (41.0, -18.2, -1.0), (40.7, -21.0, 0.0), (40.4, -23.4, 0.7), (40.1, -26.2, 1.9),
              (39.8, -28.9, 3.0), (39.5, -31.4, 4.4), (39.2, -33.6, 5.6), (38.95, -35.3, 6.6)]   # (z, y) of the tip as Fig. 188; bowed and kinked a little
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
# The crest runs on from the pillar's hind border (skull2.PILLAR_HIND, which ends at (69.7, 30.2)) with no corner between: "a curved
# ridge which runs at first forward and upward on the frontal bone, and then curving backward separates the forehead from the
# temporal fossa" (Gray 1918, p. 1288).
FRONTAL_CREST = [(71.9, 34.0), (73.3, 38.2), (73.9, 42.5), (73.6, 46.5), (73.0, 49.4), (71.3, 54.1), (69.3, 57.8), (68.1, 63.4)]
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
    # Below the digastric notch's roof the process is a stout cone flattened from side to side, not a ball (it was a slab whose
    # faces closed on each other in quarter-rounds all round its free border: from below a sphere hung under the skull, and it
    # overhung the notch so that the notch did not show). Gray (p. 141): the mastoid process "is conical in form"; on its medial
    # side "is a deep groove, the mastoid notch (digastric fossa)". Fig. 187 draws the process from the skull's side wall
    # (x 62) in to the notch's lateral lip (x 51), the notch 8 mm across, medial to it the occipital groove. So at each level
    # the section runs from the side outline's front border to its hind border, with a lateral face that is nearly flat and a
    # medial face (the notch's lateral wall) that is convex, the breadth from side to side shrinking to the blunt tip.
    low = smoothstep((-16.5 - y) / 6.5)                         # 0 above the notch's roof, 1 from 23 mm below the plane down
    inside = reg < 0
    zf = np.where(inside, z, -99.0).max(0); zb = np.where(inside, z, 99.0).min(0)   # the outline's front and hind border at each level
    ok = zf > zb
    zf = np.interp(M.V[0], M.V[0][ok], zf[ok]); zb = np.interp(M.V[0], M.V[0][ok], zb[ok])
    u = np.clip((z - zb[None, :]) / np.maximum(zf - zb, 1.0)[None, :], 0.0, 1.0)
    wob = uneven(M, 421, 3.5); wob2 = uneven(M, 422, 1.6)      # no two millimetres of it alike, and not the other side's
    T = np.interp(y, [-34.0, -32.0, -29.0, -26.0, -22.0, -18.0], [3.2, 5.2, 7.6, 9.4, 11.2, 13.5]) * (1.0 + 0.07 * wob)
    g = np.maximum(np.sin(np.pi * np.clip(u ** 0.9, 0.0, 1.0)) ** 0.5, 0.42)                # thickest a little in front of the middle
    xo_low = xo + low * (0.3 * wob2 - 0.5 * np.clip(u - 0.75, 0.0, 1.0) * 4.0 * smoothstep((-24.0 - y) / 6.0))   # the hind border turns in
    xi = xi * (1.0 - low) + np.maximum(xi, xo_low - T * g) * low
    xo = xo * (1.0 - low) + xo_low * low
    xi = ndimage.gaussian_filter(xi, 1.2 / M.cell)            # (no crease where the faces' rules change)
    # the slab ends 23.5 mm below the plane, inside the cone's upper part; the free process below is one smooth cone (a slab's outline and faces met there in
    # ridges and corners, a keel along the bottom and a beak at the front)
    F.add(Slab(M, (2, 1, 0), xo, np.minimum(xi, xo - 0.8), np.maximum(reg, -(y + 23.5)), round=2.0), 3.0)
    # The cone: sections square to its axis, longer front to back than across, the outer face the flatter; its axis leans forward
    # as it comes down, its front and hind borders on the side outline (Fig. 188), its tip 33 mm below the plane and 15 behind
    # the ear hole; from below it runs from the side wall (x 62) in to the notch's lateral lip (x 46 in front to 51 behind, Fig. 187),
    # its tip under the inner half, where the plate's muscle outlines hook round it (x 50, z -12). The
    # sections' sizes do not fall evenly.
    CONE = [(55.6, -16.0, -21.4), (55.9, -19.0, -20.9), (55.7, -22.0, -20.1), (54.8, -24.2, -18.7), (54.0, -26.0, -17.4), (53.2, -27.7, -15.8),
            (52.5, -29.0, -14.5), (51.8, -30.2, -13.3)]
    F.add(Tube(spline(CONE, 0.5), [(0, 9.4), (0.18, 9.2), (0.4, 8.1), (0.55, 7.1), (0.7, 6.5), (0.82, 5.6), (0.92, 4.6), (1, 3.9)],
               [(0, 6.9), (0.18, 6.5), (0.4, 5.7), (0.55, 5.1), (0.7, 4.9), (0.82, 4.1), (0.92, 3.5), (1, 3.1)], up=(0, 0.22, 1.0)), 3.2, keep=4)
    # where the slab runs out into the cone its front border sank in a shallow dent 23 to 25 mm below the plane: filled
    F.add(Ellipsoid((54.6, -24.0, -14.6), (3.2, 3.6, 2.8)), 2.2, keep=4)
    # the notch's lateral lip: Fig. 187 draws it at x 46 where the notch begins (z -14); the cone's front-inner foot is filled out
    # toward it, low down and on the medial side only (the side outline is not touched)
    F.add(Ellipsoid((48.9, -27.2, -14.3), (1.9, 3.4, 2.6)), 1.4, keep=4)
    mastoid_relief(F)
    # the mastoid foramen: a small oblique canal through the bone near its hind border, in front of the occipitomastoid suture
    # (Gray, p. 141: "Near the posterior border of this region is the mastoid foramen"); it opens on the surface as an oval
    # with a short groove leading from it upward and backward (the vein's and the artery's way), not as a punched round hole
    zc, yc = -41.5, -4.5
    xs_ = np.arange(76.0, 40.0, -0.25)
    dd = sdf.sample_field(F.D, F.lo, F.h, np.column_stack([xs_, np.full_like(xs_, yc), np.full_like(xs_, zc)]))
    if (dd < 0).any():
        xc = xs_[np.argmax(dd < 0)]
        F.cut(Tube(spline([(xc + 1.2, yc + 0.3, zc - 0.4), (xc - 1.5, yc - 0.4, zc + 0.6), (xc - 4.5, yc - 1.0, zc + 2.2)], 0.5),
                   [(0, 1.05), (0.4, 0.85), (1, 0.7)], [(0, 0.8), (0.4, 0.65), (1, 0.55)], up=(0, 0.9, -0.44)), 0.4)
        F.cut(Tube(spline([(xc + 0.6, yc + 0.6, zc - 0.6), (xc + 0.5, yc + 2.0, zc - 2.0), (xc + 0.35, yc + 3.1, zc - 3.6)], 0.5),
                   [(0, 0.6), (1, 0.4)], [(0, 0.5), (1, 0.3)], up=(1, 0, 0)), 0.5)
    tip = min(MASTOID_SIDE, key=lambda p: p[1])
    log("mastoid process: tip %.1f mm below the Frankfurt plane, %.1f behind the ear hole's upper edge; a cone flattened from side to side, %.1f to %.1f mm across at 26 and 22 mm below the plane; outer face out to x %.1f"
        % (-tip[1], -tip[0], 9.4, 11.2, float(xo[reg < 0].max())))


def mastoid_relief(F, seed=431):
    """The mastoid's outer and hind face are rough with the attachments of the sternocleidomastoid, splenius capitis and
    longissimus capitis (Fig. 187 hatches the outer face down to the tip): many fine, low, overlapping striae running obliquely
    down and forward with the sternocleidomastoid's fibres, and a few small vascular pits. Nothing stands out singly; the
    outline moves by less than 0.2 mm. Done as a relief on the field near the surface (a displacement of 0.05 to 0.15 mm),
    not as solids added: band-limited noise, long (3 to 8 mm) along the fibres and narrow (0.4 to 1 mm) across them, under an
    envelope that is strongest toward the tip and the hind border and fades to nothing at the region's edges."""
    sl = F.window((49.0, -37.0, -37.0), (66.0, -12.0, -6.0))
    if sl is None:
        return
    X, Y, Z = (np.asarray(a, np.float64) for a in np.broadcast_arrays(*F.coords(sl)))
    D = F.D[sl]
    band = np.abs(D) < 1.4
    if not band.any():
        return
    rng = np.random.default_rng(seed)
    P = np.column_stack([X[band], Y[band], Z[band]])
    def striae(fibre, along, across, seed_):
        f = np.asarray(fibre, float); f /= np.linalg.norm(f)
        e2 = np.cross(f, (1.0, 0.0, 0.0)); e2 /= np.linalg.norm(e2); e3 = np.cross(f, e2)
        Q = P @ np.column_stack([f, e2, e3])
        c = 0.25; q0 = Q.min(0) - 3 * along; n = np.ceil((Q.max(0) + 3 * along - q0) / c).astype(int) + 1
        G = np.random.default_rng(seed_).standard_normal(n).astype(np.float32)
        fine = ndimage.gaussian_filter(G, (along / c, across / c, across / c))
        coarse = ndimage.gaussian_filter(G, (2.5 * along / c, 2.5 * across / c, 2.5 * across / c))
        N = fine - coarse                                        # band-limited: no broad swellings that would move the outline
        v = ndimage.map_coordinates(N, ((Q - q0) / c).T, order=1)
        return v / (v.std() + 1e-9)
    # mostly down and forward (the sternocleidomastoid), some steeper (splenius, longissimus) at the hind border
    n = 0.75 * striae((0.0, -0.78, 0.62), 1.3, 0.22, seed) + 0.45 * striae((0.0, -0.93, 0.36), 0.9, 0.3, seed + 1)
    n = 1.4 * np.tanh(n / 1.4)
    x, y, z = P.T
    env = (smoothstep((x - 52.0) / 3.0)                         # the outer face and the hind border, not the notch's wall
           * smoothstep((-13.0 - y) / 4.0) * smoothstep((y + 35.5) / 2.0)      # fading out at the top and under the tip
           * smoothstep((-10.5 - z) / 2.5) * smoothstep((z + 36.0) / 3.0))     # and at the front border and behind
    amp = 0.06 + 0.06 * smoothstep((-20.0 - y) / 10.0) + 0.03 * smoothstep((-19.0 - z) / 7.0)     # strongest at the tip and hind border
    dD = -amp * env * n
    # a few small vascular pits, eased at the rim
    cand = np.nonzero((np.abs(D[band]) < 0.3) & (env > 0.5))[0]
    for i in rng.choice(cand, size=min(22, len(cand)), replace=False) if len(cand) else []:
        c = P[i]; s = rng.uniform(0.3, 0.45); dep = rng.uniform(0.1, 0.18)
        dD += dep * np.exp(-np.sum((P - c) ** 2, axis=1) / (2 * s * s))
    D[band] = D[band] + dD.astype(np.float32)
    F.D[sl] = D


def behind_crest(F):
    """From below, the tympanic plate is one curved plate with a single crest: behind the crest the plate's under face rises
    steeply and then slopes back down onto the mastoid's front and the ground round the stylomastoid foramen, with no second
    ridge and no flat floor between (the outer end's lower outline, extruded inward, stood 4 mm behind the crest as a second
    rail). Measured on the field as it stands: the crest's line (the lowest bone 4 mm either side of z -1.5 at each x), and the
    under face behind it; then a new under face is set there and the bone is filled up to it or cut back to it."""
    M = Map(42.0, 55.0, -13.0, 1.0, 0.25)                      # u = x, v = z
    X, Zm = M.U, M.V
    ys = np.arange(-30.0, -10.0, 0.25)
    P = np.column_stack([np.repeat(X.ravel(), len(ys)), np.tile(ys, X.size), np.repeat(Zm.ravel(), len(ys))])
    dd = sdf.sample_field(F.D, F.lo, F.h, P).reshape(X.size, len(ys)) < 0
    ye = np.where(dd.any(1), ys[np.argmax(dd, axis=1)], -10.0).reshape(X.shape)     # the under face: first bone met from below
    band = (Zm > -4.0) & (Zm < 0.5)
    yb = np.where(band, ye, 0.0)
    jc = np.argmin(yb, axis=1); zc = M.V[0][jc]; yc = yb[np.arange(M.nu), jc]
    zc = ndimage.gaussian_filter1d(zc, 1.5); yc = ndimage.gaussian_filter1d(yc, 2.0)
    s = zc[:, None] - Zm                                        # how far behind the crest
    wob = uneven(M, 441, 2.0); wob2 = uneven(M, 442, 0.8)
    rise = (3.6 + 0.6 * wob) * smoothstep(s / (2.0 + 0.3 * wob2))                         # the steep back of the crest
    reach = np.interp(X, [42.0, 45.0, 49.0, 52.0, 55.0], [5.5, 7.0, 6.0, 7.5, 5.0]) + 0.8 * wob   # where it has come down again
    fall = smoothstep((s - 2.2) / (reach - 2.2))
    yt = yc[:, None] + rise + 0.25 * wob2
    yt = yt * (1 - fall) + ye * fall
    w = smoothstep((s - 0.5) / 0.8) * smoothstep((X - 42.6) / 1.0) * smoothstep((52.5 - X) / 2.5)   # (the outer end, under the canal, is left as it was)
    keep = ((ye < -10.5) & (ye > -20.5)).astype(float)          # only under bone, and off the mastoid's front (its face falls steeply there)
    w = w * np.clip(ndimage.gaussian_filter(keep, 0.6 / M.cell) * 2.0 - 1.0, 0.0, 1.0)
    yt = ye * (1 - w) + yt * w
    yt = np.clip(ndimage.gaussian_filter(yt, 0.5 / M.cell), -23.0, -12.6)     # (the maps stay in the plate's band, so the solids' reach does too)
    ye_raw = ye; ye = np.clip(ye, -23.0, -12.6)
    reg = np.where((w > 0.02) & (s < reach + 1.0), -1.0, 1.0)
    reg = ndimage.gaussian_filter(reg, 0.5 / M.cell)
    F.cut(Slab(M, (0, 2, 1), yt, np.full(X.shape, -23.0), reg, round=0.5), 0.5)       # (no deeper than the old rail: the field below is left alone)
    # filled only where the trough was, away from the mastoid's steep front (there the smoothed face would hang a fin beside it)
    wf = w * smoothstep((reach - 0.8 - s) / 1.5)
    top = np.minimum(np.full(X.shape, -12.5), ye + 4.0)
    bot = np.where((ye_raw < -20.5) | (ye_raw > -10.5), top + 1.0, yt * wf + np.maximum(yt, ye + 0.3) * (1 - wf))   # (nothing where there was no plate)
    F.add(Slab(M, (0, 2, 1), top, bot, reg, round=0.5), 0.5)
    # two small notches in the crest's edge, unequal, where the plate's border is broken
    for xn, dy, rz in ((47.4, 0.75, 1.1), (44.9, 0.55, 0.8)):
        i = int(round((xn - M.u0) / M.cell))
        F.cut(Ellipsoid((xn, yc[i] - 0.15, zc[i] - 0.2), (0.45, dy + 0.15, rz)), 0.2)


def ear_hole(F, log=print):
    """The outer ear opening (external acoustic meatus) and the tympanic part round it, as Figs. 188 and 137 draw them.
    Call after the jaw's socket is cut: the tympanic part's front face is the socket's back wall."""
    up = (0, 1, 0)
    M = Map(-16.0, 6.0, -23.0, 4.0, 0.25)                    # u = z, v = y
    reg = M.region(spline(np.array(TYMPANIC_SIDE, float), 0.4, closed=True))
    # the tympanic part's outer end: the band's crest, the canal's floor running out behind it (deepest where it enters the
    # canal), the fall to the mastoid's front and round the front edge
    pts = [(z, y, x) for (z, y), x in zip(BAND, BAND_X)]
    pts += [(-1.3, -2.6, 56.5), (-1.5, -6.0, 56.9), (-1.9, -9.6, 56.5), (-2.9, -12.4, 55.7), (-4.6, -14.6, 54.9), (-7.0, -15.8, 54.1),      # the band is 3 mm wide, flat on top
            (-5.6, -10.4, 51.8), (-7.8, -10.8, 51.8), (-9.8, -12.2, 52.6), (-7.6, -13.4, 52.8),                                             # the floor running out
            (-6.0, -4.0, 51.0), (-9.0, -4.5, 51.5),
            (-11.6, -9.0, 53.6), (-12.0, -13.0, 53.6), (-11.8, -16.5, 53.5), (-13.2, -9.0, 54.4), (-13.4, -13.0, 54.2),
            (2.6, -5.0, 55.2), (2.1, -11.0, 54.6), (0.6, -15.2, 53.4), (-2.0, -18.6, 52.6), (-7.0, -19.8, 52.2),
            (0.6, -0.2, 58.6), (-1.2, 0.3, 59.2), (1.6, -1.6, 57.4), (-2.6, -0.6, 58.8)]          # at its top it runs up under the post-glenoid process with no ledge
    xo = M.thin_plate(pts, weight=30.0)
    d, t = along(M, BAND)                                    # the border is thick and rough: no two stretches of it alike
    xo += np.exp(-(d / 4.0) ** 2) * (0.36 * uneven(M, 411, 1.8) + 0.3 * uneven(M, 412, 0.8))
    edge = reg + 0.45 * uneven(M, 413, 1.4) * np.exp(-(d / 3.0) ** 2)      # its front edge is ragged
    # the base's own mass stands further out than this in front of the canal and under it (it was the ground of the old ring):
    # it is taken back to the traced surface, from under the post-glenoid process down and back to the mastoid's front border
    clear = M.region(spline(np.array([(-4.4, -0.4), (-2.2, -0.8), (0.2, -1.8), (1.6, -3.0), (2.3, -4.8), (2.4, -8.0), (1.7, -11.0), (0.4, -14.2), (-1.8, -17.2), (-4.6, -18.8), (-8.0, -19.5),
                                      (-11.6, -19.7), (-12.3, -15.5), (-11.9, -12.0), (-11.6, -9.0), (-12.0, -6.0), (-12.2, -3.4), (-11.0, -1.4), (-9.0, -0.6),
                                      (-6.5, -0.4)], float), 0.4, closed=True))
    F.cut(Slab(M, (2, 1, 0), np.full(M.U.shape, 76.0), xo, clear, round=0.8), 0.8)
    F.add(Slab(M, (2, 1, 0), xo, np.full(M.U.shape, 44.0), edge, round=1.0), 1.0, keep=4)
    # behind its outer end the tympanic part is a plate under the canal with a thin lower border, running inward and forward
    # to the styloid's root, which it sheathes in front (the vaginal process), and on toward the carotid canal
    # Fig. 187 draws its lower border from the canal's outer end in to the styloid's root 2 mm in front of the stylomastoid
    # foramen's level (z -2; the line below is 1 mm further forward, as the plate leans back as it comes down), gently bowed, and at the root it wraps round the front of the styloid as its sheath. (It was a
    # straight plate leaning back to z -6 at the canal, with a rounded bar of a border; its inner end ran on past the root,
    # and where it met the styloid the two webbed into a fan.) The border is thin and rough: its height and thickness change
    # every two or three millimetres, no two stretches alike.
    # Seen from below the crest is one nearly straight, slightly bowed line (Fig. 187) that strays forward and back by 0.2 to
    # 0.4 mm at uneven spacing, with two small notches cut in it below (it was ruled straight, then an even wave); it is
    # thicker out at the canal than in at the root, where it thins and splits round the styloid (the sheath: styloid())
    TP = [(53.4, -12.4, -3.4), (51.6, -12.7, -2.3), (49.8, -12.9, -1.55), (48.0, -13.0, -1.2), (47.1, -13.05, -1.3), (46.2, -13.1, -1.55),
          (44.4, -13.3, -1.3), (42.9, -13.5, -1.6), (41.9, -13.7, -1.15), (41.0, -13.9, -0.6), (40.1, -14.0, 0.2), (39.2, -13.9, 0.9),
          (38.4, -13.7, 1.9), (37.6, -13.5, 2.9)]          # (and on inward toward the carotid canal, as it was)
    TPa = [(0, 5.1), (0.12, 5.45), (0.24, 5.45), (0.36, 5.8), (0.46, 5.6), (0.55, 5.75), (0.67, 6.15), (0.76, 6.4), (0.83, 5.7), (0.92, 5.0), (1, 4.8)]
    TPb = [(0, 1.5), (0.12, 1.05), (0.22, 1.15), (0.34, 1.35), (0.46, 1.2), (0.58, 1.05), (0.68, 1.0), (0.77, 1.3), (0.88, 1.1), (1, 1.2)]
    F.add(Tube(spline(TP, 0.6), TPa, TPb, up=(0.0, 0.985, 0.17), taper=-0.2), 1.8, keep=4)
    behind_crest(F)
    # the petrotympanic fissure: a fine cleft across the fossa's back wall where the tympanic plate meets the squama, 5 to 6 mm
    # below the fossa's roof, behind the articular part. Found on the wall as it stands (the first bone met going forward at
    # that height), then cut as a wavering slit 0.7 mm wide and 1.2 deep that comes and goes (Fig. 187: "Petrotympanic fissure")
    fis = []
    zz = np.arange(-6.0, 9.0, 0.25)
    for xq in np.arange(51.0, 41.4, -0.5):
        yq = np.interp(xq, [41.4, 44.0, 47.0, 50.0, 52.0], [-3.7, -4.1, -4.7, -5.1, -5.3]) + 0.35 * np.sin(xq * 0.9 + 0.6) + 0.15 * np.sin(xq * 2.3 + 2.0)
        dq = sdf.sample_field(F.D, F.lo, F.h, np.column_stack([np.full_like(zz, xq), np.full_like(zz, yq), zz]))
        k = np.nonzero((dq[:-1] < 0) & (dq[1:] >= 0) & (zz[:-1] > -4.0))[0]       # the back wall's face: the first edge met going forward
        if len(k) and zz[k[0]] < 3.0:                      # only on the back wall, never forward into the fossa the jaw's head works in
            fis.append((xq, yq, zz[k[0]] + 0.1))
        elif fis:
            break
    if len(fis) > 4:
        fis = np.array(fis); fis[:, 2] = ndimage.gaussian_filter1d(fis[:, 2], 2.5, mode="nearest")
        n = len(fis); s = np.linspace(0, 1, n)
        # a crack, not a ruled groove: it curves (lower out at the canal, higher in toward the root, so it is not parallel to the
        # crest below), its width comes and goes, and it is broken in two places where the plate and the squama touch
        cuts = [(0.0, 0.42), (0.47, 0.71), (0.76, 1.0)]
        for a, b in cuts:
            seg = fis[int(a * (n - 1)):int(np.ceil(b * (n - 1))) + 1]
            if len(seg) < 3:
                continue
            F.cut(Tube(spline(seg, 0.3), [(0, 0.18), (0.3, 0.34), (0.6, 0.26), (1, 0.16)],
                       [(0, 0.25), (0.2, 0.7), (0.5, 0.9), (0.8, 0.6), (1, 0.25)], up=(0, 1, 0)), 0.2)
    # the post-glenoid process: a small tongue of the squama hanging between the opening and the jaw's socket
    F.add(Ellipsoid((57.6, -1.2, 2.4), (3.4, 1.9, 1.7)), 1.2, keep=4)
    # the canal: the traced mouth carried inward, a little forward and upward, narrowing
    lean = (0.05, 0.03); w0 = 64.0; ref = 57.0
    mouth = np.array(LUMEN, float) - np.array(lean) * (w0 - ref)
    F.cut(Prism(M, (2, 1, 0), M.region(spline(mouth, 0.4, closed=True)), w0, 40.5, taper=0.9, lean=lean), 0.7)
    # its upper and hind rim is no edge and no ring: the root's under side and the mastoid's front turn into the canal over
    # 2 to 3 mm (the lit crescent both figures draw), along the arc traced on the plate; the tympanic part in front and below
    # stands lower and is left as it is
    F.cut(Prism(M, (2, 1, 0), M.region(spline(np.array(RIM, float), 0.4, closed=True)), 63.0, 54.0, taper=2.9), 1.3)
    q = np.array(LUMEN, float)
    log("ear opening: canal %.1f mm from front to back, %.1f high at its mouth; the tympanic part's rough border stands at x %.1f to %.1f and reaches %.1f mm below the Frankfurt plane"
        % (np.ptp(q[:, 0]), np.ptp(q[:, 1]), min(BAND_X), max(BAND_X), -min(p[1] for p in TYMPANIC_SIDE)))


class _Sheath:
    """A thin curved shell about a short axis A-B: radius r_in..r_in+t, over the front and outer side only, its lower rim oblique
    (lowest in front) and uneven."""
    def __init__(self, A, B, r_in=(2.25, 1.75), t=0.8, wrap=0.15):
        self.A, self.B = np.asarray(A, float), np.asarray(B, float)
        self.r_in, self.t, self.wrap = r_in, t, wrap
        r = max(r_in) + t + 1.0
        self.bounds = (np.minimum(self.A, self.B) - r, np.maximum(self.A, self.B) + r)
    def __call__(self, X, Y, Z):
        X, Y, Z = np.broadcast_arrays(X, Y, Z)
        AB = self.B - self.A; Lq = np.linalg.norm(AB); ax = AB / Lq
        R = np.stack([X - self.A[0], Y - self.A[1], Z - self.A[2]], -1)
        s = R @ ax; tq = np.clip(s / Lq, 0.0, 1.0)
        rad = R - tq[..., None] * AB
        rho = np.linalg.norm(rad, axis=-1)
        ri = self.r_in[0] + (self.r_in[1] - self.r_in[0]) * tq
        shell = np.maximum(ri - rho, rho - ri - self.t)
        n = np.array([0.72, 0.0, 0.69]); n = n - ax * (n @ ax); n /= np.linalg.norm(n)
        side = -(rad @ n) / np.maximum(rho, 1e-6) - self.wrap          # < 0 on the front-outer side
        side = side * np.maximum(rho, 0.5)
        e2 = np.cross(ax, n)
        ang = np.arctan2(rad @ e2, rad @ n)
        low = Lq * (0.63 + 0.12 * np.cos(ang) + 0.04 * np.sin(3.1 * ang + 0.7))   # the rim: lowest in front, uneven
        ends = np.maximum(-s, s - low)
        return np.maximum(np.maximum(shell, side), ends).astype(np.float32)


def styloid(F, log=print):
    """The styloid process: a tapering thorn, a little flattened, never quite straight, its root in the tympanic part's sheath."""
    # Gray (p. 145): "The styloid process is slender, pointed, and of varying length; it projects downward and forward". It was a
    # straight machined cone 6.4 mm across at the root, joined to the tympanic plate in a fan of bone (a blend 1.6 mm wide). Now
    # a spine 4.6 mm across where it leaves its sheath and 1.2 at the point, faintly bowed (concave forward) with a small kink
    # and its thickness not falling evenly, set into the bone with a blend of 0.7 mm so that the sheath's edge shows as an edge.
    # Its tip stays where Fig. 188 draws it (z 6.6, y -35.4 there).
    P = spline(np.array(STYLOID, float), 0.5)
    F.add(Tube(P, [(0, 2.4), (0.16, 2.25), (0.3, 1.6), (0.42, 1.38), (0.55, 1.3), (0.66, 1.08), (0.78, 0.95), (0.9, 0.78), (1, 0.62)],
               [(0, 2.2), (0.16, 2.05), (0.3, 1.45), (0.44, 1.32), (0.56, 1.12), (0.68, 1.06), (0.8, 0.86), (0.91, 0.74), (1, 0.6)],
               up=(1, 0, 0.25)), 0.7, keep=3)
    # the vaginal process (Fig. 187 "Vagin. proc."): the tympanic plate's crest, at its inner end, splits and runs down as a thin
    # sheath round the front and outer side of the styloid's root, standing a little off it, its lower rim oblique and uneven
    F.add(_Sheath((41.15, -15.0, -1.95), (40.6, -22.2, 0.35)), 0.4, keep=2)      # (it grows out of the plate: no top edge)
    L = np.linalg.norm(np.diff(P, axis=0), axis=1).sum()
    log("styloid process: %.0f mm long, its tip %.1f mm below the Frankfurt plane" % (L, -STYLOID[-1][1]))


def side_relief(seed, log=print):
    """The small relief of the temporal bone's outer surface as a height map over the side view (mm, + raised)."""
    M = Map(-42.0, 30.0, -37.0, 40.0, 0.25)
    H = np.zeros(M.U.shape)
    slow = uneven(M, seed, 6.0); fine = uneven(M, seed + 1, 1.5)
    d, t = along(M, CREST)                                   # the supramastoid crest: strongest over the ear hole, fading as it climbs
    H += (1.15 - 0.8 * t) * (1.0 + 0.22 * slow) * np.exp(-(d / (1.6 + 0.3 * slow)) ** 2)
    H -= 0.7 * np.exp(-((M.U + 14.0) / 2.3) ** 2 - ((M.V - 1.6) / 1.8) ** 2)         # the suprameatal triangle: behind and above the opening, under the crest (p. 183)
    H += 0.45 * np.exp(-((M.U + 11.6) / 0.9) ** 2 - ((M.V - 0.3) / 0.8) ** 2)       # the small spine on its front border, at the opening's upper hind corner (p. 145: "sometimes seen")
    d, t = along(M, FISSURE)
    H -= (0.5 + 0.15 * fine) * np.exp(-(d / 0.55) ** 2)
    d, t = along(M, BAND)                                    # the tympanic part's free border is rough (each side its own)
    H += np.exp(-(d / 2.2) ** 2) * (0.22 * fine + 0.18 * uneven(M, seed + 3, 0.8))
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
    edge = list(border) + FRONTAL_CREST[:6] + [(70.3, 58.0)]              # the cheek bone's hind border, then the crest
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
