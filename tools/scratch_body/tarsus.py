"""tarsus.py: the right tarsus built as ONE solid from Gray's four whole-foot plates, then cut into its seven bones.

The owner, 25 Nov: "let's change the approach for complex bone collections. make the full foot bones then we separate
them." Two earlier attempts (foot_whole.py, commits d1e9d46 and 7ef1ac3) started from the seven single-bone builds and
failed: Gray's single-bone plates are different specimens at no common scale, so their joint faces disagree. Here the
assembly plates are the model and the single-bone plates only decorate it:

M1 territories: on Fig. 268 (dorsal), 269 (plantar), 290 (medial) and 291 (lateral), rendered at 400 dpi from the 1918
   scan, each bone's own visible region is the plate's whole-foot silhouette (ink, filled) cut by the drawn joint lines
   and the borders where one bone is seen over another (traces/tarsus_lines.json). All four are put in foot_frame's
   frame: the plans (268, 269) project along y, the side views (290, 291) along x.
M2 one solid: a body over the plan, between a top height T(x, z) and a bottom height B(x, z), each a smooth surface
   through heights read off the side plates where the plan places them (the plan line of a joint or border x its side
   line gives one 3D curve), and the crest of the side silhouettes; where one bone stands on another (the talus on the
   calcaneus, the sustentaculum over the calcaneus's body) the surface is cut along that border and runs down as a
   rounded wall; the rim along the plan's outline is a rounded superellipse wall. The sinus tarsi and tarsal canal are
   a tunnel along the talocalcaneal joint, shaped from Fig. 268 and 291.
M3 joints: each joint is one smooth surface: a graph over the plane it lies across, interpolated (thin-plate) through
   the 3D curves where its drawn lines in the plates meet the solid's surface, then bent to the kind Gray gives it.
   Bones are what the solid holds on each side of the joints, each set back half the joint space, edges rounded.
M4 relief (later): each bone's own plates, as local relief on its free surfaces.

Frame: foot_frame.py's (right foot, x medial, y up, z forward, mm; origin the navicular's middle).
bones(h) -> ({name: Grid}, assembled Grid, report). The metatarsals join later as more territories and joints.
Plates: Gray, Anatomy of the Human Body, 20th ed., 1918, public domain (Fig. 268 and 269 on PDF pages 263 and 264,
Fig. 290 and 291 on pages 275 and 276 of the scan in gray1918_pdf).
"""
import json
import os
import time
import numpy as np
from scipy import ndimage as ndi
import foot_frame as ff

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
BONES = ("calcaneus", "talus", "navicular", "cuboid", "first", "second", "third")
FIGS = ("Gray268", "Gray269", "Gray290", "Gray291")
LINES_FILE = os.path.join(HERE, "traces", "tarsus_lines.json")
OUTLINE_FILE = os.path.join(HERE, "traces", "tarsus_outlines.npz")

# ------------------------------------------------------------------------------------------------ M1. the plates
# The 400 dpi renders (the scan's 1-bit line art, pdfimages) cropped at BOX (page pixels), and each registered on the
# Wikimedia copy the frame was fitted on: hi pixel = s Rot(rot) wiki pixel + t (ORB features, RANSAC, then the
# correlation of the two pictures maximised: 0.85 to 0.87).
REG_HI = {"Gray268": dict(page=263, box=(300, 200, 2120, 3500), s=2.67876, rot=-0.5519, t=(6.405, 91.882)),
          "Gray269": dict(page=264, box=(180, 180, 2000, 3560), s=2.67113, rot=-0.3346, t=(35.627, 80.814)),
          "Gray290": dict(page=275, box=(120, 1900, 2200, 2800), s=3.75008, rot=0.0790, t=(95.737, 102.467)),
          "Gray291": dict(page=276, box=(100, 950, 2240, 1720), s=3.80182, rot=0.0327, t=(54.683, 59.66))}
FIG269 = dict(th=1.7405, s=0.19820, u0=210.993, v0=463.580)     # foot_whole.py: Fig. 269 laid on Fig. 268 (attempt A)
PLAN = ("Gray268", "Gray269")
SIDE = ("Gray290", "Gray291")


def plate_dir():
    return os.path.join(OUT, "tarsW", "pg")


def render_plates(pdf=None):
    """Render the four plates from the 1918 scan (pdfimages: the line-art mask) into plate_dir() as <fig>_hi.png."""
    import subprocess, glob
    from PIL import Image
    pdf = pdf or os.path.join(OUT, "gray1918_pdf", "Anatomy_of_the_human_body_1918.pdf")
    d = plate_dir(); os.makedirs(d, exist_ok=True)
    for fig, r in REG_HI.items():
        p = r["page"]; pre = os.path.join(d, "m%d" % p)
        subprocess.run(["pdfimages", "-f", str(p), "-l", str(p), "-png", pdf, pre], check=True)
        m = sorted(glob.glob(pre + "-*.png"))
        m = [f for f in m if Image.open(f).mode == "1"][0]
        a = np.asarray(Image.open(m))
        im = Image.fromarray(((~a) * 255).astype(np.uint8)).resize((2250, 3678), Image.BILINEAR)
        im.crop(r["box"]).save(os.path.join(d, fig + "_hi.png"))


def _M(fig):
    r = REG_HI[fig]; c, s = np.cos(np.radians(r["rot"])), np.sin(np.radians(r["rot"]))
    return np.array([[r["s"] * c, -r["s"] * s, r["t"][0]], [r["s"] * s, r["s"] * c, r["t"][1]], [0, 0, 1.0]])


def wiki_to_hi(fig, P):
    M = _M(fig); P = np.asarray(P, float); return P @ M[:2, :2].T + M[:2, 2]


def hi_to_wiki(fig, Q):
    M = np.linalg.inv(_M(fig)); Q = np.asarray(Q, float); return Q @ M[:2, :2].T + M[:2, 2]


def view(fig):
    """A plate's picture basis in the frame: (right, up, toward the eye) rows, mm a (wiki) pixel, origin pixel."""
    if fig == "Gray268":
        return np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]]), 0.208, 377.0, 440.0
    if fig == "Gray269":
        c, s = np.cos(np.radians(FIG269["th"])), np.sin(np.radians(FIG269["th"]))
        return np.array([[-c, 0, -s], [s, 0, -c], [0, -1.0, 0]]), FIG269["s"], FIG269["u0"], FIG269["v0"]
    p = ff.PLATES[fig]; R = np.asarray(p["R"], float)
    return np.array([R[0], R[1], -R[2]]), p["s"], p["u0"], p["v0"]


def to_pixels(fig, P):
    """Frame points (..., 3) to wiki pixels (..., 2)."""
    B, s, u0, v0 = view(fig); P = np.asarray(P, float)
    return np.stack([u0 + (P @ B[0]) / s, v0 - (P @ B[1]) / s], -1)


def plane_axes(fig):
    """The frame plane a plate projects on: (0, 2) = (x, z) for the plans, (1, 2) = (y, z) for the side views."""
    return (0, 2) if fig in PLAN else (1, 2)


def to_plane(fig, uv):
    """Wiki pixels to the plate's frame plane (mm): (x, z) for a plan, (y, z) for a side view."""
    B, s, u0, v0 = view(fig); uv = np.asarray(uv, float)
    a = (uv[..., 0] - u0) * s; b = (v0 - uv[..., 1]) * s
    P = a[..., None] * B[0] + b[..., None] * B[1]
    i, j = plane_axes(fig); return np.stack([P[..., i], P[..., j]], -1)


def from_plane(fig, q):
    """The plate's frame plane (mm) to wiki pixels."""
    q = np.asarray(q, float); P = np.zeros(q.shape[:-1] + (3,)); i, j = plane_axes(fig)
    P[..., i] = q[..., 0]; P[..., j] = q[..., 1]
    return to_pixels(fig, P)


def lines():
    return json.load(open(LINES_FILE))


# Where a plate's tarsus ends: foot_whole.CARE (pixels; the tarsometatarsal joints and off the fifth metatarsal's
# tuberosity); Fig. 269's is Fig. 268's carried over through the two plans' registration.
def care(fig):
    import foot_whole as W
    return np.asarray(W._care269() if fig == "Gray269" else W.CARE[fig], float)


def trace_outlines():
    """The whole-foot silhouette's tarsal part in each plate, from the hi-res render (ink closed over 4 px, holes
    filled, leader lines opened away over 9 px, the largest piece), as a closed polygon in the plate's frame plane
    (mm): written to OUTLINE_FILE. Needs the rendered plates (render_plates)."""
    from PIL import Image, ImageDraw
    from skimage import measure, morphology as mo
    out = {}
    for fig in FIGS:
        g = np.asarray(Image.open(os.path.join(plate_dir(), fig + "_hi.png")).convert("L"))
        m = ndi.binary_fill_holes(ndi.binary_closing(np.pad(g < 128, 30), mo.disk(4)))
        m = ndi.binary_opening(m, mo.disk(9))
        lab, n = ndi.label(m); m = ndi.binary_fill_holes(lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1))))))[30:-30, 30:-30]
        im = Image.new("L", (m.shape[1], m.shape[0]), 0)
        ImageDraw.Draw(im).polygon([tuple(p) for p in wiki_to_hi(fig, care(fig))], fill=255)
        m = m & (np.asarray(im) > 0)
        lab, n = ndi.label(m); m = lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1)))))
        c = max(measure.find_contours(np.pad(m, 1).astype(float), 0.5), key=len)[:, ::-1] - 1.0
        q = to_plane(fig, hi_to_wiki(fig, c))
        out[fig] = q[::2].astype(np.float32)
        out[fig + "_full"] = to_plane(fig, hi_to_wiki(fig, _whole_contour(fig))).astype(np.float32)
    np.savez_compressed(OUTLINE_FILE, **out)
    return out


