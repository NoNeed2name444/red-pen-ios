// The million map's level of detail and streaming (plan 4e), worked out
// on the CPU each frame from the octree's few thousand cells, never from
// the million bodies:
//
// - Level of detail by size on screen: a cell opens once its ball covers
//   `split` points (radius), fully by `split` x `span`. Opening is a morph,
//   never a fade: the cell's summary point shrinks while its children (or,
//   in a leaf, its bodies) move out from where it was drawn and grow to
//   their own size. A link inside a closed leaf ends at the leaf's summary
//   point, so links grow out with their bodies too.
// - Culling: a cell outside the view (GraphPerfFrustum) is neither drawn
//   nor opened. The guard band (GraphPerfGuardBand) is a wider frustum,
//   widest on the side the camera is moving towards: a leaf in it about to
//   open is prepared (laid out, its links streamed) before it is on screen.
// - Streaming: the leaves wanted this frame, nearest first, are prepared
//   within a per-frame budget (GraphPerfStreamer); a leaf not prepared yet
//   keeps showing its summary, then morphs open over a quarter second once
//   it is ready. Recently used leaves stay prepared (GraphPerfChunkCache, the
//   least recently used goes first), so turning back is instant.
// - Bundles: the links between two cells of the bundle cut are one bundle,
//   as wide as the share of both ends still closed: the links take over as
//   either end opens.
//
// Foundation only: tested on Linux (Tests/GraphPerfChunkTests.swift).
import Foundation

/// What a frame needs from the camera.
nonisolated struct GraphPerfChunkView: Sendable {
    var eye: SIMD3<Float>
    /// Points per world unit at depth 1.
    var focal: Float
    var frustum: GraphPerfFrustum
    /// The view widened by the guard band.
    var guardFrustum: GraphPerfFrustum

    init(camera: GraphPerfCamera, width: Float, height: Float, near: Float, far: Float,
         guardBand: GraphPerfGuardBand = GraphPerfGuardBand(), motion: SIMD2<Float> = .zero) {
        eye = camera.eye
        focal = camera.focal(viewHeight: height)
        frustum = camera.frustum(width: width, height: height, near: near, far: far)
        guardFrustum = guardBand.frustum(camera, width: width, height: height, near: near, far: far, motion: motion)
    }
}

/// Chunks just outside the screen are prepared too: every side widened by
/// `base` (as a share of the view's half width), and the side the view is
/// turning or sliding towards by `lead` seconds of that motion more.
nonisolated struct GraphPerfGuardBand: Sendable, Equatable {
    var base: Float = 0.2
    var lead: Float = 0.6
    var widest: Float = 1.5

    /// How far each side reaches past the screen, in shares of the view's
    /// half width (right, left, up, down), for a view moving `motion`
    /// (half widths a second; +x: the view moves right, so new things come
    /// in from the right).
    func margins(motion: SIMD2<Float>) -> SIMD4<Float> {
        let m = SIMD4<Float>(max(motion.x, 0), max(-motion.x, 0), max(motion.y, 0), max(-motion.y, 0))
        let out = SIMD4<Float>(repeating: base) + m * lead
        return pointwiseMin(out, SIMD4(repeating: widest))
    }

    /// The camera's view widened by the margins.
    func frustum(_ cam: GraphPerfCamera, width: Float, height: Float, near: Float, far: Float,
                 motion: SIMD2<Float>) -> GraphPerfFrustum {
        let m = margins(motion: motion)
        let f = cam.forward, r = cam.right, u = cam.up, e = cam.eye
        let ty = tan(cam.fovY / 2)
        let tx = ty * width / max(height, 1e-6)
        func side(_ axis: SIMD3<Float>, _ t: Float) -> GraphPerfPlane {
            let half = atan(t)
            let n = axis * cos(half) - f * sin(half)
            return GraphPerfPlane(normal: n, d: (n * e).sum())
        }
        let nearPlane = GraphPerfPlane(normal: -f, d: (-f * e).sum() - near)
        let farPlane = GraphPerfPlane(normal: f, d: (f * e).sum() + far)
        return GraphPerfFrustum(planes: [nearPlane, farPlane, side(r, tx * (1 + m.x)), side(-r, tx * (1 + m.y)),
                                         side(u, ty * (1 + m.z)), side(-u, ty * (1 + m.w))])
    }

    /// How fast the view moves between two camera poses `seconds` apart, in
    /// half view widths a second: its turn, and its slide at the target's depth.
    static func motion(from a: GraphPerfCamera, to b: GraphPerfCamera, seconds: Float, aspect: Float) -> SIMD2<Float> {
        guard seconds > 1e-4 else { return .zero }
        let tx = max(tan(b.fovY / 2) * aspect, 1e-4), ty = max(tan(b.fovY / 2), 1e-4)
        let turn = b.forward - a.forward
        let slide = (b.target - a.target) / max(b.distance, 1e-4)
        let x = ((turn + slide) * b.right).sum() / tx
        let y = ((turn + slide) * b.up).sum() / ty
        let v = SIMD2<Float>(x, y) / seconds
        return SIMD2(v.x.isFinite ? v.x : 0, v.y.isFinite ? v.y : 0)
    }
}

