import Foundation

// MARK: - Lines: Curved / Straight
//
// One choice for both Ideas modes: how a link between two ideas is drawn.
// Curved (the standard, today's look) keeps each 3D theme's own shape -
// the Space's arches and black-hole curls, the Neurons' axons, the Circuit's
// routed 45° traces - and bows the 2D board's connectors gently. Straight
// draws every link as one direct segment between its two trimmed ends, in
// every theme and on the board.
//
// Set in Settings > Look and feel and in the Look menu of the 3D map and the
// board; both read the same stored Bool (SpaceSettings.straightLinesKey).
//
// Foundation only: tested on Linux (Tests/LineStyleTests.swift).

/// How links are drawn in the Ideas map and on the board.
nonisolated enum GraphLineStyle: String, CaseIterable, Sendable, Identifiable {
    case curved
    case straight

    var id: String { rawValue }

    /// Where it is stored: a Bool, true for Straight.
    static let key: String = "vignette.ideas.straightLines"
    /// Until the owner chooses: Curved, today's look.
    static let standard: GraphLineStyle = .curved

    var title: String {
        switch self {
        case .curved: return "Curved"
        case .straight: return "Straight"
        }
    }

    var isStraight: Bool { self == .straight }

    /// The stored Bool read back (nothing stored: the standard).
    static func stored(_ straight: Bool?) -> GraphLineStyle {
        guard let straight else { return standard }
        return straight ? .straight : .curved
    }

    /// `-ideasLines straight` (or `curved`) at launch: that style for this
    /// run whatever is stored, for the design preview's pictures (the
    /// owner's stored choice is not read). Nil without it.
    static let launchOverride: GraphLineStyle? = parse(arguments: ProcessInfo.processInfo.arguments)

    static func parse(arguments: [String]) -> GraphLineStyle? {
        guard let at = arguments.firstIndex(of: "-ideasLines"), at + 1 < arguments.count else { return nil }
        return GraphLineStyle(rawValue: arguments[at + 1])
    }

    /// The style in force, given the stored Bool (as a view holds it).
    static func inForce(_ stored: Bool) -> GraphLineStyle {
        if let forced = launchOverride { return forced }
        return stored ? .straight : .curved
    }

    /// The choice in force now, read from the defaults.
    static var current: GraphLineStyle {
        if let forced = launchOverride { return forced }
        let raw: Any? = UserDefaults.standard.object(forKey: key)
        return stored(raw as? Bool)
    }
}

/// The choice as the render thread reads it, every frame, without touching
/// UserDefaults: cached here and refreshed whenever the defaults change (a
/// flip of the setting redraws the links on the next frame they are
/// written, with no rebuild of the scene).
nonisolated final class GraphLineStyleLive: @unchecked Sendable {
    static let shared = GraphLineStyleLive()

    private let lock = NSLock()
    private var straight: Bool
    private var token: NSObjectProtocol?

    private init() {
        straight = GraphLineStyle.current.isStraight
        let centre: NotificationCenter = NotificationCenter.default
        token = centre.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                   queue: nil) { [weak self] _ in
            self?.reload()
        }
    }

    /// Whether links are drawn straight now.
    var isStraight: Bool {
        lock.lock()
        defer { lock.unlock() }
        return straight
    }

    /// Reads the stored choice again.
    func reload() {
        let now: Bool = GraphLineStyle.current.isStraight
        lock.lock()
        straight = now
        lock.unlock()
    }
}

// MARK: - The 3D map's straight segment

