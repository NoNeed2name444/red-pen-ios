"""foot.py: the bones of the foot, built from nothing but what is read off Gray's plates (Anatomy of the Human Body,
20th edition, 1918, public domain) and his text. No scan and no other model is used. The owner, 18 Nov: "ignore skull
for now and start from foot upward."; 19 Nov, of the first heel bone: "the heel looks no where near similar as the images.",
and of the second: "bone surface details are not similar".

The right foot is built; the left is its mirror. Foot frame, millimetres: x toward the big toe's side (medial),
y up, z forward toward the toes. Each bone is first made in a frame of its own and then set in the foot.

A bone is made from its plates themselves, not from a reading of them by eye:
  1. its outline in each plate is found from the plate (platematch.silhouette) and the solid is what lies inside all of
     them, each seen from the direction its plate is drawn from, with the edges between rounded;
  2. what no outline can show (a shelf's underside, a hollow wall, how a surface slopes away from the eye) is cut in
     from Gray's text and the other plates' evidence;
  3. each plate's shading is turned into relief on the face that plate shows (emboss): the surface is moved until the
     model, lit as the plate is lit, takes the plate's lights and darks, so a ridge, a facet's rim or a foramen stands
     where the plate has it;
  4. the fine grain of bone goes over all.
dev/match_plates.py draws the result in each plate's own frame beside the plate and measures how far the outlines lie apart.

The calcaneus (Fig. 264 from above, 265 from below, 266 the lateral surface, 267 the medial; pp. 263 to 266). Its own
frame: z from the back of the tuberosity forward, y up, x toward the sustentaculum. Gray gives no measure in
millimetres: the bone is set 79 mm long in the side view, which fixes every other size by the plates' own proportions."""
import os
import numpy as np
from scipy import ndimage as ndi
import sdf
import platematch as pm
from sdf import Ellipsoid, Field, rot

HERE = os.path.dirname(os.path.abspath(__file__))

# Fig. 264, the left calcaneus from above, read off the plate under a millimetre grid (0.225 mm a pixel) and written for
# the right bone: x across, z up the plate from the tuberosity's lowest drawn point. The three surfaces for the talus:
CALC_FACETS = [[(-7.7, 57.8), (-0.2, 58.9), (6.6, 58.1), (12.6, 58.5), (16.0, 57.8), (17.5, 55.1), (15.6, 49.9), (13.4, 45.4),
                (10.0, 42.6), (5.1, 44.6), (1.4, 49.1), (-2.4, 52.1), (-6.2, 54.0), (-8.4, 56.3)],
               [(17.1, 65.8), (20.5, 66.4), (25.0, 63.6), (29.0, 60.2), (30.0, 57.4), (27.6, 56.2), (23.0, 58.4), (19.0, 61.0), (16.6, 63.6)],
               [(11.4, 77.0), (14.6, 75.6), (17.2, 71.0), (17.6, 66.6), (15.2, 67.0), (12.6, 70.6), (10.8, 74.4)]]
# on the same plate: the line that parts the sustentaculum and its facet from the posterior facet (the sulcus
# calcanei runs along it), and the furrow itself from its narrow medial end out into the sinus tarsi
CALC_SPLIT = [(40, 14.0), (44, 15.5), (48, 18.0), (52, 18.8), (58, 17.5), (61, 13.0), (64, 10.0), (70, 9.0), (80, 8.0)]      # (z, x)
CALC_SULCUS = [(18.6, 45.5), (18.8, 52.0), (17.5, 58.0), (12.0, 61.0), (4.0, 62.0), (-4.0, 62.5)]                              # (x, z)


def _ss(t):
    t = np.clip(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t)


def _bump(z, a, b, c, d):
    """0 before a, 1 from b to c, 0 after d, eased."""
    return _ss((z - a) / (b - a)) * (1.0 - _ss((z - c) / (d - c)))


def _near(X, Z, path):
    """Distance on the plan from each point to a bent line (x, z), and how far along it (0 to 1) the nearest point is."""
    P = sdf.spline(np.asarray(path, float), 0.5); n = len(P)
    d = np.full(np.broadcast(X, Z).shape, 1e9, np.float32); t = np.zeros_like(d)
    for i in range(n):
        e = np.sqrt((X - P[i, 0]) ** 2 + (Z - P[i, 1]) ** 2).astype(np.float32)
        t = np.where(e < d, i / (n - 1.0), t); d = np.minimum(d, e)
    return d, t


def _wave(X, Y, Z, seed, scale, n=7):
    """A smooth wandering field of about unit spread, the same at any grid step: n plane waves in chance directions,
    their lengths about `scale` mm. Used to bend a border that a rule would draw dead straight (bones do not run
    straight) and to vary how sharp it is along its length."""
    rng = np.random.default_rng(seed); out = 0.0
    for _ in range(n):
        d = rng.normal(size=3); d /= np.linalg.norm(d); k = 2.0 * np.pi / (scale * rng.uniform(0.7, 1.4))
        out = out + np.cos(k * (d[0] * X + d[1] * Y + d[2] * Z) + rng.uniform(0.0, 2.0 * np.pi))
    return (out * np.sqrt(2.0 / n)).astype(np.float32)


def _sinterp(x, xp, fp, soft):
    """np.interp eased over `soft` mm: a table's knots would else run across the bone as straight creases."""
    t = np.arange(xp[0] - 3.0 * soft, xp[-1] + 3.0 * soft, 0.1)
    f = ndi.gaussian_filter1d(np.interp(t, xp, fp), soft / 0.1, mode="nearest")
    return np.interp(x, t, f).astype(np.float32)


