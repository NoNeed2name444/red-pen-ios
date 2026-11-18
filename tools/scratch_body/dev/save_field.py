"""save_field.py h name [--jaw]: build the whole skull's field (or the lower jaw's) and keep it (with the lines the bones are split along), so the
splitting can be worked on without building the skull again each time."""
import os
import sys, time, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, skull2, nose
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
h = float(sys.argv[1]); out = sys.argv[2]
t0 = time.time()
if "--jaw" in sys.argv:                                            # the lower jaw's field instead (for dev/try_structure.py)
    import mandible4
    FM, info = mandible4.build(h)
    D, lo = mandible4.whole(FM, info, rough="--smooth" not in sys.argv)
    np.save(S + "/sb/%s_D.npy" % out, np.clip(D, -12, 12).astype(np.float16))
    import structure
    canals = structure.jaw_canals(np.clip(D, -12, 12).astype(np.float32), np.asarray(lo, float), h, info["canal"], info["sockets"])   # the mandibular canal's course, found in the bone itself
    pickle.dump(dict(h=h, lo=np.asarray(lo, float), sockets=info["sockets"], canal=info["canal"], canals=canals), open(S + "/sb/%s_info.pkl" % out, "wb"))
    print("jaw's field", D.shape, "kept in %.0f s" % (time.time() - t0))
    sys.exit(0)
F, V = skull2.build(h)
D, lo = skull2.whole(F, rough="--smooth" not in sys.argv, sinuses="--nosinus" not in sys.argv)   # (--nosinus: the bones left solid, for dev/try_sinus.py)
info = dict(h=h, lo=np.asarray(lo, float), sutures=skull2.build.sutures, midlines=skull2.whole.midlines, palate=skull2.build.palate,
            sockets=skull2.build.sockets,
            conchae=nose.conchae.solids, sidewall=nose.conchae.wall, septum=skull2.build.midsolids[0][0])
np.save(S + "/sb/%s_D.npy" % out, np.clip(D, -12, 12).astype(np.float16))
pickle.dump(info, open(S + "/sb/%s_info.pkl" % out, "wb"))
print("field", D.shape, "kept in %.0f s" % (time.time() - t0))
