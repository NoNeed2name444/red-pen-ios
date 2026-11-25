"""foot_frame.py: one assembly frame for the right tarsus, from Gray's whole-foot plates (Anatomy of the Human Body, 1918,
public domain): Fig. 268 (bones of the right foot, dorsal surface), Fig. 290 (skeleton of foot, medial aspect), Fig. 291
(lateral aspect); Fig. 269 (plantar) only as a cross-check. Data and small accessors only: nothing here builds a bone.
Pixels are those of the Wikimedia files in refs_foot (268: 638 x 1195, 290: 500 x 189, 291: 500 x 179).

THE FRAME (the "plan frame"): x medial, z forward, millimetres, exactly as the bones already use it:
    x = (u - 377) 0.208,  z = (v - 440) 0.208   in Fig. 268's pixels (the navicular frame of midfoot.py / cuneiforms.py),
and y the normal of Fig. 268's page, toward the viewer ("up"). The origin is the navicular's middle; y = 0 where Fig. 290's
pixel (210, 80) falls, the convention midfoot.NAV_SIDE already uses.

What the registration found (T-foot-frame, 25 Nov): the side plates' vertical is NOT this y. Fig. 290 and 291 are drawn
standing (heel and the metatarsal heads on one horizontal line); Fig. 268 looks at the dorsum along a line tilted forward.
Seen in this frame the side plates are turned in their own plane: Fig. 290 by 18.8 degrees, Fig. 291 by 12.3 (leave-one-
landmark-out range 13.7..23.4 and 7.4..17.0). Every number read off Fig. 290/291 as if their vertical were this y (NAV_SIDE,
cuneiforms.HEIGHT, CUBOID_AT's height, the talus's plate fit) is off by that turn: up to 7 mm over a 25 mm lever.
Use side_to_frame() / project() below to carry side-plate readings into the frame. STAND turns the frame to standing
(y vertical as Fig. 290/291 draw it), taking the mean of the two side plates (15.5 degrees).

Fitting: landmarks seen in two or three plates (LANDMARKS), each coordinate weighted by how sharply its plate fixes it;
unknowns: per side plate an in-plane turn, a scale and an origin, and each landmark's 3D position. Fig. 268 is the gauge
(its 0.208 mm a pixel and axes are kept). Free tilt or yaw of the side views was tried and not kept: it did not lower the
residuals reliably and swung by tens of degrees between leave-one-out runs.
"""
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------------------------------------------- plates
# Fig. 268: the gauge. u = 377 + x / 0.208, v = 440 + z / 0.208 (y is along the line of sight).
FIG268 = dict(s=0.208, u0=377.0, v0=440.0)
# Fig. 290 (medial) and 291 (lateral): rows of R are the plate's right, up and toward-the-eye directions in the frame;
# u = u0 + (R[0] . P) / s, v = v0 - (R[1] . P) / s. s: mm a pixel (0.49 was assumed so far, from the calcaneus at 79 mm:
# the landmarks give 0.485 and 0.483, i.e. the side plates' bones 1.0 to 1.5 % longer than read; within the leave-one-
# out spread 0.457..0.504, so no rescale is recommended).
FIG290 = dict(R=[[0.0, 0.32159, 0.94688], [0.0, 0.94688, -0.32159], [-1.0, 0.0, 0.0]], s=0.48542, u0=204.03, v0=80.0,
              turn_deg=18.76)
FIG291 = dict(R=[[0.0, -0.21333, -0.97698], [0.0, 0.97698, -0.21333], [1.0, 0.0, 0.0]], s=0.4828, u0=300.2, v0=70.26,
              turn_deg=12.32)
PLATES = {"Gray268": FIG268, "Gray290": FIG290, "Gray291": FIG291}
STAND_DEG = 15.5      # frame -> standing: a turn about x, the toes' end of the frame's z going down by this much

