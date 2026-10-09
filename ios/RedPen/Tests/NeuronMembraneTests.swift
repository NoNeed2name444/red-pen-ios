// A Neurons cell's membrane (GraphNeuronMembrane.swift): its soma and
// dendrites one closed surface, as the owner asked ("one entity, not
// multiple stitched things") - no holes or loose edges, every triangle
// facing out, all in one piece, every vertex on the field's zero set with
// the field's gradient as its normal, the soma round where no dendrite
// leaves it, every dendrite covered to its tip, the dendrites apart
// rather than melted into a disc, and what the shader reads per vertex
// (the share along a dendrite, how much is soma) in range and in place.
//
// Compiled with Features/Notes/GraphNeuronMembrane.swift, which imports
// only Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
func length(_ a: SIMD3<Float>) -> Float { dot(a, a).squareRoot() }
func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

/// A crown like NeuronArbor.branches(.cell): `count` dendrites round the
/// soma in the plane facing the camera (tilting out of it by up to 0.35),
/// from 0.75 of its radius, 0.3 thick tapering to 0.7 of that, about one
/// radius long with every tip inside the map's reach (1.9), wandering in
/// the plane, flared at the base.
func crown(_ count: Int, seed: UInt64) -> [NeuronBranch] {
    var state: UInt64 = seed
    func unit() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
    }
    func signed() -> Float { unit() * 2 - 1 }
    var out: [NeuronBranch] = []
    for k in 0..<count {
        let a: Float = 2 * Float.pi * (Float(k) + 0.35 * signed()) / Float(count)
        let raw = SIMD3<Float>(cos(a), sin(a), 0.35 * signed())
        let d: SIMD3<Float> = raw / length(raw)
        let reach: Float = min(1.0 + 0.2 * unit(), 1.9 - 0.75 - 0.05)
        let start: SIMD3<Float> = d * 0.75
        let across: SIMD3<Float> = cross(d, SIMD3<Float>(0, 0, 1))
        let side: SIMD3<Float> = across / length(across)
        let wander: Float = signed() * 0.3 * reach
        let bend: SIMD3<Float> = start + d * (reach * 0.5) + side * wander
        let end: SIMD3<Float> = start + d * reach + side * (wander * 0.6)
        out.append(NeuronBranch(start: start, bend: bend, end: end, r0: 0.3, r1: 0.3 * 0.7, s0: 0, s1: 1,
                                flare: 0.5))
    }
    return out
}

let h: Float = NeuronMembrane.step

