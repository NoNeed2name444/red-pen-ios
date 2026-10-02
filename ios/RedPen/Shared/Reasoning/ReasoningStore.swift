import SwiftUI

/// The Reasoning tools' material and scores, kept on this device, and the
/// writing of new material.
///
/// A file of its own in Application Support rather than part of the library:
/// duels and scripts are practice made from a set, not part of it, and they
/// should not travel with every sync of the deck.
///
/// Writing lives here rather than in a screen, so leaving the screen does not
/// lose what is being written: it lands in the pack whenever it finishes.
@MainActor
final class ReasoningStore: ObservableObject {
    static let shared = ReasoningStore()

    @Published private(set) var packs: [UUID: ReasoningPack] = [:]
    @Published private(set) var duelPlays: [DuelPlay] = []
    /// What is being written now, if anything.
    @Published private(set) var writing: (setId: UUID, tool: ReasoningTool)?
    /// Why the last attempt at writing a tool for a set failed, by set and tool.
    @Published var trouble: [String: String] = [:]

    private var running: Task<Void, Never>?
    private let fileURL: URL
    private let writer = DispatchQueue(label: "vignette.reasoning.save", qos: .utility)

    private struct Snapshot: Codable {
        var packs: [ReasoningPack]?
        var duelPlays: [DuelPlay]?
    }

    private init() {
        let manager = FileManager.default
        let dir = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("vignette-reasoning.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder.redPen.decode(Snapshot.self, from: data) else { return }
        var byId: [UUID: ReasoningPack] = [:]
        for pack in snapshot.packs ?? [] { byId[pack.setId] = pack }
        packs = byId
        duelPlays = snapshot.duelPlays ?? []
    }

    private func save() {
        let snapshot = Snapshot(packs: Array(packs.values), duelPlays: duelPlays)
        guard let data = try? JSONEncoder.redPen.encode(snapshot) else { return }
        let url = fileURL
        writer.async { try? data.write(to: url, options: .atomic) }
    }

    // MARK: reading

    /// What has been written for a set. The personal build's example set
    /// answers with the ready-made examples.
    func pack(for setId: UUID) -> ReasoningPack {
        if let stored = packs[setId] { return stored }
        if setId == ReasoningExamples.setId { return ReasoningExamples.pack }
        return ReasoningPack(setId: setId)
    }

    func isWriting(_ tool: ReasoningTool, for setId: UUID) -> Bool {
        writing?.setId == setId && writing?.tool == tool
    }

    static func troubleKey(_ tool: ReasoningTool, _ setId: UUID) -> String {
        setId.uuidString + "." + tool.rawValue
    }

    func lastDuel(of pairId: UUID) -> DuelPlay? {
        duelPlays.filter { $0.pairId == pairId }.max { $0.date < $1.date }
    }

    // MARK: changing

    func record(_ play: DuelPlay) {
        duelPlays.append(play)
        save()
    }

    /// Forgets one tool's material for a set, and its scores.
    func clear(_ tool: ReasoningTool, for setId: UUID) {
        var pack = self.pack(for: setId)
        switch tool {
        case .duels:
            let ids = Set(pack.duels.map(\.id))
            duelPlays.removeAll { ids.contains($0.pairId) }
            pack.duels = []
        case .scripts:
            pack.scripts = []
        }
        pack.updatedAt = Date()
        packs[setId] = pack
        save()
    }

    private func add(_ change: (inout ReasoningPack) -> Void, to setId: UUID) {
        var pack = self.pack(for: setId)
        change(&pack)
        pack.updatedAt = Date()
        packs[setId] = pack
        save()
    }

    // MARK: writing

    /// Writes `count` more of a tool's material for a set with the chosen
    /// writer, showing progress in the generation card. New material is added
    /// to what is there; what is there is listed to the writer so it is not
    /// written again.
    func write(_ tool: ReasoningTool, for set: StudySet, count: Int) {
        let key = Self.troubleKey(tool, set.id)
        trouble[key] = nil
        guard writing == nil else {
            trouble[key] = "Something else is being written \u{2014} wait for it to finish."
            return
        }
        // another screen's generation, running: said here, and left running
        if let busy = GenerationCenter.shared.busy {
            trouble[key] = busy
            return
        }
        guard let backend = LocalLLMService.shared.writerOrApple() else {
            trouble[key] = "No model is ready to write with. Choose one in AI models."
            return
        }
        let source = ReasoningWriter.source(of: set)
        guard source.count >= 200 else {
            trouble[key] = "This set has too little text to write from."
            return
        }
        let setId = set.id, subject = set.subject == "General" ? "" : set.subject
        let exam = ExamTrack.current
        let title: String = "Writing \(count) \(tool.noun)\(count == 1 ? "" : "s")"
        guard let job = GenerationCenter.shared.begin(title, total: count, onCancel: {
            self.running?.cancel()
            self.running = nil
            self.writing = nil
        }) else {
            trouble[key] = GenerationCenter.shared.busy
            return
        }
        writing = (setId: setId, tool: tool)
        let progress: (Int, Int) -> Void = { done, total in
            GenerationCenter.shared.update(job, done: done, total: total)
        }
        running = Task {
            do {
                switch tool {
                case .duels:
                    let made = try await ReasoningWriter.duels(source: source, count: count, subject: subject,
                                                               exam: exam, using: backend, onProgress: progress)
                    try Task.checkCancellation()
                    self.add({ pack in
                        let known = Set(pack.duels.map { ReasoningWriter.pairKey($0.a, $0.b) })
                        pack.duels += made.filter { !known.contains(ReasoningWriter.pairKey($0.a, $0.b)) }
                    }, to: setId)
                case .scripts:
                    let made = try await ReasoningWriter.scripts(source: source, count: count, subject: subject,
                                                                 exam: exam, using: backend, onProgress: progress)
                    try Task.checkCancellation()
                    self.add({ pack in
                        let known = Set(pack.scripts.map { $0.disease.lowercased() })
                        pack.scripts += made.filter { !known.contains($0.disease.lowercased()) }
                    }, to: setId)
                }
                GenerationCenter.shared.end(job, finished: "Your \(tool.title.lowercased()) are ready")
            } catch is CancellationError {
                // the card's Cancel has already tidied up
            } catch {
                GenerationCenter.shared.end(job)
                if !Task.isCancelled { self.trouble[key] = error.localizedDescription }
            }
            self.writing = nil
            self.running = nil
        }
    }

    /// Stops what is being written, from the screen rather than the card.
    func cancelWriting() {
        GenerationCenter.shared.cancel()
    }
}
