// The 3D map's shader modifiers (GraphShaderCatalog), read the way Metal's
// compiler would read them - before a device does. SceneKit compiles a
// shader modifier only at run time, and one that fails just draws the plain
// fallback, so a typo would otherwise show up only as a duller map.
//
// For every shader: brackets balance; every rp_ name is declared before it
// is used and not declared twice in one scope; every rp argument it uses is
// declared under #pragma arguments (and every declared one is used); no
// GLSL or HLSL spelling (vec3, mod, lerp, frac, atan(y, x)); no vector set
// from a bare number (Metal wants float3(x)); a surface modifier ends by
// writing _surface.diffuse with rpProbe in it (the probes' check), and a
// geometry modifier writes _geometry; and a material's geometry and surface
// modifiers never declare the same argument (SceneKit fails such a
// material). tools/shader_check.py goes further (a real compile against a
// stand-in for Metal) where clang is installed.
//
// Compiled with GraphSpaceShaders.swift, GraphNeuronShaders.swift and
// GraphShaderCatalog.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: reading a shader

let types: Set<String> = ["float", "float2", "float3", "float4", "float3x3", "float4x4", "int", "int2", "int3",
                          "int4", "uint", "uint2", "uint3", "bool", "half", "half3", "half4"]

/// The source without // comments.
func stripComments(_ text: String) -> [String] {
    text.components(separatedBy: "\n").map { line in
        if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
        return line
    }
}

/// Identifiers and single characters, in order (numbers kept whole).
func tokens(_ line: String) -> [String] {
    var out: [String] = []
    var word: String = ""
    var number: Bool = false
    for ch in line {
        let isWordChar: Bool = ch.isLetter || ch.isNumber || ch == "_"
        if isWordChar || (number && ch == ".") {
            if word.isEmpty { number = ch.isNumber }
            word.append(ch)
            continue
        }
        if !word.isEmpty {
            out.append(word)
            word = ""
        }
        number = false
        if ch == "." && !out.isEmpty {
            out.append(".")
            continue
        }
        if !ch.isWhitespace { out.append(String(ch)) }
    }
    if !word.isEmpty { out.append(word) }
    return out
}

struct ShaderReport {
    var problems: [String] = []
    /// Legal, but worth a look (an argument declared and never read).
    var notes: [String] = []
    var arguments: [String] = []
}

