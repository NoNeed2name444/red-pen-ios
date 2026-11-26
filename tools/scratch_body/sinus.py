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
    (6.0, -14.0), (9.0, -5.0), (11.0, 1.5), (13.0, 9.0), (14.6, 15.5),              # the clivus, sloping up and forward to the dorsum's back (foramina.py runs the great opening's front wall up it)
    (15.6, 18.6), (16.6, 19.7), (17.6, 19.6),                                       # the dorsum sellae: a thin plate leaning up from the clivus, its top rounded
    (29.2, 17.8),                                                                   # the tuberculum sellae, a low transverse ridge (between the two: the fossa, FOSSA)
    (30.2, 17.4), (31.4, 16.9), (32.6, 17.0), (33.6, 17.6),                         # the chiasmatic groove, running out at either end to the optic canal
    (34.8, 18.6), (36.0, 19.3), (38.0, 19.8), (40.0, 20.3), (43.0, 20.5),           # its front border and the level part in front (the jugum)
]
# The hypophyseal fossa: a bowl, oval in plan and wider than long, sunk into the rim the dorsum and the tuberculum stand on.
# Its floor is curved both ways (no level part); its walls steepen toward the rim, the dorsum's front face more than the
# front wall, which slopes down from the tuberculum. floor: the deepest point (y); half: half-width; front, back: half-lengths
# in front of and behind the deepest point (z centre); bend, steep: how the floor rises, as floor + bend*r^2 + steep*r^4 at
# r (1 on the oval's edge). wall: the sinus's wall under the floor and front wall (mm), over |x| < 6 and z 18.5 to 28.5.
FOSSA = dict(floor=10.1, centre=23.2, half=7.0, front=4.9, back=4.7, bend=3.4, steep=4.0, lip=4.6, z=(18.5, 28.5), floor_wall=1.0)
# Across the body: (z, half-width at which its upper face turns down its side, the width the side falls over to the middle
# fossa's floor). The dorsum is narrower at its top than at its root; along the fossa the side falls broad and shallow (the
# carotid groove lies on it); in front the face widens to the optic canals at the chiasmatic groove's ends.
SADDLE = [(12.0, 6.0, 3.5), (13.4, 6.0, 5.0), (14.6, 6.0, 6.5), (16.6, 4.6, 7.0), (17.8, 5.2, 7.4), (19.5, 7.0, 8.4),
          (23.5, 7.6, 8.6), (27.0, 7.4, 7.6), (29.2, 7.5, 5.0), (30.4, 7.8, 3.6), (31.6, 8.6, 3.2), (33.0, 9.2, 3.0),
          (34.5, 9.5, 3.0), (36.0, 9.8, 3.0), (38.0, 10.0, 3.0), (44.0, 10.0, 3.0)]
CAROTID_GROOVE = [(14.0, 3.6, 0.0), (17.0, 3.8, 1.2), (20.0, 3.6, 1.6), (23.0, 3.0, 1.0), (26.0, 3.0, 0.9), (29.0, 2.8, 0.7),
                  (31.0, 2.4, 0.3), (33.0, 2.4, 0.0)]       # its course down the body's side, f-wise: (z, how far out of the side's top edge its bottom lies, depth under the slope)


def _smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0.0, None) / k
    return np.minimum(a, b) - h * h * k / 4.0


def _smax(a, b, k):
    return -_smin(-a, -b, k)


