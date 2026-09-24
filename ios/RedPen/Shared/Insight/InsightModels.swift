import Foundation

// What the quiz remembers about HOW a question was answered, not only whether
// it was right: when, how sure the student was beforehand, and - for a wrong
// one - why they think they lost the mark. Foundation only, so the sums built
// on it (Readiness) can be tested without a phone.

/// How sure the student said they were before checking an answer.
enum AnswerConfidence: String, Codable, CaseIterable, Identifiable, Hashable {
    case sure, maybe, guess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sure: return "Sure"
        case .maybe: return "Maybe"
        case .guess: return "Guess"
        }
    }
}

/// Why a mark was lost, in the student's own judgement, picked with one tap
/// after a wrong answer.
enum MistakeReason: String, Codable, CaseIterable, Identifiable, Hashable {
    case didntKnow, misread, changedAnswer, outOfTime, lookalikes

    var id: String { rawValue }

    /// The words on the chip under a wrong answer.
    var title: String {
        switch self {
        case .didntKnow: return "Didn\u{2019}t know it"
        case .misread: return "Misread the question"
        case .changedAnswer: return "Changed a right answer"
        case .outOfTime: return "Ran out of time"
        case .lookalikes: return "Mixed up lookalikes"
        }
    }

    /// A monochrome symbol, drawn in the screen's tint.
    var symbol: String {
        switch self {
        case .didntKnow: return "book.closed"
        case .misread: return "eye"
        case .changedAnswer: return "arrow.uturn.backward"
        case .outOfTime: return "timer"
        case .lookalikes: return "square.on.square"
        }
    }
}

/// One checked answer, with the moment it was checked.
///
/// The per-question history (Store.answerHistory) keeps only right or wrong;
/// this keeps the order they happened in across every question, which is what
/// a "recent accuracy" and a calibration need.
struct AnswerEvent: Codable, Hashable {
    var questionId: UUID
    var correct: Bool
    var date: Date = Date()
    var confidence: AnswerConfidence?
    /// Set on the ready-made history a personal build starts with, so the
    /// screens can say it is an example.
    var isExample: Bool?
}

/// The latest reason given for getting one question wrong.
struct MistakeNote: Codable, Hashable {
    var reason: MistakeReason
    var date: Date = Date()
    var isExample: Bool?
}

/// One line on the rule sheet: what to remember so a missed question is got
/// right next time.
///
/// Keeps its own copy of the question's stem, answer and explanation, so the
/// rule outlives the set it came from and can be rewritten by a model later
/// without the question still being in the library.
struct StudyRule: Codable, Hashable, Identifiable {
    /// The question's id: one rule per question.
    var id: UUID
    var subject: String
    /// The one-line rule itself.
    var text: String
    /// A sentence of support under it - the first of the explanation.
    var detail: String
    var stem: String
    var answer: String
    var explanation: String
    var byAI: Bool = false
    var date: Date = Date()
    var isExample: Bool?
}

/// Rough pass marks, kept apart from ExamTrack on purpose: they move from
/// sitting to sitting and are only here to give the readiness estimate
/// something to be read against.
enum PassMark {
    /// The typical pass mark for a track, as a fraction - approximate.
    static func typical(for track: ExamTrack) -> Double {
        switch track {
        case .usmle: return 0.60
        case .plab: return 0.63
        case .mrcp: return 0.60
        case .mrcs: return 0.70
        case .general: return 0.60
        }
    }
}
