"""cuneiforms.py: the three cuneiform bones of the right foot (first or medial, second or intermediate, third or
lateral), built as midfoot.py builds the cuboid and the navicular: from Gray's plates (Anatomy of the Human Body,
1918, public domain) and his text. No scan and no other model is used.

Each bone has two plates of its own, drawn from nearly opposite sides, all of the LEFT bone (so each is written as a
mirror view of the right-hand model: the picture's right is minus up x eye):
  first:  Fig. 278 "antero-medial view", Fig. 279 "postero-lateral view"
  second: Fig. 280 "antero-medial view", Fig. 281 "postero-lateral view"
  third:  Fig. 282 "postero-medial view", Fig. 283 "antero-lateral view"
Two such outlines fix each bone's side profile and say little of its breadth across the line of sight. That comes from
Fig. 268 (the right foot from above, 0.208 mm a pixel, the scale at which the heel bone is 79 mm, as in midfoot.py),
which gives each bone's plan and where it lies beside the navicular and the cuboid, and from Gray's text, which says
which way each wedge points: "The plantar surface is rough, and forms the base of the wedge ... The dorsal surface is
the narrow end of the wedge, and is directed upward and lateralward" (first); "of very regular wedge-like form, the
thin end being directed downward" (second); "wedge-shaped, the base being uppermost ... The plantar surface is a
rounded margin" (third). So each body is lofted from cross-sections (a wedge across x and y at every z, its two sides
read off the plan's borders), and then held within the two plates' outlines.

Frame of each bone (right bone, as it lies in the foot): x medial, y up, z forward, millimetres, origin at the middle
of the bone. PLACE gives where that origin lies in the navicular's frame (midfoot.navicular: x = (u - 377) 0.208,
z = (v - 440) 0.208 in Fig. 268's pixels, y as Fig. 290 has it), so the three sit beside the navicular and the cuboid
(the cuboid's own frame is CUBOID_AT from the navicular's: its plan origin is Fig. 268's pixel (190, 388)).
"""
import os
import numpy as np
from scipy import ndimage as ndi
import sdf
import platematch as pm
from foot import _ss, _read, _pixels, _cut, _tube, _one_piece, _marks_map
from midfoot import _mask, _shown, _lay, _pits
from sdf import Ellipsoid, Field, rot

HERE = os.path.dirname(os.path.abspath(__file__))
PX268 = 0.208


def _p268(pts):
    """Fig. 268 pixels as (x, z) mm in the navicular's frame."""
    return [((u - 377.0) * PX268, (v - 440.0) * PX268) for u, v in pts]


# Fig. 268 (the right foot from above), each bone's outline read under a 10 pixel grid. The first cuneiform shows its
# dorsal edge laterally and the broad medial surface, which faces medially and up, out to its plantar-medial border;
# the second and third their dorsal surfaces (the bases of their wedges), the third's "postero-lateral angle prolonged
# backward" along the navicular's lateral end and the cuboid.
PLAN = {
    "first": _p268([(359, 498), (372, 493), (386, 487), (400, 481), (413, 477), (424, 478), (428, 490), (427, 505), (425, 522),
                    (424, 540), (421, 560), (419, 578), (419, 592), (414, 602), (402, 602), (390, 608), (375, 617), (360, 622),
                    (345, 622), (335, 617), (328, 605), (325, 585), (325, 565), (330, 550), (340, 538), (350, 522), (356, 508)]),
    "second": _p268([(291, 474), (303, 474), (315, 475), (327, 478), (339, 482), (351, 490), (359, 496), (358, 502), (353, 520),
                     (345, 534), (335, 546), (325, 558), (315, 562), (299, 566), (285, 566), (275, 562), (267, 554), (265, 546),
                     (267, 534), (269, 520), (272, 506), (275, 494), (281, 484)]),
    "third": _p268([(269, 441), (280, 457), (289, 473), (281, 484), (275, 494), (272, 506), (269, 520), (267, 534), (265, 546),
                    (267, 554), (262, 566), (255, 568), (245, 560), (231, 552), (221, 542), (215, 530), (213, 514), (215, 500),
                    (221, 486), (229, 472), (239, 462), (251, 452), (261, 444)]),
}
# Heights in the navicular's frame (top, bottom of the bone), from Fig. 290 (the first: its medial surface stands from
# 14 mm above the navicular's middle to 20 below, the bone some 34 mm high) and Fig. 291 (the third), and the plates'
# own proportions at the scale the plan gives (the second is the lowest of the three, its dorsal surface the
# summit of the transverse arch; the third between).
HEIGHT = {"first": (14.7, -24.6), "second": (16.0, -6.0), "third": (13.5, -11.5)}
# The wedge: at the top (t = 0) and at the bottom (t = 1) of the bone, where its lateral and medial sides lie, as
# shares of the plan's breadth at that z (0 its lateral border, 1 its medial).
WEDGE = {
    "first": ((0.0, 0.30), (0.18, 1.0)),       # the dorsal edge 6 mm broad over the lateral border; the plantar base the whole plan
    "second": ((0.0, 1.0), (0.64, 0.86)),      # base above the whole plan; the thin sharp edge below
    "third": ((0.0, 1.0), (0.52, 0.84)),       # base above; the rounded plantar margin below, under its medial half
}


def _centre(name):
    P = np.asarray(PLAN[name]); t, b = HEIGHT[name]
    return np.array([0.5 * (P[:, 0].min() + P[:, 0].max()), 0.5 * (t + b), 0.5 * (P[:, 1].min() + P[:, 1].max())])


