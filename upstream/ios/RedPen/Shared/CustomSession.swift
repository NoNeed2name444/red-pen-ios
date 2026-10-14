import Foundation

/// A study session built to order - Anki's filtered deck: "the cards I got
/// wrong this week, cardiology", "everything the accuracy engine flagged",
/// "what matches this search".
///
/// Nothing here is saved to the library. The session is a copy taken when it
/// is started, holding the questions and cards with their own ids, so every
/// answer and every rating lands on the item it came from - a filtered deck
/// that reschedules its cards, as Anki's does.
///
/// Pure, like LibrarySearch: the sheet (CustomSessionSheet) gathers what the
/// store knows into a `Context` and asks this what the session holds.
enum CustomSession {

    /// Which kinds of item the session takes.
    enum Include: String, CaseIterable, Identifiable, Sendable {
        case both, questions, cards

        var id: String { rawValue }

        var title: String {
            switch self {
            case .both: return "Both"
            case .questions: return "Questions"
            case .cards: return "Cards"
            }
        }
    }

    /// How the session is sat.
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Every item as a multiple-choice question; cards are turned into
        /// questions with QuizFromCards.
        case quiz
        /// Cards reviewed as cards, rated and rescheduled.
        case review

        var id: String { rawValue }

        var title: String { self == .quiz ? "Quiz" : "Review" }
    }

    struct Filter: Equatable, Sendable {
        /// Words that must be in the item, as the library search reads them.
        var text: String = ""
        var include: Include = .both
        /// Missed within this many days: 7 is "failed this week".
        var failedWithinDays: Int? = nil
        /// A tag or topic: matches the item's tags or its set's (Anki's
        /// `Cardio` or `#AK_Step1::Cardio` - nesting kept, case ignored),
        /// the set's subject, its exam or its name, or a #tag in the item's
        /// own text.
        var tag: String = ""
        /// Only sets filed under this subject.
        var subject: String? = nil
        /// Only cards that are due now.
        var dueOnly: Bool = false
        /// Only items the accuracy engine flagged or asked to check.
        var accuracyFlagged: Bool = false
        /// Only questions the student flagged.
        var myFlags: Bool = false
        /// At most this many items, most recently missed first.
        var limit: Int = 40

        /// Whether anything narrows the library at all. A session of the
        /// whole library is not a filter; the sheet asks for one.
        var narrows: Bool {
            let words: Bool = !text.trimmingCharacters(in: .whitespaces).isEmpty
            let tagged: Bool = !tag.trimmingCharacters(in: .whitespaces).isEmpty
            let flags: Bool = accuracyFlagged || myFlags || dueOnly
            return words || tagged || flags || failedWithinDays != nil || subject != nil
        }
    }

    /// A card's standing in the schedule, as far as a filter cares.
    struct CardState: Sendable {
        var due: Date
        var lapses: Int
        var ratedAt: Date
        var suspended: Bool = false
    }

    /// What the store knows about the student's history, copied out.
    struct Context: Sendable {
        /// When each question was last answered wrong (the answer log).
        var lastMissed: [UUID: Date] = [:]
        var cards: [UUID: CardState] = [:]
        /// Items the accuracy engine graded Flagged or Check this.
        var accuracyFlagged: Set<UUID> = []
        /// Questions the student flagged.
        var flagged: Set<UUID> = []
        var now: Date = Date()
    }

    /// One item that passed, with the set it lives in.
    struct Pick: Sendable {
        var setID: UUID
        var question: MCQQuestion? = nil
        var card: AnkiCard? = nil
        /// When it was last missed, for ordering; nil when never.
        var missed: Date? = nil
    }

    struct Plan: Sendable {
        var questions: [Pick] = []
        var cards: [Pick] = []

        var count: Int { questions.count + cards.count }
        var isEmpty: Bool { count == 0 }
    }

    // MARK: choosing

    /// The items that pass `filter`, most recently missed first, then in
    /// library order; each item once, however many sets hold a copy.
    static func plan(sets: [StudySet], filter: Filter, context: Context) -> Plan {
        let words: String = LibrarySearch.fold(filter.text.trimmingCharacters(in: .whitespaces))
        let wordList: [String] = words.split(separator: " ").map(String.init)
        let typed: String = LibrarySearch.fold(filter.tag.trimmingCharacters(in: .whitespaces))
        let tag: String = typed.hasPrefix("#") ? String(typed.dropFirst()) : typed
        // the tag as tags are stored, for CardTags (which ignores case and "#")
        let wanted: [String] = CardTags.normalized(filter.tag).map { [$0] } ?? []
        let since: Date? = filter.failedWithinDays.map { days in
            context.now.addingTimeInterval(-Double(days) * 86_400)
        }
        var plan = Plan()
        var seen: Set<UUID> = []
        for set in sets {
            if let subject = filter.subject, subjectName(set) != subject { continue }
            let setTagged: Bool = tag.isEmpty || setMatches(set, tag: tag)
                || (!wanted.isEmpty && CardTags.matches(set.tags, wanted: wanted))
            if filter.include != .cards && set.kind == .mcq {
                for q in set.questions where !seen.contains(q.id) {
                    let text: String = q.stem + "\n" + q.options.joined(separator: "\n") + "\n" + q.explanation
                    let tagged: Bool = setTagged || CardTags.matches(q.tags, wanted: wanted)
                    guard passes(text, id: q.id, words: words, wordList: wordList, tag: tag,
                                 setTagged: tagged, filter: filter, context: context) else { continue }
                    let missed: Date? = context.lastMissed[q.id]
                    if let since {
                        guard let missed, missed >= since else { continue }
                    }
                    if filter.dueOnly { continue }
                    seen.insert(q.id)
                    plan.questions.append(Pick(setID: set.id, question: q, missed: missed))
                }
            }
            if filter.include != .questions && set.kind == .anki {
                for c in set.cards where !seen.contains(c.id) {
                    let text: String = LibrarySearch.cardTitle(c) + "\n" + c.bullets.joined(separator: "\n") + "\n" + c.why
                    let tagged: Bool = setTagged || CardTags.matches(c.tags, wanted: wanted)
                    guard passes(text, id: c.id, words: words, wordList: wordList, tag: tag,
                                 setTagged: tagged, filter: filter, context: context) else { continue }
                    let state: CardState? = context.cards[c.id]
                    if state?.suspended == true { continue }
                    if filter.myFlags { continue }
                    if filter.dueOnly {
                        guard let state, state.due <= context.now else { continue }
                    }
                    var missed: Date? = nil
                    if let since {
                        guard let state, state.lapses > 0, state.ratedAt >= since else { continue }
                        missed = state.ratedAt
                    }
                    seen.insert(c.id)
                    plan.cards.append(Pick(setID: set.id, card: c, missed: missed))
                }
            }
        }
        return trimmed(plan, to: filter.limit)
    }

    private static func passes(_ text: String, id: UUID, words: String, wordList: [String], tag: String,
                               setTagged: Bool, filter: Filter, context: Context) -> Bool {
        if filter.accuracyFlagged && !context.accuracyFlagged.contains(id) { return false }
        if filter.myFlags && !context.flagged.contains(id) { return false }
        let folded: String? = (words.isEmpty && setTagged) ? nil : LibrarySearch.fold(text)
        if !words.isEmpty, let folded {
            guard LibrarySearch.matches(folded, needle: words, words: wordList) else { return false }
        }
        if !setTagged, let folded {
            guard folded.contains("#" + tag) else { return false }
        }
        return true
    }

    /// The set's subject, name or exam holds the tag; a leading "#" is
    /// optional.
    static func setMatches(_ set: StudySet, tag: String) -> Bool {
        let bare: String = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        guard !bare.isEmpty else { return true }
        let about: String = LibrarySearch.fold(set.subject + "\n" + set.name + "\n" + (set.exam ?? ""))
        return about.contains(bare)
    }

    /// A set's subject as the Progress screen groups it: blank is "General".
    static func subjectName(_ set: StudySet) -> String {
        let s: String = set.subject.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "General" : s
    }

    /// The subjects that hold questions or cards, for the sheet's picker.
    static func subjects(in sets: [StudySet]) -> [String] {
        let studied: [StudySet] = sets.filter { $0.kind == .mcq || $0.kind == .anki }
        let names: Set<String> = Set(studied.map { subjectName($0) })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Most recently missed first, then as found; the cap shared between
    /// questions and cards in proportion, so neither crowds the other out.
    static func trimmed(_ plan: Plan, to limit: Int) -> Plan {
        let cap: Int = max(1, limit)
        var out = Plan(questions: ordered(plan.questions), cards: ordered(plan.cards))
        guard out.count > cap else { return out }
        let share: Double = Double(out.questions.count) / Double(out.count)
        var keepQ: Int = Int((Double(cap) * share).rounded())
        keepQ = min(out.questions.count, max(out.questions.isEmpty ? 0 : 1, keepQ))
        let keepC: Int = min(out.cards.count, cap - keepQ)
        out.questions = Array(out.questions.prefix(keepQ))
        out.cards = Array(out.cards.prefix(keepC))
        return out
    }

    private static func ordered(_ picks: [Pick]) -> [Pick] {
        let indexed: [(Int, Pick)] = Array(picks.enumerated())
        let sorted: [(Int, Pick)] = indexed.sorted { a, b in
            let da: Date = a.1.missed ?? .distantPast
            let db: Date = b.1.missed ?? .distantPast
            if da != db { return da > db }
            return a.0 < b.0
        }
        return sorted.map { $0.1 }
    }

    // MARK: sitting it

    /// The session as a quiz: its questions as they are, and its cards
    /// turned into questions whose wrong answers come from the cards' own
    /// decks (a handful of filtered cards cannot supply four each).
    /// Returns the set and how many cards could not be made into a question.
    static func quiz(_ plan: Plan, sets: [StudySet], name: String, seed: UInt64 = 0) -> (set: StudySet, skipped: Int) {
        var out = StudySet(name: name, subject: "Custom", kind: .mcq)
        let byID: [UUID: StudySet] = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var bases: [UUID: Int] = [:]
        for pick in plan.questions {
            guard var q = pick.question else { continue }
            q.imageIndex = remap(q.imageIndex, from: byID[pick.setID], into: &out, bases: &bases)
            out.questions.append(q)
        }
        let cards: [AnkiCard] = plan.cards.compactMap { $0.card }
        var skipped: Int = 0
        if !cards.isEmpty {
            let deckIDs: Set<UUID> = Set(plan.cards.map { $0.setID })
            let pool: [AnkiCard] = sets.filter { deckIDs.contains($0.id) }.flatMap { $0.cards }
            let built = QuizFromCards.build(from: cards, distractorsFrom: pool, seed: seed)
            out.questions.append(contentsOf: built.questions)
            skipped = built.skipped.count
        }
        return (out, skipped)
    }

    /// The session as a deck to review: the cards themselves, ids kept, so
    /// ratings reschedule them where they live.
    static func deck(_ plan: Plan, sets: [StudySet], name: String) -> StudySet {
        var out = StudySet(name: name, subject: "Custom", kind: .anki)
        let byID: [UUID: StudySet] = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var bases: [UUID: Int] = [:]
        for pick in plan.cards {
            guard var c = pick.card else { continue }
            c.imageIndex = remap(c.imageIndex, from: byID[pick.setID], into: &out, bases: &bases)
            out.cards.append(c)
        }
        return out
    }

    /// An item's picture index in the session: the source set's pictures are
    /// copied in once, the first time one of its items needs one.
    static func remap(_ index: Int?, from set: StudySet?, into out: inout StudySet,
                      bases: inout [UUID: Int]) -> Int? {
        guard let index, let set, set.images.indices.contains(index) else { return nil }
        if let base = bases[set.id] { return base + index }
        let base: Int = out.images.count
        out.images.append(contentsOf: set.images)
        bases[set.id] = base
        return base + index
    }

    /// "Missed this week · Cardiology · 24 items".
    static func title(for filter: Filter) -> String {
        var parts: [String] = []
        if filter.failedWithinDays == 7 { parts.append("Missed this week") }
        else if let d = filter.failedWithinDays { parts.append("Missed in \(d) days") }
        if filter.accuracyFlagged { parts.append("Flagged for accuracy") }
        if filter.myFlags { parts.append("My flags") }
        if filter.dueOnly { parts.append("Due") }
        if let s = filter.subject { parts.append(s) }
        let tag: String = filter.tag.trimmingCharacters(in: .whitespaces)
        if !tag.isEmpty { parts.append(tag.hasPrefix("#") ? tag : "#" + tag) }
        let words: String = filter.text.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { parts.append("\u{201C}" + words + "\u{201D}") }
        return parts.isEmpty ? "Custom session" : parts.joined(separator: " \u{00B7} ")
    }
}
