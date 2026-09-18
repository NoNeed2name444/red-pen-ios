import UIKit
import Vision

/// Printing a set as a flashcard deck.
///
/// One question to a page, its answer on the very next page, so nothing is
/// spoiled while you test yourself - which is the entire reason the layout is
/// this rigid. Every page carries the mode's own colour, so a deck printed from
/// Cases is recognisably Cases.
///
/// The contents index is made of real PDF links. That is what makes the file
/// usable on a phone: six hundred cards is unnavigable by scrolling, and a
/// tapped topic has to land on the card itself.
enum DeckPDF {

    // A4, in points.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 46

    /// Writes the deck and returns the file.
    ///
    /// Anki sets are refused rather than printed: their scheduling and their
    /// occlusion masks do not survive a PDF, and .apkg keeps both. The library
    /// offers .apkg for those, and this is the guard that keeps the two from
    /// being confused if a caller gets it wrong.
    static func export(_ set: StudySet) -> URL? {
        guard DeckBuilder.printsAsPDF(set.kind) else { return nil }
        var cards = DeckBuilder.cards(for: set)
        guard !cards.isEmpty else { return nil }

        let pictures = images(in: set)
        place(&cards, using: pictures)

        let palette = DeckPalette.of(set.kind)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize),
                                             format: info(for: set, count: cards.count))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: set))

        do {
            try renderer.writePDF(to: url) { context in
                cover(set, cards: cards, palette: palette, context: context)
                contents(set, rows: DeckIndex.rows(cards), palette: palette, context: context)
                for card in cards {
                    questionPage(card, set: set, total: cards.count, palette: palette,
                                 picture: picture(for: card, in: pictures, on: .question),
                                 context: context)
                    answerPage(card, set: set, total: cards.count, palette: palette,
                               picture: picture(for: card, in: pictures, on: .answer),
                               context: context)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: pictures

    struct Picture {
        var image: UIImage
        /// What the picture says, as far as it could be read. Empty is normal.
        var text: String
    }

    /// Decodes the set's pictures and reads whatever text is in them.
    ///
    /// Reading them is what makes the spoiler decision real rather than a
    /// guess. It is slow - a second or so per picture - but this happens once,
    /// when somebody deliberately exports, and it is the difference between a
    /// deck you can test yourself with and one that shows you the answers.
    static func images(in set: StudySet) -> [Int: Picture] {
        var out: [Int: Picture] = [:]
        for index in set.images.indices {
            autoreleasepool {
                guard let image = decode(set.images[index]) else { return }
                out[index] = Picture(image: image, text: readText(image))
            }
        }
        return out
    }

    static func decode(_ encoded: String) -> UIImage? {
        var payload = encoded
        if let comma = payload.range(of: ","), payload.hasPrefix("data:") {
            payload = String(payload[comma.upperBound...])
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    static func readText(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: " ")
    }

    /// Settles which page each picture belongs on.
    static func place(_ cards: inout [DeckCard], using pictures: [Int: Picture]) {
        for i in cards.indices {
            guard let index = cards[i].imageIndex, let picture = pictures[index] else { continue }
            cards[i].imagePlacement = ImageSpoiler.placement(
                imageText: picture.text,
                question: plain(cards[i].question),
                answer: plain(cards[i].answer))
        }
    }

    static func picture(for card: DeckCard, in pictures: [Int: Picture],
                        on side: ImageSpoiler.Placement) -> UIImage? {
        guard let index = card.imageIndex, card.imagePlacement == side else { return nil }
        return pictures[index]?.image
    }

    static func plain(_ blocks: [DeckBlock]) -> String {
        blocks.map { block in
            switch block {
            case .text(let t): return t
            case .bullet(let lead, let t): return [lead, t].compactMap { $0 }.joined(separator: " ")
            case .option(_, let t, _): return t
            case .note(let label, let t): return label + " " + t
            }
        }.joined(separator: " ")
    }

    // MARK: file

    static func info(for set: StudySet, count: Int) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: set.name,
            kCGPDFContextSubject as String:
                "\(count) cards \u{2014} \(set.subject), \(set.kind.label)",
            kCGPDFContextCreator as String: "Red Pen",
        ]
        return format
    }

    static func fileName(for set: StudySet) -> String {
        let safe = set.name.isEmpty ? "Red Pen deck" : set.name
        let cleaned = safe.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        return cleaned + ".pdf"
    }
}