# (set by the plan, the three stand 1 to 5 mm short of the built navicular's facets: Fig. 268's outlines are read off
# the dorsal surfaces, the joints lie a little behind them below. Each is moved back toward the navicular by what the
# nearest 200 points of the two surfaces ask, as far as the bone beside it allows. The third asks 5 mm medially and
# gets none: the second stands there, and moved so far the third loses its medial face to it. It is left 5 mm off
# the navicular's lateral end, an open defect: Fig. 268 draws it lateral of where the built navicular ends)
NUDGE = {"first": (0.0, 0.0, -1.5), "second": (0.9, 0.0, -1.6), "third": (0.3, 0.0, -1.0)}
PLACE = {n: _centre(n) + np.array(NUDGE[n]) for n in PLAN}
# the cuboid's frame (midfoot.cuboid) in the navicular's: Fig. 268 puts its origin at pixel (190, 388); its height
# is set so its facet for the third cuneiform lies against the third's (A4 in the task notes)
# (its height and side: set where the cuboid's medial surface lies against the third's lateral surface without passing
# far into it (scratch cubscan.py: the deepest overlap of the two eased solids, before either is cut, 0.6 mm), 12 mm
# below the navicular's middle and 3 mm lateral of where Fig. 268 alone puts it. Fig. 268's two outlines are of the
# dorsal surfaces; the cuboid's lower medial part (CUB_SOLE) reaches further medially, under the third's sloping
# lateral surface, and set by the dorsal plan alone it ran 3 to 4 mm into the third)
CUBOID_AT = np.array([(190.0 - 377.0) * PX268 - 3.0, -12.0, (388.0 - 440.0) * PX268])

# The plates. s: mm a pixel (the six are printed at one scale: 0.074 mm a pixel, which makes the
# first cuneiform as high as Fig. 290 draws it, 39 mm); u0, v0: where the bone's
# middle falls; pose: nod, turn, roll (degrees), scale factor, shift right and down (pixels). The turn is how far the
# eye stands toward the front ("antero-") or the back ("postero-") from straight medial or lateral; the nod how far
# above. Each bone's first plate is set by judgment (the turn from how broad the end face it shows is beside the side
# face; the nod from the strip of dorsal surface it shows) and shifted on to the loft; the second is then fitted, nod,
# turn and shift, to the loft held within the first plate's outline (scratch fitpair.py), so the two agree.
S0 = 0.074
VIEWS = {
    "first": [
        dict(fig="Gray278", cap="antero-medial view", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=S0, u0=231, v0=452,
             pose=(5.00, -28.00, 0.00, 1.0, 3.57, -5.58),
             erase=[[(386, 150), (410, 150), (410, 192), (386, 192)], [(270, 712), (300, 712), (300, 745), (270, 745)]]),
        dict(fig="Gray279", cap="postero-lateral view", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=S0, u0=270, v0=450,
             pose=(0.02, -19.74, 0.00, 1.0, -5.63, -3.11),
             erase=[[(436, 690), (475, 690), (475, 745), (436, 745)], [(122, 150), (148, 150), (148, 190), (122, 190)],
                    [(318, 175), (345, 175), (345, 246), (318, 246)]]),
    ],
    "second": [
        dict(fig="Gray280", cap="antero-medial view", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=S0, u0=214, v0=258,
             pose=(14.00, -20.00, 0.00, 1.0, -1.42, 27.67)),
        dict(fig="Gray281", cap="postero-lateral view", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=S0, u0=170, v0=230,
             pose=(12.0, -21.74, 0.00, 1.0, 16.11, 24.63)),
    ],
    "third": [
        dict(fig="Gray282", cap="postero-medial view", right=(0, 0, 1), up=(0, 1, 0), eye=(1, 0, 0), s=S0, u0=550, v0=340,
             pose=(14.00, 14.00, 0.00, 1.0, -11.63, -0.40),
             # the two label lines "For 2nd metatarsal" meet right of the bone and close a triangle on to it
             erase=[[(750, 232), (725, 290), (714, 305), (714, 322), (680, 392), (660, 432), (660, 470), (790, 470), (790, 232)]]),
        dict(fig="Gray283", cap="antero-lateral view", right=(0, 0, -1), up=(0, 1, 0), eye=(-1, 0, 0), s=S0, u0=405, v0=320,
             pose=(12.0, 3.00, 0.00, 1.0, 22.86, 14.57),
             # the pin standing on the top border, and the label line "For 3rd metatarsal" running on below the bone
             erase=[[(511, 90), (533, 90), (533, 166), (511, 166)], [(228, 432), (276, 432), (262, 512), (228, 512)]]),
    ],
}

