import Foundation

/// How far a soft UI surface stands off the base: a row or a chip sits low,
/// a card mid, a sheet or a floating bar high, the one hero of a screen at
/// its peak.
///
/// Not Comparable on purpose: a `<` of its own would join every `<` the
/// compiler weighs app-wide; order by `rawValue` instead.
enum WardLift: Int, CaseIterable, Sendable {
    case low = 1, mid, high, peak

    /// One step nearer the base, never below low: what a raised surface
    /// sinks to, pressed in, while it is held.
    var lower: WardLift { WardLift(rawValue: rawValue - 1) ?? .low }
}

/// One of the two lights a relief is drawn with: a colour, how strong it
/// is, where it falls (points) and how soft its edge is (blur radius,
/// points).
struct WardReliefLight: Equatable, Sendable {
    var hex: UInt32
    var alpha: Double
    var x: Double
    var y: Double
    var radius: Double

    /// Lights below the visible threshold are omitted from rendering.
    var lit: Bool { alpha > 1e-4 }
}

/// A relief: a highlight from the top left and a shade to the bottom right.
/// Raised, they are drop shadows outside the shape; pressed in (`inner`),
/// the same two fall inside it, so the shade lines the top-left wall and
/// the highlight the bottom-right one.
struct WardReliefSpec: Equatable, Sendable {
    var highlight: WardReliefLight
    var shade: WardReliefLight
    var inner: Bool
    /// The ink edge's strength; 0 draws none.
    var edgeAlpha: Double

    /// Raised to pressed in and back: the lights stay where they are.
    func mirrored() -> WardReliefSpec {
        var m = self
        m.inner.toggle()
        return m
    }
}

/// The soft UI light, per mode and lift. Foundation only, so the numbers
/// are tested on Linux (WardReliefTests); WardSurfaces draws them.
///
/// Light mode: white at 0.75 to 0.9 and a cool grey shade (#A3B1C6) at 0.5
/// to 0.65. Dark mode: white at 0.05 to 0.08, so nothing glares, and black
/// at 0.45 to 0.6. A control's face (a button, a chip, a tile to tap, a
/// field) has a 1-pt edge in the ECG paper's ink that reads at least 3:1
/// on the base (the owner, 9 Oct: buttons "not visually distinct in
/// borders", then "make the line around the buttons match the grid
/// color"), so what can
/// be pressed stands apart from what cannot; a card or a slab shows its
/// shape by its lights alone, as Retro Press draws it, with an edge only
/// under Increase Contrast. Increase Contrast deepens the shade and
/// strengthens both edges.
enum WardRelief {
    static let lightShade: UInt32 = 0xA3B1C6
    static let highContrastShadeGain = 0.15
    /// A control's edge, light and dark, in the paper's ink: about 3.3:1
    /// on the base in both (the grid's own strength would be about 2:1).
    static let lightEdge = 0.85
    static let darkEdge = 0.7
    static let highContrastEdge = 1.0
    /// A card's or a slab's edge under Increase Contrast; none otherwise.
    static let containerHighContrastEdge = 0.35
    /// The least a control's boundary may read against the base (WCAG 1.4.11).
    static let edgeContrast = 3.0

    /// A control's edge strength.
    static func edgeAlpha(dark: Bool, highContrast: Bool = false) -> Double {
        highContrast ? highContrastEdge : (dark ? darkEdge : lightEdge)
    }

    /// A card's or a slab's edge strength: 0 unless Increase Contrast is on.
    static func containerEdgeAlpha(highContrast: Bool = false) -> Double {
        highContrast ? containerHighContrastEdge : 0
    }

    /// The ink of a control's edge: the ECG paper's ink outside any
    /// section, so the edges carry on the grid and its frame line.
    static func edgeHex(dark: Bool) -> UInt32 {
        WardPaper.ink(dark: dark, highContrast: false).hex
    }

    /// A control's edge as it lands on the base.
    static func edgeColor(dark: Bool, highContrast: Bool = false) -> UInt32 {
        composite(WardReliefLight(hex: edgeHex(dark: dark),
                                  alpha: edgeAlpha(dark: dark, highContrast: highContrast),
                                  x: 0, y: 0, radius: 0), on: base(dark: dark))
    }

