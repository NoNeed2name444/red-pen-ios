"""landmarks.py: the master landmark table of the from-scratch body.

One adult man, 1.75 m, standing in the anatomical position. Body frame: metres, x = his left,
y up (soles at 0), z forward, the midline exactly x = 0. The plumb line through the ear holes
(porions) is z = 0, the usual line of gravity of the standing body.

The head is laid out in its own millimetre frame, the Frankfurt horizontal: origin midway between
the two porions (upper margins of the ear holes), the plane through them and the lowest points of
the orbital margins level. HEAD (below) places that origin in the body.

Every number is a typical textbook value for an adult man (craniometric and dental averages as
commonly tabulated); none is measured from a scan or copied from a model. Where a published plate
was looked at for shape, it is listed in REFERENCES.md.
"""
import numpy as np

STATURE = 1.750
SCALP = 0.006                       # soft tissue over the vertex
VERTEX_ABOVE_FH = 115.0             # mm, skull vertex above the Frankfurt plane
HEAD = np.array([0.0, STATURE - SCALP - VERTEX_ABOVE_FH / 1000.0, 0.0])      # the porion midpoint, body frame


def body(p_mm):
    """A point of the head frame (mm) in the body frame (m)."""
    return HEAD + np.asarray(p_mm, float) / 1000.0


# ---- skull, head frame, mm (left side where paired; the right is the mirror image) -------------
SKULL = {
    "nasion": (0, 27, 91), "glabella": (0, 34, 94.5), "metopion": (0, 68, 88.5), "bregma": (0, 111, 14),
    "vertex": (0, 115, -12), "obelion": (0, 101, -62), "lambda": (0, 78, -82), "opisthocranion": (0, 52, -89),
    "inion": (0, 2, -79), "opisthion": (0, -26, -40), "basion": (0, -22, -5),
    "euryon": (71, 62, -25), "frontotemporale": (48, 47, 71), "pterion": (53, 31, 42), "asterion": (56, 5, -50),
    "porion": (60, 0, 0), "orbitale": (30, 0, 83), "zygion": (66.5, -2, 34), "mastoidale": (53, -27, -11),
    "styloid tip": (34.5, -35, 9.5), "ectoconchion": (50.5, 17, 72), "dacryon": (11.5, 18, 84),
    "rhinion": (0, 5, 104), "nasospinale": (0, -25, 93), "anterior nasal spine": (0, -24.5, 99.5),
    "prosthion": (0, -43, 96.5), "posterior nasal spine": (0, -29, 46.5), "frontomalare": (51, 27, 71.5),
    "mandibular fossa": (51, 2.5, 10.5), "articular tubercle": (52, -7, 22),
    "occipital condyle": (17.5, -28, -14),
}
MANDIBLE = {
    # as built (mandible.py); the first plan had the coronoid and the angle 3 mm further out
    "condylion": (50, -0.8, 10.5), "coronion": (43, -4.9, 39.1), "sigmoid notch": (45.5, -18, 25),
    "gonion": (45.4, -63.6, 8.2), "menton": (0, -94.2, 86), "pogonion": (0, -87, 94.8), "infradentale": (0, -60, 93),
    "mental foramen": (30.9, -71.0, 70.4), "lingula": (41.6, -32, 25),
}
# target sizes, mm (typical adult man)
SIZES = {
    "skull length glabella-opisthocranion": 183.5, "skull breadth euryon-euryon": 142.0,
    "basion-bregma height": 134.0, "bizygomatic breadth": 133.0, "minimum frontal breadth": 96.0,
    "upper facial height nasion-prosthion": 70.0, "total facial height nasion-menton": 120.0,
    "orbit breadth": 39.0, "orbit height": 35.0, "nasal height": 52.0, "nasal breadth": 24.5,
    "foramen magnum length": 35.0, "foramen magnum breadth": 30.0, "bimastoid breadth at the tips": 106.0,
    "bigonial breadth": 98.0, "bicondylar breadth": 120.0, "ramus height condylion-gonion": 62.0,
    "minimum ramus breadth": 32.0, "symphysis height": 33.0,
}

# ---- teeth: mesiodistal width, crown height, root length (mm), midline outward -------------------
TEETH = ["central incisor", "lateral incisor", "canine", "first premolar", "second premolar",
         "first molar", "second molar", "third molar"]
