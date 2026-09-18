import Foundation

/// What editing a question is allowed to do to it.
///
/// One rule, and it is the reason this is a file of its own rather than a
/// closure in a sheet: `correctIndex` is a POSITION, and every edit that
/// removes an option shifts the positions after it. Get that wrong and the app
/// does not crash or complain - it quietly marks a different option correct,
/// and the student finds out when they are told they got it wrong.
///
/// So the key is remembered by its text before anything moves, and looked up
/// again afterwards.
///
/// Foundation only, so it can be tested. That is why the removal is written out
/// rather than using `remove(atOffsets:)`, which SwiftUI supplies and a test
/// runner has no business importing.
enum MCQEdit {

    static func removing(_ offsets: IndexSet, from question: MCQQuestion) -> MCQQuestion {
        var out = question
        let key = out.options.indices.contains(out.correctIndex)
            ? out.options[out.correctIndex] : nil
        out.options = out.options.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        out.correctIndex = key.flatMap { out.options.firstIndex(of: $0) } ?? 0
        return out
    }

    /// Blank options are dropped on the way out, which moves positions too.
    static func tidied(_ question: MCQQuestion) -> MCQQuestion {
        var out = question
        let key = out.options.indices.contains(out.correctIndex)
            ? out.options[out.correctIndex].trimmingCharacters(in: .whitespaces) : nil
        out.options = out.options
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        out.correctIndex = key.flatMap { out.options.firstIndex(of: $0) } ?? 0
        return out
    }
}
