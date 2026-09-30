import Foundation
import ImageIO
import UIKit

/// Word and PowerPoint files, brought in the same door as a PDF.
///
/// Both are zips, both give text plus a folder of pictures, and everything
/// downstream - cleaning, generation, occlusion - is shared. So both return a
/// SourceIngest.Result rather than a shape of their own.
///
/// They differ in what a "page" means. A PowerPoint slide is a page and is
/// numbered the way the student sees it. A Word document has no pages at all -
/// Word decides where the breaks fall when it lays the document out, and the
/// file does not record it - so a handout arrives as one page. That costs
/// nothing: page numbers were only ever used to find the running footer, and a
/// document with one page has no footer to find.
enum OfficeIngest {

    /// `figureLimit` bounds the diagrams looked for, as it does for a PDF: a
    /// deck with three hundred pasted pictures is three hundred OCR runs.
    static func read(_ url: URL, findingFigures: Bool = true, figureLimit: Int = 60) async throws
        -> SourceIngest.Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Mapped rather than read: a deck with a lecture video in it is
        // hundreds of megabytes, and only its slides and pictures are touched.
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { throw Trouble.unreadable }
        let listed = Zip.directory(of: data)
        let names = listed.map(\.name)
        let slides = PptxText.slidePaths(in: names)
        guard !slides.isEmpty || names.contains(DocxText.documentPath) else { throw Trouble.notAnOfficeFile }

        // the text only; the pictures are read one at a time further down,
        // and nothing else in the file is inflated at all
        let archive = Zip.entries(in: data) { PptxText.isNeeded($0, pictures: false) }
        let name = url.deletingPathExtension().lastPathComponent

        let raw: [(number: Int, text: String, recognised: Bool)]
        let mediaPrefix: String
        if !slides.isEmpty {
            // numbered against every slide listed, so one slide too large to
            // open does not shift the numbers of all the ones after it
            guard slides.contains(where: { archive[$0] != nil }) else { throw Trouble.damaged }
            raw = PptxText.pages(archive, slides: slides)
            mediaPrefix = PptxText.mediaPrefix
        } else {
            guard archive[DocxText.documentPath] != nil else { throw Trouble.damaged }
            raw = [(1, DocxText.read(archive).text, false)]
            mediaPrefix = DocxText.mediaPrefix
        }
        try Task.checkCancellation()

        let document = SourceText.document(from: raw)
        var figures: [UIImage] = []
        var notes: [(page: Int?, labels: [String])] = []
        var cards: [AnkiCard] = []
        if findingFigures {
            let pictures = listed
                .filter { $0.name.hasPrefix(mediaPrefix) && DocxText.isPicture($0.name) }
                .sorted { DocxText.natural($0.name) < DocxText.natural($1.name) }
            var budget = Zip.Limits.standard.totalBytes
            for entry in pictures {
                if Task.isCancelled || figures.count >= figureLimit || budget <= 0 { break }
                let read = Zip.contents(of: entry, in: data, budget: budget)
                budget -= read.cost
                guard let picture = read.body else { continue }
                autoreleasepool {
                    // decoded no larger than a rendered page, and kept as a
                    // small JPEG: dozens of full-size pictures held at once
                    // are what gets an import killed for memory
                    guard let cg = thumbnail(picture),
                          // a picture out of the file is the diagram itself,
                          // not a slide with a header and footer round it
                          let found = FigureFinder.read(cg, imageIndex: figures.count,
                                                        pageBands: false),
                          let small = SourceIngest.downsized(UIImage(cgImage: cg))
                              .flatMap(UIImage.init(data:))
                    else { return }
                    // The file names the deck and nothing finer. A picture in
                    // the media folder is not tied to the slide it appears on
                    // without following the relationship files, so its position
                    // in that folder is NOT its slide number - quoting one
                    // would produce a citation that looks precise and points at
                    // the wrong slide, which is worse than no citation at all.
                    cards.append(contentsOf: found.cards.map {
                        var card = $0
                        card.source = name
                        return card
                    })
                    figures.append(small)
                    notes.append((nil, found.cards.flatMap(\.bullets)))
                }
            }
            try Task.checkCancellation()
        }

        guard !document.isEmpty || !cards.isEmpty else { throw Trouble.noText }
        return SourceIngest.Result(document: document, figures: figures,
                                   occlusionCards: cards, figureNotes: notes)
    }

    /// A picture out of the file, decoded no larger than a rendered page.
    ///
    /// Pictures in a deck are whatever size was pasted in, and a 12,000-pixel
    /// scan decoded whole is over half a gigabyte before OCR has started. One
    /// whose header claims more than `maxPixels` altogether is not decoded at
    /// all - a tiny PNG can claim to be enormous.
    static func thumbnail(_ data: Data, longestSide: Int = 2000,
                          maxPixels: Double = 60_000_000) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= maxPixels
        else { return nil }
        let wanted: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, wanted as CFDictionary)
    }

    enum Trouble: LocalizedError {
        case unreadable, notAnOfficeFile, damaged, noText
        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file could not be opened."
            case .notAnOfficeFile:
                return "That does not look like a Word or PowerPoint file. An old .doc or .ppt needs saving as .docx or .pptx first."
            case .damaged:
                return "That file is damaged, or too large inside to open safely. Try saving it again, or exporting it as a PDF."
            case .noText:
                return "No text could be read from that file."
            }
        }
    }
}
