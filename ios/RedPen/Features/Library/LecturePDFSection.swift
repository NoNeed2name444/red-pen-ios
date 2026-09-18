import SwiftUI
import UniformTypeIdentifiers

/// Reading the lecture out of the file the lecturer handed out.
///
/// Three things come back from one pass, and they are worth keeping apart. The
/// TEXT is appended to whatever the student has already pasted. The COUNT is a
/// proposal - a forty-page lecture cannot be covered by the ten questions the
/// form defaults to, and nobody knows that until the file has been read. The
/// DIAGRAMS are something the text route cannot produce at all: a labelled
/// figure already carries its own answers, so each label becomes an occlusion
/// card without a model being asked anything. That deck is offered separately
/// rather than mixed into the questions, because it is a different way of
/// studying and the student should choose it deliberately.
struct LecturePDFSection: View {
    @Binding var sourceText: String
    @Binding var questionCount: Int
    let disabled: Bool
    let name: String
    let subject: String
    let onOcclusionSet: (StudySet) -> Void

    @State private var picking = false
    @State private var reading = false
    @State private var status: String?
    @State private var cards: [AnkiCard] = []
    @State private var images: [String] = []

    /// A .docx is a zip, and a zip is not a type the picker offers by name, so
    /// Word's own identifier is asked for directly. If the system does not know
    /// it, the picker simply offers PDFs rather than failing to open.
    private var readableTypes: [UTType] {
        [.pdf, UTType("org.openxmlformats.wordprocessingml.document")].compactMap { $0 }
    }

    var body: some View {
        Section {
            Button { picking = true } label: {
                HStack {
                    if reading { ProgressView().controlSize(.small) }
                    Label(reading ? "Reading the file\u{2026}" : "Read a lecture file",
                          systemImage: "doc.text.viewfinder")
                }
            }
            .disabled(reading || disabled)

            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            if !cards.isEmpty {
                Button {
                    makeOcclusionSet()
                } label: {
                    Label("Make an image-occlusion deck (\(cards.count) card\(cards.count == 1 ? "" : "s"))",
                          systemImage: "rectangle.dashed")
                }
                .disabled(disabled)
                Text("One card per label on the diagrams, masking the label itself. Nothing was generated \u{2014} the labels are the slide's own words.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("From a file")
        } footer: {
            Text("PDF slides and Word handouts are read on this phone. A scanned page is read by OCR, in Arabic or English.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: readableTypes) { result in
            Task { await read(result) }
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
                let isWord = url.pathExtension.lowercased().hasPrefix("doc")
                let read = isWord ? try await DocxIngest.read(docx: url)
                                  : try await SourceIngest.read(pdf: url)
                let document = read.document
                // appended rather than replacing: a student who pasted notes and
                // then adds the slides means both, and silently discarding what
                // they typed would be unforgivable
                let existing = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                sourceText = existing.isEmpty ? document.text
                                              : existing + "\n\n" + document.text
                keepFigures(read)

                // proposed, not imposed: the stepper still moves, and a student
                // who wants a quick ten-question run can say so
                let suggested = MCQCoverage.suggestedCount(forCharacters: sourceText.count)
                questionCount = min(MCQGenerator.maxQuestionsTotal, suggested)

                let ocr = document.recognisedPages
                let pages = document.pages.count
                status = (isWord ? "Read the handout"
                                 : "Read \(pages) page\(pages == 1 ? "" : "s")")
                    + (ocr > 0 ? ", \(ocr) by OCR" : "")
                    + (cards.isEmpty ? "" : ", \(images.count) labelled diagram\(images.count == 1 ? "" : "s")")
                    + ". Set to \(questionCount) questions \u{2014} about what this much material can cover without repeating itself. Check anything garbled before generating."
            } catch {
                status = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            reading = false
        }
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
        onOcclusionSet(set)
    }
}
