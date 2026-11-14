"""palate.py: the roof of the mouth, as one height map over the view from below.

The hard palate is not a tunnel bored between the teeth. Seen from below (Gray 1918, Fig. 187) it is a vault whose
side walls are the tooth-bearing process: steep beside the molars, a longer slope behind the front teeth, a nearly
level roof between; behind, a thin free edge that ends in a spine at the midline. On it the plate draws:

  the incisive fossa   a pear-shaped pit close behind the two middle incisors, the canals opening in its roof
  the sutures          one down the midline; one across (maxilla in front, palatine bone behind), which turns back along
                       the groove to the greater palatine foramen
  the greater palatine foramen, inward of the last molar, and the groove that runs forward from it at the foot of the
                       side wall, with a low ridge on its inner side
  the lesser foramina  behind the greater one, on the palatine bone's pyramidal process
  the palatine crest   a low ridge across the palatine bone a little in front of its free edge
  the surface          rough and pitted in front (the maxilla's part: glands and small vessels), smoother behind

Where things lie along the arch is read off the plate tooth by tooth (each feature keeps its place against the tooth
it lies beside), because this skull's teeth are set by their standard widths and its arch is a few mm longer than the
plate's. Heights: the roof is 12 mm above the gum at the molars (20 mm above the biting plane), the usual depth.
Here y is the height of the mouth's side of the bone; the bone is above it.
"""
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
import relief, sdf, base, foramina
from skull import arch

# the free hind edge, from behind the last molar in to the spine at the midline (x, z): each half sweeps a little forward
HIND = [(23.6, 39.3), (20.6, 39.1), (18.2, 39.7), (16.6, 41.2), (15.6, 43.0), (14.5, 44.2), (11.5, 45.0), (8.0, 45.3), (5.0, 44.9), (2.9, 44.2), (1.6, 43.3), (0.7, 42.5), (0.0, 42.2)]
NECK_HALF = [3.1, 2.7, 3.7, 4.2, 4.2, 5.3, 5.3, 4.9]          # half of each tooth's thickness at the gum, lip side to tongue side (mm)
FORAMEN = (16.6, 46.3)                                        # greater palatine foramen (x, z)
LESSER = [(17.5, 43.5), (19.3, 43.8)]
# the suture across: from the midline outward, then back along the groove's inner side to the foramen
TRANSVERSE = [(0.0, 56.1), (1.6, 56.4), (3.6, 55.9), (6.0, 55.4), (8.4, 55.2), (10.6, 54.8), (12.3, 53.9), (13.6, 52.0), (14.7, 49.8), (15.6, 48.2)]
# the incisive fossa: a pear, broad in front, drawn out to a slit behind (left half of its outline)
FOSSA = [(0.0, 88.6), (1.1, 88.3), (1.95, 87.2), (2.3, 85.6), (2.05, 83.8), (1.35, 82.2), (0.75, 80.8), (0.4, 79.6), (0.0, 79.0)]
NOSE_FLOOR = -28.0                                            # the floor of the nose is never lower than this (it is nearly level)


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def to_line(M, P):
    """Distance (mm) of every point of the map from a line of points (x, z), and how far along the line the nearest point is."""
    P = np.asarray(P, float)
    s = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(P, axis=0).T))])
    d, i = cKDTree(P).query(np.column_stack([np.abs(M.U).ravel(), M.V.ravel()]))
    return d.reshape(M.U.shape), s[i].reshape(M.U.shape)


def wavy(P, amp, seed, step=0.2):
    """A suture's line: the traced course with the small teeth a real one has (mm), its ends kept."""
    Q = sdf.spline(np.column_stack([np.asarray(P, float), np.zeros(len(P))]), step)[:, :2]
    s = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(Q, axis=0).T))])
    t = np.gradient(Q, axis=0); t /= np.linalg.norm(t, axis=1, keepdims=True)
    n = np.column_stack([-t[:, 1], t[:, 0]])
    r = np.random.default_rng(seed).uniform(0, 2 * np.pi, 4)
    w = np.sin(2 * np.pi * s / 2.6 + r[0]) + 0.8 * np.sin(2 * np.pi * s / 1.5 + r[1]) + 0.6 * np.sin(2 * np.pi * s / 4.3 + r[2]) + 0.5 * np.sin(2 * np.pi * s / 0.9 + r[3])
    fade = np.clip(np.minimum(s, s[-1] - s) / 1.5, 0, 1)
    return Q + (amp * 0.5 * w * fade)[:, None] * n


