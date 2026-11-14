"""nose.py: what stands inside the nose's opening: the partition down the middle and the scrolls on the side walls.

Read from Gray's Anatomy, 1918 (public domain):
  Fig. 195  the medial wall: the perpendicular plate of the ethmoid above, the vomer below and behind, and in front
            the three-cornered gap between them that the cartilage fills in life (so the bony partition's front
            edge lies well back from the opening, deepest about a third of the way up)
  Fig. 196  the lateral wall: the inferior concha, a bone of its own, long and low, hung by its upper border, its
            lower border free and arched; the middle concha (ethmoid) above it, shorter, further back
  Fig. 190  how much of them shows through the opening from in front
  p. 194    the partition "is frequently deflected to one or other side, more often to the left than to the right"

Head frame, millimetres: x to the body's left, y up, z forward. The conchae are built with the left half; the
partition is put in after the halves are joined (skull2.whole), because a bowed sheet is not the same on both sides.
Nothing here is thinner than the grid can carry: on a 0.5 mm grid a sheet of bone is 1.3 mm, though the real ones
are a third of that; a finer grid may take `sheet` down.
"""
import numpy as np
from scipy import ndimage
import sdf
from sdf import spline
from relief import Map, Slab

SEPTUM = [   # the bony partition seen from the side: (z, y), closed, starting under the tip of the nasal bones
    (104.0, 8.5), (97.0, 3.2), (89.0, -3.2), (81.5, -9.2), (76.5, -12.6),      # front edge of the perpendicular plate, down and back to the gap's corner
    (81.0, -16.4), (87.0, -21.0), (93.0, -25.0), (97.6, -27.3),                 # front edge of the vomer, down and forward to the crest behind the spine
    (98.0, -30.5), (84.0, -30.5), (77.0, -29.4), (71.0, -27.0), (60.0, -26.0), (50.0, -25.9), (43.6, -26.5),   # its foot, sunk in the crest along the floor: never below the palate's own middle
    (42.6, -24.4), (40.9, -21.4), (39.0, -17.6), (36.9, -14.2),  # the vomer's free hind edge: hollowed ("free, concave"), up and back
    (34.5, -11.3), (32.4, -9.3), (30.8, -8.0),                                  # under the sphenoid's body (Fig. 187: the wings end at z 28)
    (29.5, -5.0), (45.0, -2.0), (47.0, 15.0), (90.0, 15.0), (100.0, 12.0),      # sunk under the sphenoid's body, the roof and the nasal bones
]
BOW = 1.3            # mm to the left at the middle of the sheet

INFERIOR = dict(     # the inferior concha: its attached upper border and its free lower border, (z, y), front to back
    top=[(86.5, -13.6), (80.0, -13.6), (68.0, -14.6), (56.0, -16.2), (46.5, -17.4)],
    bottom=[(87.0, -17.6), (84.2, -20.4), (76.0, -22.6), (66.0, -23.4), (56.0, -22.8), (49.5, -21.6), (46.0, -20.6)],
    bulge=6.0, lift=0.0)
MIDDLE = dict(       # the middle concha: hangs from the ethmoid, shorter, its front end further back
    top=[(77.0, 3.0), (68.0, 2.2), (58.0, 0.2), (47.0, -3.0)],
    bottom=[(77.5, -1.0), (74.0, -4.8), (66.0, -8.6), (58.0, -9.6), (51.0, -9.0), (46.5, -7.0)],
    bulge=4.0, lift=0.0)


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def septum(h=0.5, log=print):
    """The partition as one thin sheet about the middle plane, bowed a little to the left. For the whole head's field."""
    M = Map(25.0, 108.0, -34.0, 18.0, 0.5)                   # u = z, v = y
    reg = M.region(spline(np.array(SEPTUM, float), 0.5, closed=True))
    sheet = max(1.5, 3.0 * h)
    bow = BOW * np.exp(-((M.U - 68.0) / 17.0) ** 2 - ((M.V + 13.0) / 9.5) ** 2)
    # thicker where it stands on the crest of the floor and where it meets the roof; thin and sharp at its free edges
    half = 0.5 * sheet + 0.55 * smoothstep((-24.0 - M.V) / 4.0) * smoothstep((M.U - 45.0) / 8.0) + 0.3 * smoothstep((M.V - 6.0) / 6.0)   # (its free hind edge stays thin to its foot)
    # the vomer's hind border "is thick and bifid above, thin below": toward the sphenoid's body it spreads into the two wings (alae)
    # that clasp the body's beak; seen from behind a Y, not a T
    half = half + 3.1 * smoothstep((M.V + 14.5) / 6.0) ** 2 * smoothstep((45.0 - M.U) / 7.0)
    log("septum: a sheet %.1f mm thick, bowed %.1f mm to the left; its front edge lies %.0f mm behind the nasal spine at the gap's corner"
        % (sheet, BOW, 100.0 - min(p[0] for p in SEPTUM[:9])))
    return Slab(M, (2, 1, 0), bow + half, bow - half, reg, round=min(0.5, 0.38 * sheet), mirror=False)


