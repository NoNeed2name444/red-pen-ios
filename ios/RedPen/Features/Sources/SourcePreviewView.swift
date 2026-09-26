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
    /// False while the whole document is in Quick Look, which cannot be sent
    /// to a page - so no page list is offered there.
    @State private var documentFollowsPage = true
    /// This reader, for the slip a passage saved to Ideas shows.
    @State private var ideaHost = UUID()

    init(source: SourceDoc, set: StudySet? = nil, openAt: Int = 1) {
        self.source = source
        self.set = set
        _page = State(initialValue: openAt)
    }

    private var hits: [SourceSearch.Hit] {
        SourceSearch.hits(for: term, in: source.pages)
    }

    /// A sheet is only as wide as the window it opens in, so a page list
    /// beside the reader is a luxury of a big window rather than of a big
    /// device.
    private var wide: Bool { span == .broad }

    /// Whether picking a page moves what is on screen. Page view always
    /// does; Document view does unless the file is in Quick Look.
    private var pageAware: Bool { !whole || documentFollowsPage }

    /// The page list beside the reader: a wide window, and a reader that
    /// can follow it.
    private var sidebar: Bool { wide && pageAware }

    private var searchPrompt: String {
        "Search this \(source.kind.label.lowercased())"
    }

    var body: some View {
        NavigationStack {
            content
                // the deep plane: the same slow mesh as every other screen,
                // behind the glass, so the reader is not a flat sheet
                .background(LibraryBackdrop())
                .navigationTitle(source.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                // search stays at the top, out of the thumb's way
                .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .automatic),
                            prompt: searchPrompt)
                // Document / Page, the page list and the pager, under the
                // thumb; out of the way while the results are showing
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if term.isEmpty { bar }
                }
                .sheet(isPresented: $showingPages) { pageSheet }
                .task { file = SourceFiles.url(for: source) }
                // a passage selected on a page: Save to Ideas in its menu
                .environment(\.ideaPassage, passageSaver)
                .saveToIdeasHost(ideaHost)
        }
    }

    /// Keeps a passage in the lecture's note in Ideas, filed under its set's
    /// subject; nil when the lecture's set is not known.
    private var passageSaver: IdeaPassageSaver? {
        guard let set else { return nil }
        let lecture: SourceDoc = source
        let host: UUID = ideaHost
        return IdeaPassageSaver { text, page in
            let clip: IdeaClip = SaveToIdeas.clip(passage: text, page: page, of: lecture, in: set)
            IdeaSaver.shared.save(clip, host: host)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !term.isEmpty {
            SourceResultsList(hits: hits, source: source) { found in
                page = found
                term = ""
            }
        } else {
            // the page list stays beside the reader in both views; one
            // HStack either way, so the reader is not rebuilt (and a Word
            // file not converted again) when the list comes or goes
            HStack(spacing: 0) {
                if sidebar {
                    SourcePageList(source: source, selected: $page)
                        .frame(width: 240)
                    Divider()
                }
                reading
            }
        }
    }

    @ViewBuilder
    private var reading: some View {
        if whole {
            SourceDocumentView(source: source, file: file, page: $page,
                               followsPage: $documentFollowsPage)
        } else {
            SourcePageReader(source: source, page: $page, set: set, file: file)
        }
    }

    private var bar: some View {
        let pagesButton: Bool = !wide && pageAware
        return ReaderBar(whole: $whole, page: $page, pageCount: source.pageCount,
                         pageNoun: source.kind.pageNoun, showsPages: pagesButton,
                         openPages: { showingPages = true })
    }

    private var pageSheet: some View {
        let noun: String = source.kind.pageNoun.lowercased()
        let title: String = "\(source.pageCount) \(noun)s"
        return NavigationStack {
            SourcePageList(source: source, selected: $page)
                .background(LibraryBackdrop())
                .navigationTitle(title)
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
            // clear, so the backdrop behind the reader shows through
            .scrollContentBackground(.hidden)
            .onAppear { scroll.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, now in
                withAnimation { scroll.scrollTo(now, anchor: .center) }
            }
        }
    }

    private func firstLine(_ page: SourceDoc.Page) -> String {
        guard page.isBlank else { return page.heading }
        let noun: String = source.kind.pageNoun.lowercased()
        return "No text on this \(noun)"
    }

    private func row(_ page: SourceDoc.Page) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(page.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(firstLine(page))
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
                        Text(heading)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// "5 mentions on 3 pages".
    private var heading: String {
        let found: Int = hits.count
        let mentions: String = found == 1 ? "mention" : "mentions"
        let pages: Int = SourceSearch.pagesMatched(hits)
        let noun: String = source.kind.pageNoun.lowercased()
        return "\(found) \(mentions) on \(pages) \(noun)s"
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
        return Text("\(before)\(Text(match).bold().foregroundColor(modeTint))\(after)")
    }
}
