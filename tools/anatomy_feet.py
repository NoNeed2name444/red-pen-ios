"""The foot bones of both atlas bodies, found in CT scans and posed into
each body's skin. Called by tools/anatomy_gaps.py; not run on its own.

As with the forearm and hand (tools/anatomy_limbs.py, whose first steps
this shares), the TotalSegmentator dataset (CC BY 4.0) segments no bone
below the femur, so the foot is found in the scans' CT itself:

1. The lowest 250 mm of the scan, on the foot's side: bone by density
   (anatomy_limbs step 1), the piece that holds the most bone in the
   lowest 120 mm with the small pieces near it, on a grid twice as fine,
   cut into pieces where it narrows (step 2). The leg's bones are the
   pieces that reach the top.
2. The five rays: the toes' tips as the bone's farthest points from the
   leg, each traced back along the middle of the bone (step 3). The great
   toe's ray is the most medial, the others follow it in order.
3. The joints, read by eye from the CT straightened along each toe's ray,
   and along the straight line of each metatarsal (fitted on its shaft
   just behind its head, and continued into the tarsus): the base of each
   metatarsal; on the first three lines the medial, intermediate and
   lateral cuneiforms, then the navicular; on the last two the cuboid,
   then the calcaneus. Along the tibia's axis (the widest of the leg's
   bones), the ankle joint and the joint under the talus; the talus is
   seeded between them and along the great toe's ray through its head and
   neck, the calcaneus under it and at the heel (the bone farthest from
   the toes), the leg above the ankle (FEET below). A random walk from the
   seeds over the bone, on the CT with its joint lines darkened (as for
   the hand), gives each bone.
4. Posed into the body: see pose_foot.

One foot per body is taken from a scan; the other side is its mirror
image (noted in SOURCES.md). The scans:

- the man's: s1767 (a man of 56), his left foot; the male body's own scan
  (s1803) and the man's hand scan (s1880) end above the toes;
- the woman's: s1764 (a woman of 32, the female body's scan), her right.
"""
import os

import numpy as np
from scipy import ndimage

import anatomy_limbs as L

TOES = ("great", "second", "third", "fourth", "little")
METATARSAL = {"great": "first", "second": "second", "third": "third", "fourth": "fourth", "little": "fifth"}
_DIGIT = {"great": 1, "second": 2, "third": 3, "fourth": 4, "little": 5}
# the bones each metatarsal's line runs into, behind its base; the last
# is seeded only just past the joint before it (the line soon leaves it)
LINE_BONES = {
    "great": ["medial cuneiform", "navicular"],
    "second": ["intermediate cuneiform", "navicular"],
    "third": ["lateral cuneiform"],
    "fourth": ["cuboid", "calcaneus"],
    "little": ["cuboid", "calcaneus"],
}
TARSALS = ("talus", "calcaneus", "navicular", "cuboid", "medial cuneiform", "intermediate cuneiform", "lateral cuneiform")
UBERON = {"talus": "0002395", "calcaneus": "0001450", "navicular": "0001451", "cuboid": "0001455",
          "medial cuneiform": "0001452", "intermediate cuneiform": "0001453", "lateral cuneiform": "0001454",
          "first metatarsal": "0003650", "second metatarsal": "0003651", "third metatarsal": "0003652",
          "fourth metatarsal": "0003653", "fifth metatarsal": "0003654",
          "sesamoid bones of the great toe": "0008000"}
SESAMOIDS = "sesamoid bones of the great toe"
for _t, _d in _DIGIT.items():
    UBERON[f"distal phalanx of {_t} toe"] = f"000{4314 + _d}"
    UBERON[f"proximal phalanx of {_t} toe"] = f"000{4331 + _d}"
    if _d > 1:
        UBERON[f"middle phalanx of {_t} toe"] = f"000{4322 + _d}"

# Per body: the scan, the foot, and the joints read from it. "toes": along
# each toe's ray, mm from its tip: the distal joint(s), then the
# metatarsophalangeal joint. "lines": along the metatarsal's line, mm from
# its head (level with that joint): the joint at its base, then the joints
# between the bones of LINE_BONES (fewer where the line leaves the bone:
# the man's fifth runs past the cuboid). "fit": where a metatarsal's line
# is fitted instead of 8-28 mm behind the joint (the man's great toe's ray
# runs through a sesamoid there). "talus": mm along the great toe's ray
# where it crosses into the talus head, and where it leaves its neck (past
# that it dips through the joint below it). "ankle": mm along the tibia's
# axis below the lowest point of its pieces near the axis, the ankle joint
# and the joint under the talus. "sesamoids": the two sesamoids under the
# first metatarsal's head (the medial first), each its densest point: mm
# behind the joint along the metatarsal's line, toward the sole (against
# the tibia's axis), toward the medial side. Where the CT does not show a
# small toe's end joint (at 1.5 mm it blurs), it is set by the toe's usual
# proportions and the walk finds the gap near it.
FEET = {
    "female": {
        "subject": "s1764", "side": "right",
        "toes": {
            "great": [31, 63.5],
            "second": [13, 27, 60],
            "third": [17.5, 27, 52],
            "fourth": [10, 20, 41.8],
            "little": [9, 18.5, 39.3],
        },
        "lines": {
            "great": [62, 86.5],
            "second": [74, 93],
            "third": [70.5, 90.5],
            "fourth": [71, 100],
            "little": [63, 87],
        },
        "talus": [177.5, 198],
        "ankle": [4.5, 35.25],
        "sesamoids": [[2.5, 10.5, 5.5], [7.0, 13.0, -10.0]],
    },
    "male": {
        "subject": "s1767", "side": "left",
        "toes": {
            "great": [30.5, 66],
            "second": [12.5, 30.2, 67],
            "third": [12.5, 30, 63],
            "fourth": [11, 21.8, 53],
            "little": [12, 24, 47],
        },
        "lines": {
            "great": [67.5, 94.4],
            "second": [80.1, 100.8],
            "third": [77.7, 99.7],
            "fourth": [75, 111.25],
            "little": [75.9],
        },
        "fit": {"great": [32, 66]},
        "talus": [194, 212],
        "ankle": [10.5, 35.25],
        "sesamoids": [[0.5, 4.5, 9.0], [5.5, 14.0, -2.0]],
    },
}
UP, VX = L.UP, L.VX
TOP_MM = 250      # the scan's lowest this many mm hold the foot and the lower leg