def _whole_contour(fig):
    """The whole-foot silhouette (all of it, the metatarsals and toes too) as a hi-res contour: for drawing only."""
    from PIL import Image
    from skimage import measure, morphology as mo
    g = np.asarray(Image.open(os.path.join(plate_dir(), fig + "_hi.png")).convert("L"))
    m = ndi.binary_fill_holes(ndi.binary_closing(np.pad(g < 128, 30), mo.disk(4)))
    m = ndi.binary_opening(m, mo.disk(9))
    lab, n = ndi.label(m); m = ndi.binary_fill_holes(lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1))))))[30:-30, 30:-30]
    return max(measure.find_contours(np.pad(m, 1).astype(float), 0.5), key=len)[:, ::-1][::3] - 1.0


def outlines():
    return dict(np.load(OUTLINE_FILE))


class Plane:
    """A raster on a plate's frame plane: a[0] along the plane's first axis (x or y), a[1] along z."""
    def __init__(self, lo, hi, h):
        self.lo = np.asarray(lo, float); self.h = float(h)
        self.n = np.ceil((np.asarray(hi, float) - self.lo) / h).astype(int) + 1
        self.ax = [self.lo[k] + h * np.arange(self.n[k]) for k in range(2)]

    def idx(self, q):
        return (np.asarray(q, float) - self.lo) / self.h

    def grid(self):
        return np.meshgrid(self.ax[0], self.ax[1], indexing="ij")

    def at(self, A, q, order=1, cval=0.0):
        i = self.idx(q).reshape(-1, 2).T
        return ndi.map_coordinates(A, i, order=order, mode="constant", cval=cval).reshape(np.asarray(q).shape[:-1])


PLAN_PLANE = ((-64.0, -100.0), (40.0, 46.0))      # (x, z)
SIDE_PLANE = ((-78.0, -100.0), (36.0, 46.0))      # (y, z)


def plane_of(fig, h=0.1):
    lo, hi = PLAN_PLANE if fig in PLAN else SIDE_PLANE
    return Plane(lo, hi, h)


def _poly_mask(P, poly, closed=True, width=0):
    """A polygon (plane mm) filled (or a polyline drawn `width` cells wide) on the Plane's raster (bool, shape n)."""
    from PIL import Image, ImageDraw
    q = P.idx(poly); im = Image.new("L", (int(P.n[0]), int(P.n[1])), 0); d = ImageDraw.Draw(im)
    pts = [tuple(p) for p in q]
    if closed:
        d.polygon(pts, fill=255)
    else:
        d.line(pts, fill=255, width=max(1, int(width)))
    return (np.asarray(im) > 0).T


def territories(fig, h=0.1, lines_=None, keep_sinus=False):
    """M1: each bone's own visible region in a plate, on its frame plane: (label raster: index into BONES, -1 off the
    tarsus, len(BONES) the sinus tarsi's mouth in Fig. 291; the Plane). The tarsal silhouette is cut along every line of
    kind joint or edge; each piece takes the bone of the seed inside it; the cut lines go to the nearer piece."""
    L = lines_ or lines(); P = plane_of(fig, h)
    sil = _poly_mask(P, outlines()[fig])
    w = max(2, int(round(0.25 / h)))
    own = [_poly_mask(P, to_plane(fig, np.asarray(pts, float)), closed=False, width=w)
           for a, b, kind, pts in L[fig] if kind != "inner"]
    qs = [to_plane(fig, np.asarray(pts, float)) for a, b, kind, pts in L[fig] if kind != "inner"]
    bar = np.any(own, 0)
    # an end within 1.5 mm of another line is joined to it
    for k, q in enumerate(qs):
        for end in (q[0], q[-1]):
            best = None
            for k2, q2 in enumerate(qs):
                if k2 == k:
                    continue
                dd = np.linalg.norm(q2 - end, axis=1); i = int(np.argmin(dd))
                if dd[i] < 1.5 and (best is None or dd[i] < best[0]):
                    best = (dd[i], q2[i])
            if best is not None and best[0] > 1e-6:
                bar |= _poly_mask(P, np.array([end, best[1]]), closed=False, width=w)
    # a line that stops short of the outline or of the line it meets is carried on straight, up to 14 mm, until it does
    for k, q in enumerate(qs):
        others = bar & ~ndi.binary_dilation(own[k], iterations=2 * w)
        for end, prev in ((q[0], q[min(2, len(q) - 1)]), (q[-1], q[max(-3, -len(q))])):
            d = end - prev; d = d / max(np.linalg.norm(d), 1e-9); ext = [end]
            for t in np.arange(h, 14.0, h):
                p = end + t * d; i, j = np.round(P.idx(p)).astype(int)
                if not (0 <= i < P.n[0] and 0 <= j < P.n[1]) or not sil[i, j] or others[i, j]:
                    ext.append(p); break
            else:
                continue
            bar |= _poly_mask(P, np.array(ext), closed=False, width=w)
    lab, n = ndi.label(sil & ~bar)
    names = list(BONES) + ["sinus"]
    out = np.full(sil.shape, -1, int)
    for bone, uv in L["seeds"][fig].items():
        i, j = np.round(P.idx(to_plane(fig, np.asarray(uv, float)))).astype(int)
        k = lab[i, j]
        if k == 0:
            raise ValueError("seed of %s in %s falls on a line or off the foot" % (bone, fig))
        out[lab == k] = names.index(bone)
    # pieces with no seed (crumbs cut off between lines) and the line pixels: the nearest labelled piece
    holes = sil & (out < 0)
    if holes.any():
        _, (ii, jj) = ndi.distance_transform_edt(out < 0, return_indices=True)
        out[holes] = out[ii[holes], jj[holes]]
    return out, P


# ------------------------------------------------------------------------------------------------ M2. one solid
EXT_MM = 9.0      # mm: the solid runs on this far past the tarsometatarsal lines (the metatarsals' bases), cut off later


def care_ext(fig):
    """The tarsal part of a plate carried this far forward too (so the tarsometatarsal joints are cut through the solid,
    not where the solid ends): the care polygon and its copy moved EXT_MM forward, joined, in the frame plane (mm)."""
    q = to_plane(fig, care(fig)); q2 = q.copy(); q2[:, 1] += EXT_MM
    return q, q2


def plane_mask(fig, P, ext=True):
    """A plate's whole-foot silhouette's tarsal part (with the extension) on a Plane: bool."""
    full = _poly_mask(P, outlines()[fig + "_full"])
    q, q2 = care_ext(fig)
    c = _poly_mask(P, q) | (_poly_mask(P, q2) if ext else False)
    return full & c


def _sdist(m, h):
    """Signed distance (mm, + inside) of a mask."""
    return (ndi.distance_transform_edt(m) - ndi.distance_transform_edt(~m)) * h


def consensus(figs, P, ext=True):
    """Two plates of one projection laid together: the mean of their signed distances (mm), + inside."""
    return np.mean([_sdist(plane_mask(f, P, ext), P.h) for f in figs], 0)


def _ss(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t)


def _resample(P, step):
    P = np.asarray(P, float); out = [P[0]]
    for a, b in zip(P[:-1], P[1:]):
        k = max(1, int(np.ceil(np.linalg.norm(b - a) / step))); out += [a + (b - a) * i / k for i in range(1, k + 1)]
    return np.array(out)


def _line(fig, a, b, kind=None):
    """A traced line of a plate (in its frame plane, mm, resampled at 0.5 mm), or None."""
    for la, lb, k, pts in lines()[fig]:
        if {la, lb} == {a, b} and (kind is None or k == kind):
            return _resample(to_plane(fig, np.asarray(pts, float)), 0.5)
    return None


def _lines(fig, pairs):
    out = [q for q in (_line(fig, a, b) for a, b in pairs) if q is not None]
    return np.concatenate(out) if out else None


def _fn_of_z(q, i=0):
    """A line (n, 2) in a frame plane as a function of z (its second coordinate): (zs, values of coordinate i)."""
    q = q[np.argsort(q[:, 1])]; return q[:, 1], q[:, i]


