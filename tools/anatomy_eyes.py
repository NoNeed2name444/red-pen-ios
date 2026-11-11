#!/usr/bin/env python3
"""The eyes and their muscles, made anew where the organ set put them. The organ set's eyeball is a few hundred
triangles a structure (a lumpy sclera, the cornea and iris thin rims of one colour), its inferior oblique runs
through the eyeball and its muscles end without tendons; these are built to the textbook's measures instead.

  python3 tools/anatomy_eyes.py ATLAS_FOLDER   remakes them in that atlas, then the muscles' bundles
                                               (tools/anatomy_fibres.py); tools/anatomy_atlas.py calls remake()

Each eye's frame is the organ set's: the centre and radius of its sclera's sphere (about 12 mm), its optical axis
from that centre through its cornea, up the body's, nasal toward the midline. In that frame, in millimetres scaled
by the radius over 12:

1. The coats. The sclera a sphere up to the limbus, 5.85 mm off the axis, its rim bevelled inward there. The cornea
   a shell from the organ set's apex (about 13.1 mm before the centre) to the limbus, its front the sphere through
   both (radius about 7.8 mm), 0.55 mm thick in the middle and 0.7 mm at the limbus, clear. In the angle the
   trabecular meshwork, a ring of triangle section from Schwalbe's line to the scleral spur, Schlemm's canal (the
   scleral venous sinus) an oval ring outside it, and the corneoscleral junction a ring within the limbus. The
   choroid and the retina shells inside the sclera from the ora serrata (62 degrees from the front, about 7.5 mm
   behind the limbus) to the back, the ora a band of teeth; the optic disc (1.75 by 1.9 mm, cupped) where the optic
   nerve leaves, the macula lutea (5.5 mm across) and the fovea (1.5 mm, a pit) 22 degrees temporal of it, a
   little below.
2. The iris an annulus from the pupil (3.6 mm across) to its root on the ciliary body, thickest at its collarette,
   with radial ridges and contraction furrows; the pupil a black cap behind the iris's rim, on the lens. The lens
   9.2 mm across and 4 mm thick, its front 3 mm behind the cornea's back. The ciliary body from the iris root to the
   ora, its muscle a triangle in its front, 60 ciliary processes on it pointing at the lens's equator, and the
   zonule's fibres from them to the lens, before, at and behind its equator.
3. The aqueous humour filling the anterior chamber and the vitreous body the space behind the lens, both nearly
   clear. The bulbar conjunctiva a clear film over the sclera from the limbus; the palpebral conjunctiva the pink
   lining of each lid, from its margin (at the limbus) to its fornix, half see-through, facing the eye and laid
   just under the sclera's face, where the lids (not drawn) would hold it: no pink over the white of the eye.
4. The muscles. The four recti from the common tendinous ring around the optic nerve (where the organ set's begin)
   straight to the eyeball, onto it and along it to flat tendons inserted on the spiral of Tillaux: medial 5.5 mm
   behind the limbus, inferior 6.5, lateral 6.9, superior 7.7; their tendons 3.7, 5.5, 8.8 and 5.8 mm long and 10.3,
   9.8, 9.2 and 10.6 mm wide. The superior oblique from above the ring along the orbit's roof to the trochlea (where
   the organ set's bends), its tendon through it and back under the superior rectus to a fan behind the equator,
   superotemporally. The inferior oblique from the orbit's floor behind its rim (where a ray from the eye meets the
   maxilla) back under the inferior rectus and around the eyeball to its insertion below the lateral rectus, near
   the macula, by a short tendon. Where one crosses another the outer gives way, a section at a time, so that it
   bends over the other rather than folding; none enters the eyeball, the optic nerve or another muscle (but where
   they gather at the ring, as they do). Each is nudged off the bone where the bone is on one side of it, by 1 mm
   at most: the scanned skull's orbit is a little tighter than the textbook's cone, and where a muscle is caught
   between two walls it is left touching them rather than crushed. The woman's muscles in "right eye muscles" and
   "left eye muscles", as the man's.
5. Each structure's own colour, how see-through and how glossy, in the manifest ("colour", "opacity",
   "roughness"), which the app draws over its tissue's: the sclera white, the cornea, humours and bulbar
   conjunctiva clear, the lids' linings half so, the iris brown, the pupil black, the choroid dark, the retina
   orange, the disc pale.

The measures are the textbooks' (Gray's Anatomy, 1918, public domain, figs. 869 to 883 and its text on the eye;
the spiral of Tillaux), the shapes checked against the reference index's images of each structure
(docs/sciences/anatomy-references.json): looked at, never traced or shipped.
"""
import json
import os
import re
import sys

import numpy as np
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# how each structure looks: sRGB colour, opacity, roughness
LOOK = {
    "sclera": ("#F2EEE6", 1.0, 0.22),
    "cornea": ("#F4F8FA", 0.28, 0.03),
    "corneo_scleral_junction": ("#EFEBE3", 1.0, 0.2),
    "trabecular_meshwork": ("#5C4A3F", 1.0, 0.5),
    "schlemms_canal": ("#6F86B8", 1.0, 0.3),
    "iris": ("#6B4A2E", 1.0, 0.45),
    "pupil": ("#060607", 1.0, 0.85),
    "lens": ("#F1E4BC", 0.5, 0.08),
    "ciliary_body": ("#3E261B", 1.0, 0.45),
    "ciliary_muscle": ("#8E4A3A", 1.0, 0.42),
    "ciliary_processes": ("#4E2C20", 1.0, 0.45),
    "suspensory_ligament_of_lens": ("#E9E3D3", 1.0, 0.4),
    "optic_choroid": ("#4A2622", 1.0, 0.4),
    "retina": ("#D98C6A", 1.0, 0.3),
    "ora_serrata_of_retina": ("#B06A4E", 1.0, 0.35),
    "optic_disc": ("#F0C9A0", 1.0, 0.3),
    "macula_lutea": ("#C47A3E", 1.0, 0.3),
    "fovea": ("#8A3E22", 1.0, 0.3),
    "vitreous_humor": ("#EEF2F4", 0.05, 0.5),
    "aqueous_humor": ("#EEF2F4", 0.05, 0.5),
    "bulbar_conjunctiva": ("#F2F2F0", 0.06, 0.1),
    "palpebral_conjunctiva_of_upper_eyelid": ("#E39A90", 0.5, 0.25),
    "palpebral_conjunctiva_of_lower_eyelid": ("#E39A90", 0.5, 0.25),
}

# what is drawn with a pattern of its own (AtlasShaders): the iris's fibres, collarette and crypts
SURFACE = {"iris": "iris"}

# the recti: meridian (x nasal, y up), insertion behind the limbus, tendon length, insertion width, belly thickness
# (mm); the spiral of Tillaux
RECTI = {
    "medial_rectus": ((1.0, 0.0), 5.5, 3.7, 10.3, 3.6),
    "inferior_rectus": ((0.0, -1.0), 6.5, 5.5, 9.8, 3.2),
    "lateral_rectus": ((-1.0, 0.0), 6.9, 8.8, 9.2, 3.2),
    "superior_rectus": ((0.0, 1.0), 7.7, 5.8, 10.6, 2.9),
}
LIMBUS = 5.85          # the limbus's distance off the axis (mm)
RING = 4.0             # the common tendinous ring's radius about the optic nerve (mm)


# MARK: meshes

def lattice(rows, closed=False):
    """Triangles between consecutive rows of points (each (n, 3), or one point for a pole), the last row joined to
    the first if `closed`: (vertices, triangles)."""
    n = max(len(r) for r in rows)
    v, index, at = [], [], 0
    for r in rows:
        r = np.atleast_2d(r)
        v.append(r)
        index.append(np.full(n, at) if len(r) == 1 else at + np.arange(n))
        at += len(r)
    j = np.arange(n)
    k = (j + 1) % n
    f = []
    for i in range(len(rows) - (0 if closed else 1)):
        a, b = index[i], index[(i + 1) % len(rows)]
        f += [np.stack([a[j], a[k], b[k]], 1), np.stack([a[j], b[k], b[j]], 1)]
    f = np.vstack(f)
    f = f[(f[:, 0] != f[:, 1]) & (f[:, 1] != f[:, 2]) & (f[:, 2] != f[:, 0])]
    return np.vstack(v).astype(np.float64), f


def revolve(profile, n, phase=0.0, closed=False, bump=None):
    """A surface of revolution about z from (rho, z) rows (rho 0 a pole); bump(rho, phi) -> dz on a row's points."""
    phi = phase + 2 * np.pi * np.arange(n) / n
    rows = []
    for rho, z in profile:
        if rho < 1e-9:
            rows.append(np.array([[0.0, 0.0, z]]))
            continue
        dz = bump(rho, phi) if bump is not None else 0.0
        rows.append(np.c_[rho * np.cos(phi), rho * np.sin(phi), z + dz * np.ones(n)])
    return lattice(rows, closed)


def facing(v, f, out):
    """The triangles wound so their normals agree with out(centroids) ((m, 3) directions) on the whole."""
    c = v[f].mean(1)
    nrm = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    return f if np.einsum("ij,ij->i", nrm, out(c)).sum() >= 0 else f[:, ::-1]


def outward(v, f):
    """A closed mesh's triangles wound to face out."""
    vol = np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum()
    return f if vol > 0 else f[:, ::-1]


def merge(meshes):
    v, f, at = [], [], 0
    for mv, mf in meshes:
        v.append(mv)
        f.append(mf + at)
        at += len(mv)
    return np.vstack(v), np.vstack(f)


