import Combine
import Foundation

/// Each case's latest run, kept on this device: what was done, the ladder's
/// history and the score. Progress, not material, so it lives beside the
/// library rather than in it, the way a quiz's place does.
@MainActor
final class CaseRunStore: ObservableObject {
    static let shared = CaseRunStore()

    @Published private(set) var runs: [UUID: CaseRun] = [:]

    private let url: URL

    init(url: URL? = nil) {
        let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = url ?? folder.appendingPathComponent("case-runs.json")
        load()
    }

    func run(for file: CaseFile) -> CaseRun? { runs[file.id] }

    func state(of file: CaseFile) -> CaseRun.State { runs[file.id].caseState }

    /// Keeps a run, after every step, rung and decision.
    func save(_ run: CaseRun) {
        runs[run.caseID] = run
        write()
    }

    /// Starts the case again from arrival.
    func reset(_ file: CaseFile) {
        runs[file.id] = nil
        write()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CaseRun].self, from: data) else { return }
        runs = Dictionary(list.map { ($0.caseID, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    private func write() {
        let list: [CaseRun] = Array(runs.values)
        let target: URL = url
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
    }
}