/// How soon cells open: the frame budget (GraphPerfFrameBudget) sets `split`.
nonisolated struct GraphPerfChunkSettings: Sendable, Equatable {
    /// A cell starts to open once its ball's radius on screen is this many points.
    var split: Float = 28
    /// It is fully open at split x span.
    var span: Float = 2
    /// A leaf is wanted (prepared) from this share of `split`.
    var want: Float = 0.55
    /// The smallest a summary point is drawn (points, radius).
    var summaryFloor: Float = 1.6
}

/// What one frame draws, in the arrays the GPU reads.
nonisolated struct GraphPerfChunkFrame: Sendable {
    /// Per leaf: where its bodies come from (x, y, z: its summary point as
    /// drawn) and how far it is open (w: 0 closed ... 1 open; 2 more when
    /// it is drawn body by body this frame).
    var standIn: [SIMD4<Float>] = []
    /// The leaves drawn body by body: leaf, then the first instance it
    /// starts at (pairs).
    var drawLeaves: [UInt32] = []
    var drawnBodies: Int = 0
    /// Summary points, two float4s each: x, y, z and radius (world); then
    /// the colour (RGBA8's bits), brightness (how many it stands for, never
    /// changed by a morph) and scale (0...1: how far it has grown out of its
    /// parent or shrunk into its children - radius and its floor both
    /// follow it, so a point never pops).
    var summaries: [SIMD4<Float>] = []
    /// The cell each summary point stands for.
    var summaryCells: [Int32] = []
    /// Per bundle cut cell: where it is drawn, and its share still closed.
    var bundleCells: [SIMD4<Float>] = []
    /// Leaves to prepare (in or near the view, about to open), with how
    /// soon (smaller first).
    var wanted: [(leaf: Int32, priority: Float)] = []
    var visibleLeaves: Int = 0
    var openLeaves: Int = 0

    var summaryCount: Int { summaries.count / 2 }
}

