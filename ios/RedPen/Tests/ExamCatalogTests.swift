// Putting the student's exam first: the catalogue's integrity (every
// blueprint adds up to 100%, formats are sane, the published USMLE numbers
// are the ones used), the choice and its fallback when the track changes,
// the blueprint as coverage map, readiness and what to study next, how a
// generated set divides by blueprint, the exemplars picked for the writer,
// the prompt each exam gets, its mock papers and pacing, a mock drawn in the
// blueprint's proportions, and the accuracy engine's stricter cut-offs for
// management questions.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

// MARK: - The catalogue

let all: [TargetExam] = ExamCatalog.all
check("at least twenty exams", all.count >= 20, "\(all.count)")
check("ids are unique", Set(all.map(\.id)).count == all.count)
let wantedIds: [String] = ["step1", "step2ck", "step3", "comlex1", "comlex2", "plab1", "mrcp1", "mrcsA", "mccqe1", "amc",
                           "neetpg", "inicet", "fmge", "smle", "dha", "doh", "mohap", "qchp", "omsb", "emle", "ifom"]
check("every exam asked for is there", wantedIds.allSatisfy { ExamCatalog.exam($0) != nil },
      wantedIds.filter { ExamCatalog.exam($0) == nil }.joined(separator: ","))
for exam in all {
    let total: Double = exam.shares.reduce(0) { $0 + $1.percent }
    check("\(exam.id): the blueprint sums to 100%", near(total, 100), "\(total)")
    check("\(exam.id): raw weights are near 100% (or out of 200 / 300)",
          [100.0, 200.0, 300.0].contains { abs(exam.totalWeight - $0) / $0 <= 0.13 }, "\(exam.totalWeight)")
    check("\(exam.id): no area twice", Set(exam.blueprint.map(\.domain)).count == exam.blueprint.count)
    check("\(exam.id): every weight positive", exam.blueprint.allSatisfy { $0.weight > 0 })
    check("\(exam.id): four or five options", exam.options == 4 || exam.options == 5)
    check("\(exam.id): a paper to sit", !exam.sections.isEmpty && exam.sections.allSatisfy { $0.questions > 0 && $0.minutes > 0 })
    check("\(exam.id): a sane pace", (45...120).contains(exam.secondsPerQuestion), "\(exam.secondsPerQuestion) s")
    check("\(exam.id): a sane pass mark", exam.passMark >= 0.4 && exam.passMark <= 0.8)
    check("\(exam.id): strictness 0-1", exam.accuracyStrictness >= 0 && exam.accuracyStrictness <= 1)
    check("\(exam.id): a stem range", exam.stemWords.lowerBound > 0 && exam.stemWords.upperBound > exam.stemWords.lowerBound)
    check("\(exam.id): cites its blueprint", exam.blueprintSource.count > 20)
    check("\(exam.id): not both blockwise and separate", !(exam.sitsBlockwise && exam.sitsSeparately))
}
for domain in ExamDomain.allCases {
    check("\(domain.rawValue) has syllabus subtopics", !ExamBlueprint.subtopics(domain).isEmpty)
}
check("the picker's regions hold every exam", ExamCatalog.byRegion.reduce(0) { $0 + $1.exams.count } == all.count)

// the published USMLE Step 1 ranges, midpoints
let step1: TargetExam = ExamCatalog.step1
check("Step 1: cardiovascular 8% (6-10%)", near(step1.percent(.cardio), 8))
check("Step 1: multisystem 10% (8-12%)", near(step1.percent(.multisystem), 10))
check("Step 1: biostatistics 5% (4-6%)", near(step1.percent(.biostatistics), 5))
check("Step 1: respiratory + renal 13% (11-15%)", near(step1.percent(.resp) + step1.percent(.renal), 13))
check("Step 1 is 7 blocks of 40 in an hour", step1.sections.count == 7 && step1.secondsPerQuestion == 90)
let ck: TargetExam = ExamCatalog.step2ck
check("Step 2 CK: normalised from the published midpoints", near(ck.percent(.ethics), 12.5 / 112.5 * 100))
check("MRCP Part 1 is out of 200", near(ExamCatalog.mrcp1.totalWeight, 200) && near(ExamCatalog.mrcp1.percent(.cardio), 7.5))
check("NEET-PG: four options, negative marking", ExamCatalog.neetpg.options == 4 && ExamCatalog.neetpg.negativeMarking != nil)
check("FMGE passes at 50%", near(ExamCatalog.fmge.passMark, 0.5))
check("Step 2 CK and 3 are stricter than Step 1", ck.accuracyStrictness > step1.accuracyStrictness
      && ExamCatalog.step3.accuracyStrictness >= ck.accuracyStrictness)
