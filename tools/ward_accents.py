#!/usr/bin/env python3
"""Each Ward section's colours, worked out from its hue, and written into
ios/RedPen/Shared/Ward/WardLook.swift (the table between the
"ward_accents.py" marks).

  tools/ward_accents.py           print the table and how far apart it sits
  tools/ward_accents.py --write   rewrite the table in WardLook.swift
  tools/ward_accents.py --check   exit 1 if WardLook.swift's table differs,
                                  but for the owner's accepted cases (below)

A section has a hue in OKLCH degrees, its identity in both modes, a
lightness (OKLab L) for its words in each mode, and its fill in each mode,
pinned. For each mode it has three colours of that hue:

  accent  words and glyphs (button labels, links, icons, the chosen tab,
          progress): the most chroma, between the mode's floor (so it
          reads as its hue) and its cap (so it is not neon), that stays in
          sRGB and reads 4.6:1 (AA's 4.5 with a margin, so rounding never
          tips it) on every tier, the well to a sheet, and on the
          section's own wash behind the page.
  fill    under the on-fill words (a switch that is on, a chosen segment): the
          owner's colour as given, checked, never searched: the on-fill words (onPrimary) read
          4.6:1 on it and its hue is within 2 degrees of the section's, or
          the tool exits 1.
  ink     the paper's grid and the controls' edges: the most chroma at the
          ink's lightness that, laid on at a control edge's strength
          (WardRelief.edgeAlpha), reads 3.1:1 on the base and on a card.

When no chroma in that range keeps the promise, the lightness steps away
from the page (darker in light mode, lighter in dark) until one does: the
shade moves, never the hue. The palette (WardPalette.swift) and the edge
strengths (WardRelief.swift) are read from the source, so a palette or
route change is one edit there (or of the rows below) and a --write.

The hues and fills are the owner's 2026-10-21 palette
(docs/design/palette-2026-10-21.md): seven of its ten colours, one per
section, each fill the owner's hex exactly in both modes and each hue the
fill's own; Cards' Care Blue is also the primary (the look outside any
section). Where the owner's colour reads 4.6:1 on every tier as it is (at
night, mostly), it is the words' colour too; elsewhere the words are a
shade of its hue. The words' lightnesses were chosen, one section at a
time inside the bands below, so that every accent stays at least 0.076 in
OKLab from every other and from the colours that mean something (right,
wrong, due, the ECG red, the beam), in both modes: the least gaps are
0.082 by day (textbook/success) and 0.084 by night (cards/audio).
tests/ward/accent-blue.test.mjs and WardLookTests hold them to it.

The ground behind each section's pages (WardSection.wash in WardLook.swift)
is the plain base in every section since 22 Oct, the owner's grey ground, so
it is read from there, not mixed from the fill. Since the same day every
role is the owner's hex exactly (no shades) and the on-fill words are white
again: white reads under 4.6:1 on every fill, so this tool exits 1 at the
first fill, and the table in WardLook.swift is written by hand.

--check holds that table to this tool, cell by cell. A cell may differ only
as the owner's own hex, and a promise may fall short only, as a case on the
owner's list in tests/ward/owner-accepted.json (the owner, 22 Oct 2026,
about 3:44 AM Cairo, shown that these colours fail the readability checks:
"STOP IMPROVISING DONT CHANGE THE COLORS I GAVE U"), measured within 0.01 of
the value recorded there. Any other difference, a value that moves, or a
listed case this tool no longer finds exits 1.
"""
import json, math, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WARD = os.path.join(ROOT, "ios/RedPen/Shared/Ward")
LOOK = os.path.join(WARD, "WardLook.swift")
# the owner's accepted cases, shared with tests/ward/accent-blue.test.mjs
OWNER = os.path.join(ROOT, "tests/ward/owner-accepted.json")
OWNER_KEY = "tools/ward_accents.py --check"
OWNER_SLACK = 0.01        # how far a listed case's measure may move

# section, in WardSection's order: (hue, words' lightness in light, in dark,
# fill in light, in dark). Light words sit between 0.36 and 0.55 (darker is
# muddy, lighter fails the well); dark words between 0.66 and 0.94.
SECTIONS = [
    ("questions", 23, 0.40, 0.85, 0xFF6B6B, 0xFF6B6B),   # Vital Coral, red as ECG paper
    ("cards", 260, 0.47, 0.76, 0x3B82F6, 0x3B82F6),      # Care Blue, the primary
    ("textbook", 182, 0.41, 0.75, 0x14B8A6, 0x14B8A6),   # Pulse Teal
    ("cases", 42, 0.47, 0.79, 0xFF9F7A, 0xFF9F7A),       # Peach Glow
    ("osce", 129, 0.36, 0.85, 0xA3E635, 0xA3E635),       # Lime Zest
    ("audio", 294, 0.47, 0.74, 0xA78BFA, 0xA78BFA),      # Soft Lilac
    ("ideas", 350, 0.47, 0.75, 0xF472B6, 0xF472B6),      # Bubblegum Pink
]
CAP = (0.19, 0.15)        # chroma in light and dark: vivid, not neon
FLOOR = (0.07, 0.08)      # and at least this, so every colour reads as its hue.
                          # By day 0.07, not 0.085: at hue 186 no teal with
                          # 0.085 of chroma reads 4.6:1 on the paler tiers, so
                          # the search found nothing; at 0.07 every hue stays
                          # within 2 degrees and every promise holds. At night
                          # 0.08, not 0.10: Questions' words are a pale coral
                          # (L 0.85), the only coral that keeps clear of Cases'
                          # Peach Glow and of a wrong answer's Vital Coral