func read(_ item: GraphShaderItem) -> ShaderReport {
    var report = ShaderReport()
    let lines: [String] = stripComments(item.source)
    var section: String = "body"
    var args: Set<String> = []
    var argOrder: [String] = []
    var scopes: [Set<String>] = [[]]
    var usedArgs: Set<String> = []
    var round: Int = 0
    var square: Int = 0
    var wroteDiffuse: Bool = false
    var probeInDiffuse: Bool = false
    var wroteGeometry: Bool = false
    for (n, raw) in lines.enumerated() {
        let line: String = raw.trimmingCharacters(in: .whitespaces)
        let at: String = "line \(n + 1)"
        if line.hasPrefix("#pragma") {
            if line.contains("arguments") { section = "args" }
            if line.contains("body") { section = "body" }
            continue
        }
        if line.isEmpty { continue }
        if section == "args" {
            let parts: [String] = tokens(line)
            if parts.count == 3, types.contains(parts[0]), parts[2] == ";" {
                if args.contains(parts[1]) { report.problems.append(at + ": argument declared twice: " + parts[1]) }
                args.insert(parts[1])
                argOrder.append(parts[1])
            } else {
                report.problems.append(at + ": not an argument: " + line)
            }
            continue
        }
        // GLSL and HLSL spellings, and a vector set from a bare number
        let t: [String] = tokens(line)
        for (k, word) in t.enumerated() {
            if ["vec2", "vec3", "vec4", "mat3", "mat4", "mod", "lerp", "frac", "inversesqrt", "texture2D"]
                .contains(word), k + 1 < t.count, t[k + 1] == "(" || ["vec2", "vec3", "vec4", "mat3", "mat4"].contains(word) {
                report.problems.append(at + ": not Metal: " + word)
            }
        }
        if t.count >= 5, ["float2", "float3", "float4", "int2", "int3", "uint3"].contains(t[0]), t[2] == "=",
           t[3].first?.isNumber == true || (t[3] == "-" && t[4].first?.isNumber == true),
           t.last == ";", t.count <= 6 {
            report.problems.append(at + ": a vector set from a bare number: " + line)
        }
        // atan with two arguments is GLSL's atan2
        if let r = line.range(of: "atan(") {
            var depth: Int = 1
            var comma: Bool = false
            for ch in line[r.upperBound...] {
                if ch == "(" { depth += 1 }
                if ch == ")" { depth -= 1; if depth == 0 { break } }
                if ch == "," && depth == 1 { comma = true }
            }
            if comma { report.problems.append(at + ": atan(y, x) is GLSL; Metal spells it atan2") }
        }
        // walk the tokens: scopes, declarations, uses. A declared name is
        // visible from the end of its initialiser (the next ";"); a for
        // loop's variable belongs to the block the loop opens.
        var k: Int = 0
        var inFor: Bool = false
        var pending: [String] = []
        var declareAt: Int = -1
        var declaring: String = ""
        func declare(_ name: String) {
            if inFor {
                if pending.contains(name) { report.problems.append(at + ": declared twice in one scope: " + name) }
                pending.append(name)
            } else {
                if scopes[scopes.count - 1].contains(name) {
                    report.problems.append(at + ": declared twice in one scope: " + name)
                }
                scopes[scopes.count - 1].insert(name)
            }
        }
        while k < t.count {
            let word: String = t[k]
            if k == declareAt {
                declare(declaring)
                declareAt = -1
            }
            switch word {
            case "for": inFor = true
            case "{":
                scopes.append(Set(pending))
                pending = []
                inFor = false
            case "}":
                if scopes.count > 1 { scopes.removeLast() } else { report.problems.append(at + ": a } too many") }
            case "(": round += 1
            case ")": round -= 1
            case "[": square += 1
            case "]": square -= 1
            default:
                let next: String = k + 1 < t.count ? t[k + 1] : ""
                if types.contains(word) && next.hasPrefix("rp_") {
                    // a declaration: the name counts from its initialiser's end
                    var j: Int = k + 2
                    while j < t.count && t[j] != ";" { j += 1 }
                    // (no ";" on this line: from the line's end)
                    declaring = next
                    declareAt = j
                    k += 2
                    continue
                }
                if word.hasPrefix("rp_") {
                    if !scopes.contains(where: { $0.contains(word) }) && !pending.contains(word) {
                        report.problems.append(at + ": used before it is declared: " + word)
                    }
                } else if word.hasPrefix("rp") && word.count > 2 && word.dropFirst(2).first?.isUppercase == true {
                    usedArgs.insert(word)
                }
            }
            k += 1
        }
        if declareAt >= t.count { declare(declaring) }
        if line.hasPrefix("_surface.diffuse =") {
            wroteDiffuse = true
            probeInDiffuse = line.contains("rpProbe")
        }
        if line.hasPrefix("_geometry.") { wroteGeometry = true }
    }
    if round != 0 { report.problems.append("round brackets do not balance (\(round))") }
    if square != 0 { report.problems.append("square brackets do not balance (\(square))") }
    if scopes.count != 1 { report.problems.append("braces do not balance") }
    for name in usedArgs where !args.contains(name) {
        report.problems.append("argument used but not declared: " + name)
    }
    for name in argOrder where !usedArgs.contains(name) {
        report.notes.append("argument declared but never used: " + name)
    }
    if item.entry == "surface" {
        if !wroteDiffuse { report.problems.append("never writes _surface.diffuse") }
        if wroteDiffuse && !probeInDiffuse { report.problems.append("_surface.diffuse is written without rpProbe") }
    } else if !wroteGeometry {
        report.problems.append("a geometry modifier that never writes _geometry")
    }
    report.arguments = argOrder
    return report
}

// MARK: S1 every shader reads clean

let all: [GraphShaderItem] = GraphShaderCatalog.all
check("S1 the catalogue lists every theme's shaders", GraphShaderCatalog.space.count >= 18
      && GraphShaderCatalog.neurons.count >= 7, "\(all.count)")
check("S1 names are unique", Set(all.map(\.name)).count == all.count)
check("S1 entry points are SceneKit's", all.allSatisfy { $0.entry == "surface" || $0.entry == "geometry" })
var dirty: [String] = []
var argumentsOf: [String: Set<String>] = [:]
for item in all {
    let report: ShaderReport = read(item)
    for problem in report.problems.prefix(3) { dirty.append(item.name + ": " + problem) }
    for note in report.notes { print("NOTE " + item.name + ": " + note) }
    argumentsOf[item.name] = Set(report.arguments)
}
check("S1 every shader: declared before use, arguments declared, brackets balance, Metal only",
      dirty.isEmpty, dirty.prefix(12).joined(separator: " / "))
// SceneKit fails a material whose geometry and surface modifiers declare
// the same argument: each pair must keep its own
var shared: [String] = []
for (geometry, surface) in GraphShaderCatalog.pairs {
    let both: Set<String> = (argumentsOf[geometry] ?? []).intersection(argumentsOf[surface] ?? [])
    if !both.isEmpty || argumentsOf[geometry] == nil || argumentsOf[surface] == nil {
        shared.append(geometry + "+" + surface + ": " + both.sorted().joined(separator: ","))
    }
}
check("S1 a material's geometry and surface modifiers never declare the same argument", shared.isEmpty,
      "\(shared)")

// MARK: S2 the reader catches what it should