# The joint surfaces each plate shows, traced in its own pixels along the engraved border line (not the outline), each
# with its own gentle curvature (mm at its middle: + convex, - concave), as the plate's shading and Gray's text give it.
# Points are kept as drawn (no spline): the borders keep the engraver's irregularity; only the pixel steps are eased.
FACETS = {
    "Gray278": [        # "the anterior surface, kidney-shaped ... for the first metatarsal": a tall crescent along the front, its border a lip
        ([(397, 230), (412, 224), (425, 228), (430, 262), (432, 330), (430, 420), (428, 500), (424, 560), (418, 600), (408, 620),
          (392, 606), (372, 576), (355, 540), (342, 502), (330, 462), (320, 420), (318, 380), (322, 345), (336, 316), (360, 290),
          (380, 262)], 0.20)],
    "Gray279": [        # the L-shaped surface along the superior and posterior borders: a broad squarish upper field, its front part
        # for the second metatarsal parted by a faint line from the horizontal limb (second cuneiform); the vertical limb
        # down the posterior border, its inner edge wavy, ending obliquely against the navicular border
        ([(78, 232), (88, 214), (110, 206), (140, 203), (170, 205), (183, 215), (179, 243), (173, 272), (167, 300), (140, 298),
          (112, 290), (92, 275), (82, 255)], -0.15),
        ([(183, 215), (205, 206), (235, 207), (265, 214), (295, 228), (322, 248), (345, 262), (372, 280), (400, 302), (428, 330),
          (434, 345), (425, 370), (415, 400), (405, 435), (398, 465), (394, 500), (392, 538), (370, 531), (348, 521), (331, 506),
          (322, 470), (327, 440), (320, 410), (328, 385), (322, 360), (330, 330), (325, 312), (300, 316), (270, 313), (240, 311),
          (210, 307), (185, 303), (167, 300), (173, 272), (179, 243)], 0.15)],
    "Gray280": [        # the L-shaped surface for the first cuneiform, along the superior and posterior borders; in front, for the second metatarsal
        ([(76, 205), (82, 180), (100, 160), (130, 152), (170, 150), (215, 148), (260, 150), (298, 152), (300, 190), (302, 232),
          (270, 236), (235, 240), (200, 243), (178, 252), (172, 280), (170, 320), (168, 350), (150, 365), (120, 362), (105, 345),
          (98, 310), (90, 275), (82, 240)], -0.15),
        ([(300, 135), (318, 128), (328, 140), (330, 200), (325, 260), (318, 320), (312, 360), (300, 370), (296, 320), (300, 250),
          (302, 180)], 0.15)],
    "Gray281": [        # behind on the lateral surface, for the third cuneiform; behind it the posterior surface, for the navicular
        ([(92, 165), (110, 148), (150, 145), (180, 146), (200, 148), (210, 160), (213, 200), (214, 245), (216, 290), (215, 330),
          (205, 348), (190, 355), (172, 348), (165, 320), (160, 290), (152, 258), (135, 235), (112, 210), (97, 188)], 0.15),
        ([(222, 130), (250, 122), (290, 125), (305, 150), (298, 200), (290, 250), (280, 300), (272, 330), (255, 332), (235, 325),
          (225, 290), (222, 240), (220, 180)], -0.25)],
    "Gray282": [        # the navicular field behind, meeting at a ridge the tall field for the second cuneiform, whose front border
        # is a strong S; in front, the two ovals for the second metatarsal, each with its rim
        ([(368, 250), (380, 232), (400, 218), (425, 212), (447, 228), (443, 260), (440, 300), (437, 340), (435, 380), (436, 408),
          (420, 412), (402, 410), (392, 395), (383, 365), (375, 330), (370, 290)], -0.25),
        ([(450, 229), (480, 226), (520, 226), (555, 226), (573, 234), (570, 258), (566, 280), (550, 304), (522, 315), (505, 330),
          (510, 346), (522, 365), (527, 385), (522, 405), (505, 420), (475, 422), (450, 418), (437, 405), (437, 370), (440, 330),
          (443, 290), (447, 255)], 0.15),
        ([(680, 230), (710, 225), (745, 224), (732, 250), (720, 280), (710, 297), (690, 300), (677, 292), (674, 270), (676, 245)], -0.2),
        ([(620, 360), (640, 340), (665, 332), (695, 332), (710, 340), (705, 357), (690, 370), (680, 390), (667, 430), (655, 450),
          (635, 455), (620, 440), (612, 415), (612, 390)], -0.2)],
    "Gray283": [        # the small semi-oval for the fourth metatarsal at the superior angle, the long strip for the third
        # metatarsal down the front beside it; behind, the large rounded one for the cuboid, convex border all round
        ([(275, 170), (290, 175), (300, 200), (300, 240), (295, 247), (285, 240), (277, 215), (272, 185)], 0.1),
        ([(207, 192), (222, 178), (248, 172), (258, 185), (264, 210), (274, 250), (290, 300), (306, 350), (320, 385), (325, 418),
          (312, 430), (296, 428), (280, 405), (262, 370), (248, 335), (235, 295), (222, 250), (212, 215)], 0.1),
        ([(410, 200), (430, 180), (470, 175), (520, 180), (570, 190), (595, 220), (605, 265), (597, 305), (590, 335), (565, 347),
          (530, 347), (500, 337), (475, 315), (455, 290), (435, 265), (415, 240), (407, 220)], -0.1)],
}
# whole faces that are joint surfaces: (direction they face, least cosine) — the posterior surface (navicular) and the
# anterior surface (metatarsal) of each bone; their borders eased over the next 0.2 of the cosine
FACES = {
    "first": [((0.0, 0.25, -1.0), 0.80), ((0.0, -0.3, 1.0), 0.80)],
    "second": [((0.0, 0.0, -1.0), 0.80), ((0.0, 0.0, 1.0), 0.82)],
    "third": [((0.25, 0.0, -1.0), 0.80), ((0.0, 0.0, 1.0), 0.82)],
}
# Gray's smooth non-articular areas and the marks the plates draw, in each plate's pixels
SMOOTH = {
    # "at its anterior plantar angle is a smooth oval impression, into which part of the tendon of the Tibialis anterior is
    # inserted": Fig. 278 draws a triangular smooth field, its apex forward and down at that angle, its upper-back border a
    # sharp irregular oblique crest (MARKS), its front border along the kidney-shaped surface
    "Gray278": [([(150, 505), (160, 488), (178, 470), (197, 452), (214, 436), (232, 428), (258, 436), (285, 452), (306, 472),
                  (326, 495), (343, 520), (358, 552), (372, 582), (386, 606), (360, 614), (320, 620), (280, 618), (245, 610),
                  (212, 596), (186, 575), (165, 545)], -0.2)],
}
MARKS = {
    "Gray278": [("dot", (205, 315), 0.55, -0.7), ("dot", (258, 352), 0.45, -0.6), ("dot", (172, 375), 0.4, -0.5),
                ("dot", (248, 378), 0.5, -0.6), ("dot", (250, 405), 0.55, -0.7), ("dot", (140, 398), 0.4, -0.5),
                ("dot", (95, 435), 0.35, -0.4), ("dot", (120, 300), 0.35, -0.4),
                # the rows of vascular pits running obliquely down toward the tuberosity
                ("dot", (180, 520), 0.3, -0.4), ("dot", (160, 560), 0.35, -0.45), ("dot", (135, 600), 0.3, -0.4),
                ("dot", (120, 640), 0.35, -0.5), ("dot", (215, 640), 0.3, -0.4), ("dot", (190, 668), 0.35, -0.45),
                # the impression's crest along its upper-back border, sharp and irregular: in pieces, each its own height
                ("line", [(146, 514), (152, 498), (162, 486)], 0.9, 0.55), ("line", [(160, 488), (172, 476), (186, 463)], 1.1, 0.7),
                ("line", [(184, 465), (197, 451), (205, 446)], 0.8, 0.5), ("line", [(203, 447), (215, 436), (232, 427)], 1.0, 0.65)],
    "Gray279": [("dot", (125, 497), 0.6, -0.7), ("dot", (172, 518), 0.5, -0.6), ("dot", (115, 330), 0.35, -0.4),
                ("dot", (245, 432), 0.45, -0.5), ("dot", (210, 560), 0.35, -0.4)],
    "Gray282": [("dot", (580, 340), 0.4, -0.5), ("dot", (548, 400), 0.35, -0.4), ("dot", (600, 300), 0.35, -0.4)],
    "Gray283": [("dot", (360, 400), 0.45, -0.5), ("dot", (400, 410), 0.35, -0.4), ("dot", (430, 380), 0.35, -0.4)],
    "Gray280": [("dot", (230, 330), 0.35, -0.4), ("dot", (262, 300), 0.35, -0.4)],
    "Gray281": [("dot", (70, 200), 0.3, -0.4), ("dot", (62, 240), 0.3, -0.4)],
}
# The rough hollows Gray names, as deep as the plate's shading is dark in them (darkest, the full depth in mm), eased
HOLLOWS = {
    # the rough hollow below the L-shaped surface, shaded deep, with strands across it
    "Gray279": [([(182, 322), (240, 318), (300, 322), (318, 360), (316, 420), (305, 470), (280, 500), (230, 500), (190, 460),
                  (175, 400), (172, 350)], 1.6)],
    # "separated by a rough depression ... for an interosseous ligament": deep and pitted between the facets
    "Gray282": [([(512, 236), (560, 236), (600, 240), (660, 245), (668, 300), (640, 330), (612, 352), (600, 400), (590, 440),
                  (560, 450), (530, 425), (532, 395), (518, 350), (512, 320), (548, 300), (566, 262)], 1.8)],
    # the rough area below the cuboid facet, coarsely ridged
    "Gray283": [([(320, 260), (380, 248), (440, 285), (480, 330), (520, 360), (560, 380), (570, 420), (520, 445), (430, 440),
                  (350, 425), (320, 380)], 1.2)],
}
HULL_EASE = 0.5    # mm
LNG_PAD = 6.0      # mm
CLIP_AT = -0.2     # mm: the forms are clipped to the outlines this far outside them (the soft clip pares about as much)
WMIN = {"first": 12.0, "second": 11.0, "third": 11.0}   # mm
LOFT_EASE = 1.0    # mm
JOIN_GROW = 1.3    # mm
JOIN_AT = 0.8      # mm
GAP = 0.3          # mm left between neighbours where the plates bring them together
ROUGH = 0.4        # mm
ROUGH_DROP = 0.35  # mm: the rough bone below the joint surfaces, on the whole (with FACET_PROUD, 0.7 to 0.8)
FACET_PROUD = 0.35 # mm: the joint surfaces above the bone they are set in, risen to over FACET_RISE from the border
FACET_RISE = 0.8   # mm
LIP = 0.2          # mm: the uneven lip along a joint surface's border (0.1 to 0.35 by place)
RIM = 0.15         # mm: the lip of a whole face (found by its facing), uneven too
SMOOTH_PROUD = 0.15  # mm: Gray's smooth non-articular impressions
INK_GAIN = 0.5    # mm: the plate's drawing as relief on the rough bone (9 in 10 of it within this)
END_SOFT = 1.5     # mm: the end faces' easing
END_SOFT_OF = {"third": 0.8}   # (the third's front corners are sharp in Fig. 283: eased less)


