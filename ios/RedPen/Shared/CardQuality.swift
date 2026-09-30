import Foundation

/// What makes a generated card or question bad, found before you memorise it.
///
/// A generated deck fails in ways that are invisible while you use it, because
/// each of them makes you feel like you are doing well: a question answerable
/// from the SHAPE of the options rather than the medicine, a card carrying
/// three facts so that "again" on one re-drills all three, a cloze that blanks
/// so much of the sentence there is nothing left to cue recall, two cards
/// asking one thing in different words.
///
/// Nothing here rewrites anything. Each rule reports, with the item's id and a
/// reason you can check, because a generator is wrong often enough that a
/// silent auto-fix only moves the error somewhere harder to see.
///
/// This is a port of pipeline/tools/card_quality.py and must agree with it:
/// the same deck is judged on the phone and in CI, and two verdicts would make
/// both worthless.
enum CardQuality {

    struct Problem: Identifiable, Hashable {
        let id = UUID()
        var itemID: UUID?
        var rule: String
        var detail: String
    }

    static let absolutes = ["always", "never", "all patients", "every patient", "exclusively"]
    static let hedges = ["may", "can", "sometimes", "often", "usually", "generally", "typically"]
    static let nonAnswers = ["all of the above", "none of the above", "both a and b",
                             "a and b", "all of these", "none of these"]
    static let stopwords: Set<String> = [
        "the", "a", "an", "of", "in", "is", "are", "to", "and", "or", "with", "for",
        "by", "on", "at", "as", "that", "this", "it", "be", "which", "what", "most",
        "best", "following", "patient", "next", "step"]

