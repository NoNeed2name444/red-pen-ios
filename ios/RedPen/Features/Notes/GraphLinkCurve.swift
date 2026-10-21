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
}

nonisolated enum GraphLinkCurve {
    /// The longest distance along a link the shader's texture coordinate
    /// carries (it packs the style pair and seed above it, 64 apart).
    static let alongCap: Float = 60

    /// The point `t` of the way along the grown part of the link (0 to 1).
    static func point(_ path: GraphLinkPath, _ t: Float) -> SIMD3<Float> {
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