def surface(line, table, h=0.5, log=print):
    """The map, the mouth's side of the bone on it (with and without its small relief), the palate's outline, and the lines."""
    M = relief.Map(-3.0, 31.0, 37.0, 99.0, 0.25)
    A = arch(line, 0.25)
    d = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(A, axis=0).T))])
    w = np.array(table["width"], float); mid = np.cumsum(w) - w / 2
    keep = d <= w.sum() + 4.6                                 # on behind the last molar, round the end of the tooth-bearing process
    A, d = A[keep], d[keep]
    s, arc = to_line(M, A)                                    # s: how far in from the line the teeth stand on
    cy = np.interp(arc, mid, table["crest y"])
    sb = np.interp(arc, mid, NECK_HALF) + 1.3                 # the tooth's own half thickness and 1.3 mm of bone on its tongue side
    hind = sdf.spline(np.column_stack([np.array([tuple(A[-1])] + HIND, float), np.zeros(len(HIND) + 1)]), 0.3)[:, :2]
    half = np.concatenate([A, hind[1:]])
    reg = M.region(np.concatenate([half, half[-2:0:-1] * np.array([-1.0, 1.0])]))
    # ---- the vault: level at the gum, a steep wall, a nearly level roof
    L = np.interp(M.V, [44, 70, 80, 92], [6.5, 7.0, 8.5, 9.5])
    R = np.interp(M.V, [42, 50, 66, 72, 78, 84, 90, 96], [11.2, 11.8, 12.2, 11.6, 10.2, 8.4, 6.6, 5.2])
    t = np.clip((s - sb) / L, 0.0, 1.0)
    Yb = cy + 0.05 + R * (1.0 - (1.0 - t) ** 2.2) + 1.5 * smoothstep((s - sb - L) / 9.0)      # (the roof is not level from side to side: it rises a little more to the midline)
    # behind the last molar the tooth-bearing process ends rounded: its under side rises to the palatine bone's pyramidal process,
    # which fills the gap between it and the lower ends of the pterygoid plates
    Yb = Yb + 4.4 * smoothstep((arc - (w.sum() - 0.8)) / 4.6)
    Yb = ndimage.gaussian_filter(Yb, 3.0)
    wall = s - sb                                             # < 0: on the level strip the sockets are cut in
    dh, _ = to_line(M, hind)
    ax = np.abs(M.U)
    rng = np.random.default_rng(187)
    n1 = ndimage.gaussian_filter(rng.standard_normal(M.U.shape), 4.0); n1 /= n1.std()
    n2 = ndimage.gaussian_filter(rng.standard_normal(M.U.shape), 1.7); n2 /= n2.std()
    n3 = ndimage.gaussian_filter(rng.standard_normal(M.U.shape), 9.0); n3 /= n3.std()
    Yo = Yb.copy()
    # a low ridge along the midline, from the middle of the palate back to the spine
    Yo -= 0.22 * np.exp(-(ax / (2.4 + 0.7 * n3)) ** 2) * smoothstep((72.0 - M.V) / 10.0) * np.clip(1.0 + 0.8 * n1, 0.0, 2.0)
    # the palatine crest: across the palatine bone, 3 mm in front of its free edge; the spine at the midline
    Yo -= 0.3 * np.exp(-((dh - 3.0) / 1.0) ** 2) * smoothstep((ax - 2.5) / 3.5) * smoothstep((14.5 - ax) / 4.0) * (1.0 + 0.5 * n3) * (M.V > 44.0)
    Yo -= 0.35 * np.exp(-(ax / 1.6) ** 2 - ((M.V - 43.6) / 1.8) ** 2)
    # the groove forward from the greater palatine foramen at the foot of the side wall, the ridge on its inner side, a second fainter groove
    run = smoothstep((M.V - FORAMEN[1] + 1.0) / 2.0) * smoothstep((82.0 - M.V) / 10.0)
    deep = np.interp(M.V, [46, 56, 70, 82], [1.15, 0.95, 0.6, 0.25]) * (1.0 + 0.25 * n1)
    Yo += run * deep * np.exp(-((wall - 3.6) / 1.05) ** 2)
    Yo -= run * 0.38 * np.exp(-((wall - 5.7) / 0.9) ** 2) * (1.0 + 0.5 * n1)
    Yo += run * smoothstep((74.0 - M.V) / 6.0) * 0.32 * np.exp(-((wall - 7.6) / 0.9) ** 2)
    # ---- the suture across (the one on the midline is cut after the halves are joined, with its own wander: surface.py)
    cross = wavy(TRANSVERSE, 0.75, 31)
    dc, _ = to_line(M, cross)
    hw = max(0.3, 0.8 * h)
    Yo += 0.5 * np.exp(-(dc / max(hw, 0.42)) ** 2)
    Yo = relief_mirror(M, Yo)                                 # the other side is this one mirrored
    log("palate: roof %.1f mm above the gum at the first molar, %.1f behind the canines; hind edge at z %.1f, spine at z %.1f" % (
        at(M, Yb, 0.0, 66.0) - table["crest y"][5], at(M, Yb, 0.0, 84.0) - table["crest y"][2], HIND[6][1], HIND[-1][1]))
    return dict(M=M, Yb=Yb, Yo=Yo, reg=reg, wall=wall, cross=cross, hind=hind, line=A)


def at(M, A, u, v):
    return float(M.sample(A, np.array([u], float), np.array([v], float))[0])


