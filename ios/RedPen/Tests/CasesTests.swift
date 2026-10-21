// Cases: the case file read tolerantly and kept through a StudySet, the
// structure checks, the H and L flags, the run (steps once, the clock, the
// ladder copied after every step), the score and its cap, the debrief's
// turning point and cards, and a writer's JSON read back into a case. The
// history is a written clerking note: no step ever questions the patient.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let pe: CaseFile = CaseSamples.breathless
let gca: CaseFile = CaseSamples.headache

// MARK: the samples pass their own checks

for sample in CaseSamples.all {
    let found = CaseChecks.problems(sample)
    check("sample \u{201C}\(sample.title)\u{201D} is playable", found.isEmpty, found.map(\.said).joined(separator: "; "))
    let hits = AccuracyRules.hits(CaseChecks.item(sample))
    check("sample \u{201C}\(sample.title)\u{201D} has no rule hit at all", hits.isEmpty, hits.map(\.detail).joined(separator: "; "))
    check("sample \u{201C}\(sample.title)\u{201D} has three teaching points", sample.teaching.count == 3)
    check("sample \u{201C}\(sample.title)\u{201D} has a full clerking note", sample.clerking.parts.count == 5)
}

// MARK: no questioning the patient

check("two groups only: examine and test", CaseStep.Group.allCases == [.examine, .test])
check("a history step reads as no group", CaseStep.Group.read("history") == nil && CaseStep.Group.read("ask") == nil
      && CaseStep.Group.read("Questions") == nil)
check("loose names still read", CaseStep.Group.read("Exam") == .examine && CaseStep.Group.read("investigation") == .test)

// MARK: the structure checks

func problems(_ edit: (inout CaseFile) -> Void) -> [CaseChecks.Problem] {
    var file = pe
    edit(&file)
    return CaseChecks.problems(file)
}

check("too few steps", problems { $0.steps = Array($0.steps.prefix(7)) }.contains(.stepCount(7)))
check("too many steps", problems { f in
    f.steps += (1...8).map { CaseStep(id: "x\($0)", group: .examine, label: "Extra \($0)", finding: "Nothing", minutes: 1, value: .low) }
}.contains(.stepCount(21)))
check("a missing group", problems { f in f.steps = f.steps.filter { $0.group != .examine } }.contains(.missingGroup(.examine)))
check("no clerking note", problems { $0.clerking = CaseFile.Clerking() }.contains(.noClerking))
check("fewer than two key steps", problems { f in
    for i in f.steps.indices where f.steps[i].id != "s2" { if f.steps[i].value == .key { f.steps[i].value = .useful } }
}.contains(.fewKeySteps(1)))
check("the diagnosis must be a differential", problems { $0.differentials.removeFirst() }.contains(.diagnosisNotInDifferentials))
check("a differential with no support", problems { $0.differentials[1].supportedBy = [] }.contains(.unsupported("Pneumonia")))
check("a differential naming a missing step", problems { $0.differentials[1].againstBy.append("s99") }.contains(.unknownStep("s99")))
check("the turning step must be key", problems { $0.turningStep = "s1" }.contains(.turningStepNotKey))
check("the budget covers key steps plus 30%", CaseChecks.budgetNeeded(pe) == 56
      && problems { $0.budgetMinutes = 55 }.contains(.budgetShort(have: 55, need: 56))
      && !problems { $0.budgetMinutes = 56 }.contains(where: { if case .budgetShort = $0 { return true }; return false }))
check("next step needs four or five options", problems { $0.nextStep.options = Array($0.nextStep.options.prefix(3)) }.contains(.nextStepOptions))
check("next step key in range", problems { $0.nextStep.key = 9 }.contains(.nextStepOptions))
check("a key that stands out by length is refused", problems {
    $0.nextStep.options[0] = "Start apixaban, a direct oral anticoagulant, today, with a plan for three months and review"
}.contains(.nextStepUnbalanced))
check("an impossible result is refused", problems { f in
    f.steps[7].results.append(CaseStep.LabResult(name: "Potassium", value: 45, unit: "mmol/L"))
}.contains(where: { if case .accuracy = $0 { return true }; return false }))
check("a dose outside any usual range is refused", problems { f in
    f.clerking.drugs = "Takes paracetamol 40 g each day."
}.contains(where: { if case .accuracy = $0 { return true }; return false }))
check("blank complaint", problems { $0.complaint = " " }.contains(.blank))

