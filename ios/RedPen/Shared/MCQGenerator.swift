import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates an MCQ set on-device with Apple's Foundation Models
/// (Apple Intelligence) — the native counterpart to the web app's
/// `buildPrompt()` + `generateQuestionBatch()` (see red-pen-content.html).
///
/// The prompt text, the "single best answer" rules, the length-parity
/// backstop and the batching strategy below are carried over line-for-line
/// from the web app's generator. The one deliberate difference is *how* the
/// model's answer is produced: the web app asks Claude (billed to the
/// viewer's own account, via the artifact's `sample()` capability) to reply
/// with raw JSON it then parses by hand. This asks Apple's on-device model
/// — bundled with iOS, running locally, free, with no account or API key —
/// for a `@Generable` struct directly, so there's no JSON-parsing step and
/// nothing here ever touches anyone's Claude usage.
enum MCQGenerator {
    // MARK: constants (ported from the web app's setup-form limits)

    /// How much of the pasted source text is actually sent per generation
    /// call — matches the web app's MAX_PROMPT_CHARS.
    static let maxPromptChars = 45_000

    /// The web app asks Claude for up to 20 questions per call
    /// (MAX_QUESTIONS_PER_CALL) and loops for more. The on-device model is
    /// much smaller and slower per token, so a batch that big risks running
    /// long or losing the plot partway through — this keeps each call to a
    /// size the on-device model can reliably finish.
    static let maxQuestionsPerCall = 6

    /// The web app allows up to 10,000 questions in one set (mostly so the
    /// number field never blocks a power user). On-device generation is
    /// local but not instant — a few seconds per batch of six — so this
    /// caps a single set at something that finishes in a reasonable time
    /// on a phone rather than pretending the two are equivalent.
    static let maxQuestionsTotal = 60

    // MARK: availability (the native equivalent of the web app's "not_granted" /
    // "sampling_disabled" errorCopy cases — there, whether the *viewer* has
    // granted Claude access; here, whether *this device* has Apple
    // Intelligence turned on at all)

    enum Availability: Equatable {
        case available
        case unavailable(String)

        var isAvailable: Bool { self == .available }
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This device doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in Settings ▸ Apple Intelligence & Siri to generate questions on this device.")
                case .modelNotReady:
                    return .unavailable("The on-device model is still downloading — try again shortly.")
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

    // MARK: errors (the native equivalent of the web app's errorCopy())