# Landmarks: {fig: (u, v, sigma_u, sigma_v)} in plate pixels; sigma (px) says how sharply that plate fixes that coordinate
# (a flat top fixes height, not place along the foot; a plan point picked "mid-trochlea" fixes little). AT: the fitted
# position in the frame (mm). RESID: residual in mm on the coordinates the plate fixes (sigma <= 5 px), (du, dv).
LANDMARKS = {
    "heel back":           ({"268": (232, 18, 15, 3), "290": (5, 109, 2, 10), "291": (497, 133, 2, 10)},   (-30.2, -44.7, -87.5)),
    "heel low":            ({"290": (60, 173, 8, 2), "291": (450, 176, 8, 2)},                             (0.0, -65.2, -54.9)),
    "trochlea top":        ({"290": (127, 3, 10, 2), "291": (361, 7, 10, 2)},                              (0.0, 23.3, -43.2)),
    "talonavicular dorsal":({"268": (360, 405, 15, 4), "290": (204, 44, 3, 3), "291": (305, 32, 3, 3)},    (-3.5, 17.1, -6.7)),
    "cun1 back-top":       ({"268": (358, 495, 5, 4), "290": (240, 71, 3, 3)},                             (-4.0, 9.8, 12.4)),
    "cun1-MT1 dorsal":     ({"268": (332, 612, 8, 5), "290": (282, 80, 3, 3)},                             (-9.4, 12.2, 35.8)),
    "MTP1":                ({"268": (450, 903, 10, 5), "290": (380, 145, 3, 8)},                           (15.2, -7.0, 95.1)),
    "MT5 tuberosity tip":  ({"268": (136, 449, 3, 3), "291": (304, 137, 3, 3)},                            (-50.1, -31.9, 2.4)),
    "talus back":          ({"268": (300, 160, 20, 5), "290": (68, 52, 4, 8), "291": (437, 60, 4, 8)},     (-16.0, -12.3, -60.8)),
    "calcaneocuboid dorsolateral": ({"268": (190, 378, 5, 4), "291": (334, 76, 3, 4)},                     (-38.9, -6.5, -13.5)),
    "navicular tuberosity":({"268": (447, 432, 4, 6), "290": (188, 106, 5, 5)},                            (14.6, -14.5, -2.0)),
    "navicular top":       ({"290": (214, 42, 8, 2), "291": (297, 30, 8, 2)},                              (0.0, 19.2, -1.7)),
    "cun2 top":            ({"290": (250, 51, 8, 2), "291": (265, 36, 8, 2)},                              (0.0, 20.1, 15.0)),
    "navicular-cun3-cuboid point": ({"268": (270, 441, 3, 3), "291": (297, 70, 3, 3)},                     (-22.3, 0.5, 0.4)),
}
# Residuals (mm) on well-fixed coordinates: 268 rms 1.0 (worst 2.6, the talus's back), 290 within 2.7 (cun1 back-top
# -2.7 along the foot), 291 within 2.7 (MT5 tuberosity). The one landmark beyond 2 sigma is the talus's back: Fig. 268
# puts it 2.6 mm further forward than the frame, Fig. 290 4.6 and Fig. 291 4.1 mm further back: Fig. 268's talus is
# some 7 mm shorter behind than the side plates' (different specimens or the posterior process hidden in the plan).
RESID_RMS_MM = {"Gray268": 1.0, "Gray290": 1.3, "Gray291": 1.2}


def project(fig, P):
    """Frame points (..., 3) mm to plate pixels (..., 2)."""
    P = np.asarray(P, float); p = PLATES[fig]
    if fig == "Gray268":
        return np.stack([p["u0"] + P[..., 0] / p["s"], p["v0"] + P[..., 2] / p["s"]], -1)
    R = np.asarray(p["R"]); E = P @ R.T
    return np.stack([p["u0"] + E[..., 0] / p["s"], p["v0"] - E[..., 1] / p["s"]], -1)


def side_to_frame(fig, uv, depth=0.0):
    """A side plate's pixel (u, v) as a frame point, `depth` mm toward the eye from the plane through the origin."""
    p = PLATES[fig]; R = np.asarray(p["R"]); uv = np.asarray(uv, float)
    a = (uv[..., 0] - p["u0"]) * p["s"]; b = (p["v0"] - uv[..., 1]) * p["s"]
    return a[..., None] * R[0] + b[..., None] * R[1] + np.asarray(depth, float)[..., None] * R[2]


def plan_to_frame(uv):
    """Fig. 268 pixels to (x, z) mm."""
    uv = np.asarray(uv, float); return np.stack([(uv[..., 0] - 377.0) * 0.208, (uv[..., 1] - 440.0) * 0.208], -1)


def stand():
    """The rotation taking frame vectors to standing ones (y vertical as Fig. 290/291 draw it)."""
    a = np.radians(STAND_DEG); c, s = np.cos(a), np.sin(a)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


