import Foundation

/// Making sense of a spoken answer.
///
/// The recogniser hands back what it thinks it heard, and a single letter is
/// the thing it is worst at: "B" comes back as "be", "bee" or "Bea", "C" as
/// "see" or "sea". So a letter is looked for in every way it is commonly
/// misheard, and a student who reads the option out instead of its letter is
/// understood too.
enum SpokenAnswer {

    static let letters = ["A", "B", "C", "D", "E"]

    /// Words the recogniser writes for each letter that are hardly ever
    /// anything else, first to last.
    private static let clearSpellings: [[String]] = [
        ["ay", "alpha"],
        ["b", "bee", "bea", "bravo"],
        ["c", "sea", "charlie"],
        ["d", "dee", "delta"],
        ["e", "echo"],
    ]

    /// Spellings that are also everyday words or numbers - "it must BE D",
    /// "I SEE", "the ONE with", "TWO litres" - so they count only when
    /// nothing clearer was said.
    private static let looseSpellings: [[String]] = [
        ["a", "eh", "one", "1"],
        ["be", "two", "2"],
        ["see", "si", "three", "3"],
        ["four", "4"],
        ["ee", "five", "5"],
    ]

    /// Words said around a letter that carry no answer of their own.
    private static let filler: Set<String> = [
        "i", "im", "it", "its", "s", "is", "the", "answer", "option", "letter", "think", "say",
        "go", "with", "um", "uh", "er", "erm", "hmm", "ok", "okay", "so", "my", "final", "that",
        "this", "guess", "pick", "choose", "must", "would", "should", "could", "might", "will",
        "maybe", "probably", "definitely", "sure", "id", "ll", "going", "to", "for", "yes",
        "yeah", "no", "wait", "actually", "please", "number", "then", "oh", "well", "like",
    ]

    /// Which letter a spelling stands for, and whether it is a clear one.
    private static func letter(of token: String) -> (index: Int, clear: Bool)? {
        if let i = clearSpellings.firstIndex(where: { $0.contains(token) }) { return (i, true) }
        if let i = looseSpellings.firstIndex(where: { $0.contains(token) }) { return (i, false) }
        return nil
    }

    /// Lower-case words and numbers, in order.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Which option was chosen, if one can be told from what was said. The
    /// index is the option's place in `options`, as they were read out.
    ///
    /// A letter is looked for first. When the student read an option out
    /// instead, the option whose words they said is taken - but only if they
    /// said most of its own words and no other option fits as well: one
    /// shared word ("hernia", "syndrome") is not an answer. A letter and an
    /// option that disagree is not an answer either; the caller asks again.
    static func option(in heard: String, options: [String]) -> Int? {
        let count = min(options.count, letters.count)
        guard count > 0 else { return nil }
        let words = tokens(heard)
        guard !words.isEmpty else { return nil }
        let shown = Array(options.prefix(count))
        // every word of every option, so a letter inside an option read out
        // ("hepatitis C", "vitamin B12") is not taken for the answer letter
        var optionWords: Set<String> = []
        for option in shown { optionWords.formUnion(tokens(option)) }

        // Did they say anything besides letters and filler that belongs to
        // an option? If not, every letter-like word is a letter.
        let content = words.filter {
            letter(of: $0) == nil && !filler.contains($0) && !CardQuality.stopwords.contains($0)
        }
        let readOut = content.contains { optionWords.contains($0) }

        let byText: Int? = readOut ? optionByWords(heard, options: shown) : nil
        let ignored: Set<String> = readOut ? optionWords : []
        let byLetter: Int? = letterChoice(words, count: count, ignoring: ignored)
        switch (byLetter, byText) {
        case let (l?, t?): return l == t ? l : nil
        case let (l?, nil): return l
        case let (nil, t?): return t
        default: return nil
        }
    }

