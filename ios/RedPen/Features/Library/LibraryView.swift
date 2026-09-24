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
    /// Whether the cards due across every deck are open, from the Today card.
    @State var showingDue = false
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

    /// The sets opened on this tab's stack.
    @State private var opened: [StudySet] = []
    /// A page chosen from the gear menu (account, settings, help...), pushed.
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

    /// One stack on every shape of window. The iPad sidebar used to live
    /// here, listing the support pages beside the sets; the app's four tabs
    /// (AppTabsView) are the sidebar now, and the support pages are behind
    /// the gear, so a second sidebar inside the Library tab would only be the
    /// same places twice.
    private var layout: some View {
        NavigationStack(path: $opened) {
            attachingSheets(to: screen)
                .navigationDestination(item: $support) { $0.page }
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
            .searchable(text: $query, prompt: "Search your sets")
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            // Snapshotted when tapped rather than built live: a flag taken
            // off half way through the flagged quiz must not pull the
            // question out from under it.
            .navigationDestination(item: $quickQuiz) { MCQQuizView(set: $0, keepsProgress: false) }
            .navigationDestination(isPresented: $showingDue) { DueTodayView() }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) {
                // The selection bar takes the dock's place while it is up:
                // two floating bars stacked on one another is a pile, and
                // picking sets is a different job from choosing a mode.
                if selecting {
                    selectionBar
                } else if !store.library.isEmpty {
                    // The one thing to do on this screen, always in the same
                    // place under the thumb, with the mode dock beneath it.
                    // An empty library has its own big button in the middle,
                    // so this stays away until there is something to list.
                    VStack(spacing: 8) {
                        newSetButton
                        if tabs.count > 1 {
                            ModeDock(tabs: tabs, selection: dockSelection) { sets(in: $0).count }
                        }
                    }
                    // the dock carries its own space underneath; the button
                    // alone needs some to clear the home indicator
                    .padding(.bottom, tabs.count > 1 ? 0 : 12)
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
                // Everything about today - the exam, the streak, what is due,
                // the flags - in one small card with one button, instead of
                // four separate strips stacked above the sets.
                if hasTodayCard {
                    Section {
                        todayCard
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                            // frosted, so the backdrop shows through while
                            // the text on it stays easy to read
                            .listRowBackground(Rectangle().fill(.regularMaterial))
                    }
                }
                if shown.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    // a search that found nothing says so, rather than
                    // leaving a blank page
                    Section {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    }
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
                if !selecting {
                    // A row of empty space as tall as the bottom bar. Both
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
            .listSectionSpacing(16)
            .scrollContentBackground(.hidden)
        }
    }

    /// The big "New set" button that sits at the bottom of the library.
    private var newSetButton: some View {
        Button { showNewSet = true } label: {
            Label("New set", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .accessibilityHint("Make questions or cards from a lecture")
        .accessibilityIdentifier("newSetButton")
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
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Folder options")
            }
            .textCase(nil)
        }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // The gear: account, settings, help and the lectures - the pages
        // that are about the app rather than a set. The studying itself is in
        // the tabs along the bottom (or the iPad sidebar).
        ToolbarItem(placement: .topBarLeading) {
            // toolbar items already sit in the system's glass on iOS 26;
            // an extra .glass style here squashed the label into a circle
            Menu {
                SupportMenuItems(chosen: $support)
            } label: {
                Label("Settings and help", systemImage: "gearshape")
            }
            .accessibilityIdentifier("libraryMenu")
        }
        if !store.library.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { selecting.toggle(); selected = [] }
                } label: {
                    Text(selecting ? "Done" : "Select").fixedSize()
                }
                .accessibilityHint(selecting ? "Stop choosing sets" : "Choose sets to group, mix or combine")
            }
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

    private func destination(for set: StudySet) -> some View {
        StudySetScreen(set: set)
    }
}
