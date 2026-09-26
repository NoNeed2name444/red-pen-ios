import Foundation
import AVFoundation
import Combine

/// Playing the lecture recording, and saying where it is.
///
/// The reading-pace player runs its own stopwatch and advances a line when the
/// time is up. That cannot work against a real recording: the moment the
/// student scrubs, pauses, or changes speed, a separate stopwatch and the audio
/// disagree, and the highlight ends up confidently pointing at the wrong word.
/// So there is exactly one clock here and it belongs to the audio -
/// `currentTime` is asked of the player itself, never accumulated.
///
/// An AVPlayer rather than an AVAudioPlayer: the audio player tops out at 2x,
/// and a lecture heard for the second time is often heard at 2.5x. The
/// time-domain pitch algorithm keeps the lecturer's voice at its own pitch at
/// every speed - the one made for speech.
///
/// Playback is on the device and the file stays on the device. Nothing here
/// uploads, streams or phones anywhere.
/// The audio's position, on its own.
///
/// It changes fifteen times a second. Only the scrub bar needs that; if it
/// were published by LecturePlayer, every view watching the player - the whole
/// Narrate screen, transcript and all - would be rebuilt fifteen times a
/// second for a highlight that moves two or three times.
@MainActor
final class LectureClock: ObservableObject {
    @Published var time: Double = 0
}

@MainActor
final class LecturePlayer: NSObject, ObservableObject {
    @Published private(set) var duration: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var failure: String?
    /// The word being spoken, published only when it changes.
    @Published private(set) var spot: NarrateSpot?
    /// The speed, as chosen here or on the lock screen.
    @Published private(set) var rate: Double = 1
    /// The section playing, published only when it changes.
    @Published private(set) var section: Int?

