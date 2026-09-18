import Foundation

/// `**term**` emphasis, and nothing else.
///
/// Cases cards are not Markdown. They are typed as "Question | answer; answer"
/// with the key term wrapped in asterisks, which is all the web app ever did
/// with them. Handing that text to a full Markdown reader interprets a great
/// deal more than was ever meant: a pair of underscores in "T_max_" becomes
/// italics and the underscores vanish, a line beginning "1." becomes a list, a
/// backtick starts code, a stray bracket eats what follows it. Medical writing
/// is full of exactly those characters.
///
/// So this reads the one thing the format promises and leaves every other
/// character alone. A textbook set is different - that really is Markdown, and
/// the reader treats it as such.
enum Highlight {

    /// The text, with anything between double asterisks emboldened.
    ///
    /// An unclosed `**` is not emphasis. It is two asterisks somebody typed,
    /// and they stay on the screen as two asterisks rather than swallowing the
    /// rest of the card.
    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        for run in runs(text) {
            var piece = AttributedString(run.text)
            if run.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            out.append(piece)
        }
        return out
    }

    struct Run: Equatable {
        var text: String
        var bold: Bool
    }

    /// The text split into plain and emboldened stretches.
    ///
    /// Separated from the AttributedString so it can be tested: what matters is
    /// which characters end up bold and which survive untouched, and that is a
    /// question about strings.
    static func runs(_ text: String) -> [Run] {
        var out: [Run] = []
        var plain = ""
        var rest = Substring(text)

        func keepPlain() {
            if !plain.isEmpty { out.append(Run(text: plain, bold: false)); plain = "" }
        }

        while let open = rest.range(of: "**") {
            let after = rest[open.upperBound...]
            // The closing pair, if there is one. Without it these are just
            // asterisks.
            guard let close = after.range(of: "**") else { break }
            let inner = after[..<close.lowerBound]
            // "****" is not emphasis of nothing; it is four asterisks.
            guard !inner.isEmpty else {
                plain += rest[..<close.upperBound]
                rest = after[close.upperBound...]
                continue
            }
            plain += rest[..<open.lowerBound]
            keepPlain()
            out.append(Run(text: String(inner), bold: true))
            rest = after[close.upperBound...]
        }

        plain += rest
        keepPlain()
        return out
    }

    /// The same text with the markers removed and nothing emphasised - for
    /// somewhere that cannot carry styling, such as a PDF export line or a
    /// search index.
    static func plain(_ text: String) -> String {
        runs(text).map(\.text).joined()
    }
}
