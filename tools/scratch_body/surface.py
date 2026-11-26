"""surface.py: the small unevenness of real bone, and its colour, put on after the two halves are joined.

The skull is built as its left half and mirrored. Anything random built into the half comes out the same on both
sides, and the eye picks that out at once (a blot test, not a bone). So everything that is not anatomy but texture is
added here, on the whole head, where left and right get their own:

  grain     the surface is nowhere quite smooth: it rises and falls 0.004 to 0.03 mm over 1.5 to 6 mm, more where muscles
            and ligaments take hold and on the palate, least on the joint surfaces (finer than that the grid cannot carry it:
            the fibre-like grain of 0.3 to 1 mm is the renderer's, see vertex_attrs)
  pits      the larger openings for vessels (and on the palate for glands), 0.7 to 2 mm, none round (aspect 1.3 to 2.3)
  midline   the sutures that run on the midline wander from side to side as real ones do

Every random number here is a function of the place it is used at (a hashed lattice in the head frame, mm), never of a
stream: a change to one tooth leaves the grain and the pits everywhere else as they were, bit for bit. Left and right
are different places, so they differ.

Where the bone is rough or pitted is given by zones in the head frame (mm): (name, centre, radii, grain, pits per mm2).
A zone with a negative grain smooths (a joint surface). The colour, the pores finer than the grid and the way the surface
takes the light are per-vertex channels of the finished mesh (vertex_attrs), measured against 95 photographs of dry
bone (T-bone-ref): ivory with real warmth, darker and yellower in ragged patches, in grooves and along the sutures,
a dark hairline in their seams, paler and smoother on the joint surfaces, a patchy field of fine pores, thicker on the
porous bone.
"""
import numpy as np
from scipy import ndimage

ZONES = [
    # name, centre (x, y, z), radii, extra grain (mm), pits per mm2
    # (the palate's many small openings are a third of a millimetre across: pits the grid can carry, put as close as the real ones
    # stand, ran together into cracks. The few larger ones are pits here; the fine ones are for the surface's picture, not its shape)
    ("palate, maxilla's part", (0, -34, 72), (17, 9, 20), 0.06, 0.035),
    ("palate, palatine bone", (0, -30, 49), (15, 4, 7), 0.02, 0.012),
    ("alveolar process, upper", (0, -38, 74), (32, 8, 30), 0.03, 0.03),
    ("nuchal plane", (0, -18, -52), (52, 16, 28), 0.06, 0.008),    # (rough, but not pitted all over: at a pit every 20 mm2 it looked like kneaded clay)
    ("mastoid", (56, -12, -17), (10, 20, 14), 0.05, 0.003),      # (its small openings are finer than the grid: as pits they came out as craters)
    ("mastoid", (-56, -12, -17), (10, 20, 14), 0.05, 0.003),
    ("pterygoid plates", (22, -22, 37), (10, 16, 7), 0.04, 0.04),
    ("pterygoid plates", (-22, -22, 37), (10, 16, 7), 0.04, 0.04),
    ("under side of the cheek's arch", (60, -6, 44), (9, 5, 22), 0.05, 0.04),
    ("under side of the cheek's arch", (-60, -6, 44), (9, 5, 22), 0.05, 0.04),
    ("jaw socket", (50, -1, 10), (11, 5, 9), -0.035, -0.02),
    ("jaw socket", (-50, -1, 10), (11, 5, 9), -0.035, -0.02),
    ("occipital condyles", (0, -26, -6), (22, 5, 13), -0.03, -0.02),
]
# (T-bone-surface) grain: real dry bone's relief is 0.01 to 0.03 mm (T-bone-ref); the old 0.035 mm base with zones on top, in
# blobs of 1.5 to 15 mm, read as kneaded clay. The zones' extra grain is scaled into that range.
GRAIN_BASE, GRAIN_K, GRAIN_MIN, GRAIN_MAX = 0.014, 0.3, 0.004, 0.03
# vascular pits (geometry): 0.5 to 1 per cm2 on most of the bone (T-bone-ref), the zones' extra (the palate's glands) on top
PIT_BASE, PIT_K, PIT_MAX = 0.0065, 0.5, 0.02          # per mm2
PIT_CELL, PIT_BAND = 4.0, 2.0                          # mm: one candidate per cell of the lattice; kept if within half the band of the surface

