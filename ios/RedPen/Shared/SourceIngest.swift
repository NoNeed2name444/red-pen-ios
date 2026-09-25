import Foundation
import PDFKit
import UIKit

/// Getting a lecture out of the file it arrived in.
///
/// Two kinds of PDF turn up and they need opposite treatment. A deck exported
/// from PowerPoint carries real text, which should be read exactly as written.
/// A scanned handout is a photograph of a page, where PDFKit returns nothing,
/// and the only way in is OCR - which Red Pen already does on device, in both
/// scripts, in RedPenOCR. The choice is made per PAGE rather than per document,
/// because a deck with three scanned pages in the middle is the normal case.
///
/// The text decisions live in SourceText and the figure decisions in FigureGrid,
/// both free of UIKit so they can be tested. Word and PowerPoint come in
/// through OfficeIngest and end up in this same Result.
enum SourceIngest {

    struct Result {
        var document: SourceText.Document
        /// Pages carrying a diagram, in the order the cards refer to them.
        var figures: [UIImage]
        /// Occlusion cards made from those diagrams' own labels. `imageIndex`
        /// is a position in `figures`.
        var occlusionCards: [AnkiCard]
        /// For each of `figures`: its page (when known) and the words labelled
        /// on it, so a textbook page can carry the diagrams about its topic.
        var figureNotes: [(page: Int?, labels: [String])] = []
    }

    /// Read a PDF: its own text where it has any, OCR where it does not, and a
    /// look for a labelled diagram either way.
    ///
    /// A figure is looked for on EVERY page, not only on pages with no text of
    /// their own. The anatomy slide that matters most - a title, two bullets and
    /// a labelled diagram - carries plenty of text, and an earlier version of
    /// this skipped exactly those pages.
    static func read(pdf url: URL, findingFigures: Bool = true, readingText: Bool = true,
                     figureLimit: Int = 60, workers requested: Int? = nil,
                     onPage: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let pdf = PDFDocument(url: url) else { throw Trouble.unreadable }
        let count = pdf.pageCount
        guard count > 0 else { throw Trouble.empty }
        let name = url.deletingPathExtension().lastPathComponent

        // Several pages at once, one PDF document per worker (PDFKit is not
        // safe to share across threads): each page is rendered, scanned and
        // read on its own, so a 45-slide deck takes the time of a dozen.
        let workers = requested.map { max(1, $0) } ?? max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
        let done = PageCounter()
        // Figures found so far, across the workers. The limit is applied as
        // the pages are read, not after: a scanned textbook of eight hundred
        // pages would otherwise hold every figure it found before keeping
        // sixty, and take as long as scanning every page to do it.
        let found = PageCounter()
        let pages: [PageRead] = await withTaskGroup(of: [PageRead].self) { group in
            for worker in 0..<workers {
                group.addTask {
                    guard let document = PDFDocument(url: url) else { return [] }
                    var out: [PageRead] = []
                    for index in stride(from: worker, to: count, by: workers) {
                        if Task.isCancelled { break }
                        let looking = findingFigures && found.value < figureLimit
                        // a diagram scan with its figures found has nothing
                        // left to do on the pages still to come
                        if !readingText && !looking { break }
                        autoreleasepool {
                            if let page = document.page(at: index) {
                                let read = readPage(page, number: index + 1, name: name,
                                                    findingFigures: looking, readingText: readingText)
                                if read.figure != nil { _ = found.next() }
                                out.append(read)
                            }
                        }
                        onPage?(done.next(), count)
                    }
                    return out
                }
            }
            var all: [PageRead] = []
            for await part in group { all += part }
            return all.sorted { $0.number < $1.number }
        }
        try Task.checkCancellation()

        // figures numbered in page order, and their cards with them
        var figures: [UIImage] = []
        var notes: [(page: Int?, labels: [String])] = []
        var cards: [AnkiCard] = []
        for page in pages {
            guard let figure = page.figure, figures.count < figureLimit else { continue }
            cards += page.cards.map { var card = $0; card.imageIndex = figures.count; return card }
            notes.append((page.number, page.labels))
            figures.append(figure)
        }
        let document = SourceText.document(from: pages.map { ($0.number, $0.text, $0.recognised) })
        guard !document.isEmpty || !cards.isEmpty || !readingText else { throw Trouble.noText }
        return Result(document: document, figures: figures, occlusionCards: cards, figureNotes: notes)
    }

