"""The forearm and hand bones of both atlas bodies, found in CT scans and
posed into each body's skin. Called by tools/anatomy_gaps.py; not run on
its own.

The TotalSegmentator dataset (CC BY 4.0) segments no bone below the
humerus, and the model it offers for the arm and hand bones is not under
CC BY, so the bones are found here in the scans' CT itself:

1. Bone by density: the CT above 180 HU without metal (above 1800 HU, with
   2 voxels around it), opened, without the bones the dataset does segment.
   The forearm and hand are the piece that holds the point given in LIMBS,
   with the small pieces within 10 mm of it, ring by ring (the scan sets
   some fingers' bones apart at their joints), but not the ECG leads lying
   on the skin: their metal cores make them denser than bone. Pieces denser
   than bone that remain (a clip on a fingertip) are taken out.
2. On a grid twice as fine (cubic, smoothed by 0.9 mm): the bone, cut into
   pieces where it narrows (a watershed from what is above 400 HU, split
   again where a piece is too big and round to be one bone). The CT is kept
   as it is within 15 mm of the bone, so the fingertips' faint tufts stay.
3. The hand's five rays: the fingertips as the bone's farthest points from
   the forearm, joints of up to 4.5 mm bridged at a cost (wider ones by a
   straight line), each traced back
   along the middle of the bone into the carpus. The rays are told apart by
   where they lie: the thumb's is the one farthest from the others, then
   the index, middle, ring and little fingers in order away from it.
4. The joints along each ray, in millimetres from its tip, read by eye from
   the CT straightened along the ray (LIMBS below). A seed in the middle of
   each bone (a disc either side of a joint the CT shows only faintly), the
   tufts taken in, then a random walk from the seeds over the bone, on the
   CT with its joint lines darkened (thin dark sheets between bright
   plates), gives each bone; each is then closed. The radius and ulna are
   seeded from the two longest pieces, the carpus from the piece the rays
   end in. The carpal bones stay one structure: at this resolution they
   are not told apart reliably.

One hand per body is taken from a scan: the other side is its mirror
image (noted in SOURCES.md). The scans:

- the man's: s1880 (a man of 37), his left forearm and hand; s1803, the
  male body's scan, has its hands cut off by the field of view;
- the woman's: s1764 (a woman of 32, the female body's scan), her right.
"""
import os

import numpy as np
from scipy import ndimage

FINGERS = ("thumb", "index", "middle", "ring", "little")
METACARPAL = {"thumb": "first", "index": "second", "middle": "third", "ring": "fourth", "little": "fifth"}
# UBERON ids, checked against the ontology (EBI OLS): the carpal bones are
# one structure here, so the carpal skeleton's id; per digit, 1 the thumb.
_DIGIT = {"thumb": 1, "index": 2, "middle": 3, "ring": 4, "little": 5}
_PHALANX = {("distal", 1): "0004337", ("distal", 2): "0004311", ("distal", 3): "0004312", ("distal", 4): "0004313",
            ("distal", 5): "0004314", ("middle", 2): "0004320", ("middle", 3): "0004321", ("middle", 4): "0004322",
            ("middle", 5): "0004323", ("proximal", 1): "0004338", ("proximal", 2): "0004328",
            ("proximal", 3): "0004329", ("proximal", 4): "0004330", ("proximal", 5): "0004331"}
UBERON = {"radius": "0001423", "ulna": "0001424", "carpal bones": "0009880", "first metacarpal": "0003645",
          "second metacarpal": "0003646", "third metacarpal": "0003647", "fourth metacarpal": "0003648",
          "fifth metacarpal": "0003649"}
for (_k, _d), _id in _PHALANX.items():
    _f = next(f for f, d in _DIGIT.items() if d == _d)
    UBERON[f"{_k} phalanx of thumb" if _f == "thumb" else f"{_k} phalanx of {_f} finger"] = _id

# Per body: the scan, the side taken, a scan voxel inside its radius, and per
# finger the joints along its ray (mm from the tip: distal, proximal
# interphalangeal (one for the thumb), metacarpophalangeal), where the
# metacarpal's base ends (the carpometacarpal joint), where the ray is in the
# carpus, and optionally the joints seeded by discs and the threshold for the
# tuft. A joint below 0 lies past the bone's tip: that distal phalanx is
# all tuft. The joints were read off strips of the CT along each ray and,
# for the middle joints and knuckles, where the brightest bone in each
# cross-section dips (a hollow shaft keeps its bright rim, a joint gap does
# not; a fingertip's narrow waist dips too, so not for the end joints).
LIMBS = {
    "male": {
        "subject": "s1880", "side": "left", "point": (50, 150, 438),
        "fingers": {
            "thumb": {"joints": [17.5, 59], "base_end": 106, "carpus_from": 114},
            "index": {"joints": [9.8, 28.5, 75], "base_end": 145, "carpus_from": 158},
            "middle": {"joints": [7.8, 33, 85.2], "discs": [2], "base_end": 157, "carpus_from": 166},
            "ring": {"joints": [7.2, 30.5, 84.5], "discs": [2], "base_end": 150, "carpus_from": 163},
            "little": {"joints": [-1, 21.5, 55.7], "base_end": 116, "carpus_from": 124, "tip_hu": 90},
        },
    },
    "female": {
        "subject": "s1764", "side": "right", "point": (271, 225, 745),
        "fingers": {
            "thumb": {"joints": [20, 47], "base_end": 112, "carpus_from": 118},
            "index": {"joints": [10.5, 28, 80], "base_end": 149, "carpus_from": 156},
            "middle": {"joints": [12, 35.5, 89], "base_end": 156, "carpus_from": 162},
            "ring": {"joints": [20, 43.5, 92], "base_end": 153, "carpus_from": 160},
            "little": {"joints": [16.5, 31, 66], "base_end": 131, "carpus_from": 138},
        },
    },
}
# The bones the dataset segments that the limb can touch, taken out before the limb is found.
KNOWN = ["humerus_left", "humerus_right", "femur_left", "femur_right", "hip_left", "hip_right"]
UP = 2          # the fine grid: this many voxels to the scan's one
VX = 1.5 / UP   # its spacing, mm (the scans are 1.5 mm isotropic)


def log(*a):
    print(*a, flush=True)


def bone_names(finger):
    m = METACARPAL[finger] + " metacarpal"
    if finger == "thumb":
        return ["distal phalanx of thumb", "proximal phalanx of thumb", m]
    return [f"{k} phalanx of {finger} finger" for k in ("distal", "middle", "proximal")] + [m]


def uberon_of(name):
    return "UBERON:" + UBERON[name]


# MARK: 1-2. the bone, on a finer grid, in pieces