# ---- where the bone's surface differs in kind (head frame, mm; both the skull's and the jaw's): (name, centre, radii, kind)
REGIONS = [
    ("glenoid fossa", (50, -1.5, 9), (9, 4.5, 5.5), "joint"), ("glenoid fossa", (-50, -1.5, 9), (9, 4.5, 5.5), "joint"),
    ("articular eminence", (50, -7.5, 20), (9, 4, 5), "joint"), ("articular eminence", (-50, -7.5, 20), (9, 4, 5), "joint"),
    ("mandible's head", (51.5, -3, 9.5), (10, 3.5, 5.5), "joint"), ("mandible's head", (-51.5, -3, 9.5), (10, 3.5, 5.5), "joint"),
    ("occipital condyle", (13, -27, -5), (7, 5, 12), "joint"), ("occipital condyle", (-13, -27, -5), (7, 5, 12), "joint"),
    ("temporal squama", (63, 18, 2), (9, 17, 21), "porous"), ("temporal squama", (-63, 18, 2), (9, 17, 21), "porous"),
    ("zygomatic root", (62, -4, 22), (9, 6, 9), "porous"), ("zygomatic root", (-62, -4, 22), (9, 6, 9), "porous"),
    ("mastoid", (56, -12, -17), (10, 20, 14), "porous"), ("mastoid", (-56, -12, -17), (10, 20, 14), "porous"),
    ("nuchal plane", (0, -18, -52), (52, 16, 28), "porous"),
    ("external occipital protuberance", (0, 6, -78), (12, 9, 9), "porous"),
    ("masseteric tuberosity", (47, -58, 20), (7, 14, 13), "porous"), ("masseteric tuberosity", (-47, -58, 20), (7, 14, 13), "porous"),
    ("mental protuberance", (0, -82, 92), (14, 8, 8), "porous"),
]
PORES = {"plain": 62.0, "porous": 95.0, "joint": 2.0}   # fine pores per cm2 (vault 25 to 90, porous bone 60 to 120, joint 0 to 5)
PORE_D = (0.18, 0.4, 0.10, 0.42)                          # their diameter (mm): lognormal, median and spread, clipped (p90 0.30)
# clean prepared bone, ivory with real warmth (CIELAB of the albedo; the render's light takes L* down by about 12)
LAB = {"vault": (90.0, 5.0, 24.5), "face": (90.0, 4.8, 24.0), "mandible": (90.5, 5.0, 25.0)}   # (the patches below take it darker and yellower)
JOINT_DL, JOINT_DA, JOINT_DB = 4.5, -2.5, 0.0           # a joint surface: paler, less red (real: L +20, a -7 on old stained bone;
                                                         # clean bone is pale already: more than this leaves sRGB and turns white)
GROOVE_DL, SEAM_DL = 5.0, 30.0                           # darker in grooves and pits; the sutures' seams a dark hairline
ROUGH = {"plain": 0.46, "porous": 0.61, "joint": 0.42}   # roughness for the light (0.40 to 0.50 smooth plates, 0.55 to 0.65 porous)


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def zone_field(shape, lo, h, col, zones=ZONES, base=0.0):
    """One of the zones' numbers (col 3: grain, col 4: pits) as a field over the whole grid."""
    A = np.full(shape, base, np.float32)
    ax = [lo[k] + h * np.arange(shape[k]) for k in range(3)]
    for z in zones:
        c, r, val = np.array(z[1], float), np.array(z[2], float), z[col]
        sl = tuple(slice(max(int((c[k] - 1.3 * r[k] - lo[k]) / h), 0), min(int((c[k] + 1.3 * r[k] - lo[k]) / h) + 2, shape[k])) for k in range(3))
        if any(s.stop <= s.start for s in sl):
            continue
        X, Y, Z = np.ix_(*(ax[k][sl[k]] for k in range(3)))
        q = np.sqrt(((X - c[0]) / r[0]) ** 2 + ((Y - c[1]) / r[1]) ** 2 + ((Z - c[2]) / r[2]) ** 2)
        A[sl] += (val * smoothstep((1.2 - q) / 0.35)).astype(np.float32)
    return A


def zone_at(P, col, zones=ZONES, base=0.0):
    """The same at points P (n x 3, mm)."""
    P = np.asarray(P, float); A = np.full(len(P), base, float)
    for z in zones:
        c, r = np.array(z[1], float), np.array(z[2], float)
        q = np.sqrt((((P - c) / r) ** 2).sum(1))
        A += z[col] * smoothstep((1.2 - q) / 0.35)
    return A


def region_at(P, kind, regions=REGIONS):
    """How far points P lie in a region of the kind (0 outside, 1 well inside)."""
    P = np.asarray(P, float); w = np.zeros(len(P))
    for nm, c, r, k in regions:
        if k == kind:
            q = np.sqrt((((P - np.array(c, float)) / np.array(r, float)) ** 2).sum(1))
            w = np.maximum(w, smoothstep((1.15 - q) / 0.35))
    return w


