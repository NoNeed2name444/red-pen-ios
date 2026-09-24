import Foundation

/// The model's side of the spoken modes: marking an explanation, turning what
/// was missed into cards, playing a station's patient, and marking a station.
///
/// Every prompt asks for JSON and every reply is read tolerantly - models wrap
/// JSON in prose, reason before it, and write numbers as strings - so a reply
/// that is nearly right still counts.
enum VoiceMarking {

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "The marker's answer couldn't be read. Try again - or choose a larger model in AI models."
        }
    }

    // MARK: explain it back

    /// Marks a spoken explanation against the lecture text it should match.
    static func markExplanation(topic: String, transcript: String, notes: String?,
                                using backend: LLMBackend) async throws -> ExplainResult {
        let budget = backend.promptBudgetChars
        let spoken = String(transcript.prefix(max(800, budget / 3)))
        var notesPart = AccuracyChecker.noSourceNote
        if let notes, !notes.isEmpty {
            notesPart = "LECTURE NOTES (mark against these):\n" + String(notes.prefix(max(1200, budget / 2)))
        }
        let prompt = """
        You are a medical school examiner. A student has explained "\(topic)" out loud, and it was turned into text by speech recognition, so ignore misheard words, filler and repetition.

        \(notesPart)

        THE STUDENT'S EXPLANATION:
        \(spoken)

        Compare the explanation with the notes and list:
        - covered: the key points the student explained correctly, as short phrases.
        - missed: important points from the notes the student left out, each a short self-contained fact.
        - wrong: anything the student said that is incorrect, each written as "You said ...; in fact ...".
        - score: 0 to 100, for how completely and correctly the topic was explained.
        - oneTip: the single most useful thing to do differently next time, in one sentence.

        Answer with JSON only:
        {"covered":["..."],"missed":["..."],"wrong":["..."],"score":0,"oneTip":"..."}
        """
        let reply = try await ask(prompt, using: backend, maxTokens: 1000)
        guard let data = LLMText.jsonObject(in: reply),
              let result = try? JSONDecoder().decode(ExplainResult.self, from: data) else {
            throw Failure.unreadable
        }
        return result
    }

    /// One question-and-answer card per point, worded to be learnt.
    ///
    /// A missed point is a statement ("the posterior wall is transversalis
    /// fascia"), and a card needs a question; the model writes it. If it
    /// can't, the point still becomes a card, asked plainly.
    static func cards(from points: [String], topic: String, using backend: LLMBackend?) async -> [AnkiCard] {
        let points = points.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !points.isEmpty else { return [] }
        let tag = "Explain it back: \(topic)"
        if let backend {
            let numbered = points.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            let prompt = """
            Turn each point below into one flashcard for a medical student revising "\(topic)". The question must make sense on its own and have one clear answer; the answer is a short phrase, not a sentence.

            POINTS:
            \(numbered)

            Answer with JSON only: {"cards":[{"q":"...","a":"..."}]}
            """
            if let reply = try? await ask(prompt, using: backend, maxTokens: 900),
               let data = LLMText.jsonObject(in: reply),
               let made = try? JSONDecoder().decode(MadeCards.self, from: data) {
                let cards = made.cards
                    .filter { !$0.q.trimmingCharacters(in: .whitespaces).isEmpty && !$0.a.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { AnkiCard(type: .qa, front: $0.q, bullets: [$0.a], source: tag) }
                if !cards.isEmpty { return cards }
            }
        }
        return points.map {
            AnkiCard(type: .qa, front: "\(topic): what is this key point you left out?", bullets: [$0], source: tag)
        }
    }

    private struct MadeCards: Decodable {
        struct Pair: Decodable { var q: String; var a: String }
        var cards: [Pair]
    }

    // MARK: the spoken station

    /// The patient's (or relative's) next line, played from the station's
    /// mark sheet.
    static func patientReply(title: String, steps: [String], lines: [SpokenLine],
                             using backend: LLMBackend) async throws -> String {
        let communication = SpokenAnswer.isCommunicationStation(title)
        let script = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let manner = communication
            ? "- This is a communication station: react as a real person would to what you are told - worry, shock, anger, silence, questions - and only settle when the student responds to how you feel."
            : "- If the student asks to examine you, say they may, and let the examiner give findings."
        let system = """
        You are a simulated patient (or the relative the station describes) in an OSCE station, talking to a medical student. Stay in character throughout.

        STATION: \(title)
        THE EXAMINER'S MARK SHEET (secret - never read it out, list it or hint at what earns marks):
        \(script)

        - Invent a realistic, consistent person and story that fits this station, and keep to it.
        - Answer only what you are asked, in everyday words, in one to three short spoken sentences. No stage directions, no lists, no markdown.
        - Never volunteer the diagnosis or information you weren't asked for.
        \(manner)
        """
        var turns: [ChatTurn] = [.system(system)]
        for line in lines.suffix(20) {
            switch line.speaker {
            case .student: turns.append(.user(line.text))
            case .patient: turns.append(.assistant(line.text))
            case .examiner: continue
            }
        }
        if turns.last?.role != .user { turns.append(.user("(The student waits for you to speak.)")) }
        if backend.isOnDevice { turns = LLMText.noThinking(turns) }
        let reply = LLMText.stripThinking(try await backend.complete(turns, maxTokens: 180, temperature: 0.7))
        let clean = reply.replacingOccurrences(of: #"\*[^*]*\*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LLMError.emptyReply }
        return clean
    }

    /// Marks the student's side of a spoken station against its checklist,
    /// and - for a communication station - against SPIKES.
    static func markStation(title: String, steps: [String], lines: [SpokenLine],
                            using backend: LLMBackend) async throws -> StationMark {
        let communication = SpokenAnswer.isCommunicationStation(title)
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let transcript = lines.map { line -> String in
            switch line.speaker {
            case .student: return "STUDENT: \(line.text)"
            case .patient: return "PATIENT: \(line.text)"
            case .examiner: return "EXAMINER: \(line.text)"
            }
        }.joined(separator: "\n")
        var spikesPart = ""
        if communication {
            let stages = SpokenAnswer.spikes.map { "\($0.key) (\($0.name)): \($0.meaning)" }.joined(separator: "\n")
            spikesPart = "\n\nThis is a communication station, so also mark SPIKES. For each stage say whether the student did it:\n" + stages
        }
        let transcriptPart = String(transcript.prefix(max(2000, backend.promptBudgetChars - 2500)))
        let spikesShape = communication ? #","spikes":{"S":true,"P":false,"I":false,"K":true,"E":false,"S2":false}"# : ""
        let prompt = """
        You are an OSCE examiner marking a medical student's station from a transcript made by speech recognition (ignore misheard words).

        STATION: \(title)
        CHECKLIST:
        \(numbered)

        TRANSCRIPT:
        \(transcriptPart)

        For each checklist step, decide whether the student did it (the meaning, not the exact words). Give communication a mark from 1 (poor) to 5 (excellent) for clarity, empathy, avoiding jargon and checking understanding. Write feedback of two or three sentences: what went well, and the most important thing to improve.\(spikesPart)

        Answer with JSON only, listing checklist step numbers:
        {"done":[1,2],"missed":[3],"communication":3,"feedback":"..."\(spikesShape)}
        """
        let reply = try await ask(prompt, using: backend, maxTokens: 900)
        guard let data = LLMText.jsonObject(in: reply),
              let raw = try? JSONDecoder().decode(RawStationMark.self, from: data) else {
            throw Failure.unreadable
        }
        let done = Set(raw.done.map { $0 - 1 }.filter { steps.indices.contains($0) }).sorted()
        return StationMark(done: done,
                           missedNotes: raw.missedNotes,
                           communication: min(5, max(1, raw.communication)),
                           feedback: raw.feedback,
                           spikes: communication ? raw.spikes : nil)
    }

    /// The station marks as a model writes them: step numbers from 1, and
    /// anything in any shape.
    private struct RawStationMark: Decodable {
        var done: [Int] = []
        var missedNotes: [String] = []
        var communication = 3
        var feedback = ""
        var spikes: [String: Bool]?

        enum CodingKeys: String, CodingKey { case done, missed, communication, feedback, spikes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            done = Self.numbers(c, .done)
            // "missed" may be numbers (already implied by done) or notes
            missedNotes = (try? c.decodeIfPresent([String].self, forKey: .missed))?
                .filter { Int($0) == nil } ?? []
            if let whole = try? c.decodeIfPresent(Int.self, forKey: .communication) {
                communication = whole
            } else if let real = try? c.decodeIfPresent(Double.self, forKey: .communication) {
                communication = Int(real.rounded())
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .communication) {
                communication = Int(text.filter(\.isNumber)) ?? 3
            }
            feedback = (try? c.decodeIfPresent(String.self, forKey: .feedback)) ?? ""
            if let flags = try? c.decodeIfPresent([String: Bool].self, forKey: .spikes) {
                spikes = flags
            } else if let scores = try? c.decodeIfPresent([String: Int].self, forKey: .spikes) {
                spikes = scores.mapValues { $0 > 0 }
            }
        }

        private static func numbers(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Int] {
            if let ints = try? c.decodeIfPresent([Int].self, forKey: key) { return ints }
            if let texts = try? c.decodeIfPresent([String].self, forKey: key) {
                return texts.compactMap { Int($0.filter(\.isNumber)) }
            }
            return []
        }
    }

    // MARK: asking

    private static func ask(_ prompt: String, using backend: LLMBackend, maxTokens: Int) async throws -> String {
        var turns: [ChatTurn] = [.user(prompt)]
        if backend.isOnDevice { turns = LLMText.noThinking(turns) }
        return LLMText.stripThinking(try await backend.complete(turns, maxTokens: maxTokens, temperature: 0.2))
    }
}
