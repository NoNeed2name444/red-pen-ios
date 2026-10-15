// The million map's Metal renderer (plans 4b, 4c, 4e, 4f): a million bodies
// at the screen's own rate, crisp near the camera's focus and dissolving
// into the ground with depth.
//
// - Everything coarse stays on the GPU for the whole session (about 40 MB
//   for a million): every body's 16-bit position with its leaf, its seed,
//   colour and size, each leaf's box, the links' adjacency, and the bundles.
//   "Loading" is only choosing detail: no disk, no waiting.
// - Each frame is planned from the octree's few thousand cells, never the
//   million bodies (GraphPerfChunkPlanner: culling, morphs, depth shells,
//   the guard band), on a planning thread a frame ahead (GraphPerfPlanAhead),
//   so the plan is off the main thread's frame even in an unoptimised
//   Playgrounds build.
// - The depth fade (GraphPerfDepthBand, docs/design/depth-fade.md): the
//   band follows the camera's focus, set by the Graphics level and pulled
//   in by the frame budget; past its end nothing is drawn, and detail drops
//   only where a cell is already mostly faded.
// - Bundles and summary glows add up as light in a half-float texture at a
//   quarter of the pixels; the screen shows it through a tone curve whose
//   exposure follows the picture's own 97th percentile (GraphPerfExposure),
//   and the notes are drawn over it in their own colours, so crowded light
//   reads as structure and notes stay shapes. A 64 x 64 grid measured on the
//   GPU feeds the exposure and the readout's share of the screen at 250+.
// - Links are hidden; choosing a note draws its own (from the adjacency),
//   growing out to its neighbours while the rest steps back
//   (GraphPerfFocusMotion), and its neighbourhood's leaves come to full
//   detail first (D4).
// - Leaves about to open, the crisp and big first, are prepared within the
//   frame's budget (GraphPerfStreamer): laid out by the GPU (mil_layout) in
//   the same command buffer, before they are drawn.
// - The frame budget (GraphPerfFrameBudget) reads each frame's CPU time and
//   the GPU times of its stages (near: layout, notes, the screen pass; far:
//   bundles and glows) - from the GPU's own timestamps, or the wall clock
//   where they are missing (the simulator) - and trims the stage that took
//   the time (the split and the depth band for the near one, the bundles
//   drawn for the far one), never the frame rate, which is the screen's own.
//
// Free of Stethoscore types: GraphPerfMapView drives it.
#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit

/// The GPU's own time for frames, written from Metal's completion thread.
final class GraphPerfGPUClock: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    private var latestTime: Double?

    func add(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0, seconds < 1 else { return }
        lock.lock()
        times.append(seconds)
        latestTime = seconds
        lock.unlock()
    }

    /// The last frame's GPU time.
    var latest: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestTime
    }

    /// The times since the last call.
    func drain() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let out = times
        times.removeAll(keepingCapacity: true)
        return out
    }

    /// Times a command buffer once the GPU is done with it.
    func time(_ commands: MTLCommandBuffer) {
        commands.addCompletedHandler { [self] done in
            self.add(done.gpuEndTime - done.gpuStartTime)
        }
    }
}

/// The GPU's time for each stage of a frame, each its own command buffer:
/// the near stage (layout, notes) and the far stage (bundles, glows), and
/// the screen stage (tone-mapping the light, the notes over it), which
/// counts as near. Taken from the GPU's own timestamps while they are
/// believable, else from the wall clock (GraphPerfWallStages): the
/// simulator reports about 0, and a budget blind to the GPU would never
/// trim it.
final class GraphPerfStageClock: @unchecked Sendable {
    /// One frame's three command buffers.
    final class Frame: @unchecked Sendable {
        var commitNear: Double = 0
        var gpu = SIMD3<Double>(0, 0, 0)
        var done = SIMD3<Double>(0, 0, 0)
        var finished = 0
    }

    private let lock = NSLock()
    private var nearTimes: [Double] = []
    private var farTimes: [Double] = []
    private var latestNear: Double?
    private var latestFar: Double?
    private var lastDone: Double = 0
    /// Whether the last frame's times came from the wall clock.
    private(set) var fromWall = false
    private let total: GraphPerfGPUClock

    init(total: GraphPerfGPUClock) {
        self.total = total
    }

    private static func usable(_ seconds: Double) -> Double {
        seconds.isFinite && seconds >= 0 && seconds < 1 ? seconds : 0
    }

    /// Times the frame's three command buffers (call before committing them).
    func time(near: MTLCommandBuffer, far: MTLCommandBuffer, screen: MTLCommandBuffer) -> Frame {
        let frame = Frame()
        for (k, commands) in [near, far, screen].enumerated() {
            commands.addCompletedHandler { [self] done in
                let now = CACurrentMediaTime()
                self.finish(frame, stage: k, gpu: Self.usable(done.gpuEndTime - done.gpuStartTime), at: now)
            }
        }
        return frame
    }

    /// The near stage was committed (host time).
    func committed(_ frame: Frame) {
        lock.lock()
        frame.commitNear = CACurrentMediaTime()
        lock.unlock()
    }

