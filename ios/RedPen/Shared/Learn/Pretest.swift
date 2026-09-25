import Foundation

/// "Guess first": five quick questions before a new textbook, lecture or
/// narrate set is read for the first time.
///
/// Trying to answer before studying, then seeing the answer, makes the
/// material stick better than reading alone - even when the guesses are
/// wrong (the pretesting effect; Pan & Carpenter's 2023 review). So the
/// questions are made from the set's own text, on the device, with no model:
/// a sentence that carries one of the text's key terms, with that term
/// blanked, and four other key terms from the same text as the other
/// options. Nothing is invented - every option is a word the reading uses.
///
/// Foundation only (MCQQuestion is a plain model), so it can be tested.
enum Pretest {

    /// How many questions a pretest asks.
    static let count = 5
    /// Options per question, A to E.
    static let optionCount = 5
    /// The one line on screen about why this is worth it.
    static let why = "Guessing before you read, then seeing the answer, helps it stick \u{2014} even when the guess is wrong."

    /// Up to `count` fill-the-gap questions from `text`, spread through it.
    static func questions(from text: String, count: Int = Pretest.count, seed: UInt64 = 1) -> [MCQQuestion] {
        let sentences = Self.sentences(in: plain(text))
        guard !sentences.isEmpty else { return [] }
        let freq = termFrequencies(sentences)
        let terms = freq.filter { $0.value >= 2 }.map(\.key)
        guard terms.count >= optionCount else { return [] }

        // the best sentence in each stretch of the text, so the questions
        // cover the whole of it rather than the first page; each term asked
        // about once, so a chapter's topic word is not the answer five times
        let ranked: [(index: Int, sentence: String, terms: [(term: String, score: Int)])] =
            sentences.enumerated().map { ($0.offset, $0.element, keyTerms(in: $0.element, frequencies: freq)) }
        let stretch: Int = max(1, (sentences.count + count - 1) / count)
        var chosen: [(sentence: String, term: String)] = []
        var usedTerms: Set<String> = []
        var usedSentences: Set<Int> = []
        func best(in range: Range<Int>?) -> (index: Int, sentence: String, term: String)? {
            var top: (index: Int, sentence: String, term: String, score: Int)?
            for c in ranked where !usedSentences.contains(c.index) && (range?.contains(c.index) ?? true) {
                guard let t = c.terms.first(where: { !usedTerms.contains($0.term.lowercased()) }) else { continue }
                if top == nil || t.score > top!.score { top = (c.index, c.sentence, t.term, t.score) }
            }
            return top.map { ($0.index, $0.sentence, $0.term) }
        }
        func take(_ pick: (index: Int, sentence: String, term: String)) {
            chosen.append((pick.sentence, pick.term))
            usedTerms.insert(pick.term.lowercased())
            usedSentences.insert(pick.index)
        }
        for part in 0..<count {
            if let pick = best(in: (part * stretch)..<(part * stretch + stretch)) { take(pick) }
        }
        // a short text: top up from anywhere
        while chosen.count < count, let pick = best(in: nil) { take(pick) }

        var rng = Mixer(state: seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed)
        var out: [MCQQuestion] = []
        for (sentence, term) in chosen {
            let wrong = distractors(for: term, sentence: sentence, pool: terms)
            guard wrong.count == optionCount - 1 else { continue }
            var options = wrong + [term]
            options.shuffle(using: &rng)
            let stem = blanked(term, in: sentence)
            out.append(MCQQuestion(stem: stem, options: options,
                                   correctIndex: options.firstIndex(of: term) ?? 0,
                                   explanation: sentence, imageIndex: nil))
        }
        return out
    }

    // MARK: the pieces

    /// Markdown down to prose: headings, emphasis, list markers, code and
    /// links' brackets go.
    static func plain(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            while let first = line.first, "#>-*+|".contains(first) { line.removeFirst() }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        return lines.joined(separator: "\n")
    }