def smooth(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(x):
    x = np.asarray(x, float)
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-12)


def toward(d, w, angle):
    """The unit vector d turned by `angle` toward w."""
    d = unit(d)
    t = unit(np.asarray(w, float) - (np.asarray(w, float) @ d) * d)
    return unit(d * np.cos(angle) + t * np.sin(angle))


def on_sphere(r, theta, phi):
    """Points at radius r, `theta` from the front pole (+z), `phi` about the axis from nasal (+x) toward up (+y)."""
    theta, phi = np.broadcast_arrays(np.asarray(theta, float), np.asarray(phi, float))
    return np.stack([r * np.sin(theta) * np.cos(phi), r * np.sin(theta) * np.sin(phi), r * np.cos(theta)], -1)


def patch(r, centre, half, n=(32, 4), lift=None):
    """A round patch on the sphere of radius r about the direction `centre`, of angular half-size `half`
    ((across, up), radians), rings out from the middle; lift(s) -> extra radius at fraction s of the way out."""
    c = unit(centre)
    a = unit(np.cross([0.0, 1.0, 0.0], c))
    b = np.cross(c, a)
    phi = 2 * np.pi * np.arange(n[0]) / n[0]
    rows = [r * c[None] * (1 + (lift(0.0) / r if lift else 0))]
    for s in np.linspace(0, 1, n[1] + 1)[1:]:
        d = unit(c[None] + np.tan(s * half[0]) * np.cos(phi)[:, None] * a + np.tan(s * half[1]) * np.sin(phi)[:, None] * b)
        rows.append(d * (r + (lift(s) if lift else 0.0)))
    v, f = lattice(rows)
    return v, facing(v, f, lambda p: -p)        # facing the eye's middle (seen from within)


# MARK: the eyeball

