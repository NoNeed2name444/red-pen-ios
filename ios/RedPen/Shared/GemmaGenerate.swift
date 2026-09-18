import Foundation
import LocalLLMClient
import LocalLLMClientLlama
import UIKit

/// Writing questions with the downloaded model.
///
/// Same rules and same batching as the Apple path - MCQPrompt is shared - with
/// one difference: a plain llama.cpp model has no `@Generable`, so it is asked
/// for JSON and the JSON is parsed by hand, the way the web app's generator
/// did before this app existed.
extension GemmaModel {

    enum GenerationError: LocalizedError {
        case notDownloaded
        case emptyCompletion
        case cancelled
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .notDownloaded: return "The offline model hasn't been downloaded yet."
            case .emptyCompletion: return "Couldn't get anything usable from that \u{2014} try again or shorten the text."
            case .cancelled: return ""
            case .underlying(let message): return "Something went wrong \u{2014} \(message)"
            }
        }
    }

    func loadedClient() async throws -> LlamaClient {
        if let client { return client }
        let loaded = try await LocalLLMClient.llama(
            url: Self.localURL,
            mmprojURL: Self.mmprojLocalURL,
            parameter: .init(context: 4096, temperature: 0.7, topK: 40, topP: 0.9))
        client = loaded
        return loaded
    }

    /// Questions in batches, each batch told what the earlier ones already
    /// asked.
    ///
    /// Without that, every batch independently reaches for the most obvious
    /// facts in the source and a long set becomes the same handful of questions
    /// written over and over. A batch that survives the filter empty counts as
    /// a failure, which is what ends the loop when the source has genuinely
    /// nothing left to ask about.
    func generate(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] {
        guard Self.isDownloaded else { throw GenerationError.notDownloaded }
        let llm = try await loadedClient()
        let promptSource = String(sourceText.prefix(MCQGenerator.maxPromptChars))
        var collected: [MCQQuestion] = []
        var asked: [MCQCoverage.Asked] = []
        var consecutiveFailures = 0

        while collected.count < count && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let callCount = min(MCQGenerator.maxQuestionsPerCall, count - collected.count)
            onProgress(collected.count, count)

            let instructions = MCQGenerator.buildPrompt(
                sourceText: promptSource, count: callCount, subject: subject,
                highYield: highYield, requestJSONShape: true, alreadyAsked: asked)
            do {
                let input = LLMInput.chat([
                    .system(instructions),
                    .user("Write the \(callCount) questions now, as JSON only."),
                ])
                var text = ""
                for try await chunk in try await llm.textStream(from: input) {
                    try Task.checkCancellation()
                    text += chunk
                }
                var kept = 0
                for question in Self.parseQuestions(from: text) {
                    let key = question.options[question.correctIndex]
                    guard !MCQCoverage.isRepeat(stem: question.stem, key: key, of: asked)
                    else { continue }
                    collected.append(question)
                    asked.append(MCQCoverage.Asked(stem: question.stem, key: key))
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
    }

    /// Real image understanding through llama.cpp's multimodal layer and the
    /// projector downloaded beside the text model - on-device, no network call.
    /// Apple's FoundationModels path takes no image input at all, so this is
    /// the Gemma backend's alone.
    func understandImage(_ image: UIImage, question: String) async throws -> String {
        guard Self.isDownloaded else { throw GenerationError.notDownloaded }
        let llm = try await loadedClient()
        let input = LLMInput.chat([.user(question, attachments: [.image(image)])])
        var text = ""
        for try await chunk in try await llm.textStream(from: input) {
            try Task.checkCancellation()
            text += chunk
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.emptyCompletion
        }
        return text
    }

    /// A small model asked for JSON sometimes wraps it in a code fence anyway,
    /// or adds a sentence either side, so everything outside the outermost
    /// braces is dropped before decoding.
    static func parseQuestions(from raw: String) -> [MCQQuestion] {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              start < end else { return [] }
        guard let data = raw[start...end].data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawQuestionSet.self, from: data)
        else { return [] }
        return decoded.questions.filter {
            MCQGenerator.isValidQuestion(stem: $0.stem, options: $0.options,
                                         correctIndex: $0.correctIndex)
        }.map {
            MCQQuestion(stem: $0.stem, options: $0.options,
                        correctIndex: $0.correctIndex, explanation: $0.explanation)
        }
    }

    struct RawQuestionSet: Decodable { var questions: [RawQuestion] }
    struct RawQuestion: Decodable {
        var stem: String
        var options: [String]
        var correctIndex: Int
        var explanation: String
    }
}
