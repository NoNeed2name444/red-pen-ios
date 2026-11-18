"""inner.py: the inner surface of the skull. The cranial cavity was one smooth hollow (the braincase's own shape
set inward by the wall's thickness); a real one is marked all over. Built here, each from Gray's account (Anatomy of
the Human Body, 20th edition, 1918, public domain; the page is given with his words) and laid out after his plate of
the base seen from above (Fig. 193), on this skull's own landmarks:

the hind hollow (occipital bone, p. 130: "The internal surface is deeply concave and divided into four fossae by a
cruciate eminence. The upper two fossae are triangular and lodge the occipital lobes of the cerebrum; the lower two
are quadrilateral and accommodate the hemispheres of the cerebellum. At the point of intersection of the four
divisions of the cruciate eminence is the internal occipital protuberance."; p. 131: "The lower division of the
cruciate eminence is prominent, and is named the internal occipital crest; it bifurcates near the foramen magnum";
"Transverse grooves, one on either side, extend from the internal occipital protuberance to the lateral angles of the
bone; those grooves accommodate the transverse sinuses, and their prominent margins give attachment to the tentorium
cerebelli. The groove on the right side is usually larger than that on the left, and is continuous with that for the
superior sagittal sinus.");

the mastoid part's inside (p. 142: "The inner surface of the mastoid portion presents a deep, curved groove, the
sigmoid sulcus, which lodges part of the transverse sinus");

the petrous part, which stood no higher than a swelling of the floor: a three-sided pyramid whose upper edge parts
the middle hollow from the hind one (p. 144: "The superior angle, the longest, is grooved for the superior petrosal
sinus, and gives attachment to the tentorium cerebelli; at its medial extremity is a notch, in which the trigeminal
nerve lies."; p. 142, its front surface: "near the center, an eminence (eminentia arcuata) which indicates the
situation of the superior semicircular canal"; p. 143, its hind surface: "Near the center is a large orifice, the
internal acoustic meatus, the size of which varies considerably; its margins are smooth and rounded, and it leads
into a short canal, about 1 cm. in length, which runs lateralward.");

the vault (parietal bone, p. 134: "it presents depressions corresponding to the cerebral convolutions, and numerous
furrows for the ramifications of the middle meningeal vessel; the latter run upward and backward from the sphenoidal
angle, and from the central and posterior part of the squamous border."; "Near the groove are several depressions,
best marked in the skulls of old persons, for the arachnoid granulations"), the groove for the superior sagittal sinus
along its middle line, and the frontal crest it ends at in front;

the front hollow (p. 190: "behind the foramen cecum, the crista galli, the free margin of which affords attachment to
the falx cerebri"; the ethmoid, p. 153: the crista galli's "anterior border, short and thick, articulates with the
frontal bone").

Gray gives no measure of these in millimetres but the meatus's canal: the widths, depths and heights are ours, from
the usual run of dried skulls, and are named where they are set. The two sides are not alike: the right transverse
and sigmoid grooves are the larger, and each side's artery grooves branch in their own way.

How thick the wall is (it stood 9 to 12 mm all round behind, which the owner marked as too thick). Gray, p. 132, of
the occipital: "the bone is especially thick at the ridges, protuberances, condyles, and anterior part of the basilar
part; in the inferior fossae it is thin, semitransparent, and destitute of diploe." Measured on 15 dry skulls round a
level plane through the outer protuberance (Gupta et al., Cureus 2025, doi 10.7759/cureus.98489): thickest by the
middle line behind, 10.6 to 11.3 mm; thinnest at the side in front, 3.1 to 3.2 mm. So: about 11 mm at the
protuberance only, 6 in the bands beside it, 4.6 in the upper fossae, 2.3 (all compact) in the lower, 3.4 in the
temporal squama. The fossae's own figures are ours, within those limits.

How it is done. The wall stood evenly thick, so a fossa is not dug into it with a solid (that broke through the hind
wall once): the wall is thinned from the cavity's side toward a set thickness (thin()), measured against whatever
lies behind it (the outside, a sinus, a canal). It keeps its own curve, nowhere is less bone left than that
thickness, and the ridges are what is left thick between the fossae. The cavity is told from all other air by its
width (cavity()). A groove is cut along a line found on the wall itself (line(), walk()), as wide at the wall as it
is said to be and never deeper than the bone under it allows (groove()); its width and depth are uneven along it
(varied()). The convolutions' impressions are chance smoothed over a centimetre (blobs()), with no beat in them.
dev/inner_check.py measures the wall afterwards and lists every place under 1.2 mm that was not there before."""
import numpy as np
from scipy import ndimage
import sdf
from sdf import Tube, Ellipsoid, Plate, unit, sample_field
from relief import Map, Slab
from sinus import smoothstep, uneven

K = np.array([0.0, 45.0, -2.0])                  # a point in the middle of the cavity, to look at its walls from
GREAT_OPENING = (15.0, -36.5, 7.0, -17.5)        # half its width, its hind and front ends (z), its level (y): where it is shut when the cavity is told from other air


def cavity(D, lo, h, reach=5.0):
    """The cranial cavity as a mask: the air a ball of `reach` mm can get to from the cavity's middle without leaving
    the skull (no opening is wider than twice that but the great opening, shut here at its own level), and the air
    within reach of that: the grooves and pits of its walls, the mouths of its canals. Worked at every second point of
    the grid (it is a matter of millimetres), then carried back."""
    D = np.asarray(D); n = np.array(D.shape); m = (n + 1) // 2
    bone = np.zeros(m * 2, bool); bone[:n[0], :n[1], :n[2]] = D < 0
    shut = bone.reshape(m[0], 2, m[1], 2, m[2], 2).any(axis=(1, 3, 5)); del bone       # bone if any of the eight is: no thin wall is lost
    h2 = 2.0 * h; X, Y, Z = np.ix_(*[lo[k] + h2 * np.arange(m[k]) + 0.5 * h for k in range(3)])
    hw, z0, z1, y0 = GREAT_OPENING
    shut |= (np.abs(X) < hw) & (Z > z0) & (Z < z1) & (Y < y0) & (Y > y0 - 3.0 * h2)
    lab, cnt = ndimage.label(ndimage.distance_transform_edt(~shut) * h2 > reach)
    at = lab[tuple(np.clip(((K - lo) / h2).astype(int), 0, m - 1))]
    if at == 0:
        raise ValueError("inner.py: the cavity's middle is not in the cavity")
    c2 = ndimage.binary_dilation(lab == at, iterations=int(np.ceil((reach + 2.0) / h2)) + 2, mask=~shut); del lab
    air = D > 0
    cav = np.repeat(np.repeat(np.repeat(c2, 2, 0), 2, 1), 2, 2)[:n[0], :n[1], :n[2]] & air
    return ndimage.binary_dilation(cav, iterations=3, mask=air)                        # (what is finer than two steps)


