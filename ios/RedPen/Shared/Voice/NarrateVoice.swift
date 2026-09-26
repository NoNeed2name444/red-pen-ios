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

    @Published private(set) var spot = NarrateSpot(line: 0, word: nil) {
        didSet { if spot.line != oldValue.line { lineMoved() } }
    }
    @Published private(set) var playing = false
    @Published private(set) var finished = false
    /// Playing, but the next clip has not arrived yet.
    @Published private(set) var waiting = false
    /// The speed, as chosen on the screen or the lock screen.
    @Published private(set) var speed: Double = 1
    /// Told when the student moves the place by hand, so a sleep timer set
    /// for "the end of this section" follows them to the new one.
    var sleepMoved: (@MainActor () -> Void)?

    /// After a refusal the cloud is left alone for a while, so jumping about
    /// does not wait on a server that has already said no.
    private static var cloudRestUntil = Date.distantPast
    /// Clips fetched ahead of the one playing.
    private static let ahead = 3

    private var lines: [String] = []
    private var langs: [String] = []
    private var title = "Lecture"
    private var chunks: [NarrateChunk] = []
    /// Stopped in place by Pause, so Play carries on rather than starting over.
    private var paused = false
    /// Bumped by every Play and Stop, so a late timer knows it is stale.
    private var session = 0
    private var remote: [Any] = []
    /// The lecture's sections, by line, and the one being read.
    @Published private(set) var chapters: [AudioChapter] = []
    private var section: Int?
    /// Paused by a call, so the end of the call may carry on.
    private var pausedByInterruption = false
    /// The sleep timer's fade, for the cloud voice. (The phone's voice
    /// cannot be faded part way through a line; it simply stops.)
    private var fade: Float = 1

    // the cloud voice
    private let cloud = CloudVoice()
    private var clips: [String: NarrateClip] = [:]
    private var fetching: [String: Task<Void, Never>] = [:]
    private var failed: Set<String> = []
    private var queue: AVQueuePlayer?
    private var queuedChunk: [ObjectIdentifier: Int] = [:]
    /// Each queued item's status, watched: an item that fails to load posts
    /// no notification at all, and would stay in queuedChunk for good.
    private var itemWatches: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var queuedWords: [Int: [ClipWord]] = [:]
    private var nextToQueue = 0
    private var seekChunk: Int?
    private var seekLine = 0
    private var onCloud = false
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    private var sessionWatch: [NSObjectProtocol] = []

    // the phone's voice
    private struct PhoneLine {
        let line: Int
        let first: Int
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var utterances: [ObjectIdentifier: PhoneLine] = [:]
    private var nextPhoneLine = 0
    private var phoneNeedsRestart = false
    /// Where the phone stops and hands back to the cloud: the end of the clip
    /// it is standing in for. Nil when the cloud cannot be used at all (not
    /// Pro, Arabic, switched off) and the phone reads to the end.
    private var phoneLimit: Int?
    private lazy var arabicVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "ar-SA")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// A phone call stops the lecture in place, and it carries on after the
    /// call when the system says to; headphones pulled out pause it.
    private func listen() {
        if sessionWatch.isEmpty {
            sessionWatch = NowPlaying.watch(interrupted: { [weak self] in self?.interrupted() },
                                            mayResume: { [weak self] in self?.resumeAfterInterruption() },
                                            unplugged: { [weak self] in self?.pause() })
        }
        guard observers.isEmpty else { return }
        let center: NotificationCenter = NotificationCenter.default
        let ended: NSObjectProtocol = center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            MainActor.assumeIsolated { self?.itemEnded(id) }
        }
        // a clip that cannot play never posts "played to the end": without
        // this its chunk stays queued for good and the lecture falls silent
        let broke: NSObjectProtocol = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            MainActor.assumeIsolated { self?.itemFailed(id) }
        }
        observers = [ended, broke]
    }

    private func unlisten() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        NowPlaying.unwatch(sessionWatch)
        sessionWatch = []
    }

    private func interrupted() {
        guard playing else { return }
        pause()
        pausedByInterruption = true
    }

    private func resumeAfterInterruption() {
        guard pausedByInterruption else { return }
        resume()
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
        pausedByInterruption = false
        playing = true
        spot = NarrateSpot(line: start, word: nil)
        sleepMoved?()
        // a Play is a fresh try: a clip that failed in a network drop is
        // asked for again rather than left to the phone for good
        failed = []
        NowPlaying.activate()
        listen()
        attachRemote()
        if cloudUsable {
            startCloud(at: start)
        } else {
            // resting after a refusal: the phone reads clip by clip, and the
            // cloud takes over again at a clip's edge once the rest is over
            startPhone(at: start, word: 0, until: cloudEligible ? standInEnd(forLine: start) : nil)
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
        pausedByInterruption = false
        playing = true
        NowPlaying.activate()
        listen()
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
            startPhone(at: spot.line, word: spot.word ?? 0, until: phoneLimit)
        }
        showNowPlaying()
    }

    func pause() {
        guard playing else { return }
        playing = false
        paused = true
        pausedByInterruption = false
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
        sleepMoved?()
    }

    // MARK: sections

    /// The lecture's sections, worked out by the screen once per transcript.
    func setChapters(_ made: [AudioChapter]) {
        chapters = made
        section = nil
        lineMoved()
    }

    var hasSections: Bool { chapters.count >= 2 }

    func nextSection() {
        let here: Int? = AudioChapters.index(containingLine: spot.line, in: chapters)
        guard let next = AudioChapters.next(after: here, in: chapters) else { return }
        jump(to: chapters[next].lines.lowerBound)
    }

    /// Back to this section's first line, or to the one before from there.
    func previousSection() {
        guard let back = AudioChapters.previous(fromLine: spot.line, in: chapters) else { return }
        jump(to: chapters[back].lines.lowerBound)
    }

    func jump(toSection i: Int) {
        guard chapters.indices.contains(i) else { return }
        jump(to: chapters[i].lines.lowerBound)
    }

    /// A new line may be a new section, which the lock screen shows.
    private func lineMoved() {
        let now: Int? = hasSections ? AudioChapters.index(containingLine: spot.line, in: chapters) : nil
        guard now != section else { return }
        section = now
        showNowPlaying()
    }

    /// A new speed takes effect at once: the cloud clip is sped up in place,
    /// and the phone's voice starts again from the word it was on (a
    /// synthesizer cannot change the rate of a line it has started).
    func setSpeed(_ chosen: Double) {
        let newSpeed: Double = AudioRate.snapped(chosen)
        guard newSpeed != speed else { return }
        speed = newSpeed
        if onCloud {
            queue?.defaultRate = Float(newSpeed)
            if playing, queue?.currentItem != nil { queue?.rate = Float(newSpeed) }
        } else if playing {
            startPhone(at: spot.line, word: spot.word ?? 0, until: phoneLimit)
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
        itemWatches = [:]
        queuedWords = [:]
        seekChunk = nil
        onCloud = false
        waiting = false
        utterances = [:]
        silencePhone()
        phoneNeedsRestart = false
        phoneLimit = nil
    }

    // MARK: the cloud voice

    private var cloudUsable: Bool {
        guard Date() >= Self.cloudRestUntil, !chunks.isEmpty else { return false }
        // Aura-2 speaks English; an Arabic line is the phone's
        guard !langs.contains("ar") else { return false }
        return cloud.available
    }

    /// The cloud could read this lecture, if not necessarily right now.
    private var cloudEligible: Bool {
        !chunks.isEmpty && !langs.contains("ar") && cloud.eligible
    }

    private func standInEnd(forLine line: Int) -> Int? {
        NarratePlan.standInEnd(forLine: line, in: chunks)
    }

    /// The phone reads chunk `k` - from `line`, or its start - and only that;
    /// the clips after it are fetched meanwhile, so the cloud can take the
    /// next one straight back.
    private func standIn(for k: Int, from line: Int? = nil, word: Int = 0) {
        let first: Int = line ?? chunks[k].lines.lowerBound
        startPhone(at: first, word: word, until: chunks[k].lines.upperBound)
        prefetch(after: k)
    }

    /// Fetches the clips after chunk `k`, retrying any that failed before -
    /// the cloud is usable again, so a clip lost in a network drop is worth
    /// another request.
    private func prefetch(after k: Int) {
        guard cloudUsable else { return }
        let upper: Int = min(chunks.count, k + 1 + Self.ahead)
        guard k + 1 < upper else { return }
        for next in (k + 1)..<upper {
            failed.remove(chunks[next].text)
            fetch(next)
        }
    }

    /// Whether the cloud can read from `line` straight away: usable, and the
    /// clip it starts is already here.
    private func cloudReady(at line: Int) -> Bool {
        guard cloudUsable, let c = NarratePlan.chunkIndex(containing: line, in: chunks) else { return false }
        return clips[chunks[c].text] != nil
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
        // the phone reads on clip by clip, and hands back once the rest is over
        startPhone(at: spot.line, word: 0, until: standInEnd(forLine: spot.line))
    }

    private func ensureQueue() -> AVQueuePlayer {
        if let queue { return queue }
        let made = AVQueuePlayer()
        made.volume = fade
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
            // the cache may have lost it since it arrived: fetch it again
            // rather than queue an item that can only fail
            guard FileManager.default.fileExists(atPath: clip.url.path) else {
                clips[text] = nil
                fetch(nextToQueue)
                break
            }
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
        // the phone reads that clip, and the cloud takes the one after it
        if queuedChunk.isEmpty, nextToQueue < chunks.count,
           failed.contains(chunks[nextToQueue].text), playing {
            // from the tapped line when the reading started inside this clip
            let from: Int? = seekChunk == nextToQueue ? seekLine : nil
            standIn(for: nextToQueue, from: from)
        }
    }

    private func enqueue(_ k: Int, _ clip: NarrateClip, in queue: AVQueuePlayer) {
        let item = AVPlayerItem(url: clip.url)
        // the speech-friendly way to change speed without changing pitch
        item.audioTimePitchAlgorithm = .timeDomain
        let words: [ClipWord] = NarratePlan.wordTimes(lines: lines, range: chunks[k].lines,
                                                      duration: clip.duration)
        let id = ObjectIdentifier(item)
        queuedChunk[id] = k
        queuedWords[k] = words
        itemWatches[id] = item.observe(\.status, options: [.new]) { [weak self] watched, _ in
            guard watched.status == .failed else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.itemFailed(id) } }
        }
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
        // the clips this lecture holds are never pruned to make room
        let keep: Set<String> = Set(clips.values.map { $0.url.lastPathComponent })
        let task = Task { [weak self] in
            // runs off the main thread: the request, the file, the duration
            let got: (clip: NarrateClip?, rest: TimeInterval) = await NarrateVoice.download(text, token: token, keep: keep)
            if Task.isCancelled { return }
            self?.arrived(text, got.clip, rest: got.rest)
        }
        fetching[text] = task
    }

    private func arrived(_ text: String, _ clip: NarrateClip?, rest: TimeInterval) {
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
            // the server's own word for how long to leave it - an hour after
            // the day's allowance is used, not a minute - and every speaker
            // in the app hears it. Zero is "only this clip": no rest.
            if rest > 0 {
                let until: Date = Date().addingTimeInterval(max(rest, 60))
                Self.cloudRestUntil = max(Self.cloudRestUntil, until)
                CloudVoice.rest(rest)
            }
        }
        fillQueue()
    }

    private func itemEnded(_ id: ObjectIdentifier) {
        guard let k = queuedChunk.removeValue(forKey: id) else { return }
        itemWatches[id] = nil
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

    /// A clip that could not play (it failed to load, or part way through).
    ///
    /// It comes off the queue with every clip queued after it, and the queue
    /// is refilled from it: as `failed`, it is the phone's to read. The clip
    /// that was playing is read by the phone at once, from where the voice
    /// had got to; a later one, once the clips before it have played
    /// (fillQueue) - never by jumping ahead over them. Either way the cloud
    /// takes the next clip back.
    private func itemFailed(_ id: ObjectIdentifier) {
        guard let k = queuedChunk[id] else { return }
        let current: Int = queuedChunk.values.min() ?? k
        let text: String = chunks[k].text
        clips[text] = nil
        failed.insert(text)
        if let queue {
            for item in queue.items() {
                guard let j = queuedChunk[ObjectIdentifier(item)], j >= k else { continue }
                queue.remove(item)
            }
        }
        for (other, j) in queuedChunk where j >= k {
            queuedChunk[other] = nil
            itemWatches[other] = nil
            queuedWords[j] = nil
        }
        nextToQueue = k
        guard onCloud, k == current else { return }
        let from: Int = chunks[k].lines.contains(spot.line) ? spot.line : chunks[k].lines.lowerBound
        if playing {
            standIn(for: k, from: from, word: from == spot.line ? (spot.word ?? 0) : 0)
        } else if paused {
            // Play carries on with the phone reading this clip
            onCloud = false
            waiting = false
            phoneNeedsRestart = true
            phoneLimit = chunks[k].lines.upperBound
            if from != spot.line { spot = NarrateSpot(line: from, word: nil) }
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
    ///
    /// With no clip, how long the server asked to be left alone (CloudFetch's
    /// rest; zero when only this clip failed).
    nonisolated static func download(_ text: String, token: String,
                                     keep: Set<String>) async -> (clip: NarrateClip?, rest: TimeInterval) {
        let file: URL = cacheFile(for: text)
        if FileManager.default.fileExists(atPath: file.path),
           let seconds = await duration(of: file) {
            // heard again: the newest in the cache, not the oldest
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return (NarrateClip(url: file, duration: seconds), 0)
        }
        let answer: CloudFetch = await CloudVoice.fetch(text, patient: false, token: token)
        guard let clip = answer.clip else { return (nil, answer.rest) }
        do {
            try clip.data.write(to: file, options: .atomic)
        } catch {
            return (nil, 0)
        }
        prune(keeping: keep.union([file.lastPathComponent]))
        guard let seconds = await duration(of: file) else { return (nil, 0) }
        return (NarrateClip(url: file, duration: seconds), 0)
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

    /// A few lectures' worth is kept; the least recently heard go first, and
    /// never a clip the lecture being played holds (`keeping`, file names).
    nonisolated private static func prune(keeping: Set<String>) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let folder: URL = cacheFolder
        let found: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys)) ?? []
        let keep = 400
        guard found.count > keep else { return }
        let dated: [(name: String, used: Date)] = found.map { url in
            let date: Date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (name: url.lastPathComponent, used: date)
        }
        for name in NarratePlan.pruneList(dated, keep: keep, protected: keeping) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
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
    ///
    /// `until` is where the phone hands back to the cloud (phoneLimit): the
    /// end of the clip it is standing in for. Nil reads to the end.
    private func startPhone(at line: Int, word: Int, until: Int? = nil) {
        queue?.pause()
        queue?.removeAllItems()
        queuedChunk = [:]
        itemWatches = [:]
        queuedWords = [:]
        onCloud = false
        waiting = false
        utterances = [:]
        silencePhone()
        phoneNeedsRestart = false
        phoneLimit = until
        guard line < lines.count else {
            finish()
            return
        }
        speakLine(line, from: word)
        queuePhoneLines()
        if utterances.isEmpty { phoneRanOut() }
    }

    /// Lines queued three ahead - up to phoneLimit. At that clip's edge the
    /// cloud takes back over if its clip is here; if not (still resting, or
    /// still on its way) the phone reads on through the next clip too, with
    /// no pause, and asks again at that clip's end.
    private func queuePhoneLines() {
        while utterances.count < 3 && nextPhoneLine < lines.count {
            if let limit = phoneLimit, nextPhoneLine >= limit {
                if cloudReady(at: nextPhoneLine) { break }
                guard let c = NarratePlan.chunkIndex(containing: nextPhoneLine, in: chunks) else {
                    phoneLimit = nil
                    continue
                }
                phoneLimit = chunks[c].lines.upperBound
                prefetch(after: c)
            }
            speakLine(nextPhoneLine, from: 0)
        }
    }

    /// Nothing left queued on the phone: the lecture is over, or the phone
    /// has reached the clip the cloud reads.
    private func phoneRanOut() {
        if nextPhoneLine < lines.count, let limit = phoneLimit, nextPhoneLine >= limit, playing {
            startCloud(at: nextPhoneLine)
        } else if nextPhoneLine >= lines.count {
            finish()
        }
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
        queuePhoneLines()
        if utterances.isEmpty { phoneRanOut() }
    }

    fileprivate func phoneCancelled(_ id: ObjectIdentifier) {
        utterances[id] = nil
    }

    // MARK: the lock screen

    /// Play, Pause, the speed, and the headphones' next and previous moving
    /// by section. No skip by seconds: a voice reading line by line has no
    /// clock to skip along.
    private func attachRemote() {
        guard remote.isEmpty else { return }
        var actions = NowPlaying.Actions(play: { [weak self] in self?.resume() },
                                         pause: { [weak self] in self?.pause() },
                                         toggle: { [weak self] in self?.toggle() })
        actions.section = { [weak self] step in self?.stepSection(step) }
        actions.rate = { [weak self] chosen in self?.setSpeed(chosen) }
        remote = NowPlaying.handle(actions)
    }

    /// By section when the lecture has them, otherwise by line.
    private func stepSection(_ step: Int) {
        if hasSections {
            if step > 0 { nextSection() } else { previousSection() }
        } else {
            jump(to: spot.line + (step > 0 ? 1 : -1))
        }
    }

    private func showNowPlaying() {
        guard !remote.isEmpty else { return }
        var shown: NowPlaying.Section?
        if let section, chapters.indices.contains(section) {
            shown = NowPlaying.Section(index: section, count: chapters.count, title: chapters[section].title)
        }
        NowPlaying.show(title: title, playing: playing, rate: speed, section: shown)
    }
}

// The sleep timer counts lines for "the end of this section": a voice reading
// line by line has no clock that says when the section will end, so the time
// shown is an estimate and the stop waits for the line itself.
extension NarrateVoice: SleepTarget {
    var sleepPlaying: Bool { playing }

    func sleepSectionEnd() -> Double? {
        guard !lines.isEmpty else { return nil }
        guard let i = AudioChapters.index(containingLine: spot.line, in: chapters), hasSections else {
            return Double(lines.count)
        }
        return Double(chapters[i].lines.upperBound)
    }

    func sleepSecondsLeft(until end: Double) -> Double {
        if finished { return 0 }
        let endLine: Int = Int(end)
        return AudioChapters.secondsToRead(lines, line: spot.line, word: spot.word ?? 0,
                                           until: endLine, speed: speed)
    }

    func sleepFade(_ level: Float) {
        fade = level
        queue?.volume = level
    }

    func sleepFinish() {
        pause()
        fade = 1
        queue?.volume = 1
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
