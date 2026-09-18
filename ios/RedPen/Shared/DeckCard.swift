import Foundation

/// One printed card: a question on one page, its answer on the next.
///
/// Every mode reduces to this before anything is drawn, so the exporter has one
/// shape to lay out rather than six. What differs between modes is only what
/// counts as a question - a stem and four options in MCQ, the next step of a
/// station in OSCE, a page of the textbook in Book - and that difference is
/// settled here, in code that can be tested, rather than inside a drawing
/// routine that cannot.
struct DeckCard: Equatable {
    /// 1-based, and printed on both of its pages.
    var number: Int = 0
    /// The short label the contents index groups by.
    var topic: String
    /// The chip under the title: RECALL, CASE, LIST, MCQ, STEP, PAGE.
    var kindLabel: String
    var question: [DeckBlock]
    var answer: [DeckBlock]
    /// Which picture in the set this card shows, if any.
    var imageIndex: Int?
    /// Where that picture goes once we know what it shows. Decided at export
    /// time, when the picture can actually be read - see ImageSpoiler.
    var imagePlacement: ImageSpoiler.Placement = .question
    /// Where the card came from, printed small under the answer.
    var source: String?
}

/// A line of a card. Deliberately few kinds: a printed card that needs more
/// structure than this is a card that should have been split in two.
enum DeckBlock: Equatable {
    /// Ordinary text, set larger on a question page than on an answer page.
    case text(String)
    /// A bullet. `lead` is the phrase set in the subject's colour before the
    /// rest - the highest-yield part of the line.
    case bullet(lead: String?, text: String)
    /// An MCQ option. `letter` is A, B, C…; `correct` is only ever true on an
    /// answer page, since printing it on the question page would be absurd.
    case option(letter: String, text: String, correct: Bool)
    /// A quieter note: an explanation, a "why", a citation.
    case note(label: String, text: String)
}

enum DeckBuilder {

    /// Whether a mode prints as a flashcard PDF at all.
    ///
    /// Anki does not. Its scheduling is the whole value of the deck and its
    /// occlusion cards are masked pictures; both survive .apkg and neither
    /// survives paper. Kept here, beside the building, so the rule can be
    /// tested and so there is one answer to the question in the app.
    static func printsAsPDF(_ kind: StudySetKind) -> Bool { kind != .anki }

    /// Every card in a set, numbered.
    static func cards(for set: StudySet) -> [DeckCard] {
        var built: [DeckCard]
        switch set.kind {
        case .mcq:     built = mcq(set.questions)
        case .qa:      built = qa(set.qaCards)
        case .osce:    built = osce(set.osceChecklists)
        case .book:    built = book(set.bookMarkdown)
        case .narrate: built = narrate(set.narrateSegments)
        case .anki:    built = anki(set.cards)
        }
        for i in built.indices { built[i].number = i + 1 }
        return built
    }

    // MARK: MCQ

    static func mcq(_ questions: [MCQQuestion]) -> [DeckCard] {
        questions.map { q in
            let letters = q.options.indices.map { letter($0) }
            var answer: [DeckBlock] = []
            for (i, option) in q.options.enumerated() {
                answer.append(.option(letter: letters[i], text: option, correct: i == q.correctIndex))
            }
            if !q.explanation.trimmingCharacters(in: .whitespaces).isEmpty {
                answer.append(.note(label: "Why", text: q.explanation))
            }
            return DeckCard(
                topic: topic(from: q.stem),
                kindLabel: "MCQ",
                question: [.text(q.stem)] + q.options.enumerated().map {
                    .option(letter: letters[$0.offset], text: $0.element, correct: false)
                },
                answer: answer,
                imageIndex: q.imageIndex,
                source: q.source)
        }
    }

    // MARK: Cases

    static func qa(_ cards: [QACard]) -> [DeckCard] {
        cards.map { card in
            DeckCard(topic: card.topic.isEmpty ? topic(from: card.stem) : card.topic,
                     kindLabel: card.type == .case ? "CASE" : "RECALL",
                     question: [.text(card.stem)],
                     answer: card.answer.map { .bullet(lead: nil, text: $0) })
        }
    }

    // MARK: OSCE
    //
    // One card per step, asking what comes next - which is how the station is
    // drilled on screen. The steps already taken are printed on the question
    // page as context, because on paper there is nothing else to remind you
    // where in the station you are.

