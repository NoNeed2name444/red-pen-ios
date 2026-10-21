import Foundation

/// An explanation that names an option by its place - "option B", "the
/// second option", "the correct answer is C" - rewritten to name it by its
/// words.
///
/// The options are shown shuffled, so a place written when the question was
/// made points at whichever option happens to sit there on screen. The prompt
/// forbids it (MCQPrompt, rule 6), and small models write it anyway: Qwen3-4B
/// did in five explanations out of five on the same prompt, and the on-device
/// writers are that class of model. Naming the option by its own words is
/// what the prompt asked for in the first place, and it stays right in any
/// order.
///
/// It is careful about what it touches, because clinical English is full of
/// "choice" and "option":
///   * only a capital letter is a letter reference, so "the drug of choice a
///     decade ago" is left alone, and only one of this question's letters;
///   * a number counts only after "option" or "choice", from 1 up (never
///     "option 0"), and only when what follows reads as the end of a
///     reference ("option 2 is...", "option 2,") - so "the drug of choice
///     2 weeks after" stays as written;
///   * an ordinal counts only when it ends the reference in the same way, so
///     "the second choice after metformin" and "the first option for
///     hypertension" stay as written;
///   * the letter of "choice B" is the B, not the first a-to-e letter in the
///     phrase (the transcribe repo's version read "choice B" as C).
///
/// An explanation whose stated answer disagrees with the key is left exactly
/// as it is: the accuracy rules read the stored text, and rewriting "Option C
/// is correct" on a question keyed B into the option's words would hide the
/// one sentence that shows the key is wrong (AccuracyRules'
/// key-explanation-conflict, which grades the set).
///
/// Lengths are not touched here: padding a distractor to hide a length
/// giveaway would put filler into a revision question, and
/// MCQGenerator.lengthBalanced already turns those questions away.
///
/// Foundation only, so it is tested.
enum MCQRepair {

    struct Result: Equatable {
        var text: String
        /// How many references were rewritten.
        var rewritten: Int
    }

    /// The question with its explanation's position references rewritten.
    static func repaired(_ question: MCQQuestion) -> MCQQuestion {
        var out = question
        out.explanation = rewrite(question.explanation, options: question.options,
                                  correctIndex: question.correctIndex).text
        return out
    }