def floors(cav, lo, h):
    """(floor, roof): where the cavity ends below and above in every upright line of the grid (mm; nan where the line
    misses it). Of the stretches of cavity a line passes (a groove on a steep wall is one of its own) the longest."""
    c = cav.astype(np.int16); cs = np.cumsum(c, axis=1, dtype=np.int32); del c
    run = cs - np.maximum.accumulate(np.where(cav, 0, cs), axis=1); del cs              # how long the stretch is that ends at each point
    end = run.argmax(axis=1); n = run.max(axis=1); del run
    y = lo[1] + h * np.arange(cav.shape[1]); ok = n * h >= 6.0
    return np.where(ok, y[np.maximum(end - n + 1, 0)] - 0.5 * h, np.nan), np.where(ok, y[end] + 0.5 * h, np.nan)


def refresh(G, cav, sl, depth=0.0):
    """After bone was taken from the wall (to `depth` mm) or laid on it inside the window: what is cavity there now."""
    air = G.D[sl] > 0
    cav[sl] = ndimage.binary_dilation(cav[sl] & air, iterations=int(np.ceil(depth / G.h)) + 1, mask=air)


def walls(G, cav, sl):
    """In the window: (off, T). off: how far each point lies from the cavity's wall (mm; in the bone and beyond it
    counted up, in the cavity down). T: how thick the bone is there, from the cavity to the nearest other air (the
    outside, a sinus, a canal)."""
    D = G.D[sl]; air = D > 0; c = cav[sl] & air
    d, ix = ndimage.distance_transform_edt(~c, return_indices=True)
    off = d.astype(np.float32) * G.h - np.clip(D[ix[0], ix[1], ix[2]], 0.0, G.h); del d, ix       # (the nearest point of the cavity is itself a fraction of a step off the wall)
    off = np.clip(np.where(c, -D, off), -20.0, 60.0)
    other = air & ~ndimage.binary_dilation(c, iterations=3)
    far = ndimage.distance_transform_edt(~other).astype(np.float32) * G.h if other.any() else np.full(D.shape, 99.0, np.float32)
    return off, ndimage.gaussian_filter(off + far, 2.0)


def thin(G, cav, lo, hi, want, log=print, name=""):
    """Thin the cavity's wall from within, in the block from lo to hi. want(X, Y, Z) gives (how far the wall is to be
    thinned there, 0 to 1; the thickness it is thinned toward, mm): bone is taken from the cavity's side only, the
    wall's own curve kept, and nowhere is less left than that thickness, whatever lies behind the wall."""
    sl = G.window(np.asarray(lo, float), np.asarray(hi, float))
    off, T = walls(G, cav, sl)
    w, t = want(*G.coords(sl))
    take = ndimage.gaussian_filter((w * np.clip(T - t, 0.0, None)).astype(np.float32), 1.5)
    wall = np.abs(off) < 0.6 * G.h
    was = float(np.median(T[wall & (w > 0.5)])) if (wall & (w > 0.5)).any() else float("nan")
    most = float(take[wall].max()) if wall.any() else 0.0
    D = G.D[sl]                                                       # only where bone is taken is the wall touched at all: the offset has a grain of its own (a tenth of a millimetre, the grid's), which else shows as fine ribs on every wall of the block
    G.D[sl] = D + np.clip(take / 0.3, 0.0, 1.0) * (np.maximum(D, take - ndimage.gaussian_filter(off, 1.5)) - D)
    refresh(G, cav, sl, most)
    if name:
        log("  %s: the wall thinned from within by up to %.1f mm (it was %.1f mm thick there, half of it more, half less)" % (name, most, was))
    return most


def hit(G, origin, target, far=30.0, must=True):
    """Where the straight line from a point in the cavity through `target`, and on beyond it, first meets bone."""
    o = np.asarray(origin, float); t = np.asarray(target, float); u = unit(t - o)
    r = np.arange(1.0, np.linalg.norm(t - o) + far, 0.2)
    v = sample_field(G.D, G.lo, G.h, o + r[:, None] * u)
    if v[0] < 0 or not (v < 0).any():
        if must:
            raise ValueError("inner.py: nothing met on the line from %s through %s (is the first point in the cavity?)" % (np.round(o, 1).tolist(), np.round(t, 1).tolist()))
        return None
    i = int(np.argmax(v < 0)); a, b = float(v[i - 1]), float(v[i])
    return o + (r[i - 1] + 0.2 * a / max(a - b, 1e-6)) * u


def normal(G, P, step=1.5):
    """The surface's normal at points on it, pointing into the air."""
    P = np.atleast_2d(np.asarray(P, float)); g = np.zeros_like(P)
    for k in range(3):
        e = np.zeros(3); e[k] = step
        g[:, k] = sample_field(G.D, G.lo, G.h, P + e) - sample_field(G.D, G.lo, G.h, P - e)
    return g / (np.linalg.norm(g, axis=1, keepdims=True) + 1e-9)


def settle(G, P):
    """Points near the wall carried on to it, with the wall's normals there (smoothed along the line)."""
    P = np.array(P, float)
    for _ in range(3):
        P = P - sample_field(G.D, G.lo, G.h, P)[:, None] * normal(G, P)
    N = ndimage.gaussian_filter1d(normal(G, P), 4.0, axis=0, mode="nearest")                      # (a flat groove laid in short lengths shows every change of tilt as a rib)
    return P, N / np.linalg.norm(N, axis=1, keepdims=True)


