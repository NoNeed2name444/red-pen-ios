"""foot_whole.py: the right tarsus built WHOLE, as one solid, then cut along its joints into its seven bones.

The owner, 25 Nov: "let's change the approach for complex bone collections. make the full foot bones then we separate
them." Built so far one by one (foot.py, talus.py, midfoot.py, cuneiforms.py) and then posed, the bones never fitted:
the talus stood 7 mm over the calcaneus, the two bones' facets disagreed by 5 to 14 mm, neighbours ran into each other.
Here a joint is ONE surface and the two bones' faces are that surface moved half a joint space to either side, so they
fit by construction.

Plates (Gray, Anatomy of the Human Body, 20th ed., 1918, public domain): the foot assembled, Fig. 268 (from above), 269
(from below), 290 (medial), 291 (lateral), through foot_frame.py's registration (269 is registered here, on 268); each
bone's own plates (264 to 267 calcaneus, 270 to 273 talus, 274/275 cuboid, 276/277 navicular, 278 to 283 cuneiforms)
through the single-bone builds, which are only sources of shape here, not the assembly.

Frame: foot_frame.py's (right foot, x medial, y up, z forward, mm; the origin the navicular's middle).

The build (whole()):
  1. each single-bone build is set at its place in the foot (POSE: foot_frame.TARGET, the navicular where it stands)
     and sampled on one grid; their union is where the bone's own plates give the shape the assembly plates cannot see
     (the sinus tarsi's walls, the sole's hollows, the joint faces' curvature);
  2. the joint network (JOINTS, joint_surfaces()): each joint one surface. Its form inside the foot (ball, saddle, convex
     along one axis) is the two bones' facing surfaces' middle, fitted as a quadric (or the talar head's ellipsoid), with
     the sign of each curvature checked against Gray's text; its trace on the outside (where it meets the air) is moved
     and tilted onto the joint lines drawn in Fig. 268/290/291, lifted on to the solid;
  3. the solid is made whole across each joint: between the two bones, over the joint's extent, it is filled up to the
     surface from both sides (where the posed bones stand apart, as the talus over the calcaneus) and the posed bones'
     overlap is split by the surface; the sinus tarsi and tarsal canal are kept open (a hollow shaped on the calcaneal
     and talar sulci) and so are the non-articular spaces between neighbours (whatever the posed bones leave open);
  4. the whole solid's outline is drawn on to the four assembly plates (outline_push): where its silhouette lies outside
     or inside a plate's, the surface there (only where it is seen edge on in that plate) is moved to the plate's;
  5. the cut (bones()): the whole solid is split in a fixed order of surfaces (CUTS) and each bone is the whole solid on
     its side of every surface it borders, moved back half the joint space (GAP / 2) and rounded into the joint (EDGE).
bones() returns each bone and the assembled set in the foot frame; later code (metatarsals, phalanges) adds bones to
POSE, JOINTS and CUTS and to the same grid.
"""
import os
import pickle
import time
import numpy as np
from scipy import ndimage as ndi
import sdf
import foot_frame as ff

HERE = os.path.dirname(os.path.abspath(__file__))
BONES = ("calcaneus", "talus", "navicular", "cuboid", "first", "second", "third")

GAP = 1.2          # mm: the joint space in the dry articulated foot (both faces together), half on each bone
EDGE = 0.9         # mm: how far a joint face is rounded into the bone's outer surface (no saw-cut edges)
H = 0.5            # mm: the grid
BOX = ((-62.0, -74.0, -98.0), (34.0, 34.0, 44.0))   # the tarsus in the foot frame, with room round it

_ORTH = lambda R: (lambda u, s, vt: u @ vt)(*np.linalg.svd(np.asarray(R, float)))


# ---------------------------------------------------------------------------------------------------- 1. the bones set
# Moves on top of foot_frame.TARGET: {bone: (turn axis, degrees, pivot (foot frame), then a shift mm)}.
# The third cuneiform: Fig. 291 draws its dorsolateral border at y 9.5 to 11.5 mm (pixels (250, 61) to (281, 50)) with
# the second's dorsal strip above it at 19.5, where the target pose holds the third's top at 20 to 23 (the target
# raised it 6.3 mm over cuneiforms.HEIGHT on the evidence of that plate's upper half only, foot_frame.TARGET): it is
# set 5 mm lower, nearly back to the height cuneiforms.py gives it. (Rolled instead, lateral side down, its sole swung
# under the second.)
POSE_TURN = {"third": ((0.0, 0.0, 1.0), 0.0, (-22.0, 20.0, 15.0), (0.0, -5.0, 0.0))}


def pose(name):
    """(R, t): foot point = R @ own point + t. foot_frame.TARGET (each bone fitted to Fig. 268/290/291), the navicular
    where it stands (it defines the frame; its target is within the side plates' reading error, foot_frame.TARGET),
    then POSE_TURN."""
    if name == "navicular":
        R, t = np.eye(3), np.zeros(3)
    else:
        R, t = ff.pose(name); R = _ORTH(R)
    if name in POSE_TURN:
        ax, deg, c, sh = POSE_TURN[name]; Q = sdf.rot(ax, deg); c = np.asarray(c, float)
        R, t = Q @ R, Q @ (t - c) + c + np.asarray(sh, float)
    return R, t


class Grid:
    """A field on a box (D, lo, h, n) in the foot frame; also what platematch.cast reads."""
    def __init__(self, D, lo, h):
        self.D = D; self.lo = np.asarray(lo, float); self.h = float(h); self.n = np.array(D.shape)
        self.ax = [(self.lo[k] + self.h * np.arange(self.n[k])).astype(np.float32) for k in range(3)]


def build_one(name, h=None, log=print):
    """A single-bone build (its own frame), as its module makes it."""
    q = lambda *a: None
    if name == "calcaneus":
        import foot; return foot.calcaneus(log=q)
    if name == "talus":
        import talus; return talus.talus(log=q)
    if name == "navicular":
        import midfoot; return midfoot.navicular(0.3, log=q)
    if name == "cuboid":
        import midfoot; return midfoot.cuboid(0.3, log=q)
    import cuneiforms; return cuneiforms.cuneiform(name, 0.3, log=q)


def own_fields(cache=None, log=print):
    """{name: Grid} of the single-bone builds in their own frames; kept (float16) in `cache` if given."""
    out = {}
    for name in BONES:
        path = cache and os.path.join(cache, name + ".pkl")
        if path and os.path.exists(path):
            d = pickle.load(open(path, "rb")); out[name] = Grid(np.asarray(d["D"], np.float32), d["lo"], d["h"]); continue
        t = time.time(); F = build_one(name)
        out[name] = Grid(np.asarray(F.D, np.float32), F.lo, F.h)
        if path:
            pickle.dump(dict(D=np.asarray(F.D, np.float16), lo=np.asarray(F.lo, float), h=float(F.h)), open(path, "wb"))
        log("  %s built in %.0f s" % (name, time.time() - t))
    return out


def grid_points(lo, n, h, sl=None):
    ax = [lo[k] + h * np.arange(n[k]) for k in range(3)]
    if sl is not None:
        ax = [ax[k][sl[k]] for k in range(3)]
    return np.meshgrid(*ax, indexing="ij")


def sample(G, P, cval=30.0):
    """A Grid's value at points P (..., 3) mm (linear)."""
    P = np.asarray(P, float); sh = P.shape[:-1]; Q = P.reshape(-1, 3)
    v = ndi.map_coordinates(G.D, [(Q[:, k] - G.lo[k]) / G.h for k in range(3)], order=1, mode="constant", cval=cval)
    return v.reshape(sh).astype(np.float32)


def posed(G, R, t, lo, n, h):
    """A bone's own field carried into the foot frame and sampled on the grid (lo, n, h)."""
    out = np.empty(tuple(n), np.float32)
    ys, zs = lo[1] + h * np.arange(n[1]), lo[2] + h * np.arange(n[2])
    Yg, Zg = np.meshgrid(ys, zs, indexing="ij")
    for i in range(n[0]):
        P = np.stack([np.full_like(Yg, lo[0] + h * i), Yg, Zg], -1)
        out[i] = sample(G, (P - t) @ R)
    return out


