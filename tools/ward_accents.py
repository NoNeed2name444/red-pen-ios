#!/usr/bin/env python3
"""Each Ward section's colours, worked out from its hue, and written into
ios/RedPen/Shared/Ward/WardLook.swift (the table between the
"ward_accents.py" marks).

  tools/ward_accents.py           print the table and how far apart it sits
  tools/ward_accents.py --write   rewrite the table in WardLook.swift
  tools/ward_accents.py --check   exit 1 if WardLook.swift's table differs

A section (Questions keeps the palette's own blue) has a hue in OKLCH
degrees, its identity in both modes, and a lightness (OKLab L) for its
words in each mode. For each mode it gets three colours of that hue:

  accent  words and glyphs (button labels, links, icons, the chosen tab,
          progress): the most chroma, between the mode's floor (so it
          reads as its hue) and its cap (so it is not neon), that stays in
          sRGB and reads 4.6:1 (AA's 4.5 with a margin, so rounding never
          tips it) on every tier, the well to a sheet.
  fill    under white words (a switch that is on, a chosen segment): the
          most chroma at the fill's lightness with white at 4.6:1.
  ink     the paper's grid and the controls' edges: the most chroma at the
          ink's lightness that, laid on at a control edge's strength
          (WardRelief.edgeAlpha), reads 3.1:1 on the base and on a card.

When no chroma in that range keeps the promise, the lightness steps away
from the page (darker in light mode, lighter in dark) until one does: the
shade moves, never the hue. The palette (WardPalette.swift) and the edge
strengths (WardRelief.swift) are read from the source, so a palette or
route change is one edit there (or of the hues below) and a --write.

The hues and lightnesses below were chosen (15 Oct) by searching each
section's hue family for the set that keeps the sections, and the colours
that mean something (right, wrong, due, the ECG red, the beam, the New
badge's blue), furthest apart in OKLab: at least 0.076 everywhere, in both
modes. tests/ward/accent-blue.test.mjs and WardLookTests hold them to it.
"""
import math, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WARD = os.path.join(ROOT, "ios/RedPen/Shared/Ward")
LOOK = os.path.join(WARD, "WardLook.swift")

# section: (hue, words' lightness in light, in dark). Light words sit
# between 0.42 and 0.52 (darker is muddy, lighter fails the well); dark
# words between 0.74 and 0.88.
SECTIONS = [
    ("cards", 320, 0.42, 0.77),      # orchid
    ("textbook", 132, 0.42, 0.84),   # leaf
    ("cases", 284, 0.42, 0.76),      # indigo, kept off blue
    ("osce", 92, 0.44, 0.76),        # brass
    ("audio", 302, 0.47, 0.83),      # violet
    ("ideas", 340, 0.48, 0.83),      # magenta
]
CAP = (0.19, 0.15)        # chroma in light and dark: vivid, not neon
FLOOR = (0.085, 0.10)     # and at least this, so every colour reads as its hue
FILL_L = (0.56, 0.52)     # a fill's lightness before it steps darker
INK_LIFT = (0.12, 0.0)    # the grid's ink: the words' lightness and this (a
                          # finer line wants a lighter ink by day), before it
                          # steps away from the page; following the words keeps
                          # the inks as far apart as the words
MARGIN = 0.1              # over every ratio
C_STEP, L_STEP = 0.005, 0.01


def palette():
    text = open(os.path.join(WARD, "WardPalette.swift")).read()
    table = {m.group(1): (int(m.group(2), 16), int(m.group(3), 16))
             for m in re.finditer(r"\.(\w+):\s*\(0x([0-9A-Fa-f]{6}),\s*0x([0-9A-Fa-f]{6})\)", text)}
    tiers = re.search(r"static let tiers: \[WardToken\] = \[([^\]]*)\]", text).group(1)
    return table, [t.strip().lstrip(".") for t in tiers.split(",")]


def relief():
    text = open(os.path.join(WARD, "WardRelief.swift")).read()
    get = lambda name: float(re.search(r"static let %s = ([0-9.]+)" % name, text).group(1))
    return (get("lightEdge"), get("darkEdge")), get("edgeContrast")


# --- colour ---------------------------------------------------------------