def line(G, pairs, step=1.5, wave=0.0, seed=0):
    """A line on the cavity's wall through the places where the sight lines `pairs` [(origin, target), ...] meet it:
    (points, normals). wave: mm the line may wander from side to side as it runs (a vessel's groove is no ruled line)."""
    H = [hit(G, o, t, must=False) for o, t in pairs]
    P = sdf.spline(np.array([p for p in H if p is not None]), step)
    if wave > 0 and len(P) > 4:
        rng = np.random.default_rng(seed); n = len(P)
        w = ndimage.gaussian_filter1d(rng.normal(size=n), 3.0, mode="nearest"); w *= wave / (np.abs(w).max() + 1e-9)
        w *= np.minimum(1.0, np.minimum(np.arange(n), n - 1 - np.arange(n)) / 4.0)       # (its ends stay)
        t = np.gradient(P, axis=0); t /= np.linalg.norm(t, axis=1, keepdims=True) + 1e-9
        P = P + w[:, None] * np.cross(t, normal(G, P))
    return settle(G, P)


def walk(G, p, d, length, rng, turn=0.0, wander=14.0, step=1.2, keep=None):
    """A line on the wall from p, setting out along d and going on for `length` mm: it turns `turn` degrees in all and
    wanders as a vessel does, never straight. keep(point): it stops where this is no longer true. (points, normals)"""
    p = np.asarray(p, float); n = normal(G, p)[0]; d = unit(d - (d @ n) * n)
    m = max(int(length / step), 3)
    w = ndimage.gaussian_filter1d(rng.normal(size=m), 4.0, mode="nearest"); w = np.radians(wander) / 6.0 * w / (np.abs(w).max() + 1e-9)
    P = [p]
    for i in range(m):
        a = np.radians(turn) / m + w[i]
        d = np.cos(a) * d + np.sin(a) * np.cross(n, d)
        q = P[-1] + step * d
        for _ in range(2):
            n = normal(G, q)[0]; q = q - float(sample_field(G.D, G.lo, G.h, q[None])[0]) * n
        if abs(float(sample_field(G.D, G.lo, G.h, q[None])[0])) > 0.6 or (keep is not None and not keep(q)):
            break
        d = unit(d - (d @ n) * n); P.append(q)
    return settle(G, P) if len(P) > 3 else (None, None)


def thickness(G, p, n, far=30.0):
    """How thick the bone is under the wall at p (n: the normal into the air)."""
    r = np.arange(0.4, far, 0.2); v = sample_field(G.D, G.lo, G.h, p - r[:, None] * n)
    return float(r[np.argmax(v > 0)]) if (v > 0).any() else far


def ridge(G, P, N, half, height, k=1.5):
    """A ridge along the line: `height` mm proud of the wall, `half` mm to either side."""
    hh = sdf.along(P, height); a = np.maximum(1.6 * hh, 2.0)
    G.add(Tube(P - N * (a - hh)[:, None], a, sdf.along(P, half), up=N), k, keep=4)


def groove(G, P, N, width, depth, lip=0.0, k=1.0, leave=1.6):
    """A groove along the line, `width` mm across and `depth` mm deep. lip: its margins stand this much proud of the wall.
    leave: it is nowhere so deep that less than this much bone is left under it."""
    w = sdf.along(P, width); d = sdf.along(P, depth)
    t = ndimage.minimum_filter1d(np.array([thickness(G, p, n) for p, n in zip(P, N)]), 5, mode="nearest")
    d = np.minimum(d, np.maximum(ndimage.gaussian_filter1d(t, 2.0, mode="nearest") - leave, 0.05))
    if lip > 0:
        ridge(G, P, N, 0.5 * w + 2.2, lip * np.minimum(1.0, d / max(d.max(), 1e-6) + 0.3), k=2.0)
    a = np.maximum(1.5 * d, 2.0)
    b = 0.5 * w / np.sqrt(np.clip(1.0 - (1.0 - d / a) ** 2, 0.05, 1.0))                # the oval that is `w` across where it meets the wall (a narrow groove else came out a hairline)
    G.cut(Tube(P + N * (a - d)[:, None], a, b, up=N), k)
    return float(d.max())


def varied(P, values, seed, amp=0.13, wave=9.0):
    """`values` along the line (as sdf.along takes them), made uneven by up to `amp` of themselves, over about `wave` mm:
    no sinus's groove is of one width from end to end."""
    v = sdf.along(P, values); rng = np.random.default_rng(seed)
    step = float(np.linalg.norm(np.diff(P, axis=0), axis=1).mean()) if len(P) > 1 else 1.0
    w = ndimage.gaussian_filter1d(rng.normal(size=len(P)), max(wave / (2.5 * step), 1.0), mode="nearest")
    return v * (1.0 + amp * w / (np.abs(w).max() + 1e-9))


def frame(n):
    """A right-handed frame whose third axis is n (columns), for a solid set on a wall."""
    n = unit(n); t = np.cross(n, [0.0, 0.0, 1.0])
    t = unit(t if np.linalg.norm(t) > 0.2 else np.cross(n, [1.0, 0.0, 0.0]))
    return np.stack([t, np.cross(n, t), n], axis=1)


# ---- the middle hollow and the side wall -------------------------------------------------------------------------------
def middle_fossa(G, side, cav, log=print):
    """The middle hollow's floor stood level with the saddle's floor; in the skull it lies lower at either side of the
    sphenoid's body ("deeper than the preceding, is narrow in the middle, and wide at the sides of the skull", p. 190),
    the oval and spinous foramina opening in its floor (foramina.py carries them up through it). Hollowed here beside
    the body, deepest inward and forward."""
    s = float(side); e = Ellipsoid((s * 31.0, 8.5, 21.0), (22.0, 11.5, 15.0))
    G.cut(e, 5.0)
    refresh(G, cav, G.window(e.bounds[0] - 8.0, e.bounds[1] + 8.0), 9.0)


