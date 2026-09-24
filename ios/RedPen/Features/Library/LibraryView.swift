import SwiftUI

/// The set list: every saved set, tap to open into its mode's session, swipe to
/// delete, swipe the other way to export a PDF.
///
/// The rows are in LibraryRows and the sheets in LibrarySheets; what is left
/// here is the shape of the screen.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore

    @State var showNewSet = false
    @State var exportURL: URL?
    @State var exportFailedSetName: String?

    // selection mode - the "Combine" / folder toggles
    @State var selecting = false
    /// What the search field holds: set names, subjects and question stems.
    @State var query = ""
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
    /// Today's count and the streak, for the strip at the top.
    @ObservedObject var studyLog = StudyLog.shared

    /// Which mode's shelf is showing. The whole screen takes its colour from
    /// this, so a swipe to Anki turns the navigation bar indigo instead of
    /// leaving MCQ's red over an indigo screen.
    @State var tab: LibraryTab = .all
    /// Which way the last move along the dock went, so the new shelf slides
    /// in from the side the dock moved towards.
    @State private var tabForward = true
    /// The set whose "Turn into…" picker is up.
    @State var turning: StudySet?
    /// The set whose reasoning practice (cases, duels, scripts) is open.
    @State var reasoningFor: StudySet?
    /// A set just turned into another mode, to open; or New set, filled in.
    @ObservedObject var modeSwitch = ModeSwitch.shared

    var pen: Color { tab.tint }

    var tabs: [LibraryTab] { LibraryTab.present(in: store.library) }
    func sets(in tab: LibraryTab) -> [StudySet] {
        let inTab = tab.kind.map { kind in store.library.filter { $0.kind == kind } } ?? store.library
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return inTab }
        return inTab.filter { set in
            set.name.localizedCaseInsensitiveContains(words)
                || set.subject.localizedCaseInsensitiveContains(words)
                || set.questions.contains { $0.stem.localizedCaseInsensitiveContains(words) }
                || set.cards.contains { $0.front.localizedCaseInsensitiveContains(words) }
        }
    }

    enum NamingSheet: Identifiable {
        case folder, combine
        var id: Int { self == .folder ? 0 : 1 }
    }

    var selectedSets: [StudySet] { store.library.filter { selected.contains($0.id) } }
    var canCombine: Bool {
        selectedSets.count >= 2 && Set(selectedSets.map(\.kind)).count == 1
    }
    var loose: [StudySet] { shown.filter { $0.folderId == nil } }
    func members(of folder: StudyFolder) -> [StudySet] {
        shown.filter { $0.folderId == folder.id }
    }

    /// The sets the chosen tab is about.
    var shown: [StudySet] { sets(in: tab) }

    /// How tall the dock actually is, measured rather than guessed.
    ///
    /// The first attempt padded the list by a round number and the last row
    /// still ended up behind the glass. A floating bar's height depends on the
    /// text size the reader chose, so the only reliable number is the one the
    /// layout reports.
    @State private var dockHeight: CGFloat = 0

    /// Whatever is open in the main column: a set that was tapped, and on a
    /// wide window possibly a support page chosen in the sidebar instead.
    @State private var opened: [StudySet] = []
    @State var support: SupportPage?
    @State private var columns: NavigationSplitViewVisibility = .all

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
                        // The open set lives on the same path in both shapes,
                        // so widening or narrowing the window no longer loses
                        // it; only the sidebar's own page needs putting away.
                        withAnimation(.snappy(duration: 0.25)) {
                            if !now.splits { support = nil }
                            span = now
                        }
                    }
            }
    }

    @ViewBuilder
    private var layout: some View {
        Group {
            if span.splits {
                // The sets are the work, so they get the main column at full
                // width with the dock under them. The sidebar is for the
                // places you visit and come back from - account, settings,
                // how it works, questions. The first version had this the
                // wrong way round: the library squeezed into a 340-point
                // sidebar with a seven-mode dock crushed along its foot, and
                // a detail column that said "Choose a set" for most of the
                // day.
                NavigationSplitView(columnVisibility: $columns) {
                    SupportSidebar(chosen: $support)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
                } detail: {
                    NavigationStack(path: $opened) {
                        Group {
                            if let support {
                                support.page
                            } else {
                                attachingSheets(to: screen)
                            }
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $opened) {
                    attachingSheets(to: screen)
                        .navigationDestination(item: $support) { $0.page }
                }
            }
        }
        // one accent for the whole library rather than a colour per mode
        .tint(Color.accentColor)
        // "Turn into…": an instant set opens straight away, in place of
        // whatever was open; a written one goes to New set, filled in
        .onChange(of: modeSwitch.opening) { _, set in openTurned(set) }
        .sheet(item: $modeSwitch.writing) { preset in NewSetView(preset: preset) }
    }

    /// Opens a set that has just been made by turning another into it.
    ///
    /// It replaces what was open rather than going on top of it: turning the
    /// quiz you are in into cards means you are now in the cards, and Back
    /// goes to the library, not to the quiz you left.
    private func openTurned(_ set: StudySet?) {
        guard let set else { return }
        modeSwitch.opening = nil
        let shelf = LibraryTab(kind: set.kind)
        withAnimation(.snappy) {
            if tabs.contains(shelf) {
                tabForward = (tabs.firstIndex(of: shelf) ?? 0) >= (tabs.firstIndex(of: tab) ?? 0)
                tab = shelf
            }
            quickQuiz = nil
            support = nil
            opened = [set]
        }
    }

    /// The dock's choice, noting which way it moved on the way through.
    private var dockSelection: Binding<LibraryTab> {
        Binding(get: { tab }, set: { new in
            tabForward = (tabs.firstIndex(of: new) ?? 0) >= (tabs.firstIndex(of: tab) ?? 0)
            tab = new
        })
    }

    private var screen: some View {
        ZStack {
            // One shelf at a time, keyed by the tab, so a move along the dock
            // slides the new shelf in and fades the old one out rather than
            // swapping rows in place.
            content
                .id(tab)
                .transition(AnyTransition.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: AnyTransition.offset(x: tabForward ? 36 : -36)),
                    removal: AnyTransition.opacity))
        }
            // the shared backdrop, easing into the colour of the shelf
            .background(LibraryBackdrop(kind: tab.kind))
            .navigationTitle(Brand.name)
            .searchable(text: $query, prompt: "Sets, subjects, questions")
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            // Snapshotted when tapped rather than built live: a flag taken
            // off half way through the flagged quiz must not pull the
            // question out from under it.
            .navigationDestination(item: $quickQuiz) { MCQQuizView(set: $0, keepsProgress: false) }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) {
                // The selection bar takes the dock's place while it is up:
                // two floating bars stacked on one another is a pile, and
                // picking sets is a different job from choosing a mode.
                if selecting {
                    selectionBar
                } else if tabs.count > 1 {
                    ModeDock(tabs: tabs, selection: dockSelection) { sets(in: $0).count }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            dockHeight = $0
                        }
                }
            }
            // A tab whose last set has just been deleted would otherwise leave
            // the library showing an empty shelf with no way back.
            .onChange(of: store.library) { _, sets in
                if let kind = tab.kind, !sets.contains(where: { $0.kind == kind }) { tab = .all }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.library.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    // the personal build's tour of every feature
                    if PersonalBuild.isOn {
                        Button { support = .examples } label: {
                            Label("Try every feature \u{2014} worked examples", systemImage: "sparkles.rectangle.stack")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityIdentifier("examplesBanner")
                    }
                    Group {
                        examCountdown
                        streakRow
                        dueBanner
                        flaggedRow
                    }
                    // frosted, so the backdrop shows through while the
                    // text on it stays easy to read
                    .listRowBackground(Rectangle().fill(.regularMaterial))
                }
                if !loose.isEmpty {
                    Section {
                        ForEach(Array(loose.enumerated()), id: \.element.id) { i, set in
                            row(set)
                        }
                        .onDelete { offsets in delete(offsets.map { loose[$0].id }) }
                    } header: { sectionHeader("Your sets") }
                }
                ForEach(store.folders) { folder in
                    folderSection(folder)
                }
                if !selecting && tabs.count > 1 {
                    // A row of empty space as tall as the dock. Both
                    // safeAreaInset and contentMargins were supposed to keep
                    // the last card clear of the floating bar and neither did;
                    // a row cannot be ignored, because the list has to make
                    // room for it like any other.
                    Color.clear
                        .frame(height: dockHeight + 8)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: StudyFolder) -> some View {
        let inside = members(of: folder)
        // a folder with nothing of this mode (or nothing matching the
        // search) is not shown as an empty header
        if !inside.isEmpty || (tab.kind == nil && query.isEmpty) {
        Section {
            ForEach(Array(inside.enumerated()), id: \.element.id) { i, set in
                row(set)
            }
            .onDelete { offsets in delete(offsets.map { inside[$0].id }) }
        } header: {
            HStack {
                Label(folder.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Rename folder", systemImage: "pencil") {
                        draftName = folder.name; renamingFolder = folder
                    }
                    Button("Ungroup", systemImage: "folder.badge.minus") { store.ungroup(folder.id) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body)
                }
            }
            .textCase(nil)
        }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if store.library.isEmpty {
                // toolbar items already sit in the system's glass on iOS 26; an
                // extra .glass style here squashed the label into a circle
                Menu {
                    supportItems
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            } else {
                Button {
                    withAnimation(.snappy) { selecting.toggle(); selected = [] }
                } label: {
                    Text(selecting ? "Done" : "Select").fixedSize()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("New set", systemImage: "plus") { showNewSet = true }
                Section { supportItems }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            } primaryAction: {
                showNewSet = true
            }
            .buttonStyle(.glassProminent)
            .clipShape(Circle())
        }
    }

    /// Account, Settings, How it works, Questions - the sidebar's four, for a
    /// window too narrow to have a sidebar. Same pages, pushed instead.
    @ViewBuilder
    private var supportItems: some View {
        ForEach(SupportPage.shown) { page in
            // One state for both shapes: in the sidebar it decides what the
            // main column shows, on a phone it is what gets pushed. A
            // NavigationLink cannot live inside a Menu, so this is a button
            // either way.
            Button(page.title, systemImage: page.symbol) { support = page }
        }
    }

    func delete(_ ids: [UUID]) {
        ids.forEach { store.deleteSet($0) }
        // a deleted set's cards would otherwise keep their place in the
        // schedule for ever
        reviews.prune(keeping: store.library)
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
            if let url = try? ApkgExporter.export(set) { exportURL = url }
            else { exportFailedSetName = set.name }
            return
        }
        if let url = DeckPDF.export(set) { exportURL = url }
        else { exportFailedSetName = set.name }
    }

    @ViewBuilder
    private func destination(for set: StudySet) -> some View {
        switch set.kind {
        case .mcq: MCQQuizView(set: set)
        case .anki: AnkiReviewView(set: set)
        case .book: BookReaderView(set: set)
        case .qa: QACardsView(set: set)
        case .osce: OsceReviewView(set: set)
        case .narrate: NarrateReviewView(set: set)
        }
    }
}
