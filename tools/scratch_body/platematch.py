"""platematch.py: a bone set beside the plates it is built from, like for like.

A plate shows one bone from one direction. Here the model is drawn from that same direction, with parallel lines of
sight and the light from the upper left as the engravers put it, as the same side's bone (the views below are of the
LEFT calcaneus, so they are written as mirror views of the right-hand model), and its outline is laid over the
plate's. The plate's own outline is found from the plate (silhouette), its lettering painted out first.

A view says where the picture's right, its up and the line toward the eye point in the model's frame, how many mm one
pixel is, and at which pixel the model's origin falls. Plates are not strict axis views (Fig. 264 is drawn from above
and a little behind), so a view can be nodded, turned and rolled; fit() finds those angles, the scale and the place
that make the two outlines agree best.
"""
import itertools
import numpy as np
from scipy import ndimage as ndi
from skimage import morphology as mo
import sdf

# Gray 1918, the left calcaneus. Model frame (right bone): x medial, y up, z forward.
# `pose` is how the plate is taken to be drawn (nod, turn, roll in degrees, scale factor, shift right and down in pixels);
# `free` says which of those match_plates.py --fit may move. Fig. 264 is drawn from above and about 10 degrees behind
# (the posterior facet lies 4 to 7 mm further forward in it than in the side view; the tuberosity's back shows), Fig.
# 265 from below and in front (the surface for the cuboid shows as a band). Neither side plate is a level side view:
# each shows the upper joint surfaces as bands (in Fig. 266 the middle one stands 8 mm above the lateral rim it lies
# behind), which only a view from above can, so both are set at about 14 degrees from above; Fig. 267 is besides drawn
# from 13 degrees behind (the tuberosity's hinder surface shows in it). The angles were found by dev/fit_plates.py:
# the solid lying inside all the outlines at once then fills 0.95, 0.94 and 0.94 of the three outlines.
CALCANEUS = [
    dict(fig="Gray264", cap="from above", right=(1, 0, 0), up=(0, 0, 1), eye=(0, 1, 0), s=0.225, u0=87, v0=421,
         pose=(-10.0, 0.0, -0.003, 0.996, 0.004, 21.188), free=(0, 0, 0, 0, 0, 0)),
    dict(fig="Gray266", cap="lateral surface", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=0.238, u0=438, v0=236,
         pose=(14.0, 0.0, 0.0, 1.0, 5.859, -3.647), free=(0, 0, 0, 0, 0, 0),
         # two pairs of label lines end on the lower edge and leave bumps the tracing cannot tell from bone (2 mm under
         # the trochlear process, 3 mm under the lateral process): the edge is drawn straight across each
         erase=[[(213, 193), (241, 192), (241, 208), (213, 208)], [(336, 235), (364, 235), (364, 256), (336, 256)]]),
    dict(fig="Gray267", cap="medial surface", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=0.242, u0=50, v0=278,
         pose=(13.917, 13.31, 7.224, 0.985, -1.258, 8.158), free=(0, 1, 1, 1, 1, 1)),
    dict(fig="Gray265", cap="from below", right=(-1, 0, 0), up=(0, 0, 1), eye=(0, -1, 0), s=0.2214, u0=180, v0=445,
         pose=(18.0, -0.223, 1.245, 0.99, -6.978, 35.51), free=(0, 1, 1, 1, 1, 1)),
]
PLATES = {"calcaneus": CALCANEUS}


def no_text(gray, thr=215):
    """The plate with its lettering painted out: words are short flat blobs once their letters are run together."""
    g = gray.copy(); ink = g < thr
    h = ndi.binary_closing(np.pad(ink, 12), np.ones((1, 9), bool))
    h = ndi.binary_opening(h, np.ones((3, 3), bool))[12:-12, 12:-12]
    lab, n = ndi.label(h)
    big = 1 + int(np.argmax(ndi.sum(h, lab, range(1, n + 1))))
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        hh = sl[0].stop - sl[0].start; ww = sl[1].stop - sl[1].start
        if i != big and hh <= 20 and ww >= 6:
            g[max(sl[0].start - 3, 0):sl[0].stop + 3, max(sl[1].start - 3, 0):sl[1].stop + 3] = 255
    return g


