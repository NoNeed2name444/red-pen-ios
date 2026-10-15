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
    /// The octree flattened for the walk (made once, shared by copies).
    private let cells: GraphPerfPlanCells

    init(octree: GraphPerfOctree, bundles: GraphPerfBundles) {
        self.octree = octree
        self.bundles = bundles
        cells = GraphPerfPlanCells(octree: octree, bundles: bundles)
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
        ready.withUnsafeMutableBufferPointer { r in
            for l in 0..<r.count {
                let v = r[l]
                if v > 0 && v < 1 { r[l] = min(v + step, 1) }
            }
        }
    }

    /// Makes every prepared leaf fully ready at once (tests; Reduce Motion).
    mutating func settleReady() {
        for l in 0..<ready.count where ready[l] > 0 { ready[l] = 1 }
    }

    /// The frame for this view.
    ///
    /// The walk runs over flat per-cell arrays (GraphPerfPlanCells) with
    /// plain Float arithmetic through unsafe pointers and an explicit stack:
    /// no SIMD generics, no struct copies, no bounds checks, no recursion.
    /// Swift Playgrounds builds without optimisation, where those cost about
    /// 50 times their optimised price, and that is how the owner runs it.
    @discardableResult
    mutating func plan(_ view: GraphPerfChunkView, settings: GraphPerfChunkSettings) -> GraphPerfChunkFrame {
        frame.drawLeaves.removeAll(keepingCapacity: true)
        frame.summaries.removeAll(keepingCapacity: true)
        frame.summaryCells.removeAll(keepingCapacity: true)
        frame.wanted.removeAll(keepingCapacity: true)
        frame.drawnBodies = 0
        frame.visibleLeaves = 0
        frame.openLeaves = 0
        guard !octree.cells.isEmpty, octree.bodyCount > 0 else { return frame }
        // the arrays written, moved out of self so each has its own pointer
        var standIn = frame.standIn
        var cutAt = frame.bundleCells
        var mass = expandedMass
        expandedMass = []
        var out = frame
        frame = GraphPerfChunkFrame()
        let readyNow = ready
        var walk = GraphPerfPlanWalk(view: view, settings: settings, cells: cells)
        readyNow.withUnsafeBufferPointer { readyP in
            standIn.withUnsafeMutableBufferPointer { standP in
                cutAt.withUnsafeMutableBufferPointer { cutP in
                    mass.withUnsafeMutableBufferPointer { massP in
                        for k in 0..<massP.count { massP[k] = 0 }
                        walk.run(ready: readyP, standIn: standP, cutAt: cutP, mass: massP, frame: &out)
                        // a cut cell's bundle is as wide as its share still closed
                        let cutCells = cells.cutCells, ints = cells.ints
                        for k in 0..<cutP.count {
                            let count = ints[Int(cutCells[k]) * GraphPerfPlanCells.intStride + 5]
                            cutP[k].w = 1 - min(massP[k] / Float(max(count, 1)), 1)
                        }
                    }
                }
            }
        }
        out.standIn = standIn
        out.bundleCells = cutAt
        frame = out
        expandedMass = mass
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
}

/// The planner and the cache behind a reference, so a frame changes them in
/// place (and the planning thread can work on them between frames).
nonisolated final class GraphPerfMillionState: @unchecked Sendable {
    var planner: GraphPerfChunkPlanner
    var cache: GraphPerfChunkCache

    init(planner: GraphPerfChunkPlanner, cache: GraphPerfChunkCache) {
        self.planner = planner
        self.cache = cache
    }
}