# ---- random numbers that are a function of place: a hashed integer lattice (murmur3's finaliser)
def _hash(ix, iy, iz, seed):
    u = np.uint32
    h = (np.asarray(ix).astype(np.int64).astype(u) * u(0x8DA6B343)) ^ (np.asarray(iy).astype(np.int64).astype(u) * u(0xD8163841)) \
        ^ (np.asarray(iz).astype(np.int64).astype(u) * u(0xCB1AB31F)) ^ u((int(seed) * 0x165667B1 + 0x27D4EB2F) & 0xFFFFFFFF)
    h = h ^ (h >> u(16)); h = h * u(0x85EBCA6B); h = h ^ (h >> u(13)); h = h * u(0xC2B2AE35); h = h ^ (h >> u(16))
    return h


def uniform(ix, iy, iz, seed):
    """A number in [0, 1) for each lattice point (ix, iy, iz) and seed: the same every time it is asked for."""
    return _hash(ix, iy, iz, seed).astype(np.float64) * (1.0 / 4294967296.0)


def _turn(seed):
    """A fixed turn of space for each seed, so that no two layers of noise line up with the axes or with each other."""
    q, _ = np.linalg.qr(np.random.default_rng(1000 + int(seed)).standard_normal((3, 3)))
    return q


_VN_SD = 0.4006          # spread of the raw lattice noise below (measured once over 2 million points)


def vnoise(P, wave, seed, stretch=None, grad=False):
    """Smooth noise of unit spread with blobs about `wave` mm across at points P (n x 3, mm), a function of the place
    alone. stretch=(k, s): drawn out s times along the head frame's axis k (no turn then); grad: its slope per mm too."""
    P = np.asarray(P, np.float64)
    if stretch is None:
        R = _turn(seed); sc = np.full(3, 2.0 / wave)
    else:
        R = np.eye(3); sc = np.full(3, 2.0 / wave); sc[stretch[0]] /= stretch[1]
    q = (P @ R) * sc + 0.5 * (seed % 7)
    i = np.floor(q); f = q - i; i = i.astype(np.int64)
    u = f * f * f * (f * (f * 6 - 15) + 10)
    du = 30 * f * f * (f * (f - 2) + 1) if grad else None
    val = np.zeros(len(P)); g = np.zeros((len(P), 3)) if grad else None
    for ox in (0, 1):
        wx = u[:, 0] if ox else 1 - u[:, 0]
        for oy in (0, 1):
            wy = u[:, 1] if oy else 1 - u[:, 1]
            for oz in (0, 1):
                wz = u[:, 2] if oz else 1 - u[:, 2]
                c = 2.0 * uniform(i[:, 0] + ox, i[:, 1] + oy, i[:, 2] + oz, seed) - 1.0
                val += c * wx * wy * wz
                if grad:
                    g[:, 0] += c * (du[:, 0] if ox else -du[:, 0]) * wy * wz
                    g[:, 1] += c * wx * (du[:, 1] if oy else -du[:, 1]) * wz
                    g[:, 2] += c * wx * wy * (du[:, 2] if oz else -du[:, 2])
    val /= _VN_SD
    if not grad:
        return val
    return val, ((g * sc) @ R.T) / _VN_SD


def _lerp(D, lo, h, P):
    return ndimage.map_coordinates(D, ((np.asarray(P, float) - lo) / h).T, order=1, mode="nearest")


