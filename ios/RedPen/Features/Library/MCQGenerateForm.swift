import SwiftUI
import UniformTypeIdentifiers

/// The "generate a set from my material" half of New set.
///
/// Split out of NewSetView because it is now the larger half: it owns the
/// choice of on-device model, the download of the fallback one, and - new here
/// - reading the lecture out of the PDF instead of asking the student to paste
/// forty pages by hand, which is the step the web app had and the app did not.
struct MCQGenerateForm: View {
    @EnvironmentObject var gemma: GemmaModel

    @Binding var sourceText: String
    @Binding var questionCount: Int
    @Binding var highYield: Bool
    let name: String
    let subject: String
    let onGenerated: (StudySet) -> Void

    @State private var isGenerating = false
    @State private var generationStatus: String?
    @State private var generationTask: Task<Void, Never>?

    @State private var pickingPDF = false
    @State private var reading = false
    @State private var readStatus: String?

    private enum Backend: Equatable { case apple, gemma }
    /// Which backend a tap on Generate would actually use. `nil` means neither
    /// is ready, and the UI says why rather than offering a button that fails.
    private var activeBackend: Backend? {
        if MCQGenerator.availability.isAvailable { return .apple }
        if gemma.status == .ready { return .gemma }
        return nil
    }

    var body: some View {
        Group {
            Section {
                Button {
                    pickingPDF = true
                } label: {
                    HStack {
                        if reading { ProgressView().controlSize(.small) }
                        Label(reading ? "Reading the PDF\u{2026}" : "Read a lecture PDF",
                              systemImage: "doc.text.viewfinder")
                    }
                }
                .disabled(reading || isGenerating)
                if let readStatus {
                    Text(readStatus).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("From a file")
            } footer: {
                Text("Slides and handouts are read on this phone. A scanned page is read by OCR, in Arabic or English.")
            }

            Section {
                Text("One question per line: Stem | OptA; OptB; OptC; OptD | correctLetter | Explanation")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $sourceText)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .disabled(isGenerating)
            } header: {
                Text("Paste your notes")
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
                if activeBackend == .gemma {
                    Text("Using the downloaded Gemma 4 E2B model \u{2014} on-device, nothing sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    startGenerating()
                } label: {
                    HStack {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Text(isGenerating ? (generationStatus ?? "Writing\u{2026}") : "Generate questions")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isGenerating || activeBackend == nil
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
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            Task { await readPDF(result) }
        }
        .onAppear { gemma.refreshStatus() }
        .onDisappear { generationTask?.cancel() }
    }

    /// Apple's on-device model is tried first; this only appears when that is
    /// unavailable, offering the Gemma download as a fallback that still never
    /// touches anyone's account.
    @ViewBuilder
    private var backendSection: some View {
        if !MCQGenerator.availability.isAvailable {
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

    // MARK: reading the file

    private func readPDF(_ result: Result<URL, Error>) async {
        switch result {
        case .failure(let error):
            readStatus = error.localizedDescription
        case .success(let url):
            reading = true
            readStatus = nil
            do {
                let read = try await SourceIngest.read(pdf: url)
                let document = read.document
                // appended rather than replacing: a student who pasted notes and
                // then adds the slides means both, and silently discarding what
                // they typed would be unforgivable
                let existing = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                sourceText = existing.isEmpty ? document.text : existing + "\n\n" + document.text
                let ocr = document.recognisedPages
                readStatus = "Read \(document.pages.count) page\(document.pages.count == 1 ? "" : "s")"
                    + (ocr > 0 ? ", \(ocr) by OCR" : "")
                    + ". Check anything that looks garbled before generating."
            } catch {
                readStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            reading = false
        }
    }

    // MARK: generating

    private func startGenerating() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let backend = activeBackend else { return }
        isGenerating = true
        generationStatus = "Writing 0 of \(questionCount) questions\u{2026}"
        let count = questionCount, subj = subject, hy = highYield, setName = name
        generationTask = Task {
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    Task { @MainActor in
                        generationStatus = "Writing \(done) of \(total) questions\u{2026}"
                    }
                }
                let questions: [MCQQuestion]
                switch backend {
                case .apple:
                    questions = try await MCQGenerator.generate(
                        sourceText: text, count: count, subject: subj,
                        highYield: hy, onProgress: progress)
                case .gemma:
                    questions = try await gemma.generate(
                        sourceText: text, count: count, subject: subj,
                        highYield: hy, onProgress: progress)
                }
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Done \u{2014} \(questions.count) question(s) written."
                    var set = StudySet(
                        name: setName.isEmpty
                            ? (subj.isEmpty || subj == "General" ? "Generated set" : subj)
                            : setName,
                        subject: subj.isEmpty ? "General" : subj, kind: .mcq)
                    set.questions = questions
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
