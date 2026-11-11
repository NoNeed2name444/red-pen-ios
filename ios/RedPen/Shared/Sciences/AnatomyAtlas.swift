import Foundation

/// The 3D anatomy atlas: the manifest (Resources/Anatomy/anatomy.json) and
/// the meshes of each part (<body>-<part>.atlas), made by
/// tools/anatomy_atlas.py from the Human Reference Atlas's male and female
/// reference organ sets, with each body's own skull from its Visible Human
/// head CT (tools/anatomy_skull.py; NLM's terms), its bones named, its face
/// and thinnest plates given by NIH 3D's skull model, and the ribs, shoulder
/// girdle, arm, hand and foot bones, the woman's hip bones, hip and back
/// muscles, thyroid, adrenals, oesophagus and stomach from five
/// TotalSegmentator CT scans, which tools/anatomy_gaps.py carries into each
/// body (CC BY 4.0; sources and credits in Resources/Anatomy/SOURCES.md).
///
/// Two bodies, the Visible Human Male and Female, each in its own frame:
/// metres, x to the body's left, y up, z forward, origin near the hips. A
/// part is an organ or a group (the vertebral column); a structure is one
/// mesh in it (the third lumbar vertebra), with its label, UBERON id and
/// tissue. Most parts are in both bodies; the reproductive organs (and a
/// few the organ sets model in one body only) are in their own. Inner
/// structures (the liver's segments inside its capsule) are drawn only when
/// their part is opened. Foundation only: the SceneKit view builds its
/// geometry from `AnatomyMesh`.
struct AnatomyManifest: Decodable, Hashable {
    let format: Int
    let sources: [Source]
    let changes: String
    let bodies: [AnatomyBody]

    struct Source: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
        let creators: String
        /// None for a source with no DOI (an NIH 3D entry).
        let doi: String?
        let url: String
        let sha256: String
        let licence: String
        let licenceURL: String
    }

    func body(_ sex: AnatomySex) -> AnatomyBody? { bodies.first { $0.id == sex } }

    /// The part in the first body that has it, male first: for a name.
    func part(_ id: String) -> AtlasPart? {
        for body in bodies { if let part = body.part(id) { return part } }
        return nil
    }

    /// The body to open for these parts: the first that has them all, else
    /// the one with the most, else `preferred`.
    func body(for parts: Set<String>, preferred: AnatomySex = .male) -> AnatomySex {
        let ordered: [AnatomyBody] = bodies.filter { $0.id == preferred } + bodies.filter { $0.id != preferred }
        var best: (sex: AnatomySex, held: Int) = (preferred, 0)
        for body in ordered {
            let held: Int = parts.filter { body.part($0) != nil }.count
            if held == parts.count { return body.id }
            // the first with the most, so a tie keeps the preferred body
            if held > best.held { best = (body.id, held) }
        }
        return best.sex
    }
}

/// Which body: the atlas has a male and a female one.
enum AnatomySex: String, Decodable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var name: String { self == .male ? "Male" : "Female" }

    /// Where the body last chosen is kept (UserDefaults): the atlas and the
    /// tools whose numbers differ by sex share it.
    static let rememberedKey = "sciences.atlas.body"

    /// The remembered choice, read from its raw value; the male body when
    /// nothing (or nothing readable) is kept.
    init(remembered raw: String) { self = AnatomySex(rawValue: raw) ?? .male }
}

/// One body: its parts, each with its own file.
struct AnatomyBody: Decodable, Hashable, Identifiable {
    let id: AnatomySex
    let name: String
    /// Its coordinates, in words.
    let frame: String
    /// The id of the source (in the manifest's `sources`) its meshes come from.
    let source: String
    let parts: [AtlasPart]

    func part(_ id: String) -> AtlasPart? { parts.first { $0.id == id } }

    /// The parts to read for what is shown: those of the layers shown and, while
    /// a topic's own parts are shown alone, only those. The atlas reads a layer
    /// when it is first shown, so a topic opens on its own parts and the whole
    /// body is read only when every layer is.
    func parts(showing systems: Set<AnatomySystem>, focus: Set<String> = [], alone: Bool = false) -> [AtlasPart] {
        parts.filter { systems.contains($0.system) && (!alone || focus.isEmpty || focus.contains($0.id)) }
    }

    /// A structure by its node's key in the scene, "part/structure".
    func structure(key: String) -> (part: AtlasPart, structure: AnatomyStructure)? {
        guard let slash = key.firstIndex(of: "/"), let part = part(String(key[..<slash])) else { return nil }
        let node = String(key[key.index(after: slash)...])
        guard let structure = part.structures.first(where: { $0.node == node }) else { return nil }
        return (part, structure)
    }
}