    private func finish(_ frame: Frame, stage: Int, gpu: Double, at now: Double) {
        lock.lock()
        frame.gpu[stage] = gpu
        frame.done[stage] = now
        frame.finished += 1
        guard frame.finished == 3 else {
            lock.unlock()
            return
        }
        let wall = GraphPerfWallStages.stages(commitA: frame.commitNear, doneA: frame.done.x, doneB: frame.done.y,
                                              doneC: frame.done.z, lastDoneC: lastDone)
        lastDone = max(lastDone, frame.done.z)
        let own = (near: frame.gpu.x + frame.gpu.z, far: frame.gpu.y)
        let useWall = !GraphPerfWallStages.gpuTimesUsable(gpu: own.near + own.far, wall: wall.near + wall.far)
        let near = useWall ? min(wall.near, 0.25) : own.near
        let far = useWall ? min(wall.far, 0.25) : own.far
        fromWall = useWall
        nearTimes.append(near)
        farTimes.append(far)
        latestNear = near
        latestFar = far
        lock.unlock()
        total.add(near + far)
    }

    /// The last frame's two stages (nil until a frame has reported).
    var latest: (near: Double?, far: Double?) {
        lock.lock()
        defer { lock.unlock() }
        return (latestNear, latestFar)
    }

    /// The times since the last call.
    func drain() -> (near: [Double], far: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        let out = (nearTimes, farTimes)
        nearTimes.removeAll(keepingCapacity: true)
        farTimes.removeAll(keepingCapacity: true)
        return out
    }
}

@MainActor
final class GraphPerfMillionRenderer: NSObject, @preconcurrency MTKViewDelegate, GraphPerfEngine {
    static let slotCount: Int = 3
    /// The light's format: half floats, so light adds up past 1 without clipping.
    static let lightFormat: MTLPixelFormat = .rgba16Float
    /// Leaves laid out in one frame at most (the jobs buffer's size).
    static let maxJobs = 256
    /// Seconds for the budget's depth band and bundle count to cover most
    /// (63%) of a change: the fade's edge and the bundles move, never jump.
    static let pullSeconds: Float = 0.4
    static let bundleSeconds: Float = 0.2

    let device: MTLDevice
    private let queue: MTLCommandQueue
    /// Notes in their own colours, on the screen.
    private let nodePipeline: MTLRenderPipelineState
    private let chosenPipeline: MTLRenderPipelineState
    /// The chosen note's links and neighbours, over the rest.
    private let focusLinkPipeline: MTLRenderPipelineState
    private let focusNodePipeline: MTLRenderPipelineState
    /// Light: bundles and glows add into the light texture.
    private let bundlePipeline: MTLRenderPipelineState
    private let summaryPipeline: MTLRenderPipelineState
    /// The tone curve, light to screen.
    private let resolvePipeline: MTLRenderPipelineState
    private let layoutPipeline: MTLComputePipelineState
    private let measurePipeline: MTLComputePipelineState
    private let solidDepth: MTLDepthStencilState
    private let overDepth: MTLDepthStencilState
    private let inFlight = DispatchSemaphore(value: GraphPerfMillionRenderer.slotCount)
    private let gpuClock = GraphPerfGPUClock()
    private lazy var stageClock = GraphPerfStageClock(total: gpuClock)
    private let planAhead = GraphPerfPlanAhead()

    private(set) var map: GraphPerfMillionMap?
    private var statics: GraphPerfMillionStatics?
    private var slots: [GraphPerfMillionSlot] = []
    /// The planner, mutated in place each frame (between frames by the planning thread).
    private var state: GraphPerfMillionState?
    private var streamer = GraphPerfStreamer()
    private(set) var budget: GraphPerfFrameBudget
    private var exposure = GraphPerfExposure()
    private var light: MTLTexture?
    private var frameNumber: Int = 0

