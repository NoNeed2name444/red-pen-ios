import Foundation

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
        /// A bullet carries its marker when the source numbered it. A
        /// numbered list in a textbook is usually a sequence - the steps of a
        /// protocol, the stages of a disease - and redrawing it as anonymous
        /// bullets throws that away.
        case heading(Int, String), bullet(String, marker: String?), row([String]), paragraph(String)
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
            } else if let m = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                flushPara()
                let marker = line[..<m.upperBound].trimmingCharacters(in: .whitespaces)
                let numbered = marker.first?.isNumber == true
                out.append(.bullet(String(line[m.upperBound...]),
                                   marker: numbered ? marker : nil))
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
