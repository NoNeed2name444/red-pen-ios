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
        // already checked on the server as part of a cloud job
        if let reply = CloudChecks.take(forOutput: output) { return parse(reply, checkedBy: backend.label) }
        let budget = backend.promptBudgetChars
        let prompt = medvalPrompt(instruction: instruction,
                                  input: String(input.prefix(budget)),
                                  output: String(output.prefix(budget / 2)))
        // MedVAL is Qwen3-based: "/no_think" skips the hidden reasoning pass,
        // which on a phone is most of the wait. Its own `reasoning` field still
        // explains the grade.
        let reply = try await backend.complete([.user(prompt + "\n/no_think")],
                                               maxTokens: 900, temperature: 0.1)
        return parse(reply, checkedBy: backend.label)
    }


    // MARK: the same check, on the server

    static let mcqInstruction = "Write a single-best-answer medical exam question, with its answer and explanation, from the source."
    static let osceInstruction = "Write an OSCE station checklist, in the order the steps are performed, from the source."
    static let materialInstruction = "Write study material for medical students from the source."

    /// MedVAL's prompt with the source and the output left for the server to
    /// fill in, item by item.
    static func serverCheck(instruction: String, limit: Int) -> CloudJobs.Check {
        CloudJobs.Check(template: medvalPrompt(instruction: instruction, input: "{{INPUT}}", output: "{{OUTPUT}}") + "\n/no_think",
                        limit: limit)
    }

    /// What the checker is shown for a question - here and on the server alike.
    /// Lettered A, B, C ... for any number of options (CheckedQuestion), so a
    /// sixth option is not a second "E" and a key of -1 cannot crash it.
    static func checkText(_ q: MCQQuestion) -> String {
        let base: String = CheckedQuestion.text(stem: q.stem, options: q.options,
                                                correctIndex: q.correctIndex, explanation: q.explanation)
        return base + differentialBlock(q.differential)
    }

    /// The writer's differential, for the reasoning checks to test the keyed
    /// answer against - the same block jobs.js adds on the server.
    static func differentialBlock(_ d: DifferentialTiers?) -> String {
        guard let d, !d.isEmpty else { return "" }
        return "\nDifferential:\n" + d.checkText
    }

    static func checkText(_ station: OsceChecklist) -> String {
        station.title + "\n" + station.steps.map { "- " + $0 }.joined(separator: "\n")
    }

    /// The riskiest of several verdicts' replies, for a check made in parts
    /// (a textbook's pages, a deck's batches).
    static func riskiest(_ replies: [String]) -> String? {
        replies.max { parse($0, checkedBy: "").riskLevel < parse($1, checkedBy: "").riskLevel }
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
    ///
    /// A page bigger than what is left of `limit` - a whole Word lecture is
    /// one page - is cut to its own nearest paragraphs (TextSlicing.nearestPages)
    /// rather than skipped, so a Word source is still checked against.
    static func reference(for text: String, in set: StudySet, limit: Int) -> String? {
        let pages: [(heading: String, text: String)] = set.sources.flatMap { doc in
            doc.pages.map { page in (heading: "\(doc.name), \(page.number):\n", text: page.text) }
        }
        guard !pages.isEmpty else { return nil }
        return TextSlicing.nearestPages(pages, to: text, limit: limit)
    }

    // MARK: screening generated sets

    /// Checks each generated question against the source it came from and
    /// drops the ones MedVAL grades level 4. Level 3 is kept - the student
    /// reviews every generated set, and dropping on "could plausibly confuse"
    /// empties short sets - but counted, so the status line can say so.
    ///
    /// An item the checker could not grade (offline, the day's allowance
    /// used, no model loaded) is kept but counted as `unchecked`, never as a
    /// pass: the note (MedVAL.screenNote) must not say a set was checked when it was
    /// not. Once the task is cancelled nothing more is sent to the checker;
    /// the rest is kept unchecked and the caller's own cancellation check ends
    /// the job.
    static func screen(_ questions: [MCQQuestion], source: String, using backend: LLMBackend,
                       onProgress: @escaping (Int, Int) -> Void) async
        -> (kept: [MCQQuestion], removed: Int, flagged: Int, unchecked: Int) {
        var kept: [MCQQuestion] = []
        var removed = 0, flagged = 0, unchecked = 0
        for (i, q) in questions.enumerated() {
            onProgress(i, questions.count)
            if Task.isCancelled {
                kept.append(q); unchecked += 1; continue
            }
            let output = checkText(q)
            guard let verdict = try? await check(
                instruction: mcqInstruction,
                input: nearest(source, to: output, limit: backend.promptBudgetChars),
                output: output, using: backend) else { kept.append(q); unchecked += 1; continue }
            if verdict.riskLevel >= 4 { removed += 1; continue }
            if verdict.riskLevel == 3 { flagged += 1 }
            kept.append(q)
        }
        return (kept, removed, flagged, unchecked)
    }

    static func screen(_ stations: [OsceChecklist], source: String, using backend: LLMBackend,
                       onProgress: @escaping (Int, Int) -> Void) async
        -> (kept: [OsceChecklist], removed: Int, flagged: Int, unchecked: Int) {
        var kept: [OsceChecklist] = []
        var removed = 0, flagged = 0, unchecked = 0
        for (i, station) in stations.enumerated() {
            onProgress(i, stations.count)
            if Task.isCancelled {
                kept.append(station); unchecked += 1; continue
            }
            let output = checkText(station)
            guard let verdict = try? await check(
                instruction: osceInstruction,
                input: nearest(source, to: output, limit: backend.promptBudgetChars),
                output: output, using: backend) else { kept.append(station); unchecked += 1; continue }
            if verdict.riskLevel >= 4 { removed += 1; continue }
            if verdict.riskLevel == 3 { flagged += 1 }
            kept.append(station)
        }
        return (kept, removed, flagged, unchecked)
    }

    static func nearest(_ source: String, to text: String, limit: Int) -> String {
        TextSlicing.nearest(source, to: text, limit: limit)
    }
}
