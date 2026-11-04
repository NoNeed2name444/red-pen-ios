// The bundled 3D anatomy atlas, read the way the app reads it: both bodies,
// every part's file matches the manifest, every mesh is whole and inside its
// body, sides are where their labels say, the repaired femur is a closed
// solid, and the labels and sources are clean.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let folder = URL(fileURLWithPath: "ios/RedPen/Resources/Anatomy")
guard let manifestData = try? Data(contentsOf: folder.appendingPathComponent("anatomy.json")),
      let manifest = try? AnatomyAtlas.manifest(from: manifestData),
      let male = manifest.body(.male), let female = manifest.body(.female) else {
    print("FAIL the manifest reads, with a male and a female body")
    exit(1)
}
check("the manifest reads, format 2, two bodies", manifest.format == 2 && manifest.bodies.map(\.id) == [.male, .female])
check("every source is pinned, with a DOI or (the NIH 3D skull, the Visible Human CT) its page; each CC BY 4.0 but the CT, under NLM's terms",
      manifest.sources.count == 6 && manifest.sources.allSatisfy {
          ($0.licence == "CC BY 4.0" || ($0.id == "nlm-visible-human-ct" && $0.licence.hasPrefix("NLM Terms and Conditions")))
            && $0.sha256.count == 64 && $0.url.hasPrefix("https://")
            && ($0.doi?.hasPrefix("https://doi.org/") ?? ["nih3d-3dpx-020591", "nlm-visible-human-ct"].contains($0.id))
      }, manifest.sources.map(\.id).joined(separator: ", "))
check("each body names its own source", Set(manifest.bodies.map(\.source)).count == 2
      && manifest.bodies.allSatisfy { b in manifest.sources.contains { $0.id == b.source } })
check("44 male parts and 45 female, ids unique in each",
      male.parts.count == 44 && female.parts.count == 45
      && manifest.bodies.allSatisfy { Set($0.parts.map(\.id)).count == $0.parts.count },
      "\(male.parts.count), \(female.parts.count)")
let femaleOnly: Set<String> = ["breasts", "ovaries", "uterine-tubes", "uterus", "vagina", "uterine-ligaments"]
let maleOnly: Set<String> = ["urethra", "genital-ducts", "prostate", "hyoid", "larynx-muscles"]
let maleIds = Set(male.parts.map(\.id)), femaleIds = Set(female.parts.map(\.id))
check("every other part is in both bodies",
      maleIds.subtracting(femaleIds) == maleOnly && femaleIds.subtracting(maleIds) == femaleOnly,
      "male only \(maleIds.subtracting(femaleIds).sorted()), female only \(femaleIds.subtracting(maleIds).sorted())")
for body in manifest.bodies {
    let structures = body.parts.flatMap(\.structures)
    check("\(body.name): node names unique, each with its body's prefix",
          Set(structures.map(\.node)).count == structures.count
          && structures.allSatisfy {
              $0.node.hasPrefix(body.id == .male ? "VH_M_" : "VH_F_") || $0.node.hasPrefix("Allen_")
                || $0.node.hasPrefix("NLM_") || $0.node.hasPrefix("TS_")
          })
    check("\(body.name): every body system has a part",
          Set(body.parts.map(\.system)) == Set(AnatomySystem.allCases),
          "\(Set(AnatomySystem.allCases).subtracting(body.parts.map(\.system)))")
}
check("1030 male structures and 1064 female",
      male.parts.flatMap(\.structures).count == 1030 && female.parts.flatMap(\.structures).count == 1064,
      "\(male.parts.flatMap(\.structures).count), \(female.parts.flatMap(\.structures).count)")
check("the body for a topic's parts: the one that has them all",
      manifest.body(for: ["heart"]) == .male && manifest.body(for: ["heart"], preferred: .female) == .female
      && manifest.body(for: ["uterus", "ovaries"]) == .female && manifest.body(for: ["prostate"], preferred: .female) == .male
      && manifest.body(for: ["kidneys", "bladder", "urethra"]) == .male && manifest.body(for: []) == .male)
check("the remembered body reads back, and an unreadable one is the man's",
      AnatomySex(remembered: "female") == .female && AnatomySex(remembered: "") == .male
        && AnatomySex(remembered: "nonsense") == .male && AnatomySex.rememberedKey == "sciences.atlas.body")
check("a part's name is found in whichever body has it",
      manifest.part("uterus")?.name == "Uterus" && manifest.part("prostate")?.name == "Prostate" && manifest.part("nope") == nil)

// MARK: every file, read

var meshes: [String: [AnatomyMesh]] = [:]
var readErrors: [String] = []
for body in manifest.bodies {
    for part in body.parts {
        let url = folder.appendingPathComponent(part.file)
        guard let data = try? Data(contentsOf: url) else { readErrors.append("\(part.file): missing"); continue }
        if data.count != part.bytes { readErrors.append("\(part.file): \(data.count) bytes, manifest \(part.bytes)") }
        do { meshes[part.file] = try AnatomyAtlas.meshes(of: part, from: data) } catch { readErrors.append("\(part.file): \(error)") }
    }
}
check("every part's file is there, its size as listed, and reads whole", readErrors.isEmpty, readErrors.joined(separator: "; "))
check("each body's files are its own",
      manifest.bodies.allSatisfy { b in b.parts.allSatisfy { $0.file == "\(b.id.rawValue)-\($0.id).atlas" } })

