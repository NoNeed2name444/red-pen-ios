import Foundation
import AVFoundation
import MediaPlayer

/// The lock screen and Control Center: what is playing, and Play/Pause.
///
/// A lecture is listened to with the phone in a pocket more often than not.
/// Background audio (UIBackgroundModes: audio) keeps it going; this is what
/// lets the student pause it without unlocking the phone.
@MainActor
enum NowPlaying {

    /// Spoken audio: keeps playing with the phone locked and the ring switch
    /// on silent, and other apps' spoken audio (podcasts) pauses for it.
    static func activate() {
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    static func show(title: String, playing: Bool, rate: Double,
                     elapsed: Double? = nil, duration: Double? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? rate : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if let elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Hooks the lock screen's buttons up. Keep what comes back and hand it to
    /// `release` when the screen goes, or the buttons keep calling a player
    /// that is gone.
    static func handle(play: @escaping @MainActor () -> Void,
                       pause: @escaping @MainActor () -> Void,
                       toggle: @escaping @MainActor () -> Void) -> [Any] {
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        let a: Any = center.playCommand.addTarget { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { play() } }
            return .success
        }
        let b: Any = center.pauseCommand.addTarget { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { pause() } }
            return .success
        }
        let c: Any = center.togglePlayPauseCommand.addTarget { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { toggle() } }
            return .success
        }
        return [a, b, c]
    }

    static func release(_ tokens: [Any]) {
        guard tokens.count == 3 else { return }
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(tokens[0])
        center.pauseCommand.removeTarget(tokens[1])
        center.togglePlayPauseCommand.removeTarget(tokens[2])
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
