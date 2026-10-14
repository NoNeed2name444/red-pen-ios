import Foundation
#if canImport(LocalLLMClientLlama)
import LocalLLMClient
import LocalLLMClientLlama
#endif

/// One case from the downloaded Gemma model, for a device that cannot run
/// Apple's: the same instructions with the JSON shape added, since a plain
/// llama.cpp model has no schema to fill (as GemmaGenerate does for MCQs).
extension GemmaModel {
    /// The raw reply; CaseWriting.parse reads it.
    func writeCase(instructions: String) async throws -> String {
        #if canImport(LocalLLMClientLlama)
        guard Self.isDownloaded else { throw GenerationError.notDownloaded }
        let llm = try await loadedClient()
        let input = LLMInput.chat([
            .system(instructions),
            .user(CaseWriting.requestJSON),
        ])
        var text = ""
        for try await chunk in try await llm.textStream(from: input) {
            try Task.checkCancellation()
            text += chunk
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.emptyCompletion
        }
        return text
        #else
        throw GenerationError.notDownloaded
        #endif
    }
}
