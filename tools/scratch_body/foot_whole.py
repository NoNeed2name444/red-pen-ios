"""foot_whole.py: the right tarsus built whole, its seven bones warped together into one fitted set.

The owner, 25 Nov: "let's change the approach for complex bone collections. make the full foot bones then we separate
them." Attempt 1 (commit d1e9d46) built one solid, pushed its rim on to the assembly plates and cut it along shared joint
surfaces: the joints fitted but the bones' surfaces were spoilt (flat walls, terraces, waffled cut faces). The repair
(supervisor's rulings R-a to R-f, 25 Nov):
  - every free surface is the bone's own single build (foot.py, talus.py, midfoot.py, cuneiforms.py, from its own
    plates), moved only by a smooth warp: a pose, a stretch along its own axes (each within +/-12 %) and a
    low-frequency displacement (no feature shorter than about 10 mm, at most 2.5 mm). Gray's single-bone plates carry
    no common scale and come from different specimens: the assembly plates rule proportions and places, the own
    plates rule form;
  - the seven warps are solved together (solve_affine, fit_disp): the union on to the outlines of Fig. 268 (from above),
    269 (from below), 290 (medial) and 291 (lateral); the facing facets of each joint GAP apart over their true contact
    (the facets as the bones' own plates outline them); each warp small;
  - each joint is one shared surface only over that contact (share_joints): the two faces are put on the surface where
    the two bones are equally far, set back GAP / 2 each, the pull fading out JOINT_FADE mm beyond the facet's edge.
    Outside the contacts each bone keeps its own surface: no extrusion, no cut walls.
Plates: Gray, Anatomy of the Human Body, 20th ed., 1918, public domain. Frame: foot_frame.py's (right foot, x medial,
y up, z forward, mm; the origin the navicular's middle); foot_frame.TARGET gives the warps' starting poses only.
bones() returns each bone and the assembled set in the foot frame; the solved warps are kept in WARPS_FILE. Later bones
(metatarsals) join by adding to BONES, their facets to _facet_sources() and their plates' joint lines.
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
H = 0.5            # mm: the grid
BOX = ((-62.0, -74.0, -98.0), (34.0, 34.0, 44.0))   # the tarsus in the foot frame, with room round it

_ORTH = lambda R: (lambda u, s, vt: u @ vt)(*np.linalg.svd(np.asarray(R, float)))


# ---------------------------------------------------------------------------------------------------- 1. the bones
def pose(name):
    """(R, t): foot point = R @ own point + t, where the warps start: foot_frame.TARGET (each bone fitted to Fig.
    268/290/291), the navicular where it stands (it defines the frame)."""
    if name == "navicular":
        R, t = np.eye(3), np.zeros(3)
    else:
        R, t = ff.pose(name); R = _ORTH(R)
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



def _ss(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t)




def _resample(P, step):
    P = np.asarray(P, float); out = [P[0]]
    for a, b in zip(P[:-1], P[1:]):
        k = max(1, int(np.ceil(np.linalg.norm(b - a) / step))); out += [a + (b - a) * i / k for i in range(1, k + 1)]
    return np.array(out)



# -------------------------------------------------------------------------------- 2. the joints' true contact areas
# Each joint's facets as the bones' own plates outline them (the single-bone modules' tracings, in each plate's own
# pixels), lifted on to the bone's own surface where that plate sees it. A joint: (a, b, [(bone, plate, polygon) or
# (bone, "face", (direction, least cosine))]). Where only one bone's facet is traced (the navicular's for the talar
# head, the cuboid's for the calcaneus), the other side's contact is the surface facing it.
def _facet_sources():
    import foot, talus, midfoot, cuneiforms as cu
    calc = [[(87.0 + x / 0.225, 421.0 - z / 0.225) for x, z in p] for p in foot.CALC_FACETS]
    nav, cub, F = midfoot.NAV_FACETS["Gray276"], midfoot.CUB_FACETS, cu.FACETS
    return {
        "TN": ("talus", "navicular", [("navicular", "Gray277", midfoot.NAV_TALAR)]),
        "TCp": ("talus", "calcaneus", [("talus", "Gray271", talus.POST_FACET_271), ("calcaneus", "Gray264", calc[0])]),
        "TCm": ("talus", "calcaneus", [("talus", "Gray271", talus.MID_FACET_271), ("talus", "Gray271", talus.ANT_FACET_271),
                                       ("calcaneus", "Gray264", calc[1]), ("calcaneus", "Gray264", calc[2])]),
        "CC": ("calcaneus", "cuboid", [("cuboid", "Gray275", cub["Gray275"][0])]),
        "NC1": ("navicular", "first", [("navicular", "Gray276", nav[0]), ("first", "face", cu.FACES["first"][0])]),
        "NC2": ("navicular", "second", [("navicular", "Gray276", nav[1]), ("second", "Gray281", F["Gray281"][1][0])]),
        "NC3": ("navicular", "third", [("navicular", "Gray276", nav[2]), ("third", "Gray282", F["Gray282"][0][0])]),
        "NCu": ("navicular", "cuboid", [("navicular", "Gray276", nav[3]), ("cuboid", "Gray274", cub["Gray274"][1])]),
        "C3Cu": ("third", "cuboid", [("cuboid", "Gray274", cub["Gray274"][0]), ("third", "Gray283", F["Gray283"][2][0])]),
        "C12": ("first", "second", [("first", "Gray279", F["Gray279"][1][0]), ("second", "Gray280", F["Gray280"][0][0])]),
        "C23": ("second", "third", [("second", "Gray281", F["Gray281"][0][0]), ("third", "Gray282", F["Gray282"][1][0])]),
    }


def _grad(G, P):
    g = np.stack([sample(G, P + k) - sample(G, P - k) for k in np.eye(3) * G.h], 1)
    return g / (np.linalg.norm(g, axis=1)[:, None] + 1e-9)


def _thin(P, step):
    """One point a cell of `step` mm (the first met)."""
    k = np.floor(P / step).astype(np.int64); _, i = np.unique(k, axis=0, return_index=True); return np.sort(i)


def surface(G, step):
    """A bone's own surface as points about `step` mm apart, with outward normals."""
    idx = np.argwhere(np.abs(G.D) < 0.6 * G.h); P = G.lo + G.h * idx
    P = P[_thin(P, step)]; n = _grad(G, P); P = P - sample(G, P)[:, None] * n
    return P.astype(np.float64), n


