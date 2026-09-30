// The exam tools' pure logic: a mock paper assembled from the library at the
// real exam's length and pace, and honest when the library is short; the twin
// queue that brings a missed question back in a new patient; the attending's
// hint that must never name the answer; the calculator; the reference ranges;
// and the stem cut into pieces for the highlighter.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: paper formats

let plab: MockPaperSpec = MockFormat.papers(for: .plab)[0]
check("PLAB 1 is 180 questions in 3 hours", plab.questionCount == 180 && plab.minutes == 180)
let mrcp: [MockPaperSpec] = MockFormat.papers(for: .mrcp)
check("MRCP Part 1 is two papers of 100", mrcp.count == 2 && mrcp.allSatisfy { $0.questionCount == 100 && $0.minutes == 180 })
let usmle: MockPaperSpec = MockFormat.papers(for: .usmle, usmleBlocks: 3)[0]
check("USMLE blocks are 40 in 60 minutes", usmle.sections.count == 3
      && usmle.sections.allSatisfy { $0.questions == 40 && $0.minutes == 60 })
check("no more than seven USMLE blocks", MockFormat.papers(for: .usmle, usmleBlocks: 12)[0].sections.count == 7)
check("MRCS A has its two papers", MockFormat.papers(for: .mrcs).map(\.minutes) == [180, 120])

// MARK: assembly

func pool(_ counts: [String: Int]) -> [MockCandidate] {
    var out: [MockCandidate] = []
    for (subject, n) in counts.sorted(by: { $0.key < $1.key }) {
        for _ in 0..<n { out.append(MockCandidate(id: UUID(), subject: subject)) }
    }
    return out
}

var rng = MockSeededGenerator(seed: 42)
let big: [MockCandidate] = pool(["Cardiology": 150, "Renal": 60, "Neuro": 40])
let full: MockAssembly? = MockAssembler.assemble(plab, from: big, using: &rng)
check("a big library fills the paper", full?.count == 180 && full?.isShort == false && full?.shortfallNote == nil,
      "\(full?.count ?? -1)")
let ids: [UUID] = full?.questionIds.flatMap { $0 } ?? []
check("no question twice", Set(ids).count == ids.count)
let bySubject: [String: Int] = Dictionary(grouping: big.filter { ids.contains($0.id) }, by: \.subject).mapValues(\.count)
check("every subject gets its share before one fills the rest",
      (bySubject["Neuro"] ?? 0) == 40 && (bySubject["Renal"] ?? 0) == 60, "\(bySubject)")

let small: [MockCandidate] = pool(["Cardiology": 30, "Renal": 15])
let short: MockAssembly? = MockAssembler.assemble(plab, from: small, using: &rng)
check("a short library sits a shorter paper", short?.count == 45 && short?.isShort == true)
check("at the real paper's pace", short?.sections.first?.minutes == 45, "\(short?.sections.first?.minutes ?? -1)")
check("and says so honestly", short?.shortfallNote?.contains("45") == true
      && short?.shortfallNote?.contains("180") == true, short?.shortfallNote ?? "nil")

let blocks: MockAssembly? = MockAssembler.assemble(usmle, from: pool(["A": 50, "B": 20]), using: &rng)
check("blocks fill in order, the last one short", blocks?.sections.map(\.questions) == [40, 30],
      "\(blocks?.sections.map(\.questions) ?? [])")
check("a short block keeps the pace", blocks?.sections.last?.minutes == 45)

check("too few questions makes no paper", MockAssembler.assemble(plab, from: pool(["A": 9]), using: &rng) == nil)
let dupes: [MockCandidate] = { let one = MockCandidate(id: UUID(), subject: "A"); return Array(repeating: one, count: 20) }()
check("copies of one question are one question", MockAssembler.assemble(plab, from: dupes, using: &rng) == nil)

var r1 = MockSeededGenerator(seed: 7), r2 = MockSeededGenerator(seed: 7)
let same1 = MockAssembler.assemble(plab, from: big, using: &r1)
let same2 = MockAssembler.assemble(plab, from: big, using: &r2)
check("the same seed makes the same paper", same1 == same2)

// MARK: marking

