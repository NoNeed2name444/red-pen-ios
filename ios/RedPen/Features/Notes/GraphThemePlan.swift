import Foundation

// MARK: - A theme's plan
//
// What a theme's planner (GraphNeurons, GraphCircuit) hands the shared theme
// scene (GraphThemeScene): every body in order (each after its parent), how
// it moves relative to its parent (GraphOrbit, the same moves GraphSim runs
// for the Universe), what it is in the theme (`role`, the theme's own
// code), and every link with its kind. Plus ThemeLayout: deterministic,
// overlap-free placing any theme can use.
//
// Pure Foundation (no SceneKit, UIKit or simd module), so planners and their
// tests run on Linux. Reuses UniverseInput, GraphOrbit, UniverseFrame and the
// maths helpers of GraphUniverse.swift.

/// What a planned body stands for.
nonisolated enum ThemeBodyKind: Sendable, Equatable {
    case note
    case folder
    /// The one container of a vault with no folders (GraphUniverse.homeID).
    case home
    /// A piece of a theme's own wiring that stands for no note or folder
    /// (the Circuit's power and ground taps and its edge connectors): drawn
    /// and moved like a body, never picked, named or counted.
    case fixture
}

nonisolated struct ThemeBody: Sendable, Equatable {
    /// The note's id, the folder's id, or GraphUniverse.homeID.
    let id: UUID
    let kind: ThemeBodyKind
    /// The theme's own role code (for Neurons, NeuronRole.rawValue).
    let role: Int
    /// The body it moves with, or -1.
    let parent: Int
    /// Its size: the solid body's radius.
    let sphere: Float
    /// A container's depth (0 at the top); -1 for a note.
    let depth: Int
    /// Its top-level container's body index (itself for one), or -1.
    let region: Int
    /// Notes inside a container (its whole subtree); 0 for a note.
    let count: Int
    /// A note's links; 0 for a container.
    let links: Int
    let words: Int
    /// Which end of a link sends (0...7): the higher sends, as the Space's
    /// style codes do (GraphRibbonWriter).
    let rank: Int
    /// A stable number for the look's variations.
    let seed: UInt64
    let orbit: GraphOrbit
    /// Where it is at time 0, in the space's coordinates.
    let home: SIMD3<Float>
    /// Its outward direction (a container's pathway; a note's away from its
    /// container), unit length.
    let axis: SIMD3<Float>
    let title: String
    /// What its name pill says.
    let label: String
}

/// A link between two bodies. kind: 0 inside one container, 1 between
/// containers of one region (arched away from `centre`, a body index), 2
/// between regions or to a loose note (arched round the origin, in the
/// far geometry), 3 hidden (drawn as touching instead), 4 a pathway: a
/// container to the container inside it (straight, in the far geometry);
/// 5 and 6 a theme's own wiring (the Circuit's feeds, taps and buses): 5
/// with the links, 6 in the far geometry, both always sent from `a` to `b`
/// whatever the ends' ranks.
nonisolated struct ThemeLink: Sendable, Equatable {
    let a: Int
    let b: Int
    let kind: Int
    let centre: Int
}

nonisolated struct ThemePlan: Sendable {
    /// Every body, each after its parent.
    let bodies: [ThemeBody]
    /// The notes' own links (by body index) and the pathways.
    let links: [ThemeLink]
    /// Points the whole-map framing must hold, at any time.
    let envelope: [SIMD3<Float>]
    /// For each container body, the points its fly-in framing must hold,
    /// relative to it; empty for notes.
    let systems: [[SIMD3<Float>]]
    /// The top-level containers' body indices.
    let regions: [Int]
    /// What VoiceOver reads: "2 regions, 3 relays, 12 neurons".
    let summary: String
    /// A theme's ground, when it has one (the Circuit's motherboard): its
    /// low x, low y, high x and high y in the theme's own plane.
    var ground: SIMD4<Float>? = nil
    /// Per body, a rectangle round it on that ground (the Circuit: a chip's
    /// own sub-board) - its centre's x and y from the body and its half
    /// width and height; all zero for none. Empty when the theme has none.
    var patches: [SIMD4<Float>] = []
    /// Straight bars a theme draws on its ground (the Circuit's power and
    /// ground rails), each carried by a body.
    var bars: [ThemeBar] = []
    /// Per body, the body current (or an impulse) comes into it from - its
    /// feed in the theme's wiring - or -1. Empty when the theme has none.
    var feeds: [Int] = []

    static let empty = ThemePlan(bodies: [], links: [], envelope: [], systems: [], regions: [], summary: "")

    /// Where body `i` is at `time`.
    func position(of i: Int, time: Double) -> SIMD3<Float> {
        var p = SIMD3<Float>(0, 0, 0)
        var at: Int = i
        var steps: Int = 0
        while at >= 0 && at < bodies.count && steps <= bodies.count {
            p += GraphUniverse.offset(bodies[at].orbit, time: time)
            at = bodies[at].parent
            steps += 1
        }
        return p
    }
}

/// A straight bar on a theme's ground, carried by body `owner`: its
/// middle's x and y on the ground from the owner, half its length along x,
/// and what it is (the Circuit: 0 the power rail, 1 a ground rail).
nonisolated struct ThemeBar: Sendable, Equatable {
    let owner: Int
    let x: Float
    let y: Float
    let half: Float
    let kind: Int
}

