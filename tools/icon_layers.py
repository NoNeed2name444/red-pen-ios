#!/usr/bin/env python3
"""Stethoscore's app icon, redrawn as vector layers for iOS 26 (Icon Composer).

The chosen render (design/icon/source.png) is one flat picture; iOS 26 lights
and moves an icon layer by layer (Liquid Glass), so each element of the render
is redrawn here as numbers, on Icon Composer's 1024-point canvas, and written
three ways from the same numbers so they can never drift apart:

    design/icon/layers/<n>-<layer>.svg       one SVG per layer, back to front
    ios/AppResources/AppIcon.icon/           the Icon Composer bundle: icon.json
                                             and Assets/ (the foreground SVGs)
    ios/RedPen/Shared/Brand/IconLayers.swift the same layers as SwiftUI, so the
                                             app can draw (and animate) the icon

    python3 tools/icon_layers.py            write all three
    python3 tools/icon_layers.py --check    exit 1 if any of them is out of date

The background tile is the icon's own fill in icon.json (Apple: give the
system the background as a fill, not as artwork), and an SVG layer for
everything else. The layer order, names and groups are IconLayerSpec.swift's;
the "iconlayers" Swift suite checks the files against it.
"""
from __future__ import annotations

import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYERS_DIR = ROOT / "design/icon/layers"
BUNDLE = ROOT / "ios/AppResources/AppIcon.icon"
SWIFT = ROOT / "ios/RedPen/Shared/Brand/IconLayers.swift"
S = 1024  # Icon Composer's canvas, in points

# ---- the drawing -----------------------------------------------------------
# A path is a list of ("M", x, y) / ("L", x, y) / ("C", x1, y1, x2, y2, x, y).
# A paint is ("solid", hex) or ("linear", x1, y1, x2, y2, [(offset, hex), ...])
# in canvas points. Elements:
#   ("stroke", path, width, paint)               round caps and joins
#   ("circle", cx, cy, r, paint)
#   ("ellipse", cx, cy, rx, ry, degrees, paint)
#   ("shape", [path, ...], paint)                closed, even-odd (holes)
#   ("rect", paint)                              the whole canvas

def lin(x1, y1, x2, y2, *stops):
    return ("linear", x1, y1, x2, y2, list(stops))

TUBE_EDGE, TUBE = "07307A", "0E49AE"
METAL_EDGE, METAL = "7B818D", "D3D6DC"

LEFT_BRANCH = [("M", 190, 392), ("C", 186, 480, 205, 545, 268, 560)]
RIGHT_BRANCH = [("M", 442, 428), ("C", 400, 500, 345, 548, 268, 560)]
MAIN = [("M", 268, 560), ("C", 238, 620, 238, 740, 300, 800),
        ("C", 360, 860, 470, 905, 560, 900), ("C", 660, 893, 720, 830, 742, 760),
        ("L", 760, 648)]
LOOP_C = (488, 720, 120)
LEFT_BINAURAL = [("M", 300, 128), ("C", 240, 118, 178, 140, 172, 225), ("L", 190, 400)]
RIGHT_BINAURAL = [("M", 466, 152), ("C", 530, 150, 566, 205, 546, 266), ("L", 440, 436)]
STEM = [("M", 768, 590), ("L", 759, 648)]
CHEST = (790, 478)

def tube(*paths):
    # every outline first, then every core, so pieces that meet show no seam
    return ([("stroke", p, 48, ("solid", TUBE_EDGE)) for p in paths]
            + [("stroke", p, 36, ("solid", TUBE)) for p in paths])

def metal(path, w=26):
    return [("stroke", path, w, ("solid", METAL_EDGE)), ("stroke", path, w - 10, ("solid", METAL))]

