// The first run and the tips: who is shown the first-run pages and when
// (once per account, new accounts only, never in a screenshot run or the
// simulator's UI tests unless asked), the daily goal's key, default and
// range, and the tips waiting until their screen has been opened twice.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "firstrun-\(UUID().uuidString)")!
}

// MARK: - Whether a launch may show the pages

check("a normal launch on a device shows them",
      FirstRun.allowed(arguments: [], preview: false, simulator: false))
check("the simulator does not (the UI tests run there)",
      !FirstRun.allowed(arguments: [], preview: false, simulator: true))
check("a screenshot run does not",
      !FirstRun.allowed(arguments: [], preview: true, simulator: false))
check("-showOnboarding brings them back in the simulator",
      FirstRun.allowed(arguments: ["-showOnboarding"], preview: false, simulator: true))
check("-disableOnboarding switches them off on a device",
      !FirstRun.allowed(arguments: ["-disableOnboarding"], preview: false, simulator: false))

// MARK: - Who is due

let d1: UserDefaults = freshDefaults()
check("an account that just agreed to the terms is due",
      FirstRun.isDue(accountId: "a", justAgreed: true, examAsked: true, forced: false, defaults: d1))
check("a device that never answered the exam question is due",
      FirstRun.isDue(accountId: "a", justAgreed: false, examAsked: false, forced: false, defaults: d1))
check("somebody already studying here before the pages existed is not",
      !FirstRun.isDue(accountId: "a", justAgreed: false, examAsked: true, forced: false, defaults: d1))
FirstRun.start(accountId: "a", defaults: d1)
check("pages left half way come back on the next launch",
      FirstRun.isDue(accountId: "a", justAgreed: false, examAsked: true, forced: false, defaults: d1))
FirstRun.finish(accountId: "a", defaults: d1)
check("once finished, never again", !FirstRun.isDue(accountId: "a", justAgreed: true, examAsked: false, forced: false, defaults: d1))
check("unless the launch asks for them (a simulator that ran the test before)",
      FirstRun.isDue(accountId: "a", justAgreed: false, examAsked: true, forced: true, defaults: d1))
check("finishing clears the half-way mark", d1.object(forKey: FirstRun.startedKey(for: "a")) == nil)
check("per account: a second account on the device is still due",
      FirstRun.isDue(accountId: "b", justAgreed: true, examAsked: true, forced: false, defaults: d1))
check("forced (the UI test) shows them to an account that has not finished",
      FirstRun.isDue(accountId: "c", justAgreed: false, examAsked: true, forced: true, defaults: d1))
check("the keys carry the account and the version",
      FirstRun.doneKey(for: "xyz") == "firstRun.v\(FirstRun.version).done.xyz")

// MARK: - The daily goal

check("the goal's key is the one the ward-round lane reads", DailyGoal.key == "stethoscore.dailyGoal")
check("the range is 10 to 300", DailyGoal.range == 10...300)
UserDefaults.standard.removeObject(forKey: DailyGoal.key)
check("50 until one is set", DailyGoal.current == 50, "\(DailyGoal.current)")
DailyGoal.current = 120
check("a goal is kept", DailyGoal.current == 120 && UserDefaults.standard.integer(forKey: DailyGoal.key) == 120)
DailyGoal.current = 5
check("too small comes up to 10", DailyGoal.current == 10)
DailyGoal.current = 9000
check("too big comes down to 300", DailyGoal.current == 300)
UserDefaults.standard.set(2, forKey: DailyGoal.key)
check("a stored value out of range reads in range", DailyGoal.current == 10)
UserDefaults.standard.removeObject(forKey: DailyGoal.key)

// MARK: - Tips

let d2: UserDefaults = freshDefaults()
check("no tip before the screen is opened", !TipSightings.ready(.library, defaults: d2))
TipSightings.record(.library, defaults: d2)
check("not on the first opening", !TipSightings.ready(.library, defaults: d2))
TipSightings.record(.library, defaults: d2)
check("not on the second", !TipSightings.ready(.library, defaults: d2))
let third: Int = TipSightings.record(.library, defaults: d2)
check("on the third, once it has been seen twice", TipSightings.ready(.library, defaults: d2) && third == 3)
check("each screen counts on its own", !TipSightings.ready(.lens, defaults: d2) && TipSightings.count(.lens, defaults: d2) == 0)
d2.set(TipSightings.cap, forKey: TipSightings.key(.ideas))
check("counting stops at the cap", TipSightings.record(.ideas, defaults: d2) == TipSightings.cap)
check("five screens, five keys", Set(TipScreen.allCases.map { TipSightings.key($0) }).count == 5)
check("tips on a device", TipSightings.allowed(arguments: [], preview: false, simulator: false))
check("no tips in UI tests (the simulator)", !TipSightings.allowed(arguments: [], preview: false, simulator: true))
check("no tips in a screenshot run", !TipSightings.allowed(arguments: [], preview: true, simulator: false))
check("-disableTips", !TipSightings.allowed(arguments: ["-disableTips"], preview: false, simulator: false))
check("-showTips in the simulator", TipSightings.allowed(arguments: ["-showTips"], preview: false, simulator: true))

print(failures.isEmpty ? "\nALL FIRST RUN TESTS PASS"
                       : "\n\(failures.count) FIRST RUN TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
