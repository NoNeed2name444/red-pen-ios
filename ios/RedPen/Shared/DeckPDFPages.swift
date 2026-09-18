import UIKit

/// Drawing the pages: the bar, the chip, the watermark, the links.
///
/// Apart from DeckPDF because that file decides WHAT is printed and this one
/// decides how it looks, and because the two change for different reasons.
extension DeckPDF {

    static let barHeight: CGFloat = 34

    static func color(_ p: DeckPalette, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: p.red, green: p.green, blue: p.blue, alpha: alpha)
    }

    // MARK: the furniture every page shares

    /// The coloured bar, and the y it leaves behind.
    @discardableResult
    static func bar(_ left: String, right: String, palette: DeckPalette) -> CGFloat {
        let fill = palette.barFill
        color(fill).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageSize.width, height: barHeight)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: UIColor.white,
            .kern: 1.4,
        ]
        let y = (barHeight - 11) / 2
        left.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
        let text = right.uppercased() as NSString
        let width = text.size(withAttributes: attrs).width
        text.draw(at: CGPoint(x: pageSize.width - margin - width, y: y), withAttributes: attrs)
        return barHeight
    }

    /// The topic, the "Subject · Question n of m" line, and the type chip.
    /// Returns the y below the rule.
    static func heading(topic: String, subtitle: String, chip: String,
                        palette: DeckPalette, from top: CGFloat) -> CGFloat {
        var y = top + 22
        let title = topic as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 19, weight: .bold),
            .foregroundColor: color(palette.shade(0.10)),
        ]
        let width = pageSize.width - margin * 2
        let titleHeight = title.boundingRect(
            with: CGSize(width: width, height: 70),
            options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil).height
        title.draw(with: CGRect(x: margin, y: y, width: width, height: titleHeight),
                   options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil)
        y += titleHeight + 5

        subtitle.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ])
        y += 17

        chipBox(chip, palette: palette, at: CGPoint(x: margin, y: y))
        y += 26

        color(palette.tint(0.62)).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: width, height: 0.8)).fill()
        return y + 18
    }

    static func chipBox(_ text: String, palette: DeckPalette, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .heavy),
            .foregroundColor: color(palette.shade(0.28)),
            .kern: 0.9,
        ]
        let label = text.uppercased() as NSString
        let size = label.size(withAttributes: attrs)
        let box = CGRect(x: point.x, y: point.y, width: size.width + 16, height: 17)
        color(palette.tint(0.84)).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 8.5).fill()
        label.draw(at: CGPoint(x: box.minX + 8, y: box.minY + (box.height - size.height) / 2),
                   withAttributes: attrs)
    }

    /// The giant faint letter. Placed low and right, where the eye will not
    /// mistake it for content.
    static func watermark(_ letter: String, palette: DeckPalette) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 132, weight: .bold),
            .foregroundColor: color(palette.tint(0.80)),
        ]
        let text = letter as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: pageSize.width - margin - size.width + 6,
                              y: pageSize.height - 150),
                  withAttributes: attrs)
    }

    static func footer(left: String, right: String?, palette: DeckPalette) {
        let y = pageSize.height - 34
        left.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.5, alpha: 1),
        ])
        guard let right else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: color(palette.shade(0.18)),
            .kern: 0.8,
        ]
        let text = right.uppercased() as NSString
        let width = text.size(withAttributes: attrs).width
        text.draw(at: CGPoint(x: pageSize.width - margin - width, y: y), withAttributes: attrs)
    }

    // MARK: the pages

    static func cover(_ set: StudySet, cards: [DeckCard], palette: DeckPalette,
                      context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        color(palette.barFill).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageSize.width, height: 190)).fill()

        set.kind.label.uppercased().draw(at: CGPoint(x: margin, y: 54), withAttributes: [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .kern: 2,
        ])
        let name = (set.name.isEmpty ? "Red Pen deck" : set.name) as NSString
        name.draw(with: CGRect(x: margin, y: 76, width: pageSize.width - margin * 2, height: 96),
                  options: [.usesLineFragmentOrigin],
                  attributes: [.font: UIFont.systemFont(ofSize: 27, weight: .bold),
                               .foregroundColor: UIColor.white],
                  context: nil)

        var y: CGFloat = 230
        for (label, value) in [("Subject", set.subject),
                               ("Cards", "\(cards.count)"),
                               ("Pages", "\(cards.count * 2 + 2)")] {
            label.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: UIColor(white: 0.55, alpha: 1), .kern: 1.2,
            ])
            value.draw(at: CGPoint(x: margin, y: y + 13), withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: color(palette.shade(0.14)),
            ])
            y += 46
        }

        "Every question sits alone on a page, with its answer overleaf \u{2014} so nothing is spoiled while you test yourself."
            .draw(with: CGRect(x: margin, y: pageSize.height - 120,
                               width: pageSize.width - margin * 2, height: 60),
                  options: [.usesLineFragmentOrigin],
                  attributes: [.font: UIFont.systemFont(ofSize: 9.5),
                               .foregroundColor: UIColor(white: 0.45, alpha: 1)],
                  context: nil)
    }

    /// The contents, as real links.
    ///
    /// The destination is registered a little way DOWN each question page
    /// rather than at its very top: a destination sitting exactly on the page
    /// boundary can resolve to the previous page in some readers, which lands
    /// the student on the answer to the card before the one they tapped - the
    /// one spoiler this whole layout exists to avoid.
    static func contents(_ set: StudySet, rows: [DeckIndexRow], palette: DeckPalette,
                         context: UIGraphicsPDFRendererContext) {
        var index = 0
        while index < rows.count {
            context.beginPage()
            var y = bar("Contents", right: set.subject, palette: palette) + 26
            "Contents".draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: color(palette.shade(0.10)),
            ])
            y += 34

            while index < rows.count, y < pageSize.height - 60 {
                let row = rows[index]
                let rect = CGRect(x: margin, y: y - 3,
                                  width: pageSize.width - margin * 2, height: 19)
                row.topic.draw(with: CGRect(x: margin, y: y,
                                            width: pageSize.width - margin * 2 - 60, height: 15),
                               options: [.usesLineFragmentOrigin],
                               attributes: [.font: UIFont.systemFont(ofSize: 10),
                                            .foregroundColor: UIColor(white: 0.15, alpha: 1)],
                               context: nil)
                let number = row.range as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9.5, weight: .semibold).monospacedDigits(),
                    .foregroundColor: color(palette.shade(0.18)),
                ]
                let width = number.size(withAttributes: attrs).width
                number.draw(at: CGPoint(x: pageSize.width - margin - width, y: y),
                            withAttributes: attrs)
                // The tappable area is the whole row, not just the words.
                context.setDestinationWithName("card\(row.first)", for: rect)
                y += 19
                index += 1
            }
        }
    }

    static func questionPage(_ card: DeckCard, set: StudySet, total: Int, palette: DeckPalette,
                             picture: UIImage?, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        let top = bar(set.subject.isEmpty ? set.kind.label : set.subject,
                      right: "Card \(card.number)", palette: palette)
        var y = heading(topic: card.topic,
                        subtitle: "\(set.kind.label) \u{00B7} Question \(card.number) of \(total)",
                        chip: card.kindLabel, palette: palette, from: top)
        // Registered here, clear of the page boundary - see contents().
        context.addDestination(withName: "card\(card.number)", at: CGPoint(x: 0, y: top + 12))

        watermark("Q", palette: palette)
        if let picture {
            y = draw(picture, from: y, limit: pageSize.height * 0.42)
        }
        draw(card.question, from: y, palette: palette, size: 14.5, questionSide: true)
        footer(left: "Question \(card.number) of \(total)",
               right: "Answer overleaf \u{203A}", palette: palette)
    }

    static func answerPage(_ card: DeckCard, set: StudySet, total: Int, palette: DeckPalette,
                           picture: UIImage?, context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        let top = bar("Answer", right: "Card \(card.number)", palette: palette)
        var y = heading(topic: card.topic,
                        subtitle: "\(set.kind.label) \u{00B7} Question \(card.number) of \(total)",
                        chip: card.kindLabel, palette: palette, from: top)
        watermark("A", palette: palette)
        if let picture {
            y = draw(picture, from: y, limit: pageSize.height * 0.36)
        }
        y = draw(card.answer, from: y, palette: palette, size: 10.5, questionSide: false)
        if let source = card.source, !source.isEmpty {
            source.draw(at: CGPoint(x: margin, y: min(y + 10, pageSize.height - 58)),
                        withAttributes: [.font: UIFont.italicSystemFont(ofSize: 7.5),
                                         .foregroundColor: UIColor(white: 0.55, alpha: 1)])
        }
        footer(left: "\(set.subject) \u{00B7} Answer \(card.number)", right: nil, palette: palette)
    }

    /// A picture, scaled to fit the width and a height limit, and the y below it.
    static func draw(_ image: UIImage, from top: CGFloat, limit: CGFloat) -> CGFloat {
        let width = pageSize.width - margin * 2
        guard image.size.width > 0, image.size.height > 0 else { return top }
        let scale = min(width / image.size.width, limit / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (pageSize.width - size.width) / 2, y: top)
        image.draw(in: CGRect(origin: origin, size: size))
        return top + size.height + 16
    }
}

private extension UIFont {
    func monospacedDigits() -> UIFont {
        let settings = [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                         UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        return UIFont(descriptor: fontDescriptor.addingAttributes(
            [.featureSettings: settings]), size: pointSize)
    }
}
