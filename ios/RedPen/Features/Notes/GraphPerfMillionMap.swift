// The million map's data, built once off the main thread from a
// GraphPerfScene (the same graph, seed layout and colours as the 100,000
// map): the octree of chunks, every link listed per leaf, the far bundles,
// and the arrays the GPU keeps for the whole session - a million bodies in
// about 20 MB (16-bit positions with their leaf, 8 bytes, and the same again
// as the layout's seed; colour and size, 4), the links' adjacency for the
// GPU layout (about 19 MB at 2.4 links a note), and each leaf's box.
//
// Bodies keep the scene's numbers outside (a pick, a title, the name pill);
// inside, the GPU works in slots (the octree's sorted order).
//
// Foundation only, free of Stethoscore types.
import Foundation

nonisolated struct GraphPerfMillionMap: Sendable {
    let scene: GraphPerfScene
    let octree: GraphPerfOctree
    let links: GraphPerfLeafLinks
    let bundles: GraphPerfBundles
    /// Per slot: x, y, z (16-bit across its leaf's box) and its leaf.
    let packed: [UInt16]
    /// Per slot: RGB and, in the top byte, its radius in hundredths.
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

    var bodyCount: Int { octree.bodyCount }
    var linkCount: Int { scene.graph.linkCount }
    var centre: SIMD3<Float> { scene.centre }
    var radius: Float { scene.radius }
    var spacing: Float { scene.layout.spacing }

    /// The map for `scene`, or nil once `isCancelled` says a newer one is wanted.
    static func build(_ scene: GraphPerfScene, leafSize: Int = 384,
                      isCancelled: () -> Bool = { false }) -> GraphPerfMillionMap? {
        let positions = scene.layout.positions
        let t = GraphPerfOctree(positions: positions, colours: scene.colours, leafSize: leafSize)
        if isCancelled() { return nil }
        let lines = scene.lineCount
        var a = [Int32](repeating: 0, count: lines), b = [Int32](repeating: 0, count: lines)
        for k in 0..<lines {
            a[k] = Int32(scene.lineEnds[2 * k])
            b[k] = Int32(scene.lineEnds[2 * k + 1])
        }
        let leafLinks = GraphPerfLeafLinks(octree: t, a: a, b: b)
        if isCancelled() { return nil }
        let bundles = GraphPerfBundles(octree: t, a: a, b: b)
        if isCancelled() { return nil }
        return GraphPerfMillionMap(scene: scene, octree: t, links: leafLinks, bundles: bundles, a: a, b: b)
    }

    private init(scene: GraphPerfScene, octree t: GraphPerfOctree, links: GraphPerfLeafLinks,
                 bundles: GraphPerfBundles, a: [Int32], b: [Int32]) {
        self.scene = scene
        octree = t
        self.links = links
        self.bundles = bundles
        let n = t.bodyCount
        packed = t.packedPositions(scene.layout.positions)
        var look = [UInt32](repeating: 0, count: n)
        for s in 0..<n {
            let body = Int(t.order[s])
            let r = scene.layout.radius[body]
            let code = UInt32(min(max((r * 100).rounded(), 1), 255))
            look[s] = scene.colours[body] & 0x00FF_FFFF | code << 24
        }
        looks = look
        // adjacency in slots, both ways
        var degree = [UInt32](repeating: 0, count: n + 1)
        let m = min(a.count, b.count)
        func ok(_ k: Int) -> Bool { a[k] >= 0 && b[k] >= 0 && Int(a[k]) < n && Int(b[k]) < n && a[k] != b[k] }
        for k in 0..<m where ok(k) {
            degree[Int(t.slotOf[Int(a[k])])] += 1
            degree[Int(t.slotOf[Int(b[k])])] += 1
        }
        var start = [UInt32](repeating: 0, count: n + 1)
        for s in 0..<n { start[s + 1] = start[s] + degree[s] }
        var fill = Array(start[0..<n])
        var adj = [UInt32](repeating: 0, count: Int(start[n]))
        for k in 0..<m where ok(k) {
            let sa = Int(t.slotOf[Int(a[k])]), sb = Int(t.slotOf[Int(b[k])])
            adj[Int(fill[sa])] = UInt32(sb); fill[sa] += 1
            adj[Int(fill[sb])] = UInt32(sa); fill[sb] += 1
        }
        adjacencyStart = start
        adjacency = adj
        leafBoxes = t.leafBoxes()
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

    /// Where body `i` is (its seed; the GPU layout moves it by under a third
    /// of a spacing).
    func position(_ body: Int) -> SIMD3<Float>? {
        guard body >= 0 && body < bodyCount else { return nil }
        return scene.layout.positions[body]
    }

    func title(_ body: Int) -> String { body >= 0 && body < bodyCount ? scene.title(body) : "" }

    /// A cell's ball: its centroid and the radius that holds it.
    func cellBall(_ c: Int) -> SIMD4<Float>? {
        guard c >= 0 && c < octree.cells.count else { return nil }
        let cell = octree.cells[c]
        let d = cell.hi - cell.lo
        return SIMD4(cell.centroid.x, cell.centroid.y, cell.centroid.z,
                     max((d * d).sum().squareRoot() * 0.5, spacing))
    }

    /// What a finger picks: the drawn body (or summary point) nearest the
    /// touch within `reach` points, from the frame as planned.
    func pick(x: Float, y: Float, reach: Float, frame: GraphPerfChunkFrame, camera: GraphPerfCamera,
              width: Float, height: Float) -> GraphPerfHit? {
        let eye = camera.eye, right = camera.right, up = camera.up, forward = camera.forward
        let focal = camera.focal(viewHeight: height)
        var best: GraphPerfHit?
        var bestScore: Float = .infinity
        func consider(_ p: SIMD3<Float>, _ radius: Float, _ hit: GraphPerfHit, floor: Float) {
            let v = p - eye
            let depth = (v * forward).sum()
            guard depth > 1e-3 else { return }
            let sx = width / 2 + (v * right).sum() * focal / depth
            let sy = height / 2 - (v * up).sum() * focal / depth
            let r = max(radius * focal / depth, floor)
            let d = ((sx - x) * (sx - x) + (sy - y) * (sy - y)).squareRoot()
            guard d <= r + reach else { return }
            // inside a disc beats near one; then the nearest to the eye
            let score = (d <= r ? 0 : d - r) * 1_000 + depth
            if score < bestScore { bestScore = score; best = hit }
        }
        var k = 0
        while k + 1 < frame.drawLeaves.count {
            let leaf = Int(frame.drawLeaves[k])
            k += 2
            let cell = octree.cells[Int(octree.leafCell[leaf])]
            let stand = frame.standIn[leaf]
            let open = stand.w >= 2 ? stand.w - 2 : stand.w
            let from = SIMD3(stand.x, stand.y, stand.z)
            for s in Int(cell.first) ..< Int(cell.first + cell.count) {
                let body = Int(octree.order[s])
                let p = from + (scene.layout.positions[body] - from) * open
                consider(p, scene.layout.radius[body] * open, .body(body), floor: 1.25)
            }
        }
        for (k, cell) in frame.summaryCells.enumerated() where 2 * k + 1 < frame.summaries.count {
            let at = frame.summaries[2 * k]
            let scale = frame.summaries[2 * k + 1].z
            consider(SIMD3(at.x, at.y, at.z), at.w * scale, .cluster(Int(cell)), floor: 6 * scale)
        }
        return best
    }
}

/// What a touch landed on.
nonisolated enum GraphPerfHit: Equatable, Sendable {
    /// A body drawn one by one (its index).
    case body(Int)
    /// A cluster drawn as one glow (its index; on the million map, an octree cell).
    case cluster(Int)
}
