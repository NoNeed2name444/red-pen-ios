// The ward round's clock (rounds, breaks, pausing, a locked phone coming
// back, stopping early), the daily goal, and the streak's free rest day.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

// MARK: the plan

let standard = WardRoundPlan.standard
check("standard is 25 on, 5 off, 4 rounds",
      standard.focusMinutes == 25 && standard.breakMinutes == 5 && standard.rounds == 4)
let silly = WardRoundPlan(focusMinutes: 0, breakMinutes: 900, rounds: 99)
check("a stored plan is held to sane values",
      silly.focusMinutes == 1 && silly.breakMinutes == 30 && silly.rounds == 8, "\(silly)")
check("choices", WardRoundPlan.focusChoices == [25, 50] && WardRoundPlan.breakChoices == [5, 10])

// MARK: a round from start to finish

var round = WardRound.begin(standard, at: t0)
check("starts on round 1, focusing", round.round == 1 && round.phase == .focus)
check("full clock at the start", round.remaining(at: t0) == 25 * 60)
check("ring full at the start", round.leftFraction(at: t0) == 1)
check("ring half way", abs(round.leftFraction(at: at(12.5)) - 0.5) < 0.0001)
check("clock text at the start", WardRound.clock(round.remaining(at: t0)) == "25:00")
check("clock text rounds up", WardRound.clock(0.2) == "0:01" && WardRound.clock(760) == "12:40")
check("nothing ends early", round.advance(to: at(24.9)).isEmpty && round.phase == .focus)

round.noteStudied(3)
round.noteStudied(0)
check("items counted while focusing", round.items == 3)
let twelveForty: Date = t0.addingTimeInterval(740)
check("caption", round.caption(at: twelveForty) == "Round 1 of 4 \u{00B7} 12:40 \u{00B7} 3 cards",
      round.caption(at: twelveForty))

var events = round.advance(to: at(26))
check("round 1 ends into its break",
      events == [.focusEnded(round: 1, seconds: 1500, end: at(25))] && round.phase == .rest, "\(events)")
check("the break runs from when the round ran out, not from now", round.remaining(at: at(26)) == 4 * 60)
round.noteStudied(5)
check("items in a break are not the round's", round.items == 3)
check("break caption", round.caption(at: at(26)).hasPrefix("Break \u{00B7} 4:00"), round.caption(at: at(26)))

events = round.advance(to: at(31))
check("the break ends and waits", events == [.restEnded(round: 1)] && round.phase == .ready, "\(events)")
check("waiting has no clock", round.remaining(at: at(40)) == 0 && !round.ticks)
check("waiting does not move on by itself", round.advance(to: at(500)).isEmpty && round.phase == .ready)
check("ready caption", round.caption(at: at(40)).hasPrefix("Round 2 of 4 when you"), round.caption(at: at(40)))

round.startNext(at: at(40))
check("round 2 starts when asked", round.round == 2 && round.phase == .focus && round.remaining(at: at(40)) == 25 * 60)

// MARK: a locked phone coming back

// the phone is put away mid round 2 and picked up long after its break
events = round.advance(to: at(90))
check("the round and its break both end on the way", events == [
    .focusEnded(round: 2, seconds: 1500, end: at(65)), .restEnded(round: 2)] && round.phase == .ready, "\(events)")
check("focus minutes add up", round.focusMinutes == 50)

// MARK: pause

round.startNext(at: at(100))
round.pause(at: at(110))
check("paused holds the clock", round.isPaused && round.remaining(at: at(200)) == 15 * 60)
let itemsBeforePause: Int = round.items
round.noteStudied(4)
check("items while paused are not the round's", round.items == itemsBeforePause, "\(round.items)")
check("nothing ends while paused", round.advance(to: at(1000)).isEmpty && round.phase == .focus)
check("no alarms while paused", round.alarms(at: at(200)).isEmpty)
round.resume(at: at(200))
check("resumed from where it was held", !round.isPaused && round.remaining(at: at(200)) == 15 * 60)
events = round.advance(to: at(216))
check("round 3 ends 15 minutes after resuming",
      events == [.focusEnded(round: 3, seconds: 1500, end: at(215))], "\(events)")

// MARK: skipping

round.startNext(at: at(217))
check("starting from a break skips the rest of it", round.round == 4 && round.phase == .focus)
events = round.skip(at: at(227))
check("the last round cut short still counts its ten minutes, and finishes",
      events == [.focusEnded(round: 4, seconds: 600, end: at(227)), .finished] && round.phase == .done, "\(events)")
