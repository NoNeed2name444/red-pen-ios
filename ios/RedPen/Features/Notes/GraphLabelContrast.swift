import Foundation

// MARK: - Name pills that stay readable
//
// The owner: "make the headlines of the nodes react and change in color
// according to what is behind them to keep being visible and visually clear
// and readable". A body's name pill must read over a bright star, a
// supernova's flash, a glowing cell, a lit LED, the dark board or bench, or
// a pale nebula.
//
// How the background is measured: ESTIMATED from the scene, not read back
// from the frame. GraphSim already knows, every frame and under its lock,
// where every body is, how big it is drawn and (from its look, set when the
// scene is built) how bright and what colour it and its halo are, plus the
// theme's backdrop; a dying body's flash is asked of the death stage. Five
// points across each shown pill are tested against those glows, a few
// times a second (GraphLabelSampler.interval). Reading the rendered frame
// back was the alternative, and was turned down: SCNView's drawable is
// framebuffer-only (not readable without private access to its Metal
// layer), `snapshot()` renders the whole scene again on the main thread
// (several milliseconds, a visible hitch at 120 Hz), and an SCNRenderer at
// low resolution is a second full render of every shader each time. The
// estimate costs a few hundred multiplications per label, runs where the
// labels are already moved, and is the same on every device, simulator and
// Playgrounds build.
//
// Then the style (GraphLabelChooser): dark or light words by WCAG contrast
// (at least 4.5:1 against the measured background, through the pill), the
// pill more opaque where the background is bright or busy, an outline and
// a shadow when the contrast is still marginal, tinted a little towards the
// body's own colour. Increase Contrast always takes the strongest style,
// Reduce Transparency an opaque pill. GraphLabelTracker eases between
// styles over about 0.3 s with hysteresis, so a planet orbiting behind a
// name never makes it flicker.
//
// Pure Foundation, tested on Linux (Tests/GraphLabelTests.swift).

/// A colour, sRGB, each channel 0...1.
nonisolated struct GraphRGB: Sendable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let black = GraphRGB(0, 0, 0)
    static let white = GraphRGB(1, 1, 1)

    /// `self` over `under`, `alpha` of the way.
    func over(_ under: GraphRGB, alpha: Double) -> GraphRGB {
        let a: Double = min(max(alpha, 0), 1)
        let rr: Double = r * a + under.r * (1 - a)
        let gg: Double = g * a + under.g * (1 - a)
        let bb: Double = b * a + under.b * (1 - a)
        return GraphRGB(rr, gg, bb)
    }

    /// `amount` of the way to `other`.
    func mixed(_ other: GraphRGB, _ amount: Double) -> GraphRGB {
        other.over(self, alpha: amount)
    }

    /// Light added on top, each channel held at 1.
    func adding(_ other: GraphRGB, _ amount: Double) -> GraphRGB {
        let rr: Double = min(r + other.r * amount, 1)
        let gg: Double = min(g + other.g * amount, 1)
        let bb: Double = min(b + other.b * amount, 1)
        return GraphRGB(rr, gg, bb)
    }

    var clamped: GraphRGB {
        GraphRGB(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        GraphContrast.luminance(self)
    }
}

