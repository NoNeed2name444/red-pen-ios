// What a finger or pointer picks on the Performance map, by the same rules
// the other themes use (Graph3DView.pick), but fast at 100k bodies:
// screen-space bins are built once per camera pose from the projected
// bodies, and a touch reads only the 3 x 3 bins round it (0.02 ms at 100k,
// against 12 ms for a world-space ray march at the whole-map framing).
//
// Also the world grid, for local questions in the map's own space (a body's
// neighbours, the nearest note), answered without looking at every body.
// Foundation only, free of Stethoscore types.
import Foundation

/// The bodies as drawn: centre and radius on screen (points), depth in front
/// of the camera. A body behind the camera, or not finite, is never picked.
nonisolated struct GraphPerfScreenPoints: Sendable {
    var x: [Float] = []
    var y: [Float] = []
    var radius: [Float] = []
    var depth: [Float] = []
    var isNote: [Bool] = []

    var count: Int { x.count }
    func pickable(_ i: Int) -> Bool {
        depth[i] > 0 && x[i].isFinite && y[i].isFinite && radius[i].isFinite && depth[i].isFinite
    }
}

nonisolated enum GraphPerfPick {
    /// A finger's reach for rule (b); the pointer's.
    static let fingerReach: Float = 28
    static let pointerReach: Float = 16
    /// Slack round every disc, and how close a note must be to beat a folder.
    static let slack: Float = 6
    /// A drag picks up any disc as if it were at least this big.
    static let dragFloor: Float = 12

    // MARK: - The rules, as Graph3DView.pick writes them (the reference)

    /// Brute force over every body: rule (a), else rule (b).
    static func bruteForce(_ p: GraphPerfScreenPoints, x fx: Float, y fy: Float, reach: Float = fingerReach) -> Int? {
        let all = (0..<p.count).filter { p.pickable($0) }
        if let held = holding(p, all, fx, fy, least: 0) { return held }
        return nearest(p, all, fx, fy, reach: reach)
    }

    /// Brute force for a drag: rule (a), then rule (a) with the 12-point floor.
    static func bruteForceDrag(_ p: GraphPerfScreenPoints, x fx: Float, y fy: Float) -> Int? {
        let all = (0..<p.count).filter { p.pickable($0) }
        return holding(p, all, fx, fy, least: 0) ?? holding(p, all, fx, fy, least: dragFloor)
    }

    /// Rule (a): among discs (at least `least`, plus 6 points) holding the
    /// finger, the smallest; unless a nearer one's drawn disc holds that
    /// body's centre (it is in front of it): then the nearer one.
    /// `candidates` must be in ascending order, so ties go as they do there.
    static func holding(_ p: GraphPerfScreenPoints, _ candidates: [Int], _ fx: Float, _ fy: Float, least: Float) -> Int? {
        var smallest = -1
        for i in candidates where distance(p, i, fx, fy) <= max(p.radius[i], least) + slack {
            if smallest < 0 || p.radius[i] < p.radius[smallest] { smallest = i }
        }
        guard smallest >= 0 else { return nil }
        var best = smallest
        for i in candidates where i != smallest && p.depth[i] < p.depth[best]
            && distance(p, i, fx, fy) <= max(p.radius[i], least) + slack {
            let dx = p.x[smallest] - p.x[i], dy = p.y[smallest] - p.y[i]
            if (dx * dx + dy * dy).squareRoot() <= p.radius[i] { best = i }
        }
        return best
    }

    /// Rule (b): the nearest centre within `reach`; within 6 points of it a
    /// note beats a folder, then the smaller, then the first.
    static func nearest(_ p: GraphPerfScreenPoints, _ candidates: [Int], _ fx: Float, _ fy: Float, reach: Float) -> Int? {
        var near = Float.infinity
        for i in candidates { near = min(near, distance(p, i, fx, fy)) }
        guard near <= reach else { return nil }
        var best = -1
        for i in candidates {
            let d = distance(p, i, fx, fy)
            guard d <= reach, d <= near + slack else { continue }
            if best < 0 || (p.isNote[i] && !p.isNote[best])
                || (p.isNote[i] == p.isNote[best] && p.radius[i] < p.radius[best]) { best = i }
        }
        return best
    }

    @inline(__always)
    static func distance(_ p: GraphPerfScreenPoints, _ i: Int, _ fx: Float, _ fy: Float) -> Float {
        let dx = p.x[i] - fx, dy = p.y[i] - fy
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The projected bodies counting-sorted into square bins (96 points), built
/// once per camera pose. Any disc that could hold a finger, or any centre
/// within reach, lies in the 3 x 3 bins round it - except discs wider than a
/// bin, kept on a short list every pick reads.
nonisolated struct GraphPerfScreenBins: Sendable {
    let points: GraphPerfScreenPoints
    let size: Float
    let width: Float, height: Float
    let columns: Int, rows: Int
    private let start: [Int32]
    private let items: [Int32]
    private let wide: [Int32]

    init(_ points: GraphPerfScreenPoints, width: Float, height: Float, size: Float = 96) {
        self.points = points
        self.size = size
        self.width = width
        self.height = height
        columns = max(1, Int((width / size).rounded(.up)))
        rows = max(1, Int((height / size).rounded(.up)))
        var keys = [Int32](repeating: -1, count: points.count)
        var wide: [Int32] = []
        for i in 0..<points.count where points.pickable(i) {
            // a disc too wide for its neighbours' bins is read every time
            if points.radius[i] > size - GraphPerfPick.slack { wide.append(Int32(i)); continue }
            // off-screen bodies go in the edge bins: still found by a nearby finger
            let bx = min(max(Int((points.x[i] / size).rounded(.down)), 0), columns - 1)
            let by = min(max(Int((points.y[i] / size).rounded(.down)), 0), rows - 1)
            keys[i] = Int32(by * columns + bx)
        }
        let bucketed = GraphPerfGraph.buckets(count: columns * rows, keys: keys)
        start = bucketed.start
        items = bucketed.items
        self.wide = wide
    }

    /// Rule (a), else rule (b) within `reach` (28 for a finger, 16 for the pointer).
    func pick(x: Float, y: Float, reach: Float = GraphPerfPick.fingerReach) -> Int? {
        let near = candidates(x, y, reach: reach)
        return GraphPerfPick.holding(points, near, x, y, least: 0)
            ?? GraphPerfPick.nearest(points, near, x, y, reach: reach)
    }

    /// What a drag starting here picks up: rule (a), then with the 12-point floor.
    func dragPick(x: Float, y: Float) -> Int? {
        let near = candidates(x, y, reach: 0)
        return GraphPerfPick.holding(points, near, x, y, least: 0)
            ?? GraphPerfPick.holding(points, near, x, y, least: GraphPerfPick.dragFloor)
    }

    /// Every body that could matter to a touch here, ascending. A touch off
    /// the screen, or a reach wider than a bin, falls back to all of them.
    func candidates(_ fx: Float, _ fy: Float, reach: Float) -> [Int] {
        guard fx >= 0, fy >= 0, fx < width, fy < height, reach <= size,
              GraphPerfPick.dragFloor + GraphPerfPick.slack <= size else {
            return (0..<points.count).filter { points.pickable($0) }
        }
        let bx = Int(fx / size), by = Int(fy / size)
        var out = wide.map { Int($0) }
        for row in max(by - 1, 0)...min(by + 1, rows - 1) {
            for col in max(bx - 1, 0)...min(bx + 1, columns - 1) {
                let b = row * columns + col
                for k in Int(start[b])..<Int(start[b + 1]) { out.append(Int(items[k])) }
            }
        }
        out.sort()
        return out
    }
}

/// A hashed uniform grid over world positions: cells of `cell` units hashed
/// into a table twice the number of points, counting-sorted (built in about
/// 3 ms at 100k). Queries visit each table bucket once.
nonisolated struct GraphPerfWorldGrid: Sendable {
    let points: [SIMD3<Float>]
    let cell: Float
    private let mask: Int
    private let start: [Int32]
    private let items: [Int32]

    init(_ points: [SIMD3<Float>], cell: Float) {
        self.points = points
        self.cell = cell
        var size = 1
        while size < 2 * max(points.count, 1) { size <<= 1 }
        mask = size - 1
        var keys = [Int32](repeating: 0, count: points.count)
        for (i, p) in points.enumerated() { keys[i] = Int32(Self.hash(Self.cellOf(p, cell), mask)) }
        let bucketed = GraphPerfGraph.buckets(count: size, keys: keys)
        start = bucketed.start
        items = bucketed.items
    }

    static func cellOf(_ p: SIMD3<Float>, _ cell: Float) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    static func hash(_ c: SIMD3<Int32>, _ mask: Int) -> Int {
        let h = UInt32(bitPattern: c.x) &* 73_856_093 ^ UInt32(bitPattern: c.y) &* 19_349_663
            ^ UInt32(bitPattern: c.z) &* 83_492_791
        return Int(h) & mask
    }

    /// Every point within `radius` of `p`, ascending.
    func within(_ radius: Float, of p: SIMD3<Float>) -> [Int] {
        var out: [Int] = []
        var visited = Set<Int>()
        let c = Self.cellOf(p, cell)
        let span = Int32((radius / cell).rounded(.up))
        for dx in -span...span { for dy in -span...span { for dz in -span...span {
            let b = Self.hash(c &+ SIMD3(dx, dy, dz), mask)
            guard visited.insert(b).inserted else { continue }
            for k in Int(start[b])..<Int(start[b + 1]) {
                let i = Int(items[k]), d = points[i] - p
                if (d * d).sum() <= radius * radius { out.append(i) }
            }
        } } }
        return out.sorted()
    }

    /// The k points nearest `p` (ties by index), leaving out `excluding`:
    /// rings of cells outwards until the k-th found is nearer than any
    /// unvisited cell can be.
    func nearest(_ k: Int, to p: SIMD3<Float>, excluding: Int = -1) -> [Int] {
        let wanted = min(k, points.count - (excluding >= 0 && excluding < points.count ? 1 : 0))
        guard wanted > 0 else { return [] }
        var found: [(Float, Int)] = []
        var visited = Set<Int>()
        let c = Self.cellOf(p, cell)
        var ring: Int32 = 0
        while true {
            for dx in -ring...ring { for dy in -ring...ring { for dz in -ring...ring
                where max(abs(dx), abs(dy), abs(dz)) == ring {
                let b = Self.hash(c &+ SIMD3(dx, dy, dz), mask)
                guard visited.insert(b).inserted else { continue }
                for q in Int(start[b])..<Int(start[b + 1]) {
                    let i = Int(items[q])
                    if i == excluding { continue }
                    let d = points[i] - p
                    found.append(((d * d).sum(), i))
                }
            } } }
            // anything not yet seen is at least `ring` whole cells away
            if found.count >= wanted {
                found.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
                let bound = Float(ring) * cell
                if found[wanted - 1].0 <= bound * bound || visited.count > mask { return found.prefix(wanted).map { $0.1 } }
            }
            ring += 1
        }
    }
}