def saddle(x, z):
    """The upper face of the sphenoid's body (y, mm) over x >= 0 and z. A rim first: the midline profile (SELLA), bridged
    from the dorsum's top to the tuberculum across the fossa, sagging at the fossa's sides (a saddle: high in front and
    behind, low at the sides, where it opens toward the carotid grooves), and falling away down the body's side, concave
    (steep under the top edge, then easing out into the floor). Into it the fossa is sunk as an oval bowl. Then the
    dorsum's own form (its upper border notched in the middle, its back hollowed across where it runs into the clivus, its
    upper angles the posterior clinoid processes, knobs leaning forward and outward over the notch below them), the middle
    clinoid processes and the carotid groove."""
    from scipy.interpolate import PchipInterpolator as P
    S = np.array(SELLA, float); T = np.array(SADDLE, float); C = np.array(CAROTID_GROOVE, float); f = FOSSA
    zs = np.clip(z, S[0, 0], S[-1, 0]); tc = np.clip(z, T[0, 0], T[-1, 0]); cc = np.clip(z, C[0, 0], C[-1, 0])
    m = P(S[:, 0], S[:, 1])(zs)
    (z0, y0), (z1, y1) = S[7], S[8]                                    # the dorsum's top in front, the tuberculum
    rim = np.where((z > z0) & (z < z1), y0 + (y1 - y0) * (z - z0) / (z1 - z0), m)
    xs, wd = (P(T[:, 0], T[:, k])(tc) for k in (1, 2))
    rim = rim - f["lip"] * np.exp(-((z - f["centre"]) / 3.4) ** 2) * smoothstep(x / xs)
    rim = rim - 0.6 * np.exp(-(x / 1.8) ** 2 - ((z - 16.9) / 1.4) ** 2)                 # the dorsum's upper border, notched in the middle
    rim = rim - 2.0 * np.exp(-(x / 3.6) ** 2 - ((z - 15.0) / 1.1) ** 2)                 # its back hollowed across, running into the clivus
    rim = rim + np.maximum(18.6 - m, 0.0) * smoothstep(x / 9.0) * smoothstep((z - 29.4) / 1.2) * (1.0 - smoothstep((z - 34.4) / 1.4))   # the chiasmatic groove's ends rise toward the optic canals
    s = np.clip((x - xs) / wd, 0.0, 1.0)
    c = 1.0 - smoothstep((z - 17.6) / 2.0)                            # down the side, past the middle fossa's floor: concave beside the dorsum
    y = np.where(x > xs, -2.5 + (rim + 2.5) * (1.0 - (c * (1.0 - (1.0 - s) ** 2) + (1.0 - c) * smoothstep(s))), rim)      # (the notch under the clinoid process), a long slope beside the fossa
    b = f["back"] + (f["front"] - f["back"]) * smoothstep((z - f["centre"]) / 2.0 + 0.5)
    r2 = (x / f["half"]) ** 2 + ((z - f["centre"]) / b) ** 2
    y = _smin(y, f["floor"] + f["bend"] * r2 + f["steep"] * r2 * r2, 1.4)              # the fossa
    xg, dg = xs + P(C[:, 0], C[:, 1])(cc), P(C[:, 0], C[:, 2])(cc) * (z > C[0, 0]) * (z < C[-1, 0])
    y = y - dg * np.exp(-((x - xg) / 2.0) ** 2)                       # the carotid groove: broad and shallow
    y = y - 3.0 * np.exp(-((x - 11.0) / 1.7) ** 2 - ((z - 19.8) / 1.9) ** 2)      # where it begins, over the foramen lacerum's upper mouth (foramina.through opens it here)
    y = y - 2.2 * np.exp(-((x - 6.6) / 1.3) ** 2 - ((z - 15.6) / 1.2) ** 2)            # the abducent notch: the dorsum's side hollowed below the clinoid process
    u, v = ((x - 6.0) + (z - 17.3)) / np.sqrt(2.0), ((x - 6.0) - (z - 17.3)) / np.sqrt(2.0)
    y = _smax(y, 21.2 - 2.6 * ((u / 1.7) ** 2 + (v / 1.15) ** 2), 0.7)  # the posterior clinoid process: a knob at the upper angle, leaning forward and outward
    y = y + 1.0 * np.exp(-((x - 7.2) / 1.1) ** 2 - ((z - 27.8) / 1.0) ** 2)            # the middle clinoid process, at the tuberculum's end
    return y


