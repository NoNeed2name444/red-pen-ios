import Foundation

/// What every question writer shares: how many questions a call and a set may
/// hold, and what makes a written question acceptable. The questions
/// themselves are written by the writer route only (MedicalGenerate; the
/// owner, 23 Oct: "Lock it"), never on the phone.
enum MCQGenerator {

    /// Questions per model call: a batch much bigger than this starts losing
    /// the plot partway through and returns half a question.
    static let maxQuestionsPerCall = 6

    /// No real ceiling: a student may ask for as many as they like from one
    /// source, and generation runs in batches that each avoid what came before.
    /// The number only stops a typo of extra zeros from running for a week.
    static let maxQuestionsTotal = 10_000

    // MARK: what makes a question acceptable

    /// The backstop behind rule 4 of the prompt: reject a question whose best
    /// answer is both the single longest option and meaningfully longer than
    /// the rest, so "pick the longest" stays a losing strategy even when the
    /// model ignored the instruction.
    static func lengthBalanced(_ options: [String], correctIndex: Int) -> Bool {
        let lens = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard lens.indices.contains(correctIndex) else { return false }
        let correctLen = lens[correctIndex]
        let others = lens.enumerated().filter { $0.offset != correctIndex }.map(\.element)
        guard !others.isEmpty else { return false }
        let maxOther = others.max() ?? 0
        let avgOther = Double(others.reduce(0, +)) / Double(others.count)
        return !(correctLen > maxOther && Double(correctLen) > avgOther * 1.3)
    }

    /// Every written question passes this check. Four options are as
    /// good as five: NEET-PG, FMGE, SMLE and the Gulf exams use four
    /// (ExamCatalog), and the prompt asks for the chosen exam's count.
    static func isValidQuestion(stem: String, options: [String], correctIndex: Int) -> Bool {
        (4...5).contains(options.count) && options.indices.contains(correctIndex) &&
            !stem.trimmingCharacters(in: .whitespaces).isEmpty &&
            lengthBalanced(options, correctIndex: correctIndex)
    }
}
