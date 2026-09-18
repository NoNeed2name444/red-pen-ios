import SwiftUI
import UniformTypeIdentifiers

/// Making a set. For MCQ sets this offers three paths: generate from your own
/// material - pasted, or read straight out of a lecture file - type lines by
/// hand, or import a `.json` export. Every other mode uses the typing or import
/// path.
///
/// The generate path lives in MCQGenerateForm: it owns the model choice, the
/// fallback model's download, and reading the file, which together are larger
/// than the rest of this screen put together.
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

    @State private var sourceText = ""
    @State private var questionCount = 8
    @State private var highYield = false
    /// The document the text came out of, kept so generated questions can be
    /// cited back to the page they came from.
    @State private var readSource: ReadSource?
    @State private var generatedSet: StudySet?
    @State private var generatedSetSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Name", text: $name)
                    TextField("Subject", text: $subject)
                    Picker("Type", selection: $kind) {
                        ForEach(StudySetKind.allCases) { kind in Text(kind.label).tag(kind) }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .mcq {
                    Section {
                        Picker("How", selection: $mcqPath) {
                            ForEach(MCQPath.allCases) { path in Text(path.rawValue).tag(path) }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch mcqPath {
                    case .generate:
                        MCQGenerateForm(sourceText: $sourceText,
                                        questionCount: $questionCount,
                                        highYield: $highYield,
                                        readSource: $readSource,
                                        name: name, subject: subject) { set in
                            generatedSetSaved = false
                            generatedSet = set
                        }
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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .fullScreenCover(item: $generatedSet) { set in
                NavigationStack {
                    MCQQuizView(set: set, isUnsaved: true, saved: $generatedSetSaved,
                                onSave: { store.addSet(set) })
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
            Button { showImporter = true } label: {
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
