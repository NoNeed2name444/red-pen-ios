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

    /// Words the recogniser writes for each letter, first to last.
    private static let spellings: [[String]] = [
        ["a", "ay", "eh", "alpha", "1", "one"],
        ["b", "be", "bee", "bea", "bravo", "2", "two"],
        ["c", "see", "sea", "si", "charlie", "3", "three"],
        ["d", "dee", "delta", "4", "four"],
        ["e", "ee", "echo", "5", "five"],
    ]

    /// Which option was chosen, if one can be told from what was said.
    static func option(in heard: String, options: [String]) -> Int? {
        let tokens = heard.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let count = min(options.count, letters.count)
        // "a" and "one" are also ordinary words ("it's a...", "the one with"),
        // so they count only when nothing plainer was said
        let ambiguous: Set<String> = ["a", "one"]
        for token in tokens where !ambiguous.contains(token) {
            if let index = spellings.firstIndex(where: { $0.contains(token) }), index < count { return index }
        }
        if count > 0, tokens.contains(where: { ambiguous.contains($0) }) { return 0 }
        // no letter at all: the option whose words were said
        let said = CardQuality.terms(heard)
        guard !said.isEmpty else { return nil }
        let scored = options.prefix(count).enumerated().map { ($0.offset, CardQuality.terms($0.element).intersection(said).count) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        // two options equally matched is not an answer
        return scored.filter { $0.1 == best.1 }.count == 1 ? best.0 : nil
    }

    /// Whether a spoken answer to a card has the card's answer in it.
    ///
    /// Generous on purpose - most of the answer's meaningful words, with a
    /// little slack for plurals and endings - because the recogniser mangles
    /// drug names and a student who said the right thing must not be marked
    /// down for the phone's hearing. A number in the answer has to be said.
    static func matches(_ heard: String, answer: [String]) -> Bool {
        let expected = answer.map(Highlight.plain).joined(separator: " ")
        let said = CardQuality.terms(heard)
        let saidNumbers = numbers(in: heard)
        let wanted = CardQuality.terms(expected)
        let wantedNumbers = numbers(in: expected)
        if !wantedNumbers.isEmpty, wantedNumbers.isDisjoint(with: saidNumbers) { return false }
        guard !wanted.isEmpty else {
            if !wantedNumbers.isEmpty { return true }
            let plainAnswer = expected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return !plainAnswer.isEmpty && heard.lowercased().contains(plainAnswer)
        }
        let hits = wanted.filter { word in
            said.contains(word) || said.contains { $0.hasPrefix(String(word.prefix(5))) && word.count > 5 }
        }
        let needed = answer.count > 1 ? 0.4 : 0.5
        return Double(hits.count) / Double(wanted.count) >= needed
    }

    private static func numbers(in text: String) -> Set<String> {
        Set(text.split { !$0.isNumber && $0 != "." }.map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty && $0.contains(where: \.isNumber) })
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
