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

AIR, COMPACT, SPONGY, CELLS, CANAL, MARROW = 0, 1, 2, 3, 4, 5
NAMES = {COMPACT: "compact bone", SPONGY: "cancellous (spongy) bone", CELLS: "air cells", CANAL: "a canal for a nerve and vessels",
         MARROW: "the marrow (medullary) canal"}


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


SIZES = (1.3, 2.0, 3.1)        # mm from one marrow space to the next: the smallest, a middle and the largest the lattice is made of


def lattice(Xs, Ys, Zs, X, Y, Z, m, coarse, seed):
    """Cancellous tissue whose spaces are not all of one size. Three lattices (SIZES, each with its own spread of a third
    either way, so the spaces run from about 1 to 4 mm and no further) are mixed by a measure that changes from place to
    place on no pattern: here the fine one, there the coarse, between them a mixture of two. Deeper in the bone the
    spaces are larger, under the shell smaller. (Xs, Ys, Zs: the place, drawn out along the grain if there is one.)"""
    s = 0.5 + 0.34 * (uneven(X, Y, Z, seed + 21, 1.0, 7.0) + uneven(X, Y, Z, seed + 22, 1.0, 17.0)) + 0.05 * (np.clip(m, 0.0, 8.0) - 3.0) + (coarse - 0.35)
    s = np.clip(s, 0.0, 1.0) * (len(SIZES) - 1)
    f = np.zeros(s.shape, np.float32); norm = np.zeros(s.shape, np.float32)
    for i, cell in enumerate(SIZES):
        w = np.clip(1.0 - np.abs(s - i), 0.0, 1.0).astype(np.float32)
        f += w * Sponge(cell, seed + i, spread=0.3)(Xs, Ys, Zs); norm += w * w
    return f / np.sqrt(norm)                                       # (as much bone in a mixture as in either lattice alone)


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
    cancellous within the body, the thick of the ramus and the head. `low`: (z axis, the lower border's height at each z).
    `canals`: the mandibular canal of each side with its branches (`jaw_canals`)."""
    centre = np.array([0.0, -40.0, 40.0])

    def __init__(self, low, canals=None):
        self.low = low; self.canals = canals

    @classmethod
    def of(cls, D, lo, h, canals=None):
        """From the jaw's own field: the lower border's height at each z is read off it."""
        anyx = (np.asarray(D) < 0).any(axis=0)                  # (y, z)
        ok = anyx.any(axis=0)
        return cls(((lo[2] + h * np.arange(D.shape[2]))[ok], (lo[1] + h * anyx.argmax(axis=0))[ok]), canals)

    def __call__(self, X, Y, Z):
        one = np.ones(np.broadcast_shapes(X.shape, Y.shape, Z.shape), np.float32)
        yb = np.interp(np.ravel(Z), self.low[0], self.low[1]).reshape(Z.shape).astype(np.float32)
        t = 1.25 + 1.5 * np.exp(-((Y - yb) / 8.0) ** 2) - 0.35 * smoothstep((Y + 16.0) / 6.0)      # (the head and the coronoid: thinner)
        t = t * one
        return dict(out=t, inn=t, open=0.6 * one, coarse=0.6 * one, dense=0.0 * one, cells=0.0 * one)

    def foam(self, side):
        return None


class Bone:
    """A bone below the head, in its own frame (mm; its length along the third axis, its upper end at the greater
    values), made up as Gray says of its class (TABLE). `plan` (see PLANS):
      long      "the wall consists of dense, compact tissue of considerable thickness in the middle part of the body, but
                becoming thinner toward the extremities; within the medullary canal is some cancellous tissue, scanty in
                the middle of the body but greater in amount toward the ends. The extremities ... consist of cancellous
                tissue surrounded by thin compact bone" (p. 79). Where the body ends and an extremity begins is read off
                the bone itself: where it has widened to half as wide again as at its narrowest, or more. The wall's thickness in millimetres is ours (Gray
                gives none): `wall` times the body's half-width at its narrowest, at the place Gray names where he
                names one (`thickest`, as a share of the length from the lower end).
      short     "cancellous tissue covered by a thin crust of compact substance" (p. 79)
      flat      a compact layer of `shell` mm under every surface, cancellous between: so a plate thinner than twice
                that is compact all through. Where Gray says a bone's thin parts are compact alone (the scapula's blade,
                p. 207; the middle of the iliac fossa and the acetabulum's bottom, p. 237), the bone is compact
                wherever it is thinner than `thin` mm, a measure set to the atlas's bone, whose plates are thicker
                than a dried bone's
      vertebra  "The body is composed of cancellous tissue, covered by a thin coating of compact bone"; "The arch and
                processes projecting from it have thick coverings of compact tissue." (p. 97). The body is told from
                the arch by its bulk: what a ball six tenths as wide as the bone's thickest part can reach.
    Marrow (p. 87): "In the bodies of the long bones the marrow is of a yellow color"; "In the flat and short bones, in
    the articular ends of the long bones, in the bodies of the vertebrae, in the cranial diploe, and in the sternum and
    ribs the marrow is of a red color"."""
    canals = None

    def __init__(self, D, lo, h, plan, up=None):
        self.plan = plan = dict(plan); self.lo = lo = np.asarray(lo, float); self.h = h = float(h)
        bone = np.asarray(D) < 0
        n = [bone.sum(axis=tuple(a for a in range(3) if a != k)).astype(float) for k in range(3)]
        self.centre = np.array([lo[k] + h * float((np.arange(len(n[k])) * n[k]).sum() / max(n[k].sum(), 1.0)) for k in range(3)])
        z = lo[2] + h * np.arange(bone.shape[2]); has = n[2] > 0
        self.z0, self.z1 = float(z[has][0]), float(z[has][-1])
        t = (z - self.z0) / max(self.z1 - self.z0, 1.0)
        r = np.sqrt(ndimage.gaussian_filter1d(n[2] * h * h, 4.0 / h) / np.pi)      # the half-width of a round bone as big across
        kind = plan["class"]; self.grain = None; self.body = None; self.thin = None
        one = np.ones_like(z)
        if kind == "long":
            rs = float(r[(t > 0.2) & (t < 0.8)].min())
            flare = np.maximum(smoothstep((r / rs - 1.4) / 0.45), 1.0 - smoothstep((np.minimum(t, 1.0 - t) - 0.05) / 0.09))   # (a body may widen by half, as the tibia's does upward, and still be body)
            flare = np.where((t < 0) | (t > 1), 1.0, flare)
            ends = np.clip(0.045 * r, 0.4, 1.0)
            shell = ends + (plan.get("wall", 0.44) * rs - ends) * (1.0 - flare) * (0.72 + 0.28 * np.exp(-((t - plan.get("thickest", 0.5)) / 0.22) ** 2))
            # the marrow canal: how far into the body the place is from the body's nearer end (mm; below 0 in an extremity),
            # and how wide the hollow is there. `inside` settles where the canal begins from these and from how deep the
            # point lies: later along the wall than in the middle, so the cancellous tissue runs on up the wall and thins
            # out, and the canal's end is an arch and no flat floor
            body = np.nonzero(has & (flare < 0.5))[0]
            into = np.minimum(z - z[body[0]], z[body[-1]] - z) if len(body) else -one
            self.prof = (z, shell, plan.get("open", 0.42) + plan.get("open_mid", 0.0) * (1.0 - flare), (into, np.maximum(r - shell, 1.0)) if plan.get("canal", True) else None)
            self.grain = (np.array([0.0, 0.0, 1.0]), 1.7)                           # the plates of the ends run lengthwise
            self.words = "body %.0f mm across at its narrowest, its wall up to %.1f mm; ends' crust %.1f to %.1f mm" % (
                2 * rs, float(shell.max()), float(ends[has].min()), float(ends[has].max()))
        elif kind == "short":
            size = float(np.cbrt(bone.sum() * h ** 3))
            sh = float(np.clip(0.035 * size, 0.4, 0.9)) if "shell" not in plan else plan["shell"]
            self.prof = (z, sh * one, plan.get("open", 0.4) * one, None)
            self.words = "crust %.1f mm" % sh
        else:
            sh = plan.get("shell", 0.8)
            top = plan.get("shell_top", sh)                                         # (the sternum: thickest in the manubrium)
            self.prof = (z, sh + (top - sh) * smoothstep((t - 0.8) / 0.1), plan.get("open", 0.42) * one, None)
            self.words = "compact layer %.1f mm" % sh
            if "thin" in plan:                                                      # how thick the bone is at each place: twice the depth of its middle there
                d = depth(np.asarray(D, np.float32), h)
                th = 2.0 * ndimage.gaussian_filter(ndimage.maximum_filter(d, size=int(round(9.0 / h)) | 1), 2.0 / h)
                self.thin = (1.0 - smoothstep((th - plan["thin"]) / 2.5)).astype(np.float32)
                self.words += ", compact all through where it is under %.1f mm thick" % plan["thin"]
        if kind == "vertebra":
            d = depth(np.asarray(D, np.float32), h); R = 0.6 * float(d.max())
            far = ndimage.distance_transform_edt(d < R) * h                         # how far from where a ball of that size has its middle
            self.body = (1.0 - smoothstep((far - R) / 2.0)).astype(np.float32)
            self.arch = plan.get("arch", 1.25)
            if up is not None:
                self.grain = (np.asarray(up, float), 1.6)                           # the body's plates stand upright
            self.words = "body's coat %.1f mm, the arch's and processes' covering %.1f mm; body told off by a ball %.0f mm across" % (plan.get("shell", 0.45), self.arch, 2 * R)

    def __call__(self, X, Y, Z):
        z, shell, opn, canal = self.prof
        f = lambda v: np.interp(np.ravel(Z), z, v).reshape(Z.shape).astype(np.float32)
        one = np.ones(np.broadcast_shapes(X.shape, Y.shape, Z.shape), np.float32)
        sh = f(shell) * one
        if self.body is not None:
            Xb, Yb, Zb = np.broadcast_arrays(X, Y, Z)
            w = ndimage.map_coordinates(self.body, [(Xb - self.lo[0]) / self.h, (Yb - self.lo[1]) / self.h, (Zb - self.lo[2]) / self.h], order=1, mode="nearest")
            sh = self.arch + (sh - self.arch) * w
        P = dict(out=sh, inn=sh, open=f(opn) * one, coarse=self.plan.get("coarse", 0.35) * one, dense=0.0 * one, cells=0.0 * one)
        if self.thin is not None:
            Xb, Yb, Zb = np.broadcast_arrays(X, Y, Z)
            P["dense"] = ndimage.map_coordinates(self.thin, [(Xb - self.lo[0]) / self.h, (Yb - self.lo[1]) / self.h, (Zb - self.lo[2]) / self.h], order=1, mode="nearest")
        if canal is not None:
            P["canal"] = f(canal[0]) * one; P["bore"] = f(canal[1]) * one
        return P

    def foam(self, side):
        return None