    static func osce(_ checklists: [OsceChecklist]) -> [DeckCard] {
        var out: [DeckCard] = []
        for checklist in checklists {
            for (i, step) in checklist.steps.enumerated() {
                var question: [DeckBlock] = [
                    .text(i == 0 ? "You are starting this station. What is the first step?"
                                 : "What comes next?")
                ]
                // The last few steps only: the whole station reprinted every
                // time would bury the question.
                let sofar = checklist.steps.prefix(i).suffix(3)
                for done in sofar { question.append(.bullet(lead: nil, text: done)) }
                out.append(DeckCard(topic: checklist.title,
                                    kindLabel: "STEP",
                                    question: question,
                                    answer: [.bullet(lead: "Step \(i + 1)", text: step)]))
            }
        }
        return out
    }

    // MARK: Textbook
    //
    // A textbook is not a set of questions, so printing it as question/answer
    // pairs would be a lie. Each page becomes a card whose question side is the
    // heading - "what is on this page?" is a real recall prompt - and whose
    // answer side is the page.

    static func book(_ markdown: String) -> [DeckCard] {
        BookPages.split(markdown).map { page in
            DeckCard(topic: page.title,
                     kindLabel: "PAGE",
                     question: [.text("What do you remember about \u{201C}\(page.title)\u{201D}?")],
                     answer: blocks(fromMarkdown: page.markdown))
        }
    }

    // MARK: Narrate

    static func narrate(_ segments: [NarrateSegment]) -> [DeckCard] {
        segments.enumerated().map { i, segment in
            DeckCard(topic: "Line \(i + 1)",
                     kindLabel: "LINE",
                     question: [.text("Read this aloud, then check yourself.")],
                     answer: [.text(segment.text)])
        }
    }

    // MARK: Anki
    //
    // Only for completeness: Anki decks export as .apkg, where the scheduling
    // and the occlusion masks survive and a PDF would throw both away.

    static func anki(_ cards: [AnkiCard]) -> [DeckCard] {
        cards.map { card in
            DeckCard(topic: topic(from: card.front),
                     kindLabel: card.type == .occlusion ? "IMAGE" : "RECALL",
                     question: [.text(card.front)],
                     answer: card.bullets.map { .bullet(lead: nil, text: $0) }
                         + (card.why.trimmingCharacters(in: .whitespaces).isEmpty
                            ? [] : [.note(label: "Why", text: card.why)]),
                     imageIndex: card.imageIndex,
                     source: card.source)
        }
    }

    // MARK: helpers

    /// A short label for the contents index, taken from the first few words
    /// when the card has no topic of its own.
    static func topic(from text: String) -> String {
        let cleaned = Highlight.plain(text)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Untitled" }
        let words = cleaned.split(separator: " ").prefix(5)
        var label = words.joined(separator: " ")
        if label.count > 48 { label = String(label.prefix(46)) + "\u{2026}" }
        return label
    }

    static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26,
              let scalar = UnicodeScalar(65 + index) else { return "\(index + 1)" }
        return String(Character(scalar))
    }

    /// Markdown lines as printable blocks, reusing the textbook's own reader so
    /// a page prints the way it reads on screen.
    static func blocks(fromMarkdown markdown: String) -> [DeckBlock] {
        BookPages.blocks(markdown).compactMap { block in
            switch block {
            case .heading(_, let text): return .bullet(lead: text, text: "")
            case .bullet(let text, let marker): return .bullet(lead: marker, text: text)
            case .paragraph(let text): return .text(text)
            case .row(let cells):
                guard !cells.isEmpty else { return nil }
                return .bullet(lead: cells.first,
                               text: cells.dropFirst().joined(separator: " \u{2014} "))
            }
        }
    }
}

/// The contents index: one row per topic, with the cards it covers.
///
/// Grouped by topic rather than listing every card, because a deck of six
/// hundred cards produces an index nobody can use. Consecutive cards on the
/// same topic collapse into a range.
struct DeckIndexRow: Equatable {
    var topic: String
    var first: Int
    var last: Int
    var range: String { first == last ? "\(first)" : "\(first)\u{2013}\(last)" }
}

enum DeckIndex {
    static func rows(_ cards: [DeckCard]) -> [DeckIndexRow] {
        var out: [DeckIndexRow] = []
        for card in cards {
            if var last = out.last, last.topic == card.topic, last.last == card.number - 1 {
                last.last = card.number
                out[out.count - 1] = last
            } else {
                out.append(DeckIndexRow(topic: card.topic, first: card.number, last: card.number))
            }
        }
        return out
    }
}