/// Plans each frame: which cells are culled, closed (a summary point) or
/// open, how far each is morphed, and which leaves to prepare.
nonisolated struct GraphPerfChunkPlanner: Sendable {
    let octree: GraphPerfOctree
    let bundles: GraphPerfBundles
    /// Per leaf, 0...1: how far it may open (0 until prepared, then rising
    /// to 1 over `readySeconds`, so a ready leaf morphs open, never pops).
    private(set) var ready: [Float]
    static let readySeconds: Float = 0.25
    private(set) var frame = GraphPerfChunkFrame()
    private var expandedMass: [Float]

    init(octree: GraphPerfOctree, bundles: GraphPerfBundles) {
        self.octree = octree
        self.bundles = bundles
        ready = [Float](repeating: 0, count: octree.leafCount)
        expandedMass = [Float](repeating: 0, count: bundles.cells.count)
        frame.standIn = [SIMD4<Float>](repeating: .zero, count: octree.leafCount)
        frame.bundleCells = [SIMD4<Float>](repeating: .zero, count: bundles.cells.count)
    }

    /// A leaf was prepared (true) or let go (false).
    mutating func setPrepared(_ leaf: Int, _ prepared: Bool) {
        guard leaf >= 0 && leaf < ready.count else { return }
        if !prepared { ready[leaf] = 0 } else if ready[leaf] == 0 { ready[leaf] = 1e-4 }
    }

    /// Prepared leaves rise towards fully ready.
    mutating func advance(seconds: Float) {
        let step = max(seconds, 0) / Self.readySeconds
        for l in 0..<ready.count where ready[l] > 0 && ready[l] < 1 { ready[l] = min(ready[l] + step, 1) }
    }

    /// Makes every prepared leaf fully ready at once (tests; Reduce Motion).
    mutating func settleReady() {
        for l in 0..<ready.count where ready[l] > 0 { ready[l] = 1 }
    }

    /// The frame for this view.
    @discardableResult
    mutating func plan(_ view: GraphPerfChunkView, settings: GraphPerfChunkSettings) -> GraphPerfChunkFrame {
        frame.drawLeaves.removeAll(keepingCapacity: true)
        frame.summaries.removeAll(keepingCapacity: true)
        frame.summaryCells.removeAll(keepingCapacity: true)
        frame.wanted.removeAll(keepingCapacity: true)
        frame.drawnBodies = 0
        frame.visibleLeaves = 0
        frame.openLeaves = 0
        for k in 0..<expandedMass.count { expandedMass[k] = 0 }
        guard !octree.cells.isEmpty, octree.bodyCount > 0 else { return frame }
        visit(0, at: octree.root.centroid, grow: 1, view, settings)
        for k in 0..<bundles.cells.count {
            let cell = octree.cells[Int(bundles.cells[k])]
            let closed = 1 - min(expandedMass[k] / Float(max(cell.count, 1)), 1)
            frame.bundleCells[k].w = closed
        }
        return frame
    }

    /// The radius a summary point is drawn at (world): its bodies' spread,
    /// at least a body's own size.
    static func summaryRadius(_ cell: GraphPerfOctree.Cell) -> Float {
        max(cell.spread * 0.85, 0.3)
    }

    /// Brightness grows with the log of how many it stands for.
    static func brightness(_ count: Int32) -> Float {
        min(0.45 + 0.11 * Float(log2(Double(max(count, 1)))), 2.2)
    }

    /// A ball's radius on screen (points); everything when the eye is inside it.
    static func screenRadius(centre: SIMD3<Float>, radius: Float, eye: SIMD3<Float>, focal: Float) -> Float {
        let d = centre - eye
        let dist = (d * d).sum().squareRoot()
        if dist <= radius { return .infinity }
        return radius * focal / dist
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private mutating func visit(_ c: Int, at p: SIMD3<Float>, grow: Float, _ view: GraphPerfChunkView,
                                _ settings: GraphPerfChunkSettings) {
        let cell = octree.cells[c]
        let centre = cell.ballCentre, radius = cell.ballRadius
        let visible = view.frustum.touches(centre: centre, radius: radius)
        let guarded = visible || view.guardFrustum.touches(centre: centre, radius: radius)
        let size = Self.screenRadius(centre: centre, radius: radius, eye: view.eye, focal: view.focal)
        // opening follows size alone, on screen or off: a cell leaving the
        // view never snaps shut (links into it would jump), it is only not drawn
        var open: Float = Self.smoothstep(settings.split, settings.split * settings.span, size)
        if cell.isLeaf {
            let leaf = Int(cell.leaf)
            if guarded && size >= settings.split * settings.want {
                let d = centre - view.eye
                let dist = (d * d).sum().squareRoot()
                frame.wanted.append((Int32(leaf), dist * (visible ? 1 : 2)))
            }
            open *= ready[leaf]
            if visible { frame.visibleLeaves += 1 }
        }
        let cutLo = Int(bundles.cutStart[c]), cutHi = Int(bundles.cutEnd[c])
        // a cut cell is drawn where this cell is when the cut is at or below it
        if cutHi - cutLo == 1 && Int(bundles.cells[cutLo]) == c {
            frame.bundleCells[cutLo] = SIMD4(p.x, p.y, p.z, 1)
        }
        if open <= 0 {
            if visible { addSummary(c, at: p, scale: grow, settings) }
            let lo = Int(cell.leafStart), hi = Int(cell.leafEnd)
            for l in lo..<hi { frame.standIn[l] = SIMD4(p.x, p.y, p.z, 0) }
            for k in cutLo..<cutHi where Int(bundles.cells[k]) > c {
                frame.bundleCells[k] = SIMD4(p.x, p.y, p.z, 1)
            }
            return
        }
        if open < 1 && visible { addSummary(c, at: p, scale: grow * (1 - open), settings) }
        if cell.isLeaf {
            let leaf = Int(cell.leaf)
            // drawn leaves carry 2 more: a link between two drawn leaves is drawn once
            frame.standIn[leaf] = SIMD4(p.x, p.y, p.z, open + (visible ? 2 : 0))
            frame.openLeaves += 1
            if cutHi > cutLo { expandedMass[cutLo] += Float(cell.count) * open }
            if visible {
                frame.drawLeaves.append(UInt32(leaf))
                frame.drawLeaves.append(UInt32(frame.drawnBodies))
                frame.drawnBodies += Int(cell.count)
            }
            return
        }
        for child in octree.children(c) {
            let target = octree.cells[Int(child)].centroid
            visit(Int(child), at: p + (target - p) * open, grow: open, view, settings)
        }
    }

    private mutating func addSummary(_ index: Int, at p: SIMD3<Float>, scale: Float,
                                     _ settings: GraphPerfChunkSettings) {
        guard scale > 0 else { return }
        let cell = octree.cells[index]
        frame.summaryCells.append(Int32(index))
        let c = cell.colour
        frame.summaries.append(SIMD4(p.x, p.y, p.z, Self.summaryRadius(cell)))
        frame.summaries.append(SIMD4(Float(bitPattern: c), Self.brightness(cell.count), scale, 0))
    }
}

/// The prepared leaves: their links live in a fixed pool of pages on the
/// GPU (`pageSize` links a page); when it is full, the least recently used
/// leaves go first - but never one used in the last `protect` frames, which
/// a frame still on the GPU may be drawing.
nonisolated struct GraphPerfChunkCache: Sendable {
    static let none: Int32 = -1
    let pageSize: Int
    let pageCount: Int
    var protect: Int = 3
    /// Per leaf: its pages (empty when not prepared) and when it was last used.
    private(set) var pages: [[Int32]]
    private(set) var lastUsed: [Int]
    private(set) var resident: [Bool]
    private var free: [Int32]
    /// Least recently used first: a doubly linked list over the leaves.
    private var prev: [Int32]
    private var next: [Int32]
    private var head: Int32 = none
    private var tail: Int32 = none
    private(set) var evictions: Int = 0

    init(leaves: Int, pageCount: Int, pageSize: Int = 1024) {
        self.pageSize = max(pageSize, 1)
        self.pageCount = max(pageCount, 0)
        pages = [[Int32]](repeating: [], count: leaves)
        lastUsed = [Int](repeating: -1_000_000, count: leaves)
        resident = [Bool](repeating: false, count: leaves)
        free = (0..<Int32(max(pageCount, 0))).reversed()
        prev = [Int32](repeating: Self.none, count: leaves)
        next = [Int32](repeating: Self.none, count: leaves)
    }

    var freePages: Int { free.count }
    var residentCount: Int { resident.filter { $0 }.count }

    /// Pages a leaf with `links` links needs (an empty one still takes none).
    func pagesNeeded(_ links: Int) -> Int { (links + pageSize - 1) / pageSize }

    /// The leaf was drawn or wanted this frame: most recently used.
    mutating func touch(_ leaf: Int, frame: Int) {
        guard resident[leaf] else { return }
        lastUsed[leaf] = frame
        unlink(leaf)
        append(leaf)
    }

    /// Makes room for `leaf` with `links` links and keeps it, returning its
    /// pages and the leaves let go for it; nil (nothing changed) when even
    /// letting go of every unprotected leaf would not make room.
    mutating func admit(_ leaf: Int, links: Int, frame: Int) -> (pages: [Int32], evicted: [Int])? {
        if resident[leaf] {
            touch(leaf, frame: frame)
            return (pages[leaf], [])
        }
        let need = pagesNeeded(links)
        guard need <= pageCount else { return nil }
        // what letting go could free, oldest first, without touching the protected
        var freeable = free.count
        var victims: [Int] = []
        var at = head
        while freeable < need && at != Self.none {
            let l = Int(at)
            if lastUsed[l] < frame - protect {
                victims.append(l)
                freeable += pages[l].count
            }
            at = next[l]
        }
        guard freeable >= need else { return nil }
        for v in victims { release(v) }
        evictions += victims.count
        var mine: [Int32] = []
        mine.reserveCapacity(need)
        for _ in 0..<need { mine.append(free.removeLast()) }
        pages[leaf] = mine
        resident[leaf] = true
        lastUsed[leaf] = frame
        append(leaf)
        return (mine, victims)
    }

    /// Lets a leaf go (its pages back to the pool).
    mutating func release(_ leaf: Int) {
        guard resident[leaf] else { return }
        free.append(contentsOf: pages[leaf].reversed())
        pages[leaf] = []
        resident[leaf] = false
        unlink(leaf)
    }

    /// The leaves from least to most recently used (tests).
    var orderOfUse: [Int] {
        var out: [Int] = []
        var at = head
        while at != Self.none { out.append(Int(at)); at = next[Int(at)] }
        return out
    }

    private mutating func unlink(_ leaf: Int) {
        let p = prev[leaf], n = next[leaf]
        if p != Self.none { next[Int(p)] = n } else if head == Int32(leaf) { head = n }
        if n != Self.none { prev[Int(n)] = p } else if tail == Int32(leaf) { tail = p }
        prev[leaf] = Self.none
        next[leaf] = Self.none
    }

    private mutating func append(_ leaf: Int) {
        prev[leaf] = tail
        next[leaf] = Self.none
        if tail != Self.none { next[Int(tail)] = Int32(leaf) } else { head = Int32(leaf) }
        tail = Int32(leaf)
    }
}

/// Prepares the wanted leaves, nearest first, within a budget of links
/// copied and bodies laid out per frame - always at least one leaf, so a
/// leaf bigger than the budget never waits for ever.
nonisolated struct GraphPerfStreamer: Sendable {
    /// One leaf prepared this frame: copy its links into these pages and lay it out.
    struct Job: Sendable, Equatable {
        var leaf: Int
        var pages: [Int32]
    }

    var linkBudget: Int = 96_000
    var bodyBudget: Int = 48_000

    /// This frame's jobs, and the leaves let go to make room.
    func plan(wanted: [(leaf: Int32, priority: Float)], cache: inout GraphPerfChunkCache, links: GraphPerfLeafLinks,
              bodies: (Int) -> Int, frame: Int) -> (jobs: [Job], evicted: [Int]) {
        let sorted = wanted.sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.leaf < $1.leaf }
        var jobs: [Job] = []
        var evicted: [Int] = []
        var linksLeft = linkBudget, bodiesLeft = bodyBudget
        for w in sorted {
            let leaf = Int(w.leaf)
            if cache.resident[leaf] {
                cache.touch(leaf, frame: frame)
                continue
            }
            let n = links.count(leaf), b = bodies(leaf)
            if !jobs.isEmpty && (n > linksLeft || b > bodiesLeft) { continue }
            guard let got = cache.admit(leaf, links: n, frame: frame) else { continue }
            jobs.append(Job(leaf: leaf, pages: got.pages))
            evicted += got.evicted
            linksLeft -= n
            bodiesLeft -= b
            if linksLeft <= 0 || bodiesLeft <= 0 { break }
        }
        return (jobs, evicted)
    }
}