# ------------------------------------------------------------------------------------------------ the assembly plates
REFS = os.path.join(os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out"), "refs_foot")
# Fig. 269 (from below) registered here on Fig. 268: the two whole-foot silhouettes laid over each other (the plantar
# mirrored), turn, scale and place fitted over the tarsus (z < 40 mm): overlap 0.918; the two outlines lie 1.63 mm apart
# on the mean (worst tenth 3.5 mm), what the two plates disagree by (wholeF/sc/reg269.py, 25 Nov). frame (x, z) ->
# pixel: u = U0 + (c (-x) - s z) / S, v = V0 + (s (-x) + c z) / S, (c, s) the turn.
FIG269 = dict(th=1.7405, s=0.19820, u0=210.993, v0=463.580)


# Fig. 269's joint lines (pixels), read here under a 10 px grid at three times: the talus's head over the navicular,
# the calcaneocuboid line, the navicular's front border over the first cuneiform and the first-second line.
JOINTS269 = {("talus", "navicular"): [(160, 402), (175, 408), (190, 412), (210, 415), (230, 413), (250, 407)],
             ("calcaneus", "cuboid"): [(300, 388), (320, 391), (340, 393), (360, 394), (380, 397), (400, 402)],
             ("navicular", "first"): [(155, 494), (180, 497), (200, 499), (220, 500), (250, 503)],
             ("first", "second"): [(250, 503), (250, 520), (249, 535), (247, 560)]}


def view(fig):
    """A plate's picture basis in the foot frame: (right, up, toward the eye) rows, mm a pixel, origin pixel."""
    if fig == "Gray268":
        return np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]]), 0.208, 377.0, 440.0
    if fig == "Gray269":
        c, s = np.cos(np.radians(FIG269["th"])), np.sin(np.radians(FIG269["th"]))
        return np.array([[-c, 0, -s], [s, 0, -c], [0, -1.0, 0]]), FIG269["s"], FIG269["u0"], FIG269["v0"]
    p = ff.PLATES[fig]; R = np.asarray(p["R"], float)
    return np.array([R[0], R[1], -R[2]]), p["s"], p["u0"], p["v0"]       # the eye: medial for 290, lateral for 291


def to_pixels(fig, P):
    B, s, u0, v0 = view(fig); P = np.asarray(P, float)
    return u0 + (P @ B[0]) / s, v0 - (P @ B[1]) / s


# The tarsus's part of each plate (pixels): what lies behind the tarsometatarsal joints and off the fifth metatarsal's
# tuberosity. Outside it a plate's outline is the metatarsals' and is neither followed nor scored.
CARE = {
    "Gray268": [(150, 0), (490, 0), (490, 590), (419, 592), (414, 602), (402, 602), (390, 608), (375, 617), (360, 622), (345, 622),
                (335, 617), (328, 605), (325, 558), (315, 562), (299, 566), (285, 566), (275, 562), (267, 554), (262, 566), (255, 568),
                (245, 560), (231, 552), (221, 542), (214, 533), (201, 526), (181, 511), (167, 497), (160, 480), (162, 450), (168, 400),
                (175, 300), (150, 290)],
    "Gray290": [(0, 0), (282, 0), (282, 80), (280, 87), (273, 95), (265, 102), (260, 108), (258, 118), (255, 128), (252, 135),
                (250, 189), (0, 189)],
    "Gray291": [(500, 0), (250, 0), (250, 61), (247, 67), (251, 75), (257, 81), (265, 89), (271, 93), (273, 97), (281, 105),
                (291, 109), (303, 115), (311, 127), (320, 140), (500, 179)],
}


def _care269():
    """Fig. 269's tarsal part: Fig. 268's carried over through the two registrations (both are plans)."""
    P = np.asarray(CARE["Gray268"], float); X = (P[:, 0] - 377.0) * 0.208; Z = (P[:, 1] - 440.0) * 0.208
    u, v = to_pixels("Gray269", np.stack([X, 0 * X, Z], 1)); return list(zip(u, v))


def plate_gray(fig):
    from PIL import Image
    return np.asarray(Image.open(os.path.join(REFS, fig + ".png")).convert("RGB")).astype(np.float32)


def plate_mask(fig):
    """The whole foot's silhouette in a plate (ink against the page; Fig. 269's red muscle marks counted as ink, its
    leader lines opened away), and the tarsal part of the plate (CARE)."""
    from PIL import Image, ImageDraw
    a = plate_gray(fig); g = a.mean(2)
    if fig == "Gray269":
        m = (g < 200) | (a[..., 0] - a[..., 1] > 60)
        m = ndi.binary_opening(ndi.binary_fill_holes(ndi.binary_closing(m, iterations=2)), iterations=3)
    else:
        m = ndi.binary_fill_holes(ndi.binary_closing(g < 200, iterations=2))
    lab, n = ndi.label(m); m = lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1)))))
    poly = _care269() if fig == "Gray269" else CARE[fig]
    im = Image.new("L", (m.shape[1], m.shape[0]), 0); ImageDraw.Draw(im).polygon([tuple(map(float, p)) for p in poly], fill=255)
    return m, np.asarray(im) > 0


def cast(G, fig, size=None, sub=1):
    """A field drawn in a plate's own frame: (depth toward the eye mm, nan where nothing; normals in the picture's
    basis), at the plate's pixels."""
    import platematch as pm
    B, s, u0, v0 = view(fig)
    if size is None:
        g = plate_gray(fig); size = (g.shape[1], g.shape[0])
    return pm.cast(G, B, s, u0, v0, size, sub=sub)


def _edge(m):
    return m & ~ndi.binary_erosion(m)


def outline_gap(fig, model, plate=None, care=None):
    """How far the model's silhouette (a mask at the plate's pixels) lies from the plate's, both ways, in mm, over the
    tarsal part of the plate (the line where that part is cut off is not an outline and is left out): (mean, worst
    tenth's least, the model's outline pixels, the plate's)."""
    if plate is None:
        plate, care = plate_mask(fig)
    s = view(fig)[1]
    cut = ndi.binary_dilation(_edge(care), iterations=3)
    k = int(np.ceil(1.0 / s))                     # see-through joint spaces and gaps between bones are not the outline
    model = ndi.binary_fill_holes(ndi.binary_closing(np.pad(model, k), iterations=k))[k:-k, k:-k]
    a = model & care; b = plate & care
    ea = _edge(a) & ~cut; eb = _edge(b) & ~cut
    d = np.concatenate([ndi.distance_transform_edt(~eb)[ea], ndi.distance_transform_edt(~ea)[eb]]) * s
    return float(d.mean()), float(np.percentile(d, 90)), ea, eb


