import Foundation

// MARK: - What VoiceOver says
//
// Foundation only, so the Linux suite (Tests/AccessibilityTextTests.swift)
// can check every sentence without a simulator. The views read these rather
// than building their own strings, so the same thing is said the same way on
// every screen: "back in 4 days", never "back in in 4 d".

enum SpokenText {

    // MARK: intervals

    /// The scheduler's short interval ("in 4 d", "10 min", "2 hr") without
    /// its leading "in ", for putting after "back in".
    static func bareInterval(_ label: String) -> String {
        let trimmed: String = label.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("in ") else { return trimmed }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// What a rating button shows under its word: "back in 4 d".
    static func backIn(_ label: String) -> String {
        let bare: String = bareInterval(label)
        return bare.isEmpty ? "" : "back in " + bare
    }

    /// The same interval in words: "in 4 d" -> "4 days", "1 min" -> "1 minute".
    static func interval(_ label: String) -> String {
        let bare: String = bareInterval(label)
        let parts: [Substring] = bare.split(separator: " ")
        guard parts.count == 2, let n = Int(parts[0]) else { return bare }
        let unit: String
        switch parts[1].lowercased() {
        case "min", "m": unit = "minute"
        case "hr", "h": unit = "hour"
        case "d": unit = "day"
        default: return bare
        }
        return count(n, unit)
    }

    /// "Good, back in 4 days" - a rating button's whole spoken value.
    static func rating(_ title: String, interval label: String) -> String {
        let words: String = interval(label)
        return words.isEmpty ? title : title + ", back in " + words
    }

    // MARK: numbers

    /// "1 card", "3 cards"; a noun that does not just take an s gives its
    /// plural.
    static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        let many: String = plural ?? noun + "s"
        return "\(n) " + (n == 1 ? noun : many)
    }

    /// 0.724 -> "72 percent". Out-of-range values are clamped.
    static func percent(_ fraction: Double) -> String {
        let safe: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return "\(Int((safe * 100).rounded())) percent"
    }

    /// A clock read aloud: "2 minutes 5 seconds", "1 minute", "40 seconds".
    static func duration(seconds: Int) -> String {
        let s: Int = max(0, seconds)
        let minutes: Int = s / 60
        let rest: Int = s % 60
        if minutes == 0 { return count(rest, "second") }
        if rest == 0 { return count(minutes, "minute") }
        return count(minutes, "minute") + " " + count(rest, "second")
    }

    // MARK: answers

    /// What an MCQ option says after the answer is checked - whether it is
    /// the right one and whether it was the one picked - or before, whether
    /// it is chosen. Empty when there is nothing to add.
    static func optionState(checked: Bool, isCorrect: Bool, isChosen: Bool) -> String {
        if !checked { return isChosen ? "Chosen" : "" }
        if isCorrect && isChosen { return "Correct, your answer" }
        if isCorrect { return "Correct answer" }
        if isChosen { return "Your answer, incorrect" }
        return ""
    }

    /// Said as soon as an answer is checked, so a VoiceOver user does not
    /// have to go looking for the colours: "Correct." or "Incorrect. The
    /// answer is C: Aortic stenosis."
    static func answerResult(correct: Bool, letter: String, answer: String) -> String {
        if correct { return "Correct." }
        let text: String = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !letter.isEmpty else { return "Incorrect." }
        if text.isEmpty { return "Incorrect. The answer is \(letter)." }
        return "Incorrect. The answer is \(letter): \(text)."
    }

    /// A card face with its cloze blanks said as "blank" rather than three
    /// "white square" characters.
    static func clozeFront(_ shown: String, blank: String = "\u{25A2}\u{25A2}\u{25A2}") -> String {
        shown.replacingOccurrences(of: blank, with: "blank")
    }
}

/// A day on the study calendar, as one of five steps rather than a shade
/// alone: the step picks the shade, the size of the dot drawn in the cell
/// under Differentiate Without Colour, and the word VoiceOver says.
enum HeatLevel: Int, CaseIterable {
    case none = 0, light, some, lots, most

    /// Where `count` sits against the busiest day shown.
    static func of(count: Int, busiest: Int) -> HeatLevel {
        guard count > 0, busiest > 0 else { return .none }
        let share: Double = min(1, Double(count) / Double(busiest))
        if share <= 0.25 { return .light }
        if share <= 0.5 { return .some }
        if share < 1 { return .lots }
        return .most
    }

    /// 0...1: how strongly the cell is shaded, and how big its dot is.
    var strength: Double { Double(rawValue) / 4 }

    var word: String {
        switch self {
        case .none: return "nothing"
        case .light: return "a little"
        case .some: return "some"
        case .lots: return "a lot"
        case .most: return "the most"
        }
    }
}
