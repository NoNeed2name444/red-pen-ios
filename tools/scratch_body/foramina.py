"""foramina.py: the openings of the skull's base, the condyles beside the great one, and the small relief between them.

Round pipes drilled through the base read as drawn with a compass, and eggs laid on it read as eggs. In a skull
no opening is a circle: the oval foramen is a leaf with a pointed end, the jugular hollow a bean with a domed
roof, the ragged hole (foramen lacerum) is what its name says, and the great opening is an egg that the two
condyles narrow in front. Each mouth is a little funnel with an uneven lip, not a punched edge.

Everything here is read off Gray's Fig. 187 (the base from below, page 179 of the Internet Archive scan at
300 dpi; public domain) in page pixels and turned into millimetres by plates.base_mm. The occipital bone's own
parts (great opening, condyles, the hollow behind them) are fitted to this skull's great opening, whose ends
come from the sagittal section; the temporal and sphenoid openings stand where the plate has them. Where the
plate is too small to give an outline (the small round holes) one is drawn here to the usual size, and said so.
"""
import copy
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import relief, plates, sdf
from sdf import Tube, sample_field

PLATE_BASION_Z, PLATE_OPISTHION_Z = 4.2, -34.5       # the great opening's ends on the plate (mm, plates.base_mm)
BASION_Z, OPISTHION_Z = 4.2, -34.5                   # and on this skull: the plate's own (base.py's midline heights end there)
CONDYLE_LOWEST = -28.5
# the great opening's upper edge on Fig. 193 (upper surface), traced: half width (mm, the plate at 5.2 px/mm, the
# basilar part's cut edge for the midline) at 0, 5, ... 100 % of its length from the basion (length 38.8 mm)
UPPER_193 = [5.2, 7.1, 9.0, 10.2, 10.4, 11.5, 13.1, 15.4, 16.9, 17.9, 18.1, 18.1, 17.9, 17.5, 16.9, 16.1, 14.6, 11.7, 8.1, 4.5, 0.8]                               # the condyle's lowest point (sagittal section, Fig. 194)

# ---- outlines read off the plate (page pixels; close-ups at 3.3 times with a 20-pixel grid) ----
# the great opening as it is seen from below, left half from its front (basion) round to its back (opisthion). In
# front it is narrow: the condyles' inner sides slope up to its edge and take its width
MAGNUM = [(1356, 2066), (1320, 2068), (1290, 2075), (1272, 2086), (1263, 2100), (1258, 2121), (1251, 2151), (1245, 2176),
          (1237, 2206), (1230, 2227), (1221, 2242), (1218, 2266), (1219, 2291), (1214, 2303), (1202, 2315), (1184, 2322),
          (1172, 2333), (1160, 2357), (1148, 2372), (1142, 2394), (1141, 2418), (1142, 2440), (1147, 2470), (1155, 2505),
          (1170, 2540), (1200, 2582), (1240, 2622), (1285, 2650), (1325, 2664), (1356, 2668)]
# the condyle's facet ("articulates with atlas"): a kidney 10 mm wide, its front end beside the opening's front, its
# hind end further out; between its inner border and the opening the plate shows the condyle's sloping inner side
FACET = [(1121, 2063), (1172, 2047), (1202, 2045), (1227, 2057), (1237, 2078), (1236, 2106), (1227, 2130), (1211, 2151),
         (1199, 2163), (1178, 2188), (1166, 2203), (1161, 2218), (1154, 2242), (1151, 2266), (1154, 2291), (1157, 2315),
         (1154, 2333), (1146, 2360), (1142, 2379), (1140, 2400), (1139, 2415), (1124, 2427), (1093, 2434), (1063, 2427),
         (1036, 2412), (1015, 2394), (999, 2372), (992, 2348), (990, 2318), (995, 2285), (1005, 2260), (1018, 2239),
         (1025, 2212), (1033, 2188), (1039, 2157), (1051, 2130), (1072, 2103), (1093, 2079)]
OVALE = [(867, 1846), (898, 1842), (932, 1831), (961, 1817), (986, 1796), (999, 1775), (998, 1762), (994, 1758), (973, 1756),
         (948, 1762), (927, 1777), (907, 1800), (886, 1825)]
LACERUM = [(1050, 1883), (1059, 1854), (1073, 1842), (1092, 1844), (1107, 1854), (1111, 1867), (1111, 1879), (1098, 1890),
           (1078, 1896), (1061, 1894)]
JUGULAR_FOSSA = [(777, 2121), (807, 2102), (848, 2096), (890, 2102), (932, 2117), (957, 2137), (969, 2167), (961, 2183),
                 (948, 2196), (907, 2200), (865, 2198), (823, 2187), (794, 2171), (780, 2146)]
JUGULAR_SLOT = [(975, 2100), (1000, 2085), (1012, 2100), (1014, 2140), (1005, 2165), (985, 2180), (965, 2175), (960, 2150), (966, 2120)]
CAROTID = (937, 2017)             # the middle of the ring the plate draws round its mouth, 6.7 by 7.3 mm (the dark inside it 7.0 by 5.9)
SPINOSUM, STYLOMASTOID, CONDYLAR, HYPOGLOSSAL = (818, 1890), (709, 2209), (1040, 2475), (1050, 2056)
TYMPANIC_CANALICULUS, MASTOID_CANALICULUS, COCHLEAR_AQUEDUCT = (890, 2081), (813, 2135), (961, 2125)
# the cleft between the petrous part and the occipital, from the ragged hole back to the jugular opening; and the
# one between the petrous part and the sphenoid's wing (the groove the auditory tube lies in)
PETRO_OCCIPITAL = [(1111, 1900), (1136, 1933), (1138, 1958), (1115, 1975), (1077, 2017), (1040, 2058), (1006, 2087)]
SPHENO_PETROSAL = [(1050, 1885), (990, 1903), (935, 1917), (880, 1936), (850, 1952), (822, 1984), (800, 1996)]

# ---- drawn here, to the usual size (mm about the middle: (x, z)) ----
ROUNDISH = [(1.00, 0.05), (0.80, 0.62), (0.28, 0.93), (-0.33, 1.02), (-0.84, 0.60), (-1.04, -0.02), (-0.80, -0.58),
            (-0.22, -0.90), (0.42, -0.86), (0.90, -0.50)]                       # a small hole: nearly round, not a circle
BLOB = [(1.0, 0.1), (0.75, 0.7), (0.15, 0.95), (-0.5, 0.8), (-0.95, 0.35), (-1.05, -0.3), (-0.6, -0.8), (0.1, -1.0), (0.7, -0.7)]


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mm(page, occipital=False):
    """Page pixels -> (x, z) in mm. occipital: fitted along z to this skull's great opening."""
    q = plates.base_mm(np.asarray(page, float).reshape(-1, 2))
    if occipital:
        q[:, 1] = OPISTHION_Z + (q[:, 1] - PLATE_OPISTHION_Z) * (BASION_Z - OPISTHION_Z) / (PLATE_BASION_Z - PLATE_OPISTHION_Z)
    return q


