#!/usr/bin/env python3
"""The jaw shut: each body's mandible seated in its joints and its teeth brought together.

The atlas's skulls came with the mandible hanging: the man's condyles 9 to 11 mm under the temporal bones' fossae
and his teeth 13 mm apart, inside a skin whose mouth is shut (so the chin lay 18 to 22 mm behind the skin where
half of that is soft tissue). A student's atlas shows the jaw at rest on its joints with the teeth together.

What this does, per body, as one rigid move of the mandible with its teeth:
  1. up into its joints, as high as the condyles go with SPACE left between each and its temporal bone (the
     room the joint's disc takes), a little back or forward (4 mm at most) if they go higher there;
  2. turned about the line through the two condyles until the teeth first meet (TOUCH apart), nothing of the
     mandible in the rest of the skull.
The soft parts between the jaw and the rest follow by a field smooth through space: what lies on the mandible
moves with it, what lies on the skull, the neck's vertebrae or the hyoid stays, and what lies between moves by
its share of the two distances, so a thing between two bones that close on each other stays between them. The
lower gums and the lower lip's frenulum go with the jaw whole; the palate and the upper gums stay.

Muscles made by tools/anatomy_muscles_more.py are left alone here: that tool seats them on the bones as they
are, so they are made again after this (MORE_REDO).

  python3 tools/anatomy_jaw.py <atlas folder> [--only male|female] [--dry]

Marks each body it has done ("jaw shut": true in the manifest) and leaves a done one alone.
"""
import json, os, re, sys

import numpy as np
from scipy.spatial import cKDTree

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SPACE = 0.0025        # between a condyle and its fossa: the disc's room
TOUCH = 0.0003        # the teeth stop this far apart (the samples are 0.4 mm apart: nearer cannot be told)
CLEAR = 0.0010        # the mandible off the rest of the skull, outside its joints
HEAD = 0.014          # a condyle's head: the mandible within this of its top
NEAR, FAR = 0.008, 0.024   # the field: whole within NEAR of the jaw, none beyond FAR
SKIN = 0.0015         # the bone lies at least this far under the skin
RIGID = re.compile(r"^(gingiva_of_lower_jaw|frenulum_of_lower_lip)$")
STAYS = re.compile(r"^(gin[gv]iva_of_upper_jaw|frenulum_of_upper_lip|hard_palate|mucosa_of_soft_palate)$")
JAW = re.compile(r"^(mandible|set_of_lower_jaw_teeth)$")
FIXED_PARTS = ("vertebral-column", "hyoid")
LEFT_ALONE = ("skin", "brain", "spinal-cord", "optic-nerves", "eyes", "eye-muscles", "skull")


def log(*a):
    print(*a, flush=True)


def rodrigues(u, angle):
    K = np.array([[0, -u[2], u[1]], [u[2], 0, -u[0]], [-u[1], u[0], 0]])
    return np.eye(3) + np.sin(angle) * K + (1 - np.cos(angle)) * K @ K


def condyle(v, sign):
    """One side's condyle: its top, and which of the mandible's points are its head. The ramus ends above in two
    processes; the condyle is the back one."""
    mid = (v[:, 0].min() + v[:, 0].max()) / 2
    side = (v[:, 0] - mid) * sign > 0.02
    s = v[side]
    top = s[s[:, 1] > s[:, 1].max() - 0.025]
    back = top[top[:, 2] < top[:, 2].min() + 0.014]
    apex = back[back[:, 1] > back[:, 1].max() - 0.0015].mean(0)
    return apex, side & (np.linalg.norm(v - apex, axis=1) < HEAD)


