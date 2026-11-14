"""try_jaw.py h name [--skull skullNN] [--smooth]: build the lower jaw alone (mandible4), stand its teeth, check the fit, save and show it."""
import os
import sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, view, mandible4, teeth
from scipy.spatial import cKDTree
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
h = float(sys.argv[1]); out = sys.argv[2]
t0 = time.time()
FM, info = mandible4.build(h)
Dm, lom = mandible4.whole(FM, info, rough="--smooth" not in sys.argv)
mv, mf = sdf.mesh(Dm, lom, h); mp = sdf.components(mv, mf); mv, mf = mp[0]; mv = sdf.taubin(mv, mf, 6)
print("jaw", len(mf), "pieces", [len(q[1]) for q in mp][:5], "in %.0f s" % (time.time() - t0))
lower = []; faces = []; n0 = 0
for name, side, w, g in teeth.stand(info["sockets"], False):
    lower.append(w); faces.append(g + n0); n0 += len(w)
tv, tf = np.concatenate(lower), np.concatenate(faces)
dl = sdf.sample_field(Dm, lom, h, tv)
print("lower teeth against the jaw's bone: least clearance %.2f mm, %d points inside" % (dl.min(), int((dl < 0).sum())))
if "--skull" in sys.argv:
    Z = np.load(S + "/sb/%s.npz" % sys.argv[sys.argv.index("--skull") + 1]); sv = Z["v"]
    sv = sv[(sv[:, 1] < 12) & (sv[:, 1] > -75) & (sv[:, 2] > -12) & (sv[:, 2] < 100)]
    d, j = cKDTree(sv).query(mv)
    k = int(np.argmin(d))
    print("jaw against that skull's surface (point to point): least %.2f mm at jaw %s, skull %s" % (d[k], np.round(mv[k], 1).tolist(), np.round(sv[j[k]], 1).tolist()))
    for nm, sel in (("joint head", (mv[:, 1] > -10) & (mv[:, 2] < 18)), ("coronoid", (mv[:, 1] > -22) & (mv[:, 2] > 28)), ("neck and hind border", (mv[:, 1] < -10) & (mv[:, 1] > -45) & (mv[:, 2] < 22))):
        if sel.any():
            kk = int(np.argmin(np.where(sel, d, 9e9))); print("   %-22s least %.2f mm at jaw %s" % (nm, d[kk], np.round(mv[kk], 1).tolist()))
    if "tv" in Z and "nt" in Z:
        ut = Z["tv"][:int(Z["nt"])]; d2, _ = cKDTree(ut).query(tv); print("   lower teeth against the upper teeth: least %.2f mm" % d2.min())
np.savez(S + "/sb/%s.npz" % out, mv=mv, mf=mf, tv=tv, tf=tf, nt=0)
print("saved", out, "in %.0f s" % (time.time() - t0))