def traces(name):
    return np.load(os.path.join(HERE, "traces", "cuneiform_plates.npz"))


def make_traces(refs):
    """The plates' outlines (signed distance, mm at the plate's pose), tone and ink, as midfoot's trace step makes them,
    into traces/cuneiform_plates.npz. `refs`: the folder holding GrayNNN.png. The plates are only read."""
    from PIL import Image
    keep = {}
    for name in VIEWS:
        for v in VIEWS[name]:
            gray = np.array(Image.open(os.path.join(refs, v["fig"] + ".png")).convert("L"))
            mask = pm.silhouette(gray, erase=v.get("erase", ())); pose = list(v["pose"]); px = v["s"] * pose[3]
            d = (ndi.distance_transform_edt(~mask) - ndi.distance_transform_edt(mask)).astype(np.float32)
            d = ndi.gaussian_filter(d + np.where(mask, 0.5, -0.5), 1.0) * px
            keep[v["fig"] + "_sdf"] = d.astype(np.float16); keep[v["fig"] + "_pose"] = np.array(pose, np.float32)
            keep[v["fig"] + "_mask"] = mask.astype(np.uint8)
            keep[v["fig"] + "_ink"] = np.round(pm.ink_of(gray, mask, px) * 50).astype(np.int8)
            # the shading, eased over half a millimetre (dark 255): how deep the plate draws the rough hollows
            keep[v["fig"] + "_dark"] = np.round(ndi.gaussian_filter(255.0 - gray.astype(np.float32), 0.5 / px) * mask).astype(np.uint8)
    np.savez_compressed(os.path.join(HERE, "traces", "cuneiform_plates.npz"), **keep)
    return keep


