import Foundation
import AVFoundation
import MediaPlayer

/// The lock screen and Control Center: what is playing, and its buttons.
///
/// A lecture is listened to with the phone in a pocket more often than not.
/// Background audio (UIBackgroundModes: audio) keeps it going; this is what
/// lets the student pause it, skip back, change speed or move to the next
/// section without unlocking the phone - and what the headphones' own
/// double and triple press (next and previous track) move by.
@MainActor
enum NowPlaying {

    /// Spoken audio: keeps playing with the phone locked and the ring switch
    /// on silent, and other apps' spoken audio (podcasts) pauses for it.
    static func activate() {
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    /// The section playing, for the lock screen's second line.
    struct Section {
        let index: Int
        let count: Int
        let title: String
    }

    static func show(title: String, playing: Bool, rate: Double,
                     elapsed: Double? = nil, duration: Double? = nil,
                     section: Section? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? rate : 0.0
        // the speed Play will use, so the lock screen's speed shows the
        // student's choice while paused rather than 1x
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
        if let elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let section {
            // zero-based, as MediaPlayer counts chapters
            info[MPNowPlayingInfoPropertyChapterNumber] = section.index
            info[MPNowPlayingInfoPropertyChapterCount] = section.count
            let place: String = "\(section.index + 1)/\(section.count)"
            info[MPMediaItemPropertyArtist] = place + " \u{00B7} " + section.title
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// What the lock screen's buttons do. Only Play, Pause and Play/Pause
    /// are needed; a button left nil is not shown.
    struct Actions {
        var play: @MainActor () -> Void
        var pause: @MainActor () -> Void
        var toggle: @MainActor () -> Void
        /// Seconds to move by: -15 or +30.
        var skip: (@MainActor (Double) -> Void)? = nil
        /// +1 for the next section, -1 for the previous.
        var section: (@MainActor (Int) -> Void)? = nil
        var rate: (@MainActor (Double) -> Void)? = nil
        /// The lock screen's scrub bar, in seconds.
        var position: (@MainActor (Double) -> Void)? = nil
    }

    /// Back fifteen, forward thirty: back is for "what did she just say",
    /// forward for skipping a tangent.
    static let back: Double = 15
    static let forward: Double = 30

    /// One button's handler, kept so `release` can take it off again.
    private struct Hook {
        let command: MPRemoteCommand
        let token: Any
    }

    /// Hooks the lock screen's buttons up. Keep what comes back and hand it to
    /// `release` when the screen goes, or the buttons keep calling a player
    /// that is gone.
    static func handle(play: @escaping @MainActor () -> Void,
                       pause: @escaping @MainActor () -> Void,
                       toggle: @escaping @MainActor () -> Void) -> [Any] {
        handle(Actions(play: play, pause: pause, toggle: toggle))
    }

    static func handle(_ actions: Actions) -> [Any] {
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        var hooks: [Hook] = []
        hooks.append(hook(center.playCommand, actions.play))
        hooks.append(hook(center.pauseCommand, actions.pause))
        hooks.append(hook(center.togglePlayPauseCommand, actions.toggle))
        if let skip = actions.skip {
            hooks.append(contentsOf: skipHooks(center, skip))
        }
        if let section = actions.section {
            hooks.append(hook(center.nextTrackCommand) { section(1) })
            hooks.append(hook(center.previousTrackCommand) { section(-1) })
        }
        if let rate = actions.rate {
            hooks.append(rateHook(center, rate))
        }
        if let position = actions.position {
            hooks.append(positionHook(center, position))
        }
        return hooks
    }

    private static func hook(_ command: MPRemoteCommand, _ run: @escaping @MainActor () -> Void) -> Hook {
        command.isEnabled = true
        let token: Any = command.addTarget { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { run() } }
            return .success
        }
        return Hook(command: command, token: token)
    }

    private static func skipHooks(_ center: MPRemoteCommandCenter,
                                  _ skip: @escaping @MainActor (Double) -> Void) -> [Hook] {
        let backCommand: MPSkipIntervalCommand = center.skipBackwardCommand
        let forwardCommand: MPSkipIntervalCommand = center.skipForwardCommand
        backCommand.preferredIntervals = [NSNumber(value: back)]
        forwardCommand.preferredIntervals = [NSNumber(value: forward)]
        let a: Hook = hook(backCommand) { skip(-back) }
        let b: Hook = hook(forwardCommand) { skip(forward) }
        return [a, b]
    }

    private static func rateHook(_ center: MPRemoteCommandCenter,
                                 _ rate: @escaping @MainActor (Double) -> Void) -> Hook {
        let command: MPChangePlaybackRateCommand = center.changePlaybackRateCommand
        command.supportedPlaybackRates = AudioRate.steps.map { NSNumber(value: $0) }
        command.isEnabled = true
        let token: Any = command.addTarget { event in
            guard let change = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let chosen: Double = Double(change.playbackRate)
            DispatchQueue.main.async { MainActor.assumeIsolated { rate(chosen) } }
            return .success
        }
        return Hook(command: command, token: token)
    }

    private static func positionHook(_ center: MPRemoteCommandCenter,
                                     _ position: @escaping @MainActor (Double) -> Void) -> Hook {
        let command: MPChangePlaybackPositionCommand = center.changePlaybackPositionCommand
        command.isEnabled = true
        let token: Any = command.addTarget { event in
            guard let change = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds: Double = change.positionTime
            DispatchQueue.main.async { MainActor.assumeIsolated { position(seconds) } }
            return .success
        }
        return Hook(command: command, token: token)
    }

    /// Takes this player's buttons off again. Nothing hooked, nothing to do:
    /// a player that never played must not clear the card or the buttons of
    /// something else that is playing (Commute mode uses Next too).
    static func release(_ tokens: [Any]) {
        guard !tokens.isEmpty else { return }
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        let always: [MPRemoteCommand] = [center.playCommand, center.pauseCommand,
                                         center.togglePlayPauseCommand]
        for case let hook as Hook in tokens {
            hook.command.removeTarget(hook.token)
            // the optional buttons go with their player, so the next thing
            // to play does not show a skip or a speed it cannot do
            let kept: Bool = always.contains { $0 === hook.command }
            if !kept { hook.command.isEnabled = false }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: calls and headphones

    /// A phone call (or a Siri request, or an alarm) pauses the lecture; when
    /// it ends and the system says to carry on, it carries on. Headphones
    /// pulled out pause it, rather than a lecture suddenly playing out loud
    /// on the bus. Keep what comes back and hand it to `unwatch`.
    static func watch(interrupted: @escaping @MainActor () -> Void,
                      mayResume: @escaping @MainActor () -> Void,
                      unplugged: @escaping @MainActor () -> Void) -> [NSObjectProtocol] {
        let center: NotificationCenter = NotificationCenter.default
        let calls: NSObjectProtocol = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw: UInt = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let kind: AVAudioSession.InterruptionType? = AVAudioSession.InterruptionType(rawValue: raw)
            let flags: UInt = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let resume: Bool = AVAudioSession.InterruptionOptions(rawValue: flags).contains(.shouldResume)
            MainActor.assumeIsolated {
                if kind == .began { interrupted() }
                if kind == .ended && resume { mayResume() }
            }
        }
        let route: NSObjectProtocol = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let raw: UInt = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let reason: AVAudioSession.RouteChangeReason? = AVAudioSession.RouteChangeReason(rawValue: raw)
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { unplugged() }
        }
        return [calls, route]
    }

    static func unwatch(_ observers: [NSObjectProtocol]) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
