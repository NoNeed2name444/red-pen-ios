// "How to reach it": the differential in three tiers (most likely, expanded,
// can't miss) that a question's explanation now carries, and the reasoning
// checks added to MedVAL's.
//
// Two things matter most. A library saved before the field existed must open
// exactly as before - a decoding change that refuses an old set loses a
// student's work. And the tiers must be read from what a model actually
// writes, in either the JSON or the one-line form, without inventing any.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let decoder = JSONDecoder()
let encoder = JSONEncoder()

// MARK: - old saved sets decode without the field

let oldQuestion: String = #"{"id":"5EA50000-0000-4000-8000-000000000001","stem":"Which hernia strangulates most?","options":["Femoral","Direct inguinal","Indirect inguinal","Umbilical","Incisional"],"correctIndex":0,"explanation":"The narrow femoral canal.","source":"Hernia, p. 4"}"#
let q: MCQQuestion? = try? decoder.decode(MCQQuestion.self, from: Data(oldQuestion.utf8))
check("a question saved before the field decodes", q != nil)
check("with no differential", q?.differential == nil)
check("and everything else as it was", q?.source == "Hernia, p. 4" && q?.correctIndex == 0)

// Tolerant decoding: every set saved while the old Cases existed carries a
// "qaCards" key, which is passed over.
let oldCard: String = #"{"id":"5EA50000-0000-4000-8000-000000000002","topic":"Hernia","type":"case","stem":"A 70-year-old woman with a tender groin lump.","answer":["**Femoral hernia**"]}"#
let oldSet: String = "{\"name\":\"Old\",\"kind\":\"mcq\",\"questions\":[" + oldQuestion + "],\"qaCards\":[" + oldCard + "]}"
let set: StudySet? = try? decoder.decode(StudySet.self, from: Data(oldSet.utf8))
check("a whole old set still opens", set?.questions.count == 1)

// MARK: - a library with a set of the removed kind
//
// Tolerant decoding: "qa", the old Cases, is a kind this version does not
// have. A library file holding one such set and an MCQ set loads without
// throwing: the MCQ set is kept, and the "qa" set is skipped but kept as it
// was written (LibraryFile.entries), so Store saves it on with the library.

let oldCasesSet: String = #"{"id":"5EA50000-0000-4000-8000-0000000000a1","name":"Respiratory","kind":"qa","qaCards":[{"id":"5EA50000-0000-4000-8000-0000000000a2","topic":"Asthma","type":"recall","stem":"Features of life-threatening asthma?","answer":["PEF < 33% of best"]}]}"#
let mcqSet: String = "{\"name\":\"Hernia\",\"kind\":\"mcq\",\"questions\":[" + oldQuestion + "]}"
let libraryData = Data(("{\"library\":[" + oldCasesSet + "," + mcqSet + "],\"folders\":[]}").utf8)
var libraryFile: LibraryFile?
var libraryError: String = ""
do {
    libraryFile = try decoder.decode(LibraryFile.self, from: libraryData)
} catch {
    libraryError = "\(error)"
}
check("a library holding a qa set and an MCQ set decodes without throwing", libraryFile != nil, libraryError)
check("the MCQ set is kept", libraryFile?.library.count == 1 && libraryFile?.library.first?.kind == .mcq
      && libraryFile?.library.first?.questions.count == 1)
check("the qa set is skipped, its place noted", libraryFile?.skipped == 1 && libraryFile?.skippedAt == [0])
let keptAside: [String] = LibraryFile.entries(of: libraryData, at: libraryFile?.skippedAt ?? [])
let keptObject: [String: Any]? = keptAside.first.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
check("and kept as it was written", keptAside.count == 1 && keptObject?["kind"] as? String == "qa"
      && keptAside.first?.contains("life-threatening asthma") == true)
check("sync knows the qa kind as removed, not newer", StudySetKind.isRetired(Data(oldCasesSet.utf8))
      && !StudySetKind.isRetired(Data(mcqSet.utf8)))

// a differential saved with some tiers missing still reads
let partial: String = #"{"mostLikely":[{"name":"Femoral hernia","supporting":["older woman"]}]}"#
let partialTiers: DifferentialTiers? = try? decoder.decode(DifferentialTiers.self, from: Data(partial.utf8))
check("a differential with tiers missing decodes", partialTiers?.mostLikely.first?.name == "Femoral hernia"
      && partialTiers?.cantMiss.isEmpty == true && partialTiers?.mostLikely.first?.test == "")

