import Foundation

/// What the accuracy engine checks: one question, card, case, OSCE station,
/// textbook page, stretch of a narrated lecture's facts, or - only when the
/// student asks - one of their own notes.
enum AccuracyKind: String, Codable, CaseIterable {
    case mcq, card, `case`, osce, page, fact, note

    var noun: String {
        switch self {
        case .mcq: return "question"
        case .card: return "card"
        case .case: return "case"
        case .osce: return "station"
        case .page: return "page"
        case .fact: return "passage"
        case .note: return "note"
        }
    }
}

/// One item as the server's /accuracy/check reads it (server/accuracy.js
/// cleanItem): a question's parts, or the text of anything else, and the
/// lecture excerpt it is checked against.
struct AccuracyItem: Codable, Hashable {
    /// Which item in the app this is: a question's, card's or station's id,
    /// or "<set id>#p<n>" for a textbook page.
    var id: String
    var kind: AccuracyKind
    var stem: String = ""
    var options: [String] = []
    var key: Int = -1
    var explanation: String = ""
    var text: String = ""
    var source: String = ""

    enum CodingKeys: String, CodingKey {
        case id, kind, stem, options, key, explanation, text, source
    }

    static let sourceLimit = 1400

    static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26 else { return "?" }
        return String(UnicodeScalar(UInt8(65 + index)))
    }

    /// The words the checker, the cache and the rules see - the same as
    /// itemText in server/accuracy-rules.js.
    var checkedText: String {
        guard kind == .mcq else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines: [String] = [stem]
        for (i, option) in options.enumerated() {
            lines.append(Self.letter(i) + ". " + option)
        }
        let keyed: String = options.indices.contains(key) ? Self.letter(key) + ". " + options[key] : "none"
        lines.append("Keyed answer: " + keyed)
        lines.append("Explanation: " + explanation)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The cache key on this device: the item's content and its source
    /// excerpt, so an edit - and only an edit - means a new check. FNV-1a,
    /// twice with different seeds: stable across launches and platforms
    /// (Swift's own Hasher is not).
    var contentHash: String {
        let body: String = "v1|" + kind.rawValue + "|" + checkedText + "|" + source.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.fnv(body, seed: 0xcbf29ce484222325) + Self.fnv(body, seed: 0x84222325cbf29ce4)
    }

    static func fnv(_ text: String, seed: UInt64) -> String {
        var hash: UInt64 = seed
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

// MARK: every item in a set

extension AccuracyItem {

    static func mcq(_ q: MCQQuestion, source: String = "") -> AccuracyItem {
        AccuracyItem(id: q.id.uuidString, kind: .mcq, stem: q.stem, options: q.options, key: q.correctIndex,
                     explanation: q.explanation, source: String(source.prefix(sourceLimit)))
    }

    /// A card as question and answer; an image-occlusion card with no words
    /// has nothing to check and gives nil.
    static func card(_ c: AnkiCard, source: String = "") -> AccuracyItem? {
        var lines: [String] = []
        switch c.type {
        case .cloze:
            lines.append("Cloze: " + c.clozeText)
        case .qa, .occlusion:
            let front: String = c.front.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.type == .occlusion && front.isEmpty { return nil }
            lines.append("Q: " + front)
            if !c.bullets.isEmpty { lines.append("A: " + c.bullets.joined(separator: "; ")) }
        }
        let why: String = c.why.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { lines.append("Why: " + why) }
        let text: String = lines.joined(separator: "\n")
        guard text.count > 8 else { return nil }
        return AccuracyItem(id: c.id.uuidString, kind: .card, text: text, source: String(source.prefix(sourceLimit)))
    }

    static func qa(_ c: QACard, source: String = "") -> AccuracyItem {
        let points: String = c.answer.map { "- " + $0 }.joined(separator: "\n")
        let head: String = c.type == .case ? "Case: " : "Q: "
        return AccuracyItem(id: c.id.uuidString, kind: .case, text: head + c.stem + "\nAnswer points:\n" + points,
                            source: String(source.prefix(sourceLimit)))
    }

    static func osce(_ s: OsceChecklist, source: String = "") -> AccuracyItem {
        let steps: String = s.steps.map { "- " + $0 }.joined(separator: "\n")
        return AccuracyItem(id: s.id.uuidString, kind: .osce, text: s.title + "\n" + steps,
                            source: String(source.prefix(sourceLimit)))
    }

    static func page(setID: UUID, number: Int, title: String, markdown: String, source: String = "") -> AccuracyItem {
        AccuracyItem(id: setID.uuidString + "#p\(number)", kind: .page,
                     text: String((title + "\n" + markdown).prefix(3400)), source: String(source.prefix(sourceLimit)))
    }

    /// A student's own note, checked only when they ask.
    static func note(id: UUID, title: String, body: String) -> AccuracyItem {
        AccuracyItem(id: id.uuidString, kind: .note, text: String((title + "\n" + body).prefix(3400)))
    }

    /// Every checkable item of a set, in the set's own order. `source` finds
    /// the lecture excerpt for an item's words (AccuracyChecker.reference on
    /// the phone); nil means the set has no source.
    static func items(in set: StudySet, source: (String) -> String? = { _ in nil }) -> [AccuracyItem] {
        func src(_ words: String) -> String { source(words) ?? "" }
        switch set.kind {
        case .mcq:
            return set.questions.map { q in
                let base = mcq(q)
                return mcq(q, source: src(base.checkedText))
            }
        case .anki:
            return set.cards.compactMap { c in
                guard let base = card(c) else { return nil }
                return card(c, source: src(base.checkedText))
            }
        case .qa:
            return set.qaCards.map { c in qa(c, source: src(qa(c).checkedText)) }
        case .osce:
            return set.osceChecklists.map { s in osce(s, source: src(osce(s).checkedText)) }
        case .book:
            return BookPages.split(set.bookMarkdown).map { p in
                let base = page(setID: set.id, number: p.id, title: p.title, markdown: p.markdown)
                return page(setID: set.id, number: p.id, title: p.title, markdown: p.markdown, source: src(base.text))
            }
        case .narrate:
            return facts(in: set)
        }
    }

    /// A narrated lecture's key facts: the sentences that carry a number, a
    /// dose or a named value, in passages of up to 900 characters - the parts
    /// of a transcript that can be wrong in a way that matters.
    static func facts(in set: StudySet) -> [AccuracyItem] {
        let all: String = set.narrateSegments.map(\.text).joined(separator: " ")
        let sentences: [String] = all.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let factual: [String] = sentences.filter { isFactual($0) }
        var out: [AccuracyItem] = []
        var chunk: String = ""
        func flush() {
            guard !chunk.isEmpty else { return }
            out.append(AccuracyItem(id: set.id.uuidString + "#f\(out.count)", kind: .fact, text: chunk))
            chunk = ""
        }
        for s in factual {
            if chunk.count + s.count > 900 { flush() }
            chunk += (chunk.isEmpty ? "" : " ") + s + "."
        }
        flush()
        return out
    }

    static func isFactual(_ sentence: String) -> Bool {
        if sentence.rangeOfCharacter(from: .decimalDigits) != nil { return true }
        let lower: String = sentence.lowercased()
        if AccuracyRules.drugs.keys.contains(where: { lower.contains($0) }) { return true }
        let markers: [String] = ["first line", "first-line", "drug of choice", "treatment of choice", "gold standard",
                                 "diagnostic", "contraindicated", "most common", "pathognomonic"]
        return markers.contains { lower.contains($0) }
    }
}
