import AudioToolbox
import AVFoundation
import CoreHaptics
import MediaPlayer
import SwiftUI
import UIKit

// MARK: - A small vocabulary of touch and sound
//
// Five cues, each with its own feel, so a right answer, a reveal, a lift-off
// and a finished session are told apart in the hand:
//
//   correct   success notification           + a rising fifth
//   wrong     warning (not error)            + a low, muted thunk (no buzzer)
//   reveal    a soft half-strength tap       (no sound: it happens constantly)
//   liftOff   a light tap                    + a soft rising sweep
//   complete  a swell that locks in (Core Haptics, built in code; .success
//             where there is no Taptic Engine) + a three-note chime
//
// Haptics follow the system's own haptics setting. Sounds are OFF unless the
// "Sounds" setting is on, and even then:
//
// - they are system sounds (AudioServicesPlaySystemSound), so they obey the
//   Ring/Silent switch, mix with other audio and never touch the app's
//   AVAudioSession - which the voice modes (.playAndRecord) and narration
//   (.playback) configure for themselves and must not have taken from them;
// - they stay quiet while narration is playing (Now Playing rate > 0), while
//   the system asks secondary audio to be silenced, and while any screen has
//   asked for quiet with `.spaceSoundsHushed()`.
//
// The tones are synthesized in code the first time (a sine with a light
// second harmonic, fast attack, exponential decay, under -18 dBFS and under
// half a second), written as tiny WAVs to Caches and registered once.

enum SpaceCue: String, CaseIterable {
    case correct, wrong, reveal, liftOff, complete
}

@MainActor
enum SpaceFeedback {
    /// The cue's haptic, and its sound when sounds are allowed.
    static func play(_ cue: SpaceCue) {
        haptic(cue)
        SpaceSounds.shared.play(cue)
    }

    static func haptic(_ cue: SpaceCue) {
        switch cue {
        case .correct:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .wrong:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .reveal:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        case .liftOff:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .complete:
            if !SpaceHaptics.shared.playComplete() {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

extension View {
    /// Plays `cue` (haptic and, when allowed, sound) each time `trigger`
    /// changes to a value that passes `when`.
    func spaceFeedback<T: Equatable>(_ cue: SpaceCue, trigger: T,
                                     when: @escaping (T) -> Bool = { _ in true }) -> some View {
        onChange(of: trigger) { _, now in
            if when(now) { SpaceFeedback.play(cue) }
        }
    }

    /// Keeps the sounds quiet while this screen is showing (voice, narration,
    /// recording).
    func spaceSoundsHushed() -> some View {
        modifier(SpaceSoundsHush())
    }
}

private struct SpaceSoundsHush: ViewModifier {
    @State private var token = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear { SpaceSounds.shared.hush(token) }
            .onDisappear { SpaceSounds.shared.unhush(token) }
    }
}

// MARK: - Core Haptics: the session-complete swell

@MainActor
final class SpaceHaptics {
    static let shared = SpaceHaptics()

    private var engine: CHHapticEngine?

    private init() {}

    /// A continuous swell 0.2 to 0.6 over 0.35 s, then a crisp tap - an
    /// orbit locking in. False when the device cannot play it.
    func playComplete() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            let engine: CHHapticEngine = try readyEngine()
            let pattern: CHHapticPattern = try SpaceHaptics.completePattern()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            self.engine = nil
            return false
        }
    }

    private func readyEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let made = try CHHapticEngine()
        made.isAutoShutdownEnabled = true
        made.playsHapticsOnly = true
        made.resetHandler = { [weak made] in
            try? made?.start()
        }
        try made.start()
        engine = made
        return made
    }

    private static func completePattern() throws -> CHHapticPattern {
        let softness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        let base = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let swell = CHHapticEvent(eventType: .hapticContinuous, parameters: [base, softness],
                                  relativeTime: 0, duration: 0.35)
        let hit = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let crisp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        let lock = CHHapticEvent(eventType: .hapticTransient, parameters: [hit, crisp],
                                 relativeTime: 0.36)
        let start = CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.2)
        let end = CHHapticParameterCurve.ControlPoint(relativeTime: 0.35, value: 0.6)
        let ramp = CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                          controlPoints: [start, end], relativeTime: 0)
        return try CHHapticPattern(events: [swell, lock], parameterCurves: [ramp])
    }
}

// MARK: - The sounds

@MainActor
final class SpaceSounds {
    static let shared = SpaceSounds()

    private var ids: [SpaceCue: SystemSoundID] = [:]
    private var hushTokens: Set<String> = []
    private var preparing = false

    private init() {}

    func hush(_ token: String) { hushTokens.insert(token) }

    func unhush(_ token: String) { hushTokens.remove(token) }

    func play(_ cue: SpaceCue) {
        guard cue != .reveal, allowed() else { return }
        if let id = ids[cue] {
            AudioServicesPlaySystemSound(id)
            return
        }
        // the first time: make them all, then this one plays next time
        prepare()
    }

