import Foundation

// Study Lens: turning a captured question and its answer into something to
// study - a question in a set, a flashcard, a case, an OSCE station, an idea
// note, or a narration script.
//
// Where the app already knows how to turn one mode into another
// (ModeConversion), that is used, so a Lens capture becomes a card exactly as
// a quiz question does. Everything made here is marked as coming from the
// lens: the "Lens" tag where the item has tags, "Study Lens" as its source,
// and the set's own tag - so the accuracy engine, which reads every set in the
// library, checks it like any other new content.
//
// Foundation only; tested in Tests/LensTests.swift.

/// Where a capture can go.
enum LensDestination: String, CaseIterable, Identifiable, Hashable {
    case questions, cards, cases, osce, ideas, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questions: return "Questions"
        case .cards: return "Cards"
        case .cases: return "Cases"
        case .osce: return "OSCE"
        case .ideas: return "Ideas"
        case .audio: return "Audio"
        }
    }

    var detail: String {
        switch self {
        case .questions: return "A multiple-choice question in a set"
        case .cards: return "A flashcard, or a cloze card"
        case .cases: return "A case card to talk through"
        case .osce: return "A station checklist"
        case .ideas: return "A note with the question and why"
        case .audio: return "A script read aloud in Audio"
        }
    }

    var symbol: String {
        switch self {
        case .questions: return "checklist.checked"
        case .cards: return "rectangle.on.rectangle.angled"
        case .cases: return "stethoscope"
        case .osce: return "list.clipboard"
        case .ideas: return "lightbulb"
        case .audio: return "waveform"
        }
    }

    /// The kind of set it goes into; nil for Ideas, which are notes.
    var kind: StudySetKind? {
        switch self {
        case .questions: return .mcq
        case .cards: return .anki
        case .cases: return .qa
        case .osce: return .osce
        case .audio: return .narrate
        case .ideas: return nil
        }
    }

    /// The destination a type goes to first in the picker.
    static func suggested(for type: LensQuestionType) -> LensDestination {
        switch type {
        case .mcq, .bestAnswer, .trueFalse: return .questions
        case .cloze, .shortAnswer, .calculation, .imageLabel: return .cards
        case .clinicalCase: return .cases
        case .osce: return .osce
        }
    }
}

enum LensConversion {

    static let tag: String = "Lens"
    static let source: String = "Study Lens"
    /// The set, folder and hub note captures go to unless another is chosen.
    static let defaultName: String = "Lens captures"

    // MARK: into a set

    /// A new, empty set for a destination: "Lens captures", tagged.
    static func newSet(for destination: LensDestination, name: String = defaultName) -> StudySet? {
        guard let kind = destination.kind else { return nil }
        var set = StudySet(name: name, subject: "General", kind: kind)
        set.tags = [tag]
        return set
    }

    /// `set` with the capture added in its own mode, or nil when the capture
    /// cannot become that mode (a question with nothing to offer as wrong
    /// options cannot be a multiple-choice question).
    static func adding(_ q: DetectedQuestion, _ a: LensAnswer, to set: StudySet) -> StudySet? {
        var out = set
        switch set.kind {
        case .mcq:
            guard let made = question(q, a) else { return nil }
            out.questions.append(made)
        case .anki:
            let made: [AnkiCard] = cards(q, a)
            guard !made.isEmpty else { return nil }
            out.cards.append(contentsOf: made)
        case .qa:
            guard let made = caseCard(q, a, topic: set.subject) else { return nil }
            out.qaCards.append(made)
        case .osce:
            guard let made = station(q, a) else { return nil }
            out.osceChecklists.append(made)
        case .narrate:
            let made: [NarrateSegment] = narration(q, a)
            guard !made.isEmpty else { return nil }
            out.narrateSegments.append(contentsOf: made)
        case .book:
            return nil
        }
        var tags: [String] = out.tags ?? []
        if !tags.contains(tag) { tags.append(tag) }
        out.tags = tags
        return out
    }