def _grad(D, lo, h, P):
    g = np.stack([_lerp(D, lo, h, P + 0.5 * h * e) - _lerp(D, lo, h, P - 0.5 * h * e) for e in np.eye(3)], 1) / h
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def roughen(D, lo, h, seed=1918, zones=ZONES, log=print):
    """Give the whole head's field D (mm, < 0 in bone) its grain and pits. Returns the new field (D is not changed).
    Each value is a function of its place (and the seed, one per bone): what is put at a point depends only on the field
    within 4 mm of it."""
    lo = np.asarray(lo, float); h = float(h)
    detail = max(2.2 * h, 0.55)
    D_in = D
    D = D.astype(np.float32, copy=True)
    # ---- grain, on the points within 3 mm of the surface
    idx = np.nonzero(np.abs(D) < 3.0)
    # a thin plate keeps its thickness: the grain is weaker on it (how thin is read off a blurred field, 4 mm round)
    thin = smoothstep((ndimage.gaussian_filter(D, 1.0 / h) - 0.15) / 0.2).astype(np.float32)[idx]      # 0 on a plate 2.4 mm thick, 1 on one of 1.2 mm
    add = np.empty(len(idx[0]), np.float32)
    wts = (0.7, 0.55, 0.35); norm = float(np.sqrt(sum(w * w for w in wts)))
    gmin, gmax = np.inf, -np.inf
    for a in range(0, len(add), 1_500_000):
        b = min(a + 1_500_000, len(add))
        P = lo + h * np.stack([idx[k][a:b] for k in range(3)], 1).astype(np.float64)
        G = np.clip(GRAIN_BASE + GRAIN_K * zone_at(P, 3, zones), GRAIN_MIN, GRAIN_MAX)
        gmin, gmax = min(gmin, G.min()), max(gmax, G.max())
        N = sum(w * vnoise(P, detail * m, seed * 16 + j) for j, (w, m) in enumerate(zip(wts, (1.3, 2.4, 4.5)))) / norm
        add[a:b] = (G * N * (1.0 - 0.8 * thin[a:b])).astype(np.float32)
    D[idx] += add
    del thin, add
    # ---- pits: one candidate in each cell of a 4 mm lattice, at a place of its own; kept where the surface passes near it
    c0 = np.floor(lo / PIT_CELL).astype(np.int64); c1 = np.floor((lo + h * (np.array(D.shape) - 1)) / PIT_CELL).astype(np.int64)
    C = np.stack(np.meshgrid(*[np.arange(c0[k], c1[k] + 1) for k in range(3)], indexing="ij"), -1).reshape(-1, 3)
    U = [uniform(C[:, 0], C[:, 1], C[:, 2], seed * 64 + 40 + k) for k in range(9)]
    q = (C + np.stack(U[1:4], 1)) * PIT_CELL
    K = int(np.ceil(2.4 * 1.0 / h)); n = np.array(D.shape)
    ok = np.all((q - lo) / h > K + 2, 1) & np.all((q - lo) / h < n - K - 3, 1)
    dens = np.clip(PIT_BASE + PIT_K * zone_at(q, 4, zones), 0.0, PIT_MAX)
    ok &= U[0] < dens * PIT_CELL ** 3 / PIT_BAND
    sel = np.where(ok)[0]
    Dq = _lerp(D, lo, h, q[sel]); sel = sel[np.abs(Dq) < 0.5 * PIT_BAND]
    p = q[sel]
    for _ in range(2):                                         # onto the surface along the field's slope
        p = p - _lerp(D, lo, h, p)[:, None] * _grad(D, lo, h, p)
    g = _grad(D, lo, h, p)
    # no pit in a thin plate (it would go through): the bone must be bone 1.5 mm in from the surface
    keep = (_lerp(D, lo, h, p - 1.5 * g) <= -1.15) & (np.abs(_lerp(D, lo, h, p)) < 0.3)
    sel, p, g = sel[keep], p[keep], g[keep]
    # each its own size and shape: the long way 0.7 to 2 mm asked (most near 1), never round (aspect 1.3 to 2.3); the short way no less than the grid carries
    diam = 0.7 * (2.0 / 0.7) ** (U[4][sel] ** 1.8)
    e = 1.3 + 1.0 * U[5][sel]
    r = np.clip(diam / (2 * e), 0.8 * h, 0.55)
    e = np.minimum(e, 1.0 / r)                                 # (the long way no more than 2 mm; a short way the grid can carry makes the small ones longer)
    dep = np.minimum(2 * r * (0.35 + 0.25 * U[6][sel]), 0.7)
    # a vessel's opening is drawn out along the surface the way the vessel runs, aslant
    a1 = np.where(np.abs(g[:, 0:1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]]))
    t1 = np.cross(g, a1); t1 /= np.linalg.norm(t1, axis=1, keepdims=True); t2 = np.cross(g, t1)
    th = 2 * np.pi * U[7][sel]
    v = np.cos(th)[:, None] * t1 + np.sin(th)[:, None] * t2
    off = np.arange(-K, K + 1)
    Dp = D.copy()                                              # (every pit is placed on the field before any is cut: none decides another's place)
    for j in range(len(p)):
        cidx = np.round((p[j] - lo) / h).astype(np.int64)
        sl = tuple(slice(cidx[k] - K, cidx[k] + K + 1) for k in range(3))
        OX, OY, OZ = np.meshgrid(*[lo[k] + h * (cidx[k] + off) - p[j, k] for k in range(3)], indexing="ij")
        along = OX * v[j, 0] + OY * v[j, 1] + OZ * v[j, 2]
        qq = (OX ** 2 + OY ** 2 + OZ ** 2 - along ** 2) + along ** 2 / (e[j] * e[j])
        Dp[sl] += (dep[j] * np.exp(-qq / (r[j] * r[j]))).astype(np.float32)
    roughen.pits = dict(p=p, v=v, n=g, r=r, e=e, dep=dep, diam=2 * r * e)
    # no new shut pocket of air: a few voxels of a thin partition (the ethmoid's) can close round a speck of air; where the field
    # had bone, the bone is kept (only pockets of 8 voxels or fewer, which a change elsewhere cannot open or shut)
    air, n_air = ndimage.label(Dp >= 0)
    if n_air > 1:
        size = np.bincount(air.ravel())
        edge = np.unique(np.concatenate([air[[0, -1]].ravel(), air[:, [0, -1]].ravel(), air[:, :, [0, -1]].ravel()]))
        small = (size <= 8); small[0] = False; small[edge] = False
        if small.any():
            pocket = small[air]
            carved = np.bincount(air[pocket], weights=(D_in[pocket] < 0).astype(float), minlength=len(size)) > 0   # pockets the roughening made
            pocket &= carved[air]
            Dp[pocket] = np.minimum(D_in[pocket], -0.02)
            log("surface: %d voxel(s) of new shut air pockets given back to the bone" % int(pocket.sum()))
    del air
    area = float(np.count_nonzero(np.abs(D) < 0.5 * h)) * h * h / 1.5
    log("surface: grain %.3f to %.3f mm (nothing finer than %.2f mm), %d pits on about %.0f cm2 (%.2f per cm2), %.1f to %.1f mm long, aspect %.1f to %.1f"
        % (gmin, gmax, detail, len(p), area / 100.0, len(p) / max(area / 100.0, 1e-9), (2 * r * e).min() if len(p) else 0, (2 * r * e).max() if len(p) else 0,
           e.min() if len(p) else 0, e.max() if len(p) else 0))
    return Dp


