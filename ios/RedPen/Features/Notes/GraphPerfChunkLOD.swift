// The million map's level of detail and streaming (plan 4e), worked out
// on the CPU each frame from the octree's few thousand cells, never from
// the million bodies:
//
// - Level of detail by size on screen: a cell opens once its ball covers
//   `split` points (radius), fully by `split` x `span`. Opening is a morph,
//   never a fade: the cell's summary point shrinks while its children (or,
//   in a leaf, its bodies) move out from where it was drawn and grow to
//   their own size. A child is never more open than its parent has grown,
//   so nothing inside a cell shows before the cell has made room for it;
//   and a cell opens or closes at a bounded pace (a quarter second end to
//   end), so no body rushes through the depth fade.
// - Depth shells (the owner: "the most surfaced is loaded and the deepest
//   to u is faded until u turn and they load"; plan 4f's depth fade,
//   GraphPerfDepthBand): each cell's fade f at its depth puts it in the
//   front, middle or back shell, and every switch is where f is about 0.6
//   or more (the cell already mostly faded), with hysteresis so a cell on a
//   border does not flicker. Its detail (1 front, 0.5 middle, 0 back)
//   moves there over `shellSeconds` (a fifth of a second), never at once:
//   a back cell opens only once it is `backSplit` times bigger than a front
//   one would, and the GPU draws its bodies smaller and flatter as well as
//   faded; turning the map round brings the back to the front and its
//   detail grows in. What lies past the band's end is culled (the view's
//   far plane). The selected note's leaf and its neighbours' leaves are
//   front whatever their depth.
// - Culling: a cell outside the view (GraphPerfFrustum) is neither drawn
//   nor opened. The guard band (GraphPerfGuardBand) is a wider frustum,
//   widest on the side the camera is moving towards: a leaf in it about to
//   open is prepared (laid out) before it is on screen.
// - Streaming: the leaves wanted this frame, front and big first, are
//   ordered here on the planning thread and prepared within a per-frame
//   budget of bodies laid out (GraphPerfStreamer); a leaf not prepared yet
//   keeps showing its summary, then morphs open over a quarter second once
//   it is ready. A laid-out leaf stays laid out, so turning back is instant.
// - Bundles: the links between two cells of the bundle cut are one bundle,
//   as wide as the share of both ends still closed.
//
// Foundation only: tested on Linux (Tests/GraphPerfChunkTests.swift).
import Foundation