def log(*a):
    print(*a, flush=True)


def bone_names(toe):
    m = METATARSAL[toe] + " metatarsal"
    if toe == "great":
        return ["distal phalanx of great toe", "proximal phalanx of great toe", m]
    return [f"{k} phalanx of {toe} toe" for k in ("distal", "middle", "proximal")] + [m]


def uberon_of(name):
    return "UBERON:" + UBERON[name]


# MARK: 1-2. the foot's bone, its pieces, its rays

def foot_volume(ct, affine, side):
    """The foot's side of the scan's lowest TOP_MM: (ct, voxel offset)."""
    nz = int(TOP_MM / 1.5)
    mid = int(round(np.linalg.solve(affine[:3, :3], -affine[:3, 3])[0]))   # the voxel column at x = 0
    half = slice(mid, ct.shape[0]) if side == "right" else slice(0, mid)   # RAS: +x is the body's right
    return ct[half, :, :nz], np.array([half.start, 0, 0])


def name_toes(paths, medial):
    """Which toe each ray is: on a line across the metatarsals (60 mm back
    from each tip), the great toe's is the most medial, then the others."""
    def at(P, mm):
        s = L.arclength(P); return np.array([np.interp(mm, s, P[:, i]) for i in range(3)])
    pts = np.array([at(P, min(60.0, L.arclength(P)[-1] - 20)) for P in paths])
    c = pts.mean(0); ax = np.linalg.svd(pts - c)[2][0]
    if ax @ medial < 0:
        ax = -ax
    order = sorted(range(5), key=lambda i: -(pts[i] - c) @ ax)
    return dict(zip(TOES, order))


def mt_line(P, mtp, fit=(8, 28)):
    """A metatarsal's straight line: its head (level with the joint at mtp
    mm along the ray P, tip first) and its direction toward the base,
    fitted on the ray fit mm behind the joint (fine-grid voxels)."""
    s = L.arclength(P); seg = P[(s >= mtp + fit[0]) & (s <= mtp + fit[1])].astype(float)
    c = seg.mean(0); t = np.linalg.svd(seg - c)[2][0]
    head = np.array([np.interp(mtp, s, P[:, i]) for i in range(3)])
    if (c - head) @ t < 0:
        t = -t
    return c - ((c - head) @ t) * t, t


def leg_axis(ws, leg):
    """The tibia's axis (fine-grid voxels): its centre, the direction toward
    the foot, and its lowest point within 12 mm of the axis. The tibia is
    the widest of the leg's bones where the volume ends above (the fibula's
    pieces are left out: the axis runs down the middle of the ankle joint)."""
    top = ndimage.binary_fill_holes(ndimage.binary_closing(np.isin(ws[:, :, -1], leg), iterations=2))
    blobs, n = ndimage.label(top)
    widest = int(np.argmax(np.bincount(blobs.ravel())[1:])) + 1
    tibia = [t for t in leg if (ws[:, :, -1][blobs == widest] == t).any()]
    idx = np.argwhere(np.isin(ws, tibia)).astype(float); c = idx.mean(0); ax = np.linalg.svd(idx[::7] - c, full_matrices=False)[2][0]
    if ax[2] > 0:
        ax = -ax                       # the scan's z runs up the body: toward the foot is down
    t = (idx - c) @ ax; rad = np.linalg.norm((idx - c) - np.outer(t, ax), axis=1) * VX
    return c, ax, c + t[rad < 12].max() * ax


def foot_pieces(ct):
    """Step 1 on the foot's side of the scan: (sm, bone, lo, ws, leg, foreign).
    The leg's bones are added to the foot's piece first (at 1.5 mm the ankle
    joint can part the tibia from the talus) and are never taken for metal
    (a young tibia's cortex is denser than the hand's bone)."""
    lab = L.components(ct, np.zeros(ct.shape, bool))
    low = lab[:, :, :int(120 / 1.5)]; sz = np.bincount(low.ravel()); sz[0] = 0; c = int(sz.argmax())
    top = lab[:, :, -8:]; ids, n = np.unique(top[top > 0], return_counts=True)
    lab[np.isin(lab, ids[n >= 100])] = c
    point = tuple(np.argwhere(low == c)[0])
    sm, bone, lo = L.work_volume(ct, lab, point); del lab
    ws = L.pieces(sm, bone)
    leg = [int(t) for t in np.unique(ws[:, :, -UP * 18:]) if t]
    bad = L.drop_foreign(sm, bone, ws, keep=leg)
    return sm, bone, lo, ws, leg, bad


# MARK: 3. each bone

