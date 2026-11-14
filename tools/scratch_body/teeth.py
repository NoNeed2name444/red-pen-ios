"""teeth.py: the from-scratch teeth (teeth2.py: textbook sizes, outlines traced from Gray's plate) stood in a jaw's sockets."""
import os, sys
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import teeth2 as AT
import landmarks as L

NECK_ABOVE_CREST = 1.6        # mm from the bone's margin to the line where enamel begins


def frame(s):
    """A socket frame's axes as columns (toward the back of the arch, toward the cheek, toward the biting surface)
    and the middle of the tooth's neck (mm, head frame)."""
    z = np.array(s["axis"], float); z /= np.linalg.norm(z)
    t = np.array(s["along_arch"], float)
    x = t - (t @ z) * z; x /= np.linalg.norm(x)
    y = np.cross(z, x)
    if y @ np.array(s["outward"], float) < 0:              # keep the cheek side outward
        y = -y; x = -x
    return np.column_stack([x, y, z]), np.array(s["position_mm"], float) + NECK_ABOVE_CREST * z


def fair(f, h):
    """A field made a fair distance (mm) outside its surface. The teeth's fields are drawn from outlines and run
    slow across a root's flat sides: 1.2 mm by the field can be 5 mm of real distance, and a wall of bone measured
    by it stands out of the jaw as a peg. Close to the surface the field divided by its own slope is a distance
    again; further out the grid's own distance to the surface holds it from both sides."""
    from scipy import ndimage
    g = np.gradient(f.astype(np.float64), h)
    s = ndimage.gaussian_filter(np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2), 1.0)
    d = f / np.clip(s, 0.25, 2.5)
    out = ndimage.distance_transform_edt(f > 0) * h
    return np.where(f > 0, np.clip(d, out - 0.9 * h, out + 0.9 * h), d).astype(np.float32)


def seat(F, frames, upper, wall=1.0, gap=0.3, k=1.0, reach=None):
    """Bone round every root and a socket of the root's own shape: first the bone is brought to at least `wall` mm
    round each socket (below the bone's margin), then the tooth's own shape, `gap` mm larger, is cut out of the jaw.
    F is the jaw's left half (sdf.Field); the teeth are the same ones stand() gives. `reach` (mm): how far below the
    margin bone is added; a jaw whose faces already stand clear of its roots needs it at the margin only."""
    from sdf import smin, smax
    arch = "upper" if upper else "lower"
    todo = [s for s in frames if s["side"] == "L"]
    h = float(F.ax[0][1] - F.ax[0][0])
    fields = []
    for s in todo:
        i = L.TEETH.index(s["tooth"].split(" ", 1)[1])
        R, p = frame(s)
        root = AT.ARCHES[arch][i][4]; wide = max(AT.ARCHES[arch][i][5], AT.ARCHES[arch][i][7])
        c = p - R[:, 2] * (root / 2 - 2.0); half = np.abs(R) @ np.array([wide / 2 + 3.5, wide / 2 + 3.5, root / 2 + 6.0])
        sl = F.window(c - half, c + half)
        if sl is None:                                   # the field is a block of the head that this tooth lies outside
            continue
        X, Y, Z = np.broadcast_arrays(*F.coords(sl))
        Q = np.stack([X - p[0], Y - p[1], Z - p[2]], -1) @ R
        f = AT.field(arch, i, Q[..., 0], Q[..., 1], Q[..., 2]).astype(np.float32)
        lz = Q[..., 2]
        # the socket is the tooth's shape `gap` mm larger, measured as a fair distance: by the tooth's own field (which runs slow off a
        # root's tip) a socket 0.3 mm larger reached 2 mm beyond the first premolar's outer root and came out through the jaw's face
        socket = fair(f, h) - gap * np.clip(-(lz + NECK_ABOVE_CREST) / 2.0, 0.4, 1.0)     # the bone closes on the tooth's neck at the margin
        fields.append((sl, socket, lz, root))
    for sl, socket, lz, root in fields:                    # bone round the sockets, up to the margin
        thin = wall * np.clip(-(lz + NECK_ABOVE_CREST) / 3.5, 0.55, 1.0)         # the bone thins toward its margin, and the margin is rounded
        deep = np.clip((-(lz + NECK_ABOVE_CREST) / root - 0.55) / 0.4, 0.0, 1.0)  # and toward the root's tip, where a full wall would stand out of the jaw's face as a knob
        thin = thin * (1.0 - 0.45 * deep * deep * (3 - 2 * deep))
        if reach is not None:                              # below `reach` nothing is added: the wall runs out over 3 mm
            thin = thin - 4.0 * np.clip((-(lz + NECK_ABOVE_CREST) - reach) / 3.0, 0.0, 1.0)
        sleeve = smax(socket - thin, lz + NECK_ABOVE_CREST, 0.8)
        F.D[sl] = smin(F.D[sl], sleeve, k)
    for sl, socket, lz, root in fields:                    # then every socket
        F.D[sl] = np.maximum(F.D[sl], -socket)
    return F


