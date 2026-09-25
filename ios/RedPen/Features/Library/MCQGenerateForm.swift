import SwiftUI

/// The "generate a set from my material" half of New set.
///
/// Where the paywall sits, and it sits in one place on purpose. Reading a file,
/// typing questions, importing a deck and reviewing everything you already have
/// stay free, and so does generating with Apple's model or the Gemma fallback.
/// What Pro buys is the medical models: Doctor-R1 and MedVAL on the device,
/// and CramDown Cloud, the larger hosted models.
struct MCQGenerateForm: View {
    @EnvironmentObject var gemma: GemmaModel
    @EnvironmentObject var llm: LocalLLMService
    @EnvironmentObject var subscriptions: SubscriptionStore

    @Binding var sourceText: String
    @Binding var questionCount: Int
    @Binding var highYield: Bool
    @Binding var readSource: ReadSource?
    /// Kept by New set; asked for here, under More options, because it only
    /// matters once there is something to write.
    @Binding var subject: String
    let name: String
    /// Which step of New set is showing: the lecture in step 2, the count and
    /// the Make button in step 3, nothing in step 1. The form stays in the
    /// view throughout so a file read in step 2 is still read in step 3.
    let step: NewSetStep
    let onGenerated: (StudySet) -> Void

    @State private var isGenerating = false
    @State private var generationStatus: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var showPaywall = false
    @State private var showMore = false

    private enum Backend: Equatable { case medical, apple, gemma }
    /// Which backend a tap on Generate would actually use. `nil` means neither
    /// is ready, and the UI says why rather than offering a button that fails.
    private var activeBackend: Backend? {
        // a writer chosen in AI models is an explicit choice, so it goes first
        if llm.backend(for: .writer) != nil { return .medical }
        if MCQGenerator.availability.isAvailable { return .apple }
        if gemma.status == .ready { return .gemma }
        return nil
    }

