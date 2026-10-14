import Foundation
import LocalLLMClientLlama

/// The fallback MCQ-generation backend for devices that cannot run Apple's
/// on-device model at all - anything older than iPhone 15 Pro, or a newer phone
/// with Apple Intelligence turned off. It downloads a quantized Gemma 4 E2B
/// checkpoint (~2.8 GB at 4-bit) plus its vision projector (~530 MB) and runs
/// both fully on-device through llama.cpp. Like the Apple path, it never
/// touches anyone's account or any paid API; it is just a bigger one-time
/// download and a slower model.
///
/// This file holds what the model IS - where it lives on disk and whether it is
/// there. Fetching it is in GemmaDownload, writing questions with it is in
/// GemmaGenerate.
///
/// Audio input is NOT implemented, on purpose rather than by oversight:
/// llama.cpp's multimodal layer supports audio, but the LocalLLMClient package
/// this app depends on only wires that up as far as images at the Swift level -
/// `LLMAttachment.Content` has one case, `.image`, and the helpers around it
/// are `package`, not `public`. Doing it for real means forking that package
/// and writing new C-interop bindings, so it is left undone rather than faked.
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

    /// The model card at ggml-org/gemma-4-E2B-it-GGUF. Q4_0 is the smallest
    /// quantization it publishes that keeps the full-precision tokenizer.
    static let downloadURL = URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf")!
    static let filename = "gemma-4-E2B-it-Q4_0.gguf"
    /// For UI copy only - the file on disk decides whether a download finished.
    static let approxDownloadBytes: Int64 = 2_840_000_000

    /// The matching vision projector from the same card, which is what turns on
    /// image understanding. Q8_0 rather than Q4_0 because ggml-org publish no
    /// Q4_0 projector for this checkpoint.
    static let mmprojDownloadURL = URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/mmproj-gemma-4-E2B-it-Q8_0.gguf")!
    static let mmprojFilename = "mmproj-gemma-4-E2B-it-Q8_0.gguf"
    static let approxMmprojDownloadBytes: Int64 = 557_368_064
    static var approxTotalDownloadBytes: Int64 { approxDownloadBytes + approxMmprojDownloadBytes }

    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models", isDirectory: true)
    }
    static var localURL: URL { modelsDirectory.appendingPathComponent(filename) }
    static var mmprojLocalURL: URL { modelsDirectory.appendingPathComponent(mmprojFilename) }

    var downloadTask: Task<Void, Never>?
    /// The loaded llama.cpp client. Expensive to create, so it is kept for the
    /// lifetime of the app once generation has happened once rather than
    /// reloaded for every batch.
    var client: LlamaClient?

    private init() {
        status = Self.isDownloaded ? .ready : .notDownloaded
    }

    func setStatus(_ new: Status) { status = new }

    /// A half-downloaded or corrupt file would otherwise look ready, so most of
    /// the expected size has to be there before it is trusted.
    static func fileLooksComplete(at url: URL, approxSize: Int64) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return (size ?? 0) > Int64(Double(approxSize) * 0.9)
    }

    static var isDownloaded: Bool {
        fileLooksComplete(at: localURL, approxSize: approxDownloadBytes)
            && fileLooksComplete(at: mmprojLocalURL, approxSize: approxMmprojDownloadBytes)
    }

    func refreshStatus() {
        if case .downloading = status { return } // don't clobber an in-flight download
        status = Self.isDownloaded ? .ready : .notDownloaded
    }

    func deleteDownloadedModel() {
        cancelDownload()
        client = nil
        try? FileManager.default.removeItem(at: Self.localURL)
        try? FileManager.default.removeItem(at: Self.mmprojLocalURL)
        status = .notDownloaded
    }
}