def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_gamma(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb(h):
    return ((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255


def luminance(h):
    r, g, b = (to_linear(c) for c in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def oklab(h):
    r, g, b = (to_linear(c) for c in rgb(h))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def oklch(h):
    L, a, b = oklab(h)
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def delta(a, b):
    return math.dist(oklab(a), oklab(b))


def from_oklch(L, C, hue):
    """0xRRGGBB, or None outside sRGB."""
    a, b = C * math.cos(math.radians(hue)), C * math.sin(math.radians(hue))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    lin = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    if any(c < -1e-6 or c > 1 + 1e-6 for c in lin):
        return None
    out = 0
    for c in lin:
        out = out << 8 | int(round(min(1, max(0, to_gamma(min(1, max(0, c))))) * 255))
    return out


def composite(top, alpha, base):
    """`top` laid on `base` at `alpha`, as WardRelief.composite does."""
    out = 0
    for x, y in zip(rgb(base), rgb(top)):
        out = out << 8 | int(round((x + (y - x) * alpha) * 255))
    return out


# --- the search -----------------------------------------------------------

def vivid(hue, L, cap, floor, ok):
    """The most chroma (cap down to floor, in steps) at L that is in sRGB
    and ok."""
    for i in range(int(round(cap / C_STEP)), int(round(floor / C_STEP)) - 1, -1):
        c = from_oklch(L, i * C_STEP, hue)
        if c is not None and ok(c):
            return c
    return None


def settle(hue, L, dark, ok, step):
    """vivid() at L, or stepping L by `step` until something is ok. Returns
    the colour and how far the lightness moved."""
    moved = 0.0
    while 0 <= L + moved <= 1:
        c = vivid(hue, L + moved, CAP[dark], FLOOR[dark], ok)
        if c is not None:
            return c, moved
        moved += step
    raise SystemExit("no colour of hue %s keeps its promise" % hue)


def section_colours(table, tiers, edge_alpha, edge_contrast):
    out, notes = {}, []
    for name, hue, light_L, dark_L in SECTIONS:
        row = {}
        for dark in (0, 1):
            grounds = [table[t][dark] for t in tiers]
            white = table["onPrimary"][dark]
            base = [table["background"][dark], table["surface"][dark]]
            away = L_STEP if dark else -L_STEP
            words = lambda c: all(contrast(c, g) >= 4.5 + MARGIN for g in grounds)
            under = lambda c: contrast(white, c) >= 4.5 + MARGIN
            edge = lambda c: all(contrast(composite(c, edge_alpha[dark], g), g) >= edge_contrast + MARGIN
                                 for g in base)
            words_L = dark_L if dark else light_L
            accent, m1 = settle(hue, words_L, dark, words, away)
            fill, m2 = settle(hue, FILL_L[dark], dark, under, -L_STEP)
            ink, m3 = settle(hue, words_L + INK_LIFT[dark], dark, edge, away)
            for role, moved in (("accent", m1), ("fill", m2), ("ink", m3)):
                if moved:
                    notes.append("%s %s %s: lightness moved %+.2f to keep its promise"
                                 % (name, "dark" if dark else "light", role, moved))
            row[dark] = {"accent": accent, "fill": fill, "ink": ink}
        out[name] = (hue, row)
    return out, notes


def swift_table(colours):
    lines = ["    // ward_accents.py: begin",
             "    private static let table: [WardSection: WardSectionColours] = ["]
    for name, (hue, row) in colours.items():
        pair = lambda role: "(0x%06X, 0x%06X)" % (row[0][role], row[1][role])
        lines.append("        .%s: WardSectionColours(hue: %d, ink: %s, accent: %s, fill: %s),"
                     % (name, hue, pair("ink"), pair("accent"), pair("fill")))
    lines += ["    ]", "    // ward_accents.py: end"]
    return "\n".join(lines)


MARKS = re.compile(r"    // ward_accents\.py: begin.*?// ward_accents\.py: end", re.S)


def report(colours, table):
    semantic = ["success", "danger", "warning", "ecg", "beam"]
    for dark in (0, 1):
        mode = "dark" if dark else "light"
        print("==", mode)
        accents = {n: r[dark]["accent"] for n, (_, r) in colours.items()}
        accents["questions"] = table["primaryInk"][dark]
        for n, (hue, r) in colours.items():
            c = r[dark]
            L, C, H = oklch(c["accent"])
            print("  %-9s accent %06X (L %.2f C %.3f h %5.1f)  fill %06X  ink %06X"
                  % (n, c["accent"], L, C, H, c["fill"], c["ink"]))
        pairs = sorted((delta(accents[a], accents[b]), a, b)
                       for i, a in enumerate(accents) for b in list(accents)[i + 1:])
        print("  closest sections:", ", ".join("%s/%s %.3f" % (a, b, d) for d, a, b in pairs[:4]))
        sem = sorted((delta(accents[a], table[s][dark]), a, s) for a in accents for s in semantic + ["primaryInk"]
                     if not (a == "questions" and s == "primaryInk"))
        print("  closest to a meaning:", ", ".join("%s/%s %.3f" % (a, s, d) for d, a, s in sem[:4]))


def main():
    table, tiers = palette()
    edge_alpha, edge_contrast = relief()
    colours, notes = section_colours(table, tiers, edge_alpha, edge_contrast)
    block = swift_table(colours)
    source = open(LOOK).read()
    if not MARKS.search(source):
        raise SystemExit("WardLook.swift has no ward_accents.py marks")
    if "--check" in sys.argv:
        if MARKS.search(source).group(0) != block:
            print("WardLook.swift's section table is not what tools/ward_accents.py makes; run it with --write")
            sys.exit(1)
        print("section table up to date")
        return
    if "--write" in sys.argv:
        open(LOOK, "w").write(MARKS.sub(lambda _: block, source))
        print("wrote", os.path.relpath(LOOK, ROOT))
    report(colours, table)
    for n in notes:
        print("  note:", n)


if __name__ == "__main__":
    main()
