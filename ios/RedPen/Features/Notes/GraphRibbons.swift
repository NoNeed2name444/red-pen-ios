import SceneKit
import UIKit
import Metal
import simd

/// One link to draw this frame: its sending end `a` (the higher style
/// code), its receiving end `b`, its seed, and how far it has grown (0 to
/// 1, eased; less than 1 while it grows in or fades out). In the Universe a
/// link between folders arches: `bow` of its length away from `centre` (a
/// galaxy core, or the origin); 0 draws it straight.
nonisolated struct GraphRibbonLink {
    let a: Int
    let b: Int
    let seed: Int
    let grow: Float
    var bow: Float = 0
    var centre = SIMD3<Float>(0, 0, 0)
}

/// Builds every shown link as one geometry of camera-facing ribbons, each
/// ONE smooth continuous curve (GraphLinkCurve): sampled finely enough -
/// GraphicsBudget.linkSamples, 40 at High quality and 20 at Smooth - that no
/// joint, kink or gap shows, with one strip of shared vertices from end to
/// end, so there is nothing between samples for a seam to hide in. Near a
/// black hole the last stretch curls into the disk's plane and swings round
/// its axis; near a gas giant it is pulled gently towards the ring's plane;
/// an arched link bows on a smooth parabola. A link that is growing in is
/// drawn from its sending end along the same curve, its tip fading in the
/// shader.
///
/// The texture coordinates carry what the link shader needs (see
/// GraphStyleShaders.link): u = ((styleA * 8 + styleB) * 16 + seed) * 64 +
/// 1 + the distance along the ribbon, continuous from end to end so the
/// shader's flow runs without a seam (a link longer than 60 units has its
/// distances evenly shrunk to fit, rather than the far part stopping dead);
/// v = the length in sixteenths, doubled, plus one if the link touches the
/// chosen or dragged note, plus the position across. GraphShaders.link,
/// the fallback, reads the same numbers (its seed is just larger).
///
/// No geometry is made per frame. The vertices live in Metal buffers that
/// SceneKit draws straight from, three sets in turn (so the one being
/// written is never one the GPU may still be reading); each frame only
/// their contents are rewritten and the node is pointed at the set just
/// written. The index list is made once for as many links as the scene can
/// show; slots not used this frame are collapsed to a point, which draws
/// nothing. Without Metal (never on a device) it falls back to a new
/// geometry a frame.
///
/// Render thread only.
nonisolated final class GraphRibbonWriter {
    /// Points along each link's curve (the strip has one more pair).
    let samples: Int
    /// Half the ribbon's width: today's in the graph look, finer in the
    /// Universe.
    private let halfWidth: Float
    private let material: SCNMaterial
    private var points: [SIMD3<Float>] = []
    private var lengths: [Float] = []
    /// The three buffer sets, the one written last, and how many links
    /// each can hold.
    private var sets: [GraphRibbonBuffers] = []
    private var turn: Int = 0
    private var capacity: Int = 0
    private var element: SCNGeometryElement?
    /// The fallback's scratch.
    private var scratchPositions: [Float] = []
    private var scratchCoords: [Float] = []
    /// This frame's bounds, for SceneKit's culling.
    private var low = SIMD3<Float>(0, 0, 0)
    private var high = SIMD3<Float>(0, 0, 0)
    /// The themes' coding (GraphThemeScene): u = (seed mod 256) * 64 + 1
    /// + the distance along, with no style pair - a theme's link shader
    /// reads no styles, and 256 seeds give links their own rhythms (the
    /// Neurons' impulses fire at each link's own random times) while u
    /// stays under 16,448, where a 32-bit float still steps by about
    /// 0.002 - fine enough for the shaders' finest marks (dots, nodes of
    /// Ranvier, impulse heads a few hundredths wide).
    private let seeded: Bool
    /// A board the links are routed on (the Circuit theme): each one a
    /// trace square to the board's edges with rounded 45° corners
    /// (GraphLinkRoute), its strip lying flat on the board instead of
    /// facing the camera. Nil everywhere else.
    private let board: GraphLinkBoard?

    init(halfWidth: Float = GraphShape.linkHalfWidth, material: SCNMaterial,
         samples: Int = GraphQuality.current.linkSamples, expected: Int = 0, seeded: Bool = false,
         board: GraphLinkBoard? = nil) {
        self.halfWidth = halfWidth
        self.material = material
        self.seeded = seeded
        self.board = board
        self.samples = max(samples, 2)
        let count: Int = self.samples + 1
        points = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count)
        lengths = [Float](repeating: 0, count: count)
        capacity = max(expected, 0)
    }

    /// Floats a link takes in the position (3 a vertex) and coordinate (2 a
    /// vertex) buffers: two vertices per point.
    private var vertsPerLink: Int { (samples + 1) * 2 }

    /// `codes`: each note's style code; `axis`: each note's disk axis (or
    /// nil for none known); `focus`: the chosen or dragged note, or -1;
    /// `device`: the renderer's Metal device (nil: the fallback).
    func write(links: [GraphRibbonLink], position: [SIMD3<Float>], radius: [Float], codes: [Int],
               axis: [SIMD3<Float>]?, focus: Int, eye: SIMD3<Float>, device: MTLDevice?) -> SCNGeometry? {
        guard !links.isEmpty else { return nil }
        guard let device else {
            return writeFallback(links: links, position: position, radius: radius, codes: codes,
                                 axis: axis, focus: focus, eye: eye)
        }
        if sets.isEmpty || links.count > capacity {
            grow(to: links.count, device: device)
        }
        guard !sets.isEmpty else { return nil }
        turn = (turn + 1) % sets.count
        let set: GraphRibbonBuffers = sets[turn]
        let perLink: Int = vertsPerLink
        let posCount: Int = capacity * perLink * 3
        let uvCount: Int = capacity * perLink * 2
        let pos: UnsafeMutablePointer<Float> = set.positions.contents().bindMemory(to: Float.self, capacity: posCount)
        let uv: UnsafeMutablePointer<Float> = set.coords.contents().bindMemory(to: Float.self, capacity: uvCount)
        startBounds()
        for (slot, link) in links.enumerated() {
            let first: Int = slot * perLink
            fill(link, position: position, radius: radius, codes: codes, axis: axis, focus: focus,
                 eye: eye, pos: pos, uv: uv, first: first)
        }
        // slots used last time this set was drawn and not now: collapsed
        let used: Int = links.count
        if set.filled > used {
            let from: Int = used * perLink * 3
            let upTo: Int = set.filled * perLink * 3
            for k in from..<upTo { pos[k] = 0 }
        }
        set.filled = used
        set.geometry.boundingBox = bounds()
        return set.geometry
    }

    /// Makes (or remakes, larger) the three buffer sets and the index list.
    private func grow(to count: Int, device: MTLDevice) {
        let wanted: Int = max(count, capacity, 8)
        let doubled: Int = sets.isEmpty ? wanted : max(wanted, capacity * 2)
        capacity = doubled
        let perLink: Int = vertsPerLink
        let vertexCount: Int = capacity * perLink
        element = Self.indices(links: capacity, samples: samples)
        guard let element else { return }
        var made: [GraphRibbonBuffers] = []
        for _ in 0..<3 {
            let posBytes: Int = vertexCount * 3 * MemoryLayout<Float>.stride
            let uvBytes: Int = vertexCount * 2 * MemoryLayout<Float>.stride
            guard let positions = device.makeBuffer(length: posBytes, options: .storageModeShared),
                  let coords = device.makeBuffer(length: uvBytes, options: .storageModeShared) else {
                sets = []
                return
            }
            // every slot starts collapsed to a point: nothing drawn
            memset(positions.contents(), 0, posBytes)
            memset(coords.contents(), 0, uvBytes)
            let vertexSource = SCNGeometrySource(buffer: positions, vertexFormat: .float3, semantic: .vertex,
                                                 vertexCount: vertexCount, dataOffset: 0, dataStride: 12)
            let coordSource = SCNGeometrySource(buffer: coords, vertexFormat: .float2, semantic: .texcoord,
                                                vertexCount: vertexCount, dataOffset: 0, dataStride: 8)
            let geometry = SCNGeometry(sources: [vertexSource, coordSource], elements: [element])
            geometry.materials = [material]
            made.append(GraphRibbonBuffers(positions: positions, coords: coords, geometry: geometry))
        }
        sets = made
    }

    /// Two triangles between each pair of neighbouring samples, for
    /// `links` links; the strips share their vertices, so there is no joint.
    private static func indices(links: Int, samples n: Int) -> SCNGeometryElement? {
        var list: [Int32] = []
        list.reserveCapacity(links * n * 6)
        for link in 0..<links {
            let first: Int = link * (n + 1) * 2
            for k in 0..<n {
                let base = Int32(first + k * 2)
                list.append(base)
                list.append(base + 1)
                list.append(base + 2)
                list.append(base + 2)
                list.append(base + 1)
                list.append(base + 3)
            }
        }
        guard !list.isEmpty else { return nil }
        return SCNGeometryElement(indices: list, primitiveType: .triangles)
    }

    /// Without Metal: the same vertices into arrays, as a new geometry.
    private func writeFallback(links: [GraphRibbonLink], position: [SIMD3<Float>], radius: [Float],
                               codes: [Int], axis: [SIMD3<Float>]?, focus: Int,
                               eye: SIMD3<Float>) -> SCNGeometry? {
        if element == nil || links.count > capacity {
            capacity = max(links.count, capacity)
            element = Self.indices(links: capacity, samples: samples)
        }
        guard let element else { return nil }
        let perLink: Int = vertsPerLink
        let vertexCount: Int = capacity * perLink
        let posCount: Int = vertexCount * 3
        let uvCount: Int = vertexCount * 2
        if scratchPositions.count != posCount {
            scratchPositions = [Float](repeating: 0, count: posCount)
            scratchCoords = [Float](repeating: 0, count: uvCount)
        }
        startBounds()
        scratchPositions.withUnsafeMutableBufferPointer { posBuffer in
            scratchCoords.withUnsafeMutableBufferPointer { uvBuffer in
                guard let pos = posBuffer.baseAddress, let uv = uvBuffer.baseAddress else { return }
                for k in 0..<posCount { pos[k] = 0 }
                for (slot, link) in links.enumerated() {
                    fill(link, position: position, radius: radius, codes: codes, axis: axis, focus: focus,
                         eye: eye, pos: pos, uv: uv, first: slot * perLink)
                }
            }
        }
        let posData: Data = scratchPositions.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData: Data = scratchCoords.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertexSource = SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: vertexCount,
                                             usesFloatComponents: true, componentsPerVector: 3,
                                             bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let coordSource = SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: vertexCount,
                                            usesFloatComponents: true, componentsPerVector: 2,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let geometry = SCNGeometry(sources: [vertexSource, coordSource], elements: [element])
        geometry.materials = [material]
        return geometry
    }

    /// Writes one link's strip - two vertices per sample, starting at
    /// vertex `first` - and its texture coordinates.
    private func fill(_ link: GraphRibbonLink, position: [SIMD3<Float>], radius: [Float], codes: [Int],
                      axis: [SIMD3<Float>]?, focus: Int, eye: SIMD3<Float>,
                      pos: UnsafeMutablePointer<Float>, uv: UnsafeMutablePointer<Float>, first: Int) {
        let n: Int = samples
        let path: GraphLinkPath = self.path(link, position: position, radius: radius, codes: codes, axis: axis)
        let total: Float = GraphLinkCurve.sample(path, count: n, points: &points, lengths: &lengths)
        let dir: SIMD3<Float> = GraphLinkCurve.unit(path.end - path.start, or: SIMD3<Float>(1, 0, 0))

        let codeA: Int = codes[link.a]
        let codeB: Int = codes[link.b]
        let seed: Int = link.seed % 16
        let pair: Int = codeA * 8 + codeB
        let styled: Int = pair * 16 + seed
        let code: Int = seeded ? Self.themeSeed(link.seed) : styled
        let lit: Int = (link.a == focus || link.b == focus) ? 1 : 0
        let scale: Float = GraphLinkCurve.alongScale(total: total)
        let coded: Float = min(total * scale, GraphLinkCurve.alongCap)
        let sixteenths: Int = Int((coded * 16).rounded(.down))
        let band: Float = Float(sixteenths * 2 + lit)
        let lowV: Float = band + 0.002
        let highV: Float = band + 0.998
        let u0: Float = Float(code * 64 + 1)
        for k in 0...n {
            let tangent: SIMD3<Float> = GraphLinkCurve.tangent(points, k, n, fallback: dir)
            let p: SIMD3<Float> = points[k]
            let facing: SIMD3<Float> = GraphLinkCurve.cross(tangent, eye - p)
            let fallback: SIMD3<Float> = GraphLinkCurve.perpendicular(to: tangent)
            var side: SIMD3<Float> = GraphLinkCurve.unit(facing, or: fallback)
            if let board {
                // flat on the board (facing the camera only where a dragged
                // part has pulled it up off the board)
                side = GraphLinkCurve.unit(GraphLinkCurve.cross(board.normal, tangent), or: side)
            }
            let offset: SIMD3<Float> = side * halfWidth
            let p0: SIMD3<Float> = p - offset
            let p1: SIMD3<Float> = p + offset
            let v: Int = first + k * 2
            put(p0, pos, v)
            put(p1, pos, v + 1)
            let along: Float = min(lengths[k] * scale, GraphLinkCurve.alongCap)
            let u: Float = u0 + along
            uv[v * 2] = u
            uv[v * 2 + 1] = lowV
            uv[v * 2 + 2] = u
            uv[v * 2 + 3] = highV
        }
    }

    /// A link's seed as a theme's shader reads it (0...255), and as its
    /// CPU side must use it to stay in step (NeuronImpulses).
    static let themeSeeds: Int = 256

    static func themeSeed(_ seed: Int) -> Int {
        let wrapped: Int = seed % themeSeeds
        return wrapped < 0 ? wrapped + themeSeeds : wrapped
    }

    /// The curve's inputs for one link: trimmed clear of both rings, arched
    /// away from its centre, bent near a black hole or a gas giant.
    private func path(_ link: GraphRibbonLink, position: [SIMD3<Float>], radius: [Float], codes: [Int],
                      axis: [SIMD3<Float>]?) -> GraphLinkPath {
        let pa: SIMD3<Float> = position[link.a]
        let pb: SIMD3<Float> = position[link.b]
        let delta: SIMD3<Float> = pb - pa
        let length: Float = simd_length(delta)
        let dir: SIMD3<Float> = length > 0.0001 ? delta / length : SIMD3<Float>(1, 0, 0)
        let trimA: Float = min(radius[link.a] * GraphShape.linkTrim, length * 0.45)
        let trimB: Float = min(radius[link.b] * GraphShape.linkTrim, length * 0.45)
        var path = GraphLinkPath(start: pa + dir * trimA, end: pb - dir * trimB)
        path.grow = link.grow
        if let board {
            let fullA: Float = radius[link.a] * GraphShape.linkTrim
            let fullB: Float = radius[link.b] * GraphShape.linkTrim
            path.route = GraphLinkRoute(from: pa, to: pb, board: board, trimA: fullA, trimB: fullB, seed: link.seed)
            return path
        }
        if link.bow > 0 {
            path.arch = archDirection(link, from: pa, to: pb, dir: dir)
            path.archSize = link.bow * length
        }
        if let axis {
            path.bendA = GraphLinkBend.forStyle(codes[link.a], centre: pa, axis: axis[link.a])
            path.bendB = GraphLinkBend.forStyle(codes[link.b], centre: pb, axis: axis[link.b])
        }
        return path
    }

    private func put(_ p: SIMD3<Float>, _ pos: UnsafeMutablePointer<Float>, _ vertex: Int) {
        let at: Int = vertex * 3
        pos[at] = p.x
        pos[at + 1] = p.y
        pos[at + 2] = p.z
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }

    private func startBounds() {
        let big: Float = Float.greatestFiniteMagnitude
        low = SIMD3<Float>(big, big, big)
        high = SIMD3<Float>(-big, -big, -big)
    }

    /// This frame's bounds, a little padded; the origin when nothing was
    /// written.
    private func bounds() -> (min: SCNVector3, max: SCNVector3) {
        guard low.x <= high.x else {
            let zero = SCNVector3(x: 0, y: 0, z: 0)
            return (zero, zero)
        }
        let pad: Float = halfWidth
        let a: SIMD3<Float> = low - SIMD3<Float>(pad, pad, pad)
        let b: SIMD3<Float> = high + SIMD3<Float>(pad, pad, pad)
        return (SCNVector3(x: a.x, y: a.y, z: a.z), SCNVector3(x: b.x, y: b.y, z: b.z))
    }

    /// Which way a link arches: away from its centre, square to the link;
    /// any square direction when the centre is on the line.
    private func archDirection(_ link: GraphRibbonLink, from pa: SIMD3<Float>, to pb: SIMD3<Float>,
                               dir: SIMD3<Float>) -> SIMD3<Float> {
        let middle: SIMD3<Float> = (pa + pb) * 0.5
        var w: SIMD3<Float> = middle - link.centre
        w -= dir * simd_dot(w, dir)
        let size: Float = simd_length(w)
        if size > 0.0001 { return w / size }
        let side: SIMD3<Float> = simd_cross(dir, SIMD3<Float>(0, 0, 1))
        let sideSize: Float = simd_length(side)
        return sideSize > 0.0001 ? side / sideSize : GraphLinkCurve.perpendicular(to: dir)
    }
}