def facet_points(own, P, n, bone, fig, poly):
    """The bone's surface points (own frame) inside a facet traced on one of its own plates, where that plate sees them;
    or, for ("face", (direction, cosine)), where the surface faces that way."""
    import platematch as pm
    from PIL import Image, ImageDraw
    if fig == "face":
        d, c = poly; d = np.asarray(d, float) / np.linalg.norm(d); return n @ d >= c
    v, mask, p = [t for t in own_views(bone) if t[0]["fig"] == fig][0]
    B = pm.basis(v, p[:3]); px = v["s"] * p[3]; u0, v0 = v["u0"] + p[4], v["v0"] + p[5]; H, Wd = mask.shape
    depth, _ = pm.cast(own[bone], B, px, u0, v0, (Wd, H), normals=False)
    u = u0 + (P @ B[0]) / px; w = v0 - (P @ B[1]) / px; e = P @ B[2]
    ui = np.clip(np.round(u).astype(int), 0, Wd - 1); wi = np.clip(np.round(w).astype(int), 0, H - 1)
    seen = np.nan_to_num(depth[wi, ui], nan=-1e9) - e < 1.0
    im = Image.new("L", (Wd, H), 0); ImageDraw.Draw(im).polygon([tuple(map(float, q)) for q in poly], fill=1)
    inside = np.asarray(im)[wi, ui] > 0
    return seen & inside & (n @ B[2] > 0.0)