# -------------------------------------------------------------------------------------------------- 2. the joints
# One surface a joint. a, b: the two bones (the surface's normal runs from a to b; g < 0 on a's side). form: "head" the
# talar head's ellipsoid (talus.HEAD_*, fitted on its articular front 0.4 mm rms), moved onto the drawn joint lines;
# "quad" a quadric height over the joint's plane, its curvature from `curv` (the bone whose own plates show that face
# best, Gray's text naming its form), its place and tilt from the drawn joint lines. patch: where the joint is: the
# calcaneus's own facets as Fig. 264 outlines them (CALC_FACETS: 0 posterior, 1 middle, 2 anterior), or "facing" (where
# the two posed bones' surfaces face each other within `reach` mm). form_check: Gray's words for the surface, tested on
# the fitted curvatures (seen from a): "convex": bulging toward b... along the long axis; "saddle"; "concave".
JOINTS = {
    "TN":   dict(a="talus", b="navicular", form="head", traces={"Gray268": ("talus", "navicular"), "Gray290": ("talus", "navicular"),
                                                                "Gray291": ("talus", "navicular")},
                 gray="p. 268: the head 'oval ... articulates with the navicular' (a ball in the navicular's hollow)"),
    "TCp":  dict(a="calcaneus", b="talus", form="quad", curv="calcaneus", patch=("calc", (0,)), check="convex",
                 traces={"Gray291": ("talus", "calcaneus", "posterior")},
                 gray="p. 265: the calcaneus's posterior facet 'convex from behind forward'; p. 268: the talus's 'deeply "
                      "concave in the direction of its long axis which runs forward and lateralward at about 45 degrees'"),
    "TCm":  dict(a="calcaneus", b="talus", form="quad", curv="calcaneus", patch=("calc", (1, 2)), check="concave",
                 traces={"Gray290": ("talus", "calcaneus"), "Gray291": ("talus", "calcaneus")},
                 gray="p. 268: the talus's middle facet 'slightly convex', the anterior on the head: the calcaneus's two "
                      "carry it as a shallow cup"),
    "CC":   dict(a="calcaneus", b="cuboid", form="quad", curv="calcaneus", patch="facing", check="saddle", hollow=(-1.0, -1.0, 0.0),
                 traces={"Gray268": ("calcaneus", "cuboid"), "Gray291": ("calcaneus", "cuboid")},
                 gray="p. 265: 'concave from above downward and lateralward, and convex in a direction at right angles'"),
    "NC1":  dict(a="navicular", b="first", form="quad", curv="navicular", patch="facing", check="convex",
                 traces={"Gray268": ("navicular", "first"), "Gray290": ("navicular", "first")},
                 gray="p. 270: the navicular's front 'convex from side to side', in three facets"),
    "NC2":  dict(a="navicular", b="second", form="quad", curv="navicular", patch="facing", check="convex",
                 traces={"Gray268": ("navicular", "second"), "Gray290": ("navicular", "second")}, gray="as NC1"),
    "NC3":  dict(a="navicular", b="third", form="quad", curv="navicular", patch="facing", check="convex",
                 traces={"Gray268": ("navicular", "third"), "Gray291": ("navicular", "third")}, gray="as NC1"),
    "NCu":  dict(a="cuboid", b="navicular", form="quad", curv=None, patch="facing", check=None,
                 traces={"Gray268": ("navicular", "cuboid"), "Gray291": ("navicular", "cuboid")},
                 gray="p. 270: the navicular's lateral surface 'occasionally' a facet for the cuboid; mostly ligament"),
    "C3Cu": dict(a="cuboid", b="third", form="quad", curv=None, patch="facing", check=None,
                 traces={"Gray268": ("third", "cuboid"), "Gray291": ("third", "cuboid")},
                 gray="p. 273: the third cuneiform's lateral surface, a facet for the cuboid behind"),
    "C12":  dict(a="second", b="first", form="quad", curv=None, patch="facing", check=None,
                 traces={"Gray268": ("first", "second"), "Gray290": ("first", "second")},
                 gray="p. 272: the first cuneiform's lateral surface, an L-shaped facet for the second"),
    "C23":  dict(a="third", b="second", form="quad", curv=None, patch="facing", check=None,
                 traces={"Gray268": ("second", "third"), "Gray291": ("second", "third")},
                 gray="p. 273: the second's lateral surface, the third's medial"),
}
# The cut: the whole split in this order, each surface a blend of the listed joints' (A's side negative).
CUTS = [
    ("chopart",   ("calcaneus", "talus"), ("navicular", "cuboid", "first", "second", "third"), ("TN", "CC")),
    ("subtalar",  ("calcaneus",), ("talus",), ("TCp", "TCm")),
    ("cuboid",    ("cuboid",), ("navicular", "first", "second", "third"), ("NCu", "C3Cu")),
    ("cuneonav",  ("navicular",), ("first", "second", "third"), ("NC1", "NC2", "NC3")),
    ("medial",    ("second", "third"), ("first",), ("C12",)),
    ("lateral",   ("third",), ("second",), ("C23",)),
]


def _calc_facet_own(G, which):
    """The calcaneus's upper facets (CALC_FACETS, Fig. 264) as points of its own surface: those facing up whose Fig. 264
    pixel falls inside the traced border, the topmost over each plan cell."""
    import foot, platematch as pm
    from PIL import Image, ImageDraw
    idx = np.argwhere(np.abs(G.D) < 0.5 * G.h); P = G.lo + G.h * idx
    gr = np.stack([sample(G, P + k) - sample(G, P - k) for k in np.eye(3) * G.h], 1); n = gr / (np.linalg.norm(gr, axis=1)[:, None] + 1e-9)
    tr = foot.traces("calcaneus"); V = {v["fig"]: v for v in pm.CALCANEUS}; p4 = np.asarray(tr["Gray264_pose"], float)
    u, v = foot._pixels(V["Gray264"], p4, P[:, 0], P[:, 1], P[:, 2])
    shp = tr["Gray264_sdf"].shape; out = []
    for i in which:
        poly = [(87.0 + x / 0.225, 421.0 - z / 0.225) for x, z in sdf.spline(np.asarray(foot.CALC_FACETS[i], float), 0.4, closed=True)]
        im = Image.new("L", shp[::-1], 0); ImageDraw.Draw(im).polygon(poly, fill=255); m = np.asarray(im) > 0
        k = (ndi.map_coordinates(m.astype(np.float32), [v, u], order=0) > 0.5) & (n[:, 1] > 0.3)
        Q = P[k]; key = np.round(Q[:, [0, 2]]).astype(int); top = {}
        for kk, y in zip(map(tuple, key), Q[:, 1]):
            top[kk] = max(top.get(kk, -1e9), y)
        out.append(Q[np.array([y > top[kk] - 2.0 for kk, y in zip(map(tuple, key), Q[:, 1])])])
    return np.vstack(out)


def _grad_at(D, lo, h, P):
    G = Grid(D, lo, h)
    g = np.stack([sample(G, P + k) - sample(G, P - k) for k in np.eye(3) * h], 1)
    return g / (np.linalg.norm(g, axis=1)[:, None] + 1e-9)


def contact(Dp, a, b, lo, h, reach=14.0):
    """Points of the middle surface between two posed bones where they face each other (|d_a - d_b| small, d_a + d_b
    below `reach`, their normals opposed): (points, the normal from a to b at each)."""
    A, B = Dp[a], Dp[b]
    m = (np.abs(A - B) < 0.6 * h) & (A + B < reach)
    idx = np.argwhere(m); P = lo + h * idx
    if len(P) == 0:
        return P, P
    na = _grad_at(A, lo, h, P); nb = _grad_at(B, lo, h, P)
    k = (na * nb).sum(1) < -0.6
    n = na - nb; n /= np.linalg.norm(n, axis=1)[:, None] + 1e-9
    return P[k], n[k]


class Quad:
    """A joint surface: a quadric height over a plane. g(x) < 0 on a's side, scaled to about unit slope."""
    def __init__(self, o, E, c):
        self.o = np.asarray(o, float); self.E = np.asarray(E, float); self.c = np.asarray(c, float)   # E rows: e1, e2, n

    def uvw(self, P):
        q = np.asarray(P, float) - self.o; return q @ self.E[0], q @ self.E[1], q @ self.E[2]

    def height(self, u, v):
        c = self.c; return c[0] + c[1] * u + c[2] * v + c[3] * u * u + c[4] * u * v + c[5] * v * v

    def __call__(self, P):
        u, v, w = self.uvw(P); c = self.c
        gu = c[1] + 2 * c[3] * u + c[4] * v; gv = c[2] + c[4] * u + 2 * c[5] * v
        return ((w - self.height(u, v)) / np.sqrt(1.0 + gu * gu + gv * gv)).astype(np.float32)

    def curvatures(self):
        """Principal curvatures (1/mm) of the height at the patch's middle and their directions in the frame: positive
        = the surface curls toward b (concave seen from b, convex seen from a)."""
        Hm = np.array([[2 * self.c[3], self.c[4]], [self.c[4], 2 * self.c[5]]]); k, V = np.linalg.eigh(Hm)
        return k, [V[0, i] * self.E[0] + V[1, i] * self.E[1] for i in range(2)]


class Head:
    """The talonavicular surface: the talar head's ellipsoid (talus.HEAD_*) carried into the frame and moved by `shift`
    and grown by `grow` mm; g < 0 inside (the talus's side)."""
    def __init__(self, shift=(0.0, 0.0, 0.0), grow=0.0):
        import talus
        R, t = pose("talus")
        self.c = R @ np.asarray(talus.HEAD_C, float) + t + np.asarray(shift, float)
        self.ax = R @ np.asarray(talus.HEAD_AX, float); self.r = np.asarray(talus.HEAD_R, float) + grow
        self.shift = np.asarray(shift, float); self.grow = grow

    def __call__(self, P):
        """Behind the head's middle (along its long axis, forward) all is the talus's side; in front, the ellipsoid."""
        E = sdf.Ellipsoid(self.c, self.r, self.ax); P = np.asarray(P, float)
        f = self.ax[:, 2] if self.ax[2, 2] > 0 else -self.ax[:, 2]
        return np.minimum(E(P[..., 0], P[..., 1], P[..., 2]), (P - self.c) @ f).astype(np.float32)


