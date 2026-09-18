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
@MainActor
final class LecturePlayer: NSObject, ObservableObject {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var failure: String?

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// How often the highlight is allowed to move. Fifteen times a second is
    /// past what anyone perceives as lag and a fraction of the work of a
    /// display link, which would redraw the whole transcript at 120Hz for a
    /// highlight that changes a couple of times a second.
    private let tick = 1.0 / 15.0

    var hasAudio: Bool { player != nil }

    func load(_ url: URL) {
        stop()
        do {
            // .playback so the lecture keeps going with the phone locked and
            // is not silenced by the ring switch - a student listens with the
            // screen off more often than not.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let made = try AVAudioPlayer(contentsOf: url)
            made.enableRate = true
            made.prepareToPlay()
            made.delegate = self
            player = made
            duration = made.duration
            time = 0
            failure = nil
        } catch {
            player = nil
            duration = 0
            failure = error.localizedDescription
        }
    }

    func play(rate: Double = 1) {
        guard let player else { return }
        player.rate = Float(rate)
        player.play()
        playing = true
        startTicking()
    }

    func pause() {
        player?.pause()
        playing = false
        ticker?.invalidate()
        syncTime()
    }

    func toggle(rate: Double = 1) {
        playing ? pause() : play(rate: rate)
    }

    func setRate(_ rate: Double) {
        player?.rate = Float(rate)
    }

    /// Jump to a moment - a tapped line, or a scrub.
    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        syncTime()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playing = false
        time = 0
        duration = 0
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncTime() }
        }
    }

    private func syncTime() {
        guard let player else { return }
        time = player.currentTime
    }
}

extension LecturePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playing = false
            ticker?.invalidate()
            // park on the end rather than snapping to zero, so the last line
            // stays highlighted when the lecture finishes
            time = duration
        }
    }
}
