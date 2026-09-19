import SwiftUI

/// The reader — matches `#bookView`: title + word count, the page, a
/// Previous / Next bar with "Page X of Y — title", and a table of contents.
struct BookReaderView: View {
    let studySet: StudySet
    private let pages: [BookPage]
    @State private var index = 0
    @State private var showToc = false
    @EnvironmentObject private var store: Store

    init(set studySet: StudySet, page: Int = 0) {
        self.studySet = studySet
        self.pages = BookPages.split(studySet.bookMarkdown)
        _index = State(initialValue: min(max(0, page), max(0, pages.count - 1)))
    }

    private var page: BookPage? { pages.indices.contains(index) ? pages[index] : nil }
    private var wordCount: Int { studySet.bookMarkdown.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(wordCount.formatted()) words · \(pages.count) page\(pages.count == 1 ? "" : "s")")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if pages.count > 1 {
                    Button { showToc = true } label: { Label("Contents", systemImage: "list.bullet").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let page {
                        ForEach(Array(BookPages.blocks(page.markdown).enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    } else {
                        Text("This textbook is empty.").foregroundStyle(.secondary)
                    }
                }
                .contentCard()
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .readableColumn()
            }
            .id(index)
            if pages.count > 1 { footer }
        }
        .onAppear {
            if index == 0 { index = store.reading(for: studySet.id, count: pages.count) }
        }
        .onChange(of: index) { _, now in store.saveReading(at: now, for: studySet.id) }
        .modeScreen(.book)
        .navigationTitle(studySet.subject.isEmpty ? "Textbook" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showToc) {
            NavigationStack {
                List(pages) { p in
                    Button {
                        index = p.id; showToc = false
                    } label: {
                        HStack {
                            Text("\(p.id + 1).").font(.subheadline.monospaced()).foregroundStyle(.secondary)
                            Text(p.title).foregroundStyle(.primary)
                            Spacer()
                            if p.id == index { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func blockView(_ block: BookPages.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(md(text))
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 6)
        case .bullet(let text, let marker):
            HStack(alignment: .top, spacing: 8) {
                Text(marker ?? "\u{2022}")
                    .font(marker == nil ? .body : .body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(md(text))
            }
        case .row(let cells):
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                    Text(md(cell))
                        .font(i == 0 ? .subheadline.weight(.semibold) : .subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .paragraph(let text):
            Text(md(text)).font(.body).lineSpacing(3)
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button("Previous") { index = max(0, index - 1) }.buttonStyle(.glass).disabled(index == 0)
                Spacer()
                Text("Page \(index + 1) of \(pages.count)").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Next") { index = min(pages.count - 1, index + 1) }.buttonStyle(.glassProminent).disabled(index >= pages.count - 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
