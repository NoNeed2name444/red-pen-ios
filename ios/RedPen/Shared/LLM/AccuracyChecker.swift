import Foundation

/// MedVAL as the app uses it: before a case's patient reply is shown, and on
/// anything generated or studied in the other modes.
///
/// MedVAL grades an output AGAINST ITS INPUT - it asks "is this consistent with
/// what it was made from?", not "is this true in general?". So every check is
/// given the text the output came from: the case file for a patient reply, the
/// lecture for a question. Where a set has no source, it is told so and grades
/// against standard teaching, and the sheet says that is a weaker check.
enum AccuracyChecker {


    static let noSourceNote = "No source document was provided. Judge the output against standard, current medical teaching for students; treat any claim that contradicts it as a fabricated claim."

    /// Grades `output` against `input`.
    static func check(instruction: String, input: String, output: String,
                      using backend: LLMBackend) async throws -> AccuracyVerdict {
        let budget = backend.promptBudgetChars
        let prompt = medvalPrompt(instruction: instruction,
                                  input: String(input.prefix(budget)),
                                  output: String(output.prefix(budget / 2)))
        // MedVAL is Qwen3-based: "/no_think" skips the hidden reasoning pass,
        // which on a phone is most of the wait. Its own `reasoning` field still
        // explains the grade.
        let reply = try await backend.complete([.user(prompt + "\n/no_think")],
                                               maxTokens: 700, temperature: 0.1)
        return parse(reply, checkedBy: backend.label)
    }


    // MARK: MedVAL's prompt and answer (in LLMParsing, where they are tested)

    static func medvalPrompt(instruction: String, input: String, output: String) -> String {
        MedVAL.prompt(instruction: instruction, input: input, output: output)
    }

    static func parse(_ reply: String, checkedBy: String) -> AccuracyVerdict {
        MedVAL.parse(reply, checkedBy: checkedBy)
    }

    // MARK: finding the source text a check is made against

    /// The pages of a set's sources that share the most words with `text`,
    /// up to `limit` characters. A check against the right page is a real
    /// check; a check against the first 8,000 characters of a 300-page
    /// lecture is a coin toss.
    static func reference(for text: String, in set: StudySet, limit: Int) -> String? {
        let pages = set.sources.flatMap { doc in doc.pages.map { (doc.name, $0) } }
        guard !pages.isEmpty else { return nil }
        let wanted = words(text)
        let ranked = pages.map { pair -> (String, Int) in
            let (name, page) = pair
            return ("\(name), \(page.number):\n\(page.text)", words(page.text).intersection(wanted).count)
        }.sorted { $0.1 > $1.1 }
        var out = ""
        for (pageText, score) in ranked where score > 0 {
            if out.count + pageText.count > limit { break }
            out += pageText + "\n\n"
        }
        return out.isEmpty ? nil : out
    }

    private static func words(_ text: String) -> Set<String> { TextSlicing.words(text) }

    // MARK: screening generated sets

    /// Checks each generated question against the source it came from and
    /// drops the ones MedVAL grades level 4. Level 3 is kept - the student
    /// reviews every generated set, and dropping on "could plausibly confuse"
    /// empties short sets - but counted, so the status line can say so.
    static func screen(_ questions: [MCQQuestion], source: String, using backend: LLMBackend,
                       onProgress: @escaping (Int, Int) -> Void) async -> (kept: [MCQQuestion], removed: Int, flagged: Int) {
        var kept: [MCQQuestion] = []
        var removed = 0, flagged = 0
        for (i, q) in questions.enumerated() {
            onProgress(i, questions.count)
            let letters = ["A", "B", "C", "D", "E"]
            let options = q.options.enumerated().map { "\(letters[min($0.offset, 4)]). \($0.element)" }
            let output = "\(q.stem)\n\(options.joined(separator: "\n"))\nAnswer: \(letters[min(q.correctIndex, 4)])\nExplanation: \(q.explanation)"
            guard let verdict = try? await check(
                instruction: "Write a single-best-answer medical exam question, with its answer and explanation, from the source.",
                input: nearest(source, to: output, limit: backend.promptBudgetChars),
                output: output, using: backend) else { kept.append(q); continue }
            if verdict.riskLevel >= 4 { removed += 1; continue }
            if verdict.riskLevel == 3 { flagged += 1 }
            kept.append(q)
        }
        return (kept, removed, flagged)
    }

    static func screen(_ stations: [OsceChecklist], source: String, using backend: LLMBackend,
                       onProgress: @escaping (Int, Int) -> Void) async -> (kept: [OsceChecklist], removed: Int, flagged: Int) {
        var kept: [OsceChecklist] = []
        var removed = 0, flagged = 0
        for (i, station) in stations.enumerated() {
            onProgress(i, stations.count)
            let output = station.title + "\n" + station.steps.map { "- " + $0 }.joined(separator: "\n")
            guard let verdict = try? await check(
                instruction: "Write an OSCE station checklist, in the order the steps are performed, from the source.",
                input: nearest(source, to: output, limit: backend.promptBudgetChars),
                output: output, using: backend) else { kept.append(station); continue }
            if verdict.riskLevel >= 4 { removed += 1; continue }
            if verdict.riskLevel == 3 { flagged += 1 }
            kept.append(station)
        }
        return (kept, removed, flagged)
    }

    static func nearest(_ source: String, to text: String, limit: Int) -> String {
        TextSlicing.nearest(source, to: text, limit: limit)
    }
}