def loop():
    cx, cy, r = LOOP_C
    k = r * 0.5523  # a circle as four curves, so it strokes like the rest
    p = [("M", cx + r, cy), ("C", cx + r, cy + k, cx + k, cy + r, cx, cy + r),
         ("C", cx - k, cy + r, cx - r, cy + k, cx - r, cy),
         ("C", cx - r, cy - k, cx - k, cy - r, cx, cy - r),
         ("C", cx + k, cy - r, cx + r, cy - k, cx + r, cy)]
    return tube(p)

def grade():
    a = [("M", 734, 521), ("L", 765, 428), ("L", 795, 428), ("L", 826, 521), ("L", 801, 521),
         ("L", 794, 500), ("L", 766, 500), ("L", 759, 521)]
    hole = [("M", 772, 478), ("L", 788, 478), ("L", 780, 451)]
    px, py, arm, t = 852, 468, 22, 8
    plus = [("M", px - t, py - arm), ("L", px + t, py - arm), ("L", px + t, py - t), ("L", px + arm, py - t),
            ("L", px + arm, py + t), ("L", px + t, py + t), ("L", px + t, py + arm), ("L", px - t, py + arm),
            ("L", px - t, py + t), ("L", px - arm, py + t), ("L", px - arm, py - t), ("L", px - t, py - t)]
    ink = ("solid", "0E3C8C")
    return [("shape", [a, hole], ink), ("shape", [plus], ink)]

def chest_piece():
    x, y = CHEST
    return [
        ("circle", x, y, 132, lin(x - 100, y - 120, x + 100, y + 120, (0, "F4F5F7"), (0.55, "B9BDC6"), (1, "7D838F"))),
        ("circle", x, y, 116, ("solid", "4A4E58")),
        ("circle", x, y, 102, lin(x + 80, y + 90, x - 80, y - 90, (0, "C4C8CF"), (1, "F6F6F8"))),
        ("circle", x, y, 88, lin(x - 60, y - 80, x + 60, y + 80, (0, "FAFAFB"), (1, "D3D5DA"))),
    ]

def earpieces():
    bud = lin(0, 105, 0, 185, (0, "FFFFFF"), (1, "D6D8DD"))
    return [("ellipse", 316, 138, 40, 32, -5, bud), ("ellipse", 452, 152, 40, 32, 8, bud)]

# Back to front, matching IconLayerSpec.swift: (spec name, Icon Composer group, elements).
LAYERS = [
    ("background", None, [("rect", lin(330, 0, 694, S, (0, "5BBDF9"), (0.45, "2C84EE"), (1, "1849D4")))]),
    ("metal", "Metal", metal(LEFT_BINAURAL) + metal(RIGHT_BINAURAL) + metal(STEM, 34)),
    ("tubing", "Tubing", tube(MAIN, LEFT_BRANCH, RIGHT_BRANCH) + loop()),
    ("earpieces", "Earpieces", earpieces()),
    ("chest-piece", "Chest piece", chest_piece()),
    ("a-plus", "Chest piece", grade()),
]
# The icon's fill: the background tile's gradient, top-left sky to bottom-right royal.
FILL = {"linear-gradient": ["srgb:0.35686,0.74118,0.97647,1.00000", "srgb:0.09412,0.28627,0.83137,1.00000"],
        "orientation": {"start": {"x": 0.32, "y": 0}, "stop": {"x": 0.68, "y": 1}}}

def asset_name(i, name):
    return f"{i}-{name}.svg"