for body in manifest.bodies {
    let parts = body.parts
    let mismatched: [String] = parts.flatMap { part in
        zip(part.structures, meshes[part.file] ?? []).compactMap { s, m in m.triangleCount == s.triangles ? nil : s.node }
    }
    check("\(body.name): every structure has the triangles the manifest says", mismatched.isEmpty, mismatched.prefix(5).joined(separator: ", "))
    let total: Int = parts.map(\.triangles).reduce(0, +)
    check("\(body.name): between 530,000 and 600,000 triangles", (530_000...600_000).contains(total), "\(total)")
    let empty = parts.flatMap { p in zip(p.structures, meshes[p.file] ?? []).filter { $0.1.triangleCount == 0 }.map { $0.0.node } }
    check("\(body.name): no structure is empty", empty.isEmpty, empty.joined(separator: ", "))
    let outside: [String] = parts.compactMap { part in
        guard let ms = meshes[part.file], part.bounds.count == 6 else { return part.id }
        for m in ms {
            for i in 0..<m.vertexCount {
                let p = m.position(i)
                for a in 0..<3 where p[a] < part.bounds[a] - 1e-4 || p[a] > part.bounds[a + 3] + 1e-4 { return part.id }
            }
        }
        return nil
    }
    check("\(body.name): every position lies in its part's bounds", outside.isEmpty, outside.joined(separator: ", "))
    let skin = body.part("skin")!.bounds
    let beyond = parts.filter { p in (0..<3).contains { p.bounds[$0] < skin[$0] - 0.02 || p.bounds[$0 + 3] > skin[$0 + 3] + 0.02 } }
    check("\(body.name): every part lies inside the skin's box", beyond.isEmpty, beyond.map(\.id).joined(separator: ", "))
}
let maleHeight: Float = male.part("skin")!.bounds[4] - male.part("skin")!.bounds[1]
let femaleHeight: Float = female.part("skin")!.bounds[4] - female.part("skin")!.bounds[1]
check("the man is about 1.82 m tall, the woman about 1.66 m",
      abs(maleHeight - 1.82) < 0.05 && abs(femaleHeight - 1.66) < 0.05, "\(maleHeight), \(femaleHeight)")

// MARK: geometry

/// The middle of a structure, by node name, in one body.
func centre(_ node: String, in body: AnatomyBody) -> SIMD3<Float>? {
    for part in body.parts {
        if let i = part.structures.firstIndex(where: { $0.node == node }), let m = meshes[part.file]?[i] { return m.centre }
    }
    return nil
}
/// One structure's mesh, by node name.
func mesh(_ node: String, in body: AnatomyBody) -> AnatomyMesh? {
    for part in body.parts {
        if let i = part.structures.firstIndex(where: { $0.node == node }) { return meshes[part.file]?[i] }
    }
    return nil
}
let places: [(AnatomyBody, String, heart: String, liver: String)] = [
    (male, "VH_M_", "VH_M_heart_left_ventricle", "VH_M_liver_capsule"),
    (female, "VH_F_", "VH_F_left_ventricle", "VH_F_capsule_of_the_liver"),
]
for (body, prefix, heartNode, liverNode) in places {
    let heart: SIMD3<Float> = centre(heartNode, in: body) ?? SIMD3(-9, -9, -9)
    let liverX: Float = centre(liverNode, in: body)?.x ?? 9
    let brainY: Float = centre("Allen_head_of_caudate_L", in: body)?.y ?? -9
    let bladderY: Float = centre(prefix + "trigone_of_urinary_bladder", in: body)?.y ?? 9
    let spineZ: Float = centre(prefix + "thoracic_vertebra_6", in: body)?.z ?? 9
    check("\(body.name): the heart lies left of the midline (x > 0)", heart.x > 0, "\(heart.x)")
    check("\(body.name): the liver lies on the right (x < 0)", liverX < 0, "\(liverX)")
    check("\(body.name): the brain is above the heart, the bladder below", brainY > heart.y && bladderY < heart.y)
    check("\(body.name): the spine is behind the heart (z smaller)", spineZ < heart.z)
    check("\(body.name): the vertebrae run in order down the column", {
        let names = ["cervical_vertebra_1", "cervical_vertebra_7", "thoracic_vertebra_1", "thoracic_vertebra_12",
                     "lumbar_vertebra_1", "lumbar_vertebra_5"].map { prefix + $0 }
        let ys = names.compactMap { centre($0, in: body)?.y }
        return ys.count == names.count && zip(ys, ys.dropFirst()).allSatisfy { $0 > $1 }
    }())
    check("\(body.name): the brain's left half is on the body's left (mirrored from the organ set)",
          (centre("Allen_thalamus_L", in: body)?.x ?? -1) > 0 && (centre("Allen_thalamus_R", in: body)?.x ?? 1) < 0)
}

// Labelled sides against where the structure is: x > 0 is the body's left.
// Named left or right for the organ, not the body: the right ventricle
// lies left of the midline with the rest of the heart (and in the female
// heart, turned further, the right coronary artery's start), and the left
// liver's vessels, ducts and medial segments lie right of it.
let organSided: Set<String> = [
    "VH_M_heart_right_ventricle", "VH_M_left_hepatic_artery", "VH_M_left_hepatic_vein",
    "VH_M_left_branch_of_portal_vein", "VH_M_left_superiomedial_segment",
    "VH_M_left_inferomedial_segment", "VH_M_left_hepatic_duct",
    "VH_F_right_ventricle", "VH_F_right_coronary_artery", "VH_F_left_branch_of_portal_vein",
    "VH_F_left_superomedial_segment1", "VH_F_left_inferomedial_segment", "VH_F_left_hepatic_duct",
]
for body in manifest.bodies {
    var sided = 0, wrongSide: [String] = []
    for part in body.parts {
        for (s, m) in zip(part.structures, meshes[part.file] ?? []) {
            let left = s.label.hasPrefix("left "), right = s.label.hasPrefix("right ")
            guard left || right else { continue }
            sided += 1
            // within a centimetre of the midline is on it (the third ventricle's halves)
            if (left && m.centre.x < -0.01) || (right && m.centre.x > 0.01) { wrongSide.append(s.node) }
        }
    }
    let misplaced: [String] = wrongSide.filter { !organSided.contains($0) }
    check("\(body.name): left and right labels are on their side (\(sided) checked)", sided > 500 && misplaced.isEmpty,
          misplaced.prefix(8).joined(separator: ", "))
}
check("the swapped renal arteries are named for the kidney they reach",
      male.parts.flatMap(\.structures).first { $0.node == "VH_M_left_renal_artery" }?.label == "right renal artery"
      && (centre("VH_M_left_renal_artery", in: male)?.x ?? 1) < 0)
