import Foundation

/// Turns a missed question into one line worth remembering.
///
/// Without a model the line is mechanical but honest: the question being
/// asked, an arrow, and the right answer, with the explanation's first
/// sentence under it. With a writer model the lines can be rewritten as the
/// kind of rule an examiner is testing ("Painless jaundice + palpable
/// gallbladder \u{2192} think pancreatic head carcinoma").
///
/// Foundation only, so the text handling can be tested without a phone.
enum RuleWriter {

    /// Questions sent to the model in one call.
    static let batchSize = 10

    // MARK: without a model

    /// A rule for one question, built from its own words.
    static func plainRule(for question: MCQQuestion, subject: String) -> StudyRule {
        let answer = question.options.indices.contains(question.correctIndex)
            ? question.options[question.correctIndex] : ""
        let text = "\(askedPart(of: question.stem)) \u{2192} \(answer)"
        return StudyRule(id: question.id, subject: subject, text: text,
                         detail: firstSentence(of: question.explanation),
                         stem: question.stem, answer: answer, explanation: question.explanation)
    }

    /// The sentence the stem ends by asking, or its first twelve words when
    /// it asks nothing in so many words.
    static func askedPart(of stem: String) -> String {
        let text = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mark = text.lastIndex(of: "?") {
            let before = text[..<mark]
            // back to the end of the sentence before it
            let start = before.lastIndex(where: { ".!?\n".contains($0) }).map { text.index(after: $0) }
                ?? text.startIndex
            let asked = text[start...mark].trimmingCharacters(in: .whitespacesAndNewlines)
            if asked.count >= 8 { return asked }
        }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        let head = words.prefix(12).joined(separator: " ")
        return words.count > 12 ? head + "\u{2026}" : head
    }

    /// Up to and including the first full stop that ends a sentence.
    static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let ch = trimmed[index]
            let next = trimmed.index(after: index)
            if ".!?".contains(ch), next == trimmed.endIndex || trimmed[next].isWhitespace {
                return String(trimmed[...index])
            }
            index = next
        }
        return trimmed
    }

    // MARK: with a model

    /// The request for one batch: every question numbered, with its answer
    /// and explanation, and the reply's shape spelled out.
    static func prompt(for rules: [StudyRule]) -> String {
        var lines = [
            "You are helping a medical student build a rule sheet for their exam.",
            "For each question below, write ONE precise, exam-style rule line (at most 25 words) that would let the student answer this kind of question correctly next time. State the discriminating clue and the answer, e.g. \"Painless jaundice + palpable gallbladder \u{2192} pancreatic head carcinoma\". No preamble, no numbering inside the rule, no hedging.",
            "Reply with JSON only, in exactly this shape, with one rule per question in the same order: {\"rules\": [\"...\", \"...\"]}",
            ""
        ]
        for (i, rule) in rules.enumerated() {
            lines.append("Question \(i + 1): \(rule.stem)")
            lines.append("Correct answer: \(rule.answer)")
            if !rule.explanation.isEmpty {
                lines.append("Explanation: \(String(rule.explanation.prefix(600)))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private struct Reply: Decodable { var rules: [String] }

    /// The rule lines in a reply, in order, or nil when it is not the JSON
    /// asked for.
    static func parse(_ raw: String) -> [String]? {
        let text = LLMText.stripThinking(raw)
        guard let data = LLMText.jsonObject(in: text),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return reply.rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Rewrites `rules` with the model, `batchSize` at a time, calling
    /// `onBatch` with each batch's new lines by rule id as they arrive, so the
    /// sheet fills in as it goes. A batch that fails is skipped; the rules in
    /// it keep their plain wording.
    static func write(_ rules: [StudyRule], with backend: LLMBackend,
                      onBatch: @MainActor ([UUID: String]) -> Void) async {
        var start = 0
        while start < rules.count {
            if Task.isCancelled { return }
            let batch = Array(rules[start..<min(start + batchSize, rules.count)])
            start += batchSize
            var turns: [ChatTurn] = [.user(prompt(for: batch))]
            if backend.isOnDevice { turns = LLMText.noThinking(turns) }
            guard let reply = try? await backend.complete(turns, maxTokens: 120 * batch.count + 200,
                                                          temperature: 0.3),
                  let lines = parse(reply) else { continue }
            var out: [UUID: String] = [:]
            for (rule, line) in zip(batch, lines) where !line.isEmpty && line.count <= 300 {
                out[rule.id] = line
            }
            if !out.isEmpty { await onBatch(out) }
        }
    }
}