def split_foot(sm, bone, ws, paths, which, spec, leg, tip_hu=120, tip_mm=16, gap_mm=3.0, seed_r=2.5, beta=2000, sheet=3.0):
    """Label each bone of the foot. Returns (labels, names); the leg's
    bones are labelled "leg" (not kept)."""
    from skimage.segmentation import random_walker
    bone = bone.copy()
    # the toes' tufts: what is above the tuft threshold beyond each tip, touching it or across a gap; each
    # toe's zone holds only what is nearer its own tip than any other (a short toe's would reach its neighbour's)
    grown = np.zeros_like(bone); own = {}; tips = np.array([paths[which[f]][0] for f in TOES], float)
    for k, f in enumerate(TOES):
        P = paths[which[f]].astype(float); tip = P[0]; t = P[0] - P[min(16, len(P) - 1)]; t /= np.linalg.norm(t)
        R = int(tip_mm / VX) + 2; a = np.maximum(np.round(tip).astype(int) - R, 0); b = np.minimum(np.round(tip).astype(int) + R, bone.shape)
        sl = tuple(slice(a[i], b[i]) for i in range(3)); g = np.indices(b - a).reshape(3, -1).T + a
        along = ((g - tip) @ t * VX).reshape(b - a); dall = np.linalg.norm(g[:, None, :] - tips[None], axis=2)
        dist = (dall[:, k] * VX).reshape(b - a); nearest = (dall.argmin(1) == k).reshape(b - a)
        zone = (dist < tip_mm) & (along > -3) & nearest
        cand = (sm[sl] > tip_hu) & zone & ~bone[sl]
        lab, n = ndimage.label(cand)
        reach = ndimage.binary_dilation(bone[sl] & zone, iterations=int(round(gap_mm / VX)))
        touch = ndimage.binary_dilation(bone[sl] & zone)
        add = np.zeros_like(cand)
        for c in range(1, n + 1):
            m = lab == c
            if (m & touch).any() or ((m & reach).any() and m.sum() * VX ** 3 >= 20):
                add |= m
        grown[sl] |= add; own[f] = np.argwhere(add) + a
    bone |= grown; bone = ndimage.binary_fill_holes(bone)

    markers = np.zeros(bone.shape, np.int32); names = []

    def put(name, m):
        if name not in names:
            names.append(name)
        lid = names.index(name) + 1; markers[m & bone & (markers == 0)] = lid
        return lid

    def segment(P, s, j0, j1, r, keep_end=False):
        """Seed balls along P between j0 and j1 mm, kept clear of both joints."""
        m_ = max(r + 1.5, 0.2 * (j1 - max(j0, 0)))
        lo_, hi_ = max(j0 + m_, 0), (j1 if keep_end else j1 - m_)
        if hi_ <= lo_:
            lo_ = hi_ = (max(j0, 0) + j1) / 2
        pts = P[(s >= lo_ - 0.4) & (s <= hi_ + 0.4)]
        return _ball(bone.shape, pts, r)

    leg_m = np.isin(ws, leg)
    # along the tibia's axis: the leg above the ankle joint (less 3 mm), within 25 mm of the axis and holding
    # the shaft (the heel of a foot pointed down rises level with the joint, behind it); the talus from the
    # joint to the one under it (its dome broad, then a narrow core); the calcaneus a core below that
    _, ax, end = leg_axis(ws, leg); idx = np.argwhere(bone); rel = (idx - end).astype(float)
    t_ = rel @ ax * VX; rad = np.linalg.norm(rel - np.outer(rel @ ax, ax), axis=1) * VX; ankle, sub = spec["ankle"]
    above = np.zeros_like(bone); above[tuple(idx[(t_ < ankle - 3) & (rad < 25)].T)] = True
    cl, _ = ndimage.label(above | leg_m); above = np.isin(cl, np.unique(cl[leg_m])) & above
    core = ((t_ > ankle + 3) & (t_ < ankle + 10) & (rad < 10)) | ((t_ >= ankle + 10) & (t_ < sub - 4) & (rad < 5))
    dome = np.zeros_like(bone); dome[tuple(idx[core].T)] = True
    under = np.zeros_like(bone); under[tuple(idx[(t_ > sub + 4) & (t_ < sub + 16) & (rad < 5)].T)] = True
    put("leg", above | ndimage.binary_erosion(leg_m, iterations=2))
    # the toes, along their rays
    for f in TOES:
        P = paths[which[f]].astype(float); s = L.arclength(P); J = [-30.0] + list(spec["toes"][f]); bn = bone_names(f)[:-1]
        for i, nm in enumerate(bn):
            pts_m = segment(P, s, J[i], J[i + 1], 2.0)
            if J[i] < 0 and len(own[f]):   # the distal phalanx's seed reaches into the tuft
                tv = P[0] - P[min(16, len(P) - 1)]; tv /= np.linalg.norm(tv); g = own[f]
                far = g[(g - P[0]) @ tv * VX > 1.5]
                if len(far):
                    pts_m[tuple(far.T)] = True
            assert pts_m.any(), f"no seed for the {nm}"
            put(nm, pts_m)
    # the metatarsals and tarsal bones, along the metatarsals' lines
    lines = {}
    for f in TOES:
        P = paths[which[f]].astype(float); head, t = mt_line(P, spec["toes"][f][-1], spec.get("fit", {}).get(f, (8, 28)))
        lines[f] = (head, t)
        J = [0.0] + list(spec["lines"][f]); bn = ([bone_names(f)[-1]] + LINE_BONES[f])[:len(J)]
        Q = head + np.arange(0, J[-1] + 16, 0.5)[:, None] / VX * t; sq = np.arange(0, J[-1] + 16, 0.5)
        for i, nm in enumerate(bn):
            if i + 1 < len(J):
                put(nm, segment(Q, sq, J[i] + (3 if i == 0 else 0), J[i + 1], 3.0))
            else:                                               # past the last joint: 5-9 mm into the bone
                put(nm, _ball(bone.shape, Q[(sq >= J[i] + 5) & (sq <= J[i] + 9)], 2.5))
    # the sesamoids, under the first metatarsal's head (FEET), and the head's core, so the walk parts them
    # at the joint between them (the metatarsal's own seeds start well behind its head)
    head, t = lines["great"]; sole = ax - (ax @ t) * t; sole /= np.linalg.norm(sole)
    medial = np.cross(t, sole); medial = medial if medial @ (lines["great"][0] - lines["little"][0]) > 0 else -medial
    ses = np.array([head + (s * t + p * sole + q * medial) / VX for s, p, q in spec["sesamoids"]])
    lid = put(SESAMOIDS, _ball(bone.shape, ses, 2.0))
    assert (markers == lid).any(), "no seed for the sesamoids"
    put("first metatarsal", _ball(bone.shape, head + np.arange(5, 13.01, 0.5)[:, None] / VX * t, 2.5))
    # the talus: along the great toe's ray from the joint with the navicular to its neck, and its dome
    P = paths[which["great"]].astype(float); s = L.arclength(P); t0, t1 = spec["talus"]
    put("talus", _ball(bone.shape, P[(s >= t0 + 4) & (s <= t1 - 3)], 3.0) | dome)
    d = ndimage.distance_transform_edt(~above) * VX
    # the heel: the bone farthest from the toes' tips, away from the leg
    tips = np.array([paths[which[f]][0] for f in TOES], float).mean(0)
    idx = np.argwhere(bone & ~above & (d > 25)); far = np.linalg.norm(idx - tips, axis=1)
    heel = idx[far >= np.percentile(far, 99.0)]; hm = np.zeros_like(bone); hm[tuple(heel.T)] = True
    put("calcaneus", hm | under)

    # the random walk
    idx = np.argwhere(bone); a = np.maximum(idx.min(0) - 2, 0); b = idx.max(0) + 3
    sl = tuple(slice(a[i], b[i]) for i in range(3))
    data = np.clip((sm[sl] + 100) / 1500, 0, 1).astype(np.float64)
    if sheet:
        data -= sheet * L.sheetness(sm[sl], bone[sl]) / 1500
    mk = markers[sl].copy(); mk[~bone[sl]] = -1
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        res = random_walker(data, mk, beta=beta, mode="cg_mg", tol=1e-3)
    res[res < 0] = 0; lab = np.zeros(bone.shape, np.int32); lab[sl] = res

    # The walk parts the sesamoids from the first metatarsal where their dense cores end, leaving the
    # metatarsal's head wrapped round them: within 7 mm of their centres (a sesamoid is about 12 by
    # 8 mm), the two are parted again by a watershed on the CT, from those cores and the head beyond,
    # which meet in the joint between them where it shows
    from skimage.segmentation import watershed
    ls, l1 = names.index(SESAMOIDS) + 1, names.index("first metatarsal") + 1
    R_ = int(12 / VX); a = np.maximum(ses.min(0).astype(int) - R_, 0); b = np.minimum(ses.max(0).astype(int) + R_ + 1, lab.shape)
    sl = tuple(slice(a[i], b[i]) for i in range(3)); sub = lab[sl]
    g = np.indices(b - a).reshape(3, -1).T + a; near = (np.min(np.linalg.norm(g[:, None] - ses[None], axis=2), 1) * VX).reshape(b - a)
    both = np.isin(sub, [ls, l1]) & (near < 10)
    mk = np.zeros(sub.shape, np.int32); mk[both & (sub == ls)] = 1; mk[both & (sub == l1) & (near > 7)] = 2
    w = watershed(-ndimage.gaussian_filter(sm[sl].astype(np.float32), 0.7), markers=mk, mask=both)
    sub[w == 1] = ls; sub[w == 2] = l1

    # each bone's main piece kept, stray bits to the bone they touch most; each closed into one solid
    for l in range(1, len(names) + 1):
        cc, n = ndimage.label(lab == l)
        if n > 1:
            size = ndimage.sum(np.ones_like(cc), cc, range(1, n + 1)); big = int(np.argmax(size)) + 1
            for j in range(1, n + 1):
                if j == big:
                    continue
                part = cc == j; nb = lab[ndimage.binary_dilation(part) & ~part]; nb = nb[(nb > 0) & (nb != l)]
                lab[part] = np.bincount(nb).argmax() if len(nb) else 0
    # flaps no more than 1.5 mm thick (the walk leaves them along the joints; smoothed, they come apart in holes)
    cross = ndimage.generate_binary_structure(3, 1)
    for l in range(1, len(names) + 1):
        if names[l - 1] != "leg":
            m = lab == l; lab[m & ~ndimage.binary_opening(m, cross)] = 0
    # Where a bone's thin cortex fell under the threshold, the marrow behind it (the calcaneus's neutral
    # triangle is nearly as dark as fat) opens a pit or a tunnel into it: each bone is filled slice by
    # slice along the three axes (no foot bone has a hole through it) and closed harder until its
    # surface, as bone_meshes makes it, is one piece without a hole; what still stands apart is dropped
    ball = ndimage.generate_binary_structure(3, 1); cube = np.ones((3, 3, 3), bool)
    for l in range(1, len(names) + 1):
        m = lab == l
        if names[l - 1] == "leg" or not m.any():
            continue
        idx = np.argwhere(m); a = np.maximum(idx.min(0) - 8, 0); b = np.minimum(idx.max(0) + 9, lab.shape)
        sl = tuple(slice(a[i], b[i]) for i in range(3)); sub = lab[sl]; m = m[sl]; best = None
        for it in range(5):
            c = ndimage.binary_closing(m, ball, iterations=2) if it == 0 else ndimage.binary_closing(m, cube, iterations=it)
            c = m | (_fill_slices(ndimage.binary_fill_holes(c)) & (sub == 0))
            parts, chi = _surface(c)
            if best is None or (parts, -chi) < best[:2]:
                best = (parts, -chi, c)
            if parts == 1 and chi == 2:
                break
        parts, _, c = best
        if parts > 1:
            sm_ = ndimage.gaussian_filter(c.astype(np.float32), 1.0) > 0.5; cl, n = ndimage.label(sm_)
            main = cl == np.bincount(cl.ravel())[1:].argmax() + 1
            sub[c & ~ndimage.binary_dilation(main, iterations=2) & (sub == l)] = 0
            c &= ndimage.binary_dilation(main, iterations=2)
        sub[c & (sub == 0)] = l
    return lab, names, lines