check("the ovaries, uterine tubes and breasts are on their sides", {
    let pairs = [("VH_F_left_ovary", "VH_F_right_ovary"), ("VH_F_nipple_L", "VH_F_nipple_R")]
    return pairs.allSatisfy { l, r in (centre(l, in: female)?.x ?? -1) > 0 && (centre(r, in: female)?.x ?? 1) < 0 }
}())
check("the uterus lies behind the bladder and above the vagina", {
    guard let uterus = centre("VH_F_body_of_uterus", in: female), let bladder = centre("VH_F_trigone_of_urinary_bladder", in: female),
          let cervix = centre("VH_F_cervix", in: female) else { return false }
    return uterus.z < bladder.z + 0.03 && uterus.y > cervix.y
}())

/// Signed volume: positive when the triangles wind counter-clockwise seen
/// from outside, so the normals point out. Only meaningful for a closed
/// surface, whose volume does not depend on where the origin is.
func volume(_ meshes: [AnatomyMesh]) -> Float {
    var v: Float = 0
    for m in meshes {
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let a = m.position(Int(m.indices[t])), b = m.position(Int(m.indices[t + 1])), c = m.position(Int(m.indices[t + 2]))
            let n = SIMD3(b.y * c.z - b.z * c.y, b.z * c.x - b.x * c.z, b.x * c.y - b.y * c.x)
            v += (a * n).sum() / 6
        }
    }
    return v
}
/// Edges only one triangle has, across these meshes: none on a closed surface.
func openEdges(_ meshes: [AnatomyMesh]) -> Int {
    struct Point: Hashable { let x, y, z: Float }
    var count: [[Point]: Int] = [:]
    for m in meshes {
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            for (i, j) in [(0, 1), (1, 2), (2, 0)] {
                let a = m.position(Int(m.indices[t + i])), b = m.position(Int(m.indices[t + j]))
                let pa = Point(x: a.x, y: a.y, z: a.z), pb = Point(x: b.x, y: b.y, z: b.z)
                let key = (pa.x, pa.y, pa.z) < (pb.x, pb.y, pb.z) ? [pa, pb] : [pb, pa]
                count[key, default: 0] += 1
            }
        }
    }
    return count.values.filter { $0 == 1 }.count
}
for (body, prefix, range, length) in [(male, "VH_M_", 6.0e-4...7.0e-4, Float(0.49)), (female, "VH_F_", 5.0e-4...5.8e-4, Float(0.43))] {
    let femur = mesh(prefix + "femur_L", in: body)!
    let knee = mesh(prefix + "articular_cartilage_of_knee_L", in: body)!
    let edges = openEdges([femur, knee])
    let solid = volume([femur, knee])
    check("\(body.name): the femur's lower end is repaired: with its cartilage a closed solid (\(edges) open edges)", edges == 0)
    check("\(body.name): the femur faces outward, its volume with its cartilage \(Int(solid * 1e6)) cm³", range.contains(Double(solid)))
    var lo: Float = 9, hi: Float = -9
    for i in 0..<femur.vertexCount { lo = min(lo, femur.position(i).y); hi = max(hi, femur.position(i).y) }
    check("\(body.name): the femur is about \(Int(length * 100)) cm long", abs((hi - lo) - length) < 0.03, "\(hi - lo)")
    let normals = femur.normals()
    let unit: Bool = stride(from: 0, to: normals.count, by: 3).allSatisfy { i in
        let x: Float = normals[i], y: Float = normals[i + 1], z: Float = normals[i + 2]
        return abs(x * x + y * y + z * z - 1) < 1e-3
    }
    check("\(body.name): smooth normals, one per vertex, unit length", normals.count == femur.positions.count && unit)
}
check("the mirrored brain still faces outward", volume([mesh("Allen_thalamus_L", in: male)!]) > 0)

// MARK: shading a part as one surface

