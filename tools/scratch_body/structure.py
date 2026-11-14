"""structure.py: what the bones are made of inside: compact bone, cancellous (spongy) bone, air cells.

The owner's order of 14 November: "make bones compact - cancellous - spongy in each place each one should be and in each
part of each bone. some bones also combine multiple types."

Gray 1918 (the page is the book's own):
  p. 86   "On examining a section of any bone, it is seen to be composed of two kinds of tissue, one of which is dense in
          texture, like ivory, and is termed compact tissue"; the other, "from its resemblance to lattice-work, is called
          cancellous tissue. The compact tissue is always placed on the exterior of the bone, the cancellous in the interior."
  p. 79   flat bones "are composed of two thin layers of compact tissue enclosing between them a variable quantity of
          cancellous tissue. In the cranial bones, the layers of compact tissue are familiarly known as the tables of the
          skull; the outer one is thick and tough; the inner is thin, dense, and brittle, and hence is termed the vitreous
          table."
  p. 80   the cancellous tissue between them "is called the diploe, and this, in certain regions of the skull, becomes
          absorbed so as to leave spaces filled with air (air-sinuses) between the two tables." Irregular bones "consist of
          cancellous tissue enclosed within a thin layer of compact bone."
  p. 132  the occipital "is especially thick at the ridges, protuberances, condyles, and anterior part of the basilar part;
          in the inferior fossae it is thin, semitransparent, and destitute of diploe."
  p. 138  the frontal: "The orbital portion is thin, translucent, and composed entirely of compact bone".
  p. 145  the temporal: "The structure of the squama is like that of the other cranial bones: the mastoid portion is spongy,
          and the petrous portion dense and hard."
  p. 142  the mastoid cells: "At the upper and front part of the process they are large and irregular and contain air, but
          toward the lower part they diminish in size, while those at the apex of the process are frequently quite small and
          contain marrow"; and "a large irregular cavity is situated at the upper and front part of the bone. It is called
          the tympanic antrum".
The whole skeleton, part by part, is in TABLE below (STRUCTURE.md is written from it by dev/structure_doc.py).

How it is made here. The bone's outside is left as it is. Inside it, three things are told apart from how deep a point lies
under the surface (any surface: the outer one, the brain's side, a sinus's wall, a tooth's socket):
  compact     everything within the shell's thickness of a surface. A plate thinner than twice the shell is therefore
              compact all through, with no rule saying so: the orbit's roof, the squama's thin middle, the wings, the
              scrolls, the lower fossae of the occipital.
  cancellous  deeper than that: a lattice of bars and plates with spaces between. It is a sum of waves of one length
              running every way (no two crossings alike), denser against the shell, so the shell's inner side is scalloped
              and not a ruled line.
  air cells   in the mastoid part: rounded cells between thin partitions, each the room nearest one of a scatter of points
              set far apart high and forward in the process and close together at its tip, with the antrum the largest.
The petrous part is left dense. Which shell, how open a lattice, which cells: `Skull` and `Jaw` below, zone by zone.
"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from sinus import depth, smoothstep, uneven

AIR, COMPACT, SPONGY, CELLS = 0, 1, 2, 3
NAMES = {COMPACT: "compact bone", SPONGY: "cancellous (spongy) bone", CELLS: "air cells"}


class Sponge:
    """Cancellous tissue as a field: a sum of waves of about one length (`cell`, mm from one space to the next) running in
    every direction. Above a level it is bone, below it marrow space: bars and plates that join every way."""
    def __init__(self, cell, seed, n=22, spread=0.2):
        rng = np.random.default_rng(seed)
        d = rng.normal(size=(n, 3)); d /= np.linalg.norm(d, axis=1, keepdims=True)
        self.cell = float(cell); self.n = n
        self.k = ((2 * np.pi / (cell * (1 + spread * rng.uniform(-1, 1, n))))[:, None] * d).astype(np.float32)
        self.ph = rng.uniform(0, 2 * np.pi, n).astype(np.float32)

    def __call__(self, X, Y, Z):
        f = np.zeros(np.broadcast_shapes(X.shape, Y.shape, Z.shape), np.float32)
        for (kx, ky, kz), p in zip(self.k, self.ph):
            f += np.cos(kx * X + ky * Y + kz * Z + p)
        return f * np.float32(np.sqrt(2.0 / self.n))


def scatter(centre, radii, size, first, seed, tries=9000):
    """Points for a foam of unequal cells in an egg-shaped block: no two nearer than the mean of their two sizes
    (`size(p)`, mm). `first`: (point, size) pairs that are placed before any other (the antrum)."""
    rng = np.random.default_rng(seed)
    c = np.asarray(centre, float); r = np.asarray(radii, float)
    pts = [np.asarray(p, float) for p, s in first]; sz = [float(s) for p, s in first]
    for u in rng.uniform(-1, 1, (tries, 3)):
        p = c + u * (r + 3.0); s = float(size(p))
        if len(pts) == 0 or np.all(np.linalg.norm(np.array(pts) - p, axis=1) > 0.45 * (np.array(sz) + s)):
            pts.append(p); sz.append(s)
    return np.array(pts)


class Skull:
    """The skull's bone, zone by zone (head frame, both sides alike in kind; the lattice and the cells are not mirrored)."""
    centre = np.array([0.0, 36.0, -6.0])                        # inside the braincase: the table that faces it is the inner one
    MASTOID = ((52.0, -8.0, -15.0), (10.5, 22.0, 13.0))         # the mastoid part: middle and half-lengths
    ANTRUM = (44.5, 4.5, -11.5)                                 # high and forward in it, behind the drum's attic
    PETROUS = ((45.0, 3.0, -3.0), (12.0, 8.0, 23.0), 8.5)       # the petrous part's axis from the ear inward and forward, and its half-width

    def __call__(self, X, Y, Z):
        aX = np.abs(X)
        one = np.ones(np.broadcast_shapes(X.shape, Y.shape, Z.shape), np.float32)
        # the vault: "the outer one is thick and tough; the inner is thin, dense, and brittle", diploe between
        P = dict(out=1.7 * one, inn=1.15 * one, open=0.28 * one, coarse=0.0 * one, dense=0.0 * one, cells=0.0 * one)

        def lay(w, **kw):
            for k, v in kw.items():
                P[k] = P[k] + w * (v - P[k])
        # the face (upper jaws, cheek bones, palate): a thin shell, an open lattice in the thick parts (the cheek bone's body,
        # the bone round the teeth's sockets)
        lay(smoothstep((Z - 40.0) / 10.0) * smoothstep((22.0 - Y) / 8.0), out=1.0, inn=1.0, open=0.55, coarse=0.25)
        # the base in the middle: the basilar part, the sphenoid's body round its sinuses, the condyles
        lay(smoothstep((14.0 - Y) / 6.0) * smoothstep((34.0 - aX) / 8.0) * smoothstep((Z + 36.0) / 8.0) * smoothstep((44.0 - Z) / 8.0),
            out=1.0, inn=1.0, open=0.5, coarse=0.5)
        # the petrous part: "dense and hard"
        a, b, r = (np.array(q, np.float32) for q in self.PETROUS)
        ab = b - a; t = np.clip(((aX - a[0]) * ab[0] + (Y - a[1]) * ab[1] + (Z - a[2]) * ab[2]) / float(ab @ ab), 0.0, 1.0)
        dist = np.sqrt((aX - a[0] - t * ab[0]) ** 2 + (Y - a[1] - t * ab[1]) ** 2 + (Z - a[2] - t * ab[2]) ** 2)
        dist = dist + uneven(X, Y, Z, 77, 1.8, 9.0)                # (its limits are no ruled lines)
        lay(1.0 - smoothstep((dist - r + 2.0) / 6.0), dense=1.0)
        # the mastoid part: air cells
        c, rr = self.MASTOID
        e = np.sqrt(((aX - c[0]) / rr[0]) ** 2 + ((Y - c[1]) / rr[1]) ** 2 + ((Z - c[2]) / rr[2]) ** 2)
        e = e + 0.11 * uneven(X, Y, Z, 78, 1.0, 7.0)
        lay(1.0 - smoothstep((e - 0.9) / 0.25), cells=1.0, dense=0.0, out=1.3, inn=1.0)      # (which cells: the points of `foam` this holds)
        return P

    def foam(self, side):
        c, r = self.MASTOID
        c = np.array([side * c[0], c[1], c[2]])

        def size(p):                                            # large high and forward, small toward the tip
            return 1.9 + 3.3 * smoothstep((p[1] + 24.0) / 26.0) + 0.9 * smoothstep((p[2] + 22.0) / 16.0)
        pts = scatter(c, r, size, [((side * self.ANTRUM[0],) + self.ANTRUM[1:], 9.5)], 1918 + (0 if side > 0 else 31))
        on = self(pts[:, 0], pts[:, 1], pts[:, 2])["cells"] > 0.5              # a cell is an air cell whole or not at all
        return pts, on, c - np.array(r) - 3.0, c + np.array(r) + 3.0