def squama(G, side, cav, log=print):
    """The side wall of the middle hollow (the temporal squama and the great wing behind the orbit) is thin in the
    skull, a couple of millimetres and translucent; it stood as thick as the vault. Thinned from within; the thickness
    it is brought to (3.4 mm, uneven) is ours."""
    s = float(side)

    def want(X, Y, Z):
        r = np.sqrt(((Y - 24.0) / 24.0) ** 2 + ((Z - 14.0) / 32.0) ** 2)
        return (1.0 - smoothstep((r - 0.55) / 0.45)) * smoothstep((s * X - 38.0) / 8.0), 3.4 + 0.4 * uneven(X, Y, Z, 93 + int(s < 0), 1.0, 14.0)
    lo, hi = np.array([20.0, -18.0, -36.0]), np.array([80.0, 66.0, 62.0])
    if s < 0:
        lo, hi = np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]])
    thin(G, cav, lo, hi, want, log, "side wall of the middle hollow (%s)" % ("left" if s > 0 else "right"))


# ---- the petrous part ------------------------------------------------------------------------------------------------
PETROUS_BASE = (58.0, -18.0)        # (x, z): where its upper edge leaves the side wall, behind the ear hole (the edge then stands 52 degrees off the middle plane)
PETROUS_APEX = (14.0, 17.0)         # its tip, at the ragged hole beside the sphenoid's body
PETROUS_CREST = [(-0.15, 11.0), (0.0, 12.0), (0.36, 14.0), (0.55, 11.8), (0.78, 8.4), (1.0, 5.0), (1.1, 1.0)]   # (fraction of the edge from the wall, height above the Frankfurt plane); ours


class _Side:
    """A solid drawn for the left side, set on the side asked for."""
    def __init__(self, solid, s):
        self.solid, self.s = solid, s
        lo, hi = solid.bounds
        self.bounds = (np.array([min(s * lo[0], s * hi[0]), lo[1], lo[2]]), np.array([max(s * lo[0], s * hi[0]), hi[1], hi[2]]))

    def __call__(self, X, Y, Z):
        return self.solid(self.s * X, Y, Z)


def petrous(G, side, cav, log=print):
    """The petrous pyramid of one side raised from the floor: its upper edge, the gently sloping front surface (the
    middle hollow's hind floor) with the arcuate eminence, the steep hind surface (the hind hollow's front wall) with
    the internal acoustic meatus, the groove along the edge and the trigeminal notch at its tip. Nothing of it is ruled:
    the edge bends and rises and falls, the surfaces swell and sink, and the two sides are not alike. Returns the
    meatus's mouth."""
    s = float(side); A = np.array(PETROUS_BASE); Pp = np.array(PETROUS_APEX)
    e = unit(Pp - A); nf = np.array([-e[1], e[0]]); nf = nf if nf[1] > 0 else -nf      # along the edge; square to it, forward
    L = float(np.linalg.norm(Pp - A))
    M = Map(4.0, 70.0, -30.0, 40.0, 0.5)                                # u = |x|, v = z
    dx, dz = M.U - A[0], M.V - A[1]
    sa = dx * e[0] + dz * e[1]; q = dx * nf[0] + dz * nf[1]
    seed = 310 if side > 0 else 311; rng = np.random.default_rng(seed); ph = rng.uniform(0, 2 * np.pi, 6)
    q = q - (2.0 * np.sin(np.pi * sa / L * 1.25 + ph[0]) + 0.9 * np.sin(2 * np.pi * sa / 17.0 + ph[1])) * smoothstep(sa / 10.0) * smoothstep((L - sa) / 10.0)   # the edge is no ruled line (its two ends stay where they are)
    c = np.array(PETROUS_CREST)
    yc = np.interp(sa, c[:, 0] * L, c[:, 1]) + 0.7 * np.sin(2 * np.pi * sa / 21.0 + ph[2]) + 0.4 * np.sin(2 * np.pi * sa / 9.0 + ph[3])
    steep = 1.9 + 0.35 * np.sin(2 * np.pi * sa / 26.0 + ph[4])                           # the hind surface stands steeper here, flatter there
    top = np.where(q < 0, yc + steep * q + 0.03 * q * q, yc - 0.30 * q - q * q / 45.0)
    top = top + 1.8 * np.exp(-((sa - 0.4 * L) / 5.5) ** 2 - ((q - 5.0) / 4.0) ** 2)     # the arcuate eminence, near the middle of the front surface
    top = top - 0.8 * np.exp(-((sa - 0.24 * L) / 5.0) ** 2 - ((q - 10.0) / 4.5) ** 2)   # the hollow over the drum's cavity, in front of and outside it
    top = top - 1.3 * np.exp(-((sa - L + 8.0) / 4.5) ** 2 - ((q - 1.0) / 4.5) ** 2)     # the notch the trigeminal nerve lies in, at the tip
    top = top - 1.0 * np.exp(-((sa - 0.36 * L) / 2.6) ** 2 - ((q + 2.6) / 2.2) ** 2)    # the small pit under the edge behind (the subarcuate fossa)
    top = top + uneven(M.U, 0.0 * M.U, M.V, seed, 0.8, 13.0) + uneven(M.U, 0.0 * M.U, M.V, seed + 5, 0.3, 5.0)
    top = ndimage.gaussian_filter(top, 3.0)                                               # (its edge is rounded: 1.5 mm)
    xz = lambda a, b: (A[0] + a * e[0] + b * nf[0], A[1] + a * e[1] + b * nf[1])
    reg = M.region(np.array([xz(-10, -15), xz(L + 2, -10), xz(L + 5, 0), xz(L + 3, 8), xz(30, 23), xz(-10, 25)]))
    sol = Slab(M, (0, 2, 1), top, np.full_like(top, -34.0), reg, round=2.5, mirror=False)
    sl, d = G.dist(_Side(sol, s), 6.0)
    if sl is not None:                                                                    # bone is laid in the cavity only: no canal or hollow under its floor is filled
        c_ = cav[sl]; out = (ndimage.distance_transform_edt(~c_) - ndimage.distance_transform_edt(c_)) * G.h
        G.D[sl] = sdf.smin(G.D[sl], np.maximum(d, out.astype(np.float32) - 1.0), 2.5)
        refresh(G, cav, sl)
    at = lambda a, b: np.array([s * xz(a, b)[0], float(M.sample(top, [xz(a, b)[0]], [xz(a, b)[1]])[0]), xz(a, b)[1]])
    # the groove for the superior petrosal sinus, along the edge
    P, N = line(G, [(at(a, 0.0) + (0, 12.0, 0), at(a, 0.0)) for a in np.arange(5.0, L - 6.0, 3.0)], wave=0.6, seed=seed)
    groove(G, P, N, 2.4, 0.7, k=0.6)
    # the internal acoustic meatus, on the hind surface near its middle: its mouth 5 mm across, its canal 1 cm long, lateralward
    a_ = 0.54 * L; yc_ = float(np.interp(a_, c[:, 0] * L, c[:, 1]))
    o_ = np.array([s * xz(a_, -15.0)[0], yc_ - 4.5, xz(a_, -15.0)[1]]); t_ = np.array([s * xz(a_, -3.2)[0], yc_ - 6.2, xz(a_, -3.2)[1]])
    m = hit(G, o_, t_, must=False)
    if m is not None:
        u = unit(np.array([s * 1.0, -0.08, 0.24]))
        G.cut(Tube(np.array([m - 2.5 * u, m, m + 3.0 * u, m + 10.0 * u]), [(0, 3.2), (0.16, 2.6), (0.4, 2.1), (1, 1.7)], [(0, 2.7), (0.16, 2.2), (0.4, 1.9), (1, 1.5)]), 1.2)
    log("  petrous part (%s): edge %.0f mm long, %.1f mm above the Frankfurt plane at the arcuate eminence, %.1f at the tip; meatus at %s" % (
        "left" if side > 0 else "right", L, float(at(0.4 * L, 5.0)[1]), float(at(L, 0.0)[1]), None if m is None else np.round(m, 1).tolist()))
    return m