/// A link drawn Straight in the 3D map: `count + 1` points evenly spaced on
/// the direct segment from its trimmed start towards its trimmed end, as far
/// as it has grown - the same thing GraphLinkCurve.sample gives the ribbon
/// writer for a curve, so the length coordinate (and the impulses, packets
/// and flow that run on it) follows the straight path unchanged.
nonisolated enum GraphStraightLine {
    /// Fills `points` and `lengths` (reused; grown as needed, never shrunk)
    /// and returns the drawn length. `grow` (0 to 1) is how far along the
    /// segment the link has grown from its start.
    @discardableResult
    static func sample(from start: SIMD3<Float>, to end: SIMD3<Float>, grow: Float, count: Int,
                       points: inout [SIMD3<Float>], lengths: inout [Float]) -> Float {
        let n: Int = max(count, 1)
        if points.count < n + 1 {
            points = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n + 1)
        }
        if lengths.count < n + 1 {
            lengths = [Float](repeating: 0, count: n + 1)
        }
        let grown: Float = min(max(grow, 0), 1)
        let run: SIMD3<Float> = (end - start) * grown
        let total: Float = size(run)
        let step: Float = 1 / Float(n)
        for k in 0...n {
            let f: Float = Float(k) * step
            points[k] = start + run * f
            lengths[k] = total * f
        }
        // the last point exactly on the end, free of rounding
        points[n] = start + run
        lengths[n] = total
        return total
    }

    static func size(_ v: SIMD3<Float>) -> Float {
        let squared: Float = v.x * v.x + v.y * v.y + v.z * v.z
        return squared.squareRoot()
    }
}

// MARK: - The 2D board's connectors

