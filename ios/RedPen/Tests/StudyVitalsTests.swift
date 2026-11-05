// The study rhythm and the streak agree (T0211 A4): Vitals said "Studied 10
// of the last 10 days" beside "No streak yet", the rhythm read from the
// study log with the dated answers and the streak from the study log alone.
// StudyVitals reads both from one set of days. This runs every pattern of
// study over the last twelve days, and 2,000 seeded ones over forty, in two
// time zones whose clocks change inside the strip, and checks the two
// readings can never say different things.
import Foundation

var failures: [String] = []
var passed = 0

// only failures are printed (see LearnTests)
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; return }
    print("FAIL " + label + "  | " + detail)
    failures.append(label)
}

/// Every way the two readings could disagree, for one set of days.
func agree(_ days: [String: Int], minutes: [String: Int] = [:], now: Date, calendar: Calendar, _ name: String) {
    let r = StudyVitals.read(days: days, minutes: minutes, now: now, calendar: calendar)
    let all = StudyVitals.studied(days: days, minutes: minutes)
    let strip = r.rhythm, streak = r.streak.streak
    check("\(name): the rhythm is RhythmReading's on the same days",
          strip == RhythmReading.read(days: all, now: now, calendar: calendar))
    check("\(name): the streak is StudyStreak's on the same days",
          r.streak == StudyStreak.summary(active: Set(all.filter { $0.value > 0 }.keys), today: now, calendar: calendar))
    // the strip ends today, or yesterday while today has nothing yet
    if strip.beats.last == true {
        check("\(name): a beat on the strip's last day is a streak of at least one", streak >= 1, "\(streak)")
    }
    var run = 0
    for beat in strip.beats.reversed() {
        if !beat { break }
        run += 1
    }
    check("\(name): the beats in a row at the strip's end are no longer than the streak", run <= streak,
          "\(run) beats, streak \(streak)")
    if strip.span > 0 && strip.activeDays == strip.span {
        check("\(name): \"\(strip.line)\" is a streak of at least \(strip.span)", streak >= strip.span, "\(streak)")
    }
    if streak > 0 {
        check("\(name): a streak is never beside a resting or empty strip",
              strip.rhythm == .regular || strip.rhythm == .irregular, "\(strip.rhythm), streak \(streak)")
    }
    for rest in r.streak.restDays {
        check("\(name): a rest day is a day not studied", (all[rest] ?? 0) == 0, rest)
    }
}

for zone in ["Europe/London", "Africa/Cairo"] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    // the strip runs back over the clock change at the end of October
    // (25 Oct 2026 in London; Egypt's last Thursday, 29 Oct)
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
    let today = calendar.startOfDay(for: now)
    let keys: [String] = (0..<40).map {
        RhythmReading.key(calendar.date(byAdding: .day, value: -$0, to: today)!, calendar: calendar)
    }
    check("\(zone): forty days back are forty different days", Set(keys).count == 40)

    // every pattern of the last twelve days, today included
    let span = 12
    for mask in 0..<(1 << span) {
        var days: [String: Int] = [:]
        for back in 0..<span where mask & (1 << back) != 0 { days[keys[back]] = 1 + back % 3 }
        agree(days, now: now, calendar: calendar, "\(zone) pattern \(mask)")
    }

    // seeded longer ones, with zero counts and a ward round's minutes mixed in
    var seed: UInt64 = 0x5EED_0211
    func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed >> 33
    }
    for n in 0..<2000 {
        var days: [String: Int] = [:], minutes: [String: Int] = [:]
        let density = Int(next() % 10)
        for back in 0..<40 {
            let roll = Int(next() % 10)
            if roll < density { days[keys[back]] = Int(next() % 4) }      // 0 is a day kept with nothing in it
            else if roll == 9 { minutes[keys[back]] = Int(next() % 30) }  // minutes alone, or none
        }
        agree(days, minutes: minutes, now: now, calendar: calendar, "\(zone) seeded \(n)")
    }

    // the review's case: ten days of answers synced from another phone, the
    // study log empty. The log's own streak was 0 beside "10 of the last 10".
    let answers: [Date] = (0..<10).map { calendar.date(byAdding: .day, value: -$0, to: now)! }
    let merged = RhythmReading.merged(log: [:], answers: answers, calendar: calendar)
    let review = StudyVitals.read(days: merged, now: now, calendar: calendar)
    check("\(zone): ten days of answers read \"Studied 10 of the last 10 days.\"",
          review.rhythm.line == "Studied 10 of the last 10 days.", review.rhythm.line)
    check("\(zone): beside a ten-day streak", review.streak.streak == 10, "\(review.streak.streak)")
    check("\(zone): where the log alone said no streak",
          StudyStreak.summary(active: [], today: now, calendar: calendar).streak == 0)

    // a ward round's minutes count as a day studied in both readings
    let roundOnly = StudyVitals.read(days: [:], minutes: [keys[0]: 25, keys[1]: 0], now: now, calendar: calendar)
    check("\(zone): a day of minutes alone is a beat", roundOnly.rhythm.beats.last == true && roundOnly.rhythm.activeDays == 1)
    check("\(zone): and a day of the streak", roundOnly.streak.streak == 1, "\(roundOnly.streak.streak)")
    check("\(zone): minutes never lower a day's count",
          StudyVitals.studied(days: [keys[0]: 7], minutes: [keys[0]: 30]) == [keys[0]: 7])
    check("\(zone): no minutes and no days are no trace",
          StudyVitals.read(days: [:], minutes: [keys[0]: 0], now: now, calendar: calendar).rhythm.rhythm == .noTrace)
}

print(failures.isEmpty ? "\nALL \(passed) STUDY VITALS CHECKS PASS" : "\n\(failures.count) FAILED of \(passed + failures.count)")
exit(failures.isEmpty ? 0 : 1)
