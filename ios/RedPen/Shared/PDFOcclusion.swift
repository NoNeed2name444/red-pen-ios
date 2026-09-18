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
                 pageSize: pageSize, margin: margin)
        }
    }

    private static func page(_ card: AnkiCard, number: Int, picture: UIImage,
                             box: OcclusionBox, pageSize: CGRect, margin: CGFloat) {
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

        // the mask, in the same fractions the app stores and the app draws
        let mask = CGRect(x: drawn.minX + box.x * drawn.width,
                          y: drawn.minY + box.y * drawn.height,
                          width: box.w * drawn.width,
                          height: box.h * drawn.height)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor(red: 0.62, green: 0.16, blue: 0.09, alpha: 1).cgColor)
        context?.fill(mask)

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