let marks: [MockMark] = [
    MockMark(questionId: UUID(), subject: "Cardio", picked: 1, correct: true, seconds: 50),
    MockMark(questionId: UUID(), subject: "Cardio", picked: 2, correct: false, seconds: 70),
    MockMark(questionId: UUID(), subject: "Renal", picked: nil, correct: false, seconds: 0),
    MockMark(questionId: UUID(), subject: "Renal", picked: 0, correct: true, seconds: 60)
]
let result = MockResult(marks: marks, passMark: 0.6)
check("score counts right answers", result.correct == 2 && result.total == 4)
check("unanswered are counted", result.unanswered == 1)
check("50% does not pass a 60% mark", !result.passed)
check("subjects are listed", result.bySubject.map(\.subject).sorted() == ["Cardio", "Renal"])
check("renal answered once of twice", result.bySubject.first { $0.subject == "Renal" }?.answered == 1)
check("pacing: halfway through PLAB is Q90", MockPacing.target(elapsed: 5_400, questions: 180, minutes: 180) == 90)

// MARK: twins

var queue = TwinQueue()
let now = Date(timeIntervalSince1970: 1_000_000)
let parent = UUID(), twin = UUID()
queue.add(twin: twin, parent: parent, now: now, confident: true)
check("a confident mistake's twin is due in a day", queue.entries.first?.dueAt == now.addingTimeInterval(86_400))
check("not due at once", queue.due(now: now).isEmpty)
check("due the next day", queue.due(now: now.addingTimeInterval(90_000)).map(\.id) == [twin])
check("the question has a twin on the way", queue.hasTwin(for: parent))
let twin2 = UUID()
queue.add(twin: twin2, parent: parent, now: now, guessed: true)
check("one waiting twin per missed question", queue.waiting.map(\.id) == [twin2])
check("a guess waits three days", queue.entries.first?.dueAt == now.addingTimeInterval(3 * 86_400))
let later = now.addingTimeInterval(4 * 86_400)
queue.answered(twin2, correct: false, now: later)
check("a missed twin comes back a day later", queue.due(now: later.addingTimeInterval(86_400)).map(\.id) == [twin2])
queue.answered(twin2, correct: true, now: later.addingTimeInterval(86_400))
check("a twin got right leaves the queue", queue.waiting.isEmpty && queue.isTwin(twin2))
queue.prune(keeping: [])
check("twins gone from the library are forgotten", queue.entries.isEmpty)
check("the re-test comes a few questions on", TwinRetest.slot(after: 2, count: 20) == 6)
check("or at the end", TwinRetest.slot(after: 18, count: 20) == 20)

let input = TwinPrompt.input(stem: "A 24-year-old woman has palpitations.", options: ["Graves disease", "Toxic adenoma"],
                             correctIndex: 0, explanation: "Diffuse uptake.", picked: 1, reason: "Mixed up lookalikes")
check("the twin prompt carries the answer, the choice and the reason",
      input.contains("Correct answer: Graves disease") && input.contains("chose: Toxic adenoma")
      && input.contains("lookalikes"))
check("the same stem again is too close",
      TwinPrompt.isTooClose("A 24-year-old woman has palpitations and weight loss.", to: "A 24-year-old woman has palpitations and weight loss today."))
check("a new patient is not",
      !TwinPrompt.isTooClose("A 61-year-old man with tremor and a goitre sees his GP.", to: "A 24-year-old woman has palpitations and weight loss."))

// MARK: the attending's hint

let stem = "A 30-year-old woman has heat intolerance, a diffuse goitre and exophthalmos."
let options = ["Graves disease", "Toxic multinodular goitre", "Subacute thyroiditis", "Hashimoto thyroiditis"]
let others = Array(options.dropFirst())
check("naming the answer leaks", AttendingHint.leaks("Think of Graves disease.", answer: options[0], stem: stem, otherOptions: others))
check("its distinctive word leaks", AttendingHint.leaks("Could this be Graves?", answer: options[0], stem: stem, otherOptions: others))
check("a nudge about the eyes does not",
      !AttendingHint.leaks("Which finding here is not explained by a nodule - look at the eyes.", answer: options[0], stem: stem, otherOptions: others))
check("a word shared with other options is not a leak",
      !AttendingHint.leaks("Which kind of thyroiditis would be painful?", answer: "Subacute thyroiditis", stem: stem,
                           otherOptions: ["Graves disease", "Hashimoto thyroiditis"]))