# Marks traced on the plates, in each plate's own pixels: what a plate draws that no outline shows and no rule gives.
# ("dot", (u, v), radius mm, height mm), ("line", [(u, v), ...], width mm, height mm), ("area", [(u, v), ...],
# height mm, soft edge mm); a height below 0 is sunk (a foramen, a slit), above 0 raised (a tubercle, a rim).
CALC_MARKS = {
    "Gray264": [("dot", (105, 150), 0.8, -1.3),                                       # the foramen in the floor of the sinus tarsi
                # the raised lateral part of the anterior process's upper face (for the extensor digitorum brevis)
                ("area", [(62, 95), (80, 84), (96, 92), (98, 120), (92, 150), (72, 152), (60, 125)], 1.0, 2.0)],
    "Gray266": [("dot", (305, 115), 0.5, -0.7), ("dot", (312, 130), 0.45, -0.7), ("dot", (265, 95), 0.4, -0.5),    # vascular foramina
                ("line", [(160, 88), (185, 90), (207, 93)], 1.2, 0.6),                # the sinus tarsi's lateral rim, a clear light edge
                # (the line the plate draws along the posterior facet's lateral margin is the facet's own edge, which
                # the facet's lip gives; cut in as a groove it read as a scratch, and is left out)
                ],
    "Gray267": [("dot", (215, 178), 0.55, -0.9),                                      # the foramen in the medial surface
                # the eminence low on the medial side in front
                ("area", [(296, 180), (305, 171), (322, 170), (331, 182), (328, 198), (314, 206), (300, 200)], 1.4, 1.5),
                ("line", [(96, 198), (120, 207), (148, 232), (168, 257)], 2.5, 1.0),   # the medial process's upper border
                ("line", [(70, 118), (80, 140), (90, 175), (96, 198)], 1.5, 0.7)],     # the rim of the tuberosity's hinder surface
    "Gray265": [# the anterior tubercle (for the plantar calcaneocuboid ligament), with the two pits the plate puts on it
                ("area", [(128, 120), (150, 113), (166, 122), (168, 145), (160, 162), (140, 166), (127, 155), (124, 135)], 1.3, 0.9),
                ("dot", (135, 125), 0.5, -0.6), ("dot", (128, 137), 0.45, -0.6),
                # the slit-like nutrient foramina of the sole
                ("line", [(163, 283), (167, 296)], 0.7, -0.8), ("line", [(150, 300), (152, 308)], 0.6, -0.6),
                ("line", [(160, 318), (162, 326)], 0.6, -0.6), ("line", [(140, 310), (141, 316)], 0.6, -0.6),
                ("line", [(176, 297), (178, 305)], 0.6, -0.6)],
}


def _marks_map(items, shape, px):
    """Traced marks as a picture of heights (mm toward the eye) the size of their plate."""
    from PIL import Image, ImageDraw
    k = 3; H, W = shape; d = np.zeros((H, W), np.float32)
    at = lambda u, v: ((u + 0.5) * k, (v + 0.5) * k)
    for kind, where, a, b in items:
        im = Image.new("L", (W * k, H * k), 0); dr = ImageDraw.Draw(im)
        if kind == "dot":
            (cx, cy), r = at(*where), a / px * k; dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255); height, soft = b, 0.4 * a
        elif kind == "line":
            pts = [at(u, v) for u, v in (sdf.spline(np.asarray(where, float), 2.0) if len(where) > 2 else where)]
            dr.line(pts, fill=255, width=max(1, int(round(a / px * k)))); height, soft = b, 0.35 * a
        else:
            dr.polygon([at(u, v) for u, v in sdf.spline(np.asarray(where, float), 2.0, closed=True)], fill=255); height, soft = a, b
        m = np.asarray(im.resize((W, H), Image.BOX), np.float32) / 255.0
        d += height * ndi.gaussian_filter(m, soft / px)
    return d


def _marks_soft(items, shape, px):
    """As _marks_map, but as bone has them: a foramen a bowl, not a drilled hole with a flat floor and sheer sides;
    a line (a slit, a rim) thinning out to nothing at its two ends, not a rod of one width with round ends."""
    from PIL import Image, ImageDraw
    k = 3; H, W = shape; d = np.zeros((H, W), np.float32)
    at = lambda u, v: ((u + 0.5) * k, (v + 0.5) * k)
    for kind, where, a, b in items:
        im = Image.new("L", (W * k, H * k), 0); dr = ImageDraw.Draw(im)
        if kind == "dot":
            (cx, cy), r = at(*where), 0.7 * a / px * k; dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255); height, soft = 1.2 * b, 0.6 * a
        elif kind == "line":
            pts = [at(u, v) for u, v in sdf.spline(np.asarray(where, float), 0.5)]; n = len(pts)
            for i in range(n - 1):
                t = (i + 0.5) / (n - 1.0); wd = a / px * k * (0.25 + 0.75 * np.sin(np.pi * t) ** 0.7)
                dr.line([pts[i], pts[i + 1]], fill=255, width=max(1, int(round(wd))))
            height, soft = b, 0.45 * a
        else:
            dr.polygon([at(u, v) for u, v in sdf.spline(np.asarray(where, float), 2.0, closed=True)], fill=255); height, soft = a, b
        m = np.asarray(im.resize((W, H), Image.BOX), np.float32) / 255.0
        d += height * ndi.gaussian_filter(m, soft / px)
    return d


