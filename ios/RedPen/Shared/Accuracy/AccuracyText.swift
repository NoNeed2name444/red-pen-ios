import Foundation

/// What a checker is shown for an item, and the source text it is checked
/// against - for the verification layer, Explain it back and voice marking.
enum AccuracyText {

    static let noSourceNote = "No source document was provided. Judge the output against standard, current medical teaching for students; treat any claim that contradicts it as a fabricated claim."

    /// What the checker is shown for a question - here and on the server alike.
    /// Lettered A, B, C ... for any number of options (CheckedQuestion), so a
    /// sixth option is not a second "E" and a key of -1 cannot crash it.
    static func checkText(_ q: MCQQuestion) -> String {
        let base: String = CheckedQuestion.text(stem: q.stem, options: q.options,
                                                correctIndex: q.correctIndex, explanation: q.explanation)
        return base + differentialBlock(q.differential)
    }

    /// The writer's differential, for the reasoning checks to test the keyed
    /// answer against - the same block jobs.js adds on the server.
    static func differentialBlock(_ d: DifferentialTiers?) -> String {
        guard let d, !d.isEmpty else { return "" }
        return "\nDifferential:\n" + d.checkText
    }

    static func checkText(_ station: OsceChecklist) -> String {
        station.title + "\n" + station.steps.map { "- " + $0 }.joined(separator: "\n")
    }

    /// The pages of a set's sources that share the most words with `text`,
    /// up to `limit` characters. A check against the right page is a real
    /// check; a check against the first 8,000 characters of a 300-page
    /// lecture is a coin toss.
    ///
    /// A page bigger than what is left of `limit` - a whole Word lecture is
    /// one page - is cut to its own nearest paragraphs (TextSlicing.nearestPages)
    /// rather than skipped, so a Word source is still checked against.
    static func reference(for text: String, in set: StudySet, limit: Int) -> String? {
        let pages: [(heading: String, text: String)] = set.sources.flatMap { doc in
            doc.pages.map { page in (heading: "\(doc.name), \(page.number):\n", text: page.text) }
        }
        guard !pages.isEmpty else { return nil }
        return TextSlicing.nearestPages(pages, to: text, limit: limit)
    }
}

/// The old name, still used by ExplainBackView and MCQQuizView; renamed
/// there when those screens are next edited.
typealias AccuracyChecker = AccuracyText
