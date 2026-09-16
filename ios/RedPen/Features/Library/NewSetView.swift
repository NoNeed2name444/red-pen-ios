import SwiftUI
import UniformTypeIdentifiers

/// Stands in for the web app's setup screen (`#setupView`) — which there
/// builds a set via an AI generation call. That call isn't wired up in
/// this phase (see the README), so this gives two on-device ways to get
/// content into the same data model: quick line-based typing, or importing
/// a `.json` file that matches `StudySet`'s Codable shape (which is what a
/// future export/import bridge with the web app would use).
struct NewSetView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var subject: String = "General"
    @State private var kind: StudySetKind = .mcq
    @State private var bodyText: String = ""
    @State private var showImporter = false
    @State private var importError: String?

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

                Section {
                    Text(formatHelp)
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 160)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Type or paste \(kind == .book ? "the textbook (Markdown)" : kind == .mcq ? "questions" : kind == .osce ? "checklists" : "cards")")
                } footer: {
                    if let importError { Text(importError).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import a .json export instead", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("New set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
    }

    private var formatHelp: String {
        switch kind {
        case .mcq: return "One question per line: Stem | OptA; OptB; OptC; OptD | correctLetter | Explanation"
        case .anki: return "One card per line: Front | bullet1; bullet2 | why (optional)"
        case .book: return "Markdown. Every # or ## heading starts a new page."
        case .qa: return "One card per line: Topic | case or recall | Question | answer1; answer2"
        case .osce: return "## Station title, then one step per line. Blank line or the next ## starts a new station."
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