def _borders(poly, A, across, step=0.1, soft=1.2):
    """A traced outline's two borders along one coordinate at each value of the other: for (x, z) outlines, across=0
    gives (least z, greatest z) at each x = A; across=1 gives (least x, greatest x) at each z = A. Read off the outline
    filled on a fine raster, eased along A over `soft` mm; beyond the outline's ends its end values hold."""
    from PIL import Image, ImageDraw
    P = sdf.spline(np.asarray(poly, float), 0.4, closed=True)
    if across == 1:
        P = P[:, ::-1]
    fine = 0.02; lo, hi = P.min(0), P.max(0); W, H = (np.ceil((hi - lo) / fine).astype(int) + 2)
    im = Image.new("L", (int(H), int(W)), 0); ImageDraw.Draw(im).polygon([((b - lo[1]) / fine, (a - lo[0]) / fine) for a, b in P], fill=255)
    m = np.asarray(im) > 0; zs = lo[1] + np.arange(m.shape[1]) * fine; rows = lo[0] + np.arange(m.shape[0]) * fine; ok = m.any(1)
    b0 = np.where(ok, zs[np.argmax(m, 1)], np.nan); b1 = np.where(ok, zs[m.shape[1] - 1 - np.argmax(m[:, ::-1], 1)], np.nan)
    grid = np.arange(lo[0], hi[0] + step, step)
    g0 = ndi.gaussian_filter1d(np.interp(grid, rows[ok], b0[ok]), soft / step, mode="nearest")
    g1 = ndi.gaussian_filter1d(np.interp(grid, rows[ok], b1[ok]), soft / step, mode="nearest")
    return np.interp(A, grid, g0).astype(np.float32), np.interp(A, grid, g1).astype(np.float32)


def _box(name, pad=6.0):
    P = np.asarray(PLAN[name]) - PLACE[name][[0, 2]]; t, b = np.array(HEIGHT[name]) - PLACE[name][1]
    return (P[:, 0].min() - pad, b - pad, P[:, 1].min() - pad), (P[:, 0].max() + pad, t + pad, P[:, 1].max() + pad)


def loft(name, X, Y, Z):
    """The body from its cross-sections: at each z a wedge across x and y, its two sides leaning from where the plan's
    borders put them at the top to where Gray's text puts them at the bottom, within the plan's front and back
    borders and the bone's height."""
    c = PLACE[name]; P = np.asarray(PLAN[name]) - c[[0, 2]]; top, bot = np.array(HEIGHT[name]) - c[1]
    L, M = _borders(P, Z, 1)
    (a0, b0), (a1, b1) = WEDGE[name]
    t = np.clip((top - Y) / (top - bot), 0.0, 1.0); t = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65    # (the sides a little full, not straight lines)
    # (where the plan's front or back border runs obliquely, as the third's front does along the oblique line of the
    # tarsometatarsal joints, its breadth across x falls to nothing at the tip; the end faces are whole faces as broad
    # as the bone, which the plates show, so the breadth is kept at WMIN at least, about the middle)
    w = np.maximum(M - L, WMIN[name]); L = 0.5 * (L + M) - 0.5 * w
    lo = L + w * (a0 + (a1 - a0) * t); hi = L + w * (b0 + (b1 - b0) * t)
    sec = np.maximum(lo - X, X - hi) * 0.9
    zb, zf = _borders(P, X, 0)
    lng = np.maximum(zb - Z, Z - zf) - LNG_PAD       # (the plan is read off a view from above: its front and back borders
    # at each x are those of the bone's top and of its sole together, and its ends are oblique; the plates' outlines
    # rule the length, the plan only keeps the loft from running on past them)
    ht = np.maximum(Y - top - 1.5, bot - 1.5 - Y)       # (the plates' outlines rule the top and the bottom)
    return np.maximum(np.maximum(sec, lng), ht).astype(np.float32)


def _outline(name, fig, P, tr, X, Y, Z, ease=0.5):
    v = [q for q in VIEWS[name] if q["fig"] == fig][0]; px = v["s"] * P[fig][3]
    d = tr[fig + "_sdf"].astype(np.float32) * (P[fig][3] / tr[fig + "_pose"][3])
    return _read(ndi.gaussian_filter(d, ease / px), *_pixels(v, P[fig], X, Y, Z))


def _ends(D, F, soft=None):
    """The front and back faces eased. Both plates look along the bone from its sides, so each end face is where the
    two outlines' walls, each straight along its own line of sight, meet: two planes and a straight ridge between
    (the second's front face stood so, cut by a knife). Each end is read as a height over (x, y) (how far forward, or
    back, the bone reaches in each column), that height eased over END_SOFT mm, weighted to the columns the bone fills
    deeply, and the bone cut back to it: the ridge goes, the face is a gently curved one."""
    soft = END_SOFT if soft is None else soft
    ins = D < 0; got = ins.any(2); Zax = F.ax[2]; n = ins.shape[2]
    zf = np.where(got, Zax[n - 1 - np.argmax(ins[:, :, ::-1], 2)], 0.0); zb = np.where(got, Zax[np.argmax(ins, 2)], 0.0)
    w = np.clip((zf - zb) / max(float((zf - zb).max()) * 0.6, 1e-3), 0.0, 1.0) ** 2 * got
    sg = soft / F.h
    norm = np.maximum(ndi.gaussian_filter(w, sg), 1e-4)
    zfs = ndi.gaussian_filter(zf * w, sg) / norm; zbs = ndi.gaussian_filter(zb * w, sg) / norm
    Z = Zax[None, None, :]
    cut = np.maximum(Z - zfs[:, :, None] - 0.15, zbs[:, :, None] - 0.15 - Z)
    return sdf.smax(D, cut.astype(np.float32), 0.8).astype(np.float32)