nonisolated enum GraphContrast {
    /// One sRGB channel, linearised (WCAG 2).
    static func linear(_ c: Double) -> Double {
        let v: Double = min(max(c, 0), 1)
        if v <= 0.04045 { return v / 12.92 }
        return pow((v + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    static func luminance(_ c: GraphRGB) -> Double {
        let r: Double = linear(c.r) * 0.2126
        let g: Double = linear(c.g) * 0.7152
        let b: Double = linear(c.b) * 0.0722
        return r + g + b
    }

    /// WCAG contrast ratio between two luminances, 1 to 21.
    static func ratio(_ a: Double, _ b: Double) -> Double {
        let hi: Double = max(a, b)
        let lo: Double = min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }

    static func ratio(_ a: GraphRGB, _ b: GraphRGB) -> Double {
        ratio(a.luminance, b.luminance)
    }

    /// The contrast WCAG AA asks of body text.
    static let target: Double = 4.5
}

// MARK: - What is behind a label

/// One light in the picture, as seen from the camera: its direction (unit)
/// and angular radii - the solid body, and how far its glow reaches - its
/// colour at the core, and how strong its halo is at the body's rim.
nonisolated struct GraphGlow: Sendable, Equatable {
    var direction: SIMD3<Double>
    var core: Double
    var halo: Double
    var colour: GraphRGB
    var haloStrength: Double
}

/// What a label's measure found behind it.
nonisolated struct GraphBackdrop: Sendable, Equatable {
    /// The average colour behind the pill.
    var mean: GraphRGB
    /// The brightest and darkest luminance among the points.
    var brightest: Double
    var darkest: Double

    /// How much it changes across the pill (0 flat, 1 black to white).
    var busy: Double { max(brightest - darkest, 0) }

    static func flat(_ c: GraphRGB) -> GraphBackdrop {
        let l: Double = c.luminance
        return GraphBackdrop(mean: c, brightest: l, darkest: l)
    }
}

nonisolated enum GraphBackdropEstimate {
    /// The colour at one point (a unit direction from the eye): the theme's
    /// backdrop, plus every glow that covers it - its core fully, its halo
    /// fading with the square of the distance out.
    static func colour(at d: SIMD3<Double>, glows: [GraphGlow], backdrop: GraphRGB) -> GraphRGB {
        var out: GraphRGB = backdrop
        for g in glows {
            let cosine: Double = min(max((d * g.direction).sum(), -1), 1)
            let angle: Double = acos(cosine)
            if angle <= g.core {
                out = g.colour.over(out, alpha: 1)
                continue
            }
            guard angle < g.halo, g.halo > g.core else { continue }
            let t: Double = (angle - g.core) / (g.halo - g.core)
            let fade: Double = (1 - t) * (1 - t) * g.haloStrength
            out = out.adding(g.colour, fade)
        }
        return out.clamped
    }

    /// Averages the colour at each of `points` (unit directions from the
    /// eye across the pill).
    static func measure(points: [SIMD3<Double>], glows: [GraphGlow], backdrop: GraphRGB) -> GraphBackdrop {
        guard !points.isEmpty else { return GraphBackdrop.flat(backdrop) }
        var sum = GraphRGB(0, 0, 0)
        var hi: Double = 0
        var lo: Double = 1
        for p in points {
            let c: GraphRGB = colour(at: p, glows: glows, backdrop: backdrop)
            sum = GraphRGB(sum.r + c.r, sum.g + c.g, sum.b + c.b)
            let l: Double = c.luminance
            hi = max(hi, l)
            lo = min(lo, l)
        }
        let n: Double = Double(points.count)
        let mean = GraphRGB(sum.r / n, sum.g / n, sum.b / n)
        return GraphBackdrop(mean: mean, brightest: hi, darkest: lo)
    }

    /// Five points across a pill centred on `centre` (a point in the
    /// scene), `halfWidth` along `right` and `halfHeight` along `up`, as
    /// unit directions from `eye`: its middle and four points in from its
    /// corners.
    static func pillPoints(centre: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>, halfWidth: Double,
                           halfHeight: Double, eye: SIMD3<Double>) -> [SIMD3<Double>] {
        let across: SIMD3<Double> = right * (halfWidth * 0.8)
        let over: SIMD3<Double> = up * (halfHeight * 0.6)
        let spots: [SIMD3<Double>] = [centre, centre - across + over, centre + across + over,
                                      centre - across - over, centre + across - over]
        var out: [SIMD3<Double>] = []
        for s in spots {
            let v: SIMD3<Double> = s - eye
            let n: Double = (v * v).sum().squareRoot()
            if n > 1e-9 { out.append(v / n) }
        }
        return out
    }

    /// A body as a glow seen from `eye`: centred at `at`, its solid body
    /// `radius` across, its glow reaching `reach` times that.
    static func glow(at: SIMD3<Double>, radius: Double, reach: Double, colour: GraphRGB, strength: Double,
                     eye: SIMD3<Double>) -> GraphGlow? {
        let v: SIMD3<Double> = at - eye
        let d: Double = (v * v).sum().squareRoot()
        guard d > radius * 1.05, d > 1e-6 else { return nil }
        let core: Double = asin(min(radius / d, 1))
        let far: Double = min(radius * max(reach, 1) / d, 1)
        let halo: Double = max(asin(far), core)
        return GraphGlow(direction: v / d, core: core, halo: halo, colour: colour, haloStrength: strength)
    }
}

// MARK: - The style

/// How a name pill is drawn.
nonisolated struct GraphLabelLook: Sendable, Equatable {
    /// true: dark words on a pale pill; false: light words on a dark one.
    var darkText: Bool
    var text: GraphRGB
    var pill: GraphRGB
    /// The pill's opacity, 0...1.
    var opacity: Double
    var rim: GraphRGB
    /// A thin outline round the words (and a stronger rim) when the
    /// contrast is marginal.
    var outline: Bool
    /// The shadow behind the pill, 0...1.
    var shadow: Double
    /// The contrast the words get against what shows through the pill.
    var contrast: Double
}

/// What a label's style depends on besides the background.
nonisolated struct GraphLabelSettings: Sendable, Equatable {
    var increaseContrast: Bool = false
    var reduceTransparency: Bool = false
}

nonisolated enum GraphLabelChooser {
    static let lightText = GraphRGB(0.97, 0.97, 0.99)
    static let darkText = GraphRGB(0.05, 0.06, 0.09)
    /// The dark slate pill of old (Graph3DView.pillFill) and its pale twin.
    static let darkPill = GraphRGB(0.12, 0.13, 0.19)
    static let palePill = GraphRGB(0.93, 0.94, 0.97)

    /// What the words sit on: the pill at `opacity` over the background.
    static func seen(pill: GraphRGB, opacity: Double, over back: GraphBackdrop) -> GraphRGB {
        pill.over(back.mean, alpha: opacity)
    }

    /// The worst contrast the words get: against the pill over the
    /// brightest and the darkest point behind it.
    static func worstContrast(text: GraphRGB, pill: GraphRGB, opacity: Double, back: GraphBackdrop) -> Double {
        let a: Double = min(max(opacity, 0), 1)
        let pillL: Double = pill.luminance
        let hi: Double = pillL * a + back.brightest * (1 - a)
        let lo: Double = pillL * a + back.darkest * (1 - a)
        let mid: Double = seen(pill: pill, opacity: a, over: back).luminance
        let t: Double = text.luminance
        return min(GraphContrast.ratio(t, hi), GraphContrast.ratio(t, lo), GraphContrast.ratio(t, mid))
    }

    /// The least opacity (in steps of 0.05, from `floor`) at which `text`
    /// on `pill` reaches the target against the background; 1 if none does.
    static func opacity(text: GraphRGB, pill: GraphRGB, back: GraphBackdrop, floor: Double) -> Double {
        var a: Double = floor
        while a < 1 {
            if worstContrast(text: text, pill: pill, opacity: a, back: back) >= GraphContrast.target { return a }
            a += 0.05
        }
        return 1
    }

    /// The style for a label over `back`, for a body of colour `tint`.
    static func choose(_ back: GraphBackdrop, tint: GraphRGB, settings: GraphLabelSettings,
                       preferDark: Bool? = nil) -> GraphLabelLook {
        if settings.increaseContrast {
            // always the strongest: black pill, white words, white rim
            let c: Double = GraphContrast.ratio(lightText, .black)
            return GraphLabelLook(darkText: false, text: .white, pill: .black, opacity: 1, rim: .white,
                                  outline: true, shadow: 0.6, contrast: c)
        }
        let floor: Double = settings.reduceTransparency ? 1 : 0.62
        // the pill leans a little towards the body's own colour
        let darkPillTinted: GraphRGB = darkPill.mixed(tint, 0.18)
        let palePillTinted: GraphRGB = palePill.mixed(tint, 0.10)
        let lightNeed: Double = opacity(text: lightText, pill: darkPillTinted, back: back, floor: floor)
        let darkNeed: Double = opacity(text: darkText, pill: palePillTinted, back: back, floor: floor)
        let lightGets: Double = worstContrast(text: lightText, pill: darkPillTinted, opacity: lightNeed, back: back)
        let darkGets: Double = worstContrast(text: darkText, pill: palePillTinted, opacity: darkNeed, back: back)
        var dark: Bool
        if let preferDark {
            dark = preferDark
        } else if lightNeed != darkNeed {
            // whichever needs the lighter pill (shows more of the scene)
            dark = darkNeed < lightNeed
        } else {
            dark = darkGets > lightGets
        }
        // the night look is light-on-dark; only switch to a pale pill when
        // the background itself is pale
        if preferDark == nil && dark && back.mean.luminance < 0.35 { dark = false }
        let text: GraphRGB = dark ? darkText : lightText
        let pill: GraphRGB = dark ? palePillTinted : darkPillTinted
        var alpha: Double = dark ? darkNeed : lightNeed
        // a busy or bright background: more opaque still
        let glare: Double = max(0, back.brightest - 0.25) * 0.3
        alpha = min(1, alpha + 0.25 * back.busy + glare)
        let gets: Double = worstContrast(text: text, pill: pill, opacity: alpha, back: back)
        let marginal: Bool = gets < 7
        let rimBase: GraphRGB = dark ? GraphRGB(0.35, 0.37, 0.45) : GraphRGB(0.40, 0.43, 0.55)
        let rim: GraphRGB = marginal ? (dark ? GraphRGB(0.1, 0.1, 0.14) : GraphRGB(0.85, 0.87, 0.95))
            : rimBase.mixed(tint, 0.35)
        let shadow: Double = marginal ? 0.45 : 0.15 + 0.2 * back.busy
        return GraphLabelLook(darkText: dark, text: text, pill: pill, opacity: alpha, rim: rim, outline: marginal,
                              shadow: min(shadow, 0.6), contrast: gets)
    }
}

// MARK: - Easing without flicker

/// One shown label's style over time. A new measure only changes which
/// words it shows (light or dark) when the other kind has been better by a
/// clear margin for `hold` seconds in a row; everything else eases to the
/// new measure over `ease` seconds.
nonisolated struct GraphLabelTracker: Sendable, Equatable {
    static let ease: Double = 0.3
    static let hold: Double = 0.35
    /// The band round the flip: dark words once what is behind is paler
    /// than this, light again only once it is darker than that.
    static let paleAbove: Double = 0.40
    static let darkBelow: Double = 0.28

    private(set) var target: GraphLabelLook
    private(set) var shown: GraphLabelLook
    /// 0...1: how far `shown` has come from where it was towards `target`.
    private var from: GraphLabelLook
    private var progress: Double = 1
    /// How long the other kind has been winning.
    private var pending: Double = 0

    init(_ look: GraphLabelLook) {
        target = look
        shown = look
        from = look
    }

    /// A new measure, `elapsed` seconds after the last one.
    mutating func measure(_ back: GraphBackdrop, tint: GraphRGB, settings: GraphLabelSettings, elapsed: Double) {
        let keep: GraphLabelLook = GraphLabelChooser.choose(back, tint: tint, settings: settings,
                                                           preferDark: target.darkText)
        var next: GraphLabelLook = keep
        if !settings.increaseContrast {
            // the other kind of words wins only past a band either side of
            // where the choice would flip: pale enough (or dark enough)
            // that it is clearly the better one
            let free: GraphLabelLook = GraphLabelChooser.choose(back, tint: tint, settings: settings)
            let light: Double = back.mean.luminance
            let clear: Bool = target.darkText ? light <= Self.darkBelow : light >= Self.paleAbove
            let otherWins: Bool = free.darkText != target.darkText && clear
            if otherWins {
                let other: GraphLabelLook = free
                pending += max(elapsed, 0)
                if pending >= Self.hold - 1e-9 {
                    next = other
                    pending = 0
                }
            } else {
                pending = 0
            }
        }
        guard next != target else { return }
        from = shown
        target = next
        progress = 0
    }

    /// Moves `shown` on by `dt` seconds (at once with `instant`: Reduce
    /// Motion). Whether it changed.
    @discardableResult
    mutating func step(_ dt: Double, instant: Bool = false) -> Bool {
        guard progress < 1 else { return false }
        progress = instant ? 1 : min(1, progress + max(dt, 0) / Self.ease)
        if progress >= 1 {
            shown = target
            return true
        }
        let t: Double = progress * progress * (3 - 2 * progress)
        shown = Self.blend(from, target, t)
        return true
    }

    static func blend(_ a: GraphLabelLook, _ b: GraphLabelLook, _ t: Double) -> GraphLabelLook {
        let late: Bool = t >= 0.5
        let opacity: Double = a.opacity + (b.opacity - a.opacity) * t
        let shadow: Double = a.shadow + (b.shadow - a.shadow) * t
        let contrast: Double = a.contrast + (b.contrast - a.contrast) * t
        let text: GraphRGB = a.text.mixed(b.text, t)
        let pill: GraphRGB = a.pill.mixed(b.pill, t)
        let rim: GraphRGB = a.rim.mixed(b.rim, t)
        return GraphLabelLook(darkText: late ? b.darkText : a.darkText, text: text, pill: pill, opacity: opacity,
                              rim: rim, outline: late ? b.outline : a.outline, shadow: shadow, contrast: contrast)
    }
}

/// How often the labels are measured, and how many at most.
nonisolated enum GraphLabelSampler {
    /// Seconds between measures: about 5 a second, 3 on Smooth.
    static func interval(smooth: Bool) -> Double {
        smooth ? 0.3 : 0.2
    }

    /// The most labels measured at once.
    static let most: Int = 10

    /// A pill's half width and height in points for a title: about 8.5
    /// points a character of a 15-point bold font, plus its padding.
    static func pillPoints(characters: Int) -> (Double, Double) {
        let n: Double = Double(min(max(characters, 1), 29))
        let width: Double = n * 8.5 + 7
        return (width * 0.5, 11)
    }
}

// MARK: - How bright each body is

/// A body's light for the estimate: its colour, how far its glow reaches
/// (in its own radii) and how strong the halo is at its rim. Set once when
/// the scene is built, from what the body is in its theme.
nonisolated struct GraphShine: Sendable, Equatable {
    var colour: GraphRGB
    var reach: Double
    var strength: Double

    static let dark = GraphShine(colour: GraphRGB(0.04, 0.04, 0.05), reach: 1, strength: 0)

    /// The Universe (UniverseRole's raw value; an empty folder is dark).
    static func universe(_ role: String, empty: Bool, tier: Int) -> GraphShine {
        switch role {
        case "galaxy":
            // a black hole: the sphere black, the disk round it bright
            if empty { return GraphShine(colour: GraphRGB(0.05, 0.05, 0.06), reach: 2, strength: 0.15) }
            return GraphShine(colour: GraphRGB(0.10, 0.08, 0.06), reach: 3.2, strength: 0.85)
        case "star", "home":
            if empty { return GraphShine(colour: GraphRGB(0.18, 0.12, 0.10), reach: 1.4, strength: 0.2) }
            let colours: [GraphRGB] = [GraphRGB(1.0, 0.97, 0.88), GraphRGB(1.0, 0.97, 0.88),
                                       GraphRGB(1.0, 0.78, 0.45), GraphRGB(1.0, 0.52, 0.35)]
            let c: GraphRGB = colours[min(max(tier, 0), 3)]
            return GraphShine(colour: c, reach: 2.6, strength: 0.9)
        case "gasGiant": return GraphShine(colour: GraphRGB(0.78, 0.62, 0.45), reach: 1.3, strength: 0.25)
        case "rocky": return GraphShine(colour: GraphRGB(0.42, 0.40, 0.38), reach: 1.1, strength: 0.1)
        case "moon": return GraphShine(colour: GraphRGB(0.62, 0.62, 0.64), reach: 1, strength: 0)
        case "pulsar": return GraphShine(colour: GraphRGB(0.75, 0.88, 1.0), reach: 3.5, strength: 0.8)
        case "comet", "oort": return GraphShine(colour: GraphRGB(0.80, 0.92, 1.0), reach: 2.2, strength: 0.5)
        default: return .dark
        }
    }

    /// The Neurons (NeuronRole's raw value): glowing somata, pale glia.
    static func neurons(_ role: Int) -> GraphShine {
        switch role {
        case 0, 1, 2: return GraphShine(colour: GraphRGB(0.95, 0.62, 0.78), reach: 2.2, strength: 0.7)
        case 3: return GraphShine(colour: GraphRGB(0.72, 0.60, 0.95), reach: 1.8, strength: 0.55)
        case 4, 6: return GraphShine(colour: GraphRGB(0.55, 0.78, 0.95), reach: 1.6, strength: 0.45)
        case 5: return GraphShine(colour: GraphRGB(0.85, 0.88, 0.80), reach: 1.2, strength: 0.25)
        case 7: return GraphShine(colour: GraphRGB(0.95, 0.85, 0.50), reach: 1.8, strength: 0.5)
        default: return GraphShine(colour: GraphRGB(0.60, 0.70, 0.60), reach: 1.3, strength: 0.2)
        }
    }

    /// The Circuit (CircuitRole's raw value): dark chips, a lit LED
    /// bright, gold pads.
    static func circuit(_ role: Int, lit: Bool) -> GraphShine {
        switch role {
        case 0, 1, 2: return GraphShine(colour: GraphRGB(0.10, 0.11, 0.12), reach: 1, strength: 0)
        case 3: return GraphShine(colour: GraphRGB(0.30, 0.42, 0.70), reach: 1, strength: 0.05)
        case 6:
            if lit { return GraphShine(colour: GraphRGB(0.95, 1.0, 0.85), reach: 2.8, strength: 0.85) }
            return GraphShine(colour: GraphRGB(0.35, 0.40, 0.32), reach: 1, strength: 0)
        case 11: return GraphShine(colour: GraphRGB(0.95, 0.78, 0.35), reach: 1.3, strength: 0.3)
        default: return GraphShine(colour: GraphRGB(0.6, 0.55, 0.40), reach: 1, strength: 0)
        }
    }

    /// Each theme's ground behind everything: the night sky, the Neurons'
    /// dark fluid, the Circuit's bench and boards.
    static func backdrop(theme: String) -> GraphRGB {
        switch theme {
        case "neurons": return GraphRGB(0.05, 0.05, 0.09)
        case "circuit": return GraphRGB(0.06, 0.10, 0.08)
        default: return GraphRGB(0.03, 0.03, 0.06)
        }
    }

    /// A dying body's flash at `t` seconds of a `duration`-second death
    /// (GraphDeathEffect's raw value): how bright, and how many radii it
    /// reaches.
    static func deathFlash(_ effect: String, t: Double, duration: Double) -> (Double, Double) {
        let span: Double = max(duration, 0.01)
        let x: Double = min(max(t / span, 0), 1)
        switch effect {
        case "supernova":
            let peak: Double = x < 0.08 ? x / 0.08 : max(0, 1 - (x - 0.08) / 0.5)
            return (peak, 11)
        case "planetaryNebula", "tidalDisruption":
            return (max(0, 1 - x / 0.6) * 0.7, 6)
        case "shortCircuit":
            let peak: Double = t < 0.08 ? t / 0.08 : max(0, 1 - (t - 0.1) / 0.5)
            return (peak, 4)
        default:
            return (max(0, 1 - x) * 0.3, 2)
        }
    }
}
