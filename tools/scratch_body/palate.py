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
from scipy.interpolate import RegularGridInterpolator
import relief, sdf, base, foramina
from skull import arch

# the free hind edge, from behind the last molar in to the spine at the midline (x, z): each half sweeps a little forward.
# Read off Fig. 996 (= Fig. 160) against its own tooth row, which this skull's row was fitted to (scale 0.083 mm a pixel at
# 300 dpi from the third molars' spread and the incisor-to-third-molar depth): the spine 12.6 mm behind the third molars'
# crown centres, the edge concave either side, deepest (9.9 mm behind them) 6 to 9 mm out, then sweeping back to 11.2 at 13.5 mm
# out, where it meets the inner pterygoid plate; 3.7 mm behind the tuberosity's hind end. (Fig. 187 draws the row further back
# against the palate: there the spine is only 7.8 mm behind the third molar.) Out from the inner plate the edge is the
# pyramidal process's (pterygoid.py) and keeps its old line.
HIND = [(24.6, 39.6), (21.2, 39.2), (18.2, 39.7), (16.6, 41.2), (15.6, 43.0), (14.6, 43.4), (13.9, 41.0), (13.4, 38.2), (12.6, 37.2), (11.4, 37.6), (9.0, 38.1), (6.0, 38.2), (3.0, 37.8), (1.5, 37.0), (0.6, 35.8), (0.0, 34.9)]
PNS = 35.6                                                    # where the spine's tip ends up once the edge is rounded
NECK_HALF = [3.1, 2.7, 3.7, 4.2, 4.2, 5.3, 5.3, 4.9]          # half of each tooth's thickness at the gum, lip side to tongue side (mm)
FORAMEN = (17.7, 46.9)                                        # greater palatine foramen (x, z): inward of the third molar (Fig. 160)
# the lesser foramina: on the base of the pyramidal process close to its union with the horizontal part (p. 168), behind the
# greater one: Fig. 996 has them 5.7 and 7.2 mm behind it, 1.6 mm inward and 0.4 outward of it (Fig. 187: 3 mm behind); (x, z, half-width, half-length) of each mouth
LESSER = [(16.1, 41.2, 0.72, 1.15), (18.1, 39.7, 0.66, 0.95)]
# the suture across: from the midline outward, then back along the groove's inner side to the foramen (Fig. 996: about 3.5 mm in
# front of the third molars' crown centres, the horizontal plates 16 mm long at the midline)
TRANSVERSE = [(0.0, 51.6), (1.6, 51.9), (3.6, 51.5), (6.0, 51.8), (8.4, 51.4), (10.7, 51.7), (12.5, 51.3), (14.0, 50.4), (15.0, 49.6), (15.9, 48.9)]
# the incisive fossa: a pear, broad in front, drawn out to a slit behind (left half of its outline)
FOSSA = [(0.0, 84.6), (1.3, 84.3), (2.4, 83.2), (3.1, 81.6), (2.7, 79.8), (1.6, 78.2), (0.9, 76.8), (0.5, 75.6), (0.0, 75.0)]   # carried 3 mm back with the incisors (T-rows-refit)
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
    M = relief.Map(-3.0, 31.0, 32.0, 99.0, 0.25)
    A = arch(line, 0.25)
    d = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(A, axis=0).T))])
    w = np.array(table["width"], float); mid = np.cumsum(w) - w / 2
    keep = d <= w.sum() + 4.6                                 # on behind the last molar, round the end of the tooth-bearing process
    A, d = A[keep], d[keep]
    s, arc = to_line(M, A)                                    # s: how far in from the line the teeth stand on
    cy = np.interp(arc, mid, table["crest y"])
    sb = np.interp(arc, mid, NECK_HALF) + 1.3                 # the tooth's own half thickness and 1.3 mm of bone on its tongue side
    # (both are read off the nearest tooth, and on the broad, round arch the nearest tooth changes along a V from behind the incisive
    # fossa to the canines: from the middle incisors' gum, 1.7 mm lower, to the canines'. Read so, the roof stepped along that V;
    # they are made to change smoothly, over some 4 mm)
    cy = ndimage.gaussian_filter(cy, 16.0); sb = ndimage.gaussian_filter(sb, 16.0)
    hind = sdf.spline(np.column_stack([np.array([tuple(A[-1])] + HIND, float), np.zeros(len(HIND) + 1)]), 0.3)[:, :2]
    half = np.concatenate([A, hind[1:]])
    reg = M.region(np.concatenate([half, half[-2:0:-1] * np.array([-1.0, 1.0])]))
    # ---- the vault: level at the gum, a steep wall, a nearly level roof
    L = np.interp(M.V, [44, 68.3, 77, 88], [6.5, 7.0, 8.5, 9.5])
    R = np.interp(M.V, [42, 50, 66, 69.5, 75, 80, 86, 92], [11.2, 11.8, 12.2, 11.6, 10.2, 8.4, 6.6, 5.2])
    t = np.clip((s - sb) / L, 0.0, 1.0)
    Yb = cy + 0.05 + R * (1.0 - (1.0 - t) ** 2.2) + 1.5 * smoothstep((s - sb - L) / 9.0)      # (the roof is not level from side to side: it rises a little more to the midline)
    # behind the last molar the tooth-bearing process ends rounded: its under side rises to the palatine bone's pyramidal process,
    # which fills the gap between it and the lower ends of the pterygoid plates
    Yb = Yb + 4.4 * smoothstep((arc - (w.sum() - 0.8)) / 4.6)
    # behind the greater palatine foramen the floor runs down into the under side of the pyramidal process (pterygoid.py), which
    # stands as low as the tooth-bearing process beside it: a slope from the foramen back, not a cliff 7 mm high at the process's front
    Ynf = ndimage.gaussian_filter(Yb, 3.0)                    # (the nose's side of the plate is counted from the floor as it was without that slope)
    # and behind the last molar's socket the strip the teeth stand on does not run on at the gum's level: it rises into the
    # tuberosity's rounded back (left at the gum it hung behind the tuberosity as a thin rod)
    Yb = Yb + 5.0 * smoothstep((44.2 - M.V) / 3.5) * smoothstep((M.U - 19.0) / 2.5)
    xm = np.interp(M.V, [38.0, 49.0], [12.8, 16.5])            # (the slope's foot runs in toward the pyramidal process, not straight back)
    Yb = Yb - 6.5 * smoothstep((M.U - xm) / 4.2) * smoothstep((21.0 - M.U) / 2.5) * smoothstep((49.0 - M.V) / 4.5) * smoothstep((M.V - 38.0) / 3.0)
    Yb = ndimage.gaussian_filter(Yb, 3.0)
    wall = s - sb                                             # < 0: on the level strip the sockets are cut in
    dh, _ = to_line(M, hind)
    ax = np.abs(M.U)
    rng = np.random.default_rng(187)
    pad = int(round((37.0 - M.v0) / M.cell)); sh = (M.U.shape[0], M.U.shape[1] - pad)   # (drawn on the map as it was from z 37, so the front keeps its grain; carried back by reflection)
    n1 = ndimage.gaussian_filter(rng.standard_normal(sh), 4.0); n1 = np.pad(n1 / n1.std(), ((0, 0), (pad, 0)), mode="reflect")
    n2 = ndimage.gaussian_filter(rng.standard_normal(sh), 1.7); n2 = np.pad(n2 / n2.std(), ((0, 0), (pad, 0)), mode="reflect")
    n3 = ndimage.gaussian_filter(rng.standard_normal(sh), 9.0); n3 = np.pad(n3 / n3.std(), ((0, 0), (pad, 0)), mode="reflect")
    Yo = Yb.copy()
    # a low ridge along the midline, from the middle of the palate back to the spine
    Yo -= 0.22 * np.exp(-(ax / (2.4 + 0.7 * n3)) ** 2) * smoothstep((69.5 - M.V) / 10.0) * np.clip(1.0 + 0.8 * n1, 0.0, 2.0)
    # the palatine crest: across the palatine bone, 3 mm in front of its free edge; the spine at the midline
    Yo -= 0.42 * np.exp(-((dh - 3.2) / 1.1) ** 2) * smoothstep((ax - 2.5) / 3.5) * smoothstep((14.5 - ax) / 4.0) * (1.0 + 0.5 * n3) * (M.V > PNS + 1.8)
    Yo -= 0.35 * np.exp(-(ax / 1.6) ** 2 - ((M.V - PNS - 1.4) / 1.8) ** 2)
    # the groove forward from the greater palatine foramen at the foot of the side wall, the ridge on its inner side, a second fainter groove
    run = smoothstep((M.V - FORAMEN[1] + 1.0) / 2.0) * smoothstep((79.0 - M.V) / 10.0)
    deep = np.interp(M.V, [46, 56, 70, 82], [1.15, 0.95, 0.6, 0.25]) * (1.0 + 0.25 * n1)
    Yo += run * deep * np.exp(-((wall - 3.6) / 1.05) ** 2)
    Yo -= run * 0.38 * np.exp(-((wall - 5.7) / 0.9) ** 2) * (1.0 + 0.5 * n1)
    Yo += run * smoothstep((71.5 - M.V) / 6.0) * 0.32 * np.exp(-((wall - 7.6) / 0.9) ** 2)
    # ---- the suture across (the one on the midline is cut after the halves are joined, with its own wander: surface.py)
    cross = wavy(TRANSVERSE, 0.75, 31)
    dc, _ = to_line(M, cross)
    hw = max(0.3, 0.8 * h)
    Yo += 0.5 * np.exp(-(dc / max(hw, 0.42)) ** 2)
    Yo = relief_mirror(M, Yo)                                 # the other side is this one mirrored
    log("palate: roof %.1f mm above the gum at the first molar, %.1f behind the canines; hind edge at z %.1f 6 mm out, spine at z %.1f" % (
        at(M, Yb, 0.0, 66.0) - table["crest y"][5], at(M, Yb, 0.0, 81.0) - table["crest y"][2], dict(HIND)[6.0], PNS))
    return dict(M=M, Yb=Yb, Ynf=Ynf, Yo=Yo, reg=reg, wall=wall, cross=cross, hind=hind, line=A)


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
    NF = np.maximum(P["Ynf"] + thick, NOSE_FLOOR)
    NF = ndimage.gaussian_filter(NF, 2.0)
    F.cut(sdf.Box((0, -38.5, 40.5), (19.4, 7.2, 4.9), 1.0), 1.0)          # nothing hangs below the choanae behind the palate's free edge (the face's block ends there in a sliver)
    F.cut(base.Below(M, Yo, reg), 0.5)
    F.add(relief.Slab(M, (0, 2, 1), -Yo, -NF, reg, round=0.7, sign=-1.0), 0.8, keep=4)
    # the floor of the nose, cleared down to the plate from the septum's foot out to the side wall
    nose = [(1.4, 87.0), (5.5, 86.6), (9.5, 84.5), (11.8, 79.0), (12.8, 68.0), (12.9, 54.0), (12.6, 44.0), (12.0, 38.0), (9.0, 38.3), (6.0, 38.4), (3.0, 38.0), (1.4, 37.2)]
    regN = M.region(sdf.spline(np.column_stack([np.array(nose, float), np.zeros(len(nose))]), 0.5, closed=True)[:, :2])
    F.cut(relief.Slab(M, (0, 2, 1), -(NF + 0.2), -(NF + 7.0), regN, round=1.2, sign=-1.0), 1.0)
    # ---- the openings
    # incisive fossa: the pear the plate draws, a funnel that narrows upward and runs up and back; in its roof the two side canals
    fo = np.array(FOSSA, float); pear = np.concatenate([fo, fo[-2:0:-1] * np.array([-1.0, 1.0])])
    Mf, rf = foramina.outline_map(foramina.fair(pear, 0.2), cell=0.2, margin=3.0)
    ysf = M.sample(Yb, Mf.U, Mf.V)
    F.cut(foramina.Opening(Mf, rf, ysf, 6.5, rim=0.6 * np.ones(Mf.U.shape), mouth=2.4, taper=0.2, lean=(0.0, -0.3)), 0.5)
    yf = at(M, Yb, 0.0, 80.5)
    F.cut(sdf.Tube(np.array([(1.0, yf + 3.5, 80.2), (1.9, yf + 7.5, 78.8), (2.7, yf + 13.0, 76.6)]), 0.85), 0.4)
    # greater palatine foramen: an oval longer front to back, its canal running up and a little back; open forward into the groove
    c = np.array(FORAMEN); oval = foramina.ragged(c + np.array(foramina.ROUNDISH) * np.array([1.3, 2.35]), 53, 0.1, n=9)
    Mg, rg = foramina.outline_map(oval, cell=0.2, margin=3.0)
    F.cut(foramina.Opening(Mg, rg, M.sample(Yb, Mg.U, Mg.V) - 0.6, 11.0 + at(M, P["Ynf"] - Yb, *FORAMEN), rim=0.45 * np.ones(Mg.U.shape), mouth=1.6, taper=0.03, lean=(0.02, -0.1)), 0.5)
    # (the lesser foramina are cut by lesser(), once the pyramidal process they open on is there: pterygoid.py adds it after this)
    log("palate: plate %.1f mm thick in the middle of each half at the first molar, %.1f on the midline; incisive fossa 3.9 by 7.5 mm" % (
        at(M, NF - Yb, 7.0, 66.0), at(M, NF - Yb, 0.0, 66.0)))
    P["NF"] = NF
    zs = np.arange(44.2, 76.6, 0.4)                                       # the suture down the midline, for surface.py to cut
    P["median"] = np.column_stack([np.zeros(len(zs)), M.sample(Yo, np.zeros(len(zs)), zs) - 0.12, zs])
    zs = np.arange(PNS + 2.0, 44.21, 0.4)                                 # and on between the palatine bones to near the spine (its own wander: skull2.whole)
    P["median hind"] = np.column_stack([np.zeros(len(zs)), M.sample(Yo, np.zeros(len(zs)), zs) - 0.12, zs])
    return P