    /// The shade's offset from the shape, down and right; the highlight
    /// falls the same distance up and left.
    static func offset(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 2
        case .mid: return 5
        case .high: return 8
        case .peak: return 11
        }
    }

    static func radius(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 3
        case .mid: return 8
        case .high: return 12
        case .peak: return 16
        }
    }

    /// Per lift, low to peak.
    static let lightHighlight = [0.75, 0.8, 0.85, 0.9]
    static let lightShadeAlpha = [0.5, 0.55, 0.6, 0.65]
    static let darkHighlight = [0.05, 0.06, 0.07, 0.08]
    static let darkShadeAlpha = [0.45, 0.5, 0.55, 0.6]

    static func highlightAlpha(_ lift: WardLift, dark: Bool) -> Double {
        (dark ? darkHighlight : lightHighlight)[lift.rawValue - 1]
    }

    static func shadeAlpha(_ lift: WardLift, dark: Bool, highContrast: Bool = false) -> Double {
        let alpha = (dark ? darkShadeAlpha : lightShadeAlpha)[lift.rawValue - 1]
        return highContrast ? alpha + highContrastShadeGain : alpha
    }

    /// The ground both lights fall on.
    static func base(dark: Bool) -> UInt32 { WardPalette.hex(.background, dark: dark) }

    /// A surface raised off the base: a card or a slab, or with `control`
    /// a control's face, which carries the ink edge.
    static func raised(_ lift: WardLift, dark: Bool, highContrast: Bool = false,
                       control: Bool = false) -> WardReliefSpec {
        let d = offset(lift), r = radius(lift)
        return WardReliefSpec(
            highlight: WardReliefLight(hex: 0xFFFFFF, alpha: highlightAlpha(lift, dark: dark), x: -d, y: -d, radius: r),
            shade: WardReliefLight(hex: dark ? 0x000000 : lightShade,
                                   alpha: shadeAlpha(lift, dark: dark, highContrast: highContrast),
                                   x: d, y: d, radius: r),
            inner: false,
            edgeAlpha: control ? edgeAlpha(dark: dark, highContrast: highContrast)
                               : containerEdgeAlpha(highContrast: highContrast))
    }

    static func inset(_ lift: WardLift, dark: Bool, highContrast: Bool = false,
                      control: Bool = false) -> WardReliefSpec {
        raised(lift, dark: dark, highContrast: highContrast, control: control).mirrored()
    }

    // MARK: The rim: the one soft light a button keeps

    /// A button's rim (the owner, 14 Oct: "add fade to the buttons but only
    /// a very small rim around the buttons enough to make them have
    /// neumorphism but doesn't affect elements behind them"): a highlight
    /// up and left and a shade down and right, offset 2 to 3 points with a
    /// crisp blur of 2, so the whole light stays within `rimReach` of the
    /// face. That is less than the smallest gap the scale puts between two
    /// controls (WardScale.s), so a rim never reaches another control or
    /// the words beside it, and it is drawn under the face only, never over
    /// what lies behind. Nothing else in the app casts a soft light outward
    /// any more than it did: cards and slabs keep their own relief, and
    /// what floats over a page stays unlit (wardUnlit) except its buttons'
    /// rims. Raised and pressed in read alike at the old 1 to 2 points
    /// (the owner, 16 Oct: buttons "can't be distinguished between pushed
    /// and not because the button highte is a bit low"), so the rim now
    /// stands at the largest offset its reach allows, with less blur, so
    /// its edge is crisp, and a darker shade.
    static let rimReach = 5.0
    static let rimMaxBlur = 2.0
    static let rimMaxOffset = 3.0

    static func rimOffset(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 2
        case .mid: return 2.5
        case .high, .peak: return 3
        }
    }

    static func rimBlur(_ lift: WardLift) -> Double { rimMaxBlur }

    /// A small rim reads only when it is strong: stronger than the wide
    /// relief, which spreads the same light over far more of the base. The
    /// dark highlight stays at 0.1, the most it can be without glaring.
    static let rimLightHighlight = 0.95
    static let rimLightShade = 0.9
    static let rimDarkHighlight = 0.1
    static let rimDarkShade = 0.85

    /// A button's face raised by its rim, with the control's ink edge.
    static func rim(_ lift: WardLift, dark: Bool, highContrast: Bool = false) -> WardReliefSpec {
        let d = rimOffset(lift), r = rimBlur(lift)
        let shade = (dark ? rimDarkShade : rimLightShade) + (highContrast ? highContrastShadeGain : 0)
        return WardReliefSpec(
            highlight: WardReliefLight(hex: 0xFFFFFF, alpha: dark ? rimDarkHighlight : rimLightHighlight,
                                       x: -d, y: -d, radius: r),
            shade: WardReliefLight(hex: dark ? 0x000000 : lightShade, alpha: min(1, shade), x: d, y: d, radius: r),
            inner: false,
            edgeAlpha: edgeAlpha(dark: dark, highContrast: highContrast))
    }

    /// How far past the face a light can show: its offset plus its blur.
    static func reach(_ light: WardReliefLight) -> Double {
        max(abs(light.x), abs(light.y)) + light.radius
    }

    /// How much of a pressed-in face's inner shade reaches `depth` points in
    /// from its edge, 0 to 1: the shade is cast `offset` in and blurred (a
    /// SwiftUI radius is twice the blur's standard deviation), so it falls
    /// away to nothing a few points inside.
    static func shadeCoverage(_ lift: WardLift, depth: Double) -> Double {
        let sigma: Double = radius(lift) / 2
        return 0.5 * (1 - erf((depth - offset(lift)) / sigma / 2.0.squareRoot()))
    }

    /// What a pressed-in face of `fill` really is `depth` points in from its
    /// edge: the fill with the inner shade over it, as strong as it is there
    /// (Increase Contrast deepens it). This is the ground a chip's words sit
    /// on, not the bare fill.
    static func insetGround(_ fill: UInt32, lift: WardLift, dark: Bool, highContrast: Bool,
                            depth: Double) -> UInt32 {
        let alpha: Double = shadeAlpha(lift, dark: dark, highContrast: highContrast) * shadeCoverage(lift, depth: depth)
        return composite(WardReliefLight(hex: dark ? 0x000000 : lightShade, alpha: alpha, x: 0, y: 0, radius: 0),
                         on: fill)
    }

    /// What a light looks like where it lies at full strength on `base`.
    static func composite(_ light: WardReliefLight, on base: UInt32) -> UInt32 {
        let (r0, g0, b0) = WardPalette.rgb(base), (r1, g1, b1) = WardPalette.rgb(light.hex)
        func mix(_ a: Double, _ b: Double) -> UInt32 { UInt32(((a + (b - a) * light.alpha) * 255).rounded()) }
        return mix(r0, r1) << 16 | mix(g0, g1) << 8 | mix(b0, b1)
    }
}

