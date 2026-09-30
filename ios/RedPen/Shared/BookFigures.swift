import Foundation

/// A diagram found in the lecture, ready to sit on the textbook page about
/// the same topic.
///
/// Foundation only (the image is already JPEG, base64), so which figure goes
/// on which page can be tested without a lecture or a model.
struct BookFigure: Equatable {
    /// JPEG, base64: the form StudySet.images keeps pictures in.
    var imageBase64: String
    /// The page or slide it was on, when the file says (PDFs do; a PowerPoint's
    /// media folder does not).
    var page: Int?
    /// The words labelled on it, and the text of its page - what it is about.
    var labels: [String]
    var pageText: String = ""

    var about: String { (labels + [pageText]).joined(separator: " ") }
}

enum BookFigures {
    /// Most figures one page carries: a page of pictures is an atlas, not a
    /// textbook.
    static let perPage = 3

    /// Which figures belong to which slice of the lecture: each figure goes to
    /// the slice it shares the most words with, and only if it shares enough
    /// to be about the same thing.
    static func assign(_ figures: [BookFigure], to slices: [String], minimumOverlap: Int = 2) -> [[Int]] {
        var out = Array(repeating: [Int](), count: slices.count)
        guard !slices.isEmpty else { return out }
        let sliceWords = slices.map(words)
        var ranked: [(figure: Int, slice: Int, score: Int)] = []
        for (f, figure) in figures.enumerated() {
            let about = words(figure.about)
            guard !about.isEmpty else { continue }
            let scores = sliceWords.map { $0.intersection(about).count }
            if let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] >= minimumOverlap {
                ranked.append((f, best, scores[best]))
            }
        }
        // the closest matches first, so a crowded page keeps its best figures
        for pick in ranked.sorted(by: { $0.score > $1.score }) where out[pick.slice].count < perPage {
            out[pick.slice].append(pick.figure)
        }
        return out.map { $0.sorted() }
    }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
    }

    /// Keeps only the pictures a textbook actually shows, renumbering the
    /// references to match, so a set does not carry every diagram the lecture
    /// had.
    static func compact(_ markdown: String, images: [String]) -> (markdown: String, images: [String]) {
        var kept: [String] = []
        var remap: [Int: Int] = [:]
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            guard let (index, caption) = parse(line.trimmingCharacters(in: .whitespaces)),
                  images.indices.contains(index) else { return line }
            if remap[index] == nil { remap[index] = kept.count; kept.append(images[index]) }
            return "![\(caption)](\(reference(remap[index]!)))"
        }
        return (lines.joined(separator: "\n"), kept)
    }

    /// The reference a page uses for picture `index` of the set.
    static func reference(_ index: Int) -> String { "image:\(index)" }

    /// `![caption](image:3)` - the picture's index into StudySet.images and
    /// its caption, or nil for any other line.
    static func parse(_ line: String) -> (index: Int, caption: String)? {
        guard let m = line.range(of: #"^!\[([^\]]*)\]\(image:(\d+)\)\s*$"#, options: .regularExpression) else { return nil }
        let text = String(line[m])
        guard let open = text.firstIndex(of: "["), let close = text.firstIndex(of: "]"),
              let colon = text.lastIndex(of: ":"), let end = text.lastIndex(of: ")"),
              let index = Int(text[text.index(after: colon)..<end]) else { return nil }
        return (index, String(text[text.index(after: open)..<close]))
    }
}