# ------------------------------------------------------------------------------------------------------- target poses
# Each bone as built (its own field, its own frame) fitted rigidly to its outlines in Fig. 268, 290 and 291 through the
# registration above: the traced outline points' distance to the bone's silhouette edge (one way, so hidden parts do not
# count) plus a penalty for silhouette lying outside the plate's foot. frame point = R @ bone point + t.
# CURRENT is how the bone stands now (for comparison); dR = degrees about x, y, z through the bone's centroid, dt = mm
# the centroid moves (target - now). fit: mean outline distance (mm) per plate at the target (now in brackets).
# Confidence: Fig. 268 is read to 0.2 mm a pixel and fixes x, z and the turn about y; the side plates (0.48 mm a pixel,
# inner joint lines read by hand) fix y and the nod to within about 2 mm and 4 degrees; the roll about z of a bone seen
# in only one side plate (cuboid, third) is the weakest.
TARGET = {
    "calcaneus": dict(R=[[0.9852, 0.0851, -0.1484], [-0.0196, 0.9179, 0.3963], [0.1700, -0.3876, 0.9060]], t=[-19.49, -70.74, -78.39],
                      current=None, fit={"Gray268": 2.28, "Gray290": 2.35, "Gray291": 2.35},
                      note="not placed in the foot yet; its front up 23 deg in this frame (8 deg standing), turned 8.5 deg laterally"),
    "talus": dict(R=[[0.9969, -0.0754, -0.0212], [0.0784, 0.9638, 0.2549], [0.0012, -0.2558, 0.9667]], t=[-8.82, -20.14, -58.76],
                  current="navB/a4.py: turn -5 deg, t (-8.17, -13.21, -59.99), seated by its head (midfoot.NAV_HEAD_*)",
                  dR=(-14.6, -5.6, 5.1), dt=(-5.6, 0.5, -4.8), fit={"Gray268": 1.16, "Gray290": 2.99, "Gray291": 2.24},
                  now={"Gray268": 3.60, "Gray290": 3.95, "Gray291": 4.27},
                  note="head centre at target (-7.5, 5.9, -28.4) against the hollow's (-1.6, 4.0, -24.4)"),
    "navicular": dict(R=[[0.9978, 0.0059, -0.0662], [-0.0018, 0.9982, 0.0608], [0.0664, -0.0605, 0.9960]], t=[-0.73, 0.41, 1.35],
                      current="identity (it defines the frame)", dR=(-3.5, -3.8, -0.2), dt=(-0.7, 0.4, 1.1),
                      fit={"Gray268": 0.91, "Gray290": 1.80, "Gray291": 2.76}, now={"Gray268": 0.59, "Gray290": 2.50, "Gray291": 2.78},
                      note="within the side plates' reading error: keep it where it is"),
    "cuboid": dict(R=[[0.9682, 0.2487, -0.0280], [-0.2426, 0.9602, 0.1383], [0.0613, -0.1271, 0.9900]], t=[-41.54, -25.30, -10.08],
                   current="cuneiforms.CUBOID_AT (-41.9, -12.0, -10.82), no turn", dR=(-7.7, -2.6, -14.3), dt=(2.2, -14.4, -0.1),
                   fit={"Gray268": 1.39, "Gray291": 2.36}, now={"Gray268": 2.07, "Gray291": 7.89},
                   note="translation alone gets only 5.7 mm lower and leaves Fig. 291 at 5.8 mm: the roll (dorsum facing up and "
                        "lateral) is needed, but is fixed by one side plate only"),
    "first": dict(R=[[0.9987, -0.0447, -0.0241], [0.0442, 0.9989, -0.0180], [0.0248, 0.0170, 0.9996]], t=[-0.09, -1.57, 22.81],
                  current="cuneiforms.PLACE['first']", dR=(1.0, -1.4, 2.6), dt=(0.1, 3.3, 1.5),
                  fit={"Gray268": 0.71, "Gray290": 2.26}, now={"Gray268": 0.85, "Gray290": 2.65}),
    "second": dict(R=[[0.9958, 0.0110, 0.0905], [-0.0141, 0.9993, 0.0339], [-0.0900, -0.0350, 0.9953]], t=[-13.85, 7.28, 16.77],
                   current="cuneiforms.PLACE['second']", dR=(-2.0, 5.2, -0.7), dt=(-0.2, 2.3, -0.1),
                   fit={"Gray268": 0.71, "Gray290": 3.11, "Gray291": 2.79}, now={"Gray268": 0.76, "Gray290": 3.11, "Gray291": 3.99}),
    "third": dict(R=[[0.9992, 0.0200, -0.0345], [-0.0175, 0.9973, 0.0712], [0.0358, -0.0706, 0.9969]], t=[-27.17, 7.35, 15.28],
                  current="cuneiforms.PLACE['third']", dR=(-4.1, -2.0, -1.1), dt=(-0.9, 6.3, 1.8),
                  fit={"Gray268": 0.80, "Gray291": 3.35}, now={"Gray268": 0.92, "Gray291": 3.70},
                  note="only Fig. 291's upper half shows it (the cuboid hides the rest); at this target and the cuboid's the "
                       "two no longer face each other (38 mm2): settle the two together, held in contact"),
}


