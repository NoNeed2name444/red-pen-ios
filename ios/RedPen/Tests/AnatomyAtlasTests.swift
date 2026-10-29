// The bundled 3D anatomy atlas, read the way the app reads it: every part's
// file matches the manifest, every mesh is whole and inside the body, sides
// are where their labels say, and the labels and sources are clean.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let folder = URL(fileURLWithPath: "ios/RedPen/Resources/Anatomy")
guard let manifestData = try? Data(contentsOf: folder.appendingPathComponent("anatomy.json")),
      let manifest = try? AnatomyAtlas.manifest(from: manifestData) else {
    print("FAIL the manifest reads")
    exit(1)
}
check("the manifest reads, format 1", manifest.format == 1)
check("32 parts, ids unique", manifest.parts.count == 32 && Set(manifest.parts.map(\.id)).count == 32)
let structures = manifest.parts.flatMap(\.structures)
check("863 structures, node names unique", structures.count == 863 && Set(structures.map(\.node)).count == 863,
      "\(structures.count)")
check("every body system has a part",
      Set(manifest.parts.map(\.system)) == Set(AnatomySystem.allCases), "\(Set(AnatomySystem.allCases).subtracting(manifest.parts.map(\.system)))")
check("both sources are CC BY 4.0 and pinned",
      manifest.sources.count == 2 && manifest.sources.allSatisfy {
          $0.licence == "CC BY 4.0" && $0.sha256.count == 64 && $0.doi.hasPrefix("https://doi.org/")
      })

// MARK: every file, read

var meshes: [String: [AnatomyMesh]] = [:]
var readErrors: [String] = []
for part in manifest.parts {
    let url = folder.appendingPathComponent(part.file)
    guard let data = try? Data(contentsOf: url) else { readErrors.append("\(part.id): missing"); continue }
    if data.count != part.bytes { readErrors.append("\(part.id): \(data.count) bytes, manifest \(part.bytes)") }
    do { meshes[part.id] = try AnatomyAtlas.meshes(of: part, from: data) } catch { readErrors.append("\(part.id): \(error)") }
}
check("every part's file is there, its size as listed, and reads whole", readErrors.isEmpty, readErrors.joined(separator: "; "))
let mismatched: [String] = manifest.parts.flatMap { part in
    zip(part.structures, meshes[part.id] ?? []).compactMap { s, m in m.triangleCount == s.triangles ? nil : s.node }
}
check("every structure has the triangles the manifest says", mismatched.isEmpty, mismatched.prefix(5).joined(separator: ", "))
check("about a third of a million triangles in all",
      (300_000...360_000).contains(manifest.parts.map(\.triangles).reduce(0, +)))
let empty = manifest.parts.flatMap { p in zip(p.structures, meshes[p.id] ?? []).filter { $0.1.triangleCount == 0 }.map { $0.0.node } }
check("no structure is empty", empty.isEmpty, empty.joined(separator: ", "))

// MARK: geometry

let outside: [String] = manifest.parts.compactMap { part in
    guard let ms = meshes[part.id], part.bounds.count == 6 else { return part.id }
    for m in ms {
        for i in 0..<m.vertexCount {
            let p = m.position(i)
            for a in 0..<3 where p[a] < part.bounds[a] - 1e-4 || p[a] > part.bounds[a + 3] + 1e-4 { return part.id }
        }
    }
    return nil
}
check("every position lies in its part's bounds", outside.isEmpty, outside.joined(separator: ", "))
let body = manifest.part("skin")!.bounds
let beyond = manifest.parts.filter { p in (0..<3).contains { p.bounds[$0] < body[$0] - 0.02 || p.bounds[$0 + 3] > body[$0 + 3] + 0.02 } }
check("every part lies inside the skin's box", beyond.isEmpty, beyond.map(\.id).joined(separator: ", "))
check("the body is about 1.8 m tall", abs((body[4] - body[1]) - 1.82) < 0.05, "\(body[4] - body[1])")