    /// Whether a capture can go to a destination at all.
    static func can(_ q: DetectedQuestion, _ a: LensAnswer, goTo destination: LensDestination) -> Bool {
        switch destination {
        case .questions: return question(q, a) != nil
        case .cards: return !cards(q, a).isEmpty
        case .cases: return caseCard(q, a, topic: "General") != nil
        case .osce: return station(q, a) != nil
        case .ideas: return true
        case .audio: return !narration(q, a).isEmpty
        }
    }

    // MARK: Questions

    /// A multiple-choice question. The printed options when there were any;
    /// True and False for a true/false statement; otherwise the answer and
    /// the model's plausible wrong answers, in a fixed shuffled order.
    static func question(_ q: DetectedQuestion, _ a: LensAnswer) -> MCQQuestion? {
        var options: [String] = []
        var key: Int = -1
        switch q.type {
        case .mcq, .bestAnswer:
            options = q.options.map(\.text)
            key = a.correctIndex ?? -1
        case .trueFalse:
            guard let verdict = a.verdict else { return nil }
            options = ["True", "False"]
            key = verdict ? 0 : 1
        default:
            let right: String = a.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let wrong: [String] = uniqueDistractors(a.distractors, excluding: right)
            guard !right.isEmpty, wrong.count >= 2 else { return nil }
            let slot: Int = seededSlot(q.stem, count: wrong.count + 1)
            options = wrong
            options.insert(right, at: min(slot, options.count))
            key = min(slot, options.count - 1)
        }
        guard options.indices.contains(key) else { return nil }
        var stem: String = q.stem
        if q.type == .trueFalse && !stem.lowercased().contains("true") { stem = "True or false: " + stem }
        return MCQQuestion(stem: stem, options: options, correctIndex: key,
                           explanation: explanation(q, a), source: source,
                           differential: a.differential, tags: [tag])
    }

    /// The explanation as it is kept with a question: why the answer is
    /// right, then a sentence on each wrong option, then anything else the
    /// model gave (steps, the corrected statement).
    static func explanation(_ q: DetectedQuestion, _ a: LensAnswer) -> String {
        var parts: [String] = []
        if !a.explanation.isEmpty { parts.append(a.explanation) }
        if !a.correction.isEmpty { parts.append("Correctly: " + a.correction) }
        if !a.steps.isEmpty && q.type == .calculation { parts.append("Working: " + a.steps.joined(separator: "; ")) }
        if q.type.hasOptions {
            for (i, note) in a.optionNotes.enumerated() where i != a.correctIndex && !note.isEmpty {
                let option: String = q.options.indices.contains(i) ? q.options[i].text : LensHash.letter(i)
                parts.append(option + " is not the answer: " + note)
            }
        }
        if !a.nextStep.isEmpty { parts.append("Next step: " + a.nextStep) }
        return parts.joined(separator: " ")
    }

    /// Where the right answer goes among the wrong ones: fixed for the same
    /// question, so saving it twice gives the same order.
    static func seededSlot(_ text: String, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let hash: UInt64 = UInt64(LensHash.fnv(text), radix: 16) ?? 0
        let slot: UInt64 = hash % UInt64(count)
        return Int(slot)
    }

    static func uniqueDistractors(_ list: [String], excluding right: String) -> [String] {
        var seen: Set<String> = [right.lowercased()]
        var out: [String] = []
        for item in list {
            let t: String = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower: String = t.lowercased()
            guard !t.isEmpty, !seen.contains(lower) else { continue }
            seen.insert(lower)
            out.append(t)
        }
        return Array(out.prefix(4))
    }

    // MARK: Cards