HUE_SLACK = 2             # a pinned fill's hue, at most this far from its section's
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


def washes(table):
    """Each section's wash behind the page, (light, dark): WardSection.wash
    in WardLook.swift, the plain base (WardPalette's .background) in every
    section since 22 Oct."""
    text = open(LOOK).read()
    if not re.search(r"func wash\(dark: Bool\) -> UInt32 \{\s*WardPalette\.hex\(\.background, dark: dark\)\s*\}", text):
        raise SystemExit("WardSection.wash in WardLook.swift is not the plain base (WardPalette's .background)")
    return {name: table["background"] for name, *_ in SECTIONS}


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


def hue_apart(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def pinned_fill(name, hue, fill, white, lenient=False):
    """The owner's fill as given, once it keeps its promises: on-fill words
    4.6:1 on it, and the section's hue. Exits 1 if it does not; `lenient`
    (--check, which weighs a short ratio against the owner's list) exits
    only for the hue."""
    ratio, h = contrast(white, fill), oklch(fill)[2]
    if hue_apart(h, hue) > HUE_SLACK or (ratio < 4.5 + MARGIN and not lenient):
        print("%s fill %06X: on-fill words %.2f:1 (needs %.1f), hue %.1f (section %d, within %d)"
              % (name, fill, ratio, 4.5 + MARGIN, h, hue, HUE_SLACK))
        sys.exit(1)
    return fill


def section_colours(table, tiers, edge_alpha, edge_contrast, wash, lenient=False):
    out, notes = {}, []
    for name, hue, light_L, dark_L, fill_light, fill_dark in SECTIONS:
        row = {}
        for dark in (0, 1):
            white = table["onPrimary"][dark]
            fill = pinned_fill(name, hue, fill_dark if dark else fill_light, white, lenient)
            # every tier, and the section's own wash behind the page
            grounds = [table[t][dark] for t in tiers] + [wash[name][dark]]
            base = [table["background"][dark], table["surface"][dark]]
            away = L_STEP if dark else -L_STEP
            words = lambda c: all(contrast(c, g) >= 4.5 + MARGIN for g in grounds)
            edge = lambda c: all(contrast(composite(c, edge_alpha[dark], g), g) >= edge_contrast + MARGIN
                                 for g in base)
            words_L = dark_L if dark else light_L
            # the owner's colour itself for the words, where it keeps the
            # promise as it is (at night, mostly); else a shade of its hue
            accent, m1 = (fill, 0.0) if words(fill) else settle(hue, words_L, dark, words, away)
            ink, m3 = settle(hue, words_L + INK_LIFT[dark], dark, edge, away)
            for role, moved in (("accent", m1), ("ink", m3)):
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
ROW = re.compile(r"\.(\w+): WardSectionColours\(hue: (\d+), ink: \(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\), "
                 r"accent: \(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\), fill: \(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)\)")


def source_table(source):
    """The table as WardLook.swift has it: {section: (hue, {mode: {role: hex}})}."""
    out = {}
    for m in ROW.finditer(MARKS.search(source).group(0)):
        v = [int(x, 16) for x in m.groups()[2:]]
        out[m.group(1)] = (int(m.group(2)), {dark: {"ink": v[dark], "accent": v[2 + dark], "fill": v[4 + dark]}
                                             for dark in (0, 1)})
    return out


def owner_accepted():
    """The owner's accepted cases for --check, {case: measured}, from
    tests/ward/owner-accepted.json."""
    try:
        with open(OWNER) as f:
            cases = json.load(f).get(OWNER_KEY)
    except (OSError, ValueError) as e:
        raise SystemExit("the owner's list %s cannot be read: %s" % (os.path.relpath(OWNER, ROOT), e))
    if not isinstance(cases, dict) or not cases:
        raise SystemExit("the owner's list %s has no %r cases" % (os.path.relpath(OWNER, ROOT), OWNER_KEY))
    return {k: float(v) for k, v in cases.items()}


def check(colours, table, tiers, edge_alpha, edge_contrast, wash, source):
    """--check: WardLook.swift's table against what this tool makes, cell
    by cell, each promise at the tool's own thresholds. A fill whose on-fill
    words read short, and a cell that is the owner's hex where the tool
    makes a shade, pass only as a case on the owner's list at its measure
    (within OWNER_SLACK). Returns the exit status."""
    accepted, have = owner_accepted(), source_table(source)
    problems, seen, cells, short = [], set(), 0, 0

    def owner(case, measured):
        seen.add(case)
        if case not in accepted:
            problems.append('owner-accepted miss: "%s": %.3f' % (case, measured))
        elif abs(measured - accepted[case]) > OWNER_SLACK:
            problems.append('owner-accepted moved: "%s": %.3f, listed %.3f' % (case, measured, accepted[case]))

    def lowest(c, grounds, measure):
        return min(((measure(c, g), name) for name, g in grounds), key=lambda x: x[0])

    kept = {}
    for name, hue, _, _, fill_light, fill_dark in SECTIONS:
        if name not in have:
            problems.append("%s: no row in WardLook.swift's table" % name)
            continue
        src_hue, src = have[name]
        if src_hue != hue:
            problems.append("%s: hue %d in WardLook.swift, %d here" % (name, src_hue, hue))
        row = {}
        for dark in (0, 1):
            mode = "dark" if dark else "light"
            made, given, mine = colours[name][1][dark], src[dark], fill_dark if dark else fill_light
            if given["fill"] != made["fill"]:
                problems.append("%s %s fill: %06X, not the owner's %06X" % (name, mode, given["fill"], made["fill"]))
            ratio = contrast(table["onPrimary"][dark], made["fill"])
            if ratio < 4.5 + MARGIN:
                short += 1
                owner("%s %s fill: the on-fill words on it" % (name, mode), ratio)
            grounds = [(t, table[t][dark]) for t in tiers] + [("wash", wash[name][dark])]
            base = [(t, table[t][dark]) for t in ("background", "surface")]
            promise = {
                "accent": lambda c: lowest(c, grounds, contrast) + ("words",),
                "ink": lambda c: lowest(c, base, lambda c, g: contrast(composite(c, edge_alpha[dark], g), g))
                + ("a control's edge",),
            }
            for role in ("accent", "ink"):
                if given[role] == made[role]:
                    continue
                if given[role] != mine:
                    problems.append("%s %s %s: %06X, neither the tool's %06X nor the owner's %06X"
                                    % (name, mode, role, given[role], made[role], mine))
                    continue
                cells += 1
                value, ground, what = promise[role](given[role])
                owner("%s %s %s: %s on the %s" % (name, mode, role, what, ground), value)
            row[dark] = dict(given)
        kept[name] = (hue, row)
    extra = sorted(set(have) - set(kept))
    if extra:
        problems.append("rows this tool does not make: %s" % ", ".join(extra))
    if not problems and MARKS.search(source).group(0) != swift_table(kept):
        problems.append("WardLook.swift's table is laid out unlike this tool's (order, spacing or a row)")
    for case in sorted(set(accepted) - seen):
        problems.append('owner-accepted stale: "%s": listed %.3f, no such case now' % (case, accepted[case]))
    if problems:
        print("WardLook.swift's section table is not what tools/ward_accents.py makes, but for the owner's list (%s):"
              % os.path.relpath(OWNER, ROOT))
        for p in problems:
            print("  " + p)
        return 1
    print("section table up to date, but for the owner's accepted cases: %d cells in the owner's hex, "
          "%d fills short for white (%d cases, %s)" % (cells, short, len(seen), os.path.relpath(OWNER, ROOT)))
    return 0


def report(colours, table):
    semantic = ["success", "danger", "warning", "ecg", "beam"]
    for dark in (0, 1):
        mode = "dark" if dark else "light"
        print("==", mode)
        accents = {n: r[dark]["accent"] for n, (_, r) in colours.items()}
        for n, (hue, r) in colours.items():
            c = r[dark]
            L, C, H = oklch(c["accent"])
            print("  %-9s accent %06X (L %.2f C %.3f h %5.1f)  fill %06X  ink %06X"
                  % (n, c["accent"], L, C, H, c["fill"], c["ink"]))
        pairs = sorted((delta(accents[a], accents[b]), a, b)
                       for i, a in enumerate(accents) for b in list(accents)[i + 1:])
        print("  closest sections:", ", ".join("%s/%s %.3f" % (a, b, d) for d, a, b in pairs[:4]))
        sem = sorted((delta(accents[a], table[s][dark]), a, s) for a in accents for s in semantic)
        print("  closest to a meaning:", ", ".join("%s/%s %.3f" % (a, s, d) for d, a, s in sem[:4]))
        least = min(pairs[0], sem[0])
        print("  least gap: %.3f (%s/%s)" % least)


def main():
    table, tiers = palette()
    edge_alpha, edge_contrast = relief()
    wash = washes(table)
    checking = "--check" in sys.argv
    colours, notes = section_colours(table, tiers, edge_alpha, edge_contrast, wash, lenient=checking)
    source = open(LOOK).read()
    if not MARKS.search(source):
        raise SystemExit("WardLook.swift has no ward_accents.py marks")
    if checking:
        sys.exit(check(colours, table, tiers, edge_alpha, edge_contrast, wash, source))
    block = swift_table(colours)
    if "--write" in sys.argv:
        open(LOOK, "w").write(MARKS.sub(lambda _: block, source))
        print("wrote", os.path.relpath(LOOK, ROOT))
    report(colours, table)
    for n in notes:
        print("  note:", n)


if __name__ == "__main__":
    main()