let broken: [(String, String)] = [
    ("undeclared", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = rp_b;\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("twice", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = 1.0;\nfloat rp_a = 2.0;\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("argument", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = rpGain;\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("for", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = 0.0;\nfor (int rp_j = 0; rp_j < 3; rp_j++) {\nrp_a = rp_a + 1.0;\n}\nrp_a = rp_a + float(rp_j);\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("self", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = rp_a + 1.0;\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("brackets", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = (1.0;\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("glsl", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = mod(3.0, 2.0);\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("atan", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = atan(1.0, 2.0);\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);"),
    ("splat", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat3 rp_c = 0.5;\n_surface.diffuse = float4(rp_c + float3(rpProbe), 1.0);"),
    ("probe", "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = rpProbe;\n_surface.diffuse = float4(float3(rp_a), 1.0);"),
    ("scope", "#pragma arguments\nfloat rpProbe;\n#pragma body\nif (rpProbe > 0.5) {\nfloat rp_a = 1.0;\n}\n_surface.diffuse = float4(float3(rp_a + rpProbe), 1.0);")
]
var missed: [String] = []
for (name, source) in broken where read(GraphShaderItem(name: name, entry: "surface", source: source)).problems.isEmpty {
    missed.append(name)
}
check("S2 a broken shader is caught (undeclared, twice, arguments, brackets, GLSL, splat, probe, scope)",
      missed.isEmpty, "\(missed)")
let fine: String = "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat rp_a = 1.0;\nif (rp_a > 0.5) {\nfloat rp_b = rp_a;\nrp_a = rp_b;\n}\nif (rp_a > 0.2) {\nfloat rp_b = 2.0;\nrp_a = rp_b;\n}\n_surface.diffuse = float4(float3(rp_a) + float3(rpProbe), 1.0);"
let fineReport: ShaderReport = read(GraphShaderItem(name: "fine", entry: "surface", source: fine))
check("S2 the same name in two sibling blocks is fine", fineReport.problems.isEmpty, "\(fineReport.problems)")

// MARK: S3 the shared noise (GraphShaderKit), on the CPU as on the GPU

var outside: Int = 0
var worstJump: Float = 0
var sum: Float = 0
var lowest: Float = 1
var highest: Float = 0
var samples: Int = 0
for k in 0..<3000 {
    let p = SIMD3<Float>(Float(k % 37) * 0.731 - 13, Float(k % 53) * 0.419 - 11, Float(k / 37) * 0.293 - 7)
    let v: Float = GraphShaderKit.value(p)
    if v < 0 || v > 1 { outside += 1 }
    sum += v
    samples += 1
    lowest = min(lowest, v)
    highest = max(highest, v)
    // either side of the lattice face just below p.x: no jump
    let face: Float = p.x.rounded(.down)
    let a: Float = GraphShaderKit.value(SIMD3<Float>(face - 0.0005, p.y, p.z))
    let b: Float = GraphShaderKit.value(SIMD3<Float>(face + 0.0005, p.y, p.z))
    worstJump = max(worstJump, abs(a - b))
}
let mean: Float = sum / Float(max(samples, 1))
check("S3 value noise stays in 0...1", outside == 0, "\(outside) outside")
check("S3 value noise is continuous across cell faces", worstJump < 0.02, "\(worstJump)")
check("S3 value noise is varied, centred near a half", mean > 0.35 && mean < 0.65 && highest - lowest > 0.7,
      "mean \(mean), \(lowest)...\(highest)")
var fbmOutside: Int = 0
for k in 0..<500 {
    let p = SIMD3<Float>(Float(k) * 0.137, Float(k % 7) * 0.71, Float(k % 11) * 0.31)
    let v: Float = GraphShaderKit.fbm(p, octaves: 5)
    if v < 0 || v > 1 { fbmOutside += 1 }
}
check("S3 fBm stays in 0...1", fbmOutside == 0)
check("S3 the same point gives the same noise", GraphShaderKit.value(SIMD3<Float>(1.3, -2.7, 4.1))
      == GraphShaderKit.value(SIMD3<Float>(1.3, -2.7, 4.1)))
// the Metal it writes: every name it declares starts with the result's
let snippet: String = GraphShaderKit.noise("rp_q", "rp_p * 2.0") + GraphShaderKit.fbm("rp_f", "rp_p", octaves: "3")
var strays: [String] = []
for line in snippet.components(separatedBy: "\n") {
    let t: [String] = tokens(line)
    for k in 0..<max(t.count - 1, 0) where types.contains(t[k]) && t[k + 1].hasPrefix("rp_") {
        let name: String = t[k + 1]
        if !(name.hasPrefix("rp_q") || name.hasPrefix("rp_f")) { strays.append(name) }
    }
}
check("S3 the kit's Metal names everything after its result", strays.isEmpty, "\(strays)")
let kitShader = GraphShaderItem(name: "kit", entry: "surface", source: "#pragma arguments\nfloat rpProbe;\n#pragma body\nfloat3 rp_p = float3(1.0, 2.0, 3.0);\n"
    + snippet + "_surface.diffuse = float4(float3(rp_q + rp_f + rpProbe), 1.0);")
check("S3 the kit's Metal reads clean, used twice in one shader", read(kitShader).problems.isEmpty,
      "\(read(kitShader).problems.prefix(3))")

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
