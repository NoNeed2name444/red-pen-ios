// Level of detail by cluster on the Performance map. Every system (a
// folder's own notes round its hub, or a loose group) is a cluster with a
// ball that holds it. Each time the camera moves, the planner decides per
// cluster:
//
//   culled      outside the view: none of it is drawn
//   collapsed   its ball smaller on screen than `collapseBelow` points: one
//               glow (an impostor) stands for the hub and every note, and a
//               link into it ends at its centre
//   notes       its notes drawn one by one, its own links not (its ball is
//               under `linksBelow` points: every link would be under the
//               shader's two-point fade anyway)
//   full        its notes and its own links
//
// Links between two clusters are kept by cluster pair (a bundle): drawn one
// by one while either end is drawn in detail, else as one line between the
// two centres. So as the camera moves away the bodies and lines drawn only
// shrink, and past the budgets (the most bodies and lines a tier draws one
// by one) the clusters smallest on screen give way first.
//
// The planner writes the renderer's draw lists (body, glow, link and
// bundle indices, and a collapsed flag per cluster) and says whether they
// changed, so the GPU copies are made only then. Foundation only, free of
// Stethoscore types.
import Foundation

nonisolated struct GraphPerfClusters: Sendable {
    let count: Int
    let noteCount: Int
    let linkCount: Int
    /// The graph's link ends (body indices), for the filter.
    let linkA: [Int32]
    let linkB: [Int32]
    /// Per cluster: centre x, y, z and the radius of the ball holding its
    /// hub and its own notes.
    let ball: [SIMD4<Float>]
    /// The hub's body index (noteCount + folder), or -1 for a loose group.
    let hub: [Int32]
    /// Members: members[memberStart[s] ..< memberStart[s + 1]], in slot order.
    let memberStart: [Int32]
    let members: [Int32]
    /// Links inside cluster s: internalLinks[internalStart[s] ..< internalStart[s + 1]].
    let internalStart: [Int32]
    let internalLinks: [Int32]
    /// Bundles: the cluster pair (a < b) and their links, by pair.
    let bundleA: [Int32]
    let bundleB: [Int32]
    let bundleStart: [Int32]
    let bundleLinks: [Int32]
    /// Folder tree lines (a folder's hub to its parent's): line k is link
    /// index linkCount + k, between these two clusters.
    let treeChild: [Int32]
    let treeParent: [Int32]

    var bundleCount: Int { bundleA.count }

    init(graph g: GraphPerfGraph, layout: GraphPerfLayout) {
        count = g.systemCount
        noteCount = g.noteCount
        linkCount = g.linkCount
        linkA = g.edgeA
        linkB = g.edgeB
        var balls = [SIMD4<Float>](repeating: .zero, count: g.systemCount)
        for s in 0..<g.systemCount {
            let c = layout.systemCentre[s]
            balls[s] = SIMD4(c.x, c.y, c.z, layout.coreRadius[s])
        }
        ball = balls
        hub = (0..<g.systemCount).map { $0 < g.folderCount ? Int32(g.noteCount + $0) : -1 }
        memberStart = g.systemNoteStart
        members = g.systemNotes

        // inside one cluster: bucketed by cluster; between two: by pair
        var inside = [Int32](repeating: -1, count: g.linkCount)
        var cross: [(pair: UInt64, link: Int32)] = []
        for k in 0..<g.linkCount {
            let sa = g.systemOfNote[Int(g.edgeA[k])], sb = g.systemOfNote[Int(g.edgeB[k])]
            if sa == sb {
                inside[k] = sa
            } else {
                cross.append((UInt64(min(sa, sb)) << 32 | UInt64(max(sa, sb)), Int32(k)))
            }
        }
        let buckets = GraphPerfGraph.buckets(count: g.systemCount, keys: inside)
        internalStart = buckets.start
        internalLinks = buckets.items
        let sorted = Self.byPair(cross, clusters: g.systemCount, links: g.linkCount)
        var a: [Int32] = [], b: [Int32] = [], start: [Int32] = [], links: [Int32] = []
        links.reserveCapacity(sorted.count)
        var last = UInt64.max
        for item in sorted {
            if item.pair != last {
                last = item.pair
                a.append(Int32(truncatingIfNeeded: item.pair >> 32))
                b.append(Int32(truncatingIfNeeded: item.pair & 0xFFFF_FFFF))
                start.append(Int32(links.count))
            }
            links.append(item.link)
        }
        start.append(Int32(links.count))
        bundleA = a
        bundleB = b
        bundleStart = start
        bundleLinks = links

        var child: [Int32] = [], parent: [Int32] = []
        for f in 0..<g.folderCount where g.folderParent[f] >= 0 {
            child.append(Int32(f))
            parent.append(g.folderParent[f])
        }
        treeChild = child
        treeParent = parent
    }

    /// Cross links sorted by pair, then link: one radix sort of packed keys
    /// (21 bits a cluster, 22 a link) while they fit, a comparison sort past that.
    private static func byPair(_ items: [(pair: UInt64, link: Int32)], clusters: Int,
                               links: Int) -> [(pair: UInt64, link: Int32)] {
        guard clusters < 1 << 21, links < 1 << 22 else {
            return items.sorted { $0.pair != $1.pair ? $0.pair < $1.pair : $0.link < $1.link }
        }
        var keys = items.map { item -> UInt64 in
            let lo = item.pair >> 32, hi = item.pair & 0xFFFF_FFFF
            return (lo << 21 | hi) << 22 | UInt64(item.link)
        }
        GraphPerfGraph.radixSort(&keys, maxKey: UInt64(max(clusters, 1)) << 43)
        return keys.map { key in
            let pair = key >> 22
            return ((pair >> 21) << 32 | (pair & 0x1F_FFFF), Int32(truncatingIfNeeded: key & 0x3F_FFFF))
        }
    }

    func memberCount(_ s: Int) -> Int { Int(memberStart[s + 1] - memberStart[s]) }
    func internalCount(_ s: Int) -> Int { Int(internalStart[s + 1] - internalStart[s]) }
}

