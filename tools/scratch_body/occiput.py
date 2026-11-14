"""occiput.py: the outer relief of the occipital bone, pressed into the braincase's own surface.

A real occipital bone has no ridges laid on it. Below the outer protuberance the neck's muscles each leave a
shallow hollow, and the nuchal lines and the crest are what stands between the hollows. So that is how it is
made here: the areas Gray's Fig. 187 rings (traced from the plate's ink by trace_occiput.py) are sunk a
millimetre or so into the surface with soft floors, a low lip is left round each, and the protuberance is a
low swelling where the lines meet. Nothing is added as a solid of its own: the skull's surface itself is moved
in or out along its normal, so the relief runs out into the bone with no seam.

The map the relief is drawn on looks at the bone from below and behind (40 degrees), so the plane the neck's
muscles hold is seen nearly face on. The plate is a view from straight below: each traced point is carried
straight up on to this skull's own under surface and then into the map.
"""
import json, os
import numpy as np
from scipy import ndimage
import relief, plates, base

TILT = np.radians(40.0)
ST, CT = float(np.sin(TILT)), float(np.cos(TILT))
PLATE_OPISTHION_Z, PLATE_INION_Z = -34.5, -77.4          # where the plate has the back of the great opening and the protuberance (mm, plates.base_mm)

# name: (depth of the hollow, how far in from its edge the floor is reached, height of the lip left round it), mm
AREAS = {
    "semispinalis capitis": (1.2, 7.0, 0.55),
    "rectus capitis posterior minor": (0.7, 4.5, 0.4),
    "rectus capitis posterior major": (0.55, 3.5, 0.25),
    "obliquus capitis superior": (0.55, 4.5, 0.25),
}
# the superior nuchal line: the middle of the strip on which the plate rings trapezius, sternocleidomastoid and splenius (page pixels)
SUP_LINE = [(1356, 3335), (1260, 3325), (1173, 3305), (1080, 3270), (990, 3232), (900, 3190), (809, 3145), (735, 3100),
            (670, 3040), (610, 2975), (560, 2900), (515, 2820), (480, 2740)]


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def to_map(x, y, z):
    return np.abs(x), y * ST - z * CT


