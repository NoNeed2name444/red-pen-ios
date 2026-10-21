// The Performance map's Metal renderer: the whole map in five instanced
// draws a frame - bodies, links, bundles, glows and the chosen body - from
// buffers made once per map and per-frame buffers written in place.
//
// - Static buffers (made when a map loads): each body's colour, both ends
//   of every line, each body's cluster, each cluster's ball and colour, and
//   each bundle's ends and weight (GraphPerfScene).
// - Three frame slots, each with the bodies' positions and the draw lists
//   (GraphPerfLODPlanner). A frame waits until the GPU is done with its
//   slot (three in flight), then copies into it only what changed since
//   that slot was last written: positions while the layout settles, the
//   lists when the level of detail changes. A still map copies nothing.
// - Each frame first runs a slice of the layout (GraphPerfForce) sized to
//   about three milliseconds, so settling never costs a frame.
//
// Free of SceneKit and of Stethoscore types: GraphPerfMapView drives it,
// and only the theme's glue (GraphPerfTheme.swift) knows the app.
#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit

@MainActor
final class GraphPerfRenderer: NSObject, @preconcurrency MTKViewDelegate {
    static let slotCount: Int = 3
    /// The layout's share of a frame.
    static let layoutSeconds: Double = 0.003

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bodyPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let bundlePipeline: MTLRenderPipelineState
    private let glowPipeline: MTLRenderPipelineState
    /// Bodies: tested and written. Lines and glows: tested only. The chosen
    /// body: drawn over everything.
    private let solidDepth: MTLDepthStencilState
    private let glassDepth: MTLDepthStencilState
    private let overDepth: MTLDepthStencilState
    private let inFlight = DispatchSemaphore(value: GraphPerfRenderer.slotCount)

    private(set) var scene: GraphPerfScene?
    private(set) var force: GraphPerfForce?
    private(set) var planner = GraphPerfLODPlanner()
    private var statics: GraphPerfStatics?
    private var slots: [GraphPerfSlot] = []
    private var frameNumber: Int = 0

    // what the map view sets
    var camera = GraphPerfCamera()
    var tier: GraphPerfTier = .high
    var bold: Bool = false
    var selected: Int?
    var focus: Int?
    private(set) var mask: [Bool]?
    private var maskVersion: Int = 0
    /// Called at the start of each frame with the seconds since the last.
    var beforeFrame: ((Double) -> Void)?
    var onStats: ((GraphPerfStats) -> Void)?