class Jaw:
    """The lower jaw: a thick compact shell, thickest along the lower border, thin on the joint head and round the teeth;
    cancellous within the body, the thick of the ramus and the head. `low`: (z axis, the lower border's height at each z)."""
    centre = np.array([0.0, -40.0, 40.0])

    def __init__(self, low):
        self.low = low

    @classmethod
    def of(cls, D, lo, h):
        """From the jaw's own field: the lower border's height at each z is read off it."""
        anyx = (np.asarray(D) < 0).any(axis=0)                  # (y, z)
        ok = anyx.any(axis=0)
        return cls(((lo[2] + h * np.arange(D.shape[2]))[ok], (lo[1] + h * anyx.argmax(axis=0))[ok]))

    def __call__(self, X, Y, Z):
        one = np.ones(np.broadcast_shapes(X.shape, Y.shape, Z.shape), np.float32)
        yb = np.interp(np.ravel(Z), self.low[0], self.low[1]).reshape(Z.shape).astype(np.float32)
        t = 1.25 + 1.5 * np.exp(-((Y - yb) / 8.0) ** 2) - 0.35 * smoothstep((Y + 16.0) / 6.0)      # (the head and the coronoid: thinner)
        t = t * one
        return dict(out=t, inn=t, open=0.6 * one, coarse=0.6 * one, dense=0.0 * one, cells=0.0 * one)

    def foam(self, side):
        return None