def lesser(F, log=print):
    """The lesser palatine foramina, cut into the under side of the palatine bone's pyramidal process (after pterygoid.py has
    added it): small uneven ovals, each the mouth of a canal that runs up and forward toward the greater palatine canal."""
    out = []
    for k, (x, z, a, b) in enumerate(LESSER):
        oval = foramina.ragged(np.array((x, z)) + np.array(foramina.ROUNDISH) * np.array([a, b]), 61 + k, 0.2, n=7)
        Mo, ro = foramina.outline_map(oval, cell=0.2, margin=2.5)
        # the under surface over the small map, read off the field: the lowest bone above y -46 in each column (smoothed)
        sl = F.window((Mo.U.min(), -46.0, Mo.V.min()), (Mo.U.max(), -24.0, Mo.V.max()))
        X, Y, Z = F.coords(sl)
        x1, y1, z1 = X[:, 0, 0], Y[0, :, 0], Z[0, 0, :]
        solid = F.D[sl] < 0
        first = np.where(solid.any(1), y1[np.argmax(solid, axis=1)], -24.0)
        ys = RegularGridInterpolator((x1, z1), first, bounds_error=False, fill_value=None)(np.column_stack([Mo.U.ravel(), Mo.V.ravel()])).reshape(Mo.U.shape)
        ys = ndimage.gaussian_filter(ys, 2.0)
        F.cut(foramina.Opening(Mo, ro, ys - 0.4, 7.0, rim=np.clip(0.3 + 0.18 * foramina.uneven(Mo, 81 + k, 0.8), 0.05, None), mouth=1.2, taper=0.03, lean=(-0.12, 0.3), wobble=(0.12, 71 + k)), 0.3)
        out.append((x, float(Mo.sample(ys, np.array([x]), np.array([z]))[0]), z))
    log("palate: lesser palatine foramina at " + ", ".join("(%.1f, %.1f, %.1f)" % p for p in out))
    return out