struct AtlasPart: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let system: AnatomySystem
    let file: String
    let bytes: Int
    let sha256: String
    let triangles: Int
    /// min x, y, z, max x, y, z in metres.
    let bounds: [Float]
    let structures: [AnatomyStructure]
    /// For a part of muscles, the file of their fibres (tools/anatomy_fibres.py):
    /// AnatomyAtlas.fibres reads it.
    let fibres: AtlasFile?
}

/// A file of the atlas, as the manifest lists it.
struct AtlasFile: Decodable, Hashable {
    let file: String
    let bytes: Int
    let sha256: String
}

struct AnatomyStructure: Decodable, Hashable {
    /// The node's name in the organ set, "VH_M_femur_L" or "VH_F_femur_L":
    /// unique in its body, and the key the view uses for picking.
    let node: String
    let label: String
    let uberon: String?
    let tissue: AnatomyTissue
    /// The organ set's group it sits in ("arteries of heart").
    let group: String
    let inner: Bool
    let triangles: Int
    /// Its own look where it is not its tissue's (the eye's parts, tools/anatomy_eyes.py): its colour in sRGB
    /// ("#F2EEE6"), how see-through (0 to 1) and how rough to the light (0 to 1).
    let ownColour: String?
    let ownOpacity: Double?
    let ownRoughness: Double?
    /// Its own surface pattern, drawn by a surface modifier of its own ("iris": AtlasShaders.iris).
    let ownSurface: String?

    private enum CodingKeys: String, CodingKey {
        case node, label, uberon, tissue, group, inner, triangles
        case ownColour = "colour", ownOpacity = "opacity", ownRoughness = "roughness", ownSurface = "surface"
    }

    /// The colour it is drawn in, sRGB 0...1: its own, else its tissue's.
    var colour: (red: Double, green: Double, blue: Double) {
        guard let own = ownColour?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), own.count == 6,
              let hex = Int(own, radix: 16) else { return tissue.colour }
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    /// How opaque it is drawn: its own, else its tissue's.
    var opacity: Double { ownOpacity ?? tissue.opacity }
    /// Clear as glass or water by its own look (the cornea, the humours, the conjunctiva over the sclera): drawn
    /// as what it reflects alone, over what shows through it, which a veil of its colour would cloud.
    var clear: Bool { (ownOpacity ?? 1) < 0.3 }
    /// Black by its own look, as an opening into the dark is (the pupil): drawn unlit, so that it stays black
    /// under any light rather than taking the faint sheen every lit surface has.
    var unlit: Bool {
        guard ownColour != nil else { return false }
        let c = colour
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.05
    }
    /// How rough its surface is to the light: its own, else its tissue's.
    var roughness: Double { ownRoughness ?? tissue.roughness }
    /// The iris, drawn with its own pattern about its middle (its fibres, crypts and rings: AtlasShaders.iris).
    var iris: Bool { ownSurface == "iris" }

    /// The label as a title: the first letter capitalised.
    var title: String { label.prefix(1).uppercased() + label.dropFirst() }

    var uberonURL: String? {
        uberon.map { "http://purl.obolibrary.org/obo/" + $0.replacingOccurrences(of: ":", with: "_") }
    }

    /// Where the mesh comes from when it is not the body's own organ set's:
    /// another person's scan, fitted to this body, which the card says.
    var origin: String? {
        if node.hasPrefix("TS_") { return "From a CT scan (TotalSegmentator), fitted to this body" }
        if Self.modelFace.contains(where: { node.hasPrefix("NLM_" + $0) }) {
            return "From the NIH 3D skull (Visible Human Male), fitted to this body"
        }
        if node.hasPrefix("NLM_") { return "From this body's own CT (Visible Human Project), thin plates from the NIH 3D skull" }
        return nil
    }

    /// The face's bones, which the skull takes whole from the NIH 3D model
    /// (tools/anatomy_skull.py FACE): at 1 mm the CT breaks their plates into lace.
    static let modelFace = ["ethmoid_bone", "nasal_bone", "lacrimal_bone", "zygomatic_bone", "maxilla", "palatine_bone", "vomer"]
}

enum AnatomySystem: String, Decodable, CaseIterable, Identifiable {
    case skeletal, muscular, nervous, specialSenses = "special senses", cardiovascular, respiratory
    case digestive, lymphatic, endocrine, urinary, reproductive, integumentary
    var id: String { rawValue }