def _fill_slices(c):
    """c with what each of its slices encloses filled, along the three axes."""
    for k in range(3):
        st = np.zeros((3, 3, 3), bool); ix = [slice(None)] * 3; ix[k] = 1
        st[tuple(ix)] = ndimage.generate_binary_structure(2, 1)
        c = ndimage.binary_fill_holes(c, structure=st)
    return c


def _surface(m, sigma=1.0):
    """The surface bone_meshes makes of m (smoothed, at half): (parts, V - E + F),
    2 for one closed piece without a hole through it."""
    from skimage.measure import marching_cubes
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    v, f, _, _ = marching_cubes(ndimage.gaussian_filter(np.pad(m, 2).astype(np.float32), sigma), 0.5)
    e = np.unique(np.sort(np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1), axis=0)
    _, part = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(v),) * 2), directed=False)
    return len(np.unique(part[f[:, 0]])), len(v) - len(e) + len(f)


def _ball(shape, pts, rad_mm):
    return L._ball_mask(shape, pts, rad_mm) if len(pts) else np.zeros(shape, bool)


def bones_from_scan(sex, folder):
    """The labelled foot of one body's scan, on the fine grid:
    (labels, names, lo, affine, paths, which, the metatarsals' lines)."""
    import nibabel
    spec = FEET[sex]
    im = nibabel.as_closest_canonical(nibabel.load(f"{folder}/ct.nii.gz")); A = im.affine
    ct, off = foot_volume(np.asarray(im.dataobj, dtype=np.int16), A, spec["side"])
    log(f"    {spec['subject']}: the foot's bone by density")
    sm, bone, lo, ws, leg, bad = foot_pieces(ct); del ct
    if bad:
        log(f"    {spec['subject']}: {len(bad)} pieces denser than bone left out")
    log(f"    {spec['subject']}: {ws.max()} pieces, the leg's {len(leg)}; tracing the rays")
    paths = L.rays(sm, bone, ws, leg)
    medial = np.array([-1.0, 0, 0]) if spec["side"] == "right" else np.array([1.0, 0, 0])
    which = name_toes(paths, np.linalg.solve(A[:3, :3], medial))
    log("    rays: " + ", ".join(f"{f} {L.arclength(paths[which[f]])[-1]:.0f} mm" for f in TOES))
    labels, names, lines = split_foot(sm, bone, ws, paths, which, spec, leg)
    return labels, names, lo + off, A, paths, which, lines