def inside(A, lo, h, zones, seed=1918, slab=None, wall=0.9):
    """A: a block of the bone's field (below 0 in bone), sampled every h mm from lo. Returns (B, kind): the field with
    the marrow spaces and air cells taken out of the bone's inside, and what each point is (AIR, COMPACT, SPONGY, CELLS;
    SPONGY and CELLS mark the region, bars, partitions and spaces alike). `slab`: the part of the block (slices) to do it
    in; the rest is left solid."""
    lo = np.asarray(lo, float)
    d = depth(A, h)
    sl = (slice(None),) * 3 if slab is None else tuple(slab)
    ax = [(lo[k] + h * np.arange(A.shape[k])).astype(np.float32)[sl[k]] for k in range(3)]
    X, Y, Z = np.ix_(*ax)
    dd = d[sl]; P = zones(X, Y, Z)
    g = np.gradient(dd, h); c = zones.centre
    rx, ry, rz = c[0] - X, c[1] - Y, c[2] - Z
    toward = (g[0] * rx + g[1] * ry + g[2] * rz) / (np.sqrt(rx * rx + ry * ry + rz * rz) * np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6)
    del g
    shell = P["inn"] + (P["out"] - P["inn"]) * smoothstep(1.5 * toward + 0.5)      # the nearest surface faces outward: the outer table
    m = dd - shell                                                                 # how far inside the shell (mm)
    fine, coarse = Sponge(1.75, seed), Sponge(2.7, seed + 1)
    f = (1.0 - P["coarse"]) * fine(X, Y, Z) + P["coarse"] * coarse(X, Y, Z)
    kind = np.where(A[sl] < 0, COMPACT, AIR).astype(np.uint8)
    kind[(kind == COMPACT) & (m > 0)] = SPONGY
    Xb, Yb, Zb = np.broadcast_arrays(X, Y, Z)
    cells = np.zeros(m.shape, np.float32); keep = np.full(m.shape, -9.0, np.float32); room = np.full(m.shape, -9.0, np.float32)
    for side in (1, -1):
        got = zones.foam(side)
        if got is None:
            continue
        pts, on, b0, b1 = got
        sel = (m > -0.5) & (Xb > b0[0]) & (Xb < b1[0]) & (Yb > b0[1]) & (Yb < b1[1]) & (Zb > b0[2]) & (Zb < b1[2])
        if not sel.any():
            continue
        xs, ys, zs = Xb[sel], Yb[sel], Zb[sel]
        Q = np.stack([xs + uneven(xs, ys, zs, 501, 0.8, 6.0), ys + uneven(xs, ys, zs, 502, 0.8, 6.5), zs + uneven(xs, ys, zs, 503, 0.8, 5.5)], 1)
        dn, jn = cKDTree(pts).query(Q, k=2)
        r = (0.5 * (dn[:, 1] - dn[:, 0]) - 0.5 * wall).astype(np.float32)          # above 0 in a room, away from its partitions
        mine = on[jn[:, 0]]
        cells[sel] = mine; room[sel] = np.where(mine, r, -9.0)
        keep[sel] = np.where(~mine & on[jn[:, 1]], -r, -9.0)                       # a cell's neighbour keeps its half of their partition
    level = P["open"] - 3.0 * (1.0 - smoothstep(m / 0.9)) - 6.0 * P["dense"] - 6.0 * cells
    q = np.maximum(np.maximum((f - level) * 0.3, -m), keep)                        # below 0 in a marrow space
    q = np.minimum(q, np.maximum(-room, -m))                                       # or in an air cell
    kind[(kind != AIR) & (cells > 0.5) & (m > 0)] = CELLS
    B = A.copy() if slab is not None else A
    B[sl] = np.maximum(A[sl], -q)
    # what is drawn as cancellous or as cells is what lies among the spaces: bone further than a bar's width from any space
    # is compact, whatever zone it is in
    near = ndimage.binary_dilation(q < 0, iterations=max(int(round(0.75 / h)), 1))
    kind[(kind != AIR) & ~near] = COMPACT
    kind[(q < 0) & (kind == AIR)] = SPONGY
    kind[(q < 0) & (cells > 0.5)] = CELLS
    return B, kind