def eyeball(R, apex, disc):
    """The eyeball's structures in its frame (mm): {key: (vertices, triangles)}. R the sclera's radius, apex the
    cornea's front (along +z), disc the direction the optic nerve leaves by."""
    s = R / 12.0
    out = {}
    L = LIMBUS * s
    zl = np.sqrt(R * R - L * L)
    thl = np.arcsin(L / R)                                  # the limbus, from the front pole
    # sclera: the sphere from the limbus back, its rim under the limbus's white and the angle's meshwork (below)
    th = np.r_[np.linspace(thl, thl + 0.5, 8), np.linspace(thl + 0.5, np.pi, 21)[1:]]
    prof = [(R * np.sin(t), R * np.cos(t)) for t in th]
    v, f = revolve(prof, 72)
    out["sclera"] = (v, facing(v, f, lambda p: p))
    # cornea: front the sphere through the apex and the limbus, back 0.55 mm in at the middle, 0.7 at the rim
    h = apex - zl
    rc = (L * L + h * h) / (2 * h)
    front = [(rc * np.sin(t), apex - rc + rc * np.cos(t)) for t in np.linspace(0, np.arcsin(L / rc), 13)]
    back_apex, back_rim = apex - 0.55 * s, (L - 0.52 * s, zl - 0.47 * s)
    hb = back_apex - back_rim[1]
    rb = (back_rim[0] ** 2 + hb * hb) / (2 * hb)
    back = [(rb * np.sin(t), back_apex - rb + rb * np.cos(t)) for t in np.linspace(np.arcsin(back_rim[0] / rb), 0, 7)]
    v, f = revolve(front + back[::2] + back[-1:], 72)
    out["cornea"] = (v, outward(v, f))
    cornea_back = lambda rho: back_apex - rb + np.sqrt(np.maximum(rb * rb - rho * rho, 0))
    # the angle: the trabecular meshwork lining the limbus's inside from Schwalbe's line (the cornea's back rim) to
    # the recess before the iris's root and back to the ciliary body, as gonioscopy shows it (a pigmented band,
    # grey-brown), filling the corner between the cornea's rim, the sclera and the ciliary body: so that through the
    # cornea the angle shows dark, as it does (the limbal ring about the iris), and nothing white of the sclera's
    # inside (the sclera is one surface here, its thickness the room the angle's parts lie in)
    schwalbe = np.array(back_rim)
    spur = np.array([L - 0.08 * s, zl - 0.85 * s])
    recess = np.array([L - 0.40 * s, zl - 0.85 * s])
    corner = [on_sphere(R - 0.02 * s, thl + 0.004, 0)[[0, 2]], schwalbe + [0.02 * s, 0], recess,
              on_sphere(R - 0.6 * s, thl + 0.06, 0)[[0, 2]], on_sphere(R - 0.02 * s, thl + 0.06, 0)[[0, 2]],
              on_sphere(R - 0.02 * s, thl + 0.03, 0)[[0, 2]]]
    v, f = revolve([tuple(p) for p in corner], 72, closed=True)
    out["trabecular_meshwork"] = (v, outward(v, f))
    mid = np.array([L + 0.12 * s, zl - 0.5 * s])
    along = unit(schwalbe - spur)
    acr = np.array([along[1], -along[0]])
    ell = [tuple(mid + 0.17 * s * np.cos(t) * along + 0.05 * s * np.sin(t) * acr) for t in np.linspace(0, 2 * np.pi, 7)[:-1]]
    v, f = revolve(ell, 48, closed=True)
    out["schlemms_canal"] = (v, outward(v, f))
    # the limbus (the corneo-scleral junction): the sclera's white run on just over the cornea's rim, to 5.75 mm off
    # the axis (white to white 11.5 mm), where the cornea has barely begun to rise, as the sclera overlaps the cornea
    # there; its face rounding from the sclera's curve into the cornea's over the sulcus between them, a hair
    # (0.01 mm) over both, its edge on the cornea a wall too low to see and its edge on the sclera sunk into it, so
    # that seen from the side nothing stands up at the cornea's rim and from the front the clear cornea begins
    # where the white ends (the dark band of the angle's meshwork just inside it, as the limbal ring)
    e, tip, zc = 0.01 * s, 5.75 * s, apex - rc
    on_c = [(r, zc + np.sqrt((rc + e) ** 2 - r * r)) for r in np.linspace(tip, L, 4)[:-1]]
    on_s = [((R + e) * np.sin(t), (R + e) * np.cos(t)) for t in thl + np.linspace(0, 0.06, 4)]
    on_s[-1] = ((R - e) * np.sin(thl + 0.06), (R - e) * np.cos(thl + 0.06))    # sunk at its back edge
    face = np.array(on_c + on_s)
    for _ in range(4):                                       # the sulcus rounded, the ends held
        face[1:-1] = 0.5 * face[1:-1] + 0.25 * (face[:-2] + face[2:])
    cdist = np.hypot(face[:, 0], face[:, 1] - zc)
    out_c = (face[:, 0] < L) & (cdist < rc + e)
    face[out_c] = np.c_[face[out_c, 0], face[out_c, 1] - zc] / cdist[out_c, None] * (rc + e) + [0, zc]
    sdist = np.hypot(face[:, 0], face[:, 1])
    out_s = (face[:, 0] >= L) & (sdist < R + e) & (np.arange(len(face)) < len(face) - 1)
    face[out_s] = face[out_s] / sdist[out_s, None] * (R + e)
    tang = np.gradient(face, axis=0)
    inward = unit(np.c_[tang[:, 1], -tang[:, 0]])
    inward = np.where((np.einsum("ij,ij->i", inward, face - [0, zc]) > 0)[:, None], -inward, inward)
    depth = 2 * e + 0.03 * s * np.sin(np.linspace(0, np.pi, len(face)))
    under = (face + depth[:, None] * inward)[[6, 4, 2, 0]]
    v, f = revolve([tuple(p) for p in face] + [tuple(p) for p in under], 72, closed=True)
    out["corneo_scleral_junction"] = (v, outward(v, f))
    # lens: the equator 4.6 mm off the axis, its front 3 mm behind the cornea's back, 4 mm thick
    la, lr = back_apex - 3.0 * s, 4.6 * s
    ha, hp = 1.6 * s, 2.4 * s
    ze = la - ha
    lens_front = lambda rho: ze + ha * np.sqrt(np.clip(1 - (rho / lr) ** 2, 0, 1))
    lens_back = lambda rho: ze - hp * np.sqrt(np.clip(1 - (rho / lr) ** 2, 0, 1))
    t = np.linspace(0, np.pi / 2, 9)
    prof = [(lr * np.sin(a), ze + ha * np.cos(a)) for a in t] + [(lr * np.cos(a), ze - hp * np.sin(a)) for a in t[1:]]
    v, f = revolve(prof, 40)
    out["lens"] = (v, outward(v, f))
    # iris: from the pupil's rim to its root, thickest at the collarette; low ridges and furrows on its front (its
    # fibres, crypts and rings are drawn on it, AtlasShaders.iris: ridges deep enough to show them alone read as a
    # fluted cap)
    pupil = 1.8 * s
    root = np.array([L - 0.42 * s, zl - 1.05 * s])
    rho = np.array([pupil, 2.0, 2.4, 2.9, 3.3, 3.7, 4.1, 4.5, 4.8, 5.1, 5.3]) * s
    rho[-1] = root[0]
    rest = lens_front(pupil) + 0.04 * s                      # the rim's back lies on the lens
    zf = rest + np.interp(rho / s, [1.8, 2.4, 3.3, 4.1, 4.8, 5.43], [0.33, 0.48, 0.55, 0.42, 0.22, -0.02]) * s
    zf[-1] = root[1] + 0.12 * s
    thick = np.interp(rho / s, [1.8, 2.1, 3.3, 4.4, 5.43], [0.3, 0.45, 0.62, 0.42, 0.22]) * s
    collarette = 3.3 * s

    def iris_bump(r, phi):
        ridge = 0.018 * s * np.cos(28 * phi + 1.3 * np.sin(3 * phi)) * smooth(collarette, collarette + 0.4 * s, r) * \
            smooth(root[0], root[0] - 0.4 * s, r)
        fine = 0.008 * s * np.cos(44 * phi + 0.7 * np.sin(5 * phi)) * smooth(pupil + 0.15 * s, pupil + 0.5 * s, r) * \
            smooth(collarette, collarette - 0.3 * s, r)
        crest = 0.07 * s * np.exp(-((r - collarette - 0.12 * s * np.sin(9 * phi)) / (0.22 * s)) ** 2)
        furrow = -0.04 * s * (np.exp(-((r - 4.25 * s) / (0.1 * s)) ** 2) + np.exp(-((r - 4.75 * s) / (0.1 * s)) ** 2))
        return ridge + fine + crest + furrow

    front = list(zip(rho, zf))
    keep = [10, 8, 6, 4, 2, 0]                                # the back, hidden, in fewer rows
    back = [(rho[i], zf[i] - thick[i]) for i in keep]
    ruff = [(pupil - 0.05 * s, rest + 0.13 * s)]
    n = 96
    v_f, f_f = revolve(front, n, bump=iris_bump)
    v_b, f_b = revolve(back + ruff, n)
    # one closed ring: the front rows, then the back rows and the ruff, joined at the root and the rim
    rows_front = [v_f[i * n:(i + 1) * n] for i in range(len(front))]
    rows_back = [v_b[i * n:(i + 1) * n] for i in range(len(back) + 1)]
    v, f = lattice(rows_front + rows_back, closed=True)
    out["iris"] = (v, outward(v, f))
    # pupil: a black cap on the lens, under the iris's rim
    edge = pupil + 0.15 * s
    cap = [(r, lens_front(r) + 0.035 * s) for r in np.linspace(0, edge, 5)]
    cap += [(r, lens_front(r) + 0.012 * s) for r in np.linspace(edge, 0, 5)]
    v, f = revolve(cap, 32)
    out["pupil"] = (v, outward(v, f))
    # the ciliary body: from the iris root along the sclera's inside to the ora
    ri = R - 0.62 * s                                       # the sclera's inner surface
    ora = thl + 7.5 * s / R
    th_body = np.linspace(thl + 0.04, ora, 9)
    rows_at = [0, 1, 2, 3, 5, 8]                             # the body's rows (the processes use all nine)
    outer = [on_sphere(ri, t, 0)[[0, 2]] for t in th_body]
    inner_r = ri - np.interp(th_body, [thl, thl + 0.12, thl + 0.22, ora - 0.15, ora], [0.9, 1.0, 0.6, 0.5, 0.25]) * s
    inner = [on_sphere(r, t, 0)[[0, 2]] for r, t in zip(inner_r, th_body)]
    prof = [tuple(outer[i]) for i in rows_at] + [tuple(inner[i]) for i in rows_at[::-1]] + [tuple(root + [0.1 * s, -0.2 * s])]
    v, f = revolve(prof, 48, closed=True)
    out["ciliary_body"] = (v, outward(v, f))
    tri = [on_sphere(ri - 0.05 * s, thl + 0.05, 0)[[0, 2]], on_sphere(ri - 0.05 * s, thl + 0.2, 0)[[0, 2]],
           on_sphere(ri - 0.7 * s, thl + 0.07, 0)[[0, 2]]]
    v, f = revolve([tuple(p) for p in tri], 48, closed=True)
    out["ciliary_muscle"] = (v, outward(v, f))
    # 60 ciliary processes: ridges on the pars plicata reaching aim the lens's equator
    procs = []
    for k in range(60):
        phi = 2 * np.pi * (k + 0.5) / 60
        base = [on_sphere(r, t, phi) for r, t in zip(inner_r[1:4], th_body[1:4])]
        a0, a1 = base[0], base[2]
        mid_b = base[1]
        # the crest reaches to 0.6 mm off the lens's equator
        aim = unit(np.array([lr * np.cos(phi), lr * np.sin(phi), ze]) - mid_b)
        reach = np.linalg.norm(np.array([lr * np.cos(phi), lr * np.sin(phi), ze]) - mid_b) - 0.6 * s
        tip = mid_b + aim * reach
        side = unit(np.cross(aim, a1 - a0)) * 0.16 * s
        # a closed spindle: base front, tip, base back, either side
        rows = [a0, np.stack([0.5 * (a0 + mid_b) + side, 0.55 * mid_b + 0.45 * tip, 0.5 * (a0 + mid_b) - side, 0.5 * (a0 + mid_b) - 0.01 * aim]),
                np.stack([mid_b + side * 1.2, tip, mid_b - side * 1.2, mid_b - 0.02 * aim]),
                np.stack([0.5 * (a1 + mid_b) + side, 0.6 * mid_b + 0.4 * tip, 0.5 * (a1 + mid_b) - side, 0.5 * (a1 + mid_b) - 0.01 * aim]), a1]
        pv, pf = lattice(rows)
        procs.append((pv, outward(pv - pv.mean(0), pf)))
    out["ciliary_processes"] = merge(procs)
    # the zonule: fibres in the valleys between the processes to the lens, before and behind its equator in one
    # valley, at it in the next
    strands = []
    fibres = (((th_body[2], (0.86 * lr, lens_front(0.86 * lr))), (th_body[5], (0.88 * lr, lens_back(0.88 * lr)))),
              ((th_body[3], (lr * 0.995, ze)),))
    for k in range(60):
        phi = 2 * np.pi * k / 60
        for start_t, end in fibres[k % 2]:
            p0 = on_sphere(np.interp(start_t, th_body, inner_r) - 0.05 * s, start_t, phi)
            p1 = np.array([end[0] * np.cos(phi), end[0] * np.sin(phi), end[1]])
            d = unit(p1 - p0)
            e1 = unit(np.cross(d, [0, 0, 1.0])) * 0.035 * s
            e2 = np.cross(d, unit(e1)) * 0.035 * s
            ring = lambda p: np.stack([p + e1, p + e2 * 0.9 - e1 * 0.5, p - e2 * 0.9 - e1 * 0.5])
            sv, sf = lattice([p0, ring(p0 + 0.3 * (p1 - p0)), ring(p0 + 0.7 * (p1 - p0)), p1])
            strands.append((sv, outward(sv - sv.mean(0), sf)))
    out["suspensory_ligament_of_lens"] = merge(strands)
    # choroid and retina: shells inside the sclera from the ora back; the ora a band of teeth
    th = np.r_[np.linspace(ora - 0.03, np.pi * 0.75, 7), np.linspace(np.pi * 0.75, np.pi, 6)[1:]]
    for key, r, t0 in (("optic_choroid", ri - 0.04 * s, ora - 0.05), ("retina", ri - 0.3 * s, ora)):
        tt = np.r_[t0, th[1:]]
        v, f = revolve([(r * np.sin(t), r * np.cos(t)) for t in tt], 48)
        out[key] = (v, facing(v, f, lambda p: p))
    teeth = lambda phi: 0.045 * np.clip(np.cos(24 * phi), 0, 1) ** 3
    phi = 2 * np.pi * np.arange(144) / 144
    rows = [on_sphere(ri - 0.33 * s, ora + 0.035 - teeth(phi) * 0.25, phi), on_sphere(ri - 0.33 * s, ora - 0.005 - teeth(phi), phi)]
    v, f = lattice(rows, closed=False)
    out["ora_serrata_of_retina"] = (v, facing(v, f, lambda p: -p))
    # the optic disc where the nerve leaves, its rim raised and its middle cupped; the macula and fovea 22 degrees
    # temporal of it, a little below; all just within the retina
    d = unit(disc)
    rr = ri - 0.3 * s
    out["optic_disc"] = patch(rr - 0.12 * s, d, (0.875 * s / rr, 0.95 * s / rr), (28, 4),
                              lift=lambda q: 0.1 * s * (1 - smooth(0.25, 0.55, q)) - 0.04 * s * np.exp(-((q - 0.8) / 0.15) ** 2))
    fov = toward(toward(d, [-1.0, 0, 0], 0.384), [0, -1.0, 0], 0.07)
    out["macula_lutea"] = patch(rr - 0.05 * s, fov, (2.75 * s / rr, 2.75 * s / rr), (28, 3),
                                lift=lambda q: 0.02 * s * (1 - q))
    out["fovea"] = patch(rr - 0.08 * s, fov, (0.75 * s / rr, 0.75 * s / rr), (20, 2),
                         lift=lambda q: 0.06 * s * (1 - smooth(0.0, 1.0, q)))
    # the humours: the vitreous behind the lens, the aqueous in the anterior chamber
    th = np.linspace(np.pi, ora + 0.04, 10)
    back = [(0.0, -(ri - 0.5 * s))] + [((ri - 0.5 * s) * np.sin(t), (ri - 0.5 * s) * np.cos(t)) for t in th[1:]]
    plana = on_sphere(inner_r[5] - 0.08 * s, th_body[5], 0)[[0, 2]]
    vit = back + [tuple(plana), (lr * 0.97, ze - 0.25 * s)] + [(r, lens_back(r) - 0.05 * s) for r in np.linspace(lr * 0.85, 0, 5)]
    v, f = revolve(vit, 32)
    out["vitreous_humor"] = (v, outward(v, f))
    iris_front = lambda r: np.interp(r, rho, zf)
    aq = [(r, cornea_back(r) - 0.03 * s) for r in np.linspace(0, back_rim[0] - 0.02 * s, 7)]
    aq += [tuple(recess + [-0.04 * s, 0.05 * s]), (root[0] - 0.05 * s, iris_front(root[0] - 0.05 * s) + 0.05 * s)]
    aq += [(r, iris_front(r) + 0.06 * s) for r in np.linspace(4.6 * s, pupil + 0.05 * s, 6)]
    aq += [(r, lens_front(r) + 0.05 * s) for r in np.linspace(pupil - 0.05 * s, 0, 4)]
    v, f = revolve(aq, 32)
    out["aqueous_humor"] = (v, outward(v, f))
    # the bulbar conjunctiva over the sclera from the limbus (laid over the recti's tendons once they are made:
    # drape(), in remake())
    th = np.linspace(thl + 0.01, thl + 0.85, 13)
    v, f = revolve([((R + 0.1 * s) * np.sin(t), (R + 0.1 * s) * np.cos(t)) for t in th], 72)
    out["bulbar_conjunctiva"] = (v, facing(v, f, lambda p: p))
    # the palpebral conjunctiva: each lid's lining, from its margin (at the limbus, above and below) to its fornix,
    # facing the eye as a lining does, and laid just under the sclera's face, where the lids (not drawn) would
    # hold it against the eyeball: so it is never seen over the white. Laid over the eyeball, half see-through,
    # it was: a pink film over the sclera where its face turned to the eye, and, facing the eye, still a pink rim
    # at the eyeball's outline from its far side. Shown alone it shows its pink face, the side toward the eye.
    rp = R - 0.05 * s                                       # under the sclera's facets (they sag 0.013 mm)
    for key, margin, fornix in (("palpebral_conjunctiva_of_upper_eyelid", thl + 0.03, 1.18),
                                ("palpebral_conjunctiva_of_lower_eyelid", -(thl + 0.03), -0.98)):
        alpha = np.linspace(-1.12, 1.0, 25)                 # temporal to nasal about the vertical
        w = np.cos(np.pi / 2 * (alpha - (-0.06)) / 1.07).clip(0, 1) ** 0.7
        b0 = margin * w
        b1 = fornix * (0.35 + 0.65 * w)
        rows = []
        for q in np.linspace(0, 1, 7):
            beta = b0 + (b1 - b0) * q
            rows.append(rp * np.stack([np.sin(alpha) * np.cos(beta), np.sin(beta), np.cos(alpha) * np.cos(beta)], 1))
        grid = np.array(rows)                                # (7, 25, 3)
        v = grid.reshape(-1, 3)
        i, j = np.meshgrid(np.arange(6), np.arange(24), indexing="ij")
        a = (i * 25 + j).ravel()
        f = np.vstack([np.stack([a, a + 1, a + 26], 1), np.stack([a, a + 26, a + 25], 1)])
        out[key] = (v, facing(v, f, lambda p: -p))
    return out


