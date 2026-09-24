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
struct NarrateReadingControls: View {
    @Binding var speed: Double
    let playing: Bool
    let finished: Bool
    let canPlay: Bool
    let onPlayPause: () -> Void
    let onRestart: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    speedButton(0.75, "Slow")
                    speedButton(1, "Normal")
                    speedButton(1.5, "Fast")
                }
                if finished {
                    Button("Restart", action: onRestart)
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(playing ? "Pause" : "Play", action: onPlayPause)
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(!canPlay)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func speedButton(_ value: Double, _ label: String) -> some View {
        Button(label) { speed = value }
            .buttonStyle(.glass)
            .tint(speed == value ? StudySetKind.narrate.tint : Color.secondary)
    }
}
