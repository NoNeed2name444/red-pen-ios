import Foundation

/// Plain-text import/export shape for a quick hand-authored or scripted set,
/// independent of the JSON `Codable` layout above so it's easy to type by
/// hand. One line per question:
///   Stem | OptionA; OptionB; OptionC; OptionD | correctLetter | Explanation
/// or, for Anki QA cards:
///   Front | bullet1; bullet2 | why (optional)
enum PlainTextImport {

    /// The text's lines, whichever line endings it was written with.
    ///
    /// In Swift "\r\n" is ONE character, so splitting on "\n" does not split
    /// a Windows file at all: a pasted list became one question whose
    /// explanation held the rest of the file, and everything else was lost.
    static func lines(_ text: String, keepingEmpty: Bool = false) -> [Substring] {
        let unix = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unix.split(separator: "\n", omittingEmptySubsequences: !keepingEmpty)
    }

    /// The option a letter names: A is 0, B is 1. Nil for anything that is
    /// not a letter from A to Z, rather than quietly A - a blank or a
    /// full-width letter keyed as A marks the student wrong for the right answer.
    static func optionIndex(_ field: String) -> Int? {
        guard let first = field.trimmingCharacters(in: .whitespaces).first,
              first.isLetter, let ascii = first.asciiValue else { return nil }
        // lower-cased by its bit, so "b" and "B" are both 1
        return Int(ascii | 0x20) - 97
    }

    static func parseMCQ(_ text: String) -> [MCQQuestion] {
        lines(text).compactMap { rawLine -> MCQQuestion? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let options = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let correctIndex = optionIndex(parts[2]) else { return nil }
            let explanation = parts.count >= 4 ? parts[3] : ""
            guard !options.isEmpty, correctIndex < options.count else { return nil }
            return MCQQuestion(stem: parts[0], options: options, correctIndex: correctIndex, explanation: explanation)
        }
    }

    /// Cases: one card per line — Topic | case or recall | Question | answer1; answer2
    /// and, for a clinical case, an optional fifth field: its differential,
    /// `Most likely: X (for: ...; against: ...; test: ...) / Expanded: ... / Can't miss: ...`
    static func parseQA(_ text: String) -> [QACard] {
        lines(text).compactMap { rawLine -> QACard? in
            let parts = rawLine.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else { return nil }
            let answers = parts[3].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts[2].isEmpty, !answers.isEmpty else { return nil }
            var card = QACard(topic: parts[0], type: parts[1].lowercased().hasPrefix("case") ? .case : .recall, stem: parts[2], answer: answers)
            if parts.count >= 5 { card.differential = DifferentialTiers.parse(line: parts[4]) }
            return card
        }
    }

    /// OSCE: one or more stations, each a "## Title" line followed by one
    /// step per line until the next "## " heading or the end of the text.
    static func parseOsce(_ text: String) -> [OsceChecklist] {
        var checklists: [OsceChecklist] = []
        var title = ""
        var steps: [String] = []
        func flush() {
            let t = title.trimmingCharacters(in: .whitespaces)
            let s = steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !t.isEmpty, !s.isEmpty { checklists.append(OsceChecklist(title: t, steps: s)) }
            steps = []
        }
        for rawLine in lines(text, keepingEmpty: true) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("##") {
                flush()
                title = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                steps.append(line)
            }
        }
        flush()
        return checklists
    }

    /// Narrate: one line per segment — "en|Text" or "ar|النص"; the language
    /// tag is optional and defaults to "en".
    static func parseNarrate(_ text: String) -> [NarrateSegment] {
        lines(text).compactMap { rawLine -> NarrateSegment? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|")
            if parts.count >= 2, ["en", "ar"].contains(parts[0].trimmingCharacters(in: .whitespaces).lowercased()) {
                let body = parts.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return nil }
                return NarrateSegment(text: body, lang: parts[0].trimmingCharacters(in: .whitespaces).lowercased())
            }
            return NarrateSegment(text: line, lang: "en")
        }
    }

    static func parseAnkiQA(_ text: String) -> [AnkiCard] {
        lines(text).compactMap { rawLine -> AnkiCard? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // a cloze line: the sentence with its hidden part as {{c1::...}},
            // then optionally why it matters
            if parts[0].contains("{{c") && parts[0].contains("::") && parts[0].contains("}}") {
                return AnkiCard(type: .cloze, clozeText: parts[0], why: parts.count >= 2 ? parts[1] : "")
            }
            guard parts.count >= 2 else { return nil }
            let bullets = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let why = parts.count >= 3 ? parts[2] : ""
            guard !bullets.isEmpty else { return nil }
            return AnkiCard(type: .qa, front: parts[0], bullets: bullets, why: why)
        }
    }
}