# ---- SVG ---------------------------------------------------------------------
def n(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")

def svg_d(path):
    return " ".join(c[0] + " ".join(n(v) for v in c[1:]) for c in path)

def svg(name, elements):
    defs, body = [], []
    def paint(p):
        if p[0] == "solid": return f"#{p[1]}"
        gid = f"g{len(defs)}"
        stops = "".join(f'<stop offset="{n(o)}" stop-color="#{c}"/>' for o, c in p[5])
        defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{n(p[1])}" y1="{n(p[2])}" '
                    f'x2="{n(p[3])}" y2="{n(p[4])}">{stops}</linearGradient>')
        return f"url(#{gid})"
    for e in elements:
        k = e[0]
        if k == "stroke":
            body.append(f'<path d="{svg_d(e[1])}" fill="none" stroke="{paint(e[3])}" stroke-width="{n(e[2])}" '
                        'stroke-linecap="round" stroke-linejoin="round"/>')
        elif k == "circle":
            body.append(f'<circle cx="{n(e[1])}" cy="{n(e[2])}" r="{n(e[3])}" fill="{paint(e[4])}"/>')
        elif k == "ellipse":
            body.append(f'<ellipse cx="{n(e[1])}" cy="{n(e[2])}" rx="{n(e[3])}" ry="{n(e[4])}" '
                        f'transform="rotate({n(e[5])} {n(e[1])} {n(e[2])})" fill="{paint(e[6])}"/>')
        elif k == "shape":
            d = " ".join(svg_d(p) + " Z" for p in e[1])
            body.append(f'<path d="{d}" fill="{paint(e[2])}" fill-rule="evenodd"/>')
        elif k == "rect":
            body.append(f'<rect x="0" y="0" width="{S}" height="{S}" fill="{paint(e[1])}"/>')
    d = f"<defs>{''.join(defs)}</defs>" if defs else ""
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<!-- Stethoscore icon, layer "{name}". Generated by tools/icon_layers.py; edit that, not this. -->\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}" id="{name}">\n'
            + (d + "\n" if d else "") + "\n".join(body) + "\n</svg>\n")

