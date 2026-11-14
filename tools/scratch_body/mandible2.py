"""mandible2.py: the lower jaw on lines traced from the side view of the skull (Gray 1918, Fig. 188).

The borders a side view shows (hind border, angle, lower border, chin, the front border of the ramus up to the
coronoid tip, the notch, the condyle) are the plate's own, read in the head frame; breadths the side view cannot
show are the usual ones (across the angles 98, across the condyles 120) and the teeth's line follows the upper
teeth's, a little inside it in front. The solid is made the way mandible.py makes it (a body swept between the
tooth-bearing margin and the lower border, a ramus plate thickened along its borders); only the lines differ.
"""
import numpy as np
import sdf, landmarks as L
import mandible as MB
import skull, teeth

# the line the lower teeth stand on, seen from above: (x, z) from the midline to behind the last molar
LOWER_LINE = [(0, 89.9), (5.5, 88.6), (10.8, 85.6), (14.8, 80.5), (17.6, 74.0), (20.6, 65.0), (23.0, 56.0), (24.9, 47.0),
              (26.4, 39.0), (27.6, 33.0)]
# the bone's margin at each tooth, set so that the crowns meet the upper teeth on the traced biting line
# (from z 97, y -54.5 to z 52, y -49.6) with the front teeth behind and 1 to 2 mm above the upper ones' edges
LOWER_T = dict(L.LOWER, **{"crest y": [-62.8, -63.2, -65.0, -62.9, -61.7, -60.2, -58.6, -57.6]})

# matched stations from the midline back: the middle of the tooth-bearing margin, and the lower border under it
T = [(0, -62.8, 89.9), (5.5, -63.0, 88.6), (10.8, -64.6, 85.6), (14.8, -63.2, 80.5), (17.6, -61.9, 74.0),
     (20.6, -60.4, 65.0), (23.0, -59.2, 56.0), (24.9, -58.0, 47.0), (26.8, -57.4, 38.5),
     (33.5, -51.0, 31.5), (40.0, -44.0, 27.0)]                 # the last two climb the ramus
# Seen from below the base is a V with a rounded point, not a U: from the chin's tubercles the two halves run back and outward
# nearly straight (about 27 degrees off the midline) to the angles. Under the premolars the base lies straight under the teeth;
# under the molars it lies outside them, more and more toward the ramus. (An earlier line stood 4 to 7 mm too far out in its
# front half: from in front the jaw was a box, where the plate of the skull from in front, Fig. 190, narrows evenly to the chin.)
# Its height is not the plate's. Traced from Fig. 188 the chin's lowest point stood 90 mm below the Frankfurt plane and the
# angle 67: a lower border 17 degrees off that plane and an angle of 112 degrees, a square jaw with upright sides (the owner,
# 14 November: "the jaw should be angled no?"). The usual sizes this model is built to (landmarks.py: nasion to chin 120 mm,
# joint to angle 62) put the chin at 94 and the angle at 64: the border then slopes 21 degrees (Downs' norm for the mandibular
# plane is 21.9) and the angle opens to about 117, inside the "110 to 120 degrees" Gray gives for the adult (p. 177). The
# body gains height in front (31 mm at the chin for 27) and keeps what it had under the last molar.
B = [(0, -94.2, 86.2), (6.2, -94.2, 85.9), (10.6, -93.7, 82.4), (15.0, -91.8, 74.6), (19.8, -88.2, 64.5),
     (25.2, -84.2, 54.0), (31.6, -79.4, 42.0), (37.6, -74.9, 31.0), (42.0, -71.0, 22.0),
     (44.5, -67.6, 16.5), (45.2, -63.6, 12.8)]                 # breadths: the usual ones (about 50 between the chin's foramina, 98 across the angles)
# the ramus: a plane closing in toward the chin and leaning in toward the angle (120 across the condyles, 98 across the angles);
# its outline in (z, y) as traced
O = np.array([49.0, -12.0, 10.5])
ES = sdf.unit((-0.20, 0.0, 0.98))
ET = np.array([0.065, 1.0, 0.0])
OUTLINE = [(5.5, -6.0), (4.9, -9.2), (6.5, -15.7), (8.4, -21.4), (9.6, -26.2), (11.6, -31.2), (12.2, -37.4), (11.6, -45.0),
           (11.1, -51.5), (11.0, -57.5), (12.6, -63.0), (16.4, -67.6), (21.9, -71.0), (36.4, -77.1), (46.0, -81.0),      # the angle: a round turn of 9 to 10 mm, not a corner
           (50.0, -69.0), (48.5, -58.0), (44.8, -47.3), (46.1, -35.4), (47.2, -26.5), (47.9, -18.3), (46.2, -11.9),
           (43.1, -8.2), (39.5, -5.5), (36.6, -6.2), (35.5, -8.1), (32.9, -15.1), (30.0, -19.9), (25.8, -21.4),
           (21.7, -19.7), (17.9, -15.9), (15.1, -11.4), (12.9, -7.1), (11.5, -5.0)]
CONDYLE = {"centre": (50.6, -5.9, 8.9), "half": (9.0, 4.3, 4.1), "turn": -15.0}     # its neck spans z 5.5 to 12.2 on the plate


SECTIONS0 = [list(q) for q in MB.SECTIONS]


