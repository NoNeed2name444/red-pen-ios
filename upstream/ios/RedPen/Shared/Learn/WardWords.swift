import Foundation

/// The few words the Ward Round home and the Vitals screen put around their
/// numbers: the exam countdown, the greeting, and where the readiness
/// estimate stands against the pass mark.
///
/// Calm by rule: a countdown never shouts, a standing below the pass mark is
/// "for now", and a name that is only a placeholder is not used as one.
///
/// Foundation only, so the wording is tested on Linux (BedPlanTests).
enum WardWords {

    /// What the countdown calls the exam when none is chosen: the owner's
    /// finals (docs/design/targets-2026-10-01.md §1).
    static let defaultExam = "Finals"

    /// "Finals in 23 days", "PLAB 1 tomorrow", "Finals today"; nil with no
    /// date, or once it has passed.
    static func countdown(days: Int?, exam: String? = nil) -> String? {
        guard let days, days >= 0 else { return nil }
        let given: String = (exam ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String = given.isEmpty ? defaultExam : given
        switch days {
        case 0: return "\(name) today"
        case 1: return "\(name) tomorrow"
        default: return "\(name) in \(days) days"
        }
    }

    /// "Good morning, Sam"; "Good evening" without a name.
    static func greeting(hour: Int, name: String? = nil) -> String {
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        default: part = "Good evening"
        }
        guard let first = firstName(name) else { return part }
        return part + ", " + first
    }

    /// The first word of a display name, when it is a name: not an email
    /// address, and not "Me", the app's own stand-in for a nameless account.
    static func firstName(_ display: String?) -> String? {
        let trimmed: String = (display ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("@"), trimmed.lowercased() != "me" else { return nil }
        let first: String = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        guard first.count <= 24 else { return nil }
        return first
    }

    /// Where a readiness estimate stands against the pass mark, in the words
    /// the readiness card uses: its whole range above, below, or across it.
    static func standing(low: Double, high: Double, passMark: Double) -> String {
        if low >= passMark { return "on track for a pass" }
        if high < passMark { return "below the pass mark for now" }
        return "around the pass mark"
    }

    /// "Finals in 23 days · on track for a pass": the countdown, with the
    /// standing when there is an estimate; nil with no countdown.
    static func vitalsLine(countdown: String?, standing: String?) -> String? {
        guard let countdown else { return nil }
        guard let standing, !standing.isEmpty else { return countdown }
        return countdown + " \u{00B7} " + standing
    }
}
