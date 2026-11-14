"""trace_occiput.py <page 179 of Gray 1918 at 300 dpi, jpg> : the muscle areas of the occipital bone as the plate rings them.

Gray's Fig. 187 (the base of the skull from below, public domain) rings every muscle's attachment in red. Here the
red ink itself is found, the areas it encloses are taken as they are drawn, and their outlines are written to
occiput_traced.json in page pixels (plates.base_mm turns them into millimetres). The ridges of the occipital bone
are the borders between these areas, so the bone's relief is drawn from the plate and not from arcs of our own.
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

BOX = (280, 2100, 1420, 3420)               # the part of the page that holds the occipital bone and the mastoid
GROW = 5                                    # px: the ink is thickened by this to close the dashed lines
SEEDS = {                                   # a point inside each area (page pixels)
    "semispinalis capitis": (1061, 3118), "obliquus capitis superior": (817, 2745),
    "rectus capitis posterior minor": (1179, 2827), "rectus capitis posterior major": (958, 2700),
    "rectus capitis lateralis": (876, 2290), "digastric": (616, 2441), "trapezius": (969, 3239),
    "longissimus capitis": (504, 2451), "splenius capitis": (452, 2412), "sternocleidomastoid": (403, 2330),
}


def main(page):
    x0, y0, x1, y1 = BOX
    im = np.asarray(Image.open(page).convert("RGB").crop(BOX)).astype(np.int32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    red = (r > 95) & ((r - np.maximum(g, b)) > 0.3 * r) & (r - g > 38)
    wall = ndimage.binary_dilation(red, iterations=GROW)
    lab, n = ndimage.label(~wall)
    out = {}
    for name, (sx, sy) in SEEDS.items():
        k = lab[sy - y0, sx - x0]
        if k == 0:
            print("no area at the seed of", name); continue
        m = lab == k
        if m.sum() > 0.3 * m.size:
            print("the seed of", name, "lies in the open"); continue
        m = ndimage.binary_dilation(m, iterations=GROW)          # out to the middle of the ink
        m = ndimage.binary_fill_holes(m)
        c = max(measure.find_contours(m.astype(float), 0.5), key=len)
        c = measure.approximate_polygon(c, 1.2)
        P = np.column_stack([c[:, 1] + x0, c[:, 0] + y0])
        out[name] = np.round(P[:-1], 1).tolist()
        print("%-32s %3d points, %6d px" % (name, len(P) - 1, int(m.sum())))
    here = os.path.dirname(os.path.abspath(__file__))
    json.dump({"source": "Gray's Anatomy, 20th ed. (1918), Fig. 187, page 179 of the Internet Archive scan at 300 dpi; public domain",
               "units": "page pixels", "areas": out}, open(os.path.join(here, "occiput_traced.json"), "w"), indent=0)


if __name__ == "__main__":
    main(sys.argv[1])
