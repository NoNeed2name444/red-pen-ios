import SceneKit
import UIKit
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
/// in six segments so it can bend: near a black hole the last stretch is
/// pulled towards the disk's plane and swung round its axis, so the beam
/// curls in along the disk; near a gas giant it is pulled gently towards
/// the ring's plane. A link that is growing in is drawn from its sending
/// end along the same curve, its tip fading in the shader.
///
/// The texture coordinates carry what the link shader needs (see
/// GraphStyleShaders.link): u = ((styleA * 8 + styleB) * 16 + seed) * 64 +
/// 1 + the distance along the ribbon (in the space's units, capped at 60);
/// v = the length in sixteenths, doubled, plus one if the link touches the
/// chosen or dragged note, plus the position across. GraphShaders.link,
/// the fallback, reads the same numbers (its seed is just larger).
///
/// Render thread only. Nothing is allocated per frame once the buffers
/// have grown to the number of links.
nonisolated final class GraphRibbonWriter {
    static let segments: Int = 6
    private var vertices: [SCNVector3] = []
    private var uvs: [Float] = []
    private var points: [SIMD3<Float>] = []
    private var lengths: [Float] = []
    private var element: SCNGeometryElement?
    private var elementLinks: Int = -1
    /// Half the ribbon's width: today's in the graph look, finer in the
    /// Universe.
    private let halfWidth: Float

    init(halfWidth: Float = GraphShape.linkHalfWidth) {
        self.halfWidth = halfWidth
        let count: Int = Self.segments + 1
        points = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count)
        lengths = [Float](repeating: 0, count: count)
    }

    /// `codes`: each note's style code; `axis`: each note's disk axis (or
    /// nil for none known); `focus`: the chosen or dragged note, or -1.
    func write(links: [GraphRibbonLink], position: [SIMD3<Float>], radius: [Float], codes: [Int],
               axis: [SIMD3<Float>]?, focus: Int, eye: SIMD3<Float>) -> SCNGeometry? {
        guard !links.isEmpty else { return nil }
        if elementLinks != links.count { rebuildElement(links.count) }
        guard let element else { return nil }
        vertices.removeAll(keepingCapacity: true)
        uvs.removeAll(keepingCapacity: true)
        for link in links {
            append(link, position: position, radius: radius, codes: codes, axis: axis,
                   focus: focus, eye: eye)
        }
        let source = SCNGeometrySource(vertices: vertices)
        let data: Data = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let coords = SCNGeometrySource(data: data, semantic: .texcoord,
                                       vectorCount: vertices.count, usesFloatComponents: true,
                                       componentsPerVector: 2, bytesPerComponent: 4,
                                       dataOffset: 0, dataStride: 8)
        return SCNGeometry(sources: [source, coords], elements: [element])
    }

    private func rebuildElement(_ count: Int) {
        let n: Int = Self.segments
        var indices: [Int32] = []
        indices.reserveCapacity(count * n * 6)
        for link in 0..<count {
            let first: Int = link * (n + 1) * 2
            for k in 0..<n {
                let base = Int32(first + k * 2)
                indices.append(base)
                indices.append(base + 1)
                indices.append(base + 2)
                indices.append(base + 2)
                indices.append(base + 1)
                indices.append(base + 3)
            }
        }
        element = indices.isEmpty ? nil : SCNGeometryElement(indices: indices, primitiveType: .triangles)
        elementLinks = count
    }

    private func append(_ link: GraphRibbonLink, position: [SIMD3<Float>], radius: [Float],
                        codes: [Int], axis: [SIMD3<Float>]?, focus: Int, eye: SIMD3<Float>) {
        let n: Int = Self.segments
        let pa: SIMD3<Float> = position[link.a]
        let pb: SIMD3<Float> = position[link.b]
        let delta: SIMD3<Float> = pb - pa
        let length: Float = simd_length(delta)
        let dir: SIMD3<Float> = length > 0.0001 ? delta / length : SIMD3<Float>(1, 0, 0)
        let trimA: Float = min(radius[link.a] * GraphShape.linkTrim, length * 0.45)
        let trimB: Float = min(radius[link.b] * GraphShape.linkTrim, length * 0.45)
        let start: SIMD3<Float> = pa + dir * trimA
        let end: SIMD3<Float> = pb - dir * trimB
        let codeA: Int = codes[link.a]
        let codeB: Int = codes[link.b]
        let arch: SIMD3<Float> = link.bow > 0 ? archDirection(link, from: pa, to: pb, dir: dir) : .zero
        let archSize: Float = link.bow * length
        for k in 0...n {
            let s: Float = Float(k) / Float(n) * link.grow
            var p: SIMD3<Float> = start + (end - start) * s
            if link.bow > 0 {
                let hump: Float = 4 * s * (1 - s) * archSize
                p += arch * hump
            }
            if let axis {
                p = bend(p, s: s, centre: pb, axis: axis[link.b], code: codeB)
                p = bend(p, s: 1 - s, centre: pa, axis: axis[link.a], code: codeA)
            }
            points[k] = p
        }
        var total: Float = 0
        lengths[0] = 0
        for k in 1...n {
            total += simd_distance(points[k], points[k - 1])
            lengths[k] = total
        }

        let seed: Int = link.seed % 16
        let pair: Int = codeA * 8 + codeB
        let code: Int = pair * 16 + seed
        let lit: Int = (link.a == focus || link.b == focus) ? 1 : 0
        let coded: Float = min(total, 60)
        let sixteenths: Int = Int((coded * 16).rounded(.down))
        let band: Float = Float(sixteenths * 2 + lit)
        let low: Float = band + 0.002
        let high: Float = band + 0.998
        let u0: Float = Float(code * 64 + 1)
        for k in 0...n {
            let before: SIMD3<Float> = points[max(k - 1, 0)]
            let after: SIMD3<Float> = points[min(k + 1, n)]
            var tangent: SIMD3<Float> = after - before
            let tl: Float = simd_length(tangent)
            tangent = tl > 0.00001 ? tangent / tl : dir
            let p: SIMD3<Float> = points[k]
            var side: SIMD3<Float> = simd_cross(tangent, eye - p)
            let sl: Float = simd_length(side)
            side = sl > 0.0001 ? side / sl : Self.perpendicular(to: tangent)
            let offset: SIMD3<Float> = side * halfWidth
            let p0: SIMD3<Float> = p - offset
            let p1: SIMD3<Float> = p + offset
            vertices.append(SCNVector3(x: p0.x, y: p0.y, z: p0.z))
            vertices.append(SCNVector3(x: p1.x, y: p1.y, z: p1.z))
            let u: Float = u0 + min(lengths[k], 60)
            uvs.append(u)
            uvs.append(low)
            uvs.append(u)
            uvs.append(high)
        }
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
        return sideSize > 0.0001 ? side / sideSize : Self.perpendicular(to: dir)
    }

    /// Bends a point `s` of the way from the far end towards an end at
    /// `centre` (1 at that end): a black hole (code 0) pulls the last half
    /// towards its disk's plane and swings it round the axis; a gas giant
    /// (code 2) only pulls it towards its ring's plane. The point keeps its
    /// distance from the centre, so the link still ends at the trim.
    private func bend(_ p: SIMD3<Float>, s: Float, centre: SIMD3<Float>, axis n: SIMD3<Float>,
                      code: Int) -> SIMD3<Float> {
        guard code == 0 || code == 2 else { return p }
        let t: Float = min(max((s - 0.45) / 0.55, 0), 1)
        let w: Float = t * t * (3 - 2 * t)
        guard w > 0.0001 else { return p }
        var rel: SIMD3<Float> = p - centre
        let dist: Float = simd_length(rel)
        guard dist > 0.0001 else { return p }
        let pull: Float = code == 0 ? 0.7 : 0.35
        rel -= n * (simd_dot(rel, n) * pull * w)
        if code == 0 {
            let swing = simd_quatf(angle: 0.55 * w * w, axis: n)
            rel = swing.act(rel)
        }
        let now: Float = simd_length(rel)
        guard now > 0.0001 else { return p }
        return centre + rel * (dist / now)
    }

    private static func perpendicular(to dir: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(dir.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        return simd_normalize(simd_cross(dir, helper))
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
