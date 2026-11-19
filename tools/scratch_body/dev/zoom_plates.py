"""zoom_plates.py <bone> <fig> [h] [--k=3] [--pick=u,v;u,v;..] [--plain] [--over] [--save=file | --load=file]: one plate enlarged beside the model drawn in
its frame, both under the same grid of the plate's own pixels (a line every 20, numbered), so a landmark's place can be
read off the plate and looked for on the model. --pick prints where the model's surface lies under plate pixels (x, y,
z in mm). Writes look/zoom_<bone>_<fig>.jpg."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, foot, platematch as pm
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
args = [a for a in sys.argv[1:] if not a.startswith("--")]; flags = dict(a[2:].split("=") if "=" in a else (a[2:], "") for a in sys.argv[1:] if a.startswith("--"))
name, fig = args[0], args[1]; h = float(args[2]) if len(args) > 2 else 0.4; k = int(flags.get("k", 3))
v = [p for p in pm.PLATES[name] if p["fig"] == fig][0]
if "load" in flags:                                          # a bone built before (dev/zoom_plates.py ... --save=file)
    F = pickle.load(open(flags["load"], "rb"))
else:
    F = foot.grain(getattr(foot, name)(h, log=lambda *a: None, **({"relief": 0.0} if "plain" in flags else {})))
    if "save" in flags:
        pickle.dump(F, open(flags["save"], "wb"))
gray = np.array(Image.open(S + "/refs_foot/%s.png" % fig).convert("L")); H, W = gray.shape
pose = [float(x) for x in foot.traces(name)[fig + "_pose"]]
B = pm.basis(v, pose[:3]); s = v["s"] * pose[3]
# drawn k times finer than the plate, in the same frame
depth, N = pm.cast(F, B, s / k, (v["u0"] + pose[4] + 0.5) * k - 0.5, (v["v0"] + pose[5] + 0.5) * k - 0.5, (W * k, H * k))
big = np.array(Image.fromarray(gray).resize((W * k, H * k), Image.LANCZOS)); mask = pm.silhouette(gray, erase=v.get("erase", ()))
tone, ok, _ = pm.tone_of(big, np.array(Image.fromarray(mask).resize((W * k, H * k))), s / k); w = ok * ~np.isnan(depth) * np.clip((N[..., 2] - 0.15) / 0.35, 0, 1)
a_, b_, L, _ = pm.light_of(tone, N, w)                       # under the plate's own light and at its contrast
pale = pm.seen(F, F.smooth, B, s / k, (v["u0"] + pose[4] + 0.5) * k - 0.5, (v["v0"] + pose[5] + 0.5) * k - 0.5, depth) if hasattr(F, "smooth") else None
pic = pm.shade(depth, N, s / k, light=L); print("shading alike %.2f" % pm.likeness(tone, pic / 255.0, w, s / k))
pic = np.where(~np.isnan(depth), pm.in_tones(pic, tone, w > 0.3), 255).astype(np.uint8)


def grid(a):
    im = Image.fromarray(a).convert("RGB"); d = ImageDraw.Draw(im)
    for x in range(0, W, 20):
        d.line([(x * k, 0), (x * k, H * k)], fill=(255, 120, 0) if x % 100 == 0 else (120, 170, 255), width=1); d.text((x * k + 2, 2), str(x), fill=(200, 0, 0))
    for y in range(0, H, 20):
        d.line([(0, y * k), (W * k, y * k)], fill=(255, 120, 0) if y % 100 == 0 else (120, 170, 255), width=1); d.text((2, y * k + 2), str(y), fill=(200, 0, 0))
    return im


a = grid(np.array(Image.fromarray(gray).resize((W * k, H * k), Image.LANCZOS))); b = grid(pic)
tall = H > W; n = 3 if "over" in flags else 2
sheet = Image.new("RGB", (W * k * (n if tall else 1), H * k * (1 if tall else n)), (255, 255, 255))
sheet.paste(a, (0, 0)); sheet.paste(b, (W * k, 0) if tall else (0, H * k))
if "over" in flags:                                          # --over: the model's own edges (where its shading breaks) drawn in blue on the plate
    from skimage import feature
    lines = feature.canny(pic.astype(float) / 255.0, sigma=1.0 * k, low_threshold=0.03, high_threshold=0.09) & ~np.isnan(depth)
    o = np.stack([255 - (255 - big) // 2] * 3, -1).astype(np.uint8); o[lines] = (0, 60, 255)
    hit = ~np.isnan(depth); o[hit & ~np.roll(hit, 1, 0) | hit & ~np.roll(hit, 1, 1) | hit & ~np.roll(hit, -1, 0) | hit & ~np.roll(hit, -1, 1)] = (0, 160, 60)
    c = grid(o); sheet.paste(c, (2 * W * k, 0) if tall else (0, 2 * H * k))
out = S + "/look/zoom_%s_%s%s.jpg" % (name, fig, flags.get("tag", ""))
sheet.save(out, quality=88); print(out, sheet.size)
for p in [q for q in flags.get("pick", "").split(";") if q]:
    u, w = [float(t) for t in p.split(",")]
    d = depth[int(round((w + 0.5) * k - 0.5)), int(round((u + 0.5) * k - 0.5))]
    P = (u - v["u0"] - pose[4]) * s * B[0] + (v["v0"] + pose[5] - w) * s * B[1] + (0 if np.isnan(d) else d) * B[2]
    print("  plate (%.0f, %.0f): %s" % (u, w, "nothing there" if np.isnan(d) else "x %.1f y %.1f z %.1f" % tuple(P)))