def thin_plate(P, inside, data, slits=(), slope=(), lam=40.0, alpha=0.02):
    """A smooth surface on the Plane P's nodes where `inside` (bool) holds: least bending (second differences squared)
    plus lam x the data's squared misfit. data: (n, 4) rows (a, z, value, weight) with a the plane's first coordinate;
    slope: (n, 4) rows (a, z, d value / d a, weight); slits: polylines (mm) no difference stencil may cross (the surface
    is free to jump across them). alpha: a little first-difference smoothing, so a node with no data near is held."""
    from scipy import sparse
    from scipy.sparse.linalg import spsolve
    n0, n1 = P.n; N = n0 * n1; idx = np.arange(N).reshape(n0, n1); h = P.h
    act = inside.copy()
    # edges crossing a slit: between (i, j) and (i+1, j) (along a), and (i, j) and (i, j+1) (along z)
    cutA = np.zeros((n0 - 1, n1), bool); cutZ = np.zeros((n0, n1 - 1), bool)
    A0, Z0 = P.grid()
    for sl in slits:
        sl = np.asarray(sl, float)
        for p, q in zip(sl[:-1], sl[1:]):
            lo = np.minimum(p, q) - h; hi = np.maximum(p, q) + h
            i0, j0 = np.floor((lo - P.lo) / h).astype(int); i1, j1 = np.ceil((hi - P.lo) / h).astype(int)
            i0, j0 = max(i0, 0), max(j0, 0); i1, j1 = min(i1, n0 - 1), min(j1, n1 - 1)
            for cut, di, dj in ((cutA, 1, 0), (cutZ, 0, 1)):
                ii, jj = np.meshgrid(np.arange(i0, min(i1, n0 - di)), np.arange(j0, min(j1, n1 - dj)), indexing="ij")
                a1 = np.stack([A0[ii, jj], Z0[ii, jj]], -1); a2 = np.stack([A0[ii + di, jj + dj], Z0[ii + di, jj + dj]], -1)
                cr = lambda o, a, b: (a[..., 0] - o[..., 0]) * (b[..., 1] - o[..., 1]) - (a[..., 1] - o[..., 1]) * (b[..., 0] - o[..., 0])
                pp = np.broadcast_to(p, a1.shape); qq = np.broadcast_to(q, a1.shape)
                x = (np.sign(cr(a1, a2, pp)) != np.sign(cr(a1, a2, qq))) & (np.sign(cr(pp, qq, a1)) != np.sign(cr(pp, qq, a2)))
                cut[ii, jj] |= x
    rows, cols, vals = [], [], []; r = 0
    okA = act[:-1, :] & act[1:, :] & ~cutA
    okZ = act[:, :-1] & act[:, 1:] & ~cutZ
    # second differences along a: (i-1, i, i+1)
    m = okA[:-1, :] & okA[1:, :]
    ii, jj = np.nonzero(m)
    for k, (di, w) in enumerate(((0, 1.0), (1, -2.0), (2, 1.0))):
        rows.append(r + np.arange(len(ii))); cols.append(idx[ii + di, jj]); vals.append(np.full(len(ii), w / h ** 2))
    r += len(ii)
    m = okZ[:, :-1] & okZ[:, 1:]
    ii, jj = np.nonzero(m)
    for dj, w in ((0, 1.0), (1, -2.0), (2, 1.0)):
        rows.append(r + np.arange(len(ii))); cols.append(idx[ii, jj + dj]); vals.append(np.full(len(ii), w / h ** 2))
    r += len(ii)
    m = okA[:, :-1] & okA[:, 1:] & okZ[:-1, :] & okZ[1:, :]
    ii, jj = np.nonzero(m)
    for di, dj, w in ((0, 0, 1.0), (1, 0, -1.0), (0, 1, -1.0), (1, 1, 1.0)):
        rows.append(r + np.arange(len(ii))); cols.append(idx[ii + di, jj + dj]); vals.append(np.full(len(ii), np.sqrt(2.0) * w / h ** 2))
    r += len(ii)
    for ok, di, dj in ((okA, 1, 0), (okZ, 0, 1)):
        ii, jj = np.nonzero(ok)
        for d, w in ((0, -1.0), (1, 1.0)):
            rows.append(r + np.arange(len(ii))); cols.append(idx[ii + d * di, jj + d * dj]); vals.append(np.full(len(ii), np.sqrt(alpha) * w / h))
        r += len(ii)
    def bil(a, z):
        t = (np.stack([a, z], -1) - P.lo) / h; i = np.clip(np.floor(t[:, 0]).astype(int), 0, n0 - 2); j = np.clip(np.floor(t[:, 1]).astype(int), 0, n1 - 2)
        fa = t[:, 0] - i; fz = t[:, 1] - j
        return [(idx[i, j], (1 - fa) * (1 - fz)), (idx[i + 1, j], fa * (1 - fz)), (idx[i, j + 1], (1 - fa) * fz), (idx[i + 1, j + 1], fa * fz)]
    rhs = [np.zeros(r)]
    if len(data):
        D = np.asarray(data, float); s = np.sqrt(lam * D[:, 3])
        for c, w in bil(D[:, 0], D[:, 1]):
            rows.append(r + np.arange(len(D))); cols.append(c); vals.append(w * s)
        rhs.append(D[:, 2] * s); r += len(D)
    if len(slope):
        D = np.asarray(slope, float); s = np.sqrt(lam * D[:, 3])
        for c, w in bil(D[:, 0] + 0.5 * h, D[:, 1]):
            rows.append(r + np.arange(len(D))); cols.append(c); vals.append(w * s / h)
        for c, w in bil(D[:, 0] - 0.5 * h, D[:, 1]):
            rows.append(r + np.arange(len(D))); cols.append(c); vals.append(-w * s / h)
        rhs.append(D[:, 2] * s); r += len(D)
    A = sparse.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(r, N))
    b = np.concatenate(rhs)
    used = np.zeros(N, bool); used[np.unique(A.indices)] = True
    A = A[:, used]
    x = spsolve((A.T @ A).tocsc() + 1e-9 * sparse.identity(int(used.sum())), A.T @ b)
    out = np.full(N, np.nan); out[used] = x
    return out.reshape(n0, n1), (cutA, cutZ)


_TERR = {}


def terr(fig, h=0.1):
    """territories(), kept for the session."""
    if (fig, h) not in _TERR:
        _TERR[(fig, h)] = territories(fig, h)
    return _TERR[(fig, h)]


def _owner_x(lab, P, bone, z, share, from_medial):
    """Where a bone's region in a plan plate lies across at z: the x `share` of the way in from its medial (or lateral)
    border. None if the bone is not there at z."""
    j = int(round((z - P.lo[1]) / P.h))
    if not 0 <= j < P.n[1]:
        return None
    col = lab[:, j] == BONES.index(bone) if bone in BONES else lab[:, j] >= 0
    if not col.any():
        return None
    xs = P.ax[0][col]; xm, xl = xs.max(), xs.min()
    return xm - share * (xm - xl) if from_medial else xl + share * (xm - xl)


def side_samples(fig, which, share, step=0.5):
    """The side plate's top (which='top') or bottom silhouette, column by column along z, each height placed across at
    the bone that holds it (its region in Fig. 268 for the top, Fig. 269 for the bottom, `share` in from the side the
    plate looks at): rows (x, z, y, owner index or -1)."""
    Ps = plane_of(fig, 0.1); m = plane_mask(fig, Ps); lab, _ = terr(fig)
    pf = "Gray268" if which == "top" else "Gray269"; labp, Pp = terr(pf)
    omega = plane_mask(pf, Pp)
    out = []
    for z in np.arange(Ps.ax[1][0], Ps.ax[1][-1], step):
        j = int(round((z - Ps.lo[1]) / Ps.h)); col = m[:, j]
        if not col.any():
            continue
        ys = Ps.ax[0][col]; y = ys.max() if which == "top" else ys.min()
        i = int(round((y - (0.4 if which == "top" else -0.4) - Ps.lo[0]) / Ps.h)); k = lab[i, j]
        owner = BONES[k] if 0 <= k < len(BONES) else None
        x = _owner_x(labp, Pp, owner, z, share, fig == "Gray290") if owner else None
        if x is None:          # the metatarsals' bases (past the tarsus) or a bone the plan does not show at that z
            continue
        out.append((x, z, y, k))
    return np.array(out)


def _pair(fig_plan, fig_side, pairs_plan, pairs_side=None, dx=0.0):
    """A 3D curve from a plan line (x of z) and a side line (y of z) of the same border: rows (x + dx, z, y)."""
    a = _lines(fig_plan, pairs_plan); b = _lines(fig_side, pairs_side or pairs_plan)
    if a is None or b is None:
        return np.zeros((0, 3))
    za, xa = _fn_of_z(a, 0); zb, yb = _fn_of_z(b, 0)
    z0, z1 = max(za.min(), zb.min()), min(za.max(), zb.max())
    if z1 <= z0:
        return np.zeros((0, 3))
    zs = np.arange(z0, z1, 0.5)
    return np.stack([np.interp(zs, za, xa) + dx, zs, np.interp(zs, zb, yb)], 1)


TOP_SHARE = 0.35       # the top silhouette's height placed this share in from the side each plate looks at
BOT_SHARE = 0.25
STEP_R = 3.8           # mm: the talus's lateral wall over the calcaneus seen from above (Fig. 268: the lateral malleolar facet, 3.5 mm)
RIM_P = 2.2            # the rim's superellipse power (2: an ellipse)
# helper heights (dorsum to plantar edge, mm) where no plate shows the plantar side: the second and third cuneiforms
# from their own plates as cuneiforms.HEIGHT reads them (22 and 25 mm); the navicular's body away from its tuberosity
# set by us at 17 mm (Gray gives no figure; its side outline in Fig. 290 stands 21 mm from its dorsum to the tuberosity's
# foot, which is lower than the body)
PLANTAR_DEPTH = {"second": 22.0, "third": 25.0, "navicular": 17.0}


def slit():
    """Where the talus stands on the calcaneus, seen from above (Fig. 268's borders behind and lateral to the talus,
    from its back medial corner round to its head's lateral end), carried 3 mm beyond each end: plane polyline (x, z)."""
    L = [to_plane("Gray268", np.asarray(pts, float)) for a, b, k, pts in lines()["Gray268"] if {a, b} == {"talus", "calcaneus"}]
    back = [q for q in L if np.ptp(q[:, 0]) > np.ptp(q[:, 1])][0]; lat = [q for q in L if np.ptp(q[:, 0]) <= np.ptp(q[:, 1])][0]
    back = back[np.argsort(-back[:, 0])]                    # medial to lateral
    s = np.concatenate([back, lat])
    s = _resample(s, 0.5)
    d0 = s[0] - s[3]; d1 = s[-1] - s[-4]
    return np.concatenate([[s[0] + 3.0 * d0 / np.linalg.norm(d0)], s, [s[-1] + 0.0 * d1]])


PLAN_EASE, LAM, RIM_SHARE, RIM_MAX = 1.0, 40.0, 0.3, 8.0


