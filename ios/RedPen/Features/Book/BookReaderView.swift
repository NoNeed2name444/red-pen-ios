import SwiftUI

/// A textbook page — the web app's Markdown, split into pages at headings
/// (`splitBookIntoPages()`), drawn as native text.
struct BookPage: Identifiable, Hashable {
    let id: Int
    let title: String
    let markdown: String
}

enum BookPages {
    /// Every `#` or `##` heading starts a page; text before the first
    /// heading is a page of its own called "Introduction".
    static func split(_ markdown: String) -> [BookPage] {
        var pages: [BookPage] = []
        var title = "Introduction", body: [String] = []
        func flush() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pages.append(BookPage(id: pages.count, title: title, markdown: text)) }
            body = []
        }
        for line in markdown.components(separatedBy: "\n") {
            if let m = line.range(of: #"^#{1,2}\s+"#, options: .regularExpression) {
                flush()
                title = String(line[m.upperBound...]).trimmingCharacters(in: .whitespaces)
                body = [line]
            } else {
                body.append(line)
            }
        }
        flush()
        return pages
    }

    /// A tiny block-level Markdown reader: headings, bullets, tables (as
    /// rows), everything else a paragraph. Inline `**bold**` / `_italic_`
    /// / `` `code` `` come from SwiftUI's own Markdown support.
    enum Block: Hashable {
        case heading(Int, String), bullet(String), row([String]), paragraph(String)
    }
    static func blocks(_ markdown: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flushPara() {
            let t = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(.paragraph(t)) }
            para = []
        }
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushPara(); continue }
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushPara()
                let level = line.distance(from: line.startIndex, to: m.upperBound) - 1
                out.append(.heading(min(level, 3), String(line[m.upperBound...])))
            } else if let m = line.range(of: #"^([-*•]|\d+\.)\s+"#, options: .regularExpression) {
                flushPara(); out.append(.bullet(String(line[m.upperBound...])))
            } else if line.hasPrefix("|") {
                flushPara()
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { out.append(.row(Array(cells))) }
            } else {
                para.append(line)
            }
        }
        flushPara()
        return out
    }
}

/// The reader — matches `#bookView`: title + word count, the page, a
/// Previous / Next bar with "Page X of Y — title", and a table of contents.
struct BookReaderView: View {
    let studySet: StudySet
    private let pages: [BookPage]
    @State private var index = 0
    @State private var showToc = false

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
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            Divider()
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .id(index)
            if pages.count > 1 { footer }
        }
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
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        case .paragraph(let text):
            Text(md(text)).font(.body).lineSpacing(3)
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private var footer: some View {
        HStack {
            Button("Previous") { index = max(0, index - 1) }.disabled(index == 0)
            Spacer()
            Text("Page \(index + 1) of \(pages.count)").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Next") { index = min(pages.count - 1, index + 1) }.disabled(index >= pages.count - 1)
        }
        .padding()
        .background(.bar)
    }
}