def prep(own, step=1.5, fstep=1.0, log=print):
    """Each bone's surface (thinned to `step` mm for the outlines and overlaps) and its facets (to `fstep`), own frame."""
    data = {}
    for b in BONES:
        P, n = surface(own[b], fstep); keep = _thin(P, step)
        from scipy.spatial import cKDTree
        data[b] = dict(P=P, n=n, coarse=keep, c=P.mean(0), facets={}, tree=cKDTree(P))
    for j, (a, b, src) in _facet_sources().items():
        for bone, fig, poly in src:
            d = data[bone]; m = facet_points(own, d["P"], d["n"], bone, fig, poly)
            d["facets"][j] = np.union1d(d["facets"].get(j, np.zeros(0, int)), np.nonzero(m)[0]).astype(int)
    log("  facets: " + ", ".join("%s %s %d" % (j, b, len(i)) for b in BONES for j, i in data[b]["facets"].items()))
    return data


# ------------------------------------------------------------------------------------------- 3. the warps, together
# Each bone's own build is carried into the foot by a smooth warp: foot point = Q R0 (c + e^sig (x - c) - c) + C0 + dlt
# + disp(...): its pose (R0, t0 from foot_frame.TARGET, then turned by Q about its middle C0 and shifted dlt), a stretch
# e^sig along its own three axes (each within +/-12 %: Gray's single-bone plates carry no common scale), and a
# low-frequency displacement (DISP_STEP-mm lattice, DISP_SIGMA-mm Gaussians, normalised; no feature shorter than
# about 10 mm, nowhere more than DISP_MAX mm). The seven are solved together (solve_affine, then fit_disp): the union
# on to the four assembly plates' outlines, the facing facets of each joint GAP apart, each warp small.
STRETCH = 0.12
DISP_STEP, DISP_SIGMA, DISP_MAX = 12.0, 7.0, 2.5
WARPS_FILE = os.path.join(HERE, "traces", "foot_whole_warps.json")


def _rot(w):
    from scipy.spatial.transform import Rotation
    return Rotation.from_rotvec(np.asarray(w, float)).as_matrix()


def warp0(data):
    out = {}
    for b in BONES:
        R0, t0 = pose(b); c = data[b]["c"]
        out[b] = dict(R0=R0, t0=t0, c=c, C0=R0 @ c + t0, w=np.zeros(3), dlt=np.zeros(3), sig=np.zeros(3), nodes=None, coef=None)
    return out


def _disp(Wb, Y):
    if Wb.get("nodes") is None:
        return np.zeros_like(Y)
    out = np.empty_like(Y); N = np.asarray(Wb["nodes"]); Cf = np.asarray(Wb["coef"])
    for i in range(0, len(Y), 50000):
        d2 = ((Y[i:i + 50000, None, :] - N[None]) ** 2).sum(-1); f = np.exp(-d2 / (2 * DISP_SIGMA ** 2)) + 1e-12
        out[i:i + 50000] = (f @ Cf) / f.sum(1)[:, None]
    return out


def fwd(Wb, x, disp=True):
    Q = _rot(Wb["w"]); xs = (x - Wb["c"]) * np.exp(Wb["sig"])
    Y = xs @ (Q @ Wb["R0"]).T + Wb["C0"] + Wb["dlt"]
    return Y + _disp(Wb, Y) if disp else Y


def inv(Wb, X, disp=True):
    if disp and Wb.get("nodes") is not None:
        Y = X - _disp(Wb, X); Y = X - _disp(Wb, Y); Y = X - _disp(Wb, Y)
    else:
        Y = X
    Q = _rot(Wb["w"]); xs = (Y - Wb["C0"] - Wb["dlt"]) @ (Q @ Wb["R0"])
    return Wb["c"] + xs / np.exp(Wb["sig"])


