import Foundation

/// A single multiple-choice question. Mirrors one entry of the web app's
/// `state.questions` array (see `renderQuestion()` in red-pen-content.html):
/// a stem, an option list, the index of the correct option, and an
/// explanation shown after checking. `imageIndex`, when present, points into
/// the owning `StudySet.images` array — same convention as the web app's
/// `q.imageIndex` / `state.images`.
struct MCQQuestion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var stem: String
    var options: [String]
    var correctIndex: Int
    var explanation: String
    var imageIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id, stem, options, correctIndex, explanation, imageIndex
    }
}

/// One question's answer state during a quiz session — the native
/// equivalent of the web app's `state.answers[i]` (`{selected, checked}`).
struct MCQAnswer: Codable, Hashable {
    var selected: Int? = nil
    var checked: Bool = false

    func isCorrect(for question: MCQQuestion) -> Bool {
        checked && selected == question.correctIndex
    }
}