// tidying: no medicine changed, only the mechanics
var loose = pe
loose.steps[0].id = ""
loose.steps[1].id = "s3"
loose.turningStep = "nowhere"
loose.budgetMinutes = 10
let tidy = CaseChecks.tidied(loose)
check("tidy numbers a blank id and a repeated one", Set(tidy.steps.map(\.id)).count == tidy.steps.count && tidy.steps[0].id == "s1")
check("tidy points a lost turning step at the first key step", tidy.turningStep == tidy.keySteps.first?.id)
check("tidy raises a short budget to cover the key steps", tidy.budgetMinutes == CaseChecks.budgetNeeded(tidy))

let screened = CaseChecks.screen([pe, { var f = pe; f.steps = []; return f }()])
check("screen keeps the playable, marked passed", screened.kept.count == 1 && screened.kept[0].verification == .passed)
check("screen drops the rest with reasons", screened.dropped.count == 1 && !screened.dropped[0].why.isEmpty)
check("a held case is kept off the list", CaseChecks.isHeld(pe, flagged: [pe.id.uuidString])
      && !CaseChecks.isHeld(pe, flagged: []) && CaseChecks.isHeld({ var f = pe; f.verification = .held; return f }(), flagged: []))

// MARK: the chart's flags

check("tachycardia flagged high", CaseChart.flag(CaseFile.Obs(sign: .hr, value: 112)) == .high)
check("normal heart rate not flagged", CaseChart.flag(CaseFile.Obs(sign: .hr, value: 78)) == nil)
check("saturation 93 flagged low", CaseChart.flag(CaseFile.Obs(sign: .spo2, value: 93)) == .low)
check("systolic 86 flagged low", CaseChart.flag(CaseFile.Obs(sign: .bp, value: 86, second: 50)) == .low)
check("142/84 flagged high, as the question chart flags it", CaseChart.flag(CaseFile.Obs(sign: .bp, value: 142, second: 84)) == .high)
check("fever flagged high", CaseChart.flag(CaseFile.Obs(sign: .temp, value: 38.4)) == .high)
check("PaO2 8.9 kPa low by the accuracy engine's range", CaseChart.flag(CaseStep.LabResult(name: "PaO2", value: 8.9, unit: "kPa")) == .low)
check("pH 7.47 high", CaseChart.flag(CaseStep.LabResult(name: "pH", value: 7.47)) == .high)
check("potassium in mmol/L by the table", CaseChart.flag(CaseStep.LabResult(name: "Potassium", value: 6.1, unit: "mmol/L")) == .high)
check("the table wins over a stated range", CaseChart.flag(CaseStep.LabResult(name: "Sodium", value: 140, unit: "mmol/L", low: 141, high: 150)) == nil)
check("a stated range for a test the table lacks", CaseChart.flag(CaseStep.LabResult(name: "CRP", value: 64, unit: "mg/L", low: 0, high: 5)) == .high)
check("no range, no flag", CaseChart.flag(CaseStep.LabResult(name: "Troponin", value: 12, unit: "ng/L")) == nil)

// MARK: names

check("names match across case and punctuation", CaseNames.same("Pulmonary-embolism", "pulmonary embolism"))
check("an accepted name is the diagnosis", pe.isDiagnosis("PE") && pe.isDiagnosis("pulmonary thromboembolism"))
check("a runner-up is not", !pe.isDiagnosis("Pneumonia"))
check("typed names resolve to the case's own", pe.resolve("chest infection") == "Pneumonia" && pe.resolve("pe") == "Pulmonary embolism")
check("an unknown name does not resolve", pe.resolve("Gout") == nil)
let candidates = pe.candidates
check("candidates: every differential and distractor once", candidates.count == 7
      && Set(candidates) == Set(pe.differentials.map(\.name) + pe.distractors))
check("candidates in the same order every time", candidates == pe.candidates)
check("the diagnosis is not always first", CaseSamples.all.contains { $0.candidates.first != $0.diagnosis.name })
check("the runner-up is the first non-diagnosis", pe.runnerUp?.name == "Pneumonia" && gca.runnerUp?.name == "Polymyalgia rheumatica")

// MARK: the run

