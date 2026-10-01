import SwiftUI
import PDFKit

/// One page, and what came off it.
///
/// Two ways of showing the same page. If this device still has the file, the
/// page is rendered - which for a lecture full of diagrams is the whole point,
/// because the extracted text of an anatomy slide is a list of labels with the
/// picture missing. Otherwise the text is laid out to be read.
///
/// Underneath either, the cards this page produced. That is the connection
/// worth making: a card that makes no sense and the slide it came from, on one
/// screen.
///
/// Moving between pages is the reader's pager, at the bottom under the
/// thumb (ReaderBar), or the page list.
struct SourcePageReader: View {
    let source: SourceDoc
    @Binding var page: Int
    var set: StudySet?
    var file: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let file, source.kind == .pdf {
                    SourcePDFPage(url: file, page: page)
                        .frame(minHeight: 420)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                text
                cards
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var current: SourceDoc.Page? { source.page(page) }

    @ViewBuilder
    private var text: some View {
        if let current {
            if current.isBlank {
                Label("No text on this \(source.kind.pageNoun.lowercased())",
                      systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if current.recognised {
                    Label("Read by text recognition — worth checking against the original",
                          systemImage: "text.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LecturePassageText(text: current.text, page: page)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Cards whose citation points at this page.
    private var fromHere: [String] {
        guard let set else { return [] }
        let labels = set.cards.compactMap(\.source) + set.questions.compactMap(\.source)
        return labels.enumerated().compactMap { _, label in
            Citation.read(label)?.page == page ? label : nil
        }
    }

    @ViewBuilder
    private var cards: some View {
        let mine = fromHere
        if !mine.isEmpty {
            let found: Int = mine.count
            let noun: String = found == 1 ? "card" : "cards"
            let place: String = source.kind.pageNoun.lowercased()
            let line: String = "\(found) \(noun) from this \(place)"
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(line)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One rendered page of a PDF.
///
/// A PDFView rather than a rendered image so that pinching to zoom, and
/// selecting text off the page itself, work the way they do everywhere else.
/// Locked to a single page: the list is how you move between them, and a view
/// that also scrolls through the whole document would fight it.
struct SourcePDFPage: UIViewRepresentable {
    let url: URL
    let page: Int

    func makeUIView(context: Context) -> IdeaPDFView {
        let view = IdeaPDFView()
        view.onSaveSelection = IdeaPDFView.saver(context.environment.ideaPassage)
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        go(view)
        return view
    }

    func updateUIView(_ view: IdeaPDFView, context: Context) {
        view.onSaveSelection = IdeaPDFView.saver(context.environment.ideaPassage)
        if view.document == nil { view.document = PDFDocument(url: url) }
        go(view)
    }

    /// Page numbers here are the ones a person reads, starting at one; PDFKit
    /// counts from zero, and the off-by-one shows a student the wrong slide.
    private func go(_ view: PDFView) {
        guard let document = view.document else { return }
        let index = min(max(page - 1, 0), max(document.pageCount - 1, 0))
        guard let destination = document.page(at: index) else { return }
        if view.currentPage != destination { view.go(to: destination) }
    }
}
