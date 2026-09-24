import Foundation

/// A single multiple-choice question: a stem, an option list, the index of the
/// correct option, and an explanation shown after checking. `imageIndex`, when
/// present, points into the owning `StudySet.images` array.
struct MCQQuestion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var stem: String
    var options: [String]
    var correctIndex: Int
    var explanation: String
    var imageIndex: Int?
    /// Where this came from, when it was generated from a file - "Lupus, p.14".
    /// Optional because a hand-typed question has no source, and because sets
    /// saved before this existed decode without it.
    var source: String?
    /// The differential reasoned through before the answer was keyed, when
    /// the question is about a diagnosis. Nil for recall questions and for
    /// every set saved before it existed.
    var differential: DifferentialTiers?

    // Spelled out rather than synthesised, so it is obvious that a new field
    // has to be added here too - leaving it out silently drops the field on
    // save, and the loss only shows up after a restart.
    enum CodingKeys: String, CodingKey {
        case id, stem, options, correctIndex, explanation, imageIndex, source, differential
    }
}

/// One question's answer state during a quiz session.
struct MCQAnswer: Codable, Hashable {
    var selected: Int?
    var checked: Bool = false

    func isCorrect(for question: MCQQuestion) -> Bool {
        checked && selected == question.correctIndex
    }
}
