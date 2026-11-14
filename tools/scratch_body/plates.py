"""plates.py: the reference plates the skull is traced from, and how each is put to scale.

All are figures of Gray's Anatomy, 20th edition, 1918 (public domain), from the Internet Archive's
scan (anatomyofhumanbo1918gray). Points are pixels of the page rendered at 300 dpi.

The side view (Fig. 188) is the master: levelled on the Frankfurt plane (the line through the top of
the ear hole and the lowest point of the orbit's margin) and scaled so that the greatest length,
glabella to the back of the head, is 183.5 mm. Heights (y) and depths (z) are read from it. The
front view (Fig. 190) and the base (Fig. 187) give breadths (x): each is scaled across so that the
cheek bones are 133 mm apart, and along its other axis it is tied to the side view at the landmarks
both show. One correction is made to the side view: its nose is short (nasion to the floor of the
nasal opening 45 mm); the floor is put at the usual 51 mm, as in the front view.
"""
import json, os
import numpy as np
from tracing import Frame

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = {"side": 182, "front": 186, "base": 179}
LENGTH, BIZYGOMATIC, BREADTH = 183.5, 133.0, 142.0

SIDE = {            # Fig. 188
    "porion": (1280, 2060), "orbitale": (575, 1912), "glabella": (399, 1600), "nasion": (443, 1660),
    "rhinion": (300, 1760), "anterior nasal spine": (279, 2057), "prosthion": (283, 2287),
    "bregma": (1230, 1000), "lambda": (2108, 1690), "mastoid tip": (1343, 2393),
}
NASAL_FLOOR_Y = -27.8          # nasion (23.2) less the usual nasal height (51)


def traces():
    return {k: np.array(v, float) if isinstance(v, list) else v
            for k, v in json.load(open(os.path.join(HERE, "traces", "skull.json"))).items()}


def side_frame(sil):
    """The side view's frame: (z, y) in head-frame mm from page pixels. `sil` is the traced silhouette (page pixels)."""
    g = np.array(SIDE["glabella"], float)
    far = sil[np.argmax(np.linalg.norm(sil - g, axis=1))]
    return Frame(g, far, LENGTH, level=(SIDE["orbitale"], SIDE["porion"]), origin_px=SIDE["porion"], flip=True)


def subnasal(y):
    """The side view's heights below the nasal spine, drawn out so that the nasal floor lies at the usual height."""
    y = np.asarray(y, float)
    a, b = -21.4, -45.1                     # the spine and the prosthion as drawn
    return np.where(y < a, NASAL_FLOOR_Y + (y - a) * (b - NASAL_FLOOR_Y) / (b - a), y)


# ---- front view, Fig. 190 ------------------------------------------------------------------------
FRONT_MID = 974.0
FRONT_SX = 1216.0 / BIZYGOMATIC                                   # pixels per mm across
FRONT_Y = [(872, 113.2), (1750, 23.2), (1973, 0.0), (2235, NASAL_FLOOR_Y), (2417, -45.1), (2900, -92.0)]   # page y -> head y (vertex, nasion, orbitale, nasal floor, prosthion, menton)


def front_mm(p):
    """(x, y) in head-frame mm from page pixels of the front view (x measured from the midline, either side positive)."""
    p = np.atleast_2d(np.asarray(p, float))
    py, hy = zip(*FRONT_Y)
    return np.column_stack([np.abs(p[:, 0] - FRONT_MID) / FRONT_SX, np.interp(p[:, 1], py, hy)])


# ---- base, Fig. 187 (the left half, seen from below; the picture's left is the skull's left) -------------
BASE_MID = 1356.0
BASE_SX = 1062.0 / (BIZYGOMATIC / 2)
BASE_Z = [(612, 98.1), (3400, -81.9)]                             # page y -> head z (prosthion, back of the head)


def base_mm(p):
    """(x, z) in head-frame mm from page pixels of the base view."""
    p = np.atleast_2d(np.asarray(p, float))
    py, hz = zip(*BASE_Z)
    return np.column_stack([np.abs(BASE_MID - p[:, 0]) / BASE_SX, np.interp(p[:, 1], py, hz)])


# ---- lines picked by hand on the front view (the skull's right orbit and cheek; page pixels) ----------------
ORBIT_FRONT = [      # the orbital margin, from the supraorbital notch outward and round: (x, y, depth z in mm read from the side view)
    (757, 1648, 92.0), (718, 1675, 89.5), (670, 1687, 85.5), (621, 1700, 80.5), (582, 1714, 76.5), (553, 1744, 73.0),
    (539, 1773, 70.5), (531, 1812, 69.2), (534, 1851, 68.8), (544, 1890, 70.0), (558, 1929, 72.5),
    (582, 1953, 75.0), (621, 1968, 77.5), (670, 1973, 79.5), (718, 1965, 81.5), (757, 1948, 83.5), (796, 1929, 85.0), (820, 1909, 86.0),
    (840, 1880, 87.0), (854, 1846, 88.2), (857, 1812, 89.2), (850, 1775, 90.0), (832, 1735, 91.0), (800, 1690, 92.0),
]
APERTURE_FRONT = [   # the nasal opening's rim, right half from the tip of the nasal bones down to the spine: (x, y, z)
    (966, 1900, 107.0), (927, 1934, 103.0), (903, 1987, 99.0), (874, 2045, 96.0), (859, 2094, 95.3), (852, 2143, 95.6),
    (859, 2181, 96.2), (879, 2210, 97.2), (913, 2235, 98.6), (956, 2249, 100.0),
]
CHEEK_FRONT = [      # the cheek bone's outline in the front view: frontal process outer edge, arch, lower border to the maxilla
    (449, 1774), (449, 1851), (451, 1900), (393, 1997), (427, 2045), (466, 2094), (495, 2133), (524, 2157),
    (558, 2167), (602, 2172), (680, 2206), (692, 2240),
]


# the braincase's sutures as the side view draws them (Fig. 188, page pixels), each from its upper or front end
SUTURES_SIDE = {
    "coronal": [(1230, 1000), (1175, 1059), (1143, 1124), (1104, 1176), (1071, 1228), (1032, 1280), (987, 1332), (955, 1385),
                (929, 1450), (918, 1515), (916, 1567), (877, 1606)],
    "sphenoparietal": [(877, 1606), (980, 1598), (1084, 1593)],
    "sphenofrontal": [(877, 1606), (820, 1640), (770, 1690), (750, 1720)],
    "squamosal": [(1084, 1593), (1162, 1570), (1240, 1561), (1318, 1567), (1396, 1587), (1461, 1619), (1513, 1671), (1565, 1737),
                  (1617, 1795), (1630, 1828)],
    "sphenosquamosal": [(1084, 1593), (1030, 1700), (960, 1800), (900, 1890), (880, 1950)],
    "parietomastoid": [(1630, 1828), (1656, 1893), (1708, 1958), (1753, 1997)],
    "lambdoid": [(2108, 1690), (2050, 1750), (1980, 1820), (1900, 1890), (1820, 1950), (1753, 1997)],
    "occipitomastoid": [(1753, 1997), (1700, 2090), (1620, 2180), (1540, 2260), (1480, 2320)],
}
# how far each wanders from side to side (mm): the toothed ones a millimetre or more, the scale-like ones hardly at all
SUTURE_WAVE = {"coronal": 0.9, "sagittal": 1.1, "lambdoid": 1.5, "squamosal": 0.25, "parietomastoid": 0.7, "occipitomastoid": 0.6,
               "sphenoparietal": 0.3, "sphenofrontal": 0.4, "sphenosquamosal": 0.3}
