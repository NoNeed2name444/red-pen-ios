"""try_foot.py <bone> [h]: build one bone of the foot (foot.py) and draw it from the sides its plates are drawn from,
beside those plates if they are in <SCRATCH_OUT>/refs_foot. Writes look/foot_<bone>.jpg."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, view, foot
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
name = sys.argv[1]; h = float(sys.argv[2]) if len(sys.argv) > 2 else 0.4
VIEWS = {"calcaneus": [("from above (Fig. 264 is the left bone: mirrored)", (0, 1, 0.02)), ("lateral surface", (-1, 0.05, 0.0)),
                       ("medial surface", (1, 0.05, 0.0)), ("from behind", (0, 0.1, -1)), ("from in front", (0, 0.1, 1)), ("from below", (0, -1, 0.02))]}
PLATES = {"calcaneus": ["Gray264.png", "Gray266.png"]}
t0 = time.time()
F = foot.grain(getattr(foot, name)(h))
v, f = sdf.mesh(F.D, F.lo, F.h); parts = sdf.components(v, f); v, f = parts[0]; v = sdf.taubin(v, f, 4)
print("%s: %d faces, %d piece(s), box %s to %s, in %.0f s" % (name, len(f), len(parts), np.round(v.min(0), 1).tolist(), np.round(v.max(0), 1).tolist(), time.time() - t0))
np.savez(S + "/sb/foot_%s.npz" % name, v=v, f=f)
c = 0.5 * (v.min(0) + v.max(0)); span = float((v.max(0) - v.min(0)).max()) * 1.08
row = [(view.picture([(v, f, (232, 222, 200))], np.array(eye, float), 560, frame=(c, span)), cap) for cap, eye in VIEWS[name]]
rows = [row[:3], row[3:]]
ref = []
for p in PLATES.get(name, []):
    q = S + "/refs_foot/" + p
    if os.path.exists(q):
        im = Image.open(q).convert("RGB"); k = 560.0 / max(im.size); im = im.resize((int(im.size[0] * k), int(im.size[1] * k)))
        bg = Image.new("RGB", (560, 560), (255, 255, 255)); bg.paste(im, ((560 - im.size[0]) // 2, (560 - im.size[1]) // 2)); ref.append((bg, "Gray 1918, " + p[:-4].replace("Gray", "Fig. ") + " (left bone)"))
ref.append((view.picture([(v, f, (232, 222, 200))], np.array((0.75, 0.7, 0.55)), 560, frame=(c, span)), "from above, in front and the medial side"))
rows.append(ref)
view.sheet(rows, S + "/look/foot_%s.jpg" % name, title="from scratch: %s (right)" % name)
print(S + "/look/foot_%s.jpg" % name)
