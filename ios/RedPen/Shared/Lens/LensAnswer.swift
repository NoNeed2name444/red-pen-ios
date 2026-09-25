import Foundation

// Study Lens: asking a model to answer a question the camera found, and
// reading its reply.
//
// One prompt per question type, each asking for ONE JSON object in a fixed
// shape; the reply is read tolerantly (LLMText strips a reasoning model's
// working and finds the object inside prose or a code fence; keys are read
// under the spellings models actually use). Only the recognised words of the
// one question the student tapped are ever sent - never the camera's picture.
//
// Foundation only; tested in Tests/LensTests.swift.

/// A worked answer to one question, whatever its type. Fields a type does not
/// use stay empty.
struct LensAnswer: Codable, Hashable {
    var type: LensQuestionType
    /// MCQ / single best answer: the keyed option, 0-based, in the order the
    /// options were printed.
    var correctIndex: Int? = nil
    /// The answer in words: the option's text, "True", the missing word, the
    /// calculation's result with its unit, a short answer.
    var answer: String = ""
    /// True/false: the verdict.
    var verdict: Bool? = nil
    /// Why the answer is right.
    var explanation: String = ""
    /// MCQ: one note per printed option - why the key is right, why each
    /// other one is wrong. Empty strings where the model said nothing.
    var optionNotes: [String] = []
    /// Calculation: each working step with its units. OSCE: the checklist,
    /// in order.
    var steps: [String] = []
    var keyPoints: [String] = []
    /// Fill in the blank: the sentence with the blank filled.
    var filled: String = ""
    /// True/false: the statement corrected, when it is false.
    var correction: String = ""
    /// Clinical case.
    var diagnosis: String = ""
    var nextStep: String = ""
    var differential: DifferentialTiers? = nil
    /// Plausible wrong answers, so a question of any type can become a
    /// multiple-choice question.
    var distractors: [String] = []
    /// Which model answered: "Apple on-device model".
    var answeredBy: String = ""
}

// MARK: - The prompt

enum LensPrompt {

    static let system: String = """
    You are a careful medical tutor. A medical student pointed their camera at an exam question and \
    wants it answered and explained. Answer from current, standard medical teaching. If the question \
    text looks garbled by the camera, answer the most sensible reading and say so in the explanation. \
    Reply with ONE JSON object in exactly the shape asked for, and nothing else - no prose, no code fence.
    """

    /// The user turn for one question.
    static func user(for q: DetectedQuestion) -> String {
        let head: String = "Question type: " + q.type.title + "\n\nQuestion:\n" + q.fullText + "\n\n"
        return head + "Reply as JSON:\n" + shape(for: q) + "\n" + rules(for: q.type)
    }

    /// The JSON shape asked for, per type.
    static func shape(for q: DetectedQuestion) -> String {
        switch q.type {
        case .mcq, .bestAnswer:
            let letters: [String] = q.options.indices.map { LensHash.letter($0) }
            let notes: String = letters.map { "\"" + $0 + "\":\"why it is right or wrong\"" }.joined(separator: ",")
            return "{\"answer\":\"the letter of the one best option\",\"explanation\":\"why it is right, 2-4 sentences\","
                + "\"why\":{" + notes + "},\"key_points\":[\"1-3 short facts to remember\"]}"
        case .trueFalse:
            return "{\"verdict\":true,\"explanation\":\"why, 1-3 sentences\",\"correction\":\"the corrected statement if false, else empty\","
                + "\"key_points\":[\"...\"]}"
        case .cloze:
            return "{\"answer\":\"the missing word or phrase\",\"filled\":\"the whole sentence with the blank filled\","
                + "\"explanation\":\"why, 1-3 sentences\",\"distractors\":[\"3 plausible wrong fills\"]}"
        case .calculation:
            return "{\"steps\":[\"each step with its numbers and units\"],\"answer\":\"the final value with its unit\","
                + "\"explanation\":\"the formula and any caveat\",\"distractors\":[\"3 plausible wrong results with units\"]}"
        case .clinicalCase:
            return "{\"diagnosis\":\"the most likely diagnosis\",\"differential\":{\"mostLikely\":[{\"name\":\"...\",\"supporting\":[\"finding\"],"
                + "\"against\":[\"finding\"],\"test\":\"what confirms it\"}],\"expanded\":[...],\"cantMiss\":[...]},"
                + "\"next_step\":\"the single best next step\",\"explanation\":\"the reasoning, 2-4 sentences\","
                + "\"distractors\":[\"3 plausible wrong diagnoses\"]}"
        case .osce:
            return "{\"title\":\"the station in a few words\",\"steps\":[\"each checklist step, in the order it is performed\"],"
                + "\"explanation\":\"what examiners look for\",\"key_points\":[\"common reasons marks are lost\"]}"
        case .shortAnswer, .imageLabel:
            return "{\"answer\":\"the answer, as short as it can be\",\"explanation\":\"why, 2-4 sentences\","
                + "\"key_points\":[\"1-4 points a marker looks for\"],\"distractors\":[\"3 plausible wrong answers\"]}"
        }
    }

