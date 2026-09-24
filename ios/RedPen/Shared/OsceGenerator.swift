import Foundation
#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
import FoundationModels
#endif

/// Writing OSCE stations from a lecture or a mark sheet, on the device.
///
/// The web version of Red Pen built checklists by reading a mark sheet; here
/// the same job is done from whatever the student imported - a skills lecture,
/// a station handout, a set of notes - because that is what they actually have
/// on a phone the night before.
///
/// Shaped like MCQGenerator on purpose: same availability reasons in the same
/// words, same cancellation, same refusal to return nonsense rather than
/// returning something. What differs is the bar for keeping an answer, which
/// lives in OsceStations and is tested without a model.
enum OsceGenerator {

    static let maxStationsPerCall = 2
    static let maxStationsTotal = 1_000
    static let maxPromptChars = 12_000

    /// Whether generating is possible at all, in the words the student needs.
    /// Deferred to MCQGenerator so there is one answer to this question in the
    /// app rather than two that can drift apart.
    static var availability: MCQGenerator.Availability { MCQGenerator.availability }

    enum Trouble: LocalizedError {
        case unavailable(String)
        case nothingUsable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .nothingUsable:
                return "Nothing in that source reads like a station. A skills lecture or a mark sheet works best \u{2014} a slide deck of facts usually has no procedure in it."
            case .cancelled: return nil
            }
        }
    }

    /// The prompt lives in OsceStations, with its tests.
    static func prompt(sourceText: String, count: Int, subject: String,
                       alreadyWritten: [String]) -> String {
        OsceStations.prompt(sourceText: sourceText, count: count,
                            subject: subject, alreadyWritten: alreadyWritten)
    }

    static func generate(
        sourceText: String, count: Int, subject: String,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [OsceChecklist] {
        #if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
        guard #available(iOS 26.0, *) else {
            throw Trouble.unavailable("Writing stations needs iOS 26 or later.")
        }
        guard availability.isAvailable else {
            if case .unavailable(let reason) = availability { throw Trouble.unavailable(reason) }
            throw Trouble.unavailable("On-device generation isn't available right now.")
        }

        let wanted = min(count, maxStationsTotal)
        let promptSource = String(sourceText.prefix(maxPromptChars))
        var collected: [OsceChecklist] = []
        var titles: [String] = []
        var consecutiveFailures = 0

        // Asked for a couple at a time: a station is long, and one request for
        // ten of them reliably returns ten thin ones.
        while collected.count < wanted && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let callCount = min(maxStationsPerCall, wanted - collected.count)
            onProgress(collected.count, wanted)

            let instructions = prompt(sourceText: promptSource, count: callCount,
                                      subject: subject, alreadyWritten: titles)
            let session = LanguageModelSession(instructions: Instructions { instructions })
            do {
                let response = try await session.respond(
                    to: "Write the \(callCount) station\(callCount == 1 ? "" : "s") now.",
                    generating: GeneratedStations.self)
                let tidied = OsceStations.tidy(response.content.stations.map {
                    OsceChecklist(title: $0.title, steps: $0.steps)
                })
                var kept = 0
                for station in tidied {
                    guard !titles.contains(where: {
                        $0.compare(station.title, options: .caseInsensitive) == .orderedSame
                    }) else { continue }
                    collected.append(station)
                    titles.append(station.title)
                    kept += 1
                    if collected.count >= wanted { break }
                }
                consecutiveFailures = kept == 0 ? consecutiveFailures + 1 : 0
            } catch is CancellationError {
                throw Trouble.cancelled
            } catch {
                consecutiveFailures += 1
            }
        }

        guard !collected.isEmpty else { throw Trouble.nothingUsable }
        return Array(collected.prefix(wanted))
        #else
        throw Trouble.unavailable("Writing stations isn't available in this build.")
        #endif
    }
}

#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
@available(iOS 26.0, *)
@Generable
struct GeneratedStations {
    @Guide(description: "The OSCE station checklists.")
    var stations: [GeneratedStation]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedStation {
    @Guide(description: "What the station is, as an examiner would name it. For example: Cardiovascular examination.")
    var title: String
    @Guide(description: "The steps, in the order they are performed. Each one thing the candidate does or says, under 20 words, not numbered.")
    var steps: [String]
}
#endif
