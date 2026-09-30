import Foundation

/// The prompts, in the same line formats PlainTextImport reads, so what a
/// model writes and what a student types go through one parser.
enum LectureWriter {

    static func write(kind: StudySetKind, source: String, count: Int, subject: String,
                      using backend: LLMBackend, figures: [BookFigure] = [], style: CardStyle = .mixed,
                      onProgress: @escaping (Int, Int) -> Void) async throws -> String {
        if kind == .book { return try await book(source: source, pages: count, subject: subject,
                                                 using: backend, figures: figures, onProgress: onProgress) }
        let perCall = backend.isOnDevice ? 6 : 12
        // A long lecture is taken a window at a time, round and round, so a
        // big set covers all of it instead of the first chapter again and again.
        let budget = max(2_000, backend.promptBudgetChars)
        let windows = source.count <= budget ? [source]
            : TextSlicing.slice(source, into: (source.count + budget - 1) / budget, maxChars: budget)
        // Vignette Cloud: every window's prompt goes to the server at once, and
        // the server takes them in turn until the count is reached
        if let cloud = CloudJobs.endpoint(for: backend) {
            let cloudPerCall = 12
            let rounds = min(60, max(windows.count, 1) * (kind == .qa ? 4 : 1))
            let steps = (0..<rounds).map { r -> CloudJobs.Step in
                let prompt = cardPrompt(kind: kind, count: cloudPerCall, subject: subject,
                                        already: ["{{ALREADY}}"], source: "{{SOURCE}}", style: style,
                                        presentations: kind == .qa ? CaseVariety.plan(cloudPerCall, round: r + 1) : [])
                return .init(system: prompt, user: "Write the \(cloudPerCall) lines now.",
                             source: r % windows.count, maxTokens: (kind == .qa ? 240 : 160) * cloudPerCall, temperature: 0.6)
            }
            var spec = CloudJobs.Spec(
                title: "Writing \(count) \(kind == .qa ? "cases" : "cards")", mode: "loop", extract: "lines",
                count: count, sources: windows, steps: steps,
                minFields: kind == .qa ? 4 : 2, keyFields: kind == .qa ? 3 : 1, cloze: kind == .anki,
                patience: min(12, max(3, windows.count + 2)))
            if CloudJobs.context?.serverCheck == true {
                spec.check = AccuracyChecker.serverCheck(instruction: AccuracyChecker.materialInstruction,
                                                         limit: backend.promptBudgetChars)
            }
            let replies = try await CloudJobs.run(spec, at: cloud, onProgress: onProgress)
            let collected = collectLines(replies, kind: kind, count: count)
            guard !collected.isEmpty else { throw LLMError.emptyReply }
            let written = collected.joined(separator: "\n")
            // checked batch by batch on the server: the screen's check of the
            // whole reports the riskiest batch
            if let worst = AccuracyChecker.riskiest(CloudChecks.allReplies) {
                CloudChecks.remember(worst, forOutput: written)
            }
            return written
        }
        var lines: [String] = []
        var seen: Set<String> = []
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
                                    already: already, source: promptSource, style: style,
                                    presentations: kind == .qa ? CaseVariety.plan(batch, round: round) : [])
            let reply = try await backend.complete([.system(prompt), .user("Write the \(batch) lines now.")],
                                                   maxTokens: (kind == .qa ? 240 : 160) * batch, temperature: 0.6)
            let fresh = freshLines(in: reply, kind: kind, seen: &seen)
            failures = fresh.isEmpty ? failures + 1 : 0
            lines.append(contentsOf: fresh.prefix(count - lines.count))
        }
        guard !lines.isEmpty else { throw LLMError.emptyReply }
        return lines.joined(separator: "\n")
    }

    static func cardPrompt(kind: StudySetKind, count: Int, subject: String,
                           already: [String], source: String, style: CardStyle = .mixed,
                           presentations: [String] = []) -> String {
        var rules: [String]
        if kind == .qa {
            rules = [
                "Write \(count) Cases cards for a medical student revising \(subject.isEmpty ? "medicine" : subject).",
                "One card per line, exactly: Topic | case or recall | Question | answer point 1; answer point 2; answer point 3 | differential (clinical cases only)",
                "About half should be clinical cases: a two-sentence vignette ending in a question (\"What is the most likely diagnosis?\", \"What is the next step?\"). The rest are direct recall questions.",
                "Wrap the key term in each answer point in **double asterisks**.",
                "A clinical case carries a fifth field: the differential you reasoned through BEFORE writing the answer, exactly as: Most likely: Diagnosis (for: finding, finding; against: finding; test: the test that confirms or rules it out) / Expanded: Diagnosis (for: ...; against: ...; test: ...); Diagnosis (for: ...; against: ...; test: ...) / Can't miss: Diagnosis (for: ...; against: ...; test: ...)",
                "In it, the findings for and against are taken from the vignette, a few words each; Expanded is 1 or 2 reasonable alternatives; Can't miss is 1 or 2 dangerous diagnoses to exclude, or \"Can't miss: none\" if none fit. The answer points must agree with Most likely and fit every key finding. No | inside the field. Recall cards have no fifth field.",
                "Follow current guidance, but never cite a source, guideline or reference by name: the app cites the lecture.",
                "Every clinical case must present differently, even when two cases share a disease: vary the patient (age, sex, pregnancy, comorbidities, medications), the setting (GP, emergency department, ward, clinic), the stage (early, classic, late or complicated), typical versus atypical features, the trigger, and what is asked (diagnosis, next investigation, first-line treatment, complication, contraindication, monitoring). Never reuse a vignette already written, reworded.",
            ]
            if !presentations.isEmpty {
                rules.append("Write the clinical cases in this batch as:")
                rules += presentations.enumerated().map { "- case \($0.offset + 1): \($0.element)" }
                rules.append("(skip any of these the disease in the source cannot fit, and pick another variation instead)")
            }
        } else {
            let qa = "Question cards, one per line, exactly: Front | answer point 1; answer point 2 | why it matters (optional). The front is a question; answers are one to three short points; wrap the single tested word or number in **double asterisks**."
            let cloze = "Cloze cards, one per line, exactly: one sentence stating the fact with the tested word or number hidden as {{c1::that word}} | why it matters (optional). Hide the one thing worth remembering, never a filler word; one hidden part per card."
            rules = ["Write \(count) flashcards for a medical student revising \(subject.isEmpty ? "medicine" : subject). One fact per card."]
            switch style {
            case .qa: rules.append(qa)
            case .cloze: rules.append(cloze)
            case .mixed, .image: rules += ["Mix the two kinds, about half each:", "- " + qa, "- " + cloze]
            }
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
    /// chapter summarised N times. Each page is laid out like a clinical
    /// textbook chapter, with tables, flowcharts and callouts where they
    /// help, and carries the lecture's own diagrams about its topic.
    /// A reply's usable lines that are new against earlier batches and
    /// within this reply; a cloze line needs no second field.
    static func freshLines(in reply: String, kind: StudySetKind, seen: inout Set<String>) -> [String] {
        reply.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression) }
            .filter { line in
                (line.components(separatedBy: "|").count >= (kind == .qa ? 4 : 2) || (kind == .anki && line.contains("{{c")))
                    && seen.insert(line.lowercased()).inserted
            }
    }

    /// The lines of a cloud job's replies, as the loop above would have kept them.
    static func collectLines(_ replies: [String], kind: StudySetKind, count: Int) -> [String] {
        var seen: Set<String> = []
        return Array(replies.flatMap { freshLines(in: $0, kind: kind, seen: &seen) }.prefix(count))
    }

    /// A cloud job's pages, tidied, with each page's figures placed.
    static func assembleBook(_ replies: [String], placement: [[Int]]) -> String {
        replies.enumerated().map { i, reply in
            BookPages.tidyPage(reply, fallbackTitle: "Part \(i + 1)",
                               figures: placement.indices.contains(i) ? placement[i] : [])
        }.joined(separator: "\n\n")
    }

    static func book(source: String, pages: Int, subject: String, using backend: LLMBackend,
                     figures: [BookFigure] = [], exam: ExamTrack = .current,
                     onProgress: @escaping (Int, Int) -> Void) async throws -> String {
        let slices = slice(source, into: pages, maxChars: backend.promptBudgetChars)
        let placement = BookFigures.assign(figures, to: slices)
        if let cloud = CloudJobs.endpoint(for: backend) {
            let steps = slices.indices.map { i -> CloudJobs.Step in
                let mine = placement.indices.contains(i) ? placement[i] : []
                return .init(system: "", user: bookPrompt(source: "{{SOURCE}}", subject: subject, exam: exam,
                                                          figures: mine.map { (index: $0, figure: figures[$0]) }),
                             source: i, maxTokens: 3_000, temperature: 0.3)
            }
            var spec = CloudJobs.Spec(title: "Writing \(slices.count) textbook pages", mode: "each", extract: "pages",
                                      count: slices.count, sources: slices, steps: steps)
            if CloudJobs.context?.serverCheck == true {
                spec.check = AccuracyChecker.serverCheck(instruction: AccuracyChecker.materialInstruction,
                                                         limit: backend.promptBudgetChars)
            }
            let replies = try await CloudJobs.run(spec, at: cloud, extra: try? JSONEncoder().encode(placement),
                                                  onProgress: onProgress)
            guard !replies.isEmpty else { throw LLMError.emptyReply }
            let written = assembleBook(replies, placement: placement)
            // checked page by page on the server: the riskiest page speaks for the book
            if let worst = AccuracyChecker.riskiest(CloudChecks.allReplies) {
                CloudChecks.remember(worst, forOutput: written)
            }
            return written
        }
        var written: [String] = []
        for (i, part) in slices.enumerated() {
            try Task.checkCancellation()
            onProgress(i, slices.count)
            let mine = placement.indices.contains(i) ? placement[i] : []
            let prompt = bookPrompt(source: part, subject: subject, exam: exam,
                                    figures: mine.map { (index: $0, figure: figures[$0]) })
            let reply = try await backend.complete([.user(prompt)],
                                                   maxTokens: backend.isOnDevice ? 1_600 : 3_000,
                                                   temperature: 0.3)
            written.append(BookPages.tidyPage(reply, fallbackTitle: "Part \(i + 1)", figures: mine))
        }
        guard !written.isEmpty else { throw LLMError.emptyReply }
        return written.joined(separator: "\n\n")
    }

    static func bookPrompt(source: String, subject: String, exam: ExamTrack,
                           figures: [(index: Int, figure: BookFigure)]) -> String {
        var lines = [
            "You are writing one page of a medical revision textbook for medical students\(subject.isEmpty ? "" : " studying \(subject)")\(exam == .general ? "" : ", preparing for \(exam.title)").",
            "Turn the source below into that page, in Markdown, laid out like a good clinical textbook chapter.",
            "",
            "LAYOUT",
            "- The first line is the page title: exactly one \"## \" heading naming the topic. Every other heading uses \"### \".",
            "- Then these sections, in this order, but ONLY the ones the source actually covers: ### Definition, ### Epidemiology, ### Causes and risk factors, ### Pathophysiology, ### Clinical features, ### Investigations, ### Diagnosis, ### Differential diagnosis, ### Management, ### Complications, ### Prognosis. A topic that is not a disease (anatomy, a drug, a procedure) uses the headings that fit it instead.",
            "- Short paragraphs and bullet lists. Bold the terms a student must remember. Clinical features as bullets, the classic ones in bold. Investigations: first-line first, and name the gold standard. Management stepwise: first-line, then second-line, then when to escalate or refer.",
            "",
            "VISUAL AIDS - use them wherever they make the topic clearer:",
            "- A table (header row, then a |---| line, then the rows) for any comparison: types or classifications, differentials (| Condition | Key distinguishing feature |), drug classes, staging.",
            "- A flowchart for any pathway: a diagnostic work-up, a management algorithm, or a cause-to-effect cascade. Write it as a fenced block that starts with ```flow, one step per line, a branch as \"If ... → ...\", and ends with ```.",
            "- Callout lines where they earn their place: \"> **Key point:** ...\", \"> **Exam tip:** ...\", \"> **Red flag:** ...\", \"> **Mnemonic:** ...\".",
        ]
        if !figures.isEmpty {
            lines.append("- These diagrams from the lecture belong on this page. Put each one on its own line where it fits the text, exactly as ![a one-line caption saying what it shows](image:N):")
            lines += figures.map { f in
                "  - image:\(f.index)\(f.figure.page.map { " (page \($0))" } ?? "") labelled: \(f.figure.labels.prefix(12).joined(separator: ", "))"
            }
        }
        lines += [
            "",
            "ACCURACY",
            "- Every fact, number, dose and threshold must come from the source. Do not add drugs, doses, criteria or statistics it does not give.",
            "- You may explain in plain words how the source's facts connect (why a mechanism causes a finding), but add no new facts.",
            "- Where the source is unclear, keep its meaning rather than guessing.",
            "- No introduction, no closing remarks, no notes to the reader - just the page.",
            "",
            "SOURCE:",
            source,
        ]
        return lines.joined(separator: "\n")
    }

    static func slice(_ text: String, into count: Int, maxChars: Int) -> [String] {
        TextSlicing.slice(text, into: count, maxChars: maxChars)
    }
}
