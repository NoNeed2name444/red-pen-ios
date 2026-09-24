import Foundation
import AVFoundation
import Combine

/// Reading text aloud, one line at a time, and saying when the line is done.
///
/// `say` waits until the sentence has actually been spoken. That is what lets
/// commute mode and the spoken patient run as a plain sequence - speak the
/// question, then listen - instead of guessing how long a sentence takes and
/// starting the microphone over the end of it.
///
/// Two voices: the narrator (questions, the examiner) is the phone's own voice
/// for the language, and the patient is a different one, so a student with the
/// phone in a pocket can hear who is talking without looking.
@MainActor
final class VoiceSpeaker: NSObject, ObservableObject {

    enum Role { case narrator, patient }

    @Published private(set) var speaking = false

    /// Slightly under the default pace: medical words read at full speed run
    /// together, and a listener cannot scroll back.
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.95

    private let synthesizer = AVSpeechSynthesizer()
    private var waiting: CheckedContinuation<Void, Never>?
    /// Which utterance the current wait belongs to. A cancelled line reports
    /// its end a moment later; without this it would end the NEXT line's wait.
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` and returns once it has been said (or `stop` was called).
    func say(_ text: String, as role: Role = .narrator) async {
        stop()
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: clean)
        let voices = Self.voices
        utterance.voice = role == .patient ? voices.patient : voices.narrator
        utterance.rate = rate
        // the same voice for both on a phone with only one: a lower patient is
        // still audibly somebody else
        if role == .patient, voices.patient?.identifier == voices.narrator?.identifier {
            utterance.pitchMultiplier = 0.85
        }
        utterance.postUtteranceDelay = 0.15
        speaking = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting = continuation
            current = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    /// Silences whatever is being said, and releases anyone waiting on it.
    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        release()
    }

    fileprivate func finished(_ id: ObjectIdentifier) {
        guard id == current else { return }
        release()
    }

    private func release() {
        current = nil
        speaking = false
        let pending = waiting
        waiting = nil
        pending?.resume()
    }

    // MARK: what is read

    /// Markdown and card markup are for eyes: `**term**` would be read as
    /// "asterisk asterisk", and a cloze's braces as punctuation.
    static func speakable(_ text: String) -> String {
        var out = Highlight.plain(text)
        out = CardQuality.clozeBare(out)
        // a quiz blank is read as the word, not skipped
        out = out.replacingOccurrences(of: "_{2,}", with: " blank ", options: .regularExpression)
        for mark in ["#", "`", "_", "*"] { out = out.replacingOccurrences(of: mark, with: "") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: choosing voices

    /// Worked out once: listing the installed voices is slow enough to notice.
    private static let voices: (narrator: AVSpeechSynthesisVoice?, patient: AVSpeechSynthesisVoice?) = {
        let phone = AVSpeechSynthesisVoice.currentLanguageCode()
        let language = phone.hasPrefix("en") ? phone : "en-GB"
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
        let narrator = installed.first ?? AVSpeechSynthesisVoice(language: language)
        let others = installed.filter { $0.identifier != narrator?.identifier }
        // someone of the other sex where the phone has one, so the two are
        // told apart at once
        let patient = others.first { $0.gender != narrator?.gender && $0.gender != .unspecified }
            ?? others.first
            ?? narrator
        return (narrator, patient)
    }()
}

extension VoiceSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}
