import Foundation

// MARK: - A Neurons axon's ending: the terminal arbor and its synapses
//
// A real axon does not end in a fork. Near its target it loses its myelin
// and breaks into a small, irregular brush of fine branchlets (the
// telodendria), each a different length, curving and tapering, spreading
// over the target cell's surface; each ends in a swollen bouton pressed
// against the membrane with a thin dark cleft between them, full of
// vesicles. Here each bouton is drawn like a golf tee of gel: the branchlet
// thins to a stem, swells into a thicker, wet neck and flares into a wide,
// shallow cup curved to hug the target across the cleft, its rim soft and
// slowly wobbling on its own phase, the whole cup bulging and settling like
// jelly as an impulse lands (no wobble or bulge at Smooth or with Reduce
// Motion). An impulse arriving splits into the branchlets and reaches the
// boutons at slightly different times; each bouton brightens and a soft
// glow of transmitter crosses its cleft and spreads on the membrane.
//
// The Neurons' link shader (NeuronShaders.axon) draws all of that on the
// link's own ribbon - no node per branchlet - so the ribbon has to reach
// round the target: in this mode GraphRibbonWriter runs each link right to
// its target's centre (not trimmed at its rim), widens it over its last
// stretch to hold the brush (`halfWidth`), writes the distance from the
// END into u (exact, so the boutons sit on the membrane) and the target's
// membrane radius, as one of 16 steps (`level`), into v. The shader mirrors
// every measure here exactly; this file is Foundation only, so the brush's
// geometry is tested on Linux (Tests/GraphDeathTests.swift).
//
// Measures, from the target's membrane radius R and the ribbon's base half
// width h (world units): one fibre's radius fw = h * share (0.3 for an
// axon, 0.2 for each of a tract's three fibres), a bouton's radius 0.95 fw,
// the cleft 0.3 fw, the boutons' centres on a circle of Rb = R + cleft +
// bouton round the target's centre, at up to 60 degrees either side of the
// way in; every branch point within D1 of the centre, the ribbon widening
// from h at D0 to its full width at D1.

