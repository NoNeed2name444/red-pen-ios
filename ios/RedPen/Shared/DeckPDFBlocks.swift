import UIKit

/// Laying out a card's own content, and making it fit.
///
/// Fitting is not a nicety here. Every card is exactly two pages, and the
/// reader's whole promise - your answer is overleaf and nowhere else - holds
/// only while that is true. One answer that spills onto a third page shifts
/// every card after it by one, so from that point on every question is printed
/// opposite the previous card's answer. So content is measured first and
/// stepped down through a ladder of sizes until it fits, and a card that still
/// will not fit is truncated with a mark rather than allowed to run over.
extension DeckPDF {

    /// The sizes a card is allowed to shrink through before it is cut.
    static let ladder: [CGFloat] = [1.0, 0.94, 0.88, 0.82, 0.76, 0.7, 0.64]

    /// Draws the blocks, shrinking them first if they would not otherwise fit.
    /// Returns the y it finished at.
    @discardableResult
    static func draw(_ blocks: [DeckBlock], from top: CGFloat, palette: DeckPalette,
                     size: CGFloat, scale: CGFloat) -> CGFloat {
        // Both sides start directly under the rule. Centring the question in
        // what was left of the page made every question page sit at a different
        // height, so a deck flicked through looked like pages from several
        // different documents.
        render(blocks, from: top, palette: palette, size: size * scale, measuring: false)
    }

    /// The one step at which EVERY card on a side still fits.
    ///
    /// Fitting each card on its own is what made a deck look unfinished: a card
    /// with three lines was set at full size and the next one at two thirds of
    /// it, so the type changed size each time a page was turned. Taking the
    /// smallest step any card needs and using it throughout keeps every page
    /// identical to every other, which is the only way a deck reads as one
    /// thing rather than a pile.
    ///
    /// It still has to shrink at all because every card is exactly two pages:
    /// one answer spilling onto a third would print every later question
    /// opposite the previous card's answer.
    static func fit(_ sides: [(blocks: [DeckBlock], top: CGFloat)], palette: DeckPalette,
                    size: CGFloat) -> CGFloat {
        var scale = ladder[0]
        for step in ladder {
            scale = step
            let overflowing = sides.contains { side in
                height(side.blocks, palette: palette, size: size * step)
                    > pageSize.height - 52 - side.top
            }
            if !overflowing { break }
        }
        return scale
    }

