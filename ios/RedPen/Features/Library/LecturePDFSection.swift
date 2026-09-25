import SwiftUI
import UniformTypeIdentifiers

/// What a file gave us, kept so that questions generated later can be cited
/// back to the page they came from.
struct ReadSource: Equatable {
    var name: String
    var document: SourceText.Document
    var kind: SourceDoc.Kind = .pdf
    /// The hash of the original file, if it was kept. Absent is normal - a
    /// device short of space, or a file that could not be copied - and only
    /// means the preview falls back to the text.
    var fileBlob: String?

    /// The keepable form of what was read, to store on the set.
    ///
    /// Blank pages are kept rather than dropped. A lecture's page nine being
    /// empty is a fact about the lecture, and renumbering around it would make
    /// every citation after it point one page short.
    func doc() -> SourceDoc {
        SourceDoc(name: name, kind: kind,
                  pages: document.pages.map {
                      SourceDoc.Page(number: $0.number, text: $0.text,
                                     recognised: $0.recognised)
                  },
                  fileBlob: fileBlob)
    }
}

/// Reading the lecture out of the file the lecturer handed out.
///
/// Three things come back from one pass. The TEXT is appended to whatever the
/// student has already pasted. The COUNT is a proposal - a forty-page lecture
/// cannot be covered by the ten questions the form defaults to, and nobody
/// knows that until the file has been read. The DIAGRAMS are something the text
/// route cannot produce at all: a labelled figure already carries its own
/// answers, so each label becomes an occlusion card without a model being asked
/// anything. That deck is offered separately rather than mixed into the
/// questions, because it is a different way of studying.
struct LecturePDFSection: View {
    @Binding var sourceText: String
    @Binding var questionCount: Int
    @Binding var readSource: ReadSource?
    let disabled: Bool
    let name: String
    let subject: String
    /// Whether to draw anything. New set keeps this section alive on every
    /// step so the diagrams it found survive, and shows it only on step 2.
    var visible: Bool = true
    let onOcclusionSet: (StudySet) -> Void

    @State private var picking = false
    @State private var reading = false
    @State private var status: String?
    @State private var cards: [AnkiCard] = []
    @State private var images: [String] = []
    @State private var diagramTask: Task<Void, Never>?
    @State private var diagramProgress: String?
    /// Which diagram scan is current. A scan that has been replaced by a
    /// newer file's may still report a page or finish before it notices it
    /// was cancelled, and must not write over the newer one's progress.
    @State private var diagramRun = 0
    /// Asking first: the picture cards are saved as their own set, and New
    /// set closes.
    @State private var confirmingPictures = false