    /// The letter said, if any: the last clear spelling (so "B - no, D" is D),
    /// or failing that the last loose one, as long as it is not an ordinary
    /// word in the middle of a sentence ("it must be", "I see").
    private static func letterChoice(_ words: [String], count: Int, ignoring: Set<String>) -> Int? {
        var clear: Int?
        var loose: Int?
        for (i, word) in words.enumerated() where !ignoring.contains(word) {
            guard let found = letter(of: word), found.index < count else { continue }
            if found.clear {
                clear = found.index
                continue
            }
            // "be" after "must", "would", "to" and so on is the verb; "see"
            // after "I" or "let's" is too
            let before: String = i > 0 ? words[i - 1] : ""
            let verbBefore: Set<String> = ["must", "would", "could", "should", "might", "will",
                                           "to", "can", "may", "i", "lets", "let", "cant", "wont"]
            if (word == "be" || word == "see") && verbBefore.contains(before) { continue }
            // "the one with..." points at an option; it is not option A
            let pointing: Set<String> = ["the", "that", "this", "which", "no"]
            if word == "one" && pointing.contains(before) { continue }
            loose = found.index
        }
        return clear ?? loose
    }

    /// The option whose own words were said. Words every option shares
    /// ("hernia" in a question about hernias) say nothing; an option is taken
    /// when it is the only one whose own distinguishing words were said, or,
    /// failing that, the only one whose words were all said. Nil when none
    /// fits, or more than one does.
    static func optionByWords(_ heard: String, options: [String]) -> Int? {
        let said = keyWords(heard)
        guard !said.isEmpty else { return nil }
        let wanted: [Set<String>] = options.map { keyWords($0) }
        var distinctHits: [Int] = []
        var whole: [Int] = []
        for (index, words) in wanted.enumerated() {
            if words.isEmpty || contradicts(said, words) {
                distinctHits.append(0)
                continue
            }
            var others: Set<String> = []
            for (j, other) in wanted.enumerated() where j != index { others.formUnion(other) }
            let own = words.filter { word in !others.contains { close($0, word) } }
            let hits = own.filter { word in said.contains { close($0, word) } }.count
            distinctHits.append(hits)
            if words.allSatisfy({ word in said.contains { close($0, word) } }) { whole.append(index) }
        }
        let hitters = distinctHits.indices.filter { distinctHits[$0] > 0 }
        if hitters.count == 1 { return hitters[0] }
        if hitters.isEmpty && whole.count == 1 { return whole[0] }
        return nil
    }

    /// Whether a spoken answer to a card has the card's answer in it.
    ///
    /// Generous about how things are said - plurals and endings, British
    /// and American spelling, a drug name the recogniser splits in two - but
    /// not about what: more than half of each answer line's own words must be
    /// said (all of them when there are only one or two), and a word said
    /// with its opposite prefix ("indirect" for "direct", "hypo" for "hyper")
    /// is a wrong answer however much else matches. A number in the answer
    /// has to be said. A list of several answer lines needs half of them.
    static func matches(_ heard: String, answer: [String]) -> Bool {
        let lines = answer.map(Highlight.plain)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        let said = keyWords(heard)
        let saidNumbers = numbers(in: heard)
        var matched = 0
        for line in lines where lineMatches(line, said: said, saidNumbers: saidNumbers, heard: heard) {
            matched += 1
        }
        return matched * 2 >= lines.count && matched > 0
    }

    private static func lineMatches(_ line: String, said: Set<String>, saidNumbers: Set<String>,
                                    heard: String) -> Bool {
        let wantedNumbers = numbers(in: line)
        if !wantedNumbers.isEmpty, wantedNumbers.isDisjoint(with: saidNumbers) { return false }
        let wanted = keyWords(line)
        guard !wanted.isEmpty else {
            // nothing but numbers, or nothing but small words: the words
            // themselves, whole, in the order written
            if !wantedNumbers.isEmpty { return true }
            let want = tokens(line)
            let got = tokens(heard)
            return !want.isEmpty && want.allSatisfy { got.contains($0) }
        }
        if contradicts(said, wanted) { return false }
        let hits = wanted.filter { word in said.contains { close($0, word) } }.count
        // one or two words: all of them; more: a clear majority
        if wanted.count <= 2 { return hits == wanted.count }
        return hits * 2 > wanted.count
    }