# MARK: the muscles

SECTION = 16           # points around a muscle's section
BED = -0.06            # a muscle lying on the sclera has its underside this far off it (mm): under its face, so
                       # that a tendon's thin edge is in the sclera and its face comes out of the sclera's at an
                       # angle (no face of the edge, nor the sclera's, then flickers through the other)
FLOOR = -0.09          # and none of it deeper (the suite's bound is 0.15)
EDGE = 0.5             # a tendon lying on the sclera rises to its full thickness within this of its edge (mm)


def sweep(path, width, thick, up, n=SECTION, p=2.3, hug=None, back=None, seat=None):
    """A closed tube along `path` ((k, 3)), `width` and `thick` its full sizes at each point, its thickness lying
    along `up` (made perpendicular to the path) and its width across, each end closed by its middle point. Its
    sections are superellipses of exponent p (one number, or one a point): 2 an ellipse, under 2 a lens whose edges
    thin to nothing, as a tendon's do, over 2 a fuller belly. back ((k,), mm) carries each section's edges that far
    on along the path (away from its first point) and its middle not, so that the insertion's line is curved, its
    middle foremost. Where hug ((k,), 0 to 1) is above 0, a section lies on the eyeball (centred at the origin) as
    on a bed: its underside on the sphere of radius `seat` across its whole width, its thickness all above it, its
    edges meeting the sphere in a fine edge, so that a tendon lies flat on the sclera and blends into it rather than
    standing on it (a tendon's top rising from the sphere within EDGE of its edge and flat across, so its edge
    comes out of the sclera along a clean line); an end lying on the eyeball is closed by rings drawn in to its
    middle along the sphere, so its end lies on the sclera too."""
    t = unit(np.gradient(path, axis=0))
    u = unit(up - np.einsum("ij,ij->i", up, t)[:, None] * t)
    w = np.cross(t, u)
    # the points around a section closer together toward its edges (where a flat section turns), and none on an
    # edge itself but one either side of it, above and below: so a thin edge is a wall too low to see between its
    # two faces, and the top face's edge takes its light from the top face alone (one point where the faces met
    # would take it from both, facing apart, and show as a line)
    q = 4 * (np.arange(n) + 0.5) / n
    k, f = np.floor(q), q - np.floor(q)
    a = (k + np.where(k % 2 == 0, f ** 1.6, 1 - (1 - f) ** 1.6)) * np.pi / 2
    p = np.broadcast_to(np.asarray(p, float), (len(path),))
    rows = []
    for k in range(len(path)):
        cx = np.sign(np.cos(a)) * np.abs(np.cos(a)) ** (2 / p[k])
        cy = np.sign(np.sin(a)) * np.abs(np.sin(a)) ** (2 / p[k])
        across = path[k] + (width[k] / 2 * cx)[:, None] * w[k]
        if back is not None and back[k] > 0:
            across = across + (back[k] * cx * cx)[:, None] * t[k]
        ring = across + (thick[k] / 2 * cy)[:, None] * u[k]
        if hug is not None and hug[k] > 0:
            # its thickness all above the bed: a tendon's (p under 2) a band whose top rises from the bed within
            # EDGE of its edge, steeply (at 30 degrees or so), and is flat across, so that it comes out of the
            # sclera along one clean line: a top rising at a few degrees across its whole width (a lens) met the
            # sclera along a line that wandered a third of a millimetre with the sclera's facets, and read as a
            # sticker's torn edge; a belly's its section's own top
            edge = (1 - np.abs(cx)) * width[k] / 2
            lens = np.where(cy > 0, np.sin(np.pi / 2 * np.clip(edge / EDGE, 0, 1)) ** 0.7, 0.0)
            wt = float(np.clip((2.0 - p[k]) / 0.3, 0, 1))
            top = wt * lens + (1 - wt) * np.clip(cy, 0, None)
            bed = unit(across) * (seat + thick[k] * top)[:, None]
            ring = ring + hug[k] * (bed - ring)
        rows.append(ring)
    first = [path[0]]
    if hug is not None and hug[0] >= 0.5:
        # the end on the eyeball: its middle on the bed, two rings between drawn in to it along the sphere
        middle = unit(path[0]) * seat
        lift = np.linalg.norm(rows[0], axis=1) - seat
        first = [middle] + [unit(middle + f * (rows[0] - middle)) * (seat + f * lift)[:, None] for f in (1 / 3, 2 / 3)]
    v, f = lattice(first + rows + [path[-1]])
    return v, outward(v - v.mean(0), f)


def dome(s, total, r):
    """Each point's share of its section's full size: 1, but within r of the end at `total`, where the muscle
    closes as a dome does (to a seventh at the very end, which its middle point closes)."""
    q = np.clip((np.asarray(s, float) - (total - r)) / r, 0, 1)
    return np.maximum(np.sqrt(np.maximum(1 - q * q, 0.0)), 0.15)


def insertion_curve(s, sc, deep=1.0, over=3.0):
    """How far a section's edges lie behind its middle (sweep's back): `deep` mm at the insertion, none `over` mm
    along, so the insertion's line is bowed forward at its middle, as a rectus's is."""
    return deep * sc * np.clip(1 - np.asarray(s, float) / (over * sc), 0, 1)


def stepped(dense, fine_until, sc, fine=0.5, coarse=1.3, end=0.3, end_span=2.0):
    """The polyline `dense` at even steps along it: `fine` mm up to `fine_until` (the tendon and the belly's rise),
    `coarse` along the belly, `end` within `end_span` mm of its far end (its rounded end)."""
    total = float(np.linalg.norm(np.diff(dense, axis=0), axis=1).sum())
    return resample(dense, lambda at: fine * sc if at < fine_until else (end * sc if at > total - end_span * sc
                                                                           else coarse * sc))


def hugging(path, R, sc):
    """How far each point of a muscle's path lies on the eyeball: 1 within 1.5 mm of it, 0 from 4 mm."""
    return smooth(R + 4 * sc, R + 1.5 * sc, np.linalg.norm(path, axis=1))


def resample(points, step):
    """The polyline through `points` at even steps along it (`step` mm, or a function of the length so far)."""
    seg = np.linalg.norm(np.diff(points, axis=0), axis=1)
    s = np.r_[0, np.cumsum(seg)]
    out, at = [0.0], 0.0
    while at < s[-1]:
        at += step(at) if callable(step) else step
        out.append(min(at, s[-1]))
    out = np.unique(np.array(out))
    return np.stack([np.interp(out, s, points[:, i]) for i in range(3)], 1), out


