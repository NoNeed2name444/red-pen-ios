import SwiftUI
import UniformTypeIdentifiers

/// The three steps of New set, in the order they are asked.
enum NewSetStep: Int, CaseIterable, Identifiable, Comparable {
    /// What kind of set: questions, cards, a textbook...
    case kind = 1
    /// Where the material comes from: a lecture file, typing, a saved set.
    case material
    /// A name, how many, and the one button that makes it.
    case make

    var id: Int { rawValue }

    /// The short name under the step's number in the indicator.
    var short: String {
        switch self {
        case .kind: return "Choose"
        case .material: return "Add"
        case .make: return "Make"
        }
    }

    /// The question the step asks, as the heading of its screen.
    var question: String {
        switch self {
        case .kind: return "What do you want to make?"
        case .material: return "Add your lecture"
        case .make: return "Make it"
        }
    }

    static func < (a: NewSetStep, b: NewSetStep) -> Bool { a.rawValue < b.rawValue }
}

/// Making a set, in three steps asked one at a time: what kind of set, where
/// its material comes from, and then a name, a count and one big Make button.
/// Only the step you are on is shown, so the screen is never every option at
/// once, and the rarely-needed choices (subject, card style, which model is
/// writing) wait behind "More options".
///
/// Every path ends in the same place - text in the line format the typing path
/// uses, checked by the student, then Save - except MCQ generation, which
/// opens the quiz straight away (MCQGenerateForm owns that, with the model
/// choice and the lecture reading, which together are larger than the rest of
/// this screen).
///
/// The lecture sections stay in the view the whole time and only draw the
/// part for the current step. That is what keeps a file read in step 2 still
/// read in step 3: a section taken out of the view and put back starts again
/// from nothing.
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
    /// Which of the three steps is showing.
    @State private var step: NewSetStep = .kind

    /// Where the material comes from.
    enum Path: String, CaseIterable, Identifiable {
        case lecture, type, importFile
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lecture: return "From a lecture file"
            case .type: return "Type or paste"
            case .importFile: return "Open a saved set"
            }
        }
        /// One plain line under the title.
        var blurb: String {
            switch self {
            case .lecture: return "A PDF, Word or PowerPoint file \u{2014} or notes you paste"
            case .type: return "Write the questions or cards yourself"
            case .importFile: return "A .json set someone shared with you"
            }
        }
        var symbol: String {
            switch self {
            case .lecture: return "doc.text.viewfinder"
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
    @State private var bookFigures: [BookFigure] = []
    @State private var diagrams = DiagramCards()
    @ObservedObject private var generation = GenerationCenter.shared
    @State private var generatedSet: StudySet?
    @State private var generatedSetSaved = false
    /// Set when a set is being turned into another mode by the writer, or
    /// started from the syllabus: the mode is chosen and the material is in,
    /// so New set opens on its last step with Make the next tap.
    private let preset: NewSetPreset?

    init(preset: NewSetPreset? = nil) {
        self.preset = preset
        if let preset {
            _kind = State(initialValue: preset.kind)
            _name = State(initialValue: preset.name)
            _subject = State(initialValue: preset.subject)
            _path = State(initialValue: .lecture)
            _readSource = State(initialValue: preset.lecture)
            _sourceText = State(initialValue: preset.text)
            _step = State(initialValue: .make)
        }
    }

    /// New set from a category's "+ New set": that category's kind already
    /// chosen, still on the first step, so a different one is one tap away.
    init(kind: StudySetKind) {
        self.preset = nil
        _kind = State(initialValue: kind)
        _path = State(initialValue: Self.paths(for: kind)[0])
    }

    /// New set from a category's "Paste or import" tile: that kind chosen and
    /// already on the step that asks where the material comes from, with
    /// typing picked - a saved set or a lecture file is one tap away there.
    init(kind: StudySetKind, startingAt start: NewSetStep) {
        self.init(kind: kind)
        _step = State(initialValue: start)
        _path = State(initialValue: .type)
    }

    var body: some View {
        NavigationStack {
            form
                .scrollContentBackground(.hidden)
                .floatingAction(id: "create", title: saveTitle, symbol: "checkmark",
                                enabled: canCreate, run: create)
                // the one bottom container: Back and the step's main button,
                // or the progress card while something is being written
                .safeAreaInset(edge: .bottom, spacing: 0) { dock }
                .onDisappear {
                    FloatingAction.shared.clear()
                    // closing New set stops what it started, so nothing keeps
                    // running unseen or turns up as a stray card next time
                    GenerationCenter.shared.cancel()
                }
                .interactiveDismissDisabled(generation.job != nil)
                .background(ModeBackdrop(kind: kind))
                // the chosen kind's colour, for the big buttons at the bottom
                // as much as for the backdrop
                .tint(kind.tint)
                .environment(\.modeTint, kind.tint)
                .navigationTitle("New set")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .onChange(of: kind) { _, now in
                    if !Self.paths(for: now).contains(path) { path = Self.paths(for: now)[0] }
                    // each mode's draft is in its own format: Anki lines are not
                    // textbook pages, so a draft never carries over to another mode
                    GenerationCenter.shared.cancel()
                    bodyText = ""
                    bookFigures = []
                    diagrams = DiagramCards()
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

    /// Only the step you are on, and the material for the chosen path.
    private var form: some View {
        Form {
            Section {
                stepHeader
            }
            .listRowBackground(Color.clear)

            if step == .kind {
                Section { modeGrid }
            }
            if step == .material {
                Section { pathPicker }
            }
            if step == .make {
                nameSection
            }

            material

            if step == .make && showsCreate {
                createSection
            }
        }
    }

    private var saveTitle: String { "Save \(kind.label) set" }

    // MARK: moving between the steps

    /// "1 Choose — 2 Add — 3 Make" and the step's question. A step already
    /// done is a button back to it; Back itself is at the bottom, under the
    /// thumb.
    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(NewSetStep.allCases) { one in
                    stepDot(one)
                    if one != .make {
                        stepLink(after: one)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Step \(step.rawValue) of 3")
            Text(step.question)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func stepLink(after one: NewSetStep) -> some View {
        let passed: Bool = one < step
        let fill: Color = passed ? kind.tint : Color.secondary.opacity(0.25)
        return Capsule()
            .fill(fill)
            .frame(height: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stepDot(_ one: NewSetStep) -> some View {
        let dot = NewSetStepDot(one: one, current: step, tint: kind.tint)
        if one < step {
            let spoken: String = "Back to step \(one.rawValue), \(one.short)"
            // borderless, so in a Form row only the dot takes the tap
            Button { goTo(one) } label: { dot }
                .buttonStyle(.borderless)
                .hoverEffect(.highlight)
                // the step being written stays in sight until it is done
                .disabled(generation.job != nil)
                .accessibilityLabel(spoken)
        } else {
            dot
        }
    }

    private func goBack() {
        guard let before = NewSetStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) { step = before }
    }

    private func goTo(_ earlier: NewSetStep) {
        guard earlier < step else { return }
        withAnimation(.snappy) { step = earlier }
    }

    private func goForward() {
        guard let next = NewSetStep(rawValue: step.rawValue + 1) else { return }
        // a sensible name to start from: the lecture's own
        if next == .make, name.trimmingCharacters(in: .whitespaces).isEmpty, let readSource {
            name = readSource.name
        }
        withAnimation(.snappy) { step = next }
    }

    /// The bottom slab: Back at the leading end, and at the trailing end
    /// Next on step 2 (or the file picker for a saved set), then on step 3
    /// the floating copy of Make or Save while the real one is scrolled away.
    private var dock: some View {
        NewSetDock(step: step, primary: dockPrimary, hint: dockHint,
                   back: goBack, next: goForward, chooseSaved: { showImporter = true })
    }

    private var dockPrimary: NewSetDockPrimary {
        switch step {
        case .kind: return .floating(nil)
        case .material:
            if path == .importFile { return .chooseSaved }
            return .next(ready: canGoOn)
        case .make: return .floating(floatingID)
        }
    }

    /// Why Next is greyed out, in the slab above it.
    private var dockHint: String? {
        guard step == .material, path != .importFile, !canGoOn else { return nil }
        if path == .type { return "Type or paste something first" }
        return "Add a lecture file or paste your notes first"
    }

    /// Whether step 2 has something to go on with. The lecture sections for
    /// cards, cases, textbooks and OSCE keep their file to themselves, so for
    /// those step 3 says what is missing instead.
    private var canGoOn: Bool {
        switch (path, kind) {
        case (.type, _), (.lecture, .narrate):
            return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case (.lecture, .mcq):
            return !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    // MARK: the three choices

    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(StudySetKind.allCases) { option in
                modeTile(option)
            }
        }
        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .listRowBackground(Color.clear)
    }

    /// One kind of set, as a big tile standing out of the glass; the chosen
    /// one stands higher. Tapping it chooses it and moves on.
    private func modeTile(_ option: StudySetKind) -> some View {
        let chosen: Bool = kind == option
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let plane: PopOutPlane = chosen ? .floating : .raised
        let fill: AnyShapeStyle = Self.tileFill(chosen: chosen, tint: option.tint)
        let edge: Color = chosen ? option.tint : Color.clear
        let traits: AccessibilityTraits = chosen ? .isSelected : []
        return Button {
            withAnimation(.snappy) {
                kind = option
                step = .material
            }
        } label: {
            HStack(spacing: 16) {
                ModeTile(kind: option, size: 44, selected: chosen)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.plainName(option)).font(.headline)
                    Text(Self.blurb(option))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(PopTileStyle(cornerRadius: 16, plane: plane))
        .accessibilityAddTraits(traits)
    }

    /// A chosen tile is washed in its colour; the others are frosted.
    private static func tileFill(chosen: Bool, tint: Color) -> AnyShapeStyle {
        if chosen { return AnyShapeStyle(tint.opacity(0.12)) }
        return AnyShapeStyle(.regularMaterial)
    }

    private var pathPicker: some View {
        VStack(spacing: 12) {
            ForEach(Self.paths(for: kind)) { option in
                pathTile(option)
            }
        }
        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func pathTile(_ option: Path) -> some View {
        let chosen: Bool = path == option
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let plane: PopOutPlane = chosen ? .floating : .raised
        let fill: AnyShapeStyle = Self.tileFill(chosen: chosen, tint: kind.tint)
        let edge: Color = chosen ? kind.tint : Color.clear
        let ink: Color = chosen ? kind.tint : Color.secondary
        let mark: String = chosen ? "checkmark.circle.fill" : "circle"
        let traits: AccessibilityTraits = chosen ? .isSelected : []
        return Button { withAnimation(.snappy) { path = option } } label: {
            HStack(spacing: 16) {
                Image(systemName: option.symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.headline)
                    Text(option.blurb).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: mark)
                    .font(.title3)
                    .foregroundStyle(ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(PopTileStyle(cornerRadius: 16, plane: plane))
        .accessibilityAddTraits(traits)
    }

    private var nameSection: some View {
        Section {
            // the main field of New set: its own slab, standing out of the glass
            TextField("Name", text: $name, prompt: Text("e.g. Cardiology week 3"))
                .font(.body)
                .popFieldRow()
        } header: {
            Text("Name your set")
        }
    }

    /// Narrate's lecture path is recording, which lives in Narrate itself.
    static func paths(for kind: StudySetKind) -> [Path] {
        kind == .narrate ? [.type, .importFile] : Path.allCases
    }

    /// The kind's name in plain words, for the tiles: "Practice questions"
    /// says what an MCQ set is to someone who has never met the letters.
    static func plainName(_ kind: StudySetKind) -> String {
        switch kind {
        case .mcq: return "Practice questions (MCQ)"
        case .anki: return "Flashcards"
        case .book: return "Textbook"
        case .qa: return "Cases"
        case .osce: return "OSCE checklists"
        case .narrate: return "Narrate"
        }
    }

    static func blurb(_ kind: StudySetKind) -> String {
        switch kind {
        case .mcq: return "Multiple-choice questions, like the exam"
        case .anki: return "Cards that come back just before you forget"
        case .book: return "Your lecture as easy pages to read"
        case .qa: return "Patient cases to talk through"
        case .osce: return "Step-by-step checklists for practical exams"
        case .narrate: return "Your lecture written out to read along"
        }
    }

    /// Which button floats: the generator while there is nothing to save yet,
    /// then Save once there is - and only on the last step, which is the
    /// only one with a button to float.
    private var floatingID: String? {
        guard step == .make else { return nil }
        let generator: String?
        switch (path, kind) {
        case (.lecture, .mcq): generator = "mcq"
        case (.lecture, .osce): generator = "osce"
        case (.lecture, .anki), (.lecture, .qa), (.lecture, .book): generator = "writer"
        default: generator = nil
        }
        if showsCreate && (generator == nil || !bodyText.isEmpty || diagrams.included) { return "create" }
        return generator
    }

    // MARK: the material, for the chosen path only

    /// The lecture sections are always here, drawing only their part of the
    /// current step (nothing in step 1), so what they have read survives a
    /// trip back and forth between the steps.
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
                                subject: $subject,
                                name: name, step: step) { set in
                    // Diagram (occlusion) cards come back as an Anki set, which
                    // the quiz screen cannot show - opening it there crashed.
                    // Anything that is not a question set goes straight into
                    // the library instead.
                    guard set.kind == .mcq else {
                        store.addSet(set)
                        dismiss()
                        return
                    }
                    guard !set.questions.isEmpty else { return }
                    generatedSetSaved = false
                    generatedSet = set
                }
            case .osce:
                OsceGenerateSection(bodyText: $bodyText, subject: $subject, step: step,
                                    presetText: preset?.text ?? "", presetName: preset?.name ?? "")
                if step == .make && !bodyText.isEmpty { draftSection(title: "Check and edit") }
            case .anki, .qa, .book:
                LectureWriterSection(kind: kind, bodyText: $bodyText, readSource: $readSource,
                                     suggestedName: $name, bookFigures: $bookFigures, diagrams: $diagrams,
                                     subject: $subject, step: step,
                                     presetNotes: preset?.notes ?? "")
                if step == .make && !bodyText.isEmpty { draftSection(title: "Check and edit") }
            case .narrate:
                if step == .material { draftSection(title: "Type or paste") }
            }
        case .type:
            if step == .material { draftSection(title: "Type or paste") }
        case .importFile:
            if step == .material { importSection }
        }
    }

    /// A shared set: what it can be, or why the chosen file could not be
    /// read. The button that picks it is at the bottom, under the thumb.
    private var importSection: some View {
        let plain: String = "A .json set exported from \(Brand.name) (formerly CramDown) or the Red Pen web app. Choose it below \u{2014} it goes straight into your library."
        let message: String = importError ?? plain
        let ink: Color = importError == nil ? Color.secondary : Color.red
        let symbol: String = importError == nil ? "square.and.arrow.down" : "exclamationmark.triangle"
        return Section {
            Label(message, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(ink)
        }
    }

    /// Save, with how much is ready under it. On the typing path this is
    /// also where the subject waits, behind More options, since there is no
    /// lecture section to hold it.
    private var createSection: some View {
        Section {
            if !usesWriter {
                DisclosureGroup("More options") {
                    // a slab inside its cell: the rows around it stay cells
                    TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                        .popField()
                }
            }
            // the hero slab, the same as its floating copy in the dock
            Button { create() } label: {
                Label(saveTitle, systemImage: "checkmark")
            }
            .buttonStyle(.bigPrimary)
            .disabled(!canCreate)
            .keyboardShortcut("s", modifiers: .command)
            .frame(maxWidth: .infinity)
            .floatingActionAnchor("create")
        } footer: {
            Text(readiness)
        }
    }

    /// Whether a lecture section is doing the writing - and so holds the
    /// subject and the other extra choices itself.
    private var usesWriter: Bool {
        path == .lecture && kind != .narrate
    }

    private func draftSection(title: String) -> some View {
        Section {
            // what each line needs, before the box it goes in
            DisclosureGroup("How to lay it out", isExpanded: $showFormat) {
                Text(formatHelp(for: kind))
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $bodyText)
                .frame(minHeight: 180)
                .font(.system(.footnote, design: .monospaced))
                .popEditor()
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
        case .anki:
            let written: Int = PlainTextImport.parseAnkiQA(bodyText).count
            let pictures: Int = diagrams.included ? diagrams.cards.count : 0
            return written + pictures
        case .book:
            if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
            return BookPages.split(bodyText).count
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
        if count == 0 { return "Nothing readable yet \u{2014} open \u{201C}How to lay it out\u{201D} to see what each line needs." }
        let plural: String = count == 1 ? "" : "s"
        let ready: String = "\(count) \(noun)\(plural) ready."
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return ready + " Give the set a name to save it." }
        return ready
    }

    private func create() {
        guard canCreate else { return }
        var set = StudySet(name: name, subject: subject.isEmpty ? "General" : subject, kind: kind)
        set.folderId = preset?.folderId
        switch kind {
        case .mcq: set.questions = PlainTextImport.parseMCQ(bodyText)
        case .anki:
            set.cards = PlainTextImport.parseAnkiQA(bodyText)
            // image occlusion cards from the lecture's diagrams, with their pictures
            if diagrams.included {
                set.cards += diagrams.cards
                set.images = diagrams.images
            }
        case .book:
            // only the diagrams the pages actually show go into the set
            let kept = BookFigures.compact(bodyText, images: bookFigures.map(\.imageBase64))
            set.bookMarkdown = kept.markdown
            set.images = kept.images
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
