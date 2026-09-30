import Foundation

// MARK: - One link's path, as one smooth curve
//
// The path a link takes, worked out as a continuous function of s (0 at its
// sending end, 1 at its receiving end) so it can be sampled as finely as the
// Graphics budget allows (GraphicsBudget.linkSamples) and always reads as
// one unbroken curve: a straight run between the two trims, bowed by a
// smooth parabola when it arches round a galaxy's core, and bent by a
// smoothstep near a black hole (pulled into its disk's plane and swung
// round its axis) or a gas giant (pulled towards its ring's plane), and -
// a Neurons axon - meandering gently (GraphLinkWander). Every piece has a
// continuous tangent, so no sample count shows a kink.
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
    /// A gentle meander (a Neurons axon's); nil runs it straight.
    var wander: GraphLinkWander? = nil
}

/// A gentle, organic meander: a Neurons axon's (GraphRibbonWriter sets it
/// on every link when it draws axons). The link strays from its straight
/// run along two directions square to it - fixed for the link, from its
/// seed - on two slow sine waves under a sin² envelope, so it leaves and
/// arrives square to both cells: at most `most` along the first
/// direction and 0.6 of it along the second. It is
/// shape, not motion: the same every frame (still with Reduce Motion).
/// The directions come from a fixed reference direction (`lean`, `turn`)
/// crossed with the link's, so they turn smoothly as the cells move; the
/// meander fades out as the link comes in line with that reference rather
/// than letting them spin.
nonisolated struct GraphLinkWander: Sendable, Equatable {
    /// How far it strays at most (along the first direction), as a share
    /// of the straight run, and in world units.
    var share: Float = 0.045
    var most: Float = 0.1
    /// Waves along the run (the second direction's are 1.9 times as many)
    /// and where they start.
    var waves: Float
    var phase: Float
    /// The reference direction: its height (-1 to 1) and its turn round.
    var lean: Float
    var turn: Float

    /// A Neurons axon's, from its seed: one S or a little more.
    static func neuron(seed: Int) -> GraphLinkWander {
        let waves: Float = 0.7 + 0.8 * fraction(seed, 0.7548777)
        let phase: Float = 6.2831853 * fraction(seed, 0.5698403)
        let lean: Float = 2 * fraction(seed, 0.3819660) - 1
        let turn: Float = 6.2831853 * fraction(seed, 0.8566748)
        return GraphLinkWander(waves: waves, phase: phase, lean: lean, turn: turn)
    }

    /// 0...1 from a seed, well spread over neighbouring seeds.
    static func fraction(_ seed: Int, _ step: Float) -> Float {
        let n: Float = Float(abs(seed) % 1009) + 1
        let v: Float = n * step
        return v - v.rounded(.down)
    }

    /// The offsets along the two directions `s` of the way along (0 to 1)
    /// a run `run` long: none at either end.
    func offset(_ s: Float, run: Float) -> SIMD2<Float> {
        let e: Float = sin(Float.pi * s)
        let size: Float = min(share * run, most) * e * e
        let one: Float = sin(6.2831853 * waves * s + phase)
        let two: Float = sin(6.2831853 * waves * 1.9 * s + phase * 1.7)
        return SIMD2<Float>(size * one, size * 0.6 * two)
    }

    /// The two directions for a run along unit `dir`, already scaled by
    /// how far the meander shows (fading as `dir` meets the reference).
    func axes(_ dir: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let ring: Float = max(1 - lean * lean, 0).squareRoot()
        let ref = SIMD3<Float>(cos(turn) * ring, lean, sin(turn) * ring)
        let across: SIMD3<Float> = GraphLinkCurve.cross(dir, ref)
        let size: Float = GraphLinkCurve.length(across)
        guard size > 0.0001 else { return (SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0)) }
        let first: SIMD3<Float> = across / size
        let second: SIMD3<Float> = GraphLinkCurve.cross(dir, first)
        let show: Float = min(size / 0.35, 1)
        return (first * show, second * show)
    }
}

/// A meander worked out for one path (GraphLinkCurve.meander).
nonisolated struct GraphLinkMeander: Sendable {
    let wander: GraphLinkWander
    let one: SIMD3<Float>
    let two: SIMD3<Float>
    let run: Float
}