def dist(own, Wb, b, X, far=None):
    """Bone b's (warped) signed distance at foot points X, mm (the own field's, scaled by the stretch's mean); beyond
    the own field's reach (it is clipped at 12 mm), with `far` (b's own surface points), the distance to the nearest
    of them."""
    xo = inv(Wb, X); g = sample(own[b], xo, cval=30.0).astype(float)
    if far is not None:
        o = np.abs(g) >= 9.0
        if o.any():
            g[o] = far.query(xo[o])[0]
    return g * float(np.exp(np.mean(Wb["sig"])))


def normals_fwd(Wb, n):
    m = (n / np.exp(Wb["sig"])) @ (_rot(Wb["w"]) @ Wb["R0"]).T
    return m / np.linalg.norm(m, axis=1)[:, None]


class Plates:
    """The four assembly plates' outlines for the solve: each plate's signed distance (mm, + outside the foot) over its
    tarsal part, and points along its outline there (1 mm apart)."""
    def __init__(self, figs=("Gray268", "Gray269", "Gray290", "Gray291")):
        self.f = {}
        for fig in figs:
            m, care = plate_mask(fig); s = view(fig)[1]
            sd = (ndi.distance_transform_edt(~m) - ndi.distance_transform_edt(m)) * s
            cut = ndi.binary_dilation(_edge(care), iterations=3)
            e = np.argwhere(_edge(m & care) & ~cut)[:, ::-1].astype(float)
            e = e[_thin(np.c_[e, np.zeros(len(e))] * s, 1.0)]
            self.f[fig] = dict(sd=sd, care=care, E=e, s=s, B=view(fig))


def residuals(own, data, W, plates, wj=1.0, wo=1.0, wr=3.0, sil=None, jn=60.0):
    """The solve's residuals (mm-like): outline (model outside the plate; plate outline far from the model), joints
    (facet to the other bone minus GAP), overlaps (any point nearer than 0.8 mm to another bone), the warp's size."""
    from scipy.spatial import cKDTree
    r = []; X = {b: fwd(W[b], data[b]["P"][data[b]["coarse"]], disp=True) for b in BONES}
    for fig, p in plates.f.items():
        B, s, u0, v0 = p["B"]; pts = []
        for b in BONES:
            Xb = X[b] if sil is None else X[b][sil[fig][b]]
            pts.append(np.stack([u0 + Xb @ B[0] / s, v0 - Xb @ B[1] / s], 1))
        U = np.concatenate(pts); H, Wd = p["sd"].shape
        Uc = np.clip(U, 0, [Wd - 1, H - 1]); ok = p["care"][Uc[:, 1].astype(int), Uc[:, 0].astype(int)]
        sd = ndi.map_coordinates(p["sd"], [U[:, 1], U[:, 0]], order=1, mode="nearest")
        out = np.maximum(sd, 0.0) * ok; r.append(out / np.sqrt(len(out)) * np.sqrt(len(p["E"])))
        d, _ = cKDTree(U[ok]).query(p["E"]); r.append(np.maximum(d * s - 0.8, 0.0))
        # the union's own outline (points drawn, closed over the joint spaces): where it lies inside the plate's
        m = np.zeros((H, Wd), bool); ui = Uc.astype(int); m[ui[:, 1], ui[:, 0]] = True
        k = int(np.ceil(1.2 / s)); m = ndi.binary_fill_holes(ndi.binary_closing(np.pad(m, k), iterations=k))[k:-k, k:-k]
        rim = ndi.binary_dilation(_edge(m), iterations=1)[ui[:, 1], ui[:, 0]] & ok
        r.append(np.maximum(-sd, 0.0) * rim / np.sqrt(len(sd)) * np.sqrt(len(p["E"])))
    for j, (a, b, _) in _facet_sources().items():
        for x, y in ((a, b), (b, a)):
            i = data[x]["facets"].get(j)
            if i is None or not len(i):
                continue
            Px = fwd(W[x], data[x]["P"][i]); g = dist(own, W[y], y, Px, far=data[y]["tree"])
            r.append(wj * np.clip(g - GAP, -4.0, 4.0) * np.sqrt(jn / len(i)))
    for ia in range(len(BONES)):
        for ib in range(ia + 1, len(BONES)):
            a, b = BONES[ia], BONES[ib]; g = dist(own, W[b], b, X[a])
            r.append(wo * np.maximum(0.8 - g, 0.0) * (g < 25))
    for b in BONES:
        r.append(wr * np.r_[W[b]["sig"] / 0.06, np.degrees(W[b]["w"]) / 3.0, W[b]["dlt"] / 4.0])
    return np.concatenate(r)