/// One of the writer's three sets: the Metal buffers SceneKit draws the
/// links from, the geometry over them, and how many link slots were
/// written when it was last used.
nonisolated final class GraphRibbonBuffers {
    let positions: MTLBuffer
    let coords: MTLBuffer
    let geometry: SCNGeometry
    var filled: Int = 0

    init(positions: MTLBuffer, coords: MTLBuffer, geometry: SCNGeometry) {
        self.positions = positions
        self.coords = coords
        self.geometry = geometry
    }
}

/// What the scene before this one showed, so a rebuild (a note added, a
/// link made, the look changed) animates only what changed: new notes pop
/// in, new links grow, removed links fade out, a note whose look changed
/// blooms into its new one, and everything else glides from where it was
/// to its new place instead of the whole space blooming again.
nonisolated struct GraphRecall: Sendable {
    /// Notes to pop in; nil means all of them (a first showing).
    let fresh: Set<UUID>?
    /// Links (GraphMemory.key) to grow in; nil means all of them.
    let freshLinks: Set<String>?
    /// Links that were shown and are gone, between notes still here.
    let ghosts: [(UUID, UUID)]
    /// Where each known note was.
    let starts: [UUID: SIMD3<Float>]
    /// The Universe's orbit clock on the scene being replaced, so a rebuild
    /// never rewinds the orbits; 0 when the space opens.
    var orbitTime: Double = 0

    static let everything = GraphRecall(fresh: nil, freshLinks: nil, ghosts: [], starts: [:])
}

