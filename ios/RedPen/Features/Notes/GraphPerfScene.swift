// Everything the Performance map's renderer needs, built once off the main
// thread from a GraphPerfInput: the graph, its seed layout, its clusters,
// and the GPU's static arrays - a colour per body, both ends of every line
// (links, then the folder tree), each body's cluster, each cluster's ball
// and colour, and each bundle's two clusters and weight - so the renderer
// only copies them into buffers. Also the map's bounds for framing, and a
// body's id and title on demand.
//
// Bodies are the graph's: notes (slots 0..<noteCount, in UUID order), then
// one hub per folder. Foundation only, free of Stethoscore types.
import Foundation

nonisolated struct GraphPerfScene: Sendable {
    let graph: GraphPerfGraph
    let layout: GraphPerfLayout
    let clusters: GraphPerfClusters
    /// Per body: RGBA, 8 bits each, red lowest (Metal's unpack_unorm4x8).
    let colours: [UInt32]
    /// Per line: its two bodies (graph links, then folder tree lines).
    let lineEnds: [UInt32]
    /// Per body: its cluster (a hub's is its folder's).
    let clusterOfBody: [UInt32]
    /// Per cluster: centre x, y, z and ball radius; and its glow's colour.
    let clusterBalls: [Float]
    let clusterColours: [UInt32]
    /// Per bundle: its two clusters, and how many links it carries.
    let bundleEnds: [UInt32]
    let bundleWeights: [Float]
    /// A ball holding the whole map.
    let centre: SIMD3<Float>
    let radius: Float
    /// The input's titles (in input order), when it had them.
    private let noteTitles: [String]
    private let folderNames: [String]
    private let index: [UUID: Int32]

    var bodyCount: Int { graph.nodeCount }
    var lineCount: Int { lineEnds.count / 2 }

    /// The scene, or nil once `isCancelled` says a newer one is wanted.
    static func build(_ input: GraphPerfInput, isCancelled: () -> Bool = { false }) -> GraphPerfScene? {
        let g = GraphPerfGraph(input)
        if isCancelled() { return nil }
        guard let layout = GraphPerfLayout.seed(g, isCancelled: isCancelled) else { return nil }
        if isCancelled() { return nil }
        return GraphPerfScene(graph: g, layout: layout, input: input)
    }

    init(graph g: GraphPerfGraph, layout: GraphPerfLayout, input: GraphPerfInput) {
        graph = g
        self.layout = layout
        let c = GraphPerfClusters(graph: g, layout: layout)
        clusters = c
        noteTitles = input.noteTitles
        folderNames = input.folderNames

        // colours: the region's hue, lighter a level down, brighter with links
        var colour = [UInt32](repeating: 0, count: g.nodeCount)
        for i in 0..<g.noteCount {
            let f = Int(g.folder[i])
            var rgb = f >= 0 ? Self.palette[Int(g.folderRegion[f]) % Self.palette.count] : Self.loose
            if f >= 0 { rgb = Self.mix(rgb, Self.white, min(0.08 * Float(g.folderDepth[f]), 0.3)) }
            rgb *= g.isPage[i] ? 1 : 0.86
            rgb = Self.mix(rgb, Self.white, min(0.3, 0.06 * Float(log2(Double(1 + g.degree(i))))))
            colour[i] = Self.pack(rgb)
        }
        var clusterColour = [UInt32](repeating: Self.pack(Self.loose), count: g.systemCount)
        for f in 0..<g.folderCount {
            let base = Self.palette[Int(g.folderRegion[f]) % Self.palette.count]
            colour[g.noteCount + f] = Self.pack(Self.mix(base, Self.white, 0.45))
            clusterColour[f] = Self.pack(Self.mix(base, Self.white, 0.2))
        }
        colours = colour
        clusterColours = clusterColour

        // lines: links, then hub to parent hub
        var ends = [UInt32](repeating: 0, count: 2 * (g.linkCount + c.treeChild.count))
        for k in 0..<g.linkCount {
            ends[2 * k] = UInt32(g.edgeA[k])
            ends[2 * k + 1] = UInt32(g.edgeB[k])
        }
        for t in 0..<c.treeChild.count {
            ends[2 * (g.linkCount + t)] = UInt32(g.noteCount + Int(c.treeChild[t]))
            ends[2 * (g.linkCount + t) + 1] = UInt32(g.noteCount + Int(c.treeParent[t]))
        }
        lineEnds = ends

        var owner = [UInt32](repeating: 0, count: g.nodeCount)
        for i in 0..<g.noteCount { owner[i] = UInt32(g.systemOfNote[i]) }
        for f in 0..<g.folderCount { owner[g.noteCount + f] = UInt32(f) }
        clusterOfBody = owner

        var balls = [Float](repeating: 0, count: 4 * c.count)
        for s in 0..<c.count {
            balls[4 * s] = c.ball[s].x
            balls[4 * s + 1] = c.ball[s].y
            balls[4 * s + 2] = c.ball[s].z
            balls[4 * s + 3] = c.ball[s].w
        }
        clusterBalls = balls
        var bundleEnd = [UInt32](repeating: 0, count: 2 * c.bundleCount)
        var weight = [Float](repeating: 0, count: c.bundleCount)
        for b in 0..<c.bundleCount {
            bundleEnd[2 * b] = UInt32(c.bundleA[b])
            bundleEnd[2 * b + 1] = UInt32(c.bundleB[b])
            weight[b] = Float(c.bundleStart[b + 1] - c.bundleStart[b])
        }
        bundleEnds = bundleEnd
        bundleWeights = weight

        // bounds: round the top level's systems (each with all it holds)
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        var tops: [Int] = (0..<g.folderCount).filter { g.folderParent[$0] < 0 }
        tops += Array(g.folderCount..<g.systemCount)
        for s in tops {
            let r = SIMD3<Float>(repeating: layout.systemRadius[s])
            lo = pointwiseMin(lo, layout.systemCentre[s] - r)
            hi = pointwiseMax(hi, layout.systemCentre[s] + r)
        }
        if tops.isEmpty {
            centre = .zero
            radius = 1
        } else {
            let mid = (lo + hi) / 2
            var reach: Float = 0
            for s in tops {
                let d = layout.systemCentre[s] - mid
                reach = max(reach, (d * d).sum().squareRoot() + layout.systemRadius[s])
            }
            centre = mid
            radius = max(reach, 1)
        }

        var ids: [UUID: Int32] = [:]
        ids.reserveCapacity(g.nodeCount)
        for i in 0..<g.noteCount { ids[g.noteIDs[i]] = Int32(i) }
        for f in 0..<g.folderCount { ids[g.folderIDs[f]] = Int32(g.noteCount + f) }
        index = ids
    }

    // MARK: - Bodies

    /// The note's or folder's id.
    func id(_ body: Int) -> UUID? {
        if body >= 0 && body < graph.noteCount { return graph.noteIDs[body] }
        let f = body - graph.noteCount
        return f >= 0 && f < graph.folderCount ? graph.folderIDs[f] : nil
    }

    /// The body standing for a note or folder id.
    func body(_ id: UUID) -> Int? { index[id].map { Int($0) } }

    func isNote(_ body: Int) -> Bool { body < graph.noteCount }

    func position(_ body: Int) -> SIMD3<Float> { layout.positions[body] }

    /// What its name pill says: the input's title, or one made on demand.
    func title(_ body: Int) -> String {
        if body < graph.noteCount {
            let k = Int(graph.inputOfNote[body])
            if k < noteTitles.count { return noteTitles[k].isEmpty ? "Untitled" : noteTitles[k] }
            return GraphPerfSynthetic.title(k)
        }
        let f = body - graph.noteCount
        guard f >= 0 && f < graph.folderCount else { return "" }
        let k = Int(graph.inputOfFolder[f])
        if k < folderNames.count { return folderNames[k].isEmpty ? "Folder" : folderNames[k] }
        return "Folder " + String(k + 1)
    }

    /// A cluster's name: its folder's, or for a loose group its first note's.
    func clusterTitle(_ s: Int) -> String {
        if s < graph.folderCount { return title(graph.noteCount + s) }
        let lo = Int(clusters.memberStart[s])
        return lo < Int(clusters.memberStart[s + 1]) ? title(Int(clusters.members[lo])) : ""
    }

    // MARK: - Colour

    /// Twelve hues that read on the near-black sky, one per top folder in turn.
    static let palette: [SIMD3<Float>] = [
        SIMD3(0.36, 0.61, 1.00), SIMD3(1.00, 0.37, 0.49), SIMD3(1.00, 0.71, 0.26), SIMD3(0.25, 0.85, 0.60),
        SIMD3(0.73, 0.55, 1.00), SIMD3(0.27, 0.84, 0.92), SIMD3(1.00, 0.53, 0.26), SIMD3(0.90, 0.42, 1.00),
        SIMD3(0.66, 0.88, 0.35), SIMD3(1.00, 0.85, 0.35), SIMD3(0.50, 0.65, 1.00), SIMD3(1.00, 0.56, 0.72)
    ]
    static let loose = SIMD3<Float>(0.79, 0.82, 0.88)
    static let white = SIMD3<Float>(1, 1, 1)
    /// The sky behind it all (sRGB).
    static let background = SIMD3<Float>(0.02, 0.027, 0.047)

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    /// RGBA8 with red in the low byte, opaque.
    static func pack(_ rgb: SIMD3<Float>) -> UInt32 {
        func byte(_ v: Float) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
        return byte(rgb.x) | byte(rgb.y) << 8 | byte(rgb.z) << 16 | 255 << 24
    }

    static func unpack(_ c: UInt32) -> SIMD4<Float> {
        SIMD4(Float(c & 0xFF), Float(c >> 8 & 0xFF), Float(c >> 16 & 0xFF), Float(c >> 24 & 0xFF)) / 255
    }
}