    /// Words too general to tell one answer from another: "Addison's
    /// disease" and "Cushing's disease" share "disease" and nothing that
    /// matters. They are left out unless an answer has nothing else.
    private static let general: Set<String> = [
        "disease", "syndrome", "disorder", "condition", "deficiency", "infection", "failure",
        "acute", "chronic", "the", "and", "with", "for", "from", "that", "this", "which", "into",
        "of", "in", "is", "are", "to", "or", "on", "at", "as", "by", "be", "it", "an", "a",
        "its", "was", "were", "has", "have", "due", "caused", "cause", "causes", "type",
        "most", "likely", "probably", "think", "answer", "um", "uh", "er", "erm", "so", "then",
    ]

    /// The words of `text` that carry its meaning, spelled one way:
    /// lower case, "ae" and "oe" as "e" (haem/hem, oedema/edema), and number
    /// words as digits.
    static func keyWords(_ text: String) -> Set<String> {
        // "SGLT2" and "SGLT 2" are the same thing said two ways: letters and
        // digits are separate words (the digits are checked as numbers)
        var pieces: [String] = []
        // "Type II" is said, and written by the recogniser, as "type 2"
        for token in arabic(tokens(Highlight.plain(text))) {
            var run = ""
            for ch in token {
                if let last = run.last, last.isNumber != ch.isNumber {
                    pieces.append(run)
                    run = ""
                }
                run.append(ch)
            }
            if !run.isEmpty { pieces.append(run) }
        }
        let words = pieces.map(normalise)
        let meaningful = words.filter { !general.contains($0) && !$0.allSatisfy(\.isNumber) }
        if !meaningful.isEmpty { return Set(meaningful) }
        // an answer made only of general words is still an answer
        return Set(words.filter { !$0.allSatisfy(\.isNumber) && $0.count > 2 })
    }

    private static func normalise(_ word: String) -> String {
        word.replacingOccurrences(of: "ae", with: "e").replacingOccurrences(of: "oe", with: "e")
    }

    private static let romans: [String: String] = [
        "i": "1", "ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6",
        "vii": "7", "viii": "8", "ix": "9", "x": "10", "xi": "11", "xii": "12",
    ]
    /// Numerals that are also a letter or a word - "I", "X-linked", "V/Q",
    /// "IV fluids" - and so are read as numbers only after a word that takes
    /// a numeral.
    private static let ambiguousRomans: Set<String> = ["i", "v", "x", "iv"]
    private static let takesNumeral: Set<String> = [
        "type", "class", "grade", "stage", "factor", "cn", "nerve", "cranial", "phase", "mobitz",
        "degree", "collagen", "level", "zone", "schedule", "part", "complex", "group", "category",
        "tier", "lead", "fort", "harris",
    ]

    /// Roman numerals as digits, the way the recogniser writes them: "Type
    /// II hypersensitivity" is heard as "type 2", "Factor VIII" as "factor
    /// 8". A numeral of two or more letters always; I, V, X and IV only after
    /// a word that takes a numeral ("type I", "factor V", "CN X").
    static func arabic(_ words: [String]) -> [String] {
        var out = words
        for (i, word) in words.enumerated() {
            guard let digits = romans[word] else { continue }
            if ambiguousRomans.contains(word) {
                guard i > 0, takesNumeral.contains(words[i - 1]) else { continue }
            }
            out[i] = digits
        }
        return out
    }

