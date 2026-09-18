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

    /// The band behind the right answer, drawn before the text so it sits under it.
    ///
    /// A hairline rule in the margin was too quiet on paper: printed at A4 and
    /// read at arm's length, the right answer has to be findable without
    /// hunting for a change in font weight.
    static func drawBand(correct: Bool, y: CGFloat, size: CGFloat, width: CGFloat,
                         palette: DeckPalette) {
        guard correct else { return }
        let box = CGRect(x: margin - 8, y: y - size * 0.3, width: width + 16, height: size * 1.85)
        color(palette.tint(0.88)).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
        color(palette, 0.9).setFill()
        UIBezierPath(rect: CGRect(x: box.minX, y: box.minY, width: 2.5, height: box.height)).fill()
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
                    .font: UIFont.systemFont(ofSize: size),
                    .foregroundColor: UIColor(white: 0.5, alpha: 1),
                ])
                break
            }
            switch block {
            case .text(let text):
                y += write(text, x: margin, y: y, width: width,
                           font: .systemFont(ofSize: size, weight: .semibold),
                           color: UIColor(white: 0.07, alpha: 1), measuring: measuring,
                           accent: color(palette.shade(0.22)))
                y += size * 0.5

            case .bullet(let lead, let text):
                let indent: CGFloat = 14
                if !measuring {
                    "\u{2022}".draw(at: CGPoint(x: margin, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: size),
                        .foregroundColor: color(palette, 0.9),
                    ])
                }
                y += writeLead(lead, text: text, x: margin + indent, y: y,
                               width: width - indent, size: size, palette: palette,
                               measuring: measuring)
                y += size * 0.42

            case .option(let letter, let text, let correct):
                let indent: CGFloat = 20
                if !measuring {
                    let marker = (letter + ".") as NSString
                    drawBand(correct: correct, y: y, size: size, width: width, palette: palette)
                    marker.draw(at: CGPoint(x: margin, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: size, weight: correct ? .bold : .regular),
                        .foregroundColor: correct ? color(palette.shade(0.14))
                                                  : UIColor(white: 0.22, alpha: 1),
                    ])
                }
                y += write(text, x: margin + indent, y: y, width: width - indent,
                           font: .systemFont(ofSize: size, weight: correct ? .semibold : .regular),
                           color: correct ? UIColor(white: 0.07, alpha: 1)
                                          : UIColor(white: 0.16, alpha: 1),
                           measuring: measuring, accent: color(palette.shade(0.22)))
                y += size * 0.45

            case .note(let label, let text):
                y += size * 0.3
                if !measuring {
                    label.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: size * 0.78, weight: .heavy),
                        .foregroundColor: color(palette.shade(0.2)),
                        .kern: 0.8,
                    ])
                }
                y += size * 1.05
                y += write(marking(key, in: text), x: margin, y: y, width: width,
                           font: .systemFont(ofSize: size * 0.94),
                           color: UIColor(white: 0.16, alpha: 1), measuring: measuring,
                           accent: color(palette.shade(0.22)))
                y += size * 0.5
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
            out.replaceSubrange(found, with: "**" + out[found] + "**")
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
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: color(palette.shade(0.16)),
            ]))
        }
        if !text.isEmpty {
            let plain = UIFont.systemFont(ofSize: size)
            let strong = UIFont.systemFont(ofSize: size, weight: .bold)
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
            ?? UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
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
