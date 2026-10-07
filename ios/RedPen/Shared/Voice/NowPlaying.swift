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

    /// Hands the audio back, so the music or podcast it stopped can carry
    /// on. Call when the screen that played goes (audit #78).
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Calls (or alarms) taking the audio, and headphones going, as
    /// AudioEvents signals on the main actor (audit #76, #77). Hand what
    /// comes back to `unwatch` when the player goes.
    static func watch(_ react: @escaping @MainActor (AudioEvents.Signal) -> Void) -> [NSObjectProtocol] {
        let center: NotificationCenter = NotificationCenter.default
        let interrupted: NSObjectProtocol = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let type: UInt = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let options: UInt = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let resume: Bool = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            let signal: AudioEvents.Signal = AVAudioSession.InterruptionType(rawValue: type) == .began
                ? .interruptionBegan : .interruptionEnded(shouldResume: resume)
            MainActor.assumeIsolated { react(signal) }
        }
        let rerouted: NSObjectProtocol = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason: UInt = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            MainActor.assumeIsolated { react(.routeChanged(reason: reason)) }
        }
        return [interrupted, rerouted]
    }

    static func unwatch(_ tokens: [NSObjectProtocol]) {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
