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

    var pen: Color { StudySetKind.mcq.tint }

    enum NamingSheet: Identifiable {
        case folder, combine
        var id: Int { self == .folder ? 0 : 1 }
    }

    var selectedSets: [StudySet] { store.library.filter { selected.contains($0.id) } }
    var canCombine: Bool {
        selectedSets.count >= 2 && Set(selectedSets.map(\.kind)).count == 1
    }
    var loose: [StudySet] { store.library.filter { $0.folderId == nil } }
    func members(of folder: StudyFolder) -> [StudySet] {
        store.library.filter { $0.folderId == folder.id }
    }

    var body: some View {
        NavigationStack {
            attachingSheets(to: screen)
        }
        .tint(pen)
    }

    private var screen: some View {
        content
            .background(LibraryBackdrop())
            .navigationTitle("Red Pen")
            .navigationDestination(for: StudySet.self) { destination(for: $0) }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .sheet(isPresented: $showAccount) { AccountView() }
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
            }
            .scrollContentBackground(.hidden)
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
