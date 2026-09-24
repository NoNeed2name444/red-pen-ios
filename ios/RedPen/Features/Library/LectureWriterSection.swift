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
            CountField(title: "\(noun.capitalized)s", value: $count,
                       range: kind == .book ? 1...1_000 : 1...10_000)
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
            .floatingActionAnchor("writer")
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
        .floatingAction(id: "writer", title: "Write \(count) \(noun)\(count == 1 ? "" : "s")",
                        enabled: hasSource && !working, run: start)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.readableTypes,
                      allowsMultipleSelection: false) { result in
            Task { await read(result) }
        }
        .sheet(isPresented: $showModels) { ModelSettingsView() }
    }

    private var modelLine: String {
        if let backend = llm.writerOrApple() {
            return "Written by \(backend.label)\(backend.isOnDevice ? " on this device" : ""). The \(noun)s land below to check and edit before you create the set."
        }
        return "No model is ready: turn on Apple Intelligence, or use Doctor-R1 or \(Brand.name) Cloud with Pro."
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
        let job = GenerationCenter.shared.begin("Writing \(wanted) \(noun)\(wanted == 1 ? "" : "s")", total: wanted) {
            task?.cancel()
            task = nil
            working = false
            status = "Cancelled."
        }
        task = Task {
            do {
                let written = try await LectureWriter.write(
                    kind: mode, source: text, count: wanted, subject: subj, using: backend,
                    onProgress: { done, total in
                        GenerationCenter.shared.update(job, done: done, total: total)
                        Task { @MainActor in status = "Writing \(done) of \(total)\u{2026}" }
                    })
                try Task.checkCancellation()
                var note = ""
                if let checker {
                    GenerationCenter.shared.update(job, done: wanted, total: wanted, phase: "Checking with \(checker.label)")
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
                try Task.checkCancellation()
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyText = existing.isEmpty ? written : existing + "\n" + written
                    working = false
                    status = "Written \u{2014} check them below." + finalNote
                }
            } catch is CancellationError {
                await MainActor.run { GenerationCenter.shared.end(job) }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    working = false
                    status = nil
                    trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func stop() { GenerationCenter.shared.cancel() }
}