# which rule a bone follows, by its name (the first that fits). Thicknesses in mm are ours where Gray gives none.
PLANS = [
    ("clavicle", dict({"class": "long"}, canal=False, wall=0.34, open_mid=0.35)),   # p. 202: cancellous all through, the compact layer "much thicker in the intermediate part"
    ("tibia", dict({"class": "long"}, thickest=0.36)),                                # p. 260: "thickest at the junction of the middle and lower thirds"
    ("humerus|femur|fibula|radius|ulna|metacarpal|metatarsal|phalanx", {"class": "long"}),
    ("patella", dict({"class": "short"}, open=0.12)),                                 # p. 256: "a nearly uniform dense cancellous tissue"
    ("carpal|calcaneus|talus|navicular|cuboid|cuneiform|sesamoid", {"class": "short"}),
    ("atlas|axis|vertebra", dict({"class": "vertebra"}, shell=0.45, arch=1.25)),
    ("sacrum|coccyx|hyoid", dict({"class": "flat"}, shell=0.55)),                     # p. 111: "a thin layer of compact bone"
    ("sternum", dict({"class": "flat"}, shell=0.5, shell_top=1.0)),                   # p. 121: "thickest in the manubrium"
    ("rib", dict({"class": "flat"}, shell=0.7)),                                      # p. 127
    ("scapula", dict({"class": "flat"}, shell=1.0, thin=7.5)),                        # p. 207
    ("ilium|ischium|pubis|hip bone", dict({"class": "flat"}, shell=1.2, thin=5.5)),   # p. 237
]


