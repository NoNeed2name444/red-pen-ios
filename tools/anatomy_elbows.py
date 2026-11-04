"""The elbows of both atlas bodies: each body's humerus with the upper ends
of its radius and ulna, found in one CT scan that holds the whole joint,
joined onto the forearm and hand bones tools/anatomy_limbs.py finds, so the
arm is one chain from shoulder to fingertips. Called by
tools/anatomy_limbs.py; not run on its own.

The scans the hands come from cut the elbow short: the man's (s1880) leaves
the olecranon outside its field of view, and in both the bone within 3 mm
of the humerus is set aside with it, which takes the olecranon's tip and
the radial head. So for each body a scan whose elbow lies whole in the
field of view (ELBOWS) gives the elbow:

1. Around the humerus's lower end, the bone by density (as for the hand:
   above 180 HU, no metal, opened, the other bones the dataset segments set
   aside), and on a grid twice as fine, smoothed, the humerus and the upper
   forearm told apart by a watershed on the CT from three seeds: the
   dataset's humerus label (shrunk by 1.5 mm), and the radius and ulna
   where they lie apart (the first 40 mm stretch below the elbow, from 50
   mm down, where they are two pieces). The joint lines are
   darker than the bone either side, so the watershed meets there. The
   ulna is the one reaching higher (the olecranon). Each forearm bone keeps
   0.75 mm clear of the humerus label, and the upper 150 mm of it.
2. Where the elbow's scan is not the hand's (the man's), the elbow is
   carried onto the hand's forearm by the similarity that best lays its
   radius and ulna over the hand scan's, tried from several starting
   heights (a shaft fits itself anywhere along its length; the radius and
   ulna together, thick and thin at opposite ends, do not), and its radius
   then turned about its own axis to lie as the hand scan's does (the scans
   hold their forearms turned differently).
3. Each forearm bone is then the elbow's above a band in its upper shaft
   and the hand scan's below it, blended across the band (a weighted sum of
   the two bones' signed distances), so the shaft runs on without a step.
4. The elbow's flexion axis runs through the centres of the trochlea and
   the capitulum, each the sphere that best fits the humerus's surface
   facing the ulna's notch and the radial head (tools/anatomy_limbs.py
   bends the forearm about it).

The humerus then is the elbow scan's, so the joint's two sides come from
one person and fit as they did in life.
"""
import numpy as np
from scipy import ndimage

# Per body: the scan and side whose elbow lies whole in the field of view.
ELBOWS = {
    "male": {"subject": "s1831", "side": "left"},     # a man of 33; his right elbow is cut by the field of view
    "female": {"subject": "s1764", "side": "right"},  # the female body's own scan, as for her hand
}
REACH = 150.0    # mm of forearm below the elbow taken from the elbow's scan
SLAB = (50.0, 200.0)   # mm below the forearm's top where the radius and ulna may be seeded apart
OTHERS = ["femur_left", "femur_right", "hip_left", "hip_right"]


def log(*a):
    print(*a, flush=True)


def files_used(sex):
    side = ELBOWS[sex]["side"]; other = "right" if side == "left" else "left"
    return ["ct.nii.gz", f"humerus_{side}.nii.gz", f"humerus_{other}.nii.gz"] + [k + ".nii.gz" for k in OTHERS]


def _pca(p):
    c = p.mean(0); _, _, vt = np.linalg.svd(p - c, full_matrices=False)
    return c, vt[0]


def _along(shape, origin, axis, scale):
    """Each voxel's distance along axis from origin (voxel units), times scale, without a coordinate array."""
    o = np.ogrid[tuple(slice(0, n) for n in shape)]
    return sum((o[k].astype(np.float32) - np.float32(origin[k])) * np.float32(axis[k] * scale) for k in range(3))


