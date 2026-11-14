"""close.py <name> <set>: close-up pictures of a built skull (and its teeth) for checking a region."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, view
from PIL import Image
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
name = sys.argv[1]; which = sys.argv[2] if len(sys.argv) > 2 else "face"
Z = np.load(S + "/sb/%s.npz" % name)
meshes = [(Z["v"], Z["f"], view.BONE)]
if "tv" in Z:
    meshes.append((Z["tv"], Z["tf"], (240, 236, 222)))
if "mv" in Z:
    meshes.append((Z["mv"], Z["mf"], view.BONE))
SETS = {
    "face": [("front", (0, 0, 1), (0, -8, 80), 150), ("left side, face", (1, 0, 0), (0, -8, 55), 150),
             ("three-quarter", (0.62, 0.12, 0.77), (0, -5, 60), 170), ("from below and in front", (0.35, -0.65, 0.67), (0, -15, 50), 170)],
    "base": [("below", (0, -1, 0), (0, 0, 10), 190), ("below, front half", (0, -1, 0), (0, 0, 55), 110),
             ("from below and behind", (0.3, -0.72, -0.62), (0, -5, 0), 190), ("from below and the side", (0.75, -0.6, 0.25), (0, -5, 20), 190)],
    "ear": [("left side, ear", (1, 0, 0), (0, -10, 2), 90), ("from below, left half", (0, -1, 0), (30, 0, 5), 100),
            ("from behind and below", (0.45, -0.5, -0.74), (30, -10, -5), 110), ("from in front and below", (0.5, -0.6, 0.62), (25, -10, 20), 110)],
    "nose": [("front, nose and orbits", (0, 0, 1), (0, 5, 80), 100), ("into the left orbit", (0.38, 0.05, 0.92), (30, 16, 70), 60),
             ("palate from below", (0, -1, 0), (0, 0, 62), 90), ("from behind: choanae", (0, -0.25, -0.97), (0, -22, 30), 62)],
    "ptery": [("from behind and a little below: choanae", (0, -0.3, -0.95), (0, -22, 30), 60), ("from behind, below and the side", (0.5, -0.35, -0.79), (10, -24, 34), 60),
              ("from below: hind edge of the palate", (0, -1, 0), (0, 0, 38), 60), ("from the side and below", (0.9, -0.35, 0.25), (20, -24, 36), 60)],
    "palate": [("palate from below", (0, -1, 0), (0, 0, 68), 66), ("from below and behind", (0.0, -0.8, -0.6), (0, -34, 62), 70),
               ("from below, behind and the side", (0.45, -0.75, -0.48), (0, -34, 62), 70), ("from behind: choanae and the palate's edge", (0, -0.3, -0.95), (0, -24, 34), 60)],
    "palcorner": [("hind corner of the palate, from below", (0, -1, 0), (17, 0, 47), 30), ("the same from below and behind", (0.2, -0.75, -0.63), (17, -34, 46), 30),
                  ("incisive fossa, from below", (0, -1, 0), (0, 0, 84), 30), ("across suture, from below", (0, -1, 0), (6, 0, 57), 30)],
    "maxilla": [("upper jaw, left, from the front", (0, 0, 1), (20, -24, 85), 46), ("from the side", (1, 0, 0), (20, -24, 80), 46),
                ("three-quarter", (0.62, 0.1, 0.78), (20, -24, 85), 46), ("three-quarter from below", (0.55, -0.45, 0.7), (20, -26, 85), 46)],
    "nosehole": [("nose opening, front", (0, 0, 1), (0, -8, 90), 52), ("three-quarter", (0.5, 0.05, 0.86), (0, -8, 88), 56),
                 ("from below and in front", (0, -0.55, 0.83), (0, -12, 90), 52), ("from the side and in front", (0.85, 0.0, 0.52), (0, -8, 88), 56)],
    "occiput": [("from below and behind", (0.3, -0.72, -0.62), (0, -8, -50), 130), ("from behind", (0, -0.1, -1), (0, -5, -60), 130),
                ("from below, hind half", (0, -1, 0), (0, 0, -45), 110), ("from behind and the side, low light", (0.75, -0.35, -0.56), (10, -8, -50), 130)],
    "openings": [("from below: the middle of the base", (0, -1, 0), (0, 0, 2), 100), ("from below: left half, close", (0, -1, 0), (27, 0, 8), 52),
                 ("great opening, from below", (0, -1, 0), (0, 0, -16), 60), ("from below and the side", (0.55, -0.8, 0.2), (25, -10, 6), 70)],
    "vault": [("left side", (1, 0, 0), (0, 30, 8), 235), ("top", (0, 1, 0), (0, 30, 8), 235),
              ("back", (0, 0, -1), (0, 30, 8), 235), ("from above and in front", (0.5, 0.6, 0.62), (0, 30, 8), 235)],
}
if "--nojaw" in sys.argv:
    meshes = meshes[:2] if "tv" in Z else meshes[:1]
    if "tv" in Z and "nt" in Z:
        k = int(Z["nt"]); tv, tf = Z["tv"], Z["tf"]; keep = (tf < k).all(1); meshes[1] = (tv[:k], tf[keep], (240, 236, 222))
def one(k):
    label, eye, c, span = SETS[which][k]
    return view.picture(meshes, eye, 900, frame=(np.array(c, float), float(span)))
jobs = int(sys.argv[sys.argv.index("--jobs") + 1]) if "--jobs" in sys.argv else 2
if jobs > 1:                                              # the four views side by side (each worker shares the meshes)
    import multiprocessing as mp
    with mp.get_context("fork").Pool(jobs) as pool:
        pics = pool.map(one, range(len(SETS[which])))
else:
    pics = [one(k) for k in range(len(SETS[which]))]
rows = [[], []]
for k, (label, eye, c, span) in enumerate(SETS[which]):
    rows[k // 2].append((pics[k], label))
tag = which + ("_nojaw" if "--nojaw" in sys.argv else "")
view.sheet(rows, S + "/look/%s_%s.png" % (name, tag), "%s: %s" % (name, tag))
im = Image.open(S + "/look/%s_%s.png" % (name, tag)); im.thumbnail((1560, 1560)); im.convert("RGB").save(S + "/look/%s_%s.jpg" % (name, tag), quality=86)
print(S + "/look/%s_%s.jpg" % (name, tag))