def heights(h=0.5, log=print):
    """M2: the top and bottom surfaces over the plan. Returns dict with the Plane, T and B (raw and with the rims),
    the plan's signed distance (mm, + inside), and the samples used."""
    t0 = time.time()
    P = Plane(PLAN_PLANE[0], PLAN_PLANE[1], h)
    Pf = plane_of("Gray268", 0.1)
    sd = consensus(PLAN, Pf)
    sd = ndi.gaussian_filter(sd, PLAN_EASE / Pf.h)                     # the two plates' outlines eased (ink ripple out)
    A, Z = P.grid(); q = np.stack([A, Z], -1)
    d_out = Pf.at(sd, q, cval=-30.0)
    omega = d_out > 0
    dom = d_out > -4.0
    lab268, P268 = terr("Gray268"); lab269, P269 = terr("Gray269")
    tal = Pf.at((lab268 == BONES.index("talus")).astype(float), q) > 0.5
    # --- the top
    S = []
    for fig in ("Gray290", "Gray291"):
        s = side_samples(fig, "top", TOP_SHARE)
        S.append(np.column_stack([s[:, 0], s[:, 1], s[:, 2], np.ones(len(s))]))
    top_sil = np.concatenate(S)
    inner = []
    for fs, pairs in (("Gray290", [("first", "second")]), ("Gray291", [("second", "third")]),
                      ("Gray291", [("third", "cuboid"), ("navicular", "cuboid")])):
        c = _pair("Gray268", fs, pairs)
        inner.append(np.column_stack([c[:, 0], c[:, 1], c[:, 2], np.full(len(c), 1.0)]))
    # the calcaneus at the foot of the talus's lateral wall: Fig. 268's border x Fig. 291's talocalcaneal line and the
    # sinus tarsi's floor (placed just on the calcaneus's side)
    lat = [to_plane("Gray268", np.asarray(pts, float)) for a, b, k, pts in lines()["Gray268"] if {a, b} == {"talus", "calcaneus"}]
    lat = _resample([qq for qq in lat if np.ptp(qq[:, 0]) <= np.ptp(qq[:, 1])][0], 0.5)
    sid = np.concatenate([_line("Gray291", "talus", "calcaneus", "joint")[:0]] + [to_plane("Gray291", np.asarray(pts, float))
                          for a, b, k, pts in lines()["Gray291"] if (a, b) in (("talus", "calcaneus"), ("calcaneus", "sinus"))])
    zs, ys = _fn_of_z(_resample(sid, 0.5), 0)
    za, xa = _fn_of_z(lat, 0)
    zz = np.arange(max(zs.min(), za.min()), min(zs.max(), za.max()), 0.5)
    foot = np.stack([np.interp(zz, za, xa) - 0.8, zz, np.interp(zz, zs, ys)], 1)
    inner.append(np.column_stack([foot, np.full(len(foot), 2.0)]))
    data_t = np.concatenate([top_sil] + inner)
    data_t = data_t[Pf.at(sd, data_t[:, :2], cval=-30) > -1.0]
    sl = slit()
    T, cuts = thin_plate(P, dom, data_t, slits=[sl], lam=LAM)
    log("  T solved: %d samples, %.0f s" % (len(data_t), time.time() - t0))
    # the talus's lateral and hind walls: rounded down to the calcaneus at the slit
    from scipy.spatial import cKDTree
    sd_ = _resample(sl, 0.1); tree = cKDTree(sd_)
    dist, k = tree.query(q.reshape(-1, 2)); dist = dist.reshape(A.shape); k = k.reshape(A.shape)
    tal_side = ndi.binary_dilation(tal, iterations=1) & (dist < STEP_R + 1.0)
    # the foot of the wall: T just across the slit on the calcaneus's side (the side away from the talus's middle)
    tc = np.array([P.ax[0][tal.any(1)].mean(), P.ax[1][tal.any(0)].mean()])
    nrm = sd_ - tc; nrm /= np.linalg.norm(nrm, axis=1)[:, None]
    footT = P.at(np.nan_to_num(T, nan=0.0), sd_ + 0.9 * nrm)
    Tw = T.copy()
    m = tal_side & ~np.isnan(T)
    e = _E(dist[m] / STEP_R, RIM_P)
    Tw[m] = footT[k[m]] + (T[m] - footT[k[m]]) * e
    # --- the bottom
    S = []
    for fig in ("Gray290", "Gray291"):
        s = side_samples(fig, "bottom", BOT_SHARE)
        S.append(np.column_stack([s[:, 0], s[:, 1], s[:, 2], np.ones(len(s))]))
    bot_sil = np.concatenate(S)
    inner = []
    # the sustentaculum's under edge (Fig. 290) at the plan's medial border
    su = _line("Gray290", "calcaneus", "calcaneus", "inner")
    for y, z in su:
        j = int(round((z - P.lo[1]) / h)); col = omega[:, j]
        if col.any():
            inner.append((P.ax[0][col].max() - 1.5, z, y, 2.0))
    # the talar head's underside (Fig. 290's line in front of the sustentaculum), where Fig. 269 shows the head
    tcl = _line("Gray290", "talus", "calcaneus", "joint")
    for y, z in tcl:
        x = _owner_x(lab269, P269, "talus", z, 0.3, True)
        if x is not None and z > su[:, 1].max() - 1.0:
            inner.append((x, z, y, 1.0))
    inner = np.array(inner)
    data_b = np.concatenate([bot_sil, inner])
    # the plantar edges no plate shows from the side: the depth below the top (helper heights)
    extra = []
    for bone, depth in PLANTAR_DEPTH.items():
        for z in np.arange(-20, 40, 0.5):
            x = _owner_x(lab269, P269, bone, z, 0.5 if bone != "navicular" else 0.7, True)
            if x is None:
                continue
            t = P.at(np.nan_to_num(Tw, nan=0.0), np.array([[x, z]]))[0]
            extra.append((x, z, t - depth, 0.6))
    data_b = np.concatenate([data_b, np.array(extra)])
    data_b = data_b[Pf.at(sd, data_b[:, :2], cval=-30) > -1.0]
    B, _ = thin_plate(P, dom, data_b, lam=LAM)
    log("  B solved: %d samples, %.0f s" % (len(data_b), time.time() - t0))
    # --- the rim
    Tn = np.nan_to_num(Tw, nan=0.0); Bn = np.nan_to_num(B, nan=0.0)
    Bn = np.minimum(Bn, Tn - 2.0)
    r = np.clip(RIM_SHARE * (Tn - Bn), 3.0, RIM_MAX)
    e = _E(np.clip(d_out, 0, None) / r, RIM_P)
    M = 0.5 * (Tn + Bn)
    Tr = M + (Tn - M) * e; Br = M - (M - Bn) * e
    return dict(P=P, T=Tn, B=Bn, Tr=Tr, Br=Br, d_out=d_out, data_t=data_t, data_b=data_b, slit=sl, T_raw=T, tal=tal)


def _E(t, p):
    t = np.clip(t, 0.0, 1.0); return (1.0 - (1.0 - t) ** p) ** (1.0 / p)


class Grid:
    """A field on a box (D, lo, h, n) in the foot frame; also what platematch.cast reads."""
    def __init__(self, D, lo, h):
        self.D = D; self.lo = np.asarray(lo, float); self.h = float(h); self.n = np.array(D.shape)
        self.ax = [(self.lo[k] + self.h * np.arange(self.n[k])).astype(np.float32) for k in range(3)]


def sample(G, P, cval=30.0):
    """A Grid's value at points P (..., 3) mm (linear)."""
    P = np.asarray(P, float); sh = P.shape[:-1]; Q = P.reshape(-1, 3)
    v = ndi.map_coordinates(G.D, [(Q[:, k] - G.lo[k]) / G.h for k in range(3)], order=1, mode="constant", cval=cval)
    return v.reshape(sh).astype(np.float32)


def solid(H, h=0.5, pad=3.0):
    """M2: the one solid as a field on a box (mm, - inside), from heights(): the body between the rounded top and
    bottom over the plan, nothing outside the plan."""
    P = H["P"]; inside = H["d_out"] > 0
    xs = P.ax[0][inside.any(1)]; zs = P.ax[1][inside.any(0)]
    lo = np.array([xs.min() - pad, H["Br"][inside].min() - pad, zs.min() - pad])
    hi = np.array([xs.max() + pad, H["Tr"][inside].max() + pad, zs.max() + pad])
    n = np.ceil((hi - lo) / h).astype(int) + 1
    ax = [lo[k] + h * np.arange(n[k]) for k in range(3)]
    Xg, Zg = np.meshgrid(ax[0], ax[2], indexing="ij")
    iq = [(Xg - P.lo[0]) / P.h, (Zg - P.lo[1]) / P.h]
    def at(A, order=3):
        return ndi.map_coordinates(A, iq, order=order, mode="nearest")
    Tr, Br, dout = at(H["Tr"]), at(H["Br"]), at(H["d_out"], 1)
    gT = np.hypot(*np.gradient(Tr, h)); gB = np.hypot(*np.gradient(Br, h))
    nT = np.sqrt(1 + gT ** 2); nB = np.sqrt(1 + gB ** 2)
    D = np.empty(tuple(n), np.float32)
    for j, y in enumerate(ax[1]):
        D[:, j, :] = np.maximum(np.maximum((y - Tr) / nT, (Br - y) / nB), -dout)
    return Grid(D, lo, h)


# ------------------------------------------------------------------------------------- M2 (attempt 2): lofted sections
SECTION_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "traces", "tarsus_sections.npz")
SEC_K, SEC_N, SEC_PAD = 48, 64, 0.15
SEC_EASE = (2.0, 1.5)
SEC_Q = 40.0            # the library kept as int8: value x SEC_Q (1/40 of a section's half size)   # library smoothing: (fractions, raster px)     # fractions along a bone, raster per section, margin round the unit box


def make_sections(cache, h=0.3, log=print):
    """Rule 2 of the repair: each single-bone build's coronal section shape, normalised. The build (own frame, from
    foot_whole's cache) is only turned to the foot's axes (the rotation part of its pose, so 'coronal' means the
    foot's x-y plane); its size and place are thrown away. For SEC_K fractions t of its length along z: its field on
    the section's own bounding box (x lateral to medial, y bottom to top) widened by SEC_PAD, in units of the box's
    half mean size. Saved to traces/tarsus_sections.npz."""
    import foot_whole as W
    own = W.own_fields(cache, log=log); out = {}
    for name in BONES:
        G = own[name]; R, _ = W.pose(name)
        ins = np.argwhere(G.D < 0) * G.h + G.lo
        c_own = ins.mean(0); q = (ins - c_own) @ R.T
        lo, hi = q.min(0) - 1.0, q.max(0) + 1.0
        ax = [np.arange(lo[k], hi[k], h) for k in range(3)]
        X, Y, Z = np.meshgrid(*ax, indexing="ij")
        Q = np.stack([X, Y, Z], -1) @ R + c_own                          # foot-turned point -> own point
        D = ndi.map_coordinates(G.D, [(Q[..., k] - G.lo[k]) / G.h for k in range(3)], order=1, mode="constant", cval=20.0)
        inside = D < 0
        zin = np.where(inside.any((0, 1)))[0]; z0, z1 = ax[2][zin[0]], ax[2][zin[-1]]
        lib = np.zeros((SEC_K, SEC_N, SEC_N), np.float32); box = np.zeros((SEC_K, 4))
        for k in range(SEC_K):
            t = (k + 0.5) / SEC_K; z = z0 + t * (z1 - z0)
            j = np.argmin(abs(ax[2] - z)); m = inside[:, :, j]
            xs = ax[0][m.any(1)]; ys = ax[1][m.any(0)]
            bx = (xs.min(), xs.max(), ys.min(), ys.max()); box[k] = bx
            s = 0.5 * np.sqrt((bx[1] - bx[0]) * (bx[3] - bx[2]))
            u = np.linspace(-SEC_PAD, 1 + SEC_PAD, SEC_N)
            U, V = np.meshgrid(u, u, indexing="ij")
            px = bx[0] + U * (bx[1] - bx[0]); py = bx[2] + V * (bx[3] - bx[2])
            lib[k] = ndi.map_coordinates(D[:, :, j], [(px - lo[0]) / h, (py - lo[1]) / h], order=1, mode="nearest") / s
        out[name] = lib; out[name + "_box"] = box; out[name + "_len"] = np.array([z1 - z0])
        log("  %s: length %.1f mm, widest %.1f, tallest %.1f" % (name, z1 - z0, (box[:, 1] - box[:, 0]).max(), (box[:, 3] - box[:, 2]).max()))
    np.savez_compressed(SECTION_FILE, **{k: (np.clip(np.round(v * SEC_Q), -127, 127).astype(np.int8) if v.ndim == 3 else v)
                                         for k, v in out.items()})
    return out