// and one saved now round-trips
var withTiers: MCQQuestion = q ?? MCQQuestion(stem: "x", options: ["a"], correctIndex: 0, explanation: "")
withTiers.differential = ReasoningExamples.herniaDifferential
let saved: Data? = try? encoder.encode(withTiers)
let back: MCQQuestion? = saved.flatMap { try? decoder.decode(MCQQuestion.self, from: $0) }
check("a question with a differential keeps it through a save", back?.differential == ReasoningExamples.herniaDifferential)

// MARK: - the tiers out of a model's JSON reply

let reply: String = """
Here is the differential.
```json
{"differential":{
   "mostLikely":[{"name":"Strangulated femoral hernia","for":["older woman","below and lateral to the pubic tubercle","irreducible and tender"],"against":[],"test":"CT: bowel in the femoral canal"}],
   "expanded":[{"name":"Inguinal hernia","for":["groin lump"],"against":["below and lateral to the tubercle"],"test":"ultrasound"},
               {"name":"Inguinal lymphadenopathy","for":"firm lump","against":"bowel obstruction","test":"ultrasound"}],
   "cant_miss":[{"diagnosis":"Femoral artery aneurysm","supporting":["groin lump"],"against":["not pulsatile"],"discriminatingTest":"duplex ultrasound"}]
 },
 "diagnosis":"Strangulated femoral hernia"}
```
"""
let tiers: DifferentialTiers? = DifferentialTiers.parse(reply: reply)
check("a written differential is read", tiers != nil)
check("most likely is read", tiers?.mostLikely.map(\.name) == ["Strangulated femoral hernia"])
check("with its findings for and its test", tiers?.mostLikely.first?.supporting.count == 3
      && tiers?.mostLikely.first?.test == "CT: bowel in the femoral canal")
check("expanded keeps both, in order", tiers?.expanded.map(\.name) == ["Inguinal hernia", "Inguinal lymphadenopathy"])
check("a finding written as a string rather than a list is still read",
      tiers?.expanded.last?.supporting == ["firm lump"] && tiers?.expanded.last?.against == ["bowel obstruction"])
check("can't miss under another key spelling and other field names is read",
      tiers?.cantMiss.first?.name == "Femoral artery aneurysm" && tiers?.cantMiss.first?.test == "duplex ultrasound")

