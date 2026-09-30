import Foundation
import AVFoundation
import CryptoKit

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

        // Every chunk Gemini has already answered is kept until the whole
        // recording is done. A failure on part six of six used to throw away
        // parts one to five, which had each used the day's allowance, and a
        // retry paid for all of them again - enough, for a long lecture, to
        // never finish in the cloud at all.
        let done = ChunkCache(recording: url)
        var lines: [LectureTranscriber.Line] = []
        for (i, start) in starts.enumerated() {
            try Task.checkCancellation()
            onProgress(i + 1, starts.count)
            let end = i + 1 < starts.count ? starts[i + 1] : duration
            let phrases: [CloudTranscript.Phrase]
            if let kept = done?.phrases(start: start, length: end - start) {
                phrases = kept
            } else {
                let piece = folder.appendingPathComponent("\(i).m4a")
                try await exportChunk(of: asset, start: start, length: end - start, to: piece)
                let audio = try Data(contentsOf: piece)
                phrases = try await ask(audio: audio, prompt: prompt, token: token)
                done?.keep(phrases, start: start, length: end - start)
            }
            lines += CloudTranscript.lines(from: phrases, offset: start, length: end - start)
        }
        done?.clear()
        return lines
    }

    /// The chunks of one recording already transcribed, on disk in Caches,
    /// filed under the hash of the recording's own bytes - so the same lecture
    /// attached again, or retried tomorrow, finds them, and a different one
    /// never does. Kept a week at most: the system may clear Caches sooner,
    /// which only costs a chunk sent twice.
    struct ChunkCache {
        let folder: URL

        static let keptFor: TimeInterval = 7 * 24 * 3600

        /// Nil when the recording cannot be read to hash it: then nothing is
        /// cached, as before.
        init?(recording url: URL) {
            guard let key = Self.fingerprint(of: url) else { return nil }
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("transcribed-chunks", isDirectory: true)
            Self.forgetOld(in: root)
            folder = root.appendingPathComponent(key, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        private func file(start: Double, length: Double) -> URL {
            folder.appendingPathComponent("\(Int((start * 1000).rounded()))-\(Int((length * 1000).rounded())).json")
        }

        func phrases(start: Double, length: Double) -> [CloudTranscript.Phrase]? {
            guard let data = try? Data(contentsOf: file(start: start, length: length)) else { return nil }
            return try? JSONDecoder().decode([CloudTranscript.Phrase].self, from: data)
        }

        func keep(_ phrases: [CloudTranscript.Phrase], start: Double, length: Double) {
            guard let data = try? JSONEncoder().encode(phrases) else { return }
            try? data.write(to: file(start: start, length: length), options: .atomic)
        }

        /// The whole recording is transcribed: its pieces are not needed again.
        func clear() {
            try? FileManager.default.removeItem(at: folder)
        }

        /// SHA-256 of the file, read a megabyte at a time: a lecture is tens
        /// of megabytes and is never loaded whole to be hashed.
        static func fingerprint(of url: URL) -> String? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let piece = try? handle.read(upToCount: 1 << 20), !piece.isEmpty {
                hasher.update(data: piece)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }

        /// Transcripts of lectures abandoned a week ago are not kept for ever.
        private static func forgetOld(in root: URL) {
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let found = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? []
            let cutoff = Date().addingTimeInterval(-keptFor)
            for folder in found {
                let changed = (try? folder.resourceValues(forKeys: Set(keys)))?.contentModificationDate
                if let changed, changed < cutoff { try? FileManager.default.removeItem(at: folder) }
            }
        }
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
                Diagnostics.record(.warning, area: .transcribe, message: "transcribe.unreadable_reply")
                lastError = .failed("Gemini's answer couldn't be read.")
            case 401: throw Failure.failed("Please sign in again to use cloud transcription.")
            case 402: throw Failure.needsPro
            case 429: throw Failure.busy(message ?? "Cloud transcription is busy. Try again later, or transcribe on this phone.")
            case 404, 410, 503: throw Failure.notSetUp
            case 500...599:
                Diagnostics.record(.error, area: .transcribe, message: "transcribe.server_error", code: code)
                lastError = .failed(message ?? "The server couldn't transcribe that (\(code)).")
                if attempt == 0 { try await Task.sleep(nanoseconds: 3_000_000_000) }
            default:
                Diagnostics.record(.error, area: .transcribe, message: "transcribe.http_status", code: code)
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
