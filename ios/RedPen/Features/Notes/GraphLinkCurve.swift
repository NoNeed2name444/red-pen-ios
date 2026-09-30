import Foundation

// MARK: - One link's path, as one smooth curve
//
// The path a link takes, worked out as a continuous function of s (0 at its
// sending end, 1 at its receiving end) so it can be sampled as finely as the
// Graphics budget allows (GraphicsBudget.linkSamples) and always reads as
// one unbroken curve: a straight run between the two trims, bowed by a
// smooth parabola when it arches round a galaxy's core, and bent by a
// smoothstep near a black hole (pulled into its disk's plane and swung
// round its axis) or a gas giant (pulled towards its ring's plane). Every
// piece has a continuous tangent, so no sample count shows a kink.
//
// Plain SIMD3<Float> arithmetic only - no simd module - so the curve is
// tested on Linux (Tests/GraphicsTests.swift) and GraphRibbonWriter draws
// exactly what the test checks.

/// How a link is pulled in near one end: towards the plane square to `axis`
/// through `centre` by `pull` (0 to 1), and swung round the axis by up to
/// `swing` radians.
nonisolated struct GraphLinkBend: Sendable {
    let centre: SIMD3<Float>
    let axis: SIMD3<Float>
    let pull: Float
    let swing: Float

    /// A black hole's (style code 0) or a gas giant's (code 2); nil for any
    /// other style, which leaves the link straight.
    static func forStyle(_ code: Int, centre: SIMD3<Float>, axis: SIMD3<Float>) -> GraphLinkBend? {
        let n: SIMD3<Float> = GraphLinkCurve.unit(axis, or: SIMD3<Float>(0, 1, 0))
        if code == 0 { return GraphLinkBend(centre: centre, axis: n, pull: 0.7, swing: 0.55) }
        if code == 2 { return GraphLinkBend(centre: centre, axis: n, pull: 0.35, swing: 0) }
        return nil
    }
}

/// Everything that fixes one link's path this frame.
nonisolated struct GraphLinkPath: Sendable {
    /// Where it leaves the sending note and reaches the receiving one
    /// (already trimmed to clear their rings).
    var start: SIMD3<Float>
    var end: SIMD3<Float>
    /// Which way it bows, unit length, and how far at the middle.
    var arch: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var archSize: Float = 0
    /// How far it has grown from its sending end, 0 to 1.
    var grow: Float = 1
    /// Bends near the sending (A) and receiving (B) ends.
    var bendA: GraphLinkBend? = nil
    var bendB: GraphLinkBend? = nil
    /// A routed trace on a board (the Circuit theme): when set, it alone
    /// fixes the path (already trimmed), and start, end, arch and bends
    /// are not used.
    var route: GraphLinkRoute? = nil
}

