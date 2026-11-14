import os
import sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, sdf, view, skull2
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")       # working folder: sb/ (fields, built heads), look/ (pictures), gray1918/ (the plates)
h = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
out = sys.argv[2] if len(sys.argv) > 2 else "skull2"
t0 = time.time()
box = None
if "--box" in sys.argv:
    q = [float(a) for a in sys.argv[sys.argv.index("--box") + 1].split(",")]; box = (q[:3], q[3:])
F, V = skull2.build(h, box=box)
T = skull2.build.parts["T"]
D, lo = skull2.whole(F, rough="--smooth" not in sys.argv)
v, f = sdf.mesh(D, lo, h); parts = sdf.components(v, f); v, f = parts[0]; v = sdf.taubin(v, f, 6)
print("mesh", len(f), "pieces", [len(q[1]) for q in parts][:6], "in %.0f s" % (time.time() - t0))
for q in parts[1:4]:
    if len(q[1]) > 300:
        print("  loose piece of %d faces from %s to %s" % (len(q[1]), np.round(q[0].min(0), 1).tolist(), np.round(q[0].max(0), 1).tolist()))
np.savez(S + "/sb/%s.npz" % out, v=v, f=f)
meshes = [(v, f, view.BONE)]
if "--teeth" in sys.argv:
    import teeth
    for name, side, w, g in teeth.stand(skull2.build.sockets, True):
        meshes.append((w, g, (240, 236, 222)))
    print("teeth", len(meshes) - 1, "in %.0f s" % (time.time() - t0))
    nt = sum(len(m[0]) for m in meshes[1:])          # vertices of the upper teeth
    du = sdf.sample_field(D, lo, h, np.concatenate([m[0] for m in meshes[1:]]))
    print("upper teeth against the skull's bone: least clearance %.2f mm (negative = a tooth inside bone), %d points inside" % (du.min(), int((du < 0).sum())))
    c1 = [w for name, side, w, g in teeth.stand(skull2.build.sockets, True) if "central" in name and side == "L"]
    if c1:
        print("upper central incisor: nearest the midline x = %.2f mm" % c1[0][:, 0].min())
    extra = {}
    if "--jaw" in sys.argv:
        import mandible4
        FM, info = mandible4.build(h)
        Dm, lom = mandible4.whole(FM, info, rough="--smooth" not in sys.argv)
        mv, mf = sdf.mesh(Dm, lom, h); mp = sdf.components(mv, mf); mv, mf = mp[0]; mv = sdf.taubin(mv, mf, 6)
        print("jaw", len(mf), "pieces", [len(q[1]) for q in mp][:5], "in %.0f s" % (time.time() - t0))
        lower = []
        for name, side, w, g in teeth.stand(info["sockets"], False):
            meshes.append((w, g, (240, 236, 222))); lower.append(w)
        dl = sdf.sample_field(Dm, lom, h, np.concatenate(lower))
        print("lower teeth against the jaw's bone: least clearance %.2f mm, %d points inside" % (dl.min(), int((dl < 0).sum())))
        ds = sdf.sample_field(D, lo, h, mv)
        print("lower jaw against the skull: least clearance %.2f mm at %s" % (ds.min(), np.round(mv[int(np.argmin(ds))], 1).tolist()))
        extra = dict(mv=mv, mf=mf)
    tv = np.concatenate([m[0] for m in meshes[1:]]); n0 = np.cumsum([0] + [len(m[0]) for m in meshes[1:-1]])
    tf = np.concatenate([m[1] + k for m, k in zip(meshes[1:], n0)])
    np.savez(S + "/sb/%s.npz" % out, v=v, f=f, tv=tv, tf=tf, nt=nt, **extra)
    if extra:
        meshes.append((mv, mf, view.BONE))
if box is not None:
    sys.exit(0)
size = 760; c3 = np.array([0, 12.0, 8.0]); span = 250.0
def proj(P, eye):
    e, r, u = view.camera(eye); s = size / span
    return np.column_stack([(P @ r - c3 @ r) * s + size / 2, size / 2 - (P @ u - c3 @ u) * s])
rows = [[], []]
for k, (name, eye) in enumerate((("left side", (1, 0, 0)), ("front", (0, 0, 1)), ("three-quarter", (0.6, 0.25, 0.75)), ("below", (0, -1, 0)), ("top", (0, 1, 0)), ("back", (0, 0, -1)))):
    im = view.picture(meshes, eye, size, frame=(c3, span)); d = ImageDraw.Draw(im)
    if "--lines" in sys.argv:
        if name == "left side":
            q = T.side; P = np.column_stack([np.zeros(len(q)), q[:, 1], q[:, 0]])
            d.line([tuple(p) for p in proj(P, eye)], fill=(255, 60, 60), width=1)
        if name == "front":
            q = T.front * np.where(T.front[:, 1:2] > 12.0, np.array([0.949, 1.0]), np.array([1.0, 1.0]))   # the vault brought to the usual breadth
            for sgn in (1, -1):
                d.point([tuple(p) for p in proj(np.column_stack([sgn * q[:, 0], q[:, 1], np.zeros(len(q))]), eye)], fill=(255, 60, 60))
    rows[k // 3].append((im, name))
view.sheet(rows, S + "/look/%s.png" % out, "cranium on traced plates, draft h = %.2f mm" % h)
im = Image.open(S + "/look/%s.png" % out); im.thumbnail((1500, 1500)); im.convert("RGB").save(S + "/look/%s.jpg" % out, quality=85)
