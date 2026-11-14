"""block.py field name x0,y0,z0,x1,y1,z1: mesh one block of a kept field (dev/save_field.py) so that a region can be looked at
(dev/close.py name set) a minute after a change, without meshing the whole head, its teeth and its jaw."""
import os, sys, pickle
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
field, name = sys.argv[1], sys.argv[2]; q = [float(a) for a in sys.argv[3].split(",")]
D = np.load(S + "/sb/%s_D.npy" % field).astype(np.float32); info = pickle.load(open(S + "/sb/%s_info.pkl" % field, "rb")); lo, h = info["lo"], info["h"]
a = np.maximum(np.floor((np.array(q[:3]) - lo) / h).astype(int), 0); b = np.minimum(np.ceil((np.array(q[3:]) - lo) / h).astype(int) + 1, D.shape)
v, f = sdf.mesh(D[a[0]:b[0], a[1]:b[1], a[2]:b[2]], lo + a * h, h); v = sdf.taubin(v, f, 6)
np.savez(S + "/sb/%s.npz" % name, v=v, f=f); print(name, len(f), "faces")