def plan_for(label):
    import re
    for pat, plan in PLANS:
        if re.search(pat, label):
            return dict(plan)
    return None


def zones_for(info, D, lo, h):
    """The rule a kept field follows: a bone below the head by its plan, else the lower jaw or the skull."""
    if "bone" in info:
        return Bone(D, lo, h, info["bone"], up=info.get("up"))
    if "sutures" in info:
        return Skull()
    return Jaw.of(D, lo, h, canals=info.get("canals"))


def route(d, lo, h, a, b, enough=3.2, power=2.0):
    """The shortest way through the bone from a to b (mm) that keeps well under every surface (`d`: the depth, mm): the
    least sum of 1 / depth^power along it, a depth of `enough` counting as much as any greater one (so it runs straight
    where there is room and bends only to keep clear). It starts and ends at the bone nearest a and b."""
    from skimage.graph import route_through_array
    cost = np.where(d > 0.45, 1.0 / np.clip(d, 0.45, enough) ** power, 1.0e5).astype(np.float64)

    def at(p):
        i = np.round((np.asarray(p, float) - lo) / h).astype(int); r = int(round(4.0 / h))
        i0 = np.maximum(i - r, 0); i1 = np.minimum(i + r + 1, d.shape)
        blk = d[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]
        g = np.stack(np.meshgrid(*[np.arange(i0[k], i1[k]) for k in range(3)], indexing="ij"), -1)
        far = np.linalg.norm(g - i, axis=-1) + np.where(blk > 0.8, 0.0, 1.0e3)
        return tuple(int(v) for v in g.reshape(-1, 3)[int(np.argmin(far))])
    path, _ = route_through_array(cost, at(a), at(b), fully_connected=True, geometric=True)
    return lo + h * np.array(path, float)