    var name: String {
        switch self {
        case .specialSenses: return "Special senses"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// What a structure is made of; the atlas is coloured by it, but for a
/// structure with a look of its own (the eye's parts).
enum AnatomyTissue: String, Decodable, CaseIterable, Identifiable {
    case skin, fat, bone, cartilage, ligament, muscle, artery, vein, heart, nerve, brain
    case organ, gland, duct, airway, lung, gut, lymph, eye, fluid, tooth
    var id: String { rawValue }

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The colour the textbooks use for it, in sRGB 0...1: arteries red,
    /// veins blue, nerves yellow, bone ivory. Muscle the warm red of fresh
    /// flesh (its shader draws its fibres on it, paler and deeper, and
    /// lays a soft sheen on it: AtlasShaders.muscle), the heart a muted
    /// brownish red, and arteries scarlet, so a student can tell an artery
    /// on a muscle (CIEDE2000 13.4 apart, 5 when both were one red; 10.5
    /// and 14.6 to eyes that confuse red and green, by Machado's model;
    /// an artery on the heart 19, 14 and 21).
    var colour: (red: Double, green: Double, blue: Double) {
        let hex: Int
        switch self {
        case .skin: hex = 0xE8B89A
        case .fat: hex = 0xF2D27A
        case .bone: hex = 0xDDD1B6
        case .cartilage: hex = 0xB8D4E3
        case .ligament: hex = 0xD9CFA8
        case .muscle: hex = 0xA8443C
        case .artery: hex = 0xE8301E
        case .vein: hex = 0x2F62C8
        case .heart: hex = 0x8E3F38
        case .nerve: hex = 0xF2CC3A
        case .brain: hex = 0xE7B8B0
        case .organ: hex = 0xB26A4F
        case .gland: hex = 0xD39A6A
        case .duct: hex = 0x7FAE4F
        case .airway: hex = 0xD9A3A0
        case .lung: hex = 0xE59A9A
        case .gut: hex = 0xD98C7A
        case .lymph: hex = 0x8A5A8F
        case .eye: hex = 0xF0F0EA
        case .fluid: hex = 0xA7C7E7
        case .tooth: hex = 0xF4F1E6
        }
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// How rough its surface is to the light, 0 (a mirror) to 1 (chalk),
    /// for the atlas's physically based materials: bone matte, cartilage and
    /// the moist surfaces (vessels, gut, the eye, fluid) glossier, muscle
    /// satin under its fascia (a sharper gloss on it reads as plastic).
    var roughness: Double {
        switch self {
        case .eye: return 0.12
        case .fluid: return 0.15
        case .tooth: return 0.28
        case .artery, .vein: return 0.3
        case .cartilage: return 0.32
        case .duct, .gut: return 0.35
        case .heart, .organ: return 0.38
        case .airway: return 0.4
        case .ligament, .nerve, .gland, .lymph: return 0.45
        case .brain: return 0.48
        case .fat, .lung, .muscle: return 0.5
        case .skin: return 0.55
        case .bone: return 0.62
        }
    }

    /// Skin is drawn as a faint shell around the rest, so the organs show;
    /// fat (the breast's, the omentum) half see-through over what it wraps.
    var opacity: Double {
        switch self {
        case .skin: return 0.18
        case .fat: return 0.45
        default: return 1
        }
    }
}

/// One structure's triangles, positions in metres in the body frame.
struct AnatomyMesh: Hashable {
    /// x, y, z per vertex.
    var positions: [Float]
    /// Three per triangle, counter-clockwise seen from outside.
    var indices: [UInt32]

    var vertexCount: Int { positions.count / 3 }
    var triangleCount: Int { indices.count / 3 }

    func position(_ i: Int) -> SIMD3<Float> {
        SIMD3(positions[3 * i], positions[3 * i + 1], positions[3 * i + 2])
    }

    /// Smooth normals: each vertex gets the area-weighted sum of its
    /// triangles' normals, made unit length (up, for a vertex no triangle uses).
    func normals() -> [Float] {
        Self.normals(welding: [self])[0]
    }

    /// Each vertex's area-weighted sum of its triangles' normals, not yet unit length.
    func normalSums() -> [SIMD3<Float>] {
        var sums: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let pa = position(a), pb = position(b), pc = position(c)
            let n = cross(pb - pa, pc - pa)
            sums[a] += n; sums[b] += n; sums[c] += n
        }
        return sums
    }

    /// Smooth normals for the structures of one part, shaded as one surface.
    /// A bone cut into named pieces, or a mesh split along a seam, has a vertex
    /// on each side of the cut at the same place; each side's own normal sees
    /// only its own triangles, so the cut shows as a line in the light. Here
    /// every vertex at a shared place takes the sum over all the triangles
    /// round that place that face within `crease` degrees of its own, so the
    /// cut disappears, while the two faces of a thin plate, which meet at an
    /// edge facing apart, keep their own. Where three or more pieces meet, the
    /// vertices that face alike are joined through one another (a and c, each
    /// within `crease` of b, join though they are further apart), so any two
    /// that face alike take the same normal and no line shows between them.
    /// One array per mesh, as normals() gives.
    static func normals(welding meshes: [AnatomyMesh], crease: Float = 70) -> [[Float]] {
        struct Place: Hashable { let x, y, z: UInt32 }
        var sums: [SIMD3<Float>] = []
        var places: [Place: Int32] = [:]
        var group: [Int32] = []
        var size: [Int32] = []
        for mesh in meshes {
            sums += mesh.normalSums()
            for v in 0..<mesh.vertexCount {
                let p = mesh.position(v)
                let key = Place(x: p.x.bitPattern, y: p.y.bitPattern, z: p.z.bitPattern)
                if let g = places[key] {
                    group.append(g)
                    size[Int(g)] += 1
                } else {
                    places[key] = Int32(size.count)
                    group.append(Int32(size.count))
                    size.append(1)
                }
            }
        }
        // the vertices of each place more than one vertex shares, place by place
        var first: [Int] = Array(repeating: 0, count: size.count + 1)
        for g in 0..<size.count { first[g + 1] = first[g] + (size[g] > 1 ? Int(size[g]) : 0) }
        var members: [Int] = Array(repeating: 0, count: first[size.count])
        var next: [Int] = first
        for i in 0..<group.count where size[Int(group[i])] > 1 {
            let g = Int(group[i])
            members[next[g]] = i
            next[g] += 1
        }
        func unit(_ s: SIMD3<Float>) -> SIMD3<Float> {
            let length = (s * s).sum().squareRoot()
            return length > 0 ? s / length : .zero
        }
        let agree: Float = Float(cos(Double(crease) * .pi / 180))
        var welded: [SIMD3<Float>] = sums
        var root: [Int] = []
        var total: [SIMD3<Float>] = []
        for g in 0..<size.count where size[g] > 1 {
            let shared = Array(members[first[g]..<first[g + 1]])
            let units = shared.map { unit(sums[$0]) }
            root = Array(0..<shared.count)
            func find(_ k: Int) -> Int {
                var k = k
                while root[k] != k { root[k] = root[root[k]]; k = root[k] }
                return k
            }
            for a in 0..<shared.count {
                for b in (a + 1)..<shared.count where (units[a] * units[b]).sum() >= agree {
                    let ra = find(a), rb = find(b)
                    if ra != rb { root[rb] = ra }
                }
            }
            total = Array(repeating: .zero, count: shared.count)
            for k in 0..<shared.count { total[find(k)] += sums[shared[k]] }
            for k in 0..<shared.count { welded[shared[k]] = total[find(k)] }
        }
        var out: [[Float]] = []
        out.reserveCapacity(meshes.count)
        var at = 0
        for mesh in meshes {
            var normals: [Float] = []
            normals.reserveCapacity(mesh.positions.count)
            for s in welded[at..<(at + mesh.vertexCount)] {
                let length = (s * s).sum().squareRoot()
                let n = length > 0 ? s / length : SIMD3<Float>(0, 1, 0)
                normals += [n.x, n.y, n.z]
            }
            at += mesh.vertexCount
            out.append(normals)
        }
        return out
    }

    /// How the surface bends at each vertex, for the atlas's shading of its
    /// hollows (AtlasRelief): the mean curvature in 1/metre, positive where
    /// it bulges (a sphere of radius r gives 1/r), negative in a hollow. The
    /// structures of one part are read as one surface, as normals(welding:)
    /// reads them, so a cut between two pieces does not show in it: a vertex
    /// at a shared place sees the triangles of every piece round it. A
    /// place's value comes from how far it stands off the middle of its
    /// neighbours along its normal, over the mean square of the edges to them
    /// (a ring of neighbours h away on a sphere of radius r stands h²/2r
    /// below it); the values are then averaged with their neighbours', over
    /// about `spread` metres whatever the mesh's density (as many rounds as
    /// it takes a step the length of a mean edge to wander that far), so the
    /// mesh's own unevenness does not show and a coarse mesh is not smoothed
    /// flat. A place on an open edge, or where faces meet back to back, sees
    /// one side only: it takes its neighbours' values (0 if none has one).
    /// One array per mesh, a value per vertex.
    static func curvature(welding meshes: [AnatomyMesh], spread: Float = 0.003) -> [[Float]] {
        struct Place: Hashable { let x, y, z: UInt32 }
        var places: [Place: Int32] = [:]
        var group: [Int32] = []
        var spot: [SIMD3<Float>] = []
        var sums: [SIMD3<Float>] = []
        var sizes: [Float] = []
        var base: [Int] = []
        for mesh in meshes {
            base.append(group.count)
            let own = mesh.normalSums()
            for v in 0..<mesh.vertexCount {
                let p = mesh.position(v)
                let key = Place(x: p.x.bitPattern, y: p.y.bitPattern, z: p.z.bitPattern)
                let g: Int32
                if let known = places[key] {
                    g = known
                } else {
                    g = Int32(spot.count)
                    places[key] = g
                    spot.append(p)
                    sums.append(.zero)
                    sizes.append(0)
                }
                group.append(g)
                sums[Int(g)] += own[v]
                sizes[Int(g)] += (own[v] * own[v]).sum().squareRoot()
            }
        }
        let count = spot.count
        // each triangle's edges between places, the lower place first
        var edges: [UInt64] = []
        edges.reserveCapacity(meshes.reduce(0) { $0 + $1.indices.count })
        for (m, mesh) in meshes.enumerated() {
            for t in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let a = group[base[m] + Int(mesh.indices[t])]
                let b = group[base[m] + Int(mesh.indices[t + 1])]
                let c = group[base[m] + Int(mesh.indices[t + 2])]
                for (u, w) in [(a, b), (b, c), (c, a)] where u != w {
                    edges.append(UInt64(UInt32(min(u, w))) << 32 | UInt64(UInt32(max(u, w))))
                }
            }
        }
        edges.sort()
        // each place's neighbours, and the places on an open edge (one triangle's alone)
        var open = [Bool](repeating: false, count: count)
        var first = [Int](repeating: 0, count: count + 1)
        var unique: [UInt64] = []
        var k = 0
        while k < edges.count {
            var j = k + 1
            while j < edges.count && edges[j] == edges[k] { j += 1 }
            let lo = Int(edges[k] >> 32), hi = Int(edges[k] & 0xFFFF_FFFF)
            if j - k == 1 { open[lo] = true; open[hi] = true }
            unique.append(edges[k])
            first[lo + 1] += 1
            first[hi + 1] += 1
            k = j
        }
        for g in 0..<count { first[g + 1] += first[g] }
        var next = first
        var ring = [Int32](repeating: 0, count: first[count])
        for e in unique {
            let lo = Int(e >> 32), hi = Int(e & 0xFFFF_FFFF)
            ring[next[lo]] = Int32(hi)
            next[lo] += 1
            ring[next[hi]] = Int32(lo)
            next[hi] += 1
        }
        var value = [Float](repeating: .nan, count: count)
        for g in 0..<count where !open[g] && first[g + 1] > first[g] {
            let s = sums[g]
            let length = (s * s).sum().squareRoot()
            // faces back to back: their normals all but cancel
            guard length > 0.2 * sizes[g] else { continue }
            let n = s / length
            var middle = SIMD3<Float>.zero
            var square: Float = 0
            for r in first[g]..<first[g + 1] {
                let q = spot[Int(ring[r])]
                middle += q
                let d = q - spot[g]
                square += (d * d).sum()
            }
            let k = Float(first[g + 1] - first[g])
            guard square > 0 else { continue }
            value[g] = 2 * ((spot[g] - middle / k) * n).sum() / (square / k)
        }
        var edgeSum: Double = 0
        for e in unique {
            let d = spot[Int(e >> 32)] - spot[Int(e & 0xFFFF_FFFF)]
            edgeSum += Double((d * d).sum().squareRoot())
        }
        let edge = unique.isEmpty ? spread : Float(edgeSum / Double(unique.count))
        let rounds = min(8, max(1, Int((spread / max(edge, 1e-6) * spread / max(edge, 1e-6)).rounded())))
        for _ in 0..<rounds {
            var smoothed = value
            for g in 0..<count {
                var total: Float = 0, taken: Float = 0
                if !value[g].isNaN { total += value[g]; taken += 1 }
                for r in first[g]..<first[g + 1] {
                    let v = value[Int(ring[r])]
                    if !v.isNaN { total += v; taken += 1 }
                }
                smoothed[g] = taken > 0 ? total / taken : .nan
            }
            value = smoothed
        }
        return meshes.indices.map { m in
            (0..<meshes[m].vertexCount).map { v in
                let c = value[Int(group[base[m] + v])]
                return c.isNaN ? 0 : c
            }
        }
    }

    /// A ring's frame (the iris, AtlasShaders.iris): its middle (the mean of
    /// its vertices), the axis it is turned about (the least of their spread:
    /// at right angles to the two main axes of their covariance), and how far
    /// its vertices lie off that axis, nearest and farthest (the pupil's rim
    /// and the root). Nil for fewer than three vertices.
    func ringFrame() -> AnatomyRing? {
        guard vertexCount > 2 else { return nil }
        var mean = SIMD3<Double>(repeating: 0)
        for i in 0..<vertexCount { mean += SIMD3<Double>(position(i)) }
        mean /= Double(vertexCount)
        var c = [Double](repeating: 0, count: 9)
        for i in 0..<vertexCount {
            let d = SIMD3<Double>(position(i)) - mean
            for r in 0..<3 { for k in 0..<3 { c[3 * r + k] += d[r] * d[k] } }
        }
        func times(_ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(c[0] * v.x + c[1] * v.y + c[2] * v.z, c[3] * v.x + c[4] * v.y + c[5] * v.z,
                  c[6] * v.x + c[7] * v.y + c[8] * v.z)
        }
        func unit(_ v: SIMD3<Double>) -> SIMD3<Double>? {
            let length = (v * v).sum().squareRoot()
            return length > 1e-300 ? v / length : nil
        }
        // the first main axis, then the second (the first taken out of each step), by power iteration
        var first = SIMD3<Double>(0.48, 0.71, 0.52)
        for _ in 0..<80 { guard let next = unit(times(first)) else { return nil }; first = next }
        var second = SIMD3<Double>(-0.61, 0.23, 0.76)
        second -= (second * first).sum() * first
        for _ in 0..<80 {
            var w = times(second)
            w -= (w * first).sum() * first
            guard let next = unit(w) else { return nil }
            second = next
        }
        let a = SIMD3<Double>(first.y * second.z - first.z * second.y, first.z * second.x - first.x * second.z,
                              first.x * second.y - first.y * second.x)
        guard let axis = unit(a) else { return nil }
        var inner = Double.infinity, outer = 0.0
        for i in 0..<vertexCount {
            let d = SIMD3<Double>(position(i)) - mean
            let off = d - (d * axis).sum() * axis
            let r = (off * off).sum().squareRoot()
            inner = min(inner, r); outer = max(outer, r)
        }
        return AnatomyRing(centre: SIMD3<Float>(mean), axis: SIMD3<Float>(axis), inner: Float(inner), outer: Float(outer))
    }

    /// The direction the structure is longest in (unit length, the sign
    /// arbitrary): the main axis of its vertices' spread, by power iteration
    /// on their covariance. A muscle's fibres run roughly along it (the suite
    /// holds the fibres tools/anatomy_fibres.py lays to that).
    func longAxis() -> SIMD3<Float> {
        guard vertexCount > 1 else { return SIMD3(0, 1, 0) }
        var mean = SIMD3<Double>(repeating: 0)
        for i in 0..<vertexCount { mean += SIMD3<Double>(position(i)) }
        mean /= Double(vertexCount)
        var c = [Double](repeating: 0, count: 9)
        for i in 0..<vertexCount {
            let d = SIMD3<Double>(position(i)) - mean
            for r in 0..<3 { for k in 0..<3 { c[3 * r + k] += d[r] * d[k] } }
        }
        // start off every axis, so no main axis is ever exactly at right angles to the start
        var v = SIMD3<Double>(0.48, 0.71, 0.52)
        for _ in 0..<60 {
            let w = SIMD3<Double>(c[0] * v.x + c[1] * v.y + c[2] * v.z,
                                  c[3] * v.x + c[4] * v.y + c[5] * v.z,
                                  c[6] * v.x + c[7] * v.y + c[8] * v.z)
            let length = (w * w).sum().squareRoot()
            guard length > 0 else { return SIMD3(0, 1, 0) }
            v = w / length
        }
        return SIMD3<Float>(v)
    }

    /// The middle of the structure's box, for framing it in the camera.
    var centre: SIMD3<Float> {
        guard vertexCount > 0 else { return .zero }
        var lo = position(0), hi = lo
        for i in 0..<vertexCount {
            let p = position(i)
            lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
        }
        return (lo + hi) / 2
    }

    private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}

/// A muscle's fibres over its surface, as tools/anatomy_fibres.py lays them:
/// for each vertex a point (two numbers) whose angle about the origin is the
/// same all along a fibre and turns once round the muscle, so the lines the
/// shader draws along the fibres have no seam anywhere; and whose distance
/// from the origin is 2 less its tendon's share (2 in the belly, 1 where it
/// is all tendon).
struct AnatomyFibres: Hashable {
    /// x then y, one vertex after another.
    var around: [Float]

    var vertexCount: Int { around.count / 2 }

    /// Two numbers a vertex, which the muscle's shader (AtlasShaders.muscle)
    /// reads as its texture coordinates: the points as they are.
    func coordinates() -> [Float] { around }

    /// How far vertex `i` is tendon rather than belly, 0 to 1.
    func tendon(_ i: Int) -> Float {
        let x: Float = around[2 * i], y: Float = around[2 * i + 1]
        return min(max(2 - (x * x + y * y).squareRoot(), 0), 1)
    }

    /// Where vertex `i` lies round the muscle, in turns (0 up to 1): the
    /// same all along a fibre.
    func turn(_ i: Int) -> Float {
        let a: Float = atan2(around[2 * i + 1], around[2 * i]) / (2 * Float.pi)
        return a < 0 ? a + 1 : a
    }

    /// Tendon's colour (sRGB): the white of a fresh tendon, a shade warmer and
    /// duller than the sclera's (#F2EEE6), so an eye muscle's tendon reads as
    /// a band on the sclera it inserts on, not a cream patch stuck to it.
    static let tendonColour: (red: Double, green: Double, blue: Double) = (0.94, 0.92, 0.88)

    /// Tendon's linear colour over a muscle's (sRGB `muscle`), per channel:
    /// what the muscle's shader multiplies its colour by where it is tendon.
    static func tendonRatio(muscle: (red: Double, green: Double, blue: Double)) -> SIMD3<Float> {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let t = tendonColour
        return SIMD3(Float(linear(t.red) / max(linear(muscle.red), 1e-4)),
                     Float(linear(t.green) / max(linear(muscle.green), 1e-4)),
                     Float(linear(t.blue) / max(linear(muscle.blue), 1e-4)))
    }
}

/// The atlas's shading of a surface's hollows: a foramen, a groove, a
/// fossa's floor or the crease where two bulges meet catches less of the
/// light round it, as it does in an anatomist's drawing, and in bone a
/// little more of the yellow of age. A multiplier on the tissue's colour
/// from the surface's curvature (AnatomyMesh.curvature, 1/metre): 1 where
/// the surface is flat or bulges, or hollow over a wide span (the iliac
/// fossa, a curvature of some -15); falling to `depth` in a hollow `full`
/// or tighter (a groove some 5 mm across), the blue falling
/// fastest, so it warms as it darkens. It is fixed to the surface, so it
/// does not move with the light.
enum AtlasRelief {
    static let depth: Float = 0.72
    static let start: Float = 15
    static let full: Float = 180

    static func shade(_ curvature: Float) -> SIMD3<Float> {
        let x = min(1, max(0, (-curvature - start) / (full - start)))
        let s = 1 - (1 - depth) * x * x * (3 - 2 * x)
        return SIMD3(s, Float(pow(Double(s), 1.08)), Float(pow(Double(s), 1.2)))
    }
}

enum AnatomyAtlas {

    enum ReadError: Error, Equatable {
        case notAnAtlas
        case truncated(at: Int)
        case structureCount(file: Int, manifest: Int)
        case indexOutOfRange(structure: Int)
        case leftover(bytes: Int)
    }

    static func manifest(from data: Data) throws -> AnatomyManifest {
        try JSONDecoder().decode(AnatomyManifest.self, from: data)
    }

    /// Every structure's mesh in one .atlas file, in the manifest's order.
    static func meshes(from data: Data) throws -> [AnatomyMesh] {
        let bytes: [UInt8] = Array(data)
        var at: Int = 0
        func need(_ n: Int) throws {
            if at + n > bytes.count { throw ReadError.truncated(at: at) }
        }
        func u16() -> UInt16 { let v = UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8; at += 2; return v }
        func u32() -> UInt32 {
            let v = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            at += 4; return v
        }
        func f32() -> Float { Float(bitPattern: u32()) }

        try need(32)
        guard bytes[0] == 0x53, bytes[1] == 0x41, bytes[2] == 0x54, bytes[3] == 0x31 else { throw ReadError.notAnAtlas }
        at = 4
        let count = Int(u32())
        let lo: [Float] = [f32(), f32(), f32()]
        let hi: [Float] = [f32(), f32(), f32()]
        let scale: [Float] = (0..<3).map { (hi[$0] - lo[$0]) / 65535 }
        var out: [AnatomyMesh] = []
        out.reserveCapacity(count)
        for s in 0..<count {
            try need(8)
            let vertices = Int(u32()), triangles = Int(u32())
            let wide: Bool = vertices > 65535
            try need(vertices * 6 + triangles * 3 * (wide ? 4 : 2))
            var positions: [Float] = []
            positions.reserveCapacity(vertices * 3)
            for i in 0..<(vertices * 3) {
                let axis = i % 3
                positions.append(lo[axis] + Float(u16()) * scale[axis])
            }
            var indices: [UInt32] = []
            indices.reserveCapacity(triangles * 3)
            for _ in 0..<(triangles * 3) {
                let index: UInt32 = wide ? u32() : UInt32(u16())
                if Int(index) >= vertices { throw ReadError.indexOutOfRange(structure: s) }
                indices.append(index)
            }
            at += (4 - at % 4) % 4
            out.append(AnatomyMesh(positions: positions, indices: indices))
        }
        if at != bytes.count { throw ReadError.leftover(bytes: bytes.count - at) }
        return out
    }

    /// A part's meshes, checked against what the manifest says it holds.
    static func meshes(of part: AtlasPart, from data: Data) throws -> [AnatomyMesh] {
        let meshes = try meshes(from: data)
        guard meshes.count == part.structures.count else {
            throw ReadError.structureCount(file: meshes.count, manifest: part.structures.count)
        }
        return meshes
    }

    /// Every structure's fibres in one .fibres file, in the manifest's
    /// order (nil for a structure that is not a skeletal muscle):
    /// "SAF2", u32 count, then per structure u32 vertices (0: none) and two
    /// f32 a vertex (AnatomyFibres.around).
    static func fibres(from data: Data) throws -> [AnatomyFibres?] {
        let bytes: [UInt8] = Array(data)
        var at: Int = 0
        func need(_ n: Int) throws {
            if at + n > bytes.count { throw ReadError.truncated(at: at) }
        }
        func u32() -> UInt32 {
            let v = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            at += 4; return v
        }
        try need(8)
        guard bytes[0] == 0x53, bytes[1] == 0x41, bytes[2] == 0x46, bytes[3] == 0x32 else { throw ReadError.notAnAtlas }
        at = 4
        let count = Int(u32())
        // (a structure takes four bytes at least: a count the file cannot hold is refused before any
        // room is set aside for it)
        guard count <= (bytes.count - 8) / 4 else { throw ReadError.truncated(at: 4) }
        var out: [AnatomyFibres?] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            try need(4)
            let vertices = Int(u32())
            guard vertices > 0 else { out.append(nil); continue }
            guard vertices <= (bytes.count - at) / 8 else { throw ReadError.truncated(at: at) }
            let around: [Float] = (0..<(2 * vertices)).map { _ in Float(bitPattern: u32()) }
            out.append(AnatomyFibres(around: around))
        }
        if at != bytes.count { throw ReadError.leftover(bytes: bytes.count - at) }
        return out
    }

    /// A part's fibres, checked against its structures and their meshes:
    /// a structure whose fibres do not match its mesh's vertices gets none.
    static func fibres(of part: AtlasPart, meshes: [AnatomyMesh], from data: Data) throws -> [AnatomyFibres?] {
        let all = try fibres(from: data)
        guard all.count == part.structures.count else {
            throw ReadError.structureCount(file: all.count, manifest: part.structures.count)
        }
        return zip(all, meshes).map { f, m in f.flatMap { $0.vertexCount == m.vertexCount ? $0 : nil } }
    }

    /// Structures in one body whose label holds every word of `query`,
    /// parts in the manifest's order: "left femur", "coronary".
    static func search(_ query: String, in body: AnatomyBody) -> [(part: AtlasPart, structure: AnatomyStructure)] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return [] }
        var out: [(part: AtlasPart, structure: AnatomyStructure)] = []
        for part in body.parts {
            for s in part.structures {
                let label = s.label.lowercased()
                if words.allSatisfy({ label.contains($0) }) { out.append((part, s)) }
            }
        }
        return out
    }

    /// The atlas folder wherever the build put it: the app's own folder,
    /// the Swift package's resource bundle, or a resource bundle inside
    /// the app (Swift Playgrounds).
    static func file(_ name: String) -> URL? {
        var bundles: [Bundle] = [Bundle.main]
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        let inside = (try? FileManager.default.contentsOfDirectory(
            at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)) ?? []
        bundles += inside.filter { $0.pathExtension == "bundle" }.compactMap(Bundle.init(url:))
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        for bundle in bundles {
            if let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "Anatomy") { return url }
        }
        return nil
    }
}

/// A ring's frame in the body's frame (metres): its middle, the unit axis it
/// is turned about (the sign arbitrary), and its radii about that axis.
struct AnatomyRing: Equatable {
    let centre: SIMD3<Float>
    let axis: SIMD3<Float>
    let inner: Float
    let outer: Float
}

