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
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import relief, plates, sdf
from sdf import Tube

PLATE_BASION_Z, PLATE_OPISTHION_Z = 4.2, -34.5       # the great opening's ends on the plate (mm, plates.base_mm)
BASION_Z, OPISTHION_Z = 4.2, -34.5                   # and on this skull: the plate's own (base.py's midline heights end there)
CONDYLE_LOWEST = -28.5                               # the condyle's lowest point (sagittal section, Fig. 194)

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
CAROTID = (942, 2033)             # its mouth is 7.0 by 5.9 mm on the plate
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
      lean   (dx, dz) per mm of height: the canal does not run straight up"""
    def __init__(self, M, reg, ys, top, rim=None, mouth=1.8, taper=0.0, dome=None, lean=(0.0, 0.0), below=5.0):
        self.M, self.c, self.ys, self.top, self.rim, self.mouth = M, M.smooth(reg), ys, top, rim, mouth
        self.taper, self.dome, self.lean = taper, dome, lean
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
        if self.rim is not None:
            d = d - self.M.sample(self.rim, u, v) * np.clip(1.0 - up / self.mouth, 0.0, 1.5) ** 2
        return np.maximum(d, up - self.top).astype(np.float32)


def condyles(F, B, log=print):
    """The condyle on the plate's own facet outline: a facet convex from front to back and from side to side, looking
    down and a little outward; its inner side slopes up to the edge of the great opening (the plate shows that slope
    as a strip beside the facet), its outer side is steeper."""
    P = fair(mm(FACET, True))
    M, reg = outline_map(P, margin=7.0)
    ground = B["M"].sample(B["Yb"], M.U, M.V)
    c = P.mean(0); Q = P - c
    w, E = np.linalg.eigh(np.cov(Q.T))
    long = E[:, 1]; wide = np.array([-long[1], long[0]])
    if wide[0] < 0:
        wide = -wide                                                   # toward the body's side
    a = (M.U - c[0]) * long[0] + (M.V - c[1]) * long[1]; b = (M.U - c[0]) * wide[0] + (M.V - c[1]) * wide[1]
    La, Lb = np.abs(Q @ long).max(), np.abs(Q @ wide).max()
    facet = CONDYLE_LOWEST + 0.3 + 2.0 * (a / La) ** 2 + 1.0 * (b / Lb) ** 2 + 0.22 * b
    # the facet has an edge: the surface turns over within a millimetre of its outline. From there the outer side drops
    # to the ground within 1.4 mm; the inner side slopes up to the great opening's edge over 4 mm
    W = 1.4 + 2.6 * smoothstep(-b / 3.0)
    g = smoothstep((W - reg) / (W + 0.9))
    # past the foot of its sides the solid's face rises into the bone, so that nothing is laid on the bone's own surface there
    low = ground - np.maximum(ground - facet, 1.5) * g + 2.0 * smoothstep((reg - W + 0.4) / 1.5)
    F.add(relief.Slab(M, (0, 2, 1), -low, -(ground + 5.0), reg - 5.0, round=0.8, sign=-1.0, mirror=False), 1.0)
    log("condyle: facet %.1f mm long, %.1f wide, from x %.1f to %.1f and z %.1f to %.1f; it stands %.1f mm out of the base, lowest at y %.1f" % (
        2 * La, 2 * Lb, P[:, 0].min(), P[:, 0].max(), P[:, 1].min(), P[:, 1].max(), float((ground - low).max()), float(low[reg < 0].min())))


def cut(F, B, log=print):
    """Cut the base's openings into the field F (the skull's left half). B: what base.build returned (its heights).
    Returns the outlines, for press() to sink each mouth's lip a little."""
    Mb, Yb = B["M"], B["Yb"]
    mouths = {}

    def opening(name, poly, top, k, lip=None, **kw):
        poly = np.asarray(poly, float)
        lean = kw.get("lean", (0.0, 0.0))
        M, reg = outline_map(poly, margin=4.0 + top * max(abs(lean[0]), abs(lean[1])))
        F.cut(Opening(M, reg, Mb.sample(Yb, M.U, M.V), top, **kw), k)
        c = poly.mean(0)
        if lip:
            mouths[name] = (poly, lip[0], lip[1])
        log("opening: %-24s middle x %.1f z %.1f, %.1f by %.1f mm, %.0f mm up from y %.1f" % (
            name, c[0], c[1], np.ptp(poly[:, 0]), np.ptp(poly[:, 1]), top, float(Mb.sample(Yb, [c[0]], [c[1]])[0])))
        return c

    def whole(half):
        half = np.array(half, float); half[0, 0] = half[-1, 0] = 0.0
        return fair(np.concatenate([half, half[-2:0:-1] * np.array([-1.0, 1.0])]), 0.4)

    # the great opening: at its edge and below, the plate's outline; higher up, behind the condyles' inner sides, the
    # bony ring is wider in front (drawn here: 2.5 mm a side)
    g = mm(MAGNUM, True)
    r = g.copy(); r[:, 0] += 2.5 * smoothstep((r[:, 1] + 12.8) / 6.0) * smoothstep(r[:, 0] / 5.0)
    g, r = whole(g), whole(r)
    M, reg = outline_map(np.concatenate([g, r]), cell=0.5, margin=11.0)
    F.cut(relief.Prism(M, (0, 2, 1), M.region(g), -46.0, -20.0, mirror=False), 1.4)
    # Above its edge the passage is no chimney. In front its wall is the clivus, which leans forward as it rises (about
    # 65 degrees to the Frankfurt plane, Fig. 194: 0.45 mm forward for each mm up); the side walls draw apart a little;
    # the back wall stands, and the floor of the hind hollow of the cranial cavity begins a few mm above it.
    F.cut(relief.Prism(M, (0, 2, 1), M.region(r), -21.5, -2.0, mirror=False, taper=-3.9, lean=(0.0, 0.25)), 2.5)
    i = int(np.argmax(g[:, 0])); front = g[g[:, 1] > g[:, 1].max() - 13.0]
    log("opening: great opening %.1f mm long, %.1f wide (widest at z %.1f), %.1f wide 6 mm behind its front" % (
        np.ptp(g[:, 1]), 2 * g[:, 0].max(), g[i, 1], 2 * np.abs(front[np.argmin(np.abs(front[:, 1] - (g[:, 1].max() - 6.0))), 0])))
    # the oval foramen: the plate's leaf, up through the greater wing
    opening("oval foramen", fair(mm(OVALE)), 9.0, 0.6, lip=(0.6, 1.1))
    # the spinous foramen behind and outside it
    c = mm([SPINOSUM])[0]
    opening("spinous foramen", fair(c + 1.15 * np.array(ROUNDISH)), 8.0, 0.5, lip=(0.45, 0.8))
    # the ragged hole at the tip of the petrous part: the plate's own outline half as large again (a dried skull's is wider than the plate draws)
    L = mm(LACERUM); L = L.mean(0) + 1.5 * (L - L.mean(0))
    lac = opening("ragged hole (lacerum)", ragged(L, 187, 0.22), 13.0, 0.6, lip=(0.9, 1.5), taper=0.06)
    # the carotid canal: its mouth looks down; the canal climbs and then turns forward and inward through the petrous part
    c = mm([CAROTID])[0]
    c = opening("carotid canal", ragged(c + np.array(ROUNDISH) * np.array([3.4, 2.9]), 7, 0.13, n=9), 9.0, 0.8, lip=(0.8, 1.3), taper=0.05)
    y, yl = float(Mb.sample(Yb, [c[0]], [c[1]])[0]), float(Mb.sample(Yb, [lac[0]], [lac[1]])[0])
    F.cut(Tube(np.array([(c[0], y + 6.0, c[1]), (c[0] - 3.5, y + 8.3, c[1] + 4.0), (lac[0] + 0.5, yl + 6.5, lac[1] - 0.5)]), 2.6), 1.0)
    # the jugular hollow: the plate's bean, vaulted for the vein's bulb; at its inner end the opening itself climbs back and inward
    opening("jugular hollow", fair(mm(JUGULAR_FOSSA)), 7.0, 1.2, lip=(0.7, 1.4), dome=(3.7, 7.0))
    opening("jugular opening", fair(mm(JUGULAR_SLOT)), 17.0, 0.9, lip=(0.5, 1.0), lean=(-0.30, -0.25))
    # the stylomastoid foramen, behind the root of the styloid process
    c = mm([STYLOMASTOID])[0]
    opening("stylomastoid foramen", fair(c + 1.15 * np.array(ROUNDISH)[::-1] * np.array([1.0, -1.0])), 9.0, 0.5, lip=(0.5, 0.9))
    # the canal that opens in the hollow behind the condyle (the hollow itself is pressed in: see press)
    c = mm([CONDYLAR], True)[0]
    opening("condylar canal", fair(c + 1.3 * np.array(ROUNDISH) * np.array([1.0, 1.1])), 14.0, 0.5, lean=(-0.10, 0.45))
    # the hypoglossal canal: from above the condyle's middle, forward and outward, to its mouth in front of the condyle's outer side
    c = mm([HYPOGLOSSAL], True)[0]; y = float(Mb.sample(Yb, [c[0]], [c[1]])[0])
    F.cut(Tube(np.array([(c[0] + 1.8, y - 1.2, c[1] + 1.5), (c[0], y + 0.8, c[1]), (11.0, -14.5, -3.0)]), 2.1, 1.5, up=(0, 1, 0)), 0.8)
    log("opening: hypoglossal canal        mouth at x %.1f z %.1f" % (c[0], c[1]))
    if F.h <= 0.3:
        # three pinholes the plate marks, where the grid can carry them: the canaliculi for the tympanic nerve and the
        # vagus' auricular branch, and the cochlea's aqueduct
        for at, r, d in ((TYMPANIC_CANALICULUS, 0.5, (0.0, 1.0, 0.2)), (MASTOID_CANALICULUS, 0.5, (0.6, 0.8, 0.0)), (COCHLEAR_AQUEDUCT, 0.7, (-0.3, 1.0, 0.3))):
            c = mm([at])[0]; y = float(Mb.sample(Yb, [c[0]], [c[1]])[0])
            F.cut(Tube(np.array([np.array([c[0], y - 1.0, c[1]]), np.array([c[0], y + 0.5, c[1]]) + 4.0 * np.array(d)]), r), 0.4)
    return mouths


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