# ---- icon.json -----------------------------------------------------------------
def icon_json():
    groups = {}
    for i, (name, group, _) in enumerate(LAYERS):
        if group: groups.setdefault(group, []).append({"glass": True, "image-name": asset_name(i, name), "name": name})
    # Icon Composer lists groups, and the layers in each, front first.
    out = [{"layers": list(reversed(layers)), "name": g, "shadow": {"kind": "neutral", "opacity": 0.5},
            "specular": True, "translucency": {"enabled": False, "value": 0.5}}
           for g, layers in reversed(list(groups.items()))]
    # No "color-space-for-untagged-svg-colors": actool in Xcode 26.4-26.6
    # crashes on it ("attempt to insert nil object"); untagged SVG is sRGB anyway.
    return json.dumps({"fill": FILL, "groups": out,
                       "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}},
                      indent=2, sort_keys=True) + "\n"

# ---- SwiftUI -------------------------------------------------------------------
def sw(v):
    return n(v)

def sw_path(paths, close=False):
    out = []
    for path in paths:
        for c in path:
            if c[0] == "M": out.append(f"p.move(to: P({sw(c[1])}, {sw(c[2])}))")
            elif c[0] == "L": out.append(f"p.addLine(to: P({sw(c[1])}, {sw(c[2])}))")
            else: out.append(f"p.addCurve(to: P({sw(c[5])}, {sw(c[6])}), control1: P({sw(c[1])}, {sw(c[2])}), "
                             f"control2: P({sw(c[3])}, {sw(c[4])}))")
        if close: out.append("p.closeSubpath()")
    return "Path { p in " + "; ".join(out) + " }"

def sw_paint(p):
    if p[0] == "solid": return f".color(hex(0x{p[1]}))"
    stops = ", ".join(f"(0x{c}, {sw(o)})" for o, c in p[5])
    return f"lin(P({sw(p[1])}, {sw(p[2])}), P({sw(p[3])}, {sw(p[4])}), [{stops}])"

def sw_element(e):
    k = e[0]
    if k == "stroke":
        return f"c.stroke({sw_path([e[1]])}, with: {sw_paint(e[3])}, style: line({sw(e[2])}))"
    if k == "circle":
        x, y, r = e[1:4]
        return f"c.fill(Path(ellipseIn: CGRect(x: {sw(x - r)}, y: {sw(y - r)}, width: {sw(2 * r)}, height: {sw(2 * r)})), with: {sw_paint(e[4])})"
    if k == "ellipse":
        x, y, rx, ry, deg = e[1:6]
        return (f"c.fill(oval({sw(x)}, {sw(y)}, {sw(rx)}, {sw(ry)}, degrees: {sw(deg)}), with: {sw_paint(e[6])})")
    if k == "shape":
        return f"c.fill({sw_path(e[1], close=True)}, with: {sw_paint(e[2])}, style: FillStyle(eoFill: true))"
    if k == "rect":
        return f"c.fill(Path(CGRect(x: 0, y: 0, width: {S}, height: {S})), with: {sw_paint(e[1])})"

def swift():
    cases = []
    for name, _, elements in LAYERS:
        body = "\n".join("            " + sw_element(e) for e in elements)
        cases.append(f"        case .{swift_case(name)}:\n{body}")
    return f'''// Generated by tools/icon_layers.py from the same numbers as design/icon/layers
// and AppIcon.icon - edit the script and run it, not this file.
#if canImport(SwiftUI)
import SwiftUI

/// The app icon drawn in the app, layer by layer, on Icon Composer's
/// 1024-point canvas scaled to fit: `IconLayersView()` is the whole icon, and
/// `IconLayerView(layer:)` one layer, so a screen can move or light them apart.
struct IconLayersView: View {{
    var layers: [IconLayer] = IconLayer.allCases
    var body: some View {{
        ZStack {{ ForEach(layers, id: \\.self) {{ IconLayerView(layer: $0) }} }}
            .aspectRatio(1, contentMode: .fit)
            .clipShape(IconTile())
    }}
}}

/// The rounded tile iOS cuts every icon to.
struct IconTile: Shape {{
    func path(in r: CGRect) -> Path {{
        RoundedRectangle(cornerRadius: 0.2237 * min(r.width, r.height), style: .continuous).path(in: r)
    }}
}}

struct IconLayerView: View {{
    let layer: IconLayer
    var body: some View {{
        Canvas {{ ctx, size in
            var c = ctx
            c.scaleBy(x: size.width / {S}, y: size.height / {S})
            IconLayerArt.draw(layer, in: c)
        }}
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }}
}}

private enum IconLayerArt {{
    static func draw(_ layer: IconLayer, in c: GraphicsContext) {{
        switch layer {{
{chr(10).join(cases)}
        }}
    }}
    private static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ CGPoint(x: x, y: y) }}
    private static func hex(_ v: UInt32) -> Color {{
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }}
    private static func lin(_ a: CGPoint, _ b: CGPoint, _ stops: [(UInt32, Double)]) -> GraphicsContext.Shading {{
        .linearGradient(Gradient(stops: stops.map {{ .init(color: hex($0.0), location: $0.1) }}), startPoint: a, endPoint: b)
    }}
    private static func line(_ w: CGFloat) -> StrokeStyle {{ StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }}
    private static func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, degrees: Double) -> Path {{
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(CGAffineTransform(translationX: x, y: y)))
    }}
}}
#endif
'''

def swift_case(name):
    head, *rest = name.split("-")
    return head + "".join(w.capitalize() for w in rest)

# ---- write ---------------------------------------------------------------------
def outputs():
    files = {}
    for i, (name, group, elements) in enumerate(LAYERS):
        text = svg(name, elements)
        files[LAYERS_DIR / asset_name(i, name)] = text
        if group: files[BUNDLE / "Assets" / asset_name(i, name)] = text
    files[BUNDLE / "icon.json"] = icon_json()
    files[SWIFT] = swift()
    return files

def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for path, text in outputs().items():
        if path.exists() and path.read_text() == text: continue
        stale.append(path.relative_to(ROOT))
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    for p in stale: print(("stale " if check else "wrote ") + str(p))
    return 1 if check and stale else 0

if __name__ == "__main__":
    sys.exit(main())
