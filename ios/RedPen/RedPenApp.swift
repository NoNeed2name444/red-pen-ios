import SwiftUI

@main
struct RedPenApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store: Store
    // What the phone has learned about a lecturer outlives any one set, so it
    // is owned here rather than by the screen that happens to teach it.
    @StateObject private var learned: PronunciationLibrary
    // The schedule spans the whole library - what is due today is a question
    // about every deck at once - so it is owned here too.
    @StateObject private var reviews: ReviewStore
    @StateObject private var account: AccountStore
    @StateObject private var subscriptions: SubscriptionStore
    /// Built after the stores it reconciles, and given them directly rather
    /// than through the environment: it is not a view and has no business
    /// waiting for one.
    @StateObject private var sync: SyncEngine
    /// Who has agreed to the recording terms (see RecordingTermsView).
    @StateObject private var terms = RecordingTermsStore()
    // GemmaModel is a true singleton (its download must survive view
    // teardown), so it's observed here rather than owned by @StateObject.
    @ObservedObject private var gemma = GemmaModel.shared
    // The medical models and hosted providers, shared the same way: a
    // download has to outlive the screen that started it.
    @ObservedObject private var llm = LocalLLMService.shared

    init() {
        // A CI screenshot launch (see PreviewLaunch) runs on a throwaway,
        // pre-seeded store; a normal launch opens the user's own library.
        let seeded = PreviewLaunch.screen != nil
        let store = seeded ? PreviewLaunch.seededStore() : Store()
        // a personal build opens with a finished example in every mode, so
        // each one can be tried straight away
        if !seeded { SampleData.seedPersonalBuild(into: store) }
        _store = StateObject(wrappedValue: store)
        // and on throwaway files, so a screenshot run never writes into the
        // student's own pronunciations, schedule or subscription record
        let scratch = FileManager.default.temporaryDirectory
        _learned = StateObject(wrappedValue: seeded
            ? PronunciationLibrary(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).tsv"))
            : PronunciationLibrary())
        let reviews = seeded ? ReviewStore(fileURL: scratch
            .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
            : ReviewStore()
        _reviews = StateObject(wrappedValue: reviews)
        let subscriptions = seeded
            ? SubscriptionStore(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
            : SubscriptionStore()
        _subscriptions = StateObject(wrappedValue: subscriptions)
        // A screenshot run is signed in to nobody's account in particular: the
        // alternative is every preview screen being a picture of a sign-in
        // page.
        let account = seeded ? AccountStore(session: PreviewLaunch.pretendSession())
                             : AccountStore()
        _account = StateObject(wrappedValue: account)
        LocalLLMService.shared.attach(account: account, subscriptions: subscriptions)
        // A screenshot run reconciles with nothing: there is no server, and a
        // failed sync badge in every preview would be noise in the one place
        // that exists to make changes visible.
        _sync = StateObject(wrappedValue: SyncEngine(
            store: store, reviews: reviews, account: account,
            bookmarks: seeded ? SyncStateStore(fileURL: scratch
                .appendingPathComponent("redpen-preview-\(UUID().uuidString).json")) : nil))
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
                } else if let signedIn = account.account, !terms.hasAgreed(signedIn.id) {
                    // once per account, before anything else: recordings are
                    // only transcribed with the speakers' permission
                    RecordingTermsView { terms.agree(signedIn.id) }
                } else if account.isSignedIn {
                    LibraryView()
                        .task {
                            // All three are cheap and all three are wrong to
                            // leave stale: a session that expires mid-sentence,
                            // a subscription that renewed an hour ago, and a
                            // library edited on the other device last night.
                            await account.refreshIfNeeded()
                            await subscriptions.refreshIfNeeded()
                            // CramDown Cloud checks with Apple, server side;
                            // this tells it which subscription to ask about
                            subscriptions.accountId = account.account?.id
                            await subscriptions.report(token: account.token)
                            await sync.syncNow()
                        }
                        // Coming back to the app is the moment somebody expects
                        // to see what they did on the other device.
                        .onChange(of: phase) { _, new in
                            // Coming back is when somebody expects to see last
                            // night's work from the other device; leaving is the
                            // last chance to send this device's before the phone
                            // goes in a pocket for the rest of the day.
                            if new == .active || new == .background {
                                Task { await sync.syncNow() }
                            }
                        }
                } else {
                    SignInView()
                }
            }
            .environmentObject(store)
            // a personal build's bundled lecture becomes examples, made by the
            // app's own pipeline (diagram cards, a textbook with its figures)
            .task { await SampleLectures.seed(into: store) }
            .environmentObject(learned)
            .environmentObject(reviews)
            .environmentObject(account)
            .environmentObject(subscriptions)
            .environmentObject(sync)
            .environmentObject(gemma)
            .environmentObject(llm)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
        }
    }
}