def fair(poly, step=0.3):
    """A closed outline drawn smoothly through its points."""
    poly = np.asarray(poly, float)
    return sdf.spline(np.column_stack([poly, np.zeros(len(poly))]), step, closed=True)[:, :2]


def ragged(poly, seed, amount, n=14):
    """An outline with its edge broken up: `amount` of its radius, unevenly, the same every time for one seed.
    The teeth are a millimetre or two long: finer ones would only alias on the grid."""
    P = fair(poly, 0.2); c = P.mean(0)
    P = P[np.linspace(0, len(P), n, endpoint=False).astype(int)]
    j = np.random.default_rng(seed).standard_normal(n); j /= np.abs(j).max()
    return fair(c + (P - c) * (1.0 + amount * j)[:, None], 0.2)


def outline_map(poly, cell=0.25, margin=4.0):
    """A fine map just large enough for one outline (mm, (x, z)), and the outline's signed distance on it."""
    poly = np.asarray(poly, float)
    lo, hi = poly.min(0) - margin, poly.max(0) + margin
    M = relief.Map(lo[0], hi[0], lo[1], hi[1], cell)
    return M, M.region(poly)


def uneven(M, seed, grain=1.2):
    """Smooth noise on a map (unit spread): nothing in a body is ruled."""
    n = ndimage.gaussian_filter(np.random.default_rng(seed).standard_normal(M.U.shape), grain / M.cell)
    return n / (n.std() + 1e-9)


class Opening:
    """A hole pushed up into the bone from its under surface. Its outline is drawn on a map over (x, z); `ys` is
    the height of the bone's under surface on that map and every height is counted from it.
      top    how far up it goes (mm above the surface)
      rim    the mouth is a funnel: at the surface the outline is this much wider (a map: the lip is uneven), and
             the funnel has run out `mouth` mm up
      taper  the hole narrows by this much per mm of height; dome=(r, d): instead it closes as a vault d mm up
      lean   (dx, dz) per mm of height: the canal does not run straight up
      wobble (amp, seed): the bore is no cylinder: its wall bulges and draws in by up to amp mm, differently at every
             height (two noise maps turned into each other over a few mm of the run)
      lid    no higher than this (absolute y): a canal left shut over its top until through() opens it
      flare  under the surface the funnel goes on widening, up to this factor (1: no more than at the surface, for a
             wide funnel beside bone that hangs lower than the map's surface, as the mastoid does)"""
    def __init__(self, M, reg, ys, top, rim=None, mouth=1.8, taper=0.0, dome=None, lean=(0.0, 0.0), below=5.0, wobble=None, lid=None, flare=1.5):
        self.M, self.c, self.ys, self.top, self.rim, self.mouth, self.flare = M, M.smooth(reg), ys, top, rim, mouth, flare
        self.taper, self.dome, self.lean, self.lid = taper, dome, lean, lid
        self.wob = None
        if wobble is not None and wobble[0] > 0:
            self.wob = (wobble[0], M.smooth(uneven(M, wobble[1], 1.3)), M.smooth(uneven(M, wobble[1] + 1, 1.3)),
                        np.random.default_rng(wobble[1]).uniform(0, 2 * np.pi))
        widest = 1.0 + (2.3 * float(np.max(rim)) if rim is not None else 0.0)
        ins = reg < widest
        lo = np.array([M.U[ins].min() + min(0.0, lean[0] * top), float(ys[ins].min()) - below, M.V[ins].min() + min(0.0, lean[1] * top)])
        hi = np.array([M.U[ins].max() + max(0.0, lean[0] * top), float(ys[ins].max()) + top, M.V[ins].max() + max(0.0, lean[1] * top)])
        self.bounds = (lo, hi)

    def __call__(self, X, Y, Z):
        u, v, y = np.broadcast_arrays(X, Z, Y)
        up = y - self.M.sample(self.ys, u, v)
        run = np.clip(up, 0.0, None)
        uu, vv = u - self.lean[0] * run, v - self.lean[1] * run
        d = self.M.smooth_sample(self.c, uu, vv)
        e = self.M.outside(uu, vv)
        d = np.where(e > 0, np.maximum(d, e), d) + self.taper * run
        if self.dome is not None:
            d = d + self.dome[0] * (1.0 - np.sqrt(np.clip(1.0 - (run / self.dome[1]) ** 2, 0.0, 1.0)))
        if self.wob is not None:
            amp, A, Bn, ph = self.wob
            t = run / 2.6 + ph
            d = d - amp * (self.M.smooth_sample(A, uu, vv) * np.cos(t) + self.M.smooth_sample(Bn, uu, vv) * np.sin(t))
        if self.rim is not None:
            d = d - self.M.sample(self.rim, u, v) * np.clip(1.0 - up / self.mouth, 0.0, self.flare) ** 2
        d = np.maximum(d, up - self.top)
        if self.lid is not None:
            d = np.maximum(d, y - self.lid)
        return d.astype(np.float32)


class _Passage:
    """The great opening's passage above its lower edge: outline g (the lower edge) at y0 going over into r (the upper
    edge, Fig. 193) by y0 + 6, its front on the clivus line (the sphenoid's body's, sinus.SELLA, run down to the rim at
    z zf), its sides and back drawn apart by up to 3.9 mm at the top y1."""
    def __init__(self, M, g, r, zf, y0, y1):
        import sinus
        self.M, self.cg, self.cr, self.zf, self.y0, self.y1 = M, M.smooth(g), M.smooth(r), zf, y0, y1
        S = np.array(sinus.SELLA[:4], float)                         # the clivus: (z, y) from the rim's height up
        self.cy = np.concatenate([[y0], S[:, 1]]); self.cz = np.concatenate([[zf], S[:, 0]]) - zf
        lo = np.array([M.U.min(), y0, M.V.min()]); hi = np.array([M.U.max(), y1, M.V.max() + float(np.interp(y1, self.cy, self.cz))])
        self.bounds = (lo, hi)

    def __call__(self, X, Y, Z):
        u, y, v = np.broadcast_arrays(X, Y, Z)
        t = np.clip((y - self.y0) / (self.y1 - self.y0), 0.0, 1.0)
        w = 1.0 - smoothstep((np.abs(u) - 7.0) / 3.0)                      # (beside the clivus the walls lean as they did, 0.25 mm forward per mm up)
        vv = v - w * np.interp(np.clip(y, self.y0, self.y1), self.cy, self.cz) - (1.0 - w) * 0.25 * np.clip(y - self.y0, 0.0, self.y1 - self.y0)
        a = smoothstep((y - self.y0) / 6.0)
        d = (1.0 - a) * self.M.smooth_sample(self.cg, u, vv) + a * self.M.smooth_sample(self.cr, u, vv)
        e = self.M.outside(u, vv)
        d = np.where(e > 0, np.maximum(d, e), d)
        d = d - 3.9 * t * np.maximum(smoothstep((self.zf - 2.0 - vv) / 6.0), smoothstep((np.abs(u) - 7.0) / 3.0))    # (the front stays on the clivus, as wide as the clivus is)
        return np.maximum(d, np.maximum(self.y0 - y, y - self.y1)).astype(np.float32)