    /// Flashcards: a cloze card for a fill-in-the-blank, the station's
    /// order drilled one step a card for an OSCE instruction, and a question
    /// and answer card for everything else.
    static func cards(_ q: DetectedQuestion, _ a: LensAnswer) -> [AnkiCard] {
        var made: [AnkiCard] = []
        switch q.type {
        case .mcq, .bestAnswer:
            if let mcq = question(q, a), let card = ModeConversion.card(from: mcq) { made = [card] }
        case .cloze:
            if let card = clozeCard(q, a) { made = [card] }
        case .osce:
            if let station = station(q, a) { made = ModeConversion.cards(from: station) }
        case .trueFalse:
            guard let verdict = a.verdict else { return [] }
            let fix: String = a.correction.isEmpty ? "" : " \u{2013} " + a.correction
            let back: String = verdict ? "True" : "False" + fix
            made = [AnkiCard(type: .qa, front: "True or false: " + q.stem, bullets: [back], why: a.explanation)]
        case .clinicalCase:
            var bullets: [String] = []
            if !a.diagnosis.isEmpty { bullets.append("**" + a.diagnosis + "**") }
            if !a.nextStep.isEmpty { bullets.append("Next: " + a.nextStep) }
            guard !bullets.isEmpty else { return [] }
            made = [AnkiCard(type: .qa, front: q.stem, bullets: bullets, why: a.explanation)]
        case .calculation:
            guard !a.answer.isEmpty else { return [] }
            let why: String = a.steps.isEmpty ? a.explanation : a.steps.joined(separator: " \u{2192} ")
            made = [AnkiCard(type: .qa, front: q.stem, bullets: ["**" + a.answer + "**"], why: why)]
        case .shortAnswer, .imageLabel:
            guard !a.answer.isEmpty else { return [] }
            let bullets: [String] = ["**" + a.answer + "**"] + Array(a.keyPoints.prefix(3))
            made = [AnkiCard(type: .qa, front: q.stem, bullets: bullets, why: a.explanation)]
        }
        return made.map { card -> AnkiCard in
            var c = card
            c.source = source
            c.tags = [tag]
            if c.why.count > 400 { c.why = String(c.why.prefix(400)) + "\u{2026}" }
            return c
        }
    }

