"""muscles.py: the first muscles of the head, built from nothing on the from-scratch skull and jaw: the masseter (its
superficial and deep portions) and the temporalis, right and left. MUSCLES.md is the ledger of every muscle of the head
that holds to the skull or the jaw, with Gray's words for each.

Read from Gray's Anatomy, 20th edition, 1918 (public domain):
  Fig. 382  (p. 386) the temporalis with the arch and the masseter taken away: its outline, its fan, the white tendon
            spreading up into the fan's middle and running down to the coronoid, the fleshy front band down the coronoid's
            front border; its outline is the plate's red and white, registered on six landmarks (traces/muscle_fig382_temporalis.json)
  Fig. 176  (p. 172) the jaw's outer face with the masseter's area ringed in red (traces/muscle_fig176_masseter.json)
  Fig. 177  (p. 173) the jaw's inner face: the temporalis down the coronoid's inner face to the ridge behind the last molar
  Fig. 378  (p. 379) the masseter on the whole head, superficial and deep portions, the deep one showing behind
  pp. 385-386 the text: "The superficial portion, the larger, arises by a thick, tendinous aponeurosis from the zygomatic
            process of the maxilla, and from the anterior two-thirds of the lower border of the zygomatic arch: its fibers
            pass downward and backward, to be inserted into the angle and lower half of the lateral surface of the ramus of the
            mandible. The deep portion is much smaller, and more muscular in texture; it arises from the posterior third of the
            lower border and from the whole of the medial surface of the zygomatic arch; its fibers pass downward and forward,
            to be inserted into the upper half of the ramus and the lateral surface of the coronoid process of the mandible."
            "The Temporalis ... arises from the whole of the temporal fossa (except that portion of it which is formed by the
            zygomatic bone) and from the deep surface of the temporal fascia. Its fibers converge as they descend, and end in a
            tendon, which passes deep to the zygomatic arch and is inserted into the medial surface, apex, and anterior border
            of the coronoid process, and the anterior border of the ramus of the mandible nearly as far forward as the last
            molar tooth."
  pp. 134, 139, 183 the inferior temporal line and the supramastoid crest limit the temporalis' origin; p. 174 the
            coronoid's lateral surface "affords insertion to the Temporalis and Masseter", its medial surface to the Temporalis.

How a muscle is made. Each muscle (or portion) is a sheet of fibres: fibre(t, w, s), t across the sheet (front to back),
w through it (deep to superficial), s along it (origin to insertion). Every fibre starts on the bone's surface and ends on
it, at the marks named above, which are found on the built bone fields themselves (never moved or changed). A deep fibre is
a string pulled taut over the bone (wrap): where Gray has the muscle lie on the bone (the temporalis on the floor of its
fossa) it lies on it; elsewhere it keeps off. The sheet is filled in finely, written into a grid, softened, and the result
is held off every bone by 0.45 mm except where it is attached (where it meets the bone flush), and off any muscle built
before it. The fibres' lines are kept: the surface carries grooves between fascicles of uneven width that run with the
fibres (geometry), each vertex carries its fibre's direction (a per-vertex field kept with the mesh), and the tendon and
the aponeurosis are smooth, ungrooved and coloured apart.

Head frame, mm: x the body's left, y up, z forward; origin between the porions, Frankfurt plane y = 0.
Run: python3 muscles.py build|check|render  (bone fields from $SCRATCH_OUT/b/<tag>_{skull,jaw}_D.npz, tag $MUSCLE_BONE, default M06)
"""
import os, sys, json, time, pickle
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from scipy.interpolate import RegularGridInterpolator as RGI

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(1, os.path.dirname(HERE))
import sdf
import temporal as TP
import skull2 as SK2

OUT = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
TAG = os.environ.get("MUSCLE_BONE", "M06")
H = 0.5                                   # the muscles' grid (mm)
CLEAR = 0.45                              # held off bone and other muscles by this much except where attached (mm)
BETA_TEM = [0.55, 0.38, 0.2, 0.08, 0.02]   # how far each fibre's guide point drops (front .. hind): Fig. 382's radiating fan
TENDON_SMOOTH = 12                        # rounds of smoothing of the tendon's share over the surface
FLESH, TENDON = (168, 72, 62), (226, 220, 204)


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ====================================================================== the bone, as built (read only)
class Bone:
    def __init__(self, tag=TAG):
        self.F = {}
        for k in ("skull", "jaw"):
            Z = np.load(os.path.join(OUT, "b", "%s_%s_D.npz" % (tag, k)))
            D = Z["D"].astype(np.float32); lo = np.asarray(Z["lo"], float); h = float(Z["h"])
            self.F[k] = RGI([lo[i] + h * np.arange(D.shape[i]) for i in range(3)], D, bounds_error=False, fill_value=6.0)
        self.tag = tag

    def d(self, P, which=("skull", "jaw")):
        P = np.asarray(P, float).reshape(-1, 3)
        return np.min([self.F[k](P) for k in which], axis=0)

    def grad(self, P, which=("skull", "jaw"), e=0.3):
        P = np.asarray(P, float).reshape(-1, 3)
        g = np.zeros_like(P)
        for i in range(3):
            d = np.zeros(3); d[i] = e
            g[:, i] = (self.d(P + d, which) - self.d(P - d, which)) / (2 * e)
        n = np.linalg.norm(g, axis=1, keepdims=True)
        return g / np.maximum(n, 1e-9)

    def onto(self, P, which, target=0.0, rounds=8):
        """points moved along the field's gradient onto its level `target`"""
        P = np.asarray(P, float).reshape(-1, 3).copy()
        for _ in range(rounds):
            P -= (self.d(P, which) - target)[:, None] * self.grad(P, which)
        return P

    def ray(self, starts, step, which, n=400):
        """first entry into bone along a straight ray from each start (stepping by the vector `step`); nan if none"""
        starts = np.asarray(starts, float).reshape(-1, 3); step = np.asarray(step, float)
        out = np.full(starts.shape, np.nan)
        prev = self.d(starts, which); alive = prev > 0
        for i in range(1, n):
            P = starts + i * step
            d = self.d(P, which)
            hit = alive & (d <= 0)
            if hit.any():
                f = prev[hit] / np.maximum(prev[hit] - d[hit], 1e-9)
                out[hit] = starts[hit] + (i - 1 + f)[:, None] * step
                alive &= ~hit
            prev = d
            if not alive.any():
                break
        return out


# ====================================================================== fibres
def wrap(P, bone, which, target, pin, rounds=160, k=0.45, onto=None, push_dir=None, zone=None):
    """Fibres (rows of P: (n, m, 3)) pulled taut between their pinned points (pin: (n, m) bool) and kept `target` mm off the
    bone (a string over the bone: where the straight way runs through bone, the fibre lies on it). onto: (n, m) bool, points
    that are laid on the bone's surface itself whichever side of it they are (where Gray has the muscle arise from the floor of
    a hollow, a taut string would bridge the hollow). push_dir: push along this direction instead of the field's gradient."""
    P = P.copy()
    n, m, _ = P.shape
    tgt = np.broadcast_to(np.asarray(target, float), (n, m)) if np.ndim(target) else np.full((n, m), float(target))
    onto = np.zeros((n, m), bool) if onto is None else onto
    for r in range(rounds):
        Q = P.copy()
        Q[:, 1:-1] += k * (P[:, :-2] + P[:, 2:] - 2 * P[:, 1:-1])
        Q[pin] = P[pin]
        flat = Q.reshape(-1, 3)
        d = bone.d(flat, which).reshape(n, m)
        bad = ((d < tgt) | onto) & ~pin
        if bad.any():
            g = bone.grad(flat[bad.ravel()], which)
            if push_dir is not None:
                pd = np.asarray(push_dir, float)
                zn = zone(flat[bad.ravel()]) if zone is not None else np.ones(len(g), bool)
                g = np.where(((g @ pd) > -0.2)[:, None] | ~zn[:, None], g, pd)     # never out through the far side of the arch
            Q[bad] += ((tgt - d)[bad])[:, None] * g * 1.0
        P = Q
    return P


def resample(C, m):
    """a polyline resampled to m points evenly along its length"""
    C = np.asarray(C, float)
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))]
    u = np.linspace(0, L[-1], m)
    return np.column_stack([np.interp(u, L, C[:, i]) for i in range(C.shape[1])])


def noise1(n, seed, scale, amp):
    """smooth 1-d noise of n samples: a sum of a few sines with random waves"""
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 1, n)
    out = np.zeros(n)
    for _ in range(4):
        out += rng.normal() * np.sin(2 * np.pi * (x * rng.uniform(0.5, 1.5) / scale + rng.random()))
    return amp * out / 2.0


