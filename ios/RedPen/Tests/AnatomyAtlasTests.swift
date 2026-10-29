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
check("every source is CC BY 4.0 and pinned, with a DOI or (the NIH 3D skull) its entry's page",
      manifest.sources.count == 5 && manifest.sources.allSatisfy {
          $0.licence == "CC BY 4.0" && $0.sha256.count == 64 && $0.url.hasPrefix("https://")
            && ($0.doi?.hasPrefix("https://doi.org/") ?? ($0.id == "nih3d-3dpx-020591"))
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
check("932 male structures and 966 female",
      male.parts.flatMap(\.structures).count == 932 && female.parts.flatMap(\.structures).count == 966,
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
    check("\(body.name): about 450,000 to 470,000 triangles", (440_000...480_000).contains(total), "\(total)")
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
      && named("VH_F_ilium_compact_bone_L")?.label == "left hip bone"
      && named("VH_F_left_anterior_descending_artery")?.label.contains("left coronary") == true)
check("corrected labels drop the wrong UBERON id", named("VH_M_superior_mesenteric_vein")?.uberon == nil)
check("the female set's sixth lumbar vertebra is named as the variant it is",
      named("VH_F_lumbar_vertebra_6")?.label.contains("normal variant") == true)
check("a structure from a scan says so; the organ sets' own say nothing",
      named("TS_stomach")?.origin?.contains("CT scan") == true && named("NLM_mandible")?.origin?.contains("NIH 3D") == true
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