check("the exams with unpublished formats say so", !ExamCatalog.emle.formatConfirmed && !ExamCatalog.dha.formatConfirmed
      && ExamCatalog.emle.blueprintIsApproximate)
check("families: UK exams keep their track", ExamCatalog.plab1.family == .plab && ExamCatalog.mrcp1.family == .mrcp
      && ExamCatalog.mrcsA.family == .mrcs && step1.family == .usmle && ExamCatalog.smle.family == .general)

// MARK: - The choice

let defaults: UserDefaults = UserDefaults(suiteName: "exam-tests-\(UUID().uuidString)")!
check("nothing chosen, nothing asked", ExamChoice.picked(defaults) == nil && !ExamChoice.hasAsked(defaults))
ExamChoice.choose(primary: ExamCatalog.smle, secondary: ExamCatalog.dha, defaults: defaults)
check("choosing moves the track to the exam's family", ExamChoice.currentTrack(defaults) == .general)
check("the choice is effective under its track", ExamChoice.effective(for: .general, defaults: defaults)?.id == "smle")
check("the second exam comes with it", ExamChoice.secondary(for: .general, defaults: defaults)?.id == "dha")
check("the accuracy engine is told", near(defaults.double(forKey: ExamChoice.strictnessKey), 0.2)
      && defaults.string(forKey: ExamChoice.strictnessFamilyKey) == "general")
check("answered once chosen", ExamChoice.hasAsked(defaults))
check("another track lets go of it", ExamChoice.effective(for: .usmle, defaults: defaults) == nil
      && ExamChoice.secondary(for: .usmle, defaults: defaults) == nil)
check("the UK tracks fall back to their own exam", ExamChoice.effective(for: .plab, defaults: defaults)?.id == "plab1"
      && ExamChoice.effective(for: .mrcp, defaults: defaults)?.id == "mrcp1")
ExamChoice.choose(primary: step1, secondary: step1, defaults: defaults)
check("the same exam twice is one exam", ExamChoice.pickedSecondary(defaults) == nil && ExamChoice.currentTrack(defaults) == .usmle)
ExamChoice.choose(primary: nil, secondary: nil, defaults: defaults)
check("clearing forgets the exam and the strictness", ExamChoice.picked(defaults) == nil
      && defaults.object(forKey: ExamChoice.strictnessKey) == nil && ExamChoice.hasAsked(defaults))

// MARK: - The plan, coverage, readiness and priority

let plan: [BlueprintArea] = ExamBlueprint.plan(primary: ExamCatalog.neetpg)
check("the plan follows the blueprint, heaviest first", plan.first?.domain == .surgery && plan.count == ExamCatalog.neetpg.blueprint.count)
check("area names are unique", Set(plan.map(\.title)).count == plan.count)
check("alone, weight is share", plan.allSatisfy { near($0.weight, $0.percent) })
let both: [BlueprintArea] = ExamBlueprint.plan(primary: ExamCatalog.neetpg, secondary: ExamCatalog.plab1)
check("a second exam adds its own areas", both.count > plan.count && both.contains { $0.domain == .emergency && $0.percent == 0 })
check("combined weights still add to 100", near(both.reduce(0) { $0 + $1.weight }, 100, 0.05))
let surgeryAlone: Double = plan.first { $0.domain == .surgery }!.weight
let surgeryBoth: Double = both.first { $0.domain == .surgery }!.weight
check("the second exam's share is 30%", near(surgeryBoth, surgeryAlone * 0.7 + ExamCatalog.plab1.percent(.surgery) * 0.3))
for exam in all {
    let p: [BlueprintArea] = ExamBlueprint.plan(primary: exam, secondary: ExamCatalog.plab1)
    check("\(exam.id) + PLAB: unique area names", Set(p.map(\.title)).count == p.count)
}

// quotas: largest remainder, sums to the count
let q20: [(area: BlueprintArea, questions: Int)] = ExamBlueprint.quotas(count: 20, plan: plan)
check("quotas add up to the set", q20.reduce(0) { $0 + $1.questions } == 20)
check("the heaviest area gets the most", q20.first?.area.domain == .surgery && q20.first?.questions == 3,
      q20.map { "\($0.area.domain.rawValue)=\($0.questions)" }.joined(separator: " "))