# ---- the hind hollow ---------------------------------------------------------------------------------------------------
BACK = -15.0                        # z of the upright line the hind wall is looked at from (over the great opening's middle)


def transverse_height(y0, deg):
    """How high the transverse line stands at an azimuth about that upright line (0 = straight back): it rises a little
    as it runs outward."""
    return y0 + 4.5 * np.clip((np.abs(deg) - 4.0) / 74.0, 0.0, 1.0) ** 1.6


def occipital(G, cav, inion_y, log=print):
    """The cruciate eminence and what it parts. The wall, which stood evenly thick, is thinned to what it is in the
    skull: thin in the two lower fossae (the cerebellum's), less so in the two upper, and left thick along the
    transverse line and the sagittal groove's band between them, round the great opening and toward the mastoid; the
    crest below the protuberance is a narrow ridge on the thinned plate, forking at the great opening. Then the protuberance where the four meet, the transverse grooves in the thick band (the
    right the larger, and the one the sagittal groove runs into) and the sigmoid grooves down to the jugular openings.
    The thicknesses (2.3 mm in the lower fossae, 4.6 in the upper, 5.9 along the crest, 6 to 11 in the bands between; uneven) and the grooves' sizes are ours. Returns the protuberance."""
    y0 = inion_y + 5.0                                                # the protuberance within stands a little above the one without

    def want(X, Y, Z):
        ax = np.abs(X)
        yt = transverse_height(y0, np.degrees(np.arctan2(ax, -(Z - BACK))))
        e = np.sqrt((X / 13.5) ** 2 + ((Z + 15.0) / 19.5) ** 2)                          # 1 on the great opening's edge
        A, B = np.array(PETROUS_BASE), np.array(PETROUS_APEX); u = unit(B - A)
        behind = (ax - A[0]) * -u[1] + (Z - A[1]) * u[0]                                 # mm behind the petrous part's upper edge, seen from above
        wob = 3.0 * uneven(X, Y, Z, 95, 1.0, 30.0)                                       # (and no outline is drawn with a ruler, nor the left like the right)
        inside = lambda *d: np.clip(-np.log(sum(np.exp(-np.clip(x, -30.0, 60.0) / 5.0) for x in d)) * 5.0 + wob, 0.0, None)   # mm inside all of a fossa's bounds at once: its outline is rounded, no four-cornered pane
        # the cerebellum's fossae: from the crest outward, under the transverse line, behind the sigmoid groove, clear of the great opening
        # (a bound counted more than once is a shorter slope: the transverse line stands as a ridge, the outer bounds fade)
        wb = smoothstep(inside(50.0 - ax, 1.3 * (yt - 4.0 - Y), (e - 1.0) * 16.0 - 2.5, behind - 15.0) / 15.0)
        # the crest between them: no slab of the wall's whole thickness but a narrow ridge on the thinned plate, a little
        # off the middle line, which forks near the great opening and runs out round its hind margin (p. 131)
        q = np.sqrt((Y + 14.0) ** 2 + (Z + 34.5) ** 2)                                   # mm from the opening's hind margin
        fork = 5.5 * (1.0 - smoothstep(q / 16.0)); xc = -0.8 + 1.1 * np.sin((Y - Z) / 11.0)
        crest = (3.6 - 1.4 * (1.0 - smoothstep(q / 12.0))) * np.maximum(np.exp(-((X - xc - fork) / 2.5) ** 2), np.exp(-((X - xc + fork) / 2.5) ** 2))
        # the occipital lobes' fossae: above it, either side of the sagittal groove, fading toward the lambda
        mid = -4.6 * (1.0 - smoothstep((Y - y0) / 55.0))                                 # the sagittal groove's middle: right of the middle line by the protuberance, on it higher up (sagittal())
        wc = smoothstep(inside(1.6 * (np.abs(X - mid) - 5.5), 0.5 * (64.0 - ax), 1.3 * (Y - yt - 4.5), 0.4 * (98.0 - Y), 0.6 * (-30.0 - Z)) / 14.0)
        # the whole hind wall besides: it stood 9 to 12 mm thick all round. Measured on dry skulls at the level of the
        # outer protuberance (Gupta et al. 2025, doi 10.7759/cureus.98489) the wall is 10.6 to 11.3 mm by the middle line
        # behind and falls to about 3 mm at the side; so the thickness is kept only about the protuberance
        wall = smoothstep((-30.0 - Z) / 14.0) * smoothstep((behind - 10.0) / 12.0) * smoothstep(((e - 1.0) * 16.0 - 2.0) / 6.0)
        tb = 6.0 + 5.0 * np.exp(-(ax / 20.0) ** 2) * np.exp(-((Y - yt) / 15.0) ** 2)
        t = tb - wb * (tb - (2.3 + crest)) - wc * (tb - 4.6)
        return np.maximum(wall, np.maximum(wb, wc)), t + (0.5 - 0.25 * wb) * uneven(X, Y, Z, 91, 1.0, 16.0)
    thin(G, cav, (-70.0, -44.0, -100.0), (70.0, 102.0, -4.0), want, log, "occipital fossae")
    ax = lambda y: np.array([0.0, y, BACK])
    back = lambda y, deg, R=100.0: ax(y) + R * np.array([np.sin(np.radians(deg)), 0.0, -np.cos(np.radians(deg))])
    iop = hit(G, ax(y0), back(y0, 0.0)); n0 = normal(G, iop)[0]
    G.add(Ellipsoid(iop - n0 * 2.0, (6.5, 5.5, 4.6), frame(n0)), 3.0, keep=4)           # the protuberance, where the four meet
    for sgn, wid, dep in ((1.0, 8.5, 2.4), (-1.0, 11.0, 3.1)):
        sd = 41 if sgn > 0 else 42
        P, N = line(G, [(ax(transverse_height(y0, a)), back(transverse_height(y0, a), sgn * a)) for a in np.linspace(4.0, 78.0, 13)], wave=1.5, seed=sd)
        groove(G, P, N, varied(P, [(0, wid - 1.0), (0.5, wid), (1, wid + 0.5)], sd + 100), varied(P, [(0, 0.6 * dep), (0.25, dep), (1, dep)], sd + 200, 0.18), k=3.0)
        E = P[-1]; o = np.array([sgn * 12.0, 2.0, -22.0])
        way = [E, (54.5, 6.0, -27.5), (54.0, -1.5, -25.5), (51.0, -7.5, -23.0), (46.0, -11.5, -20.5), (40.0, -13.5, -17.5), (34.0, -14.0, -13.5), (29.0, -12.5, -9.0), (25.5, -9.5, -4.5)]
        P, N = line(G, [(o, E)] + [(o, np.array(w) * (sgn, 1.0, 1.0)) for w in way[1:]], wave=1.0, seed=43 if sgn > 0 else 44)
        deep = groove(G, P, N, varied(P, [(0, wid + 0.5), (0.4, wid + 1.5), (1, wid - 0.5)], sd + 300, 0.1), varied(P, [(0, dep), (0.35, dep + 1.6), (0.8, dep + 1.2), (1, dep)], sd + 400, 0.12), k=2.5)
        log("  transverse groove (%s): %.0f mm wide, %.1f deep, from the protuberance to x %.0f y %.0f z %.0f; the sigmoid groove %.1f deep, down to %s" % (
            "left" if sgn > 0 else "right", wid, dep, E[0], E[1], E[2], deep, np.round(P[-1], 0).tolist()))
    log("  internal occipital protuberance at %s (the outer one %.1f mm lower)" % (np.round(iop, 1).tolist(), y0 - inion_y))
    return iop


