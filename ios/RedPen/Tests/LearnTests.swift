// The learning-science pieces: the exam-day forecast and exam cap, "lock it
// in", the exam-week planner, the symptom classifier, the pretest writer and
// the daily rhythm. All of them are sums over dates, which is exactly where a
// wrong sign or an off-by-one day hides without anything on screen showing it.
import Foundation

var failures: [String] = []
var passed = 0

// Only failures are printed: the workflow keeps the first 90 lines of a
// suite's output, and a suite that printed every pass would be cut off (and
// killed by the closed pipe) before its verdict.
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; return }
    print("FAIL " + label + "  | " + detail)
    failures.append(label)
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!
let day: TimeInterval = 86_400
// noon on a fixed day, well away from midnight and clock changes
let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!

// MARK: the forecast

check("recall is 90% exactly one stability after a review",
      abs(RetentionForecast.recall(elapsedDays: 10, stability: 10) - 0.9) < 1e-9)
check("and falls further the longer it is left",
      RetentionForecast.recall(elapsedDays: 30, stability: 10) < RetentionForecast.recall(elapsedDays: 20, stability: 10))
check("a card not seen since just now is fully recalled",
      abs(RetentionForecast.recall(elapsedDays: 0, stability: 3) - 1) < 1e-9)

let tenDay = ReviewRecord(due: now.addingTimeInterval(10 * day), intervalMin: 10 * 1440,
                          reviews: 3, lapses: 0, ratedAt: now)
let lapsed = ReviewRecord(due: now.addingTimeInterval(10 * day), intervalMin: 10 * 1440,
                          reviews: 6, lapses: 3, ratedAt: now)
check("lapses make a card less stable than its interval",
      RetentionForecast.stabilityDays(lapsed) < RetentionForecast.stabilityDays(tenDay))
check("a card never rated has no recall to forecast",
      RetentionForecast.recall(nil, at: now) == nil)

let a = UUID(), b = UUID(), c = UUID()
let records: [UUID: ReviewRecord] = [a: tenDay, b: lapsed]
let exam = now.addingTimeInterval(30 * day)
let f = RetentionForecast.forecast(cardIDs: [a, b, c], records: records, now: now, exam: exam)
check("the forecast counts studied and unseen cards apart", f.studied == 2 && f.unseen == 1,
      "\(f.studied) \(f.unseen)")
check("recall on exam day is below today's", f.onExamDay < f.today, "\(f.onExamDay) \(f.today)")
check("so reviews are needed to reach 90%", f.reviewsNeeded >= 2, "\(f.reviewsNeeded)")
check("over the days left", f.days == 30, "\(f.days)")
check("and not on course yet", !f.onCourse)
check("a per-day figure rounds up", f.perDay == Int((Double(f.reviewsNeeded) / 30).rounded(.up)))

// a card reviewed yesterday with a long interval needs nothing before an
// exam in three days
let solid = ReviewRecord(due: now.addingTimeInterval(20 * day), intervalMin: 20 * 1440,
                         reviews: 5, lapses: 0, ratedAt: now.addingTimeInterval(-day))
check("a solid card needs no review before a near exam",
      RetentionForecast.reviewsToTarget(solid, now: now, exam: now.addingTimeInterval(3 * day)) == 0)
check("a weak card needs at least one",
      RetentionForecast.reviewsToTarget(lapsed, now: now, exam: exam) >= 1)
let plan = RetentionForecast.reviewsToTarget(
    ReviewRecord(due: now, intervalMin: 10, reviews: 1, lapses: 0, ratedAt: now), now: now, exam: exam)
check("a card just learned needs a handful, not dozens", plan >= 2 && plan < RetentionForecast.maxPlanned, "\(plan)")
let noExam = RetentionForecast.forecast(cardIDs: [a], records: records, now: now, exam: nil)
check("without an exam there is no review plan", noExam.reviewsNeeded == 0)

let byDay = RetentionForecast.dueByDay(cardIDs: [a, b, c], records: records, now: now, days: 14, calendar: calendar)
check("an unrated card is due today", byDay[0] == 1, "\(byDay)")
check("and cards due in ten days land on day ten", byDay[10] == 2, "\(byDay)")

// MARK: the exam cap