/// The middle of a structure, by node name.
func centre(_ node: String) -> SIMD3<Float>? {
    for part in manifest.parts {
        if let i = part.structures.firstIndex(where: { $0.node == node }), let m = meshes[part.id]?[i] { return m.centre }
    }
    return nil
}
let heart: SIMD3<Float> = centre("VH_M_heart_left_ventricle") ?? SIMD3(-9, -9, -9)
let liverX: Float = centre("VH_M_liver_capsule")?.x ?? 9
let brainY: Float = centre("Allen_head_of_caudate_L")?.y ?? -9
let bladderY: Float = centre("VH_M_trigone_of_urinary_bladder")?.y ?? 9
let spineZ: Float = centre("VH_M_thoracic_vertebra_6")?.z ?? 9
check("the heart lies left of the midline (x > 0)", heart.x > 0, "\(heart.x)")
check("the liver lies on the right (x < 0)", liverX < 0, "\(liverX)")
check("the brain is above the heart, the bladder below", brainY > heart.y && bladderY < heart.y)
check("the spine is behind the heart (z smaller)", spineZ < heart.z)
check("the vertebrae run in order down the column", {
    let names = ["cervical_vertebra_1", "cervical_vertebra_7", "thoracic_vertebra_1", "thoracic_vertebra_12",
                 "lumbar_vertebra_1", "lumbar_vertebra_5"].map { "VH_M_" + $0 }
    let ys = names.compactMap { centre($0)?.y }
    return ys.count == names.count && zip(ys, ys.dropFirst()).allSatisfy { $0 > $1 }
}())

// Labelled sides against where the structure is: x > 0 is the body's left.
var sided = 0, wrongSide: [String] = []
for part in manifest.parts {
    for (s, m) in zip(part.structures, meshes[part.id] ?? []) {
        let left = s.label.hasPrefix("left "), right = s.label.hasPrefix("right ")
        guard left || right else { continue }
        sided += 1
        // within a centimetre of the midline is on it (the third ventricle's halves)
        if (left && m.centre.x < -0.01) || (right && m.centre.x > 0.01) { wrongSide.append(s.node) }
    }
}
// Named left or right for the organ, not the body: the right ventricle
// lies left of the midline with the rest of the heart, and the left
// liver's vessels, ducts and medial segments lie right of it.
let organSided: Set<String> = [
    "VH_M_heart_right_ventricle", "VH_M_left_hepatic_artery", "VH_M_left_hepatic_vein",
    "VH_M_left_branch_of_portal_vein", "VH_M_left_superiomedial_segment",
    "VH_M_left_inferomedial_segment", "VH_M_left_hepatic_duct",
]
let misplaced: [String] = wrongSide.filter { !organSided.contains($0) }
check("left and right labels are on their side (\(sided) checked)", sided > 500 && misplaced.isEmpty,
      misplaced.prefix(8).joined(separator: ", "))
check("the brain's left half is on the body's left (mirrored from the organ set)",
      (centre("Allen_thalamus_L")?.x ?? -1) > 0 && (centre("Allen_thalamus_R")?.x ?? 1) < 0)
check("the swapped renal arteries are named for the kidney they reach",
      structures.first { $0.node == "VH_M_left_renal_artery" }?.label == "right renal artery"
      && (centre("VH_M_left_renal_artery")?.x ?? 1) < 0)

let mesh = meshes["legs"]![manifest.part("legs")!.structures.firstIndex { $0.node == "VH_M_femur_L" }!]
let normals = mesh.normals()
let unit: Bool = stride(from: 0, to: normals.count, by: 3).allSatisfy { i in
    let x: Float = normals[i], y: Float = normals[i + 1], z: Float = normals[i + 2]
    return abs(x * x + y * y + z * z - 1) < 1e-3
}
check("smooth normals: one per vertex, unit length", normals.count == mesh.positions.count && unit)
/// Signed volume: positive when the triangles wind counter-clockwise seen
/// from outside, so the normals point out.
func volume(_ m: AnatomyMesh) -> Float {
    var v: Float = 0
    for t in stride(from: 0, to: m.indices.count, by: 3) {
        let a = m.position(Int(m.indices[t])), b = m.position(Int(m.indices[t + 1])), c = m.position(Int(m.indices[t + 2]))
        let n = SIMD3(b.y * c.z - b.z * c.y, b.z * c.x - b.x * c.z, b.x * c.y - b.y * c.x)
        v += (a * n).sum() / 6
    }
    return v
}
let femurVolume = volume(mesh)
check("the femur's triangles face outward, its volume about 83 cm³", abs(femurVolume - 8.3e-5) < 1e-5, "\(femurVolume)")
let thalamus = meshes["brain"]![manifest.part("brain")!.structures.firstIndex { $0.node == "Allen_thalamus_L" }!]
check("the mirrored brain still faces outward", volume(thalamus) > 0, "\(volume(thalamus))")
check("the femur is about 45 cm long", {
    var lo: Float = 9, hi: Float = -9
    for i in 0..<mesh.vertexCount { lo = min(lo, mesh.position(i).y); hi = max(hi, mesh.position(i).y) }
    return abs((hi - lo) - 0.45) < 0.06
}())