def relief_mirror(M, Y):
    """The map's x < 0 part made the mirror image of its x > 0 part."""
    i0 = int(round((0.0 - M.u0) / M.cell))
    out = Y.copy()
    n = min(i0, Y.shape[0] - 1 - i0)
    out[i0 - n:i0] = Y[i0 + n:i0:-1]
    return out


def build(F, line, table, log=print):
    """Cut the vault of the palate into the field F (the skull's left half) and leave the palate a thin plate: the
    mouth's side as mapped, the nose's floor above it. Returns the maps (for the bones' borders later)."""
    P = surface(line, table, F.h, log)
    M, Yb, Yo, reg = P["M"], P["Yb"], P["Yo"], P["reg"]
    ax = np.abs(M.U)
    # how thick the plate is: thin in each half, a crest along the midline for the vomer, thick in front and at the sides
    thick = np.interp(M.V, [42, 54, 58, 99], [1.7, 1.9, 2.4, 2.6]) + 2.7 * np.exp(-(ax / 2.3) ** 2) + 2.2 * (1 - smoothstep((P["wall"] - 0.5) / 3.0)) \
        + 6.0 * smoothstep((44.5 - M.V) / 3.0) * smoothstep((ax - 14.6) / 1.6)        # the pyramidal process is a block, not a plate
    NF = np.maximum(Yb + thick, NOSE_FLOOR)
    NF = ndimage.gaussian_filter(NF, 2.0)
    F.cut(sdf.Box((0, -38.5, 40.5), (19.4, 7.2, 4.9), 1.0), 1.0)          # nothing hangs below the choanae behind the palate's free edge (the face's block ends there in a sliver)
    F.cut(base.Below(M, Yo, reg), 0.5)
    F.add(relief.Slab(M, (0, 2, 1), -Yo, -NF, reg, round=0.7, sign=-1.0), 0.8, keep=4)
    # the floor of the nose, cleared down to the plate from the septum's foot out to the side wall
    nose = [(1.4, 87.0), (5.5, 86.6), (9.5, 84.5), (11.8, 79.0), (12.8, 68.0), (12.9, 54.0), (12.6, 47.0), (11.5, 45.1), (8.0, 45.4), (5.0, 45.0), (2.9, 44.3), (1.4, 43.4)]
    regN = M.region(sdf.spline(np.column_stack([np.array(nose, float), np.zeros(len(nose))]), 0.5, closed=True)[:, :2])
    F.cut(relief.Slab(M, (0, 2, 1), -(NF + 0.2), -(NF + 7.0), regN, round=1.2, sign=-1.0), 1.0)
    # ---- the openings
    # incisive fossa: the pear the plate draws, a funnel that narrows upward and runs up and back; in its roof the two side canals
    fo = np.array(FOSSA, float); pear = np.concatenate([fo, fo[-2:0:-1] * np.array([-1.0, 1.0])])
    Mf, rf = foramina.outline_map(foramina.fair(pear, 0.2), cell=0.2, margin=3.0)
    ysf = M.sample(Yb, Mf.U, Mf.V)
    F.cut(foramina.Opening(Mf, rf, ysf, 6.5, rim=0.6 * np.ones(Mf.U.shape), mouth=2.4, taper=0.2, lean=(0.0, -0.3)), 0.5)
    yf = at(M, Yb, 0.0, 84.5)
    F.cut(sdf.Tube(np.array([(1.0, yf + 3.5, 84.2), (1.9, yf + 7.5, 82.8), (2.7, yf + 13.0, 80.6)]), 0.85), 0.4)
    # greater palatine foramen: an oval longer front to back, its canal running up and a little back; open forward into the groove
    c = np.array(FORAMEN); oval = foramina.ragged(c + np.array(foramina.ROUNDISH) * np.array([1.3, 2.35]), 53, 0.1, n=9)
    Mg, rg = foramina.outline_map(oval, cell=0.2, margin=3.0)
    F.cut(foramina.Opening(Mg, rg, M.sample(Yb, Mg.U, Mg.V) - 0.6, 11.0, rim=0.45 * np.ones(Mg.U.shape), mouth=1.6, taper=0.03, lean=(0.02, -0.1)), 0.5)
    for k, (x, z) in enumerate(LESSER if F.h <= 0.3 else []):             # the lesser foramina, on the pyramidal process behind it (too small for a coarse grid)
        F.cut(sdf.Tube(np.array([(x, -43.0, z + 0.4), (x + 0.3, -36.0, z), (x + 0.5, -30.0, z - 0.8)]), 0.7 - 0.08 * k), 0.3)
    log("palate: plate %.1f mm thick in the middle of each half at the first molar, %.1f on the midline; incisive fossa 3.9 by 7.5 mm" % (
        at(M, NF - Yb, 7.0, 66.0), at(M, NF - Yb, 0.0, 66.0)))
    P["NF"] = NF
    zs = np.arange(44.2, 79.6, 0.4)                                       # the suture down the midline, for surface.py to cut
    P["median"] = np.column_stack([np.zeros(len(zs)), M.sample(Yo, np.zeros(len(zs)), zs) - 0.12, zs])
    return P
