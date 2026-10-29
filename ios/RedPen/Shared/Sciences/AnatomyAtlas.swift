import Foundation

/// The 3D anatomy atlas: the manifest (Resources/Anatomy/anatomy.json) and
/// the meshes of each part (<body>-<part>.atlas), made by
/// tools/anatomy_atlas.py from the Human Reference Atlas's male and female
/// reference organ sets, with the skull from NIH 3D and the ribs, shoulder
/// girdle, humeri, hip and back muscles, thyroid, adrenals, oesophagus and
/// stomach from two TotalSegmentator CT scans, which tools/anatomy_gaps.py
/// carries into each body (all CC BY 4.0; sources and credits in
/// Resources/Anatomy/SOURCES.md).
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

    /// The label as a title: the first letter capitalised.
    var title: String { label.prefix(1).uppercased() + label.dropFirst() }

    var uberonURL: String? {
        uberon.map { "http://purl.obolibrary.org/obo/" + $0.replacingOccurrences(of: ":", with: "_") }
    }

    /// Where the mesh comes from when it is not the body's own organ set's:
    /// another person's scan, fitted to this body, which the card says.
    var origin: String? {
        if node.hasPrefix("TS_") { return "From a CT scan (TotalSegmentator), fitted to this body" }
        if node.hasPrefix("NLM_") { return "The Visible Human Male's skull (NIH 3D), fitted to this body" }
        return nil
    }
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

/// What a structure is made of; the atlas is coloured by it.
enum AnatomyTissue: String, Decodable, CaseIterable, Identifiable {
    case skin, fat, bone, cartilage, ligament, muscle, artery, vein, heart, nerve, brain
    case organ, gland, duct, airway, lung, gut, lymph, eye, fluid, tooth
    var id: String { rawValue }

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The colour the textbooks use for it, in sRGB 0...1: arteries red,
    /// veins blue, nerves yellow, bone ivory.
    var colour: (red: Double, green: Double, blue: Double) {
        let hex: Int
        switch self {
        case .skin: hex = 0xE8B89A
        case .fat: hex = 0xF2D27A
        case .bone: hex = 0xE9E2CF
        case .cartilage: hex = 0xB8D4E3
        case .ligament: hex = 0xD9CFA8
        case .muscle: hex = 0xB5483F
        case .artery: hex = 0xC8302C
        case .vein: hex = 0x3D5FB0
        case .heart: hex = 0xB33A3A
        case .nerve: hex = 0xE3C84A
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
        var sums: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let pa = position(a), pb = position(b), pc = position(c)
            let n = cross(pb - pa, pc - pa)
            sums[a] += n; sums[b] += n; sums[c] += n
        }
        var out: [Float] = []
        out.reserveCapacity(positions.count)
        for s in sums {
            let length = (s * s).sum().squareRoot()
            let n = length > 0 ? s / length : SIMD3<Float>(0, 1, 0)
            out += [n.x, n.y, n.z]
        }
        return out
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
