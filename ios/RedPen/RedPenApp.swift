import SwiftUI

@main
struct RedPenApp: App {
    @StateObject private var store: Store
    // What the phone has learned about a lecturer outlives any one set, so it
    // is owned here rather than by the screen that happens to teach it.
    @StateObject private var learned: PronunciationLibrary
    // GemmaModel is a true singleton (its download must survive view
    // teardown), so it's observed here rather than owned by @StateObject.
    @ObservedObject private var gemma = GemmaModel.shared

    init() {
        // A CI screenshot launch (see PreviewLaunch) runs on a throwaway,
        // pre-seeded store; a normal launch opens the user's own library.
        let seeded = PreviewLaunch.screen != nil
        _store = StateObject(wrappedValue: seeded ? PreviewLaunch.seededStore() : Store())
        // and on a throwaway table, so a screenshot run never writes into the
        // student's own learned pronunciations
        _learned = StateObject(wrappedValue: seeded
            ? PronunciationLibrary(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).tsv"))
            : PronunciationLibrary())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen = PreviewLaunch.screen {
                    // Screens added after the original harness live in
                    // PreviewExtras, so the ones already being compared week to
                    // week are never disturbed by adding one.
                    if PreviewExtras.handles(screen) {
                        PreviewExtras.view(for: screen)
                    } else {
                        PreviewRoot(screen: screen)
                    }
                } else {
                    LibraryView()
                }
            }
            .environmentObject(store)
            .environmentObject(learned)
            .environmentObject(gemma)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
        }
    }
}