# MARK: 4. posed into the body

def skin_foot(v, f, side, y_cut, h=0.0015):
    """The skin's foot and ankle below y = y_cut on this side (1 left, -1
    right) as a solid; its sole's level; its long axis (the footprint's,
    the skin within 30 mm of the sole, across x and z, forward); its heel's
    and toes' ends along that axis (within 40 mm of the sole: the back of
    the ankle above can stand out behind the heel) and its length."""
    import anatomy_gaps as g
    on = (v[f][:, :, 1] < y_cut + 0.01).any(1) & (side * v[f][:, :, 0] > 0).all(1)
    f2 = f[on]; used = np.unique(f2); remap = -np.ones(len(v), int); remap[used] = np.arange(len(used)); v2 = v[used]; f2 = remap[f2]
    loop = max(g._loops(v2, f2, np.array([0.0, y_cut, 0.0]), np.array([0.0, 1.0, 0.0])), key=len)
    c = loop.mean(0); loop = loop[np.argsort(np.arctan2(loop[:, 2] - c[2], loop[:, 0] - c[0]))]
    rings = [c + (loop - c) * r for r in (1.0, 0.8, 0.6, 0.4, 0.2)]       # the cut capped in rings
    k = len(loop); n0 = len(v2); cf = []
    for r in range(len(rings) - 1):
        for i in range(k):
            a0, a1 = n0 + r * k + i, n0 + r * k + (i + 1) % k
            cf += [[a0, a1, a1 + k], [a0, a1 + k, a0 + k]]
    last = n0 + (len(rings) - 1) * k
    cf += [[last + i, last + (i + 1) % k, n0 + len(rings) * k] for i in range(k)]
    S = g.Solid([(np.vstack([v2] + rings + [c[None]]), np.vstack([f2, np.array(cf)]))], h=h, close=1)
    G = S.g.copy(); lo = S.lo
    G[:, lo[1] + (np.arange(G.shape[1]) + 0.5) * h > y_cut - 0.002, :] = False
    G = ndimage.gaussian_filter(G.astype(np.float32), 1.0) > 0.5
    lab, _ = ndimage.label(G); sz = np.bincount(lab.ravel()); sz[0] = 0; G = lab == sz.argmax()
    q = v2[v2[:, 1] < y_cut]; y0 = q[:, 1].min(); fp = q[q[:, 1] < y0 + 0.03]; c = fp.mean(0)
    u = np.linalg.svd(fp[:, [0, 2]] - c[[0, 2]], full_matrices=False)[2][0]; ax = np.array([u[0], 0.0, u[1]])
    ax = ax if ax[2] > 0 else -ax; t = (q[q[:, 1] < y0 + 0.04] - c) @ ax   # the heel's back and the toes' end, near the floor
    return {"solid": (G, lo, h), "sole": float(y0), "axis": ax, "heel": c + t.min() * ax, "toe": c + t.max() * ax,
            "length": float(t.max() - t.min()), "side": side}


