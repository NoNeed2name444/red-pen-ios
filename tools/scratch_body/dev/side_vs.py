"""side_vs.py <name> [--nojaw]: the model's left side beside the same piece of Gray's Fig. 188 (page 182), frame for frame."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view, plates
from scipy import ndimage
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]
Z = np.load(S + "/sb/%s.npz" % name)
meshes = [(Z["v"], Z["f"], view.BONE)]
if "tv" in Z:
    meshes.append((Z["tv"], Z["tf"], (240, 236, 222)))
if "mv" in Z and "--nojaw" not in sys.argv:
    meshes.append((Z["mv"], Z["mf"], view.BONE))
page = np.asarray(Image.open(S + "/gray1918/pages/p-0182.jpg").convert("RGB"), np.float32)
F = plates.side_frame(plates.traces()["side_silhouette_px"])
N = 900
def plate(c, span):
    """The plate resampled into the model's own frame: screen right is toward the back of the head (-z), up is +y."""
    j, i = np.meshgrid(np.arange(N), np.arange(N))
    z = c[2] + span / 2 - (j + 0.5) * span / N; y = c[1] + span / 2 - (i + 0.5) * span / N
    px = F.px(np.column_stack([z.ravel(), y.ravel()]))
    out = np.stack([ndimage.map_coordinates(page[:, :, k], [px[:, 1], px[:, 0]], order=1, mode="nearest") for k in range(3)], -1)
    return Image.fromarray(out.reshape(N, N, 3).astype(np.uint8))
sets = (("ear, joint and mastoid", (0, -8, 8), 84), ("the same, close", (0, -8, 2), 52)) if "--face" not in sys.argv else (("cheek bone and arch", (0, -2, 45), 84), ("upper jaw", (0, -22, 78), 60))
rows = []
for label, c, span in sets:
    m = view.picture(meshes, (1, 0, 0), N, frame=(np.array(c, float), float(span)))
    rows.append([(plate(c, span), "Gray 1918, Fig. 188 (public domain): " + label), (m, "the model from the left, same frame: " + label)])
out = S + "/look/%s_side_vs.png" % name
view.sheet(rows, out, "%s: the side of the head, plate beside model" % name)
im = Image.open(out); im.thumbnail((1700, 1700)); im.convert("RGB").save(out[:-4] + ".jpg", quality=88)
print(out[:-4] + ".jpg")