/// Continuous control relief, independent of SwiftUI and its animation clock.
struct WardPressSpec: Equatable, Sendable {
    var blur: Double
    /// Raised, outside the face: a control's rim highlight (none for an
    /// icon tile, which keeps the softened outline it had).
    var outerHighlight: WardReliefLight
    var outerShade: WardReliefLight
    var innerShade: WardReliefLight
    var innerHighlight: WardReliefLight
    var edgeAlpha: Double
}

enum WardPress {
    static let sinkScale = 0.985
    static let press = 0.05
    static let release = 0.07
    /// The shade's glide in and out. At the old depth of 0.7 a pressed face
    /// sank too little to tell from a raised one (the owner, 16 Oct: "the
    /// pressed doesn't have much depress"), so it now sinks the whole of
    /// its lift's lights, with the inner shade a quarter stronger. Over the
    /// old times that would sink half as fast again, a snap rather than a
    /// press, so the times grow with the depth (0.15 and 0.18 at 0.7):
    /// the shade starts in at the speed it always had and goes on to the
    /// new depth. The click (press, release) keeps its time, so the face
    /// still dips at once under the finger.
    static let shadePress = 0.21
    static let shadeRelease = 0.26
    static let depth = 1.0
    static let innerShadeGain = 1.25
    static let softKeep = 0.6
    static let hollowSoft = 1.0

    static func soft(_ lift: WardLift) -> Double {
        Double(lift.rawValue + 1) / 2
    }
    static let quickCurve = (x1: 1.0 / 3, y1: 0.5, x2: 2.0 / 3, y2: 5.0 / 6)

    static func quick(_ u: Double) -> Double {
        let u = min(1, max(0, u))
        return u * (1.5 - 0.5 * u)
    }

    static func glide(_ u: Double) -> Double {
        sin(min(1, max(0, u)) * .pi / 2)
    }

    static func releaseHold(held: Double) -> Double {
        max(0, press - max(0, held))
    }

    /// A pressable face at `depth` (0 raised, 1 pressed in): a control's,
    /// with its ink edge and its rim (WardRelief.rim) and a crisp outline,
    /// unless `control` is false (an icon tile that only shows a choice),
    /// which keeps the wide shade and the softened outline. Pressed in, the
    /// lift's own lights fall inside the face, where they touch nothing else.
    static func spec(_ lift: WardLift, depth q: Double, dark: Bool,
                     highContrast: Bool = false, control: Bool = true) -> WardPressSpec {
        let q = min(1, max(0, q))
        let up = 1 - q, down = depth * q
        let raised = WardRelief.raised(lift, dark: dark, highContrast: highContrast, control: control)
        let rim = WardRelief.rim(lift, dark: dark, highContrast: highContrast)
        func light(_ original: WardReliefLight, weight: Double) -> WardReliefLight {
            WardReliefLight(hex: original.hex, alpha: original.alpha * weight,
                            x: original.x * weight, y: original.y * weight,
                            radius: original.radius * (softKeep + (1 - softKeep) * weight))
        }
        let none = WardReliefLight(hex: 0xFFFFFF, alpha: 0, x: 0, y: 0, radius: 0)
        var deeper = raised.shade
        deeper.alpha = min(1, deeper.alpha * innerShadeGain)
        return WardPressSpec(blur: control ? 0 : soft(lift) + hollowSoft * q,
                             outerHighlight: control ? light(rim.highlight, weight: up) : none,
                             outerShade: light(control ? rim.shade : raised.shade, weight: up),
                             innerShade: light(deeper, weight: down),
                             innerHighlight: light(raised.highlight, weight: down),
                             edgeAlpha: raised.edgeAlpha)
    }
}

