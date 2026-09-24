import SwiftUI

/// Every lecture in the library, whichever sets it went into - and, before
/// there are any, a clear way to add the first one.
struct SourcesLibraryView: View {
    @EnvironmentObject private var store: Store
    @State private var opening: Entry?
    @State private var adding = false

    /// One lecture, once, with the sets made from it.
    struct Entry: Identifiable {
        var source: SourceDoc
        var sets: [StudySet]
        var id: String { source.fileBlob ?? "\(source.name)|\(source.pages.count)" }
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
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No sources yet", systemImage: "doc.richtext")
                } description: {
                    Text("Lectures, slides and notes you make sets from appear here, to read again page by page.")
                } actions: {
                    Button("Add a lecture") { adding = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                List(entries) { entry in
                    Button { opening = entry } label: {
                        HStack(spacing: 14) {
                            Image(systemName: symbol(entry.source.kind))
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.source.name).font(.body.weight(.semibold)).lineLimit(2)
                                Text("\(entry.source.kind.label) \u{00B7} \(entry.source.pages.count) \(entry.source.kind.pageNoun.lowercased())\(entry.source.pages.count == 1 ? "" : "s") \u{00B7} \(entry.sets.count) set\(entry.sets.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("source-row")
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(LibraryBackdrop())
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a lecture")
            }
        }
        .sheet(item: $opening) { entry in
            SourcePreviewView(source: entry.source, set: entry.sets.first, openAt: 1)
        }
        .sheet(isPresented: $adding) { NewSetView() }
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