def _unhidden(F, idx, over=1.2):
    """Eases a plate's say on what it sees (1 where nothing stands in front of a point, 0 where something does) to
    nothing over about two millimetres toward the edge of what it sees. Where a nearer part hides the surface, the say
    stops along that part's shadow line; a say that stops dead prints the line on the bone as a step and, where the
    line grazes the surface, as a grid of dots the size of the model's own grid (the medial wall under the shelf had
    three such grids)."""
    got = np.zeros(F.D.shape, np.float32); got[idx] = 1.0
    norm = np.maximum(ndi.gaussian_filter(got, over / F.h)[idx], 1e-3); del got

    def ease(say):
        vol = np.zeros(F.D.shape, np.float32); vol[idx] = say
        return np.minimum(say, _ss(2.0 * ndi.gaussian_filter(vol, over / F.h)[idx] / norm - 1.0))
    return ease


def lay(F, views, poses, maps, shared=False, rough=False):
    """Pictures of heights (mm, each the size of its plate: {fig: map}) set on the model where each plate has them:
    every point of the surface a plate sees squarely takes that plate's height, measured along the surface's own
    normal. shared: where two plates see a point it takes their mean, not their sum (the plates' fine drawing, which
    each of them has all over; a traced mark is on one plate). rough: not on the joint surfaces."""
    D = F.D; idx = np.nonzero(np.abs(D) < 3.0)
    g = np.gradient(ndi.gaussian_filter(D, 1.0 / F.h), F.h)
    n = np.stack([c[idx] for c in g], 1); n /= np.maximum(np.linalg.norm(n, axis=1), 1e-9)[:, None]; del g
    P = np.stack([F.ax[k][idx[k]] for k in range(3)], 1).astype(np.float64)
    total = np.zeros(len(P), np.float32); wsum = np.zeros(len(P), np.float32); ease = _unhidden(F, idx)
    for v in views:
        m = maps.get(v["fig"])
        if m is None:
            continue
        pose = poses[v["fig"]]; B = pm.basis(v, pose[:3]); px = v["s"] * pose[3]
        depth, _ = pm.cast(F, B, px, v["u0"] + pose[4], v["v0"] + pose[5], m.shape[::-1], normals=False)
        u, r = _pixels(v, pose, P[:, 0], P[:, 1], P[:, 2])
        front = _read(np.where(np.isnan(depth), -1e3, depth), u, r)
        wt = ease(_ss((P @ B[2] - front + 3.0) / 2.0)) * _ss((n @ B[2] - 0.1) / 0.3)
        total += (wt * _read(m, u, r)).astype(np.float32); wsum += wt.astype(np.float32)
    if shared:
        total /= np.maximum(wsum, 1.0)
    if rough and hasattr(F, "smooth"):
        total *= 1.0 - np.clip(F.smooth[idx], 0.0, 1.0)
    D[idx] -= total
    return F