class Sheet:
    """fibres P (nt, nw, ns, 3); tendon (nt, nw, ns) 0 flesh .. 1 tendon; name; attachment sets"""
    def __init__(self, name, P, tendon, groove=1.0, seed=1):
        self.name, self.P, self.tendon, self.groove, self.seed = name, P, tendon, groove, seed

    def fine(self, step=0.45):
        """the sheet filled in so that no two neighbouring samples are further apart than `step`"""
        P = self.P
        sh = P.shape[:3]
        # the fibres eased along their length (2 nodes) and across (1 node), ends kept: the wrapping leaves each node a little off
        # its neighbours' line, and that jitter, read through the fill-in, showed on the surface as scales and contour-like rings
        # (across, the sheet is padded by its point reflection, so a straight run is kept and the edge fibres stay where they are)
        Ps = ndimage.gaussian_filter1d(P, 2.0, axis=2, mode="nearest")
        q = min(4, sh[0] - 1)
        Pp = np.concatenate([2 * Ps[:1] - Ps[q:0:-1], Ps, 2 * Ps[-1:] - Ps[-2:-q - 2:-1]], 0)
        Ps = ndimage.gaussian_filter1d(Pp, 1.0, axis=0)[q:q + sh[0]]
        k = np.clip(np.minimum(np.arange(sh[2]), sh[2] - 1 - np.arange(sh[2])) / 3.0, 0, 1)
        P = P + (Ps - P) * k[None, None, :, None]
        f = []
        for ax in range(3):
            d = np.percentile(np.linalg.norm(np.diff(P, axis=ax), axis=-1), 97) if sh[ax] > 1 else 0
            f.append(int(np.clip(np.ceil(d / step), 1, 14)))
        coords = np.meshgrid(*[np.linspace(0, sh[a] - 1, (sh[a] - 1) * f[a] + 1) for a in range(3)], indexing="ij")
        # cubic across and along the fibres (a linear fill-in leaves a crease at every coarse sample), but linear through the
        # layers: a cubic through them overshoots the outer layer, and the overshoot showed on the surface as wavy terraces
        ax = [np.linspace(0, sh[a] - 1, (sh[a] - 1) * f[a] + 1) for a in range(3)]
        C2 = np.meshgrid(ax[0], ax[2], indexing="ij")
        Lay = np.stack([np.stack([ndimage.map_coordinates(P[:, j, :, c], C2, order=3, mode="nearest") for c in range(3)], -1)
                        for j in range(sh[1])], 1).astype(np.float32)               # (nt', nw, ns', 3)
        j0 = np.minimum(np.floor(ax[1]).astype(int), sh[1] - 2) if sh[1] > 1 else np.zeros(len(ax[1]), int)
        fw = (ax[1] - j0)[None, :, None, None].astype(np.float32)
        X = Lay[:, j0] * (1 - fw) + Lay[:, np.minimum(j0 + 1, sh[1] - 1)] * fw
        tt = coords[0] / max(sh[0] - 1, 1); ww = coords[1] / max(sh[1] - 1, 1); ss = coords[2] / max(sh[2] - 1, 1)
        if getattr(self, "tendon_fn", None) is not None:
            T = self.tendon_fn(tt, ww, ss).astype(np.float32)
        else:
            T = ndimage.map_coordinates(self.tendon, coords, order=1).astype(np.float32)
        return X, T, tt, ww, ss

    def set_tendon(self, fas):
        """the flesh-tendon border along the fibres: each strand's tendon starts at its own place, the border wandering in soft
        tongues across the sheet (a smooth wave, about every `tongue` of the sheet's width) and each strand's share ramping
        over `width` of its length (flesh thinning over tendon), so the border is tongued and soft, never a stepped line
        (T-muscle-2, G7)"""
        spec = getattr(self, "tendon_spec", None)
        if spec is None:
            return
        if spec.get("kind") == "tongues":
            # (repair 2, H1) the aponeurosis drawn on the sheet itself: a narrow tendinous strip along the origin, and a few
            # separate pale tongues reaching down from it between the red bundles, each its own length (mm), narrowing to a
            # point; and a short tendinous insertion
            P = self.P[:, -1]                                               # the outer layer (nt, ns, 3)
            Wmm = float(np.linalg.norm(np.diff(P[:, P.shape[1] // 2], axis=0), axis=-1).sum())
            Lmm = float(np.linalg.norm(np.diff(P[P.shape[0] // 2], axis=0), axis=-1).sum())
            tg = spec["tongues"]

            def fn(tt, ww, ss):
                smm_ = ss * Lmm; umm = tt * Wmm
                T = smoothstep((spec["base_mm"] - smm_) / 1.6 + 0.5)
                for c_, L_, w_ in tg:
                    half = 0.5 * w_ * np.clip(1 - smm_ / L_, 0, 1) ** 0.8
                    T = np.maximum(T, smoothstep((half - np.abs(umm - c_ * Wmm)) / 1.6 + 0.3) * (half > 0))
                return np.maximum(T, smoothstep((ss - spec["after"]) / 0.05 + 0.5))
            self.tendon_fn = fn
            return
        nt, nw = spec["st"].shape
        sd_ = self.seed + 99

        def fn(tt, ww, ss):
            st = ndimage.map_coordinates(spec["st"], [tt * (nt - 1), ww * (nw - 1)], order=1, mode="nearest")
            st = st + spec["jitter"] * vnoise(tt / spec["tongue"], 0.3 * ww, sd_) - spec["side"] * spec["tip"] * (0.5 + 0.5 * vnoise(tt / (0.5 * spec["tongue"]), 0.0, sd_ + 1))
            wd = spec["width"] * (1 + 0.3 * vnoise(tt / spec["tongue"], 5.0, sd_ + 2))
            T = smoothstep((ss - st) / wd + 0.5) if spec["side"] > 0 else smoothstep((st - ss) / wd + 0.5)
            if spec.get("after") is not None:
                T = np.maximum(T, smoothstep((ss - spec["after"]) / 0.08 + 0.5))
            return T
        self.tendon_fn = fn


# ====================================================================== the grid a muscle is written into
class Grid:
    def __init__(self, lo, hi, h=H):
        self.lo = np.asarray(lo, float); self.h = h
        self.n = tuple(int(np.ceil((hi[i] - lo[i]) / h)) + 1 for i in range(3))
        self.ax = [self.lo[i] + h * np.arange(self.n[i]) for i in range(3)]

    def points(self, mask=None):
        I = np.argwhere(mask) if mask is not None else np.indices(self.n).reshape(3, -1).T
        return self.lo + self.h * I, I

    def sample(self, f, chunk=2_000_000):
        out = np.empty(self.n, np.float32).ravel()
        X, Y, Z = self.ax
        idx = np.arange(out.size)
        for a in range(0, out.size, chunk):
            ii = np.unravel_index(idx[a:a + chunk], self.n)
            P = np.column_stack([X[ii[0]], Y[ii[1]], Z[ii[2]]])
            out[a:a + chunk] = f(P)
        return out.reshape(self.n)


def write(grid, X, sigma=0.75):
    """the samples X (k, 3) as a field on the grid: occupied cells softened by sigma mm, read off as a distance (mm, negative inside)"""
    I = np.round((X - grid.lo) / grid.h).astype(np.int64)
    ok = np.all((I >= 0) & (I < np.array(grid.n)), axis=1)
    occ = np.zeros(grid.n, np.float32)
    occ[I[ok, 0], I[ok, 1], I[ok, 2]] = 1.0
    G = ndimage.gaussian_filter(occ, sigma / grid.h)
    return np.clip((0.5 - G) * sigma * np.sqrt(2 * np.pi), -3.0, 3.0).astype(np.float32)


# ====================================================================== plates, put into the head frame
def similarity(A, B):
    """least-squares s, R, t with B ~ s R A + t (2-d)"""
    A = np.asarray(A, float); B = np.asarray(B, float)
    ma, mb = A.mean(0), B.mean(0); A0, B0 = A - ma, B - mb
    U, S, Vt = np.linalg.svd(B0.T @ A0)
    D = np.eye(2); D[1, 1] = np.sign(np.linalg.det(U @ Vt))
    R = U @ D @ Vt; s = (S * np.diag(D)).sum() / (A0 ** 2).sum()
    return s, R, mb - s * R @ ma


def apply(T, P):
    s, R, t = T
    return s * np.asarray(P, float) @ R.T + t


def silhouette(bone, which, sgn, lo=(-60, -110), hi=(110, 125), h=0.5, xs=None):
    """the side view's silhouette of one half (x * sgn > 0): mask over (z, y) and its boundary points (z, y)"""
    zs = np.arange(lo[0], hi[0], h); ys = np.arange(lo[1], hi[1], h)
    xs = np.arange(2, 80, 0.75) if xs is None else xs
    Zg, Yg = np.meshgrid(zs, ys, indexing="ij")
    m = np.zeros(Zg.shape, bool)
    for x in xs:
        P = np.c_[np.full(Zg.size, sgn * x), Yg.ravel(), Zg.ravel()]
        m |= (bone.d(P, which) < 0).reshape(Zg.shape)
    e = m & ~ndimage.binary_erosion(m)
    return m, np.c_[Zg[e], Yg[e]], (zs, ys)


def icp(src, dst, T, rounds=40):
    """refine a similarity T so that the points src (plate) lie on the curve dst (model), both (z, y)"""
    tree = cKDTree(dst)
    for _ in range(rounds):
        Q = apply(T, src)
        d, i = tree.query(Q)
        keep = d < np.percentile(d, 90)
        T = similarity(src[keep], dst[i[keep]])
    d, _ = tree.query(apply(T, src))
    return T, d


def ramus_area(bone, sgn=1, inset=1.5):
    """(repair 2, J2) the masseter's insertion found on the built jaw, not traced from a plate: "the angle and lower half of
    the lateral surface of the ramus" and "the upper half of the ramus and the lateral surface of the coronoid process"
    (p. 386), i.e. the ramus' lateral face below the notch. Side view (z, y), from the jaw's silhouette: the top side level
    with the notch's lowest point, the hind border, the lower border from the angle forward, and the front border (the
    ramus' anterior border, carried on down the oblique line to the lower border); each drawn in by `inset` mm. Ordered as
    area_patch() wants it: from the notch's front, back along the top, down the hind border, forward along the lower border,
    up the front border."""
    m, _, (zs, ys) = silhouette(bone, ("jaw",), sgn, lo=(-30, -110), hi=(90, 20), h=0.5)
    runs = []
    for j, y in enumerate(ys):
        idx = np.flatnonzero(m[:, j])
        runs.append(np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1) if len(idx) else [])
    two = [j for j in range(len(ys)) if len(runs[j]) >= 2 and ys[j] > -40]
    jn = min(two) - 1                                        # the notch's lowest row: the last row the ramus is one piece
    yn = ys[jn] - inset
    rows = [j for j in range(len(ys)) if ys[j] <= yn and len(runs[j])]
    hind = np.array([(zs[runs[j][0][0]] + inset, ys[j]) for j in rows])
    hz_min = hind[:, 0].min()
    hind = hind[hind[:, 0] < hz_min + 12.0]                 # the hind border down to the angle (below it the lower border)
    front = np.array([(zs[runs[j][0][-1]] - inset, ys[j]) for j in rows])
    # where the body begins (the front edge leaps forward), the anterior border is carried on straight, at its own slope above
    # (rows ascend in y: low down the body reaches far forward; going up, the front edge falls back onto the ramus)
    jump = np.flatnonzero(np.diff(front[:, 0]) < -4.0)
    k0 = int(jump.max()) + 1 if len(jump) else 0
    up_ = front[k0:]
    sel = up_[2:26] if len(up_) > 8 else up_
    a_, b_ = np.polyfit(sel[:, 1], sel[:, 0], 1) if len(sel) >= 3 else (0.0, up_[0, 0])
    ylow = ys[min(rows)]                                   # the lowest row of the jaw here
    # the lower border: for each z from the angle forward, the lowest jaw point (drawn up by inset)
    zf_low = a_ * (ylow + inset) + b_
    bz = np.arange(hind[0, 0], zf_low, 0.5)
    low = []
    for z in bz:
        i = int(np.argmin(np.abs(zs - z))); col = np.flatnonzero(m[i, :])
        if len(col):
            low.append((z, ys[col[0]] + inset))
    low = np.array(low)
    yl_front = low[-1, 1]
    fr_lo = np.array([(a_ * y + b_, y) for y in np.arange(yl_front, up_[0, 1], 0.5)])
    front_all = np.r_[fr_lo, up_]
    top = np.array([(z, yn) for z in np.arange(front_all[-1, 0], hind[-1, 0], -0.5)])
    hind_down = hind[::-1]
    poly = np.r_[top, hind_down, low, front_all]
    return resample(poly, 400)


def plate176(bone, sgn=1):
    """Fig. 176 in the head frame: the jaw's outline fitted to the built jaw's side silhouette (similarity, ICP from the
    plate's own registration of mandible4: condyle top, gonion, pogonion); returns the transform and the masseter's area"""
    jo = json.load(open(os.path.join(HERE, "traces", "mandible_fig176_outline.json")))
    mo = json.load(open(os.path.join(HERE, "traces", "muscle_fig176_masseter.json")))
    A = np.array(jo["outline_px"], float); A = np.c_[-A[:, 0], -A[:, 1]]              # plate (x right, y down) -> (z-like, y)
    _, edge, _ = silhouette(bone, ("jaw",), sgn, lo=(-10, -110), hi=(110, 10))
    s = 1 / 4.66
    T0 = (s, np.eye(2), edge.mean(0) - s * A.mean(0))
    T, d = icp(A, edge, T0)
    Mp = np.array(mo["outline_px"], float); Mp = np.c_[-Mp[:, 0], -Mp[:, 1]]
    return T, apply(T, Mp), d


# Fig. 382 is another skull than Fig. 188's: fitted on its six landmarks alone its bregma and glabella fall 11 to 15 mm from
# ours. It is fitted instead on the vault's whole outline (brow, crown, occiput: ICP onto the built skull's side silhouette)
# together with the points round the temporal fossa and the jaw (porion, frontomalare, coronion, mastoid tip, each weighted
# as 25 outline points); what each landmark then misses is reported.
REG382 = ("porion", "frontomalare", "coronion", "mastoid tip")


def plate382(bone):
    """Fig. 382 in the head frame: (transform, the muscle's outline (z, y), each landmark's miss, the trace)"""
    po = json.load(open(os.path.join(HERE, "traces", "muscle_fig382_temporalis.json")))
    L = po["landmarks_px"]
    model = model_landmarks(bone)
    flip = lambda P: np.c_[-np.asarray(P, float)[:, 0], -np.asarray(P, float)[:, 1]]
    names = [k for k in REG382 if k in model and k in L]
    A = flip([L[k] for k in names]); Bm = np.array([model[k] for k in names], float)
    V = flip(po["skull_outline_px"])
    _, edge, _ = silhouette(bone, ("skull",), 1, lo=(-110, -10), hi=(120, 130))
    edge = edge[(edge[:, 1] > 12) | (edge[:, 0] < -60)]
    tree = cKDTree(edge)
    T = similarity(A, Bm)
    for _ in range(40):
        d, i = tree.query(apply(T, V))
        k = d < np.percentile(d, 90)
        T = similarity(np.r_[V[k], np.repeat(A, 25, 0)], np.r_[edge[i[k]], np.repeat(Bm, 25, 0)])
    dv, _ = tree.query(apply(T, V))
    res = {k: float(np.linalg.norm(apply(T, flip([L[k]]))[0] - np.array(model[k], float))) for k in L if k in model}
    res["vault outline mean"] = float(dv.mean()); res["vault outline max"] = float(dv.max())
    return T, apply(T, flip(po["outline_px"])), res, po


def model_landmarks(bone, sgn=1):
    """(z, y) of the landmarks Fig. 382 shows, on the built bone (left side): porion is the frame's origin"""
    out = {"porion": (0.0, 0.0), "mastoid tip": (TP.MASTOID_TIP[2], TP.MASTOID_TIP[1]),
           "frontomalare": (SK2.ZYG_SIDE[0][0], SK2.ZYG_SIDE[0][1])}
    # bregma, lambda and glabella: Fig. 188's, in the frame the skull's outline was fitted to (plates.side_frame)
    import plates
    Fr = plates.side_frame(plates.traces()["side_silhouette_px"])
    for k in ("bregma", "lambda", "glabella"):
        out[k] = tuple(Fr.mm(plates.SIDE[k])[0])
    # coronion: the coronoid's highest point
    P = cor_apex(bone, sgn)
    out["coronion"] = (P[2], P[1])
    return out


def cor_apex(bone, sgn):
    zs = np.arange(30, 52, 0.25); xs = np.arange(30, 52, 0.25)
    Zg, Xg = np.meshgrid(zs, xs, indexing="ij")
    for y in np.arange(-2.0, -14, -0.1):
        P = np.c_[sgn * Xg.ravel(), np.full(Zg.size, y), Zg.ravel()]
        inb = bone.d(P, ("jaw",)) < 0
        if inb.any():
            return P[inb].mean(0)
    return None


def warp_plate(img, T, zr, yr, px_per_mm=4.0, origin=(0, 0)):
    """the plate image (PIL) drawn in the head frame's side view: (z from zr[1] on the left to zr[0] on the right, as the
    plates face, y up), at px_per_mm; T maps plate pixels (as (-x, -y)) to (z, y)"""
    from PIL import Image
    s, R, t = T
    W = int((zr[1] - zr[0]) * px_per_mm); Hh = int((yr[1] - yr[0]) * px_per_mm)
    u, v = np.meshgrid(np.arange(W), np.arange(Hh))
    z = zr[1] - u / px_per_mm; y = yr[1] - v / px_per_mm
    Q = np.c_[z.ravel(), y.ravel()] - t
    A = (Q @ R) / s                                    # inverse similarity: (-x, -y) of the plate
    px, py = -A[:, 0] - origin[0], -A[:, 1] - origin[1]
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    out = np.stack([ndimage.map_coordinates(a[..., c], [py, px], order=1, cval=255) for c in range(3)], -1)
    return Image.fromarray(out.reshape(Hh, W, 3).astype(np.uint8))


def to_px(P, zr, yr, k):
    P = np.asarray(P, float)
    return np.c_[(zr[1] - P[:, 0]) * k, (yr[1] - P[:, 1]) * k]


# ====================================================================== marks on the built bone
def side_hit(bone, z, y, sgn, which=("skull",), x0=85.0, x1=15.0, through_plates=False):
    """the bone's surface met coming in from the side at (z, y): (x, y, z) or nan. through_plates: a thin plate with free
    space within 14 mm behind it (the arch, the cheek bone) is passed through, and the floor behind it is returned."""
    z = np.atleast_1d(np.asarray(z, float)); y = np.atleast_1d(np.asarray(y, float))
    st = np.c_[np.full(len(z), sgn * x0), y, z]
    P = bone.ray(st, (-sgn * 0.25, 0, 0), which, n=int((x0 - x1) / 0.25))
    if through_plates:          # (only the cheek bone's plate, in front: elsewhere the next free space is the braincase's)
        for i in np.where(~np.isnan(P[:, 0]) & (P[:, 2] > 46.0) & (P[:, 1] < 34.0) & (np.abs(P[:, 0]) > 52.0))[0]:
            for dx in np.arange(2.0, 14.0, 0.5):
                q = P[i] - np.array([sgn * dx, 0, 0])
                if bone.d(q, which)[0] > 1.0:
                    r = bone.ray(q, (-sgn * 0.25, 0, 0), which, n=int(max(abs(q[0]) - x1, 1) / 0.25))[0]
                    P[i] = r
                    break
    return P


def lower_border(bone, sgn, zs, xmin=48.0, ylo=-26.0, yhi=6.0):
    """the arch's (and the cheek bone's, and the maxilla's zygomatic process's) lowest bone at each z: (x, y, z)"""
    out = []
    xs = np.arange(xmin, 72, 0.25); ys = np.arange(ylo, yhi, 0.25)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    for z in zs:
        P = np.c_[sgn * X.ravel(), Y.ravel(), np.full(X.size, z)]
        ins = (bone.d(P, ("skull",)) < 0).reshape(X.shape)
        if not ins.any():
            out.append((np.nan,) * 3); continue
        Ym = np.where(ins, Y, 99.0)
        j = np.unravel_index(np.argmin(Ym), Ym.shape)
        row = ins[:, j[1]]
        xm = X[row, j[1]].mean()
        out.append((sgn * xm, Y[j], z))
    return np.array(out)


def jaw_section(bone, sgn, y, zlo=-5.0, zhi=60.0, xlo=26.0, xhi=62.0, h=0.25):
    """the jaw's section at height y (left half): mask over (x, z)"""
    xs = np.arange(xlo, xhi, h); zs = np.arange(zlo, zhi, h)
    X, Z = np.meshgrid(xs, zs, indexing="ij")
    P = np.c_[sgn * X.ravel(), np.full(X.size, y), Z.ravel()]
    return (bone.d(P, ("jaw",)) < 0).reshape(X.shape), X, Z


def coronoid_line(bone, sgn):
    """the coronoid's border as one line: up the ramus's front border from beside the last molar to the apex, and down its
    hind border into the notch (Gray p. 174; Fig. 177). Points (x, y, z) on the bone."""
    front, back = [], []
    for y in np.arange(-50.0, -7.4, 1.0):
        m, X, Z = jaw_section(bone, sgn, y, zlo=24.0)
        if not m.any():
            continue
        zz = np.where(m, Z, -99); i = np.unravel_index(np.argmax(zz), zz.shape)
        front.append((sgn * X[i], y, Z[i]))
    ap = cor_apex(bone, sgn)
    for y in np.arange(-8.0, -17.5, -1.0):
        m, X, Z = jaw_section(bone, sgn, y, zlo=26.0)
        if not m.any():
            continue
        zz = np.where(m, Z, 99); i = np.unravel_index(np.argmin(zz), zz.shape)
        back.append((sgn * X[i], y, Z[i]))
    return np.array(front + [tuple(ap)] + back), len(front)


def face_hit(bone, y, z, sgn, medial):
    """the jaw's medial (or lateral) face at (y, z)"""
    y = np.atleast_1d(y).astype(float); z = np.atleast_1d(z).astype(float)
    if medial:
        st = np.c_[np.full(len(y), sgn * 20.0), y, z]; step = (sgn * 0.2, 0, 0)
    else:
        st = np.c_[np.full(len(y), sgn * 72.0), y, z]; step = (-sgn * 0.2, 0, 0)
    return bone.ray(st, step, ("jaw",), n=300)


def poly_exit(poly, c, ang):
    """the largest distance from c along the direction ang (radians) at which the ray leaves the closed polygon (z, y); nan if it never enters"""
    P = np.asarray(poly, float); Q = np.roll(P, -1, 0)
    d = np.array([np.cos(ang), np.sin(ang)])
    e = Q - P
    den = d[0] * e[:, 1] - d[1] * e[:, 0]
    w = P - c
    with np.errstate(divide="ignore", invalid="ignore"):
        r = (w[:, 0] * e[:, 1] - w[:, 1] * e[:, 0]) / den
        u = (w[:, 0] * d[1] - w[:, 1] * d[0]) / den
    ok = (np.abs(den) > 1e-12) & (u >= 0) & (u <= 1) & (r > 0)
    return r[ok].max() if ok.any() else np.nan


def inside(poly, pts):
    """points (z, y) inside a closed polygon (even-odd rule)"""
    P = np.asarray(poly, float); Q = np.roll(P, -1, 0); x, y = np.asarray(pts, float).T
    out = np.zeros(len(x), bool)
    for (x0, y0), (x1, y1) in zip(P, Q):
        c = ((y0 > y) != (y1 > y))
        with np.errstate(divide="ignore", invalid="ignore"):
            xc = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
        out ^= c & (x < xc)
    return out


# ====================================================================== the temporalis
def fossa_outline():
    """the temporal fossa as the built skull's own marks bound it, side view (z, y), closed: the frontal bone's temporal crest
    and the inferior temporal line ("the upper limit of the muscular origin of the Temporalis", p. 134), the supramastoid
    crest ("limits the origin of the Temporalis muscle", p. 139), the level of the arch, and the cheek bone's hind border
    (the fossa "except that portion of it which is formed by the zygomatic bone", p. 386)"""
    crest = [(z, y) for z, y in TP.CREST if z < -4][::-1]
    bottom = [(0.0, 3.6), (10.0, 2.6), (20.0, 1.5), (32.0, 0.5), (44.0, 0.5), (52.0, 2.5)]
    return np.array(list(TP.FRONTAL_CREST) + list(TP.LINE_LOWER) + crest + bottom + list(SK2.PILLAR_HIND), float)


def arch_frame(bone, sgn, z):
    """at depth z: the arch's top and lowest y (lateral bone beyond x 57), and its inner face's x at mid height"""
    lb = lower_border(bone, sgn, [z], xmin=57.0, ylo=-22.0, yhi=10.0)[0]
    ys = np.arange(lb[1], 10.0, 0.25)
    xs = np.arange(57.0, 70.0, 0.5)
    Y, X = np.meshgrid(ys, xs, indexing="ij")
    ins = (bone.d(np.c_[sgn * X.ravel(), Y.ravel(), np.full(X.size, z)], ("skull",)) < 0).reshape(Y.shape)
    rows = ins.any(1)
    top = ys[rows].max() if rows.any() else lb[1]
    mid = 0.5 * (top + lb[1])
    p = bone.ray(np.array([[sgn * 48.0, mid, z]]), (sgn * 0.2, 0, 0), ("skull",), n=150)[0]
    return lb[1], top, (p[0] if not np.isnan(p[0]) else sgn * 60.0)


def temporalis(bone, sgn, seed, plate_outline, nt=80, nw=7, ns1=40, ns2=26, log=print):
    """the temporalis of one side as a fibre sheet (Sheet), with its attachment points"""
    rng = np.random.default_rng(seed)
    ap = cor_apex(bone, sgn)
    C = np.array([ap[2], ap[1]])
    fos = fossa_outline()
    # the origin's margin: within the fossa the skull's marks allow and within the plate's outline, seen from the apex
    angs = np.radians(np.arange(15.0, 185.0, 0.25))
    rf = np.array([poly_exit(fos, C, a) for a in angs])
    # (repair 2, J1: the fossa wins. The origin is the whole temporal fossa of this skull, edge to edge: up to the inferior
    # temporal line and the supramastoid crest, forward to the frontal and cheek bones' temporal surfaces, down to the arch's
    # level (Gray p. 386: "the whole of the temporal fossa"; p. 134: the line "indicates the upper limit of the muscular
    # origin"). Fig. 382 is only a likeness check now; repair 1 took its outline and left bone bare inside the line.)
    ok = ~np.isnan(rf)
    r = rf[ok]; a = angs[ok]
    r = ndimage.gaussian_filter1d(r, 0.6)
    # the margin on the line, never a ruled one: drawn in by an uneven 0 to 0.3 mm (a gap of at most 1 mm on the bone)
    r = r - (0.15 + noise1(len(r), seed + 7, 0.15, 0.08) + noise1(len(r), seed + 8, 0.05, 0.04))
    G2 = np.c_[C[0] + r * np.cos(a), C[1] + r * np.sin(a)]                       # front (small angle) first
    G2 = resample(G2, nt)
    # each margin point on the bone: the fossa's floor (behind the cheek bone, the floor behind the plate)
    G3 = side_hit(bone, G2[:, 0], G2[:, 1], sgn, through_plates=True)
    for i in np.where(np.isnan(G3[:, 0]))[0]:
        G3[i] = G3[i - 1] if i else G3[i + 1]
    t = np.linspace(0, 1, nt)
    # the arch along its length: lowest and top y, inner face x
    za = np.arange(0.0, 60.0, 1.0)
    AF = np.array([arch_frame(bone, sgn, z) for z in za])
    # where each fibre passes the arch: medial to it, at its mid height, off the fossa's floor by no more than the muscle's
    # own thickness (where the floor falls away, over the infratemporal fossa, the fibre leaves it)
    Tcap = np.interp(t, [0, 0.15, 0.45, 0.8, 1.0], [7.0, 11.5, 10.5, 7.0, 4.5]) * (1 + rng.normal(0, 0.04, nt))
    zv = 50.0 - 24.0 * t + rng.normal(0, 0.3, nt)
    V = np.zeros((nt, 3)); room = np.zeros(nt); xin = np.zeros(nt)
    for i, z in enumerate(zv):
        lb, top, xi = [np.interp(z, za, AF[:, k]) for k in range(3)]
        yv = 0.5 * (lb + top)
        fl = bone.ray(np.array([[xi - sgn * 1.0, yv, z]]), (-sgn * 0.25, 0, 0), ("skull",), n=120)[0]
        xf = abs(fl[0]) if not np.isnan(fl[0]) else 0.0
        xv = max(xf + 0.8, abs(xi) - 2 * CLEAR - 0.6 - Tcap[i])
        V[i] = (sgn * xv, yv, z); xin[i] = xi; room[i] = abs(xi) - xv - 2 * CLEAR - 0.4
    # where each fibre ends: the coronoid's border, apex and inner face (Gray p. 386, Fig. 177)
    K, nf = coronoid_line(bone, sgn)
    Ls = np.r_[0, np.cumsum(np.linalg.norm(np.diff(K, axis=0), axis=1))]; Ls /= Ls[-1]
    ua = Ls[nf]
    u = np.interp(t, [0.0, 0.28, 0.62, 1.0], [0.0, 0.93 * ua, ua + 0.3 * (1 - ua), 1.0])
    Kt = np.column_stack([np.interp(u, Ls, K[:, i]) for i in range(3)])
    # into the inner face from the border: back from the front border, down from the apex, forward from the hind border
    dy = np.interp(u, [0, 0.8 * ua, ua, 1], [-0.25, -0.3, -1.0, -0.45]); dz = np.interp(u, [0, 0.8 * ua, ua, 1], [-1.0, -1.0, -0.2, 1.0])
    nn = np.hypot(dy, dz); dy /= nn; dz /= nn
    ws = np.linspace(0, 1, nw)
    I = np.zeros((nt, nw, 3))
    for j, w in enumerate(ws):
        dl = (1 - w) * 7.0
        if dl < 0.3:
            I[:, j] = Kt
        else:
            I[:, j] = face_hit(bone, Kt[:, 1] + dl * dy, Kt[:, 2] + dl * dz, sgn, medial=True)
            bad = np.isnan(I[:, j, 0]); I[bad, j] = Kt[bad]
    # the deep fibres: laid on the fossa's floor from the margin down to the arch's level (each point the floor met from the side,
    # from inside the arch where the arch is in the way), then a taut tendon to the inner face
    ns = ns1 + ns2 - 1
    s1 = np.linspace(0, 1, ns1); s2 = np.linspace(0, 1, ns2)
    # side view (z, y): each fibre radiates from the coronoid as Fig. 382 draws it: the front ones nearly straight down, the
    # middle ones curving, the hind ones running forward nearly level above the ear and turning down only toward the arch
    # (a quadratic curve from the margin through a guide point at 60 % of the way forward, lowered by beta of the drop)
    beta = np.interp(t, [0.0, 0.25, 0.5, 0.75, 1.0], BETA_TEM)[:, None]
    P1 = np.c_[G2[:, 0] + 0.6 * (V[:, 2] - G2[:, 0]), G2[:, 1] + beta[:, 0] * (V[:, 1] - G2[:, 1])]
    S1 = s1[None, :, None]
    F2 = (1 - S1) ** 2 * G2[:, None, :] + 2 * S1 * (1 - S1) * P1[:, None, :] + S1 ** 2 * V[:, None, [2, 1]]
    fz, fy = F2[..., 0].ravel(), F2[..., 1].ravel()
    # (the hind fibres run forward over the arch's root, not across it: Fig. 382 draws them level above the ear, turning down
    # only in front of the articular tubercle)
    sv1 = np.broadcast_to(s1[None, :], F2.shape[:2]).ravel()
    fy = np.where(fz < 25.0, np.maximum(fy, 4.5 * (1 - smoothstep((fz - 21.0) / 5.0)) + fy * smoothstep((fz - 21.0) / 5.0)), fy)
    top = np.interp(fz, za, AF[:, 1]); xi = np.interp(fz, za, AF[:, 2])
    under = (fy < top + 2.5) & (fz > 25.0) & (fz < 58.0)
    x0 = np.where(under, np.abs(xi) - 1.0, 85.0)
    st = np.c_[sgn * x0, fy, fz]
    F3 = bone.ray(st, (-sgn * 0.2, 0, 0), ("skull",), n=500)
    fr = (fz > 46.0) & (fy < 34.0) & ~under
    if fr.any():
        F3[fr] = side_hit(bone, fz[fr], fy[fr], sgn, through_plates=True)
    F3 = F3.reshape(nt, ns1, 3)
    for i in range(nt):                                            # (no floor: carried straight on to the via point)
        bad = np.isnan(F3[i, :, 0]) | (np.abs(F3[i, :, 0]) < np.abs(V[i, 0]) - 0.5)
        if bad.any():
            ok = np.where(~bad)[0]
            for c in range(3):
                F3[i, bad, c] = np.interp(np.where(bad)[0], np.r_[ok, ns1 - 1], np.r_[F3[i, ok, c], V[i, c]])
    F3 = ndimage.gaussian_filter1d(F3, 1.0, axis=1); F3[:, 0] = G3; F3[:, -1] = V
    Pd = np.zeros((nt, ns, 3))
    Pd[:, :ns1] = F3
    Pd[:, ns1 - 1:] = V[:, None] + (I[:, 0] - V)[:, None] * s2[None, :, None]
    pin = np.zeros((nt, ns), bool); pin[:, 0] = pin[:, -1] = True; pin[:, ns1 - 1] = True
    tgt = np.zeros((nt, ns)); tgt[:, ns1 - 1:] = CLEAR + 0.1
    frz = np.zeros((nt, ns), bool); frz[:, :ns1] = True
    Pd = wrap(Pd, bone, ("skull", "jaw"), tgt, pin | frz, rounds=150, k=0.4)                 # the tendon: taut, off the bone
    Pd = wrap(Pd, bone, ("skull", "jaw"), 0.0, pin, rounds=12, k=0.05)                       # nothing of the floor inside the bone
    # thickness: thin at the line, full low in the fossa, as much as the room inside the arch allows (Gray gives none)
    Tm = np.minimum(Tcap, np.maximum(room, 2.0))
    sall = np.linspace(0, 1, ns); sv = (ns1 - 1) / (ns - 1)
    # a belly: thin at the line, swelling steadily down the fossa to its thickest above the arch (no flat stretch)
    prof = np.where(sall <= sv, 0.22 + 0.78 * smoothstep(sall / (0.97 * sv)) ** 1.25, 1.0 - 0.55 * smoothstep((sall - sv) / (1 - sv)))
    T = Tm[:, None] * prof[None, :]
    # the outward direction: the bone's on the floor; carried down unchanged below the arch
    nrm = bone.grad(Pd[:, :ns1].reshape(-1, 3), ("skull",)).reshape(nt, ns1, 3)
    nrm = ndimage.gaussian_filter1d(nrm, 2, axis=1)
    nrm = np.concatenate([nrm, np.repeat(nrm[:, -1:], ns - ns1, 1)], 1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    P = np.zeros((nt, nw, ns, 3))
    endb = smoothstep((sall - sv) / (1 - sv) * 1.4 - 0.4)
    for j, w in enumerate(ws):
        Q = Pd + (w * T)[..., None] * nrm
        Q = Q + (I[:, j] - Q[:, -1])[:, None, :] * endb[None, :, None]
        P[:, j] = Q
    archzone = lambda Q: (Q[:, 2] > 21.0) & (Q[:, 2] < 58.0) & (Q[:, 1] < np.interp(Q[:, 2], za, AF[:, 1]) + 2.5) & (np.abs(Q[:, 0]) > 50.0)
    # the outer layers kept off the bone and the arch (pushed medially at the arch: the muscle passes deep to it)
    for j in range(1, nw):
        pinj = np.zeros((nt, ns), bool); pinj[:, 0] = pinj[:, -1] = True
        P[:, j] = wrap(P[:, j], bone, ("skull", "jaw"), CLEAR + 0.15, pinj, rounds=60, k=0.08, push_dir=(-sgn, 0, 0), zone=archzone)
    # tendon: the central fibres' superficial layers are tendinous far up into the fan (the white of Fig. 382); the front band
    # is fleshy almost to the bone, the hind fibres only at their turn
    Lt = 0.6 * np.exp(-((t - 0.45) / 0.28) ** 2)
    Wg = ws ** 0.8
    st = sv + 0.12 - Lt[:, None] * Wg[None, :] + noise1(nt, seed + 5, 0.18, 0.05)[:, None]
    front = smoothstep((0.22 - t) / 0.12)[:, None]                 # the fleshy front band, blended in (no step)
    st = st + (np.maximum(st, 0.9 - 2.0 * t[:, None]) - st) * front
    tend = smoothstep((sall[None, None, :] - st[..., None]) / 0.07)
    tspec = dict(st=st, side=1, width=0.06, jitter=0.05, tip=0.1, tongue=0.06)
    info = dict(margin=G2, V=V, I=I, K=K, room=room, Tm=Tm, sv=sv, apex=ap)
    log("temporalis %s: %d fibres x %d layers, margin %d pts, thickness %.1f..%.1f mm, room at the arch %.1f..%.1f" % (
        "L" if sgn > 0 else "R", nt, nw, len(G2), Tm.min(), Tm.max(), room.min(), room.max()))
    sh = Sheet("temporalis", P, tend, seed=seed)
    sh.tendon_spec = tspec
    sh.info = info
    fz = fossa_outline()
    po_ = np.asarray(plate_outline, float)
    sh.origin_ok = lambda Q: (inside(fz, Q[:, [2, 1]]) | inside(po_, Q[:, [2, 1]])) & ~archzone(Q)
    sh.origin = (slice(None), slice(None), slice(0, ns1))     # where the fibres may lie on bone (deep layer), and the ends
    return sh


# ====================================================================== from fibres to a solid with a fibre texture
def fascicles(seed, nt_mm, n_extra=0):
    """the boundaries between fascicles across a sheet: t positions (0..1), each with its depth (mm), half-width (mm) and
    where along the fibres it runs out. Widths of 1.4 to 6 mm, uneven (lognormal), as dissections show them."""
    rng = np.random.default_rng(seed)
    pos = []; x = rng.uniform(0.5, 2.0)
    while x < nt_mm - 1.0:
        pos.append(x); x += float(np.clip(rng.lognormal(np.log(2.8), 0.45), 1.4, 6.0))
    pos = np.array(pos) / nt_mm
    k = len(pos)
    return dict(t=pos, depth=rng.uniform(0.18, 0.5, k), hw=rng.uniform(0.28, 0.55, k),
                s0=np.where(rng.random(k) < 0.3, rng.uniform(0.05, 0.4, k), 0.0),
                s1=np.where(rng.random(k) < 0.3, rng.uniform(0.6, 0.95, k), 1.0),
                wave=rng.uniform(0.002, 0.008, k), ph=rng.uniform(0, 2 * np.pi, k), shade=rng.uniform(0.86, 1.1, k + 1),
                crown=rng.uniform(0.8, 1.25, k + 1))


def field(grid, X, vol, sigma=0.6):
    """the samples X (k, 3), each standing for vol (k,) mm3 of muscle, as a field on the grid: each sample's volume shared
    among its 8 neighbouring cells (trilinear), the cells' filled fraction blurred by sigma mm, read off as a distance (mm,
    negative inside) about the half-full level. Written so the surface carries no trace of the grid. (T-muscle-1 marked cells
    full or empty; a later try took the distance to the nearest sample: both alias the samples' spacing against the grid's,
    and the beat showed on every gently sloping face as rings like wood grain, 2-3 mm apart: T-muscle-2, G2.)"""
    q = (X - grid.lo) / grid.h
    i0 = np.floor(q).astype(np.int64); fr = (q - i0).astype(np.float32)
    n = np.array(grid.n)
    occ = np.zeros(int(np.prod(n)), np.float64)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                I = i0 + np.array([dx, dy, dz])
                w = (fr[:, 0] if dx else 1 - fr[:, 0]) * (fr[:, 1] if dy else 1 - fr[:, 1]) * (fr[:, 2] if dz else 1 - fr[:, 2])
                ok = np.all((I >= 0) & (I < n), axis=1)
                occ += np.bincount(np.ravel_multi_index(I[ok].T, grid.n), weights=(w * vol)[ok], minlength=occ.size)
    G = ndimage.gaussian_filter(occ.reshape(grid.n) / grid.h ** 3, sigma / grid.h)
    # read off through the inverse of the blurred step (exact for a flat face), so that the field is a distance out to 3 mm
    # and the clearances to other muscles taken from it are true
    from scipy.special import ndtri
    return np.clip(-sigma * ndtri(np.clip(G, 1e-7, 1 - 1e-7)), -3.0, 3.0).astype(np.float32)


def sample_volumes(X):
    """the volume (mm3) each sample of a filled-in sheet (nt, nw, ns, 3) stands for: the parallelepiped of its three steps"""
    a = np.gradient(X, axis=0); b = np.gradient(X, axis=1); c = np.gradient(X, axis=2)
    v = np.abs((np.cross(a, b) * c).sum(-1))
    # where the sheet is twisted (its layers running sideways, along its width) the cell is nearly flat though its samples
    # spread; it still stands for at least half the box of its three steps (else its corner thins out of the field)
    v = np.maximum(v, 0.5 * np.linalg.norm(a, axis=-1) * np.linalg.norm(b, axis=-1) * np.linalg.norm(c, axis=-1))
    for ax in range(3):                                   # the samples on a face stand for half a cell across it
        sl = [slice(None)] * 3; sl[ax] = 0; v[tuple(sl)] *= 0.5
        sl[ax] = -1; v[tuple(sl)] *= 0.5
    return v


def dense_samples(X, step=0.45, cap=8):
    """the filled-in sheet's samples with their volumes, and where neighbouring samples are still more than `step` apart
    (where the fibres fan out, up to 20 mm), each such sample split into a small grid over its own cell, its volume shared:
    sparse samples read through the blur as a cloud with holes, and the muscle's thin corners went missing (T-muscle-2)"""
    vol = sample_volumes(X).ravel(); sh = X.shape[:3]
    G = [np.gradient(X, axis=a).reshape(-1, 3) if sh[a] > 1 else np.zeros((X[..., 0].size, 3)) for a in range(3)]
    n = np.stack([np.clip(np.ceil(np.linalg.norm(g, axis=1) / step), 1, cap) for g in G], 1).astype(np.int64)
    idx = np.indices(sh).reshape(3, -1).T
    for a in range(3):                                     # a face sample: no split across that face
        n[(idx[:, a] == 0) | (idx[:, a] == sh[a] - 1), a] = 1
    Xf = X.reshape(-1, 3); one = n.prod(1) == 1
    xs, vs = [Xf[one]], [vol[one]]
    sp = np.flatnonzero(~one)
    if len(sp):
        combos, inv = np.unique(n[sp], axis=0, return_inverse=True)
        for ci, c in enumerate(combos):
            ii = sp[inv.ravel() == ci]
            o = np.stack(np.meshgrid(*[(np.arange(k) + 0.5) / k - 0.5 for k in c], indexing="ij"), -1).reshape(-1, 3)
            P = Xf[ii][:, None, :] + sum(o[None, :, a, None] * G[a][ii][:, None, :] for a in range(3))
            xs.append(P.reshape(-1, 3)); vs.append(np.repeat(vol[ii] / len(o), len(o)))
    return np.concatenate(xs), np.concatenate(vs)


def solid(name, sheets, grid, bone, sgn, attach, others=(), teethP=None, log=print):
    """the sheets as one smooth field on the grid, held off the bone (flush where attached), the teeth and the other
    muscles; and the samples the mesh's vertices take their fibre coordinates and tendon from. (The fibre relief is not in
    the field: it is laid on the mesh afterwards, finer than the grid can hold; see surface().)"""
    D = np.full(grid.n, 3.0, np.float32)
    keepX = []
    for sh in sheets:
        P = sh.P
        acr = np.linalg.norm(np.diff(P[:, -1], axis=0), axis=-1).sum(0)            # (ns,) the outer layer's width across
        fas = fascicles(sh.seed, float(acr.max()))
        sh.set_tendon(fas)
        X, T, tt, ww, ss = sh.fine()
        Dk = field(grid, *dense_samples(X))
        # a soft union (k = 1.2 mm): where two sheets lie within about half a millimetre of each other they are one surface,
        # not two with a crease between (repair F1: the deep and superficial masseter met in folds there)
        hk = np.clip(1.2 - np.abs(D - Dk), 0, None) / 1.2
        D = np.minimum(D, Dk) - hk * hk * 0.3
        sh.fas = fas
        keepX.append((X.reshape(-1, 3), np.c_[tt.ravel(), ww.ravel(), ss.ravel(), T.ravel()], sh))
        log("  %s: %d samples, %d fascicles" % (sh.name, X.size // 3, len(fas["t"]) + 1))
    # held off the bone except at the attachments (there flush), off the teeth and the muscles built before
    Ap = np.concatenate([a for a in attach])
    near = D < 2.0
    Pn, In = grid.points(near)
    dB = bone.d(Pn, ("skull", "jaw"))
    df, _ = cKDTree(Ap).query(Pn, distance_upper_bound=6.0)
    c = CLEAR * smoothstep((df - 0.6) / 1.0)
    v = D[tuple(In.T)]
    v = np.maximum(v, c - dB)
    if teethP is not None:
        dt, _ = cKDTree(teethP).query(Pn, distance_upper_bound=5.0)
        v = np.maximum(v, CLEAR + 0.1 - dt)
    for o in others:
        v = np.maximum(v, CLEAR + 0.35 - o(Pn))
    D[tuple(In.T)] = v
    return D, keepX


def blur3d(v, x, sigma, h=0.4):
    """a per-vertex value blurred in space (gaussian, sigma mm), across sheets that lie close without sharing the mesh's
    edges (repair F1: the deep and superficial masseter, one over the other, showed their own colours side by side)"""
    x = np.asarray(x, np.float64); one = x.ndim == 1; X = x[:, None] if one else x
    lo = v.min(0) - 4 * sigma; I = np.round((v - lo) / h).astype(np.int64); n = tuple(I.max(0) + 4)
    flat = np.ravel_multi_index(I.T, n)
    W = np.bincount(flat, minlength=int(np.prod(n))).astype(np.float32).reshape(n)
    W = ndimage.gaussian_filter(W, sigma / h)
    out = np.empty_like(X)
    for c in range(X.shape[1]):
        G = np.bincount(flat, weights=X[:, c], minlength=int(np.prod(n))).astype(np.float32).reshape(n)
        G = ndimage.gaussian_filter(G, sigma / h)
        out[:, c] = ndimage.map_coordinates(G, ((v - lo) / h).T, order=1) / np.maximum(ndimage.map_coordinates(W, ((v - lo) / h).T, order=1), 1e-9)
    return out[:, 0] if one else out


def smooth_on_mesh(v, f, x, rounds, same=None):
    """a per-vertex value averaged with its neighbours, `rounds` times (about rounds * 0.25 mm wide); same: per-vertex labels,
    averaged only within a label"""
    from scipy import sparse
    n = len(v); e = np.r_[f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]
    if same is not None:
        e = e[same[e[:, 0]] == same[e[:, 1]]]
    Adj = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr(); Adj = ((Adj + Adj.T) > 0).astype(np.float32)
    deg = np.maximum(np.asarray(Adj.sum(1)).ravel(), 1); x = np.asarray(x, np.float64)
    Adj = (sparse.diags(1.0 / deg) @ Adj).tocsr()
    for _ in range(int(rounds)):
        x = 0.5 * x + 0.5 * (Adj @ x)
    return x


def local_linear(v, n, x, same, k=48, sigma=1.0):
    """a per-vertex value replaced by a local linear fit over its neighbourhood (gaussian, sigma mm; same label, same face):
    exact for a value that runs linearly over the surface, unlike averaging over the mesh's edges, which bends it wherever
    the triangles' sizes change (the marching grid's pattern, every 0.5 mm) and drew that pattern into every groove"""
    tree = cKDTree(v); out = np.empty(len(v))
    for a in range(0, len(v), 50000):
        b_ = min(a + 50000, len(v))
        d, j = tree.query(v[a:b_], k)
        e1 = np.cross(n[a:b_], [0.577, 0.577, 0.577]); e1 /= np.maximum(np.linalg.norm(e1, axis=1, keepdims=True), 1e-9)
        e2 = np.cross(n[a:b_], e1)
        Dv = v[j] - v[a:b_, None, :]
        X = np.stack([np.ones(d.shape), (Dv * e1[:, None]).sum(-1), (Dv * e2[:, None]).sum(-1)], -1)
        w = np.exp(-0.5 * (d / sigma) ** 2) * ((n[j] * n[a:b_, None]).sum(-1) > 0.5) * (same[j] == same[a:b_, None])
        XtW = X * w[..., None]
        M_ = np.einsum("nki,nkj->nij", XtW, X) + 1e-6 * np.eye(3)
        r = np.einsum("nki,nk->ni", XtW, x[j])
        out[a:b_] = np.linalg.solve(M_, r[..., None])[:, 0, 0]
    return out


def to_mesh(D, grid, keepX, rounds=4):
    """the field's surface (largest piece), smoothed, and each vertex's fibre coordinates (t across, s along, layer), part and
    the sheet's own tendon share, each a weighted mean of the nearest samples of the vertex's own part (no staircase)"""
    Dp = np.pad(D, 1, constant_values=3.0)
    v, f = sdf.mesh(Dp, grid.lo - grid.h, grid.h)
    parts = sdf.components(v, f)
    v, f = parts[0]
    v = sdf.taubin(v, f, rounds)
    allX = np.concatenate([k[0] for k in keepX]); allA = np.concatenate([k[1] for k in keepX])
    who = np.concatenate([np.full(len(k[0]), i) for i, k in enumerate(keepX)])
    sub = np.arange(0, len(allX), max(1, len(allX) // 3_000_000))
    tree = cKDTree(allX[sub]); d, i = tree.query(v, k=8, workers=2); i = sub[i]
    W = who[i[:, 0]]
    w = (1.0 / (d + 0.05) ** 2) * (who[i] == W[:, None])
    A = (w[..., None] * allA[i]).sum(1) / w.sum(1, keepdims=True)
    return v, f, dict(tendon=A[:, 3].astype(np.float32), layer=A[:, 1].astype(np.float32),
                      t=A[:, 0].astype(np.float32), s=A[:, 2].astype(np.float32), part=W.astype(np.int8))


def attachments(sh, bone, which_o, which_i, lie=None, near=0.45):
    """the attachment footprints of a sheet as points: where its fibres begin and end, and where its deep layer lies on the
    bone (lie: index range along the fibres) -- each kept only where it is on that bone"""
    X, T, tt, ww, ss = sh.fine()
    o = X[:, :, 0].reshape(-1, 3); i = X[:, :, -1].reshape(-1, 3)
    if lie is not None:
        L = X[:, 0][ss[:, 0] <= lie].reshape(-1, 3)
        o = np.r_[o, L]
    o = o[bone.d(o, which_o) < near]; i = i[bone.d(i, which_i) < near]
    if getattr(sh, "origin_ok", None) is not None:
        o = o[sh.origin_ok(o)]
    return o, i


def grid_for(name, sgn):
    if name == "temporalis":
        lo, hi = np.array([30.0, -56.0, -50.0]), np.array([84.0, 100.0, 82.0])
    else:
        lo, hi = np.array([30.0, -84.0, -4.0]), np.array([76.0, 8.0, 74.0])
    if sgn < 0:
        lo, hi = np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]])
    return Grid(lo, hi)


def teeth_points(info):
    import teeth
    P = []
    for upper in (True, False):
        for nm, sd, w, f in teeth.stand(info["sockU"] if upper else info["sockL"], upper, h=0.25):
            P.append(w)
    return np.concatenate(P)


def largest_piece(v, f, A):
    """the mesh's largest connected piece only (repair 2, H2: no loose slivers), its per-vertex attributes with it"""
    from scipy import sparse
    from scipy.sparse.csgraph import connected_components
    n = len(v); e = np.r_[f[:, [0, 1]], f[:, [1, 2]]]
    k, lab = connected_components(sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)), directed=False)
    if k == 1:
        return v, f, A, 1
    keep = lab == np.argmax(np.bincount(lab)); idx = -np.ones(n, np.int64); idx[keep] = np.arange(keep.sum())
    f2 = idx[f]; f2 = f2[(f2 >= 0).all(1)]
    A2 = {q: (x[keep] if hasattr(x, "__len__") and not isinstance(x, (str, bytes)) and np.ndim(x) >= 1 and len(x) == n else x)
          for q, x in A.items()}
    return v[keep], f2, A2, k


def tidy_edges(v, f, A, bone, maxmove=0.2, rounds=25):
    """the line where a muscle meets its bone, smoothed (repair 2, H3): near that line (within 0.6 mm of the bone, on an
    attached margin) the height over the bone is eased along the surface and the vertices slid along it, so the line runs
    clean, not in stairs; no vertex moves more than maxmove mm, and nothing comes nearer the bone than it was off the
    attachments"""
    from scipy import sparse
    n = len(v); e = np.r_[f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]
    Adj = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr(); Adj = ((Adj + Adj.T) > 0).astype(np.float32)
    Adj = (sparse.diags(1.0 / np.maximum(np.asarray(Adj.sum(1)).ravel(), 1)) @ Adj).tocsr()
    v0 = v.copy(); dB0 = bone.d(v)
    att = A["attached"].astype(float) > 0.3
    band = att & (dB0 < 0.6)
    for _ in range(3):
        band = band | ((Adj @ band.astype(np.float32)) > 0) & att
    w = band.astype(np.float64)
    for _ in range(rounds):
        gb = bone.grad(v); dB = bone.d(v)
        hs = Adj @ dB
        dv = Adj @ v - v; dv -= (dv * gb).sum(1, keepdims=True) * gb          # slide along the bone
        v = v + 0.5 * w[:, None] * dv - (0.5 * w * (dB - hs))[:, None] * gb    # and ease the height over it
    d = v - v0; L = np.linalg.norm(d, axis=1); k = L > maxmove
    v[k] = v0[k] + d[k] * (maxmove / L[k])[:, None]
    lo = (bone.d(v) < np.minimum(dB0, 0.37)) & (dB0 > 0.3)
    v[lo] = v0[lo]
    return v


def ease_tails(v, f, A, bone, attach, maxmove=None):
    """(repair 2, H4) a margin's tail laid down: on the outer face within 3 mm of an attached edge, no higher over the bone
    than half the way in (a contact angle under about 27 degrees); off the attachments (over 1.6 mm from them, as A4 counts)
    never below 0.31 mm; only ever toward the bone, and by no more than maxmove in all"""
    v0 = v.copy(); ex = A["edge_mm"].astype(float)
    dA_ = cKDTree(np.concatenate(attach)).query(v, workers=2)[0]
    att_ = (A["attached"].astype(float) > 0.3) & (ex < 3.0)
    for _ in range(4):
        nv_ = vertex_normals(v, f); gb_ = bone.grad(v); dB_ = bone.d(v)
        tg_ = np.where(dA_ < 1.6, 0.45 * ex, np.maximum(0.45 * ex, 0.31))
        m_ = att_ & ((nv_ * gb_).sum(1) > 0.3)
        dd = np.where(m_, np.clip(dB_ - tg_, 0, 0.15), 0.0)
        v = v - dd[:, None] * gb_
    if maxmove is not None:
        d = v - v0; L = np.linalg.norm(d, axis=1); k = L > maxmove
        v[k] = v0[k] + d[k] * (maxmove / L[k])[:, None]
    return v


def keep_clear(v, bone, attach, other=None, lim=0.33, rounds=8):
    """(repair 2) the clearances after the edge tidy and the tail ease: off the attachments (over 1.6 mm from them, as A4
    counts) a vertex nearer the bone than lim is stepped out along the bone's gradient; one nearer the other muscle's surface
    (other: its distance function) is stepped away from it, up its gradient"""
    dA = cKDTree(np.concatenate(attach)).query(v, workers=2)[0]
    off = dA > 1.5
    for _ in range(rounds):
        dB = bone.d(v); m = off & (dB < lim + 0.005)
        if m.any():
            v[m] = v[m] + ((lim + 0.01 - dB[m])[:, None] * bone.grad(v[m]))
        if other is not None:
            d = other(v); k = d < lim + 0.005
            if k.any():
                e_ = 0.05; u = np.stack([other(v[k] + e_ * np.eye(3)[i]) - other(v[k] - e_ * np.eye(3)[i]) for i in range(3)], 1)
                u /= np.maximum(np.linalg.norm(u, axis=1, keepdims=True), 1e-9)
                v[k] = v[k] + (lim + 0.01 - d[k])[:, None] * u
    return v


def ease_colour_steps(v, f, A, lim=0.2, sigma=0.8):
    """(repair 2, after J3) the stored colour and film eased in space wherever two points 0.35-0.65 mm apart, facing alike,
    differ by more than `lim` of the red-white difference per 0.5 mm (B7's own measure): blended there toward the colour
    blurred over `sigma` mm. With the darker palette the red-white difference halved, and the steps left by the edge tidy
    and the clearance step (film and colour carried from far along the mesh) stood out."""
    col = A["color"].astype(float); fl = A["film"].astype(float); n = vertex_normals(v, f)
    tree = cKDTree(v); gv = np.zeros(len(v))
    for a in range(0, len(v), 50000):                      # (in pieces: all pairs at once do not fit in memory)
        ia = np.arange(a, min(a + 50000, len(v))); pr = tree.query_ball_point(v[ia], 0.65, workers=2)
        I = np.repeat(ia, [len(q) for q in pr]); J = np.concatenate([np.asarray(q, np.int64) for q in pr])
        d = np.linalg.norm(v[I] - v[J], axis=1); k = (d > 0.35) & ((n[I] * n[J]).sum(1) > 0.9); I, J, d = I[k], J[k], d[k]
        g = np.linalg.norm(col[I] - col[J], axis=1) / d * 0.5 / RED_WHITE
        np.maximum.at(gv, I, g)
    w = np.clip(blur3d(v, np.clip(gv / lim - 0.8, 0, 1), 0.5) * 2.0, 0, 1)
    # (not where the film is full: the attached line keeps the film's own colour, so the step to the bone stays small)
    w = w * np.clip((0.95 - fl) / 0.15, 0, 1)
    A["color"] = np.clip(col + (blur3d(v, col, sigma) - col) * w[:, None], 0, 1).astype(np.float16)
    A["film"] = np.clip(fl + (blur3d(v, fl, sigma) - fl) * w, 0, 1).astype(np.float16)
    return float((w > 0.05).mean())


def save_mesh(path, v, f, attrs):
    np.savez_compressed(path, v=v.astype(np.float32), f=f.astype(np.int32), **attrs)


# ====================================================================== the surface: strands, tendon, attachments (T-muscle-2)
# How the flesh looks follows the research spec of T-muscle-look (musTex/spec.md; its sources are cited there): fibres are
# bundled into fascicles by the perimysium, fascicles into the bundles a student sees, separated by septa; fine muscles have
# small fascicles; aponeurosis and tendon are white, glistening, of parallel collagen with a periodic crimp; the muscle-tendon
# junction interdigitates. None of the widths below is measured anywhere (spec D): they are our choice, tuned by eye against
# Figs. 378 and 382, where the masseter and the temporalis are fine-to-medium grained.
#   scale 1, bundles: about `bundle` mm apart, septa 0.2-0.5 mm deep (cosine crown, narrow septum, 40 % with a pale rim)
#   scale 2, fascicles: about `fasc` mm apart, 0.08-0.22 mm deep
#   scale 3, fibre striation (0.1-0.4 mm): not geometry; worked out per picture point from the vertex's across coordinate
# Every groove wanders, deepens and shallows along the fibres, starts or stops on its own (strands branch and merge), fades
# where the fan converges and its neighbours crowd it, and a few drift across a neighbour. All relief presses in (never out),
# so no clearance to bone or to another muscle can shrink by it.
# bundles: median 3.4 mm, long-tailed (meatRef T1/a: 2.7-3.4 mm in fine muscle, VH); fascicle grooves 1.3 mm (spec [D]
# anchor: primary fascicles are below the photographs' resolution); flesh: living human muscle #C9595B-#CB5F5D (meatRef T3,
# D06, D11), the masseter's deep part a shade darker; groove depths are the spec's own [C] (not measurable from photographs).
# (repair 2, J3: as rendered beside the bone that living red read too bright and pink. The bases are now deeper and browner,
# about x(0.80, 0.65, 0.59): flesh median L* about 42 in the side view against the bone's 56; was #C9595B.)
LOOK = {"temporalis": dict(fasc=1.3, bundle=3.4, d1=(0.3, 0.6), d2=(0.12, 0.3), lump=(0.3, 0.42), base=(161, 58, 54)),
        "masseter deep": dict(rough=-0.14, fasc=1.1, bundle=3.0, d1=(0.28, 0.55), d2=(0.12, 0.28), lump=(0.3, 0.42), base=(150, 52, 48)),
        "masseter superficial": dict(rough=-0.14, fasc=1.25, bundle=3.4, d1=(0.3, 0.6), d2=(0.12, 0.3), lump=(0.35, 0.5), base=(162, 62, 55)),
        "tendon": dict(fasc=0.7, bundle=1e9, d1=(0.0, 0.0), d2=(0.03, 0.07), lump=(0.0, 0.0), runs=False)}
FILM = np.array([182, 160, 145]) / 255.0          # periosteum and the thin fascia over a fleshy origin: flesh fading to bone
TENDON_C = np.array([143, 130, 119]) / 255.0      # tendon: a warm pale grey, no brighter than the bone beside it (repair 2,
                                                  # J3: the owner found the muscles too bright against the bones; atlas and
                                                  # cadaveric tendon is dull, not Gray's paper white; was (238, 224, 212))
PALE = np.array([155, 95, 85]) / 255.0            # flesh thinning over tendon, between the two
SEPTUM = np.array([134, 102, 91]) / 255.0         # perimysium seam #BA8E7E (meatRef C3, B08)
CAVITY = np.array([74, 28, 26]) / 255.0           # down in a groove (spec C2)


def hashf(i, j, seed):
    """a fixed pseudo-random number in [-1, 1] for each integer lattice point (i, j)"""
    h = (np.asarray(i, np.int64) * 73856093) ^ (np.asarray(j, np.int64) * 19349663) ^ (seed * 83492791 + 12345)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFF).astype(np.float64) / 0x7FFFF - 1.0


def vnoise(x, y, seed):
    """smooth value noise of the plane (lattice 1), about unit spread"""
    xi = np.floor(x); yi = np.floor(y); fx = x - xi; fy = y - yi
    ux = fx * fx * (3 - 2 * fx); uy = fy * fy * (3 - 2 * fy)
    a = hashf(xi, yi, seed); b = hashf(xi + 1, yi, seed); c = hashf(xi, yi + 1, seed); d = hashf(xi + 1, yi + 1, seed)
    return 1.7 * ((a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy)


def strand_set(seed, W, look):
    """the strands across a sheet W mm wide at its widest: boundaries t (0..1) between fascicles, lognormal widths about
    look['fasc'] mm (sigma 0.35, 0.6x to 1.8x), every few of them a bundle's septum, the bundles' widths long-tailed about
    look['bundle'] mm (lognormal sigma 0.6, 0.3x to 3x: meatRef T1/a, VH x9); each groove with its own depth and, along
    the fibres, its own broken run: on for about 3 strand widths (lognormal, p90 about 10), then off for about one, so that
    neighbouring strands merge and split every 2-2.5 widths (meatRef T2/b, D01); nearly straight (sideways wander about 5 %
    of the spacing, D01); and a shade for the fascicle beyond it"""
    rng = np.random.default_rng(seed)
    fm, bm = look["fasc"], look["bundle"]
    pos = []; x = rng.uniform(0.2, 1.0) * fm
    while x < W - 0.3 * fm:
        pos.append(x); x += float(np.clip(rng.lognormal(np.log(fm), 0.35), 0.6 * fm, 1.8 * fm))
    pos = np.array(pos); k = len(pos)
    lvl = np.zeros(k, bool); nxt = rng.uniform(0.3, 1.0) * bm
    for i, p in enumerate(pos):
        if p >= nxt:
            lvl[i] = True; nxt = p + float(np.clip(rng.lognormal(np.log(bm), 0.75), 0.3 * bm, 3.0 * bm))
    t = pos / W
    e = np.r_[2 * t[0] - t[1], t, 2 * t[-1] - t[-2]]
    sp2 = 0.5 * (e[2:] - e[:-2])
    sp1 = np.zeros(k); i1 = np.where(lvl)[0]
    if len(i1) > 1:
        t1 = t[i1]; e1 = np.r_[2 * t1[0] - t1[1], t1, 2 * t1[-1] - t1[-2]]
        sp1[i1] = 0.5 * (e1[2:] - e1[:-2])
    elif len(i1) == 1:
        sp1[i1] = 0.5
    d = np.where(lvl, rng.uniform(*look["d1"], k) if look["d1"][1] > 0 else 0.0, rng.uniform(*look["d2"], k))
    runs = look.get("runs", True)                       # a tendon's ridges run its whole length, unbroken
    # each groove's broken run along the fibres, as a table over -20..320 mm (0.25 mm): on ~3 widths, off ~1 width
    s_ax = np.arange(-20.0, 320.0, 0.25); on = np.ones((k, len(s_ax)), np.float32)
    if runs:
        wk = np.where(lvl, np.maximum(sp1 * W, bm), bm)   # in widths of the visible strand (the bundle: D12 3.3-4.9 mm)
        for i in range(k):
            x_ = -20.0 - rng.uniform(0, 3) * wk[i]; st = rng.random() < 0.75
            while x_ < 320.0:
                L = float(np.clip(rng.lognormal(np.log(3.0 * wk[i]), 0.8), 0.8 * wk[i], 14 * wk[i])) if st else \
                    float(np.clip(rng.lognormal(np.log(1.0 * wk[i]), 0.5), 0.4 * wk[i], 4 * wk[i]))
                if not st:
                    on[i, (s_ax >= x_) & (s_ax < x_ + L)] = 0.0
                x_ += L; st = not st
            # each end tapers over about half a width (a groove fades out, it does not stop square)
            on[i] = ndimage.gaussian_filter1d(on[i], 0.4 * wk[i] / 0.25)
    return dict(t=t, lvl=lvl, sp1=sp1, sp2=sp2, d=d, t1=t[i1], s_ax=s_ax, on=on,
                s0=np.full(k, -1e3), s1=np.full(k, -1e3), tap=rng.uniform(6, 15, k), wob=rng.uniform(0.03, 0.06, k),
                fr=rng.uniform(1 / 50.0, 1 / 15.0, (k, 3, 3)), ph=rng.uniform(0, 2 * np.pi, (k, 3, 3)), am=rng.normal(0, 1, (k, 3, 3)),
                cross=(rng.random(k) < 0.03) & ~lvl & runs, cs=rng.uniform(5, 70, k), cl=rng.uniform(25, 45, k),
                cd=rng.choice([-1.0, 1.0], k) * rng.uniform(0.6, 1.0, k), rim=lvl & (rng.random(k) < 0.4),
                dl=rng.normal(0, 0.05, k + 1), dh=rng.normal(0, 0.025, k + 1), dr=rng.uniform(-0.05, 0.05, k + 1),
                da=rng.uniform(-0.1, 0.1, k + 1), bl=rng.normal(0, 0.17, len(i1) + 1))


def _wave(B, k, which, smm):
    """a groove's own slow wave along the fibres (periods 15-50 mm), about unit spread"""
    am = B["am"][k, which]; g = (np.sin(2 * np.pi * B["fr"][k, which] * smm[:, None] + B["ph"][k, which]) * am).sum(1)
    return g / np.maximum(np.sqrt((am ** 2).sum(1)), 1e-6) * 1.2


def relief(B, t, smm, Lrest, acr):
    """the strands' relief at fibre coordinates (t across, 0..1; smm mm from the origin; Lrest mm left to the insertion; acr mm
    across per unit of t here): height h (mm, <= 0), bundle-septum and fascicle-groove depths here (for colour), the pale-rim
    weight, the fascicle index and the bundle index"""
    K = len(B["t"]); n = len(t)
    j = np.searchsorted(B["t"], t)
    g1 = np.zeros(n); g2 = np.zeros(n); rim = np.zeros(n)
    acr = np.maximum(acr, 1e-3)
    si = np.clip(np.round((smm - B["s_ax"][0]) / 0.25).astype(np.int64), 0, len(B["s_ax"]) - 1)
    for o in range(-4, 5):
        kk = j + o; ok = (kk >= 0) & (kk < K); k = np.clip(kk, 0, K - 1)
        sp = B["sp2"][k] * acr
        tk = B["t"][k] + B["wob"][k] * sp * np.clip(_wave(B, k, 1, smm), -1.5, 1.5) / acr
        cr = B["cross"][k]
        c = smoothstep((smm - B["cs"][k]) / B["cl"][k])
        tk = tk + np.where(cr, B["cd"][k] * sp * c / acr, 0.0)
        x = np.abs(t - tk) * acr
        run = B["on"][k, si]
        dep = B["d"][k] * (0.85 + 0.15 * np.clip(_wave(B, k, 0, smm), -1, 1)) * run * ok
        wj = 1 + 0.1 * np.clip(_wave(B, k, 2, smm), -1, 1)
        a2 = smoothstep((sp - 0.55) / 0.5)
        # (round-bottomed profiles: a V-bottom aliases on the mesh into a zigzag along the groove, which reads as jagged)
        K2 = 1 - smoothstep(x / (0.5 * sp * wj))
        lv = B["lvl"][k]
        g2 += a2 * K2 * np.where(lv, np.minimum(0.5 * dep, 0.2), dep)
        sp1 = B["sp1"][k] * acr
        a1 = smoothstep((sp1 - 1.2) / 1.0) * lv
        # a bundle: a broad crown over its width and a septum groove 0.18 of its width across (meatRef G4: 0.05-0.28)
        Kb = 1 - smoothstep(x / np.maximum(0.5 * sp1 * wj, 1e-3))
        Kn = 1 - smoothstep(x / np.maximum(0.09 * sp1 * wj, 0.3))
        g1 += a1 * dep * (0.4 * Kb + 0.6 * Kn)
        rim = np.maximum(rim, a1 * B["rim"][k] * run * np.exp(-(x / np.maximum(0.06 * sp1, 0.35)) ** 2))
    h = np.minimum(-(g1 + g2) + 0.1 * rim, 0.0)
    return h, g1, g2, rim, j, np.searchsorted(B["t1"], t)


def subdivide(v, f, A):
    """each triangle cut in four (edges halved); per-vertex values carried to the new vertices"""
    e = np.sort(np.r_[f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]], axis=1)
    eu, inv = np.unique(e, axis=0, return_inverse=True); inv = inv.ravel()
    m = len(v) + np.arange(len(eu)); nf = len(f)
    a, b, c = m[inv[:nf]], m[inv[nf:2 * nf]], m[inv[2 * nf:]]
    f0, f1, f2 = f.T
    F = np.r_[np.c_[f0, a, c], np.c_[a, f1, b], np.c_[c, b, f2], np.c_[a, b, c]]
    V = np.r_[v, 0.5 * (v[eu[:, 0]] + v[eu[:, 1]])]
    out = {}
    for k_, x in A.items():
        x = np.asarray(x)
        out[k_] = np.r_[x, x[eu[:, 0]]] if x.dtype.kind in "iub" else np.r_[x, 0.5 * (x[eu[:, 0]] + x[eu[:, 1]])].astype(x.dtype)
    return V, F.astype(np.int64), out


def surface_grad(v, f, x, same=None):
    """the gradient of a per-vertex value over the surface, per vertex (area-weighted mean of its faces'); faces whose
    vertices are of different parts (same: per-vertex labels) give none"""
    p0, p1, p2 = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    N = np.cross(p1 - p0, p2 - p0); A2 = np.linalg.norm(N, axis=1); Nu = N / np.maximum(A2, 1e-12)[:, None]
    g = (x[f[:, 0]][:, None] * np.cross(Nu, p2 - p1) + x[f[:, 1]][:, None] * np.cross(Nu, p0 - p2)
         + x[f[:, 2]][:, None] * np.cross(Nu, p1 - p0)) / np.maximum(A2, 1e-12)[:, None]
    w = A2.copy()
    if same is not None:
        w *= (same[f[:, 0]] == same[f[:, 1]]) & (same[f[:, 1]] == same[f[:, 2]])
    G = np.zeros_like(v); W = np.zeros(len(v))
    for k in range(3):
        np.add.at(G, f[:, k], g * w[:, None]); np.add.at(W, f[:, k], w)
    return G / np.maximum(W, 1e-12)[:, None]


def vertex_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, f[:, k], n)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-15)


def surface(v, f, A, sheets, bone, attach, sgn, seed, plate=None, others=(), log=print):
    """the muscle's finished surface: the smooth mesh cut finer, the strands pressed in along the fibres, the tendon placed and
    feathered, every attached margin thinned to nothing onto the bone, and the per-vertex values a renderer (and the app) needs:
    colour, fibre tangent, tendon share, across/along coordinates (mm), cavity, roughness and anisotropy jitter, and how far
    each vertex is from an attached margin (and whether one is under it).
    plate (temporalis): dict(sd=(z, y) -> mm inside Fig. 382's white, sv=the fibres' share above the arch)"""
    # the fibre coordinates fitted over the surface (about 1 mm, each part on its own), so that no trace of the samples' spacing
    # or layers is left in them: a wobble of 0.1 mm in t bends every groove and halves the strands' anisotropy (spec M2)
    n0 = vertex_normals(v, f); p0 = A["part"].astype(int)
    for _ in range(2):
        A["t"] = local_linear(v, n0, A["t"].astype(np.float64), p0).astype(np.float32)
        A["s"] = local_linear(v, n0, A["s"].astype(np.float64), p0).astype(np.float32)
    v, f, A = subdivide(v, f, A)
    v = sdf.taubin(v, f, 2)
    # cut once more (edges about 0.12 mm): a fascicle groove 1.3 mm across is then 10 edges wide, and its walls no longer
    # show the triangles as a zigzag along it (G7: jagged); every smoothing below is in rounds of this finer mesh (x4)
    v, f, A = subdivide(v, f, A)
    n_ = len(v); part = A["part"].astype(int)
    t = A["t"].astype(np.float64); s = A["s"].astype(np.float64)
    A["t"], A["s"] = t.astype(np.float32), s.astype(np.float32)
    smm = np.zeros(n_); Lrest = np.zeros(n_); acr = np.ones(n_)
    sets = []; W_ = []
    for j, sh in enumerate(sheets):
        m = part == j
        P = sh.P; nt, nw, ns = P.shape[:3]; out = P[:, -1]
        Lc = np.c_[np.zeros(nt), np.cumsum(np.linalg.norm(np.diff(out, axis=1), axis=-1), axis=1)]
        acr_s = np.linalg.norm(np.diff(out, axis=0), axis=-1).sum(0)
        smm[m] = ndimage.map_coordinates(Lc, [t[m] * (nt - 1), s[m] * (ns - 1)], order=1, mode="nearest")
        Lrest[m] = np.interp(t[m], np.linspace(0, 1, nt), Lc[:, -1]) - smm[m]
        acr[m] = np.interp(s[m], np.linspace(0, 1, ns), acr_s)
        W = 0.75 * float(acr_s.max()); W_.append(W)
        sets.append((strand_set(seed * 7 + j, W, LOOK[sh.name]), strand_set(seed * 7 + j + 50, W, LOOK["tendon"]), LOOK[sh.name]))
    n = vertex_normals(v, f)
    # the fibre tangent: across the surface's gradient of t (strands are lines of constant t), pointing from origin to insertion
    gt = surface_grad(v, f, t, part); gs = surface_grad(v, f, s, part)
    gt = smooth_on_mesh(v, f, gt, 16); gs = smooth_on_mesh(v, f, gs, 16)
    T = np.cross(gt, n); T *= np.sign((T * gs).sum(1) + 1e-12)[:, None]
    T -= (T * n).sum(1, keepdims=True) * n
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    # ---- the tendon
    if plate is not None:
        ns_ = smooth_on_mesh(v, f, n, 96); ns_ /= np.maximum(np.linalg.norm(ns_, axis=1, keepdims=True), 1e-9)
        wN = smoothstep((ns_[:, 0] * sgn + 0.1) / 0.4)                    # (the normal of the shape, not of its grooves)
        # well below the arch the plate shows nothing (the masseter and arch cover it): there the tendon is the fibres' own,
        # all round the coronoid (else its sharp turn flipped the share from 0 to 1 within half a millimetre)
        wN = wN * smoothstep((v[:, 1] + 18.0) / 12.0)
        below = smoothstep((s - plate["sv"] + 0.04) / 0.08)
        sd = plate["sd"](np.c_[v[:, 2], v[:, 1]])
        # the ring of flesh as the side view shows it (T-muscle-2 repair, F4): 3-6 mm of flesh before the tendon at the front
        # margin, and the tendon reaching to within about 3 mm of the hind margin low down, as on Fig. 382 (1.3 mm there)
        fo_ = f[(n[f].mean(1)[:, 0] * sgn) > 0.0]
        mk, lo_m, hm = side_mask(v, fo_, h=0.25, lo=(-70.0, -30.0), hi=(80.0, 100.0))
        ed = mk & ~ndimage.binary_erosion(mk)
        ey, ez = np.nonzero(ed); EZ = lo_m[0] + (ez + 0.5) * hm; EY = lo_m[1] + (ey + 0.5) * hm
        fr_ = (EY > 4) & (EY <= 47) & (EZ > 28); hi_ = (EY > 4) & (EY <= 47) & (EZ < 2)
        dfr = cKDTree(np.c_[EZ[fr_], EY[fr_]]).query(np.c_[v[:, 2], v[:, 1]])[0] if fr_.any() else np.full(n_, 99.0)
        dhi = cKDTree(np.c_[EZ[hi_], EY[hi_]]).query(np.c_[v[:, 2], v[:, 1]])[0] if hi_.any() else np.full(n_, 99.0)
        inwin = smoothstep((v[:, 1] - 2.0) / 4.0)
        keep_fr = 1 - inwin * (1 - smoothstep((dfr - 3.6) / 1.6))
        add_hi = inwin * smoothstep((v[:, 1] - 6.0) / 3.0) * smoothstep((24.0 - v[:, 1]) / 4.0) \
            * smoothstep((dhi - 2.6) / 1.2) * smoothstep((8.0 - dhi) / 2.5)
    Tn = np.zeros(n_); g1 = np.zeros(n_); g2 = np.zeros(n_); rim = np.zeros(n_)
    hf = np.zeros(n_); ht_ = np.zeros(n_); hl = np.zeros(n_)
    fasc = np.zeros(n_, np.int32); bund = np.zeros(n_, np.int32)
    col = np.zeros((n_, 3)); rough = np.zeros(n_); aniso = np.zeros(n_)
    u_mm = t * np.asarray(W_)[part]              # across coordinate whose lines are the fibres (they converge with the fan)
    for j, (B, Bt, look) in enumerate(sets):
        m = part == j
        hj, a1, a2, rj, fj, bj = relief(B, t[m], smm[m], Lrest[m], acr[m])
        ht = relief(Bt, t[m], smm[m], Lrest[m], acr[m])[0]
        # the lumpiness of a belly across its fibres (8-25 mm waves), pressed in
        lam = 14.0
        lump = -(look["lump"][0] + (look["lump"][1] - look["lump"][0]) * (0.5 + 0.35 * vnoise(u_mm[m] / lam, smm[m] / (2.5 * lam), seed + j)))
        lump = np.minimum(lump, 0.0)
        if plate is not None:
            # Fig. 382's white: a central fan ringed by flesh; its border runs in tongues along the fascicles (flesh tongues into
            # the tendon, tendon tongues into the flesh, 3-8 mm), each fascicle its own
            # (tongues: the border shifted along the fibres by a smooth wave across them, 3.5 mm, about 7 mm from tongue to
            # tongue; each strand's share ramps over 5-8 mm of its length: flesh thinning over tendon, pink, then white)
            uf = t[m] * W_[j]
            # (tongues kept gentle: where a tongue's side runs along the fibres the ramp is steep across them, and real flesh
            # meets tendon in a smooth ramp, toothed only a little where fibres reach the aponeurosis: meatRef d, D14, D01)
            off = 2.0 * vnoise(uf / 10.0, smm[m] / 60.0, seed + 301) + 0.4 * vnoise(uf / 4.0, smm[m] / 30.0, seed + 302)
            wd = 6.5 + 1.5 * vnoise(uf / 9.0, 0.5, seed + 303)
            tp = smoothstep((sd[m] + off + 2.0) / wd + 0.5)       # +2 mm: the soft ramp's half-way mark on the plate's edge
            tp = np.maximum(tp, add_hi[m]) * keep_fr[m]
            Tn[m] = np.maximum(wN[m] * tp + (1 - wN[m]) * below[m], below[m] * (1 - wN[m]))
        else:
            Tn[m] = A["tendon"][m]
        hf[m], ht_[m], hl[m] = hj, ht, lump
        g1[m], g2[m], rim[m] = a1 * (1 - Tn[m]), a2 * (1 - Tn[m]), rj * (1 - Tn[m])
        fasc[m] = fj + 1000 * j; bund[m] = bj + 1000 * j
        # flesh colour: the muscle's own, each bundle and each fascicle a little lighter or darker and warmer or cooler
        base = np.array(look["base"]) / 255.0
        # each fascicle and bundle a little lighter or darker, warmer or cooler, graded from one to the next (no hard stripes)
        tm = 0.5 * (np.r_[0.0, B["t"]] + np.r_[B["t"], 1.0]); tb = 0.5 * (np.r_[0.0, B["t1"]] + np.r_[B["t1"], 1.0])
        gl = lambda vals, cen: np.interp(t[m], cen, vals)
        lt = 1 + gl(B["dl"], tm) + gl(B["bl"], tb)
        c = base[None, :] * lt[:, None]
        dh = gl(B["dh"], tm)
        c[:, 0] *= 1 + dh; c[:, 2] *= 1 - dh
        rough[m] = gl(B["dr"], tm) + look.get("rough", 0.0); aniso[m] = gl(B["da"], tm) - (0.12 if "rough" in look else 0.0)
        # streaks within a bundle along the fibres (meatRef c: within a bundle L* sd 3-10)
        c = c * (1 + 0.07 * vnoise(u_mm[m] / 2.0, smm[m] / 14.0, seed + 40 + j))[:, None]
        col[m] = c
    tr_ = 400 if plate is not None else 40                                   # (the masseter's tongues: less, or they melt)
    Tn = smooth_on_mesh(v, f, Tn, tr_, same=part)                            # no step anywhere in the share (G7; ~2.4 mm)
    Tn = smooth_on_mesh(v, f, Tn, 150 if plate is not None else 24)          # and none where two parts meet on one face
    # the relief: flesh strands, tendon ridges, the belly's lumps under both; blended over a mm or so (no step at the border)
    Tg = smooth_on_mesh(v, f, Tn, 32)
    h = (1 - Tg) * hf + Tg * ht_ + hl
    # streaks along the fibres (spec C8: noise drawn out along the fibre field, here along the fibre coordinates)
    streak = 0.65 * vnoise(u_mm / 0.35, smm / 14.0, seed + 11) + 0.35 * vnoise(u_mm / 1.1, smm / 30.0, seed + 12)
    col *= (1 + 0.06 * streak)[:, None]
    # toward the tendon the flesh pales (over 10-25 mm)
    Tw = smooth_on_mesh(v, f, Tn, 240)
    col = col + (PALE - col) * np.clip(0.9 * Tw * (1 - Tn), 0, 0.6)[:, None]
    # groove darkening and the pale perimysium along some septa
    # (the cavity: how far the surface lies below its own 1.5-2 mm neighbourhood, i.e. down in a groove, not merely in a bundle)
    hc = (1 - smooth_on_mesh(v, f, Tn, 32)) * hf
    # (mostly the groove's own bottom, against its 0.5 mm neighbourhood; a little of the broader dip it lies in)
    cav = np.clip(0.75 * np.clip(-(hc - smooth_on_mesh(v, f, hc, 40)) / 0.012, 0, 1)
                  + 0.25 * np.clip(-(hc - smooth_on_mesh(v, f, hc, 500)) / 0.12, 0, 1), 0, 1)
    # (the darkening itself is the renderer's, as light that does not reach a groove's bottom: the stored colour stays the
    # tissue's own, smooth from fascicle to fascicle; see shaded(), CAV_DARK)
    col = col + (SEPTUM - col) * (0.2 * smooth_on_mesh(v, f, rim, 12))[:, None]
    tcol = TENDON_C[None, :] * (1 + 0.035 * vnoise(u_mm / 0.3, smm / 10.0, seed + 13)
                                + 0.05 * vnoise(u_mm / 0.9, smm / 40.0, seed + 14))[:, None]   # faint fibres to the coronoid
    # flesh, then flesh thinning over tendon (pink), then pearly white
    col = col + (PALE - col) * (0.75 * smoothstep(Tn / 0.6))[:, None]
    col = col + (tcol - col) * smoothstep((Tn - 0.3) / 0.7)[:, None]
    # the colour field eased over about half a millimetre (no colour step anywhere: G7, at most a quarter of the red-white
    # difference per 0.5 mm), and the flesh-tendon share with it
    col = smooth_on_mesh(v, f, col, 80)                  # (across the masseter's two parts too: no seam in colour)
    # ---- onto the bone: the relief pressed in, never deeper than 0.3 of the muscle's height over the bone here
    dB = bone.d(v); gb = bone.grad(v)
    ex = np.minimum.reduce([smm, Lrest, t * acr, (1 - t) * acr])          # mm to the sheet's nearest edge, along the surface
    datt = cKDTree(np.concatenate(attach)).query(v - gb * np.maximum(dB, 0)[:, None], workers=2)[0]
    aw = smoothstep((2.5 - datt) / 0.8) * (dB < 14.0)                      # an attachment is under this vertex
    aws = np.clip(smooth_on_mesh(v, f, aw, 60), 0, 1)                        # eased for the colour only: where the bone under a
                                                                             # vertex turns sharply, as under the arch, it jumped
                                                                             # (never for the pull: that would draw free flesh in)
    h = h * (1 - aw * (1 - smoothstep(ex / 2.0)))                           # the strands run on into the bone
    h = np.maximum(h, -0.3 * np.maximum(dB, 0.0))
    v = v + n * h[:, None]
    # every attached margin thinned to nothing: the height over the bone scaled down toward the edge (zero slope at the edge),
    # over the last 6 mm of a fleshy origin and 4 mm of a tendinous one; only toward the bone, only where the bone under the
    # vertex is an attachment
    dB = bone.d(v)
    # (repair F3: over the last 8 mm of a fleshy margin, 4.5 of a tendinous one, and flatter near the line, so the muscle meets
    # the bone at under 30 degrees; full pull wherever an attachment is more likely than not under the vertex)
    Lf = 8.0 - 3.5 * Tn
    p = smoothstep(ex / Lf) ** 2.0
    pull = np.where(dB > 0, dB * (1 - p) * np.clip(2.0 * aw, 0, 1), 0.0)
    if others:                                       # never pulled into (or within 0.45 mm of) a muscle already built
        fo = lambda q: np.min([F(q) for F in others], axis=0)
        k = np.ones(len(v)); bad = np.flatnonzero(pull > 0.01)
        for kk in (1.0, 0.8, 0.6, 0.4, 0.2, 0.0):
            if not len(bad):
                break
            ok = fo(v[bad] - gb[bad] * (kk * pull[bad])[:, None]) >= np.minimum(0.45, fo(v[bad]))
            k[bad] = kk; bad = bad[~ok]
        pull = pull * k
    v = v - gb * pull[:, None]
    # (where the bone under a margin turns, as at the zygomatic's hind border, one step along its gradient falls short: the
    # same share of what is left is taken twice more, along the gradient there)
    wpull = np.where(pull > 0, (1 - p) * np.clip(2.0 * aw, 0, 1), 0.0) * (k if others else 1.0)
    for _ in range(2):
        dB3 = bone.d(v); pl3 = np.where(dB3 > 0, dB3 * wpull, 0.0)
        v = v - bone.grad(v) * pl3[:, None]
    # off an attachment (more than about 1.5 mm from its trace) nothing lies under or within 0.35 mm of the bone (G4)
    dA = cKDTree(np.concatenate(attach)).query(v, workers=2)[0]
    wA = smoothstep((dA - 1.42) / 0.16)
    for _ in range(8):                                                       # (the field's gradient is rough deep inside)
        push = np.maximum(0.36 - bone.d(v), 0.0) * wA
        v = v + bone.grad(v) * push[:, None]
    bad = (bone.d(v) < 0.33) & (wA > 0.5)                                    # where the bone is thin the gradient fails: such a
    if bad.any():                                                            # spot is relaxed into its neighbours, then pushed
        from scipy import sparse
        e = np.r_[f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]
        Adj = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(v), len(v))).tocsr(); Adj = ((Adj + Adj.T) > 0).astype(np.float32)
        Adj = (sparse.diags(1.0 / np.maximum(np.asarray(Adj.sum(1)).ravel(), 1)) @ Adj).tocsr()
        m = bad.astype(np.float32)
        for _ in range(6):
            m = np.maximum(m, (Adj @ m > 0).astype(np.float32))
        m = ((m > 0) & (wA > 0.3) & (aw < 0.5)) | bad                     # (an attached margin, pulled down onto its bone, is left where it is)
        for _ in range(40):
            v[m] = (Adj @ v)[m]
        for _ in range(4):
            push = np.maximum(0.36 - bone.d(v), 0.0) * wA
            v = v + bone.grad(v) * push[:, None]
    if others:                                       # and no free surface within 0.36 mm of a muscle already built (G4)
        fo = lambda q: np.min([F(q) for F in others], axis=0)
        for _ in range(8):
            dO = fo(v); k = np.flatnonzero(dO < 0.36)
            if not len(k):
                break
            gO = np.stack([(fo(v[k] + 0.1 * ax) - fo(v[k] - 0.1 * ax)) / 0.2 for ax in np.eye(3)], 1)
            gO /= np.maximum(np.linalg.norm(gO, axis=1, keepdims=True), 1e-6)
            v[k] += gO * (0.37 - dO[k])[:, None]
    # last: where the bone is a thin plate its gradient points nowhere useful; what is still within 0.36 mm of it off an
    # attachment steps out along the muscle's own outward normal (G4)
    nn_ = vertex_normals(v, f)
    wA = smoothstep((cKDTree(np.concatenate(attach)).query(v, workers=2)[0] - 1.42) / 0.16)
    for _ in range(60):
        k_ = np.flatnonzero((wA > 0.5) & (bone.d(v) < 0.37))
        if not len(k_):
            break
        # (whichever way leaves the bone: the field's gradient taken over 2 mm, then the muscle's normal)
        gc = np.stack([bone.d(v[k_] + 2.0 * ax) - bone.d(v[k_] - 2.0 * ax) for ax in np.eye(3)], 1)
        gc /= np.maximum(np.linalg.norm(gc, axis=1, keepdims=True), 1e-9)
        up_ = bone.d(v[k_] + 0.15 * nn_[k_]) >= bone.d(v[k_] - 0.15 * nn_[k_])
        dn = np.where(up_, 1.0, -1.0)[:, None] * nn_[k_]
        v[k_] += 0.15 * np.where((_ % 2 == 0), 1.0, 0.0) * gc + 0.15 * np.where((_ % 2 == 1), 1.0, 0.0) * dn
    # nor any step where two sheets lie close, unjoined, as they lie now (pulled onto the bone): the share and the colour
    # blurred in space too (repair F1)
    Tn = np.clip(blur3d(v, Tn, 1.0 if plate is not None else 0.5), 0, 1); col = blur3d(v, col, 0.8 if plate is not None else 0.5)
    # flesh fading into bone over 1-3 mm (a periosteal film), tendon white into bone over 3 mm
    # (a straight ramp over 3.2 mm, eased at its ends: the fade spans 1-3 mm from 10 % to 90 % (repair F3) and is no steeper
    # anywhere than G7's cap, a quarter of red to white per 0.5 mm)
    # (measured in space from the attached margin itself, the vertices on the bone within 0.4 mm of the sheet's edge: the
    # attachment's own presence, aw, jumps where the bone under the muscle turns, as at the angle)
    m0 = (ex < 0.4) & (aw > 0.5) & (bone.d(v) < 0.6)
    if m0.sum() > 20:                                     # (along the surface: in space it leapt to the other part's edge)
        from scipy import sparse
        from scipy.sparse.csgraph import dijkstra
        e_ = np.r_[f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]
        Gm = sparse.coo_matrix((np.linalg.norm(v[e_[:, 0]] - v[e_[:, 1]], axis=1) + 1e-6, (e_[:, 0], e_[:, 1])), shape=(len(v), len(v))).tocsr()
        dline = np.minimum(dijkstra(Gm, directed=False, indices=np.flatnonzero(m0), min_only=True, limit=6.0), 99.0)
    else:
        dline = np.full(len(v), 99.0)
    film = np.clip(1.2 * smooth_on_mesh(v, f, np.clip(1 - dline / (3.4 if plate is not None else 2.4), 0, 1), 60), 0, 1)   # (masseter: a 1-3 mm fade, H4)
    tgt = FILM[None, :] + (0.5 * (TENDON_C + np.array(view_bone_rgb())) - FILM)[None, :] * Tn[:, None]
    col = col + (tgt - col) * film[:, None]
    A.update(color=np.clip(col, 0, 1).astype(np.float16), tangent=T.astype(np.float16), tendon=Tn.astype(np.float16),
             tendon_wide=Tw.astype(np.float16), u_mm=u_mm.astype(np.float32), s_mm=smm.astype(np.float32),
             cavity=cav.astype(np.float16), rim=rim.astype(np.float16), rough=rough.astype(np.float16), aniso=aniso.astype(np.float16),
             edge_mm=ex.astype(np.float16), attached=(aw * (bone.d(v) < 1.0)).astype(np.float16),film=film.astype(np.float16), relief=h.astype(np.float16),   # (attached: on bone)
             fascicle=fasc, bundle=bund)
    log("  surface: %d vertices, relief %.2f..%.2f mm, tendon %.0f %% of vertices, %d vertices pulled onto the bone (max %.2f mm)" % (
        n_, h.min(), h.max(), 100 * (Tn > 0.5).mean(), int((pull > 0.01).sum()), pull.max()))
    # (repair 2, H2-H4; both muscles since J1 rebuilt the temporalis from the fossa)
    v = tidy_edges(v, f, A, bone, maxmove=0.4 if plate is None else 0.2)
    v = ease_tails(v, f, A, bone, attach)
    if plate is None:
        # (H5) the masseter's own wet coat, a little stronger than the common one: its flatter face shows a sheen only where
        # the upper third turns up to the light
        A["coat"] = np.full(len(v), 0.8, np.float16); A["coat_rough"] = np.full(len(v), 0.3, np.float16)
    # (the margin's film and colour read again in space where the edges moved: two faces brought close by the tidy carry
    # film from far apart along the mesh, a step the eye sees; blurred over 0.6 mm only where the film is fading)
    fl_ = A["film"].astype(float); wf = np.clip(blur3d(v, ((fl_ > 0.02) & (fl_ < 0.98)).astype(float), 0.6) * 3, 0, 1)
    A["film"] = (fl_ + (blur3d(v, fl_, 0.6) - fl_) * wf).astype(np.float16)
    c_ = A["color"].astype(float); A["color"] = np.clip(c_ + (blur3d(v, c_, 0.6) - c_) * wf[:, None], 0, 1).astype(np.float16)
    v, f, A, k_ = largest_piece(v, f, A)
    v = keep_clear(v, bone, attach, other=others[-1] if others else None)
    eased = ease_colour_steps(v, f, A)
    log("  edges tidied; %d pieces, the largest kept; clearances kept; colour steps eased on %.1f %% of vertices" % (k_, 100 * eased))
    return v, f, A


def view_bone_rgb():
    """dry bone's colour as view.py paints it (0..1), the mean of its pale and its stain"""
    return [0.92, 0.87, 0.78]


# ====================================================================== pictures
def muscle_meshes(v, f, A, tint=1.0, nshade=5):
    """a muscle's mesh as a few flat-coloured pieces for view.picture's plain matte light (geometry judged without any shader's
    help): flesh in a few shades (by fascicle shade if the mesh has one, else one colour), tendon apart"""
    out = []
    ten = A["tendon"][f].astype(float).mean(1) > 0.5
    if "shade" in A:
        sh = A["shade"][f].mean(1)
        q = np.clip(((sh - 0.86) / 0.24 * nshade).astype(int), 0, nshade - 1)
    else:
        q = np.full(len(f), nshade // 2)
    for k in range(nshade):
        m = ~ten & (q == k)
        if m.any():
            c = tuple(int(min(255, x * (0.88 + 0.06 * k) * tint)) for x in FLESH)
            out.append((v, f[m], c))
    if ten.any():
        out.append((v, f[ten], TENDON))
    return out


# ====================================================================== the masseter
def sheet_normal(P, sgn):
    """a sheet's outward (lateral) normal at each point of its deep layer P (nt, ns, 3)"""
    dt = np.gradient(P, axis=0); ds = np.gradient(P, axis=1)
    n = np.cross(ds, dt)
    n *= np.sign((n[..., 0] * sgn).sum())
    n = ndimage.gaussian_filter(n, (1.5, 1.5, 0))
    return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)


def bulge(Pd, sall, seed, amp=2.0):
    """a sheet's edge fibres bowed outward across it (a belly widens between its ends), unevenly: no edge a straight string"""
    nt = Pd.shape[0]; t = np.linspace(0, 1, nt)
    dt = np.gradient(Pd, axis=0); dt /= np.maximum(np.linalg.norm(dt, axis=-1, keepdims=True), 1e-9)
    a = amp * (2 * t - 1) ** 3 * (1 + noise1(nt, seed, 0.3, 0.5))
    prof = np.sin(np.pi * sall) ** 0.9 * (1 + 0.35 * np.sin(2 * np.pi * sall * 1.3 + seed % 7))
    return Pd + dt * (a[:, None] * prof[None, :])[..., None]


def layers(Pd, nrm, T, O, I, sall):
    """the layers above a deep layer Pd (nt, ns, 3): offset along nrm by w * T, their ends drawn to their own attachments"""
    nt, ns = Pd.shape[:2]; nw = O.shape[1]
    P = np.zeros((nt, nw, ns, 3))
    b0 = 1 - sall; b1 = sall                       # each layer's own way from its origin to its insertion (no kink)
    for j, w in enumerate(np.linspace(0, 1, nw)):
        Q = Pd + (w * T)[..., None] * nrm
        Q = Q + (O[:, j] - Q[:, 0])[:, None, :] * b0[None, :, None] + (I[:, j] - Q[:, -1])[:, None, :] * b1[None, :, None]
        P[:, j] = Q
    return P


def inset(poly, d):
    """a closed outline (z, y) drawn in by d mm toward its centre"""
    c = poly.mean(0); v = poly - c
    return c + v * (1 - d / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9))


def area_patch(area):
    """Fig. 176's ringed area as a patch (u front to back, v top to bottom): its four sides are the line under the notch, the
    hind border, the lower border and the front border, met at the corners nearest the notch's front, the notch's hind end,
    the angle and the front of the lower border; a Coons patch in between. Returns f(u, v) -> (z, y)."""
    A = np.asarray(area, float); n = len(A)
    c0 = 0
    c2 = int(np.argmin(np.hypot(A[:, 0] - A[:, 0].min(), A[:, 1] - A[:, 1].min())))           # the angle: hind and low
    c3 = int(np.argmin(np.hypot(A[:, 0] - A[:, 0].max(), A[:, 1] - A[:, 1].min()) + 1e3 * (np.arange(n) <= c2)))  # front, low
    up = np.arange(1, c2)
    c1 = int(up[np.argmax(A[up, 1] - 0.6 * A[up, 0])])                                       # the notch's hind end
    top = resample(A[c0:c1 + 1], 200); right = resample(A[c1:c2 + 1], 200)
    bottom = resample(A[c2:c3 + 1][::-1], 200); left = resample(np.r_[A[c3:], A[:1]][::-1], 200)
    P00, P10, P11, P01 = A[c0], A[c1], A[c2], A[c3]
    ix = lambda C, u: np.column_stack([np.interp(u * 199, np.arange(200), C[:, k]) for k in range(2)])

    def f(u, v):
        u = np.atleast_1d(u).astype(float); v = np.atleast_1d(v).astype(float)
        U, V = u[:, None], v[:, None]
        return ((1 - V) * ix(top, u) + V * ix(bottom, u) + (1 - U) * ix(left, v) + U * ix(right, v)
                - ((1 - U) * (1 - V) * P00 + U * (1 - V) * P10 + U * V * P11 + (1 - U) * V * P01))
    return f


def face_in(bone, sgn, f, u, v, centre=(0.5, 0.5)):
    """the jaw's lateral face at the patch's (u, v); where the plate's area overhangs the built jaw, drawn in toward its centre"""
    out = np.full((len(u), 3), np.nan)
    for k in np.linspace(0, 1, 11):
        uu = u + (centre[0] - u) * k * 0.5; vv = v + (centre[1] - v) * k * 0.5
        miss = np.isnan(out[:, 0])
        if not miss.any():
            break
        q = f(uu[miss], vv[miss])
        out[miss] = face_hit(bone, q[:, 1], q[:, 0], sgn, medial=False)
    return out


def masseter(bone, sgn, seed, area, nt=40, nw=6, ns=48, log=print):
    """the masseter of one side as two sheets (deep, superficial); area: Fig. 176's masseter outline in the head frame (z, y).
    The insertion fills Fig. 176's ring: the deep portion its upper half (and the coronoid's lateral face, where the ring
    begins), the superficial portion its lower half, the angle and the hind border; the fibres of the two meet at mid-height
    ("continuous at their insertion", p. 386)."""
    rng = np.random.default_rng(seed)
    t = np.linspace(0, 1, nt); ws = np.linspace(0, 1, nw); sall = np.linspace(0, 1, ns)
    patch = area_patch(area)
    # ---- deep portion: "from the posterior third of the lower border and from the whole of the medial surface of the zygomatic
    # arch; its fibers pass downward and forward, to be inserted into the upper half of the ramus and the lateral surface of
    # the coronoid process"
    zl = np.interp(t, [0, 1], [31.0, 14.5]) + rng.normal(0, 0.15, nt); zm = np.interp(t, [0, 1], [46.0, 25.5])
    LBd = lower_border(bone, sgn, zl, xmin=55.0, ylo=-14.0, yhi=8.0)
    under = bone.ray(np.c_[LBd[:, 0] - sgn * 1.5, LBd[:, 1] - 6.0, zl], (0, 0.2, 0), ("skull",), n=60)
    under = np.where(np.isnan(under), LBd, under)
    med = np.zeros((nt, 3))
    for i, z in enumerate(zm):
        lb, top, xi = arch_frame(bone, sgn, z)
        med[i] = bone.ray(np.array([[sgn * 50.0, 0.5 * (lb + top) + 0.5, z]]), (sgn * 0.2, 0, 0), ("skull",), n=120)[0]
        if np.isnan(med[i, 0]):
            med[i] = (xi, 0.5 * (lb + top), z)
    Od = np.zeros((nt, nw, 3))
    for j, w in enumerate(ws):                      # deep layers from the medial surface, the outer from the lower border
        Od[:, j] = med * (1 - w) + under * w
    Od = bone.onto(Od.reshape(-1, 3), ("skull",)).reshape(nt, nw, 3)
    ud = 0.03 + 0.92 * t + noise1(nt, seed + 21, 0.25, 0.015)
    Id = np.zeros((nt, nw, 3))
    for j, w in enumerate(ws):
        vd = np.full(nt, 0.03 + 0.52 * w) + noise1(nt, seed + 22 + j, 0.2, 0.02)
        Id[:, j] = face_in(bone, sgn, patch, np.clip(ud, 0.02, 0.98), np.clip(vd, 0.02, 0.98))
    Pd = Od[:, 0][:, None] + (Id[:, 0] - Od[:, 0])[:, None] * sall[None, :, None]
    pin = np.zeros((nt, ns), bool); pin[:, 0] = pin[:, -1] = True
    Pd = wrap(Pd, bone, ("skull", "jaw"), CLEAR + 0.1, pin, rounds=150, k=0.4)
    Pd = bulge(Pd, sall, seed + 11, 3.0)
    Tm = np.interp(t, [0, 0.2, 0.7, 1], [2.5, 4.5, 5.0, 3.5]) * (1 + rng.normal(0, 0.05, nt) + noise1(nt, seed + 12, 0.2, 0.15))
    T = Tm[:, None] * (0.3 + 0.7 * np.sin(np.pi * np.clip(sall, 0, 1)) ** 0.7)[None, :]
    nrm = sheet_normal(Pd, sgn)
    P = layers(Pd, nrm, T, Od, Id, sall)
    for j in range(1, nw):
        pj = np.zeros((nt, ns), bool); pj[:, 0] = pj[:, -1] = True
        P[:, j] = wrap(P[:, j], bone, ("skull", "jaw"), CLEAR + 0.1, pj, rounds=50, k=0.08)
    tend = np.broadcast_to((smoothstep((0.06 - sall) / 0.04))[None, None, :], P.shape[:3]).copy()
    deep = Sheet("masseter deep", P, tend, seed=seed + 1)
    # ---- superficial portion: "arises by a thick, tendinous aponeurosis from the zygomatic process of the maxilla, and from the
    # anterior two-thirds of the lower border of the zygomatic arch: its fibers pass downward and backward, to be inserted into
    # the angle and lower half of the lateral surface of the ramus"
    zs = np.interp(t, [0, 1], [66.0, 39.0]) + rng.normal(0, 0.2, nt)     # (the deep part shows behind it, near the joint)
    LB = lower_border(bone, sgn, zs, xmin=47.0, ylo=-26.0, yhi=6.0)
    lip = side_hit(bone, zs, LB[:, 1] + 1.6 + noise1(nt, seed + 15, 0.2, 0.8), sgn)
    und = bone.ray(np.c_[LB[:, 0] - sgn * 2.5, LB[:, 1] - 6.0, zs], (0, 0.2, 0), ("skull",), n=60)
    und = np.where(np.isnan(und), LB, und); lip = np.where(np.isnan(lip), LB, lip)
    Os = np.zeros((nt, nw, 3))
    for j, w in enumerate(ws):
        Os[:, j] = und * (1 - w) + lip * w
    Os = bone.onto(Os.reshape(-1, 3), ("skull",)).reshape(nt, nw, 3)
    us = 0.02 + 0.96 * t + noise1(nt, seed + 23, 0.25, 0.015)
    Is = np.zeros((nt, nw, 3))
    for j, w in enumerate(ws):
        vs_ = np.full(nt, 0.46 + 0.52 * w) + noise1(nt, seed + 24 + j, 0.2, 0.02)
        Is[:, j] = face_in(bone, sgn, patch, np.clip(us, 0.02, 0.98), np.clip(vs_, 0.02, 0.98))
    deep.solid_D = None
    info = dict(Od=Od, Id=Id, Os=Os, Is=Is)
    log("masseter %s: deep %d x %d, superficial %d x %d" % ("L" if sgn > 0 else "R", nt, nw, nt, nw))
    return deep, (Os, Is, t, ws, sall, rng), info


def masseter_superficial(bone, sgn, seed, Os, Is, t, ws, sall, rng, which):
    nt, nw, ns = len(t), len(ws), len(sall)
    Pd = Os[:, 0][:, None] + (Is[:, 0] - Os[:, 0])[:, None] * sall[None, :, None]
    pin = np.zeros((nt, ns), bool); pin[:, 0] = pin[:, -1] = True
    Pd = wrap(Pd, bone, which, CLEAR + 0.1, pin, rounds=150, k=0.4)
    Pd = bulge(Pd, sall, seed + 13, 0.8)                                  # (straight front and hind borders)
    # a thick quadrilateral (Fig. 378): flat-topped across and along, its front and hind borders standing, a firm edge at the angle
    Tm = np.interp(t, [0, 0.05, 0.15, 0.5, 0.85, 0.95, 1], [4.2, 5.8, 6.0, 5.0, 6.0, 5.8, 4.2]) * (1 + rng.normal(0, 0.02, nt) + noise1(nt, seed + 14, 0.2, 0.04))
    # (nearly flat across, front to back; full thickness until near the angle, then a firm edge, not a lobe)
    # (repair 2, H5: the upper third thickens over a longer ramp, so the face there turns up through the light's mirror
    # direction and carries a broad sheen, as the fan's curve does; the lower end keeps its firm edge)
    T = Tm[:, None] * (0.25 + 0.75 * np.clip(1.6 * np.sin(np.pi * np.clip(sall, 0, 1) ** 1.6), 0, 1) ** np.where(sall < 0.5, 1.3, 0.4))[None, :]
    nrm = sheet_normal(Pd, sgn)
    P = layers(Pd, nrm, T, Os, Is, sall)
    # (repair 2, H1d) the outer face nearly flat front to back: across each level, its outward bow over the chord from front
    # to hind border capped softly at about 1.2 mm, every layer by its share, none brought within 2 mm of the deep layer
    X0 = P[..., 0] * sgn                                                  # (nt, nw, ns) lateral
    ch = X0[:1] + (X0[-1:] - X0[:1]) * t[:, None, None]
    dev = X0 - ch
    cap = np.where(dev > 0.3, 0.3 + 0.05 * (dev - 0.3), dev)
    wj = np.linspace(0, 1, nw)[None, :, None]
    Xn = np.maximum(X0 - wj * (dev - cap), X0[:, :1] + 2.0 * wj)
    Xn = np.minimum(Xn, X0)
    P[..., 0] = Xn * sgn
    for j in range(1, nw):
        pj = np.zeros((nt, ns), bool); pj[:, 0] = pj[:, -1] = True
        P[:, j] = wrap(P[:, j], bone, which, CLEAR + 0.1, pj, rounds=50, k=0.08)
    # the thick tendinous aponeurosis at the origin, carried down the front edge on the outer layers; a short tendinous insertion
    apo = 0.16 + 0.32 * (1 - smoothstep(t / 0.22))[:, None] * ws[None, :] ** 1.2 + noise1(nt, seed + 3, 0.15, 0.03)[:, None]
    # the aponeurosis's tendinous slips run down between the fleshy bundles to different depths in its upper half (Fig. 378,
    # p. 385): four to six, each its own length, soft-sided
    rs = np.random.default_rng(seed + 77); ksl = int(rs.integers(4, 7))
    slip = np.zeros(nt)
    for c_, L_ in zip(np.sort(rs.uniform(0.08, 0.92, ksl)), rs.uniform(0.1, 0.3, ksl)):
        slip = np.maximum(slip, L_ * np.exp(-0.5 * ((t - c_) / 0.035) ** 2))
    apo = apo + slip[:, None] * (0.4 + 0.6 * ws[None, :])
    tend = np.maximum(smoothstep((apo[..., None] - sall[None, None, :]) / 0.05), smoothstep((sall[None, None, :] - 0.95) / 0.03))
    sh = Sheet("masseter superficial", P, tend, seed=seed + 2)
    # (flesh to tendon over 14 % of the fibres' length, 5-7 mm: meatRef d measured ~6 % of a 40 cm muscle, ~24 mm, so the
    # ramp is no sharper than that in mm; G7 asks for 4-10 mm and at most a quarter of red-white per 0.5 mm)
    rs2 = np.random.default_rng(seed + 78)
    # (four tongues spread evenly over the arch's length with a small wander, so no two merge into a band; each its own
    # length, 10-22 mm, and width, 3.5-5 mm at the root)
    cen = np.linspace(0.14, 0.84, 4) + rs2.uniform(-0.03, 0.03, 4)
    sh.tendon_spec = dict(kind="tongues", base_mm=2.0, after=0.955,
                          tongues=[(float(c_), float(L_), float(rs2.uniform(4.5, 6.0)))
                                   for c_, L_ in zip(cen, rs2.permutation([13.5, 16.5, 19.5, 22.0]) + rs2.uniform(-1, 0, 4))])
    return sh


# ====================================================================== build
SEEDS = {1: dict(tem=11, mas=21), -1: dict(tem=53, mas=37)}       # the two sides grow from different seeds: no mirror copies


def field_rgi(path):
    Z = np.load(path); D = Z["D"].astype(np.float32); lo = Z["lo"]; h = float(Z["h"])
    return RGI([lo[i] + h * np.arange(D.shape[i]) for i in range(3)], D, bounds_error=False, fill_value=3.0)


WHITE382 = dict(red=55, level=0.5)      # Fig. 382's white: not red (r - g > 55, blurred 6 px, under half) inside the outline


def plate382_white(bone, plates_dir=None):
    """Fig. 382's white tendon fan as the plate's own colour shows it (inside the traced outline, the pixels that are not red
    flesh; largest piece, holes filled), and a function (z, y) -> mm inside its border (negative outside), in the head frame"""
    from PIL import Image, ImageDraw
    T, _, _, po = plate382(bone)
    im = Image.open(os.path.join(plates_dir or os.path.join(OUT, "gp"), "f382.png")).convert("RGB")
    a = np.asarray(im).astype(float)
    m = Image.new("L", im.size, 0); ImageDraw.Draw(m).polygon([tuple(p) for p in po["outline_px"]], fill=1); m = np.asarray(m) > 0
    red = ndimage.gaussian_filter(((a[..., 0] - a[..., 1]) > WHITE382["red"]).astype(float), 6) > WHITE382["level"]
    w = ndimage.binary_opening(m & ~red, iterations=6)
    lab, k = ndimage.label(w); w = lab == (1 + int(np.argmax(ndimage.sum(w, lab, range(1, k + 1)))))
    w = ndimage.binary_fill_holes(ndimage.binary_closing(w, iterations=8))
    sdp = ndimage.distance_transform_edt(w) - ndimage.distance_transform_edt(~w)
    s_, R, t_ = T

    def sd(Q):
        A_ = ((np.asarray(Q, float) - t_) @ R) / s_
        return ndimage.map_coordinates(sdp, [-A_[:, 1], -A_[:, 0]], order=1, cval=-80.0) * s_
    return sd, w, m, T


def build(sides=(1, -1), parts=("tem", "mas"), log=print):
    """the temporalis, then the masseter (kept off the temporalis), of each side; meshes, fields and attachments into $SCRATCH_OUT/b"""
    B = Bone(); t0 = time.time()
    info = pickle.load(open(os.path.join(OUT, "b", "%s_info.pkl" % TAG), "rb"))
    TPts = teeth_points(info)
    _, O382, _, _ = plate382(B)
    sd382 = plate382_white(B)[0]
    for sgn in sides:
        sd = "L" if sgn > 0 else "R"; base = os.path.join(OUT, "b", "mus_%%s_%s" % sd)
        if "tem" in parts:
            sh = temporalis(B, sgn, SEEDS[sgn]["tem"], O382, log=log)
            g = grid_for("temporalis", sgn)
            o, i = attachments(sh, B, ("skull",), ("jaw",), lie=sh.info["sv"])
            D, keep = solid("temporalis", [sh], g, B, sgn, [o, i], teethP=TPts, log=log)
            v, f, A = to_mesh(D, g, keep)
            v, f, A = surface(v, f, A, [sh], B, [o, i], sgn, SEEDS[sgn]["tem"], plate=dict(sd=sd382, sv=sh.info["sv"]), log=log)
            save_mesh(base % "tem" + ".npz", v, f, A)
            np.savez_compressed(base % "tem" + "_D.npz", D=D.astype(np.float16), lo=g.lo, h=g.h)
            pickle.dump(dict(o=[o], i=[i], fas=[sh.fas], P=[sh.P], tendon=[sh.tendon], sv=sh.info["sv"]), open(base % "tem" + "_meta.pkl", "wb"))
            log("temporalis %s: %d vertices, %.0f s" % (sd, len(v), time.time() - t0))
        if "mas" in parts:
            area = ramus_area(B, sgn)                      # (J2: the insertion from the built jaw; Fig. 176 only checks it)
            deep, rest, inf = masseter(B, sgn, SEEDS[sgn]["mas"], area, log=log)
            g = grid_for("masseter", sgn)
            B.F["mdeep"] = RGI(g.ax, write(g, deep.fine()[0].reshape(-1, 3)), bounds_error=False, fill_value=3.0)
            sup = masseter_superficial(B, sgn, SEEDS[sgn]["mas"], *rest, which=("skull", "jaw", "mdeep"))
            del B.F["mdeep"]
            oa, ia = attachments(deep, B, ("skull",), ("jaw",)); ob, ib = attachments(sup, B, ("skull",), ("jaw",))
            D, keep = solid("masseter", [deep, sup], g, B, sgn, [oa, ia, ob, ib], others=[field_rgi(base % "tem" + "_D.npz")],
                            teethP=TPts, log=log)
            v, f, A = to_mesh(D, g, keep)
            tT = cKDTree(np.load(base % "tem" + ".npz")["v"].astype(np.float64))   # the temporalis as built (pulled, pushed),
            v, f, A = surface(v, f, A, [deep, sup], B, [oa, ia, ob, ib], sgn, SEEDS[sgn]["mas"],  # not only its field
                              others=[field_rgi(base % "tem" + "_D.npz"), lambda q: tT.query(q, workers=2)[0]], log=log)
            save_mesh(base % "mas" + ".npz", v, f, A)
            np.savez_compressed(base % "mas" + "_D.npz", D=D.astype(np.float16), lo=g.lo, h=g.h)
            pickle.dump(dict(o=[oa, ob], i=[ia, ib], fas=[deep.fas, sup.fas], P=[deep.P, sup.P], tendon=[deep.tendon, sup.tendon],
                             area=area), open(base % "mas" + "_meta.pkl", "wb"))
            log("masseter %s: %d vertices, %.0f s" % (sd, len(v), time.time() - t0))


# ====================================================================== checks (A1..A5)
def load_built(name, sd):
    base = os.path.join(OUT, "b", "mus_%s_%s" % (name, sd))
    z = np.load(base + ".npz"); A = {k: z[k] for k in z.files}
    meta = pickle.load(open(base + "_meta.pkl", "rb"))
    return A, meta, field_rgi(base + "_D.npz")


def side_mask(v, f, h=0.25, lo=(-60.0, -110.0), hi=(110.0, 130.0), axes=(2, 1)):
    """the mesh's silhouette projected on two axes (default side view (z, y)), raster h mm: (mask, lo)"""
    from PIL import Image, ImageDraw
    W = int((hi[0] - lo[0]) / h); Hh = int((hi[1] - lo[1]) / h)
    im = Image.new("L", (W, Hh), 0); d = ImageDraw.Draw(im)
    Q = np.c_[(v[:, axes[0]] - lo[0]) / h, (v[:, axes[1]] - lo[1]) / h]
    for t in Q[f]:
        d.polygon([tuple(p) for p in t], fill=1)
    return np.asarray(im) > 0, np.asarray(lo, float), h


def outline_of(mask, lo, h):
    """the longest boundary of a mask, as points in mm"""
    from skimage import measure
    cs = measure.find_contours(np.pad(mask.astype(float), 1), 0.5)
    c = max(cs, key=len) - 1
    return np.c_[lo[0] + c[:, 1] * h, lo[1] + c[:, 0] * h]


def two_way(A, B):
    """misses between two outlines (mm): from A to B and from B to A, each (mean, max)"""
    a = resample(np.r_[A, A[:1]], 2000); b = resample(np.r_[B, B[:1]], 2000)
    da, _ = cKDTree(b).query(a); db, _ = cKDTree(a).query(b)
    return ((round(float(da.mean()), 2), round(float(da.max()), 2), a[np.argmax(da)].round(1).tolist()),
            (round(float(db.mean()), 2), round(float(db.max()), 2), b[np.argmax(db)].round(1).tolist()))


def straight_runs(C, L=8.0, tol=0.2):
    """the longest run (mm) of an outline that stays within tol of a straight line, for chords of length L or more"""
    C = resample(np.r_[C, C[:1]], max(200, int(np.sum(np.linalg.norm(np.diff(C, axis=0), axis=1)) / 0.25)))
    C = ndimage.gaussian_filter1d(C, 1.0, axis=0, mode="wrap")
    s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))]
    n = len(C); best = 0.0
    j = 0
    for i in range(n):
        j = max(j, i + 1)
        while j < n:
            a, b = C[i], C[j]; e = b - a; ln = np.linalg.norm(e)
            if ln < 1e-6:
                j += 1; continue
            seg = C[i:j + 1] - a
            dev = np.abs(seg[:, 0] * e[1] - seg[:, 1] * e[0]) / ln
            if dev.max() > tol:
                break
            j += 1
        best = max(best, s[j - 1] - s[i])
    return float(best)


