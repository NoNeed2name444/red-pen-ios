import Foundation

/// What writing OSCE stations from a lecture or a mark sheet shares: how many
/// a call and a set may hold, the prompt (in OsceStations, with its tests) and
/// the words for a source with no station in it. The stations themselves are
/// written by the writer route only (MedicalGenerate; the owner, 23 Oct: "Lock
/// it"), never on the phone. The bar for keeping a station lives in
/// OsceStations and is tested without a model.
enum OsceGenerator {

    static let maxStationsPerCall = 2
    static let maxStationsTotal = 1_000
    /// The source a small-window writer is given at a time (audit #85: 12,000
    /// characters overflowed a 4,096-token window); a long lecture is read a
    /// window at a time.
    static let maxPromptChars = 4_000

    enum Trouble: LocalizedError {
        case nothingUsable

        var errorDescription: String? {
            switch self {
            case .nothingUsable:
                return "Nothing in that source reads like a station. A skills lecture or a mark sheet works best \u{2014} a slide deck of facts usually has no procedure in it."
            }
        }
    }

    /// The prompt lives in OsceStations, with its tests.
    static func prompt(sourceText: String, count: Int, subject: String,
                       alreadyWritten: [String]) -> String {
        OsceStations.prompt(sourceText: sourceText, count: count,
                            subject: subject, alreadyWritten: alreadyWritten)
    }
}
