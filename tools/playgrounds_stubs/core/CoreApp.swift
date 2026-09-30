import SwiftUI

// Only in the Swift Playgrounds core build (make_swiftpm.py --without core).
// The app's entry point without the platform work the full app does at
// launch: no sync, no widgets or Siri, no crash reporter, no design preview.
// Sign-in, the recording terms and the exam question are the full app's own
// screens; the library is the core shell's (CoreLibrary.swift).
@main
struct StethoscoreCoreApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store: Store
    @StateObject private var reviews: ReviewStore
    @StateObject private var account: AccountStore
    @StateObject private var subscriptions: SubscriptionStore
    /// Stands in for the full app's sync (CoreStandIns.swift): the personal
    /// build skips sync anyway.
    @StateObject private var sync = SyncEngine()
    @StateObject private var terms = RecordingTermsStore()
    @StateObject private var examQuestion = ExamQuestionStore()
    @ObservedObject private var gemma = GemmaModel.shared
    @ObservedObject private var llm = LocalLLMService.shared

    init() {
        // the background check for cloud jobs has to be registered before
        // launch finishes
        CloudJobCollector.registerRefresh()
        let store = Store()
        // a personal build opens with a finished example in every mode
        SampleData.seedPersonalBuild(into: store)
        _store = StateObject(wrappedValue: store)
        _reviews = StateObject(wrappedValue: ReviewStore())
        let subscriptions = SubscriptionStore()
        _subscriptions = StateObject(wrappedValue: subscriptions)
        let account = AccountStore()
        _account = StateObject(wrappedValue: account)
        LocalLLMService.shared.attach(account: account, subscriptions: subscriptions)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let signedIn = account.account, !terms.hasAgreed(signedIn.id) {
                    RecordingTermsView { terms.agree(signedIn.id) }
                } else if account.isSignedIn && !examQuestion.asked {
                    ExamOnboardingView { examQuestion.done() }
                } else if account.isSignedIn {
                    LibraryView()
                        // the bundled lecture becomes examples, once the library shows
                        .task { await SampleLectures.seed(into: store) }
                        // sets the cloud finished while the app was closed
                        .task { await CloudJobCollector.collect(into: store) }
                        // the accuracy engine checks new and edited content
                        .task { AccuracyStore.shared.attach(store) }
                        .task {
                            await account.refreshIfNeeded()
                            await subscriptions.refreshIfNeeded()
                            subscriptions.accountId = account.account?.id
                            await subscriptions.report(token: account.token)
                            SourceFiles.sweepUnused(in: store)
                        }
                        .onChange(of: account.account?.id) { _, id in
                            subscriptions.accountId = id
                            Task { await subscriptions.report(token: account.token) }
                        }
                        .onChange(of: phase) { _, new in
                            if new == .active {
                                Task { await account.refreshIfNeeded() }
                                AccuracyStore.shared.kick()
                                Task { await SupportSender.shared.flush() }
                                CloudJobCollector.appReturned()
                                Task { await CloudJobCollector.collect(into: store) }
                            }
                            if new == .background {
                                AppNotifications.scheduleReviews(sets: store.library, reviews: reviews)
                                CloudJobCollector.appLeft()
                            }
                        }
                } else {
                    SignInView()
                }
            }
            .environmentObject(store)
            .environmentObject(reviews)
            .environmentObject(account)
            .environmentObject(subscriptions)
            .environmentObject(sync)
            .environmentObject(gemma)
            .environmentObject(llm)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16))
            .launchSplash()
        }
    }
}
