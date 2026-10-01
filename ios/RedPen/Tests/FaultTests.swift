// Fault injection on the app's side (plan Task 5c step 4): what an accuracy
// batch and a cloud transcription chunk do with a 500, a 429, a timeout, an
// answer that cannot be read, and no network. Closed means queued or
// Unverified with a reason - never a frozen screen or a silent drop.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: - The accuracy check

let offline = AccuracySendOutcome.of(status: nil, limit: nil, message: nil)
check("offline or timed out: queued for the next try", offline == .offline)
check("a 500: queued", AccuracySendOutcome.of(status: 500, limit: nil, message: "internal") == .offline)
check("a 502 or 504 from the Worker: queued",
      [502, 503, 504].allSatisfy { AccuracySendOutcome.of(status: $0, limit: nil, message: nil) == .offline })
check("a 429: today's checks are used", AccuracySendOutcome.of(status: 429, limit: nil, message: nil) == .dayUsed)
check("a 200 that says the day is used: the same",
      AccuracySendOutcome.of(status: 200, limit: "day", message: nil) == .dayUsed)
check("a 200 with an answer that cannot be read: done, and the items stay unchecked (Unverified)",
      AccuracySendOutcome.of(status: 200, limit: nil, message: nil) == .done)
check("a 402: not Pro, with the server's words",
      AccuracySendOutcome.of(status: 402, limit: nil, message: "Pro only.") == .notPro("Pro only."))
check("a 402 with no words: the app's own", {
    if case .notPro(let why) = AccuracySendOutcome.of(status: 402, limit: nil, message: nil) { return !why.isEmpty }
    return false
}())
check("a 401: sign in again", {
    if case .notPro(let why) = AccuracySendOutcome.of(status: 401, limit: nil, message: nil) { return why.contains("Sign in") }
    return false
}())
check("a 200 that says busy (nobody checked): wait, not done",
      AccuracySendOutcome.of(status: 200, limit: nil, message: nil, busy: true) == .busy)
check("busy only counts with a 200: a 500 is still queued",
      AccuracySendOutcome.of(status: 500, limit: nil, message: nil, busy: true) == .offline)
check("a refusal is not written to the ledger", !AccuracySendOutcome.notPro("x").records)
check("every other outcome is", [AccuracySendOutcome.done, .dayUsed, .offline, .busy].allSatisfy(\.records))

// MARK: - Cloud transcription

check("a 200 is read", TranscribeStep.of(code: 200, message: nil, attempt: 0) == .read)
check("a 500 is tried once more, after a pause",
      TranscribeStep.of(code: 500, message: nil, attempt: 0) == .retry("The server couldn't transcribe that (500).", pause: 3))
check("...and with no pause on the last try", {
    if case .retry(_, let pause) = TranscribeStep.of(code: 502, message: nil, attempt: 1) { return pause == 0 }
    return false
}())
check("the Worker's timeout (504) is a hiccup too", {
    if case .retry = TranscribeStep.of(code: 504, message: "timed out", attempt: 0) { return true }
    return false
}())
check("a 429 stops with the server's words", TranscribeStep.of(code: 429, message: "Busy.", attempt: 0) == .stop(.busy("Busy.")))
check("a 429 with no words: the app's own, pointing at the phone", {
    if case .stop(.busy(let why)) = TranscribeStep.of(code: 429, message: nil, attempt: 0) { return why.contains("this phone") }
    return false
}())
check("a 503: not set up (no retry against a server that has no key)",
      TranscribeStep.of(code: 503, message: nil, attempt: 0) == .stop(.notSetUp))
check("404 and 410: not set up", [404, 410].allSatisfy { TranscribeStep.of(code: $0, message: nil, attempt: 0) == .stop(.notSetUp) })
check("a 401: sign in", TranscribeStep.of(code: 401, message: nil, attempt: 0) == .stop(.signIn))
check("a 402: Pro", TranscribeStep.of(code: 402, message: nil, attempt: 0) == .stop(.needsPro))
check("no HTTP answer at all (code 0): a stop with a reason, not a retry loop", {
    if case .stop(.failed(let why)) = TranscribeStep.of(code: 0, message: nil, attempt: 0) { return !why.isEmpty }
    return false
}())
check("an unexpected 4xx: stops with the server's words",
      TranscribeStep.of(code: 413, message: "Too large.", attempt: 0) == .stop(.failed("Too large.")))

print(failures.isEmpty ? "\nALL FAULT TESTS PASS" : "\n\(failures.count) FAULT TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