    // pacing and the readout
    private var layoutBudget: Int = 4_000
    private var lastTime: CFTimeInterval = 0
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var intervals: [Double] = []
    private var cpuTimes: [Double] = []
    private var statsTime: CFTimeInterval = 0
    /// The viewpoint the last frame was drawn from (for picks and the name pill).
    private(set) var viewpoint: GraphPerfViewpoint?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: GraphPerfShaders.source, options: nil) else {
            return nil
        }
        let colourFormat: MTLPixelFormat = view.colorPixelFormat
        let depthFormat: MTLPixelFormat = view.depthStencilPixelFormat
        let samples: Int = view.sampleCount
        func pipeline(_ vertex: String, _ fragment: String, additive: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                return nil
            }
            d.vertexFunction = v
            d.fragmentFunction = f
            d.depthAttachmentPixelFormat = depthFormat
            d.rasterSampleCount = samples
            guard let colour = d.colorAttachments[0] else { return nil }
            colour.pixelFormat = colourFormat
            colour.isBlendingEnabled = true
            colour.rgbBlendOperation = .add
            colour.alphaBlendOperation = .add
            colour.sourceAlphaBlendFactor = .one
            if additive {
                colour.sourceRGBBlendFactor = .one
                colour.destinationRGBBlendFactor = .one
                colour.destinationAlphaBlendFactor = .one
            } else {
                colour.sourceRGBBlendFactor = .sourceAlpha
                colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        func depth(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        guard let body = pipeline("perf_body_vertex", "perf_body_fragment", additive: false),
              let line = pipeline("perf_line_vertex", "perf_line_fragment", additive: true),
              let bundle = pipeline("perf_bundle_vertex", "perf_line_fragment", additive: true),
              let glow = pipeline("perf_glow_vertex", "perf_glow_fragment", additive: true),
              let solid = depth(.less, write: true),
              let glass = depth(.lessEqual, write: false),
              let over = depth(.always, write: false) else {
            return nil
        }
        self.device = device
        self.queue = queue
        bodyPipeline = body
        linePipeline = line
        bundlePipeline = bundle
        glowPipeline = glow
        solidDepth = solid
        glassDepth = glass
        overDepth = over
        super.init()
    }

    // MARK: - The map

    /// Shows a newly built map: its static buffers, fresh frame slots, and
    /// its layout from the seed. The camera is the view's to set.
    func load(_ scene: GraphPerfScene) {
        guard let made = GraphPerfStatics(device: device, scene: scene) else { return }
        var fresh: [GraphPerfSlot] = []
        for _ in 0..<Self.slotCount {
            guard let slot = GraphPerfSlot(device: device, scene: scene) else { return }
            fresh.append(slot)
        }
        self.scene = scene
        statics = made
        slots = fresh
        force = GraphPerfForce(graph: scene.graph, layout: scene.layout)
        planner = GraphPerfLODPlanner()
        mask = nil
        maskVersion += 1
        selected = nil
        focus = nil
    }

    /// The filter: which bodies show (nil: all).
    func setMask(_ next: [Bool]?) {
        mask = next
        maskVersion += 1
    }

    /// Whether frames are still needed for the map itself (its layout settling).
    var isSettling: Bool { !(force?.isSettled ?? true) }

    /// Where body `i` is now.
    func position(_ i: Int) -> SIMD3<Float>? {
        guard let force, i >= 0, i < force.nodeCount else { return nil }
        return force.position(i)
    }

    /// The viewpoint for a view of this size (points), its depth range round the map.
    func viewpoint(width: Float, height: Float) -> GraphPerfViewpoint {
        let centre: SIMD3<Float> = scene?.centre ?? .zero
        let radius: Float = scene?.radius ?? 1
        let range = camera.depthRange(centre: centre, radius: radius)
        return GraphPerfViewpoint(camera: camera, width: max(width, 1), height: max(height, 1),
                                  near: range.near, far: range.far)
    }

    /// What the last frame drew, as a pick sees it.
    func drawnPoints() -> GraphPerfDrawnPoints? {
        guard let scene, let force, let viewpoint else { return nil }
        return GraphPerfDrawnPoints.of(scene, lists: planner.lists, xyzr: force.xyzr, view: viewpoint)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now: CFTimeInterval = CACurrentMediaTime()
        let step: Double = lastTime > 0 ? min(now - lastTime, 0.25) : 1.0 / 60.0
        if lastTime > 0 { intervals.append(now - lastTime) }
        lastTime = now
        beforeFrame?(step)
        guard let scene, let statics, slots.count == Self.slotCount else { return }
        let started: CFTimeInterval = CACurrentMediaTime()

        // a slice of the layout, sized to its share of the frame
        if isSettling {
            let t0: CFTimeInterval = CACurrentMediaTime()
            force?.step(budget: layoutBudget)
            let spent: Double = max(CACurrentMediaTime() - t0, 0.000_05)
            let scaled: Double = Double(layoutBudget) * Self.layoutSeconds / spent
            layoutBudget = min(max(Int(scaled * 0.5 + Double(layoutBudget) * 0.5), 500), 60_000)
        }

        // the level of detail for this viewpoint
        let size: CGSize = view.bounds.size
        let here: GraphPerfViewpoint = viewpoint(width: Float(size.width), height: Float(size.height))
        viewpoint = here
        planner.plan(scene.clusters, view: here, settings: GraphPerfLODSettings.of(tier), mask: mask,
                     maskVersion: maskVersion)

        // this slot, once the GPU is done with it, brought up to date
        inFlight.wait()
        let slot: GraphPerfSlot = slots[frameNumber % Self.slotCount]
        frameNumber += 1
        if let force, slot.positionsVersion != force.version {
            GraphPerfSlot.copy(force.xyzr, into: slot.positions)
            slot.positionsVersion = force.version
        }
        let lists: GraphPerfDrawLists = planner.lists
        if slot.listsVersion != planner.version {
            GraphPerfSlot.copy(lists.nodes, into: slot.nodes)
            GraphPerfSlot.copy(lists.glows, into: slot.glows)
            GraphPerfSlot.copy(lists.links, into: slot.links)
            GraphPerfSlot.copy(lists.bundles, into: slot.bundles)
            GraphPerfSlot.copy(lists.collapsed, into: slot.collapsed)
            slot.listsVersion = planner.version
        }

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let frame: [SIMD4<Float>] = GraphPerfShaders.frame(here, scene: scene, tier: tier, bold: bold,
                                                           selected: selected, focus: focus,
                                                           pixelsPerPoint: Float(view.contentScaleFactor),
                                                           time: Float(now - startTime))
        frame.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                encoder.setVertexBytes(base, length: raw.count, index: GraphPerfShaders.Slot.frame)
            }
        }
        encoder.setVertexBuffer(slot.positions, offset: 0, index: GraphPerfShaders.Slot.positions)
        encoder.setVertexBuffer(statics.colours, offset: 0, index: GraphPerfShaders.Slot.colours)
        encoder.setVertexBuffer(statics.lineEnds, offset: 0, index: GraphPerfShaders.Slot.lineEnds)
        encoder.setVertexBuffer(statics.clusterOfBody, offset: 0, index: GraphPerfShaders.Slot.clusterOfBody)
        encoder.setVertexBuffer(statics.clusterBalls, offset: 0, index: GraphPerfShaders.Slot.clusterBalls)
        encoder.setVertexBuffer(slot.collapsed, offset: 0, index: GraphPerfShaders.Slot.collapsed)
        encoder.setVertexBuffer(statics.clusterColours, offset: 0, index: GraphPerfShaders.Slot.clusterColours)
        encoder.setVertexBuffer(statics.bundleEnds, offset: 0, index: GraphPerfShaders.Slot.bundleEnds)
        encoder.setVertexBuffer(statics.bundleWeights, offset: 0, index: GraphPerfShaders.Slot.bundleWeights)

        if !lists.nodes.isEmpty {
            encoder.setRenderPipelineState(bodyPipeline)
            encoder.setDepthStencilState(solidDepth)
            encoder.setVertexBuffer(slot.nodes, offset: 0, index: GraphPerfShaders.Slot.list)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: lists.nodes.count)
        }
        if !lists.links.isEmpty {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setDepthStencilState(glassDepth)
            encoder.setVertexBuffer(slot.links, offset: 0, index: GraphPerfShaders.Slot.list)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2 * lists.links.count)
        }
        if !lists.bundles.isEmpty {
            encoder.setRenderPipelineState(bundlePipeline)
            encoder.setDepthStencilState(glassDepth)
            encoder.setVertexBuffer(slot.bundles, offset: 0, index: GraphPerfShaders.Slot.list)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2 * lists.bundles.count)
        }
        if !lists.glows.isEmpty {
            encoder.setRenderPipelineState(glowPipeline)
            encoder.setDepthStencilState(glassDepth)
            encoder.setVertexBuffer(slot.glows, offset: 0, index: GraphPerfShaders.Slot.list)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: lists.glows.count)
        }
        if let chosen = selected, chosen >= 0, chosen < scene.bodyCount {
            var one = UInt32(chosen)
            encoder.setRenderPipelineState(bodyPipeline)
            encoder.setDepthStencilState(overDepth)
            encoder.setVertexBytes(&one, length: MemoryLayout<UInt32>.stride, index: GraphPerfShaders.Slot.list)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        }
        encoder.endEncoding()
        commands.present(drawable)
        let done: DispatchSemaphore = inFlight
        commands.addCompletedHandler { _ in done.signal() }
        commands.commit()

        cpuTimes.append(CACurrentMediaTime() - started)
        report(now: now, scene: scene, lists: lists)
    }

    /// Twice a second: the readout's numbers.
    private func report(now: CFTimeInterval, scene: GraphPerfScene, lists: GraphPerfDrawLists) {
        if statsTime == 0 { statsTime = now }
        guard now - statsTime >= 0.5 else { return }
        var stats = GraphPerfStats()
        stats.notes = scene.graph.noteCount
        stats.links = scene.graph.linkCount
        stats.drawnBodies = lists.nodes.count
        stats.drawnGlows = lists.glows.count
        stats.drawnLines = lists.lineCount
        let total: Double = intervals.reduce(0, +)
        stats.fps = total > 0 ? Double(intervals.count) / total : 0
        let target: Double = 1.0 / Double(max(Int(stats.fps.rounded()), 1))
        stats.cpuP95 = GraphPerfFrameStats(cpuTimes, target: target).p95
        stats.settling = isSettling
        intervals.removeAll(keepingCapacity: true)
        cpuTimes.removeAll(keepingCapacity: true)
        statsTime = now
        onStats?(stats)
    }

    /// Forget the frame clock (the view paused and comes back).
    func resumeClock() {
        lastTime = 0
        intervals.removeAll(keepingCapacity: true)
        statsTime = 0
    }
}

