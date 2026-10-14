import Foundation

// MARK: - A Neurons axon's ending: one gel golf-tee synapse
//
// Every axon (and every tract, its three fibres gathered into one first)
// runs straight to its target and ends in ONE synapse, drawn like a golf tee
// made of gel: the fibre loses its myelin, narrows into a thin stem, swells
// into a thicker, wet neck and flares into one wide, shallow cup whose
// front follows the target's membrane across a thin dark cleft. The cup is
// translucent gel like the cells - a bright edge, faint vesicle specks
// inside - its soft rim wobbling slowly on the synapse's own phase, and it
// bulges and settles like jelly as an impulse lands. Transmitter then glows
// across the cleft and spreads along the membrane from the cup's rim. No
// wobble or bulge at Smooth (a plain cup) or with Reduce Motion.
//
// The impulse reaches the cup's back at exactly the moment NeuronImpulse
// lands it (the old arrival time), so the target's dendrite glow stays in
// step.
//
// The Neurons' link shader (NeuronShaders.axon) draws all of that on the
// link's own ribbon, so the ribbon has to reach the target and be wide
// enough near it: in this mode GraphRibbonWriter runs each link right to
// its target's centre (not trimmed at its rim), widens it over its last
// stretch (`halfWidth`), writes the distance from the END into u (exact, so
// the cup sits on the membrane) and the target's membrane radius, as one of
// 16 steps (`level`), into v. The shader mirrors every measure here
// exactly; this file is Foundation only, so the synapse's geometry is
// tested on Linux (Tests/GraphDeathTests.swift).
//
// Measures, from the target's membrane radius R and the ribbon's base half
// width h (world units): one fibre's radius fw = h * share (0.3 for an
// axon, 0.2 for a tract's fibres); the cleft 0.3 fw; the cup 0.55 fw thick
// at its middle, half as thick again at its rim, 2.6 fw either side of the
// way in - but, rim and all, never more than `widest` radians round the
// membrane (and never under a quarter of a fibre radius), so the
// cups of links arriving at one cell from different sides never touch; its
// neck 1.4 cup-widths long behind it, its stem as long again; the ribbon
// widening from h at D0 to its full width at D1, where the neck begins.

nonisolated struct GraphLinkArbor: Sendable, Equatable {
    /// The target's membrane radius over its link trim radius (GraphSim's
    /// radius: the Neurons' cell is `size`, its trim radius 0.8 size).
    var membrane: Float = 1.25
    /// One fibre's radius over the ribbon's base half width.
    var share: Float = 0.3

    /// How many membrane sizes v can carry.
    static let levels: Int = 16
    /// The most a cup reaches round its target either side of the way in
    /// (radians).
    static let widest: Float = 0.42

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
        let cleft: Float = 0.3 * fw
        let front: Float = r + cleft
        let thick: Float = 0.55 * fw
        let cup: Float = max(min(2.6 * fw, Self.widest * front - 0.75 * thick), 0.25 * fw)
        let back: Float = front + thick
        let neck: Float = 1.4 * cup
        let full: Float = back + neck + 0.02
        let start: Float = full + 0.5 * r + 4 * fw
        let side: Float = cup + 1.5 * thick + 3 * fw
        let wide: Float = max(side, h)
        return GraphArborMeasures(fibre: fw, cleft: cleft, front: front, thick: thick, cup: cup, back: back,
                                  neck: neck, full: full, start: start, wide: wide)
    }

    /// The ribbon's half width `dEnd` from the target's centre: h beyond
    /// D0, widening in a straight ramp to the full width at D1 and on to
    /// the end (straight, so the strip between its samples is exactly what
    /// the shader assumes wherever the synapse is).
    func halfWidth(dEnd: Float, r: Float, h: Float) -> Float {
        let m: GraphArborMeasures = measures(r: r, h: h)
        let run: Float = max(m.start - m.full, 0.0001)
        let ramp: Float = min(max((m.start - dEnd) / run, 0), 1)
        return h + (m.wide - h) * ramp
    }

    /// Where the ribbon ends, as a trim from the target's centre towards
    /// the sender: the difference between its true membrane radius and the
    /// step's, so the middle of the shader's membrane (where the cup sits)
    /// is on the true membrane.
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

    /// How far round the target (radians, either side of the way in) a
    /// cup reaches, its rim included.
    func reach(r: Float, h: Float) -> Float {
        let m: GraphArborMeasures = measures(r: r, h: h)
        return (m.cup + 0.75 * m.thick) / m.front
    }

    /// Where along the link (from its start, a link `length` long) the
    /// impulse lands: the cup's back - so it lands at NeuronImpulse's
    /// arrival time, as the shader's pulse reaches `lref` at pos 1.
    static func landing(length: Float, measures m: GraphArborMeasures) -> Float {
        max(length - m.back, 0.05)
    }
}

/// A synapse's measures (GraphLinkArbor.measures), world units, as
/// distances from the target's centre where they lie along the way in.
nonisolated struct GraphArborMeasures: Sendable, Equatable {
    let fibre: Float
    let cleft: Float
    /// The cup's front (hugging the membrane across the cleft).
    let front: Float
    /// Its thickness at the middle (the rim half as thick again).
    let thick: Float
    /// How far it reaches either side of the way in.
    let cup: Float
    /// Its back, at the middle: where the neck meets it and the impulse
    /// lands.
    let back: Float
    /// The neck's length behind it (the stem as long again).
    let neck: Float
    /// The ribbon is at its full width from here in.
    let full: Float
    /// It starts widening here.
    let start: Float
    /// Its full half width.
    let wide: Float
}
