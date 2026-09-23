import SwiftUI

/// The "generate a set from my material" half of New set.
///
/// Where the paywall sits, and it sits in one place on purpose. Reading a file,
/// typing questions, importing a deck and reviewing everything you already have
/// stay free, and so does generating on the device - Apple's model, Gemma or
/// Doctor-R1 cost nothing to run. What Pro buys is CramDown Cloud: the larger
/// hosted models, which cost real money per request.
struct MCQGenerateForm: View {
    @EnvironmentObject var gemma: GemmaModel
    @EnvironmentObject var llm: LocalLLMService
    @EnvironmentObject var subscriptions: SubscriptionStore

    @Binding var sourceText: String
    @Binding var questionCount: Int
    @Binding var highYield: Bool
    @Binding var readSource: ReadSource?
    let name: String
    let subject: String
    let onGenerated: (StudySet) -> Void

    @State private var isGenerating = false
    @State private var generationStatus: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var showPaywall = false

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

    var body: some View {
        Group {
            LecturePDFSection(sourceText: $sourceText, questionCount: $questionCount,
                              readSource: $readSource, disabled: isGenerating,
                              name: name, subject: subject,
                              onOcclusionSet: onGenerated)

            Section {
                Text("The questions are written from this text \u{2014} a lecture read above lands here too.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $sourceText)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isGenerating)
            } header: {
                Text("Or paste notes")
            }

            Section {
                Stepper("Questions: \(questionCount)", value: $questionCount,
                        in: 3...MCQGenerator.maxQuestionsTotal)
                    .disabled(isGenerating)
                Toggle("High-yield focus", isOn: $highYield)
                    .disabled(isGenerating)
            }

            backendSection

            Section {
                if llm.writerChoice == .cloud, !subscriptions.isPro {
                    Label("CramDown Cloud is part of Pro. On-device models are free \u{2014} switch in AI models.",
                          systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if activeBackend == .medical, let summary = llm.summary(for: .writer) {
                    Text("Using \(summary).").font(.footnote).foregroundStyle(.secondary)
                } else if activeBackend == .gemma {
                    Text("Using the downloaded Gemma 4 E2B model \u{2014} on-device, nothing sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button { startGenerating() } label: {
                    HStack {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Text(generateLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isGenerating
                          || (activeBackend == nil && llm.writerChoice != .cloud)
                          || sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
                if isGenerating {
                    Button("Cancel", role: .cancel) { generationTask?.cancel() }
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { gemma.refreshStatus() }
        .onDisappear { generationTask?.cancel() }
    }

    private var generateLabel: String {
        if isGenerating { return generationStatus ?? "Writing\u{2026}" }
        return llm.writerChoice == .cloud && !subscriptions.isPro ? "Unlock CramDown Cloud" : "Generate questions"
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
                        Label("Download offline model (~3.4 GB, one-time)",
                              systemImage: "arrow.down.circle")
                    }
                    Text("A smaller model (Gemma 4 E2B, plus its vision projector) that runs entirely on this device once downloaded \u{2014} works on hardware that can't run Apple's own on-device model, and can also read images.")
                        .font(.caption).foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Downloading offline model \u{2014} \(Int(fraction * 100))%").font(.footnote)
                    }
                    Button("Cancel download", role: .cancel) { gemma.cancelDownload() }
                case .failed(let message):
                    Text("Download failed: \(message)").font(.footnote).foregroundStyle(.red)
                    Button("Try again") { gemma.download() }
                }
            } header: {
                Text("Offline model")
            }
        }
    }

    // MARK: generating

    private func startGenerating() {
        // On-device models are free. Only CramDown Cloud is Pro, and then the
        // paywall opens instead of the work starting; nothing is generated and
        // then taken away, which is the version of this people hate.
        if llm.writerChoice == .cloud, !subscriptions.isPro { showPaywall = true; return }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let backend = activeBackend else { return }
        isGenerating = true
        generationStatus = "Writing 0 of \(questionCount) questions\u{2026}"
        let count = questionCount, subj = subject, hy = highYield, setName = name
        let cite = readSource
        let writer = llm.backend(for: .writer)
        let checker = llm.checkGenerated ? llm.backend(for: .checker) : nil
        generationTask = Task {
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    Task { @MainActor in
                        generationStatus = "Writing \(done) of \(total) questions\u{2026}"
                    }
                }
                var questions: [MCQQuestion]
                switch backend {
                case .medical:
                    guard let writer else { throw LLMError.notReady("Choose a writer in AI models.") }
                    questions = try await MedicalGenerate.mcq(
                        sourceText: text, count: count, subject: subj,
                        highYield: hy, using: writer, onProgress: progress)
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
                var checkNote = ""
                if let checker {
                    let screened = await AccuracyChecker.screen(
                        questions, source: text, using: checker,
                        onProgress: { done, total in
                            Task { @MainActor in
                                generationStatus = "Checking \(done) of \(total) with \(checker.label)\u{2026}"
                            }
                        })
                    questions = screened.kept
                    if screened.removed > 0 { checkNote += " \(screened.removed) removed as high risk." }
                    if screened.flagged > 0 { checkNote += " \(screened.flagged) flagged moderate risk \u{2014} check them." }
                }
                guard !questions.isEmpty else {
                    throw LLMError.notReady("The checker graded every question high risk \u{2014} try a clearer source.")
                }
                let finalQuestions = questions
                let note = checkNote
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Done \u{2014} \(finalQuestions.count) question(s) written." + note
                    var set = StudySet(
                        name: setName.isEmpty
                            ? (subj.isEmpty || subj == "General" ? "Generated set" : subj)
                            : setName,
                        subject: subj.isEmpty ? "General" : subj, kind: .mcq)
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
}
