"""teeth2.py: the from-scratch teeth with their outlines traced from Gray's plate.

tools/anatomy_teeth.py builds each permanent tooth from its textbook sizes and description. Seen from the cheek
side its crowns came out as blocks on pegs. Here the outline from that side is the one Gray's Anatomy 1918 draws
(Fig. 1002, "Permanent teeth. Right side", public domain; traced by trace_teeth.py into teeth_traced.json):
the crown's bulge and its narrowing to the neck, the root's taper and its bend toward the back of the mouth,
and for the lower molars the two roots and where they part. The sizes stay the textbook's (crown height, root
length, greatest width); the shape from tongue to cheek, the cusps and the grooves stay anatomy_teeth's.

Same frame as anatomy_teeth: x toward the back of the arch, y toward the cheek, z toward the biting surface,
the origin at the middle of the neck; millimetres.
"""
import json, os, sys
import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anatomy_teeth as AT

ARCHES = AT.ARCHES
_T = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "teeth_traced.json")))["teeth"]
_P, _cache = {}, {}
_OLD = (AT.shell, AT.root, AT.forked)


def profile(arch, i):
    """Tooth i's traced outline in its own frame (mm): heights z (rising), the outline's middle c and half-width a
    at each; for a lower molar also `fork` (the height its roots part at) and `roots` (mesial, distal), each with
    its own z, c, a."""
    if (arch, i) in _P:
        return _P[arch, i]
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    rows = _T["%s %d" % (arch, i)]
    rows = [r for r in (rows[::-1] if arch == "upper" else rows) if r[1]]   # from the biting end to the root's tip
    n = len(rows)
    lo = np.array([min(a for a, b in r[1]) for r in rows], float); hi = np.array([max(b for a, b in r[1]) for r in rows], float)
    w = ndimage.gaussian_filter1d(hi - lo, 3.0, mode="nearest")
    j = np.arange(n)
    z = H - j * (H + R) / (n - 1)                                       # one scale along the tooth: the drawing's own proportions
    kn = int(np.argmin(np.abs(z)))                                      # the row of the neck
    kx = W / w[z > 0.15 * H].max()                                      # mm for a pixel, across
    x0 = (lo[kn] + hi[kn]) / 2
    g = lambda q: ndimage.gaussian_filter1d(np.asarray(q, float), 7.0, mode="nearest")     # the drawing's line wavers by a pixel or two
    c = g((x0 - (lo + hi) / 2) * kx); half = np.maximum(g((hi - lo) / 2 * kx), 0.25)   # the drawing's right is toward the midline
    if kind in ("premolar", "molar"):                                   # the cusps are the biting surface's own: no pinch for them
        zs = H - (2.3 if kind == "premolar" else 2.0)
        ks = int(np.argmin(np.abs(z - zs)))
        s = np.clip((z[:ks] - zs) / (H - zs), 0, 1)
        half[:ks] = half[ks] * (1 - 0.06 * s * s); c[:ks] = c[ks]
    P = {"z": z[::-1].copy(), "c": c[::-1].copy(), "a": half[::-1].copy(), "neck_row": kn, "rows": n,
         "mm_per_px": (round(kx, 4), round((H + R) / (n - 1), 4))}
    if kind == "molar" and arch == "lower":
        # two roots, one in front and one behind. Low down the drawing shows the gap between them; from there up to
        # where the roots part (about 3.5 mm under the neck, lower in the hinder molars) the gap is run on, narrowing to nothing
        two = [k for k in range(kn, n) if z[k] < -1.5 and len(rows[k][1]) >= 2]
        kf = two[0]
        zt = (-3.5, -4.2, -5.5)[i - 5]
        gap = lambda k: (min(r[1] for r in rows[k][1]), max(r[0] for r in rows[k][1]))      # (its left edge, its right edge)
        first = np.array([gap(k) for k in two[:40]], float)
        mid = np.polyfit(np.arange(len(first)), first.mean(1), 1)
        w0 = (first[:8, 1] - first[:8, 0]).mean() / 2
        kt = int(np.argmin(np.abs(z - zt)))
        P["fork"] = float(z[kt])
        rm, rd = [], []
        for k in range(kt, n):
            runs = rows[k][1]
            if k < kf:
                gc, gw = np.polyval(mid, k - kf), w0 * (k - kt) / max(kf - kt, 1)
                runs = [(lo[k], gc - gw), (gc + gw, hi[k])]
            runs = sorted(runs, key=lambda r: -r[0])                    # the mesial root first (the drawing's right)
            for q, r in enumerate(runs[:2]):
                cc, aa = (x0 - (r[0] + r[1]) / 2) * kx, (r[1] - r[0]) / 2 * kx
                if len(runs) == 1:                                      # one root left: the one this run continues
                    q = 0 if (not rd or (rm and abs(rm[-1][1] - cc) < abs(rd[-1][1] - cc))) else 1
                (rm if q == 0 else rd).append((z[k], cc, aa))
        P["roots"] = []
        for r in (rm, rd):
            r = np.array(r)[::-1]
            P["roots"].append({"z": r[:, 0].copy(), "c": g(r[:, 1]), "a": np.maximum(g(r[:, 2]), 0.3)})
    if kind == "molar" and arch == "upper":
        # three roots. From the cheek side the drawing's outline is all three together: its two sides are the two
        # cheek-side roots' outer borders, and the palate-side root stands behind the gap between them. Each cheek-side
        # root keeps to its side of the outline, has its own width (half the trunk where they part, a third of it
        # half-way down) and its own tip; the gap between them is narrower in the hinder molars, whose roots draw together.
        zt = (-4.0, -4.5, -6.0)[i - 5]
        kt = int(np.argmin(np.abs(z - zt)))
        P["fork"] = float(z[kt])
        zz, cc, aa = z[kt:], c[kt:], half[kt:]
        L = zz[0] - zz[-1]
        mid = ndimage.gaussian_filter1d(cc, 25.0, mode="nearest")
        P["c0"], P["lean"] = float(cc[0]), float(mid[-1])   # where the root complex's middle is at the fork, and at the tips
        sm = lambda t: (lambda q: q * q * (3 - 2 * q))(np.clip(t, 0, 1))
        P["roots"] = []
        for side, share in ((-1, 0.97), (1, 0.89)):
            keep = (zz[0] - zz) <= L * share
            u = (zz[0] - zz[keep]) / (L * share)
            ar = np.minimum(aa[0] * (0.5 - 0.09 * sm(u / 0.3)) * AT.taper(u, 0.45, 0.9), aa[keep])
            apart = ar + 0.24 * aa[0] * (1.0, 0.7, 0.3)[i - 5] * sm(u / 0.3)
            w = sm((u - 0.45) / 0.3)                             # low down the outline is the three tips together: each root keeps its own line
            cr = (cc[keep] + side * np.maximum(aa[keep] - ar, apart)) * (1 - w) + (mid[keep] + side * apart) * w
            cr = ndimage.gaussian_filter1d(cr, 8.0, mode="nearest")
            P["roots"].append({"z": zz[keep][::-1].copy(), "c": cr[::-1].copy(), "a": np.maximum(ar[::-1], 0.3)})
    _P[arch, i] = P
    return P


