// Today's ward round and the Vitals screen's readings: which beds a round
// holds and in what order, the weak spots that need a consult (and that the
// weakest of them always has a bed, which is what the Vitals screen promises),
// the minutes, the study rhythm read from StudyLog's days, and the words
// around the numbers - all choices that look right on screen whether or not
// they are, so they are pinned here.
import Foundation

var failures: [String] = []
var passed = 0

// only failures are printed (see LearnTests)
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; return }
    print("FAIL " + label + "  | " + detail)
    failures.append(label)
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!
let day: TimeInterval = 86_400
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!

typealias Topic = BedPlan.Topic
func topic(_ name: String, _ correct: Int, of answered: Int, questions: Int = 40) -> Topic {
    Topic(name: name, questions: questions, answered: answered, correct: correct)
}
func fresh(_ name: String, _ mode: BedPlan.Mode = .questions, items: Int = 42, daysAgo: Double = 1,
           subject: String = "Renal") -> BedPlan.FreshSet {
    BedPlan.FreshSet(id: UUID(), name: name, subject: subject, mode: mode, items: items,
                     createdAt: now.addingTimeInterval(-daysAgo * day))
}
func station(_ title: String, resumes: Bool = false, daysAgo: Double = 1) -> BedPlan.Station {
    BedPlan.Station(setID: UUID(), title: title, resumes: resumes, createdAt: now.addingTimeInterval(-daysAgo * day))
}
func kinds(_ beds: [BedPlan.Bed]) -> [String] {
    beds.map { bed in
        switch bed.kind {
        case .priority: return "priority"
        case .dueCards: return "due"
        case .weakest: return "weakest"
        case .freshSet: return "fresh"
        case .station: return "station"
        }
    }
}

// MARK: weak spots

let topics: [Topic] = [
    topic("Cardiology", 30, of: 40),      // 75%: not below the line
    topic("Renal", 12, of: 25),           // 48%
    topic("Endocrine", 2, of: 4),         // 50% but only 4 answers
    topic("Neurology", 13, of: 25),       // 52%
    topic("Haematology", 0, of: 0),       // never tried
]
let spots = BedPlan.weakSpots(topics)
check("weak spots: tried five times or more and under 75%, weakest first",
      spots.map(\.name) == ["Renal", "Neurology"], "\(spots.map(\.name))")
check("exactly 75% does not need a consult", !spots.contains { $0.name == "Cardiology" })
check("four answers are not enough to judge", !spots.contains { $0.name == "Endocrine" })
check("a subject never tried is not a weak spot", !spots.contains { $0.name == "Haematology" })
check("a tie in accuracy goes to the one with more answers",
      BedPlan.weakSpots([topic("A", 5, of: 10), topic("B", 10, of: 20)]).map(\.name) == ["B", "A"])
check("percent is rounded", topic("x", 12, of: 25).percent == 48 && topic("y", 2, of: 3).percent == 67)

// MARK: the round

var full = BedPlan.Input()
full.phase = .building(days: 30)
full.mission = .dueCards(12)
full.dueCards = 12
full.dueFrom = ["Cardiology"]
full.topics = topics
full.fresh = [fresh("Nephrotic syndrome")]
full.stations = [station("CVS examination")]
full.secondsPerQuestion = 75
full.stationMinutes = 8
let round = BedPlan.beds(full)
check("the round: cards due, weakest, a new set, a station",
      kinds(round) == ["due", "weakest", "fresh", "station"], "\(kinds(round))")
check("beds are numbered from one", round.map(\.number) == [1, 2, 3, 4])
check("bed 1 is overlined with the one subject the due cards come from",
      round[0].overline == "Bed 1 \u{00B7} Cardiology", round[0].overline)
check("and says how many are due", round[0].title == "12 cards due" && round[0].status == .due)
check("the weakest topic is the first weak spot",
      round[1].ward == "Renal" && round[1].title == "Weakest topic \u{00B7} 48%" && round[1].status == .weak,
      "\(round[1])")
check("its drill is twenty MCQs", round[1].detail == "20 MCQs, missed ones first", round[1].detail)
check("the new set is New, with its kind and size",
      round[2].title == "Nephrotic syndrome" && round[2].detail == "MCQ \u{00B7} 42 questions \u{00B7} not started"
        && round[2].status == .new, round[2].detail)
