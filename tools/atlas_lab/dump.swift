// tools/atlas_lab's reader: the chosen parts of one atlas body, read and
// shaded the way the app reads them (AnatomyAtlas.meshes, each part's
// structures welded into one surface by AnatomyMesh.normals(welding:)),
// written for scene.cpp: "ATL5", the structure count, then per structure (what
// is solid, and what is see-through by its own look, as the eye's clear parts:
// not the skin or fat) its linear colour, roughness and opacity (its own or its
// tissue's), its surface (0 plain, 1 bone, 2 muscle, 3 iris), its long axis
// (the iris: the axis it is turned about), the bundles' width and tendon's
// colour over muscle's (the muscle shader's rpBundle and rpTendon), the
// iris's middle and its radii (AnatomyMesh.ringFrame; others' 0), its name, and its
// vertices, normals, the relief's shade at each vertex (AtlasRelief, from
// AnatomyMesh.curvature(welding:); 1 on what is see-through, as the app
// leaves it), its texture coordinates (a muscle's
// bundles, AnatomyStripes.coordinates, from its part's .fibres file;
// others' 0) and its triangles.
//   dump <atlas folder> <male|female> <out> <part,part,...>
import Foundation

let args = CommandLine.arguments
guard args.count >= 5 else { print("dump <atlas folder> <male|female> <out> <parts>"); exit(2) }
let folder = URL(fileURLWithPath: args[1])
let manifest = try! AnatomyAtlas.manifest(from: Data(contentsOf: folder.appendingPathComponent("anatomy.json")))
guard let body = manifest.body(args[2] == "female" ? .female : .male) else { exit(2) }
let wanted: Set<String> = Set(args[4].split(separator: ",").map(String.init))
var out = Data("ATL5".utf8)
func put<T>(_ v: T) { withUnsafeBytes(of: v) { out.append(contentsOf: $0) } }
func linear(_ c: Double) -> Float { Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)) }
var chosen: [(AnatomyStructure, AnatomyMesh, [Float], [Float], AnatomyStripes?)] = []
for part in body.parts where wanted.contains(part.id) || wanted.contains("all") {
    let meshes = try! AnatomyAtlas.meshes(of: part, from: Data(contentsOf: folder.appendingPathComponent(part.file)))
    let normals = AnatomyMesh.normals(welding: meshes)
    let bends = AnatomyMesh.curvature(welding: meshes)
    var stripes: [AnatomyStripes?] = Array(repeating: nil, count: meshes.count)
    if let fibres = part.fibres {
        stripes = try! AnatomyAtlas.stripes(of: part, meshes: meshes, from: Data(contentsOf: folder.appendingPathComponent(fibres.file)))
    }
    for (k, structure) in part.structures.enumerated() where structure.opacity == 1 || structure.ownOpacity != nil {
        chosen.append((structure, meshes[k], normals[k], structure.opacity < 1
            ? [Float](repeating: 1, count: 3 * meshes[k].vertexCount)
            : bends[k].flatMap { c -> [Float] in
                let s = AtlasRelief.shade(c)
                return [s.x, s.y, s.z]
            }, stripes[k]))
    }
}
put(UInt32(chosen.count))
for (structure, mesh, normals, relief, stripes) in chosen {
    let c = structure.colour
    put(linear(c.red)); put(linear(c.green)); put(linear(c.blue)); put(Float(structure.roughness)); put(Float(structure.opacity))
    let ring: AnatomyRing? = structure.iris ? mesh.ringFrame() : nil
    put(UInt32(structure.tissue == .bone ? 1 : structure.tissue == .muscle ? 2 : ring != nil ? 3 : 0))
    let axis = ring?.axis ?? mesh.longAxis()
    let bundle: Float = stripes?.bundle ?? 0
    let coordinates: [Float] = stripes?.coordinates() ?? [Float](repeating: 0, count: 2 * mesh.vertexCount)
    let tendon = AnatomyStripes.tendonRatio(muscle: structure.colour)
    put(axis.x); put(axis.y); put(axis.z); put(bundle); put(tendon.x); put(tendon.y); put(tendon.z)
    let centre = ring?.centre ?? .zero
    put(centre.x); put(centre.y); put(centre.z); put(ring?.inner ?? 0); put(ring?.outer ?? 0)
    let name = Array(structure.node.utf8)
    put(UInt32(name.count)); out.append(contentsOf: name)
    put(UInt32(mesh.vertexCount)); put(UInt32(mesh.triangleCount))
    mesh.positions.withUnsafeBytes { out.append(contentsOf: $0) }
    normals.withUnsafeBytes { out.append(contentsOf: $0) }
    relief.withUnsafeBytes { out.append(contentsOf: $0) }
    coordinates.withUnsafeBytes { out.append(contentsOf: $0) }
    mesh.indices.withUnsafeBytes { out.append(contentsOf: $0) }
}
try! out.write(to: URL(fileURLWithPath: args[3]))
print("\(chosen.count) structures")
