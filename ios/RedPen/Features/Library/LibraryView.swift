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

    /// Whatever is open in the main column: a set that was tapped, and on a
    /// wide window possibly a support page chosen in the sidebar instead.
    @State private var opened: [StudySet] = []
    @State private var support: SupportPage?
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
        ForEach(SupportPage.allCases) { page in
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