def eased(P, sigma, step=0.1):
    """A broken line as a smooth one, sampled every `step` mm, its two ends where they were."""
    P = np.asarray(P, float)
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    keep = np.concatenate([[True], np.diff(s) > 1e-9]); P, s = P[keep], s[keep]
    t = np.arange(0.0, s[-1], step)
    Q = np.stack([np.interp(t, s, P[:, k]) for k in range(3)], 1)
    G = ndimage.gaussian_filter1d(Q, sigma / step, axis=0, mode="nearest")
    w0 = np.exp(-(t / (1.5 * sigma)) ** 2)[:, None]; w1 = np.exp(-((t[-1] - t) / (1.5 * sigma)) ** 2)[:, None]
    return G + w0 * (Q[0] - G[0]) + w1 * (Q[-1] - G[-1])


def jaw_canals(D, lo, h, canal, sockets, log=print):
    """The mandibular canal of both sides, found in the jaw's own bone. Gray 1918, p. 173: "The mandibular canal runs
    obliquely downward and forward in the ramus, and then horizontally forward in the body, where it is placed under the
    alveoli and communicates with them by small openings. On arriving at the incisor teeth, it turns back to communicate
    with the mental foramen, giving off two small canals which run to the cavities containing the incisor teeth."
    `canal`: the bottom of the mandibular foramen's funnel and the mental foramen's inner end, each with its direction
    (left side; mandible4.build). Between them the canal takes the shortest way that keeps 3 mm under every surface of the
    bone where the bone allows, the sockets' among them: so it runs under the roots and clear of them; it passes the mental
    foramen below and inside it and turns back up into it. Its bore is ours (Gray gives none): 2.4 mm narrowing to 2. Returns a list of
    {"name", "points" (every 0.1 mm), "radius"}."""
    D = np.asarray(D, np.float32); lo = np.asarray(lo, float)
    d = depth(D, h)
    out = []
    for side, word in ((1, "left"), (-1, "right")):
        mir = np.array([side, 1.0, 1.0])
        a, va = np.array(canal["in"][0]) * mir, np.array(canal["in"][1]) * mir
        b, vb = np.array(canal["out"][0]) * mir, np.array(canal["out"][1]) * mir
        up = np.array([0.0, 1.0, 0.0]); inward = np.array([-side, 0.0, 0.0])
        bend = b - 4.0 * vb - 1.2 * up + 1.0 * inward                      # below and inside the foramen, in front of it: where the canal turns back
        i0 = int(np.floor((-4.0 - lo[0]) / h)) if side > 0 else 0          # (one half of the jaw at a time)
        i1 = d.shape[0] if side > 0 else int(np.ceil((4.0 - lo[0]) / h))
        dh = d[i0:i1]; lh = lo + np.array([i0 * h, 0.0, 0.0])
        main = route(dh, lh, h, a + 1.2 * va, bend)
        main = eased(main, 3.0, step=0.25)                                 # (its course is no chain of arcs from one root's tip to the next)
        line = eased(np.concatenate([[a - 0.6 * va], main, [b - 1.6 * vb, b + 0.8 * vb]]), 1.3)
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(line, axis=0), axis=1))])
        rad = np.interp(s / s[-1], [0.0, 0.25, 0.8, 1.0], [1.2, 1.15, 1.05, 1.0])
        out.append(dict(name="mandibular canal, %s" % word, points=line, radius=rad))
        dd = ndimage.map_coordinates(d, ((line - lo) / h).T, order=1) - rad
        mid = (s > 5.0) & (s < s[-1] - 5.0)
        log("%s mandibular canal: %.0f mm long; between its ends the bone round it is never thinner than %.1f mm; it lies %.1f mm above the lower border under the first molar"
            % (word, s[-1], float(dd[mid].min()), float(line[np.argmin(np.abs(line[:, 2] - 65.5)), 1] - (lo[1] + h * np.argmax((D[:, :, int(round((65.5 - lo[2]) / h))] < 0).any(axis=0))))))
        for f in sockets:                                                  # "two small canals which run to the cavities containing the incisor teeth"
            if f["side"] == ("L" if side > 0 else "R") and "incisor" in f["tooth"]:
                tip = np.array(f["position_mm"], float) - (f["root_mm"] + 0.3) * np.array(f["axis"], float)
                twig = eased(np.concatenate([route(dh, lh, h, bend, tip), [tip]]), 1.0)
                out.append(dict(name="incisive canal to the %s, %s" % (f["tooth"], word), points=twig, radius=np.full(len(twig), 0.45)))
    return out


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
    Xs, Ys, Zs = X, Y, Z
    grain = getattr(zones, "grain", None)
    if grain is not None:                                                          # the spaces drawn out along one direction: plates that run that way
        a, k = np.asarray(grain[0], np.float32), np.float32(1.0 - 1.0 / grain[1])
        along = a[0] * X + a[1] * Y + a[2] * Z
        Xs, Ys, Zs = X - k * a[0] * along, Y - k * a[1] * along, Z - k * a[2] * along
        del along
    Xs, Ys, Zs = (Xs + uneven(X, Y, Z, seed + 31, 0.45, 4.5), Ys + uneven(X, Y, Z, seed + 32, 0.45, 4.9),
                  Zs + uneven(X, Y, Z, seed + 33, 0.45, 4.1))                      # (pushed about a little, so no row of spaces runs straight)
    f = lattice(Xs, Ys, Zs, X, Y, Z, m, P["coarse"], seed)
    del Xs, Ys, Zs
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
    level = level + 0.22 * uneven(X, Y, Z, seed + 23, 1.0, 5.0)                    # the bars stouter here, slighter there
    canal = None
    if "canal" in P:                                                               # a long bone's marrow canal: it begins sooner in the bone's middle than along its wall, and on no ruled line
        late = 1.3 * P["bore"] * (1.0 - np.clip(m / P["bore"], 0.0, 1.0)) ** 1.5      # (mm further into the body, at the wall)
        canal = smoothstep((P["canal"] - late + uneven(X, Y, Z, seed + 7, 2.5, 24.0) + uneven(X, Y, Z, seed + 8, 0.8, 7.0)) / 5.0)
        level = level + canal * (1.6 + 1.2 * np.maximum(m, 0.0))                   # the few bars left in it keep to its wall
    q = np.maximum(np.maximum((f - level) * 0.3, -m), keep)                        # below 0 in a marrow space
    q = np.minimum(q, np.maximum(-room, -m))                                       # or in an air cell
    kind[(kind != AIR) & (cells > 0.5) & (m > 0)] = CELLS
    tube = None
    canals = getattr(zones, "canals", None)
    if canals:                                                                     # canals for a nerve and vessels, each in its own thin wall
        pts = np.concatenate([c["points"] for c in canals]); rad = np.concatenate([c["radius"] for c in canals])
        b0, b1 = pts.min(axis=0) - 3.0, pts.max(axis=0) + 3.0
        sel = (Xb > b0[0]) & (Xb < b1[0]) & (Yb > b0[1]) & (Yb < b1[1]) & (Zb > b0[2]) & (Zb < b1[2])
        tube = np.full(m.shape, 9.0, np.float32)
        if sel.any():
            dn, jn = cKDTree(pts).query(np.stack([Xb[sel], Yb[sel], Zb[sel]], 1), distance_upper_bound=4.0)
            ok = np.isfinite(dn); t = np.full(dn.shape, 9.0, np.float32); t[ok] = dn[ok] - rad[jn[ok]]
            tube[sel] = t
        q = np.maximum(q, 0.3 - np.abs(tube - 0.25))
        q = np.minimum(q, tube)
    B = A.copy() if slab is not None else A
    B[sl] = np.maximum(A[sl], -q)
    # what is drawn as cancellous or as cells is what lies among the spaces: bone further than a bar's width from any space
    # is compact, whatever zone it is in
    space = (q < 0) if tube is None else ((q < 0) & (tube >= 0))
    near = ndimage.binary_dilation(space, iterations=max(int(round(0.75 / h)), 1))
    kind[(kind != AIR) & ~near] = COMPACT
    kind[space & (kind == AIR)] = SPONGY
    kind[space & (cells > 0.5)] = CELLS
    if canal is not None:
        kind[space & (canal > 0.2)] = MARROW                                       # the marrow canal of a long bone's body: from where the bars give out
    if tube is not None:
        kind[(tube < 0) & (A[sl] < 0)] = CANAL
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
C, S, A_, M, N = "compact", "cancellous", "air", "marrow canal", "canal"
ATLAS = "rule written; drawn on the atlas's bone"          # (tools/anatomy_inside.py: the from-scratch model has no bone below the head yet)
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
    ("Temporal", "mastoid part", [C, A_, S], 142, "At the upper and front part of the process they are large and irregular and contain air, but toward the lower part they diminish in size, while those at the apex of the process are frequently quite small and contain marrow", "yes (cells; the tympanic cavity not yet: the petrous part must first be built up inside the skull)"),
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
    ("Mandible", "body", [C, S], 80, "~an irregular bone (p. 80): cancellous within a compact shell, here thickest along the lower border", "yes"),
    ("Mandible", "the mandibular canal", [N], 173, "The mandibular canal runs obliquely downward and forward in the ramus, and then horizontally forward in the body, where it is placed under the alveoli", "yes (its small openings into the sockets not yet)"),
    ("Mandible", "ramus, coronoid process", [C, S], 80, "~two compact plates, cancellous between them where the ramus is thick; the coronoid and the middle of the ramus compact", "yes"),
    ("Mandible", "head (condyle)", [C, S], 279, "spongy cancellous tissue with a thin coating of compact substance", "yes"),
    ("Hyoid", "the whole bone", [C, S], 80, "cancellous tissue enclosed within a thin layer of compact bone", ATLAS),
    ("Vertebra", "body", [C, S], 97, "The body is composed of cancellous tissue, covered by a thin coating of compact bone", ATLAS),
    ("Vertebra", "arch and processes", [C, S], 97, "The arch and processes projecting from it have thick coverings of compact tissue.", ATLAS),
    ("Sacrum, coccyx", "the whole bone", [C, S], 111, "The sacrum consists of cancellous tissue enveloped by a thin layer of compact bone.", ATLAS),
    ("Sternum", "the whole bone", [C, S], 121, "highly vascular cancellous tissue, covered by a thin layer of compact bone which is thickest in the manubrium between the articular facets for the clavicles", ATLAS),
    ("Ribs", "the whole bone", [C, S], 127, "The ribs consist of highly vascular cancellous tissue, enclosed in a thin layer of compact bone.", ATLAS),
    ("Clavicle", "the whole bone", [C, S], 202, "cancellous tissue, enveloped by a compact layer, which is much thicker in the intermediate part than at the extremities of the bone", ATLAS),
    ("Scapula", "head, processes, thickened parts", [C, S], 207, "The head, processes, and the thickened parts of the bone, contain cancellous tissue", ATLAS),
    ("Scapula", "the blade", [C], 207, "the rest consists of a thin layer of compact tissue", ATLAS),
    ("Long bones (humerus, radius, ulna, femur, tibia, fibula, metacarpals, metatarsals, phalanges)", "body (shaft)", [C, M], 79, "the wall consists of dense, compact tissue of considerable thickness in the middle part of the body, but becoming thinner toward the extremities", ATLAS),
    ("Long bones", "extremities", [C, S], 79, "consist of cancellous tissue surrounded by thin compact bone", ATLAS),
    ("Long bones", "within the marrow canal", [S, M], 79, "within the medullary canal is some cancellous tissue, scanty in the middle of the body but greater in amount toward the ends", ATLAS),
    ("Long bones", "the marrow", [M], 87, "In the bodies of the long bones the marrow is of a yellow color", ATLAS),
    ("Flat and short bones, ends of the long bones, bodies of the vertebrae", "the marrow", [S], 87, "In the flat and short bones, in the articular ends of the long bones, in the bodies of the vertebrae, in the cranial diploe, and in the sternum and ribs the marrow is of a red color", ATLAS),
    ("Humerus", "body", [C, M], 212, "a cylinder of compact tissue, thicker at the center than toward the extremities, and contains a large medullary canal which extends along its whole length", ATLAS),
    ("Ulna, radius", "body", [C, M], 219, "The long, narrow medullary cavity is enclosed in a strong wall of compact tissue which is thickest along the interosseous border", ATLAS),
    ("Femur", "lower end", [C, S], 253, "there remains only a thin shell of compact bone", ATLAS),
    ("Tibia", "body", [C, M], 260, "The compact wall of the body is thickest at the junction of the middle and lower thirds of the bone.", ATLAS),
    ("Hip bone", "thicker parts", [C, S], 237, "The thicker parts of the bone consist of cancellous tissue, enclosed between two layers of compact tissue", ATLAS),
    ("Hip bone", "bottom of the acetabulum, centre of the iliac fossa", [C], 237, "usually semitransparent, and composed entirely of compact tissue", ATLAS),
    ("Patella", "the whole bone", [C, S], 256, "a nearly uniform dense cancellous tissue, covered by a thin compact lamina", ATLAS),
    ("Carpal and tarsal bones", "the whole bone", [C, S], 79, "These consist of cancellous tissue covered by a thin crust of compact substance.", ATLAS),
]