def flat_patches(v, n=6000, r=2.83, tol=0.05, seed=0, keep=None):
    """how flat the flattest 4 x 4 mm patch is: per sampled vertex, the largest miss of its neighbours (within r) from their plane"""
    rng = np.random.default_rng(seed)
    pool = np.arange(len(v)) if keep is None else np.where(keep)[0]
    idx = rng.choice(pool, min(n, len(pool)), replace=False)
    tree = cKDTree(v); out = []
    for i in idx:
        nb = tree.query_ball_point(v[i], r)
        if len(nb) < 12:
            continue
        P = v[nb] - v[nb].mean(0)
        _, S_, Vt = np.linalg.svd(P, full_matrices=False)
        out.append(np.abs(P @ Vt[2]).max())
    out = np.array(out)
    return float(out.min()), int((out < tol).sum()), len(out)


def steps(v, f, bone=None, r=1.0, n=8000, seed=1, keep=None):
    """a step is a sudden turn of the surface over a millimetre: per sampled vertex, the surface's normal over the 1 mm round
    it (plane fit) against the normals of the patches 1 mm away; the largest turn (degrees), its 99.9th percentile, and how
    many turn more than 60 degrees. Rims where the muscle meets the bone (within 1 mm of it) are left out: the muscle's
    edge on the bone is a crease by design."""
    rng = np.random.default_rng(seed); tree = cKDTree(v)
    pool = np.arange(len(v)) if keep is None else np.where(keep)[0]
    idx = rng.choice(pool, min(n, len(pool)), replace=False)
    if bone is not None:
        idx = idx[bone.d(v[idx]) > 1.0]

    def nrm(p):
        nb = tree.query_ball_point(p, r)
        if len(nb) < 6:
            return None
        P = v[nb] - v[nb].mean(0)
        return np.linalg.svd(P, full_matrices=False)[2][2]
    out = []
    for i in idx:
        n0 = nrm(v[i])
        if n0 is None:
            continue
        worst = 0.0
        for j in tree.query_ball_point(v[i], 1.6)[::4]:
            if np.linalg.norm(v[j] - v[i]) < 0.8:
                continue
            n1 = nrm(v[j])
            if n1 is not None:
                worst = max(worst, np.degrees(np.arccos(min(1.0, abs(float(n0 @ n1))))))
        out.append(worst)
    out = np.array(out)
    return float(out.max()), int((out > 60).sum()), float(np.percentile(out, 99.9))


