import Combine
import CoreSpotlight
import SwiftUI
import UIKit

// MARK: - Acting on an AppLink
//
// Siri, Shortcuts, Spotlight, the widgets, the Control, `redpen://` links and
// the iPad's keyboard commands all end here. A request that arrives before
// the library is on screen (a cold launch from a widget, or while the sign-in
// or the terms are showing) waits until it is.
//
// What the router cannot do itself - put text in the library's search - it
// announces with a notification (PlatformNotice) the library observes.

/// Notifications the keyboard commands and intents post for screens owned
/// elsewhere to act on.
enum PlatformNotice {
    /// ⌘F / redpen://search: `userInfo["text"]` is the search text (may be "").
    static let search = Notification.Name("stethoscore.command.search")
    /// A focus round finished: `userInfo["start"]` and `["end"]` are Dates.
    /// Posted by the focus timer; MindfulMinutes logs it to Health.
    static let focusRoundEnded = Notification.Name("stethoscore.focusRoundEnded")
    /// A note's backlink chip / redpen://item: `userInfo["source"]` is the
    /// NoteSource; the library opens the item in its set.
    static let openItem = Notification.Name("stethoscore.openItem")

    static func post(_ name: Notification.Name, _ info: [String: Any] = [:]) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: info)
    }

    static func publisher(_ name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }
}

/// A sheet the router shows itself.
enum PlatformSheet: String, Identifiable {
    case reviewDue
    case newSet
    var id: String { rawValue }
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// A sheet asked for (nil: close the one showing). Sent, not kept, so
    /// with two main windows on an iPad only the one in front shows it
    /// (PlatformRoutes), rather than both at once.
    let sheetRequests = PassthroughSubject<PlatformSheet?, Never>()
    /// Said when a request could not be met ("No cardiology questions yet").
    @Published var notice: String?

    /// A request waiting for the library.
    private var pending: AppLink?
    private weak var store: Store?
    /// Whether the signed-in library is on screen.
    private var ready = false

    /// The library on screen, for an intent's query; nil before it is.
    var library: [StudySet]? { store?.library }

    func attach(store: Store, ready: Bool) {
        self.store = store
        self.ready = ready
        IntentLibrary.forget()
        guard ready, let link = pending else { return }
        pending = nil
        // after the library's first layout, so its pushes and sheets land
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.perform(link)
        }
    }

    func open(_ link: AppLink) {
        guard ready, store != nil else {
            pending = link
            return
        }
        perform(link)
    }

    func open(url: URL) -> Bool {
        guard let link = AppLink.parse(url) else { return false }
        open(link)
        return true
    }

    private func perform(_ link: AppLink) {
        guard let store else { return }
        switch link {
        case .reviewDue:
            present(.reviewDue)
        case .newSet:
            present(.newSet)
        case .openSet(let id):
            guard let set = store.library.first(where: { $0.id == id }) else {
                notice = "That set is no longer in your library."
                return
            }
            sheetRequests.send(nil)
            ModeSwitch.shared.opening = set
        case .quiz(let subject):
            quiz(on: subject, from: store.library)
        case .search(let text):
            PlatformNotice.post(PlatformNotice.search, ["text": text])
        case .examPlan:
            LearnRouter.shared.open(.examPlan)
        case .openItem(let source):
            sheetRequests.send(nil)
            PlatformNotice.post(PlatformNotice.openItem, ["source": source])
        }
    }

    private func present(_ next: PlatformSheet) {
        sheetRequests.send(next)
    }

    // MARK: which window

    /// The main window last in front. Sheets and the inbox for opened files
    /// show only there; nil (one window, or none known yet) lets any show.
    private(set) var frontScene: UUID?

    func sceneInFront(_ id: UUID) {
        frontScene = id
    }

    func sceneGone(_ id: UUID) {
        if frontScene == id { frontScene = nil }
    }

    func isFront(_ id: UUID) -> Bool {
        frontScene == nil || frontScene == id
    }

    /// Up to twenty questions from the sets that best match the subject -
    /// its questions as they are, its cards made into questions.
    private func quiz(on subject: String, from library: [StudySet]) {
        let studied: [StudySet] = library.filter { $0.kind == .mcq || $0.kind == .anki }
        var best: Int = 0
        var chosen: [StudySet] = []
        for set in studied {
            let names: [String] = [set.subject, set.name] + (set.tags ?? [])
            let score: Int = SubjectMatch.score(query: subject, names: names)
            if score > best {
                best = score
                chosen = [set]
            } else if score == best && score > 0 {
                chosen.append(set)
            }
        }
        guard !chosen.isEmpty else {
            notice = "Nothing on \u{201C}\(subject)\u{201D} in your library yet."
            return
        }
        var filter = CustomSession.Filter()
        filter.limit = 20
        let plan = CustomSession.plan(sets: chosen, filter: filter, context: CustomSession.Context())
        let title: String = "Quiz: " + subject.capitalized
        let built = CustomSession.quiz(plan, sets: chosen, name: title, seed: UInt64(Date().timeIntervalSince1970))
        guard !built.set.questions.isEmpty else {
            notice = "Nothing on \u{201C}\(subject)\u{201D} could be made into a quiz."
            return
        }
        LearnRouter.shared.open(.quiz(built.set, timed: false))
    }
}

// MARK: - The root's end of it

extension View {
    /// Once, on the app's root: links, files, Spotlight taps, the router's
    /// sheets, the widgets' digest, the Spotlight index, Health, the app lock
    /// and the multi-window sky. See PlatformRoutes.
    /// `libraryShowing`: the signed-in library is on screen (not the
    /// sign-in, the terms or the exam question), so routes can land.
    func platformRoutes(libraryShowing: Bool) -> some View {
        modifier(PlatformRoutes(libraryShowing: libraryShowing))
    }
}

