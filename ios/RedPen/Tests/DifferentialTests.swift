// "How to reach it": the differential in three tiers (most likely, expanded,
// can't miss) that a case, a clue-by-clue case or a question's explanation
// now carries, and the reasoning checks added to MedVAL's.
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

let oldCard: String = #"{"id":"5EA50000-0000-4000-8000-000000000002","topic":"Hernia","type":"case","stem":"A 70-year-old woman with a tender groin lump.","answer":["**Femoral hernia**"]}"#
let card: QACard? = try? decoder.decode(QACard.self, from: Data(oldCard.utf8))
check("a Cases card saved before the field decodes", card != nil && card?.differential == nil)

let oldCase: String = #"{"id":"5EA50000-0000-4000-8000-000000000003","clues":["A 24-year-old man.","A groin lump."],"diagnosis":"Indirect inguinal hernia","differentials":["Direct inguinal hernia","Femoral hernia","Hydrocele"],"teachingPoint":"Lateral means indirect.","decisiveClue":2}"#
let clue: ClueCase? = try? decoder.decode(ClueCase.self, from: Data(oldCase.utf8))
check("a clue-by-clue case saved before the field decodes", clue != nil && clue?.differential == nil)

let oldSet: String = "{\"name\":\"Old\",\"kind\":\"mcq\",\"questions\":[" + oldQuestion + "],\"qaCards\":[" + oldCard + "]}"
let set: StudySet? = try? decoder.decode(StudySet.self, from: Data(oldSet.utf8))
check("a whole old set still opens", set?.questions.count == 1 && set?.qaCards.count == 1)

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
let savedCase: Data? = try? encoder.encode(ReasoningExamples.cases[0])
let backCase: ClueCase? = savedCase.flatMap { try? decoder.decode(ClueCase.self, from: $0) }
check("so does a clue-by-clue case", backCase?.differential == ReasoningExamples.herniaDifferential)

// MARK: - the tiers out of a model's JSON reply

let reply: String = """
Here is the case.
```json
{"cases":[{"clues":["A 71-year-old woman.","Two days of colicky abdominal pain and vomiting.","A small, firm, tender lump in the right groin.","It lies below and lateral to the pubic tubercle and will not reduce.","Abdominal X-ray: dilated small-bowel loops."],
 "differential":{
   "mostLikely":[{"name":"Strangulated femoral hernia","for":["older woman","below and lateral to the pubic tubercle","irreducible and tender"],"against":[],"test":"CT: bowel in the femoral canal"}],
   "expanded":[{"name":"Inguinal hernia","for":["groin lump"],"against":["below and lateral to the tubercle"],"test":"ultrasound"},
               {"name":"Inguinal lymphadenopathy","for":"firm lump","against":"bowel obstruction","test":"ultrasound"}],
   "cant_miss":[{"diagnosis":"Femoral artery aneurysm","supporting":["groin lump"],"against":["not pulsatile"],"discriminatingTest":"duplex ultrasound"}]
 },
 "diagnosis":"Strangulated femoral hernia","differentials":["Inguinal hernia","Inguinal lymphadenopathy","Femoral artery aneurysm"],
 "teachingPoint":"A femoral hernia in an older woman presents as obstruction.","decisiveClue":4}]}
```
"""
let parsed: [ClueCase] = ReasoningWriter.parseCases(reply)
let tiers: DifferentialTiers? = parsed.first?.differential
check("a written case keeps its differential", tiers != nil)
check("most likely is read", tiers?.mostLikely.map(\.name) == ["Strangulated femoral hernia"])
check("with its findings for and its test", tiers?.mostLikely.first?.supporting.count == 3
      && tiers?.mostLikely.first?.test == "CT: bowel in the femoral canal")
check("expanded keeps both, in order", tiers?.expanded.map(\.name) == ["Inguinal hernia", "Inguinal lymphadenopathy"])
check("a finding written as a string rather than a list is still read",
      tiers?.expanded.last?.supporting == ["firm lump"] && tiers?.expanded.last?.against == ["bowel obstruction"])
check("can't miss under another key spelling and other field names is read",
      tiers?.cantMiss.first?.name == "Femoral artery aneurysm" && tiers?.cantMiss.first?.test == "duplex ultrasound")