def _neighbour(Fn, at, X, Y, Z, soft=0.8, order=1):
    """Another bone's field (an object with D, lo, h; its origin at `at` in the navicular's frame) at this bone's
    points (given in the navicular's frame), eased so that its fine marks do not print on this bone."""
    D = ndi.gaussian_filter(np.asarray(Fn.D, np.float32), soft / Fn.h)
    shape = np.broadcast(X, Y, Z).shape
    c = [((np.broadcast_to(q, shape) - at[k]) - Fn.lo[k]) / Fn.h for k, q in enumerate((X, Y, Z))]
    # (order 3 where this bone's surface is laid along the other's: read linearly, the other's grid cells print as
    # fine parallel facets)
    return ndi.map_coordinates(D, [q.ravel() for q in c], order=order, mode="constant", cval=20.0).reshape(shape).astype(np.float32)


def _field(polys, shape, px, seed, proud=FACET_PROUD):
    """Joint surfaces traced on a plate, as two plate-sized pictures: how smooth (0 to 1) and how high (mm toward the
    eye). Each border is the traced line, its pixel steps eased but its turns kept, wandering a little more (0.1 mm);
    the field rises from the rough bone over FACET_RISE with an uneven lip just inside its border, and is gently
    domed or dished (the curvature given with each)."""
    from PIL import Image, ImageDraw
    rng = np.random.default_rng(seed); H, W = shape
    sm = np.zeros(shape, np.float32); hh = np.zeros(shape, np.float32)
    for poly, curv in polys:
        im = Image.new("L", (W * 3, H * 3), 0)
        ImageDraw.Draw(im).polygon([((u + 0.5) * 3, (v + 0.5) * 3) for u, v in poly], fill=255)
        m = ndi.gaussian_filter(np.asarray(im.resize((W, H), Image.BOX), np.float32) / 255.0, 0.8) > 0.5
        d = (ndi.distance_transform_edt(m) - ndi.distance_transform_edt(~m)).astype(np.float32) * px
        wob = ndi.gaussian_filter(rng.normal(size=shape).astype(np.float32), 0.7 / px); wob /= wob.std() + 1e-9
        lip = ndi.gaussian_filter(rng.normal(size=shape).astype(np.float32), 1.2 / px); lip /= lip.std() + 1e-9
        d = d + 0.1 * wob
        dmax = max(float(d.max()), 0.5)
        h = proud * _ss(d / FACET_RISE) + LIP * (1.0 + 0.6 * np.tanh(lip)) * np.exp(-((d - 0.35) / 0.3) ** 2) \
            + curv * np.clip(d / dmax, 0.0, 1.0) ** 1.5
        h = np.where(d > -1.0, h, 0.0) * _ss((d + 1.0) / 0.5)
        sm = np.maximum(sm, _ss((d + 0.05) / 0.3)); hh = np.maximum(hh, h)
    return sm, hh.astype(np.float32)