def components(ct, known):
    """The bone the dataset does not segment, by density, in connected pieces."""
    bone = (ct > 180) & ~ndimage.binary_dilation(ct > 1800, iterations=2)
    bone = ndimage.binary_opening(bone, ndimage.generate_binary_structure(3, 1))
    bone &= ~ndimage.binary_dilation(known, iterations=2)
    lab, _ = ndimage.label(bone, structure=np.ones((3, 3, 3)))
    return lab


def work_volume(ct, lab, point, margin=16, keep=10, reach_mm=10.0):
    """The limb's CT on the fine grid, smoothed, and its bone."""
    comp = lab == lab[tuple(point)]
    assert comp.any() and lab[tuple(point)] > 0, f"no bone at {point}"
    sizes = np.bincount(lab.ravel())
    # the small pieces near it (a finger's bones the scan sets apart at its joints), ring by ring, within
    # reach_mm of what is taken; not the leads lying on the skin, whose metal cores make them denser than bone
    idx = np.argwhere(comp); a = np.maximum(idx.min(0) - 60, 0); b = idx.max(0) + 61
    sl = tuple(slice(x, y) for x, y in zip(a, b)); L, C, A = lab[sl], comp[sl].copy(), ct[sl]
    ids = np.unique(L[L > 0]); dense = dict(zip(ids.tolist(), ndimage.mean(A, L, ids)))
    for _ in range(8):
        d = ndimage.distance_transform_edt(~C) * 1.5
        near = [int(i) for i in np.unique(L[(d <= reach_mm) & (L > 0) & ~C]) if 50 <= sizes[i] < 5000 and dense[int(i)] <= 900]
        if not near:
            break
        C |= np.isin(L, near)
    comp[sl] = C
    idx = np.argwhere(comp); lo = np.maximum(idx.min(0) - margin, 0); hi = np.minimum(idx.max(0) + margin + 1, ct.shape)
    sl = tuple(slice(a, b) for a, b in zip(lo, hi))
    A = ct[sl].astype(np.float32); C = ndimage.binary_dilation(comp[sl], iterations=2)
    A = np.where(ndimage.binary_dilation(comp[sl], iterations=keep), A, np.minimum(A, 0))
    sm = ndimage.gaussian_filter(ndimage.zoom(A, UP, order=3), 0.6 * UP)
    C2 = ndimage.zoom(C.astype(np.uint8), UP, order=0) > 0
    bone = ndimage.binary_fill_holes((sm > 150) & C2)
    l2, _ = ndimage.label(bone, np.ones((3, 3, 3))); sz = np.bincount(l2.ravel()); sz[0] = 0
    bone = np.isin(l2, np.flatnonzero(sz > 30 * UP ** 3))
    return sm.astype(np.float32), bone, lo


def pieces(sm, bone, T=400, least=20):
    from skimage.segmentation import watershed
    mk, n = ndimage.label(bone & (sm > T), np.ones((3, 3, 3)))
    sz = np.bincount(mk.ravel()); sz[0] = 0
    keep = np.flatnonzero(sz >= least * UP ** 3); remap = np.zeros(n + 1, int); remap[keep] = np.arange(1, len(keep) + 1)
    ws = watershed(-sm, remap[mk], mask=bone).astype(np.int32)

    def elong(m):
        P = np.argwhere(m).astype(float); P -= P.mean(0); s = np.linalg.svd(P[::max(1, len(P) // 20000)], compute_uv=False)
        return s[0] / max(s[1], 1e-9)
    for _ in range(6):  # pieces too big and round to be one bone, split again at a higher threshold
        changed = False; nxt = ws.max() + 1
        for l in range(1, ws.max() + 1):
            m = ws == l
            if m.sum() / UP ** 3 < 1300 or elong(m) > 3.0:
                continue
            for t in range(500, 1300, 100):
                mk, n = ndimage.label(m & (sm > t), np.ones((3, 3, 3)))
                sz = np.bincount(mk.ravel()); sz[0] = 0
                seeds = np.flatnonzero(sz >= 12 * UP ** 3)
                if len(seeds) >= 2:
                    remap = np.zeros(n + 1, int); remap[seeds] = np.arange(1, len(seeds) + 1)
                    sub = watershed(-sm, remap[mk], mask=m)
                    for k in range(2, len(seeds) + 1):
                        ws[sub == k] = nxt; nxt += 1
                    changed = True
                    break
        if not changed:
            break
    return ws


def drop_foreign(sm, bone, ws, hu=1600, keep=()):
    """Pieces denser than bone (a clip on a fingertip, a lead's connector):
    taken out, with 2 mm around them. Bone here peaks near 1300 HU; keep
    names pieces known to be bone (a young tibia's cortex is denser)."""
    idx = np.arange(1, ws.max() + 1)
    bad = [b for b in idx[ndimage.maximum(sm, ws, idx) > hu] if int(b) not in keep]
    if len(bad):
        F = ndimage.binary_dilation(np.isin(ws, bad), iterations=3)
        bone &= ~F; ws[~bone] = 0
    return [int(b) for b in bad]


# MARK: 3. the rays

def _join(mask, most_mm=15.0):
    """Bridges joining a mask's pieces to the rest, nearest first: a
    straight line from each piece's nearest point to the nearest point of
    what it joins (the scan sets some fingers' bones apart at their joints).
    Pieces farther than most_mm stay apart."""
    lab, n = ndimage.label(mask, np.ones((3, 3, 3))); out = np.zeros_like(mask)
    if n < 2:
        return out
    idx = np.argwhere(mask); a = np.maximum(idx.min(0) - 2, 0); b = idx.max(0) + 3
    sl = tuple(slice(a[i], b[i]) for i in range(3)); lab = lab[sl]
    sz = np.bincount(lab.ravel()); sz[0] = 0; main = lab == sz.argmax(); rest = set(range(1, n + 1)) - {int(sz.argmax())}
    while rest:
        d, ind = ndimage.distance_transform_edt(~main, return_indices=True)
        near = {c: d[lab == c].min() for c in rest}; c = min(near, key=near.get)
        if near[c] * VX > most_mm:
            break
        m = lab == c; i = np.argwhere(m)[np.argmin(d[m])]; j = ind[:, i[0], i[1], i[2]]
        for t in np.linspace(0, 1, int(np.ceil(np.linalg.norm(j - i))) * 2 + 2):
            q = np.round(i + t * (j - i)).astype(int); out[sl][q[0] - 1:q[0] + 2, q[1] - 1:q[1] + 2, q[2] - 1:q[2] + 2] = True
        main |= m; rest.discard(c)
    return out


def rays(sm, bone, ws, forearm):
    """Five rays, tip first, each a path of fine-grid voxels."""
    from skimage.graph import MCP_Geometric
    F = np.isin(ws, forearm); Hd = bone & ~F
    lab, _ = ndimage.label(Hd, np.ones((3, 3, 3))); sz = np.bincount(lab.ravel()); sz[0] = 0
    Hd = np.isin(lab, np.flatnonzero(sz >= 30 * UP ** 3))     # the hand: its pieces, minus specks
    src = Hd & ndimage.binary_dilation(F, iterations=2)
    # joints of up to 4.5 mm bridged, and pieces further apart joined by a line; both dearer than bone
    B = ndimage.binary_dilation(Hd, iterations=6) | _join(Hd | F)
    D = ndimage.distance_transform_edt(Hd)
    cost = np.where(Hd, 1.0, np.where(B, 3.0, np.inf))
    dist, _ = MCP_Geometric(cost).find_costs([tuple(p) for p in np.argwhere(src)])
    dist[~B] = 0; dist[~np.isfinite(dist)] = 0
    tips = []; dd = np.where(Hd, dist, 0); R = 15 / VX
    while len(tips) < 5:   # the farthest points, none within 15 mm of a farther one
        t = np.unravel_index(np.argmax(dd), dd.shape)
        if dd[t] <= 0:
            break
        d2, _ = MCP_Geometric(cost).find_costs([t], max_cumulative_cost=R)
        ball = np.isfinite(d2) & (d2 < R) & Hd
        if dist[ball].max() <= dist[t] + 1e-6:
            tips.append(t); dd[ball] = 0
        else:
            dd[t] = 0; dd[ball & (dist < dist[t])] = 0
    assert len(tips) == 5, f"{len(tips)} fingertips found"
    mid = MCP_Geometric(np.where(Hd, 1.0 / np.maximum(D, 0.7) ** 2, np.where(B, 4.0, np.inf)))
    mid.find_costs([tuple(p) for p in np.argwhere(src)])
    return [np.array(mid.traceback(t))[::-1] for t in tips]


def arclength(P):
    return np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))] * VX