def condyles(F, B, log=print):
    """The condyle on the plate's own facet outline: a facet convex from front to back and from side to side, looking
    down and a little outward; its inner side slopes up to the edge of the great opening (the plate shows that slope
    as a strip beside the facet), its outer side is steeper.
    Its outline is the plate's own facet, traced (a kidney: the inner border hollow toward the great opening), made a
    little broader at its hind end and broken a little all round; across the facet a faint uneven line, as on many
    condyles where its two parts meet (no pinch in its outline).
    Gray p. 131: "The condyles are oval or reniform in shape, and their anterior extremities, directed forward and
    medialward, are closer together than their posterior ... The articular surfaces ... are convex from before
    backward and from side to side, and look downward and lateralward." The plate's outline, of one width from end to
    end, made a sausage, and a waist drawn in at its middle made it a pinched one: here it is one eased oval, its length
    brought to about twice its width, fullest a little behind its middle and rounder at its front end, its inner border
    only a little flatter than its outer (reniform, no waist)."""
    P = fair(mm(FACET, True))
    c = P.mean(0); Q = P - c
    w, E = np.linalg.eigh(np.cov(Q.T))
    long = E[:, 1] if E[1, 1] > 0 else -E[:, 1]                        # toward the front
    wide = np.array([-long[1], long[0]])
    if wide[0] < 0:
        wide = -wide                                                   # toward the body's side
    qa, qb = Q @ long, Q @ wide; La0 = np.abs(qa).max()
    qb = qb * (1.0 + 0.10 * np.clip(-qa / La0, -1.0, 1.0))             # broader at its hind end
    P = jag(c + np.outer(qa, long) + np.outer(qb, wide), 133, 0.035, 26)
    w2, E2 = np.linalg.eigh(np.cov((P - P.mean(0)).T)); l2 = E2[:, 1] if E2[1, 1] > 0 else -E2[:, 1]
    th = np.arctan2(l2[0], l2[1]) - np.arctan2(long[0], long[1])                # its axis kept the plate's
    P = c + (P - c) @ np.array([[np.cos(th), np.sin(th)], [-np.sin(th), np.cos(th)]])
    M, reg = outline_map(P, margin=7.0)
    ground = B["M"].sample(B["Yb"], M.U, M.V)
    c = P.mean(0); Q = P - c
    a = (M.U - c[0]) * long[0] + (M.V - c[1]) * long[1]; b = (M.U - c[0]) * wide[0] + (M.V - c[1]) * wide[1]
    La, Lb = np.abs(Q @ long).max(), np.abs(Q @ wide).max()
    facet = CONDYLE_LOWEST + 0.3 + 2.0 * (a / La) ** 2 + 1.0 * (b / Lb) ** 2 + 0.30 * b + 0.22 * uneven(M, 131, 2.2) + 0.12 * uneven(M, 132, 0.9)
    facet = facet + 0.3 * np.exp(-((a / La + 0.05) / 0.07) ** 2) * np.clip(0.7 + 0.5 * uneven(M, 134, 1.5), 0.15, 1.3)   # the faint line across   # (no lathe-turned surface)
    # the facet has an edge: the surface turns over within a millimetre of its outline. From there the outer side drops
    # to the ground within 1.4 mm; the inner side slopes up to the great opening's edge over 4 mm
    W = 1.4 + 2.6 * smoothstep(-b / 3.0)
    g = smoothstep((W - reg) / (W + 0.9))
    # past the foot of its sides the solid's face rises into the bone, so that nothing is laid on the bone's own surface there
    low = ground - np.maximum(ground - facet, 1.5) * g + 2.0 * smoothstep((reg - W + 0.4) / 1.5)
    F.add(relief.Slab(M, (0, 2, 1), -low, -(ground + 5.0), reg - 5.0, round=0.8, sign=-1.0, mirror=False), 1.0)
    log("condyle: facet %.1f mm long, %.1f wide, from x %.1f to %.1f and z %.1f to %.1f; it stands %.1f mm out of the base, lowest at y %.1f" % (
        2 * La, 2 * Lb, P[:, 0].min(), P[:, 0].max(), P[:, 1].min(), P[:, 1].max(), float((ground - low).max()), float(low[reg < 0].min())))


# the canals that go through into the cranial cavity are cut here from below only as far as a lid a few millimetres
# under the cavity's floor. The cavity's own surface is worked on later in the whole head (inner.py): its middle
# hollow is deepened and the petrous part's solid is laid in the cavity, and that work takes all air joined to the
# cavity within 9 mm for cavity; an opening already through let it run down the canals into the air under the base,
# where the petrous solid then filled the canals and hung a three-sided block 7 mm under the greater wing. through()
# opens them once that is done. (Heights: y of the lid, mm.)
LIDS = {"oval foramen": -8.5, "spinous foramen": -8.5, "ragged hole (lacerum)": -8.0, "jugular foramen": -16.5, "carotid canal": -8.0}


class _Down:
    """An Opening turned over: pushed down into the bone from above (its surface ys the top), for an upper mouth."""
    def __init__(self, op):
        self.op = op
        lo, hi = op.bounds
        self.bounds = (np.array([lo[0], 2 * float(op.ys.min()) - hi[1] - 1.0, lo[2]]), np.array([hi[0], float(op.ys.max()) + 2.0, hi[2]]))

    def __call__(self, X, Y, Z):
        return self.op(X, 2 * float(self.op.ys.mean()) - Y, Z)


class _Mirror:
    """A solid drawn for the left side (x > 0) set on the right."""
    def __init__(self, solid):
        self.solid = solid
        lo, hi = solid.bounds
        self.bounds = (np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]]))

    def __call__(self, X, Y, Z):
        return self.solid(-X, Y, Z)


def lip(M, seed, w):
    """The mouth's funnel: about w mm wide, wider here and narrower there (a map)."""
    return w * np.clip(1.0 + 0.6 * uneven(M, seed, 1.1), 0.2, 2.0)


def jag(poly, seed, amount, n):
    """ragged() for an outline given in mm about its own middle."""
    return ragged(np.asarray(poly, float), seed, amount, n)


