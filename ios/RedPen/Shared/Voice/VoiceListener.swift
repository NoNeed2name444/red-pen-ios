import Foundation
import AVFoundation
import Speech
import Combine

/// Live speech to text from the microphone, as the student speaks.
///
/// The same recogniser LectureTranscriber uses, fed from the microphone
/// instead of a file. On a phone that can recognise the language on the
/// device, it is made to - the same privacy position as the lecture
/// transcriber: a student talking through a diagnosis is not something to send
/// anywhere. Where the phone can only recognise on Apple's servers, listening
/// still works (the student asked it to listen, on screen), and `onDevice`
/// says which it was.
@MainActor
final class VoiceListener: ObservableObject {

    /// Everything heard so far in this listen, best guess, updated as it goes.
    @Published private(set) var text = ""
    @Published private(set) var listening = false
    @Published private(set) var failure: String?
    /// True when the words were recognised on the phone and went nowhere.
    @Published private(set) var onDevice = false

    /// When the recogniser last changed its mind - the end of the last word
    /// heard, near enough. Silence since then is how a spoken answer ends.
    private(set) var lastHeard = Date()

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    /// Bumped on every start: a recognition that was stopped can still report
    /// once more, and must not overwrite the next one's words.
    private var generation = 0

    /// The phone's language where it has a recogniser, else English.
    nonisolated static func makeRecogniser() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    }

    /// Starts listening. Permission must already have been given
    /// (VoiceAccess.request); returns false, with `failure` set, if the
    /// microphone or recogniser can't start.
    @discardableResult
    func start(hints: [String] = []) -> Bool {
        stop()
        text = ""
        failure = nil
        guard let recogniser = Self.makeRecogniser(), recogniser.isAvailable else {
            failure = VoiceAccess.noRecogniser
            return false
        }
        let made = SFSpeechAudioBufferRecognitionRequest()
        made.shouldReportPartialResults = true
        made.addsPunctuation = true
        made.taskHint = .dictation
        made.contextualStrings = Array((hints + MedicalTerms.common).prefix(100))
        if recogniser.supportsOnDeviceRecognition { made.requiresOnDeviceRecognition = true }
        onDevice = recogniser.supportsOnDeviceRecognition

        VoiceAccess.activate()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            failure = "No microphone is available right now - is another app using it?"
            return false
        }
        Self.feed(input, format: format, into: made)
        tapped = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapped = false
            failure = "The microphone wouldn't start: \(error.localizedDescription)"
            return false
        }
        generation += 1
        request = made
        task = Self.recognise(with: recogniser, request: made, owner: self, generation: generation)
        listening = true
        lastHeard = Date()
        return true
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        if engine.isRunning { engine.stop() }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        generation += 1
        listening = false
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Listens for one spoken answer: until the student has said something and
    /// then paused for `silence` seconds, or nothing at all has been said for
    /// `patience` seconds. Returns nil if listening could not start.
    func listenOnce(patience: Double = 9, silence: Double = 1.3, hints: [String] = []) async -> String? {
        guard start(hints: hints) else { return nil }
        let began = Date()
        while listening, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            let now = Date()
            let heardSomething = !text.trimmingCharacters(in: .whitespaces).isEmpty
            if heardSomething, now.timeIntervalSince(lastHeard) >= silence { break }
            if !heardSomething, now.timeIntervalSince(began) >= patience { break }
            // someone talking on and on still gets an answer marked
            if now.timeIntervalSince(began) >= patience * 4 { break }
        }
        return stop()
    }

    // MARK: off the main thread

    // Both closures below are called by the audio and speech frameworks on
    // their own threads, so they are made here, outside the main actor, and
    // only hop back to it with plain values.

    nonisolated private static func feed(_ input: AVAudioInputNode, format: AVAudioFormat,
                                         into request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognise(with recogniser: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              owner: VoiceListener,
                                              generation: Int) -> SFSpeechRecognitionTask {
        recogniser.recognitionTask(with: request) { [weak owner] result, error in
            guard let listener = owner else { return }
            let heard = result?.bestTranscription.formattedString
            let failed = error != nil && result == nil
            Task { @MainActor in listener.receive(heard, failed: failed, generation: generation) }
        }
    }

    private func receive(_ heard: String?, failed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        if let heard, heard != text {
            text = heard
            lastHeard = Date()
        }
        // An error with nothing heard is usually just "no speech detected";
        // the caller sees an empty answer and says so in its own words.
        if failed { stop() }
    }
}
