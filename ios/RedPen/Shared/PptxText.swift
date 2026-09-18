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
    /// a bullet list arrives as a list rather than as one long sentence.
    static func text(fromSlideXML xml: String) -> String {
        var out: [String] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<a:t"),
              let gt = rest[open.upperBound...].firstIndex(of: ">"),
              let close = rest.range(of: "</a:t>", range: gt..<rest.endIndex) {
            let run = rest[rest.index(after: gt)..<close.lowerBound]
            let text = DocxText.decodeEntities(String(run))
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
    static func images(_ archive: [String: Data]) -> [Data] {
        archive.keys
            .filter { $0.hasPrefix(mediaPrefix) && DocxText.isPicture($0) }
            .sorted { DocxText.natural($0) < DocxText.natural($1) }
            .compactMap { archive[$0] }
    }
}