def shut(nodes, say):
    """The jaw's rigid move (R, t): x -> x @ R.T + t; and what it measured."""
    from anatomy_muscles_more import short, outward_samples, Surface
    by = {short(n): (pid, st, v, f) for n, (pid, st, v, f) in nodes.items() if pid == "skull"}
    md, teeth, upper = by["mandible"], by["set_of_lower_jaw_teeth"], by["set_of_upper_jaw_teeth"]
    fixed = [(v, f) for k, (pid, st, v, f) in by.items() if not JAW.search(k)]
    box = (md[2].min(0) - 0.035, md[2].max(0) + 0.035)
    rest = Surface(meshes=fixed, h=0.0005, box=box)
    up = Surface(meshes=[upper[2:]], h=0.0004)
    out = {}
    apex, heads = {}, np.zeros(len(md[2]), bool)
    for s, sign in (("L", 1), ("R", -1)):
        apex[s], head = condyle(md[2], sign)
        heads |= head
    # 1 and 2. into the joint: as high as the condyles go, SPACE off the bone, trying a little back and forward
    head = md[2][heads]
    def room(ty, tz):
        ins, d, _ = rest.query(head + [0, ty, tz], 0.03)
        return -1.0 if ins.any() else float(d.min())
    out["joint before mm"] = round(room(0, 0) * 1000, 1)
    def lift(tz):
        if room(0, tz) <= SPACE:
            return 0.0
        ty = 0.0
        while ty < 0.03 and room(ty + 0.00025, tz) > SPACE:
            ty += 0.00025
        lo, hi = ty, ty + 0.00025
        for _ in range(8):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if room(mid, tz) > SPACE else (lo, mid)
        return lo
    tried = {tz: lift(tz) for tz in np.arange(-4, 4.5, 1.0) / 1000}
    best = max(tried.values())
    tz = min((z for z, y in tried.items() if y > best - 0.0003), key=abs)
    ty = tried[tz]
    t0 = np.array([0, ty, tz])
    # 3. turned until the teeth meet
    a0, a1 = apex["R"] + t0, apex["L"] + t0
    u = (a1 - a0) / np.linalg.norm(a1 - a0)
    mp, _ = outward_samples(md[2][:, :], md[3], 0.0008)
    mp = mp[np.minimum(np.linalg.norm(mp - apex["L"], axis=1), np.linalg.norm(mp - apex["R"], axis=1)) > HEAD + 0.004]
    tp, _ = outward_samples(*teeth[2:], 0.0004)
    def moved(x, angle):
        R = rodrigues(u, -angle)            # about +x, a negative turn lifts the chin
        return (x + t0 - a0) @ R.T + a0
    def gaps(angle):
        """How far the teeth are apart, and the mandible from the rest of the skull. By distance alone: the tooth
        rows are open shells, cut at the gums, with no inside to be in, and the steps are finer than the samples."""
        teeth_gap = float(np.minimum(up.tree.query(moved(tp, angle), distance_upper_bound=0.004, workers=2)[0], 0.004).min())
        bone_gap = float(np.minimum(rest.tree.query(moved(mp, angle), distance_upper_bound=0.004, workers=2)[0], 0.004).min())
        return teeth_gap, bone_gap
    def free(angle):
        g = gaps(angle)
        return g[0] >= TOUCH and g[1] >= CLEAR
    angle = np.radians(-6.0)
    if not free(angle):
        raise SystemExit("the jaw is not free of the skull even 6 degrees more open: not moved")
    step = np.radians(0.1)
    while angle < np.radians(25) and free(angle + step):
        angle += step
    lo, hi = angle, angle + step
    for _ in range(12):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if free(mid) else (lo, mid)
    angle = lo
    out["stopped by"] = "the teeth" if gaps(hi)[0] < TOUCH else "the mandible against the skull"
    R = rodrigues(u, -angle)
    t = a0 - (a0 - t0) @ R.T
    g = gaps(angle)
    # the bite, read at the front teeth
    lt, ut = teeth[2] @ R.T + t, upper[2]
    lf, uf = lt[lt[:, 2] > np.quantile(lt[:, 2], 0.9)], ut[ut[:, 2] > np.quantile(ut[:, 2], 0.9)]
    out.update({"forward mm": round(tz * 1000, 1), "up mm": round(ty * 1000, 1), "turned deg": round(float(np.degrees(angle)), 2),
                "teeth apart mm": round(g[0] * 1000, 2), "mandible off skull mm": round(g[1] * 1000, 1),
                "overbite mm": round(float(lf[:, 1].max() - uf[:, 1].min()) * 1000, 1),
                "overjet mm": round(float(uf[:, 2].max() - lf[:, 2].max()) * 1000, 1),
                "chin moved mm": [round(float(x) * 1000, 1) for x in
                                  ((md[2][md[2][:, 1].argmin()] @ R.T + t) - md[2][md[2][:, 1].argmin()])]})
    say("    " + ", ".join(f"{k} {v}" for k, v in out.items()))
    return R, t, out


def follow(nodes, R, t, say):
    """Every other node's moved positions: {node: positions} for those that move at all."""
    from anatomy_muscles_more import short, samples, MARK
    jaw = np.concatenate([samples(v, f, 0.001)[0] for n, (pid, st, v, f) in nodes.items()
                          if (pid == "skull" and JAW.search(short(n))) or RIGID.search(short(n))])
    still = np.concatenate([samples(v, f, 0.0015)[0] for n, (pid, st, v, f) in nodes.items()
                            if (pid == "skull" and not JAW.search(short(n))) or STAYS.search(short(n))
                            or (pid in FIXED_PARTS and st.get("tissue") in ("bone", "cartilage"))])
    lo, hi = jaw.min(0) - FAR, jaw.max(0) + FAR
    still = still[np.all((still > lo - 0.05) & (still < hi + 0.05), axis=1)]
    tj, ts = cKDTree(jaw), cKDTree(still)
    out, table = {}, []
    for n, (pid, st, v, f) in nodes.items():
        name = short(n)
        if pid in LEFT_ALONE or pid in FIXED_PARTS or st.get("made") == MARK or STAYS.search(name):
            continue
        box = np.all((v > lo) & (v < hi), axis=1)
        if not box.any():
            continue
        if RIGID.search(name):
            out[n] = v @ R.T + t
            table.append((pid, name, 1.0, float(np.linalg.norm(out[n] - v, axis=1).max())))
            continue
        dm = tj.query(v, workers=2)[0]
        if dm.min() > FAR:
            continue
        df = ts.query(v, workers=2)[0]
        a, b = np.maximum(dm - 0.0015, 0), np.maximum(df - 0.0015, 0)
        w = np.where(a + b > 0, b / np.maximum(a + b, 1e-9), 0.5)
        x = np.clip((FAR - dm) / (FAR - NEAR), 0, 1)
        w = w * x * x * (3 - 2 * x)
        if w.max() < 0.02:
            continue
        out[n] = v + w[:, None] * (v @ R.T + t - v)
        table.append((pid, name, float((w > 0.02).mean()), float(np.linalg.norm(out[n] - v, axis=1).max())))
    for pid, name, share, most in sorted(table):
        say(f"      {pid:16s} {name:44s} {share:4.0%} of it moves, at most {most * 1000:4.1f} mm")
    return out


