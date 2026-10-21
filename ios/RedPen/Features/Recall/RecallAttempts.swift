import UIKit
import CryptoKit

/// A figure to draw from memory: the picture, what it is called (hidden
/// while drawing), and the labels on it to tick off afterwards.
struct RecallFigure: Identifiable {
    /// Which figure this is, for keeping attempts: the same picture in two
    /// sets is the same figure.
    let key: String
    let image: UIImage
    let title: String
    let labels: [String]

    var id: String { key }

    init(key: String, image: UIImage, title: String, labels: [String]) {
        self.key = key
        self.image = image
        self.title = title
        self.labels = labels
    }

    /// Picture `index` of a set, with the labels any image occlusion card in
    /// the library hides on that same picture. Nil when the picture will not
    /// decode.
    init?(set: StudySet, index: Int, caption: String, library: [StudySet]) {
        guard set.images.indices.contains(index) else { return nil }
        let base64 = AnkiCardFace.stripDataPrefix(set.images[index])
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        self.init(key: RecallFigure.key(for: base64),
                  image: image,
                  title: caption,
                  labels: RecallFigure.labels(for: base64, in: [set] + library.filter { $0.id != set.id }))
    }

    /// A short, stable name for a picture: a hash of its bytes.
    static func key(for base64: String) -> String {
        let digest = SHA256.hash(data: Data(base64.utf8))
        return "figure-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The labels image occlusion cards hide on this picture, in card order,
    /// each once.
    static func labels(for base64: String, in library: [StudySet]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for set in library {
            for card in set.cards where card.type == .occlusion {
                guard let i = card.imageIndex, set.images.indices.contains(i),
                      set.images[i].utf8.count >= base64.utf8.count,
                      AnkiCardFace.stripDataPrefix(set.images[i]) == base64 else { continue }
                let raw = card.bullets.first ?? card.front
                let label = raw.replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty, label != "What's hidden here?",
                      seen.insert(label.lowercased()).inserted else { continue }
                out.append(label)
            }
        }
        return out
    }
}

/// One go at drawing a figure from memory.
struct RecallAttempt: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    /// PencilKit's own data for the drawing.
    var drawing: Data
    /// The size of the paper it was drawn on, so it can be scaled to fit a
    /// different screen later.
    var width: Double
    var height: Double
    /// The labels the student ticked as got, and how many there were.
    var got: [String]
    var labelCount: Int

    init(id: UUID = UUID(), date: Date = Date(), drawing: Data,
         width: Double, height: Double, got: [String] = [], labelCount: Int = 0) {
        self.id = id
        self.date = date
        self.drawing = drawing
        self.width = width
        self.height = height
        self.got = got
        self.labelCount = labelCount
    }
}

/// Attempts kept per figure, on this device only, in Application Support:
/// one small JSON file per figure, newest attempt first.
enum RecallAttempts {
    /// Most attempts kept per figure; the oldest go first.
    static let limit = 20

    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("DrawRecall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ key: String) -> URL? {
        folder?.appendingPathComponent(key + ".json")
    }

    static func load(_ key: String) -> [RecallAttempt] {
        guard let url = file(key), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([RecallAttempt].self, from: data) else { return [] }
        return list
    }

    /// Adds an attempt, or replaces the one with the same id.
    static func save(_ attempt: RecallAttempt, for key: String) {
        var list = load(key).filter { $0.id != attempt.id }
        list.insert(attempt, at: 0)
        list.sort { $0.date > $1.date }
        guard let url = file(key),
              let data = try? JSONEncoder().encode(Array(list.prefix(limit))) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