UPPER = {"width": [8.5, 6.5, 7.5, 7.0, 6.5, 10.0, 9.0, 8.5], "crown": [10.5, 9.0, 10.0, 8.5, 8.5, 7.5, 7.0, 6.5],
         "root": [13.0, 13.0, 17.0, 14.0, 14.0, 12.5, 11.5, 11.0],
         "labial tilt deg": [22, 18, 8, -4, -6, -8, -8, -8],          # crown tipped toward the lips/cheek (+)
         "crest y": [-44.3, -44.5, -43.9, -42.8, -42.3, -41.3, -40.3, -39.3]}       # the alveolar margin as built
LOWER = {"width": [5.0, 5.5, 7.0, 7.0, 7.0, 11.0, 10.5, 10.0], "crown": [9.0, 9.5, 11.0, 8.5, 8.0, 7.5, 7.0, 7.0],
         "root": [12.5, 14.0, 16.0, 14.0, 14.5, 14.0, 13.0, 11.0],
         "labial tilt deg": [22, 20, 10, -6, -10, -14, -18, -20],
         "crest y": [-60.0, -60.0, -60.3, -58.0, -56.5, -54.2, -52.2, -50.7]}
# the two arches seen from above: (x, z) of the middle of the alveolar crest, midline to behind the last molar
UPPER_ARCH = [(0, 93.0), (9, 91.3), (17.2, 85.6), (21.6, 78.8), (24.2, 72.0), (26.6, 63.5), (28.0, 54.5), (28.4, 46.5), (28.2, 41.0)]
LOWER_ARCH = [(0, 89.8), (6.5, 88.3), (13.5, 84.5), (18.6, 78.6), (21.8, 72.0), (24.6, 62.5), (26.8, 52.0), (28.8, 42.0), (30.5, 35.0)]

# ---- neck, head frame, mm -----------------------------------------------------------------------
# each vertebra: body height (front), disc below it, depth and width of the body, forward tilt of
# its lower end plate (degrees, front edge down); typical adult values
CERVICAL = {
    "C2": {"body": 22.0, "disc": 4.8, "depth": 16.0, "width": 19.0, "tilt": 9.0},
    "C3": {"body": 13.5, "disc": 5.0, "depth": 15.5, "width": 17.5, "tilt": 12.0},
    "C4": {"body": 13.2, "disc": 5.2, "depth": 15.8, "width": 18.5, "tilt": 15.5},
    "C5": {"body": 13.0, "disc": 5.2, "depth": 16.2, "width": 20.0, "tilt": 19.0},
    "C6": {"body": 13.2, "disc": 5.0, "depth": 16.8, "width": 22.0, "tilt": 22.5},
    "C7": {"body": 14.5, "disc": 4.5, "depth": 17.2, "width": 24.5, "tilt": 26.0},
}
DENS_TIP = (0, -27.5, -5.5)                 # 5 to 6 mm below and behind the basion
C2_FACET_Y = -43.0                          # level of the axis's upper joint surfaces beside the dens
HYOID = {"body": (0, -82, 38), "greater horn tip": (22, -76, 9), "lesser horn tip": (12.8, -74.5, 32)}   # level of the lower half of C3

# ---- the rest of the body: levels the later regions hang on (m above the soles, typical proportions
# of stature for an adult man; to be refined region by region as each is built) ------------------
LEVELS = {
    "vertex": STATURE, "chin": 0.870 * STATURE, "seventh cervical spine": 0.845 * STATURE,
    "acromion": 0.818 * STATURE, "suprasternal notch": 0.815 * STATURE, "nipple": 0.720 * STATURE,
    "xiphoid": 0.690 * STATURE, "elbow": 0.630 * STATURE, "navel and iliac crest top": 0.600 * STATURE,
    "anterior superior iliac spine": 0.555 * STATURE, "greater trochanter": 0.530 * STATURE,
    "wrist": 0.485 * STATURE, "pubic symphysis": 0.500 * STATURE, "fingertip": 0.377 * STATURE,
    "knee joint": 0.285 * STATURE, "ankle joint": 0.039 * STATURE,
}