def _old_steps(v, f):
    """the sharpest fold between neighbouring faces (degrees) and how many edges fold more than 60 degrees"""
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]); n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    e = np.r_[np.c_[f[:, 0], f[:, 1]], np.c_[f[:, 1], f[:, 2]], np.c_[f[:, 2], f[:, 0]]]
    fi = np.tile(np.arange(len(f)), 3)
    key = np.sort(e, axis=1); order = np.lexsort((key[:, 1], key[:, 0])); key = key[order]; fi = fi[order]
    same = np.all(key[1:] == key[:-1], axis=1)
    a = fi[:-1][same]; b = fi[1:][same]
    ang = np.degrees(np.arccos(np.clip((n[a] * n[b]).sum(1), -1, 1)))
    return float(ang.max()), int((ang > 60).sum()), float(np.percentile(ang, 99.9))


def footprint(v, f, bone, A=None, tol=0.2):
    """faces lying on bone (all three vertices within tol): per bone, area (mm2), centroid, z/y extent, and the face mask"""
    out = {}
    ds = bone.d(v, ("skull",)); dj = bone.d(v, ("jaw",))
    tri_area = 0.5 * np.linalg.norm(np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]]), axis=1)
    for k, d in (("skull", ds), ("jaw", dj)):
        m = np.all(d[f] < tol, axis=1)
        if not m.any():
            out[k] = dict(area=0.0); continue
        c = v[f[m]].mean(1)
        out[k] = dict(area=float(tri_area[m].sum()), centroid=c.mean(0).round(1).tolist(),
                      z=[round(float(c[:, 2].min()), 1), round(float(c[:, 2].max()), 1)],
                      y=[round(float(c[:, 1].min()), 1), round(float(c[:, 1].max()), 1)], mask=m)
        if A is not None:
            out[k]["by_part"] = {int(p): float(tri_area[m & (A["part"][f].max(1) == p)].sum()) for p in np.unique(A["part"])}
    return out