def elbow_from_scan(sex, folder, up=2):
    """The elbow of one body's elbow scan: {"humerus", "ulna", "radius":
    (points, triangles)} in the atlas frame as scanned (the forearm bones'
    upper REACH mm), and what was found."""
    import nibabel
    from skimage.segmentation import watershed
    from skimage.measure import marching_cubes
    import anatomy_gaps as g
    spec = ELBOWS[sex]; side = spec["side"]; other = "right" if side == "left" else "left"
    im = nibabel.load(f"{folder}/ct.nii.gz"); aff = im.affine; vx = float(abs(aff[0, 0]))
    hum_im = nibabel.load(f"{folder}/humerus_{side}.nii.gz"); hum_all = np.asarray(hum_im.dataobj) > 0
    idx = np.argwhere(hum_all); c, ax = _pca(idx.astype(float))
    t = (idx - c) @ ax
    if idx[t > np.percentile(t, 95), 2].mean() > idx[t < np.percentile(t, 5), 2].mean():
        ax = -ax                                                        # ax: shoulder to elbow (the arm hangs down)
    t = (idx - c) @ ax
    D = idx[t > np.percentile(t, 97)].mean(0)                           # the humerus's lower end
    r = int(round(165 / vx)); dn = int(round((REACH + 25) / vx)); upz = int(round(60 / vx))
    lo = np.maximum(np.round(D).astype(int) - [r, r, dn], 0)
    hi = np.minimum(np.round(D).astype(int) + [r, r, upz] + 1, im.shape)
    sl = tuple(slice(a, b) for a, b in zip(lo, hi))
    ct = np.asarray(im.dataobj[sl], dtype=np.int16); hum = hum_all[sl]; del hum_all, idx
    far = np.zeros(ct.shape, bool)
    for k in OTHERS + [f"humerus_{other}"]:
        far |= np.asarray(nibabel.load(f"{folder}/{k}.nii.gz").dataobj[sl]) > 0
    bone = (ct > 180) & ~ndimage.binary_dilation(ct > 1800, iterations=2)
    bone = ndimage.binary_opening(bone, ndimage.generate_binary_structure(3, 1))
    bone &= ~ndimage.binary_dilation(far, iterations=2); del far
    # the forearm: the big pieces of bone touching the humerus's lower end (within 40 mm of it), beyond it
    Dl = D - lo
    lab, n = ndimage.label(bone & ~ndimage.binary_dilation(hum), np.ones((3, 3, 3)))
    touch = ndimage.binary_dilation(hum, iterations=3) & (lab > 0) & (np.abs(_along(ct.shape, Dl, ax, vx)) < 40)
    ids = np.unique(lab[touch]); sz = np.bincount(lab.ravel())
    cand = sorted(((sz[i], int(i)) for i in ids if sz[i] > 2000 and (np.argwhere(lab == i).mean(0) - Dl) @ ax > 0), reverse=True)
    assert cand, f"{spec['subject']}: no forearm below the elbow"
    fore = np.isin(lab, [i for _, i in cand[:2]])
    # small pieces near it within 50 mm of the elbow (a radial head or olecranon tip set apart), ring by ring
    for _ in range(3):
        d = ndimage.distance_transform_edt(~fore) * vx
        near = [int(i) for i in np.unique(lab[(d <= 4.0) & (lab > 0) & ~fore]) if 50 <= sz[i] < 5000
                and np.linalg.norm(np.argwhere(lab == i).mean(0) - Dl) * vx < 50 and ct[lab == i].mean() <= 900]
        if not near:
            break
        fore |= np.isin(lab, near)
    del lab, touch
    comp = fore | hum | (bone & ndimage.binary_dilation(hum, iterations=2)); del bone
    # on a grid twice as fine around it, as for the hand (anatomy_limbs.work_volume)
    q = np.argwhere(comp); a = np.maximum(q.min(0) - 16, 0); b = np.minimum(q.max(0) + 17, ct.shape); del q
    s2 = tuple(slice(x, y) for x, y in zip(a, b)); lo = lo + a; Dl = Dl - a
    ct, hum, fore, comp = ct[s2], hum[s2], fore[s2], comp[s2]
    A = np.where(ndimage.binary_dilation(comp, iterations=10), ct.astype(np.float32), np.minimum(ct, 0).astype(np.float32))
    sm = ndimage.gaussian_filter(ndimage.zoom(A, up, order=3), 0.6 * up).astype(np.float32); del A
    C2 = ndimage.zoom(ndimage.binary_dilation(comp, iterations=2).astype(np.uint8), up, order=0) > 0
    bf = ndimage.binary_fill_holes((sm > 150) & C2); del C2
    H2 = ndimage.zoom(hum.astype(np.uint8), up, order=0) > 0
    F2 = ndimage.zoom(fore.astype(np.uint8), up, order=0) > 0
    fx = vx / up
    # the forearm's own axis, elbow to wrist, and each voxel's mm along it from the forearm's top
    fp = np.argwhere(F2 & bf).astype(float); fc, fa = _pca(fp)
    if ((fp - fc) @ fa)[np.argmax(np.linalg.norm(fp / up - Dl, axis=1))] < 0:
        fa = -fa
    tf = _along(sm.shape, fc + fa * ((fp - fc) @ fa).min(), fa, fx); del fp
    mk = np.zeros(sm.shape, np.int32)
    mk[ndimage.binary_erosion(H2, iterations=2) & bf] = 1
    two = None
    for a_ in np.arange(SLAB[0], SLAB[1], 10.0):   # the first 40 mm slab below the elbow where the two lie apart
        l2, k2 = ndimage.label(bf & F2 & ~H2 & (tf > a_) & (tf < a_ + 40), np.ones((3, 3, 3)))
        c2 = np.bincount(l2.ravel()); c2[0] = 0; top = np.sort(c2)[::-1]
        if k2 >= 2 and top[1] > 0.25 * top[0] and top[:2].sum() > 0.9 * top.sum():
            two = np.argsort(c2)[::-1][:2]; facts_slab = float(a_); break
    assert two is not None, f"{spec['subject']}: the radius and ulna are not apart below the elbow"
    mk[l2 == two[0]] = 2; mk[l2 == two[1]] = 3; del l2
    ws = watershed(-sm, mk, mask=bf | H2); del mk
    keep = ~ndimage.binary_dilation(H2) & (tf < REACH)
    found = {}
    for j in (2, 3):
        m = (ws == j) & keep
        l3, _ = ndimage.label(m, np.ones((3, 3, 3))); c3 = np.bincount(l3.ravel()); c3[0] = 0
        m = l3 == np.argmax(c3)
        m = ndimage.binary_fill_holes(ndimage.binary_closing(m, ndimage.generate_binary_structure(3, 1), iterations=2) & keep)
        found[j] = (m, float(tf[m].min()), float(tf[m].max()))
    ulna = 2 if found[2][1] < found[3][1] else 3
    facts = {"scan": spec["subject"], "side": side, "seeded at mm": facts_slab,
             "ulna mm": [round(found[ulna][1], 1), round(found[ulna][2], 1)],
             "radius mm": [round(found[5 - ulna][1], 1), round(found[5 - ulna][2], 1)]}
    del ws, sm, tf, bf
    out = {}
    for nm, m in (("ulna", found[ulna][0]), ("radius", found[5 - ulna][0])):
        q = np.argwhere(m); a = np.maximum(q.min(0) - 3, 0); b = q.max(0) + 4
        sub = np.pad(m[a[0]:b[0], a[1]:b[1], a[2]:b[2]].astype(np.float32), 2)
        v, f, _, _ = marching_cubes(ndimage.gaussian_filter(sub, 1.0), 0.5)
        n = np.array(m.shape) // up
        sc = lo + (v - 2 + a) * (n - 1) / (up * n - 1)                    # the fine grid is ndimage.zoom's: corners kept
        p = (sc @ aff[:3, :3].T + aff[:3, 3]) @ g.TO_ATLAS.T; f = f.astype(np.int64)
        if g.signed_volume(p, f) < 0:
            f = f[:, [0, 2, 1]]
        out[nm] = (p, f)
    out["humerus"] = g.ct_mesh(np.asarray(hum_im.dataobj) > 0, hum_im.affine)
    log(f"    {spec['subject']} {side} elbow: ulna {facts['ulna mm'][0]:.0f} to {facts['ulna mm'][1]:.0f} mm, "
        f"radius {facts['radius mm'][0]:.0f} to {facts['radius mm'][1]:.0f} mm below the forearm's top")
    return out, facts


