import Foundation

// MARK: - A Neurons axon: hillock, fibre, one bouton
//
// Every link in the Neurons theme is one textbook axon from the sending
// cell to the receiving one. From the sender: a smooth axon-hillock cone
// flaring out of its membrane (a trumpet bell, filled with the same milky
// gel as the soma), a short bare initial segment, then a thin fibre -
// much thinner than any cell, round like a gel tube, with the soma's own
// fresnel rim - wrapped in a faint, soft, continuous myelin haze (never
// beaded or segmented), tapering gently towards its target, bare again for
// its last stretch, and ending in exactly ONE small terminal bouton
// pressed flat on the target's membrane across a thin dark synaptic
// cleft. Nothing else anywhere along it: no knobs, twigs, pods or beads.
// With "Lines: Curved" the axon meanders gently (GraphLinkWander, fixed
// per link); with "Lines: Straight" it runs straight.
//
// An impulse lights the hillock (the trigger zone) as the axon fires, runs
// down the fibre as a white-hot front over an amber wake and reaches the
// bouton's back at exactly the moment NeuronImpulse lands it, so the
// target's arrival glow comes in the same frame; the bouton flashes and
// transmitter glows in the cleft.
//
// The Neurons' link shader (NeuronShaders.axon) draws all of that on the
// link's own ribbon, which GraphRibbonWriter writes in this mode (an arbor
// set) as follows: from the sender's trim to its target's centre (give or
// take the membrane's step, `endTrim`); u = seed * 64 + 1 + the distance
// from that END along the ribbon (exact, so the bouton sits on the
// membrane); v = `band` - the whole length in 64ths, the target's
// membrane radius as one of 16 steps (`level`), the lit bit - plus the
// position across. The ribbon is one width all along (`halfWidth` is the
// look's half width, which `ribbon` makes wide enough for the hillock),
// so the shader reads the offset across exactly as that share of it. The
// shader mirrors every measure here; this file is Foundation only, so the
// axon's geometry is tested on Linux (Tests/GraphDeathTests.swift).
//
// Measures, in fibre radii f (world units: `fibre`): the ribbon's half
// width 4.2; the hillock 3.2 wide at its base, 8 long; the fibre f to 0.7f
// at the terminal; the bouton 1.7 (swelling 14% as an impulse lands, not at
// Smooth or with Reduce Motion), its centre 0.78 of its radius past the
// cleft, so it is pressed flat on it; the cleft 0.55.

nonisolated struct GraphLinkArbor: Sendable, Equatable {
    /// The target's membrane radius over its link trim radius (GraphSim's
    /// radius: the Neurons' cell is `size`, its trim radius 0.8 size).
    var membrane: Float = 1.25
    /// The fibre's radius, world units.
    var fibre: Float = 0.018

    /// An axon between two notes, and a tract (one thicker fibre) between
    /// regions and down a pathway.
    static let axon = GraphLinkArbor(membrane: 1.25, fibre: 0.018)
    static let tract = GraphLinkArbor(membrane: 1.25, fibre: 0.026)

    /// How many membrane sizes v can carry.
    static let levels: Int = 16
    /// The ribbon's half width, in fibre radii.
    static let across: Float = 4.2
    /// The hillock's base radius and length, in fibre radii.
    static let hillockBase: Float = 3.2
    static let hillockLength: Float = 8
    /// The fibre's radius at the terminal, as a share of its start's.
    static let taper: Float = 0.7
    /// The bouton's radius, the cleft, and where the bouton's centre lies
    /// past the cleft (a share of its radius: under 1, so it is pressed
    /// flat), in fibre radii; how much it swells as an impulse lands.
    static let knob: Float = 1.7
    static let cleft: Float = 0.55
    static let press: Float = 0.78
    static let swell: Float = 0.14
    /// Coded length steps per unit, and the most steps coded (v's band
    /// stays under 65,536, where a float still steps finely across).
    static let steps: Float = 64
    static let mostSteps: Int = 2047

    /// The ribbon's half width this fibre needs: the look's link width.
    var ribbon: Float { Self.across * fibre }

    /// Membrane radius of step `level` (0...15): 0.05 growing by 16% a
    /// step, to 0.46.
    static func radius(level: Int) -> Float {
        let q: Int = min(max(level, 0), levels - 1)
        let grow: Float = Float(q) * 0.14842
        return 0.05 * exp(grow)
    }

    /// The step nearest `membrane` (by ratio).
    static func level(for membrane: Float) -> Int {
        let r: Float = max(membrane, 0.001)
        let steps: Float = log(r / 0.05) / 0.14842
        let q: Int = Int(steps.rounded())
        return min(max(q, 0), levels - 1)
    }

    /// Where the ribbon ends, as a trim from the target's centre towards
    /// the sender: the difference between its true membrane radius and the
    /// step's, so the shader's membrane (where the bouton sits) is on the
    /// true membrane.
    static func endTrim(membrane: Float) -> Float {
        let stepped: Float = radius(level: level(for: membrane))
        return membrane - stepped
    }

    /// The ribbon's half width anywhere along it: the base width `h` all
    /// along (the look's `ribbon`), so the shader reads the offset across
    /// exactly - one straight strip, nothing for a sample to bend.
    func halfWidth(dEnd: Float, r: Float, h: Float) -> Float {
        h
    }

    /// The bouton's centre, from the target's centre (`r` its membrane).
    func knobCentre(r: Float) -> Float {
        r + Self.cleft * fibre + Self.press * Self.knob * fibre
    }

    /// The bouton's back, from the target's centre: where impulses land.
    func back(r: Float) -> Float {
        knobCentre(r: r) + Self.knob * fibre
    }

    /// The fibre's radius `along` from the ribbon's start of an axon
    /// `length` long ending on membrane `r`: the hillock's trumpet flare
    /// into the fibre, which tapers to `taper` of it at the bouton.
    func radius(along: Float, length: Float, r: Float) -> Float {
        let f: Float = fibre
        let hill: Float = Self.hillockLength * f
        let run: Float = max(landing(length: length, r: r) - hill, f)
        let t: Float = min(max((along - hill) / run, 0), 1)
        let thin: Float = f * (1 - (1 - Self.taper) * t)
        let q: Float = min(max(1 - along / hill, 0), 1)
        return thin + (Self.hillockBase - 1) * f * q * q * q
    }

    /// Where along a link `length` long (from its start) the impulse lands:
    /// the bouton's back - so it lands at NeuronImpulse's arrival time, as
    /// the shader's pulse reaches it at pos 1.
    func landing(length: Float, r: Float) -> Float {
        max(length - back(r: r), 0.05)
    }

    /// The v band: the length in 64ths, then the level, then the lit bit.
    /// Under 65,536 for any coded length (up to 32 units; longer ones are
    /// coded as 32).
    static func band(length: Float, level: Int, lit: Int) -> Int {
        let raw: Int = Int((max(length, 0) * steps).rounded(.down))
        let q: Int = min(raw, mostSteps)
        let lv: Int = min(max(level, 0), levels - 1)
        return (q * 16 + lv) * 2 + lit
    }

    /// The shader's reading of a band: (length, level, lit) - the length
    /// the middle of its 64th.
    static func read(band: Int) -> (Float, Int, Int) {
        let lit: Int = band % 2
        let rest: Int = band / 2
        let level: Int = rest % 16
        let q: Int = rest / 16
        let length: Float = (Float(q) + 0.5) / steps
        return (length, level, lit)
    }
}
