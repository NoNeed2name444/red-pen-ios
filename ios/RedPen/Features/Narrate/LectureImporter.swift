import SwiftUI

/// Attaching a recording to a Narrate set and transcribing it: with Gemini by
/// default, or on the phone.
///
/// Held apart from the player view because it is the only part that can fail in
/// ways a student has to be told about - no permission, no offline language for
/// this dialect, an unreadable file - and error handling tangled into a view
/// body is error handling nobody can follow.
@MainActor
final class LectureImporter: ObservableObject {
    /// What it is doing, or nil when idle. Shown as a state rather than a
    /// percentage: the recogniser reports no progress, and a bar that crawls to
    /// 90% and stops is a lie with a progress indicator on it.
    @Published var working: String?
    @Published var trouble: String?

    /// The transcript the recording produced, ready to replace the set's own.
    @Published var produced: [NarrateSegment]?

    /// A passing note, such as the lecture being transcribed on the phone
    /// because Gemini was out of quota. Not an error: there is a transcript.
    @Published var notice: String?

    /// True while Gemini has the recording, so the screen says where it went.
    @Published var inCloud = false

    /// Who does the listening.
    enum Engine { case cloud, device }

    /// Arabic first: these lectures are Egyptian Arabic carrying English terms,
    /// and an English recogniser turns the Arabic into noise. If the phone has
    /// no offline Arabic it is worth saying so rather than quietly producing a
    /// transcript of the English words only.
    var locale: Locale = Locale(identifier: "ar-EG")

    func attach(_ picked: Result<[URL], Error>, to set: StudySet,
                learned: PronunciationLibrary, engine: Engine = .cloud) async {
        trouble = nil
        switch picked {
        case .failure(let error):
            trouble = error.localizedDescription
        case .success(let urls):
            guard let source = urls.first else { return }
            do {
                working = "Copying the recording"
                let stored = try LectureAudio.store(imported: source, for: set.id)
                await transcribe(stored, learned: learned, engine: engine,
                                 vocabulary: Self.vocabulary(for: set))
            } catch {
                working = nil
                trouble = error.localizedDescription
            }
        }
    }

    /// The lecture's own slide terms first, so Gemini spells them as the
    /// slides do.
    static func vocabulary(for set: StudySet) -> [String] {
        CloudTranscript.vocabulary(from: set.sources.flatMap { $0.pages.map(\.text) },
                                   extra: MedicalTerms.common)
    }

    func transcribe(_ url: URL, learned: PronunciationLibrary,
                    engine: Engine = .cloud, vocabulary: [String] = MedicalTerms.common) async {
        trouble = nil
        notice = nil
        do {
            var lines: [LectureTranscriber.Line] = []
            var byLine = false
            if engine == .cloud {
                working = "Sending the lecture to Gemini"
                inCloud = true
                defer { inCloud = false }
                do {
                    lines = try await CloudTranscriber.transcribe(fileAt: url, vocabulary: vocabulary,
                                                                  token: LocalLLMService.shared.cloudToken) { part, parts in
                        Task { @MainActor [weak self] in
                            self?.working = parts > 1 ? "Gemini is transcribing part \(part) of \(parts)"
                                                      : "Gemini is transcribing"
                        }
                    }
                    byLine = true
                } catch is CancellationError {
                    working = nil
                    return
                } catch {
                    // a transcript from the phone beats no transcript: Gemini
                    // being out of quota, unreachable or not set up falls back
                    let why = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    notice = "Transcribed on this phone instead. \(why)"
                }
            }
            if !byLine {
                working = "Listening to the lecture"
                lines = try await LectureTranscriber.transcribe(fileAt: url, locale: locale)
            }
            guard !lines.isEmpty else {
                working = nil
                trouble = "Nothing recognisable was found in that recording."
                return
            }
            let deviceLang = locale.identifier.hasPrefix("ar") ? "ar" : "en"
            var segments = NarrateScheduler.segments(from: lines, lang: deviceLang)
            // Gemini writes Arabic and English each in its own script, so the
            // pace and direction can follow the line itself
            if byLine {
                for i in segments.indices { segments[i].lang = CloudTranscript.language(of: segments[i].text) }
            }
            // Everything already learned is applied before the student ever
            // sees the transcript: a term corrected last week arrives correct.
            var texts = segments.map(\.text)
            _ = learned.applyLearned(to: &texts)
            for i in segments.indices { segments[i].text = texts[i] }

            produced = segments
            working = nil
        } catch {
            working = nil
            let why = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // both ways failed: one message saying so, not two alerts
            if let cloud = notice {
                notice = nil
                trouble = cloud.replacingOccurrences(of: "Transcribed on this phone instead. ", with: "Gemini: ")
                    + "\n\nOn this phone: " + why
            } else {
                trouble = why
            }
        }
    }
}