def name_rays(paths):
    """Which finger each ray is, read on the metacarpals, which lie side by
    side however the fingers bend: a point on each, 60 mm back from where
    the ray leaves the forearm. The thumb's is the one farthest from the
    others; the other four in order along the line through theirs, from the
    thumb's side. (Read at the fingers instead, a short little finger can
    look nearer the thumb than the ring finger.)"""
    def at(P, mm):
        s = arclength(P); return np.array([np.interp(mm, s, P[:, i]) for i in range(3)])
    pts = np.array([at(P, max(arclength(P)[-1] - 60.0, 40.0)) for P in paths])
    far = [np.mean([np.linalg.norm(pts[i] - pts[j]) for j in range(5) if j != i]) for i in range(5)]
    th = int(np.argmax(far))
    rest = [i for i in range(5) if i != th]; c = pts[rest].mean(0)
    ax = np.linalg.svd(pts[rest] - c)[2][0]
    if (pts[th] - c) @ ax > 0:
        ax = -ax
    rest.sort(key=lambda i: (pts[i] - c) @ ax)
    return dict(zip(FINGERS, [th] + rest))


# MARK: 4. bone by bone

def sheetness(sm, mask, sigma_mm=0.9):
    """Thin dark sheets between bright plates (joint lines): the largest
    Hessian eigenvalue where the other two are small."""
    sig = sigma_mm / VX; H = {}
    for i, j in [(0, 0), (1, 1), (2, 2), (0, 1), (0, 2), (1, 2)]:
        o = [0, 0, 0]; o[i] += 1; o[j] += 1
        H[i, j] = ndimage.gaussian_filter(sm, sig, order=o)[mask]
    M = np.stack([np.stack([H[0, 0], H[0, 1], H[0, 2]], -1), np.stack([H[0, 1], H[1, 1], H[1, 2]], -1),
                  np.stack([H[0, 2], H[1, 2], H[2, 2]], -1)], -2)
    ev = np.linalg.eigvalsh(M); l1 = ev[:, 2]; l2 = np.abs(ev[:, 1])
    out = np.zeros(mask.shape, np.float32)
    out[mask] = np.where(l1 > 0, l1 * np.exp(-(l2 / (l1 + 1e-6)) ** 2 / (2 * 0.5 ** 2)), 0) * sig ** 2
    return out


def _ball_mask(shape, pts, rad_mm):
    m = np.zeros(shape, bool); R = int(np.ceil(rad_mm / VX))
    for p in pts:
        c = np.round(p).astype(int); a = np.maximum(c - R, 0); b = np.minimum(c + R + 1, shape)
        if (b <= a).any():
            continue
        g = np.indices(b - a).reshape(3, -1).T + a
        m[a[0]:b[0], a[1]:b[1], a[2]:b[2]] |= (np.linalg.norm(g - p, axis=1) * VX <= rad_mm).reshape(b - a)
    return m