/// Plans the next frame on its own thread while the main thread finishes
/// this one, so planning is off the frame's critical path (Swift Playgrounds
/// builds without optimisation, where a plan costs the most). The next frame
/// takes the plan made from this frame's view: the guard band already covers
/// a frame of motion. Only one plan is ever in flight, and the main thread
/// touches the state only after `finish` or `wait`, so the two never share it.
nonisolated final class GraphPerfPlanAhead: @unchecked Sendable {
    private let queue = DispatchQueue(label: "graphperf.plan", qos: .userInteractive)
    private let group = DispatchGroup()
    private var made: (state: GraphPerfMillionState, frame: GraphPerfChunkFrame, seconds: Double)?
    /// The last wait for a plan still running (seconds).
    private(set) var waited: Double = 0

    init() {}

    /// Starts the next plan: the ready leaves advance by `step`, then the plan for `view`.
    func start(_ state: GraphPerfMillionState, view: GraphPerfChunkView, settings: GraphPerfChunkSettings, step: Float) {
        group.wait()
        made = nil
        group.enter()
        queue.async { [self] in
            let began = DispatchTime.now().uptimeNanoseconds
            state.planner.advance(seconds: step)
            let frame = state.planner.plan(view, settings: settings)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9
            made = (state, frame, seconds)
            group.leave()
        }
    }

    /// Waits for the plan in flight; returns it (and how long it took) when it
    /// was made for `state`, nil when there was none or the map changed.
    func finish(for state: GraphPerfMillionState) -> (frame: GraphPerfChunkFrame, seconds: Double)? {
        let began = DispatchTime.now().uptimeNanoseconds
        group.wait()
        waited = Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9
        defer { made = nil }
        guard let m = made, m.state === state else { return nil }
        return (m.frame, m.seconds)
    }

    /// Waits until no plan is running (before the main thread reads the state).
    func wait() {
        group.wait()
    }
}

/// The octree flattened for the planner's walk, made once per map: per
/// cell its ball and centroid (4 floats each), its summary's radius,
/// brightness and colour bits (4 floats), and 9 integers (leaf, first
/// child, children, first leaf, leaf end, bodies, bundle-cut range, and the
/// cut index it is itself, or -1). Read-only after it is made, so copies of
/// a planner share it.
nonisolated final class GraphPerfPlanCells: @unchecked Sendable {
    static let intStride = 9
    let count: Int
    let ball: UnsafeMutablePointer<Float>
    let centroid: UnsafeMutablePointer<Float>
    let looks: UnsafeMutablePointer<Float>
    let ints: UnsafeMutablePointer<Int32>
    let children: UnsafeMutablePointer<Int32>
    let childTotal: Int
    /// The bundle cut's cells, as GraphPerfBundles.cells.
    let cutCells: UnsafeMutablePointer<Int32>
    let cutCount: Int

    init(octree: GraphPerfOctree, bundles: GraphPerfBundles) {
        let n = octree.cells.count
        count = n
        ball = .allocate(capacity: max(4 * n, 1))
        centroid = .allocate(capacity: max(4 * n, 1))
        looks = .allocate(capacity: max(4 * n, 1))
        ints = .allocate(capacity: max(Self.intStride * n, 1))
        childTotal = octree.childList.count
        children = .allocate(capacity: max(childTotal, 1))
        cutCount = bundles.cells.count
        cutCells = .allocate(capacity: max(cutCount, 1))
        for (c, cell) in octree.cells.enumerated() {
            let centre = cell.ballCentre
            ball[4 * c] = centre.x
            ball[4 * c + 1] = centre.y
            ball[4 * c + 2] = centre.z
            ball[4 * c + 3] = cell.ballRadius
            centroid[4 * c] = cell.centroid.x
            centroid[4 * c + 1] = cell.centroid.y
            centroid[4 * c + 2] = cell.centroid.z
            centroid[4 * c + 3] = 0
            looks[4 * c] = GraphPerfChunkPlanner.summaryRadius(cell)
            looks[4 * c + 1] = GraphPerfChunkPlanner.brightness(cell.count)
            looks[4 * c + 2] = Float(bitPattern: cell.colour)
            looks[4 * c + 3] = 0
            let cutLo = c < bundles.cutStart.count ? Int32(bundles.cutStart[c]) : 0
            let cutHi = c < bundles.cutEnd.count ? Int32(bundles.cutEnd[c]) : 0
            let own: Int32 = cutHi - cutLo == 1 && Int(bundles.cells[Int(cutLo)]) == c ? cutLo : -1
            let base = Self.intStride * c
            ints[base] = cell.leaf
            ints[base + 1] = cell.childStart
            ints[base + 2] = cell.childCount
            ints[base + 3] = cell.leafStart
            ints[base + 4] = cell.leafEnd
            ints[base + 5] = cell.count
            ints[base + 6] = cutLo
            ints[base + 7] = cutHi
            ints[base + 8] = own
        }
        for (k, child) in octree.childList.enumerated() { children[k] = child }
        for (k, cell) in bundles.cells.enumerated() { cutCells[k] = Int32(cell) }
    }

    deinit {
        ball.deallocate()
        centroid.deallocate()
        looks.deallocate()
        ints.deallocate()
        children.deallocate()
        cutCells.deallocate()
    }
}