check("the cap reads the same key as ExamTrack", ExamCap.dateKey == ExamTrack.dateKey)
let capExam = now.addingTimeInterval(12 * day)
let capped = ExamCap.capped(30 * 1440, now: now, exam: capExam)
check("an interval past the exam is brought back before it", capped <= 11 * 1440, "\(capped / 1440) d")
check("to about two days before", abs(capped - 10 * 1440) < 1, "\(capped / 1440) d")
check("an interval well before the exam is untouched",
      ExamCap.capped(4 * 1440, now: now, exam: capExam) == 4 * 1440)
check("learning steps under a day are untouched",
      ExamCap.capped(600, now: now, exam: now.addingTimeInterval(3600 * 5)) == 600)
check("no exam, no cap", ExamCap.capped(30 * 1440, now: now, exam: nil) == 30 * 1440)
check("a past exam changes nothing",
      ExamCap.capped(30 * 1440, now: now, exam: now.addingTimeInterval(-day)) == 30 * 1440)
let close = ExamCap.capped(4 * 1440, now: now, exam: now.addingTimeInterval(2 * day))
check("with the exam two days off, a card comes back halfway", abs(close - 1440) < 1, "\(close)")
let rated = ReviewPlan.after(rating: .easy, record: ReviewRecord(due: now, intervalMin: 30 * 1440),
                             now: now, exam: capExam)
check("a rating stores the capped interval", rated.due <= capExam.addingTimeInterval(-day),
      "\(rated.due.timeIntervalSince(now) / day) d")
let labels = AnkiScheduler.previewLabels(currentIntervalMin: 30 * 1440, now: now, exam: capExam)
check("and the button promises the same", labels[.easy] == "in 10 d", labels[.easy] ?? "nil")

// MARK: lock it in

let q = UUID()
func event(_ id: UUID, _ right: Bool, _ daysAgo: Double, hour: Double = 0) -> AnswerEvent {
    AnswerEvent(questionId: id, correct: right, date: now.addingTimeInterval(-daysAgo * day + hour * 3600))
}
check("never answered is new", SecuredRule.standing(of: [], calendar: calendar) == .new)
check("three right answers in one day are one day",
      SecuredRule.standing(of: [event(q, true, 0), event(q, true, 0, hour: 1), event(q, true, 0, hour: 2)],
                           calendar: calendar) == .building(1))
check("right on three separate days is secured",
      SecuredRule.standing(of: [event(q, true, 5), event(q, true, 3), event(q, true, 1)],
                           calendar: calendar) == .secured)
check("a slip after that starts again",
      SecuredRule.standing(of: [event(q, true, 5), event(q, true, 3), event(q, true, 1), event(q, false, 0)],
                           calendar: calendar) == .building(0))
check("a slip in between resets the count",
      SecuredRule.standing(of: [event(q, true, 5), event(q, false, 4), event(q, true, 3), event(q, true, 1)],
                           calendar: calendar) == .building(2))
check("events out of order are read in date order",
      SecuredRule.standing(of: [event(q, true, 1), event(q, false, 4), event(q, true, 3), event(q, true, 5)],
                           calendar: calendar) == .building(2))
var helped = event(q, true, 1)
helped.hinted = true
check("right with the hint is neither a day towards locking in nor a slip",
      SecuredRule.standing(of: [event(q, true, 5), event(q, true, 3), helped],
                           calendar: calendar) == .building(2))

let q2 = UUID(), q3 = UUID()
let standings = SecuredRule.standings([event(q, true, 5), event(q, true, 3), event(q, true, 1),
                                       event(q2, true, 2), event(q2, true, 1)], calendar: calendar)
let rings = SecuredRule.rings(subjects: [q: "Cardiology", q2: "Cardiology", q3: "Renal"], standings: standings)
check("rings come per subject", rings.map(\.subject) == ["Cardiology", "Renal"], "\(rings.map(\.subject))")
check("with secured, building and new counted",
      rings[0].secured == 1 && rings[0].building == 1 && rings[1].new == 1)
check("close to secure puts two-of-three first",
      SecuredRule.closeToSecure([q, q2, q3], standings: standings) == [q2])
check("a question already right today does not count again today",
      !SecuredRule.countsToday(q, events: [event(q, true, 0)], now: now, calendar: calendar))

// MARK: exam week