check("a long stem of the answer word leaks",
      AttendingHint.leaks("It is hyperthyroid in origin.", answer: "Hyperthyroidism", stem: "Tired woman.", otherOptions: ["Anaemia"]))
check("a leaking reply is refused",
      AttendingHint.accept("Hint: it's Graves disease.", answer: options[0], stem: stem, otherOptions: others) == nil)
check("a good reply is kept, tidied",
      AttendingHint.accept("Hint: What does eye involvement tell you about the cause?", answer: options[0], stem: stem,
                           otherOptions: others) == "What does eye involvement tell you about the cause?")
let tiers = DifferentialTiers(mostLikely: [DifferentialEntry(name: "Graves disease", supporting: ["Exophthalmos"])],
                              expanded: [DifferentialEntry(name: "Toxic multinodular goitre", against: ["A diffuse, not nodular, goitre"])])
let fb = AttendingHint.fallback(answer: options[0], stem: stem, options: options, differential: tiers)
check("the fallback rules a rival out", fb.contains("Toxic multinodular goitre") && fb.contains("diffuse"), fb)
check("and never names the answer", !AttendingHint.leaks(fb, answer: options[0], stem: stem, otherOptions: others), fb)
let bare = AttendingHint.fallback(answer: options[0], stem: stem, options: options, differential: nil)
check("with no differential, a fixed nudge", bare.contains("most specific finding"))
var cache = HintCache()
let hid = UUID()
cache.store("one", for: hid)
check("a hint is kept", cache.hint(for: hid) == "one")
for _ in 0..<(HintCache.cap + 5) { cache.store("x", for: UUID()) }
check("the oldest go past the cap", cache.hint(for: hid) == nil && cache.hints.count == HintCache.cap)

// MARK: calculator

var calc = ExamCalculator()
calc.digit(1); calc.digit(2); calc.op(.add); calc.digit(3); calc.equals()
check("12 + 3 = 15", calc.display == "15", calc.display)
calc.clear(); calc.digit(7); calc.op(.divide); calc.digit(2); calc.equals()
check("7 / 2 = 3.5", calc.display == "3.5", calc.display)
calc.clear(); calc.digit(2); calc.op(.add); calc.digit(3); calc.op(.multiply); calc.digit(4); calc.equals()
check("chained left to right, as a basic calculator does", calc.display == "20", calc.display)
calc.clear(); calc.digit(5); calc.op(.divide); calc.digit(0); calc.equals()
check("dividing by zero says Error", calc.display == "Error")
calc.digit(8)
check("a digit after Error starts again", calc.display == "8")
calc.clear(); calc.dot(); calc.digit(5); calc.negate()
check("-0.5", calc.display == "-0.5", calc.display)
calc.clear(); calc.digit(1); calc.op(.divide); calc.digit(3); calc.equals()
check("a third to ten figures", calc.display == "0.3333333333", calc.display)

// MARK: reference ranges

check("every group is listed", Set(LabRanges.all.map(\.group)) == Set(LabRanges.groups))
check("no range twice", Set(LabRanges.all.map(\.id)).count == LabRanges.all.count)
let sodium = LabRanges.search("sodium").first
check("sodium in SI and US units", sodium?.si.contains("mmol/L") == true && sodium?.us.contains("mEq/L") == true)
check("USMLE reads conventional units", LabUnits.conventional(for: .usmle) && !LabUnits.conventional(for: .plab))
check("search finds a group", LabRanges.search("blood gases").count == LabRanges.gases.count)

// MARK: highlighter pieces

let longStem = "A 67-year-old man presents with sudden breathlessness. He had a hip replacement 10 days ago, and his left calf is swollen and tender to touch. What is the most likely diagnosis?"
let pieces = StemPieces.split(longStem)
check("the pieces give back the stem", pieces.joined() == longStem)
check("sentences are pieces", pieces.count >= 3, "\(pieces)")
check("a decimal is not a break", StemPieces.split("Potassium 5.9 mmol/L. Next?").count == 2)

print(failures.isEmpty ? "\nALL EXAM TOOLS TESTS PASS"
                       : "\n\(failures.count) EXAM TOOLS TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
