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
    @State var showAccount = false
    @State var exportURL: URL?
    @State var exportFailedSetName: String?

    // selection mode - the "Combine" / folder toggles
    @State var selecting = false
    @State var selected: Set<UUID> = []
    @State var naming: NamingSheet?
    @State var renaming: StudySet?
    /// A lecture being read from the library, rather than from a card.
    @State var reading: SourceOpening?
    @State var renamingFolder: StudyFolder?
    @State var editing: StudySet?
    @State var draftName = ""

    /// Which mode's shelf is showing. The whole screen takes its colour from
    /// this, so a swipe to Anki turns the navigation bar indigo instead of
    /// leaving MCQ's red over an indigo screen.
    @State var tab: LibraryTab = .all

    var pen: Color { tab.tint }

    var tabs: [LibraryTab] { LibraryTab.present(in: store.library) }
    func sets(in tab: LibraryTab) -> [StudySet] {
        guard let kind = tab.kind else { return store.library }
        return store.library.filter { $0.kind == kind }
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

    /// Which set the detail column is showing, on a screen wide enough to have
    /// one. The phone pushes instead, and leaves this alone.
    @State var chosen: StudySet.ID?
    @State private var opened: [StudySet] = []
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
                        withAnimation(.snappy(duration: 0.25)) {
                            // Dropping to one column with a set selected would
                            // leave that choice invisible and unreachable, so
                            // the selection becomes a pushed screen instead.
                            if span.splits, !now.splits {
                                if let set = store.library.first(where: { $0.id == chosen }) {
                                    opened = [set]
                                }
                                chosen = nil
                            } else if !span.splits, now.splits {
                                chosen = opened.last?.id
                                opened = []
                            }
                            span = now
                        }
                    }
            }
    }

    @ViewBuilder
    private var layout: some View {
        Group {
            if span.splits {
                // iPad, and a phone held sideways in Split View: the sets stay
                // on screen beside whatever is open, because a tablet's whole
                // advantage is not having to leave one thing to look at
                // another. A stack here would be a phone app blown up.
                // Columns pinned open, and a width given to the sidebar.
                // Left to itself the split view hid the sidebar in portrait and
                // showed nothing in its place - an iPad opening on a blank
                // white screen, which is what the first iPad screenshots
                // caught.
                NavigationSplitView(columnVisibility: $columns) {
                    attachingSheets(to: screen)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
                } detail: {
                    NavigationStack(path: $opened) {
                        detailColumn
                            .navigationDestination(for: StudySet.self) { destination(for: $0) }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // The same path the detail column uses, so a set stays open
                // across a resize: widen the window and it moves into the
                // second column, narrow it and it becomes a pushed screen.
                NavigationStack(path: $opened) {
                    attachingSheets(to: screen)
                }
            }
        }
        .tint(pen)
        .animation(.snappy(duration: 0.28), value: tab)
    }

    /// What fills the second column before a set has been chosen.
    @ViewBuilder
    private var detailColumn: some View {
        if let set = store.library.first(where: { $0.id == chosen }) {
            destination(for: set)
        } else {
            VStack(spacing: 14) {
                Brand.Mark(size: 54, tint: .secondary)
                    .opacity(0.5)
                Text("Choose a set")
                    .font(.title3.weight(.semibold))
                Text(Brand.line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LibraryBackdrop())
        }
    }

    private var screen: some View {
        content
            .background(LibraryBackdrop())
            .navigationTitle(Brand.name)
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) {
                // The selection bar takes the dock's place while it is up:
                // two floating bars stacked on one another is a pile, and
                // picking sets is a different job from choosing a mode.
                if selecting {
                    selectionBar
                } else if tabs.count > 1 {
                    ModeDock(tabs: tabs, selection: $tab) { sets(in: $0).count }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            dockHeight = $0
                        }
                }
            }
            .sheet(isPresented: $showAccount) { AccountView() }
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
                    dueBanner
                    summaryStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                if !loose.isEmpty {
                    Section {
                        ForEach(Array(loose.enumerated()), id: \.element.id) { i, set in
                            row(set).riseIn(index: i)
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
            // The dock floats over the list, so the last row needs somewhere
            // to end that is not behind glass.
            .id(tab)
            .transition(.opacity)
            .gesture(
                // A horizontal drag moves one tab along. The list keeps its own
                // vertical scrolling because the gesture only claims a drag
                // that is clearly sideways.
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.6,
                              abs(value.translation.width) > 60,
                              tabs.count > 1,
                              let here = tabs.firstIndex(of: tab) else { return }
                        let next = value.translation.width < 0 ? here + 1 : here - 1
                        guard tabs.indices.contains(next) else { return }
                        withAnimation(.snappy(duration: 0.28)) { tab = tabs[next] }
                    }
            )
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: StudyFolder) -> some View {
        let inside = members(of: folder)
        Section {
            ForEach(Array(inside.enumerated()), id: \.element.id) { i, set in
                row(set).riseIn(index: loose.count + i)
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

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if store.library.isEmpty {
                // toolbar items already sit in the system's glass on iOS 26; an
                // extra .glass style here squashed the label into a circle
                Button { showAccount = true } label: {
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
                Button("Account", systemImage: "person.crop.circle") { showAccount = true }
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