def cuneiform(name, h=0.3, log=print, upto="all", poses=None, neighbours=()):
    """name: "first", "second" or "third". upto="body": the loft alone (what the plates' poses are fitted on);
    "hull": within the plates' outlines as well; "forms": with the forms Gray names, before the surface's marks.
    neighbours: [(field, origin in the navicular's frame), ...] of bones already built that this one must not run
    into (it is kept GAP mm off them)."""
    lo, hi = _box(name)
    F = Field(lo, hi, h); X, Y, Z = F.coords((slice(None),) * 3)
    V = {v["fig"]: v for v in VIEWS[name]}
    D = loft(name, X, Y, Z)
    D = ndi.gaussian_filter(D, LOFT_EASE / F.h)
    if upto == "body":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    tr = traces(name)
    P = {f: np.asarray((poses or {}).get(f, tr[f + "_pose"]), float) for f in V}
    o = [_outline(name, f, P, tr, X, Y, Z) for f in V]
    within = np.maximum(o[0], o[1]); del o
    D = ndi.gaussian_filter(np.maximum(within, D), HULL_EASE / F.h).astype(np.float32)
    D = _ends(D, F, END_SOFT_OF.get(name))
    if upto == "hull":
        F.D = np.clip(D, -12.0, 12.0).astype(np.float32); return F
    c = PLACE[name]; top, bot = np.array(HEIGHT[name]) - c[1]
    Pl = np.asarray(PLAN[name]) - c[[0, 2]]
    if name == "first":
        # the plantar surface "at its back part is a tuberosity for the insertion of part of the tendon of the Tibialis
        # posterior" (Fig. 278 has it as the low swelling of the hind lower corner): a low rounded swelling under the
        # back of the base, kept inside Fig. 278's and 279's outlines
        tub = Ellipsoid((4.0, bot + 3.0, Pl[:, 1].min() + 5.5), (5.0, 3.2, 5.0), rot((0, 0, 1), 15.0))(X, Y, Z)
        D = sdf.smin(D, tub, 3.0)
        # "the lateral surface is concave": a broad shallow hollow below the L-shaped facet, where the plantar part of the
        # second metatarsal's base and the peroneus longus come
        cav = Ellipsoid((Pl[:, 0].min() - 3.5, bot + 0.40 * (top - bot), 2.0), (5.0, 9.0, 9.0), rot((0, 1, 0), 0.0))(X, Y, Z)
        D = sdf.smax(D, -cav, 3.0)
    elif name == "second":
        # "the plantar surface, sharp and tuberculated": two or three low tubercles along the thin edge
        for zz, ss, a in ((-4.5, 1.0, 20.0), (0.6, 1.3, -15.0), (5.4, 0.8, 35.0)):
            xx = float(np.interp(zz, *_lh(Pl, 0.74)))
            D = sdf.smin(D, Ellipsoid((xx, bot + 2.0, zz), (1.4 * ss, 1.3, 2.4 * ss), rot((0, 1, 0), a))(X, Y, Z), 1.6)
    elif name == "third":
        # "the plantar surface is a rounded margin": its edge rounded off broadly
        D = sdf.smin(D, _tube(X, Y, Z, [(float(np.interp(z, *_lh(Pl, 0.68))), bot + 2.2, z) for z in (-8.0, -2.0, 4.0, 9.0)], [1.9, 2.3, 2.2, 1.6]), 1.5)
    # (no face of a bone is a plane: the whole eased once more, and given a low, broad unevenness)
    rng = np.random.default_rng({"first": 278, "second": 280, "third": 282}[name])
    wav = ndi.gaussian_filter(rng.normal(size=D.shape).astype(np.float32), 3.0 / F.h); wav /= wav.std()
    D = ndi.gaussian_filter(D + 0.25 * wav, 0.4 / F.h)
    # (and what the forms added kept within the plates' outlines: a swelling standing out past them was a round lump
    # the plates do not draw)
    D = sdf.smax(D, within + CLIP_AT, 0.8)
    # the neighbours: where the plates bring two bones together the joint surfaces lie GAP apart; nowhere do they pass
    # into each other
    for Fn, at in neighbours:
        Xn, Yn, Zn = X + c[0], Y + c[1], Z + c[2]
        Dn = _neighbour(Fn, at, Xn, Yn, Zn)
        # (and where the two already come within a couple of millimetres, this one is let grow up to JOIN_GROW toward
        # the other, to JOIN_AT off it: a joint's faces follow each other, they do not merely fail to meet)
        Dg = _neighbour(Fn, at, Xn, Yn, Zn, soft=1.5, order=3)     # (the other's broad form only: its marks and steps not copied)
        # (the growth eased out over a couple of millimetres in space: where the other bone ends abruptly, a growth that
        # stopped with it stood as a slab with a cliff round it)
        amt = ndi.gaussian_filter(JOIN_GROW * _ss((2.5 - Dg) / 1.2), 1.5 / F.h)
        grow = sdf.smax(D - amt, JOIN_AT - Dg, 0.6); del Dg, amt
        D = np.minimum(D, np.maximum(grow, within - 0.1)); del grow    # (never past the plates' outlines)
        D = sdf.smax(D, GAP - Dn, 1.2)    # (eased: met sharply, the cut stood as a hard step round the joint surface)
    F.D = np.clip(D, -12.0, 12.0).astype(np.float32); del D, within
    if upto == "forms":
        return F
    # 3. The surfaces, as the plates draw them. Each joint surface is a smooth field standing FACET_PROUD above the
    # rough bone round it, with a low rim (RIM) along its border where the rough bone begins; the rough bone is pitted
    # and ridged, the ridges running as the engraver's lines run (the plate's fine drawing, pm.ink_of, laid on as
    # relief where the plate faces the surface and only on rough bone). The whole faces (posterior, anterior) are found
    # by the way they face, their border wandering (a cosine threshold alone is a ruler line along the bone's edge);
    # the others are the fields traced inside each plate's outline. Everything is laid on through _shown (the points
    # each plate sees, within a few mm behind the surface), so a field seen at a slant is laid as fully as one seen
    # square, and each is eased out over the plate outline's last half millimetre.
    rs = np.random.default_rng({"first": 1278, "second": 1280, "third": 1282}[name])
    g = np.gradient(ndi.gaussian_filter(F.D, 1.2 / F.h), F.h); nrm = np.sqrt(g[0] ** 2 + g[1] ** 2 + g[2] ** 2) + 1e-6
    wan = ndi.gaussian_filter(rs.normal(size=F.D.shape).astype(np.float32), 1.6 / F.h); wan /= wan.std()
    face = np.zeros(F.D.shape, np.float32)
    for e, cmin in FACES[name]:
        e = np.asarray(e, float); e /= np.linalg.norm(e)
        face = np.maximum(face, _ss(((g[0] * e[0] + g[1] * e[1] + g[2] * e[2]) / nrm - cmin - 0.07 * wan) / 0.12))
    del g, nrm
    # (a whole face rises over half a millimetre and more, its lip uneven: no constant step)
    face = np.clip(ndi.gaussian_filter(face, 0.5 / F.h), 0.0, 1.0)
    hface = FACET_PROUD * face + RIM * (0.5 + 0.5 * np.tanh(wan)) * 4.0 * face * (1.0 - face)
    zero = lambda: np.zeros(F.D.shape, np.float32)
    fpl, hpl, sma, hsm, marks, ink, hol, sil = zero(), zero(), zero(), zero(), zero(), zero(), zero(), zero()
    for f, v in V.items():
        px = v["s"] * P[f][3]; sh = tr[f + "_sdf"].shape; q = _ss((-tr[f + "_sdf"].astype(np.float32) - 0.05) / 0.5)
        sd = int(f[4:])
        # (the bone each plate sees within its outline's last millimetre and a half: where a sunk surface would pare
        # the silhouette, so the rough bone's drop and the hollows are eased off there)
        np.maximum(sil, _shown(F, v, P[f], 1.0 - _ss((-tr[f + "_sdf"].astype(np.float32) - 0.2) / 1.3), deep=2.5), out=sil)
        for polys, sm3, h3 in ((FACETS.get(f), fpl, hpl), (SMOOTH.get(f), sma, hsm)):
            if polys:
                m2, h2 = _field(polys, sh, px, sd, proud=FACET_PROUD if sm3 is fpl else SMOOTH_PROUD)
                np.maximum(sm3, _shown(F, v, P[f], m2 * q, deep=2.5), out=sm3)
                np.maximum(h3, _shown(F, v, P[f], h2 * q, deep=2.5), out=h3)
        if MARKS.get(f):
            marks += _shown(F, v, P[f], _marks_map(_pits(MARKS[f], px, seed=sd), sh, px) * q, deep=2.0)
        if HOLLOWS.get(f) and f + "_dark" in tr.files:
            dark = tr[f + "_dark"].astype(np.float32) / 255.0; hm = np.zeros(sh, np.float32)
            for poly, depth in HOLLOWS[f]:
                hm = np.maximum(hm, depth * _mask([poly], sh, 1.0 / px) * np.clip((dark - 0.3) / 0.4, 0.0, 1.0) ** 0.8)
            np.maximum(hol, _shown(F, v, P[f], ndi.gaussian_filter(hm, 0.6 / px) * q, deep=2.5), out=hol)
        if f + "_ink" in tr.files:
            B = pm.basis(v, P[f][:3])
            gg = np.gradient(ndi.gaussian_filter(F.D, 1.0 / F.h), F.h); nn = np.sqrt(gg[0] ** 2 + gg[1] ** 2 + gg[2] ** 2) + 1e-6
            facing = _ss(((gg[0] * B[2][0] + gg[1] * B[2][1] + gg[2] * B[2][2]) / nn - 0.35) / 0.35); del gg, nn
            ink = np.where(facing > 0, np.maximum(ink * (1 - facing), 0) + facing * _shown(F, v, P[f], tr[f + "_ink"].astype(np.float32) / 50.0 * q, deep=1.5), ink)
    # (laid on the grid, a field's border rising over a few voxels prints their steps: eased once more in space)
    for a3 in (fpl, hpl, sma, hsm):
        a3[...] = ndi.gaussian_filter(a3, 0.35 / F.h)
    fac = np.maximum(face, fpl)
    F.smooth = np.clip(np.maximum(fac, sma), 0.0, 1.0).astype(np.float32)
    F.D -= np.maximum(hface, hpl) + hsm + marks; del hface, hpl, hsm, marks, face, fpl
    rough = 1.0 - F.smooth
    # (where a neighbour lies within a couple of millimetres the two bones meet at a joint or are tied by short
    # ligaments: the rough bone's drop and grain are mostly let go there, so the joint gap stays a joint's)
    dnear = np.full(F.D.shape, 20.0, np.float32)
    for Fn, at in neighbours:
        np.minimum(dnear, _neighbour(Fn, at, X + c[0], Y + c[1], Z + c[2]), out=dnear)
    rough = rough * (1.0 - 0.75 * _ss((2.5 - dnear) / 1.5)); del dnear
    sh3 = F.D.shape
    # the rough bone: not one even grain. A broad field (reg) decides, place by place, whether the bone is finely
    # pitted or coarsely lumped; the pits are fewer and each its own size; the ridges are the plate's own lines (ink),
    # laid on where a plate looks at the bone, so they run as the engraver drew them
    reg = ndi.gaussian_filter(rs.normal(size=sh3).astype(np.float32), 3.0 / F.h); reg = 0.5 + 0.5 * np.tanh(reg / reg.std())
    n1 = ndi.gaussian_filter(rs.normal(size=sh3).astype(np.float32), 0.35 / F.h); n1 /= n1.std()
    n2 = ndi.gaussian_filter(rs.normal(size=sh3).astype(np.float32), 1.2 / F.h); n2 /= n2.std()
    n3 = ndi.gaussian_filter(rs.normal(size=sh3).astype(np.float32), 0.3 / F.h); n3 /= n3.std()
    grain = ROUGH * (0.55 * reg * n1 + 0.8 * (1.0 - reg) * n2 + 2.0 * _ss((n3 - 2.3) / 0.5) * (0.3 + reg))
    del n1, n2, n3, reg
    # (D grows outward: + sinks the surface. The rough bone stands ROUGH_DROP below the joint surfaces on the whole)
    keep = 1.0 - 0.75 * np.clip(ndi.gaussian_filter(sil, 0.5 / F.h), 0.0, 1.0); del sil
    F.D += (grain + (ROUGH_DROP + hol) * keep - INK_GAIN * ink) * rough; del grain, ink, hol, keep
    # (and still clear of the neighbours after it)
    for Fn, at in neighbours:
        # (eased against the other's broad form, so its grain and the grid's steps do not print here)
        Dn = _neighbour(Fn, at, X + c[0], Y + c[1], Z + c[2], soft=1.0, order=3)
        F.D = sdf.smax(F.D, GAP - Dn, 0.6); del Dn
        # (and, against its own form, never into it: this last only where the eased form missed a lump of the other's)
        Dn = _neighbour(Fn, at, X + c[0], Y + c[1], Z + c[2], soft=0.05)
        F.D = np.maximum(F.D, 0.06 - Dn).astype(np.float32); del Dn
    log("%s cuneiform: built from %s, its plan from Fig. 268" % (name, " and ".join(V)))
    return _one_piece(F)


