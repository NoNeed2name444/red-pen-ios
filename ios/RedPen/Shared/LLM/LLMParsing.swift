import Foundation

// The parts of the model layer that are pure text in, text out: MedVAL's prompt
// and how its answer is read, stripping a reasoning model's working, pulling
// JSON out of a chatty reply, and choosing which part of a lecture a check is
// made against. Foundation only, so Tests/LLMTests.swift can compile and RUN
// them without a model, a phone or a network.

/// What MedVAL made of a piece of generated text.
struct AccuracyVerdict: Hashable, Codable {
    enum Category: String, Codable, CaseIterable {
        case hallucination, omission, certainty, other

        var title: String {
            switch self {
            case .hallucination: return "Hallucination"
            case .omission: return "Omission"
            case .certainty: return "Certainty"
            case .other: return "Other"
            }
        }
    }

    struct Finding: Hashable, Codable {
        var category: Category
        var text: String
    }

    /// 1 no risk, 2 low, 3 moderate, 4 high - MedVAL's own scale.
    var riskLevel: Int
    var findings: [Finding]
    var reasoning: String
    /// Which backend graded it, for the result sheet.
    var checkedBy: String

    /// Levels 1 and 2 cannot change a clinical decision; 3 and 4 can.
    var passed: Bool { riskLevel <= 2 }

    var riskTitle: String {
        switch riskLevel {
        case 1: return "Level 1 \u{2014} no risk"
        case 2: return "Level 2 \u{2014} low risk"
        case 3: return "Level 3 \u{2014} moderate risk"
        default: return "Level 4 \u{2014} high risk"
        }
    }

    var categories: [Category] {
        Category.allCases.filter { c in findings.contains { $0.category == c } }
    }
}

/// MedVAL-4B's own prompt format (from its model card) and its answer format.
enum MedVAL {

    // MARK: the prompt, as MedVAL was trained on it

    static func prompt(instruction: String, input: String, output: String) -> String {
        """
        Your objective is to evaluate the output in comparison to the input composed by an expert.

        Instructions:
        1. Categorize a claim as an error only if it is clinically relevant, considering the nature of the task.
        2. To determine clinical significance, consider clinical understanding, decision-making, and safety.
        3. Some tasks (e.g., summarization) require concise outputs, while others may result in more verbose candidates.
            - For tasks requiring concise outputs, evaluate the clinical impact of the missing information, given the nature of the task.
            - For verbose tasks, evaluate whether the additional content introduces factual inconsistency.

        Your input fields are:
        1. `instruction' (str)
        2. `input' (str)
        3. `output' (str)

        Your output fields are:
        1. `reasoning' (str)
        2. `errors' (str):
            Evaluate the output in comparison to the input and determine errors that exhibit factual inconsistency with the input.

            Instructions:
            - Output format: `Error 1: <brief explanation in a few words>\nError 2: ...'
            - Each error must be numbered and separated by a newline character \\n; do not use newline characters for anything else.
            - Return `None' if no errors are found.
            - Refer to the exact text from the input or output in the error assessments.

            Error Categories:
            1) Fabricated claim:         Introduction of a claim not present in the input.
            2) Misleading justification: Incorrect reasoning, leading to misleading conclusions.
            3) Detail misidentification: Incorrect reference to a detail in the input.
            4) False comparison:         Mentioning a comparison not supported by the input.
            5) Incorrect recommendation: Suggesting a diagnosis/follow-up outside the input.
            6) Missing claim:            Failure to mention a claim present in the input.
            7) Missing comparison:       Omitting a comparison that details change over time.
            8) Missing context:          Omitting details necessary for claim interpretation.
            9) Overstating intensity:    Exaggerating urgency, severity, or confidence.
            10) Understating intensity:  Understating urgency, severity, or confidence.
            11) Other:                   Additional errors not covered.

        3. `risk_level' (Literal[1, 2, 3, 4]):
            The risk level must be an integer from 1, 2, 3, or 4. Assign a risk level to the output from the following options:

            Level 1 (No Risk):       The output should contain no clinically meaningful factual inconsistencies. Any deviations from the input (if present) should not affect clinical understanding, decision-making, or safety.
            Level 2 (Low Risk):      The output should contain subtle or ambiguous inconsistencies that are unlikely to influence clinical decisions or understanding. These inconsistencies should not introduce confusion or risk.
            Level 3 (Moderate Risk): The output should contain inconsistencies that could plausibly affect clinical interpretation, documentation, or decision-making. These inconsistencies may lead to confusion or reduced trust, even if they don't cause harm.
            Level 4 (High Risk):     The output should include one or more inconsistencies that could result in incorrect or unsafe clinical decisions. These errors should pose a high likelihood of compromising clinical understanding or patient safety if not corrected.

        All interactions will be structured in the following way, with the appropriate values filled in.

        [[ ## instruction ## ]]
        \(instruction)

        [[ ## input ## ]]
        \(input)

        [[ ## output ## ]]
        \(output)

        [[ ## reasoning ## ]]
        # TO_BE_FILLED_BY_MODEL

        [[ ## errors ## ]]
        # TO_BE_FILLED_BY_MODEL

        [[ ## risk_level ## ]]
        # TO_BE_FILLED_BY_MODEL

        [[ ## completed ## ]]
        """
    }

    // MARK: reading the answer