// MARK: reading errors

check("a file that is not an atlas is refused", (try? AnatomyAtlas.meshes(from: Data(repeating: 0, count: 64))) == nil)
let first = try! Data(contentsOf: folder.appendingPathComponent(manifest.parts[0].file))
check("a cut-off file is refused", {
    do { _ = try AnatomyAtlas.meshes(from: first.prefix(first.count - 7)); return false } catch { return true }
}())
check("a file with bytes left over is refused", {
    do { _ = try AnatomyAtlas.meshes(from: first + Data([0, 0, 0, 0])); return false }
    catch AnatomyAtlas.ReadError.leftover { return true } catch { return false }
}())
check("a part read against another's manifest entry is refused", {
    do { _ = try AnatomyAtlas.meshes(of: manifest.part("brain")!, from: first); return false } catch { return true }
}())

// MARK: labels

func cluttered(_ label: String) -> Bool {
    label.contains("Allen") || label.hasSuffix(" L") || label.hasSuffix(" R") || label.contains("_")
}
let clutter: [String] = structures.map(\.label).filter(cluttered)
check("labels carry no source clutter", clutter.isEmpty, clutter.prefix(5).joined(separator: ", "))
check("no label names a side twice",
      !structures.contains { $0.label.hasPrefix("left left") || $0.label.hasPrefix("right right") || $0.label.hasPrefix("left right") || $0.label.hasPrefix("right left") })
check("UBERON ids are well formed", structures.compactMap(\.uberon).allSatisfy { $0.range(of: #"^UBERON:\d{7}$"#, options: .regularExpression) != nil })
check("the crosswalk's mislabels are corrected",
      structures.first { $0.node == "VH_M_superior_mesenteric_vein" }?.label == "superior mesenteric vein"
      && structures.first { $0.node == "VH_M_left_anterior_descending_artery" }?.label.contains("left coronary") == true
      && structures.first { $0.node == "VH_M_ilium_compact_bone_L" }?.label == "left ilium")
check("corrected labels drop the wrong UBERON id", structures.first { $0.node == "VH_M_superior_mesenteric_vein" }?.uberon == nil)
check("titles start with a capital", structures.first { $0.node == "VH_M_femur_L" }?.title == "Left femur")
check("tissues: veins are veins, arteries arteries, bones bone",
      structures.first { $0.node == "VH_M_superior_vena_cava" }?.tissue == .vein
      && structures.first { $0.node == "VH_M_aortic_arch" }?.tissue == .artery
      && structures.first { $0.node == "VH_M_femur_R" }?.tissue == .bone)
check("every part shows something before it is opened",
      manifest.parts.allSatisfy { $0.structures.contains { !$0.inner } },
      manifest.parts.filter { !$0.structures.contains { !$0.inner } }.map(\.id).joined(separator: ", "))
check("the liver shows its capsule; its segments wait inside",
      manifest.part("liver")!.structures.filter { !$0.inner }.map(\.node) == ["VH_M_liver_capsule"])

// MARK: search

let femurs = Set(AnatomyAtlas.search("femur", in: manifest).map(\.structure.node))
check("search finds both femurs", femurs.isSuperset(of: ["VH_M_femur_L", "VH_M_femur_R"]), "\(femurs)")
let leftFemur = AnatomyAtlas.search("left femur", in: manifest).map(\.structure.node)
check("search needs every word", leftFemur.contains("VH_M_femur_L") && !leftFemur.contains { $0.hasSuffix("_R") }, "\(leftFemur)")
check("search finds the coronary arteries", AnatomyAtlas.search("coronary artery", in: manifest).count >= 4)
check("an empty search finds nothing", AnatomyAtlas.search("  ", in: manifest).isEmpty)

// MARK: colours

check("every tissue has its own colour",
      Set(AnatomyTissue.allCases.map { "\($0.colour.red),\($0.colour.green),\($0.colour.blue)" }).count == AnatomyTissue.allCases.count)
check("arteries are red and veins blue",
      AnatomyTissue.artery.colour.red > AnatomyTissue.artery.colour.blue && AnatomyTissue.vein.colour.blue > AnatomyTissue.vein.colour.red)
check("only skin is see-through", AnatomyTissue.allCases.filter { $0.opacity < 1 } == [.skin])

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