def _pack(W):
    return np.concatenate([np.r_[W[b]["w"], W[b]["dlt"], W[b]["sig"]] for b in BONES])


def _unpack(W, v):
    for k, b in enumerate(BONES):
        q = v[9 * k: 9 * k + 9]; W[b]["w"], W[b]["dlt"], W[b]["sig"] = q[:3].copy(), q[3:6].copy(), q[6:].copy()
    return W


def _silhouette_sets(data, W, plates, cos=0.45):
    """Per plate, each bone's points that can stand on its outline (their surface seen nearly edge on)."""
    out = {}
    for fig, p in plates.f.items():
        e = p["B"][0][2]; out[fig] = {}
        for b in BONES:
            nn = normals_fwd(W[b], data[b]["n"][data[b]["coarse"]]); out[fig][b] = np.abs(nn @ e) < cos
    return out


def solve_affine(own, data, W, plates, log=print, rounds=3, nfev=25):
    from scipy.optimize import least_squares
    lo = np.concatenate([np.r_[[-0.35] * 3, [-15.0] * 3, [np.log(1 - STRETCH)] * 3] for _ in BONES])
    hi = np.concatenate([np.r_[[0.35] * 3, [15.0] * 3, [np.log(1 + STRETCH)] * 3] for _ in BONES])
    for k in range(rounds):
        sil = _silhouette_sets(data, W, plates)
        f = lambda v: residuals(own, data, _unpack(W, v), plates, sil=sil)
        v0 = np.clip(_pack(W), lo + 1e-9, hi - 1e-9)
        res = least_squares(f, v0, bounds=(lo, hi), loss="soft_l1", f_scale=1.0, max_nfev=nfev, diff_step=1e-3, x_scale="jac")
        _unpack(W, res.x); log("  warp solve round %d: cost %.1f (%d evaluations)" % (k + 1, res.cost, res.nfev))
    return W


def contact_sets(own, data, W, reach=4.0):
    """Each joint's contact on both bones (foot frame): the traced facets, and on a bone without a tracing for it, its
    surface points facing the other's facet within `reach` mm."""
    from scipy.spatial import cKDTree
    out = {}
    for j, (a, b, _) in _facet_sources().items():
        S = {}
        for x in (a, b):
            i = data[x]["facets"].get(j)
            S[x] = None if i is None or not len(i) else i
        for x, y in ((a, b), (b, a)):
            if S[x] is None and S[y] is not None:
                Py = fwd(W[y], data[y]["P"][S[y]]); Px = fwd(W[x], data[x]["P"])
                d, _ = cKDTree(Py).query(Px); nx = normals_fwd(W[x], data[x]["n"])
                g = dist(own, W[y], y, Px, far=data[y]["tree"])
                S[x] = np.nonzero((d < reach) & (g < reach))[0]
        out[j] = S
    return out