/// A connector's shape on the idea board, between two card centres `p` and
/// `q` (always passed in the same order for a pair, so every bow leans the
/// same way). Curved: a quadratic bow to the left of p-to-q, its control
/// `bow` of the length off the middle - symmetric end to end; several links
/// between one pair (lanes) fan out, each bowed a different amount, so they
/// never lie on one another. Straight: the direct segment, lanes set side
/// by side `laneGap` apart.
///
/// Drawing, any arrowhead (endDirection) and any hit test (distance) all go
/// through `point`, so they follow the shape chosen.
nonisolated enum IdeaLinkShape {
    /// Today's gentle bow: the control this much of the length off the
    /// middle (the curve's middle, half as far).
    static let bow: Double = 0.18
    /// How much more (or less) each further lane bows.
    static let fanStep: Double = 0.14
    /// Points between side-by-side straight lanes.
    static let laneGap: Double = 10

    /// Lane `lane` of `lanes`, centred on 0: -0.5 and 0.5 for two.
    static func laneOffset(_ lane: Int, of lanes: Int) -> Double {
        let count: Int = max(lanes, 1)
        let middle: Double = Double(count - 1) / 2
        return Double(lane) - middle
    }

    /// How much a curved lane bows (a fraction of the length).
    static func bowFactor(lane: Int, of lanes: Int) -> Double {
        let shift: Double = laneOffset(lane, of: lanes)
        return bow + fanStep * shift
    }

    /// The quadratic's control point for a curved link.
    static func control(from p: CGPoint, to q: CGPoint, lane: Int = 0, lanes: Int = 1) -> CGPoint {
        let factor: Double = bowFactor(lane: lane, of: lanes)
        let dx: Double = Double(q.x - p.x)
        let dy: Double = Double(q.y - p.y)
        let midX: Double = Double(p.x + q.x) / 2
        let midY: Double = Double(p.y + q.y) / 2
        let x: Double = midX - dy * factor
        let y: Double = midY + dx * factor
        return CGPoint(x: x, y: y)
    }

    /// A straight link's two ends, moved sideways for its lane.
    static func straightEnds(from p: CGPoint, to q: CGPoint, lane: Int = 0,
                             lanes: Int = 1) -> (CGPoint, CGPoint) {
        let shift: Double = laneOffset(lane, of: lanes) * laneGap
        let dx: Double = Double(q.x - p.x)
        let dy: Double = Double(q.y - p.y)
        let length: Double = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001, shift != 0 else { return (p, q) }
        let sideX: Double = -dy / length * shift
        let sideY: Double = dx / length * shift
        let a = CGPoint(x: Double(p.x) + sideX, y: Double(p.y) + sideY)
        let b = CGPoint(x: Double(q.x) + sideX, y: Double(q.y) + sideY)
        return (a, b)
    }

    /// The point `t` of the way along (0 to 1).
    static func point(_ style: GraphLineStyle, from p: CGPoint, to q: CGPoint, lane: Int = 0,
                      lanes: Int = 1, t: Double) -> CGPoint {
        if style.isStraight {
            let ends: (CGPoint, CGPoint) = straightEnds(from: p, to: q, lane: lane, lanes: lanes)
            return lerp(ends.0, ends.1, t)
        }
        let k: CGPoint = control(from: p, to: q, lane: lane, lanes: lanes)
        let s: Double = 1 - t
        let w0: Double = s * s
        let w1: Double = 2 * s * t
        let w2: Double = t * t
        let x: Double = Double(p.x) * w0 + Double(k.x) * w1 + Double(q.x) * w2
        let y: Double = Double(p.y) * w0 + Double(k.y) * w1 + Double(q.y) * w2
        return CGPoint(x: x, y: y)
    }

    /// `count + 1` points along it, end to end.
    static func samples(_ style: GraphLineStyle, from p: CGPoint, to q: CGPoint, lane: Int = 0,
                        lanes: Int = 1, count: Int = 24) -> [CGPoint] {
        let n: Int = max(count, 1)
        var result: [CGPoint] = []
        result.reserveCapacity(n + 1)
        for k in 0...n {
            let t: Double = Double(k) / Double(n)
            result.append(point(style, from: p, to: q, lane: lane, lanes: lanes, t: t))
        }
        return result
    }

    /// The way it runs into `q`, unit length (for an arrowhead there).
    static func endDirection(_ style: GraphLineStyle, from p: CGPoint, to q: CGPoint, lane: Int = 0,
                             lanes: Int = 1) -> CGPoint {
        let before: CGPoint = point(style, from: p, to: q, lane: lane, lanes: lanes, t: 0.98)
        let end: CGPoint = point(style, from: p, to: q, lane: lane, lanes: lanes, t: 1)
        return unit(CGPoint(x: end.x - before.x, y: end.y - before.y))
    }

    /// How far `spot` is from the link as drawn (for a hit test).
    static func distance(from spot: CGPoint, to style: GraphLineStyle, from p: CGPoint, to q: CGPoint,
                         lane: Int = 0, lanes: Int = 1) -> Double {
        let line: [CGPoint] = samples(style, from: p, to: q, lane: lane, lanes: lanes, count: style.isStraight ? 1 : 32)
        var best: Double = Double.greatestFiniteMagnitude
        for k in 1..<line.count {
            let d: Double = segmentDistance(spot, line[k - 1], line[k])
            best = min(best, d)
        }
        return best
    }

    /// Each link's lane among the links joining the same two cards: `keys`
    /// names each link's pair (in the order the links come); the result is
    /// (its lane, how many share the pair).
    static func lanes(for keys: [String]) -> [(lane: Int, lanes: Int)] {
        var counts: [String: Int] = [:]
        for key in keys { counts[key, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var result: [(lane: Int, lanes: Int)] = []
        result.reserveCapacity(keys.count)
        for key in keys {
            let lane: Int = seen[key, default: 0]
            seen[key] = lane + 1
            result.append((lane: lane, lanes: counts[key] ?? 1))
        }
        return result
    }

    // MARK: helpers

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let x: Double = Double(a.x) + Double(b.x - a.x) * t
        let y: Double = Double(a.y) + Double(b.y - a.y) * t
        return CGPoint(x: x, y: y)
    }

    static func unit(_ v: CGPoint) -> CGPoint {
        let x: Double = Double(v.x)
        let y: Double = Double(v.y)
        let length: Double = (x * x + y * y).squareRoot()
        guard length > 0.000001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: x / length, y: y / length)
    }

    /// The distance from `c` to the segment a-b.
    static func segmentDistance(_ c: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let abx: Double = Double(b.x - a.x)
        let aby: Double = Double(b.y - a.y)
        let acx: Double = Double(c.x - a.x)
        let acy: Double = Double(c.y - a.y)
        let span: Double = abx * abx + aby * aby
        var f: Double = 0
        if span > 0.0000001 { f = min(max((acx * abx + acy * aby) / span, 0), 1) }
        let dx: Double = acx - abx * f
        let dy: Double = acy - aby * f
        return (dx * dx + dy * dy).squareRoot()
    }
}
