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
check("every source is pinned, with a DOI or (the NIH 3D skulls, the Visible Human CT) its page; each CC BY 4.0 but the CT, under NLM's terms",
      manifest.sources.count == 8 && manifest.sources.allSatisfy {
          ($0.licence == "CC BY 4.0" || ($0.id == "nlm-visible-human-ct" && $0.licence.hasPrefix("NLM Terms and Conditions")))
            && $0.sha256.count == 64 && $0.url.hasPrefix("https://")
            && ($0.doi?.hasPrefix("https://doi.org/") ?? ["nih3d-3dpx-020591", "nih3d-3dpx-012260", "nlm-visible-human-ct"].contains($0.id))
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
check("1033 male structures and 1064 female",
      male.parts.flatMap(\.structures).count == 1033 && female.parts.flatMap(\.structures).count == 1064,
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
let hearts: [String] = male.parts.filter { $0.system == .cardiovascular }.map(\.id)
check("a body reads only the layers shown, and a topic's parts alone while only they are shown",
      male.parts(showing: [.cardiovascular], focus: ["heart"], alone: true).map(\.id) == ["heart"]
        && male.parts(showing: [.cardiovascular], focus: ["heart"], alone: false).map(\.id) == hearts
        && male.parts(showing: [.cardiovascular]).map(\.id) == hearts && hearts.count > 1
        && male.parts(showing: [.skeletal], focus: ["heart"], alone: true).isEmpty
        && male.parts(showing: []).isEmpty
        && male.parts(showing: Set(AnatomySystem.allCases)).count == male.parts.count,
      hearts.joined(separator: ", "))
let firstStructure: AnatomyStructure = male.part("heart")!.structures[0]
check("a structure is found by its key in the scene, and a wrong key finds nothing",
      male.structure(key: "heart/" + firstStructure.node)?.structure.node == firstStructure.node
        && male.structure(key: "heart/" + firstStructure.node)?.part.id == "heart"
        && male.structure(key: "heart/nope") == nil && male.structure(key: "nope/x") == nil
        && male.structure(key: "heart") == nil)

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
    check("\(body.name): between 780,000 and 880,000 triangles", (780_000...880_000).contains(total), "\(total)")
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

// MARK: the muscles' fibres (tools/anatomy_fibres.py)

let notSkeletal = ["papillary", "ciliary", "smooth_muscle", "gyrus"]
for body in manifest.bodies {
    var problems: [String] = []
    var laid: Int = 0
    var crossing: [Float] = []
    var cut: [String: Int] = [:]
    for part in body.parts where part.system == .muscular {
        guard let listed = part.fibres else { problems.append("\(part.id): no fibres listed"); continue }
        if listed.file != "\(body.id.rawValue)-\(part.id).fibres" { problems.append("\(part.id): file \(listed.file)") }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(listed.file)) else {
            problems.append("\(listed.file): missing"); continue
        }
        if data.count != listed.bytes { problems.append("\(listed.file): \(data.count) bytes, manifest \(listed.bytes)") }
        guard let ms = meshes[part.file], let all = try? AnatomyAtlas.fibres(of: part, meshes: ms, from: data) else {
            problems.append("\(listed.file): unreadable"); continue
        }
        for ((structure, mesh), fibres) in zip(zip(part.structures, ms), all) {
            let skeletal = structure.tissue == .muscle && !notSkeletal.contains { structure.node.contains($0) }
            guard let b = fibres else {
                if skeletal { problems.append("\(structure.node): no fibres") }
                continue
            }
            if !skeletal { problems.append("\(structure.node): fibres, not a skeletal muscle") }
            laid += 1
            cut[structure.node] = mesh.triangleCount
            // every vertex's point 1 to 2 from the origin: 2 less its tendon's share
            var off: Int = 0
            for i in 0..<b.vertexCount {
                let x: Float = b.around[2 * i], y: Float = b.around[2 * i + 1]
                let r: Float = (x * x + y * y).squareRoot()
                if !(r.isFinite && r > 0.999 && r < 2.001) { off += 1 }
            }
            if off > 0 { problems.append("\(structure.node): \(off) points not 1 to 2 from the origin") }
            // how the angle runs over each triangle of the belly: across the muscle's long axis, so the
            // fibres (the lines of one angle) run down it (the long, straight rectus femoris)
            guard structure.node.contains("rectus_femoris") else { continue }
            let axis = mesh.longAxis()
            for t in 0..<mesh.triangleCount {
                let i = (0..<3).map { Int(mesh.indices[3 * t + $0]) }
                if i.contains(where: { b.tendon($0) > 0.2 }) { continue }
                let p = i.map { mesh.position($0) }
                let e1 = p[1] - p[0], e2 = p[2] - p[0]
                let n = SIMD3<Float>(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
                let area2 = (n * n).sum()
                guard area2 > 1e-14 else { continue }
                // (the angle's change along an edge, the short way round)
                func short(_ a: Float) -> Float { a - a.rounded() }
                let d1 = short(b.turn(i[1]) - b.turn(i[0])), d2 = short(b.turn(i[2]) - b.turn(i[0]))
                // the gradient on the triangle's plane: (d1 (e2 x n) + d2 (n x e1)) / |n|^2
                func cross(_ a: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
                    SIMD3(a.y * c.z - a.z * c.y, a.z * c.x - a.x * c.z, a.x * c.y - a.y * c.x)
                }
                let g = (cross(e2, n) * d1 + cross(n, e1) * d2) / area2
                let length = (g * g).sum().squareRoot()
                guard length > 0 else { continue }
                crossing.append(abs((g * axis).sum()) / length)
            }
        }
    }
    check("\(body.name): every muscular part lists its fibres' file, there, its size as listed, and reads whole",
          problems.isEmpty, problems.prefix(6).joined(separator: "; "))
    check("\(body.name): every skeletal muscle has its fibres (\(laid))", laid == (body.id == .male ? 34 : 24), "\(laid)")
    // (a bipennate muscle: its fibres leave its front tendon at 14 degrees to its line of pull, so across them
    // is a little off across the muscle: the sine of 14 degrees is 0.24)
    let crossingMedian: Float = crossing.isEmpty ? 1 : crossing.sorted()[crossing.count / 2]
    check("\(body.name): the rectus femoris's fibres run down it, slanting as a pennate muscle's do: across them is nearly across the muscle (median cosine with its long axis \(String(format: "%.2f", crossingMedian)))",
          crossing.count > 1000 && (0.1...0.4).contains(crossingMedian))
    // each muscle and its mirror split alike (tools/anatomy_fibres.py): split in four on one side only, the
    // woman's right gluteus medius had three times the left's triangles
    let uneven = cut.keys.sorted().compactMap { node -> String? in
        guard node.hasSuffix("_L"), let l = cut[node], let r = cut[String(node.dropLast()) + "R"] else { return nil }
        return Double(max(l, r)) > 2 * Double(min(l, r)) ? "\(node.dropLast(2)) \(l), \(r)" : nil
    }
    check("\(body.name): each muscle cut as finely as its mirror (triangles within 2 times)", uneven.isEmpty,
          uneven.joined(separator: "; "))
}

func saf(_ entries: [[Float]?]) -> Data {
    var d = Data("SAF2".utf8)
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    u32(UInt32(entries.count))
    for e in entries {
        guard let e = e else { u32(0); continue }
        u32(UInt32(e.count / 2))
        for a in e { u32(a.bitPattern) }
    }
    return d
}
let twoMuscles = saf([nil, [2, 0, 0, 1.5, -1, 0]])
let readBack = try? AnatomyAtlas.fibres(from: twoMuscles)
check("a fibres file reads back: a structure without, then one with three corners",
      readBack?.count == 2 && readBack?[0] == nil && readBack?[1]?.around == [2, 0, 0, 1.5, -1, 0])
check("its texture coordinates are its points as they are", readBack?[1]?.coordinates() == [2, 0, 0, 1.5, -1, 0])
if let three = readBack?[1] {
    check("a corner's tendon is 2 less its distance from the origin: belly at 2, half at 1.5, all tendon at 1",
          three.tendon(0) == 0 && three.tendon(1) == 0.5 && three.tendon(2) == 1)
    check("and where it lies round the muscle its angle in turns: 0, a quarter, a half",
          abs(three.turn(0)) < 1e-6 && abs(three.turn(1) - 0.25) < 1e-6 && abs(three.turn(2) - 0.5) < 1e-6)
} else {
    check("the fibres file's second structure reads", false)
}
check("a cut-off fibres file is refused", {
    do { _ = try AnatomyAtlas.fibres(from: twoMuscles.prefix(twoMuscles.count - 4)); return false }
    catch AnatomyAtlas.ReadError.truncated { return true } catch { return false }
}())
check("a fibres file with bytes left over is refused", {
    do { _ = try AnatomyAtlas.fibres(from: twoMuscles + Data([0, 0, 0, 0])); return false }
    catch AnatomyAtlas.ReadError.leftover { return true } catch { return false }
}())
check("a mesh file is not a fibres file", (try? AnatomyAtlas.fibres(from: first)) == nil)
if let hip = male.part("hip-muscles"), let listed = hip.fibres, let ms = meshes[hip.file],
   let data = try? Data(contentsOf: folder.appendingPathComponent(listed.file)) {
    let shuffled = Array(ms.reversed())
    let kept = (try? AnatomyAtlas.fibres(of: hip, meshes: shuffled, from: data))?.compactMap { $0 }.count
    check("fibres read against meshes they do not fit are dropped, not drawn wrong (\(kept ?? -1) of \(ms.count) kept)",
          kept != nil && kept! < ms.count)
    check("fibres read against another part's structures are refused",
          (try? AnatomyAtlas.fibres(of: male.part("eye-muscles")!, meshes: ms, from: data)) == nil)
} else {
    check("the man's hip muscles have their fibres", false)
}
let muscleRed = AnatomyTissue.muscle.colour
let ratio = AnatomyFibres.tendonRatio(muscle: muscleRed)
check("tendon is paler than muscle in every channel, most in green and blue",
      ratio.x > 1 && ratio.y > ratio.x && ratio.z > ratio.x)

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
    // each rib's head and neck on its own vertebrae (tools/anatomy_ribs.py): the second to the ninth on the vertebra
    // it is named for and the one above, the others on their own alone; its nearest point 3.5 mm or less from them
    // (a joint's 1.5 mm and a vertex's spacing)
    let vh = body.id == .male ? "VH_M_" : "VH_F_"
    let unseated: [String] = ["L", "R"].flatMap { s in
        (1...12).compactMap { n -> String? in
            guard let rib = mesh("TS_rib_\(n)_\(s)", in: body) else { return "\(n)\(s) missing" }
            let own = ((2...9).contains(n) ? [n - 1, n] : [n]).compactMap { mesh("\(vh)thoracic_vertebra_\($0)", in: body) }
            guard !own.isEmpty else { return "\(n)\(s) without its vertebrae" }
            let grid = PointGrid(own.flatMap(points), size: 0.01)
            let gap = points(rib).map(grid.nearest).min()! * 1000
            return gap <= 3.5 ? nil : "\(n)\(s) \(String(format: "%.1f", gap)) mm"
        }
    }
    check("\(body.name): each rib's head on its own vertebrae, 3.5 mm or nearer", unseated.isEmpty,
          unseated.joined(separator: ", "))
    // the scanned skull (tools/anatomy_bones.py): its bones, named as the CT skull's, and its own teeth, which
    // take the place of the organ sets' rows in the mouth under the same names
    let skull = body.part("skull")?.structures ?? []
    let skullBones = skull.filter { $0.tissue == .bone }, teeth = skull.filter { $0.tissue == .tooth }
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    check("\(body.name): the skull's thirteen bones, the paired ones left and right, and its upper and lower teeth (22 pieces)",
          skull.count == 22 && skullBones.count == 20 && skullBones.allSatisfy { $0.node.hasPrefix("NLM_") }
          && Set(teeth.map(\.node)) == [pre + "set_of_upper_jaw_teeth", pre + "set_of_lower_jaw_teeth"],
          "\(skull.count) pieces, \(skullBones.count) bone, \(teeth.map(\.node))")
    check("\(body.name): no teeth left in the mouth", body.part("mouth")?.structures.contains { $0.tissue == .tooth } == false)
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
    // the shoulders' width and the clavicles' line (a girdle turned 47 degrees about its joint with the sternum
    // swung the man's clavicles to run backward, his humeri's heads 16 cm apart): each clavicle runs out to the
    // side, its outer end 10 cm or more further out than its inner end and at most 7 cm behind it; the humeri's
    // tops 28 to 42 cm apart
    var tops: [Float] = []
    for s in ["L", "R"] {
        guard let clavicle = mesh("TS_clavicle_\(s)", in: body), let humerus = mesh("TS_humerus_\(s)", in: body) else { continue }
        let points = (0..<clavicle.vertexCount).map(clavicle.position)
        let outer = points.max { abs($0.x) < abs($1.x) }!, inner = points.min { abs($0.x) < abs($1.x) }!
        let out = abs(outer.x) - abs(inner.x), back = inner.z - outer.z
        check("\(body.name): the \(s == "L" ? "left" : "right") clavicle runs out to the side (\(Int(out * 1000)) mm out, \(Int(back * 1000)) mm back)",
              out >= 0.10 && back <= 0.07)
        tops.append((0..<humerus.vertexCount).map(humerus.position).max { $0.y < $1.y }!.x)
    }
    let apart = tops.count == 2 ? abs(tops[0] - tops[1]) : 0
    check("\(body.name): the humeri's heads 28 to 42 cm apart (\(Int(apart * 1000)) mm)", (0.28...0.42).contains(apart))
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

// MARK: the scanned skull and spine (tools/anatomy_bones.py)

// Points binned in cells, for the nearest-point distances below: a lookup reads the 27 cells about a point, so a
// distance comes out exact up to the cell's size and as the cell's size beyond it
struct GridCell: Hashable { let x, y, z: Int32 }
struct PointGrid {
    let size: Float
    var cells: [GridCell: [SIMD3<Float>]] = [:]
    init(_ points: [SIMD3<Float>], size: Float = 0.004) {
        self.size = size
        for p in points { cells[key(p), default: []].append(p) }
    }
    func key(_ p: SIMD3<Float>) -> GridCell {
        GridCell(x: Int32((p.x / size).rounded(.down)), y: Int32((p.y / size).rounded(.down)), z: Int32((p.z / size).rounded(.down)))
    }
    func nearest(_ q: SIMD3<Float>) -> Float {
        let k = key(q)
        var best = size * size
        for dx: Int32 in -1...1 {
            for dy: Int32 in -1...1 {
                for dz: Int32 in -1...1 {
                    for p in cells[GridCell(x: k.x + dx, y: k.y + dy, z: k.z + dz)] ?? [] {
                        let d = p - q
                        best = min(best, (d * d).sum())
                    }
                }
            }
        }
        return best.squareRoot()
    }
}
func points(_ m: AnatomyMesh) -> [SIMD3<Float>] { (0..<m.vertexCount).map(m.position) }

/// A closed mesh (in mm) for asking what lies inside it: by the parity of a ray's crossings along +x, its
/// triangles kept in a grid across y and z so each ray meets only those over it.
struct Solid {
    let a: [SIMD3<Double>], b: [SIMD3<Double>], c: [SIMD3<Double>]
    let lo: SIMD3<Double>, hi: SIMD3<Double>
    let cell = 0.5
    let grid: [SIMD2<Int>: [Int]]

    init(_ m: AnatomyMesh) {
        func at(_ i: UInt32) -> SIMD3<Double> {
            let p = m.position(Int(i))
            return SIMD3(Double(p.x), Double(p.y), Double(p.z)) * 1000
        }
        var a: [SIMD3<Double>] = [], b: [SIMD3<Double>] = [], c: [SIMD3<Double>] = []
        for t in 0..<m.triangleCount {
            a.append(at(m.indices[3 * t])); b.append(at(m.indices[3 * t + 1])); c.append(at(m.indices[3 * t + 2]))
        }
        var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
        var grid: [SIMD2<Int>: [Int]] = [:]
        for t in a.indices {
            let l = pointwiseMin(a[t], pointwiseMin(b[t], c[t])), h = pointwiseMax(a[t], pointwiseMax(b[t], c[t]))
            lo = pointwiseMin(lo, l); hi = pointwiseMax(hi, h)
            for y in Int((l.y / cell).rounded(.down))...Int((h.y / cell).rounded(.down)) {
                for z in Int((l.z / cell).rounded(.down))...Int((h.z / cell).rounded(.down)) {
                    grid[SIMD2(y, z), default: []].append(t)
                }
            }
        }
        self.a = a; self.b = b; self.c = c; self.lo = lo; self.hi = hi; self.grid = grid
    }

    func contains(_ q: SIMD3<Double>) -> Bool {
        guard q.x > lo.x, q.x < hi.x, q.y > lo.y, q.y < hi.y, q.z > lo.z, q.z < hi.z else { return false }
        // nudged off the grid of the mesh's own numbers, so the ray never runs exactly through an edge
        let p = q + SIMD3(0, 1.3e-7, 2.9e-7)
        var crossings = 0
        for t in grid[SIMD2(Int((p.y / cell).rounded(.down)), Int((p.z / cell).rounded(.down)))] ?? [] {
            // where the line through p along x meets the triangle's plane, if inside it (y, z barycentric)
            let (A, B, C) = (a[t], b[t], c[t])
            let d = (B.y - A.y) * (C.z - A.z) - (C.y - A.y) * (B.z - A.z)
            if abs(d) < 1e-15 { continue }
            let u = ((p.y - A.y) * (C.z - A.z) - (C.y - A.y) * (p.z - A.z)) / d
            let v = ((B.y - A.y) * (p.z - A.z) - (p.y - A.y) * (B.z - A.z)) / d
            if u < 0 || v < 0 || u + v > 1 { continue }
            if A.x + u * (B.x - A.x) + v * (C.x - A.x) > p.x { crossings += 1 }
        }
        return crossings % 2 == 1
    }
}

let kinds = ["cervical", "thoracic", "lumbar"]
for body in manifest.bodies {
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    // the skull's two sides mirror each other: every 25th point, mirrored about the middle of the skull's width,
    // lands on the skull's other side, the median within 1.3 mm (the scan stands at about 1.0 mm, after its
    // turn to the body's plane and the mirror pass; the skull before it, at 1.7)
    if let skull = body.part("skull"), let ms = meshes[skull.file], skull.bounds.count == 6 {
        let all = ms.flatMap(points), x0 = (skull.bounds[0] + skull.bounds[3]) / 2
        let grid = PointGrid(all)
        var gaps: [Float] = stride(from: 0, to: all.count, by: 25).map { i in
            var q = all[i]
            q.x = 2 * x0 - q.x
            return grid.nearest(q)
        }
        gaps.sort()
        let median = gaps[gaps.count / 2] * 1000
        check("\(body.name): the skull's sides mirror each other (median \(String(format: "%.2f", median)) mm)", median < 1.3)
    } else {
        check("\(body.name): the skull is there", false)
    }
    // the column from its scans: seven cervical vertebrae, twelve thoracic and five lumbar (the woman's set six),
    // each with the scan's detail (at least 1,500 triangles; the organ set's had a few hundred), and every one
    // below the one above it (the six-point check above samples the column; this takes each scanned vertebra)
    let column = (body.part("vertebral-column")?.structures ?? []).filter { s in kinds.contains { s.node.hasPrefix(pre + $0 + "_vertebra_") } }
    let counts = kinds.map { k in column.filter { $0.node.hasPrefix(pre + k) }.count }
    check("\(body.name): 7 cervical, 12 thoracic and \(body.id == .male ? 5 : 6) lumbar vertebrae",
          counts == [7, 12, body.id == .male ? 5 : 6], "\(counts)")
    let thin = column.filter { $0.triangles < 1_500 }.map(\.node)
    check("\(body.name): every vertebra has the scan's detail (1,500 triangles or more)", thin.isEmpty, thin.joined(separator: ", "))
    let ordered = kinds.enumerated().flatMap { k, kind in
        column.filter { $0.node.hasPrefix(pre + kind) }
            .sorted { Int($0.node.split(separator: "_").last!)! < Int($1.node.split(separator: "_").last!)! }
    }
    let heights = ordered.compactMap { centre($0.node, in: body)?.y }
    check("\(body.name): each vertebra sits below the one above it, from the atlas to the last lumbar",
          heights.count == column.count && zip(heights, heights.dropFirst()).allSatisfy { $0 > $1 })
    // the sacrum and the coccyx, scanned too; the coccyx hangs from the sacrum's tip and carries the column on
    // straight below it: its own tip under the sacrum's (the middles of their lowest 5 mm) to within 2.5 mm
    // across (the organ set's leaned 3 to 5 mm to one side)
    guard let sacrum = mesh(pre + "sacrum", in: body), let coccyx = mesh(pre + "coccyx", in: body) else {
        check("\(body.name): the sacrum and coccyx are there", false); continue
    }
    check("\(body.name): the sacrum and the coccyx have the scan's detail",
          sacrum.triangleCount >= 10_000 && coccyx.triangleCount >= 1_500, "\(sacrum.triangleCount), \(coccyx.triangleCount)")
    let sp = points(sacrum), cp = points(coccyx)
    let sacral = PointGrid(sp)
    let joint = cp.map(sacral.nearest).min()! * 1000
    let sacrumLow = sp.map(\.y).min()!, coccyxTop = cp.map(\.y).max()!, coccyxLow = cp.map(\.y).min()!
    func middle(_ ps: [SIMD3<Float>]) -> SIMD3<Float> { ps.reduce(.zero, +) / Float(ps.count) }
    let apex = middle(sp.filter { $0.y < sacrumLow + 0.005 }), tip = middle(cp.filter { $0.y < coccyxLow + 0.005 })
    let across = abs(tip.x - apex.x) * 1000
    check("\(body.name): the coccyx meets the sacrum's tip (\(String(format: "%.1f", joint)) mm) and hangs straight below it (\(String(format: "%.1f", across)) mm across)",
          joint < 1.5 && across < 2.5)
    check("\(body.name): the coccyx carries the column on below the sacrum",
          coccyx.centre.y < sacrum.centre.y && coccyxLow < sacrumLow - 0.01 && coccyxTop < sacrumLow + 0.015,
          "top \(Int((coccyxTop - sacrumLow) * 1000)) mm above the sacrum's lowest point, lowest \(Int((sacrumLow - coccyxLow) * 1000)) mm below it")
    // the sacrum seated by its joints (tools/anatomy_bones.py seat_sacrum, ease_facets and discs): the disc under
    // the last lumbar vertebra meets the vertebra and the sacrum (their nearest vertices within 1.5 mm), about as
    // big as the disc above it; the vertebra stands on the sacrum, the middles of the faces the disc meets within
    // 12 mm front to back (the man's lay 22 to 26 mm apart, with no disc between them); each nucleus pulposus lies
    // in the disc it is named for; and each sacroiliac joint is closed to a joint's width, the median of the 30 of
    // the ilium's vertices nearest the sacrum within 3 mm of it (the woman's stood 6 to 7 mm open)
    let lumbar = ordered.filter { $0.node.hasPrefix(pre + "lumbar") }
    if lumbar.count >= 2, let vertebra = mesh(lumbar[lumbar.count - 1].node, in: body),
       let disc = mesh(pre + "intervertebral_disk_of_\(ordinals[lumbar.count - 1])_lumbar_vertebra", in: body),
       let above = mesh(pre + "intervertebral_disk_of_\(ordinals[lumbar.count - 2])_lumbar_vertebra", in: body) {
        let dp = points(disc), vp = points(vertebra)
        let toVertebra = dp.map(PointGrid(vp).nearest).min()! * 1000, toSacrum = dp.map(sacral.nearest).min()! * 1000
        let ratio = abs(volume([disc])) / abs(volume([above]))
        check("\(body.name): the disc under the last lumbar vertebra meets it (\(String(format: "%.1f", toVertebra)) mm) and the sacrum (\(String(format: "%.1f", toSacrum)) mm), \(String(format: "%.2f", ratio)) times the disc above",
              toVertebra < 1.5 && toSacrum < 1.5 && (0.7...1.6).contains(ratio))
        let faces = PointGrid(dp)
        let under = vp.filter { faces.nearest($0) < 0.003 }, top = sp.filter { faces.nearest($0) < 0.003 }
        let offset = under.isEmpty || top.isEmpty ? Float.infinity : abs(middle(under).z - middle(top).z) * 1000
        check("\(body.name): the last lumbar vertebra stands on the sacrum (\(String(format: "%.1f", offset)) mm front to back)", offset < 12)
    } else {
        check("\(body.name): the disc under the last lumbar vertebra is there", false)
    }
    let columnParts = body.part("vertebral-column")?.structures ?? []
    let discNodes = columnParts.map(\.node).filter { $0.hasPrefix(pre + "intervertebral_disk_of_") }
    let nucleusNodes = columnParts.map(\.node).filter { $0.hasPrefix(pre + "nucleus_pulposus_of_") }
    let discCentres = discNodes.compactMap { n in centre(n, in: body).map { (node: n, at: $0) } }
    func nucleus(of disc: String) -> String { pre + "nucleus_pulposus_of_" + String(disc.dropFirst(pre.count)) }
    let astray = nucleusNodes.filter { n in
        guard let c = centre(n, in: body),
              let home = discCentres.min(by: { (($0.at - c) * ($0.at - c)).sum() < (($1.at - c) * ($1.at - c)).sum() }) else { return true }
        return nucleus(of: home.node) != n || ((home.at - c) * (home.at - c)).sum().squareRoot() > 0.015
    }
    check("\(body.name): every disc has its nucleus pulposus, each in the disc it is named for (\(discNodes.count) discs)",
          Set(nucleusNodes) == Set(discNodes.map(nucleus)) && astray.isEmpty, astray.joined(separator: ", "))
    let wide = PointGrid(sp, size: 0.01)
    for (node, side) in body.id == .male ? [("VH_M_ilium_compact_bone_L", "left"), ("VH_M_ilium_compact_bone_R", "right")]
                                         : [("TS_hip_L", "left"), ("TS_hip_R", "right")] {
        guard let ilium = mesh(node, in: body) else {
            check("\(body.name): the \(side) ilium is there", false); continue
        }
        let closest = points(ilium).map(wide.nearest).sorted().prefix(30)
        let gap = closest[closest.startIndex + closest.count / 2] * 1000
        check("\(body.name): the \(side) sacroiliac joint is closed to a joint's width (\(String(format: "%.1f", gap)) mm)", gap < 3)
    }
    // every disc made anew between the scanned bones (tools/anatomy_bones.py fit_discs): each meets the two bones
    // it lies between (its nearest points within 1.5 mm of each; the organ sets' stood up to 4 mm off the scanned
    // bodies) and stands no more than 2.5 mm in front of their rims where it meets them (theirs overhung by up to
    // 7 mm)
    let bones: [(node: String, centre: SIMD3<Float>, grid: PointGrid, points: [SIMD3<Float>])] =
        ordered.compactMap { s in mesh(s.node, in: body).map { m in (s.node, m.centre, PointGrid(points(m)), points(m)) } }
        + [(pre + "sacrum", sacrum.centre, sacral, sp)]
    var unseated: [String] = []
    for node in discNodes {
        guard let disc = mesh(node, in: body) else { unseated.append(node + " missing"); continue }
        let dp = points(disc), faces = PointGrid(dp)
        let close = bones.filter { (($0.centre - disc.centre) * ($0.centre - disc.centre)).sum() < 0.08 * 0.08 }
            .map { b in (bone: b, gap: dp.map(b.grid.nearest).min()!) }
            .sorted { $0.gap < $1.gap }.prefix(2)
        guard close.count == 2 else { unseated.append(node + " between fewer than two bones"); continue }
        let gap = close.map(\.gap).max()! * 1000
        let rims = close.map { c in c.bone.points.filter { faces.nearest($0) < 0.003 }.map(\.z).max() ?? -.infinity }.max()!
        let over = (dp.map(\.z).max()! - rims) * 1000
        if gap > 1.5 || over > 2.5 {
            unseated.append("\(node.dropFirst(pre.count)) \(String(format: "%.1f", gap)) mm off, \(String(format: "%.1f", over)) mm over")
        }
    }
    check("\(body.name): every disc meets the bones above and below it and stands no further forward than their rims (\(discNodes.count) discs)",
          discNodes.count >= 23 && unseated.isEmpty, unseated.joined(separator: "; "))
}

// MARK: the gluteus maximus (tools/anatomy_gluteus.py)

/// The Euler characteristic of a mesh's surface, its vertices welded where they meet: 2 for one closed surface
/// without holes through it (a sphere's), 0 for one with a hole (a ring's).
func euler(_ m: AnatomyMesh) -> Int {
    struct Point: Hashable { let x, y, z: Float }
    var ids: [Point: Int] = [:]
    let id: [Int] = (0..<m.vertexCount).map { i in
        let p = m.position(i), key = Point(x: p.x, y: p.y, z: p.z)
        if let known = ids[key] { return known }
        ids[key] = ids.count
        return ids.count - 1
    }
    struct Edge: Hashable { let a, b: Int }
    var edges = Set<Edge>()
    for t in stride(from: 0, to: m.indices.count, by: 3) {
        for (i, j) in [(0, 1), (1, 2), (2, 0)] {
            let a = id[Int(m.indices[t + i])], b = id[Int(m.indices[t + j])]
            edges.insert(Edge(a: min(a, b), b: max(a, b)))
        }
    }
    return ids.count - edges.count + m.triangleCount
}
/// The body's midline (x): the middle of the sacrum's width, height by height over its lower half, the median
/// of eight heights (as tools/anatomy_gluteus.py finds it; the vertices' mean leans toward the side with more).
func midline(_ sacrum: [SIMD3<Float>]) -> Float {
    let y0 = sacrum.map(\.y).min()!, y1 = y0 + 0.5 * (sacrum.map(\.y).max()! - y0)
    let mids: [Float] = (0..<8).compactMap { k in
        let y = y0 + 0.005 + (y1 - y0 - 0.005) * Float(k) / 7
        let band = sacrum.filter { abs($0.y - y) < 0.003 }.map(\.x)
        return band.count >= 3 ? (band.min()! + band.max()!) / 2 : nil
    }.sorted()
    guard !mids.isEmpty else { return sacrum.map(\.x).reduce(0, +) / Float(sacrum.count) }
    return mids.count % 2 == 1 ? mids[mids.count / 2] : (mids[mids.count / 2 - 1] + mids[mids.count / 2]) / 2
}

// Made anew from its attachments on each body's own bones (the one from the CT was an oval pad over the buttock,
// the woman's with a loop and a hole at its lower end): one closed surface with no hole through it, arising from
// the hip bone, the sacrum and the coccyx and inserted on the femur 30% of its length below its top; as big as MRI
// finds it in living adults (Belzunce et al. 2023, 87 recreational cyclists: a median of 770 cm³ in the men and
// 621 in the women); the two at least 5 mm either side of the midline, apart over the coccyx.
for body in manifest.bodies {
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    guard let sacrum = mesh(pre + "sacrum", in: body), let coccyx = mesh(pre + "coccyx", in: body) else {
        check("\(body.name): the sacrum and the coccyx are there", false); continue
    }
    let middle = midline(points(sacrum))
    let volumes: ClosedRange<Float> = body.id == .male ? 600...950 : 480...780
    for (side, name) in [("L", "left"), ("R", "right")] {
        guard let muscle = mesh("TS_gluteus_maximus_" + side, in: body), let femur = mesh(pre + "femur_" + side, in: body),
              let hip = mesh(body.id == .male ? pre + "ilium_compact_bone_" + side : "TS_hip_" + side, in: body) else {
            check("\(body.name): the \(name) gluteus maximus, femur and hip bone are there", false); continue
        }
        let ps = points(muscle), fp = points(femur)
        let edges = openEdges([muscle]), chi = euler(muscle), cc = abs(volume([muscle])) * 1e6
        check("\(body.name): the \(name) gluteus maximus one closed surface with no hole through it (\(edges) open edges, Euler characteristic \(chi)), \(Int(cc)) cm³ (\(Int(volumes.lowerBound)) to \(Int(volumes.upperBound)))",
              edges == 0 && chi == 2 && volumes.contains(cc))
        let gaps = [hip, sacrum, coccyx, femur].map { bone -> Float in
            let grid = PointGrid(points(bone), size: 0.01)
            return ps.map(grid.nearest).min()! * 1000
        }
        let top = fp.map(\.y).max()!, reach = (top - ps.map(\.y).min()!) / (top - fp.map(\.y).min()!)
        check("\(body.name): the \(name) gluteus maximus on the hip bone, the sacrum, the coccyx and the femur (\(gaps.map { String(format: "%.1f", $0) }.joined(separator: ", ")) mm), \(Int(reach * 100))% of the femur's length down it (25 to 40)",
              gaps.allSatisfy { $0 < 2.5 } && (0.25...0.40).contains(reach))
        let inner = side == "L" ? ps.map { $0.x - middle }.min()! : ps.map { middle - $0.x }.min()!
        check("\(body.name): the \(name) gluteus maximus \(String(format: "%.1f", inner * 1000)) mm from the midline (4.5 or more)", inner >= 0.0045)
    }
}

// MARK: the eyes (tools/anatomy_eyes.py)

/// The sphere nearest some points, least squares (|p|^2 = 2 c.p + d, r^2 = d + |c|^2), about their mean.
func sphere(_ ps: [SIMD3<Double>]) -> (centre: SIMD3<Double>, radius: Double) {
    let mean = ps.reduce(SIMD3<Double>.zero, +) / Double(ps.count)
    var m = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 4)
    for q in ps {
        let p = q - mean
        let row: [Double] = [2 * p.x, 2 * p.y, 2 * p.z, 1]
        let b = (p * p).sum()
        for i in 0..<4 {
            for j in 0..<4 { m[i][j] += row[i] * row[j] }
            m[i][4] += row[i] * b
        }
    }
    for k in 0..<4 {
        let pivot = (k..<4).max { abs(m[$0][k]) < abs(m[$1][k]) }!
        m.swapAt(k, pivot)
        for i in (k + 1)..<4 {
            let f = m[i][k] / m[k][k]
            for j in k..<5 { m[i][j] -= f * m[k][j] }
        }
    }
    var x = [Double](repeating: 0, count: 4)
    for i in stride(from: 3, through: 0, by: -1) {
        x[i] = (m[i][4] - ((i + 1)..<4).map { m[i][$0] * x[$0] }.reduce(0, +)) / m[i][i]
    }
    let c = SIMD3(x[0], x[1], x[2])
    return (c + mean, (x[3] + (c * c).sum()).squareRoot())
}

for body in manifest.bodies {
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    guard let eyes = body.part("eyes"), let eyeMuscles = body.part("eye-muscles") else {
        check("\(body.name): the eyes and their muscles are there", false)
        continue
    }
    // in millimetres
    func mm(_ p: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(p.x), Double(p.y), Double(p.z)) * 1000 }
    func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { (a * b).sum() }
    func size(_ a: SIMD3<Double>) -> Double { dot(a, a).squareRoot() }
    func unit(_ a: SIMD3<Double>) -> SIMD3<Double> { a / size(a) }
    func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    func median(_ xs: [Double]) -> Double { xs.isEmpty ? .nan : xs.sorted()[xs.count / 2] }
    func light(_ s: AnatomyStructure) -> Double { 0.2126 * s.colour.red + 0.7152 * s.colour.green + 0.0722 * s.colour.blue }
    func at(_ node: String) -> [SIMD3<Double>] { mesh(node, in: body).map { points($0).map(mm) } ?? [] }

    // how each part of the eye looks: its own colour, how see-through and how glossy
    let looks = eyes.structures.filter { s in
        guard let own = s.ownColour, own.count == 7, own.hasPrefix("#"), Int(own.dropFirst(), radix: 16) != nil,
              let o = s.ownOpacity, let r = s.ownRoughness else { return false }
        return (0.05...1).contains(o) && (0.02...0.9).contains(r)
    }
    check("\(body.name): each of the eyes' 46 structures has its own look (a colour, 0.05 to 1 opaque, 0.02 to 0.9 rough)",
          eyes.structures.count == 46 && looks.count == 46, "\(looks.count) of \(eyes.structures.count)")
    let right: (String) -> AnatomyStructure? = { key in eyes.structures.first { $0.node == pre + key + "_R" } }
    if let sclera = right("sclera"), let iris = right("iris"), let pupil = right("pupil"),
       let darkest = eyes.structures.min(by: { light($0) < light($1) }) {
        check("\(body.name): the sclera white, the iris darker, the pupil black (the darkest of the eye's parts)",
              light(sclera) > 0.8 && light(iris) < 0.5 * light(sclera) && darkest.node.contains("pupil") && light(pupil) < 0.05)
    } else {
        check("\(body.name): the sclera, iris and pupil are there", false)
    }
    // what each structure is, without the body's prefix and its side
    func key(_ s: AnatomyStructure) -> String {
        let name = String(s.node.dropFirst(pre.count))
        return name.hasSuffix("_R") || name.hasSuffix("_L") ? String(name.dropLast(2)) : name
    }
    let clear: Set<String> = ["cornea", "aqueous_humor", "vitreous_humor", "bulbar_conjunctiva"]
    let seeThrough = eyes.structures.filter { s in
        clear.contains(key(s)) ? s.opacity >= 0.3
            : key(s) == "lens" || key(s).hasPrefix("palpebral") ? !(0.3...0.7).contains(s.opacity) : s.opacity < 1
    }
    check("\(body.name): the cornea, the humours and the bulbar conjunctiva clear, the lens and the lids' linings half, the rest solid",
          seeThrough.isEmpty, seeThrough.map(\.node).joined(separator: ", "))
    let dark = body.parts.flatMap(\.structures).filter(\.unlit)
    check("\(body.name): what is drawn unlit (an opening, black) the pupils alone",
          dark.count == 2 && dark.allSatisfy { key($0) == "pupil" }, dark.map(\.node).joined(separator: ", "))
    let glassy = body.parts.flatMap(\.structures).filter(\.clear)
    check("\(body.name): what is drawn as its reflections alone (clear) the cornea, the humours and the bulbar conjunctiva, both sides, nothing else",
          glassy.count == 8 && glassy.allSatisfy { clear.contains(key($0)) }, glassy.map(\.node).joined(separator: ", "))
    check("\(body.name): the eye muscles, six a side, grouped by side",
          eyeMuscles.structures.count == 12 && eyeMuscles.structures.allSatisfy {
              $0.group == ($0.node.hasSuffix("_R") ? "right eye muscles" : "left eye muscles")
          }, eyeMuscles.structures.map(\.group).joined(separator: ", "))

    // each eyeball: a sphere about 12 mm across its radius, its axis from the centre through the cornea
    let balls = ["R", "L"].map { sphere(at(pre + "sclera_" + $0)) }
    for (k, side) in ["R", "L"].enumerated() {
        let (c, r) = balls[k]
        let sclera = at(pre + "sclera_" + side), cornea = at(pre + "cornea_" + side)
        let iris = at(pre + "iris_" + side), pupil = at(pre + "pupil_" + side)
        guard !sclera.isEmpty, !cornea.isEmpty, !iris.isEmpty, !pupil.isEmpty else {
            check("\(body.name), \(side): the eyeball's coats, iris and pupil are there", false)
            continue
        }
        let onIt = sclera.filter { abs(size($0 - c) - r) < 0.15 }.count
        check("\(body.name), \(side): the sclera a sphere (radius \(String(format: "%.2f", r)) mm, 11 to 13; nine in ten of its points within 0.15 mm of it)",
              (11...13).contains(r) && Double(onIt) >= 0.9 * Double(sclera.count), "\(onIt) of \(sclera.count)")
        let a = unit(cornea.reduce(SIMD3<Double>.zero, +) / Double(cornea.count) - c)
        let up = unit(SIMD3<Double>(0, 1, 0) - a.y * a)
        let toward = balls[1 - k].centre - c
        let nasal = unit(toward - dot(toward, a) * a - dot(toward, up) * up)
        let apex = cornea.map { dot($0 - c, a) }.max()!
        let chamber = apex - iris.map { dot($0 - c, a) }.max()!
        check("\(body.name), \(side): the cornea's apex 12.5 to 14 mm before the centre (\(String(format: "%.2f", apex))), the iris 2.5 to 3.8 mm behind it (\(String(format: "%.2f", chamber)))",
              (12.5...14).contains(apex) && (2.5...3.8).contains(chamber))
        func offAxis(_ p: SIMD3<Double>) -> Double { size((p - c) - dot(p - c, a) * a) }
        let pupilMiddle = pupil.reduce(SIMD3<Double>.zero, +) / Double(pupil.count)
        check("\(body.name), \(side): the pupil on the axis, 1.6 to 2.2 mm across its radius",
              offAxis(pupilMiddle) < 0.3 && (1.6...2.2).contains(pupil.map(offAxis).max()!),
              "\(offAxis(pupilMiddle)), \(pupil.map(offAxis).max()!)")
        // the recti's insertions, each on its own meridian: how far behind the limbus (5.85 mm off the axis)
        let limbus = asin(5.85 / 12)
        let tillaux: [(String, SIMD3<Double>)] = [("medial_rectus", nasal), ("inferior_rectus", -up), ("lateral_rectus", -nasal), ("superior_rectus", up)]
        let behind: [Double] = tillaux.map { key, meridian in
            let across = cross(a, meridian)
            let thetas = at(pre + key + "_extraocular_muscle_" + side).map { $0 - c }
                .filter { size($0) < r + 1.5 && abs(dot($0, across)) < 1 && dot($0, meridian) > 0 }
                .map { atan2(dot($0, meridian), dot($0, a)) }
            return r * ((thetas.min() ?? .nan) - limbus)
        }
        check("\(body.name), \(side): the recti on the spiral of Tillaux, medial 5.5 mm behind the limbus, inferior 6.5, lateral 6.9, superior 7.7 (within 0.7 mm, in that order)",
              zip(behind, [5.5, 6.5, 6.9, 7.7]).allSatisfy { abs($0 - $1) <= 0.7 } && behind == behind.sorted(),
              behind.map { String(format: "%.2f", $0) }.joined(separator: ", "))
        func onBack(_ key: String) -> [SIMD3<Double>] {
            at(pre + key + "_extraocular_muscle_" + side).map { $0 - c }.filter { size($0) < r + 1.2 && dot($0, a) < -1 }
        }
        let so = onBack("superior_oblique"), io = onBack("inferior_oblique")
        check("\(body.name), \(side): the superior oblique inserted behind the equator, above; the inferior behind it, below and temporal",
              so.count > 20 && median(so.map { dot($0, up) }) > 6
                && io.count > 20 && median(io.map { dot($0, up) }) < -3 && median(io.map { dot($0, nasal) }) < -3,
              "\(so.count) \(median(so.map { dot($0, up) })); \(io.count) \(median(io.map { dot($0, up) })) \(median(io.map { dot($0, nasal) }))")
        let entering = eyeMuscles.structures.filter { $0.node.hasSuffix("_" + side) }.compactMap { s -> String? in
            let n = at(s.node).filter { size($0 - c) < r - 0.15 }.count
            return n == 0 ? nil : "\(s.label) \(n)"
        }
        check("\(body.name), \(side): no eye muscle enters the eyeball", entering.isEmpty, entering.joined(separator: ", "))
        // none passes into another: no point of one inside another (where one crosses another, the outer lies
        // over it; tools/anatomy_eyes.py)
        let mine = eyeMuscles.structures.filter { $0.node.hasSuffix("_" + side) }
        let solids = mine.compactMap { s in mesh(s.node, in: body).map { Solid($0) } }
        var passing: [String] = []
        if solids.count == mine.count {
            for (i, a) in mine.enumerated() {
                for (j, b) in mine.enumerated() where i != j {
                    let n = at(a.node).filter { solids[j].contains($0) }.count
                    if n > 0 { passing.append("\(a.label) in \(b.label) \(n)") }
                }
            }
        }
        check("\(body.name), \(side): no eye muscle passes into another", solids.count == mine.count && passing.isEmpty,
              passing.joined(separator: ", "))
        // the iris's frame, about which its pattern is drawn (AtlasShaders.iris): its middle on the eye's axis,
        // turned about that axis, its pupil's rim and its root as far off it as the build puts them
        if let ring = mesh(pre + "iris_" + side, in: body)?.ringFrame() {
            let middle = SIMD3<Double>(Double(ring.centre.x), Double(ring.centre.y), Double(ring.centre.z)) * 1000
            let turned = abs(dot(unit(SIMD3<Double>(Double(ring.axis.x), Double(ring.axis.y), Double(ring.axis.z))), a))
            check("\(body.name), \(side): the iris's frame: its middle on the axis, turned about it, its rim 1.5 to 2.2 mm and its root 5 to 5.8 mm off it",
                  offAxis(middle) < 0.3 && turned > cos(5 * Double.pi / 180)
                    && (1.5...2.2).contains(Double(ring.inner) * 1000) && (5...5.8).contains(Double(ring.outer) * 1000),
                  "\(offAxis(middle)) \(turned) \(ring.inner * 1000) \(ring.outer * 1000)")
        } else {
            check("\(body.name), \(side): the iris's frame", false)
        }
    }
    let patterned = body.parts.flatMap(\.structures).filter(\.iris)
    check("\(body.name): what is drawn with the iris's pattern the irises alone, both sides",
          patterned.count == 2 && patterned.allSatisfy { key($0) == "iris" }, patterned.map(\.node).joined(separator: ", "))

    // each eye muscle a belly ending in a tendon (the fibres' tendon share, tools/anatomy_fibres.py)
    if let listed = eyeMuscles.fibres, let data = try? Data(contentsOf: folder.appendingPathComponent(listed.file)),
       let ms = meshes[eyeMuscles.file], let all = try? AnatomyAtlas.fibres(of: eyeMuscles, meshes: ms, from: data) {
        let lacking = zip(eyeMuscles.structures, all).compactMap { s, b -> String? in
            guard let b else { return s.label + ": no fibres" }
            let shares: [Float] = (0..<b.vertexCount).map { b.tendon($0) }
            let tendon = shares.filter { $0 > 0.5 }.count, belly = shares.filter { $0 <= 0.1 }.count
            return tendon >= 30 && belly >= 200 ? nil : "\(s.label): \(tendon) tendon, \(belly) belly"
        }
        check("\(body.name): each eye muscle a belly ending in a tendon", lacking.isEmpty, lacking.joined(separator: "; "))
    } else {
        check("\(body.name): the eye muscles' fibres read", false)
    }
}

// MARK: the tubes closed, and the pelvis's structures apart (tools/anatomy_apart.py)

/// A closed surface's inside: a point is in it when a ray from it straight up, and one straight down, each
/// cross the surface an odd number of times (the two agree for a closed surface; a ray grazing an edge, which
/// two triangles both count, makes them differ, and the point is then read as outside). The triangles are
/// binned by their spans across x and z, so a point reads only the ones over and under it.
struct ClosedSolid {
    struct Bin: Hashable { let x, z: Int32 }
    let size: Float
    let lo: SIMD3<Float>, hi: SIMD3<Float>
    var corners: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    var bins: [Bin: [Int]] = [:]
    init(_ m: AnatomyMesh, size: Float = 0.004) {
        self.size = size
        let ps = points(m)
        lo = ps.reduce(SIMD3(repeating: .infinity)) { pointwiseMin($0, $1) }
        hi = ps.reduce(SIMD3(repeating: -.infinity)) { pointwiseMax($0, $1) }
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let a = ps[Int(m.indices[t])], b = ps[Int(m.indices[t + 1])], c = ps[Int(m.indices[t + 2])]
            corners.append((a, b, c))
            let x0 = Int32((min(a.x, b.x, c.x) / size).rounded(.down)), x1 = Int32((max(a.x, b.x, c.x) / size).rounded(.down))
            let z0 = Int32((min(a.z, b.z, c.z) / size).rounded(.down)), z1 = Int32((max(a.z, b.z, c.z) / size).rounded(.down))
            for x in x0...x1 { for z in z0...z1 { bins[Bin(x: x, z: z), default: []].append(corners.count - 1) } }
        }
    }
    func contains(_ q: SIMD3<Float>) -> Bool {
        guard q.x >= lo.x, q.x <= hi.x, q.y >= lo.y, q.y <= hi.y, q.z >= lo.z, q.z <= hi.z else { return false }
        var up = 0, down = 0
        for i in bins[Bin(x: Int32((q.x / size).rounded(.down)), z: Int32((q.z / size).rounded(.down)))] ?? [] {
            let (a, b, c) = corners[i]
            let d = (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
            if d == 0 { continue }
            let u = ((q.x - a.x) * (c.z - a.z) - (c.x - a.x) * (q.z - a.z)) / d
            let v = ((b.x - a.x) * (q.z - a.z) - (q.x - a.x) * (b.z - a.z)) / d
            guard u >= 0, v >= 0, u + v <= 1 else { continue }
            if a.y + u * (b.y - a.y) + v * (c.y - a.y) > q.y { up += 1 } else { down += 1 }
        }
        return up % 2 == 1 && down % 2 == 1
    }
}

// The organ set's vessels and gut tubes were cut open where each meets the next, and the app draws a solid's
// inside: each is a closed surface now, yet hollow at a cut across it, as a cut tube is (a double wall's two rims
// joined by the ring between them; a single wall given a wall's ring and a lumen sealed out of sight), a sheet
// over a branch's mouth
let tubeParts: Set<String> = ["vessels", "colon", "small-intestine", "urethra", "genital-ducts", "uterine-tubes", "vagina", "biliary-tree"]
for body in manifest.bodies {
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    let named = body.id == .male
        ? ["rectum", "sigmoid_colon", "common_iliac_vein_L", "common_iliac_vein_R", "internal_iliac_vein_L", "internal_iliac_vein_R", "median_sacral_vein"]
        : ["rectum", "sigmoid_colon", "left_common_iliac_vein", "right_common_iliac_vein", "internal_iliac_vein_L", "internal_iliac_vein_R", "median_sacral_vein"]
    let open = named.compactMap { key -> String? in
        guard let m = mesh(pre + key, in: body) else { return key + " missing" }
        let n = openEdges([m])
        return n == 0 ? nil : "\(key) \(n)"
    }
    check("\(body.name): the rectum, the sigmoid colon, the common and internal iliac veins and the median sacral vein each a closed surface",
          open.isEmpty, open.joined(separator: ", "))
    var tubes = 0, closed = 0
    for part in body.parts where tubeParts.contains(part.id) || part.id == "kidneys" {
        for (s, m) in zip(part.structures, meshes[part.file] ?? []) where part.id != "kidneys" || s.node.contains("ureter") {
            tubes += 1
            if openEdges([m]) == 0 { closed += 1 }
        }
    }
    check("\(body.name): the tubes closed at their cut ends, \(closed) of \(tubes) (19 in 20 or more; a few branch where three meet at an edge)",
          tubes > 100 && closed * 20 >= tubes * 19)
}

// In the pelvis no vein runs into a bone (the sacrum, the coccyx, the lumbar vertebrae, the hip bones), nor into
// the rectum or the sigmoid colon unless it is that gut's own (a rectal vein, a sigmoid vein, which end in it):
// the organs, the vessels and the ducts were eased out of the bones and one another. Each vein's points in the
// pelvis (its part's box, 2 cm wider, 1 cm above the iliac crests) are read against each closed bone and gut:
// at most 15 points in, none deeper than 3 mm (the organ set's ran 4 to 5 mm into the ischia, and the woman's
// median sacral vein 5 mm into the back of her rectum; the man's left internal pudendal vein, which runs along
// the inside of his ischium where a push cannot tell which face it lies on, still grazes it by under 3 mm).
for body in manifest.bodies {
    let pre = body.id == .male ? "VH_M_" : "VH_F_"
    guard let pelvis = body.part("pelvis"), pelvis.bounds.count == 6, let vessels = body.part("vessels"),
          let vesselMeshes = meshes[vessels.file] else {
        check("\(body.name): the pelvis and the vessels are there", false); continue
    }
    let lo = SIMD3(pelvis.bounds[0], pelvis.bounds[1], pelvis.bounds[2]) - 0.02
    var hi = SIMD3(pelvis.bounds[3], pelvis.bounds[4], pelvis.bounds[5]) + 0.02
    hi.y -= 0.01
    func inPelvis(_ p: SIMD3<Float>) -> Bool { all(p .>= lo) && all(p .<= hi) }
    var walls: [(node: String, owns: String?, solid: ClosedSolid, surface: PointGrid)] = []
    for s in pelvis.structures where s.tissue == .bone {
        if let m = mesh(s.node, in: body) { walls.append((s.node, nil, ClosedSolid(m), PointGrid(points(m)))) }
    }
    for s in body.part("vertebral-column")?.structures ?? [] where s.node.hasPrefix(pre + "lumbar_vertebra_") {
        if let m = mesh(s.node, in: body) { walls.append((s.node, nil, ClosedSolid(m), PointGrid(points(m)))) }
    }
    for (key, own) in [("rectum", "rectal"), ("sigmoid_colon", "sigmoid")] {
        if let m = mesh(pre + key, in: body) { walls.append((pre + key, own, ClosedSolid(m), PointGrid(points(m)))) }
    }
    var veins = 0, inside: [String] = [], count = 0
    var deepest: Float = 0
    for (s, m) in zip(vessels.structures, vesselMeshes) where s.tissue == .vein {
        let ps = points(m).filter(inPelvis)
        if ps.isEmpty { continue }
        veins += 1
        for wall in walls where wall.owns.map({ !s.node.contains($0) }) ?? true {
            let ins = ps.filter(wall.solid.contains)
            if ins.isEmpty { continue }
            let depth = ins.map(wall.surface.nearest).max()! * 1000
            count += ins.count
            deepest = max(deepest, depth)
            inside.append("\(s.node.dropFirst(pre.count)) in \(wall.node.dropFirst(pre.count)) \(ins.count) (\(String(format: "%.1f", depth)) mm)")
        }
    }
    check("\(body.name): in the pelvis no vein in a bone or a gut not its own (\(veins) veins, \(walls.count) bones and guts; \(count) points in, deepest \(String(format: "%.1f", deepest)) mm)",
          veins >= 15 && walls.count >= 7 && count <= 15 && deepest < 3, inside.joined(separator: "; "))
}
// The woman's sacrum, a scan of another body's, drawn out of her hip bones (from her CT) where it ran into them at
// its joints, a joint's width off them (some 70 of its points a side lay 1 to 4 mm inside). The man's hip bones are
// his organ set's thin plates, which the sacrum still crosses: drawing it out of them would dent it, so it is left
// as it was (tools/anatomy_apart.py ease_sacrum).
if let sacrum = mesh("VH_F_sacrum", in: female) {
    let sp = points(sacrum)
    let crossing = ["TS_hip_L", "TS_hip_R"].compactMap { mesh($0, in: female) }.map { hip in sp.filter(ClosedSolid(hip).contains).count }
    check("Female: the sacrum clear of the hip bones (\(crossing.map(String.init).joined(separator: " and ")) of its points in them)",
          crossing.count == 2 && crossing.allSatisfy { $0 <= 3 })
} else {
    check("Female: the sacrum is there", false)
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