    // what the map view sets
    var camera = GraphPerfCamera()
    var tier: GraphPerfTier = .high {
        didSet { if tier != oldValue { budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp) } }
    }
    var bold: Bool = false
    /// Increase Contrast: the depth fade starts later and stops short of the ground.
    var contrast: Bool = false
    /// The depth fade on (off only for the before-and-after numbers).
    var depthFade: Bool = true
    var reduceMotion: Bool = false
    var selected: Int?
    var focus: Int?
    var screenFPS: Int = 60 {
        didSet { if screenFPS != oldValue { budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp) } }
    }
    var beforeFrame: ((Double) -> Void)?
    var onStats: ((GraphPerfStats) -> Void)?
    /// Every drawn frame's numbers (the proof tour's).
    var onFrame: ((GraphPerfFrameReport) -> Void)?

    // the selection's motion, and the depth band and bundles as eased
    private var focusMotion = GraphPerfFocusMotion()
    private var focusSlot: Int?
    private var focusReach: Float = 1
    private var focusReachSlot: Int?
    private var pull: Float = 1
    private var bundlesShown: Float = -1
    /// Cells moving to their shell's detail, cells or leaves still
    /// morphing, and leaves laid out this frame: more frames are needed.
    private var ramping = 0
    private var morphing = 0
    private var streaming = false

    // motion for the guard band, pacing and the readout
    private var lastCamera: GraphPerfCamera?
    private var motion = SIMD2<Float>(0, 0)
    private var lastTime: CFTimeInterval = 0
    private var lastMeasure: CFTimeInterval = 0
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var intervals: [Double] = []
    /// The last 3 s of frame intervals, for the readout's median, 5th percentile and 1% low.
    private var recentIntervals: [Double] = []
    private var cpuTimes: [Double] = []
    private var planTimes: [Double] = []
    private var saturations: [Double] = []
    private var drawnBundles: Int = 0
    private var drawCalls: Int = 0
    private var memoryPeak: Int = 0
    private var statsTime: CFTimeInterval = 0

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: GraphPerfMillionShaders.source, options: nil)
        } catch {
            NSLog("GraphPerfMillion: the shaders did not compile: %@", String(describing: error))
            return nil
        }
        let screenFormat: MTLPixelFormat = view.colorPixelFormat
        let depthFormat: MTLPixelFormat = view.depthStencilPixelFormat
        enum Blend { case none, additive, over }
        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat, blend: Blend,
                      onScreen: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                NSLog("GraphPerfMillion: no function %@ or %@", vertex, fragment)
                return nil
            }
            d.vertexFunction = v
            d.fragmentFunction = f
            // the light pass has no depth: glows and bundles add up, and the
            // notes, drawn opaque over the light, hide what is behind them
            d.depthAttachmentPixelFormat = onScreen ? depthFormat : .invalid
            d.rasterSampleCount = onScreen ? view.sampleCount : 1
            guard let colour = d.colorAttachments[0] else { return nil }
            colour.pixelFormat = format
            switch blend {
            case .none:
                break
            case .additive:
                colour.isBlendingEnabled = true
                colour.rgbBlendOperation = .add
                colour.alphaBlendOperation = .add
                colour.sourceRGBBlendFactor = .one
                colour.destinationRGBBlendFactor = .one
                colour.sourceAlphaBlendFactor = .zero
                colour.destinationAlphaBlendFactor = .one
            case .over:
                // premultiplied: the focus links' smooth edges
                colour.isBlendingEnabled = true
                colour.rgbBlendOperation = .add
                colour.alphaBlendOperation = .add
                colour.sourceRGBBlendFactor = .one
                colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colour.sourceAlphaBlendFactor = .one
                colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            do {
                return try device.makeRenderPipelineState(descriptor: d)
            } catch {
                NSLog("GraphPerfMillion: pipeline %@: %@", vertex, String(describing: error))
                return nil
            }
        }
        func compute(_ name: String) -> MTLComputePipelineState? {
            guard let kernel = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: kernel)
        }
        func depth(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        let lightFormat = Self.lightFormat
        guard let node = pipeline("mil_node_vertex", "mil_node_fragment", format: screenFormat, blend: .none,
                                  onScreen: true),
              let chosen = pipeline("mil_chosen_vertex", "mil_node_fragment", format: screenFormat, blend: .none,
                                    onScreen: true),
              let focusLink = pipeline("mil_focus_link_vertex", "mil_focus_link_fragment", format: screenFormat,
                                       blend: .over, onScreen: true),
              let focusNode = pipeline("mil_focus_node_vertex", "mil_node_fragment", format: screenFormat,
                                       blend: .none, onScreen: true),
              let bundle = pipeline("mil_bundle_vertex", "mil_line_fragment", format: lightFormat, blend: .additive,
                                    onScreen: false),
              let summary = pipeline("mil_summary_vertex", "mil_summary_fragment", format: lightFormat,
                                     blend: .additive, onScreen: false),
              let resolve = pipeline("mil_resolve_vertex", "mil_resolve_fragment", format: screenFormat, blend: .none,
                                     onScreen: true),
              let layout = compute("mil_layout"),
              let measure = compute("mil_measure"),
              let solid = depth(.less, write: true),
              let over = depth(.always, write: false) else {
            return nil
        }
        self.device = device
        self.queue = queue
        nodePipeline = node
        chosenPipeline = chosen
        focusLinkPipeline = focusLink
        focusNodePipeline = focusNode
        bundlePipeline = bundle
        summaryPipeline = summary
        resolvePipeline = resolve
        layoutPipeline = layout
        measurePipeline = measure
        solidDepth = solid
        overDepth = over
        budget = GraphPerfFrameBudget(screenFPS: 60)
        super.init()
    }

    // MARK: - The map

    /// Shows a newly built million map: its buffers once, for the session.
    func load(_ next: GraphPerfMillionMap) {
        guard let made = GraphPerfMillionStatics(device: device, map: next) else { return }
        var fresh: [GraphPerfMillionSlot] = []
        for _ in 0..<Self.slotCount {
            guard let slot = GraphPerfMillionSlot(device: device, map: next) else { return }
            fresh.append(slot)
        }
        // the plan being made and the frames still on the GPU finish with the old map first
        planAhead.wait()
        for _ in 0..<Self.slotCount { inFlight.wait() }
        map = next
        statics = made
        slots = fresh
        state = GraphPerfMillionState(planner: GraphPerfChunkPlanner(octree: next.octree, bundles: next.bundles))
        budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp)
        exposure = GraphPerfExposure()
        selected = nil
        focus = nil
        focusMotion = GraphPerfFocusMotion()
        focusSlot = nil
        focusReachSlot = nil
        pull = 1
        bundlesShown = -1
        for _ in 0..<Self.slotCount { inFlight.signal() }
    }

    // MARK: - GraphPerfEngine

    /// Frames are still needed while a shell's detail, a leaf's morph or
    /// the selection is moving.
    var isSettling: Bool {
        ramping > 0 || morphing > 0 || streaming || focusMotion.isMoving(towards: chosenSlot)
    }

    var mapBounds: GraphPerfEngineBounds? {
        guard let map else { return nil }
        return GraphPerfEngineBounds(centre: map.centre, radius: map.radius, spacing: map.spacing,
                                     bodies: map.bodyCount)
    }

    func position(_ i: Int) -> SIMD3<Float>? {
        guard let map, let s = map.slot(ofBody: i) else { return nil }
        return laidOut(s) ?? map.position(i)
    }

    func clusterBall(_ s: Int) -> SIMD4<Float>? { map?.cellBall(s) }

    func title(_ i: Int) -> String { map?.title(i) ?? "" }

    func setMask(_ mask: [Bool]?) {}

    /// The depth band in force (the Graphics level's, or Increase Contrast's).
    var band: GraphPerfDepthBand { GraphPerfDepthBand.of(tier, contrast: contrast) }

    /// A slot where the GPU layout put it (the shared buffer's numbers).
    private func laidOut(_ s: Int) -> SIMD3<Float>? {
        guard let map, let statics, s >= 0 && s < map.bodyCount else { return nil }
        let packed = statics.packed.contents().assumingMemoryBound(to: UInt16.self)
        return GraphPerfMillionMap.unpack(UnsafePointer(packed), slot: s, boxes: map.leafBoxes)
    }

    func pick(_ point: CGPoint, reach: Float, width: Float, height: Float) -> GraphPerfHit? {
        guard let map, let statics, let state else { return nil }
        planAhead.wait()
        let packed = UnsafePointer(statics.packed.contents().assumingMemoryBound(to: UInt16.self))
        let boxes = map.leafBoxes
        return map.pick(x: Float(point.x), y: Float(point.y), reach: reach, frame: state.planner.frame,
                        camera: camera, width: width, height: height, focus: focusMotion.shown,
                        at: { GraphPerfMillionMap.unpack(packed, slot: $0, boxes: boxes) })
    }

    /// Forget the frame clock (the view paused and comes back).
    func resumeClock() {
        lastTime = 0
        lastMeasure = 0
        lastCamera = nil
        intervals.removeAll(keepingCapacity: true)
        recentIntervals.removeAll(keepingCapacity: true)
        statsTime = 0
    }

    /// The chosen note's slot.
    private var chosenSlot: Int? {
        guard let map, let selected else { return nil }
        return map.slot(ofBody: selected)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// The light texture, `lightScale` of the drawable a side.
    private func lightTarget(width: Int, height: Int) -> MTLTexture? {
        let w = max(Int((Float(width) * GraphPerfMillionShaders.lightScale).rounded(.up)), 1)
        let h = max(Int((Float(height) * GraphPerfMillionShaders.lightScale).rounded(.up)), 1)
        if let light, light.width == w, light.height == h { return light }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.lightFormat, width: w, height: h,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        light = device.makeTexture(descriptor: d)
        return light
    }

    /// The longest of a slot's drawn links (world), the focus's reach.
    private func reach(of s: Int, map: GraphPerfMillionMap) -> Float {
        guard let from = laidOut(s) else { return 1 }
        var longest: Float = 0
        for n in map.neighbours(ofSlot: s).prefix(GraphPerfFocusLook.most) {
            guard let to = laidOut(Int(n)) else { continue }
            let d = to - from
            longest = max(longest, (d * d).sum().squareRoot())
        }
        return max(longest, map.spacing * 0.1)
    }

    func draw(in view: MTKView) {
        let now: CFTimeInterval = CACurrentMediaTime()
        let interval: Double? = lastTime > 0 ? now - lastTime : nil
        let step: Double = min(interval ?? 1.0 / Double(screenFPS), 0.25)
        if let interval {
            intervals.append(interval)
            recentIntervals.append(interval)
            // 3 s of them
            var span = recentIntervals.reduce(0, +)
            var drop = 0
            while span > 3, drop < recentIntervals.count {
                span -= recentIntervals[drop]
                drop += 1
            }
            if drop > 0 { recentIntervals.removeFirst(drop) }
        }
        lastTime = now
        beforeFrame?(step)
        guard let map, let statics, let state, slots.count == Self.slotCount else { return }
        let started: CFTimeInterval = CACurrentMediaTime()
        let size: CGSize = view.bounds.size
        let width = Float(max(size.width, 1)), height = Float(max(size.height, 1))
        let seconds = Float(step)

        // where the view is heading, for the guard band (smoothed)
        if let last = lastCamera {
            let raw = GraphPerfGuardBand.motion(from: last, to: camera, seconds: seconds, aspect: width / height)
            motion = motion * 0.6 + raw * 0.4
        }
        lastCamera = camera
        // the depth band: the Graphics level's, as far as the budget allows (eased)
        pull += (budget.pull - pull) * (1 - exp(-seconds / Self.pullSeconds))
        if abs(pull - budget.pull) < 1e-3 { pull = budget.pull }
        let range = camera.depthRange(centre: map.centre, radius: map.radius)
        let here = GraphPerfChunkView(camera: camera, width: width, height: height, near: range.near, far: range.far,
                                      motion: motion, band: depthFade ? band : nil, pull: pull)

        // plan: the one made a frame ahead on the planning thread (from the
        // last frame's view; the guard band covers the motion), or now
        let frame: GraphPerfChunkFrame
        let planned: Double
        if let ahead = planAhead.finish(for: state) {
            frame = ahead.frame
            planned = ahead.seconds
        } else {
            let planStart: CFTimeInterval = CACurrentMediaTime()
            state.planner.advance(seconds: seconds)
            frame = state.planner.plan(here, settings: budget.settings)
            planned = CACurrentMediaTime() - planStart
        }
        let planWait: Double = planAhead.waited
        ramping = frame.ramping
        morphing = frame.morphing

        // the selection: its neighbourhood's leaves at full detail, first
        // in the queue (D4); its links grow while the rest steps back
        let chosen = chosenSlot
        if chosen != focusSlot {
            focusSlot = chosen
            state.planner.setFocus(leaves: chosen.map { map.focusLeaves(ofSlot: $0) } ?? [])
        }
        focusMotion.step(towards: chosen, seconds: seconds, reduceMotion: reduceMotion)
        let shown = focusMotion.shown
        if let shown, shown != focusReachSlot {
            focusReachSlot = shown
            focusReach = reach(of: shown, map: map)
        }
        let focusLinks = shown.map { min(map.degree(ofSlot: $0), GraphPerfFocusLook.most) } ?? 0
        let drawnFocus = GraphPerfMillionShaders.Focus(slot: shown, links: focusLinks, grow: focusMotion.grow,
                                                       reach: focusReach, dim: focusMotion.dim)

        // stream: the wanted leaves, the selection's and then the crisp and
        // big first, within the budget
        frameNumber += 1
        streamer.bodyBudget = budget.bodyBudget
        let octree = map.octree
        var jobs = streamer.plan(wanted: frame.wanted, isPrepared: { state.planner.isPrepared($0) },
                                 bodies: { Int(octree.cells[Int(octree.leafCell[$0])].count) })
        if jobs.count > Self.maxJobs { jobs.removeLast(jobs.count - Self.maxJobs) }
        for leaf in jobs { state.planner.setPrepared(leaf, true) }
        streaming = !jobs.isEmpty

        // this slot, once the GPU is done with it; what it measured sets the exposure
        let waitStart: CFTimeInterval = CACurrentMediaTime()
        inFlight.wait()
        let waited: CFTimeInterval = CACurrentMediaTime() - waitStart
        let slot: GraphPerfMillionSlot = slots[frameNumber % Self.slotCount]
        if slot.measured {
            let since: Double = lastMeasure > 0 ? now - lastMeasure : 1.0 / Double(max(screenFPS, 1))
            lastMeasure = now
            let samples = UnsafeBufferPointer(start: slot.samples.contents().assumingMemoryBound(to: Float.self),
                                              count: 2 * GraphPerfMillionShaders.measureGrid
                                                  * GraphPerfMillionShaders.measureGrid)
            exposure.update(samples: samples, seconds: since)
            if exposure.saturated >= 0 { saturations.append(exposure.saturated) }
            slot.measured = false
        }
        slot.write(frame)
        let jobCount = slot.writeJobs(jobs, octree: octree)

        guard let commands = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        var calls = 0

        // the GPU layout of the leaves prepared this frame, before they are
        // drawn: one dispatch a step over all of them
        if jobCount.jobs > 0, let compute = commands.makeComputeCommandEncoder() {
            compute.setComputePipelineState(layoutPipeline)
            compute.setBuffer(slot.jobs, offset: 0, index: GraphPerfMillionShaders.LayoutSlot.jobs)
            compute.setBuffer(statics.packed, offset: 0, index: GraphPerfMillionShaders.LayoutSlot.packed)
            compute.setBuffer(statics.seed, offset: 0, index: GraphPerfMillionShaders.LayoutSlot.seed)
            compute.setBuffer(statics.boxes, offset: 0, index: GraphPerfMillionShaders.LayoutSlot.boxes)
            compute.setBuffer(statics.adjacencyStart, offset: 0,
                              index: GraphPerfMillionShaders.LayoutSlot.adjacencyStart)
            compute.setBuffer(statics.adjacency, offset: 0, index: GraphPerfMillionShaders.LayoutSlot.adjacency)
            var params = SIMD4<Float>(GraphPerfMillionShaders.layoutPull, GraphPerfMillionShaders.layoutAnchor,
                                      GraphPerfMillionShaders.layoutReach * map.spacing, 0)
            compute.setBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride,
                             index: GraphPerfMillionShaders.LayoutSlot.params)
            var count = SIMD2<UInt32>(UInt32(jobCount.jobs), UInt32(jobCount.threads))
            compute.setBytes(&count, length: MemoryLayout<SIMD2<UInt32>>.stride,
                             index: GraphPerfMillionShaders.LayoutSlot.count)
            let wide = min(layoutPipeline.maxTotalThreadsPerThreadgroup, 64)
            let groups = (jobCount.threads + wide - 1) / wide
            for _ in 0..<GraphPerfMillionShaders.layoutSteps {
                compute.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                             threadsPerThreadgroup: MTLSize(width: wide, height: 1, depth: 1))
                calls += 1
            }
            compute.endEncoding()
        }

        // the drawable: on a busy screen (or the simulator) a wait for the
        // compositor, not the map's work, so it is not counted as the CPU's
        let drawableStart: CFTimeInterval = CACurrentMediaTime()
        let passOrNil: MTLRenderPassDescriptor? = view.currentRenderPassDescriptor
        let drawableOrNil: CAMetalDrawable? = view.currentDrawable
        let drawableWait: CFTimeInterval = CACurrentMediaTime() - drawableStart
        let done: DispatchSemaphore = inFlight
        guard let screenPass = passOrNil, let drawable = drawableOrNil,
              let lightTexture = lightTarget(width: drawable.texture.width, height: drawable.texture.height),
              let farCommands = queue.makeCommandBuffer(),
              let screenCommands = queue.makeCommandBuffer() else {
            commands.addCompletedHandler { _ in done.signal() }
            commands.commit()
            return
        }
        let timing = stageClock.time(near: commands, far: farCommands, screen: screenCommands)

        // the bundles drawn: the budget's count, eased, the last few narrowing away
        let bundleCount = min(statics.bundleCount, GraphPerfMillionShaders.bundleCap)
        let bundleTarget = Float(budget.bundleLimit(bundleCount))
        if bundlesShown < 0 { bundlesShown = bundleTarget }
        bundlesShown += (bundleTarget - bundlesShown) * (1 - exp(-seconds / Self.bundleSeconds))
        if abs(bundlesShown - bundleTarget) < 0.05 { bundlesShown = bundleTarget }
        let bundleRamp = GraphPerfMillionShaders.bundleRamp(limit: bundlesShown)
        drawnBundles = min(Int((bundlesShown + bundleRamp).rounded(.up)), bundleCount)

        let numbers: [SIMD4<Float>] = GraphPerfMillionShaders.frame(
            camera: camera, width: width, height: height, near: here.near, far: here.far, tier: tier, bold: bold,
            focus: drawnFocus, fade: here.fade, bundleLimit: bundlesShown, sky: GraphPerfScene.background,
            pixelsPerPoint: Float(view.contentScaleFactor), time: Float(now - startTime))
        typealias S = GraphPerfMillionShaders.Slot
        var drawCount = UInt32(frame.drawLeaves.count / 2)
        func bind(_ encoder: MTLRenderCommandEncoder) {
            numbers.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    encoder.setVertexBytes(base, length: raw.count, index: S.frame)
                    encoder.setFragmentBytes(base, length: raw.count, index: S.frame)
                }
            }
            encoder.setVertexBuffer(statics.packed, offset: 0, index: S.packed)
            encoder.setVertexBuffer(statics.looks, offset: 0, index: S.looks)
            encoder.setVertexBuffer(statics.boxes, offset: 0, index: S.boxes)
            encoder.setVertexBuffer(slot.standIn, offset: 0, index: S.standIn)
            encoder.setVertexBuffer(slot.drawLeaves, offset: 0, index: S.drawLeaves)
            encoder.setVertexBytes(&drawCount, length: MemoryLayout<UInt32>.stride, index: S.drawCount)
            encoder.setVertexBuffer(statics.adjacencyStart, offset: 0, index: S.adjacencyStart)
            encoder.setVertexBuffer(statics.adjacency, offset: 0, index: S.adjacency)
            encoder.setVertexBuffer(statics.bundleEnds, offset: 0, index: S.bundleEnds)
            encoder.setVertexBuffer(statics.bundleWeights, offset: 0, index: S.bundleWeights)
            encoder.setVertexBuffer(slot.bundleCells, offset: 0, index: S.bundleCells)
            encoder.setVertexBuffer(statics.cutColours, offset: 0, index: S.cutColours)
            encoder.setVertexBuffer(slot.summaries, offset: 0, index: S.summaries)
            encoder.setVertexBuffer(statics.cutWeights, offset: 0, index: S.cutWeights)
            encoder.setVertexBuffer(slot.leafDetail, offset: 0, index: S.leafDetail)
        }

        // two light passes, each its own command buffer so the GPU times
        // each stage: near (the layout above) and far (bundles, glows: what
        // the bundle share trims) add light into the half-float texture;
        // the screen pass tone-maps it and draws the notes over it
        let lightPass = MTLRenderPassDescriptor()
        lightPass.colorAttachments[0].texture = lightTexture
        lightPass.colorAttachments[0].loadAction = .clear
        lightPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        lightPass.colorAttachments[0].storeAction = .store
        stageClock.committed(timing)
        commands.commit()

        if let farEncoder = farCommands.makeRenderCommandEncoder(descriptor: lightPass) {
            bind(farEncoder)
            if drawnBundles > 0 {
                farEncoder.setRenderPipelineState(bundlePipeline)
                farEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                          instanceCount: drawnBundles)
                calls += 1
            }
            if frame.summaryCount > 0 {
                farEncoder.setRenderPipelineState(summaryPipeline)
                farEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                          instanceCount: frame.summaryCount)
                calls += 1
            }
            farEncoder.endEncoding()
        }
        farCommands.commit()

        // the screen: every pixel is the resolve's, then the notes on a
        // fresh depth, the chosen neighbourhood over them, the chosen note
        // on top; then the measure for the next exposure and the readout
        screenPass.colorAttachments[0].loadAction = .dontCare
        screenPass.colorAttachments[0].storeAction = .store
        screenPass.depthAttachment.loadAction = .clear
        screenPass.depthAttachment.clearDepth = 1
        screenPass.depthAttachment.storeAction = .dontCare
        if let screenEncoder = screenCommands.makeRenderCommandEncoder(descriptor: screenPass) {
            let sky = GraphPerfScene.background
            var tone = SIMD4<Float>(exposure.k, sky.x, sky.y, sky.z)
            screenEncoder.setRenderPipelineState(resolvePipeline)
            screenEncoder.setDepthStencilState(overDepth)
            screenEncoder.setFragmentTexture(lightTexture, index: GraphPerfMillionShaders.ResolveSlot.light)
            screenEncoder.setFragmentBytes(&tone, length: MemoryLayout<SIMD4<Float>>.stride,
                                           index: GraphPerfMillionShaders.ResolveSlot.tone)
            screenEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            calls += 1
            bind(screenEncoder)
            if frame.drawnBodies > 0 {
                screenEncoder.setRenderPipelineState(nodePipeline)
                screenEncoder.setDepthStencilState(solidDepth)
                screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                             instanceCount: frame.drawnBodies)
                calls += 1
            }
            if shown != nil {
                if focusLinks > 0 {
                    screenEncoder.setRenderPipelineState(focusLinkPipeline)
                    screenEncoder.setDepthStencilState(overDepth)
                    screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                                 instanceCount: focusLinks)
                    screenEncoder.setRenderPipelineState(focusNodePipeline)
                    screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                                 instanceCount: focusLinks)
                    calls += 2
                }
                screenEncoder.setRenderPipelineState(chosenPipeline)
                screenEncoder.setDepthStencilState(overDepth)
                screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                calls += 1
            }
            screenEncoder.endEncoding()
        }
        if !view.framebufferOnly, let measure = screenCommands.makeComputeCommandEncoder() {
            let grid = GraphPerfMillionShaders.measureGrid
            measure.setComputePipelineState(measurePipeline)
            measure.setTexture(lightTexture, index: GraphPerfMillionShaders.ResolveSlot.light)
            measure.setTexture(drawable.texture, index: GraphPerfMillionShaders.ResolveSlot.screen)
            measure.setBuffer(slot.samples, offset: 0, index: GraphPerfMillionShaders.ResolveSlot.samples)
            let side = 8
            measure.dispatchThreadgroups(MTLSize(width: (grid + side - 1) / side, height: (grid + side - 1) / side, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: side, height: side, depth: 1))
            measure.endEncoding()
            calls += 1
            slot.measured = true
        }
        screenCommands.present(drawable)
        screenCommands.addCompletedHandler { _ in done.signal() }
        screenCommands.commit()

        // the next frame's plan, on the planning thread, while this one is drawn
        planAhead.start(state, view: here, settings: budget.settings, step: seconds)

        // the CPU's own time: not the waits for a slot the GPU still had, for
        // a drawable, or for the planning thread; the planning runs beside it,
        // so the CPU stage is the longer of the two
        let cpu = max(CACurrentMediaTime() - started - waited - drawableWait - planWait, 0)
        cpuTimes.append(cpu)
        planTimes.append(planned)
        let gpu = stageClock.latest
        budget.record(GraphPerfFrameStages(cpu: max(cpu, planned), near: gpu.near, far: gpu.far, plan: planned),
                      interval: interval)
        drawCalls = calls
        let memory = device.currentAllocatedSize
        memoryPeak = max(memoryPeak, memory)
        let instances = frame.drawnBodies + frame.summaryCount + drawnBundles + (shown != nil ? 2 * focusLinks + 1 : 0)
        onFrame?(GraphPerfFrameReport(interval: interval ?? step, cpu: max(cpu, planned),
                                      gpu: (gpu.near ?? 0) + (gpu.far ?? 0), drawCalls: calls, instances: instances,
                                      gpuMemory: memory, ramping: frame.ramping, shells: frame.shellCounts))
        report(now: now, map: map, frame: frame)
    }

    /// Twice a second: the readout's numbers.
    private func report(now: CFTimeInterval, map: GraphPerfMillionMap, frame: GraphPerfChunkFrame) {
        if statsTime == 0 { statsTime = now }
        guard now - statsTime >= 0.5 else { return }
        var stats = GraphPerfStats()
        stats.notes = map.scene.graph.noteCount
        stats.links = map.linkCount
        stats.drawnBodies = frame.drawnBodies
        stats.drawnGlows = frame.summaryCount
        stats.drawnLines = drawnBundles + (focusMotion.shown != nil ? min(map.degree(ofSlot: focusMotion.shown ?? 0),
                                                                          GraphPerfFocusLook.most) : 0)
        // the median and 5th percentile over the last 3 s, a fifth of a
        // second at a time, and the 1% low (the slowest hundredth's rate)
        let rates = GraphPerfStats.rates(recentIntervals, group: max(screenFPS / 5, 1))
        let total: Double = intervals.reduce(0, +)
        stats.fps = rates.median > 0 ? rates.median : (total > 0 ? Double(intervals.count) / total : 0)
        stats.fpsLow = rates.low
        stats.fpsOnePercent = GraphPerfStats.onePercentLow(recentIntervals)
        stats.screenFPS = screenFPS
        let gpu = gpuClock.drain()
        let stages = stageClock.drain()
        stats.cpuMedian = GraphPerfStats.median(cpuTimes)
        stats.planMedian = GraphPerfStats.median(planTimes)
        stats.nearMedian = GraphPerfStats.median(stages.near)
        stats.farMedian = GraphPerfStats.median(stages.far)
        // the worst of the half second, so a passing flash still shows
        stats.saturated = saturations.max() ?? -1
        let target: Double = 1.0 / Double(max(screenFPS, 1))
        stats.cpuP95 = GraphPerfFrameStats(cpuTimes, target: target).p95
        stats.gpuP95 = GraphPerfFrameStats(gpu, target: target).p95
        stats.detail = budget.split
        stats.drawCalls = drawCalls
        stats.gpuMemoryPeak = memoryPeak
        stats.shells = frame.shellCounts
        stats.fadeOn = depthFade
        stats.settling = false
        intervals.removeAll(keepingCapacity: true)
        cpuTimes.removeAll(keepingCapacity: true)
        planTimes.removeAll(keepingCapacity: true)
        saturations.removeAll(keepingCapacity: true)
        statsTime = now
        onStats?(stats)
    }
}