    private var canStart: Bool {
        !isGenerating
            && !(activeBackend == nil && !llm.needsPro(.writer))
            && !sourceText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            // Always built, only shown in step 2: it holds the diagrams it
            // found, and leaving the view would forget them.
            LecturePDFSection(sourceText: $sourceText, questionCount: $questionCount,
                              readSource: $readSource, disabled: isGenerating,
                              name: name, subject: subject,
                              visible: step == .material,
                              onOcclusionSet: onGenerated)

            if step == .material {
                Section {
                    TextEditor(text: $sourceText)
                        .frame(minHeight: 160)
                        .font(.system(.footnote, design: .monospaced))
                        .popEditorRow()
                        .disabled(isGenerating)
                } header: {
                    Text("Or paste your notes")
                } footer: {
                    Text("The questions are written from this text. A file you add above lands here too.")
                }
            }

            if step == .make {
                // with no model ready, getting one is the first thing to do,
                // so it comes before the button it unlocks
                if needsOfflineModel {
                    backendSection
                    makeSection
                } else {
                    makeSection
                    backendSection
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { gemma.refreshStatus() }
        .floatingAction(id: "mcq", title: makeTitle, enabled: canStart,
                        inputs: [name, subject, String(highYield), String(sourceText.count)],
                        run: startGenerating)
    }

    private var makeTitle: String { "Make \(questionCount) questions" }

    /// No model can write yet, and none needs Pro: the offline model has to
    /// be downloaded first.
    private var needsOfflineModel: Bool {
        activeBackend == nil && !llm.needsPro(.writer)
    }

    /// Why Make cannot be tapped yet, under it. Stopping is the progress
    /// card's Cancel, at the bottom.
    private var makeHint: String? {
        if isGenerating { return nil }
        if needsOfflineModel {
            if case .downloading = gemma.status { return "The offline model is downloading \u{2014} Make works once it is done." }
            return "Download the offline model first"
        }
        if sourceText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Nothing to write from yet \u{2014} go Back and add a lecture."
        }
        return nil
    }

    /// Step 3: how many, the one big button, and the rest behind More options.
    private var makeSection: some View {
        Section {
            CountField(title: "How many questions", value: $questionCount,
                       range: 3...MCQGenerator.maxQuestionsTotal)
                .disabled(isGenerating)
            if llm.needsPro(.writer) {
                Label("The medical models are part of Pro. Apple's model is free \u{2014} switch in AI models.",
                      systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // the hero slab, the same as its floating copy in the dock, so
            // it does not flatten when the real one takes over
            Button { startGenerating() } label: {
                HStack {
                    if isGenerating { ProgressView().controlSize(.small) }
                    Text(generateLabel)
                }
            }
            .buttonStyle(.bigPrimary)
            .disabled(!canStart)
            .frame(maxWidth: .infinity)
            .floatingActionAnchor("mcq")
            if let generationStatus, !isGenerating {
                Text(generationStatus).font(.footnote).foregroundStyle(.secondary)
            }
            if let makeHint {
                Text(makeHint)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("More options", isExpanded: $showMore) {
                TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                    .popField()
                    .disabled(isGenerating)
                Toggle("Focus on high-yield facts", isOn: $highYield)
                    .disabled(isGenerating)
                if activeBackend == .medical, let summary = llm.summary(for: .writer) {
                    Text("Using \(summary).").font(.footnote).foregroundStyle(.secondary)
                } else if activeBackend == .gemma {
                    Text("Using the downloaded Gemma 4 E2B model \u{2014} on-device, nothing sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
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

    private var generateLabel: String {
        if isGenerating { return generationStatus ?? "Writing\u{2026}" }
        if llm.needsPro(.writer) { return "Unlock the medical models" }
        return makeTitle
    }

    /// Apple's on-device model is tried first; this only appears when that is
    /// unavailable, offering the Gemma download as a fallback that still never
    /// touches anyone's account.
    @ViewBuilder
    private var backendSection: some View {
        if activeBackend != .medical, !MCQGenerator.availability.isAvailable {
            Section {
                if case .unavailable(let reason) = MCQGenerator.availability {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                switch gemma.status {
                case .ready:
                    EmptyView() // covered by the note in the generate section
                case .notDownloaded:
                    Button { gemma.download() } label: {
                        Label("Download the offline model (3.4 GB, once)",
                              systemImage: "arrow.down.circle")
                    }
                    Text("A smaller model (Gemma 4 E2B, plus its vision projector) that runs entirely on this device once downloaded \u{2014} works on hardware that can't run Apple's own on-device model, and can also read images.")
                        .font(.caption).foregroundStyle(.secondary)
                case .downloading(let fraction):
                    let percent: Int = Int(fraction * 100)
                    let line: String = "Downloading offline model \u{2014} \(percent)%"
                    ProgressView(value: fraction) {
                        Text(line).font(.footnote)
                    }
                    Button("Cancel download", role: .cancel) { gemma.cancelDownload() }
                case .failed(let message):
                    Text("Download failed: \(message)").font(.footnote).foregroundStyle(.red)
                    Button("Try again") { gemma.download() }
                }
            } header: {
                Text("Needed first: an offline model")
            }
        }
    }

    // MARK: generating

    private func startGenerating() {
        // Apple's model and Gemma are free; the medical models are Pro, and
        // then the paywall opens instead of the work starting - nothing is
        // generated and then taken away, which is the version people hate.
        if llm.needsPro(.writer) { showPaywall = true; return }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let backend = activeBackend else { return }
        isGenerating = true
        generationStatus = "Writing 0 of \(questionCount) questions\u{2026}"
        let count = questionCount, subj = subject, hy = highYield, setName = name
        let cite = readSource
        let writer = llm.backend(for: .writer)
        let checker = llm.checkGenerated ? llm.backend(for: .checker) : nil
        let job = GenerationCenter.shared.begin("Writing \(count) questions", total: count) {
            generationTask?.cancel()
            generationTask = nil
            isGenerating = false
            generationStatus = "Cancelled."
        }
        generationTask = Task {
            // A cloud job's replies stay kept - on this device and on the
            // server - until this generation is done with them, however it
            // ends: an app closed while they are checked or saved finds them
            // again on its next launch (CloudJobs.Delivery).
            let delivery = CloudJobs.Delivery()
            defer { CloudJobs.finish(delivery) }
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    GenerationCenter.shared.update(job, done: done, total: total)
                    Task { @MainActor in
                        generationStatus = "Writing \(done) of \(total) questions\u{2026}"
                    }
                }
                var questions: [MCQQuestion]
                switch backend {
                case .medical:
                    guard let writer else { throw LLMError.notReady("Choose a writer in AI models.") }
                    // kept with a cloud job, so the set is still made if the
                    // app is closed before the server finishes
                    let onServer = (checker as? CloudJobBackend)?.checksOnServer == true
                    let check: String? = MCQGenerateForm.checkPlace(checker != nil, onServer: onServer)
                    let recipe = CloudRecipe(kind: .mcq, name: setName, subject: subj, count: count,
                                             source: cite?.doc(), check: check).encoded
                    questions = try await CloudJobs.$context.withValue(CloudJobs.Context(recipe: recipe, serverCheck: onServer,
                                                               checking: { done, total in
                        Task { @MainActor in GenerationCenter.shared.update(job, done: done, total: total, phase: "Checking accuracy in the cloud") }
                    }, delivery: delivery)) {
                        try await MedicalGenerate.mcq(
                            sourceText: text, count: count, subject: subj,
                            highYield: hy, using: writer, onProgress: progress)
                    }
                case .apple:
                    questions = try await MCQGenerator.generate(
                        sourceText: text, count: count, subject: subj,
                        highYield: hy, onProgress: progress)
                case .gemma:
                    questions = try await gemma.generate(
                        sourceText: text, count: count, subject: subj,
                        highYield: hy, onProgress: progress)
                }
                // every generated question checked against the lecture before it
                // reaches the set; high-risk ones are dropped
                try Task.checkCancellation()
                var checkNote = ""
                if let checker {
                    let screened = await AccuracyChecker.screen(
                        questions, source: text, using: checker,
                        onProgress: { done, total in
                            GenerationCenter.shared.update(job, done: done, total: total, phase: "Checking with \(checker.label)")
                            Task { @MainActor in
                                generationStatus = "Checking \(done) of \(total) with \(checker.label)\u{2026}"
                            }
                        })
                    let screenedTotal: Int = questions.count
                    questions = screened.kept
                    // a question the checker never graded is not a checked one
                    checkNote += MedVAL.uncheckedNote(screened.unchecked, of: screenedTotal)
                    if screened.removed > 0 { checkNote += " \(screened.removed) removed as high risk." }
                    if screened.flagged > 0 { checkNote += " \(screened.flagged) flagged moderate risk \u{2014} check them." }
                }
                guard !questions.isEmpty else {
                    throw LLMError.notReady("The checker graded every question high risk \u{2014} try a clearer source.")
                }
                let finalQuestions = questions
                let note = checkNote
                try Task.checkCancellation()
                await MainActor.run {
                    GenerationCenter.shared.end(job, finished: "Your \(finalQuestions.count) questions are ready")
                    isGenerating = false
                    generationStatus = "Done \u{2014} \(finalQuestions.count) question(s) written." + note
                    let plainSubject: Bool = subj.isEmpty || subj == "General"
                    let fallback: String = plainSubject ? "Generated set" : subj
                    let setTitle: String = setName.isEmpty ? fallback : setName
                    let setSubject: String = subj.isEmpty ? "General" : subj
                    var set = StudySet(name: setTitle, subject: setSubject, kind: .mcq)
                    // each question is matched back to the page whose words it
                    // shares; one that matches nothing is left uncited, which
                    // is itself worth seeing
                    set.questions = cite.map {
                        Provenance.attribute(finalQuestions, to: $0.document, name: $0.name)
                    } ?? finalQuestions
                    // The lecture goes with the set, so those citations lead
                    // somewhere instead of merely naming a page.
                    set.sources = cite.map { [$0.doc()] } ?? []
                    onGenerated(set)
                }
            } catch is CancellationError {
                await MainActor.run { GenerationCenter.shared.end(job); isGenerating = false }
            } catch {
                // a model that reports being stopped as its own error (Gemma)
                // is still just stopped
                guard !Task.isCancelled else {
                    await MainActor.run { GenerationCenter.shared.end(job); isGenerating = false }
                    return
                }
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    isGenerating = false
                    generationStatus = (error as? MCQGenerator.GenerationError)?.errorDescription
                        ?? (error as? GemmaModel.GenerationError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    /// Where the accuracy check runs, for a cloud job's recipe: nil for none.
    nonisolated static func checkPlace(_ checking: Bool, onServer: Bool) -> String? {
        guard checking else { return nil }
        return onServer ? "server" : "device"
    }
}
