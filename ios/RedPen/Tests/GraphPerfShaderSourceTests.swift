// The map's Metal programs, compiled at run time from Swift strings
// (MTLDevice.makeLibrary(source:)), checked here the way the app hands them
// over: the same `source` string, whole. Linux has no Metal compiler, so
// this checks what can go wrong in a program's names without one:
//   S1 every top-level declaration is one this test recognises, so a new
//      kind is never skipped quietly;
//   S2 no top-level name is declared twice in a program;
//   S3 every top-level function and constant carries its program's prefix.
//      `using namespace metal;` puts all of metal_stdlib in scope, and Linux
//      cannot read that header: a plain helper name can collide with it.
//      The million map's `quad` did ("redefinition of 'quad' as different
//      kind of symbol"), so the map never drew on the Mac;
//   S4 every top-level struct is CamelCase (metal_stdlib's types and
//      functions are lower case).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

struct Program {
    let name: String
    let prefix: String
    let source: String
}

let programs = [
    Program(name: "Performance map", prefix: "perf_", source: GraphPerfShaders.source),
    Program(name: "million map", prefix: "mil_", source: GraphPerfMillionShaders.source)
]

enum Kind: String { case function, constant, structure }

struct Declaration {
    let kind: Kind
    let name: String
    let line: Int
}

func firstMatch(_ pattern: String, _ text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r])
}

/// The program's top-level declarations, and the top-level lines that are
/// none this reads. A top-level line starts in the first column (the
/// strings' own indentation is gone); a signature's later lines are indented.
func topLevel(_ source: String) -> (found: [Declaration], unread: [String]) {
    var found: [Declaration] = []
    var unread: [String] = []
    for (i, line) in source.components(separatedBy: "\n").enumerated() {
        guard let first = line.first, !first.isWhitespace else { continue }
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("//") || text.hasPrefix("}") || text == "#include <metal_stdlib>"
            || text == "using namespace metal;" { continue }
        if let n = firstMatch(#"^struct\s+(\w+)\s*\{"#, text) {
            found.append(Declaration(kind: .structure, name: n, line: i + 1))
        } else if let n = firstMatch(#"^(?:static\s+)?(?:constant|constexpr\s+constant)\s+[\w:<>, ]+?\s+(\w+)\s*(?:\[[^\]]*\])?\s*="#, text) {
            found.append(Declaration(kind: .constant, name: n, line: i + 1))
        } else if let n = firstMatch(#"^(?:static\s+)?(?:inline\s+)?(?:kernel\s+|vertex\s+|fragment\s+)?[\w:<>, ]+?[\s&*]+(\w+)\s*\("#, text) {
            found.append(Declaration(kind: .function, name: n, line: i + 1))
        } else {
            unread.append("\(i + 1): \(text)")
        }
    }
    return (found, unread)
}

for p in programs {
    let (found, unread) = topLevel(p.source)
    check("S1 \(p.name): every top-level line is a declaration this test reads", unread.isEmpty,
          unread.joined(separator: " / "))
    check("S1 \(p.name): its declarations are found", found.count > 5, "\(found.count)")

    var seen: [String: Int] = [:]
    var twice: [String] = []
    for d in found {
        if let before = seen[d.name] { twice.append("\(d.name) at \(before) and \(d.line)") }
        seen[d.name] = d.line
    }
    check("S2 \(p.name): no top-level name is declared twice", twice.isEmpty, twice.joined(separator: ", "))

    let bare = found.filter { $0.kind != .structure && !$0.name.hasPrefix(p.prefix) }
        .map { "\($0.name) (line \($0.line))" }
    check("S3 \(p.name): every top-level function and constant starts \(p.prefix)", bare.isEmpty,
          bare.joined(separator: ", "))

    let lower = found.filter { $0.kind == .structure && !($0.name.first?.isUppercase ?? false) }.map(\.name)
    check("S4 \(p.name): every struct is CamelCase", lower.isEmpty, lower.joined(separator: ", "))
}

// the entry points the renderers look up by name are all declared
for (p, names) in [(programs[0], GraphPerfShaders.functions), (programs[1], GraphPerfMillionShaders.functions)] {
    let declared = Set(topLevel(p.source).found.filter { $0.kind == .function }.map(\.name))
    let missing = names.filter { !declared.contains($0) }
    check("S5 \(p.name): every function the renderer looks up is declared", missing.isEmpty,
          missing.joined(separator: ", "))
}

// the reader itself: a doubled name, a bare helper and an unread line are each caught
let sample = """
#include <metal_stdlib>
using namespace metal;
struct Frame {
    float4 eye;
};
static float2 quad(uint vid) {
    return float2(0.0);
}
static float mil_a(float x) { return x; }
static float mil_a(float x) { return x; }
constant float mil_scale = 2.0;
#define MIL_X 1
"""
let read = topLevel(sample)
check("S6 the reader finds the sample's declarations",
      read.found.map(\.name) == ["Frame", "quad", "mil_a", "mil_a", "mil_scale"], "\(read.found.map(\.name))")
check("S6 and the line it cannot read", read.unread == ["12: #define MIL_X 1"], "\(read.unread)")

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
