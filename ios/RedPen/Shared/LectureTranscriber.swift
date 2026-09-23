import Foundation
import Speech

/// Turning a recording into a transcript, on the phone. (Gemini, in
/// CloudTranscriber, is the default; this is the offline choice and the
/// fallback when Gemini can't be reached.)
///
/// This is the piece the web app never had natively and the conversion note
/// listed as unported: Narrate following a REAL recording rather than a typed
/// transcript read at a reading pace.
///
/// Apple's Speech framework does the recognition, with
/// `requiresOnDeviceRecognition` forced on. That is not a performance
/// preference - it is the whole privacy position. A lecture recording is other
/// people's voices in a room they did not agree to have uploaded, and Red Pen
/// has no account to upload it to anyway. If a locale cannot run on-device on
/// this phone, the honest outcome is to say so, not to quietly send the audio
/// to a server.
///
/// What makes it worth the trouble: the recogniser reports a timestamp per
/// word. Those become `.measured` word times, so the highlight sits on the
/// word actually being said instead of on a line that is roughly in range.
enum LectureTranscriber {

    /// One word as a recogniser reports it. Declared here rather than using
    /// SFTranscriptionSegment directly so the line-splitting below can be
    /// tested without a microphone, a locale, or a permission prompt.
    struct SpokenWord: Equatable {
        var text: String
        var start: Double
        var duration: Double
        var end: Double { start + duration }
    }

    struct Line: Equatable {
        var text: String
        var start: Double
        var end: Double
        var words: [SpokenWord]
    }

    enum Failure: LocalizedError {
        case notPermitted
        case noRecogniser(String)
        case notOnDevice(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notPermitted:
                return "\(Brand.name) needs permission to use speech recognition. Settings › \(Brand.name)."
            case .noRecogniser(let locale):
                return "This phone has no speech recogniser for \(locale)."
            case .notOnDevice(let locale):
                return "\(locale) can only be recognised on Apple's servers on this phone, and on-device transcription never uploads. Transcribe with Gemini instead, or download the offline language in Settings › General › Keyboard › Dictation."
            case .failed(let why):
                return why
            }
        }
    }

    /// A pause long enough to be the end of a sentence.
    ///
    /// Lecturers do not speak in sentences, they speak in breaths, so the
    /// transcript is broken where the speaking stops rather than where
    /// punctuation would go - punctuation a recogniser guesses is not evidence
    /// of anything.
    static let pauseSeconds = 0.55
    /// A line nobody paused inside still has to end somewhere, or one
    /// unbroken stretch of speech becomes a paragraph nobody can follow.
    static let maxWordsPerLine = 14

    /// Break a stream of timed words into readable lines.
    static func lines(from words: [SpokenWord]) -> [Line] {
        var lines: [Line] = []
        var current: [SpokenWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            lines.append(Line(text: current.map(\.text).joined(separator: " "),
                              start: first.start, end: last.end, words: current))
            current = []
        }

        for word in words {
            if let previous = current.last {
                let gap = word.start - previous.end
                if gap >= pauseSeconds || current.count >= maxWordsPerLine { flush() }
            }
            current.append(word)
        }
        flush()
        return lines
    }

    /// The lines as the Narrate player wants them: text, end times, and the
    /// measured word timings that let the highlight follow a word at a time.
    static func timings(for lines: [Line]) -> [[(text: String, start: Double, end: Double)]] {
        lines.map { line in line.words.map { ($0.text, $0.start, $0.end) } }
    }

    // MARK: the device

    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// Transcribe a recording already on disk.
    ///
    /// Recording is deliberately not this type's job: a lecture is usually
    /// already in Voice Memos or the Files app by the time a student thinks
    /// about studying it, and a file is also what a share-sheet import hands
    /// over.
    static func transcribe(fileAt url: URL, locale: Locale) async throws -> [Line] {
        guard await authorize() else { throw Failure.notPermitted }
        guard let recogniser = SFSpeechRecognizer(locale: locale) else {
            throw Failure.noRecogniser(locale.identifier)
        }
        guard recogniser.supportsOnDeviceRecognition else {
            throw Failure.notOnDevice(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        // Medical lectures are mostly terms no general recogniser expects, and
        // this is the one hint the framework takes.
        request.contextualStrings = Array(MedicalTerms.common.prefix(100))

        let transcription: SFTranscription = try await withCheckedThrowingContinuation { continuation in
            var settled = false
            recogniser.recognitionTask(with: request) { result, error in
                guard !settled else { return }
                if let error {
                    settled = true
                    continuation.resume(throwing: Failure.failed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    settled = true
                    continuation.resume(returning: result.bestTranscription)
                }
            }
        }

        let words = transcription.segments.map {
            SpokenWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
        }
        return lines(from: words)
    }
}

/// Terms worth telling the recogniser to expect.
///
/// Kept short on purpose: contextualStrings biases the recogniser, and a long
/// list of rare words biases it into hearing them where they were not said.
enum MedicalTerms {
    static let common = [
        "lupus", "erythematosus", "malar", "nasolabial", "discoid", "mucocutaneous",
        "hydroxychloroquine", "mycophenolate", "cyclophosphamide", "prednisolone",
        "nephritis", "proteinuria", "antinuclear", "antibody", "complement",
        "serositis", "pericarditis", "arthralgia", "thrombosis", "anticoagulant",
        "vasculitis", "alopecia", "photosensitivity", "leukopenia", "thrombocytopenia",
    ]
}