def cut(F, B, log=print):
    """Cut the base's openings into the field F (the skull's left half). B: what base.build returned (its heights).
    Returns the outlines, for press() to sink each mouth's lip a little. What through() needs is kept on cut.through."""
    Mb, Yb = B["M"], B["Yb"]
    mouths = {}
    cut.through = []; cut.sides = []; cut.extra = []

    def opening(name, poly, top, k, lip_=None, seed=0, funnel=0.6, wob=0.3, through=None, front_sharp=False, side=None, mouth=1.6, **kw):
        poly = np.asarray(poly, float)
        lean = kw.get("lean", (0.0, 0.0))
        M, reg = outline_map(poly, margin=4.0 + top * max(abs(lean[0]), abs(lean[1])) + max(0.0, 3.4 * funnel - 2.6))     # (a wide funnel needs its map wider than it: past the map's edge the funnel's width is held and the edge cut a line)
        ys = Mb.sample(Yb, M.U, M.V)
        rim = lip(M, seed + 7, funnel)
        if front_sharp:                                   # the edge sharp in front, the funnel wide behind
            rim = rim * (0.25 + 1.1 * smoothstep((poly.mean(0)[1] + 2.0 - M.V) / 4.0))
        if side is not None:                              # the edge rolls in deep on one side, hardly on the other: no countersunk ring
            cc, a_ = poly.mean(0), np.radians(side)
            pr = ((M.U - cc[0]) * np.cos(a_) + (M.V - cc[1]) * np.sin(a_)) / (0.5 * float(np.ptp(poly, 0).max()))
            rim = rim * (0.03 + 1.6 * smoothstep(0.5 + 0.5 * pr) ** 1.5)
        F.cut(Opening(M, reg, ys, top, rim=rim, mouth=mouth, wobble=(wob, seed), lid=LIDS.get(name), **kw), k)
        # this half is mirrored to make the other: each side's mouth gets a lip of its own afterwards (through()), a
        # shallow cut on an outline broken with a seed of that side's, so the two mouths' small irregularities differ
        for sd, sds in (((1, 600), (-1, 700)) if name not in ("jugular hollow", "stylomastoid foramen") else ()):     # (not beside the styloid's root)
            Mv, rv = outline_map(jag(poly, seed + sds, 0.08, 9), margin=3.0)
            a_ = np.random.default_rng(seed + sds).uniform(0, 2 * np.pi); cc = poly.mean(0)        # (its lip rolls in on one side, a side of its own: no ring)
            if name == "carotid canal":
                a_ = np.radians(side) + 0.5 * (a_ / np.pi - 1.0)            # (on the funnel's side, so the hind edge stays sharp)
            pr = ((Mv.U - cc[0]) * np.cos(a_) + (Mv.V - cc[1]) * np.sin(a_)) / (0.5 * float(np.ptp(poly, 0).max()))
            rv_ = lip(Mv, seed + sds + 1, min(0.3, 0.1 * float(np.ptp(poly, 0).min()))) * (0.1 + 1.4 * smoothstep(0.5 + 0.5 * pr) ** 1.5)
            cut.sides.append((sd, Opening(Mv, rv, Mb.sample(Yb, Mv.U, Mv.V), 1.6, rim=rv_,
                                          mouth=1.4, lean=lean, below=3.0, taper=0.45), 0.5))     # (it narrows into the canal within the 1.6 mm: no shelf inside)
        c = poly.mean(0)
        if lip_:
            mouths[name] = (poly, lip_[0], lip_[1])
        if through is not None:
            cut.through.append(dict(name=name, poly=poly, k=k, seed=seed, lean=lean, ys=float(Mb.sample(Yb, [c[0]], [c[1]])[0]), **through))
        log("opening: %-24s middle x %.1f z %.1f, %.1f by %.1f mm, %.0f mm up from y %.1f%s" % (
            name, c[0], c[1], np.ptp(poly[:, 0]), np.ptp(poly[:, 1]), top, float(Mb.sample(Yb, [c[0]], [c[1]])[0]),
            (", shut at y %.1f until through()" % LIDS[name]) if name in LIDS else ""))
        return c

    def whole(half):
        half = np.array(half, float); half[0, 0] = half[-1, 0] = 0.0
        return fair(np.concatenate([half, half[-2:0:-1] * np.array([-1.0, 1.0])]), 0.4)

    # the great opening (Gray p. 130: "a large oval aperture with its long diameter antero-posterior; it is wider behind
    # than in front where it is encroached upon by the condyles"). One closed eased curve: an egg from the plate's basion
    # to its opisthion (38.9 mm), widest (27 mm) at the plate's widest place, a little behind the middle; then the condyles
    # bulge into its front half as broad smooth swellings. (The plate's own points, followed, gave a straight-sided neck in
    # front opening into a round bay behind: a keyhole.)
    zf, zb = BASION_Z + 0.2, OPISTHION_Z
    zc, L = (zf + zb) / 2, (zf - zb) / 2
    t = np.linspace(0.0, np.pi, 61)
    gz = zc + L * np.cos(t)
    gx = 13.6 * np.sin(t) ** 0.92 * (1.0 - 0.08 * np.cos(t))
    bulge = 3.8 * np.exp(-((gz + 3.0) / 9.0) ** 2) * np.sin(t) ** 0.5          # the condyles' inner sides
    wav = ndimage.gaussian_filter1d(np.random.default_rng(130).standard_normal(len(t)), 3.0)
    wav = 0.35 * wav / (np.abs(wav).max() + 1e-9) * np.sin(t)                  # its rim is not ruled
    g = np.column_stack([gx - bulge + wav, gz])
    # its upper edge, where the hind hollow's floor turns down into it: Fig. 193 traced (half widths, mm, from the
    # basion back in twentieths of its length): broad and blunt in front, widest a little behind the middle. The wall
    # between the two edges slopes: the condyles' inner sides in front, the floor's rounded edge behind. (Less here what
    # the passage's taper and the blend add at the height the floor meets it.)
    fr = (zf - gz) / (zf - zb)
    rh = np.interp(fr, np.linspace(0.0, 1.0, 21), UPPER_193) - np.interp(fr, [0.0, 0.25, 0.5, 0.75, 1.0], [3.4, 3.4, 2.6, 0.9, 0.9])
    r = np.column_stack([np.maximum(rh + 0.8 * wav, gx - bulge + wav), gz])
    g, r = whole(g), whole(r)
    M, reg = outline_map(np.concatenate([g, r]), cell=0.5, margin=11.0)
    F.cut(relief.Prism(M, (0, 2, 1), M.region(g), -46.0, -20.0, mirror=False), 1.4)
    # Above its edge the passage is no chimney. In front its wall is the clivus, which leans forward as it rises (Fig. 194);
    # the side walls draw apart a little; the back wall stands, and the floor of the hind hollow of the cranial cavity begins
    # a few mm above it. The front wall follows the clivus of the sphenoid's body (sinus.SELLA) down to the rim, so the two
    # are one surface (a wall leaning at its own slope stood 3 mm proud of it, a step 19 mm above the rim); the outline
    # goes over from the lower edge's to the upper's in the first 6 mm, so the condyles' inner sides are a slope and not a
    # ledge with a groove along it seen from above.
    F.cut(_Passage(M, M.region(g), M.region(r), zf, -21.5, -2.0), 2.5)
    # The front rim itself (the basion and a centimetre either side of it) is a thick rounded edge (Fig. 194: the
    # basilar part's cut ends blunt), not the wedge the underside and the clivus met in: the field is eased over it.
    for p_, r_ in (((0.0, -21.8, zf + 0.6), 4.2), ((4.2, -21.9, zf - 0.1), 3.6), ((7.8, -22.4, zf - 2.0), 3.0)):
        F.ease(p_, r_, 1.0)
    F.ease((0.0, -2.2, 9.9), 2.6, 1.0)                   # (where the passage's top meets the sphenoid's clivus: no notch across the midline)
    mouths["great opening"] = (g, 0.5, 1.6)
    i = int(np.argmax(g[:, 0])); front = g[g[:, 1] > g[:, 1].max() - 13.0]
    log("opening: great opening %.1f mm long, %.1f wide (widest at z %.1f), %.1f wide 6 mm behind its front" % (
        np.ptp(g[:, 1]), 2 * g[:, 0].max(), g[i, 1], 2 * np.abs(front[np.argmin(np.abs(front[:, 1] - (g[:, 1].max() - 6.0))), 0])))
    # the oval foramen (Gray p. 147: in the great wing "behind and lateral to the foramen rotundum"): the plate's leaf,
    # its edge uneven, up through the greater wing into the middle hollow (through() finishes it)
    # (the plate's traced leaf, 9.8 by 3.4 mm, came out a thin slanted slit; the plate's opening reads as a plump oval
    # about 7 by 4, its long axis along the leaf's)
    co = fair(mm(OVALE)).mean(0); ua = np.radians(-55.0); tt = np.linspace(0, 2 * np.pi, 14, endpoint=False)
    ov = co + np.outer(3.9 * np.cos(tt) * (1 + 0.08 * np.cos(tt)), [np.sin(ua), np.cos(ua)]) + np.outer(2.2 * np.sin(tt), [np.cos(ua), -np.sin(ua)])
    opening("oval foramen", jag(ov, 41, 0.07, 10), 17.0, 0.6, lip_=(0.35, 1.0), seed=41, funnel=0.6,
            lean=(0.05, 0.08), taper=0.06, through=dict(grow=(1.0, 1.15), bore=(1.06, 1.0)))      # (the bore carried up a little wider than the one from below, which narrows into it: no ledge seen inside the mouth)      # (it climbs a little forward and outward: Fig. 193 has its upper mouth 3 to 4 mm ahead of the lower)
    # the spine of the sphenoid (p. 149: "the angular spine ... projects downward", the sphenomandibular ligament's
    # attachment): a short blunt point hanging from the wing's hind corner, behind and outside the spinous foramen, at
    # the plate's red-marked tip (Fig. 187, page 790, 1993: x 35.4, z 8.9); it stands inside the jaw's socket's inner
    # edge. Its length (3 mm) is ours.
    # It grows out of the bone: a root as broad as the wing's hind angle (5 to 7 mm from front to back) drawn down into a
    # flattened point, thin from side to side, its front edge longer than its back one and a low ridge down its back
    # (it read as a round peg 3 mm proud with parallel sides and a domed tip). The right one is not the left: through()
    # gives it a tip of its own.
    sp0, sp1 = np.array([34.0, 12.4]), np.array([35.3, 9.3])
    y0_, y1_ = (float(Mb.sample(Yb, [q[0]], [q[1]])[0]) for q in (sp0, sp1))
    blade = sdf.spline(np.array([(sp0[0] - 0.2, y0_ + 2.4, sp0[1] + 0.4), (sp0[0] + 0.1, y0_ - 0.1, sp0[1] + 0.3),
                                 (0.5 * (sp0[0] + sp1[0]) + 0.5, 0.5 * (y0_ + y1_) - 1.0, 0.5 * (sp0[1] + sp1[1]) - 0.1),
                                 (sp1[0] + 0.4, y1_ - 2.3, sp1[1] - 0.3)]), 0.4)
    F.add(Tube(blade, [(0, 3.5), (0.3, 2.6), (0.62, 1.45), (0.85, 0.75), (1, 0.28)], [(0, 2.4), (0.3, 1.5), (0.62, 0.8), (0.85, 0.45), (1, 0.2)],
               up=(0.35, 0.0, -0.94)), 3.0)          # (a = front to back, b = side to side)
    F.add(Tube(np.array([(sp0[0] + 1.2, y0_ + 0.6, sp0[1] - 1.2), (sp0[0] + 1.3, y0_ - 0.8, sp0[1] - 1.9), (sp1[0] + 0.7, y1_ - 1.3, sp1[1] - 0.6)]),
               [(0, 1.2), (0.6, 0.7), (1, 0.3)], [(0, 0.9), (0.6, 0.5), (1, 0.25)], up=(0.35, 0.0, -0.94)), 1.4)     # a low ridge down its hind and outer face (away from the spinous foramen)
    tip = np.array([sp1[0] + 0.4, y1_ - 2.3, sp1[1] - 0.3])
    cut.extra = [(-1, "add", Tube(np.array([tip + (-0.3, 1.4, 0.6), tip + (0.15, -0.5, -0.5)]), [(0, 0.9), (1, 0.3)], [(0, 0.55), (1, 0.2)],
                                  up=(0.35, 0.0, -0.94)), 0.8),                  # the right tip a little longer, bent back
                 (1, "cut", Tube(np.array([tip + (0.9, 2.2, 1.3), tip + (0.9, 1.0, 0.2)]), 0.55), 0.5)]     # the left one nicked behind its tip
    # the spinous foramen at the spine's root, behind and outside the oval one: small and "sometimes double" (p. 147), its
    # outline a little egg (Fig. 187: 2.0 by 1.8 mm inside the ring the engraver drew round it; Fig. 193, from above, the
    # same), no ring: its edge is thin and sharp in front and on the inner side and the canal leans up, forward and
    # outward (it reaches the middle hollow's floor 4 mm further forward and 3 further out, where Fig. 193 has it), so
    # that from below its hind and outer wall is seen running in and the mouth has a lip on one side only
    c = mm([SPINOSUM])[0]
    spn = c + np.array([(1.05, 0.25), (0.75, 0.85), (0.1, 1.08), (-0.6, 0.85), (-1.0, 0.2), (-0.85, -0.55), (-0.25, -1.0), (0.55, -0.8)]) * np.array([0.95, 0.86])
    opening("spinous foramen", jag(spn, 42, 0.10, 8), 18.0, 0.5, lip_=(0.25, 0.7), seed=42, funnel=0.45, side=-60.0, mouth=1.6, wob=0.12,
            lean=(0.16, 0.25), through=dict(grow=(1.35, 1.45)))
    # the ragged hole (p. 181: "a large and somewhat triangular aperture ... bounded in front by the great wing of the
    # sphenoid, behind by the apex of the petrous portion ... and medially by the body of the sphenoid and basilar
    # portion of the occipital"): a three-cornered gap, its broad side against the body and its point running out
    # backward and outward between the wing and the petrous apex, its edges broken
    # The plate's gap is 5.4 by 3.5 mm from below (Fig. 187, the dark between the petrous apex and the basilar part) and
    # 7 by 4.6 from above (Fig. 193): it was cut 10.6 by 6.9, a clean triangle with an even rounded funnel. Now the
    # outline is the old three-cornered one brought to the plates' size, broken twice over (a few big bays and spurs, then
    # finer teeth), with hardly any funnel on its hind and outer side (the petrous apex's rough broken end) and a soft one
    # against the body; it climbs a little forward and outward to the upper mouth where Fig. 193 has it.
    tri = np.array([(14.2, 20.6), (16.6, 19.9), (19.4, 18.0), (21.4, 16.6), (23.0, 15.2), (21.0, 14.5), (18.4, 13.6), (16.0, 12.9),
                    (14.1, 13.3), (13.4, 15.2), (13.6, 18.2)])
    tri = np.array([17.0, 16.6]) + (tri - tri.mean(0)) * np.array([0.6, 0.52])
    lac_poly = jag(jag(tri, 187, 0.20, 9), 188, 0.09, 23)
    lac = opening("ragged hole (lacerum)", lac_poly, 13.0, 0.6, lip_=(0.7, 1.1), seed=187, funnel=0.5, wob=0.45, taper=0.03, side=200.0,
                  mouth=2.0, lean=(0.06, 0.12),
                  through=dict(grow=(1.25, 1.32), ragged=0.3, hole=0.9, search_from=-4.0,
                  upper=[(15.6, 19.0), (17.4, 19.7), (19.6, 18.6), (20.6, 17.0), (19.9, 15.6), (17.9, 15.1), (16.0, 15.4), (15.0, 17.2)]))     # from above: part-floored, broken edged
    # the carotid canal (p. 140: "it ascends at first, and then, making a bend, runs horizontally forward and medialward"):
    # its mouth looks down: an uneven round-oval in the rough petrous bone, its edge sharper in front and eased behind, the
    # wall leaning forward and inward from the start so that the bend is seen from below (no ring: it read as a pipe fitting)
    # Its mouth is its own, on the petrous underside, a ridge of bone between it and the jugular hollow behind and a
    # broad bar between it and the ragged hole in front and inside. The canal first climbs nearly straight up for 8 mm
    # (the vertical part), turns through a bend and runs forward and inward nearly level (the horizontal part), rising
    # only a little, to the petrous apex, where it opens into the upper part of the ragged hole from behind and outside,
    # above the gap's floor (Fig. 193: "Orifice of carotid canal", beside the sphenoid's body).
    c0 = mm([CAROTID])[0]
    # (it read as a round drilled pit: now an uneven oval drawn out forward and inward, the way the canal goes on, its
    # hind and outer edge sharp and the funnel a long soft slope on the front and inner side only, no even sunk ring)
    ua = np.radians(135.0); tt = np.linspace(0, 2 * np.pi, 13, endpoint=False)
    car = jag(c0 + np.array([0.3, -0.4]) + np.outer(3.4 * np.cos(tt) * (1 + 0.12 * np.cos(tt)), [np.cos(ua), np.sin(ua)]) + np.outer(2.0 * np.sin(tt), [-np.sin(ua), np.cos(ua)]), 7, 0.16, 9)
    y = float(Mb.sample(Yb, [c0[0]], [c0[1]])[0])
    c = opening("carotid canal", car, 7.5, 0.7, lip_=(0.12, 0.6), seed=7, funnel=1.1, wob=0.2, taper=0.03, lean=(-0.03, 0.05), side=135.0, mouth=3.0, flare=1.0)     # (its hind edge, the ridge against the jugular hollow, sharp; the funnel in front and inside, where the canal goes on)
    yl = float(Mb.sample(Yb, [lac[0]], [lac[1]])[0])
    to = np.array([lac[0] + 1.6, yl + 4.0, lac[1] - 0.6])                     # its inner orifice, in the ragged hole's hind and outer wall
    bend = sdf.spline(np.array([(c[0] - 0.1, y + 3.0, c[1] + 0.2), (c[0] - 0.3, y + 6.0, c[1] + 0.6), (c[0] - 1.0, y + 8.2, c[1] + 1.6),
                                (c[0] - 2.8, y + 9.0, c[1] + 3.4), (0.5 * (c[0] + to[0]) - 0.6, 0.5 * (y + 9.0 + to[1]), 0.5 * (c[1] + to[2]) + 0.6), tuple(to)]), 0.4)
    F.cut(Tube(bend, [(0, 2.6), (0.3, 2.4), (0.6, 2.35), (1, 2.2)], [(0, 2.8), (0.3, 2.6), (0.6, 2.5), (1, 2.3)], up=(0, 1, 0)), 0.8)
    log("opening: carotid canal bends at y %.1f, its inner orifice at x %.1f y %.1f z %.1f" % (y + 8.6, to[0], to[1], to[2]))
    # the jugular hollow: the plate's bean, vaulted for the vein's bulb, its edge uneven
    opening("jugular hollow", jag(fair(mm(JUGULAR_FOSSA)), 51, 0.08, 12), 7.0, 1.2, lip_=(0.7, 1.4), seed=51, funnel=0.6, wob=0.4,
            dome=(3.7, 7.0))
    # the jugular foramen (p. 181: "a large aperture, formed in front by the petrous portion of the temporal, and behind
    # by the occipital; it is generally larger on the right than on the left side"): at the hollow's inner end, from
    # the slot the plate draws there half as large again and run into the hollow's inner third; it climbs back and
    # inward into the hind hollow of the cavity. through() opens it there, sets the intrajugular processes across it
    # and makes the right one the larger
    s0 = mm(JUGULAR_SLOT); s0 = s0.mean(0) + np.array([1.4, 1.0]) * (s0 - s0.mean(0))      # (half as large again across, not forward: in front of it the ridge to the carotid canal)
    jf = jag(np.vstack([s0[:6], [(26.4, -3.8), (28.0, -1.6), (27.6, 1.6), (25.4, 2.6)]]), 52, 0.12, 13)
    opening("jugular foramen", jf, 17.0, 0.9, lip_=(0.5, 1.0), seed=52, funnel=0.5, wob=0.45, lean=(-0.30, -0.25),
            through=dict(grow=(1.0, 1.22), spur=True))
    # the stylomastoid foramen (p. 181: "at the base of this process"), between the styloid and the mastoid: small, a
    # little drawn out toward the mastoid, its lip thin in front and rounded behind; the facial canal climbs from it
    c = mm([STYLOMASTOID])[0]
    # (it read as a round drilled pit: now an uneven oval drawn out toward the mastoid, its edge sharp on the styloid's
    # side and a soft slope behind it, toward the mastoid notch (turned back so it stays off the mastoid itself))
    ua = np.radians(-70.0); tt = np.linspace(0, 2 * np.pi, 11, endpoint=False)
    sm = c + np.outer(1.6 * np.cos(tt) * (1 + 0.12 * np.cos(tt)), [np.cos(ua), np.sin(ua)]) + np.outer(1.1 * np.sin(tt), [-np.sin(ua), np.cos(ua)])
    opening("stylomastoid foramen", jag(sm, 61, 0.18, 7), 9.0, 0.9,
            seed=61, funnel=0.85, side=-95.0, mouth=2.8, wob=0.15, lean=(0.06, -0.08), flare=1.0)      # (its funnel was a countersunk ring 2.4 mm deep)      # (Fig. 187: a dark disc 2.7 by 2.4)
    # the canal in the hollow behind the condyle (p. 131: the fossa "is sometimes perforated by the condyloid canal"; p.
    # 181: "on one or both sides"): small here; through() makes the right one the larger (the hollow is pressed in: press)
    c = mm([CONDYLAR], True)[0]
    opening("condylar canal", jag(c + 1.0 * np.array(ROUNDISH) * np.array([1.0, 1.25]), 71, 0.15, 7), 14.0, 0.5, seed=71, funnel=0.4,
            wob=0.2, lean=(-0.10, 0.45), through=dict(right_only=True, grow=(1.0, 1.75), top=14.0))
    # the hypoglossal canal: from above the condyle's middle, forward and outward, to its mouth in front of the condyle's outer side
    c = mm([HYPOGLOSSAL], True)[0]; y = float(Mb.sample(Yb, [c[0]], [c[1]])[0])
    F.cut(Tube(np.array([(c[0] + 1.8, y - 1.2, c[1] + 1.5), (c[0], y + 0.8, c[1]), (10.0, -14.0, -3.5)]), [(0, 2.3), (0.5, 2.2), (1, 2.3)],
               [(0, 1.85), (0.5, 1.8), (1, 1.85)], up=(0, 1, 0)), 0.8)
    log("opening: hypoglossal canal        mouth at x %.1f z %.1f" % (c[0], c[1]))
    if F.h <= 0.3:
        # three pinholes the plate marks, where the grid can carry them: the canaliculi for the tympanic nerve and the
        # vagus' auricular branch, and the cochlea's aqueduct
        for at, r, d in ((TYMPANIC_CANALICULUS, 0.5, (0.0, 1.0, 0.2)), (MASTOID_CANALICULUS, 0.5, (0.6, 0.8, 0.0)), (COCHLEAR_AQUEDUCT, 0.7, (-0.3, 1.0, 0.3))):
            c = mm([at])[0]; y = float(Mb.sample(Yb, [c[0]], [c[1]])[0])
            F.cut(Tube(np.array([np.array([c[0], y - 1.0, c[1]]), np.array([c[0], y + 0.5, c[1]]) + 4.0 * np.array(d)]), r), 0.4)
    return mouths