    /// The same word, allowing for how it ends: plurals, -ic/-ia, -al, -ed,
    /// -ing, and the endings one condition is said with - "infarct" and
    /// "infarction", "embolus" and "embolism", "hypertensive" and
    /// "hypertension", "thrombosis" and "thrombotic". "Hypertension" is not
    /// "hyperthyroidism", and "carcinoma" is not "carcinoid", because only
    /// endings are forgiven.
    static func close(_ said: String, _ wanted: String) -> Bool {
        if said == wanted { return true }
        guard said.count >= 4, wanted.count >= 4 else { return false }
        return stem(said) == stem(wanted)
    }

    static func stem(_ word: String) -> String {
        // the longer endings first, so "necrotic" loses "-otic", not "-ic"
        let endings: [String] = ["osis", "otic", "ism", "ion", "ive",
                                 "ies", "es", "us", "um", "s", "ic", "ia", "al", "ed", "ing", "y", "a", "e", "i"]
        var out = word
        var changed = true
        // ending by ending, so "kidneys" and "kidney" come to the same stem
        while changed {
            changed = false
            for ending in endings where out.hasSuffix(ending) && out.count - ending.count >= 4 {
                out = String(out.dropLast(ending.count))
                changed = true
                break
            }
        }
        return out
    }

    /// A word said with the opposite prefix of one wanted: "indirect" for
    /// "direct", "hypokalaemia" for "hyperkalaemia", "atypical" for
    /// "typical" - the answer's opposite, not a near miss.
    static func contradicts(_ said: Set<String>, _ wanted: Set<String>) -> Bool {
        let negations = ["in", "non", "un", "dis", "a", "an", "anti", "ir", "im"]
        let pairs: [(String, String)] = [("hyper", "hypo"), ("hypo", "hyper")]
        // a wanted word whose opposite was said instead of it
        for w in wanted {
            guard let opposite = opposites[w], said.contains(opposite), !said.contains(w) else { continue }
            return true
        }
        // a wanted word not said, but a different word with most of its
        // letters was: "carcinoid" for "carcinoma" is another answer, not a
        // mishearing of the same one
        for w in wanted where w.count >= 6 && !said.contains(where: { close($0, w) }) {
            for s in said where s.count >= 6 && !wanted.contains(s) {
                let shared = zip(w, s).prefix { $0 == $1 }.count
                if shared >= 6 && Double(shared) >= 0.7 * Double(min(w.count, s.count)) { return true }
            }
        }
        for w in wanted where w.count >= 4 {
            for s in said where s != w && !wanted.contains(s) {
                for p in negations where s == p + w || w == p + s { return true }
                for (x, y) in pairs where w.hasPrefix(x) && s.hasPrefix(y)
                    && stem(String(w.dropFirst(x.count))) == stem(String(s.dropFirst(y.count))) {
                    return true
                }
            }
        }
        return false
    }

    /// Words whose opposite is a different answer: the right coronary artery
    /// is not the left one.
    private static let opposites: [String: String] = {
        let pairs: [(String, String)] = [
            ("left", "right"), ("upper", "lower"), ("medial", "lateral"), ("anterior", "posterior"),
            ("superior", "inferior"), ("proximal", "distal"), ("high", "low"),
            ("increased", "decreased"), ("raised", "lowered"), ("positive", "negative"),
            ("systolic", "diastolic"), ("benign", "malignant"), ("central", "peripheral"),
            ("sensory", "motor"), ("afferent", "efferent"), ("internal", "external"),
            ("flexion", "extension"), ("adduction", "abduction"), ("dorsal", "ventral"),
        ]
        var out: [String: String] = [:]
        for (x, y) in pairs {
            out[x] = y
            out[y] = x
        }
        return out
    }()