# ---- the finished mesh's per-vertex channels: what the renders use, and what the app's shader is to read
def lab_to_srgb(L, a, b):
    """CIELAB (D65) to sRGB 0..255; a colour outside sRGB keeps its lightness and hue and gives up chroma."""
    L = np.asarray(L, float); a = np.asarray(a, float); b = np.asarray(b, float)
    def lin(k):
        fy = (L + 16) / 116; fx = fy + k * a / 500; fz = fy - k * b / 200
        def inv(t):
            return np.where(t > 6 / 29, t ** 3, 3 * (6 / 29) ** 2 * (t - 4 / 29))
        X, Y, Z = 0.95047 * inv(fx), inv(fy), 1.08883 * inv(fz)
        return np.stack([3.2406 * X - 1.5372 * Y - 0.4986 * Z, -0.9689 * X + 1.8758 * Y + 0.0415 * Z, 0.0557 * X - 0.2040 * Y + 1.0570 * Z], -1)
    lo_, hi = np.zeros(L.shape), np.ones(L.shape)
    rgb = lin(hi)
    out = ((rgb > 1.0) | (rgb < 0.0)).any(-1)
    if out.any():
        for _ in range(12):
            mid = 0.5 * (lo_ + hi); bad = ((lin(mid) > 1.0) | (lin(mid) < 0.0)).any(-1)
            hi = np.where(out & bad, mid, hi); lo_ = np.where(out & ~bad, mid, lo_)
        rgb = lin(np.where(out, lo_, 1.0))
    rgb = np.clip(rgb, 0, 1)
    return 255 * np.where(rgb <= 0.0031308, 12.92 * rgb, 1.055 * rgb ** (1 / 2.4) - 0.055)


def srgb_to_lab(rgb):
    c = np.asarray(rgb, float) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    X = (0.4124 * c[..., 0] + 0.3576 * c[..., 1] + 0.1805 * c[..., 2]) / 0.95047
    Y = 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]
    Z = (0.0193 * c[..., 0] + 0.1192 * c[..., 1] + 0.9505 * c[..., 2]) / 1.08883
    def f(t):
        return np.where(t > (6 / 29) ** 3, np.cbrt(t), t / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z))], -1)


def _normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, f[:, k], n)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-15)


EMINENCES = [(28, 72, 86), (-28, 72, 86), (58, 72, -22), (-58, 72, -22)]       # frontal and parietal: the vault's grain runs out from them


STAIN_DL = 3.0          # (repair 2) how much darker (L*) the deepest of the tone's drifts are; they are yellower by about half that in b*


def stain_field(v, t, seed):
    """Broad, faint, edge-less drifts of tone (about unit spread): a gently warped sum of noises 90 and 45 mm across (lattices
    45 and 22 mm). Nothing narrower than about 15 mm, so no outline can be traced."""
    w = np.stack([vnoise(v, 60, seed + 201 + k) for k in range(3)], 1) * 8.0
    P = v + w
    F = 1.0 * vnoise(P, 90, seed + 210) + 0.3 * vnoise(P, 45, seed + 214)     # (t is not used: the grain's fallback way jumps on the jaw)
    return F / 1.1