def pose(name):
    """(R, t) of a bone's target: frame point = R @ bone point + t."""
    T = TARGET[name]; return np.asarray(T["R"], float), np.asarray(T["t"], float)


# ------------------------------------------------------------------------------------------------- outlines and joints
# Fig. 268 outlines (pixels): the navicular, cuboid and cuneiforms are those already in midfoot.py (NAV_PLAN, CUB_PLAN
# from pixel (190, 388)) and cuneiforms.py (PLAN); new here, read under a pixel grid: the calcaneus's visible border
# (the medial border to where the talus covers it, the tuberosity's top edge, the lateral border with the peroneal
# trochlea to the calcaneocuboid joint) and the talus (navB/talplace3.py's reading: back, medial side, neck and head).
PLAN268 = {
    "calcaneus": [[(372, 77), (373, 90), (367, 107), (357, 123), (352, 140)],
                  [(353, 47), (320, 33), (287, 25), (253, 18), (237, 17), (230, 20), (225, 33), (223, 67), (220, 93), (212, 103),
                   (207, 117), (207, 140), (208, 160), (207, 187), (203, 213), (193, 253), (180, 277), (193, 320), (188, 333),
                   (187, 353), (190, 373)],
                  [(353, 47), (358, 50), (367, 60), (372, 77)]],
    "talus": [[(272, 166), (290, 163), (310, 165), (330, 166), (350, 165), (365, 163), (393, 182), (396, 210), (395, 250), (397, 290),
               (404, 322), (418, 330), (426, 345), (428, 362), (425, 380), (418, 393), (400, 402), (380, 407), (350, 408), (330, 404),
               (312, 398)]],
}
# Fig. 268 joint lines (pixels): the line midway between the two neighbours' traced borders where they run within 6 px
# (1.2 mm). The median distance apart of the two traced borders is given: it is how far the existing tracings disagree.
JOINTS268 = {
    ("talus", "navicular"): [(423, 389), (414, 395), (404, 400), (393, 404), (383, 406), (371, 408), (360, 407), (348, 407),
                             (337, 404), (325, 402), (314, 399)],                                              # 0.7 px apart
    ("navicular", "first"): [(426, 476), (416, 480), (399, 485), (388, 489), (377, 492), (366, 495), (361, 496)],  # 3.3 px
    ("navicular", "second"): [(362, 495), (353, 489), (343, 483), (332, 479), (321, 476), (310, 474), (299, 472), (293, 472)],  # 2.2 px
    ("navicular", "third"): [(291, 471), (284, 462), (278, 453), (271, 444), (270, 439)],                        # 1.4 px
    ("navicular", "cuboid"): [(271, 439), (275, 434), (281, 425), (287, 415), (292, 405)],                       # 4.1 px
    ("first", "second"): [(362, 496), (357, 506), (353, 517), (348, 527), (342, 537), (334, 546), (328, 555), (325, 560)],  # 1.3 px
    ("second", "third"): [(269, 557), (265, 547), (267, 536), (268, 525), (270, 513), (273, 502), (276, 492), (283, 482),
                          (290, 474)],                                                                            # 0.0 px
    ("third", "cuboid"): [(269, 441), (260, 448), (251, 455), (242, 463), (234, 471), (228, 479), (223, 490), (218, 500),
                          (216, 512), (215, 523), (215, 533)],                                                    # 4.9 px
    ("calcaneus", "cuboid"): [(190, 377), (215, 378), (240, 379), (265, 380), (290, 380)],    # under the EDB origin's ring
    # the tarsometatarsal joints, as far as the bases are drawn (the bones' front borders; the base sits in front)
    ("first", "MT1"): [(419, 592), (414, 602), (402, 602), (390, 608), (375, 617), (360, 622), (345, 622), (335, 617), (328, 605)],
    ("second", "MT2"): [(325, 558), (315, 562), (299, 566), (285, 566), (275, 562), (267, 554)],
    ("third", "MT3"): [(262, 566), (255, 568), (245, 560), (231, 552), (221, 542)],
    ("cuboid", "MT4-5"): [(214, 533), (201, 526), (181, 511), (167, 497), (160, 480)],
}
MT5_TUBEROSITY_268 = (136, 449)        # its tip, behind the cuboid's lateral end (Peronaeus brevis)

