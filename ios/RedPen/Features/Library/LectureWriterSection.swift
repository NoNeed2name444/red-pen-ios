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
    let subject: String
    /// Notes to start from, when a set is being turned into this mode and
    /// kept no lecture: its own content, in the paste box, ready to write from.
    var presetNotes: String = ""
    @State private var style: CardStyle = .mixed

    @EnvironmentObject private var llm: LocalLLMService
    @State private var picking = false
    @State private var pastedNotes = ""
    @State private var showPaste = false
    @State private var count = 12
    @State private var working = false
    @State private var reading = false
    /// The background look for diagrams, and how far it has got.
    @State private var figureTask: Task<Void, Never>?
    @State private var diagramProgress: String?
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
            if let diagramProgress {
                Label(diagramProgress, systemImage: "photo.on.rectangle.angled")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if kind == .anki {
                Picker("Card type", selection: $style) {
                    ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(working)
                if style.usesDiagrams, readSource != nil {
                    Text(diagrams.cards.isEmpty ? "No labelled diagrams were found in this file."
                                                : "\(diagrams.cards.count) image occlusion card\(diagrams.cards.count == 1 ? "" : "s") from the file's diagrams.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if style.writesText || kind != .anki {
            CountField(title: "\(noun.capitalized)s", value: $count,
                       range: kind == .book ? 1...1_000 : 1...10_000)
                .disabled(working)
            }
            Button {
                working ? stop() : start()
            } label: {
                HStack {
                    if working || reading { ProgressView().controlSize(.small) }
                    Text(reading ? "Reading\u{2026}" : working ? (status ?? "Writing\u{2026}") : actionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled((!canWrite && !working) || reading)
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
        .floatingAction(id: "writer", title: actionTitle,
                        enabled: canWrite && !working && !reading,
                        inputs: [kind.rawValue, subject, style.rawValue, String(sourceText.count),
                                 String(bookFigures.count), String(diagrams.cards.count)], run: start)
        .onChange(of: style) { _, now in
            if kind == .anki { diagrams.included = now.usesDiagrams && !diagrams.cards.isEmpty && (now == .image || !bodyText.isEmpty) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.readableTypes,
                      allowsMultipleSelection: false) { result in
            Task { await read(result) }
        }
        .onAppear {
            guard pastedNotes.isEmpty, !presetNotes.isEmpty else { return }
            pastedNotes = presetNotes
            showPaste = true
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
        reading = true
        status = "Reading\u{2026}"
        defer { reading = false }
        do {
            let ext = url.pathExtension.lowercased()
            // The text first - it is almost instant - so writing can start
            // straight away; the diagrams are looked for afterwards, in the
            // background (findDiagrams).
            figureTask?.cancel()
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
            readSource = ReadSource(name: name, document: read.document,
                                    kind: ext == "pdf" ? .pdf : ext == "pptx" ? .powerpoint : .word)
            if suggestedName.trimmingCharacters(in: .whitespaces).isEmpty { suggestedName = name }
            if kind == .book { count = min(30, max(1, read.document.pages.count / 3)) }
            else { count = min(80, max(8, (read.document.pages.count / 2 + 3) / 4 * 4)) }
            status = nil
            if !hasSource { trouble = "There is not much text in that file to work from." }
            // a textbook places the lecture's diagrams; Cards makes image
            // occlusion cards from them
            if kind == .book || kind == .anki { findDiagrams(in: url, pdf: ext == "pdf") }
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    /// Each diagram as a JPEG small enough to keep in a set, with its page,
    /// labels and page text so it can find the page about its topic.
    nonisolated static func figures(from read: SourceIngest.Result) -> [BookFigure] {
        read.figures.enumerated().compactMap { i, image in
            let scale = min(1, 1400 / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = small.jpegData(compressionQuality: 0.7) else { return nil }
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
            return "Add \(diagrams.cards.count) image card\(diagrams.cards.count == 1 ? "" : "s")"
        }
        return "Write \(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private var canWrite: Bool {
        if kind == .anki && style == .image { return !diagrams.cards.isEmpty }
        return hasSource
    }

    /// Looks for labelled diagrams while the student carries on: several
    /// slides at a time, off the main thread, the count shown as it goes.
    private func findDiagrams(in url: URL, pdf: Bool) {
        let mode = kind
        let name = url.deletingPathExtension().lastPathComponent
        diagramProgress = "Finding diagrams\u{2026}"
        figureTask = Task {
            let read = await Task.detached(priority: .userInitiated) { () -> SourceIngest.Result? in
                if pdf {
                    return try? await SourceIngest.read(pdf: url, findingFigures: true, readingText: false,
                                                        onPage: { done, total in
                        Task { @MainActor in diagramProgress = "Finding diagrams \(done) of \(total)\u{2026}" }
                    })
                }
                return try? await OfficeIngest.read(url, findingFigures: true)
            }.value
            guard !Task.isCancelled else { return }
            bookFigures = read.map { mode == .book ? Self.figures(from: $0) : [] } ?? []
            diagrams = read.map { mode == .anki ? Self.diagramCards(from: $0, name: name) : DiagramCards() } ?? DiagramCards()
            // found after the text cards were written: still in the set
            diagrams.included = style.usesDiagrams && !diagrams.cards.isEmpty && (style == .image || !bodyText.isEmpty)
            diagramProgress = nil
        }
    }

    // MARK: writing

    private func start() {
        trouble = nil
        // image occlusion alone needs no model: the diagrams are the cards
        if kind == .anki {
            diagrams.included = style.usesDiagrams && !diagrams.cards.isEmpty
            if style == .image {
                status = diagrams.cards.isEmpty ? nil
                    : "\(diagrams.cards.count) image card\(diagrams.cards.count == 1 ? "" : "s") ready \u{2014} create the set below."
                if diagrams.cards.isEmpty { trouble = "No labelled diagrams were found in this file." }
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
        let job = GenerationCenter.shared.begin("Writing \(wanted) \(noun)\(wanted == 1 ? "" : "s")", total: wanted) {
            task?.cancel()
            task = nil
            working = false
            status = "Cancelled."
        }
        task = Task {
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
                let recipe = await MainActor.run {
                    CloudRecipe(kind: mode, name: suggestedName, subject: subj, count: wanted,
                                source: readSource?.doc(),
                                figures: mode == .book ? figures.map(\.imageBase64) : nil,
                                diagramCards: mode == .anki && diagrams.included ? diagrams.cards : nil,
                                diagramImages: mode == .anki && diagrams.included ? diagrams.images : nil,
                                check: checker == nil ? nil : onServer ? "server" : "device").encoded
                }
                let written = try await CloudJobs.$context.withValue(CloudJobs.Context(recipe: recipe, serverCheck: onServer,
                                                               checking: { done, total in
                        GenerationCenter.shared.update(job, done: done, total: total, phase: "Checking accuracy in the cloud")
                    })) {
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
                        note = verdict.passed ? " Checked: \(verdict.riskTitle.lowercased())."
                            : " Checker: \(verdict.riskTitle.lowercased()) \u{2014} \(verdict.findings.first?.text ?? "read it carefully")."
                    }
                }
                let finalNote = note
                try Task.checkCancellation()
                await MainActor.run {
                    GenerationCenter.shared.end(job, finished: mode == .book ? "Your textbook is ready" : "Your \(mode == .qa ? "cases" : "cards") are ready")
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

    private func stop() { GenerationCenter.shared.cancel() }
}