// a reply that is only the differential, nested or bare, or as a tier-labelled list
let nested: DifferentialTiers? = DifferentialTiers.parse(reply: #"{"differential":{"Most Likely":["Hydrocele"],"Can't Miss":["Testicular tumour"]}}"#)
check("tier names written as titles are read", nested?.mostLikely.first?.name == "Hydrocele" && nested?.cantMiss.first?.name == "Testicular tumour")
let listed: DifferentialTiers? = DifferentialTiers.parse(json: [["tier": "can't miss", "name": "Testicular torsion", "test": "exploration"],
                                                                ["tier": "most likely", "name": "Epididymitis"]])
check("a list of entries each naming its tier is read", listed?.cantMiss.first?.name == "Testicular torsion" && listed?.mostLikely.first?.name == "Epididymitis")
check("an MCQ reply with no differential is not read as one, even saying \"most likely\"",
      DifferentialTiers.parse(reply: #"{"stem":"What is the most likely diagnosis?","options":["a"]}"#) == nil)
check("nothing is nothing", DifferentialTiers.parse(reply: "No differential here.") == nil)
let blank: DifferentialTiers? = DifferentialTiers.parse(json: ["mostLikely": [["name": "Hydrocele"]], "cantMiss": ["none"]])
check("\"none\" in a tier is not a diagnosis", blank?.cantMiss.isEmpty == true && blank?.mostLikely.count == 1)

// MARK: - an MCQ reply in the shape MCQPrompt asks for

let mcqReply: String = #"""
{"questions":[
 {"stem":"A 68-year-old woman has a tender, irreducible lump below and lateral to the pubic tubercle and has vomited twice. What is the most likely diagnosis?",
  "options":["Femoral hernia","Direct inguinal hernia","Indirect inguinal hernia","Saphena varix","Inguinal lymphadenopathy"],
  "differential":{"mostLikely":[{"name":"Strangulated femoral hernia","for":["below and lateral to the pubic tubercle","irreducible, vomiting"],"against":[],"test":"urgent groin ultrasound or CT"}],
                  "expanded":[{"name":"Inguinal hernia","for":["groin lump"],"against":["below and lateral to the pubic tubercle"],"test":"ultrasound"}],
                  "cantMiss":[{"name":"Femoral artery aneurysm","for":["groin lump"],"against":["not pulsatile"],"test":"duplex ultrasound"}]},
  "correctIndex":0,"explanation":"Below and lateral to the pubic tubercle is the femoral canal."},
 {"stem":"Which structure forms the medial border of the femoral canal?","options":["Lacunar ligament","Femoral vein","Pectineal ligament","Inguinal ligament","Adductor longus"],
  "correctIndex":0,"explanation":"The lacunar ligament."},
 {"stem":"A 30-year-old man has a groin lump.","options":["a","b","c","d","e"],"differential":"not a differential","correctIndex":1,"explanation":"x"}
]}
"""#
let perItem: [DifferentialTiers?] = DifferentialTiers.perItem(in: Data(mcqReply.utf8), list: "questions")
check("each question's differential is read by position", perItem.count == 3)
check("a vignette's differential is read in full", perItem.first??.mostLikely.first?.name == "Strangulated femoral hernia"
      && perItem.first??.cantMiss.first?.test == "duplex ultrasound")
check("a recall question has none", perItem.count > 1 && perItem[1] == nil)
check("a malformed one is none, and costs nothing else", perItem.count > 2 && perItem[2] == nil)

// MARK: - the one-line form

let line: String = "Most likely: Femoral hernia (for: older woman, below and lateral to the pubic tubercle; against: none of note; test: groin ultrasound) / Expanded: Inguinal hernia (for: groin lump; against: below the ligament; test: ultrasound); Saphena varix (for: cough impulse; against: does not empty on lying; test: duplex) / Can't miss: Incarcerated/strangulated hernia (for: tender, irreducible; test: urgent surgical review)"
let fromLine: DifferentialTiers? = DifferentialTiers.parse(line: line)
check("the line form reads every tier", fromLine?.mostLikely.count == 1 && fromLine?.expanded.count == 2 && fromLine?.cantMiss.count == 1)
check("findings are split at commas inside the brackets",
      fromLine?.mostLikely.first?.supporting == ["older woman", "below and lateral to the pubic tubercle"],
      "\(String(describing: fromLine?.mostLikely.first?.supporting))")
check("a name with a slash in it stays whole", fromLine?.cantMiss.first?.name == "Incarcerated/strangulated hernia",
      "\(String(describing: fromLine?.cantMiss.first?.name))")
check("the test is kept", fromLine?.expanded.last?.test == "duplex")

// MARK: - what the checker is shown

let text: String = ReasoningExamples.herniaDifferential.checkText
check("the checker sees each tier on its own line", text.hasPrefix("- Most likely: Indirect inguinal hernia (for: Young man")
      && text.contains("\n- Expanded: Direct inguinal hernia") && text.contains("\n- Can\u{2019}t miss: Incarcerated or strangulated hernia"))

// MARK: - the example is complete and sound

let example: DifferentialTiers = ReasoningExamples.herniaDifferential
check("the hernia example has all three tiers", !example.mostLikely.isEmpty && !example.expanded.isEmpty && !example.cantMiss.isEmpty)
check("its most likely is an indirect inguinal hernia", example.mostLikely.first?.name == "Indirect inguinal hernia")
check("its expanded tier holds the hernia's lookalikes",
      ["Direct inguinal hernia", "Femoral hernia", "Hydrocele"].allSatisfy { d in example.expanded.contains { $0.name == d } })
let cantMissNames: [String] = example.cantMiss.map(\.name)
check("its can't-miss tier names strangulation, torsion and a femoral aneurysm",
      cantMissNames.contains { $0.contains("strangulated") } && cantMissNames.contains("Testicular torsion")
      && cantMissNames.contains("Femoral artery aneurysm"))
check("femoral hernia is argued against by where the lump is",
      example.expanded.first { $0.name == "Femoral hernia" }?.against.contains { $0.contains("below and lateral") } == true)
check("every entry has findings and a test", (example.mostLikely + example.expanded + example.cantMiss).allSatisfy { $0.hasDetail && !$0.test.isEmpty })
check("nothing cites a source the lookup did not return", example.evidence.isEmpty)

print(failures.isEmpty ? "\nALL DIFFERENTIAL TESTS PASS"
                       : "\n\(failures.count) DIFFERENTIAL TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
