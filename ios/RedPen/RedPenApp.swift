import SwiftUI

@main
struct RedPenApp: App {
    @StateObject private var store: Store
    // What the phone has learned about a lecturer outlives any one set, so it
    // is owned here rather than by the screen that happens to teach it.
    @StateObject private var learned: PronunciationLibrary
    // The schedule spans the whole library - what is due today is a question
    // about every deck at once - so it is owned here too.
    @StateObject private var reviews: ReviewStore
    @StateObject private var account: AccountStore
    @StateObject private var subscriptions: SubscriptionStore
    // GemmaModel is a true singleton (its download must survive view
    // teardown), so it's observed here rather than owned by @StateObject.
    @ObservedObject private var gemma = GemmaModel.shared

    init() {
        // A CI screenshot launch (see PreviewLaunch) runs on a throwaway,
        // pre-seeded store; a normal launch opens the user's own library.
        let seeded = PreviewLaunch.screen != nil
        _store = StateObject(wrappedValue: seeded ? PreviewLaunch.seededStore() : Store())
        // and on throwaway files, so a screenshot run never writes into the
        // student's own pronunciations, schedule or subscription record
        let scratch = FileManager.default.temporaryDirectory
        _learned = StateObject(wrappedValue: seeded
            ? PronunciationLibrary(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).tsv"))
            : PronunciationLibrary())
        _reviews = StateObject(wrappedValue: seeded
            ? ReviewStore(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
            : ReviewStore())
        _subscriptions = StateObject(wrappedValue: seeded
            ? SubscriptionStore(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
            : SubscriptionStore())
        // A screenshot run is signed in to nobody's account in particular: the
        // alternative is every preview screen being a picture of a sign-in
        // page.
        _account = StateObject(wrappedValue: seeded
            ? AccountStore(session: PreviewLaunch.pretendSession())
            : AccountStore())
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
                } else if account.isSignedIn {
                    LibraryView()
                        .task {
                            // both are cheap and both are wrong to leave stale:
                            // a session that expires mid-session, and a
                            // subscription that renewed an hour ago
                            await account.refreshIfNeeded()
                            await subscriptions.refreshIfNeeded()
                        }
                } else {
                    SignInView()
                }
            }
            .environmentObject(store)
            .environmentObject(learned)
            .environmentObject(reviews)
            .environmentObject(account)
            .environmentObject(subscriptions)
            .environmentObject(gemma)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
        }
    }
}
