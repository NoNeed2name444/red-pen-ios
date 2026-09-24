import UIKit

/// Occlusion cards in an exported PDF.
///
/// These cannot go through the text flow the rest of the export uses, and the
/// attempt was worse than useless: an occlusion card's front is "What is
/// labelled here?" and its bullet is the answer, so the whole card printed as
/// a question with no picture followed immediately by what it was asking. Every
/// card in a printed deck of diagrams gave itself away.
///
/// So each one gets a page: the slide, the mask drawn over the label the way
/// the app draws it, and the answer underneath where it can be covered with a
/// hand or folded away.
enum PDFOcclusion {

    /// The images a set carries are base64 in its JSON, which is what keeps a
    /// set portable; they become pictures only here and on screen.
    static func image(at index: Int, in set: StudySet) -> UIImage? {
        guard set.images.indices.contains(index),
              let data = Data(base64Encoded: set.images[index]) else { return nil }
        return UIImage(data: data)
    }

    static func cards(in set: StudySet) -> [AnkiCard] {
        set.cards.filter { $0.type == .occlusion && $0.occlusion != nil }
    }

    static func draw(_ set: StudySet, in context: UIGraphicsPDFRendererContext,
                     pageSize: CGRect, margin: CGFloat) {
        for (number, card) in cards(in: set).enumerated() {
            guard let index = card.imageIndex, let picture = image(at: index, in: set),
                  let box = card.occlusion else { continue }
            context.beginPage()
            page(card, number: number + 1, picture: picture, box: box,
                 others: OcclusionCovers.others(for: card, in: set.cards),
                 pageSize: pageSize, margin: margin)
        }
    }

    private static func page(_ card: AnkiCard, number: Int, picture: UIImage,
                             box: OcclusionBox, others: [OcclusionBox],
                             pageSize: CGRect, margin: CGFloat) {
        let width = pageSize.width - margin * 2
        var y = margin

        y += write("Occlusion card \(number)", at: CGPoint(x: margin, y: y), width: width,
                   font: .boldSystemFont(ofSize: 14), colour: .black)
        y += write(card.displayFront, at: CGPoint(x: margin, y: y + 2), width: width,
                   font: .systemFont(ofSize: 11.5), colour: .black)
        y += 10

        // the picture keeps its proportions and takes whatever room is left
        // after the answer's reserved strip at the foot of the page
        let available = CGSize(width: width, height: pageSize.height - y - margin - 64)
        let scale = min(available.width / max(picture.size.width, 1),
                        available.height / max(picture.size.height, 1))
        let drawn = CGRect(x: margin, y: y,
                           width: picture.size.width * scale,
                           height: picture.size.height * scale)
        picture.draw(in: drawn)

        // the masks, in the same fractions and colours the app draws: every
        // other label grey, this card's orange with a "?"
        if let context = UIGraphicsGetCurrentContext() {
            drawCovers(target: box, others: others, revealed: false, in: drawn,
                       padding: 3, minimum: 10, context: context)
        }

        var footer = drawn.maxY + 18
        footer += write("ANSWER", at: CGPoint(x: margin, y: footer), width: width,
                        font: .boldSystemFont(ofSize: 9),
                        colour: UIColor(red: 0.62, green: 0.16, blue: 0.09, alpha: 1))
        let answer = card.bullets.joined(separator: ", ")
        footer += write(answer, at: CGPoint(x: margin, y: footer + 1), width: width,
                        font: .systemFont(ofSize: 11), colour: .black)
        if !card.why.isEmpty {
            _ = write(card.why, at: CGPoint(x: margin, y: footer + 4), width: width,
                      font: .systemFont(ofSize: 10), colour: .darkGray)
        }
    }

    /// Solid covers over a picture drawn in `frame`, shared with the Anki
    /// export so a printed card, an exported card and the app all look alike.
    ///
    /// Never translucent: a cover you can half read through is no cover. Each
    /// is grown past the glyphs by `padding` and snapped outward to whole
    /// units, so no anti-aliased edge lets a letter show. With `revealed`, the
    /// other labels stay covered and the target's place is outlined instead.
    static func drawCovers(target: OcclusionBox?, others: [OcclusionBox], revealed: Bool,
                           in frame: CGRect, padding: CGFloat, minimum: CGFloat,
                           context: CGContext) {
        let grey = OcclusionCovers.otherRGB, orange = OcclusionCovers.targetRGB
        let greyColour = UIColor(red: CGFloat(grey.red), green: CGFloat(grey.green),
                                 blue: CGFloat(grey.blue), alpha: 1)
        let orangeColour = UIColor(red: CGFloat(orange.red), green: CGFloat(orange.green),
                                   blue: CGFloat(orange.blue), alpha: 1)
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(1)
        context.setBlendMode(.normal)
        context.setShouldAntialias(false)

        context.setFillColor(greyColour.cgColor)
        for box in others {
            let rect = OcclusionCovers.rect(for: box, in: frame, padding: padding, minimum: minimum)
            if rect.width > 0, rect.height > 0 { context.fill(rect) }
        }
        guard let target else { return }
        let rect = OcclusionCovers.rect(for: target, in: frame, padding: padding, minimum: minimum)
        guard rect.width > 0, rect.height > 0 else { return }
        if revealed {
            let line = max(2, padding * 0.6)
            context.setStrokeColor(orangeColour.cgColor)
            context.setLineWidth(line)
            context.stroke(rect.insetBy(dx: line / 2, dy: line / 2))
            return
        }
        context.setFillColor(orangeColour.cgColor)
        context.fill(rect)
        context.setShouldAntialias(true)
        let size = max(7, min(rect.height * 0.7, rect.width * 0.8, 40))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: UIColor.white,
        ]
        let mark = "?" as NSString
        let measured = mark.size(withAttributes: attributes)
        mark.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2),
                  withAttributes: attributes)
    }

    /// Draws one run of text and reports how tall it turned out, so the caller
    /// can put the next thing under it.
    @discardableResult
    private static func write(_ text: String, at point: CGPoint, width: CGFloat,
                              font: UIFont, colour: UIColor) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: colour, .paragraphStyle: paragraph,
        ]
        let bounds = CGSize(width: width, height: .greatestFiniteMagnitude)
        let height = (text as NSString).boundingRect(
            with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil).height
        (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: height),
                                withAttributes: attributes)
        return ceil(height)
    }
}