def through(G, log=print):
    """In the whole head's field, once the cavity's surface is made (inner.py): open each canal cut.through lists from
    under its lid up into the cavity, on both sides; and what is not the same on both sides: the right jugular foramen
    the larger, the right condylar canal open and wide where the left is small, the intrajugular processes."""
    spec = getattr(cut, "through", [])
    found = []
    for o in spec:
        for s in (1, -1):
            if o.get("right_only") and s > 0:
                continue
            g = o["grow"][0 if s > 0 else 1]
            base = np.asarray(o.get("upper", o["poly"]), float)     # the upper mouth may have an outline of its own
            c = base.mean(0)
            poly = jag(c + g * o.get("hole", 1.0) * (base - c), o["seed"] + (0 if s > 0 else 500), o.get("ragged", 0.10), 13 if o.get("ragged") else 11)
            lean = o["lean"]
            if o.get("right_only"):
                y0, top = o["ys"] - 3.0, o.get("top", 14.0) + 3.0             # a canal of its own, from below the surface
                yt = y0 + top
            else:
                y0 = LIDS[o["name"]] - 2.5
                sh = np.array(lean) * (y0 - o["ys"]); c = c + sh; poly = poly + sh      # (where the canal cut from below has got to by then: it leans)
                # up the canal's line to the cavity: the first 2 mm of air above the lid
                ys_ = np.arange(o.get("search_from", LIDS[o["name"]]), LIDS[o["name"]] + 28.0, 0.25)     # (the ragged hole's search starts above the carotid canal, which opens into it)
                px = s * (c[0] + lean[0] * (ys_ - y0)); pz = c[1] + lean[1] * (ys_ - y0)
                dd = sample_field(G.D, G.lo, G.h, np.column_stack([px, ys_, pz]))
                air = dd > 0.0
                run = np.convolve(air.astype(float), np.ones(8), "valid") >= 8
                yt = float(ys_[int(np.argmax(run))]) + 1.0 if run.any() else float(ys_[-1])
                top = yt - y0 + 1.0
            M, reg = outline_map(poly, margin=4.0 + top * max(abs(lean[0]), abs(lean[1])))
            if o.get("bore"):
                Mb_, rb_ = outline_map(c + o["bore"][0 if s > 0 else 1] * (poly - c), margin=4.0 + top * max(abs(lean[0]), abs(lean[1])))
            else:
                Mb_, rb_ = M, reg
            op = Opening(Mb_, rb_, np.full(Mb_.U.shape, y0), top, wobble=(min(0.3, 0.08 * float(np.ptp(poly, 0).min())), o["seed"] + (1 if s > 0 else 2)), lean=lean,
                         rim=None if not o.get("right_only") else lip(Mb_, o["seed"] + 9, 0.5), mouth=1.6, below=1.0)
            G.cut(op if s > 0 else _Mirror(op), o["k"])
            # its upper mouth: the floor's edge is no punched rim but runs down into the opening, unevenly
            Mf, rf = outline_map(poly + np.array(lean) * (yt - y0), margin=4.0)
            fl = Opening(Mf, rf, np.full(Mf.U.shape, yt + 0.5), 3.5, rim=lip(Mf, o["seed"] + (3 if s > 0 else 4), 0.9), mouth=3.5, below=4.0)
            G.cut(_Down(fl) if s > 0 else _Mirror(_Down(fl)), 0.8)
            if o.get("hole"):
                # the gap's floor (cartilage in life): a shallow broken-edged hollow over the whole gap, and only part
                # of it open through
                Pf = jag(c + g * (base - c), o["seed"] + (11 if s > 0 else 511), 0.3, 9) + np.array(lean) * (yt - y0)
                Mh, rh_ = outline_map(Pf, margin=4.0)
                hf = Opening(Mh, rh_, np.full(Mh.U.shape, yt + 0.5), 1.6, rim=lip(Mh, o["seed"] + (12 if s > 0 else 13), 0.7), mouth=1.6, below=3.0)
                G.cut(_Down(hf) if s > 0 else _Mirror(_Down(hf)), 0.8)
            if not o.get("right_only"):
                # and the floor's edge rounded over about a millimetre: no knife edge, no dark cut line
                m = c + np.array(lean) * (yt - y0)
                G.ease((s * m[0], yt - 0.5, m[1]), 3.0 + 0.5 * float(np.ptp(poly, 0).max()), min(0.9, 0.12 * float(np.ptp(poly, 0).min())))     # (gently on a small canal: smoothed as much it closed)
            found.append("%s (%s) from y %.1f up to %.1f" % (o["name"], "left" if s > 0 else "right", y0, yt))
            if o.get("spur"):
                # the intrajugular processes (p. 131: "a bony spicule ... which projects lateralward above the hypoglossal
                # canal"; the temporal's own meets it from in front): two spurs from the walls toward each other, a third
                # of the way along from the inner end, not meeting; they part the inferior petrosal sinus's compartment
                # from the nerves'
                yy = o["ys"] + 3.5; cc = c + 3.5 * np.array(lean)
                P1 = np.array([(cc[0] - 1.2, yy, cc[1] + 3.6), (cc[0] - 0.9, yy + 0.3, cc[1] + 1.3)])
                P2 = np.array([(cc[0] - 2.6, yy - 0.6, cc[1] - 2.8), (cc[0] - 1.7, yy - 0.2, cc[1] - 0.9)])
                for P, r_ in ((P1, [(0, 0.95), (1, 0.55)]), (P2, [(0, 0.8), (1, 0.45)])):
                    P = P * np.array([s, 1.0, 1.0]) + (0 if s > 0 else np.array([-0.3, 0.2, 0.4]))
                    G.add(Tube(P, r_), 0.6, keep=3)
    for sd, op, k in getattr(cut, "sides", []):
        G.cut(op if sd > 0 else _Mirror(op), k)
    for sd, how, prim, k in getattr(cut, "extra", []):                # what is not the same on both sides (the spine's tip)
        if sd < 0:                                                      # (a Tube is set on the right by turning its own line over)
            prim = copy.copy(prim); prim.P = prim.P * np.array([-1.0, 1.0, 1.0]); prim.up = prim.up * np.array([-1.0, 1.0, 1.0])
            lo, hi = prim.P.min(0), prim.P.max(0); r = np.maximum(prim.a, prim.b).max(); prim.bounds = (lo - r, hi + r)
        getattr(G, how)(prim, k)
    log("base openings carried through into the cavity: " + "; ".join(found) + "; %d mouths given a lip of their own side" % len(getattr(cut, "sides", [])))


