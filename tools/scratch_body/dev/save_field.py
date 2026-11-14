"""save_field.py h name: build the whole skull's field and keep it (with the lines the bones are split along), so the
splitting can be worked on without building the skull again each time."""
import os
import sys, time, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, skull2, nose
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
h = float(sys.argv[1]); out = sys.argv[2]
t0 = time.time()
F, V = skull2.build(h)
D, lo = skull2.whole(F, rough="--smooth" not in sys.argv)
info = dict(h=h, lo=np.asarray(lo, float), sutures=skull2.build.sutures, midlines=skull2.whole.midlines, palate=skull2.build.palate,
            sockets=skull2.build.sockets,
            conchae=nose.conchae.solids, sidewall=nose.conchae.wall, septum=skull2.build.midsolids[0][0])
np.save(S + "/sb/%s_D.npy" % out, np.clip(D, -12, 12).astype(np.float16))
pickle.dump(info, open(S + "/sb/%s_info.pkl" % out, "wb"))
print("field", D.shape, "kept in %.0f s" % (time.time() - t0))
