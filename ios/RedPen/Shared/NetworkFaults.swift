import Foundation

// What the app does with each way a request can fail - a 500, a 429, a
// timeout, an answer it cannot read, no network (plan Task 5c step 4). Kept
// apart from the URLSession calls so FaultTests can feed it every fault on
// Linux. Closed means Unverified or queued with a reason, never a frozen
// screen or a silent drop.

/// An accuracy batch's outcome, from the server's status (nil: no answer at
/// all - offline or timed out) and its reply's limit and message.
enum AccuracySendOutcome: Equatable {
    case done, dayUsed, notPro(String), offline

    static func of(status: Int?, limit: String?, message: String?) -> AccuracySendOutcome {
        guard let status else { return .offline }
        if status == 402 { return .notPro(message ?? "The accuracy check is part of Pro.") }
        if status == 401 { return .notPro("Sign in again to check accuracy.") }
        if status == 429 || limit == "day" { return .dayUsed }
        // anything else that is not a 200 is kept for the next try
        return status == 200 ? .done : .offline
    }

    /// Whether the reply should be written to the ledger (a refusal says
    /// nothing about the items).
    var records: Bool {
        if case .notPro = self { return false }
        return true
    }
}

/// One cloud transcription attempt's next step, from the server's status.
enum TranscribeStep: Equatable {
    enum Stop: Equatable { case signIn, needsPro, busy(String), notSetUp, failed(String) }
    /// a 200: read the phrases
    case read
    /// a server hiccup: try once more after `pause` seconds
    case retry(String, pause: Double)
    case stop(Stop)

    static func of(code: Int, message: String?, attempt: Int) -> TranscribeStep {
        switch code {
        case 200: return .read
        case 401: return .stop(.signIn)
        case 402: return .stop(.needsPro)
        case 429: return .stop(.busy(message ?? "Cloud transcription is busy. Try again later, or transcribe on this phone."))
        case 404, 410, 503: return .stop(.notSetUp)
        case 500...599: return .retry(message ?? "The server couldn't transcribe that (\(code)).", pause: attempt == 0 ? 3 : 0)
        default: return .stop(.failed(message ?? "The server couldn't transcribe that (\(code))."))
        }
    }
}