def jugular(G, side, cav, log=print):
    """Beside the front half of the great opening. The jugular tubercle (p. 131: "The upper surface of the lateral
    part presents an oval eminence, the jugular tubercle, which overlies the hypoglossal canal"), set over the canal's
    own run; and before it, where the basilar part meets the petrous, the groove for the inferior petrosal sinus
    (p. 132: "On the lateral margins of this surface are faint grooves for the inferior petrosal sinuses"; p. 144, the
    petrous part's hind edge: "Its medial half is marked by a sulcus, which forms, with a corresponding sulcus on the
    occipital bone, the channel for the inferior petrosal sinus"), down to the front of the jugular opening. Their
    sizes are ours."""
    s = float(side)
    p = hit(G, (s * 14.2, 16.0, -0.5), (s * 14.2, -30.0, -0.5)); n = normal(G, p)[0]
    run = unit(np.array([s * 0.72, 0.0, 0.69]))                        # the canal's run under it: forward and outward
    t = unit(run - (run @ n) * n); Rm = np.stack([t, np.cross(n, t), n], axis=1)
    sl = G.window(p - 12.0, p + 12.0); before = G.D[sl].copy()
    G.add(Ellipsoid(p - n * 0.9, (4.6, 3.4, 2.9), Rm), 2.5, keep=4)
    G.D[sl] = np.where((before > 0) & ~cav[sl], before, G.D[sl])       # (it is set on the cavity's floor: the canal under it stays open)
    o = np.array([s * 6.0, 14.0, -6.0])
    way = [(12.0, 2.2, 16.0), (12.2, -0.2, 12.0), (14.5, -2.5, 8.0), (18.5, -2.5, 4.5), (21.5, -3.5, 1.5)]
    P, N = line(G, [(o, np.array(w) * (s, 1.0, 1.0)) for w in way], step=1.2, wave=0.5, seed=81 if s > 0 else 82)
    deep = groove(G, P, N, varied(P, [(0, 2.6), (1, 3.4)], 83 if s > 0 else 84), varied(P, [(0, 0.5), (1, 0.9)], 85 if s > 0 else 86, 0.2), k=1.2)
    canal = float(sample_field(G.D, G.lo, G.h, np.array([[s * 11.6, -14.2, -2.4]]))[0])
    log("  jugular tubercle (%s) at %s, 2 mm proud; hypoglossal canal under it %s; inferior petrosal groove %.0f mm long, %.1f deep" % (
        "left" if s > 0 else "right", np.round(p, 1).tolist(), "open" if canal > 0 else "SHUT", np.linalg.norm(np.diff(P, axis=0), axis=1).sum(), deep))


