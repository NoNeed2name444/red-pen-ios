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
    /// The lecture's diagrams, for a textbook to place on its pages.
    @Binding var bookFigures: [BookFigure]
    /// Cards made from the lecture's labelled diagrams (Cards mode).
    @Binding var diagrams: DiagramCards
    /// Kept by New set; asked for here, under More options.
    @Binding var subject: String
    /// Which step of New set is showing: the file and notes in step 2, the
    /// count and the Make button in step 3, nothing in step 1. The section
    /// stays in the view throughout, so what it read survives the steps.
    let step: NewSetStep
    /// Notes to start from, when a set is being turned into this mode and
    /// kept no lecture: its own content, in the paste box, ready to write from.
    var presetNotes: String = ""
    @State private var style: CardStyle = .mixed

    @EnvironmentObject private var llm: LocalLLMService
    @State private var picking = false
    @State private var pastedNotes = ""
    @State private var showMore = false
    @State private var count = 12
    @State private var working = false
    @State private var reading = false
    /// The background look for diagrams, and how far it has got.
    @State private var figureTask: Task<Void, Never>?
    @State private var diagramProgress: String?
    /// Which diagram scan is current, so one that was replaced by a newer
    /// file cannot write over the newer one's progress or results.
    @State private var diagramRun = 0
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
        Group {
            if step == .material { addSection }
            if step == .make { makeSection }
        }
        .floatingAction(id: "writer", title: actionTitle,
                        enabled: canWrite && !working && !reading,
                        inputs: [kind.rawValue, subject, style.rawValue, String(sourceText.count),
                                 String(bookFigures.count), String(diagrams.cards.count)], run: start)
        .onChange(of: style) { _, now in
            guard kind == .anki else { return }
            diagrams.included = diagramsWanted(now)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.readableTypes,
                      allowsMultipleSelection: false) { result in
            // held by FileReads, so closing New set stops the reading
            FileReads.run { await read(result) }
        }
        .onAppear {
            guard pastedNotes.isEmpty, !presetNotes.isEmpty else { return }
            pastedNotes = presetNotes
        }
        .sheet(isPresented: $showModels) { ModelSettingsView() }
    }

    /// Step 2: a lecture file, or notes pasted in, or both.
    private var addSection: some View {
        Section {
            // raised, but second to the dock's Next
            Button { picking = true } label: {
                HStack {
                    if reading { ProgressView().controlSize(.small) }
                    Label(pickTitle, systemImage: "doc.badge.plus")
                }
            }
            .buttonStyle(.bigSecondary)
            .disabled(working || reading)
            .frame(maxWidth: .infinity)
            if let readSource {
                let pages: Int = readSource.document.pages.count
                let line: String = "\(readSource.name) \u{2014} \(pages) pages"
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let diagramProgress {
                Label(diagramProgress, systemImage: "photo.on.rectangle.angled")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let trouble {
                Text(trouble).font(.footnote).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Or paste your notes").font(.subheadline.weight(.semibold))
                TextEditor(text: $pastedNotes)
                    .frame(minHeight: 120)
                    .font(.footnote)
                    .popEditor()
                    .disabled(working)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Add a file")
        } footer: {
            Text("PDF, Word or PowerPoint. It is read on this device.")
        }
    }

    /// Step 3: the card type (Cards only), how many, the one big button,
    /// and the rest behind More options. Stopping is the progress card's
    /// Cancel, at the bottom, so the button never turns into Stop.
    private var makeSection: some View {
        Section {
            if kind == .anki {
                Picker("Card type", selection: $style) {
                    ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(working)
                if style.usesDiagrams, readSource != nil {
                    Text(diagramNote)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if style.writesText || kind != .anki {
                CountField(title: "How many \(noun)s", value: $count, range: countRange)
                    .disabled(working)
            }
            // the hero slab, the same as its floating copy in the dock
            Button { start() } label: {
                HStack {
                    if working || reading { ProgressView().controlSize(.small) }
                    Text(primaryLabel)
                }
            }
            .buttonStyle(.bigPrimary)
            .disabled(!canWrite || working || reading)
            .frame(maxWidth: .infinity)
            .floatingActionAnchor("writer")
            if let diagramProgress {
                Label(diagramProgress, systemImage: "photo.on.rectangle.angled")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let status, !working {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if !hasSource && !(kind == .anki && style == .image) {
                Text("Nothing to write from yet \u{2014} go Back and add a lecture.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let trouble {
                Text(trouble).font(.footnote).foregroundStyle(.red)
                Button("AI models") { showModels = true }
                    .buttonStyle(.bordered)
            }
            DisclosureGroup("More options", isExpanded: $showMore) {
                TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                    .popField()
                    .disabled(working)
                Text(modelLine)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Step 2's file button: what it does now.
    private var pickTitle: String {
        if reading { return "Reading\u{2026}" }
        if readSource == nil { return "Choose a lecture file" }
        return "Choose a different file"
    }

    /// Step 3's button: what it will make, or how far it has got.
    private var primaryLabel: String {
        if reading { return "Reading\u{2026}" }
        if working { return status ?? "Writing\u{2026}" }
        return actionTitle
    }

    private var countRange: ClosedRange<Int> {
        kind == .book ? 1...1_000 : 1...10_000
    }

    /// Whether the diagrams' picture cards go into the set, for a card
    /// type: only when it uses them, some were found, and there is either
    /// nothing else (picture cards alone) or written cards beside them.
    private func diagramsWanted(_ chosen: CardStyle) -> Bool {
        let found: Bool = !diagrams.cards.isEmpty
        let alongside: Bool = chosen == .image || !bodyText.isEmpty
        return chosen.usesDiagrams && found && alongside
    }

    private var diagramNote: String {
        let found = diagrams.cards.count
        if found == 0 { return "No labelled diagrams were found in this file." }
        let plural: String = found == 1 ? "" : "s"
        return "\(found) picture card\(plural) from the file's diagrams."
    }

    private var modelLine: String {
        if let backend = llm.writerOrApple() {
            let place: String = backend.isOnDevice ? " on this device" : ""
            return "Written by \(backend.label)\(place). The \(noun)s appear below to check before you save the set."
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
        reading = true
        status = "Reading\u{2026}"
        defer { reading = false }
        do {
            let ext = url.pathExtension.lowercased()
            // The text first - it is almost instant - so writing can start
            // straight away; the diagrams are looked for afterwards, in the
            // background (findDiagrams).
            // the previous file's diagram scan ends here, label and all,
            // whatever kind this file turns out to be
            stopDiagrams()
            bookFigures = []
            diagrams = DiagramCards()
            let read = ext == "pdf" ? try await SourceIngest.read(pdf: url, findingFigures: false)
                                    : try await OfficeIngest.read(url, findingFigures: false)
            // pictures numbered for the previous file would now point at the
            // wrong diagrams: they go, and the new pages will place their own
            bodyText = bodyText.components(separatedBy: "\n")
                .filter { BookFigures.parse($0.trimmingCharacters(in: .whitespaces)) == nil }
                .joined(separator: "\n")
            let name = url.deletingPathExtension().lastPathComponent
            let fileKind: SourceDoc.Kind = LectureWriterSection.fileKind(ext)
            readSource = ReadSource(name: name, document: read.document, kind: fileKind)
            if suggestedName.trimmingCharacters(in: .whitespaces).isEmpty { suggestedName = name }
            if kind == .book { count = min(30, max(1, read.document.pages.count / 3)) }
            else {
                let pages: Int = read.document.pages.count
                let raw: Int = (pages / 2 + 3) / 4 * 4
                count = min(80, max(8, raw))
            }
            status = nil
            if !hasSource { trouble = "There is not much text in that file to work from." }
            // a textbook places the lecture's diagrams; Cards makes image
            // occlusion cards from them
            if kind == .book || kind == .anki { findDiagrams(in: url, pdf: ext == "pdf") }
        } catch is CancellationError {
            // New set closed: nobody is waiting for this file any more
            status = nil
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    /// Each diagram as a JPEG small enough to keep in a set, with its page,
    /// labels and page text so it can find the page about its topic.
    nonisolated static func figures(from read: SourceIngest.Result) -> [BookFigure] {
        read.figures.enumerated().compactMap { i, image in
            // 1,400 PIXELS: a renderer at the screen's scale made this 4,200
            guard let jpeg = SourceIngest.downsized(image, maxDimension: 1400, quality: 0.7) else { return nil }
            let note = read.figureNotes.indices.contains(i) ? read.figureNotes[i] : (page: nil, labels: [])
            let pageText = note.page.flatMap { number in read.document.pages.first { $0.number == number }?.text } ?? ""
            return BookFigure(imageBase64: jpeg.base64EncodedString(), page: note.page,
                              labels: note.labels, pageText: String(pageText.prefix(600)))
        }
    }

    /// The file's image occlusion cards, their pictures kept small and
    /// renumbered to the pictures actually kept.
    nonisolated static func diagramCards(from read: SourceIngest.Result, name: String) -> DiagramCards {
        var images: [String] = []
        var moved: [Int: Int] = [:]
        for (old, figure) in read.figures.enumerated() {
            guard let data = SourceIngest.downsized(figure) else { continue }
            moved[old] = images.count
            images.append(data.base64EncodedString())
        }
        let cards = read.occlusionCards.compactMap { card -> AnkiCard? in
            guard let old = card.imageIndex, let new = moved[old] else { return nil }
            var renumbered = card
            renumbered.imageIndex = new
            return renumbered
        }
        return DiagramCards(cards: cards, images: images, included: false)
    }

    private var actionTitle: String {
        if kind == .anki && style == .image {
            let found: Int = diagrams.cards.count
            let plural: String = found == 1 ? "" : "s"
            return "Add \(found) image card\(plural)"
        }
        let plural: String = count == 1 ? "" : "s"
        return "Make \(count) \(noun)\(plural)"
    }

    /// PDF, PowerPoint or Word, by the file's extension.
    nonisolated static func fileKind(_ ext: String) -> SourceDoc.Kind {
        if ext == "pdf" { return .pdf }
        if ext == "pptx" { return .powerpoint }
        return .word
    }

    /// Where the accuracy check runs, for a cloud job's recipe: nil for none.
    nonisolated static func checkPlace(_ checking: Bool, onServer: Bool) -> String? {
        guard checking else { return nil }
        return onServer ? "server" : "device"
    }

    private var canWrite: Bool {
        if kind == .anki && style == .image { return !diagrams.cards.isEmpty }
        return hasSource
    }

    /// Looks for labelled diagrams while the student carries on: several
    /// slides at a time, off the main thread, the count shown as it goes.
    ///
    /// Awaited inside a task FileReads holds, not detached: a detached scan
    /// never heard it had been cancelled, so picking another file left the
    /// old one OCRing every page and writing its count into the label.
    private func findDiagrams(in url: URL, pdf: Bool) {
        stopDiagrams()
        let mode = kind
        let name = url.deletingPathExtension().lastPathComponent
        let run = diagramRun
        diagramProgress = "Finding diagrams\u{2026}"
        figureTask = FileReads.run {
            let read: SourceIngest.Result?
            if pdf {
                read = try? await SourceIngest.read(pdf: url, findingFigures: true, readingText: false,
                                                    onPage: { done, total in
                    Task { @MainActor in
                        guard diagramRun == run else { return }
                        diagramProgress = "Finding diagrams \(done) of \(total)\u{2026}"
                    }
                })
            } else {
                read = try? await OfficeIngest.read(url, findingFigures: true)
            }
            // a scan that was replaced leaves everything to its successor
            guard diagramRun == run else { return }
            diagramProgress = nil
            guard !Task.isCancelled else { return }
            var figures: [BookFigure] = []
            var cards = DiagramCards()
            if let read, mode == .book { figures = Self.figures(from: read) }
            if let read, mode == .anki { cards = Self.diagramCards(from: read, name: name) }
            bookFigures = figures
            diagrams = cards
            // found after the text cards were written: still in the set
            diagrams.included = diagramsWanted(style)
        }
    }

    /// Cancels the diagram scan running, if any, and takes its label down.
    private func stopDiagrams() {
        figureTask?.cancel()
        figureTask = nil
        diagramRun += 1
        diagramProgress = nil
    }

    // MARK: writing

    private func start() {
        trouble = nil
        // image occlusion alone needs no model: the diagrams are the cards
        if kind == .anki {
            diagrams.included = style.usesDiagrams && !diagrams.cards.isEmpty
            if style == .image {
                let found: Int = diagrams.cards.count
                let plural: String = found == 1 ? "" : "s"
                status = found == 0 ? nil : "\(found) image card\(plural) ready \u{2014} save the set below."
                if found == 0 { trouble = "No labelled diagrams were found in this file." }
                return
            }
        }
        guard let backend = llm.writerOrApple() else {
            trouble = "No model is ready to write with."
            return
        }
        let checker = llm.checkGenerated ? llm.backend(for: .checker) : nil
        let text = sourceText, wanted = count, subj = subject, mode = kind, cardStyle = style, pending = figureTask
        working = true
        status = "Writing\u{2026}"
        let plural: String = wanted == 1 ? "" : "s"
        let jobTitle: String = "Writing \(wanted) \(noun)\(plural)"
        let job = GenerationCenter.shared.begin(jobTitle, total: wanted) {
            task?.cancel()
            task = nil
            working = false
            status = "Cancelled."
        }
        task = Task {
            // A cloud job's replies stay kept - on this device and on the
            // server - until this generation is done with them, however it
            // ends: an app closed while they are checked or saved finds them
            // again on its next launch (CloudJobs.Delivery).
            let delivery = CloudJobs.Delivery()
            defer { CloudJobs.finish(delivery) }
            do {
                // a textbook places the lecture's diagrams, so it waits for the
                // look for them to finish; cards never wait
                if mode == .book, let pending {
                    await MainActor.run { status = "Finishing the diagrams\u{2026}" }
                    await pending.value
                }
                let figures = await MainActor.run { bookFigures }
                let onServer = (checker as? CloudJobBackend)?.checksOnServer == true
                // kept with a cloud job, so the set is still made if the app
                // is closed before the server finishes
                let check: String? = LectureWriterSection.checkPlace(checker != nil, onServer: onServer)
                let recipe: Data? = await MainActor.run { () -> Data? in
                    let pictures: Bool = mode == .anki && diagrams.included
                    let figureImages: [String]? = mode == .book ? figures.map(\.imageBase64) : nil
                    let cards: [AnkiCard]? = pictures ? diagrams.cards : nil
                    let images: [String]? = pictures ? diagrams.images : nil
                    return CloudRecipe(kind: mode, name: suggestedName, subject: subj, count: wanted,
                                       source: readSource?.doc(), figures: figureImages,
                                       diagramCards: cards, diagramImages: images, check: check).encoded
                }
                let written = try await CloudJobs.$context.withValue(CloudJobs.Context(recipe: recipe, serverCheck: onServer,
                                                               checking: { done, total in
                        Task { @MainActor in GenerationCenter.shared.update(job, done: done, total: total, phase: "Checking accuracy in the cloud") }
                    }, delivery: delivery)) {
                    try await LectureWriter.write(
                        kind: mode, source: text, count: wanted, subject: subj, using: backend, figures: figures, style: cardStyle,
                        onProgress: { done, total in
                            GenerationCenter.shared.update(job, done: done, total: total)
                            Task { @MainActor in status = "Writing \(done) of \(total)\u{2026}" }
                        })
                }
                try Task.checkCancellation()
                var note = ""
                if let checker {
                    GenerationCenter.shared.update(job, done: wanted, total: wanted, phase: "Checking with \(checker.label)")
                    await MainActor.run { status = "Checking with \(checker.label)\u{2026}" }
                    if let verdict = try? await AccuracyChecker.check(
                        instruction: "Write study material for medical students from the source.",
                        input: AccuracyChecker.nearest(text, to: written, limit: checker.promptBudgetChars),
                        output: written, using: checker) {
                        let risk: String = verdict.riskTitle.lowercased()
                        let finding: String = verdict.findings.first?.text ?? "read it carefully"
                        note = verdict.passed ? " Checked: \(risk)." : " Checker: \(risk) \u{2014} \(finding)."
                    }
                }
                let finalNote = note
                try Task.checkCancellation()
                await MainActor.run {
                    let made: String = mode == .qa ? "cases" : "cards"
                    let finished: String = mode == .book ? "Your textbook is ready" : "Your \(made) are ready"
                    GenerationCenter.shared.end(job, finished: finished)
                    let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyText = existing.isEmpty ? written : existing + "\n" + written
                    working = false
                    status = "Written \u{2014} check them below." + finalNote
                }
            } catch is CancellationError {
                await MainActor.run { GenerationCenter.shared.end(job); working = false }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run { GenerationCenter.shared.end(job); working = false }
                    return
                }
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    working = false
                    status = nil
                    trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

}
