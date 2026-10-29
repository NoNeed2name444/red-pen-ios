// Where a set's content came from, and whose licence it carries: the
// lectures it was made from and how many questions cite each, the exam's
// style bank, the public sources its checks read, and the app's own list.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func question(_ stem: String, source: String? = nil, evidence: [EvidenceRef] = []) -> MCQQuestion {
    MCQQuestion(stem: stem, options: ["a", "b", "c", "d"], correctIndex: 0, explanation: "",
                source: source,
                differential: evidence.isEmpty ? nil : DifferentialTiers(evidence: evidence))
}

// MARK: citations, as Provenance writes them

check("a citation names its lecture",
      SetCredits.lectureName(Provenance.label("Lupus", page: 14)) == "Lupus",
      SetCredits.lectureName(Provenance.label("Lupus", page: 14)))
check("a lecture whose name has a comma in it",
      SetCredits.lectureName(Provenance.label("Renal, part 2", page: 3)) == "Renal, part 2")
check("a citation with no lecture name names none",
      SetCredits.lectureName(Provenance.label("", page: 3)) == "")
check("cites matches the lecture and no other",
      SetCredits.cites("Lupus, p. 14", "Lupus") && !SetCredits.cites("Lupus, p. 14", "Lupus 2"))

// MARK: one set

let lupus = SourceDoc(name: "Lupus", kind: .pdf,
                      pages: [.init(number: 1, text: "SLE"), .init(number: 2, text: "Malar rash", recognised: true)])
let renal = SourceDoc(name: "Renal", kind: .powerpoint, pages: [.init(number: 1, text: "Nephritis")])
let medline = EvidenceRef(id: "m1", source: "MedlinePlus", title: "Lupus", url: "https://medlineplus.gov/lupus.html")
let pmc = EvidenceRef(id: "p1", source: "Europe PMC", title: "Lupus nephritis (Kidney Int, 2024)", url: "https://doi.org/10.1/x")
let fda = EvidenceRef(id: "f1", source: "openFDA label", title: "hydroxychloroquine (FDA label, effective 2025)",
                      url: "https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=1")
let odd = EvidenceRef(id: "x1", source: "Somewhere new", title: "A page", url: "https://example.org/a")

var set = StudySet(name: "SLE", kind: .mcq)
set.sources = [lupus, renal]
set.questions = [
    question("q1", source: "Lupus, p. 1", evidence: [medline, pmc]),
    question("q2", source: "Lupus, p. 2", evidence: [medline]),          // the same MedlinePlus page again
    question("q3", source: "Renal, p. 1", evidence: [fda, odd]),
    question("q4", source: "Cardio, p. 9"),                               // a lecture no longer kept
    question("q5"),                                                        // typed in
]
var card = AnkiCard(type: .qa)
card.source = "Renal, p. 1"                                               // a card cites a page too
set.cards = [card]
let credits = SetCredits.make(set, exam: (name: "USMLE Step 2 CK", bank: "medqa-step23"))

check("every lecture is listed, in the set's order",
      credits.lectures.map(\.source.name) == ["Lupus", "Renal"], "\(credits.lectures.map(\.source.name))")
check("with how many questions and cards cite each",
      credits.lectures.map(\.cited) == [2, 2], "\(credits.lectures.map(\.cited))")
check("a lecture's detail says its kind, its pages and how many were read from pictures",
      credits.lectures[0].detail == "PDF \u{00B7} 2 pages \u{00B7} 1 read from pictures", credits.lectures[0].detail)
check("slides are counted as slides",
      credits.lectures[1].detail == "Slides \u{00B7} 1 slide", credits.lectures[1].detail)
check("a cited lecture that is no longer kept is still named",
      credits.citedElsewhere == ["Cardio"], "\(credits.citedElsewhere)")
check("the exam's style bank is credited",
      credits.style?.id == "medqa" && credits.examName == "USMLE Step 2 CK")
check("each public source is listed once, in the catalogue's order",
      credits.evidence.map(\.source.id) == ["medlineplus", "europepmc", "openfda"],
      "\(credits.evidence.map(\.source.id))")
check("an evidence page cited twice is listed once",
      credits.evidence.first?.refs.count == 1, "\(credits.evidence.first?.refs.count ?? -1)")
check("evidence from a source with no known licence is kept apart, not dropped",
      credits.otherEvidence == [odd])
check("a set with all this is not empty", !credits.isEmpty)

let bare = SetCredits.make(StudySet(name: "Typed", kind: .anki), exam: nil)
check("a typed-in set with no exam has nothing recorded", bare.isEmpty)
check("an exam with no openly licensed bank credits none",
      SetCredits.make(StudySet(name: "x", kind: .mcq), exam: (name: "PLAB 1", bank: "none")).style == nil)
