import Foundation
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

    static func read(_ url: URL, findingFigures: Bool = true) async throws
        -> SourceIngest.Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw Trouble.unreadable }
        let archive = Zip.entries(in: data)
        guard !archive.isEmpty else { throw Trouble.notAnOfficeFile }

        let name = url.deletingPathExtension().lastPathComponent
        let slides = PptxText.slidePaths(in: Array(archive.keys))

        let raw: [(number: Int, text: String, recognised: Bool)]
        let pictures: [Data]

        if !slides.isEmpty {
            raw = PptxText.pages(archive)
            pictures = PptxText.images(archive)
        } else if archive[DocxText.documentPath] != nil {
            let read = DocxText.read(archive)
            raw = [(1, read.text, false)]
            pictures = read.images
        } else {
            throw Trouble.notAnOfficeFile
        }

        let document = SourceText.document(from: raw)
        var figures: [UIImage] = []
        var notes: [(page: Int?, labels: [String])] = []
        var cards: [AnkiCard] = []
        if findingFigures {
            for picture in pictures {
                autoreleasepool {
                    guard let image = UIImage(data: picture), let cg = image.cgImage,
                          let found = FigureFinder.read(cg, imageIndex: figures.count)
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
                    figures.append(image)
                    notes.append((nil, found.cards.flatMap(\.bullets)))
                }
            }
        }

        guard !document.isEmpty || !cards.isEmpty else { throw Trouble.noText }
        return SourceIngest.Result(document: document, figures: figures,
                                   occlusionCards: cards, figureNotes: notes)
    }

    enum Trouble: LocalizedError {
        case unreadable, notAnOfficeFile, noText
        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file could not be opened."
            case .notAnOfficeFile:
                return "That does not look like a Word or PowerPoint file. An old .doc or .ppt needs saving as .docx or .pptx first."
            case .noText:
                return "No text could be read from that file."
            }
        }
    }
}
