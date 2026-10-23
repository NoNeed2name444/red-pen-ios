import SwiftUI

/// The "generate a set from my material" half of New set.
///
/// Where the paywall sits, and it sits in one place on purpose. Reading a file,
/// typing questions, importing a deck and reviewing everything you already have
/// stay free. Writing questions is the app's one writer, its Cloud, which is
/// Pro; there is no writer to choose and nothing is written on the phone (the
/// owner, 23 Oct: "Lock it"). What it writes is checked by the verification
/// layer.
struct MCQGenerateForm: View {
    @EnvironmentObject var llm: LocalLLMService
    @EnvironmentObject var subscriptions: SubscriptionStore
    /// The New set this is in: closing it stops what this started, and only that.
    @Environment(\.generationOwner) private var generationOwner

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

    /// Whether the writer route can write here. Without it the UI says why
    /// (and offers Pro) rather than a button that fails.
    private var writerReady: Bool { llm.writer() != nil }

    private var canStart: Bool {
        !isGenerating
            && writerReady
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
                .wardRowBackground()
            }

            if step == .make {
                makeSection
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .floatingAction(id: "mcq", title: makeTitle, enabled: canStart,
                        inputs: [name, subject, String(highYield), String(sourceText.count)],
                        run: startGenerating)
    }

    private var makeTitle: String { "Make \(questionCount) questions" }

    /// Why Make cannot be tapped yet, under it (no writer: the row under the
    /// count says why). Stopping is the progress card's Cancel, at the bottom.
    private var makeHint: String? {
        if isGenerating || !writerReady { return nil }
        if sourceText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Go back and add a lecture first."
        }
        return nil
    }

    /// Step 3: how many, the one big button, and the rest behind More options.
    private var makeSection: some View {
        Section {
            CountField(title: "How many questions", value: $questionCount,
                       range: 3...MCQGenerator.maxQuestionsTotal)
                .disabled(isGenerating)
            if !writerReady {
                Label(llm.noWriter, systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
                if !llm.isPro {
                    Button("See Pro") { showPaywall = true }
                        .buttonStyle(.wardCompact)
                }
            }
            // the same as its floating copy in the dock
            Button { startGenerating() } label: {
                HStack {
                    if isGenerating { EcgLoader() }
                    Text(generateLabel)
                }
            }
            .buttonStyle(.wardPrimary)
            .disabled(!canStart)
            .frame(maxWidth: .infinity)
            .floatingActionAnchor("mcq")
            .wardButtonRow()
            if let generationStatus, !isGenerating {
                Text(generationStatus).font(.footnote).foregroundStyle(Color.wardInkSecondary)
            }
            if let makeHint {
                Text(makeHint)
                    .font(.footnote).foregroundStyle(Color.wardInkSecondary)
            }
            DisclosureGroup("More options", isExpanded: $showMore) {
                TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                    .popField()
                    .disabled(isGenerating)
                Toggle("Focus on high-yield facts", isOn: $highYield)
                    .disabled(isGenerating)
                if let summary = llm.summary(for: .writer) {
                    Text("Using \(summary).").font(.footnote).foregroundStyle(Color.wardInkSecondary)
                }
            }
        }
        .wardRowBackground()
    }

    private var generateLabel: String {
        if isGenerating { return generationStatus ?? "Writing\u{2026}" }
        return makeTitle
    }

    // MARK: generating

    private func startGenerating() {
        // the writer route or nothing (WriterGate): it is Pro, offered beside
        // the count rather than started and taken away, and no question is
        // written on the phone.
        // something else is being written: said here, and left running
        if let busy = GenerationCenter.shared.busy {
            generationStatus = busy
            return
        }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let writer: LLMBackend? = llm.writer()
        let noWriter: String = llm.noWriter
        guard !text.isEmpty, writer != nil else { return }
        isGenerating = true
        generationStatus = "Writing 0 of \(questionCount) questions\u{2026}"
        let count = questionCount, subj = subject, hy = highYield, setName = name
        let cite = readSource
        // the verification layer checks what is made (VerificationScreen now,
        // the independent checkers once the set is saved): no single model's
        // screening to wait on
        let verify: Bool = llm.checkGenerated
        // A cloud job's replies stay kept - on this device and on the
        // server - until this generation is done with them, however it
        // ends: an app closed while they are checked or saved finds them
        // again on its next launch (CloudJobs.Delivery). Made before the
        // card, which tells it when the system stopped the generation.
        let delivery = CloudJobs.Delivery()
        guard let job = GenerationCenter.shared.begin("Writing \(count) questions", total: count, owner: generationOwner,
                                                      keeping: delivery, onCancel: {
            generationTask?.cancel()
            generationTask = nil
            isGenerating = false
            generationStatus = "Cancelled."
        }) else {
            isGenerating = false
            generationStatus = GenerationCenter.shared.busy
            return
        }
        generationTask = Task {
            defer { CloudJobs.finish(delivery) }
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    GenerationCenter.shared.update(job, done: done, total: total)
                    Task { @MainActor in
                        generationStatus = "Writing \(done) of \(total) questions\u{2026}"
                    }
                }
                // kept with a cloud job, so the set is still made if the
                // app is closed before the server finishes
                let recipe = CloudRecipe(kind: .mcq, name: setName, subject: subj, count: count,
                                         source: cite?.doc(), exam: ExamChoice.current?.id).encoded
                var questions: [MCQQuestion] = try await WriterGate.write(.questions, with: writer, noWriter: noWriter) { writer in
                    try await CloudJobs.$context.withValue(CloudJobs.Context(recipe: recipe, delivery: delivery)) {
                        try await MedicalGenerate.mcq(
                            sourceText: text, count: count, subject: subj,
                            highYield: hy, using: writer, onProgress: progress)
                    }
                }
                // the verification layer's first stage, on the device and
                // instant: a broken question is removed with its reason, a red
                // flag is held; the independent checkers take the set once saved
                try Task.checkCancellation()
                var checkNote = ""
                if verify {
                    let screened = VerificationScreen.questions(questions)
                    questions = screened.kept
                    checkNote = VerificationScreen.note(screened)
                }
                guard !questions.isEmpty else {
                    throw LLMError.notReady("Every question failed the on-device checks \u{2014} try a clearer source.")
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
                    // written to the chosen exam's format: badged with it
                    set.exam = ExamChoice.current?.id
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
                // a writer that reports being stopped as its own error is
                // still just stopped
                guard !Task.isCancelled else {
                    await MainActor.run { GenerationCenter.shared.end(job); isGenerating = false }
                    return
                }
                await MainActor.run {
                    GenerationCenter.shared.end(job)
                    isGenerating = false
                    generationStatus = error.localizedDescription
                }
            }
        }
    }
}