nonisolated enum GraphLinkCurve {
    /// The longest distance along a link the shader's texture coordinate
    /// carries (it packs the style pair and seed above it, 64 apart).
    static let alongCap: Float = 60

    /// The point `t` of the way along the grown part of the link (0 to 1).
    static func point(_ path: GraphLinkPath, _ t: Float) -> SIMD3<Float> {
        if let route = path.route { return route.point(t * path.grow) }
        let s: Float = t * path.grow
        let run: SIMD3<Float> = path.end - path.start
        var p: SIMD3<Float> = path.start + run * s
        if path.archSize > 0 {
            let hump: Float = 4 * s * (1 - s) * path.archSize
            p += path.arch * hump
        }
        if let b = path.bendB { p = bend(p, s: s, b) }
        if let a = path.bendA { p = bend(p, s: 1 - s, a) }
        return p
    }

    /// `count + 1` points evenly spread in t from 0 to 1, into `points`
    /// (reused; it is grown as needed and never shrunk). Returns the
    /// distance along each one, in `lengths`, and the whole length.
    @discardableResult
    static func sample(_ path: GraphLinkPath, count: Int, points: inout [SIMD3<Float>],
                       lengths: inout [Float]) -> Float {
        let n: Int = max(count, 1)
        if points.count < n + 1 {
            points = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n + 1)
        }
        if lengths.count < n + 1 {
            lengths = [Float](repeating: 0, count: n + 1)
        }
        let step: Float = 1 / Float(n)
        for k in 0...n {
            points[k] = point(path, Float(k) * step)
        }
        var total: Float = 0
        lengths[0] = 0
        for k in 1...n {
            total += length(points[k] - points[k - 1])
            lengths[k] = total
        }
        return total
    }

    /// How much to shrink distances along a link so its whole length fits
    /// under alongCap: 1 for any shorter link. The shader's flow then runs
    /// evenly all the way along a long link instead of stopping dead at 60
    /// units (the old cap froze the far stretch of a long link into a flat
    /// band).
    static func alongScale(total: Float) -> Float {
        guard total > alongCap else { return 1 }
        return alongCap / total
    }

    /// The direction along the curve at sample `k` of `n`, from its
    /// neighbours (one-sided at the ends).
    static func tangent(_ points: [SIMD3<Float>], _ k: Int, _ n: Int,
                        fallback: SIMD3<Float>) -> SIMD3<Float> {
        let before: SIMD3<Float> = points[max(k - 1, 0)]
        let after: SIMD3<Float> = points[min(k + 1, n)]
        return unit(after - before, or: fallback)
    }

    /// Bends a point `s` of the way from the far end towards an end (1 at
    /// that end): from s 0.45 on, eased by a smoothstep, pulled towards the
    /// plane and swung round the axis. The point keeps its distance from the
    /// centre, so the link still ends at the trim.
    static func bend(_ p: SIMD3<Float>, s: Float, _ b: GraphLinkBend) -> SIMD3<Float> {
        let t: Float = min(max((s - 0.45) / 0.55, 0), 1)
        let w: Float = t * t * (3 - 2 * t)
        guard w > 0.0001 else { return p }
        var rel: SIMD3<Float> = p - b.centre
        let dist: Float = length(rel)
        guard dist > 0.0001 else { return p }
        let n: SIMD3<Float> = b.axis
        let lift: Float = dot(rel, n) * b.pull * w
        rel -= n * lift
        if b.swing > 0 {
            rel = rotate(rel, about: n, by: b.swing * w * w)
        }
        let now: Float = length(rel)
        guard now > 0.0001 else { return p }
        return b.centre + rel * (dist / now)
    }

    // MARK: vector helpers (no simd module on Linux)

    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let v: SIMD3<Float> = a * b
        return v.x + v.y + v.z
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        let x: Float = a.y * b.z - a.z * b.y
        let y: Float = a.z * b.x - a.x * b.z
        let z: Float = a.x * b.y - a.y * b.x
        return SIMD3<Float>(x, y, z)
    }

    static func length(_ v: SIMD3<Float>) -> Float {
        dot(v, v).squareRoot()
    }

    static func unit(_ v: SIMD3<Float>, or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let size: Float = length(v)
        guard size > 0.00001 else { return fallback }
        return v / size
    }

    /// Any unit direction square to `dir`.
    static func perpendicular(to dir: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(dir.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        return unit(cross(dir, helper), or: SIMD3<Float>(0, 0, 1))
    }

    /// `v` turned by `angle` radians about the unit `axis` (Rodrigues).
    static func rotate(_ v: SIMD3<Float>, about axis: SIMD3<Float>, by angle: Float) -> SIMD3<Float> {
        let c: Float = cos(angle)
        let s: Float = sin(angle)
        let along: SIMD3<Float> = axis * (dot(axis, v) * (1 - c))
        let side: SIMD3<Float> = cross(axis, v) * s
        return v * c + side + along
    }
}

// MARK: - A routed trace

/// A board's plane, in the space's coordinates: its x (`right`), its y
/// (`forward`) and its up (`normal`), all unit length and square to one
/// another; how round a trace's corners are, and how far above the board
/// its copper lies. Set for the Circuit theme (GraphCircuit).
nonisolated struct GraphLinkBoard: Sendable, Equatable {
    let right: SIMD3<Float>
    let forward: SIMD3<Float>
    let normal: SIMD3<Float>
    /// The radius of a trace's rounded 45° corners.
    var corner: Float = 0.09
    /// How far the copper lies above the board.
    var lift: Float = 0.012
}

