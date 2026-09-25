import Foundation
import AVFoundation
import Speech
import UIKit

/// Asking for the microphone and for speech recognition, and setting up the
/// audio session every spoken mode shares.
///
/// Both permissions are asked for only when a student presses a button that
/// needs them, never on launch: a prompt that arrives with no reason attached
/// is the one people refuse. And refusing is allowed - every spoken mode still
/// works without them, it just reads aloud and lets the student type or tap.
enum VoiceAccess {

    /// What the phone will let a spoken mode do.
    enum Hearing: Equatable {
        /// Microphone and recogniser both allowed.
        case ready
        /// One of them was refused; the text says which, and how to undo it.
        case refused(String)
        /// Nothing was refused, but the phone can't recognise speech right now.
        case unavailable(String)

        var canHear: Bool { self == .ready }

        var message: String? {
            switch self {
            case .ready: return nil
            case .refused(let why), .unavailable(let why): return why
            }
        }
    }

    static let micRefused = "\(Brand.name) can't hear you because microphone access is off. Turn it on in Settings \u{203A} \(Brand.name) \u{203A} Microphone. Until then everything is read aloud, and you answer by tapping or typing."
    static let speechRefused = "\(Brand.name) can't turn your voice into text because Speech Recognition is off. Turn it on in Settings \u{203A} \(Brand.name) \u{203A} Speech Recognition. Until then everything is read aloud, and you answer by tapping or typing."
    static let noRecogniser = "This phone has no speech recogniser for your language right now. Everything is still read aloud; answer by tapping or typing."

    /// Asks for whatever has not been decided yet, and says what came of it.
    static func request() async -> Hearing {
        guard await microphoneAllowed() else { return .refused(micRefused) }
        guard await speechAllowed() else { return .refused(speechRefused) }
        guard let recogniser = VoiceListener.makeRecogniser(), recogniser.isAvailable else {
            return .unavailable(noRecogniser)
        }
        return .ready
    }

    static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
    }

    static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// The app's own page in Settings, where both switches live.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: the audio session

    /// Speaking and listening in turn, with other audio turned down rather
    /// than stopped.
    ///
    /// `.playAndRecord` because the same session both reads aloud and listens;
    /// switching categories between the two is audible and slow. The app has
    /// the audio background mode, so with the session active a commute
    /// session carries on with the screen locked. The loudspeaker rather than
    /// the earpiece, because a phone on a car seat is not held to an ear.
    @discardableResult
    static func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker,
                                                       .allowBluetooth, .allowBluetoothA2DP]
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: options)
        } catch {
            // Some routes refuse the spoken-audio mode with recording; the
            // default mode still does everything that matters.
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: options)
            } catch {
                Diagnostics.record(.error, area: .audio, message: "audio.category_failed", error: error)
                return false
            }
        }
        do {
            try session.setActive(true)
            return true
        } catch {
            Diagnostics.record(.error, area: .audio, message: "audio.activate_failed", error: error)
            return false
        }
    }

    /// Hands the audio back, so whatever was ducked comes back up.
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