/// ECG paper geometry and ink, independent of the rendering framework.
struct WardPaperInk: Equatable, Sendable {
    var hex: UInt32
    var fine: Double
    var bold: Double
    var edge: Double
}

/// The page's opening in the paper: its frame in points and its corner
/// radii, `radius` for the top corners and `bottomRadius` for the bottom
/// ones (equal unless the system bars set the top and bottom apart).
struct WardPaperPanel: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var radius: Double
    var bottomRadius: Double

    init(x: Double, y: Double, width: Double, height: Double, radius: Double, bottomRadius: Double? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.radius = radius
        self.bottomRadius = bottomRadius ?? radius
    }
}

/// How far the system's bars reach in from each screen edge (the window's
/// safe area insets: the status bar, the Dynamic Island, the home
/// indicator), in points.
struct WardSystemInsets: Equatable, Sendable {
    var top: Double = 0
    var bottom: Double = 0
    var left: Double = 0
    var right: Double = 0

    static let none = WardSystemInsets()
}

/// The one corner rule for anything with a radius near the screen's corner
/// (Android WardCorner): concentric with the display's own corner, so its
/// radius is the display's less its distance from the screen edge, never
/// under the element's own `floor`. A screen with square corners (device 0)
/// leaves every element at its floor.
enum WardCorner {
    static func concentric(device: Double, inset: Double, floor: Double) -> Double {
        max(floor, device - inset)
    }

    /// How near a corner must come to the frame's corner to follow it: one
    /// gutter (WardSpace.gutter).
    static let reach = WardScale.l

    /// Each corner of `element` (window points): a corner within `reach` of
    /// both edges of `frame`'s corner is concentric with it (its radius the
    /// frame corner's less the larger of the two distances, floored at
    /// `own`); every other corner keeps `own`. None is rounder than half
    /// the element's shorter side.
    static func radii(element: CGRect, frame: WardCornerFrame, own: Double, reach: Double = WardCorner.reach) -> WardCornerRadii {
        let f = frame.rect
        let left = max(0, Double(element.minX - f.minX))
        let right = max(0, Double(f.maxX - element.maxX))
        let top = max(0, Double(element.minY - f.minY))
        let bottom = max(0, Double(f.maxY - element.maxY))
        let cap = max(own, Double(min(element.width, element.height)) / 2)
        func corner(_ dx: Double, _ dy: Double, _ radius: Double) -> Double {
            dx <= reach && dy <= reach ? min(cap, concentric(device: radius, inset: max(dx, dy), floor: own)) : own
        }
        return WardCornerRadii(topLeft: corner(left, top, frame.top), topRight: corner(right, top, frame.top),
                               bottomRight: corner(right, bottom, frame.bottom),
                               bottomLeft: corner(left, bottom, frame.bottom))
    }
}

/// One radius for each corner, clockwise from the top left, in points.
struct WardCornerRadii: Equatable, Sendable {
    var topLeft: Double
    var topRight: Double
    var bottomRight: Double
    var bottomLeft: Double

