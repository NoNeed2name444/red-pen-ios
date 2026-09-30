import SwiftUI

/// A note read as Markdown: headings, bullet and numbered lists, quotes,
/// code blocks, rules, bold, italic, `code` and links - and `[[Title]]`
/// links to other notes, which open that note when tapped.
struct NoteMarkdownView: View {
    let text: String
    /// Tapping a `[[Title]]`.
    let openNote: (String) -> Void

    var body: some View {
        let blocks: [NoteMarkdown.Block] = NoteMarkdown.blocks(in: text)
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("Nothing written yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == NoteMarkdown.scheme else { return .systemAction }
            openNote(NoteMarkdown.title(from: url))
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: NoteMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let line):
            Text(NoteMarkdown.inline(line))
                .font(Self.headingFont(level))
                .padding(.top, level == 1 ? 6 : 2)
        case .bullet(let depth, let marker, let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(.secondary)
                Text(NoteMarkdown.inline(line))
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let line):
            Text(NoteMarkdown.inline(line))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tint).frame(width: 3)
                }
        case .code(let body):
            Text(body)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        case .paragraph(let line):
            Text(NoteMarkdown.inline(line))
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}

/// Markdown into blocks, and a line's inline styling - kept apart from the
/// view so it is easy to follow.
enum NoteMarkdown {
    static let scheme = "vignette-note"

    enum Block {
        case heading(Int, String)
        case bullet(Int, String, String)
        case quote(String)
        case code(String)
        case rule
        case paragraph(String)
    }

    static func blocks(in text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let trimmed: String = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    out.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if trimmed.isEmpty { flush(); continue }
            if let block = lineBlock(raw, trimmed: trimmed) {
                flush()
                out.append(block)
            } else {
                paragraph.append(trimmed)
            }
        }
        if let open = code { out.append(.code(open.joined(separator: "\n"))) }
        flush()
        return out
    }

    /// A heading, list item, quote or rule; nil for plain text.
    private static func lineBlock(_ raw: String, trimmed: String) -> Block? {
        if trimmed == "---" || trimmed == "***" || trimmed == "___" { return .rule }
        let hashes: Int = trimmed.prefix { $0 == "#" }.count
        if hashes > 0 && hashes <= 6 && trimmed.dropFirst(hashes).hasPrefix(" ") {
            let rest: String = String(trimmed.dropFirst(hashes + 1))
            return .heading(hashes, rest)
        }
        if trimmed.hasPrefix("> ") { return .quote(String(trimmed.dropFirst(2))) }
        let indent: Int = raw.prefix { $0 == " " || $0 == "\t" }.count
        let depth: Int = min(indent / 2, 4)
        for mark in ["- ", "* ", "+ ", "\u{2022} "] where trimmed.hasPrefix(mark) {
            return .bullet(depth, "\u{2022}", String(trimmed.dropFirst(mark.count)))
        }
        let digits: String = String(trimmed.prefix { $0.isNumber })
        if !digits.isEmpty && digits.count <= 3 {
            let after: Substring = trimmed.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") {
                return .bullet(depth, digits + ".", String(after.dropFirst(2)))
            }
        }
        return nil
    }

    /// Bold, italic, `code` and links; `[[Title]]` becomes a link to that note.
    static func inline(_ line: String) -> AttributedString {
        let linked: String = wikiLinksAsMarkdown(line)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let styled = try? AttributedString(markdown: linked, options: options) {
            return styled
        }
        return AttributedString(line)
    }

    private static func wikiLinksAsMarkdown(_ line: String) -> String {
        var out: String = ""
        var rest: Substring = Substring(line)
        while let open = rest.range(of: "[["), let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) {
            out += rest[rest.startIndex..<open.lowerBound]
            let title: String = String(rest[open.upperBound..<close.lowerBound])
            let allowed: CharacterSet = .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))
            let encoded: String = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
            out += "[\(title)](\(scheme):///\(encoded))"
            rest = rest[close.upperBound...]
        }
        out += rest
        return out
    }

    static func title(from url: URL) -> String {
        let path: String = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return path.removingPercentEncoding ?? path
    }
}
