import Foundation

/// The prompts, in the same line formats PlainTextImport reads, so what a
/// model writes and what a student types go through one parser.
enum LectureWriter {

    static func write(kind: StudySetKind, source: String, count: Int, subject: String,
                      using backend: LLMBackend,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> String {
        if kind == .book { return try await book(source: source, pages: count, subject: subject,
                                                 using: backend, onProgress: onProgress) }
        let perCall = backend.isOnDevice ? 6 : 12
        // A long lecture is taken a window at a time, round and round, so a
        // big set covers all of it instead of the first chapter again and again.
        let budget = max(2_000, backend.promptBudgetChars)
        let windows = source.count <= budget ? [source]
            : TextSlicing.slice(source, into: (source.count + budget - 1) / budget, maxChars: budget)
        var lines: [String] = []
        var failures = 0
        var round = 0
        // no fixed ceiling: it keeps going until the count is reached, and
        // only stops when several batches in a row bring nothing new
        while lines.count < count && failures < max(3, windows.count + 2) {
            try Task.checkCancellation()
            onProgress(lines.count, count)
            let batch = min(perCall, count - lines.count)
            let promptSource = windows[round % windows.count]
            round += 1
            // what has been written, in enough words to tell two cases of the
            // same disease apart
            let already = lines.map { line -> String in
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                return String((kind == .qa ? parts.prefix(3) : parts.prefix(1)).joined(separator: " | ").prefix(140))
            }
            let prompt = cardPrompt(kind: kind, count: batch, subject: subject,
                                    already: already, source: promptSource,
                                    presentations: kind == .qa ? CaseVariety.plan(batch, round: round) : [])
            let reply = try await backend.complete([.system(prompt), .user("Write the \(batch) lines now.")],
                                                   maxTokens: 160 * batch, temperature: 0.6)
            let fresh = reply.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression) }
                .filter { line in
                    line.components(separatedBy: "|").count >= (kind == .qa ? 4 : 2)
                        && !lines.contains { $0.lowercased() == line.lowercased() }
                }
            failures = fresh.isEmpty ? failures + 1 : 0
            lines.append(contentsOf: fresh.prefix(count - lines.count))
        }
        guard !lines.isEmpty else { throw LLMError.emptyReply }
        return lines.joined(separator: "\n")
    }

    static func cardPrompt(kind: StudySetKind, count: Int, subject: String,
                           already: [String], source: String,
                           presentations: [String] = []) -> String {
        var rules: [String]
        if kind == .qa {
            rules = [
                "Write \(count) Cases cards for a medical student revising \(subject.isEmpty ? "medicine" : subject).",
                "One card per line, exactly: Topic | case or recall | Question | answer point 1; answer point 2; answer point 3",
                "About half should be clinical cases: a two-sentence vignette ending in a question (\"What is the most likely diagnosis?\", \"What is the next step?\"). The rest are direct recall questions.",
                "Wrap the key term in each answer point in **double asterisks**.",
                "Every clinical case must present differently, even when two cases share a disease: vary the patient (age, sex, pregnancy, comorbidities, medications), the setting (GP, emergency department, ward, clinic), the stage (early, classic, late or complicated), typical versus atypical features, the trigger, and what is asked (diagnosis, next investigation, first-line treatment, complication, contraindication, monitoring). Never reuse a vignette already written, reworded.",
            ]
            if !presentations.isEmpty {
                rules.append("Write the clinical cases in this batch as:")
                rules += presentations.enumerated().map { "- case \($0.offset + 1): \($0.element)" }
                rules.append("(skip any of these the disease in the source cannot fit, and pick another variation instead)")
            }
        } else {
            rules = [
                "Write \(count) Anki flashcards for a medical student revising \(subject.isEmpty ? "medicine" : subject).",
                "One card per line, exactly: Front | answer point 1; answer point 2 | why it matters (optional)",
                "One fact per card. The front is a question. Answers are short: one to three points, a few words each.",
                "Wrap the single tested word or number in each answer in **double asterisks**.",
            ]
        }
        rules += [
            "Use only what the source supports.",
            "No numbering, no headings, no blank lines, nothing but the lines.",
        ]
        if !already.isEmpty {
            rules.append("Already written - do not repeat these:")
            rules += already.suffix(60).map { "- " + $0 }
        }
        return (rules + ["", "SOURCE:", source]).joined(separator: "\n")
    }

    /// A textbook is written a page at a time from its own slice of the
    /// source, so a long lecture is covered end to end rather than its first
    /// chapter summarised N times.
    static func book(source: String, pages: Int, subject: String, using backend: LLMBackend,
                     onProgress: @escaping (Int, Int) -> Void) async throws -> String {
        let slices = slice(source, into: pages, maxChars: backend.promptBudgetChars)
        var written: [String] = []
        for (i, part) in slices.enumerated() {
            try Task.checkCancellation()
            onProgress(i, slices.count)
            let prompt = """
            You are writing one page of a concise revision textbook for medical students\(subject.isEmpty ? "" : " in \(subject)").
            Rewrite the source below as that page, in Markdown:
            - Start with a single "## " heading naming the topic.
            - Short paragraphs and bullet lists; bold the terms a student must remember.
            - Keep every clinically important fact, number and threshold; add nothing the source doesn't say.
            - No introduction or closing remarks - just the page.

            SOURCE:
            \(part)
            """
            let reply = try await backend.complete([.user(prompt)], maxTokens: 1_200, temperature: 0.4)
            var page = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !page.hasPrefix("#") { page = "## Part \(i + 1)\n\n" + page }
            written.append(page)
        }
        guard !written.isEmpty else { throw LLMError.emptyReply }
        return written.joined(separator: "\n\n")
    }

    static func slice(_ text: String, into count: Int, maxChars: Int) -> [String] {
        TextSlicing.slice(text, into: count, maxChars: maxChars)
    }
}