    static func all(_ radius: Double) -> WardCornerRadii {
        WardCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

/// What a corner element is concentric with, in window points: the paper
/// frame's ring on a framed page (the owner, 22 Oct, "clear bars, small
/// top": things near the top take the ring's top corner), or the screen
/// with the display's own corner where there is no frame (home).
struct WardCornerFrame: Equatable, Sendable {
    var rect: CGRect
    var top: Double
    var bottom: Double

    static func screen(width: Double, height: Double, device: Double) -> WardCornerFrame {
        WardCornerFrame(rect: CGRect(x: 0, y: 0, width: width, height: height), top: device, bottom: device)
    }

    static func ring(_ panel: WardPaperPanel) -> WardCornerFrame {
        WardCornerFrame(rect: CGRect(x: panel.x, y: panel.y, width: panel.width, height: panel.height),
                        top: panel.radius, bottom: panel.bottomRadius)
    }
}

enum WardPaper {
    static let frame = 12.0
    /// Keep controls four points inside the paper frame line.
    static let sideInset = frame + 4
    static let cell = 6.0
    static let boldEvery = 5
    static let line = 1.0
    static let edgeWidth = 1.5
    static let cornerShare = 53.33 / 428
    /// The rounded iPad screen, including its smaller multitasking windows.
    static let padRadius = 18.0

    static func ink(dark: Bool, highContrast: Bool) -> WardPaperInk {
        // the ink outside any section (WardSection.outside, Cards' Care
        // Blue, the owner's hex in both modes)
        WardPaperInk(hex: 0x3B82F6,
                     fine: highContrast ? 0 : (dark ? 0.07 : 0.09),
                     bold: highContrast ? 0 : (dark ? 0.14 : 0.18),
                     edge: dark ? 0.5 : 0.55)
    }

    /// The display's corner radius. iOS gives no public value for it, so
    /// this is the corner the frame has always been drawn for: its
    /// opening's share of the width (cornerShare) plus the frame, or the
    /// iPad's 18 points plus the frame. It is also the fallback for a
    /// device that reports none.
    static func deviceRadius(width: Double, height: Double, pad: Bool = false) -> Double {
        pad ? padRadius + frame : (min(width, height) - 2 * frame) * cornerShare + frame
    }

    /// The opening's edge on a side whose system bar reaches `inset` in:
    /// the frame's own 12 points, or just past the bar, so the ring's whole
    /// width lies clear of it (the owner, 22 Oct: the frame never crosses a
    /// system bar).
    static func edge(_ inset: Double) -> Double { max(frame, inset + edgeWidth / 2) }

    /// Where page content starts on a side whose bar reaches `inset` in:
    /// sideInset past it (SkyRoot's padding inside the safe area).
    static func contentEdge(_ inset: Double) -> Double { inset + sideInset }

    /// The opening clear of the system bars (`safe`), its corners
    /// concentric with the display's corner `device` (nil: deviceRadius):
    /// each corner is WardCorner.concentric of its larger distance from the
    /// two screen edges it meets, floored at WardEdge.minRadius.
    static func panel(width: Double, height: Double, safe: WardSystemInsets, device: Double?,
                      pad: Bool = false) -> WardPaperPanel? {
        guard width > 4 * frame, height > 4 * frame else { return nil }
        let left = edge(safe.left), right = edge(safe.right), top = edge(safe.top), bottom = edge(safe.bottom)
        let w = width - left - right, h = height - top - bottom
        guard w > 2 * frame, h > 2 * frame else { return nil }
        let d = device ?? deviceRadius(width: width, height: height, pad: pad)
        let side = max(left, right)
        // a continuous corner reaches 1.53 radii along each edge: two must fit
        let cap = min(w, h) / (2 * 1.52866483)
        func corner(_ inset: Double) -> Double {
            min(cap, WardCorner.concentric(device: d, inset: max(side, inset), floor: WardEdge.minRadius))
        }
        return WardPaperPanel(x: left, y: top, width: w, height: h, radius: corner(top), bottomRadius: corner(bottom))
    }

    /// As panel(width:height:safe:device:pad:), its top moved down to `top`,
    /// held to what fits.
    static func panel(width: Double, height: Double, top: Double, safe: WardSystemInsets, device: Double?,
                      pad: Bool = false) -> WardPaperPanel? {
        guard var p = panel(width: width, height: height, safe: safe, device: device, pad: pad) else { return nil }
        let bottom = p.y + p.height
        let y = min(max(top, p.y), bottom - p.radius - p.bottomRadius)
        guard y > p.y else { return p }
        p.y = y
        p.height = bottom - y
        return p
    }

    static func panel(width: Double, height: Double, pad: Bool = false) -> WardPaperPanel? {
        guard width > 4 * frame, height > 4 * frame else { return nil }
        return WardPaperPanel(x: frame, y: frame,
                              width: width - 2 * frame, height: height - 2 * frame,
                              radius: pad ? padRadius : (min(width, height) - 2 * frame) * cornerShare)
    }

    /// The panel with its top moved down to `top` (window points): the home
    /// page's opening starts under its header, the paper solid above it,
    /// with the frame's own corners (the owner, 9 Oct: the line under the
    /// header "with the roundedness of it and continuity with the rest of
    /// the grid line"). A `top` above the frame's, or too low to leave room
    /// for both corners, is held to what fits.
    static func panel(width: Double, height: Double, top: Double, pad: Bool = false) -> WardPaperPanel? {
        guard var p = panel(width: width, height: height, pad: pad) else { return nil }
        let bottom = p.y + p.height
        let y = min(max(top, p.y), bottom - 2 * p.radius)
        guard y > p.y else { return p }
        p.y = y
        p.height = bottom - y
        return p
    }

    static func lines(_ length: Double) -> [(at: Double, bold: Bool)] {
        lines(length, from: 0)
    }

    /// The frame's lines (k·cell, bold every fifth) that fall in
    /// [origin, origin + length), in positions local to `origin`: a band
    /// that starts at a global `origin` lines up with the frame's grid.
    static func lines(_ length: Double, from origin: Double) -> [(at: Double, bold: Bool)] {
        guard length > 0, origin.isFinite, length.isFinite else { return [] }
        var result: [(at: Double, bold: Bool)] = []
        var k = Int((origin / cell).rounded(.up))
        while Double(k) * cell < origin + length {
            let at = Double(k) * cell - origin
            if at >= 0 {
                result.append((at: at, bold: ((k % boldEvery) + boldEvery) % boldEvery == 0))
            }
            k += 1
        }
        return result
    }
}

/// One end of a line across the frame's opening: the circular arc from the
/// line down to the opening's outline, tangent to both.
struct WardEdgeCorner: Equatable, Sendable {
    var center: SIMD2<Double>
    var radius: Double
    /// where the arc leaves the line: center.x
    var lineX: Double
    /// where the arc meets the outline, tangent to it
    var join: SIMD2<Double>
}

/// A line across the opening at `y`, with its ends joined to the outline.
struct WardEdgeJoin: Equatable, Sendable {
    var y: Double
    var left: WardEdgeCorner?
    var right: WardEdgeCorner?
    /// the straight line's ends: an arc's lineX, or, on a joined side with
    /// no room for an arc, where the line meets the outline; nil on a side
    /// that is not joined (the caller keeps its own end there)
    var fromX: Double?
    var toX: Double?
}

enum WardEdge {
    static let minRadius = 12.0

    private static func cubicPoint(p0: SIMD2<Double>, p1: SIMD2<Double>, p2: SIMD2<Double>, p3: SIMD2<Double>, t: Double) -> SIMD2<Double> {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        return uuu * p0 + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + ttt * p3
    }

    private static func sampleCubic(p0: SIMD2<Double>, p1: SIMD2<Double>, p2: SIMD2<Double>, p3: SIMD2<Double>, n: Int) -> [SIMD2<Double>] {
        guard n > 0 else { return [p3] }
        var points: [SIMD2<Double>] = []
        points.reserveCapacity(n)
        for i in 1...n {
            let t = Double(i) / Double(n)
            points.append(cubicPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t))
        }
        return points
    }

    /// The panel's outline with iOS continuous corners, a closed polyline,
    /// clockwise from the top edge's left end of straight run.
    static func outline(_ panel: WardPaperPanel, pointsPerCurve: Int = 24) -> [SIMD2<Double>] {
        guard pointsPerCurve > 0 else { return [] }
        let minX = panel.x
        let maxX = panel.x + panel.width
        let minY = panel.y
        let maxY = panel.y + panel.height
        let r = panel.radius
        // the bottom corners' own radius
        let b = panel.bottomRadius
        let c = 1.52866483

        // Start at top edge's left end of straight run
        var poly: [SIMD2<Double>] = [SIMD2<Double>(minX + c * r, minY)]

        // 1. Top straight run to top-right corner start
        poly.append(SIMD2<Double>(maxX - c * r, minY))

        // 2. Top-right corner (3 cubics)
        let tr_c1_p0 = SIMD2<Double>(maxX - 1.52866483 * r, minY)
        let tr_c1_p1 = SIMD2<Double>(maxX - 1.08849299 * r, minY)
        let tr_c1_p2 = SIMD2<Double>(maxX - 0.86840701 * r, minY)
        let tr_c1_p3 = SIMD2<Double>(maxX - 0.63149399 * r, minY + 0.07491100 * r)

        let tr_c2_p0 = tr_c1_p3
        let tr_c2_p1 = SIMD2<Double>(maxX - 0.37282401 * r, minY + 0.16905501 * r)
        let tr_c2_p2 = SIMD2<Double>(maxX - 0.16905501 * r, minY + 0.37282401 * r)
        let tr_c2_p3 = SIMD2<Double>(maxX - 0.07491100 * r, minY + 0.63149399 * r)

        let tr_c3_p0 = tr_c2_p3
        let tr_c3_p1 = SIMD2<Double>(maxX, minY + 0.86840701 * r)
        let tr_c3_p2 = SIMD2<Double>(maxX, minY + 1.08849299 * r)
        let tr_c3_p3 = SIMD2<Double>(maxX, minY + 1.52866483 * r)

        poly.append(contentsOf: sampleCubic(p0: tr_c1_p0, p1: tr_c1_p1, p2: tr_c1_p2, p3: tr_c1_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: tr_c2_p0, p1: tr_c2_p1, p2: tr_c2_p2, p3: tr_c2_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: tr_c3_p0, p1: tr_c3_p1, p2: tr_c3_p2, p3: tr_c3_p3, n: pointsPerCurve))

        // 3. Right straight run
        poly.append(SIMD2<Double>(maxX, maxY - c * b))

        // 4. Bottom-right corner (mirroring TR)
        func brPoint(u: Double, v: Double) -> SIMD2<Double> {
            SIMD2<Double>(maxX - b * v, maxY + b * u)
        }
        let br_c1_p0 = brPoint(u: -1.52866483, v: 0)
        let br_c1_p1 = brPoint(u: -1.08849299, v: 0)
        let br_c1_p2 = brPoint(u: -0.86840701, v: 0)
        let br_c1_p3 = brPoint(u: -0.63149399, v: 0.07491100)

        let br_c2_p0 = br_c1_p3
        let br_c2_p1 = brPoint(u: -0.37282401, v: 0.16905501)
        let br_c2_p2 = brPoint(u: -0.16905501, v: 0.37282401)
        let br_c2_p3 = brPoint(u: -0.07491100, v: 0.63149399)

        let br_c3_p0 = br_c2_p3
        let br_c3_p1 = brPoint(u: 0, v: 0.86840701)
        let br_c3_p2 = brPoint(u: 0, v: 1.08849299)
        let br_c3_p3 = brPoint(u: 0, v: 1.52866483)

        poly.append(contentsOf: sampleCubic(p0: br_c1_p0, p1: br_c1_p1, p2: br_c1_p2, p3: br_c1_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: br_c2_p0, p1: br_c2_p1, p2: br_c2_p2, p3: br_c2_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: br_c3_p0, p1: br_c3_p1, p2: br_c3_p2, p3: br_c3_p3, n: pointsPerCurve))

        // 5. Bottom straight run
        poly.append(SIMD2<Double>(minX + c * b, maxY))

        // 6. Bottom-left corner (mirroring TR)
        func blPoint(u: Double, v: Double) -> SIMD2<Double> {
            SIMD2<Double>(minX - b * u, maxY - b * v)
        }
        let bl_c1_p0 = blPoint(u: -1.52866483, v: 0)
        let bl_c1_p1 = blPoint(u: -1.08849299, v: 0)
        let bl_c1_p2 = blPoint(u: -0.86840701, v: 0)
        let bl_c1_p3 = blPoint(u: -0.63149399, v: 0.07491100)

        let bl_c2_p0 = bl_c1_p3
        let bl_c2_p1 = blPoint(u: -0.37282401, v: 0.16905501)
        let bl_c2_p2 = blPoint(u: -0.16905501, v: 0.37282401)
        let bl_c2_p3 = blPoint(u: -0.07491100, v: 0.63149399)

        let bl_c3_p0 = bl_c2_p3
        let bl_c3_p1 = blPoint(u: 0, v: 0.86840701)
        let bl_c3_p2 = blPoint(u: 0, v: 1.08849299)
        let bl_c3_p3 = blPoint(u: 0, v: 1.52866483)

        poly.append(contentsOf: sampleCubic(p0: bl_c1_p0, p1: bl_c1_p1, p2: bl_c1_p2, p3: bl_c1_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: bl_c2_p0, p1: bl_c2_p1, p2: bl_c2_p2, p3: bl_c2_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: bl_c3_p0, p1: bl_c3_p1, p2: bl_c3_p2, p3: bl_c3_p3, n: pointsPerCurve))

        // 7. Left straight run
        poly.append(SIMD2<Double>(minX, minY + c * r))

        // 8. Top-left corner (mirroring TR)
        func tlPoint(u: Double, v: Double) -> SIMD2<Double> {
            SIMD2<Double>(minX + r * v, minY - r * u)
        }
        let tl_c1_p0 = tlPoint(u: -1.52866483, v: 0)
        let tl_c1_p1 = tlPoint(u: -1.08849299, v: 0)
        let tl_c1_p2 = tlPoint(u: -0.86840701, v: 0)
        let tl_c1_p3 = tlPoint(u: -0.63149399, v: 0.07491100)

        let tl_c2_p0 = tl_c1_p3
        let tl_c2_p1 = tlPoint(u: -0.37282401, v: 0.16905501)
        let tl_c2_p2 = tlPoint(u: -0.16905501, v: 0.37282401)
        let tl_c2_p3 = tlPoint(u: -0.07491100, v: 0.63149399)

        let tl_c3_p0 = tl_c2_p3
        let tl_c3_p1 = tlPoint(u: 0, v: 0.86840701)
        let tl_c3_p2 = tlPoint(u: 0, v: 1.08849299)
        let tl_c3_p3 = tlPoint(u: 0, v: 1.52866483)

        poly.append(contentsOf: sampleCubic(p0: tl_c1_p0, p1: tl_c1_p1, p2: tl_c1_p2, p3: tl_c1_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: tl_c2_p0, p1: tl_c2_p1, p2: tl_c2_p2, p3: tl_c2_p3, n: pointsPerCurve))
        poly.append(contentsOf: sampleCubic(p0: tl_c3_p0, p1: tl_c3_p1, p2: tl_c3_p2, p3: tl_c3_p3, n: pointsPerCurve))

        return poly
    }

    private static func closestPointOnSegment(p: SIMD2<Double>, a: SIMD2<Double>, b: SIMD2<Double>) -> (point: SIMD2<Double>, dist: Double) {
        let ab = b - a
        let abLenSq = ab.x * ab.x + ab.y * ab.y
        if abLenSq < 1e-12 {
            let d = hypot(p.x - a.x, p.y - a.y)
            return (a, d)
        }
        let t = max(0.0, min(1.0, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / abLenSq))
        let proj = a + t * ab
        let d = hypot(p.x - proj.x, p.y - proj.y)
        return (proj, d)
    }

    private static func horizontalCrossing(poly: [SIMD2<Double>], y: Double, left: Bool) -> Double? {
        guard poly.count >= 2 else { return nil }
        var xs: [Double] = []
        for i in 0..<(poly.count - 1) {
            let p1 = poly[i]
            let p2 = poly[i + 1]
            let minY = min(p1.y, p2.y)
            let maxY = max(p1.y, p2.y)
            if y >= minY && y <= maxY && p1.y != p2.y {
                let t = (y - p1.y) / (p2.y - p1.y)
                let x = p1.x + t * (p2.x - p1.x)
                xs.append(x)
            }
        }
        if xs.isEmpty { return nil }
        return left ? xs.min() : xs.max()
    }

    private static func solveLeftCorner(outline: [SIMD2<Double>], y: Double, radius: Double,
                                        midX: Double, maxY: Double) -> (WardEdgeCorner?, fromX: Double?) {
        let room = maxY - y
        let r = min(radius, room / 2.0)
        guard r >= minRadius else {
            let fromX = horizontalCrossing(poly: outline, y: y, left: true)
            return (nil, fromX)
        }
        let cy = y + r
        guard let lowX = horizontalCrossing(poly: outline, y: cy, left: true) else {
            return (nil, nil)
        }

        func distToOuter(c: SIMD2<Double>) -> (dist: Double, nearest: SIMD2<Double>) {
            var bestDist = Double.infinity
            var bestPoint = c
            for i in 0..<(outline.count - 1) {
                let (proj, d) = closestPointOnSegment(p: c, a: outline[i], b: outline[i + 1])
                // Outer side is x < c.x (touching the bottom edge straight below has x == c.x, which is not the join)
                if proj.x < c.x - 1e-9 {
                    if d < bestDist {
                        bestDist = d
                        bestPoint = proj
                    }
                }
            }
            return (bestDist, bestPoint)
        }

        var lo = lowX
        var hi = midX
        for _ in 0..<60 {
            let mid = (lo + hi) / 2.0
            let (d, _) = distToOuter(c: SIMD2<Double>(mid, cy))
            if d < r {
                lo = mid
            } else {
                hi = mid
            }
        }
        let cx = (lo + hi) / 2.0
        let (_, join) = distToOuter(c: SIMD2<Double>(cx, cy))
        let corner = WardEdgeCorner(center: SIMD2<Double>(cx, cy), radius: r, lineX: cx, join: join)
        return (corner, cx)
    }

    /// The line at `y` across the opening whose outline is `outline`, its
    /// ends joined on the sides asked for, with arcs of `radius` or the
    /// largest that fits. nil when y is not inside the opening.
    static func join(outline: [SIMD2<Double>], y: Double, radius: Double,
                     left: Bool = true, right: Bool = true) -> WardEdgeJoin? {
        guard outline.count >= 3 else { return nil }
        var minY = Double.infinity
        var maxY = -Double.infinity
        var minX = Double.infinity
        var maxX = -Double.infinity
        for pt in outline {
            if pt.y < minY { minY = pt.y }
            if pt.y > maxY { maxY = pt.y }
            if pt.x < minX { minX = pt.x }
            if pt.x > maxX { maxX = pt.x }
        }

        guard y > minY, y < maxY else { return nil }
        let midX = (minX + maxX) / 2.0

        var leftCorner: WardEdgeCorner? = nil
        var rightCorner: WardEdgeCorner? = nil
        var fromX: Double? = nil
        var toX: Double? = nil

        if left {
            let res = solveLeftCorner(outline: outline, y: y, radius: radius, midX: midX, maxY: maxY)
            leftCorner = res.0
            fromX = res.fromX
        }

        if right {
            // Mirror outline horizontally about midX so the left solver solves the right side symmetrically
            let mirroredOutline = outline.map { SIMD2<Double>(2.0 * midX - $0.x, $0.y) }
            let res = solveLeftCorner(outline: mirroredOutline, y: y, radius: radius, midX: midX, maxY: maxY)
            if let mc = res.0 {
                let rx = 2.0 * midX - mc.center.x
                let jx = 2.0 * midX - mc.join.x
                rightCorner = WardEdgeCorner(center: SIMD2<Double>(rx, mc.center.y),
                                             radius: mc.radius,
                                             lineX: rx,
                                             join: SIMD2<Double>(jx, mc.join.y))
                toX = rx
            } else if let mFromX = res.fromX {
                toX = 2.0 * midX - mFromX
            }
        }

        return WardEdgeJoin(y: y, left: leftCorner, right: rightCorner, fromX: fromX, toX: toX)
    }

    /// The slab's top corner radius on one side (`leading`: its left side
    /// at x `slabSide`; otherwise its right side): `base` unless its top edge
    /// would run past where the arc leaves the line.
    static func slabTopRadius(_ corner: WardEdgeCorner?, slabSide: Double,
                              leading: Bool, base: Double = 24) -> Double {
        guard let corner else { return base }
        let diff = leading ? (corner.lineX - slabSide) : (slabSide - corner.lineX)
        return max(base, diff)
    }
}