/// How much one frame may draw in detail.
nonisolated struct GraphPerfLODSettings: Sendable, Equatable {
    /// A cluster whose ball is drawn smaller than this radius (points)
    /// collapses to one glow...
    var collapseBelow: Float
    /// ...and under this one draws its notes but not its own links.
    var linksBelow: Float
    /// The most bodies, and links, drawn one by one.
    var nodeBudget: Int
    var linkBudget: Int

    static func of(_ tier: GraphPerfTier) -> GraphPerfLODSettings {
        switch tier {
        case .high:
            return GraphPerfLODSettings(collapseBelow: 0.75, linksBelow: 1, nodeBudget: 400_000, linkBudget: 1_000_000)
        case .smooth:
            return GraphPerfLODSettings(collapseBelow: 1.5, linksBelow: 3, nodeBudget: 160_000, linkBudget: 400_000)
        case .saver:
            return GraphPerfLODSettings(collapseBelow: 3, linksBelow: 6, nodeBudget: 60_000, linkBudget: 120_000)
        }
    }
}

/// A camera on a screen of `width` x `height` points, with its depth range.
nonisolated struct GraphPerfViewpoint: Sendable, Equatable {
    var camera: GraphPerfCamera
    var width: Float
    var height: Float
    var near: Float
    var far: Float
}

/// What one frame draws: indices into the scene's buffers.
nonisolated struct GraphPerfDrawLists: Sendable {
    /// Bodies drawn one by one (notes, then hubs, by index).
    var nodes: [UInt32] = []
    /// Clusters drawn as one glow.
    var glows: [UInt32] = []
    /// Links drawn one by one (graph links, then folder tree lines).
    var links: [UInt32] = []
    /// Bundles drawn as one line between cluster centres.
    var bundles: [UInt32] = []
    /// Per cluster: 1 while it is collapsed (a link into it ends at its centre).
    var collapsed: [UInt32] = []

    var lineCount: Int { links.count + bundles.count }
}