def wrap_path(I, O, r, steps=60, nasal_to=None):
    """From I (on the sphere of radius r) along the great circle toward O, to where the line to O leaves it as a
    tangent (or on along the sphere until its x, nasal, reaches nasal_to: the superior oblique's tendon is held to
    the eyeball by the superior rectus over it, so leaves it only past the rectus's nasal border), then straight to
    O: a dense polyline."""
    e1 = unit(I)
    e2 = unit(O - (O @ e1) * e1)
    a_o = np.arctan2(O @ e2, O @ e1)
    a_t = max(a_o - np.arccos(np.clip(r / np.linalg.norm(O), -1, 1)), 0.0)
    if nasal_to is not None:
        on = [a for a in np.linspace(a_t, a_o, 400)[:-20] if r * (np.cos(a) * e1[0] + np.sin(a) * e2[0]) >= nasal_to]
        a_t = on[0] if on else a_t
    arc = [r * (np.cos(a) * e1 + np.sin(a) * e2) for a in np.linspace(0, a_t, steps)]
    line = [arc[-1] + (O - arc[-1]) * q for q in np.linspace(0, 1, steps)[1:]]
    return np.array(arc + line)


def rounded(points, sc, sigma=1.5):
    """The polyline rounded where it bends, over about `sigma` mm, its ends where they were: resampled at 0.25 mm
    and blurred along itself, the blur fading out toward each end."""
    from scipy.ndimage import gaussian_filter1d
    p, s = resample(points, 0.25 * sc)
    q = gaussian_filter1d(p, sigma * 4, axis=0, mode="nearest")
    keep = smooth(0, 3 * sigma * sc, np.minimum(s, s[-1] - s))[:, None]
    return p + keep * (q - p)


def clear_of_globe(path, thick, R, gap, rounds=30):
    """The path moved out from the globe's centre where its inner face would go into it, then evened."""
    p = path.copy()
    for _ in range(rounds):
        need = R + gap + thick / 2
        d = np.linalg.norm(p, axis=1)
        p = np.where((d < need)[:, None], p / d[:, None] * need[:, None], p)
        q = p.copy()
        q[1:-1] = 0.5 * p[1:-1] + 0.25 * (p[:-2] + p[2:])
        p = q
    d = np.linalg.norm(p, axis=1)
    need = R + gap + thick / 2
    return np.where((d < need)[:, None], p / d[:, None] * need[:, None], p)


def thickness_way(path, A, R):
    """Which way a muscle's thickness lies: away from the eyeball's centre near it, away from the line from the
    eyeball to the common ring (the cone the recti make) farther back."""
    axis = unit(A)
    off = path - np.outer(path @ axis, axis)
    near = smooth(R + 12, R + 3, np.linalg.norm(path, axis=1))[:, None]
    return unit(near * unit(path) + (1 - near) * unit(off))


def profile(s, at, values):
    from scipy.interpolate import PchipInterpolator
    return PchipInterpolator(at, values)(np.clip(s, at[0], at[-1]))


def rectus(R, sc, key, O, A):
    """A rectus from its origin O on the common ring (A its middle) to its insertion: (vertices, triangles). A flat
    band: its tendon thin, its edges thinning to nothing, and thinner still where it meets the sclera, along a line
    bowed forward at its middle; the belly swelling from it over a few millimetres (the fibres' step reads tendon
    where a muscle is under half its thickest, so the white ends about where the textbook's tendon does) and
    narrowing to a rounded end at the ring."""
    meridian, behind, tendon, wide, belly = RECTI[key]
    m3 = np.array([meridian[0], meridian[1], 0.0])
    thl = np.arcsin(LIMBUS * sc / R)
    th_i = thl + behind * sc / R
    rt = R + 0.2 * sc
    I = rt * (np.sin(th_i) * m3 + np.array([0, 0, np.cos(th_i)]))
    dense = wrap_path(I, O, rt)
    path, s = stepped(dense, (tendon + 6) * sc, sc)
    total = s[-1]
    lt, lb = tendon * sc, total - (tendon + 5) * sc - 5 * sc
    at = [0, 0.4 * sc, lt - 0.5 * sc, lt + 1.0 * sc, lt + 3.5 * sc, lt + 5 * sc + 0.4 * lb, total - 5 * sc, total]
    width = profile(s, at, [wide, wide, 0.95 * wide, 0.91 * wide, 0.88 * wide, 0.9 * wide, 0.42 * wide, 3.2]) * sc
    thick = profile(s, at, [0.03, 0.24, 0.4, 0.42 * belly, 0.8 * belly, belly, 0.55 * belly, 1.5]) * sc
    p = profile(s, at, [1.7, 1.7, 1.7, 2.0, 2.3, 2.3, 2.3, 2.2])
    end = dome(s, total, 1.8 * sc)
    width, thick = width * end, thick * end
    path = clear_of_globe(path, thick, R, 0.04 * sc)
    return sweep(path, width, thick, thickness_way(path, A, R), p=p, hug=hugging(path, R, sc),
                 back=insertion_curve(s, sc), seat=R + BED * sc)


def superior_oblique(R, sc, O, trochlea, A):
    """From above the common ring along the roof to the trochlea, its tendon through it and back under the
    superior rectus to a fan behind the equator, superotemporally: the fan thin, its edges thinning to nothing and
    its insertion's line bowed; the tendon round in the trochlea and a flat band under the rectus; the belly
    swelling behind the trochlea and ending rounded at its origin."""
    # its insertion's middle 120 deg from the front pole, superotemporally: the reflected tendon's anterior border
    # then passes about 5 mm behind the superior rectus's nasal insertion corner, and the insertion's anterior end
    # lies about 7.5 mm behind the rectus's temporal one (5.1 and 7.7 mm in enucleated eyes stained with trypan
    # blue, J Korean Ophthalmol Soc 2012); at 110 deg it crossed 2.5 mm behind the corner and lifted the rectus's
    # tendon off the sclera next to its insertion
    I = on_sphere(R + 0.22 * sc, np.radians(120), np.radians(112))
    # under the superior rectus it lies on the eyeball, the rectus over it; it leaves the eyeball for the trochlea
    # past the rectus's nasal border (its middle 6.5 mm nasal), the bend rounded. (A straight line from the
    # trochlea, laid on the eyeball where it would pass inside it, met the eyeball under the rectus and raised its
    # tendon a millimetre; leaving at 7.5 mm raised it more.)
    reflected = rounded(wrap_path(I, trochlea, R + 0.22 * sc, nasal_to=6.5 * sc), sc)
    # round the bend at the trochlea, 2.5 mm either way
    back = trochlea + unit(O - trochlea) * 2.5 * sc
    front = trochlea + unit(reflected[-8] - trochlea) * 2.5 * sc
    bend = np.array([(1 - q) ** 2 * front + 2 * q * (1 - q) * trochlea + q * q * back for q in np.linspace(0, 1, 9)])
    keep = np.linalg.norm(reflected - trochlea, axis=1) > 2.5 * sc
    dense = np.vstack([reflected[keep], bend, [back + (O - back) * q for q in np.linspace(0, 1, 30)[1:]]])
    along = np.r_[0, np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))]
    there, whole = along[np.argmin(np.linalg.norm(dense - trochlea, axis=1))], along[-1]
    # finely along the fan and round the trochlea, coarser along the belly, finely again at its rounded end
    path, s = resample(dense, lambda at: 0.5 * sc if at < 8 * sc else 0.7 * sc if at < there + 5 * sc
                       else 0.3 * sc if at > whole - 2 * sc else 1.3 * sc)
    total = s[-1]
    to_trochlea = s[np.argmin(np.linalg.norm(path - trochlea, axis=1))]
    belly_start = to_trochlea + 10 * sc
    # the reflected tendon a flat band where it passes under the superior rectus (3.5 to 13 mm from its insertion)
    # and on to within a few millimetres of the trochlea, round only in it
    flat = min(14 * sc, to_trochlea - 4 * sc)
    at = [0, 0.4 * sc, 3 * sc, 7 * sc, flat, to_trochlea - 2.5 * sc, to_trochlea, belly_start, belly_start + 4 * sc,
          0.5 * (belly_start + total), total - 3 * sc, total]
    width = profile(s, at, [10.0, 9.4, 6.5, 3.6, 3.2, 2.6, 1.8, 1.8, 3.6, 4.6, 3.4, 2.4]) * sc
    thick = profile(s, at, [0.03, 0.2, 0.35, 0.45, 0.5, 0.7, 1.4, 1.6, 3.0, 3.9, 2.8, 1.8]) * sc
    p = profile(s, at, [1.6, 1.6, 1.7, 1.8, 1.8, 1.9, 2.1, 2.2, 2.3, 2.3, 2.3, 2.2])
    end = dome(s, total, 1.8 * sc)
    width, thick = width * end, thick * end
    path = clear_of_globe(path, thick, R, 0.04 * sc)
    return sweep(path, width, thick, thickness_way(path, A, R), p=p, hug=hugging(path, R, sc),
                 back=insertion_curve(s, sc), seat=R + BED * sc)