    let clock = LectureClock()
    var time: Double { clock.time }
    /// Told when the student moves the place by hand, so a sleep timer set
    /// for "the end of this section" follows them to the new one.
    var sleepMoved: (@MainActor () -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemWatch: NSKeyValueObservation?
    private var endWatch: NSObjectProtocol?
    private var sessionWatch: [NSObjectProtocol] = []
    private var timeline: [TranscriptWord] = []
    /// The lecture's sections; only a timed transcript's can be jumped to.
    @Published private(set) var chapters: [AudioChapter] = []
    private var remote: [Any] = []
    private var title = "Lecture"
    /// Paused by a call, so the end of the call may carry on.
    private var pausedByInterruption = false
    /// Seeks not yet landed: until they have, the player still reports the
    /// old place, and the clock would jump back to it for a moment.
    private var seeksInFlight = 0

    /// How often the highlight is allowed to move. Fifteen times a second is
    /// past what anyone perceives as lag and a fraction of the work of a
    /// display link.
    private let tick = CMTime(value: 1, timescale: 15)

    var hasAudio: Bool { player != nil }

    /// Where every word is in the recording. Laid out once when the
    /// transcript changes - not on every tick, which is what it used to cost.
    func setTimeline(_ words: [TranscriptWord]) {
        timeline = words
        syncTime()
    }

    /// The lecture's sections; only timed ones can be jumped to.
    func setChapters(_ made: [AudioChapter]) {
        chapters = made.allSatisfy { $0.start != nil } ? made : []
        publishSection(at: time)
        showNowPlaying()
    }

    func load(_ url: URL, title newTitle: String = "Lecture") {
        stop()
        title = newTitle
        // .playback so the lecture keeps going with the phone locked and
        // is not silenced by the ring switch - a student listens with the
        // screen off more often than not.
        NowPlaying.activate()
        // precise timing: the word highlight is laid over these seconds, and
        // a compressed file's estimated times drift by whole words
        let options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let made = AVPlayer(playerItem: item)
        made.actionAtItemEnd = .pause
        made.defaultRate = Float(rate)
        player = made
        clock.time = 0
        failure = nil
        watch(item, in: made)
        Task { [weak self] in
            let length: Double? = await LecturePlayer.length(of: asset)
            self?.measured(length, for: item)
        }
    }

    nonisolated private static func length(of asset: AVURLAsset) async -> Double? {
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds: Double = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func measured(_ length: Double?, for item: AVPlayerItem) {
        guard let player, player.currentItem === item else { return }
        guard let length else {
            broke(nil)
            return
        }
        duration = length
        showNowPlaying()
    }

    private func watch(_ item: AVPlayerItem, in made: AVPlayer) {
        timeObserver = made.addPeriodicTimeObserver(forInterval: tick, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTime() }
        }
        // a file that cannot be played says so here, not when it was opened
        itemWatch = item.observe(\.status, options: [.new]) { [weak self] watched, _ in
            guard watched.status == .failed else { return }
            let error: Error? = watched.error
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.broke(error) } }
        }
        endWatch = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }
    }

    private func broke(_ error: Error?) {
        Diagnostics.record(.error, area: .audio, message: "lecture_player.open_failed", error: error)
        let message: String = error?.localizedDescription ?? "This recording can't be played."
        stop()
        failure = message
    }

    /// Play at the speed chosen. At the end, Play starts over.
    func play() {
        guard let player else { return }
        NowPlaying.activate()
        listen()
        pausedByInterruption = false
        if duration > 0, time >= duration - 0.05 { moveTo(0) }
        player.defaultRate = Float(rate)
        player.play()
        playing = true
        attachRemote()
        showNowPlaying()
    }

    func pause() {
        player?.pause()
        playing = false
        pausedByInterruption = false
        syncTime()
        showNowPlaying()
    }

    func toggle() {
        playing ? pause() : play()
    }

    /// A new speed takes effect at once, and is what Play uses next.
    func setRate(_ newRate: Double) {
        let chosen: Double = AudioRate.snapped(newRate)
        rate = chosen
        player?.defaultRate = Float(chosen)
        if playing { player?.rate = Float(chosen) }
        showNowPlaying()
    }

    /// Jump to a moment - a tapped line, a scrub, a skip, a section.
    func seek(to seconds: Double) {
        guard player != nil else { return }
        let end: Double = duration > 0 ? duration : max(0, seconds)
        moveTo(max(0, min(seconds, end)))
        sleepMoved?()
    }

    /// Back fifteen, forward thirty, or any other step.
    func skip(by seconds: Double) {
        seek(to: time + seconds)
    }

    // MARK: sections

    var hasSections: Bool { chapters.count >= 2 }

    func nextSection() {
        guard let next = AudioChapters.next(after: section, in: chapters),
              let start = chapters[next].start else { return }
        seek(to: start)
    }

    /// Back to this section's start, or to the one before when it has only
    /// just begun - as Back does on any player.
    func previousSection() {
        guard let back = AudioChapters.previous(fromTime: time, in: chapters),
              let start = chapters[back].start else { return }
        seek(to: start)
    }

    func jump(toSection i: Int) {
        guard chapters.indices.contains(i), let start = chapters[i].start else { return }
        seek(to: start)
    }

    func stop() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemWatch = nil
        if let endWatch { NotificationCenter.default.removeObserver(endWatch) }
        endWatch = nil
        NowPlaying.unwatch(sessionWatch)
        sessionWatch = []
        player?.pause()
        player = nil
        playing = false
        pausedByInterruption = false
        seeksInFlight = 0
        clock.time = 0
        duration = 0
        spot = nil
        section = nil
        NowPlaying.release(remote)
        remote = []
    }

    private func moveTo(_ target: Double) {
        guard let player else { return }
        let at = CMTime(seconds: target, preferredTimescale: 600)
        seeksInFlight += 1
        // exact: a tapped line should start on its first word, not near it
        player.seek(to: at, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.seekLanded() } }
        }
        // the clock shows the new place at once, not when the seek lands
        clock.time = target
        publishSpot(at: target)
        publishSection(at: target)
        showNowPlaying()
    }

    private func seekLanded() {
        seeksInFlight = max(0, seeksInFlight - 1)
        if seeksInFlight == 0 { syncTime() }
    }

    private func syncTime() {
        guard let player, seeksInFlight == 0 else { return }
        let now: Double = player.currentTime().seconds
        guard now.isFinite else { return }
        clock.time = now
        publishSpot(at: now)
        publishSection(at: now)
    }

    private func publishSpot(at t: Double) {
        guard let word = WordTiming.word(at: t, in: timeline) else {
            if spot != nil { spot = nil }
            return
        }
        let next = NarrateSpot(line: word.segment, word: word.index)
        if next != spot { spot = next }
    }

    /// A new section also updates the lock screen, which says which it is.
    private func publishSection(at t: Double) {
        let now: Int? = hasSections ? AudioChapters.index(atTime: t, in: chapters) : nil
        guard now != section else { return }
        section = now
        showNowPlaying()
    }

    fileprivate func ended() {
        playing = false
        // park on the end rather than snapping to zero, so the last line
        // stays highlighted when the lecture finishes
        clock.time = duration
        publishSpot(at: duration)
        showNowPlaying()
    }

    // MARK: calls and headphones

    private func listen() {
        guard sessionWatch.isEmpty else { return }
        sessionWatch = NowPlaying.watch(interrupted: { [weak self] in self?.interrupted() },
                                        mayResume: { [weak self] in self?.resumeAfterInterruption() },
                                        unplugged: { [weak self] in self?.pause() })
    }

    private func interrupted() {
        guard playing else { return }
        pause()
        pausedByInterruption = true
    }

    private func resumeAfterInterruption() {
        guard pausedByInterruption else { return }
        play()
    }

    // MARK: the lock screen

    private func attachRemote() {
        guard remote.isEmpty else { return }
        var actions = NowPlaying.Actions(play: { [weak self] in self?.play() },
                                         pause: { [weak self] in self?.pause() },
                                         toggle: { [weak self] in self?.toggle() })
        actions.skip = { [weak self] seconds in self?.skip(by: seconds) }
        actions.section = { [weak self] step in self?.stepSection(step) }
        actions.rate = { [weak self] chosen in self?.setRate(chosen) }
        actions.position = { [weak self] seconds in self?.seek(to: seconds) }
        remote = NowPlaying.handle(actions)
    }

    /// The headphones' next and previous: by section when the lecture has
    /// them, otherwise the same skip as the buttons.
    private func stepSection(_ step: Int) {
        if hasSections {
            if step > 0 { nextSection() } else { previousSection() }
        } else {
            skip(by: step > 0 ? NowPlaying.forward : -NowPlaying.back)
        }
    }

    private func showNowPlaying() {
        guard !remote.isEmpty, player != nil else { return }
        var shown: NowPlaying.Section?
        if let section, chapters.indices.contains(section) {
            shown = NowPlaying.Section(index: section, count: chapters.count, title: chapters[section].title)
        }
        let length: Double? = duration > 0 ? duration : nil
        NowPlaying.show(title: title, playing: playing, rate: rate,
                        elapsed: time, duration: length, section: shown)
    }
}

// The sleep timer counts in the recording's own clock: the section ends at a
// moment in the recording, and a faster speed gets there sooner.
extension LecturePlayer: SleepTarget {
    var sleepPlaying: Bool { playing }

    func sleepSectionEnd() -> Double? {
        guard hasAudio, duration > 0 else { return nil }
        return AudioChapters.end(after: time, in: chapters, duration: duration)
    }

    func sleepSecondsLeft(until end: Double) -> Double {
        (end - time) / max(0.25, rate)
    }

    /// The player's own volume, not the phone's: the student's volume is
    /// just where they left it when they wake.
    func sleepFade(_ level: Float) {
        player?.volume = level
    }

    func sleepFinish() {
        pause()
        player?.volume = 1
    }
}
