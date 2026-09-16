import SwiftUI

@main
struct RedPenApp: App {
    @StateObject private var store: Store

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
                    PreviewRoot(screen: screen)
                } else {
                    LibraryView()
                }
            }
            .environmentObject(store)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
        }
    }
}
