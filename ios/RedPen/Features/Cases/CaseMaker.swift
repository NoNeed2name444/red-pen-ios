import Foundation

/// Writing cases with whichever writer this device has, the same order as
/// question generation: a writer chosen in AI models (the medical models, or
/// the cloud for Pro) first, then Apple's on-device model, then the
/// downloaded Gemma. One case per call, each from the next window of the
/// lecture, each through the structure checks and the accuracy rules before
/// it is kept (CaseChecks). The rest of the verification layer takes the
/// cases once the set is saved, as items of kind "case"; one it grades
/// Flagged is held off the list (AccuracyHolds).
enum CaseMaker {

    enum Writer {
        case backend(LLMBackend)
        case apple
        case gemma(GemmaModel)
    }

    enum Trouble: LocalizedError {
        case unavailable(String)
        case nothingUsable(dropped: Int)

        var errorDescription: String? {
            switch self {
            case .unavailable(let why): return why
            case .nothingUsable(let dropped):
                if dropped > 0 {
                    return "The cases written from this lecture did not pass the structure and accuracy checks. A lecture about a condition - its presentation, tests and treatment - works best."
                }
                return "Nothing in that lecture could be written up as a patient. A lecture about a condition - its presentation, tests and treatment - works best."
            }
        }
    }

    struct Made {
        var cases: [CaseFile]
        /// Written but refused by the checks.
        var dropped: Int
    }

    /// The writer to use here, or nil when there is none.
    @MainActor static func writer(llm: LocalLLMService, gemma: GemmaModel) -> Writer? {
        if let chosen = llm.backend(for: .writer) { return .backend(chosen) }
        if CaseAppleWriter.availability.isAvailable { return .apple }
        if gemma.status == .ready { return .gemma(gemma) }
        return nil
    }

    /// Why there is no writer, in the student's words.
    @MainActor static func noWriter(gemma: GemmaModel) -> String {
        var why: String = "On-device writing isn't available here."
        if case .unavailable(let reason) = CaseAppleWriter.availability { why = reason }
        return why + " Download the offline model in a question set's New set page, or choose a writer in Settings \u{25B8} AI models."
    }

    /// The lecture as the writers read it, each page marked with its number
    /// so the teaching can cite it.
    static func sourceText(_ pages: [(number: Int, text: String)]) -> String {
        pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[Page \($0.number)]\n\($0.text)" }
            .joined(separator: "\n\n")
    }