/// The buffers made once per map.
final class GraphPerfStatics {
    let colours: MTLBuffer
    let lineEnds: MTLBuffer
    let clusterOfBody: MTLBuffer
    let clusterBalls: MTLBuffer
    let clusterColours: MTLBuffer
    let bundleEnds: MTLBuffer
    let bundleWeights: MTLBuffer

    init?(device: MTLDevice, scene: GraphPerfScene) {
        guard let colours = Self.buffer(device, scene.colours),
              let lineEnds = Self.buffer(device, scene.lineEnds),
              let clusterOfBody = Self.buffer(device, scene.clusterOfBody),
              let clusterBalls = Self.buffer(device, scene.clusterBalls),
              let clusterColours = Self.buffer(device, scene.clusterColours),
              let bundleEnds = Self.buffer(device, scene.bundleEnds),
              let bundleWeights = Self.buffer(device, scene.bundleWeights) else {
            return nil
        }
        self.colours = colours
        self.lineEnds = lineEnds
        self.clusterOfBody = clusterOfBody
        self.clusterBalls = clusterBalls
        self.clusterColours = clusterColours
        self.bundleEnds = bundleEnds
        self.bundleWeights = bundleWeights
    }

    /// A shared buffer holding `array` (at least 16 bytes, so an empty map binds too).
    static func buffer<T>(_ device: MTLDevice, _ array: [T]) -> MTLBuffer? {
        let length: Int = max(array.count * MemoryLayout<T>.stride, 16)
        guard let made = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
        GraphPerfSlot.copy(array, into: made)
        return made
    }
}

