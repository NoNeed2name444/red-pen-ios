"""sinus.py: the air sinuses, the hollows inside the bones round the nose.

Read from Gray's Anatomy, 1918 (public domain), "The Accessory Sinuses of the Nose" (pp. 998 to 1000) and the maxilla's
own account (p. 160):
  "The accessory sinuses or air cells of the nose are the frontal, ethmoidal, sphenoidal, and maxillary; they vary in
   size and form in different individuals" (p. 998)
  maxillary  "the largest of the accessory sinuses of the nose, is a pyramidal cavity in the body of the maxilla. Its base
             is formed by the lateral wall of the nasal cavity, and its apex extends into the zygomatic process. Its roof
             or orbital wall is frequently ridged by the infraorbital canal, while its floor is formed by the alveolar
             process"; "projecting into the floor are several conical elevations corresponding with the roots of the
             first and second molar teeth"; "vertical height opposite the first molar tooth, 3.75 cm.; transverse breadth,
             2.5 cm.; antero-posterior depth, 3 cm. In the antero-superior part of its base is an opening through which
             it communicates with the lower part of the hiatus semilunaris" (pp. 999, 1000); "Its walls are everywhere
             exceedingly thin" (p. 160)
  frontal    "situated behind the superciliary arches, are rarely symmetrical, and the septum between them frequently
             deviates to one or other side of the middle line. Their average measurements are as follows: height, 3 cm.;
             breadth, 2.5 cm.; depth from before backward, 2.5 cm. Each opens into the anterior part of the corresponding
             middle meatus of the nose through the frontonasal duct which traverses the anterior part of the labyrinth of
             the ethmoid" (p. 998)

  sphenoidal "contained within the body of the sphenoid vary in size and shape; owing to the lateral displacement of the
             intervening septum they are rarely symmetrical. The following are their average measurements: vertical
             height, 2.2 cm.; transverse breadth, 2 cm.; antero-posterior depth, 2.2 cm."; "Each sinus communicates with
             the sphenoethmoidal recess by means of an aperture in the upper part of its anterior wall." (p. 999)
  ethmoidal  "consist of numerous thin-walled cavities situated in the ethmoidal labyrinth"; "They lie between the upper
             parts of the nasal cavities and the orbits, and are separated from these cavities by thin bony laminae. On
             either side they are arranged in three groups, anterior, middle, and posterior. The anterior and middle
             groups open into the middle meatus of the nose"; "The posterior cells open into the superior meatus under
             cover of the superior nasal concha" (p. 999)

How a sinus is made here. A sinus is not drawn as a shape of its own: it is the inside of its bone. Each is whatever lies
inside a roomy rounded solid (its limits where the bone runs on into the next one) AND deeper than a wall's thickness under
every surface the bone already has. So its walls are the bone's own surfaces seen from within: the orbit's floor is the
upper jaw's sinus's roof, the canal under that floor raises a ridge in it and the sockets of the molars raise cones in its
floor, as Gray describes, without any of that being drawn. Then each sinus is opened into the nose where Gray has it open.

Head frame, millimetres: x to the body's left, y up, z forward. Done on the whole head (skull2.whole), after the halves
are joined, because the two sides are not alike. No wall is thinner than the grid can carry: 1.6 mm on a half-millimetre
grid, though the real ones are a third of that in places.
"""
import numpy as np
from scipy import ndimage
from sdf import Tube, smax, unit, spline, sample_field
from relief import Map, Slab


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Hull:
    """A rounded convex solid: what lies on the inner side of every face, the corners rounded off over k mm. A face is
    (a point on it, its outward direction) for a flat one, or (point, direction, radius) for one bulging outward as part
    of a ball of that radius: no real sinus ends on a ruled plane."""
    def __init__(self, faces, k=3.0):
        self.faces = [(np.asarray(f[0], float), unit(f[1]), f[2] if len(f) > 2 else None) for f in faces]; self.k = k

    def __call__(self, X, Y, Z):
        d = None
        for p, n, R in self.faces:
            if R is None:
                e = (X - p[0]) * n[0] + (Y - p[1]) * n[1] + (Z - p[2]) * n[2]
            else:
                c = p - R * n
                e = np.sqrt((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2) - R
            d = e if d is None else smax(d, e, self.k)
        return d


def uneven(X, Y, Z, seed, amp=0.5, wave=8.0):
    """A slow unevenness (mm) to add to a solid's distance: a few crossing waves, none of them along an axis."""
    rng = np.random.default_rng(seed); out = 0.0
    for _ in range(5):
        d = unit(rng.normal(size=3)); w = wave * rng.uniform(0.7, 1.6); ph = rng.uniform(0, 2 * np.pi)
        out = out + np.sin(2 * np.pi * (X * d[0] + Y * d[1] + Z * d[2]) / w + ph)
    return amp * out / np.sqrt(5.0)


def depth(A, h):
    """How deep each point lies under the bone's surface as it stands (mm; negative in the air)."""
    ins = A < 0
    d = np.where(ins, ndimage.distance_transform_edt(ins) - 0.5, 0.5 - ndimage.distance_transform_edt(~ins)) * h
    return ndimage.gaussian_filter(d.astype(np.float32), 0.8)


def hollow(G, lo, hi, env, wall, k=1.2):
    """Hollow the bone inside the solid `env` (between the corners lo and hi), leaving a wall of `wall` mm (a number, or a
    function of X, Y, Z) under every surface the bone has now. Returns the hollow's size in cm3 and its box, or None."""
    sl = G.window(np.minimum(lo, hi) - 6.0, np.maximum(lo, hi) + 6.0)
    if sl is None:
        return None
    X, Y, Z = G.coords(sl)
    A = G.D[sl]
    w = wall(X, Y, Z) if callable(wall) else wall
    c = smax(env(X, Y, Z), w - depth(A, G.h), k)                # below 0 inside the hollow
    G.D[sl] = np.maximum(A, -c)
    m = c < 0
    if not m.any():
        return None
    box = []
    for j in range(3):
        on = np.where(m.any(axis=tuple(i for i in range(3) if i != j)))[0]
        box.append((float(G.ax[j][sl[j]][on[0]]), float(G.ax[j][sl[j]][on[-1]])))
    return float(m.sum()) * G.h ** 3 / 1000.0, box


# ---- the bone the sinuses lie in (built with the left half: skull2.build) ---------------------------------------------
class Orbit:
    """The orbit's hollow: the funnel from the traced margin to the optic canal, less whatever of it lies inward of the
    ethmoid's orbital plate. Gray (p. 155): the labyrinth's lateral surface "is formed of a thin, smooth, oblong plate, the
    lamina papyracea", which "forms a large part of the medial wall of the orbit". The funnel alone swept in to 5 mm from the
    middle plane at mid-depth and left 8 mm of bone between the two orbits, where a skull has some 25: no room for the
    ethmoid's cells. The plate stands 12 mm from the middle plane in front and 13 behind, a shade full in the middle; in
    front of it the funnel's own wall is left, so the traced margin is untouched and a shallow hollow lies behind the
    margin's inner edge, where the tear sac's fossa is."""
    def __init__(self, funnel):
        self.funnel = funnel; self.bounds = funnel.bounds

    def plate(self, Y, Z):
        return (12.0 + (84.0 - Z) / 38.0 + 0.4 * np.exp(-((Z - 66.0) / 14.0) ** 2 - ((Y - 14.0) / 8.0) ** 2)
                - 4.0 * smoothstep((Z - 82.0) / 7.0))

    def __call__(self, X, Y, Z):
        return smax(self.funnel(X, Y, Z), self.plate(Y, Z) - X, 3.0).astype(np.float32)


def cleft(F, log=print):
    """The nose's narrow upper part, either side of the partition, up to the plate that roofs it. Gray (p. 153): "The
    cribriform plate ... is received into the ethmoidal notch of the frontal bone and roofs in the nasal cavities"; "the
    cribriform plate is narrow and deeply grooved". The nose's chamber ended in a pointed arch 8 to 10 mm above the Frankfurt
    plane under a bar of bone 10 mm thick; the cleft carries it up to 17, leaving a roof of 3 mm (the real plate is a third
    of a millimetre and full of holes: the grid cannot carry that)."""
    F.cut(Tube(np.array([(0, 12.4, 80.0), (0, 12.8, 66.0), (0, 12.4, 51.0)]), [(0, 4.2), (0.5, 4.5), (1, 4.2)], 3.3, up=(0, 1, 0), n=3.0), 1.0)
    log("olfactory cleft: 3.3 mm to either side of the middle plane, up to 17 mm above the Frankfurt plane, from 48 to 83 mm forward")


SELLA = [   # the sphenoid's body from the side, its upper surface in the middle plane: (z, y)
    (6.0, -14.0), (9.0, -5.0), (11.0, 1.5), (13.0, 9.0), (14.6, 15.5),              # the clivus, sloping up and forward to the dorsum's back
    (15.8, 19.2), (17.0, 19.8), (18.3, 17.2),                                       # the dorsum sellae: a plate standing across the body
    (19.8, 13.2), (22.0, 11.4), (24.5, 11.0), (27.0, 12.0), (29.3, 15.2),           # the fossa for the hypophysis
    (31.3, 18.3), (33.5, 17.6), (36.0, 19.0), (40.0, 19.8), (43.0, 20.0),           # tuberculum, the groove for the chiasma, the level part in front
]


def body(F, log=print):
    """The upper part of the sphenoid's body, where the sphenoidal sinuses lie. Gray (pp. 147, 148): "Behind the chiasmatic
    groove is an elevation, the tuberculum sellae; and still more posteriorly, a deep depression, the sella turcica, the
    deepest part of which lodges the hypophysis cerebri"; its hind boundary is "a squareshaped plate of bone, the dorsum
    sellae"; "Behind the dorsum sellae is a shallow depression, the clivus, which slopes obliquely backward, and is
    continuous with the groove on the basilar portion of the occipital bone". The cranial floor ran level here, 15 mm of bone
    whose top stood 16 mm under the optic canals that open beside the tuberculum; the saddle is put where the usual
    measurements have it (its middle 71 mm behind nasion on a line 7 degrees off the Frankfurt plane)."""
    M = Map(0.0, 16.0, 4.0, 45.0, 0.5)                       # u = x, v = z
    P = np.array(SELLA, float)
    mid = np.interp(M.V, P[:, 0], P[:, 1])
    mid = ndimage.gaussian_filter1d(mid, 0.8, axis=1, mode="nearest")
    # across: the saddle is 13 mm wide and the dorsum a little wider at its top (the hind clinoid processes); in front the
    # level part runs out into the small wings; behind, the clivus widens downward
    w0 = 6.5 + 3.5 * smoothstep((M.V - 30.0) / 5.0) + 2.5 * smoothstep((14.0 - M.V) / 6.0)
    fall = 1.0 - smoothstep((M.U - w0 + 1.0) / 7.0)        # (its sides slope away into the middle fossa's floor: no box)
    knob = 0.9 * np.exp(-((M.U - 6.3) / 1.6) ** 2 - ((M.V - 17.0) / 1.5) ** 2)       # the hind clinoid process at the dorsum's corner
    top = -6.0 + (mid + knob + 6.0) * fall
    reg = M.region(np.array([(-1.0, 5.0), (10.5, 5.0), (15.0, 12.0), (15.0, 44.0), (-1.0, 44.0)], float))
    F.add(Slab(M, (0, 2, 1), top, np.full_like(top, -6.5), reg, round=0.6, mirror=True), 1.2, keep=4)
    log("sphenoid's body: the saddle's floor %.1f mm above the Frankfurt plane, the dorsum's top %.1f, the tuberculum %.1f"
        % (P[:, 1][8:13].min(), P[5:8, 1].max(), P[13, 1]))


# ---- the maxillary sinus ---------------------------------------------------------------------------------------------
# Its limits where the upper jaw's body runs on into other bone (left side; the right is its mirror, a little smaller):
# the tooth-bearing process below, the cheek bone outside, the bone under the orbit's apex behind and above, the frontal
# process in front and above. Everywhere else the bone's own surfaces limit it.
MAXILLARY = dict(floor=-33.4, front=80.2, back=47.2, out=41.2, roof=3.4)
MAXILLARY_RIGHT = dict(floor=-32.2, front=79.2, back=47.8, out=40.2, roof=3.0)      # "they vary in size and form"
OSTIUM = [(11.2, -2.4, 69.0), (14.5, -2.8, 68.8), (18.0, -3.4, 68.4)]               # through the nose's side wall, high and forward, under the middle concha


def maxillary(G, side, log=print):
    m = MAXILLARY if side > 0 else MAXILLARY_RIGHT
    s = float(side)
    hull = Hull([((s * 11.0, 0, 0), (-s, 0, 0)),
                 ((s * 24.0, m["roof"], 62.0), (0, 1, 0), 70.0),
                 ((s * 25.0, m["floor"], 61.0), (0, -1, 0), 30.0),       # the floor dips deepest over the first two molars
                 ((s * m["out"], -10.0, 64.0), (s, 0, 0), 24.0),        # the apex, in the root of the cheek bone's process (a face's ball must hold the whole sinus)
                 ((s * 24.0, -14.0, m["front"]), (0, 0, 1), 28.0),
                 ((s * 24.0, -16.0, m["back"]), (0, 0, -1), 28.0),
                 ((0, -5.0, 49.0), (0, 0.75, -0.66)),                   # under the orbit's apex the bone is the palatine's and the sphenoid's
                 ((0, -1.5, 80.0), (0, 0.7, 0.7))], 4.0)                # the frontal process and the tear duct's canal
    seed = 160 if side > 0 else 161
    # the wall: 1.6 mm, and 2.2 over the teeth's sockets (their roots raise cones in the floor)
    got = hollow(G, (s * 11.0, m["floor"], m["back"]), (s * m["out"], m["roof"], m["front"]),
                 lambda X, Y, Z: hull(X, Y, Z) + uneven(X, Y, Z, seed, 0.5, 9.0),
                 lambda X, Y, Z: 1.6 + 0.6 * smoothstep((-23.0 - Y) / 5.0) + 0 * X + 0 * Z)
    if got is None:
        return None
    # the opening into the middle meatus: a short oval passage through the nose's side wall
    G.cut(Tube(spline(np.array(OSTIUM, float) * np.array([s, 1.0, 1.0]), 0.8), 1.4, 2.0, up=(0, 1, 0)), 0.6)
    vol, box = got
    log("maxillary sinus, %s: %.1f cm3; %.0f mm high, %.0f across, %.0f from front to back; opens by a passage 4 by 3 mm into the middle meatus"
        % ("left" if side > 0 else "right", vol, box[1][1] - box[1][0], box[0][1] - box[0][0], box[2][1] - box[2][0]))
    return vol


# ---- the frontal sinuses ----------------------------------------------------------------------------------------------
# Seen from in front each is a fan of lobes with a scalloped upper edge; the left the larger here, and the partition between
# them leaning to the right as it rises, so the left one crosses the middle plane above. Front to back they are limited by
# the bone's own two tables. Each lobe: (x, y, half-breadth, half-height).
FRONTAL = {1: [(5.6, 30.0, 4.9, 9.4), (10.6, 29.6, 5.0, 8.8), (15.4, 27.8, 4.4, 6.4), (2.6, 38.6, 4.4, 6.6), (8.4, 38.4, 3.6, 5.0)],
           -1: [(-5.0, 28.8, 4.6, 7.8), (-9.8, 27.6, 4.4, 6.2), (-6.4, 35.2, 3.4, 4.4)]}
DUCT = {1: [(5.2, 22.6, 88.4), (6.0, 17.0, 85.4), (7.4, 11.0, 81.6), (8.8, 5.2, 78.2), (9.8, 0.2, 76.2)],      # the frontonasal duct, down and back through
        -1: [(-4.8, 22.4, 88.0), (-5.8, 16.6, 85.0), (-7.4, 10.6, 81.2), (-8.9, 5.0, 77.8), (-9.9, 0.0, 75.6)]}   # the front of the labyrinth into the middle meatus


def frontal_septum(Y, Z):
    """Where the partition between the two frontal sinuses stands (x): leaning to the right as it rises, and not flat."""
    return 0.4 - 0.13 * (Y - 22.0) + 0.8 * np.sin((Z - 79.0) / 4.6) + 0.5 * np.sin((Y - 20.0) / 5.3)


def frontal(G, side, log=print):
    from sdf import Ellipsoid
    lobes = [Ellipsoid((x, y, 90.6 + 0.12 * (40.0 - y)), (rx + 0.6, ry, 9.6)) for x, y, rx, ry in FRONTAL[side]]
    s = float(side); seed = 170 if side > 0 else 171

    def env(X, Y, Z):
        d = None
        for e in lobes:
            v = e(X, Y, Z)
            d = v if d is None else -smax(-d, -v, 1.6)       # the lobes run together, a low ridge between each two
        return smax(d + uneven(X, Y, Z, seed, 0.35, 6.0), 0.9 - s * (X - frontal_septum(Y, Z)), 1.0)      # the partition between the two sinuses
    lo = (min(x - rx for x, _, rx, _ in FRONTAL[side]) - 1.0, min(y - ry for _, y, _, ry in FRONTAL[side]), 79.0)
    hi = (max(x + rx for x, _, rx, _ in FRONTAL[side]) + 1.0, max(y + ry for _, y, _, ry in FRONTAL[side]), 102.0)
    got = hollow(G, lo, hi, env, 2.0, 1.0)
    if got is None:
        return None
    G.cut(Tube(spline(np.array(DUCT[side], float), 0.8), [(0, 1.5), (0.3, 1.25), (1, 1.3)]), 0.6)
    vol, box = got
    log("frontal sinus, %s: %.1f cm3; %.0f mm high, %.0f across, %.0f from front to back; its duct runs down through the labyrinth's front into the middle meatus"
        % ("left" if side > 0 else "right", vol, box[1][1] - box[1][0], box[0][1] - box[0][0], box[2][1] - box[2][0]))
    return vol


# ---- the sphenoidal sinuses -------------------------------------------------------------------------------------------
APERTURE = {1: [(3.6, 10.2, 40.5), (3.0, 10.8, 44.5), (2.5, 11.4, 48.6)],          # from the upper part of each sinus's front wall
            -1: [(-3.9, 9.4, 40.5), (-3.1, 10.4, 44.5), (-2.6, 11.2, 48.6)]}       # forward into the recess above the nose's back


def sphenoid_septum(Y, Z):
    """Where the partition between the two sphenoidal sinuses stands (x): to the left of the middle plane, so the right
    sinus is the larger, and bent."""
    return 1.7 + 0.08 * (Z - 30.0) + 0.9 * np.sin((Z - 20.0) / 5.0) + 0.6 * np.sin((Y - 2.0) / 4.4)


def sphenoidal(G, side, log=print):
    s = float(side)
    hull = Hull([((0, 18.5, 30.0), (0, 1, 0), 60.0), ((0, -8.5, 30.0), (0, -1, 0), 40.0),
                 ((s * 10.5, 5.0, 30.0), (s, 0, 0), 26.0),
                 ((0, 6.0, 43.6), (0, 0, 1), 34.0), ((0, 4.0, 17.0), (0, 0, -1), 30.0)], 3.0)
    seed = 180 if side > 0 else 181

    def env(X, Y, Z):
        return smax(hull(X, Y, Z) + uneven(X, Y, Z, seed, 0.45, 7.0), 0.8 - s * (X - sphenoid_septum(Y, Z)), 1.0)
    got = hollow(G, (min(s * 10.5, 2.5 * s), -8.5, 17.0), (max(s * 10.5, 2.5 * s), 18.5, 43.6), env, 1.6, 1.0)
    if got is None:
        return None
    G.cut(Tube(spline(np.array(APERTURE[side], float), 0.8), 1.3), 0.5)
    vol, box = got
    log("sphenoidal sinus, %s: %.1f cm3; %.0f mm high, %.0f across, %.0f from front to back; opens forward by an aperture high in its front wall"
        % ("left" if side > 0 else "right", vol, box[1][1] - box[1][0], box[0][1] - box[0][0], box[2][1] - box[2][0]))
    return vol


# ---- the ethmoidal cells ----------------------------------------------------------------------------------------------
# Each labyrinth is a honeycomb, not one hollow: the cells are the rooms left between thin partitions. They are set out
# here from a point inside each: (x, y, z, size); a cell is what lies nearer its own point than any other's, counted from
# each point's own size, so a larger cell's partitions bulge into its smaller neighbours, and the whole is bent a little
# so that no partition is a ruled plane. Three groups from front to back, as Gray has them: the front cells small and
# many, the middle group with one large cell low down (the bulla), the hind cells fewer and larger. `to` says where a
# cell opens: "meatus" (down into the middle meatus under the labyrinth), "upper" (through the labyrinth's inner plate
# into the nose's upper passage), or the number of the cell it opens into.
CELLS = {
    1: [("anterior", (8.8, 6.6, 80.0, 0.0), "meatus"), ("anterior", (7.6, 13.6, 81.2, 0.3), 0), ("anterior", (8.4, 20.8, 79.2, 0.0), 1),
        ("anterior", (9.2, 9.8, 74.4, 0.6), "meatus"), ("anterior", (7.4, 18.2, 73.8, 0.2), 3),
        ("middle", (8.9, 7.6, 67.0, 1.4), "meatus"), ("middle", (7.8, 17.8, 66.4, 0.4), 5), ("middle", (8.6, 12.6, 60.8, 0.0), "meatus"),
        ("posterior", (8.4, 7.8, 54.8, 1.0), "upper"), ("posterior", (8.2, 18.6, 56.4, 1.2), 8), ("posterior", (9.0, 12.8, 48.8, 0.8), "upper")],
    -1: [("anterior", (-8.4, 7.4, 79.2, 0.4), "meatus"), ("anterior", (-8.0, 15.8, 80.4, 0.0), 0), ("anterior", (-9.0, 10.6, 73.2, 0.0), "meatus"),
         ("anterior", (-7.6, 19.6, 75.0, 0.5), 2),
         ("middle", (-8.6, 6.8, 65.6, 1.1), "meatus"), ("middle", (-8.2, 15.4, 68.2, 0.0), 4), ("middle", (-7.6, 20.4, 62.4, 0.6), 7),
         ("middle", (-9.0, 10.4, 59.4, 0.3), "meatus"),
         ("posterior", (-8.2, 8.4, 53.0, 0.6), "upper"), ("posterior", (-8.6, 17.2, 54.4, 1.4), 8), ("posterior", (-8.8, 9.6, 47.8, 0.2), "upper"),
         ("posterior", (-8.0, 19.0, 48.4, 0.7), 10)],
}


def ethmoidal(G, side, log=print, before=None):
    s = float(side); seed = 190 if side > 0 else 191
    cells = CELLS[side]
    hull = Hull([((s * 2.6, 0, 0), (-s, 0, 0)), ((s * 13.6, 0, 0), (s, 0, 0)), ((0, 1.0, 64.0), (0, -1, 0), 80.0), ((0, 29.0, 0), (0, 1, 0)),
                 ((0, 0, 83.0), (0, 0, 1)), ((0, 0, 46.2), (0, 0, -1))], 2.0)

    def env(X, Y, Z):
        Xw = X + uneven(X, Y, Z, seed + 10, 0.9, 7.0); Yw = Y + uneven(X, Y, Z, seed + 20, 1.2, 7.5); Zw = Z + uneven(X, Y, Z, seed + 30, 1.3, 8.0)
        d1 = None; d2 = None
        for _, (x, y, z, r), _ in cells:                      # the nearest and second nearest points, each counted from its own size
            d = np.sqrt((Xw - x) ** 2 + (Yw - y) ** 2 + (Zw - z) ** 2) - r
            if d1 is None:
                d1 = d; d2 = np.full_like(d, 1e9)
            else:
                d2 = np.minimum(d2, np.maximum(d1, d)); d1 = np.minimum(d1, d)
        return smax(hull(X, Y, Z), 0.75 - 0.5 * (d2 - d1), 1.4)          # a partition some 1.5 mm thick between any two cells, each cell's corners rounded
    got = hollow(G, (min(s * 2.6, s * 13.6), 1.0, 46.2), (max(s * 2.6, s * 13.6), 29.0, 83.0), env, 1.5, 1.0)
    if got is None:
        return None
    for _, (x, y, z, r), to in cells:
        q = np.array([x, y, z])
        if to == "meatus":                                    # straight down to the middle meatus: the air next inside the nose's side wall, under the concha's root
            zt = z - 1.0; xs = np.arange(14.0, 2.0, -0.25)
            d = sample_field(before[0], before[1], G.h, np.column_stack([s * xs, np.full_like(xs, -2.5), np.full_like(xs, zt)]))
            on = np.where(d >= 0.4)[0]
            if len(on):
                G.cut(Tube(np.array([q, (s * (xs[on[0]] - 0.9), -2.5, zt)]), 1.1), 0.4)
        elif to == "upper":
            zt = max(z, 50.6)
            G.cut(Tube(spline(np.array([q, (s * 5.2, y + 1.6, 0.5 * (z + zt)), (s * 2.4, min(y + 2.6, 15.6), zt)]), 0.8), 1.1), 0.4)
        else:
            G.cut(Tube(np.array([q, np.array(cells[to][1][:3])]), 1.0), 0.4)
    vol, box = got
    n = {g: sum(1 for c in cells if c[0] == g) for g in ("anterior", "middle", "posterior")}
    log("ethmoidal cells, %s: %d in front, %d in the middle, %d behind; %.1f cm3 together, in a labyrinth %.0f mm long and %.0f high; partitions 1.5 mm"
        % ("left" if side > 0 else "right", n["anterior"], n["middle"], n["posterior"], vol, box[2][1] - box[2][0], box[1][1] - box[1][0]))
    return vol


FACE = ((-50.0, -40.0, 8.0), (50.0, 56.0, 108.0))               # the block of the head all of these lie in


def air(G, log=print):
    """Every sinus, cut into the whole head's field G (skull2.whole). The order matters: each keeps its wall from all that
    was cut before it. Last, any hollow left shut off from the outside is filled again: a sinus is an open room, and a
    shut bubble inside a bone would be no part of its surface."""
    sl = G.window(*[np.array(c) for c in FACE])
    if sl is None:
        return {}
    D0 = G.D[sl].copy(); lo = np.array([float(G.ax[k][sl[k]][0]) for k in range(3)])
    out = {}
    for name, f in (("maxillary", maxillary), ("frontal", frontal), ("sphenoidal", sphenoidal)):
        for side in (1, -1):
            out[name, side] = f(G, side, log)
    for side in (1, -1):
        out["ethmoidal", side] = ethmoidal(G, side, log, before=(D0, lo))
    A = G.D[sl] >= 0
    lab, n = ndimage.label(A)
    if n > 1:
        size = ndimage.sum(A, lab, range(1, n + 1)); keep = int(np.argmax(size)) + 1
        shut = A & (lab != keep) & (D0 < 0)                   # air now, bone before, and not joined to the outside
        if shut.any():
            G.D[sl] = np.where(shut, D0, G.D[sl])
        out["filled again"] = float(shut.sum()) * G.h ** 3 / 1000.0
        log("sinuses: every hollow opens to the outside; %.2f cm3 of shut-off pockets filled again" % out["filled again"])
    return out