def fit_disp(own, data, W, contact, log=print, lam=0.3):
    """The low-frequency displacement: each bone's facet points moved half the way to GAP from the other bone, points
    inside another bone moved out, the rest held; a ridge fit of the lattice's vectors, each capped at DISP_MAX."""
    rep = {}
    for b in BONES:
        d = data[b]; X = fwd(W[b], d["P"][d["coarse"]], disp=False); want = np.zeros_like(X); wt = np.full(len(X), lam)
        Xf = fwd(W[b], d["P"], disp=False); nf = normals_fwd(W[b], d["n"]); ci = d["coarse"]
        lut = -np.ones(len(d["P"]), int); lut[ci] = np.arange(len(ci))
        for j, (a, c, _) in _facet_sources().items():
            if b not in (a, c):
                continue
            o = c if b == a else a; i = contact[j][b]
            if i is None or not len(i):
                continue
            g = dist(own, W[o], o, Xf[i], far=data[o]["tree"]); dv = 0.5 * (g - GAP)[:, None] * nf[i]
            X = np.vstack([X, Xf[i]]); want = np.vstack([want, dv]); wt = np.r_[wt, np.ones(len(i))]
        for o in BONES:
            if o == b:
                continue
            g = dist(own, W[o], o, Xf[ci]); m = g < 0.8
            if m.any():
                gr = np.stack([dist(own, W[o], o, Xf[ci][m] + k) - dist(own, W[o], o, Xf[ci][m] - k) for k in np.eye(3) * 0.5], 1)
                gr /= np.linalg.norm(gr, axis=1)[:, None] + 1e-9
                X = np.vstack([X, Xf[ci][m]]); want = np.vstack([want, (0.8 - g[m])[:, None] * gr]); wt = np.r_[wt, np.ones(m.sum())]
        lo, hi = Xf.min(0) - 6.0, Xf.max(0) + 6.0
        ax = [np.arange(lo[k], hi[k] + DISP_STEP, DISP_STEP) for k in range(3)]
        N = np.stack(np.meshgrid(*ax, indexing="ij"), -1).reshape(-1, 3)
        f = np.exp(-((X[:, None, :] - N[None]) ** 2).sum(-1) / (2 * DISP_SIGMA ** 2)) + 1e-12; f /= f.sum(1)[:, None]
        A = f * wt[:, None]; M = A.T @ f + 1e-2 * np.eye(len(N))
        Cf = np.linalg.solve(M, A.T @ want)
        nr = np.linalg.norm(Cf, axis=1); Cf *= np.minimum(1.0, DISP_MAX / np.maximum(nr, 1e-9))[:, None]
        W[b]["nodes"], W[b]["coef"] = N, Cf
        dd = np.linalg.norm(_disp(W[b], Xf), axis=1); rep[b] = (round(float(np.median(dd)), 2), round(float(dd.max()), 2))
    log("  displacement (median, max mm): " + ", ".join("%s %s" % kv for kv in rep.items()))
    return rep


def save_warps(W, path=WARPS_FILE):
    import json
    keep = {b: {k: (np.asarray(v).tolist() if v is not None else None) for k, v in W[b].items()} for b in BONES}
    json.dump(keep, open(path, "w"))


def load_warps(path=WARPS_FILE):
    import json
    d = json.load(open(path)); return {b: {k: (np.asarray(v, float) if v is not None else None) for k, v in d[b].items()} for b in BONES}


