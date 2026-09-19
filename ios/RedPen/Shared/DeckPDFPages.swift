import UIKit

/// Drawing the pages: the bar, the chip, the watermark, the links.
///
/// Apart from DeckPDF because that file decides WHAT is printed and this one
/// decides how it looks, and because the two change for different reasons.
extension DeckPDF {

    static let barHeight: CGFloat = 34

    /// The deck's face: SF Rounded, falling back to the system font if a
    /// platform has no rounded design (it always does on iOS, but asking for a
    /// design that is not there returns nil rather than trapping).
    static func round(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    // Set for reading at arm's length off a printed A4 page, not for fitting
    // as much as possible onto one.
    static let questionSize: CGFloat = 13.5
    static let answerSize: CGFloat = 13.5
    static let questionPictureLimit = pageSize.height * 0.42
    static let answerPictureLimit = pageSize.height * 0.36

    static func color(_ p: DeckPalette, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: p.red, green: p.green, blue: p.blue, alpha: alpha)
    }

    // MARK: the furniture every page shares

    /// The white card the content sits on.
    ///
    /// Structure, not decoration: a column of text laid straight onto the
    /// tinted ground has no edges, so nothing on the page says where the card's
    /// own content begins and the page furniture ends.
    static func contentCard(from top: CGFloat, palette: DeckPalette) {
        let box = CGRect(x: margin - 12, y: top - 14,
                         width: pageSize.width - (margin - 12) * 2,
                         height: pageSize.height - 44 - (top - 14))
        color(palette.tint(0.92)).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 12).fill()
        UIColor.white.setFill()
        UIBezierPath(roundedRect: box.insetBy(dx: 0.7, dy: 0.7), cornerRadius: 11.5).fill()
    }

    /// The page's own ground: the faintest wash of the mode's colour.
    ///
    /// A sheet of pure white with one coloured strip along the top reads as a
    /// form. This is light enough not to touch how the text prints, and enough
    /// to tell two decks apart lying on a desk.
    static func paper(_ palette: DeckPalette) {
        color(palette.tint(0.975)).setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: pageSize)).fill()
    }

    /// The coloured bar, and the y it leaves behind.
    @discardableResult
    static func bar(_ left: String, right: String, palette: DeckPalette) -> CGFloat {
        // Darker on an answer page. The two pages of a card are laid out
        // identically on purpose, which left nothing to tell them apart at a
        // glance in a stack of printed sheets; the depth of the bar is that
        // signal, in the same hue, so the deck still reads as one thing.
        let fill = left.lowercased() == "answer" ? palette.barFill.shade(0.3) : palette.barFill
        color(fill).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageSize.width, height: barHeight)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: round(9, weight: .bold),
            .foregroundColor: UIColor.white,
            .kern: 1.4,
        ]
        let y = (barHeight - 11) / 2
        left.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
        let text = right.uppercased() as NSString
        let width = text.size(withAttributes: attrs).width
        text.draw(at: CGPoint(x: pageSize.width - margin - width, y: y), withAttributes: attrs)

        // A brighter strip under the bar, so the head of the page has some
        // depth to it rather than one flat block of colour.
        color(palette).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: barHeight, width: pageSize.width, height: 3)).fill()
        return barHeight + 3
    }

    /// The topic, the "Subject · Question n of m" line, and the type chip.
    /// Returns the y below the rule.
    static func heading(topic: String, subtitle: String, chip: String,
                        palette: DeckPalette, from top: CGFloat) -> CGFloat {
        var y = top + 22
        let title = topic as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: round(19, weight: .bold),
            .foregroundColor: color(palette.shade(0.10)),
        ]
        let width = pageSize.width - margin * 2
        let titleHeight = titleHeight(topic)
        title.draw(with: CGRect(x: margin, y: y, width: width, height: titleHeight),
                   options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil)
        y += titleHeight + 5

        subtitle.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: round(8.5, weight: .regular),
            .foregroundColor: UIColor(white: 0.3, alpha: 1),
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
            .font: round(7.5, weight: .heavy),
            .foregroundColor: UIColor.white,
            .kern: 0.9,
        ]
        let label = text.uppercased() as NSString
        let size = label.size(withAttributes: attrs)
        let box = CGRect(x: point.x, y: point.y, width: size.width + 16, height: 17)
        color(palette).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 8.5).fill()
        label.draw(at: CGPoint(x: box.minX + 8, y: box.minY + (box.height - size.height) / 2),
                   withAttributes: attrs)
    }

    /// The giant faint letter. Placed low and right, where the eye will not
    /// mistake it for content.
    static func watermark(_ letter: String, palette: DeckPalette) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: round(132, weight: .bold),
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
            .font: round(7.5),
            .foregroundColor: UIColor(white: 0.32, alpha: 1),
        ])
        guard let right else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: round(7.5, weight: .bold),
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
            .font: round(10, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .kern: 2,
        ])
        let name = (set.name.isEmpty ? "Red Pen deck" : set.name) as NSString
        name.draw(with: CGRect(x: margin, y: 76, width: pageSize.width - margin * 2, height: 96),
                  options: [.usesLineFragmentOrigin],
                  attributes: [.font: round(27, weight: .bold),
                               .foregroundColor: UIColor.white],
                  context: nil)

        var y: CGFloat = 230
        for (label, value) in [("Subject", set.subject),
                               ("Cards", "\(cards.count)"),
                               ("Pages", "\(cards.count * 2 + 2)")] {
            label.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: round(8, weight: .bold),
                .foregroundColor: UIColor(white: 0.34, alpha: 1), .kern: 1.2,
            ])
            value.draw(at: CGPoint(x: margin, y: y + 13), withAttributes: [
                .font: round(15, weight: .semibold),
                .foregroundColor: color(palette.shade(0.14)),
            ])
            y += 46
        }

        "Every question sits alone on a page, with its answer overleaf \u{2014} so nothing is spoiled while you test yourself."
            .draw(with: CGRect(x: margin, y: pageSize.height - 120,
                               width: pageSize.width - margin * 2, height: 60),
                  options: [.usesLineFragmentOrigin],
                  attributes: [.font: round(9.5),
                               .foregroundColor: UIColor(white: 0.3, alpha: 1)],
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
            paper(palette)
            var y = bar("Contents", right: set.subject, palette: palette) + 26
            "Contents".draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: round(17, weight: .bold),
                .foregroundColor: color(palette.shade(0.10)),
            ])
            y += 34

            while index < rows.count, y < pageSize.height - 60 {
                let row = rows[index]
                let rect = CGRect(x: margin, y: y - 3,
                                  width: pageSize.width - margin * 2, height: 19)
                // Banded, so an eye running down a long index keeps its line.
                if index % 2 == 0 {
                    color(palette.tint(0.93)).setFill()
                    UIBezierPath(roundedRect: rect.insetBy(dx: -6, dy: -1),
                                 cornerRadius: 5).fill()
                }
                row.topic.draw(with: CGRect(x: margin, y: y,
                                            width: pageSize.width - margin * 2 - 60, height: 15),
                               options: [.usesLineFragmentOrigin],
                               attributes: [.font: round(10),
                                            .foregroundColor: UIColor(white: 0.15, alpha: 1)],
                               context: nil)
                let number = row.range as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: round(9.5, weight: .heavy).monospacedDigits(),
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

    /// How tall a card's title is, measured the same way it is drawn.
    ///
    /// Shared so that the size the deck is set at can be worked out before any
    /// page exists - a measurement taken one way and a page drawn another is
    /// how a layout comes to disagree with itself about whether it fits.
    static func titleHeight(_ topic: String) -> CGFloat {
        (topic as NSString).boundingRect(
            with: CGSize(width: pageSize.width - margin * 2, height: 70),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: round(19, weight: .bold)],
            context: nil).height
    }

    /// The y a card's content starts at, given the bar and its heading.
    static func contentTop(topic: String, picture: UIImage?, limit: CGFloat) -> CGFloat {
        var y = barHeight + 3 + 22 + titleHeight(topic) + 5 + 17 + 26 + 18
        if let picture, picture.size.width > 0, picture.size.height > 0 {
            let scale = min((pageSize.width - margin * 2) / picture.size.width,
                            limit / picture.size.height)
            y += picture.size.height * scale + 16
        }
        return y
    }

    static func questionPage(_ card: DeckCard, set: StudySet, total: Int, palette: DeckPalette,
                             picture: UIImage?, scale: CGFloat,
                             context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        paper(palette)
        let top = bar(set.subject.isEmpty ? set.kind.label : set.subject,
                      right: "Card \(card.number)", palette: palette)
        var y = heading(topic: card.topic,
                        subtitle: "\(set.kind.label) \u{00B7} Question \(card.number) of \(total)",
                        chip: card.kindLabel, palette: palette, from: top)
        // Registered here, clear of the page boundary - see contents().
        context.addDestination(withName: "card\(card.number)", at: CGPoint(x: 0, y: top + 12))

        if let picture {
            y = draw(picture, from: y, limit: questionPictureLimit)
        }
        // The card first, then the watermark on top of it: drawn the other way
        // round, the opaque card paints the letter out.
        contentCard(from: y, palette: palette)
        watermark("Q", palette: palette)
        draw(card.question, from: y, palette: palette, size: questionSize, scale: scale)
        footer(left: "Question \(card.number) of \(total)",
               right: "Answer overleaf \u{203A}", palette: palette)
    }

    static func answerPage(_ card: DeckCard, set: StudySet, total: Int, palette: DeckPalette,
                           picture: UIImage?, scale: CGFloat,
                           context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        paper(palette)
        let top = bar("Answer", right: "Card \(card.number)", palette: palette)
        var y = heading(topic: card.topic,
                        subtitle: "\(set.kind.label) \u{00B7} Question \(card.number) of \(total)",
                        chip: card.kindLabel, palette: palette, from: top)
        if let picture {
            y = draw(picture, from: y, limit: answerPictureLimit)
        }
        contentCard(from: y, palette: palette)
        watermark("A", palette: palette)
        y = draw(card.answer, from: y, palette: palette, size: answerSize, scale: scale)
        if let source = card.source, !source.isEmpty {
            source.draw(at: CGPoint(x: margin, y: min(y + 10, pageSize.height - 58)),
                        withAttributes: [.font: round(8.5),
                                         .foregroundColor: UIColor(white: 0.34, alpha: 1)])
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