# ---- the vault ---------------------------------------------------------------------------------------------------------
def sagittal(G, iop, log=print):
    """The groove for the superior sagittal sinus: from the right of the protuberance up the occipital, along the
    vault's middle line, narrowing forward, to the frontal crest, a ridge that runs down to the foramen cecum; and
    beside it the pits of the arachnoid granulations, a few, each a cluster of small uneven hollows."""
    a0 = np.degrees(np.arctan2(iop[1] - K[1], -(iop[2] - K[2])))      # the protuberance's angle about the cavity's middle (0 = straight back, 90 = up)
    pts = []
    for a in np.arange(a0 + 4.0, 150.0, 6.0):
        off = -4.6 * (1.0 - smoothstep((a - a0) / 46.0))               # to the right of the middle line behind, on it by the top of the occipital
        o = K + np.array([off, 0.0, 0.0]); r = np.radians(a)
        pts.append((o, o + 100.0 * np.array([0.0, np.sin(r), -np.cos(r)])))
    P, N = line(G, pts, wave=1.7, seed=51)
    groove(G, P, N, varied(P, [(0, 10.5), (0.5, 8.0), (1, 4.5)], 54, 0.16, 12.0), varied(P, [(0, 1.8), (0.5, 1.1), (1, 0.5)], 55, 0.2, 14.0), k=2.5)
    pts = [(K, K + 100.0 * np.array([0.0, np.sin(np.radians(a)), -np.cos(np.radians(a))])) for a in np.arange(152.0, 189.0, 5.0)]
    Q, Nq = line(G, pts, wave=0.4, seed=53)
    ridge(G, Q, Nq, [(0, 1.2), (1, 1.9)], [(0, 0.4), (0.6, 2.0), (1, 2.6)], k=1.5)
    log("  groove for the sagittal sinus: %.0f mm long, 10.5 mm wide behind and 4.5 in front; the frontal crest %.0f mm long" % (
        np.linalg.norm(np.diff(P, axis=0), axis=1).sum(), np.linalg.norm(np.diff(Q, axis=0), axis=1).sum()))
    rng = np.random.default_rng(52); pits = 0
    for a in (52.0, 63.0, 71.0, 79.0, 88.0, 96.0, 107.0, 119.0, 131.0):
        sgn = 1.0 if rng.random() < 0.5 else -1.0; r = np.radians(a + rng.uniform(-4, 4))
        o = K + np.array([sgn * rng.uniform(6.0, 15.0), 0.0, 0.0])
        p = hit(G, o, o + 100.0 * np.array([0.0, np.sin(r), -np.cos(r)]), must=False)
        if p is None:
            continue
        n = normal(G, p)[0]; Rm = frame(n); run = rng.uniform(0, np.pi)                  # (each cluster drawn out its own way)
        for _ in range(int(rng.integers(3, 7))):
            u, v = rng.normal() * 2.2, rng.normal() * 0.9
            c = p + Rm[:, 0] * (u * np.cos(run) - v * np.sin(run)) + Rm[:, 1] * (u * np.sin(run) + v * np.cos(run))
            c = c - float(sample_field(G.D, G.lo, G.h, c[None])[0]) * n
            ra, rb = rng.uniform(0.8, 1.9), rng.uniform(0.7, 1.5); deep = rng.uniform(0.4, 1.0)
            G.cut(Ellipsoid(c + n * (1.3 - deep), (ra, rb, 1.3), Rm @ sdf.rot((0, 0, 1), rng.uniform(0, 180))), 0.7)
        pits += 1
    log("  pits of the arachnoid granulations: %d clusters beside the sagittal groove" % pits)


# the middle meningeal artery's grooves, left side (mm, near the wall: each point is carried on to the wall along the line
# of sight from the cavity's middle). The trunk from the spinous foramen forward and outward over the middle hollow's
# floor; its frontal branch up behind the coronal suture from the parietal's sphenoidal angle; its parietal branch
# backward over the squama and up toward the lambda (p. 134). Their twigs are not drawn: each leaves its branch where
# and as chance has it, and wanders (walk), so that the two sides are not alike.
MENINGEAL = {
    "trunk": ([(36.3, -1.0, 17.9), (39.5, 0.5, 21.5), (46.0, 4.0, 27.0), (52.0, 10.0, 31.0)], 2.7, 2.4, None, 0),
    "frontal": ([(52.0, 10.0, 31.0), (57.0, 21.0, 36.0), (59.5, 34.0, 38.0), (60.5, 48.0, 34.0), (57.5, 64.0, 27.0), (50.0, 80.0, 18.0), (38.0, 93.0, 8.0)], 2.4, 1.3, [(0.0, 0.5, -1.0)] * 3 + [(0.0, 0.4, 1.0)], 4),
    "parietal": ([(52.0, 10.0, 31.0), (58.0, 16.0, 20.0), (61.5, 24.0, 5.0), (63.5, 36.0, -12.0), (62.0, 50.0, -30.0), (56.0, 64.0, -46.0), (46.0, 76.0, -58.0)], 2.2, 1.2, [(0.0, 1.0, -0.2)] * 3 + [(0.0, -0.6, -1.0)], 4),
}


def meningeal(G, side, log=print):
    s = float(side); rng = np.random.default_rng(61 if side > 0 else 62); total = 0.0; count = 0
    shift = {}                                                        # where a branch leaves the trunk, both move alike
    on_vault = lambda q: q[1] > 4.0 and s * q[0] > 7.0

    def cut(P, N, w0, w1):
        nonlocal total, count
        groove(G, P, N, (w0, w1), (0.3 * w0, 0.3 * w1), k=0.8)
        total += float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum()); count += 1

    def twig(P, N, at, pref, width, length, forks=1):
        i = int(np.clip(at * (len(P) - 1), 2, len(P) - 3)); t = unit(P[i + 1] - P[i - 1]); sv = unit(np.cross(N[i], t))
        sv = sv if sv @ (np.array(pref) * np.array([s, 1.0, 1.0])) > 0 else -sv                 # (the side of the branch it leaves on)
        a = np.radians(rng.uniform(28.0, 55.0))
        Q, Nq = walk(G, P[i], np.cos(a) * t + np.sin(a) * sv, length, rng, turn=rng.uniform(-25.0, 25.0), keep=on_vault)
        if Q is None:
            return
        cut(Q, Nq, width, max(0.6 * width, 1.0))
        if forks and len(Q) > 12 and rng.random() < 0.7:
            twig(Q, Nq, rng.uniform(0.35, 0.7), unit(rng.normal(size=3)), 0.72 * width, rng.uniform(12.0, 26.0), forks - 1)

    for name, (way, w0, w1, prefs, n) in MENINGEAL.items():
        W = np.array(way, float) * np.array([s, 1.0, 1.0])
        for i in range(len(W)):
            key = tuple(np.round(W[i], 1))
            if key not in shift:
                shift[key] = rng.normal(size=3) * (0.0 if (name == "trunk" and i == 0) else (2.2 if side > 0 else 3.2))
            W[i] = W[i] + shift[key]
        o = np.array([s * 30.0, 26.0, 20.0]) if name == "trunk" else K
        P, N = line(G, [(o, w) for w in W], step=1.2, wave=1.0, seed=int(rng.integers(1 << 30)))
        cut(P, N, w0, w1)
        for j in range(n):
            at = (j + rng.uniform(0.2, 0.8)) / n * 0.8 + 0.12
            twig(P, N, at, prefs[j], (w0 + (w1 - w0) * at) * 0.68, rng.uniform(22.0, 50.0))
    log("  grooves for the middle meningeal vessels (%s): %d, %.0f mm in all, 2.7 mm wide at the trunk to 1.0 at the twigs' ends" % (
        "left" if side > 0 else "right", count, total))