check("one question goes to the heaviest", ExamBlueprint.quotas(count: 1, plan: plan).map(\.area.domain) == [.surgery])
check("no questions, no quotas", ExamBlueprint.quotas(count: 0, plan: plan).isEmpty)
let q200: [(area: BlueprintArea, questions: Int)] = ExamBlueprint.quotas(count: 200, plan: plan)
check("200 questions follow NEET-PG's 200-question distribution", q200.first { $0.area.domain == .pathology }?.questions == 14
      && q200.first { $0.area.domain == .community }?.questions == 16)

// coverage mapping and standings, from a hand-made assessment
func sub(_ area: String, _ name: String, _ status: CoverageStatus, answered: Int = 0, correct: Int = 0) -> SubtopicCoverage {
    SubtopicCoverage(area: area, subtopic: SyllabusSubtopic(name: name, keywords: [name.lowercased()]), evidence: status == .notCovered ? 0 : 5,
                     practice: status == .covered ? 3 : 0, answered: answered, correct: correct, samples: [], status: status)
}
let small: [BlueprintArea] = ExamBlueprint.plan(primary: ExamCatalog.ifom)
let heavy: BlueprintArea = small[0]   // surgery or paediatrics, 17.5%
let light: BlueprintArea = small.last!
let assessed: [AreaCoverage] = [
    AreaCoverage(area: heavy.syllabus, subtopics: [sub(heavy.title, "A", .notCovered), sub(heavy.title, "B", .notCovered)]),
    AreaCoverage(area: light.syllabus, subtopics: [sub(light.title, "C", .covered, answered: 20, correct: 18),
                                                   sub(light.title, "D", .thin)]),
]
let standings: [BlueprintStanding] = ExamBlueprint.standings(plan: small, assessed: assessed)
let heavyStanding: BlueprintStanding = standings.first { $0.area.id == heavy.id }!
let lightStanding: BlueprintStanding = standings.first { $0.area.id == light.id }!
check("coverage: covered 1, thin a half", near(lightStanding.coverage, 0.75) && near(heavyStanding.coverage, 0))
check("readiness leans on the answers", lightStanding.readiness > 0.75 && near(heavyStanding.readiness, 0.35),
      "\(lightStanding.readiness) \(heavyStanding.readiness)")
check("an unassessed area starts at the prior", standings.filter { $0.area.id != heavy.id && $0.area.id != light.id }
      .allSatisfy { near($0.readiness, 0.35) && $0.answered == 0 })
let next: [BlueprintStanding] = ExamBlueprint.studyNext(standings, limit: 3)
check("study next: a heavy uncovered area first", next.first?.area.weight == small[0].weight && next.count == 3)
check("study next: a well-known light area is not in it", !next.contains { $0.area.id == light.id })
let predicted: Double = ExamBlueprint.predictedScore(standings)
check("predicted score is a weighted readiness", predicted > 0.35 && predicted < 0.5, "\(predicted)")
check("blueprint coverage is weighted by share", near(ExamBlueprint.weightedCoverage(standings), 0.75 * light.percent / 100, 0.001))

// what a piece of text is about
check("a question on asthma is respiratory", ExamBlueprint.domain(of: "A child with wheeze uses a salbutamol inhaler for asthma") == .resp)
check("atrial fibrillation is cardiovascular", ExamBlueprint.domain(of: "Atrial fibrillation with a fast ventricular rate: rate control") == .cardio)
check("within a blueprint only", ExamBlueprint.domain(of: "asthma and wheeze", within: [.cardio, .gi]) == nil)
check("nothing matches, nothing returned", ExamBlueprint.domain(of: "the quick brown fox") == nil)

// MARK: - Exemplars

let bundled: ExamExemplarIndex = ExamExemplars.bundled
let bundledCount: Int = bundled.sources.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
check("the bundled exemplars decode", bundledCount >= 60 && bundled.licences.count == 2, "\(bundledCount)")
check("three style sources", Set(bundled.sources.keys) == ["medqa-step1", "medqa-step23", "medmcqa"])
check("filed under known topics", bundled.sources.values.allSatisfy { $0.keys.allSatisfy { ExamDomain(rawValue: $0) != nil } })
check("every exam has exemplars", all.allSatisfy { !ExamExemplars.pick(for: $0, domain: nil).isEmpty })
check("NEET-PG's are four-option one-liners", ExamExemplars.pick(for: ExamCatalog.neetpg, domain: .pharmacology, count: 3)
      .allSatisfy { $0.o.count == 4 && $0.s.count <= 240 })

