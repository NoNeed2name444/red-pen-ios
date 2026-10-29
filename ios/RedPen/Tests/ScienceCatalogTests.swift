// The Sciences catalog: every subject and body system has its topics, every
// tool is reached from a topic, every atlas part a topic names is in the
// bundled atlas, and the notes are notes, not essays.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let topics = ScienceCatalog.topics
check("ids unique", Set(topics.map(\.id)).count == topics.count)
check("titles unique", Set(topics.map(\.title)).count == topics.count)
check("ids start with their subject's prefix",
      topics.allSatisfy { t in
          let prefix: [ScienceSubject: String] = [.anatomy: "anatomy-", .physiology: "phys-", .biochemistry: "bio-",
                                                  .pathology: "path-", .microbiology: "micro-", .immunology: "imm-",
                                                  .genetics: "gen-", .pharmacology: "pharm-", .biostatistics: "stats-"]
          return t.id.hasPrefix(prefix[t.subject] ?? "?")
      }, topics.filter { !$0.id.contains("-") }.map(\.id).joined(separator: ", "))

// MARK: coverage

let thin = ScienceSubject.allCases.filter { ScienceCatalog.topics($0).count < 2 }
check("every subject has at least two topics", thin.isEmpty, thin.map(\.name).joined(separator: ", "))
check("anatomy, physiology and pathology have the most", [.anatomy, .physiology, .pathology].allSatisfy {
    ScienceCatalog.topics($0).count >= 12
})
for system in BodySystem.allCases {
    let mine = ScienceCatalog.topics(system)
    let missing = [ScienceSubject.anatomy, .physiology, .pathology].filter { s in !mine.contains { $0.subject == s } }
    check("\(system.name): anatomy, physiology and pathology", missing.isEmpty, missing.map(\.name).joined(separator: ", "))
}
let unused = ScienceTool.allCases.filter { tool in !topics.contains { $0.tools.contains(tool) } }
check("every tool is reached from a topic", unused.isEmpty, unused.map(\.rawValue).joined(separator: ", "))
check("every subject has a tool", ScienceSubject.allCases.allSatisfy { !ScienceCatalog.tools($0).isEmpty })
check("a topic's own subject's tool comes first where it has one",
      topics.filter { t in t.tools.contains { $0.subject == t.subject } }.allSatisfy { $0.tools.first?.subject == $0.subject },
      topics.filter { t in t.tools.contains { $0.subject == t.subject } && t.tools.first?.subject != t.subject }.map(\.id).joined(separator: ", "))
check("anatomy topics open the atlas", ScienceCatalog.topics(.anatomy).allSatisfy { $0.tools.first == .atlas && !$0.atlas.isEmpty })

// MARK: the atlas parts named are in the atlas

let folder = URL(fileURLWithPath: "ios/RedPen/Resources/Anatomy")
if let data = try? Data(contentsOf: folder.appendingPathComponent("anatomy.json")),
   let manifest = try? AnatomyAtlas.manifest(from: data) {
    let ids = Set(manifest.parts.map(\.id))
    let unknown = topics.flatMap(\.atlas).filter { !ids.contains($0) }
    check("every atlas part a topic names is bundled", unknown.isEmpty, unknown.joined(separator: ", "))
    let shown = Set(topics.flatMap(\.atlas))
    let unshown = manifest.parts.map(\.id).filter { !shown.contains($0) }
    check("every bundled part is reached from a topic", unshown.isEmpty, unshown.joined(separator: ", "))
} else {
    check("the atlas manifest reads", false)
}

// MARK: the writing

let longNotes = topics.filter { $0.note.count < 80 || $0.note.count > 420 }
check("notes are two or three sentences (80 to 420 characters)", longNotes.isEmpty,
      longNotes.map { "\($0.id) \($0.note.count)" }.joined(separator: ", "))
check("one to four points each, none empty",
      topics.allSatisfy { (1...4).contains($0.points.count) && $0.points.allSatisfy { $0.count > 10 } },
      topics.filter { !(1...4).contains($0.points.count) }.map(\.id).joined(separator: ", "))
check("notes end with a full stop, points do not",
      topics.allSatisfy { $0.note.hasSuffix(".") && $0.points.allSatisfy { !$0.hasSuffix(".") } },
      topics.filter { !$0.note.hasSuffix(".") || $0.points.contains { $0.hasSuffix(".") } }.map(\.id).joined(separator: ", "))
// whole words: oedema and angioedema are right, edema is not ("fetal" is
// British medical usage too)
let american = #"\b(hemoglobin|edema|anemia|tumors?|center|esophag\w*|estrogen)\b"#
let spelled = topics.filter { t in
    let text = ([t.title, t.note] + t.points).joined(separator: " ").lowercased()
    return text.range(of: american, options: .regularExpression) != nil
}
check("British spelling, as the rest of the app", spelled.isEmpty, spelled.map(\.id).joined(separator: ", "))
check("tool blurbs are a line", ScienceTool.allCases.allSatisfy { $0.blurb.count < 90 && !$0.blurb.hasSuffix(".") },
      ScienceTool.allCases.filter { $0.blurb.count >= 90 }.map(\.rawValue).joined(separator: ", "))

// MARK: facts the tools also state, kept the same

check("the nephrotic line is the pathology tool's", ScienceCatalog.topic("path-glomerular")?.points.first?.contains("3.5 g") == true
      && Pathology.nephroticProtein == 3.5)
check("the infarct topic's rupture window is the tool's",
      ScienceCatalog.topic("path-mi")?.points.first?.hasPrefix("Days 3 to 7") == true
        && Pathology.infarctStage(hours: 96)?.risk?.contains("Rupture") == true)
check("the shock topic names what the tool reads",
      ScienceCatalog.topic("path-shock")?.note.contains("wedge pressure") == true
        && Pathology.readShock(cardiacOutput: .up, resistance: .down, wedge: .down) == [.distributive])

// MARK: search

check("search finds the heart's anatomy", ScienceCatalog.search("left ventricle").contains { $0.id == "anatomy-heart" })
check("search needs every word", ScienceCatalog.search("sickle valine").map(\.id) == ["gen-code"])
check("an empty search finds nothing", ScienceCatalog.search(" ").isEmpty)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