def _base(v, vn, part, seed):
    """What of the colour, roughness and pores is read off the place alone (no mesh): Lab, pores, roughness, region, joint, grain's fallback way."""
    if part is None:
        part = "jaw" if (v[:, 1].max() < 15 and v[:, 1].min() < -60) else "skull"
    joint = region_at(v, "joint"); porous = region_at(v, "porous") * (1 - joint)
    if part == "jaw":
        L0, a0, b0 = (np.full(len(v), x) for x in LAB["mandible"]); face = np.zeros(len(v))
    else:
        face = smoothstep((v[:, 2] - 30) / 25) * (1 - smoothstep((v[:, 1] - 40) / 20))
        L0, a0, b0 = (LAB["vault"][k] * (1 - face) + LAB["face"][k] * face for k in range(3))
    # the grain's way where the shape does not tell it: on the vault out from the eminences, on the jaw along the arch, up the ramus
    if part == "jaw":
        fb = np.cross(np.array([0, 1.0, 0]), v - np.array([0, 0, 30.0]))
        fb = np.where((v[:, 1] > -45)[:, None], np.array([[0, 1.0, 0]]), fb)
    else:
        Em = np.array(EMINENCES, float)
        near = np.argmin(((v[:, None, :] - Em[None]) ** 2).sum(2), 1)
        fb = v - Em[near]
    fb = fb - (fb * vn).sum(1, keepdims=True) * vn
    fb /= np.maximum(np.linalg.norm(fb, axis=1, keepdims=True), 1e-9)
    # (T-bone-surface repair) the bone's tone: never paler than the ground (pale round clouds read as airbrush, and as white
    # spots), only a little darker and yellower in sparse, irregular, ragged, drawn-out patches (a fifth of the surface or
    # less in any 20 mm, so that what is left is the ground and nothing reads as lighter than its surroundings), more of them
    # on the rough bone
    F = stain_field(v, fb, seed) + 0.2 * porous
    st = np.clip(0.5 + F / 4.0, 0.0, 1.0) * (1 - joint)          # (repair 2) no threshold, no knee: a slow linear drift (about 0.75 L* per spread; joints keep the ground)
    dL = -STAIN_DL * st
    da = 0.12 * STAIN_DL * st; db = 0.45 * STAIN_DL * st
    # joint surfaces
    dL = dL + JOINT_DL * joint; da = da + JOINT_DA * joint; db = db + JOINT_DB * joint
    # fine pores: per cm2 by region, thicker and thinner in patches (some nearly bare)
    patch = np.clip(1.0 + 0.95 * vnoise(v, 6, seed + 105) + 0.45 * vnoise(v, 17, seed + 106), 0.0, 2.2)    # pore-free between the patches
    pores = (PORES["plain"] * (1 - porous) + PORES["porous"] * porous) * patch
    pores = pores * (1 - joint) + PORES["joint"] * joint
    pmean = (PORES["plain"] * (1 - porous) + PORES["porous"] * porous) * (1 - joint) + PORES["joint"] * joint
    frac = pmean / 100.0 * np.pi * (PORE_D[0] / 2) ** 2 * 1.4          # the share of the surface they take (by region: their patches are the shader's)
    dL = dL - 12.0 * frac
    rough = (ROUGH["plain"] * (1 - porous) + ROUGH["porous"] * porous) * (1 - joint) + ROUGH["joint"] * joint
    rough = rough + 0.02 * vnoise(v, 20, seed + 107)
    region = np.where(part == "jaw", 2, np.where(face > 0.5, 1, 0))
    region = np.where(porous > 0.5, 4, region); region = np.where(joint > 0.5, 3, region)
    return dict(L=L0 + dL, a=a0 + da, b=b0 + db, pores=pores, rough=rough, region=region, joint=joint, fb=fb, part=part)


def point_attrs(P, N, part=None, seed=7):
    """vertex_attrs' channels at loose points (no mesh: no grooves, seams or ridge-following grain)."""
    P = np.asarray(P, np.float64); N = np.asarray(N, np.float64)
    B = _base(P, N, part, seed)
    return dict(rgb=lab_to_srgb(B["L"], B["a"], B["b"]).astype(np.float32), rough=np.clip(B["rough"], 0.40, 0.65).astype(np.float32),
                pores=B["pores"].astype(np.float32), tangent=B["fb"].astype(np.float32), coh=(0.6 * (1 - B["joint"])).astype(np.float32))


