import Foundation

/// Which page a generated question came off.
///
/// The model is not asked. Asking it to cite its own page invites it to invent
/// a plausible number, which is exactly the failure provenance exists to catch;
/// and a small on-device model asked to carry a citation through a long answer
/// usually drops it. So the attribution is made afterwards, by looking at which
/// page's text the question actually shares its words with. A question that
/// matches no page well gets no citation, which is itself worth seeing: it
/// means the question drifted from the source.
///
/// Pure, so it can be tested.
enum Provenance {

    static func label(_ name: String, page: Int) -> String {
        name.isEmpty ? "p. \(page)" : "\(name), p. \(page)"
    }

    /// The page sharing most of this text's own words, if any page shares
    /// enough of them to be worth naming.
    ///
    /// Measured as a share of the QUESTION's words rather than the page's:
    /// pages differ wildly in length, and dividing by the page would hand every
    /// question to the shortest slide in the deck.
    static func page(for text: String, in pages: [SourceText.Page],
                     floor: Double = 0.3) -> Int? {
        let wanted = MCQCoverage.contentWords(text)
        guard !wanted.isEmpty else { return nil }
        var best: (share: Double, page: Int)?
        for page in pages {
            let have = MCQCoverage.contentWords(page.text)
            guard !have.isEmpty else { continue }
            let share = Double(wanted.intersection(have).count) / Double(wanted.count)
            if share >= floor, best == nil || share > best!.share {
                best = (share, page.number)
            }
        }
        return best?.page
    }

    /// Cites each question against the document it was generated from.
    ///
    /// The stem alone is not enough to go on - a vignette is written in the
    /// model's own words - so the answer and explanation are weighed with it,
    /// since those carry the source's terminology.
    static func attribute(_ questions: [MCQQuestion], to document: SourceText.Document,
                          name: String) -> [MCQQuestion] {
        guard !document.pages.isEmpty else { return questions }
        return questions.map { question in
            var cited = question
            let key = question.options.indices.contains(question.correctIndex)
                ? question.options[question.correctIndex] : ""
            let material = [question.stem, key, question.explanation].joined(separator: " ")
            if let found = page(for: material, in: document.pages) {
                cited.source = label(name, page: found)
            }
            return cited
        }
    }

    /// The same, for cards.
    static func attribute(_ cards: [AnkiCard], to document: SourceText.Document,
                          name: String) -> [AnkiCard] {
        guard !document.pages.isEmpty else { return cards }
        return cards.map { card in
            // a figure card already knows its page exactly; nothing guessed
            // should overwrite something known
            guard card.source == nil else { return card }
            var cited = card
            let material = [card.front, card.clozeText, card.bullets.joined(separator: " "),
                            card.why].joined(separator: " ")
            if let found = page(for: material, in: document.pages) {
                cited.source = label(name, page: found)
            }
            return cited
        }
    }
}
