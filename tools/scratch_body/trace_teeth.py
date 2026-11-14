"""trace_teeth.py <page 1117 of Gray 1918 as an image, 300 dpi> <out.json> [check.png]

The outline of each permanent tooth seen from the cheek side, read off Gray's Anatomy 1918, Fig. 1002
("Permanent teeth. Right side", page 1117 of the Internet Archive scan anatomyofhumanbo1918gray; public domain).
The figure draws the sixteen kinds in two rows, upper teeth crown down and lower teeth crown up, third molar on
the left and central incisor on the right. Each tooth's drawn outline is filled, and for every height the spans
it covers are written down in the drawing's own pixels: one span through the crown and the root's trunk, two
where a molar's roots part. teeth2.py turns these into millimetres with the textbook sizes.
"""
import json, sys
import numpy as np
from PIL import Image
from scipy import ndimage

BOX = (0.18, 0.168, 0.83, 0.432)          # the figure on the page, as shares of its width and height


def masks(page):
    g = np.asarray(Image.open(page).convert("L"), float)
    H, W = g.shape
    x0, y0, x1, y1 = int(BOX[0] * W), int(BOX[1] * H), int(BOX[2] * W), int(BOX[3] * H)
    g = g[y0:y1, x0:x1]
    paper = ndimage.maximum_filter(ndimage.gaussian_filter(g, 2.0), 41)
    ink = g < paper - 24                                       # the drawn lines, the faint ones too
    blob = ndimage.binary_dilation(ndimage.binary_closing(ink, np.ones((9, 9), bool)), np.ones((5, 5), bool))
    lab, n = ndimage.label(blob)
    size = ndimage.sum(blob, lab, np.arange(1, n + 1))
    keep = np.argsort(size)[::-1][:16] + 1
    # the paper's own white, as far as it can go without squeezing through a gap in a drawn line
    shut = ndimage.binary_closing(ink, np.ones((7, 7), bool))
    free, m = ndimage.label(ndimage.binary_erosion(~shut, np.ones((13, 13), bool), border_value=1))
    edge = np.unique(np.concatenate([free[0], free[-1], free[:, 0], free[:, -1]]))
    outside = ndimage.binary_dilation(np.isin(free, edge[edge > 0]), np.ones((13, 13), bool)) & ~shut
    out = []
    for k in keep:
        t = ink & (lab == k)
        ys, xs = np.nonzero(t)
        out.append([t, ys.mean(), xs.mean()])
    mid = np.median([o[1] for o in out])
    rows = [sorted([o for o in out if o[1] < mid], key=lambda o: o[2]), sorted([o for o in out if o[1] >= mid], key=lambda o: o[2])]
    for r, lower in zip(rows, (False, True)):
        for j, o in enumerate(r):
            t = o[0]
            fill = np.zeros_like(t)
            ys = np.nonzero(t.any(1))[0]
            for y in ys:
                xs = np.nonzero(t[y])[0]
                fill[y, xs[0]:xs[-1] + 1] = True                 # between the outline's two sides
            if lower and j < 3:                                  # a lower molar's two roots stand apart
                # the gap between them is followed up from the root tips, row by row, in the paper's own white
                gap, prev = np.zeros_like(t), None
                for y in ys[::-1]:
                    if y < ys[0] + 0.35 * (ys[-1] - ys[0]):
                        break
                    xs = np.nonzero(t[y])[0]
                    r = np.concatenate([[False], outside[y, xs[0]:xs[-1] + 1], [False]])
                    d = np.diff(r.astype(np.int8))
                    runs = [(p + xs[0], q + xs[0]) for p, q in zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0])]
                    if prev is None:
                        runs = [u for u in runs if u[1] - u[0] >= 12]
                        if runs:
                            prev = max(runs, key=lambda u: u[1] - u[0])
                    else:
                        runs = [u for u in runs if u[0] < prev[1] and u[1] > prev[0] and u[1] - u[0] >= 3]
                        if not runs:
                            break
                        prev = max(runs, key=lambda u: min(u[1], prev[1]) - max(u[0], prev[0]))
                    if prev is not None:
                        gap[y, prev[0]:prev[1]] = True
                fill &= ~gap
            o[0] = fill; o.append(int(fill.sum()))
    return g, rows


def spans(m):
    """For each pixel row of a tooth's mask, the runs it covers: [(y, [(x0, x1), ...])]."""
    ys = np.nonzero(m.any(1))[0]
    out = []
    for y in range(ys[0], ys[-1] + 1):
        r = np.concatenate([[False], m[y], [False]])
        d = np.diff(r.astype(np.int8))
        a, b = np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]
        runs = [(int(p), int(q)) for p, q in zip(a, b) if q - p >= 4]
        out.append((int(y), runs))
    return out


if __name__ == "__main__":
    g, rows = masks(sys.argv[1])
    data = {}
    for arch, row in zip(("upper", "lower"), rows):
        for j, (m, cy, cx, n) in enumerate(row):
            data["%s %d" % (arch, 7 - j)] = spans(m)                # 7 the third molar ... 0 the central incisor
    json.dump({"source": "Gray's Anatomy 1918, Fig. 1002 (public domain), page 1117 of the Internet Archive scan", "pixels_per_inch": 300,
               "teeth": data}, open(sys.argv[2], "w"), separators=(",", ":"))
    print("teeth traced:", [len(r) for r in rows], "areas", [[o[3] for o in r] for r in rows])
    if len(sys.argv) > 3:
        rgb = np.stack([g, g, g], -1)
        for r, col in zip(rows, ((255, 120, 90), (90, 150, 255))):
            for m, cy, cx, n in r:
                rgb[m] = rgb[m] * 0.45 + np.array(col) * 0.55
        Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(sys.argv[3], quality=88)