let e1 = ExamExemplar(id: "c1", s: "Cardio one", o: ["a", "b", "c", "d"], a: 0)
let e2 = ExamExemplar(id: "c2", s: "Cardio two", o: ["a", "b", "c", "d"], a: 1)
let e3 = ExamExemplar(id: "c3", s: "Cardio three", o: ["a", "b", "c", "d"], a: 2)
let r1 = ExamExemplar(id: "r1", s: "Resp one", o: ["a", "b", "c", "d"], a: 3)
let tiny = ExamExemplarIndex(version: "t", licences: [], sources: ["medqa-step23": ["cardio": [e1, e2, e3], "resp": [r1]]])
check("the topic's own first", ExamExemplars.pick(for: ck, domain: .cardio, count: 2, index: tiny).map(\.id) == ["c1", "c2"])
check("turned over each round (as the server does)", ExamExemplars.pick(for: ck, domain: .cardio, count: 2, round: 1, index: tiny).map(\.id) == ["c3", "c1"])
check("a topic with none borrows", ExamExemplars.pick(for: ck, domain: .gi, count: 2, index: tiny).map(\.id) == ["c1", "c2"])
check("never more than three", ExamExemplars.pick(for: ck, domain: .cardio, count: 9, index: tiny).count == 3)
check("another exam's source gives none", ExamExemplars.pick(for: ExamCatalog.neetpg, domain: .cardio, index: tiny).isEmpty)
let block: String = ExamExemplars.block(for: ck, domain: .resp, count: 1, index: tiny)
check("the block: stem, options, key, warning", block.contains("Example 1: Resp one") && block.contains("  D. d")
      && block.contains("Answer: D") && block.contains("Never copy"))
check("the placeholder for a cloud job", ExamExemplars.placeholder(for: ck, domain: .cardio, count: 5) == "{{EXEMPLARS:step2ck:cardio:3}}")
let lifted: String = ExamExemplars.pick(for: ck, domain: .cardio, count: 1)[0].s
check("a stem that lifts an exemplar is caught", ExamExemplars.copies(lifted))
check("a fresh stem is not", !ExamExemplars.copies("A 67-year-old retired teacher describes six weeks of progressive exertional breathlessness and ankle swelling after a viral illness last spring."))

// MARK: - Prompts

let neetPrompt: String = MCQGenerator.buildPrompt(sourceText: "Notes on pharmacology of antiepileptics.", count: 10, subject: "",
                                                  highYield: true, requestJSONShape: true, exam: .general,
                                                  target: ExamCatalog.neetpg, secondary: nil, exemplars: 2)
check("NEET-PG: four options", neetPrompt.contains("exactly 4 options") && neetPrompt.contains("\"options\" must have exactly 4 strings")
      && !neetPrompt.contains("exactly 5 options"))