/// The buffers made once per million map, kept for the session.
final class GraphPerfMillionStatics {
    let packed: MTLBuffer
    let seed: MTLBuffer
    let looks: MTLBuffer
    let boxes: MTLBuffer
    let adjacencyStart: MTLBuffer
    let adjacency: MTLBuffer
    let bundleEnds: MTLBuffer
    let bundleWeights: MTLBuffer
    let cutColours: MTLBuffer
    /// Each cut cell's share of the bundle light where bundles meet.
    let cutWeights: MTLBuffer
    let bundleCount: Int

    init?(device: MTLDevice, map: GraphPerfMillionMap) {
        let colours: [UInt32] = map.bundles.cells.map { map.octree.cells[Int($0)].colour }
        guard let packed = GraphPerfStatics.buffer(device, map.packed),
              let seed = GraphPerfStatics.buffer(device, map.packed),
              let looks = GraphPerfStatics.buffer(device, map.looks),
              let boxes = GraphPerfStatics.buffer(device, map.leafBoxes),
              let adjacencyStart = GraphPerfStatics.buffer(device, map.adjacencyStart),
              let adjacency = GraphPerfStatics.buffer(device, map.adjacency),
              let bundleEnds = GraphPerfStatics.buffer(device, map.bundleEnds),
              let bundleWeights = GraphPerfStatics.buffer(device, map.bundleWeights),
              let cutColours = GraphPerfStatics.buffer(device, colours),
              let cutWeights = GraphPerfStatics.buffer(device, map.bundleShares) else {
            return nil
        }
        self.packed = packed
        self.seed = seed
        self.looks = looks
        self.boxes = boxes
        self.adjacencyStart = adjacencyStart
        self.adjacency = adjacency
        self.bundleEnds = bundleEnds
        self.bundleWeights = bundleWeights
        self.cutColours = cutColours
        self.cutWeights = cutWeights
        bundleCount = map.bundles.count
    }
}