check("MedMCQA's exams credit MedMCQA",
      ContentSources.styleBank("medmcqa")?.id == "medmcqa" && ContentSources.styleBank("medqa-step1")?.id == "medqa")

// MARK: the app's own list

check("every source names a licence with a link, a credit line and a home page",
      ContentSources.all.allSatisfy { source in
          !source.licences.isEmpty && source.licences.allSatisfy { $0.url.hasPrefix("https://") }
            && !source.attribution.isEmpty && source.home.hasPrefix("https://")
      })
check("ids are unique", Set(ContentSources.all.map(\.id)).count == ContentSources.all.count)
check("CC BY content says what was changed",
      ContentSources.all.filter { $0.licences.contains(ContentSources.ccBy4) }.allSatisfy { ($0.changes ?? "").count > 20 })
check("MedlinePlus is credited the way it asks",
      ContentSources.medlinePlus.attribution.hasPrefix("Courtesy of MedlinePlus from the National Library of Medicine"))

// the bundled exemplars carry their own licence lines: each bank they name
// is on the list, with the same licence
if let data = ExamExemplarData.json.data(using: .utf8),
   let index = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
   let lines = index["licences"] as? [String] {
    check("the bundled exemplars name two banks", lines.count == 2, "\(lines)")
    let medqaLine = lines.first { $0.hasPrefix("MedQA") } ?? ""
    let medmcqaLine = lines.first { $0.hasPrefix("MedMCQA") } ?? ""
    check("MedQA's line matches its credit",
          medqaLine.contains("MIT") && medqaLine.contains("CC-BY-4.0")
            && ContentSources.medqa.licences == [ContentSources.mit, ContentSources.ccBy4], medqaLine)
    check("MedMCQA's line matches its credit",
          medmcqaLine.contains("Apache-2.0") && ContentSources.medmcqa.licences == [ContentSources.apache2], medmcqaLine)
} else {
    check("the bundled exemplars can be read", false)
}

// the Earth's imagery is credited in Settings with the line its maps'
// SOURCES.md gives, word for word
var earthRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
while !FileManager.default.fileExists(atPath: earthRoot.appendingPathComponent("ios/RedPen").path),
      earthRoot.path != "/" {
    earthRoot.deleteLastPathComponent()
}
let earthSources: String = (try? String(contentsOf: earthRoot.appendingPathComponent("ios/RedPen/Resources/Earth/SOURCES.md"),
                                         encoding: .utf8)) ?? ""
let earthFlat: String = earthSources.split(whereSeparator: \.isWhitespace).joined(separator: " ")
check("the Earth imagery's credit is its SOURCES.md's, word for word",
      earthFlat.contains("\"" + ContentSources.nasaEarthCredit + "\"")
        && ContentSources.nasaEarth.attribution.hasPrefix(ContentSources.nasaEarthCredit),
      ContentSources.nasaEarthCredit)
check("the Earth imagery is in Settings' list", ContentSources.all.contains(ContentSources.nasaEarth))

// the anatomy atlas likewise, and its manifest names the same releases
let anatomySources: String = (try? String(contentsOf: earthRoot.appendingPathComponent("ios/RedPen/Resources/Anatomy/SOURCES.md"),
                                           encoding: .utf8)) ?? ""
let anatomyFlat: String = anatomySources.split(whereSeparator: \.isWhitespace).joined(separator: " ")
check("the anatomy atlas's credit is its SOURCES.md's, word for word",
      anatomyFlat.contains("\"" + ContentSources.hraCredit + "\"")
        && ContentSources.hraAnatomy.attribution.hasPrefix(ContentSources.hraCredit),
      ContentSources.hraCredit)
let anatomyManifest: String = (try? String(contentsOf: earthRoot.appendingPathComponent("ios/RedPen/Resources/Anatomy/anatomy.json"),
                                            encoding: .utf8)) ?? ""
check("the credit names both releases the atlas's manifest pins",
      ["https://doi.org/10.48539/HBM833.WZWN.425", "https://doi.org/10.48539/HBM626.BRWN.943"].allSatisfy {
          anatomyManifest.contains($0) && ContentSources.hraCredit.contains($0)
      })
check("the Sciences' sources are in Settings' list",
      [ContentSources.hraAnatomy, ContentSources.uberon, ContentSources.cellOntology,
       ContentSources.reactome, ContentSources.ncbiTaxonomy].allSatisfy(ContentSources.all.contains))

print(failures.isEmpty ? "\nALL CREDITS TESTS PASS"
                       : "\n\(failures.count) CREDITS TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