func phase(_ days: Int) -> ExamWeekPlanner.Phase {
    ExamWeekPlanner.phase(exam: now.addingTimeInterval(Double(days) * day), now: now, calendar: calendar)
}
check("no date, no phase", ExamWeekPlanner.phase(exam: nil, now: now) == .noDate)
check("six weeks out is building", phase(42) == .building(days: 42))
check("T-10 is the mock window", phase(10) == .mockWindow(days: 10))
check("T-8 still is", phase(8) == .mockWindow(days: 8))
check("T-7 is exam week", phase(7) == .examWeek(days: 7))
check("and holds back new material", phase(3).holdsNewMaterial)
check("the day itself", phase(0) == .examDay)
check("and after it", phase(-2) == .after)

typealias Sit = ExamWeekPlanner.Situation
check("exam day opens the kit whatever is due",
      ExamWeekPlanner.mission(Sit(phase: .examDay, dueCards: 40)) == .examKit)
check("a morning check comes before due cards",
      ExamWeekPlanner.mission(Sit(phase: .building(days: 30), dueCards: 12, morningCheck: 3)) == .morningCheck(3))
check("due cards come before anything else",
      ExamWeekPlanner.mission(Sit(phase: .building(days: 30), dueCards: 12, confidentErrors: 5)) == .dueCards(12))
check("the mock window suggests a mock",
      ExamWeekPlanner.mission(Sit(phase: .mockWindow(days: 9), confidentErrors: 5)) == .mock)
check("a mock missed in its window is still offered at T-7",
      ExamWeekPlanner.mission(Sit(phase: .examWeek(days: 7), confidentErrors: 2)) == .mock)
check("but not once it is done",
      ExamWeekPlanner.mission(Sit(phase: .examWeek(days: 7), confidentErrors: 2, mockDone: true)) == .confidentErrors(2))
check("exam week goes to confident errors, then mistakes",
      ExamWeekPlanner.mission(Sit(phase: .examWeek(days: 4), missed: 6)) == .mistakes(6))
check("and never to new questions",
      ExamWeekPlanner.mission(Sit(phase: .examWeek(days: 4), untried: 200, weakestSubject: "Renal")) == .nothing)
check("far out, the half-secured come before the weakest subject",
      ExamWeekPlanner.mission(Sit(phase: .building(days: 40), closeToSecure: 8, weakestSubject: "Renal")) == .lockIn(8))
check("then the weakest subject",
      ExamWeekPlanner.mission(Sit(phase: .noDate, weakestSubject: "Renal")) == .weakest("Renal"))

let plab = ExamWeekPlanner.checkpoints(for: ExamWeekPlanner.paper(for: .plab))
check("PLAB pacing: Q60 by 1:00, Q120 by 2:00, Q180 by 3:00",
      plab == [.init(minute: 60, question: 60), .init(minute: 120, question: 120), .init(minute: 180, question: 180)],
      "\(plab)")
let usmle = ExamWeekPlanner.checkpoints(for: ExamWeekPlanner.paper(for: .usmle))
check("a USMLE block is paced in quarters", usmle.map(\.question) == [10, 20, 30, 40], "\(usmle)")
let mrcp = ExamWeekPlanner.checkpoints(for: ExamWeekPlanner.paper(for: .mrcp))
check("an MRCP paper ends at Q100 at 3:00", mrcp.last == .init(minute: 180, question: 100), "\(mrcp)")
check("MRCS is paced but not claimed as the paper's own format",
      !ExamWeekPlanner.paper(for: .mrcs).published)
check("clock reads hours and minutes", ExamWeekPlanner.clock(135) == "2:15")

// MARK: symptom blocks

func tags(_ stem: String) -> [String] { SymptomBlocks.presentations(in: stem).map(\.id) }
check("central chest pain is chest pain",
      tags("A 58-year-old man has 40 minutes of central chest pain radiating to the jaw.") == ["chest-pain"])
check("denied chest pain is not",
      !tags("She is breathless on exertion and denies chest pain.").contains("chest-pain"))
check("but the breathlessness in the same sentence is",
      tags("She is breathless on exertion and denies chest pain.") == ["breathless"])
check("a negation in an earlier sentence does not carry over",
      tags("No fever. He has pleuritic chest pain and is short of breath.") == ["chest-pain", "breathless"])
check("'but' starts a new clause",
      tags("No cough but sudden shortness of breath after a long flight.") == ["breathless"])
