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

    /// Removing options. When the keyed option itself goes, nothing is marked
    /// correct (`correctIndex` -1) until the student picks again - it is
    /// never quietly moved to option A - and `tidied` will not save it so.
    static func removing(_ offsets: IndexSet, from question: MCQQuestion) -> MCQQuestion {
        var out = question
        let keyed: Int = question.correctIndex
        var moved: Int = -1
        var kept: [String] = []
        for (index, option) in question.options.enumerated() where !offsets.contains(index) {
            if index == keyed { moved = kept.count }
            kept.append(option)
        }
        out.options = kept
        out.correctIndex = moved
        return out
    }

    /// Whether an option with words in it is marked correct.
    static func hasKey(_ question: MCQQuestion) -> Bool {
        guard question.options.indices.contains(question.correctIndex) else { return false }
        return !question.options[question.correctIndex].trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The question as it is saved: blank options dropped, which moves
    /// positions too, and the key moved with its option.
    ///
    /// Nil when it cannot be saved: fewer than two options with words in
    /// them, or no option with words marked correct - the keyed option was
    /// emptied to be retyped, or deleted. Falling back to option A there was
    /// the silent wrong key this file exists to prevent; the sheet keeps Done
    /// off and asks for the right answer instead.
    static func tidied(_ question: MCQQuestion) -> MCQQuestion? {
        var out = question
        var moved: Int = -1
        var kept: [String] = []
        for (index, option) in question.options.enumerated() {
            let trimmed: String = option.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if index == question.correctIndex { moved = kept.count }
            kept.append(trimmed)
        }
        guard kept.count >= 2, moved >= 0 else { return nil }
        out.options = kept
        out.correctIndex = moved
        return out
    }
}