/// One frame slot: the positions and the draw lists, and which versions
/// of each it holds.
final class GraphPerfSlot {
    let positions: MTLBuffer
    let nodes: MTLBuffer
    let glows: MTLBuffer
    let links: MTLBuffer
    let bundles: MTLBuffer
    let collapsed: MTLBuffer
    var positionsVersion: Int = -1
    var listsVersion: Int = -1

    init?(device: MTLDevice, scene: GraphPerfScene) {
        let word: Int = MemoryLayout<UInt32>.stride
        func make(_ bytes: Int) -> MTLBuffer? {
            device.makeBuffer(length: max(bytes, 16), options: .storageModeShared)
        }
        guard let positions = make(scene.bodyCount * 4 * MemoryLayout<Float>.stride),
              let nodes = make(scene.bodyCount * word),
              let glows = make(scene.clusters.count * word),
              let links = make(scene.lineCount * word),
              let bundles = make(scene.clusters.bundleCount * word),
              let collapsed = make(scene.clusters.count * word) else {
            return nil
        }
        self.positions = positions
        self.nodes = nodes
        self.glows = glows
        self.links = links
        self.bundles = bundles
        self.collapsed = collapsed
    }

    /// Copies `array` into the start of `buffer`, never past its end.
    static func copy<T>(_ array: [T], into buffer: MTLBuffer) {
        array.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            buffer.contents().copyMemory(from: base, byteCount: min(raw.count, buffer.length))
        }
    }
}
#endif