def upright_lines(g, thr=150, least=16):
    """The thin straight upright lines of a plate (its label lines are all drawn so): a mask."""
    ink = g < thr
    thin = ink & ~ndi.binary_opening(ink, np.ones((1, 4), bool))
    return ndi.binary_dilation(ndi.binary_opening(thin, np.ones((least, 1), bool)), np.ones((1, 3), bool))


def silhouette(gray, close=5, open_=4, thr=215, erase=()):
    """The bone's outline in a plate, as a filled mask: the inked part closed over the white of its lit surfaces, the
    label lines opened away, the largest piece kept. Where label lines end on the bone they leave false bumps: the
    outline is found again with the upright lines standing in open paper taken out, and whatever thin part of the
    first outline the second lacks is dropped (the bone's own body is kept as first found, for the bone's edge is
    itself a thin line beside open paper in places). `erase`: a plate's own list of patches (pixel polygons) where label
    lines still leave a bump, taken off at the end."""
    g = no_text(gray, thr)

    def solid(g):
        g = np.pad(g, 12, constant_values=255)
        opened = ndi.binary_opening(ndi.binary_fill_holes(ndi.binary_closing(g < thr, mo.disk(close))), mo.disk(open_))
        lab, n = ndi.label(opened)
        return ndi.binary_fill_holes(lab == (1 + int(np.argmax(ndi.sum(opened, lab, range(1, n + 1))))))[12:-12, 12:-12]

    m = solid(g)
    white = ndi.uniform_filter((g > 200).astype(np.float32), (1, 5))
    lone = upright_lines(g, least=10) & ((np.roll(white, 5, 1) > 0.9) | (np.roll(white, -5, 1) > 0.9))
    g1 = g.copy(); g1[ndi.binary_dilation(lone, iterations=1)] = 255
    m = m & (solid(g1) | ndi.binary_opening(m, mo.disk(7)))
    # where an upright line crosses the edge it leaves a small bump on it: round the edge off there, and only there
    cross = ndi.binary_dilation(upright_lines(g, least=10) & ~ndi.binary_erosion(m, iterations=6), iterations=8)
    m = np.where(cross, ndi.binary_opening(m, mo.disk(9)), m)
    lab, n = ndi.label(m); m = ndi.binary_fill_holes(lab == (1 + int(np.argmax(ndi.sum(m, lab, range(1, n + 1))))))
    lab, n = ndi.label(m & ~ndi.binary_opening(m, mo.disk(7)))          # what is still left of a label line: a thin upright spike
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        hh = sl[0].stop - sl[0].start; ww = sl[1].stop - sl[1].start
        if hh >= 7 and ww <= 7 and hh >= 1.6 * ww:
            m[sl][lab[sl] == i] = False
    if len(erase):
        from PIL import Image, ImageDraw
        im = Image.new("L", m.shape[::-1], 0)
        for poly in erase:
            ImageDraw.Draw(im).polygon([tuple(q) for q in poly], fill=255)
        m = m & ~(np.asarray(im) > 0)
    return m