def run(folder, only=None, dry=False, quiet=False):
    from anatomy_fibres import read_part, write_part, sha256
    from anatomy_muscles_more import body_nodes, short, Surface, samples, inside_share, unpoke
    say = (lambda *a: None) if quiet else log
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    notes = []
    for body in manifest["bodies"]:
        if only and body["id"] != only:
            continue
        if body.get("jaw shut"):
            notes.append(f"{body['id']}: shut already")
            continue
        say(f"  {body['id']}")
        nodes = body_nodes(folder, body)
        R, t, got = shut(nodes, say)
        new = {n: v @ R.T + t for n, (pid, st, v, f) in nodes.items() if pid == "skull" and JAW.search(short(n))}
        soft = follow(nodes, R, t, say)
        # nothing newly in the bones
        jawv = np.concatenate(list(new.values()))
        box = (jawv.min(0) - 0.04, jawv.max(0) + 0.04)
        hard = [n for n, (pid, st, v, f) in nodes.items()
                if pid == "skull" or (pid in FIXED_PARTS and st.get("tissue") == "bone")]
        bones_was = Surface(meshes=[nodes[n][2:] for n in hard], h=0.0006, box=box)
        bones_now = Surface(meshes=[(new.get(n, nodes[n][2]), nodes[n][3]) for n in hard], h=0.0006, box=box)
        for n in sorted(soft):
            pid, st, v, f = nodes[n]
            if RIGID.search(short(n)):       # moved with the jaw whole: it lies on it as it did
                continue
            was, now = inside_share(v, f, bones_was), inside_share(soft[n], f, bones_now)
            if now > was + 0.003:
                fixed, _ = unpoke(soft[n], f, bones_now, 0.0004, rounds=10, sigma=0.003, cap=0.002)
                after = inside_share(fixed, f, bones_now)
                say(f"      {short(n)}: {was:.1%} of it in bone before, {now:.1%} after the move, {after:.1%} eased out")
                if after < now:
                    soft[n] = fixed
        # under the skin still
        skin = [(v, f) for n, (pid, st, v, f) in nodes.items() if pid == "skin"]
        if skin:
            sp = np.concatenate([samples(v, f, 0.002)[0] for v, f in skin])
            jawp = np.concatenate(list(new.values()))
            sp = sp[np.all((sp > jawp.min(0) - 0.05) & (sp < jawp.max(0) + 0.05), axis=1)]
            d = cKDTree(sp).query(jawp)[0]
            got["under the skin mm"] = round(float(d.min()) * 1000, 1)
            say(f"    the mandible's nearest point to the skin: {d.min() * 1000:.1f} mm under it")
            if d.min() < SKIN:
                raise SystemExit(f"{body['id']}: the shut jaw would come within {d.min() * 1000:.1f} mm of the skin: not moved")
        notes.append(f"{body['id']}: " + ", ".join(f"{k} {v}" for k, v in got.items()) + f"; {len(soft)} soft structures follow")
        if dry:
            continue
        new.update(soft)
        for part in body["parts"]:
            if not any(st["node"] in new for st in part["structures"]):
                continue
            file = os.path.join(folder, part["file"])
            meshes = [(new.get(st["node"], v), f) for st, (v, f) in zip(part["structures"], read_part(file))]
            lo, hi = write_part(file, meshes)
            part["bytes"] = os.path.getsize(file)
            part["sha256"] = sha256(file)
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
        body["jaw shut"] = True
    if not dry:
        with open(path, "w") as out:
            json.dump(manifest, out, indent=1, ensure_ascii=False)
    return notes


if __name__ == "__main__":
    argv = sys.argv[1:]
    only = None
    if "--only" in argv:
        k = argv.index("--only")
        only = argv[k + 1]
        del argv[k:k + 2]
    dry = "--dry" in argv
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    for line in run(args[0], only=only, dry=dry):
        log(line)
