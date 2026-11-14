"""plate_side.py field x0 y0 x1 y1 out [zoom]: the built skull's left side laid over Gray's side view (Fig. 188), pixel for pixel.

For the part of the page from (x0, y0) to (x1, y1) it draws three panels: the plate; the model's outer surface seen from the
left, shaded, with the plate's ink drawn over it in red; and the model alone. What the plate draws and the model lacks, or
has in another place, shows at once. `field` is a kept field (dev/save_field.py)."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, plates
from scipy import ndimage
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
name = sys.argv[1]; x0, y0, x1, y1 = [int(a) for a in sys.argv[2:6]]; out = sys.argv[6]; zoom = float(sys.argv[7]) if len(sys.argv) > 7 else 1.0
D = np.load(S + "/sb/%s_D.npy" % name).astype(np.float32); info = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); lo, h = info["lo"], info["h"]
T = plates.traces(); F = plates.side_frame(T["side_silhouette_px"])
W, H = int((x1 - x0) * zoom), int((y1 - y0) * zoom)
U, V = np.meshgrid(x0 + (np.arange(W) + 0.5) / zoom, y0 + (np.arange(H) + 0.5) / zoom)
zy = np.asarray(F.mm(np.column_stack([U.ravel(), V.ravel()])))
# the outermost bone on each line that runs from side to side through (z, y): the first cell inside, coming in from the left
inside = D < 0
ix = inside.shape[0] - 1 - np.argmax(inside[::-1], axis=0)                 # (ny, nz): the highest x index that is bone
has = inside.any(axis=0)
d0 = np.take_along_axis(D, ix[None], 0)[0]; d1 = np.take_along_axis(D, np.minimum(ix + 1, D.shape[0] - 1)[None], 0)[0]
X = lo[0] + h * (ix + np.where(d1 > d0, -d0 / np.maximum(d1 - d0, 1e-6), 0.0)); X[~has] = np.nan
jy, jz = (zy[:, 1] - lo[1]) / h, (zy[:, 0] - lo[2]) / h
Xp = ndimage.map_coordinates(np.nan_to_num(X, nan=-50.0), [jy, jz], order=1, mode="nearest").reshape(H, W)
gz, gy = np.gradient(ndimage.gaussian_filter(Xp, 0.6)); s = 1.0 / (zoom * 9.8)       # mm per picture pixel, about
n = np.dstack([-gy / s, -gz / s, np.ones_like(Xp)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
light = np.array([-0.45, -0.35, 0.82]); shade = np.clip(n @ light, 0.05, 1.0) ** 0.9
shade[Xp < -20] = 0.08
model = Image.fromarray((np.dstack([shade * 232, shade * 224, shade * 205])).astype(np.uint8))
page = Image.open(S + "/gray1918/pages/p-0182.jpg").convert("RGB").crop((x0, y0, x1, y1)).resize((W, H), Image.LANCZOS)
ink = np.asarray(page.convert("L"), float); ink = np.clip((150.0 - ndimage.gaussian_filter(ink, 0.5)) / 60.0, 0, 1)      # the plate's dark lines
both = np.asarray(model, float); both = both * (1 - 0.85 * ink[..., None]) + np.array([225.0, 30.0, 20.0]) * 0.85 * ink[..., None]
sheet = Image.new("RGB", (3 * W + 20, H + 24), (20, 22, 28)); dr = ImageDraw.Draw(sheet)
for k, (im, t) in enumerate(((page, "Gray 1918, Fig. 188"), (Image.fromarray(both.astype(np.uint8)), "the model, the plate's ink over it in red"), (model, "the model"))):
    sheet.paste(im, (k * (W + 10), 24)); dr.text((k * (W + 10) + 4, 6), t, fill=(220, 220, 220))
step = 100
for k in range(3):
    for gx in range((x0 // step + 1) * step, x1, step):
        px = k * (W + 10) + (gx - x0) * zoom; dr.line([(px, 24), (px, 32)], fill=(90, 140, 255)); dr.text((px + 2, 26), str(gx), fill=(90, 140, 255))
    for gy_ in range((y0 // step + 1) * step, y1, step):
        py = 24 + (gy_ - y0) * zoom; dr.line([(k * (W + 10), py), (k * (W + 10) + 8, py)], fill=(90, 140, 255)); dr.text((k * (W + 10) + 10, py - 5), str(gy_), fill=(90, 140, 255))
sheet.save(out, quality=90); print(out, sheet.size)
