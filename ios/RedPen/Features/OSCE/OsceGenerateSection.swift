import SwiftUI
import UniformTypeIdentifiers

/// Writing stations from a lecture, for the new-set screen.
///
/// The result is written into the text box rather than straight into a set.
/// That is deliberate: a checklist written by a model is a draft, and the
/// person who knows whether "auscultate in four areas" was taught as one step
/// or four is the student who sat the teaching. They edit, then create.
///
/// Its own file because SwiftUI type-checks a whole view as one expression, and
/// the new-set screen is already long enough to have been split once.
struct OsceGenerateSection: View {
    @Binding var bodyText: String
    /// Kept by New set; asked for here, under More options.
    @Binding var subject: String
    /// Which step of New set is showing: the file in step 2, the count and
    /// the Make button in step 3, nothing in step 1. The section stays in
    /// the view throughout, so the file it read survives the steps.
    let step: NewSetStep
    /// Material to start from, when a set is being turned into stations: read
    /// already, as if its file had just been opened.
    var presetText: String = ""
    var presetName: String = ""
    @EnvironmentObject private var llm: LocalLLMService
    /// The New set this is in: closing it stops what this started, and only that.
    @Environment(\.generationOwner) private var generationOwner

    @State private var picking = false
    @State private var working = false
    @State private var status: String?
    @State private var trouble: String?
    @State private var sourceText = ""
    @State private var sourceName = ""
    @State private var stationCount = 3
    @State private var task: Task<Void, Never>?
    @State private var showMore = false

    private var readableTypes: [UTType] {
        [.pdf,
         UTType("org.openxmlformats.wordprocessingml.document"),
         UTType("org.openxmlformats.presentationml.presentation")].compactMap { $0 }
    }

    private var canGenerate: Bool {
        !working && sourceText.trimmingCharacters(in: .whitespacesAndNewlines).count > 200
    }

    var body: some View {
        Group {
            if step == .material { addSection }
            if step == .make { makeSection }
        }
        // only once a file is read is there a button to float
        .floatingAction(id: sourceName.isEmpty ? "osce-unread" : "osce", title: makeTitle,
                        enabled: canGenerate, inputs: [subject, String(sourceText.count)], run: start)
        .fileImporter(isPresented: $picking, allowedContentTypes: readableTypes,
                      allowsMultipleSelection: false) { result in
            // held by FileReads, so closing New set stops the reading
            FileReads.run { await read(result) }
        }
        .onAppear {
            guard sourceName.isEmpty, !presetText.isEmpty else { return }
            sourceText = presetText
            sourceName = presetName.isEmpty ? "This set" : presetName
            if !canGenerate {
                trouble = "There is not much in this set to write stations from."
            }
        }
    }