@MainActor
enum GraphMemory {
    private static weak var lastSim: GraphSim?
    private static var lastStyles: [UUID: GraphNodeStyle] = [:]
    private static var lastLinks: Set<String> = []
    private static var lastPairs: [String: (UUID, UUID)] = [:]

    nonisolated static func key(_ a: UUID, _ b: UUID) -> String {
        let x: String = a.uuidString
        let y: String = b.uuidString
        return x < y ? x + y : y + x
    }

    /// What changed since the scene still on screen; everything when there
    /// is none (the space is just opening) or nothing moves anyway.
    static func recall(ids: [UUID], edges: [(UUID, UUID)], styles: [UUID: GraphNodeStyle],
                       lively: Bool) -> GraphRecall {
        guard lively, let sim = lastSim else { return .everything }
        var fresh = Set<UUID>()
        var starts: [UUID: SIMD3<Float>] = [:]
        for id in ids {
            guard let slot = sim.index[id] else {
                fresh.insert(id)
                continue
            }
            starts[id] = sim.currentPosition(slot)
            if lastStyles[id] != styles[id] { fresh.insert(id) }
        }
        var now = Set<String>()
        for (a, b) in edges { now.insert(key(a, b)) }
        let freshLinks: Set<String> = now.subtracting(lastLinks)
        let here = Set<UUID>(ids)
        var ghosts: [(UUID, UUID)] = []
        for gone in lastLinks.subtracting(now) {
            guard let pair = lastPairs[gone], here.contains(pair.0), here.contains(pair.1) else { continue }
            ghosts.append(pair)
        }
        var recalled = GraphRecall(fresh: fresh, freshLinks: freshLinks, ghosts: ghosts, starts: starts)
        recalled.orbitTime = sim.orbitClock
        return recalled
    }

    /// Remembers the scene now on screen. Its orbit clock is read from the
    /// sim itself when the next scene is built, so it carries over as it
    /// stands then.
    static func remember(_ sim: GraphSim, edges: [(UUID, UUID)], styles: [UUID: GraphNodeStyle]) {
        lastSim = sim
        lastStyles = styles
        var links = Set<String>()
        var pairs: [String: (UUID, UUID)] = [:]
        for (a, b) in edges {
            let k: String = key(a, b)
            links.insert(k)
            pairs[k] = (a, b)
        }
        lastLinks = links
        lastPairs = pairs
    }
}
