import SwiftUI

/// The app's one screen at the top: the floating dock's five categories -
/// Questions, Cards, Cases, OSCE, Audio - and, for the one chosen, its sets
/// (tap to open, swipe to delete or export, hold for the rest) with every way
/// to practise them underneath as big tiles.
///
/// The rows are in LibraryRows, the category's tiles in LibraryCategory and
/// the sheets in LibrarySheets; what is left here is the shape of the screen.
/// Everything that is about the app rather than a category - Ideas, Progress,
/// lectures, the tour of examples, account, settings, help - is behind the
/// gear.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore

    /// New set, opened on this kind of set (the category's own, from its
    /// "+ New set").
    @State var newSetKind: StudySetKind?
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
    /// dock happened to be on another one.
    func sets(in category: StudyCategory) -> [StudySet] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else {
            return store.library.filter { category.kinds.contains($0.kind) }
        }
        return store.library.filter { set in
            set.name.localizedCaseInsensitiveContains(words)
                || set.subject.localizedCaseInsensitiveContains(words)
                || set.questions.contains { $0.stem.localizedCaseInsensitiveContains(words) }
                || set.cards.contains { $0.front.localizedCaseInsensitiveContains(words) }
        }
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
    var loose: [StudySet] { shown.filter { $0.folderId == nil } }
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

    /// One stack on every shape of window: the dock chooses what the page
    /// shows, and the gear holds the pages about the app, so a sidebar would
    /// only be the same places twice.
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
    /// goes to the library - on the new set's category - not to the quiz you
    /// left.
    private func openTurned(_ set: StudySet?) {
        guard let set else { return }
        modeSwitch.opening = nil
        withAnimation(.snappy) {
            dockSelection.wrappedValue = StudyCategory(kind: set.kind)
            quickQuiz = nil
            featureQuiz = nil
            featurePage = nil
            support = nil
            opened = [set]
        }
    }

    /// The dock's choice, noting which way it moved on the way through.
    private var dockSelection: Binding<StudyCategory> {
        Binding(get: { category }, set: { new in
            let all: [StudyCategory] = StudyCategory.allCases
            let to: Int = all.firstIndex(of: new) ?? 0
            let from: Int = all.firstIndex(of: category) ?? 0
            forward = to >= from
            category = new
        })
    }

    /// The new page comes in from the side the dock moved towards.
    private var pageTransition: AnyTransition {
        let shift: CGFloat = forward ? 36 : -36
        let arrive: AnyTransition = AnyTransition.opacity.combined(with: AnyTransition.offset(x: shift))
        return AnyTransition.asymmetric(insertion: arrive, removal: AnyTransition.opacity)
    }

    private var screen: some View {
        ZStack {
            // One category at a time, keyed by it, so a move along the dock
            // slides the new page in and fades the old one out rather than
            // swapping rows in place.
            content
                .id(category)
                .transition(pageTransition)
        }
            // the shared backdrop, easing into the category's colour
            .background(AppBackdrop(tint: category.tint))
            .navigationTitle(Brand.name)
            .searchable(text: $query, prompt: "Search your sets")
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            // Snapshotted when tapped rather than built live: a flag taken
            // off half way through the flagged quiz must not pull the
            // question out from under it.
            .navigationDestination(item: $quickQuiz) { MCQQuizView(set: $0, keepsProgress: false) }
            .navigationDestination(item: $featureQuiz) { quiz in
                MCQQuizView(set: quiz.set, keepsProgress: false,
                            minReadSeconds: quiz.minReadSeconds, startsTimed: quiz.timed)
            }
            .navigationDestination(item: $featurePage) { $0.page }
            .navigationDestination(isPresented: $showingDue) { DueTodayView() }
            .alert("Nothing here yet", isPresented: nothingYetShown, presenting: nothingYet) { _ in
                Button("OK", role: .cancel) {}
            } message: { feature in
                Text(feature.emptyText)
            }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) { bottomBar }
    }

    /// The selection bar while picking sets; otherwise New set over the dock.
    @ViewBuilder
    private var bottomBar: some View {
        // The selection bar takes the dock's place while it is up: two
        // floating bars stacked on one another is a pile, and picking sets
        // is a different job from choosing a category.
        if selecting {
            selectionBar
        } else {
            VStack(spacing: 10) {
                // An empty library has its own big button in the middle of
                // the page, so this one stays away until there is something
                // to list.
                if !store.library.isEmpty { newSetButton }
                CategoryDock(selection: dockSelection) { count(in: $0) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                dockHeight = $0
            }
        }
    }

    private var content: some View {
        List {
            if store.library.isEmpty {
                Section {
                    emptyState
                        .frostedListRow()
                }
            }
            // Everything about today - the exam, the streak, what is due,
            // the flags - in one small card on the first page.
            if category == .questions && hasTodayCard && !searching {
                Section {
                    todayCard
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                        // frosted, so the backdrop shows through while
                        // the text on it stays easy to read
                        .frostedListRow()
                }
            }
            setsSections
            if !searching {
                featureSection
                examplesSection
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

    /// The category's sets: the loose ones, then each folder that holds any.
    @ViewBuilder
    private var setsSections: some View {
        if shown.isEmpty && searching {
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
            Section {
                ForEach(loose) { set in
                    row(set)
                }
                .onDelete { offsets in delete(offsets.map { loose[$0].id }) }
            } header: { sectionHeader(searching ? "Found" : category.setsHeading) }
        }
        ForEach(store.folders) { folder in
            folderSection(folder)
        }
    }

    /// The big "New set" button that sits over the dock.
    private var newSetButton: some View {
        Button { newSetKind = category.mainKind } label: {
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
        // a folder with nothing in this category (or nothing matching the
        // search) is not shown as an empty header
        if !inside.isEmpty {
        Section {
            ForEach(inside) { set in
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
        // The gear: Ideas, Progress, the lectures, the tour of examples,
        // account, settings and help - the pages that are about the app
        // rather than one category. The studying itself is in the dock.
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