check("a groin lump is tagged",
      tags("A 70-year-old woman has a lump in the groin below and lateral to the pubic tubercle.") == ["groin-lump"])
check("words are matched whole, not inside others",
      tags("He has a headache-free interval.") == ["headache"] && tags("Headaches for a month.") == ["headache"])
check("'no' as part of another word is not a negation",
      tags("A known smoker with nocturnal chest pain.") == ["chest-pain"])
check("a stem with no complaint gets no tag", tags("Which enzyme is deficient in Gaucher disease?").isEmpty)
check("a collapsed patient is a collapse", tags("She collapsed while standing in a queue.") == ["collapse"])

var items: [SymptomBlocks.Item] = []
for (i, answer) in ["Acute coronary syndrome", "Pulmonary embolism", "Aortic dissection",
                    "Pericarditis", "Acute coronary syndrome", "Pneumothorax"].enumerated() {
    items.append(.init(id: UUID(), stem: "Case \(i): sudden chest pain for an hour.", answer: answer))
}
items.append(.init(id: UUID(), stem: "A 30-year-old with a headache.", answer: "Migraine"))
let blocks = SymptomBlocks.blocks(items)
check("six chest pain questions across five causes make a block",
      blocks.count == 1 && blocks[0].presentation.id == "chest-pain" && blocks[0].causes == 5,
      "\(blocks.map { ($0.id, $0.ids.count, $0.causes) })")
check("one headache question does not", !blocks.contains { $0.id == "headache" })
check("but is listed when thin ones are asked for",
      SymptomBlocks.blocks(items, includeThin: true).contains { $0.id == "headache" })
let sameAnswer = (0..<6).map { SymptomBlocks.Item(id: UUID(), stem: "Chest pain \($0).", answer: "Pericarditis") }
check("six questions with one answer are not a block (nothing to tell apart)",
      SymptomBlocks.blocks(sameAnswer).isEmpty)

struct Fixed: RandomNumberGenerator {
    var s: UInt64 = 7
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
}
var rng = Fixed()
let chest = Array(items.prefix(6))
let mixed = SymptomBlocks.interleaved(chest, using: &rng)
check("interleaving keeps every question", Set(mixed.map(\.id)) == Set(chest.map(\.id)))
var repeats = 0
for i in 1..<mixed.count where SymptomBlocks.normalised(mixed[i].answer) == SymptomBlocks.normalised(mixed[i - 1].answer) {
    repeats += 1
}
check("and never puts the same answer twice in a row here", repeats == 0, "\(mixed.map(\.answer))")

let cq = UUID()
let confusions = SymptomBlocks.confusions(
    questions: [cq: (options: ["ACS", "PE", "Dissection"], correct: 2)],
    events: [AnswerEvent(questionId: cq, correct: false, date: now, picked: 0),
             AnswerEvent(questionId: cq, correct: false, date: now, picked: 0),
             AnswerEvent(questionId: cq, correct: true, date: now, picked: 2)])
check("the confusion table counts what was picked against what it was",
      confusions == [.init(picked: "ACS", actual: "Dissection", count: 2)], "\(confusions)")

// MARK: guess first

let chapter = """
# Hernias

An inguinal hernia emerges above and medial to the pubic tubercle.
A femoral hernia emerges below and lateral to the pubic tubercle.
A femoral hernia is more common in women and carries a high risk of strangulation.
An indirect inguinal hernia passes through the deep ring lateral to the inferior epigastric vessels.
A direct inguinal hernia pushes through Hesselbach's triangle medial to the inferior epigastric vessels.
A saphena varix is a dilatation of the saphenous vein at the saphenofemoral junction and has a cough impulse.
The saphena varix disappears when the patient lies down and may show a fluid thrill.
Inguinal lymphadenopathy is often multiple and may follow infection in the leg or perineum.
Lymphadenopathy in the groin should prompt examination of the lower limb, anus and genitalia.
Strangulation of a hernia causes pain, tenderness and features of bowel obstruction.
"""
let pre = Pretest.questions(from: chapter, seed: 42)
check("a pretest is five questions", pre.count == 5, "\(pre.count)")
check("each with five options", pre.allSatisfy { $0.options.count == 5 })
check("and one blank in its stem", pre.allSatisfy { $0.stem.components(separatedBy: "_____").count == 2 },
      "\(pre.map(\.stem))")
