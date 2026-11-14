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


# ---- dry bone: what makes a picture read as bone and not as clay. None of it is geometry: it is colour and the way the
# surface takes the light, worked out at every point of the picture from the point's place on the bone (so it stays put
# when the view turns). A dried skull is ivory, unevenly stained toward yellow-brown; its surface is matt and finely
# grained, never polished; it is pricked with pores, more of them in patches; and dirt sits in every crease.
TEXTURE = True
_VOL = {}


def _volume(seed, n=128):
    if seed not in _VOL:
        v = ndimage.gaussian_filter(np.random.default_rng(seed).standard_normal((n, n, n)).astype(np.float32), 1.0, mode="wrap")
        v /= float(v.std())
        _VOL[seed] = (v, [((np.roll(v, -1, k) - np.roll(v, 1, k)) * 0.5).astype(np.float32) for k in range(3)])
    return _VOL[seed]


def _turn(seed):
    """A fixed turn of space, so that no two layers of noise repeat along the same lines."""
    q, _ = np.linalg.qr(np.random.default_rng(1000 + seed).standard_normal((3, 3)))
    return q.astype(np.float32)


def noise(P, wave, seed, grad=False):
    """Smooth noise of unit spread whose blobs are about `wave` mm across, at points P (mm); with grad, its slope per mm too."""
    v, g = _volume(seed)
    R = _turn(seed); cell = wave / 4.0
    q = ((np.asarray(P, np.float32) @ R) / cell).T
    val = ndimage.map_coordinates(v, q, order=1, mode="grid-wrap")
    if not grad:
        return val
    gq = np.stack([ndimage.map_coordinates(gk, q, order=1, mode="grid-wrap") for gk in g], 1) / cell
    return val, gq @ R.T


def bone(P, N, s):
    """Colour (0..255) and the normal as the light meets it, for dry bone at points P (mm) with smooth normals N.
    s: pixels per mm of the picture (grain finer than a pixel is left out: it would only be speckle)."""
    def show(wave):
        return float(np.clip((wave * s - 1.3) / 2.0, 0.0, 1.0))
    pale = np.array([240, 231, 208], np.float32); stain = np.array([203, 176, 132], np.float32)
    w = 0.30 + 0.20 * noise(P, 38.0, 11) + 0.11 * noise(P, 9.0, 12) + 0.06 * show(2.2) * noise(P, 2.2, 13)
    w = np.clip(w, 0.0, 1.0)
    col = pale + (stain - pale) * w[:, None]
    Nb = N.astype(np.float32).copy()
    for wave, seed, amp in ((2.6, 21, 0.012), (1.0, 22, 0.014), (0.42, 23, 0.011)):        # grain: height in mm of each layer
        k = show(wave)
        if k > 0:
            f, g = noise(P, wave, seed, grad=True)
            g = g - (g * N).sum(1, keepdims=True) * N
            Nb -= (k * amp) * g
    k = show(0.42)
    if k > 0:                                                                              # pores: dark pricks, thick in some patches and thin in others
        f = noise(P, 0.34, 31)
        patch = np.clip(0.45 + 0.4 * noise(P, 7.0, 32) + 0.3 * noise(P, 21.0, 33), 0.0, 1.0)      # most of the bone has few; they gather in fields
        pore = np.clip((f - (2.75 - 1.15 * patch * patch)) / 0.4, 0.0, 1.0)
        col *= (1.0 - 0.34 * k * pore)[:, None]
    Nb /= np.maximum(np.linalg.norm(Nb, axis=1, keepdims=True), 1e-9)
    return col, Nb


def camera(eye):
    eye = np.asarray(eye, float); eye = eye / np.linalg.norm(eye)
    up = np.array([0, 0, 1.0]) if abs(eye[1]) > 0.98 else np.array([0, 1.0, 0])
    right = np.cross(up, eye); right /= np.linalg.norm(right)
    return eye, right, np.cross(eye, right)


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
            del g, idx, r1, r2, w0, w1, w2
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
                who[i] = m; Pb[i] = P[src]; Nw[i] = N[src]
    for m, (v, f, col) in enumerate(meshes):            # only what is seen is coloured and lit
        pix = np.where(who == m)[0]
        if not len(pix):
            continue
        P = Pb[pix].astype(np.float64); N = Nw[pix].astype(np.float64)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
        dry = TEXTURE and tuple(col) == BONE
        if dry:
            col, N = bone(P, N, s)
        sh = 0.16 + 0.66 * np.clip(N @ light, 0, 1) ** 1.1 + 0.2 * np.clip(N @ fill, 0, 1)
        sh = sh * np.clip(0.55 + 0.45 * np.clip(N @ eye, 0, 1) ** 0.5, 0, 1)      # edges fall away a little
        img[pix] = sh[:, None] * np.asarray(col, np.float32)
        if dry:
            # dry bone is matt but not chalk: where it faces half-way between the light and the eye it gives back a faint, broad sheen,
            # and the grain breaks that sheen up. It is by this broken sheen that the eye reads a surface as bone and not as clay.
            hv = light + eye; hv = hv / np.linalg.norm(hv)
            img[pix] += (20.0 * np.clip(N @ hv, 0, 1) ** 14)[:, None] * np.array([1.0, 0.98, 0.93], np.float32)
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
