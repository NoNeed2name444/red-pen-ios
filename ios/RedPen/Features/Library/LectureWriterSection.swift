import SwiftUI
import UniformTypeIdentifiers

/// Writing Anki cards, Cases cards or a Textbook from a lecture, for the
/// new-set screen.
///
/// Like OSCE stations, what it writes lands in the editor as text in the same
/// line format the typing path uses, so the student checks and edits a draft
/// rather than receiving a finished set they never looked at. Free on the
/// device (Apple's model or Doctor-R1); CramDown Cloud when chosen and Pro.
struct LectureWriterSection: View {
    let kind: StudySetKind
    @Binding var bodyText: String
    @Binding var readSource: ReadSource?
    @Binding var suggestedName: String
    let subject: String

    @EnvironmentObject private var llm: LocalLLMService
    @State private var picking = false
    @State private var pastedNotes = ""
    @State private var showPaste = false
    @State private var count = 12
    @State private var working = false
    @State private var status: String?
    @State private var trouble: String?
    @State private var task: Task<Void, Never>?
    @State private var showModels = false

    private var sourceText: String {
        [readSource?.document.text ?? "", pastedNotes]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    private var hasSource: Bool { sourceText.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 }
    private var noun: String { kind == .book ? "page" : "card" }

    var body: some View {
        Section {
            Button { picking = true } label: {
                Label(readSource == nil ? "Choose a lecture file" : "Choose a different file",
                      systemImage: "doc.badge.plus")
            }
            .disabled(working)
            if let readSource {
                Label("\(readSource.name) \u{2014} \(readSource.document.pages.count) pages",
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("Or paste notes", isExpanded: $showPaste) {
                TextEditor(text: $pastedNotes)
                    .frame(minHeight: 120)
                    .font(.footnote)
                    .disabled(working)
            }
            Stepper("\(noun.capitalized)s: \(count)", value: $count,
                    in: kind == .book ? 1...30 : 4...80, step: kind == .book ? 1 : 4)
                .disabled(working)
            Button {
                working ? stop() : start()
            } label: {
                HStack {
                    if working { ProgressView().controlSize(.small) }
                    Text(working ? (status ?? "Writing\u{2026}") : "Write the \(noun)s")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!hasSource && !working)
            if working {
                Button("Stop", role: .cancel) { stop() }
            }
            if let status, !working {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if let trouble {
                Text(trouble).font(.footnote).foregroundStyle(.red)
                Button("AI models") { showModels = true }.font(.footnote)
            }
        } header: {
            Text("From a lecture")
        } footer: {
            Text(modelLine)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.readableTypes,
                      allowsMultipleSelection: false) { result in
            Task { await read(result) }
        }
        .sheet(isPresented: $showModels) { ModelSettingsView() }
    }

    private var modelLine: String {
        if let backend = llm.writerOrApple() {
            return "Written by \(backend.label)\(backend.isOnDevice ? " on this device, free" : ""). The \(noun)s land below to check and edit before you create the set."
        }
        return "No model is ready: turn on Apple Intelligence, download Doctor-R1 in AI models, or use CramDown Cloud with Pro."
    }

    static var readableTypes: [UTType] {
        [.pdf,
         UTType("org.openxmlformats.wordprocessingml.document"),
         UTType("org.openxmlformats.presentationml.presentation")].compactMap { $0 }
    }

    // MARK: reading

    private func read(_ result: Result<[URL], Error>) async {
        trouble = nil
        guard let url = (try? result.get())?.first else {
            if case .failure(let error) = result { trouble = error.localizedDescription }
            return
        }
        working = true
        status = "Reading\u{2026}"
        defer { working = false }
        do {
            let ext = url.pathExtension.lowercased()
            let read = ext == "pdf" ? try await SourceIngest.read(pdf: url, findingFigures: false)
                                    : try await OfficeIngest.read(url)
            let name = url.deletingPathExtension().lastPathComponent
            readSource = ReadSource(name: name, document: read.document,
                                    kind: ext == "pdf" ? .pdf : ext == "pptx" ? .powerpoint : .word)
            if suggestedName.trimmingCharacters(in: .whitespaces).isEmpty { suggestedName = name }
            if kind == .book { count = min(30, max(1, read.document.pages.count / 3)) }
            else { count = min(80, max(8, (read.document.pages.count / 2 + 3) / 4 * 4)) }
            status = nil
            if !hasSource { trouble = "There is not much text in that file to work from." }
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    // MARK: writing

    private func start() {
        trouble = nil
        guard let backend = llm.writerOrApple() else {
            trouble = "No model is ready to write with."
            return
        }
        let checker = llm.checkGenerated ? llm.backend(for: .checker) : nil
        let text = sourceText, wanted = count, subj = subject, mode = kind
        working = true
        status = "Writing\u{2026}"
        task = Task {
            do {
                let written = try await LectureWriter.write(
                    kind: mode, source: text, count: wanted, subject: subj, using: backend,
                    onProgress: { done, total in
                        Task { @MainActor in status = "Writing \(done) of \(total)\u{2026}" }
                    })
                var note = ""
                if let checker {
                    await MainActor.run { status = "Checking with \(checker.label)\u{2026}" }
                    if let verdict = try? await AccuracyChecker.check(
                        instruction: "Write study material for medical students from the source.",
                        input: AccuracyChecker.nearest(text, to: written, limit: checker.promptBudgetChars),
                        output: written, using: checker) {
                        note = verdict.passed ? " Checked: \(verdict.riskTitle.lowercased())."
                            : " Checker: \(verdict.riskTitle.lowercased()) \u{2014} \(verdict.findings.first?.text ?? "read it carefully")."
                    }
                }
                let finalNote = note
                await MainActor.run {
                    let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyText = existing.isEmpty ? written : existing + "\n" + written
                    working = false
                    status = "Written \u{2014} check them below." + finalNote
                }
            } catch is CancellationError {
                await MainActor.run { working = false; status = nil }
            } catch {
                await MainActor.run {
                    working = false
                    status = nil
                    trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        working = false
        status = nil
    }
}

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
