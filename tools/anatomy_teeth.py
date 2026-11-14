#!/usr/bin/env python3
"""Thirty-two teeth, each one made here from its textbook description: nothing scanned, nothing imported.

The atlas's tooth rows were two fused strips (and a few crowns baked into the jaw bones), which no student can
learn the dentition from. Here every permanent tooth is built on its own from the numbers and shapes a dental
anatomy text gives it: the crown's height and widths, its incisal edge or cusps, its neck, and its root or
roots. Each is a closed surface with nothing of it inside its neighbours.

A tooth is made in its own frame, in millimetres: x towards the back of the arch (distal), y towards the lip or
cheek (labial, buccal), z towards the biting surface; the origin at the middle of its neck (the cement-enamel
line). `tooth(arch, index)` gives one (index 0 the central incisor, 7 the third molar); `set_in(...)` turns it
into the body's frame, in metres.

The sizes are the usual textbook ones for the permanent teeth (crown height, root length, the crown's greatest
width along the arch, its width at the neck, and its thickness from cheek to tongue).

  python3 tools/anatomy_teeth.py <atlas folder>       seats the thirty-two in each body's jaws (TEETH_ONLY=male)
  python3 tools/anatomy_teeth.py --sheet out.png      a picture of the sixteen kinds, to check them by eye
"""
import sys

import numpy as np

sys.dont_write_bytecode = True

