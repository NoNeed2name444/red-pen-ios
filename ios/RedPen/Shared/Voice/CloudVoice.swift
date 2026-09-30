import Foundation
import AVFoundation

/// The "Natural cloud voice" setting, kept outside CloudVoice so a view can
/// read the key without touching anything that runs on the main actor.
enum CloudVoiceSetting {
    static let key = "voice.naturalCloud"

    /// On unless the student has turned it off.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// One line of speech from the server, as MP3.
struct CloudClip: Sendable {
    let data: Data
    /// True when the server used Aura-2, which has a separate voice for the
    /// patient. Its cheaper fallback has only one voice for everybody.
    let distinctVoices: Bool
}

/// What one request to the server came to: a clip, or how long to leave the
/// server alone before asking again (zero means "just this line failed").
struct CloudFetch: Sendable {
    var clip: CloudClip?
    var rest: TimeInterval
}

/// Speech that sounds like a person, made on the server.
///
/// The server's /tts route runs Deepgram's Aura-2 voice model on Cloudflare
/// and sends back MP3; this fetches it and plays it with AVAudioPlayer. It is
/// part of Pro and needs the internet, so whenever it cannot be used - offline,
/// signed out, not Pro, the day's allowance spent, the setting off - it simply
/// returns nothing and VoiceSpeaker uses the phone's own voice instead.
///
/// Lines are kept in memory once fetched, and `prefetch` fetches the next one
/// while the current one is playing, so there is no gap between them.
@MainActor
final class CloudVoice: NSObject {

    /// The server takes up to 1,500 characters; a little under leaves room.
    static let maxChars = 1400

    // Shared by every speaker in the app: a line fetched by one screen is
    // there for the next, and a refusal is remembered everywhere.
    private static var clips: [String: CloudClip] = [:]
    private static var order: [String] = []
    private static var pending: [String: Task<CloudClip?, Never>] = [:]
    private static var restUntil = Date.distantPast
    private static let keepAtMost = 40

    private var player: AVAudioPlayer?
    private var waiting: CheckedContinuation<Bool, Never>?
    private var current: ObjectIdentifier?

    /// Whether it is worth asking the server at all right now.
    var available: Bool {
        eligible && Date() >= Self.restUntil
    }

    /// Whether the cloud voice can be used at all - switched on, signed in,
    /// Pro - leaving aside a rest after a refusal. Narrate reads on with the
    /// phone through a rest and hands back to the cloud once it is over.
    var eligible: Bool {
        guard CloudVoiceSetting.isOn else { return false }
        let service = LocalLLMService.shared
        guard service.cloudToken != nil else { return false }
        return service.isPro || PersonalBuild.isOn
    }

    /// A refusal heard by another speaker (Narrate makes its own requests)
    /// rests every speaker in the app, for as long as the server asked.
    static func rest(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        restUntil = max(restUntil, Date().addingTimeInterval(seconds))
    }

    // MARK: fetching

    /// The audio for one piece of text (at most `maxChars`), or nil when the
    /// phone should read it itself.
    func clip(for text: String, patient: Bool) async -> CloudClip? {
        guard available, !text.isEmpty, text.count <= Self.maxChars else { return nil }
        let key = Self.key(text, patient: patient)
        if let done = Self.clips[key] { return done }
        let task = Self.pending[key] ?? start(text, patient: patient, key: key)
        return await task.value
    }

    /// Starts fetching a line that is about to be needed, without waiting.
    func prefetch(_ text: String, patient: Bool) {
        guard available, !text.isEmpty, text.count <= Self.maxChars else { return }
        let key = Self.key(text, patient: patient)
        if Self.clips[key] != nil || Self.pending[key] != nil { return }
        _ = start(text, patient: patient, key: key)
    }

    private func start(_ text: String, patient: Bool, key: String) -> Task<CloudClip?, Never> {
        let token = LocalLLMService.shared.cloudToken ?? ""
        let task = Task { @MainActor () -> CloudClip? in
            let answer = await CloudVoice.fetch(text, patient: patient, token: token)
            CloudVoice.settle(key: key, answer: answer)
            return answer.clip
        }
        Self.pending[key] = task
        return task
    }

