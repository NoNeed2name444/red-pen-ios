// tools/atlas_lab's reader: the chosen parts of one atlas body, read and
// shaded the way the app reads them (AnatomyAtlas.meshes, each part's
// structures welded into one surface by AnatomyMesh.normals(welding:)),
// written for scene.cpp: "ATL2", the structure count, then per structure its
// tissue's linear colour and roughness, its surface (0 plain, 1 bone, 2
// muscle), its long axis, its name, and its vertices, normals, the relief's
// shade at each vertex (AtlasRelief, from AnatomyMesh.curvature(welding:)),
// and its triangles.
//   dump <atlas folder> <male|female> <out> <part,part,...>
import Foundation

let args = CommandLine.arguments
guard args.count >= 5 else { print("dump <atlas folder> <male|female> <out> <parts>"); exit(2) }
let folder = URL(fileURLWithPath: args[1])
let manifest = try! AnatomyAtlas.manifest(from: Data(contentsOf: folder.appendingPathComponent("anatomy.json")))
guard let body = manifest.body(args[2] == "female" ? .female : .male) else { exit(2) }
let wanted: Set<String> = Set(args[4].split(separator: ",").map(String.init))
var out = Data("ATL2".utf8)
func put<T>(_ v: T) { withUnsafeBytes(of: v) { out.append(contentsOf: $0) } }
func linear(_ c: Double) -> Float { Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)) }
var chosen: [(AnatomyStructure, AnatomyMesh, [Float], [Float])] = []
for part in body.parts where wanted.contains(part.id) || wanted.contains("all") {
    let meshes = try! AnatomyAtlas.meshes(of: part, from: Data(contentsOf: folder.appendingPathComponent(part.file)))
    let normals = AnatomyMesh.normals(welding: meshes)
    let bends = AnatomyMesh.curvature(welding: meshes)
    for (k, structure) in part.structures.enumerated() where structure.tissue != .skin && structure.tissue != .fat {
        chosen.append((structure, meshes[k], normals[k], bends[k].flatMap { c -> [Float] in
            let s = AtlasRelief.shade(c)
            return [s.x, s.y, s.z]
        }))
    }
}
put(UInt32(chosen.count))
for (structure, mesh, normals, relief) in chosen {
    let c = structure.tissue.colour
    put(linear(c.red)); put(linear(c.green)); put(linear(c.blue)); put(Float(structure.tissue.roughness))
    put(UInt32(structure.tissue == .bone ? 1 : structure.tissue == .muscle ? 2 : 0))
    let axis = mesh.longAxis()
    put(axis.x); put(axis.y); put(axis.z)
    let name = Array(structure.node.utf8)
    put(UInt32(name.count)); out.append(contentsOf: name)
    put(UInt32(mesh.vertexCount)); put(UInt32(mesh.triangleCount))
    mesh.positions.withUnsafeBytes { out.append(contentsOf: $0) }
    normals.withUnsafeBytes { out.append(contentsOf: $0) }
    relief.withUnsafeBytes { out.append(contentsOf: $0) }
    mesh.indices.withUnsafeBytes { out.append(contentsOf: $0) }
}
try! out.write(to: URL(fileURLWithPath: args[3]))
print("\(chosen.count) structures")
