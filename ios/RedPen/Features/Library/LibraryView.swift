import Combine
import SwiftUI
import UIKit

/// The app's one screen at the top: the floating dock's four categories -
/// Questions, Cards, OSCE, Audio - and Ideas beside them. For the
/// category chosen it shows its sets (tap to open, swipe to delete or export,
/// hold or tap the ellipsis for the rest), a tile for each of its modes above
/// them when it has more than one, and every way to practise them underneath.
/// Ideas swaps the page for the idea dump, its board and the 3D map.
///
/// Where things sit, for the hand that reaches them: what is tapped again and
/// again - the dock and New set - is at the bottom under the thumb (on a wide
/// iPad the dock stands on the leading edge as a rail, under the left hand,
/// and New set goes bottom-trailing, under the right); what is glanced at or
/// rarely needed - the title, search, the account and settings menu - is at
/// the top.
///
/// The rows are in LibraryRows, the category's tiles in LibraryCategory and
/// the sheets in LibrarySheets; what is left here is the shape of the screen.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore
    /// Read only, for search: notes are found here and opened in their editor;
    /// and counted for the home's brain map tile.
    @EnvironmentObject var noteStore: NoteStore
    /// Who is signed in, for the home's greeting.
    @EnvironmentObject var account: AccountStore

    /// New set, opened on this kind of set (the category's own, from its
    /// "+ New set").
    @State var newSetKind: StudySetKind?
    /// New set on this kind, opened at "where from" - a category's "Paste
    /// or import" tile.
    @State var addingKind: StudySetKind?
    @State var exportURL: URL?
    @State var exportFailedSetName: String?
    /// An Anki export waiting on "export without them?": picture cards whose
    /// pictures are not on this phone.
    @State var pendingDeckExport: PendingDeckExport?
    /// Whether an Anki deck is being built, so a second tap waits for it.
    @State var buildingDeck = false

    // selection mode - the "Combine" / folder toggles
    @State var selecting = false
    /// What the search field holds: set names, subjects and question stems.
    @State var query = ""
    /// The search field has the keyboard: ⌘F, `redpen://search` and the
    /// search intents put it there (PlatformNotice.search).
    @FocusState var searchFocused: Bool
    /// The search's index and results, worked out off the main thread
    /// (LibrarySearchModel).
    @StateObject var search = LibrarySearchModel()
    /// A card a search found, shown on its own.
    @State var foundCard: FoundCard?
    /// A note a search found, open in its editor.
    @State var foundNote: FoundNote?
    /// Whether "Build a session" is up, and the search it starts from.
    @State var buildingSession = false
    @State var sessionText = ""
    /// A custom session's cards, being reviewed.
    @State var sessionDeck: StudySet?
    @State var selected: Set<UUID> = []
    @State var naming: NamingSheet?
    @State var renaming: StudySet?
    /// A lecture being read from the library, rather than from a card.
    @State var reading: SourceOpening?
    @State var renamingFolder: StudyFolder?
    @State var editing: StudySet?
    @State var draftName = ""
    /// A quiz put together on the spot - the flagged questions, or a mix of
    /// the selected sets - opened without being saved to the library.
    @State var quickQuiz: StudySet?
    /// A quiz started from one of the category's tiles.
    @State var featureQuiz: InsightQuiz?
    /// A page opened from one of the category's tiles.
    @State var featurePage: CategoryFeature?
    /// A tile that had nothing to practise yet, for the alert that says so.
    @State var nothingYet: CategoryFeature?
    /// Whether the cards due across every deck are open.
    @State var showingDue = false
    /// Today's count and the streak, for the strip at the top.
    @ObservedObject var studyLog = StudyLog.shared

    /// Which category the dock has chosen. Questions first: it is where most
    /// of the studying is, and what the app opens on.
    @State var category: StudyCategory = .questions
    /// Whether the page is Ideas rather than a category. Never kept between
    /// launches: the app always opens on Questions.
    @State var inIdeas = false
    /// What the search field holds while Ideas is on show.
    @State var ideasQuery = ""
    /// Whether the software keyboard is up. The dock steps aside while it
    /// is, so the field being typed in is not squeezed between the two.
    @State var keyboardUp = false
    /// Whether the rest of the ways to practise are open.
    @State var morePractise = false
    /// Sets waiting on "Delete?" - swiped, from a row's menu, or in bulk.
    @State var pendingDelete: [UUID]?
    /// A set just made by Turn into, to bring into view when the library
    /// comes back from it.
    @State var arrived: UUID?
    @State private var restoredLastSet = false
    @AppStorage("cramdown.confirmDelete") var confirmDelete = true
    @AppStorage("cramdown.openLastSet") var openLastSet = false
    @AppStorage("cramdown.lastSetId") var lastSetId = ""
    /// Which of Ideas' views is open (IdeasView): only the 3D map keeps the sky.
    @AppStorage("vignette.ideas.mode") private var ideasModeRaw = IdeasMode.list.rawValue
    /// The phone's light or dark, for the dock: over the 3D map it is night.
    @Environment(\.colorScheme) private var scheme
    /// Which way the last move along the dock went, so the new page slides
    /// in from the side the dock moved towards.
    @State private var forward = true
    /// The set whose "Turn into…" picker is up.
    @State var turning: StudySet?
    /// The set whose reasoning practice (duels, scripts) is open.
    @State var reasoningFor: StudySet?
    /// The set whose sources and licences are open.
    @State var creditsFor: StudySet?
    /// A set just turned into another mode, to open; or New set, filled in.
    @ObservedObject var modeSwitch = ModeSwitch.shared

    /// Whether the search field holds anything.
    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The sets in a category - or, while searching, every set that matches,
    /// whatever its category: a search should not miss a set because the
    /// dock happened to be on another one. The matching is LibrarySearch's,
    /// done off the main thread; its name matches come first.
    func sets(in category: StudyCategory) -> [StudySet] {
        guard searching else {
            return store.library.filter { category.kinds.contains($0.kind) }
        }
        let found: [UUID] = search.results.sets
        let order: [UUID: Int] = Dictionary(found.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let matched: [StudySet] = store.library.filter { order[$0.id] != nil }
        return matched.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    /// How many sets each category holds, for the dock's spoken labels.
    func count(in category: StudyCategory) -> Int {
        store.library.filter { category.kinds.contains($0.kind) }.count
    }

    enum NamingSheet: Identifiable {
        case folder, combine
        var id: Int { self == .folder ? 0 : 1 }
    }

    var selectedSets: [StudySet] { store.library.filter { selected.contains($0.id) } }
    var canCombine: Bool {
        selectedSets.count >= 2 && Set(selectedSets.map(\.kind)).count == 1
    }
    /// Sets in no folder - or in one that is not here (deleted on another
    /// device, or a shared set that came with somebody else's folder), which
    /// would otherwise be a set shown nowhere at all.
    var loose: [StudySet] {
        let filed = Set(store.folders.map(\.id))
        return shown.filter { set in set.folderId.map { !filed.contains($0) } ?? true }
    }
    func members(of folder: StudyFolder) -> [StudySet] {
        shown.filter { $0.folderId == folder.id }
    }

    /// The sets the chosen category is about.
    var shown: [StudySet] { sets(in: category) }

    /// How tall the dock actually is, measured rather than guessed.
    ///
    /// The first attempt padded the list by a round number and the last row
    /// still ended up behind the bar. A floating bar's height depends on the
    /// text size the reader chose, so the only reliable number is the one the
    /// layout reports.
    @State private var dockHeight: CGFloat = 0
    /// Where the bottom bar (New set over the dock, or the selection bar)
    /// begins, in global points; nil while there is none (the keyboard has
    /// put it away). The page is not cut above it: its rows run on behind
    /// it (HomeFit); Start ward round keeps clear of its line (trimSlicedStart).
    @State private var barTop: CGFloat?

    /// Where the home's grid band ends, followed through a scroll without
    /// redrawing the list (HomeBandTrack).
    @State var bandTrack = HomeBandTrack()
    /// Where the set rows stand in the list, so a turn keeps the first one
    /// in view (HomeRowKeep); followed without redrawing the list.
    @State var rowTrack = HomeRowTrack()

    // The spacer marks the end of the library list for preview scrolling.
    private static let listEndID = "library-list-end"

    /// The sets opened on the stack.
    @State var opened: [StudySet] = []
    /// A page chosen from the account and settings menu (Vitals, lectures,
    /// account, settings, help...), pushed.
    @State var support: SupportPage?

    /// The window, not the screen: an iPad app can be a third of one, and the
    /// rows read this to choose between selecting and pushing.
    @State var span: WindowSpan = .slim
    /// A short window (HomeFit): New set stands up beside the account
    /// button, and the round shows its first beds, so the card and its
    /// button end above the dock.
    @State var shortWindow = false
    /// At large text, how many of the round's beds were taken off so the
    /// bar's line does not slice Start ward round (HomeFit.slices), and
    /// where Start was last laid out, in global points.
    @State var bedsTrimmed = 0
    @State var startFrame: CGRect = .zero
    /// At the accessibility text sizes the dock is one button over a list
    /// (CategoryDock), so it sits at the bottom even on a wide iPad.
    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        layout
            .environment(\.windowSpan, span)
            // the preview's fit check (HomeFitProbe); nothing outside it.
            // Past the default text size the page may scroll (HomeFit).
            .task {
                WardPartBook.shared.atRest = { [bandTrack] in bandTrack.isAtRest }
                HomeFitProbe.shared.large = typeSize > .large
                async let trip: Void = previewPushBack()
                await HomeFitProbe.shared.report()
                _ = await trip
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        let now = WindowSpan(width: size.width)
                        let short: Bool = HomeFit.isShort(height: Double(size.height), broad: now == .broad)
                        if short != shortWindow { shortWindow = short }
                        // In iPadOS 26 this changes while the student drags
                        // the window's edge. Not animated: animating it would
                        // cross-fade one column into two, and nothing in the
                        // app fades, so the layout simply changes.
                        guard now != span else { return }
                        // The open set and any pushed page live on the one
                        // stack, so widening or narrowing the window loses
                        // neither.
                        span = now
                    }
            }
            // home, its rail or dock and the open set on one side of a
            // fold's hinge, the base across it; measured inside, so the
            // span is the side's, not the window's
            .clearOfBand()
    }

    /// With `-uiPreviewPushBack` on the "library" preview, once home is up
    /// with its parts booked and a set to open, notes the book's part names,
    /// pushes the first set onto `opened` and pops it once a part of home
    /// has left the book (1.5 s at the soonest, 10 s at the most). A
    /// slow launch (AX5 on the SE's size takes about half a minute on a busy
    /// Mac) is waited for, up to 30 s, instead of being reported as no set.
    private func previewPushBack() async {
        guard PreviewLaunch.screen == "library", PreviewLaunch.pushBack else { return }
        do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
        for _ in 0..<300 where WardPartBook.shared.parts.isEmpty || (loose.first ?? shown.first) == nil {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard let set = loose.first ?? shown.first, !WardPartBook.shared.parts.isEmpty else {
            HomeFitProbe.shared.pushBackNoSet = true
            return
        }
        let before = WardPartBook.shared.parts
        HomeFitProbe.shared.beforePush = before.values.map(\.name)
        // home's cut and the faces it booked, before the push covers it
        let restCut: Double? = WardPartBook.shared.cut
        let faces: [Double] = before.values.map { Double($0.rect.minY) }
        WardPartBook.shared.resetDropCounts()
        opened = [set]
        // Home's parts leave the book once the pushed page covers it. A busy
        // Mac can take longer than 1.5 s to get there (one look then missed
        // it at random), so watch for it, up to 10 s, and pop no sooner
        // than 1.5 s in, as before.
        var lost = false
        var lastLookCount = before.count
        for tick in 1...100 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let duringPush = WardPartBook.shared.parts
            lastLookCount = duringPush.count
            let removed: Int = WardPartBook.shared.dropsRemoved + (before.keys.contains { duringPush[$0] == nil } ? 1 : 0)
            lost = lost || HomeFit.pushCovered(faces: faces, cut: restCut, removed: removed,
                                               kept: WardPartBook.shared.dropsKept)
            if lost && tick >= 15 { break }
        }
        HomeFitProbe.shared.pushLostParts = lost
        HomeFitProbe.shared.pushDropsRemoved = WardPartBook.shared.dropsRemoved
        HomeFitProbe.shared.pushDropsKept = WardPartBook.shared.dropsKept
        HomeFitProbe.shared.pushLastKeptCut = WardPartBook.shared.lastKeptCut
        HomeFitProbe.shared.pushBookCountBefore = before.count
        HomeFitProbe.shared.pushBookCountLastLook = lastLookCount
        opened = []
        HomeFitProbe.shared.pushBackDone = true
    }

    /// One stack on every shape of window: the dock (or the rail) chooses
    /// what the page shows, and the account menu holds the pages about the
    /// app, so a sidebar would only be the same places twice.
    private var layout: some View {
        NavigationStack(path: $opened) {
            attachingSheets(to: screen)
                .navigationDestination(item: pushedSupport) { $0.page }
        }
        // one accent for the whole library rather than a colour per mode:
        // the section's accent, in the tone that reads as text on the soft base
        .tint(Color.wardPrimaryInk)
        // "Turn into…": an instant set opens straight away, in place of
        // whatever was open; a written one goes to New set, filled in
        .onChange(of: modeSwitch.opening) { _, set in openTurned(set) }
        .sheet(item: $modeSwitch.writing) { preset in NewSetView(preset: preset) }
        // Ideas is a place in the dock now, not a pushed page: anything that
        // still asks for the old page is taken there instead.
        .onChange(of: support) { _, page in
            if page == .notes {
                support = nil
                goToIdeas()
            }
        }
        .task { restoreLastSet() }
        // the "section-switch" preview steps along the dock as a tap would
        .onReceive(NotificationCenter.default.publisher(for: PreviewExtras.dockStep)) { note in
            previewDockStep(toIdeas: note.object as? String == "ideas")
        }
        // the search's index follows the library and the notes; it is only
        // rebuilt while a search is showing
        .onReceive(store.$library) { search.libraryChanged($0) }
        .onReceive(noteStore.$notes) { search.notesChanged($0) }
        .onChange(of: query) { _, text in
            search.update(query: text)
            // a search is the student's own move: a turn's hold ends
            rowTrack.touched()
        }
        // so does a set added or removed, a folder made, picking sets, and
        // leaving home for a pushed page or coming back to it
        .onChange(of: store.library.count) { rowTrack.touched() }
        .onChange(of: store.folders.count) { rowTrack.touched() }
        .onChange(of: selecting) { rowTrack.touched() }
        .onChange(of: homeShowing) { rowTrack.touched() }
        .sheet(isPresented: $buildingSession) {
            CustomSessionSheet(text: sessionText) { set, mode in startSession(set, mode) }
        }
        .sheet(item: $foundCard) { found in
            FoundCardSheet(found: found) { set in opened.append(set) }
        }
        .sheet(item: $foundNote) { found in NoteEditorView(noteID: found.id).noteSourceChip(noteID: found.id) }
        // decks, tables and backups opened from other apps: the import preview
        // (waiting while one of the library's own sheets is up)
        .incomingImportPreview(busy: presentingSheet)
        // ⌘F, redpen://search and the search intents (AppRouter)
        .onReceive(PlatformNotice.publisher(PlatformNotice.search)) { note in
            openSearch(note.userInfo?["text"] as? String)
        }
        // Save to Ideas: the study screens' store, and a saved note's way
        // back to where it came from (LibrarySavedIdeas)
        .onAppear {
            LaunchStage.shared.mark("home", once: true)
            attachIdeaSaver()
        }
        .onReceive(PlatformNotice.publisher(PlatformNotice.openItem)) { note in
            if let source = note.userInfo?["source"] as? NoteSource { openSaved(source) }
        }
        .appLinksInPlace()
    }

    /// Whether one of the library's own sheets is up.
    var presentingSheet: Bool {
        let sets: Bool = newSetKind != nil || addingKind != nil || naming != nil || renaming != nil
        let edits: Bool = renamingFolder != nil || editing != nil || reading != nil || reasoningFor != nil
            || creditsFor != nil
        let found: Bool = buildingSession || foundCard != nil || foundNote != nil || exportURL != nil
        let turned: Bool = turning != nil || modeSwitch.writing != nil
        return sets || edits || found || turned
    }

    /// The library's search, open with the keyboard in it - back on the
    /// library itself, out of Ideas - and the text given, when there is one.
    private func openSearch(_ text: String?) {
        if !opened.isEmpty { opened = [] }
        support = nil
        if inIdeas { dockSelection.wrappedValue = category }
        if let text, !text.isEmpty { query = text }
        // after a pop back to the library has landed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            searchFocused = true
        }
    }

    /// The pushed support page - never Ideas, which is a place of its own.
    private var pushedSupport: Binding<SupportPage?> {
        Binding(get: {
            support == .notes ? nil : support
        }, set: { support = $0 })
    }

    /// "Open the last set on launch": once, at launch, if the set is still
    /// in the library and nothing else has been opened yet.
    private func restoreLastSet() {
        guard !restoredLastSet else { return }
        restoredLastSet = true
        guard openLastSet, opened.isEmpty else { return }
        guard let id = UUID(uuidString: lastSetId) else { return }
        guard let set = store.library.first(where: { $0.id == id }) else { return }
        opened = [set]
    }

    /// Opens a set that has just been made by turning another into it.
    ///
    /// It replaces what was open rather than going on top of it: turning the
    /// quiz you are in into cards means you are now in the cards, and Back
    /// goes to the library - on the new set's category - not to the quiz you
    /// left.
    private func openTurned(_ set: StudySet?) {
        guard let set else { return }
        modeSwitch.opening = nil
        withAnimation(Motion.gentle(.snappy(duration: 0.25))) {
            dockSelection.wrappedValue = StudyCategory(kind: set.kind)
            inIdeas = false
            arrived = set.id
            quickQuiz = nil
            featureQuiz = nil
            featurePage = nil
            support = nil
            opened = [set]
        }
    }

    /// The dock's choice, noting which way it moved on the way through.
    /// Choosing any category also leaves Ideas.
    private var dockSelection: Binding<StudyCategory> {
        Binding(get: { category }, set: { new in
            let all: [StudyCategory] = StudyCategory.allCases
            let to: Int = all.firstIndex(of: new) ?? 0
            let here: Int = all.firstIndex(of: category) ?? 0
            let from: Int = inIdeas ? IdeasPlace.order : here
            forward = to >= from
            inIdeas = false
            ideasQuery = ""
            category = new
        })
    }

    /// The dock's Ideas pill. Leaving Ideas is choosing a category, so only
    /// "on" does anything here.
    private var ideasSelection: Binding<Bool> {
        Binding(get: { inIdeas }, set: { on in
            if on { goToIdeas() }
        })
    }

    /// One step along the dock, as a tap on the next place would take it:
    /// each category, then Ideas, then back to Questions (a recording of the
    /// sections' hues shifting); or straight to Ideas.
    private func previewDockStep(toIdeas: Bool = false) {
        let all: [StudyCategory] = StudyCategory.allCases
        withAnimation(Motion.gentle(.snappy(duration: 0.3))) {
            if toIdeas {
                inIdeas = true
            } else if inIdeas {
                dockSelection.wrappedValue = all[0]
            } else if let i = all.firstIndex(of: category), i + 1 < all.count {
                dockSelection.wrappedValue = all[i + 1]
            } else {
                inIdeas = true
            }
        }
    }

    /// Ideas in place of the category's page. It sits after the four
    /// categories, so it always slides in from the trailing side.
    func goToIdeas() {
        withAnimation(Motion.gentle(.snappy(duration: 0.3))) {
            forward = true
            selecting = false
            selected = []
            query = ""
            inIdeas = true
        }
    }

    /// The new page comes in solid from the side the dock moved towards,
    /// and the old one goes at once: nothing fades. Under Reduce Motion the
    /// new page is simply there.
    private var pageTransition: AnyTransition {
        if UIAccessibility.isReduceMotionEnabled { return .identity }
        let shift: CGFloat = forward ? 36 : -36
        return AnyTransition.asymmetric(insertion: AnyTransition.offset(x: shift), removal: AnyTransition.identity)
    }

    /// The page and its chrome: the backdrop, the title and search at the
    /// top, the account menu, the rail and the bottom bar.
    private var screen: some View {
        routedPage
            .background { backdrop }
            .navigationTitle(screenTitle)
            .diagnosticsScreen("screen:library")
            .navigationBarTitleDisplayMode(.inline)
            // The search field and the account menu at the top, so they
            // never fight the dock at the bottom for the thumb. Drawn by the
            // page in Ward colours rather than in the system bar: the bar's
            // glass search field and its items changed style on their own
            // clock, a grey film over the page for most of a second after
            // light and dark switched (the owner, 14 Oct). Here they shift
            // with every other Ward colour (WardLookStore).
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { topRow }
            // the wide iPad's rail, under the left hand
            .safeAreaInset(edge: .leading, spacing: 0) { rail }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .modifier(KeyboardWatch(up: $keyboardUp))
            // the dock steps aside while typing, and the page runs to the
            // keyboard
            .onChange(of: keyboardUp) { _, up in if up { barTop = nil } }
            // Start ward round is whole above the bar's line or wholly past
            // it, never sliced by it, at any text size
            .onChange(of: startFrame) { trimSlicedStart() }
            .onChange(of: barTop) { trimSlicedStart() }
            .onChange(of: typeSize) { bedsTrimmed = 0 }
            .onChange(of: span) { bedsTrimmed = 0 }
            // the category's hue (or Ideas') on the paper's grid and the
            // controls' edges, shifting with the dock
            .wardSection(inIdeas ? .ideas : WardSection(rawValue: category.rawValue) ?? .questions)
            .onChange(of: homeShowing, initial: true) { _, showing in WardPaperTop.shared.home = showing }
            .onAppear { WardPaperTop.shared.home = homeShowing }
            .onDisappear { WardPaperTop.shared.home = false }
    }

    /// True while home itself is on screen, with no page pushed over it.
    private var homeShowing: Bool {
        opened.isEmpty && pushedSupport.wrappedValue == nil && quickQuiz == nil
            && featureQuiz == nil && featurePage == nil && !showingDue && sessionDeck == nil
    }

    /// The page, and everything it can push.
    private var routedPage: some View {
        let pageKey: String = inIdeas ? "ideas" : category.rawValue
        return ZStack {
            // One page at a time, keyed by it, so a move along the dock
            // slides the new page in and takes the old one away rather than
            // swapping rows in place.
            page
                .id(pageKey)
                .transition(pageTransition)
        }
            // The page is not cut above the bottom bar (the owner, 22 Oct:
            // the band under New set and the tabs was wrong): its rows run
            // on behind New set and the dock to the window's bottom edge,
            // and the row that ends the list lets the last one scroll clear
            // of them (HomeFit.endSpace). No soft edge under the bar either:
            // nothing at the bottom fades (the owner, 9 Oct).
            .scrollEdgeEffectHidden(true, for: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // a new page's list starts at its top, its header not yet seen
            .onChange(of: pageKey) {
                bandTrack.reset()
                WardPartBook.shared.clear()
                rowTrack.clear()
            }
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            // Snapshotted when tapped rather than built live: a flag taken
            // off half way through the flagged quiz must not pull the
            // question out from under it.
            .navigationDestination(item: $quickQuiz) { MCQQuizView(set: $0, keepsProgress: false) }
            .navigationDestination(item: $featureQuiz) { quiz in
                MCQQuizView(set: quiz.set, keepsProgress: false,
                            minReadSeconds: quiz.minReadSeconds, startsTimed: quiz.timed)
            }
            .navigationDestination(item: $featurePage) { featurePageView($0) }
            .navigationDestination(isPresented: $showingDue) { DueTodayView() }
            // a custom session's cards, reviewed and rescheduled where they live
            .navigationDestination(item: $sessionDeck) { AnkiReviewView(set: $0) }
            .alert(NothingYetAlert.title, isPresented: nothingYetShown, presenting: nothingYet) { _ in
                Button(NothingYetAlert.done, role: .cancel) {}
            } message: { feature in
                Text(feature.emptyText)
            }
    }

    /// The category's page, or Ideas.
    @ViewBuilder
    private var page: some View {
        if inIdeas {
            IdeasView(query: $ideasQuery, dockClearance: ideasClearance)
                // once Ideas is familiar: the map's theme (StudyTips)
                .tipSighting(.ideas)
                .ideasThemeTip(when: ideasQuery.isEmpty)
        } else {
            categoryPage
                .tipSighting(.library)
        }
    }

    /// The category's list; on a wide iPad, one column of a comfortable
    /// width rather than rows stretched across the whole window. The bar
    /// area over it is solid (the masthead).
    ///
    /// One list either way, its width capped by a value rather than drawn in
    /// a branch of its own: a branch per span made a new list whenever the
    /// span changed, so turning the phone on its side (874 points wide is
    /// broad) threw away the scroll and put the student back at the top
    /// (T0151, RotationStateUITests.testLibraryKeepsItsRow).
    private var categoryPage: some View {
        content
            .frame(maxWidth: span == .broad ? 820 : .infinity)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { HomeMasthead(track: bandTrack, band: bandShown) }
    }

    /// The band runs down from the window's top to just under the header,
    /// on a category's page at rest or scrolled, not while searching (the
    /// header steps aside), not in Ideas and never under the sky.
    private var bandShown: Bool { !inIdeas && !underSky && !searching }

    /// How far Ideas' lists run on past their last row: the dock's height,
    /// as they run on under it; nothing while the keyboard has put the dock
    /// away.
    private var ideasClearance: CGFloat {
        if keyboardUp { return 0 }
        return dockHeight
    }

    /// At large text the round can run on behind the bar and scroll, but
    /// with the page at rest the bar's line must not fall through Start ward
    /// round: half a button would stand behind New set and the dock. Then
    /// the round gives up a bed (Plan has the whole day) and Start rises
    /// clear. A page being scrolled is left alone.
    private func trimSlicedStart() {
        guard typeSize > .large, bedsTrimmed < 8, bandTrack.isAtRest,
              let barTop, startFrame.height > 0 else { return }
        let cut: Double = HomeFit.barLine(barTop: Double(barTop))
        if HomeFit.slices(minY: Double(startFrame.minY), maxY: Double(startFrame.maxY), cut: cut) {
            bedsTrimmed += 1
        }
    }

    /// The base under every page, Ideas' list and board too, with the grid
    /// band under a category page's header; only the 3D map keeps the sky
    /// it flies through.
    @ViewBuilder
    private var backdrop: some View {
        // one ground or the other at once, never cross-faded
        if underSky {
            AppBackdrop(tint: IdeasPlace.tint)
                .transition(.identity)
        } else {
            WardBackground()
                .overlay(alignment: .top) {
                    if bandShown { HomeBand(track: bandTrack).transition(.identity) }
                }
                .transition(.identity)
        }
    }

    private var underSky: Bool { inIdeas && ideasModeRaw == IdeasMode.space.rawValue }

    /// The dock is soft UI shaped from the base; over the 3D map's sky the
    /// base is the night one, so the dock is too.
    private var dockScheme: ColorScheme { underSky ? .dark : scheme }

    /// A category's page is titled by its own first row - the date, the
    /// app's name with its squiggle, a greeting (WardHome) - so the bar
    /// carries no title of its own there; Ideas keeps its name.
    private var screenTitle: String { inIdeas ? IdeasPlace.title : "" }

    /// The one search field at the top searches whatever is on show.
    private var searchText: Binding<String> { inIdeas ? $ideasQuery : $query }

    private var searchPrompt: String { inIdeas ? "Search ideas" : "Search questions, cards, notes" }

    /// The dock on end, on a wide iPad, while no sets are being picked -
    /// not at the accessibility text sizes, where it is at the bottom.
    private var railed: Bool { span == .broad && !typeSize.isAccessibilitySize }

    /// The dock on end, on a wide iPad, while no sets are being picked.
    @ViewBuilder
    private var rail: some View {
        if railed && !selecting {
            CategoryDock(selection: dockSelection, inIdeas: ideasSelection, axis: .vertical) { count(in: $0) }
                .environment(\.colorScheme, dockScheme)
                .environment(\.wardHeld, underSky)
                .wardUnlit()
                .launchEntrance()
                .transition(.slideIn(.leading))
        }
    }

    /// The selection bar while picking sets; otherwise New set over the dock.
    @ViewBuilder
    private var bottomBar: some View {
        // The selection bar takes the dock's place while it is up: two
        // floating bars stacked on one another is a pile, and picking sets
        // is a different job from choosing a category.
        if selecting {
            // measured like the dock, so the rows can still be scrolled
            // clear of it
            selectionBar
                // it floats on the page as the dock does, with no strip
                // under it, so no glow round it either (the owner, 9 Oct)
                .wardUnlit()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    dockHeight = $0
                }
                // where it begins (Start ward round keeps clear of its line)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    barTop = $0
                }
                .frame(maxWidth: .infinity)
                .transition(.slideIn(.bottom))
        } else if keyboardUp {
            // the dock steps aside while typing
            EmptyView()
        } else {
            // on a short window New set is up in the top row (HomeFit)
            let newSet: Bool = newSetShown && !shortWindow
            VStack(spacing: 10) {
                // An empty library has its own big button in the middle of
                // the page, so this one stays away until there is something
                // to list; Ideas has its own capture row instead.
                // arrives with the page's opening at the hand-off (LaunchStage)
                if newSet { newSetRow.launchEntrance().transition(.identity) }
                if !railed {
                    CategoryDock(selection: dockSelection, inIdeas: ideasSelection) { count(in: $0) }
                        .environment(\.colorScheme, dockScheme)
                        .environment(\.wardHeld, underSky)
                        .launchEntrance()
                }
            }
            // New set and the dock float on the page itself, with nothing
            // behind them but the page: no strip, no line, no cut of the
            // rows above them, so the page reads unbroken to the bottom (the
            // owner, 9 and 22 Oct). Without a glow round them, only their
            // edges.
            .wardUnlit()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                dockHeight = $0
            }
            // where the bar begins: Start ward round's line, and the
            // preview's fit check. Beside the rail with no New set (Ideas)
            // the bar holds nothing, and the page runs on to the bottom.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                HomeFitProbe.shared.bar = $0
                barTop = $0.height > 0 ? $0.minY : nil
            }
            .frame(maxWidth: .infinity)
            .transition(.slideIn(.bottom))
        }
    }

    /// Whether this page has a New set button: an empty library has its
    /// own big button in the middle, and Ideas its own capture row.
    private var newSetShown: Bool { !inIdeas && !store.library.isEmpty }

    /// New set on its own row over the dock, at the trailing end - under the
    /// right thumb on a phone, bottom-right under the right hand on a wide
    /// iPad.
    private var newSetRow: some View {
        let broad: Bool = span == .broad
        let cap: CGFloat? = broad ? nil : 560
        let side: CGFloat = broad ? 24 : 16
        let below: CGFloat = broad ? 16 : 0
        return HStack {
            Spacer(minLength: 0)
            newSetButton
        }
        .frame(maxWidth: cap)
        .padding(.horizontal, side)
        .padding(.bottom, below)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            List {
                Group {
                    // the page's title: the date, the name, a greeting and the
                    // countdown to the exam (WardHome)
                    if !searching { homeHeaderSection }
                    if store.library.isEmpty {
                        Section {
                            emptyState
                                .launchEntrance(inOpening: true)
                                .frostedListRow()
                        }
                    }
                    // Today's ward round - what is due, the weakest topic,
                    // something new, a station - in one card, and on Questions
                    // the Vitals and brain map tiles under it (WardHome).
                    homeRoundSections
                    // The modes first - one tile per kind of set here - where
                    // there is more than one. A category of one kind has its
                    // "See all" beside the heading over its sets instead.
                    if !searching && category.kinds.count > 1 { modesSection }
                    listBody
                }
                // The whole page already sits 16 points in from the paper
                // frame (SkyRoot), so the sections' own side margins would
                // inset the list a second time and squeeze it. Beside the
                // rail on a wide iPad they stay, to keep the list off it.
                .listSectionMargins(.horizontal, railed ? 16 : 0)
            }
            // the scale's 16, not a page's 24: Start ward round has to end
            // above New set, which floats over the list
            .listSectionSpacing(WardSpace.l)
            // the rows and parts that report where they stand at rest, so the
            // cut leaves no sliver of any (WardPartBook)
            .environment(\.wardPartsProbed, true)
            .scrollContentBackground(.hidden)
            // the masthead stands in for iOS's soft top edge (categoryPage)
            .scrollEdgeEffectHidden(true, for: .top)
            // how far the list has scrolled, for the grid band and the
            // masthead's line
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                bandTrack.scroll = y
            }
            .onScrollPhaseChange { _, phase in
                bandTrack.settle(idle: phase == .idle)
                // a finger on the list ends a turn's hold: the place is the
                // student's again. Not .animating: the phase cannot tell a
                // scroll to the top (the status bar) from the hold's own
                // scroll back, so that one ends at a rest at the top or when the
                // hold's window runs out (HomeRowKeep.Hold)
                if phase == .interacting { rowTrack.touched() }
                // a rest at the top (a scroll to the top) ends the hold; a
                // rest elsewhere may be the hold's own scroll back, so the
                // hold runs on to its window (HomeRowKeep.Hold). Where the
                // student came to rest is the place the next turn keeps,
                // noted once no row is held; at the top nothing is kept
                if phase == .idle {
                    rowTrack.settled(atTop: bandTrack.scroll < 1)
                    rowTrack.capture(atTop: bandTrack.scroll < 1)
                }
            }
            // The list's own frame and insets, so the rows' frames can be read
            // against what shows; a new size (the phone turned, the window
            // resized) scrolls the kept row back into view (HomeRowKeep).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowTrack.list = $0 }
            .onScrollGeometryChange(for: HomeRowTrack.Band.self) { geometry in
                HomeRowTrack.Band(size: geometry.containerSize, top: geometry.contentInsets.top,
                                  bottom: geometry.contentInsets.bottom)
            } action: { old, now in
                rowTrack.band = now
                // a turn or a resize changes the width; the keyboard, a
                // search or a set added or opened change only the height
                // or the rows, and are the student's own doing
                if old.size.width != now.size.width, old.size.width > 0, !searching { keepRow(proxy) }
            }
            // and again each time the list lays out while the row is held:
            // its new size, then the rows' new heights, arrive as the app
            // gets to them, which on a busy phone is seconds after the turn
            // (the hold ends at rest, after a second of a free app with no
            // new layout, or 8 seconds after the turn)
            .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                [geometry.containerSize.width, geometry.containerSize.height,
                 geometry.contentSize.width, geometry.contentSize.height]
            } action: { _, _ in
                guard let place = rowTrack.relaid() else { return }
                proxy.scrollTo(place.id, anchor: UnitPoint(x: 0.5, y: HomeRowKeep.anchor(place.fraction)))
            }
            // Back from a set that Turn into just made: the new set in view,
            // not somewhere below the fold.
            .onChange(of: opened.isEmpty) { _, back in
                guard back, let id = arrived else { return }
                arrived = nil
                withAnimation(Motion.gentle(.snappy(duration: 0.25))) { proxy.scrollTo(id, anchor: .center) }
            }
            .task(id: dockHeight) {
                guard PreviewLaunch.screen == "library-end", dockHeight > 0 else { return }
                // A measured dock does not mean List has laid out its rows yet.
                // Retry across layout passes, including any late inset updates,
                // rather than spending the preview's only scroll on an early pass.
                // This finishes in three seconds; the capture waits seven.
                for _ in 0..<12 {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(Self.listEndID, anchor: .bottom)
                }
            }
        }
    }

    /// Scrolls the row the student was on back into view after a turn: at
    /// once, on the next pass of the run loop, and again each time the list
    /// lays out while the turn settles (HomeRowKeep.Hold): until the list
    /// rests, the student moves it, a second of a free app passes with no
    /// new layout, or 8 seconds after the turn. Nothing kept, nothing moves.
    private func keepRow(_ proxy: ScrollViewProxy) {
        guard let held = rowTrack.turned() else { return }
        let anchor = UnitPoint(x: 0.5, y: HomeRowKeep.anchor(held.place.fraction))
        proxy.scrollTo(held.place.id, anchor: anchor)
        Task { @MainActor in
            guard let place = rowTrack.relaid() else { return }
            proxy.scrollTo(place.id, anchor: UnitPoint(x: 0.5, y: HomeRowKeep.anchor(place.fraction)))
        }
        // a tick at a time: a stalled main thread runs none, so only the
        // time the app was free counts toward the hold's window
        Task { @MainActor in
            for _ in 0..<HomeRowKeep.Hold<UUID>.ticks {
                try? await Task.sleep(for: .seconds(HomeRowKeep.Hold<UUID>.tick))
                rowTrack.expired(turn: held.turn)
            }
        }
    }

    /// Everything under the Today card and the modes: the sets, then the
    /// tiles, then the pages about the whole app.
    @ViewBuilder
    private var listBody: some View {
        if searching { searchScopeSection }
        if !searching || search.scope == .all { setsSections }
        if searching { searchItemsSection }
        if !searching {
            if category == .questions || category == .cards {
                Section {
                    buildSessionButton(from: "")
                }
                .wardButtonRow()
            }
            featureSection
            moreSection
            examplesSection
        }
        // A row of empty space as tall as the bottom bar - the dock, or
        // the selection bar in its place. Both safeAreaInset and
        // contentMargins were supposed to keep the last card clear of the
        // floating bar and neither did; a row cannot be ignored, because
        // the list has to make room for it like any other.
        // The page is not cut above the bar, so this row is what lets the
        // last card scroll wholly clear of it (HomeFit.endSpace).
        Color.clear
            .frame(height: CGFloat(HomeFit.endSpace(barHeight: Double(dockHeight))))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
            .id(Self.listEndID)
    }

    /// The category's sets: the loose ones, then each folder that holds any.
    @ViewBuilder
    private var setsSections: some View {
        if shown.isEmpty && searching && search.results.items.isEmpty && !search.busy {
            // a search that found nothing says so, rather than leaving a
            // blank page
            Section {
                WardEmptyState(symbol: "magnifyingglass", title: "No results for \u{201C}\(query)\u{201D}",
                               message: "Check the spelling or try a new search.")
                    .listRowBackground(Color.clear)
            }
        } else if shown.isEmpty && !searching && !store.library.isEmpty {
            // a search that found questions but no set is not an empty
            // category: no "Make one" under its results (audit #32)
            Section {
                emptyCategoryRow
            } header: { sectionHeader(category.setsHeading) }
        }
        if !loose.isEmpty {
            let firstId: UUID? = loose.first?.id
            Section {
                ForEach(loose) { set in
                    row(set)
                        // "hold a set for more", on the first (StudyTips)
                        .studyTip(.holdSet, when: set.id == firstId)
                }
                .onDelete { offsets in delete(offsets.map { loose[$0].id }) }
            } header: { setsHeader(searching ? "Sets" : category.setsHeading) }
        }
        ForEach(store.folders) { folder in
            folderSection(folder)
        }
    }

    /// "New set": the library's one main button, in the section's accent, over the dock.
    private var newSetButton: some View {
        Button { newSetKind = category.mainKind } label: {
            Label("New set", systemImage: "plus")
        }
        .buttonStyle(WardButtonStyle(kind: .primary, fills: false))
        .accessibilityHint("Make questions or cards from a lecture")
        .accessibilityIdentifier("newSetButton")
        .keyboardShortcut("n", modifiers: .command)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            HomeFitProbe.shared.newSet = $0
        }
    }

    /// New set on a short window: a round button in the top row, so the
    /// bar at the bottom is the dock alone and the round card fits above it.
    private var newSetCircle: some View {
        Button { newSetKind = category.mainKind } label: {
            Label("New set", systemImage: "plus")
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.wardPrimaryInk)
        }
        .buttonStyle(.wardCircle)
        .accessibilityHint("Make questions or cards from a lecture")
        .accessibilityIdentifier("newSetButton")
        .keyboardShortcut("n", modifiers: .command)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            HomeFitProbe.shared.newSet = $0
        }
    }

    /// Over the category's loose sets: the heading, "See all" for a category
    /// of one kind (its mode tile, since it has no Modes row), and Select.
    func setsHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            CategoryHeading(title: title, home: true)
            Spacer(minLength: 8)
            if !searching { seeAllButton }
            selectButton
        }
        .launchEntrance(inOpening: true)
        .textCase(nil)
    }

    /// The mode's own page of sets, for a category with only one kind.
    @ViewBuilder
    private var seeAllButton: some View {
        let single: Bool = category.kinds.count == 1
        if single, let mode = category.features(in: .modes).first, !mode.shelfSets(store).isEmpty {
            Button { start(mode) } label: { headerButtonFace("See all") }
                .buttonStyle(.borderless)
                .accessibilityHint("Every one of these sets, newest first")
                .accessibilityIdentifier("feature-\(mode.rawValue)")
        }
    }

    /// Select, to pick sets to move, mix, combine or delete; Done to stop.
    private var selectButton: some View {
        let title: String = selecting ? "Done" : "Select"
        let hint: String = selecting ? "Stop choosing sets" : "Choose sets to group, mix or combine"
        return Button {
            withAnimation(Motion.gentle(.snappy(duration: 0.25))) { selecting.toggle(); selected = [] }
        } label: {
            headerButtonFace(title)
        }
        .buttonStyle(.borderless)
        .accessibilityHint(hint)
        .accessibilityIdentifier("selectSets")
    }

    /// A sets header button's words: a link in the section's accent, in a
    /// 44-point target.
    private func headerButtonFace(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.wardPrimaryInk)
            .lineLimit(1)
            .contentTransition(.identity)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func folderSection(_ folder: StudyFolder) -> some View {
        let inside = members(of: folder)
        // the hold-a-set tip, when every set is in a folder
        let tipHere: Bool = folder.id == store.folders.first?.id && loose.isEmpty
        // a folder with nothing in this category (or nothing matching the
        // search) is not shown as an empty header
        if !inside.isEmpty {
        Section {
            ForEach(inside) { set in
                row(set)
                    .studyTip(.holdSet, when: tipHere && set.id == inside.first?.id)
            }
            .onDelete { offsets in delete(offsets.map { inside[$0].id }) }
        } header: {
            HStack {
                Label {
                    Text(folder.name).homeSmallCaps()
                } icon: {
                    Image(systemName: "folder.fill").foregroundStyle(Color.wardInkSecondary)
                }
                .font(.caption2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Button("Select sets", systemImage: "checkmark.circle") {
                        withAnimation(Motion.gentle(.snappy(duration: 0.25))) { selecting = true; selected = [] }
                    }
                    Button("Rename folder", systemImage: "pencil") {
                        draftName = folder.name; renamingFolder = folder
                    }
                    Button("Ungroup", systemImage: "folder.badge.minus") { store.ungroup(folder.id) }
                } label: {
                    // a control, so it stands out from the header
                    moreMenuFace
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.highlight)
                .accessibilityLabel("Folder options")
            }
            .launchEntrance(inOpening: true)
            .textCase(nil)
        }
        }
    }

    /// The top of home: the one search field, which searches whatever is on
    /// show, and the account menu beside it. While typing, Cancel takes the
    /// menu's place. At the accessibility sizes the field has a row of its
    /// own under them, so its prompt has the width to wrap whole.
    private var topRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: WardSpace.s) {
                    HStack(spacing: WardSpace.m) { topControls }
                    searchField
                }
            } else {
                HStack(spacing: WardSpace.m) {
                    searchField
                    topControls
                }
            }
        }
        .padding(.horizontal, WardSpace.l)
        .padding(.top, WardSpace.xs)
        .padding(.bottom, WardSpace.s)
        // over a category the header's paper band runs on behind it; in
        // Ideas the plain base, so nothing scrolled shows through
        .background {
            if !bandShown && !underSky {
                Color.wardWash
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .transition(.identity)
            }
        }
    }

    /// The search field: the magnifier, the field, and Clear once there is
    /// something to clear. Its prompt is drawn over it (SearchPrompt) rather
    /// than as its placeholder, which UIKit cut short on one line at every
    /// size ("Search questions, cards, no..."); VoiceOver still hears the
    /// field's own name.
    private var searchField: some View {
        HStack(spacing: WardSpace.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.wardInkSecondary)
                // a glyph, grown no further than AX1, leaving the prompt
                // its width
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                // kept in the layout while typing, so the field keeps its
                // height and the page does not jump
                SearchPrompt(text: searchPrompt)
                    .opacity(searchText.wrappedValue.isEmpty ? 1 : 0)
                TextField(searchPrompt, text: searchText, prompt: Text(verbatim: ""))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(Color.wardInk)
                    // its name said outright: with the placeholder emptied
                    // for SearchPrompt, UIKit's field had no description
                    .accessibilityLabel(Text(searchPrompt))
                    .accessibilityIdentifier("librarySearch")
            }
            if !searchText.wrappedValue.isEmpty {
                Button {
                    searchText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.wardInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .wardField()
    }

    /// Beside the search field (above it, at the accessibility sizes):
    /// Cancel while typing; otherwise the account menu, and a short window's
    /// New set beside it.
    @ViewBuilder
    private var topControls: some View {
        if searchFocused {
            Button("Cancel") {
                searchText.wrappedValue = ""
                searchFocused = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.wardPrimaryInk)
        } else {
            if shortWindow && newSetShown { newSetCircle }
            accountMenu
        }
    }

    /// Progress, the lectures, the tour of examples, account, settings and
    /// help - the pages about the app rather than one category, and seldom
    /// needed, so up here out of the thumb's way. The studying itself is in
    /// the dock; Select is beside the sets it picks from.
    private var accountMenu: some View {
        Menu {
            SupportMenuItems(chosen: $support)
        } label: {
            Label("Account and settings", systemImage: "person.crop.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.wardCircle)
        .accessibilityIdentifier("libraryMenu")
    }

    /// Every delete - a swipe, a row's menu, the selection bar - comes
    /// here, and asks first unless "Ask before deleting a set" is off.
    func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if confirmDelete {
            pendingDelete = ids
        } else {
            performDelete(ids)
        }
    }

    func performDelete(_ ids: [UUID]) {
        // the deleted sets' own cards, found before they go (see below)
        let doomed = Set(ids)
        let cards: [UUID] = store.library.filter { doomed.contains($0.id) }.flatMap { $0.cards.map(\.id) }
        ids.forEach { store.deleteSet($0) }
        // and its lecture recording with it: the file lives outside the
        // library, where the student cannot see or reach it once the set is gone
        ids.forEach { LectureAudio.remove(for: $0) }
        // a deleted set's cards would otherwise keep their place in the
        // schedule for ever - its own cards only: a blanket prune against the
        // library also dropped the schedules of decks a sync had not brought yet
        reviews.forget(cards)
        selected.subtract(ids)
        if selecting && selected.isEmpty {
            withAnimation(Motion.gentle(.snappy(duration: 0.25))) { selecting = false }
        }
    }

    /// Exports a set in whichever form keeps the most of it.
    ///
    /// Every mode prints as a flashcard deck - one question to a page, its
    /// answer overleaf - except Anki, which exports as .apkg. That is not an
    /// omission: an Anki deck's value is its schedule and its occlusion masks,
    /// and paper keeps neither, while .apkg keeps both and opens in the app
    /// the student already uses.
    func export(_ set: StudySet) {
        if set.kind == .anki {
            exportDeck(set)
            return
        }
        if let url = DeckPDF.export(set) { exportURL = url }
        else { exportFailedSetName = set.name }
    }

    /// An Anki deck, built off the main thread: its pictures are drawn one
    /// by one, and a big deck of diagrams froze the library while they were.
    ///
    /// Pictures a sync has fetched but not yet put back into the set are
    /// filled in from the cache first. Picture cards whose pictures are not on
    /// this phone at all cannot be drawn, and are asked about rather than
    /// silently missing from the deck the student imports.
    func exportDeck(_ set: StudySet, withoutMissing: Bool = false) {
        guard !buildingDeck else { return }
        let restored = BlobCache().restore(set)
        let missing = ApkgExporter.missingPictures(in: restored)
        if missing > 0 && !withoutMissing {
            pendingDeckExport = PendingDeckExport(set: restored, missing: missing)
            return
        }
        buildingDeck = true
        Task {
            defer { buildingDeck = false }
            do {
                exportURL = try await ApkgExporter.exportInBackground(restored, schedule: reviews.records)
            } catch {
                Diagnostics.record(.error, area: .export, message: "export.apkg_failed", error: error)
                ReviewPromptRules.noteTrouble()
                exportFailedSetName = set.name
            }
        }
    }

    private func destination(for set: StudySet) -> some View {
        // remembered for "Open the last set on launch"
        StudySetScreen(set: set)
            .onAppear { lastSetId = set.id.uuidString }
    }
}

/// Whether the software keyboard is up, so the dock can step aside while
/// something is being typed.
private struct KeyboardWatch: ViewModifier {
    @Binding var up: Bool

    private static var shows: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
    }

    private static var hides: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    }

    /// A keyboard tall enough to be the on-screen one - not the thin bar of
    /// shortcuts an iPad shows over a hardware keyboard.
    private static func isSoftKeyboard(_ note: Notification) -> Bool {
        let value: NSValue? = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        let frame: CGRect = value?.cgRectValue ?? .zero
        return frame.height > 140
    }

    func body(content: Content) -> some View {
        content
            .onReceive(KeyboardWatch.shows) { note in
                let soft: Bool = KeyboardWatch.isSoftKeyboard(note)
                withAnimation(Motion.gentle(.snappy(duration: 0.25))) { up = soft }
            }
            .onReceive(KeyboardWatch.hides) { _ in
                withAnimation(Motion.gentle(.snappy(duration: 0.25))) { up = false }
            }
    }
}

/// The search field's prompt, whole: on one line in the field's own size
/// where it fits, else a size or two smaller, else wrapped over two or more
/// lines, never cut and never broken inside a word. Past AX1 it grows no
/// further, so its longest word ("questions,") still fits the field; the
/// words typed grow on. VoiceOver reads the field's name instead.
private struct SearchPrompt: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1)
            Text(text).font(.callout).lineLimit(1)
            Text(text).font(.subheadline).lineLimit(1)
            Text(text).font(.footnote).lineLimit(1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.wardInkSecondary)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
