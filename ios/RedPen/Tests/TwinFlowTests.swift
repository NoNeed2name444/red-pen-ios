// Write a twin, step by step (T0133): a question is missed, Write a twin is
// tapped, a stand-in writer (no network) writes the twin, it waits a day or
// two on a fake clock, then it is due in the Twins review; the empty Twins
// tile; the twin answered; and everything read back as after a relaunch.
// The steps' names match android/.../quiz/TwinFlowTest.kt.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!

/// The fake clock: a day and hour in October 2026, London time.
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

let missed = MCQQuestion(
    stem: "A 34-year-old man has frothy urine, periorbital oedema and 6 g/day proteinuria. Which finding on light microscopy is most likely?",
    options: ["Normal glomeruli", "Segmental sclerosis in some glomeruli", "Diffuse basement membrane thickening",
              "Mesangial IgA deposits", "Crescents"],
    correctIndex: 1, explanation: "FSGS is the commonest primary cause of nephrotic syndrome in Black adults.")

/// The stand-in writer: answers as the worker would, from the prompt it is given.
func standInWriter(system: String, input: String) -> [MCQQuestion] {
    guard system.contains("\"twin\""), input.contains(missed.stem) else { return [] }
    return [MCQQuestion(
        stem: "A 52-year-old woman with long-standing obesity has leg swelling and 5 g/day of protein in her urine. What does a kidney biopsy most likely show?",
        options: ["Segmental sclerosis in some glomeruli", "Normal glomeruli", "Crescents", "Mesangial IgA deposits",
                  "Diffuse basement membrane thickening"],
        correctIndex: 0, explanation: "Obesity-related FSGS.")]
}

// MARK: S1 a miss offers the twin, and the writer is told what was chosen

let picked = 0
let system = TwinPrompt.instructions(style: "UK finals style.")
let input = TwinPrompt.input(stem: missed.stem, options: missed.options, correctIndex: missed.correctIndex,
                             explanation: missed.explanation, picked: picked, reason: "Misread the question")
check("S1 miss: the writer is told the missed stem", input.contains(missed.stem))
check("S1 miss: and the answer the student chose", input.contains("The student chose: Normal glomeruli"))
check("S1 miss: and the right one", input.contains("Correct answer: Segmental sclerosis in some glomeruli"))
check("S1 miss: and why it was missed", input.contains("Why they missed it: Misread the question"))

// MARK: S2 Write a twin: the stand-in writes it, and it joins the queue

var book = TwinBook()
let request = PendingTwin(parentId: missed.id, picked: picked, reason: nil, confident: false, guessed: false)
let twinId = UUID()
let twin = TwinDraft.pick(standInWriter(system: system, input: input), missed: missed, id: twinId)
check("S2 write: the stand-in's question is taken as the twin", twin != nil)
check("S2 write: the twin has its own id", twin?.id == twinId && twinId != missed.id)
check("S2 write: it says where it came from", twin?.source == "Twin of a missed question", "\(twin?.source ?? "nil")")
let missTime = at(22, 21)   // a Thursday, nine at night
if let twin { book.added(twin.id, parent: missed.id, confident: false, guessed: false, now: missTime, calendar: calendar) }
check("S2 write: the twin is on the way", book.isOnTheWay(for: missed.id))
check("S2 write: the quiz says when it comes back", TwinDraft.madeNote(days: 2)
      == "Twin written. It comes back in 2 days, under Questions \u{2192} Twins.")
// the same stem back again is not a twin: it waits to be written later
let echo = MCQQuestion(stem: missed.stem, options: missed.options, correctIndex: 1, explanation: "")
check("S2 write: the missed question again is refused", TwinDraft.pick([echo], missed: missed) == nil)
var offline = TwinBook()
offline.later(request)
offline.later(request)
check("S2 write: refused or offline, it waits to be written, once", offline.pending == [request])
check("S2 write: and is on the way", offline.isOnTheWay(for: missed.id))
var nothingOut = TwinBook()
check("S2 write: a writer that gives nothing gives no twin", TwinDraft.pick([], missed: missed) == nil)
nothingOut.later(request)
for _ in 0..<40 {
    nothingOut.later(PendingTwin(parentId: UUID(), picked: nil, reason: nil, confident: false, guessed: false))
}
check("S2 write: at most 30 wait, the oldest let go first", nothingOut.pending.count == TwinBook.pendingLimit
      && !nothingOut.pending.contains(request))

// MARK: S3 it waits a day or two, on the fake clock