def fibre_angles_side(P, sel, R=None):
    """the mean angle (degrees, to the Frankfurt plane, in side view, face to the left: + rising backward) of fibre segments
    P[..., s] chosen by sel (bool over the segments)"""
    dP = np.diff(P, axis=-2)
    dz, dy = -dP[..., 2], dP[..., 1]                  # face to the left: backward is +
    a = np.arctan2(dy, dz)[sel]
    w = np.hypot(dz, dy)[sel]
    c = (w * np.cos(2 * a)).sum(); s = (w * np.sin(2 * a)).sum()
    m = 0.5 * np.arctan2(s, c)
    return float(np.degrees(m)), float(np.degrees(np.sqrt(max(-2.0 * np.log(np.hypot(c, s) / w.sum()), 0.0)) / 2))


def plate_orient(img, poly, sig=5, cmin=0.5):
    """the stripes' mean direction in a polygon of a plate (degrees, image x right, y up) and their spread (structure tensor)"""
    from PIL import Image, ImageDraw
    g = np.asarray(img.convert("L")).astype(float); gs = ndimage.gaussian_filter(g, 1.0)
    gx = ndimage.sobel(gs, 1); gy = -ndimage.sobel(gs, 0)
    Jxx = ndimage.gaussian_filter(gx * gx, sig); Jyy = ndimage.gaussian_filter(gy * gy, sig); Jxy = ndimage.gaussian_filter(gx * gy, sig)
    m = Image.new("L", img.size, 0); ImageDraw.Draw(m).polygon([tuple(p) for p in poly], fill=1)
    m = ndimage.binary_erosion(np.asarray(m) > 0, iterations=4)
    tr = Jxx + Jyy; coh = np.sqrt((Jxx - Jyy) ** 2 + 4 * Jxy ** 2) / np.maximum(tr, 1e-9)
    th = 0.5 * np.arctan2(2 * Jxy, Jxx - Jyy) + np.pi / 2
    k = m & (coh > cmin); w = coh[k] * tr[k]
    c = (w * np.cos(2 * th[k])).sum(); s = (w * np.sin(2 * th[k])).sum()
    return float(np.degrees(0.5 * np.arctan2(s, c))), float(np.degrees(0.5 * np.sqrt(-2 * np.log(np.hypot(c, s) / w.sum()))))


def cross2(a, b):
    return a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]


def wrap180(a):
    return (a + 90.0) % 180.0 - 90.0


TENDON_SHARE_382 = 0.39     # Fig. 382: the white tendon (traced polygon) over the whole muscle outline, in plate pixels

# Fig. 382's regions (crop pixels) for the fibres' angles: front band, middle of the fan above the tendon, hind fibres
F382_REGIONS = {"front": [(300, 460), (370, 360), (410, 480), (380, 640), (330, 660)],
                "middle": [(480, 240), (600, 220), (640, 340), (520, 380)],
                "hind": [(840, 480), (980, 460), (980, 580), (840, 600)]}
# Fig. 378 (page 379 at 2x: h-0378.png, crop at (480, 760)): the superficial portion, and the deep portion showing behind it
F378_CROP = (480, 760, 1100, 1380)
F378_REGIONS = {"superficial": [(215, 330), (320, 290), (345, 330), (360, 420), (355, 490), (320, 510), (255, 480), (215, 420)],
                "deep": [(325, 288), (370, 290), (378, 345), (352, 365), (338, 320)]}