/// What a frame needs from the camera.
nonisolated struct GraphPerfChunkView: Sendable {
    var eye: SIMD3<Float>
    /// Where the camera looks (unit length): depth is along it.
    var forward: SIMD3<Float>
    /// Points per world unit at depth 1.
    var focal: Float
    var frustum: GraphPerfFrustum
    /// The view widened by the guard band.
    var guardFrustum: GraphPerfFrustum
    /// The view volume's depths (the far one pulled in to the depth band's
    /// end when the band culls).
    var near: Float
    var far: Float
    /// The depth fade (GraphPerfDepthBand): its start and end depths, its
    /// exponent and how far it fades at most (0: no fade, everything front).
    var fade: SIMD4<Float>

    init(camera: GraphPerfCamera, width: Float, height: Float, near: Float, far: Float,
         guardBand: GraphPerfGuardBand = GraphPerfGuardBand(), motion: SIMD2<Float> = .zero,
         band: GraphPerfDepthBand? = nil, pull: Float = 1, mapRadius: Float = 0) {
        eye = camera.eye
        forward = camera.forward
        var farthest = far
        if let band {
            // as seen from here: inside the map every level fades over High's width
            let depths = band.seen(from: camera.distance, mapRadius: mapRadius).depths(focus: camera.distance, pull: pull)
            fade = SIMD4(depths.x, depths.y, band.k, band.most)
            if band.culls { farthest = max(min(far, depths.y), near + 1e-3) }
        } else {
            fade = SIMD4(0, 1, 1, 0)
        }
        self.near = near
        self.far = farthest
        focal = camera.focal(viewHeight: height)
        frustum = camera.frustum(width: width, height: height, near: near, far: farthest)
        guardFrustum = guardBand.frustum(camera, width: width, height: height, near: near, far: farthest,
                                         motion: motion)
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
    /// Depth shells, by the cell's fade f (GraphPerfDepthBand): it joins the
    /// front below `frontIn` and leaves it past `frontOut`; joins the back
    /// past `backIn` and leaves it below `backOut` (the gaps are the
    /// hysteresis). Every switch is where f is about 0.6 or more: the cell
    /// is already mostly faded, so the change does not show.
    var frontIn: Float = 0.6
    var frontOut: Float = 0.7
    var backIn: Float = 0.85
    var backOut: Float = 0.75
    /// A middle cell opens at `split` x this, a back one at `split` x `backSplit`.
    var middleSplit: Float = 1.7
    var backSplit: Float = 3.2
    /// Seconds a cell's detail takes from back (0) to front (1).
    var shellSeconds: Float = 0.2
    /// The fewest seconds a cell takes to open or close fully (a planner
    /// never advanced, as in some tests, opens at once).
    var openSeconds: Float = 0.25

    init() {}

    init(split: Float) {
        self.split = split
    }

    /// The detail a shell asks for: front 1, middle 0.5, back 0.
    static func detail(shell: UInt8) -> Float {
        shell == 0 ? 1 : (shell == 1 ? 0.5 : 0)
    }

    /// How much later than a front cell a cell of this detail opens.
    func splitFactor(detail q: Float) -> Float {
        let t = min(max(q, 0), 1)
        if t >= 0.5 { return middleSplit + (1 - middleSplit) * (2 * t - 1) }
        return backSplit + (middleSplit - backSplit) * (2 * t)
    }

    /// The shell for a fade f (0 crisp ... 1 gone), from the shell a cell was in.
    func shell(depth d: Float, was: UInt8) -> UInt8 {
        switch was {
        case 0:
            if d <= frontOut { return 0 }
            return d > backIn ? 2 : 1
        case 2:
            if d >= backOut { return 2 }
            return d < frontIn ? 0 : 1
        default:
            if d < frontIn { return 0 }
            return d > backIn ? 2 : 1
        }
    }
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
    /// Leaves to prepare (in or near the view, about to open), soonest
    /// first: the selected neighbourhood's, then by depth and size on screen.
    var wanted: [(leaf: Int32, priority: Float)] = []
    var visibleLeaves: Int = 0
    var openLeaves: Int = 0
    /// Per leaf: its detail, 0 (back) ... 1 (front), as last planned.
    var leafDetail: [Float] = []
    /// The depth fade this plan used: start and end depths, exponent, most
    /// (GraphPerfChunkView.fade).
    var fade = SIMD4<Float>(0, 1, 1, 0)
    /// Cells in each shell this plan (front, middle, back), and how many
    /// were still moving to their shell's detail.
    var shellCounts = SIMD3<Int32>(0, 0, 0)
    var ramping: Int = 0
    /// Cells still opening or closing towards their size's share, and
    /// leaves still growing ready: more frames are needed.
    var morphing: Int = 0

    var summaryCount: Int { summaries.count / 2 }
}

/// Plans each frame: which cells are culled, closed (a summary point) or
/// open, how far each is morphed, which shell each is in, and which leaves
/// to prepare.
nonisolated struct GraphPerfChunkPlanner: Sendable {
    let octree: GraphPerfOctree
    let bundles: GraphPerfBundles
    /// Per leaf, 0...1: how far it may open (0 until prepared, then rising
    /// to 1 over `readySeconds`, so a ready leaf morphs open, never pops).
    private(set) var ready: [Float]
    static let readySeconds: Float = 0.25
    private(set) var frame = GraphPerfChunkFrame()
    private var expandedMass: [Float]
    /// Per cell: its shell (0 front, 1 middle, 2 back), its detail (-1 not
    /// yet planned), and the plan it was last walked in.
    private var shell: [UInt8]
    private var detail: [Float]
    private var seen: [Int32]
    /// Per cell: how far it was open (before its leaf's readiness).
    private var opened: [Float]
    private var planNumber: Int32 = 0
    /// Seconds since the last plan (advance), for the shells' ramps.
    private var step: Float = 0
    /// Leaves shown at full detail whatever their depth (the selected
    /// note's and its neighbours'), sorted.
    private(set) var focusLeaves: [Int32] = []
    /// The octree flattened for the walk (made once, shared by copies).
    private let cells: GraphPerfPlanCells

    init(octree: GraphPerfOctree, bundles: GraphPerfBundles) {
        self.octree = octree
        self.bundles = bundles
        cells = GraphPerfPlanCells(octree: octree, bundles: bundles)
        ready = [Float](repeating: 0, count: octree.leafCount)
        expandedMass = [Float](repeating: 0, count: bundles.cells.count)
        shell = [UInt8](repeating: 1, count: octree.cells.count)
        detail = [Float](repeating: -1, count: octree.cells.count)
        seen = [Int32](repeating: -2, count: octree.cells.count)
        opened = [Float](repeating: 0, count: octree.cells.count)
        frame.standIn = [SIMD4<Float>](repeating: .zero, count: octree.leafCount)
        frame.bundleCells = [SIMD4<Float>](repeating: .zero, count: bundles.cells.count)
        frame.leafDetail = [Float](repeating: 0, count: octree.leafCount)
    }

    /// A leaf was prepared (true) or let go (false).
    mutating func setPrepared(_ leaf: Int, _ prepared: Bool) {
        guard leaf >= 0 && leaf < ready.count else { return }
        if !prepared { ready[leaf] = 0 } else if ready[leaf] == 0 { ready[leaf] = 1e-4 }
    }

    /// Whether a leaf has been prepared (laid out).
    func isPrepared(_ leaf: Int) -> Bool { leaf >= 0 && leaf < ready.count && ready[leaf] > 0 }

    /// Prepared leaves rise towards fully ready; the shells' ramps take the same step.
    mutating func advance(seconds: Float) {
        step = max(seconds, 0)
        let rise = step / Self.readySeconds
        ready.withUnsafeMutableBufferPointer { r in
            for l in 0..<r.count {
                let v = r[l]
                if v > 0 && v < 1 { r[l] = min(v + rise, 1) }
            }
        }
    }

    /// Makes every prepared leaf fully ready at once (tests; Reduce Motion).
    mutating func settleReady() {
        for l in 0..<ready.count where ready[l] > 0 { ready[l] = 1 }
    }

    /// The leaves shown at full detail whatever their depth: the selected
    /// note's and its neighbours' (empty for none).
    mutating func setFocus(leaves: [Int]) {
        focusLeaves = Array(Set(leaves.filter { $0 >= 0 && $0 < ready.count }.map { Int32($0) })).sorted()
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
        frame.shellCounts = SIMD3(0, 0, 0)
        frame.ramping = 0
        frame.morphing = 0
        guard !octree.cells.isEmpty, octree.bodyCount > 0 else { return frame }
        planNumber &+= 1
        // the arrays written, moved out of self so each has its own pointer
        var standIn = frame.standIn
        var cutAt = frame.bundleCells
        var leafDetail = frame.leafDetail
        var mass = expandedMass
        var shells = shell
        var details = detail
        var seenAt = seen
        var openedAt = opened
        expandedMass = []
        shell = []
        detail = []
        seen = []
        opened = []
        var out = frame
        frame = GraphPerfChunkFrame()
        let readyNow = ready
        let focus = focusLeaves
        var walk = GraphPerfPlanWalk(view: view, settings: settings, cells: cells, step: step,
                                     planNumber: planNumber)
        readyNow.withUnsafeBufferPointer { readyP in
            standIn.withUnsafeMutableBufferPointer { standP in
                cutAt.withUnsafeMutableBufferPointer { cutP in
                    mass.withUnsafeMutableBufferPointer { massP in
                        shells.withUnsafeMutableBufferPointer { shellP in
                            details.withUnsafeMutableBufferPointer { detailP in
                                seenAt.withUnsafeMutableBufferPointer { seenP in
                                    openedAt.withUnsafeMutableBufferPointer { openedP in
                                        leafDetail.withUnsafeMutableBufferPointer { leafDetailP in
                                            focus.withUnsafeBufferPointer { focusP in
                                                for k in 0..<massP.count { massP[k] = 0 }
                                                let state = GraphPerfPlanWalk.State(
                                                    ready: readyP, standIn: standP, cutAt: cutP, mass: massP,
                                                    shell: shellP, detail: detailP, seen: seenP, opened: openedP,
                                                    leafDetail: leafDetailP, focus: focusP)
                                                walk.run(state, frame: &out)
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
                            }
                        }
                    }
                }
            }
        }
        // the wanted leaves, soonest first: ordered here, on the planning
        // thread, so the frame only takes them in turn
        out.wanted.sort { $0.priority != $1.priority ? $0.priority < $1.priority : $0.leaf < $1.leaf }
        out.standIn = standIn
        out.bundleCells = cutAt
        out.leafDetail = leafDetail
        out.fade = view.fade
        frame = out
        expandedMass = mass
        shell = shells
        detail = details
        seen = seenAt
        opened = openedAt
        return frame
    }

    /// The detail a cell was last planned at (-1 when never walked).
    func cellDetail(_ c: Int) -> Float { c >= 0 && c < detail.count ? detail[c] : -1 }

    /// The shell a cell was last planned in (0 front, 1 middle, 2 back).
    func cellShell(_ c: Int) -> UInt8 { c >= 0 && c < shell.count ? shell[c] : 1 }

    /// Whether the last plan reached a cell (its parent was open).
    func wasWalked(_ c: Int) -> Bool { c >= 0 && c < seen.count && seen[c] == planNumber }

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

/// The planner behind a reference, so a frame changes it in place (and the
/// planning thread can work on it between frames).
nonisolated final class GraphPerfMillionState: @unchecked Sendable {
    var planner: GraphPerfChunkPlanner

    init(planner: GraphPerfChunkPlanner) {
        self.planner = planner
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
    /// The arrays a walk reads and writes, as raw buffers.
    struct State {
        var ready: UnsafeBufferPointer<Float>
        var standIn: UnsafeMutableBufferPointer<SIMD4<Float>>
        var cutAt: UnsafeMutableBufferPointer<SIMD4<Float>>
        var mass: UnsafeMutableBufferPointer<Float>
        /// Per cell.
        var shell: UnsafeMutableBufferPointer<UInt8>
        var detail: UnsafeMutableBufferPointer<Float>
        var seen: UnsafeMutableBufferPointer<Int32>
        var opened: UnsafeMutableBufferPointer<Float>
        /// Per leaf.
        var leafDetail: UnsafeMutableBufferPointer<Float>
        /// The focus leaves, sorted.
        var focus: UnsafeBufferPointer<Int32>
    }

    private let ex: Float, ey: Float, ez: Float
    private let fx: Float, fy: Float, fz: Float
    private let focal: Float
    private let split: Float, span: Float, want: Float
    private let settings: GraphPerfChunkSettings
    /// The depth fade: start depth, 1 / its width, exponent, most (0: none).
    private let fadeStart: Float, fadeScale: Float, fadeK: Float, fadeMost: Float
    /// How far a cell's detail may move this plan (0...1).
    private let ramp: Float
    /// How far a cell may open or close this plan (-1: as far as it likes).
    private let openStep: Float
    private let planNumber: Int32
    /// Planes as (nx, ny, nz, d): the view's, then the guard band's.
    private var planes: [Float]
    private let viewPlanes: Int, guardPlanes: Int
    private let cells: GraphPerfPlanCells

    init(view: GraphPerfChunkView, settings: GraphPerfChunkSettings, cells: GraphPerfPlanCells,
         step: Float = 0, planNumber: Int32 = 1) {
        ex = view.eye.x
        ey = view.eye.y
        ez = view.eye.z
        fx = view.forward.x
        fy = view.forward.y
        fz = view.forward.z
        focal = view.focal
        split = settings.split
        span = settings.span
        want = settings.want
        self.settings = settings
        fadeStart = view.fade.x
        fadeScale = 1 / max(view.fade.y - view.fade.x, 1e-6)
        fadeK = max(view.fade.z, 0.05)
        fadeMost = min(max(view.fade.w, 0), 1)
        ramp = settings.shellSeconds > 0 ? max(step, 0) / settings.shellSeconds : 1
        openStep = step > 0 && settings.openSeconds > 0 ? step / settings.openSeconds : -1
        self.planNumber = planNumber
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

    /// Whether any focus leaf lies in lo ..< hi (the focus is sorted).
    @inline(__always)
    private static func holdsFocus(_ focus: UnsafeBufferPointer<Int32>, _ lo: Int, _ hi: Int) -> Bool {
        var a = 0, b = focus.count
        while a < b {
            let mid = (a + b) / 2
            if Int(focus[mid]) < lo { a = mid + 1 } else { b = mid }
        }
        return a < focus.count && Int(focus[a]) < hi
    }

    /// Walks the octree.
    mutating func run(_ st: State, frame: inout GraphPerfChunkFrame) {
        let n = cells.count
        guard n > 0 else { return }
        let ball = cells.ball, centroid = cells.centroid, looks = cells.looks
        let ints = cells.ints, children = cells.children, cutCells = cells.cutCells
        let stride = GraphPerfPlanCells.intStride
        let ex = self.ex, ey = self.ey, ez = self.ez, fx = self.fx, fy = self.fy, fz = self.fz
        let focal = self.focal, split = self.split, span = self.span, want = self.want
        let fadeStart = self.fadeStart, fadeScale = self.fadeScale, fadeK = Double(self.fadeK)
        let fadeMost = self.fadeMost, ramp = self.ramp, openStep = self.openStep
        let settings = self.settings, planNumber = self.planNumber
        let viewPlanes = self.viewPlanes, guardPlanes = self.guardPlanes
        let ready = st.ready, standIn = st.standIn, cutAt = st.cutAt, mass = st.mass
        let shellP = st.shell, detailP = st.detail, seenP = st.seen, openedP = st.opened
        let leafDetail = st.leafDetail, focus = st.focus
        let anyFocus = focus.count > 0
        // the stack: a cell, where it is drawn and how far it has grown
        let stackCell = UnsafeMutablePointer<Int32>.allocate(capacity: n + 1)
        let stackAt = UnsafeMutablePointer<Float>.allocate(capacity: 4 * (n + 1))
        defer {
            stackCell.deallocate()
            stackAt.deallocate()
        }
        var drawn = frame.drawnBodies, visibleLeaves = frame.visibleLeaves, openLeaves = frame.openLeaves
        var front: Int32 = 0, middle: Int32 = 0, back: Int32 = 0, ramping = 0, morphing = 0
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
                let base = stride * c
                let leaf = Int(ints[base])
                // the cell's fade at its depth, 0 crisp ... 1 gone (GraphPerfDepthBand)
                let depth = dx * fx + dy * fy + dz * fz
                let t = min(max((depth - fadeStart) * fadeScale, 0), 1)
                let d: Float = t > 0 && fadeMost > 0 ? Float(pow(Double(t), fadeK)) * fadeMost : 0
                // its shell (with hysteresis) and its detail, moving there over
                // shellSeconds; a cell reached for the first time since it was
                // last hidden starts at its own shell's detail (its parent has
                // only begun to open, so it is drawn at next to nothing)
                let lo = Int(ints[base + 3]), hi = Int(ints[base + 4])
                let focused = anyFocus && Self.holdsFocus(focus, lo, hi)
                let walkedLast = seenP[c] == planNumber &- 1
                var sh = shellP[c]
                var q = detailP[c]
                if !walkedLast || q < 0 {
                    sh = focused ? 0 : settings.shell(depth: d, was: d < settings.frontOut ? 0 : 2)
                    q = GraphPerfChunkSettings.detail(shell: sh)
                } else {
                    sh = settings.shell(depth: d, was: sh)
                }
                if focused { sh = 0 }
                let target = GraphPerfChunkSettings.detail(shell: sh)
                if q < target {
                    q = min(q + ramp, target)
                } else if q > target {
                    q = max(q - ramp, target)
                }
                if q != target { ramping += 1 }
                shellP[c] = sh
                detailP[c] = q
                seenP[c] = planNumber
                if sh == 0 { front += 1 } else if sh == 1 { middle += 1 } else { back += 1 }
                let factor = settings.splitFactor(detail: q)
                let cellSplit = split * factor
                // opening follows size alone, on screen or off: a cell leaving
                // the view never snaps shut, it is only not drawn; and never
                // past how far its parent has grown, so a cell never shows
                // what is inside it before it has made room. It gets there at
                // a bounded pace: a turn that changes its detail moves its
                // bodies out (or in) over a quarter second, not in a frame
                let wantOpen = min(Self.smoothstep(cellSplit, cellSplit * span, size), grow)
                var open = wantOpen
                if openStep >= 0 && walkedLast {
                    let was = openedP[c]
                    open = min(max(wantOpen, was - openStep), was + openStep)
                    open = min(max(open, 0), grow)
                    if open != wantOpen { morphing += 1 }
                }
                openedP[c] = open
                if leaf >= 0 {
                    leafDetail[leaf] = q
                    if focused {
                        // the selected neighbourhood is prepared first, however small
                        if ready[leaf] == 0 { frame.wanted.append((Int32(leaf), 0)) }
                    } else if guarded && size >= cellSplit * want {
                        // sooner for the crisp and the big: fade, then size on screen
                        let soon = (1 + 2 * d) * (visible ? 1 : 2) / max(size, 1e-3)
                        frame.wanted.append((Int32(leaf), soon))
                    }
                    let r = ready[leaf]
                    if r > 0 && r < 1 { morphing += 1 }
                    open *= r
                    if visible { visibleLeaves += 1 }
                }
                let cutLo = Int(ints[base + 6]), cutHi = Int(ints[base + 7]), own = Int(ints[base + 8])
                // a cut cell is drawn where this cell is when the cut is at or below it
                if own >= 0 { cutAt[own] = SIMD4(px, py, pz, 1) }
                if open <= 0 {
                    if visible && grow > 0 { Self.summary(c, px, py, pz, grow, looks, &frame) }
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
                    // drawn leaves carry 2 more
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
        frame.shellCounts = SIMD3(front, middle, back)
        frame.ramping = ramping
        frame.morphing = morphing
    }

    @inline(__always)
    private static func summary(_ c: Int, _ x: Float, _ y: Float, _ z: Float, _ scale: Float,
                                _ looks: UnsafeMutablePointer<Float>, _ frame: inout GraphPerfChunkFrame) {
        frame.summaryCells.append(Int32(c))
        frame.summaries.append(SIMD4(x, y, z, looks[4 * c]))
        frame.summaries.append(SIMD4(looks[4 * c + 2], looks[4 * c + 1], scale, 0))
    }
}

/// Prepares the wanted leaves in the order the planner gave them (the
/// selected neighbourhood first, then front and big first) within a budget
/// of bodies laid out a frame - always at least one leaf, so a leaf bigger
/// than the budget never waits for ever. A leaf once laid out stays laid
/// out: its positions are on the GPU for the session.
nonisolated struct GraphPerfStreamer: Sendable {
    var bodyBudget: Int = 28_000

    /// This frame's leaves to lay out: wanted, not yet prepared, in order.
    func plan(wanted: [(leaf: Int32, priority: Float)], isPrepared: (Int) -> Bool, bodies: (Int) -> Int) -> [Int] {
        var jobs: [Int] = []
        var bodiesLeft = bodyBudget
        var taken = Set<Int>()
        for w in wanted {
            let leaf = Int(w.leaf)
            if isPrepared(leaf) || taken.contains(leaf) { continue }
            let b = bodies(leaf)
            if !jobs.isEmpty && b > bodiesLeft { continue }
            jobs.append(leaf)
            taken.insert(leaf)
            bodiesLeft -= b
            if bodiesLeft <= 0 { break }
        }
        return jobs
    }
}