    /// Office files are zips, and a zip is not a type the picker offers by
    /// name, so Word's and PowerPoint's own identifiers are asked for directly.
    /// A system that does not know one simply offers the others.
    /// What kind of document this is, by its extension.
    ///
    /// The extension rather than the picker's type, because a file that arrived
    /// through Files, AirDrop or a shared folder may carry no useful type at
    /// all, and the extension is the one thing that survives every route in.
    static func kind(of url: URL) -> SourceDoc.Kind {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "docx", "doc": return .word
        case "pptx", "ppt": return .powerpoint
        default: return .text
        }
    }

    private var readableTypes: [UTType] {
        [.pdf,
         UTType("org.openxmlformats.wordprocessingml.document"),
         UTType("org.openxmlformats.presentationml.presentation")].compactMap { $0 }
    }

    var body: some View {
        Group {
            if visible { fileSection }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: readableTypes) { result in
            // held by FileReads, so closing New set stops the reading
            FileReads.run { await read(result) }
        }
    }

    private var fileSection: some View {
        Section {
            // raised, but second to the dock's Next
            Button { picking = true } label: {
                HStack {
                    if reading { ProgressView().controlSize(.small) }
                    Label(pickTitle, systemImage: "doc.badge.plus")
                }
            }
            .buttonStyle(.bigSecondary)
            .disabled(reading || disabled)
            .frame(maxWidth: .infinity)

            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            if let diagramProgress {
                Label(diagramProgress, systemImage: "photo.on.rectangle.angled")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !cards.isEmpty {
                Button { confirmingPictures = true } label: {
                    Label(picturesTitle, systemImage: "rectangle.dashed")
                }
                .disabled(disabled)
                .confirmationDialog(picturesTitle, isPresented: $confirmingPictures,
                                    titleVisibility: .visible) {
                    Button(picturesConfirm) { makeOcclusionSet() }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text("They are saved as a Cards set of their own, and New set closes. Make the questions first if you want those too.")
                }
                Text("One card per label on the diagrams, masking the label itself. Nothing was generated \u{2014} the labels are the slide's own words.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Add a file")
        } footer: {
            Text("PDF, Word or PowerPoint. It is read on this device, scanned pages too.")
        }
    }

    private var picturesTitle: String {
        let found: Int = cards.count
        let plural: String = found == 1 ? "" : "s"
        return "Also make \(found) picture card\(plural) from the diagrams"
    }

    private var picturesConfirm: String {
        let found: Int = cards.count
        let plural: String = found == 1 ? "" : "s"
        return "Save \(found) picture card\(plural) and close"
    }

    /// The file button: what it does now.
    private var pickTitle: String {
        if reading { return "Reading the file\u{2026}" }
        if readSource == nil { return "Choose a lecture file" }
        return "Add another file"
    }

    private func read(_ result: Result<URL, Error>) async {
        switch result {
        case .failure(let error):
            status = error.localizedDescription
        case .success(let url):
            reading = true
            status = nil
            cards = []
            images = []
            // the previous file's diagram scan is over whether or not this
            // file reads: its cards would belong to a different lecture
            stopDiagrams()
            do {
                let isPDF = url.pathExtension.lowercased() == "pdf"
                // the text first, which is almost instant; the diagrams are
                // looked for afterwards in the background (findDiagrams)
                let read = isPDF ? try await SourceIngest.read(pdf: url, findingFigures: false)
                                 : try await OfficeIngest.read(url, findingFigures: false)
                let document = read.document
                let fileName = url.deletingPathExtension().lastPathComponent
                // appended rather than replacing: a student who pasted notes and
                // then adds the slides means both, and silently discarding what
                // they typed would be unforgivable
                let existing = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                let joined: String = existing + "\n\n" + document.text
                sourceText = existing.isEmpty ? document.text : joined
                // The file itself is kept on this device so the preview can show
                // the real pages, diagrams and all. It is not synced - see
                // SourceFiles - so the text above is what travels.
                let kind = Self.kind(of: url)
                readSource = ReadSource(name: fileName, document: document, kind: kind,
                                        fileBlob: await SourceFiles.keeping(url, kind: kind))
                findDiagrams(in: url, pdf: isPDF)

                // proposed, not imposed: the stepper still moves, and a student
                // who wants a quick ten-question run can say so
                questionCount = min(MCQGenerator.maxQuestionsTotal,
                                    MCQCoverage.suggestedCount(forCharacters: sourceText.count))

                status = summary(pages: document.pages.count,
                                 ocr: document.recognisedPages)
            } catch is CancellationError {
                // New set closed: nobody is waiting for this file any more
            } catch {
                status = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            reading = false
        }
    }

    /// Labelled diagrams, looked for while the student carries on: several
    /// slides at a time, off the main thread, with the count shown.
    ///
    /// The scan is awaited inside a task FileReads holds rather than run
    /// detached. A detached task does not hear its parent being cancelled, so
    /// picking another file or closing New set used to leave the old scan
    /// rendering and OCRing every page beside the new one.
    private func findDiagrams(in url: URL, pdf: Bool) {
        stopDiagrams()
        let run = diagramRun
        diagramProgress = "Finding diagrams\u{2026}"
        diagramTask = FileReads.run {
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
            // a scan that was replaced leaves the label to the one that
            // replaced it; one that was only cancelled clears its own
            guard diagramRun == run else { return }
            diagramProgress = nil
            guard !Task.isCancelled, let read else { return }
            keepFigures(read)
        }
    }

    /// Cancels the diagram scan running, if any, and takes its label down.
    private func stopDiagrams() {
        diagramTask?.cancel()
        diagramTask = nil
        diagramRun += 1
        diagramProgress = nil
    }

    private func summary(pages: Int, ocr: Int) -> String {
        let pagePlural: String = pages == 1 ? "" : "s"
        let read: String = "Read \(pages) page\(pagePlural)"
        let recognised: String = ocr > 0 ? ", \(ocr) by OCR" : ""
        let figureCount: Int = images.count
        let figurePlural: String = figureCount == 1 ? "" : "s"
        let figures: String = cards.isEmpty ? "" : ", \(figureCount) labelled diagram\(figurePlural)"
        let advice: String = ". \(questionCount) questions suits this much material."
        return read + recognised + figures + advice
    }

    /// Shrink the figures for storage, and renumber the cards as we go.
    ///
    /// A card points at an image by position, so an image that fails to encode
    /// must not simply be skipped - that would silently slide every later card
    /// onto the wrong diagram.
    private func keepFigures(_ read: SourceIngest.Result) {
        var moved: [Int: Int] = [:]
        for (old, figure) in read.figures.enumerated() {
            guard let data = SourceIngest.downsized(figure) else { continue }
            moved[old] = images.count
            images.append(data.base64EncodedString())
        }
        cards = read.occlusionCards.compactMap { card in
            guard let old = card.imageIndex, let new = moved[old] else { return nil }
            var renumbered = card
            renumbered.imageIndex = new
            return renumbered
        }
    }

    private func makeOcclusionSet() {
        let plainSubject: Bool = subject.isEmpty || subject == "General"
        let fromSubject: String = plainSubject ? "Diagrams" : subject + " diagrams"
        let title: String = name.isEmpty ? fromSubject : name + " diagrams"
        let setSubject: String = subject.isEmpty ? "General" : subject
        var set = StudySet(name: title, subject: setSubject, kind: .anki)
        set.cards = cards
        set.images = images
        // The diagrams came off the same lecture, so it travels with them too:
        // an occlusion card is exactly the kind that sends you back to the
        // slide to see the whole figure.
        if let readSource { set.sources = [readSource.doc()] }
        onOcclusionSet(set)
    }
}