F378_ORIGIN_EDGE = [(215, 330), (320, 290)]          # the superficial portion's upper edge: the arch's lower border drawn


def vs_arch(sgn):
    """points on the zygomatic arch's surface (the skull's mesh beside the temporal fossa, lateral to 55 mm)"""
    v, f = bone_mesh("skull")
    m = (sgn * v[:, 0] > 55.0) & (v[:, 2] > 22.0) & (v[:, 2] < 58.0) & (v[:, 1] > -24.0) & (v[:, 1] < 4.0)
    return v[m]


def check(log=print, plates_dir=None):
    """every acceptance number, as a dict (and logged)"""
    from PIL import Image
    B = Bone(); R = {}
    info = pickle.load(open(os.path.join(OUT, "b", "%s_info.pkl" % TAG), "rb")); TPts = teeth_points(info)
    Ttree = cKDTree(TPts)
    T382, O382, res382, _ = plate382(B)
    s382 = T382[0]; rot382 = float(np.degrees(np.arctan2(T382[1][1, 0], T382[1][0, 0])))
    R["registration"] = {"fig382": dict(mm_per_px=round(float(s382), 4), rotation_deg=round(rot382, 1),
                                        misses_mm={k: round(v, 2) for k, v in res382.items()})}
    built = {}
    for sd, sgn in (("L", 1), ("R", -1)):
        for nm in ("tem", "mas"):
            built[nm, sd] = load_built(nm, sd)
    for sd, sgn in (("L", 1), ("R", -1)):
        T176, area, d176 = plate176(B, sgn)
        R["registration"]["fig176_" + sd] = dict(mm_per_px=round(float(T176[0]), 4),
                                                 rotation_deg=round(float(np.degrees(np.arctan2(T176[1][1, 0], T176[1][0, 0]))), 1),
                                                 jaw_outline_miss_mm=(round(float(np.mean(d176)), 2), round(float(np.max(d176)), 2)))
        At, Mt, Ft = built["tem", sd]; Am, Mm, Fm = built["mas", sd]
        vt, ft, vm, fm = At["v"], At["f"], Am["v"], Am["f"]
        r = R[sd] = {}
        # ---- A1: outlines against the plates
        mk, lo, h = side_mask(vt, ft)
        ot = outline_of(mk, lo, h)
        r["A1_temporalis_side_vs_fig382"] = dict(zip(("plate_to_model", "model_to_plate"), two_way(O382, ot)))
        a_ = resample(np.r_[O382, O382[:1]], 2000); b_ = resample(np.r_[ot, ot[:1]], 2000)
        da_, _ = cKDTree(b_).query(a_); db_, _ = cKDTree(a_).query(b_)
        ka, kb = a_[:, 1] > 0.0, b_[:, 1] > 0.0
        r["A1_temporalis_above_arch_y>0"] = dict(plate_to_model=(round(float(da_[ka].mean()), 2), round(float(da_[ka].max()), 2)),
                                                 model_to_plate=(round(float(db_[kb].mean()), 2), round(float(db_[kb].max()), 2)))
        fpm = footprint(vm, fm, B, Am)
        mj = fpm["jaw"]["mask"]
        mk2, lo2, h2 = side_mask(vm, fm[mj])
        mk2 = ndimage.binary_closing(mk2, iterations=6)
        oi = outline_of(mk2, lo2, h2)
        r["A1_masseter_insertion_vs_fig176"] = dict(zip(("plate_to_model", "model_to_plate"), two_way(area, oi)))
        # ---- A2
        outl = {"tem_side": ot, "mas_side": outline_of(side_mask(vm, fm)[0], lo, h)}
        for nm, (v, f) in (("tem", (vt, ft)), ("mas", (vm, fm))):
            mf, lf, hf = side_mask(v, f, lo=(-110.0, -110.0), hi=(110.0, 130.0), axes=(0, 1))
            outl[nm + "_front"] = outline_of(mf, lf, hf)
            mb, lb, hb = side_mask(v, f, lo=(-110.0, -80.0), hi=(110.0, 140.0), axes=(0, 2))
            outl[nm + "_below"] = outline_of(mb, lb, hb)
        r["A2_longest_straight_run_mm"] = {k: round(straight_runs(c), 1) for k, c in outl.items()}
        # free surface: off the bone by more than 1 mm (where the muscle lies on bone its face is the bone's own cast)
        r["A2_flattest_4x4_patch_free_surface"] = {nm: dict(zip(("min_max_deviation_mm", "patches_under_0.05", "patches_tested"),
                                                                flat_patches(v, keep=B.d(v) > 1.0)))
                                                   for nm, v in (("tem", vt), ("mas", vm))}
        r["A2_flattest_4x4_patch_all"] = {nm: dict(zip(("min_max_deviation_mm", "patches_under_0.05", "patches_tested"), flat_patches(v)))
                                          for nm, v in (("tem", vt), ("mas", vm))}

        def away_from_rims(v, A_, meta):
            """vertices more than 2 mm from a border: from the sheet's front and hind edges (its t ends, in mm across) and
            from the bone (the attached borders)"""
            keep = B.d(v) > 2.0
            for j, P in enumerate(meta["P"]):
                acr = np.linalg.norm(np.diff(P[:, -1], axis=0), axis=-1).sum(0)
                wmm = np.interp(A_["s"], np.linspace(0, 1, P.shape[2]), acr)
                m = A_["part"] == j
                keep &= ~(m & ((A_["t"] * wmm < 2.0) | ((1 - A_["t"]) * wmm < 2.0)))
            return keep
        r["A2_steps_away_from_rims"] = {nm: dict(zip(("max_turn_over_1mm_deg", "samples_over_45deg", "p99.9_turn_deg"),
                                                     steps(v, f, B, keep=away_from_rims(v, A_, meta))))
                                        for nm, v, f, A_, meta in (("tem", vt, ft, At, Mt), ("mas", vm, fm, Am, Mm))}
        # the masseter's waist: side view breadth just under the arch (y -20) and at mid-height (y -46)
        mkm, lom, hm = side_mask(vm, fm)
        def breadth(y):
            row = mkm[int((y - lom[1]) / hm)]
            z = lom[0] + np.where(row)[0] * hm
            return float(z.max() - z.min()) if len(z) else 0.0
        b20, b46 = breadth(-20.0), breadth(-46.0)
        r["F1_masseter_breadth_mm"] = dict(at_arch_y_minus20=round(b20, 1), mid_height_y_minus46=round(b46, 1), ratio=round(b46 / max(b20, 1e-6), 3))
        # the tendon's share of the temporalis seen from the side (outer surface), against Fig. 382's white
        outer = At["layer"][ft].mean(1) > 0.85
        pa = 0.5 * np.abs(cross2(vt[ft[:, 1]][:, [2, 1]] - vt[ft[:, 0]][:, [2, 1]], vt[ft[:, 2]][:, [2, 1]] - vt[ft[:, 0]][:, [2, 1]]))
        tf = At["tendon"][ft].mean(1) > 0.5
        r["F3_tendon_share_side_view"] = dict(model=round(float(pa[outer & tf].sum() / max(pa[outer].sum(), 1e-6)), 3), plate_fig382=TENDON_SHARE_382)
        om = Am["layer"][fm].mean(1) > 0.85
        pam = 0.5 * np.abs(cross2(vm[fm[:, 1]][:, [2, 1]] - vm[fm[:, 0]][:, [2, 1]], vm[fm[:, 2]][:, [2, 1]] - vm[fm[:, 0]][:, [2, 1]]))
        r["F3_masseter_aponeurosis_share_side_view"] = round(float(pam[om & (Am["tendon"][fm].mean(1) > 0.5)].sum() / max(pam[om].sum(), 1e-6)), 3)
        import sdf as _s
        r["A2_pieces"] = {nm: len(_s.components(v, f)) for nm, v, f in (("tem", vt, ft), ("mas", vm, fm))}
        # (no blob: each muscle one piece; how thick it is against how long, from the fibre sheets)
        r["A2_thickness_vs_length"] = {}
        for nm, meta in (("tem", Mt), ("mas", Mm)):
            for P in meta["P"]:
                L_ = np.linalg.norm(np.diff(P[:, 0], axis=1), axis=-1).sum(1)
                Th = np.linalg.norm(P[:, -1] - P[:, 0], axis=-1).max(1)
                r["A2_thickness_vs_length"]["%s_%d" % (nm, len(r["A2_thickness_vs_length"]))] = dict(
                    fibre_length_mm=[round(float(L_.min()), 1), round(float(L_.max()), 1)], max_thickness_mm=round(float(Th.max()), 1))
        # ---- A3: footprints and parts
        fpt = footprint(vt, ft, B, At)
        r["A3_temporalis"] = {k: {kk: vv for kk, vv in d.items() if kk != "mask"} for k, d in fpt.items()}
        r["A3_masseter"] = {k: {kk: vv for kk, vv in d.items() if kk != "mask"} for k, d in fpm.items()}
        ten = At["tendon"][ft].mean(1) > 0.5
        ta = 0.5 * np.linalg.norm(np.cross(vt[ft[:, 1]] - vt[ft[:, 0]], vt[ft[:, 2]] - vt[ft[:, 0]]), axis=1)
        r["A3_parts"] = dict(masseter_deep_vertices=int((Am["part"] == 0).sum()), masseter_superficial_vertices=int((Am["part"] == 1).sum()),
                             temporalis_fan_area_mm2=round(float(ta[~ten].sum())), temporalis_tendon_area_mm2=round(float(ta[ten].sum())),
                             masseter_tendinous_area_mm2=round(float((0.5 * np.linalg.norm(np.cross(vm[fm[:, 1]] - vm[fm[:, 0]], vm[fm[:, 2]] - vm[fm[:, 0]]), axis=1))[Am["tendon"][fm].mean(1) > 0.5].sum())))
        # passage under the arch: the temporalis' section in the plane through the arch at mid height, medial to its inner face
        sec = []
        for z in np.arange(26.0, 50.0, 2.0):
            lb_, top_, xi = arch_frame(B, sgn, z)
            ym = 0.5 * (lb_ + top_)
            xs = np.arange(20.0, 75.0, 0.25)
            P = np.c_[sgn * xs, np.full(len(xs), ym), np.full(len(xs), z)]
            inm = Ft(P) < 0
            lat = sgn * P[:, 0] > abs(xi)
            sec.append((z, float(inm[~lat].sum() * 0.25), float(inm[lat].sum() * 0.25)))
        r["A3_tendon_under_arch"] = dict(width_medial_to_arch_mm_by_z={int(a): b for a, b, c in sec},
                                         muscle_lateral_to_arch_mm=float(sum(c for a, b, c in sec)))
        # ---- A4: clearances
        def clear(v, A_, meta):
            Ap = np.concatenate([np.concatenate(meta["o"]), np.concatenate(meta["i"])])
            da, _ = cKDTree(Ap).query(v)
            off = da > 1.6
            dB = B.d(v)
            return off, dB
        offt, dBt = clear(vt, At, Mt); offm, dBm = clear(vm, Am, Mm)
        dteeth_t, _ = Ttree.query(vt); dteeth_m, _ = Ttree.query(vm)
        dmt, _ = cKDTree(vt).query(vm)
        pen_m = float((Ft(vm) < -0.05).mean()); pen_t = float((Fm(vt) < -0.05).mean())
        cs_ = vs_arch(sgn)
        r["A4_clearance_mm"] = dict(temporalis_to_bone_outside_attachments=round(float(dBt[offt].min()), 3),
                                    masseter_to_bone_outside_attachments=round(float(dBm[offm].min()), 3),
                                    temporalis_to_teeth=round(float(dteeth_t.min()), 2), masseter_to_teeth=round(float(dteeth_m.min()), 2),
                                    masseter_to_temporalis_surfaces=round(float(dmt.min()), 3),
                                    masseter_vertices_inside_temporalis=pen_m, temporalis_vertices_inside_masseter=pen_t,
                                    temporalis_to_arch=round(float(cKDTree(cs_).query(vt)[0].min()), 3),
                                    deepest_into_bone_at_attachments_tem=round(float(-dBt.min()), 3),
                                    deepest_into_bone_at_attachments_mas=round(float(-dBm.min()), 3))
        # ---- A5: fibre angles to the Frankfurt plane, side view, face to the left (+ = rising backward)
        Pt = Mt["P"][0]; nt_, nw_, ns_ = Pt.shape[:3]
        tt = np.linspace(0, 1, nt_)[:, None, None] * np.ones((1, nw_, ns_ - 1))
        ss = np.linspace(0, 1, ns_ - 1)[None, None, :] * np.ones((nt_, nw_, 1))
        ww = np.arange(nw_)[None, :, None] * np.ones((nt_, 1, ns_ - 1))
        # the model's fibres in the same plate regions (Fig. 382 mapped to the head frame)
        im382 = Image.open(os.path.join(plates_dir or os.path.join(OUT, "gp"), "f382.png"))
        flipP = lambda P: np.c_[-np.asarray(P, float)[:, 0], -np.asarray(P, float)[:, 1]]
        mid = 0.5 * (Pt[..., 1:, :] + Pt[..., :-1, :])
        ang = {}
        for k, poly in F382_REGIONS.items():
            pa, psp = plate_orient(im382, poly)
            # plate direction (image, y up) to head frame: through the registration (flip, rotate), then face-left view
            dv = np.array([np.cos(np.radians(pa)), np.sin(np.radians(pa))])
            dm = T382[1] @ np.array([-dv[0], dv[1]])            # (dz, dy) in the head frame
            pa_fh = wrap180(np.degrees(np.arctan2(dm[1], -dm[0])))
            regz = apply(T382, flipP(poly))
            sel = inside(regz, mid[..., [2, 1]].reshape(-1, 2)).reshape(mid.shape[:3]) & (ww == nw_ - 1)
            if not sel.any():
                sel = inside(regz, mid[..., [2, 1]].reshape(-1, 2)).reshape(mid.shape[:3])
            ma, msp = fibre_angles_side(Pt, sel) if sel.any() else (np.nan, np.nan)
            ang["temporalis_" + k] = dict(model=round(ma, 1), model_spread=round(msp, 1), plate=round(pa_fh, 1), plate_spread=round(psp, 1),
                                          difference=round(wrap180(ma - pa_fh), 1), segments=int(sel.sum()))
        # masseter: Fig. 378 is not registered to the head frame (no landmarks of the bone show); its angles are given against
        # the drawn upper edge of the superficial portion (the arch's lower border), and the model's against its own arch border
        try:
            im378 = Image.open(os.path.join(plates_dir or os.path.join(OUT, "gp"), "h-0378.png")).crop(F378_CROP)
            e = np.array(F378_ORIGIN_EDGE, float); edge_img = np.degrees(np.arctan2(-(e[1, 1] - e[0, 1]), e[1, 0] - e[0, 0]))
        except Exception:
            im378 = None
        LBm = lower_border(B, sgn, np.linspace(35.0, 65.0, 13), xmin=47.0, ylo=-26.0, yhi=6.0)
        okb = ~np.isnan(LBm[:, 0]); pf = np.polyfit(LBm[okb, 2], LBm[okb, 1], 1)
        edge_model = float(np.degrees(np.arctan2(-pf[0], 1.0)))          # face left: the border's angle in the side view
        for j, (k, nmk) in enumerate((("deep", "deep"), ("superficial", "superficial"))):
            P = Mm["P"][j]; n1, n2, n3 = P.shape[:3]
            s_ = np.linspace(0, 1, n3 - 1)[None, None, :] * np.ones((n1, n2, 1))
            w_ = np.arange(n2)[None, :, None] * np.ones((n1, 1, n3 - 1))
            sel = (s_ > 0.2) & (s_ < 0.8) & (w_ == n2 - 1)
            ma, msp = fibre_angles_side(P, sel)
            d = dict(model_to_FH=round(ma, 1), model_spread=round(msp, 1), model_to_arch_border=round(wrap180(ma - edge_model), 1))
            if im378 is not None:
                pa, psp = plate_orient(im378, F378_REGIONS[nmk])
                d.update(plate_image_angle=round(pa, 1), plate_spread=round(psp, 1), plate_to_arch_border=round(wrap180(pa - edge_img), 1),
                         plate_to_FH_if_arch_as_model=round(wrap180(pa - edge_img + edge_model), 1))
                d["difference_via_arch"] = round(wrap180(d["model_to_arch_border"] - d["plate_to_arch_border"]), 1)
            ang["masseter_" + k] = d
        r["A5_angles_deg"] = ang
        log(sd, json.dumps({k: v for k, v in r.items()}, default=float)[:4000])
    # ---- left against right: the relief is not a mirror copy
    for nm in ("tem", "mas"):
        vl = built[nm, "L"][0]["v"]; vr = built[nm, "R"][0]["v"].copy(); vr[:, 0] *= -1
        d, _ = cKDTree(vl).query(vr)
        fl = built[nm, "L"][1]["fas"]; fr = built[nm, "R"][1]["fas"]
        R.setdefault("A2_left_vs_right", {})[nm] = dict(mean_mm=round(float(d.mean()), 2), p95_mm=round(float(np.percentile(d, 95)), 2),
                                                        max_mm=round(float(d.max()), 2),
                                                        fascicles_L=[len(x["t"]) + 1 for x in fl], fascicles_R=[len(x["t"]) + 1 for x in fr])
    import hashlib
    R["bone_sha256"] = {k: hashlib.sha256(open(os.path.join(OUT, "b", "%s_%s_D.npz" % (TAG, k)), "rb").read()).hexdigest() for k in ("skull", "jaw")}
    json.dump(R, open(os.path.join(OUT, "b", "muscle_checks.json"), "w"), indent=1, default=float)
    return R


# ====================================================================== the shaded renderer (T-muscle-2, G5): this file's own
# A check picture of muscle drawn matte reads as clay whatever its geometry. Here, and only for these sheets, the flesh is lit
# as the spec (B3) asks: wrap diffuse with the wrapped light reddened (light scattered in the flesh), an anisotropic GGX lobe
# whose highlight is drawn out across the fibres (fibres are fine cylinders; its tangent is the vertex's fibre tangent), a thin
# wet coat (a second, sharp isotropic lobe, F0 0.04), groove darkening, and the fibre striation finer than the mesh worked out
# per picture point from the across coordinate. Tendon: whiter, more strongly anisotropic, crimp banding (the fibres' tangent
# turned to and fro along their length). The bone is view.py's dry bone. Where a muscle is attached, the bone beside the margin
# takes the film's tint over 1.5 mm and, at a tendon, the tendon's striation fading over 3 mm.
CAV_DARK = 0.5                                    # a groove's bottom: linear albedo x0.5 (meatRef C2: x0.47-0.55, D01, B12)
SHADE = dict(wrap=0.4, flesh_rough=0.5, flesh_aniso=0.22, tendon_rough=0.28, tendon_aniso=0.5, coat=0.45, coat_rough=0.27,
             gloss_stria=0.3, gloss_ease=200)          # (repair F2: a broad sheen; the gloss sees the surface eased ~1 mm)


def _lin(c):
    c = np.clip(c, 0, 1); return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)


def _show(lam, s_px):
    return np.clip((lam * s_px - 1.5) / 2.0, 0.0, 1.0)


def stria(u, smm, s_px, tendon, seed=5):
    """the fibres' relief finer than the mesh (spec S1): its slope dh/du across the fibres at across coordinate u (mm), drawn
    out 40 times along them; bands finer than about two picture pixels are left out (they would only be speckle)"""
    out = np.zeros(len(u))
    for lam, amp, ten in ((0.42, 0.011, 0), (0.16, 0.004, 0), (0.09, 0.002, 0), (0.22, 0.02, 1), (0.085, 0.005, 1)):
        k = _show(lam, s_px)
        if k <= 0:
            continue
        e = lam / 8.0
        sl = (vnoise((u + e) / lam, smm / (40 * lam), seed + int(lam * 1000)) - vnoise((u - e) / lam, smm / (40 * lam), seed + int(lam * 1000))) / (2 * e)
        out += k * amp * sl * (tendon if ten else (1 - tendon))
    return out


