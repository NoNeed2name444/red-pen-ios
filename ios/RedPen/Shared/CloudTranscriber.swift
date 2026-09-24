import Foundation
import AVFoundation

/// Transcribing a lecture with Gemini, for Pro.
///
/// The recording is cut into ten-minute pieces and each goes to CramDown's
/// server (`/transcribe/chunk`) with the account's session, and the server
/// asks Gemini. The Google key never reaches the phone, so only Pro accounts
/// can use it, within a daily allowance and a monthly budget. Apple's
/// on-device recogniser stays as the offline path and the fallback.
enum CloudTranscriber {

    enum Failure: LocalizedError, Equatable {
        case notSetUp
        /// Not signed in to a Pro account.
        case needsPro
        /// Out of today's allowance or this month's budget, or Google is busy.
        case busy(String)
        case noAudio
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Cloud transcription isn't set up yet."
            case .needsPro: return "Cloud transcription is part of Pro."
            case .busy(let why): return why
            case .noAudio: return "That file has no audio in it."
            case .failed(let why): return why
            }
        }
    }

    /// The whole recording as timed lines. `token` is the account's session
    /// (or the owner key in the owner's build).
    static func transcribe(fileAt url: URL, vocabulary: [String], token: String?,
                           onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [LectureTranscriber.Line] {
        guard let token, !token.isEmpty else { throw Failure.needsPro }
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
        for (i, start) in starts.enumerated() {
            try Task.checkCancellation()
            onProgress(i + 1, starts.count)
            let end = i + 1 < starts.count ? starts[i + 1] : duration
            let piece = folder.appendingPathComponent("\(i).m4a")
            try await exportChunk(of: asset, start: start, length: end - start, to: piece)
            let audio = try Data(contentsOf: piece)
            let phrases = try await ask(audio: audio, prompt: prompt, token: token)
            lines += CloudTranscript.lines(from: phrases, offset: start, length: end - start)
        }
        return lines
    }

    // MARK: the server

    /// One chunk. An unreadable answer or a server hiccup gets one more try;
    /// anything the server says in words is passed on as it is.
    static func ask(audio: Data, prompt: String, token: String) async throws -> [CloudTranscript.Phrase] {
        var lastError: Failure = .failed("Gemini's answer couldn't be read.")
        for attempt in 0..<2 {
            let (code, object) = try await post(audio: audio, prompt: prompt, token: token)
            let message = object?["message"] as? String
            switch code {
            case 200:
                if let text = object?["text"] as? String, let phrases = CloudTranscript.phrases(fromReply: text) { return phrases }
                lastError = .failed("Gemini's answer couldn't be read.")
            case 401: throw Failure.failed("Please sign in again to use cloud transcription.")
            case 402: throw Failure.needsPro
            case 429: throw Failure.busy(message ?? "Cloud transcription is busy. Try again later, or transcribe on this phone.")
            case 404, 410, 503: throw Failure.notSetUp
            case 500...599:
                lastError = .failed(message ?? "The server couldn't transcribe that (\(code)).")
                if attempt == 0 { try await Task.sleep(nanoseconds: 3_000_000_000) }
            default:
                throw Failure.failed(message ?? "The server couldn't transcribe that (\(code)).")
            }
        }
        throw lastError
    }

    static func post(audio: Data, prompt: String, token: String) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent("transcribe/chunk"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "audio": audio.base64EncodedString(), "prompt": prompt,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (code, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
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