    static func write(count: Int, source: String, lecture: String, subject: String,
                      brief: CaseWriting.Brief = CaseWriting.Brief(), using writer: Writer,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> Made {
        let wanted: Int = min(max(count, 1), CaseWriting.maxCases)
        if case .backend(let backend) = writer, let cloud = CloudJobs.endpoint(for: backend) {
            return try await cloudWrite(wanted, source: source, lecture: lecture, subject: subject, brief: brief,
                                        backend: backend, at: cloud, onProgress: onProgress)
        }
        let chars: Int
        switch writer {
        case .apple: chars = CaseAppleWriter.sourceChars
        case .gemma: chars = CaseWriting.onDeviceSourceChars
        case .backend(let backend):
            chars = backend.isOnDevice ? CaseWriting.onDeviceSourceChars : min(backend.promptBudgetChars, 12_000)
        }
        let windows: [String] = TextSlicing.windows(source, maxChars: chars)
        var kept: [CaseFile] = []
        var dropped = 0
        var failures = 0
        var round = 0
        while kept.count < wanted && failures < 3 && round < wanted * 3 {
            try Task.checkCancellation()
            onProgress(kept.count, wanted)
            var asked: CaseWriting.Brief = brief
            if asked.setting == nil && asked.diagnosis == nil { asked.setting = CaseWriting.setting(for: round) }
            if asked.diagnosis == nil { asked.avoid = brief.avoid + kept.map(\.diagnosis.name) }
            let window: String = windows.isEmpty ? "" : TextSlicing.window(windows, round: round)
            round += 1
            do {
                let written: [CaseFile] = try await one(window, lecture: lecture, subject: subject, brief: asked, using: writer)
                let screened = CaseChecks.screen(written)
                dropped += screened.dropped.count
                var added = 0
                for file in screened.kept where kept.count < wanted {
                    // one patient per diagnosis in a run, unless asked for one
                    if brief.diagnosis == nil, kept.contains(where: { CaseNames.same($0.diagnosis.name, file.diagnosis.name) }) { continue }
                    kept.append(file)
                    added += 1
                }
                failures = added == 0 ? failures + 1 : 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as MCQGenerator.GenerationError {
                if case .unavailable = error { throw error }
                if case .cancelled = error { throw CancellationError() }
                failures += 1
            } catch let error as LLMError {
                // a missing key or a refused request will not fix itself on retry
                if case .emptyReply = error { failures += 1 } else { throw error }
            } catch {
                failures += 1
            }
        }
        onProgress(kept.count, wanted)
        guard !kept.isEmpty else { throw Trouble.nothingUsable(dropped: dropped) }
        return Made(cases: kept, dropped: dropped)
    }

    /// One call to the writer.
    private static func one(_ window: String, lecture: String, subject: String, brief: CaseWriting.Brief,
                            using writer: Writer) async throws -> [CaseFile] {
        switch writer {
        case .apple:
            return try await CaseAppleWriter.one(source: window, subject: subject, brief: brief, lecture: lecture)
                .map { [$0] } ?? []
        case .gemma(let gemma):
            let rules: String = CaseWriting.instructions(source: window, subject: subject, brief: brief, json: true)
            let reply: String = try await gemma.writeCase(instructions: rules)
            return CaseWriting.parse(reply, lecture: lecture)
        case .backend(let backend):
            let rules: String = CaseWriting.instructions(source: window, subject: subject, brief: brief, json: true)
            let reply: String = try await backend.complete([.system(rules), .user(CaseWriting.requestJSON)],
                                                           maxTokens: 3_500, temperature: 0.7)
            return CaseWriting.parse(reply, lecture: lecture)
        }
    }

    /// Vignette Cloud writes every case in one job, a prompt per case, even
    /// with the app closed (CloudJobCollector makes the set if it is).
    private static func cloudWrite(_ wanted: Int, source: String, lecture: String, subject: String,
                                   brief: CaseWriting.Brief, backend: LLMBackend, at cloud: (base: URL, bearer: String),
                                   onProgress: @escaping (Int, Int) -> Void) async throws -> Made {
        let windows: [String] = Array(TextSlicing.windows(source, maxChars: min(backend.promptBudgetChars, 12_000)).prefix(60))
        let sources: [String] = windows.isEmpty ? [""] : windows
        let steps: [CloudJobs.Step] = (0..<wanted).map { i in
            var asked: CaseWriting.Brief = brief
            if asked.setting == nil && asked.diagnosis == nil { asked.setting = CaseWriting.setting(for: i) }
            return CloudJobs.Step(system: CaseWriting.instructions(source: "{{SOURCE}}", subject: subject, brief: asked, json: true),
                                  user: CaseWriting.requestJSON, source: i % sources.count, maxTokens: 3_500, temperature: 0.7)
        }
        let spec = CloudJobs.Spec(title: "Writing \(wanted) case\(wanted == 1 ? "" : "s")", mode: "each", extract: "pages",
                                  count: wanted, sources: sources, steps: steps)
        let replies: [String] = try await CloudJobs.run(spec, at: cloud, onProgress: onProgress)
        let written: [CaseFile] = replies.flatMap { CaseWriting.parse($0, lecture: lecture) }
        let screened = CaseChecks.screen(written)
        guard !screened.kept.isEmpty else { throw Trouble.nothingUsable(dropped: screened.dropped.count) }
        return Made(cases: Array(screened.kept.prefix(wanted)), dropped: screened.dropped.count)
    }
}