    static func parse(_ reply: String, checkedBy: String) -> AccuracyVerdict {
        let reasoning = section("reasoning", in: reply) ?? ""
        let errorsText = section("errors", in: reply) ?? ""
        // without the field, the text after the last "level" is the best guess;
        // without that either there is no grade to read
        let riskText = section("risk_level", in: reply)
            ?? reply.range(of: "level", options: [.caseInsensitive, .backwards])
                .map { String(reply[$0.upperBound...].prefix(12)) }
            ?? ""

        var findings: [AccuracyVerdict.Finding] = []
        for line in errorsText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.lowercased() != "none",
                  !trimmed.hasPrefix("#") else { continue }
            findings.append(.init(category: category(of: trimmed), text: trimmed))
        }

        // The first digit 1-4 in the risk field; "Level 3 (Moderate Risk)" and
        // a bare "3" both read as 3. Nothing readable is treated as moderate:
        // an unreadable grade is not a pass.
        var risk = riskText.first { "1234".contains($0) }.flatMap { Int(String($0)) } ?? 3
        // a reply that lists errors but grades them "1" is read at least as low risk
        if !findings.isEmpty && risk == 1 { risk = 2 }
        return AccuracyVerdict(riskLevel: risk, findings: findings,
                               reasoning: reasoning, checkedBy: checkedBy)
    }

    private static func section(_ name: String, in reply: String) -> String? {
        guard let start = reply.range(of: "[[ ## \(name) ## ]]") else { return nil }
        let rest = reply[start.upperBound...]
        let end = rest.range(of: "[[ ##")?.lowerBound ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// MedVAL's eleven categories folded into the three the app reports.
    static func category(of line: String) -> AccuracyVerdict.Category {
        let l = line.lowercased()
        if l.contains("missing") || l.contains("omit") { return .omission }
        if l.contains("overstat") || l.contains("understat") || l.contains("intensity")
            || l.contains("certain") || l.contains("confiden") { return .certainty }
        if l.contains("fabricat") || l.contains("misleading") || l.contains("misidentif")
            || l.contains("false comparison") || l.contains("incorrect recommendation")
            || l.contains("hallucinat") { return .hallucination }
        return .other
    }
}

// MARK: - text helpers shared by every backend

enum LLMText {
    /// Doctor-R1 and MedVAL are reasoning models: their answer follows a
    /// `<think>...</think>` block that is working, not output.
    static func stripThinking(_ raw: String) -> String {
        var text = raw
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        } else if text.contains("<think>") {
            // cut off mid-thought: nothing after it is an answer
            text = ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Doctor-R1 and MedVAL are Qwen3 models: "/no_think" on the last user
    /// turn skips the hidden reasoning. On a phone that reasoning can use the
    /// whole length budget before the answer starts, so on-device calls always
    /// skip it; the prompts already say exactly what to produce.
    static func noThinking(_ turns: [ChatTurn]) -> [ChatTurn] {
        guard let last = turns.lastIndex(where: { $0.role == .user }),
              !turns[last].text.contains("/no_think") else { return turns }
        var out = turns
        out[last].text += "\n/no_think"
        return out
    }

    /// The outermost `{...}` in a reply, for models that wrap JSON in prose or
    /// a code fence even when told not to.
    static func jsonObject(in raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }
}

/// Choosing text by overlap, and cutting it into pieces.
enum TextSlicing {

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 })
    }

    /// The paragraphs of a long source that share the most words with `text`.
    static func nearest(_ source: String, to text: String, limit: Int) -> String {
        guard source.count > limit else { return source }
        let wanted = words(text)
        let paragraphs = source.components(separatedBy: "\n\n")
        let ranked = paragraphs.enumerated()
            .map { ($0.offset, words($0.element).intersection(wanted).count) }
            .sorted { $0.1 > $1.1 }
        var chosen: [Int] = []
        var size = 0
        for (index, score) in ranked where score > 0 {
            let length = paragraphs[index].count
            if size + length > limit { continue }
            chosen.append(index)
            size += length
        }
        guard !chosen.isEmpty else { return String(source.prefix(limit)) }
        // back in reading order, so the check reads the source as written
        return chosen.sorted().map { paragraphs[$0] }.joined(separator: "\n\n")
    }

    /// Paragraph-aligned slices of roughly equal length.
    static func slice(_ text: String, into count: Int, maxChars: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !paragraphs.isEmpty else { return [] }
        let target = min(maxChars, max(800, text.count / max(1, count)))
        var slices: [String] = []
        var current = ""
        for p in paragraphs {
            if !current.isEmpty && current.count + p.count > target {
                slices.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + String(p.prefix(maxChars))
        }
        if !current.isEmpty { slices.append(current) }
        let wanted = max(1, count)
        guard slices.count > wanted else { return slices }
        // More pieces than pages: neighbours are merged rather than the tail
        // dropped, so the last chapter of a lecture is never silently lost.
        // Only a source bigger than the whole budget loses anything, and
        // then evenly, not from the end.
        var merged: [String] = []
        for bucket in 0..<wanted {
            let from = bucket * slices.count / wanted
            let to = (bucket + 1) * slices.count / wanted
            merged.append(String(slices[from..<to].joined(separator: "\n\n").prefix(maxChars)))
        }
        return merged
    }
}