    /// A cloze card: the blank written as `{{c1::answer}}`. When the stem's
    /// blank cannot be found, the answer is marked inside the filled
    /// sentence instead; nil when neither works.
    static func clozeCard(_ q: DetectedQuestion, _ a: LensAnswer) -> AnkiCard? {
        let answer: String = a.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return nil }
        let marked: String = "{{c1::" + answer + "}}"
        let fromStem: String = LensAnswerParser.fill(q.stem, with: marked)
        var text: String = fromStem
        if fromStem == q.stem {
            guard let range = a.filled.range(of: answer, options: .caseInsensitive) else { return nil }
            text = a.filled.replacingCharacters(in: range, with: marked)
        }
        return AnkiCard(type: .cloze, clozeText: text, why: a.explanation)
    }

    // MARK: Cases

    static func caseCard(_ q: DetectedQuestion, _ a: LensAnswer, topic: String) -> QACard? {
        let cleanTopic: String = topic == "General" ? "" : topic
        switch q.type {
        case .mcq, .bestAnswer:
            guard let mcq = question(q, a) else { return nil }
            return ModeConversion.caseCard(from: mcq, topic: topic)
        case .clinicalCase:
            var points: [String] = []
            if !a.diagnosis.isEmpty { points.append("Most likely: **" + a.diagnosis + "**") }
            if !a.nextStep.isEmpty { points.append("Next step: " + a.nextStep) }
            if !a.explanation.isEmpty { points.append(a.explanation) }
            guard !points.isEmpty else { return nil }
            var card = QACard(topic: cleanTopic, type: .case, stem: q.stem, answer: points)
            card.differential = a.differential
            return card
        case .osce:
            guard let s = station(q, a) else { return nil }
            return ModeConversion.caseCard(from: s)
        default:
            let right: String = a.answer.isEmpty ? a.verdict.map { $0 ? "True" : "False" } ?? "" : a.answer
            guard !right.isEmpty else { return nil }
            var points: [String] = ["**" + right + "**"]
            if !a.explanation.isEmpty { points.append(a.explanation) }
            points.append(contentsOf: a.steps)
            return QACard(topic: cleanTopic, type: .recall, stem: q.stem, answer: points)
        }
    }

    // MARK: OSCE

    /// An OSCE station. An OSCE instruction gives its own checklist; any
    /// other question becomes a "talk it through" station built from the
    /// answer's steps or points, when it has at least three.
    static func station(_ q: DetectedQuestion, _ a: LensAnswer) -> OsceChecklist? {
        if q.type == .osce {
            let title: String = a.answer.isEmpty ? LensHash.firstWords(q.stem, count: 8) : a.answer
            return a.steps.isEmpty ? nil : OsceChecklist(title: title, steps: a.steps)
        }
        var steps: [String] = a.steps
        if steps.count < 3 { steps = a.keyPoints }
        if steps.count < 3 { steps = sentences(a.explanation) }
        guard steps.count >= 3 else { return nil }
        let title: String = "Explain: " + LensHash.firstWords(q.stem, count: 7)
        return OsceChecklist(title: title, steps: Array(steps.prefix(15)))
    }

    /// Sentences, cut after ". ", "? " or "! " - but not after a lone
    /// capital ("E. coli") or a number ("2.5").
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current: String = ""
        let chars: [Character] = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            guard ch == "." || ch == "?" || ch == "!" else { continue }
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            guard next == nil || next == " " || next == "\n" else { continue }
            let words: [Substring] = current.split(separator: " ")
            let last: String = words.last.map(String.init) ?? ""
            if ch == "." && last.count == 2 && (last.first?.isUppercase ?? false) { continue }
            let t: String = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(t) }
            current = ""
        }
        let rest: String = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    // MARK: Ideas

    /// A note for the idea dump: the question, the answer and why, linked to
    /// the "Lens captures" hub note by `[[...]]` so every capture sits
    /// together on the board.
    static func note(_ q: DetectedQuestion, _ a: LensAnswer) -> (title: String, body: String) {
        let title: String = LensHash.firstWords(q.stem, count: 10)
        var lines: [String] = ["**" + q.type.title + "** \u{00B7} from [[" + defaultName + "]]", "", q.fullText, ""]
        let answer: String = a.answer.isEmpty ? (a.verdict.map { $0 ? "True" : "False" } ?? "") : a.answer
        if !answer.isEmpty { lines.append("**Answer:** " + answer) }
        if !a.filled.isEmpty { lines.append(a.filled) }
        if !a.correction.isEmpty { lines.append("Correctly: " + a.correction) }
        if !a.nextStep.isEmpty { lines.append("**Next step:** " + a.nextStep) }
        if !a.explanation.isEmpty { lines.append(""); lines.append(a.explanation) }
        if !a.steps.isEmpty {
            lines.append("")
            for (i, step) in a.steps.enumerated() { lines.append("\(i + 1). " + step) }
        }
        let notes: [String] = optionLines(q, a)
        if !notes.isEmpty { lines.append(""); lines.append(contentsOf: notes) }
        if !a.keyPoints.isEmpty {
            lines.append("")
            lines.append(contentsOf: a.keyPoints.map { "- " + $0 })
        }
        return (title, lines.joined(separator: "\n"))
    }

    private static func optionLines(_ q: DetectedQuestion, _ a: LensAnswer) -> [String] {
        var out: [String] = []
        for (i, note) in a.optionNotes.enumerated() where !note.isEmpty && q.options.indices.contains(i) {
            let mark: String = i == a.correctIndex ? "\u{2713} " : "\u{2717} "
            out.append("- " + mark + LensHash.letter(i) + ". " + q.options[i].text + ": " + note)
        }
        return out
    }

    // MARK: Audio

    /// A narration script, one line per spoken phrase: the question, its
    /// options, the answer, then why.
    static func narration(_ q: DetectedQuestion, _ a: LensAnswer) -> [NarrateSegment] {
        var lines: [String] = [q.stem]
        for (i, option) in q.options.enumerated() {
            lines.append("Option " + LensHash.letter(i) + ": " + option.text + ".")
        }
        let answer: String = a.answer.isEmpty ? (a.verdict.map { $0 ? "True" : "False" } ?? "") : a.answer
        if !answer.isEmpty { lines.append("The answer is " + answer + ".") }
        if q.type == .osce || q.type == .calculation {
            for (i, step) in a.steps.enumerated() { lines.append("Step \(i + 1): " + step) }
        }
        lines.append(contentsOf: sentences(a.explanation))
        if !a.nextStep.isEmpty { lines.append("The next step: " + a.nextStep) }
        let kept: [String] = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard kept.count >= 2 else { return [] }
        return kept.map { NarrateSegment(text: $0) }
    }
}