check("the answer fills the blank back to the sentence",
      pre.allSatisfy { $0.explanation.lowercased().contains($0.options[$0.correctIndex].lowercased()) })
check("options are all different", pre.allSatisfy { Set($0.options.map { $0.lowercased() }).count == 5 })
check("no option is already in the stem",
      pre.allSatisfy { q in q.options.enumerated().allSatisfy { i, o in
          i == q.correctIndex || !Pretest.words(q.stem).map { $0.lowercased() }.contains(o.lowercased()) } })
check("the same text gives the same pretest",
      Pretest.questions(from: chapter, seed: 42).map { $0.stem + $0.options.joined() } == pre.map { $0.stem + $0.options.joined() })
check("too little text gives none rather than a bad one",
      Pretest.questions(from: "Short note. Nothing here.").isEmpty)
check("blanks match whole words",
      Pretest.blanked("renal", in: "The adrenal gland sits on the renal pole.") == "The adrenal gland sits on the _____ pole.")
check("markdown marks are stripped", Pretest.plain("## **Bold** heading") == "Bold heading")

// MARK: the daily rhythm

let m1 = UUID(), m2 = UUID(), m3 = UUID()
let yesterday = now.addingTimeInterval(-day)
let log: [AnswerEvent] = [
    AnswerEvent(questionId: m1, correct: false, date: yesterday),
    AnswerEvent(questionId: m2, correct: false, date: yesterday),
    AnswerEvent(questionId: m2, correct: true, date: yesterday.addingTimeInterval(600)),
    AnswerEvent(questionId: m3, correct: false, date: yesterday.addingTimeInterval(900)),
    AnswerEvent(questionId: m3, correct: true, date: now.addingTimeInterval(-600)),
]
check("the day's misses are those last got wrong that day",
      StudyRhythm.missed(on: yesterday, events: log, calendar: calendar) == [m1, m3])
check("the morning check leaves out what is already answered today",
      StudyRhythm.morningItems(now: now, events: log, calendar: calendar) == [m1])

let cands = [StudyRhythm.Candidate(id: m1, subject: "Renal", optionCount: 5),
             StudyRhythm.Candidate(id: m2, subject: "Renal", optionCount: 5),
             StudyRhythm.Candidate(id: m3, subject: "Cardiology", optionCount: 5),
             StudyRhythm.Candidate(id: UUID(), subject: "Renal", optionCount: 7)]
let pick = StudyRhythm.questionOfTheDay(cands, weakestFirst: ["Renal", "Cardiology"],
                                        standings: [m2: .building(2)], day: now, calendar: calendar)
check("the question of the day comes from the weakest subject, nearest to secured", pick == m2)
check("and is the same all day",
      StudyRhythm.questionOfTheDay(cands, weakestFirst: ["Renal"], standings: [:], day: now, calendar: calendar)
      == StudyRhythm.questionOfTheDay(cands, weakestFirst: ["Renal"], standings: [:],
                                      day: now.addingTimeInterval(3600), calendar: calendar))
check("a question with more options than buttons is never chosen",
      StudyRhythm.questionOfTheDay([cands[3]], weakestFirst: ["Renal"], standings: [:], day: now) == nil)
check("the body lists the options by letter",
      StudyRhythm.questionBody(stem: "Which?", options: ["One", "Two"]).contains("B  Two"))
check("a long option is cut for its button", StudyRhythm.abbreviated(String(repeating: "x", count: 50)).count == 34)
check("bedtime mentions sleep only in exam week",
      StudyRhythm.bedtimeBody(misses: 3, examDays: 5).contains("sleep")
      && !StudyRhythm.bedtimeBody(misses: 3, examDays: 30).contains("sleep"))
let at = ReminderSettings.next(22 * 60, after: now, calendar: calendar)
check("a reminder later today is today's",
      calendar.isDate(at, inSameDayAs: now) && calendar.component(.hour, from: at) == 22)
let early = ReminderSettings.next(7 * 60, after: now, calendar: calendar)
check("one already past is tomorrow's", calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                                  to: calendar.startOfDay(for: early)).day == 1)

print("\(passed) checks passed")
print(failures.isEmpty ? "ALL LEARN TESTS PASS" : "\(failures.count) LEARN TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