check("the station is timed at the exam's station length, with no chip",
      round[3].ward == "OSCE station" && round[3].detail == "8 min timed" && round[3].status == nil)
check("minutes: 12 cards at 10 s is 2, 20 MCQs at 75 s is 25, 20 of a new set 25, a station 8",
      round.map(\.minutes) == [2, 25, 25, 8], "\(round.map(\.minutes))")
check("the summary counts patients and adds the minutes",
      BedPlan.summary(round) == "4 patients \u{00B7} 60 min", BedPlan.summary(round))
check("one patient is singular", BedPlan.summary([round[3]]) == "1 patient \u{00B7} 8 min")
check("an empty round says so", BedPlan.summary([]) == "No patients waiting")
check("VoiceOver hears the heading without separators",
      BedPlan.spokenSummary(round) == "Today\u{2019}s ward round: 4 patients, about 60 minutes.",
      BedPlan.spokenSummary(round))
check("and an empty round in words", BedPlan.spokenSummary([]) == "Today\u{2019}s ward round: no patients waiting.")
check("each bed has its own id", Set(round.map(\.id)).count == round.count)
check("VoiceOver hears the bed whole",
      round[0].spoken == "Bed 1, Cardiology. 12 cards due. Spaced review. About 2 minutes. Due", round[0].spoken)

// the planner's priority goes first, and pushes the station off a full round
var morning = full
morning.mission = .morningCheck(3)
let morningRound = BedPlan.beds(morning)
check("the morning check takes bed 1", kinds(morningRound) == ["priority", "due", "weakest", "fresh"],
      "\(kinds(morningRound))")
check("never more than four beds", morningRound.count == BedPlan.most)
check("the morning check is three questions from yesterday",
      morningRound[0].title == "3 questions from yesterday" && morningRound[0].ward == "Morning check")

// missions another bed already holds are not doubled
for mission in [ExamWeekPlanner.Mission.dueCards(12), .weakest("Renal"), .newQuestions, .nothing] {
    check("no priority bed for \(mission)", BedPlan.priority(mission) == nil)
}
for mission in [ExamWeekPlanner.Mission.examKit, .morningCheck(1), .mock, .confidentErrors(2), .mistakes(3),
                .lockIn(4), .flagged(5)] {
    check("a priority bed for \(mission)", BedPlan.priority(mission) == mission)
}

// several decks
var spread = full
spread.dueFrom = ["Cardiology", "Renal", "Respiratory"]
let spreadDue = BedPlan.beds(spread)[0]
check("due cards from several subjects", spreadDue.ward == "Spaced review" && spreadDue.detail == "From 3 subjects",
      "\(spreadDue)")
check("one card is singular", BedPlan.bed(.dueCards(1), number: 1, full).title == "1 card due")

// the newest unstarted set, and nothing new in exam week
var two = full
let older = fresh("Older set", daysAgo: 5)
let newer = fresh("Newer set", daysAgo: 1)
two.fresh = [older, newer]
let picked = BedPlan.beds(two).first { if case .freshSet = $0.kind { return true }; return false }
check("the newest unstarted set takes the bed", picked?.title == "Newer set", picked?.title ?? "none")
check("an empty set never takes a bed", BedPlan.newest([fresh("Empty", items: 0)]) == nil)
var week = full
week.phase = .examWeek(days: 5)
week.mission = .confidentErrors(2)
let weekRound = BedPlan.beds(week)
check("exam week: no new set", !kinds(weekRound).contains("fresh"), "\(kinds(weekRound))")
check("exam week: the confident errors first, then due, weakest, station",
      kinds(weekRound) == ["priority", "due", "weakest", "station"], "\(kinds(weekRound))")
var examDay = full
examDay.phase = .examDay
examDay.mission = .examKit
let dayRound = BedPlan.beds(examDay)
check("exam day: the kit and nothing else", kinds(dayRound) == ["priority"] && dayRound[0].title == "Your exam-day kit")

// new questions when the planner wants them and no set is new
var untried = BedPlan.Input()
untried.mission = .newQuestions
untried.untried = 37
let untriedRound = BedPlan.beds(untried)
check("new questions take a bed when no set is new",
      untriedRound.count == 1 && untriedRound[0].title == "37 not tried yet" && untriedRound[0].status == .new,
      "\(untriedRound)")