def inferior_oblique(R, sc, O, I, A):
    """From the orbit's floor behind its rim, under the inferior rectus and around the eyeball to its insertion
    below the lateral rectus, by a short tendon thinning to its insertion, its edges thinning to nothing; its belly
    ending rounded at its origin."""
    I = unit(I) * (R + 0.3 * sc)
    path, s = stepped(wrap_path(I, O, R + 0.3 * sc), 6 * sc, sc, coarse=1.0)
    total = s[-1]
    at = [0, 0.4 * sc, 2.5 * sc, 5 * sc, 0.45 * total, total - 3 * sc, total]
    width = profile(s, at, [9.0, 8.6, 7.6, 6.6, 6.0, 4.4, 2.8]) * sc
    thick = profile(s, at, [0.03, 0.26, 0.8, 1.6, 2.0, 1.6, 1.0]) * sc
    p = profile(s, at, [1.7, 1.7, 1.9, 2.2, 2.3, 2.3, 2.2])
    end = dome(s, total, 1.8 * sc)
    width, thick = width * end, thick * end
    path = clear_of_globe(path, thick, R, 0.04 * sc)
    return sweep(path, width, thick, thickness_way(path, A, R), p=p, hug=hugging(path, R, sc),
                 back=insertion_curve(s, sc, deep=0.7), seat=R + BED * sc)


def even_out(v, v0, sc, n=SECTION, reach=2.0, anchor=None):
    """A muscle's moves since it was swept (v now, v0 as swept: an end point, rings of n points, an end point) made
    smooth along it, so that it bends over what it crosses in an even rise rather than a step: each ring's move as a
    whole widened to the largest within `reach` mm along the muscle, then blurred over half that (so it keeps nearly
    all of what clears the other); how a ring was pressed out of its shape (by the optic nerve, the eyeball) blurred
    over 0.6 mm along the muscle and a little around it; the end points moved with their rings; with `anchor`, no
    move as a whole at the insertion, whole from `anchor` mm along."""
    rings, rings0 = v[1:-1].reshape(-1, n, 3), v0[1:-1].reshape(-1, n, 3)
    move = rings - rings0
    whole = move.mean(1)
    shape = move - whole[:, None]
    first, last = v[0] - v0[0] - whole[0], v[-1] - v0[-1] - whole[-1]
    s = np.r_[0, np.cumsum(np.linalg.norm(np.diff(rings0.mean(1), axis=0), axis=1))]
    gap = np.abs(s[:, None] - s[None, :])
    size = np.linalg.norm(whole, axis=1)
    wide = whole[np.argmax(np.where(gap <= reach * sc, size[None, :], -1.0), axis=1)]
    g = np.exp(-0.5 * (gap / (0.5 * reach * sc)) ** 2)
    whole = (g / g.sum(1, keepdims=True)) @ wide
    if anchor is not None:
        whole = whole * smooth(0, anchor, s)[:, None]
    g = np.exp(-0.5 * (gap / (0.6 * sc)) ** 2)
    shape = np.einsum("ik,kjc->ijc", g / g.sum(1, keepdims=True), shape)
    shape = 0.5 * shape + 0.25 * (np.roll(shape, 1, axis=1) + np.roll(shape, -1, axis=1))
    v[1:-1] = (rings0 + whole[:, None] + shape).reshape(-1, 3)
    v[0] = v0[0] + whole[0] + first
    v[-1] = v0[-1] + whole[-1] + last


def drape_over(v, inner, clearance, sc, n=SECTION, reach=1.0, radial=None, cap=3.0, rounds=12):
    """A muscle lying on the eyeball (a sweep: an end point, rings of n points, an end point) laid over another
    that passes under it on the eyeball (inner: its points), as a tendon drapes over what crosses under it: each
    column of its section (a point on its top and the one under it on its underside) lifted along its radius until
    its underside clears what lies under it there (the inner's points within `reach` mm of its direction, about the
    widest gap between two columns, so nothing of the other comes up between them; nearer the eyeball's centre than
    `radial`) by `clearance`, at most `cap` mm (the inferior oblique under the inferior rectus's belly needs two); then the lift spread to its neighbours along
    the muscle and around it, never below what a column needs, so it rises over the other in a swell, and where
    nothing lies under it the muscle stays on the sclera (moving whole sections, by what the deepest point of each
    needed, lifted a tendon's whole width off the sclera where only its edge crossed the other: a curled slab).
    How many sections moved."""
    rings = v[1:-1].reshape(-1, n, 3)
    k = len(rings)
    pts = inner if radial is None else inner[np.linalg.norm(inner, axis=1) < radial]
    if not len(pts):
        return 0
    h = np.linalg.norm(pts, axis=1)
    r = np.linalg.norm(rings, axis=2)
    d = rings / r[..., None]
    tree = cKDTree(pts / h[:, None])
    hits = tree.query_ball_point(d.reshape(-1, 3), reach * sc / r.mean())
    top = np.array([h[u].max() if u else -np.inf for u in hits]).reshape(k, n)
    partner = n - 1 - np.arange(n)                     # the point across the section's thickness from each
    top = np.maximum(top, top[:, partner])
    under = np.minimum(r, r[:, partner])
    need = np.clip(np.where(np.isfinite(top), top + clearance - under, 0.0), 0.0, cap * sc)
    lift = need.copy()
    for _ in range(rounds):
        along = lift.copy()
        along[1:-1] = 0.5 * lift[1:-1] + 0.25 * (lift[:-2] + lift[2:])
        around = 0.5 * along + 0.25 * (np.roll(along, 1, axis=1) + np.roll(along, -1, axis=1))
        lift = np.maximum(need, around)
    rings += d * lift[..., None]
    v[0] += unit(v[0]) * lift[0].mean()
    v[-1] += unit(v[-1]) * lift[-1].mean()
    return int((lift.max(1) > 1e-6).sum())


def vertex_normals(v, f):
    n = np.zeros_like(v)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    for i in range(3):
        np.add.at(n, f[:, i], fn)
    return unit(n)


def lift_off(v, pts, nrm, clearance, reach=3.0, n=SECTION, rounds=12, dense=4, radial=None, hold=(4.0, 8.0), limit=None, spent=None,
             globe=None, anchor=None):
    """A muscle (a sweep from its insertion to its origin: an end point first and last, rings of n points between)
    moved off a surface (pts, nrm: its points and outward normals) a section at a time: each ring (checked at
    `dense` points along each of its edges and at `dense` steps toward the next ring, so nothing thin passes between
    its points) moved as one, along the mean normal of what it meets, by as much as its deepest point needs, the
    moves eased along the muscle so that it bends over what it crosses rather than folding into it; with `radial`
    (a distance from the eyeball's centre, the origin), where it crosses something lying on the eyeball nearer than
    that, lifted away from the centre until clear of what lies under it there, however deep it went; with `limit`,
    each ring moved no farther than that in all (`spent`: its moves so far, kept by the caller across calls), and
    only where what it meets lies on one side of it (their normals agree), so that it is nudged off a wall but left
    where it is caught between two; with `globe` (a distance from the eyeball's centre), never moved into the
    eyeball: a move that would carry a ring under it loses its part toward the centre and then as much of the rest
    as it needs (so a muscle caught between a wall and the eyeball is left there); the origin held where it is
    (`hold`: mm from it where the moves start and are whole), and with `anchor` the insertion too (no move at it,
    whole moves from `anchor` mm along: a tendon stays where it is inserted on the sclera); how many rings moved."""
    rings = v[1:-1].reshape(-1, n, 3)
    k = len(rings)
    t = np.arange(dense) / dense
    # each check point's ring: the nearer of the two it lies between
    owner = np.minimum(np.floor(np.arange(k)[:, None] + t[None, :] + 0.5), k - 1).astype(int).ravel()
    centres = rings.mean(1)
    from_origin = np.r_[np.cumsum(np.linalg.norm(np.diff(centres[::-1], axis=0), axis=1))[::-1], 0.0]
    weight = smooth(hold[0], hold[1], from_origin)
    if anchor is not None:
        weight = weight * smooth(0, anchor, from_origin[0] - from_origin)
    if radial is not None:
        # what lies on the eyeball under it: the other's points nearer its centre than `radial`
        heights = np.linalg.norm(pts, axis=1)
        pts = pts[heights < radial]
        heights = heights[heights < radial]
        if not len(pts):
            return 0
        tree = cKDTree(pts / heights[:, None])
    else:
        tree = cKDTree(pts)
    moved = np.zeros(k, bool)
    total = spent if spent is not None else np.zeros((k, 3))
    for _ in range(rounds):
        nxt = np.vstack([rings[1:], rings[-1:]])
        between = rings[:, None] + (nxt - rings)[:, None] * t[None, :, None, None]
        around = between[:, :, :, None] + (np.roll(between, -1, axis=2) - between)[:, :, :, None] * t[None, None, None, :, None]
        flat = around.reshape(-1, 3)
        if radial is not None:
            r = np.linalg.norm(flat, axis=1)
            under = tree.query_ball_point(flat / r[:, None], 0.6 / r.mean())
            top = np.array([heights[u].max() if u else -np.inf for u in under])
            need = np.where(r < radial, top + clearance - r, 0.0).reshape(k * dense, -1)
            normal = (flat / r[:, None]).reshape(k * dense, -1, 3)
        else:
            d, i = tree.query(flat)
            depth = np.einsum("ij,ij->i", flat - pts[i], nrm[i])
            need = np.where(d < reach, clearance - depth, 0.0).reshape(k * dense, -1)
            normal = nrm[i].reshape(k * dense, -1, 3)
        worst = np.zeros(k)
        np.maximum.at(worst, owner, need.max(1))
        way = np.zeros((k, 3))
        np.add.at(way, owner, np.where((need > 0)[..., None], normal, 0.0).sum(1))
        if limit is not None:
            # one-sided only: the normals of what a ring meets agree when it lies against one wall, cancel between two
            count = np.zeros(k)
            np.add.at(count, owner, (need > 0).sum(1))
            worst = np.where(np.linalg.norm(way, axis=1) >= 0.6 * np.maximum(count, 1), worst, 0.0)
        worst *= weight
        if worst.max() <= 1e-3:
            break
        size = np.linalg.norm(way, axis=1)
        go = (worst > 0) & (size > 1e-9)
        push = np.where(go[:, None], way / np.maximum(size, 1e-9)[:, None] * worst[:, None], 0.0)
        for _ in range(4):
            eased = push.copy()
            eased[1:-1] = 0.25 * push[:-2] + 0.5 * push[1:-1] + 0.25 * push[2:]
            push = np.where((np.linalg.norm(eased, axis=1) > np.linalg.norm(push, axis=1))[:, None], eased, push)
        push *= weight[:, None]
        if globe is not None:
            for i in np.where(np.linalg.norm(push, axis=1) > 1e-9)[0]:
                floor = min(globe, np.linalg.norm(rings[i], axis=1).min())   # one already lower is not made lower
                if np.linalg.norm(rings[i] + push[i], axis=1).min() >= floor - 1e-6:
                    continue
                out = unit(rings[i].mean(0))
                p = push[i] - out * min(float(push[i] @ out), 0.0)
                for share in (1.0, 0.5, 0.25, 0.0):
                    if np.linalg.norm(rings[i] + share * p, axis=1).min() >= floor - 1e-6:
                        break
                push[i] = share * p
        if limit is not None:
            # no ring farther than `limit` from where it began
            after = total + push
            size = np.linalg.norm(after, axis=1)
            after *= np.minimum(1.0, limit / np.maximum(size, 1e-12))[:, None]
            push = after - total
            total[:] = after
        rings += push[:, None, :]
        v[0] += push[0]
        v[-1] += push[-1]
        moved |= np.linalg.norm(push, axis=1) > 1e-9
    return int(moved.sum())