def _rigid(src, dst, w):
    w = w / w.sum(); ms, md = w @ src, w @ dst; a, b = src - ms, dst - md
    U, _, Vt = np.linalg.svd((b * w[:, None]).T @ a); D = np.eye(3)
    if np.linalg.det(U @ Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt
    return R, md - R @ ms


def fit_leg(leg, H, rounds=30):
    """The rigid motion taking the scan's leg (its tibia and fibula's lowest
    part, sized already) onto the body's tibia and fibula H: their long axes
    and lower ends lined up, then refined by nearest points with the
    lowest 40 mm counted four times. Returns (R, t, mean distance m)."""
    from scipy.spatial import cKDTree
    _, a1 = L._axis(leg); a1 = a1 if a1[1] > 0 else -a1
    _, a2 = L._axis(H); a2 = a2 if a2[1] > 0 else -a2
    e1, e2 = L._end(leg, a1, False), L._end(H, a2, False)
    tgt = H[(H - e2) @ a2 < ((leg - e1) @ a1).max() + 0.01]
    R = L._rot(a1, a2); t = e2 - R @ e1
    tree = cKDTree(tgt); src = leg[np.random.default_rng(0).choice(len(leg), min(len(leg), 4000), replace=False)]
    w = np.where((src - e1) @ a1 < 0.04, 4.0, 1.0)
    for _ in range(rounds):
        d, i = tree.query(src @ R.T + t); keep = d < np.percentile(d, 90)
        R, t = _rigid(src[keep], tgt[i[keep]], w[keep])
    return R, t, float(np.mean(tree.query(src @ R.T + t)[0]))


def _lowest(p, down, share=3):
    """The mean of p's points farthest along down."""
    s = p @ down
    return p[s >= np.percentile(s, 100 - share)].mean(0)


def toe_chain(toe):
    """A toe's bones, base to tip."""
    return bone_names(toe)[:-1][::-1]


def pose_foot(pts, H, foot, back=0.008, pulp=0.005, margin=0.002, pad=0.014):
    """Pose one foot: pts, name -> the scan's points of each bone (atlas
    frame, on this side already), "leg" among them (its tibia and fibula's
    lowest part, not kept); H, the body's tibia and fibula; foot,
    skin_foot()'s. Returns the Pose and what it found."""
    import anatomy_gaps as g
    from scipy.spatial import cKDTree
    G, glo, gh = foot["solid"]; P = L.Pose(pts); facts = {}
    every = list(pts); bones = [n for n in every if n != "leg"]
    down0 = np.array([0.0, -1.0, 0.0]); ax = foot["axis"]

    def outside(names):   # the share of these bones the skin does not hold
        p = np.vstack([P.p[n] for n in names]); idx = np.floor((p - glo) / gh).astype(int)
        ok = ((idx >= 0) & (idx < G.shape)).all(1); ins = np.zeros(len(p), bool); ins[ok] = G[tuple(idx[ok].T)]
        return float(1 - ins.mean())

    # 1. sized to the skin's foot: the bones' length, heel to the farthest toe tip along the foot,
    #    the skin's less the soft tissue behind the heel and at the tip (the scan's leg with them)
    F_ = np.vstack([pts[n] for n in bones]); c0, u = L._axis(F_)
    u = u if (pts["distal phalanx of second toe"].mean(0) - c0) @ u > 0 else -u
    t = (F_ - c0) @ u; want = (foot["length"] - back - pulp) / (t.max() - t.min())
    k = float(np.clip(want, 0.85, 1.25)); P.move(every, np.eye(3), c0, k)
    facts["scale wanted"] = float(want); facts["scale"] = k

    # 2. the scan's leg onto the body's: the talus in the body's ankle
    R, t_, fit = fit_leg(P.p["leg"], H); P.move(every, R, np.zeros(3), 1.0, t_); facts["leg fit mm"] = fit * 1000
    _, a2 = L._axis(H); a2 = a2 if a2[1] > 0 else -a2

    # 3. turned about the talus's dome (a sphere fitted where it meets the leg) so the sole's three
    #    points of support (the heel bone, the sesamoids, the fifth metatarsal's head) lie level, and
    #    the line from the heel to the second metatarsal's head runs along the skin's foot
    tal = P.p["talus"]; d, _ = cKDTree(P.p["leg"]).query(tal); top = tal[d < 0.003]
    top = top[(top - top.mean(0)) @ a2 > -0.002]; D, rD = g._sphere(top); facts["dome radius mm"] = float(rD * 1000)
    def support(down):
        for _ in range(4):
            C, M1, M5 = (_lowest(P.p[n], down) for n in ("calcaneus", SESAMOIDS, "fifth metatarsal"))
            n_ = np.cross(M1 - C, M5 - C); n_ /= np.linalg.norm(n_); down = n_ if n_ @ down > 0 else -n_
        return down, C, M1, M5
    down, C, M1, M5 = support(-a2)
    m2 = L._joint(P.p["second metatarsal"], P.p["proximal phalanx of second toe"])
    fwd = m2 - C; fwd -= (fwd @ down) * down
    R1 = L._rot(down, down0); R2 = L._turn(down0, L._angle_about(R1 @ fwd, ax, down0))
    P.move(bones, R2 @ R1, D)
    facts["turned deg"] = float(np.degrees(np.arccos(np.clip((np.trace(R2 @ R1) - 1) / 2, -1, 1))))

    # 4. fitted into the skin, from there: a small turn about the dome, a shift of the whole foot and its
    #    sizes along, across and up the foot (about the dome), chosen so the bones lie at least `margin`
    #    inside the skin, the heel bone's lowest about `pad` above the sole, each kept near where the leg
    #    and the bones' own proportions put it (the skins' feet are not all a foot's shape: lying, a
    #    body's heel spreads behind the ankle; hers is long and narrow). First without the toes, which
    #    step 5 then fits; then once more with them, and the toes again.
    from scipy.optimize import minimize
    sdf = (ndimage.distance_transform_edt(~G) - ndimage.distance_transform_edt(G)) * gh   # + outside the skin
    def depth(p):   # mm outside the skin (- inside)
        return ndimage.map_coordinates(sdf, ((p - glo) / gh - 0.5).T, order=1, mode="nearest") * 1000
    up = -down0; lat = np.array([foot["side"], 0.0, 0.0]); lat -= (lat @ ax) * ax; lat /= np.linalg.norm(lat)
    Fr = np.column_stack([ax, lat, up]); toes = [n for f in TOES for n in toe_chain(f)]
    rng = np.random.default_rng(1)

    def fit_whole(D, with_toes):
        use = [n for n in bones if with_toes or n not in toes]
        X = np.vstack([P.p[n][rng.choice(len(P.p[n]), min(len(P.p[n]), 1500), replace=False)] for n in use])
        rest = np.concatenate([np.full(min(len(P.p[n]), 1500), n not in toes) for n in use])   # the sole's level: not the toes
        def motion(q):
            R = L._turn(up, np.radians(q[0])) @ L._turn(lat, np.radians(q[1])) @ L._turn(ax, np.radians(q[2]))
            return R @ Fr @ np.diag(np.exp(q[6:9])) @ Fr.T, D + Fr @ q[3:6] / 1000
        def cost(q):
            A, t = motion(q); Y = (X - D) @ A.T + t
            out = np.mean(np.maximum(depth(Y) + margin * 1000, 0) ** 2)
            low = (np.percentile(Y[rest] @ up, 0.5) - foot["sole"]) * 1000
            return (20 * out + (np.linalg.norm(q[3:6]) / 3) ** 2 + (np.linalg.norm(q[:3]) / 10) ** 2 + ((low - pad * 1000) / 4) ** 2
                    + (q[6] / 0.05) ** 2 + ((q[7] - q[6]) / 0.06) ** 2 + ((q[8] - q[6]) / 0.06) ** 2)
        lim = [(-15, 15)] * 3 + [(-8, 8)] * 3 + [(np.log(0.88), np.log(1.12))] * 3
        res = minimize(cost, np.zeros(9), method="Powell", bounds=lim, options={"xtol": 1e-3, "ftol": 1e-6, "maxfev": 6000})
        A, t = motion(res.x); P.move(bones, A, D, 1.0, t)
        return res.x, t

    # 5. each toe fitted into the skin's: bent at each joint (the base joint 30 degrees up to 40 down, the
    #    others 5 up to 45 down, the great toe's 30), turned at its base up to 15 degrees either way, and
    #    shortened to no less than 0.8 of its length: the least change that brings it in, a bend weighing
    #    as much as 45 degrees, a turn as 15 and a shortening as 8% (the scan's toes lie as that foot's
    #    did, the skin's as the body's; a skin's toes can be shorter than a foot's bones and soft tissue need)
    flex = lat * foot["side"]   # about this, a positive turn bends a toe down on either side;
                                # about up * side, it turns a toe outward
    def toe_out(pts):
        return float(np.mean(np.maximum(depth(np.vstack(list(pts.values()))) + margin * 1000, 0) ** 2))

    def fit_toes(before=None):   # before: the first pass's, which this one's limits and costs count in
        got = {}
        for f in TOES:
            ch = [METATARSAL[f] + " metatarsal"] + toe_chain(f); n = len(ch) - 1
            J = [L._joint(P.p[ch[i]], P.p[ch[i + 1]]) for i in range(n)]
            sub = {c: P.p[c][rng.choice(len(P.p[c]), min(len(P.p[c]), 1500), replace=False)] for c in ch[1:]}
            def turns(q):   # (bones, R, about) from the tip's joint to the base's, then the shortening about the base
                out = [(ch[i + 1:], L._turn(flex, np.radians(q[2 + i])), J[i]) for i in range(n - 1, 0, -1)]
                return out + [(ch[1:], L._turn(up * foot["side"], np.radians(q[1])) @ L._turn(flex, np.radians(q[2])), J[0])]
            def placed(q):
                p = {c: v.copy() for c, v in sub.items()}
                for names_, R, c in turns(q):
                    for m in names_:
                        p[m] = c + (p[m] - c) @ R.T
                return {m: J[0] + q[0] * (v - J[0]) for m, v in p.items()}
            b = np.array([1.0, 0.0] + [0.0] * n) if before is None else before[f]
            def total(q):
                return np.concatenate([[q[0] * b[0]], np.asarray(q[1:]) + b[1:]])
            def toe_cost(q):
                t = total(q)
                return (10 * toe_out(placed(q)) + np.sum((t[2:] / 45) ** 2) + (t[1] / 15) ** 2 + (np.log(t[0]) / 0.08) ** 2)
            lim = [(0.8, 1.0), (-15, 15), (-30, 40)] + [(-5, 30 if f == "great" else 45)] * (n - 1)
            lim = [(lo_ / b[0], min(hi_ / b[0], 1.0)) if i == 0 else (lo_ - b[i], hi_ - b[i]) for i, (lo_, hi_) in enumerate(lim)]
            r_ = minimize(toe_cost, np.array([1.0, 0.0] + [0.0] * n), method="Powell", bounds=lim,
                          options={"xtol": 1e-2, "ftol": 1e-5, "maxfev": 3000})
            for names_, R, c in turns(r_.x):
                P.move(names_, R, c)
            P.move(ch[1:], np.eye(3), J[0], float(r_.x[0])); got[f] = total(r_.x)
        return got

    q1, D = fit_whole(D, False); t1 = fit_toes(); q2, D = fit_whole(D, True); t2 = fit_toes(t1)
    for k_, q in (("fit", q1), ("refit", q2)):
        facts[k_ + " turn deg"] = [round(float(x), 1) for x in q[:3]]; facts[k_ + " shift mm"] = [round(float(x), 1) for x in q[3:6]]
        facts[k_ + " sizes"] = [round(float(np.exp(x)), 3) for x in q[6:9]]
    for f in TOES:   # both passes' (bends and turns add up near enough, shortenings multiply)
        facts[f"{f} toe bent deg"] = [round(float(a), 1) for a in t2[f][2:]]
        facts[f"{f} toe turned deg"] = round(float(t2[f][1]), 1); facts[f"{f} toe scale"] = round(float(t2[f][0]), 3)

    # 6. what the skin holds, and how the bones sit in it
    down, C, M1, M5 = support(down0)
    tips = np.vstack([P.p[toe_chain(f)[-1]] for f in TOES])
    heel = P.p["calcaneus"][np.argmin(P.p["calcaneus"] @ ax)]
    facts["heel pad mm"] = float((C[1] - foot["sole"]) * 1000); facts["ball pad mm"] = float((M1[1] - foot["sole"]) * 1000)
    facts["behind the heel mm"] = float((heel - foot["heel"]) @ ax * 1000)
    facts["toe pulp mm"] = float((foot["toe"] - tips[np.argmax(tips @ ax)]) @ ax * 1000)
    facts["outside the skin"] = {n: round(outside([n]), 3) for n in bones}
    return P, facts


# MARK: 5. both sides, as meshes

BUDGET = {"talus": 1200, "calcaneus": 1500}   # triangles; the other tarsals 600, metatarsals 400, phalanges 250, the sesamoids 150


def files_used(sex):
    return ["ct.nii.gz"]


def budget(name):
    if name in BUDGET:
        return BUDGET[name]
    if name in TARSALS:
        return 600
    if name.endswith("metatarsal"):
        return 400
    return 150 if name == SESAMOIDS else 250


def smooth(p, f, n=10, lam=0.5, mu=-0.53):
    """Taubin smoothing (each step towards the neighbours' mean, then back
    a little): the CT's 1.5 mm steps taken off without shrinking the bone."""
    from scipy.sparse import coo_matrix, diags
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]); e = np.vstack([e, e[:, ::-1]])
    A = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(p), len(p))).tocsr(); A.data[:] = 1
    W = diags(1 / np.maximum(np.asarray(A.sum(1)).ravel(), 1)) @ A
    for _ in range(n):
        p = p + lam * (W @ p - p); p = p + mu * (W @ p - p)
    return p