# ---- the front hollow --------------------------------------------------------------------------------------------------
CRISTA = [(57.0, 20.0), (61.0, 23.6), (66.0, 27.2), (71.0, 30.4), (75.0, 32.2), (77.5, 32.0), (79.2, 29.5), (80.0, 25.0), (80.3, 20.0), (80.3, 17.5), (57.0, 17.5)]   # (z, y): ours, 23 mm long and 11 high


def front(G, floor_at, log=print):
    """The crista galli on the cribriform plate, thick and short in front, long and thin behind; the foramen cecum
    before it."""
    f = floor_at(0.0, 68.0)
    out = np.array(CRISTA) + np.array([0.0, f - 21.5])                # set on the plate where it really is
    G.add(Plate(out, (0.0, 0.0, 0.0), (0, 0, 1), (0, 1, 0), 1.15, round=1.0), 1.0, keep=3)
    G.add(Ellipsoid((0.0, out[6, 1] - 3.5, 78.0), (2.1, 5.0, 2.6)), 1.2, keep=3)       # its thick front border
    p = hit(G, (0.0, out[:, 1].max() + 14.0, 82.0), (0.0, f - 4.0, 82.0), far=2.0, must=False)     # the foramen cecum, between it and the frontal crest
    if p is not None:
        G.cut(Tube(np.array([p + (0.0, 1.5, 0.0), p - (0.0, 3.5, 0.3)]), 0.9), 0.5)
    log("  crista galli: %.0f mm long, %.1f mm above the cribriform plate (plate at %.1f mm)" % (np.ptp(out[:, 0]), out[:, 1].max() - f, f))


def blobs(G, seed, size):
    """An unevenness with no beat in it (crossing waves show as ripples on a broad wall): chance, smoothed over `size`
    mm, on G's grid; mean 0, spread 1, nothing beyond 1.8."""
    rng = np.random.default_rng(seed); n = (np.array(G.n) + 3) // 4 + 2                # (laid at every fourth point, then carried to all)
    a = ndimage.gaussian_filter(rng.normal(size=n).astype(np.float32), size / (4.0 * G.h))
    a = ndimage.zoom(a / a.std(), 4, order=1)[:G.n[0], :G.n[1], :G.n[2]]
    return np.clip(ndimage.gaussian_filter(a, 2.0), -1.8, 1.8)


def impressions(G, cav, f, log=print):
    """The shallow hollows the brain's convolutions leave, and the low ridges between them: marked on the orbital
    plates and in the middle hollow, faint on the vault and the thin side wall, none in the cerebellum's fossae.
    Pressed into the cavity's own surface only."""
    near = np.clip(4.0 * ndimage.gaussian_filter(cav.astype(np.float32), 1.5 / G.h) - 0.2, 0.0, 1.0)
    X, Y, Z = np.ix_(*G.ax)
    floorw = (1.0 - smoothstep((Y - (np.nan_to_num(f, nan=-99.0)[:, None, :] + 5.0)) / 4.0))       # near the floor of its own upright line
    amp = 0.6 * floorw * smoothstep((Z - 40.0) / 5.0) * smoothstep((np.abs(X) - 14.0) / 8.0)        # the orbital plates (not the thin roof of the ethmoid's cells)
    amp = np.maximum(amp, 0.5 * smoothstep((36.0 - Z) / 5.0) * smoothstep((Z + 6.0) / 8.0) * smoothstep((np.abs(X) - 15.0) / 6.0) * (1.0 - smoothstep((Y - 34.0) / 10.0))
                     * (1.0 - 0.6 * smoothstep((np.abs(X) - 46.0) / 8.0)))                           # the middle hollow; less on its thin side wall
    amp = np.maximum(amp, 0.2 * smoothstep((Y - 30.0) / 10.0))                                        # the vault
    amp = (amp * near).astype(np.float32)
    del floorw, near
    G.D += amp * np.clip(0.8 * blobs(G, 71, 4.5) + 0.45 * blobs(G, 72, 2.4), -1.8, 1.8)
    log("  impressions of the convolutions: up to %.1f mm on the orbital plates, %.1f in the middle hollow, %.1f on the vault" % (0.6 * 1.8, 0.5 * 1.8, 0.2 * 1.8))


def build(G, inion_y=3.9, log=print):
    """Mark the cranial cavity's walls and floor of the whole head's field G. inion_y: the height of the outer
    occipital protuberance (occiput.py)."""
    log("inner surface of the skull:")
    cav = cavity(G.D, G.lo, G.h)
    for side in (1, -1):
        middle_fossa(G, side, cav, log)
    for side in (1, -1):
        squama(G, side, cav, log)
    meatus = {side: petrous(G, side, cav, log) for side in (1, -1)}
    iop = occipital(G, cav, inion_y, log)
    for side in (1, -1):
        jugular(G, side, cav, log)
    sagittal(G, iop, log)
    for side in (1, -1):
        meningeal(G, side, log)
    cav = cavity(G.D, G.lo, G.h); f, r = floors(cav, G.lo, G.h)
    front(G, lambda x, z: float(f[int(round((x - G.lo[0]) / G.h)), int(round((z - G.lo[2]) / G.h))]), log)
    impressions(G, cav, f, log)
    build.marks = dict(protuberance=iop, meatus=meatus)
    return build.marks
