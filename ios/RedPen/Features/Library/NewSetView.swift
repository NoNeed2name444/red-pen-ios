import SwiftUI
import UniformTypeIdentifiers

/// Making a set, in three decisions asked one at a time: what kind of set,
/// what to call it, and where its material comes from. Only the path chosen is
/// shown, so the screen is never every option at once.
///
/// Every path ends in the same place - text in the line format the typing path
/// uses, checked by the student, then Create - except MCQ generation, which
/// opens the quiz straight away (MCQGenerateForm owns that, with the model
/// choice and the lecture reading, which together are larger than the rest of
/// this screen).
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
    @State private var showFormat = false

    /// Where the material comes from.
    enum Path: String, CaseIterable, Identifiable {
        case lecture, type, importFile
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lecture: return "A lecture"
            case .type: return "Type or paste"
            case .importFile: return "A saved set"
            }
        }
        var symbol: String {
            switch self {
            case .lecture: return "sparkles"
            case .type: return "keyboard"
            case .importFile: return "square.and.arrow.down"
            }
        }
    }
    @State private var path: Path = .lecture

    @State private var sourceText = ""
    @State private var questionCount = 8
    @State private var highYield = false
    /// The document the text came out of, kept so generated questions can be
    /// cited back to the page they came from, and so the accuracy check has
    /// the lecture to check against.
    @State private var readSource: ReadSource?
    @State private var generatedSet: StudySet?
    @State private var generatedSetSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    modeGrid
                } header: {
                    Text("What are you making?")
                }

                Section {
                    TextField("Name", text: $name, prompt: Text("Name \u{2014} e.g. Cardiology week 3"))
                    TextField("Subject", text: $subject)
                } header: {
                    Text("Details")
                }

                Section {
                    pathPicker
                } header: {
                    Text("Start from")
                }

                material

                if showsCreate {
                    Section {
                        Button { create() } label: {
                            Text("Create \(kind.label) set").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!canCreate)
                    } footer: {
                        Text(readiness)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ModeBackdrop(kind: kind).animation(.easeInOut(duration: 0.5), value: kind))
            .navigationTitle("New set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if showsCreate {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }.disabled(!canCreate)
                    }
                }
            }
            .onChange(of: kind) { _, now in
                if !Self.paths(for: now).contains(path) { path = Self.paths(for: now)[0] }
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

    // MARK: the three choices

    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(StudySetKind.allCases) { option in
                Button { withAnimation(.snappy) { kind = option } } label: {
                    HStack(spacing: 10) {
                        ModeTile(kind: option, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.subheadline.weight(.semibold))
                            Text(Self.blurb(option))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .background(kind == option ? option.tint.opacity(0.16) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(kind == option ? option.tint : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    private var pathPicker: some View {
        HStack(spacing: 10) {
            ForEach(Self.paths(for: kind)) { option in
                Button { withAnimation(.snappy) { path = option } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.title3)
                        Text(option.title).font(.caption.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(path == option ? kind.tint : Color.primary)
                    .background(path == option ? kind.tint.opacity(0.14) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(path == option ? kind.tint : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(path == option ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
    }

    /// Narrate's lecture path is recording, which lives in Narrate itself.
    static func paths(for kind: StudySetKind) -> [Path] {
        kind == .narrate ? [.type, .importFile] : Path.allCases
    }

    static func blurb(_ kind: StudySetKind) -> String {
        switch kind {
        case .mcq: return "Single-best-answer questions"
        case .anki: return "Spaced-repetition flashcards"
        case .book: return "Your lecture as readable pages"
        case .qa: return "Clinical cases and recall, with a simulated patient"
        case .osce: return "Station checklists, step by step"
        case .narrate: return "A transcript read along with audio"
        }
    }

    // MARK: the material, for the chosen path only

    @ViewBuilder
    private var material: some View {
        switch path {
        case .lecture:
            switch kind {
            case .mcq:
                MCQGenerateForm(sourceText: $sourceText,
                                questionCount: $questionCount,
                                highYield: $highYield,
                                readSource: $readSource,
                                name: name, subject: subject) { set in
                    generatedSetSaved = false
                    generatedSet = set
                }
            case .osce:
                OsceGenerateSection(bodyText: $bodyText, subject: subject)
                if !bodyText.isEmpty { draftSection(title: "Check and edit") }
            case .anki, .qa, .book:
                LectureWriterSection(kind: kind, bodyText: $bodyText, readSource: $readSource,
                                     suggestedName: $name, subject: subject)
                if !bodyText.isEmpty { draftSection(title: "Check and edit") }
            case .narrate:
                draftSection(title: "Type or paste")
            }
        case .type:
            draftSection(title: "Type or paste")
        case .importFile:
            Section {
                Button { showImporter = true } label: {
                    Label("Choose a .json set", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text(importError ?? "A set exported from \(Brand.name) (formerly CramDown) or the Red Pen web app. It's added as it is, so there's nothing to create.")
                    .foregroundStyle(importError == nil ? Color.secondary : Color.red)
            }
        }
    }

    private func draftSection(title: String) -> some View {
        Section {
            TextEditor(text: $bodyText)
                .frame(minHeight: 180)
                .font(.system(.footnote, design: .monospaced))
            DisclosureGroup("Format", isExpanded: $showFormat) {
                Text(formatHelp(for: kind))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(title)
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

    // MARK: creating

    /// MCQ generation saves from its own quiz screen, and an import adds the
    /// set as it is: neither has anything for Create to do.
    private var showsCreate: Bool {
        path != .importFile && !(kind == .mcq && path == .lecture)
    }

    private var itemCount: Int {
        switch kind {
        case .mcq: return PlainTextImport.parseMCQ(bodyText).count
        case .anki: return PlainTextImport.parseAnkiQA(bodyText).count
        case .book: return bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : BookPages.split(bodyText).count
        case .qa: return PlainTextImport.parseQA(bodyText).count
        case .osce: return PlainTextImport.parseOsce(bodyText).count
        case .narrate: return PlainTextImport.parseNarrate(bodyText).count
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && itemCount > 0
    }

    private var readiness: String {
        let count = itemCount
        let noun: String
        switch kind {
        case .mcq: noun = "question"
        case .anki, .qa: noun = "card"
        case .book: noun = "page"
        case .osce: noun = "station"
        case .narrate: noun = "line"
        }
        if count == 0 { return "Nothing readable yet \u{2014} open Format to see the layout each line needs." }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "\(count) \(noun)\(count == 1 ? "" : "s") ready. Give the set a name to create it." }
        return "\(count) \(noun)\(count == 1 ? "" : "s") ready."
    }

    private func create() {
        guard canCreate else { return }
        var set = StudySet(name: name, subject: subject.isEmpty ? "General" : subject, kind: kind)
        switch kind {
        case .mcq: set.questions = PlainTextImport.parseMCQ(bodyText)
        case .anki: set.cards = PlainTextImport.parseAnkiQA(bodyText)
        case .book: set.bookMarkdown = bodyText
        case .qa: set.qaCards = PlainTextImport.parseQA(bodyText)
        case .osce: set.osceChecklists = PlainTextImport.parseOsce(bodyText)
        case .narrate: set.narrateSegments = PlainTextImport.parseNarrate(bodyText)
        }
        // the lecture it was written from goes with it: page citations and
        // the accuracy check both read it
        if path == .lecture, let readSource { set.sources = [readSource.doc()] }
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