    /// Content words only. A rule that counted "the" as shared vocabulary would
    /// fire on every question ever written.
    static func terms(_ text: String) -> Set<String> {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    // MARK: questions

    static func check(_ q: MCQQuestion) -> [Problem] {
        var out: [Problem] = []
        func flag(_ rule: String, _ detail: String) {
            out.append(Problem(itemID: q.id, rule: rule, detail: detail))
        }
        let stem = q.stem.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = q.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // five, or four for the exams that use A-D (ExamCatalog)
        if !(4...5).contains(options.count) { flag("option-count", "\(options.count) options, expected 4 or 5") }
        guard options.indices.contains(q.correctIndex) else {
            flag("no-key", "correctIndex \(q.correctIndex)")
            return out
        }
        let key = options[q.correctIndex]
        let others = options.enumerated().filter { $0.offset != q.correctIndex }.map(\.element)

        if Set(options.map { $0.lowercased() }).count != options.count {
            flag("duplicate-option", "two options say the same thing")
        }
        for o in options where nonAnswers.contains(o.lowercased()) {
            flag("non-answer-option", o)
        }

        // Cover the options: a stem that is only a topic tests recognition
        // rather than recall, because you cannot answer it without reading them.
        if !stem.hasSuffix("?") && !stem.contains("______") && stem.count <= 60 {
            flag("stem-not-a-question", String(stem.prefix(80)))
        }
        if stem.split(separator: " ").count < 6 {
            flag("stem-too-thin", "\(stem.split(separator: " ").count) words")
        }

        // The length tell: a key noticeably longer than every distractor is the
        // most reliable way to pass a generated question knowing nothing, since
        // the model elaborates the answer it believes.
        if let longest = others.map(\.count).max(), key.count > 40,
           Double(key.count) > 1.6 * Double(longest) {
            flag("key-is-longest", "key \(key.count) chars, longest distractor \(longest)")
        }

        // The hedge tell, in both directions.
        let keyHedges = hedges.contains { key.lowercased().contains($0) }
        let othersHedge = others.contains { o in hedges.contains { o.lowercased().contains($0) } }
        if keyHedges && !othersHedge { flag("only-key-hedges", String(key.prefix(80))) }
        if absolutes.contains(where: { key.lowercased().contains($0) }) {
            flag("absolute-in-key", String(key.prefix(80)))
        }

        // The clang tell: a content word in the stem and the key and nowhere else.
        let elsewhere = others.reduce(into: Set<String>()) { $0.formUnion(terms($1)) }
        let giveaway = terms(stem).intersection(terms(key)).subtracting(elsewhere)
        if !giveaway.isEmpty {
            flag("stem-word-only-in-key", giveaway.sorted().joined(separator: ", "))
        }

        let why = q.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if why.isEmpty {
            flag("no-explanation", "")
        } else if terms(key).isDisjoint(with: terms(why)) {
            // an explanation that never mentions the answer is usually an
            // explanation of a different question
            flag("explanation-misses-the-key", String(why.prefix(80)))
        }
        return out
    }

    // MARK: cards

    static func check(_ card: AnkiCard) -> [Problem] {
        var out: [Problem] = []
        func flag(_ rule: String, _ detail: String) {
            out.append(Problem(itemID: card.id, rule: rule, detail: detail))
        }
        let why = card.why.trimmingCharacters(in: .whitespacesAndNewlines)

        if card.type == .cloze {
            let holes = clozeHoles(card.clozeText)
            if holes.isEmpty {
                flag("cloze-without-a-deletion", String(card.clozeText.prefix(80)))
                return out
            }
            let deleted = holes.reduce(0) { $0 + $1.text.count }
            let bare = clozeBare(card.clozeText)
            if !bare.isEmpty && Double(deleted) > 0.5 * Double(bare.count) {
                flag("cloze-swallows-the-sentence",
                     "\(deleted) of \(bare.count) characters deleted")
            }
            if Set(holes.map(\.number)).count > 3 {
                flag("too-many-deletions", "\(Set(holes.map(\.number)).count) separate deletions")
            }
            for hole in holes where hole.text.split(separator: " ").count > 6 {
                flag("deletion-is-a-clause", String(hole.text.prefix(60)))
            }
            return out
        }

        let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets = card.bullets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if card.type == .occlusion {
            // an occlusion card's answer is the picture, so the text rules below
            // would only ever fire on cards that are perfectly fine
            if card.imageIndex == nil { flag("occlusion-without-an-image", front) }
            if card.occlusion == nil { flag("occlusion-without-a-box", front) }
            return out
        }

        if front.isEmpty {
            flag("no-front", "")
        } else if front.split(separator: " ").count < 3 {
            flag("front-too-thin", front)
        }
        // One fact per card: the point of spaced repetition is that one "again"
        // costs you one fact, not five.
        if bullets.count > 4 { flag("too-many-facts", "\(bullets.count) bullets") }
        for b in bullets where b.split(separator: " ").count > 30 {
            flag("bullet-is-a-paragraph", String(b.prefix(60)))
        }
        if !front.isEmpty && !bullets.isEmpty {
            let back = bullets.joined(separator: " ").lowercased()
            if back.contains(front.lowercased().replacingOccurrences(of: "?", with: "")) {
                flag("front-appears-on-the-back", String(front.prefix(60)))
            }
        }
        if bullets.isEmpty { flag("no-answer", String(front.prefix(60))) }
        return out
    }

    // MARK: cloze parsing, shared with the quiz builder

    struct Hole { var number: Int; var text: String; var range: Range<String.Index> }

    static func clozeHoles(_ text: String) -> [Hole] {
        guard let re = try? NSRegularExpression(pattern: #"\{\{c(\d+)::(.+?)(?:::.*?)?\}\}"#)
        else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                guard let range = Range(m.range, in: text) else { return nil }
                return Hole(number: Int(ns.substring(with: m.range(at: 1))) ?? 1,
                            text: ns.substring(with: m.range(at: 2)),
                            range: range)
            }
    }

    /// The sentence with the braces removed but the words kept.
    static func clozeBare(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\{\{c\d+::(.+?)(?:::.*?)?\}\}"#)
        else { return text }
        let ns = NSMutableString(string: text)
        re.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length),
                          withTemplate: "$1")
        return ns as String
    }

    // MARK: whole sets

    /// Pairs asking the same thing in different words.
    ///
    /// Measured on the QUESTION, not the answer: two cards with the same answer
    /// are often fine (many things cause anaemia), while two cards asking the
    /// same question are one card you will review twice forever.
    static func duplicates(_ items: [(id: UUID, text: String)],
                           threshold: Double = 0.86) -> [Problem] {
        var out: [Problem] = []
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i].text.lowercased(), b = items[j].text.lowercased()
                if a.isEmpty || b.isEmpty { continue }
                let score = similarity(a, b)
                if score >= threshold {
                    out.append(Problem(itemID: items[i].id, rule: "near-duplicate",
                                       detail: String(format: "%.2f like another", score)))
                }
            }
        }
        return out
    }

    /// Token-level overlap, which is enough to spot a reworded duplicate and
    /// cheap enough to run over a whole deck on the phone.
    ///
    /// Read through `similarityTokens`: case, hyphens and a plural "s" do not
    /// make two answers different ("Beta blockers", "beta-blocker"), and a
    /// number does ("140 mmol/L", "3.5 mmol/L" are two different answers, not
    /// one unit written twice).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = similarityTokens(a)
        let y = similarityTokens(b)
        if x.isEmpty || y.isEmpty { return 0 }
        return Double(x.intersection(y).count) / Double(max(x.count, y.count))
    }

    /// Lower-cased words and numbers ("3.5" is one number), with a plural
    /// "s" taken off a longer word ("inhibitors" is "inhibitor"; "sepsis",
    /// "mellitus" and "loss" are left alone).
    static func similarityTokens(_ text: String) -> Set<String> {
        var out = Set<String>()
        var word = ""
        var number = ""
        func flush() {
            if !word.isEmpty { out.insert(singular(word)); word = "" }
            if !number.isEmpty {
                // a trailing point is punctuation, not a decimal
                while number.hasSuffix(".") { number.removeLast() }
                if !number.isEmpty { out.insert(number) }
                number = ""
            }
        }
        for ch in text.lowercased() {
            if ch.isNumber {
                if !word.isEmpty { flush() }
                number.append(ch)
            } else if ch == ".", !number.isEmpty, !number.contains(".") {
                number.append(ch)
            } else if ch.isLetter {
                if !number.isEmpty { flush() }
                word.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s") else { return word }
        for kept in ["ss", "us", "is"] where word.hasSuffix(kept) { return word }
        return String(word.dropLast())
    }

    static func review(questions: [MCQQuestion] = [], cards: [AnkiCard] = []) -> [Problem] {
        var out: [Problem] = []
        for q in questions { out += check(q) }
        for c in cards { out += check(c) }
        out += duplicates(questions.map { ($0.id, $0.stem) })
        out += duplicates(cards.map { ($0.id, $0.type == .cloze ? $0.clozeText : $0.front) })
        return out
    }
}
