import Foundation

/// Tags on cards, questions and sets: tidying what is typed, counting what
/// the library holds, and the filter search uses.
///
/// Tags follow Anki's rules, because the biggest source of them is Anki decks
/// (AnKing's `#AK_Step1_v12::#B&B::...`): no spaces inside a tag, `::` nests
/// one tag under another, case is ignored when matching, and asking for a
/// parent tag finds everything filed under it.
///
/// The search hook is `CardTags.query(_:)` - `tag:pharm` or `#pharm` in the
/// search text - with `matches(_:wanted:)` / `tagged(_:with:)` to apply it.
///
/// Foundation only, so it is tested.
enum CardTags {

    /// The longest one tag may be.
    static let maxLength = 120
    /// The most tags one card, question or set keeps.
    static let maxPerItem = 20

    /// A tag as it is stored: trimmed, inner spaces joined with "_", no
    /// empty `::` levels. Nil when nothing is left.
    static func normalized(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace })
        let joined = words.joined(separator: "_")
        let levels = joined.components(separatedBy: "::").filter { !$0.isEmpty }
        let tag = String(levels.joined(separator: "::").prefix(maxLength))
        return tag.isEmpty ? nil : tag
    }

    /// Tags typed in one go - "cardio, pharm renal" - as a list.
    static func parse(_ typed: String) -> [String] {
        let pieces = typed.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        var out: [String] = []
        for piece in pieces {
            // a comma list keeps its spaces as part of each tag; a plain list
            // of words is one tag per word
            let parts: [String] = typed.contains(",") || typed.contains(";")
                ? [piece] : piece.split(separator: " ").map(String.init)
            for part in parts {
                guard let tag = normalized(part), !contains(out, tag) else { continue }
                out.append(tag)
            }
        }
        return Array(out.prefix(maxPerItem))
    }

    /// A list with one more tag, or the same list when it is already there.
    static func adding(_ raw: String, to tags: [String]?) -> [String]? {
        var list = tags ?? []
        for tag in parse(raw) where !contains(list, tag) && list.count < maxPerItem {
            list.append(tag)
        }
        return list.isEmpty ? nil : list
    }

    /// A list without one tag. Nil once none are left, so an untagged item
    /// stores nothing.
    static func removing(_ tag: String, from tags: [String]?) -> [String]? {
        let list = (tags ?? []).filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        return list.isEmpty ? nil : list
    }

    static func contains(_ list: [String], _ tag: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// The last level, for a chip: "#AK_Step1::Cardio" shows as "Cardio".
    static func label(_ tag: String) -> String {
        tag.components(separatedBy: "::").last(where: { !$0.isEmpty }) ?? tag
    }

    // MARK: - search

    /// Search text split into words and wanted tags: `tag:pharm` and
    /// `#pharm` are tags, everything else is text.
    static func query(_ text: String) -> (text: String, tags: [String]) {
        var words: [String] = []
        var tags: [String] = []
        for word in text.split(separator: " ") {
            let lower = word.lowercased()
            if lower.hasPrefix("tag:"), word.count > 4 {
                if let tag = normalized(String(word.dropFirst(4))) { tags.append(tag) }
            } else if word.hasPrefix("#"), word.count > 1 {
                if let tag = normalized(String(word.dropFirst())) { tags.append(tag) }
            } else {
                words.append(String(word))
            }
        }
        return (words.joined(separator: " "), tags)
    }

    /// Whether one tag is the wanted one or filed under it, ignoring case and
    /// a leading "#": `pharm` finds `Pharm` and `pharm::diuretics`, and a
    /// tag written `#AK_Step1` is found by `AK_Step1` too. The wanted tag
    /// may also start at any deeper level, whole levels only: `cardio` finds
    /// AnKing's `#AK_Step1_v12::#B&B::Cardio` (and what is under it), since
    /// nobody types the whole path - but `pharm` never finds `pharmacology`.
    static func tag(_ tag: String, isUnder wanted: String) -> Bool {
        let have = levels(tag)
        let want = levels(wanted)
        guard !want.isEmpty, want.count <= have.count else { return false }
        let last: Int = have.count - want.count
        for start in 0...last where Array(have[start..<(start + want.count)]) == want {
            return true
        }
        return false
    }

    /// A tag's levels, each lower-cased without its leading "#".
    private static func levels(_ tag: String) -> [String] {
        tag.components(separatedBy: "::").map(bare).filter { !$0.isEmpty }
    }

    private static func bare(_ tag: String) -> String {
        var t = tag.lowercased()
        while t.hasPrefix("#") { t.removeFirst() }
        return t
    }

    /// Whether an item with `tags` has every wanted tag.
    static func matches(_ tags: [String]?, wanted: [String]) -> Bool {
        guard !wanted.isEmpty else { return true }
        let have = tags ?? []
        return wanted.allSatisfy { want in have.contains { tag($0, isUnder: want) } }
    }

    /// The part of a set that carries the wanted tags - all of it when the
    /// set's own tags do, otherwise only the cards and questions that do.
    /// Nil when nothing in it does.
    static func tagged(_ set: StudySet, with wanted: [String]) -> StudySet? {
        guard !wanted.isEmpty else { return set }
        if matches(set.tags, wanted: wanted) { return set }
        var out = set
        out.cards = set.cards.filter { card in
            matches(combined(card.tags, set.tags), wanted: wanted)
        }
        out.questions = set.questions.filter { question in
            matches(combined(question.tags, set.tags), wanted: wanted)
        }
        guard !out.cards.isEmpty || !out.questions.isEmpty else { return nil }
        return out
    }

    /// An item's tags with its set's added, since a set's tag covers every
    /// card in it.
    static func combined(_ own: [String]?, _ set: [String]?) -> [String] {
        (own ?? []) + (set ?? [])
    }

    // MARK: - counting

    /// Every tag in the library with how many items carry it, most used
    /// first - for suggestions under the tag field and in search.
    static func counts(in sets: [StudySet]) -> [(tag: String, count: Int)] {
        var tally: [String: (tag: String, count: Int)] = [:]
        func add(_ tags: [String]?) {
            for tag in tags ?? [] {
                let key = tag.lowercased()
                let now = tally[key]?.count ?? 0
                tally[key] = (tally[key]?.tag ?? tag, now + 1)
            }
        }
        for set in sets {
            add(set.tags)
            for card in set.cards { add(card.tags) }
            for question in set.questions { add(question.tags) }
        }
        return tally.values.sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }

    /// Suggestions for what is being typed: known tags that start with it,
    /// or contain it, most used first, never one already chosen.
    static func suggestions(for typed: String, from known: [(tag: String, count: Int)],
                            excluding chosen: [String]?, limit: Int = 8) -> [String] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = chosen ?? []
        let open = known.filter { !contains(taken, $0.tag) }
        guard !needle.isEmpty else { return Array(open.prefix(limit).map { $0.tag }) }
        let starts = open.filter { bare($0.tag).hasPrefix(needle) || label($0.tag).lowercased().hasPrefix(needle) }
        let inside = open.filter { $0.tag.lowercased().contains(needle) && !starts.map { $0.tag }.contains($0.tag) }
        return Array((starts + inside).prefix(limit).map { $0.tag })
    }
}