/// One trace's path across a board, routed the way a board's copper is:
/// square to the board's edges, turning through 45° - straight along the
/// longer way, a diagonal, straight again - with each corner rounded (a
/// quadratic curve whose tangent runs on into the straight on each side,
/// so it never kinks), and its height eased from one end's to the other's.
/// Each end leaves its part at its own pin, to one side of the middle, so
/// traces from one chip fan out instead of lying on top of one another;
/// parts nearly in line are joined by one straight run, and a trace that
/// runs mostly one way keeps its diagonal for the end.
///
/// Sampled by distance along, but with each corner given extra samples
/// (a tenth of the length's worth each), so even the Smooth budget's
/// twenty points draw every corner round. The visible part runs from
/// `trimA` along it to `trimB` short of its end, clear of both parts.
///
/// Foundation only: tested on Linux (Tests/CircuitHierarchyTests).
nonisolated struct GraphLinkRoute: Sendable {
    let board: GraphLinkBoard
    /// The five pieces' ends, on the board: a straight p0-p1, a corner
    /// p1-k1-p2, a straight p2-p3, a corner p3-k2-p4, a straight p4-p5.
    let p0: SIMD2<Float>
    let p1: SIMD2<Float>
    let k1: SIMD2<Float>
    let p2: SIMD2<Float>
    let p3: SIMD2<Float>
    let k2: SIMD2<Float>
    let p4: SIMD2<Float>
    let p5: SIMD2<Float>
    /// The ends' heights above the board's plane.
    let heightA: Float
    let heightB: Float
    /// Each piece's length, the whole length, and each piece's weight
    /// (its length, plus the corners' extra samples).
    let lengths: SIMD8<Float>
    let total: Float
    let weights: SIMD8<Float>
    /// The visible part: from this far along to that far.
    let from: Float
    let to: Float

    /// A trace from `a` to `b` (points in the space): which pins it leaves
    /// from, and where its diagonal falls, come from `seed`.
    init(from a: SIMD3<Float>, to b: SIMD3<Float>, board: GraphLinkBoard, trimA: Float, trimB: Float,
         seed: Int) {
        self.board = board
        let qa = SIMD2<Float>(GraphLinkCurve.dot(a, board.right), GraphLinkCurve.dot(a, board.forward))
        let qb = SIMD2<Float>(GraphLinkCurve.dot(b, board.right), GraphLinkCurve.dot(b, board.forward))
        heightA = GraphLinkCurve.dot(a, board.normal)
        heightB = GraphLinkCurve.dot(b, board.normal)
        let d: SIMD2<Float> = qb - qa
        let alongX: Bool = abs(d.x) >= abs(d.y)
        // each end leaves at its own pin, beside the middle, square to the
        // way the trace sets off
        let h1: Float = GraphLinkRoute.fraction(seed, 0.618034)
        let h2: Float = GraphLinkRoute.fraction(seed, 0.414214)
        let h3: Float = GraphLinkRoute.fraction(seed, 0.302776)
        let side: SIMD2<Float> = alongX ? SIMD2<Float>(0, 1) : SIMD2<Float>(1, 0)
        let start: SIMD2<Float> = qa + side * ((h1 - 0.5) * trimA * 0.7)
        var end: SIMD2<Float> = qb + side * ((h2 - 0.5) * trimB * 0.7)
        // parts nearly in line: one straight run, the end's pin in line
        // with the start's (no jog where a straight run works)
        let minor: Float = alongX ? abs(d.y) : abs(d.x)
        if minor <= max(trimA, trimB) * 0.35 + 0.001 {
            if alongX {
                end.y = start.y
            } else {
                end.x = start.x
            }
        }
        let e: SIMD2<Float> = end - start
        let ax: Float = abs(e.x)
        let ay: Float = abs(e.y)
        let sx: Float = e.x >= 0 ? 1 : -1
        let sy: Float = e.y >= 0 ? 1 : -1
        // mostly one way: straight along it, and the one diagonal at the
        // end (a bus's drops into its parts); else the diagonal part way
        let lean: Bool = min(ax, ay) < max(ax, ay) * 0.4
        let split: Float = lean ? 1 : 0.25 + 0.5 * h3
        var c1: SIMD2<Float>
        var c2: SIMD2<Float>
        if ax >= ay {
            let run: Float = (ax - ay) * split
            c1 = start + SIMD2<Float>(sx * run, 0)
            c2 = c1 + SIMD2<Float>(sx * ay, sy * ay)
        } else {
            let run: Float = (ay - ax) * split
            c1 = start + SIMD2<Float>(0, sy * run)
            c2 = c1 + SIMD2<Float>(sx * ax, sy * ax)
        }
        // round each corner: its curve starts and ends `cut` either side
        let before: Float = GraphLinkRoute.size(c1 - start)
        let middle: Float = GraphLinkRoute.size(c2 - c1)
        let after: Float = GraphLinkRoute.size(end - c2)
        let reach: Float = board.corner * 0.41421356
        let cut1: Float = min(reach, before * 0.45, middle * 0.45)
        let cut2: Float = min(reach, middle * 0.45, after * 0.45)
        let u01: SIMD2<Float> = GraphLinkRoute.direction(c1 - start)
        let u12: SIMD2<Float> = GraphLinkRoute.direction(c2 - c1)
        let u23: SIMD2<Float> = GraphLinkRoute.direction(end - c2)
        p0 = start
        p1 = c1 - u01 * cut1
        k1 = c1
        p2 = c1 + u12 * cut1
        p3 = c2 - u12 * cut2
        k2 = c2
        p4 = c2 + u23 * cut2
        p5 = end
        let l0: Float = GraphLinkRoute.size(p1 - p0)
        let l1: Float = GraphLinkRoute.curveLength(p1, k1, p2)
        let l2: Float = GraphLinkRoute.size(p3 - p2)
        let l3: Float = GraphLinkRoute.curveLength(p3, k2, p4)
        let l4: Float = GraphLinkRoute.size(p5 - p4)
        lengths = SIMD8<Float>(l0, l1, l2, l3, l4, 0, 0, 0)
        let whole: Float = l0 + l1 + l2 + l3 + l4
        total = whole
        let extra: Float = whole * 0.1
        let w1: Float = l1 > 0.00001 ? l1 + extra : 0
        let w3: Float = l3 > 0.00001 ? l3 + extra : 0
        weights = SIMD8<Float>(l0, w1, l2, w3, l4, 0, 0, 0)
        let trimmedA: Float = min(trimA, whole * 0.45)
        let trimmedB: Float = min(trimB, whole * 0.45)
        from = trimmedA
        to = max(whole - trimmedB, trimmedA)
    }

    /// The point `u` of the way along the visible part (0 to 1), in the
    /// space, spaced by weight (so the corners get more of the samples).
    func point(_ u: Float) -> SIMD3<Float> {
        let w0: Float = weightAt(from)
        let w1: Float = weightAt(to)
        let clamped: Float = min(max(u, 0), 1)
        let w: Float = w0 + (w1 - w0) * clamped
        var left: Float = w
        var piece: Int = 0
        while piece < 4 && left > weights[piece] {
            left -= weights[piece]
            piece += 1
        }
        let weight: Float = weights[piece]
        let f: Float = weight > 0.00001 ? min(max(left / weight, 0), 1) : 0
        var gone: Float = 0
        for k in 0..<piece { gone += lengths[k] }
        let along: Float = gone + lengths[piece] * f
        return place(piece: piece, f, along: along)
    }

    /// The weight up to `distance` along.
    func weightAt(_ distance: Float) -> Float {
        var left: Float = distance
        var w: Float = 0
        for k in 0..<5 {
            let l: Float = lengths[k]
            if left <= l || k == 4 {
                let share: Float = l > 0.00001 ? min(max(left / l, 0), 1) : 0
                return w + weights[k] * share
            }
            left -= l
            w += weights[k]
        }
        return w
    }

    /// Where piece `k` is `f` of the way along it, `along` the route.
    private func place(piece k: Int, _ f: Float, along: Float) -> SIMD3<Float> {
        var q: SIMD2<Float>
        switch k {
        case 0: q = p0 + (p1 - p0) * f
        case 1: q = GraphLinkRoute.curve(p1, k1, p2, f)
        case 2: q = p2 + (p3 - p2) * f
        case 3: q = GraphLinkRoute.curve(p3, k2, p4, f)
        default: q = p4 + (p5 - p4) * f
        }
        let share: Float = total > 0.00001 ? along / total : 0
        let h: Float = heightA + (heightB - heightA) * share + board.lift
        let x: SIMD3<Float> = board.right * q.x
        let y: SIMD3<Float> = board.forward * q.y
        return x + y + board.normal * h
    }

    // MARK: helpers

    static func fraction(_ seed: Int, _ step: Float) -> Float {
        let n: Float = Float(abs(seed) % 1009) + 1
        let v: Float = n * step
        return v - v.rounded(.down)
    }

    static func size(_ v: SIMD2<Float>) -> Float {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    static func direction(_ v: SIMD2<Float>) -> SIMD2<Float> {
        let s: Float = size(v)
        return s > 0.000001 ? v / s : SIMD2<Float>(0, 0)
    }

    static func curve(_ a: SIMD2<Float>, _ k: SIMD2<Float>, _ b: SIMD2<Float>, _ f: Float) -> SIMD2<Float> {
        let g: Float = 1 - f
        let first: SIMD2<Float> = a * (g * g) + k * (2 * g * f)
        return first + b * (f * f)
    }

    /// A quadratic curve's length, near enough: between its chord and its
    /// control polygon.
    static func curveLength(_ a: SIMD2<Float>, _ k: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let chord: Float = size(b - a)
        let polygon: Float = size(k - a) + size(b - k)
        return (2 * chord + polygon) / 3
    }
}