    /// Step 2: the skills lecture or mark sheet.
    private var addSection: some View {
        Section {
            // raised, but second to the dock's Next
            Button { picking = true } label: {
                Label(pickTitle, systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bigSecondary)
            .disabled(working)
            .frame(maxWidth: .infinity)
            if !sourceName.isEmpty {
                Label(sourceName, systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            messages
        } header: {
            Text("Add a file")
        } footer: {
            Text("PDF, Word or PowerPoint. A skills lecture or a mark sheet works best.")
        }
    }

    /// Step 3: how many stations, the one big button, and More options.
    private var makeSection: some View {
        Section {
            if sourceName.isEmpty {
                Text("Nothing to write from yet \u{2014} go Back and add a file.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                CountField(title: "How many stations", value: $stationCount,
                           range: 1...OsceGenerator.maxStationsTotal)
                    .disabled(working)
                // stopping is the progress card's Cancel, at the bottom, so
                // this never turns into a second Stop
                // the hero slab, the same as its floating copy in the dock
                Button { start() } label: {
                    HStack {
                        if working { ProgressView().controlSize(.small) }
                        Label(makeTitle, systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bigPrimary)
                .disabled(!canGenerate)
                .frame(maxWidth: .infinity)
                .floatingActionAnchor("osce")
            }
            messages
            DisclosureGroup("More options", isExpanded: $showMore) {
                TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                    .popField()
                    .disabled(working)
            }
        } footer: {
            Text("The stations appear below to check before you save the set.")
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let status {
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        if let trouble {
            Text(trouble).font(.caption).foregroundStyle(.red)
        }
    }

    private var pickTitle: String {
        if sourceName.isEmpty { return "Choose a skills lecture or mark sheet" }
        return "Choose a different file"
    }

    private var makeTitle: String {
        let plural: String = stationCount == 1 ? "" : "s"
        return "Make \(stationCount) station" + plural
    }

    private func read(_ result: Result<[URL], Error>) async {
        trouble = nil
        guard let url = (try? result.get())?.first else {
            if case .failure(let error) = result { trouble = error.localizedDescription }
            return
        }
        working = true
        status = "Reading\u{2026}"
        defer { working = false }
        do {
            let isPDF = url.pathExtension.lowercased() == "pdf"
            // No figures: a station comes out of the words, and rendering every
            // page to hunt for diagrams is the slow half of reading a file.
            let read = isPDF ? try await SourceIngest.read(pdf: url, findingFigures: false)
                             : try await OfficeIngest.read(url, findingFigures: false)
            sourceText = read.document.text
            sourceName = url.deletingPathExtension().lastPathComponent
            let pages: Int = read.document.pages.count
            status = "\(sourceName) \u{2014} \(pages) pages."
            if !canGenerate {
                trouble = "There is not much text in that file to work from."
            }
        } catch is CancellationError {
            // New set closed: nobody is waiting for this file any more
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    private func start() {
        trouble = nil
        // something else is being written: said here, and left running
        if let busy = GenerationCenter.shared.busy {
            trouble = busy
            return
        }
        working = true
        let wanted = stationCount, subj = subject, text = sourceText
        status = "Writing 0 of \(wanted)\u{2026}"
        // a writer chosen in AI models goes first; otherwise Apple's model
        let writer = llm.backend(for: .writer)
        // the verification layer checks what is made (VerificationScreen now,
        // the independent checkers once the set is saved)
        let verify: Bool = llm.checkGenerated
        let plural: String = wanted == 1 ? "" : "s"
        let jobTitle: String = "Writing \(wanted) station\(plural)"
        // A cloud job's replies stay kept - on this device and on the
        // server - until this generation is done with them, however it
        // ends: an app closed while they are checked or saved finds them
        // again on its next launch (CloudJobs.Delivery). Made before the
        // card, which tells it when the system stopped the generation.
        let delivery = CloudJobs.Delivery()
        guard let job = GenerationCenter.shared.begin(jobTitle, total: wanted, owner: generationOwner,
                                                      keeping: delivery, onCancel: {
            task?.cancel()
            task = nil
            working = false
            status = "Cancelled."
        }) else {
            working = false
            status = nil
            trouble = GenerationCenter.shared.busy
            return
        }
        task = Task {
            defer { CloudJobs.finish(delivery) }
            do {
                let progress: (Int, Int) -> Void = { done, total in
                    GenerationCenter.shared.update(job, done: done, total: total)
                    Task { @MainActor in status = "Writing \(done) of \(total)\u{2026}" }
                }
                var stations: [OsceChecklist]
                if let writer {
                    let recipe = CloudRecipe(kind: .osce, name: "", subject: subj, count: wanted, source: nil,
                                             check: nil).encoded
                    stations = try await CloudJobs.$context.withValue(CloudJobs.Context(recipe: recipe, serverCheck: false,
                                                               checking: { done, total in
                        Task { @MainActor in GenerationCenter.shared.update(job, done: done, total: total, phase: "Checking accuracy in the cloud") }
                    }, delivery: delivery)) {
                        try await MedicalGenerate.osce(
                            sourceText: text, count: wanted, subject: subj,
                            using: writer, onProgress: progress)
                    }
                } else {
                    stations = try await OsceGenerator.generate(
                        sourceText: text, count: wanted, subject: subj, onProgress: progress)
                }
                try Task.checkCancellation()
                var checkNote = ""
                if verify {
                    let screened = VerificationScreen.stations(stations)
                    stations = screened.kept
                    checkNote = VerificationScreen.note(screened)
                }
                guard !stations.isEmpty else { throw OsceGenerator.Trouble.nothingUsable }
                let finalStations = stations
                let note = checkNote
                try Task.checkCancellation()
                let made: Int = finalStations.count
                let verb: String = made == 1 ? " is" : "s are"
                let madePlural: String = made == 1 ? "" : "s"
                let finished: String = "Your \(made) OSCE station\(verb) ready"
                let done: String = "\(made) station\(madePlural) written \u{2014} check them below."
                await MainActor.run {
                    GenerationCenter.shared.end(job, finished: finished)
                    working = false
                    let written = OsceStations.format(finalStations)
                    // Appended, never replacing: a student who typed a station
                    // and then generated more means both.
                    let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let joined: String = existing + "\n\n" + written
                    bodyText = existing.isEmpty ? written : joined
                    status = done + note
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
                    trouble = (error as? LocalizedError)?.errorDescription
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
