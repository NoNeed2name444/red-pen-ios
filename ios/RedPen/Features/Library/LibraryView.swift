import SwiftUI

/// The set list — matches the web app's `renderLibrary()` / `#libraryView`:
/// every saved set, tap to open into its mode's session, swipe to delete,
/// swipe the other way to export a PDF.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @State private var showNewSet = false
    @State private var exportURL: URL?
    @State private var exportFailedSetName: String?

    private var pen: Color { StudySetKind.mcq.tint }

    var body: some View {
        NavigationStack {
            Group {
                if store.library.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            summaryStrip
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                        Section {
                            ForEach(store.library) { set in
                                NavigationLink(value: set) {
                                    setRow(set)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                                .swipeActions(edge: .leading) {
                                    // matches the web app's per-mode "Export PDF" button
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
                                let ids = offsets.map { store.library[$0].id }
                                ids.forEach { store.deleteSet($0) }
                            }
                        } header: {
                            Text("Your sets")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(LibraryBackdrop())
            .navigationTitle("Red Pen")
            .navigationDestination(for: StudySet.self) { set in
                destination(for: set)
            }
            .toolbar {
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
            .sheet(isPresented: $showNewSet) { NewSetView() }
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
        .tint(pen)
    }

    // MARK: pieces

    /// A row of small mode counters across the top — how many of each kind
    /// of set the library holds.
    private var summaryStrip: some View {
        let counts = Dictionary(grouping: store.library, by: \.kind).mapValues(\.count)
        let kinds = StudySetKind.allCases.filter { counts[$0] != nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    HStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.caption.weight(.semibold))
                        Text("\(counts[kind] ?? 0) \(kind.label)").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(kind.tint)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .glassEffect(.regular.tint(kind.tint.opacity(0.22)), in: .capsule)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func setRow(_ set: StudySet) -> some View {
        HStack(spacing: 14) {
            ModeTile(kind: set.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(set.kind.tint)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !set.subject.isEmpty && set.subject != "General" {
                        Text("·").foregroundStyle(.tertiary)
                        Text(set.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    ModeTile(kind: kind, size: 56)
                        .rotationEffect(.degrees(kind == .anki ? 0 : (kind == .mcq ? -10 : 10)))
                }
            }
            Text("Nothing here yet")
                .font(.title2.weight(.bold))
            Text("Make an MCQ quiz, an Anki deck, a textbook, a case set, an OSCE checklist, or a narrated transcript — all of it stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showNewSet = true } label: {
                Label("New set", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

/// The library's own backdrop: a warm paper tone with a whisper of pen red,
/// matching the web app's cream-and-red identity.
private struct LibraryBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(colors: [StudySetKind.mcq.tint.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: .init(x: 1.0, y: 0.0), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [StudySetKind.anki.tint.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: .init(x: 0.0, y: 1.0), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}
