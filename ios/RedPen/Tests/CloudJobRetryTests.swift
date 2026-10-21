// A finished cloud job's result that fails to download is asked for again,
// with waits between, while its screen waits; given up, the job is handed to
// the collector and the student told it is not lost (audit #93). A job whose
// generation the system stopped is handed over too, never deleted (#94) -
// unless the stop may have been the student's own, from the progress indicator.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

typealias Rules = CloudJobRules

// MARK: no answer, or a server error: asked again, waiting longer each time

ok(Rules.afterFailedFetch(failed: 1, status: nil) == .after(2), "no signal: asked again in two seconds")
var waits: [TimeInterval] = []
var failed = 0
while case .after(let seconds) = Rules.afterFailedFetch(failed: failed + 1, status: 503) {
    failed += 1
    waits.append(seconds)
    if failed > 100 { break }
}
ok(failed == Rules.fetchWaits.count, "a server error is asked again \(Rules.fetchWaits.count) times, then handed over")
ok(waits == Rules.fetchWaits, "with the waits in order: \(waits)")
ok(zip(waits, waits.dropFirst()).allSatisfy { $0 <= $1 }, "each wait no shorter than the one before")
let total: TimeInterval = waits.reduce(0, +)
ok(total >= 60 && total <= 180, "about two minutes in all while the screen waits (\(Int(total)) s)")
ok(Rules.afterFailedFetch(failed: Rules.fetchWaits.count + 1, status: nil) == .handOver,
   "past the last wait, handed over to the collector")

for code in [429, 500, 502, 503, 504] {
    ok(Rules.afterFailedFetch(failed: 1, status: code) != .handOver, "HTTP \(code) is worth asking again")
}

// MARK: answers that asking again cannot change: handed over at once

for code in [401, 403, 404] {
    ok(Rules.afterFailedFetch(failed: 1, status: code) == .handOver, "HTTP \(code) is handed over at once, not retried")
}
ok(Rules.afterFailedFetch(failed: 0, status: nil) == .handOver, "a count of nothing failed is not a reason to wait")

// MARK: a fetch that fails some times, then works

/// What the screen ends with, for a server that fails `times` times in a
/// row with `status` and then answers: the result, or handed over.
func screen(failing times: Int, status: Int?) -> (fetched: Bool, waited: TimeInterval) {
    var tries = 0
    var waited: TimeInterval = 0
    while true {
        tries += 1
        if tries > times { return (true, waited) }
        switch Rules.afterFailedFetch(failed: tries, status: status) {
        case .after(let seconds): waited += seconds
        case .handOver: return (false, waited)
        }
    }
}

ok(screen(failing: 0, status: nil).fetched, "a fetch that works is not delayed")
ok(screen(failing: 0, status: nil).waited == 0, "not by a second")
ok(screen(failing: 1, status: nil).fetched, "one dropped request no longer loses the wait")
ok(screen(failing: 3, status: 502).fetched, "a server that blinks for a few seconds is waited out")
ok(screen(failing: Rules.fetchWaits.count, status: nil).fetched, "so is a lift with no signal, up to the last wait")
ok(!screen(failing: Rules.fetchWaits.count + 1, status: nil).fetched, "longer than that, the collector takes over")
ok(!screen(failing: 1, status: 404).fetched, "and a job the server does not know is handed over at once")

// MARK: a generation stopped part way

ok(Rules.afterStop(.student) == .delete, "the student's Cancel stops the cloud job and forgets it, as asked")
ok(Rules.afterStop(.system) == .handOver,
   "the system stopping the work leaves the job to finish, for the collector")
// the expiration handler cannot tell the system from the student's Stop on
// the progress indicator, which is shown only while the app is away
ok(Rules.stopAtExpiry(appActive: true) == .system, "an expiry on screen is the system's: the job is kept")
ok(Rules.stopAtExpiry(appActive: false) == .student,
   "an expiry while away may be the student's Stop on the progress indicator, and is honoured as one")
ok(Rules.afterStop(Rules.stopAtExpiry(appActive: false)) == .delete,
   "so a set stopped from the indicator is not written on and put in the library")

// MARK: what the student is told

let told = Rules.handedOverMessage("Your 40 questions")
ok(told.hasPrefix("Your 40 questions"), "the message names what was written: \(told)")
ok(told.contains("Nothing is lost"), "says nothing is lost")
ok(told.contains("library"), "and where it will be")
ok(!told.lowercased().contains("error"), "without calling it an error")

print(failures == 0 ? "\nALL CLOUD JOB RETRY TESTS PASS" : "\n\(failures) CLOUD JOB RETRY TEST FAILURE(S)")
exit(failures == 0 ? 0 : 1)
