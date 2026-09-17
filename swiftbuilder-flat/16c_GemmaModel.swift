import Foundation
import LocalLLMClient
import LocalLLMClientLlama
import UIKit

/// The fallback MCQ-generation backend for devices that can't run Apple's
/// on-device model at all — anything older than iPhone 15 Pro, or a newer
/// phone with Apple Intelligence turned off in Settings. It downloads a
/// quantized Gemma 4 E2B checkpoint (Google's small "edge" model, ~2.8 GB
/// at 4-bit) plus its vision projector (~530 MB), then runs both fully
/// on-device through llama.cpp — same as the Apple path, this never
/// touches anyone's Claude account or any paid API, it's just a bigger
/// one-time download and a slower model.
///
/// Shares its prompt rules with MCQGenerator.buildPrompt(); the one real
/// difference is that a plain llama.cpp model has no `@Generable` — this
/// asks the model for JSON directly (`requestJSONShape: true`) and parses
/// it by hand, the same way the web app's Claude-backed generator did.
///
/// Audio input is NOT implemented here, on purpose rather than by
/// oversight: llama.cpp's own multimodal layer (mtmd) supports audio
/// (`mtmd_bitmap_init_from_audio`, `mtmd_support_audio`), but the
/// LocalLLMClient package this app depends on only wires that support up
/// to images at the Swift level — `LLMAttachment.Content` has just one
/// case, `.image`, and the encode/decode helpers around it are scoped
/// `package`, not `public`, so app code can't add an audio case from the
/// outside. Doing this for real would mean forking LocalLLMClient and
/// writing new C-interop bindings against mtmd's audio API — a much
/// bigger, unverified undertaking than the rest of this file, so it's
/// left undone rather than faked.
@MainActor
final class GemmaModel: ObservableObject {
    static let shared = GemmaModel()

    enum Status: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .notDownloaded

    /// The model card at ggml-org/gemma-4-E2B-it-GGUF (verified on
    /// Hugging Face) — Q4_0 is the smallest full-precision-tokenizer
    /// quantization it publishes, small enough to be a plausible phone
    /// download without giving up much quality.
    private static let downloadURL = URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf")!
    private static let filename = "gemma-4-E2B-it-Q4_0.gguf"
    /// For UI copy only — the file itself is the source of truth for
    /// whether a download finished (see `isDownloaded`).
    static let approxDownloadBytes: Int64 = 2_840_000_000

    /// The matching vision projector ("mmproj") for the same checkpoint,
    /// from the same model card — this is what turns on image
    /// understanding via llama.cpp's mtmd layer. Q8_0 (not the smaller
    /// text model's Q4_0) because ggml-org don't publish a Q4_0 mmproj
    /// for this card; verified present at this exact path on Hugging
    /// Face, ~530 MB by its real Content-Length.
    private static let mmprojDownloadURL = URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/mmproj-gemma-4-E2B-it-Q8_0.gguf")!
    private static let mmprojFilename = "mmproj-gemma-4-E2B-it-Q8_0.gguf"
    static let approxMmprojDownloadBytes: Int64 = 557_368_064
    /// For UI copy only — the two files' combined size.
    static var approxTotalDownloadBytes: Int64 { approxDownloadBytes + approxMmprojDownloadBytes }