def vertex_attrs(v, f, part=None, seed=7):
    """Per-vertex channels of a finished bone mesh (head frame, mm), each a function of the vertex's place and the mesh's shape:
      rgb      sRGB 0..255: the albedo, ivory by region (vault, face, mandible), never paler than that but a little darker and
               yellower in ragged, drawn-out patches (2.5 to 40 mm), more so on rough bone, along the sutures' margins and in
               grooves; a dark hairline in the sutures' seams; paler and less red on the joint surfaces; the fine pores' mean darkening
      rough    the roughness for the light (0.40 to 0.65)
      region   0 vault, 1 face, 2 mandible, 3 joint surface, 4 porous bone
      pores    how many fine pores per cm2 the shader is to put there (0 to 150; their diameter PORE_D)
      tangent  the direction the fibre-like grain runs (unit, in the surface), and coh how surely (0 none: isotropic grain)
      cavity   0..1, how much of the darkening is a groove or seam (for the app: keep it out of the ambient occlusion twice)
    part: 'skull' or 'jaw' (None: read off the mesh's extent)."""
    v = np.asarray(v, np.float64); f = np.asarray(f, np.int64)
    vn = _normals(v, f)
    B = _base(v, vn, part, seed)
    Lc, ac, bc = B["L"], B["a"], B["b"]
    # grooves and seams: the mean curvature (1/mm, + convex) from the edges' turn of the normals
    E = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]); E = np.unique(np.sort(E, 1), axis=0)
    d = v[E[:, 1]] - v[E[:, 0]]
    k = ((vn[E[:, 1]] - vn[E[:, 0]]) * d).sum(1) / np.maximum((d * d).sum(1), 1e-12)
    H = np.zeros(len(v)); cnt = np.zeros(len(v))
    np.add.at(H, E[:, 0], k); np.add.at(H, E[:, 1], k); np.add.at(cnt, E[:, 0], 1); np.add.at(cnt, E[:, 1], 1)
    H /= np.maximum(cnt, 1)
    groove = smoothstep((-H - 0.25) / 0.6); seam = smoothstep((-H - 0.75) / 0.9)     # (a broad hollow is not a groove: its rims would stand out pale)
    cavity = np.maximum(groove * GROOVE_DL, seam * SEAM_DL) / SEAM_DL
    Lc = Lc - GROOVE_DL * groove * (1 - seam) - SEAM_DL * seam
    bc = bc - 6.0 * seam; ac = ac - 1.0 * seam
    rough = np.clip(B["rough"] + 0.03 * groove, 0.40, 0.65)
    # the grain's way: along a ridge or a border, the way the normals turn least (their spread over about 3 mm)
    nn = np.stack([vn[:, 0] * vn[:, 0], vn[:, 1] * vn[:, 1], vn[:, 2] * vn[:, 2], vn[:, 0] * vn[:, 1], vn[:, 1] * vn[:, 2], vn[:, 0] * vn[:, 2]], 1)
    from scipy import sparse
    A = sparse.coo_matrix((np.ones(2 * len(E)), (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(len(v), len(v))).tocsr()
    A = A + sparse.identity(len(v), format="csr")
    A = sparse.diags(1.0 / np.asarray(A.sum(1)).ravel()) @ A
    for _ in range(6):
        nn = A @ nn
    # the margins of the sutures and the floors of grooves take more of the tone, out to about 3 mm, raggedly
    rec = np.maximum(seam, 0.5 * groove)
    for _ in range(10):
        rec = A @ rec
    rag = 0.6 + 0.4 * smoothstep((vnoise(v, 20, seed + 150) + 1.0) / 2.0)    # (repair 2) varies along the suture, no crumbs
    edge = np.clip(4.0 * rec, 0, 1) * rag * (1 - seam)
    Lc = Lc - 4.0 * edge; bc = bc + 2.0 * edge; ac = ac + 0.5 * edge
    M = np.empty((len(v), 3, 3))
    M[:, 0, 0], M[:, 1, 1], M[:, 2, 2], M[:, 0, 1], M[:, 1, 2], M[:, 0, 2] = nn.T
    M[:, 1, 0], M[:, 2, 1], M[:, 2, 0] = M[:, 0, 1], M[:, 1, 2], M[:, 0, 2]
    lam, ev = np.linalg.eigh(M)
    t = ev[:, :, 0]
    coh = np.clip((lam[:, 1] - lam[:, 0]) / (lam[:, 1] + lam[:, 0] + 0.01), 0, 1)
    fb = B["fb"]
    t = t - (t * vn).sum(1, keepdims=True) * vn
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
    sgn = np.sign((t * fb).sum(1, keepdims=True)); sgn[sgn == 0] = 1
    w = coh[:, None]
    tan = w * t * sgn + (1 - w) * fb
    tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-9)
    cohf = np.maximum(coh, 0.6 * (1 - B["joint"]))                                 # the fallback ways are known well enough
    rgb = lab_to_srgb(Lc, ac, bc)
    return dict(rgb=np.round(rgb).astype(np.uint8), rough=rough.astype(np.float32), region=B["region"].astype(np.uint8),
                pores=B["pores"].astype(np.float32), tangent=tan.astype(np.float32), coh=cohf.astype(np.float32), cavity=cavity.astype(np.float32))


def write_ply(path, v, f, attrs):
    """A binary PLY with the per-vertex channels (x y z, nx ny nz, red green blue, roughness, region, pores, tx ty tz, coh, cavity)."""
    v = np.asarray(v, np.float32); f = np.asarray(f, np.int32); vn = _normals(v.astype(np.float64), f).astype(np.float32)
    dt = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"), ("nx", "<f4"), ("ny", "<f4"), ("nz", "<f4"), ("red", "u1"), ("green", "u1"), ("blue", "u1"),
                   ("roughness", "<f4"), ("region", "u1"), ("pores", "<f4"), ("tx", "<f4"), ("ty", "<f4"), ("tz", "<f4"), ("coh", "<f4"), ("cavity", "<f4")])
    V = np.empty(len(v), dt)
    V["x"], V["y"], V["z"] = v.T; V["nx"], V["ny"], V["nz"] = vn.T
    V["red"], V["green"], V["blue"] = attrs["rgb"].T
    V["roughness"], V["region"], V["pores"] = attrs["rough"], attrs["region"], attrs["pores"]
    V["tx"], V["ty"], V["tz"] = attrs["tangent"].T; V["coh"], V["cavity"] = attrs["coh"], attrs["cavity"]
    F = np.empty(len(f), np.dtype([("n", "u1"), ("i", "<i4", (3,))])); F["n"] = 3; F["i"] = f
    head = ["ply", "format binary_little_endian 1.0", "element vertex %d" % len(v)]
    head += ["property %s %s" % ({"<f4": "float", "u1": "uchar"}[dt[nm].str.replace("|", "")], nm) for nm in dt.names]
    head += ["element face %d" % len(f), "property list uchar int vertex_indices", "end_header"]
    with open(path, "wb") as o:
        o.write(("\n".join(head) + "\n").encode()); o.write(V.tobytes()); o.write(F.tobytes())
    return path