/// One plan's walk over GraphPerfPlanCells: depth first, children in order
/// (the same order, and the same arithmetic, as walking the octree's cells).
nonisolated struct GraphPerfPlanWalk {
    private let ex: Float, ey: Float, ez: Float
    private let focal: Float
    private let split: Float, fullSplit: Float, wantSize: Float
    /// Planes as (nx, ny, nz, d): the view's, then the guard band's.
    private var planes: [Float]
    private let viewPlanes: Int, guardPlanes: Int
    private let cells: GraphPerfPlanCells

    init(view: GraphPerfChunkView, settings: GraphPerfChunkSettings, cells: GraphPerfPlanCells) {
        ex = view.eye.x
        ey = view.eye.y
        ez = view.eye.z
        focal = view.focal
        split = settings.split
        fullSplit = settings.split * settings.span
        wantSize = settings.split * settings.want
        self.cells = cells
        var p: [Float] = []
        p.reserveCapacity(4 * (view.frustum.planes.count + view.guardFrustum.planes.count))
        for plane in view.frustum.planes { p += [plane.normal.x, plane.normal.y, plane.normal.z, plane.d] }
        for plane in view.guardFrustum.planes { p += [plane.normal.x, plane.normal.y, plane.normal.z, plane.d] }
        planes = p
        viewPlanes = view.frustum.planes.count
        guardPlanes = view.guardFrustum.planes.count
    }

    /// Whether a ball reaches inside planes[from ..< from + count].
    @inline(__always)
    private static func touches(_ planes: UnsafeBufferPointer<Float>, from: Int, count: Int,
                                _ x: Float, _ y: Float, _ z: Float, _ r: Float) -> Bool {
        var k = from
        let end = from + count
        while k < end {
            let b = 4 * k
            if planes[b] * x + planes[b + 1] * y + planes[b + 2] * z - planes[b + 3] > r { return false }
            k += 1
        }
        return true
    }

    @inline(__always)
    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    mutating func run(ready: UnsafeBufferPointer<Float>, standIn: UnsafeMutableBufferPointer<SIMD4<Float>>,
                      cutAt: UnsafeMutableBufferPointer<SIMD4<Float>>, mass: UnsafeMutableBufferPointer<Float>,
                      frame: inout GraphPerfChunkFrame) {
        let n = cells.count
        guard n > 0 else { return }
        let ball = cells.ball, centroid = cells.centroid, looks = cells.looks
        let ints = cells.ints, children = cells.children, cutCells = cells.cutCells
        let stride = GraphPerfPlanCells.intStride
        let ex = self.ex, ey = self.ey, ez = self.ez, focal = self.focal
        let split = self.split, fullSplit = self.fullSplit, wantSize = self.wantSize
        let viewPlanes = self.viewPlanes, guardPlanes = self.guardPlanes
        // the stack: a cell, where it is drawn, and how far it has grown
        let stackCell = UnsafeMutablePointer<Int32>.allocate(capacity: n + 1)
        let stackAt = UnsafeMutablePointer<Float>.allocate(capacity: 4 * (n + 1))
        defer {
            stackCell.deallocate()
            stackAt.deallocate()
        }
        var drawn = frame.drawnBodies, visibleLeaves = frame.visibleLeaves, openLeaves = frame.openLeaves
        planes.withUnsafeBufferPointer { pl in
            var top = 0
            stackCell[0] = 0
            stackAt[0] = centroid[0]
            stackAt[1] = centroid[1]
            stackAt[2] = centroid[2]
            stackAt[3] = 1
            top = 1
            while top > 0 {
                top -= 1
                let c = Int(stackCell[top])
                let px = stackAt[4 * top], py = stackAt[4 * top + 1], pz = stackAt[4 * top + 2]
                let grow = stackAt[4 * top + 3]
                let cx = ball[4 * c], cy = ball[4 * c + 1], cz = ball[4 * c + 2], radius = ball[4 * c + 3]
                let visible = Self.touches(pl, from: 0, count: viewPlanes, cx, cy, cz, radius)
                let guarded = visible || Self.touches(pl, from: viewPlanes, count: guardPlanes, cx, cy, cz, radius)
                let dx = cx - ex, dy = cy - ey, dz = cz - ez
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                let size: Float = dist <= radius ? .infinity : radius * focal / dist
                // opening follows size alone, on screen or off: a cell leaving
                // the view never snaps shut, it is only not drawn
                var open = Self.smoothstep(split, fullSplit, size)
                let base = stride * c
                let leaf = Int(ints[base])
                if leaf >= 0 {
                    if guarded && size >= wantSize {
                        frame.wanted.append((Int32(leaf), dist * (visible ? 1 : 2)))
                    }
                    open *= ready[leaf]
                    if visible { visibleLeaves += 1 }
                }
                let cutLo = Int(ints[base + 6]), cutHi = Int(ints[base + 7]), own = Int(ints[base + 8])
                // a cut cell is drawn where this cell is when the cut is at or below it
                if own >= 0 { cutAt[own] = SIMD4(px, py, pz, 1) }
                if open <= 0 {
                    if visible && grow > 0 { Self.summary(c, px, py, pz, grow, looks, &frame) }
                    let lo = Int(ints[base + 3]), hi = Int(ints[base + 4])
                    var l = lo
                    while l < hi {
                        standIn[l] = SIMD4(px, py, pz, 0)
                        l += 1
                    }
                    var k = cutLo
                    while k < cutHi {
                        if Int(cutCells[k]) > c { cutAt[k] = SIMD4(px, py, pz, 1) }
                        k += 1
                    }
                    continue
                }
                if open < 1 && visible {
                    let scale = grow * (1 - open)
                    if scale > 0 { Self.summary(c, px, py, pz, scale, looks, &frame) }
                }
                if leaf >= 0 {
                    let count = Int(ints[base + 5])
                    // drawn leaves carry 2 more: a link between two drawn leaves is drawn once
                    standIn[leaf] = SIMD4(px, py, pz, open + (visible ? 2 : 0))
                    openLeaves += 1
                    if cutHi > cutLo { mass[cutLo] += Float(count) * open }
                    if visible {
                        frame.drawLeaves.append(UInt32(leaf))
                        frame.drawLeaves.append(UInt32(drawn))
                        drawn += count
                    }
                    continue
                }
                // children pushed last first, so they come off in order
                let first = Int(ints[base + 1]), kids = Int(ints[base + 2])
                var j = kids - 1
                while j >= 0 {
                    let child = Int(children[first + j])
                    let tx = centroid[4 * child], ty = centroid[4 * child + 1], tz = centroid[4 * child + 2]
                    stackCell[top] = Int32(child)
                    stackAt[4 * top] = px + (tx - px) * open
                    stackAt[4 * top + 1] = py + (ty - py) * open
                    stackAt[4 * top + 2] = pz + (tz - pz) * open
                    stackAt[4 * top + 3] = open
                    top += 1
                    j -= 1
                }
            }
        }
        frame.drawnBodies = drawn
        frame.visibleLeaves = visibleLeaves
        frame.openLeaves = openLeaves
    }

    @inline(__always)
    private static func summary(_ c: Int, _ x: Float, _ y: Float, _ z: Float, _ scale: Float,
                                _ looks: UnsafeMutablePointer<Float>, _ frame: inout GraphPerfChunkFrame) {
        frame.summaryCells.append(Int32(c))
        frame.summaries.append(SIMD4(x, y, z, looks[4 * c]))
        frame.summaries.append(SIMD4(looks[4 * c + 2], looks[4 * c + 1], scale, 0))
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
