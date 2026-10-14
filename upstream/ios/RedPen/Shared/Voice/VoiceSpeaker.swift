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
/// Where it can, a line is read by the natural cloud voice (CloudVoice: a
/// voice model on the server that sounds like a person). When that cannot be
/// used - offline, not Pro, the setting off, the day's allowance spent - the
/// phone's own best voice reads it instead, so speech never stops.
///
/// Two voices: the narrator (questions, the examiner) and the patient are
/// different people, so a student with the phone in a pocket can hear who is
/// talking without looking.
@MainActor
final class VoiceSpeaker: NSObject, ObservableObject {

    enum Role { case narrator, patient }

    @Published private(set) var speaking = false

    /// The phone's normal speaking pace. Slower than this sounds drawn out
    /// and more robotic, not clearer.
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    private let synthesizer = AVSpeechSynthesizer()
    private let cloud = CloudVoice()
    private var waiting: CheckedContinuation<Void, Never>?
    /// Which utterance the current wait belongs to. A cancelled line reports
    /// its end a moment later; without this it would end the NEXT line's wait.
    private var current: ObjectIdentifier?
    /// Which call to `say` is the live one. `stop` clears it, so a line that
    /// was waiting for the cloud voice gives up instead of starting late.
    private var turn: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` and returns once it has been said (or `stop` was called).
    func say(_ text: String, as role: Role = .narrator) async {
        stop()
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }
        let myTurn = UUID()
        turn = myTurn
        speaking = true

        // the natural voice first, piece by piece
        let pieces = cloud.available ? CloudVoice.pieces(of: clean) : []
        let patient = role == .patient
        var played = 0
        for (index, piece) in pieces.enumerated() {
            // the next piece is fetched while this one plays
            if index + 1 < pieces.count { cloud.prefetch(pieces[index + 1], patient: patient) }
            guard let clip = await cloud.clip(for: piece, patient: patient) else { break }
            guard turn == myTurn else { return }
            // with only one cloud voice, the patient would sound like the
            // examiner: the phone's own patient voice is kept apart instead
            if patient && !clip.distinctVoices { break }
            let finished = await cloud.play(clip)
            guard turn == myTurn else { return }
            guard finished else { break }
            played += 1
        }
        guard turn == myTurn else { return }
        if !pieces.isEmpty && played == pieces.count {
            release()
            return
        }

        // whatever the cloud did not read, the phone reads
        let rest = played == 0 ? clean : pieces.dropFirst(played).joined(separator: " ")
        await speakOnPhone(rest, as: role, turn: myTurn)
    }

    /// Starts fetching a line that will be said soon, so it plays without a
    /// pause when its turn comes. Does nothing when the cloud voice is off.
    func prefetch(_ text: String, as role: Role = .narrator) {
        let clean = Self.speakable(text)
        guard !clean.isEmpty, cloud.available else { return }
        if let first = CloudVoice.pieces(of: clean).first {
            cloud.prefetch(first, patient: role == .patient)
        }
    }

    /// Silences whatever is being said, and releases anyone waiting on it.
    func stop() {
        turn = nil
        cloud.stop()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        release()
    }

    // MARK: the phone's own voice

    private func speakOnPhone(_ text: String, as role: Role, turn myTurn: UUID) async {
        let utterance = AVSpeechUtterance(string: text)
        let voices = Self.voices
        utterance.voice = role == .patient ? voices.patient : voices.narrator
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        // the same voice for both on a phone with only one: a slightly lower
        // patient is still audibly somebody else
        if role == .patient, voices.patient?.identifier == voices.narrator?.identifier {
            utterance.pitchMultiplier = 0.9
        }
        // a breath before and after, as a person would leave
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.2
        guard turn == myTurn else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting = continuation
            current = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
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

    // MARK: choosing the phone's voices

    /// Worked out once: listing the installed voices is slow enough to notice.
    ///
    /// The most natural installed voice wins: Premium, then Enhanced, then the
    /// basic ones, in the phone's own English first, then British, then
    /// American. Novelty, Personal Voice and the old Eloquence voices (Eddy,
    /// Flo, Grandma...) are left out - they are the robotic-sounding ones.
    /// Narrate's read-aloud uses the same narrator.
    static let voices: (narrator: AVSpeechSynthesisVoice?, patient: AVSpeechSynthesisVoice?) = {
        let phone = AVSpeechSynthesisVoice.currentLanguageCode()
        var languages: [String] = phone.hasPrefix("en") ? [phone] : []
        for extra in ["en-GB", "en-US"] where !languages.contains(extra) { languages.append(extra) }
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { languages.contains($0.language) && VoiceSpeaker.usable($0) }
            .sorted { VoiceSpeaker.score($0, languages) > VoiceSpeaker.score($1, languages) }
        let narrator = installed.first ?? AVSpeechSynthesisVoice(language: languages[0])
        let others = installed.filter { $0.identifier != narrator?.identifier }
        // someone of the other sex where the phone has one, so the two are
        // told apart at once
        let otherSex = others.first { $0.gender != narrator?.gender && $0.gender != .unspecified }
        let patient = otherSex ?? others.first ?? narrator
        return (narrator, patient)
    }()

    nonisolated private static func usable(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if voice.voiceTraits.contains(.isNoveltyVoice) { return false }
        if voice.voiceTraits.contains(.isPersonalVoice) { return false }
        return !voice.identifier.lowercased().contains("eloquence")
    }

    /// Quality counts most; the language order breaks ties.
    nonisolated private static func score(_ voice: AVSpeechSynthesisVoice, _ languages: [String]) -> Int {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        let place = languages.firstIndex(of: voice.language) ?? languages.count
        return quality * 10 + (languages.count - place)
    }
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