def lift(fig, pix, G, reach=3.0):
    """Points drawn on a plate (pixels) carried on to the solid G: along each one's line of sight, the first point where
    the line enters the solid, or where it passes closest to it (within `reach` mm: a drawn joint line falls on the
    joint's gap). Returns (points (n, 3), found (n,))."""
    B, s, u0, v0 = view(fig); pix = np.asarray(pix, float)
    P0 = (pix[:, 0] - u0)[:, None] * s * B[0] + (v0 - pix[:, 1])[:, None] * s * B[1]
    corners = G.lo + np.array([[i, j, k] for i in (0, 1) for j in (0, 1) for k in (0, 1)]) * (G.n - 1) * G.h
    t = corners @ B[2]; ts = np.arange(t.max(), t.min(), -0.5 * G.h)
    D = np.stack([sample(G, P0 + tk * B[2], cval=50.0) for tk in ts], 1)       # (n, steps)
    inside = D < 0; first = np.where(inside.any(1), inside.argmax(1), D.argmin(1))
    ok = inside.any(1) | (D.min(1) < reach)
    return P0 + ts[first][:, None] * B[2], ok


def _resample(P, step):
    P = np.asarray(P, float); out = [P[0]]
    for a, b in zip(P[:-1], P[1:]):
        k = max(1, int(np.ceil(np.linalg.norm(b - a) / step))); out += [a + (b - a) * i / k for i in range(1, k + 1)]
    return np.array(out)


def joint_traces(name, G):
    """The joint lines drawn for a joint, lifted on to the solid G: {fig: (points, found)}."""
    out = {}
    for fig, key in JOINTS[name]["traces"].items():
        J = ff.JOINTS268 if fig == "Gray268" else ff.JOINTS_SIDE[fig]
        pts = J.get(tuple(key)) or J.get(tuple(key[:2][::-1]) + tuple(key[2:]))
        if pts is None or len(pts) < 2:
            continue
        out[fig] = lift(fig, _resample(pts, 1.0), G)
    return out


def _plane(P, toward):
    o = P.mean(0); _, _, vt = np.linalg.svd(P - o, full_matrices=False); n = vt[2]
    if n @ toward < 0:
        n = -n
    e1 = vt[0]; e2 = np.cross(n, e1)
    return o, np.array([e1, e2, n])


def _quadfit(u, v, w, wt=None, cmax=1.0 / 12.0):
    A = np.stack([np.ones_like(u), u, v, u * u, u * v, v * v], 1); wt = np.ones_like(u) if wt is None else wt
    c = np.linalg.lstsq(A * wt[:, None], w * wt, rcond=None)[0]
    k = np.linalg.eigvalsh(np.array([[2 * c[3], c[4]], [c[4], 2 * c[5]]]))
    if np.abs(k).max() > cmax:                    # a patch too small to hold its curvature: held to a gentler one
        c[3:] *= cmax / np.abs(k).max()
    return c


def fit_joint(name, Dp, lo, h, G, own=None, log=print):
    """The joint's surface (Quad or Head) and its patch points, fitted as JOINTS says. G: the union of the posed bones
    (what the drawn joint lines are lifted on to). Returns dict(surf, patch, traces, report)."""
    J = JOINTS[name]; a, b = J["a"], J["b"]
    T = joint_traces(name, G)
    TP = np.vstack([p[k] for p, k in T.values()]) if T else np.zeros((0, 3))
    rep = {"traces": {f: int(k.sum()) for f, (p, k) in T.items()}}
    if J["form"] == "head":
        from scipy.optimize import minimize
        P, nrm = contact(Dp, a, b, lo, h, reach=10.0)
        f = lambda x: float(np.mean(Head(x[:3], x[3])(TP) ** 2) + 0.01 * np.sum(x[:3] ** 2) + 0.05 * x[3] ** 2)
        x = minimize(f, np.zeros(4), method="Powell").x
        surf = Head(x[:3], x[3]); rep.update(shift=np.round(x[:3], 2).tolist(), grow=round(float(x[3]), 2),
                                             trace_rms=round(float(np.sqrt(np.mean(surf(TP) ** 2))), 2))
        return dict(surf=surf, patch=P, traces=T, report=rep)
    # the patch and its plane
    if isinstance(J["patch"], tuple):
        R, t = pose("calcaneus"); P = _calc_facet_own(own["calcaneus"], J["patch"][1]) @ R.T + t
        toward = np.array([0.0, 1.0, 0.0])
    else:
        P, nrm = np.zeros((0, 3)), None
        for reach in (6.0, 10.0, 16.0, 24.0):
            P, nrm = contact(Dp, a, b, lo, h, reach)
            if len(P) > 150:
                break
        if len(TP):                                   # the facing part near the joint's drawn lines, not elsewhere
            from scipy.spatial import cKDTree
            d, _ = cKDTree(TP).query(P); keep = d < 15.0
            if keep.sum() > 50:
                P, nrm = P[keep], nrm[keep]
        toward = nrm.mean(0)
    o, E = _plane(P, toward)
    q = P - o; u, v, w = q @ E[0], q @ E[1], q @ E[2]
    c = _quadfit(u, v, w)
    if J.get("curv"):                                 # the curvature of that bone's own face over the patch
        Gb = Grid(Dp[J["curv"]], lo, h); s = 1.0 if J["curv"] == a else -1.0
        lo2 = P.min(0) - 6; hi2 = P.max(0) + 6
        sl = tuple(slice(max(0, int((lo2[k] - lo[k]) / h)), int((hi2[k] - lo[k]) / h) + 1) for k in range(3))
        idx = np.argwhere(np.abs(Dp[J["curv"]][sl]) < 0.6 * h) + np.array([x.start for x in sl]); Q = lo + h * idx
        nq = _grad_at(Dp[J["curv"]], lo, h, Q)
        qq = Q - o; uq, vq, wq = qq @ E[0], qq @ E[1], qq @ E[2]
        from scipy.spatial import cKDTree
        dd, _ = cKDTree(np.stack([u, v], 1)).query(np.stack([uq, vq], 1))
        k = (dd < 1.5) & (s * (nq @ E[2]) > 0.5) & (np.abs(wq) < 10.0)
        if k.sum() > 30:
            cb = _quadfit(uq[k], vq[k], wq[k]); c[3:] = cb[3:]
            rep["curv_points"] = int(k.sum())
    else:                                             # no face to read a curvature from: about flat (Gray: plane facets)
        c[3:] *= 0.25
    chk = J.get("check"); fixed = []
    if chk:                                           # Gray's words for the form win over the build's face
        Hm = np.array([[2 * c[3], c[4]], [c[4], 2 * c[5]]]); k, V = np.linalg.eigh(Hm); k0 = k.copy()
        if chk == "convex":
            k = -np.abs(k)
        elif chk == "concave":
            k = np.abs(k)
        elif chk == "saddle":
            d = np.asarray(J["hollow"], float); d = np.array([d @ E[0], d @ E[1]]); d /= np.linalg.norm(d) + 1e-9
            m = max(np.abs(k).mean(), 1.0 / 25.0); V = np.array([d, [-d[1], d[0]]]).T; k = np.array([m, -m])
        if not np.allclose(k, k0):
            Hm = V @ np.diag(k) @ V.T; c[3], c[4], c[5] = Hm[0, 0] / 2, Hm[0, 1], Hm[1, 1] / 2
            fixed = ["curvature set to Gray's form (%s): radii %s -> %s" % (chk, np.round(1 / k0, 1).tolist(), np.round(1 / k, 1).tolist())]
    # place and tilt from the drawn lines (and the patch's middle surface, a third of the weight)
    if len(TP):
        qt = TP - o; ut, vt_, wt = qt @ E[0], qt @ E[1], qt @ E[2]
        near = np.abs(wt - (c[0] + c[1] * ut + c[2] * vt_ + c[3] * ut ** 2 + c[4] * ut * vt_ + c[5] * vt_ ** 2)) < 10.0
        ut, vt_, wt = ut[near], vt_[near], wt[near]
    else:
        ut = vt_ = wt = np.zeros(0)
    curv = lambda uu, vv: c[3] * uu ** 2 + c[4] * uu * vv + c[5] * vv ** 2
    A = np.concatenate([np.stack([np.ones_like(ut), ut, vt_], 1), np.stack([np.ones_like(u), u, v], 1)])
    y = np.concatenate([wt - curv(ut, vt_), w - curv(u, v)])
    wgt = np.concatenate([np.full(len(ut), 1.0 / max(len(ut), 1)), np.full(len(u), (0.5 if len(ut) else 1.0) / len(u))])
    c[:3] = np.linalg.lstsq(A * np.sqrt(wgt)[:, None], y * np.sqrt(wgt), rcond=None)[0]
    surf = Quad(o, E, c)
    k, dirs = surf.curvatures()
    rep.update(n=len(P), normal=np.round(E[2], 2).tolist(), radii=[round(float(1.0 / x), 1) if abs(x) > 1e-4 else None for x in k],
               trace_rms=round(float(np.sqrt(np.mean(surf(TP) ** 2))), 2) if len(TP) else None,
               patch_rms=round(float(np.sqrt(np.mean(surf(P) ** 2))), 2))
    if chk:
        rep["gray"] = chk + (": " + fixed[0] if fixed else ": as built")
    return dict(surf=surf, patch=P, traces=T, report=rep)