    /// Numbers written as digits, and the number words a recogniser may
    /// write instead, as digits.
    private static func numbers(in text: String) -> Set<String> {
        let words: [String: String] = [
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11",
            "twelve": "12", "twenty": "20", "thirty": "30", "forty": "40", "fifty": "50", "hundred": "100",
        ]
        var out = Set(text.split { !$0.isNumber && $0 != "." }.map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty && $0.contains(where: \.isNumber) })
        let said: [String] = tokens(text)
        for word in said {
            if let digit = words[word] { out.insert(digit) }
        }
        // "Type II", "CN VII": a numeral is a number too
        for (word, converted) in zip(said, arabic(said)) where converted != word {
            out.insert(converted)
        }
        return out
    }

    /// Something said to the app rather than an answer.
    enum Command { case skip, again, dontKnow, pause }

    static func command(in heard: String) -> Command? {
        let said = heard.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if ["skip", "next", "skip it", "next one", "pass"].contains(said) { return .skip }
        if ["repeat", "again", "say again", "say that again", "repeat that", "what"].contains(said) { return .again }
        if ["pause", "stop", "wait"].contains(said) { return .pause }
        if said.contains("don't know") || said.contains("dont know") || said.contains("no idea")
            || said == "not sure" || said == "i give up" { return .dontKnow }
        return nil
    }

    /// The first sentence, short enough to say in one breath: an explanation
    /// read in full while driving is an explanation nobody hears the end of.
    static func firstSentence(_ text: String, limit: Int = 180) -> String {
        let plain = Highlight.plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
        var cut = plain
        if let end = plain.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            cut = String(plain[..<end.upperBound])
        }
        if cut.count > limit {
            let prefix = cut.prefix(limit)
            cut = (prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? String(prefix)) + "\u{2026}"
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A station whose marks are for talking rather than finding: breaking bad
    /// news, explaining, consenting, counselling. These are also marked against
    /// SPIKES.
    static func isCommunicationStation(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["bad news", "breaking", "break news", "spikes", "explain", "explaining",
                "counsel", "consent", "communicat", "discuss", "angry", "complaint",
                "inform", "procedure", "reassur", "breaking news", "dnacpr", "resuscitation status",
                "death", "bereave", "cancer diagnosis", "difficult conversation", "error", "apolog"]
            .contains { t.contains($0) }
    }

    /// The six SPIKES stages, in order, as the marker is told them.
    static let spikes: [(key: String, name: String, meaning: String)] = [
        ("S", "Setting", "private setting, introduces self, sits down, checks who should be present, avoids interruptions"),
        ("P", "Perception", "asks what the patient already knows or suspects"),
        ("I", "Invitation", "asks how much the patient wants to know"),
        ("K", "Knowledge", "warning shot, then gives the news clearly in plain words, in small chunks, without jargon"),
        ("E", "Emotions", "acknowledges and responds to emotion with empathy, allows silence"),
        ("S2", "Strategy and summary", "summarises, agrees a plan, checks understanding, offers support and follow-up"),
    ]
}

/// Numbers in a model's marks, read as a person would: "3/5" is 3 out of 5,
/// not 35, and "72/100" is 72, not 72100.
enum MarkNumber {
    /// Every number in the text, in order: "3/5" is 3 and 5, "72.5%" is 72.5.
    static func numbers(in text: String) -> [Double] {
        var out: [Double] = []
        var current = ""
        for ch in text + " " {
            if ch.isNumber || (ch == "." && !current.isEmpty && !current.contains(".")) {
                current.append(ch)
            } else {
                let digits: String = current.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if let value = Double(digits) { out.append(value) }
                current = ""
            }
        }
        return out
    }

    /// The first number, rounded: "4/5" is 4, "Step 2" is 2.
    static func first(in text: String) -> Int? {
        numbers(in: text).first.map { Int($0.rounded()) }
    }

    /// A score out of 100: "72", "72.5", "72%", "72/100", "8/10".
    static func percent(from text: String) -> Int? {
        let parts = numbers(in: text)
        guard let value = parts.first else { return nil }
        if text.contains("/"), parts.count >= 2, parts[1] > 0 {
            return Int((value / parts[1] * 100).rounded())
        }
        return Int(value.rounded())
    }
}