def build(F, inion, opisthion_z=-34.5, log=print):
    """Press the relief into the field F (the skull's left half, before its hollows are cut). inion: the point of
    the outer protuberance on this skull's surface. Returns the map and the relief (mm, + outward) for checks."""
    if F.window((0.0, -50.0, float(F.ax[2][0])), (68.0, 26.0, -16.0)) is None:      # a block built without the back of the head
        return None, None
    here = os.path.dirname(os.path.abspath(__file__))
    T = json.load(open(os.path.join(here, "occiput_traced.json")))["areas"]
    yu = base.underside(F.D, F)
    xs, zs = np.asarray(F.ax[0], float), np.asarray(F.ax[2], float)
    k = (inion[2] - opisthion_z) / (PLATE_INION_Z - PLATE_OPISTHION_Z)

    def on_skull(page):
        """page pixels -> (x, y, z) on this skull's under surface"""
        q = plates.base_mm(np.asarray(page, float))
        x, z = q[:, 0], opisthion_z + (q[:, 1] - PLATE_OPISTHION_Z) * k
        z = np.maximum(z, inion[2] + 0.3 * (z - inion[2]))                 # nothing is carried past the protuberance's own level
        i = np.clip((x - xs[0]) / F.h, 0, len(xs) - 1.001); j = np.clip((z - zs[0]) / F.h, 0, len(zs) - 1.001)
        y = ndimage.map_coordinates(np.nan_to_num(yu, nan=0.0), [i, j], order=1, mode="nearest")
        return np.column_stack([x, y, z])

    M = relief.Map(-2.0, 68.0, -10.0, 84.0, 0.5)
    rng = np.random.default_rng(187)
    slow = ndimage.gaussian_filter(rng.standard_normal(M.U.shape), 12.0); slow /= slow.std()      # nothing in a body is ruled: the lips rise and fall along their length
    fine = ndimage.gaussian_filter(rng.standard_normal(M.U.shape), 5.0); fine /= fine.std()
    H = np.zeros(M.U.shape); lip = np.zeros(M.U.shape)
    # a hollow keeps no lip on the side that faces the great opening: the bone there runs level into the opening's edge
    away = smoothstep((np.hypot(M.U, M.V - (-27.0 * ST - opisthion_z * CT)) - 11.0) / 9.0)
    for name, (depth, soft, rim) in AREAS.items():
        P = on_skull(T[name])
        u, v = to_map(P[:, 0], P[:, 1], P[:, 2])
        reg = M.region(np.column_stack([u, v]))
        H -= depth * smoothstep(-reg / soft) * (1.0 + 0.12 * fine)
        lip = np.maximum(lip, rim * np.exp(-((reg - 1.2) / 2.6) ** 2) * away)
        log("occiput: %-32s x %.0f to %.0f, y %.0f to %.0f, z %.0f to %.0f; hollow %.1f mm" % (
            name, P[:, 0].min(), P[:, 0].max(), P[:, 1].min(), P[:, 1].max(), P[:, 2].min(), P[:, 2].max(), depth))
    # the superior nuchal line: a broad low swell along the traced strip, highest in its inner third
    L = on_skull(SUP_LINE); L[0] = inion
    lu, lv = to_map(L[:, 0], L[:, 1], L[:, 2])
    s = np.concatenate([[0], np.cumsum(np.hypot(np.diff(lu), np.diff(lv)))])
    ss = np.arange(0, s[-1], 0.25); pu, pv = np.interp(ss, s, lu), np.interp(ss, s, lv)
    from scipy.spatial import cKDTree
    d, i = cKDTree(np.column_stack([pu, pv])).query(np.column_stack([M.U.ravel(), M.V.ravel()]))
    d = d.reshape(M.U.shape); along = (ss[i] / ss[-1]).reshape(M.U.shape)
    above = (M.V > np.interp(M.U, lu, lv))                                  # the side toward the crown: there the swell falls away slowly
    swell = np.interp(along, [0, 0.15, 0.55, 1.0], [1.0, 0.95, 0.7, 0.35]) * np.exp(-(d / np.where(above, 4.5, 2.2)) ** 2)
    lip = np.maximum(lip, 0.75 * swell)
    # the crest down the midline from the protuberance to the great opening, lower toward the opening
    vi = inion[1] * ST - inion[2] * CT; vo = -27.0 * ST - opisthion_z * CT
    t = np.clip((M.V - vo) / (vi - vo), 0, 1)
    crest = (0.6 + 0.8 * t ** 1.5) * np.exp(-(M.U / 1.9) ** 2) * smoothstep((M.V - vo - 1.0) / 4.0) * (M.V < vi + 2)
    lip = np.maximum(lip, crest)
    H += lip * (1.0 + 0.28 * slow)
    # the protuberance: a low swelling where the lines meet, a little beaked toward the neck
    H += 2.1 * np.exp(-(M.U / 8.5) ** 2 - ((M.V - vi + 1.0) / np.where(M.V > vi - 1.0, 4.0, 5.5)) ** 2)
    H = ndimage.gaussian_filter(H, 2.6)
    # ---- press it into the surface: each point of the field takes the relief of the surface point under it
    sl = F.window((0.0, -50.0, float(F.ax[2][0])), (68.0, 26.0, -16.0))
    X, Y, Z = np.broadcast_arrays(*F.coords(sl))
    D = F.D[sl].astype(np.float32)
    Ds = ndimage.gaussian_filter(D, 2.5)                                    # the way down to the surface is read off a smoothed field: no creases carried into the relief
    g = np.gradient(Ds, F.h)
    n = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6
    t = Ds / (n * n)
    x0, y0, z0 = X - t * g[0], Y - t * g[1], Z - t * g[2]
    u, v = to_map(x0, y0, z0)
    h = M.smooth_sample(M.smooth(H), u, v)
    facing = -(g[1] * CT + g[2] * ST) / n                                   # the surface looks toward the map's eye
    w = (1 - smoothstep((np.abs(D) - 3.0) / 3.0)) * (1 - smoothstep((Y - 14.0) / 8.0)) * smoothstep((facing + 0.05) / 0.3) * (M.outside(u, v) < -1.0)
    F.D[sl] = D - h * w * np.clip(n, 0.6, 1.8)
    log("occiput: relief from %.2f to %.2f mm pressed into the surface (protuberance at %s)" % (H.min(), H.max(), np.round(inion, 1).tolist()))
    return M, H