var run = CaseRun(caseID: pe.id)
check("a fresh run is new", run.state == .new && run.minutesUsed == 0)
check("a step is taken", run.take("s2", in: pe) && run.minutesUsed == 3)
check("not twice", !run.take("s2", in: pe) && run.taken.count == 1)
check("not a step the case lacks", !run.take("s99", in: pe))
run.add("pneumonia", in: pe)
run.add("PE", in: pe)
check("ladder names are the case's own", run.ladder == ["Pneumonia", "Pulmonary embolism"])
run.add("Pulmonary embolism", in: pe)
check("a rung once", run.ladder.count == 2)
run.add("Pericarditis", in: pe)
run.add("Pneumothorax", in: pe)
check("three rungs at most; a newcomer takes the bottom", run.ladder == ["Pneumonia", "Pulmonary embolism", "Pneumothorax"])
run.move("Pulmonary embolism", up: true)
check("a rung moves up", run.ladder.first == "Pulmonary embolism")
run.move("Pulmonary embolism", up: true)
check("the top cannot move higher", run.ladder.first == "Pulmonary embolism")
run.remove("Pneumothorax")
check("a rung is removed", run.ladder == ["Pulmonary embolism", "Pneumonia"])
check("a run with steps is seen", run.state == .seen)
check("the ladder is copied once per step", run.ladders.count == run.taken.count && run.ladders[0] == [])

// MARK: the score

/// A run of a case: these steps in order, the ladder set before each, then
/// the decision.
func play(_ steps: [(String, [String])], diagnosis: String, next: Int, file: CaseFile = pe) -> CaseRun {
    var r = CaseRun(caseID: file.id, started: Date(timeIntervalSince1970: 0))
    for (id, ladder) in steps {
        r.setLadder(ladder)
        r.take(id, in: file)
    }
    r.decide(CaseRun.Decision(diagnosis: diagnosis, nextStep: next), in: file, at: Date(timeIntervalSince1970: 60))
    return r
}

let ideal = play([("s3", []), ("s2", ["Pneumothorax"]), ("s8", ["Pneumonia"]), ("s13", ["Pulmonary embolism"])],
                 diagnosis: "Pulmonary embolism", next: 0)
let best = ideal.score!
check("all key and red flags, right answers, in time: 100", best.total == 100, "\(best)")
check("a finished run is discharged with its score", ideal.state == .discharged(score: 100))
check("a finished run takes no more steps", { var r = ideal; return !r.take("s1", in: pe) }())

let wrong = play([("s2", []), ("s13", [])], diagnosis: "Pneumonia", next: 4)
check("wrong diagnosis and next step lose 30 and 20", wrong.score?.diagnosis == 0 && wrong.score?.nextStep == 0)
check("red flags in proportion (1 of 2 = 8 of 15)", wrong.score?.redFlags == 8, "\(String(describing: wrong.score))")

let missedCalf = play([("s3", []), ("s8", []), ("s13", [])], diagnosis: "PE", next: 0)
check("key findings in proportion (2 of 3 = 17 of 25)", missedCalf.score?.keyFindings == 17)
check("a missed must-not-miss caps the total at 60", missedCalf.score?.capped == true && missedCalf.score?.total == 60,
      "\(String(describing: missedCalf.score))")

let lowYield = play([("s5", []), ("s6", []), ("s12", []), ("s2", [])], diagnosis: "PE", next: 0)
check("three low-yield steps cost 4 of the time", lowYield.score?.time == 6, "\(String(describing: lowYield.score))")
check("one low-yield step is free", play([("s2", []), ("s5", []), ("s8", []), ("s13", [])], diagnosis: "PE", next: 0).score?.time == 10)

var slow = CaseRun(caseID: pe.id)
for step in pe.steps { slow.take(step.id, in: pe) }
slow.decide(CaseRun.Decision(diagnosis: "PE", nextStep: 0), in: pe)
check("past the budget: allowed, counted", slow.minutesUsed > pe.budgetMinutes && slow.isOver(pe))
check("over budget with three low-yield steps: 10 - 4 - 5", slow.score?.time == 1, "\(String(describing: slow.score))")
check("shares round to the nearest, all when nothing to find", CaseScore.share(0, of: 3, points: 25) == 0
      && CaseScore.share(5, of: 0, points: 15) == 15)

// MARK: the debrief

let lateLead = CaseDebrief(file: pe, run: ideal)
check("turning point: the ladder led only after a later step",
      lateLead.turning == .late(turning: "Examine the legs", led: "CT pulmonary angiogram"), "\(lateLead.turning)")
let quick = play([("s2", ["Pulmonary embolism"]), ("s13", ["Pulmonary embolism"])], diagnosis: "PE", next: 0)
check("turning point: in time", CaseDebrief(file: pe, run: quick).turning == .onTime(turning: "Examine the legs", led: "Examine the legs"))
check("turning point: never led", CaseDebrief(file: pe, run: wrong).turning == .never(turning: "Examine the legs"))
check("turning point: the step was never taken", CaseDebrief(file: pe, run: missedCalf).turning == .missedStep(turning: "Examine the legs"))
var lateLadder = CaseRun(caseID: pe.id)
lateLadder.take("s2", in: pe)
lateLadder.setLadder(["Pulmonary embolism"])
lateLadder.decide(CaseRun.Decision(diagnosis: "PE", nextStep: 0), in: pe)
check("turning point: only at the decision", CaseDebrief(file: pe, run: lateLadder).turning == .atDecision(turning: "Examine the legs"))
check("every turning point is said", !CaseDebrief(file: pe, run: missedCalf).turningSaid.isEmpty)