def split(sm, bone, ws, paths, which, table, tip_hu=120, tip_mm=22, gap_mm=4.0, seed_r=3.0, beta=2000, sheet=3.0):
    """Label each bone of the forearm and hand. Returns (labels, names)."""
    from skimage.segmentation import random_walker
    bone = bone.copy()
    sz = np.bincount(ws.ravel()); sz[0] = 0
    forearm = [int(i) for i in np.argsort(sz)[::-1][:2]]
    ends = [ws[tuple(P[-1])] for P in paths]
    carpus = int(np.bincount(ends).argmax())

    # the fingertips: what is above the tuft threshold beyond each tip, touching it or across a joint gap
    grown = np.zeros_like(bone); own = {}
    for f in FINGERS:
        P = paths[which[f]].astype(float); tip = P[0]; t = P[0] - P[min(16, len(P) - 1)]; t /= np.linalg.norm(t)
        R = int(tip_mm / VX) + 2; a = np.maximum(np.round(tip).astype(int) - R, 0); b = np.minimum(np.round(tip).astype(int) + R, bone.shape)
        sl = tuple(slice(a[i], b[i]) for i in range(3)); g = np.indices(b - a).reshape(3, -1).T + a
        along = ((g - tip) @ t * VX).reshape(b - a); dist = (np.linalg.norm(g - tip, axis=1) * VX).reshape(b - a)
        zone = (dist < tip_mm) & (along > -4)
        cable = ndimage.binary_dilation((sm[sl] > 1100) & ~bone[sl], iterations=4)   # ECG leads lie on the hands
        cand = (sm[sl] > table[f].get("tip_hu", tip_hu)) & zone & ~cable & ~bone[sl]
        lab, n = ndimage.label(cand)
        reach = ndimage.binary_dilation(bone[sl] & zone, iterations=int(round(gap_mm / VX)))
        touch = ndimage.binary_dilation(bone[sl] & zone)
        add = np.zeros_like(cand)
        for c in range(1, n + 1):
            m = lab == c
            if (m & touch).any() or ((m & reach).any() and m.sum() * VX ** 3 >= 40):
                add |= m
        grown[sl] |= add; own[f] = np.argwhere(add) + a
    tips = {f: paths[which[f]][0].astype(float) for f in FINGERS}
    tipp = {f: int(ws[tuple(paths[which[f]][0])]) for f in FINGERS}
    gl, _ = ndimage.label(grown | np.isin(ws, list(tipp.values())))
    owner = {}
    for f, p in tipp.items():
        for c in np.unique(gl[ws == p]):
            owner.setdefault(int(c), []).append(f)
    T = np.array([tips[f] for f in FINGERS])
    for f in FINGERS:   # a grown bit is its own finger's; where two fingers share one, the nearer tip's
        g = own[f]
        if not len(g):
            continue
        c = gl[tuple(g.T)]
        mine = np.array([f in owner.get(int(x), []) for x in c])
        multi = np.array([len(owner.get(int(x), [])) > 1 for x in c])
        near = np.argmin(np.linalg.norm(g[:, None, :] - T[None], axis=2), axis=1) == FINGERS.index(f)
        own[f] = g[mine & (~multi | near)]
    bone |= grown; bone = ndimage.binary_fill_holes(bone)

    # seeds
    markers = np.zeros(bone.shape, np.int32); names = []

    def put(name, m):
        if name not in names:
            names.append(name)
        lid = names.index(name) + 1; markers[m & bone & (markers == 0)] = lid
        return lid
    ext = {}
    for p in forearm:
        idx = np.argwhere(ws == p); ext[p] = idx
    put("radius", np.zeros_like(bone)); put("ulna", np.zeros_like(bone)); put("carpal bones", np.zeros_like(bone))
    # the radius is the long piece whose far end lies nearer the thumb's metacarpal
    thumb_mc = paths[which["thumb"]][len(paths[which["thumb"]]) * 2 // 3]
    end = {p: ext[p][np.argmin(((ext[p] - paths[which["middle"]][-1]) ** 2).sum(1))] for p in forearm}
    rad = min(forearm, key=lambda p: np.linalg.norm(end[p] - thumb_mc))
    for name, p in (("radius", rad), ("ulna", next(q for q in forearm if q != rad))):
        put(name, ndimage.binary_erosion(ws == p, iterations=2))
    put("carpal bones", ndimage.binary_erosion(ws == carpus, iterations=4))
    for f in FINGERS:
        P = paths[which[f]].astype(float); s = arclength(P); spec = table[f]
        J = [-30.0] + list(spec["joints"]) + [spec["base_end"]]; bn = bone_names(f)
        for i, nm in enumerate(bn):
            j0, j1 = J[i], J[i + 1]
            m_ = max(seed_r + 1.5, 0.2 * (j1 - max(j0, 0)))
            hi_m = 6.0 if i == len(bn) - 1 else m_
            lo_, hi_ = max(j0 + m_, 0), j1 - hi_m
            pts = P[(s >= lo_) & (s <= hi_)] if hi_ > lo_ else P[:0]
            if j0 < 0:   # the distal phalanx: its seed reaches into the tuft
                t = P[0] - P[min(16, len(P) - 1)]; t /= np.linalg.norm(t)
                g = own[f]; far = g[(g - P[0]) @ t * VX > max(2.0, -j1 + 2.0)] if len(g) else g
                pts = np.vstack([pts, far]) if len(far) else pts
            assert len(pts), f"no seed for the {nm}"
            put(nm, _ball_mask(bone.shape, pts, seed_r))
        for jd in spec.get("discs", []):
            Jm = spec["joints"][jd]
            for side, bi in ((-1.5, jd), (1.5, jd + 1)):
                i0 = int(np.argmin(np.abs(s - (Jm + side)))); p0 = P[i0]
                tv = P[min(i0 + 3, len(P) - 1)] - P[max(i0 - 3, 0)]; tv /= np.linalg.norm(tv)
                R = int(8 / VX); a = np.maximum(np.round(p0).astype(int) - R, 0); b = np.minimum(np.round(p0).astype(int) + R + 1, bone.shape)
                g = np.indices(b - a).reshape(3, -1).T + a; rel = g - p0
                disc = ((np.abs(rel @ tv) <= 0.6) & (np.linalg.norm(rel, axis=1) * VX <= 8)).reshape(b - a) & bone[a[0]:b[0], a[1]:b[1], a[2]:b[2]]
                cl, _ = ndimage.label(disc, np.ones((3, 3, 3))); c0 = cl[tuple(np.round(p0).astype(int) - a)]
                assert c0, f"the disc at {Jm + side} mm misses the {f} ray's bone"
                lid = names.index(bn[bi]) + 1; sub = markers[a[0]:b[0], a[1]:b[1], a[2]:b[2]]
                sub[(cl == c0) & ((sub == 0) | (sub == lid))] = lid
        cid = names.index("carpal bones") + 1
        for p in P[s >= spec["carpus_from"]]:
            c = np.round(p).astype(int); sl = tuple(slice(max(c[i] - 3, 0), c[i] + 4) for i in range(3))
            sub = markers[sl]; sub[(sub == 0) & bone[sl]] = cid

    # the random walk
    idx = np.argwhere(bone); a = np.maximum(idx.min(0) - 2, 0); b = idx.max(0) + 3
    sl = tuple(slice(a[i], b[i]) for i in range(3))
    data = np.clip((sm[sl] + 100) / 1500, 0, 1).astype(np.float64)
    if sheet:
        data -= sheet * sheetness(sm[sl], bone[sl]) / 1500
    mk = markers[sl].copy(); mk[~bone[sl]] = -1
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        res = random_walker(data, mk, beta=beta, mode="cg_mg", tol=1e-3)
    res[res < 0] = 0; lab = np.zeros(bone.shape, np.int32); lab[sl] = res

    # each bone's main piece kept, stray bits to the bone they touch most; then each closed
    for l in range(1, len(names) + 1):
        cc, n = ndimage.label(lab == l)
        if n > 1:
            size = ndimage.sum(np.ones_like(cc), cc, range(1, n + 1)); big = int(np.argmax(size)) + 1
            for j in range(1, n + 1):
                if j == big:
                    continue
                part = cc == j; nb = lab[ndimage.binary_dilation(part) & ~part]; nb = nb[(nb > 0) & (nb != l)]
                lab[part] = np.bincount(nb).argmax() if len(nb) else 0
    # a bone whose thin cortex fell under the threshold has a tunnel through
    # its wall: closed harder until it is one solid (Euler number 1); the
    # carpus is eight bones, its gaps real
    from skimage.measure import euler_number
    ball = ndimage.generate_binary_structure(3, 1); cube = np.ones((3, 3, 3), bool)
    for l in range(1, len(names) + 1):
        m = lab == l
        if not m.any():
            continue
        idx = np.argwhere(m); a = np.maximum(idx.min(0) - 6, 0); b = np.minimum(idx.max(0) + 7, lab.shape)
        sl = tuple(slice(a[i], b[i]) for i in range(3))
        c = ndimage.binary_fill_holes(ndimage.binary_closing(m[sl], ball, iterations=2))
        it = 0
        while names[l - 1] != "carpal bones" and euler_number(c, connectivity=3) != 1 and it < 4:
            it += 1; c = ndimage.binary_fill_holes(ndimage.binary_closing(m[sl], cube, iterations=it))
        sub = lab[sl]; sub[c & (sub == 0)] = l
    return lab, names


def bones_from_scan(sex, folder):
    """The labelled forearm and hand of one body's scan, on the fine grid:
    (labels, names, lo, affine, paths, which)."""
    import nibabel
    spec = LIMBS[sex]
    im = nibabel.load(f"{folder}/ct.nii.gz"); ct = np.asarray(im.dataobj, dtype=np.int16)
    known = np.zeros(ct.shape, bool)
    for k in KNOWN:
        known |= np.asarray(nibabel.load(f"{folder}/{k}.nii.gz").dataobj) > 0
    log(f"    {spec['subject']}: bone by density")
    lab = components(ct, known); del known
    sm, bone, lo = work_volume(ct, lab, spec["point"]); del lab, ct
    ws = pieces(sm, bone)
    bad = drop_foreign(sm, bone, ws)
    if bad:
        log(f"    {spec['subject']}: {len(bad)} pieces denser than bone left out")
    sz = np.bincount(ws.ravel()); sz[0] = 0
    log(f"    {spec['subject']}: {ws.max()} pieces; tracing the rays")
    paths = rays(sm, bone, ws, [int(i) for i in np.argsort(sz)[::-1][:2]])
    which = name_rays(paths)
    log(f"    rays: " + ", ".join(f"{f} {arclength(paths[which[f]])[-1]:.0f} mm" for f in FINGERS))
    labels, names = split(sm, bone, ws, paths, which, spec["fingers"])
    return labels, names, lo, im.affine, paths, which


# MARK: 5. posed into the body

def _rot(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b); v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def _turn(k, t):
    k = k / np.linalg.norm(k); K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K


def _angle_about(a, b, k):
    """The turn about k taking a's part across k to b's."""
    k = k / np.linalg.norm(k); a = a - (a @ k) * k; b = b - (b @ k) * k
    return np.arctan2(np.cross(a, b) @ k, a @ b)


class Pose:
    """Each bone's points as the steps move them: x -> c2 + s R (x - c)."""
    def __init__(self, pts):
        self.p = {n: p.copy() for n, p in pts.items()}
        self.A = {n: np.eye(3) for n in pts}; self.t = {n: np.zeros(3) for n in pts}

    def move(self, names, R, c, s=1.0, c2=None):
        c2 = c if c2 is None else c2
        for n in names:
            self.p[n] = c2 + s * (self.p[n] - c) @ R.T
            self.A[n] = s * R @ self.A[n]; self.t[n] = c2 + s * R @ (self.t[n] - c)


def _end(p, axis, top, share=4):
    t = p @ axis
    return p[t >= np.percentile(t, 100 - share)].mean(0) if top else p[t <= np.percentile(t, share)].mean(0)


def _axis(p):
    c = p.mean(0); _, _, vt = np.linalg.svd(p - c, full_matrices=False)
    return c, vt[0]


def _joint(a, b, mm=2.0):
    """The middle of a joint: the points of each bone within `mm` of the
    nearest approach of the other, averaged."""
    from scipy.spatial import cKDTree
    da, _ = cKDTree(b).query(a); db, _ = cKDTree(a).query(b)
    return np.vstack([a[da <= da.min() + mm / 1000], b[db <= db.min() + mm / 1000]]).mean(0)


def fit_humerus(h, H, medial_h, medial_H):
    """The similarity taking the scan's humerus h onto the body's H: their
    long axes and elbows lined up, the epicondyles across, then refined by
    nearest points with the elbow's half counted four times."""
    from scipy.spatial import cKDTree
    def frame(p, medial):
        c, ax = _axis(p)
        if ax[1] < 0:
            ax = -ax           # both humeri hang head up in the atlas frame (checked below)
        t = (p - c) @ ax; low = p[t < np.percentile(t, 8)].mean(0); head = p[t > np.percentile(t, 92)].mean(0)
        q = p[t < np.percentile(t, 8)] - low; q -= np.outer(q @ ax, ax); _, _, vt = np.linalg.svd(q, full_matrices=False)
        e = vt[0] if vt[0] @ medial > 0 else -vt[0]
        return ax, e, low, np.linalg.norm(head - low)
    ax1, e1, low1, l1 = frame(h, medial_h); ax2, e2, low2, l2 = frame(H, medial_H)
    R = _rot(ax1, ax2); R = _turn(ax2, _angle_about(R @ e1, e2, ax2)) @ R
    s = l2 / l1; t = low2 - s * R @ low1
    tree = cKDTree(H); rng = np.random.default_rng(0)
    src = h[rng.choice(len(h), min(len(h), 4000), replace=False)]
    w = np.where(((src - h.mean(0)) @ (ax1)) < 0, 4.0, 1.0)
    for _ in range(30):
        cur = src @ (s * R).T + t; d, i = tree.query(cur)
        keep = d < np.percentile(d, 90)
        s, R, t = _umeyama(src[keep], H[i[keep]], w[keep])
    return s, R, t


def _umeyama(src, dst, w):
    w = w / w.sum(); ms, md = w @ src, w @ dst; a, b = src - ms, dst - md
    U, S, Vt = np.linalg.svd((b * w[:, None]).T @ a); D = np.eye(3)
    if np.linalg.det(U @ Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt; s = (S * np.diag(D)).sum() / (w * (a ** 2).sum(1)).sum()
    return s, R, md - s * R @ ms


def skin_hand(v, f, side, x0, h=0.0015):
    """The skin's forearm and hand beyond |x| = x0 as a solid, and its five
    finger lines (cut to tip, through the middle of the soft tissue) by
    finger: the thumb's tip is the farthest from the others; the rest in
    order away from it across the hand. Also the wrist: the narrowest cross-section before the thumb
    leaves."""
    import anatomy_gaps as g
    from skimage.graph import MCP_Geometric
    keepf = (side * v[f][:, :, 0] > x0 - 0.01).any(1); f2 = f[keepf]
    used = np.unique(f2); remap = -np.ones(len(v), int); remap[used] = np.arange(len(used)); v2 = v[used]; f2 = remap[f2]
    loops = g._loops(v2, f2, np.array([side * (x0 - 0.004), 0, 0]), np.array([1.0, 0, 0]))
    L = max(loops, key=len); c = L.mean(0); L = L[np.argsort(np.arctan2(L[:, 2] - c[2], L[:, 1] - c[1]))]
    rings = [c + (L - c) * r for r in (1.0, 0.8, 0.6, 0.4, 0.2)]      # the cut capped in rings
    k = len(L); n0 = len(v2); cf = []
    for r in range(len(rings) - 1):
        for i in range(k):
            a0, a1 = n0 + r * k + i, n0 + r * k + (i + 1) % k
            cf += [[a0, a1, a1 + k], [a0, a1 + k, a0 + k]]
    last = n0 + (len(rings) - 1) * k
    cf += [[last + i, last + (i + 1) % k, n0 + len(rings) * k] for i in range(k)]
    S = g.Solid([(np.vstack([v2] + rings + [c[None]]), np.vstack([f2, np.array(cf)]))], h=h, close=1)
    G = S.g.copy(); lo = S.lo
    xs = lo[0] + (np.arange(G.shape[0]) + 0.5) * h
    G[~(side * xs > x0 + 0.002)] = False
    G = ndimage.gaussian_filter(G.astype(np.float32), 1.0) > 0.5
    lab, _ = ndimage.label(G); sz = np.bincount(lab.ravel()); sz[0] = 0; G = lab == sz.argmax()
    D = ndimage.distance_transform_edt(G)
    ii = np.argwhere(G); cut = ii[side * (lo[0] + (ii[:, 0] + .5) * h) < x0 + 0.004]
    dist, _ = MCP_Geometric(np.where(G, 1.0, np.inf)).find_costs([tuple(q) for q in cut]); dist[~G] = 0
    tips = []; dd = dist.copy(); R = 0.04 / h
    while len(tips) < 5:   # the farthest points from the cut, none within 40 mm of a farther one
        t = np.unravel_index(np.argmax(dd), dd.shape)
        assert dd[t] > 0, f"the skin's hand shows {len(tips)} fingertips"
        d2, _ = MCP_Geometric(np.where(G, 1.0, np.inf)).find_costs([t], max_cumulative_cost=R)
        ball = np.isfinite(d2) & (d2 < R) & G
        if dist[ball].max() <= dist[t] + 1e-6:
            tips.append(t); dd[ball] = 0
        else:
            dd[t] = 0; dd[ball & (dist < dist[t])] = 0
    mid = MCP_Geometric(np.where(G, 1.0 / np.maximum(D, 0.5) ** 2, np.inf)); mid.find_costs([tuple(q) for q in cut])
    lines = [lo + (np.array(mid.traceback(t)) + 0.5) * h for t in tips]     # cut to tip
    from scipy.spatial import cKDTree
    T = np.array([l[-1] for l in lines])
    th = int(np.argmax([np.mean([np.linalg.norm(T[i] - T[j]) for j in range(5) if j != i]) for i in range(5)]))
    rest = [i for i in range(5) if i != th]
    c, ax = _axis(T[rest])
    if (T[th] - c) @ ax < 0:
        ax = -ax
    rest.sort(key=lambda i: -(T[i] @ ax))         # index nearest the thumb, little farthest
    by = dict(zip(FINGERS, [lines[i] for i in [th] + rest]))
    # the wrist: where the forearm's narrowest stretch ends and the hand begins to widen, along the middle
    # finger's line, before the palm's widest section (the radiocarpal joint lies under it)
    M = by["middle"]; sm_ = np.r_[0, np.cumsum(np.linalg.norm(np.diff(M, axis=0), axis=1))]
    rows = []
    for q in np.arange(0.01, sm_[-1] * 0.75, 0.002):
        i = np.searchsorted(sm_, q); p0 = M[i]; d = M[min(i + 8, len(M) - 1)] - M[max(i - 8, 0)]; d /= np.linalg.norm(d)
        u = np.cross(d, [0, 0, 1.0]); u /= np.linalg.norm(u); w = np.cross(d, u)
        gr = np.arange(-0.06, 0.0605, 0.001); U, W = np.meshgrid(gr, gr, indexing="ij")
        pts = p0 + U[..., None] * u + W[..., None] * w
        idx = np.floor((pts - lo) / h).astype(int); ok = ((idx >= 0) & (idx < G.shape)).all(-1)
        ins = np.zeros(U.shape, bool); ins[ok] = G[tuple(idx[ok].T)]
        cl, _ = ndimage.label(ins); c0 = cl[60, 60]
        rows.append(((cl == c0).sum() if c0 else 10 ** 9, p0))
    area = np.array([r[0] for r in rows]); qs = np.arange(0.01, sm_[-1] * 0.75, 0.002)[:len(rows)]
    from_ = int(np.searchsorted(qs, 0.3 * sm_[-1])); palm = from_ + int(np.argmax(area[from_:]))
    lowest = int(np.argmin(area[:palm]))
    end = lowest + int(np.flatnonzero(np.r_[area[lowest:] > 1.04 * area[lowest], True])[0]) - 1
    wrist = rows[end][1]
    return {"lines": by, "wrist": wrist, "solid": (G, lo, h), "x0": x0}


def _on_line(L, origin, r):
    """The first point of line L, past its nearest to origin, at least r from
    it; if the line ends nearer, on straight past its end (never back
    toward the origin, which would fold a finger over itself)."""
    i0 = int(np.argmin(np.linalg.norm(L - origin, axis=1))); d = np.linalg.norm(L[i0:] - origin, axis=1)
    j = np.flatnonzero(d >= r)
    if len(j):
        return L[i0 + j[0]]
    t = L[-1] - L[max(len(L) - 6, 0)]; t /= max(np.linalg.norm(t), 1e-9); e = L[-1] - origin
    b = e @ t; s = -b + np.sqrt(max(b * b - (e @ e - r * r), 0.0))
    return L[-1] + max(s, 0.0) * t


def _arc_to_tip(L, origin):
    """The length of line L from its point nearest origin to its end, the
    line smoothed first (a path on the voxel grid zigzags: about 10% long)."""
    L = ndimage.gaussian_filter1d(L, 4, axis=0, mode="nearest")
    i0 = int(np.argmin(np.linalg.norm(L - origin, axis=1)))
    return float(np.linalg.norm(L[i0] - origin) + np.sum(np.linalg.norm(np.diff(L[i0:], axis=0), axis=1)))


def chain(finger):
    if finger == "thumb":
        return ["first metacarpal", "proximal phalanx of thumb", "distal phalanx of thumb"]
    return [f"{k} phalanx of {finger} finger" for k in ("proximal", "middle", "distal")]


def fit_elbow(H, hum, pts, wrist, lo=0.9, hi=1.2):
    """The body's humerus H stretched along its length, about its head, so
    its elbow splits the arm from the shoulder to the skin's wrist as the
    scan's humerus (hum) and forearm (pts) split theirs. (A humerus scaled
    with the shoulders can come out as short as the forearm.) Returns the
    new points and the stretch."""
    import anatomy_gaps as g
    def ends(p):
        _, a = _axis(p); a = a if a[1] > 0 else -a
        return _end(p, a, True, 6), _end(p, a, False, 6), a
    Tc, Ec, _ = ends(hum)
    f2 = np.vstack([pts["radius"], pts["ulna"]]); _, a = _axis(f2)
    a = a if (pts["carpal bones"].mean(0) - f2.mean(0)) @ a > 0 else -a
    Wc = (_end(pts["radius"], a, True) + _end(pts["ulna"], a, True)) / 2
    rho = np.linalg.norm(Ec - Tc) / (np.linalg.norm(Ec - Tc) + np.linalg.norm(Wc - Ec))
    T, E, ax = ends(H)
    c = g._sphere(H[(H - H.mean(0)) @ ax > np.percentile((H - H.mean(0)) @ ax, 88)])[0]
    def at(k):
        E2 = E + (k - 1) * ((E - c) @ ax) * ax
        return np.linalg.norm(E2 - T) / (np.linalg.norm(E2 - T) + np.linalg.norm(wrist - E2))
    a_, b_ = lo, hi
    for _ in range(40):
        m = (a_ + b_) / 2; a_, b_ = (m, b_) if at(m) < rho else (a_, m)
    k = (a_ + b_) / 2
    return H + (k - 1) * ((H - c) @ ax)[:, None] * ax, float(k)


def pose(pts, hum, H, side, hand, pulp=0.004, stages=None):
    """Pose one forearm and hand: pts, name -> the scan's points of each bone
    (atlas frame, on this side already); hum, the scan's humerus; H, the
    body's; hand, skin_hand()'s. Returns the Pose and what it found."""
    lines, Wsk, (G, glo, gh) = hand["lines"], hand["wrist"], hand["solid"]
    P = Pose(pts); every = list(pts); facts = {}
    hand_bones = [n for n in every if n not in ("radius", "ulna")]
    fore = np.vstack([pts["radius"], pts["ulna"]]); _, ax = _axis(fore)
    if (pts["carpal bones"].mean(0) - fore.mean(0)) @ ax < 0:
        ax = -ax                                                             # elbow to wrist
    medial = _end(pts["ulna"], ax, False) - _end(pts["radius"], ax, False)   # the ulna is medial at the elbow
    s, R, t = fit_humerus(hum, H, medial, np.array([-side, 0.0, 0.0]))
    P.move(every, R, np.zeros(3), s, t); hum2 = hum @ (s * R).T + t
    snap = (lambda: stages.append({n: (P.A[n].copy(), P.t[n].copy()) for n in P.p})) if stages is not None else (lambda: None)
    snap()
    from scipy.spatial import cKDTree
    facts["humerus fit mm"] = float(np.mean(cKDTree(H).query(hum2)[0]) * 1000); facts["scale"] = float(s)

    # the elbow straightened toward the skin's wrist, the forearm sized to it
    _, hax = _axis(H); hax = hax if hax[1] > 0 else -hax
    E = _end(H, hax, False, 6)
    def wrist():
        f2 = np.vstack([P.p["radius"], P.p["ulna"]]); _, a = _axis(f2)
        a = a if (P.p["carpal bones"].mean(0) - f2.mean(0)) @ a > 0 else -a
        return (_end(P.p["radius"], a, True) + _end(P.p["ulna"], a, True)) / 2, a
    W, _ = wrist()
    want = float(np.linalg.norm(Wsk - E) / np.linalg.norm(W - E)); k = float(np.clip(want, 0.85, 1.15))
    P.move(every, _rot(W - E, Wsk - E), E, k); facts["forearm scale"] = k; facts["forearm scale wanted"] = want; snap()

    def align_hand():
        for _ in range(2):
            # the forearm aimed at the skin's wrist again (each turn below swings the radius round the ulna)
            W, _ = wrist(); P.move(every, _rot(W - E, Wsk - E), E)
            # the forearm turned (pronation) so the knuckles lie across as the skin's do
            W, a = wrist()
            axis = _end(P.p["ulna"], a, True) - _end(P.p["radius"], a, False); piv = _end(P.p["radius"], a, False)
            mcp = {f: _joint(P.p[METACARPAL[f] + " metacarpal"], P.p[chain(f)[0]]) for f in ("index", "middle", "little")}
            Cw = _joint(P.p["radius"], P.p["carpal bones"])
            q = {f: _on_line(lines[f], Cw, np.linalg.norm(mcp[f] - Cw)) for f in mcp}
            th = _angle_about(mcp["little"] - mcp["index"], q["little"] - q["index"], axis)
            P.move(["radius"] + hand_bones, _turn(axis, th), piv)
            facts["pronation turn deg"] = facts.get("pronation turn deg", 0) + float(np.degrees(th))
            # the hand turned at the wrist so its middle metacarpal points along the skin's
            Cw = _joint(P.p["radius"], P.p["carpal bones"])
            m3 = _joint(P.p["third metacarpal"], P.p[chain("middle")[0]])
            q3 = _on_line(lines["middle"], Cw, np.linalg.norm(m3 - Cw))
            P.move(hand_bones, _rot(m3 - Cw, q3 - Cw), Cw)
        for f in FINGERS:   # each finger laid along its line, joint by joint
            lay(f)

    def lay(f):
        for i in range(3):
            J = joints(f); q = _on_line(lines[f], J[i], np.linalg.norm(J[i + 1] - J[i]))
            P.move(chain(f)[i:], _rot(J[i + 1] - J[i], q - J[i]), J[i])

    def outside(n):   # the share of a bone the skin does not hold (beyond the cut, where the skin's solid is)
        p = P.p[n]; idx = np.floor((p - glo) / gh).astype(int); ok = ((idx >= 0) & (idx < G.shape)).all(1)
        ok &= side * p[:, 0] > hand["x0"] + 0.004
        ins = np.zeros(len(p), bool); ins[ok] = G[tuple(idx[ok].T)]
        return round(float(1 - ins[ok].mean()), 3) if ok.sum() > 20 else None

    def joints(f):
        ch = chain(f)
        J = [_joint(P.p["carpal bones"] if f == "thumb" else P.p[METACARPAL[f] + " metacarpal"], P.p[ch[0]])]
        J += [_joint(P.p[ch[i]], P.p[ch[i + 1]]) for i in range(len(ch) - 1)]
        d = P.p[ch[-1]]; return J + [d[np.argmax(np.linalg.norm(d - J[-1], axis=1))]]

    # the hand sized so its middle fingertip lies the pulp's depth inside the skin's, then each finger so
    kh = 1.0
    for _ in range(3):
        align_hand()
        Cw = _joint(P.p["radius"], P.p["carpal bones"]); tip = joints("middle")[-1]
        r = (np.linalg.norm(lines["middle"][-1] - Cw) - pulp) / np.linalg.norm(tip - Cw)
        r = float(np.clip(kh * r, 0.85, 1.15) / kh); P.move(hand_bones, np.eye(3), Cw, r); kh *= r
    facts["hand scale"] = kh; snap()
    for f in FINGERS:   # by the bones' lengths joint to joint against the line's to its tip (a bent chain measures short straight)
        J = joints(f); kf = (_arc_to_tip(lines[f], J[0]) - pulp) / sum(np.linalg.norm(J[i + 1] - J[i]) for i in range(len(J) - 1))
        kf = float(np.clip(kf, 0.9, 1.1)); P.move(chain(f), np.eye(3), J[0], kf); facts[f"{f} scale"] = kf
    align_hand()
    for f in FINGERS:   # a fingertip the skin cannot hold (the scan's finger thicker than the skin's), the finger shortened
        n_ = 0
        while (outside(chain(f)[-1]) or 0) > 0.05 and facts[f"{f} scale"] > 0.85 and n_ < 8:
            P.move(chain(f), np.eye(3), joints(f)[0], 0.97); facts[f"{f} scale"] *= 0.97; n_ += 1; lay(f)
    W, a = wrist()
    twist = _angle_about(_end(P.p["radius"], a, False) - _end(P.p["ulna"], a, False),
                         _end(P.p["radius"], a, True) - _end(P.p["ulna"], a, True), a)
    facts["radius across the ulna deg"] = float(np.degrees(twist)); facts["wrist gap mm"] = float(np.linalg.norm(W - Wsk) * 1000); snap()

    facts["outside the skin"] = {n: outside(n) for n in every}
    return P, facts


# MARK: 6. both sides, as meshes

TO_ATLAS = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float) / 1000   # NIfTI RAS mm to the atlas frame
BUDGET = {"radius": 1200, "ulna": 1200, "carpal bones": 1500}             # triangles; metacarpals 400, phalanges 250


def files_used(sex):
    return ["ct.nii.gz"] + [k + ".nii.gz" for k in KNOWN]


def bone_meshes(labels, names, lo, affine, sigma=1.0):
    """Each labelled bone's surface in the atlas frame (as scanned),
    counter-clockwise seen from outside."""
    from skimage.measure import marching_cubes
    n = np.array(labels.shape) // UP; out = {}
    for i, nm in enumerate(names, 1):
        m = labels == i
        assert m.any(), f"no {nm}"
        idx = np.argwhere(m); a = np.maximum(idx.min(0) - 3, 0); b = idx.max(0) + 4
        sub = np.pad(m[a[0]:b[0], a[1]:b[1], a[2]:b[2]].astype(np.float32), 2)
        v, f, _, _ = marching_cubes(ndimage.gaussian_filter(sub, sigma), 0.5)
        sc = lo + (v - 2 + a) * (n - 1) / (UP * n - 1)          # the fine grid is ndimage.zoom's: corners kept
        p = (sc @ affine[:3, :3].T + affine[:3, 3]) @ TO_ATLAS.T; f = f.astype(np.int64)
        a_, b_, c_ = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
        if np.einsum("ij,ij->i", a_, np.cross(b_, c_)).sum() < 0:
            f = f[:, [0, 2, 1]]
        out[nm] = (p, f)
    return out


def limbs(sex, ct_dir, humeri, skin):
    """The forearm and hand bones of one body, both sides, posed into its
    skin. humeri: {"left": points, "right": points}, the body's humeri as
    placed; skin: (positions, triangles). Returns (structures, [(positions,
    triangles, budget)], facts by side, the humeri's points with each
    elbow fitted)."""
    import nibabel
    spec = LIMBS[sex]; folder = os.path.join(ct_dir, spec["subject"])
    labels, names, lo, affine, _, _ = bones_from_scan(sex, folder)
    meshes = bone_meshes(labels, names, lo, affine); del labels
    im = nibabel.load(f"{folder}/humerus_{spec['side']}.nii.gz"); j = np.argwhere(np.asarray(im.dataobj) > 0).astype(float)
    rng = np.random.default_rng(0)
    hum = (j[rng.choice(len(j), min(len(j), 20000), replace=False)] @ im.affine[:3, :3].T + im.affine[:3, 3]) @ TO_ATLAS.T
    pts = {n: p[rng.choice(len(p), min(len(p), 20000), replace=False)] for n, (p, f) in meshes.items()}
    taken = 1 if spec["side"] == "left" else -1
    structures, out, facts, fitted = [], [], {}, {}
    for side, s in (("left", "L"), ("right", "R")):
        sign = 1 if side == "left" else -1
        M = np.diag([-1.0, 1, 1]) if sign != taken else np.eye(3)   # the other side: the mirror image
        mine = {n: q @ M.T for n, q in pts.items()}
        H = humeri[side]; _, hax = _axis(H); hax = hax if hax[1] > 0 else -hax
        hand = skin_hand(skin[0], skin[1], sign, abs(_end(H, hax, False, 6)[0]) + 0.03)
        H, kel = fit_elbow(H, hum @ M.T, mine, hand["wrist"]); fitted[side] = H
        hand = skin_hand(skin[0], skin[1], sign, abs(_end(H, hax, False, 6)[0]) + 0.03)
        P, f_ = pose(mine, hum @ M.T, H, sign, hand); f_["humerus stretched"] = kel; facts[side] = f_
        log(f"    {side} forearm and hand: humerus stretched x{kel:.3f}, fit {f_['humerus fit mm']:.1f} mm, forearm x{f_['forearm scale']:.2f}, "
            f"hand x{f_['hand scale']:.2f}, fingers x" + "/".join(f"{f_[f + ' scale']:.2f}" for f in FINGERS)
            + "; outside the skin: " + (", ".join(f"{k} {v:.0%}" for k, v in f_["outside the skin"].items() if v and v > 0.02) or "none"))
        for n in names:
            p, f = meshes[n]; p = (p @ M.T) @ P.A[n].T + P.t[n]
            if sign != taken:
                f = f[:, [0, 2, 1]]
            structures.append({"node": f"TS_{n.replace(' ', '_')}_{s}", "label": f"{side} {n}", "uberon": uberon_of(n),
                               "tissue": "bone", "group": "Forearm bones" if n in ("radius", "ulna") else "Hand bones",
                               "inner": False})
            out.append((p, f, BUDGET.get(n, 400 if n.endswith("metacarpal") else 250)))
    return structures, out, facts, fitted
