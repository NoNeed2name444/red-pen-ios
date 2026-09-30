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

    let clock = LectureClock()
    var time: Double { clock.time }

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var timeline: [TranscriptWord] = []
    private var remote: [Any] = []
    private var title = "Lecture"

    /// How often the highlight is allowed to move. Fifteen times a second is
    /// past what anyone perceives as lag and a fraction of the work of a
    /// display link.
    private let tick = 1.0 / 15.0

    var hasAudio: Bool { player != nil }

    /// Where every word is in the recording. Laid out once when the
    /// transcript changes - not on every tick, which is what it used to cost.
    func setTimeline(_ words: [TranscriptWord]) {
        timeline = words
        syncTime()
    }

    func load(_ url: URL, title newTitle: String = "Lecture") {
        stop()
        title = newTitle
        do {
            // .playback so the lecture keeps going with the phone locked and
            // is not silenced by the ring switch - a student listens with the
            // screen off more often than not.
            NowPlaying.activate()
            let made = try AVAudioPlayer(contentsOf: url)
            made.enableRate = true
            made.prepareToPlay()
            made.delegate = self
            player = made
            duration = made.duration
            clock.time = 0
            failure = nil
        } catch {
            Diagnostics.record(.error, area: .audio, message: "lecture_player.open_failed", error: error)
            player = nil
            duration = 0
            failure = error.localizedDescription
        }
    }

    func play(rate: Double = 1) {
        guard let player else { return }
        NowPlaying.activate()
        player.rate = Float(rate)
        player.play()
        playing = true
        startTicking()
        attachRemote()
        showNowPlaying()
    }

    func pause() {
        player?.pause()
        playing = false
        ticker?.invalidate()
        syncTime()
        showNowPlaying()
    }

    func toggle(rate: Double = 1) {
        playing ? pause() : play(rate: rate)
    }

    func setRate(_ rate: Double) {
        player?.rate = Float(rate)
        showNowPlaying()
    }

    /// Jump to a moment - a tapped line, or a scrub.
    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        syncTime()
        showNowPlaying()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playing = false
        clock.time = 0
        duration = 0
        spot = nil
        NowPlaying.release(remote)
        remote = []
    }

    private func startTicking() {
        ticker?.invalidate()
        let made = Timer(timeInterval: tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTime() }
        }
        made.tolerance = tick / 4
        // .common, not the default mode: a default-mode timer stops while the
        // transcript is being scrolled, so the highlight froze under the
        // student's finger and then jumped
        RunLoop.main.add(made, forMode: .common)
        ticker = made
    }

    private func syncTime() {
        guard let player else { return }
        let now: Double = player.currentTime
        clock.time = now
        publishSpot(at: now)
    }

    private func publishSpot(at t: Double) {
        guard let word = WordTiming.word(at: t, in: timeline) else {
            if spot != nil { spot = nil }
            return
        }
        let next = NarrateSpot(line: word.segment, word: word.index)
        if next != spot { spot = next }
    }

    fileprivate func ended() {
        playing = false
        ticker?.invalidate()
        // park on the end rather than snapping to zero, so the last line
        // stays highlighted when the lecture finishes
        clock.time = duration
        publishSpot(at: duration)
        showNowPlaying()
    }

    // MARK: the lock screen

    private func attachRemote() {
        guard remote.isEmpty else { return }
        remote = NowPlaying.handle(play: { [weak self] in self?.resumeAtRate() },
                                   pause: { [weak self] in self?.pause() },
                                   toggle: { [weak self] in self?.toggleAtRate() })
    }

    /// The lock screen's Play keeps the speed the student chose.
    private var currentRate: Double {
        let rate: Float = player?.rate ?? 1
        return rate > 0 ? Double(rate) : 1
    }

    private func resumeAtRate() { play(rate: currentRate) }

    private func toggleAtRate() { toggle(rate: currentRate) }

    private func showNowPlaying() {
        guard !remote.isEmpty, let player else { return }
        NowPlaying.show(title: title, playing: playing, rate: Double(player.rate),
                        elapsed: player.currentTime, duration: player.duration)
    }
}

extension LecturePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.ended() }
    }
}