check("NEET-PG: its own opening, not NBME's", neetPrompt.hasPrefix("You are writing NEET-PG") && !neetPrompt.hasPrefix("You are writing single-best-answer"))
check("NEET-PG: the JSON shape has four slots", neetPrompt.contains(#""options":["...","...","...","..."],"#))
check("NEET-PG: three distractors", neetPrompt.contains("each of the 3 distractors"))
check("NEET-PG: recall-heavy", neetPrompt.contains("About 60% of the questions"))
check("NEET-PG: negative marking noted", neetPrompt.contains("-1 of +4"))
check("NEET-PG: weighted by blueprint with no topic", neetPrompt.contains("BLUEPRINT WEIGHTING: NEET-PG") && neetPrompt.contains("General surgery"))
check("NEET-PG: exemplars shown", neetPrompt.contains("STYLE EXAMPLES") && neetPrompt.contains("Example 2:"))

let ckPrompt: String = MCQGenerator.buildPrompt(sourceText: "{{SOURCE}}", count: 4, subject: "Heart failure", highYield: false,
                                                requestJSONShape: true, exam: .usmle, target: ck, secondary: nil,
                                                exemplars: 2, exemplarPlaceholder: true, topicText: "")
check("Step 2 CK: the family's style names the exam", ckPrompt.contains("USMLE Step 1 / Step 2 CK") && ckPrompt.contains("preparing for USMLE Step 2 CK"))
check("Step 2 CK: exemplars left for the server, on the topic", ckPrompt.contains("{{EXEMPLARS:step2ck:cardio:2}}"))
check("Step 2 CK: a topic set is not blueprint-weighted", !ckPrompt.contains("BLUEPRINT WEIGHTING"))
check("Step 2 CK: management emphasis", ckPrompt.contains("Most questions are management decisions"))
check("Step 2 CK: five options", ckPrompt.contains("exactly 5 options"))

let mismatch: String = MCQGenerator.buildPrompt(sourceText: "x", count: 3, subject: "", highYield: false, exam: .plab,
                                                target: ck, secondary: nil)
check("an exam from another track is ignored", !mismatch.contains("EXAM FORMAT") && mismatch.contains("exactly 5 options"))
let none: String = MCQGenerator.buildPrompt(sourceText: "x", count: 3, subject: "", highYield: false, exam: .general,
                                            target: nil, secondary: nil)
check("no exam: the prompt as before", !none.contains("EXAM FORMAT") && none.contains("At least one in five"))
let plabPrompt: String = MCQGenerator.buildPrompt(sourceText: "x", count: 5, subject: "", highYield: false, exam: .plab,
                                                  target: ExamCatalog.plab1, secondary: ExamCatalog.mrcp1, exemplars: 1)
check("PLAB + MRCP: combined weighting", plabPrompt.contains("BLUEPRINT WEIGHTING: PLAB 1") && plabPrompt.contains("Example 1:")
      && !plabPrompt.contains("Example 2:"))
check("four or five options are valid, three are not",
      MCQGenerator.isValidQuestion(stem: "Q?", options: ["alpha", "bravo", "charlie", "delta"], correctIndex: 3)
      && MCQGenerator.isValidQuestion(stem: "Q?", options: ["alpha", "bravo", "charlie", "delta", "echo"], correctIndex: 4)
      && !MCQGenerator.isValidQuestion(stem: "Q?", options: ["alpha", "bravo", "charlie"], correctIndex: 0)
      && !MCQGenerator.isValidQuestion(stem: "Q?", options: ["alpha", "bravo", "charlie", "delta"], correctIndex: 4))
for exam in all {
    let p: String = MCQGenerator.buildPrompt(sourceText: "notes", count: 6, subject: "", highYield: false, requestJSONShape: true,
                                             exam: exam.family, target: exam, secondary: nil, exemplars: 2)
    check("\(exam.id): prompt asks for its option count and names it", p.contains("exactly \(exam.options) options")
          && p.contains("EXAM FORMAT - \(exam.name)") && p.contains("STYLE EXAMPLES"))
}

// MARK: - Papers and pacing

let three: [MockPaperSpec] = MockFormat.papers(for: step1, blocks: 3)
check("Step 1: three blocks of 40 in an hour", three.count == 1 && three[0].sections.count == 3 && three[0].questionCount == 120 && three[0].minutes == 180)
check("never more blocks than the exam", MockFormat.papers(for: step1, blocks: 99)[0].sections.count == 7)
check("MRCP: two papers sat apart", MockFormat.papers(for: ExamCatalog.mrcp1).map(\.questionCount) == [100, 100])
let neetPaper: [MockPaperSpec] = MockFormat.papers(for: ExamCatalog.neetpg)
check("NEET-PG: one paper, 200 in 210 minutes", neetPaper.count == 1 && neetPaper[0].questionCount == 200 && neetPaper[0].minutes == 210)
check("Step 3's blocks are named for the day", MockFormat.papers(for: ExamCatalog.step3, blocks: 2)[0].title.contains("fip block"))
check("exam-day kit: a Step 2 CK block", ExamWeekPlanner.paper(for: ck).questions == 40 && ExamWeekPlanner.paper(for: ck).minutes == 60)
check("exam-day kit: all of NEET-PG", ExamWeekPlanner.paper(for: ExamCatalog.neetpg).questions == 200)
check("exam-day kit: an unconfirmed format is not called published", !ExamWeekPlanner.paper(for: ExamCatalog.emle).published)
check("pass mark: the exam's, else the track's", near(PassMark.typical(for: ExamCatalog.fmge, track: .general), 0.5)
      && near(PassMark.typical(for: nil, track: .mrcs), PassMark.typical(for: .mrcs)))

// a mock in the blueprint's proportions
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
var rng = Seeded(state: 42)
var mockPool: [(candidate: MockCandidate, domain: ExamDomain?)] = []
for _ in 0..<100 { mockPool.append((candidate: MockCandidate(id: UUID(), subject: "Surgery"), domain: .surgery)) }
for _ in 0..<100 { mockPool.append((candidate: MockCandidate(id: UUID(), subject: "Paeds"), domain: .peds)) }
for _ in 0..<3 { mockPool.append((candidate: MockCandidate(id: UUID(), subject: "Psych"), domain: .psychiatry)) }
for _ in 0..<50 { mockPool.append((candidate: MockCandidate(id: UUID(), subject: "Misc"), domain: nil)) }
let ifomPlan: [BlueprintArea] = ExamBlueprint.plan(primary: ExamCatalog.ifom)
let drawn: [MockCandidate] = ExamMock.select(mockPool, wanted: 40, plan: ifomPlan, using: &rng)
let surgeryDrawn: Int = drawn.filter { $0.subject == "Surgery" }.count
let paedsDrawn: Int = drawn.filter { $0.subject == "Paeds" }.count
check("the mock is the size asked", drawn.count == 40 && Set(drawn.map(\.id)).count == 40)
check("areas short of questions give their places away", drawn.filter { $0.subject == "Psych" }.count == 3)
check("surgery and paediatrics share the rest evenly", abs(surgeryDrawn - paedsDrawn) <= 1 && surgeryDrawn + paedsDrawn == 37,
      "\(surgeryDrawn) \(paedsDrawn)")
var rng2 = Seeded(state: 7)
let small5: [MockCandidate] = ExamMock.select(Array(mockPool.prefix(5)), wanted: 40, plan: ifomPlan, using: &rng2)
check("a small library gives what it has", small5.count == 5)

// MARK: - Accuracy: stricter for management questions

let base = AccuracyWeights.Thresholds(verified: 0.85, flagged: 0.4)
let half: AccuracyWeights.Thresholds = AccuracyModel.stricter(base, by: 0.5)
check("half strict: 0.92 / 0.45, as the server", near(half.verified, 0.92, 0.00001) && near(half.flagged, 0.45, 0.00001))
let full: AccuracyWeights.Thresholds = AccuracyModel.stricter(base, by: 1)
check("fully strict: 0.99 with a gap", near(full.verified, 0.99, 0.00001) && full.flagged < full.verified)
check("no strictness, no change", AccuracyModel.stricter(base, by: 0) == base)
check("management lead-ins", AccuracyModel.isManagement("What is the most appropriate next step in management?")
      && !AccuracyModel.isManagement("Which enzyme is deficient?"))
let mgmtItem = AccuracyItem(id: "m", kind: .mcq, stem: "What is the next best step in management?", options: ["a", "b", "c", "d"], key: 0)
let mechItem = AccuracyItem(id: "n", kind: .mcq, stem: "Which enzyme is deficient?", options: ["a", "b", "c", "d"], key: 0)
let accDefaults: UserDefaults = UserDefaults(suiteName: "exam-acc-\(UUID().uuidString)")!
ExamChoice.choose(primary: ck, secondary: nil, defaults: accDefaults)
check("Step 2 CK: a management question is judged stricter", near(AccuracyModel.examStrictness(for: mgmtItem, defaults: accDefaults), 0.5))
check("Step 2 CK: a mechanism question is not", AccuracyModel.examStrictness(for: mechItem, defaults: accDefaults) == 0)
accDefaults.set("plab", forKey: ExamTrack.storageKey)
check("once the track moves on, the strictness goes", AccuracyModel.examStrictness(for: mgmtItem, defaults: accDefaults) == 0)
let f: [String: Double] = ["no_models": 0, "rule_severe": 0]
var plainWeights: AccuracyWeights = AccuracyModel.bundled
plainWeights.thresholds = base
var strictWeights: AccuracyWeights = plainWeights
strictWeights.thresholds = AccuracyModel.stricter(base, by: 0.5)
check("P = 0.9: Verified for Step 1, Check this for a Step 2 CK management question",
      AccuracyModel.grade(0.9, f, weights: plainWeights) == .verified && AccuracyModel.grade(0.9, f, weights: strictWeights) == .check)

print(failures.isEmpty ? "\nALL EXAM CATALOGUE TESTS PASS"
                       : "\n\(failures.count) EXAM CATALOGUE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