class _Now:
    P = None; X = None; Z = None; Y = None; k = 0; R = 0.0; two = False; parts = []


def _shell(X, Y, a_m, a_d, b_o, b_i, p, conv=0.0, cx=0.0, cy=0.0):
    P = _Now.P
    c = np.interp(_Now.Z, P["z"], P["c"]); a = np.interp(_Now.Z, P["z"], P["a"])
    return _OLD[0](X - c, Y, a, a, b_o, b_i, p, conv, cx=0.0, cy=cy)


def _root(X, Y, Z, top, tip, a, b, end=0.36, power=0.9, curve=1.0, bow=(0.0, 0.0), p=2.0):
    P = _Now.P
    k = _Now.k; _Now.k += 1
    if _Now.two:                                            # the upper first premolar: see _forked
        return np.full(np.shape(Z), 9.0)
    if k >= len(P.get("roots", [])):
        if "roots" in P:                                    # an upper molar's palate-side root: it ends level with the drawn outline's tip
            tip = (tip[0] + P["lean"], tip[1], -_Now.R + 0.4); top = (top[0] + P["c0"], top[1], top[2])
        tp, tq = np.asarray(top, float), np.asarray(tip, float)
        u = np.clip((tp[2] - Z) / (tp[2] - tq[2]), 0, 1); w = AT.taper(u, end, power)
        _Now.parts.append((tp[0] + (tq[0] - tp[0]) * u ** curve + bow[0] * np.sin(np.pi * u), a * w,
                           tp[1] + (tq[1] - tp[1]) * u ** curve + bow[1] * np.sin(np.pi * u), b * w))
        return _OLD[1](X, Y, Z, top, tip, a, b, end, power, curve, bow, p)
    T = P["roots"][k]
    c = np.interp(Z, T["z"], T["c"]); aa = np.interp(Z, T["z"], T["a"])
    u = np.clip((T["z"][-1] - Z) / (T["z"][-1] - T["z"][0]), 0, 1)
    bb = b * AT.taper(u, 0.42, 0.9)
    yc = top[1] + (tip[1] - top[1]) * u ** curve
    _Now.parts.append((c, aa, yc, bb))
    yy = Y - yc
    rho = ((np.abs(X - c) / aa) ** p + (np.abs(yy) / bb) ** p) ** (1.0 / p)
    d = (rho - 1) * np.minimum(aa, bb)
    under = T["z"][0] - Z; r_end = float(T["a"][0])
    return np.where(under > 0, np.sqrt((rho * r_end) ** 2 + under ** 2) - r_end, d)


