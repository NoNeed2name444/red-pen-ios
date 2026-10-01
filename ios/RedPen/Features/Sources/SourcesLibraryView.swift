import SwiftUI

/// Every lecture in the library, whichever sets it went into - and, before
/// there are any, a clear way to add the first one.
///
/// Adding a lecture is the screen's one main button: at the bottom, under
/// the thumb, on a phone; in the toolbar, with its name, on a wide iPad.
/// Holding a lecture lists every set made from it, to read it beside that
/// set's cards.
struct SourcesLibraryView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.windowSpan) private var span
    @State private var opening: SourceOpen?
    @State private var adding = false

    /// One lecture, once, with the sets made from it.
    struct Entry: Identifiable {
        var source: SourceDoc
        var sets: [StudySet]
        var id: String { source.fileBlob ?? "\(source.name)|\(source.pages.count)" }
    }

    /// A lecture to read, beside the cards of one of its sets.
    struct SourceOpen: Identifiable {
        let id = UUID()
        var source: SourceDoc
        var set: StudySet?
    }

    private var entries: [Entry] {
        var byID: [String: Entry] = [:]
        var order: [String] = []
        for set in store.library {
            for source in set.sources {
                let entry = Entry(source: source, sets: [set])
                if byID[entry.id] == nil {
                    byID[entry.id] = entry
                    order.append(entry.id)
                } else {
                    byID[entry.id]?.sets.append(set)
                }
            }
        }
        return order.compactMap { byID[$0] }.sorted { $0.source.addedAt > $1.source.addedAt }
    }

    var body: some View {
        let all: [Entry] = entries
        let broad: Bool = span == .broad
        return Group {
            if all.isEmpty {
                emptyState
            } else {
                list(all)
            }
        }
        .background(LibraryBackdrop())
        .navigationTitle("Sources")
        .toolbar {
            // a wide iPad has the room for the words, at the top; the empty
            // screen already has its own big button
            if broad && !all.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: {
                        Label("Add a lecture", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !broad && !all.isEmpty { addBar }
        }
        .sheet(item: $opening) { open in
            SourcePreviewView(source: open.source, set: open.set, openAt: 1)
        }
        .sheet(isPresented: $adding) { NewSetView() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No sources yet", systemImage: "doc.richtext")
        } description: {
            Text("Lectures, slides and notes you make sets from appear here, to read again page by page.")
        } actions: {
            Button("Add a lecture") { adding = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .popOut(.hero, in: Capsule())
        }
    }

    private func list(_ all: [Entry]) -> some View {
        List(all) { entry in
            Button { opening = SourceOpen(source: entry.source, set: entry.sets.first) } label: {
                SourceRow(entry: entry, symbol: symbol(entry.source.kind))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .contextMenu { setsMenu(entry) }
            .accessibilityIdentifier("source-row")
        }
        .scrollContentBackground(.hidden)
    }

    /// Every set made from the lecture: opening the lecture with that set's
    /// cards beside its pages.
    @ViewBuilder
    private func setsMenu(_ entry: Entry) -> some View {
        Button("Read", systemImage: "book") {
            opening = SourceOpen(source: entry.source, set: entry.sets.first)
        }
        Section("Made from it") {
            ForEach(entry.sets) { set in
                Button {
                    opening = SourceOpen(source: entry.source, set: set)
                } label: {
                    Label(set.name, systemImage: set.kind.symbol)
                }
            }
        }
    }

    /// The one main button, at the bottom under the thumb.
    private var addBar: some View {
        StudyActionBar {
            Button { adding = true } label: {
                Label("Add a lecture", systemImage: "plus")
            }
            .buttonStyle(.bigPrimary)
        }
    }

    private func symbol(_ kind: SourceDoc.Kind) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .word: return "doc.text"
        case .powerpoint: return "rectangle.on.rectangle"
        case .text: return "text.alignleft"
        }
    }
}

/// One lecture: its kind, its name, how long it is and how many sets came
/// from it.
private struct SourceRow: View {
    let entry: SourcesLibraryView.Entry
    let symbol: String

    private var detail: String {
        let source = entry.source
        let pages: Int = source.pages.count
        let pagePlural: String = pages == 1 ? "" : "s"
        let noun: String = source.kind.pageNoun.lowercased()
        let sets: Int = entry.sets.count
        let setPlural: String = sets == 1 ? "" : "s"
        let length: String = "\(pages) \(noun)\(pagePlural)"
        let made: String = "\(sets) set\(setPlural)"
        return "\(source.kind.label) \u{00B7} \(length) \u{00B7} \(made)"
    }

    var body: some View {
        let line: String = detail
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.source.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(line)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
