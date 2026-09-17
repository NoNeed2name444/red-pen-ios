import SwiftUI
import UniformTypeIdentifiers

/// Stands in for the web app's setup screen (`#setupView`). For MCQ sets
/// this now offers the same three paths the web app effectively does:
/// generate a set from pasted notes (there, via Claude; here, via Apple's
/// on-device Foundation Models — see MCQGenerator.swift), type lines by
/// hand, or import a `.json` export. Every other mode still uses the
/// line-based typing / import path, since generation is being ported
/// mode by mode starting with MCQ.
struct NewSetView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var gemma: GemmaModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var subject: String = "General"
    @State private var kind: StudySetKind = .mcq
    @State private var bodyText: String = ""
    @State private var showImporter = false
    @State private var importError: String?

    private enum MCQPath: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case type = "Type"
        case importJSON = "Import"
        var id: String { rawValue }
    }
    @State private var mcqPath: MCQPath = .generate

    // generation state
    @State private var sourceText = ""
    @State private var questionCount = 8
    @State private var highYield = false
    @State private var isGenerating = false
    @State private var generationStatus: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var generatedSet: StudySet?
    @State private var generatedSetSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Name", text: $name)
                    TextField("Subject", text: $subject)
                    Picker("Type", selection: $kind) {
                        ForEach(StudySetKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .mcq {
                    Section {
                        Picker("How", selection: $mcqPath) {
                            ForEach(MCQPath.allCases) { p in Text(p.rawValue).tag(p) }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch mcqPath {
                    case .generate: generateSection
                    case .type: typeSection
                    case .importJSON: importSection
                    }
                } else {
                    typeSection
                    importSection
                }
            }
            .navigationTitle("New set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !(kind == .mcq && mcqPath == .generate) {
                    ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $generatedSet) { set in
                NavigationStack {
                    MCQQuizView(set: set, isUnsaved: true, saved: $generatedSetSaved, onSave: { store.addSet(set) })
                }
            }
            .onAppear { gemma.refreshStatus() }
            .onDisappear { generationTask?.cancel() }
        }
    }

    // MARK: generate (MCQ only — see MCQGenerator / GemmaModel)

    /// Which backend a tap on "Generate" would actually use right now.
    /// `nil` means neither is ready — the UI shows why, and for Gemma,
    /// an offer to download it — instead of a Generate button that would
    /// just fail.
    private enum Backend: Equatable { case apple, gemma }
    private var activeBackend: Backend? {
        if MCQGenerator.availability.isAvailable { return .apple }
        if gemma.status == .ready { return .gemma }
        return nil
    }

    private var generateSection: some View {
        Group {
            Section {
                Text(formatHelp(for: .mcq))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $sourceText)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isGenerating)
            } header: {
                Text("Paste your notes")
            }

            Section {
                Stepper("Questions: \(questionCount)", value: $questionCount, in: 3...MCQGenerator.maxQuestionsTotal)
                    .disabled(isGenerating)
                Toggle("High-yield focus", isOn: $highYield)
                    .disabled(isGenerating)
            }

            backendSection

            Section {
                if activeBackend == .gemma {
                    Text("Using the downloaded Gemma 4 E2B model — on-device, nothing sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    startGenerating()
                } label: {
                    HStack {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Text(isGenerating ? (generationStatus ?? "Writing…") : "Generate questions")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isGenerating || activeBackend == nil || sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
                if isGenerating {
                    Button("Cancel", role: .cancel) {
                        generationTask?.cancel()
                    }
                }
                if let generationStatus, !isGenerating {
                    Text(generationStatus).font(.footnote).foregroundStyle(.secondary)
                }
                if activeBackend == .gemma, !isGenerating {
                    Button("Remove downloaded model", role: .destructive) {
                        gemma.deleteDownloadedModel()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    /// Apple's on-device model is tried first; this section only shows up
    /// when that's unavailable, offering the Gemma 4 E2B download as a
    /// fallback that still never touches anyone's Claude account.
    @ViewBuilder
    private var backendSection: some View {
        if !MCQGenerator.availability.isAvailable {
            Section {
                if case .unavailable(let reason) = MCQGenerator.availability {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                switch gemma.status {
                case .ready:
                    EmptyView() // handled by the note in the generate section above
                case .notDownloaded:
                    Button {
                        gemma.download()
                    } label: {
                        Label("Download offline model (~2.8 GB, one-time)", systemImage: "arrow.down.circle")
                    }
                    Text("A smaller model (Gemma 4 E2B) that runs entirely on this device once downloaded — works on hardware that can't run Apple's own on-device model.")
                        .font(.caption).foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Downloading offline model — \(Int(fraction * 100))%")
                            .font(.footnote)
                    }
                    Button("Cancel download", role: .cancel) { gemma.cancelDownload() }
                case .failed(let message):
                    Text("Download failed: \(message)")
                        .font(.footnote).foregroundStyle(.red)
                    Button("Try again") { gemma.download() }
                }
            } header: {
                Text("Offline model")
            }
        }
    }

    private func startGenerating() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let backend = activeBackend else { return }
        isGenerating = true
        generationStatus = "Writing 0 of \(questionCount) questions…"
        let count = questionCount, subj = subject, hy = highYield, setName = name
        generationTask = Task {
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    Task { @MainActor in generationStatus = "Writing \(done) of \(total) questions…" }
                }
                let questions: [MCQQuestion]
                switch backend {
                case .apple:
                    questions = try await MCQGenerator.generate(
                        sourceText: text, count: count, subject: subj, highYield: hy, onProgress: progress
                    )
                case .gemma:
                    questions = try await gemma.generate(
                        sourceText: text, count: count, subject: subj, highYield: hy, onProgress: progress
                    )
                }
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Done — \(questions.count) question(s) written."
                    var set = StudySet(
                        name: setName.isEmpty ? (subj.isEmpty || subj == "General" ? "Generated set" : subj) : setName,
                        subject: subj.isEmpty ? "General" : subj, kind: .mcq
                    )
                    set.questions = questions
                    generatedSetSaved = false
                    generatedSet = set
                }
            } catch is CancellationError {
                await MainActor.run { isGenerating = false; generationStatus = nil }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    generationStatus = (error as? MCQGenerator.GenerationError)?.errorDescription
                        ?? (error as? GemmaModel.GenerationError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: type / import (every mode)

    private var typeSection: some View {
        Section {
            Text(formatHelp(for: kind))
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $bodyText)
                .frame(minHeight: 160)
                .font(.system(.footnote, design: .monospaced))
        } header: {
            Text("Type or paste \(kind == .book ? "the textbook (Markdown)" : kind == .mcq ? "questions" : kind == .osce ? "checklists" : kind == .narrate ? "the transcript" : "cards")")
        } footer: {
            if let importError { Text(importError).foregroundStyle(.red) }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("Import a .json export instead", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func formatHelp(for kind: StudySetKind) -> String {
        switch kind {
        case .mcq: return "One question per line: Stem | OptA; OptB; OptC; OptD | correctLetter | Explanation"
        case .anki: return "One card per line: Front | bullet1; bullet2 | why (optional)"
        case .book: return "Markdown. Every # or ## heading starts a new page."
        case .qa: return "One card per line: Topic | case or recall | Question | answer1; answer2"
        case .osce: return "## Station title, then one step per line. Blank line or the next ## starts a new station."
        case .narrate: return "One line per phrase. Prefix with \"ar|\" for Arabic reading pace, otherwise it reads at English pace."
        }
    }

    private func create() {
        var set = StudySet(name: name, subject: subject.isEmpty ? "General" : subject, kind: kind)
        switch kind {
        case .mcq: set.questions = PlainTextImport.parseMCQ(bodyText)
        case .anki: set.cards = PlainTextImport.parseAnkiQA(bodyText)
        case .book: set.bookMarkdown = bodyText
        case .qa: set.qaCards = PlainTextImport.parseQA(bodyText)
        case .osce: set.osceChecklists = PlainTextImport.parseOsce(bodyText)
        case .narrate: set.narrateSegments = PlainTextImport.parseNarrate(bodyText)
        }
        store.addSet(set)
        dismiss()
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // a file picked outside the app's sandbox needs this while it's read
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            var imported = try JSONDecoder.redPen.decode(StudySet.self, from: data)
            imported.id = UUID() // never collide with an existing id
            store.addSet(imported)
            dismiss()
        } catch {
            importError = "Couldn't read that file: \(error.localizedDescription)"
        }
    }
}