#  key, name, kind, crown, root, width, width at the neck, thickness   (mm)
UPPER = [
    ("central_incisor", "central incisor", "incisor", 10.5, 13.0, 8.5, 7.0, 7.0),
    ("lateral_incisor", "lateral incisor", "incisor", 9.0, 13.0, 6.5, 5.0, 6.0),
    ("canine", "canine", "canine", 10.0, 17.0, 7.5, 5.5, 8.0),
    ("first_premolar", "first premolar", "premolar", 8.5, 14.0, 7.0, 5.0, 9.0),
    ("second_premolar", "second premolar", "premolar", 8.5, 14.0, 7.0, 5.0, 9.0),
    ("first_molar", "first molar", "molar", 7.5, 12.5, 10.0, 8.0, 11.0),
    ("second_molar", "second molar", "molar", 7.0, 11.5, 9.0, 7.0, 11.0),
    ("third_molar", "third molar", "molar", 6.5, 11.0, 8.5, 6.5, 10.0),
]
LOWER = [
    ("central_incisor", "central incisor", "incisor", 9.0, 12.5, 5.0, 3.5, 6.0),
    ("lateral_incisor", "lateral incisor", "incisor", 9.5, 14.0, 5.5, 4.0, 6.5),
    ("canine", "canine", "canine", 11.0, 16.0, 7.0, 5.5, 7.5),
    ("first_premolar", "first premolar", "premolar", 8.5, 14.0, 7.0, 5.0, 7.5),
    ("second_premolar", "second premolar", "premolar", 8.0, 14.5, 7.0, 5.0, 8.0),
    ("first_molar", "first molar", "molar", 7.5, 14.0, 11.0, 9.0, 10.5),
    ("second_molar", "second molar", "molar", 7.0, 13.0, 10.5, 8.0, 10.0),
    ("third_molar", "third molar", "molar", 7.0, 11.0, 10.0, 7.5, 9.5),
]
ARCHES = {"upper": UPPER, "lower": LOWER}
TRIANGLES = {"incisor": 1500, "canine": 1600, "premolar": 2400, "molar": 3600}


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def ease(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def shell(X, Y, a_m, a_d, b_o, b_i, p, conv=0.0, cx=0.0, cy=0.0):
    """How far outside (mm, about) a rounded outline seen from the biting side: half-widths a_m towards the
    midline and a_d away from it, b_o towards the cheek and b_i towards the tongue, squareness p (2 an oval);
    its width draws in by the share `conv` towards the tongue (or, below zero, towards the cheek)."""
    x, y = X - cx, Y - cy
    b = np.where(y >= 0, b_o, b_i)
    yy = np.abs(y) / np.maximum(b, 1e-3)
    k = (1 - np.maximum(conv, 0) * np.clip(-y / np.maximum(b_i, 1e-3), 0, 1) ** 1.5
         - np.maximum(-np.asarray(conv, float), 0) * np.clip(y / np.maximum(b_o, 1e-3), 0, 1) ** 1.5)
    a = np.where(x < 0, a_m, a_d) * k
    xx = np.abs(x) / np.maximum(a, 1e-3)
    rho = (xx ** p + yy ** p) ** (1.0 / p)
    return (rho - 1) * np.minimum(np.minimum(a_m, a_d), np.minimum(b_o, b_i))


def flare(t, tc):
    """A crown's widening from its neck (0) to its contact with the next tooth at the height tc (1)."""
    return np.sin(np.pi / 2 * np.clip(t / tc, 0, 1)) ** 0.9


def arc(t, t0, e=1.8):
    """1 up to the height t0, then curving in to 0 at the top."""
    return 1 - np.clip((t - t0) / (1 - t0), 0, 1) ** e


def taper(u, end=0.22, power=0.9, late=1.6):
    """A root's width from its neck (u = 0) to its tip (u = 1), as a share: it keeps most of its width over its
    upper half and draws in to a blunt tip."""
    return end + (1 - end) * (1 - np.clip(u, 0, 1) ** late) ** power


def closed(side, Z, R, r_end):
    """A single root's rounded tip, below its length R."""
    under = -R - Z
    return np.where(under > 0, np.sqrt(np.maximum(side + r_end, 0) ** 2 + under ** 2) - r_end, side)


def root(X, Y, Z, top, tip, a, b, end=0.36, power=0.9, curve=1.0, bow=(0.0, 0.0), p=2.0):
    """A root from `top` (x, y, z) to `tip`: half-widths a along the arch and b across it at its top, drawing in
    to the share `end` at its tip; its axis is straight for curve 1 and turns to the tip late for more (early
    for less); `bow` (x, y) bulges its middle sideways."""
    top, tip = np.asarray(top, float), np.asarray(tip, float)
    u = np.clip((top[2] - Z) / (top[2] - tip[2]), 0, 1)
    cx = top[0] + (tip[0] - top[0]) * u ** curve + bow[0] * np.sin(np.pi * u)
    cy = top[1] + (tip[1] - top[1]) * u ** curve + bow[1] * np.sin(np.pi * u)
    w = taper(u, end, power)
    rho = ((np.abs(X - cx) / (a * w)) ** p + (np.abs(Y - cy) / (b * w)) ** p) ** (1.0 / p)
    r_end = min(a, b) * end
    d = (rho - 1) * min(a, b) * w
    under = tip[2] - Z
    d = np.where(under > 0, np.sqrt((rho * r_end) ** 2 + under ** 2) - r_end, d)
    return np.maximum(d, Z - top[2])


def forked(trunk, roots, Z, zf):
    """A crown and trunk (its outline carried on downward) with the roots that leave it below the height zf:
    near the fork the roots keep inside the trunk's outline, so the wall runs on from one into the other with
    no step, and lower down they are free to spread."""
    return smin(np.maximum(trunk, zf - Z), np.maximum(roots, trunk - 0.6 * np.clip(zf - Z, 0, None)), 0.35)


def tent(X, Y, c, slope, r=0.35, sx=1.0, sy=1.0):
    """A cusp: its tip at c = (x, y, height), its sides falling away at `slope`, the tip itself rounded to r;
    sx and sy below 1 make it longer along or across the arch."""
    d = np.sqrt(((X - c[0]) * sx) ** 2 + ((Y - c[1]) * sy) ** 2 + r * r) - r
    return c[2] - slope * d


def crest(X, Y, p0, p1, h0, h1, slope, r=0.3):
    """A ridge from p0 to p1 (x, y), its crest at the heights h0 to h1, its sides falling away at `slope`."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    w = np.clip(((X - p0[0]) * dx + (Y - p0[1]) * dy) / (dx * dx + dy * dy), 0, 1)
    d = np.sqrt((X - p0[0] - w * dx) ** 2 + (Y - p0[1] - w * dy) ** 2 + r * r) - r
    return h0 + (h1 - h0) * w - slope * d


def table(parts, k=0.06):
    """A biting surface: the highest of its cusps and ridges at each point, so that where two slopes meet they
    leave a sharp groove between them (a fissure), and a pit where three or four meet."""
    top = parts[0]
    for q in parts[1:]:
        top = smax(top, q, k)
    return top


#  the incisors: where the edge lies before (+) or behind the root's line, how round the corner towards the
#  midline and the one away from it are (mm), how deep the hollow on the tongue side is, how high the contacts
#  with the neighbours lie, the edge's slope, how much narrower the tongue side is, the root tip's bend
INCISORS = {
    ("upper", 0): dict(edge=0.45, rm=0.45, rd=1.3, fossa=0.65, tcm=0.88, tcd=0.78, tilt=0.03, conv=0.30, bend=0.5),
    ("upper", 1): dict(edge=0.35, rm=0.8, rd=1.9, fossa=0.70, tcm=0.80, tcd=0.66, tilt=0.06, conv=0.32, bend=0.9),
    ("lower", 0): dict(edge=-0.45, rm=0.3, rd=0.35, fossa=0.25, tcm=0.90, tcd=0.90, tilt=0.0, conv=0.20, bend=0.2),
    ("lower", 1): dict(edge=-0.45, rm=0.35, rd=0.8, fossa=0.28, tcm=0.90, tcd=0.82, tilt=0.04, conv=0.20, bend=0.4),
}
CANINES = {
    "upper": dict(tip=0.5, xt=-0.35, sm=0.82, sd=0.88, tcm=0.70, tcd=0.56, wm=0.97, wd=1.03, fossa=0.40, conv=0.28, bend=0.9),
    "lower": dict(tip=-0.3, xt=-0.45, sm=0.66, sd=0.80, tcm=0.80, tcd=0.60, wm=0.90, wd=1.08, fossa=0.18, conv=0.22, bend=0.6),
}


def incisor(arch, i, X, Y, Z):
    """A chisel: seen from the lip a crown widening from the neck to its contacts near the edge, the corner
    towards the midline sharp and the other rounded; seen from the side a wedge, full at the neck on the lip
    side, with the cingulum's bulge on the tongue side and above it the hollow between the two marginal ridges;
    one root, a cone (flattened from side to side in the lower ones)."""
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    q = INCISORS[arch, i]
    a0, b0 = Wc / 2, 0.93 * B / 2
    t, u = np.clip(Z / H, 0, 1), np.clip(-Z / R, 0, 1)
    w, crown = taper(u), Z >= 0
    am = np.where(crown, a0 + (W / 2 - a0) * flare(t, q["tcm"]), a0 * w)
    ad = np.where(crown, a0 + (W / 2 - a0) * flare(t, q["tcd"]), a0 * w)
    ye = q["edge"]
    lab = np.where(t < 0.18, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.18), ye + 0.5 + (B / 2 - ye - 0.5) * arc(t, 0.18, 1.7))
    cing = 0.97 * B / 2
    s = np.clip((t - 0.2) / 0.8, 0, 1)
    rid = np.where(t < 0.2, b0 + (cing - b0) * np.sin(np.pi / 2 * t / 0.2), cing + (0.5 - ye - cing) * s ** 0.85)
    g = np.clip(1 - (np.abs(X) / (0.46 * (am + ad))) ** 2, 0, 1) ** 2
    lin = rid - q["fossa"] * np.sin(np.pi * s) ** 2 * g
    lab, lin = np.where(crown, lab, b0 * w), np.where(crown, lin, b0 * w)
    p = np.where(crown, 2.15 + 1.2 * ease(t / 0.7), 2.15)
    conv = np.where(crown, q["conv"] * (1 - 0.8 * ease((t - 0.3) / 0.6)), q["conv"] * (1 - 0.5 * u))
    side = shell(X, Y, am, ad, lab, np.maximum(lin, 0.3), p, conv, cx=q["bend"] * u ** 2.2)
    side = closed(side, Z, R, 0.22 * min(a0, b0))
    e, rm, rd = 0.99 * W / 2, q["rm"], q["rd"]
    um, ud = np.clip(-X - (e - rm), 0, rm), np.clip(X - (e - rd), 0, rd)
    top = H - (rm - np.sqrt(rm * rm - um * um)) - (rd - np.sqrt(rd * rd - ud * ud)) - q["tilt"] * (X + W / 2)
    return smax(side, Z - top, 0.22)


def canine(arch, i, X, Y, Z):
    """One pointed cusp, its tip a little towards the midline, its two ridges running down to the contacts (the
    hinder one longer and lower); thick from lip to tongue, with a strong cingulum and a ridge down the tongue
    side between two shallow hollows; the longest root of all, oval."""
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    q = CANINES[arch]
    a0, b0 = Wc / 2, 0.93 * B / 2
    t, u = np.clip(Z / H, 0, 1), np.clip(-Z / R, 0, 1)
    w, crown = taper(u), Z >= 0
    am = (a0 + (q["wm"] * W / 2 - a0) * flare(t, q["tcm"])) * (1 - 0.10 * ease((t - q["tcm"]) / (1 - q["tcm"])))
    ad = (a0 + (q["wd"] * W / 2 - a0) * flare(t, q["tcd"])) * (1 - 0.10 * ease((t - q["tcd"]) / (1 - q["tcd"])))
    am, ad = np.where(crown, am, a0 * w), np.where(crown, ad, a0 * w)
    ty = q["tip"]
    lab = np.where(t < 0.22, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.22), ty + 0.75 + (B / 2 - ty - 0.75) * arc(t, 0.22, 1.9))
    cing = 0.97 * B / 2
    s = np.clip((t - 0.22) / 0.78, 0, 1)
    rid = np.where(t < 0.22, b0 + (cing - b0) * np.sin(np.pi / 2 * t / 0.22), cing + (0.75 - ty - cing) * s ** 0.9)
    g = np.sin(np.pi * np.clip(np.abs(X) / (0.45 * (am + ad)), 0, 1)) ** 2
    lin = rid - q["fossa"] * np.sin(np.pi * s) ** 2 * g
    lab, lin = np.where(crown, lab, b0 * w), np.where(crown, lin, b0 * w)
    p = np.where(crown, 2.0 + 0.5 * ease(t / 0.6), 2.0)
    conv = np.where(crown, q["conv"] * (1 - 0.6 * ease((t - 0.3) / 0.6)), q["conv"] * (1 - 0.5 * u))
    side = shell(X, Y, am, ad, lab, np.maximum(lin, 0.3), p, conv, cx=q["bend"] * u ** 2.2)
    side = closed(side, Z, R, 0.22 * min(a0, b0))
    r = 0.4
    top = H + r - np.sqrt((np.where(X < q["xt"], q["sm"], q["sd"]) * (X - q["xt"])) ** 2 + r * r) - 0.05 * (Y - ty) ** 2
    return smax(side, Z - top, 0.25)


def premolar(arch, i, X, Y, Z):
    """Two cusps (the lower second: three), cheek side and tongue side, with the groove between them running
    along the arch from one marginal ridge to the other. Upper: the two nearly alike (the first's tongue-side
    cusp a millimetre lower), the crown an oval set across the arch; the first has two roots. Lower first: a
    big pointed cheek-side cusp over the root's line and a tongue-side nub far below it, joined by a ridge
    with a pit on either side, the whole crown leaning to the tongue. Lower second: squarer, a cheek-side cusp
    and two tongue-side ones parted by a Y of grooves."""
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    up = arch == "upper"
    a0, b0 = Wc / 2, 0.86 * B / 2
    t, u = np.clip(Z / H, 0, 1), np.clip(-Z / R, 0, 1)
    w, crown = taper(u), Z >= 0
    xm = W / 2 - 0.95                                       # where the marginal ridges run
    if up:
        cb, cl = (-0.2, 0.27 * B, H), (-0.5, -0.26 * B, H - (1.0 if i == 3 else 0.35))
        lean, conv, p0 = 0.0, 0.16, 2.25
        parts = [tent(X, Y, cb, 0.8, 0.4, sx=0.65), tent(X, Y, cl, 0.8, 0.45, sx=0.65)]
        hb = hl = H - 1.5
        yb, yl = cb[1] + 1.3, -cl[1] + 1.15
    elif i == 3:
        cb, cl = (-0.1, 0.9, H), (-0.4, -2.5, H - 3.0)
        lean, conv, p0 = 0.7, 0.30, 2.2
        parts = [tent(X, Y, cb, 0.95, 0.4, sx=0.75), crest(X, Y, cb[:2], cl[:2], H - 0.3, H - 2.9, 1.0),
                 tent(X, Y, cl, 0.9, 0.4)]
        hb, hl = H - 2.0, H - 3.2
        yb, yl = cb[1] + 1.3, -cl[1] + 1.0
    else:
        cb, cm, cd = (0.0, 1.7, H), (-1.3, -2.4, H - 1.2), (1.6, -2.5, H - 1.7)
        lean, conv, p0 = 0.3, 0.05, 2.5
        parts = [tent(X, Y, cb, 0.8, 0.45, sx=0.7), tent(X, Y, cm, 0.8, 0.4), tent(X, Y, cd, 0.8, 0.4)]
        hb, hl = H - 1.6, H - 2.0
        yb, yl = cb[1] + 1.35, 2.45 + 1.1
    for sgn in (-1, 1):
        parts.append(crest(X, Y, (sgn * xm, yb - 1.9), (sgn * xm, -(yl - 1.6)), hb, hl, 0.9))
    cy = np.where(crown, -lean * t, 0.0)
    bo1, bi1 = yb + lean, yl - lean
    lab = np.where(t < 0.25, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.25), bo1 + (B / 2 - bo1) * arc(t, 0.25, 1.8))
    lin = np.where(t < 0.5, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.5), bi1 + (B / 2 - bi1) * arc(t, 0.5, 1.8))
    am = (a0 + (W / 2 - a0) * flare(t, 0.68)) * (1 - 0.10 * ease((t - 0.68) / 0.32))
    ad = (a0 + (W / 2 - a0) * flare(t, 0.60)) * (1 - 0.10 * ease((t - 0.60) / 0.40))
    two = up and i == 3
    if two:                                                 # a trunk, then a cheek-side and a palate-side root
        w = 1 - 0.12 * np.clip(-Z / 5.5, 0, 1)
    am, ad = np.where(crown, am, a0 * w), np.where(crown, ad, a0 * w)
    lab, lin = np.where(crown, lab, b0 * w), np.where(crown, lin, b0 * w)
    into = ease(t / 0.2)                                    # the neck's outline passing into the crown's
    side = shell(X, Y, am, ad, lab, lin, 2.0 + (p0 - 2.0) * into, conv * into,
                 cx=0.0 if two else 0.7 * u ** 2.2, cy=cy)
    if two:
        zf = -5.5
        rb = root(X, Y, Z, (0, 1.85, zf + 1.5), (0.5, 2.4, -R), 1.9, 1.75, curve=1.6)
        rl = root(X, Y, Z, (0, -1.85, zf + 1.5), (0.5, -2.3, -R + 0.8), 1.85, 1.7, curve=1.6)
        side = forked(side, smin(rb, rl, 0.5), Z, zf)
    else:
        side = closed(side, Z, R, 0.22 * min(a0, b0))
    return smax(side, Z - table(parts), 0.2)


def molar(arch, i, X, Y, Z):
    """Upper: a crown wider across the arch than along it, its outline a rhomboid; four cusps, the big one on
    the palate side in front joined to the hinder cheek-side one by the oblique ridge, the hinder palate-side
    one small (smaller still in the second and third); a groove running out between the cusps on to the cheek
    side and one on to the palate side; three roots, two on the cheek side and the longest on the palate side,
    spread in the first, closer in the second, run together in the third. Lower: a crown longer along the
    arch; the first with five cusps (three on the cheek side) parted by a Y of grooves, the second and third
    with four parted by a cross; the tongue-side cusps the sharper; the crown leaning to the tongue; two roots
    flattened from front to back, one in front and one behind."""
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    up, n = arch == "upper", i - 5
    a0, b0 = Wc / 2, 0.90 * B / 2
    t = np.clip(Z / H, 0, 1)
    crown = Z >= 0
    fx, fy = W / (10.0 if up else 11.0 if n == 0 else 10.5), B / (11.0 if up else 10.5 if n == 0 else 10.0)
    at = lambda x, y, h: (x * fx, y * fy, h)
    if up:
        mb, db, ml, dl = at(-2.45, 2.85, H - 0.35), at(2.35, 2.70, H - 0.8), at(-1.9, -2.55, H), at(3.0, -2.9, H - 1.7 - 0.55 * n)
        parts = [tent(X, Y, mb, 0.8, 0.6, sx=0.55), tent(X, Y, db, 0.8, 0.6, sx=0.55), tent(X, Y, ml, 0.72, 0.7, sx=0.6),
                 tent(X, Y, dl, 0.85, 0.5, sx=0.7), crest(X, Y, ml[:2], db[:2], H - 1.25, H - 1.35, 0.8)]
        lean, conv, shear, p0, narrow = 0.0, (-0.04, 0.10, 0.20)[n], 0.55, 2.9 - 0.2 * n, 0.03 * n
        yb, yl = 2.85 * fy + 1.45, 2.9 * fy + 1.35
        grooves = [(1, -0.05, 0.30), (-1, 1.3 * fx, 0.28 - 0.08 * n)]
    elif n == 0:
        mb, db, d_ = at(-3.35, 2.35, H - 0.5), at(0.35, 2.55, H - 0.7), at(3.75, 1.2, H - 1.7)
        ml, dl = at(-3.0, -2.6, H), at(1.9, -2.65, H - 0.25)
        parts = [tent(X, Y, mb, 0.75, 0.7, sx=0.55), tent(X, Y, db, 0.75, 0.7, sx=0.55), tent(X, Y, d_, 0.8, 0.6, sx=0.7),
                 tent(X, Y, ml, 0.85, 0.45, sx=0.6), tent(X, Y, dl, 0.85, 0.45, sx=0.6)]
        lean, conv, shear, p0, narrow = 0.5, 0.10, 0.0, 3.0, 0.12
        yb, yl = 2.5 * fy + 1.55, 2.6 * fy + 1.2
        grooves = [(1, -1.5 * fx, 0.30), (1, 2.3 * fx, 0.25), (-1, -0.5 * fx, 0.25)]
    else:
        mb, db, ml, dl = at(-2.6, 2.3, H - 0.4), at(2.5, 2.25, H - 0.6), at(-2.6, -2.5, H), at(2.5, -2.5, H - 0.3)
        parts = [tent(X, Y, mb, 0.75, 0.7, sx=0.55), tent(X, Y, db, 0.75, 0.7, sx=0.55),
                 tent(X, Y, ml, 0.85, 0.45, sx=0.6), tent(X, Y, dl, 0.85, 0.45, sx=0.6)]
        lean, conv, shear, p0, narrow = 0.5, 0.10, 0.0, 3.0 - 0.25 * (n - 1), 0.06 + 0.05 * (n - 1)
        yb, yl = 2.4 * fy + 1.55, 2.5 * fy + 1.2
        grooves = [(1, 0.0, 0.30), (-1, 0.0, 0.22)]
    xm = W / 2 - 1.05
    for sgn in (-1, 1):
        parts.append(crest(X, Y, (sgn * xm, 2.5 * fy), (sgn * xm, -2.5 * fy), H - 1.55, H - 1.55, 0.9))
    cy = np.where(crown, -lean * t, 0.0)
    bo1, bi1 = yb + lean, yl - lean
    lab = np.where(t < 0.25, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.25), bo1 + (B / 2 - bo1) * arc(t, 0.25, 1.8))
    lin = np.where(t < 0.5, b0 + (B / 2 - b0) * np.sin(np.pi / 2 * t / 0.5), bi1 + (B / 2 - bi1) * arc(t, 0.5, 1.8))
    am = (a0 + (W / 2 - a0) * flare(t, 0.72)) * (1 - 0.07 * ease((t - 0.72) / 0.28))
    ad = (a0 + (W / 2 - a0) * flare(t, 0.60)) * (1 - 0.07 * ease((t - 0.60) / 0.40))
    wt = 1 - 0.06 * np.clip(-Z / 4.0, 0, 1)                 # the trunk the roots leave from
    am, ad = np.where(crown, am, a0 * wt), np.where(crown, ad, a0 * wt)
    lab, lin = np.where(crown, lab, b0 * wt), np.where(crown, lin, b0 * wt)
    thin = 1 - narrow * np.clip(X / (W / 2), 0, 1) ** 1.5 * ease(t / 0.3)      # narrower across at its hind end
    xs = X + shear * (Y / (B / 2)) * ease(t / 0.4)          # the upper crown's rhomboid
    into = ease(t / 0.2)                                    # the neck's outline passing into the crown's
    side = shell(xs, Y, am, ad, lab * thin, lin * thin, 2.6 + (p0 - 2.6) * into, conv * into, cy=cy)
    if up and n == 0:                                       # the first upper molar's fifth, small cusp (Carabelli's)
        bump = np.sqrt((X + 2.3 * fx) ** 2 + (Y + B / 2 - 0.85) ** 2 + (Z - 0.52 * H) ** 2) - 1.2
        side = smin(side, bump, 0.6)
    for sgn, xg, depth in grooves:
        side = side + depth * np.exp(-((X - xg) / 0.8) ** 2) * ease((t - 0.35) / 0.5) * (sgn * Y > 0)
    if up:
        g, back, zf = (1.0, 0.82, 0.55)[n], (0.3, 1.1, 1.9)[n], -4.0
        r1 = root(X, Y, Z, (-2.0 * g, 2.2 * g, -2.4), (-2.3 * g + back + 0.8, 3.3 * g, -R), 1.7, 2.5, curve=1.7, bow=(-0.4, 0))
        r2 = root(X, Y, Z, (2.1 * g, 2.3 * g, -2.4), (2.7 * g + back, 2.8 * g, -R + 1.0), 1.6, 2.1, curve=1.3)
        r3 = root(X, Y, Z, (0.1, -2.5 * g, -2.4), (0.3 + 0.6 * back, -5.0 * g + 0.6, -R - 1.0), 2.5, 2.2, curve=0.85)
        roots = smin(smin(r1, r2, 0.5), r3, 0.5)
    else:
        g, back, zf = (1.0, 0.8, 0.5)[n], (0.4, 1.3, 2.2)[n], -3.0
        r1 = root(X, Y, Z, (-2.75 * g * fx, 0, -1.8), (-2.9 * g * fx + 0.8 * back, 0, -R), 2.1, 0.95 * b0, curve=1.5, bow=(-0.5, 0), p=2.5)
        r2 = root(X, Y, Z, (2.75 * g * fx, 0, -1.8), (3.6 * g * fx + back, 0, -R + 1.0), 1.9, 0.80 * b0, curve=1.2, p=2.3)
        roots = smin(r1, r2, 0.5)
    body = forked(side, roots, Z, zf)
    return smax(body, Z - table(parts), 0.2)


def field(arch, i, X, Y, Z):
    """Negative inside tooth i of the arch (about the distance to its surface in mm)."""
    kind = ARCHES[arch][i][2]
    return {"incisor": incisor, "canine": canine, "premolar": premolar, "molar": molar}[kind](arch, i, X, Y, Z)


def clip(v, f, s):
    """The part of a mesh where s, a number at each vertex, is above zero: its triangles cut along s = 0."""
    pos = s > 0
    n = pos[f].sum(1)
    out = [f[n == 3]]
    cut = f[(n == 1) | (n == 2)]
    if len(cut):
        one = pos[cut].sum(1) == 1
        odd = np.where(one[:, None], pos[cut], ~pos[cut])       # the corner alone on its side, put first
        k = np.argmax(odd, axis=1)
        r = np.arange(len(cut))
        a, b, c = cut[r, k], cut[r, (k + 1) % 3], cut[r, (k + 2) % 3]
        uniq, inv = np.unique(np.sort(np.concatenate([np.c_[a, b], np.c_[a, c]]), axis=1), axis=0, return_inverse=True)
        inv = inv.ravel()
        t = s[uniq[:, 0]] / (s[uniq[:, 0]] - s[uniq[:, 1]])
        ab, ac = len(v) + inv[:len(cut)], len(v) + inv[len(cut):]
        v = np.concatenate([v, v[uniq[:, 0]] + t[:, None] * (v[uniq[:, 1]] - v[uniq[:, 0]])])
        out += [np.c_[a, ab, ac][one], np.c_[ab, b, c][~one], np.c_[ab, c, ac][~one]]
    f = np.concatenate(out)
    used = np.unique(f)
    remap = np.full(len(v), -1, np.int64)
    remap[used] = np.arange(len(used))
    return v[used], remap[f]


def taubin(v, f, rounds=6, lam=0.5, mu=-0.53):
    n = len(v)
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]], f[:, [1, 0]], f[:, [2, 1]], f[:, [0, 2]]])
    deg = np.bincount(e[:, 0], minlength=n).astype(float)[:, None]
    for _ in range(rounds):
        for w in (lam, mu):
            s = np.zeros_like(v)
            np.add.at(s, e[:, 0], v[e[:, 1]])
            v = v + w * (s / np.maximum(deg, 1) - v)
    return v


_cache = {}


def tooth(arch, i, h=0.14, triangles=None):
    """Tooth i of the arch in its own frame (mm): vertices, triangles (outward)."""
    if (arch, i, h, triangles) in _cache:
        return _cache[arch, i, h, triangles]
    from skimage import measure
    key, _, kind, H, R, W, Wc, B = ARCHES[arch][i]
    lo = np.array([-W / 2 - 2.2, -B / 2 - 3.2, -R - 2.6])
    hi = np.array([W / 2 + 3.0, B / 2 + 2.2, H + 1.4])
    ax = [np.arange(lo[k], hi[k] + h, h) for k in range(3)]
    X, Y, Z = np.meshgrid(*ax, indexing="ij")
    F = field(arch, i, X, Y, Z)
    v, f, _, _ = measure.marching_cubes(F, 0.0, spacing=(h, h, h))
    v = v + lo
    f = f[:, ::-1].astype(np.int64)                     # skimage winds them inward for a field negative inside
    if np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum() < 0:
        f = f[:, ::-1]
    v = taubin(v, f, 4)
    import fast_simplification
    target = triangles or TRIANGLES[kind]
    q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=1 - target / len(f), agg=4)
    used = np.unique(g)
    remap = np.full(len(q), -1, np.int64)
    remap[used] = np.arange(len(used))
    _cache[arch, i, h, triangles] = out = (q[used].astype(np.float64), remap[g].astype(np.int64))
    return out


def set_in(v, f, neck, distal, buccal, occlusal):
    """A tooth from its own frame (mm) into the body's (m): its neck's middle at `neck`, its three axes along the
    unit vectors given (made square to each other here, `occlusal` kept)."""
    o = np.asarray(occlusal, float); o = o / np.linalg.norm(o)
    b = np.asarray(buccal, float); b = b - o * (b @ o); b = b / np.linalg.norm(b)
    d = np.asarray(distal, float); d = d - o * (d @ o) - b * (d @ b); d = d / np.linalg.norm(d)
    p = np.asarray(neck, float) + (v[:, :1] * d + v[:, 1:2] * b + v[:, 2:3] * o) / 1000.0
    return p, (f if np.linalg.det(np.stack([d, b, o])) > 0 else f[:, ::-1])


# MARK: seating the thirty-two in a body's jaws

UBERON = {   # each looked up in the EBI ontology lookup, 12 Nov 2026 ("secondary": of the permanent set)
    ("upper", 0): "UBERON:0018603", ("upper", 1): "UBERON:0018604", ("upper", 2): "UBERON:0018621",
    ("upper", 3): "UBERON:0018571", ("upper", 4): "UBERON:0018572", ("upper", 5): "UBERON:0018575",
    ("upper", 6): "UBERON:0018576", ("upper", 7): "UBERON:0018577",
    ("lower", 0): "UBERON:0018601", ("lower", 1): "UBERON:0018602", ("lower", 2): "UBERON:0018622",
    ("lower", 3): "UBERON:0018573", ("lower", 4): "UBERON:0018574", ("lower", 5): "UBERON:0018578",
    ("lower", 6): "UBERON:0018579", ("lower", 7): "UBERON:0018580",
}
MARK = "teeth-1"
# how far each crown leans towards the lip or cheek (degrees; the hinder lower ones lean to the tongue)
LEAN = {"upper": [17, 14, 7, 0, 0, -5, -5, -5], "lower": [15, 13, 8, -3, -6, -11, -13, -13]}
# the tooth's biting point lies this far (mm) inside the upper row's outline: the upper front teeth's edges on
# it, the cheek teeth's outer faces on it; the lower row inside the upper (the upper front teeth overlap the
# lower, the lower cheek teeth's outer cusps bite into the upper ones' middle)
INSIDE = {"upper": [1.0, 1.0, 3.0, 4.5, 4.5, 5.5, 5.5, 5.0], "lower": [3.5, 3.5, 5.0, 5.75, 5.75, 7.9, 7.9, 7.4]}
RISE = {"upper": [0.0] * 8, "lower": [1.5, 1.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]}   # above the biting plane (mm), at most
GAP = 0.10            # between neighbours (mm)
OLD = r"set_of_(upper|lower)_jaw_teeth$"


def bite(nodes, short, samples, quiet=False):
    """The biting plane and the upper row's outline, from a body's old tooth rows and the crowns its jaw bones
    carry: (c, n, left, back, front, outline): a point at height h over the plane, u to the left and d back from
    the front tooth's lip face is front + u left + d back + h n; outline: (u, d) down one side, 0.1 mm apart."""
    import re
    from scipy.ndimage import gaussian_filter1d
    def pts(pat):
        return np.concatenate([samples(v, f, 0.0005)[0] for n, (_, _, v, f) in nodes.items() if re.search(pat, short(n))])
    up = pts(r"set_of_upper_jaw_teeth$")
    cell = np.floor(up[:, [0, 2]] / 0.004).astype(int)
    key = cell[:, 0] * 10000 + cell[:, 1]
    order = np.lexsort((up[:, 1], key))
    low = up[order][np.r_[True, key[order][1:] != key[order][:-1]]]
    A = np.c_[low[:, 0], low[:, 2], np.ones(len(low))]
    for _ in range(6):          # a plane under the row: through the lowest of its points, the roots' side dropped
        co, *_ = np.linalg.lstsq(A, low[:, 1], rcond=None)
        res = low[:, 1] - A @ co
        keep = res < np.percentile(res, 60)
        co, *_ = np.linalg.lstsq(A[keep], low[keep][:, 1], rcond=None)
        ok = np.abs(low[:, 1] - A @ co) < 0.0025
        A, low = A[ok], low[ok]
    n = np.array([-co[0], 1, -co[1]]); n /= np.linalg.norm(n)
    c = n[1] * co[2]
    ez = np.array([0, 0, 1.0]); ez -= n * (ez @ n); ez /= np.linalg.norm(ez)
    ex = np.cross(n, ez); ex /= np.linalg.norm(ex)
    ex = ex if ex[0] > 0 else -ex
    mx = pts(r"^maxilla")
    crown = np.concatenate([up[up @ n - c < 0.006], mx[mx @ n - c < 0.0055]])
    P2 = np.c_[crown @ ex, crown @ ez]

    def table(x0, phi):
        back = np.array([np.sin(phi), -np.cos(phi)]); left = np.array([np.cos(phi), np.sin(phi)])
        u = (P2 - [x0, 0]) @ left; d = (P2 - [x0, 0]) @ back
        d0 = d.min(); d = d - d0
        rows = []
        for dd in np.arange(0.002, 0.062, 0.002):
            s = np.abs(d - dd) < 0.0015
            L = u[s][u[s] > 0.004]; R = -u[s][u[s] < -0.004]
            rows.append((dd, np.percentile(L, 97) if len(L) > 25 else np.nan, np.percentile(R, 97) if len(R) > 25 else np.nan))
        return np.array(rows), d0

    best = None
    for x0 in np.arange(-0.004, 0.0081, 0.0005):
        for phi in np.radians(np.arange(-8, 8.1, 0.5)):
            T, _ = table(x0, phi)
            ok = np.isfinite(T[:, 1]) & np.isfinite(T[:, 2]) & (T[:, 0] > 0.006)
            if ok.sum() >= 15:
                e = np.sqrt(np.mean((T[ok, 1] - T[ok, 2]) ** 2))
                if best is None or e < best[0]:
                    best = (e, x0, phi)
    e, x0, phi = best
    T, d0 = table(x0, phi)
    half = np.nanmean(T[:, 1:], axis=1)
    good = np.isfinite(half)
    one = np.c_[half[good], T[good, 0]]
    one = one[one[:, 1] <= one[np.argmax(one[:, 0]), 1] + 0.016]         # to a little behind its widest
    poly = np.concatenate([one[::-1] * [-1, 1], [[0, 0]], one])          # right end, the front, left end
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(poly, axis=0), axis=1))])
    si = np.arange(0, s[-1], 0.0001)
    poly = np.c_[np.interp(si, s, poly[:, 0]), np.interp(si, s, poly[:, 1])]
    poly = np.c_[gaussian_filter1d(poly[:, 0], 30, mode="nearest"), gaussian_filter1d(poly[:, 1], 30, mode="nearest")]
    poly[:, 0] = (poly[:, 0] - poly[::-1, 0]) / 2                        # the two sides alike
    poly[:, 1] = (poly[:, 1] + poly[::-1, 1]) / 2
    k = len(poly) // 2
    side = poly[k:] - [poly[k, 0], poly[k, 1]]
    left = np.cos(phi) * ex + np.sin(phi) * ez
    back = np.sin(phi) * ex - np.cos(phi) * ez
    front = x0 * ex + c * n + back * (d0 + poly[k, 1]) + ez * 0.0        # the outline's front point, on the plane
    if not quiet:
        print(f"   the biting plane tilts {np.degrees(np.arctan(co[1])):.1f} deg; the row's midline {x0 * 1000:.1f} mm "
              f"left, turned {np.degrees(phi):.1f} deg; its two sides differ by {e * 1000:.2f} mm; "
              f"{side[:, 0].max() * 2000:.1f} mm wide, {side[:, 1].max() * 1000:.1f} mm deep", flush=True)
    return c, n, left, back, front, side