def tube_way(v, centre, radius, clearance):
    """v's points within a tube (centre (k, 3) its middle line, radius (k,) its radius) moved out of it."""
    seg = centre[1:] - centre[:-1]
    best = np.full(len(v), np.inf)
    push = np.zeros_like(v)
    for k in range(len(seg)):
        t = np.clip(((v - centre[k]) @ seg[k]) / max(seg[k] @ seg[k], 1e-12), 0, 1)
        foot = centre[k] + t[:, None] * seg[k]
        off = v - foot
        d = np.linalg.norm(off, axis=1)
        need = radius[k] + (radius[k + 1] - radius[k]) * t + clearance
        better = d < best
        best = np.where(better, d, best)
        push = np.where(better[:, None], unit(off) * np.maximum(need - d, 0)[:, None], push)
    v += push
    return int((np.linalg.norm(push, axis=1) > 0).sum())


# MARK: the atlas

def drape(v, f, muscles, R, sc, reach=1.4, gap=0.06, rounds=8):
    """The bulbar conjunctiva (v, f, in the eye's frame, mm) laid over the muscles where they pass under it, as the
    film lies over the recti's tendons: each point lifted along its radius to `gap` over the highest muscle point
    within `reach` of it (as far as a point of a triangle lies from that triangle's farthest corner, so no
    tendon's edge comes up through a triangle between them), then the lift spread to its neighbours, never below
    what a point needs, so the film rises over a tendon in a gentle swell rather than a step."""
    pts = np.vstack(muscles)
    pts = pts[np.linalg.norm(pts, axis=1) < R + 2.5 * sc]
    if not len(pts):
        return v
    rv = np.linalg.norm(v, axis=1)
    d = v / rv[:, None]
    tree = cKDTree(unit(pts) * rv.mean())
    need = np.zeros(len(v))
    for i, hits in enumerate(tree.query_ball_point(d * rv.mean(), reach * sc)):
        if hits:
            need[i] = max(0.0, float(np.linalg.norm(pts[hits], axis=1).max()) + gap * sc - rv[i])
    e = np.vstack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.unique(np.sort(e, axis=1), axis=0)
    deg = np.bincount(e.ravel(), minlength=len(v)).astype(float)
    lift = need.copy()
    for _ in range(rounds):
        total = np.zeros(len(v))
        np.add.at(total, e[:, 0], lift[e[:, 1]])
        np.add.at(total, e[:, 1], lift[e[:, 0]])
        lift = np.maximum(need, 0.5 * lift + 0.5 * total / np.maximum(deg, 1))
    return v + d * lift[:, None]


def side_of(node):
    return "R" if node.endswith("_R") or "_right" in node else "L"


def key_of(node):
    name = re.sub(r"^VH_[MF]_", "", node)
    return re.sub(r"_(R|L)$|(right|left)_", "", name)


def sphere_fit(p):
    A = np.c_[2 * p, np.ones(len(p))]
    x = np.linalg.lstsq(A, (p ** 2).sum(1), rcond=None)[0]
    return x[:3], float(np.sqrt(x[3] + x[:3] @ x[:3]))