def double(A):
    """The same block sampled twice as finely (each new point midway between its neighbours)."""
    for k in range(3):
        n = A.shape[k]; shape = list(A.shape); shape[k] = 2 * n - 1
        B = np.empty(shape, np.float32)
        even = [slice(None)] * 3; even[k] = slice(0, None, 2); odd = [slice(None)] * 3; odd[k] = slice(1, None, 2)
        a = [slice(None)] * 3; a[k] = slice(0, n - 1); b = [slice(None)] * 3; b[k] = slice(1, n)
        B[tuple(even)] = A; B[tuple(odd)] = 0.5 * (A[tuple(a)] + A[tuple(b)])
        A = B
    return A


# ---- every bone, part by part ------------------------------------------------------------------------------------------
# (bone or group, part, what it is made of, Gray's page, Gray's words (or, after a ~, the rule followed, in this file's words), built here?)
C, S, A_, M = "compact", "cancellous", "air", "marrow canal"
TABLE = [
    ("Every bone", "outside and inside", [C, S], 86, "The compact tissue is always placed on the exterior of the bone, the cancellous in the interior.", "rule"),
    ("Frontal", "squama and zygomatic processes", [C, S], 138, "very thick, consisting of diploic tissue contained between two compact laminae", "yes"),
    ("Frontal", "where the frontal sinuses lie", [C, A_], 138, "the diploic tissue is absent in the regions occupied by the frontal air sinuses", "yes"),
    ("Frontal", "orbital plates", [C], 138, "thin, translucent, and composed entirely of compact bone", "yes"),
    ("Parietal", "the whole bone", [C, S], 79, "two thin layers of compact tissue enclosing between them a variable quantity of cancellous tissue ... the tables of the skull", "yes"),
    ("Occipital", "squama, ridges, protuberances", [C, S], 132, "two compact lamellae, called the outer and inner tables, between which is the cancellous tissue or diploe", "yes"),
    ("Occipital", "condyles and the front of the basilar part", [C, S], 132, "especially thick at the ridges, protuberances, condyles, and anterior part of the basilar part", "yes"),
    ("Occipital", "lower (cerebellar) fossae", [C], 132, "in the inferior fossae it is thin, semitransparent, and destitute of diploe", "yes, where the plate is thin"),
    ("Temporal", "squama", [C, S], 145, "The structure of the squama is like that of the other cranial bones", "yes (compact alone where it is thin)"),
    ("Temporal", "mastoid part", [C, A_, S], 142, "At the upper and front part of the process they are large and irregular and contain air, but toward the lower part they diminish in size, while those at the apex of the process are frequently quite small and contain marrow", "yes (cells; the tympanic cavity not yet)"),
    ("Temporal", "petrous part", [C], 145, "the petrous portion dense and hard", "yes (the inner ear's canals not yet)"),
    ("Temporal", "tympanic part, styloid process, zygomatic process", [C], 86, "~thin parts: within the shell's thickness of a surface everywhere", "yes"),
    ("Sphenoid", "body", [C, A_, S], 80, "cancellous tissue enclosed within a thin layer of compact bone", "yes: what the two sphenoidal sinuses leave of the body"),
    ("Sphenoid", "greater and lesser wings, pterygoid plates", [C], 86, "~thin plates; cancellous only where they thicken at their roots", "yes"),
    ("Ethmoid", "the whole bone", [C, A_], 153, "exceedingly light and spongy", "yes: thin plates of compact bone round the air cells"),
    ("Inferior nasal concha", "the whole bone", [C], 169, "a lamina of spongy bone, curled upon itself like a scroll", "as a thin plate (its pitted surface not yet)"),
    ("Nasal, lacrimal, vomer", "the whole bone", [C], 80, "~flat bones (p. 80), here too thin to hold diploe", "yes"),
    ("Maxilla", "body", [C, A_], 80, "~hollowed by the maxillary sinus, its walls thin plates", "yes"),
    ("Maxilla", "alveolar process, round the teeth's sockets", [C, S], 80, "cancellous tissue enclosed within a thin layer of compact bone", "yes"),
    ("Maxilla", "frontal and palatine processes", [C], 86, "~thin plates; a little cancellous where the palate thickens in front", "yes"),
    ("Zygomatic", "body and processes", [C, S], 80, "cancellous tissue enclosed within a thin layer of compact bone", "yes"),
    ("Palatine", "the whole bone", [C], 80, "~thin plates", "yes"),
    ("Mandible", "body", [C, S, M], 80, "~an irregular bone (p. 80): cancellous within a compact shell, here thickest along the lower border; the mandibular canal runs through it", "yes (the canal not yet)"),
    ("Mandible", "ramus, coronoid process", [C, S], 80, "~two compact plates, cancellous between them where the ramus is thick; the coronoid and the middle of the ramus compact", "yes"),
    ("Mandible", "head (condyle)", [C, S], 279, "spongy cancellous tissue with a thin coating of compact substance", "yes"),
    ("Hyoid", "the whole bone", [C, S], 80, "cancellous tissue enclosed within a thin layer of compact bone", "no (not built)"),
    ("Vertebra", "body", [C, S], 97, "The body is composed of cancellous tissue, covered by a thin coating of compact bone", "no"),
    ("Vertebra", "arch and processes", [C, S], 97, "The arch and processes projecting from it have thick coverings of compact tissue.", "no"),
    ("Sacrum, coccyx", "the whole bone", [C, S], 111, "The sacrum consists of cancellous tissue enveloped by a thin layer of compact bone.", "no"),
    ("Sternum", "the whole bone", [C, S], 121, "highly vascular cancellous tissue, covered by a thin layer of compact bone which is thickest in the manubrium between the articular facets for the clavicles", "no"),
    ("Ribs", "the whole bone", [C, S], 127, "The ribs consist of highly vascular cancellous tissue, enclosed in a thin layer of compact bone.", "no"),
    ("Clavicle", "the whole bone", [C, S], 202, "cancellous tissue, enveloped by a compact layer, which is much thicker in the intermediate part than at the extremities of the bone", "no"),
    ("Scapula", "head, processes, thickened parts", [C, S], 207, "The head, processes, and the thickened parts of the bone, contain cancellous tissue", "no"),
    ("Scapula", "the blade", [C], 207, "the rest consists of a thin layer of compact tissue", "no"),
    ("Long bones (humerus, radius, ulna, femur, tibia, fibula, metacarpals, metatarsals, phalanges)", "body (shaft)", [C, M], 79, "the wall consists of dense, compact tissue of considerable thickness in the middle part of the body, but becoming thinner toward the extremities", "no"),
    ("Long bones", "extremities", [C, S], 79, "consist of cancellous tissue surrounded by thin compact bone", "no"),
    ("Humerus", "body", [C, M], 212, "a cylinder of compact tissue, thicker at the center than toward the extremities, and contains a large medullary canal which extends along its whole length", "no"),
    ("Ulna, radius", "body", [C, M], 219, "The long, narrow medullary cavity is enclosed in a strong wall of compact tissue which is thickest along the interosseous border", "no"),
    ("Femur", "lower end", [C, S], 253, "there remains only a thin shell of compact bone", "no"),
    ("Tibia", "body", [C, M], 260, "The compact wall of the body is thickest at the junction of the middle and lower thirds of the bone.", "no"),
    ("Hip bone", "thicker parts", [C, S], 237, "The thicker parts of the bone consist of cancellous tissue, enclosed between two layers of compact tissue", "no"),
    ("Hip bone", "bottom of the acetabulum, centre of the iliac fossa", [C], 237, "usually semitransparent, and composed entirely of compact tissue", "no"),
    ("Patella", "the whole bone", [C, S], 256, "a nearly uniform dense cancellous tissue, covered by a thin compact lamina", "no"),
    ("Carpal and tarsal bones", "the whole bone", [C, S], 79, "These consist of cancellous tissue covered by a thin crust of compact substance.", "no"),
]