_SEC = {}
def sections():
    if not _SEC:
        d = np.load(SECTION_FILE)
        for k in d.files:
            a = d[k].astype(np.float32)
            if a.ndim == 3:
                a = a / SEC_Q if d[k].dtype == np.int8 else a     # the builds' fine relief and raster steps out of the shapes; smooth along the bone
                a = ndi.gaussian_filter(a, (SEC_EASE[0], SEC_EASE[1], SEC_EASE[1]), mode="nearest")
            _SEC[k] = a
    return _SEC


ZSTEP = 0.5
SIDE_PICK = {"talus": "Gray291", "calcaneus": None, "navicular": "Gray290", "first": "Gray290", "second": None,
             "third": "Gray291", "cuboid": "Gray291"}      # rule 4: the plate that shows the part directly decides
                                                           # (None: the mean of the two where they agree within 2 mm)
BOX_EASE = 3.0    # mm along z: each bone's box edges eased (no owner flips from one column to the next)


def _edges(lab, P, b, axis_vals, zj, outside_ok):
    """A bone's extent in one column of a plate's labels: (lo, hi, lo_true, hi_true). An edge is true when the next
    pixel beyond it is off the tarsus or belongs to a bone in `outside_ok` (a neighbour met edge to edge)."""
    col = lab[:, zj]; w = np.where(col == b)[0]
    if len(w) < 3:
        return None
    i0, i1 = w.min(), w.max()
    nxt = lambda i: col[i] if 0 <= i < len(col) else -1
    a, c = nxt(i0 - 3), nxt(i1 + 3)
    return axis_vals[i0], axis_vals[i1], (a < 0 or a in outside_ok), (c < 0 or c in outside_ok)


def boxes(log=print):
    """Each bone's coronal box along z from the four plates (rule 1): x lateral/medial from Figs. 268/269, y bottom/top
    from Figs. 290/291, z from where Fig. 268 (269 for the calcaneus's medial half) shows it. Where a plate does not
    show an edge directly (a neighbour stacked in front of it) the edge comes from a drawn joint line, a helper depth,
    or interpolation along z; each source is recorded. Returns {bone: dict(z, xl, xm, yb, yt, src)}."""
    zg = np.arange(-100.0, 46.0 + 1e-6, ZSTEP)
    T = {f: terr(f) for f in FIGS}
    bi = {b: i for i, b in enumerate(BONES)}
    stacked_plan = {("Gray268", "calcaneus"): {bi["talus"]}}
    lab268, P268 = T["Gray268"]
    cx = [P268.ax[0][np.where(lab268 == i)[0]].mean() for i in range(len(BONES))]
    def behind(f, k):
        # in a side view a bone's edge against a bone farther from the eye is its own outline (it hides the other)
        s = 1.0 if f == "Gray290" else -1.0
        return {o for o in range(len(BONES)) if o != k and s * cx[k] > s * cx[o] + 2.0}
    out = {}
    for b in BONES:
        k = bi[b]; rec = {kk: np.full(len(zg), np.nan) for kk in ("xl", "xm", "yb", "yt")}; src = {}
        others = set(range(len(BONES))) - {k}
        # plan: x
        cand = {"xl": [], "xm": []}
        for f in PLAN:
            lab, P = T[f]; ok = others - stacked_plan.get((f, b), set())
            if f == "Gray269" and b == "talus":
                continue
            v = np.full((2, len(zg)), np.nan)
            for i, z in enumerate(zg):
                j = int(round((z - P.lo[1]) / P.h))
                if not 0 <= j < P.n[1]:
                    continue
                e = _edges(lab, P, k, P.ax[0], j, ok)
                if e is None:
                    continue
                if e[2]: v[0, i] = e[0]
                if e[3]: v[1, i] = e[1]
            cand["xl"].append(v[0]); cand["xm"].append(v[1])
        for kk in ("xl", "xm"):
            A = np.array(cand[kk]); rec[kk] = _nanmean(A) if len(A) else rec[kk]
        # z range: Fig. 268 (the calcaneus: either plan)
        figs_z = PLAN if b == "calcaneus" else ("Gray268",)
        if b == "talus":      # its posterior process: Fig. 268 draws the trochlea's hind border; Figs. 290/291 show the
            figs_z = ("Gray268",) + SIDE    # process directly, from the side (rule 4)
        zin = np.zeros(len(zg), bool)
        for f in figs_z:
            lab, P = T[f]
            pres = (lab == k).sum(0) > 3
            zin |= np.interp(zg, P.ax[1], pres.astype(float)) > 0.5
        # side: y
        cy = {}
        for f in SIDE:
            lab, P = T[f]
            v = np.full((2, len(zg)), np.nan)
            for i, z in enumerate(zg):
                j = int(round((z - P.lo[1]) / P.h))
                if not 0 <= j < P.n[1]:
                    continue
                e = _edges(lab, P, k, P.ax[0], j, behind(f, k))
                if e is None:
                    continue
                if e[2]: v[0, i] = e[0]
                if e[3]: v[1, i] = e[1]
            cy[f] = v
        pick = SIDE_PICK[b]
        for r, kk in ((0, "yb"), (1, "yt")):
            a, c = cy["Gray290"][r], cy["Gray291"][r]
            if pick:
                o = c if pick == "Gray291" else a; other = a if pick == "Gray291" else c
                rec[kk] = np.where(np.isnan(o), other, o)
            else:
                m = _nanmean(np.stack([a, c]))
                big = np.abs(a - c) > 2.0
                ext = np.fmin(a, c) if r == 0 else np.fmax(a, c)        # disagreeing: the outer one (the silhouette)
                rec[kk] = np.where(big, ext, m)
        out[b] = dict(z=zg, zin=zin, src=src, **rec)
    _fallbacks(out, log)
    for b, r in out.items():
        for kk in ("xl", "xm", "yb", "yt"):
            r[kk] = _fill_ease(r["z"], r[kk], r["zin"])
    return out


def _nanmean(A):
    n = (~np.isnan(A)).sum(0); return np.where(n > 0, np.nansum(A, 0) / np.maximum(n, 1), np.nan)


def _line_y(fig, pairs, z):
    """The lowest/highest y of a plate's drawn lines (bone pairs) at z: (min, max) arrays, nan where none."""
    lo = np.full(len(z), np.nan); hi = np.full(len(z), np.nan)
    for a, b, kind, pts in lines()[fig]:
        if (a, b) in pairs or (b, a) in pairs:
            q = _resample(to_plane(fig, np.asarray(pts, float)), 0.2)
            for i, zz in enumerate(z):
                s = q[np.abs(q[:, 1] - zz) < 0.3]
                if len(s):
                    lo[i] = np.fmin(lo[i], s[:, 0].min()); hi[i] = np.fmax(hi[i], s[:, 0].max())
    return lo, hi


def _fallbacks(out, log):
    z = out["talus"]["z"]
    tc = [("talus", "calcaneus"), ("talus", "sinus"), ("calcaneus", "sinus")]
    lo0, hi0 = _line_y("Gray290", tc, z); lo1, hi1 = _line_y("Gray291", tc, z)
    t = out["talus"]; c = out["calcaneus"]
    tb = np.fmin(lo0, lo1); ct = np.fmax(hi0, hi1)
    m = np.isnan(t["yb"]) | (t["yb"] > tb + 0.5)
    t["yb"] = np.where(m & ~np.isnan(tb), tb, t["yb"]); t["src"]["yb"] = "Figs. 290/291 talocalcaneal and sinus lines"
    m = ~np.isnan(ct) & (np.isnan(c["yt"]) | (c["yt"] < ct))
    c["yt"] = np.where(m, ct, c["yt"]); c["src"]["yt"] = "own silhouette; under the talus Figs. 290/291 joint lines"
    for b, depth in PLANTAR_DEPTH.items():
        r = out[b]; m = np.isnan(r["yb"]) & r["zin"]
        r["yb"] = np.where(m, r["yt"] - depth, r["yb"]); r["src"]["yb"] = "helper depth %.0f mm below its top where hidden" % depth


def _fill_ease(z, v, zin):
    """Interpolated along z over the gaps inside the bone, held flat beyond, eased by BOX_EASE, nan outside it."""
    ok = ~np.isnan(v) & zin
    if ok.sum() < 2:
        return np.where(zin, np.nan, np.nan)
    f = np.interp(z, z[ok], v[ok])
    f = ndi.gaussian_filter1d(ndi.median_filter(f, 5), BOX_EASE / ZSTEP, mode="nearest")
    return np.where(zin, f, np.nan)


END_R = {"calcaneus": (6.0, 0.8), "talus": (4.0, 0.8)}   # mm: (back, front) end rounding: the free ends
END_T = 0.1       # the fraction of a bone's length kept off each articular end of its section library
END_RIM = 0.8     # mm: an articular end only its rim rounded
LOFT_K = 2.0      # mm: the bones' sections met by a soft union (one solid, no seams)
LOFT_EASE = 1.0   # mm: the lofted field eased in 3D once (the sections' raster steps out)


