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
    /// The clinical-reasoning issues the checker named (a finding that
    /// contradicts the keyed answer, a can't-miss diagnosis left open, an
    /// unsupported claim), also counted among `findings`. Nil when the reply
    /// had none, and for every verdict saved before the field existed.
    var reasoningIssues: [String]? = nil

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

        4. `reasoning_issues' (str):
            \(reasoningChecks)

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

        [[ ## reasoning_issues ## ]]
        # TO_BE_FILLED_BY_MODEL

        [[ ## completed ## ]]
        """
    }

    /// The clinical-reasoning checks added to MedVAL's own, after the way
    /// Glass Health lays out a differential: does the keyed answer fit every
    /// key finding, is a can't-miss diagnosis better supported or left
    /// unexcluded, and is every claim backed by the input or the evidence.
    /// Asked for as a fourth field AFTER MedVAL's three, so a model trained on
    /// MedVAL's exact format still writes those first and unchanged; an
    /// answer without the field reads exactly as before.
    static let reasoningChecks: String = [
        "Check the clinical reasoning of the output, the way a diagnostic reasoning tool checks a differential:",
        "    a) Does the keyed answer (or the stated diagnosis) fit ALL the key findings given in the output? Name any finding that contradicts it.",
        "    b) Is a can't-miss (dangerous) diagnosis better supported by the findings than the keyed answer, or not excluded where the question implies it should be?",
        "    c) Is every factual claim in the explanation or answer supported by the input or by any reference evidence given? Name any claim that is not.",
        "    - Output format: one issue per line, each starting with its kind: `Contradicting finding: <the finding, and why it does not fit>', `Can't miss: <the diagnosis, and why>', or `Unsupported claim: <the claim>'.",
        "    - Return `None' if there are no issues, or if the output has no answer or diagnosis to check.",
        "    - Take these into account in risk_level: a contradicting finding or a can't-miss diagnosis left open is at least Level 3; an unsupported claim is at least Level 2, and Level 3 or 4 if it could change a clinical decision.",
    ].joined(separator: "\n")

    // MARK: reading the answer

    static func parse(_ reply: String, checkedBy: String) -> AccuracyVerdict {
        let reasoning = section("reasoning", in: reply) ?? ""
        let errorsText = section("errors", in: reply) ?? ""

        var findings: [AccuracyVerdict.Finding] = []
        for line in errorsText.components(separatedBy: .newlines) {
            let trimmed: String = line.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-*\u{2022}")))
            // "None.", "`None'", "Error 1: None" - the prompt's own quoting
            // and a full stop are still nothing to report
            let bare: String = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".`' "))
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  !saysNone(bare), !labelSaysNone(bare) else { continue }
            findings.append(.init(category: category(of: trimmed), text: trimmed))
        }

        // The first digit 1-4 in the risk field; "Level 3 (Moderate Risk)" and
        // a bare "3" both read as 3. Without the field, the grade written after
        // "risk level" in the prose (looseRisk). Nothing readable is treated as
        // moderate: an unreadable grade is not a pass.
        var risk: Int
        if let riskText = section("risk_level", in: reply) {
            risk = riskText.first { "1234".contains($0) }.flatMap { Int(String($0)) } ?? 3
        } else {
            risk = looseRisk(in: reply) ?? 3
        }
        // the clinical-reasoning checks: each issue is a finding too, and the
        // serious kinds hold the grade up whatever number was written
        let issues: [ReasoningIssue] = reasoningIssues(in: reply)
        for issue in issues {
            findings.append(.init(category: issue.kind.category, text: issue.text))
            risk = max(risk, issue.kind.floor)
        }
        // a reply that lists errors but grades them "1" is read at least as low risk
        if !findings.isEmpty && risk == 1 { risk = 2 }
        var verdict = AccuracyVerdict(riskLevel: risk, findings: findings,
                                      reasoning: reasoning, checkedBy: checkedBy)
        verdict.reasoningIssues = issues.isEmpty ? nil : issues.map(\.text)
        return verdict
    }

    /// One line of the optional `reasoning_issues` field.
    struct ReasoningIssue: Hashable {
        enum Kind: Hashable {
            case contradictingFinding, cantMiss, unsupportedClaim, other

            /// The lowest risk level an issue of this kind allows.
            var floor: Int {
                switch self {
                case .contradictingFinding, .cantMiss: return 3
                case .unsupportedClaim, .other: return 2
                }
            }

            /// Where it is counted among the app's three kinds of finding: a
            /// keyed answer the findings contradict is misleading reasoning, a
            /// danger left open is an omission, an unbacked claim is made up.
            var category: AccuracyVerdict.Category {
                switch self {
                case .contradictingFinding, .unsupportedClaim: return .hallucination
                case .cantMiss: return .omission
                case .other: return .other
                }
            }
        }
        var kind: Kind
        var text: String
    }

    /// The `reasoning_issues` field, if the reply has one; "None" is none.
    static func reasoningIssues(in reply: String) -> [ReasoningIssue] {
        guard let body = section("reasoning_issues", in: reply) else { return [] }
        var out: [ReasoningIssue] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed: String = line.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-*\u{2022}")))
            let bare: String = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".`' "))
            // "Contradicting finding: None" fills in the kind and reports nothing
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !saysNone(bare),
                  !labelSaysNone(bare) else { continue }
            out.append(ReasoningIssue(kind: issueKind(of: bare), text: trimmed))
        }
        return out
    }

    /// "None", "None found", "No issues.", "N/A": a line that says there is
    /// nothing to report is not an issue.
    static func saysNone(_ lowered: String) -> Bool {
        if onlyNone(lowered) { return true }
        let openers: [String] = ["none ", "none,", "no issues ", "no issue ", "no reasoning issues ", "nothing to report",
                                 "no errors ", "no error "]
        return openers.contains { lowered.hasPrefix($0) }
    }

    /// The whole of the text is a way of writing "none".
    static func onlyNone(_ lowered: String) -> Bool {
        let empty: [String] = ["none", "n/a", "na", "nil", "nothing", "no issues", "no issue", "no reasoning issues",
                               "no errors", "no error", "not applicable", "none found", "none identified",
                               "none noted", "none detected", "no errors found", "no issues found"]
        return empty.contains(lowered)
    }

    /// A line that names a kind and then nothing: "Contradicting finding:
    /// None", "Can't miss: n/a", "Error 1: None." The label is short - a
    /// sentence with a colon in it is not a label - and what follows it has
    /// to be nothing but "none": "Missing claim: none of the doses is
    /// given" is a finding.
    static func labelSaysNone(_ lowered: String) -> Bool {
        guard let colon = lowered.firstIndex(of: ":") else { return false }
        let label: String = String(lowered[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.count <= 30 else { return false }
        let rest: String = String(lowered[lowered.index(after: colon)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".`' ").union(.whitespaces))
        return onlyNone(rest)
    }

    /// The grade in a reply that did not keep the `[[ ## risk_level ## ]]`
    /// header, as a hosted checker often does not.
    ///
    /// The number written just after "risk level" is the grade; the reply's
    /// prose can go on to mention other levels ("...clearly not a Level 1
    /// output"), so the LAST "level" is the wrong place to look. With no
    /// "risk level" at all, the highest "level N" mentioned: a reply that
    /// names Level 4 and Level 1 is not read as a pass.
    static func looseRisk(in reply: String) -> Int? {
        let labelled: [Int] = grades(after: ["risk_level", "risk level", "risk-level"], in: reply)
        if let first = labelled.first { return first }
        return grades(after: ["level"], in: reply).max()
    }

    /// The grade (1-4) written within a few characters after each place one
    /// of `labels` appears, in reading order.
    static func grades(after labels: [String], in reply: String) -> [Int] {
        var found: [(at: String.Index, grade: Int)] = []
        for label in labels {
            var from: String.Index = reply.startIndex
            while let hit = reply.range(of: label, options: .caseInsensitive, range: from..<reply.endIndex) {
                let near: Substring = reply[hit.upperBound...].prefix(12)
                if let digit = near.first(where: { "1234".contains($0) }), let grade = Int(String(digit)) {
                    found.append((at: hit.lowerBound, grade: grade))
                }
                from = hit.upperBound
            }
        }
        return found.sorted { $0.at < $1.at }.map(\.grade)
    }

    static func issueKind(of lowered: String) -> ReasoningIssue.Kind {
        let cantMiss: [String] = ["can't miss", "can\u{2019}t miss", "cannot miss", "cant miss", "can't-miss"]
        // the kind the line starts with wins over a word further along it
        if lowered.hasPrefix("contradict") { return .contradictingFinding }
        if cantMiss.contains(where: { lowered.hasPrefix($0) }) { return .cantMiss }
        if lowered.hasPrefix("unsupported") { return .unsupportedClaim }
        if lowered.contains("contradict") { return .contradictingFinding }
        if cantMiss.contains(where: { lowered.contains($0) }) { return .cantMiss }
        if lowered.contains("unsupported") || lowered.contains("not supported") { return .unsupportedClaim }
        return .other
    }

    static func section(_ name: String, in reply: String) -> String? {
        guard let start = reply.range(of: "[[ ## \(name) ## ]]") else { return nil }
        let rest = reply[start.upperBound...]
        let end = rest.range(of: "[[ ##")?.lowerBound ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: saying what a screen did

    /// The status line after a generated set was screened item by item.
    /// "Accuracy checked." only when every item actually got a grade: an item
    /// the checker could not reach (offline, the day's allowance used, no
    /// model loaded) was kept without a check, and saying otherwise tells the
    /// student a Level 4 item was looked at when nothing looked at it.
    static func screenNote(total: Int, removed: Int, flagged: Int, unchecked: Int) -> String {
        var note: String = unchecked == 0 ? " Accuracy checked." : uncheckedNote(unchecked, of: total)
        if removed > 0 { note += " \(removed) removed as high risk." }
        if flagged > 0 { note += " \(flagged) flagged moderate risk." }
        return note
    }

    /// " 3 of 10 could not be checked.", " Not checked for accuracy - the
    /// checker could not be reached." when none were, or "" when all were.
    static func uncheckedNote(_ unchecked: Int, of total: Int) -> String {
        guard unchecked > 0 else { return "" }
        if unchecked >= total {
            return " Not checked for accuracy \u{2014} the checker could not be reached."
        }
        return " \(unchecked) of \(total) could not be checked for accuracy."
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

    /// Each object in the `list` array of a JSON reply, read one at a time,
    /// so one malformed item costs only itself rather than the whole reply.
    /// A reply cut off mid-array (the length limit hit) still gives back
    /// every item that was complete.
    static func jsonItems(in raw: String, list key: String) -> [[String: Any]] {
        if let data = jsonObject(in: raw),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let list = object[key] as? [Any] {
            return list.compactMap { $0 as? [String: Any] }
        }
        return completeItems(in: raw, list: key)
    }

    /// The complete `{...}` objects inside a `"list": [` array that may
    /// never close. Braces inside strings are not counted.
    static func completeItems(in raw: String, list key: String) -> [[String: Any]] {
        guard let named = raw.range(of: "\"" + key + "\""),
              let open = raw[named.upperBound...].firstIndex(of: "[") else { return [] }
        var out: [[String: Any]] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.Index? = nil
        var i: String.Index = raw.index(after: open)
        while i < raw.endIndex {
            let c: Character = raw[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth < 0 { break }
                if depth == 0, let from = start {
                    let piece: String = String(raw[from...i])
                    if let data = piece.data(using: .utf8),
                       let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        out.append(item)
                    }
                    start = nil
                }
            } else if c == "]" && depth == 0 {
                break
            }
            i = raw.index(after: i)
        }
        return out
    }

    /// The keyed option however a model wrote it - 2, "2", "C", or the
    /// option's own text. Nil when it names no option.
    static func keyIndex(_ value: Any?, options: [String]) -> Int? {
        var index: Int? = nil
        if let number = value as? Int {
            index = number
        } else if let text = value as? String {
            let t: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper: [Unicode.Scalar] = Array(t.uppercased().unicodeScalars)
            if let number = Int(t) {
                index = number
            } else if upper.count == 1, let only = upper.first, (65...90).contains(only.value) {
                index = Int(only.value) - 65
            } else {
                index = options.firstIndex { $0.compare(t, options: .caseInsensitive) == .orderedSame }
            }
        }
        guard let index, options.indices.contains(index) else { return nil }
        return index
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
        // A paragraph too long to fit is taken line by line instead: a Word
        // file's text is one page with a line per paragraph and no blank
        // lines, so as one paragraph it could never be chosen at all.
        var paragraphs: [String] = []
        for paragraph in source.components(separatedBy: "\n\n") {
            if paragraph.count > limit {
                paragraphs.append(contentsOf: paragraph.components(separatedBy: "\n"))
            } else {
                paragraphs.append(paragraph)
            }
        }
        let ranked = paragraphs.enumerated()
            .map { ($0.offset, words($0.element).intersection(wanted).count) }
            .sorted { $0.1 > $1.1 }
        var chosen: [Int] = []
        var size = 0
        for (index, score) in ranked where score > 0 {
            // the blank line each one is joined with counts too
            let length: Int = paragraphs[index].count + (chosen.isEmpty ? 0 : 2)
            if size + length > limit { continue }
            chosen.append(index)
            size += length
        }
        guard !chosen.isEmpty else { return String(source.prefix(limit)) }
        // back in reading order, so the check reads the source as written
        return chosen.sorted().map { paragraphs[$0] }.joined(separator: "\n\n")
    }

    /// The pages that share the most words with `text`, best first, up to
    /// `limit` characters; nil when no page shares a word with it.
    ///
    /// A page bigger than the room left is cut down to its own nearest
    /// paragraphs rather than ending the search: a Word file is kept as ONE
    /// page, so stopping at the first page that does not fit meant a Word
    /// lecture was never used at all, and the check fell back to "no source".
    static func nearestPages(_ pages: [(heading: String, text: String)], to text: String,
                             limit: Int) -> String? {
        let wanted = words(text)
        let ranked = pages.map { page -> (heading: String, text: String, score: Int) in
            (page.heading, page.text, words(page.text).intersection(wanted).count)
        }.sorted { $0.score > $1.score }
        // less than this left is not worth a page
        let smallest: Int = min(200, max(1, limit / 4))
        var out = ""
        for page in ranked where page.score > 0 {
            let room: Int = limit - out.count - page.heading.count - 2
            guard room >= smallest else { break }
            let body: String = page.text.count <= room ? page.text : nearest(page.text, to: text, limit: room)
            out += page.heading + body + "\n\n"
        }
        return out.isEmpty ? nil : out
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

// MARK: - what the checker is shown for a question

enum CheckedQuestion {
    /// "A", "B" ... "Z" for any number of options, the same lettering the
    /// deck and the quiz show; past Z, the option's number.
    static func letter(_ index: Int) -> String {
        guard index >= 0, index < 26, let scalar = UnicodeScalar(65 + index) else { return "\(index + 1)" }
        return String(Character(scalar))
    }

    /// A question as the checker reads it. A sixth option is F, not a second
    /// E, and the key names the option that is actually keyed; a key that
    /// points at no option (a hand-written or imported file's -1) is said to
    /// be missing rather than read out of range.
    static func text(stem: String, options: [String], correctIndex: Int, explanation: String) -> String {
        let lines: [String] = options.enumerated().map { letter($0.offset) + ". " + $0.element }
        let key: String = options.indices.contains(correctIndex) ? letter(correctIndex) : "none keyed"
        return stem + "\n" + lines.joined(separator: "\n") + "\nAnswer: " + key + "\nExplanation: " + explanation
    }
}