# MARK: 2-3. the elbow joined onto the hand's forearm

def _sample(p, n, seed=0):
    return p if len(p) <= n else p[np.random.default_rng(seed).choice(len(p), n, replace=False)]


def _umeyama(src, dst, w, lo=0.85, hi=1.15):
    """The similarity taking src onto dst (weights w), its scale held within [lo, hi]."""
    w = w / w.sum(); ms, md = w @ src, w @ dst; a, b = src - ms, dst - md
    U, S, Vt = np.linalg.svd((b * w[:, None]).T @ a); D = np.eye(3)
    if np.linalg.det(U @ Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt; s = float(np.clip((S * np.diag(D)).sum() / (w * (a ** 2).sum(1)).sum(), lo, hi))
    return s, R, md - s * R @ ms


def _turn(k, t):
    k = k / np.linalg.norm(k); K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K


def _rot(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b); v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else _turn(np.cross(a, [1.0, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1.0, 0]), np.pi)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def _forearm_axis(ulna, radius, away):
    """The forearm's long axis through both bones, pointing away from `away`."""
    c, a = _pca(np.vstack([ulna, radius]))
    return (a if (c - away) @ a > 0 else -a), c


def fit_elbow_to_forearm(elbow, hand, tries=(0, 10, 20, 30, 40, 50, 60), trim=80, iters=40):
    """The similarity (s, R, t) laying the elbow scan's radius and ulna over
    the hand scan's, each bone onto its own, tried from several starting
    heights along the forearm; and the residual (mm)."""
    from scipy.spatial import cKDTree
    eu, er = elbow["ulna"][0], elbow["radius"][0]; hu, hr = hand["ulna"][0], hand["radius"][0]
    hum_c = elbow["humerus"][0].mean(0)
    ae, ce = _forearm_axis(eu, er, hum_c)
    ah, ch = _forearm_axis(hu, hr, hand["carpal bones"][0].mean(0)); ah = -ah   # elbow to wrist, as the elbow's
    te_u, te_r = (eu - ce) @ ae, (er - ce) @ ae; top_e = min(te_u.min(), te_r.min())
    th_u, th_r = (hu - ch) @ ah, (hr - ch) @ ah; top_h = min(th_u.min(), th_r.min())
    # the roll about the axis: the radius beside the ulna, 40 to 110 mm below each top
    def side_vec(u, r, tu, tr, top, a):
        mu = u[(tu > top + 40e-3) & (tu < top + 110e-3)].mean(0); mr = r[(tr > top + 40e-3) & (tr < top + 110e-3)].mean(0)
        v = mr - mu; v -= (v @ a) * a; return v / np.linalg.norm(v)
    R0 = _rot(ae, ah); v_e = R0 @ side_vec(eu, er, te_u, te_r, top_e, ae); v_h = side_vec(hu, hr, th_u, th_r, top_h, ah)
    ang = np.arctan2(np.cross(v_e, v_h) @ ah, v_e @ v_h); R0 = _turn(ah, ang) @ R0
    tree_u, tree_r = cKDTree(hu), cKDTree(hr)
    best = None
    for d in tries:
        # the hand's top taken d mm below the elbow's: source points below it (the hand's bones are whole there)
        su = _sample(eu[te_u > top_e + (d + 10) * 1e-3], 3000, 1); sr = _sample(er[te_r > top_e + (d + 10) * 1e-3], 3000, 2)
        if len(su) < 200 or len(sr) < 200:
            continue
        s = 1.0; R = R0.copy()
        t = ch + ah * top_h - R @ (ce + ae * (top_e + d * 1e-3))
        for _ in range(iters):
            pu = su @ (s * R).T + t; pr = sr @ (s * R).T + t
            du, iu = tree_u.query(pu); dr, ir = tree_r.query(pr)
            dd = np.concatenate([du, dr]); keep = dd <= np.percentile(dd, trim)
            src = np.vstack([su, sr])[keep]; dst = np.vstack([hu[iu], hr[ir]])[keep]
            s, R, t = _umeyama(src, dst, np.ones(len(src)))
        pu = su @ (s * R).T + t; pr = sr @ (s * R).T + t
        dd = np.concatenate([tree_u.query(pu)[0], tree_r.query(pr)[0]]); res = float(np.mean(np.sort(dd)[:int(len(dd) * trim / 100)]) * 1000)
        if best is None or res < best[0]:
            best = (res, s, R, t, d)
    assert best is not None, "the elbow's forearm is too short to fit"
    return best[1], best[2], best[3], {"fit mm": round(best[0], 2), "scale": round(best[1], 3), "start mm": best[4]}


def turn_radius(elbow_r, hand_r, pivot, far, below, span=40, step=2):
    """The angle (radians) about the line from the radial head's centre
    (pivot) to the ulna's lower end (far) that best lays the elbow's radius
    (its points below `below` along the line) over the hand's."""
    from scipy.spatial import cKDTree
    k = (far - pivot) / np.linalg.norm(far - pivot); tree = cKDTree(hand_r)
    src = _sample(elbow_r[(elbow_r - pivot) @ k > below], 3000, 3)
    best = (np.inf, 0.0)
    for deg in range(-span, span + 1, step):
        R = _turn(k, np.radians(deg)); d, _ = tree.query((src - pivot) @ R.T + pivot)
        r = np.mean(np.sort(d)[:int(0.8 * len(d))])
        best = min(best, (r, np.radians(deg)))
    return best[1], float(best[0] * 1000)


def _frame_of(axis):
    """A rotation taking `axis` to +z."""
    return _rot(axis, np.array([0.0, 0.0, 1.0]))


def _filled(p, f, lo, shape, h):
    import anatomy_gaps as g
    P = g.surface_points(p, f, h)
    idx = np.floor((P - lo) / h).astype(int); ok = ((idx >= 0) & (idx < shape)).all(1)
    G = np.zeros(shape, bool); G[tuple(idx[ok].T)] = True
    return ndimage.binary_fill_holes(ndimage.binary_closing(G, iterations=1))


def blend(upper, lower, axis, band, h=0.0004):
    """One bone from two: `upper` (points, triangles) above the band, `lower`
    below it, their signed distances mixed linearly across it. axis: the
    bone's long axis, upper to lower; band: (from, to) in metres along it
    (from the origin). Returns (points, triangles)."""
    from skimage.measure import marching_cubes
    import anatomy_gaps as g
    Q = _frame_of(axis)                                  # the bone's frame: its axis along z
    up = (upper[0] @ Q.T, upper[1]); lw = (lower[0] @ Q.T, lower[1])
    z0, z1 = band
    allp = np.vstack([up[0], lw[0]]); lo = allp.min(0) - 4 * h; shape = np.ceil((allp.max(0) + 4 * h - lo) / h).astype(int)
    A = _filled(*up, lo, shape, h); B = _filled(*lw, lo, shape, h)
    sd = lambda M: (ndimage.distance_transform_edt(~M) - ndimage.distance_transform_edt(M)).astype(np.float32) * h
    z = lo[2] + (np.arange(shape[2]) + 0.5) * h
    w = np.clip((z1 - z) / (z1 - z0), 0, 1).astype(np.float32)[None, None, :]
    S = w * sd(A) + (1 - w) * sd(B); del A, B
    S = ndimage.gaussian_filter(S, 0.7)
    v, f, _, _ = marching_cubes(S, 0.0)
    p = (lo + (v + 0.5) * h) @ Q                          # back from the bone's frame
    p, f = _largest(p, f.astype(np.int64))
    if g.signed_volume(p, f) < 0:
        f = f[:, [0, 2, 1]]
    return p, f


def _largest(p, f):
    """The mesh's largest connected piece."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    n, lab = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(p), len(p))), directed=False)
    if n == 1:
        return p, f
    keep = lab == np.bincount(lab[f[:, 0]]).argmax(); kf = f[keep[f[:, 0]]]
    remap = -np.ones(len(p), int); used = np.unique(kf); remap[used] = np.arange(len(used))
    return p[used], remap[kf]


def _sphere(p):
    A = np.c_[2 * p, np.ones(len(p))]; b = (p ** 2).sum(1)
    x, *_ = np.linalg.lstsq(A, b, rcond=None)
    return x[:3], float(np.sqrt(x[3] + x[:3] @ x[:3]))


def elbow_axis(hum, ulna, radius, near=3.0e-3):
    """The elbow's flexion axis: (a point on it, its direction from the
    trochlea to the capitulum), through the centres of the spheres fitted to
    the humerus's surface facing the ulna and the radius (within `near` of
    its closest approach to each), refined as the cylinder best fitting both."""
    from scipy.spatial import cKDTree
    from scipy.optimize import least_squares
    du, _ = cKDTree(ulna).query(hum); dr, _ = cKDTree(radius).query(hum)
    tro = hum[du < du.min() + near]; cap = hum[dr < dr.min() + near]
    Ct, rt = _sphere(tro); Cc, rc = _sphere(cap)
    n = (Cc - Ct) / np.linalg.norm(Cc - Ct)
    pts = np.vstack([tro, cap]); c0 = (Ct + Cc) / 2
    u = np.cross(n, [1.0, 0, 0]) if abs(n[0]) < 0.9 else np.cross(n, [0, 1.0, 0]); u /= np.linalg.norm(u); v = np.cross(n, u)
    def res(x):
        c = c0 + x[0] * u + x[1] * v; d = n + x[2] * u + x[3] * v; d = d / np.linalg.norm(d)
        q = pts - c; return np.linalg.norm(q - np.outer(q @ d, d), axis=1) - x[4]
    r0 = float(np.median(np.linalg.norm((pts - c0) - np.outer((pts - c0) @ n, n), axis=1)))
    x = least_squares(res, [0, 0, 0, 0, r0], loss="soft_l1", f_scale=1e-3).x
    c = c0 + x[0] * u + x[1] * v; d = n + x[2] * u + x[3] * v; d /= np.linalg.norm(d)
    # the axis point midway between the two joints, on the line
    mid = c + ((c0 - c) @ d) * d
    return mid, d, {"trochlea r mm": round(rt * 1000, 1), "capitulum r mm": round(rc * 1000, 1),
                    "joints apart mm": round(float(np.linalg.norm(Cc - Ct)) * 1000, 1),
                    "cylinder r mm": round(float(x[4]) * 1000, 1), "turned from the spheres' line deg": round(float(np.degrees(np.arccos(min(1, abs(d @ n))))), 1)}


def seat(hum, others, at, margin=1.0e-3, sigma=2.0e-3, reach=0.05, rounds=6, step=1.5e-3):
    """The humerus's surface moved out of the forearm's bones where they
    meet, within `reach` of `at` (the elbow), `margin` clear of them. A CT's
    mask fills much of the olecranon fossa (its floor is thin bone), so with
    the arm straight the olecranon's tip would lie in the humerus: the fossa
    is deepened to take it, as the living one does. hum: (points,
    triangles); others: [(points, triangles)], closed. Returns the
    humerus's new points and its deepest move, mm."""
    from scipy.spatial import cKDTree
    Q, N = [], []
    for p, f in others:
        a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
        n = np.cross(b - a, c - a)
        if np.einsum("ij,ij->i", a, n).sum() < 0:      # inside-out: the normals turned round
            n = -n
        vn = np.zeros_like(p)
        for k in range(3):
            np.add.at(vn, f[:, k], n)
        keep = np.linalg.norm(p - at, axis=1) < reach + 0.015
        Q.append(p[keep]); N.append(vn[keep] / np.maximum(np.linalg.norm(vn[keep], axis=1, keepdims=True), 1e-15))
    Q, N = np.vstack(Q), np.vstack(N); tree = cKDTree(Q)
    p0, f0 = hum; x = p0.copy(); sel = np.flatnonzero(np.linalg.norm(p0 - at, axis=1) < reach)
    for _ in range(rounds):
        y = x[sel]; d, i = tree.query(y, k=6)
        w = 1 / np.maximum(d, 1e-5); side = np.einsum("ijk,ijk->ij", y[:, None] - Q[i], N[i])
        s = -(side * w).sum(1) / w.sum(1)                                     # positive inside
        hit = s > -margin
        if not hit.any():
            break
        n0 = (N[i] * w[..., None]).sum(1); n0 /= np.maximum(np.linalg.norm(n0, axis=1, keepdims=True), 1e-15)
        D = (Q[i[hit, 0]] - y[hit]) + n0[hit] * margin; yh = y[hit]
        mv = np.zeros_like(y); ws = np.zeros(len(y))
        for j in range(0, len(y), 2000):     # each move spread over the surface round it
            g = np.exp(-((y[j:j + 2000, None] - yh[None]) ** 2).sum(-1) / (2 * sigma ** 2))
            mv[j:j + 2000] = g @ D; ws[j:j + 2000] = g.sum(1)
        mv /= np.maximum(ws, 1)[:, None]; L = np.linalg.norm(mv, axis=1, keepdims=True)
        x[sel] = y + mv * np.minimum(1, step / np.maximum(L, 1e-12))
    return x, float(np.linalg.norm(x - p0, axis=1).max() * 1000)