def _forked(trunk, roots, Z, zf):
    if _Now.two:
        # the upper first premolar's two roots stand one behind the other from this side: the drawn outline is their
        # common one, and the cleft between them shows from in front, running up from the tips
        R = _Now.R
        body = AT.closed(trunk, Z, R, 0.6)
        cleft = np.abs(_Now.Y) - 0.30 * (6.5 - R - Z)
        return AT.smax(body, -cleft, 0.5)
    if "roots" in _Now.P:
        # traced roots. Where they part the tooth is still one solid with the outline of the trunk; the gap between the
        # roots opens in it as a cleft that widens downward (a second cleft, across, parts the palate-side root of an
        # upper molar from the two on the cheek side), and within 2.5 mm the two or three limbs have become the roots
        zf = _Now.P["fork"]; X, Y = _Now.X, _Now.Y
        (x0, a0, y0, b0), (x1, a1, y1, b1) = _Now.parts[0], _Now.parts[1]
        cleft = np.maximum((x0 + a0) - X, X - (x1 - a1))
        if len(_Now.parts) > 2:
            x2, a2, y2, b2 = _Now.parts[2]
            cleft = np.maximum(cleft, (y2 + 0.3 * b2) - Y)
            cleft = np.minimum(cleft, np.maximum((y2 + b2) - Y, Y - np.minimum(y0 - b0, y1 - b1)))
        cleft = np.maximum(cleft, Z - zf)
        solid = AT.smax(trunk, -cleft, 0.4)
        w = np.clip((zf - Z) / 2.5, 0, 1); w = w * w * (3 - 2 * w)
        return np.where(Z >= zf, trunk, solid * (1 - w) + roots * w)
    return _OLD[2](trunk, roots, Z, zf)


def _once(arch, i, X, Y, Z):
    _Now.X, _Now.Z, _Now.Y, _Now.k, _Now.parts = X, Z, Y, 0, []
    return AT.field(arch, i, X, Y, Z)


def field(arch, i, X, Y, Z):
    """Negative inside tooth i of the arch (about the distance to its surface in mm)."""
    X, Y, Z = np.broadcast_arrays(X, Y, Z)
    _Now.P, _Now.R, _Now.two = profile(arch, i), ARCHES[arch][i][4], (arch == "upper" and i == 3)
    AT.shell, AT.root, AT.forked = _shell, _root, _forked
    try:
        F = _once(arch, i, X, Y, Z)
        w = np.exp(-(Z / 1.6) ** 2)                         # round the neck: the crown swells out of the root, with no ledge
        if (w > 0.02).any():
            soft = (_once(arch, i, X, Y, Z - 0.45) + 2 * F + _once(arch, i, X, Y, Z + 0.45)) / 4
            F = F * (1 - w) + soft * w
        return F
    finally:
        AT.shell, AT.root, AT.forked = _OLD


def tooth(arch, i, h=0.15, triangles=40000):
    """Tooth i of the arch in its own frame (mm): vertices, triangles (outward)."""
    if (arch, i, h, triangles) in _cache:
        return _cache[arch, i, h, triangles]
    from skimage import measure
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    P = profile(arch, i)
    xs = [P["c"] - P["a"], P["c"] + P["a"]] + [q for r in P.get("roots", []) for q in (r["c"] - r["a"], r["c"] + r["a"])]
    lo = np.array([min(q.min() for q in xs) - 1.6, -B / 2 - 3.6, -R - 2.6])
    hi = np.array([max(q.max() for q in xs) + 1.6, B / 2 + 2.6, H + 1.4])
    ax = [np.arange(lo[k], hi[k] + h, h) for k in range(3)]
    X, Y, Z = np.meshgrid(*ax, indexing="ij")
    F = field(arch, i, X, Y, Z)
    v, f, _, _ = measure.marching_cubes(F, 0.0, spacing=(h, h, h))
    v = v + lo
    f = f[:, ::-1].astype(np.int64)
    if np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum() < 0:
        f = f[:, ::-1]
    v = AT.taubin(v, f, 6)
    if len(f) > triangles:
        import fast_simplification
        q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - triangles / len(f), agg=4)
        used = np.unique(g); remap = np.full(len(q), -1, np.int64); remap[used] = np.arange(len(used))
        v, f = q[used].astype(np.float64), remap[g].astype(np.int64)
    _cache[arch, i, h, triangles] = (v, f)
    return v, f


if __name__ == "__main__":
    for arch in ("upper", "lower"):
        for i in range(8):
            key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
            P = profile(arch, i)
            neck = 2 * float(np.interp(0.0, P["z"], P["a"]))
            print("%s %-16s mm per pixel: across %.3f, along %.3f   neck width %.1f (textbook %.1f)%s"
                  % (arch, key, *P["mm_per_px"], neck, Wc,
                     "  roots part at z %.1f" % P["fork"] if "fork" in P else ""))
            for r in P.get("roots", []):
                q = np.linspace(r["z"][-1], r["z"][0], 6)
                print("      root: " + "  ".join("z %.1f x %.1f to %.1f" % (zq, np.interp(zq, r["z"], r["c"]) - np.interp(zq, r["z"], r["a"]), np.interp(zq, r["z"], r["c"]) + np.interp(zq, r["z"], r["a"])) for zq in q))
