import SwiftUI
import UniformTypeIdentifiers

/// New set, for Cases: the lecture in step 2, how many patients and Make in
/// step 3. The cases are written, checked and saved as a set in one go - a
/// case is not a draft to edit line by line - and the lecture goes with the
/// set, so the teaching points can be checked against it.
struct CaseMakeSection: View {
    @Binding var subject: String
    let name: String
    let step: NewSetStep
    /// Material to start from, when a set is being turned into cases.
    var presetText: String = ""
    var presetName: String = ""
    let onMade: (StudySet) -> Void

    @EnvironmentObject private var llm: LocalLLMService
    @EnvironmentObject private var gemma: GemmaModel
    @Environment(\.generationOwner) private var generationOwner

    @State private var picking = false
    @State private var working = false
    @State private var status: String?
    @State private var trouble: String?
    @State private var read: ReadSource?
    @State private var caseCount = 3
    @State private var task: Task<Void, Never>?
    @State private var showMore = false

    private var readableTypes: [UTType] {
        [.pdf,
         UTType("org.openxmlformats.wordprocessingml.document"),
         UTType("org.openxmlformats.presentationml.presentation")].compactMap { $0 }
    }

    private var sourceText: String {
        guard let read else { return presetText }
        return CaseMaker.sourceText(read.document.pages.map { (number: $0.number, text: $0.text) })
    }

    private var sourceName: String {
        read?.name ?? (presetText.isEmpty ? "" : (presetName.isEmpty ? "This set" : presetName))
    }

    private var canMake: Bool {
        !working && sourceText.trimmingCharacters(in: .whitespacesAndNewlines).count > 200
    }

    var body: some View {
        Group {
            if step == .material { addSection }
            if step == .make { makeSection }
        }
        .floatingAction(id: sourceName.isEmpty ? "cases-unread" : "cases", title: makeTitle,
                        enabled: canMake, inputs: [subject, String(sourceText.count)], run: start)
        .fileImporter(isPresented: $picking, allowedContentTypes: readableTypes,
                      allowsMultipleSelection: false) { result in
            FileReads.run { await readFile(result) }
        }
    }

    private var addSection: some View {
        Section {
            Button { picking = true } label: {
                Label(sourceName.isEmpty ? "Choose a lecture" : "Choose a different lecture",
                      systemImage: "doc.badge.plus")
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
            Text("Add a lecture")
        } footer: {
            Text("PDF, Word or PowerPoint. A lecture on a condition - how it presents, what the tests show, how it is treated - makes the best patients.")
        }
    }

    private var makeSection: some View {
        Section {
            if sourceName.isEmpty {
                Text("Nothing to write from yet \u{2014} go Back and add a lecture.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                CountField(title: "How many patients", value: $caseCount, range: 1...CaseWriting.maxCases)
                    .disabled(working)
                Button { start() } label: {
                    HStack {
                        if working { ProgressView().controlSize(.small) }
                        Label(makeTitle, systemImage: "stethoscope")
                    }
                }
                .buttonStyle(.bigPrimary)
                .disabled(!canMake)
                .frame(maxWidth: .infinity)
                .floatingActionAnchor("cases")
            }
            messages
            DisclosureGroup("More options", isExpanded: $showMore) {
                TextField("Subject", text: $subject, prompt: Text("Subject, e.g. Cardiology"))
                    .popField()
                    .disabled(working)
            }
        } footer: {
            Text("Each patient is checked for its structure and its numbers before it is kept, and by the accuracy checkers once the set is saved.")
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

    private var makeTitle: String {
        "Make \(caseCount) patient" + (caseCount == 1 ? "" : "s")
    }

    private func readFile(_ result: Result<[URL], Error>) async {
        trouble = nil
        guard let url = (try? result.get())?.first else {
            if case .failure(let error) = result { trouble = error.localizedDescription }
            return
        }
        working = true
        status = "Reading\u{2026}"
        defer { working = false }
        do {
            let ext: String = url.pathExtension.lowercased()
            let isPDF: Bool = ext == "pdf"
            let ingested = isPDF ? try await SourceIngest.read(pdf: url, findingFigures: false)
                                 : try await OfficeIngest.read(url, findingFigures: false)
            let kind: SourceDoc.Kind = isPDF ? .pdf : (ext == "pptx" ? .powerpoint : .word)
            let named: String = url.deletingPathExtension().lastPathComponent
            read = ReadSource(name: named, document: ingested.document, kind: kind)
            status = "\(named) \u{2014} \(ingested.document.pages.count) pages."
            if !canMake { trouble = "There is not much text in that file to write patients from." }
        } catch is CancellationError {
            // New set closed: nobody is waiting for this file any more
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    private func start() {
        trouble = nil
        if let busy = GenerationCenter.shared.busy {
            trouble = busy
            return
        }
        guard let writer = CaseMaker.writer(llm: llm, gemma: gemma) else {
            trouble = CaseMaker.noWriter(gemma: gemma)
            return
        }
        working = true
        let wanted: Int = caseCount
        let subj: String = subject
        let text: String = sourceText
        let lecture: String = sourceName
        let doc: SourceDoc? = read?.doc()
        let setName: String = name.trimmingCharacters(in: .whitespaces).isEmpty ? (lecture.isEmpty ? "Cases" : lecture) : name
        status = "Writing 0 of \(wanted)\u{2026}"
        let delivery = CloudJobs.Delivery()
        guard let job = GenerationCenter.shared.begin("Writing \(wanted) patient\(wanted == 1 ? "" : "s")", total: wanted,
                                                      owner: generationOwner, keeping: delivery, onCancel: {
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
                // kept with a cloud job, so the set is still made if the app
                // is closed before the server finishes (CloudJobCollector)
                let recipe = CloudRecipe(kind: .cases, name: setName, subject: subj, count: wanted, source: doc,
                                         check: nil).encoded
                let made: CaseMaker.Made = try await CloudJobs.$context.withValue(
                    CloudJobs.Context(recipe: recipe, serverCheck: false, checking: nil, delivery: delivery)) {
                    try await CaseMaker.write(count: wanted, source: text, lecture: lecture, subject: subj,
                                              using: writer, onProgress: progress)
                }
                try Task.checkCancellation()
                var set = StudySet(name: setName, subject: subj.isEmpty ? "General" : subj, kind: .cases)
                set.caseFiles = made.cases
                if let doc { set.sources = [doc] }
                let count: Int = made.cases.count
                let note: String = CaseChecks.note(kept: count, dropped: made.dropped)
                let finished: StudySet = set
                await MainActor.run {
                    GenerationCenter.shared.end(job, finished: "Your \(count) patient\(count == 1 ? " is" : "s are") ready")
                    working = false
                    status = "\(count) written." + note
                    onMade(finished)
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
