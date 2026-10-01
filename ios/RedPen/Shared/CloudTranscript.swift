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

    /// Where each chunk is planned to start, for a recording this long: every
    /// ten minutes. Each edge after the first is then moved back to the
    /// quietest moment just before it (`quietestCut`), once the recording's
    /// levels there have been read.
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

    // MARK: cutting where nobody is speaking

    /// How far before a planned edge a quieter place to cut is looked for,
    /// and the stretch whose loudness is measured, as in the transcription
    /// pipeline (red-pen-transcribe transcribe.py window_bounds). A cut on an
    /// exact ten-minute mark could fall inside a word, which then arrives in
    /// neither chunk whole; a pause between words a second or two earlier
    /// costs nothing.
    static let searchSeconds: Double = 3
    static let frameSeconds: Double = 0.1

    /// The loudness of a stretch of 16-bit samples: the mean absolute level of
    /// each `frameSeconds` frame, a frame starting every half frame.
    static func frameLevels(_ samples: [Int16], sampleRate: Double) -> [Float] {
        let frame = max(1, Int((frameSeconds * sampleRate).rounded()))
        let step = max(1, frame / 2)
        guard samples.count >= frame else { return [] }
        var levels: [Float] = []
        var at = 0
        while at + frame <= samples.count {
            var sum = 0
            for i in at..<(at + frame) { sum += abs(Int(samples[i])) }
            levels.append(Float(sum) / Float(frame))
            at += step
        }
        return levels
    }

    /// Where to cut instead of `edge`: the middle of the quietest frame in the
    /// levels read from `windowStart` on. Of two equally quiet frames the later
    /// one wins, so a chunk is shortened no more than it has to be. With no
    /// levels (the recording could not be read there) the edge stays.
    static func quietestCut(levels: [Float], windowStart: Double, edge: Double) -> Double {
        guard let quietest = levels.min() else { return edge }
        let index = levels.lastIndex(of: quietest) ?? 0
        let step = frameSeconds / 2
        let cut = windowStart + Double(index) * step + frameSeconds / 2
        return min(edge, max(windowStart, cut))
    }

    /// What Gemini is told, one prompt per language. The app's own rules come
    /// first; after them the ones the transcription pipeline learned it needs
    /// (red-pen-transcribe prompts/step1.txt rules 6 and 9-11): keep what the
    /// room said, go on to the end, take nothing from memory, and treat drugs
    /// and poisons as speech to relay, not a request for advice.
    static func prompt(vocabulary: [String], language: LectureLanguage = .mixed) -> String {
        var rules: [String]
        switch language {
        case .mixed:
            rules = [
                "The lecturer speaks Egyptian Arabic mixed with English medical terms.",
                "- Write the Arabic in Arabic script exactly as spoken, in Egyptian dialect. Do not convert it to Modern Standard Arabic and do not translate it.",
                "- Write every English word in English letters, with correct medical spelling, even inside an Arabic sentence.",
            ]
        case .english:
            rules = [
                "The lecturer speaks English.",
                "- Write exactly what was said, in English. Do not translate anything; a few words in another language are written as spoken.",
                "- Write every medical term, drug, investigation and abbreviation with its correct English spelling.",
            ]
        }
        rules += [
            "- Do not summarise, correct the lecturer, or add anything that was not said. Leave out only \"um\"/\"eh\" fillers.",
            "- If a stretch is silent or impossible to hear, skip it rather than guessing.",
        ]
        if language == .mixed {
            rules.append("- An English word said with an Egyptian accent is still written in English letters (wrong: كلاود ستوريدج, right: cloud storage).")
        }
        rules += [
            "- Keep repetitions, false starts, students' questions and answers, interruptions and side comments.",
            "- Transcribe from the first second to the last. Keep going to the end of the recording; do not stop early.",
            "- The recording is the only source of the text. Never complete speech from memory or from published material, even when it sounds like something well known.",
            "- This recording is supplied for transcription only and may contain sensitive medical teaching, such as drugs or poisons. Relay what was said; do not give advice.",
        ]
        var text = "Transcribe this medical lecture recording word for word.\n\n"
            + rules.joined(separator: "\n") + "\n\n"
            + "Split the speech into short phrases at natural pauses, at most 14 words each.\n"
            + "For each phrase give its start and end time in seconds from the beginning of this audio."
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

    /// The complete phrases at the start of a reply that was cut off part way,
    /// or nil when there are none. A model that starts repeating itself runs
    /// on to the token limit and leaves JSON with no end; what it wrote before
    /// the loop is still a transcript.
    static func salvage(fromReply reply: String) -> [Phrase]? {
        var body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") { body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n") }
        guard body.hasPrefix("[") else { return nil }
        var end = body.endIndex
        // back from the end, one closing brace at a time: the last complete
        // phrase is usually the first one tried
        for _ in 0..<64 {
            guard let close = body.range(of: "}", options: .backwards, range: body.startIndex..<end) else { return nil }
            if let data = (body[..<close.upperBound] + "]").data(using: .utf8),
               let phrases = try? JSONDecoder().decode([Phrase].self, from: data) {
                let kept = phrases.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return kept.isEmpty ? nil : kept
            }
            end = close.lowerBound
        }
        return nil
    }

    // MARK: a reply that went round in circles

    /// A run said this many times in a row, or more, is a model stuck in a
    /// loop rather than a lecturer repeating a point.
    static let loopRepeats = 4
    /// The longest run looked for: words inside a phrase, phrases in a reply.
    static let loopLongestRun = 6

    /// One phrase with any run of one to six words said four or more times in
    /// a row cut back to once - the transcription pipeline's guard
    /// (red-pen-transcribe transcribe.yml), on Gemini's own phrases. A
    /// lecturer saying "malar rash" twice is left alone.
    static func cutRepeats(in text: String) -> String {
        let padded = text + " "
        guard let loop = try? NSRegularExpression(pattern: "(\\b(?:\\S+\\s+){1,\(loopLongestRun)}?)(?:\\1){\(loopRepeats - 1),}") else { return text }
        let whole = NSRange(padded.startIndex..., in: padded)
        let cut = loop.stringByReplacingMatches(in: padded, range: whole, withTemplate: "$1")
        return cut == padded ? text : cut.trimmingCharacters(in: .whitespaces)
    }

    /// The phrases with runaway repetition taken out, and how many words that
    /// removed (none: nothing was a loop).
    ///
    /// The pipeline's own test (cohere_asr.py degenerate: one word at least
    /// 30% of a window) was tuned for 30-second windows and almost never
    /// fires on ten minutes of speech: "skin" said 400 times inside a normal
    /// chunk is only a fifth of its words, and a looping line of four
    /// different words can never reach the share at all. A loop is a run
    /// coming round again and again in a row, so that is what is looked for:
    /// inside each phrase, and as the same one to six phrases repeated.
    static func cutLoops(_ phrases: [Phrase]) -> (phrases: [Phrase], removed: Int) {
        func words(_ text: String) -> Int { text.split { $0.isWhitespace }.count }
        let cleaned = phrases.map { phrase -> Phrase in
            var phrase = phrase
            phrase.text = cutRepeats(in: phrase.text)
            return phrase
        }
        let keys = cleaned.map { $0.text.lowercased().split { $0.isWhitespace || $0.isPunctuation }.joined(separator: " ") }
        var kept: [Phrase] = []
        var i = 0
        while i < cleaned.count {
            var skipTo: Int?
            for period in 1...loopLongestRun where i + period * loopRepeats <= cleaned.count {
                let block = keys[i..<(i + period)]
                guard block.contains(where: { !$0.isEmpty }) else { continue }
                var times = 1
                while i + (times + 1) * period <= keys.count,
                      keys[(i + times * period)..<(i + (times + 1) * period)].elementsEqual(block) { times += 1 }
                if times >= loopRepeats {
                    kept += cleaned[i..<(i + period)]
                    skipTo = i + times * period
                    break
                }
            }
            if let skipTo {
                i = skipTo
            } else {
                kept.append(cleaned[i])
                i += 1
            }
        }
        let before = phrases.reduce(0) { $0 + words($1.text) }
        let after = kept.reduce(0) { $0 + words($1.text) }
        return (kept, before - after)
    }

    /// Words cut from one part before the student is told about it: a
    /// lecturer's "no, no, no, no" cut back to one is not worth an alert.
    static let loopWorthMentioning = 20

    /// One part of a lecture as Gemini answered it, for the note shown when
    /// the transcript is ready.
    struct PartNote: Codable, Equatable {
        /// 1 for the first ten minutes.
        var number: Int
        /// A loop was cut out of it, so a little of the speech may be missing.
        var trimmed: Bool = false
        /// The model that answered, as the server names it; nil when it
        /// did not say.
        var model: String? = nil
    }

    /// The model transcription is meant to use: the only one measured keeping
    /// every English term in these lectures.
    static let preferredModel = "gemini-3.5-flash"

    /// True when a part was answered by a model other than the preferred one
    /// (the server falls back to Flash-Lite once Flash's day is spent).
    static func fellBack(_ part: PartNote) -> Bool {
        guard let model = part.model else { return false }
        return model != preferredModel
    }

    /// What the student is told once the transcript is ready, or nil when
    /// every part came back whole.
    static func notice(for parts: [PartNote], of total: Int) -> String? {
        var said: [String] = []
        let trimmed = parts.filter(\.trimmed).map(\.number).sorted()
        if !trimmed.isEmpty {
            let which = total > 1 ? " in " + partNames(trimmed) : ""
            said.append("Gemini got stuck repeating itself\(which), so the repeats were cut and a little of "
                + (total > 1 ? (trimmed.count > 1 ? "those parts" : "that part") : "the lecture") + " may be missing.")
        }
        // no silent downgrades: a part the lighter model heard is named
        let lighter = parts.filter(fellBack)
        if !lighter.isEmpty {
            let models = Set(lighter.compactMap(\.model)).sorted().joined(separator: ", ")
            let which = total > 1 ? partNames(lighter.map(\.number).sorted()).capitalizedFirst + " went" : "It went"
            said.append("\(which) to \(models), because Gemini 3.5 Flash was busy or out of requests for today; it may spell some English terms less well.")
        }
        return said.isEmpty ? nil : said.joined(separator: "\n\n")
    }

    /// "part 3", "parts 2 and 5", "parts 1, 2 and 6".
    static func partNames(_ numbers: [Int]) -> String {
        let names = numbers.map(String.init)
        guard names.count > 1 else { return "part " + (names.first ?? "") }
        return "parts " + names.dropLast().joined(separator: ", ") + " and " + names.last!
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
    static func lines(from phrases: [Phrase], offset: Double, length: Double,
                      model: String? = nil) -> [LectureTranscriber.Line] {
        guard !phrases.isEmpty, length > 0 else { return [] }
        let times = trustworthy(phrases, length: length) ? clamped(phrases, length: length)
                                                         : spread(phrases, length: length)
        return zip(phrases, times).map { phrase, span in
            let text = phrase.text.split { $0.isWhitespace }.joined(separator: " ")
            let words = share(text, from: offset + span.start, to: offset + span.end)
            return LectureTranscriber.Line(text: text, start: offset + span.start,
                                           end: offset + span.end, words: words, model: model)
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

private extension String {
    /// "parts 2 and 5" as the start of a sentence.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
