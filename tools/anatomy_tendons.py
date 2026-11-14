#!/usr/bin/env python3
"""The long tendons of the lower limb: where a muscle's flesh ends far from the bone it inserts on, the tendon
that carries it there, each a structure of its own (tissue "ligament", as the atlas's quadriceps tendon is), so
a student can tap it and read its name, and every muscle is seen to reach its insertion.

    remake(folder, quiet=False)      adds them to <folder>'s atlas
    anatomy_tendons.py <atlas folder>

Run after tools/anatomy_muscles_body.py (it reads the muscles that tool made) and before the fibres. Each tendon
made carries "made": MARK, so a second run makes only what is missing.

No scan gives these: the muscle labels hold the flesh and the CT cannot tell a tendon from what lies beside it at
this size. Each is drawn from the textbook's account of its course and insertion (Gray, Anatomy of the Human
Body, 20th ed., 1918, public domain; this file's own words, TENDONS) on the body's own muscles and bones:

1. It starts inside the end of its muscle (or muscles: the tendo calcaneus gathers three), START from the tip,
   as wide and thick there as the muscle is, so the flesh is seen to run into it.
2. It runs along a smooth curve (a spline) through the points its course is known by on the body's own bones:
   behind a malleolus, under the sustentaculum, over the front of the ankle; from there to its insertion.
3. Its section narrows from the muscle's to the cord's own (SIZE: width and thickness from the table) and widens
   a little where it meets its bone, on which its last ring is laid.
4. Out of every bone and of the muscles and tendons it runs beside (not of its own muscle's end), smoothed.

The right side is the left's course found the same way on the right's bones (each side's bones are their own).
"""
import json, os, re, sys

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "tendons-1"
START = 0.012          # a tendon starts this far inside its muscle's end
RING = 12              # vertices round a tendon
STEP = 0.003           # between its rings
BLEND = 0.03           # the length over which the muscle's section becomes the cord's
FLARE = 0.012          # the length over which the cord widens to its insertion
OFF = 0.0004           # off the bone it lies on


def log(*a):
    print(*a, flush=True)


# MARK: curves and tubes