def shaded(items, eye, size=560, frame=None, hollow=0.6, lights=None, ss=2, buffers=False, matte=False):
    """matte: the plain matte look (view.picture's lambert on the interpolated vertex colour; no striation, no gloss).
    items: [dict(kind='bone'|'muscle', v, f, A=per-vertex attributes for a muscle)]; eye: from the subject to the camera;
    frame: (centre, span mm). Returns a PIL image (and, with buffers, the per-pixel buffers at the final size)."""
    from PIL import Image
    import view
    N_ = size * ss
    eye_, right, up = view.camera(eye)
    allv = np.concatenate([it["v"] for it in items])
    c3 = (allv.max(0) + allv.min(0)) / 2 if frame is None else np.asarray(frame[0], float)
    if frame is None:
        X = (allv - c3) @ right; Y = (allv - c3) @ up; span = max(np.ptp(X), np.ptp(Y)) * 1.1
    else:
        span = frame[1]
    s = N_ / span
    zb = np.full(N_ * N_, -np.inf); who = np.full(N_ * N_, -1, np.int32); fid = np.zeros(N_ * N_, np.int64)
    W1 = np.zeros(N_ * N_, np.float32); W2 = np.zeros(N_ * N_, np.float32)
    rng = np.random.default_rng(7); spacing = 0.8 / s
    for m, it in enumerate(items):
        v, f = it["v"], it["f"]
        a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
        fn = np.cross(b - a, c - a); cc = (a + b + c) / 3
        keep = fn @ eye_ > 0
        qx = (cc - c3) @ right * s + N_ / 2; qy = N_ / 2 - (cc - c3) @ up * s; mg = 0.05 * N_
        keep &= (qx > -mg) & (qx < N_ + mg) & (qy > -mg) & (qy < N_ + mg)
        fi = np.where(keep)[0]
        if not len(fi):
            continue
        k = np.maximum(np.ceil(0.5 * np.linalg.norm(fn[fi], axis=1) / (0.5 * spacing ** 2)).astype(np.int64), 1)
        cuts = np.searchsorted(np.cumsum(k), np.arange(3_000_000, int(k.sum()), 3_000_000))
        for fc, kc in zip(np.split(fi, cuts), np.split(k, cuts)):
            if not len(fc):
                continue
            idx = np.repeat(fc, kc)
            r1 = np.sqrt(rng.random(len(idx), dtype=np.float32)); r2 = rng.random(len(idx), dtype=np.float32)
            w1 = r1 * (1 - r2); w2 = r1 * r2; w0 = 1 - w1 - w2
            g = f[idx]
            P = w0[:, None] * v[g[:, 0]] + w1[:, None] * v[g[:, 1]] + w2[:, None] * v[g[:, 2]]
            d = P - c3
            px = np.floor(d @ right * s + N_ / 2).astype(np.int64); py = np.floor(N_ / 2 - d @ up * s).astype(np.int64)
            pz = d @ eye_
            order = np.argsort(pz)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                x, y = px[order] + dx, py[order] + dy
                ok = (x >= 0) & (x < N_) & (y >= 0) & (y < N_)
                i = y[ok] * N_ + x[ok]; src = order[ok]
                near = pz[src] > zb[i]
                i, src = i[near], src[near]
                zb[i] = pz[src]; who[i] = m; fid[i] = idx[src]; W1[i] = w1[src]; W2[i] = w2[src]
    img = np.zeros((N_ * N_, 3), np.float32) + np.array(view.BG, np.float32) / 255.0
    nb = np.zeros((N_ * N_, 3), np.float32)
    L = lights or [(0.35 * right + 0.55 * up + 0.75 * eye_, np.array([1.0, 0.97, 0.92]) * 1.5),
                   (-0.5 * right + 0.2 * up + 0.6 * eye_, np.array([0.85, 0.9, 1.0]) * 0.4),
                   (-0.3 * right + 0.6 * up - 0.75 * eye_, np.array([0.8, 0.88, 1.0]) * 0.7)]
    L = [(np.asarray(l_[0], float) if len(l_) > 2 else np.asarray(l_[0], float) / np.linalg.norm(l_[0]), np.asarray(l_[1], float),
          len(l_) > 2) for l_ in L]                                  # (direction or, for a point light, its place; colour; point?)
    spec_img = np.zeros(N_ * N_, np.float32); mus = np.zeros(N_ * N_, bool)
    glue = np.zeros(N_ * N_, np.float32)                           # near an attachment line, on either side (0..1)
    marg = []                                                      # attached margins: points, kind (tendon), tangent, across u
    for it in items:
        if it["kind"] == "muscle":
            A = it["A"]; mm = (A["attached"] > 0.5) & (A["edge_mm"] < 0.6)
            if mm.any():
                marg.append((it["v"][mm], A["tendon"][mm].astype(float), A["tangent"][mm].astype(float), A["u_mm"][mm], A["s_mm"][mm]))
    if marg:
        MP = np.concatenate([q[0] for q in marg]); MT = np.concatenate([q[1] for q in marg]); MTa = np.concatenate([q[2] for q in marg])
        MU = np.concatenate([q[3] for q in marg]); MS = np.concatenate([q[4] for q in marg]); mtree = cKDTree(MP)
    for m, it in enumerate(items):
        pix = np.where(who == m)[0]
        if not len(pix):
            continue
        v, f = it["v"], it["f"]; g = f[fid[pix]]
        w1, w2 = W1[pix].astype(np.float64)[:, None], W2[pix].astype(np.float64)[:, None]; w0 = 1 - w1 - w2
        vn = it.get("vn")
        if vn is None:
            vn = it["vn"] = vertex_normals(v, f)
        lerp = lambda X: w0 * X[g[:, 0]] + w1 * X[g[:, 1]] + w2 * X[g[:, 2]]
        P = lerp(v); N = lerp(vn); N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
        if it["kind"] in ("bone", "plain"):
            if it["kind"] == "bone":
                col, Nb = view.bone(P, N, s)
                col = col / 255.0
            else:
                col = np.broadcast_to(np.asarray(it["col"], float) / 255.0, P.shape).copy(); Nb = N
            if marg:
                d, j = mtree.query(P, distance_upper_bound=3.2)
                ok = np.isfinite(d); jj = np.minimum(j, len(MP) - 1)
                ten = np.where(ok, MT[jj], 0.0); dd = np.where(ok, d, 9.0)
                tint = 1 - smoothstep(dd / 2.5)                    # the film's colour runs on, fading, 2.5 mm onto the bone
                glue[pix] = 1 - smoothstep(dd / 1.8)
                tg = FILM[None, :] + (0.5 * (TENDON_C + np.array(view_bone_rgb())) - FILM)[None, :] * ten[:, None]
                col = col + (tg - col) * tint[:, None]
                # a tendon's fibres run on into the bone's surface and become its grain (fading over 3 mm)
                k = np.clip(1 - dd / 3.0, 0, 1) * ten
                if (k > 0).any():
                    Ta = MTa[jj]; Ba = np.cross(Nb, Ta); Ba /= np.maximum(np.linalg.norm(Ba, axis=1, keepdims=True), 1e-9)
                    u = MU[jj] + ((P - MP[jj]) * Ba).sum(1)
                    sl = stria(u, MS[jj], s, np.ones(len(u)))
                    Nb = Nb - (k * sl * 1.6)[:, None] * Ba
                    Nb /= np.maximum(np.linalg.norm(Nb, axis=1, keepdims=True), 1e-9)
            key = L[0][0] if not L[0][2] else eye_; fill = L[1][0] if len(L) > 1 and not L[1][2] else eye_
            sh = 0.16 + 0.66 * np.clip(Nb @ key, 0, 1) ** 1.1 + 0.2 * np.clip(Nb @ fill, 0, 1)
            sh = sh * np.clip(0.55 + 0.45 * np.clip(Nb @ eye_, 0, 1) ** 0.5, 0, 1)
            hv = key + eye_; hv /= np.linalg.norm(hv)
            img[pix] = sh[:, None] * col + (20.0 / 255 * np.clip(Nb @ hv, 0, 1) ** 14)[:, None] * np.array([1.0, 0.98, 0.93])
            nb[pix] = np.c_[Nb @ right, Nb @ up, Nb @ eye_]
            continue
        A = it["A"]; mus[pix] = True
        if matte:
            col = lerp(A["color"].astype(np.float64))
            key = L[0][0] if not L[0][2] else eye_; fill = L[1][0] if len(L) > 1 and not L[1][2] else eye_
            sh = 0.16 + 0.66 * np.clip(N @ key, 0, 1) ** 1.1 + 0.2 * np.clip(N @ fill, 0, 1)
            sh = sh * np.clip(0.55 + 0.45 * np.clip(N @ eye_, 0, 1) ** 0.5, 0, 1)
            img[pix] = sh[:, None] * col
            nb[pix] = np.c_[N @ right, N @ up, N @ eye_]
            continue
        cd_ = lerp(A["cavity"].astype(np.float64)[:, None]) * CAV_DARK * (1 - lerp(A["film"].astype(np.float64)[:, None]))
        alb = _lin(lerp(A["color"].astype(np.float64))) * (1 - cd_)
        T = lerp(A["tangent"].astype(np.float64))
        Tn = lerp(A["tendon"].astype(np.float64)[:, None])[:, 0]
        cav = lerp(A["cavity"].astype(np.float64)[:, None])[:, 0]
        u = lerp(A["u_mm"].astype(np.float64)[:, None])[:, 0]; smm = lerp(A["s_mm"].astype(np.float64)[:, None])[:, 0]
        rj = lerp(A["rough"].astype(np.float64)[:, None])[:, 0]; aj = lerp(A["aniso"].astype(np.float64)[:, None])[:, 0]
        film = lerp(A["film"].astype(np.float64)[:, None])[:, 0]
        T -= (T * N).sum(1, keepdims=True) * N; T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
        Bt = np.cross(N, T)
        # striation: the normal tilted across the fibres; crimp: the tendon's fibres turned to and fro along their length
        sl = stria(u, smm, s, Tn)
        Np = N - sl[:, None] * Bt; Np /= np.linalg.norm(Np, axis=1, keepdims=True)
        lamc = 1.1
        phi = 0.09 * np.sin(2 * np.pi * smm / lamc + 2.5 * vnoise(u / 0.6, smm / 4.0, 77)) * Tn * _show(lamc, s)
        T2 = T * np.cos(phi)[:, None] + Bt * np.sin(phi)[:, None]
        T2 -= (T2 * Np).sum(1, keepdims=True) * Np; T2 /= np.maximum(np.linalg.norm(T2, axis=1, keepdims=True), 1e-9)
        B2 = np.cross(Np, T2)
        r = Tn * SHADE["tendon_rough"] + (1 - Tn) * (SHADE["flesh_rough"] + rj + 0.12 * cav)
        an = np.clip(Tn * SHADE["tendon_aniso"] + (1 - Tn) * (SHADE["flesh_aniso"] + aj), 0, 0.95)
        # the lobe stretched ALONG the strands, weakly (meatRef T5/f: highlights elongated 2-3 along the strands, untinted;
        # the spec's across-fibre stretch is overturned): rougher along the tangent than across
        al = r * r; aT = al * (1 + an); aB = np.maximum(al * (1 - an), 0.002)
        Vv = eye_; NV = np.clip(Np @ Vv, 1e-3, 1)
        # the tissue's gloss sees only a little of the striation (repair F2: needle glints along every striation band)
        # and not the sharp crests between the grooves either: the gloss follows the surface eased over about half a
        # millimetre (a wet film fills the grooves' edges), so a sheen is broad, never a needle
        if it.get("vns") is None:
            it["vns"] = smooth_on_mesh(v, f, vn, SHADE.get("gloss_ease", 40))
        Nsm = lerp(it["vns"]); Nsm /= np.maximum(np.linalg.norm(Nsm, axis=1, keepdims=True), 1e-12)
        Ns = Nsm + SHADE.get("gloss_stria", 0.3) * (Np - N); Ns /= np.linalg.norm(Ns, axis=1, keepdims=True)
        Nc = Nsm                                     # the wet coat follows the eased shape, not the striation: a broad sheen

        out = np.zeros((len(pix), 3)); spec = np.zeros(len(pix))
        wrap = SHADE["wrap"]; tint = _lin(np.array([0.71, 0.23, 0.18]))
        # (repair 2, H5: a muscle may carry its own coat, strength and roughness per vertex; the masseter's flatter face
        # needs a broader sheen to show one at all; muscles without them keep the common coat)
        cw_ = lerp(A["coat"].astype(np.float64)[:, None])[:, 0] if "coat" in A else SHADE["coat"]
        coat_w = cw_ * (1 - 0.4 * Tn) * (1 - film)
        ac = (lerp(A["coat_rough"].astype(np.float64)[:, None])[:, 0] if "coat_rough" in A else SHADE["coat_rough"]) ** 2
        for Ld, Lc, point in L:
            Ld = (Ld[None, :] - P) if point else np.broadcast_to(Ld, P.shape)
            Ld = Ld / np.linalg.norm(Ld, axis=1, keepdims=True)
            NL = (Np * Ld).sum(1)
            wr = np.clip((NL + wrap) / (1 + wrap), 0, 1); lam = np.clip(NL, 0, 1)
            diff = alb * wr[:, None] + (tint * (wr - lam)[:, None] * 0.3 * (1 - Tn)[:, None])
            H = Ld + Vv; H = H / np.linalg.norm(H, axis=1, keepdims=True)
            hT = (H * T2).sum(1); hB = (H * B2).sum(1); hN = (Ns * H).sum(1)
            D = 1.0 / (np.pi * aT * aB * ((hT / aT) ** 2 + (hB / aB) ** 2 + hN ** 2) ** 2)
            a_ = np.sqrt(aT * aB); NLc = np.clip(NL, 1e-3, 1)
            Vis = 0.5 / (NLc * np.sqrt(NV ** 2 * (1 - a_ ** 2) + a_ ** 2) + NV * np.sqrt(NLc ** 2 * (1 - a_ ** 2) + a_ ** 2))
            VH = np.clip(H @ Vv, 0, 1); F = 0.04 + 0.96 * (1 - VH) ** 5
            sp = D * Vis * F * lam * (1 + 1.5 * Tn) * (1 - film)
            NLk = np.clip((Nc * Ld).sum(1), 0, 1); hc = (Nc * H).sum(1)
            # the coat's lobe too drawn out along the strands (meatRef T5/f): rougher along the tangent than across
            anc = 0.8 * an; acT = ac * (1 + anc); acB = np.maximum(ac * (1 - anc), 0.002)
            Dc = 1.0 / (np.pi * acT * acB * (((H * T).sum(1) / acT) ** 2 + ((H * np.cross(N, T)).sum(1) / acB) ** 2 + hc ** 2) ** 2)
            Vc = 0.5 / (NLk * np.sqrt(NV ** 2 * (1 - ac) + ac) + NV * np.sqrt(NLk ** 2 * (1 - ac) + ac) + 1e-6)
            sc = Dc * Vc * F * NLk * coat_w
            out += (diff * (1 - 0.04 * coat_w)[:, None] + (sp + sc)[:, None]) * Lc[None, :]
            spec += (sp + sc) * Lc.mean()
        amb = alb * (0.10 + 0.06 * np.clip(N @ up, -1, 1))[:, None] * (1 - 0.55 * cav)[:, None]
        out += amb
        out = out / (1 + 0.35 * out)                                 # a soft shoulder (no hard clipping of highlights)
        img[pix] = _srgb(out); spec_img[pix] = spec
        glue[pix] = np.clip(1.6 * film, 0, 1)
        nb[pix] = np.c_[Np @ right, Np @ up, Np @ eye_]
    zb = zb.reshape(N_, N_); got = np.isfinite(zb)
    img = img.reshape(N_, N_, 3)
    if hollow > 0 and got.any():
        occ = view.occlusion(zb, nb.reshape(N_, N_, 3), got, s)
        # where a muscle lies glued onto bone the corner is filled by the film: no shadow line along the attachment (repair F3)
        occ = occ * (1 - 0.9 * ndimage.gaussian_filter(glue.reshape(N_, N_), 0.4 * s))
        img *= (1 - hollow * occ[..., None] * np.array([0.85, 0.89, 0.94]))
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if ss > 1:
        im = im.resize((size, size), Image.LANCZOS)
    if not buffers:
        return im
    bf = dict(spec=spec_img.reshape(N_, N_), muscle=mus.reshape(N_, N_), zb=zb, s=s, right=right, up=up, eye=eye_, c3=c3,
              who=who.reshape(N_, N_), fid=fid.reshape(N_, N_), w1=W1.reshape(N_, N_), w2=W2.reshape(N_, N_), img=img)
    return im, bf


# ====================================================================== the look's checks (spec section C; T-muscle-2 B1, B2, B3, B6)
LOOK_PATCH = {("tem", "flesh"): (-22.0, 60.0), ("tem", "tendon"): (22.0, 28.0), ("mas", "flesh"): (36.0, -42.0)}   # (z, y) aimed at


def pick_patch(v, n, A, sgn, zy, tendon=False, r=15.0):
    """the vertex nearest (z, y) on the outer face (normal outward) whose r mm round is all flesh (or all tendon) of one part,
    off margins"""
    ten = A["tendon"].astype(float); part = A["part"]
    tree = cKDTree(v)
    order = np.argsort(np.hypot(v[:, 2] - zy[0], v[:, 1] - zy[1]))
    # (repair 2: the masseter's tongues leave fewer rounds clean of tendon; a second, looser pass before giving up)
    for lim, share, ps in ((0.05, 0.97, 0.99), (0.15, 0.9, 0.95)):
        good = (n[:, 0] * sgn > 0.55) & (A["edge_mm"].astype(float) > min(8.0, 0.5 * r)) & ((ten > 1 - 2 * lim) if tendon else (ten < lim))
        for i in order[:80000:20]:
            if not good[i]:
                continue
            nb = tree.query_ball_point(v[i], r)
            nb = np.asarray(nb)[(n[nb] @ n[i]) > 0.3]
            if good[nb].mean() > share and (part[nb] == part[i]).mean() > ps:
                return i
    raise ValueError("no clean %.0f mm patch near %s" % (r, zy))


def patch_grid(v, n, A, c, r=15.0, h=0.1, base=False):
    """the surface round vertex c in its own frame (u across the fibres, s along them, h out of it), interpolated on a grid
    of h mm: (U, S, H grid, frame (centre, eu, es, nz), vertex mask). base: the surface without its strands (the relief taken
    back off along the normal), to see what the meshing alone left"""
    from scipy.interpolate import griddata
    P = v - (n * A["relief"].astype(float)[:, None] if base else 0.0)
    d = np.linalg.norm(v - v[c], axis=1); m = (d < r * 1.5) & ((n @ n[c]) > 0.3)
    nz = n[m & (d < r)].mean(0); nz /= np.linalg.norm(nz)
    es = A["tangent"].astype(float)[m & (d < r)].mean(0); es -= (es @ nz) * nz; es /= np.linalg.norm(es)
    eu = np.cross(nz, es)
    Q = P[m] - v[c]
    # only the outermost face (a deeper face of the same aspect, such as the deep masseter's under the superficial, left out)
    qu, qs, qh = Q @ eu, Q @ es, Q @ nz
    cell = (np.floor((qu + 2 * r) / 0.75).astype(np.int64) * 100000 + np.floor((qs + 2 * r) / 0.75).astype(np.int64))
    _, inv = np.unique(cell, return_inverse=True); inv = inv.ravel()
    top = np.full(inv.max() + 1, -np.inf); np.maximum.at(top, inv, qh)
    keep = qh > top[inv] - 1.2
    m = m.copy(); m[np.flatnonzero(m)[~keep]] = False; Q = Q[keep]
    g = np.arange(-r, r + 1e-9, h)
    U, S_ = np.meshgrid(g, g, indexing="ij")                      # axis 0: u (across), axis 1: s (along)
    Hg = griddata(np.c_[Q @ eu, Q @ es], Q @ nz, (U, S_), method="linear")
    Tg = A["tangent"].astype(float)[m]
    ang = griddata(np.c_[Q @ eu, Q @ es], np.arctan2(Tg @ eu, Tg @ es), (U, S_), method="nearest")
    patch_grid.fibre_angle = ang                                   # the local fibres' angle from the s axis (for M2)
    return U, S_, Hg, (v[c], eu, es, nz), m


def nblur(G, sig, inner=True):
    """a gaussian blur that ignores the grid's empty (nan) cells (normalised convolution); inner: cells within 1.5 sigma of an
    empty one left out (nan), so a patch's ragged border puts no false slopes into the checks"""
    ok = ~np.isnan(G)
    B = ndimage.gaussian_filter(np.where(ok, G, 0.0), sig) / np.maximum(ndimage.gaussian_filter(ok.astype(float), sig), 1e-9)
    if inner:
        B[~ndimage.binary_erosion(ok, iterations=max(int(1.5 * sig), 1), border_value=0)] = np.nan
    return B


def _ma(x, w):
    return ndimage.uniform_filter1d(x, w, axis=0, mode="nearest")


def height_checks(Hg, h=0.1):
    """spec M1-M3 on a grid of heights (axis 0 across the fibres, axis 1 along)"""
    ok = ~np.isnan(Hg).any(0)
    Hl = Hg[:, ok]                                                  # lines across the fibres, one per s
    det = Hl - _ma(Hl, int(20.0 / h))
    n_ = Hl.shape[0]; win = np.hanning(n_)[:, None]
    F = np.abs(np.fft.rfft(det * win, axis=0)) ** 2; fr = np.fft.rfftfreq(n_, h); Pm = F.mean(1)
    band = (fr >= 1 / 12.0) & (fr <= 2.0)
    b1 = (fr >= 1 / 12.0) & (fr < 1 / 2.5); b2 = (fr >= 1 / 2.5) & (fr <= 2.0)
    tot = Pm[band].sum()
    i = int(np.argmax(np.where(band, Pm, 0)))
    peak = (Pm * band)[max(i - 1, 0):i + 2].sum() / tot                 # the peak's own bins, within the band
    sm = ndimage.uniform_filter1d(Pm, 3)
    loc = lambda b: int(((sm[1:-1] > sm[:-2]) & (sm[1:-1] >= sm[2:]) & b[1:-1]).sum())
    M1 = dict(rms_mm=round(float(det.std()), 3), bundle_band_share=round(float(Pm[b1].sum() / tot), 3),
              fascicle_band_share=round(float(Pm[b2].sum() / tot), 3), finer_than_0p5mm_share=round(float(Pm[fr > 2].sum() / Pm[fr > 0].sum()), 3),
              largest_peak_share=round(float(peak), 3), largest_peak_period_mm=round(float(1 / fr[i]), 2),
              local_maxima_bundle_band=loc(b1), local_maxima_fascicle_band=loc(b2))
    # M2: the slope across against the slope along, of what is left once a 3 mm blur is taken off
    # (slopes taken along and across the local fibres: over a 30 mm patch of a fan they turn by 10-20 deg)
    G = Hg - nblur(Hg, 3.0 / h)
    gu, gs = np.gradient(G, h)
    a = getattr(patch_grid, "fibre_angle", None)
    a = np.zeros_like(G) if a is None or a.shape != G.shape else a
    g_al = gu * np.sin(a) + gs * np.cos(a); g_ac = gu * np.cos(a) - gs * np.sin(a)
    M2 = round(float(np.sqrt(np.nanmean(g_ac ** 2)) / np.sqrt(np.nanmean(g_al ** 2))), 2)
    # M3: grooves, the local minima across, each as deep as the mean of the crests on either side
    deps, gaps = [], []
    for k in range(0, det.shape[1], 5):
        x = det[:, k]
        mn = np.where((x[1:-1] < x[:-2]) & (x[1:-1] <= x[2:]))[0] + 1
        mx = np.where((x[1:-1] > x[:-2]) & (x[1:-1] >= x[2:]))[0] + 1
        if len(mx) < 2:
            continue
        good = []
        for q in mn:
            l = mx[mx < q]; r_ = mx[mx > q]
            if len(l) and len(r_):
                d = 0.5 * (x[l[-1]] + x[r_[0]]) - x[q]
                if d > 0.02:
                    deps.append(d); good.append(q)
        if len(good) > 2:
            gaps += list(np.diff(np.array(good) * h))
    deps = np.array(deps); gaps = np.array(gaps)
    M3 = dict(grooves=len(deps), median_mm=round(float(np.median(deps)), 3), p10_mm=round(float(np.percentile(deps, 10)), 3),
              p90_mm=round(float(np.percentile(deps, 90)), 3), p90_over_p10=round(float(np.percentile(deps, 90) / np.percentile(deps, 10)), 2),
              p95_mm=round(float(np.percentile(deps, 95)), 3), spacing_cv=round(float(gaps.std() / gaps.mean()), 2) if len(gaps) else None,
              spacing_median_mm=round(float(np.median(gaps)), 2) if len(gaps) else None)
    return M1, M2, M3


def voxel_period(Hg, h=0.1, per=None):
    """amplitude (mm) of the height at the field grid's period, along and across, and the rms between 0.4 and 6 mm periods,
    once a 2 mm blur is taken off"""
    per = per or H
    G = Hg - nblur(Hg, 2.0 / h)
    # the patch is a disc (NaN outside): the square inside it, with any odd hole set to the local level (it was all dropped)
    ok = ~np.isnan(G); c0, c1 = [int(round(np.mean(np.flatnonzero(ok.any(1 - a_))))) for a_ in (0, 1)]
    hw = int(0.5 * min(ok.any(1).sum(), ok.any(0).sum()) / np.sqrt(2)) - 2
    G = np.nan_to_num(G[c0 - hw:c0 + hw, c1 - hw:c1 + hw], nan=0.0)
    out = {"square_mm": round(2 * hw * h, 1)}
    for ax, nm in ((0, "across"), (1, "along")):
        X = np.moveaxis(G, ax, 0)
        n_ = X.shape[0]; win = np.hanning(n_)[:, None]
        F = np.abs(np.fft.rfft(X * win, axis=0)) / (win.sum() / 2); fr = np.fft.rfftfreq(n_, h)
        k = int(np.argmin(np.abs(fr - 1 / per)))
        out["amplitude_at_%.1fmm_%s" % (per, nm)] = round(float(F[k - 1:k + 2].mean(1).max()), 4)
        b = (fr >= 1 / 6.0) & (fr <= 1 / 0.4)
        out["rms_0.4_to_6mm_%s" % nm] = round(float(np.sqrt((F[b] ** 2).sum(0).mean() / 2)), 4)
    return out


def flat_patch(v, f, n, A, c, r=15.0):
    """the patch round vertex c laid flat in its own frame (x across, y along, z its height less a 3 mm blur), as a muscle item"""
    U, S_, Hg, (c0, eu, es, nz), m = patch_grid(v, n, A, c, r)
    trend = np.nan_to_num(nblur(Hg, 30, inner=False), nan=float(np.nanmean(Hg)))
    Q = v - c0; u, s_, hh = Q @ eu, Q @ es, Q @ nz
    tr = ndimage.map_coordinates(trend, [(u + r) / 0.1, (s_ + r) / 0.1], order=1, mode="nearest")
    keep = m & (np.abs(u) < r) & (np.abs(s_) < r)
    fk = f[keep[f].all(1)]
    idx = -np.ones(len(v), np.int64); idx[np.where(keep)[0]] = np.arange(keep.sum())
    Vf = np.c_[u, s_, hh - tr][keep]
    Af = {k: np.asarray(x)[keep] for k, x in A.items() if np.ndim(x) and len(x) == len(v)}
    Tg = A["tangent"].astype(float)[keep]; Af["tangent"] = np.c_[Tg @ eu, Tg @ es, Tg @ nz].astype(np.float16)
    fk = idx[fk]
    if np.linalg.det(np.array([eu, es, nz])) < 0:          # a left-handed frame mirrors the patch: keep its faces outward
        fk = fk[:, ::-1]
    return dict(kind="muscle", v=Vf, f=fk, A=Af)


def render_checks(item, s_px_span=30.0):
    """spec R1, R2, R4 on a flat patch: R1 one point light at 45 deg (eye at 45 deg the other side, so the highlight falls
    mid-patch), the specular blob over half its peak (after a 0.3 mm blur), its moments in the patch's own (across, along)
    coordinates; R2 luminance spread under the sheets' three lights; R4 mean luminance in the grooves over that on the crowns"""
    out = {}
    q = 0.7 * s_px_span
    for nm, eye, lp in (("light_plane_across_fibres", (-1, 0, 1), (q, 0.0, q)), ("light_plane_along_fibres", (0, -1, 1), (0.0, q, q))):
        im, bf = shaded([item], eye, 400, (np.zeros(3), s_px_span), hollow=0.0, lights=[(lp, np.array([1.0, 1.0, 1.0]) * 3.0, "point")], ss=1, buffers=True)
        # (the peak taken from the highlight blurred over 1 mm: the 0.3 mm blur alone leaves single glints from the striation
        # as the peak, and half of a glint's height cuts the streak into specks)
        sp = ndimage.gaussian_filter(bf["spec"], 0.3 * bf["s"]); mk = bf["muscle"]
        thr = 0.5 * ndimage.gaussian_filter(bf["spec"], 1.0 * bf["s"])[mk].max()
        lab, k = ndimage.label((sp > thr) & mk)
        if not k:
            continue
        j = 1 + int(np.argmax(ndimage.sum(np.ones_like(sp), lab, range(1, k + 1))))
        yy, xx = np.where(lab == j)
        P = _pix_points(item, bf, yy, xx)
        cu, cs = np.var(P[:, 0]), np.var(P[:, 1])
        out["R1_" + nm] = dict(along_over_across=round(float(np.sqrt(cs / cu)), 2), across_over_along=round(float(np.sqrt(cu / cs)), 2), blob_mm=(round(float(4 * np.sqrt(cu)), 1), round(float(4 * np.sqrt(cs)), 1)),
                               touches_patch_edge=bool((np.abs(P[:, :2]) > 0.9 * s_px_span / 2).any()))
    im, bf = shaded([item], (0, 0, 1), 400, (np.zeros(3), s_px_span), hollow=0.0, ss=1, buffers=True)
    img = bf["img"]; mk = bf["muscle"].copy()
    lum = 0.2126 * img[..., 0] + 0.7152 * img[..., 1] + 0.0722 * img[..., 2]
    yy, xx = np.where(mk)
    P = _pix_points(item, bf, yy, xx)
    inner = (np.abs(P[:, 0]) < 0.43 * s_px_span) & (np.abs(P[:, 1]) < 0.43 * s_px_span)
    L_ = lum[yy, xx][inner]
    out["R2_luminance_cv"] = round(float(L_.std() / L_.mean()), 3)
    # highlight coverage as meatRef T5 measured it: L* over the local (2 mm) median by 30 and chroma under half the local
    from skimage.color import rgb2lab
    lab = rgb2lab(np.clip(img, 0, 1)); Ls = lab[..., 0]; ch = np.hypot(lab[..., 1], lab[..., 2])
    w_ = max(int(2.0 * bf["s"]), 3)
    Lm = ndimage.median_filter(np.where(mk, Ls, np.nan_to_num(np.median(Ls[mk]))), w_); cm = ndimage.median_filter(ch, w_)
    hl = mk & (Ls > Lm + 30) & (ch < 0.5 * cm)
    out["S_highlight_coverage_pct"] = round(float(100 * hl[yy, xx][inner].mean()), 2)
    hgt = np.full(mk.shape, np.nan); hgt[yy, xx] = P[:, 2]
    # grooves and crowns as M3 finds them: along each row (across the fibres) the local minima at least 0.02 mm below the
    # mean of the crests either side, and those crests; luminance read there (a pixel either side too)
    hs = ndimage.gaussian_filter(np.nan_to_num(hgt, nan=0.0), 1.0)
    gr = np.zeros(mk.shape, bool); cr = np.zeros(mk.shape, bool)
    for y in range(0, mk.shape[0], 2):
        row = hs[y]; ok = mk[y]
        mn = np.where((row[1:-1] < row[:-2]) & (row[1:-1] <= row[2:]) & ok[1:-1])[0] + 1
        mx = np.where((row[1:-1] > row[:-2]) & (row[1:-1] >= row[2:]) & ok[1:-1])[0] + 1
        for q in mn:
            l_ = mx[mx < q]; r_ = mx[mx > q]
            if len(l_) and len(r_) and 0.5 * (row[l_[-1]] + row[r_[0]]) - row[q] > 0.02:
                gr[y, max(q - 1, 0):q + 2] = True; cr[y, l_[-1]] = cr[y, r_[0]] = True
    gr &= mk; cr &= mk
    # (in linear luminance, as meatRef C2 measured its x0.47-0.55; the sRGB ratio is given beside it)
    ll = _lin(img); lin = 0.2126 * ll[..., 0] + 0.7152 * ll[..., 1] + 0.0722 * ll[..., 2]
    out["R4_cavity_contrast"] = round(float(lin[gr].mean() / lin[cr].mean()), 3)
    out["R4_cavity_contrast_srgb"] = round(float(lum[gr].mean() / lum[cr].mean()), 3)
    out["R4_groove_and_crown_pixels"] = (int(gr.sum()), int(cr.sum()))
    return out, im


def _pix_points(item, bf, yy, xx):
    v, f = item["v"], item["f"]
    g = f[bf["fid"][yy, xx]]; w1 = bf["w1"][yy, xx][:, None]; w2 = bf["w2"][yy, xx][:, None]
    return (1 - w1 - w2) * v[g[:, 0]] + w1 * v[g[:, 1]] + w2 * v[g[:, 2]]


