// The million map's Metal renderer (plans 4b, 4c, 4e): a million bodies and
// their links at the screen's own rate.
//
// - Everything coarse stays on the GPU for the whole session (about 40 MB
//   for a million): every body's 16-bit position with its leaf, its seed,
//   colour and size, each leaf's box, the links' adjacency, and the bundles.
//   "Loading" is only choosing detail: no disk, no waiting.
// - Each frame is planned from the octree's few thousand cells, never the
//   million bodies (GraphPerfChunkPlanner: culling, morphs, the guard band),
//   on a planning thread a frame ahead (GraphPerfPlanAhead), so the plan is
//   off the main thread's frame even in an unoptimised Playgrounds build.
// - Links, bundles and summary glows add up as light in a half-float
//   texture; the screen shows it through a tone curve whose exposure follows
//   the picture's own 97th percentile (GraphPerfExposure), and the notes are
//   drawn over it in their own colours, so crowded light reads as structure
//   and notes stay shapes. A 64 x 64 grid measured on the GPU feeds the
//   exposure and the readout's share of the screen at 250+.
// - Leaves about to open, nearest first and ahead of the camera's motion,
//   are prepared within the frame's budget (GraphPerfStreamer): their links
//   copied into a fixed pool of pages (GraphPerfChunkCache, least recently
//   used first out) and the leaf laid out by the GPU (mil_layout) in the
//   same command buffer, before it is drawn.
// - The frame budget (GraphPerfFrameBudget) reads each frame's CPU time and,
//   when the GPU reports them, the GPU times of its stages (near: notes and
//   links, with the screen pass; far: bundles and glows), and trims
//   the stage that took the time - the split for the near one, the bundles
//   drawn (lightest first) for the far one - never the frame rate, which is
//   the screen's own.
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
/// the near stage (layout, the notes' depth, links) and the far stage
/// (bundles, glows) add light; the screen stage tone-maps it and draws the
/// notes over it. The screen stage scales with the notes drawn, so it counts
/// as near. When a frame's screen stage is done, its near and far go to the
/// lists and their sum to `total`.
final class GraphPerfStageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var nearTimes: [Double] = []
    private var farTimes: [Double] = []
    private var latestNear: Double?
    private var latestFar: Double?
    private var pendingNear: Double = 0
    private var pendingFar: Double = 0
    private let total: GraphPerfGPUClock

    init(total: GraphPerfGPUClock) {
        self.total = total
    }

    private func usable(_ seconds: Double) -> Double? {
        seconds.isFinite && seconds >= 0 && seconds < 1 ? seconds : nil
    }

    private func add(near seconds: Double) {
        lock.lock()
        pendingNear = usable(seconds) ?? 0
        lock.unlock()
    }

    private func add(far seconds: Double) {
        lock.lock()
        pendingFar = usable(seconds) ?? 0
        lock.unlock()
    }

    private func add(screen seconds: Double) {
        lock.lock()
        let near = pendingNear + (usable(seconds) ?? 0)
        let far = pendingFar
        nearTimes.append(near)
        farTimes.append(far)
        latestNear = near
        latestFar = far
        pendingNear = 0
        pendingFar = 0
        lock.unlock()
        total.add(near + far)
    }

    func timeNear(_ commands: MTLCommandBuffer) {
        commands.addCompletedHandler { [self] done in
            self.add(near: done.gpuEndTime - done.gpuStartTime)
        }
    }

    func timeFar(_ commands: MTLCommandBuffer) {
        commands.addCompletedHandler { [self] done in
            self.add(far: done.gpuEndTime - done.gpuStartTime)
        }
    }

    func timeScreen(_ commands: MTLCommandBuffer) {
        commands.addCompletedHandler { [self] done in
            self.add(screen: done.gpuEndTime - done.gpuStartTime)
        }
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

    let device: MTLDevice
    private let queue: MTLCommandQueue
    /// Notes in their own colours, on the screen.
    private let nodePipeline: MTLRenderPipelineState
    private let chosenPipeline: MTLRenderPipelineState
    /// Notes' depth only, in the light pass, so links behind a note are hidden.
    private let nodeDepthPipeline: MTLRenderPipelineState
    /// Light: links, bundles and glows add into the light texture.
    private let linkPipeline: MTLRenderPipelineState
    private let bundlePipeline: MTLRenderPipelineState
    private let summaryPipeline: MTLRenderPipelineState
    /// The tone curve, light to screen.
    private let resolvePipeline: MTLRenderPipelineState
    private let layoutPipeline: MTLComputePipelineState
    private let measurePipeline: MTLComputePipelineState
    private let solidDepth: MTLDepthStencilState
    private let glassDepth: MTLDepthStencilState
    private let overDepth: MTLDepthStencilState
    private let inFlight = DispatchSemaphore(value: GraphPerfMillionRenderer.slotCount)
    private let gpuClock = GraphPerfGPUClock()
    private lazy var stageClock = GraphPerfStageClock(total: gpuClock)
    private let planAhead = GraphPerfPlanAhead()

    private(set) var map: GraphPerfMillionMap?
    private var statics: GraphPerfMillionStatics?
    private var slots: [GraphPerfMillionSlot] = []
    /// The planner and the cache, mutated in place each frame (between
    /// frames by the planning thread).
    private var state: GraphPerfMillionState?
    private var streamer = GraphPerfStreamer()
    private(set) var budget: GraphPerfFrameBudget
    private var exposure = GraphPerfExposure()
    private var light: MTLTexture?
    private var frameNumber: Int = 0
    private let linkPages: Int

    // what the map view sets
    var camera = GraphPerfCamera()
    var tier: GraphPerfTier = .high {
        didSet { if tier != oldValue { budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp) } }
    }
    var bold: Bool = false
    var selected: Int?
    var focus: Int?
    var screenFPS: Int = 60 {
        didSet { if screenFPS != oldValue { budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp) } }
    }
    var beforeFrame: ((Double) -> Void)?
    var onStats: ((GraphPerfStats) -> Void)?

    // motion for the guard band, pacing and the readout
    private var lastCamera: GraphPerfCamera?
    private var motion = SIMD2<Float>(0, 0)
    private var lastTime: CFTimeInterval = 0
    private var lastMeasure: CFTimeInterval = 0
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var intervals: [Double] = []
    private var cpuTimes: [Double] = []
    private var planTimes: [Double] = []
    private var saturations: [Double] = []
    private var drawnBundles: Int = 0
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
        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat, additive: Bool,
                      colour writes: Bool = true) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                NSLog("GraphPerfMillion: no function %@ or %@", vertex, fragment)
                return nil
            }
            d.vertexFunction = v
            d.fragmentFunction = f
            d.depthAttachmentPixelFormat = depthFormat
            d.rasterSampleCount = view.sampleCount
            guard let colour = d.colorAttachments[0] else { return nil }
            colour.pixelFormat = format
            if !writes { colour.writeMask = [] }
            if additive {
                colour.isBlendingEnabled = true
                colour.rgbBlendOperation = .add
                colour.alphaBlendOperation = .add
                colour.sourceRGBBlendFactor = .one
                colour.destinationRGBBlendFactor = .one
                colour.sourceAlphaBlendFactor = .zero
                colour.destinationAlphaBlendFactor = .one
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
        guard let node = pipeline("mil_node_vertex", "mil_node_fragment", format: screenFormat, additive: false),
              let chosen = pipeline("mil_chosen_vertex", "mil_node_fragment", format: screenFormat, additive: false),
              let nodeDepth = pipeline("mil_node_vertex", "mil_node_fragment", format: lightFormat, additive: false,
                                       colour: false),
              let link = pipeline("mil_link_vertex", "mil_line_fragment", format: lightFormat, additive: true),
              let bundle = pipeline("mil_bundle_vertex", "mil_line_fragment", format: lightFormat, additive: true),
              let summary = pipeline("mil_summary_vertex", "mil_summary_fragment", format: lightFormat, additive: true),
              let resolve = pipeline("mil_resolve_vertex", "mil_resolve_fragment", format: screenFormat, additive: false),
              let layout = compute("mil_layout"),
              let measure = compute("mil_measure"),
              let solid = depth(.less, write: true),
              let glass = depth(.lessEqual, write: false),
              let over = depth(.always, write: false) else {
            return nil
        }
        self.device = device
        self.queue = queue
        nodePipeline = node
        chosenPipeline = chosen
        nodeDepthPipeline = nodeDepth
        linkPipeline = link
        bundlePipeline = bundle
        summaryPipeline = summary
        resolvePipeline = resolve
        layoutPipeline = layout
        measurePipeline = measure
        solidDepth = solid
        glassDepth = glass
        overDepth = over
        linkPages = GraphPerfMemoryBudget.linkPages(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        budget = GraphPerfFrameBudget(screenFPS: 60)
        super.init()
    }

    // MARK: - The map

    /// Shows a newly built million map: its buffers once, for the session.
    func load(_ next: GraphPerfMillionMap) {
        guard let made = GraphPerfMillionStatics(device: device, map: next, linkPages: linkPages) else { return }
        var fresh: [GraphPerfMillionSlot] = []
        for _ in 0..<Self.slotCount {
            guard let slot = GraphPerfMillionSlot(device: device, map: next, linkPages: linkPages) else { return }
            fresh.append(slot)
        }
        // the plan being made and the frames still on the GPU finish with the old map first
        planAhead.wait()
        for _ in 0..<Self.slotCount { inFlight.wait() }
        map = next
        statics = made
        slots = fresh
        state = GraphPerfMillionState(
            planner: GraphPerfChunkPlanner(octree: next.octree, bundles: next.bundles),
            cache: GraphPerfChunkCache(leaves: next.octree.leafCount, pageCount: linkPages,
                                       pageSize: GraphPerfMillionShaders.pageSize))
        budget = GraphPerfFrameBudget(screenFPS: screenFPS, tier: tier, warmUp: GraphPerfFrameBudget.warmUp)
        exposure = GraphPerfExposure()
        selected = nil
        focus = nil
        for _ in 0..<Self.slotCount { inFlight.signal() }
    }

    // MARK: - GraphPerfEngine

    var isSettling: Bool { false }

    var mapBounds: GraphPerfEngineBounds? {
        guard let map else { return nil }
        return GraphPerfEngineBounds(centre: map.centre, radius: map.radius, spacing: map.spacing,
                                     bodies: map.bodyCount)
    }

    func position(_ i: Int) -> SIMD3<Float>? { map?.position(i) }

    func clusterBall(_ s: Int) -> SIMD4<Float>? { map?.cellBall(s) }

    func title(_ i: Int) -> String { map?.title(i) ?? "" }

    func setMask(_ mask: [Bool]?) {}

    func pick(_ point: CGPoint, reach: Float, width: Float, height: Float) -> GraphPerfHit? {
        guard let map, let state else { return nil }
        planAhead.wait()
        return map.pick(x: Float(point.x), y: Float(point.y), reach: reach, frame: state.planner.frame, camera: camera,
                        width: width, height: height)
    }

    /// Forget the frame clock (the view paused and comes back).
    func resumeClock() {
        lastTime = 0
        lastMeasure = 0
        lastCamera = nil
        intervals.removeAll(keepingCapacity: true)
        statsTime = 0
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// The light texture, the drawable's size.
    private func lightTarget(width: Int, height: Int) -> MTLTexture? {
        if let light, light.width == width, light.height == height { return light }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.lightFormat, width: max(width, 1),
                                                         height: max(height, 1), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        light = device.makeTexture(descriptor: d)
        return light
    }

    func draw(in view: MTKView) {
        let now: CFTimeInterval = CACurrentMediaTime()
        let interval: Double? = lastTime > 0 ? now - lastTime : nil
        let step: Double = min(interval ?? 1.0 / Double(screenFPS), 0.25)
        if let interval { intervals.append(interval) }
        lastTime = now
        beforeFrame?(step)
        guard let map, let statics, let state, slots.count == Self.slotCount else { return }
        let started: CFTimeInterval = CACurrentMediaTime()
        let size: CGSize = view.bounds.size
        let width = Float(max(size.width, 1)), height = Float(max(size.height, 1))

        // where the view is heading, for the guard band (smoothed)
        if let last = lastCamera {
            let raw = GraphPerfGuardBand.motion(from: last, to: camera, seconds: Float(step), aspect: width / height)
            motion = motion * 0.6 + raw * 0.4
        }
        lastCamera = camera
        let range = camera.depthRange(centre: map.centre, radius: map.radius)
        let here = GraphPerfChunkView(camera: camera, width: width, height: height, near: range.near, far: range.far,
                                      motion: motion)

        // plan: the one made a frame ahead on the planning thread (from the
        // last frame's view; the guard band covers the motion), or now
        let frame: GraphPerfChunkFrame
        let planned: Double
        if let ahead = planAhead.finish(for: state) {
            frame = ahead.frame
            planned = ahead.seconds
        } else {
            let planStart: CFTimeInterval = CACurrentMediaTime()
            state.planner.advance(seconds: Float(step))
            frame = state.planner.plan(here, settings: budget.settings)
            planned = CACurrentMediaTime() - planStart
        }
        let planWait: Double = planAhead.waited

        // stream: the wanted leaves, nearest first, within the budget
        frameNumber += 1
        streamer.linkBudget = budget.linkBudget
        streamer.bodyBudget = budget.bodyBudget
        let octree = map.octree
        let streamed = streamer.plan(wanted: frame.wanted, cache: &state.cache, links: map.links,
                                     bodies: { Int(octree.cells[Int(octree.leafCell[$0])].count) }, frame: frameNumber)
        for gone in streamed.evicted { state.planner.setPrepared(gone, false) }
        for job in streamed.jobs {
            statics.write(links: map.links, leaf: job.leaf, pages: job.pages)
            state.planner.setPrepared(job.leaf, true)
        }

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
        let (pageCount, linkEntries) = slot.write(frame, cache: state.cache, links: map.links)

        guard let commands = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }

        // the GPU layout of the leaves prepared this frame, before they are drawn
        if !streamed.jobs.isEmpty, let compute = commands.makeComputeCommandEncoder() {
            compute.setComputePipelineState(layoutPipeline)
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
            let wide = min(layoutPipeline.maxTotalThreadsPerThreadgroup, 64)
            for _ in 0..<GraphPerfMillionShaders.layoutSteps {
                for job in streamed.jobs {
                    let cell = octree.cells[Int(octree.leafCell[job.leaf])]
                    guard cell.count > 0 else { continue }
                    var spec = SIMD4<UInt32>(UInt32(cell.first), UInt32(cell.count), UInt32(job.leaf), 0)
                    compute.setBytes(&spec, length: MemoryLayout<SIMD4<UInt32>>.stride,
                                     index: GraphPerfMillionShaders.LayoutSlot.job)
                    let groups = (Int(cell.count) + wide - 1) / wide
                    compute.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                                 threadsPerThreadgroup: MTLSize(width: wide, height: 1, depth: 1))
                }
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
              let depthTexture = screenPass.depthAttachment.texture,
              let lightTexture = lightTarget(width: drawable.texture.width, height: drawable.texture.height),
              let farCommands = queue.makeCommandBuffer(),
              let screenCommands = queue.makeCommandBuffer() else {
            commands.addCompletedHandler { _ in done.signal() }
            commands.commit()
            return
        }

        // three passes, each its own command buffer so the GPU times each
        // stage: near (the notes' depth, links: what the split opens) and
        // far (bundles, glows: what the bundle share trims) add light into
        // the half-float texture; the screen pass tone-maps it and draws the
        // notes over it in their own colours
        let nearPass = MTLRenderPassDescriptor()
        nearPass.colorAttachments[0].texture = lightTexture
        nearPass.colorAttachments[0].loadAction = .clear
        nearPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        nearPass.colorAttachments[0].storeAction = .store
        nearPass.depthAttachment.texture = depthTexture
        nearPass.depthAttachment.loadAction = .clear
        nearPass.depthAttachment.clearDepth = 1
        nearPass.depthAttachment.storeAction = .store
        let farPass = MTLRenderPassDescriptor()
        farPass.colorAttachments[0].texture = lightTexture
        farPass.colorAttachments[0].loadAction = .load
        farPass.colorAttachments[0].storeAction = .store
        farPass.depthAttachment.texture = depthTexture
        farPass.depthAttachment.loadAction = .load
        farPass.depthAttachment.storeAction = .dontCare
        // the screen: every pixel is the resolve's, then the notes on a fresh depth
        screenPass.colorAttachments[0].loadAction = .dontCare
        screenPass.colorAttachments[0].storeAction = .store
        screenPass.depthAttachment.loadAction = .clear
        screenPass.depthAttachment.clearDepth = 1
        screenPass.depthAttachment.storeAction = .dontCare
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: nearPass) else {
            commands.addCompletedHandler { _ in done.signal() }
            commands.commit()
            return
        }
        let chosenSlot: Int? = selected.flatMap { $0 >= 0 && $0 < map.bodyCount ? Int(octree.slotOf[$0]) : nil }
        let numbers: [SIMD4<Float>] = GraphPerfMillionShaders.frame(
            camera: camera, width: width, height: height, near: range.near, far: range.far, centre: map.centre,
            radius: map.radius, tier: tier, bold: bold, chosenSlot: chosenSlot,
            pixelsPerPoint: Float(view.contentScaleFactor), time: Float(now - startTime))
        typealias S = GraphPerfMillionShaders.Slot
        var drawCount = UInt32(frame.drawLeaves.count / 2)
        func bind(_ encoder: MTLRenderCommandEncoder) {
            numbers.withUnsafeBytes { raw in
                if let base = raw.baseAddress { encoder.setVertexBytes(base, length: raw.count, index: S.frame) }
            }
            encoder.setVertexBuffer(statics.packed, offset: 0, index: S.packed)
            encoder.setVertexBuffer(statics.looks, offset: 0, index: S.looks)
            encoder.setVertexBuffer(statics.boxes, offset: 0, index: S.boxes)
            encoder.setVertexBuffer(slot.standIn, offset: 0, index: S.standIn)
            encoder.setVertexBuffer(slot.drawLeaves, offset: 0, index: S.drawLeaves)
            encoder.setVertexBytes(&drawCount, length: MemoryLayout<UInt32>.stride, index: S.drawCount)
            encoder.setVertexBuffer(statics.pool, offset: 0, index: S.pool)
            encoder.setVertexBuffer(slot.pages, offset: 0, index: S.pages)
            encoder.setVertexBuffer(statics.bundleEnds, offset: 0, index: S.bundleEnds)
            encoder.setVertexBuffer(statics.bundleWeights, offset: 0, index: S.bundleWeights)
            encoder.setVertexBuffer(slot.bundleCells, offset: 0, index: S.bundleCells)
            encoder.setVertexBuffer(statics.cutColours, offset: 0, index: S.cutColours)
            encoder.setVertexBuffer(slot.summaries, offset: 0, index: S.summaries)
            encoder.setVertexBuffer(statics.cutWeights, offset: 0, index: S.cutWeights)
        }

        // near: the notes' depth (no colour), then the links' light behind it
        bind(encoder)
        if frame.drawnBodies > 0 {
            encoder.setRenderPipelineState(nodeDepthPipeline)
            encoder.setDepthStencilState(solidDepth)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: frame.drawnBodies)
        }
        if pageCount > 0 {
            encoder.setRenderPipelineState(linkPipeline)
            encoder.setDepthStencilState(glassDepth)
            encoder.drawPrimitives(type: .line, vertexStart: 0,
                                   vertexCount: 2 * pageCount * GraphPerfMillionShaders.pageSize)
        }
        encoder.endEncoding()
        stageClock.timeNear(commands)
        commands.commit()

        // far: the heaviest bundles the budget allows, and the glows
        if let farEncoder = farCommands.makeRenderCommandEncoder(descriptor: farPass) {
            bind(farEncoder)
            drawnBundles = budget.bundleLimit(statics.bundleCount)
            if drawnBundles > 0 {
                farEncoder.setRenderPipelineState(bundlePipeline)
                farEncoder.setDepthStencilState(glassDepth)
                farEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                          instanceCount: drawnBundles)
            }
            if frame.summaryCount > 0 {
                farEncoder.setRenderPipelineState(summaryPipeline)
                farEncoder.setDepthStencilState(glassDepth)
                farEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                          instanceCount: frame.summaryCount)
            }
            farEncoder.endEncoding()
        }
        stageClock.timeFar(farCommands)
        farCommands.commit()

        // the screen: the light through the tone curve over the sky, the
        // notes in their own colours, the chosen one on top; then the
        // measure for the next exposure and the readout
        if let screenEncoder = screenCommands.makeRenderCommandEncoder(descriptor: screenPass) {
            let sky = view.clearColor
            var tone = SIMD4<Float>(exposure.k, Float(sky.red), Float(sky.green), Float(sky.blue))
            screenEncoder.setRenderPipelineState(resolvePipeline)
            screenEncoder.setDepthStencilState(overDepth)
            screenEncoder.setFragmentTexture(lightTexture, index: GraphPerfMillionShaders.ResolveSlot.light)
            screenEncoder.setFragmentBytes(&tone, length: MemoryLayout<SIMD4<Float>>.stride,
                                           index: GraphPerfMillionShaders.ResolveSlot.tone)
            screenEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            bind(screenEncoder)
            if frame.drawnBodies > 0 {
                screenEncoder.setRenderPipelineState(nodePipeline)
                screenEncoder.setDepthStencilState(solidDepth)
                screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                             instanceCount: frame.drawnBodies)
            }
            if chosenSlot != nil {
                screenEncoder.setRenderPipelineState(chosenPipeline)
                screenEncoder.setDepthStencilState(overDepth)
                screenEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
            slot.measured = true
        }
        screenCommands.present(drawable)
        screenCommands.addCompletedHandler { _ in done.signal() }
        stageClock.timeScreen(screenCommands)
        screenCommands.commit()

        // the next frame's plan, on the planning thread, while this one is drawn
        planAhead.start(state, view: here, settings: budget.settings, step: Float(step))

        // the CPU's own time: not the waits for a slot the GPU still had, for
        // a drawable, or for the planning thread; the planning runs beside it,
        // so the CPU stage is the longer of the two
        let cpu = max(CACurrentMediaTime() - started - waited - drawableWait - planWait, 0)
        cpuTimes.append(cpu)
        planTimes.append(planned)
        let gpu = stageClock.latest
        budget.record(GraphPerfFrameStages(cpu: max(cpu, planned), near: gpu.near, far: gpu.far, plan: planned),
                      interval: interval)
        report(now: now, map: map, frame: frame, links: linkEntries)
    }

    /// Twice a second: the readout's numbers.
    private func report(now: CFTimeInterval, map: GraphPerfMillionMap, frame: GraphPerfChunkFrame, links: Int) {
        if statsTime == 0 { statsTime = now }
        guard now - statsTime >= 0.5 else { return }
        var stats = GraphPerfStats()
        stats.notes = map.scene.graph.noteCount
        stats.links = map.linkCount
        stats.drawnBodies = frame.drawnBodies
        stats.drawnGlows = frame.summaryCount
        stats.drawnLines = links + drawnBundles
        let total: Double = intervals.reduce(0, +)
        stats.fps = total > 0 ? Double(intervals.count) / total : 0
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
    /// The link pages: entries of (home slot, other slot).
    let pool: MTLBuffer
    let bundleCount: Int

    init?(device: MTLDevice, map: GraphPerfMillionMap, linkPages: Int) {
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
              let cutWeights = GraphPerfStatics.buffer(device, map.bundleShares),
              let pool = device.makeBuffer(length: max(linkPages, 1) * GraphPerfMillionShaders.pageSize * 8,
                                           options: .storageModeShared) else {
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
        self.pool = pool
        bundleCount = map.bundles.count
    }

    /// Copies a leaf's links into its pages, the rest of its last page empty.
    func write(links: GraphPerfLeafLinks, leaf: Int, pages: [Int32]) {
        let size = GraphPerfMillionShaders.pageSize
        let base = pool.contents().assumingMemoryBound(to: UInt32.self)
        let capacity = pool.length / 8
        var entry = Int(links.start[leaf])
        let end = Int(links.start[leaf + 1])
        links.pairs.withUnsafeBufferPointer { pairs in
            for page in pages {
                let first = Int(page) * size
                guard first + size <= capacity else { continue }
                let n = min(size, end - entry)
                if n > 0, let source = pairs.baseAddress {
                    (base + 2 * first).update(from: source + 2 * entry, count: 2 * n)
                }
                if n < size {
                    (base + 2 * (first + max(n, 0))).update(repeating: GraphPerfMillionShaders.emptyEntry,
                                                            count: 2 * (size - max(n, 0)))
                }
                entry += max(n, 0)
            }
        }
    }
}

/// One frame slot: the planner's arrays as the GPU reads them.
final class GraphPerfMillionSlot {
    let standIn: MTLBuffer
    let drawLeaves: MTLBuffer
    let pages: MTLBuffer
    let summaries: MTLBuffer
    let bundleCells: MTLBuffer
    /// The measure kernel's grid: (light, screen) luminance pairs.
    let samples: MTLBuffer
    /// The GPU wrote `samples` for the frame that last used this slot.
    var measured = false

    init?(device: MTLDevice, map: GraphPerfMillionMap, linkPages: Int) {
        func make(_ bytes: Int) -> MTLBuffer? { device.makeBuffer(length: max(bytes, 16), options: .storageModeShared) }
        let leaves = map.octree.leafCount
        guard let standIn = make(leaves * 16),
              let drawLeaves = make(leaves * 8),
              let pages = make(max(linkPages, 1) * 4),
              let summaries = make(map.octree.cells.count * 32),
              let bundleCells = make(map.bundles.cells.count * 16),
              let samples = make(GraphPerfMillionShaders.measureGrid * GraphPerfMillionShaders.measureGrid * 8) else {
            return nil
        }
        self.standIn = standIn
        self.drawLeaves = drawLeaves
        self.pages = pages
        self.summaries = summaries
        self.bundleCells = bundleCells
        self.samples = samples
    }

    /// Writes this frame's plan; returns how many link pages it draws, and
    /// the link entries on them.
    func write(_ frame: GraphPerfChunkFrame, cache: GraphPerfChunkCache, links: GraphPerfLeafLinks) -> (Int, Int) {
        GraphPerfSlot.copy(frame.standIn, into: standIn)
        GraphPerfSlot.copy(frame.drawLeaves, into: drawLeaves)
        GraphPerfSlot.copy(frame.summaries, into: summaries)
        GraphPerfSlot.copy(frame.bundleCells, into: bundleCells)
        // the link pages of every leaf drawn body by body
        let out = pages.contents().assumingMemoryBound(to: UInt32.self)
        let room = pages.length / 4
        var n = 0, entries = 0
        var k = 0
        while k < frame.drawLeaves.count {
            let leaf = Int(frame.drawLeaves[k])
            k += 2
            entries += links.count(leaf)
            for page in cache.pages[leaf] where n < room {
                out[n] = UInt32(page)
                n += 1
            }
        }
        return (n, entries)
    }
}

#endif