def _lh(Pl, share):
    """(z values, x at `share` of the plan's breadth from its lateral border) along the plan."""
    zz = np.linspace(Pl[:, 1].min(), Pl[:, 1].max(), 60)
    L, M = _borders(Pl, zz, 1)
    return zz, L + share * (M - L)


class _Grid:
    def __init__(self, D, lo, h):
        self.D, self.lo, self.h = D, np.asarray(lo, float), float(h)


def assemble(h=0.3, log=print, navicular=None, cuboid=None, poses=None):
    """The three built in turn, each kept clear of the navicular, the cuboid and those already built: {name: field}.
    navicular, cuboid: their fields (midfoot.navicular(), midfoot.cuboid()), built here if not given."""
    import midfoot
    nav = navicular if navicular is not None else midfoot.navicular(h, log=log)
    cub = cuboid if cuboid is not None else midfoot.cuboid(h, log=log)
    out = {}
    near = {"first": [(nav, np.zeros(3))], "second": [(nav, np.zeros(3))], "third": [(nav, np.zeros(3)), (cub, CUBOID_AT)]}
    for name in ("first", "second", "third"):
        nb = list(near[name]) + [(out[k], PLACE[k]) for k in out]
        out[name] = cuneiform(name, h, log=log, poses=poses, neighbours=nb)
    return out


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 2 and sys.argv[1] == "trace":
        k = make_traces(sys.argv[2]); print("traced", sorted(f for f in k if f.endswith("_pose")))