private struct PlatformRoutes: ViewModifier {
    let libraryShowing: Bool
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var router = AppRouter.shared
    /// Watches the library, the schedule and the study log once - not a
    /// new subscription on every redraw of the root.
    @StateObject private var glance = GlanceTrigger()
    /// This window, for which of two main windows shows a sheet.
    @State private var scene = UUID()
    @State private var isKey = true
    /// The router's sheet, as this window shows it.
    @State private var shown: PlatformSheet?

    /// The library is what routes land on; the sign-in screen and the terms
    /// come first, and a screenshot run never routes.
    private var ready: Bool {
        libraryShowing && PreviewLaunch.screen == nil
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { router.notice != nil }, set: { if !$0 { router.notice = nil } })
    }

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if url.isFileURL {
                    ImportRouter.shared.receive(url)
                } else {
                    _ = router.open(url: url)
                }
            }
            // a Spotlight result from the older CoreSpotlight index
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                let raw: String? = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
                if let raw, let id = UUID(uuidString: raw) { router.open(.openSet(id)) }
            }
            .importRouting(scene: scene)
            .onReceive(router.sheetRequests) { asked in show(asked) }
            .sheet(item: $shown) { sheet in
                PlatformSheetView(sheet: sheet)
            }
            .alert("Stethoscore", isPresented: noticeShown) {
                Button("OK", role: .cancel) { router.notice = nil }
            } message: {
                Text(router.notice ?? "")
            }
            .onAppear { router.attach(store: store, ready: ready) }
            .onChange(of: ready) { _, now in router.attach(store: store, ready: now) }
            .onChange(of: phase) { _, now in
                guard ready, now != .inactive else { return }
                GlancePublisher.publish(store: store, reviews: reviews)
            }
            .task(id: ready) {
                guard ready else {
                    glance.stop()
                    return
                }
                GlancePublisher.publish(store: store, reviews: reviews)
                SpotlightIndexer.shared.update(store.library)
                MindfulMinutes.listen()
                glance.start(store: store, reviews: reviews)
            }
            // which main window is in front, for the router's sheets
            .background(KeyWindowProbe(isKey: $isKey).allowsHitTesting(false))
            .onChange(of: isKey, initial: true) { _, key in
                if key { router.sceneInFront(scene) }
            }
            .onDisappear { router.sceneGone(scene) }
            .appLockShield()
            .stillWhenNotKey()
    }

    /// A sheet the router asked for, shown only in the window in front; one
    /// already up is closed first, and the next follows once it has gone.
    private func show(_ asked: PlatformSheet?) {
        guard router.isFront(scene) else { return }
        guard let asked else {
            shown = nil
            return
        }
        guard shown != nil else {
            shown = asked
            return
        }
        shown = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            shown = asked
        }
    }
}

/// The widgets' digest and the Spotlight index, redone a few seconds after
/// the library, the schedule or the study log stops changing. Subscribed
/// once (on the library's first showing), so a redraw of the root does not
/// start another debounce or replay the current values.
@MainActor
private final class GlanceTrigger: ObservableObject {
    private var watching: AnyCancellable?

    func start(store: Store, reviews: ReviewStore) {
        guard watching == nil else { return }
        let library: AnyPublisher<Void, Never> = store.$library.dropFirst().map { _ in () }.eraseToAnyPublisher()
        let schedule: AnyPublisher<Void, Never> = reviews.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        let log: AnyPublisher<Void, Never> = StudyLog.shared.$days.dropFirst().map { _ in () }.eraseToAnyPublisher()
        let merged: AnyPublisher<Void, Never> = library.merge(with: schedule, log).eraseToAnyPublisher()
        watching = merged
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { [weak store, weak reviews] _ in
                guard let store, let reviews else { return }
                GlancePublisher.publish(store: store, reviews: reviews)
                SpotlightIndexer.shared.update(store.library)
            }
    }

    /// Signed out: nothing to publish until the library is back.
    func stop() {
        watching = nil
    }
}

/// The router's own sheets.
private struct PlatformSheetView: View {
    let sheet: PlatformSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .reviewDue:
            NavigationStack {
                DueTodayView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                                .accessibilityIdentifier("platformDone")
                        }
                    }
            }
        case .newSet:
            NewSetView()
        }
    }
}

// MARK: - iPad keyboard commands

/// The menu a hardware keyboard shows when ⌘ is held, for what no screen
/// already offers: search, due cards and a set in its own window.
///
/// ⌘N (New set, LibraryView), ⌘1–⌘5 (the dock, StudyCategory) and ⌘Z
/// (the undo chip after a rating, ReviewCardActions) are already on the
/// screens that own them, and a second binding for the same keys would leave
/// which one fires to chance - so they are not repeated here.
struct StethoscoreCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Last Set in New Window") { openLastSetWindow() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!SetWindow.available)
        }
        CommandGroup(after: .textEditing) {
            // the library's search observes this (PlatformNotice.search)
            Button("Search Library") { PlatformNotice.post(PlatformNotice.search, ["text": ""]) }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("Study") {
            Button("Review Due Cards") { AppRouter.shared.open(.reviewDue) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    private func openLastSetWindow() {
        let raw: String = UserDefaults.standard.string(forKey: "cramdown.lastSetId") ?? ""
        guard let id = UUID(uuidString: raw) else { return }
        openWindow(id: SetWindow.sceneID, value: id)
    }
}
