import Foundation

/// One "Cases" card — matches the web app's QA-card objects rendered in
/// `renderQaCard()`: a topic line, a type (a clinical case or plain
/// recall), the question, and answer bullets with `**term**` highlights.
struct QACard: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case `case`, recall }

    var id: UUID = UUID()
    var topic: String = ""
    var type: Kind = .recall
    var stem: String
    var answer: [String] = []

    var badge: String { type == .case ? "Clinical case" : "Recall" }
}
