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

    // MARK: fetching a finished job's result

    /// What to do after a request for a finished job's result has failed.
    enum Retry: Equatable {
        /// Ask again after this many seconds, the screen still waiting.
        case after(TimeInterval)
        /// Stop asking from the screen. The job is handed to the collector,
        /// which asks again every minute while the app is open and at every
        /// launch, and makes the set; it is never forgotten here.
        case handOver
    }

    /// The waits between tries while the screen waits: about two minutes
    /// in all, for a signal that drops in a lift or a server that blinks.
    static let fetchWaits: [TimeInterval] = [2, 4, 8, 15, 30, 30, 30]

    /// `failed`: how many tries have failed so far (1 after the first).
    /// `status`: the HTTP status the failure came with; nil for no answer at
    /// all (no signal, a timeout) or one that could not be read.
    ///
    /// The job was finished when this was asked, so a failure here never
    /// means the set is gone: at worst it is collected later.
    static func afterFailedFetch(failed: Int, status: Int?) -> Retry {
        // Answers that asking again in a few seconds cannot change: no such
        // job (404), or a session that does not open it (401, 403), which the
        // next launch's sign-in may.
        if let status, status == 401 || status == 403 || status == 404 { return .handOver }
        guard failed >= 1, failed <= fetchWaits.count else { return .handOver }
        return .after(fetchWaits[failed - 1])
    }

    // MARK: a generation stopped part way

    /// Who stopped the generation a job was running under.
    enum Stop: Equatable {
        /// The student: Cancel on the card, or closing the screen that
        /// started it.
        case student
        /// The system, ending the app's time in the background. The student
        /// did not ask, and the server is still writing.
        case system
    }

    /// What becomes of the job when its generation is stopped.
    enum StopFate: Equatable {
        /// Stopped on the server and forgotten here, as the student asked.
        case delete
        /// Left to finish on the server and handed to the collector, which
        /// makes the set: work nobody asked to stop is never thrown away.
        case handOver
    }

    static func afterStop(_ stop: Stop) -> StopFate {
        stop == .system ? .handOver : .delete
    }

    /// What the student is told when the screen stops waiting for a finished
    /// job's result. `what`: "Your 40 questions" (CloudJobs.Pending.what).
    static func handedOverMessage(_ what: String) -> String {
        what + " finished in the cloud but could not be downloaded yet. Nothing is lost: the set will be in your library as soon as the cloud can be reached."
    }
}