# ------------------------------------------------------------------------- 4. the bones on one grid, joints shared
def place(own, W, h=H, pad=4.0):
    """Each warped bone on the foot grid (BOX, h): its own field read through the inverse warp over its own box (the
    displacement read off a 2 mm lattice), 30 elsewhere."""
    lo = np.asarray(BOX[0], float); n = (np.ceil((np.asarray(BOX[1]) - lo) / h)).astype(int) + 1; out = {}
    for b in BONES:
        G = own[b]; C = np.array(list(np.ndindex(2, 2, 2)), float) * (G.n - 1) * G.h + G.lo
        Y = fwd(W[b], C, disp=False); a = np.maximum(((Y.min(0) - pad - lo) / h).astype(int), 0)
        z = np.minimum(((Y.max(0) + pad - lo) / h).astype(int) + 1, n)
        D = np.full(tuple(n), 30.0, np.float32)
        ax = [lo[k] + h * np.arange(a[k], z[k]) for k in range(3)]
        if W[b].get("nodes") is not None:       # the displacement on a coarse lattice, read between its points
            cl = [np.arange(ax[k][0] - 2, ax[k][-1] + 4, 2.0) for k in range(3)]
            L = np.stack(np.meshgrid(*cl, indexing="ij"), -1); dl = _disp(W[b], L.reshape(-1, 3)).reshape(L.shape)
        g = float(np.exp(np.mean(W[b]["sig"]))); Yg, Zg = np.meshgrid(ax[1], ax[2], indexing="ij")
        for ii, x in enumerate(ax[0]):
            X = np.stack([np.full_like(Yg, x), Yg, Zg], -1).reshape(-1, 3)
            if W[b].get("nodes") is not None:
                Yx = X.copy()
                for _ in range(3):
                    q = [(Yx[:, k] - cl[k][0]) / 2.0 for k in range(3)]
                    dd = np.stack([ndi.map_coordinates(dl[..., k], q, order=1, mode="nearest") for k in range(3)], 1)
                    Yx = X - dd
                xo = inv(W[b], Yx, disp=False)
            else:
                xo = inv(W[b], X, disp=False)
            D[a[0] + ii, a[1]:z[1], a[2]:z[2]] = (sample(G, xo) * g).reshape(Yg.shape)
        out[b] = Grid(D, lo, h)
    return out


JOINT_FADE = 4.0    # mm outside a facet's edge over which the shared surface's pull fades to nothing


def share_joints(parts, own, data, W, contact, log=print):
    """Inside each joint's contact the two faces are put on ONE surface (where the two bones are as far from one as
    from the other) set back GAP / 2 on each side; the pull fades to nothing JOINT_FADE mm outside the facet's edge, so
    there is no flat face and no step. Returns what each joint's faces were moved (median, max mm)."""
    from scipy.spatial import cKDTree
    rep = {}
    for j, (a, b, _) in _facet_sources().items():
        K = []; moved = []
        for x, y in ((a, b), (b, a)):
            i = contact[j][x]
            if i is None or not len(i):
                continue
            Px = fwd(W[x], data[x]["P"][i]); K.append(Px)
            moved.append(np.abs(0.5 * (sample(parts[y], Px) - GAP)))
        if not K:
            continue
        T = cKDTree(np.vstack(K)); A, B = parts[a].D, parts[b].D
        zone = (np.minimum(A, B) < 6.0) & (np.maximum(A, B) < 10.0)
        idx = np.argwhere(zone); P = parts[a].lo + parts[a].h * idx
        d, _ = T.query(P, distance_upper_bound=JOINT_FADE + 8.0); d = np.minimum(d, 99.0)
        w = 1.0 - _ss((d - 1.0) / JOINT_FADE)
        da, db = A[zone], B[zone]; mid = 0.5 * (da - db)
        A[zone] = ((1 - w) * da + w * (mid + 0.5 * GAP)).astype(np.float32)
        B[zone] = ((1 - w) * db + w * (-mid + 0.5 * GAP)).astype(np.float32)
        m = np.concatenate(moved); rep[j] = (round(float(np.median(m)), 2), round(float(m.max()), 2), round(float(np.percentile(m, 95)), 2))
    log("  joint faces moved to the shared surface (median, max, p95 mm): " + ", ".join("%s %s" % kv for kv in rep.items()))
    return rep


def keep_one(G):
    """The largest piece of a bone (and its count of pieces before)."""
    lab, k = ndi.label(G.D < 0)
    if k > 1:
        big = 1 + int(np.argmax(ndi.sum(np.ones_like(lab), lab, range(1, k + 1))))
        G.D[(lab > 0) & (lab != big)] = 0.6
    return k


