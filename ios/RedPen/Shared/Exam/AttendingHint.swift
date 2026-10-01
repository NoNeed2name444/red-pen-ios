import Foundation

// The attending's hint: the next step in the reasoning - what the key finding
// points to, which kind of option can be ruled out - without naming the
// answer. Written by the model when there is one, checked so it never gives
// the answer away, and otherwise made from the item's own differential or a
// fixed nudge.
//
// Foundation only, so the prompt, the leak check and the fallbacks can be
// tested on Linux.

enum AttendingHint {

    /// What the writer is told.
    static let instructions: String = [
        "You are an experienced attending physician teaching a medical student at the bedside.",
        "The student is stuck on the question below. Give ONE short Socratic nudge - the next reasoning step: which finding matters most and what it points towards in general terms, or which category of option it rules out.",
        "NEVER name, paraphrase, abbreviate or hint at the wording of the correct answer, and never say which option letter is right. Do not list the options back.",
        "At most two sentences, plain text, no preamble."
    ].joined(separator: "\n")

    /// The item as the writer sees it: the stem, the options, and the
    /// differential when there is one (so the nudge follows the same route).
    static func input(stem: String, options: [String], answer: String,
                      differential: DifferentialTiers?) -> String {
        var lines: [String] = ["Question:", stem, "", "Options:"]
        for o in options { lines.append("- " + o) }
        lines.append("")
        lines.append("Correct answer (NEVER reveal it): " + answer)
        if let tiers = differential, !tiers.isEmpty {
            lines.append("")
            lines.append("The expert's differential:")
            lines.append(tiers.checkText)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: the leak check

    /// Words too common in medicine to give an answer away on their own.
    static let commonWords: Set<String> = [
        "acute", "chronic", "disease", "syndrome", "with", "without", "from", "into",
        "that", "this", "which", "the", "and", "primary", "secondary", "left", "right",
        "type", "deficiency", "infection", "failure", "test", "level", "levels", "blood",
        "oral", "intravenous", "dose", "start", "give", "refer", "urgent", "normal"
    ]

    static func words(_ text: String) -> [String] {
        let lowered: String = text.lowercased()
        let parts: [Substring] = lowered.split { !$0.isLetter && !$0.isNumber }
        return parts.map(String.init)
    }

    /// Whether `hint` gives the answer away: it contains the answer whole, or
    /// a distinctive word of it - one not in the stem and in no other option.
    static func leaks(_ hint: String, answer: String, stem: String, otherOptions: [String]) -> Bool {
        let h: [String] = words(hint)
        let a: [String] = words(answer)
        guard !a.isEmpty else { return false }
        let hintLine: String = " " + h.joined(separator: " ") + " "
        let answerLine: String = " " + a.joined(separator: " ") + " "
        if hintLine.contains(answerLine) { return true }
        var elsewhere: Set<String> = Set(words(stem))
        for o in otherOptions { elsewhere.formUnion(words(o)) }
        let hintWords: Set<String> = Set(h)
        for w in a where w.count > 3 && !commonWords.contains(w) && !elsewhere.contains(w) {
            if hintWords.contains(w) { return true }
            // "hyperthyroid" for "hyperthyroidism": a shared long stem
            let root: String = String(w.prefix(7))
            if root.count == 7 && h.contains(where: { $0.count >= 7 && $0.hasPrefix(root) }) { return true }
        }
        return false
    }

    /// The model's reply tidied to the nudge itself, or nil when it is empty
    /// or gives the answer away.
    static func accept(_ reply: String, answer: String, stem: String, otherOptions: [String]) -> String? {
        var text: String = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Hint:", "hint:", "Nudge:", "Attending:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D} "))
        guard text.count >= 12 else { return nil }
        if text.count > 400 { text = String(text.prefix(400)) + "\u{2026}" }
        if leaks(text, answer: answer, stem: stem, otherOptions: otherOptions) { return nil }
        return text
    }

    // MARK: without a model

    /// A nudge made from the differential, or a fixed one. Never names the
    /// answer: a finding that would give it away is passed over.
    static func fallback(answer: String, stem: String, options: [String],
                         differential: DifferentialTiers?) -> String {
        let others: [String] = options.filter { $0 != answer }
        if let tiers = differential {
            // a can't-miss or alternative that is not the answer: what argues against it
            let rivals: [DifferentialEntry] = tiers.cantMiss + tiers.expanded
            for rival in rivals where !rival.against.isEmpty {
                let line: String = "Before you settle, rule something out: what in the stem argues against \(rival.name)? Look at \(rival.against[0].lowercased())."
                if !leaks(line, answer: answer, stem: stem, otherOptions: others) { return line }
            }
            for entry in tiers.mostLikely {
                for finding in entry.supporting {
                    let line: String = "The finding that carries this question is \(finding.lowercased()). What does it point to, and which options can't explain it?"
                    if !leaks(line, answer: answer, stem: stem, otherOptions: others) { return line }
                }
            }
        }
        return "Find the single most specific finding in the stem - the one that fits only one of the options - and ask what it points to. Then rule out any option that can't explain it."
    }
}

/// Hints kept once written, so a question asks the model only once.
/// Keyed by the item's id; the oldest go first past the cap.
struct HintCache: Codable, Hashable {
    static let cap = 400
    var hints: [String: String] = [:]
    var order: [String] = []

    func hint(for id: UUID) -> String? { hints[id.uuidString] }

    mutating func store(_ hint: String, for id: UUID) {
        let key: String = id.uuidString
        if hints[key] == nil { order.append(key) }
        hints[key] = hint
        while order.count > Self.cap {
            let old: String = order.removeFirst()
            hints[old] = nil
        }
    }
}