def side_wall(F, M, x0=1.5, x1=26.0):
    """The nose's side wall over the side view: the first bone met going outward from the middle plane (mm from it).
    Read off the half-built field, so the scrolls hang from the wall that is really there."""
    xs = np.arange(x0, x1, 0.25)
    P = np.stack(np.broadcast_arrays(xs[:, None, None], M.V[None], M.U[None]), -1)        # (x, y, z)
    d = sdf.sample_field(F.D, F.lo, F.h, P.reshape(-1, 3)).reshape(P.shape[:3])
    ins = d < 0
    k = ins.argmax(0); none = ~ins.any(0) | ins[0]
    xw = xs[k]
    xw[none] = np.nan
    # holes (openings in the wall) take their neighbours' value; then the wall is faired
    bad = np.isnan(xw)
    if bad.all():
        return None
    idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
    xw = xw[tuple(idx)]
    return ndimage.gaussian_filter(xw, 1.2 / M.cell)


def scroll(F, M, xw, spec, h, name, log=print):
    """One concha: a thin sheet hung from the side wall along its upper border, bellied toward the partition, its free
    lower border turned back outward and rolled thick, pointed at both ends."""
    top = np.array(spec["top"], float); bot = np.array(spec["bottom"], float)
    zf, zb = top[0, 0], top[-1, 0]
    ot = np.argsort(top[:, 0]); ob = np.argsort(bot[:, 0])
    ytop = np.interp(M.U, top[ot, 0], top[ot, 1]); ybot = np.interp(M.U, bot[ob, 0], bot[ob, 1])
    t = (ytop - M.V) / np.maximum(ytop - ybot, 1.0)                                       # 0 at the attached border, 1 at the free one
    s = np.clip((M.U - zb) / (zf - zb), 0.0, 1.0)                                         # 0 at the hind end, 1 at the front
    ends = smoothstep((s + 0.06) / 0.26) * smoothstep((1.06 - s) / 0.2)
    # the wall the sheet hangs from: the side wall's own place along the attached border
    xtop = M.sample(xw, M.U, ytop + 0.5)
    # across the sheet, from the attached border down: out from the wall and round to hang nearly straight, the free border
    # turned back a little toward the wall but well clear of it (the passage under the scroll stays open below)
    tt = np.clip(t, -0.5, 1.2)
    prof = np.where(tt < 0.55, np.sin(0.5 * np.pi * tt / 0.55), 1.0 - 0.12 * ((tt - 0.55) / 0.45) ** 2)
    belly = spec["bulge"] * (0.4 + 0.6 * ends) * prof
    sheet = max(2.0, 4.0 * h)                                                             # (the bone itself is under a millimetre: a 0.5 mm grid tears anything thinner than this)
    thick = sheet + 0.6 * ends * smoothstep((t - 0.5) / 0.5)                               # the free border is rolled
    inner = xtop - belly                                                                  # the face toward the partition
    outer = inner + thick * np.minimum(M.slope(ndimage.gaussian_filter(inner, 1.0)), 2.6)  # `thick` is measured square to the sheet, not along x
    outer = np.minimum(outer, xw + 1.2)                                                   # never through the wall it hangs from (it showed as a pimple on the face beside the opening)
    up = top.copy(); up[:, 1] += 2.2                                                      # above the attached border the sheet runs into the wall
    poly = np.concatenate([up, bot[::-1]])
    reg = M.region(spline(poly, 0.5, closed=True))
    slab = Slab(M, (2, 1, 0), outer, inner, reg, round=min(0.95, 0.46 * sheet))
    F.add(slab, 0.9, keep=3)
    conchae.solids[name] = slab                       # kept: bones.py marks the scroll off as a bone of its own
    mid = len(top) // 2
    log("%s: %.0f mm long, %.1f high in the middle, bellied %.1f mm from the wall (wall at x %.1f there)"
        % (name, zf - zb, float(np.interp(top[mid, 0], bot[ob, 0], bot[ob, 1]) * -1 + top[mid, 1]), spec["bulge"],
           float(M.sample(xw, np.array([top[mid, 0]]), np.array([top[mid, 1]]))[0])))


def conchae(F, log=print):
    """Both scrolls of the left side wall, hung on the half-built field (call after the nose's hollow is cut)."""
    M = Map(40.0, 96.0, -30.0, 10.0, 0.5)                   # u = z, v = y
    xw = side_wall(F, M)
    conchae.solids, conchae.wall = {}, (M, xw)
    if xw is None:
        return
    scroll(F, M, xw, INFERIOR, F.h, "inferior concha", log)
    scroll(F, M, xw, MIDDLE, F.h, "middle concha", log)
