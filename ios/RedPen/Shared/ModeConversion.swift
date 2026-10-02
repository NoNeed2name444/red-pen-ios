import Foundation

/// Turning a set of one mode into a set of another - an MCQ quiz into Anki
/// cards, a deck into a quiz, an OSCE station into cards to drill its order.
///
/// Two kinds of turning, and the difference matters to the student:
///
/// - **Instant.** When the content already says everything the other mode
///   needs, it is simply rearranged: a question's stem is a card's front and
///   its right answer is the back. Nothing is written by a model and nothing
///   leaves the phone, so the new set is exactly as right as the old one.
/// - **Written.** When it does not - a card has no wrong answers to offer a
///   question, a list of facts is not a textbook page - the set goes back to
///   New set with the target mode chosen and the material filled in, and the
///   writer does the rest as it would for any lecture. `sourceText(of:)` and
///   `lecture(of:)` are that material.
///
/// Either way the original is left as it was. The new set sits beside it, in
/// the same folder, with the same subject, pictures and lectures.
///
/// Nothing here imports SwiftUI, so every conversion can be run by the tests.
enum ModeConversion {

    /// The modes a set can be turned into. Narrate is a recording read along
    /// with, and there is nothing to turn into one.
    static let targets: [StudySetKind] = [.mcq, .anki, .osce, .book]

    /// Whether `set` can be turned into `kind` at all - instantly or written.
    static func canTurn(_ set: StudySet, into kind: StudySetKind) -> Bool {
        kind != set.kind && targets.contains(kind)
    }

    /// What the new set is called: "Lupus – Cards".
    static func name(of set: StudySet, as kind: StudySetKind) -> String {
        "\(set.name) \u{2013} \(kind.label)"
    }

    /// The set rearranged into `kind`, or nil when that needs writing.
    ///
    /// Nil also when the rearranging leaves nothing worth having - a deck of
    /// three cards makes no quiz, because each question needs the other cards'
    /// answers as its wrong options.
    static func convert(_ set: StudySet, to kind: StudySetKind) -> StudySet? {
        guard canTurn(set, into: kind) else { return nil }
        var out = StudySet(name: name(of: set, as: kind), subject: set.subject, kind: kind)
        out.folderId = set.folderId
        out.images = set.images
        out.sources = set.sources

        switch (set.kind, kind) {
        case (.mcq, .anki):
            out.cards = set.questions.compactMap(card(from:))
        case (.anki, .mcq):
            // The deck's own answers are the wrong options: nothing invented.
            // Three is where AnkiReviewView's own "Quiz me" draws the line.
            let built = QuizFromCards.build(from: set.cards)
            guard built.questions.count >= 3 else { return nil }
            out.questions = built.questions
        case (.osce, .anki):
            out.cards = set.osceChecklists.flatMap(cards(from:))
        default:
            return nil
        }
        return out.itemCount > 0 ? out : nil
    }

    // MARK: instant, one item at a time

    /// A question as a card: the stem on the front, the right answer on the
    /// back, the explanation as the card's "why".
    static func card(from question: MCQQuestion) -> AnkiCard? {
        guard let answer = rightAnswer(of: question) else { return nil }
        return AnkiCard(type: .qa,
                        front: question.stem.trimmingCharacters(in: .whitespacesAndNewlines),
                        bullets: [answer],
                        why: question.explanation.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: question.source)
    }

    /// A station as cards that drill its order: one card per step, asking
    /// what comes after the one before it. The order is what an examiner
    /// marks, and it is the part that slips.
    static func cards(from station: OsceChecklist) -> [AnkiCard] {
        let steps = station.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = station.title.trimmingCharacters(in: .whitespaces)
        return steps.indices.map { i -> AnkiCard in
            let front = i == 0
                ? "\(title): what is the first step?"
                : "\(title): what comes after \u{201C}\(steps[i - 1])\u{201D}?"
            return AnkiCard(type: .qa, front: front, bullets: [steps[i]],
                            why: "Step \(i + 1) of \(steps.count).")
        }
    }

    private static func rightAnswer(of question: MCQQuestion) -> String? {
        guard question.options.indices.contains(question.correctIndex) else { return nil }
        let answer = question.options[question.correctIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? nil : answer
    }

    // MARK: material for the writer

    /// The lecture the set was made from, if it kept one with any words in
    /// it. Writing from the lecture beats writing from the set: the set is
    /// already a selection of it.
    static func lecture(of set: StudySet) -> SourceDoc? {
        set.sources.first { doc in doc.pages.contains { !$0.isBlank } }
    }

    /// The set's own content as plain text, for the writer to work from when
    /// there is no lecture - every stem with its answer and explanation, every
    /// card, every page.
    static func sourceText(of set: StudySet) -> String {
        var parts: [String] = []
        switch set.kind {
        case .mcq:
            parts = set.questions.map { q -> String in
                var lines = [q.stem]
                if let answer = rightAnswer(of: q) { lines.append("Answer: \(answer)") }
                if !q.explanation.isEmpty { lines.append(q.explanation) }
                return lines.joined(separator: "\n")
            }
        case .anki:
            parts = set.cards.compactMap { c -> String? in
                switch c.type {
                case .qa:
                    return ([c.front] + c.bullets.map { "- " + $0 } + [c.why])
                        .filter { !$0.isEmpty }.joined(separator: "\n")
                case .cloze:
                    return [CardQuality.clozeBare(c.clozeText), c.why]
                        .filter { !$0.isEmpty }.joined(separator: "\n")
                case .occlusion:
                    return nil
                }
            }
        case .book:
            parts = [set.bookMarkdown]
        case .osce:
            parts = set.osceChecklists.map { station -> String in
                (["## " + station.title] + station.steps.map { "- " + $0 }).joined(separator: "\n")
            }
        case .narrate:
            parts = [set.narrateSegments.map(\.text).joined(separator: " ")]
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