def join(elbow, hand, same):
    """The elbow carried onto the hand scan's forearm and joined to it:
    {"ulna", "radius": the whole bones, "humerus": the elbow scan's, all
    (points, triangles) in the hand scan's frame; "axis": the elbow's
    flexion axis (a point, a direction)}, and what was found."""
    if same:
        s, R, t = 1.0, np.eye(3), np.zeros(3); facts = {"carried": "the same scan"}
    else:
        s, R, t, facts = fit_elbow_to_forearm(elbow, hand)
    E = {k: (p @ (s * R).T + t, f) for k, (p, f) in elbow.items()}
    hu, hr = hand["ulna"][0], hand["radius"][0]
    ah, _ = _forearm_axis(hu, hr, hand["carpal bones"][0].mean(0)); ah = -ah        # elbow to wrist
    if not same:   # the radius turned about its own axis to lie as the hand scan's (the scans' forearms turned differently)
        er, fr = E["radius"]; te = er @ ah; head = er[te < te.min() + 10e-3].mean(0)
        far = hu[hu @ ah > np.percentile(hu @ ah, 96)].mean(0); k = (far - head) / np.linalg.norm(far - head)
        ang, res = turn_radius(er, hr, head, far, (hr @ k).min() - head @ k + 10e-3)
        E["radius"] = (head + (er - head) @ _turn(k, ang).T, fr)
        facts["radius turned deg"] = round(float(np.degrees(ang)), 1); facts["radius fit mm"] = round(res, 2)
    out = {}
    for b in ("ulna", "radius"):
        tH = hand[b][0] @ ah; tE = E[b][0] @ ah
        z0 = tH.min() + 10e-3; z1 = z0 + 20e-3
        if z1 > tE.max() - 15e-3:
            z1 = tE.max() - 15e-3; z0 = z1 - 20e-3
        assert z0 > tE.min() + 5e-3, f"the elbow's {b} does not reach the hand scan's"
        out[b] = blend(E[b], hand[b], ah, (z0, z1))
        facts[f"{b} joined mm below its top"] = round(float((z0 + z1) / 2 - min(tE.min(), tH.min())) * 1000, 1)
    out["humerus"] = E["humerus"]
    m, d, af = elbow_axis(E["humerus"][0], E["ulna"][0], E["radius"][0])
    out["axis"] = (m, d); facts.update(af)
    return out, facts