// MARK: - Placing without overlaps

/// A ball: something's centre and how far it reaches.
nonisolated struct ThemeBall: Sendable, Equatable {
    var c: SIMD3<Double>
    var r: Double
}

/// Deterministic placing for any theme: even directions, turns that carry
/// +x to a direction, and sliding a group of balls out along a direction
/// until it clears everything already placed.
nonisolated enum ThemeLayout {
    /// The k-th of n directions spread evenly over the sphere (a Fibonacci
    /// spiral), unit length.
    static func fibonacci(_ k: Int, _ n: Int) -> SIMD3<Double> {
        let count: Double = Double(max(n, 1))
        let y: Double = 1 - (Double(k) + 0.5) * 2 / count
        let ring: Double = max(1 - y * y, 0).squareRoot()
        let angle: Double = Double(k) * GraphUniverse.golden
        return SIMD3<Double>(cos(angle) * ring, y, sin(angle) * ring)
    }

    /// A direction `theta` from +x, at `phi` round it.
    static func cone(theta: Double, phi: Double) -> SIMD3<Double> {
        let side: Double = sin(theta)
        return SIMD3<Double>(cos(theta), side * cos(phi), side * sin(phi))
    }

    /// A turn carrying +x to `d` (unit), twisted by `twist` about it.
    static func frame(along d: SIMD3<Double>, twist: Double) -> UniverseFrame {
        let x: SIMD3<Double> = GraphUniverse.normalize(d)
        let up: SIMD3<Double> = abs(x.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(0, 0, 1)
        var z: SIMD3<Double> = GraphUniverse.normalize(GraphUniverse.cross(x, up))
        var y: SIMD3<Double> = GraphUniverse.cross(z, x)
        if twist != 0 {
            y = GraphUniverse.rotate(y, axis: x, angle: twist)
            z = GraphUniverse.rotate(z, axis: x, angle: twist)
        }
        return UniverseFrame(x: x, y: y, z: z)
    }

    /// Whether `ball` is at least `gap` clear of every placed ball.
    static func clear(_ ball: ThemeBall, of placed: [ThemeBall], gap: Double) -> Bool {
        for other in placed {
            let reach: Double = ball.r + other.r + gap
            let d: SIMD3<Double> = ball.c - other.c
            if GraphUniverse.dot(d, d) < reach * reach { return false }
        }
        return true
    }

    /// The smallest ball holding all of `balls` round their centroid (not
    /// the tightest, but always holding them).
    static func enclosing(_ balls: [ThemeBall]) -> ThemeBall {
        guard !balls.isEmpty else { return ThemeBall(c: SIMD3<Double>(0, 0, 0), r: 0) }
        var sum = SIMD3<Double>(0, 0, 0)
        for b in balls { sum += b.c }
        let middle: SIMD3<Double> = sum / Double(balls.count)
        var reach: Double = 0
        for b in balls { reach = max(reach, GraphUniverse.length(b.c - middle) + b.r) }
        return ThemeBall(c: middle, r: reach)
    }

    /// How far along `dir` (unit) to move `group` - starting at `start`,
    /// in steps of `step` - so every ball in it is `gap` clear of `placed`.
    /// Checks the group's enclosing ball against each placed ball first,
    /// so a far group costs almost nothing. Gives up (and returns the last
    /// distance tried) after `limit` steps, which never happens with sane
    /// steps: far enough out, everything clears.
    static func slide(_ group: [ThemeBall], along dir: SIMD3<Double>, start: Double, step: Double,
                      placed: [ThemeBall], gap: Double, limit: Int = 4000) -> Double {
        let whole: ThemeBall = enclosing(group)
        var s: Double = start
        var tries: Int = 0
        while tries < limit {
            let shift: SIMD3<Double> = dir * s
            if fits(group, whole: whole, shift: shift, placed: placed, gap: gap) { return s }
            s += step
            tries += 1
        }
        return s
    }

    static func fits(_ group: [ThemeBall], whole: ThemeBall, shift: SIMD3<Double>, placed: [ThemeBall],
                     gap: Double) -> Bool {
        let moved = ThemeBall(c: whole.c + shift, r: whole.r)
        for other in placed {
            let reach: Double = moved.r + other.r + gap
            let d: SIMD3<Double> = moved.c - other.c
            if GraphUniverse.dot(d, d) >= reach * reach { continue }
            for b in group {
                let one = ThemeBall(c: b.c + shift, r: b.r)
                if !clear(one, of: [other], gap: gap) { return false }
            }
        }
        return true
    }

    /// Six points round each ball (along the axes), for framing.
    static func points(_ balls: [ThemeBall], around origin: SIMD3<Double>) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(balls.count * 6)
        let x = SIMD3<Double>(1, 0, 0)
        let y = SIMD3<Double>(0, 1, 0)
        let z = SIMD3<Double>(0, 0, 1)
        let axes: [SIMD3<Double>] = [x, -x, y, -y, z, -z]
        for b in balls {
            for a in axes {
                let p: SIMD3<Double> = b.c + a * b.r - origin
                out.append(GraphUniverse.float3(p))
            }
        }
        return out
    }
}
