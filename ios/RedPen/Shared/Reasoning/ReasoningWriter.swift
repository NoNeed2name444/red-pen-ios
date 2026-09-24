import Foundation

/// Writes the Reasoning tools' material with whichever writer is chosen in AI
/// models, the same way the other lecture writers do: the lecture a window at
/// a time, a few items per call, JSON asked for and read tolerantly, and a
/// stop when several calls in a row bring nothing new.
enum ReasoningWriter {

    // MARK: what to write from

    /// The set's lectures if it kept any with words in them - they are the
    /// whole of what was taught - and otherwise the set's own content.
    static func source(of set: StudySet) -> String {
        let lectures = set.sources
            .flatMap { $0.pages }
            .filter { !$0.isBlank }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lectures.isEmpty { return lectures.joined(separator: "\n\n") }
        return ModeConversion.sourceText(of: set)
    }

    // MARK: the three writers

    static func cases(source: String, count: Int, subject: String, exam: ExamTrack,
                      using backend: LLMBackend,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> [ClueCase] {
        try await collect(count: count, perCall: backend.isOnDevice ? 2 : 5, tokensEach: 800,
                          source: source, backend: backend, onProgress: onProgress,
                          key: { $0.diagnosis + " | " + ($0.clues.prefix(2).joined(separator: " ")) },
                          prompt: { n, already, text in
                              casesPrompt(count: n, subject: subject, exam: exam, already: already, source: text)
                          },
                          parse: parseCases)
    }

    static func duels(source: String, count: Int, subject: String, exam: ExamTrack,
                      using backend: LLMBackend,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> [LookalikePair] {
        try await collect(count: count, perCall: backend.isOnDevice ? 1 : 4, tokensEach: 900,
                          source: source, backend: backend, onProgress: onProgress,
                          key: { pairKey($0.a, $0.b) },
                          prompt: { n, already, text in
                              duelsPrompt(count: n, subject: subject, exam: exam, already: already, source: text)
                          },
                          parse: parseDuels)
    }

    static func scripts(source: String, count: Int, subject: String, exam: ExamTrack,
                        using backend: LLMBackend,
                        onProgress: @escaping (Int, Int) -> Void) async throws -> [IllnessScript] {
        try await collect(count: count, perCall: backend.isOnDevice ? 2 : 6, tokensEach: 500,
                          source: source, backend: backend, onProgress: onProgress,
                          key: { $0.disease },
                          prompt: { n, already, text in
                              scriptsPrompt(count: n, subject: subject, exam: exam, already: already, source: text)
                          },
                          parse: parseScripts)
    }

    /// The loop every writer shares. A long lecture is taken a window at a
    /// time, round and round, so later chapters get their turn; what has been
    /// written is listed in each prompt so it is not written again.
    private static func collect<Item>(
        count: Int, perCall: Int, tokensEach: Int, source: String, backend: LLMBackend,
        onProgress: @escaping (Int, Int) -> Void,
        key: (Item) -> String,
        prompt: (Int, [String], String) -> String,
        parse: (String) -> [Item]
    ) async throws -> [Item] {
        let budget = max(2_000, backend.promptBudgetChars)
        let windows = source.count <= budget ? [source]
            : TextSlicing.slice(source, into: (source.count + budget - 1) / budget, maxChars: budget)
        guard !windows.isEmpty else { throw LLMError.emptyReply }
        var collected: [Item] = []
        var seen: Set<String> = []
        var failures = 0
        var round = 0
        while collected.count < count && failures < max(3, windows.count + 2) {
            try Task.checkCancellation()
            onProgress(collected.count, count)
            let batch = min(perCall, count - collected.count)
            let window = windows[round % windows.count]
            round += 1
            let already = collected.map { String(key($0).prefix(140)) }
            do {
                let reply = try await backend.complete(
                    [.system(prompt(batch, already, window)), .user("Write the \(batch) now, as JSON only.")],
                    maxTokens: tokensEach * batch + 200, temperature: 0.6)
                var kept = 0
                for item in parse(reply) {
                    let name = key(item).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard seen.insert(name).inserted else { continue }
                    collected.append(item)
                    kept += 1
                    if collected.count >= count { break }
                }
                failures = kept == 0 ? failures + 1 : 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LLMError {
                // a missing key or a refused request will not fix itself on retry
                if case .emptyReply = error { failures += 1 } else { throw error }
            } catch {
                failures += 1
            }
        }
        onProgress(collected.count, count)
        guard !collected.isEmpty else { throw LLMError.emptyReply }
        return collected
    }

    /// The same pair whichever way round it was written.
    static func pairKey(_ a: String, _ b: String) -> String {
        [a.lowercased(), b.lowercased()].sorted().joined(separator: " vs ")
    }

    // MARK: prompts

    private static func audience(_ subject: String, _ exam: ExamTrack) -> String {
        "a medical student revising \(subject.isEmpty ? "medicine" : subject)"
            + (exam == .general ? "" : " for \(exam.title)")
    }

    private static func tail(already: [String], source: String) -> [String] {
        var lines = [
            "Use only what the source supports. Do not invent drugs, doses or thresholds it does not give.",
            "Answer with the JSON object only: no code fence, no notes before or after.",
        ]
        if !already.isEmpty {
            lines.append("Already written - do not repeat these:")
            lines += already.suffix(40).map { "- " + $0 }
        }
        return lines + ["", "SOURCE:", source]
    }

    static func casesPrompt(count: Int, subject: String, exam: ExamTrack,
                            already: [String], source: String) -> String {
        ([
            "Write \(count) clue-by-clue diagnostic case\(count == 1 ? "" : "s") for \(audience(subject, exam)), from the source below.",
            "Each case is told as 6 to 8 clues, revealed one at a time, from the least specific to the most specific, in this order where the source allows: age and sex; presenting complaint; a history detail; an examination finding; a bedside test; a key investigation; the decisive result.",
            "Each clue is one short sentence. No clue names the diagnosis.",
            "The early clues must fit all the differentials; the diagnosis should only become certain near the end.",
            "Before naming the diagnosis, reason through the differential from ALL the clues and write it as \"differential\": \"mostLikely\" (the diagnosis), \"expanded\" (reasonable alternatives), and \"cantMiss\" (1 or 2 dangerous diagnoses that must be excluded, where any fit; otherwise an empty list). For each: \"for\" and \"against\" are up to 3 findings taken from the clues, a few words each, and \"test\" is the one test that would confirm or rule it out.",
            "Then commit: the diagnosis is the mostLikely entry, and it must fit every clue.",
            "For each case give: the diagnosis; exactly 3 plausible differentials a student could reach from the early clues (never the diagnosis again), taken from expanded or cantMiss; a one-line teaching point; and decisiveClue, the number (counting from 1) of the first clue after which the diagnosis is clear.",
            "Every case is a different disease or a clearly different presentation.",
            "Follow current guidance, but never cite a source, guideline or reference by name: the app cites the lecture.",
            "JSON shape: {\"cases\":[{\"clues\":[\"...\"],\"differential\":{\"mostLikely\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}],\"expanded\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}],\"cantMiss\":[{\"name\":\"...\",\"for\":[\"...\"],\"against\":[\"...\"],\"test\":\"...\"}]},\"diagnosis\":\"...\",\"differentials\":[\"...\",\"...\",\"...\"],\"teachingPoint\":\"...\",\"decisiveClue\":6}]}",
        ] + tail(already: already, source: source)).joined(separator: "\n")
    }

    static func duelsPrompt(count: Int, subject: String, exam: ExamTrack,
                            already: [String], source: String) -> String {
        ([
            "List \(count) pair\(count == 1 ? "" : "s") of conditions from the source below that \(audience(subject, exam)) commonly confuses.",
            "For each pair give 8 to 12 discriminating features: symptoms, signs, investigation results, epidemiology, or treatment response. Each feature belongs to A, to B, or to both.",
            "Mix them: most belong to one side, and 2 or 3 are shared by both, so the shared ones cannot be used to tell them apart.",
            "Each feature is a few words, and never names either condition. \"why\" is one short line on why it points that way.",
            "bottomLine is the one sentence to remember about telling them apart.",
            "JSON shape: {\"duels\":[{\"a\":\"...\",\"b\":\"...\",\"features\":[{\"text\":\"...\",\"side\":\"A\",\"why\":\"...\"}],\"bottomLine\":\"...\"}]} where side is \"A\", \"B\" or \"both\".",
        ] + tail(already: already, source: source)).joined(separator: "\n")
    }

    static func scriptsPrompt(count: Int, subject: String, exam: ExamTrack,
                              already: [String], source: String) -> String {
        ([
            "Write illness scripts for \(audience(subject, exam)): one per disease covered in the source below, up to \(count).",
            "Each script fits on one phone screen. Fields:",
            "- disease: its usual name",
            "- who: who gets it (epidemiology and risk factors), one line",
            "- timeCourse: onset and how it evolves, one line",
            "- keyFeatures: 3 to 5 short symptoms or history points",
            "- examSigns: 2 to 4 short examination signs",
            "- decisiveTest: the investigation that settles it, and the result",
            "- firstLine: first-line management, one line",
            "- lookalikes: 2 to 4 conditions it is mistaken for, each just its usual name (no explanation), preferring ones that also appear in the source",
            "Leave a field as an empty string or list if the source says nothing about it.",
            "JSON shape: {\"scripts\":[{\"disease\":\"...\",\"who\":\"...\",\"timeCourse\":\"...\",\"keyFeatures\":[\"...\"],\"examSigns\":[\"...\"],\"decisiveTest\":\"...\",\"firstLine\":\"...\",\"lookalikes\":[\"...\"]}]}",
        ] + tail(already: already, source: source)).joined(separator: "\n")
    }

    // MARK: reading the replies

    static func parseCases(_ raw: String) -> [ClueCase] {
        items(in: raw, key: "cases").compactMap { d -> ClueCase? in
            let clues = Array(strings(d, "clues", "clue").prefix(8))
            let diagnosis = string(d, "diagnosis", "answer", "dx")
            guard clues.count >= 4, !diagnosis.isEmpty else { return nil }
            var differentials: [String] = []
            for name in strings(d, "differentials", "differential", "ddx", "distractors") {
                let same = name.compare(diagnosis, options: .caseInsensitive) == .orderedSame
                let repeated = differentials.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
                if !same && !repeated { differentials.append(name) }
            }
            guard differentials.count >= 3 else { return nil }
            let decisive = int(d, "decisiveClue", "decisive_clue", "clearAt") ?? clues.count
            let tiers: DifferentialTiers? = DifferentialTiers.parse(json: d["differential"] ?? d["ddx"])
            return ClueCase(clues: clues, diagnosis: diagnosis,
                            differentials: Array(differentials.prefix(3)),
                            teachingPoint: string(d, "teachingPoint", "teaching_point", "teaching", "learningPoint"),
                            decisiveClue: min(max(1, decisive), clues.count),
                            differential: tiers)
        }
    }

    static func parseDuels(_ raw: String) -> [LookalikePair] {
        items(in: raw, key: "duels").compactMap { d -> LookalikePair? in
            let a = string(d, "a", "A", "conditionA")
            let b = string(d, "b", "B", "conditionB")
            guard !a.isEmpty, !b.isEmpty, a.lowercased() != b.lowercased() else { return nil }
            let raws = (d["features"] as? [Any]) ?? []
            let features = raws.compactMap { entry -> LookalikeFeature? in
                guard let f = entry as? [String: Any] else { return nil }
                let text = string(f, "text", "feature")
                guard !text.isEmpty, let side = sideOf(string(f, "side", "belongs", "to"), a: a, b: b) else { return nil }
                return LookalikeFeature(text: text, side: side, why: string(f, "why", "explanation", "reason"))
            }
            guard features.count >= 6 else { return nil }
            return LookalikePair(a: a, b: b, features: Array(features.prefix(12)),
                                 bottomLine: string(d, "bottomLine", "bottom_line", "summary"))
        }
    }

    static func parseScripts(_ raw: String) -> [IllnessScript] {
        items(in: raw, key: "scripts").compactMap { d -> IllnessScript? in
            let disease = string(d, "disease", "name", "condition")
            let keyFeatures = strings(d, "keyFeatures", "key_features", "features")
            let decisive = string(d, "decisiveTest", "decisive_test", "investigation")
            guard !disease.isEmpty, !keyFeatures.isEmpty || !decisive.isEmpty else { return nil }
            let lookalikes = strings(d, "lookalikes", "differentials", "mimics")
                .map { tidyName($0) }
                .filter { !$0.isEmpty && $0.lowercased() != disease.lowercased() }
            return IllnessScript(disease: disease,
                                 who: string(d, "who", "epidemiology", "risk"),
                                 timeCourse: string(d, "timeCourse", "time_course", "course"),
                                 keyFeatures: keyFeatures,
                                 examSigns: strings(d, "examSigns", "exam_signs", "signs", "exam"),
                                 decisiveTest: decisive,
                                 firstLine: string(d, "firstLine", "first_line", "management", "treatment"),
                                 lookalikes: Array(lookalikes.prefix(5)))
        }
    }

    /// Which side a feature was put on: "A", "B", "both", or either
    /// condition's own name.
    static func sideOf(_ text: String, a: String, b: String) -> LookalikeSide? {
        var t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let nameA = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let nameB = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // a condition's own name is checked before anything is trimmed off it
        if !nameA.isEmpty && t == nameA { return .a }
        if !nameB.isEmpty && t == nameB { return .b }
        if t.contains("both") || t == "a and b" || t == "a & b" || t == "ab" { return .both }
        // "Side A", "Condition B", "A only", "only B"
        for prefix in ["side ", "condition ", "only "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        if t.hasSuffix(" only") { t = String(t.dropLast(5)) }
        t = t.trimmingCharacters(in: .whitespaces)
        if t == "a" || t == nameA { return .a }
        if t == "b" || t == nameB { return .b }
        return nil
    }

    /// A lookalike's name without a trailing explanation, so it can be a
    /// note title: "Pneumothorax (sudden pain)" becomes "Pneumothorax".
    static func tidyName(_ text: String) -> String {
        var name = text
        for mark in [" (", " - ", " \u{2014} ", ": ", "["] {
            if let cut = name.range(of: mark) { name = String(name[..<cut.lowerBound]) }
        }
        return name.replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: tolerant JSON

    /// The list of items in a reply: under the named key, under any key that
    /// holds a list of objects, a bare list, or a single object on its own.
    static func items(in raw: String, key: String) -> [[String: Any]] {
        let text = tidyJSON(LLMText.stripThinking(raw))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let list = bareList(in: trimmed) { return list }
        if let data = LLMText.jsonObject(in: text),
           let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any] {
                if let list = dict[key] as? [[String: Any]] { return list }
                for value in dict.values {
                    if let list = value as? [[String: Any]], !list.isEmpty { return list }
                }
                return [dict]
            }
        }
        return bareList(in: text) ?? []
    }

    private static func bareList(in text: String) -> [[String: Any]]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return nil }
        return list
    }

    /// Mends the slips models make most: a code fence round the JSON, and a
    /// comma before a closing bracket.
    static func tidyJSON(_ text: String) -> String {
        text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
    }

    /// The first of these keys that holds text (or a number, or a list read
    /// as one line).
    static func string(_ d: [String: Any], _ keys: String...) -> String {
        for key in keys {
            if let s = d[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            } else if let n = d[key] as? NSNumber {
                return n.stringValue
            } else if let list = d[key] as? [Any] {
                let joined = list.compactMap { $0 as? String }.joined(separator: "; ")
                if !joined.isEmpty { return joined }
            }
        }
        return ""
    }

    /// The first of these keys that holds a list; a single string is split
    /// at semicolons or line breaks.
    static func strings(_ d: [String: Any], _ keys: String...) -> [String] {
        for key in keys {
            var found: [String] = []
            if let list = d[key] as? [Any] {
                found = list.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    if let o = item as? [String: Any] { return string(o, "text", "name", "clue") }
                    return nil
                }
            } else if let s = d[key] as? String {
                found = s.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            }
            let tidied = found
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }
            if !tidied.isEmpty { return tidied }
        }
        return []
    }

    static func int(_ d: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            if let n = d[key] as? NSNumber { return n.intValue }
            if let s = d[key] as? String, let n = Int(s.filter(\.isNumber)) { return n }
        }
        return nil
    }
}
