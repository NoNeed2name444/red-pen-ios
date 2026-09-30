import Foundation

/// Everything about Gemini transcription that is a decision rather than a
/// network call: what the model is asked, what it is told to expect, and how
/// its answer becomes timed lines the Narrate player can follow.
///
/// Foundation only, so it runs in the Swift tests without a recording, a key
/// or a connection.
enum CloudTranscript {

    /// One phrase as Gemini reports it, seconds from the start of its chunk.
    struct Phrase: Codable, Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    /// Ten minutes of 32 kbps mono audio is about 2.4 MB, 3.2 MB once
    /// base64'd: well inside the 7 MB a single inline file may be, and short
    /// enough that one failed request costs ten minutes, not the lecture.
    static let chunkSeconds: Double = 600

    /// Where each chunk starts, for a recording this long.
    static func chunkStarts(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        var starts: [Double] = []
        var at = 0.0
        while at < duration {
            starts.append(at)
            at += chunkSeconds
        }
        // a last sliver of a few seconds is folded into the chunk before it:
        // a phrase cut in half at the very end is worse than a longer chunk
        if starts.count > 1, duration - starts[starts.count - 1] < 20 { starts.removeLast() }
        return starts
    }

    static func prompt(vocabulary: [String]) -> String {
        var text = """
        Transcribe this medical lecture recording word for word.

        The lecturer speaks Egyptian Arabic mixed with English medical terms.
        - Write the Arabic in Arabic script exactly as spoken, in Egyptian dialect. Do not convert it to Modern Standard Arabic and do not translate it.
        - Write every English word in English letters, with correct medical spelling, even inside an Arabic sentence.
        - Do not summarise, correct the lecturer, or add anything that was not said. Leave out only "um"/"eh" fillers.
        - If a stretch is silent or impossible to hear, skip it rather than guessing.

        Split the speech into short phrases at natural pauses, at most 14 words each.
        For each phrase give its start and end time in seconds from the beginning of this audio.
        """
        if !vocabulary.isEmpty {
            text += "\n\nTerms from this lecture's slides, spelled as they should be written: "
                + vocabulary.joined(separator: ", ") + "."
        }
        return text
    }

    /// The structured answer asked for, so the reply is JSON and nothing else.
    static let responseSchema: [String: Any] = [
        "type": "ARRAY",
        "items": [
            "type": "OBJECT",
            "properties": [
                "start": ["type": "NUMBER"],
                "end": ["type": "NUMBER"],
                "text": ["type": "STRING"],
            ],
            "required": ["start", "end", "text"],
        ],
    ]

    /// Words from the lecture's own slides worth telling the model about:
    /// long, Latin-script and repeated, which is what a medical term on a
    /// slide looks like. The common list fills any room left.
    static func vocabulary(from texts: [String], extra: [String] = [], limit: Int = 80) -> [String] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for text in texts {
            for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                guard word.count >= 6, word.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
                let key = word.lowercased()
                if stopWords.contains(key) { continue }
                counts[key, default: 0] += 1
                if spelling[key] == nil || word.first?.isUppercase == false { spelling[key] = word }
            }
        }
        var picked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { spelling[$0.key] ?? $0.key }
        for word in extra where !picked.contains(where: { $0.lowercased() == word.lowercased() }) {
            picked.append(word)
        }
        return Array(picked.prefix(limit))
    }

    private static let stopWords: Set<String> = [
        "because", "between", "patient", "patients", "should", "within", "without",
        "during", "following", "including", "however", "usually", "important",
    ]

    // MARK: reading the answer

    /// The phrases in Gemini's reply, or nil when it is not the JSON asked for.
    static func phrases(fromReply reply: String) -> [Phrase]? {
        var body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        // a fenced answer despite the schema still counts
        if body.hasPrefix("```") {
            body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let fence = body.range(of: "```", options: .backwards) { body = String(body[..<fence.lowerBound]) }
        }
        guard let data = body.data(using: .utf8),
              let phrases = try? JSONDecoder().decode([Phrase].self, from: data) else { return nil }
        return phrases.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Phrases as timed lines on the recording's own clock.
    ///
    /// Gemini's times are close but not exact, and now and then nonsense - all
    /// zero, running backwards, past the end of the chunk. Times that can be
    /// trusted are kept (clamped into order and into the chunk); when they
    /// cannot, the chunk's length is shared out by how much text each phrase
    /// has, which is how long it took to say to within a second or two.
    /// Word times inside a line are shared out the same way, so the highlight
    /// moves a word at a time rather than a line at a time.
    static func lines(from phrases: [Phrase], offset: Double, length: Double) -> [LectureTranscriber.Line] {
        guard !phrases.isEmpty, length > 0 else { return [] }
        let times = trustworthy(phrases, length: length) ? clamped(phrases, length: length)
                                                         : spread(phrases, length: length)
        return zip(phrases, times).map { phrase, span in
            let text = phrase.text.split { $0.isWhitespace }.joined(separator: " ")
            let words = share(text, from: offset + span.start, to: offset + span.end)
            return LectureTranscriber.Line(text: text, start: offset + span.start,
                                           end: offset + span.end, words: words)
        }
    }

    /// Times are usable when they mostly move forward, stay inside the chunk,
    /// and are not all piled at zero.
    static func trustworthy(_ phrases: [Phrase], length: Double) -> Bool {
        guard phrases.count > 1 else { return phrases.first.map { $0.end > $0.start } ?? false }
        let inside = phrases.filter { $0.start >= 0 && $0.end <= length + 5 && $0.end >= $0.start }.count
        var forward = 0
        for i in 1..<phrases.count where phrases[i].start >= phrases[i - 1].start { forward += 1 }
        let lastEnd = phrases.map(\.end).max() ?? 0
        return Double(inside) >= Double(phrases.count) * 0.9
            && Double(forward) >= Double(phrases.count - 1) * 0.9
            && lastEnd > 0.5 && Set(phrases.map(\.start)).count > 1
    }

    private static func clamped(_ phrases: [Phrase], length: Double) -> [(start: Double, end: Double)] {
        var result: [(start: Double, end: Double)] = []
        var floor = 0.0
        for phrase in phrases {
            let start = min(max(phrase.start, floor), length)
            let end = min(max(phrase.end, start + 0.3), length)
            result.append((start, max(end, start)))
            floor = start
        }
        return result
    }

    private static func spread(_ phrases: [Phrase], length: Double) -> [(start: Double, end: Double)] {
        let weights = phrases.map { Double(max(1, $0.text.count)) }
        let total = weights.reduce(0, +)
        var at = 0.0
        return weights.map { weight in
            let span = length * weight / total
            defer { at += span }
            return (at, at + span)
        }
    }

    private static func share(_ text: String, from start: Double, to end: Double) -> [LectureTranscriber.SpokenWord] {
        let words = text.split { $0.isWhitespace }.map(String.init)
        guard !words.isEmpty else { return [] }
        let weights = words.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        let span = max(0, end - start)
        var at = start
        return zip(words, weights).map { word, weight in
            let duration = span * weight / total
            defer { at += duration }
            return LectureTranscriber.SpokenWord(text: word, start: at, duration: duration)
        }
    }

    /// "ar" when most of the letters in a line are Arabic, for the reading
    /// pace and the right-to-left layout.
    static func language(of text: String) -> String {
        var arabic = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: arabic += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        return arabic >= latin && arabic > 0 ? "ar" : "en"
    }
}