/// The reading-pace controls, for a set with no recording attached.
///
/// One row under the thumb: the way to add a recording at the leading end
/// (while there is none), then the speed as a compact menu beside Play - the
/// one main button - at the trailing end. With nothing to read yet, adding a
/// recording is the only useful step, so it becomes the main button on its
/// own. This is the bar's content: the screen hands it to `.studyBar { }`, so
/// the transcript scrolls under the glass.
struct NarrateReadingControls: View {
    @Binding var speed: Double
    let playing: Bool
    let finished: Bool
    let canPlay: Bool
    /// True when the transcript has no lines yet.
    var isEmpty: Bool = false
    let onPlayPause: () -> Void
    let onRestart: () -> Void
    /// Adds a recording; nil hides the button (while one is being made).
    var onAddAudio: (() -> Void)? = nil

    @Environment(\.windowSpan) private var span

    /// The three reading speeds, slowest first.
    private static let speeds: [ReadingSpeed] = [
        ReadingSpeed(value: 0.75, name: "Slow"),
        ReadingSpeed(value: 1, name: "Normal"),
        ReadingSpeed(value: 1.5, name: "Fast")
    ]

    @ViewBuilder
    var body: some View {
        if isEmpty, let onAddAudio {
            addAudioMain(onAddAudio)
        } else {
            row
        }
    }

    /// Add audio to the left hand; speed right beside the Play it controls.
    private var row: some View {
        HStack(spacing: 12) {
            if let onAddAudio {
                addAudioButton(onAddAudio)
                if span == .broad { Spacer(minLength: 16) }
            }
            speedMenu
            playButton
        }
    }

    /// An empty transcript: adding a recording is the main button, in words.
    private func addAudioMain(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Add audio", systemImage: "waveform.badge.plus")
        }
        .buttonStyle(.bigPrimary)
        .accessibilityLabel("Add an audio file")
        .accessibilityHint("Transcribes a recording of the lecture and follows it word by word")
        .accessibilityIdentifier("narrateAddAudio")
    }

    /// Always in reach while the lecture has no recording: the way to add one.
    /// Words when there is room, the symbol alone on a phone.
    private func addAudioButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                Label("Add audio", systemImage: "waveform.badge.plus")
                Image(systemName: "waveform.badge.plus")
            }
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Add an audio file")
        .accessibilityHint("Transcribes a recording of the lecture and follows it word by word")
        .accessibilityIdentifier("narrateAddAudio")
    }

    /// Slow, Normal, Fast, in a compact menu showing the one chosen.
    private var speedMenu: some View {
        let shown: String = Self.name(for: speed)
        return Menu {
            // a picker inside the menu ticks the chosen speed by itself
            Picker("Reading speed", selection: $speed) {
                ForEach(Self.speeds, id: \.self) { option in
                    Text(option.name).tag(option.value)
                }
            }
        } label: {
            Text(shown)
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Reading speed, \(shown)")
    }

    @ViewBuilder
    private var playButton: some View {
        if finished {
            Button(action: onRestart) {
                Label("Start again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.space, modifiers: [])
        } else {
            Button(action: onPlayPause) {
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!canPlay)
        }
    }

    private static func name(for value: Double) -> String {
        speeds.first { $0.value == value }?.name ?? String(format: "%g\u{00d7}", value)
    }
}

/// One reading speed: how fast, and its name on the menu.
private struct ReadingSpeed: Hashable {
    let value: Double
    let name: String
}