    private static func settle(key: String, answer: CloudFetch) {
        pending[key] = nil
        rest(answer.rest)
        guard let clip = answer.clip else { return }
        clips[key] = clip
        order.append(key)
        // only the most recent lines are kept, so memory stays small
        while order.count > keepAtMost {
            let oldest = order.removeFirst()
            clips[oldest] = nil
        }
    }

    private static func key(_ text: String, patient: Bool) -> String {
        (patient ? "p|" : "n|") + text
    }

    /// One POST to /tts. Runs off the main actor; everything it touches is
    /// passed in.
    nonisolated static func fetch(_ text: String, patient: Bool, token: String) async -> CloudFetch {
        guard !token.isEmpty else { return CloudFetch(clip: nil, rest: 600) }
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        // a line that takes longer than this would leave a long silence;
        // the phone's own voice is better than waiting
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = ["text": text, "voice": patient ? "patient" : "narrator"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            // offline or timed out: try again in a minute
            return CloudFetch(clip: nil, rest: 60)
        }
        let data = result.0
        let http = result.1 as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 200, data.count > 256 {
            let model = http?.value(forHTTPHeaderField: "x-voice-model") ?? ""
            let clip = CloudClip(data: data, distinctVoices: model == "aura-2")
            return CloudFetch(clip: clip, rest: 0)
        }
        // a server error, or a line the server could not take (a bug here)
        if status >= 500 || status == 400 {
            Diagnostics.record(.warning, area: .voice, message: "tts.http_status", code: status)
        }
        return CloudFetch(clip: nil, rest: restAfter(status))
    }

    /// How long to leave the server alone after a refusal.
    nonisolated static func restAfter(_ status: Int) -> TimeInterval {
        switch status {
        case 401, 402, 403: return 600      // signed out or not Pro
        case 429: return 3600               // today's allowance used
        case 400, 413: return 0             // only this line was the problem
        default: return 120                 // the server is having trouble
        }
    }

    // MARK: playing

    /// Plays a clip and returns once it has finished: true when it played to
    /// the end, false when it could not play or `stop` was called.
    func play(_ clip: CloudClip) async -> Bool {
        stop()
        let made = try? AVAudioPlayer(data: clip.data, fileTypeHint: AVFileType.mp3.rawValue)
        guard let player = made else { return false }
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        let id = ObjectIdentifier(player)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            waiting = continuation
            current = id
            if !player.play() { finished(id, ok: false) }
        }
    }

    /// Silences the line being played, and releases whoever waits on it.
    func stop() {
        player?.stop()
        player = nil
        let pending = waiting
        waiting = nil
        current = nil
        pending?.resume(returning: false)
    }

    fileprivate func finished(_ id: ObjectIdentifier, ok: Bool) {
        guard id == current else { return }
        current = nil
        player = nil
        let pending = waiting
        waiting = nil
        pending?.resume(returning: ok)
    }

    // MARK: cutting text into pieces

    /// Text split at sentence ends into pieces the server will take, each as
    /// long as it can be: fewer requests, and whole sentences sound natural.
    static func pieces(of text: String) -> [String] {
        if text.count <= maxChars { return [text] }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sub, _, _, _ in
            if let sub { sentences.append(sub) }
        }
        var out: [String] = []
        var piece = ""
        for sentence in sentences.flatMap({ splitLong($0) }) {
            if piece.count + sentence.count > maxChars, !piece.isEmpty {
                out.append(piece.trimmingCharacters(in: .whitespaces))
                piece = ""
            }
            piece += sentence
        }
        let last = piece.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { out.append(last) }
        return out
    }

    /// A single sentence too long for one request, cut between words.
    private static func splitLong(_ sentence: String) -> [String] {
        guard sentence.count > maxChars else { return [sentence] }
        var out: [String] = []
        var piece = ""
        for word in sentence.split(separator: " ") {
            if piece.count + word.count + 1 > maxChars, !piece.isEmpty {
                out.append(piece)
                piece = ""
            }
            piece += String(word) + " "
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }
}

extension CloudVoice: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(id, ok: flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.finished(id, ok: false) }
    }
}