def _smin(a, b, k):
    hh = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * hh - k * hh * (1.0 - hh)


def bone_section_field(b, r, X, Y, z):
    """One bone's lofted field on a coronal slice (X, Y at z): its library section at its fraction of length, set in
    its box. +large where the bone is not."""
    L = sections(); lib = L[b]; zi = r["z"][r["zin"]]; z0, z1 = zi.min(), zi.max()
    i = np.argmin(np.abs(r["z"] - np.clip(z, z0, z1)))
    xl, xm, yb, yt = r["xl"][i], r["xm"][i], r["yb"][i], r["yt"][i]
    if not np.all(np.isfinite([xl, xm, yb, yt])) or xm - xl < 0.5 or yt - yb < 0.5:
        return None
    tt = (np.clip(z, z0, z1) - z0) / max(z1 - z0, 1e-6)
    cb = 0.0 if b in END_R else END_T; cf = END_T         # an articular end: the section held at its full shape
    tt = cb + (1 - cb - cf) * tt                          # there; its face comes from the joint surface (M3)
    kf = np.clip(tt * SEC_K - 0.5, 0, SEC_K - 1)
    k0 = int(np.floor(kf)); k1 = min(k0 + 1, SEC_K - 1); w = kf - k0
    sec = (1 - w) * lib[k0] + w * lib[k1]
    U = (X - xl) / (xm - xl); V = (Y - yb) / (yt - yb)
    iu = (U + SEC_PAD) / (1 + 2 * SEC_PAD) * (SEC_N - 1); iv = (V + SEC_PAD) / (1 + 2 * SEC_PAD) * (SEC_N - 1)
    rb, rf = END_R.get(b, (END_RIM, END_RIM)); d = min(z - z0, z1 - z); e = min(rb if z - z0 < z1 - z else rf, 0.2 * (z1 - z0))
    f = np.sqrt(max(0.0, 1.0 - max(0.0, 1.0 - d / e) ** 2)) if e > 0 else 1.0
    f = max(f, 0.35)       # the end's rim rounded over END_R: the box drawn in towards its middle (to 35 % at the very end)
    cxm, cym = 0.5 * (xl + xm), 0.5 * (yb + yt)
    xl, xm = cxm + (xl - cxm) * f, cxm + (xm - cxm) * f; yb, yt = cym + (yb - cym) * f, cym + (yt - cym) * f
    U = (X - xl) / (xm - xl); V = (Y - yb) / (yt - yb)
    iu = (U + SEC_PAD) / (1 + 2 * SEC_PAD) * (SEC_N - 1); iv = (V + SEC_PAD) / (1 + 2 * SEC_PAD) * (SEC_N - 1)
    s = 0.5 * np.sqrt((xm - xl) * (yt - yb))
    v = ndi.map_coordinates(sec, [iu, iv], order=1, mode="constant", cval=3.0) * s
    return np.maximum(v, max(z0 - z, z - z1))


def _true_distance(F, h, ease=0.9):
    """A lofted field made a true signed distance (mm) of its own zero set, then eased."""
    m = F < 0
    if not m.any():
        return np.full(F.shape, 20.0, np.float32)
    d = ndi.distance_transform_edt(~m, sampling=h) - ndi.distance_transform_edt(m, sampling=h)
    return ndi.gaussian_filter(np.clip(d, -12.0, 20.0), ease / h).astype(np.float32)


LOFT_FIT = 2      # rounds of the box correction: each bone's lofted extents per z brought to its plate box (rule 1)


def loft(h=0.4, B=None, log=print, pad=6.0, which=None):
    """M2: the one solid as lofted coronal sections, each bone's part a true distance field. The boxes are corrected
    LOFT_FIT times so the lofted part's own extents at each z (after easing) equal the plates' box: each bone fills
    its plate territories up to the drawn joint lines. Returns (Grid, {bone: Grid})."""
    import copy
    B0 = B or boxes(log=log); which = which or BONES; B = copy.deepcopy(B0)
    for r in range(LOFT_FIT + 1):
        G, per = _loft(h, B, pad, which, ref=B0)
        if r == LOFT_FIT:
            break
        err = []
        for b in which:
            m = per[b].D < 0; rb = B[b]; r0 = B0[b]
            for k, ax_, f in (("xl", 0, min), ("xm", 0, max), ("yb", 1, min), ("yt", 1, max)):
                got = np.full(len(rb["z"]), np.nan)
                for i, z in enumerate(rb["z"]):
                    if not rb["zin"][i]:
                        continue
                    j = int(round((z - G.lo[2]) / h))
                    if not 0 <= j < m.shape[2]:
                        continue
                    sl = m[:, :, j]
                    if not sl.any():
                        continue
                    a = np.where(sl.any(1 - ax_))[0]
                    got[i] = G.lo[ax_] + h * (a.min() if f is min else a.max())
                dlt = np.where(np.isnan(got), 0.0, r0[k] - got)
                dlt = ndi.gaussian_filter1d(np.nan_to_num(dlt), BOX_EASE / ZSTEP, mode="nearest")
                lim = 0.25 * np.abs(np.nan_to_num(rb["xm"] - rb["xl"] if ax_ == 0 else rb["yt"] - rb["yb"]))
                rb[k] = rb[k] + np.clip(dlt, -lim, lim)
                ok = ~np.isnan(got) & rb["zin"]
                if ok.any():
                    err.append(np.abs(r0[k] - got)[ok].mean())
        log("  loft round %d: mean box misfit %.2f mm" % (r, np.mean(err)))
    return G, per


def _loft(h, B, pad, which, ref):
    xs = np.concatenate([ref[b][k][ref[b]["zin"]] for b in which for k in ("xl", "xm")])
    ys = np.concatenate([ref[b][k][ref[b]["zin"]] for b in which for k in ("yb", "yt")])
    zs = np.concatenate([ref[b]["z"][ref[b]["zin"]] for b in which])
    lo = np.array([np.nanmin(xs), np.nanmin(ys), zs.min()]) - pad
    hi = np.array([np.nanmax(xs), np.nanmax(ys), zs.max()]) + pad
    n = np.ceil((hi - lo) / h).astype(int) + 1
    ax = [lo[k] + h * np.arange(n[k]) for k in range(3)]
    X, Y = np.meshgrid(ax[0], ax[1], indexing="ij")
    per = {b: np.full(tuple(n), 20.0, np.float32) for b in which}
    for j, z in enumerate(ax[2]):
        for b in which:
            v = bone_section_field(b, B[b], X, Y, z)
            if v is not None:
                per[b][:, :, j] = np.minimum(v, 20.0)
    sig = LOFT_EASE / h
    for b in which:
        per[b] = _true_distance(ndi.gaussian_filter(per[b], sig), h)
    D = None
    for b in which:
        D = per[b] if D is None else _smin(D, per[b], LOFT_K)
    return Grid(D.astype(np.float32), lo, h), {b: Grid(per[b], lo, h) for b in which}


# ----------------------------------------------------------------------------------------------- M3: joints as surfaces
GROW, GROW_R = 3.5, 6.0    # mm: each bone grows into a neighbour within GROW_R (the joint is then cut from the overlap)
JOINT_REACH = 5.0          # mm: a joint surface acts within this of the neighbour (with its side of the crevice)
SETBACK = 0.45             # mm: each bone set back from its joint surface (0.6 left the midfoot spaces at 2 mm once the rims were eased)
RIM_K = 0.6                # mm: the bone's field eased by this once it is cut (its rims rounded)
JOINT_DEG = {("calcaneus", "talus"): 3, ("navicular", "talus"): "ellipsoid"}   # the talar head: Gray "large, oval, and convex", longer across    # the talocalcaneal surface S-shaped (posterior convex, anterior concave)


def _smax(a, b, k):
    return -_smin(-a, -b, k)


ARTIC = [("calcaneus", "talus"), ("calcaneus", "cuboid"), ("talus", "navicular"), ("navicular", "first"),
         ("navicular", "second"), ("navicular", "third"), ("cuboid", "third"), ("first", "second"), ("second", "third")]
# Gray: the cuboid and navicular articulate only occasionally (a non-articular gap here); the calcaneus and navicular
# are joined by ligament only.


def neighbours(b):
    return [o for p in ARTIC for o in p if b in p and o != b]


def grown(per):
    """Each bone's lofted part grown towards its articular neighbours (only where one is within GROW_R)."""
    out = {}
    for b in per:
        m = np.min(np.stack([per[o].D for o in neighbours(b) if o in per]), 0)
        out[b] = Grid((per[b].D - GROW * np.clip(1.0 - m / GROW_R, 0.0, 1.0)).astype(np.float32), per[b].lo, per[b].h)
    return out