untried.fresh = [fresh("Brand new")]
check("but a new set is the better bed", kinds(BedPlan.beds(untried)) == ["fresh"])

// the planner's own weakest subject, when no subject is judged yet
var early = BedPlan.Input()
early.mission = .weakest("Renal")
early.topics = [topic("Renal", 1, of: 3, questions: 8)]
let earlyRound = BedPlan.beds(early)
check("the planner's weakest subject still gets its bed",
      earlyRound.count == 1 && earlyRound[0].ward == "Renal" && earlyRound[0].detail == "8 MCQs, missed ones first",
      "\(earlyRound)")

// stations: one part way through first
let resumed = station("Abdominal exam", resumes: true, daysAgo: 9)
let newestStation = station("Breaking bad news", daysAgo: 1)
check("a station part way through comes before a newer one",
      BedPlan.station([newestStation, resumed])?.title == "Abdominal exam")
var resuming = BedPlan.Input()
resuming.stations = [resumed]
check("and says it carries on", BedPlan.beds(resuming)[0].detail == "8 min timed \u{00B7} carry on where you left off")

// the weakest topic named by Vitals is always on the round
let priorities: [ExamWeekPlanner.Mission] = [.morningCheck(2), .lockIn(4), .flagged(1), .mock, .mistakes(9)]
for mission in priorities {
    var input = full
    input.mission = mission
    let beds = BedPlan.beds(input)
    let weakestBed = beds.first { if case .weakest = $0.kind { return true }; return false }
    check("weakest stays on a full round (\(mission))", weakestBed?.ward == BedPlan.weakSpots(input.topics).first?.name)
}

// a quiet library: no beds
check("nothing waiting, no beds", BedPlan.beds(BedPlan.Input()).isEmpty)

// minutes
check("minutes round up", BedPlan.minutes(seconds: 61) == 2 && BedPlan.minutes(seconds: 60) == 1)
check("and never fall under one", BedPlan.minutes(seconds: 0) == 1)
check("a textbook's first sitting is three pages",
      BedPlan.firstSittingMinutes(fresh("Book", .textbook, items: 40), secondsPerQuestion: 75) == 9)
check("a deck's first sitting is twenty cards",
      BedPlan.firstSittingMinutes(fresh("Deck", .cards, items: 200), secondsPerQuestion: 75) == 4)
check("about one minute is singular", BedPlan.aboutMinutes(1) == "About 1 minute")

// MARK: the study rhythm

func days(_ offsets: [Int], from base: Date = now) -> [String: Int] {
    var out: [String: Int] = [:]
    for offset in offsets {
        let date = calendar.date(byAdding: .day, value: -offset, to: base)!
        out[RhythmReading.key(date, calendar: calendar)] = 5
    }
    return out
}

check("the key is StudyLog's yyyy-MM-dd", RhythmReading.key(now, calendar: calendar) == "2026-09-24",
      RhythmReading.key(now, calendar: calendar))

let none = RhythmReading.read(days: [:], now: now, calendar: calendar)
check("no history: no trace yet", none.rhythm == .noTrace && none.words == "No trace yet")
check("a strip is always fourteen days", none.beats.count == RhythmReading.window)
check("zero counts are no history", RhythmReading.read(days: ["2026-09-23": 0], now: now, calendar: calendar).rhythm == .noTrace)

let steady = RhythmReading.read(days: days(Array(0..<14).filter { $0 % 7 != 3 }), now: now, calendar: calendar)
check("most days, short gaps: regular", steady.rhythm == .regular && steady.words == "Sinus \u{00B7} regular",
      "\(steady.rhythm) \(steady.activeDays)/\(steady.span)")
check("its line counts the days", steady.line == "Studied 12 of the last 14 days.", steady.line)
check("today is the last beat", steady.beats.last == true)

let patchy = RhythmReading.read(days: days([0, 4, 5, 9, 13]), now: now, calendar: calendar)
check("some days with long gaps: irregular", patchy.rhythm == .irregular, "\(patchy.rhythm)")

