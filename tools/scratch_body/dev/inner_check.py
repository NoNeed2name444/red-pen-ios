"""inner_check.py <kept field> [<field before>] [--thin 1.2]: has the cranial cavity's new relief (inner.py) broken through
anywhere? For every place on the cavity's wall, how much bone lies between it and the nearest other air (the outside,
an air sinus, a canal, the orbit, the ear hole); the places where that is under --thin mm are listed in groups, each with
its middle. An opening that is meant (the great opening, the optic canals, the jugular openings, the oval and spinous
foramina, the meatus) is such a place too: with a field from before, only the groups that were not there before are
listed. Draws the thickness as a map from above and from below (look/thick_<field>.jpg)."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw
import inner, view
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
arg = sys.argv[1:]
THIN = float(arg[arg.index("--thin") + 1]) if "--thin" in arg else 1.2
names = [a for a in arg if not a.startswith("--") and arg[arg.index(a) - 1] != "--thin"]


def thin_places(name):
    I = pickle.load(open(S + "/sb/%s_info.pkl" % name, "rb")); h = float(I["h"]); lo = np.asarray(I["lo"], float)
    D = np.load(S + "/sb/%s_D.npy" % name, mmap_mode="r")
    cav = inner.cavity(D, lo, h); f, r = inner.floors(cav, lo, h)
    bone = np.asarray(D) < 0
    other = ~bone & ~ndimage.binary_dilation(cav, iterations=3)       # every other air (three steps off the cavity's own)
    t = ndimage.distance_transform_edt(~other).astype(np.float32) * h
    del other
    wall = bone & ndimage.binary_dilation(cav)                         # the bone that faces the cavity
    T = np.where(wall, t, np.inf)
    lab, n = ndimage.label(wall & (t < THIN), structure=np.ones((3, 3, 3)))
    groups = []
    if n:
        idx = np.arange(1, n + 1)
        size = ndimage.sum(np.ones(lab.shape, np.uint8), lab, idx); least = ndimage.minimum(t, lab, idx)
        for i, c in enumerate(ndimage.center_of_mass(wall, lab, idx)):
            if size[i] >= 4:
                groups.append((lo + h * np.array(c), int(size[i]), float(least[i])))
    # the least bone under the floor and over the roof of each upright line, for the maps
    down = np.where(np.isfinite(T), T, np.inf)
    ny = T.shape[1]; y = lo[1] + h * np.arange(ny)
    low = y[None, :, None] < (np.nan_to_num(f, nan=1e9) + 1.0)[:, None, :]
    return groups, (np.where(low, down, np.inf).min(axis=1), np.where(~low, down, np.inf).min(axis=1)), lo, h, int(wall.sum())


def picture(maps, lo, h, name):
    out = []
    for M, cap in zip(maps, ("under the floor (from above)", "over the roof and in the walls (from above)")):
        v = np.clip(M / 8.0, 0, 1); bad = M < THIN; none = ~np.isfinite(M)
        rgb = np.stack([60 + 190 * v, 60 + 180 * v, 70 + 150 * v], -1)
        rgb[M < 3.0] = (235, 170, 60); rgb[bad] = (225, 40, 40); rgb[none] = (22, 24, 28)
        pic = Image.fromarray(np.transpose(rgb, (1, 0, 2))[::-1].astype(np.uint8)); pic = pic.resize((pic.size[0] * 2, pic.size[1] * 2), Image.NEAREST)
        ImageDraw.Draw(pic).text((8, 6), "%s: bone %s; red under %.1f mm, orange under 3, grey to white up to 8" % (name, cap, THIN), fill=(240, 240, 240), font=view.font(18))
        out.append(pic)
    W = sum(p.size[0] for p in out); sheet = Image.new("RGB", (W, out[0].size[1])); x = 0
    for p in out:
        sheet.paste(p, (x, 0)); x += p.size[0]
    os.makedirs(S + "/look", exist_ok=True); sheet.save(S + "/look/thick_%s.jpg" % name, quality=88)
    return S + "/look/thick_%s.jpg" % name, sheet.size


if __name__ == "__main__":
    now, maps, lo, h, nwall = thin_places(names[0])
    print("%s: %d places of the wall measured; %d groups under %.1f mm" % (names[0], nwall, len(now), THIN))
    old = thin_places(names[1])[0] if len(names) > 1 else []
    for c, n, least in sorted(now, key=lambda g: -g[1]):
        was = any(np.linalg.norm(c - c0) < 6.0 for c0, _, _ in old)
        if not was or len(names) == 1:
            print("  %s x %6.1f y %6.1f z %6.1f: %5d cells, least %.1f mm" % ("NEW" if old else "   ", c[0], c[1], c[2], n, least))
    print(*picture(maps, lo, h, names[0]))
