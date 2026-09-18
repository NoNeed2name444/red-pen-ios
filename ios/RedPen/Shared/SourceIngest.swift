import Foundation
import PDFKit
import UIKit

/// Getting a lecture out of the file it arrived in.
///
/// This is the half of the web app the native rewrite never had: sets could be
/// typed, pasted or imported as JSON, but not made from the PDF the lecturer
/// actually handed out. Everything downstream - generation, cards, occlusion -
/// is worthless if the material cannot get in.
///
/// Two kinds of PDF turn up, and they need opposite treatment. A slide deck
/// exported from PowerPoint carries real text, which should be read exactly as
/// written. A scanned handout is a photograph of a page, where PDFKit returns
/// nothing or a handful of stray characters, and the only way in is OCR. The
/// decision between them is made per page rather than per document, because a
/// deck with three scanned pages in the middle is the normal case, not the
/// exception.
enum SourceIngest {

    struct Page: Equatable {
        var number: Int
        var text: String
        /// True when the words came from OCR rather than from the file. Worth
        /// keeping: OCR text is good enough to study from and not good enough
        /// to trust silently, and the generator can weigh it accordingly.
        var recognised: Bool
    }

    struct Document {
        var pages: [Page]
        var figures: [UIImage]
        var text: String { pages.map(\.text).joined(separator: "\n\n") }
        var recognisedPages: Int { pages.filter(\.recognised).count }
    }

    /// Below this many characters a page is treated as a picture of a page.
    /// A slide with a title and two bullets clears it easily; a scan usually
    /// returns nothing at all, and occasionally a few characters of junk from
    /// an embedded watermark, which is why the floor is not zero.
    static let textFloor = 24

    // MARK: the parts worth testing - no PDFKit, no Vision, no device

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
        if lower.hasPrefix("page "), Int(lower.dropFirst(5).trimmingCharacters(in: .whitespaces)) != nil {
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

    // MARK: the device

    /// Read a PDF: its own text where it has any, OCR where it does not.
    static func read(pdf url: URL) async throws -> Document {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            throw Trouble.unreadable
        }

        var raw: [(number: Int, text: String, recognised: Bool)] = []
        var figures: [UIImage] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let embedded = page.string ?? ""
            if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count >= textFloor {
                raw.append((index + 1, embedded, false))
                continue
            }
            // a page with no text of its own is a picture: OCR it, and keep the
            // picture, because on a slide deck that picture IS the diagram
            let rendered = image(of: page)
            if let cg = rendered?.cgImage,
               let text = try? RedPenOCR.readText(cg) {
                raw.append((index + 1, text, true))
            } else {
                raw.append((index + 1, "", true))
            }
            if let rendered { figures.append(rendered) }
        }

        let furniture = runningLines(raw.map(\.text))
        let pages = raw.map { Page(number: $0.number,
                                   text: clean($0.text, dropping: furniture),
                                   recognised: $0.recognised) }
        return Document(pages: pages, figures: figures)
    }

    /// A page as an image, at a size Vision can read without the memory cost of
    /// rendering a poster.
    static func image(of page: PDFPage, maxDimension: CGFloat = 2000) -> UIImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(maxDimension / max(box.width, box.height), 4)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    enum Trouble: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "That file could not be opened as a PDF."
        }
    }
}