let missedDebrief = CaseDebrief(file: pe, run: missedCalf)
check("missed red flags, the must-not-miss first", missedDebrief.missedRedFlags.map(\.id) == ["s2"])
check("key findings counted", missedDebrief.keyFound == 2 && missedDebrief.keyFindings.count == 3)
check("separating findings: the diagnosis's against the runner-up's", lateLead.separating.map(\.step.id) == ["s9"])
check("separating findings in the clinic case", CaseDebrief(file: gca, run: CaseRun(caseID: gca.id)).separating.map(\.step.id) == ["s1", "s2", "s11"])
let lowDebrief = CaseDebrief(file: pe, run: lowYield)
check("low-yield steps listed with why", lowDebrief.lowYield.map(\.id) == ["s5", "s6", "s12"] && lowDebrief.lowYield.allSatisfy { !$0.note.isEmpty })
let cards = missedDebrief.cards
check("one card per missed key finding or red flag", cards.count == 1 && cards[0].bullets.first == pe.step("s2")?.finding)
check("cards are basic and tagged", cards.allSatisfy { $0.type == .qa && ($0.tags ?? []).contains("Cases") }
      && cards[0].why.hasPrefix("Must not miss"))
check("nothing missed, no cards", CaseDebrief(file: pe, run: slow).cards.isEmpty)
check("the Ideas note names the diagnosis", lateLead.ideaText.contains("Pulmonary embolism") && lateLead.ideaTitle == "Case: Pulmonary embolism")

// MARK: saved and read back

