import SwiftUI

/// The set list: every saved set, tap to open into its mode's session, swipe to
/// delete, swipe the other way to export a PDF. The rows themselves are in
/// LibraryRows.
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
            content
                .background(LibraryBackdrop())
                .navigationTitle("Red Pen")
                .navigationDestination(for: StudySet.self) { destination(for: $0) }
                .toolbar { toolbarItems }
                .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
                .modifier(LibrarySheets())
        }
        .tint(pen)
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
        if !store.library.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                // toolbar items already sit in the system's glass on iOS 26; an
                // extra .glass style here squashed the label into a circle
                Button {
                    withAnimation(.snappy) { selecting.toggle(); selected = [] }
                } label: {
                    Text(selecting ? "Done" : "Select").fixedSize()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showNewSet = true } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
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

    func export(_ set: StudySet) {
        if let url = PDFExporter.export(set) { exportURL = url }
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

    /// Every sheet and alert the library can raise, kept together so the main
    /// body stays one screen long.
    private struct LibrarySheets: ViewModifier {
        func body(content: Content) -> some View { content }
    }
}
