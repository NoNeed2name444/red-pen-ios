import Foundation

/// A textbook page — the web app's Markdown, split into pages at headings
/// (`splitBookIntoPages()`), drawn as native text.
struct BookPage: Identifiable, Hashable {
    let id: Int
    let title: String
    let markdown: String
}

enum BookPages {
    /// How many pages `split` would make, remembered: the library shows a
    /// textbook's page count on its row, and splitting the whole book on
    /// every redraw of the list is the slowest thing on that screen.
    static func pageCount(_ markdown: String) -> Int {
        pageCounts.count(for: markdown)
    }

    private static let pageCounts = PageCountCache()

    /// A small, thread-safe memo of page counts by book text.
    private final class PageCountCache: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func count(for markdown: String) -> Int {
            lock.lock()
            let known = counts[markdown]
            lock.unlock()
            if let known { return known }
            let fresh = BookPages.split(markdown).count
            lock.lock()
            // a handful of books at most; forgetting them all is simpler than
            // keeping an order and costs one re-split each
            if counts.count >= 64 { counts.removeAll() }
            counts[markdown] = fresh
            lock.unlock()
            return fresh
        }
    }

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
    /// rows), callouts, flowcharts and pictures; everything else a paragraph. Inline `**bold**` / `_italic_`
    /// / `` `code` `` come from SwiftUI's own Markdown support.
    enum Block: Hashable {
        case heading(Int, String), bullet(String, marker: String?), paragraph(String)
        /// A table row; `header` for the row above the |---| line.
        case row([String], header: Bool = false)
        /// A boxed aside: "Key point", "Exam tip", "Red flag", "Mnemonic"...
        case callout(kind: String, text: String)
        /// A pathway drawn as boxes and arrows, one step per line.
        case flow([String])
        /// A picture of the set (an index into StudySet.images) and its caption.
        case image(Int, caption: String)
    }

    static func blocks(_ markdown: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var flow: [String]? = nil
        func flushPara() {
            let t = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(.paragraph(t)) }
            para = []
        }
        let lines = markdown.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        func isSeparator(_ line: String) -> Bool {
            line.hasPrefix("|") && line.replacingOccurrences(of: " ", with: "")
                .split(separator: "|").allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } }
        }
        for (i, line) in lines.enumerated() {
            // a flowchart: ```flow ... ```
            if flow != nil {
                if line.hasPrefix("```") {
                    out.append(.flow(flow!.filter { !$0.isEmpty }))
                    flow = nil
                } else {
                    flow!.append(line.replacingOccurrences(of: #"^([-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression))
                }
                continue
            }
            if line.hasPrefix("```") {
                flushPara()
                if line.lowercased().contains("flow") || line.lowercased().contains("mermaid") { flow = [] }
                continue
            }
            if line.isEmpty { flushPara(); continue }
            if let picture = BookFigures.parse(line) {
                flushPara()
                out.append(.image(picture.index, caption: picture.caption))
            } else if line.hasPrefix(">") {
                flushPara()
                var text = line.drop(while: { $0 == ">" || $0 == " " }).description
                var kind = "Note"
                if let m = text.range(of: #"^\*\*([^*]{2,24}?):?\*\*:?\s*"#, options: .regularExpression) {
                    kind = text[m].replacingOccurrences(of: "*", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                    text = String(text[m.upperBound...])
                }
                out.append(.callout(kind: kind, text: text))
            } else if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushPara()
                let level = line.distance(from: line.startIndex, to: m.upperBound) - 1
                out.append(.heading(min(level, 3), String(line[m.upperBound...])))
            } else if let m = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                flushPara()
                let marker = line[..<m.upperBound].trimmingCharacters(in: .whitespaces)
                let numbered = marker.first?.isNumber == true
                out.append(.bullet(String(line[m.upperBound...]),
                                   marker: numbered ? marker : nil))
            } else if line.hasPrefix("|") {
                flushPara()
                if isSeparator(line) { continue }
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                let header = i + 1 < lines.count && isSeparator(lines[i + 1])
                out.append(.row(Array(cells), header: header))
            } else {
                para.append(line)
            }
        }
        if let flow { out.append(.flow(flow.filter { !$0.isEmpty })) }
        flushPara()
        return out
    }

    /// One written page made fit for the reader: exactly one page heading
    /// ("## "), every other heading a section inside it ("### ") - a second
    /// "##" would split one topic across two pages - and only the pictures
    /// this page was given, with any it did not place added at the end.
    static func tidyPage(_ written: String, fallbackTitle: String, figures: [Int]) -> String {
        var lines = written.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var titled = false
        var placed: Set<Int> = []
        lines = lines.compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let text = String(line[m.upperBound...])
                let level = line.distance(from: line.startIndex, to: m.upperBound) - 1
                if !titled && level <= 2 { titled = true; return "## " + text }
                return (level <= 3 ? "### " : "#### ") + text
            }
            if let picture = BookFigures.parse(line) {
                // a picture the page was not given is a number the model made up
                guard figures.contains(picture.index), !placed.contains(picture.index) else { return nil }
                placed.insert(picture.index)
            }
            return raw
        }
        if !titled { lines.insert("## " + fallbackTitle, at: 0); lines.insert("", at: 1) }
        let unplaced = figures.filter { !placed.contains($0) }
        if !unplaced.isEmpty {
            lines += ["", "### Figures from the lecture"]
            lines += unplaced.map { "![Figure from the lecture](\(BookFigures.reference($0)))" }
        }
        return lines.joined(separator: "\n")
    }
}