def spline(points, step=STEP):
    """A smooth curve through the points (centripetal Catmull-Rom), sampled about `step` apart."""
    P = np.asarray(points, float)
    if len(P) == 2:
        n = max(2, int(np.ceil(np.linalg.norm(P[1] - P[0]) / step)) + 1)
        return P[0] + (P[1] - P[0]) * np.linspace(0, 1, n)[:, None]
    Q = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(Q) - 2):
        p0, p1, p2, p3 = Q[i - 1], Q[i], Q[i + 1], Q[i + 2]
        t0 = 0.0
        t1 = t0 + np.linalg.norm(p1 - p0) ** 0.5
        t2 = t1 + np.linalg.norm(p2 - p1) ** 0.5
        t3 = t2 + np.linalg.norm(p3 - p2) ** 0.5
        n = max(2, int(np.ceil(np.linalg.norm(p2 - p1) / step)) + 1)
        t = np.linspace(t1, t2, n)[:, None]
        a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
        a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
        a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
        b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
        b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
        c = (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
        out.append(c if i == 1 else c[1:])
    C = np.concatenate(out)
    # evenly spaced along its length
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    n = max(2, int(np.ceil(d[-1] / step)) + 1)
    s = np.linspace(0, d[-1], n)
    return np.stack([np.interp(s, d, C[:, k]) for k in range(3)], 1)


def frames(C, wide):
    """Along the curve C: its tangent, and the direction the tendon is wide in, carried along without twist
    (parallel transport) from `wide` at its start."""
    T = np.gradient(C, axis=0)
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
    W = np.zeros_like(C)
    w = wide - T[0] * (wide @ T[0])
    W[0] = w / np.linalg.norm(w)
    for i in range(1, len(C)):
        w = W[i - 1] - T[i] * (W[i - 1] @ T[i])
        W[i] = w / max(np.linalg.norm(w), 1e-12)
    return T, W


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def tube(C, wide, section0, cord, foot, turn_to=None):
    """A closed tube along C: its section an ellipse, half-axes section0 (wide, thick) at the start, the cord's
    over BLEND, the foot's over the last FLARE. turn_to: the direction it is wide in at its end, if it turns.
    Returns positions, triangles (outward) and the rings' count."""
    T, W = frames(C, wide)
    n = len(C)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    if turn_to is not None:                       # turned evenly along it to end wide along turn_to
        w1 = turn_to - T[-1] * (turn_to @ T[-1])
        w1 /= max(np.linalg.norm(w1), 1e-12)
        if w1 @ W[-1] < 0:
            w1 = -w1
        angle = np.arctan2(np.cross(W[-1], w1) @ T[-1], W[-1] @ w1)
        for i in range(n):
            a = angle * s[i] / s[-1]
            W[i] = W[i] * np.cos(a) + np.cross(T[i], W[i]) * np.sin(a)
    B = np.cross(T, W)
    a0, b0 = section0
    a = a0 + (cord[0] - a0) * smoothstep(s / BLEND)
    b = b0 + (cord[1] - b0) * smoothstep(s / BLEND)
    k = smoothstep((s - (s[-1] - FLARE)) / FLARE)
    a, b = a + (foot[0] - a) * k, b + (foot[1] - b) * k
    th = np.linspace(0, 2 * np.pi, RING, endpoint=False)
    V = (C[:, None, :] + a[:, None, None] * np.cos(th)[None, :, None] * W[:, None, :]
         + b[:, None, None] * np.sin(th)[None, :, None] * B[:, None, :]).reshape(-1, 3)
    F = []
    for i in range(n - 1):
        for j in range(RING):
            p, q = i * RING + j, i * RING + (j + 1) % RING
            F += [(p, q, p + RING), (q, q + RING, p + RING)]
    c0, c1 = len(V), len(V) + 1                  # the two caps
    V = np.vstack([V, C[0] - T[0] * min(a0, b0) * 0.5, C[-1]])
    for j in range(RING):
        F.append((c0, (j + 1) % RING, j))
        F.append((c1, (n - 1) * RING + j, (n - 1) * RING + (j + 1) % RING))
    return V, np.asarray(F, np.int64), n


# MARK: the muscle's end

def end_of(v, toward, back=START):
    """Where a tendon leaves a muscle bound for `toward`: the middle of the muscle's slice `back` from its tip
    that way, the direction that slice is widest in, and its half-width and half-thickness."""
    d = toward - v.mean(0)
    d /= np.linalg.norm(d)
    h = v @ d
    tip = h.max()
    slab = v[(h > tip - back - 0.006) & (h < tip - back + 0.006)]
    if len(slab) < 8:
        slab = v[h > tip - back - 0.012]
    c = slab.mean(0)
    x = slab - c
    x = x - np.outer(x @ d, d)
    w, U = np.linalg.eigh(x.T @ x)
    wide, thick = U[:, 2], U[:, 1]
    return c, d, wide, float(np.abs(x @ wide).max()), float(np.abs(x @ thick).max())


def ends_of(muscles, toward):
    """end_of for one muscle or several that share a tendon: the slices taken from each at its own tip."""
    slabs, d = [], None
    for v in muscles:
        c, d1, wide, a, b = end_of(v, toward)
        h = v @ d1
        slabs.append(v[(h > h.max() - START - 0.006) & (h < h.max() - START + 0.006)])
        d = d1 if d is None else d + d1
    d /= np.linalg.norm(d)
    slab = np.concatenate(slabs)
    c = slab.mean(0)
    x = slab - c
    x = x - np.outer(x @ d, d)
    w, U = np.linalg.eigh(x.T @ x)
    wide, thick = U[:, 2], U[:, 1]
    return c, d, wide, float(np.quantile(np.abs(x @ wide), 0.95)), float(np.quantile(np.abs(x @ thick), 0.95))


# MARK: where things are on a leg's bones

TOES = ("great", "second", "third", "fourth", "little")
RAYS = ("first", "second", "third", "fourth", "fifth")


def far(v, d, band=0.003):
    """The middle of what lies farthest along d (within band of the farthest)."""
    h = v @ (np.asarray(d, float) / np.linalg.norm(d))
    return v[h > h.max() - band].mean(0)


def landmarks(B, sg):
    """Named points on one leg's bones. B: {bone: positions}, names without prefix or side; sg: +1 the left's
    (its lateral side is +x), -1 the right's. Directions: up; fwd, the foot's length, level; lat, to the leg's
    outer side."""
    up = np.array([0.0, 1.0, 0.0])
    fwd = B["second_metatarsal"].mean(0) - B["calcaneus"].mean(0)
    fwd[1] = 0
    fwd /= np.linalg.norm(fwd)
    lat = sg * np.cross(up, fwd)
    L = {"up": up, "fwd": fwd, "lat": lat}
    def band(v, lo, hi, axis=up, from_top=True):
        h = v @ axis
        ref = h.max() if from_top else h.min()
        return v[(h < ref - lo) & (h > ref - hi)] if from_top else v[(h > ref + lo) & (h < ref + hi)]
    tib, fib, fem, cal = B["tibia"], B["fibula"], B["femur"], B["calcaneus"]
    # the knee
    L["fibular head"] = far(fib, up + 0.4 * lat, 0.004)
    L["gerdy"] = far(band(tib, 0.012, 0.03), lat + 0.8 * fwd, 0.004)
    L["semimembranosus"] = far(band(tib, 0.008, 0.025), -lat - fwd, 0.004)
    pes = far(band(tib, 0.045, 0.075), -lat + 0.4 * fwd, 0.004)
    L["pes sartorius"] = pes + 0.010 * up + 0.004 * fwd
    L["pes gracilis"] = pes
    L["pes semitendinosus"] = pes - 0.012 * up - 0.004 * fwd
    L["behind medial condyle"] = far(band(fem, 0.0, 0.035, from_top=False), -lat - 0.8 * fwd, 0.004) - 0.006 * lat - 0.006 * fwd
    L["adductor tubercle"] = far(band(fem, 0.035, 0.06, from_top=False), -lat, 0.004)
    L["lateral epicondyle"] = far(band(fem, 0.0, 0.04, from_top=False), lat, 0.004)
    # the ankle
    mm, lm = far(tib, -up, 0.003), far(fib, -up, 0.003)
    L["medial malleolus"], L["lateral malleolus"] = mm, lm
    L["behind medial malleolus"] = mm - 0.010 * fwd + 0.010 * up
    L["behind lateral malleolus"] = lm - 0.009 * fwd + 0.010 * up
    low = band(tib, 0.012, 0.03, from_top=False)       # the front of the tibia over the middle of the talus
    L["front of ankle"] = far(low[np.abs((low - B["talus"].mean(0)) @ lat) < 0.008], fwd, 0.003)
    L["heel"] = (lambda b: b[np.abs(b[:, 1] - (b[:, 1].min() + b[:, 1].max()) / 2) < 0.3 * np.ptp(b[:, 1])].mean(0))(
        cal[(cal @ fwd) < (cal @ fwd).min() + 0.006])
    h = cal @ fwd                                       # the shelf on the inner side of the calcaneus's front half
    shelf = cal[(h > h.min() + 0.45 * np.ptp(h)) & (cal[:, 1] > cal[:, 1].min() + 0.4 * np.ptp(cal[:, 1]))]
    L["sustentaculum"] = far(shelf, -lat, 0.004) - 0.008 * up
    cun = np.concatenate([B["intermediate_cuneiform"], B["lateral_cuneiform"]])
    L["sole"] = np.array([0, cun[:, 1].min() - 0.008, 0]) + (cun.mean(0) * [1, 0, 1])
    L["peroneal trochlea"] = far(cal[(h > h.min() + np.ptp(h) / 3) & (h < h.max() - np.ptp(h) / 3)], lat - 0.3 * up, 0.003)
    L["back of talus"] = far(B["talus"], -fwd, 0.003) - 0.005 * lat
    # the foot
    L["navicular tuberosity"] = far(B["navicular"], -lat - 0.7 * up, 0.003)
    L["medial cuneiform"] = far(B["medial_cuneiform"], -lat - 0.9 * up, 0.003)
    L["top of navicular"] = far(B["navicular"], up, 0.003)
    L["cuboid groove"] = far(B["cuboid"], lat - up, 0.003)
    m1 = B["first_metatarsal"]
    L["first metatarsal base, under"] = far(m1[(m1 @ fwd) < (m1 @ fwd).min() + 0.012], -up + 0.4 * lat, 0.003)
    for toe, ray in zip(TOES, RAYS):
        mt, dp = B[f"{ray}_metatarsal"], B[f"distal_phalanx_of_{toe}_toe"]
        pp = B[f"proximal_phalanx_of_{toe}_toe"]
        head = mt[(mt @ fwd) > (mt @ fwd).max() - 0.008]
        base = dp[(dp @ fwd) < (dp @ fwd).min() + 0.004]
        knuckle = pp[(pp @ fwd) > (pp @ fwd).max() - 0.005]
        L[f"{toe} toe: over the metatarsal's head"], L[f"{toe} toe: under the metatarsal's head"] = far(head, up), far(head, -up)
        L[f"{toe} toe: over the knuckle"], L[f"{toe} toe: under the knuckle"] = far(knuckle, up), far(knuckle, -up)
        L[f"{toe} toe: last phalanx, above"], L[f"{toe} toe: last phalanx, below"] = far(base, up, 0.002), far(base, -up, 0.002)
        L[f"{ray} metatarsal: over its base"] = far(mt[(mt @ fwd) < (mt @ fwd).min() + 0.01], up)
    return L


# MARK: the tendons

MM = 0.001
# (node, label, part, group, the muscles it leaves (tools/anatomy_muscles_body.py's nodes), the bone it ends on,
#  its slips: (the points its course passes, by landmarks()' names; where it ends; the cord's half-width and
#  half-thickness, mm; the same at its insertion), what it lies on and is kept out of, its course in words)
TENDONS = [
    ("tendo_calcaneus", "tendo calcaneus (Achilles tendon)", "leg-muscles", "Tendons of the leg",
     ["gastrocnemius_medial_head", "gastrocnemius_lateral_head"], "calcaneus",
     [([], "heel", (7.5, 3.0), (11, 3.0))], ["soleus"],
     "the common tendon of the gastrocnemius and soleus, the thickest in the body: it begins near the middle of "
     "the leg, narrows, and is inserted into the middle of the back of the calcaneus"),
    ("tendon_of_tibialis_anterior", "tendon of tibialis anterior", "leg-muscles", "Tendons of the leg",
     ["tibialis_anterior"], "medial_cuneiform",
     [(["front of ankle: inner"], "medial cuneiform", (3.5, 2.0), (4.5, 1.8))], [],
     "over the front of the ankle, the innermost tendon there, to the medial and under surface of the first "
     "cuneiform and the base of the first metatarsal"),
    ("tendons_of_extensor_digitorum_and_hallucis_longus", "tendons of extensor digitorum longus and extensor "
     "hallucis longus", "leg-muscles", "Tendons of the leg", ["extensor_digitorum_and_hallucis_longus"], "phalanx",
     [(["front of ankle", "first metatarsal: over its base", "great toe: over the metatarsal's head",
        "great toe: over the knuckle"], "great toe: last phalanx, above", (2.2, 1.3), (2.6, 1.0))]
     + [(["front of ankle: outer", f"{ray} metatarsal: over its base", f"{toe} toe: over the metatarsal's head",
          f"{toe} toe: over the knuckle"], f"{toe} toe: last phalanx, above", (1.6, 1.0), (1.8, 0.8))
        for toe, ray in zip(TOES[1:], RAYS[1:])], [],
     "over the front of the ankle and the back of the foot: the long extensor of the great toe to the base of "
     "its last phalanx, the long extensor of the toes dividing into four, one to each lesser toe"),
    ("tendon_of_peroneus_longus", "tendon of peroneus longus", "leg-muscles", "Tendons of the leg",
     ["peroneus_longus"], "first_metatarsal",
     [(["behind lateral malleolus", "peroneal trochlea", "cuboid groove"], "first metatarsal base, under",
       (3.0, 1.8), (3.5, 1.5))], [],
     "behind the lateral malleolus, forward along the outer side of the calcaneus, then under the cuboid in its "
     "groove and across the sole to the outer side of the first metatarsal's base and the first cuneiform"),
    ("tendon_of_tibialis_posterior", "tendon of tibialis posterior", "leg-muscles", "Tendons of the leg",
     ["tibialis_posterior"], "navicular",
     [(["behind medial malleolus"], "navicular tuberosity", (3.8, 2.0), (4.5, 1.8))], [],
     "behind the medial malleolus, in the groove it shares with the long flexor of the toes, to the tuberosity "
     "of the navicular"),
    ("tendons_of_flexor_digitorum_longus", "tendons of flexor digitorum longus", "leg-muscles", "Tendons of the leg",
     ["flexor_digitorum_longus"], "phalanx",
     [(["behind medial malleolus: second", "sustentaculum", "sole", f"{toe} toe: under the metatarsal's head",
        f"{toe} toe: under the knuckle"], f"{toe} toe: last phalanx, below", (1.6, 1.0), (1.8, 0.8))
      for toe in TOES[1:]], [],
     "behind the medial malleolus, behind the tibialis posterior's, into the sole, where it divides into four, "
     "one to the base of the last phalanx of each lesser toe"),
    ("tendon_of_flexor_hallucis_longus", "tendon of flexor hallucis longus", "leg-muscles", "Tendons of the leg",
     ["flexor_hallucis_longus"], "phalanx",
     [(["back of talus", "sustentaculum: under", "great toe: under the metatarsal's head",
        "great toe: under the knuckle"], "great toe: last phalanx, below", (2.4, 1.5), (2.8, 1.2))], [],
     "in the groove on the back of the talus and under the sustentaculum tali, forward through the sole to the "
     "base of the last phalanx of the great toe"),
    ("tendon_of_semimembranosus", "tendon of semimembranosus", "thigh-muscles", "Tendons of the thigh",
     ["semimembranosus"], "tibia", [([], "semimembranosus", (5.0, 2.5), (7.0, 2.0))], [],
     "to the groove on the back of the medial condyle of the tibia"),
    ("tendon_of_semitendinosus", "tendon of semitendinosus", "thigh-muscles", "Tendons of the thigh",
     ["semitendinosus"], "tibia",
     [(["behind medial condyle"], "pes semitendinosus", (2.6, 2.0), (4.0, 1.2))], [],
     "a long round tendon from the middle of the thigh, curving round the medial condyle of the tibia to the "
     "upper part of the medial surface of its shaft, behind the sartorius and below the gracilis"),
    ("tendon_of_gracilis", "tendon of gracilis", "thigh-muscles", "Tendons of the thigh",
     ["gracilis"], "tibia", [(["behind medial condyle: gracilis"], "pes gracilis", (2.3, 1.6), (3.6, 1.1))], [],
     "behind the medial condyle of the femur, curving round the medial condyle of the tibia to the upper part "
     "of the medial surface of its shaft"),
    ("tendon_of_sartorius", "tendon of sartorius", "thigh-muscles", "Tendons of the thigh",
     ["sartorius"], "tibia", [(["behind medial condyle: sartorius"], "pes sartorius", (6.0, 1.2), (8.0, 1.0))], [],
     "a flat tendon behind the medial condyle of the femur, curving forward to the upper part of the medial "
     "surface of the tibia, in front of the gracilis and semitendinosus"),
    ("tendon_of_biceps_femoris", "tendon of biceps femoris", "thigh-muscles", "Tendons of the thigh",
     ["biceps_femoris_long_head", "biceps_femoris_short_head"], "fibula",
     [([], "fibular head", (5.0, 2.5), (6.0, 2.0))], [],
     "the two heads' common tendon, to the lateral side of the head of the fibula"),
]


def clear_of(p, bone, r):
    """A point of a tendon's course brought out of the bone, r off it."""
    for _ in range(4):
        ins, d, i = bone.query(p[None], 0.03)
        if not np.isfinite(d[0]) or not (ins[0] or d[0] < r):
            break
        p = bone.P[i[0]] + bone.N[i[0]] * r
    return p


def course(L, name):
    """A named point of landmarks(), or one a little off it: "front of ankle: inner", ": outer"; "behind medial
    malleolus: second" (the second tendon back in that groove); "behind medial condyle: gracilis", ": sartorius"
    (in front of the semitendinosus's, each further forward); "sustentaculum: under" (lower, where the great
    toe's flexor runs)."""
    base, _, how = name.partition(": ")
    if base in L and how and name not in L:
        p = L[base]
        return p + {"inner": -0.011 * L["lat"], "outer": 0.011 * L["lat"],
                    "second": -0.006 * L["fwd"] + 0.002 * L["lat"],
                    "gracilis": 0.006 * L["fwd"] + 0.002 * L["up"], "sartorius": 0.013 * L["fwd"] + 0.004 * L["up"],
                    "under": -0.006 * L["up"] + 0.004 * L["lat"]}[how]
    return L[name]


def make_tendon(row, muscles, L, bone, end_bone, others, say):
    """One tendon of one side: positions and triangles (its slips together), or None with what was said why."""
    from anatomy_muscles_more import relax, unpoke, GAP, MARGIN
    node, label, part, group, from_, _, slips, over, words = row
    V, F = [], []
    for k, (via, target, cord, foot) in enumerate(slips):
        goal = L[target]
        first = course(L, via[0]) if via else goal
        c, d, wide, a0, b0 = ends_of(muscles, first)
        tip = max((v @ d).max() for v in muscles)
        gap = float((goal - c) @ d) if not via else float(np.linalg.norm(first - c))
        if np.linalg.norm(goal - c) < 0.02:
            say(f"      {label}: its muscle ends {np.linalg.norm(goal - c) * 1000:.0f} mm from its insertion: no tendon needed")
            return None
        n = len(slips)
        if n > 1:               # slips leave the muscle side by side
            c = c + wide * a0 * 0.7 * (2 * k / (n - 1) - 1)
            a0 = a0 / n
        cord, foot = np.array(cord) * MM, np.array(foot) * MM
        r = cord[1] + 0.0008
        pts = [c] + [clear_of(course(L, x), bone, r) for x in via]
        dn, i = end_bone.tree.query(goal)
        pts.append(end_bone.P[i] + end_bone.N[i] * OFF)
        C = spline(pts)
        section0 = (max(a0 * 0.85, cord[0]), max(b0 * 0.85, cord[1]))
        v, f, rings = tube(C, wide, section0, tuple(cord), tuple(foot))
        last = np.r_[np.arange((rings - 1) * RING, rings * RING), len(v) - 1]      # its foot laid on the bone
        dl, il = end_bone.tree.query(v[last])
        v[last] = end_bone.P[il] + end_bone.N[il] * OFF
        v, _ = unpoke(v, f, bone, GAP, rounds=8, h=0.0006, sigma=0.004, cap=0.002)
        if others is not None and others.tree is not None:
            v, _ = unpoke(v, f, others, MARGIN, rounds=6, h=0.0008, sigma=0.004, cap=0.002)
        v = relax(v, f, rounds=2)
        v, _ = unpoke(v, f, bone, GAP, rounds=8, h=0.0006, sigma=0.002, cap=0.001, local=True)
        F.append(f + sum(len(x) for x in V))
        V.append(v)
    return np.concatenate(V), np.concatenate(F)


def remake(folder, quiet=False):
    """Adds the lower limbs' long tendons to the bodies in `folder`'s atlas that have the muscles; does nothing
    for those made already. Returns what it did."""
    from anatomy_fibres import read_part, write_part, sha256
    from anatomy_muscles_more import (Surface, area, body_nodes, contact, inside_share, outward_samples, short,
                                      side_of)
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    say = (lambda *a: None) if quiet else log
    only, some = os.environ.get("MORE_ONLY"), os.environ.get("TENDONS")     # development only
    said = []
    for body in manifest["bodies"]:
        if only and body["id"] != only:
            continue
        sex = body["id"]
        nodes = body_nodes(folder, body)
        made = {}
        for side, s, sg in (("left", "L", 1), ("right", "R", -1)):
            B = {short(n)[:-2]: v for n, (pid, st, v, f) in nodes.items()
                 if pid == "legs" and st.get("tissue") == "bone" and short(n).endswith("_" + s)}
            if "calcaneus" not in B or "tibia" not in B:
                continue
            L = landmarks(B, sg)
            pieces = {n: outward_samples(v, f, 0.0006) for n, (pid, st, v, f) in nodes.items()
                      if pid == "legs" and st.get("tissue") in ("bone", "cartilage") and side_of(n) == s}
            box = (np.concatenate(list(B.values())).min(0) - 0.05, np.concatenate(list(B.values())).max(0) + 0.05)
            bone = Surface(pieces=list(pieces.values()), box=box)
            placed = []
            for row in TENDONS:
                node, label, part, group, from_, ends_on, slips, over, words = row
                name = f"TS_{node}_{s}"
                if some and node not in some.split(","):
                    continue
                if name in nodes and nodes[name][1].get("made") == MARK:
                    continue
                mine = [nodes[f"TS_{m}_{s}"][2] for m in from_ if f"TS_{m}_{s}" in nodes]
                if len(mine) < len(from_):
                    said.append(f"{sex} {name}: its muscle is not in this body, not made")
                    continue
                end_bone = Surface(pieces=[x for n, x in pieces.items() if re.search(ends_on, short(n))], box=box)
                keep_out = [outward_samples(*nodes[n][2:4], 0.0008) for n in nodes
                            if nodes[n][1].get("tissue") == "muscle" and side_of(n) == s
                            and nodes[n][0] in ("leg-muscles", "thigh-muscles", "knee-muscles")
                            and re.sub(r"^TS_|_[LR]$", "", n) not in from_]
                others = Surface(pieces=keep_out + placed, box=box)
                got = make_tendon(row, mine, L, bone, end_bone, others, say)
                if got is None:
                    continue
                v, f = got
                st = {"node": name, "label": f"{side} {label}", "tissue": "ligament", "group": group, "inner": False,
                      "made": MARK, "triangles": int(len(f))}
                made[name] = (st, part, v, f)
                placed.append(outward_samples(v, f, 0.0008))
                said.append(f"{sex} {name}: {len(f)} triangles, {area(v, f) * 1e4:.0f} cm2; in bone "
                            f"{inside_share(v, f, bone):.2%}, in others {inside_share(v, f, others):.2%}, on its "
                            f"bone {contact(v, f, end_bone):.0f} mm2")
                say("   " + said[-1])
        for pid in sorted({x[1] for x in made.values()}):
            part = next(p for p in body["parts"] if p["id"] == pid)
            file = os.path.join(folder, part["file"])
            meshes = [(np.asarray(v, np.float64), np.asarray(f, np.int64)) for v, f in read_part(file)]
            had_fibres = part.get("fibres")
            for name, (st, p_, v, f) in made.items():
                if p_ != pid:
                    continue
                k = next((i for i, x in enumerate(part["structures"]) if x["node"] == name), None)
                if k is None:
                    part["structures"].append(st); meshes.append((v, f))
                else:
                    part["structures"][k] = st; meshes[k] = (v, f)
            lo, hi = write_part(file, meshes)
            if had_fibres:           # the fibres file lists the part's structures in order: laid again
                part.pop("fibres", None)
            part["bytes"] = os.path.getsize(file)
            part["sha256"] = sha256(file)
            part["triangles"] = int(sum(x["triangles"] for x in part["structures"]))
            part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    n = sum(1 for line in said if "triangles" in line)
    return f"{n} tendons made" if n else "; ".join(said) or "nothing to make"


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