nonisolated struct GraphPerfLODPlanner: Sendable {
    enum State: UInt8, Sendable {
        case culled = 0
        case collapsed = 1
        case notes = 2
        case full = 3
    }

    private(set) var states: [State] = []
    private(set) var lists = GraphPerfDrawLists()
    /// Bumped whenever the lists change.
    private(set) var version: Int = 0
    /// Each cluster's ball radius on screen at the last plan (points; 0 culled).
    private(set) var screenRadius: [Float] = []
    private var scratch: [State] = []
    private var order: [Int32] = []
    private var lastMaskVersion: Int = -1

    init() {}

    /// Decides every cluster's detail for this viewpoint and, when anything
    /// changed, writes the lists again. `mask` (per body, nil for all) is
    /// the filter: bump `maskVersion` whenever it changes. Returns whether
    /// the lists changed.
    @discardableResult
    mutating func plan(_ c: GraphPerfClusters, view: GraphPerfViewpoint, settings: GraphPerfLODSettings,
                       mask: [Bool]? = nil, maskVersion: Int = 0) -> Bool {
        let n = c.count
        if scratch.count != n {
            scratch = [State](repeating: .culled, count: n)
            screenRadius = [Float](repeating: 0, count: n)
        }
        let cam = view.camera
        let frustum = cam.frustum(width: view.width, height: view.height, near: view.near, far: view.far)
        let focal = cam.focal(viewHeight: view.height)
        let eye = cam.eye, forward = cam.forward

        // each cluster on its own
        var nodesWanted = 0, linksWanted = 0
        for s in 0..<n {
            let b = c.ball[s]
            let centre = SIMD3(b.x, b.y, b.z)
            guard frustum.touches(centre: centre, radius: b.w) else {
                scratch[s] = .culled
                screenRadius[s] = 0
                continue
            }
            let depth = ((centre - eye) * forward).sum()
            // the eye inside or at the ball: as near as can be
            let rho: Float = depth > b.w ? b.w * focal / depth : .infinity
            screenRadius[s] = rho
            if rho < settings.collapseBelow {
                scratch[s] = .collapsed
            } else {
                scratch[s] = rho < settings.linksBelow ? .notes : .full
                nodesWanted += c.memberCount(s) + 1
                if scratch[s] == .full { linksWanted += c.internalCount(s) }
            }
        }
        // over a budget: the clusters smallest on screen give way first
        if nodesWanted > settings.nodeBudget || linksWanted > settings.linkBudget {
            order.removeAll(keepingCapacity: true)
            for s in 0..<n where scratch[s].rawValue >= State.notes.rawValue { order.append(Int32(s)) }
            let radius = screenRadius
            order.sort { radius[Int($0)] != radius[Int($1)] ? radius[Int($0)] < radius[Int($1)] : $0 < $1 }
            var k = 0
            while linksWanted > settings.linkBudget && k < order.count {
                let s = Int(order[k])
                if scratch[s] == .full {
                    scratch[s] = .notes
                    linksWanted -= c.internalCount(s)
                }
                k += 1
            }
            k = 0
            while nodesWanted > settings.nodeBudget && k < order.count {
                let s = Int(order[k])
                scratch[s] = .collapsed
                nodesWanted -= c.memberCount(s) + 1
                k += 1
            }
        }

        if scratch == states && maskVersion == lastMaskVersion && lists.collapsed.count == n { return false }
        states = scratch
        lastMaskVersion = maskVersion
        write(c, mask: mask)
        version += 1
        return true
    }

    private mutating func write(_ c: GraphPerfClusters, mask: [Bool]?) {
        let n = c.count
        var out = GraphPerfDrawLists()
        swap(&out, &lists)
        out.nodes.removeAll(keepingCapacity: true)
        out.glows.removeAll(keepingCapacity: true)
        out.links.removeAll(keepingCapacity: true)
        out.bundles.removeAll(keepingCapacity: true)
        if out.collapsed.count != n { out.collapsed = [UInt32](repeating: 0, count: n) }
        let shown: (Int) -> Bool = { i in
            guard let m = mask else { return true }
            return i < m.count && m[i]
        }
        let linkShown: (Int) -> Bool = { k in
            mask == nil || (shown(Int(c.linkA[k])) && shown(Int(c.linkB[k])))
        }
        for s in 0..<n {
            let state = states[s]
            out.collapsed[s] = state == .collapsed ? 1 : 0
            let lo = Int(c.memberStart[s]), hi = Int(c.memberStart[s + 1])
            switch state {
            case .culled:
                continue
            case .collapsed:
                var any = c.hub[s] >= 0 && shown(Int(c.hub[s]))
                var k = lo
                while !any && k < hi {
                    any = shown(Int(c.members[k]))
                    k += 1
                }
                if any { out.glows.append(UInt32(s)) }
            case .notes, .full:
                if c.hub[s] >= 0 && shown(Int(c.hub[s])) { out.nodes.append(UInt32(c.hub[s])) }
                for k in lo..<hi where shown(Int(c.members[k])) { out.nodes.append(UInt32(c.members[k])) }
            }
        }
        // links inside clusters drawn in full
        for s in 0..<n where states[s] == .full {
            for k in Int(c.internalStart[s])..<Int(c.internalStart[s + 1]) {
                let link = Int(c.internalLinks[k])
                if linkShown(link) { out.links.append(UInt32(link)) }
            }
        }
        // between clusters: one by one while either end is in detail, else one line
        for b in 0..<c.bundleCount {
            let sa = states[Int(c.bundleA[b])], sb = states[Int(c.bundleB[b])]
            if sa == .culled && sb == .culled { continue }
            let range = Int(c.bundleStart[b])..<Int(c.bundleStart[b + 1])
            if sa.rawValue >= State.notes.rawValue || sb.rawValue >= State.notes.rawValue {
                for k in range where linkShown(Int(c.bundleLinks[k])) { out.links.append(UInt32(c.bundleLinks[k])) }
            } else if range.contains(where: { linkShown(Int(c.bundleLinks[$0])) }) {
                out.bundles.append(UInt32(b))
            }
        }
        // the folder tree, wherever either end is in view
        for t in 0..<c.treeChild.count {
            let child = Int(c.treeChild[t]), parent = Int(c.treeParent[t])
            if states[child] == .culled && states[parent] == .culled { continue }
            if !(shown(c.noteCount + child) && shown(c.noteCount + parent)) { continue }
            out.links.append(UInt32(c.linkCount + t))
        }
        lists = out
    }
}
