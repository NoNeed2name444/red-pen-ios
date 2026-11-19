"""match_plates.py <bone> [h] [--fit] [--plain] [--hull] [--only=Gray264,..]: the bone drawn in each of its plates' own
frames (platematch.py) and under each plate's own light, beside the plate, with both outlines laid over each other,
how far apart they lie, and how alike the plate's shading and the model's are (1 the same picture, 0 no likeness).
Writes look/match_<bone>.jpg. --plain leaves the plates' relief off (what the relief adds shows by comparison).
--fit finds each plate's angle, scale and place afresh (kept in sb/platefit_<bone>.json and reused without it)."""
import os, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view, foot, platematch as pm
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
args = [a for a in sys.argv[1:] if not a.startswith("--")]; flags = [a for a in sys.argv[1:] if a.startswith("--")]
name = args[0]; h = float(args[1]) if len(args) > 1 else 0.4
only = [a.split("=")[1].split(",") for a in flags if a.startswith("--only=")]
keep = S + "/sb/platefit_%s.json" % name
poses = json.load(open(keep)) if os.path.exists(keep) else {}        # sb/platefit: poses being tried; else the ones the traces were made at
t0 = time.time()
F = (lambda f: f if "--hull" in flags else foot.grain(f))(getattr(foot, name)(h, log=lambda *a: None, **({"relief": 0.0} if "--plain" in flags else {}), **({"upto": "hull"} if "--hull" in flags else {})))
print("%s built in %.0f s" % (name, time.time() - t0))


def cell(a, cap, box=620):
    im = Image.fromarray(a).convert("RGB"); k = box / max(im.size); im = im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)
    bg = Image.new("RGB", (box, box), (255, 255, 255)); bg.paste(im, ((box - im.size[0]) // 2, (box - im.size[1]) // 2)); return bg, cap


rows = []
for v in pm.PLATES[name]:
    if only and v["fig"] not in only[0]:
        continue
    gray = np.array(Image.open(S + "/refs_foot/%s.png" % v["fig"]).convert("L")); mask = pm.silhouette(gray, erase=v.get("erase", ())); H, W = mask.shape
    pose = [float(x) for x in poses.get(v["fig"], foot.traces(name)[v["fig"] + "_pose"])]
    if "--fit" in flags:
        pose, _ = pm.fit(F, v, mask, start=pose, log=print); poses[v["fig"]] = [round(float(x), 3) for x in pose]
    px = v["s"] * pose[3]; depth, N = pm.cast(F, pm.basis(v, pose[:3]), px, v["u0"] + pose[4], v["v0"] + pose[5], (W, H)); got = ~np.isnan(depth)
    tone, ok, _ = pm.tone_of(gray, mask, px); w = ok * got * np.clip((N[..., 2] - 0.15) / 0.35, 0, 1)
    a, b, L, r2 = pm.light_of(tone, N, w)                       # the model is drawn under the plate's own light
    pale = pm.seen(F, F.smooth, pm.basis(v, pose[:3]), px, v["u0"] + pose[4], v["v0"] + pose[5], depth) if hasattr(F, "smooth") else None
    pic = pm.shade(depth, N, px, light=L); like = pm.likeness(tone, pic / 255.0, w, px)
    pic = np.where(got, pm.in_tones(pic, tone, w > 0.3), 255).astype(np.uint8)       # shown at the plate's own contrast
    mean, p95, worst = pm.gap(got, mask, px)
    print("%s %-16s overlap %.3f; outlines apart: mean %.2f mm, worst twentieth %.2f mm, worst %.2f mm; shading alike %.2f (nod %.1f turn %.1f roll %.1f scale %.3f)"
          % (v["fig"], v["cap"], pm.iou(got, mask), mean, p95, worst, like, *pose[:4]))
    over = np.stack([255 - (255 - gray) // 3] * 3, -1).astype(np.uint8)
    over[pm.edge(mask)] = (220, 30, 30); over[pm.edge(got)] = (20, 90, 230)
    fig = v["fig"].replace("Gray", "Fig. ")
    rows.append([cell(gray, "Gray 1918, %s: %s (left bone)" % (fig, v["cap"])), cell(pic, "the model: same side, angle, light and contrast; shading alike %.2f" % like),
                 cell(over, "outlines: plate red, model blue; mean %.1f mm apart, worst %.1f" % (mean, worst))])
json.dump(poses, open(keep, "w"), indent=1)
view.sheet(rows, S + "/look/match_%s.jpg" % name, title="from scratch: %s against its plates" % name)
print(S + "/look/match_%s.jpg" % name, "in %.0f s" % (time.time() - t0))