class JointSurface:
    """One joint as one smooth surface: in a local frame (e1, e2, n) from the contact's own spread, n-offset a
    polynomial in (e1, e2) of degree 2 (ball, saddle, near-flat) or 3. side: +1 when bone `a` lies on +n."""
    def __init__(self, a, b, pts, wa, deg=2):
        self.a, self.b, self.deg = a, b, deg
        if deg == "ellipsoid":
            from scipy.optimize import least_squares
            ca = np.asarray(wa).mean(0); c0 = pts.mean(0); _, _, vt = np.linalg.svd(pts - c0, full_matrices=False)
            n0 = vt[2] if vt[2] @ (ca - c0) > 0 else -vt[2]; e1 = vt[0]; e2 = np.cross(n0, e1)
            self.E = np.stack([e1, e2, n0]); keep = np.ones(len(pts), bool)
            def res(v, P):
                c = c0 + v[0] * n0 + v[1] * e1 + v[2] * e2; q = (P - c) @ self.E.T
                return (np.sqrt((q[:, 0] / v[3]) ** 2 + (q[:, 1] / v[4]) ** 2 + (q[:, 2] / v[4]) ** 2) - 1.0) * v[4]
            x = np.r_[18.0, 0, 0, 22.0, 18.0]
            for _ in range(3):
                x = least_squares(lambda v: res(v, pts[keep]), x, bounds=([8, -8, -8, 12, 12], [40, 8, 8, 45, 40])).x
                rr = res(x, pts); keep = np.abs(rr) < 2.5 * rr[keep].std() + 0.2
            self.x = x; self.c = c0 + x[0] * n0 + x[1] * e1 + x[2] * e2; self.R = (x[3], x[4]); self.rms = float(rr[keep].std())
            self.side = 1.0 if np.mean(self.signed_raw(wa)) > 0 else -1.0
            return
        if deg == "sphere":                                  # algebraic sphere fit, then refined radius
            from scipy.optimize import least_squares
            # radius held to the talar head's own (14-24 mm: our talus build's head, talus.HEAD_R 16.6-25), the
            # centre on the talus's side of the contact; points off the ball by more than 2.5 sd dropped, 3 rounds
            ca = np.asarray(wa).mean(0); c0 = pts.mean(0); n0 = (ca - c0) / np.linalg.norm(ca - c0)
            x = np.r_[c0 + 18.0 * n0, 18.0]; keep = np.ones(len(pts), bool)
            for _ in range(3):
                r = least_squares(lambda v: np.linalg.norm(pts[keep] - v[:3], axis=1) - v[3], x,
                                  bounds=([-np.inf] * 3 + [14.0], [np.inf] * 3 + [24.0]))
                x = r.x; res = np.linalg.norm(pts - x[:3], axis=1) - x[3]; keep = np.abs(res) < 2.5 * res[keep].std() + 0.2
            if (x[:3] - c0) @ n0 < 0:                         # the ball's centre on the talus's side (a head, not a cup)
                r = least_squares(lambda v: np.linalg.norm(pts[keep] - (c0 + v[0] * n0 + v[1:4]), axis=1) - v[0],
                                  np.r_[18.0, 0, 0, 0], bounds=([14.0, -6, -6, -6], [24.0, 6, 6, 6]))
                x = np.r_[c0 + r.x[0] * n0 + r.x[1:4], r.x[0]]
                res = np.linalg.norm(pts - x[:3], axis=1) - x[3]
            self.c, self.R = x[:3], float(x[3]); self.rms = float(res[keep].std())
            self.side = 1.0 if np.mean(self.signed_raw(wa)) > 0 else -1.0
            return
        c = pts.mean(0); u, s, vt = np.linalg.svd(pts - c, full_matrices=False)
        self.c, self.E = c, vt               # rows: e1, e2, n
        q = (pts - c) @ vt.T
        A = self._basis(q[:, 0], q[:, 1]); keep = np.ones(len(q), bool)
        for _ in range(3):
            coef, *_ = np.linalg.lstsq(A[keep], q[keep, 2], rcond=None)
            r = q[:, 2] - A @ coef; sd = r[keep].std() + 1e-6; keep = np.abs(r) < 2.5 * sd
        self.coef = coef; self.rms = float(r[keep].std())
        self.side = 1.0 if np.mean(self.signed_raw(wa)) > 0 else -1.0
        self.ext = (q[:, 0].min(), q[:, 0].max(), q[:, 1].min(), q[:, 1].max())

    def _basis(self, u, v):
        cols = [np.ones_like(u), u, v, u * u, u * v, v * v]
        if self.deg >= 3:
            cols += [u ** 3, u * u * v, u * v * v, v ** 3]
        return np.stack(cols, -1)

    def signed_raw(self, P):
        if self.deg == "ellipsoid":
            q = (np.asarray(P) - self.c) @ self.E.T; R1, R2 = self.R
            return (np.sqrt((q[..., 0] / R1) ** 2 + (q[..., 1] / R2) ** 2 + (q[..., 2] / R2) ** 2) - 1.0) * R2
        if self.deg == "sphere":
            return np.linalg.norm(np.asarray(P) - self.c, axis=-1) - self.R
        q = (np.asarray(P) - self.c) @ self.E.T
        f = self._basis(q[..., 0], q[..., 1]) @ self.coef
        h = 1e-3; fu = (self._basis(q[..., 0] + h, q[..., 1]) @ self.coef - f) / h
        fv = (self._basis(q[..., 0], q[..., 1] + h) @ self.coef - f) / h
        return (q[..., 2] - f) / np.sqrt(1 + fu ** 2 + fv ** 2)

    def toward(self, name, P):
        """Signed distance (approx., mm) from the surface, positive on `name`'s side."""
        s = self.side * self.signed_raw(P)
        return s if name == self.a else -s

    def curvature(self):
        """Principal curvatures (1/mm) at the contact's middle, sign: + convex toward bone a."""
        if self.deg == "ellipsoid":
            return np.array([1.0 / self.R[0], 1.0 / self.R[1]])
        if self.deg == "sphere":
            return np.array([1.0, 1.0]) / self.R * (1.0 if self.side < 0 else -1.0) * (1 if self.a == "talus" else -1) * -1
        c = self.coef; Hm = np.array([[2 * c[3], c[4]], [c[4], 2 * c[5]]])
        return np.linalg.eigvalsh(Hm) * (-self.side)


BRIDGE = 6.0      # mm: the crevice between two articulating parts closed up to this radius (the joint is cut from it)


def _crop(*Ms, pad=6):
    idx = np.argwhere(np.any(np.stack(Ms), 0)); lo = np.maximum(idx.min(0) - pad, 0); hi = np.minimum(idx.max(0) + pad + 1, Ms[0].shape)
    return tuple(slice(a, b) for a, b in zip(lo, hi))


LINE_W = 6        # the drawn joint lines' weight in a joint surface's fit (as many copies of each lifted point)
LINE_IN = 1.0     # mm below the outer surface at which a drawn line's point is lifted into the crevice


def lifted_lines(a, b, per):
    """The plates' drawn joint lines between a and b lifted onto the solid: a plan's line at the solid's top (Fig.
    268) or bottom (Fig. 269) less LINE_IN, a side plate's line at its medial (Fig. 290) or lateral (Fig. 291) side.
    Returns (n, 3)."""
    names = list(per); G = per[names[0]]; h = G.h
    U = np.min(np.stack([per[k].D for k in names]), 0) < 0.5 * BRIDGE       # the crevices counted in
    out = []
    for fig in FIGS:
        for p, q, kind, pts in lines()[fig]:
            if kind != "joint" or {p, q} != {a, b}:
                continue
            ln = _resample(to_plane(fig, np.asarray(pts, float)), 0.8)
            for u, z in ln:
                k = int(round((z - G.lo[2]) / h))
                if not 0 <= k < U.shape[2]:
                    continue
                if fig in PLAN:
                    i = int(round((u - G.lo[0]) / h))
                    if not 0 <= i < U.shape[0] or not U[i, :, k].any():
                        continue
                    col = np.where(U[i, :, k])[0]
                    y = G.lo[1] + h * (col.max() if fig == "Gray268" else col.min())
                    out.append((u, y - LINE_IN if fig == "Gray268" else y + LINE_IN, z))
                else:
                    j = int(round((u - G.lo[1]) / h))
                    if not 0 <= j < U.shape[1] or not U[:, j, k].any():
                        continue
                    row = np.where(U[:, j, k])[0]
                    x = G.lo[0] + h * (row.max() if fig == "Gray290" else row.min())
                    out.append((x - LINE_IN if fig == "Gray290" else x + LINE_IN, u, z))
    return np.array(out).reshape(-1, 3)


def joints(per, gr=None, log=print, min_pts=40):
    """M3: one surface per articulating pair (ARTIC), fitted to the middle of the two lofted parts' contact: the
    crevice between them closed by BRIDGE, its points about equally far from both."""
    names = list(per); G = per[names[0]]; h = G.h
    M = {b: per[b].D < 0 for b in names}
    out, zones = {}, {}
    for a, b in ARTIC:
        sl = _crop(M[a], M[b])
        ma, mb = M[a][sl], M[b][sl]; u = ma | mb
        dil = ndi.distance_transform_edt(~u, sampling=h) <= BRIDGE
        closed = ndi.distance_transform_edt(dil, sampling=h) > BRIDGE
        da = ndi.distance_transform_edt(~ma, sampling=h); db = ndi.distance_transform_edt(~mb, sampling=h)
        zone = (closed & ~u & (da < BRIDGE + 1) & (db < BRIDGE + 1)) | (ma & mb)
        mid = zone & (np.abs(da - db) < 0.75 * h)
        if (ma & mb).any():
            mid |= (ma & mb) & (np.abs(per[a].D[sl] - per[b].D[sl]) < 0.75 * h)
        if mid.sum() < min_pts:
            log("  joint %s-%s: no contact (%d pts)" % (a, b, mid.sum())); continue
        off = np.array([q.start for q in sl])
        pts = G.lo + (np.argwhere(mid) + off) * h
        rng = np.random.default_rng(0)
        if len(pts) > 20000:
            pts = pts[rng.choice(len(pts), 20000, replace=False)]
        ia = np.argwhere(ma & (db < 6.0)); wa = G.lo + (ia[rng.choice(len(ia), min(3000, len(ia)), replace=False)] + off) * h
        key = (a, b)
        drawn = lifted_lines(a, b, per)
        if len(drawn):
            pts = np.concatenate([pts] + [drawn] * LINE_W)
        J = JointSurface(a, b, pts, wa, JOINT_DEG.get(tuple(sorted(key)), 2))
        J.drawn = len(drawn)
        out[key] = J; zones[key] = (sl, zone)
        log("  joint %-20s %6d pts (%d drawn)  rms %.2f mm  curvature radii %s" % ("-".join(key), len(pts), J.drawn, J.rms,
            ", ".join("%.0f" % (1 / k) if abs(k) > 1e-4 else "flat" for k in J.curvature())))
    return out, zones


def _ss_ramp(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3 - 2 * t)


