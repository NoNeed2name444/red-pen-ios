import SwiftUI

@main
struct RedPenApp: App {
    @StateObject private var store: Store
    // GemmaModel is a true singleton (its download must survive view
    // teardown), so it's observed here rather than owned by @StateObject.
    @ObservedObject private var gemma = GemmaModel.shared

    init() {
        // A CI screenshot launch (see PreviewLaunch) runs on a throwaway,
        // pre-seeded store; a normal launch opens the user's own library.
        let seeded = PreviewLaunch.screen != nil
        _store = StateObject(wrappedValue: seeded ? PreviewLaunch.seededStore() : Store())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen = PreviewLaunch.screen {
                    // Screens added after the original harness live in
                    // PreviewExtras, so the fifteen already being compared week
                    // to week are never disturbed by adding one.
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
            .environmentObject(gemma)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
        }
    }
}