    /// One page: its own text, OCR when it has none, and a look for a labelled
    /// diagram.
    private static func readPage(_ page: PDFPage, number: Int, name: String,
                                 findingFigures: Bool, readingText: Bool) -> PageRead {
        let embedded = page.string ?? ""
        let thin = embedded.trimmingCharacters(in: .whitespacesAndNewlines).count < SourceText.textFloor
        var read = PageRead(number: number, text: embedded, recognised: false)
        var rendered: UIImage?
        if thin && readingText {
            rendered = image(of: page)
            read.text = rendered?.cgImage.flatMap { try? RedPenOCR.readText($0) } ?? ""
            read.recognised = true
        }
        // A labelled diagram sits on a slide of few words; a page that is a
        // wall of text has none worth the scan, which is most of the cost.
        guard findingFigures, embedded.count < 900 else { return read }
        // 1,600 pixels is plenty for labels and a good deal cheaper to scan
        let picture = rendered ?? image(of: page, maxDimension: 1600)
        guard let cg = picture?.cgImage,
              let found = FigureFinder.read(cg, imageIndex: 0),
              // kept as a small JPEG, not the full render: dozens of full
              // renders held at once are hundreds of megabytes
              let small = picture.flatMap({ downsized($0) }).flatMap(UIImage.init(data:))
        else { return read }
        read.figure = small
        read.labels = found.cards.flatMap(\.bullets)
        // the page number is the whole value of provenance: a card that looks
        // wrong can be checked against the slide it came off
        read.cards = found.cards.map { var card = $0; card.source = "\(name), p. \(number)"; return card }
        return read
    }

    private struct PageRead {
        var number: Int
        var text: String
        var recognised: Bool
        var figure: UIImage?
        var labels: [String] = []
        var cards: [AnkiCard] = []
    }

    /// A count shared by the workers: pages finished, or figures found.
    private final class PageCounter: @unchecked Sendable {
        private var count = 0
        private let lock = NSLock()
        func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// A page as an image, at a size Vision can read without the memory cost of
    /// rendering a poster. A forty-page deck at full resolution is enough to
    /// have the app killed for memory on an older phone.
    ///
    /// `maxDimension` is in PIXELS. A renderer left to its default format
    /// draws at the screen's scale, which on a 3x phone made a 2,000-pixel
    /// render 6,000 pixels across - nine times the memory per page, with four
    /// pages rendering at once.
    ///
    /// The page is drawn the way it is shown: turned by its /Rotate, and
    /// cut to its crop box. A landscape scan saved as a portrait page turned
    /// 90 degrees is the ordinary output of a scanning app, and drawing it
    /// into an unturned canvas cut a strip off every page before OCR saw it.
    static func image(of page: PDFPage, maxDimension: CGFloat = 2000) -> UIImage? {
        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let turned = abs(page.rotation) % 180 == 90
        let shown = turned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(maxDimension / max(shown.width, shown.height), 4)
        let size = CGSize(width: (shown.width * scale).rounded(), height: (shown.height * scale).rounded())
        guard size.width >= 1, size.height >= 1 else { return nil }
        return pixelRenderer(size: size, opaque: true).image { ctx in
            // white behind the page: a PDF page is transparent, and OCR on a
            // transparent-over-black render reads almost nothing
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            // draws with the page's rotation and the box's origin applied
            page.draw(with: .cropBox, to: ctx.cgContext)
        }
    }

    /// A renderer whose points are pixels, so a size asked for is the size
    /// made, on every device.
    static func pixelRenderer(size: CGSize, opaque: Bool = false) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// An image small enough to keep inside a set without bloating the library
    /// file. Sets are stored as JSON with images base64'd inside them, so a
    /// full-resolution photo of a slide costs several megabytes of text.
    ///
    /// `maxDimension` is in pixels, measured on the image's pixels rather than
    /// its points: a render at 3x scale is three times the size its points
    /// say, and measuring points is how "1,400 pixels" came out 4,200.
    static func downsized(_ image: UIImage, maxDimension: CGFloat = 1400,
                          quality: CGFloat = 0.8) -> Data? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        if scale >= 1 && !hasAlpha(image) { return image.jpegData(compressionQuality: quality) }
        let size = CGSize(width: max(1, (pixels.width * scale).rounded()),
                          height: max(1, (pixels.height * scale).rounded()))
        let smaller = pixelRenderer(size: size, opaque: true).image { ctx in
            // on white: a JPEG has no transparency, and a diagram pasted as
            // a transparent PNG otherwise comes out black on black
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return smaller.jpegData(compressionQuality: quality)
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let info = image.cgImage?.alphaInfo else { return true }
        return !(info == .none || info == .noneSkipFirst || info == .noneSkipLast)
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