def basis(view, tilt=(0.0, 0.0, 0.0)):
    """The picture's right, up and toward-the-eye in the model's frame, after the view is nodded (about the picture's
    left-right line), turned (about its up-down line) and rolled (in its own plane), in degrees."""
    B = np.array([view["right"], view["up"], view["eye"]], float)
    a, b, c = np.radians(np.asarray(tilt, float))
    Rx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
    Ry = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
    Rz = np.array([[np.cos(c), -np.sin(c), 0], [np.sin(c), np.cos(c), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx @ B


def cast(F, B, s, u0, v0, size, sub=1, normals=True):
    """What each pixel's line of sight meets in the field: (how far toward the eye the surface stands there, mm, nan
    where it meets nothing; the surface's normal there as its parts along right, up and toward the eye)."""
    W, H = size; r, u, e = B
    U, V = np.meshgrid(np.arange(sub // 2, W, sub, dtype=float), np.arange(sub // 2, H, sub, dtype=float))
    P0 = (U - u0)[..., None] * s * r + (v0 - V)[..., None] * s * u
    corners = F.lo + np.array(list(itertools.product((0, 1), repeat=3))) * (F.n - 1) * F.h
    t = corners @ e; step = F.h * min(sub, 2)
    base = ((P0 - F.lo) / F.h).reshape(-1, 3).T; de = e / F.h
    depth = np.full(U.shape, np.nan, np.float32); prev = np.full(U.shape, 50.0, np.float32)
    for tk in np.arange(t.max(), t.min() - step, -step):
        d = ndi.map_coordinates(F.D, base + (de * tk)[:, None], order=1, mode="constant", cval=50.0).reshape(U.shape)
        new = np.isnan(depth) & (d <= 0)
        depth[new] = tk + step * d[new] / (d[new] - prev[new] - 1e-9)
        prev = d
    if not normals:
        return depth, None
    hit = ~np.isnan(depth); P = P0[hit] + depth[hit][:, None] * e
    g = np.stack([sdf.sample_field(F.D, F.lo, F.h, P + k) - sdf.sample_field(F.D, F.lo, F.h, P - k) for k in np.eye(3) * F.h * 0.75], 1)
    g /= np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
    N = np.zeros(U.shape + (3,), np.float32); N[hit] = g @ B.T
    return depth, N


def seen(F, arr, B, s, u0, v0, depth):
    """A field's values (an array on F's grid) at the points of the surface each pixel sees (0 where it sees none)."""
    H, W = depth.shape; r, u, e = B; hit = ~np.isnan(depth)
    U, V = np.meshgrid(np.arange(W, dtype=float), np.arange(H, dtype=float))
    P = (U[hit] - u0)[:, None] * s * r + (v0 - V[hit])[:, None] * s * u + depth[hit][:, None] * e
    out = np.zeros((H, W), np.float32); out[hit] = sdf.sample_field(np.asarray(arr, np.float32), F.lo, F.h, P)
    return out


# how much darker a hollow is drawn than what stands round it: for each width (mm) the surface is compared with the
# mean of its surroundings over that width, and darkened by the share given as it lies below it by up to half the width
HOLLOWS = ((1.2, 0.3), (3.5, 0.4), (8.0, 0.3))
HOLLOW = 0.9          # a hollow as deep as half its width is drawn nearly black (the plates' sinus tarsi, grooves and pits are)


def shade(depth, N, px, light=(-0.3, 0.35, 0.89), hollow=HOLLOW, pale=None):
    """A grey picture on white paper, shaded as the plates are: what faces the eye light and what turns away dark, the
    light a little from the upper left, hollows darker than what stands round them (HOLLOWS). `pale` (0 to 1 a pixel)
    marks the smooth joint surfaces, which a dry bone shows paler than its rough faces and the plates leave light."""
    hit = ~np.isnan(depth); L = np.asarray(light, float); L /= np.linalg.norm(L)
    dif = np.clip(N @ L, 0, 1); z = np.where(hit, depth, 0.0); w = hit.astype(np.float32); occ = 0.0
    for sig, wt in HOLLOWS:
        m = ndi.gaussian_filter(z * w, sig / px) / np.maximum(ndi.gaussian_filter(w, sig / px), 1e-3)
        occ = occ + wt * np.clip((m - z) / (0.5 * sig), 0, 1)
    g = (0.12 + 0.88 * dif) * (1.0 - hollow * occ) * (0.55 + 0.45 * np.sqrt(np.clip(N[..., 2], 0, 1)))
    if pale is not None:
        g = g * (1.0 + 0.22 * pale)
    return np.where(hit, 255.0 * np.clip(g, 0, 1) ** 1.15, 255.0).astype(np.uint8)


def iou(a, b):
    return float((a & b).sum()) / max(float((a | b).sum()), 1.0)


def edge(m):
    return m & ~ndi.binary_erosion(m)


def gap(model, plate, px):
    """How far the model's outline lies from the plate's, both ways, in mm: (mean, the worst twentieth's least, the worst)."""
    em, ep = edge(model), edge(plate)
    d = np.concatenate([ndi.distance_transform_edt(~ep)[em], ndi.distance_transform_edt(~em)[ep]]) * px
    return float(d.mean()), float(np.percentile(d, 95)), float(d.max())


def fit(F, view, mask, sub=3, start=None, free=None, limit=30.0, log=None):
    """The nod, turn and roll, the scale and the shift that lay the model's outline best over the plate's:
    (nod, turn, roll, scale factor, shift right px, shift down px) and the overlap reached."""
    from scipy.optimize import minimize
    H, W = mask.shape; small = mask[sub // 2::sub, sub // 2::sub]
    x0 = np.array(view["pose"] if start is None else start, float); free = np.array(view["free"] if free is None else free, bool)
    if not free.any():
        return x0, 1.0 - 0.0

    def full(q):
        p = x0.copy(); p[free] = q; return p

    def cost(q):
        p = full(q)
        depth, _ = cast(F, basis(view, p[:3]), view["s"] * p[3], view["u0"] + p[4], view["v0"] + p[5], (W, H), sub, normals=False)
        over = np.clip(np.abs(p[:3]) - limit, 0, None).sum()
        return 1.0 - iou(~np.isnan(depth), small) + 0.02 * over

    step = np.array([6.0, 6.0, 4.0, 0.04, 6.0, 6.0])[free]; q0 = x0[free]
    simplex = np.vstack([q0] + [q0 + step[i] * np.eye(len(q0))[i] for i in range(len(q0))])
    best = minimize(cost, q0, method="Nelder-Mead", options=dict(initial_simplex=simplex, xatol=0.05, fatol=2e-4, maxfev=500))
    # once more from where it ended, with a smaller start, in case it stuck
    simplex = np.vstack([best.x] + [best.x - 0.4 * step[i] * np.eye(len(q0))[i] for i in range(len(q0))])
    best = minimize(cost, best.x, method="Nelder-Mead", options=dict(initial_simplex=simplex, xatol=0.03, fatol=1e-4, maxfev=400))
    if log:
        log("  fit: nod %.1f turn %.1f roll %.1f scale %.3f shift %.1f %.1f, overlap %.3f" % (*full(best.x), 1.0 - best.fun))
    return full(best.x), 1.0 - best.fun


def draw(F, view, pose, size):
    """The model drawn in a plate's frame at full size: (grey picture, filled outline mask, depth)."""
    W, H = size
    depth, N = cast(F, basis(view, pose[:3]), view["s"] * pose[3], view["u0"] + pose[4], view["v0"] + pose[5], (W, H))
    return shade(depth, N, view["s"] * pose[3]), ~np.isnan(depth), depth


def light_of(tone, N, w, lift=40.0, b=0.9):
    """The light a plate is shaded by, read from the plate against the model's own faces. Which side it falls from is
    what fits the tone best as a + c . n over the faces the weight w trusts (the plates here all come out lit from the
    upper left, the engraver's custom). How steeply it falls cannot be had from a model still bare of detail (seen so,
    a plate looks lit head-on, and a head-on light leaves the way every slope faces undecided), so the light is set
    `lift` degrees off the line of sight, and the tone taken as a + b (n . L) with b fixed and a leaving the mean tone
    right. Returns (a, b, L as right, up and toward the eye, the share of the tone's spread the model's faces explain)."""
    k = w > 0.3; ww = w[k].astype(float); A = np.column_stack([np.ones(int(k.sum())), N[k].astype(float)]); t = tone[k].astype(float)
    c, *_ = np.linalg.lstsq(A * ww[:, None], t * ww, rcond=None)
    fit = A @ c; mean = (t * ww).sum() / ww.sum()
    r2 = 1.0 - float((ww * (t - fit) ** 2).sum() / max((ww * (t - mean) ** 2).sum(), 1e-9))
    side = c[1:3] / max(np.linalg.norm(c[1:3]), 1e-9) if np.linalg.norm(c[1:3]) > 0.02 else np.array([-0.707, 0.707])
    L = np.array([side[0] * np.sin(np.radians(lift)), side[1] * np.sin(np.radians(lift)), np.cos(np.radians(lift))])
    a = mean - b * float(((N[k] @ L) * ww).sum() / ww.sum())
    return a, b, L, r2


def shading_relief(tone, N, depth, w, px, a, b, L, hollow=HOLLOW, smooth=0.03, hold=0.002, cap=3.5, fine=(4.0, 0.012, 0.004, 1.5), rounds=200, test=None):
    """How far each pixel's surface must be moved toward the eye (mm) for the model, drawn as the plates are drawn, to
    take the plate's lights and darks: the least movement (hold), smoothly spread (smooth), that makes
    (a + b (n . L)) (1 - hollow x how far the surface lies below its surroundings) match the tone where w trusts it.
    Two things darken a plate and both are in that rule: a face turned from the light, and a hollow (the sinus tarsi,
    the pit behind a process, a foramen), which an engraver draws dark whichever way it faces. So a dark that no turn
    of the face can give is sunk, and a light and dark side by side become a ridge or a rim.
    Done in two steps. First the plate's whole run of tone at half size, smoothly: the broad turn of each face and the
    hollows. Then at full size only what is finer than fine[0] mm (smoothness fine[1], hold fine[2], at most fine[3] mm
    more): ridges, grooves, rims and pits, which show as a light beside a dark.
    N: the model's normals as (right, up, toward the eye); depth: how far toward the eye the surface stands (nan off
    the bone)."""
    from scipy.optimize import minimize, Bounds
    L = np.asarray(L, float)

    def level(T, N, z0, w, px, x0, rounds, smooth, hold, lo, hi, broad=None, hollows=HOLLOWS, test=None):
        H, W = T.shape; m = (w > 0).astype(float); hw = (~np.isnan(z0)).astype(float); z0 = np.where(hw > 0, z0, 0.0)
        ne = np.clip(N[..., 2].astype(float), 0.2, None); g0r = -N[..., 0] / ne; g0u = -N[..., 1] / ne
        gm = np.maximum(ndi.gaussian_filter(m, broad / px, mode="constant"), 1e-3) if broad else None
        gh = [np.maximum(ndi.gaussian_filter(hw, sig / px, mode="constant"), 1e-3) for sig, _ in hollows]
        ref = np.zeros((H, W)) if x0 is None else x0

        def f(x):
            d = x.reshape(H, W); dr = np.zeros((H, W)); du = np.zeros((H, W))
            dr[:, :-1] = (d[:, 1:] - d[:, :-1]) / px; du[1:, :] = (d[:-1, :] - d[1:, :]) / px   # toward the right; upward (rows run down)
            gr = g0r + dr; gu = g0u + du; q = np.sqrt(1.0 + gr * gr + gu * gu); nl = (-gr * L[0] - gu * L[1] + L[2]) / q
            z = z0 + d; occ = np.zeros((H, W)); live = []
            for (sig, wt), g in zip(hollows, gh):
                raw = (ndi.gaussian_filter(hw * z, sig / px, mode="constant") / g - z) / (0.5 * sig)
                occ += wt * np.clip(raw, 0.0, 1.0); live.append(wt * ((raw > 0) & (raw < 1)) / (0.5 * sig))
            lit = a + b * nl; dark = 1.0 - hollow * occ
            e = lit * dark - T
            eh = e - ndi.gaussian_filter(m * e, broad / px, mode="constant") / gm if broad else e          # the misfit with its broad part taken off
            E = float((w * eh * eh).sum() + smooth * (dr * dr + du * du).sum() + hold * ((d - ref) ** 2).sum())
            c = 2.0 * w * eh
            if broad:
                c = c - m * ndi.gaussian_filter(c / gm, broad / px, mode="constant")                     # the same taken off the other way round (the adjoint)
            cn = c * dark * b
            cr = cn * (-L[0] / q - nl * gr / (q * q)) + 2.0 * smooth * dr
            cu = cn * (-L[1] / q - nl * gu / (q * q)) + 2.0 * smooth * du
            Gd = 2.0 * hold * (d - ref)
            Gd[:, 1:] += cr[:, :-1] / px; Gd[:, :-1] -= cr[:, :-1] / px; Gd[:-1, :] += cu[1:, :] / px; Gd[1:, :] -= cu[1:, :] / px
            co = -hollow * c * lit
            for ((sig, _), g), act in zip(zip(hollows, gh), live):
                k = co * act; Gd += hw * ndi.gaussian_filter(k / g, sig / px, mode="constant") - k
            return E, Gd.ravel()

        if test is not None:
            return f(test)
        best = minimize(f, ref.ravel().astype(float), jac=True, method="L-BFGS-B", bounds=Bounds((ref + lo).ravel(), (ref + hi).ravel()), options=dict(maxiter=rounds, maxcor=12))
        return best.x.reshape(H, W)

    T = tone.astype(float); w = w.astype(float); H, W = T.shape
    if test is not None:
        return level(T, N, depth, w, px, None, 0, smooth, hold, -cap, cap, broad=fine[0], test=test)

    def half(x, fill=0.0):                     # each 2 x 2 block's mean (of what is there)
        x = x[:H // 2 * 2, :W // 2 * 2]; k = ~np.isnan(x); x = np.where(k, x, 0.0)
        s = x.reshape(H // 2, 2, W // 2, 2).sum((1, 3)); n = k.reshape(H // 2, 2, W // 2, 2).sum((1, 3))
        return np.where(n > 0, s / np.maximum(n, 1), fill)

    N2 = np.stack([half(N[..., i].astype(float)) for i in range(3)], -1); N2 /= np.maximum(np.linalg.norm(N2, axis=2), 1e-6)[..., None]
    d2 = level(half(T), N2, half(depth.astype(float), np.nan), half(w), 2.0 * px, None, rounds, smooth, hold, -cap, cap)
    d0 = np.zeros((H, W)); up = np.repeat(np.repeat(d2, 2, 0), 2, 1); d0[:up.shape[0], :up.shape[1]] = up
    d0 = np.clip(ndi.gaussian_filter(d0, 0.8), -cap, cap)
    if not fine:
        return d0.astype(np.float32)
    return level(T, N, depth, w, px, d0, rounds, fine[1], fine[2], -fine[3], fine[3], broad=fine[0], hollows=HOLLOWS[:2]).astype(np.float32)


def likeness(tone, picture, w, px, over=1.0):
    """How alike a plate's lights and darks and the model's picture are where w trusts the plate: the correlation of
    the two, both eased over `over` mm (1 would be the same picture, 0 no likeness)."""
    k = w > 0.3; a = ndi.gaussian_filter(tone.astype(float), over / px)[k]; b = ndi.gaussian_filter(picture.astype(float), over / px)[k]
    a = a - a.mean(); b = b - b.mean()
    return float((a * b).sum() / max(np.sqrt((a * a).sum() * (b * b).sum()), 1e-9))


def tone_of(gray, mask, px, fine=0.9):
    """A plate's shading as tone (0 dark to 1 light) with the hatching run together over `fine` mm, the label lines
    that cross the bone painted over from beside them, and the inked outline left out; and how far each pixel of it is
    to be trusted (0 outside the bone and on its outline, 0.3 where a label line was painted over, else 1)."""
    g = no_text(gray); line = upright_lines(g) & ndi.binary_dilation(mask, iterations=3); g = g.astype(np.float32)
    wl = (~line).astype(np.float32); g = np.where(line, ndi.gaussian_filter(g * wl, 2.0) / np.maximum(ndi.gaussian_filter(wl, 2.0), 1e-3), g)
    inside = ndi.binary_erosion(mask, iterations=3)
    idx = ndi.distance_transform_edt(~inside, return_distances=False, return_indices=True)
    tone = ndi.gaussian_filter(g[tuple(idx)], fine / px) / 255.0
    ok = inside * np.where(ndi.binary_dilation(line, iterations=1), 0.3, 1.0)
    return tone.astype(np.float32), ok.astype(np.float32), line



def ink_of(gray, mask, px, lo=0.4, hi=2.0, along=2.0):
    """A plate's fine drawing as relief to lay on the model: what of its tone lies between lo and hi mm across, light
    for raised and dark for sunk, run together over `along` mm in the direction of the plate's own lines wherever
    they keep one direction (an engraver's lines follow the fibre of the bone's surface: streaks, not pits) and left
    as it is where they do not (pits, foramina, rough patches). 90 in 100 of it lie within -1 to 1; nothing within a
    millimetre of the outline, whose ink is no relief."""
    g = no_text(gray); line = upright_lines(g) & ndi.binary_dilation(mask, iterations=3); g = g.astype(np.float32)
    wl = (~line).astype(np.float32); g = np.where(line, ndi.gaussian_filter(g * wl, 2.0) / np.maximum(ndi.gaussian_filter(wl, 2.0), 1e-3), g)
    inside = ndi.binary_erosion(mask, iterations=3)
    idx = ndi.distance_transform_edt(~inside, return_distances=False, return_indices=True)
    t = g[tuple(idx)] / 255.0
    band = ndi.gaussian_filter(t, lo / px) - ndi.gaussian_filter(t, hi / px)
    gy, gx = np.gradient(ndi.gaussian_filter(t, 1.0))
    jxx, jxy, jyy = (ndi.gaussian_filter(a, 1.0 / px) for a in (gx * gx, gx * gy, gy * gy))
    th = 0.5 * np.arctan2(2 * jxy, jxx - jyy) + np.pi / 2                           # the lines' direction: across the steepest change
    one = np.sqrt((jxx - jyy) ** 2 + 4 * jxy ** 2) / np.maximum(jxx + jyy, 1e-9)    # how far the lines keep one direction (0 to 1)
    dx, dy = np.cos(th), np.sin(th); yy, xx = np.mgrid[0:t.shape[0], 0:t.shape[1]].astype(np.float32)
    n = max(int(round(along / px)), 1); run = np.zeros_like(band); ws = 0.0
    for k in range(-n, n + 1):
        wk = np.exp(-0.5 * (2.0 * k / n) ** 2); ws += wk
        run += wk * ndi.map_coordinates(band, [yy + k * dy, xx + k * dx], order=1, mode="nearest")
    band = one * 1.6 * run / ws + (1.0 - one) * band
    band = band / np.percentile(np.abs(band[inside]), 90)
    ease = np.clip(ndi.distance_transform_edt(inside) * px / 1.2, 0.0, 1.0)
    return (np.clip(band, -2.5, 2.5) * ease * ease * (3.0 - 2.0 * ease)).astype(np.float32)


def in_tones(picture, tone, k):
    """The model's picture given the plate's own run of tones (its darkest as dark as the plate's darkest, its lightest
    as light, and so between), so the two are compared at one contrast. The order of its tones is kept: nothing is
    drawn in that the model does not have."""
    q = np.linspace(0, 100, 101); a = np.percentile(picture[k].astype(float), q); b = np.percentile(tone[k].astype(float) * 255.0, q)
    out = np.interp(picture.astype(float), a + np.arange(101) * 1e-6, b)
    return np.where(picture < 255, np.clip(out, 0, 250), 255).astype(np.uint8)
