import Foundation

// MARK: - A Neurons link: one dendrite joining two cells
//
// The owner asked for links to be dendrites, not axons: "don't use axons
// as connections use dendrites and extend them / make the tube connected
// both ways so the 2 cell surfaces connected become continuous". So a link
// is one glass tube that leaves its first cell's body the way the
// membrane's dendrites leave the soma (GraphNeuronMembrane: blended in with
// a smooth minimum, so the outline flares out of the body and curves into
// the tube without a seam) and joins its second cell's body the same way:
// no myelin, synapse or cup, the same at both ends.
//
// The tube is GraphRibbonWriter's strip, facing the camera, so the join is
// worked out where it is seen: in the plane square to the view each cell is
// a disc of its membrane radius R and the tube a band of half width h along
// the link. Their outline is where the smooth minimum of the two distances
// (the disc's, |p| - R, and the band's, |y| - h) is zero, blended over
// k = `blend` R as the membrane blends its dendrites (0.3). At a seen
// distance x from a cell's centre the outline's half width is then
//   - exactly h from the flare's end, sqrt((R + k)^2 - h^2), outwards;
//   - h + k at the join, sqrt(R^2 - (h + k)^2), where the outline meets the
//     disc's edge, tangent to it (the strip starts there, never nearer the
//     cell's centre);
//   - in between, falling smoothly and steadily (found by bisection: there
//     the smooth minimum rises steadily with the distance across, so it has
//     one zero).
// A link pointing nearly at the camera is foreshortened to a stub: its
// flare eases out as it turns towards the view (`gate`), and its trim is
// capped so the strip stays inside its cells' discs.
//
// The strip's samples crowd towards both ends (`warp`), where the flares
// curve, and are sparse in the middle, where the tube is straight; at each
// the strip is as wide as the wider of its two flares there (`End`,
// `halfWidth(at:)`), so GraphRibbonWriter only places it.
//
// Foundation only: tested on Linux (Tests/GraphLinkBridgeTests.swift).

nonisolated struct GraphLinkBridge: Sendable, Equatable {
    /// A cell's membrane radius over its link trim radius (GraphSim's
    /// radius: the Neurons' cell is `size`, its trim radius 0.8 size).
    var membrane: Float = 1.25
    /// The blend's width over the membrane radius, as the membrane blends
    /// its dendrites into the soma (NeuronMembrane.blend).
    var blend: Float = 0.3

    /// How strongly the samples crowd towards the ends: dt/du runs from
    /// 1 - crowd at the ends to 1 + crowd in the middle.
    static let crowd: Float = 0.85

    /// The polynomial smooth minimum the membrane blends with (width k).
    static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        let over: Float = max(k - abs(a - b), 0)
        return min(a, b) - over * over / (4 * k)
    }

    /// Where the outline meets a cell's disc (its seen distance from the
    /// centre), for membrane radius `r` and tube half width `h`; 0 when the
    /// tube is too thick to meet it beside the centre.
    func join(r: Float, h: Float) -> Float {
        let edge: Float = h + blend * r
        return max(r * r - edge * edge, 0).squareRoot()
    }

    /// Where the flare ends: from here out the tube is its own width.
    func flare(r: Float, h: Float) -> Float {
        let reach: Float = r + blend * r
        return max(reach * reach - h * h, 0).squareRoot()
    }

    /// The outline's half width at seen distance `rho` from a cell's centre
    /// (never nearer than the join).
    func halfWidth(rho: Float, r: Float, h: Float) -> Float {
        guard r > 0.0001, h > 0 else { return h }
        let x: Float = max(rho, join(r: r, h: h))
        if x >= flare(r: r, h: h) { return h }
        let k: Float = blend * r
        var low: Float = 0
        var high: Float = max(h, r) + k
        for _ in 0..<22 {
            let mid: Float = (low + high) * 0.5
            let disc: Float = (x * x + mid * mid).squareRoot() - r
            if Self.smin(disc, mid - h, k) < 0 { low = mid } else { high = mid }
        }
        return max((low + high) * 0.5, h)
    }

    /// How far along the link (in the world) the strip starts from a cell's
    /// centre: at the join, as seen; capped where the link points within 30
    /// degrees of the view, where the join would be far behind or in front.
    func trim(r: Float, h: Float, sine: Float) -> Float {
        join(r: r, h: h) / max(sine, 0.5)
    }

    /// How much of a cell's flare is drawn: all of it while the link is
    /// seen at 30 degrees or more from the view, none within about 17.
    static func gate(sine: Float) -> Float {
        let t: Float = min(max((sine - 0.3) / 0.2, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The sine of the angle between the link (unit `dir`) and the view
    /// towards a cell (unit `view`).
    static func sine(_ dir: SIMD3<Float>, _ view: SIMD3<Float>) -> Float {
        let c: Float = dir.x * view.x + dir.y * view.y + dir.z * view.z
        return max(1 - c * c, 0).squareRoot()
    }

    /// How far a point `rel` from a cell's centre is from it as seen along
    /// unit `view`: the length of its part square to the view.
    static func seen(_ rel: SIMD3<Float>, view: SIMD3<Float>) -> Float {
        let along: Float = rel.x * view.x + rel.y * view.y + rel.z * view.z
        let square: SIMD3<Float> = rel - view * along
        return (square.x * square.x + square.y * square.y + square.z * square.z).squareRoot()
    }

    /// Where sample share `u` (0 to 1) of the strip sits along the link (0
    /// to 1): steadily further, closest together at the ends.
    static func warp(_ u: Float) -> Float {
        let turn: Float = 2 * Float.pi * u
        return u - crowd * sin(turn) / (2 * Float.pi)
    }

    /// One end of a link as its strip is drawn: the cell's centre, its
    /// membrane radius, the unit view towards it, how much of its flare is
    /// drawn and how far along the link from its centre the strip starts.
    struct End: Sendable, Equatable {
        var centre: SIMD3<Float>
        var radius: Float
        var view: SIMD3<Float>
        var gate: Float
        var trim: Float
    }

    /// The end at the cell centred at `centre` (its link trim radius
    /// `radius`, as GraphSim gives it) seen from `eye`, for a link along
    /// unit `dir` of world length `length` and tube half width `h`. The
    /// trim never takes more than 0.45 of the link.
    func end(centre: SIMD3<Float>, radius: Float, eye: SIMD3<Float>, dir: SIMD3<Float>, h: Float,
             length: Float) -> End {
        let r: Float = radius * membrane
        let toward: SIMD3<Float> = eye - centre
        let far: Float = (toward.x * toward.x + toward.y * toward.y + toward.z * toward.z).squareRoot()
        let view: SIMD3<Float> = far > 0.000001 ? toward / far : SIMD3<Float>(0, 0, 1)
        let sine: Float = Self.sine(dir, view)
        return End(centre: centre, radius: r, view: view, gate: Self.gate(sine: sine),
                   trim: min(trim(r: r, h: h, sine: sine), max(length, 0) * 0.45))
    }

    /// The strip's half width at `p` on the link between ends `a` and `b`:
    /// the tube's own, flared where it leaves either cell.
    func halfWidth(at p: SIMD3<Float>, _ a: End, _ b: End, h: Float) -> Float {
        let wa: Float = halfWidth(rho: Self.seen(p - a.centre, view: a.view), r: a.radius, h: h) - h
        let wb: Float = halfWidth(rho: Self.seen(p - b.centre, view: b.view), r: b.radius, h: h) - h
        return h + max(wa * a.gate, wb * b.gate)
    }
}
