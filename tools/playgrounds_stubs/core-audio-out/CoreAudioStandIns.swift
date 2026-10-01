import SwiftUI

// Only in the Swift Playgrounds core build (make_swiftpm.py --without core):
// stand-ins for the parts that step 1 of the add-back order brings back
// (tools/playgrounds_stubs/README.md): lecture audio, the spoken modes
// (Features/Voice, Shared/Voice), draw from memory (Features/Recall) and
// the narrate screens (Features/Narrate). The core1 build has the real ones
// and core-audio-in/CoreAudio.swift instead of this file.

/// A narrate set opened from the library: not in this build.
struct CoreNarrateScreen: View {
    let set: StudySet

    var body: some View { NotInThisBuild(feature: "Audio lectures") }
}

/// The library's extra rows: none here.
struct CoreLibraryExtras: View {
    var body: some View { EmptyView() }
}

/// What this build leaves out of step 1, for the note under the library.
enum CoreAudioPart {
    static let missing: [String] = ["audio lectures", "spoken OSCE practice", "commute mode", "explain it back", "draw from memory"]
}

struct SpokenStationView: View {
    let station: OsceChecklist

    var body: some View { NotInThisBuild(feature: "Spoken OSCE practice") }
}

struct NarrateReviewView: View {
    let studySet: StudySet

    init(set studySet: StudySet, startIndex: Int = 0, startPlaying: Bool = false,
         startFinished: Bool = false, startFixing: Int? = nil) {
        self.studySet = studySet
    }

    var body: some View { NotInThisBuild(feature: "Audio lectures") }
}

struct CaseStationClock: View {
    var body: some View { EmptyView() }
}

/// The case's composer without the voice: the field and a Send button.
struct CaseVoiceButtons<Field: View>: View {
    let hasDraft: Bool
    let onSend: () -> Void
    private let field: Field

    init(simulator: CaseSimulator, hasDraft: Bool, onSend: @escaping () -> Void,
         @ViewBuilder field: () -> Field) {
        self.hasDraft = hasDraft
        self.onSend = onSend
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            field
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(!hasDraft)
            .accessibilityLabel("Send")
        }
    }
}

struct DrawFromMemoryButton: View {
    let set: StudySet
    let imageIndex: Int
    let caption: String

    var body: some View { EmptyView() }
}

/// The recording transcriber's line shape (Shared/LectureTranscriber.swift),
/// which the narrate segments are built from.
enum LectureTranscriber {
    struct Word: Equatable {
        var text: String
        var start: Double
        var end: Double
    }

    struct Line: Equatable {
        var text: String
        var start: Double
        var end: Double
        var words: [Word]
        var model: String? = nil
    }
}

extension View {
    func commuteModeSheet(isPresented: Binding<Bool>) -> some View { self }
}

extension View {
    /// The spoken screens are not in this build, so nothing they read is
    /// needed (CoreAudio.swift supplies it where they are).
    func coreAudioEnvironment() -> some View { self }
}