let set = StudySet(name: "Patients", subject: "Medicine", kind: .cases, caseFiles: CaseSamples.all)
let data = try JSONEncoder().encode(set)
let back = try JSONDecoder().decode(StudySet.self, from: data)
check("a Cases set round-trips", back.kind == .cases && back.caseFiles == CaseSamples.all && back.itemCount == 2)
check("the kind is saved as \"cases\"", String(decoding: data, as: UTF8.self).contains(#""kind":"cases""#))
check("its noun", back.itemNoun == "patient" && StudySetKind.cases.label == "Cases")
check("\"qa\" is still retired, \"cases\" is not", StudySetKind.isRetired(Data(#"{"kind":"qa"}"#.utf8))
      && !StudySetKind.isRetired(Data(#"{"kind":"cases"}"#.utf8)))
let thin = try JSONDecoder().decode(CaseFile.self, from: Data(#"{"complaint":"I feel faint","clerking":{"presenting":"Faint"},"steps":[{"label":"Look","finding":"Pale","group":"exam"}],"setting":"A&E"}"#.utf8))
check("a case missing most fields still reads", thin.complaint == "I feel faint" && thin.steps.first?.group == .examine
      && thin.setting == .emergency && thin.budgetMinutes == 20 && thin.clerking.presenting == "Faint" && thin.clerking.history.isEmpty)
let copy = set.withNewItemIDs()
check("a copy's cases get new ids", Set(copy.caseFiles.map(\.id)).isDisjoint(with: Set(set.caseFiles.map(\.id))))
check("the set's item ids include its cases", set.itemIDs.isSuperset(of: Set(CaseSamples.all.map(\.id))))
let items = AccuracyItem.items(in: set)
check("each case is one accuracy item of kind case", items.count == 2 && items.allSatisfy { $0.kind == .case })
check("what it asserts: the clerking and the key, not the wrong options", !items[0].text.contains("alteplase")
      && items[0].text.contains("apixaban") && items[0].text.contains("Flew home from Sydney"))

// MARK: a writer's JSON

let reply = """
Here is the patient:
```json
{"cases":[{"title":"Thirsty and vomiting","specialty":"Endocrinology","setting":"ED",
 "patient":{"name":"Sam Okafor","age":"19","sex":"M","about":"student"},
 "complaint":"\\"I can't stop being sick and I'm so thirsty\\"",
 "clerking":{"presenting":"Vomiting and abdominal pain, 1 day","history":"A week of thirst and polyuria.","pmh":"Nil","drugs":"None","social":"Student"},
 "vitals":{"hr":118,"sbp":104,"dbp":66,"rr":"28","spo2":99,"temp":36.9},"budget":40,
 "steps":[{"id":"s0","group":"history","label":"Ask about thirst","finding":"Thirsty for a week","minutes":2,"value":"key"},
          {"id":"s1","group":"exam","label":"Smell the breath","finding":"Ketotic breath","minutes":1,"value":"KEY","mustNotMiss":"true"},
          {"id":"s2","group":"investigation","label":"Venous gas","finding":"Acidosis","minutes":10,"value":"key","results":[{"name":"pH","value":7.12},{"name":"Bicarbonate","value":"9","unit":"mmol/L"},{"name":"Ketones","value":5.2,"unit":"mmol/L","low":0,"high":0.6}]}],
 "diagnosis":{"name":"Diabetic ketoacidosis","accepted":["DKA"]},
 "differentials":[{"name":"Diabetic ketoacidosis","for":["s1","s2"],"against":[]},{"name":"Gastroenteritis","for":["s1"],"against":["s2"]}],
 "distractors":["Appendicitis"],"turningStep":"s2",
 "nextStep":{"options":["Fixed-rate insulin infusion","Subcutaneous insulin","Oral rehydration","Antiemetic only","Observe"],"answer":"A","why":"..."},
 "teaching":["One","Two","Three"],"pages":"4-6"}]}
```
"""
let parsed = CaseWriting.parse(reply, lecture: "Endocrine emergencies")
check("a fenced reply is read", parsed.count == 1)
if let w = parsed.first {
    check("patient read, numbers as strings too", w.patient.age == 19 && w.patient.initials == "SO" && w.setting == .emergency)
    check("the complaint loses the writer's quotation marks", w.complaint == "I can't stop being sick and I'm so thirsty")
    check("the clerking note is read, short keys too", w.clerking.presenting.hasPrefix("Vomiting") && w.clerking.past == "Nil"
          && w.clerking.drugs == "None")
    check("vitals in the chart's order", w.arrival.map(\.sign) == [.hr, .bp, .rr, .spo2, .temp] && w.arrival[1].shown == "104/66")
    check("a step that questions the patient is dropped", w.steps.map(\.id) == ["s1", "s2"] && w.steps.map(\.group) == [.examine, .test])
    check("loose values read", w.steps[0].value == .key && w.steps[0].mustNotMiss)
    check("results read, ranges kept only when given", w.steps[1].results.count == 3 && w.steps[1].results[1].value == 9
          && w.steps[1].results[2].high == 0.6 && w.steps[1].results[0].low == nil)
    check("the answer letter read as an index", w.nextStep.key == 0)
    check("the source names the lecture and pages", w.source.cited == "Endocrine emergencies, pp. 4-6")
}
check("a reply with no JSON gives nothing", CaseWriting.parse("Sorry, I cannot help with that.").isEmpty)
check("one case on its own is read too", CaseWriting.parse(#"{"complaint":"Ow","steps":[{"label":"Look","finding":"Red","group":"examine"}]}"#).count == 1)
check("a thinking block is skipped", CaseWriting.parse("<think>{\"x\":1}</think>" + #"{"complaint":"Ow","steps":[{"label":"L","finding":"F"}]}"#).count == 1)
check("a case whose only steps question the patient is no case",
      CaseWriting.parse(#"{"complaint":"Ow","steps":[{"label":"Ask","finding":"Yes","group":"history"}]}"#).isEmpty)
check("a cloud job's replies are collected up to the count", CaseWriting.collect([reply, reply, reply], count: 2).count == 2)

// MARK: the instructions

let rules = CaseWriting.instructions(source: "LECTURE TEXT", subject: "Cardiology",
                                     brief: CaseWriting.Brief(diagnosis: "Aortic stenosis", unlike: "72 M, clinic", setting: .ward,
                                                              avoid: ["Heart failure"]), json: true)
check("the instructions carry the lecture last", rules.hasSuffix("LECTURE TEXT"))
check("and the brief", rules.contains("must be Aortic stenosis") && rules.contains("72 M, clinic")
      && rules.contains("ward") && rules.contains("Heart failure") && rules.contains("Cardiology"))
check("they ask for a clerking note and no questions to the patient", rules.contains("clerking note")
      && rules.contains("never a question to the patient") && !rules.contains("\"ask\""))
check("and the JSON shape when asked", rules.contains(#""turningStep""#) && rules.contains(#""clerking""#)
      && !CaseWriting.instructions(source: "x", subject: "", brief: .init(), json: false).contains(#""turningStep""#))
check("settings turn over case by case", (0..<4).map(CaseWriting.setting(for:)) == [.emergency, .ward, .clinic, .community])

print(failures.isEmpty ? "\nALL CASES TESTS PASS" : "\n\(failures.count) CASES TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
