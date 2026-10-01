import Foundation

/// Runs the AI check for the Syllabus screen and keeps its result: one
/// request per area, a few at a time, the finished check saved per exam.
@MainActor
final class CoverageChecker: ObservableObject {
    /// The check on show: the kept one for this exam, the one just run, or
    /// the personal build's example.
    @Published private(set) var check: CoverageCheck?
    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// Why the last run failed, in the student's terms.
    @Published private(set) var failure: String?

    /// Requests in flight at once: quick enough, and gentle on the server.
    static let parallel = 3

    private var task: Task<Void, Never>?

    /// Why the cloud cannot be asked right now, or nil when it can.
    var blocker: String? {
        let cloud = LocalLLMService.shared
        if cloud.cloudToken == nil {
            return "Sign in to have \(Brand.name) Cloud check this too. Until then the keyword check below is all there is."
        }
        if !cloud.isPro && !PersonalBuild.isOn {
            return "The AI check uses \(Brand.name) Cloud, which is part of Pro. The keyword check below still works."
        }
        return nil
    }

    /// Shows what is kept for an exam - or, in the personal build, the
    /// example when nothing real has been run yet.
    func load(for track: ExamTrack, areas: [AreaCoverage]) {
        guard !running else { return }
        failure = nil
        if let kept = CoverageCloudCheck.load(for: track) {
            check = kept
        } else if PersonalBuild.isOn, !areas.isEmpty {
            check = CoverageExamples.check(for: track, areas: areas)
        } else {
            check = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }

    /// Checks every area and keeps the result.
    func run(track: ExamTrack, areas: [AreaCoverage], library: [StudySet]) {
        guard !running, blocker == nil, let token = LocalLLMService.shared.cloudToken else { return }
        let prompts = areas.map { CoverageCloudCheck.prompt(for: $0, exam: track, library: library) }
        running = true
        failure = nil
        done = 0
        total = areas.count
        task = Task { [weak self] in
            var verdicts: [String: CoverageVerdict] = [:]
            var sources: [String: Int] = [:]
            var failed: [String] = []
            var firstError: Error?

            await withTaskGroup(of: (Int, Result<(content: String, source: String), Error>).self) { group in
                var next = 0
                while next < min(CoverageChecker.parallel, prompts.count) {
                    let i = next, prompt = prompts[i]
                    group.addTask {
                        let reply = await CoverageChecker.ask(prompt, token: token)
                        return (i, reply)
                    }
                    next += 1
                }
                while let finished = await group.next() {
                    let (i, result) = finished
                    switch result {
                    case .success(let reply):
                        let found = CoverageCloudCheck.parse(reply.content, for: areas[i])
                        if found.isEmpty { failed.append(areas[i].area.name) }
                        verdicts.merge(found) { _, new in new }
                        sources[reply.source, default: 0] += 1
                    case .failure(let error):
                        failed.append(areas[i].area.name)
                        if firstError == nil { firstError = error }
                    }
                    self?.done += 1
                    if Task.isCancelled { group.cancelAll(); break }
                    if next < prompts.count {
                        let j = next, prompt = prompts[j]
                        group.addTask {
                            let reply = await CoverageChecker.ask(prompt, token: token)
                            return (j, reply)
                        }
                        next += 1
                    }
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.running = false
            if verdicts.isEmpty {
                self.failure = (firstError as? LocalizedError)?.errorDescription
                    ?? "The cloud check did not come back. The keyword check below still stands."
                return
            }
            let ranked = sources.sorted { $0.value > $1.value }.map(\.key)
            let made = CoverageCheck(track: track.rawValue, date: Date(), sources: ranked,
                                     verdicts: verdicts, failedAreas: failed)
            CoverageCloudCheck.save(made, for: track)
            self.check = made
        }
    }

    /// One request, with its failure kept rather than thrown, so one area
    /// going wrong does not lose the others.
    nonisolated private static func ask(_ prompt: String, token: String) async -> Result<(content: String, source: String), Error> {
        do {
            return .success(try await CoverageCloudCheck.send(prompt, token: token))
        } catch {
            return .failure(error)
        }
    }
}
