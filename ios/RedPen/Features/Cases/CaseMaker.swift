import Foundation

/// Writing cases with the app's one writer, the hosted writer route (Pro),
/// and nothing else (the owner, 23 Oct: "Lock it"): without it no case is
/// written and the screen says why (noWriter). One case per call, each from
/// the next window of the lecture, each through the structure checks and the accuracy rules before
/// it is kept (CaseChecks). The rest of the verification layer takes the
/// cases once the set is saved, as items of kind "case"; one it grades
/// Flagged is held off the list (AccuracyHolds).
enum CaseMaker {

    enum Trouble: LocalizedError {
        case nothingUsable(dropped: Int)

        var errorDescription: String? {
            switch self {
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

    /// The writer to use here: the writer route, or nil when it is blocked.
    @MainActor static func writer(llm: LocalLLMService) -> LLMBackend? { llm.writer() }

    /// Why there is no writer, in the cloud's own words: part of Pro, sign
    /// in, or out of reach (LocalLLMService.noWriter).
    @MainActor static func noWriter(llm: LocalLLMService) -> String { llm.noWriter }

    /// The lecture as the writers read it, each page marked with its number
    /// so the teaching can cite it.
    static func sourceText(_ pages: [(number: Int, text: String)]) -> String {
        pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[Page \($0.number)]\n\($0.text)" }
            .joined(separator: "\n\n")
    }

    static func write(count: Int, source: String, lecture: String, subject: String,
                      brief: CaseWriting.Brief = CaseWriting.Brief(), using writer: LLMBackend,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> Made {
        let wanted: Int = min(max(count, 1), CaseWriting.maxCases)
        if let cloud = CloudJobs.endpoint(for: writer) {
            return try await cloudWrite(wanted, source: source, lecture: lecture, subject: subject, brief: brief,
                                        backend: writer, at: cloud, onProgress: onProgress)
        }
        let chars: Int = min(writer.promptBudgetChars, 12_000)
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
                            using writer: LLMBackend) async throws -> [CaseFile] {
        let rules: String = CaseWriting.instructions(source: window, subject: subject, brief: brief, json: true)
        let reply: String = try await writer.complete([.system(rules), .user(CaseWriting.requestJSON)],
                                                      maxTokens: 3_500, temperature: 0.7)
        return CaseWriting.parse(reply, lecture: lecture)
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
