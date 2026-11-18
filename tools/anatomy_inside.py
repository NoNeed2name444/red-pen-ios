#!/usr/bin/env python3
"""What each of the atlas's bones is made of inside: compact bone, cancellous (spongy) bone, the marrow canal.

The owner's order of 14 November: "make bones compact - cancellous - spongy in each place each one should be and in each
part of each bone. some bones also combine multiple types."

The rules are Gray's (1918, public domain), bone by bone and part by part; they are written down, with his words and
pages, in tools/scratch_body/structure.py (its TABLE, PLANS and `Bone`) and listed in tools/scratch_body/STRUCTURE.md.
This tool applies them to a bone of the app's atlas (ios/RedPen/Resources/Anatomy): the bone's surface is read from its
part, turned into its own frame (its length along the third axis, its upper end at the greater values) and made into a
field (below 0 in bone) every `--h` mm; the field is kept, with the rule it follows, where the drawing tools look for it:

    python3 -I tools/anatomy_inside.py --body male --bone "left femur" --name femur [--h 0.5] [--out DIR]
    SCRATCH_OUT=DIR python3 tools/scratch_body/dev/try_structure.py femur --auto      (flat sections, coloured by kind)

Several bones that are one in the adult are given together, joined by "+" ("left ilium+left ischium+left pubis": the
hip bone). Nothing is written into the app: its parts are surfaces, and what a bone is made of only shows when it is
cut. Nothing is imported here but the atlas's own bones; no source is added.
"""
import argparse, json, os, pickle, struct, sys
import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "scratch_body"))
import structure

ATLAS = os.path.join(os.path.dirname(HERE), "ios", "RedPen", "Resources", "Anatomy")


def read_part(path):
    """A part's meshes (positions in metres, triangles) from its .atlas file (the format: tools/anatomy_atlas.py)."""
    b = open(path, "rb").read()
    if b[:4] != b"SAT1":
        raise ValueError("%s: not an atlas part" % path)
    n, = struct.unpack_from("<I", b, 4)
    lo = np.array(struct.unpack_from("<3f", b, 8), np.float64); hi = np.array(struct.unpack_from("<3f", b, 20), np.float64)
    at = 32; scale = (hi - lo) / 65535; out = []
    for _ in range(n):
        v, t = struct.unpack_from("<II", b, at); at += 8
        q = np.frombuffer(b, "<u2", v * 3, at).reshape(-1, 3); at += v * 6
        wide = v > 65535
        f = np.frombuffer(b, "<u4" if wide else "<u2", t * 3, at).reshape(-1, 3).astype(np.int64)
        at += t * 3 * (4 if wide else 2); at += (4 - at % 4) % 4
        out.append((lo + q.astype(np.float64) * scale, f))
    return out


def bones(body, labels):
    """The meshes (mm) of the named structures of one body."""
    man = json.load(open(os.path.join(ATLAS, "anatomy.json")))
    b = [x for x in man["bodies"] if x["id"] == body][0]
    got = {}
    for part in b["parts"]:
        want = [i for i, s in enumerate(part["structures"]) if s["label"] in labels]
        if want:
            ms = read_part(os.path.join(ATLAS, "%s-%s.atlas" % (body, part["id"])))
            for i in want:
                got[part["structures"][i]["label"]] = (ms[i][0] * 1000.0, ms[i][1])
    missing = [l for l in labels if l not in got]
    if missing:
        raise SystemExit("not in the %s atlas: %s" % (body, ", ".join(missing)))
    return [got[l] for l in labels]


def frame(P):
    """The bone's own axes: the third along its length (pointing up in the body), the first across its thinnest way."""
    c = P.mean(axis=0)
    w, V = np.linalg.eigh(np.cov((P - c).T))                    # ascending
    R = V.T.copy()
    if R[2, 1] < 0:
        R[2] = -R[2]
    if np.linalg.det(R) < 0:
        R[0] = -R[0]
    return c, R