/// One frame slot: the planner's arrays as the GPU reads them.
final class GraphPerfMillionSlot {
    let standIn: MTLBuffer
    let drawLeaves: MTLBuffer
    let summaries: MTLBuffer
    let bundleCells: MTLBuffer
    let leafDetail: MTLBuffer
    /// The layout's jobs: first slot, count, leaf, the threads before it.
    let jobs: MTLBuffer
    /// The measure kernel's grid: (light, screen) luminance pairs.
    let samples: MTLBuffer
    /// The GPU wrote `samples` for the frame that last used this slot.
    var measured = false

    init?(device: MTLDevice, map: GraphPerfMillionMap) {
        func make(_ bytes: Int) -> MTLBuffer? { device.makeBuffer(length: max(bytes, 16), options: .storageModeShared) }
        let leaves = map.octree.leafCount
        guard let standIn = make(leaves * 16),
              let drawLeaves = make(leaves * 8),
              let summaries = make(map.octree.cells.count * 32),
              let bundleCells = make(map.bundles.cells.count * 16),
              let leafDetail = make(leaves * 4),
              let jobs = make(GraphPerfMillionRenderer.maxJobs * 16),
              let samples = make(GraphPerfMillionShaders.measureGrid * GraphPerfMillionShaders.measureGrid * 8) else {
            return nil
        }
        self.standIn = standIn
        self.drawLeaves = drawLeaves
        self.summaries = summaries
        self.bundleCells = bundleCells
        self.leafDetail = leafDetail
        self.jobs = jobs
        self.samples = samples
    }

    /// Writes this frame's plan.
    func write(_ frame: GraphPerfChunkFrame) {
        GraphPerfSlot.copy(frame.standIn, into: standIn)
        GraphPerfSlot.copy(frame.drawLeaves, into: drawLeaves)
        GraphPerfSlot.copy(frame.summaries, into: summaries)
        GraphPerfSlot.copy(frame.bundleCells, into: bundleCells)
        GraphPerfSlot.copy(frame.leafDetail, into: leafDetail)
    }

    /// Writes the layout's jobs for `leaves`; returns how many, and the threads they need.
    func writeJobs(_ leaves: [Int], octree: GraphPerfOctree) -> (jobs: Int, threads: Int) {
        let out = jobs.contents().assumingMemoryBound(to: SIMD4<UInt32>.self)
        let room = jobs.length / 16
        var n = 0, threads = 0
        for leaf in leaves where n < room {
            let cell = octree.cells[Int(octree.leafCell[leaf])]
            guard cell.count > 0 else { continue }
            out[n] = SIMD4(UInt32(cell.first), UInt32(cell.count), UInt32(leaf), UInt32(threads))
            threads += Int(cell.count)
            n += 1
        }
        return (n, threads)
    }
}

#endif
