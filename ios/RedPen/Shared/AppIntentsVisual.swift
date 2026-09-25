#if canImport(VisualIntelligence) && !SWIFT_PACKAGE
import AppIntents
import Foundation
import VisualIntelligence

// MARK: - Visual Intelligence (iOS 26)
//
// A screenshot of a question, or the camera on a textbook page: Visual
// Intelligence's search offers the student's own sets that match what it
// sees. It hands over the labels it recognised; they are matched against
// each set's name, subject and tags with the same folding Siri's "Quiz me on"
// uses (SubjectMatch), and a tapped result runs OpenSetIntent.
//
// Only the labels are read - the picture itself is never kept or sent.
// Xcode build only: the Playgrounds package has no App Intents metadata, so
// the system would never ask it.

struct StudySetVisualQuery: IntentValueQuery {
    @MainActor
    func values(for input: SemanticContentDescriptor) async throws -> [StudySetEntity] {
        let labels: [String] = input.labels
        guard !labels.isEmpty else { return [] }
        let library: [StudySet] = await IntentLibrary.sets()
        var scored: [(score: Int, set: StudySet)] = []
        for set in library {
            let names: [String] = [set.name, set.subject] + (set.tags ?? [])
            var best: Int = 0
            for label in labels {
                let one: Int = SubjectMatch.score(query: label, names: names)
                if one > best { best = one }
            }
            if best >= 2 { scored.append((best, set)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.set.name < b.set.name }
        return scored.prefix(12).map { StudySetEntity($0.set) }
    }
}
#endif