let gappy = RhythmReading.read(days: days(Array(0..<14).filter { ![4, 5, 6].contains($0) }), now: now, calendar: calendar)
check("three days off in a row is not regular, however many days", gappy.rhythm == .irregular, "\(gappy.rhythm)")

let away = RhythmReading.read(days: days([8, 9, 10, 11, 12, 13]), now: now, calendar: calendar)
check("a week with nothing: resting", away.rhythm == .resting && away.line.hasPrefix("Nothing in the last 7 days"),
      "\(away.rhythm)")
let long = RhythmReading.read(days: days([40]), now: now, calendar: calendar)
check("studying long ago and not since: resting, not no trace", long.rhythm == .resting)

// the day is not over: nothing yet today does not count against the strip
let breakfast = RhythmReading.read(days: days(Array(1..<14)), now: now, calendar: calendar)
check("nothing yet today: the strip ends yesterday, still regular",
      breakfast.rhythm == .regular && breakfast.beats.last == true, "\(breakfast.rhythm)")

// a new student is read over the days since starting
let newcomer = RhythmReading.read(days: days([0, 1, 2]), now: now, calendar: calendar)
check("three days in, three days studied: regular over three days",
      newcomer.rhythm == .regular && newcomer.span == 3 && newcomer.line == "Studied 3 of the last 3 days.",
      "\(newcomer.span) \(newcomer.line)")
let first = RhythmReading.read(days: days([0]), now: now, calendar: calendar)
check("the first day says day, not 1 days", first.line == "Studied 1 of the last day.", first.line)
check("VoiceOver hears the rhythm", steady.spoken.hasPrefix("Study rhythm, regular."), steady.spoken)
check("no word is alarming", [none, steady, patchy, away].allSatisfy { reading in
    let text = (reading.words + " " + reading.line).lowercased()
    return !["arrest", "flatline", "fail", "bad", "lazy", "danger"].contains { text.contains($0) }
})

// MARK: the words

check("countdown with no date: none", WardWords.countdown(days: nil) == nil)
check("countdown after the exam: none", WardWords.countdown(days: -2) == nil)
check("countdown names finals by default", WardWords.countdown(days: 23) == "Finals in 23 days")
check("countdown names the chosen exam", WardWords.countdown(days: 23, exam: "PLAB 1") == "PLAB 1 in 23 days")
check("countdown tomorrow and today",
      WardWords.countdown(days: 1) == "Finals tomorrow" && WardWords.countdown(days: 0, exam: "Step 1") == "Step 1 today")
check("a blank exam name is finals", WardWords.countdown(days: 3, exam: "  ") == "Finals in 3 days")

check("greeting by the hour", WardWords.greeting(hour: 8) == "Good morning"
      && WardWords.greeting(hour: 14) == "Good afternoon" && WardWords.greeting(hour: 21) == "Good evening"
      && WardWords.greeting(hour: 2) == "Good evening")
check("greeting with a first name", WardWords.greeting(hour: 9, name: "Sam Patel") == "Good morning, Sam")
check("no greeting by the stand-in name", WardWords.greeting(hour: 9, name: "Me") == "Good morning")
check("no greeting by email", WardWords.firstName("sam@example.edu") == nil)
check("no greeting by a blank name", WardWords.firstName("  ") == nil && WardWords.firstName(nil) == nil)

check("standing: the whole range above the mark", WardWords.standing(low: 0.62, high: 0.74, passMark: 0.6) == "on track for a pass")
check("standing: below, for now", WardWords.standing(low: 0.40, high: 0.55, passMark: 0.6) == "below the pass mark for now")
check("standing: across the mark", WardWords.standing(low: 0.55, high: 0.66, passMark: 0.6) == "around the pass mark")
check("the vitals line joins them",
      WardWords.vitalsLine(countdown: "Finals in 23 days", standing: "on track for a pass")
        == "Finals in 23 days \u{00B7} on track for a pass")
check("the vitals line without an estimate is the countdown",
      WardWords.vitalsLine(countdown: "Finals in 23 days", standing: nil) == "Finals in 23 days")
check("no countdown, no line", WardWords.vitalsLine(countdown: nil, standing: "on track for a pass") == nil)

print("\(passed) checks passed")
print(failures.isEmpty ? "ALL BED PLAN TESTS PASS" : "\(failures.count) BED PLAN TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