nonisolated enum GraphLinkCurve {
    /// The longest distance along a link the shader's texture coordinate
    /// carries (it packs the style pair and seed above it, 64 apart).
    static let alongCap: Float = 60

    /// The point `t` of the way along the grown part of the link (0 to 1).
    static func point(_ path: GraphLinkPath, _ t: Float) -> SIMD3<Float> {
        point(path, t, meander: meander(path))
    }

    /// A meandering path's two directions and straight run, worked out
    /// once for all its samples (nil: no meander).
    static func meander(_ path: GraphLinkPath) -> GraphLinkMeander? {
        guard let wander = path.wander, path.route == nil else { return nil }
        let run: SIMD3<Float> = path.end - path.start
        let size: Float = length(run)
        guard size > 0.0001 else { return nil }
        let (one, two) = wander.axes(run / size)
        return GraphLinkMeander(wander: wander, one: one, two: two, run: size)
    }

    static func point(_ path: GraphLinkPath, _ t: Float, meander: GraphLinkMeander?) -> SIMD3<Float> {
        if let route = path.route { return route.point(t * path.grow) }
        let s: Float = t * path.grow
        let run: SIMD3<Float> = path.end - path.start
        var p: SIMD3<Float> = path.start + run * s
        if path.archSize > 0 {
            let hump: Float = 4 * s * (1 - s) * path.archSize
            p += path.arch * hump
        }
        if let m = meander {
            let w: SIMD2<Float> = m.wander.offset(s, run: m.run)
            p += m.one * w.x + m.two * w.y
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
        let wander: GraphLinkMeander? = meander(path)
        for k in 0...n {
            points[k] = point(path, Float(k) * step, meander: wander)
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
/// another; how round a guide's corners are, and how far above the board
/// it lies. Set for the Circuit theme (GraphCircuit).
nonisolated struct GraphLinkBoard: Sendable, Equatable {
    let right: SIMD3<Float>
    let forward: SIMD3<Float>
    let normal: SIMD3<Float>
    /// The radius of a guide's rounded 45° corners.
    var corner: Float = 0.07
    /// How far a guide lies above the board.
    var lift: Float = 0.012
    /// How much higher each class of guide lies than the one before it
    /// (GraphCircuitMap.guideClass): the shader reads the class back from
    /// the height, as nothing else in a strip can carry it.
    var step: Float = 0.004
    /// How far a wire runs straight out of its part, past the part's trim,
    /// before it may turn through 45°: all the lanes fanning out of one
    /// page's ring split at the same place.
    var stem: Float = 0.07
    /// How far a guide runs on past a joint it ends at (a part with no
    /// trim), so two guides meeting at a corner leave no notch.
    var overhang: Float = 0.02
    /// The circuit's own map of its wiring (GraphCircuitLook fills it):
    /// what rests where and how far the light has come to reach it. Nil
    /// draws every guide alike, starting its pulse at its own start.
    var circuit: GraphCircuitMap? = nil
}

/// A body of the circuit as the routes see it: where it rests on the
/// board, how far along the wiring the light has come from its circuit's
/// source to reach it, and what it is (GraphCircuitMap's kinds).
nonisolated struct GraphCircuitSpot: Sendable, Equatable {
    let at: SIMD2<Float>
    let dist: Float
    let kind: Int
}

/// Every body of the circuits by where it rests, so a route between two of
/// them can tell a trunk from a branch, a return rail from a link, and
/// where along it the pulse of light is. A body that has moved from its
/// rest (dragged) is not found, and its guides are drawn as plain
/// branches or links until it settles.
nonisolated struct GraphCircuitMap: Sendable, Equatable {
    /// Kinds: a note's part, a chip, a joint on a trunk, a joint on a
    /// return rail, a circuit's source, a port on a tile's edge.
    static let part: Int = 0
    static let chip: Int = 1
    static let joint: Int = 2
    static let rail: Int = 3
    static let source: Int = 4
    static let port: Int = 5
    /// Guide classes, as the height above the board carries them: a
    /// branch, the trunk (a source's feed, a chip's trunk down its tile)
    /// and a return rail on the wiring; a link between two notes, a link's
    /// leg to a port and the fibre between two ports on the links.
    static let branch: Int = 0
    static let trunk: Int = 1
    static let returnRail: Int = 2
    static let link: Int = 0
    static let leg: Int = 1
    static let fibre: Int = 2

    /// The distance between two pulses along the wiring (the shaders'
    /// `rpSpacing`): a route's phase is its start's distance modulo this.
    var spacing: Float
    private(set) var cells: [Int64: [GraphCircuitSpot]] = [:]

    init(spacing: Float) {
        self.spacing = spacing
    }

    /// The grid a spot is filed in: 1/32 of a unit.
    static func cell(_ q: SIMD2<Float>) -> (Int, Int) {
        let x: Int = Int((q.x * 32).rounded())
        let y: Int = Int((q.y * 32).rounded())
        return (x, y)
    }

    static func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(x) &* 1_000_003 &+ Int64(y)
    }

    mutating func add(_ spot: GraphCircuitSpot) {
        let (x, y) = Self.cell(spot.at)
        cells[Self.key(x, y), default: []].append(spot)
    }

    /// The body resting at `q` (within a hundredth), or nil.
    func find(_ q: SIMD2<Float>) -> GraphCircuitSpot? {
        let (x, y) = Self.cell(q)
        var best: GraphCircuitSpot? = nil
        var nearest: Float = 0.0001
        for dx in -1...1 {
            for dy in -1...1 {
                guard let list = cells[Self.key(x + dx, y + dy)] else { continue }
                for spot in list {
                    let d: SIMD2<Float> = spot.at - q
                    let gap: Float = d.x * d.x + d.y * d.y
                    if gap < nearest {
                        nearest = gap
                        best = spot
                    }
                }
            }
        }
        return best
    }

    /// The class of a guide from `a` to `b`, `run` apart on the board: a
    /// port at an end makes a leg, ports at both a fibre; a rail joint to
    /// the next one up (or into the source) a return rail; the source, a
    /// chip or a joint straight down to a chip or a joint the trunk;
    /// anything else, or an end not found, a branch (or a link).
    static func guideClass(_ a: GraphCircuitSpot?, _ b: GraphCircuitSpot?, run: SIMD2<Float>) -> Int {
        guard let a, let b else { return branch }
        if a.kind == port && b.kind == port { return fibre }
        if a.kind == port || b.kind == port { return leg }
        if a.kind == rail && (b.kind == rail || b.kind == source) { return returnRail }
        let feeds: Bool = a.kind == source || a.kind == chip || a.kind == joint
        let takes: Bool = b.kind == chip || b.kind == joint
        let down: Bool = abs(run.x) < 0.005 && run.y < 0
        return feeds && takes && down ? trunk : branch
    }
}

/// One guide's path across a board, routed the way a tidy circuit's is:
/// square to the board's edges, turning only through 45° - straight out of
/// its part along the longer way (the board's `stem` past its trim), a
/// diagonal, straight on into the other part - with each corner rounded (a
/// quadratic curve whose tangent runs on into the straight on each side,
/// so it never kinks), and its height eased from one end's to the other's.
/// Parts in line are joined by one straight run; the lanes a page's ring
/// fans out to all split at one place. A link to a port on a tile's edge
/// takes its diagonal half way instead.
///
/// With the board's circuit map it also knows its class (a trunk, a
/// branch, a return rail; a link, a leg, a fibre), which lifts it by that
/// many of the board's steps, and its `phase`: where the circuit's pulse
/// of light is at its start, so the pulse runs on through every joint.
///
/// Sampled by distance along, but with each corner given extra samples
/// (a tenth of the length's worth each), so even the Smooth budget's
/// twenty points draw every corner round. The visible part runs from
/// `trimA` along it to `trimB` short of its end, clear of both parts; an
/// end with no trim (a joint) runs on the board's `overhang` past it.
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
    /// From one end's centre to the other's (the whole, less the runs on
    /// past joints).
    let span: Float
    /// Its class (GraphCircuitMap.guideClass) and how far that lifts it.
    let kind: Int
    let classLift: Float
    /// How far past a whole number of pulse spacings the light has come at
    /// its visible start (0 without the circuit map): GraphRibbonWriter
    /// adds it to the distance along, so a pulse leaving one guide's end
    /// runs on into the next.
    let phase: Float

    /// A guide from `a` to `b` (points in the space). `seed` is not used:
    /// a tidy circuit routes every guide the same way.
    init(from a: SIMD3<Float>, to b: SIMD3<Float>, board: GraphLinkBoard, trimA: Float, trimB: Float,
         seed: Int) {
        self.board = board
        let qa = SIMD2<Float>(GraphLinkCurve.dot(a, board.right), GraphLinkCurve.dot(a, board.forward))
        let qb = SIMD2<Float>(GraphLinkCurve.dot(b, board.right), GraphLinkCurve.dot(b, board.forward))
        heightA = GraphLinkCurve.dot(a, board.normal)
        heightB = GraphLinkCurve.dot(b, board.normal)
        let d: SIMD2<Float> = qb - qa
        let spotA: GraphCircuitSpot? = board.circuit?.find(qa)
        let spotB: GraphCircuitSpot? = board.circuit?.find(qb)
        let kindNow: Int = GraphCircuitMap.guideClass(spotA, spotB, run: d)
        kind = kindNow
        classLift = Float(kindNow) * board.step
        let ported: Bool = spotA?.kind == GraphCircuitMap.port || spotB?.kind == GraphCircuitMap.port
        let ax: Float = abs(d.x)
        let ay: Float = abs(d.y)
        let sx: Float = d.x >= 0 ? 1 : -1
        let sy: Float = d.y >= 0 ? 1 : -1
        let alongX: Bool = ax >= ay
        let minor: Float = min(ax, ay)
        let straight: Float = max(ax, ay) - minor
        // straight out of the part first, then the diagonal, then on in
        let out: Float = ported ? straight * 0.5 : min(trimA + board.stem, straight)
        let major: SIMD2<Float> = alongX ? SIMD2<Float>(sx, 0) : SIMD2<Float>(0, sy)
        let c1: SIMD2<Float> = qa + major * out
        let c2: SIMD2<Float> = c1 + SIMD2<Float>(sx * minor, sy * minor)
        // an end at a joint runs on a little past it
        let extA: Float = trimA < 0.002 ? board.overhang : 0
        let extB: Float = trimB < 0.002 ? board.overhang : 0
        let first: SIMD2<Float> = GraphLinkRoute.firstWay(qa, c1, c2, qb)
        let last: SIMD2<Float> = GraphLinkRoute.firstWay(qb, c2, c1, qa) * -1
        let start: SIMD2<Float> = qa - first * extA
        let end: SIMD2<Float> = qb + last * extB
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
        span = max(whole - extA - extB, 0)
        let extra: Float = whole * 0.1
        let w1: Float = l1 > 0.00001 ? l1 + extra : 0
        let w3: Float = l3 > 0.00001 ? l3 + extra : 0
        weights = SIMD8<Float>(l0, w1, l2, w3, l4, 0, 0, 0)
        let trimmedA: Float = min(trimA, whole * 0.45)
        let trimmedB: Float = min(trimB, whole * 0.45)
        from = trimmedA
        to = max(whole - trimmedB, trimmedA)
        var ahead: Float = 0
        if let map = board.circuit, let spotA, map.spacing > 0 {
            let reached: Float = spotA.dist + trimmedA - extA
            let turns: Float = (reached / map.spacing).rounded(.down)
            ahead = reached - turns * map.spacing
        }
        phase = ahead
    }

    /// The way a path through `p`, `q`, `r`, `s` first sets off (unit), or
    /// none when all four are one point.
    static func firstWay(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>,
                         _ s: SIMD2<Float>) -> SIMD2<Float> {
        if size(q - p) > 0.00001 { return direction(q - p) }
        if size(r - p) > 0.00001 { return direction(r - p) }
        return direction(s - p)
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
        let h: Float = heightA + (heightB - heightA) * share + board.lift + classLift
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