# --------------------------------------------------------------------------------------- 3. the whole solid and the cut
def _ss(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t)


def _on_surface(surf, P, iters=3):
    """Points carried on to a joint surface along its slope."""
    P = np.asarray(P, float).copy()
    for _ in range(iters):
        g = surf(P); gr = np.stack([surf(P + k) - surf(P - k) for k in np.eye(3) * 0.25], 1) / 0.5
        P -= (g / np.maximum((gr ** 2).sum(1), 1e-6))[:, None] * gr
    return P


def _sub(lo, h, n, a, b, pad):
    """The grid's window over the box a..b (mm) widened by pad."""
    return tuple(slice(max(0, int(np.floor((a[k] - pad - lo[k]) / h))), min(int(n[k]), int(np.ceil((b[k] + pad - lo[k]) / h)) + 1))
                 for k in range(3))


def frame_of(surf):
    """A joint surface's own frame: origin and rows e1, e2, n (n from a toward b)."""
    if isinstance(surf, Quad):
        return surf.o, surf.E
    f = surf.ax[:, 2] if surf.ax[2, 2] > 0 else -surf.ax[:, 2]
    return surf.c + f * surf.r[2], np.array([surf.ax[:, 0], surf.ax[:, 1], f])


def patch_map(J, Dp, a, b, lo, h, reach=8.0, near=None, step=0.5, half=32.0):
    """Where the joint is, as a map over its plane: along each line across the surface (along n), is there bone a
    within `reach` mm behind the surface and bone b within `reach` in front? Kept: the piece of that map that holds
    `near` (points (u, v)) or else the largest. Returns dict(o, E, ax, mask, r (mm outside the patch), w (the surface's
    height along each line))."""
    surf = J["surf"]; o, E = frame_of(surf)
    ax = np.arange(-half, half + 1e-6, step); Uu, Vv = np.meshgrid(ax, ax, indexing="ij")
    ws = np.arange(-30.0, 30.0 + 1e-6, 0.5)
    base = o + Uu[..., None] * E[0] + Vv[..., None] * E[1]
    g = np.stack([surf(base + w * E[2]) for w in ws], -1)                      # (nu, nv, nw)
    cross = (g[..., :-1] < 0) & (g[..., 1:] >= 0)
    has = cross.any(-1); k = np.argmax(cross, -1)
    g0 = np.take_along_axis(g, k[..., None], -1)[..., 0]; g1 = np.take_along_axis(g, (k + 1)[..., None], -1)[..., 0]
    wsurf = ws[k] + 0.5 * g0 / np.minimum(g0 - g1, -1e-6)
    Ga, Gb = Grid(Dp[a], lo, h), Grid(Dp[b], lo, h)
    S = base + wsurf[..., None] * E[2]
    ta = np.arange(0.0, reach + 1e-6, 0.5)
    da = np.min(np.stack([sample(Ga, S - t * E[2]) for t in ta]), 0); db = np.min(np.stack([sample(Gb, S + t * E[2]) for t in ta]), 0)
    m = has & (da < 0) & (db < 0)
    m = ndi.binary_opening(ndi.binary_closing(m, iterations=2), iterations=1)
    lab, nl = ndi.label(m)
    if nl > 1:
        if near is not None and len(near):
            iu = np.clip(np.round((near[:, 0] + half) / step).astype(int), 0, len(ax) - 1)
            iv = np.clip(np.round((near[:, 1] + half) / step).astype(int), 0, len(ax) - 1)
            d = ndi.distance_transform_edt(lab == 0, return_indices=True)[1]
            hits = lab[d[0][iu, iv], d[1][iu, iv]]; keep = np.unique(hits[hits > 0])
        else:
            keep = [1 + int(np.argmax(ndi.sum(m, lab, range(1, nl + 1))))]
        m = np.isin(lab, keep)
    r = ndi.distance_transform_edt(~m) * step - ndi.distance_transform_edt(m) * step
    return dict(o=o, E=E, ax=ax, step=step, half=half, mask=m, r=r.astype(np.float32), w=wsurf, reach=reach,
                area=float(m.sum() * step * step))


def patch_points(PM):
    m = PM["mask"]; iu, iv = np.nonzero(m); E = PM["E"]
    return PM["o"] + PM["ax"][iu][:, None] * E[0] + PM["ax"][iv][:, None] * E[1] + PM["w"][iu, iv][:, None] * E[2]