for (name, count, seed) in [("six", 6, UInt64(7)), ("seven", 7, UInt64(0x9E37_79B9 &+ 7)), ("six b", 6, UInt64(41))] {
    let branches: [NeuronBranch] = crown(count, seed: seed)
    let field = NeuronMembraneField(branches)
    let began = Date()
    let membrane: NeuronMembrane = NeuronMembrane.make(branches)
    let took: Double = Date().timeIntervalSince(began)
    let points: [SIMD3<Float>] = membrane.points
    let tris: Int = membrane.indices.count / 3
    print("  \(name): \(points.count) vertices, \(tris) triangles, \(String(format: "%.0f", took * 1000)) ms")

    // M1 - closed: every edge shared by two triangles, each the other way round
    var undirected: [UInt64: Int] = [:]
    var directed: [UInt64: Int] = [:]
    func key(_ a: Int32, _ b: Int32) -> UInt64 { UInt64(UInt32(a)) << 32 | UInt64(UInt32(b)) }
    for t in 0..<tris {
        let v: [Int32] = Array(membrane.indices[(t * 3)..<(t * 3 + 3)])
        for (a, b) in [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])] {
            undirected[key(min(a, b), max(a, b)), default: 0] += 1
            directed[key(a, b), default: 0] += 1
        }
    }
    let loose: Int = undirected.values.filter { $0 % 2 == 1 }.count
    let pairs: Int = undirected.values.filter { $0 == 2 }.count
    check("M1a \(name): a real mesh", tris > 2000 && points.count > 1000, "\(tris) triangles")
    check("M1b \(name): no loose edge (closed, no holes)", loose == 0, "\(loose) of \(undirected.count)")
    check("M1c \(name): almost every edge between exactly two triangles",
          Float(pairs) >= 0.99 * Float(undirected.count), "\(pairs) of \(undirected.count)")
    let unbalanced: Int = directed.filter { directed[key(Int32($0.key & 0xFFFF_FFFF), Int32($0.key >> 32)), default: 0] != $0.value }.count
    check("M1d \(name): every edge crossed once each way (wound alike)", unbalanced == 0, "\(unbalanced)")
    check("M1e \(name): no triangle uses a vertex twice", (0..<tris).allSatisfy { t in
        let a = membrane.indices[t * 3], b = membrane.indices[t * 3 + 1], c = membrane.indices[t * 3 + 2]
        return a != b && b != c && a != c
    })

    // M2 - one piece
    var parent: [Int] = Array(0..<points.count)
    func root(_ x: Int) -> Int {
        var r: Int = x
        while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
        return r
    }
    for t in 0..<tris {
        let a = root(Int(membrane.indices[t * 3]))
        let b = root(Int(membrane.indices[t * 3 + 1]))
        let c = root(Int(membrane.indices[t * 3 + 2]))
        parent[b] = a
        parent[root(c)] = root(a)
    }
    let pieces: Int = Set((0..<points.count).map { root($0) }).count
    check("M2a \(name): one piece (soma and dendrites one surface)", pieces == 1, "\(pieces) pieces")

    // M3 - on the surface
    let off: [Float] = points.map { abs(field.distance($0)) }
    let worst: Float = off.max() ?? 0
    let close: Int = off.filter { $0 < 0.1 * h }.count
    check("M3a \(name): every vertex within a quarter step of the surface", worst < 0.25 * h, "\(worst)")
    check("M3b \(name): 99% within a tenth of a step", Float(close) >= 0.99 * Float(points.count),
          "\(close) of \(points.count)")

    // M4 - normals out
    let units: Bool = membrane.normals.allSatisfy { abs(length($0) - 1) < 0.001 }
    check("M4a \(name): one unit normal per vertex", membrane.normals.count == points.count && units)
    var agree: Int = 0
    var volume: Float = 0
    for t in 0..<tris {
        let i0 = Int(membrane.indices[t * 3]), i1 = Int(membrane.indices[t * 3 + 1]), i2 = Int(membrane.indices[t * 3 + 2])
        let face: SIMD3<Float> = cross(points[i1] - points[i0], points[i2] - points[i0])
        let mean: SIMD3<Float> = membrane.normals[i0] + membrane.normals[i1] + membrane.normals[i2]
        if dot(face, mean) > 0 { agree += 1 }
        volume += dot(points[i0], cross(points[i1], points[i2])) / 6
    }
    check("M4b \(name): triangles face the way their normals point", Float(agree) >= 0.995 * Float(tris),
          "\(agree) of \(tris)")
    let sphere: Float = 4 / 3 * Float.pi
    check("M4c \(name): wound outwards (positive volume, more than the soma's)", volume > sphere && volume < 4 * sphere,
          "\(volume)")
    let outward: Int = (0..<points.count).filter { dot(membrane.normals[$0], points[$0]) > 0 }.count
    check("M4d \(name): normals point away from the centre almost everywhere",
          Float(outward) > 0.9 * Float(points.count), "\(outward) of \(points.count)")

    // M5 - the shape
    check("M5a \(name): the centre is inside", field.distance(SIMD3<Float>(0, 0, 0)) < -0.9)
    let top: SIMD3<Float> = points.max { $0.z < $1.z } ?? SIMD3<Float>(0, 0, 0)
    let bottom: SIMD3<Float> = points.min { $0.z < $1.z } ?? SIMD3<Float>(0, 0, 0)
    check("M5b \(name): the soma round where no dendrite leaves it (top and bottom at its radius)",
          abs(length(top) - 1) < 0.05 && abs(length(bottom) - 1) < 0.05, "\(length(top)) \(length(bottom))")
    for (n, branch) in branches.enumerated() {
        let reach: Float = points.map { dot($0, branch.end) / length(branch.end) }.max() ?? 0
        let tip: Float = length(branch.end)
        check("M5c \(name): dendrite \(n) covered to its rounded tip",
              field.distance(branch.end) < 0 && abs(reach - (tip + branch.r1)) < 0.08, "\(reach) for \(tip)")
    }
    // halfway between two neighbouring dendrites, well out from the soma,
    // is outside: the blend webs their bases, it does not melt the crown
    // into a disc
    var webbed: [String] = []
    var compared: Int = 0
    for n in 0..<branches.count {
        let a: SIMD3<Float> = branches[n].point(0.8)
        let b: SIMD3<Float> = branches[(n + 1) % branches.count].point(0.8)
        let mid: SIMD3<Float> = (a + b) * 0.5
        guard length(a - b) > 0.7 && length(mid) > 1.25 else { continue }
        compared += 1
        if field.distance(mid) <= 0 { webbed.append("\(n): \(field.distance(mid)) at \(length(mid))") }
    }
    check("M5d \(name): neighbouring dendrites stay apart out along them", compared >= 3 && webbed.isEmpty,
          "\(compared) compared; \(webbed)")

    // M6 - what the shader reads
    let inRange: Bool = membrane.coords.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }
    check("M6a \(name): one (along, soma) pair per vertex, both 0 to 1",
          membrane.coords.count == points.count && inRange)
    let topAt: Int = points.firstIndex(of: top) ?? 0
    check("M6b \(name): the soma's top is all soma, at the start of nothing",
          membrane.coords[topAt].y > 0.95 && membrane.coords[topAt].x < 0.05, "\(membrane.coords[topAt])")
    var tipsOK: Bool = true
    for branch in branches {
        let near: Int = (0..<points.count).min { length(points[$0] - branch.end) < length(points[$1] - branch.end) } ?? 0
        if !(membrane.coords[near].y < 0.05 && membrane.coords[near].x > 0.9) { tipsOK = false }
    }
    check("M6c \(name): at every tip, all dendrite and all the way along", tipsOK)

    // M7 - cost, made once per variant
    check("M7a \(name): made in under a second even unoptimised (the previews, Swift Playgrounds)", took < 1, "\(took) s")
    let again: NeuronMembrane = NeuronMembrane.make(branches)
    check("M7b \(name): the same every time", again.points == membrane.points && again.indices == membrane.indices)
}

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
