import Foundation

/// What a player does when the phone's audio changes under it: a call or an
/// alarm takes the audio, or the headphones go.
///
/// Pure, so it is tested on Linux; NowPlaying.watch turns the system's
/// notifications into `Signal`s. Without this a call left commute mode
/// waiting on a sentence that never finished, the lecture player kept
/// showing "playing" (audit #76), and pulled-out headphones or AirPods
/// running flat sent a lecture on through the loudspeaker (audit #77).
enum AudioEvents {

    enum Signal: Equatable {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        /// The raw AVAudioSession.RouteChangeReason.
        case routeChanged(reason: UInt)
    }

    enum Reaction: Equatable { case pause, resume, nothing }

    /// AVAudioSession.RouteChangeReason.oldDeviceUnavailable: the headphones
    /// were unplugged or the Bluetooth device went.
    static let deviceLost: UInt = 2

    /// `playing`: whether it is playing now; `resumeLater`: whether it was
    /// playing when an interruption began. Returns what to do, and the new
    /// `resumeLater` to keep.
    ///
    /// After a call it carries on only if it was playing and the system says
    /// it may. Headphones going pauses for good: whoever pulled them out did
    /// not ask for the loudspeaker.
    static func reaction(to signal: Signal, playing: Bool,
                         resumeLater: Bool) -> (reaction: Reaction, resumeLater: Bool) {
        switch signal {
        case .interruptionBegan:
            return (playing ? .pause : .nothing, playing)
        case .interruptionEnded(let shouldResume):
            return (shouldResume && resumeLater && !playing ? .resume : .nothing, false)
        case .routeChanged(let reason):
            guard reason == deviceLost else { return (.nothing, resumeLater) }
            return (playing ? .pause : .nothing, false)
        }
    }
}