# Side plates (pixels): joint lines read by hand under a pixel grid (5 to 6 times enlarged); the outer edges are the
# plate's own silhouette (ink against the page), kept in traces/foot_frame.npz as "<fig>_<bone>_<k>" arcs.
JOINTS_SIDE = {
    "Gray290": {   # medial aspect: toes to the right
        ("talus", "navicular"): [(204, 44), (202, 60), (200, 77), (195, 85), (190, 92), (186, 100)],
        ("talus", "calcaneus"): [(122, 93), (142, 103), (158, 106)],                 # over the sustentaculum
        ("talus", "below"): [(150, 98), (160, 100), (170, 100), (178, 98), (185, 95)],   # the head's underside
        ("navicular", "below"): [(186, 100), (186, 106), (190, 112), (198, 116), (207, 116)],  # the tuberosity
        ("navicular", "first"): [(239, 71), (238, 75), (233, 85), (225, 95), (217, 103), (210, 110), (207, 115)],
        ("navicular", "second"): [(232, 51), (237, 60), (239, 68)],
        ("first", "second"): [(240, 71), (250, 67), (255, 67), (267, 68), (278, 75), (282, 80)],
        ("first", "MT1"): [(282, 80), (280, 87), (273, 95), (265, 102), (260, 108), (258, 118), (255, 128), (252, 135)],
    },
    "Gray291": {   # lateral aspect: toes to the left
        ("talus", "navicular"): [(305, 32), (312, 40), (315, 57), (318, 70)],
        ("talus", "calcaneus"): [(318, 70), (322, 73), (334, 76)],
        ("talus", "calcaneus", "posterior"): [(437, 60), (420, 60), (405, 62), (392, 70), (375, 78)],
        ("calcaneus", "cuboid"): [(334, 76), (335, 81), (335, 95), (334, 109), (333, 119)],
        ("navicular", "cuboid"): [(319, 69), (311, 70), (299, 70)],
        ("navicular", "third"): [(281, 35), (284, 45), (290, 53), (296, 62), (297, 69)],
        ("third", "cuboid"): [(297, 69), (295, 73), (287, 81), (279, 87)],
        ("second", "third"): [(250, 61), (257, 58), (273, 54), (281, 50)],
        ("third", "MT3"): [(271, 93), (265, 89), (257, 81), (251, 75), (247, 67), (250, 61)],
        ("cuboid", "MT4-5"): [(303, 115), (291, 109), (281, 105), (273, 97), (281, 85), (289, 77)],
        ("MT5", "tuberosity"): [(304, 137)],
    },
}
# Fig. 290's front border of the navicular (its joint with the first cuneiform) as read here lies up to 9 px (4 mm) in
# front of midfoot.NAV_SIDE's at mid height (v 70 to 85): the existing reading follows a line inside the bone.


def _npz():
    return np.load(os.path.join(HERE, "traces", "foot_frame.npz"))


def outlines(fig, bone):
    """A bone's traced outline pieces in a plate, as a list of (n, 2) pixel arrays (open polylines; a closed outline
    repeats its first point)."""
    if fig == "Gray268":
        if bone in PLAN268: return [np.asarray(p, float) for p in PLAN268[bone]]
        import midfoot, cuneiforms
        if bone == "navicular": P = [(377 + x / 0.208, 440 + z / 0.208) for x, z in midfoot.NAV_PLAN]
        elif bone == "cuboid": P = [(190 + x / 0.208, 388 + z / 0.208) for x, z in midfoot.CUB_PLAN]
        else: P = [(377 + x / 0.208, 440 + z / 0.208) for x, z in cuneiforms.PLAN[bone]]
        return [np.asarray(P + P[:1], float)]
    tr = _npz(); f = fig[4:]
    out = [tr[k].astype(float) for k in sorted(tr.files) if k.startswith("%s_%s_" % (f, bone))]
    out += [np.asarray(p, float) for key, p in JOINTS_SIDE[fig].items() if bone in key[:2] and len(p) > 1]
    return out


def joint(fig, a, b):
    """The traced joint line between bones a and b in a plate (pixels), or None."""
    J = JOINTS268 if fig == "Gray268" else JOINTS_SIDE[fig]
    for key, p in J.items():
        if set(key[:2]) == {a, b}: return np.asarray(p, float)
    return None