check("S3 wait: not due the evening it was written", book.queue.due(now: at(22, 23, 59)).isEmpty)
check("S3 wait: not due the next day", book.queue.due(now: at(23, 18)).isEmpty)
check("S3 wait: due from the start of the second day", book.queue.due(now: at(24, 0)).map(\.id) == [twinId],
      "\(book.queue.entries.map(\.dueAt))")
var sure = TwinBook()
sure.added(UUID(), parent: UUID(), confident: true, guessed: false, now: missTime, calendar: calendar)
check("S3 wait: a sure-but-wrong miss comes back tomorrow morning", sure.queue.due(now: at(23, 0)).count == 1
      && sure.queue.due(now: at(22, 23, 59)).isEmpty)
var guess = TwinBook()
guess.added(UUID(), parent: UUID(), confident: false, guessed: true, now: missTime, calendar: calendar)
check("S3 wait: a guess waits three days", guess.queue.due(now: at(24, 12)).isEmpty
      && guess.queue.due(now: at(25, 0)).count == 1)

// MARK: S4 then it appears in review, the longest-waiting first

var two = book
let laterTwin = UUID()
// a sure-but-wrong miss that morning: due on the 23rd, before the first
two.added(laterTwin, parent: UUID(), confident: true, guessed: false, now: at(22, 9), calendar: calendar)
check("S4 review: on the 23rd only the earlier-due twin is in review", two.queue.due(now: at(23, 9)).map(\.id) == [laterTwin])
check("S4 review: by the 24th both, the longest-waiting first",
      two.queue.due(now: at(24, 9)).map(\.id) == [laterTwin, twinId], "\(two.queue.due(now: at(24, 9)).map(\.dueAt))")
check("S4 review: a newer twin for the same question replaces the waiting one", {
    var b = book
    let again = UUID()
    b.added(again, parent: missed.id, confident: false, guessed: false, now: at(23, 10), calendar: calendar)
    return b.queue.waiting.map(\.id) == [again]
}())

// MARK: S5 nothing yet: the Twins tile with nothing due, and its Done

let empty = TwinBook()
check("S5 nothing yet: an empty book has nothing due", empty.queue.due(now: at(30, 12)).isEmpty)
check("S5 nothing yet: a written twin is not due early either", book.queue.due(now: at(23, 12)).isEmpty)
check("S5 nothing yet: the words say what to do", TwinBook.nothingYet.contains("Write a twin")
      && TwinBook.nothingYet.contains("a day or two"))

// MARK: S6 answered: right leaves, wrong comes back a day later once

var answered = book
answered.queue.answered(twinId, correct: false, now: at(24, 10), calendar: calendar)
check("S6 answer: a missed twin comes back the next day", answered.queue.due(now: at(24, 23)).isEmpty
      && answered.queue.due(now: at(25, 0)).map(\.id) == [twinId])
answered.queue.answered(twinId, correct: false, now: at(25, 10), calendar: calendar)
check("S6 answer: missed twice, it leaves the twins for the mistakes", answered.queue.waiting.isEmpty)
var right = book
right.queue.answered(twinId, correct: true, now: at(24, 10), calendar: calendar)
check("S6 answer: got right, it leaves the queue", right.queue.waiting.isEmpty && right.queue.due(now: at(30, 0)).isEmpty)
check("S6 answer: and is kept for the record", right.queue.entries.first?.answeredCorrectly == true)

// MARK: S7 after a relaunch: everything read back as it was saved

let saved = try! JSONEncoder().encode(two.queue)
let savedPending = try! JSONEncoder().encode(offline.pending)
let reloaded = TwinBook(queue: try! JSONDecoder().decode(TwinQueue.self, from: saved),
                        pending: try! JSONDecoder().decode([PendingTwin].self, from: savedPending))
check("S7 relaunch: the queue reads back the same", reloaded.queue == two.queue)
check("S7 relaunch: the pending twins read back the same", reloaded.pending == offline.pending)
check("S7 relaunch: the same twins are due", reloaded.queue.due(now: at(24, 9)) == two.queue.due(now: at(24, 9)))
check("S7 relaunch: still nothing due early", reloaded.queue.due(now: at(22, 22)).isEmpty)
let twinSaved = try! JSONEncoder().encode(twin)
let twinBack = try! JSONDecoder().decode(MCQQuestion.self, from: twinSaved)
check("S7 relaunch: the twin question itself reads back", twinBack == twin)
check("S7 relaunch: a twin whose question left the library is let go", {
    var b = reloaded
    b.queue.prune(keeping: [twinId])
    return b.queue.entries.map(\.id) == [twinId]
}())

print(failures.isEmpty ? "\nALL TWIN FLOW TESTS PASS" : "\n\(failures.count) TWIN FLOW TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