def teeth(s, wave, ph, ph2):
    """The sideways run of a toothed suture along its length s (mm), about -1.5 to 1.5: teeth of several lengths at once, their
    spacing and their depth both changing from place to place (no two teeth of a real suture are alike, and a plain sum of
    waves reads as a zip)."""
    warp = s + 1.2 * np.sin(2 * np.pi * s / 23.0 + ph2[0]) + 0.8 * np.sin(2 * np.pi * s / 13.7 + ph2[1])
    deep = 0.75 + 0.3 * np.sin(2 * np.pi * s / 19.0 + ph2[2]) + 0.2 * np.sin(2 * np.pi * s / 7.3 + ph2[3])
    return deep * sum(a * np.sin(2 * np.pi * warp / L + p) for a, L, p in zip((1.0, 0.8, 0.7, 0.45), wave, ph)) / 1.9


def wander_line(P, amp, rng, wave=(6.1, 3.4, 9.7, 2.3), drift=0.0, depth=None):
    """A line (N x 3) made to wander sideways (in x) by up to about amp mm, its ends kept: a suture on the midline.
    depth(u): how deep its teeth are at each place along it (u from 0 at its start to 1 at its end; 1 = amp).
    drift: how far the whole line strays from the middle plane besides (mm), over lengths of 4 to 7 cm."""
    P = np.asarray(P, float)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    ph = rng.uniform(0, 2 * np.pi, 4)
    if depth is None:
        w = sum(a * np.sin(2 * np.pi * s / L + p) for a, L, p in zip((1.0, 0.8, 0.7, 0.45), wave, ph)) / 1.9
    else:
        w = teeth(s, wave, ph, rng.uniform(0, 2 * np.pi, 4)) * depth(s / s[-1])
    end = np.minimum(s, s[-1] - s)
    Q = P.copy(); Q[:, 0] += amp * w * np.clip(end / 2.0, 0, 1)
    if drift:
        ph = rng.uniform(0, 2 * np.pi, 2)
        Q[:, 0] += drift * (np.sin(2 * np.pi * s / 71.0 + ph[0]) + 0.6 * np.sin(2 * np.pi * s / 43.0 + ph[1])) / 1.3 * np.clip(end / 14.0, 0, 1)
    return Q