    static func rules(for type: LensQuestionType) -> String {
        switch type {
        case .mcq, .bestAnswer:
            return "Give a note for EVERY option in \"why\", keyed by its letter."
        case .trueFalse:
            return "\"verdict\" is the JSON literal true or false."
        case .calculation:
            return "Show every step; carry units through; round only at the end."
        case .clinicalCase:
            return "Reason through the differential before committing to the diagnosis."
        case .osce:
            return "Between 6 and 15 steps, starting with introduction and consent where they apply."
        case .imageLabel:
            return "Only the question's words are sent, not its picture. Answer from the words; if the picture is needed, say what it most likely shows and that it is a best guess."
        case .cloze, .shortAnswer:
            return ""
        }
    }

    /// Said once more when the first reply could not be read.
    static let retry: String = "That reply was not the JSON object asked for. Reply again with only the JSON object."
}

// MARK: - Reading the reply

enum LensAnswerParser {

    /// The answer in a model's reply, or nil when there is none worth showing.
    static func parse(_ reply: String, for q: DetectedQuestion) -> LensAnswer? {
        let text: String = LLMText.stripThinking(reply)
        guard let data = LLMText.jsonObject(in: text),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return fallback(text, for: q)
        }
        var a = LensAnswer(type: q.type)
        a.explanation = string(object, "explanation", "reason", "reasoning", "rationale", "why_right")
        a.keyPoints = strings(object, "key_points", "keyPoints", "points", "takeaways")
        a.distractors = strings(object, "distractors", "wrong_answers", "wrongAnswers")
        switch q.type {
        case .mcq, .bestAnswer:
            return readChoice(object, q, into: a)
        case .trueFalse:
            return readTruth(object, into: a)
        case .cloze:
            a.answer = string(object, "answer", "fill", "missing", "blank")
            a.filled = string(object, "filled", "sentence", "complete")
            if a.filled.isEmpty { a.filled = fill(q.stem, with: a.answer) }
            return a.answer.isEmpty ? nil : a
        case .calculation:
            a.steps = strings(object, "steps", "working", "workings", "solution")
            a.answer = string(object, "answer", "result", "final", "final_answer")
            return a.answer.isEmpty && a.steps.isEmpty ? nil : a
        case .clinicalCase:
            a.diagnosis = string(object, "diagnosis", "most_likely", "mostLikelyDiagnosis", "answer")
            a.nextStep = string(object, "next_step", "nextStep", "management", "next")
            a.differential = DifferentialTiers.parse(json: object["differential"] ?? object["ddx"])
            if a.differential?.isEmpty == true { a.differential = nil }
            a.answer = a.diagnosis
            return a.diagnosis.isEmpty ? nil : a
        case .osce:
            a.steps = strings(object, "steps", "checklist", "items")
            a.answer = string(object, "title", "station", "name")
            return a.steps.isEmpty ? nil : a
        case .shortAnswer, .imageLabel:
            a.answer = string(object, "answer", "short_answer", "label", "result")
            return a.answer.isEmpty ? nil : a
        }
    }

    private static func readChoice(_ object: [String: Any], _ q: DetectedQuestion, into base: LensAnswer) -> LensAnswer? {
        var a = base
        let options: [String] = q.options.map(\.text)
        let raw: Any? = object["answer"] ?? object["correct"] ?? object["key"] ?? object["correct_answer"] ?? object["correctAnswer"]
        guard let index = keyIndex(raw, options: options) else { return nil }
        a.correctIndex = index
        a.answer = options[index]
        a.optionNotes = notes(object["why"] ?? object["options"] ?? object["why_wrong"], count: options.count)
        if a.explanation.isEmpty { a.explanation = a.optionNotes[index] }
        return a
    }

    private static func readTruth(_ object: [String: Any], into base: LensAnswer) -> LensAnswer? {
        var a = base
        let raw: Any? = object["verdict"] ?? object["answer"] ?? object["true"] ?? object["is_true"]
        guard let verdict = truth(raw) else { return nil }
        a.verdict = verdict
        a.answer = verdict ? "True" : "False"
        a.correction = verdict ? "" : string(object, "correction", "corrected", "correct_statement")
        return a
    }

    /// An option index however it was written: "C", "c)", 2, "2", "(C)",
    /// "C. Aspirin", or the option's own text.
    static func keyIndex(_ raw: Any?, options: [String]) -> Int? {
        if let direct = LLMText.keyIndex(raw, options: options) { return direct }
        guard let text = raw as? String else { return nil }
        let t: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = QuestionDetector.match(#"^\(?([A-Za-z])\s*[\.\):]"#, t),
           let i = QuestionDetector.letterIndex(m[0]), options.indices.contains(i) {
            return i
        }
        if let m = QuestionDetector.match(#"^(?:option|answer)\s*:?\s*\(?([A-Fa-f])\b"#, t, caseInsensitive: true),
           let i = QuestionDetector.letterIndex(m[0]), options.indices.contains(i) {
            return i
        }
        let lower: String = t.lowercased()
        return options.firstIndex { !$0.isEmpty && lower.contains($0.lowercased()) }
    }

    /// One note per option from `{"A": "...", "B": "..."}`, a list in order,
    /// or a list of `{"option": "A", "why": "..."}`.
    static func notes(_ raw: Any?, count: Int) -> [String] {
        var out: [String] = Array(repeating: "", count: count)
        if let dict = raw as? [String: Any] {
            for (key, value) in dict {
                guard let i = keyIndex(key, options: []) ?? QuestionDetector.letterIndex(key),
                      out.indices.contains(i) else { continue }
                out[i] = flat(value)
            }
        } else if let list = raw as? [Any] {
            for (i, item) in list.enumerated() {
                if let d = item as? [String: Any] {
                    let label: String = string(d, "option", "letter", "key")
                    let index: Int = QuestionDetector.letterIndex(label) ?? i
                    if out.indices.contains(index) { out[index] = string(d, "why", "reason", "note", "explanation") }
                } else if out.indices.contains(i) {
                    out[i] = flat(item)
                }
            }
        }
        return out
    }

    static func truth(_ raw: Any?) -> Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? Int { return n != 0 }
        guard let s = raw as? String else { return nil }
        let t: String = s.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        if ["true", "t", "yes", "correct"].contains(t) { return true }
        if ["false", "f", "no", "incorrect"].contains(t) { return false }
        return nil
    }

    /// A blank filled in a sentence: the first run of underscores or dots.
    static func fill(_ stem: String, with answer: String) -> String {
        guard !answer.isEmpty else { return stem }
        let pattern: String = #"_{2,}|\.{4,}|\x{2026}{2,}|\[blank\]|\(\s{0,3}\)"#
        guard let range = stem.range(of: pattern, options: .regularExpression) else { return stem }
        return stem.replacingCharacters(in: range, with: answer)
    }

    /// A reply with no JSON in it: for a choice question, a line such as
    /// "Answer: C" is enough; for anything else the prose is kept as the
    /// explanation and its first line as the answer.
    static func fallback(_ text: String, for q: DetectedQuestion) -> LensAnswer? {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var a = LensAnswer(type: q.type)
        if q.type.hasOptions {
            guard let m = QuestionDetector.match(#"(?i:answer|correct)(?i:\s+is)?\s*[:\-]?\s*\(?([A-F])\b"#, trimmed),
                  let i = QuestionDetector.letterIndex(m[0]), q.options.indices.contains(i) else { return nil }
            a.correctIndex = i
            a.answer = q.options[i].text
            a.optionNotes = Array(repeating: "", count: q.options.count)
            a.explanation = trimmed
            return a
        }
        if q.type == .trueFalse {
            let first: String = trimmed.split(separator: " ").first.map(String.init) ?? ""
            guard let v = truth(first) else { return nil }
            a.verdict = v
            a.answer = v ? "True" : "False"
            a.explanation = trimmed
            return a
        }
        guard q.type != .osce, q.type != .clinicalCase else { return nil }
        let firstLine: String = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        a.answer = String(firstLine.prefix(160))
        a.explanation = trimmed
        return a
    }

    // MARK: tolerant reading

    static func string(_ d: [String: Any], _ keys: String...) -> String {
        for key in keys {
            guard let value = d[key] else { continue }
            let text: String = flat(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return ""
    }

    static func strings(_ d: [String: Any], _ keys: String...) -> [String] {
        for key in keys {
            guard let value = d[key] else { continue }
            var out: [String] = []
            if let list = value as? [Any] {
                out = list.map { flat($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            } else if let text = value as? String {
                out = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            let kept: [String] = out.filter { !$0.isEmpty && $0 != "..." }
            if !kept.isEmpty { return kept }
        }
        return []
    }

    /// Any JSON value as text: a string itself, a number, or an object's
    /// first text field.
    static func flat(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let d = value as? [String: Any] {
            for key in ["text", "step", "why", "reason", "name", "value"] {
                if let s = d[key] as? String { return s }
            }
        }
        return ""
    }
}