def seat(folder, only=None, quiet=False):
    """Each body's two tooth rows replaced by thirty-two teeth made here, set along its own arch on its own
    biting plane; the crowns its jaw bones carried pressed back to the necks' level."""
    import json, os, re
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import anatomy_muscles_more as m
    from anatomy_fibres import read_part, write_part, sha256
    path = os.path.join(folder, "anatomy.json")
    manifest = json.load(open(path))
    said = []
    for body in manifest["bodies"]:
        if only and body["id"] != only:
            continue
        part = next(p for p in body["parts"] if p["id"] == "skull")
        if not any(re.search(OLD, s["node"]) for s in part["structures"]):
            continue
        nodes = m.body_nodes(folder, body)
        pre = next(s["node"] for s in part["structures"] if re.search(OLD, s["node"]))
        pre = pre[:re.search(OLD, pre).start()]
        B = bite(nodes, m.short, m.samples, quiet)
        c, n, left, back, front, side = B
        tan = np.gradient(side, axis=0); tan /= np.linalg.norm(tan, axis=1, keepdims=True)
        out2 = np.c_[tan[:, 1], -tan[:, 0]]
        world = lambda q, h, sg: front + sg * q[0] * left + q[1] * back + h * n
        dirs = lambda a, sg: sg * a[0] * left + a[1] * back

        def axes(arch, sd, i, k, rise):
            """Tooth i's neck and its three axes (distal, buccal, occlusal) at the outline's point k."""
            key, name, kind, H = ARCHES[arch][i][:4]
            sg = 1.0 if sd == "L" else -1.0
            o0 = -n if arch == "upper" else n
            b = dirs(out2[k], sg)
            lean = np.radians(LEAN[arch][i])
            o = np.cos(lean) * o0 + np.sin(lean) * b
            bb = b - o * (b @ o); bb /= np.linalg.norm(bb)
            d = dirs(tan[k], sg); d = d - o * (d @ o) - bb * (d @ bb); d /= np.linalg.norm(d)
            yref = (0.55 if arch == "upper" else -0.3) if kind == "incisor" else 0.0
            q = side[k] - out2[k] * (INSIDE[arch][i] / 1000)
            neck = world(q, rise / 1000, sg) - (yref * bb + H * o) / 1000
            return neck, d, bb, o

        def placed(arch, sd, i, k, rise):
            return set_in(*tooth(arch, i), *axes(arch, sd, i, k, rise))

        def clash(a, b):
            return max(m.inside_share(*a, m.Surface([b], h=0.00025), h=0.0003), m.inside_share(*b, m.Surface([a], h=0.00025), h=0.0003))

        F, made = {}, {}
        for arch in ARCHES:             # along each row from the midline: each tooth against the one before
            k, prev = 0, None
            for i in range(8):
                W = ARCHES[arch][i][5] / 1000
                Q = side - out2 * (INSIDE[arch][i] / 1000)
                if prev is None:
                    k = int(np.argmax(Q[:, 0] >= W / 2 + GAP / 2000))
                else:
                    far = np.linalg.norm(Q[k:] - prev[0], axis=1) >= (prev[1] + W) / 2 + GAP / 1000
                    k = k + int(np.argmax(far)) if far.any() else len(Q) - 1
                rise = RISE[arch][i]
                while k < len(Q) - 3:   # and on a little until the two are clear of each other
                    mine = placed(arch, "L", i, k, rise)
                    if clash(mine, made[arch, "L", i - 1] if i else placed(arch, "R", i, k, rise)) == 0:
                        break
                    k += 2
                F[arch, i] = k
                made[arch, "L", i], made[arch, "R", i] = mine, placed(arch, "R", i, k, rise)
                prev = (Q[k], W)
        uppers = m.Surface([made["upper", "L", i] for i in range(8)], h=0.00025)
        rises = {}
        for i in range(8):
            rise = RISE["lower"][i]
            while True:                 # down until it and the upper row are clear of each other
                v, f = placed("lower", "L", i, F["lower", i], rise)
                mine = m.Surface([(v, f)], h=0.00025)
                if (m.inside_share(v, f, uppers, h=0.0003) == 0
                        and max(m.inside_share(*made["upper", "L", j], mine, h=0.0003) for j in range(8)) == 0) or rise < -3.0:
                    break
                rise -= 0.1
            rises[i] = rise
            made["lower", "L", i], made["lower", "R", i] = (v, f), placed("lower", "R", i, F["lower", i], rise)
        worst = 0.0                     # what is left of a tooth in its neighbour, or in the one across the midline
        for arch in ARCHES:
            for i in range(8):
                for other in ([made[arch, "L", i - 1]] if i else [made[arch, "R", 0]]):
                    worst = max(worst, clash(made[arch, "L", i], other))
        rise_of = lambda arch, i: rises[i] if arch == "lower" else 0.0

        def ridge(arch, sds, bone):
            """A jaw bone's tooth-bearing part made again as one solid with bone about its roots: 1.4 mm of bone
            round each root (1.1 in the lower jaw, whose own bone holds them) from 1.3 mm past its neck to its
            end, the spaces between neighbouring roots filled, run into the bone's own solid with a fillet that
            is spent 9 mm away, the teeth's sockets left out. From 10 mm away the new surface sinks half a
            millimetre under the bone's own, which takes over there: returns the new solid's surface, and the
            bone's own mesh with what the solid stands for cut away along a smooth line. (The scanned jaws have
            little bone about the roots: a plate thinner than the roots themselves.)"""
            from skimage import measure
            from scipy import ndimage
            h, R, wall, K, NEAR, HAND = 0.0003, 0.0032, 1.4 if arch == "upper" else 1.1, 9.0, 13.0, 10.2
            hm = h * 1000
            allv = np.concatenate([made[arch, sd, i][0] for sd in sds for i in range(8)])
            lo, hi = allv.min(0) - (NEAR + 3.5) / 1000, allv.max(0) + (NEAR + 3.5) / 1000
            ax = [np.arange(lo[j], hi[j] + h, h) for j in range(3)]
            G = np.stack(np.meshgrid(*ax, indexing="ij"), axis=-1).astype(np.float32)
            shape = G.shape[:3]
            U = np.full(shape, 9.0, np.float32)     # outside the roots' bone (mm)
            T = np.full(shape, 9.0, np.float32)     # outside the teeth
            above = np.zeros(shape, bool)           # past a tooth's neck, beside its crown
            for sd in sds:
                for i in range(8):
                    neck, d, bb, o = axes(arch, sd, i, F[arch, i], rise_of(arch, i))
                    v = made[arch, sd, i][0]
                    i0 = np.maximum(np.floor((v.min(0) - 0.0055 - lo) / h).astype(int), 0)
                    i1 = np.minimum(np.ceil((v.max(0) + 0.0055 - lo) / h).astype(int) + 1, np.array(shape))
                    sl = tuple(slice(a, b) for a, b in zip(i0, i1))
                    rel = (G[sl].astype(np.float64) - neck) * 1000
                    X, Y, Z = rel @ d, rel @ bb, rel @ o
                    Fi = field(arch, i, X, Y, Z)
                    # the bone's rim follows each neck: a millimetre short of it between two teeth, and further
                    # down the root on the tooth's lip and tongue faces (most on the front teeth)
                    dip = {"incisor": 1.6, "canine": 1.8, "premolar": 1.1, "molar": 0.7}[ARCHES[arch][i][2]]
                    rim = -1.0 - dip * (1 - np.clip(np.abs(X) / (ARCHES[arch][i][6] / 2), 0, 1) ** 2)
                    U[sl] = np.minimum(U[sl], np.maximum(Fi - wall, Z - rim))
                    T[sl] = np.minimum(T[sl], Fi)
                    above[sl] |= (Z > rim) & (Fi < 5.0)
            roots = U < 0
            del U
            band = ndimage.distance_transform_edt(ndimage.distance_transform_edt(~roots) * h <= R) * h > R
            band |= roots
            ob = (ndimage.distance_transform_edt(~band) * hm).astype(np.float32)        # mm outside the band
            d_band = ndimage.gaussian_filter(ob - (ndimage.distance_transform_edt(band) * hm).astype(np.float32), 1.0)
            near = ob <= NEAR
            # the bone's own solid as a signed distance, asked on every second point and read between them
            c = np.zeros(shape, bool)
            c[::2, ::2, ::2] = True
            c &= ob <= NEAR + 1.5
            surf = m.Surface([bone], h=0.0004)
            pts = G[c].astype(np.float64)
            ins, dd = np.zeros(len(pts), bool), np.zeros(len(pts))
            for part_ in np.array_split(np.arange(len(pts)), max(1, len(pts) // 300000)):
                ins[part_], dd[part_] = surf.query(pts[part_], reach=0.012)[:2]
            coarse = np.full(tuple(-(-s // 2) for s in shape), 12.0, np.float32)
            coarse[c[::2, ::2, ::2]] = np.where(ins, -1.0, 1.0) * np.minimum(dd, 0.012) * 1000
            idx = np.indices(shape, dtype=np.float32) / 2
            d_bone = ndimage.map_coordinates(coarse, idx, order=1, mode="nearest")
            del idx, c, pts
            both = smin(d_band, d_bone, K)           # a fillet where the two meet
            mask = near & ~above
            if len(sds) == 1:                        # a maxilla: its own side of the midline
                mask &= ((G.astype(np.float64) - front) @ left) * (1.0 if sds == "L" else -1.0) > 0.00005
            solid = (both < 0) & mask & (T > 0.12)
            lab, k = ndimage.label(solid)            # the one piece that holds the roots
            if k > 1:
                solid = lab == np.argmax(np.bincount(lab[band & solid])[1:]) + 1
                mask &= ndimage.binary_dilation(solid, iterations=3)
            ds = (ndimage.distance_transform_edt(~solid) * hm).astype(np.float32)        # mm outside the solid
            sink = 0.5 * ease(np.clip((ob - (HAND - 0.2)) / 2.0, 0, 1))
            edge = ndimage.gaussian_filter((ndimage.distance_transform_edt(~mask) - ndimage.distance_transform_edt(mask)).astype(np.float32), 1.0)
            dist = np.maximum(np.maximum((both + sink) / hm, edge), (0.12 - T) / hm)   # (in grid steps)
            v, f, _, _ = measure.marching_cubes(dist, 0.0, spacing=(h, h, h))
            v = v + lo
            f = f.astype(np.int64)
            if np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum() < 0:
                f = f[:, ::-1]
            v = taubin(v, f, 8)
            import fast_simplification
            q, g = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32), target_reduction=max(0.0, 1 - 11000 * len(sds) / len(f)), agg=4)
            used = np.unique(g)
            remap = np.full(len(q), -1, np.int64); remap[used] = np.arange(len(used))
            # the bone's own mesh: kept from HAND mm off the band, and nearer where the solid does not stand for
            # it (a plate too thin for the grid), cut along that line
            bv, bf = bone
            at = ((bv - lo) / h).T
            ok = np.all((at >= 0) & (at <= np.array(shape)[:, None] - 1), axis=0)
            s = np.ones(len(bv))
            o_ = ndimage.map_coordinates(ob, at[:, ok], order=1)
            s_ = ndimage.map_coordinates(ds, at[:, ok], order=1)
            s[ok] = np.maximum(o_ - HAND, np.minimum(s_ - 0.5, o_ - 2.0))
            bv, bf = clip(bv, bf, s)
            return q[used].astype(np.float64), remap[g].astype(np.int64), bv, bf

        # the jaw bones: no bone (the crowns they carried, the sockets' ragged rims) past the necks' level
        k_end = {arch: F[arch, 7] for arch in ARCHES}
        moved = {}
        meshes = list(read_part(os.path.join(folder, part["file"])))
        for k, st in enumerate(part["structures"]):
            name = m.short(st["node"])
            arch = "upper" if re.match(r"maxilla", name) else "lower" if name == "mandible" else None
            if arch is None:
                continue
            v, f = meshes[k]
            v = v.copy()
            rel = v - front
            u, d, h = rel @ left, rel @ back, rel @ n
            ke = min(k_end[arch] + 40, len(side) - 1)
            line = side[:ke] - np.c_[np.gradient(side, axis=0)[:ke, 1], -np.gradient(side, axis=0)[:ke, 0]] / 0.0001 * (0.0045 if arch == "upper" else 0.0065)
            from scipy.spatial import cKDTree
            dist, j = cKDTree(line).query(np.c_[np.abs(u), d])
            # the neck's level along the row: each tooth's crown height (leaning), between teeth interpolated
            ks = [F[arch, i] for i in range(8)]
            Hs = [ARCHES[arch][i][3] * np.cos(np.radians(LEAN[arch][i])) / 1000 for i in range(8)]
            if arch == "upper":
                level = np.interp(j, ks, Hs) + 0.0004
                hit = (dist < 0.0085) & (h < level)
                v[hit] += (level[hit] - h[hit])[:, None] * n
            else:
                rs = [rises[i] / 1000 for i in range(8)]
                level = np.interp(j, ks, np.array(rs) - np.array(Hs)) - 0.0004
                hit = (dist < 0.0075) & (h > level) & (d < side[ke, 1] + 0.001)
                v[hit] += (level[hit] - h[hit])[:, None] * n
            # and its tooth-bearing ridge made again, with bone about the roots, in place of its own there
            rv, rf, v, f = ridge(arch, "LR" if arch == "lower" else name[-1], (v, f))
            f = np.concatenate([f, rf + len(v)]); v = np.concatenate([v, rv])
            meshes[k] = (v, f)
            st["triangles"] = int(len(f))
            moved[name] = int(hit.sum())
        # the part: the old rows out, the thirty-two in
        keep = [k for k, s in enumerate(part["structures"]) if not re.search(OLD, s["node"])]
        structures = [part["structures"][k] for k in keep]
        meshes = [meshes[k] for k in keep]
        sides = {"L": "left", "R": "right"}
        for arch in ARCHES:
            for sd in "RL":
                for i in (range(7, -1, -1) if sd == "R" else range(8)):
                    key, name = ARCHES[arch][i][:2]
                    v, f = made[arch, sd, i]
                    structures.append({"node": f"{pre}{arch}_{key}_{sd}", "label": f"{arch} {sides[sd]} {name}",
                                       "uberon": UBERON[arch, i], "tissue": "tooth", "group": f"{arch.capitalize()} teeth",
                                       "inner": False, "made": MARK, "basis": "made from its textbook description",
                                       "triangles": int(len(f))})
                    meshes.append((np.asarray(v, np.float64), np.asarray(f, np.int64)))
        part["structures"] = structures
        lo, hi = write_part(os.path.join(folder, part["file"]), meshes)
        part["bytes"] = os.path.getsize(os.path.join(folder, part["file"]))
        part["sha256"] = sha256(os.path.join(folder, part["file"]))
        part["triangles"] = int(sum(s["triangles"] for s in structures))
        part["bounds"] = [round(float(x), 5) for x in (*lo, *hi)]
        body["teeth"] = MARK
        note = (f"{body['id']}: 32 teeth seated; the lower ones {min(rises.values()):.1f} to {max(rises.values()):.1f} mm over the "
                f"biting plane; a tooth in its neighbour at most {worst * 100:.2f}%; bone pressed back: {moved}")
        said.append(note)
        if not quiet:
            print("   " + note, flush=True)
    with open(path, "w") as out:
        json.dump(manifest, out, indent=1, ensure_ascii=False)
    return said


def sheet(path):
    """The sixteen kinds, from the cheek side, from the next tooth's side and from the biting surface."""
    sys.path.insert(0, "/tmp/claude-0/-home-user/da8cf5cf-b385-5646-a716-c25fc72fb88a/scratchpad/mm")
    from quick import render
    from PIL import Image, ImageDraw
    rows = []
    for arch in ("upper", "lower"):
        for view in ("lip", "tongue", "front", "bite"):
            M = []
            for i in range(8):
                v, f = tooth(arch, i)
                s = -1.0 if arch == "upper" else 1.0           # shown as in the mouth: the upper crowns down
                x, y, z = v[:, 0], v[:, 1], v[:, 2] * s
                if view == "lip":      q, flip = np.stack([x * s, z, y], axis=1), False
                elif view == "tongue": q, flip = np.stack([-x * s, z, -y], axis=1), False
                elif view == "front":  q, flip = np.stack([y * s, z, -x], axis=1), False
                else:                  q, flip = np.stack([x, -y * s, v[:, 2]], axis=1), False
                q = q + np.array([i * 16.0, 0, 0])
                g = f if np.linalg.det(np.stack([q[1] - q[0], q[2] - q[0], q[3] - q[0]])) * np.linalg.det(np.stack([v[1] - v[0], v[2] - v[0], v[3] - v[0]])) > 0 else f[:, ::-1]
                M.append((q / 1000.0, g, (236, 232, 218)))
            tmp = path.replace(".png", f"_{arch}_{view}.png")
            render(M, (0.0, 0.0, 1.0), tmp, size=1500)
            im = Image.open(tmp)
            ink = np.abs(np.asarray(im).astype(int) - np.array([22, 24, 28])).sum(2) > 12
            ys = np.flatnonzero(ink.any(1))
            rows.append(im.crop((0, max(ys[0] - 14, 0), im.width, min(ys[-1] + 14, im.height))))
    W = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        W.paste(r, (0, y)); y += r.height
    W.save(path)


if __name__ == "__main__":
    if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
        import os
        seat(sys.argv[1], only=os.environ.get("TEETH_ONLY"))
    elif len(sys.argv) > 2 and sys.argv[1] == "--sheet":
        for arch in ARCHES:
            for i in range(8):
                v, f = tooth(arch, i)
                e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
                _, c = np.unique(e, axis=0, return_counts=True)
                print(arch, ARCHES[arch][i][0], len(f), "triangles; closed", bool((c == 2).all()),
                      "box", np.round(v.min(0), 1), np.round(v.max(0), 1), flush=True)
        sheet(sys.argv[2])
    else:
        print(__doc__)
