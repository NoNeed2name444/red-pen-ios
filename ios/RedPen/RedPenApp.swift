import Combine
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
    /// The idea dump (IdeasView): notes, folders and the links between them.
    @StateObject private var noteStore: NoteStore
    /// Built after the stores it reconciles, and given them directly rather
    /// than through the environment: it is not a view and has no business
    /// waiting for one.
    @StateObject private var sync: SyncEngine
    /// Who has agreed to the recording terms (see RecordingTermsView).
    @StateObject private var terms = RecordingTermsStore()
    /// Whether "Which exam are you preparing for?" has been answered or
    /// skipped (ExamOnboardingView, once, after the terms).
    @StateObject private var examQuestion = ExamQuestionStore()
    /// Who has finished the first-run pages (FirstRunView, once per account).
    @StateObject private var firstRun = FirstRunStore()
    // GemmaModel is a true singleton (its download must survive view
    // teardown), so it's observed here rather than owned by @StateObject.
    @ObservedObject private var gemma = GemmaModel.shared
    // The medical models and hosted providers, shared the same way: a
    // download has to outlive the screen that started it.
    @ObservedObject private var llm = LocalLLMService.shared

    init() {
        // the background check for cloud jobs has to be registered before
        // launch finishes
        CloudJobCollector.registerRefresh()
        // A CI screenshot launch (see PreviewLaunch) runs on a throwaway,
        // pre-seeded store; a normal launch opens the user's own library.
        let seeded = PreviewLaunch.screen != nil
        // crash and failure reports: what the last run left, and MetricKit
        // (Shared/Diagnostics) - never for a screenshot run
        if !seeded { DiagnosticsRuntime.start() }
        let store = seeded ? PreviewLaunch.seededStore() : Store()
        // a personal build opens with a finished example in every mode, so
        // each one can be tried straight away
        if !seeded { SampleData.seedPersonalBuild(into: store) }
        // example answers, mistakes and rules, so Progress has something to show
        if !seeded { InsightExamples.seed(into: store) }
        _store = StateObject(wrappedValue: store)
        // answers from the question-of-the-day notification, and taps that
        // open a learning screen (LearnNotifications)
        if !seeded { LearnNotifications.install(store: store) }
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
        let noteStore = seeded ? NoteStore(fileURL: scratch
            .appendingPathComponent("redpen-preview-\(UUID().uuidString).json"))
            : NoteStore()
        // the personal build opens with a connected example in the idea dump
        if !seeded && PersonalBuild.isOn { NoteExamples.seedIfNeeded(into: noteStore) }
        _noteStore = StateObject(wrappedValue: noteStore)
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

    /// Shown while the sync waits for an answer about this device's library.
    private var libraryQuestion: Binding<Bool> {
        Binding(get: { sync.status == .needsLibraryChoice }, set: { _ in })
    }

    private var libraryQuestionText: String {
        let count: Int = store.library.count
        let sets: String = count == 1 ? "1 set" : "\(count) sets"
        return "This device has \(sets) from another account. Added, they sync to this account and every device on it. Kept here, they stay only on this device; anything new still syncs."
    }

    /// The signed-in library is on screen: where links, widgets, Siri and
    /// opened files land (platformRoutes waits for it).
    private var libraryShowing: Bool {
        if GraphPreview.isOn || !account.isSignedIn || !examQuestion.asked { return false }
        guard let signedIn = account.account else { return true }
        return terms.hasAgreed(signedIn.id) && !firstRun.isDue(signedIn.id, terms: terms)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if GraphPreview.isOn {
                    // the 3D map's design preview, before anything else
                    GraphPreviewRoot()
                } else if let screen = PreviewLaunch.screen {
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
                } else if let signedIn = account.account, firstRun.isDue(signedIn.id, terms: terms) {
                    // once per account, every page skippable: exam, date,
                    // daily goal, reminders, an example set
                    FirstRunView(accountId: signedIn.id) { firstRun.finish(signedIn.id); examQuestion.done() }
                } else if account.isSignedIn && !examQuestion.asked {
                    // once, skippable: the exam everything will put first
                    ExamOnboardingView { examQuestion.done() }
                } else if account.isSignedIn {
                    // the library, with the five categories and Ideas in its
                    // dock and the pages about the app in its account menu
                    LibraryView()
                        // a personal build's bundled lecture becomes examples,
                        // made by the app's own pipeline - only once the library
                        // is on screen, never under the sign-in screen
                        .task { await SampleLectures.seed(into: store) }
                        // exam plan, exam-day kit, bedtime, morning check...
                        .learnRoutes()
                        // sets the cloud finished while the app was closed
                        .task { await CloudJobCollector.collect(into: store) }
                        // the accuracy engine: new and edited content checked
                        // at once, the rest of the library in the background,
                        // within the free limits (AccuracyStore)
                        .task { AccuracyStore.shared.attach(store) }
                        // An edit reaches the other device in seconds, not at
                        // the next launch: a sync shortly after the library or
                        // the review schedule changes...
                        .onReceive(store.$library.map { _ in () }
                            .merge(with: store.$folders.map { _ in () }, reviews.objectWillChange.map { _ in () })
                            .debounce(for: .seconds(4), scheduler: RunLoop.main)) { _ in
                            Task { await sync.syncNow() }
                        }
                        // ...and a look for the other device's every minute
                        // while this one is open
                        .task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 60_000_000_000)
                                if phase == .active { await sync.syncNow() }
                            }
                        }
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
                            // lecture files no set refers to any more, with the
                            // whole library loaded (see SourceFiles.sweep)
                            SourceFiles.sweepUnused(in: store)
                        }
                        // The account can change while the library stays on
                        // screen - a device linked by code, a this-device-only
                        // library given a server account. A purchase must be
                        // tagged with the account it is for, and that account
                        // told about it; set once at launch, both went to the
                        // old one.
                        .onChange(of: account.account?.id) { _, id in
                            subscriptions.accountId = id
                            Task { await subscriptions.report(token: account.token) }
                        }
                        // Somebody else's library is on this device: asked
                        // before any of it goes into their account.
                        .alert("Add this device's library to your account?",
                               isPresented: libraryQuestion) {
                            Button("Add to my account") {
                                Task { await sync.chooseLibrary(addToAccount: true) }
                            }
                            Button("Keep on this device only") {
                                Task { await sync.chooseLibrary(addToAccount: false) }
                            }
                        } message: {
                            Text(libraryQuestionText)
                        }
                        // Coming back to the app is the moment somebody expects
                        // to see what they did on the other device.
                        .onChange(of: phase) { _, new in
                            // Coming back is when somebody expects to see last
                            // night's work from the other device; leaving is the
                            // last chance to send this device's before the phone
                            // goes in a pocket for the rest of the day.
                            if new == .active || new == .background {
                                Task {
                                    // a session near its end is renewed on the
                                    // way back in, sync or no sync: the cloud
                                    // models use it too
                                    if new == .active { await account.refreshIfNeeded() }
                                    if new == .active { AccuracyStore.shared.kick() }
                                    // question reports and messages written offline
                                    if new == .active { await SupportSender.shared.flush() }
                                    await sync.syncNow()
                                }
                            }
                            // the review reminder, rescheduled from the latest
                            // schedule each time the student leaves
                            if new == .background {
                                AppNotifications.scheduleReviews(sets: store.library, reviews: reviews)
                                LearnNotifications.reschedule(store: store)
                                CloudJobCollector.appLeft()
                            }
                            if new == .active {
                                CloudJobCollector.appReturned()
                                Task { await CloudJobCollector.collect(into: store) }
                            }
                        }
                } else {
                    SignInView()
                }
            }
            // links, opened files, Spotlight, Siri, the widgets' digest, the
            // app lock (AppIntentsRouting.swift)
            .platformRoutes(libraryShowing: libraryShowing)
            .environmentObject(store)
            .environmentObject(learned)
            .environmentObject(reviews)
            .environmentObject(account)
            .environmentObject(subscriptions)
            .environmentObject(noteStore)
            .environmentObject(sync)
            .environmentObject(gemma)
            .environmentObject(llm)
            .tint(Color(red: 0.78, green: 0.16, blue: 0.16)) // the app's "pen" red
            // the one motion source for the pop-out: started while the app
            // is active, stopped in the background (see PopOut.swift)
            .popOutLifecycle()
            // the running marker follows the app to and from the background,
            // and waiting reports go a little after it comes back
            .onChange(of: phase, initial: true) { _, new in
                DiagnosticsRuntime.phaseChanged(new, token: { account.token })
            }
            // the launch screen's picture, dissolving over the app that is
            // already running beneath it (and the only launch screen the
            // Playgrounds build has) - see LaunchSplash
            .launchSplash()
            // iPad, two windows: links, opened files, widget taps and
            // Spotlight go to a main window already open, not a new one
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        // iPad keyboard: search, due cards, a set in a new window
        .commands { StethoscoreCommands() }

        // iPad: a set in a window of its own, beside a lecture (SetWindow).
        // Only reachable where multiple windows are declared (the Xcode build).
        WindowGroup(id: SetWindow.sceneID, for: UUID.self) { $setID in
            SkyRoot(content: SetWindowRoot(setID: setID))
                .appLockShield()
                .environmentObject(store)
                .environmentObject(learned)
                .environmentObject(reviews)
                .environmentObject(account)
                .environmentObject(subscriptions)
                .environmentObject(noteStore)
                .environmentObject(sync)
                .environmentObject(gemma)
                .environmentObject(llm)
                .tint(Color(red: 0.78, green: 0.16, blue: 0.16))
        }
        // never the window a link or opened file lands in (it has no
        // routes): only its own openWindow requests open it
        .handlesExternalEvents(matching: [SetWindow.sceneID])
    }
}