/// A strip of a cylinder's side (radius 1, height 1) through these angles, in
/// degrees, its triangles facing out.
func strip(_ degrees: [Float]) -> AnatomyMesh {
    var positions: [Float] = [], indices: [UInt32] = []
    for z: Float in [0, 1] {
        for d in degrees { positions += [cos(d * .pi / 180), sin(d * .pi / 180), z] }
    }
    let n = UInt32(degrees.count)
    for i in 0..<(n - 1) { indices += [i, i + 1, n + i + 1, i, n + i + 1, n + i] }
    return AnatomyMesh(positions: positions, indices: indices)
}
func normal(_ normals: [Float], _ v: Int) -> SIMD3<Float> { SIMD3(normals[3 * v], normals[3 * v + 1], normals[3 * v + 2]) }
/// The angle between two unit vectors, in degrees (to about 0.02°: a Float's acos near 1).
func degrees(between a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { acos(min(1, max(-1, (a * b).sum()))) * 180 / .pi }
do {
    // a quarter of the cylinder cut in two along its length at 60°
    let whole = strip([0, 30, 60, 90]), lower = strip([0, 30, 60]), upper = strip([60, 90])
    let welded = AnatomyMesh.normals(welding: [lower, upper])
    let cut = degrees(between: normal(lower.normals(), 2), normal(upper.normals(), 0))
    let error = degrees(between: normal(welded[0], 2), normal(whole.normals(), 2))
    check("a surface cut in two shades as one: at the cut both sides take the whole's normal (apart \(Int(cut))° off)",
          cut > 20 && error < 0.1 && degrees(between: normal(welded[0], 2), normal(welded[1], 0)) < 0.1)
    // a thin plate's two faces, meeting at the same three places facing apart
    let top = AnatomyMesh(positions: [0, 0, 0, 1, 0, 0, 0, 1, 0], indices: [0, 1, 2])
    let bottom = AnatomyMesh(positions: [0, 0, 0, 1, 0, 0, 0, 1, 0], indices: [0, 2, 1])
    let plate = AnatomyMesh.normals(welding: [top, bottom])
    check("a thin plate's two faces keep their own normals", normal(plate[0], 0).z > 0.99 && normal(plate[1], 0).z < -0.99)
}
for body in manifest.bodies {
    // the skull, cut into its named bones: wherever two bones meet, the same place on each
    let pieces: [AnatomyMesh] = meshes[body.part("skull")!.file] ?? []
    let own: [[Float]] = pieces.map { $0.normals() }, welded = AnatomyMesh.normals(welding: pieces)
    struct Place: Hashable { let x, y, z: Float }
    var at: [Place: [(piece: Int, vertex: Int)]] = [:]
    for (k, m) in pieces.enumerated() {
        for v in 0..<m.vertexCount {
            let p = m.position(v)
            at[Place(x: p.x, y: p.y, z: p.z), default: []].append((k, v))
        }
    }
    var apart: [Float] = [], after: Float = 0
    for members in at.values where Set(members.map(\.piece)).count > 1 {
        let a = members[0], b = members.first { $0.piece != a.piece }!
        let before = degrees(between: normal(own[a.piece], a.vertex), normal(own[b.piece], b.vertex))
        apart.append(before)
        if before < 70 { after = max(after, degrees(between: normal(welded[a.piece], a.vertex), normal(welded[b.piece], b.vertex))) }
    }
    let median: Float = apart.isEmpty ? 0 : apart.sorted()[apart.count / 2]
    check("\(body.name): the skull's bones shade as one surface: where they meet (\(apart.count) places) their normals agree "
          + "(largest gap \(String(format: "%.2f", after))°; shaded apart, a median of \(Int(median))°)",
          apart.count > 100 && after < 0.5 && median > 5)
}

// MARK: the relief: how a part's surface bends

/// A sphere of radius r: an icosahedron's triangles cut in four `levels`
/// times, its points pushed out onto the sphere, its triangles facing out.
func icosphere(_ r: Float, levels: Int) -> AnatomyMesh {
    let g: Float = (1 + Float(5).squareRoot()) / 2
    var points: [SIMD3<Float>] = [(-1, g, 0), (1, g, 0), (-1, -g, 0), (1, -g, 0), (0, -1, g), (0, 1, g),
                                  (0, -1, -g), (0, 1, -g), (g, 0, -1), (g, 0, 1), (-g, 0, -1), (-g, 0, 1)]
        .map { SIMD3<Float>($0.0, $0.1, $0.2) }
    var faces: [[Int]] = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
                          [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8],
                          [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
    for _ in 0..<levels {
        var middles: [Int: Int] = [:]
        func middle(_ a: Int, _ b: Int) -> Int {
            let key = min(a, b) << 20 | max(a, b)
            if let known = middles[key] { return known }
            points.append((points[a] + points[b]) / 2)
            middles[key] = points.count - 1
            return points.count - 1
        }
        faces = faces.flatMap { f -> [[Int]] in
            let a = middle(f[0], f[1]), b = middle(f[1], f[2]), c = middle(f[2], f[0])
            return [[f[0], a, c], [f[1], b, a], [f[2], c, b], [a, b, c]]
        }
    }
    let positions: [Float] = points.flatMap { p -> [Float] in
        let q = p / (p * p).sum().squareRoot() * r
        return [q.x, q.y, q.z]
    }
    return AnatomyMesh(positions: positions, indices: faces.flatMap { $0.map(UInt32.init) })
}
do {
    // a ball 10 cm across, 642 points
    let ball = icosphere(0.05, levels: 3)
    let bends = AnatomyMesh.curvature(welding: [ball])[0]
    check("a ball 10 cm across bends by 1/r, 20 per metre, at every point (\(String(format: "%.1f...%.1f", bends.min()!, bends.max()!)))",
          volume([ball]) > 0 && bends.allSatisfy { abs($0 - 20) < 0.4 })
    // the same ball turned inside out: a hollow
    var inside = ball
    for t in stride(from: 0, to: inside.indices.count, by: 3) { inside.indices.swapAt(t + 1, t + 2) }
    let hollow = AnatomyMesh.curvature(welding: [inside])[0]
    check("inside out, it is a hollow, -20 per metre", hollow.allSatisfy { abs($0 + 20) < 0.4 })
    // cut in two at its equator, each half with its own copy of the points on the cut
    var halves: [AnatomyMesh] = []
    for north in [true, false] {
        var positions: [Float] = [], indices: [UInt32] = [], index: [UInt32: UInt32] = [:]
        for t in stride(from: 0, to: ball.indices.count, by: 3) {
            let corners = ball.indices[t..<(t + 3)]
            let z = corners.map { ball.position(Int($0)).z }.reduce(0, +)
            guard (z > 0) == north else { continue }
            for v in corners {
                if index[v] == nil {
                    index[v] = UInt32(positions.count / 3)
                    let p = ball.position(Int(v))
                    positions += [p.x, p.y, p.z]
                }
                indices.append(index[v]!)
            }
        }
        halves.append(AnatomyMesh(positions: positions, indices: indices))
    }
    let cut = AnatomyMesh.curvature(welding: halves)
    let whole: [SIMD3<Float>: Float] = Dictionary((0..<ball.vertexCount).map { (ball.position($0), bends[$0]) }) { a, _ in a }
    let worst: Float = zip(halves, cut).flatMap { half, values in
        (0..<half.vertexCount).map { abs(values[$0] - (whole[half.position($0)] ?? .infinity)) }
    }.max() ?? .infinity
    check("cut in two, it bends just as the whole does, on the cut too (largest difference \(String(format: "%.4f", worst)) per metre)",
          worst < 0.001)
    // the shade: none where the surface is flat or bulges, or hollow over a span
    let flat = AtlasRelief.shade(0), bulge = AtlasRelief.shade(40), wide = AtlasRelief.shade(-12)
    let groove = AtlasRelief.shade(-400), half = AtlasRelief.shade(-(AtlasRelief.start + AtlasRelief.full) / 2)
    check("the relief leaves flat and bulging surfaces and a wide hollow their colour, darkens a tight one to its depth, warming it",
          [flat, bulge, wide].allSatisfy { $0 == SIMD3<Float>(1, 1, 1) }
          && abs(groove.x - AtlasRelief.depth) < 1e-6 && groove.z < groove.y && groove.y < groove.x
          && half.x > AtlasRelief.depth && half.x < 1)
}
for body in manifest.bodies {
    // the vault's outer face (above the skull's middle, facing away from it) bulges, about as a ball its size does;
    // the skull from the CT has its inner table too, which hollows round the brain, so the whole bends both ways
    let pieces: [AnatomyMesh] = meshes[body.part("skull")!.file] ?? []
    let curvature = AnatomyMesh.curvature(welding: pieces), facing = AnatomyMesh.normals(welding: pieces)
    let bends: [Float] = curvature.flatMap { $0 }
    let points: [SIMD3<Float>] = pieces.flatMap { m in (0..<m.vertexCount).map(m.position) }
    let centre: SIMD3<Float> = points.reduce(.zero, +) / Float(max(points.count, 1))
    var outer: [Float] = []
    for (k, m) in pieces.enumerated() {
        for v in 0..<m.vertexCount {
            let p = m.position(v)
            if p.y > centre.y && ((p - centre) * normal(facing[k], v)).sum() > 0 { outer.append(curvature[k][v]) }
        }
    }
    outer.sort()
    let median: Float = outer.isEmpty ? 0 : outer[outer.count / 2]
    let hollows: Int = bends.filter { AtlasRelief.shade($0).x < 0.95 }.count
    check("\(body.name): the skull's vault bulges (a median of \(Int(median)) per metre over its outer face) with hollows "
          + "in the skull (\(hollows) of \(bends.count) points shaded), every value finite",
          !bends.isEmpty && bends.allSatisfy(\.isFinite) && median > 5 && median < 60 && hollows > bends.count / 100)
}

// MARK: the surfaces' inputs

do {
    // a rod 10 cm long and 1 cm thick, lying along the diagonal of x and y
    let along = SIMD3<Float>(1, 1, 0) / Float(2).squareRoot(), across = SIMD3<Float>(0, 0, 1)
    var positions: [Float] = []
    for k in 0..<200 {
        let t = Float(k % 20) / 19 - 0.5, s = Float(k / 20) / 9 - 0.5
        let p = along * (t * 0.1) + across * (s * 0.01) + SIMD3<Float>(0.3, 1.2, -0.1)
        positions += [p.x, p.y, p.z]
    }
    let axis = AnatomyMesh(positions: positions, indices: []).longAxis()
    check("a rod's long axis is found along it (\(String(format: "%.2f", degrees(between: axis, along).truncatingRemainder(dividingBy: 180)))° off)",
          abs((axis * along).sum()) > 0.9998)
}
for body in manifest.bodies {
    let prefix: String = body.id == .male ? "VH_M_" : "VH_F_"
    let thighs: [SIMD3<Float>] = ["rectus_femoris_L", "rectus_femoris_R"].compactMap { mesh(prefix + $0, in: body)?.longAxis() }
    check("\(body.name): the rectus femoris runs down the thigh, as its fibres do",
          thighs.count == 2 && thighs.allSatisfy { abs($0.y) > 0.9 }, "\(thighs)")
}
check("every tissue has a roughness for the physically based materials: bone matte, the eye and fluid glossy",
      AnatomyTissue.allCases.allSatisfy { (0.1...0.7).contains($0.roughness) }
      && AnatomyTissue.bone.roughness >= 0.55 && AnatomyTissue.eye.roughness < 0.2 && AnatomyTissue.fluid.roughness < 0.2)
for body in manifest.bodies {
    let lungs = body.part("lungs")!
    let segments = meshes[lungs.file] ?? []
    let apart: Int = segments.map { openEdges([$0]) }.reduce(0, +)
    let together: Int = openEdges(segments)
    check("\(body.name): the lung's \(segments.count) segments meet without cracks (\(apart) open edges apart, \(together) together)",
          together <= 20 && apart > 1000)
}

// MARK: reading errors

check("a file that is not an atlas is refused", (try? AnatomyAtlas.meshes(from: Data(repeating: 0, count: 64))) == nil)
let first = try! Data(contentsOf: folder.appendingPathComponent(male.parts[0].file))
check("a cut-off file is refused", {
    do { _ = try AnatomyAtlas.meshes(from: first.prefix(first.count - 7)); return false } catch { return true }
}())
check("a file with bytes left over is refused", {
    do { _ = try AnatomyAtlas.meshes(from: first + Data([0, 0, 0, 0])); return false }
    catch AnatomyAtlas.ReadError.leftover { return true } catch { return false }
}())
check("a part read against another's manifest entry is refused", {
    do { _ = try AnatomyAtlas.meshes(of: male.part("brain")!, from: first); return false } catch { return true }
}())

// MARK: the parts the organ sets lack (tools/anatomy_gaps.py)

let added: Set<String> = ["skull", "sternum", "ribs", "shoulders", "arms", "hip-muscles", "back-muscles",
                          "thyroid", "adrenals", "oesophagus", "stomach"]
let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
                "eleventh", "twelfth"]
for body in manifest.bodies {
    let ids = Set(body.parts.map(\.id))
    check("\(body.name): the skull, ribs, sternum, shoulders, arms, hip and back muscles, thyroid, adrenals, oesophagus and stomach",
          added.isSubset(of: ids), "\(added.subtracting(ids).sorted())")
    let ribs = body.part("ribs")?.structures.filter { $0.node.hasPrefix("TS_rib_") } ?? []
    let wanted = Set(["left", "right"].flatMap { side in ordinals.map { "\(side) \($0) rib" } })
    check("\(body.name): twelve ribs a side, each named for its place", ribs.count == 24 && Set(ribs.map(\.label)) == wanted,
          "\(ribs.count)")
    check("\(body.name): the ribs run down in order, each side",
          ["L", "R"].allSatisfy { s in
              let ys = (1...12).compactMap { centre("TS_rib_\($0)_\(s)", in: body)?.y }
              return ys.count == 12 && zip(ys, ys.dropFirst()).allSatisfy { $0 > $1 }
          })
    let skull = body.part("skull")?.structures ?? []
    check("\(body.name): the skull's thirteen bones, the paired ones left and right (20 pieces, all bone)",
          skull.count == 20 && skull.allSatisfy { $0.tissue == .bone && $0.node.hasPrefix("NLM_") })
    // the brain inside the skull, to within half a centimetre
    let brain = body.part("brain")!.bounds, vault = body.part("skull")!.bounds
    check("\(body.name): the brain lies within the skull",
          (0..<3).allSatisfy { brain[$0] > vault[$0] - 0.005 && brain[$0 + 3] < vault[$0 + 3] + 0.005 },
          "\(brain) in \(vault)")
    // each humerus's head at its own shoulder: its top within 6 cm of the clavicle's outer end
    for s in ["L", "R"] {
        guard let humerus = mesh("TS_humerus_\(s)", in: body), let clavicle = mesh("TS_clavicle_\(s)", in: body) else {
            check("\(body.name): the \(s) humerus and clavicle are there", false); continue
        }
        let top = (0..<humerus.vertexCount).map(humerus.position).max { $0.y < $1.y }!
        let outer = (0..<clavicle.vertexCount).map(clavicle.position).max { abs($0.x) < abs($1.x) }!
        let gap = ((top - outer) * (top - outer)).sum().squareRoot()
        check("\(body.name): the \(s == "L" ? "left" : "right") humerus's head is at its shoulder (\(Int(gap * 100)) cm from the clavicle's end)",
              gap < 0.06 && (s == "L" ? top.x > 0 : top.x < 0))
    }
    // the forearms and hands (tools/anatomy_limbs.py): 22 bones a side, the hand below the forearm below the
    // humerus, the radius and the thumb on the outer side (the body stands palms forward)
    let limb = body.part("arms")?.structures.filter { $0.group == "Forearm bones" || $0.group == "Hand bones" } ?? []
    check("\(body.name): 22 forearm and hand bones a side, each bone with its UBERON id",
          limb.count == 44 && limb.allSatisfy { $0.uberon != nil && $0.tissue == .bone } && Set(limb.map(\.node)).count == 44,
          "\(limb.count)")
    for (s, side) in [("L", "left"), ("R", "right")] {
        let outward: Float = s == "L" ? 1 : -1
        guard let humerus = centre("TS_humerus_\(s)", in: body), let radius = centre("TS_radius_\(s)", in: body),
              let ulna = centre("TS_ulna_\(s)", in: body), let tip = centre("TS_distal_phalanx_of_middle_finger_\(s)", in: body),
              let thumb = centre("TS_distal_phalanx_of_thumb_\(s)", in: body),
              let little = centre("TS_distal_phalanx_of_little_finger_\(s)", in: body) else {
            check("\(body.name): the \(side) forearm and hand are there", false); continue
        }
        check("\(body.name): the \(side) hand hangs below its forearm, the forearm below the humerus",
              tip.y < radius.y && radius.y < humerus.y)
        check("\(body.name): the \(side) radius and thumb lie on the outer side",
              outward * radius.x > outward * ulna.x && outward * thumb.x > outward * little.x)
    }
    // the arm's joints (tools/anatomy_gaps.py seat_humeri, tools/anatomy_elbows.py): the humerus meets its
    // scapula at the shoulder and its ulna and radius at the elbow (their nearest vertices within 8 mm: a
    // simplified mesh's vertices lie some millimetres apart), and the olecranon, the ulna's top, stands above
    // the humerus's lowest point, wrapping the trochlea from behind as it does with the arm straight
    func nearest(_ a: AnatomyMesh, _ b: AnatomyMesh) -> Float {
        let q = (0..<b.vertexCount).map(b.position)
        return (0..<a.vertexCount).map(a.position).reduce(Float.infinity) { best, p in
            q.reduce(best) { min($0, ((p - $1) * (p - $1)).sum()) }
        }.squareRoot()
    }
    for (s, side) in [("L", "left"), ("R", "right")] {
        guard let humerus = mesh("TS_humerus_\(s)", in: body), let scapula = mesh("TS_scapula_\(s)", in: body),
              let ulna = mesh("TS_ulna_\(s)", in: body), let radius = mesh("TS_radius_\(s)", in: body) else {
            check("\(body.name): the \(side) arm's joints are there", false); continue
        }
        let gaps = [scapula, ulna, radius].map { Int((nearest(humerus, $0) * 1000).rounded()) }
        let low = (0..<humerus.vertexCount).map(humerus.position).min { $0.y < $1.y }!
        let olecranon = (0..<ulna.vertexCount).map(ulna.position).max { $0.y < $1.y }!
        check("\(body.name): the \(side) humerus meets its scapula, ulna and radius (\(gaps.map(String.init).joined(separator: ", ")) mm)",
              gaps.allSatisfy { $0 < 8 })
        check("\(body.name): the \(side) olecranon stands above the humerus's lowest point",
              olecranon.y > low.y + 0.005, "\(Int(((olecranon.y - low.y) * 1000).rounded())) mm")
    }
    // the feet (tools/anatomy_feet.py): 27 bones a side (the great toe's two sesamoids as one), the talus at the
    // tibia's lower end (its middle about level with the tip of the medial malleolus, the tibia's lowest point,
    // which reaches down beside it), the heel bone below it, the toes in front of the heel and the great toe on the inner side
    let foot = body.part("legs")?.structures.filter { $0.group == "Foot bones" } ?? []
    check("\(body.name): 27 foot bones a side, each bone with its UBERON id",
          foot.count == 54 && foot.allSatisfy { $0.uberon != nil && $0.tissue == .bone } && Set(foot.map(\.node)).count == 54,
          "\(foot.count)")
    for (s, side) in [("L", "left"), ("R", "right")] {
        let outward: Float = s == "L" ? 1 : -1
        guard let tibia = mesh((body.id == .male ? "VH_M_" : "VH_F_") + "tibia_\(s)", in: body),
              let talus = centre("TS_talus_\(s)", in: body), let heel = centre("TS_calcaneus_\(s)", in: body),
              let great = centre("TS_distal_phalanx_of_great_toe_\(s)", in: body),
              let little = centre("TS_distal_phalanx_of_little_toe_\(s)", in: body) else {
            check("\(body.name): the \(side) foot is there", false); continue
        }
        let ankle = (0..<tibia.vertexCount).map(tibia.position).min { $0.y < $1.y }!
        let gap = ((talus - ankle) * (talus - ankle)).sum().squareRoot()
        check("\(body.name): the \(side) talus sits at its tibia's lower end (\(Int(gap * 1000)) mm), the heel bone below it",
              gap < 0.04 && talus.y < ankle.y + 0.012 && heel.y < talus.y)
        check("\(body.name): the \(side) toes lie in front of the heel, the great toe on the inner side",
              great.z > heel.z + 0.1 && little.z > heel.z + 0.08 && outward * great.x < outward * little.x)
    }
    // the hip bones whole (ilium, ischium and pubis): the ischium reaching well below the femur's head, the two
    // pubic bones meeting at the midline. The female organ set's own hip bone is the ilium alone; hers come from
    // her scan (tools/anatomy_gaps.py, whole_hips)
    func hipPoints(_ s: String) -> [SIMD3<Float>] {
        let nodes = body.id == .male ? ["ilium", "ischium", "pubis"].map { "VH_M_\($0)_compact_bone_\(s)" } : ["TS_hip_\(s)"]
        return nodes.compactMap { mesh($0, in: body) }.flatMap { m in (0..<m.vertexCount).map(m.position) }
    }
    let hipL = hipPoints("L"), hipR = hipPoints("R"), femurs = (body.id == .male ? "VH_M_" : "VH_F_") + "femur_"
    if let femurL = mesh(femurs + "L", in: body), let femurR = mesh(femurs + "R", in: body), !hipL.isEmpty, !hipR.isEmpty {
        let top = { (m: AnatomyMesh) -> Float in (0..<m.vertexCount).map { m.position($0).y }.max()! }
        let below = min(top(femurL) - hipL.map(\.y).min()!, top(femurR) - hipR.map(\.y).min()!)
        let gap = hipL.map(\.x).min()! - hipR.map(\.x).max()!
        check("\(body.name): each hip bone whole, reaching \(Int(below * 100)) cm below its femur's top; the pubic bones \(Int(gap * 1000)) mm apart",
              below > 0.04 && gap > -0.004 && gap < 0.012)
    } else {
        check("\(body.name): the hip bones and femurs are there", false)
    }
    // the thyroid in the neck, below the larynx's top and in front of the spine; the adrenals above the kidneys
    let thyroid = centre("TS_thyroid_gland", in: body) ?? SIMD3(9, 9, 9)
    let c7 = centre((body.id == .male ? "VH_M_" : "VH_F_") + "cervical_vertebra_7", in: body) ?? SIMD3(0, 0, 0)
    check("\(body.name): the thyroid sits in front of the neck's vertebrae", thyroid.z > c7.z && abs(thyroid.x) < 0.02)
    let stomach = centre("TS_stomach", in: body) ?? SIMD3(-9, -9, -9)
    check("\(body.name): the stomach lies on the left, below the heart",
          stomach.x > 0 && stomach.y < (body.part("heart").map { ($0.bounds[1] + $0.bounds[4]) / 2 } ?? 0))
    for (s, side) in [("L", "left"), ("R", "right")] {
        let gland = centre("TS_adrenal_gland_\(s)", in: body)
        let kidney = body.part("kidneys")!.structures.firstIndex { $0.label == "\(side) kidney" || $0.label.hasPrefix("\(side) kidney") }
        if let gland, let k = kidney, let m = meshes[body.part("kidneys")!.file]?[k] {
            check("\(body.name): the \(side) adrenal sits on the \(side) kidney's upper pole",
                  gland.y > m.centre.y && (s == "L" ? gland.x > 0 : gland.x < 0))
        } else {
            check("\(body.name): the \(side) adrenal and kidney are there", false)
        }
    }
}

// MARK: labels

let structures: [AnatomyStructure] = manifest.bodies.flatMap { $0.parts.flatMap(\.structures) }
func named(_ node: String) -> AnatomyStructure? { structures.first { $0.node == node } }
func cluttered(_ label: String) -> Bool {
    label.contains("Allen") || label.hasSuffix(" L") || label.hasSuffix(" R") || label.contains("_")
}
let clutter: [String] = structures.map(\.label).filter(cluttered)
check("labels carry no source clutter", clutter.isEmpty, clutter.prefix(5).joined(separator: ", "))
check("no label names a side twice",
      !structures.contains { $0.label.hasPrefix("left left") || $0.label.hasPrefix("right right") || $0.label.hasPrefix("left right") || $0.label.hasPrefix("right left") })
check("UBERON ids are well formed", structures.compactMap(\.uberon).allSatisfy { $0.range(of: #"^UBERON:\d{7}$"#, options: .regularExpression) != nil })
check("the crosswalk's mislabels are corrected",
      named("VH_M_superior_mesenteric_vein")?.label == "superior mesenteric vein"
      && named("VH_M_left_anterior_descending_artery")?.label.contains("left coronary") == true
      && named("VH_M_ilium_compact_bone_L")?.label == "left ilium"
      && named("VH_F_left_anterior_descending_artery")?.label.contains("left coronary") == true)
check("corrected labels drop the wrong UBERON id, or carry their own",
      named("VH_M_superior_mesenteric_vein")?.uberon == nil && named("VH_M_pubis_compact_bone_L")?.uberon == "UBERON:0001275"
        && named("VH_M_ischium_compact_bone_R")?.uberon == "UBERON:0001274")
check("the woman's whole hip bones, from her scan, stand in for her organ set's ilia",
      named("TS_hip_L")?.label == "left hip bone" && named("TS_hip_R")?.uberon == "UBERON:0001272"
        && named("VH_F_ilium_compact_bone_L") == nil)
check("the female set's sixth lumbar vertebra is named as the variant it is",
      named("VH_F_lumbar_vertebra_6")?.label.contains("normal variant") == true)
check("a structure from a scan says so; the organ sets' own say nothing",
      named("TS_stomach")?.origin?.contains("CT scan") == true && named("NLM_mandible")?.origin?.contains("own CT") == true
        && named("NLM_maxilla_L")?.origin?.hasPrefix("From the NIH 3D skull") == true && named("NLM_vomer")?.origin?.hasPrefix("From the NIH 3D skull") == true
        && named("NLM_sphenoid_bone")?.origin?.contains("own CT") == true
        && named("VH_M_femur_L")?.origin == nil && named("Allen_thalamus_L")?.origin == nil)
check("titles start with a capital", named("VH_M_femur_L")?.title == "Left femur" && named("VH_F_femur_L")?.title == "Left femur")
check("tissues: veins are veins, arteries arteries, bones bone, the breast's fat fat",
      named("VH_M_superior_vena_cava")?.tissue == .vein && named("VH_F_superior_vena_cava")?.tissue == .vein
      && named("VH_M_aortic_arch")?.tissue == .artery && named("VH_F_aortic_arch")?.tissue == .artery
      && named("VH_M_femur_R")?.tissue == .bone && named("VH_F_femur_R")?.tissue == .bone
      && named("VH_F_fat_L")?.tissue == .fat && named("VH_F_left_ovary")?.tissue == .gland)
for body in manifest.bodies {
    check("\(body.name): every part shows something before it is opened",
          body.parts.allSatisfy { $0.structures.contains { !$0.inner } },
          body.parts.filter { !$0.structures.contains { !$0.inner } }.map(\.id).joined(separator: ", "))
}
check("the liver shows its capsule (the female's with the bare area it lacks); its segments wait inside",
      male.part("liver")!.structures.filter { !$0.inner }.map(\.node) == ["VH_M_liver_capsule"]
      && female.part("liver")!.structures.filter { !$0.inner }.map(\.node) == ["VH_F_capsule_of_the_liver", "VH_F_bare_area_of_liver"])
check("the breast shows its skin and fat; the lobes and ducts wait inside",
      female.part("breasts")!.structures.filter(\.inner).allSatisfy { [.gland, .duct, .ligament].contains($0.tissue) }
      && female.part("breasts")!.structures.filter { !$0.inner }.allSatisfy { [.skin, .fat].contains($0.tissue) })

// MARK: search

for body in manifest.bodies {
    let p = body.id == .male ? "VH_M_" : "VH_F_"
    let femurs = Set(AnatomyAtlas.search("femur", in: body).map(\.structure.node))
    check("\(body.name): search finds both femurs", femurs.isSuperset(of: [p + "femur_L", p + "femur_R"]), "\(femurs)")
    let leftFemur = AnatomyAtlas.search("left femur", in: body).map(\.structure.node)
    check("\(body.name): search needs every word", leftFemur.contains(p + "femur_L") && !leftFemur.contains { $0.hasSuffix("_R") }, "\(leftFemur)")
    check("\(body.name): search finds the coronary arteries", AnatomyAtlas.search("coronary artery", in: body).count >= 4)
    check("\(body.name): an empty search finds nothing", AnatomyAtlas.search("  ", in: body).isEmpty)
}
check("search stays in its body", AnatomyAtlas.search("ovary", in: male).isEmpty
      && Set(AnatomyAtlas.search("ovary", in: female).map(\.structure.node)).isSuperset(of: ["VH_F_left_ovary", "VH_F_right_ovary"])
      && AnatomyAtlas.search("prostate", in: female).isEmpty)

// MARK: colours

check("every tissue has its own colour",
      Set(AnatomyTissue.allCases.map { "\($0.colour.red),\($0.colour.green),\($0.colour.blue)" }).count == AnatomyTissue.allCases.count)
check("arteries are red and veins blue",
      AnatomyTissue.artery.colour.red > AnatomyTissue.artery.colour.blue && AnatomyTissue.vein.colour.blue > AnatomyTissue.vein.colour.red)
check("only skin and fat are see-through, skin the fainter",
      AnatomyTissue.allCases.filter { $0.opacity < 1 } == [.skin, .fat] && AnatomyTissue.skin.opacity < AnatomyTissue.fat.opacity)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