    private func allowed() -> Bool {
        guard SpaceSettings.sounds, hushTokens.isEmpty else { return false }
        let session = AVAudioSession.sharedInstance()
        if session.secondaryAudioShouldBeSilencedHint { return false }
        let info: [String: Any]? = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let rate: Double = info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0
        return rate <= 0
    }

    /// Writes and registers the WAVs, off the main thread.
    func prepare() {
        guard !preparing, ids.isEmpty else { return }
        preparing = true
        Task.detached(priority: .utility) {
            var made: [(SpaceCue, URL)] = []
            for cue in SpaceCue.allCases where cue != .reveal {
                if let url = ToneSynth.file(for: cue) { made.append((cue, url)) }
            }
            let ready = made
            await MainActor.run {
                SpaceSounds.shared.register(ready)
            }
        }
    }

    private func register(_ files: [(SpaceCue, URL)]) {
        for (cue, url) in files {
            var id: SystemSoundID = 0
            let status: OSStatus = AudioServicesCreateSystemSoundID(url as CFURL, &id)
            if status == noErr { ids[cue] = id }
        }
        preparing = false
    }
}

/// The tones, synthesized into PCM buffers and written as 16-bit WAVs.
nonisolated enum ToneSynth {
    static let rate: Double = 44_100
    /// About -18 dBFS.
    static let peak: Float = 0.125

    static func file(for cue: SpaceCue) -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir: URL = caches.appendingPathComponent("SkyTones", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url: URL = dir.appendingPathComponent("cue-v1-\(cue.rawValue).wav")
        if fm.fileExists(atPath: url.path) { return url }
        let samples: [Float] = render(cue)
        return write(samples, to: url) ? url : nil
    }

    static func render(_ cue: SpaceCue) -> [Float] {
        switch cue {
        case .correct:
            var out = silence(0.22)
            add(&out, note(660, at: 0, length: 0.12, decay: 0.05))
            add(&out, note(990, at: 0.07, length: 0.15, decay: 0.06))
            return out
        case .wrong:
            var out = silence(0.18)
            add(&out, thunk(at: 0, length: 0.16))
            return out
        case .complete:
            var out = silence(0.5)
            add(&out, note(523.25, at: 0, length: 0.3, decay: 0.12))
            add(&out, note(659.25, at: 0.09, length: 0.3, decay: 0.12))
            add(&out, note(783.99, at: 0.18, length: 0.32, decay: 0.13))
            add(&out, note(786.99, at: 0.18, length: 0.32, decay: 0.13), gain: 0.35)
            return out
        case .liftOff:
            return sweep(from: 300, to: 900, length: 0.26)
        case .reveal:
            return silence(0.01)
        }
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    private static func add(_ out: inout [Float], _ part: (start: Int, samples: [Float]), gain: Float = 1) {
        for (i, s) in part.samples.enumerated() {
            let at: Int = part.start + i
            guard at < out.count else { break }
            out[at] += s * gain
        }
    }

    /// A sine with a light second harmonic, 5 ms attack, exponential decay.
    private static func note(_ hz: Double, at: Double, length: Double, decay: Double) -> (start: Int, samples: [Float]) {
        let count: Int = Int(length * rate)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t: Double = Double(i) / rate
            let attack: Double = min(1, t / 0.005)
            let envelope: Double = attack * exp(-t / decay)
            let phase: Double = 2 * Double.pi * hz * t
            let wave: Double = sin(phase) + 0.2 * sin(2 * phase)
            samples[i] = Float(wave * envelope) * peak * 0.8
        }
        return (start: Int(at * rate), samples: samples)
    }

    /// A low, soft knock whose pitch falls: 196 Hz to 150 Hz.
    private static func thunk(at: Double, length: Double) -> (start: Int, samples: [Float]) {
        let count: Int = Int(length * rate)
        var samples = [Float](repeating: 0, count: count)
        var phase: Double = 0
        for i in 0..<count {
            let t: Double = Double(i) / rate
            let hz: Double = 150 + 46 * exp(-t / 0.04)
            phase += 2 * Double.pi * hz / rate
            let attack: Double = min(1, t / 0.004)
            let envelope: Double = attack * exp(-t / 0.045)
            samples[i] = Float(sin(phase) * envelope) * peak
        }
        return (start: Int(at * rate), samples: samples)
    }

    /// A soft rising sweep, faded in and out.
    private static func sweep(from low: Double, to high: Double, length: Double) -> [Float] {
        let count: Int = Int(length * rate)
        var samples = [Float](repeating: 0, count: count)
        var phase: Double = 0
        for i in 0..<count {
            let t: Double = Double(i) / rate
            let x: Double = t / length
            let hz: Double = low + (high - low) * x * x
            phase += 2 * Double.pi * hz / rate
            let envelope: Double = sin(Double.pi * x)
            samples[i] = Float(sin(phase) * envelope) * peak * 0.5
        }
        return samples
    }

    private static func write(_ samples: [Float], to url: URL) -> Bool {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return false }
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return false }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return false }
        for (i, s) in samples.enumerated() {
            channel[i] = max(-1, min(1, s))
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }
}