check("the case itself is read as before", parsed.first?.diagnosis == "Strangulated femoral hernia" && parsed.first?.decisiveClue == 4)

let noTiers: [ClueCase] = ReasoningWriter.parseCases(#"{"cases":[{"clues":["a","b","c","d"],"diagnosis":"X","differentials":["A","B","C"],"teachingPoint":"t","decisiveClue":3}]}"#)
check("a case written without a differential has none", noTiers.count == 1 && noTiers.first?.differential == nil)

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

// a question turned into a Cases card keeps its route to the answer
let converted: QACard? = ModeConversion.caseCard(from: withTiers, topic: "Groin")
check("a question turned into a Cases card keeps its differential",
      converted?.differential == ReasoningExamples.herniaDifferential)

// MARK: - the one-line form a Cases line carries

let line: String = "Most likely: Femoral hernia (for: older woman, below and lateral to the pubic tubercle; against: none of note; test: groin ultrasound) / Expanded: Inguinal hernia (for: groin lump; against: below the ligament; test: ultrasound); Saphena varix (for: cough impulse; against: does not empty on lying; test: duplex) / Can't miss: Incarcerated/strangulated hernia (for: tender, irreducible; test: urgent surgical review)"
let fromLine: DifferentialTiers? = DifferentialTiers.parse(line: line)
check("the line form reads every tier", fromLine?.mostLikely.count == 1 && fromLine?.expanded.count == 2 && fromLine?.cantMiss.count == 1)
check("findings are split at commas inside the brackets",
      fromLine?.mostLikely.first?.supporting == ["older woman", "below and lateral to the pubic tubercle"],
      "\(String(describing: fromLine?.mostLikely.first?.supporting))")
check("a name with a slash in it stays whole", fromLine?.cantMiss.first?.name == "Incarcerated/strangulated hernia",
      "\(String(describing: fromLine?.cantMiss.first?.name))")
check("the test is kept", fromLine?.expanded.last?.test == "duplex")

let qa: [QACard] = PlainTextImport.parseQA("Groin | case | A 70-year-old woman with a tender, irreducible lump below and lateral to the pubic tubercle. Diagnosis? | **Femoral hernia**; urgent repair | " + line
                                           + "\nGroin | recall | Where does a femoral hernia emerge? | Below and lateral to the **pubic tubercle**")
check("a Cases line keeps its differential", qa.first?.differential?.mostLikely.first?.name == "Femoral hernia")
check("and its answer points as before", qa.first?.answer == ["**Femoral hernia**", "urgent repair"])
check("a recall line has none", qa.count == 2 && qa.last?.differential == nil)

// MARK: - what the checker is shown

let text: String = ReasoningExamples.herniaDifferential.checkText
check("the checker sees each tier on its own line", text.hasPrefix("- Most likely: Indirect inguinal hernia (for: Young man")
      && text.contains("\n- Expanded: Direct inguinal hernia") && text.contains("\n- Can\u{2019}t miss: Incarcerated or strangulated hernia"))

// MARK: - the example is complete and sound

let example: DifferentialTiers = ReasoningExamples.herniaDifferential
check("the hernia example has all three tiers", !example.mostLikely.isEmpty && !example.expanded.isEmpty && !example.cantMiss.isEmpty)
check("its most likely is the case's diagnosis", example.mostLikely.first?.name == ReasoningExamples.cases[0].diagnosis)
check("its expanded tier holds the case's differentials",
      ReasoningExamples.cases[0].differentials.allSatisfy { d in example.expanded.contains { $0.name == d } })
let cantMissNames: [String] = example.cantMiss.map(\.name)
check("its can't-miss tier names strangulation, torsion and a femoral aneurysm",
      cantMissNames.contains { $0.contains("strangulated") } && cantMissNames.contains("Testicular torsion")
      && cantMissNames.contains("Femoral artery aneurysm"))
check("femoral hernia is argued against by where the lump is",
      example.expanded.first { $0.name == "Femoral hernia" }?.against.contains { $0.contains("below and lateral") } == true)
check("every entry has findings and a test", (example.mostLikely + example.expanded + example.cantMiss).allSatisfy { $0.hasDetail && !$0.test.isEmpty })
check("nothing cites a source the lookup did not return", example.evidence.isEmpty)

// MARK: - the reasoning checks in MedVAL's prompt and grade

let prompt: String = MedVAL.prompt(instruction: "Write an MCQ.", input: "Lecture.", output: "Question.")
check("the prompt asks for the reasoning checks", prompt.contains("4. `reasoning_issues'")
      && prompt.contains("fit ALL the key findings") && prompt.contains("can't-miss") && prompt.contains("Unsupported claim"))
let risk: Range<String.Index>? = prompt.range(of: "[[ ## risk_level ## ]]\n# TO_BE_FILLED_BY_MODEL")
let issuesField: Range<String.Index>? = prompt.range(of: "[[ ## reasoning_issues ## ]]\n# TO_BE_FILLED_BY_MODEL")
check("and its field comes after MedVAL's own three, so MedVAL's format is unchanged",
      risk != nil && issuesField != nil && risk!.upperBound < issuesField!.lowerBound)

let flagged: AccuracyVerdict = MedVAL.parse("""
[[ ## reasoning ## ]]
The keyed answer is femoral hernia.
[[ ## errors ## ]]
None
[[ ## risk_level ## ]]
1
[[ ## reasoning_issues ## ]]
Contradicting finding: the lump is above and medial to the pubic tubercle, which places it in the inguinal canal.
Unsupported claim: "femoral hernias are commoner in men".
[[ ## completed ## ]]
""", checkedBy: "x")
check("a finding that contradicts the answer raises the grade to at least moderate", flagged.riskLevel == 3, "\(flagged.riskLevel)")
check("both issues are kept", flagged.reasoningIssues?.count == 2)
check("and counted among the findings", flagged.findings.count == 2 && flagged.findings.allSatisfy { $0.category == .hallucination })
let unsupportedOnly: AccuracyVerdict = MedVAL.parse("[[ ## errors ## ]]\nNone\n[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\n- Unsupported claim: the 5-year recurrence rate.", checkedBy: "x")
check("an unsupported claim alone raises no risk to low", unsupportedOnly.riskLevel == 2)
let cantMissOpen: AccuracyVerdict = MedVAL.parse("[[ ## errors ## ]]\nNone\n[[ ## risk_level ## ]]\n2\n[[ ## reasoning_issues ## ]]\nCan't miss: testicular torsion is not excluded despite sudden pain.", checkedBy: "x")
check("a can't-miss diagnosis left open is at least moderate", cantMissOpen.riskLevel == 3 && cantMissOpen.categories == [.omission])
let clean: AccuracyVerdict = MedVAL.parse("[[ ## errors ## ]]\nNone\n[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\nNone.\n[[ ## completed ## ]]", checkedBy: "x")
check("\"None\" is no issue, and a clean grade stays clean", clean.riskLevel == 1 && clean.reasoningIssues == nil && clean.findings.isEmpty)
for nothing in ["No issues.", "None found.", "- None", "N/A", "No issues found"] {
    let v: AccuracyVerdict = MedVAL.parse("[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\n" + nothing, checkedBy: "x")
    check("\"\(nothing)\" is no issue", v.riskLevel == 1 && v.reasoningIssues == nil)
}
check("but \"No\" starting a real issue is still one",
      MedVAL.parse("[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\nNo test excludes testicular torsion (can't miss).", checkedBy: "x").riskLevel == 3)
let oldReply: AccuracyVerdict = MedVAL.parse("[[ ## errors ## ]]\nError 1: Missing claim - dose.\n[[ ## risk_level ## ]]\n4\n[[ ## completed ## ]]", checkedBy: "x")
check("a reply without the field reads exactly as before", oldReply.riskLevel == 4 && oldReply.reasoningIssues == nil && oldReply.findings.count == 1)
check("a high grade is never lowered by an issue", MedVAL.parse("[[ ## risk_level ## ]]\n4\n[[ ## reasoning_issues ## ]]\nUnsupported claim: x", checkedBy: "").riskLevel == 4)
let oldVerdict: String = #"{"riskLevel":2,"findings":[],"reasoning":"ok","checkedBy":"MedVAL-4B"}"#
check("a verdict saved before the field decodes", (try? decoder.decode(AccuracyVerdict.self, from: Data(oldVerdict.utf8)))?.riskLevel == 2)

print(failures.isEmpty ? "\nALL DIFFERENTIAL TESTS PASS"
                       : "\n\(failures.count) DIFFERENTIAL TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
