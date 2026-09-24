import Foundation

/// A rough estimate of the score the student would get if they sat the paper
/// today, and the subjects that would move it most.
///
/// It is an estimate and says so. It starts from recent accuracy, weighted so
/// the latest answers count most, and then takes a little off for what it
/// cannot see: subjects barely practised, and flashcards left waiting for
/// review. The range around it comes from how many answers it is built on, so
/// a handful of answers gives a wide range and a few hundred a narrow one.
///
/// Foundation only: numbers in, numbers out.
struct ReadinessEstimate: Hashable {
    /// The middle of the estimate, 0...1.
    var center: Double
    var low: Double
    var high: Double
    /// Answers the estimate is built on.
    var answers: Int
    /// Recent weighted accuracy before anything was taken off.
    var recentAccuracy: Double
    /// What was taken off for thinly practised subjects, 0...1.
    var coveragePenalty: Double
    /// What was taken off for review cards waiting, 0...1.
    var reviewPenalty: Double
    /// Subjects with fewer than `Readiness.thinSubjectAnswers` answers.
    var thinSubjects: [String]
    var dueCards: Int
    var passMark: Double
    /// Up to three subjects where the most marks are being lost.
    var levers: [Lever]

    struct Lever: Hashable, Identifiable {
        var subject: String
        /// This subject's share of the questions in the library.
        var share: Double
        /// Accuracy so far, or nil when it has not been tried.
        var accuracy: Double?
        /// share x (1 - accuracy): the marks there are to gain.
        var weight: Double
        var id: String { subject }
    }
}

enum Readiness {
    /// Below this there is not enough to say anything useful.
    static let minimumAnswers = 20
    /// How many of the latest answers are read.
    static let window = 200
    /// A subject with fewer answers than this counts as thinly covered.
    static let thinSubjectAnswers = 10
    /// Each answer counts this much less than the one after it, so an answer
    /// 70 back counts about half as much as the latest.
    static let decay = 0.99

    /// `recent` is right/wrong newest first; only the first `window` are read.
    static func estimate(recent: [Bool], subjects: [SubjectStats], dueCards: Int,
                         passMark: Double) -> ReadinessEstimate? {
        let sample = Array(recent.prefix(window))
        guard sample.count >= minimumAnswers else { return nil }

        // recency-weighted accuracy, and how many answers' worth of evidence
        // the weighting leaves (Kish's effective sample size)
        var sumW = 0.0, sumW2 = 0.0, sumRight = 0.0
        var weight = 1.0
        for right in sample {
            sumW += weight
            sumW2 += weight * weight
            if right { sumRight += weight }
            weight *= decay
        }
        let p = sumRight / sumW
        let n = max(1, (sumW * sumW) / sumW2)

        // Wilson score interval at about 90%
        let z = 1.645
        let z2 = z * z
        let denominator = 1 + z2 / n
        let middle = (p + z2 / (2 * n)) / denominator
        let half = z * ((p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()) / denominator

        // subjects barely practised are assumed to go ten points worse
        let totalQuestions = subjects.reduce(0) { $0 + $1.questions }
        let thin = subjects.filter { $0.answered < thinSubjectAnswers && $0.questions > 0 }
        let thinQuestions = thin.reduce(0) { $0 + $1.questions }
        let thinShare = totalQuestions == 0 ? 0 : Double(thinQuestions) / Double(totalQuestions)
        let coverage = 0.10 * thinShare

        // a point off for every twenty cards waiting, at most five
        let review = min(0.05, Double(max(0, dueCards)) * 0.0005)

        let off = coverage + review
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

        var levers: [ReadinessEstimate.Lever] = []
        if totalQuestions > 0 {
            for s in subjects where s.questions > 0 {
                let share = Double(s.questions) / Double(totalQuestions)
                let accuracy: Double? = s.answered > 0 ? s.accuracy : nil
                let gain = share * (1 - (accuracy ?? p))
                guard gain > 0 else { continue }
                levers.append(.init(subject: s.subject, share: share, accuracy: accuracy, weight: gain))
            }
        }
        levers.sort { $0.weight > $1.weight }

        return ReadinessEstimate(
            center: clamp(p - off), low: clamp(middle - half - off), high: clamp(middle + half - off),
            answers: sample.count, recentAccuracy: p,
            coveragePenalty: coverage, reviewPenalty: review,
            thinSubjects: thin.map(\.subject).sorted(), dueCards: max(0, dueCards),
            passMark: passMark, levers: Array(levers.prefix(3)))
    }
}