    static func rewrite(_ explanation: String, options: [String], correctIndex: Int) -> Result {
        let unchanged = Result(text: explanation, rewritten: 0)
        guard !explanation.isEmpty, options.count >= 2 else { return unchanged }
        if let said = AccuracyRules.explainedAnswer(explanation, options: options), said != correctIndex {
            return unchanged
        }
        let names: [String] = shortNames(options)
        let ns = explanation as NSString
        var edits: [(range: NSRange, text: String, count: Int)] = []

        func unclaimed(_ r: NSRange) -> Bool {
            !edits.contains { NSIntersectionRange($0.range, r).length > 0 }
        }
        func quoted(_ index: Int) -> String { "\"" + names[index] + "\"" }

        // 1. a list: "Options B and C", "options A, C or D"
        for m in found(Pattern.list, in: explanation) where unclaimed(m.range) {
            let letters: String = ns.substring(with: m.range(at: 1))
            let lns = letters as NSString
            let tokens = found(Pattern.letterToken, in: letters)
            let indices: [Int?] = tokens.map { letterIndex(lns.substring(with: $0.range(at: 1)), count: options.count) }
            guard !tokens.isEmpty, !indices.contains(where: { $0 == nil }) else { continue }
            let out = NSMutableString(string: letters)
            for (token, index) in zip(tokens, indices).reversed() {
                out.replaceCharacters(in: token.range, with: quoted(index ?? 0))
            }
            edits.append((range: m.range, text: out as String, count: tokens.count))
        }
        // 2. the answer stated: "the correct answer is C", "Answer: (C)" -
        //    the words before the letter stay
        for m in found(Pattern.stated, in: explanation) where unclaimed(m.range) {
            guard let index = letterIndex(ns.substring(with: m.range(at: 2)), count: options.count) else { continue }
            edits.append((range: m.range, text: ns.substring(with: m.range(at: 1)) + quoted(index), count: 1))
        }
        // 3. one letter: "option B", "the choice (B)", "answer B"
        for m in found(Pattern.letter, in: explanation) where unclaimed(m.range) {
            guard let index = letterIndex(ns.substring(with: m.range(at: 1)), count: options.count) else { continue }
            edits.append((range: m.range, text: quoted(index), count: 1))
        }
        // 4. a number: "option 2", models count from 1
        for m in found(Pattern.number, in: explanation) where unclaimed(m.range) {
            guard let n = Int(ns.substring(with: m.range(at: 1))), n >= 1, n <= options.count else { continue }
            edits.append((range: m.range, text: quoted(n - 1), count: 1))
        }
        // 5. an ordinal: "the second option", "the last choice"
        for m in found(Pattern.ordinal, in: explanation) where unclaimed(m.range) {
            let word: String = ns.substring(with: m.range(at: 1)).lowercased()
            let index: Int = word == "last" ? options.count - 1 : (ordinals.firstIndex(of: word) ?? options.count)
            guard index < options.count else { continue }
            edits.append((range: m.range, text: quoted(index), count: 1))
        }

        guard !edits.isEmpty else { return unchanged }
        let out = NSMutableString(string: explanation)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            out.replaceCharacters(in: edit.range, with: edit.text)
        }
        return Result(text: out as String, rewritten: edits.reduce(0) { $0 + $1.count })
    }

    private static func found(_ re: NSRegularExpression?, in text: String) -> [NSTextCheckingResult] {
        re?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }

    // MARK: naming an option

    /// What each option is called in a rewritten explanation: its short
    /// name, or its whole text when two options' short names are the same -
    /// look-alike distractors are what the prompt asks for, so "Hyperkalaemia
    /// with peaked T waves" and "...with flattened T waves" both shorten to
    /// "Hyperkalaemia", and a name two options share names neither.
    static func shortNames(_ options: [String]) -> [String] {
        let short: [String] = options.map(shortName)
        return options.indices.map { i in
            let key: String = short[i].lowercased()
            let clash: Bool = short.indices.contains { $0 != i && short[$0].lowercased() == key }
            return clash ? whole(options[i]) : short[i]
        }
    }

    /// The leading phrase that names an option: cut at the first clause
    /// ("..., which", "... with", "... that"), at most six words, and never
    /// ending on a word that cannot end a phrase - a six-word cut once gave
    /// "The malar rash is chronic and".
    static func shortName(_ option: String) -> String {
        let full: String = whole(option)
        var text: String = full
        if let r = text.range(of: #"[,;:]\s|\s+(?:with|without|that|which|who|whose|where|because|due\s+to)\b"#,
                              options: [.regularExpression, .caseInsensitive]),
           r.lowerBound > text.startIndex {
            text = String(text[..<r.lowerBound])
        }
        var words: [String] = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count > 6 { words = Array(words.prefix(6)) }
        while let last = words.last, dangling.contains(last.lowercased()) { words.removeLast() }
        return words.isEmpty ? full : words.joined(separator: " ")
    }

    private static func whole(_ option: String) -> String {
        var text: String = option.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static let dangling: Set<String> = [
        "and", "or", "but", "with", "without", "that", "which", "is", "are",
        "was", "were", "the", "a", "an", "in", "of", "to", "for", "from",
        "on", "at", "by", "as", "its", "it", "this", "these",
    ]

    // MARK: reading a reference

    private static let ordinals: [String] = ["first", "second", "third", "fourth", "fifth",
                                             "sixth", "seventh", "eighth", "ninth", "tenth"]

    /// A capital letter's option, or nil when the question has no such option.
    private static func letterIndex(_ letter: String, count: Int) -> Int? {
        guard letter.count == 1, let scalar = letter.unicodeScalars.first,
              scalar.value >= 65, scalar.value <= 74 else { return nil }
        let index = Int(scalar.value) - 65
        return index < count ? index : nil
    }

    private enum Pattern {
        /// What may follow a number or an ordinal for it to be a reference:
        /// the end, punctuation (not a decimal point), or a word a sentence
        /// about an option goes on with. "option 2 weeks" is not one.
        static let ends: String = #"(?=\s*$|\s*[,;:!?)\]]|\.(?!\d)|\s+(?:is|was|would|does|did|can|could|may|might|has|had|and|or|but|because|since|as|describes|refers|represents|correctly|incorrectly|also|alone|here|do|are|were|will|should|must)\b)"#
        // "C. difficile" and "E. coli" are not options C and E
        static let letterEnd: String = #"(?![A-Za-z0-9\-])(?!\.\s?[a-z])"#

        static let list: NSRegularExpression? = make(
            #"\b[Oo]ptions\s+(\(?[A-J]\)?(?:(?:\s*,\s*|,?\s+(?:and|or)\s+)\(?[A-J]\)?)+)"# + letterEnd)
        static let letterToken: NSRegularExpression? = make(#"\(?([A-J])\)?"#)
        static let stated: NSRegularExpression? = make(
            #"\b((?:[Tt]he\s+)?(?:(?:correct|right|best)\s+)?(?:[Aa]nswer|[Oo]ption|[Cc]hoice)(?:\s+is\s+|\s*:\s*))(?:[Oo]ption\s+)?\(?([A-J])\)?"# + letterEnd)
        static let letter: NSRegularExpression? = make(
            #"\b(?:[Tt]he\s+)?(?:[Oo]ption|[Cc]hoice|[Aa]nswer)\s+\(?([A-J])\)?"# + letterEnd)
        static let number: NSRegularExpression? = make(
            #"\b(?:[Tt]he\s+)?(?:[Oo]ption|[Cc]hoice)\s+\(?([0-9])\)?"# + ends)
        static let ordinal: NSRegularExpression? = make(
            #"\b[Tt]he\s+(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|last)\s+(?:option|choice|answer)"# + ends)

        // fixed patterns: one that failed to compile would be a typo, and
        // the tests would catch it as references left unrewritten
        private static func make(_ pattern: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern)
        }
    }
}