class Deep:
    """A slab whose distance holds deep inside it. The slab's own distance is the height over the surface scaled by its
    slope: right at the surface, but under a steep side a point 4 mm into the bone read as 1 mm in, so the middle fossa's
    smooth cut (inner.py) beside the saddle left a broad band of field near zero there: ledges and dents on the body's
    side. Here the distance a millimetre and more inside or out is the true one, from the solid's own voxels (0.25 mm);
    at the surface it is the slab's, so the surface is the same. Behind the dorsum (the clivus) it is the slab's alone."""
    def __init__(self, slab, M, top, floor, reg, cell=0.25):
        self.slab, self.bounds = slab, slab.bounds
        lo, hi = np.array(slab.bounds[0], float), np.array(slab.bounds[1], float)
        self.lo, self.cell = lo - 2.0, cell
        ax = [np.arange(self.lo[k], hi[k] + 2.0 + cell, cell) for k in range(3)]
        X, Y, Z = np.meshgrid(*ax, indexing="ij", sparse=True)
        inside = slab(X, Y, Z) < 0
        self.G = np.where(inside, -(ndimage.distance_transform_edt(inside) - 0.5), ndimage.distance_transform_edt(~inside) - 0.5).astype(np.float32) * cell

    def __call__(self, X, Y, Z):
        X, Y, Z = np.broadcast_arrays(X, Y, Z)
        a = self.slab(X, Y, Z)
        P = [(np.abs(X) - self.lo[0]) / self.cell, (Y - self.lo[1]) / self.cell, (Z - self.lo[2]) / self.cell]
        e = ndimage.map_coordinates(self.G, P, order=1, mode="nearest").astype(np.float32)
        w = smoothstep((np.abs(e) - 0.6) / 0.8) * smoothstep((Z - 13.6) / 0.8)
        return (a + w * (e - a)).astype(np.float32)


