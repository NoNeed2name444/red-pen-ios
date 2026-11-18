"""floor_map.py <kept field> [--out tag] [--roof]: the floor of the cranial cavity seen from straight above, as a map: how
high each place stands (the grey: darker is lower, a line every 5 mm) with the light falling from the front left, so
that ridges and grooves show. --roof: the vault's inner surface from below instead. The cavity in each upright line of
the grid is what inner.py takes the cavity to be; its lower end is the floor. Prints the heights along the middle line."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw
import view, inner
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
arg = sys.argv[1:]; name = arg[0]
tag = arg[arg.index("--out") + 1] if "--out" in arg else name
ROOF = "--roof" in arg


def heights(D, lo, h):
    """(floor, roof): for every upright line of the grid, where the cranial cavity ends below and above (mm; nan where
    the line does not pass through the cavity): inner.py's own account of what the cavity is."""
    return inner.floors(inner.cavity(D, lo, h), lo, h)


def exact(D, lo, h, H, up):
    """The height taken to a fraction of a step from the field's own values either side of the surface."""
    ny = D.shape[1]; j = np.clip(np.round((np.nan_to_num(H, nan=lo[1]) - lo[1]) / h - 0.5).astype(int), 1, ny - 2)
    ii, kk = np.indices(j.shape)
    a = np.asarray(D[ii, j, kk], np.float32); b = np.asarray(D[ii, j + (1 if up else -1), kk], np.float32)   # bone below and air above the floor (the other way for the roof)
    a, b = (b, a) if not up else (a, b)
    t = np.clip(a / np.where(np.abs(a - b) > 1e-6, a - b, 1.0), 0.0, 1.0)
    return np.where(np.isnan(H), np.nan, lo[1] + h * (j + (t if up else -t)))


if __name__ == "__main__":
    I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); h = float(I["h"]); lo = np.asarray(I["lo"], float)
    D = np.load(S + "/sb/%s_D.npy" % name, mmap_mode="r")
    f, r = heights(D, lo, h)
    H = exact(D, lo, h, f, True) if not ROOF else exact(D, lo, h, r, False)
    x = lo[0] + h * np.arange(H.shape[0]); z = lo[2] + h * np.arange(H.shape[1])
    Hs = np.where(np.isnan(H), np.nanmin(H), H)
    gx, gz = np.gradient(Hs, h)
    L = np.array([0.45, 0.72, 0.52]); L /= np.linalg.norm(L)        # the light: from above, the front and the left (from below for the roof)
    s_ = 1.0 if not ROOF else -1.0
    shade = np.clip((-s_ * gx * L[0] + L[1] - s_ * gz * L[2]) / np.sqrt(gx * gx + 1.0 + gz * gz), 0.0, 1.0)
    lowv, highv = np.nanpercentile(H, 1), np.nanpercentile(H, 99)
    tone = 0.35 + 0.65 * np.clip((H - lowv) / max(highv - lowv, 1.0), 0, 1)
    img = (255 * np.clip(shade ** 0.8 * np.nan_to_num(tone, nan=0.0) * 1.25, 0, 1))
    line = (np.abs(((Hs + 2.5) % 5.0) - 2.5) < 0.12 * np.maximum(np.hypot(gx, gz), 0.25)) & ~np.isnan(H)
    rgb = np.stack([img * 0.98, img * 0.94, img * 0.84], -1)
    rgb[line] = rgb[line] * 0.55 + np.array([70, 40, 20]) * 0.45
    rgb[np.isnan(H)] = (22, 24, 28)
    pic = Image.fromarray(np.transpose(rgb, (1, 0, 2))[::-1].astype(np.uint8))   # x across (the skull's left to the right), the front at the top
    pic = pic.resize((pic.size[0] * 3, pic.size[1] * 3), Image.BICUBIC); d = ImageDraw.Draw(pic); ft = view.font(22)
    d.text((10, 8), "%s: the %s (front at the top; a line every 5 mm of height; %.0f to %.0f mm)" % (
        name, "vault's inner surface from below" if ROOF else "cranial floor from above", np.nanmin(H), np.nanmax(H)), fill=(240, 240, 240), font=ft)
    os.makedirs(S + "/look", exist_ok=True)
    pic.save(S + "/look/floor_%s%s.jpg" % (tag, "_roof" if ROOF else ""), quality=90)
    i0 = int(round((0.0 - lo[0]) / h))
    mid = H[i0]; ks = [int(round((zz - lo[2]) / h)) for zz in range(-90, 100, 6)]
    print("heights along the middle line (z: height):", " ".join("%d:%s" % (z[kk], "-" if np.isnan(mid[kk]) else "%.0f" % mid[kk]) for kk in ks if 0 <= kk < len(z)))
    for xx in (20, 40, 55):
        row = H[int(round((xx - lo[0]) / h))]
        print("heights 20, 40, 55 mm to the left, x = %d:" % xx, " ".join("%d:%s" % (z[kk], "-" if np.isnan(row[kk]) else "%.0f" % row[kk]) for kk in ks if 0 <= kk < len(z)))
    print(S + "/look/floor_%s%s.jpg" % (tag, "_roof" if ROOF else ""), pic.size)
