import Foundation
import AVFoundation

/// Transcribing a lecture with Gemini, through CramDown's Firebase project.
///
/// Nobody brings a key: the worker says which Firebase project and models to
/// use (`/transcribe/config`), and the audio goes from the phone straight to
/// Firebase AI Logic's Gemini endpoint - the same one the Firebase SDK calls -
/// in ten-minute pieces. Apple's on-device recogniser stays as the offline
/// path and the fallback when Gemini can't be reached.
enum CloudTranscriber {

    enum Failure: LocalizedError, Equatable {
        case notSetUp
        /// Out of quota on every model, or Google is overloaded.
        case busy
        case noAudio
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Cloud transcription isn't set up yet."
            case .busy: return "Cloud transcription has reached today's limit. Try again later, or transcribe on this phone."
            case .noAudio: return "That file has no audio in it."
            case .failed(let why): return why
            }
        }
    }

    struct Config: Decodable {
        var apiKey: String
        var projectId: String
        var models: [String]
    }

    static func config() async throws -> Config {
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent("transcribe/config"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let config = try? JSONDecoder().decode(Config.self, from: data),
              !config.apiKey.isEmpty, !config.models.isEmpty else { throw Failure.notSetUp }
        return config
    }

    /// The whole recording as timed lines.
    static func transcribe(fileAt url: URL, vocabulary: [String],
                           config: Config? = nil,
                           onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [LectureTranscriber.Line] {
        // not `config ?? await ...`: an autoclosure can't await
        let settings: Config
        if let config { settings = config } else { settings = try await self.config() }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw Failure.noAudio }
        let starts = CloudTranscript.chunkStarts(duration: duration)
        let prompt = CloudTranscript.prompt(vocabulary: vocabulary)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var lines: [LectureTranscriber.Line] = []
        // the model that last worked is tried first: once the first is out of
        // quota there is no point asking it again for every chunk
        var models = settings.models
        for (i, start) in starts.enumerated() {
            try Task.checkCancellation()
            onProgress(i + 1, starts.count)
            let end = i + 1 < starts.count ? starts[i + 1] : duration
            let piece = folder.appendingPathComponent("\(i).m4a")
            try await exportChunk(of: asset, start: start, length: end - start, to: piece)
            let audio = try Data(contentsOf: piece)
            let (phrases, used) = try await ask(audio: audio, prompt: prompt, config: settings, models: models)
            if let at = models.firstIndex(of: used), at > 0 { models = Array(models[at...]) }
            lines += CloudTranscript.lines(from: phrases, offset: start, length: end - start)
        }
        return lines
    }

    // MARK: Gemini

    /// One chunk, trying each model in turn while the answer is "no quota" or
    /// "no such model"; anything else is a real failure and says so.
    static func ask(audio: Data, prompt: String, config: Config,
                    models: [String]) async throws -> ([CloudTranscript.Phrase], String) {
        var lastError: Failure = .busy
        for model in models {
            for attempt in 0..<2 {
                do {
                    let reply = try await generate(audio: audio, prompt: prompt, model: model, config: config)
                    if let phrases = CloudTranscript.phrases(fromReply: reply) { return (phrases, model) }
                    lastError = .failed("Gemini's answer couldn't be read.")
                    // an unreadable answer is worth one more try on the same model
                    if attempt == 0 { continue }
                } catch let status as Status {
                    switch status.code {
                    case 429:
                        lastError = .busy
                    case 403 where status.quota:
                        lastError = .busy
                    case 404, 400 where status.message.localizedCaseInsensitiveContains("model"):
                        // this model isn't offered (retired, or not on the free
                        // tier): the next one may be
                        lastError = .failed(status.message)
                    case 500...504:
                        lastError = .busy
                        if attempt == 0 { try await Task.sleep(nanoseconds: 3_000_000_000); continue }
                    default:
                        throw Failure.failed(status.message)
                    }
                }
                break
            }
        }
        throw lastError
    }

    struct Status: Error {
        var code: Int
        var message: String
        var quota: Bool { message.localizedCaseInsensitiveContains("quota") }
    }

    static func generate(audio: Data, prompt: String, model: String, config: Config) async throws -> String {
        let address = "https://firebasevertexai.googleapis.com/v1beta/projects/\(config.projectId)/models/\(model):generateContent"
        guard let url = URL(string: address) else { throw Failure.notSetUp }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        if let bundle = Bundle.main.bundleIdentifier {
            request.setValue(bundle, forHTTPHeaderField: "x-ios-bundle-identifier")
        }
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inlineData": ["mimeType": "audio/mp4", "data": audio.base64EncodedString()]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 16384,
                "responseMimeType": "application/json",
                "responseSchema": CloudTranscript.responseSchema,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let message = ((object?["error"] as? [String: Any])?["message"] as? String)
                ?? "Gemini answered \(code)."
            throw Status(code: code, message: message)
        }
        let parts = (((object?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                     as? [[String: Any]]) ?? []
        // a thinking model can return its thoughts as parts of their own
        return parts.filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }.joined()
    }

    // MARK: cutting the recording

    /// One stretch of the recording as 16 kHz mono AAC at 32 kbps: all a
    /// voice needs, and small enough to send inline.
    static func exportChunk(of asset: AVURLAsset, start: Double, length: Double, to out: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudio }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: length, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        try? FileManager.default.removeItem(at: out)
        let writer = try AVAssetWriter(outputURL: out, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard reader.startReading() else {
            throw Failure.failed(reader.error?.localizedDescription ?? "The recording couldn't be read.")
        }
        guard writer.startWriting() else {
            throw Failure.failed(writer.error?.localizedDescription ?? "The recording couldn't be cut.")
        }
        writer.startSession(atSourceTime: reader.timeRange.start)
        let pump = Pump(reader: reader, output: output, input: input)
        await pump.run()
        if reader.status == .failed {
            writer.cancelWriting()
            throw Failure.failed(reader.error?.localizedDescription ?? "The recording couldn't be read.")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.failed(writer.error?.localizedDescription ?? "The recording couldn't be cut.")
        }
    }

    /// Moves samples from the reader to the writer on AVFoundation's own
    /// schedule. The AV objects are used only from its one queue.
    private final class Pump: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        private var done = false

        init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
            self.reader = reader
            self.output = output
            self.input = input
        }

        func run() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                input.requestMediaDataWhenReady(on: DispatchQueue(label: "cramdown.chunk")) { [self] in
                    guard !done else { return }
                    while input.isReadyForMoreMediaData {
                        if let buffer = output.copyNextSampleBuffer(), input.append(buffer) { continue }
                        done = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
