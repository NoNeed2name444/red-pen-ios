import Foundation

/// What to do with the words once they are out of the file.
///
/// Deliberately free of PDFKit, Vision and UIKit. Everything here is a decision
/// that ends up on a card - whether a hyphenated break is one word, whether a
/// line is the lecturer's footer or the point of the slide - and decisions that
/// can only be exercised on a phone are decisions nobody exercises.
enum SourceText {

    struct Page: Equatable {
        var number: Int
        var text: String
        /// True when the words came from OCR rather than from the file. Worth
        /// keeping: OCR text is good enough to study from and not good enough
        /// to trust silently.
        var recognised: Bool
    }

    struct Document: Equatable {
        var pages: [Page]
        var text: String { pages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n") }
        var recognisedPages: Int { pages.filter(\.recognised).count }
        var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Below this many characters a page is treated as a picture of a page.
    /// A slide with a title and two bullets clears it easily; a scan usually
    /// returns nothing at all, and occasionally a few characters of junk from
    /// an embedded watermark, which is why the floor is not zero.
    static let textFloor = 24

    /// Words broken across a line ending in a hyphen are one word.
    ///
    /// A slide that wraps "hydroxy-\nchloroquine" would otherwise teach the
    /// generator two words that do not exist, and both would end up on a card.
    static func joinHyphenated(_ text: String) -> String {
        var out: [String] = []
        var carry: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let held = carry {
                out.append(held + trimmed)
                carry = nil
                continue
            }
            if trimmed.count > 1, trimmed.hasSuffix("-"),
               let last = trimmed.dropLast().last, last.isLetter {
                carry = String(trimmed.dropLast())
            } else {
                out.append(trimmed)
            }
        }
        if let held = carry { out.append(held) }
        return out.joined(separator: "\n")
    }

    /// Lines that appear on nearly every page are furniture, not content.
    ///
    /// A lecturer's name, a course code and a page number on all forty pages is
    /// forty repetitions of the same three facts. Left in, they are the most
    /// repeated text in the document, and a generator asked what the lecture
    /// emphasised will answer with the footer.
    static func runningLines(_ pages: [String], threshold: Double = 0.6) -> Set<String> {
        guard pages.count >= 4 else { return [] }
        var seen: [String: Int] = [:]
        for page in pages {
            // once per page: a line repeated twice on one page is still one page
            for line in Set(page.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }) where line.count >= 3 && line.count <= 80 {
                seen[line, default: 0] += 1
            }
        }
        let needed = Int((Double(pages.count) * threshold).rounded())
        return Set(seen.filter { $0.value >= max(3, needed) }.keys)
    }

    /// A page number stands out even when the rest of the footer varies.
    static func isPageFurniture(_ line: String) -> Bool {
        let bare = line.trimmingCharacters(in: .whitespaces)
        if bare.isEmpty { return true }
        if Int(bare) != nil { return true }
        let lower = bare.lowercased()
        if lower.hasPrefix("page "),
           Int(lower.dropFirst(5).trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    /// One page's text, tidied.
    static func clean(_ text: String, dropping furniture: Set<String> = []) -> String {
        let joined = joinHyphenated(text)
        let kept = joined.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !isPageFurniture($0) && !furniture.contains($0) }
        // collapse the runs of blank lines a PDF's layout leaves behind
        var out: [String] = []
        for line in kept where !(line.isEmpty && out.last?.isEmpty != false) {
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Assemble the finished document from raw per-page text.
    static func document(from raw: [(number: Int, text: String, recognised: Bool)]) -> Document {
        let furniture = runningLines(raw.map(\.text))
        return Document(pages: raw.map {
            Page(number: $0.number, text: clean($0.text, dropping: furniture),
                 recognised: $0.recognised)
        })
    }
}
