import SwiftUI

/// The set list — matches the web app's `renderLibrary()` / `#libraryView`:
/// every saved set, tap to open into its mode's session, swipe to delete.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @State private var showNewSet = false
    @State private var exportURL: URL?
    @State private var exportFailedSetName: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.library.isEmpty {
                    ContentUnavailableView(
                        "No sets yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Create an MCQ quiz or an Anki deck to get started.")
                    )
                } else {
                    List {
                        ForEach(store.library) { set in
                            NavigationLink(value: set) {
                                setRow(set)
                            }
                            .swipeActions(edge: .leading) {
                                // matches the web app's per-mode "Export PDF" button
                                // (renderQuestionsPdf() and its siblings)
                                Button {
                                    if let url = PDFExporter.export(set) { exportURL = url }
                                    else { exportFailedSetName = set.name }
                                } label: {
                                    Label("Export PDF", systemImage: "arrow.down.doc")
                                }
                                .tint(.teal)
                            }
                        }
                        .onDelete { offsets in
                            // collect ids first — deleting shifts the indices
                            let ids = offsets.map { store.library[$0].id }
                            ids.forEach { store.deleteSet($0) }
                        }
                    }
                }
            }
            .navigationTitle("Red Pen")
            .navigationDestination(for: StudySet.self) { set in
                destination(for: set)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewSet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNewSet) {
                NewSetView()
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .alert("Couldn't export", isPresented: .init(
                get: { exportFailedSetName != nil },
                set: { if !$0 { exportFailedSetName = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong building the PDF for \(exportFailedSetName ?? "this set").")
            }
        }
    }

    private func setRow(_ set: StudySet) -> some View {
        HStack {
            Text(set.kind.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.body.weight(.medium))
                Text("\(set.kind.label) · \(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