def solid(P, F, lo, shape, h):
    """The voxels inside a surface. Along each of the three axes a line is run through every column of voxels and the
    faces it crosses are counted, those it goes in by against those it comes out by; a voxel is inside when two of the
    three counts say so. (So a surface in several closed pieces that overlap, or one with a seam left open, as the
    atlas's femur has at its lower end, still fills as the one solid it is.)"""
    T = P[F]; votes = np.zeros(shape, np.int8)
    for ax in range(3):
        u, v = [k for k in range(3) if k != ax]
        A = (T[:, :, [u, v]] - lo[[u, v]]) / h + np.array([0.31831e-3, 0.27183e-3])       # (no column runs exactly through an edge)
        Zd = (T[:, :, ax] - lo[ax]) / h
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])[:, ax]
        cnt = np.zeros(shape, np.int8)
        for t in np.nonzero(np.abs(n) > 1e-12)[0]:
            (x0, y0), (x1, y1), (x2, y2) = A[t]
            i0, i1 = int(np.ceil(min(x0, x1, x2))), int(np.floor(max(x0, x1, x2)))
            j0, j1 = int(np.ceil(min(y0, y1, y2))), int(np.floor(max(y0, y1, y2)))
            if i1 < i0 or j1 < j0:
                continue
            I, J = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1), indexing="ij")
            den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            w0 = ((y1 - y2) * (I - x2) + (x2 - x1) * (J - y2)) / den
            w1 = ((y2 - y0) * (I - x2) + (x0 - x2) * (J - y2)) / den
            w2 = 1.0 - w0 - w1
            ok = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not ok.any():
                continue
            k = np.clip(np.ceil(w0[ok] * Zd[t, 0] + w1[ok] * Zd[t, 1] + w2[ok] * Zd[t, 2]).astype(int), 0, shape[ax] - 1)
            idx = [None, None, None]; idx[u], idx[v], idx[ax] = I[ok], J[ok], k
            np.add.at(cnt, tuple(idx), -1 if n[t] > 0 else 1)
        votes += (np.cumsum(cnt, axis=ax, dtype=np.int16) != 0)
    return votes >= 2


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--body", default="male")
    ap.add_argument("--bone", required=True, help='a structure\'s label in the atlas; several joined by "+" are made one bone')
    ap.add_argument("--name", required=True, help="the name the field is kept under")
    ap.add_argument("--h", type=float, default=0.5)
    ap.add_argument("--out", default=os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out"))
    a = ap.parse_args()
    labels = a.bone.split("+")
    plan = structure.plan_for(labels[0])
    if plan is None:
        raise SystemExit("no rule for %r in structure.PLANS" % labels[0])
    meshes = bones(a.body, labels)
    c, R = frame(np.concatenate([p for p, f in meshes]))
    pts = [(p - c) @ R.T for p, f in meshes]
    allp = np.concatenate(pts); pad = 6.0
    lo = allp.min(axis=0) - pad; shape = tuple(int(v) for v in np.ceil((allp.max(axis=0) + pad - lo) / a.h).astype(int) + 1)
    full = np.zeros(shape, bool)
    for p, (_, f) in zip(pts, meshes):
        full |= solid(p, f, lo, shape, a.h)
    full = ndimage.binary_closing(full, iterations=int(round((1.0 if len(meshes) > 1 else 0.5) / a.h)))     # seams shut; the pieces of one bone grown together where they meet
    full = ndimage.binary_fill_holes(full)                       # (some of the atlas's bones are shells with an inner surface: a bone is solid until its rule hollows it)
    D = np.where(full, 0.5 - ndimage.distance_transform_edt(full), ndimage.distance_transform_edt(~full) - 0.5) * a.h
    D = ndimage.gaussian_filter(D.astype(np.float32), 1.0)
    os.makedirs(os.path.join(a.out, "sb"), exist_ok=True)
    np.save(os.path.join(a.out, "sb", "%s_D.npy" % a.name), np.clip(D, -12, 12).astype(np.float16))
    info = dict(h=a.h, lo=lo, bone=plan, label=" + ".join(labels), body=a.body, centre=c, axes=R, up=R @ np.array([0.0, 1.0, 0.0]))
    pickle.dump(info, open(os.path.join(a.out, "sb", "%s_info.pkl" % a.name), "wb"))
    size = (allp.max(axis=0) - allp.min(axis=0))
    print("%s (%s): %s, %.0f by %.0f by %.0f mm in its own frame, %.1f cm3; rule: %s" % (info["label"], a.body, "x".join(str(v) for v in shape), size[0], size[1], size[2], full.sum() * a.h ** 3 / 1000.0, plan))


if __name__ == "__main__":
    main()