def patch_r(PM, X, g, cap=40.0):
    """mm from a joint's patch along its surface (0 on it) at points X, whose distance from the surface is g: the
    distance to the patch's points with the part across the surface taken out."""
    from scipy.spatial import cKDTree
    if "tree" not in PM:
        P = patch_points(PM); PM["tree"] = cKDTree(P[:: max(1, len(P) // 6000)])
    d, _ = PM["tree"].query(X.reshape(-1, 3), distance_upper_bound=cap, workers=4)
    d = np.where(np.isinf(d), cap, d).reshape(X.shape[:-1])
    return np.sqrt(np.maximum(d * d - g * g, 0.0)).astype(np.float32)


def bridge(Wd, Dp, J, PM, a, b, lo, h, soft=0.8):
    """Make the solid whole across a joint: over its patch, each bone is carried on along the joint's normal up to the
    surface (as far as `reach`), so the two meet there whatever space the posed bones left. Wd changed in place."""
    m = PM["mask"]
    if not m.any():
        return
    iu, iv = np.nonzero(m); E = PM["E"]; o = PM["o"]
    U2 = PM["ax"][iu]; V2 = PM["ax"][iv]; Wz = PM["w"][iu, iv]
    P = o + U2[:, None] * E[0] + V2[:, None] * E[1] + Wz[:, None] * E[2]
    sl = _sub(lo, h, Wd.shape, P.min(0), P.max(0), PM["reach"] + 3.0)
    X = np.stack(grid_points(lo, Wd.shape, h, sl), -1)
    g = J["surf"](X); r = patch_r(PM, X, g) - 0.5
    Ga, Gb = Grid(Dp[a][sl], lo + h * np.array([x.start for x in sl]), h), Grid(Dp[b][sl], lo + h * np.array([x.start for x in sl]), h)
    ts = np.arange(0.0, PM["reach"] + 1e-6, 0.5 * h)
    fa = np.min(np.stack([sample(Ga, X - t * E[2]) for t in ts]), 0)
    fb = np.min(np.stack([sample(Gb, X + t * E[2]) for t in ts]), 0)
    ba = sdf.smax(sdf.smax(fa, g, soft), r, soft); bb = sdf.smax(sdf.smax(fb, -g, soft), r, soft)
    Wd[sl] = np.minimum(Wd[sl], np.minimum(ba, bb).astype(np.float32))


def cut_field(Js, PMs, Dp, cut, lo, h, n, fall=3.0, deep=14.0):
    """One cut's surface over the grid: away from the joints, the middle surface between the two sets of posed bones;
    over each joint's patch (and `fall` mm beyond), that joint's surface, within `deep` mm of it. Unit slope."""
    A = np.min(np.stack([Dp[b] for b in cut[1]]), 0); B = np.min(np.stack([Dp[b] for b in cut[2]]), 0)
    g = 0.5 * (A - B); del A, B
    num = np.zeros(g.shape, np.float32); den = np.zeros(g.shape, np.float32)
    for j in cut[3]:
        P = patch_points(PMs[j])
        if not len(P):
            continue
        sl = _sub(lo, h, n, P.min(0), P.max(0), deep + fall + 2.0)
        X = np.stack(grid_points(lo, n, h, sl), -1)
        gj = Js[j]["surf"](X); r = patch_r(PMs[j], X, gj)
        w = (_ss((fall - r) / fall) * _ss((deep - np.abs(gj)) / 4.0)).astype(np.float32)
        num[sl] += w * gj; den[sl] += w
    w0 = np.clip(1.0 - den, 0.0, 1.0)
    g = (num + w0 * g) / (den + w0 + 1e-6)
    gr = np.gradient(g, h); mag = np.sqrt(sum(x * x for x in gr)); del gr
    return (g / np.clip(mag, 0.5, 2.0)).astype(np.float32)


def path(bone):
    """The cuts that bound a bone, with the side it lies on: [(cut index, +1 for the A side, -1 for B)]."""
    out = []
    for i, c in enumerate(CUTS):
        if bone in c[1]:
            out.append((i, 1.0))
        elif bone in c[2]:
            out.append((i, -1.0))
    return out


def cut_bone(Wd, gcuts, bone, gap=GAP, edge=EDGE):
    """A bone: the whole solid on its side of every surface it borders, half the joint space back from it, rounded into
    the joint's edge."""
    D = Wd.copy()
    for i, s in path(bone):
        D = sdf.smax(D, s * gcuts[i] + 0.5 * gap, edge)
    lab, nl = ndi.label(D < 0)                    # one piece: crumbs the cut leaves of a neighbour's overlap are dropped
    if nl > 1:
        keep = 1 + int(np.argmax(ndi.sum(D < 0, lab, range(1, nl + 1))))
        D[(lab != keep) & (D < 0)] = 0.5 * GAP
    return D.astype(np.float32)


def whole(h=H, cache=None, log=print, push=True, tune=True):
    """The tarsus as one solid and its joint surfaces: dict(W=whole field, lo, h, posed={bone: field}, joints={name:
    fit}, cuts=[surface fields], report)."""
    t0 = time.time()
    own = own_fields(cache, log)
    lo = np.asarray(BOX[0], float); n = np.ceil((np.asarray(BOX[1]) - lo) / h).astype(int) + 1
    Dp = {b: posed(own[b], *pose(b), lo, n, h) for b in BONES}
    U = np.min(np.stack([Dp[b] for b in BONES]), 0)
    log("  the seven bones set and sampled: %.0f s" % (time.time() - t0))
    G = Grid(U, lo, h); Js = {}
    for j in JOINTS:
        Js[j] = fit_joint(j, Dp, lo, h, G, own, log)
    log("  joint surfaces fitted: %.0f s" % (time.time() - t0))
    PMs = {}
    for j in JOINTS:
        a, b = JOINTS[j]["a"], JOINTS[j]["b"]; J = Js[j]
        o, E = frame_of(J["surf"]); TP = np.vstack([p[k] for p, k in J["traces"].values()]) if J["traces"] else np.zeros((0, 3))
        near = np.stack([(TP - o) @ E[0], (TP - o) @ E[1]], 1) if len(TP) else None
        PMs[j] = patch_map(J, Dp, a, b, lo, h, reach=JOINTS[j].get("reach", 8.0), near=near)
    Wd = U.copy()
    for j in JOINTS:
        bridge(Wd, Dp, Js[j], PMs[j], JOINTS[j]["a"], JOINTS[j]["b"], lo, h)
    log("  bridged across the joints: %.0f s" % (time.time() - t0))
    out = dict(W=Wd, lo=lo, h=h, n=n, posed=Dp, joints=Js, patches=PMs, own=own,
               report=dict(patch_mm2={j: round(PMs[j]["area"]) for j in JOINTS}))
    if push:
        outline_push(out, log=log)
        log("  outlines drawn on to the plates: %.0f s" % (time.time() - t0))
    out["cuts"] = [cut_field(Js, PMs, Dp, c, lo, h, n) for c in CUTS]
    if tune:
        tune_joints(out, log=log)
        for j in JOINTS:                     # the solid made whole again up to the moved surfaces
            a, b = JOINTS[j]["a"], JOINTS[j]["b"]
            PMs[j] = patch_map(Js[j], Dp, a, b, lo, h, reach=JOINTS[j].get("reach", 8.0), near=None if not PMs[j]["mask"].any() else
                               np.stack([(patch_points(PMs[j]) - frame_of(Js[j]["surf"])[0]) @ frame_of(Js[j]["surf"])[1][k] for k in (0, 1)], 1))
            bridge(Wd, Dp, Js[j], PMs[j], a, b, lo, h)
        out["cuts"] = [cut_field(Js, PMs, Dp, c, lo, h, n) for c in CUTS]
        log("  joints tuned to the drawn lines: %.0f s" % (time.time() - t0))
    log("  cut surfaces: %.0f s" % (time.time() - t0))
    return out


def bones(h=H, cache=None, log=print, built=None):
    """Each bone of the tarsus, cut from the whole, in the foot frame: ({bone: Grid}, the assembled set as one Grid (the
    least of the seven), the whole build)."""
    B = built or whole(h, cache, log)
    out = {b: Grid(cut_bone(B["W"], B["cuts"], b), B["lo"], B["h"]) for b in BONES}
    asm = Grid(np.min(np.stack([g.D for g in out.values()]), 0), B["lo"], B["h"])
    return out, asm, B


PUSH_ROUNDS = 5       # each round: Fig. 268, 269, 290, 291 in turn
PUSH_MAX = 5.0        # mm a round may move the surface
PUSH_FIGS = ("Gray268", "Gray269", "Gray290", "Gray291")


def _sdist(m, s):
    return ((ndi.distance_transform_edt(~m) - ndi.distance_transform_edt(m)) * s).astype(np.float32)


def outline_push(B, log=print, rounds=None, figs=PUSH_FIGS, band=7.0):
    """Draw the whole solid's outline on to the assembly plates: in each plate, where the solid's silhouette lies off the
    plate's (over the plate's tarsal part), the surface that makes that stretch of silhouette (seen edge on: its normal
    across the line of sight, its pixel near the silhouette) is moved in or out by the distance between the two
    outlines. The plates are taken in turn, so where they disagree the solid ends between them."""
    Wd = B["W"]; lo, h = B["lo"], B["h"]; rep = {}
    PL = {f: plate_mask(f) for f in figs}
    for rnd in range(rounds or PUSH_ROUNDS):
        for f in figs:
            G = Grid(Wd, lo, h); plate, care = PL[f]; Bv, s, u0, v0 = view(f)
            dep, _ = cast(G, f, size=(plate.shape[1], plate.shape[0]), sub=1)
            k = int(np.ceil(1.0 / s)); m = ndi.binary_fill_holes(ndi.binary_closing(np.pad(~np.isnan(dep), k), iterations=k))[k:-k, k:-k]
            sm = _sdist(m, s); sp = _sdist(plate, s)
            # where the plate's outline is not the tarsus's (beyond the tarsometatarsal line), nothing is asked
            delta = np.clip(sp - sm, -PUSH_MAX, PUSH_MAX) * ndi.gaussian_filter(care.astype(np.float32), 4.0)
            delta = ndi.gaussian_filter(delta, 1.0 / s)
            idx = np.argwhere(np.abs(Wd) < band); P = lo + h * idx
            nrm = _grad_at(Wd, lo, h, P); ce = np.abs(nrm @ Bv[2])
            u = u0 + (P @ Bv[0]) / s; v = v0 - (P @ Bv[1]) / s
            smp = ndi.map_coordinates(sm, [v, u], order=1, mode="nearest"); dl = ndi.map_coordinates(delta, [v, u], order=1, mode="nearest")
            wt = (1.0 - ce ** 2) ** 2 * np.exp(-(smp / 2.5) ** 2)
            dW = np.zeros(Wd.shape, np.float32); dW[tuple(idx.T)] = (dl * wt).astype(np.float32)
            dW = ndi.gaussian_filter(dW, 0.8 / h)
            Wd += dW
            if rnd == 0 or rnd == (rounds or PUSH_ROUNDS) - 1:
                rep["%s round %d" % (f, rnd + 1)] = round(outline_gap(f, m, plate, care)[0], 2)
    B["report"]["outline_push"] = rep
    log("  outline push: " + ", ".join("%s %.2f" % kv for kv in rep.items()))


# ------------------------------------------------------------------------------------------------------- 4. pictures
COLOURS = {"calcaneus": (226, 205, 160), "talus": (170, 200, 230), "navicular": (235, 170, 150), "cuboid": (170, 220, 170),
           "first": (225, 190, 230), "second": (240, 225, 140), "third": (160, 215, 215)}
EYES = {"above": ((1, 0, 0), (0, 0, 1), (0, 1, 0)), "below": ((-1, 0, 0), (0, 0, 1), (0, -1, 0)),
        "medial": ((0, 0, 1), (0, 1, 0), (1, 0, 0)), "lateral": ((0, 0, -1), (0, 1, 0), (-1, 0, 0)),
        "behind": ((-1, 0, 0), (0, 1, 0), (0, 0, -1)), "front": ((1, 0, 0), (0, 1, 0), (0, 0, 1))}
LIGHTS = {"upper left": (-0.45, 0.55, 0.70), "low right": (0.65, -0.25, 0.72)}


def render(parts, eye, light=LIGHTS["upper left"], s=0.2, size=None, centre=None, plain=False):
    """parts: {name: Grid} drawn together from `eye` (a name of EYES, a plate's name, or a (right, up, eye) basis),
    each in its colour (or bone-white with plain), shaded under `light` (picture basis): an RGB array and the label of
    what each pixel shows (-1 none)."""
    import platematch as pm
    names = list(parts); G0 = parts[names[0]]
    A = Grid(np.min(np.stack([parts[k].D for k in names]), 0), G0.lo, G0.h)
    if isinstance(eye, str) and eye.startswith("Gray"):
        B, s, u0, v0 = view(eye); g = plate_gray(eye); size = (g.shape[1], g.shape[0])
    else:
        B = np.asarray(EYES[eye] if isinstance(eye, str) else eye, float)
        idx = np.argwhere(A.D < 0); P = A.lo + A.h * idx[:: max(1, len(idx) // 20000)]
        c = P.mean(0) if centre is None else np.asarray(centre, float)
        uu, vv = (P - c) @ B[0], (P - c) @ B[1]
        if size is None:
            size = (int(2 * np.abs(uu).max() / s) + 40, int(2 * np.abs(vv).max() / s) + 40)
        u0 = size[0] / 2 - (c @ B[0]) / s; v0 = size[1] / 2 + (c @ B[1]) / s
    depth, N = pm.cast(A, B, s, u0, v0, size)
    hit = ~np.isnan(depth); lab = np.full(depth.shape, -1, int)
    V, Uu = np.nonzero(hit); P = (Uu - u0)[:, None] * s * B[0] + (v0 - V)[:, None] * s * B[1] + depth[hit][:, None] * B[2]
    lab[hit] = np.argmin(np.stack([sample(parts[k], P) for k in names]), 0)
    L = np.asarray(light, float); L /= np.linalg.norm(L)
    sh = pm.shade(depth, N, s, light=L).astype(np.float32) / 255.0
    col = np.array([COLOURS.get(k, (220, 220, 220)) if not plain else (232, 222, 200) for k in names], np.float32)
    img = np.full(depth.shape + (3,), 255.0, np.float32)
    img[hit] = col[lab[hit]] * (0.25 + 0.85 * sh[hit][:, None])
    return np.clip(img, 0, 255).astype(np.uint8), lab


def meet_line(lab, a, b, width):
    """Where two bones are seen to meet: the middle of the space between them (as far from one as from the other),
    where they lie within `width` pixels of each other."""
    da = ndi.distance_transform_edt(lab != a); db = ndi.distance_transform_edt(lab != b)
    return (np.abs(da - db) <= 1.0) & (da <= width) & (db <= width)


def label_edges(lab, a, b, width=2):
    """Pixels of label a beside label b (within `width`): where a joint between them is seen."""
    return (lab == a) & ndi.binary_dilation(lab == b, iterations=width)


def section(parts, axis, at, lo2, hi2, px=0.1, whole=None):
    """A flat section of the bones: axis 0 (x = at: sagittal, z to the right, y up), 2 (z = at: coronal, seen from in
    front, medial to the right... x to the right, y up). Each bone in its colour, the joint spaces and the open spaces
    white; `whole` (a Grid) outlined in grey. An RGB array."""
    names = list(parts)
    a1 = np.arange(lo2[0], hi2[0], px); a2 = np.arange(lo2[1], hi2[1], px)
    A1, A2 = np.meshgrid(a1, a2[::-1])
    if axis == 0:
        P = np.stack([np.full_like(A1, at), A2, A1], -1)
    else:
        P = np.stack([A1, A2, np.full_like(A1, at)], -1)
    D = np.stack([sample(parts[k], P) for k in names]); k = D.argmin(0); inside = D.min(0) < 0
    img = np.full(A1.shape + (3,), 255, np.uint8)
    col = np.array([COLOURS[n] for n in names], np.uint8); img[inside] = col[k[inside]]
    edge = inside & ~ndi.binary_erosion(inside); img[edge] = (60, 60, 60)
    if whole is not None:
        w = sample(whole, P) < 0; e = w & ~ndi.binary_erosion(w); img[e & ~inside] = (150, 150, 150)
    return img


def drawn_lines(fig):
    """The joint lines drawn in a plate, as {(a, b): pixels} (tarsal pairs only)."""
    J = ff.JOINTS268 if fig == "Gray268" else ff.JOINTS_SIDE.get(fig, {})
    if fig == "Gray269":
        J = JOINTS269
    return {k: np.asarray(v, float) for k, v in J.items() if k[0] in BONES and k[1] in BONES and len(v) > 1}


def joint_line_gaps(fig, lab, names, s):
    """For each joint line drawn in a plate: the mean distance (mm) from its points to where the two built bones are
    seen to meet (pixels of one beside the other, across the joint space)."""
    out = {}; wdt = max(2, int(np.ceil(1.8 / s)))
    for key, L in drawn_lines(fig).items():
        a, b = key[:2]; ia, ib = names.index(a), names.index(b)
        e = meet_line(lab, ia, ib, wdt)
        if not e.any():
            out[key] = None; continue
        dt = ndi.distance_transform_edt(~e) * s
        P = _resample(L, 1.0)
        out[key] = float(np.mean(ndi.map_coordinates(dt, [P[:, 1], P[:, 0]], order=1, mode="nearest")))
    return out


def _move(surf, a, b=0.0, c=0.0):
    """A joint surface moved a mm along its normal (and tilted by b, c mm a mm along e1, e2)."""
    if isinstance(surf, Quad):
        cc = surf.c.copy(); cc[0] += a; cc[1] += b; cc[2] += c; return Quad(surf.o, surf.E, cc)
    o, E = frame_of(surf); return Head(surf.shift + a * E[2], surf.grow)


TUNE_CAP = 3.0      # mm: the most a joint surface is moved from its fit to bring its outer trace on to the drawn lines


def tune_joints(B, rounds=2, damp=0.8, log=print):
    """Bring each joint's outer trace on to the lines the plates draw for it: the bones are cut and drawn in each plate,
    the built meeting line is compared with the drawn one point by point, and the surface is moved along its normal
    (and tilted) by what that asks, at most TUNE_CAP mm in all. What is left is reported (plates that disagree with the
    bones' own shapes or with each other)."""
    Js = B["joints"]; lo, h, n = B["lo"], B["h"], B["n"]; moved = {j: np.zeros(3) for j in JOINTS}
    Gw = Grid(B["W"], lo, h)
    for rnd in range(rounds):
        parts = {b: Grid(cut_bone(B["W"], B["cuts"], b), lo, h) for b in BONES}; names = list(parts)
        asks = {j: [] for j in JOINTS}
        for fig in ("Gray268", "Gray269", "Gray290", "Gray291"):
            img, lab = render(parts, fig); Bv, s, u0, v0 = view(fig); wdt = max(2, int(np.ceil(1.8 / s)))
            for key, L in drawn_lines(fig).items():
                a, b = key[:2]; j = [k for k, J in JOINTS.items() if {J["a"], J["b"]} == {a, b}]
                if not j:
                    continue
                j = ("TCp" if len(key) > 2 and key[2] == "posterior" else "TCm") if {a, b} == {"talus", "calcaneus"} else j[0]
                e = meet_line(lab, names.index(a), names.index(b), wdt)
                if not e.any():
                    continue
                dist, ind = ndi.distance_transform_edt(~e, return_indices=True)
                P = _resample(L, 1.0); iu = np.clip(np.round(P[:, 0]).astype(int), 0, lab.shape[1] - 1); iv = np.clip(np.round(P[:, 1]).astype(int), 0, lab.shape[0] - 1)
                ok = dist[iv, iu] * s < 8.0
                if ok.sum() < 3:
                    continue
                du = (ind[1][iv, iu] - iu)[ok] * s; dv = (ind[0][iv, iu] - iv)[ok] * s
                Dm = du[:, None] * Bv[0] - dv[:, None] * Bv[1]                     # built line minus drawn, in the frame
                X, found = lift(fig, P[ok], Gw)
                o, E = frame_of(Js[j]["surf"]); nn = E[2]; npj = nn - (nn @ Bv[2]) * Bv[2]; k2 = float(npj @ npj)
                if k2 < 0.15:
                    continue
                delta = -(Dm @ npj) / k2                                           # move the surface by this along n
                q = X - o
                asks[j].append(np.stack([q @ E[0], q @ E[1], delta], 1)[found[: len(X)]])
        rep = {}
        for j, L in asks.items():
            if not L:
                continue
            A = np.vstack(L); uu, vv, dd = A.T
            if np.ptp(uu) > 8 or np.ptp(vv) > 8:
                M = np.stack([np.ones_like(uu), uu - uu.mean(), vv - vv.mean()], 1)
                _, b_, c_ = np.linalg.lstsq(M, dd, rcond=None)[0]; b_, c_ = np.clip([b_, c_], -0.15, 0.15)
                a_ = float(np.mean(dd - b_ * uu - c_ * vv))
            else:
                a_, b_, c_ = float(np.mean(dd)), 0.0, 0.0
            step = damp * np.array([a_, b_, c_]); tot = moved[j] + step
            tot[0] = np.clip(tot[0], -TUNE_CAP, TUNE_CAP); step = tot - moved[j]; moved[j] = tot
            Js[j]["surf"] = _move(Js[j]["surf"], *step)
            rep[j] = round(float(np.mean(dd)), 2)
        log("  joints tuned (round %d, mean asked mm): %s" % (rnd + 1, rep))
        B["cuts"] = [cut_field(Js, B["patches"], B["posed"], c, lo, h, n) for c in CUTS]
    B["report"]["joint_moves"] = {j: np.round(m, 2).tolist() for j, m in moved.items()}


# ------------------------------------------------------------------------------------------------ 5. checks (A2, A3)
def own_views(bone):
    """A bone's own plates: [(view, traced outline mask, pose the single-bone build was read at)]."""
    import platematch as pm
    if bone == "calcaneus":
        import foot; V, tr = pm.CALCANEUS, foot.traces("calcaneus")
    elif bone == "talus":
        import talus, foot; V, tr = talus.TALUS, foot.traces("talus")
    elif bone in ("cuboid", "navicular"):
        import midfoot; V, tr = midfoot.PLATES[bone], midfoot.traces(bone)
    else:
        import cuneiforms; V, tr = cuneiforms.VIEWS[bone], cuneiforms.traces(bone)
    return [(v, tr[v["fig"] + "_sdf"] < 0, np.asarray(tr[v["fig"] + "_pose"], float)) for v in V]


def to_own(G, bone, like):
    """A bone (a Grid in the foot frame) carried back into its own frame, on the grid of `like` (its own build)."""
    R, t = pose(bone); out = np.empty(tuple(like.n), np.float32)
    ys, zs = like.ax[1], like.ax[2]; Yg, Zg = np.meshgrid(ys, zs, indexing="ij")
    for i in range(like.n[0]):
        P = np.stack([np.full_like(Yg, like.ax[0][i]), Yg, Zg], -1); out[i] = sample(G, P @ R.T + t)
    return Grid(out, like.lo, like.h)


def own_plate_gaps(F, bone, shift=6):
    """A bone (own frame) drawn in each of its own plates at the pose its build was read at, then moved in the plate's
    plane to lie best (whole pixels, up to `shift` mm): {fig: (mean outline distance mm, [three worst places: (u, v,
    mm, 'out' where the bone runs outside the plate / 'in' where it falls short)])}."""
    import platematch as pm
    out = {}
    for v, mask, p in own_views(bone):
        px = v["s"] * p[3]; H, Wd = mask.shape
        depth, _ = pm.cast(F, pm.basis(v, p[:3]), px, v["u0"] + p[4], v["v0"] + p[5], (Wd, H), normals=False)
        m = ~np.isnan(depth); k = int(shift / px); best = None
        for du in range(-k, k + 1, max(1, k // 8)):
            for dv in range(-k, k + 1, max(1, k // 8)):
                mm = np.roll(np.roll(m, du, 1), dv, 0); i = pm.iou(mm, mask)
                if best is None or i > best[0]:
                    best = (i, du, dv)
        m = np.roll(np.roll(m, best[1], 1), best[2], 0)
        em, ep = pm.edge(m), pm.edge(mask)
        dm = ndi.distance_transform_edt(~ep)[em] * px; dp = ndi.distance_transform_edt(~em)[ep] * px
        mean = float(np.concatenate([dm, dp]).mean())
        # the worst places: model edge pixels far from the plate's ('out' if outside the plate) and plate edge pixels
        # far from the model's ('in')
        P = np.concatenate([np.argwhere(em), np.argwhere(ep)]); d = np.concatenate([dm, dp])
        kind = np.concatenate([np.where(mask[em], "in", "out"), np.full(len(dp), "in")])
        worst = []; order = np.argsort(-d); taken = []
        for i in order:
            if len(worst) == 3 or d[i] < 0.5:
                break
            if any(np.hypot(*(P[i] - q)) * px < 6.0 for q in taken):
                continue
            taken.append(P[i]); worst.append((int(P[i][1]), int(P[i][0]), round(float(d[i]), 1), str(kind[i])))
        out[v["fig"]] = (round(mean, 2), worst)
    return out


def articular_gaps(parts, B):
    """A2: for each joint, the gap between its two cut bones over its patch (the place where the two posed bones face
    each other across the surface): the share of the patch where it lies within 0.8 to 2.0 mm, and its median."""
    out = {}
    for j, J in JOINTS.items():
        P = patch_points(B["patches"][j])
        if not len(P):
            out[j] = None; continue
        P = _on_surface(B["joints"][j]["surf"], P[:: max(1, len(P) // 3000)])
        g = sample(parts[J["a"]], P) + sample(parts[J["b"]], P)
        out[j] = dict(n=len(P), within=round(float(np.mean((g >= 0.8) & (g <= 2.0))), 3), median=round(float(np.median(g)), 2),
                      p5=round(float(np.percentile(g, 5)), 2), p95=round(float(np.percentile(g, 95)), 2))
    return out


def overlaps(parts):
    """A2: for every pair, the deepest point inside both (mm; 0 when they do not overlap)."""
    names = list(parts); out = {}
    for i in range(len(names)):
        for k in range(i + 1, len(names)):
            a, b = parts[names[i]].D, parts[names[k]].D; both = (a < 0) & (b < 0)
            out[(names[i], names[k])] = round(float(np.max(np.minimum(-a[both], -b[both]))), 3) if both.any() else 0.0
    return out