    enum GenerationError: LocalizedError {
        case unavailable(String)
        case emptyCompletion
        case cancelled
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .emptyCompletion: return "Couldn't get anything usable from that — try again or shorten the text."
            case .cancelled: return ""
            case .underlying(let message): return "Something went wrong — \(message)"
            }
        }
    }

    // MARK: the prompt itself — ported from the web app's buildPrompt()

    /// Builds the instructions sent to the model for one batch of `count`
    /// questions. Word-for-word the same rules the web app's Claude prompt
    /// uses (minus the image-anchoring branch, which the on-device model
    /// doesn't take image input for, and minus the trailing "reply with
    /// only this JSON shape" instruction, which `@Generable` makes moot —
    /// the framework guarantees the shape instead of asking nicely for it).
    static func buildPrompt(sourceText: String, count: Int, subject: String, highYield: Bool) -> String {
        var lines: [String] = [
            "You are writing single-best-answer multiple-choice questions for a medical student's internal medicine exam revision, in the NBME/USMLE \"one-best-answer\" style.",
            "",
        ]
        if !sourceText.isEmpty {
            lines.append("SOURCE MATERIAL (the student's own notes — use ONLY facts found in it):")
            lines.append("\"\"\"")
            lines.append(sourceText)
            lines.append("\"\"\"")
            lines.append("")
        }
        if !subject.isEmpty && subject != "General" {
            lines.append("Topic to focus on: \"\(subject)\". Every question in this set must specifically test this topic" +
                (sourceText.isEmpty ? "" : " — draw only on the parts of the source material relevant to it, and ignore parts of the source that aren't") +
                ". Interpret the topic as written (it may name a disease, a drug or drug class, a mechanism, a lab test, an exam theme, or anything else) and build the whole set around it rather than around the source material's overall subject.")
            lines.append("A topic being given does not mean a narrow set: aim for COMPREHENSIVE coverage of that topic. Identify every distinct fact, mechanism, subtype, complication, diagnostic criterion, or exam angle the source material offers on it — not just the first or most obvious one — and spread the \(count) questions across all of them in rough proportion to how much the source covers each, rather than writing several questions that circle back to the same one or two facts.")
            lines.append("")
        } else {
            lines.append("No specific topic was given, so aim for comprehensive coverage" +
                (!sourceText.isEmpty
                    ? " of the source material: identify every distinct medically-relevant fact, concept, finding, or topic it contains — not just the first or most prominent one — and make sure the set as a whole tests across all of them, in rough proportion to how much of the source each one occupies, rather than repeatedly circling back to a handful of favorites. Skip only content with no medical relevance (e.g. citations, formatting, or administrative text)."
                    : " — write a well-rounded general set") + ".")
            lines.append("")
        }
        lines.append("Write exactly \(count) multiple-choice questions. Follow these rules strictly:")
        lines.append("1. Each question has exactly 5 options. Do not prefix options with letters or numbers — just the option text.")
        lines.append("2. SINGLE BEST ANSWER format: more than one option may be defensible or partially true, but exactly one option must clearly be the BEST answer given the full picture. Every distractor must be the SAME kind of answer as the best one and genuinely in contention — if the best answer is a diagnosis, all 5 must be diagnoses from the same differential; if it's a drug, all 5 must be drugs a clinician would realistically consider here; if it's a lab value or number, all 5 must be plausible values in the same range. Never include an option that's a different category of answer, off-topic, or eliminable on sight — that's the single biggest tell students report, worse even than length. Draw distractors from closely related diagnoses or conditions in the same category, the correct action taken at the wrong stage of workup or management, a classic mix-up (a drug from the same class with a different indication/side-effect/mechanism, a similar-sounding eponym or criterion, a lab value just outside the diagnostic threshold), or the specific wrong answer students most commonly pick in practice. A student should need real, specific knowledge to eliminate each distractor — if you can imagine a student ruling one out without knowing the topic, rewrite it to be more specific and more plausible.")
        lines.append("3. Never use \"all of the above\" or \"none of the above\".")
        lines.append("4. CRITICAL — length is the other giveaway students report (\"the longest option is always right\"), and it's not fixed by randomizing option order, since the length travels with the answer text itself: write the best answer in its natural, complete form, then write each of the 4 distractors to that SAME level of clinical specificity and length — within about 2-3 words of it and of each other. If a distractor is coming out shorter, add real clinical detail (a mechanism, a qualifier, a specific value) to lengthen it, never vague filler; if the best answer is coming out longer, tighten the wording rather than dropping the detail that makes it correct. Before you finalize each question, look at your own 5 options as a student would: is one option noticeably longer, more hedged, or more specific than the rest? If so, rewrite until none of them stand out — a student must not be able to shortcut the question by picking the longest, most detailed-sounding option.")
        lines.append("5. Vary the question style across the set, and deliberately mix two kinds of difficulty: (a) reasoning/application questions — brief clinical vignettes (age/sex/presentation/findings) and \"best next step / most likely diagnosis / most specific finding\" questions that require synthesizing several findings, and (b) pure memorization questions that test one specific fact, number, definition, classification, criterion, mechanism, or eponym directly, answerable only by having actually memorized it — no vignette or context clues to reason from. At least one in five questions in the set should be this recall-only style.")
        lines.append("6. In the explanation for each question: state why the best answer is best, and explicitly address at least one other option that is tempting or partially correct, explaining why it falls short of best. Never refer to options by a letter or position (\"option A\", \"the first choice\") — the order they're shown in is randomized after you write them, so a letter reference would be wrong. Refer to each option by its actual content instead (e.g. \"metformin\" or \"the biopsy finding of...\").")
        lines.append("7. Every question must be answerable from the source material above — never invent facts outside it.")
        if highYield { lines.append("8. Favor the highest-yield, most exam-relevant facts in the source material.") }
        return lines.joined(separator: "\n")
    }

    /// Same backstop the web app applies after generation (`lengthBalanced`):
    /// rejects a question if its best answer is both the single longest
    /// option and meaningfully longer than the distractors' average, so
    /// "pick the longest option" stays a losing strategy even when the
    /// model didn't follow the length-parity rule closely.
    private static func lengthBalanced(_ options: [String], correctIndex: Int) -> Bool {
        let lens = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard lens.indices.contains(correctIndex) else { return false }
        let correctLen = lens[correctIndex]
        let others = lens.enumerated().filter { $0.offset != correctIndex }.map(\.element)
        guard !others.isEmpty else { return false }
        let maxOther = others.max() ?? 0
        let avgOther = Double(others.reduce(0, +)) / Double(others.count)
        return !(correctLen > maxOther && Double(correctLen) > avgOther * 1.3)
    }

    private static func isValid(_ q: GeneratedQuestion) -> Bool {
        q.options.count == 5 && (0...4).contains(q.correctIndex) &&
            !q.stem.trimmingCharacters(in: .whitespaces).isEmpty &&
            lengthBalanced(q.options, correctIndex: q.correctIndex)
    }

    // MARK: generation

    /// Generates up to `count` questions, looping on-device model calls of
    /// at most `maxQuestionsPerCall` each — the same batching shape as the
    /// web app's `generateQuestionBatch()`. `onProgress` is called before
    /// each call so a caller can show "N of total written…"; the task can
    /// be cancelled between batches (SwiftUI cancels the enclosing `Task`
    /// when the generating screen goes away).
    static func generate(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw GenerationError.unavailable("Generating questions needs iOS 26 or later.") }
        guard availability.isAvailable else {
            if case .unavailable(let reason) = availability { throw GenerationError.unavailable(reason) }
            throw GenerationError.unavailable("On-device generation isn't available right now.")
        }
        let promptSource = String(sourceText.prefix(maxPromptChars))
        var collected: [MCQQuestion] = []
        var consecutiveFailures = 0

        while collected.count < count && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let remaining = count - collected.count
            let callCount = min(maxQuestionsPerCall, remaining)
            onProgress(collected.count, count)

            let instructionsText = buildPrompt(sourceText: promptSource, count: callCount, subject: subject, highYield: highYield)
            let session = LanguageModelSession(instructions: Instructions {
                instructionsText
            })
            do {
                let response = try await session.respond(
                    to: "Write the \(callCount) questions now.",
                    generating: GeneratedQuestionSet.self
                )
                let batch = response.content.questions.filter(isValid).map { gq -> MCQQuestion in
                    MCQQuestion(stem: gq.stem, options: gq.options, correctIndex: gq.correctIndex, explanation: gq.explanation)
                }
                if batch.isEmpty {
                    consecutiveFailures += 1
                } else {
                    collected.append(contentsOf: batch)
                    consecutiveFailures = 0
                }
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

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedQuestion {
    @Guide(description: "The question stem — a clinical vignette or a direct recall question, ending the way an exam question would.")
    var stem: String
    @Guide(description: "Exactly five answer options, in plain text with no letter or number prefix.")
    var options: [String]
    @Guide(description: "The zero-based index (0 to 4) into options of the single best answer.")
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