def press(F, B, mouths, log=print):
    """The small relief of the base, moved into the bone's own under surface (nothing laid on it): each opening's lip
    sunk a little and unevenly so its mouth is a soft funnel, the hollow behind the condyle, the two clefts beside the
    petrous part, the tubercle the pharynx hangs from."""
    M = relief.Map(-2.0, 64.0, -46.0, 46.0, 0.25)
    H = np.zeros(M.U.shape)
    slow = uneven(M, 1870, 5.0); fine = uneven(M, 1871, 1.5)

    def along(pts):
        L = sdf.spline(np.column_stack([pts, np.zeros(len(pts))]), 0.25)[:, :2]
        d, i = cKDTree(L).query(np.column_stack([M.U.ravel(), M.V.ravel()]))
        return d.reshape(M.U.shape), (i / max(len(L) - 1, 1)).reshape(M.U.shape)

    sink = np.zeros(M.U.shape)
    for name, (poly, deep, wide) in mouths.items():
        reg = M.region(poly)
        sink = np.maximum(sink, deep * np.exp(-np.clip(reg, 0.0, None) / wide) * np.clip(0.85 + 0.3 * fine, 0.4, 1.4))
    H -= sink
    c = mm([CONDYLAR], True)[0]                                                  # the hollow behind the condyle: broad, shallow, uneven; the canal opens in its outer part
    reg = M.region(ragged(c + np.array([-2.2, 0.6]) + np.array(BLOB) * np.array([6.8, 3.9]), 31, 0.14, n=9))
    H -= 1.1 * smoothstep(-reg / 3.4)
    d, t = along(mm(PETRO_OCCIPITAL))
    H -= (1.1 + 0.3 * slow) * np.exp(-(d / (1.2 + 0.25 * slow)) ** 2) * smoothstep(t / 0.08)
    d, t = along(mm(SPHENO_PETROSAL))
    H -= (0.9 + 0.25 * slow) * np.exp(-(d / (1.2 + 0.2 * slow)) ** 2) * (1 - 0.6 * smoothstep((t - 0.6) / 0.4))
    H += 1.6 * np.exp(-(M.U / 3.4) ** 2 - ((M.V - 11.0) / 2.8) ** 2)            # the pharyngeal tubercle, on the midline
    H = ndimage.gaussian_filter(H, 1.0)
    sl = F.window((0.0, -40.0, -46.0), (64.0, -4.0, 46.0))
    X, Y, Z = np.broadcast_arrays(*F.coords(sl))
    D = F.D[sl].astype(np.float32)
    Ds = ndimage.gaussian_filter(D, 0.6 / F.h)
    g = np.gradient(Ds, F.h)
    n = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6
    t = Ds / (n * n)
    u, v = X - t * g[0], Z - t * g[2]                                            # the surface point under each point of the field
    h = M.smooth_sample(M.smooth(H), u, v)
    w = (1 - smoothstep((np.abs(D) - 2.0) / 2.0)) * smoothstep((-g[1] / n - 0.2) / 0.4) * (M.outside(u, v) < -1.0)
    F.D[sl] = D - h * w * np.clip(n, 0.6, 1.8)
    log("base: relief from %.2f to %.2f mm pressed into the under surface (%d mouths' lips sunk)" % (H.min(), H.max(), len(mouths)))
