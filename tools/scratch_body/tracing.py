"""tracing.py: take outlines off a reference plate (a scanned page of a public-domain atlas).

Nothing here is 3D: a plate is a flat picture. What is taken from it is where lines run on the page
(a silhouette, the edge of a coloured bone, a line picked by hand), turned into millimetres by two
marked points whose real distance is known.

  python3 -I tracing.py page <pdf> <page> <out.jpg>            render a page at 300 dpi
  python3 -I tracing.py grid <image> <out.jpg> x0 y0 x1 y1 [step] [width]   a crop with a pixel grid, to read points off
"""
import subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage


def page(pdf, number, out, dpi=300):
    stem = out.rsplit(".", 1)[0]
    subprocess.run(["pdftoppm", "-q", "-r", str(dpi), "-f", str(number), "-l", str(number), "-jpeg", "-jpegopt",
                    "quality=93", "-singlefile", pdf, stem], check=True)
    return stem + ".jpg"


def font(px):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        try:
            return ImageFont.truetype(p, px)
        except OSError:
            pass
    return ImageFont.load_default()


def grid(image, out, box, step=100, width=1400, marks=(), lines=()):
    """A crop of the plate with a grid in the plate's own pixels (labelled), to read coordinates from."""
    im = Image.open(image).convert("RGB") if isinstance(image, str) else image
    x0, y0, x1, y1 = box
    c = im.crop(box)
    k = width / c.size[0]
    c = c.resize((width, int(round(c.size[1] * k))), Image.LANCZOS)
    d = ImageDraw.Draw(c, "RGBA"); f = font(15)
    for x in range((x0 // step + 1) * step, x1, step):
        d.line([((x - x0) * k, 0), ((x - x0) * k, c.size[1])], fill=(0, 90, 255, 110), width=1)
        d.text(((x - x0) * k + 2, 2), str(x), fill=(0, 60, 220, 255), font=f)
    for y in range((y0 // step + 1) * step, y1, step):
        d.line([(0, (y - y0) * k), (c.size[0], (y - y0) * k)], fill=(0, 90, 255, 110), width=1)
        d.text((2, (y - y0) * k + 2), str(y), fill=(0, 60, 220, 255), font=f)
    for pts, col in lines:
        d.line([((x - x0) * k, (y - y0) * k) for x, y in pts], fill=col, width=2)
    for (x, y), col in marks:
        r = 5
        d.ellipse([(x - x0) * k - r, (y - y0) * k - r, (x - x0) * k + r, (y - y0) * k + r], outline=col, width=2)
    c.save(out, quality=88)
    return c.size


def paper(rgb):
    """The paper's colour: the commonest light colour of the page."""
    a = rgb.reshape(-1, 3)[::17]
    a = a[a.sum(1) > 540]
    return np.median(a, axis=0)


def ink(rgb, tol=38):
    """Everything that is not bare paper: lines, shading, colour."""
    p = paper(rgb)
    return np.abs(rgb.astype(np.int16) - p).sum(-1) > tol


def silhouette(mask, close=4, open_=3):
    """The filled outline of the largest drawn thing: gaps in its line closed, lettering and leader lines dropped."""
    m = ndimage.binary_closing(mask, iterations=close)
    m = ndimage.binary_fill_holes(m)
    m = ndimage.binary_opening(m, iterations=open_)
    lab, n = ndimage.label(m)
    if n == 0:
        return m
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = lab == 1 + int(np.argmax(sizes))
    return ndimage.binary_fill_holes(m)


def outline(mask, step=2.0):
    """The silhouette's edge as a closed line of (x, y) pixels, evenly spaced."""
    from skimage import measure
    cs = measure.find_contours(mask.astype(float), 0.5)
    c = max(cs, key=len)[:, ::-1]
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(c, axis=0), axis=1))])
    t = np.arange(0, d[-1], step)
    return np.column_stack([np.interp(t, d, c[:, 0]), np.interp(t, d, c[:, 1])])


class Frame:
    """Pixels of a plate to millimetres of a view: two marked points with a known distance fix the scale,
    a direction that should be level fixes the turn, and one point fixes the origin."""
    def __init__(self, a_px, b_px, mm, level=None, origin_px=None, origin_mm=(0.0, 0.0), flip=False):
        a, b = np.asarray(a_px, float), np.asarray(b_px, float)
        self.k = mm / np.linalg.norm(b - a)                         # mm per pixel
        l0, l1 = (a, b) if level is None else (np.asarray(level[0], float), np.asarray(level[1], float))
        self.t = np.arctan2(l1[1] - l0[1], l1[0] - l0[0])            # the page direction that is level in life
        self.o = a if origin_px is None else np.asarray(origin_px, float)
        self.o_mm = np.asarray(origin_mm, float); self.flip = flip

    def mm(self, p):
        """(u, v) in mm: u along the level direction, v up."""
        p = np.atleast_2d(np.asarray(p, float)) - self.o
        c, s = np.cos(-self.t), np.sin(-self.t)
        u = (p[:, 0] * c - p[:, 1] * s) * self.k
        v = -(p[:, 0] * s + p[:, 1] * c) * self.k
        if self.flip:
            u = -u
        return np.column_stack([u, v]) + self.o_mm

    def px(self, q):
        q = np.atleast_2d(np.asarray(q, float)) - self.o_mm
        u = -q[:, 0] if self.flip else q[:, 0]
        x, y = u / self.k, -q[:, 1] / self.k
        c, s = np.cos(self.t), np.sin(self.t)
        return np.column_stack([x * c - y * s, x * s + y * c]) + self.o


if __name__ == "__main__":
    if sys.argv[1] == "page":
        print(page(sys.argv[2], int(sys.argv[3]), sys.argv[4]))
    elif sys.argv[1] == "grid":
        b = [int(v) for v in sys.argv[4:8]]
        step = int(sys.argv[8]) if len(sys.argv) > 8 else 100
        width = int(sys.argv[9]) if len(sys.argv) > 9 else 1400
        print(grid(sys.argv[2], sys.argv[3], b, step, width))