def _cut(a, b, k):
    """What of a lies outside b's cut (sdf.smax), the edge between rounded over k mm, k given point by point."""
    h = np.clip(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
    return (b + (a - b) * h + k * h * (1.0 - h)).astype(np.float32)


def _tube(X, Y, Z, pts, r):
    """Distance to a bent rod through the points pts (x, y, z), r mm thick at each (round ends)."""
    pts = np.asarray(pts, float); r = np.broadcast_to(np.asarray(r, float), (len(pts),)); d = None
    for i in range(len(pts) - 1):
        a, ab = pts[i], pts[i + 1] - pts[i]
        t = np.clip(((X - a[0]) * ab[0] + (Y - a[1]) * ab[1] + (Z - a[2]) * ab[2]) / (ab @ ab), 0.0, 1.0)
        e = np.sqrt((X - a[0] - t * ab[0]) ** 2 + (Y - a[1] - t * ab[1]) ** 2 + (Z - a[2] - t * ab[2]) ** 2) - (r[i] + (r[i + 1] - r[i]) * t)
        d = e if d is None else np.minimum(d, e)
    return d.astype(np.float32)


def _one_piece(F):
    """Nothing loose: only the largest piece is kept."""
    lab, n = ndi.label(F.D < 0)
    if n > 1:
        F.D[(lab != 1 + int(np.argmax(ndi.sum(F.D < 0, lab, range(1, n + 1))))) & (F.D < 0)] = 0.5
    return F


def traces(name):
    """What dev/trace_plates.py took from a bone's plates: outlines, reliefs and the pose each plate was read at."""
    return np.load(os.path.join(HERE, "traces", name + "_plates.npz"))


def _pixels(view, pose, X, Y, Z):
    """Where points of the model fall on a plate drawn at `pose`: (column, row)."""
    B = pm.basis(view, pose[:3]); s = view["s"] * pose[3]
    u = view["u0"] + pose[4] + (X * B[0][0] + Y * B[0][1] + Z * B[0][2]) / s
    v = view["v0"] + pose[5] - (X * B[1][0] + Y * B[1][1] + Z * B[1][2]) / s
    return u, v


def _read(arr, u, v):
    """A plate-sized picture's values at (column, row), between its pixels."""
    shape = np.broadcast(u, v).shape
    c = [np.broadcast_to(v, shape).ravel(), np.broadcast_to(u, shape).ravel()]
    return ndi.map_coordinates(np.asarray(arr, np.float32), c, order=1, mode="nearest").reshape(shape).astype(np.float32)


def _round_meet(a, b, R):
    """Two solids' common part with the edge where their faces meet rounded to radius R."""
    a = a + R; b = b + R
    return (np.minimum(np.maximum(a, b), 0.0) + np.sqrt(np.maximum(a, 0.0) ** 2 + np.maximum(b, 0.0) ** 2) - R).astype(np.float32)


INK = 0.25        # mm: how far the plates' fine drawing stands in and out of the surface (9 in 10 of it within this)
RELIEF = dict(smooth=0.08, hold=0.002, cap=2.0, fine=None, rounds=140)      # how platematch.shading_relief is run
PROCS = 1         # the plates' reliefs one after another (side by side in four processes was slower here: 156 s against 60)
_JOB = {}


def _plate_relief(fig):
    """One plate's relief (run in a process of its own, the four plates side by side): (fig, relief map, the model's
    depth in the plate's frame, what was read of the light)."""
    F, tr, v, pose = _JOB["F"], _JOB["tr"], _JOB["views"][fig], _JOB["poses"][fig]
    B = pm.basis(v, pose[:3]); px = v["s"] * pose[3]
    tone = tr[fig + "_tone"].astype(np.float32) / 255.0; ok = tr[fig + "_ok"].astype(np.float32) / 255.0
    depth, N = pm.cast(F, B, px, v["u0"] + pose[4], v["v0"] + pose[5], tone.shape[::-1])
    hit = ~np.isnan(depth); w = ok * hit * _ss((N[..., 2] - 0.15) / 0.35)
    a, b, L, r2 = pm.light_of(tone, N, w)
    # a joint surface is smooth, and the plates fill it with even hatching, which says nothing of its shape: the
    # shading is not read there and no relief is laid on it
    rough = 1.0 - np.clip(pm.seen(F, F.smooth, B, px, v["u0"] + pose[4], v["v0"] + pose[5], depth), 0.0, 1.0) if hasattr(F, "smooth") else 1.0
    d = pm.shading_relief(tone, N, depth, w * rough, px, a, b, L, **RELIEF) * rough
    d *= np.clip(ndi.distance_transform_edt(hit & (ok > 0)) * px / 1.5, 0.0, 1.0)        # eased to nothing at the outline
    return fig, d, depth, (a, b, L, r2)


def emboss(F, tr, views, poses, gain=1.0, log=None):
    """Each plate's shading turned into relief on the face it shows. The model is drawn in the plate's frame; the light
    the plate is shaded by is read from the plate against the model's own faces (platematch.light_of); then each pixel's
    surface is moved toward or from the eye, as little and as smoothly as will do, until the model so lit takes the
    plate's lights and darks (platematch.shading_relief): a ridge, a groove, a facet's edge or a foramen then stands
    where the plate draws it. A point of the model takes a plate's relief by how squarely its surface faces that
    plate's eye, and only if nothing stands in front of it in that view."""
    import multiprocessing as mp
    reach = RELIEF["cap"] + (RELIEF["fine"][3] if RELIEF["fine"] else 0.0)
    D = F.D; idx = np.nonzero(np.abs(D) < reach + 1.5)
    g = np.gradient(ndi.gaussian_filter(D, 1.0 / F.h), F.h)
    n = np.stack([c[idx] for c in g], 1); n /= np.maximum(np.linalg.norm(n, axis=1), 1e-9)[:, None]; del g
    P = np.stack([F.ax[k][idx[k]] for k in range(3)], 1).astype(np.float64)
    total = np.zeros(len(P), np.float32); wsum = np.zeros(len(P), np.float32)
    _JOB.update(F=F, tr={k: tr[k] for k in tr.files}, views={v["fig"]: v for v in views}, poses=poses)
    if PROCS > 1:
        with mp.get_context("fork").Pool(min(PROCS, len(views))) as pool:
            out = pool.map(_plate_relief, [v["fig"] for v in views])
    else:
        out = [_plate_relief(v["fig"]) for v in views]
    _JOB.clear(); F.relief = {}; ease = _unhidden(F, idx)
    for v, (fig, d, depth, (a, b, L, r2)) in zip(views, out):
        pose = poses[fig]; B = pm.basis(v, pose[:3]); hit = ~np.isnan(depth); F.relief[fig] = d
        if log:
            log("  %s: light from right %.2f up %.2f eye %.2f (tone = %.2f + %.2f n.L, explains %.2f); relief %.1f to %.1f mm"
                % (fig, L[0], L[1], L[2], a, b, r2, d.min(), d.max()))
        u, r = _pixels(v, pose, P[:, 0], P[:, 1], P[:, 2])
        front = _read(np.where(hit, depth, -1e3), u, r); face = n @ B[2]
        wt = ease(_ss((P @ B[2] - front + max(4.0, reach + 1.0)) / 2.5)) * _ss((face - 0.1) / 0.4)
        total += (wt * _read(d, u, r) * face).astype(np.float32); wsum += wt.astype(np.float32)
    D[idx] -= gain * total / np.maximum(wsum, 1.0)
    return F


def _emboss_eased(F, tr, views, poses, gain=1.0, log=None, apart=0.8, over=1.5):
    """emboss, but where the plates that see a point disagree on how far to move it (by `apart` mm and more, between
    their weighted spread), what they move is eased together over `over` mm: there the surface would else go from one
    plate's height to the other's within the millimetre in which the edge turns from one eye to the other."""
    reach = RELIEF["cap"] + (RELIEF["fine"][3] if RELIEF["fine"] else 0.0)
    D = F.D; idx = np.nonzero(np.abs(D) < reach + 1.5)
    g = np.gradient(ndi.gaussian_filter(D, 1.0 / F.h), F.h)
    n = np.stack([c[idx] for c in g], 1); n /= np.maximum(np.linalg.norm(n, axis=1), 1e-9)[:, None]; del g
    P = np.stack([F.ax[k][idx[k]] for k in range(3)], 1).astype(np.float64)
    _JOB.update(F=F, tr={k: tr[k] for k in tr.files}, views={v["fig"]: v for v in views}, poses=poses)
    out = [_plate_relief(v["fig"]) for v in views]
    _JOB.clear(); F.relief = {}; ease = _unhidden(F, idx); cs, ws = [], []
    for v, (fig, d, depth, (a, b, L, r2)) in zip(views, out):
        pose = poses[fig]; B = pm.basis(v, pose[:3]); hit = ~np.isnan(depth); F.relief[fig] = d
        if log:
            log("  %s: light from right %.2f up %.2f eye %.2f (tone = %.2f + %.2f n.L, explains %.2f); relief %.1f to %.1f mm"
                % (fig, L[0], L[1], L[2], a, b, r2, d.min(), d.max()))
        u, r = _pixels(v, pose, P[:, 0], P[:, 1], P[:, 2])
        front = _read(np.where(hit, depth, -1e3), u, r); face = n @ B[2]
        wt = ease(_ss((P @ B[2] - front + max(4.0, reach + 1.0)) / 2.5)) * _ss((face - 0.1) / 0.4)
        cs.append((_read(d, u, r) * face).astype(np.float32)); ws.append(wt.astype(np.float32))
    cs, ws = np.array(cs), np.array(ws); wsum = ws.sum(0)
    mean = (ws * cs).sum(0) / np.maximum(wsum, 1e-6)
    spread = np.sqrt((ws * (cs - mean) ** 2).sum(0) / np.maximum(wsum, 1e-6))
    move = (ws * cs).sum(0) / np.maximum(wsum, 1.0); del cs, ws
    vol = np.zeros(D.shape, np.float32); vol[idx] = move; on = np.zeros(D.shape, np.float32); on[idx] = 1.0
    s = over / F.h; eased = ndi.gaussian_filter(vol, s)[idx] / np.maximum(ndi.gaussian_filter(on, s)[idx], 1e-3); del vol, on
    a = np.zeros(D.shape, np.float32); a[idx] = _ss(spread / apart)
    a = ndi.gaussian_filter(a, s)[idx]                       # the easing itself comes in gradually
    D[idx] -= gain * (move + a * (eased - move))
    return F


def calcaneus(h=0.4, log=print, relief=1.0, upto="all", poses=None, ink=INK):
    """upto="hull" stops at the bare solid inside the outlines of Fig. 264 and the two side plates (what the plates'
    poses are fitted on, dev/fit_plates.py); `poses` tries other poses than the traces were made at ({fig: pose})."""
    F = Field((-24.0, -8.0, -6.0), (40.0, 58.0, 88.0), h)
    X, Y, Z = F.coords((slice(None),) * 3)
    tr = traces("calcaneus"); V = {v["fig"]: v for v in pm.CALCANEUS}
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}

    def outline(fig, dz=0.0, x=X):  # eased over a millimetre: an outline's small wiggles would else run right across the bone as flutes
        px = V[fig]["s"] * P[fig][3]; d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
        return _read(ndi.gaussian_filter(d, 1.0 / px), *_pixels(V[fig], P[fig], x, Y, Z + dz))

    # the front (for the cuboid) is convex from side to side (Gray: "concave from above downward and lateralward, and
    # convex in a direction at right angles to this"): the profile stands 2 mm farther back at the face's two edges
    bow = 0.0 if upto == "hull" else 2.0 * np.clip(((X - 4.0) / 12.0) ** 2, 0.0, 1.5) * _ss((Z - 64.0) / 8.0)

    # 1. inside the plates' outlines. The plan is Fig. 264's above mid height and Fig. 265's below. The two side plates
    # are both drawn from some 12 degrees above (each shows the upper joint surfaces, which a level side view could
    # not), so their outlines carried through the bone lean toward each other: what lies inside both has a ridged top
    # and a keeled sole, the lateral plate ruling the lateral slope and the lateral process, the medial plate the
    # medial slope and the medial process.
    plan = outline("Gray264")
    if upto != "hull":
        plan = plan + (outline("Gray265") - plan) * _ss((31.0 - Y) / 12.0)
    side = sdf.smax(outline("Gray266", bow), outline("Gray267", bow), 1.5)
    R = ndi.gaussian_filter1d(np.interp(F.ax[2], [0.0, 40.0, 60.0, 72.0, 80.0], [11.0, 10.5, 7.0, 4.5, 3.0]), 4.0 / h)[None, None, :]
    R = R - (R - 3.5) * _ss((X - 2.0) / 6.0) * _ss((Y - 34.0) / 6.0) * _bump(Z, 28.0, 35.0, 62.0, 66.0)      # the facet's medial rim is no rounded edge
    # below, the lateral surface turns under into the sole all along (Gray: the plantar surface "convex from side to
    # side"; Fig. 266 shades the lower third of the lateral surface dark right to the front)
    Rb = ndi.gaussian_filter1d(np.interp(F.ax[2], [0.0, 40.0, 62.0, 72.0, 80.0], [11.0, 11.0, 10.0, 7.5, 4.0]), 4.0 / h)[None, None, :]
    R = R + (Rb - R) * _ss((20.0 - Y) / 10.0) * _ss((6.0 - X) / 8.0)
    D = _round_meet(plan, side, R)
    # (the edges where the faces meet neither run dead straight nor are rounded alike all along, as an outline carried
    # through the bone would leave them: along each the bone stands up to half a millimetre out or in, over some 9 mm,
    # so the edge wanders and is sharp in one place and broad in the next. Only near an edge (where both outlines are
    # close), and as much out as in, so the outlines lie no farther from the plates' on the mean. Widening the
    # rounding itself instead, by as much, ran over whole faces as lumps.)
    D = D + 0.3 * _wave(X, Y, Z, 31, 9.0) * _ss(np.minimum(plan, side) / R + 1.0)
    del plan, side
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    p4 = P["Gray264"]

    def on264(X, Y, Z):        # Fig. 264's own coordinates (its tracings above are in them)
        u, v = _pixels(V["Gray264"], p4, X, Y, Z); return (u - 87.0) * 0.225, (421.0 - v) * 0.225

    # 2a. the upper surface, where the outlines leave it too high. Heights are read off Fig. 266 as drawn from 14
    # degrees above (a point x mm medial stands 0.24 x higher in it). Lateral to the split line the posterior facet:
    # all but level from side to side (its medial edge and its lateral border read within a millimetre or two of one
    # height), falling forward from 47 mm at its hind end to 43 at z 51 and curling down to 37 at its front corner
    # (Gray: convex from behind forward); in front of it the floor of the sinus tarsi, lowest just before the facet
    # (its lateral rim stays 36 to 37 mm up from z 57 to 68, where the plate's dark hollow ends on a clear line) and
    # back up to 42 on the anterior process in front of z 71. Medial to the line the sustentaculum's upper face, 42 mm
    # up and falling forward.
    zs = F.ax[2][None, :]; xs = F.ax[0][:, None]
    yref = np.interp(zs, [0.0, 30, 36, 43, 47, 51, 56.9, 66, 80], [44.0, 49, 47.6, 47, 45.3, 43, 37, 40.8, 41.5])
    u2, v2 = _pixels(V["Gray264"], p4, xs, yref, zs); xp = (u2 - 87.0) * 0.225; zp = (421.0 - v2) * 0.225
    split = np.interp(zp, [a for a, _ in CALC_SPLIT], [b for _, b in CALC_SPLIT])
    free = 70.0 + 0 * xp
    facet = ndi.gaussian_filter1d(np.interp(F.ax[2], [30.0, 36, 40, 43.3, 47.3, 51.4, 55.7, 58, 62], [52.0, 47.6, 47.2, 47.0, 45.3, 43.0, 38.0, 35.5, 33.0]), 1.0 / h)[None, :] + 0.05 * (xp - 6.0)
    floor = np.interp(zs, [56.9, 60, 64, 68, 70.5, 73, 79], [36.5, 36.3, 36.6, 37.3, 40.0, 41.8, 41.5]) + 1.0 * np.clip((xp + 8.0) / np.maximum(split + 8.0, 1.0), 0.0, 1.0) ** 1.5
    f = _ss((zp - 57.5) / 3.0); lateral = np.minimum(facet * (1.0 - f) + floor * f, free)
    b = _bump(zs, 40.0, 44.0, 68.0, 72.0)
    shelf = (np.clip(42.0 + 4.0 * (1.0 - _ss((zs - 58.0) / 8.0)) - 0.21 * (zs - 58.0), 39.0, 47.0) - 0.08 * (xp - 18.0)) * b + free * (1.0 - b)
    w = _ss((xp - split + 1.5) / 3.0); top = lateral * (1.0 - w) + shelf * w
    d, t = _near(xp, zp, CALC_SULCUS)
    # (the sulcus calcanei is "a deep depression continued backward and medialward in the form of a groove": Fig. 264
    # draws it a dark furrow between the posterior facet and the sustentaculum, and Fig. 266 looks into its wide
    # lateral end, the sinus tarsi, as the darkest hollow of the bone, in front of the posterior facet)
    top = top - (3.0 + 1.5 * t) * np.exp(-(d / (2.0 + 3.0 * t)) ** 2)
    # (the sinus tarsi itself: Fig. 264 draws a hollow some 10 mm across and 13 long in front of the posterior facet,
    # between the raised lateral part of the anterior process and the two front facets, with a foramen in its floor)
    top = top - 2.6 * np.exp(-(((xp - 6.0) / 4.5) ** 2 + ((zp - 65.5) / 5.5) ** 2))
    top = ndi.gaussian_filter(top.astype(np.float32), 0.8 / h); gx, gz = np.gradient(top, h)
    # (the shelf's free border is a flat face with a clear edge above and below, as Fig. 267 draws it: the cuts that
    # make its upper face and its underside meet that border all but sharp, everything else rounded over 2 mm)
    xp3, zp3 = on264(X, Y, Z)
    edge = 2.0 - 1.3 * _ss((xp3 - 19.0) / 4.0) * _bump(Z, 42.0, 46.0, 66.0, 70.0)
    D = _cut(D, (Y - top[:, None, :]) / np.sqrt(1.0 + gx ** 2 + gz ** 2)[:, None, :], edge)
    # 2b. the sustentaculum is a shelf: under it the wall falls back into the groove for the flexor hallucis longus
    # (the shelf thinner toward its free edge, and never less than 5 mm of bone left under the upper surface)
    # (the cut comes in from behind gradually and from clear of the wall: begun at once, 2 mm short of the wall, it
    # left a seam down the wall at z 42; its tables are eased so that their knots draw no lines across the bone)
    wall = _sinterp(zp3, [30.0, 38, 42, 46, 50, 58, 64, 70, 74, 80], [40.0, 30.0, 21.0, 18.0, 18.5, 18.0, 16.5, 17.0, 17.5, 40], 1.5)
    # (Fig. 267 draws the shelf's free border as a face 6 to 7 mm tall that falls forward: under pixels (270, 135),
    # (285, 145) and (300, 152) its lower edge stands 36.7, 34.3 and 32.4 mm up; in front of z 60 the shelf is a
    # thinner ledge under the middle facet's fore end. The groove is deeper at the shelf's root.)
    under = _sinterp(Z, [42.0, 45, 49, 52, 55, 58, 61, 66, 72], [42.5, 41.0, 38.3, 36.2, 33.8, 31.9, 32.5, 34.5, 36.5], 1.0) - 2.0 * (1.0 - _ss((xp3 - 19.0) / 9.0))
    under = np.minimum(under, top[:, None, :] - 5.0)
    D = _cut(D, sdf.smin(xp3 - wall, under - Y, 3.0), edge); del wall, under, edge
    # 2c. the medial surface is deeply hollowed below and behind the shelf; the trochlear process is a knob at mid height
    D = sdf.smax(D, -Ellipsoid((24.0, 25.0, 36.0), (13.5, 12.0, 24.0), rot((1, 0, 0), -12.0))(X, Y, Z), 5.0)
    # (the groove for the flexor hallucis longus: Fig. 267 draws it the darkest band of the medial side, close under
    # the shelf's free border and falling forward with it, some 6 mm wide)
    D = sdf.smax(D, -_tube(X, Y, Z, [(17.0, 34.0, 50.5), (17.6, 31.6, 55.0), (18.0, 28.6, 61.0), (17.5, 26.5, 66.5)],
                           [1.6, 3.0, 3.2, 2.2]), 1.6)
    # (the trochlear process. Fig. 264's outline has it as a bump 4 mm proud; drawn out as a prism that would be a
    # flute down the whole wall, so the bump is taken off to the wall's own line and the process set on as what Fig. 266
    # draws (read as from 14 degrees above): a ridge whose crest runs level, 31 to 32 mm up, from z 45 to z 57, where it
    # turns down and ends 24 mm up at z 58, a hook; in the hook, under the crest, the groove for the peroneus longus
    # begins as a deep pit (the plate's label ends in it) and runs downward and forward under the hook's end to the
    # lower border. Fig. 264's bump and Fig. 265's then fall on the same ridge.)
    # (lower down the plan is Fig. 265's, which has the bump 4 mm farther forward: the trim follows it)
    zt = zp3 - 4.5 * _ss((27.0 - Y) / 8.0) * _ss((zp3 - 52.0) / 4.0)
    out = np.interp(zt, [42.0, 46, 52, 58, 61], [-40.0, -14.5, -13.6, -12.5, -40])
    D = sdf.smax(D, out - xp3, 1.0); del out, zt
    D = sdf.smin(D, _tube(X, Y, Z, [(-14.0, 31.4, 44.5), (-15.1, 31.5, 48.5), (-15.4, 31.0, 53.0), (-15.2, 29.6, 56.6), (-14.7, 26.6, 57.8),
                                    (-13.6, 23.6, 58.0)], [1.4, 1.9, 2.1, 2.0, 1.8, 1.3]), 2.0)    # (eased in over 2 mm: at 1.4 its foot was a dark pen line)
    # (the pit under the crest is no round hole: Fig. 266 draws it flat-topped under the crest, widest behind, and
    # narrowing downward and forward into the groove; two unequal hollows run together, and the groove begins wide)
    # (their rims eased over 2.4 mm: a crisp oval rim read as a capsule pressed into the wall)
    D = sdf.smax(D, -Ellipsoid((-13.3, 27.0, 48.6), (3.1, 2.6, 3.6), rot((1, 0, 0), 18.0))(X, Y, Z), 2.4)
    D = sdf.smax(D, -Ellipsoid((-13.4, 25.2, 51.6), (2.7, 3.0, 2.6), rot((1, 0, 0), -25.0))(X, Y, Z), 2.4)
    D = sdf.smax(D, -_tube(X, Y, Z, [(-13.8, 25.2, 52.0), (-13.9, 23.4, 54.8), (-14.0, 21.3, 58.0), (-11.0, 19.3, 64.0), (-7.5, 17.2, 70.0)],
                           [2.7, 2.4, 2.0, 1.9, 1.6]), 2.2)
    # (the lateral process of the tuberosity: Fig. 266 draws it a rounded knob at the lower hind corner of the lateral
    # surface, 22 mm from the back, with a shallow hollow between it and the hinder surface)
    # (the wall there stands at x -12 to -13: set at x -10 the hollow went 5 mm in and left a sheer wall in front of
    # it at z 19, which read as a tooth with a crescent cut behind it, and the knob stood no more than half a
    # millimetre proud. Now the knob stands 1.5 mm out, the hollow is 2 mm deep, both eased in over 2.5 to 3 mm.)
    D = sdf.smin(D, Ellipsoid((-11.5, 6.8, 23.5), (3.2, 4.2, 4.6))(X, Y, Z), 2.5)
    D = sdf.smax(D, -Ellipsoid((-13.0, 10.2, 16.2), (2.6, 4.0, 5.0))(X, Y, Z), 3.0)
    # 2d. the tuberosity's hinder surface and its two processes below stand a little proud of the body, marked off by a
    # line: on the upper surface it runs across 20 mm from the back (Fig. 264), on the sides nearer the back and
    # slanting forward as it goes down (Fig. 267), below it bounds the two processes with the notch between them (Fig. 265)
    sn = np.sin(np.arctan2(Y - 22.0, X - 2.0)); up = np.maximum(sn, 0.0) ** 1.5; down = np.maximum(-sn, 0.0) ** 1.5
    # (Fig. 265 has the two processes' front border 30 mm from the back, the notch between them a little behind it)
    line = 11.0 + 9.0 * up + (19.5 + 0.05 * (X - 2.0) - 3.0 * np.exp(-((X + 2.0) / 4.0) ** 2)) * down
    # (no such line is ruled: it wanders a millimetre or so either way, is a clear step in one place and a
    # slope over 4 mm in the next, and stands higher and lower along its length)
    line = line + 1.2 * _wave(X, Y, Z, 41, 18.0)
    # (on the two sides, where no plate draws it as a line, it is a low slope: kept sheer there it ran down the
    # medial and lateral faces as a crack, and cut a sickle beside the lateral process)
    side = 1.0 - np.abs(sn); wid = 2.0 * np.exp(0.4 * _wave(X, Y, Z, 42, 12.0)) * (1.0 + 1.5 * side)
    D = D - (0.5 + 1.2 * down) * (1.0 - 0.6 * side) * np.exp(0.3 * _wave(X, Y, Z, 43, 15.0)) * _ss((line - Z) / wid)
    del sn, up, down, line, wid, side
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32)
    # the three surfaces for the talus are smooth (no grain on them): their outlines, as Fig. 264 draws them
    from PIL import Image, ImageDraw
    im = Image.new("L", tr["Gray264_sdf"].shape[::-1], 0)
    for poly in CALC_FACETS:
        ImageDraw.Draw(im).polygon([(87.0 + x / 0.225, 421.0 - z / 0.225) for x, z in sdf.spline(np.asarray(poly, float), 0.4, closed=True)], fill=255)
    m = _read(ndi.gaussian_filter(np.asarray(im, np.float32) / 255.0, 1.2), *_pixels(V["Gray264"], p4, X, Y, Z))
    m = m * _ss((Y - top[:, None, :] + 5.0) / 2.0)
    # each stands a little proud, its margin a rounded lip (a step 0.6 mm tall over a quarter of a millimetre read as
    # a wire laid round it), the lip a little higher in some places than in others
    m2 = _read(ndi.gaussian_filter(np.asarray(im, np.float32) / 255.0, 4.0), *_pixels(V["Gray264"], p4, X, Y, Z)) * _ss((Y - top[:, None, :] + 5.0) / 2.0)
    F.D -= (0.5 + 0.15 * _wave(X, Y, Z, 51, 6.0)) * _ss(m2 / 0.8)
    F.smooth = np.maximum(m, _ss((Z - 76.0) / 2.0) + 0.0 * m).astype(np.float32)
    # (the rough faces are not flat between their borders: they swell and sink a tenth or two of a millimetre over
    # some 15 mm, as much out as in; shorter or deeper waves read as hammered metal)
    F.D += 0.1 * _wave(X, Y, Z, 61, 15.0) * (1.0 - F.smooth)
    lay(F, pm.CALCANEUS, P, {f: _marks_soft(m, tr[f + "_sdf"].shape, V[f]["s"] * P[f][3]) for f, m in CALC_MARKS.items()})
    # 3. the plates' relief
    if relief:
        # (where two plates see one edge they can ask for very different heights, Fig. 264 a 1.5 mm swell on top of the
        # tuberosity, Fig. 267 a 1.4 mm hollow under it on the medial face; as the edge turns from one eye to the other
        # the surface went from the one to the other in a millimetre and drew the edge as a crack. What the plates
        # move is eased together over a millimetre and a half there, and only there: eased all over, it took the relief
        # off thin parts such as the shelf, whose two faces' reliefs ran together.)
        _emboss_eased(F, tr, pm.CALCANEUS, P, relief, log)
    # 4. the plates' fine drawing: the streaks, pits and rough patches each plate draws on the faces it shows
    if ink:
        lay(F, pm.CALCANEUS, P, {f: tr[f + "_ink"].astype(np.float32) * (ink / 50.0) for f in V}, shared=True, rough=True)
    log("calcaneus: built from its four plates")
    return _one_piece(F)                                           # no crumb left by a cut


def grain(F, seed=264, amp=0.12, fibre=0.02):
    """A bone's fine unevenness (no surface of it is polished): chance, smoothed over about a millimetre and over four;
    and the faint lengthwise fibre its rough surfaces show (Gray's plates draw it), chance drawn out along the bone."""
    from scipy import ndimage
    rng = np.random.default_rng(seed); n = F.D.shape
    a = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), 1.0 / F.h); a /= a.std()
    b = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), 3.5 / F.h); b /= b.std()
    c = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), (0.45 / F.h, 0.45 / F.h, 7.0 / F.h)); c /= c.std()
    F.D += (amp * (0.6 * a + 0.8 * b) + fibre * c) * (1.0 - 0.85 * getattr(F, 'smooth', 0.0))
    return _one_piece(F)
