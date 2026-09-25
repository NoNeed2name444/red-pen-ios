import Foundation

/// Search that finds the item, not just the set it is in.
///
/// The library's search used to list the sets whose questions or cards held
/// the words, and leave the student to find the question inside. This keeps
/// an index of every question, card, note and set - built once, off the main
/// thread, whenever the library changes - so a search can list the matching
/// items themselves, each with the phrase that matched marked, and a tap can
/// go straight to it.
///
/// Pure Foundation, with no view and no store in it, so it runs (and is
/// tested) anywhere. The view model that debounces typing and hops threads
/// is LibrarySearchModel, beside the library.
enum LibrarySearch {

    /// What the search looks through: everything, or one kind of thing.
    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case all, questions, cards, notes, lectures

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .questions: return "Questions"
            case .cards: return "Cards"
            case .notes: return "Notes"
            case .lectures: return "Lectures"
            }
        }

        func admits(_ kind: Kind) -> Bool {
            switch self {
            case .all: return true
            case .questions: return kind == .question
            case .cards: return kind == .card
            case .notes: return kind == .note
            case .lectures: return kind == .lecture
            }
        }
    }

    enum Kind: String, Sendable {
        case set, question, card, note, lecture

        var label: String {
            switch self {
            case .set: return "Set"
            case .question: return "Question"
            case .card: return "Card"
            case .note: return "Note"
            case .lecture: return "Lecture"
            }
        }

        var symbol: String {
            switch self {
            case .set: return "square.stack"
            case .question: return "list.bullet.rectangle"
            case .card: return "rectangle.on.rectangle"
            case .note: return "lightbulb"
            case .lecture: return "doc.richtext"
            }
        }
    }

    /// A note as the index reads it. The notes store is not touched here -
    /// the caller copies out what is needed - so this file stays free of it.
    struct NoteText: Sendable {
        var id: UUID
        var title: String
        var body: String
        var tags: [String] = []
    }

    /// One searchable thing.
    struct Entry: Sendable {
        var kind: Kind
        var setID: UUID?
        var itemID: UUID?
        /// What the result shows first: a stem, a card's front, a note's
        /// title, a set's name.
        var title: String
        /// The rest of what can match: options, answers, the reasoning, a
        /// note's body, a set's subject.
        var detail: String
        var setName: String
        /// Folded once when the index is built, so a keystroke compares
        /// plain lower-case text rather than folding the whole library again.
        /// Holds the tags' words too, so "cardio" finds a card tagged Cardio.
        var folded: String
        /// The item's own tags with its set's (a set's tag covers every card
        /// in it), for `#tag` and `tag:x` in the search (CardTags).
        var tags: [String] = []
    }

    /// A lecture a set was made from, searched page by page with
    /// SourceSearch when asked for.
    struct Lecture: Sendable {
        var setID: UUID
        var setName: String
        var source: SourceDoc
    }

    struct Index: Sendable {
        var entries: [Entry] = []
        var lectures: [Lecture] = []

        var isEmpty: Bool { entries.isEmpty && lectures.isEmpty }
    }

    /// One result, with the text to show and where in it the match is.
    struct Hit: Identifiable, Hashable, Sendable {
        var kind: Kind
        var setID: UUID?
        var itemID: UUID?
        /// The page of a lecture hit; nil for everything else.
        var page: Int?
        var snippet: String
        /// Where the match sits in `snippet`, in Characters.
        var range: Range<Int>
        var setName: String
        /// For a lecture: its name. Otherwise empty.
        var sourceName: String = ""

        var id: String {
            let item: String = itemID?.uuidString ?? setID?.uuidString ?? sourceName
            let at: String = page.map { "p\($0)" } ?? ""
            return kind.rawValue + ":" + item + at + ":" + String(range.lowerBound)
        }
    }

    struct Results: Equatable, Sendable {
        var query: String = ""
        var scope: Scope = .all
        /// Sets, in order: the ones whose name or subject matched first, then
        /// those that only hold a matching item.
        var sets: [UUID] = []
        /// Questions, cards, notes and lecture pages, capped.
        var items: [Hit] = []
        /// True when there were more items than the cap.
        var more: Bool = false

        var isEmpty: Bool { sets.isEmpty && items.isEmpty }
    }

    /// Items at most, the "first 50".
    static let itemLimit = 50
    /// Text each side of a match in a snippet.
    static let context = 48

    // MARK: building

    static func build(sets: [StudySet], notes: [NoteText]) -> Index {
        var index = Index()
        for set in sets {
            appendEntries(of: set, to: &index.entries)
            for source in set.sources where !source.pages.isEmpty {
                index.lectures.append(Lecture(setID: set.id, setName: set.name, source: source))
            }
        }
        for note in notes {
            let tags: String = note.tags.joined(separator: " ")
            let detail: String = note.body + "\n" + tags
            index.entries.append(entry(.note, set: nil, item: note.id, title: note.title,
                                       detail: detail, setName: "Ideas", tags: note.tags))
        }
        return index
    }

    private static func appendEntries(of set: StudySet, to entries: inout [Entry]) {
        let about: String = set.subject + "\n" + (set.exam ?? "")
        let setTags: [String] = set.tags ?? []
        entries.append(entry(.set, set: set.id, item: nil, title: set.name, detail: about, setName: set.name,
                             tags: setTags))
        for q in set.questions {
            let detail: String = q.options.joined(separator: "\n") + "\n" + q.explanation
            entries.append(entry(.question, set: set.id, item: q.id, title: q.stem,
                                 detail: detail, setName: set.name,
                                 tags: CardTags.combined(q.tags, set.tags)))
        }
        for c in set.cards {
            let title: String = cardTitle(c)
            let detail: String = c.bullets.joined(separator: "\n") + "\n" + c.why
            entries.append(entry(.card, set: set.id, item: c.id, title: title,
                                 detail: detail, setName: set.name,
                                 tags: CardTags.combined(c.tags, set.tags)))
        }
        for c in set.qaCards {
            let detail: String = c.answer.joined(separator: "\n") + "\n" + c.topic
            entries.append(entry(.card, set: set.id, item: c.id, title: c.stem,
                                 detail: detail, setName: set.name, tags: setTags))
        }
    }

    private static func entry(_ kind: Kind, set: UUID?, item: UUID?, title: String,
                              detail: String, setName: String, tags: [String] = []) -> Entry {
        // "#AK_Step1::Cardio" searchable as its words: AK, Step1, Cardio
        let tagWords: String = tags.map(tagText).joined(separator: " ")
        let both: String = title + "\n" + detail + "\n" + tagWords
        return Entry(kind: kind, setID: set, itemID: item, title: title, detail: detail,
                     setName: setName, folded: fold(both), tags: tags)
    }

    /// A tag as words: "#AK_Step1::Cardio" reads "AK Step1 Cardio".
    static func tagText(_ tag: String) -> String {
        let spaced: String = tag.replacingOccurrences(of: "::", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "#", with: "")
        return spaced
    }

    /// A card as it reads on its front: a cloze with its gaps filled in
    /// ("{{c1::Warfarin}}" reads "Warfarin"), so a search for the answer
    /// finds it and the snippet reads as a sentence.
    static func cardTitle(_ card: AnkiCard) -> String {
        if card.type == .cloze { return clozeBare(card.clozeText) }
        return card.displayFront
    }

    /// "{{c1::Warfarin::drug}} needs INR" -> "Warfarin needs INR".
    static func clozeBare(_ text: String) -> String {
        var out: String = ""
        var rest: Substring = Substring(text)
        while let open = rest.range(of: "{{") {
            out += rest[rest.startIndex..<open.lowerBound]
            let after: Substring = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else {
                out += rest[open.lowerBound...]
                return out
            }
            let inside: Substring = after[after.startIndex..<close.lowerBound]
            let parts: [Substring] = inside.components(separatedBy: "::").map { Substring($0) }
            out += parts.count >= 2 ? parts[1] : inside
            rest = after[close.upperBound...]
        }
        out += rest
        return out
    }

    // MARK: text

    /// Lower-cased and without accents: "Œdème" and "oedeme" alike.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The words of a text, folded, for anything else that indexes the
    /// library the same way (Spotlight). Two letters or more.
    static func tokens(_ text: String) -> [String] {
        let words: [String] = fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.filter { $0.count >= 2 }
    }

    /// The first place `needle` appears in `text`, ignoring case and accents.
    static func find(_ needle: String, in text: String) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return text.range(of: needle, options: options)
    }

    /// Text around a match, on one line, and where the match is inside it.
    static func snippet(of text: String, around match: Range<String.Index>,
                        context: Int = LibrarySearch.context) -> (String, Range<Int>) {
        let before: String.Index = text.index(match.lowerBound, offsetBy: -context,
                                              limitedBy: text.startIndex) ?? text.startIndex
        let after: String.Index = text.index(match.upperBound, offsetBy: context,
                                             limitedBy: text.endIndex) ?? text.endIndex
        let lead: String = flatten(String(text[before..<match.lowerBound]))
        let body: String = flatten(String(text[match]))
        let tail: String = flatten(String(text[match.upperBound..<after]))
        let front: String = before > text.startIndex ? "\u{2026}" : ""
        let back: String = after < text.endIndex ? "\u{2026}" : ""
        let head: String = front + trimLeading(lead)
        let end: String = trimTrailing(tail) + back
        let start: Int = head.count
        let line: String = head + body + end
        return (line, start..<(start + body.count))
    }

    private static func flatten(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private static func trimLeading(_ text: String) -> String {
        String(text.drop { $0 == " " })
    }

    private static func trimTrailing(_ text: String) -> String {
        var out: String = text
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    // MARK: searching

    /// Every match for `query` within `scope`.
    ///
    /// A phrase first: "nephrotic syndrome" finds those two words together.
    /// When the phrase is nowhere, every word anywhere in the item will do,
    /// and the first word is the one marked. `#cardio` or `tag:cardio` asks
    /// for a tag (CardTags.query): only items carrying it, or filed under
    /// it, are listed - with the rest of the text still to be matched.
    static func search(_ query: String, in index: Index, scope: Scope,
                       limit: Int = LibrarySearch.itemLimit) -> Results {
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = Results(query: trimmed, scope: scope)
        guard !trimmed.isEmpty else { return out }
        let asked = CardTags.query(trimmed)
        let wanted: [String] = asked.tags
        let phrase: String = asked.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle: String = fold(phrase)
        let words: [String] = needle.split(separator: " ").map(String.init)

        var named: [UUID] = []
        var holding: [UUID] = []
        var seenSets: Set<UUID> = []
        var strong: [Hit] = []
        var weak: [Hit] = []
        var total: Int = 0
        // one letter matches almost everything; sets only until there are
        // two (a tag asked for is specific enough on its own)
        let itemsToo: Bool = phrase.count >= 2 || !wanted.isEmpty

        for entry in index.entries {
            guard CardTags.matches(entry.tags, wanted: wanted) else { continue }
            guard phrase.isEmpty || matches(entry.folded, needle: needle, words: words) else { continue }
            if entry.kind == .set {
                if let id = entry.setID, seenSets.insert(id).inserted { named.append(id) }
                continue
            }
            guard itemsToo else { continue }
            if let id = entry.setID, !seenSets.contains(id) { holding.append(id) }
            guard scope.admits(entry.kind) else { continue }
            total += 1
            guard strong.count + weak.count < limit else { continue }
            let (hit, inTitle) = makeHit(entry, phrase: phrase, words: words)
            if inTitle { strong.append(hit) } else { weak.append(hit) }
        }
        var ordered: [UUID] = named
        var added: Set<UUID> = Set(named)
        for id in holding where added.insert(id).inserted { ordered.append(id) }
        out.sets = scope == .all ? ordered : []

        var items: [Hit] = strong + weak
        // lecture pages carry no tags: only a plain search reaches them
        if itemsToo && wanted.isEmpty && (scope == .all || scope == .lectures) {
            let room: Int = max(0, limit - items.count)
            let pages: [Hit] = lectureHits(phrase, in: index.lectures, limit: room + 1)
            total += pages.count
            items += pages.prefix(room)
        }
        out.items = Array(items.prefix(limit))
        out.more = total > out.items.count
        return out
    }

    static func matches(_ folded: String, needle: String, words: [String]) -> Bool {
        if folded.contains(needle) { return true }
        guard words.count > 1 else { return false }
        return words.allSatisfy { folded.contains($0) }
    }

    /// The hit for an entry, and whether the match is in its title (a stem,
    /// a front) rather than further in - those are listed first.
    private static func makeHit(_ entry: Entry, phrase: String, words: [String]) -> (Hit, Bool) {
        let first: String = words.first ?? phrase
        let lookFor: [String] = phrase.isEmpty ? [] : [phrase, first]
        for needle in lookFor {
            if let r = find(needle, in: entry.title) {
                return (hit(entry, text: entry.title, match: r), true)
            }
            if let r = find(needle, in: entry.detail) {
                return (hit(entry, text: entry.detail, match: r), false)
            }
        }
        // matched only across the join of title and detail: show the title
        let whole: String = entry.title
        let empty: Range<Int> = 0..<0
        let plain = Hit(kind: entry.kind, setID: entry.setID, itemID: entry.itemID, page: nil,
                        snippet: String(whole.prefix(LibrarySearch.context * 2)), range: empty,
                        setName: entry.setName)
        return (plain, true)
    }

    private static func hit(_ entry: Entry, text: String, match: Range<String.Index>) -> Hit {
        let (line, range) = snippet(of: text, around: match)
        return Hit(kind: entry.kind, setID: entry.setID, itemID: entry.itemID, page: nil,
                   snippet: line, range: range, setName: entry.setName)
    }

    /// One hit per lecture page, in reading order, through SourceSearch so
    /// the lecture reader and this agree about what matched.
    static func lectureHits(_ phrase: String, in lectures: [Lecture], limit: Int) -> [Hit] {
        var out: [Hit] = []
        for lecture in lectures {
            guard out.count < limit else { break }
            let found: [SourceSearch.Hit] = SourceSearch.hits(for: phrase, in: lecture.source.pages,
                                                              context: LibrarySearch.context, limit: 200)
            var pages: Set<Int> = []
            for h in found where pages.insert(h.page).inserted {
                let item = Hit(kind: .lecture, setID: lecture.setID, itemID: lecture.source.id,
                               page: h.page, snippet: h.snippet, range: h.range,
                               setName: lecture.setName, sourceName: lecture.source.name)
                out.append(item)
                if out.count >= limit { break }
            }
        }
        return out
    }

    // MARK: opening

    /// A copy of `set` that opens on the question `id` and carries on
    /// through the rest in the set's own order, wrapping round - "open that
    /// question inside its set". Nil when the question is not in it.
    static func opening(_ set: StudySet, atQuestion id: UUID) -> StudySet? {
        guard let at = set.questions.firstIndex(where: { $0.id == id }) else { return nil }
        var out: StudySet = set
        let tail: ArraySlice<MCQQuestion> = set.questions[at...]
        let head: ArraySlice<MCQQuestion> = set.questions[..<at]
        out.questions = Array(tail) + Array(head)
        return out
    }
}
