import Foundation

/// A mock paper part way through, kept on disk after every answer.
///
/// A sitting can run for three hours, and iOS may end an app it has put in
/// the background at any time; a sitting held only on screen was lost with
/// it. This is everything needed to put it back as it was: which questions
/// were drawn, the order their options were shown in, every answer, flag,
/// strike-through and highlight, and the clock.
struct MockSittingSave: Codable, Equatable {
    var title: String
    var specs: [MockSectionSpec]
    /// The questions of each section, by id, in the order they were drawn.
    var questionIds: [[UUID]]
    var wanted: Int
    /// The exam track, by its raw value.
    var track: String
    var passMark: Double?
    var section: Int
    var current: Int
    var selected: [UUID: Int]
    var orders: [UUID: [Int]]
    var flagged: Set<UUID>
    var struck: [UUID: Set<Int>]
    var highlights: [UUID: Set<Int>]
    /// Seconds left on the open section's clock, or nil between sections. The
    /// clock waits while the app is closed: nobody is sitting the paper then.
    var secondsLeft: Double?
    var onBreak: Bool
    var spent: [UUID: Double]
    var startedAt: Date

    /// Answers given so far.
    var answered: Int { selected.count }
    /// Questions on the paper.
    var total: Int { questionIds.reduce(0) { $0 + $1.count } }
}

/// Where the sitting in progress is kept: one at a time, beside the library.
enum MockSittingStore {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mock-sitting.json")
    }

    /// Written whole, atomically: a write cut short leaves the last good one.
    static func save(_ sitting: MockSittingSave, to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sitting) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The sitting in progress, or nil when there is none (or it cannot be read).
    static func load(from url: URL = defaultURL) -> MockSittingSave? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MockSittingSave.self, from: data)
    }

    /// Finished or left: nothing to resume.
    static func clear(at url: URL = defaultURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
