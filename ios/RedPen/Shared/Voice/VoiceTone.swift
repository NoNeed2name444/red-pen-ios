import Foundation

/// How a line is said, by what it is for.
///
/// A person reading questions aloud does not say "Correct" and "Not quite" in
/// the same voice as the question: praise lifts a little, a correction slows
/// and softens, an explanation is unhurried, a time warning is brisk. The
/// phone's voice reads every line flat unless it is told otherwise, which is
/// most of what makes it sound like a machine. Each tone is a small change of
/// pace, pitch and the pauses around the line - small enough that the same
/// person is still talking.
///
/// Foundation only, so the numbers and the wording are tested on Linux
/// (VoiceToneTests); VoiceSpeaker applies them to AVSpeechUtterance.
enum VoiceTone: String, CaseIterable, Sendable {
    /// A question or a prompt, read plainly, with room after it to think.
    case asking
    /// The options of a question, one after another.
    case listing
    /// A right answer.
    case praise
    /// A wrong answer, or none: gentle, not a buzzer.
    case correcting
    /// Why an answer is right: unhurried.
    case explaining
    /// Time running out, or time up: brisk and level.
    case alert
    /// Someone in pain or worried: slower and lower, with a pause first.
    case uneasy
    /// Anything else: the voice as it is.
    case plain

    /// Multiplies the speaker's own rate.
    var pace: Float {
        switch self {
        case .asking: return 1.0
        case .listing: return 0.97
        case .praise: return 1.03
        case .correcting: return 0.95
        case .explaining: return 0.94
        case .alert: return 1.05
        case .uneasy: return 0.92
        case .plain: return 1.0
        }
    }

    /// Multiplies the voice's pitch; 1 is the voice's own.
    var pitch: Float {
        switch self {
        case .praise: return 1.06
        case .correcting: return 0.96
        case .explaining: return 0.98
        case .uneasy: return 0.96
        default: return 1.0
        }
    }

    /// Seconds of quiet before the line: a breath, a little longer before
    /// bad news.
    var before: Double {
        switch self {
        case .correcting, .uneasy: return 0.18
        case .alert: return 0.0
        default: return 0.05
        }
    }

    /// Seconds of quiet after it: longer after a question, so the
    /// microphone does not open on the last word.
    var after: Double {
        switch self {
        case .asking: return 0.35
        case .listing: return 0.25
        case .alert: return 0.1
        default: return 0.2
        }
    }

    // MARK: reading the room

    /// Words a person in pain or afraid would use.
    static let uneasyWords = ["pain", "hurt", "hurts", "hurting", "ache", "aching", "sore", "agony",
                              "worried", "worry", "scared", "afraid", "frightened", "anxious", "nervous",
                              "can't breathe", "dizzy", "sick", "terrible", "awful", "crying"]

    /// The tone a patient's reply is said in: uneasy when it speaks of pain or
    /// fear, plain otherwise. Whole words only, so "painting" is not pain.
    static func forPatient(_ reply: String) -> VoiceTone {
        let lower = reply.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for word in uneasyWords {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            if lower.range(of: pattern, options: .regularExpression) != nil { return .uneasy }
        }
        return .plain
    }

    // MARK: saying the same thing in different words

    /// What opens a right answer. Said in turn, so a long session does not
    /// hear the same word forty times.
    static let praiseOpeners = ["Correct", "That's right", "Yes, well done", "Spot on", "Exactly"]

    /// What opens a wrong answer.
    static let correctionOpeners = ["Not quite", "Close, but no", "Not this time", "Not that one"]

    /// The opener for the `turn`th answer of its kind; any turn, even a
    /// negative one, gives an opener.
    static func opener(praise: Bool, turn: Int) -> String {
        let words = praise ? praiseOpeners : correctionOpeners
        let count = words.count
        return words[((turn % count) + count) % count]
    }

    /// One answer's verdict and explanation, each with its own tone, as the
    /// lines to say in order. The explanation is left out when empty.
    static func verdict(praise: Bool, turn: Int, answer: String, why: String) -> [(String, VoiceTone)] {
        let opener = opener(praise: praise, turn: turn)
        let said = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [(String, VoiceTone)] = []
        if praise {
            lines.append((said.isEmpty ? "\(opener)." : "\(opener), \(said).", .praise))
        } else {
            lines.append((said.isEmpty ? "\(opener)." : "\(opener). It's \(said).", .correcting))
        }
        let reason = why.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { lines.append((reason, .explaining)) }
        return lines
    }
}