def margin_checks(v, f, A, bone):
    """B6 at every attached margin: the muscle's height over the bone 0.2-0.4 mm in from its edge (edge thickness), the slope
    from the edge to 1 mm in (contact angle, as the secant), the height right at the line (step), and how far the colour
    takes to pass from 10 % to 90 % of the way from the bone's to the muscle's own (spread)"""
    n = vertex_normals(v, f); gb = bone.grad(v); dB = bone.d(v)
    aw = A["attached"].astype(float) > 0.5; ex = A["edge_mm"].astype(float); ten = A["tendon"].astype(float) > 0.5
    outw = (n * gb).sum(1) > 0.3
    # a part's edge that lies on the muscle's other part (the superficial masseter over the deep) is not on bone: left out
    part = A["part"].astype(int)
    if part.max() > 0:
        for p_ in np.unique(part):
            o_ = part != p_
            if o_.any():
                dpo = cKDTree(v[o_]).query(v[part == p_], distance_upper_bound=8.0)[0]
                sel_ = np.flatnonzero(part == p_)[dpo < dB[part == p_] - 0.2]
                outw[sel_] = False
    out = {}
    for nm, k in (("fleshy", ~ten), ("tendinous", ten)):
        sel = aw & outw & k
        if sel.sum() < 50:
            continue
        e1 = sel & (ex > 0.2) & (ex < 0.4); e2 = sel & (ex > 0.5) & (ex < 1.5); e0 = sel & (ex < 0.3)
        ang = np.degrees(np.arctan2(np.maximum(dB[e2], 0), ex[e2]))
        # (repair 2, H4: the fade read on the outer face going away from the attached line, attached or not, by the straight
        # distance to that line, as the eye reads it; the edge distance along the sheet had left far bins empty or mixed
        # (a face lying over another attached part), and the spread NaN). Medians per 0.25 mm bin.
        e_line = np.flatnonzero(sel & (ex < 0.3))
        fz = np.flatnonzero(outw & k)
        exs = cKDTree(v[e_line]).query(v[fz], distance_upper_bound=8.0)[0] if len(e_line) else np.full(len(fz), np.inf)
        film = A["film"].astype(float)[fz]
        bins = np.arange(0, 6.01, 0.25); fb = [np.median(film[(exs >= a) & (exs < a + 0.25)]) if ((exs >= a) & (exs < a + 0.25)).sum() > 5 else np.nan for a in bins[:-1]]
        fb = np.array(fb); cen = bins[:-1] + 0.125
        x90 = cen[np.nanargmax(fb < 0.9)] if (fb < 0.9).any() else np.nan; x10 = cen[np.nanargmax(fb < 0.1)] if (fb < 0.1).any() else np.nan
        out[nm] = dict(margin_vertices=int(e0.sum()), edge_thickness_mm=dict(median=round(float(np.median(dB[e1])), 3), p99=round(float(np.percentile(dB[e1], 99)), 3), max=round(float(dB[e1].max()), 3)),
                       contact_angle_deg=dict(median=round(float(np.median(ang)), 1), p99=round(float(np.percentile(ang, 99)), 1), max=round(float(ang.max()), 1)),
                       step_at_line_mm=dict(p99=round(float(np.percentile(dB[e0], 99)), 3), max=round(float(dB[e0].max()), 3)),
                       colour_spread_on_muscle_mm=round(float(x10 - x90), 2), bone_side_tint_mm=1.6)
    return out


RED_WHITE = float(np.linalg.norm(np.array(LOOK["temporalis"]["base"]) / 255.0 - TENDON_C))   # the red-white difference


def colour_gradients(v, f, A, n=40000, seed=3, bone=None):
    """B7 on the mesh: the colour change over 0.5 mm (pairs of points 0.35-0.65 mm apart, scaled to 0.5 mm) as a share of the
    red-white difference, by border: flesh/tendon (either point 0.05 < tendon < 0.95), fascicle/fascicle (both flesh, other
    fascicles), elsewhere; only pairs on the same face (normals within 25 deg, not the top and underside of a thinned edge);
    and muscle/bone at the attached edge, where the muscle's edge colour meets the bone's tinted one"""
    rng = np.random.default_rng(seed); col = A["color"].astype(float); Tn = A["tendon"].astype(float)
    fa = A["fascicle"].astype(float); i0 = rng.choice(len(v), min(n, len(v)), replace=False)
    tree = cKDTree(v); out = {}
    pr = tree.query_ball_point(v[i0], 0.65)
    I = np.repeat(i0, [len(q) for q in pr]); J = np.concatenate([np.asarray(q, int) for q in pr])
    nv = vertex_normals(v, f)
    d = np.linalg.norm(v[I] - v[J], axis=1); k = (d > 0.35) & ((nv[I] * nv[J]).sum(1) > 0.9)
    if bone is not None:                                 # the faces one sees (away from the bone), not the face lying on it
        k &= (nv[I] * bone.grad(v[I])).sum(1) > 0.3
    I, J, d = I[k], J[k], d[k]
    g = np.linalg.norm(col[I] - col[J], axis=1) / d * 0.5 / RED_WHITE
    ft = ((Tn[I] > 0.05) & (Tn[I] < 0.95)) | ((Tn[J] > 0.05) & (Tn[J] < 0.95)) | ((Tn[I] - 0.5) * (Tn[J] - 0.5) < 0)
    ff = ~ft & (Tn[I] < 0.05) & (Tn[J] < 0.05) & (np.abs(fa[I] - fa[J]) > 1e-3)
    for nm, sel in (("flesh_tendon", ft), ("fascicle_fascicle", ff), ("other", ~ft & ~ff)):
        if sel.sum() > 20:
            out[nm] = dict(p99=round(float(np.percentile(g[sel], 99)), 3), max=round(float(g[sel].max()), 3), pairs=int(sel.sum()))
    # the renderer's groove darkening (light kept out of the grooves, not a colour of the tissue), for the record
    cd_ = A["cavity"].astype(float)[:, None] * CAV_DARK * (1 - A["film"].astype(float)[:, None])
    c2 = _srgb(_lin(col) * (1 - cd_))
    g2 = np.linalg.norm(c2[I] - c2[J], axis=1) / d * 0.5 / RED_WHITE
    out["with_groove_darkening_all_pairs"] = dict(p99=round(float(np.percentile(g2, 99)), 3), max=round(float(g2.max()), 3))
    # muscle/bone: at the line the bone shows the edge's own target colour (tint 1), so the step is |edge colour - target|;
    # beyond it the tint fades by smoothstep over 2.5 mm (steepest 0.3 of the target-bone difference per 0.5 mm)
    e = (A["attached"].astype(float) > 0.5) & (A["edge_mm"].astype(float) < 0.25)
    if e.any():
        tg = FILM[None, :] + (0.5 * (TENDON_C + np.array(view_bone_rgb())) - FILM)[None, :] * Tn[e][:, None]
        step = np.linalg.norm(col[e] - tg, axis=1) / RED_WHITE
        fade = 0.3 * np.linalg.norm(tg - np.array(view_bone_rgb())[None, :], axis=1) / RED_WHITE
        out["muscle_bone"] = dict(step_at_line_p99=round(float(np.percentile(step, 99)), 3), step_max=round(float(step.max()), 3),
                                  bone_side_fade_max=round(float(fade.max()), 3))
    return out


def stair_amplitude(lines, px_mm, win_mm=1.0):
    """B7: the stair of a picture's border lines (skimage contours, sub-pixel): each point's distance from the line smoothed
    over win_mm along it; returns the p99 and max in mm"""
    res = []
    for c in lines:
        if len(c) < 40:
            continue
        c = c * px_mm; sl = np.r_[0, np.cumsum(np.linalg.norm(np.diff(c, axis=0), axis=1))]
        if sl[-1] < 4 * win_mm:
            continue
        uu = np.arange(0, sl[-1], 0.02); cx = np.interp(uu, sl, c[:, 0]); cy = np.interp(uu, sl, c[:, 1])
        sg = win_mm / 0.02 / 2.355
        sx = ndimage.gaussian_filter1d(cx, sg, mode="nearest"); sy = ndimage.gaussian_filter1d(cy, sg, mode="nearest")
        tx = np.gradient(sx); ty = np.gradient(sy); tn = np.hypot(tx, ty) + 1e-12
        r = np.abs(((cx - sx) * ty - (cy - sy) * tx) / tn)
        cut = int(2 * sg) + 1; r = r[cut:-cut] if len(r) > 2 * cut + 10 else r
        res.append(r)
    if not res:
        return None
    r = np.concatenate(res)
    return dict(p99=round(float(np.percentile(r, 99)), 3), max=round(float(r.max()), 3))


def picture_borders(items, bf, mi):
    """B7 in a close-up picture (buffers at the supersampled size): the muscle's outline against the bone and the tendon's
    0.5 line, as sub-pixel contours"""
    from skimage import measure
    who = bf["who"]; mus = who == mi; s = bf["s"]; it = items[mi]
    T = np.zeros(who.shape)
    yy, xx = np.where(mus)
    if len(yy):
        g = it["f"][bf["fid"][yy, xx]]; w1 = bf["w1"][yy, xx]; w2 = bf["w2"][yy, xx]; t = it["A"]["tendon"].astype(float)
        T[yy, xx] = (1 - w1 - w2) * t[g[:, 0]] + w1 * t[g[:, 1]] + w2 * t[g[:, 2]]
    inside = ndimage.binary_erosion(mus, iterations=3)
    H, W = who.shape; m = 4
    frame = np.zeros(who.shape, bool); frame[m:H - m, m:W - m] = True

    def runs(cs, ok):
        out = []
        for c in cs:
            k = ok[np.clip(np.round(c[:, 0]).astype(int), 0, H - 1), np.clip(np.round(c[:, 1]).astype(int), 0, W - 1)]
            ed = np.flatnonzero(np.diff(np.r_[0, k.astype(np.int8), 0]))
            out += [c[a:b] for a, b in zip(ed[::2], ed[1::2])]
        return out
    tl = runs(measure.find_contours(np.where(mus, T, np.nan), 0.5), inside & frame)
    # the outline: only where the muscle meets bone behind it (not the frame's edge, nor the background)
    bone_near = ndimage.binary_dilation((who >= 0) & ~mus, iterations=4) & ndimage.binary_dilation(mus, iterations=4)
    ol = runs(measure.find_contours(ndimage.gaussian_filter(mus.astype(float), 0.7), 0.5), bone_near & frame & ~ndimage.binary_dilation(who < 0, iterations=4))
    return dict(tendon_line=stair_amplitude(tl, 1.0 / s), outline=stair_amplitude(ol, 1.0 / s), px_mm=round(1.0 / s, 4))


def look_checks(log=print, plates_dir=None):
    """B1-B3, B6 numbers into $SCRATCH_OUT/b/muscle_look.json; the flat patches' renders beside it"""
    from PIL import Image
    B = Bone(); R = {}
    sd382, white, outl, T382 = plate382_white(B, plates_dir)
    pics = {}
    for sd, sgn in (("L", 1), ("R", -1)):
        r = R[sd] = {}
        for nm in ("tem", "mas"):
            z = np.load(os.path.join(OUT, "b", "mus_%s_%s.npz" % (nm, sd))); A = {k: z[k] for k in z.files}
            v = A["v"].astype(np.float64); f = A["f"].astype(np.int64); n = vertex_normals(v, f)
            for kind in ("flesh", "tendon"):
                if (nm, kind) not in LOOK_PATCH:
                    continue
                rr = 6.0 if kind == "tendon" else (10.0 if nm == "mas" else 15.0)
                c = pick_patch(v, n, A, sgn, LOOK_PATCH[nm, kind], tendon=(kind == "tendon"), r=rr)
                U, S_, Hg, fr, m = patch_grid(v, n, A, c, rr)
                key = "%s_%s" % (nm, kind)
                if kind == "flesh":
                    M1, M2, M3 = height_checks(Hg)
                    r[key] = dict(centre=v[c].round(1).tolist(), M1_spectrum_across=M1, M2_across_over_along_gradient=M2, M3_grooves=M3)
                    r[key]["B2_terraces_final_surface"] = voxel_period(Hg)
                    r[key]["B2_terraces_base_surface"] = voxel_period(patch_grid(v, n, A, c, rr, base=True)[2])
                    it = flat_patch(v, f, n, A, c, rr)
                    rc, im = render_checks(it, 2 * rr)
                    r[key].update(rc); pics[sd, key] = im
                else:
                    G = Hg - nblur(Hg, 2.0 / 0.1)
                    gu, gs = np.gradient(G, 0.1); a_ = patch_grid.fibre_angle
                    g_al = gu * np.sin(a_) + gs * np.cos(a_); g_ac = gu * np.cos(a_) - gs * np.sin(a_)
                    r[key] = dict(centre=v[c].round(1).tolist(), across_over_along_gradient=round(float(np.sqrt(np.nanmean(g_ac ** 2) / np.nanmean(g_al ** 2))), 2),
                                  rms_across_mm=round(float(np.nanstd(G)), 3), B2=voxel_period(Hg))
            r[nm + "_margins_B6"] = margin_checks(v, f, A, B)
            r[nm + "_colour_B7"] = colour_gradients(v, f, A, bone=B)
            if nm == "tem":
                r["B3_tendon"] = tendon_vs_plate(v, f, A, n, sgn, white, outl, T382)
        log(sd, json.dumps(r, default=float)[:3000])
    json.dump(R, open(os.path.join(OUT, "b", "muscle_look.json"), "w"), indent=1, default=float)
    return R, pics


def tendon_vs_plate(v, f, A, n, sgn, white, outl, T):
    """side view, outer faces: the model's tendon against Fig. 382's white (IoU), the tendon's share of the muscle (model and
    plate), and how wide the flesh is between the tendon and the muscle's upper, front and hind margins"""
    lo, hi, h = (-70.0, -30.0), (80.0, 100.0), 0.25
    fo = f[(n[f].mean(1)[:, 0] * sgn) > 0.0]
    ten = A["tendon"].astype(float)[fo].mean(1) > 0.5
    mall, lo_, _ = side_mask(v, fo, h=h, lo=lo, hi=hi)
    mten = side_mask(v, fo[ten], h=h, lo=lo, hi=hi)[0]
    W_, H_ = mall.shape[1], mall.shape[0]
    zz = lo[0] + (np.arange(W_) + 0.5) * h; yy = lo[1] + (np.arange(H_) + 0.5) * h
    Z, Y = np.meshgrid(zz, yy)
    s_, R_, t_ = T
    A_ = ((np.c_[Z.ravel(), Y.ravel()] - t_) @ R_) / s_
    wpl = ndimage.map_coordinates(white.astype(float), [-A_[:, 1], -A_[:, 0]], order=1, cval=0).reshape(Z.shape) > 0.5
    opl = ndimage.map_coordinates(outl.astype(float), [-A_[:, 1], -A_[:, 0]], order=1, cval=0).reshape(Z.shape) > 0.5
    iou = (mten & wpl).sum() / max((mten | wpl).sum(), 1)
    # flesh between the tendon and the margin, above the arch (y > 6): the least distance from the outline to the tendon
    dt = ndimage.distance_transform_edt(~mten) * h
    edge = mall & ~ndimage.binary_erosion(mall)
    ring = {}
    for nm, sel in (("upper", (Y > 45)), ("front", (Y > 6) & (Y <= 45) & (Z > 30)), ("hind", (Y > 6) & (Y <= 45) & (Z < 0))):
        e = edge & sel
        ring[nm] = round(float(dt[e].min()), 1) if e.any() else None
    dtp = ndimage.distance_transform_edt(~wpl) * h; ep = opl & ~ndimage.binary_erosion(opl)
    ringp = {nm: (round(float(dtp[ep & sel].min()), 1) if (ep & sel).any() else None) for nm, sel in
             (("upper", (Y > 45)), ("front", (Y > 6) & (Y <= 45) & (Z > 30)), ("hind", (Y > 6) & (Y <= 45) & (Z < 0)))}
    return dict(IoU_with_fig382_white=round(float(iou), 3), share_model=round(float(mten.sum() / mall.sum()), 3),
                share_plate=round(float(wpl.sum() / opl.sum()), 3), flesh_between_tendon_and_margin_mm_model=ring,
                same_on_plate_mm=ringp)


# ====================================================================== pictures (sheets, each with Gray's plate beside it)
def bone_mesh(kind):
    """the bone's surface from its field (cached beside it)"""
    key = os.path.join(OUT, "b", "%s_m_%s_None_None.npz" % (TAG, kind))
    if os.path.exists(key):
        z = np.load(key); return z["v"], z["f"]
    Z = np.load(os.path.join(OUT, "b", "%s_%s_D.npz" % (TAG, kind))); D = np.pad(Z["D"].astype(np.float32), 1, constant_values=6.0)
    h = float(Z["h"]); v, f = sdf.mesh(D, np.asarray(Z["lo"], float) - h, h); v = sdf.taubin(v, f, 6)
    np.savez(key, v=v.astype(np.float32), f=f.astype(np.int32)); return v, f


def save_small(im, path, cap=395000):
    from PIL import Image
    q = 90
    while True:
        im.save(path, quality=q)
        if os.path.getsize(path) < cap or q < 40:
            break
        q -= 6
        if q < 66:
            im = im.resize((im.size[0] * 9 // 10, im.size[1] * 9 // 10), Image.LANCZOS)
    return path, os.path.getsize(path)


def outline_panel(plate_img, T, zr, yr, lines, k=4.0, mirror=False):
    """the plate drawn in the head frame (side view, face to the left) with outlines over it: lines [(points (z, y), rgb)]"""
    from PIL import ImageDraw, ImageOps
    im = warp_plate(plate_img, T, zr, yr, k)
    d = ImageDraw.Draw(im)
    for P, col in lines:
        q = to_px(np.r_[P, P[:1]], zr, yr, k)
        d.line([tuple(p) for p in q], fill=col, width=3)
    return ImageOps.mirror(im) if mirror else im


def render(plates_dir, prev=None, log=print, N=560, only=None):
    """the sheets of T-muscle-2 into $SCRATCH_OUT/pics/muscle_*.jpg: shaded (this file's renderer) beside Gray's plates, plain
    matte (view.py) for the geometry alone, and, where prev (a directory of the previous attempt's meshes and bone) is given, the
    previous attempt in the same matte light and the same frame"""
    from PIL import Image, ImageOps
    import view, teeth
    B = Bone(); info = pickle.load(open(os.path.join(OUT, "b", "%s_info.pkl" % TAG), "rb"))
    vs, fs = bone_mesh("skull"); vj, fj = bone_mesh("jaw")
    TE = [(w, ff, (238, 232, 214)) for upper in (True, False) for nm, sd, w, ff in teeth.stand(info["sockU"] if upper else info["sockL"], upper, h=0.2)]
    bone = [(vs, fs, view.BONE), (vj, fj, view.BONE)] + TE
    M = {}
    for nm in ("tem", "mas"):
        for sd in ("L", "R"):
            z = np.load(os.path.join(OUT, "b", "mus_%s_%s.npz" % (nm, sd))); M[nm, sd] = {k: z[k] for k in z.files}
    MI = {k: dict(kind="muscle", v=M[k]["v"].astype(np.float64), f=M[k]["f"].astype(np.int64), A=M[k]) for k in M}
    c_ = vs[fs].mean(1)
    lbz = np.interp(c_[:, 2], [12, 40, 52, 62], [-8, -8, -16, -20])
    cut = ~((np.abs(c_[:, 0]) > 55) & (c_[:, 2] > 14) & (c_[:, 2] < 54) & (c_[:, 1] > lbz - 3) & (c_[:, 1] < 5))      # the arch alone
    SB = [dict(kind="bone", v=vs, f=fs), dict(kind="bone", v=vj, f=fj)] + [dict(kind="plain", v=w, f=ff, col=c) for w, ff, c in TE]
    SBcut = [dict(kind="bone", v=vs, f=fs[cut])] + SB[1:]
    mus = lambda keys, MM=M: sum([muscle_meshes(MM[k]["v"], MM[k]["f"], MM[k]) for k in keys], [])
    allk = [("tem", "L"), ("mas", "L"), ("tem", "R"), ("mas", "R")]
    P_ = None
    if prev:
        ptag = os.environ.get("PREV_TAG", "M05")
        P_ = dict(bone=[], M={})
        for kind in ("skull", "jaw"):
            z = np.load(os.path.join(prev, "%s_m_%s_None_None.npz" % (ptag, kind))); P_["bone"].append((z["v"], z["f"], view.BONE))
        for k in allk:
            z = np.load(os.path.join(prev, "mus_%s_%s.npz" % k)); P_["M"][k] = {q: z[q] for q in z.files}
        pv, pf = P_["bone"][0][:2]; pc = pv[pf].mean(1)
        plb = np.interp(pc[:, 2], [12, 40, 52, 62], [-8, -8, -16, -20])
        pcut = ~((np.abs(pc[:, 0]) > 55) & (pc[:, 2] > 14) & (pc[:, 2] < 54) & (pc[:, 1] > plb - 3) & (pc[:, 1] < 5))
        P_["cut"] = [(pv, pf[pcut], view.BONE), P_["bone"][1]] + TE
        P_["bone"] += TE
    pl = lambda n: Image.open(os.path.join(plates_dir, n)).convert("RGB")
    f382 = pl("f382.png"); f378 = pl("h-0378.png").crop(F378_CROP); f383 = pl("f383.png"); f176 = pl("Gray176.png")
    T382, O382, _, _ = plate382(B)
    sh_ = lambda items, e, c, sp: shaded(items, e, N, (np.array(c, float), sp))
    mt_ = lambda keys, e, c, sp, bb=None: view.picture((bb or bone) + mus(keys), e, N, frame=(np.array(c, float), sp))
    pv_ = lambda keys, e, c, sp, cutb=False: view.picture((P_["cut"] if cutb else P_["bone"]) + mus(keys, P_["M"]), e, N, frame=(np.array(c, float), sp))
    out = []
    zr, yr = (-75.0, 95.0), (-80.0, 95.0)
    want = lambda nm: only is None or nm in only

    def model_outline(key):
        mk, lo, h = side_mask(M[key]["v"], M[key]["f"]); return outline_of(mk, lo, h)
    for sd, sgn, e in (("L", 1, (1, 0, 0)), ("R", -1, (-1, 0, 0))):
        if not want("side_" + sd):
            continue
        im = sh_(SB + [MI[k] for k in allk], e, (sgn * 10, 10, 15), 205)
        ov = outline_panel(f382, T382, zr, yr, [(O382, (0, 150, 0)), (model_outline(("tem", sd)), (20, 60, 220))], mirror=(sgn < 0))
        P382 = ImageOps.mirror(f382) if sgn < 0 else f382
        P378 = ImageOps.mirror(f378) if sgn < 0 else f378
        cells = [(im, "model, %s side, shaded (wet, anisotropic)" % ("left" if sgn > 0 else "right")),
                 (ov, "Fig. 382 registered: plate outline green, model temporalis blue" + (" (mirrored)" if sgn < 0 else "")),
                 (P382, "Gray 1918 Fig. 382 (p. 386)" + (", mirrored" if sgn < 0 else "")), (P378, "Gray 1918 Fig. 378 (p. 379), masseter" + (", mirrored" if sgn < 0 else ""))]
        out.append(("side_" + sd, [cells[:2], cells[2:]]))
    if want("matte"):
        row = [(mt_(allk, (1, 0, 0), (10, 10, 15), 205), "this attempt, plain matte light (view.py): geometry only")]
        if P_:
            row.append((pv_(allk, (1, 0, 0), (10, 10, 15), 205), "previous attempt (T-muscle-1), same matte light"))
        out.append(("matte", [row]))
    if want("front"):
        out.append(("front", [[(sh_(SB + [MI[k] for k in allk], (0, 0, 1), (0, 0, 20), 205), "model, front, shaded"),
                               (f378, "Gray 1918 Fig. 378 (p. 379): no front plate of these muscles in Gray")]]))
    if want("below"):
        out.append(("below", [[(sh_(SB + [MI[k] for k in allk], (0, -1, 0.001), (0, 0, 20), 205), "model, from below, shaded"),
                               (f383, "Gray 1918 Fig. 383 (p. 387): no view from below in Gray")]]))
    # close-ups: this attempt shaded and matte, the previous one matte, the plate
    ap = cor_apex(B, 1)
    vjm = vj[vj[:, 0] > 30]; gon = vjm[np.argmin(vjm[:, 1] + 0.9 * vjm[:, 2])]
    close = {"tex_fan": ([("tem", "L"), ("mas", "L")], (1, 0.1, 0.15), (60, 60, 2), 36, f382.crop((560, 200, 960, 520)), "Fig. 382 detail, the fan's hind part"),
             "tex_tendon_border": ([("tem", "L"), ("mas", "L")], (1, 0.05, 0.1), (62, 37, -8), 30, f382.crop((560, 380, 860, 620)), "Fig. 382 detail, the tendon's hind border"),
             "tex_masseter": ([("tem", "L"), ("mas", "L")], (1, -0.1, 0.25), (55, -38, 30), 45, f378.crop((180, 260, 420, 540)), "Fig. 378 detail, the superficial masseter"),
             "attach_temporalis_margin": ([("tem", "L")], (1, 0.45, 0.05), (56, 80, 2), 30, f382.crop((380, 180, 760, 420)), "Fig. 382 detail, the upper margin"),
             "attach_coronoid": ([("tem", "L")], (1, -0.15, 0.25), (ap[0] + 4, ap[1] - 6, ap[2]), 34, f382.crop((300, 560, 560, 800)), "Fig. 382 detail, the coronoid"),
             "attach_arch_underside": ([("tem", "L"), ("mas", "L")], (1, -0.75, 0.3), (60, -12, 44), 40, f378.crop((180, 230, 420, 420)), "Fig. 378 detail, the arch"),
             "attach_ramus_angle": ([("tem", "L"), ("mas", "L")], (1, -0.25, -0.2), (gon[0] + 3, gon[1] + 10, gon[2] + 8), 40, f176, "Fig. 176 (p. 172), the angle's ridges")}
    for nm, (keys, e, c, sp, plate, cap) in close.items():
        if not want(nm):
            continue
        cutb = nm == "attach_coronoid"
        items = (SBcut if cutb else SB) + [MI[k] for k in keys]
        bb = [(vs, fs[cut], view.BONE), (vj, fj, view.BONE)] + TE if cutb else None
        row = [(sh_(items, e, c, sp), "this attempt, shaded"), (mt_(keys, e, c, sp, bb), "this attempt, plain matte")]
        if P_:
            row.append((pv_(keys, e, c, sp, cutb), "previous attempt, plain matte"))
        row.append((plate, "Gray 1918 " + cap))
        out.append((nm, [row[:2], row[2:]]))
    if want("arch_cut"):
        cells = [(sh_(SBcut + [MI["tem", "L"]], (1, 0, 0), (10, 10, 15), 205), "left, arch and masseter taken away, shaded"),
                 (sh_(SBcut + [MI["tem", "L"]], (1, -0.2, 0.15), (40, -5, 30), 80), "left, closer: the tendon to the coronoid"),
                 (sh_(SBcut + [MI["tem", "R"]], (-1, 0, 0), (-10, 10, 15), 205), "right, arch and masseter taken away"),
                 (f382, "Gray 1918 Fig. 382 (p. 386): the arch and masseter removed")]
        out.append(("arch_cut", [cells[:2], cells[2:]]))
    paths = []
    for name, rows in out:
        p = os.path.join(OUT, "pics", "muscle_%s.png" % name)
        view.sheet(rows, p, "T-muscle-2: %s" % name.replace("_", " "))
        im = Image.open(p); q = p[:-4] + ".jpg"
        paths.append(save_small(im, q)); os.remove(p)
        log("wrote", paths[-1])
    return paths


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    if cmd == "build":
        build(tuple(int(a) for a in (sys.argv[2].split(",") if len(sys.argv) > 2 else ("1", "-1"))),
              tuple(sys.argv[3].split(",")) if len(sys.argv) > 3 else ("tem", "mas"), log=lambda *a: print(*a, flush=True))
    elif cmd == "check":
        print(json.dumps(check(plates_dir=sys.argv[2] if len(sys.argv) > 2 else None), indent=1, default=float))
    elif cmd == "look":
        R_, pics_ = look_checks(plates_dir=sys.argv[2] if len(sys.argv) > 2 else None)
        print(json.dumps(R_, indent=1, default=float))
        import view
        rows = [[(im, "%s %s: flat 30 mm patch, sheets' lights" % k) for k, im in pics_.items()]]
        p = os.path.join(OUT, "pics", "muscle_look_patches.png"); view.sheet(rows, p, "T-muscle-2: flat patches the R checks were run on")
        from PIL import Image
        print(save_small(Image.open(p), p[:-4] + ".jpg")); os.remove(p)
    elif cmd == "render":
        render(sys.argv[2] if len(sys.argv) > 2 else os.path.join(OUT, "gp"), prev=sys.argv[3] if len(sys.argv) > 3 else None,
               only=sys.argv[4].split(",") if len(sys.argv) > 4 else None)
