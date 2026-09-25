import Combine
import SwiftUI
import UIKit

/// The app's one screen at the top: the floating dock's five categories -
/// Questions, Cards, Cases, OSCE, Audio - and Ideas beside them. For the
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
    /// Read only, for search: notes are found here and opened in their editor.
    @EnvironmentObject var noteStore: NoteStore

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
    /// Which way the last move along the dock went, so the new page slides
    /// in from the side the dock moved towards.
    @State private var forward = true
    /// The set whose "Turn into…" picker is up.
    @State var turning: StudySet?
    /// The set whose reasoning practice (cases, duels, scripts) is open.
    @State var reasoningFor: StudySet?
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
    /// still ended up behind the glass. A floating bar's height depends on the
    /// text size the reader chose, so the only reliable number is the one the
    /// layout reports.
    @State private var dockHeight: CGFloat = 0

    /// The sets opened on the stack.
    @State var opened: [StudySet] = []
    /// A page chosen from the account and settings menu (Progress, lectures,
    /// account, settings, help...), pushed.
    @State var support: SupportPage?

    /// The window, not the screen: an iPad app can be a third of one, and the
    /// rows read this to choose between selecting and pushing.
    @State var span: WindowSpan = .slim

    var body: some View {
        layout
            .environment(\.windowSpan, span)
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        let now = WindowSpan(width: w)
                        // Animated, because in iPadOS 26 this changes while the
                        // student is dragging the window's edge, and a layout
                        // that jumps between one column and two mid-drag is
                        // alarming in a way a quick crossfade is not.
                        guard now != span else { return }
                        // The open set and any pushed page live on the one
                        // stack, so widening or narrowing the window loses
                        // neither.
                        withAnimation(.snappy(duration: 0.25)) { span = now }
                    }
            }
    }

    /// One stack on every shape of window: the dock (or the rail) chooses
    /// what the page shows, and the account menu holds the pages about the
    /// app, so a sidebar would only be the same places twice.
    private var layout: some View {
        NavigationStack(path: $opened) {
            attachingSheets(to: screen)
                .navigationDestination(item: pushedSupport) { $0.page }
        }
        // one accent for the whole library rather than a colour per mode
        .tint(Color.accentColor)
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
        // the search's index follows the library and the notes; it is only
        // rebuilt while a search is showing
        .onReceive(store.$library) { search.libraryChanged($0) }
        .onReceive(noteStore.$notes) { search.notesChanged($0) }
        .onChange(of: query) { _, text in search.update(query: text) }
        .sheet(isPresented: $buildingSession) {
            CustomSessionSheet(text: sessionText) { set, mode in startSession(set, mode) }
        }
        .sheet(item: $foundCard) { found in
            FoundCardSheet(found: found) { set in opened.append(set) }
        }
        .sheet(item: $foundNote) { found in NoteEditorView(noteID: found.id) }
        // decks, tables and backups opened from other apps: the import preview
        // (waiting while one of the library's own sheets is up)
        .incomingImportPreview(busy: presentingSheet)
        // ⌘F, redpen://search and the search intents (AppRouter)
        .onReceive(PlatformNotice.publisher(PlatformNotice.search)) { note in
            openSearch(note.userInfo?["text"] as? String)
        }
    }

    /// Whether one of the library's own sheets is up.
    var presentingSheet: Bool {
        let sets: Bool = newSetKind != nil || addingKind != nil || naming != nil || renaming != nil
        let edits: Bool = renamingFolder != nil || editing != nil || reading != nil || reasoningFor != nil
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
        withAnimation(.snappy) {
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

    /// Ideas in place of the category's page. It sits after the five
    /// categories, so it always slides in from the trailing side.
    func goToIdeas() {
        withAnimation(.snappy(duration: 0.3)) {
            forward = true
            selecting = false
            selected = []
            query = ""
            inIdeas = true
        }
    }

    /// The new page comes in from the side the dock moved towards.
    private var pageTransition: AnyTransition {
        let shift: CGFloat = forward ? 36 : -36
        let arrive: AnyTransition = AnyTransition.opacity.combined(with: AnyTransition.offset(x: shift))
        return AnyTransition.asymmetric(insertion: arrive, removal: AnyTransition.opacity)
    }

    /// The page and its chrome: the backdrop, the title and search at the
    /// top, the account menu, the rail and the bottom bar.
    private var screen: some View {
        routedPage
            // the shared backdrop - the deepest plane - easing into the
            // category's colour, or Ideas' gold
            .background(AppBackdrop(tint: backdropTint))
            .navigationTitle(screenTitle)
            .diagnosticsScreen("screen:library")
            .navigationBarTitleDisplayMode(titleMode)
            // pinned in the bar's drawer at the top, so it never fights the
            // dock at the bottom for the thumb
            .searchable(text: searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: searchPrompt)
            .searchFocused($searchFocused)
            .toolbar { toolbarItems }
            // the wide iPad's rail, under the left hand
            .safeAreaInset(edge: .leading, spacing: 0) { rail }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .modifier(KeyboardWatch(up: $keyboardUp))
    }

    /// The page, and everything it can push.
    private var routedPage: some View {
        let pageKey: String = inIdeas ? "ideas" : category.rawValue
        return ZStack {
            // One page at a time, keyed by it, so a move along the dock
            // slides the new page in and fades the old one out rather than
            // swapping rows in place.
            page
                .id(pageKey)
                .transition(pageTransition)
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
            .alert("Nothing here yet", isPresented: nothingYetShown, presenting: nothingYet) { _ in
                Button("OK", role: .cancel) {}
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
                .ideasThemeTip()
        } else {
            categoryPage
                .tipSighting(.library)
        }
    }

    /// The category's list; on a wide iPad, one column of a comfortable
    /// width rather than rows stretched across the whole window.
    @ViewBuilder
    private var categoryPage: some View {
        if span == .broad {
            content
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }

    /// How far Ideas' lists run on past their last row, to clear the dock -
    /// nothing while the keyboard has put the dock away.
    private var ideasClearance: CGFloat { keyboardUp ? 0 : dockHeight }

    private var backdropTint: Color { inIdeas ? IdeasPlace.tint : category.tint }

    private var screenTitle: String { inIdeas ? IdeasPlace.title : Brand.name }

    private var titleMode: NavigationBarItem.TitleDisplayMode { inIdeas ? .inline : .automatic }

    /// The one search field at the top searches whatever is on show.
    private var searchText: Binding<String> { inIdeas ? $ideasQuery : $query }

    private var searchPrompt: String { inIdeas ? "Search ideas" : "Search questions, cards, notes" }

    /// The dock on end, on a wide iPad, while no sets are being picked.
    @ViewBuilder
    private var rail: some View {
        if span == .broad && !selecting {
            CategoryDock(selection: dockSelection, inIdeas: ideasSelection, axis: .vertical) { count(in: $0) }
                .transition(.move(edge: .leading).combined(with: .opacity))
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
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    dockHeight = $0
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if keyboardUp {
            // the dock steps aside while typing
            EmptyView()
        } else {
            VStack(spacing: 10) {
                // An empty library has its own big button in the middle of
                // the page, so this one stays away until there is something
                // to list; Ideas has its own capture row instead.
                if !inIdeas && !store.library.isEmpty { newSetRow }
                if span != .broad {
                    CategoryDock(selection: dockSelection, inIdeas: ideasSelection) { count(in: $0) }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                dockHeight = $0
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

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
                if store.library.isEmpty {
                    Section {
                        emptyState
                            .frostedListRow()
                    }
                }
                // Everything about today - the exam, the streak, what is
                // due, the flags - in one small card at the top.
                if showsTodayCard {
                    Section {
                        todayCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            // the card is its own raised slab; the row
                            // under it stays clear
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                // The modes first - one tile per kind of set here - where
                // there is more than one. A category of one kind has its
                // "See all" beside the heading over its sets instead.
                if !searching && category.kinds.count > 1 { modesSection }
                listBody
            }
            .listSectionSpacing(16)
            .scrollContentBackground(.hidden)
            // the backdrop's stars drift with the scroll (parallax)
            .skyScroll()
            // Back from a set that Turn into just made: the new set in view,
            // not somewhere below the fold.
            .onChange(of: opened.isEmpty) { _, back in
                guard back, let id = arrived else { return }
                arrived = nil
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// The Today card: on Questions whenever it has something to say, and on
    /// Cards when cards are waiting.
    private var showsTodayCard: Bool {
        if searching { return false }
        let onQuestions: Bool = category == .questions && hasTodayCard
        let dueNow: Int = category == .cards ? reviews.dueAcross(store.library).count : 0
        let onCards: Bool = category == .cards && dueNow > 0
        return onQuestions || onCards
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
        Color.clear
            .frame(height: dockHeight + 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
    }

    /// The category's sets: the loose ones, then each folder that holds any.
    @ViewBuilder
    private var setsSections: some View {
        if shown.isEmpty && searching && search.results.items.isEmpty && !search.busy {
            // a search that found nothing says so, rather than leaving a
            // blank page
            Section {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        } else if shown.isEmpty && !store.library.isEmpty {
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

    /// "New set": the library's one hero, standing highest out of the glass.
    private var newSetButton: some View {
        Button { newSetKind = category.mainKind } label: {
            Label("New set", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 22)
                .frame(minHeight: 50)
        }
        .buttonStyle(.glassProminent)
        // on the button itself, before the glass and the pop-out wrap it, so
        // UI tests find the button rather than its raised surface
        .accessibilityHint("Make questions or cards from a lecture")
        .accessibilityIdentifier("newSetButton")
        .popOut(.hero, in: Capsule(), tint: .accentColor)
        .keyboardShortcut("n", modifiers: .command)
    }

    /// Over the category's loose sets: the heading, "See all" for a category
    /// of one kind (its mode tile, since it has no Modes row), and Select.
    func setsHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            CategoryHeading(title: title)
            Spacer(minLength: 8)
            if !searching { seeAllButton }
            selectButton
        }
        .textCase(nil)
    }

    /// The mode's own page of sets, for a category with only one kind.
    @ViewBuilder
    private var seeAllButton: some View {
        let single: Bool = category.kinds.count == 1
        if single, let mode = category.features(in: .modes).first, !mode.shelfSets(store).isEmpty {
            // a control, so it stands out of the glass like Make one
            Button { start(mode) } label: { headerButtonFace("See all") }
                .buttonStyle(.glass)
                .popOut(.raised, in: Capsule())
                .accessibilityHint("Every one of these sets, newest first")
                .accessibilityIdentifier("feature-\(mode.rawValue)")
        }
    }

    /// Select, to pick sets to move, mix, combine or delete; Done to stop.
    private var selectButton: some View {
        let title: String = selecting ? "Done" : "Select"
        let hint: String = selecting ? "Stop choosing sets" : "Choose sets to group, mix or combine"
        return Button {
            withAnimation(.snappy) { selecting.toggle(); selected = [] }
        } label: {
            headerButtonFace(title)
        }
        .buttonStyle(.glass)
        .popOut(.raised, in: Capsule())
        .accessibilityHint(hint)
        .accessibilityIdentifier("selectSets")
    }

    /// A sets header button's words, tall enough that with the glass
    /// around them the button is a 44-point target.
    private func headerButtonFace(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(minHeight: 30)
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
                Label(folder.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Select sets", systemImage: "checkmark.circle") {
                        withAnimation(.snappy) { selecting = true; selected = [] }
                    }
                    Button("Rename folder", systemImage: "pencil") {
                        draftName = folder.name; renamingFolder = folder
                    }
                    Button("Ungroup", systemImage: "folder.badge.minus") { store.ungroup(folder.id) }
                } label: {
                    // a control, so it stands out of the glass
                    moreMenuFace
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.highlight)
                .accessibilityLabel("Folder options")
            }
            .textCase(nil)
        }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // One item, top-trailing: Progress, the lectures, the tour of
        // examples, account, settings and help - the pages about the app
        // rather than one category, and seldom needed, so up here out of
        // the thumb's way. The studying itself is in the dock; Select is
        // beside the sets it picks from.
        ToolbarItem(placement: .topBarTrailing) {
            // toolbar items already sit in the system's glass on iOS 26;
            // an extra .glass style here squashed the label into a circle
            Menu {
                SupportMenuItems(chosen: $support)
            } label: {
                Label("Account and settings", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("libraryMenu")
        }
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
            withAnimation(.snappy) { selecting = false }
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
                exportURL = try await ApkgExporter.exportInBackground(restored)
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
                withAnimation(.snappy) { up = soft }
            }
            .onReceive(KeyboardWatch.hides) { _ in
                withAnimation(.snappy) { up = false }
            }
    }
}
