import Foundation
import UIKit

/// A Word handout, brought in the same door as a PDF.
///
/// The two formats differ in how the words are stored and in nothing else that
/// matters: what comes out is a document and a set of pictures, and everything
/// downstream - cleaning, generation, occlusion - is shared. So this returns a
/// SourceIngest.Result rather than a shape of its own.
///
/// The one real difference is pages. A PDF has them; a .docx does not - Word
/// decides where the page breaks fall when it lays the document out, and the
/// file itself does not say. So the handout arrives as one page, which costs
/// nothing: page numbers were only ever used to find the running footer, and a
/// document with no pages has no footer to find.
enum DocxIngest {

    static func read(docx url: URL, findingFigures: Bool = true) async throws
        -> SourceIngest.Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw Trouble.unreadable }
        let archive = Zip.entries(in: data)
        guard archive[DocxText.documentPath] != nil else { throw Trouble.notAWordFile }

        let read = DocxText.read(archive)
        let document = SourceText.document(from: [(1, read.text, false)])

        var figures: [UIImage] = []
        var cards: [AnkiCard] = []
        if findingFigures {
            for data in read.images {
                autoreleasepool {
                    guard let image = UIImage(data: data), let cg = image.cgImage,
                          let found = FigureFinder.read(cg, imageIndex: figures.count)
                    else { return }
                    figures.append(image)
                    cards.append(contentsOf: found.cards)
                }
            }
        }

        guard !document.isEmpty || !cards.isEmpty else { throw Trouble.noText }
        return SourceIngest.Result(document: document, figures: figures,
                                   occlusionCards: cards)
    }

    enum Trouble: LocalizedError {
        case unreadable, notAWordFile, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file could not be opened."
            case .notAWordFile:
                return "That does not look like a Word document \u{2014} it has no document.xml inside it. A .doc from a very old Word needs saving as .docx first."
            case .noText: return "No text could be read from that document."
            }
        }
    }
}
