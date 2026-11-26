"""view.py: plain check pictures of the from-scratch bones (our own renderer, nothing imported).

picture(meshes, eye, size) -> PIL image: an orthographic view, bone-coloured on the dark ground,
shaded with one light and a soft darkening of hollows so that orbits, notches and foramina read.
sheet(rows, path, title) lays pictures out with captions, optionally beside a reference plate.
Frame: x = the body's left, y up, z forward. `eye` is the direction from the subject to the camera.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
import surface

BONE = (226, 214, 190)
BG = (22, 24, 28)
VIEWS = {"front": (0, 0, 1), "left side": (1, 0, 0), "back": (0, 0, -1), "top": (0, 1, 0), "below": (0, -1, 0),
         "right side": (-1, 0, 0), "three-quarter": (0.6, 0.25, 0.75)}


def normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, f[:, k], n)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-15)


def sample(v, f, spacing):
    """Points spread over the surface about `spacing` apart, with smooth normals."""
    vn = normals(v, f)
    a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    k = np.maximum(np.ceil(area / (0.5 * spacing ** 2)).astype(int), 1)
    idx = np.repeat(np.arange(len(f)), k)
    rng = np.random.default_rng(7)
    r1, r2 = np.sqrt(rng.random(len(idx))), rng.random(len(idx))
    w = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], axis=1)
    P = w[:, :1] * a[idx] + w[:, 1:2] * b[idx] + w[:, 2:] * c[idx]
    N = w[:, :1] * vn[f[idx, 0]] + w[:, 1:2] * vn[f[idx, 1]] + w[:, 2:] * vn[f[idx, 2]]
    P = np.concatenate([P, v]); N = np.concatenate([N, vn])
    return P, N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-15)


# ---- dry bone: what makes a picture read as bone and not as clay. The bone's own channels (colour, roughness, how many
# fine pores, which way its grain runs) are per vertex (surface.vertex_attrs: what the app's mesh carries too); what is finer
# than the mesh is worked out here at every point of the picture from the point's place on the bone, as the app's shader
# must: the fine pores (0.17 to 0.5 mm, 25 to 120 per cm2), the fibre-like grain along the bone's long way, and a broad
# soft sheen whose width follows the roughness. All of it hashed from the place, so it stays put when the view turns.
TEXTURE = True
_ATTRS = {}
PORE_CELL = 0.7          # mm: the pores' lattice (one in four cells or fewer carries one)


def attrs(v, f):
    """surface.vertex_attrs for a mesh, kept for the next picture of the same mesh."""
    key = (len(v), len(f), np.asarray(v[:: max(1, len(v) // 61)], np.float32).tobytes())
    if key not in _ATTRS:
        if len(_ATTRS) > 6:
            _ATTRS.clear()
        _ATTRS[key] = surface.vertex_attrs(v, f)
    return _ATTRS[key]


def pores(P, N, T, dens, s=50.0, seed=500, coh=None):
    """How dark each point is from the fine pores round it (0..1): seeds hashed in a 3D lattice of PORE_CELL mm, each kept
    where the surface passes within half a cell of it and the density (per cm2) asks for it. (repair 2) On flat bone a
    pin-prick: nearly round (aspect 1 to 1.9, median about 1.2), turned any way at random, 0.10 to 0.42 mm across (lognormal,
    median 0.18, p90 0.30), the small ones faint and only the largest tenth dark. Only where the grain's way is sure
    (coh over 0.75: a ridge, a border) do they line up with it and draw out further (to 2.5)."""
    c = PORE_CELL; lam = np.clip(dens, 0, None) / 100.0 * c * c            # how many a cell's slab of surface carries
    base = np.floor(P / c).astype(np.int64)
    dark = np.zeros(len(P))
    md, sd, dmin, dmax = surface.PORE_D
    ali = np.zeros(len(P)) if coh is None else surface.smoothstep((np.asarray(coh, float) - 0.75) / 0.15)
    Bt = np.cross(N, T)
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for oz in (-1, 0, 1):
                C = base + np.array([ox, oy, oz])
                for m in range(2):
                    s0 = seed + 16 * m
                    u = [surface.uniform(C[:, 0], C[:, 1], C[:, 2], s0 + k) for k in range(7)]
                    if u[0].min() >= 0.5 * lam.max():
                        continue
                    q = (C + np.stack(u[1:4], 1)) * c
                    d = P - q; dn = (d * N).sum(1)
                    live = (u[0] < 0.5 * lam) & (np.abs(dn) < 0.5 * c)
                    if not live.any():
                        continue
                    th = 2 * np.pi * u[6]
                    Dr = (1 - ali)[:, None] * (np.cos(th)[:, None] * T + np.sin(th)[:, None] * Bt) + ali[:, None] * T
                    Dr /= np.maximum(np.linalg.norm(Dr, axis=1, keepdims=True), 1e-9)
                    dt = d - dn[:, None] * N; al = (dt * Dr).sum(1)
                    e = 1.0 + (0.9 + 0.6 * ali) * u[5] ** 2                  # round to short flecks; a little longer on ridges
                    dia = np.clip(md * np.exp(sd * np.sqrt(2) * _erfinv(2 * u[4] - 1)), dmin, dmax)
                    rad = 0.5 * dia
                    con = 0.17 + 0.33 * surface.smoothstep((dia - 0.24) / 0.1)         # the small ones faint (8 to 12 L*), the largest tenth dark (about 25)
                    rho = np.sqrt(np.maximum((dt * dt).sum(1) - al * al, 0) + (al / e) ** 2)
                    w = np.clip(1.0 - (rho / (rad + 0.25 / s)) ** 2, 0, 1) * np.minimum(1.0, (2 * rad * s) ** 2)   # a funnel, darkest at its foot
                    dark = np.maximum(dark, np.where(live, w * con, 0.0))
    return dark


def _erfinv(x):
    a = 0.147; ln = np.log(np.maximum(1 - x * x, 1e-12)); t = 2 / (np.pi * a) + ln / 2
    return np.sign(x) * np.sqrt(np.sqrt(t * t - ln / a) - t)


def bone(P, N, s, A=None):
    """Colour (0..255), the normal as the light meets it and the roughness, for dry bone at points P (mm) with smooth normals N
    and the bone's per-vertex channels A there (rgb, rough, pores, tangent, coh). Without A: the channels read off the
    place alone (surface.point_attrs: no grooves or seams), and only the colour and the normal are returned.
    s: pixels per mm of the picture (what is finer than a pixel is left to the colour's mean: it would only be speckle)."""
    def show(wave):
        return float(np.clip((wave * s - 1.3) / 2.0, 0.0, 1.0))
    loose = A is None
    if loose:
        A = surface.point_attrs(P, N)
    col = A["rgb"].astype(np.float32)
    T = A["tangent"]; T = T - (T * N).sum(1, keepdims=True) * N; T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    c = A["coh"][:, None]
    Nb = N.astype(np.float32).copy()
    smooth = np.clip((A["rough"] - 0.38) / 0.12, 0.25, 1.0)[:, None]          # the joint surfaces' grain is a quarter of the rest's
    # the fibre-like grain: 0.01 to 0.03 mm high, 0.3 to 1 mm across, drawn out five times along the grain where its way is known
    # (three copies drawn out along the head frame's axes, mixed by how the grain's way lies along each: no seams)
    for wave, seed, amp in ((2.6, 21, 0.014), (1.0, 22, 0.018), (0.45, 23, 0.011)):
        k = show(wave)
        if k > 0:
            _, gi = surface.vnoise(P, wave, seed, grad=True)
            ga = sum((T[:, j:j + 1] ** 2) * surface.vnoise(P, wave * 0.8, seed + 10 + j, stretch=(j, 5.0), grad=True)[1] for j in range(3))
            g = (1 - c) * gi + c * ga
            g = g - (g * N).sum(1, keepdims=True) * N
            Nb -= (k * amp) * smooth * g
    k = show(0.3)
    if k > 0:
        dk = pores(P, N, T, A["pores"], s, coh=A["coh"])
        col *= (1.0 - k * dk)[:, None]
    Nb /= np.maximum(np.linalg.norm(Nb, axis=1, keepdims=True), 1e-9)
    return (col, Nb) if loose else (col, Nb, A["rough"])


def camera(eye):
    eye = np.asarray(eye, float); eye = eye / np.linalg.norm(eye)
    up = np.array([0, 0, 1.0]) if abs(eye[1]) > 0.98 else np.array([0, 1.0, 0])
    right = np.cross(up, eye); right /= np.linalg.norm(right)
    return eye, right, np.cross(eye, right)


LIGHT = (0.16, 0.66, 0.2, 0.55)      # ambient, key light, fill light, how far the edges fall away
DIST = None          # the eye's distance (mm) from the middle of what is drawn; None: no perspective (parallel lines of sight)
SUPER = int(os.environ.get("SCRATCH_SUPER", "1"))      # each picture drawn this many times larger and brought down (finer grain, cleaner edges)
                     # the fine mottling they give real bone at arm's length, instead of being left out


def picture(meshes, eye, size=760, frame=None, pad=0.05, hollow=1.0, dist=None, _whole=True):
    """meshes: [(v, f, rgb)] in any one unit, each a closed surface with its faces wound outward.
    frame: (centre, span) to hold several pictures to one scale.
    dist: the eye's distance from the centre (mm). A skull photographed or drawn from in front is seen from under a metre
    away: what lies further back (the jaw's angles, the back of the head) comes out smaller, as in every plate and photograph."""
    if _whole and SUPER > 1:
        big = picture(meshes, eye, size * SUPER, frame, pad, hollow, dist, _whole=False)
        return big.resize((size, size), Image.LANCZOS)
    eye, right, up = camera(eye)
    dist = DIST if dist is None else dist
    allv = np.concatenate([m[0] for m in meshes])
    c3 = (allv.max(0) + allv.min(0)) / 2 if frame is None else np.asarray(frame[0], float)
    cam = None if not dist else c3 + dist * eye

    def proj(P):
        """Where a point falls on the picture (mm, at the scale of the centre's depth) and its depth toward the eye."""
        d = np.asarray(P, np.float64) - c3
        x, y, z = d @ right, d @ up, d @ eye
        if dist:
            k = dist / np.maximum(dist - z, 0.2 * dist); x, y = x * k, y * k
        return x, y, z
    X, Y, Zd = proj(allv)
    if frame is None:
        span = max(np.ptp(X), np.ptp(Y)) * (1 + 2 * pad)
        cx, cy = (X.max() + X.min()) / 2, (Y.max() + Y.min()) / 2
    else:
        span = frame[1]; cx = cy = 0.0
    near = 1.0 if not dist else float(dist / max(dist - Zd.max(), 0.2 * dist))
    del X, Y, Zd
    s = size / span
    img = np.zeros((size * size, 3), np.float32) + np.array(BG, np.float32)
    zb = np.full(size * size, -np.inf)
    nb = np.zeros((size * size, 3), np.float32)          # the surface's normal at each picture point (right, up, toward the eye)
    who = np.full(size * size, -1, np.int64)             # which mesh each picture point shows,
    Pb = np.zeros((size * size, 3), np.float32)          # and the point of it that is seen there, with its normal
    Nw = np.zeros((size * size, 3), np.float32)
    Vb = np.zeros((size * size, 3), np.int32)           # and the triangle's corners and their weights there (for the per-vertex channels)
    Wb = np.zeros((size * size, 3), np.float32)
    light = 0.35 * right + 0.55 * up + 0.75 * eye; light /= np.linalg.norm(light)
    fill = -0.5 * right + 0.2 * up + 0.6 * eye; fill /= np.linalg.norm(fill)
    spacing = 0.8 / (s * near)
    rng = np.random.default_rng(7)
    for m, (v, f, col) in enumerate(meshes):
        vn = normals(v, f).astype(np.float32)
        a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
        fn = np.cross(b - a, c - a)
        cc = (a + b + c) / 3.0
        keep = (fn @ eye > 0) if cam is None else (((cam - cc) * fn).sum(1) > 0)      # a closed surface shows only the faces turned toward the eye
        if frame is not None:                           # a close-up: only the triangles in the picture are sampled
            qx, qy, _ = proj(cc); qx = (qx - cx) * s + size / 2; qy = size / 2 - (qy - cy) * s
            mg = 0.12 * size
            keep &= (qx > -mg) & (qx < size + mg) & (qy > -mg) & (qy < size + mg)
        f = f[keep]
        if not len(f):
            continue
        k = np.maximum(np.ceil(0.5 * np.linalg.norm(fn[keep], axis=1) / (0.5 * spacing ** 2)).astype(np.int64), 1)
        del a, b, c, fn, keep, cc
        cuts = np.searchsorted(np.cumsum(k), np.arange(2_000_000, int(k.sum()), 2_000_000))        # a couple of million points at a time
        for fc, kc in zip(np.split(f, cuts), np.split(k, cuts)):
            if not len(fc):
                continue
            idx = np.repeat(np.arange(len(fc)), kc)
            r1, r2 = np.sqrt(rng.random(len(idx), dtype=np.float32)), rng.random(len(idx), dtype=np.float32)
            w0, w1, w2 = (1 - r1)[:, None], (r1 * (1 - r2))[:, None], (r1 * r2)[:, None]
            g = fc[idx]
            P = (w0 * v[g[:, 0]] + w1 * v[g[:, 1]] + w2 * v[g[:, 2]]).astype(np.float32)
            N = w0 * vn[g[:, 0]] + w1 * vn[g[:, 1]] + w2 * vn[g[:, 2]]
            W = np.concatenate([w0, w1, w2], 1)
            del idx, r1, r2, w0, w1, w2
            qx, qy, pz = proj(P)
            px = np.floor((qx - cx) * s + size / 2).astype(np.int32)
            py = np.floor(size / 2 - (qy - cy) * s).astype(np.int32)
            del qx, qy
            order = np.argsort(pz)
            px, py, pz = px[order], py[order], pz[order]
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                x, y = px + dx, py + dy
                ok = (x >= 0) & (x < size) & (y >= 0) & (y < size)
                i = y[ok].astype(np.int64) * size + x[ok]
                near = pz[ok] > zb[i]
                i = i[near]; src = order[ok][near]
                zb[i] = pz[ok][near]                    # sorted far to near: the last written is the nearest
                who[i] = m; Pb[i] = P[src]; Nw[i] = N[src]; Vb[i] = g[src]; Wb[i] = W[src]
    for m, (v, f, col) in enumerate(meshes):            # only what is seen is coloured and lit
        pix = np.where(who == m)[0]
        if not len(pix):
            continue
        P = Pb[pix].astype(np.float64); N = Nw[pix].astype(np.float64)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
        dry = TEXTURE and tuple(col) == BONE
        if dry:
            At = attrs(v, f); Vi, Wi = Vb[pix], Wb[pix]
            A = {nm: sum(Wi[:, j:j + 1] * At[nm][Vi[:, j]].reshape(len(pix), -1).astype(np.float32) for j in range(3)).reshape((len(pix),) + At[nm].shape[1:])
                 for nm in ("rgb", "rough", "pores", "tangent", "coh")}
            col, N, rough = bone(P, N, s, A)
        am, key, fl, edge = LIGHT
        sh = am + key * np.clip(N @ light, 0, 1) ** 1.1 + fl * np.clip(N @ fill, 0, 1)
        sh = sh * np.clip(edge + (1 - edge) * np.clip(N @ eye, 0, 1) ** 0.5, 0, 1)      # edges fall away a little
        img[pix] = sh[:, None] * np.asarray(col, np.float32)
        if dry:
            # dry bone is matt but not chalk: where it faces half-way between the light and the eye it gives back a faint, broad sheen,
            # and the grain breaks that sheen up. It is by this broken sheen that the eye reads a surface as bone and not as clay.
            # How broad follows the roughness (Blinn's exponent from it): narrower and a little brighter on the smooth plates and
            # the joint surfaces, broad and faint on the porous and rough bone.
            hv = light + eye; hv = hv / np.linalg.norm(hv)
            r_ = np.asarray(rough, np.float64); ex = 4.0 / (r_ * r_) - 2.0
            img[pix] += ((9.0 + 15.0 * np.clip(0.62 - r_, 0, None)) * np.clip(N @ hv, 0, 1) ** ex)[:, None] * np.array([1.0, 0.98, 0.94], np.float32)
        nb[pix] = np.column_stack([N @ right, N @ up, N @ eye]).astype(np.float32)
    zb = zb.reshape(size, size); img = img.reshape(size, size, 3); nb = nb.reshape(size, size, 3)
    got = np.isfinite(zb)
    if got.any() and hollow > 0:
        occ = occlusion(zb, nb, got, s)
        dark = 1 - hollow * occ[:, :, None] * (np.array([0.85, 0.89, 0.94], np.float32) if TEXTURE else 0.88)   # what little light reaches a crease comes back warm: dirt lies there
        # a hole narrower than it is deep is dark however its floor is turned: light does not get down it. How deep each point
        # lies below the surface round it, for holes up to 12 mm and up to 26 mm across
        zf = np.where(got, zb, zb[got].min() - 1.0).astype(np.float32)
        for across, soft in ((12.0, 6.0), (26.0, 28.0)):
            w = int(across * s) | 1
            if 5 <= w <= size // 2:
                deep = ndimage.gaussian_filter(ndimage.grey_closing(zf, size=(w, w)) - zf, max(1.0, 0.03 * w))
                dark *= (1.0 / (1.0 + hollow * deep / soft))[:, :, None]
        img *= dark * got[:, :, None] + (~got)[:, :, None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def occlusion(zb, nb, got, s):
    """How much of the open sky each picture point has lost to the surface round it (0 none, 1 all): a hole is dark
    inside and a pit darker the deeper it is, while a flat slope keeps its light. At each point the surface is looked
    at in rings of 1 to 24 mm: whatever stands above the point's own tangent plane takes light away, and a ring that
    is shut all round (the rim of a deep hole) takes nearly all of it, however far away that rim is.
    zb: depth toward the eye (mm), nb: normals (right, up, eye), s: pixels per mm."""
    size = zb.shape[0]
    z = np.where(got, zb, -1e9).astype(np.float32)
    open_sky = np.ones(zb.shape, np.float32)
    for ring, (r_mm, wgt) in enumerate(((0.8, 0.5), (1.6, 0.6), (3.0, 0.7), (5.5, 0.7), (10.0, 0.6), (16.0, 0.45), (24.0, 0.3))):
        r = r_mm * s
        if r < 1.5 or r > 0.45 * size:
            continue
        occ = np.zeros(zb.shape, np.float32)
        for a in np.radians(np.arange(0, 360, 22.5) + 11.25 * (ring % 2)):
            dx, dy = int(round(r * np.cos(a))), int(round(r * np.sin(a)))
            zq = np.full(z.shape, -1e9, np.float32)
            ys, yd = (slice(max(dy, 0), size + min(dy, 0)), slice(max(-dy, 0), size + min(-dy, 0)))
            xs, xd = (slice(max(dx, 0), size + min(dx, 0)), slice(max(-dx, 0), size + min(-dx, 0)))
            zq[yd, xd] = z[ys, xs]                           # the surface dx to the right and dy down from each point
            vx, vy, vz = dx / s, -dy / s, zq - z
            c = (vx * nb[..., 0] + vy * nb[..., 1] + vz * nb[..., 2]) / np.sqrt(vx * vx + vy * vy + vz * vz)
            occ += np.clip(c - 0.1, 0.0, 1.0) * (zq > -1e8)
        open_sky *= 1.0 - wgt * np.clip(1.5 * ndimage.gaussian_filter(occ / 16.0, max(1.0, 0.2 * r)), 0.0, 1.0)   # (blurred: sixteen looks a ring would show as tiles)
    return (1.0 - open_sky) * got


def font(px):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"):
        try:
            return ImageFont.truetype(p, px)
        except OSError:
            pass
    return ImageFont.load_default()


def sheet(rows, path, title=None, cell=None):
    """rows: [[(image, caption), ...], ...] -> one picture."""
    f1, f2 = font(15), font(20)
    cw = cell or max(im.size[0] for r in rows for im, _ in r)
    ch = max(im.size[1] for r in rows for im, _ in r)
    top = 40 if title else 8
    W = cw * max(len(r) for r in rows) + 8; H = top + (ch + 26) * len(rows) + 8
    out = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(out)
    if title:
        d.text((12, 10), title, fill=(235, 235, 235), font=f2)
    for j, r in enumerate(rows):
        for i, (im, cap) in enumerate(r):
            if im.size[1] != ch or im.size[0] > cw:
                k = min(cw / im.size[0], ch / im.size[1]); im = im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)
            x, y = 4 + i * cw + (cw - im.size[0]) // 2, top + j * (ch + 26)
            out.paste(im.convert("RGB"), (x, y))
            d.text((4 + i * cw + 8, y + ch + 4), cap, fill=(200, 200, 200), font=f1)
    out.save(path)
    return path