nonisolated struct GraphLinkArbor: Sendable, Equatable {
    /// The target's membrane radius over its link trim radius (GraphSim's
    /// radius: the Neurons' cell is `size`, its trim radius 0.8 size).
    var membrane: Float = 1.25
    /// One fibre's radius over the ribbon's base half width.
    var share: Float = 0.3

    /// How many membrane sizes v can carry.
    static let levels: Int = 16
    /// The widest the boutons spread either side of the way in (radians).
    static let spread: Float = 1.05

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

    /// The measures for membrane radius `r` (already a step's) and base
    /// half width `h`.
    func measures(r: Float, h: Float) -> GraphArborMeasures {
        let fw: Float = h * share
        let rb: Float = 0.95 * fw
        let cleft: Float = 0.3 * fw
        let ring: Float = r + cleft + rb
        let d1: Float = ring + 1.5 * r + 2.5 * fw + 0.02
        let d0: Float = d1 + 0.5 * r + 4 * fw
        let side: Float = ring * 0.867 + rb + 3 * fw
        let wide: Float = max(side, h)
        return GraphArborMeasures(fibre: fw, bouton: rb, cleft: cleft, ring: ring, full: d1, start: d0,
                                  wide: wide)
    }

    /// The ribbon's half width `dEnd` from the target's centre: h beyond
    /// D0, widening in a straight ramp to the full width at D1 and on to
    /// the end (straight, so the strip between its samples is exactly what
    /// the shader assumes wherever the brush is).
    func halfWidth(dEnd: Float, r: Float, h: Float) -> Float {
        let m: GraphArborMeasures = measures(r: r, h: h)
        let run: Float = max(m.start - m.full, 0.0001)
        let ramp: Float = min(max((m.start - dEnd) / run, 0), 1)
        return h + (m.wide - h) * ramp
    }

    /// Where the ribbon ends, as a trim from the target's centre towards
    /// the sender: the difference between its true membrane radius and the
    /// step's, so the front of the shader's membrane circle (and the
    /// boutons nearest the way in) sits on the true membrane.
    static func endTrim(membrane: Float) -> Float {
        let stepped: Float = radius(level: level(for: membrane))
        return membrane - stepped
    }

    /// The v band in this mode: length in eighths, then the level, then
    /// the lit bit. Under 16,384 for any coded length up to 60, so the
    /// position across still steps by about 0.001.
    static func band(length: Float, level: Int, lit: Int) -> Int {
        let eighths: Int = Int((max(length, 0) * 8).rounded(.down))
        let q: Int = min(max(level, 0), levels - 1)
        return (eighths * 16 + q) * 2 + lit
    }

    /// The shader's reading of a band: (length, level, lit).
    static func read(band: Int) -> (Float, Int, Int) {
        let lit: Int = band % 2
        let rest: Int = band / 2
        let level: Int = rest % 16
        let eighths: Int = rest / 16
        let length: Float = Float(eighths) * 0.125 + 0.0625
        return (length, level, lit)
    }

    /// Branchlet `i` of `n` on the link with `seed`, as the shader works it
    /// out from the same hash. Branchlets go in pairs (0 and 1, 2 and 3,
    /// ...; the last alone when `n` is odd): a pair leaves the fibre at
    /// one point as one trunk heading between its two boutons, and splits
    /// part way - so the brush branches twice, like a real terminal arbor,
    /// instead of fanning from one point.
    static func branch(_ i: Int, of n: Int, seed: Int, measures m: GraphArborMeasures,
                       r: Float) -> GraphArborBranch {
        let sibling: Int = pairOf(i, of: n)
        let first: Int = min(i, sibling)
        let angle: Float = boutonAngle(i, of: n, seed: seed)
        let b: Float = hash(seed, first, 1)
        let c: Float = hash(seed, first, 2)
        let run: Float = r * (0.6 + 0.9 * b) + m.fibre * (1.0 + 1.5 * c)
        let from: Float = m.ring + run
        let alongB: Float = m.ring * cos(angle)
        let acrossB: Float = m.ring * sin(angle)
        return GraphArborBranch(angle: angle, from: from, to: alongB, across: acrossB)
    }

    /// The branchlet paired with `i` (itself when it has none).
    static func pairOf(_ i: Int, of n: Int) -> Int {
        let j: Int = i % 2 == 0 ? i + 1 : i - 1
        return j < n ? j : i
    }

    /// Where bouton `i` of `n` sits, as an angle from the way in: evenly
    /// across the spread, jittered by up to 7.5% of the gap either way.
    static func boutonAngle(_ i: Int, of n: Int, seed: Int) -> Float {
        let count: Float = Float(max(n, 1))
        let gap: Float = 2 * spread / count
        let even: Float = (Float(i) + 0.5) / count * 2 - 1
        let a: Float = hash(seed, i, 0)
        return spread * even + (a - 0.5) * gap * 0.15
    }

    /// How many branchlets a link's brush has: 4 to 7 (3 or 4 at Smooth),
    /// but no more than fit round its target without their boutons
    /// touching (a small cell's brush has as few as two).
    static func count(seed: Int, rich: Bool, measures m: GraphArborMeasures) -> Int {
        let pick: Float = hash(seed, 9, 3)
        let wanted: Int = rich ? 4 + min(Int(pick * 4), 3) : 3 + min(Int(pick * 2), 1)
        return min(wanted, room(m))
    }

    /// How many boutons fit along the spread, jitter and all: each is a
    /// tee's cup 2.3 bouton radii across (1.15 either side, as the shader
    /// draws it), which may swell 12% as an impulse lands.
    static func room(_ m: GraphArborMeasures) -> Int {
        let fit: Float = (0.68 * m.ring / max(m.bouton, 0.0001)).rounded(.down)
        return max(Int(fit), 2)
    }

    /// The shader's hash of (seed, branch, which), 0 to 1: sin-free, so a
    /// GPU and this agree to the last bit that matters.
    static func hash(_ seed: Int, _ i: Int, _ which: Int) -> Float {
        let s: UInt32 = UInt32(truncatingIfNeeded: seed)
        let k: UInt32 = UInt32(truncatingIfNeeded: i * 4 + which)
        var h: UInt32 = s &* 747_796_405 &+ k &* 2_891_336_453 &+ 1_442_695_041
        let shift: UInt32 = (h >> 28) &+ 4
        h = ((h >> shift) ^ h) &* 277_803_737
        h = (h >> 22) ^ h
        return Float(h & 1023) / 1023
    }
}

/// A brush's measures (GraphLinkArbor.measures), world units.
nonisolated struct GraphArborMeasures: Sendable, Equatable {
    let fibre: Float
    let bouton: Float
    let cleft: Float
    /// The circle the boutons' centres sit on, round the target's centre.
    let ring: Float
    /// Every branch point is within this of the centre; the ribbon is at
    /// its full width from here in.
    let full: Float
    /// The ribbon starts widening here.
    let start: Float
    /// Its full half width.
    let wide: Float
}

/// One branchlet: its bouton's angle from the way in, where it leaves the
/// fibre (distance from the target's centre), and its bouton's centre
/// (distance along the way in from the centre, and across).
nonisolated struct GraphArborBranch: Sendable, Equatable {
    let angle: Float
    let from: Float
    let to: Float
    let across: Float
}
