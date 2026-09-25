import Foundation

/// What becomes of a cloud job this device is still waiting for.
///
/// Pure, and apart from the collector that acts on it, because every wrong
/// answer here is a paid generation thrown away: a job taken for gone while
/// the phone was merely offline, or asked about with the wrong account's
/// session and so "not found", was deleted after a week with its finished
/// set still waiting on the server.
enum CloudJobRules {

    /// How asking the server about a job ended.
    enum Answer: Equatable {
        /// It answered, with the job's status.
        case status(String)
        /// It said it has no such job.
        case gone
        /// No answer worth acting on: no signal, a server error, too many
        /// requests, a session that ran out. None of these says anything
        /// about the job.
        case unreachable
    }

    /// What a failed status request means. Only the server saying "no such
    /// job" (404) is taken for gone.
    static func answer(forFailedStatus code: Int?) -> Answer {
        code == 404 ? .gone : .unreachable
    }

    /// The server keeps a finished job for a week (server/jobs.js keepDays);
    /// one gone for longer than this was collected or has expired.
    static let goneAfter: TimeInterval = 8 * 86_400
    /// A job made under an identity this device can no longer ask with (an
    /// account since signed out of) is kept this long, in case it comes back.
    static let unreachableAfter: TimeInterval = 30 * 86_400

    /// Whether this device lets go of its record of a job.
    ///
    /// `reachable`: whether this device can still ask as the identity the job
    /// was made under. Asking as anyone else always finds nothing.
    static func letGo(started: Date, answer: Answer, reachable: Bool, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(started)
        guard reachable else { return age > unreachableAfter }
        return answer == .gone && age > goneAfter
    }
}