check("focus total", round.focusMinutes == 85, "\(round.focusMinutes)")
check("done caption", round.caption(at: at(230)) == "Ward round done \u{00B7} 85 min \u{00B7} 3 cards",
      round.caption(at: at(230)))
round.startNext(at: at(240))
check("no fifth round", round.phase == .done && round.round == 4)
check("stopping a finished round does nothing", round.stop(at: at(241)).isEmpty)

var skipper = WardRound.begin(WardRoundPlan(focusMinutes: 50, breakMinutes: 10), at: t0)
_ = skipper.advance(to: at(51))
check("a 50-minute round has a 10-minute break", skipper.phase == .rest && skipper.remaining(at: at(51)) == 9 * 60)
events = skipper.skip(at: at(52))
check("a skipped break goes to ready", events == [.restEnded(round: 1)] && skipper.phase == .ready)

// MARK: stopping

var stopper = WardRound.begin(standard, at: t0)
stopper.pause(at: at(5))
events = stopper.stop(at: at(30))
check("stopping mid round counts the time sat, not the time paused",
      events == [.focusEnded(round: 1, seconds: 300, end: at(30)), .finished] && stopper.phase == .done, "\(events)")
var inBreak = WardRound.begin(standard, at: t0)
_ = inBreak.advance(to: at(27))
events = inBreak.stop(at: at(28))
check("stopping in a break logs no more focus", events == [.finished], "\(events)")

// MARK: alarms

let fresh = WardRound.begin(standard, at: t0)
let alarms = fresh.alarms(at: t0)
check("two alarms: the round's end and the break's end", alarms.count == 2
      && alarms[0].date == at(25) && alarms[1].date == at(30), "\(alarms)")
check("alarm ids are the known ones", Set(alarms.map(\.id)).isSubset(of: Set(WardRound.alarmIDs)))
check("round alarm says which round", alarms[0].title == "Round 1 of 4 done", alarms[0].title)
var last = WardRound.begin(WardRoundPlan(focusMinutes: 25, breakMinutes: 5, rounds: 1), at: t0)
check("the last round's alarm is the end", last.alarms(at: t0).map(\.title) == ["Ward round done"])
_ = last.advance(to: at(26))
check("no alarms when done", last.alarms(at: at(26)).isEmpty)

// MARK: round trip

let saved = try? JSONEncoder().encode(fresh)
let loaded = saved.flatMap { try? JSONDecoder().decode(WardRound.self, from: $0) }
check("a round survives being saved", loaded == fresh)

// MARK: the daily goal

check("goal label", GoalProgress(done: 32, goal: 50).label == "32 / 50 today")
check("goal fraction", abs(GoalProgress(done: 32, goal: 50).fraction - 0.64) < 0.0001)
check("goal ring stops at full", GoalProgress(done: 80, goal: 50).fraction == 1)
check("goal met", GoalProgress(done: 50, goal: 50).met && !GoalProgress(done: 49, goal: 50).met)
check("no goal, no ring", GoalProgress(done: 5, goal: 0).fraction == 0 && !GoalProgress(done: 5, goal: 0).met)
check("stored goal: nothing stored reads 50", GoalProgress.goal(stored: 0) == 50)
check("stored goal: held to the range", GoalProgress.goal(stored: 3) == 10 && GoalProgress.goal(stored: 5000) == 300)
check("stored goal: a chosen goal is kept", GoalProgress.goal(stored: 120) == 120)
let goalDefaults = UserDefaults.standard
goalDefaults.removeObject(forKey: DailyGoal.key)
check("goal defaults to 50", DailyGoal.current == 50)
DailyGoal.current = 5
check("goal held to the bottom of the range", DailyGoal.current == 10, "\(DailyGoal.current)")
DailyGoal.current = 1000
check("goal held to the top of the range", DailyGoal.current == 300, "\(DailyGoal.current)")
DailyGoal.current = 70
check("goal kept", DailyGoal.current == 70)
check("the ring reads what Settings stored the way DailyGoal does",
      GoalProgress.goal(stored: goalDefaults.integer(forKey: DailyGoal.key)) == DailyGoal.current)
goalDefaults.removeObject(forKey: DailyGoal.key)

// MARK: the streak on day numbers