def bones(h=H, cache=None, log=print, solve=False):
    """The seven bones in the foot frame: ({bone: Grid}, the assembled set (a Grid: the union), report). With solve, the
    warps are solved afresh (and kept in WARPS_FILE); otherwise read from it."""
    t = time.time(); own = own_fields(cache, log=log); data = prep(own, log=log); rep = {}
    if solve or not os.path.exists(WARPS_FILE):
        W = warp0(data); plates = Plates()
        solve_affine(own, data, W, plates, log=log); log("  warps solved: %.0f s" % (time.time() - t))
        contact = contact_sets(own, data, W); rep["disp"] = fit_disp(own, data, W, contact, log=log)
        save_warps(W)
    else:
        W = load_warps()
    contact = contact_sets(own, data, W)
    parts = place(own, W, h); log("  bones placed: %.0f s" % (time.time() - t))
    rep["moved"] = share_joints(parts, own, data, W, contact, log=log)
    rep["pieces"] = {b: keep_one(parts[b]) for b in BONES}
    rep["warps"] = {b: dict(stretch_pct=np.round(100 * (np.exp(W[b]["sig"]) - 1), 1).tolist(),
                            turn_deg=round(float(np.degrees(np.linalg.norm(W[b]["w"]))), 1), shift_mm=np.round(W[b]["dlt"], 1).tolist())
                    for b in BONES}
    A = Grid(np.min(np.stack([parts[b].D for b in BONES]), 0), parts[BONES[0]].lo, h)
    rep.update(W=W, data=data, contact=contact, own=own)
    log("  built: %.0f s" % (time.time() - t))
    return parts, A, rep


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


# Fig. 290, re-read at five times (25 Nov): foot_frame's talus-calcaneus line ((122, 93) to (158, 106)) follows the
# under edge of the sustentaculum tali, the groove for the flexor hallucis longus below it, not a joint. The medial
# talocalcaneal (middle facet) joint is the line above the sustentaculum, where the talus's dark underside meets the
# sustentaculum's pale upper border.
TC290 = {("talus", "calcaneus", "middle"): [(106, 86), (118, 84), (130, 83), (140, 86), (150, 93)]}


def drawn_lines(fig):
    """The joint lines drawn in a plate, as {(a, b): pixels} (tarsal pairs only)."""
    J = ff.JOINTS268 if fig == "Gray268" else ff.JOINTS_SIDE.get(fig, {})
    if fig == "Gray269":
        J = JOINTS269
    if fig == "Gray290":        # R-d: the line first read as the talocalcaneal joint runs under the sustentaculum
        J = {k: v for k, v in J.items() if k != ("talus", "calcaneus")}; J.update(TC290)
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


def to_own(G, Wb, like):
    """A bone (a Grid in the foot frame) carried back into its own frame through its warp's pose and stretch only (its
    affine part; what the displacement and the shared joints changed stays), on the grid of `like` (its own build)."""
    out = np.empty(tuple(like.n), np.float32); g = float(np.exp(np.mean(Wb["sig"])))
    Yg, Zg = np.meshgrid(like.ax[1], like.ax[2], indexing="ij")
    for i in range(like.n[0]):
        P = np.stack([np.full_like(Yg, like.ax[0][i]), Yg, Zg], -1).reshape(-1, 3)
        out[i] = (sample(G, fwd(Wb, P, disp=False)) / g).reshape(Yg.shape)
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


def overlaps(parts):
    """A2: for every pair, the deepest point inside both (mm; 0 when they do not overlap)."""
    names = list(parts); out = {}
    for i in range(len(names)):
        for k in range(i + 1, len(names)):
            a, b = parts[names[i]].D, parts[names[k]].D; both = (a < 0) & (b < 0)
            out[(names[i], names[k])] = round(float(np.max(np.minimum(-a[both], -b[both]))), 3) if both.any() else 0.0
    return out
