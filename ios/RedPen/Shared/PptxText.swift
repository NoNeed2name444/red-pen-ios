import Foundation

/// A PowerPoint deck's words and pictures.
///
/// The format lecturers actually hand out. A .pptx is a zip like a .docx, so
/// the reader built for Word opens it already; what differs is where the text
/// lives. Word keeps one document.xml; PowerPoint keeps one file per slide
/// under ppt/slides/, and the numbering in those filenames is the deck's order.
///
/// Pure Foundation, so every decision here is tested.
enum PptxText {

    static let slidePrefix = "ppt/slides/slide"
    static let mediaPrefix = "ppt/media/"

    /// Slide XML paths in the order they are shown, which is numeric order -
    /// slide10 comes after slide9, not after slide1.
    static func slidePaths(in names: [String]) -> [String] {
        names.filter { $0.hasPrefix(slidePrefix) && $0.hasSuffix(".xml") }
            .sorted { number(in: $0) < number(in: $1) }
    }

    static func number(in path: String) -> Int {
        let digits = path.dropFirst(slidePrefix.count).prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// One slide's text, one line per text run.
    ///
    /// PowerPoint wraps every run in <a:t>, and a line break inside a text box
    /// is a new run - so runs are joined with newlines rather than spaces, and
    /// a bulleted slide arrives as a list rather than one long sentence.
    ///
    /// The tag has to be matched exactly. Looking for "<a:t" alone also matches
    /// <a:tbl>, the tag that opens a TABLE - and since a table has no </a:t> of
    /// its own, everything from the table to the end of the next real run gets
    /// swallowed as one blob of markup. Tables are common on a lecture slide.
    static func text(fromSlideXML xml: String) -> String {
        var out: [String] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<a:t") {
            var contentStart: Substring.Index?
            if open.upperBound < rest.endIndex {
                let next = rest[open.upperBound]
                if next == ">" {
                    contentStart = rest.index(after: open.upperBound)
                } else if next == " " || next == "\n" || next == "\r" || next == "\t" {
                    // <a:t dirty="0"> - attributes are allowed on the run
                    if let gt = rest[open.upperBound...].firstIndex(of: ">") {
                        contentStart = rest.index(after: gt)
                    }
                }
            }
            guard let start = contentStart,
                  let close = rest.range(of: "</a:t>", range: start..<rest.endIndex) else {
                // <a:tbl>, <a:tc>, or a run with no closing tag: step over the
                // tag name and carry on rather than swallowing the rest
                rest = rest[open.upperBound...]
                continue
            }
            let text = DocxText.decodeEntities(String(rest[start..<close.lowerBound]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(text) }
            rest = rest[close.upperBound...]
        }
        return out.joined(separator: "\n")
    }

    /// The deck as pages, one per slide, numbered the way the student sees them.
    static func pages(_ archive: [String: Data]) -> [(number: Int, text: String, recognised: Bool)] {
        slidePaths(in: Array(archive.keys)).enumerated().map { index, path in
            let xml = archive[path].map { String(decoding: $0, as: UTF8.self) } ?? ""
            return (index + 1, text(fromSlideXML: xml), false)
        }
    }

    /// The pictures, in filename order. A deck's diagrams are here, and they are
    /// what the occlusion cards are made from.
    ///
    /// Note what this does NOT give: which slide each picture sits on. That is
    /// recorded in the relationship files, not the media folder, so a picture's
    /// position in this list is not its slide number and must never be quoted
    /// as one.
    static func images(_ archive: [String: Data]) -> [Data] {
        archive.keys
            .filter { $0.hasPrefix(mediaPrefix) && DocxText.isPicture($0) }
            .sorted { DocxText.natural($0) < DocxText.natural($1) }
            .compactMap { archive[$0] }
    }
}
