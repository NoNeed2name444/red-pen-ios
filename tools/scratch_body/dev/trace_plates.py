"""trace_plates.py <bone>: what a bone's plates give its model, taken from the plates themselves and kept in
traces/<bone>_plates.npz: each plate's outline as a signed distance (mm, in the plate's own pixels), its shading as
tone with how far each pixel of it is to be trusted (platematch.tone_of: hatching run together, label lines painted
over, the inked outline left out), and the angle, scale and place it is read at (platematch's, or
sb/platefit_<bone>.json while a fit from fit_plates.py or match_plates.py --fit is being tried).
Writes look/tone_<bone>.jpg (plate with the painted lines | tone | trust). The builder turns the tone into relief
against the model's own faces (foot.emboss)."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, platematch as pm
from scipy import ndimage as ndi
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
name = sys.argv[1]
poses = json.load(open(S + "/sb/platefit_%s.json" % name)) if os.path.exists(S + "/sb/platefit_%s.json" % name) else {}


keep = {}; cells = []
for v in pm.PLATES[name]:
    gray = np.array(Image.open(S + "/refs_foot/%s.png" % v["fig"]).convert("L")); mask = pm.silhouette(gray, erase=v.get("erase", ()))
    pose = poses.get(v["fig"], list(v["pose"])); px = v["s"] * pose[3]
    d = (ndi.distance_transform_edt(~mask) - ndi.distance_transform_edt(mask)).astype(np.float32)
    d = ndi.gaussian_filter(d + np.where(mask, 0.5, -0.5), 1.0) * px
    tone, ok, line = pm.tone_of(gray, mask, px)
    keep[v["fig"] + "_sdf"] = d.astype(np.float16); keep[v["fig"] + "_pose"] = np.array(pose, np.float32)
    keep[v["fig"] + "_tone"] = np.round(tone * 255).astype(np.uint8); keep[v["fig"] + "_ok"] = np.round(ok * 255).astype(np.uint8)
    print("%s: outline area %.0f mm2, %d px of label lines painted over" % (v["fig"], mask.sum() * px * px, line.sum()))
    a = np.concatenate([np.where(line, 0, gray), (np.clip(tone, 0, 1) * 255).astype(np.uint8), (ok * 255).astype(np.uint8)], 1)
    cells.append(Image.fromarray(a))
np.savez_compressed(HERE + "/traces/%s_plates.npz" % name, **keep)
W = max(c.size[0] for c in cells); sheet = Image.new("L", (W, sum(c.size[1] for c in cells)), 255); y = 0
for c in cells:
    sheet.paste(c, (0, y)); y += c.size[1]
sheet.save(S + "/look/tone_%s.jpg" % name, quality=88)
print(HERE + "/traces/%s_plates.npz" % name, os.path.getsize(HERE + "/traces/%s_plates.npz" % name) // 1024, "KB;", S + "/look/tone_%s.jpg" % name)
