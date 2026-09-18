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
/// Two kinds of PDF turn up and they need opposite treatment. A deck exported
/// from PowerPoint carries real text, which should be read exactly as written.
/// A scanned handout is a photograph of a page, where PDFKit returns nothing,
/// and the only way in is OCR - which Red Pen already does on device, in both
/// scripts, in RedPenOCR. The choice is made per PAGE rather than per document,
/// because a deck with three scanned pages in the middle is the normal case.
///
/// The text decisions all live in SourceText, which knows nothing about PDFKit
/// and can therefore be tested; the figure decisions live in FigureGrid for the
/// same reason.
enum SourceIngest {

    struct Result {
        var document: SourceText.Document
        /// Pages carrying a diagram, in the order the cards refer to them.
        var figures: [UIImage]
        /// Occlusion cards made from those diagrams' own labels. `imageIndex`
        /// is a position in `figures`.
        var occlusionCards: [AnkiCard]
    }

    /// Read a PDF: its own text where it has any, OCR where it does not, and a
    /// look for a labelled diagram either way.
    ///
    /// A figure is looked for on EVERY page, not only on the pages with no text
    /// of their own. The anatomy slide that matters most - a title, two bullets
    /// and a labelled diagram - carries plenty of text, and the earlier version
    /// of this skipped exactly those pages.
    static func read(pdf url: URL, findingFigures: Bool = true,
                     figureLimit: Int = 60) async throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: url) else { throw Trouble.unreadable }
        guard pdf.pageCount > 0 else { throw Trouble.empty }

        var raw: [(number: Int, text: String, recognised: Bool)] = []
        var figures: [UIImage] = []
        var cards: [AnkiCard] = []

        for index in 0..<pdf.pageCount {
            // each page's render is several megabytes; without this, a forty
            // page deck holds all forty at once and the app is killed
            autoreleasepool {
                guard let page = pdf.page(at: index) else { return }
                let embedded = page.string ?? ""
                let thin = embedded.trimmingCharacters(in: .whitespacesAndNewlines)
                    .count < SourceText.textFloor
                let rendered = (thin || findingFigures) ? image(of: page) : nil

                if thin {
                    var recognised = ""
                    if let cg = rendered?.cgImage {
                        recognised = (try? RedPenOCR.readText(cg)) ?? ""
                    }
                    raw.append((index + 1, recognised, true))
                } else {
                    raw.append((index + 1, embedded, false))
                }

                guard findingFigures, figures.count < figureLimit,
                      let cg = rendered?.cgImage,
                      let found = FigureFinder.read(cg, imageIndex: figures.count)
                else { return }
                figures.append(rendered!)
                cards.append(contentsOf: found.cards)
            }
        }

        let document = SourceText.document(from: raw)
        guard !document.isEmpty || !cards.isEmpty else { throw Trouble.noText }
        return Result(document: document, figures: figures, occlusionCards: cards)
    }

    /// A page as an image, at a size Vision can read without the memory cost of
    /// rendering a poster. A forty-page deck rendered at full resolution is
    /// enough to have the app killed for memory on an older phone.
    static func image(of page: PDFPage, maxDimension: CGFloat = 2000) -> UIImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(maxDimension / max(box.width, box.height), 4)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // white behind the page: a PDF page is transparent, and OCR on a
            // transparent-over-black render reads almost nothing
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    /// An image small enough to keep inside a set without bloating the library
    /// file. Sets are stored as JSON with images base64'd inside them, so a
    /// full-resolution photo of a slide costs several megabytes of text.
    static func downsized(_ image: UIImage, maxDimension: CGFloat = 1400,
                          quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        if scale >= 1 { return image.jpegData(compressionQuality: quality) }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let smaller = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return smaller.jpegData(compressionQuality: quality)
    }

    enum Trouble: LocalizedError {
        case unreadable, empty, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file could not be opened as a PDF."
            case .empty: return "That PDF has no pages."
            case .noText: return "No text could be read from that PDF, even by OCR."
            }
        }
    }
}
