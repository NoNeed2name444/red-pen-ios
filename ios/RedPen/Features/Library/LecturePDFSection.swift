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
            Task { await read(result) }
        }
    }

    private var fileSection: some View {
        Section {
            Button { picking = true } label: {
                HStack {
                    if reading { ProgressView().controlSize(.small) }
                    Label(reading ? "Reading the file\u{2026}" : (readSource == nil ? "Choose a lecture file" : "Add another file"),
                          systemImage: "doc.badge.plus")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(reading || disabled)

            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            if let diagramProgress {
                Label(diagramProgress, systemImage: "photo.on.rectangle.angled")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !cards.isEmpty {
                Button { makeOcclusionSet() } label: {
                    Label("Also make \(cards.count) picture card\(cards.count == 1 ? "" : "s") from the diagrams",
                          systemImage: "rectangle.dashed")
                }
                .disabled(disabled)
                Text("One card per label on the diagrams, masking the label itself. Nothing was generated \u{2014} the labels are the slide's own words.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Add a file")
        } footer: {
            Text("PDF, Word or PowerPoint. It is read on this phone, scanned pages too.")
        }
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
                sourceText = existing.isEmpty ? document.text
                                              : existing + "\n\n" + document.text
                // The file itself is kept on this device so the preview can show
                // the real pages, diagrams and all. It is not synced - see
                // SourceFiles - so the text above is what travels.
                let kind = Self.kind(of: url)
                readSource = ReadSource(name: fileName, document: document, kind: kind,
                                        fileBlob: SourceFiles.keep(url, kind: kind))
                findDiagrams(in: url, pdf: isPDF)

                // proposed, not imposed: the stepper still moves, and a student
                // who wants a quick ten-question run can say so
                questionCount = min(MCQGenerator.maxQuestionsTotal,
                                    MCQCoverage.suggestedCount(forCharacters: sourceText.count))

                status = summary(pages: document.pages.count,
                                 ocr: document.recognisedPages)
            } catch {
                status = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            reading = false
        }
    }

    /// Labelled diagrams, looked for while the student carries on: several
    /// slides at a time, off the main thread, with the count shown.
    private func findDiagrams(in url: URL, pdf: Bool) {
        diagramTask?.cancel()
        diagramProgress = "Finding diagrams\u{2026}"
        diagramTask = Task {
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
            if let read { keepFigures(read) }
            diagramProgress = nil
        }
    }

    private func summary(pages: Int, ocr: Int) -> String {
        "Read \(pages) page\(pages == 1 ? "" : "s")"
            + (ocr > 0 ? ", \(ocr) by OCR" : "")
            + (cards.isEmpty ? "" : ", \(images.count) labelled diagram\(images.count == 1 ? "" : "s")")
            + ". \(questionCount) questions suits this much material."
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
        var set = StudySet(
            name: name.isEmpty ? (subject.isEmpty || subject == "General"
                                  ? "Diagrams" : subject + " diagrams")
                               : name + " diagrams",
            subject: subject.isEmpty ? "General" : subject, kind: .anki)
        set.cards = cards
        set.images = images
        // The diagrams came off the same lecture, so it travels with them too:
        // an occlusion card is exactly the kind that sends you back to the
        // slide to see the whole figure.
        if let readSource { set.sources = [readSource.doc()] }
        onOcclusionSet(set)
    }
}
