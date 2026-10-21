// The Performance theme's layout: an O(n) deterministic seed that is the
// layout. No force simulation: at 100k notes 20 grid-force passes cost over
// a second and shortened links by only 5%, so each folder is built directly.
//
// - A folder's own notes sit on concentric Fibonacci shells one spacing
//   apart, starting just outside its hub, so no two notes crowd (a single
//   Fibonacci-ball formula let thousands of discs touch).
// - Notes go onto the shells in breadth-first order over the folder's own
//   links, so linked notes sit near each other and the best-linked near the hub.
// - Subfolders' systems are packed round the folder's ball by an exact
//   greedy: for each child, largest first, the nearest clear spot along a
//   fixed set of directions. Top folders and loose groups are packed the
//   same way round the origin.
//
// Foundation only, free of Stethoscore types (its own Fibonacci helper).
import Foundation

nonisolated struct GraphPerfLayout: Sendable {
    /// Notes (graph slots), then one hub per folder.
    let positions: [SIMD3<Float>]
    /// Each body's radius, the same order; fixed whatever the link scale.
    let radius: [Float]
    /// Per system (folders, then loose groups): the centre, the ball that
    /// holds its own notes, and the ball that holds it and every subfolder.
    let systemCentre: [SIMD3<Float>]
    let coreRadius: [Float]
    let systemRadius: [Float]
    let spacing: Float

    static let noteRadius: Float = 0.18
    static let pageRadius: Float = 0.28
    /// Clearance past the outermost shell, more than the largest note.
    static let margin: Float = 0.6

    /// A hub's radius, 0.35 to 1.2, growing with the log of the notes under it.
    static func hubRadius(notes: Int) -> Float {
        min(1.2, 0.35 + 0.085 * Float(log2(Double(1 + notes))))
    }

    /// Points on shell j of a ball whose first shell has radius `first` (in
    /// spacings): about one per 1.1 square spacings of its surface.
    static func shellPoints(_ radius: Float) -> Int {
        max(1, Int((4 * Float.pi * radius * radius / 1.1).rounded()))
    }

    /// The radius (in spacings) of the last shell needed for `count` notes.
    static func lastShell(count: Int, first: Float) -> Float {
        var placed = 0, r = first
        while true {
            placed += shellPoints(r)
            if placed >= count { return r }
            r += 1
        }
    }

    /// The k-th of n points spread evenly over the unit sphere.
    static func fibonacci(_ k: Int, _ n: Int) -> SIMD3<Float> {
        let y: Float = 1 - (Float(k) + 0.5) * 2 / Float(max(n, 1))
        let ring = max(1 - y * y, 0).squareRoot()
        let a = Float(k) * 2.399_963_2 // the golden angle
        return SIMD3(cos(a) * ring, y, sin(a) * ring)
    }

    /// The seed layout, or nil once `isCancelled` says a newer one is wanted
    /// (checked per folder, so a superseded layout stops within milliseconds).
    static func seed(_ g: GraphPerfGraph, isCancelled: () -> Bool = { false }) -> GraphPerfLayout? {
        let n = g.noteCount, fc = g.folderCount, sc = g.systemCount
        let s = g.linkScale > 0 ? g.linkScale : 1

        var radius = [Float](repeating: 0, count: n + fc)
        for i in 0..<n { radius[i] = g.isPage[i] ? pageRadius : noteRadius }
        for f in 0..<fc { radius[n + f] = hubRadius(notes: Int(g.folderSubtreeCount[f])) }

        // each system's own ball: the first shell clears the hub by half a spacing
        var firstShell = [Float](repeating: 0.5, count: sc)
        var core = [Float](repeating: 0, count: sc)
        for sys in 0..<sc {
            let hub: Float = sys < fc ? radius[n + sys] : 0
            firstShell[sys] = hub / s + 0.5
            let count = Int(g.systemNoteStart[sys + 1] - g.systemNoteStart[sys])
            core[sys] = (count > 0 ? lastShell(count: count, first: firstShell[sys]) * s : hub) + margin
        }

        // children before parents: place each folder's subfolders round its ball
        var offset = [SIMD3<Float>](repeating: .zero, count: sc)
        var reach = core
        var packer = Packer()
        for f in GraphPerfGraph.deepestFirst(g.folderDepth) {
            if isCancelled() { return nil }
            let kids = g.folderChildren[Int(g.folderChildStart[f])..<Int(g.folderChildStart[f + 1])].map { Int($0) }
            guard !kids.isEmpty else { continue }
            packer.place(kids, core: core[f], gap: s, reach: reach, offset: &offset)
            for c in kids { reach[f] = max(reach[f], length(offset[c]) + reach[c]) }
        }
        // the top level: top folders and loose groups round the origin
        let tops = (0..<fc).filter { g.folderParent[$0] < 0 } + Array(fc..<sc)
        packer.place(tops, core: 0, gap: 2 * s, reach: reach, offset: &offset)

        // parents before children: absolute centres
        var centre = offset
        for f in GraphPerfGraph.deepestFirst(g.folderDepth).reversed() where g.folderParent[f] >= 0 {
            centre[f] = centre[Int(g.folderParent[f])] + offset[f]
        }

        var positions = [SIMD3<Float>](repeating: .zero, count: n + fc)
        for f in 0..<fc { positions[n + f] = centre[f] }

        // notes: breadth first over the system's own links, each walk from
        // the best unseen root (pages first, then the most linked, then slot)
        var seen = [Bool](repeating: false, count: n)
        var queue = [Int32](repeating: 0, count: n)
        var roots: [UInt64] = []
        for sys in 0..<sc {
            if isCancelled() { return nil }
            let a = Int(g.systemNoteStart[sys]), b = Int(g.systemNoteStart[sys + 1])
            guard b > a else { continue }
            roots.removeAll(keepingCapacity: true)
            for k in a..<b {
                let i = Int(g.systemNotes[k])
                let rank = UInt64(g.isPage[i] ? 0 : 1) << 60 | UInt64(0xFFF_FFFF - min(g.degree(i), 0xFFF_FFFF)) << 32
                roots.append(rank | UInt64(i))
            }
            roots.sort()
            var shells = Shells(count: b - a, first: firstShell[sys], spacing: s, centre: centre[sys])
            var head = 0, tail = 0, cursor = 0
            while cursor < roots.count {
                let root = Int(roots[cursor] & 0xFFFF_FFFF)
                cursor += 1
                if seen[root] { continue }
                seen[root] = true
                queue[tail] = Int32(root); tail += 1
                while head < tail {
                    let i = Int(queue[head]); head += 1
                    positions[i] = shells.next()
                    for e in Int(g.adjStart[i])..<Int(g.adjStart[i + 1]) {
                        let j = Int(g.adjacency[e])
                        if seen[j] || g.systemOfNote[j] != Int32(sys) { continue }
                        seen[j] = true
                        queue[tail] = Int32(j); tail += 1
                    }
                }
            }
        }
        return GraphPerfLayout(positions: positions, radius: radius, systemCentre: centre,
                               coreRadius: core, systemRadius: reach, spacing: s)
    }

    private static func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

    /// Hands out shell positions one by one: shell j has radius first + j
    /// spacings, each shell twisted so neighbouring shells do not line up;
    /// the last shell takes only what is left, spread over its whole sphere.
    struct Shells {
        var left: Int
        let spacing: Float
        let centre: SIMD3<Float>
        var r: Float
        var shell = 0, i = 0, m = 0
        var turn = (cos: Float(1), sin: Float(0))

        init(count: Int, first: Float, spacing: Float, centre: SIMD3<Float>) {
            left = count
            self.spacing = spacing
            self.centre = centre
            r = first
            m = min(GraphPerfLayout.shellPoints(first), count)
        }

        mutating func next() -> SIMD3<Float> {
            if i == m {
                left -= m
                shell += 1
                r += 1
                i = 0
                m = min(GraphPerfLayout.shellPoints(r), left)
                let twist = Float(shell) * 0.7
                turn = (cos(twist), sin(twist))
            }
            let d = GraphPerfLayout.fibonacci(i, m)
            i += 1
            let t = SIMD3(turn.cos * d.x - turn.sin * d.z, d.y, turn.sin * d.x + turn.cos * d.z)
            return centre + t * (r * spacing)
        }
    }

    /// Exact greedy packing of sibling systems round a core ball.
    struct Packer {
        private static let wide = (0..<48).map { fibonacci($0, 48) }
        private static let narrow = (0..<24).map { fibonacci($0, 24) }
        private var spans: [(Float, Float)] = []

        /// Places `list` (system indices) largest first. For each child and
        /// each direction d, a sibling at c with combined reach r forbids
        /// the distances t where |t d - c| < r: t in b -+ sqrt(b^2 - |c|^2 + r^2),
        /// b = d.c. Sweeping those intervals from the core outwards gives the
        /// smallest clear distance; the child takes the nearest over all
        /// directions. 24 directions above 100 siblings keep it quick.
        mutating func place(_ list: [Int], core: Float, gap: Float, reach: [Float], offset: inout [SIMD3<Float>]) {
            let order = list.sorted { reach[$0] != reach[$1] ? reach[$0] > reach[$1] : $0 < $1 }
            let dirs = order.count > 100 ? Self.narrow : Self.wide
            for (k, c) in order.enumerated() {
                var bestT = Float.infinity, bestD = SIMD3<Float>(1, 0, 0)
                for q in 0..<dirs.count {
                    let d = dirs[(q * 7 + k * 13) % dirs.count]
                    var t: Float = core > 0 ? core + reach[c] + gap : (k == 0 ? 0 : reach[c] + gap)
                    spans.removeAll(keepingCapacity: true)
                    for j in 0..<k {
                        let o = offset[order[j]]
                        let r = reach[c] + reach[order[j]] + gap
                        let b = (d * o).sum()
                        let disc = b * b - (o * o).sum() + r * r
                        if disc <= 0 { continue }
                        let root = disc.squareRoot()
                        if b + root > t { spans.append((b - root, b + root)) }
                    }
                    spans.sort { $0.0 < $1.0 }
                    for (lo, hi) in spans {
                        if lo > t { break }
                        if hi > t { t = hi + 1e-4 }
                    }
                    if t < bestT { bestT = t; bestD = d }
                }
                offset[c] = bestD * bestT
            }
        }
    }
}