    /// The band behind the right answer, sized to the answer it sits behind.
    ///
    /// A hairline rule in the margin was too quiet on paper: printed at A4 and
    /// read at arm's length, the right answer has to be findable without
    /// hunting for a change in font weight.
    static func band(correct: Bool, y: CGFloat, height: CGFloat, width: CGFloat,
                     palette: DeckPalette) {
        guard correct else { return }
        let box = CGRect(x: margin - 10, y: y - 4,
                         width: width + 20, height: height + 9)
        color(palette.tint(0.88)).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 7).fill()
    }

    /// The option's letter, in a circle of one fixed size.
    ///
    /// Drawn as a disc with the glyph centred in it rather than as a box around
    /// the glyph: a box takes the width of whatever letter is inside it, so A
    /// and I came out different widths and the column of letters looked
    /// accidental. The disc is the same for every option on every card.
    static func badge(_ letter: String, at point: CGPoint, size: CGFloat,
                      correct: Bool, palette: DeckPalette) {
        let diameter = size * 1.45
        let circle = CGRect(x: point.x, y: point.y - 1, width: diameter, height: diameter)
        color(correct ? palette : palette.tint(0.86)).setFill()
        UIBezierPath(ovalIn: circle).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: DeckPDF.round(size * 0.78, weight: .heavy),
            .foregroundColor: correct ? UIColor.white : color(palette.shade(0.34)),
        ]
        let glyph = letter as NSString
        let measured = glyph.size(withAttributes: attrs)
        glyph.draw(at: CGPoint(x: circle.midX - measured.width / 2,
                               y: circle.midY - measured.height / 2),
                   withAttributes: attrs)
    }

    static func height(_ blocks: [DeckBlock], palette: DeckPalette, size: CGFloat) -> CGFloat {
        render(blocks, from: 0, palette: palette, size: size, measuring: true)
    }

    /// One pass over the blocks, either measuring or drawing.
    ///
    /// Deliberately the same code for both. Measuring with one routine and
    /// drawing with another is how a layout comes to disagree with itself about
    /// whether it fits.
    @discardableResult
    static func render(_ blocks: [DeckBlock], from top: CGFloat, palette: DeckPalette,
                       size: CGFloat, measuring: Bool) -> CGFloat {
        let width = pageSize.width - margin * 2
        var y = top
        let limit = pageSize.height - 48
        // The phrase worth picking out of the reasoning, on a card that carries
        // no marked terms of its own. Taken from the option marked correct, so
        // it is empty on a question page by construction - no option is marked
        // correct there, which is what keeps this from spoiling anything.
        let key = keyPhrase(blocks)

        for block in blocks {
            if !measuring, y > limit {
                "\u{2026}".draw(at: CGPoint(x: margin, y: min(y, limit)), withAttributes: [
                    .font: DeckPDF.round(size),
                    .foregroundColor: UIColor(white: 0.5, alpha: 1),
                ])
                break
            }
            switch block {
            case .text(let text):
                y += write(text, x: margin, y: y, width: width,
                           font: DeckPDF.round(size, weight: .semibold),
                           color: UIColor(white: 0.07, alpha: 1), measuring: measuring,
                           accent: color(palette.shade(0.22)))
                y += size * 0.5

            case .bullet(let lead, let text):
                // A tinted row per bullet, with a dot rather than a glyph. A
                // list of OSCE steps is a list of things to DO, and set as
                // plain paragraphs with bullets it reads as prose.
                let indent = size * 1.5
                let rowHeight = writeLead(lead, text: text, x: margin + indent, y: y,
                                          width: width - indent, size: size, palette: palette,
                                          measuring: true)
                if !measuring {
                    let row = CGRect(x: margin - 8, y: y - size * 0.35,
                                     width: width + 16, height: rowHeight + size * 0.7)
                    color(palette.tint(0.93)).setFill()
                    UIBezierPath(roundedRect: row, cornerRadius: 6).fill()
                    color(palette, 0.95).setFill()
                    UIBezierPath(ovalIn: CGRect(x: margin, y: y + size * 0.32,
                                                width: size * 0.38, height: size * 0.38)).fill()
                    _ = writeLead(lead, text: text, x: margin + indent, y: y,
                                  width: width - indent, size: size, palette: palette,
                                  measuring: false)
                }
                y += rowHeight + size * 0.75

            case .option(let letter, let text, let correct):
                let indent = size * 2.1
                // Measured first, so the band behind a right answer is the
                // height of the answer rather than a guess: an option that
                // wraps onto two lines used to get the same short box as a
                // one-line option, and the column looked broken.
                let textHeight = write(text, x: margin + indent, y: y, width: width - indent,
                                       font: DeckPDF.round(size, weight: correct ? .semibold : .regular),
                                       color: .black, measuring: true)
                if !measuring {
                    band(correct: correct, y: y, height: textHeight, width: width,
                         palette: palette)
                    badge(letter, at: CGPoint(x: margin + size * 0.35, y: y),
                          size: size, correct: correct, palette: palette)
                }
                y += write(text, x: margin + indent, y: y + size * 0.1, width: width - indent,
                           font: DeckPDF.round(size, weight: correct ? .semibold : .regular),
                           color: correct ? UIColor(white: 0.07, alpha: 1)
                                          : UIColor(white: 0.16, alpha: 1),
                           measuring: measuring, accent: color(palette.shade(0.22)))
                y += size * 0.7

            case .note(let label, let text):
                // Its own card, so the reasoning reads as a separate thing from
                // the options above it rather than as more of the same column.
                let marked = marking(key, in: text)
                let body = DeckPDF.round(size * 0.94)
                let inset: CGFloat = 12
                let textHeight = write(marked, x: margin + inset, y: y, width: width - inset * 2,
                                       font: body, color: .black, measuring: true)
                let cardHeight = textHeight + size * 2.4
                if !measuring {
                    let card = CGRect(x: margin - 6, y: y, width: width + 12, height: cardHeight)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: card, cornerRadius: 7).fill()
                    color(palette, 0.9).setFill()
                    UIBezierPath(roundedRect: CGRect(x: card.minX, y: card.minY,
                                                     width: 3.4, height: card.height),
                                 cornerRadius: 1.7).fill()
                    label.uppercased().draw(at: CGPoint(x: margin + inset, y: y + size * 0.5),
                                            withAttributes: [
                        .font: DeckPDF.round(size * 0.78, weight: .heavy),
                        .foregroundColor: color(palette.shade(0.2)),
                        .kern: 0.8,
                    ])
                }
                _ = write(marked, x: margin + inset, y: y + size * 1.7, width: width - inset * 2,
                      font: body, color: UIColor(white: 0.16, alpha: 1), measuring: measuring,
                      accent: color(palette.shade(0.22)))
                y += cardHeight + size * 0.4

            }
        }
        return y
    }

    /// The answer's own phrase, for cards written without any marking.
    ///
    /// A set with nothing marked prints as a wall of one grey, which is exactly
    /// the page that is hard to revise from. The option marked correct is the
    /// one phrase on the page that is certainly the point of the card, so that
    /// is what gets picked out of the reasoning.
    static func keyPhrase(_ blocks: [DeckBlock]) -> String? {
        for block in blocks {
            if case .option(_, let text, let correct) = block, correct {
                let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                return trimmed.count >= 4 ? trimmed : nil
            }
        }
        return nil
    }

    /// Marks a phrase where it appears, leaving text that is already marked alone.
    static func marking(_ phrase: String?, in text: String) -> String {
        guard let phrase, !text.contains("**") else { return text }
        var out = text
        var searched = out.startIndex..<out.endIndex
        while let found = out.range(of: phrase, options: .caseInsensitive, range: searched) {
            out.replaceSubrange(found, with: "**" + String(out[found]) + "**")
            guard let resume = out.index(found.lowerBound, offsetBy: phrase.count + 4,
                                         limitedBy: out.endIndex) else { break }
            searched = resume..<out.endIndex
        }
        return out
    }

    /// A bullet whose opening phrase is set in the deck's colour.
    static func writeLead(_ lead: String?, text: String, x: CGFloat, y: CGFloat, width: CGFloat,
                          size: CGFloat, palette: DeckPalette, measuring: Bool) -> CGFloat {
        let body = NSMutableAttributedString()
        if let lead, !lead.isEmpty {
            body.append(NSAttributedString(string: text.isEmpty ? lead : lead + ": ", attributes: [
                .font: DeckPDF.round(size, weight: .bold),
                .foregroundColor: color(palette.shade(0.16)),
            ]))
        }
        if !text.isEmpty {
            let plain = DeckPDF.round(size)
            let strong = DeckPDF.round(size, weight: .bold)
            for run in Highlight.runs(text) {
                body.append(NSAttributedString(string: run.text, attributes: [
                    .font: run.bold ? strong : plain,
                    .foregroundColor: run.bold ? color(palette.shade(0.22))
                                               : UIColor(white: 0.18, alpha: 1),
                ]))
            }
        }
        guard body.length > 0 else { return 0 }
        let rect = body.boundingRect(with: CGSize(width: width, height: 2000),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     context: nil)
        if !measuring {
            body.draw(with: CGRect(x: x, y: y, width: width, height: ceil(rect.height)),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return ceil(rect.height)
    }

    /// Writes text, setting anything marked in the deck's own colour.
    ///
    /// Colour is the point here, not decoration. A printed page of one uniform
    /// grey gives the eye nowhere to land: the term a card is actually about
    /// reads exactly like the words around it, so nothing can be found by
    /// glancing. What the student marked while writing the set is what matters
    /// on the card, so that is what is coloured - a deliberate choice already
    /// made, rather than this code guessing at which words look important.
    ///
    /// Weight carries it as well as hue, so the emphasis survives a black and
    /// white printer and is still visible to somebody who cannot distinguish
    /// the colour.
    static func write(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
                      font: UIFont, color textColor: UIColor, measuring: Bool,
                      accent: UIColor? = nil) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font.pointSize * 0.22

        let body = NSMutableAttributedString()
        let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
        let bold = descriptor.map { UIFont(descriptor: $0, size: font.pointSize) }
            ?? DeckPDF.round(font.pointSize, weight: .bold)
        for run in Highlight.runs(text) {
            body.append(NSAttributedString(string: run.text, attributes: [
                .font: run.bold ? bold : font,
                .foregroundColor: run.bold ? (accent ?? textColor) : textColor,
                .paragraphStyle: paragraph,
            ]))
        }
        guard body.length > 0 else { return 0 }
        let rect = body.boundingRect(with: CGSize(width: width, height: 4000),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     context: nil)
        if !measuring {
            body.draw(with: CGRect(x: x, y: y, width: width, height: ceil(rect.height)),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return ceil(rect.height)
    }
}