def feet(sex, ct_dir, legs, skin):
    """The foot bones of one body, both sides, posed into its skin. legs:
    {"left": points, "right": points}, the body's tibia and fibula; skin:
    (positions, triangles). Returns (structures, [(positions, triangles,
    budget)], facts by side)."""
    spec = FEET[sex]; folder = os.path.join(ct_dir, spec["subject"])
    labels, names, lo, affine, _, _, _ = bones_from_scan(sex, folder)
    meshes = {n: (smooth(p, f), f) for n, (p, f) in L.bone_meshes(labels, names, lo, affine).items()}; del labels
    rng = np.random.default_rng(0)
    pts = {n: p[rng.choice(len(p), min(len(p), 20000), replace=False)] for n, (p, f) in meshes.items()}
    taken = 1 if spec["side"] == "left" else -1
    structures, out, facts = [], [], {}
    for side, s in (("left", "L"), ("right", "R")):
        sign = 1 if side == "left" else -1
        M = np.diag([-1.0, 1, 1]) if sign != taken else np.eye(3)   # the other side: the mirror image
        mine = {n: q @ M.T for n, q in pts.items()}
        H = np.asarray(legs[side], float)
        foot = skin_foot(np.asarray(skin[0], float), skin[1], sign, H[:, 1].min() + 0.06)
        P, f_ = pose_foot(mine, H, foot); facts[side] = f_
        log(f"    {side} foot: x{f_['scale']:.2f}, sizes " + "/".join(f"{a * b:.2f}" for a, b in zip(f_["fit sizes"], f_["refit sizes"]))
            + f", leg fit {f_['leg fit mm']:.1f} mm, heel pad {f_['heel pad mm']:.0f} mm, toes x"
            + "/".join(f"{f_[t + ' toe scale']:.2f}" for t in TOES)
            + "; outside the skin: " + (", ".join(f"{k} {v:.0%}" for k, v in f_["outside the skin"].items() if v > 0.02) or "none"))
        for n in names:
            if n == "leg":
                continue
            p, f = meshes[n]; p = (p @ M.T) @ P.A[n].T + P.t[n]
            if sign != taken:
                f = f[:, [0, 2, 1]]
            structures.append({"node": f"TS_{n.replace(' ', '_')}_{s}", "label": f"{side} {n}", "uberon": uberon_of(n),
                               "tissue": "bone", "group": "Foot bones", "inner": False})
            out.append((p, f, budget(n)))
    return structures, out, facts