    /// Sentences of 8 to 40 words.
    static func sentences(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        func flush() {
            let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            let words = s.split(separator: " ").count
            if words >= 8 && words <= 40 { out.append(s) }
        }
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if ch == "\n" {
                flush()
                continue
            }
            current.append(ch)
            if ".?!".contains(ch) {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                // "e.g." and "2.5" are not the end of a sentence
                if next == nil || next == " " || next == "\n" {
                    let tail = current.suffix(5).lowercased()
                    if !tail.hasSuffix("e.g.") && !tail.hasSuffix("i.e.") && !tail.hasSuffix("vs.") { flush() }
                }
            }
        }
        flush()
        return out
    }

    /// Common words that are never the point of a sentence.
    static let stopwords: Set<String> = [
        "about", "above", "after", "again", "against", "along", "also", "although", "always", "among",
        "another", "around", "because", "been", "before", "being", "below", "between", "both", "cause",
        "caused", "causes", "could", "does", "doing", "down", "during", "each", "either", "every",
        "first", "following", "from", "further", "have", "having", "here", "however", "into", "itself",
        "later", "least", "less", "like", "likely", "made", "make", "many", "might", "more", "most",
        "much", "must", "never", "often", "only", "other", "others", "over", "patient", "patients",
        "people", "rather", "same", "second", "seen", "should", "shows", "since", "some", "such",
        "than", "that", "their", "them", "then", "there", "these", "they", "this", "those", "though",
        "three", "through", "under", "until", "usually", "used", "using", "very", "what", "when",
        "where", "whether", "which", "while", "with", "within", "without", "would", "your", "years",
        "common", "commonly", "important", "include", "includes", "including", "known", "called",
        "usual", "emerges", "passes", "pushes", "appears", "typically", "typical", "result", "results", "occur", "occurs", "found", "given",
    ]

    /// A word worth blanking: at least five letters, not a stopword.
    /// Words ending "-ing" or "-ed" are nearly always verbs here, and a
    /// verb makes a poor blank.
    static func isTerm(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        guard letters.count >= 5, letters.count == word.filter({ $0.isLetter || $0 == "-" }).count else { return false }
        let lower = word.lowercased()
        if lower.hasSuffix("ing") || lower.hasSuffix("ed") { return false }
        return !stopwords.contains(lower)
    }

    /// The words of a sentence, punctuation trimmed.
    static func words(_ sentence: String) -> [String] {
        sentence.split(whereSeparator: { $0 == " " || $0 == "/" }).map {
            $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-")))
        }.filter { !$0.isEmpty }
    }

    /// How often each term appears across the text, by lower-case form; the
    /// key is the first spelling met.
    static func termFrequencies(_ sentences: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for s in sentences {
            for w in words(s) where isTerm(w) {
                let key = w.lowercased()
                counts[key, default: 0] += 1
                if spelling[key] == nil { spelling[key] = w }
            }
        }
        var out: [String: Int] = [:]
        for (key, n) in counts { out[spelling[key] ?? key] = n }
        return out
    }

    /// The sentence's telling terms, best first: ones the text keeps coming
    /// back to, longer ones first. Empty when it has none worth asking about.
    static func keyTerms(in sentence: String, frequencies: [String: Int]) -> [(term: String, score: Int)] {
        var lower: [String: (String, Int)] = [:]
        for (k, v) in frequencies { lower[k.lowercased()] = (k, v) }
        var out: [(term: String, score: Int)] = []
        var seen: Set<String> = []
        for (position, w) in words(sentence).enumerated() where isTerm(w) {
            guard let (term, n) = lower[w.lowercased()], n >= 2, seen.insert(term.lowercased()).inserted else { continue }
            // the sentence's own first word is usually its subject, and
            // blanking it leaves a stem with no footing
            let score = n * 10 + w.count - (position == 0 ? 15 : 0)
            out.append((term, score))
        }
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.term < $1.term }
    }

    /// Four other key terms, nearest in length, none already in the sentence.
    static func distractors(for term: String, sentence: String, pool: [String]) -> [String] {
        let inSentence = Set(words(sentence).map { $0.lowercased() })
        let capital = term.first?.isUppercase ?? false
        let ending = term.lowercased().suffix(2)
        let others = pool.filter { t in
            t.lowercased() != term.lowercased() && !inSentence.contains(t.lowercased())
        }
        let ranked = others.sorted { a, b in
            // same capitalisation first (names with names), then length
            // same ending (adjectives with adjectives: femoral, inguinal),
            // then same capitalisation (names with names), then length
            let ea = a.lowercased().suffix(2) == ending, eb = b.lowercased().suffix(2) == ending
            if ea != eb { return ea }
            let ca = (a.first?.isUppercase ?? false) == capital
            let cb = (b.first?.isUppercase ?? false) == capital
            if ca != cb { return ca }
            let da = abs(a.count - term.count), db = abs(b.count - term.count)
            if da != db { return da < db }
            return a < b
        }
        var out: [String] = []
        var seen: Set<String> = []
        for t in ranked where seen.insert(t.lowercased()).inserted {
            out.append(t)
            if out.count == optionCount - 1 { break }
        }
        return out
    }

    /// The sentence with the term replaced by a blank, once.
    /// Whole words only: "renal" is not blanked inside "adrenal".
    static func blanked(_ term: String, in sentence: String) -> String {
        var from = sentence.startIndex
        while let r = sentence.range(of: term, options: .caseInsensitive, range: from..<sentence.endIndex) {
            from = r.upperBound
            let before: Character? = r.lowerBound > sentence.startIndex ? sentence[sentence.index(before: r.lowerBound)] : nil
            let after: Character? = r.upperBound < sentence.endIndex ? sentence[r.upperBound] : nil
            if let b = before, b.isLetter { continue }
            if let a = after, a.isLetter { continue }
            return sentence.replacingCharacters(in: r, with: "_____")
        }
        return sentence
    }

    /// A small seeded generator, so a set's pretest is the same each time.
    struct Mixer: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