    private static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models", isDirectory: true)
    }

    private static var localURL: URL {
        modelsDirectory.appendingPathComponent(filename)
    }

    private static var mmprojLocalURL: URL {
        modelsDirectory.appendingPathComponent(mmprojFilename)
    }

    private var downloadTask: Task<Void, Never>?
    /// The loaded llama.cpp client — expensive to create, so it's kept
    /// around for the lifetime of the app once generation has happened
    /// once, rather than reloaded on every batch. `LocalLLMClient` itself
    /// is just an empty namespace enum for the static factory methods
    /// (`LocalLLMClient.llama(...)`) — the actual client type it hands
    /// back is `LlamaClient`.
    private var client: LlamaClient?

    private init() {
        status = Self.isDownloaded ? .ready : .notDownloaded
    }

    private static func fileLooksComplete(at url: URL, approxSize: Int64) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        // A half-downloaded or corrupt file would otherwise look "ready" —
        // require at least 90% of the known file size before trusting it.
        return (size ?? 0) > Int64(Double(approxSize) * 0.9)
    }

    private static var isDownloaded: Bool {
        fileLooksComplete(at: localURL, approxSize: approxDownloadBytes)
            && fileLooksComplete(at: mmprojLocalURL, approxSize: approxMmprojDownloadBytes)
    }

    func refreshStatus() {
        if case .downloading = status { return } // don't clobber an in-flight download
        status = Self.isDownloaded ? .ready : .notDownloaded
    }

    func download() {
        guard downloadTask == nil else { return }
        status = .downloading(fraction: 0)
        downloadTask = Task {
            do {
                try FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
                let total = Double(Self.approxTotalDownloadBytes)
                let textWeight = Double(Self.approxDownloadBytes) / total
                let mmprojWeight = Double(Self.approxMmprojDownloadBytes) / total

                let textTmpURL = Self.modelsDirectory.appendingPathComponent(Self.filename + ".part")
                try await Self.download(from: Self.downloadURL, to: textTmpURL) { fraction in
                    Task { @MainActor in self.status = .downloading(fraction: fraction * textWeight) }
                }
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: Self.localURL.path) {
                    try FileManager.default.removeItem(at: Self.localURL)
                }
                try FileManager.default.moveItem(at: textTmpURL, to: Self.localURL)

                let mmprojTmpURL = Self.modelsDirectory.appendingPathComponent(Self.mmprojFilename + ".part")
                try await Self.download(from: Self.mmprojDownloadURL, to: mmprojTmpURL) { fraction in
                    Task { @MainActor in self.status = .downloading(fraction: textWeight + fraction * mmprojWeight) }
                }
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: Self.mmprojLocalURL.path) {
                    try FileManager.default.removeItem(at: Self.mmprojLocalURL)
                }
                try FileManager.default.moveItem(at: mmprojTmpURL, to: Self.mmprojLocalURL)

                await MainActor.run { self.status = .ready }
            } catch is CancellationError {
                await MainActor.run { self.status = Self.isDownloaded ? .ready : .notDownloaded }
            } catch {
                await MainActor.run { self.status = .failed(error.localizedDescription) }
            }
            await MainActor.run { self.downloadTask = nil }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteDownloadedModel() {
        cancelDownload()
        client = nil
        try? FileManager.default.removeItem(at: Self.localURL)
        try? FileManager.default.removeItem(at: Self.mmprojLocalURL)
        status = .notDownloaded
    }

    /// A plain `URLSession` download with progress — no third-party
    /// networking dependency, just the delegate-based API `URLSession`
    /// has always exposed for exactly this.
    private static func download(from url: URL, to destination: URL, onProgress: @escaping (Double) -> Void) async throws {
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let (tempFileURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GenerationError.underlying("Download failed (HTTP \(http.statusCode)).")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempFileURL, to: destination)
    }

    // MARK: generation — same batching/retry shape as MCQGenerator.generate()

    enum GenerationError: LocalizedError {
        case notDownloaded
        case emptyCompletion
        case cancelled
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .notDownloaded: return "The offline model hasn't been downloaded yet."
            case .emptyCompletion: return "Couldn't get anything usable from that — try again or shorten the text."
            case .cancelled: return ""
            case .underlying(let message): return "Something went wrong — \(message)"
            }
        }
    }

    private func loadedClient() async throws -> LlamaClient {
        if let client { return client }
        let loaded = try await LocalLLMClient.llama(
            url: Self.localURL,
            mmprojURL: Self.mmprojLocalURL,
            parameter: .init(context: 4096, temperature: 0.7, topK: 40, topP: 0.9)
        )
        client = loaded
        return loaded
    }

    func generate(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] {
        guard Self.isDownloaded else { throw GenerationError.notDownloaded }
        let llm = try await loadedClient()
        let promptSource = String(sourceText.prefix(MCQGenerator.maxPromptChars))
        var collected: [MCQQuestion] = []
        var consecutiveFailures = 0

        while collected.count < count && consecutiveFailures < 3 {
            try Task.checkCancellation()
            let remaining = count - collected.count
            let callCount = min(MCQGenerator.maxQuestionsPerCall, remaining)
            onProgress(collected.count, count)

            let instructions = MCQGenerator.buildPrompt(
                sourceText: promptSource, count: callCount, subject: subject, highYield: highYield,
                requestJSONShape: true
            )
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
                let batch = Self.parseQuestions(from: text)
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
    }

    /// Real image understanding, via llama.cpp's mtmd layer and the
    /// vision projector downloaded alongside the text model — genuinely
    /// on-device, no network call. Useful on its own (e.g. reading a
    /// photographed diagram or exam figure), and this is the underlying
    /// call an image-anchored MCQ path would build on for the Gemma
    /// backend (Apple's FoundationModels path has no image input at all,
    /// per MCQGenerator's own doc comments, so this is Gemma-only for now).
    func understandImage(_ image: UIImage, question: String) async throws -> String {
        guard Self.isDownloaded else { throw GenerationError.notDownloaded }
        let llm = try await loadedClient()
        let input = LLMInput.chat([
            .user(question, attachments: [.image(image)]),
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
    }

    /// A small model asked for JSON sometimes wraps it in a markdown code
    /// fence anyway, or adds a stray sentence before/after — strip down to
    /// the outermost `{...}` before decoding, same defensive parsing the
    /// web app's own hand-rolled JSON extraction used.
    private static func parseQuestions(from raw: String) -> [MCQQuestion] {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { return [] }
        let jsonSlice = raw[start...end]
        guard let data = jsonSlice.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawQuestionSet.self, from: data) else { return [] }
        return decoded.questions.filter {
            MCQGenerator.isValidQuestion(stem: $0.stem, options: $0.options, correctIndex: $0.correctIndex)
        }.map {
            MCQQuestion(stem: $0.stem, options: $0.options, correctIndex: $0.correctIndex, explanation: $0.explanation)
        }
    }

    private struct RawQuestionSet: Decodable {
        var questions: [RawQuestion]
    }
    private struct RawQuestion: Decodable {
        var stem: String
        var options: [String]
        var correctIndex: Int
        var explanation: String
    }
}

/// `URLSessionDownloadDelegate` doesn't hand back progress through
/// async/await on its own — this bridges its callbacks to the fraction
/// the download UI wants, same pattern any plain URLSession download
/// with progress uses.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                     didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                     totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                     didFinishDownloadingTo location: URL) {
        // Handled by the `download(from:delegate:)` async call itself,
        // which returns this same temp URL — nothing to do here.
    }
}
