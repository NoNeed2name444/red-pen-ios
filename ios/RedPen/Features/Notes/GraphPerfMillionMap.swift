// The million map's data, built once off the main thread from a
// GraphPerfScene (the same graph, seed layout and colours as the 100,000
// map): the octree of chunks, the far bundles, and the arrays the GPU keeps
// for the whole session - a million bodies in about 20 MB (16-bit positions
// with their leaf, 8 bytes, and the same again as the layout's seed; colour
// and size, 4), the links' adjacency (about 19 MB at 2.4 links a note: the
// GPU layout's neighbours, and the selected note's own links, read straight
// from it), and each leaf's box.
//
// Hierarchy: a note's size and brightness grow with how linked it is (the
// log of its degree), so hubs read first and the many leaf notes stay
// quiet; each leaf keeps its two most linked notes as its label candidates.
//
// Bodies keep the scene's numbers outside (a pick, a title, the name pill);
// inside, the GPU works in slots (the octree's sorted order).
//
// Foundation only, free of Stethoscore types.
import Foundation

nonisolated struct GraphPerfMillionMap: Sendable {
    let scene: GraphPerfScene
    let octree: GraphPerfOctree
    let bundles: GraphPerfBundles
    /// Per slot: x, y, z (16-bit across its leaf's box) and its leaf.
    let packed: [UInt16]
    /// Per slot: RGB and, in the top byte, its radius in hundredths (both
    /// already scaled by its importance).
    let looks: [UInt32]
    /// Per slot: its neighbours (slots), adjacencyStart[s] ..< adjacencyStart[s + 1].
    let adjacencyStart: [UInt32]
    let adjacency: [UInt32]
    /// Per leaf: low corner and first slot; extent and count (GraphPerfOctree.leafBoxes).
    let leafBoxes: [SIMD4<Float>]
    /// Per bundle, heaviest first: its two cut cells; and how many links it carries.
    let bundleEnds: [UInt32]
    let bundleWeights: [Float]
    /// Each cut cell's share of the bundle light (overlapShares).
    let bundleShares: [Float]
    /// Per leaf, its two most linked notes (slots; -1 for none): the notes
    /// whose names it may show.
    let leafTops: [Int32]
    /// A note needs this many links to be a leaf's label candidate.
    static let topDegree = 6

    var bodyCount: Int { octree.bodyCount }
    var linkCount: Int { scene.graph.linkCount }
    var centre: SIMD3<Float> { scene.centre }
    var radius: Float { scene.radius }
    var spacing: Float { scene.layout.spacing }

    /// The map for `scene`, or nil once `isCancelled` says a newer one is wanted.
    ///
    /// After the octree, its parts do not depend on each other, so they are
    /// made at once, one a core (the bundles, the slots' positions, their
    /// looks and the leaves' boxes, their adjacency): on a phone's or an
    /// iPad's unoptimised Playgrounds build that is most of the wait.
    static func build(_ scene: GraphPerfScene, leafSize: Int = 384,
                      isCancelled: () -> Bool = { false }) -> GraphPerfMillionMap? {
        let positions = scene.layout.positions
        let t = GraphPerfOctree(positions: positions, colours: scene.colours, leafSize: leafSize)
        if isCancelled() { return nil }
        let (a, b) = lineEnds(scene)
        let parts = Parts()
        DispatchQueue.concurrentPerform(iterations: 4) { part in
            switch part {
            case 0: parts.bundles = GraphPerfBundles(octree: t, a: a, b: b)
            case 1: parts.packed = t.packedPositions(positions)
            case 2:
                parts.looks = slotLooks(t, scene)
                parts.boxes = t.leafBoxes()
            default: parts.adjacency = slotAdjacency(t, a: a, b: b)
            }
        }
        guard let bundles = parts.bundles, !isCancelled() else { return nil }
        return GraphPerfMillionMap(scene: scene, octree: t, bundles: bundles, packed: parts.packed,
                                   looks: parts.looks, adjacency: parts.adjacency, boxes: parts.boxes)
    }

    /// The parts made at once: each written by one thread, read after all are done.
    private final class Parts: @unchecked Sendable {
        var bundles: GraphPerfBundles?
        var packed: [UInt16] = []
        var looks: [UInt32] = []
        var boxes: [SIMD4<Float>] = []
        var adjacency: (start: [UInt32], items: [UInt32]) = ([], [])
    }

    /// Every line's two bodies (links, then the folder tree's lines).
    static func lineEnds(_ scene: GraphPerfScene) -> (a: [Int32], b: [Int32]) {
        let lines = scene.lineCount
        var a = [Int32](repeating: 0, count: lines), b = [Int32](repeating: 0, count: lines)
        scene.lineEnds.withUnsafeBufferPointer { ends in
            a.withUnsafeMutableBufferPointer { pa in
                b.withUnsafeMutableBufferPointer { pb in
                    for k in 0..<lines {
                        pa[k] = Int32(truncatingIfNeeded: ends[2 * k])
                        pb[k] = Int32(truncatingIfNeeded: ends[2 * k + 1])
                    }
                }
            }
        }
        return (a, b)
    }

    private init(scene: GraphPerfScene, octree t: GraphPerfOctree, bundles: GraphPerfBundles, packed: [UInt16],
                 looks: [UInt32], adjacency: (start: [UInt32], items: [UInt32]), boxes: [SIMD4<Float>]) {
        self.scene = scene
        octree = t
        self.bundles = bundles
        self.packed = packed
        self.looks = looks
        adjacencyStart = adjacency.start
        self.adjacency = adjacency.items
        leafBoxes = boxes
        // heaviest first, so a frame short of time draws a prefix and the
        // narrowest, faintest bundles are the ones left out
        let heaviest = (0..<bundles.count).sorted {
            bundles.weight[$0] != bundles.weight[$1] ? bundles.weight[$0] > bundles.weight[$1] : $0 < $1
        }
        var ends = [UInt32](repeating: 0, count: 2 * bundles.count)
        var weights = [Float](repeating: 0, count: bundles.count)
        for (k, from) in heaviest.enumerated() {
            ends[2 * k] = bundles.a[from]
            ends[2 * k + 1] = bundles.b[from]
            weights[k] = bundles.weight[from]
        }
        bundleEnds = ends
        bundleWeights = weights
        bundleShares = Self.overlapShares(ends: ends, cells: bundles.cells.count)
        leafTops = Self.tops(t, start: adjacency.start, notes: scene.graph.noteCount)
    }

    // MARK: - Hierarchy

    /// A note's importance, 0...1, from how many links it has: the log, so
    /// a hub of 63 links is full and a note of one is a sixth.
    static func importance(degree: Int) -> Float {
        min(Float(log2(Double(1 + max(degree, 0)))) / 6, 1)
    }

    /// Its size and brightness factors: a leaf note at 0.8 and 0.78, a hub at 1.5 and 1.
    static func sizeFactor(_ i: Float) -> Float { 0.8 + 0.7 * min(max(i, 0), 1) }
    static func brightnessFactor(_ i: Float) -> Float { 0.78 + 0.22 * min(max(i, 0), 1) }

    /// Per slot: the body's colour and, in the top byte, its radius in
    /// hundredths; a note's both scaled by its importance (folders' hubs
    /// keep theirs: they are already the biggest).
    static func slotLooks(_ t: GraphPerfOctree, _ scene: GraphPerfScene) -> [UInt32] {
        let n = t.bodyCount
        let notes = scene.graph.noteCount
        var look = [UInt32](repeating: 0, count: n)
        t.order.withUnsafeBufferPointer { order in
            scene.layout.radius.withUnsafeBufferPointer { radius in
                scene.colours.withUnsafeBufferPointer { colours in
                    scene.graph.adjStart.withUnsafeBufferPointer { adjStart in
                        look.withUnsafeMutableBufferPointer { out in
                            for s in 0..<n {
                                let body = Int(order[s])
                                var r = radius[body]
                                var colour = colours[body]
                                if body < notes && body + 1 < adjStart.count {
                                    let i = importance(degree: Int(adjStart[body + 1] - adjStart[body]))
                                    r *= sizeFactor(i)
                                    colour = scaled(colour, brightnessFactor(i))
                                }
                                let code = UInt32(min(max((r * 100).rounded(), 1), 255))
                                out[s] = colour & 0x00FF_FFFF | code << 24
                            }
                        }
                    }
                }
            }
        }
        return look
    }

    /// An RGBA8 colour's RGB times `k` (alpha kept).
    static func scaled(_ colour: UInt32, _ k: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let v = Float((colour >> shift) & 0xFF) * k
            return UInt32(min(max(v.rounded(), 0), 255)) << shift
        }
        return channel(0) | channel(8) | channel(16) | (colour & 0xFF00_0000)
    }

    /// The links' adjacency in slots, both ways (the GPU layout's neighbours).
    static func slotAdjacency(_ t: GraphPerfOctree, a: [Int32], b: [Int32]) -> (start: [UInt32], items: [UInt32]) {
        let n = t.bodyCount
        let m = min(a.count, b.count)
        var start = [UInt32](repeating: 0, count: n + 1)
        var adj: [UInt32] = []
        t.slotOf.withUnsafeBufferPointer { slotOf in
            a.withUnsafeBufferPointer { pa in
                b.withUnsafeBufferPointer { pb in
                    start.withUnsafeMutableBufferPointer { st in
                        // counts at s + 1, then the running total
                        for k in 0..<m {
                            let x = Int(pa[k]), y = Int(pb[k])
                            guard x >= 0 && y >= 0 && x < n && y < n && x != y else { continue }
                            st[Int(slotOf[x]) + 1] += 1
                            st[Int(slotOf[y]) + 1] += 1
                        }
                        for s in 0..<n { st[s + 1] += st[s] }
                    }
                    adj = [UInt32](repeating: 0, count: Int(start[n]))
                    var fill = Array(start[0..<n])
                    fill.withUnsafeMutableBufferPointer { fp in
                        adj.withUnsafeMutableBufferPointer { out in
                            for k in 0..<m {
                                let x = Int(pa[k]), y = Int(pb[k])
                                guard x >= 0 && y >= 0 && x < n && y < n && x != y else { continue }
                                let sa = Int(slotOf[x]), sb = Int(slotOf[y])
                                out[Int(fp[sa])] = UInt32(sb)
                                fp[sa] += 1
                                out[Int(fp[sb])] = UInt32(sa)
                                fp[sb] += 1
                            }
                        }
                    }
                }
            }
        }
        return (start, adj)
    }

    /// Per leaf, its two most linked notes with at least `topDegree` links
    /// (slots, most linked first; -1 where there are fewer).
    static func tops(_ t: GraphPerfOctree, start: [UInt32], notes: Int) -> [Int32] {
        var out = [Int32](repeating: -1, count: 2 * t.leafCount)
        for leaf in 0..<t.leafCount {
            let cell = t.cells[Int(t.leafCell[leaf])]
            var best: (slot: Int32, degree: Int) = (-1, topDegree - 1)
            var second: (slot: Int32, degree: Int) = (-1, topDegree - 1)
            for s in Int(cell.first) ..< Int(cell.first + cell.count) where Int(t.order[s]) < notes {
                let d = Int(start[s + 1] - start[s])
                if d > best.degree {
                    second = best
                    best = (Int32(s), d)
                } else if d > second.degree {
                    second = (Int32(s), d)
                }
            }
            out[2 * leaf] = best.slot
            out[2 * leaf + 1] = second.slot
        }
        return out
    }

    /// Each cut cell's share of the light where bundles meet: 1/sqrt of how
    /// many bundles end there (one bundle alone keeps its full strength), so
    /// a crowded hub reads as structure and not as a solid fill. A bundle
    /// takes the smaller share of its two ends.
    static func overlapShares(ends: [UInt32], cells: Int) -> [Float] {
        var count = [Int](repeating: 0, count: max(cells, 0))
        for e in ends where Int(e) < count.count { count[Int(e)] += 1 }
        return count.map { 1 / Float(max($0, 1)).squareRoot() }
    }

    // MARK: - Bodies and slots

    /// Where body `i` is (its seed; the GPU layout moves it by under a third
    /// of a spacing).
    func position(_ body: Int) -> SIMD3<Float>? {
        guard body >= 0 && body < bodyCount else { return nil }
        return scene.layout.positions[body]
    }

    func title(_ body: Int) -> String { body >= 0 && body < bodyCount ? scene.title(body) : "" }

    func body(ofSlot s: Int) -> Int { s >= 0 && s < bodyCount ? Int(octree.order[s]) : -1 }

    func slot(ofBody b: Int) -> Int? { b >= 0 && b < bodyCount ? Int(octree.slotOf[b]) : nil }

    /// A slot's neighbours (slots).
    func neighbours(ofSlot s: Int) -> ArraySlice<UInt32> {
        guard s >= 0 && s + 1 < adjacencyStart.count else { return [] }
        return adjacency[Int(adjacencyStart[s]) ..< Int(adjacencyStart[s + 1])]
    }

    func degree(ofSlot s: Int) -> Int {
        guard s >= 0 && s + 1 < adjacencyStart.count else { return 0 }
        return Int(adjacencyStart[s + 1] - adjacencyStart[s])
    }

    /// A slot's radius (world), as the GPU draws it (the shader reads the
    /// top byte as unorm8, code / 255, and scales it by 2.55: code / 100).
    func radius(ofSlot s: Int) -> Float {
        guard s >= 0 && s < looks.count else { return 0 }
        return Float(looks[s] >> 24) / 100
    }

    /// The leaves a selection brings to full detail: the chosen note's own,
    /// then its neighbours' (each once, at most `cap`).
    func focusLeaves(ofSlot s: Int, cap: Int = 64) -> [Int] {
        guard s >= 0 && s < bodyCount else { return [] }
        var out = [octree.leaf(ofSlot: s)]
        var seen = Set(out)
        for n in neighbours(ofSlot: s) where out.count < cap {
            let leaf = octree.leaf(ofSlot: Int(n))
            if seen.insert(leaf).inserted { out.append(leaf) }
        }
        return out
    }

    /// A slot's position from 16-bit numbers across its leaf's box (the
    /// GPU's packed positions, laid out).
    static func unpack(_ packed: UnsafePointer<UInt16>, slot s: Int, boxes: [SIMD4<Float>]) -> SIMD3<Float> {
        let leaf = Int(packed[4 * s + 3])
        guard 2 * leaf + 1 < boxes.count else { return .zero }
        let lo = boxes[2 * leaf], extent = boxes[2 * leaf + 1]
        let q = SIMD3<Float>(Float(packed[4 * s]), Float(packed[4 * s + 1]), Float(packed[4 * s + 2])) / 65_535
        return SIMD3(lo.x, lo.y, lo.z) + q * SIMD3(extent.x, extent.y, extent.z)
    }

    /// A cell's ball: its centroid and the radius that holds it.
    func cellBall(_ c: Int) -> SIMD4<Float>? {
        guard c >= 0 && c < octree.cells.count else { return nil }
        let cell = octree.cells[c]
        let d = cell.hi - cell.lo
        return SIMD4(cell.centroid.x, cell.centroid.y, cell.centroid.z,
                     max((d * d).sum().squareRoot() * 0.5, spacing))
    }

    // MARK: - Picking

    /// What a finger picks: the drawn body (or summary point) nearest the
    /// touch within `reach` points, as the frame drew it - a body at its
    /// depth's size (GraphPerfDepthLook), the chosen note's neighbourhood at
    /// its focus size (GraphPerfFocusLook) - nearest the eye first. A faded
    /// body is picked like any other; one past the depth band's end, or too
    /// faded to see, is not (a tapped body must be visible). `at` gives a
    /// slot's laid-out position.
    func pick(x: Float, y: Float, reach: Float, frame: GraphPerfChunkFrame, camera: GraphPerfCamera,
              width: Float, height: Float, focus: Int? = nil,
              at: (Int) -> SIMD3<Float>) -> GraphPerfHit? {
        let eye = camera.eye, right = camera.right, up = camera.up, forward = camera.forward
        let focal = camera.focal(viewHeight: height)
        let fade = frame.fade
        var best: GraphPerfHit?
        var bestScore: Float = .infinity
        func project(_ p: SIMD3<Float>) -> (sx: Float, sy: Float, depth: Float)? {
            let v = p - eye
            let depth = (v * forward).sum()
            guard depth > 1e-3 else { return nil }
            if fade.w > 0 && GraphPerfDepthBand.fade(depth, depths: SIMD2(fade.x, fade.y), k: fade.z,
                                                      most: fade.w) >= Self.unseen { return nil }
            return (width / 2 + (v * right).sum() * focal / depth, height / 2 - (v * up).sum() * focal / depth, depth)
        }
        func consider(_ sx: Float, _ sy: Float, _ depth: Float, _ r: Float, _ hit: GraphPerfHit) {
            let d = ((sx - x) * (sx - x) + (sy - y) * (sy - y)).squareRoot()
            guard d <= r + reach else { return }
            // inside a disc beats near one; then the nearest to the eye
            let score = (d <= r ? 0 : d - r) * 1_000 + depth
            if score < bestScore {
                bestScore = score
                best = hit
            }
        }
        var k = 0
        while k + 1 < frame.drawLeaves.count {
            let leaf = Int(frame.drawLeaves[k])
            k += 2
            let cell = octree.cells[Int(octree.leafCell[leaf])]
            let stand = frame.standIn[leaf]
            let open = stand.w >= 2 ? stand.w - 2 : stand.w
            let q = leaf < frame.leafDetail.count ? frame.leafDetail[leaf] : 1
            let from = SIMD3(stand.x, stand.y, stand.z)
            for s in Int(cell.first) ..< Int(cell.first + cell.count) {
                let p = from + (at(s) - from) * open
                guard let v = project(p) else { continue }
                let r = GraphPerfDepthLook.pixels(radius: radius(ofSlot: s), focal: focal, depth: v.depth,
                                                  open: open, detail: q)
                consider(v.sx, v.sy, v.depth, r, .body(Int(octree.order[s])))
            }
        }
        if let chosen = focus, chosen >= 0 && chosen < bodyCount {
            var slots = [chosen]
            slots.append(contentsOf: neighbours(ofSlot: chosen).prefix(GraphPerfFocusLook.most).map { Int($0) })
            for s in slots {
                let v0 = at(s)
                let v = v0 - eye
                let depth = (v * forward).sum()
                guard depth > 1e-3 else { continue }
                let sx = width / 2 + (v * right).sum() * focal / depth
                let sy = height / 2 - (v * up).sum() * focal / depth
                let r = GraphPerfFocusLook.pixels(radius: radius(ofSlot: s), focal: focal, depth: depth)
                consider(sx, sy, depth, r, .body(Int(octree.order[s])))
            }
        }
        for (k, cell) in frame.summaryCells.enumerated() where 2 * k + 1 < frame.summaries.count {
            let at = frame.summaries[2 * k]
            let scale = frame.summaries[2 * k + 1].z
            guard let v = project(SIMD3(at.x, at.y, at.z)) else { continue }
            consider(v.sx, v.sy, v.depth, max(at.w * focal / v.depth, 6) * scale, .cluster(Int(cell)))
        }
        return best
    }

    /// A body this faded or more cannot be picked: it is all but gone.
    static let unseen: Float = 0.92
}

/// What a touch landed on.
nonisolated enum GraphPerfHit: Equatable, Sendable {
    /// A body drawn one by one (its index).
    case body(Int)
    /// A cluster drawn as one glow (its index; on the million map, an octree cell).
    case cluster(Int)
}
