import Foundation
import Combine

// MARK: - what an attempt leaves behind

/// The marker's verdict on an explanation: what it covered, left out and got
/// wrong against the lecture, a score, and the one thing to do next time.
struct ExplainResult: Codable, Hashable {
    var covered: [String] = []
    var missed: [String] = []
    var wrong: [String] = []
    var score: Int = 0
    var oneTip: String = ""

    enum CodingKeys: String, CodingKey { case covered, missed, wrong, score, oneTip }
}

/// Read tolerantly: this is also how a model's JSON is read, and models write
/// a score as 72, 72.0 or "72" and sometimes leave a list out.
extension ExplainResult {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        covered = (try? c.decodeIfPresent([String].self, forKey: .covered)) ?? []
        missed = (try? c.decodeIfPresent([String].self, forKey: .missed)) ?? []
        wrong = (try? c.decodeIfPresent([String].self, forKey: .wrong)) ?? []
        oneTip = (try? c.decodeIfPresent(String.self, forKey: .oneTip)) ?? ""
        if let whole = try? c.decodeIfPresent(Int.self, forKey: .score) {
            score = whole
        } else if let real = try? c.decodeIfPresent(Double.self, forKey: .score) {
            score = Int(real.rounded())
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .score) {
            score = Int(text.filter(\.isNumber)) ?? 0
        }
        score = min(100, max(0, score))
    }
}

/// One go at explaining a topic out loud.
struct ExplainAttempt: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var topic: String
    var setName: String
    var transcript: String
    var result: ExplainResult
    /// Shipped with a personal build to show what a marked attempt looks
    /// like. Never saved.
    var isExample = false
}

/// One line of a spoken station, as it was said.
struct SpokenLine: Codable, Identifiable, Hashable {
    enum Speaker: String, Codable { case student, patient, examiner }
    var id = UUID()
    var speaker: Speaker
    var text: String
}

/// The examiner's marks for a spoken station.
struct StationMark: Codable, Hashable {
    /// Checklist steps done, by position in the station (from 0).
    var done: [Int] = []
    /// Anything the examiner wanted to add about what was missed.
    var missedNotes: [String] = []
    /// Communication, 1 (poor) to 5 (excellent).
    var communication: Int = 3
    var feedback: String = ""
    /// SPIKES stage key (see SpokenAnswer.spikes) to whether it was done.
    /// Only for a communication station.
    var spikes: [String: Bool]?
}

/// One spoken station, from first word to marks.
struct StationAttempt: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var title: String
    var steps: [String]
    var lines: [SpokenLine]
    var mark: StationMark
    var isCommunication: Bool
    var isExample = false
}

// MARK: - where they are kept

/// Past attempts at the spoken modes, so a student can see last week's marks
/// beside today's.
///
/// A small file of its own, like the review schedule, rather than a field in
/// the library: attempts are the student's practice, not study material, and
/// nothing else needs to move when one is added.
@MainActor
final class VoiceHistory: ObservableObject {
    static let shared = VoiceHistory()

    @Published private(set) var explains: [ExplainAttempt] = []
    @Published private(set) var stations: [StationAttempt] = []

    /// Enough to see progress; old enough attempts stop being useful.
    private static let keep = 40

    private struct Saved: Codable {
        var explains: [ExplainAttempt] = []
        var stations: [StationAttempt] = []
    }

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("vignette-voice-attempts.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            explains = saved.explains
            stations = saved.stations
        }
    }

    /// Attempts to list, newest first, with the examples after them in a
    /// personal build so there is always something to open.
    var explainList: [ExplainAttempt] {
        explains + (PersonalBuild.isOn ? VoiceExamples.explainAttempts : [])
    }

    var stationList: [StationAttempt] {
        stations + (PersonalBuild.isOn ? VoiceExamples.stationAttempts : [])
    }

    func add(_ attempt: ExplainAttempt) {
        explains.insert(attempt, at: 0)
        explains = Array(explains.prefix(Self.keep))
        save()
    }

    func add(_ attempt: StationAttempt) {
        stations.insert(attempt, at: 0)
        stations = Array(stations.prefix(Self.keep))
        save()
    }

    func delete(explain id: UUID) {
        explains.removeAll { $0.id == id }
        save()
    }

    func delete(station id: UUID) {
        stations.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(explains: explains, stations: stations)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