func streak(_ days: [Int], today: Int) -> (streak: Int, rests: [Int], restReady: Bool) {
    StudyStreak.run(studied: Set(days), today: today)
}

check("nothing studied", streak([], today: 10).streak == 0)
check("a plain run ending today", streak([8, 9, 10], today: 10).streak == 3)
check("a run ending yesterday is alive before today's first card", streak([7, 8, 9], today: 10).streak == 3)
let oneOff = streak([5, 6, 8, 9, 10], today: 10)
check("one missed day is a rest day", oneOff.streak == 5 && oneOff.rests == [7], "\(oneOff)")
check("a rest day used means none is ready", !oneOff.restReady)
let yesterdayOff = streak([7, 8], today: 10)
check("yesterday missed: the run lives while today can still close it",
      yesterdayOff.streak == 2 && yesterdayOff.rests == [9], "\(yesterdayOff)")
let twoOff = streak([5, 6, 9, 10], today: 10)
check("two missed days end it and use no rest day", twoOff.streak == 2 && twoOff.rests.isEmpty, "\(twoOff)")
check("two missed days before today end it", streak([6, 7], today: 10).streak == 0)
let twiceInAWeek = streak([1, 3, 4, 6, 7], today: 7)
check("a second rest day inside a week is not covered",
      twiceInAWeek.streak == 2 && twiceInAWeek.rests == [2], "\(twiceInAWeek)")
let weekApart = streak([1, 3, 4, 5, 6, 7, 8, 9, 11], today: 11)
check("rest days a week apart are both covered",
      weekApart.streak == 9 && weekApart.rests == [2, 10], "\(weekApart)")
check("a rest day is ready again a week later", streak([1, 3, 4, 5, 6, 7, 8, 9], today: 9).restReady)
check("and not six days later", !streak([1, 3, 4, 5, 6, 7, 8], today: 8).restReady)
check("a gap before anything was studied is no rest day", streak([5], today: 5).rests.isEmpty)

// MARK: the streak on real dates

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC") ?? .current
let today = utc.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9)) ?? t0
check("key format", StudyStreak.key(for: today, calendar: utc) == "2026-09-25")
let keyed = StudyStreak.summary(active: ["2026-09-22", "2026-09-23", "2026-09-25"], today: today, calendar: utc)
check("keys: a rest day on the 24th", keyed.streak == 3 && keyed.restDays == ["2026-09-24"], "\(keyed)")
check("keys: future and junk keys ignored",
      StudyStreak.summary(active: ["2026-09-25", "2026-09-26", "junk"], today: today, calendar: utc).streak == 1)
let acrossMonths = StudyStreak.summary(active: ["2026-08-30", "2026-08-31", "2026-09-02"], today: today, calendar: utc)
check("keys: across a month end, a gap of 23 days ends it", acrossMonths.streak == 0, "\(acrossMonths)")
let monthEnd = utc.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 20)) ?? t0
let bridgesMonth = StudyStreak.summary(active: ["2026-08-30", "2026-08-31", "2026-09-02"], today: monthEnd, calendar: utc)
check("keys: a rest day on the 1st bridges the month", bridgesMonth.streak == 3
      && bridgesMonth.restDays == ["2026-09-01"], "\(bridgesMonth)")

// summer time: London moves its clocks on 29 March 2026
var london = Calendar(identifier: .gregorian)
london.timeZone = TimeZone(identifier: "Europe/London") ?? .current
let afterChange = london.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 8)) ?? t0
let dst = StudyStreak.summary(active: ["2026-03-27", "2026-03-28", "2026-03-29", "2026-03-30"],
                              today: afterChange, calendar: london)
check("summer time does not break a run", dst.streak == 4 && dst.restDays.isEmpty, "\(dst)")
let n1 = StudyStreak.dayNumber("2026-03-29", calendar: london) ?? 0
let n2 = StudyStreak.dayNumber("2026-03-30", calendar: london) ?? 0
check("consecutive days are one apart across the change", n2 - n1 == 1, "\(n1) \(n2)")
let back = StudyStreak.date(ofDay: n1, calendar: london).map { StudyStreak.key(for: $0, calendar: london) }
check("a day number turns back into its key", back == "2026-03-29", back ?? "nil")

print(failures.isEmpty ? "\nALL PASSED" : "\n\(failures.count) FAILED: \(failures)")
exit(failures.isEmpty ? 0 : 1)