def separate(per, J, zones, log=print):
    """Each bone: its lofted part (its continuous field) joined (soft union) to its side of each joint's closed
    crevice, then cut by each joint surface set back SETBACK where the neighbour is near (soft max: the rim
    rounded over RIM_K). Exactly one piece kept."""
    names = list(per); G = per[names[0]]; h = G.h
    X = None
    pre = {}
    for b in names:
        F = per[b].D.copy()
        for key, (sl, zone) in zones.items():
            if b not in key:
                continue
            o = key[0] if key[1] == b else key[1]; j = J[key]
            # the crevice closed smoothly: the pair's soft union (radius BRIDGE), this bone's side of the joint only
            U = _smin(per[b].D[sl], per[o].D[sl], BRIDGE)
            idx = np.indices(U.shape).reshape(3, -1).T
            P = G.lo + (idx + np.array([q.start for q in sl])) * h
            side = (-j.toward(b, P)).reshape(U.shape).astype(np.float32)
            reach = per[b].D[sl] - (BRIDGE + 1.0)              # and only across the crevice from this bone's part
            F[sl] = _smin(F[sl], _smax(_smax(U, side, 0.5), reach, 0.5), 0.5)
        pre[b] = F
    out = {}
    for b in names:
        F = pre[b].copy()
        for key, (sl, zone) in zones.items():
            if b not in key:
                continue
            o = key[0] if key[1] == b else key[1]; j = J[key]
            sl2 = _crop(pre[o] < JOINT_REACH + 2.0, pad=2)
            idx = np.indices([q.stop - q.start for q in sl2]).reshape(3, -1).T
            P = G.lo + (idx + np.array([q.start for q in sl2])) * h
            near = pre[o][sl2].reshape(-1)        # the neighbour with its side of the crevice
            far = _ss_ramp((near - JOINT_REACH) / 4.0) * 12.0     # let go gently (a steep let-go printed a comb)
            cut = (SETBACK - j.toward(b, P) - far).reshape(F[sl2].shape).astype(np.float32)
            F[sl2] = _smax(F[sl2], cut, RIM_K)
        lab, n = ndi.label(F < 0)
        if n > 1:
            sz = ndi.sum(np.ones(F.shape), lab, range(1, n + 1)); keep = 1 + int(np.argmax(sz))
            F = np.where((lab > 0) & (lab != keep), np.float32(0.05), F)
        m = F < 0; holes = ndi.binary_fill_holes(m) & ~m           # no closed voids
        F = np.where(holes, np.float32(-0.05), F)
        out[b] = Grid(F.astype(np.float32), G.lo, h)
    return out


def bones(h=0.4, log=print):
    """({name: Grid}, assembled Grid, report). Metatarsals and phalanges join later as further lofted parts in
    loft() (their own section libraries and boxes) and further pairs in joints()."""
    t0 = time.time(); rep = {}
    B = boxes(log=log)
    solid_, per = loft(h, B, log=log)
    J, zones = joints(per, log=log)
    bn = separate(per, J, zones, log=log)
    A = Grid(np.min(np.stack([g.D for g in bn.values()]), 0), solid_.lo, h)
    rep["build_s"] = time.time() - t0; rep["joints"] = J; rep["solid"] = solid_; rep["boxes"] = B
    log("  bones built in %.0f s" % rep["build_s"])
    return bn, A, rep


# ------------------------------------------------------------------------------------------------------------ checks
def visible(bn, fig, h=0.2):
    """What each bone shows in a plate's view: a label raster on the plate's frame plane (index into BONES, -1 none)."""
    P = plane_of(fig, h); B = view(fig)[0]
    zb = np.full(tuple(P.n), -1e9); lab = np.full(tuple(P.n), -1, int)
    for name, g in bn.items():
        idx = np.argwhere((g.D < 0) & (g.D > -1.5 * g.h)); X = g.lo + idx * g.h
        q = to_plane(fig, to_pixels(fig, X)); d = X @ B[2]
        ij = np.round(P.idx(q)).astype(int); ok = (ij >= 0).all(1) & (ij < P.n).all(1)
        ij, d = ij[ok], d[ok]
        o = np.argsort(d); ij, d = ij[o], d[o]                    # nearest written last
        k = BONES.index(name)
        better = d > zb[ij[:, 0], ij[:, 1]]
        zb[ij[better, 0], ij[better, 1]] = d[better]; lab[ij[better, 0], ij[better, 1]] = k
    out = np.full(lab.shape, -1, int)                               # each bone's splats closed into its region
    for k in range(len(BONES)):
        m = ndi.binary_fill_holes(ndi.binary_closing(lab == k, iterations=3))
        out[m & (out < 0)] = k
    lab = np.where(lab >= 0, lab, out)
    return lab, P


def _edge(m):
    return m & ~ndi.binary_erosion(m)


def _edge_gap(a, b, h):
    ea, eb = _edge(a), _edge(b)
    if not ea.any() or not eb.any():
        return np.array([np.nan])
    return np.concatenate([ndi.distance_transform_edt(~eb)[ea], ndi.distance_transform_edt(~ea)[eb]]) * h


def check_a1(bn, log=print):
    rep = {}
    for fig in FIGS:
        lab, P = visible(bn, fig)
        tl, TP = terr(fig)
        tl = ndi.zoom(tl, (P.n[0] / tl.shape[0], P.n[1] / tl.shape[1]), order=0)
        sil = tl >= 0                     # the tarsal silhouette (Fig. 291's sinus tarsi mouth inside it)
        mod = ndi.binary_fill_holes(ndi.binary_closing(lab >= 0, iterations=int(1.5 / P.h)))   # joint spaces closed
        d = _edge_gap(mod, sil, P.h)
        r = dict(union=float(np.nanmean(d)), bones={}, lines={})
        for k, b in enumerate(BONES):
            if (tl == k).sum() < 100 or (lab == k).sum() < 10:
                continue
            r["bones"][b] = float(np.nanmean(_edge_gap(lab == k, tl == k, P.h)))
        for a, b, kind, pts in lines()[fig]:
            if kind != "joint" or a not in BONES or b not in BONES:
                continue
            ia, ib = BONES.index(a), BONES.index(b)
            zone = ndi.binary_dilation(lab == ia, iterations=int(2.5 / P.h)) & ndi.binary_dilation(lab == ib, iterations=int(2.5 / P.h))
            zone = zone & ~(ndi.binary_erosion(lab == ia, iterations=int(1.5 / P.h)) | ndi.binary_erosion(lab == ib, iterations=int(1.5 / P.h)))
            q = _resample(to_plane(fig, np.asarray(pts, float)), 0.5)
            if not zone.any():
                r["lines"]["%s-%s" % (a, b)] = float("nan"); continue
            sk = ndi.distance_transform_edt(~zone) * P.h
            # the built joint's outer trace: the middle of the zone where the two visible regions meet
            mid = zone & (ndi.distance_transform_edt(lab != ia) * P.h < 2.5) & (ndi.distance_transform_edt(lab != ib) * P.h < 2.5)
            dm = ndi.distance_transform_edt(~mid) * P.h if mid.any() else sk
            r["lines"]["%s-%s" % (a, b)] = float(np.mean(P.at(dm, q, cval=30.0)))
        rep[fig] = r
        log("  A1 %s union %.2f | %s | lines %s" % (fig, r["union"], " ".join("%s %.2f" % kv for kv in r["bones"].items()),
            " ".join("%s %.2f" % kv for kv in r["lines"].items())))
    return rep


def check_a2(bn, J, log=print):
    names = list(bn); G = bn[names[0]]; h = G.h; rep = {"overlap": {}, "space": {}, "pieces": {}, "voids": {}}
    M = {b: bn[b].D < 0 for b in names}
    E = {b: ndi.distance_transform_edt(~M[b]) * h for b in names}
    X = None
    for key, j in J.items():
        a, b = key
        both = M[a] & M[b]
        rep["overlap"][key] = float(-np.max(np.maximum(bn[a].D, bn[b].D)[both])) if both.any() else 0.0
        fr = []
        for s, o in ((a, b), (b, a)):
            surf = M[s] & ~ndi.binary_erosion(M[s])
            idx = np.argwhere(surf); P = G.lo + idx * h
            t = j.toward(s, P); g = E[o][surf]
            facet = (np.abs(t) < 1.2) & (g < 3.0)                     # this bone's face on the joint (by the surface, its rim's fall-off out)
            if facet.sum():
                fr.append(g[facet])
        g = np.concatenate(fr) if fr else np.array([np.nan])
        rep["space"][key] = dict(n=int(len(g)), share=float(np.mean((g >= 0.8) & (g <= 2.0))), median=float(np.median(g)),
                                 p10=float(np.percentile(g, 10)), p90=float(np.percentile(g, 90)))
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            both = M[a] & M[b]
            if both.any() and tuple(sorted((a, b))) not in rep["overlap"]:
                rep["overlap"][tuple(sorted((a, b)))] = float(-np.max(np.maximum(bn[a].D, bn[b].D)[both]))
    for b in names:
        lab, n = ndi.label(M[b]); rep["pieces"][b] = int(n)
        holes = ndi.binary_fill_holes(M[b]) & ~M[b]; rep["voids"][b] = int(ndi.label(holes)[1])
    # sinus tarsi: the vertical gap between the talus's underside and the calcaneus's top, per coronal slice, where it
    # is not a joint (gap > 2.5 mm); its narrowest along the canal
    t, c = M["talus"], M["calcaneus"]
    ys = np.arange(t.shape[1])
    tb = np.where(t.any(1), np.argmax(t, 1), -1)                    # the talus's lowest voxel per (x, z)
    ct = np.where(c.any(1), t.shape[1] - 1 - np.argmax(c[:, ::-1, :], 1), -1)
    gap = np.where((tb >= 0) & (ct >= 0) & (tb > ct), (tb - ct - 1) * h, np.nan)
    per_z = np.nanmax(np.where(gap > 2.5, gap, np.nan), 0)
    zz = G.ax[2]; okz = ~np.isnan(per_z)
    rep["sinus"] = dict(z=zz[okz].tolist(), widest_per_z=per_z[okz].tolist(),
                        narrowest=float(np.nanmin(per_z)) if okz.any() else float("nan"))
    log("  A2 overlap(max mm) %s" % {"-".join(k): round(v, 2) for k, v in rep["overlap"].items()})
    for k, v in rep["space"].items():
        log("  A2 space %-22s share %.0f%%  median %.2f  p10 %.2f  p90 %.2f  (n %d)" % ("-".join(k), 100 * v["share"], v["median"], v["p10"], v["p90"], v["n"]))
    log("  A2 pieces %s voids %s sinus narrowest %.1f mm" % (rep["pieces"], rep["voids"], rep["sinus"]["narrowest"]))
    return rep
