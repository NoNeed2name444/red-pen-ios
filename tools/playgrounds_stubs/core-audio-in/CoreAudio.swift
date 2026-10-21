import SwiftUI

// Only in the Swift Playgrounds core1 build (make_swiftpm.py --without core1):
// the core plus step 1 of the add-back order (tools/playgrounds_stubs/README.md),
// so lecture audio, the spoken modes, draw from memory and the narrate
// screens are the app's own. This file gives the core shell its ways in.

/// A narrate set opened from the library: the app's own reader.
struct CoreNarrateScreen: View {
    let set: StudySet

    var body: some View { NarrateReviewView(set: set) }
}

/// The spoken modes, which the full app reaches from its study categories
/// (StudyCategory.swift, not in this build): commute mode reads the due cards
/// and questions aloud, explain-it-back marks a spoken explanation.
struct CoreLibraryExtras: View {
    @State private var commuting = false

    var body: some View {
        Section("Spoken") {
            Button {
                commuting = true
            } label: {
                Label("Commute mode", systemImage: "car.fill")
            }
            .accessibilityHint("Reads your due cards and questions aloud and listens for the answers")
            .commuteModeSheet(isPresented: $commuting)
            NavigationLink {
                ExplainBackView()
            } label: {
                Label("Explain it back", systemImage: "waveform.and.mic")
            }
        }
    }
}

/// What this build leaves out of step 1, for the note under the library.
enum CoreAudioPart {
    static let missing: [String] = []
}

/// What the spoken screens read from the environment, which the full app
/// hands down from RedPenApp: what this phone has learned about how a
/// lecturer says things (PronunciationLibrary). Without it, opening a lecture
/// stopped the app.
struct CoreAudioEnvironment: ViewModifier {
    @StateObject private var learned = PronunciationLibrary()

    func body(content: Content) -> some View {
        content.environmentObject(learned)
    }
}

extension View {
    func coreAudioEnvironment() -> some View { modifier(CoreAudioEnvironment()) }
}