def remake(folder, quiet=False):
    """Remakes the eyes and their muscles in `folder`'s atlas (anatomy.json and its part files); does nothing if
    they are made already. Returns what it did."""
    from anatomy_fibres import read_part, write_part, sha256

    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []

    def rewrite(part, meshes):
        lo, hi = write_part(os.path.join(folder, part["file"]), [(np.asarray(v, np.float32), np.asarray(f, np.int64)) for v, f in meshes])
        for st, (_, f) in zip(part["structures"], meshes):
            st["triangles"] = int(len(f))
        part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
        part["sha256"] = sha256(os.path.join(folder, part["file"]))
        part["triangles"] = int(sum(st["triangles"] for st in part["structures"]))
        part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]

    for body in manifest["bodies"]:
        parts = {p["id"]: p for p in body["parts"]}
        eyes, muscles = parts.get("eyes"), parts.get("eye-muscles")
        if eyes is None or any("colour" in st for st in eyes["structures"]):
            continue
        meshes = {st["node"]: m for st, m in zip(eyes["structures"], read_part(os.path.join(folder, eyes["file"])))}
        own = {st["node"]: m for st, m in zip(muscles["structures"], read_part(os.path.join(folder, muscles["file"])))} if muscles else {}
        nerves = {}
        if "optic-nerves" in parts:
            for st, m in zip(parts["optic-nerves"]["structures"], read_part(os.path.join(folder, parts["optic-nerves"]["file"]))):
                nerves[st["node"]] = m
        bone_v, bone_n = [], []
        if "skull" in parts:
            for st, (v, f) in zip(parts["skull"]["structures"], read_part(os.path.join(folder, parts["skull"]["file"]))):
                if st.get("tissue") == "bone":
                    bone_v.append(v)
                    bone_n.append(vertex_normals(v, f))
        bone_v = np.vstack(bone_v) if bone_v else np.zeros((0, 3))
        bone_n = np.vstack(bone_n) if bone_n else np.zeros((0, 3))
        frames = {}
        for side in "RL":
            sv = next(m[0] for n, m in meshes.items() if side_of(n) == side and key_of(n) == "sclera")
            cv = next(m[0] for n, m in meshes.items() if side_of(n) == side and key_of(n) == "cornea")
            c, R = sphere_fit(sv)
            frames[side] = (c, R, cv)
        middle = 0.5 * (frames["R"][0] + frames["L"][0])
        made_eyes, made_muscles = {}, {}
        for side in "RL":
            c, R, cv = frames[side]
            a = unit(cv.mean(0) - c)
            up = unit(np.array([0, 1.0, 0]) - a[1] * a)
            nasal = np.cross(up, a)
            nasal = nasal if nasal @ (middle - c) > 0 else -nasal
            E = np.stack([nasal, up, a])
            mm = lambda v: (v - c) @ E.T * 1000                 # world (m) to the eye's frame (mm)
            world = lambda p: c + p @ E / 1000
            flip = np.linalg.det(E) < 0
            Rm = R * 1000
            sc = Rm / 12.0
            apex = float((mm(cv) @ [0, 0, 1.0]).max())
            # the optic nerve where it leaves the eye, and its middle line back to the common ring
            nerve = np.vstack([mm(m[0]) for n, m in nerves.items() if ("right" if side == "R" else "left") in n]) \
                if nerves else np.zeros((0, 3))
            leaving = nerve[np.linalg.norm(nerve, axis=1) < Rm + 3 * sc] if len(nerve) else nerve
            disc = unit(leaving.mean(0)) if len(leaving) > 3 else toward([0, 0, -1.0], [1.0, 0, 0], 0.24)
            if (disc @ [0, 0, 1.0]) > -0.7:
                disc = toward([0, 0, -1.0], [1.0, 0, 0], 0.24)
            ball = eyeball(Rm, apex, disc)
            for n, (v, f) in meshes.items():
                if side_of(n) != side:
                    continue
                k = key_of(n)
                if k not in ball:
                    raise ValueError(f"{n}: no eye structure made for it")
                bv, bf = ball[k]
                made_eyes[n] = (world(bv), bf[:, ::-1] if flip else bf)
            if not own:
                continue
            mine = {key_of(n).replace("_extraocular_muscle", ""): n for n in own if side_of(n) == side}
            far = {k: mm(own[n][0]) for k, n in mine.items()}
            tips = {k: q[np.linalg.norm(q, axis=1) > np.percentile(np.linalg.norm(q, axis=1), 96)].mean(0) for k, q in far.items()}
            ring_z = np.mean([tips[k][2] for k in RECTI])
            slab = nerve[np.abs(nerve[:, 2] - ring_z) < 2.0] if len(nerve) else nerve
            A = np.r_[slab[:, :2].mean(0), ring_z] if len(slab) > 3 else np.mean([tips[k] for k in RECTI], 0)
            centre_line, radius = [], []
            for z in np.arange(-Rm, ring_z - 1, -1.0):
                sl = nerve[np.abs(nerve[:, 2] - z) < 0.75] if len(nerve) else nerve
                if len(sl) > 3:
                    mid = sl.mean(0)
                    centre_line.append(np.r_[mid[:2], z])
                    radius.append(np.percentile(np.linalg.norm(sl[:, :2] - mid[:2], axis=1), 90))
            so = far["superior_oblique"]
            trochlea = so[so[:, 2] > np.percentile(so[:, 2], 96)].mean(0)
            hit = None
            if len(bone_v):
                near = mm(bone_v)
                keep = np.linalg.norm(near, axis=1) < 45 * sc
                # the orbit's floor under the eyeball's front, toward the nose: the highest bone there facing up
                near_n = (bone_n @ E.T)[keep]
                sel = near[keep][(np.abs(near[keep][:, 0] - 11 * sc) < 2.5 * sc) & (np.abs(near[keep][:, 2] - 5 * sc) < 2.5 * sc)
                                 & (near[keep][:, 1] < -8 * sc) & (near[keep][:, 1] > -20 * sc) & (near_n[:, 1] > 0.5)]
                if len(sel) >= 3:
                    hit = sel[sel[:, 1] > sel[:, 1].max() - 0.8 * sc].mean(0) + [0, 1.2 * sc, 0]
            io_origin = hit if hit is not None else np.array([11.0, -12.5, 5.0]) * sc
            built = {k: rectus(Rm, sc, k, A + RING * sc * np.r_[RECTI[k][0], 0], A) for k in RECTI}
            # the superior oblique from the sphenoid's body above and medial to the optic canal: between the superior
            # and the medial rectus's origins on the ring, clear of both (2.4 mm from the superior rectus's, its
            # rounded end passed into the rectus's)
            built["superior_oblique"] = superior_oblique(Rm, sc, A + 1.15 * RING * sc * np.r_[unit(np.array([0.9, 1.0])), 0]
                                                         + [0, 0, 1.5 * sc], trochlea, A)
            built["inferior_oblique"] = inferior_oblique(Rm, sc, io_origin, on_sphere(1, np.radians(128), np.radians(208)), A)
            # where one passes another the outer gives way (the superior rectus over the superior oblique's tendon,
            # the inferior oblique under the inferior rectus, the lateral rectus over the inferior oblique's
            # insertion; the superior oblique above the medial rectus; the recti where they gather at the ring),
            # a section at a time; then the optic nerve's sheath, the bone and the eyeball itself, three times over
            moved = {}
            # each ring's nudges off the bone so far, so the cap holds over all three rounds
            spent = {k: np.zeros(((len(v) - 2) // SECTION, 3)) for k, (v, f) in built.items()}
            pairs = (("superior_rectus", "superior_oblique"), ("inferior_oblique", "inferior_rectus"),
                     ("lateral_rectus", "inferior_oblique"), ("superior_oblique", "medial_rectus"),
                     ("superior_rectus", "medial_rectus"), ("inferior_rectus", "medial_rectus"),
                     ("superior_rectus", "lateral_rectus"), ("inferior_rectus", "lateral_rectus"))
            # the crossings on the eyeball, where the outer is laid over the inner once the rest has settled
            on_globe = pairs[:3]
            # (each other last: where the orbit is too tight for both, a muscle may touch the bone, never another)
            designed = {k: v.copy() for k, (v, f) in built.items()}

            def settle():
                if centre_line:
                    for k, (v, f) in built.items():
                        moved[k] = moved.get(k, 0) + tube_way(v, np.array(centre_line), np.array(radius), 0.25 * sc)
                if len(bone_v):
                    for k, (v, f) in built.items():
                        moved[k] = moved.get(k, 0) + lift_off(v, near[keep], near_n, 0.3 * sc, reach=3.0 * sc,
                                                              hold=(4 * sc, 8 * sc), limit=1.0 * sc, spent=spent[k],
                                                              globe=Rm + FLOOR * sc, anchor=2.5 * sc)
                for k, (v, f) in built.items():
                    d = np.linalg.norm(v, axis=1)
                    inside = d < Rm + FLOOR * sc
                    v[inside] *= ((Rm + FLOOR * sc) / d[inside])[:, None]
                for outer, inner in pairs:
                    if (outer, inner) in on_globe:
                        continue
                    iv, jf = built[inner]
                    moved[outer] = moved.get(outer, 0) + lift_off(built[outer][0], iv, vertex_normals(iv, jf), 0.12 * sc,
                                                                  reach=2.5 * sc, hold=(4 * sc, 8 * sc),
                                                                  globe=Rm + FLOOR * sc, anchor=2.5 * sc)

            for _ in range(3):
                settle()
            # the moves made smooth along each muscle (so it bends over what it crosses, without a step), and once
            # more what that smoothing gave back settled
            for k, (v, f) in built.items():
                even_out(v, designed[k], sc, anchor=2.5 * sc)
            settle()
            # where one crosses another on the eyeball, the outer laid over the inner, column by column
            for outer, inner in on_globe:
                moved[outer] = moved.get(outer, 0) + drape_over(built[outer][0], built[inner][0], 0.12 * sc, sc,
                                                                radial=Rm + 6 * sc)
            # each end's cap clear of the eyeball too: a wide tendon's cap is its end point joined to its last ring,
            # flat across the curve, and the middles of those spokes sag into the eyeball (a quarter of a millimetre
            # across a fan 10 mm wide), so the end point is lifted until they clear it
            for k, (v, f) in built.items():
                for pole, ring in ((0, slice(1, SECTION + 1)), (len(v) - 1, slice(len(v) - SECTION - 1, len(v) - 1))):
                    for _ in range(4):
                        need = Rm + FLOOR * sc - np.linalg.norm((v[pole] + v[ring]) / 2, axis=1)
                        if need.max() <= 1e-4:
                            break
                        v[pole] += unit(v[pole]) * 2.2 * need.max()
            # what is left inside the bone (its nearest bone point's normal facing away), checked
            deep = {}
            if len(bone_v):
                tree = cKDTree(near[keep])
                for k, (v, f) in built.items():
                    d, i = tree.query(v)
                    depth = np.einsum("ij,ij->i", v - near[keep][i], near_n[i])
                    if ((depth < -0.3 * sc) & (d < 3 * sc)).any():
                        deep[k] = int(((depth < -0.3 * sc) & (d < 3 * sc)).sum())
            for k, n in mine.items():
                v, f = built[k]
                made_muscles[n] = (world(v), f[:, ::-1] if flip else f)
            # the conjunctiva over the tendons, now they are where they end
            for n in made_eyes:
                if side_of(n) == side and key_of(n) == "bulbar_conjunctiva":
                    cv, cf = ball["bulbar_conjunctiva"]
                    cv = drape(cv, cf, [v for v, f in built.values()], Rm, sc)
                    made_eyes[n] = (world(cv), cf[:, ::-1] if flip else cf)
            said.append(f"{body['id']} {side}: radius {Rm:.2f} mm, cornea {apex:.2f} mm before its middle, optic disc "
                        f"{np.degrees(np.arccos(-disc[2])):.0f} deg off the back pole; common ring {np.round(A, 1)} mm, trochlea "
                        f"{np.round(trochlea, 1)}, inferior oblique from {np.round(io_origin, 1)}"
                        f"{'' if hit is not None else ' (no bone found: the textbook place)'}; gave way: "
                        + ", ".join(f"{k} {m}" for k, m in moved.items() if m)
                        + ("; still in the bone: " + ", ".join(f"{k} {m}" for k, m in deep.items()) if deep else ""))
        rewrite(eyes, [made_eyes[st["node"]] for st in eyes["structures"]])
        for st in eyes["structures"]:
            colour, opacity, rough = LOOK[key_of(st["node"])]
            st["colour"], st["opacity"], st["roughness"] = colour, opacity, rough
            if key_of(st["node"]) in SURFACE:
                st["surface"] = SURFACE[key_of(st["node"])]
        if muscles and made_muscles:
            rewrite(muscles, [made_muscles[st["node"]] for st in muscles["structures"]])
            for st in muscles["structures"]:
                st["group"] = ("right" if side_of(st["node"]) == "R" else "left") + " eye muscles"
            # their bundles are laid anew (tools/anatomy_fibres.py)
            fibres = muscles.pop("fibres", None)
            if fibres and os.path.exists(os.path.join(folder, fibres["file"])):
                os.remove(os.path.join(folder, fibres["file"]))
    json.dump(manifest, open(path, "w"), indent=1, ensure_ascii=False)
    if not quiet:
        for line in said:
            print("  " + line)
    return f"{len(said)} eyes made anew" if said else "the eyes made already"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(remake(sys.argv[1]))
    import anatomy_fibres
    print(f"{anatomy_fibres.annotate(sys.argv[1], quiet=True)} muscles with their bundles laid")
