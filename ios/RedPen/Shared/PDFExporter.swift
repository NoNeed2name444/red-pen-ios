import UIKit

/// Ports the web app's per-mode "Export PDF" buttons (`exportPdfBtn`,
/// `ankiExportBtn`, `exportBookPdfBtn`, `exportOscePdfBtn`,
/// `exportNarratePdfBtn`, `exportQaPdfBtn`) as one generic renderer: build a
/// flowing `NSAttributedString` for whichever kind of set this is, then
/// paginate it into a real multi-page PDF with Core Text. No jsPDF equivalent
/// is needed - `UIGraphicsPDFRenderer` and `CTFramesetter` do the same job
/// natively.
///
/// Occlusion cards are the exception and get pages of their own, drawn by
/// PDFOcclusion: a picture cannot flow through a text frame, and a card whose
/// whole content is a masked diagram has nothing to say without it.
enum PDFExporter {
    private static let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792) // US letter, matches jsPDF's default
    private static let margin: CGFloat = 42

    /// Renders `set` to a PDF file in a temp directory and returns its URL,
    /// ready for a `ShareLink` or `UIActivityViewController`.
    static func export(_ set: StudySet) -> URL? {
        let text = attributedString(for: set)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitizedFileName(set.name))
            .appendingPathExtension("pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        do {
            try renderer.writePDF(to: url) { context in
                paginate(text, context: context)
                PDFOcclusion.draw(set, in: context, pageSize: pageSize, margin: margin)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: pagination - a generic Core Text flow across as many pages as needed

    private static func paginate(_ text: NSAttributedString, context: UIGraphicsPDFRendererContext) {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let textRect = pageSize.insetBy(dx: margin, dy: margin)
        let path = CGPath(rect: textRect, transform: nil)
        var start = 0
        let length = text.length

        while start < length {
            context.beginPage()
            let range = CFRangeMake(start, 0)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            let cgContext = context.cgContext
            cgContext.saveGState()
            // Core Text draws bottom-up; flip so it matches the page's top-down layout.
            cgContext.textMatrix = .identity
            cgContext.translateBy(x: 0, y: pageSize.height)
            cgContext.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, cgContext)
            cgContext.restoreGState()

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break } // guard against an infinite loop on content that can't fit at all
            start += visible.length
        }
    }

    // MARK: content per StudySet kind

    private static func attributedString(for set: StudySet) -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(title(set.name))
        out.append(subtitle("\(set.kind.label) · \(set.subject) · \(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")"))
        out.append(rule())

        switch set.kind {
        case .mcq:
            for (i, q) in set.questions.enumerated() {
                out.append(heading("Question \(i + 1)"))
                out.append(body(q.stem))
                for (idx, opt) in q.options.enumerated() {
                    let mark = idx == q.correctIndex ? "✓" : " "
                    out.append(bullet("\(mark) \(letter(idx)). \(opt)", emphasize: idx == q.correctIndex))
                }
                if !q.explanation.isEmpty { out.append(note("Why", q.explanation)) }
                out.append(spacer())
            }
        case .anki:
            // occlusion cards are drawn later, as pictures
            for (i, card) in set.cards.enumerated() where card.type != .occlusion {
                out.append(heading("Card \(i + 1)"))
                if card.type == .cloze {
                    // the sentence with its blanks IS the card; printing the
                    // front instead left every cloze card in the export blank
                    out.append(body(card.clozeText))
                } else {
                    out.append(body(card.displayFront))
                    for b in card.bullets { out.append(bullet(b, emphasize: false)) }
                }
                if !card.why.isEmpty { out.append(note("Why / how", card.why)) }
                out.append(spacer())
            }
        case .book:
            for page in BookPages.split(set.bookMarkdown) {
                out.append(heading(page.title))
                out.append(body(page.markdown))
                out.append(spacer())
            }
        case .qa:
            for (i, card) in set.qaCards.enumerated() {
                out.append(heading("\(i + 1). \(card.topic.isEmpty ? card.badge : card.topic) — \(card.badge)"))
                out.append(body(card.stem))
                for a in card.answer { out.append(bullet(a, emphasize: false)) }
                out.append(spacer())
            }
        case .osce:
            for checklist in set.osceChecklists {
                out.append(heading(checklist.title))
                for (i, step) in checklist.steps.enumerated() { out.append(bullet("\(i + 1). \(step)", emphasize: false)) }
                out.append(spacer())
            }
        case .narrate:
            for seg in set.narrateSegments { out.append(body(seg.text)) }
        }
        return out
    }

    // MARK: small attributed-string builders

    private static func title(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black])
    }
    private static func subtitle(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s + "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
    }
    private static func rule() -> NSAttributedString {
        NSAttributedString(string: String(repeating: "—", count: 40) + "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.lightGray])
    }
    private static func heading(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.black])
    }
    private static func body(_ s: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3; para.paragraphSpacing = 8
        return NSAttributedString(string: s + "\n", attributes: [.font: UIFont.systemFont(ofSize: 11.5), .foregroundColor: UIColor.black, .paragraphStyle: para])
    }
    private static func bullet(_ s: String, emphasize: Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.firstLineHeadIndent = 6; para.headIndent = 6; para.lineSpacing = 2; para.paragraphSpacing = 3
        return NSAttributedString(string: s + "\n", attributes: [
            .font: emphasize ? UIFont.boldSystemFont(ofSize: 11) : UIFont.systemFont(ofSize: 11),
            .foregroundColor: emphasize ? UIColor(red: 0.18, green: 0.43, blue: 0.29, alpha: 1) : UIColor.black,
            .paragraphStyle: para,
        ])
    }
    private static func note(_ label: String, _ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle(); para.paragraphSpacingBefore = 4; para.paragraphSpacing = 8
        out.append(NSAttributedString(string: label.uppercased() + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 9), .foregroundColor: UIColor(red: 0.62, green: 0.16, blue: 0.09, alpha: 1), .paragraphStyle: para]))
        out.append(NSAttributedString(string: text + "\n", attributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.darkGray]))
        return out
    }
    private static func spacer() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 6)])
    }
    private static func letter(_ idx: Int) -> String {
        String(Character(Unicode.Scalar(UInt8(65 + idx))))
    }
    private static func sanitizedFileName(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "red-pen-export" : cleaned
    }
}