def use():
    """Put these lines in place of mandible.py's own."""
    MB.T, MB.B, MB.O, MB.ES, MB.ET, MB.OUTLINE, MB.CONDYLE = T, B, O, ES, sdf.unit(ET - (ET @ ES) * ES), OUTLINE, CONDYLE
    S = [list(q) for q in SECTIONS0]
    for i, k in ((5, 0.72), (6, 0.78)):                      # the two sections that climb the ramus: a ramus is 5 to 6 mm thick, not 7
        S[i] = [(o * k, u) for o, u in S[i]]
    MB.SECTIONS = S


def build(h=0.5, log=print):
    use()
    on = MB.on_ramus
    F = sdf.Field([0, -99, -1], [64, 5, 101], h)
    line = MB.body_line()
    M, up, a, b, tp, uu = line
    F.add(sdf.Sweep(M, up, MB.outlines(uu, a)))
    Q = sdf.spline(np.array(OUTLINE, float), 1.5, closed=True)
    st = np.stack([(Q[:, 0] - O[2]) / MB.ES[2], (Q[:, 1] - O[1]) / MB.ET[1]], axis=1)
    F.add(sdf.Plate(st, O, MB.ES, MB.ET, 1.3, 1.3), k=5.0)                 # thin in the middle; the borders below thicken it
    back = sdf.spline([on(z, y) for z, y in [(9.0, -14), (12.2, -24), (14.8, -33), (15.3, -42), (14.6, -52), (14.2, -60)]], 2.0)
    F.add(sdf.Tube(back, [(0, 2.6), (0.25, 3.2), (0.6, 3.3), (1, 4.0)], [(0, 2.5), (0.5, 2.3), (1, 2.2)], up=MB.ES), k=5.0)     # thick rounded hind border
    front = [on(z, y) for z, y in [(43.3, -10.5), (45.0, -18.5), (44.4, -27), (43.3, -36), (42.4, -45)]]
    p1, _ = MB.surface_point(line, 6.9, 0.60, True, -2.4)
    p2, _ = MB.surface_point(line, 6.1, 0.42, True, -2.5)
    p3, _ = MB.surface_point(line, 5.2, 0.30, True, -2.5)
    front = sdf.spline(front + [p1, p2, p3], 2.0)                           # the front border runs on as the oblique line
    F.add(sdf.Tube(front, [(0, 1.8), (0.35, 2.6), (0.6, 3.0), (1, 1.6)], [(0, 1.4), (0.35, 1.8), (0.6, 1.8), (1, 0.9)], up=MB.ES), k=5.0)
    R = np.stack([MB.ES, MB.ET, np.cross(MB.ES, MB.ET)], axis=1)
    F.add(sdf.Ellipsoid(on(19.5, -62.0, 0.6), (9.0, 7.5, 1.7), R), k=5.0)   # the angle, turned a little outward for the masseter
    F.add(sdf.Ellipsoid(on(21.0, -60.0, -0.8), (7.5, 6.5, 1.5), R), k=5.0)  # and roughened inside for the medial pterygoid
    F.add(sdf.Tube(sdf.spline([on(9.5, -11, -0.8), on(16.0, -22, -1.2), on(24.5, -31, -1.4)], 2.0), [(0, 3.6), (1, 2.6)], [(0, 1.8), (1, 1.2)], up=MB.ES), k=5.0)
    F.add(sdf.Tube(sdf.spline([on(41.5, -9, -0.6), on(43.0, -20, -1.0), on(42.5, -32, -1.3), on(41.5, -43, -1.6)], 2.0), [(0, 1.8), (0.5, 2.8), (1, 3.0)], [(0, 1.1), (0.5, 1.4), (1, 1.6)], up=MB.ES), k=5.0)
    c = CONDYLE
    F.add(sdf.Tube(sdf.spline([on(8.9, -6.5), on(9.3, -15.0)], 2.0), [(0, 3.3), (1, 3.4)], [(0, 6.2), (1, 2.4)], up=MB.ES), k=3.5)
    F.add(sdf.Ellipsoid(c["centre"], c["half"], sdf.rot((0, 1, 0), c["turn"])), k=2.5)
    F.cut(sdf.Ellipsoid(on(13.5, -8.6, -1.6), (3.0, 3.2, 2.2)), k=1.5)      # pterygoid fovea on the front of the neck
    sp, w = MB.surface_point(line, 0.0, 0.33, False, -0.6)
    F.add(sdf.Ellipsoid(sp, (1.6, 2.4, 1.5)), k=1.5)                        # mental spines
    F.add(sdf.Ellipsoid(on(28.5, -33.5, -2.0), (1.5, 2.6, 2.4)), k=2.0)     # lingula, then the mandibular foramen behind it
    F.cut(sdf.Tube(np.array([on(23.8, -31.0, -5.0), on(26.5, -37.0, -1.2)]), 1.6), k=0.8)
    mf, w = MB.surface_point(line, 4.05, 0.38, True, 0.0)
    F.cut(sdf.Tube(np.array([mf + 2.5 * w + np.array([0, 1.0, -1.0]), mf - 2.2 * w]), 1.3), k=0.6)   # mental foramen: under the second premolar, below its root's tip
    dg, w = MB.surface_point(line, 1.3, 0.10, False, 0.0)
    F.cut(sdf.Ellipsoid(dg - 1.5 * w, (6.0, 3.0, 3.2)), k=2.5)              # digastric fossa
    sdf.ease_midline(F)
    frames = skull.sockets(LOWER_LINE, LOWER_T, False, start=-0.6)
    teeth.seat(F, frames, False)
    return F, {"mental foramen": np.round(mf, 1).tolist(), "sockets": frames}