def body(F, log=print):
    """The upper part of the sphenoid's body, where the sphenoidal sinuses lie. Gray (pp. 147, 148): "Behind the chiasmatic
    groove is an elevation, the tuberculum sellae; and still more posteriorly, a deep depression, the sella turcica, the
    deepest part of which lodges the hypophysis cerebri"; "The anterior boundary of the sella turcica is completed by two
    small eminences, one on either side, called the middle clinoid processes, while the posterior boundary is formed by a
    squareshaped plate of bone, the dorsum sellae, ending at its superior angles in two tubercles, the posterior clinoid
    processes"; "Behind the dorsum sellae is a shallow depression, the clivus, which slopes obliquely backward, and is
    continuous with the groove on the basilar portion of the occipital bone"; on the body's side "a broad groove, curved
    something like the italic letter f", the carotid groove (p. 148; p. 191: "broad, shallow"). The cranial floor ran level
    here, 15 mm of bone whose top stood 16 mm under the optic canals that open beside the tuberculum; the saddle is put where
    the usual measurements have it (its middle 71 mm behind nasion on a line 7 degrees off the Frankfurt plane).
    Its form from the plates (Gray 1918, 300 dpi scan): from above (Fig. 193, 10.3 px/mm on the oval foramen's distance from
    the midline) the fossa runs 10.3 mm from the tuberculum's edge to the dorsum's front edge, its lip some 7 mm out from the
    middle, the carotid groove beside it 10 to 12; in the sagittal section (Fig. 194, 6.85 px/mm on the skull's length) it is
    9.7 mm long, 6.4 mm deep under the tuberculum and 8.8 under the line from the tuberculum to the dorsum's top. Built: 11.0
    long, 7.3 and 7.9 deep; an oval wider than long, its floor concave both ways. It was a box (a level floor, square ends,
    straight sides); now every part of it is rounded. The clivus behind z 13.4 is the old profile's (foramina.py runs the
    great opening's front wall up it), its midline unchanged and its margins raised a little (at most 0.25 mm), so that the
    dorsum's back runs down into it hollowed across. Fig. 145 and the text have the dorsum a square plate, its sides
    hollowed below the clinoid processes. The pit on the dorsum's side over the foramen lacerum is foramina.through's
    funnel, not this."""
    M = Map(0.0, 16.0, 4.0, 45.0, 0.5)                       # u = x, v = z
    P = np.array(SELLA[:8] + [(18.3, 17.2), (19.8, 13.2), (22.0, 11.4), (24.5, 11.0), (27.0, 12.0), (29.3, 15.2), (31.3, 18.3),
                              (33.5, 17.6), (36.0, 19.0), (40.0, 19.8), (43.0, 20.0)], float)     # the profile the box was built on (kept for the clivus)
    mid = np.interp(M.V, P[:, 0], P[:, 1])
    mid = ndimage.gaussian_filter1d(mid, 0.8, axis=1, mode="nearest")
    w0 = 6.5 + 3.5 * smoothstep((M.V - 30.0) / 5.0) + 2.5 * smoothstep((14.0 - M.V) / 6.0)
    fall = 1.0 - smoothstep((M.U - w0 + 1.0) / 7.0)
    knob = 0.9 * np.exp(-((M.U - 6.3) / 1.6) ** 2 - ((M.V - 17.0) / 1.5) ** 2)
    old = -6.0 + (mid + knob + 6.0) * fall                   # the clivus and the level part in front stay as they were,
    old = old + 0.9 * (1.0 - np.exp(-(M.U / 3.5) ** 2)) * (1.0 - smoothstep((M.U - 5.5) / 2.0)) * smoothstep((M.V - 8.5) / 2.0)   # but for a hollow across
    # the clivus's upper part (its margins raised, its middle line where it was), carried up the dorsum's back
    new = ndimage.gaussian_filter(saddle(M.U, M.V), 0.8 / M.cell, mode="nearest")      # (no crease left where the parts meet)
    w = smoothstep((M.V - 13.4) / 1.2) * (1.0 - smoothstep((M.V - 35.5) / 2.0))
    a, b = np.array([9.5, 30.0]), np.array([15.0, 44.0]); u = (b - a) / np.linalg.norm(b - a)          # the optic canal (skull2) seen from above:
    t = np.clip((M.U - a[0]) * u[0] + (M.V - a[1]) * u[1], -0.5, np.linalg.norm(b - a))             # under it the floor stays as it was
    w = w * smoothstep((np.hypot(M.U - a[0] - t * u[0], M.V - a[1] - t * u[1]) - 2.4) / 1.2)
    top = old + w * (new - old)
    reg = M.region(np.array([(-1.0, 5.0), (10.5, 5.0), (15.0, 12.0), (15.0, 44.0), (-1.0, 44.0)], float))
    # (under the saddle the slab stops at the old cranial floor, 1 mm above the Frankfurt plane: its distance is scaled by the
    # upper face's slope, so a slab reaching down to -6.5 under steep sides swelled the roof of the nose 20 mm below)
    floor = -6.5 + 7.5 * smoothstep((M.V - 13.4) / 1.2)
    F.add(Deep(Slab(M, (0, 2, 1), top, floor, reg, round=0.6, mirror=True), M, top, floor, reg), 1.2, keep=4)
    on = (M.U == 0.0) & (M.V > 14.0) & (M.V < 36.0)
    v, y = M.V[on], top[on]
    i = np.argmin(np.where((v > 19) & (v < 28), y, 99)); j = np.argmax(np.where((v > 26) & (v < 31), y, -99)); k = np.argmax(np.where(v < 19, y, -99))
    front = v[np.where((v > k * 0 + v[k]) & (v < v[i]) & (y <= y[j]))[0][0]]
    log("sphenoid's body: the saddle's floor %.1f mm above the Frankfurt plane at z %.1f, the dorsum's top %.1f, the tuberculum %.1f at z %.1f;"
        " the fossa %.1f mm long at the tuberculum's height, %.1f deep under it, %.1f under the line from it to the dorsum's top"
        % (y[i], v[i], y[k], y[j], v[j], v[j] - front, y[j] - y[i], 0.5 * (y[j] + y[k]) - y[i]))


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
    def wall(X, Y, Z):      # 1.6 mm, but 1 under the fossa's floor and front wall (cadaver series: floor 0.9 +- 0.4 mm, front wall 0.8 +- 0.3;
        a, b = FOSSA["z"]  # Lazaridis et al., Clin Anat 2010, doi 10.1002/ca.20984; Fig. 194 draws the floor as a single thin line)
        f = (1.0 - smoothstep((np.abs(X) - FOSSA["half"]) / 2.0)) * smoothstep((Z - a) / 1.5) * (1.0 - smoothstep((Z - b) / 1.5)) * smoothstep((Y - 6.0) / 2.0)
        return 1.6 - (1.6 - FOSSA["floor_wall"]) * f
    got = hollow(G, (min(s * 10.5, 2.5 * s), -8.5, 17.0), (max(s * 10.5, 2.5 * s), 18.5, 43.6), env, wall, 1.0)
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
