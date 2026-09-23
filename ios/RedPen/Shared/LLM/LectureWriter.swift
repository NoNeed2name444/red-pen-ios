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
        let promptSource = String(source.prefix(backend.promptBudgetChars))
        var lines: [String] = []
        var failures = 0
        while lines.count < count && failures < 3 {
            try Task.checkCancellation()
            onProgress(lines.count, count)
            let batch = min(perCall, count - lines.count)
            let already = lines.map { $0.components(separatedBy: "|").first ?? $0 }
            let prompt = cardPrompt(kind: kind, count: batch, subject: subject,
                                    already: already, source: promptSource)
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
                           already: [String], source: String) -> String {
        var rules: [String]
        if kind == .qa {
            rules = [
                "Write \(count) Cases cards for a medical student revising \(subject.isEmpty ? "medicine" : subject).",
                "One card per line, exactly: Topic | case or recall | Question | answer point 1; answer point 2; answer point 3",
                "About half should be clinical cases: a two-sentence vignette ending in a question (\"What is the most likely diagnosis?\", \"What is the next step?\"). The rest are direct recall questions.",
                "Wrap the key term in each answer point in **double asterisks**.",
            ]
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
            rules += already.suffix(40).map { "- " + $0 }
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
