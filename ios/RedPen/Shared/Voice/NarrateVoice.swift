import Foundation
import AVFoundation
import CryptoKit

/// Where the voice is: the line, and the word in it once one is being said.
struct NarrateSpot: Equatable {
    var line: Int
    var word: Int?
}

/// A clip on disk, with its measured length.
struct NarrateClip: Sendable {
    let url: URL
    let duration: Double
}

/// Reading a typed lecture aloud, word by word.
///
/// With the natural cloud voice (Pro, online, English):
///   - the lecture is cut into clips (NarratePlan.chunks): a short first one so
///     speech starts at once, then longer ones
///   - the clip playing and the next three are always being fetched, off the
///     main thread, and kept on disk, so a lecture heard twice costs nothing
///   - clips are queued in one AVQueuePlayer, which starts the next clip the
///     moment the last one ends - no gap while a new player is made
///   - which word is lit comes from the clip's own clock, 15 times a second,
///     and is published only when it changes
///
/// Otherwise the phone's own voice: one synthesizer for the whole lecture, a
/// few lines queued ahead so there is no pause between them, and the word
/// lit is the one the synthesizer says it is about to speak.
///
/// If the cloud stops answering half way through, the phone carries on from
/// the first line the cloud did not read.
@MainActor
final class NarrateVoice: NSObject, ObservableObject {

    @Published private(set) var spot = NarrateSpot(line: 0, word: nil)
    @Published private(set) var playing = false
    @Published private(set) var finished = false
    /// Playing, but the next clip has not arrived yet.
    @Published private(set) var waiting = false

    /// After a refusal the cloud is left alone for a while, so jumping about
    /// does not wait on a server that has already said no.
    private static var cloudRestUntil = Date.distantPast
    /// Clips fetched ahead of the one playing.
    private static let ahead = 3

    private var lines: [String] = []
    private var langs: [String] = []
    private var title = "Lecture"
    private var speed: Double = 1
    private var chunks: [NarrateChunk] = []
    /// Stopped in place by Pause, so Play carries on rather than starting over.
    private var paused = false
    /// Bumped by every Play and Stop, so a late timer knows it is stale.
    private var session = 0
    private var remote: [Any] = []

    // the cloud voice
    private let cloud = CloudVoice()
    private var clips: [String: NarrateClip] = [:]
    private var fetching: [String: Task<Void, Never>] = [:]
    private var failed: Set<String> = []
    private var queue: AVQueuePlayer?
    private var queuedChunk: [ObjectIdentifier: Int] = [:]
    private var queuedWords: [Int: [ClipWord]] = [:]
    private var nextToQueue = 0
    private var seekChunk: Int?
    private var seekLine = 0
    private var onCloud = false
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []

    // the phone's voice
    private struct PhoneLine {
        let line: Int
        let first: Int
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var utterances: [ObjectIdentifier: PhoneLine] = [:]
    private var nextPhoneLine = 0
    private var phoneNeedsRestart = false
    private lazy var arabicVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "ar-SA")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// A phone call stops the lecture in place; Play carries on after it.
    private func listen() {
        guard observers.isEmpty else { return }
        let center: NotificationCenter = NotificationCenter.default
        let interrupted: NSObjectProtocol = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw: UInt = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let began: Bool = AVAudioSession.InterruptionType(rawValue: raw) == .began
            guard began else { return }
            MainActor.assumeIsolated { self?.pause() }
        }
        let ended: NSObjectProtocol = center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            MainActor.assumeIsolated { self?.itemEnded(id) }
        }
        observers = [interrupted, ended]
    }

    private func unlisten() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    // MARK: what is read

    /// The lecture to read. Called again after a word is fixed: if it is
    /// playing it carries on from the same line with the new words.
    func load(_ newLines: [String], langs newLangs: [String], title newTitle: String) {
        let wasPlaying: Bool = playing
        let at: Int = spot.line
        if wasPlaying || paused { stopOutput() }
        paused = false
        lines = newLines
        langs = newLangs
        title = newTitle.isEmpty ? "Lecture" : newTitle
        chunks = NarratePlan.chunks(newLines)
        if spot.line >= newLines.count { spot = NarrateSpot(line: 0, word: nil) }
        if wasPlaying {
            play(from: min(at, max(0, newLines.count - 1)))
        }
    }

    // MARK: the controls

    func play(from line: Int) {
        guard !lines.isEmpty else { return }
        let start: Int = max(0, min(line, lines.count - 1))
        stopOutput()
        session += 1
        finished = false
        paused = false
        playing = true
        spot = NarrateSpot(line: start, word: nil)
        NowPlaying.activate()
        listen()
        attachRemote()
        if cloudUsable {
            startCloud(at: start)
        } else {
            startPhone(at: start, word: 0)
        }
        showNowPlaying()
    }

    /// Play: carries on from where Pause stopped, or starts from the line
    /// that is lit.
    func resume() {
        guard paused else {
            play(from: finished ? 0 : spot.line)
            return
        }
        paused = false
        playing = true
        NowPlaying.activate()
        if onCloud, let queue {
            queue.defaultRate = Float(speed)
            if queue.currentItem == nil {
                // still waiting for a clip: queue it if it came while paused,
                // or hand over to the phone if it never will
                waiting = true
                fillQueue()
            } else {
                queue.play()
            }
        } else if phoneNeedsRestart || !synthesizer.continueSpeaking() {
            startPhone(at: spot.line, word: spot.word ?? 0)
        }
        showNowPlaying()
    }

    func pause() {
        guard playing else { return }
        playing = false
        paused = true
        waiting = false
        if onCloud {
            queue?.pause()
        } else {
            _ = synthesizer.pauseSpeaking(at: .immediate)
        }
        showNowPlaying()
    }

    func toggle() {
        if playing { pause() } else { resume() }
    }

    /// A tapped line: read from there if reading, otherwise light it and wait.
    func jump(to line: Int) {
        guard !lines.isEmpty else { return }
        let target: Int = max(0, min(line, lines.count - 1))
        if playing {
            play(from: target)
            return
        }
        stopOutput()
        paused = false
        finished = false
        spot = NarrateSpot(line: target, word: nil)
    }

    /// A new speed takes effect at once: the cloud clip is sped up in place,
    /// and the phone's voice starts again from the word it was on (a
    /// synthesizer cannot change the rate of a line it has started).
    func setSpeed(_ newSpeed: Double) {
        guard newSpeed != speed else { return }
        speed = newSpeed
        if onCloud {
            queue?.defaultRate = Float(newSpeed)
            if playing, queue?.currentItem != nil { queue?.rate = Float(newSpeed) }
        } else if playing {
            startPhone(at: spot.line, word: spot.word ?? 0)
        } else if paused {
            phoneNeedsRestart = true
        }
        showNowPlaying()
    }

    /// Everything off: the screen is going away.
    func stop() {
        session += 1
        stopOutput()
        playing = false
        paused = false
        for task in fetching.values { task.cancel() }
        fetching = [:]
        if let timeObserver, let queue { queue.removeTimeObserver(timeObserver) }
        timeObserver = nil
        queue = nil
        NowPlaying.release(remote)
        remote = []
        unlisten()
    }

    private func finish() {
        stopOutput()
        playing = false
        paused = false
        finished = true
        spot = NarrateSpot(line: max(0, lines.count - 1), word: nil)
        showNowPlaying()
    }

    /// Silences both voices without changing what the screen shows.
    private func stopOutput() {
        queue?.pause()
        queue?.removeAllItems()
        queuedChunk = [:]
        queuedWords = [:]
        seekChunk = nil
        onCloud = false
        waiting = false
        utterances = [:]
        silencePhone()
        phoneNeedsRestart = false
    }

    // MARK: the cloud voice

    private var cloudUsable: Bool {
        guard Date() >= Self.cloudRestUntil, !chunks.isEmpty else { return false }
        // Aura-2 speaks English; an Arabic line is the phone's
        guard !langs.contains("ar") else { return false }
        return cloud.available
    }

    private func startCloud(at line: Int) {
        guard let c = NarratePlan.chunkIndex(containing: line, in: chunks) else {
            finish()
            return
        }
        onCloud = true
        _ = ensureQueue()
        nextToQueue = c
        seekChunk = c
        seekLine = line
        waiting = true
        fillQueue()
        // the first clip should be here within a moment; if the server is
        // slow today, the phone starts rather than leaving silence
        let mine: Int = session
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.giveUpIfSilent(mine, line: line)
        }
    }

    private func giveUpIfSilent(_ mine: Int, line: Int) {
        guard session == mine, onCloud, playing, waiting, queuedChunk.isEmpty else { return }
        Self.cloudRestUntil = Date().addingTimeInterval(90)
        startPhone(at: spot.line, word: 0)
    }

    private func ensureQueue() -> AVQueuePlayer {
        if let queue { return queue }
        let made = AVQueuePlayer()
        made.actionAtItemEnd = .advance
        made.automaticallyWaitsToMinimizeStalling = false
        let interval = CMTime(value: 1, timescale: 15)
        timeObserver = made.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        queue = made
        return made
    }

    /// Fetches what is coming and queues whatever has arrived, in order.
    private func fillQueue() {
        guard onCloud, let queue else { return }
        let playingChunk: Int = queuedChunk.values.min() ?? nextToQueue
        var have: Set<Int> = []
        let upper: Int = min(chunks.count, playingChunk + Self.ahead + 1)
        for k in playingChunk..<upper {
            let text: String = chunks[k].text
            if clips[text] != nil || fetching[text] != nil || failed.contains(text) { have.insert(k) }
        }
        let wanted: [Int] = NarratePlan.prefetch(current: playingChunk, count: chunks.count,
                                                 ahead: Self.ahead, have: have)
        for k in wanted { fetch(k) }

        var added = false
        while nextToQueue < chunks.count, nextToQueue <= playingChunk + Self.ahead {
            let text: String = chunks[nextToQueue].text
            guard let clip = clips[text] else { break }
            enqueue(nextToQueue, clip, in: queue)
            nextToQueue += 1
            added = true
        }
        if added && playing && waiting {
            waiting = false
            queue.defaultRate = Float(speed)
            queue.play()
        }
        // the next clip will never come: once what is queued has played,
        // the phone reads on from there
        if queuedChunk.isEmpty, nextToQueue < chunks.count,
           failed.contains(chunks[nextToQueue].text), playing {
            startPhone(at: chunks[nextToQueue].lines.lowerBound, word: 0)
        }
    }

    private func enqueue(_ k: Int, _ clip: NarrateClip, in queue: AVQueuePlayer) {
        let item = AVPlayerItem(url: clip.url)
        // the speech-friendly way to change speed without changing pitch
        item.audioTimePitchAlgorithm = .timeDomain
        let words: [ClipWord] = NarratePlan.wordTimes(lines: lines, range: chunks[k].lines,
                                                      duration: clip.duration)
        queuedChunk[ObjectIdentifier(item)] = k
        queuedWords[k] = words
        queue.insert(item, after: nil)
        if seekChunk == k {
            seekChunk = nil
            let at: Double = NarratePlan.start(ofLine: seekLine, in: words)
            if at > 0.05 {
                let time = CMTime(seconds: at, preferredTimescale: 600)
                let slack = CMTime(seconds: 0.05, preferredTimescale: 600)
                queue.seek(to: time, toleranceBefore: slack, toleranceAfter: slack)
            }
        }
    }

    private func fetch(_ k: Int) {
        let text: String = chunks[k].text
        guard clips[text] == nil, fetching[text] == nil, !failed.contains(text) else { return }
        guard !text.isEmpty, text.count <= NarratePlan.hardCap else {
            failed.insert(text)
            return
        }
        let token: String = LocalLLMService.shared.cloudToken ?? ""
        let task = Task { [weak self] in
            // runs off the main thread: the request, the file, the duration
            let clip: NarrateClip? = await NarrateVoice.download(text, token: token)
            if Task.isCancelled { return }
            self?.arrived(text, clip)
        }
        fetching[text] = task
    }

    private func arrived(_ text: String, _ clip: NarrateClip?) {
        fetching[text] = nil
        if let clip {
            clips[text] = clip
            if clips.count > 24 {
                // only the file names are kept; the audio is on disk
                var playingTexts: Set<String> = []
                for k in queuedWords.keys where k < chunks.count {
                    playingTexts.insert(chunks[k].text)
                }
                for key in clips.keys where !playingTexts.contains(key) && clips.count > 24 {
                    clips[key] = nil
                }
            }
        } else {
            failed.insert(text)
            Self.cloudRestUntil = Date().addingTimeInterval(60)
        }
        fillQueue()
    }

    private func itemEnded(_ id: ObjectIdentifier) {
        guard let k = queuedChunk.removeValue(forKey: id) else { return }
        queuedWords[k] = nil
        if k >= chunks.count - 1 {
            finish()
            return
        }
        fillQueue()
        if onCloud, queuedChunk.isEmpty, playing {
            // the next clip is still on its way
            waiting = true
            let first: Int = chunks[k + 1].lines.lowerBound
            spot = NarrateSpot(line: first, word: nil)
        }
    }

    /// Fifteen times a second while a clip plays: which word is it on?
    private func tick() {
        guard onCloud, playing, let queue, let item = queue.currentItem else { return }
        guard let k = queuedChunk[ObjectIdentifier(item)], let words = queuedWords[k] else { return }
        let t: Double = item.currentTime().seconds
        guard t.isFinite, let i = NarratePlan.spot(at: t, in: words) else { return }
        let now = NarrateSpot(line: words[i].line, word: words[i].word)
        if now != spot { spot = now }
    }

    // MARK: the clip cache, on disk

    nonisolated private static var cacheFolder: URL {
        let base: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir: URL = base.appendingPathComponent("narrate-voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func cacheFile(for text: String) -> URL {
        let digest = SHA256.hash(data: Data(("narrator|" + text).utf8))
        let name: String = digest.map { String(format: "%02x", $0) }.joined()
        return cacheFolder.appendingPathComponent(name + ".mp3")
    }

    /// One clip: from the disk if it was heard before, otherwise from the
    /// server. Never on the main thread.
    nonisolated static func download(_ text: String, token: String) async -> NarrateClip? {
        let file: URL = cacheFile(for: text)
        if FileManager.default.fileExists(atPath: file.path),
           let seconds = await duration(of: file) {
            return NarrateClip(url: file, duration: seconds)
        }
        let answer: CloudFetch = await CloudVoice.fetch(text, patient: false, token: token)
        guard let clip = answer.clip else { return nil }
        do {
            try clip.data.write(to: file, options: .atomic)
        } catch {
            return nil
        }
        prune()
        guard let seconds = await duration(of: file) else { return nil }
        return NarrateClip(url: file, duration: seconds)
    }

    /// The clip's real length - the word timing is laid over this, so it is
    /// measured, not estimated from the bit rate.
    nonisolated private static func duration(of url: URL) async -> Double? {
        let options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: url, options: options)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds: Double = time.seconds
        return seconds.isFinite && seconds > 0.2 ? seconds : nil
    }

    /// A few lectures' worth is kept; the oldest go first.
    nonisolated private static func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let found: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: cacheFolder, includingPropertiesForKeys: keys)) ?? []
        let keep = 400
        guard found.count > keep else { return }
        let dated: [(URL, Date)] = found.map { url in
            let date: Date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url, date)
        }
        let oldestFirst = dated.sorted { $0.1 < $1.1 }
        for (url, _) in oldestFirst.prefix(found.count - keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: the phone's voice

    /// Only when it has something to stop: a stop just before a speak can
    /// swallow the new line on some iOS versions.
    private func silencePhone() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    /// One synthesizer for the whole lecture, three lines queued ahead, so
    /// one line runs into the next without a pause while a new one is set up.
    private func startPhone(at line: Int, word: Int) {
        queue?.pause()
        queue?.removeAllItems()
        queuedChunk = [:]
        queuedWords = [:]
        onCloud = false
        waiting = false
        utterances = [:]
        silencePhone()
        phoneNeedsRestart = false
        guard line < lines.count else {
            finish()
            return
        }
        speakLine(line, from: word)
        while utterances.count < 3 && nextPhoneLine < lines.count {
            speakLine(nextPhoneLine, from: 0)
        }
        if utterances.isEmpty { finish() }
    }

    private func speakLine(_ line: Int, from word: Int) {
        nextPhoneLine = line + 1
        let words: [String] = NarratePlan.tokens(lines[line])
        guard word < words.count else { return }
        let text: String = words[word...].joined(separator: " ")
        let utterance = AVSpeechUtterance(string: text)
        let arabic: Bool = line < langs.count && langs[line] == "ar"
        utterance.voice = arabic ? arabicVoice : VoiceSpeaker.voices.narrator
        utterance.rate = NarratePlan.phoneRate(speed)
        utterance.preUtteranceDelay = 0
        // a phrase break, as a lecturer leaves between lines
        utterance.postUtteranceDelay = 0.06
        utterances[ObjectIdentifier(utterance)] = PhoneLine(line: line, first: word)
        synthesizer.speak(utterance)
    }

    fileprivate func phoneStarted(_ id: ObjectIdentifier) {
        guard let place = utterances[id], playing else { return }
        let now = NarrateSpot(line: place.line, word: place.first)
        if now != spot { spot = now }
    }

    fileprivate func phoneWillSpeak(_ id: ObjectIdentifier, at offset: Int, in text: String) {
        guard let place = utterances[id], playing else { return }
        let word: Int = place.first + NarratePlan.wordIndex(atUTF16: offset, in: text)
        let now = NarrateSpot(line: place.line, word: word)
        if now != spot { spot = now }
    }

    fileprivate func phoneFinished(_ id: ObjectIdentifier) {
        guard utterances.removeValue(forKey: id) != nil else { return }
        while utterances.count < 3 && nextPhoneLine < lines.count {
            speakLine(nextPhoneLine, from: 0)
        }
        if utterances.isEmpty && nextPhoneLine >= lines.count { finish() }
    }

    fileprivate func phoneCancelled(_ id: ObjectIdentifier) {
        utterances[id] = nil
    }

    // MARK: the lock screen

    private func attachRemote() {
        guard remote.isEmpty else { return }
        remote = NowPlaying.handle(play: { [weak self] in self?.resume() },
                                   pause: { [weak self] in self?.pause() },
                                   toggle: { [weak self] in self?.toggle() })
    }

    private func showNowPlaying() {
        guard !remote.isEmpty else { return }
        NowPlaying.show(title: title, playing: playing, rate: speed)
    }
}

// Delegate calls are put back on the main queue in the order they came, so a
// word's highlight never lands after the next word's.
extension NarrateVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.phoneStarted(id) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let offset: Int = characterRange.location
        let text: String = utterance.speechString
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.phoneWillSpeak(id, at: offset, in: text) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.phoneFinished(id) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.phoneCancelled(id) } }
    }
}