_PACKED = {}


def packed(ctrl, table, upper, gap=0.06, log=None):
    """The 16 socket frames of one arch with the teeth standing in contact, as a row of teeth does: the central
    incisor's inner side `gap`/2 from the midline (so it and its twin do not pass through each other), then every
    tooth moved along the arch until it is `gap` mm from the one before. The tooth's own shape decides, not a width
    from a table: by the table the front teeth stood up to 1.6 mm apart and the molars 0.4 mm inside each other."""
    import skull
    key = (upper, round(gap, 3), tuple(map(tuple, ctrl)), tuple(table["width"]), tuple(table["labial tilt deg"]), tuple(table["crest y"]))
    if key in _PACKED:
        return skull.sockets(ctrl, table, upper, mids=_PACKED[key])
    arch = "upper" if upper else "lower"
    V = [AT.tooth(arch, k, h=0.3)[0] for k in range(len(L.TEETH))]

    def placed(k, mids):
        s = [f for f in skull.sockets(ctrl, table, upper, mids=mids) if f["side"] == "L"][k]
        R, p = frame(s)
        return V[k] @ R.T + p, R, p

    def apart(k, mids):                                    # tooth k against tooth k - 1: the least of each one's field at the other's points
        a, Ra, pa = placed(k - 1, mids); b, Rb, pb = placed(k, mids)
        qa = (b - pa) @ Ra; qb = (a - pb) @ Rb
        near_a = np.abs(qa[:, 0]) < 9.0; near_b = np.abs(qb[:, 0]) < 9.0
        fa = AT.field(arch, k - 1, qa[near_a, 0], qa[near_a, 1], qa[near_a, 2]).min() if near_a.any() else 9.0
        fb = AT.field(arch, k, qb[near_b, 0], qb[near_b, 1], qb[near_b, 2]).min() if near_b.any() else 9.0
        return float(min(fa, fb))

    mids, at = [], 0.0
    for k in range(len(L.TEETH)):
        w = table["width"][k]
        lo, hi = at + w / 2 - 3.0, at + w / 2 + 3.0
        for _ in range(22):                                # the tooth moves back along the arch until it stands clear by `gap`
            m = 0.5 * (lo + hi)
            if k == 0:
                clear = placed(0, [m])[0][:, 0].min() - gap / 2
            else:
                clear = apart(k, mids + [m]) - gap
            lo, hi = (m, hi) if clear < 0 else (lo, m)
        mids.append(hi)
        if log:
            log("   %s %s: %.2f mm along the arch (by its width %.2f)" % (arch, L.TEETH[k], hi, at + w / 2))
        at = hi + w / 2
    _PACKED[key] = mids
    return skull.sockets(ctrl, table, upper, mids=mids)


def stand(frames, upper, h=0.15):
    """The teeth of one jaw as meshes in the head frame (mm): [(name, side, v, f)], from the socket frames."""
    out = []
    arch = "upper" if upper else "lower"
    made = {}
    for s in frames:
        if s["side"] != "L":
            continue
        i = L.TEETH.index(s["tooth"].split(" ", 1)[1])
        if i not in made:
            made[i] = AT.tooth(arch, i, h=h)[:2]
        v, f = made[i]
        R, p = frame(s)
        w = v @ R.T + p
        f = np.asarray(f)
        if np.linalg.det(R) < 0:
            f = f[:, ::-1]
        out.append((s["tooth"], "L", w, f))
        out.append((s["tooth"], "R", w * np.array([-1.0, 1, 1]), f[:, ::-1]))
    return out
