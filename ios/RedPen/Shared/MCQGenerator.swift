import Foundation
#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
import FoundationModels
#endif

/// Generates an MCQ set on-device with Apple's Foundation Models (Apple
/// Intelligence). On a device that cannot run Apple's model at all - anything
/// older than iPhone 15 Pro, or Apple Intelligence turned off - GemmaModel is
/// the fallback: same prompt rules (MCQPrompt is shared by both), a downloaded
/// Gemma 4 E2B instead of Apple's, still entirely on-device and free.
///
/// Nothing here touches anyone's account. The web app asked Claude and billed
/// the viewer; this asks the phone.
enum MCQGenerator {

    /// Questions per model call. Apple's on-device model is small and slow per
    /// token, so a batch much bigger than this starts losing the plot partway
    /// through and returns half a question.
    static let maxQuestionsPerCall = 6

    /// No real ceiling: a student may ask for as many as they like from one
    /// source, and generation runs in batches that each avoid what came before.
    /// The number only stops a typo of extra zeros from running for a week.
    static let maxQuestionsTotal = 10_000

    // MARK: availability

    enum Availability: Equatable {
        case available
        case unavailable(String)
        var isAvailable: Bool { self == .available }
    }

    static var availability: Availability {
        #if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This device doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in Settings \u{25B8} Apple Intelligence & Siri to generate questions on this device.")
                case .modelNotReady:
                    return .unavailable("The on-device model is still downloading \u{2014} try again shortly.")
                @unknown default:
                    return .unavailable("On-device generation isn't available right now.")
                }
            @unknown default:
                return .unavailable("On-device generation isn't available right now.")
            }
        } else {
            return .unavailable("Generating questions needs iOS 26 or later.")
        }
        #else
        return .unavailable("Generating questions isn't available in this build.")
        #endif
    }

    enum GenerationError: LocalizedError {
        case unavailable(String)
        case emptyCompletion
        case cancelled
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .emptyCompletion: return "Couldn't get anything usable from that \u{2014} try again or shorten the text."
            case .cancelled: return ""
            case .underlying(let message): return "Something went wrong \u{2014} \(message)"
            }
        }
    }

    // MARK: what makes a question acceptable

    /// The backstop behind rule 4 of the prompt: reject a question whose best
    /// answer is both the single longest option and meaningfully longer than
    /// the rest, so "pick the longest" stays a losing strategy even when the
    /// model ignored the instruction.
    static func lengthBalanced(_ options: [String], correctIndex: Int) -> Bool {
        let lens = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard lens.indices.contains(correctIndex) else { return false }
        let correctLen = lens[correctIndex]
        let others = lens.enumerated().filter { $0.offset != correctIndex }.map(\.element)
        guard !others.isEmpty else { return false }
        let maxOther = others.max() ?? 0
        let avgOther = Double(others.reduce(0, +)) / Double(others.count)
        return !(correctLen > maxOther && Double(correctLen) > avgOther * 1.3)
    }

    /// Shared by both backends: Apple's `@Generable` result and Gemma's
    /// hand-parsed JSON funnel through this same check. Four options are as
    /// good as five: NEET-PG, FMGE, SMLE and the Gulf exams use four
    /// (ExamCatalog), and the prompt asks for the chosen exam's count.
    static func isValidQuestion(stem: String, options: [String], correctIndex: Int) -> Bool {
        (4...5).contains(options.count) && options.indices.contains(correctIndex) &&
            !stem.trimmingCharacters(in: .whitespaces).isEmpty &&
            lengthBalanced(options, correctIndex: correctIndex)
    }

    // MARK: generation

    /// Generates up to `count` questions in batches of at most
    /// `maxQuestionsPerCall`.
    ///
    /// Each batch is told what the earlier batches already asked, and anything
    /// that comes back testing a fact already collected is dropped. Without
    /// both, a long set is the same handful of obvious facts written over and
    /// over: every batch starts from the same source with no memory, so every
    /// batch reaches for the same thing.
    ///
    /// A batch that is entirely repeats counts as a failure, which is what
    /// stops the loop when the source genuinely has nothing left to ask about -
    /// a short lecture asked for eighty questions finishes with the forty it
    /// can support instead of forty duplicates.
    static func generate(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] {
        #if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
        guard #available(iOS 26.0, *) else {
            throw GenerationError.unavailable("Generating questions needs iOS 26 or later.")
        }
        guard availability.isAvailable else {
            if case .unavailable(let reason) = availability {
                throw GenerationError.unavailable(reason)
            }
            throw GenerationError.unavailable("On-device generation isn't available right now.")
        }
        let promptSource = String(sourceText.prefix(maxPromptChars))
        var collected: [MCQQuestion] = []
        var asked: [MCQCoverage.Asked] = []
        var consecutiveFailures = 0

        while collected.count < count && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let callCount = min(maxQuestionsPerCall, count - collected.count)
            onProgress(collected.count, count)

            // one exemplar, turned over each batch: Apple's model has a small window
            let instructionsText = buildPrompt(
                sourceText: promptSource, count: callCount, subject: subject,
                highYield: highYield, alreadyAsked: asked, exemplars: 1, round: asked.count)
            let session = LanguageModelSession(instructions: Instructions { instructionsText })
            do {
                let response = try await session.respond(
                    to: "Write the \(callCount) questions now.",
                    generating: GeneratedQuestionSet.self)
                var kept = 0
                for generated in response.content.questions {
                    guard isValidQuestion(stem: generated.stem, options: generated.options,
                                          correctIndex: generated.correctIndex) else { continue }
                    let key = generated.options[generated.correctIndex]
                    guard !MCQCoverage.isRepeat(stem: generated.stem, key: key, of: asked),
                          !ExamExemplars.copies(generated.stem)
                    else { continue }
                    collected.append(MCQQuestion(stem: generated.stem,
                                                 options: generated.options,
                                                 correctIndex: generated.correctIndex,
                                                 explanation: generated.explanation))
                    asked.append(MCQCoverage.Asked(stem: generated.stem, key: key))
                    kept += 1
                    if collected.count >= count { break }
                }
                consecutiveFailures = kept == 0 ? consecutiveFailures + 1 : 0
            } catch is CancellationError {
                throw GenerationError.cancelled
            } catch {
                consecutiveFailures += 1
            }
        }

        guard !collected.isEmpty else { throw GenerationError.emptyCompletion }
        return Array(collected.prefix(count))
        #else
        throw GenerationError.unavailable("Generating questions isn't available in this build.")
        #endif
    }
}

#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
@available(iOS 26.0, *)
@Generable
struct GeneratedQuestion {
    @Guide(description: "The question stem \u{2014} a clinical vignette or a direct recall question, ending the way an exam question would.")
    var stem: String
    @Guide(description: "The answer options - exactly as many as the instructions ask for (four or five) - in plain text with no letter or number prefix.")
    var options: [String]
    @Guide(description: "The zero-based index into options of the single best answer.")
    var correctIndex: Int
    @Guide(description: "Why the best answer is best, and why at least one other tempting option falls short.")
    var explanation: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedQuestionSet {
    var questions: [GeneratedQuestion]
}
#endif
