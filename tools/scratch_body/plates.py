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
    # Each line is the plate's own, in page pixels, checked by drawing it back over the page (dev/plate_lines.py). An earlier
    # tracing stood 2 to 5 mm off the plate round the pterion and 4 to 10 mm off behind the mastoid, and cut straight across
    # the tongue of the parietal bone (its mastoid angle) that the plate draws let into the notch between squama and mastoid.
    "coronal": [(1230, 1000), (1214, 1050), (1198, 1092), (1166, 1135), (1148, 1166), (1122, 1192), (1105, 1232), (1082, 1268),
                (1055, 1300), (1032, 1342), (996, 1368), (962, 1402), (948, 1440), (945, 1470), (943, 1530), (940, 1575), (932, 1611)],
    "sphenoparietal": [(932, 1611), (960, 1612), (985, 1609), (1010, 1612), (1040, 1617), (1070, 1625), (1105, 1633)],
    "sphenofrontal": [(932, 1611), (905, 1610), (890, 1630), (880, 1650), (860, 1665), (840, 1675), (820, 1687), (800, 1696),
                      (775, 1715), (752, 1740)],
    "squamosal": [(1105, 1633), (1127, 1623), (1160, 1600), (1193, 1581), (1240, 1572), (1280, 1575), (1327, 1587), (1373, 1600),
                  (1397, 1622), (1433, 1643), (1473, 1657), (1508, 1672), (1520, 1705), (1545, 1735), (1573, 1753), (1593, 1787),
                  (1627, 1800), (1650, 1822), (1655, 1845), (1632, 1872), (1628, 1905), (1638, 1930), (1628, 1958), (1617, 1983)],
    "sphenosquamosal": [(1105, 1633), (1080, 1655), (1050, 1690), (1015, 1740), (985, 1780), (960, 1820), (945, 1870), (938, 1930),
                        (935, 1950)],
    "parietomastoid": [(1617, 1983), (1643, 1977), (1667, 1980), (1693, 1990), (1720, 1982), (1740, 1993), (1760, 2003), (1790, 2020)],
    "lambdoid": [(2108, 1690), (2090, 1707), (2073, 1727), (2053, 1753), (2033, 1787), (2013, 1813), (1993, 1840), (1980, 1860),
                 (1953, 1887), (1940, 1913), (1913, 1933), (1893, 1953), (1865, 1975), (1840, 1998), (1815, 2012), (1790, 2020)],
    "occipitomastoid": [(1790, 2020), (1787, 2047), (1772, 2082), (1750, 2113), (1737, 2153), (1722, 2180), (1722, 2205), (1702, 2240),
                        (1690, 2268), (1670, 2307)],
}
# how far each wanders from side to side (mm): the toothed ones a millimetre or more, the scale-like ones hardly at all
SUTURE_WAVE = {"coronal": 1.1, "sagittal": 1.1, "lambdoid": 1.9, "squamosal": 0.25, "parietomastoid": 0.7, "occipitomastoid": 0.6,
               "sphenoparietal": 0.3, "sphenofrontal": 0.4, "sphenosquamosal": 0.3}
# The parietal's toothed borders, in Gray's words (1918): the frontal border "is deeply serrated" and the occipital "deeply
# denticulated" (p. 134); the sagittal suture is "deeply serrated in its anterior two-thirds" (p. 177). The teeth of those three
# are longer than the rest's (lengths in mm that a groove a millimetre wide can still show apart on a half-millimetre grid);
# the sagittal's reach 2 to 3 mm to either side in front and about half of that in its hind third, and the whole line strays
# from the middle plane by about a millimetre: no real one is ruled (the owner, 14 November: "bones don't normally look
# perfectly straight like that").
TOOTHED = (5.3, 3.4, 8.9, 2.6)
SAGITTAL = dict(teeth=1.8, hind=0.55, drift=1.3, wave=(6.1, 4.3, 9.7, 3.1))
# The coronal suture's teeth are long only in its upper half: the plate draws loops of 2 mm and more down to page row 1400
# (61 mm above the Frankfurt plane) and a fine wavering line of a third of a millimetre from there to the pterion.
CORONAL_FINE_BELOW = (962, 1402)
