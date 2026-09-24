import SwiftUI

/// A request to open a lecture at a particular page.
///
/// Identifiable so it can drive a `.sheet(item:)`, which is what makes "open
/// this source at page 12" one piece of state rather than two that can
/// disagree - a source with no page, or a page with no source.
struct SourceOpening: Identifiable, Equatable {
    var source: SourceDoc
    var page: Int
    var id: String { "\(source.id)-\(page)" }
}

/// Reading the lecture a set was made from.
///
/// Modelled on the readers people already know - a list of pages down one side,
/// the page itself filling the rest, a search that tells you where its matches
/// are rather than just jumping to one. What it adds is the thing a study app
/// can add and Preview cannot: the cards made from the page you are looking at,
/// sitting beside it.
///
/// It shows the real pages when this device still has the file, and the
/// extracted text when it does not. That second case is not a degraded mode to
/// apologise for - it is what a student sees on their second device, and it has
/// to be good enough to study from on its own.
struct SourcePreviewView: View {
    @Environment(\.modeTint) private var modeTint
    let source: SourceDoc
    /// The set this lecture belongs to, so a page can show what came off it.
    var set: StudySet?
    /// Where to open. A citation tapped on a card arrives here.
    @State var page: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span

    @State private var term = ""
    @State private var showingPages = false
    @State private var file: URL?
    /// The whole document, or one page with the cards made from it.
    @State private var whole = true
    @AppStorage(SourceScroll.storageKey) private var scrollRaw = SourceScroll.vertical.rawValue

    init(source: SourceDoc, set: StudySet? = nil, openAt: Int = 1) {
        self.source = source
        self.set = set
        _page = State(initialValue: openAt)
    }

    private var hits: [SourceSearch.Hit] {
        SourceSearch.hits(for: term, in: source.pages)
    }

    /// A sheet is only as wide as the window it opens in, so a page beside a
    /// search result is a luxury of a big window rather than of a big device.
    private var wide: Bool { span == .broad }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(source.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .searchable(text: $term, prompt: "Search this \(source.kind.label.lowercased())")
                .sheet(isPresented: $showingPages) { pageSheet }
                .task { file = SourceFiles.url(for: source) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !term.isEmpty {
            SourceResultsList(hits: hits, source: source) { found in
                page = found
                term = ""
            }
        } else if whole {
            SourceDocumentView(source: source, file: file, page: $page)
        } else if wide {
            HStack(spacing: 0) {
                SourcePageList(source: source, selected: $page)
                    .frame(width: 240)
                Divider()
                reader
            }
        } else {
            reader
        }
    }

    private var reader: some View {
        SourcePageReader(source: source, page: $page, set: set, file: file)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $whole) {
                Text("Document").tag(true)
                Text("Page").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
        if whole {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    scrollRaw = scrollRaw == SourceScroll.vertical.rawValue
                        ? SourceScroll.horizontal.rawValue : SourceScroll.vertical.rawValue
                } label: {
                    Label(scrollRaw == SourceScroll.vertical.rawValue ? "Scroll down" : "Page across",
                          systemImage: scrollRaw == SourceScroll.vertical.rawValue
                            ? "arrow.up.and.down.text.horizontal" : "arrow.left.and.right.text.vertical")
                }
                .accessibilityHint("Switches between scrolling down and paging across")
            }
        }
        if !wide && !whole {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPages = true
                } label: {
                    Label("Pages", systemImage: "sidebar.squares.left")
                }
                .accessibilityLabel("All \(source.kind.pageNoun.lowercased())s")
            }
        }
    }

    private var pageSheet: some View {
        NavigationStack {
            SourcePageList(source: source, selected: $page)
                .navigationTitle("\(source.pageCount) \(source.kind.pageNoun.lowercased())s")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingPages = false }
                    }
                }
        }
        .onChange(of: page) { _, _ in showingPages = false }
    }
}

/// The list of pages: number, first line, and whether the words were recognised
/// rather than read.
///
/// The first line earns its place. A column of bare numbers is no faster to
/// search than flicking through the document, which is the thing the list is
/// meant to save.
struct SourcePageList: View {
    @Environment(\.modeTint) private var modeTint
    let source: SourceDoc
    @Binding var selected: Int

    var body: some View {
        ScrollViewReader { scroll in
            // No `selection:` here: that binding wants an optional or a set,
            // and the highlight is drawn by the row itself anyway, which keeps
            // this working the same way inside a sheet and beside the reader.
            List(source.pages) { page in
                Button {
                    selected = page.number
                } label: {
                    row(page)
                }
                .buttonStyle(.plain)
                .listRowBackground(page.number == selected
                                   ? modeTint.opacity(0.12) : Color.clear)
                .id(page.number)
            }
            .listStyle(.plain)
            .onAppear { scroll.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, now in
                withAnimation { scroll.scrollTo(now, anchor: .center) }
            }
        }
    }

    private func row(_ page: SourceDoc.Page) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(page.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.isBlank ? "No text on this \(source.kind.pageNoun.lowercased())"
                                  : page.heading)
                    .font(.subheadline)
                    .foregroundStyle(page.isBlank ? .secondary : .primary)
                    .lineLimit(2)
                if page.recognised {
                    Label("Recognised", systemImage: "text.viewfinder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Search results, as somewhere to go rather than a jump.
///
/// Showing every match with the words around it is what makes a search useful
/// for revision: "where does she talk about complement" is answered by the list
/// itself, often without opening a page at all.
struct SourceResultsList: View {
    @Environment(\.modeTint) private var modeTint
    let hits: [SourceSearch.Hit]
    let source: SourceDoc
    let open: (Int) -> Void

    var body: some View {
        Group {
            if hits.isEmpty {
                ContentUnavailableView("Not in this \(source.kind.label.lowercased())",
                                       systemImage: "magnifyingglass",
                                       description: Text("No \(source.kind.pageNoun.lowercased()) mentions it."))
            } else {
                List {
                    Section {
                        ForEach(hits) { hit in
                            Button { open(hit.page) } label: { row(hit) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(hits.count) \(hits.count == 1 ? "mention" : "mentions") on \(SourceSearch.pagesMatched(hits)) \(source.kind.pageNoun.lowercased())s")
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func row(_ hit: SourceSearch.Hit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(source.kind.pageNoun) \(hit.page)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(modeTint)
            marked(hit)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// The snippet with the match itself emphasised, using the range the search
    /// already worked out rather than looking for the term a second time.
    private func marked(_ hit: SourceSearch.Hit) -> Text {
        let characters = Array(hit.snippet)
        guard hit.range.lowerBound >= 0, hit.range.upperBound <= characters.count else {
            return Text(hit.snippet)
        }
        let before = String(characters[..<hit.range.lowerBound])
        let match = String(characters[hit.range])
        let after = String(characters[hit.range.upperBound...])
        return Text(before) + Text(match).bold().foregroundColor(modeTint) + Text(after)
    }
}
